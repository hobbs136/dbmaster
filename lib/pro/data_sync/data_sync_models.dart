/// 分段类型
enum SegmentType { time, numeric }

/// 目标同步策略
enum TargetStrategy {
  /// 清空目标表后全量同步
  truncate,

  /// 追加模式（忽略冲突）
  append,

  /// 覆盖模式（REPLACE INTO）
  replace,

  /// 冲突时更新（INSERT ... ON DUPLICATE KEY UPDATE / UPSERT）
  upsert,
}

/// 时间单位
enum TimeUnit { minute, hour, day }

/// 同步段定义
class SyncSegment {
  final int index;
  final String fieldName;

  /// 段的开始值（包含）
  final Object? startValue;

  /// 段的结束值（不包含）
  final Object? endValue;

  /// 该段的预估行数（可能为null）
  final int? estimatedRows;

  const SyncSegment({
    required this.index,
    required this.fieldName,
    required this.startValue,
    required this.endValue,
    this.estimatedRows,
  });

  bool contains(Object? value) {
    if (value == null) return false;
    if (startValue != null) {
      if (value is Comparable && startValue is Comparable) {
        if (value.compareTo(startValue) < 0) return false;
      }
    }
    if (endValue != null) {
      if (value is Comparable && endValue is Comparable) {
        if (value.compareTo(endValue) >= 0) return false;
      }
    }
    return true;
  }

  @override
  String toString() =>
      'SyncSegment(#$index, $fieldName: [$startValue, $endValue))';
}

/// 分段配置基类
abstract class SegmentConfig {
  final SegmentType type;
  final String fieldName;

  SegmentConfig({required this.type, required this.fieldName});
}

/// 时间窗口分段配置
class TimeSegmentConfig extends SegmentConfig {
  final TimeUnit unit;

  /// 间隔值（如 60 分钟）
  final int interval;

  TimeSegmentConfig({
    required super.fieldName,
    required this.unit,
    required this.interval,
  }) : super(type: SegmentType.time);

  Duration get duration {
    switch (unit) {
      case TimeUnit.minute:
        return Duration(minutes: interval);
      case TimeUnit.hour:
        return Duration(hours: interval);
      case TimeUnit.day:
        return Duration(days: interval);
    }
  }
}

/// 数值分段配置
class NumericSegmentConfig extends SegmentConfig {
  /// 每段的行数或范围大小
  final int segmentSize;

  NumericSegmentConfig({required super.fieldName, required this.segmentSize})
    : super(type: SegmentType.numeric);
}

/// 数据同步配置
class DataSyncConfig {
  /// 源连接ID
  final String sourceConnectionId;

  /// 源数据库名
  final String sourceDatabase;

  /// 源表名
  final String sourceTable;

  /// 目标连接ID
  final String targetConnectionId;

  /// 目标数据库名
  final String targetDatabase;

  /// 目标表名（通常与源表一致）
  final String targetTable;

  /// 分段配置
  final SegmentConfig segmentConfig;

  /// 每页行数
  final int pageSize;

  /// 目标同步策略
  final TargetStrategy targetStrategy;

  /// 段间间隔（毫秒，用于保护源库）
  final int segmentIntervalMs;

  /// 页间间隔（毫秒，用于保护源库）
  final int pageIntervalMs;

  const DataSyncConfig({
    required this.sourceConnectionId,
    required this.sourceDatabase,
    required this.sourceTable,
    required this.targetConnectionId,
    required this.targetDatabase,
    required this.targetTable,
    required this.segmentConfig,
    this.pageSize = 1000,
    this.targetStrategy = TargetStrategy.append,
    this.segmentIntervalMs = 0,
    this.pageIntervalMs = 0,
  });

  DataSyncConfig copyWith({
    String? sourceConnectionId,
    String? sourceDatabase,
    String? sourceTable,
    String? targetConnectionId,
    String? targetDatabase,
    String? targetTable,
    SegmentConfig? segmentConfig,
    int? pageSize,
    TargetStrategy? targetStrategy,
    int? segmentIntervalMs,
    int? pageIntervalMs,
  }) {
    return DataSyncConfig(
      sourceConnectionId: sourceConnectionId ?? this.sourceConnectionId,
      sourceDatabase: sourceDatabase ?? this.sourceDatabase,
      sourceTable: sourceTable ?? this.sourceTable,
      targetConnectionId: targetConnectionId ?? this.targetConnectionId,
      targetDatabase: targetDatabase ?? this.targetDatabase,
      targetTable: targetTable ?? this.targetTable,
      segmentConfig: segmentConfig ?? this.segmentConfig,
      pageSize: pageSize ?? this.pageSize,
      targetStrategy: targetStrategy ?? this.targetStrategy,
      segmentIntervalMs: segmentIntervalMs ?? this.segmentIntervalMs,
      pageIntervalMs: pageIntervalMs ?? this.pageIntervalMs,
    );
  }
}

/// 数据同步进度
class DataSyncProgress {
  /// 当前段序号
  final int currentSegmentIndex;

  /// 总段数
  final int totalSegments;

  /// 当前段内页序号
  final int currentPageInSegment;

  /// 当前段总页数（可能为null，未预估）
  final int? totalPagesInSegment;

  /// 已同步行数
  final int syncedRows;

  /// 失败行数
  final int failedRows;

  /// 总行数（可能为null）
  final int? totalRows;

  /// 当前阶段描述
  final String phase;

  /// 是否完成
  final bool isCompleted;

  /// 是否取消
  final bool isCancelled;

  const DataSyncProgress({
    this.currentSegmentIndex = 0,
    this.totalSegments = 0,
    this.currentPageInSegment = 0,
    this.totalPagesInSegment,
    this.syncedRows = 0,
    this.failedRows = 0,
    this.totalRows,
    this.phase = '',
    this.isCompleted = false,
    this.isCancelled = false,
  });

  double? get overallPercent {
    if (totalRows != null && totalRows! > 0) {
      return (syncedRows / totalRows!).clamp(0.0, 1.0);
    }
    if (totalSegments > 0) {
      return (currentSegmentIndex / totalSegments).clamp(0.0, 1.0);
    }
    return null;
  }

  DataSyncProgress copyWith({
    int? currentSegmentIndex,
    int? totalSegments,
    int? currentPageInSegment,
    int? totalPagesInSegment,
    int? syncedRows,
    int? failedRows,
    int? totalRows,
    String? phase,
    bool? isCompleted,
    bool? isCancelled,
  }) {
    return DataSyncProgress(
      currentSegmentIndex: currentSegmentIndex ?? this.currentSegmentIndex,
      totalSegments: totalSegments ?? this.totalSegments,
      currentPageInSegment: currentPageInSegment ?? this.currentPageInSegment,
      totalPagesInSegment: totalPagesInSegment ?? this.totalPagesInSegment,
      syncedRows: syncedRows ?? this.syncedRows,
      failedRows: failedRows ?? this.failedRows,
      totalRows: totalRows ?? this.totalRows,
      phase: phase ?? this.phase,
      isCompleted: isCompleted ?? this.isCompleted,
      isCancelled: isCancelled ?? this.isCancelled,
    );
  }
}

/// 数据同步结果
class DataSyncResult {
  final bool success;
  final int syncedRows;
  final int failedRows;
  final int skippedRows;
  final Duration duration;
  final String? errorMessage;

  const DataSyncResult({
    required this.success,
    required this.syncedRows,
    required this.failedRows,
    required this.skippedRows,
    required this.duration,
    this.errorMessage,
  });
}
