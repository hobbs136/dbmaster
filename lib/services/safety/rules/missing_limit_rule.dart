//! 安全审查规则 R3：缺 LIMIT 大表警告。
//!
//! SELECT 语句无 LIMIT 子句，且目标表行数超过阈值（默认 10 万）时，
//! 发出 medium 级别 finding 并建议附加 LIMIT。

import '../../../models/sql_statement.dart' show SQLType;
import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

class MissingLimitRule implements SafetyRule {
  @override
  final String id = 'missing_limit';

  /// 触发警告的行数阈值（表行数 > 此值且无 LIMIT → 警告）。
  final int threshold;

  /// 建议 SQL 中附加的 LIMIT 值。
  final int suggestedLimit;

  MissingLimitRule({
    this.threshold = 100000,
    this.suggestedLimit = 1000,
  });

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    // 只检查 SELECT 语句。用去注释文本做类型判定——前导 -- 注释会让
    // detectType 把 SELECT 判成 other，导致缺 LIMIT 规则漏报（文档 B3 场景）。
    final sqlType =
        SQLParserService.detectType(SQLParserService.cleanForAnalysis(sql));
    if (sqlType != SQLType.select) return [];

    // 有 LIMIT 子句 → 无问题。
    if (SQLParserService.hasLimitClause(sql)) return [];

    // COUNT/SUM 等整查询聚合（无 GROUP BY）无论表多大都只返回一行，
    // LIMIT 无意义 → 跳过（用户报告：大表 SELECT COUNT(*) 也弹 LIMIT
    // 警告）。放在行数查询之前，顺带省一次 getTableRowCount 往返。
    if (SQLParserService.isSingleRowAggregate(sql)) return [];

    // 提取表名。
    final tableName = SQLParserService.extractTableName(sql, sqlType);
    if (tableName == null) return []; // 无法提取表名，跳过。

    // 查表行数。
    final rowCount = await context.getRowCount(tableName);
    if (rowCount == null) return []; // 无行数数据，跳过。

    // 行数超阈值 → medium finding + 建议。
    if (rowCount > threshold) {
      // 生成建议 SQL：原 SQL 末尾追加 LIMIT（处理已有 ; 的情况）。
      final trimmedSql = sql.trim();
      final hasSemicolon = trimmedSql.endsWith(';');
      final suggestion =
          '${hasSemicolon ? trimmedSql.substring(0, trimmedSql.length - 1) : trimmedSql} LIMIT $suggestedLimit';

      return [
        SafetyFinding(
          ruleId: id,
          severity: Severity.medium,
          title: "表 '$tableName' 有 ${_formatCount(rowCount)} 行，缺 LIMIT",
          description: '全表扫描可能耗时较长。建议附加 LIMIT 子句限制返回行数。',
          suggestion: suggestion,
          affectedTable: tableName,
        ),
      ];
    }

    return [];
  }

  /// 格式化行数（如 5000000 → "5,000,000"）。
  String _formatCount(int count) {
    return count.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}
