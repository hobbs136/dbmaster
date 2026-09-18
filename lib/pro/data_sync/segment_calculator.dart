import 'package:dbmaster/pro/data_sync/data_sync_models.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/services/database_abstract.dart';

/// 分段计算器抽象类
abstract class SegmentCalculator {
  /// 根据配置计算分段列表
  Future<List<SyncSegment>> calculateSegments({
    required DatabaseAdapter adapter,
    required String tableName,
    required SegmentConfig config,
    AppLocalizations? l10n,
  });

  /// 探测字段的范围和行数
  Future<RangeInfo> _detectRange({
    required DatabaseAdapter adapter,
    required String tableName,
    required String fieldName,
  }) async {
    final sql =
        'SELECT MIN(`$fieldName`) as min_val, MAX(`$fieldName`) as max_val, COUNT(*) as cnt FROM `$tableName`';
    final result = await adapter.executeQuery(sql);

    if (result.rows.isEmpty) {
      return RangeInfo.empty();
    }

    final row = result.rows.first;
    return RangeInfo(
      minValue: row['min_val'],
      maxValue: row['max_val'],
      totalCount: row['cnt'] is int
          ? row['cnt']
          : int.tryParse(row['cnt'].toString()) ?? 0,
    );
  }
}

/// 范围探测结果
class RangeInfo {
  final dynamic minValue;
  final dynamic maxValue;
  final int totalCount;

  const RangeInfo({
    required this.minValue,
    required this.maxValue,
    required this.totalCount,
  });

  factory RangeInfo.empty() =>
      const RangeInfo(minValue: null, maxValue: null, totalCount: 0);

  bool get isEmpty => minValue == null || maxValue == null || totalCount == 0;
}

/// 时间窗口分段计算器
class TimeSegmentCalculator extends SegmentCalculator {
  @override
  Future<List<SyncSegment>> calculateSegments({
    required DatabaseAdapter adapter,
    required String tableName,
    required SegmentConfig config,
    AppLocalizations? l10n,
  }) async {
    final timeConfig = config as TimeSegmentConfig;
    final range = await _detectRange(
      adapter: adapter,
      tableName: tableName,
      fieldName: config.fieldName,
    );

    if (range.isEmpty) return [];

    final minDate = _parseDateTime(range.minValue);
    final maxDate = _parseDateTime(range.maxValue);

    if (minDate == null || maxDate == null) {
      throw FormatException(
        l10n?.dataSyncErrorDateTimeParse(
              config.fieldName,
              range.minValue.toString(),
              range.maxValue.toString(),
            ) ??
            'Field `${config.fieldName}` cannot be parsed as datetime: min=${range.minValue}, max=${range.maxValue}',
      );
    }

    final segments = <SyncSegment>[];
    final interval = timeConfig.duration;
    int index = 0;

    DateTime currentStart = minDate;
    while (currentStart.isBefore(maxDate)) {
      final currentEnd = currentStart.add(interval);

      segments.add(
        SyncSegment(
          index: index,
          fieldName: config.fieldName,
          startValue: _formatDateTime(currentStart),
          endValue: _formatDateTime(currentEnd),
        ),
      );

      currentStart = currentEnd;
      index++;

      // 安全限制：最多10000个段
      if (index >= 10000) break;
    }

    return segments;
  }

  /// 解析日期时间值（支持多种格式）
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      // 尝试解析 MySQL 格式: '2024-01-01 12:00:00'
      try {
        return DateTime.parse(value.replaceFirst(' ', 'T'));
      } catch (_) {
        try {
          return DateTime.parse(value);
        } catch (_) {
          return null;
        }
      }
    }
    if (value is num) {
      // Unix 时间戳（毫秒）
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    return null;
  }

  /// 格式化为 SQL 日期时间字符串
  String _formatDateTime(DateTime dt) {
    return dt.toIso8601String().replaceFirst('T', ' ').split('.').first;
  }
}

/// 数值分段计算器
class NumericSegmentCalculator extends SegmentCalculator {
  @override
  Future<List<SyncSegment>> calculateSegments({
    required DatabaseAdapter adapter,
    required String tableName,
    required SegmentConfig config,
    AppLocalizations? l10n,
  }) async {
    final numConfig = config as NumericSegmentConfig;
    final range = await _detectRange(
      adapter: adapter,
      tableName: tableName,
      fieldName: config.fieldName,
    );

    if (range.isEmpty) return [];

    final minValue = _parseNumeric(range.minValue);
    final maxValue = _parseNumeric(range.maxValue);

    if (minValue == null || maxValue == null) {
      throw FormatException(
        l10n?.dataSyncErrorNumericParse(
              config.fieldName,
              range.minValue.toString(),
              range.maxValue.toString(),
            ) ??
            'Field `${config.fieldName}` cannot be parsed as number: min=${range.minValue}, max=${range.maxValue}',
      );
    }

    final segments = <SyncSegment>[];
    final segmentSize = numConfig.segmentSize;
    int index = 0;

    // 使用 BigInt 避免大数溢出问题
    BigInt currentStart = BigInt.from(minValue);
    final bigMax = BigInt.from(maxValue);
    final bigSize = BigInt.from(segmentSize);

    while (currentStart <= bigMax) {
      final currentEnd = currentStart + bigSize;

      segments.add(
        SyncSegment(
          index: index,
          fieldName: config.fieldName,
          startValue: _formatNumeric(currentStart),
          endValue: _formatNumeric(currentEnd),
        ),
      );

      currentStart = currentEnd;
      index++;

      // 安全限制：最多10000个段
      if (index >= 10000) break;
    }

    return segments;
  }

  num? _parseNumeric(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    if (value is String) {
      return int.tryParse(value) ?? double.tryParse(value);
    }
    return null;
  }

  dynamic _formatNumeric(BigInt value) {
    // 如果值在 int 范围内，返回 int，否则返回 String
    if (value >= BigInt.from(-9007199254740991) &&
        value <= BigInt.from(9007199254740991)) {
      return value.toInt();
    }
    return value.toString();
  }
}

/// 分段计算器工厂
class SegmentCalculatorFactory {
  static SegmentCalculator create(SegmentConfig config) {
    switch (config.type) {
      case SegmentType.time:
        return TimeSegmentCalculator();
      case SegmentType.numeric:
        return NumericSegmentCalculator();
    }
  }
}
