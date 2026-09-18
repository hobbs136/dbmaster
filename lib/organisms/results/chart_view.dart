import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/result_filter.dart';
import '../../services/chart/chart_recommender.dart';
import 'chart_export.dart';

/// ChartView - 数据可视化组件（R2: 图表视图）
///
/// 支持折线/柱状/饼图/散点四种图表。自动检测列类型推荐图表 + 手动配置轴/类型。
/// 大数据集（>1000 点）自动采样 + 提示。支持导出 PNG。
///
/// 配色统一使用 context.themeColors（与 app_charts 一致的设计系统）。
class ChartView extends StatefulWidget {
  final List<Map<String, dynamic>> data;

  /// 列类型映射（来自 ResultFilterService.columnTypes），用于智能推荐。
  /// 为 null 时降级为「全部字符串」处理（不推荐，仅手动配置可用）。
  final Map<String, ColumnDataType>? columnTypes;

  /// R5: AI 趋势分析回调（由调用方注入 provider 配置）。null 时不显示按钮。
  /// 返回趋势分析文本；调用方负责门控（canUseAi）与 LLM 调用。
  final Future<String> Function()? onAiTrendRequest;

  const ChartView({
    super.key,
    required this.data,
    this.columnTypes,
    this.onAiTrendRequest,
  });

  @override
  State<ChartView> createState() => _ChartViewState();
}

/// 采样阈值：超过此数据点数自动等距采样（NF1 性能保护）。
const _kMaxPoints = 1000;

class _ChartViewState extends State<ChartView> with ChartExportBoundary {
  late String? _selectedXAxis;
  late String? _selectedYAxis;
  late ChartType _selectedChartType;
  bool _recommendationApplied = false;

  // R5: AI 趋势分析状态
  bool _aiLoading = false;
  String? _aiTrendResult;

  @override
  void initState() {
    super.initState();
    _selectedXAxis = null;
    _selectedYAxis = null;
    _selectedChartType = ChartType.bar;
  }

  @override
  void didUpdateWidget(ChartView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据变化时重置选择，重新推荐
    if (oldWidget.data != widget.data) {
      _selectedXAxis = null;
      _selectedYAxis = null;
      _recommendationApplied = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.data.isEmpty) {
      return _buildEmptyState(l10n);
    }

    final columns = widget.data.first.keys.toList();

    // 首次进入：用 ChartRecommender 推荐图表 + 轴
    if (!_recommendationApplied) {
      _applyRecommendation(columns);
    }

    return Column(
      children: [
        _buildChartConfigBar(columns, l10n),
        Expanded(child: _buildChart(l10n)),
        if (_aiTrendResult != null) _buildAiTrendResult(l10n),
      ],
    );
  }

  /// 应用 ChartRecommender 的推荐（首次进入或数据变化后）。
  void _applyRecommendation(List<String> columns) {
    final columnTypes = <String, ColumnDataType>{};
    if (widget.columnTypes != null) {
      // 用真实列类型
      columnTypes.addAll(widget.columnTypes!);
    } else {
      // 降级：从采样数据推断（数值 vs 字符串）
      for (final col in columns) {
        columnTypes[col] = _inferColumnType(col);
      }
    }

    final rec = ChartRecommender.recommend(
      columnTypes: columnTypes,
      sampleData: widget.data.take(100).toList(),
    );
    _selectedChartType = rec.type;
    _selectedXAxis = rec.xAxis ?? columns.first;
    _selectedYAxis =
        rec.yAxis ?? (columns.length > 1 ? columns[1] : columns.first);
    _recommendationApplied = true;
  }

  /// 无 columnTypes 时从数据推断列类型（数值 vs 字符串）。
  ColumnDataType _inferColumnType(String column) {
    for (final row in widget.data) {
      final v = row[column];
      if (v is num) return ColumnDataType.numeric;
    }
    return ColumnDataType.string;
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.chartColumn,
            size: 48,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.resultsNoDataTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.resultsNoDataChartMessage,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartConfigBar(List<String> columns, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildAxisDropdown(
              l10n.chartXAxis,
              _selectedXAxis,
              columns,
              (value) => setState(() => _selectedXAxis = value),
            ),
            const SizedBox(width: 16),
            _buildAxisDropdown(
              l10n.chartYAxis,
              _selectedYAxis,
              columns,
              (value) => setState(() => _selectedYAxis = value),
            ),
            const SizedBox(width: 16),
            _buildChartTypeSelector(l10n),
            const SizedBox(width: 16),
            // 导出 PNG 按钮（R2）
            IconButton(
              icon: const Icon(LucideIcons.download, size: 18),
              tooltip: 'Export PNG',
              onPressed: () => ChartExporter.exportToPng(
                boundaryKey: boundaryKey,
                context: context,
              ),
              visualDensity: VisualDensity.compact,
            ),
            // R5: AI 趋势分析按钮（onAiTrendRequest 为 null 时不显示）
            if (widget.onAiTrendRequest != null) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _aiLoading ? null : _runAiTrend,
                icon: _aiLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.sparkles, size: 16),
                label: Text(
                  AppLocalizations.of(context)?.chartAiTrend ?? 'AI Trend',
                  style: const TextStyle(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAxisDropdown(
    String label,
    String? value,
    List<String> items,
    ValueChanged<String?> onChanged,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: context.themeColors.bgSecondary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButton<String>(
            value: value,
            items: items
                .map(
                  (col) => DropdownMenuItem(
                    value: col,
                    child: Text(col, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
            onChanged: onChanged,
            underline: const SizedBox.shrink(),
            isDense: true,
          ),
        ),
      ],
    );
  }

  /// 图表类型选择器（line/bar/pie/scatter，SegmentedButton 紧凑）。
  Widget _buildChartTypeSelector(AppLocalizations l10n) {
    return SegmentedButton<ChartType>(
      segments: [
        ButtonSegment(
          value: ChartType.line,
          icon: const Icon(LucideIcons.trendingUp, size: 16),
        ),
        ButtonSegment(
          value: ChartType.bar,
          icon: const Icon(LucideIcons.chartColumn, size: 16),
        ),
        ButtonSegment(
          value: ChartType.pie,
          icon: const Icon(LucideIcons.chartPie, size: 16),
        ),
        ButtonSegment(
          value: ChartType.scatter,
          icon: const Icon(LucideIcons.chartScatter, size: 16),
        ),
      ],
      selected: {_selectedChartType},
      onSelectionChanged: (s) => setState(() => _selectedChartType = s.first),
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildChart(AppLocalizations l10n) {
    if (_selectedXAxis == null || _selectedYAxis == null) {
      return Center(child: Text(l10n.resultsSelectAxisFields));
    }

    // 提取并采样数据
    final extracted = _extractChartData();
    if (extracted.samples.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.chartCannotGenerate,
            style: TextStyle(color: context.themeColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        if (extracted.sampled) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: context.themeColors.warning.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  size: 14,
                  color: context.themeColors.warning,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.chartSamplingNotice(extracted.samples.length),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Expanded(
          // RepaintBoundary 包裹图表，供 PNG 导出截图
          child: RepaintBoundary(
            key: boundaryKey,
            child: _buildChartByType(extracted.samples, extracted.labels),
          ),
        ),
      ],
    );
  }

  /// R5: 触发 AI 趋势分析（调 onAiTrendRequest 回调）。
  Future<void> _runAiTrend() async {
    if (widget.onAiTrendRequest == null) return;
    setState(() => _aiLoading = true);
    try {
      final result = await widget.onAiTrendRequest!();
      if (mounted)
        setState(() {
          _aiTrendResult = result;
          _aiLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  /// R5: AI 趋势结果展示区（图表下方可折叠）。
  Widget _buildAiTrendResult(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 120),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeColors.accentPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: context.themeColors.accentPurple.withValues(alpha: 0.3),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.sparkles,
                  size: 14,
                  color: context.themeColors.accentPurple,
                ),
                const SizedBox(width: 6),
                Text(
                  'AI 趋势分析',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.accentPurple,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => setState(() => _aiTrendResult = null),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _aiTrendResult ?? '',
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textPrimary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 提取选中轴的数据，超过阈值时等距采样。
  _ChartData _extractChartData() {
    final labels = <String>[];
    final values = <num>[];

    for (final row in widget.data) {
      final label = row[_selectedXAxis]?.toString() ?? '';
      final value = row[_selectedYAxis];
      if (label.isNotEmpty && value != null) {
        final numValue = value is num
            ? value
            : double.tryParse(value.toString());
        if (numValue != null) {
          labels.add(label);
          values.add(numValue);
        }
      }
    }

    // 采样（> _kMaxPoints 等距抽取）
    if (values.length > _kMaxPoints) {
      final step = values.length / _kMaxPoints;
      final sLabels = <String>[];
      final sValues = <num>[];
      for (var i = 0.0; i < values.length; i += step) {
        final idx = i.toInt();
        if (idx < values.length) {
          sLabels.add(labels[idx]);
          sValues.add(values[idx]);
        }
      }
      return _ChartData(sLabels, sValues, sampled: true);
    }
    return _ChartData(labels, values, sampled: false);
  }

  Widget _buildChartByType(List<num> values, List<String> labels) {
    switch (_selectedChartType) {
      case ChartType.line:
        return _buildLineChart(labels, values);
      case ChartType.pie:
        return _buildPieChart(labels, values);
      case ChartType.scatter:
        return _buildScatterChart(values);
      case ChartType.bar:
        return _buildBarChart(labels, values);
    }
  }

  Widget _buildBarChart(List<String> labels, List<num> values) {
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxValue / 5,
            getDrawingHorizontalLine: (value) => FlLine(
              color: context.themeColors.borderSubtle,
              strokeWidth: 1,
            ),
          ),
          titlesData: _buildTitlesData(labels),
          borderData: FlBorderData(show: false),
          barGroups: values.asMap().entries.map((entry) {
            return BarChartGroupData(
              x: entry.key,
              barRods: [
                BarChartRodData(
                  toY: entry.value.toDouble(),
                  color: context.themeColors.accentBlue,
                  width: 20,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLineChart(List<String> labels, List<num> values) {
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final minValue = values.reduce((a, b) => a < b ? a : b);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval:
                (maxValue - minValue) / 5.clamp(1, double.infinity),
            getDrawingHorizontalLine: (value) => FlLine(
              color: context.themeColors.borderSubtle,
              strokeWidth: 1,
            ),
          ),
          titlesData: _buildTitlesData(labels),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: values
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value.toDouble()))
                  .toList(),
              isCurved: true,
              color: context.themeColors.accentBlue,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: context.themeColors.accentBlue,
                    strokeWidth: 2,
                    strokeColor: context.themeColors.bgSecondary,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(List<String> labels, List<num> values) {
    final colors = [
      context.themeColors.accentBlue,
      context.themeColors.accentGreen,
      context.themeColors.accentOrange,
      context.themeColors.accentPurple,
      context.themeColors.accentPink,
      context.themeColors.accentCyan,
    ];
    final total = values.reduce((a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: values.asMap().entries.map((entry) {
                  final percentage = entry.value / total;
                  return PieChartSectionData(
                    value: entry.value.toDouble(),
                    title: '${(percentage * 100).toStringAsFixed(1)}%',
                    color: colors[entry.key % colors.length],
                    radius: 80,
                    titleStyle: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: labels.asMap().entries.map((entry) {
              final percentage = values[entry.key] / total;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[entry.key % colors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.value}: ${(percentage * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 散点图（R2: 2 数值列相关性）。
  /// X/Y 轴都作为数值处理，直接 fl_chart ScatterChart。
  Widget _buildScatterChart(List<num> values) {
    // 散点图需要两个数值列：X 和 Y 都从数据提取（非聚合）。
    // 这里 _extractChartData 已按 Y 轴聚合一组 values（index 作 X），
    // 散点场景改为：X 列原始值 vs Y 列原始值（逐行配对）。
    final spots = <ScatterSpot>[];
    for (final row in widget.data.take(_kMaxPoints)) {
      final xRaw = row[_selectedXAxis];
      final yRaw = row[_selectedYAxis];
      final x = xRaw is num
          ? xRaw.toDouble()
          : double.tryParse(xRaw?.toString() ?? '');
      final y = yRaw is num
          ? yRaw.toDouble()
          : double.tryParse(yRaw?.toString() ?? '');
      if (x != null && y != null) {
        spots.add(
          ScatterSpot(
            x,
            y,
            dotPainter: FlDotCirclePainter(
              radius: 4,
              color: context.themeColors.accentBlue,
            ),
          ),
        );
      }
    }
    if (spots.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.chartCannotGenerate,
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }
    final xs = spots.map((s) => s.x).toList();
    final ys = spots.map((s) => s.y).toList();
    final minX = xs.reduce((a, b) => a < b ? a : b);
    final maxX = xs.reduce((a, b) => a > b ? a : b);
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final xPad = (maxX - minX).abs() < 0.001 ? 1.0 : (maxX - minX) * 0.05;
    final yPad = (maxY - minY).abs() < 0.001 ? 1.0 : (maxY - minY) * 0.05;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ScatterChart(
        ScatterChartData(
          scatterSpots: spots,
          minX: minX - xPad,
          maxX: maxX + xPad,
          minY: minY - yPad,
          maxY: maxY + yPad,
          gridData: FlGridData(show: false),
          titlesData: FlTitlesData(
            show: true,
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 40),
            ),
            bottomTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 28),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  FlTitlesData _buildTitlesData(List<String> labels) {
    return FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) => Text(
            value.toString(),
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
            ),
          ),
          reservedSize: 50,
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) {
            final index = value.toInt();
            if (index >= 0 && index < labels.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  labels[index].length > 10
                      ? '${labels[index].substring(0, 10)}...'
                      : labels[index],
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          },
          reservedSize: 60,
        ),
      ),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );
  }
}

/// 提取后的图表数据 + 是否采样标记。
class _ChartData {
  final List<String> labels;
  final List<num> samples;
  final bool sampled;
  const _ChartData(this.labels, this.samples, {required this.sampled});
}
