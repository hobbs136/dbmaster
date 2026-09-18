import '../models/result_filter.dart';

/// 结果集统计服务（R3: 就地统计分析）。
///
/// 纯函数，对查询结果集计算统计指标。无 Flutter 依赖，可纯单元测试。
///
/// 支持三类列的统计：
/// - 数值列：count / sum / avg / min / max / median / nullCount
/// - 分类列：distinctCount / topValues（TOP 5 频次）
/// - 日期列：dateMin / dateMax / dateSpan（跨度）
///
/// 性能（NF1）：>10K 行不在 Dart 侧全量计算，抛 [DatasetTooLargeException]，
/// UI 提示「建议用 SQL 聚合」。
class ResultStatisticsService {
  /// Dart 侧全量计算的行数阈值（NF1 性能保护）。
  static const int maxInMemoryRows = 10000;

  /// 计算所有列的统计指标。
  ///
  /// [data] 查询结果行。 [columnTypes] 列名 → 列类型（决定统计方式）。
  /// 行数 > maxInMemoryRows 时抛 [DatasetTooLargeException]。
  static List<ColumnStatistics> compute({
    required List<Map<String, dynamic>> data,
    required Map<String, ColumnDataType> columnTypes,
  }) {
    if (data.length > maxInMemoryRows) {
      throw DatasetTooLargeException(data.length, maxInMemoryRows);
    }
    if (data.isEmpty) return const [];

    final columns = data.first.keys.toList();
    return columns.map((col) => _computeColumn(col, data, columnTypes[col] ?? ColumnDataType.string)).toList();
  }

  static ColumnStatistics _computeColumn(
      String name, List<Map<String, dynamic>> data, ColumnDataType type) {
    switch (type) {
      case ColumnDataType.numeric:
        return _computeNumeric(name, data);
      case ColumnDataType.dateTime:
        return _computeDateTime(name, data);
      case ColumnDataType.string:
      case ColumnDataType.json:
        return _computeCategorical(name, data);
    }
  }

  /// 数值列统计：count/sum/avg/min/max/median/nullCount。
  static ColumnStatistics _computeNumeric(String name, List<Map<String, dynamic>> data) {
    final values = <num>[];
    int nullCount = 0;
    for (final row in data) {
      final v = row[name];
      if (v == null) {
        nullCount++;
      } else if (v is num) {
        values.add(v);
      } else {
        // 尝试解析字符串数值
        final parsed = double.tryParse(v.toString());
        if (parsed != null) {
          values.add(parsed);
        } else {
          nullCount++;
        }
      }
    }

    if (values.isEmpty) {
      return ColumnStatistics(name: name, type: ColumnDataType.numeric, nullCount: nullCount);
    }

    values.sort((a, b) => a.compareTo(b));
    final sum = values.fold<num>(0, (a, b) => a + b);
    final count = values.length;
    final sorted = values..sort((a, b) => a.compareTo(b));

    return ColumnStatistics(
      name: name,
      type: ColumnDataType.numeric,
      count: count,
      sum: sum.toDouble(),
      avg: sum / count,
      min: sorted.first.toDouble(),
      max: sorted.last.toDouble(),
      median: _median(sorted),
      nullCount: nullCount,
    );
  }

  static double _median(List<num> sorted) {
    final n = sorted.length;
    if (n == 0) return 0;
    if (n.isOdd) return sorted[n ~/ 2].toDouble();
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }

  /// 分类列统计：distinctCount + TOP 5 值频次。
  static ColumnStatistics _computeCategorical(String name, List<Map<String, dynamic>> data) {
    final freq = <String, int>{};
    int nullCount = 0;
    for (final row in data) {
      final v = row[name];
      if (v == null) {
        nullCount++;
        continue;
      }
      final key = v.toString();
      freq[key] = (freq[key] ?? 0) + 1;
    }

    // TOP 5 by frequency
    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).map((e) => MapEntry(e.key, e.value)).toList();

    return ColumnStatistics(
      name: name,
      type: ColumnDataType.string,
      distinctCount: freq.length,
      topValues: top5,
      nullCount: nullCount,
    );
  }

  /// 日期列统计：dateMin / dateMax / dateSpan。
  static ColumnStatistics _computeDateTime(String name, List<Map<String, dynamic>> data) {
    DateTime? minDate;
    DateTime? maxDate;
    int nullCount = 0;
    int validCount = 0;

    for (final row in data) {
      final v = row[name];
      if (v == null) {
        nullCount++;
        continue;
      }
      DateTime? dt;
      if (v is DateTime) {
        dt = v;
      } else {
        dt = DateTime.tryParse(v.toString());
      }
      if (dt == null) {
        nullCount++;
        continue;
      }
      validCount++;
      if (minDate == null || dt.isBefore(minDate)) minDate = dt;
      if (maxDate == null || dt.isAfter(maxDate)) maxDate = dt;
    }

    String? span;
    if (minDate != null && maxDate != null) {
      final diff = maxDate.difference(minDate);
      if (diff.inDays > 0) {
        span = '${diff.inDays} 天';
      } else if (diff.inHours > 0) {
        span = '${diff.inHours} 小时';
      } else if (diff.inMinutes > 0) {
        span = '${diff.inMinutes} 分钟';
      } else {
        span = '${diff.inSeconds} 秒';
      }
    }

    return ColumnStatistics(
      name: name,
      type: ColumnDataType.dateTime,
      dateMin: minDate,
      dateMax: maxDate,
      dateSpan: span,
      count: validCount,
      nullCount: nullCount,
    );
  }

  /// 生成聚合 SQL（R3: 点击统计值 → 生成查询到新 Tab，不自动执行）。
  ///
  /// [agg] 聚合函数名（'SUM'/'AVG'/'MIN'/'MAX'/'COUNT'）。
  static String generateStatsSql({
    required String column,
    required String agg,
    String? table,
  }) {
    final tbl = table?.trim().isNotEmpty == true ? table : '<target_table>';
    return 'SELECT $agg($column) FROM $tbl;';
  }

  /// 生成 GROUP BY 查询（R3: 点击分类列 → 生成 GROUP BY 到新 Tab）。
  static String generateGroupBySql({
    required String column,
    String? aggColumn,
    String agg = 'COUNT',
    String? table,
  }) {
    final tbl = table?.trim().isNotEmpty == true ? table : '<target_table>';
    final metric = aggColumn != null ? '$agg($aggColumn)' : '$agg(*)';
    return 'SELECT $column, $metric AS value\nFROM $tbl\nGROUP BY $column\nORDER BY value DESC;';
  }
}

/// 单列统计结果。
class ColumnStatistics {
  final String name;
  final ColumnDataType type;

  // 数值列
  final int? count;
  final double? sum;
  final double? avg;
  final double? min;
  final double? max;
  final double? median;
  final int? nullCount;

  // 分类列
  final int? distinctCount;
  final List<MapEntry<String, int>>? topValues;

  // 日期列
  final DateTime? dateMin;
  final DateTime? dateMax;
  final String? dateSpan;

  const ColumnStatistics({
    required this.name,
    required this.type,
    this.count,
    this.sum,
    this.avg,
    this.min,
    this.max,
    this.median,
    this.nullCount,
    this.distinctCount,
    this.topValues,
    this.dateMin,
    this.dateMax,
    this.dateSpan,
  });

  bool get isNumeric => type == ColumnDataType.numeric;
  bool get isCategorical => type == ColumnDataType.string || type == ColumnDataType.json;
  bool get isDateTime => type == ColumnDataType.dateTime;
}

/// 数据集过大异常（NF1: >10K 行不在 Dart 侧计算）。
class DatasetTooLargeException implements Exception {
  final int actualRows;
  final int threshold;
  const DatasetTooLargeException(this.actualRows, this.threshold);

  @override
  String toString() =>
      '数据集过大（$actualRows 行 > $threshold 阈值），建议用 SQL 聚合（如 SELECT AVG(col) FROM t）';
}
