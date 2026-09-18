import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 任务类型
enum TaskType { import, export, query, dataSync }

/// 任务状态
enum TaskStatus { pending, running, paused, completed, failed, cancelled }

/// 导出格式
enum ExportFormat { csv, json, sql, excel }

/// 导入格式
enum ImportFormat { csv, json, excel }

/// 任务日志
class TaskLog {
  final DateTime timestamp;
  final String message;
  final LogLevel level;

  TaskLog({
    required this.timestamp,
    required this.message,
    this.level = LogLevel.info,
  });

  factory TaskLog.info(String message) => TaskLog(
    timestamp: DateTime.now(),
    message: message,
    level: LogLevel.info,
  );

  factory TaskLog.warning(String message) => TaskLog(
    timestamp: DateTime.now(),
    message: message,
    level: LogLevel.warning,
  );

  factory TaskLog.error(String message) => TaskLog(
    timestamp: DateTime.now(),
    message: message,
    level: LogLevel.error,
  );

  factory TaskLog.success(String message) => TaskLog(
    timestamp: DateTime.now(),
    message: message,
    level: LogLevel.success,
  );
}

enum LogLevel { info, warning, error, success }

/// 任务配置基类
abstract class TaskConfig {
  final String connectionId;
  final String? databaseName;
  final String description;

  TaskConfig({
    required this.connectionId,
    this.databaseName,
    required this.description,
  });

  Map<String, dynamic> toJson();
}

/// 导入任务配置
class ImportTaskConfig extends TaskConfig {
  final String filePath;
  final String targetTable;
  final ImportFormat format;
  final bool hasHeader;
  final String delimiter;
  final bool createTableIfNotExists;
  final String? createTableSQL;

  ImportTaskConfig({
    required super.connectionId,
    super.databaseName,
    required super.description,
    required this.filePath,
    required this.targetTable,
    required this.format,
    this.hasHeader = true,
    this.delimiter = ',',
    this.createTableIfNotExists = false,
    this.createTableSQL,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'import',
    'connectionId': connectionId,
    'databaseName': databaseName,
    'description': description,
    'filePath': filePath,
    'targetTable': targetTable,
    'format': format.name,
    'hasHeader': hasHeader,
    'delimiter': delimiter,
    'createTableIfNotExists': createTableIfNotExists,
    'createTableSQL': createTableSQL,
  };
}

/// 导出任务配置
class ExportTaskConfig extends TaskConfig {
  final String tableName;
  final String outputPath;
  final ExportFormat format;
  final String? whereClause;
  final int? limit;
  final String? orderBy;
  final bool includeHeader;
  final String encoding;

  ExportTaskConfig({
    required super.connectionId,
    super.databaseName,
    required super.description,
    required this.tableName,
    required this.outputPath,
    required this.format,
    this.whereClause,
    this.limit,
    this.orderBy,
    this.includeHeader = true,
    this.encoding = 'utf-8',
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'export',
    'connectionId': connectionId,
    'databaseName': databaseName,
    'description': description,
    'tableName': tableName,
    'outputPath': outputPath,
    'format': format.name,
    'whereClause': whereClause,
    'limit': limit,
    'orderBy': orderBy,
    'includeHeader': includeHeader,
    'encoding': encoding,
  };
}

/// 数据同步任务配置
class DataSyncTaskConfig extends TaskConfig {
  final String sourceConnectionId;
  final String sourceDatabase;
  final String sourceTable;
  final String targetConnectionId;
  final String targetDatabase;
  final String targetTable;
  final String segmentField;
  final String segmentType; // 'time' | 'numeric'
  final String? timeUnit; // 'minute' | 'hour' | 'day'
  final int? timeInterval;
  final int? numericSegmentSize;
  final int pageSize;
  final String targetStrategy; // 'truncate' | 'append' | 'replace' | 'upsert'
  final int segmentIntervalMs;
  final int pageIntervalMs;

  DataSyncTaskConfig({
    required super.connectionId,
    super.databaseName,
    required super.description,
    required this.sourceConnectionId,
    required this.sourceDatabase,
    required this.sourceTable,
    required this.targetConnectionId,
    required this.targetDatabase,
    required this.targetTable,
    required this.segmentField,
    required this.segmentType,
    this.timeUnit,
    this.timeInterval,
    this.numericSegmentSize,
    this.pageSize = 1000,
    this.targetStrategy = 'append',
    this.segmentIntervalMs = 0,
    this.pageIntervalMs = 0,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'dataSync',
    'connectionId': connectionId,
    'databaseName': databaseName,
    'description': description,
    'sourceConnectionId': sourceConnectionId,
    'sourceDatabase': sourceDatabase,
    'sourceTable': sourceTable,
    'targetConnectionId': targetConnectionId,
    'targetDatabase': targetDatabase,
    'targetTable': targetTable,
    'segmentField': segmentField,
    'segmentType': segmentType,
    'timeUnit': timeUnit,
    'timeInterval': timeInterval,
    'numericSegmentSize': numericSegmentSize,
    'pageSize': pageSize,
    'targetStrategy': targetStrategy,
    'segmentIntervalMs': segmentIntervalMs,
    'pageIntervalMs': pageIntervalMs,
  };
}

/// 查询任务配置
class QueryTaskConfig extends TaskConfig {
  final String sql;
  final bool saveToFile;
  final String? outputPath;
  final ExportFormat? outputFormat;

  QueryTaskConfig({
    required super.connectionId,
    super.databaseName,
    required super.description,
    required this.sql,
    this.saveToFile = false,
    this.outputPath,
    this.outputFormat,
  });

  @override
  Map<String, dynamic> toJson() => {
    'type': 'query',
    'connectionId': connectionId,
    'databaseName': databaseName,
    'description': description,
    'sql': sql,
    'saveToFile': saveToFile,
    'outputPath': outputPath,
    'outputFormat': outputFormat?.name,
  };
}

/// 数据库任务
class DbTask {
  final String id;
  final TaskType type;
  final TaskConfig config;
  TaskStatus status;
  final DateTime createdAt;
  DateTime? startedAt;
  DateTime? completedAt;
  int progress; // 0-100
  String? currentPhase;
  String? errorMessage;
  int? totalRows;
  int? processedRows;
  int? affectedRows;
  String? outputPath;
  final List<TaskLog> logs;
  bool _isCancelled;

  DbTask({
    required this.id,
    required this.type,
    required this.config,
    this.status = TaskStatus.pending,
    DateTime? createdAt,
    this.startedAt,
    this.completedAt,
    this.progress = 0,
    this.currentPhase,
    this.errorMessage,
    this.totalRows,
    this.processedRows,
    this.affectedRows,
    this.outputPath,
    List<TaskLog>? logs,
  }) : createdAt = createdAt ?? DateTime.now(),
       logs = logs ?? [],
       _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() => _isCancelled = true;

  void reset() => _isCancelled = false;

  void addLog(TaskLog log) {
    logs.add(log);
  }

  void addInfo(String message) => addLog(TaskLog.info(message));
  void addWarning(String message) => addLog(TaskLog.warning(message));
  void addError(String message) => addLog(TaskLog.error(message));
  void addSuccess(String message) => addLog(TaskLog.success(message));

  String get displayName => config.description;

  String get typeLabel {
    switch (type) {
      case TaskType.import:
        return '导入';
      case TaskType.export:
        return '导出';
      case TaskType.query:
        return '查询';
      case TaskType.dataSync:
        return '数据同步';
    }
  }

  IconData get typeIcon {
    switch (type) {
      case TaskType.import:
        return LucideIcons.fileUp;
      case TaskType.export:
        return LucideIcons.fileDown;
      case TaskType.query:
        return LucideIcons.search;
      case TaskType.dataSync:
        return LucideIcons.refreshCw;
    }
  }

  Color get statusColor {
    switch (status) {
      case TaskStatus.pending:
        return Colors.grey;
      case TaskStatus.running:
        return Colors.blue;
      case TaskStatus.paused:
        return Colors.orange;
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.failed:
        return Colors.red;
      case TaskStatus.cancelled:
        return Colors.grey.shade600;
    }
  }

  String get statusLabel {
    switch (status) {
      case TaskStatus.pending:
        return '等待中';
      case TaskStatus.running:
        return '执行中';
      case TaskStatus.paused:
        return '已暂停';
      case TaskStatus.completed:
        return '已完成';
      case TaskStatus.failed:
        return '失败';
      case TaskStatus.cancelled:
        return '已取消';
    }
  }

  bool get isActive =>
      status == TaskStatus.pending ||
      status == TaskStatus.running ||
      status == TaskStatus.paused;

  bool get isDone =>
      status == TaskStatus.completed ||
      status == TaskStatus.failed ||
      status == TaskStatus.cancelled;

  double? get progressPercent => totalRows != null && totalRows! > 0
      ? ((processedRows ?? 0) / totalRows! * 100).clamp(0, 100)
      : null;

  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'status': status.name,
    'config': config.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'startedAt': startedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'progress': progress,
    'currentPhase': currentPhase,
    'errorMessage': errorMessage,
    'totalRows': totalRows,
    'processedRows': processedRows,
    'affectedRows': affectedRows,
    'outputPath': outputPath,
    'logs': logs
        .map(
          (l) => {
            'timestamp': l.timestamp.toIso8601String(),
            'message': l.message,
            'level': l.level.name,
          },
        )
        .toList(),
  };
}
