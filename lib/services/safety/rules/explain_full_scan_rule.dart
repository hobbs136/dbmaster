//! 安全审查规则 R9（Pro）：基于 EXPLAIN 执行计划的全表扫描检测。
//!
//! 对 SELECT 执行 EXPLAIN，检测优化器实际选择的全表扫描。
//! 区别于第二阶段 FullTableScanRule（静态启发），这是实证检测——
//! 基于优化器对索引/数据分布的实际决策。
//!
//! 用 scanType.isInefficient（fullTable/fullIndex/seqScan）判定，
//! 覆盖 MySQL（ALL）+ PostgreSQL（Seq Scan）+ 全索引扫描。
//!
//! 绕开孤儿 ExplainPreflightService（死代码 + 类型签名错配），
//! 直接调 ExplainParser.parse。

import 'dart:async';
import 'dart:math';

import '../../../models/sql_statement.dart' show SQLType;
import '../../query_optimizer/explain_parser.dart';
import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

/// Pro 规则 R9：基于 EXPLAIN 的全表扫描检测。
///
/// 纯实证——调 EXPLAIN 拿真实计划。小表（< 阈值）的全表扫不报
/// （优化器对小表故意全表扫是正常决策）。超时/失败静默跳过。
/// LIMIT（无 ORDER BY）把实际扫描截断到 ≈ min(估值, n)，按有效
/// 行数做阈值判定，避免「大表 + 小 LIMIT」误报。
class ExplainFullScanRule implements SafetyRule {
  @override
  final String id = 'explain_full_scan';

  /// 全表扫描行数阈值。预估行数 < 此值的全表扫不报。
  final int rowThreshold;

  ExplainFullScanRule({this.rowThreshold = 10000});

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      // 依赖 EXPLAIN 能力，未注入则跳过。
      final getExplain = context.getExplainPlan;
      if (getExplain == null) return [];

      // 只检查 SELECT/WITH（DML/DDL 不走此规则，控制开销）。
      final type = SQLParserService.detectType(sql);
      if (type != SQLType.select) {
        // WITH (CTE) 也算查询——detectType 可能不识别 WITH，补查前缀。
        final upper = sql.trimLeft().toUpperCase();
        if (!upper.startsWith('WITH')) return [];
      }

      // 整查询聚合（COUNT/SUM… 无 GROUP BY）：全表/全索引扫描就是统计
      // 语义本身，不是优化缺陷 → 无 WHERE 时直接跳过（也省一次 EXPLAIN
      // 往返）。带 WHERE 的聚合（如 COUNT(*) WHERE 无索引列）慢扫有
      // 诊断价值，维持检查。
      if (SQLParserService.isSingleRowAggregate(sql) &&
          !SQLParserService.hasWhereClause(sql)) {
        return [];
      }

      // 执行 EXPLAIN（带超时）。getExplainPlan 实现自己加 EXPLAIN 前缀，
      // 这里传原始 SQL（不加前缀，避免 EXPLAIN EXPLAIN 双重前缀）。
      final explainFuture = getExplain(sql);
      if (explainFuture == null) return [];
      final rawRows = await explainFuture
          .timeout(Duration(seconds: context.explainTimeoutSeconds));
      if (rawRows.isEmpty) return [];

      // 解析执行计划。
      final plan = ExplainParser.parse(
        rawResults: rawRows,
        databaseType: context.dbType.name,
        originalQuery: sql,
      );
      if (plan.steps.isEmpty) return [];

      // 检测低效扫描步（fullTable/fullIndex/seqScan）。
      final inefficientSteps = plan.steps
          .where((s) => s.scanType?.isInefficient ?? false)
          .toList();
      if (inefficientSteps.isEmpty) return [];

      // 小表全表扫不报（优化器对 < 阈值的表故意全表扫是正常的）。
      // LIMIT（无 ORDER BY）截断扫描：优化器读到 LIMIT n 行即停，实际
      // 扫描 ≈ min(估值, n)，按原始估值会对「大表 + 小 LIMIT」误报。
      // ORDER BY + LIMIT 不受此豁免——无可用索引时仍需全表扫 + filesort。
      final limitValue = SQLParserService.extractLimitValue(sql);
      final limitBounded =
          limitValue != null && !SQLParserService.hasOrderClause(sql);
      final effectiveRows =
          limitBounded ? min(plan.totalRows, limitValue) : plan.totalRows;
      if (effectiveRows < rowThreshold) return [];

      // 找到第一个全表扫的表名（用于 finding 上下文）。
      final table = inefficientSteps.first.table ?? '未知表';
      final scanName = inefficientSteps.first.scanType?.displayName ?? '全表扫描';
      return [
        SafetyFinding(
          ruleId: id,
          severity: Severity.medium,
          title: 'EXPLAIN 显示全表扫描（$table · 预估 ${_formatRows(effectiveRows)} 行）',
          description: '优化器对该表选择了 $scanName。'
              '这通常意味着缺少可用索引，或查询条件无法利用现有索引。',
          affectedTable: table,
        ),
      ];
    } on TimeoutException {
      return []; // EXPLAIN 超时 → 静默跳过
    } catch (_) {
      return []; // EXPLAIN 失败 → 静默跳过
    }
  }

  /// 格式化行数（500000 → "500,000"）。
  String _formatRows(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
}
