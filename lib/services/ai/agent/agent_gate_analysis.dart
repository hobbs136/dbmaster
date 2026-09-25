/// Agent L0.5 门判定内核：读前分析（tasks-ai-agent.md T05 / design §4.2、
/// §6.2、§8、D6 裁决②）。
///
/// L0.5 门的全部技术载体（R8 各 AC）：读前分析强制、X1/X2 窄豁免（§8，
/// 2026-09-23 已追认生效）、fail-closed（AC8.6）。本类是**判定逻辑**，
/// 不做确认卡 UI（T12）与门编排（T06）。
///
/// 判定链（D6）：
/// 1. 非 SELECT/WITH 语句与两规则范围一致地跳过 EXPLAIN 分析（只读合法性
///    由消费方先行保证——T10 的 ReadonlySqlValidator，本模块不重复判）；
/// 2. EXPLAIN 预检（fail-closed 包装）：注入的取数函数抛不支持/超时，或
///    返回空计划/解析不出计划步 → `analysisUnavailable = true`，直接判
///    需确认，**不进规则**（AC8.6；区别于编辑器 SafetyReviewService 的
///    fail-open 静默跳过，`safety_review_service.dart:50-64`）；
/// 3. R9/R10 规则**直接实例化**判定（复用规则本体，阈值经构造参数注入
///    agent 专属值——沿 `dml_risk_models.dart` 的 `fullScanRowThreshold`
///    统一喂法；数值来源 = `QuerySettingsService.agentL05RowThreshold`
///    默认 10,000，**独立于编辑器** `SafetyConfig.fullScanRowThreshold`
///    100,000，分立是有意设计，D6）；
/// 4. 信号映射：`explain_full_scan` finding（R9）= 扫描形态信号（可被
///    豁免消解）；`explain_estimated_rows` finding（R10）= 结果集规模
///    信号（**不参与豁免**，独立成立仍命中，§8 联动）；
/// 5. X1/X2 豁免检查（判定序在规则命中之后；失效条件逐字落 §8）；
/// 6. 任一信号残存 → `requiresConfirmation = true`。
///
/// ⚠️ 双接线点（design 风险 5）：R9/R10 规则本体与编辑器引擎共享——编辑器
/// 侧经 `SafetyReviewService` 构造（其规则测试在
/// `test/services/safety/rules/explain_*_rule_test.dart`），本文件是第二
/// 接线点。规则自身演化时两侧需同步（阈值分立**不是**漂移，是有意设计）。
///
/// 阈值每次判定时读配置构造（AC8.7：修改后下次判定生效；构造轻量）。EXPLAIN
/// 取数在单次 [analyze] 内共享同一次结果（两规则原本各自发起一次 EXPLAIN，
/// 不共享会放大为 3 次库往返）；缓存不跨调用——阈值即时生效由每次判定
/// 重新构造保证。
///
/// 本文件为纯逻辑（依赖全注入，NF5.3 可脱离 UI 单测）：services 层禁
/// import material（组件级 §0 MUST NOT 2）。
library;

import 'dart:async';

import '../../../models/database_models.dart' show DatabaseType;
import '../../../models/sql_statement.dart' show SQLType;
import '../../query_optimizer/explain_parser.dart' show ExplainParser;
import '../../safety/rules/explain_estimated_rows_rule.dart'
    show ExplainEstimatedRowsRule;
import '../../safety/rules/explain_full_scan_rule.dart'
    show ExplainFullScanRule;
import '../../safety/safety_finding.dart' show SafetyFinding;
import '../../safety/safety_rule.dart' show SafetyContext;
import '../../sql_parser_service.dart' show SQLParserService;
import '../../../models/query_optimizer/execution_plan.dart'
    show ExecutionPlan, PlanStep, ScanType;

/// 读前分析产物（design §4.2 字段原文，一字不改；进确认卡与轨迹）。
///
/// 归属裁决（§6 计划期发现 #4）：类型定义落本文件（产出方），
/// `agent_gate.dart`（T06）导入消费。
class ReadImpactAnalysis {
  const ReadImpactAnalysis({
    required this.estimatedRows,
    required this.fullScan,
    this.scannedTables = const <String>[],
    this.indexSummary,
    required this.analysisUnavailable,
  });

  /// EXPLAIN 估算（null = 分析不可用 → fail-closed，AC8.6）。
  final int? estimatedRows;

  /// 无可用索引/全表扫描信号（R9 规则 finding）。
  final bool fullScan;

  /// 扫描涉及的表（计划步提取；PG `using <idx>` 形态可能取不到表名 → 空）。
  final List<String> scannedTables;

  /// 命中/缺失描述（确认卡「索引缺失情况」）。维持自由文本——结构化
  /// （hit/missing 列表）的收益不抵规则产出重排成本（design §4.2 注；
  /// ui 规格 §9-A5 纯文本降级已确认，FC-5 需要时加法升级）。null = 无
  /// 索引信息可述（确认卡隐藏该行）。
  final String? indexSummary;

  /// true → 保守 confirm（AC8.6 fail-closed）。
  final bool analysisUnavailable;
}

/// L0.5 窄豁免形态（design §8；FC-5 加法开关——撤销任一豁免 = 移除对应
/// 分支，判定链其余步骤不动）。
enum AgentL05Exemption {
  /// 未命中豁免（或分析未进行/不可用）。
  none,

  /// X1：主键/唯一键等值点查（单表 + 等值 + EXPLAIN 唯一访问形态）。
  uniqueKeyPointLookup,

  /// X2：小 LIMIT（≤ 200）无 ORDER BY 早停（复用 R9 规则 `limitBounded`
  /// 分支语义）。
  smallLimitEarlyStop,
}

/// 单次 [AgentGateAnalysis.analyze] 的判定结果：命中 L0.5 与否 + 影响面
/// 数据 + 命中的豁免形态。
class AgentGateAnalysisResult {
  const AgentGateAnalysisResult({
    required this.requiresConfirmation,
    required this.impact,
    this.exemption = AgentL05Exemption.none,
  });

  /// 任一信号残存（R9 扫描形态信号未被豁免消解 / R10 结果集规模信号独立
  /// 成立 / 分析不可用 fail-closed）→ true，消费方（T06 门）判
  /// `confirm(l05)`；全消且分析可用 → false，判 `allow`。
  final bool requiresConfirmation;

  /// 读前分析影响面数据（进 L0.5 确认卡与轨迹，AC8.4）。
  final ReadImpactAnalysis impact;

  /// 本条语句命中的 L0.5 豁免形态。即使无信号残存也如实记录——X1 点查
  /// 形态在当前规则体下天然不产 R9 finding（const/eq_ref 访问不属于低效
  /// 扫描），记录豁免命中供 T06 审计与 T12/T13 轨迹呈现「为何未弹卡」。
  final AgentL05Exemption exemption;
}

/// Agent L0.5 读前分析判定内核（T05）。无状态纯逻辑：取数函数、阈值、
/// 方言全部注入，每次判定时由消费方按当前配置构造（AC8.7）。
class AgentGateAnalysis {
  /// EXPLAIN 调用超时秒数（与 [SafetyContext.explainTimeoutSeconds] 默认
  /// 值一致，规则内部的超时口径不变）。
  static const int _explainTimeoutSeconds = 3;

  /// §8 X2：LIMIT 上限（n ≤ 200 才可豁免；n > 200 → 不豁免）。
  static const int x2LimitCeiling = 200;

  final Future<List<Map<String, dynamic>>> Function(String sql) _getExplainPlan;

  /// agent 专属行数阈值（D6：默认 10,000，独立于编辑器 100,000；clamp 由
  /// T02 的 QuerySettingsService 保证，本类不再 clamp）。同时喂 R9/R10 两
  /// 规则（沿编辑器 `fullScanRowThreshold` 统一喂法）。
  final int rowThreshold;

  final DatabaseType _dbType;

  /// R9：基于 EXPLAIN 的全表扫描检测（扫描形态信号源）。
  final ExplainFullScanRule _fullScanRule;

  /// R10：基于 EXPLAIN 预估的大结果集预警（结果集规模信号源，不参与豁免）。
  final ExplainEstimatedRowsRule _estimatedRowsRule;

  AgentGateAnalysis({
    required Future<List<Map<String, dynamic>>> Function(String sql)
    getExplainPlan,
    required this.rowThreshold,
    required DatabaseType dbType,
  }) : _getExplainPlan = getExplainPlan,
       _dbType = dbType,
       _fullScanRule = ExplainFullScanRule(rowThreshold: rowThreshold),
       _estimatedRowsRule = ExplainEstimatedRowsRule(
         rowThreshold: rowThreshold,
       );

  /// 对单条 SQL 做读前分析，产出 L0.5 判定（命中与否 + 影响面 + 豁免）。
  ///
  /// 前置：消费方（T10）已做只读校验（ReadonlySqlValidator 先行）与
  /// NoSQL 方言拦截（`UNSUPPORTED_DIALECT`），本模块不重复判。
  /// [connectionId] 仅用于构造 [SafetyContext]（取数函数已绑定连接）。
  ///
  /// 永不抛出：任何取数/解析异常都收敛为 fail-closed 结果（AC8.6）。
  Future<AgentGateAnalysisResult> analyze({
    required String sql,
    required String connectionId,
  }) async {
    // 与两规则的语句范围一致（规则对非 SELECT/WITH 返回空 findings）：
    // SHOW/DESC 类语句 EXPLAIN 多会失败，跳过分析、不判需确认。
    if (!_isExplainableStatement(sql)) {
      return const AgentGateAnalysisResult(
        requiresConfirmation: false,
        impact: ReadImpactAnalysis(
          estimatedRows: null,
          fullScan: false,
          scannedTables: <String>[],
          indexSummary: null,
          analysisUnavailable: false,
        ),
      );
    }

    // ── EXPLAIN 预检（fail-closed 包装，D6 裁决②；不进规则）──
    final List<Map<String, dynamic>> rawRows;
    try {
      rawRows = await _getExplainPlan(
        sql,
      ).timeout(const Duration(seconds: _explainTimeoutSeconds));
    } catch (_) {
      // 不支持（SQL Server 网关 UnsupportedError）/ 超时 / 连接异常 →
      // 保守 confirm（AC8.6）。敏感信息不入错误面：异常细节不外抛。
      return _failClosed();
    }
    if (rawRows.isEmpty) return _failClosed(); // 空计划 → fail-closed

    final plan = ExplainParser.parse(
      rawResults: rawRows,
      databaseType: _dbType.name,
      originalQuery: sql,
    );
    // 原始行非空但解析不出任何步（如 PG 空行集）＝不可用计划 → fail-closed
    //（§8 X1 失效条件同源：解析不出访问类型 → 不豁免，此处整体更保守）。
    if (plan.steps.isEmpty) return _failClosed();

    // ── R9/R10 规则实例化判定（阈值已注入构造参数）──
    // 单次分析共享同一次 EXPLAIN 取数：两规则各自调用 getExplainPlan，
    // 注入 memoized Future 避免重复库往返（缓存仅限本次调用，见文件头）。
    final memoized = Future.value(rawRows);
    final context = SafetyContext(
      connectionId: connectionId,
      dbType: _dbType,
      getRowCount: (_) async => null,
      getColumns: (_) async => null,
      getExplainPlan: (_) => memoized,
    );
    final findings = <SafetyFinding>[
      ...await _fullScanRule.check(sql, context),
      ...await _estimatedRowsRule.check(sql, context),
    ];

    final bool scanShapeSignal = findings.any(
      (f) => f.ruleId == _fullScanRule.id,
    ); // R9
    final bool largeResultSignal = findings.any(
      (f) => f.ruleId == _estimatedRowsRule.id,
    ); // R10

    // ── X1/X2 豁免检查（§8，判定序在规则命中之后）──
    // X1 优先（更强的形态保证：唯一访问 + 等值点查）；豁免只消解 R9 扫描
    // 形态信号，R10 结果集规模信号独立成立仍命中（§8 联动）。
    var exemption = AgentL05Exemption.none;
    if (_matchesUniquePointLookup(sql, plan)) {
      exemption = AgentL05Exemption.uniqueKeyPointLookup;
    } else if (_matchesSmallLimitEarlyStop(sql, plan)) {
      exemption = AgentL05Exemption.smallLimitEarlyStop;
    }
    final bool scanDissolved =
        scanShapeSignal && exemption != AgentL05Exemption.none;
    final bool requiresConfirmation =
        largeResultSignal || (scanShapeSignal && !scanDissolved);

    return AgentGateAnalysisResult(
      requiresConfirmation: requiresConfirmation,
      impact: ReadImpactAnalysis(
        estimatedRows: plan.totalRows,
        // 如实记录 R9 信号（豁免消解的是判定，不篡改扫描形态事实——
        // 允许路径下该字段不进确认卡，仅供轨迹/审计）。
        fullScan: scanShapeSignal,
        scannedTables: _collectScannedTables(plan, findings),
        indexSummary: _buildIndexSummary(plan),
        analysisUnavailable: false,
      ),
      exemption: exemption,
    );
  }

  /// fail-closed 结果（AC8.6）：分析不可用 → 保守 confirm，不进规则。
  AgentGateAnalysisResult _failClosed() => const AgentGateAnalysisResult(
    requiresConfirmation: true,
    impact: ReadImpactAnalysis(
      estimatedRows: null,
      fullScan: false,
      scannedTables: <String>[],
      indexSummary: null,
      analysisUnavailable: true,
    ),
  );

  /// 语句是否进入 EXPLAIN 分析：SELECT/WITH（与两规则的 detectType + WITH
  /// 前缀兜底口径逐字一致）。
  bool _isExplainableStatement(String sql) {
    if (SQLParserService.detectType(sql) == SQLType.select) return true;
    return sql.trimLeft().toUpperCase().startsWith('WITH');
  }

  /// §8 X1：主键/唯一键等值点查。
  ///
  /// 语义：单表、`WHERE pk_col = 常量`（或唯一索引列等值），且 EXPLAIN
  /// 计划显示唯一访问（MySQL `type=const/eq_ref`；PG 为
  /// `Index Scan using pkey 索引` 且无 Filter 残留）。
  ///
  /// 失效条件（逐字 §8）：非等值（范围/IN 多值/函数包裹列）→ 不豁免；
  /// EXPLAIN 不可用或解析不出访问类型 → 不豁免；复合唯一索引仅命中前缀
  /// → 不豁免。任何不确定 → false（保守回严格档）。
  bool _matchesUniquePointLookup(String sql, ExecutionPlan plan) {
    // 单表：计划中承担表访问的步（scanType 可辨）恰一步——JOIN/子查询会
    // 产生多个访问步（EXPLAIN 对每个被访表/派生表各出一行）；Sort/Limit
    // 等包装节点 scanType 为空或 unknown，不计。
    final accessSteps = _tableAccessSteps(plan);
    if (accessSteps.length != 1) return false;
    final step = accessSteps.first;

    // MySQL 族：const/system/eq_ref 即唯一访问形态。优化器语义保证：
    // const/eq_ref 仅在主键/唯一索引**全键**等值比较时出现——范围（range）、
    // IN 多值（range/ref）、函数包裹列（用不上索引 → ALL）、复合唯一索引
    // 仅命中前缀（ref/range）都会降级访问类型，失效条件三与条件一在访问
    // 类型层面已天然排除。
    switch (step.scanType) {
      case ScanType.const_:
      case ScanType.system:
        return true;
      case ScanType.eqRef:
        // eq_ref 与非常量表/函数结果比较时 ref 非const——要求 ref 含
        // const（单表语句实际不产 eq_ref，此分支为形态完备性保留）。
        final ref = step.ref?.toLowerCase() ?? '';
        return ref.contains('const');
      default:
        break;
    }

    // PostgreSQL：`Index Scan using <pkey 类索引>` 且无 `Filter:` 残留。
    // 条件文本（Index Cond）可能在与访问节点相邻的行上，用整计划文本判断。
    if (_dbType == DatabaseType.postgresql) {
      final text = plan.steps.map((s) => s.extra ?? '').join('\n');
      if (!text.contains('Index Scan')) return false;
      if (text.contains('Filter:')) return false; // Filter 残留 → 不豁免
      // 唯一性可证仅认 pkey 命名族（<table>_pkey）；其它索引名无法从计划
      // 文本证明唯一 → 不豁免（保守）。
      final using = RegExp(r'using\s+(\S+)').firstMatch(text)?.group(1) ?? '';
      if (!using.endsWith('_pkey')) return false;
      // 等值证明：Index Cond 必须是单列 `col = 值` 比较——范围（>=/>）、
      // IN 多值（= ANY (...)，注意 PG 文本中 ANY 与括号间有空格）、复合
      // AND（全键命中也无法从文本证明键长，保守不豁免）、无 Index Cond
      // （解析不出）→ 全部不豁免。
      final cond = RegExp(
        r'Index Cond:\s*\(([^)]*)\)',
      ).firstMatch(text)?.group(1)?.trim();
      if (cond == null || cond.isEmpty) return false;
      final bool singleEquality =
          RegExp(r'^\w+\s*=\s*\S').hasMatch(cond) &&
          !RegExp(r'\bANY\b').hasMatch(cond);
      final bool hasAndOr = RegExp(
        r'\b(AND|OR)\b',
        caseSensitive: false,
      ).hasMatch(cond);
      return singleEquality && !hasAndOr;
    }

    // SQLite 及其它方言：§8 未给判定形态（SQLite 的 autoindex/rowid 点查
    // 无法从计划文本证明唯一性）→ 不豁免（保守回严格档）。
    return false;
  }

  /// §8 X2：小 LIMIT 无 ORDER BY 早停。
  ///
  /// 语义：语句含 `LIMIT n`（n ≤ 200）且无 `ORDER BY`，单表扫描。复用
  /// R9 规则 `limitBounded` 分支语义（`extractLimitValue` + `hasOrderClause`
  /// 同一解析器），不引入规则之外的新判断。
  ///
  /// 失效条件（逐字 §8）：n > 200 / 含 ORDER BY（filesort 需全扫）→ 不
  /// 豁免；`estimatedRows` 超 R10 阈值 → 不豁免（此条不在本函数体现——
  /// R10 信号独立叠加在判定结果上，见 [analyze]）。
  bool _matchesSmallLimitEarlyStop(String sql, ExecutionPlan plan) {
    if (_tableAccessSteps(plan).length != 1) return false; // 单表
    final int? limit = SQLParserService.extractLimitValue(sql);
    if (limit == null || limit > x2LimitCeiling) return false;
    if (SQLParserService.hasOrderClause(sql)) return false;
    return true;
  }

  /// 计划中承担表访问的步（scanType 非空且非 unknown）。MySQL 族每行一个
  /// 访问步；PG 的 Sort/Limit/条件行 scanType 为 unknown 不计。
  List<PlanStep> _tableAccessSteps(ExecutionPlan plan) {
    return plan.steps
        .where((s) => s.scanType != null && s.scanType != ScanType.unknown)
        .toList();
  }

  /// 提取扫描涉及的表名（计划步优先；规则 finding 的 affectedTable 兜底；
  /// 规则的「未知表」占位过滤）。
  List<String> _collectScannedTables(
    ExecutionPlan plan,
    List<SafetyFinding> findings,
  ) {
    final names = <String>{};
    for (final step in plan.steps) {
      final table = step.table;
      if (table != null && table.isNotEmpty) names.add(table);
    }
    if (names.isEmpty) {
      for (final finding in findings) {
        final table = finding.affectedTable;
        if (table != null && table.isNotEmpty && table != '未知表') {
          names.add(table);
        }
      }
    }
    return names.toList()..sort();
  }

  /// 构造 indexSummary 自由文本（技术词汇，非 UI 文案）：
  /// MySQL 族用 key/scanType；PG 从计划文本提取 `using <index>`；无可述
  /// 信息 → null（确认卡隐藏该行）。
  String? _buildIndexSummary(ExecutionPlan plan) {
    final parts = <String>[];
    for (final step in plan.steps) {
      final table = step.table ?? '?';
      final key = step.key;
      if (key != null && key.isNotEmpty) {
        parts.add('$table: $key (${step.scanType?.code ?? 'n/a'})');
      } else if (step.scanType?.isInefficient ?? false) {
        parts.add('$table: no index (${step.scanType?.code ?? 'n/a'})');
      }
    }
    if (parts.isEmpty) {
      for (final step in plan.steps) {
        final match = RegExp(
          r'(?:Index Scan|Index Only Scan)\s+using\s+(\S+)',
        ).firstMatch(step.extra ?? '');
        if (match != null) {
          parts.add('${step.table ?? '?'}: ${match.group(1)}');
        }
      }
    }
    return parts.isEmpty ? null : parts.join('; ');
  }
}
