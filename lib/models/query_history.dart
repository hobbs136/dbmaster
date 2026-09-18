import 'database_models.dart' show DatabaseType;

/// 查询历史来源
enum QueryHistorySource {
  /// 通过执行查询自动记录
  executed,

  /// 通过 Ctrl+S 手动保存
  saved,
}

class QueryHistory {
  final String id;
  final String sql;
  final DateTime timestamp;
  final DateTime? updatedAt;
  final String? database;
  final DatabaseType? databaseType;
  final String connectionId;
  final String? connectionName;
  final int executionTime;
  final int affectedRows;
  final String? error;
  final String? displayTitle;
  final QueryHistorySource source;

  // -------------------------------------------------------------------------
  // Equality (based on id)
  // -------------------------------------------------------------------------
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryHistory &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  QueryHistory({
    required this.id,
    required this.sql,
    required this.timestamp,
    this.updatedAt,
    this.database,
    this.databaseType,
    this.connectionId = '',
    this.connectionName,
    this.executionTime = 0,
    this.affectedRows = 0,
    this.error,
    this.displayTitle,
    this.source = QueryHistorySource.executed,
  });

  QueryHistory copyWith({
    String? id,
    String? sql,
    DateTime? timestamp,
    DateTime? updatedAt,
    String? database,
    DatabaseType? databaseType,
    String? connectionId,
    String? connectionName,
    int? executionTime,
    int? affectedRows,
    String? error,
    String? displayTitle,
    QueryHistorySource? source,
  }) {
    return QueryHistory(
      id: id ?? this.id,
      sql: sql ?? this.sql,
      timestamp: timestamp ?? this.timestamp,
      updatedAt: updatedAt ?? this.updatedAt,
      database: database ?? this.database,
      databaseType: databaseType ?? this.databaseType,
      connectionId: connectionId ?? this.connectionId,
      connectionName: connectionName ?? this.connectionName,
      executionTime: executionTime ?? this.executionTime,
      affectedRows: affectedRows ?? this.affectedRows,
      error: error ?? this.error,
      displayTitle: displayTitle ?? this.displayTitle,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sql': sql,
    'timestamp': timestamp.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'database': database,
    'databaseType': databaseType?.name,
    'connectionId': connectionId,
    'connectionName': connectionName,
    'executionTime': executionTime,
    'affectedRows': affectedRows,
    'error': error,
    'displayTitle': displayTitle,
    'source': source.name,
  };

  factory QueryHistory.fromJson(Map<String, dynamic> json) {
    DatabaseType? dbType;
    final typeStr = json['databaseType'] as String?;
    if (typeStr != null) {
      try {
        dbType = DatabaseType.values.firstWhere((e) => e.name == typeStr);
      } catch (_) {
        dbType = null;
      }
    }

    QueryHistorySource source;
    final sourceStr = json['source'] as String?;
    if (sourceStr != null) {
      try {
        source = QueryHistorySource.values.firstWhere(
          (e) => e.name == sourceStr,
        );
      } catch (_) {
        source = QueryHistorySource.executed;
      }
    } else {
      source = QueryHistorySource.executed;
    }

    return QueryHistory(
      id: json['id'] as String? ?? '',
      sql: json['sql'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
      database: json['database'] as String?,
      databaseType: dbType,
      connectionId: json['connectionId'] as String? ?? '',
      connectionName: json['connectionName'] as String?,
      executionTime: json['executionTime'] as int? ?? 0,
      affectedRows: json['affectedRows'] as int? ?? 0,
      error: json['error'] as String?,
      displayTitle: json['displayTitle'] as String?,
      source: source,
    );
  }
}
