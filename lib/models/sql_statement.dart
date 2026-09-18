import 'package:flutter/foundation.dart';

/// SQL statement type enumeration
enum SQLType { select, insert, update, delete, ddl, call, other }

@immutable
class SQLStatement {
  final int index;
  final String sql;
  final SQLType type;
  final int lineStart;
  final int lineEnd;

  const SQLStatement({
    required this.index,
    required this.sql,
    required this.type,
    required this.lineStart,
    required this.lineEnd,
  });

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'sql': sql,
      'type': type.name,
      'lineStart': lineStart,
      'lineEnd': lineEnd,
    };
  }

  factory SQLStatement.fromJson(Map<String, dynamic> json) {
    return SQLStatement(
      index: (json['index'] as num?)?.toInt() ?? 0,
      sql: json['sql'] as String? ?? '',
      type: SQLType.values.byName(json['type'] as String? ?? 'other'),
      lineStart: (json['lineStart'] as num?)?.toInt() ?? 0,
      lineEnd: (json['lineEnd'] as num?)?.toInt() ?? 0,
    );
  }

  SQLStatement copyWith({
    int? index,
    String? sql,
    SQLType? type,
    int? lineStart,
    int? lineEnd,
  }) {
    return SQLStatement(
      index: index ?? this.index,
      sql: sql ?? this.sql,
      type: type ?? this.type,
      lineStart: lineStart ?? this.lineStart,
      lineEnd: lineEnd ?? this.lineEnd,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SQLStatement &&
        other.index == index &&
        other.sql == sql &&
        other.type == type &&
        other.lineStart == lineStart &&
        other.lineEnd == lineEnd;
  }

  @override
  int get hashCode => Object.hash(index, sql, type, lineStart, lineEnd);

  @override
  String toString() {
    return 'SQLStatement(index: $index, type: $type, lines: $lineStart-$lineEnd, sql: ${sql.substring(0, sql.length > 50 ? 50 : sql.length)}...)';
  }
}
