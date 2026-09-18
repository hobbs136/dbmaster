import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../theme/design_system.dart';
import '../../theme/app_colors.dart';

/// ============================================================================
/// AppCharts - 统一的图表组件库
/// ============================================================================
///
/// 基于 fl_chart 封装的图表组件，提供：
/// - 统一的配色方案（与设计系统一致）
/// - 统一的交互样式
/// - 统一的动画效果
/// - 响应式布局支持
///
/// 支持的图表类型：
/// - 折线图 (LineChart) - 趋势展示
/// - 柱状图 (BarChart) - 数据对比
/// - 饼图 (PieChart) - 占比展示
/// - 面积图 (AreaChart) - 累积趋势
/// ============================================================================

/// ============================================================================
/// 图表数据模型
/// ============================================================================

/// 折线图数据点
class LineChartDataPoint {
  final double x;
  final double y;
  final String? label;
  final Color? color;

  const LineChartDataPoint({
    required this.x,
    required this.y,
    this.label,
    this.color,
  });
}

/// 折线图数据系列
class LineChartSeries {
  final String name;
  final List<LineChartDataPoint> data;
  final Color? color;
  final bool showArea;
  final bool showDots;
  final double lineWidth;

  const LineChartSeries({
    required this.name,
    required this.data,
    this.color,
    this.showArea = false,
    this.showDots = true,
    this.lineWidth = 2,
  });
}

/// 柱状图数据
class BarChartDataItem {
  final String label;
  final double value;
  final Color? color;
  final String? tooltip;

  const BarChartDataItem({
    required this.label,
    required this.value,
    this.color,
    this.tooltip,
  });
}

/// 饼图数据项
class PieChartDataItem {
  final String label;
  final double value;
  final Color? color;
  final IconData? icon;

  const PieChartDataItem({
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });
}

/// ============================================================================
/// AppLineChart - 折线图组件
/// ============================================================================
class AppLineChart extends StatefulWidget {
  final List<LineChartSeries> series;
  final String? title;
  final String? xAxisLabel;
  final String? yAxisLabel;
  final double height;
  final bool showLegend;
  final bool animate;
  final EdgeInsets padding;

  const AppLineChart({
    super.key,
    required this.series,
    this.title,
    this.xAxisLabel,
    this.yAxisLabel,
    this.height = 300,
    this.showLegend = true,
    this.animate = true,
    this.padding = const EdgeInsets.all(AppDesignSystem.space3),
  });

  @override
  State<AppLineChart> createState() => _AppLineChartState();
}

class _AppLineChartState extends State<AppLineChart> {
  late final List<Color> _defaultColors;

  @override
  void initState() {
    super.initState();
    _defaultColors = [
      context.themeColors.accentBlue,
      context.themeColors.success,
      context.themeColors.warning,
      context.themeColors.error,
      context.themeColors.accentOrange,
      context.themeColors.accentPurple,
    ];
  }

  Color _getSeriesColor(int index, LineChartSeries series) {
    return series.color ?? _defaultColors[index % _defaultColors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: AppDesignSystem.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null) ...[
            Text(
              widget.title!,
              style: const TextStyle(
                fontSize: AppDesignSystem.fontSizeLg,
                fontWeight: AppDesignSystem.fontWeightSemibold,
                color: AppDesignSystem.textPrimary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
          ],
          SizedBox(
            height: widget.height,
            child: LineChart(_buildLineChartData()),
          ),
          if (widget.showLegend && widget.series.length > 1) ...[
            const SizedBox(height: AppDesignSystem.space3),
            _buildLegend(),
          ],
        ],
      ),
    );
  }

  LineChartData _buildLineChartData() {
    final allDataPoints = widget.series.expand((s) => s.data).toList();
    final maxX = allDataPoints.isNotEmpty
        ? allDataPoints.map((p) => p.x).reduce((a, b) => a > b ? a : b)
        : 10.0;
    final maxY = allDataPoints.isNotEmpty
        ? allDataPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b)
        : 10.0;

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY / 5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: AppDesignSystem.borderLight,
            strokeWidth: 1,
            dashArray: [5, 5],
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            interval: maxX / 5,
            getTitlesWidget: (value, meta) {
              return Padding(
                padding: const EdgeInsets.only(top: AppDesignSystem.space1),
                child: Text(
                  value.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    color: AppDesignSystem.textTertiary,
                  ),
                ),
              );
            },
          ),
          axisNameWidget: widget.xAxisLabel != null
              ? Text(
                  widget.xAxisLabel!,
                  style: const TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    color: AppDesignSystem.textSecondary,
                  ),
                )
              : null,
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: maxY / 5,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toStringAsFixed(0),
                style: const TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  color: AppDesignSystem.textTertiary,
                ),
              );
            },
          ),
          axisNameWidget: widget.yAxisLabel != null
              ? Text(
                  widget.yAxisLabel!,
                  style: const TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    color: AppDesignSystem.textSecondary,
                  ),
                )
              : null,
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: widget.series.asMap().entries.map((entry) {
        final index = entry.key;
        final series = entry.value;
        final color = _getSeriesColor(index, series);

        return LineChartBarData(
          spots: series.data.map((p) => FlSpot(p.x, p.y)).toList(),
          isCurved: true,
          curveSmoothness: 0.3,
          color: color,
          barWidth: series.lineWidth,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: series.showDots,
            getDotPainter: (spot, percent, bar, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: color,
                strokeWidth: 2,
                strokeColor: Colors.white,
              );
            },
          ),
          belowBarData: series.showArea
              ? BarAreaData(show: true, color: color.withAlpha(26))
              : BarAreaData(show: false),
        );
      }).toList(),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: AppDesignSystem.bgSecondary,
          tooltipRoundedRadius: AppDesignSystem.radiusSm,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              return LineTooltipItem(
                spot.y.toStringAsFixed(2),
                const TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  color: AppDesignSystem.textPrimary,
                  fontWeight: AppDesignSystem.fontWeightMedium,
                ),
              );
            }).toList();
          },
        ),
        handleBuiltInTouches: true,
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: AppDesignSystem.space3,
      runSpacing: AppDesignSystem.space2,
      children: widget.series.asMap().entries.map((entry) {
        final index = entry.key;
        final series = entry.value;
        final color = _getSeriesColor(index, series);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 3,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              series.name,
              style: const TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: AppDesignSystem.textSecondary,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// ============================================================================
/// AppBarChart - 柱状图组件
/// ============================================================================
class AppBarChart extends StatefulWidget {
  final List<BarChartDataItem> data;
  final String? title;
  final double height;
  final bool animate;
  final bool showGrid;
  final EdgeInsets padding;

  const AppBarChart({
    super.key,
    required this.data,
    this.title,
    this.height = 300,
    this.animate = true,
    this.showGrid = true,
    this.padding = const EdgeInsets.all(AppDesignSystem.space3),
  });

  @override
  State<AppBarChart> createState() => _AppBarChartState();
}

class _AppBarChartState extends State<AppBarChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: AppDesignSystem.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null) ...[
            Text(
              widget.title!,
              style: const TextStyle(
                fontSize: AppDesignSystem.fontSizeLg,
                fontWeight: AppDesignSystem.fontWeightSemibold,
                color: AppDesignSystem.textPrimary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
          ],
          SizedBox(
            height: widget.height,
            child: BarChart(_buildBarChartData()),
          ),
        ],
      ),
    );
  }

  BarChartData _buildBarChartData() {
    final maxY = widget.data.isNotEmpty
        ? widget.data.map((d) => d.value).reduce((a, b) => a > b ? a : b) * 1.2
        : 10.0;

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: maxY,
      gridData: widget.showGrid
          ? FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 5,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: AppDesignSystem.borderLight,
                  strokeWidth: 1,
                  dashArray: [5, 5],
                );
              },
            )
          : FlGridData(show: false),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= widget.data.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: AppDesignSystem.space1),
                child: Text(
                  widget.data[index].label,
                  style: const TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    color: AppDesignSystem.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: maxY / 5,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toStringAsFixed(0),
                style: const TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  color: AppDesignSystem.textTertiary,
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      barGroups: widget.data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final isTouched = index == _touchedIndex;
        final color = item.color ?? context.themeColors.accentBlue;

        return BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: item.value,
              color: isTouched ? color.withAlpha(204) : color,
              width: isTouched ? 22 : 20,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppDesignSystem.radiusSm),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: maxY,
                color: AppDesignSystem.bgTertiary,
              ),
            ),
          ],
          showingTooltipIndicators: isTouched ? [0] : [],
        );
      }).toList(),
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          tooltipBgColor: AppDesignSystem.bgSecondary,
          tooltipRoundedRadius: AppDesignSystem.radiusSm,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final item = widget.data[groupIndex];
            return BarTooltipItem(
              item.tooltip ?? item.value.toStringAsFixed(2),
              const TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: AppDesignSystem.textPrimary,
                fontWeight: AppDesignSystem.fontWeightMedium,
              ),
            );
          },
        ),
        touchCallback: (event, response) {
          setState(() {
            _touchedIndex = response?.spot?.touchedBarGroupIndex;
          });
        },
      ),
    );
  }
}

/// ============================================================================
/// AppPieChart - 饼图组件
/// ============================================================================
class AppPieChart extends StatefulWidget {
  final List<PieChartDataItem> data;
  final String? title;
  final double size;
  final bool showLegend;
  final bool animate;
  final EdgeInsets padding;
  final bool showCenterSpace;

  const AppPieChart({
    super.key,
    required this.data,
    this.title,
    this.size = 200,
    this.showLegend = true,
    this.animate = true,
    this.padding = const EdgeInsets.all(AppDesignSystem.space3),
    this.showCenterSpace = false,
  });

  @override
  State<AppPieChart> createState() => _AppPieChartState();
}

class _AppPieChartState extends State<AppPieChart> {
  late final List<Color> _defaultColors;
  int? _touchedIndex;

  @override
  void initState() {
    super.initState();
    _defaultColors = [
      context.themeColors.accentBlue,
      context.themeColors.success,
      context.themeColors.warning,
      context.themeColors.error,
      context.themeColors.accentOrange,
      context.themeColors.accentPurple,
      AppDesignSystem.accentPrimary,
      context.themeColors.info,
    ];
  }

  Color _getItemColor(int index, PieChartDataItem item) {
    return item.color ?? _defaultColors[index % _defaultColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.data.fold(0.0, (sum, item) => sum + item.value);

    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: AppDesignSystem.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null) ...[
            Text(
              widget.title!,
              style: const TextStyle(
                fontSize: AppDesignSystem.fontSizeLg,
                fontWeight: AppDesignSystem.fontWeightSemibold,
                color: AppDesignSystem.textPrimary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
          ],
          Row(
            children: [
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: PieChart(_buildPieChartData(total)),
              ),
              if (widget.showLegend) ...[
                const SizedBox(width: AppDesignSystem.space4),
                Expanded(child: _buildLegend(total)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  PieChartData _buildPieChartData(double total) {
    return PieChartData(
      pieTouchData: PieTouchData(
        touchCallback: (event, response) {
          setState(() {
            _touchedIndex = response?.touchedSection?.touchedSectionIndex;
          });
        },
      ),
      borderData: FlBorderData(show: false),
      sectionsSpace: 2,
      centerSpaceRadius: widget.showCenterSpace ? widget.size * 0.3 : 0,
      sections: widget.data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final isTouched = index == _touchedIndex;
        final color = _getItemColor(index, item);
        final percentage = total > 0 ? (item.value / total * 100) : 0;

        return PieChartSectionData(
          color: color,
          value: item.value,
          title: isTouched ? '${percentage.toStringAsFixed(1)}%' : '',
          radius: isTouched ? widget.size * 0.35 : widget.size * 0.3,
          titleStyle: const TextStyle(
            fontSize: AppDesignSystem.fontSizeSm,
            fontWeight: AppDesignSystem.fontWeightBold,
            color: Colors.white,
          ),
          titlePositionPercentageOffset: 0.55,
          showTitle: isTouched,
        );
      }).toList(),
    );
  }

  Widget _buildLegend(double total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.data.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        final color = _getItemColor(index, item);
        final percentage = total > 0 ? (item.value / total * 100) : 0;
        final isHovered = index == _touchedIndex;

        return MouseRegion(
          onEnter: (_) => setState(() => _touchedIndex = index),
          onExit: (_) => setState(() => _touchedIndex = null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(
              vertical: AppDesignSystem.space1,
              horizontal: AppDesignSystem.space2,
            ),
            decoration: BoxDecoration(
              color: isHovered
                  ? AppDesignSystem.bgSecondary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeSm,
                      color: isHovered
                          ? AppDesignSystem.textPrimary
                          : AppDesignSystem.textSecondary,
                      fontWeight: isHovered
                          ? AppDesignSystem.fontWeightMedium
                          : AppDesignSystem.fontWeightRegular,
                    ),
                  ),
                ),
                Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    color: AppDesignSystem.textTertiary,
                    fontWeight: AppDesignSystem.fontWeightMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// ============================================================================
/// 简化版图表组件 - 用于快速展示
/// ============================================================================

/// 迷你折线图 - 用于卡片内嵌
class AppMiniLineChart extends StatelessWidget {
  final List<double> data;
  final Color? color;
  final double height;
  final bool showArea;

  const AppMiniLineChart({
    super.key,
    required this.data,
    this.color,
    this.height = 60,
    this.showArea = true,
  });

  @override
  Widget build(BuildContext context) {
    final chartColor = color ?? context.themeColors.accentBlue;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (data.length - 1).toDouble(),
          minY: 0,
          maxY: _getMaxY(multiplier: 1.1),
          lineBarsData: [
            LineChartBarData(
              spots: data.asMap().entries.map((e) {
                return FlSpot(e.key.toDouble(), e.value);
              }).toList(),
              isCurved: true,
              curveSmoothness: 0.3,
              color: chartColor,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(show: false),
              belowBarData: showArea
                  ? BarAreaData(show: true, color: chartColor.withAlpha(26))
                  : BarAreaData(show: false),
            ),
          ],
          lineTouchData: LineTouchData(enabled: false),
        ),
      ),
    );
  }

  double _getMaxY({required double multiplier}) {
    if (data.isEmpty) return 1.0;
    return data.reduce((a, b) => a > b ? a : b) * multiplier;
  }
}

/// 迷你柱状图 - 用于卡片内嵌
class AppMiniBarChart extends StatelessWidget {
  final List<double> data;
  final Color? color;
  final double height;

  const AppMiniBarChart({
    super.key,
    required this.data,
    this.color,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    final chartColor = color ?? context.themeColors.accentBlue;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: _getMaxY(multiplier: 1.2),
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: data.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value,
                  color: chartColor,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppDesignSystem.radiusSm),
                  ),
                ),
              ],
            );
          }).toList(),
          barTouchData: BarTouchData(enabled: false),
        ),
      ),
    );
  }

  double _getMaxY({required double multiplier}) {
    if (data.isEmpty) return 1.0;
    return data.reduce((a, b) => a > b ? a : b) * multiplier;
  }
}

/// ============================================================================
/// AppScatterChart - 散点图组件（R2: 2 数值列相关性）
/// ============================================================================
/// 基于 fl_chart ScatterChart，配色对齐设计系统。
/// 用于展示两个数值列之间的相关性（如 2 数值列 → 散点推荐）。

/// 散点图数据点
class ScatterChartDataPoint {
  final double x;
  final double y;
  final String? label;
  final Color? color;

  const ScatterChartDataPoint({
    required this.x,
    required this.y,
    this.label,
    this.color,
  });
}

/// 散点图数据系列
class ScatterChartSeries {
  final String name;
  final List<ScatterChartDataPoint> data;
  final Color? color;

  const ScatterChartSeries({
    required this.name,
    required this.data,
    this.color,
  });
}

class AppScatterChart extends StatefulWidget {
  final List<ScatterChartSeries> series;
  final String? title;
  final String? xAxisLabel;
  final String? yAxisLabel;
  final double height;
  final bool animate;
  final bool showGrid;
  final EdgeInsets padding;

  const AppScatterChart({
    super.key,
    required this.series,
    this.title,
    this.xAxisLabel,
    this.yAxisLabel,
    this.height = 300,
    this.animate = true,
    this.showGrid = true,
    this.padding = const EdgeInsets.all(AppDesignSystem.space3),
  });

  @override
  State<AppScatterChart> createState() => _AppScatterChartState();
}

class _AppScatterChartState extends State<AppScatterChart> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: AppDesignSystem.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null) ...[
            Text(
              widget.title!,
              style: const TextStyle(
                fontSize: AppDesignSystem.fontSizeLg,
                fontWeight: AppDesignSystem.fontWeightSemibold,
                color: AppDesignSystem.textPrimary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
          ],
          SizedBox(
            height: widget.height,
            child: ScatterChart(_buildScatterChartData()),
          ),
        ],
      ),
    );
  }

  ScatterChartData _buildScatterChartData() {
    // 配色用运行时主题色（与 AppLineChart 一致），不依赖 AppDesignSystem 静态常量。
    final palette = [
      context.themeColors.accentBlue,
      context.themeColors.success,
      context.themeColors.warning,
      context.themeColors.error,
      context.themeColors.accentOrange,
      context.themeColors.accentPurple,
    ];

    final allPoints = widget.series.expand((s) => s.data).toList();

    if (allPoints.isEmpty) {
      return ScatterChartData(
        scatterSpots: const [],
        minX: 0,
        maxX: 1,
        minY: 0,
        maxY: 1,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
      );
    }

    final xs = allPoints.map((e) => e.x).toList();
    final ys = allPoints.map((e) => e.y).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);

    // 避免 min == max 导致渲染异常，加 padding
    final xPad = (maxX - minX).abs() < 0.001 ? 1.0 : (maxX - minX) * 0.05;
    final yPad = (maxY - minY).abs() < 0.001 ? 1.0 : (maxY - minY) * 0.05;

    return ScatterChartData(
      scatterSpots: widget.series.asMap().entries.expand((sEntry) {
        final color =
            sEntry.value.color ?? palette[sEntry.key % palette.length];
        return sEntry.value.data.map((p) => ScatterSpot(
              p.x,
              p.y,
              dotPainter: FlDotCirclePainter(radius: 5, color: color),
            ));
      }).toList(),
      minX: minX - xPad,
      maxX: maxX + xPad,
      minY: minY - yPad,
      maxY: maxY + yPad,
      gridData: widget.showGrid
          ? FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: (maxY - minY + 2 * yPad) / 5,
              getDrawingHorizontalLine: (value) => FlLine(
                color: AppDesignSystem.borderLight,
                strokeWidth: 1,
                dashArray: [5, 5],
              ),
            )
          : const FlGridData(show: false),
      titlesData: FlTitlesData(
        show: true,
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          axisNameWidget: widget.xAxisLabel != null
              ? Text(widget.xAxisLabel!,
                  style: const TextStyle(
                      fontSize: 11, color: AppDesignSystem.textSecondary))
              : null,
          sideTitles: const SideTitles(showTitles: true, reservedSize: 28),
        ),
        leftTitles: AxisTitles(
          axisNameWidget: widget.yAxisLabel != null
              ? Text(widget.yAxisLabel!,
                  style: const TextStyle(
                      fontSize: 11, color: AppDesignSystem.textSecondary))
              : null,
          sideTitles: const SideTitles(showTitles: true, reservedSize: 40),
        ),
      ),
      borderData: FlBorderData(show: false),
      scatterTouchData: ScatterTouchData(
        touchTooltipData: ScatterTouchTooltipData(
          tooltipBgColor: Theme.of(context).cardColor,
          getTooltipItems: (touchedSpot) {
            return ScatterTooltipItem(
              '${touchedSpot.x.toStringAsFixed(2)}, ${touchedSpot.y.toStringAsFixed(2)}',
              textStyle: const TextStyle(
                fontSize: 11,
                color: AppDesignSystem.textPrimary,
              ),
            );
          },
        ),
      ),
    );
  }
}
