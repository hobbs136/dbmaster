import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class BackupFile {
  final String id;
  final String name;
  final String type; // 'sql', 'json', 'csv'
  final int size;
  final DateTime createdAt;
  final String database;
  final List<String> tables;
  final String? description;
  final String? connectionId;

  BackupFile({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    required this.createdAt,
    required this.database,
    required this.tables,
    this.description,
    this.connectionId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'size': size,
      'createdAt': createdAt.toIso8601String(),
      'database': database,
      'tables': tables,
      'description': description,
      'connectionId': connectionId,
    };
  }

  factory BackupFile.fromJson(Map<String, dynamic> json) {
    return BackupFile(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      size: json['size'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      database: json['database'] as String,
      tables: (json['tables'] as List<dynamic>).cast<String>(),
      description: json['description'] as String?,
      connectionId: json['connectionId'] as String?,
    );
  }

  String get sizeFormatted {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / 1024 / 1024).toStringAsFixed(2)}MB';
  }

  String get typeDisplay {
    switch (type.toLowerCase()) {
      case 'sql':
        return 'SQL 脚本';
      case 'json':
        return 'JSON 数据';
      case 'csv':
        return 'CSV 数据';
      default:
        return type.toUpperCase();
    }
  }

  IconData get typeIcon {
    switch (type.toLowerCase()) {
      case 'sql':
        return LucideIcons.code;
      case 'json':
        return LucideIcons.braces;
      case 'csv':
        return LucideIcons.table2;
      default:
        return LucideIcons.file;
    }
  }

  BackupFile copyWith({
    String? id,
    String? name,
    String? type,
    int? size,
    DateTime? createdAt,
    String? database,
    List<String>? tables,
    String? description,
    String? connectionId,
  }) {
    return BackupFile(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      size: size ?? this.size,
      createdAt: createdAt ?? this.createdAt,
      database: database ?? this.database,
      tables: tables ?? this.tables,
      description: description ?? this.description,
      connectionId: connectionId ?? this.connectionId,
    );
  }
}

class BackupOptions {
  final bool includeStructure;
  final bool includeData;
  final List<String> tables;
  final String format; // 'sql', 'json', 'csv'
  final String? description;
  final bool addDropTable;
  final bool addIfNotExists;
  final bool completeInsert;
  final bool extendedInsert;
  final String? whereClause;
  final int? limit;

  BackupOptions({
    this.includeStructure = true,
    this.includeData = true,
    this.tables = const [],
    this.format = 'sql',
    this.description,
    this.addDropTable = true,
    this.addIfNotExists = true,
    this.completeInsert = false,
    this.extendedInsert = true,
    this.whereClause,
    this.limit,
  });

  Map<String, dynamic> toJson() {
    return {
      'includeStructure': includeStructure,
      'includeData': includeData,
      'tables': tables,
      'format': format,
      'description': description,
      'addDropTable': addDropTable,
      'addIfNotExists': addIfNotExists,
      'completeInsert': completeInsert,
      'extendedInsert': extendedInsert,
      'whereClause': whereClause,
      'limit': limit,
    };
  }

  factory BackupOptions.fromJson(Map<String, dynamic> json) {
    return BackupOptions(
      includeStructure: json['includeStructure'] as bool? ?? true,
      includeData: json['includeData'] as bool? ?? true,
      tables: (json['tables'] as List<dynamic>?)?.cast<String>() ?? [],
      format: json['format'] as String? ?? 'sql',
      description: json['description'] as String?,
      addDropTable: json['addDropTable'] as bool? ?? true,
      addIfNotExists: json['addIfNotExists'] as bool? ?? true,
      completeInsert: json['completeInsert'] as bool? ?? false,
      extendedInsert: json['extendedInsert'] as bool? ?? true,
      whereClause: json['whereClause'] as String?,
      limit: json['limit'] as int?,
    );
  }

  BackupOptions copyWith({
    bool? includeStructure,
    bool? includeData,
    List<String>? tables,
    String? format,
    String? description,
    bool? addDropTable,
    bool? addIfNotExists,
    bool? completeInsert,
    bool? extendedInsert,
    String? whereClause,
    int? limit,
  }) {
    return BackupOptions(
      includeStructure: includeStructure ?? this.includeStructure,
      includeData: includeData ?? this.includeData,
      tables: tables ?? this.tables,
      format: format ?? this.format,
      description: description ?? this.description,
      addDropTable: addDropTable ?? this.addDropTable,
      addIfNotExists: addIfNotExists ?? this.addIfNotExists,
      completeInsert: completeInsert ?? this.completeInsert,
      extendedInsert: extendedInsert ?? this.extendedInsert,
      whereClause: whereClause ?? this.whereClause,
      limit: limit ?? this.limit,
    );
  }
}

class ImportOptions {
  final String format; // 'sql', 'json', 'csv'
  final bool incremental; // 增量导入
  final bool skipErrors; // 跳过错误
  final bool truncateBeforeImport; // 导入前清空表
  final String? targetTable; // 目标表（CSV/JSON 需要）
  final List<String>? columnMapping; // 列映射
  final String? charset; // 字符集

  ImportOptions({
    this.format = 'sql',
    this.incremental = false,
    this.skipErrors = false,
    this.truncateBeforeImport = false,
    this.targetTable,
    this.columnMapping,
    this.charset = 'utf8mb4',
  });

  Map<String, dynamic> toJson() {
    return {
      'format': format,
      'incremental': incremental,
      'skipErrors': skipErrors,
      'truncateBeforeImport': truncateBeforeImport,
      'targetTable': targetTable,
      'columnMapping': columnMapping,
      'charset': charset,
    };
  }

  factory ImportOptions.fromJson(Map<String, dynamic> json) {
    return ImportOptions(
      format: json['format'] as String? ?? 'sql',
      incremental: json['incremental'] as bool? ?? false,
      skipErrors: json['skipErrors'] as bool? ?? false,
      truncateBeforeImport: json['truncateBeforeImport'] as bool? ?? false,
      targetTable: json['targetTable'] as String?,
      columnMapping: (json['columnMapping'] as List<dynamic>?)?.cast<String>(),
      charset: json['charset'] as String? ?? 'utf8mb4',
    );
  }
}

class BackupProgress {
  final String status; // 'idle', 'running', 'completed', 'error'
  final double progress; // 0.0 - 1.0
  final String currentTable;
  final int processedRows;
  final int totalRows;
  final String? error;

  BackupProgress({
    this.status = 'idle',
    this.progress = 0.0,
    this.currentTable = '',
    this.processedRows = 0,
    this.totalRows = 0,
    this.error,
  });

  BackupProgress copyWith({
    String? status,
    double? progress,
    String? currentTable,
    int? processedRows,
    int? totalRows,
    String? error,
  }) {
    return BackupProgress(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      currentTable: currentTable ?? this.currentTable,
      processedRows: processedRows ?? this.processedRows,
      totalRows: totalRows ?? this.totalRows,
      error: error ?? this.error,
    );
  }
}
