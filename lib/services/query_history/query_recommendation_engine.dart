import 'dart:math';

import '../../models/query_history/query_record.dart';
import 'query_history_service.dart';

/// 查询推荐引擎
/// 基于当前输入和上下文推荐相似的历史查询
class QueryRecommendationEngine {
  final QueryHistoryService _historyService;

  QueryRecommendationEngine(this._historyService);

  /// 基于当前输入推荐相似查询
  Future<List<QueryRecommendation>> recommendSimilarQueries({
    required String currentQuery,
    String? currentTable,
    int limit = 5,
  }) async {
    if (currentQuery.trim().length < 3) return [];

    // 1. 获取所有历史查询
    final history = await _historyService.search(
      SearchCriteria(
        limit: 200, // 获取足够多的记录用于比较
      ),
    );

    if (history.isEmpty) return [];

    // 2. 计算相似度
    final scoredRecords = <QueryRecommendation>[];

    for (final record in history) {
      // 跳过完全相同的查询
      if (_normalizeQuery(record.sqlStatement) ==
          _normalizeQuery(currentQuery)) {
        continue;
      }

      final similarity = _calculateSimilarity(
        currentQuery,
        record.sqlStatement,
        currentTable: currentTable,
        recordTables: record.extractedTables,
      );

      if (similarity > 0.3) {
        // 只返回相似度 > 30% 的结果
        String reason;
        if (similarity > 0.8) {
          reason = 'Very similar query pattern';
        } else if (similarity > 0.6) {
          reason = 'Similar tables and structure';
        } else if (currentTable != null &&
            record.extractedTables.contains(currentTable)) {
          reason = 'Uses same table: $currentTable';
        } else {
          reason = 'Related query pattern';
        }

        scoredRecords.add(
          QueryRecommendation(
            record: record,
            similarity: similarity,
            reason: reason,
          ),
        );
      }
    }

    // 3. 排序并返回前 N 个
    scoredRecords.sort((a, b) => b.similarity.compareTo(a.similarity));
    return scoredRecords.take(limit).toList();
  }

  /// 基于选中的表推荐查询
  Future<List<QueryRecommendation>> recommendForTable({
    required String tableName,
    int limit = 5,
  }) async {
    // 获取使用该表的历史查询
    final history = await _historyService.search(SearchCriteria(limit: 100));

    final tableQueries = history.where((record) {
      return record.extractedTables.contains(tableName);
    }).toList();

    if (tableQueries.isEmpty) return [];

    // 按使用频率和最近时间排序
    final scoredRecords = tableQueries.map((record) {
      // 计算综合分数（频率 + 时间衰减）
      final ageInDays = DateTime.now().difference(record.createdAt).inDays;
      final recencyScore = exp(-ageInDays / 30.0); // 30 天衰减
      final favoriteBoost = record.isFavorite ? 1.5 : 1.0;
      final score = recencyScore * favoriteBoost;

      return QueryRecommendation(
        record: record,
        similarity: score,
        reason: record.isFavorite
            ? 'Frequently used with $tableName'
            : 'Recently used with $tableName',
      );
    }).toList();

    scoredRecords.sort((a, b) => b.similarity.compareTo(a.similarity));
    return scoredRecords.take(limit).toList();
  }

  /// 获取最常使用的查询模板
  Future<List<QueryRecommendation>> getFrequentQueries({int limit = 10}) async {
    final history = await _historyService.search(SearchCriteria(limit: 500));

    // 按查询模式分组统计
    final patternCounts = <String, List<QueryRecord>>{};

    for (final record in history) {
      final pattern = _extractPattern(record.sqlStatement);
      patternCounts.putIfAbsent(pattern, () => []).add(record);
    }

    // 计算每个模式的分数
    final recommendations = patternCounts.entries.map((entry) {
      final records = entry.value;
      final latestRecord = records.reduce(
        (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b,
      );
      final count = records.length;
      final avgExecutionTime =
          records.map((r) => r.executionTimeMs).reduce((a, b) => a + b) / count;

      // 分数 = 使用次数 * 时间衰减
      final ageInDays = DateTime.now()
          .difference(latestRecord.createdAt)
          .inDays;
      final recencyScore = exp(-ageInDays / 30.0);
      final score = count * recencyScore;

      return QueryRecommendation(
        record: latestRecord,
        similarity: score,
        reason:
            'Used $count times (avg ${avgExecutionTime.toStringAsFixed(0)}ms)',
      );
    }).toList();

    recommendations.sort((a, b) => b.similarity.compareTo(a.similarity));
    return recommendations.take(limit).toList();
  }

  /// 计算两个查询的相似度
  /// 返回 0.0 - 1.0 之间的值
  double _calculateSimilarity(
    String query1,
    String query2, {
    String? currentTable,
    List<String>? recordTables,
  }) {
    var score = 0.0;

    // 1. 表名相似度（权重 40%）
    final tables1 = _extractTables(query1);
    final tables2 = _extractTables(query2);
    final tableSimilarity = _jaccardSimilarity(tables1, tables2);
    score += tableSimilarity * 0.4;

    // 2. 查询类型相似度（权重 20%）
    final type1 = _detectQueryType(query1);
    final type2 = _detectQueryType(query2);
    if (type1 == type2) {
      score += 0.2;
    }

    // 3. 关键字相似度（权重 20%）
    final keywords1 = _extractKeywords(query1);
    final keywords2 = _extractKeywords(query2);
    final keywordSimilarity = _jaccardSimilarity(keywords1, keywords2);
    score += keywordSimilarity * 0.2;

    // 4. 结构相似度（权重 20%）
    final structure1 = _extractStructure(query1);
    final structure2 = _extractStructure(query2);
    if (structure1 == structure2) {
      score += 0.2;
    }

    // 5. 当前表匹配加成
    if (currentTable != null && recordTables != null) {
      if (recordTables.contains(currentTable)) {
        score = min(1.0, score + 0.15);
      }
    }

    return score;
  }

  /// Jaccard 相似度
  double _jaccardSimilarity(Set<String> set1, Set<String> set2) {
    if (set1.isEmpty && set2.isEmpty) return 1.0;
    if (set1.isEmpty || set2.isEmpty) return 0.0;

    final intersection = set1.intersection(set2);
    final union = set1.union(set2);

    return intersection.length / union.length;
  }

  /// 提取查询中的表名
  Set<String> _extractTables(String query) {
    final tables = <String>{};

    // FROM 子句
    final fromRegex = RegExp(r'FROM\s+(\w+)', caseSensitive: false);
    for (final match in fromRegex.allMatches(query)) {
      final table = match.group(1);
      if (table != null) tables.add(table.toLowerCase());
    }

    // JOIN 子句
    final joinRegex = RegExp(r'JOIN\s+(\w+)', caseSensitive: false);
    for (final match in joinRegex.allMatches(query)) {
      final table = match.group(1);
      if (table != null) tables.add(table.toLowerCase());
    }

    return tables;
  }

  /// 提取关键字（WHERE 条件中的列名和操作）
  Set<String> _extractKeywords(String query) {
    final keywords = <String>{};

    // WHERE 条件列
    final whereRegex = RegExp(
      r'WHERE\s+(.+?)(?:ORDER|GROUP|LIMIT|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final whereMatch = whereRegex.firstMatch(query);
    if (whereMatch != null) {
      final whereClause = whereMatch.group(1) ?? '';
      final columnRegex = RegExp(
        r'(\w+)\s*(?:=|<|>|LIKE|IN)',
        caseSensitive: false,
      );
      for (final match in columnRegex.allMatches(whereClause)) {
        final col = match.group(1);
        if (col != null && !_isReservedWord(col)) {
          keywords.add(col.toLowerCase());
        }
      }
    }

    // ORDER BY 列
    final orderRegex = RegExp(r'ORDER\s+BY\s+(\w+)', caseSensitive: false);
    for (final match in orderRegex.allMatches(query)) {
      final col = match.group(1);
      if (col != null) keywords.add('order_$col'.toLowerCase());
    }

    // GROUP BY 列
    final groupRegex = RegExp(r'GROUP\s+BY\s+(\w+)', caseSensitive: false);
    for (final match in groupRegex.allMatches(query)) {
      final col = match.group(1);
      if (col != null) keywords.add('group_$col'.toLowerCase());
    }

    return keywords;
  }

  /// 提取查询结构类型
  String _extractStructure(String query) {
    final normalized = query.toUpperCase().trim();

    if (normalized.contains('JOIN')) return 'JOIN';
    if (normalized.contains('GROUP BY')) return 'AGGREGATE';
    if (normalized.contains('ORDER BY')) return 'SORTED';
    if (normalized.contains('WHERE')) return 'FILTERED';
    if (normalized.contains('LIMIT')) return 'LIMITED';
    return 'SIMPLE';
  }

  /// 提取查询模式（用于分组）
  String _extractPattern(String query) {
    final normalized = _normalizeQuery(query);

    // 替换具体的值和表名为占位符
    var pattern = normalized;

    // 替换字符串值
    pattern = pattern.replaceAll(RegExp(r"'[^']*'"), "'?'");

    // 替换数字
    pattern = pattern.replaceAll(RegExp(r'\b\d+\b'), '?');

    // 替换 IN 列表
    pattern = pattern.replaceAll(RegExp(r'IN\s*\([^)]+\)'), 'IN (?)');

    return pattern;
  }

  /// 标准化查询（用于比较）
  String _normalizeQuery(String query) {
    return query.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 检测查询类型
  String? _detectQueryType(String query) {
    final normalized = query.trim().toUpperCase();
    if (normalized.startsWith('SELECT')) return 'SELECT';
    if (normalized.startsWith('INSERT')) return 'INSERT';
    if (normalized.startsWith('UPDATE')) return 'UPDATE';
    if (normalized.startsWith('DELETE')) return 'DELETE';
    if (normalized.startsWith('CREATE')) return 'CREATE';
    if (normalized.startsWith('ALTER')) return 'ALTER';
    if (normalized.startsWith('DROP')) return 'DROP';
    return 'OTHER';
  }

  /// 检查是否为 SQL 保留字
  bool _isReservedWord(String word) {
    final reservedWords = {
      'SELECT',
      'FROM',
      'WHERE',
      'AND',
      'OR',
      'NOT',
      'NULL',
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
    };
    return reservedWords.contains(word.toUpperCase());
  }
}
