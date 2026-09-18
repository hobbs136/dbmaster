import 'dart:developer' as developer;

enum Priority { high, medium, low }

class SqlOptimizationSuggestion {
  final String type;
  final String description;
  final String suggestion;
  final Priority priority;
  final String? beforeExample;
  final String? afterExample;

  SqlOptimizationSuggestion({
    required this.type,
    required this.description,
    required this.suggestion,
    required this.priority,
    this.beforeExample,
    this.afterExample,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'description': description,
    'suggestion': suggestion,
    'priority': priority.name,
    'beforeExample': beforeExample,
    'afterExample': afterExample,
  };
}

@Deprecated('Use QueryOptimizerService for EXPLAIN-based analysis instead')
class SqlOptimizerService {
  static final SqlOptimizerService _instance = SqlOptimizerService._internal();
  factory SqlOptimizerService() => _instance;
  SqlOptimizerService._internal();

  List<SqlOptimizationSuggestion> analyze(String sql) {
    developer.log('🔍 开始SQL优化分析', name: 'SqlOptimizerService');

    final suggestions = <SqlOptimizationSuggestion>[];
    final upperSql = sql.toUpperCase();

    _checkSelectStar(sql, upperSql, suggestions);
    _checkWhereClause(upperSql, suggestions);
    _checkLikeUsage(upperSql, suggestions);
    _checkOrUsage(sql, upperSql, suggestions);
    _checkDistinct(upperSql, suggestions);
    _checkOrderBy(upperSql, suggestions);
    _checkSubquery(sql, upperSql, suggestions);
    _checkNullComparison(upperSql, suggestions);
    _checkFunctionInWhere(sql, upperSql, suggestions);
    _checkNotIn(upperSql, suggestions);

    developer.log(
      '✅ SQL优化分析完成，发现 ${suggestions.length} 条建议',
      name: 'SqlOptimizerService',
    );

    return suggestions;
  }

  void _checkSelectStar(
    String sql,
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    if (upperSql.contains('SELECT *')) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '性能优化',
          description: '使用了 SELECT * 查询所有字段',
          suggestion: '明确指定需要的字段，避免查询不必要的数据',
          priority: Priority.high,
          beforeExample: 'SELECT * FROM users',
          afterExample: 'SELECT id, name, email FROM users',
        ),
      );
    }
  }

  void _checkWhereClause(
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    if (upperSql.contains('SELECT') && !upperSql.contains('WHERE')) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '性能优化',
          description: '查询语句缺少 WHERE 条件',
          suggestion: '添加适当的 WHERE 条件限制结果集大小，避免全表扫描',
          priority: Priority.high,
          beforeExample: 'SELECT * FROM users',
          afterExample: 'SELECT * FROM users WHERE status = 1',
        ),
      );
    }
  }

  void _checkLikeUsage(
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    if (upperSql.contains("LIKE '%")) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '索引优化',
          description: 'LIKE 语句使用了前导通配符',
          suggestion: '前导通配符会导致索引失效，考虑使用后导通配符或全文索引',
          priority: Priority.high,
          beforeExample: "WHERE name LIKE '%john%'",
          afterExample: "WHERE name LIKE 'john%'",
        ),
      );
    }
  }

  void _checkOrUsage(
    String sql,
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    final orCount = ' OR '.allMatches(upperSql).length;
    if (orCount > 2) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '性能优化',
          description: '使用了多个 OR 条件',
          suggestion: '考虑使用 IN 或 UNION 替代多个 OR 条件，可能提高查询效率',
          priority: Priority.medium,
          beforeExample: "WHERE status = 1 OR status = 2 OR status = 3",
          afterExample: "WHERE status IN (1, 2, 3)",
        ),
      );
    }
  }

  void _checkDistinct(
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    if (upperSql.contains('DISTINCT')) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '性能优化',
          description: '使用了 DISTINCT 关键字',
          suggestion: 'DISTINCT 会进行排序和去重操作，考虑优化查询逻辑或添加索引',
          priority: Priority.medium,
        ),
      );
    }
  }

  void _checkOrderBy(
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    if (upperSql.contains('ORDER BY')) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '性能优化',
          description: '使用了 ORDER BY 排序',
          suggestion: '确保排序字段有索引，大数据量排序可能影响性能',
          priority: Priority.medium,
        ),
      );
    }
  }

  void _checkSubquery(
    String sql,
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    final subqueryCount = 'SELECT'.allMatches(upperSql).length - 1;
    if (subqueryCount > 0) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '性能优化',
          description: '使用了子查询',
          suggestion: '考虑使用 JOIN 替代子查询，通常性能更好',
          priority: Priority.medium,
          beforeExample:
              'SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)',
          afterExample:
              'SELECT DISTINCT u.* FROM users u INNER JOIN orders o ON u.id = o.user_id',
        ),
      );
    }
  }

  void _checkNullComparison(
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    if (upperSql.contains('= NULL') || upperSql.contains('!= NULL')) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '语法优化',
          description: '使用了错误的 NULL 比较',
          suggestion: '使用 IS NULL 或 IS NOT NULL 进行 NULL 值判断',
          priority: Priority.high,
          beforeExample: 'WHERE column = NULL',
          afterExample: 'WHERE column IS NULL',
        ),
      );
    }
  }

  void _checkFunctionInWhere(
    String sql,
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    final functionPattern = RegExp(
      r'WHERE\s+.*\b(UPPER|LOWER|DATE|YEAR|MONTH)\s*\(',
    );
    if (functionPattern.hasMatch(upperSql)) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '索引优化',
          description: 'WHERE 子句中使用了函数',
          suggestion: '在 WHERE 子句中对字段使用函数会导致索引失效，考虑使用函数索引或修改查询逻辑',
          priority: Priority.high,
          beforeExample: "WHERE UPPER(name) = 'JOHN'",
          afterExample: "WHERE name = 'john' COLLATE utf8mb4_general_ci",
        ),
      );
    }
  }

  void _checkNotIn(
    String upperSql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    if (upperSql.contains('NOT IN')) {
      suggestions.add(
        SqlOptimizationSuggestion(
          type: '性能优化',
          description: '使用了 NOT IN 操作符',
          suggestion:
              'NOT IN 性能较差，考虑使用 LEFT JOIN ... WHERE ... IS NULL 或 NOT EXISTS',
          priority: Priority.medium,
          beforeExample: 'WHERE id NOT IN (1, 2, 3)',
          afterExample: 'WHERE NOT EXISTS (SELECT 1 FROM ...)',
        ),
      );
    }
  }

  String generateOptimizationReport(
    String sql,
    List<SqlOptimizationSuggestion> suggestions,
  ) {
    if (suggestions.isEmpty) {
      return '✅ SQL语句看起来不错，没有发现明显的优化点！';
    }

    final buffer = StringBuffer();
    buffer.writeln('📊 SQL优化分析报告');
    buffer.writeln('=' * 50);
    buffer.writeln();
    buffer.writeln('原始SQL:');
    buffer.writeln('```sql');
    buffer.writeln(sql);
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('发现 ${suggestions.length} 条优化建议：');
    buffer.writeln();

    for (var i = 0; i < suggestions.length; i++) {
      final suggestion = suggestions[i];
      buffer.writeln(
        '### ${i + 1}. ${suggestion.type} [${suggestion.priority}优先级]',
      );
      buffer.writeln();
      buffer.writeln('**问题描述**: ${suggestion.description}');
      buffer.writeln();
      buffer.writeln('**优化建议**: ${suggestion.suggestion}');

      if (suggestion.beforeExample != null) {
        buffer.writeln();
        buffer.writeln('**优化前**:');
        buffer.writeln('```sql');
        buffer.writeln(suggestion.beforeExample);
        buffer.writeln('```');
      }

      if (suggestion.afterExample != null) {
        buffer.writeln();
        buffer.writeln('**优化后**:');
        buffer.writeln('```sql');
        buffer.writeln(suggestion.afterExample);
        buffer.writeln('```');
      }

      buffer.writeln();
    }

    return buffer.toString();
  }
}
