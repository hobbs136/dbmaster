/// Agent 门判定（tasks-ai-agent.md T06 / design-ai-agent.md §4.2、D3、D6、
/// D12、D15）。
///
/// 单一判定点（D3）：所有 tool_call 的权限判定必经 [AgentGate.evaluate]，
/// 判定序固定 ①-⑤（**顺序不可换**，审计按此落）：
///
/// 1. ① 目录查找——spec 名不在目录全集内 → `reject(UNKNOWN_TOOL)`
///    （AC1.6/AC7.3）。后续判定一律以**目录权威 spec** 为准（防伪造
///    档位/类别绕门）；milestone 可寻址锁在 dispatch 侧
///    （`AgentToolCatalog.find`，T04），与全集判存分立——A1 期计划/界面
///    工具经 find 不可寻址（evaluate 不可达），但注入全集 spec 可完整
///    测试 l1/suggest 分支（FC-5）；
/// 2. ②a `requiresConnection` 且快照无连接 → `reject(CONTEXT_REQUIRED)`
///    （AC7.4 引导态）；
/// 3. ②b（T2 方案 B / FU-10 收口）[agentToolRequiresDatabaseContext]——
///    USE 语义族 `requiresDatabase` 工具 × 快照无库（db-less 是硬错误态，
///    3D000 类）→ `reject(CONTEXT_REQUIRED)`（run 立即终止，不给模型用
///    information_schema / 系统库绕行的机会）；豁免族（SQLite / PG / SS /
///    Mongo / Redis）不受拦；
/// 4. ③ readOnly 连接 × 写形态动作（plan 类工具）→
///    `reject(READONLY_CONNECTION)`（NF2.3；数据/界面工具不受限）；
/// 5. ④ 档判定——`l0` 数据读取（`execute_readonly_sql` / `get_sample_data`，
///    design §4.1 表「升 L0.5」标注的两个工具）→ 读前分析（T05 内核，
///    含 X1/X2 豁免与 fail-closed）→ 任一信号残存 `confirm(l05)` / 全消
///    `allow`；其余 `l0`（元数据/上下文/界面类）→ `allow`；`plan (l1)` →
///    `confirm(l1)`；`suggest` → `allow`（派发为建议卡，用户点击才是执行）；
/// 6. ⑤ 会话放行短路（D12）——`confirm(l05)` 候选且账本命中该连接 →
///    `allow`。审计判据 `allowed_session`：`kind == allow && level == l05`
///    ——本分支是该组合在 evaluate 内的**唯一产生源**（干净放行的 level
///    恒为 l0/suggest）。
///
/// **L2 不在 evaluate 出现**（design §4.2 末段）：DDL 双门在执行管线
/// （`DdlConfirmationRequiredException` 既有链），计划执行器逐语句接住
/// （AC10.4）；L1 会话放行同理不在本类（executor 计划链路消费，AC9.3）。
///
/// evaluate 为无状态纯逻辑（依赖全注入，NF5.3 可脱离 UI 单测）。读前分析
/// 经构造注入的工厂函数**每次判定时重新构造**（AC8.7：阈值修改后下次判定
/// 生效；gate 本体不依赖 dbService / QuerySettingsService——那是工厂闭包
/// 的装配职责，T10/T14 接线）。
///
/// 本文件不 import material（组件级 §0 MUST NOT 2）。
library;

import '../../../models/database_models.dart' show DatabaseType;
import 'agent_gate_analysis.dart'
    show AgentGateAnalysis, AgentGateAnalysisResult, ReadImpactAnalysis;
import 'agent_permission_ledger.dart' show AgentPermissionLedger;
import 'agent_tool_catalog.dart'
    show
        AgentGateLevel,
        AgentToolCategory,
        AgentToolCatalog,
        AgentToolErrorCodes,
        AgentToolSpec;

/// run 启动快照（D15，不可变）。`AgentLoopRunner.start` 时从
/// `effectiveWorkbenchContext` 一次性快照写入，运行全程只读该快照——
/// 运行中切换侧栏/tab 读取来源不漂移（AC7.2）；目录无切换连接工具
/// （§4.1 目录即边界，AC7.3）。
class AgentRunContext {
  const AgentRunContext({
    required this.runId,
    required this.dbType,
    required this.readOnly,
    this.connectionId,
    this.connectionName,
    this.databaseName,
  });

  final String runId;

  /// null = 无上下文（AC7.4 引导态；空串同视为无上下文——对齐 T07 审计的
  /// 空串占位语义）。
  final String? connectionId;

  final String? connectionName;

  final String? databaseName;

  final DatabaseType dbType;

  /// 连接属性 → 锁档数据源（NF2.3）。由快照构造侧从连接属性写入
  /// （`readOnly=true` 是构造侧语义）；evaluate 只消费快照，不实时解析。
  final bool readOnly;
}

/// 门判定三态（design §4.2 枚举原文）。
enum GateDecisionKind { allow, confirm, reject }

/// 单次门判定结果（design §4.2 代码块原文，字段一字不改）。
class GateDecision {
  const GateDecision({
    required this.kind,
    required this.level,
    this.reasonCode,
    this.impact,
  });

  final GateDecisionKind kind;

  /// 触发档（confirm/reject 时有意义）。约定：reject/confirm 用工具声明档
  /// 或判定档（l05）；UNKNOWN_TOOL 无声明档可引 → l0 占位；allow 用声明档
  /// （l0/suggest），唯一例外 = ⑤ 会话放行短路的 allow@l05（见类注释）。
  final AgentGateLevel level;

  /// reject 的错误码（§4.1 全集）；allow/confirm 为 null。
  final String? reasonCode;

  /// L0.5 确认卡数据（AC8.4）；仅 `confirm(l05)` 携带（确认卡唯一消费面），
  /// 其余判定为 null。
  final ReadImpactAnalysis? impact;
}

/// T2 方案 B 方言谓词（gate ②b 与 executor fail-closed 防御的**同一事实源**，
/// 禁两份实现）：USE 语义族下 `requiresDatabase` 工具在 db-less 快照上是
/// **硬错误态**（3D000「No database selected」类）——db-less 时执行必然报错
/// 或静默返回空表/空列，故在门处直接 `CONTEXT_REQUIRED` 终止（FU-10：
/// 错误不静默 → 升级为立即终止）。
///
/// 豁免族（连接语义合法或恒有当前库，行为同现状）：
/// - SQLite：无选库概念（本地文件库）；
/// - PostgreSQL / SQL Server：连接恒绑定当前库（PG `database` 参数路由 /
///   SS 连接串初始目录），无「未选库」态；
/// - MongoDB / Redis：连接级语义合法，无库概念。
bool agentToolRequiresDatabaseContext(
  AgentToolSpec spec,
  AgentRunContext runCtx,
) {
  if (!spec.requiresDatabase) return false;
  if (!_useSemanticsDialects.contains(runCtx.dbType)) return false;
  final String? databaseName = runCtx.databaseName;
  return databaseName == null || databaseName.isEmpty;
}

/// USE 语义族：db-less = 硬错误态的 SQL 类方言。豁免族见
/// [agentToolRequiresDatabaseContext]（sqlite / postgresql / sqlserver /
/// mongodb / redis 不在此族）。
const Set<DatabaseType> _useSemanticsDialects = <DatabaseType>{
  DatabaseType.mysql,
  DatabaseType.doris,
  DatabaseType.oceanbase,
  DatabaseType.tidb,
  DatabaseType.starrocks,
  DatabaseType.mariadb,
  DatabaseType.clickhouse,
  DatabaseType.tdengine,
};

/// Agent 门：判定序 ①-⑤ 的唯一实现（D3 单一判定点）。无状态纯逻辑，
/// 依赖全注入——读前分析经 [createAnalysis] 工厂每次判定时构造（AC8.7）。
class AgentGate {
  /// 目录全集判存用的里程碑上界：声明值域 1|2|3（D20），A3 无新工具 →
  /// 3 即全集。区别于 dispatch 侧 `AgentToolCatalog.find` 的 activeMilestone
  /// 可寻址锁（T04/A1=1）。
  static const int _fullCatalogMilestone = 3;

  /// get_sample_data 的 LIMIT clamp 区间与默认值（design §4.1 表口径：
  /// n clamp 1-100，默认 10）。T10 executor 执行同形 SQL——两处需一致。
  static const int _sampleLimitMin = 1;
  static const int _sampleLimitMax = 100;
  static const int _sampleLimitDefault = 10;

  /// 读前分析工厂：入参为本次 run 快照（工厂按 runCtx.dbType 绑定方言、
  /// 按 runCtx.connectionId 绑定取数，阈值读当前配置）——gate 借此脱离
  /// dbService 单测（NF5.3），且每次判定重新构造保证阈值即时生效（AC8.7）。
  final AgentGateAnalysis Function(AgentRunContext runCtx) _createAnalysis;

  /// [createAnalysis] 为「dbService 经接口」的注入点（design §4.2 类注）：
  /// 生产装配（T10/T14）闭包内绑 `dbService.getExplainPlan` +
  /// `QuerySettingsService().getAgentL05RowThreshold()`。
  AgentGate({
    required AgentGateAnalysis Function(AgentRunContext runCtx) createAnalysis,
  }) : _createAnalysis = createAnalysis;

  /// 判定一次工具调用（判定序见类注释①-⑤；审计按此序落，D3）。
  ///
  /// [args] 不做参数校验——缺失/类型不符是 executor（T10）handler 侧
  /// `INVALID_ARGUMENTS` 的职责；缺形参数无执行风险，门按声明档放行。
  Future<GateDecision> evaluate({
    required AgentToolSpec spec,
    required Map<String, dynamic> args,
    required AgentRunContext runCtx,
    required AgentPermissionLedger ledger,
  }) async {
    // ① 目录查找（UNKNOWN_TOOL）：全集判存 + 目录权威 spec 覆盖入参
    //（防伪造档位/类别绕门；milestone 可寻址锁在 dispatch 侧 find）。
    final AgentToolSpec? catalogSpec = _lookupInCatalog(spec.name);
    if (catalogSpec == null) {
      return const GateDecision(
        kind: GateDecisionKind.reject,
        level: AgentGateLevel.l0,
        reasonCode: AgentToolErrorCodes.unknownTool,
      );
    }

    // ②a requiresConnection 且快照无连接 → CONTEXT_REQUIRED（AC7.4）。
    final String? connectionId = runCtx.connectionId;
    if (catalogSpec.requiresConnection &&
        (connectionId == null || connectionId.isEmpty)) {
      return GateDecision(
        kind: GateDecisionKind.reject,
        level: catalogSpec.gateLevel,
        reasonCode: AgentToolErrorCodes.contextRequired,
      );
    }

    // ②b（T2 方案 B / FU-10 收口）：USE 语义族 requiresDatabase × 快照无库
    // → CONTEXT_REQUIRED（db-less 是硬错误态，3D000 类）。豁免族见
    // [agentToolRequiresDatabaseContext]。
    if (agentToolRequiresDatabaseContext(catalogSpec, runCtx)) {
      return GateDecision(
        kind: GateDecisionKind.reject,
        level: catalogSpec.gateLevel,
        reasonCode: AgentToolErrorCodes.contextRequired,
      );
    }

    // ③ readOnly 连接 × 写形态动作（plan 类）→ READONLY_CONNECTION
    //（NF2.3；数据/界面工具不受限）。readOnly 由快照携带（构造侧语义）。
    if (runCtx.readOnly && catalogSpec.category == AgentToolCategory.plan) {
      return GateDecision(
        kind: GateDecisionKind.reject,
        level: catalogSpec.gateLevel,
        reasonCode: AgentToolErrorCodes.readonlyConnection,
      );
    }

    // ④ 档判定。L2 不在 evaluate 出现（design §4.2 末段：DDL 双门在执行
    // 管线）；l05 非声明档（l0 的运行时升档，在 _evaluateL0 内产生）。
    switch (catalogSpec.gateLevel) {
      case AgentGateLevel.l0:
        return _evaluateL0(catalogSpec, args, runCtx, ledger);
      case AgentGateLevel.l1:
        return const GateDecision(
          kind: GateDecisionKind.confirm,
          level: AgentGateLevel.l1,
        );
      case AgentGateLevel.suggest:
        return const GateDecision(
          kind: GateDecisionKind.allow,
          level: AgentGateLevel.suggest,
        );
      default:
        // 结构不可达：目录无 l05/l2 声明档工具（l05 是运行时升档、l2 按
        // 设计不在 evaluate）。若未来目录误声明这两档，fail-loud 好过
        // 权限面静默误判——这是不变式守卫，非生产路径。
        throw StateError(
          'AgentGate.evaluate: no branch for declared gate level '
          '${catalogSpec.gateLevel.name} (tool ${catalogSpec.name}); l05 is '
          'runtime-escalated only and l2 lives in the execution pipeline '
          '(design §4.2)',
        );
    }
  }

  /// ④-l0：数据读取工具的读前分析判定（D6/T05），含 ⑤ 会话放行短路。
  Future<GateDecision> _evaluateL0(
    AgentToolSpec spec,
    Map<String, dynamic> args,
    AgentRunContext runCtx,
    AgentPermissionLedger ledger,
  ) async {
    final String? analysisSql = _analysisSqlFor(spec, args);
    if (analysisSql == null) {
      // 元数据/上下文/界面类 l0 工具（design §4.1 表：仅两个数据读取工具
      // 标注「升 L0.5」）或参数缺形（executor 侧 INVALID_ARGUMENTS 拦截，
      // 无执行风险）→ 直接放行。
      return const GateDecision(
        kind: GateDecisionKind.allow,
        level: AgentGateLevel.l0,
      );
    }

    // 读前分析（豁免先行、fail-closed 均在 T05 内核）：每次判定经工厂
    // 重新构造（AC8.7）。analyze 永不抛出（T05 契约）。
    final AgentGateAnalysis analysis = _createAnalysis(runCtx);
    final AgentGateAnalysisResult result = await analysis.analyze(
      sql: analysisSql,
      connectionId: runCtx.connectionId ?? '',
    );
    if (!result.requiresConfirmation) {
      return const GateDecision(
        kind: GateDecisionKind.allow,
        level: AgentGateLevel.l0,
      );
    }

    // ⑤ 会话放行短路（D12）：confirm(l05) 候选且该连接已获 L0.5 会话放行
    // → allow。审计判据 allowed_session = kind==allow && level==l05，
    // 本分支是唯一产生源（见类注释⑤）。
    if (ledger.l05Allowed.contains(runCtx.connectionId)) {
      return const GateDecision(
        kind: GateDecisionKind.allow,
        level: AgentGateLevel.l05,
      );
    }
    return GateDecision(
      kind: GateDecisionKind.confirm,
      level: AgentGateLevel.l05,
      impact: result.impact,
    );
  }

  /// 读前分析覆盖面（design §4.1 表「升 L0.5」标注的两个数据读取工具）：
  /// - `execute_readonly_sql`：分析 args['sql'] 原文；
  /// - `get_sample_data`：按 args 构造 `SELECT * FROM <table> LIMIT n`
  ///   （n 归一化同执行侧口径）；
  /// - 其余 l0 工具（list_tables / describe_table / explain_plan /
  ///   get_current_context 与 A2 界面类）无分析面 → null。
  /// 参数缺形/类型不符 → null（放行，executor 侧拦截）。
  String? _analysisSqlFor(AgentToolSpec spec, Map<String, dynamic> args) {
    switch (spec.name) {
      case 'execute_readonly_sql':
        final dynamic sql = args['sql'];
        return sql is String && sql.trim().isNotEmpty ? sql : null;
      case 'get_sample_data':
        final dynamic table = args['table'];
        if (table is String && table.trim().isNotEmpty) {
          return 'SELECT * FROM $table LIMIT ${_sampleLimit(args)}';
        }
        return null;
      default:
        return null;
    }
  }

  /// get_sample_data 的 LIMIT n 归一化：clamp 1-100、默认 10；宽容 num 与
  /// 数字字符串（LLM 参数经 JSON 往返），解析不出用默认。
  int _sampleLimit(Map<String, dynamic> args) {
    final dynamic raw = args['limit'];
    int? limit;
    if (raw is int) {
      limit = raw;
    } else if (raw is num) {
      limit = raw.toInt();
    } else if (raw is String) {
      limit = int.tryParse(raw.trim());
    }
    if (limit == null) return _sampleLimitDefault;
    if (limit < _sampleLimitMin) return _sampleLimitMin;
    if (limit > _sampleLimitMax) return _sampleLimitMax;
    return limit;
  }

  /// ① 目录全集判存：按名在 14 工具全集内查找（存在性 ≠ 可寻址性）。
  static AgentToolSpec? _lookupInCatalog(String name) {
    for (final AgentToolSpec candidate in AgentToolCatalog.specsFor(
      milestone: _fullCatalogMilestone,
    )) {
      if (candidate.name == name) return candidate;
    }
    return null;
  }
}
