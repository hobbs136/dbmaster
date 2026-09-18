import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/result_filter.dart';
import '../../services/result_statistics_service.dart';

/// StatisticsPanel - 查询结果统计面板（R3: 就地分析）
///
/// 显示数据的统计分析：总数、数值列的 sum/avg/min/max/median、分类列的
/// distinct/TOP5、日期列的范围/跨度。内部调 [ResultStatisticsService]。
///
/// 点击统计值/列名可触发 [onGenerateSql] 回调（生成 SQL 到新 Tab，R3）。
/// 数据量 >10K 行时显示降级提示（建议用 SQL 聚合）。
class StatisticsPanel extends StatefulWidget {
  final List<Map<String, dynamic>> data;

  /// 列类型映射（可选，来自 ResultFilterService）。不传时内部按值推断。
  final Map<String, ColumnDataType>? columnTypes;

  /// 点击数值统计值（如 AVG）→ 生成聚合 SQL 的回调。null 时禁用点击。
  final void Function(String column, String agg)? onStatsValueTap;

  /// 点击分类列名 → 生成 GROUP BY SQL 的回调。null 时禁用点击。
  final void Function(String column)? onCategoryColumnTap;

  const StatisticsPanel({
    super.key,
    required this.data,
    this.columnTypes,
    this.onStatsValueTap,
    this.onCategoryColumnTap,
  });

  @override
  State<StatisticsPanel> createState() => _StatisticsPanelState();
}

class _StatisticsPanelState extends State<StatisticsPanel> {
  List<ColumnStatistics>? _stats;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void didUpdateWidget(StatisticsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data ||
        oldWidget.columnTypes != widget.columnTypes) {
      _compute();
    }
  }

  void _compute() {
    try {
      final types = widget.columnTypes ?? _inferColumnTypes();
      _stats = ResultStatisticsService.compute(
        data: widget.data,
        columnTypes: types,
      );
      _errorMessage = null;
    } on DatasetTooLargeException catch (e) {
      _stats = null;
      _errorMessage = e.toString();
    }
  }

  /// 无 columnTypes 时从数据推断（数值 vs 非数值）。
  Map<String, ColumnDataType> _inferColumnTypes() {
    if (widget.data.isEmpty) return {};
    final types = <String, ColumnDataType>{};
    for (final col in widget.data.first.keys) {
      bool allNumeric = true;
      for (final row in widget.data) {
        final v = row[col];
        if (v != null && v is! num) {
          allNumeric = false;
          break;
        }
      }
      types[col] = allNumeric ? ColumnDataType.numeric : ColumnDataType.string;
    }
    return types;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (widget.data.isEmpty) {
      return _buildEmptyState(context, l10n);
    }

    // 大数据降级提示（NF1）
    if (_errorMessage != null) {
      return _buildTooLargeState(context, l10n, _errorMessage!);
    }

    final stats = _stats ?? const [];
    final totalRows = widget.data.length;
    final numericCount = stats.where((s) => s.isNumeric).length;
    final otherCount = stats.length - numericCount;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI 卡片行
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: l10n.statisticsTotalRows,
                  value: totalRows.toString(),
                  icon: LucideIcons.clipboardList,
                  color: context.themeColors.accentBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: l10n.statisticsNumeric,
                  value: numericCount.toString(),
                  icon: LucideIcons.pin,
                  color: context.themeColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: l10n.statisticsText,
                  value: otherCount.toString(),
                  icon: LucideIcons.type,
                  color: context.themeColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 数值统计表
          if (stats.any((s) => s.isNumeric)) ...[
            _buildNumericStatsTable(
              context,
              l10n,
              stats.where((s) => s.isNumeric).toList(),
            ),
            const SizedBox(height: 16),
          ],
          // 分类列 TOP5
          if (stats.any((s) => s.isCategorical)) ...[
            _buildCategoricalStats(
              context,
              l10n,
              stats.where((s) => s.isCategorical).toList(),
            ),
            const SizedBox(height: 16),
          ],
          // 日期列范围
          if (stats.any((s) => s.isDateTime))
            _buildDateTimeStats(
              context,
              l10n,
              stats.where((s) => s.isDateTime).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildNumericStatsTable(
    BuildContext context,
    AppLocalizations l10n,
    List<ColumnStatistics> numericStats,
  ) {
    if (numericStats.isEmpty) return const SizedBox.shrink();
    final columns = numericStats.map((s) => s.name).toList();
    // 含 median 的指标列表（R3 扩展）
    final metrics = <_Metric>[
      _Metric(
        'count',
        l10n.statisticsCount,
        (s) => s.count?.toString(),
        canGenerateSql: true,
        sqlAgg: 'COUNT',
      ),
      _Metric(
        'sum',
        l10n.statisticsSum,
        (s) => _fmt(s.sum),
        canGenerateSql: true,
        sqlAgg: 'SUM',
      ),
      _Metric(
        'avg',
        l10n.statisticsAvg,
        (s) => _fmt(s.avg),
        canGenerateSql: true,
        sqlAgg: 'AVG',
      ),
      _Metric('median', 'Median', (s) => _fmt(s.median)),
      _Metric(
        'min',
        l10n.statisticsMin,
        (s) => _fmt(s.min),
        canGenerateSql: true,
        sqlAgg: 'MIN',
      ),
      _Metric(
        'max',
        l10n.statisticsMax,
        (s) => _fmt(s.max),
        canGenerateSql: true,
        sqlAgg: 'MAX',
      ),
      _Metric('null', 'Null', (s) => s.nullCount?.toString()),
    ];

    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.statisticsNumericStats,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.themeColors.textPrimary,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                context.themeColors.bgSecondary,
              ),
              dataRowMinHeight: 36,
              dataRowMaxHeight: 36,
              horizontalMargin: 16,
              columnSpacing: 24,
              columns: [
                DataColumn(
                  label: Text(
                    l10n.statisticsFieldInfo,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textSecondary,
                    ),
                  ),
                ),
                ...columns.map(
                  (col) => DataColumn(
                    label: Text(
                      col,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.themeColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
              rows: metrics.map((m) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        m.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ),
                    ...columns.map((colName) {
                      final stat = numericStats.firstWhere(
                        (s) => s.name == colName,
                      );
                      final value = m.getValue(stat) ?? '-';
                      // 数值指标可点击生成 SQL（R3）
                      return DataCell(
                        widget.onStatsValueTap != null && m.canGenerateSql
                            ? InkWell(
                                onTap: () =>
                                    widget.onStatsValueTap!(colName, m.sqlAgg),
                                child: Text(
                                  value,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.themeColors.accentBlue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              )
                            : Text(
                                value,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.themeColors.textPrimary,
                                ),
                              ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCategoricalStats(
    BuildContext context,
    AppLocalizations l10n,
    List<ColumnStatistics> catStats,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '分类列统计（distinct + TOP 5）',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...catStats.map((s) => _buildCategoricalColumn(context, l10n, s)),
        ],
      ),
    );
  }

  Widget _buildCategoricalColumn(
    BuildContext context,
    AppLocalizations l10n,
    ColumnStatistics s,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 列名可点击 → 生成 GROUP BY（R3）
              widget.onCategoryColumnTap != null
                  ? InkWell(
                      onTap: () => widget.onCategoryColumnTap!(s.name),
                      child: Text(
                        s.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.accentBlue,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    )
                  : Text(
                      s.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.themeColors.textPrimary,
                      ),
                    ),
              const SizedBox(width: 8),
              Text(
                '(${s.distinctCount ?? 0} 个唯一值)',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ],
          ),
          if (s.topValues != null && s.topValues!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: s.topValues!.map((e) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: context.themeColors.bgSecondary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${e.key}: ${e.value}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateTimeStats(
    BuildContext context,
    AppLocalizations l10n,
    List<ColumnStatistics> dtStats,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '日期列范围',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...dtStats.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text(
                    '${s.name}: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  Text(
                    s.dateMin != null && s.dateMax != null
                        ? '${_fmtDate(s.dateMin)} → ${_fmtDate(s.dateMax)}'
                        : '-',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeColors.textSecondary,
                    ),
                  ),
                  if (s.dateSpan != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.themeColors.accentPurple.withValues(
                          alpha: 0.15,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '跨度 ${s.dateSpan}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.themeColors.accentPurple,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(num? v) {
    if (v == null) return '-';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2);
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '-';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations l10n) {
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
            l10n.resultsNoDataStatisticsMessage,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTooLargeState(
    BuildContext context,
    AppLocalizations l10n,
    String message,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.gauge, size: 48, color: context.themeColors.warning),
          const SizedBox(height: 16),
          Text(
            '数据量过大',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.themeColors.warning,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '建议用 SQL 聚合查询，如：',
            style: TextStyle(
              fontSize: 12,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(
              'SELECT column, AVG(value)\nFROM table\nGROUP BY column;',
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 数值指标描述（label + 取值 + 是否可生成 SQL）。
class _Metric {
  final String key;
  final String label;
  final String? Function(ColumnStatistics) getValue;
  final bool canGenerateSql;
  final String sqlAgg;
  const _Metric(
    this.key,
    this.label,
    this.getValue, {
    this.canGenerateSql = false,
    this.sqlAgg = '',
  });
}

/// _KpiCard - 紧凑型 KPI 卡片
class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
