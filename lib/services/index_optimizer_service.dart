import 'dart:developer' as developer;
import 'sql_optimizer_service.dart';

class IndexSuggestion {
  final String tableName;
  final List<String> columns;
  final String reason;
  final Priority priority;
  final String? createStatement;
  final String? impact;

  IndexSuggestion({
    required this.tableName,
    required this.columns,
    required this.reason,
    required this.priority,
    this.createStatement,
    this.impact,
  });

  Map<String, dynamic> toJson() => {
    'tableName': tableName,
    'columns': columns,
    'reason': reason,
    'priority': priority.name,
    'createStatement': createStatement,
    'impact': impact,
  };
}

class IndexInfo {
  final String table;
  final String name;
  final List<String> columns;
  final bool isUnique;
  final bool isPrimary;
  final String? indexType;

  IndexInfo({
    required this.table,
    required this.name,
    required this.columns,
    required this.isUnique,
    required this.isPrimary,
    this.indexType,
  });

  factory IndexInfo.fromMap(Map<String, dynamic> map) {
    return IndexInfo(
      table: map['Table']?.toString() ?? '',
      name: map['Key_name']?.toString() ?? '',
      columns: [map['Column_name']?.toString() ?? ''],
      isUnique: map['Non_unique']?.toString() == '0',
      isPrimary: map['Key_name']?.toString() == 'PRIMARY',
      indexType: map['Index_type']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'table': table,
    'name': name,
    'columns': columns,
    'isUnique': isUnique,
    'isPrimary': isPrimary,
    'indexType': indexType,
  };
}

@Deprecated(
  'Use IndexRecommendationEngine for EXPLAIN-based index recommendations instead',
)
class IndexOptimizerService {
  static final IndexOptimizerService _instance =
      IndexOptimizerService._internal();
  factory IndexOptimizerService() => _instance;
  IndexOptimizerService._internal();

  List<IndexSuggestion> analyzeForIndex(
    String sql,
    List<Map<String, dynamic>> tableStructures,
  ) {
    developer.log('🔍 开始索引优化分析', name: 'IndexOptimizerService');

    final suggestions = <IndexSuggestion>[];

    final whereColumns = _extractWhereColumns(sql);
    final joinColumns = _extractJoinColumns(sql);
    final orderColumns = _extractOrderColumns(sql);
    final groupColumns = _extractGroupColumns(sql);

    for (final tableStructure in tableStructures) {
      final tableName = tableStructure['table'] as String?;
      if (tableName == null) continue;

      final existingIndexes = tableStructure['indexes'] as List<dynamic>? ?? [];

      final tableWhereColumns = whereColumns[tableName] ?? [];
      final tableJoinColumns = joinColumns[tableName] ?? [];
      final tableOrderColumns = orderColumns[tableName] ?? [];
      final tableGroupColumns = groupColumns[tableName] ?? [];

      for (final column in tableWhereColumns) {
        if (!_hasIndexOnColumn(existingIndexes, column)) {
          suggestions.add(
            IndexSuggestion(
              tableName: tableName,
              columns: [column],
              reason: 'WHERE 子句中的列 $column 没有索引，可能导致全表扫描',
              priority: Priority.high,
              createStatement:
                  'CREATE INDEX idx_${tableName}_$column ON $tableName($column);',
              impact: '可显著提高 WHERE 条件查询性能',
            ),
          );
        }
      }

      for (final column in tableJoinColumns) {
        if (!_hasIndexOnColumn(existingIndexes, column)) {
          suggestions.add(
            IndexSuggestion(
              tableName: tableName,
              columns: [column],
              reason: 'JOIN 条件中的列 $column 没有索引，可能影响连接性能',
              priority: Priority.high,
              createStatement:
                  'CREATE INDEX idx_${tableName}_$column ON $tableName($column);',
              impact: '可显著提高 JOIN 查询性能',
            ),
          );
        }
      }

      for (final column in tableOrderColumns) {
        if (!_hasIndexOnColumn(existingIndexes, column)) {
          suggestions.add(
            IndexSuggestion(
              tableName: tableName,
              columns: [column],
              reason: 'ORDER BY 列 $column 没有索引，可能导致文件排序',
              priority: Priority.medium,
              createStatement:
                  'CREATE INDEX idx_${tableName}_$column ON $tableName($column);',
              impact: '可避免 filesort，提高排序性能',
            ),
          );
        }
      }

      for (final column in tableGroupColumns) {
        if (!_hasIndexOnColumn(existingIndexes, column)) {
          suggestions.add(
            IndexSuggestion(
              tableName: tableName,
              columns: [column],
              reason: 'GROUP BY 列 $column 没有索引，可能影响分组性能',
              priority: Priority.medium,
              createStatement:
                  'CREATE INDEX idx_${tableName}_$column ON $tableName($column);',
              impact: '可提高 GROUP BY 性能',
            ),
          );
        }
      }

      if (tableWhereColumns.length > 1) {
        final multiColumnKey = tableWhereColumns.take(3).toList();
        if (!_hasCompositeIndex(existingIndexes, multiColumnKey)) {
          suggestions.add(
            IndexSuggestion(
              tableName: tableName,
              columns: multiColumnKey,
              reason: '多个 WHERE 条件列可以考虑创建复合索引',
              priority: Priority.medium,
              createStatement:
                  'CREATE INDEX idx_${tableName}_${multiColumnKey.join('_')} ON $tableName(${multiColumnKey.join(', ')});',
              impact: '复合索引可以同时优化多个条件查询',
            ),
          );
        }
      }
    }

    developer.log(
      '✅ 索引优化分析完成，发现 ${suggestions.length} 条建议',
      name: 'IndexOptimizerService',
    );

    return suggestions;
  }

  Map<String, List<String>> _extractWhereColumns(String sql) {
    final result = <String, List<String>>{};
    final wherePattern = RegExp(
      r'WHERE\s+(.+?)(?:ORDER|GROUP|LIMIT|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final match = wherePattern.firstMatch(sql);

    if (match != null) {
      final whereClause = match.group(1) ?? '';
      final columnPattern = RegExp(r'(\w+)\.(\w+)\s*[=<>!]');

      for (final columnMatch in columnPattern.allMatches(whereClause)) {
        final table = columnMatch.group(1) ?? '';
        final column = columnMatch.group(2) ?? '';

        if (!result.containsKey(table)) {
          result[table] = [];
        }
        if (!result[table]!.contains(column)) {
          result[table]!.add(column);
        }
      }
    }

    return result;
  }

  Map<String, List<String>> _extractJoinColumns(String sql) {
    final result = <String, List<String>>{};
    final joinPattern = RegExp(
      r'JOIN\s+(\w+)\s+.*?ON\s+(.+?)(?:WHERE|ORDER|GROUP|LIMIT|JOIN|$)',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in joinPattern.allMatches(sql)) {
      final table = match.group(1) ?? '';
      final onClause = match.group(2) ?? '';
      final columnPattern = RegExp(r'(\w+)\.(\w+)\s*=');

      for (final columnMatch in columnPattern.allMatches(onClause)) {
        final columnTable = columnMatch.group(1) ?? '';
        final column = columnMatch.group(2) ?? '';

        if (columnTable == table) {
          if (!result.containsKey(table)) {
            result[table] = [];
          }
          if (!result[table]!.contains(column)) {
            result[table]!.add(column);
          }
        }
      }
    }

    return result;
  }

  Map<String, List<String>> _extractOrderColumns(String sql) {
    final result = <String, List<String>>{};
    final orderPattern = RegExp(
      r'ORDER\s+BY\s+(.+?)(?:LIMIT|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final match = orderPattern.firstMatch(sql);

    if (match != null) {
      final orderClause = match.group(1) ?? '';
      final columnPattern = RegExp(r'(\w+)\.(\w+)');

      for (final columnMatch in columnPattern.allMatches(orderClause)) {
        final table = columnMatch.group(1) ?? '';
        final column = columnMatch.group(2) ?? '';

        if (!result.containsKey(table)) {
          result[table] = [];
        }
        if (!result[table]!.contains(column)) {
          result[table]!.add(column);
        }
      }
    }

    return result;
  }

  Map<String, List<String>> _extractGroupColumns(String sql) {
    final result = <String, List<String>>{};
    final groupPattern = RegExp(
      r'GROUP\s+BY\s+(.+?)(?:HAVING|ORDER|LIMIT|$)',
      caseSensitive: false,
      dotAll: true,
    );
    final match = groupPattern.firstMatch(sql);

    if (match != null) {
      final groupClause = match.group(1) ?? '';
      final columnPattern = RegExp(r'(\w+)\.(\w+)');

      for (final columnMatch in columnPattern.allMatches(groupClause)) {
        final table = columnMatch.group(1) ?? '';
        final column = columnMatch.group(2) ?? '';

        if (!result.containsKey(table)) {
          result[table] = [];
        }
        if (!result[table]!.contains(column)) {
          result[table]!.add(column);
        }
      }
    }

    return result;
  }

  bool _hasIndexOnColumn(List<dynamic> indexes, String column) {
    for (final index in indexes) {
      final indexColumns = index['columns'] as List<dynamic>? ?? [];
      if (indexColumns.contains(column)) {
        return true;
      }
    }
    return false;
  }

  bool _hasCompositeIndex(List<dynamic> indexes, List<String> columns) {
    for (final index in indexes) {
      final indexColumns = index['columns'] as List<dynamic>? ?? [];
      if (indexColumns.length >= columns.length) {
        var matches = true;
        for (var i = 0; i < columns.length; i++) {
          if (indexColumns[i] != columns[i]) {
            matches = false;
            break;
          }
        }
        if (matches) return true;
      }
    }
    return false;
  }

  String generateIndexReport(List<IndexSuggestion> suggestions) {
    if (suggestions.isEmpty) {
      return '✅ 当前查询的索引配置看起来不错！';
    }

    final buffer = StringBuffer();

    buffer.writeln('📊 索引优化建议报告');
    buffer.writeln('=' * 60);
    buffer.writeln();
    buffer.writeln('发现 ${suggestions.length} 条索引优化建议：');
    buffer.writeln();

    final highPriority = suggestions
        .where((s) => s.priority == Priority.high)
        .toList();
    final mediumPriority = suggestions
        .where((s) => s.priority == Priority.medium)
        .toList();

    if (highPriority.isNotEmpty) {
      buffer.writeln('### 🔴 高优先级 (${highPriority.length})');
      buffer.writeln();
      for (final suggestion in highPriority) {
        buffer.writeln('**表**: ${suggestion.tableName}');
        buffer.writeln('**列**: ${suggestion.columns.join(', ')}');
        buffer.writeln('**原因**: ${suggestion.reason}');
        if (suggestion.createStatement != null) {
          buffer.writeln('**创建语句**:');
          buffer.writeln('```sql');
          buffer.writeln(suggestion.createStatement);
          buffer.writeln('```');
        }
        if (suggestion.impact != null) {
          buffer.writeln('**预期影响**: ${suggestion.impact}');
        }
        buffer.writeln();
      }
    }

    if (mediumPriority.isNotEmpty) {
      buffer.writeln('### 🟡 中优先级 (${mediumPriority.length})');
      buffer.writeln();
      for (final suggestion in mediumPriority) {
        buffer.writeln('**表**: ${suggestion.tableName}');
        buffer.writeln('**列**: ${suggestion.columns.join(', ')}');
        buffer.writeln('**原因**: ${suggestion.reason}');
        if (suggestion.createStatement != null) {
          buffer.writeln('**创建语句**:');
          buffer.writeln('```sql');
          buffer.writeln(suggestion.createStatement);
          buffer.writeln('```');
        }
        buffer.writeln();
      }
    }

    buffer.writeln('### 💡 索引设计原则');
    buffer.writeln();
    buffer.writeln('1. **选择性原则**: 优先为选择性高的列创建索引');
    buffer.writeln('2. **最左前缀**: 复合索引遵循最左前缀原则');
    buffer.writeln('3. **覆盖索引**: 尽量使用覆盖索引避免回表');
    buffer.writeln('4. **适度原则**: 索引不是越多越好，会降低写入性能');
    buffer.writeln('5. **定期维护**: 定期分析和优化索引');

    return buffer.toString();
  }
}
