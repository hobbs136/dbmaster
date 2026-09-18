/// Performance analysis models
/// Data models for performance tracking and analysis
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Slow query model - 慢查询
class SlowQuery {
  final String query;
  final double executionTime;
  final DateTime timestamp;
  final String database;
  final String? executionPlan;
  final int? rowsExamined;
  final int? rowsSent;
  final String? user;
  final String? host;

  SlowQuery({
    required this.query,
    required this.executionTime,
    required this.timestamp,
    required this.database,
    this.executionPlan,
    this.rowsExamined,
    this.rowsSent,
    this.user,
    this.host,
  });

  factory SlowQuery.fromMap(Map<String, dynamic> map) {
    return SlowQuery(
      query: map['sql_text']?.toString() ?? '',
      executionTime:
          double.tryParse(map['query_time']?.toString() ?? '0') ?? 0.0,
      timestamp: map['start_time'] != null
          ? DateTime.parse(map['start_time'].toString())
          : DateTime.now(),
      database: map['db']?.toString() ?? '',
      executionPlan: map['execution_plan']?.toString(),
      rowsExamined: int.tryParse(map['rows_examined']?.toString() ?? '0'),
      rowsSent: int.tryParse(map['rows_sent']?.toString() ?? '0'),
      user: map['user_host']?.toString(),
      host: map['host']?.toString(),
    );
  }

  String get executionTimeFormatted {
    if (executionTime < 1) {
      return '${(executionTime * 1000).toStringAsFixed(2)} ms';
    }
    return '${executionTime.toStringAsFixed(2)} s';
  }
}

/// Index usage model - 索引使用统计
class IndexUsage {
  final String tableName;
  final String indexName;
  final int usageCount;
  final bool isUsed;
  final int? cardinality;
  final bool isUnique;
  final bool isPrimary;
  final List<String> columns;
  final int? sizeBytes;

  IndexUsage({
    required this.tableName,
    required this.indexName,
    required this.usageCount,
    required this.isUsed,
    this.cardinality,
    this.isUnique = false,
    this.isPrimary = false,
    this.columns = const [],
    this.sizeBytes,
  });

  factory IndexUsage.fromMap(Map<String, dynamic> map) {
    final columns = map['column_list']?.toString().split(',') ?? [];
    return IndexUsage(
      tableName: map['TABLE_NAME']?.toString() ?? '',
      indexName: map['INDEX_NAME']?.toString() ?? '',
      usageCount: int.tryParse(map['usage_count']?.toString() ?? '0') ?? 0,
      isUsed: (int.tryParse(map['usage_count']?.toString() ?? '0') ?? 0) > 0,
      cardinality: int.tryParse(map['CARDINALITY']?.toString() ?? '0'),
      isUnique: map['NON_UNIQUE']?.toString() == '0',
      isPrimary: map['INDEX_NAME']?.toString() == 'PRIMARY',
      columns: columns,
      sizeBytes: int.tryParse(map['index_size']?.toString() ?? '0'),
    );
  }

  String get sizeFormatted {
    if (sizeBytes == null) return 'N/A';
    return _formatBytes(sizeBytes!);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Table statistics model - 表统计信息
class TableStatistics {
  final String tableName;
  final int rowCount;
  final int dataSize;
  final int indexSize;
  final DateTime lastUpdate;
  final String? engine;
  final String? collation;
  final int? autoIncrement;
  final DateTime? createTime;
  final int? avgRowLength;

  TableStatistics({
    required this.tableName,
    required this.rowCount,
    required this.dataSize,
    required this.indexSize,
    required this.lastUpdate,
    this.engine,
    this.collation,
    this.autoIncrement,
    this.createTime,
    this.avgRowLength,
  });

  factory TableStatistics.fromMap(Map<String, dynamic> map) {
    return TableStatistics(
      tableName: map['TABLE_NAME']?.toString() ?? '',
      rowCount: int.tryParse(map['TABLE_ROWS']?.toString() ?? '0') ?? 0,
      dataSize: int.tryParse(map['DATA_LENGTH']?.toString() ?? '0') ?? 0,
      indexSize: int.tryParse(map['INDEX_LENGTH']?.toString() ?? '0') ?? 0,
      lastUpdate: map['UPDATE_TIME'] != null
          ? DateTime.parse(map['UPDATE_TIME'].toString())
          : DateTime.now(),
      engine: map['ENGINE']?.toString(),
      collation: map['TABLE_COLLATION']?.toString(),
      autoIncrement: int.tryParse(map['AUTO_INCREMENT']?.toString() ?? '0'),
      createTime: map['CREATE_TIME'] != null
          ? DateTime.parse(map['CREATE_TIME'].toString())
          : null,
      avgRowLength: int.tryParse(map['AVG_ROW_LENGTH']?.toString() ?? '0'),
    );
  }

  int get totalSize => dataSize + indexSize;

  String get dataSizeFormatted => _formatBytes(dataSize);
  String get indexSizeFormatted => _formatBytes(indexSize);
  String get totalSizeFormatted => _formatBytes(totalSize);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Performance report model - 性能报告
class PerformanceReport {
  final DateTime generatedAt;
  final String databaseName;
  final List<TableStatistics> tableStats;
  final List<IndexUsage> indexUsage;
  final List<SlowQuery> slowQueries;
  final List<PerformanceSuggestion> suggestions;
  final DatabaseSummary summary;

  PerformanceReport({
    required this.generatedAt,
    required this.databaseName,
    required this.tableStats,
    required this.indexUsage,
    required this.slowQueries,
    required this.suggestions,
    required this.summary,
  });

  Map<String, dynamic> toJson() {
    return {
      'generatedAt': generatedAt.toIso8601String(),
      'databaseName': databaseName,
      'tableCount': tableStats.length,
      'totalRows': summary.totalRows,
      'totalDataSize': summary.totalDataSize,
      'totalIndexSize': summary.totalIndexSize,
      'slowQueryCount': slowQueries.length,
      'suggestionCount': suggestions.length,
    };
  }
}

/// Database summary model - 数据库汇总
class DatabaseSummary {
  final int totalRows;
  final int totalDataSize;
  final int totalIndexSize;
  final int tableCount;
  final int indexCount;
  final double? avgQueriesPerSecond;
  final double? avgConnections;

  DatabaseSummary({
    this.totalRows = 0,
    this.totalDataSize = 0,
    this.totalIndexSize = 0,
    this.tableCount = 0,
    this.indexCount = 0,
    this.avgQueriesPerSecond,
    this.avgConnections,
  });

  factory DatabaseSummary.fromMap(Map<String, dynamic> map) {
    return DatabaseSummary(
      totalRows: int.tryParse(map['total_rows']?.toString() ?? '0') ?? 0,
      totalDataSize: int.tryParse(map['total_data']?.toString() ?? '0') ?? 0,
      totalIndexSize: int.tryParse(map['total_index']?.toString() ?? '0') ?? 0,
      tableCount: int.tryParse(map['table_count']?.toString() ?? '0') ?? 0,
      indexCount: int.tryParse(map['index_count']?.toString() ?? '0') ?? 0,
      avgQueriesPerSecond: double.tryParse(
        map['queries_per_sec']?.toString() ?? '0',
      ),
      avgConnections: double.tryParse(
        map['avg_connections']?.toString() ?? '0',
      ),
    );
  }

  int get totalSize => totalDataSize + totalIndexSize;

  String get totalDataSizeFormatted => _formatBytes(totalDataSize);
  String get totalIndexSizeFormatted => _formatBytes(totalIndexSize);
  String get totalSizeFormatted => _formatBytes(totalSize);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Performance suggestion model - 性能优化建议
class PerformanceSuggestion {
  final String type; // 'index', 'query', 'table', 'configuration', 'general'
  final String title;
  final String description;
  final String impact; // 'high', 'medium', 'low'
  final String? sql;
  final List<String> affectedTables;
  final String? recommendation;

  PerformanceSuggestion({
    required this.type,
    required this.title,
    required this.description,
    required this.impact,
    this.sql,
    required this.affectedTables,
    this.recommendation,
  });

  factory PerformanceSuggestion.fromMap(Map<String, dynamic> map) {
    return PerformanceSuggestion(
      type: map['type']?.toString() ?? 'general',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      impact: map['impact']?.toString() ?? 'medium',
      sql: map['sql']?.toString(),
      affectedTables:
          (map['affected_tables'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      recommendation: map['recommendation']?.toString(),
    );
  }

  Color get impactColor {
    switch (impact) {
      case 'high':
        return const Color(0xFFFF5C5C); // terminal-red
      case 'medium':
        return const Color(0xFFFF8A30); // terminal-yellow
      case 'low':
        return const Color(0xFF46BF72); // terminal-green
      default:
        return const Color(0xFF8F8F8F); // neutral-500
    }
  }

  IconData get typeIcon {
    switch (type) {
      case 'index':
        return LucideIcons.database;
      case 'query':
        return LucideIcons.code;
      case 'table':
        return LucideIcons.table2;
      case 'configuration':
        return LucideIcons.settings;
      default:
        return LucideIcons.lightbulb;
    }
  }
}

/// Chart data model for fl_chart - 图表数据
class ChartData {
  final String label;
  final double value;
  final Color? color;

  ChartData({required this.label, required this.value, this.color});
}

/// Query execution plan model - 查询执行计划
class QueryExecutionPlan {
  final int id;
  final String selectType;
  final String table;
  final String type;
  final String? possibleKeys;
  final String? key;
  final String? keyLen;
  final String? ref;
  final int? rows;
  final String? extra;

  QueryExecutionPlan({
    required this.id,
    required this.selectType,
    required this.table,
    required this.type,
    this.possibleKeys,
    this.key,
    this.keyLen,
    this.ref,
    this.rows,
    this.extra,
  });

  factory QueryExecutionPlan.fromMap(Map<String, dynamic> map) {
    return QueryExecutionPlan(
      id: int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      selectType: map['select_type']?.toString() ?? '',
      table: map['table']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      possibleKeys: map['possible_keys']?.toString(),
      key: map['key']?.toString(),
      keyLen: map['key_len']?.toString(),
      ref: map['ref']?.toString(),
      rows: int.tryParse(map['rows']?.toString() ?? '0'),
      extra: map['Extra']?.toString(),
    );
  }

  bool get isUsingIndex => key != null && key!.isNotEmpty;
  bool get isFullTableScan => type == 'ALL';
}

/// Index statistics model (legacy compatibility) - 索引统计（兼容旧版本）
class IndexStatistics {
  final String database;
  final String table;
  final String indexName;
  final bool nonUnique;
  final String keyName;
  final int seqInIndex;
  final String columnName;
  final String collation;
  final int? cardinality;
  final String? subPart;
  final bool? packed;
  final String? indexType;

  IndexStatistics({
    required this.database,
    required this.table,
    required this.indexName,
    required this.nonUnique,
    required this.keyName,
    required this.seqInIndex,
    required this.columnName,
    required this.collation,
    this.cardinality,
    this.subPart,
    this.packed,
    this.indexType,
  });

  bool get isPrimary => indexName == 'PRIMARY';
  bool get isUnique => !nonUnique && indexName != 'PRIMARY';

  factory IndexStatistics.fromMap(Map<String, dynamic> map) {
    return IndexStatistics(
      database: map['TABLE_SCHEMA'] as String,
      table: map['TABLE_NAME'] as String,
      indexName: map['INDEX_NAME'] as String,
      nonUnique: (map['NON_UNIQUE'] as int) == 1,
      keyName: map['KEY_NAME'] as String,
      seqInIndex: map['SEQ_IN_INDEX'] as int,
      columnName: map['COLUMN_NAME'] as String,
      collation: map['COLLATION'] as String? ?? 'A',
      cardinality: int.tryParse(map['CARDINALITY']?.toString() ?? ''),
      subPart: map['SUB_PART']?.toString(),
      packed: map['PACKED'] != null ? (map['PACKED'] as int) == 1 : null,
      indexType: map['INDEX_TYPE']?.toString(),
    );
  }
}
