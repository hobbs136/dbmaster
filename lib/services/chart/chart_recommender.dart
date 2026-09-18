import '../../models/result_filter.dart';

/// 图表推荐引擎（R2: 智能推荐）。
///
/// 纯函数，根据列类型 + 采样数据推荐图表类型与轴选择。无 Flutter 依赖，
/// 可纯单元测试（注入 mock 列类型 + 采样数据）。
///
/// 推荐规则（requirements-results-insight-loop.md R2）：
/// - 日期列 + 数值列 → 折线图（趋势）
/// - 分类列 + 数值列 → 柱状图（对比）
/// - 恰好 1 分类 + 1 数值 → 饼图（占比）
/// - 2 数值列 → 散点图（相关性）
class ChartRecommender {
  /// 根据列类型 + 采样数据推荐图表。
  ///
  /// [columnTypes] 列名 → 列类型映射（来自 ResultFilterService.columnTypes）。
  /// [sampleData] 采样数据（用于辅助判断，如分类列的唯一值数量）。
  static ChartRecommendation recommend({
    required Map<String, ColumnDataType> columnTypes,
    List<Map<String, dynamic>> sampleData = const [],
  }) {
    final columns = columnTypes.keys.toList();
    if (columns.isEmpty) {
      return const ChartRecommendation(
        type: ChartType.bar,
        reason: '无列数据，默认柱状图',
      );
    }

    final dateTimeCols = columnTypes.entries
        .where((e) => e.value == ColumnDataType.dateTime)
        .map((e) => e.key)
        .toList();
    final numericCols = columnTypes.entries
        .where((e) => e.value == ColumnDataType.numeric)
        .map((e) => e.key)
        .toList();
    final stringCols = columnTypes.entries
        .where((e) => e.value == ColumnDataType.string)
        .map((e) => e.key)
        .toList();

    // 1. 日期 + 数值 → 折线（趋势）。日期作 X，第一个数值作 Y。
    if (dateTimeCols.isNotEmpty && numericCols.isNotEmpty) {
      return ChartRecommendation(
        type: ChartType.line,
        xAxis: dateTimeCols.first,
        yAxis: numericCols.first,
        reason: '检测到日期列 + 数值列，折线图适合展示趋势',
      );
    }

    // 2. 恰好 1 分类 + 1 数值 → 饼图（占比）。
    //    用采样数据辅助：分类列唯一值 ≤ 10 才推荐饼图（类别太多饼图不可读）。
    if (stringCols.length == 1 &&
        numericCols.length == 1 &&
        _categoryCardinality(stringCols.first, sampleData) <= 10) {
      return ChartRecommendation(
        type: ChartType.pie,
        xAxis: stringCols.first,
        yAxis: numericCols.first,
        reason: '1 分类列 + 1 数值列，饼图适合展示占比',
      );
    }

    // 3. 2+ 数值列（无日期）→ 散点图（相关性）。前两个数值列作 X/Y。
    if (numericCols.length >= 2 && dateTimeCols.isEmpty) {
      return ChartRecommendation(
        type: ChartType.scatter,
        xAxis: numericCols.first,
        yAxis: numericCols[1],
        reason: '检测到多个数值列，散点图适合展示相关性',
      );
    }

    // 4. 分类 + 数值 → 柱状图（对比）。分类作 X，数值作 Y。
    if (stringCols.isNotEmpty && numericCols.isNotEmpty) {
      return ChartRecommendation(
        type: ChartType.bar,
        xAxis: stringCols.first,
        yAxis: numericCols.first,
        reason: '分类列 + 数值列，柱状图适合对比',
      );
    }

    // 5. 兜底：有数值列就用柱状图；否则默认柱状图（用户可手动切）。
    if (numericCols.isNotEmpty) {
      return ChartRecommendation(
        type: ChartType.bar,
        xAxis: columns.first,
        yAxis: numericCols.first,
        reason: '默认柱状图（可在配置面板切换）',
      );
    }

    return ChartRecommendation(
      type: ChartType.bar,
      xAxis: columns.first,
      yAxis: columns.length > 1 ? columns[1] : columns.first,
      reason: '无可识别的数值列，默认柱状图',
    );
  }

  /// 估算分类列的唯一值数量（基于采样数据）。
  /// 采样数据为空时返回一个大数（保守，不推荐饼图）。
  static int _categoryCardinality(
      String column, List<Map<String, dynamic>> sampleData) {
    if (sampleData.isEmpty) return 999; // 保守：无法判断时不推荐饼图
    final values = <dynamic>{};
    for (final row in sampleData) {
      values.add(row[column]);
    }
    return values.length;
  }
}

/// 图表类型（与底层 fl_chart 对应）。
enum ChartType { line, bar, pie, scatter }

/// 图表推荐结果。
class ChartRecommendation {
  final ChartType type;
  final String? xAxis;
  final String? yAxis;
  final String? reason;

  const ChartRecommendation({
    required this.type,
    this.xAxis,
    this.yAxis,
    this.reason,
  });
}
