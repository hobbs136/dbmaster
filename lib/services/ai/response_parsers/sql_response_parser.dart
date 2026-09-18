import 'ai_response_parser.dart';

/// SQL 语句响应解析器
///
/// 从 AI 返回的文本中提取 SQL 语句。
class SqlResponseParser extends AiResponseParser {
  SqlResponseParser({super.locale});

  @override
  List<String> extractExecutableStatements(String response) {
    final results = <String>[];
    final processedRanges = <List<int>>[];

    // 1. 提取 <sql>...</sql> 标签（最高优先级）
    final sqlTagPattern = RegExp(
      r'<sql>\s*([\s\S]*?)\s*</sql>',
      caseSensitive: false,
    );
    for (final match in sqlTagPattern.allMatches(response)) {
      final sql = _cleanSqlContent(match.group(1) ?? '');
      if (sql.isNotEmpty) {
        results.add(sql);
        processedRanges.add([match.start, match.end]);
      }
    }

    // 2. 提取 ```sql ... ``` 代码块（仅在无 <sql> 标签时）
    if (results.isEmpty) {
      final markdownPattern = RegExp(
        r'```(?:sql|javascript|js|mongodb)?\s*\n?([\s\S]*?)```',
        caseSensitive: false,
      );
      for (final match in markdownPattern.allMatches(response)) {
        if (_isRangeOverlapping(match.start, match.end, processedRanges))
          continue;

        final sql = _cleanSqlContent(match.group(1) ?? '');
        if (sql.isNotEmpty && isValidCommand(sql)) {
          results.add(sql);
          processedRanges.add([match.start, match.end]);
        }
      }
    }

    // 3. 如果前两种格式都未匹配到，尝试提取纯 SQL 语句
    if (results.isEmpty) {
      final plainSqlPattern = RegExp(
        r'(?:^|\n)\s*(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|WITH|EXPLAIN|DESCRIBE|SHOW)\b[\s\S]*?(?=\n\s*(?:SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|WITH|EXPLAIN|DESCRIBE|SHOW)\b|$)',
        caseSensitive: false,
        multiLine: true,
      );
      for (final match in plainSqlPattern.allMatches(response)) {
        if (_isRangeOverlapping(match.start, match.end, processedRanges))
          continue;

        final sql = _cleanSqlContent(match.group(0) ?? '');
        if (sql.isNotEmpty &&
            isValidCommand(sql) &&
            !_isDuplicate(sql, results)) {
          results.add(sql);
          processedRanges.add([match.start, match.end]);
        }
      }
    }

    return results;
  }

  @override
  bool isValidCommand(String sql) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return false;

    // 检查是否包含基本的 SQL 关键字
    final basicKeywords = RegExp(
      r'\b(SELECT|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE|EXPLAIN|SHOW|DESCRIBE|USE|GRANT|REVOKE|CALL|EXEC|WITH|SET|BEGIN|COMMIT|ROLLBACK|ANALYZE|OPTIMIZE|CHECK|REPAIR|COPY|MERGE|UPSERT|REPLACE|VALUES|FROM|WHERE|JOIN|GROUP|ORDER|LIMIT|HAVING|UNION|CASE|WHEN|THEN|ELSE|END|IF|FOR|CURSOR|FETCH|OPEN|CLOSE|DECLARE|CONSTRAINT|PRIMARY|FOREIGN|KEY|INDEX|UNIQUE|NOT|NULL|AUTO_INCREMENT|IDENTITY|REFERENCES|CASCADE|ON|AS|BY|ASC|DESC|DISTINCT|AND|OR|IN|EXISTS|BETWEEN|LIKE|IS|TRUE|FALSE|NOW|CURRENT_DATE|CURRENT_TIME|CURRENT_TIMESTAMP|DATE|TIME|TIMESTAMP|INTERVAL|COUNT|SUM|AVG|MAX|MIN|LENGTH|SUBSTRING|CONCAT|UPPER|LOWER|TRIM|ROUND|ABS|MOD|POWER|SQRT|LOG|RAND|UUID|MD5|SHA1|COALESCE|NULLIF|IFNULL|GREATEST|LEAST|DATABASE|USER|VERSION|SCHEMA|FOUND_ROWS|ROW_COUNT|LAST_INSERT_ID|CONNECTION_ID|CHARSET|COLLATION|FORMAT|GET_LOCK|RELEASE_LOCK|SLEEP|BENCHMARK)\b',
      caseSensitive: false,
    );
    return basicKeywords.hasMatch(sql);
  }

  /// 清理 SQL 内容中的非 SQL 文字
  String _cleanSqlContent(String sql) {
    // 去掉 markdown 代码块标记
    sql = sql.replaceAll(RegExp(r'^\s*```\w*\s*', multiLine: true), '');
    sql = sql.replaceAll(RegExp(r'\s*```\s*$', multiLine: true), '');

    // 去掉行首的中文说明
    final lines = sql.split('\n');
    final cleanedLines = lines.where((line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return false;
      // 过滤掉纯中文说明行
      if (RegExp(r'^[\u4e00-\u9fa5\s：:]+$').hasMatch(trimmed)) return false;
      // 过滤掉纯注释行
      if (trimmed.startsWith('--') || trimmed.startsWith('#')) return false;
      return true;
    }).toList();

    var result = cleanedLines.join('\n').trim();

    // 去除末尾的分号
    if (result.endsWith(';')) {
      result = result.substring(0, result.length - 1).trim();
    }

    return result;
  }

  bool _isRangeOverlapping(int start, int end, List<List<int>> ranges) {
    for (final range in ranges) {
      if (start < range[1] && end > range[0]) {
        return true;
      }
    }
    return false;
  }

  bool _isDuplicate(String sql, List<String> existing) {
    final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (final existingSql in existing) {
      final existingNormalized = existingSql
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (normalized == existingNormalized) return true;
    }
    return false;
  }
}
