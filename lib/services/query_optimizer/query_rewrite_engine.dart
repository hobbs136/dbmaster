import '../../models/query_optimizer/execution_plan.dart';

/// 查询重写引擎
/// 提供查询优化建议并重写低效查询
class QueryRewriteEngine {
  /// 分析原始查询并提供重写建议
  ///
  /// [tableColumns] 可选：表名 → 列名列表的映射。提供时，SELECT * 重写会
  /// 用真实列名（从 FROM 子句抽出的表查表）；未提供则给出含表名的可操作
  /// 占位（不再是无信息的裸 TODO）。
  static List<QueryRewrite> suggestRewrites({
    required String originalQuery,
    required ExecutionPlan plan,
    Map<String, List<String>>? tableColumns,
  }) {
    final rewrites = <QueryRewrite>[];

    // 1. SELECT * → SELECT columns
    final selectStarRewrite = _rewriteSelectStar(
      originalQuery,
      tableColumns: tableColumns,
    );
    if (selectStarRewrite != null) {
      rewrites.add(selectStarRewrite);
    }

    // 2. OFFSET 分页 → 键集分页
    final offsetRewrite = _rewriteOffsetPagination(originalQuery);
    if (offsetRewrite != null) {
      rewrites.add(offsetRewrite);
    }

    // 3. 子查询 → JOIN（简化版）
    final subqueryRewrite = _rewriteSubqueryToJoin(originalQuery);
    if (subqueryRewrite != null) {
      rewrites.add(subqueryRewrite);
    }

    // 4. OR 条件 → UNION（特定场景）
    final orRewrite = _rewriteOrToUnion(originalQuery);
    if (orRewrite != null) {
      rewrites.add(orRewrite);
    }

    // 5. NOT IN → NOT EXISTS
    final notInRewrite = _rewriteNotInToNotExists(originalQuery);
    if (notInRewrite != null) {
      rewrites.add(notInRewrite);
    }

    return rewrites;
  }

  /// 重写 SELECT *
  ///
  /// 当 [tableColumns] 提供了 FROM 表的列名列表时，用真实列名重写；
  /// 否则抽取表名给出含表名的可操作占位（不再是无信息的裸 TODO）。
  static QueryRewrite? _rewriteSelectStar(
    String query, {
    Map<String, List<String>>? tableColumns,
  }) {
    if (!_hasSelectStar(query)) return null;

    final tableName = _extractFromTable(query);
    final columns =
        (tableName != null) ? (tableColumns?[tableName]) : null;

    String rewritten;
    String reason;
    if (columns != null && columns.isNotEmpty) {
      // 有真实列名：用列清单替换 *
      final columnList = columns.join(', ');
      rewritten = query.replaceFirstMapped(
        RegExp(r'SELECT\s+\*', caseSensitive: false),
        (_) => 'SELECT $columnList',
      );
      reason =
          'SELECT * retrieves all ${columns.length} columns of `$tableName`, '
          'causing unnecessary I/O. The rewrite below lists them explicitly; '
          'trim to only the columns you need.';
    } else if (tableName != null) {
      // 无 schema 但能抽到表名：占位含表名，可操作
      rewritten = query.replaceFirstMapped(
        RegExp(r'SELECT\s+\*', caseSensitive: false),
        (_) =>
            'SELECT /* TODO: replace with needed columns of $tableName */',
      );
      reason =
          'SELECT * on `$tableName` retrieves all columns, causing unnecessary '
          'I/O. Replace * with the columns you actually need '
          '(schema not available to the optimizer — pass tableColumns to '
          'enable automatic rewrite).';
    } else {
      // 抽不到表名（多表 JOIN / 子查询 / 解析失败）：保留裸占位
      rewritten = query.replaceFirstMapped(
        RegExp(r'SELECT\s+\*', caseSensitive: false),
        (_) => 'SELECT /* TODO: Specify required columns */',
      );
      reason =
          'SELECT * retrieves all columns, causing unnecessary I/O. '
          'Specify only needed columns.';
    }

    return QueryRewrite(
      originalQuery: query,
      rewrittenQuery: rewritten,
      reason: reason,
      type: RewriteType.selectStarToColumns,
    );
  }

  /// 从 SELECT 的 FROM 子句抽出（单）表名。
  /// 多表 JOIN / 子查询 / CTE 等复杂结构返回 null（保守不猜）。
  static String? _extractFromTable(String query) {
    // 去注释、去字符串字面量，避免被 FROM 关键字误命中
    final cleaned = query
        .replaceAll(RegExp(r'--[^\n]*'), '')
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .replaceAll(RegExp(r"'(?:[^']|'')*'"), '?')
        .replaceAll(RegExp(r'"(?:[^"]|"")*"'), '?');

    final match = RegExp(
      r'\bFROM\s+([A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)?)',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (match == null) return null;

    final raw = match.group(1);
    if (raw == null) return null;

    // 检测多表 JOIN：FROM 后还有逗号或 JOIN 关键字 → 保守返回 null
    final afterFrom = cleaned.substring(match.end);
    if (RegExp(r'\bJOIN\b', caseSensitive: false).hasMatch(afterFrom) ||
        RegExp(r',\s*[A-Za-z_]').hasMatch(afterFrom)) {
      return null;
    }

    // 取末段做 schema 查表（schema.table → table），保持大小写不敏感匹配由调用方决定
    final parts = raw.split('.');
    return parts.last;
  }

  /// 重写 OFFSET 分页为键集分页
  static QueryRewrite? _rewriteOffsetPagination(String query) {
    if (!_hasOffsetPagination(query)) return null;

    // 提取关键信息
    final orderByMatch = RegExp(
      r'ORDER\s+BY\s+(.+?)(?:LIMIT|$)',
      caseSensitive: false,
    ).firstMatch(query);
    final limitMatch = RegExp(
      r'LIMIT\s+(\d+)',
      caseSensitive: false,
    ).firstMatch(query);

    if (orderByMatch == null || limitMatch == null) return null;

    final orderByColumn = orderByMatch.group(1)?.trim().split(' ').first;
    final limit = limitMatch.group(1);

    if (orderByColumn == null || limit == null) return null;

    // 生成键集分页版本（简化示例）
    final rewritten = query
        .replaceFirst(
          RegExp(r'LIMIT\s+\d+\s+OFFSET\s+\d+', caseSensitive: false),
          'LIMIT $limit',
        )
        .replaceFirst(
          RegExp(r'WHERE\s+', caseSensitive: false),
          'WHERE $orderByColumn > last_seen_value AND ',
        );

    return QueryRewrite(
      originalQuery: query,
      rewrittenQuery: rewritten,
      reason:
          'OFFSET pagination becomes slower as offset grows. Use keyset pagination with the last seen value.',
      type: RewriteType.offsetToKeyset,
    );
  }

  /// 重写子查询为 JOIN
  static QueryRewrite? _rewriteSubqueryToJoin(String query) {
    // 检测简单的 IN 子查询
    final inSubqueryRegex = RegExp(
      r'(\w+)\s+IN\s*\(\s*SELECT\s+(\w+)\s+FROM\s+(\w+)',
      caseSensitive: false,
    );
    final match = inSubqueryRegex.firstMatch(query);

    if (match == null) return null;

    final outerColumn = match.group(1);
    final innerColumn = match.group(2);
    final innerTable = match.group(3);

    if (outerColumn == null || innerColumn == null || innerTable == null) {
      return null;
    }

    // 生成 JOIN 版本（简化版）
    final rewritten = query.replaceFirst(
      inSubqueryRegex,
      'EXISTS (SELECT 1 FROM $innerTable WHERE $innerTable.$innerColumn = outer_table.$outerColumn)',
    );

    return QueryRewrite(
      originalQuery: query,
      rewrittenQuery: rewritten,
      reason:
          'Subquery with IN can often be rewritten as JOIN or EXISTS for better performance.',
      type: RewriteType.subqueryToJoin,
    );
  }

  /// 重写 OR 条件为 UNION
  static QueryRewrite? _rewriteOrToUnion(String query) {
    // 检测简单的 OR 条件（同一列的不同值）
    final orRegex = RegExp(
      r'WHERE\s+(.+?)\s+OR\s+(.+?)(?:ORDER|GROUP|LIMIT|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final match = orRegex.firstMatch(query);

    if (match == null) return null;

    final condition1 = match.group(1)?.trim();
    final condition2 = match.group(2)?.trim();

    if (condition1 == null || condition2 == null) return null;

    // 生成 UNION 版本（简化版）
    final selectMatch = RegExp(
      r'(SELECT\s+.+?\s+FROM\s+\w+)',
      caseSensitive: false,
    ).firstMatch(query);
    if (selectMatch == null) return null;

    final baseQuery = selectMatch.group(1);
    final rewritten =
        '$baseQuery WHERE $condition1\nUNION\n$baseQuery WHERE $condition2';

    return QueryRewrite(
      originalQuery: query,
      rewrittenQuery: rewritten,
      reason:
          'OR conditions on indexed columns may prevent index usage. UNION can use indexes for each branch.',
      type: RewriteType.orToUnion,
    );
  }

  /// 重写 NOT IN 为 NOT EXISTS
  static QueryRewrite? _rewriteNotInToNotExists(String query) {
    final notInRegex = RegExp(
      r'(\w+)\s+NOT\s+IN\s*\(\s*SELECT\s+(\w+)\s+FROM\s+(\w+)',
      caseSensitive: false,
    );
    final match = notInRegex.firstMatch(query);

    if (match == null) return null;

    final outerColumn = match.group(1);
    final innerColumn = match.group(2);
    final innerTable = match.group(3);

    if (outerColumn == null || innerColumn == null || innerTable == null) {
      return null;
    }

    final rewritten = query.replaceFirst(
      notInRegex,
      'NOT EXISTS (SELECT 1 FROM $innerTable WHERE $innerTable.$innerColumn = outer_table.$outerColumn)',
    );

    return QueryRewrite(
      originalQuery: query,
      rewrittenQuery: rewritten,
      reason:
          'NOT IN with subqueries can have performance issues with NULL values. NOT EXISTS is generally safer and faster.',
      type: RewriteType.notInToNotExists,
    );
  }

  // === 辅助方法 ===

  static bool _hasSelectStar(String query) {
    final normalized = query.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.contains('SELECT *') || normalized.contains('SELECT\t*');
  }

  static bool _hasOffsetPagination(String query) {
    final normalized = query.toUpperCase();
    return normalized.contains('OFFSET') && normalized.contains('LIMIT');
  }
}
