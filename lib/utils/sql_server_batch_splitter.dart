import '../services/sql_parser_service.dart';

/// Splits a T-SQL script into batches separated by the `GO` batch terminator.
///
/// `GO` is recognized only when it appears alone on a line (optionally followed
/// by a repeat count `GO N`). Matching is case-insensitive. When no `GO` is
/// present, the script is split into individual statements (SQL-aware).
///
/// Example:
/// ```
/// CREATE TABLE t1 (id INT);
/// GO
/// CREATE TABLE t2 (id INT);
/// GO 2
/// ```
/// produces `["CREATE TABLE t1 (id INT);", "CREATE TABLE t2 (id INT);", "CREATE TABLE t2 (id INT);"]`.
List<String> splitSqlServerBatches(String script) {
  final goLine = RegExp(r'^\s*go\s*(\d*)\s*$', caseSensitive: false);
  final lines = script.split(RegExp(r'\r?\n'));

  // Fast path: no GO at all — SQL-aware statement splitting（U08：字符串/
  // 注释里的分号不截断；旧朴素 split(';') 会把 'a;b' 拦腰截断）。
  if (!lines.any((line) => goLine.hasMatch(line))) {
    return SQLParserService.split(script).map((s) => s.sql).toList();
  }

  final batches = <String>[];
  final current = <String>[];
  for (final line in lines) {
    final match = goLine.firstMatch(line);
    if (match != null) {
      batches.add(current.join('\n'));
      current.clear();
      final count = int.tryParse(match.group(1) ?? '') ?? 1;
      for (var i = 1; i < count && batches.isNotEmpty; i++) {
        batches.add(batches.last);
      }
    } else {
      current.add(line);
    }
  }
  if (current.isNotEmpty) {
    batches.add(current.join('\n'));
  }
  return batches.map((b) => b.trim()).where((b) => b.isNotEmpty).toList();
}
