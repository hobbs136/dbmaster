import 'package:flutter/foundation.dart';

/// Represents a single query audit log entry
@immutable
class AuditLogEntry {
  final String id;
  final DateTime timestamp;
  final String connectionId;
  final String? connectionName;
  final String? databaseName;
  final String sql;
  final Duration executionTime;
  final int? rowCount;
  final bool success;
  final String? errorMessage;
  final bool isWriteQuery;

  const AuditLogEntry({
    required this.id,
    required this.timestamp,
    required this.connectionId,
    this.connectionName,
    this.databaseName,
    required this.sql,
    required this.executionTime,
    this.rowCount,
    required this.success,
    this.errorMessage,
    this.isWriteQuery = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'connectionId': connectionId,
    'connectionName': connectionName,
    'databaseName': databaseName,
    'sql': sql,
    'executionTimeMs': executionTime.inMilliseconds,
    'rowCount': rowCount,
    'success': success,
    'errorMessage': errorMessage,
    'isWriteQuery': isWriteQuery,
  };

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      connectionId: json['connectionId'] as String,
      connectionName: json['connectionName'] as String?,
      databaseName: json['databaseName'] as String?,
      sql: json['sql'] as String,
      executionTime: Duration(milliseconds: json['executionTimeMs'] as int),
      rowCount: json['rowCount'] as int?,
      success: json['success'] as bool,
      errorMessage: json['errorMessage'] as String?,
      isWriteQuery: json['isWriteQuery'] as bool? ?? false,
    );
  }

  AuditLogEntry copyWith({
    String? id,
    DateTime? timestamp,
    String? connectionId,
    String? connectionName,
    String? databaseName,
    String? sql,
    Duration? executionTime,
    int? rowCount,
    bool? success,
    String? errorMessage,
    bool? isWriteQuery,
  }) {
    return AuditLogEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      connectionId: connectionId ?? this.connectionId,
      connectionName: connectionName ?? this.connectionName,
      databaseName: databaseName ?? this.databaseName,
      sql: sql ?? this.sql,
      executionTime: executionTime ?? this.executionTime,
      rowCount: rowCount ?? this.rowCount,
      success: success ?? this.success,
      errorMessage: errorMessage ?? this.errorMessage,
      isWriteQuery: isWriteQuery ?? this.isWriteQuery,
    );
  }
}
