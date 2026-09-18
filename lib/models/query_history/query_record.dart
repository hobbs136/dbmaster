import 'package:flutter/foundation.dart';

/// 查询记录模型
@immutable
class QueryRecord {
  final String? id;
  final String sqlStatement;
  final String connectionId;
  final String? connectionName;
  final String databaseType;
  final String? databaseName;
  final int executionTimeMs;
  final int? rowCount;
  final bool isSuccess;
  final String? errorMessage;
  final DateTime createdAt;
  final bool isFavorite;
  final List<String> tags;
  final String? queryType; // SELECT, INSERT, UPDATE, DELETE, CREATE, etc.

  const QueryRecord({
    this.id,
    required this.sqlStatement,
    required this.connectionId,
    this.connectionName,
    required this.databaseType,
    this.databaseName,
    required this.executionTimeMs,
    this.rowCount,
    required this.isSuccess,
    this.errorMessage,
    required this.createdAt,
    this.isFavorite = false,
    this.tags = const [],
    this.queryType,
  });

  /// 从数据库行创建
  factory QueryRecord.fromMap(Map<String, dynamic> map) {
    return QueryRecord(
      id: map['id']?.toString(),
      sqlStatement: map['sql_statement'] as String? ?? '',
      connectionId: map['connection_id'] as String? ?? '',
      connectionName: map['connection_name'] as String?,
      databaseType: map['database_type'] as String? ?? 'unknown',
      databaseName: map['database_name'] as String?,
      executionTimeMs: map['execution_time_ms'] as int? ?? 0,
      rowCount: map['row_count'] as int?,
      isSuccess: (map['is_success'] as int? ?? 1) == 1,
      errorMessage: map['error_message'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      tags: parseTags(map['tags'] as String?),
      queryType: map['query_type'] as String?,
    );
  }

  /// 转换为数据库行
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sql_statement': sqlStatement,
      'connection_id': connectionId,
      'connection_name': connectionName,
      'database_type': databaseType,
      'database_name': databaseName,
      'execution_time_ms': executionTimeMs,
      'row_count': rowCount,
      'is_success': isSuccess ? 1 : 0,
      'error_message': errorMessage,
      'created_at': createdAt.toIso8601String(),
      'is_favorite': isFavorite ? 1 : 0,
      'tags': tags.join(','),
      'query_type': queryType,
    };
  }

  /// 提取查询中的表名
  List<String> get extractedTables {
    // 020-mongo US4 — Mongo 集合名提取（db.<coll>.method(...)）
    final trimmed = sqlStatement.trim();
    if (trimmed.toLowerCase().startsWith('db.')) {
      final m = RegExp(r'db\.([A-Za-z0-9_]+)\.').firstMatch(trimmed);
      return m != null ? [m.group(1)!] : <String>[];
    }
    final tables = <String>[];
    final regex = RegExp(r'\bFROM\s+(\w+)', caseSensitive: false);
    for (final match in regex.allMatches(sqlStatement)) {
      final table = match.group(1);
      if (table != null && !tables.contains(table)) {
        tables.add(table);
      }
    }
    return tables;
  }

  /// 提取查询类型
  String? get detectedQueryType {
    final trimmed = sqlStatement.trim();
    // 020-mongo US4 — Mongo shell 查询类型检测
    if (trimmed.toLowerCase().startsWith('db.')) {
      return _detectMongoQueryType(trimmed);
    }
    final normalized = trimmed.toUpperCase();
    if (normalized.startsWith('SELECT')) return 'SELECT';
    if (normalized.startsWith('INSERT')) return 'INSERT';
    if (normalized.startsWith('UPDATE')) return 'UPDATE';
    if (normalized.startsWith('DELETE')) return 'DELETE';
    if (normalized.startsWith('CREATE')) return 'CREATE';
    if (normalized.startsWith('ALTER')) return 'ALTER';
    if (normalized.startsWith('DROP')) return 'DROP';
    if (normalized.startsWith('EXPLAIN')) return 'EXPLAIN';
    return null;
  }

  /// Mongo 方法名 → 查询类型映射（US4）。见 contracts/history-extraction.md §2。
  String? _detectMongoQueryType(String sql) {
    final m = RegExp(r'db\.[A-Za-z0-9_]+\.([A-Za-z0-9_]+)').firstMatch(sql);
    if (m == null) return null;
    switch (m.group(1)!.toLowerCase()) {
      case 'find':
      case 'findone':
      case 'count':
      case 'countdocuments':
      case 'estimateddocumentcount':
      case 'distinct':
        return 'find';
      case 'aggregate':
        return 'aggregate';
      case 'insertone':
      case 'insertmany':
        return 'insert';
      case 'updateone':
      case 'updatemany':
      case 'replaceone':
      case 'findoneandupdate':
      case 'findoneandreplace':
        return 'update';
      case 'deleteone':
      case 'deletemany':
      case 'findoneanddelete':
        return 'delete';
      default:
        return null;
    }
  }

  QueryRecord copyWith({
    String? id,
    String? sqlStatement,
    String? connectionId,
    String? connectionName,
    String? databaseType,
    String? databaseName,
    int? executionTimeMs,
    int? rowCount,
    bool? isSuccess,
    String? errorMessage,
    DateTime? createdAt,
    bool? isFavorite,
    List<String>? tags,
    String? queryType,
  }) {
    return QueryRecord(
      id: id ?? this.id,
      sqlStatement: sqlStatement ?? this.sqlStatement,
      connectionId: connectionId ?? this.connectionId,
      connectionName: connectionName ?? this.connectionName,
      databaseType: databaseType ?? this.databaseType,
      databaseName: databaseName ?? this.databaseName,
      executionTimeMs: executionTimeMs ?? this.executionTimeMs,
      rowCount: rowCount ?? this.rowCount,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      tags: tags ?? this.tags,
      queryType: queryType ?? this.queryType,
    );
  }

  static List<String> parseTags(String? tagsString) {
    if (tagsString == null || tagsString.isEmpty) return [];
    return tagsString.split(',').where((t) => t.isNotEmpty).toList();
  }
}

/// 搜索条件模型
@immutable
class SearchCriteria {
  final String? keywords;
  final String? tableFilter;
  final String? connectionId;
  final String? databaseType;
  final DateTime? after;
  final DateTime? before;
  final bool? isFavorite;
  final List<String>? tags;
  final String? queryType;
  final int limit;
  final int offset;

  const SearchCriteria({
    this.keywords,
    this.tableFilter,
    this.connectionId,
    this.databaseType,
    this.after,
    this.before,
    this.isFavorite,
    this.tags,
    this.queryType,
    this.limit = 50,
    this.offset = 0,
  });

  bool get isEmpty =>
      keywords == null &&
      tableFilter == null &&
      connectionId == null &&
      databaseType == null &&
      after == null &&
      before == null &&
      isFavorite == null &&
      tags == null &&
      queryType == null;
}

/// 查询推荐结果
@immutable
class QueryRecommendation {
  final QueryRecord record;
  final double similarity;
  final String reason;

  const QueryRecommendation({
    required this.record,
    required this.similarity,
    required this.reason,
  });
}
