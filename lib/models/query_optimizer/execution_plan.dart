import 'package:flutter/foundation.dart';

/// 查询执行计划模型
/// 封装 EXPLAIN 输出的结构化数据
@immutable
class ExecutionPlan {
  final String databaseType;
  final String originalQuery;
  final List<PlanStep> steps;
  final Map<String, dynamic> rawData;
  final DateTime analyzedAt;

  const ExecutionPlan({
    required this.databaseType,
    required this.originalQuery,
    required this.steps,
    required this.rawData,
    required this.analyzedAt,
  });

  /// 是否包含全表扫描
  bool get hasFullTableScan =>
      steps.any((step) => step.scanType == ScanType.fullTable);

  /// 预估总行数
  int get totalRows =>
      steps.fold(0, (sum, step) => sum + (step.estimatedRows ?? 0));

  /// 是否使用了临时表
  bool get hasTemporaryTable =>
      steps.any((step) => step.extra?.contains('Using temporary') ?? false);

  /// 是否使用了文件排序
  bool get hasFileSort =>
      steps.any((step) => step.extra?.contains('Using filesort') ?? false);

  /// 获取最昂贵的步骤
  PlanStep? get mostExpensiveStep {
    if (steps.isEmpty) return null;
    return steps.reduce((a, b) => (a.cost ?? 0) > (b.cost ?? 0) ? a : b);
  }

  Map<String, dynamic> toJson() => {
    'databaseType': databaseType,
    'originalQuery': originalQuery,
    'steps': steps.map((s) => s.toJson()).toList(),
    'hasFullTableScan': hasFullTableScan,
    'totalRows': totalRows,
    'hasTemporaryTable': hasTemporaryTable,
    'hasFileSort': hasFileSort,
    'analyzedAt': analyzedAt.toIso8601String(),
  };
}

/// 执行计划中的单一步骤
@immutable
class PlanStep {
  final int? id;
  final String? selectType;
  final String? table;
  final String? partition;
  final ScanType? scanType;
  final String? possibleKeys;
  final String? key;
  final String? keyLen;
  final String? ref;
  final int? estimatedRows;
  final double? cost;
  final double? time;
  final String? extra;
  final String? operation; // PostgreSQL/其他数据库的操作类型

  const PlanStep({
    this.id,
    this.selectType,
    this.table,
    this.partition,
    this.scanType,
    this.possibleKeys,
    this.key,
    this.keyLen,
    this.ref,
    this.estimatedRows,
    this.cost,
    this.time,
    this.extra,
    this.operation,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'selectType': selectType,
    'table': table,
    'partition': partition,
    'scanType': scanType?.name,
    'possibleKeys': possibleKeys,
    'key': key,
    'keyLen': keyLen,
    'ref': ref,
    'estimatedRows': estimatedRows,
    'cost': cost,
    'time': time,
    'extra': extra,
    'operation': operation,
  };
}

/// 扫描类型枚举
enum ScanType {
  fullTable('ALL', 'Full Table Scan', '全表扫描'),
  index_('index', 'Index Scan', '索引扫描'),
  range('range', 'Range Scan', '范围扫描'),
  ref('ref', 'Ref Scan', 'Ref 扫描'),
  eqRef('eq_ref', 'Eq Ref Scan', 'Eq Ref 扫描'),
  const_('const', 'Const Scan', '常量扫描'),
  system('system', 'System Scan', '系统扫描'),
  fullIndex('index_merge', 'Index Merge', '索引合并'),
  uniqueSubquery('unique_subquery', 'Unique Subquery', '唯一子查询'),
  indexSubquery('index_subquery', 'Index Subquery', '索引子查询'),
  seqScan('Seq Scan', 'Sequential Scan', '顺序扫描'), // PostgreSQL
  indexScan('Index Scan', 'Index Scan', '索引扫描'), // PostgreSQL
  bitmapHeapScan(
    'Bitmap Heap Scan',
    'Bitmap Heap Scan',
    'Bitmap 堆扫描',
  ), // PostgreSQL
  unknown('unknown', 'Unknown', '未知');

  final String code;
  final String displayName;
  final String description;

  const ScanType(this.code, this.displayName, this.description);

  static ScanType fromCode(String? code) {
    if (code == null) return ScanType.unknown;
    return ScanType.values.firstWhere(
      (type) => type.code.toUpperCase() == code.toUpperCase(),
      orElse: () => ScanType.unknown,
    );
  }

  /// 是否高效
  bool get isEfficient =>
      this == ScanType.const_ ||
      this == ScanType.eqRef ||
      this == ScanType.system;

  /// 是否低效
  bool get isInefficient =>
      this == ScanType.fullTable ||
      this == ScanType.fullIndex ||
      this == ScanType.seqScan;
}

/// 性能瓶颈模型
@immutable
class Bottleneck {
  final BottleneckType type;
  final String description;
  final String? affectedTable;
  final int? affectedRows;
  final String? recommendation;
  final Severity severity;

  const Bottleneck({
    required this.type,
    required this.description,
    this.affectedTable,
    this.affectedRows,
    this.recommendation,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'description': description,
    'affectedTable': affectedTable,
    'affectedRows': affectedRows,
    'recommendation': recommendation,
    'severity': severity.name,
  };
}

/// 瓶颈类型
enum BottleneckType {
  fullTableScan,
  missingIndex,
  largeTableScan,
  fileSort,
  temporaryTable,
  inefficientJoin,
  subqueryOptimization,
  selectStar,
  offsetPagination,
  implicitConversion,
}

/// 严重程度
enum Severity {
  critical(4, 'Critical', '严重'),
  high(3, 'High', '高'),
  medium(2, 'Medium', '中'),
  low(1, 'Low', '低'),
  info(0, 'Info', '信息');

  final int level;
  final String displayName;
  final String description;

  const Severity(this.level, this.displayName, this.description);

  bool get isCritical => level >= 3;
}

/// 索引推荐模型
@immutable
class IndexRecommendation {
  final String tableName;
  final String indexName;
  final List<String> columns;
  final String reason;
  final String? ddlStatement;
  final double? estimatedImprovement;
  final bool isUnique;

  const IndexRecommendation({
    required this.tableName,
    required this.indexName,
    required this.columns,
    required this.reason,
    this.ddlStatement,
    this.estimatedImprovement,
    this.isUnique = false,
  });

  Map<String, dynamic> toJson() => {
    'tableName': tableName,
    'indexName': indexName,
    'columns': columns,
    'reason': reason,
    'ddlStatement': ddlStatement,
    'estimatedImprovement': estimatedImprovement,
    'isUnique': isUnique,
  };
}

/// 查询重写建议
@immutable
class QueryRewrite {
  final String originalQuery;
  final String rewrittenQuery;
  final String reason;
  final RewriteType type;

  const QueryRewrite({
    required this.originalQuery,
    required this.rewrittenQuery,
    required this.reason,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'originalQuery': originalQuery,
    'rewrittenQuery': rewrittenQuery,
    'reason': reason,
    'type': type.name,
  };
}

enum RewriteType {
  selectStarToColumns,
  subqueryToJoin,
  orToUnion,
  offsetToKeyset,
  notInToNotExists,
  implicitConversionFix,
  other,
}

/// 性能分析报告
@immutable
class PerformanceReport {
  final ExecutionPlan executionPlan;
  final List<Bottleneck> bottlenecks;
  final List<IndexRecommendation> indexRecommendations;
  final List<QueryRewrite> queryRewrites;
  final String summary;
  final Duration analysisDuration;

  const PerformanceReport({
    required this.executionPlan,
    required this.bottlenecks,
    required this.indexRecommendations,
    required this.queryRewrites,
    required this.summary,
    required this.analysisDuration,
  });

  /// 最高严重程度
  Severity get highestSeverity {
    if (bottlenecks.isEmpty) return Severity.info;
    return bottlenecks
        .map((b) => b.severity)
        .reduce((a, b) => a.level > b.level ? a : b);
  }

  /// 是否有严重问题
  bool get hasCriticalIssues => bottlenecks.any((b) => b.severity.isCritical);

  /// 预估总体性能提升
  double? get totalEstimatedImprovement {
    if (indexRecommendations.isEmpty) return null;
    final improvements = indexRecommendations
        .where((r) => r.estimatedImprovement != null)
        .map((r) => r.estimatedImprovement!);
    if (improvements.isEmpty) return null;
    return improvements.reduce((a, b) => a + b);
  }

  Map<String, dynamic> toJson() => {
    'executionPlan': executionPlan.toJson(),
    'bottlenecks': bottlenecks.map((b) => b.toJson()).toList(),
    'indexRecommendations': indexRecommendations
        .map((r) => r.toJson())
        .toList(),
    'queryRewrites': queryRewrites.map((r) => r.toJson()).toList(),
    'summary': summary,
    'highestSeverity': highestSeverity.name,
    'hasCriticalIssues': hasCriticalIssues,
    'totalEstimatedImprovement': totalEstimatedImprovement,
    'analysisDurationMs': analysisDuration.inMilliseconds,
  };
}
