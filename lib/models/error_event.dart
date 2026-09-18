import '../utils/secret_redactor.dart';

/// 错误严重级别。
enum ErrorSeverity { error, warning, info }

/// 捕获的错误事件——进入执行中心历史，且可复制 / 一键 AI 分析。
///
/// [message] 保存原始（未脱敏）文本；仅在发送给 AI / 写日志的边界通过
/// [messageForAi] / [messageForLog] 脱敏（spec FR-011 + constitution 安全）。
class ErrorEvent {
  ErrorEvent({
    required this.id,
    required this.timestamp,
    required this.severity,
    required this.message,
    this.tag,
    this.context,
    this.sql,
    this.connectionId,
    this.databaseName,
    this.redactSql = false,
    this.stackTrace,
  });

  final String id;
  final DateTime timestamp;
  final ErrorSeverity severity;

  /// 原始错误文本（未脱敏）。
  final String message;

  /// 来源/组件标签（对应 AppLogger tag，如 'SchemaSync'）。
  final String? tag;

  /// 人可读的操作上下文（如 "Schema Diff sync · db_a → db_b"）。
  final String? context;

  /// 失败的 SQL（若有）。
  final String? sql;

  /// 出错时活动连接 id（供 AI 上下文）。
  final String? connectionId;

  /// 出错时活动数据库（供 AI 上下文）。
  final String? databaseName;

  /// 是否对 SQL 字面量脱敏（用户数据导入等 PII 场景为 true）。
  final bool redactSql;

  /// 可选堆栈（供执行中心展开 / AI 诊断）。
  final String? stackTrace;

  /// 发送给 AI 的脱敏文本（错误 + 可选 SQL）。
  String get messageForAi {
    final buf = StringBuffer(redactSecrets(message));
    final sqlText = sql;
    if (sqlText != null && sqlText.isNotEmpty) {
      buf.write('\n\nSQL:\n${redactSecrets(sqlText, redactSql: redactSql)}');
    }
    return buf.toString();
  }

  /// 写入日志的脱敏文本。
  String get messageForLog => redactSecrets(message);
}
