import '../../models/query_optimizer/execution_plan.dart';

/// 索引推荐引擎
/// 基于执行计划和查询结构推荐最优索引
class IndexRecommendationEngine {
  /// 分析执行计划并生成索引推荐
  static List<IndexRecommendation> recommendIndexes({
    required ExecutionPlan plan,
    required String originalQuery,
  }) {
    final recommendations = <IndexRecommendation>[];
    final existingRecommendations = <String>{}; // 去重

    for (final step in plan.steps) {
      if (step.table == null || step.table == 'NULL') continue;

      final tableName = step.table!;

      // 1. 全表扫描 → 推荐 WHERE 条件索引
      if (step.scanType?.isInefficient ?? false) {
        final columns = _extractWhereColumns(originalQuery, tableName);
        if (columns.isNotEmpty) {
          final recommendation = _createIndexRecommendation(
            tableName: tableName,
            columns: columns,
            reason:
                'Full table scan detected. Index on ${columns.join(', ')} will avoid scanning all rows.',
            isUnique: false,
          );

          if (!existingRecommendations.contains(recommendation.indexName)) {
            existingRecommendations.add(recommendation.indexName);
            recommendations.add(recommendation);
          }
        }
      }

      // 2. 文件排序 → 推荐 ORDER BY 索引
      if (step.extra?.contains('Using filesort') ?? false) {
        final orderByColumns = _extractOrderByColumns(originalQuery, tableName);
        if (orderByColumns.isNotEmpty) {
          final recommendation = _createIndexRecommendation(
            tableName: tableName,
            columns: orderByColumns,
            reason:
                'Filesort detected. Index on ${orderByColumns.join(', ')} will eliminate sorting.',
            isUnique: false,
          );

          if (!existingRecommendations.contains(recommendation.indexName)) {
            existingRecommendations.add(recommendation.indexName);
            recommendations.add(recommendation);
          }
        }
      }

      // 3. 临时表（GROUP BY）→ 推荐 GROUP BY 索引
      if (step.extra?.contains('Using temporary') ?? false) {
        final groupByColumns = _extractGroupByColumns(originalQuery, tableName);
        if (groupByColumns.isNotEmpty) {
          final recommendation = _createIndexRecommendation(
            tableName: tableName,
            columns: groupByColumns,
            reason:
                'Temporary table detected for GROUP BY. Index on ${groupByColumns.join(', ')} will avoid temp tables.',
            isUnique: false,
          );

          if (!existingRecommendations.contains(recommendation.indexName)) {
            existingRecommendations.add(recommendation.indexName);
            recommendations.add(recommendation);
          }
        }
      }

      // 4. 缺少索引但有大表
      if ((step.estimatedRows ?? 0) > 1000 &&
          step.key == null &&
          step.possibleKeys == null) {
        final columns = _extractWhereColumns(originalQuery, tableName);
        if (columns.isNotEmpty) {
          final recommendation = _createIndexRecommendation(
            tableName: tableName,
            columns: columns,
            reason:
                'Large table (${step.estimatedRows} rows) with no index usage detected.',
            isUnique: false,
          );

          if (!existingRecommendations.contains(recommendation.indexName)) {
            existingRecommendations.add(recommendation.indexName);
            recommendations.add(recommendation);
          }
        }
      }
    }

    // 5. JOIN 条件优化
    final joinRecommendations = _analyzeJoinConditions(originalQuery);
    for (final rec in joinRecommendations) {
      if (!existingRecommendations.contains(rec.indexName)) {
        existingRecommendations.add(rec.indexName);
        recommendations.add(rec);
      }
    }

    return recommendations;
  }

  /// 创建索引推荐
  static IndexRecommendation _createIndexRecommendation({
    required String tableName,
    required List<String> columns,
    required String reason,
    bool isUnique = false,
  }) {
    final indexName = _generateIndexName(tableName, columns, isUnique);
    final ddlStatement = _generateCreateIndexDDL(
      tableName: tableName,
      indexName: indexName,
      columns: columns,
      isUnique: isUnique,
    );

    return IndexRecommendation(
      tableName: tableName,
      indexName: indexName,
      columns: columns,
      reason: reason,
      ddlStatement: ddlStatement,
      estimatedImprovement: _estimateImprovement(columns.length),
      isUnique: isUnique,
    );
  }

  /// 生成索引名称
  static String _generateIndexName(
    String tableName,
    List<String> columns,
    bool isUnique,
  ) {
    final prefix = isUnique ? 'uniq' : 'idx';
    final columnPart = columns.take(3).join('_');
    return '${prefix}_${tableName}_$columnPart';
  }

  /// 生成 CREATE INDEX DDL
  static String _generateCreateIndexDDL({
    required String tableName,
    required String indexName,
    required List<String> columns,
    bool isUnique = false,
  }) {
    final uniqueKeyword = isUnique ? 'UNIQUE ' : '';
    final columnList = columns.join(', ');
    return 'CREATE ${uniqueKeyword}INDEX $indexName ON $tableName ($columnList);';
  }

  /// 预估性能提升（简化估算）
  static double? _estimateImprovement(int columnCount) {
    // 基于列数的简化估算
    if (columnCount == 1) return 50.0;
    if (columnCount == 2) return 65.0;
    if (columnCount >= 3) return 75.0;
    return null;
  }

  /// 提取 WHERE 条件中的列
  static List<String> _extractWhereColumns(String query, String tableName) {
    final columns = <String>[];

    // 简单正则提取 WHERE 后的列名
    final whereRegex = RegExp(
      r'WHERE\s+(.+?)(?:ORDER|GROUP|LIMIT|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final whereMatch = whereRegex.firstMatch(query);

    if (whereMatch != null) {
      final whereClause = whereMatch.group(1) ?? '';
      // 提取列名（简化版：假设列名在操作符前）
      final columnRegex = RegExp(
        r'\b(\w+)\s*(?:=|<|>|LIKE|IN)',
        caseSensitive: false,
      );
      for (final match in columnRegex.allMatches(whereClause)) {
        final col = match.group(1);
        if (col != null && !_isReservedWord(col)) {
          columns.add(col);
        }
      }
    }

    return columns.toSet().toList(); // 去重
  }

  /// 提取 ORDER BY 列
  static List<String> _extractOrderByColumns(String query, String tableName) {
    final columns = <String>[];

    final regex = RegExp(
      r'ORDER\s+BY\s+(.+?)(?:LIMIT|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final match = regex.firstMatch(query);

    if (match != null) {
      final orderByClause = match.group(1) ?? '';
      final columnRegex = RegExp(
        r'(\w+)(?:\s+(?:ASC|DESC))?',
        caseSensitive: false,
      );
      for (final m in columnRegex.allMatches(orderByClause)) {
        final col = m.group(1);
        if (col != null && !_isReservedWord(col)) {
          columns.add(col);
        }
      }
    }

    return columns;
  }

  /// 提取 GROUP BY 列
  static List<String> _extractGroupByColumns(String query, String tableName) {
    final columns = <String>[];

    final regex = RegExp(
      r'GROUP\s+BY\s+(.+?)(?:ORDER|HAVING|LIMIT|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final match = regex.firstMatch(query);

    if (match != null) {
      final groupByClause = match.group(1) ?? '';
      final parts = groupByClause.split(',');
      for (final part in parts) {
        final col = part.trim().split(' ').first;
        if (col.isNotEmpty && !_isReservedWord(col)) {
          columns.add(col);
        }
      }
    }

    return columns;
  }

  /// 分析 JOIN 条件
  static List<IndexRecommendation> _analyzeJoinConditions(String query) {
    final recommendations = <IndexRecommendation>[];
    final normalized = query.toUpperCase();

    if (!normalized.contains('JOIN')) return recommendations;

    // 提取 JOIN 条件
    final joinRegex = RegExp(
      r'(\w+)\s+(?:LEFT|RIGHT|INNER|OUTER)?\s*JOIN\s+(\w+)\s+ON\s+(.+?)(?:\s+(?:LEFT|RIGHT|INNER|OUTER|WHERE|ORDER|GROUP|LIMIT)|$)',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in joinRegex.allMatches(query)) {
      final leftTable = match.group(1);
      final rightTable = match.group(2);
      final joinCondition = match.group(3) ?? '';

      // 提取 JOIN 列
      final columnRegex = RegExp(
        r'(\w+)\.(\w+)\s*=\s*\w+\.(\w+)',
        caseSensitive: false,
      );
      for (final colMatch in columnRegex.allMatches(joinCondition)) {
        final leftColumn = colMatch.group(2);
        final rightColumn = colMatch.group(3);

        if (leftColumn != null && rightColumn != null) {
          // 为右表推荐索引
          if (rightTable != null) {
            recommendations.add(
              _createIndexRecommendation(
                tableName: rightTable,
                columns: [rightColumn],
                reason:
                    'JOIN optimization: Index on $rightColumn for JOIN with $leftTable.$leftColumn',
              ),
            );
          }
        }
      }
    }

    return recommendations;
  }

  /// 检查是否为 SQL 保留字
  static bool _isReservedWord(String word) {
    final reservedWords = {
      'SELECT',
      'FROM',
      'WHERE',
      'AND',
      'OR',
      'NOT',
      'NULL',
      'TRUE',
      'FALSE',
      'ORDER',
      'GROUP',
      'BY',
      'HAVING',
      'LIMIT',
      'OFFSET',
      'JOIN',
      'ON',
      'AS',
      'DISTINCT',
      'ALL',
      'UNION',
      'INTERSECT',
      'EXCEPT',
    };

    return reservedWords.contains(word.toUpperCase());
  }
}
