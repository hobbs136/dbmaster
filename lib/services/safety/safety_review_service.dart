//! SQL 安全审查 — 引擎（ADR-0003 Part A）。
//!
//! [SafetyReviewService] 遍历所有启用的 [SafetyRule]，聚合 findings，
//! 按严重度降序排序。任何规则抛异常 → 该规则静默跳过（不阻断审查），
//! 这保证了审查失败不破坏用户的执行流程。
//!
//! T13（D2 决策，2026-08-20 拍板）：降级语义从纯 fail-open 改为
//! **仅写类 fail-closed**——规则异常时若语句是写类，注入
//! `review_degraded_fail_closed`（high）finding 交给执行门；读类维持
//! 静默跳过（不骚扰）。该 finding 是引擎注入的告警，不是 SafetyRule
//! 产出（B1 开关接线归后续任务）。

import '../../models/sql_statement.dart' show SQLType;
import '../../utils/app_logger.dart';
import '../sql_parser_service.dart' show SQLParserService;
import 'safety_finding.dart';
import 'safety_rule.dart';

/// 安全审查引擎。构造时传入规则列表（编译时固定，MVP 不做运行时注册）。
///
/// 使用方式：
/// ```dart
/// final service = SafetyReviewService([
///   SchemaCompatRule(),
///   MissingLimitRule(),
/// ]);
/// final findings = await service.review(sql, context);
/// ```
class SafetyReviewService {
  final List<SafetyRule> _rules;

  /// T13 · D2 fail-closed 总开关（B1 `reviewFailClosedEnabled` 注入）。
  /// false 时规则异常对写类也只记日志（回到纯 fail-open，供用户关闭）。
  final bool failClosedForWrites;

  SafetyReviewService(this._rules, {this.failClosedForWrites = true});

  /// 审查一条 SQL，返回所有 findings（按严重度降序：high → medium → low）。
  ///
  /// 任何规则抛异常 → 该规则静默跳过（记日志），其他规则照常执行。
  /// 这保证审查引擎的健壮性——一条坏规则不破坏整体审查。
  /// 例外（T13 · D2 fail-closed）：语句为写类时，规则异常额外注入
  /// `review_degraded_fail_closed`（high）finding 走执行门。
  Future<List<SafetyFinding>> review(String sql, SafetyContext context) async {
    final allFindings = <SafetyFinding>[];
    for (final rule in _rules) {
      try {
        final findings = await rule.check(sql, context);
        allFindings.addAll(findings);
      } catch (e) {
        // 静默跳过——审查不能破坏执行流程。
        AppLogger.w(
          'SafetyReview',
          '规则 ${rule.id} 执行异常，已跳过: $e',
        );
        // T13 · D2 fail-closed：审查降级时写类语句无法确认安全性 →
        // 注入 high finding（引擎注入，非规则产出）走执行门让用户
        // 知情决定；读类维持静默跳过（不骚扰）。B1 开关关闭时回退
        // 纯 fail-open（T14 接线）。
        if (failClosedForWrites && isWriteStatement(sql)) {
          allFindings.add(degradedFailClosedFinding());
        }
      }
    }
    // 按严重度降序排序（high → medium → low）。
    allFindings.sort((a, b) => b.severity.index.compareTo(a.severity.index));
    return allFindings;
  }

  /// 审查多条 SQL（脚本），聚合所有 findings。
  ///
  /// 每条语句的 findings 标注 [SafetyFinding.statementIndex]（从 1 开始）。
  /// 用于多语句脚本执行前的批量审查——弹一次窗展示所有语句的问题。
  Future<List<SafetyFinding>> reviewScript(
    List<String> statements,
    SafetyContext context, {
    int explainSelectBudget = 10,
    /// B3：每条语句的起始行号（1-based，相对编辑器全文）。
    /// 传了则给 finding 注入 lineStart（用于行级红点）。
    /// null/长度不匹配 → finding.lineStart 保持 0（不画红点，向后兼容）。
    List<int>? statementLineStarts,
  }) async {
    final allFindings = <SafetyFinding>[];
    int selectSeen = 0; // 已 EXPLAIN 的 SELECT 计数（预算控制）。
    for (var i = 0; i < statements.length; i++) {
      final stmt = statements[i];
      // 多语句 EXPLAIN 开销控制（R12）：只对前 explainSelectBudget 条
      // SELECT 注入 EXPLAIN 能力，超限的语句用 getExplainPlan=null 的
      // context（EXPLAIN 规则天然跳过，其它规则不受影响）。
      final isSelect = _isSelectLike(stmt);
      final ctx = (isSelect && selectSeen >= explainSelectBudget)
          ? _contextWithoutExplain(context)
          : context;
      if (isSelect && selectSeen < explainSelectBudget) selectSeen++;
      final findings = await review(stmt, ctx);
      // B3：语句起始行号（来自 SQLStatement.lineStart）。
      final lineStart = (statementLineStarts != null &&
              i < statementLineStarts.length)
          ? statementLineStarts[i]
          : 0;
      // 标注语句序号（从 1 开始，0 = 单语句）。
      for (final f in findings) {
        allFindings.add(SafetyFinding(
          ruleId: f.ruleId,
          severity: f.severity,
          title: f.title,
          description: f.description,
          suggestion: f.suggestion,
          affectedTable: f.affectedTable,
          statementIndex: i + 1,
          lineStart: lineStart,
        ));
      }
    }
    return allFindings;
  }

  /// 判断语句是否为 SELECT/WITH（消耗 EXPLAIN 预算的语句类型）。
  static bool _isSelectLike(String sql) {
    final upper = sql.trimLeft().toUpperCase();
    return upper.startsWith('SELECT') || upper.startsWith('WITH');
  }

  /// 返回一个关闭 EXPLAIN 能力的 context 副本（其它字段不变）。
  /// 用于多语句预算超限后让 EXPLAIN 规则跳过，非 EXPLAIN 规则照常。
  static SafetyContext _contextWithoutExplain(SafetyContext src) {
    return SafetyContext(
      connectionId: src.connectionId,
      database: src.database,
      dbType: src.dbType,
      schemaCache: src.schemaCache,
      getRowCount: src.getRowCount,
      getColumns: src.getColumns,
      getExplainPlan: null,
      explainTimeoutSeconds: src.explainTimeoutSeconds,
    );
  }

  /// 是否有任何 medium/high 级别的 finding（决定是否弹窗）。
  ///
  /// low 级别的 findings 静默通过（不弹窗），只在状态栏/审计中记录。
  static bool shouldShowDialog(List<SafetyFinding> findings) {
    return findings.any((f) =>
        f.severity == Severity.medium || f.severity == Severity.high);
  }

  /// T13 · D2：判定单条 SQL 是否为写类（fail-closed 适用范围）。
  ///
  /// 写类 = [SQLType.insert] / [SQLType.update] / [SQLType.delete] /
  /// [SQLType.ddl] / [SQLType.call]。call（CALL/EXEC 存储过程）按写处理：
  /// 过程体内可包含任意写操作，无法静态确认其影响，从严归类。
  /// select / other 为读类——降级时维持静默跳过，不骚扰。
  static bool isWriteStatement(String sql) {
    switch (SQLParserService.detectType(sql)) {
      case SQLType.insert:
      case SQLType.update:
      case SQLType.delete:
      case SQLType.ddl:
      case SQLType.call:
        return true;
      case SQLType.select:
      case SQLType.other:
        return false;
    }
  }

  /// T13 · D2：判定一段（可能多语句的）SQL 文本是否包含写类语句。
  ///
  /// 供编辑器执行门的整体异常 catch 使用（那里拿到的是编辑器全文）。
  /// best-effort：逐条 split 判定；split 本身异常（如解析 bug）时退化
  /// 为整段 [isWriteStatement]（首关键词判定），宁可从严不漏写。
  static bool containsWriteStatement(String sql) {
    try {
      final statements = SQLParserService.split(sql);
      if (statements.isNotEmpty) {
        return statements.any((s) => isWriteStatement(s.sql));
      }
    } catch (e) {
      AppLogger.w(
        'SafetyReview',
        'fail-closed 写类判定解析异常，退化为整段判定: $e',
      );
    }
    return isWriteStatement(sql);
  }

  /// T13 · D2：构造「审查降级 fail-closed」告警 finding（引擎注入）。
  ///
  /// ruleId 固定为 `review_degraded_fail_closed`（roadmap §2.3 最后一行），
  /// 但它**不是 SafetyRule**——规则开关/注册体系（B1）不收录引擎注入的
  /// 告警。写类 SQL 在审查降级（规则异常 / 审查整体异常）时注入本
  /// finding，由执行门呈现给用户知情决定（high 语义 = 弹窗置顶、建议
  /// 修正或知情继续，非硬阻断）。
  static SafetyFinding degradedFailClosedFinding() {
    return const SafetyFinding(
      ruleId: 'review_degraded_fail_closed',
      severity: Severity.high,
      title: '安全审查降级，无法确认该写操作的安全性',
      description: '安全审查在降级状态下运行（规则执行或解析异常），'
          '无法确认该写操作的安全性。请确认 SQL 的来源与影响范围，'
          '知情后再决定是否继续执行。',
    );
  }
}
