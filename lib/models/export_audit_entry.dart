import 'package:flutter/foundation.dart';

/// R4: 导出审计日志条目。
///
/// 记录每次结果导出的元信息（不记 PII 明文，只记处理方式）。
/// 与查询审计 [AuditLogEntry] 独立存储，互不影响。
@immutable
class ExportAuditEntry {
  final String id;
  final DateTime timestamp;
  /// 源查询 SQL（脱敏后，不含 PII 明文）
  final String? sourceSql;
  /// 导出格式（csv/json/excel）
  final String format;
  /// 导出行数
  final int rowCount;
  /// 列名 → 脱敏动作（keep/mask/hash/drop），不含值
  final Map<String, String> columnActions;

  const ExportAuditEntry({
    required this.id,
    required this.timestamp,
    this.sourceSql,
    required this.format,
    required this.rowCount,
    this.columnActions = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'sourceSql': sourceSql,
        'format': format,
        'rowCount': rowCount,
        'columnActions': columnActions,
      };

  factory ExportAuditEntry.fromJson(Map<String, dynamic> json) {
    return ExportAuditEntry(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      sourceSql: json['sourceSql'] as String?,
      format: json['format'] as String,
      rowCount: json['rowCount'] as int,
      columnActions: (json['columnActions'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
    );
  }
}
