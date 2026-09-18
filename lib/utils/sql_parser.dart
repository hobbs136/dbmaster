import '../models/database_models.dart';

/// SQL 解析工具
///
/// 从 SQL 语句中解析结构化信息（外键、索引等）。
class SqlParser {
  SqlParser._();

  /// 从 SHOW CREATE TABLE 结果中解析外键约束
  ///
  /// 匹配格式:
  /// ```
  /// CONSTRAINT `name` FOREIGN KEY (`col`) REFERENCES `table` (`col`) [ON DELETE action] [ON UPDATE action]
  /// ```
  static List<ForeignKey> parseForeignKeys(String createSql, String tableName) {
    final fks = <ForeignKey>[];
    final regex = RegExp(
      r'CONSTRAINT\s+`([^`]+)`\s+FOREIGN\s+KEY\s+\(`([^`]+)`\)\s+REFERENCES\s+`([^`]+)`\s+\(`([^`]+)`\)(?:\s+ON\s+DELETE\s+(\w+(?:\s+(?!ON\s)\w+)?))?(?:\s+ON\s+UPDATE\s+(\w+(?:\s+(?!ON\s)\w+)?))?',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(createSql)) {
      fks.add(
        ForeignKey(
          name: match.group(1) ?? '',
          table: tableName,
          column: match.group(2) ?? '',
          referencedTable: match.group(3) ?? '',
          referencedColumn: match.group(4) ?? '',
          onDelete: match.group(5),
          onUpdate: match.group(6),
        ),
      );
    }
    return fks;
  }
}
