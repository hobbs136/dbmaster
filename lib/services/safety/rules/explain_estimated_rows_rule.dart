//! 安全审查规则 R10（Pro）：基于 EXPLAIN 预估的大结果集预警。
//!
//! 对 SELECT 执行 EXPLAIN，预估返回行数 ≥ 阈值时警告。
//! 区别于 MissingLimit（基于实际表行数），这是基于优化器对查询
//! 结果集的预估——能反映 WHERE 过滤后的真实规模。
//! 已有 LIMIT 的查询按 min(估值, LIMIT) 判定（EXPLAIN 估值不含
//! LIMIT 截断）；建议对已有 LIMIT 原地替换值，不重复追加。
//!
//! 绕开孤儿 ExplainPreflightService，直接调 ExplainParser.parse。

import 'dart:async';
import 'dart:math';

import '../../../models/sql_statement.dart' show SQLType;
import '../../query_optimizer/explain_parser.dart';
import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

/// Pro 规则 R10：基于 EXPLAIN 预估的大结果集预警。
class ExplainEstimatedRowsRule implements SafetyRule {
  @override
  final String id = 'explain_estimated_rows';

  /// 大结果集行数阈值。预估总行数 ≥ 此值 → 警告。
  final int rowThreshold;

  /// 建议 SQL 中附加的 LIMIT 值。
  final int suggestedLimit;

  ExplainEstimatedRowsRule({
    this.rowThreshold = 100000,
    this.suggestedLimit = 1000,
  });

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      final getExplain = context.getExplainPlan;
      if (getExplain == null) return [];

      // 只检查 SELECT/WITH（控制开销）。
      final type = SQLParserService.detectType(sql);
      if (type != SQLType.select) {
        final upper = sql.trimLeft().toUpperCase();
        if (!upper.startsWith('WITH')) return [];
      }

      // 整查询聚合（COUNT/SUM… 无 GROUP BY）恒返回单行，EXPLAIN 的扫描
      // 估值不代表返回行数 → 跳过。放在 EXPLAIN 调用之前，大表统计
      // 查询不再付一次 EXPLAIN 往返、也不再误报「预估返回 X 行」。
      if (SQLParserService.isSingleRowAggregate(sql)) return [];

      // getExplainPlan 实现自己加 EXPLAIN 前缀，这里传原始 SQL（避免双重前缀）。
      final explainFuture = getExplain(sql);
      if (explainFuture == null) return [];
      final rawRows = await explainFuture
          .timeout(Duration(seconds: context.explainTimeoutSeconds));
      if (rawRows.isEmpty) return [];

      final plan = ExplainParser.parse(
        rawResults: rawRows,
        databaseType: context.dbType.name,
        originalQuery: sql,
      );
      // LIMIT 把实际返回行数封顶为 min(优化器估值, LIMIT n)——MySQL 的
      // EXPLAIN 估值不含 LIMIT 截断，已有小 LIMIT 的查询按原始估值会误报。
      final limitValue = SQLParserService.extractLimitValue(sql);
      final effectiveRows =
          limitValue != null ? min(plan.totalRows, limitValue) : plan.totalRows;
      if (effectiveRows < rowThreshold) return [];

      // 建议 SQL：无 LIMIT → 末尾追加；已有 LIMIT（≥ 阈值才会走到这里）→
      // 原地替换 LIMIT 值（追加会产生 `LIMIT a LIMIT b` 非法 SQL）。
      final trimmed = sql.trim();
      final hasSemicolon = trimmed.endsWith(';');
      final base = hasSemicolon
          ? trimmed.substring(0, trimmed.length - 1)
          : trimmed;
      final suggestion = limitValue == null
          ? '$base LIMIT $suggestedLimit'
          : base.replaceAll(
              RegExp(r'\bLIMIT\s+\d+(?:\s*,\s*\d+)?', caseSensitive: false),
              'LIMIT $suggestedLimit',
            );

      // 已有 LIMIT 时说明阈值是被大 LIMIT 值顶破的，措辞相应调整。
      final description = limitValue != null
          ? '该 SQL 已含 LIMIT ${_formatRows(limitValue)}，'
              '实际返回不超过 ${_formatRows(limitValue)} 行。'
              '若需进一步收窄，可添加 WHERE 条件或调低 LIMIT 值。'
          : 'EXPLAIN 显示此查询可能返回大量行。'
              '考虑添加 WHERE 条件收窄范围或附加 LIMIT。';

      return [
        SafetyFinding(
          ruleId: id,
          severity: Severity.medium,
          title: '查询预估返回 ${_formatRows(effectiveRows)} 行',
          description: description,
          suggestion: suggestion,
        ),
      ];
    } on TimeoutException {
      return [];
    } catch (_) {
      return [];
    }
  }

  String _formatRows(int n) => n.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
}
