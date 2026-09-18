//! 安全审查规则 R2：Schema 兼容性检查（列是否存在）。
//!
//! 解析 SQL 中引用的表/列，与当前 schema 元数据比对，发现引用了不存在
//! 的列。保守策略——无法确定时跳过（不误报）。

import '../../../models/database_models.dart' show Database, DbTable;
import '../../sql_parser_service.dart';
import '../safety_finding.dart';
import '../safety_rule.dart';

class SchemaCompatRule implements SafetyRule {
  @override
  final String id = 'schema_compat';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    final schema = context.schemaCache;
    if (schema == null) return []; // 无 schema 数据，跳过。

    // 提取 SQL 中的表名。
    final sqlType = SQLParserService.detectType(sql);
    final tableName = SQLParserService.extractTableName(sql, sqlType);
    if (tableName == null) return []; // 无法提取表名，跳过。

    // 从 schemaCache 找到对应表。
    final table = _findTable(schema, tableName);
    if (table == null) return []; // 表不在 schemaCache 中（可能未加载），跳过。

    // 提取 SQL 中引用的列名。
    final referencedCols = SQLParserService.extractColumns(sql);
    if (referencedCols.isEmpty) return []; // 无法提取列（如 SELECT *），跳过。

    // 表的实际列名集合。
    final actualCols = table.columns.map((c) => c.name.toLowerCase()).toSet();
    if (actualCols.isEmpty) return []; // 表无列信息，跳过。

    // 比对：引用列不在实际列中 → finding。
    final findings = <SafetyFinding>[];
    for (final col in referencedCols) {
      if (!actualCols.contains(col.toLowerCase())) {
        findings.add(SafetyFinding(
          ruleId: id,
          severity: Severity.high,
          title: "列 '$col' 在表 '$tableName' 中不存在",
          description: '该列可能已被删除或改名。请检查表结构。',
          affectedTable: tableName,
        ));
      }
    }

    return findings;
  }

  /// 从 Database 中按表名查找（大小写不敏感）。
  DbTable? _findTable(Database schema, String tableName) {
    final lower = tableName.toLowerCase();
    try {
      return schema.tables.cast<DbTable?>().firstWhere(
            (t) => t?.name.toLowerCase() == lower,
            orElse: () => null,
          );
    } catch (_) {
      return null;
    }
  }
}
