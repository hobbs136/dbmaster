//! 安全审查规则 R6（Pro）：全表扫描风险检测。
//!
//! 纯静态分析 WHERE 子句，检测两类导致全表扫描的模式：
//! 1. 函数包裹列（YEAR(col) 等）—— 破坏索引使用
//! 2. LIKE 前缀通配（LIKE '%...'）—— 无法走索引
//!
//! 不检测无 WHERE 的 DML——由 DmlSafetyService 管（见 PRD R6 排除说明）。
//! 保守策略：不确定时跳过（不误报）。

import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

/// Pro 规则 R6：全表扫描风险检测。
///
/// 纯静态分析，不查库、不依赖索引元数据。`SafetyContext` 无需扩展。
class FullTableScanRule implements SafetyRule {
  @override
  final String id = 'full_table_scan';

  /// 触发警告的函数名集合（小写）。构造可覆盖以扩展/收窄。
  /// 这些函数作用于列时会使其无法走索引。
  final Set<String> indexBreakingFunctions;

  FullTableScanRule({
    Set<String>? indexBreakingFunctions,
  }) : indexBreakingFunctions =
            indexBreakingFunctions ?? _defaultIndexBreakingFunctions;

  /// 默认索引破坏函数清单。
  /// 聚焦常见的索引破坏场景；可通过构造参数扩展。
  static const _defaultIndexBreakingFunctions = {
    // 日期函数（最常见的索引破坏）。
    'year', 'month', 'day', 'date', 'dayofweek', 'dayofmonth', 'dayofyear',
    'week', 'quarter', 'hour', 'minute', 'second',
    // 字符串函数（大小写转换/截断破坏索引）。
    'lower', 'upper', 'substring', 'substr', 'left', 'right', 'trim',
    'ltrim', 'rtrim', 'reverse',
    // 类型转换。
    'cast', 'convert',
    // 数学函数。
    'abs', 'round', 'ceil', 'floor',
  };

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    try {
      // 只检查有 WHERE 的语句（无 WHERE 的 DML 由 DmlSafetyService 管）。
      final whereClause = SQLParserService.extractWhereClause(sql);
      if (whereClause == null) return [];

      final findings = <SafetyFinding>[];

      // 模式 1：函数包裹列 —— WHERE FN(col) ...
      // 匹配 WHERE 里的函数调用（不分列名/常量，保守：WHERE 里函数调用多数作用于列）。
      for (final fn in indexBreakingFunctions) {
        final pattern = RegExp('\\b$fn\\s*\\(', caseSensitive: false);
        if (pattern.hasMatch(whereClause)) {
          findings.add(SafetyFinding(
            ruleId: id,
            severity: Severity.medium,
            title: 'WHERE 子句中函数包裹列（$fn）可能导致全表扫描',
            description: '对列使用函数会使其无法走索引。'
                '建议改写为范围查询，例如 WHERE col >= "2024-01-01" '
                'AND col < "2025-01-01"。',
          ));
          break; // 一条语句只报一次函数问题（避免 N 个函数 N 条 finding）。
        }
      }

      // 模式 2：LIKE 前缀通配 —— LIKE '%...' 或 LIKE "%..."
      // 不报 LIKE 'abc%'（后缀通配，可用索引）。
      //
      // 注意：必须在 **原始** SQL 上检测，不能用 cleaned WHERE 子句——
      // _stripCommentsAndStrings 会把 LIKE '%abc' 的字符串内容剥成占位符 ' '，
      // 导致 % 不可见。原始 SQL 上 LIKE\s+引号% 模式明确（LIKE 关键字锚定）。
      final likePattern = RegExp(
        "LIKE\\s+['\"]%",
        caseSensitive: false,
      );
      if (likePattern.hasMatch(sql)) {
        findings.add(SafetyFinding(
          ruleId: id,
          severity: Severity.medium,
          title: "LIKE 前缀通配（'%...'）无法走索引",
          description: '以 % 开头的 LIKE 模式无法利用索引，会全表扫描。'
              '如需前缀匹配，考虑全文索引或调整查询逻辑。',
        ));
      }

      return findings;
    } catch (_) {
      // 规则异常 → 返回空（引擎也兜底 catch，但规则内处理更精确）。
      return [];
    }
  }
}
