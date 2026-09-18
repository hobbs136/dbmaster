/// Performance Analyzer Dialog
/// 性能分析对话框 - 提供慢查询分析、索引统计、表统计和性能报告生成功能
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import '../../providers/server_connection_provider.dart';
import '../../services/performance_analyzer_service.dart';
import '../../services/telemetry_service.dart';
import '../../services/lite_touchpoint_gate.dart';
import '../server/conversion_guide_row.dart';
import '../../models/performance_models.dart';
import '../../molecules/dialog_connection_selector.dart';
import '../../atoms/app_loading.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

/// Landing page for the "slow query weekly report" / "server automation" pitch.
/// TODO(marketing): final URL pending; harmless default for now.
const String _kServerLearnMoreUrl =
    'https://dbmaster.tech-site/server/learn-more';

class PerformanceAnalyzerDialog extends StatefulWidget {
  final String? initialConnectionId;
  final String? initialDatabase;

  const PerformanceAnalyzerDialog({
    super.key,
    this.initialConnectionId,
    this.initialDatabase,
  });

  @override
  State<PerformanceAnalyzerDialog> createState() =>
      _PerformanceAnalyzerDialogState();
}

class _PerformanceAnalyzerDialogState extends State<PerformanceAnalyzerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  PerformanceAnalyzerService? _service;

  // 数据
  List<SlowQuery> _slowQueries = [];
  List<TableStatistics> _tableStats = [];
  List<IndexUsage> _indexUsage = [];
  List<PerformanceSuggestion> _suggestions = [];
  DatabaseSummary _summary = DatabaseSummary();
  PerformanceReport? _report;

  // 状态
  bool _isLoading = false;
  String? _errorMessage;
  int _selectedSlowQueryIndex = -1;
  List<QueryExecutionPlan> _executionPlan = [];

  // 筛选
  String _searchText = '';
  double _slowQueryThreshold = 1.0;

  String? _selectedConnectionId;
  String? _selectedDatabase;
  List<String> _dialogDatabases = [];

  // Cache the lite-touchpoint gate future so FutureBuilder does not re-fire on
  // every rebuild (would otherwise cause a "no data" flash and re-evaluate the
  // SharedPreferences read repeatedly).
  late final Future<bool> _slowQueryLiteGateFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _selectedConnectionId = widget.initialConnectionId;
    _selectedDatabase = widget.initialDatabase;
    if (_selectedConnectionId != null) {
      _loadDatabasesForConnection(_selectedConnectionId!);
      _initService();
      // feature_used exposure — only when an actual connection is
      // pre-selected, so opening the dialog "just to look" is not counted.
      TelemetryService.instance.logFeatureUsed('performance_analyzer_open');
    }
    _slowQueryLiteGateFuture = LiteTouchpointGate.instance.shouldShowLite(
      guideId: 'slow-query-panel',
      featureId: 'performance_analyzer_open',
    );
  }

  /// Launches the slow-query-report learn-more page. Shared by both the
  /// full and lite guide variants.
  Future<void> _launchLearnMoreUrl() async {
    final uri = Uri.parse(_kServerLearnMoreUrl);
    try {
      await launchUrl(uri);
    } catch (_) {
      // Best-effort launch; ignore failure silently (click already counted).
    }
  }

  Future<void> _loadDatabasesForConnection(String connectionId) async {
    final provider = context.read<AppProvider>();
    final databases = await provider.connection.dbService.getDatabases(
      connectionId: connectionId,
    );
    if (mounted) {
      setState(() {
        _dialogDatabases = databases;
        // 如果当前选中的数据库不在列表中，且列表不为空，则选择第一个
        if (_selectedDatabase != null &&
            !databases.contains(_selectedDatabase) &&
            databases.isNotEmpty) {
          _selectedDatabase = databases.first;
        }
      });
    }
  }

  void _initService() {
    final provider = context.read<AppProvider>();
    if (provider.connection.dbService.isConnected) {
      _service = PerformanceAnalyzerService(provider.connection.dbService);
      _loadAllData();
    }
  }

  Future<void> _reloadService() async {
    final connectionId = _selectedConnectionId;
    if (connectionId == null) return;

    final provider = context.read<AppProvider>();

    if (provider.connection.dbService.isConnected) {
      _service = PerformanceAnalyzerService(provider.connection.dbService);
      await provider.connection.withConnection(
        connectionId,
        _selectedDatabase,
        () => _loadAllData(),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    if (_service == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _service!.analyzeSlowQueries(
          threshold: _slowQueryThreshold,
          limit: 100,
        ),
        _service!.getTableStatistics(),
        _service!.getAllIndexUsage(),
        _service!.suggestIndexes(),
        _service!.getDatabaseSummary(),
      ]);

      setState(() {
        _slowQueries = results[0] as List<SlowQuery>;
        _tableStats = results[1] as List<TableStatistics>;
        _indexUsage = results[2] as List<IndexUsage>;
        _suggestions = results[3] as List<PerformanceSuggestion>;
        _summary = results[4] as DatabaseSummary;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _generateReport() async {
    if (_service == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final report = await _service!.generateReport();
      setState(() {
        _report = report;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _analyzeQuery(SlowQuery query, int index) async {
    if (_service == null) return;

    setState(() {
      _selectedSlowQueryIndex = index;
      _executionPlan = [];
    });

    try {
      final plan = await _service!.getExecutionPlan(query.query);
      setState(() {
        _executionPlan = plan;
      });
    } catch (e) {
      // 执行计划分析失败，忽略
    }
  }

  Future<void> _exportReport() async {
    final l10n = AppLocalizations.of(context)!;
    if (_service == null || _report == null) {
      await _generateReport();
    }

    if (_report == null) return;

    final json = _service!.exportReportToJson(_report!);

    if (mounted) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: Theme.of(dialogContext).brightness == Brightness.dark
              ? const Color(0xFF2D2D2D)
              : Colors.white,
          title: Text(
            l10n.exportFile,
            style: TextStyle(
              color: Theme.of(dialogContext).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
          content: Container(
            width: 600,
            height: 400,
            decoration: BoxDecoration(
              color: Theme.of(dialogContext).brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              child: SelectableText(
                json,
                style: TextStyle(
                  color: Theme.of(dialogContext).brightness == Brightness.dark
                      ? Colors.white70
                      : Colors.black54,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.commonClose),
            ),
          ],
        ),
      );
    }
  }

  List<SlowQuery> get _filteredSlowQueries {
    if (_searchText.isEmpty) return _slowQueries;
    return _slowQueries
        .where(
          (q) =>
              q.query.toLowerCase().contains(_searchText.toLowerCase()) ||
              q.database.toLowerCase().contains(_searchText.toLowerCase()),
        )
        .toList();
  }

  List<TableStatistics> get _filteredTables {
    if (_searchText.isEmpty) return _tableStats;
    return _tableStats
        .where(
          (t) => t.tableName.toLowerCase().contains(_searchText.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();

    return Dialog(
      backgroundColor: context.themeColors.bgPrimary,
      child: Container(
        width: 1200,
        height: 800,
        decoration: BoxDecoration(
          color: context.themeColors.bgPrimary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          border: Border.all(color: context.themeColors.borderColor),
        ),
        child: Column(
          children: [
            DialogConnectionSelector(
              selectedConnectionId: _selectedConnectionId,
              selectedDatabase: _selectedDatabase,
              databases: _dialogDatabases,
              onConnectionChanged: (connectionId) {
                setState(() {
                  _selectedConnectionId = connectionId;
                  _selectedDatabase = null;
                });
                if (connectionId != null) {
                  _loadDatabasesForConnection(connectionId);
                } else {
                  setState(() {
                    _dialogDatabases = [];
                  });
                }
                _reloadService();
              },
              onDatabaseChanged: (database) {
                setState(() {
                  _selectedDatabase = database;
                });
                _reloadService();
              },
            ),
            if (!provider.connection.dbService.isConnected)
              Expanded(child: _buildNotConnectedDialog())
            else ...[
              _buildHeader(),
              _buildTabBar(),
              Expanded(
                child: _isLoading
                    ? _buildLoadingWidget()
                    : _errorMessage != null
                    ? _buildErrorWidget()
                    : _buildTabContent(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotConnectedDialog() {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      backgroundColor: context.themeColors.bgPrimary,
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(AppDesignSystem.space6),
        decoration: BoxDecoration(
          color: context.themeColors.bgPrimary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.triangleAlert,
              color: context.themeColors.warning,
              size: 48,
            ),
            const SizedBox(height: AppDesignSystem.space4),
            Text(
              l10n.performanceAnalyzerNotConnected,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              l10n.performanceAnalyzerNotConnectedDesc,
              style: TextStyle(color: context.themeColors.textSecondary),
            ),
            const SizedBox(height: AppDesignSystem.space6),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentBlue,
              ),
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.gauge,
            color: context.themeColors.accentBlue,
            size: 24,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Text(
            l10n.performanceAnalyzerTitle,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.bold,
              color: context.themeColors.textPrimary,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 250,
            child: TextField(
              decoration: InputDecoration(
                hintText: l10n.searchPlaceholder,
                hintStyle: TextStyle(color: context.themeColors.textMuted),
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 18,
                  color: context.themeColors.textMuted,
                ),
                filled: true,
                fillColor: context.themeColors.bgTertiary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space3,
                  vertical: AppDesignSystem.space2,
                ),
              ),
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 13,
              ),
              onChanged: (value) => setState(() => _searchText = value),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          IconButton(
            icon: Icon(
              LucideIcons.refreshCw,
              color: context.themeColors.textSecondary,
            ),
            onPressed: _isLoading ? null : _loadAllData,
            tooltip: l10n.refreshData,
          ),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _generateReport,
            icon: const Icon(LucideIcons.chartColumn, size: 16),
            label: Text(l10n.performanceAnalyzerGenerateReport),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space4,
                vertical: AppDesignSystem.space2,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportReport,
            icon: const Icon(LucideIcons.download, size: 16),
            label: Text(l10n.performanceAnalyzerExport),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space4,
                vertical: AppDesignSystem.space2,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          IconButton(
            icon: Icon(LucideIcons.x, color: context.themeColors.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: l10n.closeBtn,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: context.themeColors.bgSecondary,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabs: [
          Tab(
            icon: const Icon(LucideIcons.chartLine, size: 18),
            text: l10n.performanceAnalyzerSlowQueryAnalysis,
          ),
          Tab(
            icon: const Icon(LucideIcons.database, size: 18),
            text: l10n.performanceAnalyzerIndexAnalysis,
          ),
          Tab(
            icon: const Icon(LucideIcons.table2, size: 18),
            text: l10n.performanceAnalyzerTableStatistics,
          ),
          Tab(
            icon: const Icon(LucideIcons.chartColumn, size: 18),
            text: l10n.performanceAnalyzerPerformanceReport,
          ),
        ],
        labelColor: context.themeColors.accentBlue,
        unselectedLabelColor: context.themeColors.textMuted,
        indicatorColor: context.themeColors.accentBlue,
        indicatorWeight: 2,
      ),
    );
  }

  Widget _buildLoadingWidget() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: AppBrandedLoading(
        size: 32,
        label: l10n.analyzingDatabasePerformance,
      ),
    );
  }

  Widget _buildErrorWidget() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.circleAlert,
            color: context.themeColors.error,
            size: 48,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.loadFailed(_errorMessage!),
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            _errorMessage!,
            style: TextStyle(color: context.themeColors.textMuted),
          ),
          const SizedBox(height: AppDesignSystem.space6),
          ElevatedButton(
            onPressed: _loadAllData,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
            ),
            child: Text(l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildSlowQueriesTab(),
        _buildIndexAnalysisTab(),
        _buildTableStatsTab(),
        _buildReportTab(),
      ],
    );
  }

  // ========== 慢查询分析 Tab ==========
  Widget _buildSlowQueriesTab() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        // 左侧查询列表
        Expanded(
          flex: 1,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: context.themeColors.borderColor),
              ),
            ),
            child: Column(
              children: [
                // 阈值设置
                Container(
                  padding: const EdgeInsets.all(AppDesignSystem.space3),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: context.themeColors.borderColor,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        l10n.timeThreshold,
                        style: TextStyle(
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      Expanded(
                        child: Slider(
                          value: _slowQueryThreshold,
                          min: 0.1,
                          max: 10.0,
                          divisions: 99,
                          label: '${_slowQueryThreshold.toStringAsFixed(1)}s',
                          activeColor: context.themeColors.accentBlue,
                          onChanged: (value) {
                            setState(() {
                              _slowQueryThreshold = value;
                            });
                          },
                          onChangeEnd: (value) => _loadAllData(),
                        ),
                      ),
                      Text(
                        '${_slowQueryThreshold.toStringAsFixed(1)}s',
                        style: TextStyle(
                          color: context.themeColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 查询列表
                Expanded(
                  child: _filteredSlowQueries.isEmpty
                      ? Center(
                          child: Text(
                            l10n.performanceAnalyzerNoSlowQueries,
                            style: TextStyle(
                              color: context.themeColors.textMuted,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredSlowQueries.length,
                          itemBuilder: (context, index) {
                            final query = _filteredSlowQueries[index];
                            final isSelected = index == _selectedSlowQueryIndex;
                            return _buildSlowQueryItem(
                              query,
                              index,
                              isSelected,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        // 右侧详情
        Expanded(
          flex: 2,
          child:
              _selectedSlowQueryIndex >= 0 &&
                  _selectedSlowQueryIndex < _filteredSlowQueries.length
              ? _buildSlowQueryDetail(
                  _filteredSlowQueries[_selectedSlowQueryIndex],
                )
              : Center(
                  child: Text(
                    l10n.performanceAnalyzerSelectQuery,
                    style: TextStyle(color: context.themeColors.textMuted),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSlowQueryItem(SlowQuery query, int index, bool isSelected) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => _analyzeQuery(query, index),
      child: Container(
        padding: const EdgeInsets.all(AppDesignSystem.space3),
        decoration: BoxDecoration(
          color: isSelected ? context.themeColors.bgHover : null,
          border: Border(
            bottom: BorderSide(color: context.themeColors.borderColor),
            left: isSelected
                ? BorderSide(color: context.themeColors.accentBlue, width: 3)
                : BorderSide.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space1_5,
                    vertical: AppDesignSystem.space0_5,
                  ),
                  decoration: BoxDecoration(
                    color: _getTimeColor(query.executionTime),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Text(
                    query.executionTimeFormatted,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    query.database,
                    style: TextStyle(
                      color: context.themeColors.textSecondary,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatTimeAgo(query.timestamp, l10n),
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              query.query.length > 80
                  ? '${query.query.substring(0, 80)}...'
                  : query.query,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 13,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Color _getTimeColor(double seconds) {
    if (seconds >= 5) return context.themeColors.error;
    if (seconds >= 2) return context.themeColors.warning;
    return context.themeColors.success;
  }

  String _formatTimeAgo(DateTime time, AppLocalizations l10n) {
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) return l10n.timeAgoDays(diff.inDays);
    if (diff.inHours > 0) return l10n.timeAgoHours(diff.inHours);
    if (diff.inMinutes > 0) return l10n.timeAgoMinutes(diff.inMinutes);
    return l10n.timeAgoJustNow;
  }

  Widget _buildSlowQueryDetail(SlowQuery query) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 基本信息卡片
          _buildDetailCard(l10n.performanceAnalyzerQueryInfo, [
            _buildDetailRow(
              l10n.performanceAnalyzerExecutionTime,
              query.executionTimeFormatted,
            ),
            _buildDetailRow(l10n.performanceAnalyzerDatabase, query.database),
            if (query.rowsExamined != null)
              _buildDetailRow(
                l10n.performanceAnalyzerRowsScaned,
                query.rowsExamined.toString(),
              ),
            if (query.rowsSent != null)
              _buildDetailRow(
                l10n.performanceAnalyzerRowsReturned,
                query.rowsSent.toString(),
              ),
            _buildDetailRow(
              l10n.performanceAnalyzerTimestamp,
              query.timestamp.toString(),
            ),
          ]),
          const SizedBox(height: AppDesignSystem.space4),
          // SQL 语句
          _buildDetailCard(l10n.performanceAnalyzerSqlStatement, [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.bgPrimary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(color: context.themeColors.borderColor),
              ),
              child: SelectableText(
                query.query,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 13,
                ),
              ),
            ),
          ]),
          const SizedBox(height: AppDesignSystem.space4),
          // 执行计划
          if (_executionPlan.isNotEmpty)
            _buildDetailCard(l10n.performanceAnalyzerExecutionPlan, [
              _buildExecutionPlanTable(),
            ]),
          const SizedBox(height: AppDesignSystem.space4),
          // 优化建议
          _buildOptimizationSuggestions(query),
        ],
      ),
    );
  }

  Widget _buildExecutionPlanTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          context.themeColors.bgTertiary,
        ),
        dataRowColor: WidgetStateProperty.all(context.themeColors.bgPrimary),
        border: TableBorder.all(color: context.themeColors.borderColor),
        columns: [
          DataColumn(
            label: Text(
              'id',
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
          DataColumn(
            label: Text(
              'select_type',
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
          DataColumn(
            label: Text(
              'table',
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
          DataColumn(
            label: Text(
              'type',
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
          DataColumn(
            label: Text(
              'key',
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
          DataColumn(
            label: Text(
              'rows',
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
          DataColumn(
            label: Text(
              'Extra',
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
        ],
        rows: _executionPlan
            .map(
              (plan) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      '${plan.id}',
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      plan.selectType,
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      plan.table,
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space1_5,
                        vertical: AppDesignSystem.space0_5,
                      ),
                      decoration: BoxDecoration(
                        color: plan.isFullTableScan
                            ? context.themeColors.error.withAlpha(51)
                            : null,
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                      child: Text(
                        plan.type,
                        style: TextStyle(
                          color: plan.isFullTableScan
                              ? context.themeColors.error
                              : context.themeColors.textSecondary,
                          fontWeight: plan.isFullTableScan
                              ? FontWeight.bold
                              : null,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      plan.key ?? 'NULL',
                      style: TextStyle(
                        color: plan.isUsingIndex
                            ? context.themeColors.success
                            : context.themeColors.error,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${plan.rows ?? '-'}',
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      plan.extra ?? '',
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildOptimizationSuggestions(SlowQuery query) {
    final l10n = AppLocalizations.of(context)!;
    final suggestions = <Widget>[];

    // 根据执行计划给出建议
    if (_executionPlan.any((p) => p.isFullTableScan)) {
      suggestions.add(
        _buildSuggestionItem(
          LucideIcons.triangleAlert,
          context.themeColors.warning,
          l10n.optimizationFullTableScan,
          l10n.optimizationFullTableScanDesc,
        ),
      );
    }

    if (_executionPlan.any((p) => p.extra?.contains('filesort') ?? false)) {
      suggestions.add(
        _buildSuggestionItem(
          LucideIcons.arrowUpDown,
          context.themeColors.warning,
          l10n.optimizationFilesort,
          l10n.optimizationFilesortDesc,
        ),
      );
    }

    if (_executionPlan.any((p) => p.extra?.contains('temporary') ?? false)) {
      suggestions.add(
        _buildSuggestionItem(
          LucideIcons.database,
          context.themeColors.warning,
          l10n.optimizationTemporary,
          l10n.optimizationTemporaryDesc,
        ),
      );
    }

    if (query.rowsExamined != null && query.rowsSent != null) {
      final ratio =
          query.rowsExamined! / (query.rowsSent! > 0 ? query.rowsSent! : 1);
      if (ratio > 100) {
        suggestions.add(
          _buildSuggestionItem(
            LucideIcons.funnel,
            context.themeColors.error,
            l10n.optimizationLowEfficiency,
            l10n.optimizationLowEfficiencyDesc(
              query.rowsExamined!,
              query.rowsSent!,
              ratio.toStringAsFixed(1),
            ),
          ),
        );
      }
    }

    if (suggestions.isEmpty) {
      suggestions.add(
        _buildSuggestionItem(
          LucideIcons.circleCheckBig,
          context.themeColors.success,
          l10n.optimizationNoIssue,
          l10n.optimizationNoIssueDesc,
        ),
      );
    }

    return _buildDetailCard(l10n.optimizationSuggestions, suggestions);
  }

  Widget _buildSuggestionItem(
    IconData icon,
    Color color,
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  description,
                  style: TextStyle(
                    color: context.themeColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ========== 索引分析 Tab ==========
  Widget _buildIndexAnalysisTab() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        // 左侧图表
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.all(AppDesignSystem.space4),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: context.themeColors.borderColor),
              ),
            ),
            child: Column(
              children: [
                Text(
                  l10n.indexTypeDistribution,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space4),
                Expanded(child: _buildIndexPieChart()),
                const SizedBox(height: AppDesignSystem.space4),
                // 统计信息
                _buildIndexStatsSummary(),
              ],
            ),
          ),
        ),
        // 右侧索引列表
        Expanded(flex: 2, child: _buildIndexList()),
      ],
    );
  }

  Widget _buildIndexPieChart() {
    final l10n = AppLocalizations.of(context)!;
    final primaryCount = _indexUsage.where((i) => i.isPrimary).length;
    final uniqueCount = _indexUsage
        .where((i) => i.isUnique && !i.isPrimary)
        .length;
    final normalCount = _indexUsage
        .where((i) => !i.isUnique && !i.isPrimary)
        .length;

    if (_indexUsage.isEmpty) {
      return Center(
        child: Text(
          l10n.noData,
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }

    final data = [
      PieChartSectionData(
        value: primaryCount.toDouble(),
        title: '${l10n.indexTypePrimary}\n$primaryCount',
        color: context.themeColors.accentBlue,
        radius: 80,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      PieChartSectionData(
        value: uniqueCount.toDouble(),
        title: '${l10n.indexTypeUnique}\n$uniqueCount',
        color: context.themeColors.success,
        radius: 80,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      PieChartSectionData(
        value: normalCount.toDouble(),
        title: '${l10n.indexTypeNormal}\n$normalCount',
        color: context.themeColors.warning,
        radius: 80,
        titleStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    ];

    return PieChart(
      PieChartData(sections: data, sectionsSpace: 2, centerSpaceRadius: 40),
    );
  }

  Widget _buildIndexStatsSummary() {
    final l10n = AppLocalizations.of(context)!;
    final total = _indexUsage.length;
    final used = _indexUsage.where((i) => i.isUsed).length;
    final unused = total - used;

    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            l10n.totalIndexes,
            total.toString(),
            context.themeColors.accentBlue,
          ),
          _buildStatItem(
            l10n.indexUsed,
            used.toString(),
            context.themeColors.success,
          ),
          _buildStatItem(
            l10n.indexUnused,
            unused.toString(),
            context.themeColors.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: context.themeColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildIndexList() {
    // 按表分组
    final grouped = <String, List<IndexUsage>>{};
    for (final index in _indexUsage) {
      if (!grouped.containsKey(index.tableName)) {
        grouped[index.tableName] = [];
      }
      grouped[index.tableName]!.add(index);
    }

    final tables = grouped.keys.toList()..sort();

    return ListView.builder(
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final tableName = tables[index];
        final indexes = grouped[tableName]!;
        return _buildTableIndexCard(tableName, indexes);
      },
    );
  }

  Widget _buildTableIndexCard(String tableName, List<IndexUsage> indexes) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1_5,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(
              LucideIcons.table2,
              size: 18,
              color: context.themeColors.accentBlue,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              tableName,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: AppDesignSystem.space0_5,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                '${indexes.length} ${l10n.performanceAnalyzerIndexes}',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        children: indexes.map((index) => _buildIndexItem(index)).toList(),
      ),
    );
  }

  Widget _buildIndexItem(IndexUsage index) {
    final l10n = AppLocalizations.of(context)!;
    IconData icon;
    Color color;

    if (index.isPrimary) {
      icon = LucideIcons.keyRound;
      color = context.themeColors.warning;
    } else if (index.isUnique) {
      icon = LucideIcons.lock;
      color = context.themeColors.success;
    } else {
      icon = LucideIcons.database;
      color = context.themeColors.accentBlue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: context.themeColors.borderColor.withOpacity(0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  index.indexName,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${l10n.performanceAnalyzerColumns} ${index.columns.join(', ')}',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (index.cardinality != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: AppDesignSystem.space0_5,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                '${l10n.performanceAnalyzerCardinality} ${index.cardinality}',
                style: TextStyle(
                  color: context.themeColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          const SizedBox(width: AppDesignSystem.space2),
          if (index.isUsed)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: AppDesignSystem.space0_5,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.success.withAlpha(51),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                l10n.indexUsed,
                style: TextStyle(
                  color: context.themeColors.success,
                  fontSize: 11,
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: AppDesignSystem.space0_5,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.warning.withAlpha(51),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                l10n.indexUnused,
                style: TextStyle(
                  color: context.themeColors.warning,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ========== 表统计 Tab ==========
  Widget _buildTableStatsTab() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        // 汇总卡片
        Container(
          padding: const EdgeInsets.all(AppDesignSystem.space4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: context.themeColors.borderColor),
            ),
          ),
          child: Row(
            children: [
              _buildSummaryCard(
                l10n.totalTables,
                '${_summary.tableCount}',
                LucideIcons.table2,
                context.themeColors.accentBlue,
              ),
              const SizedBox(width: AppDesignSystem.space3),
              _buildSummaryCard(
                l10n.totalRows,
                _formatNumber(_summary.totalRows),
                LucideIcons.listOrdered,
                context.themeColors.success,
              ),
              const SizedBox(width: AppDesignSystem.space3),
              _buildSummaryCard(
                l10n.dataSize,
                _summary.totalDataSizeFormatted,
                LucideIcons.database,
                context.themeColors.warning,
              ),
              const SizedBox(width: AppDesignSystem.space3),
              _buildSummaryCard(
                l10n.indexSize,
                _summary.totalIndexSizeFormatted,
                LucideIcons.database,
                context.themeColors.accentPurple,
              ),
            ],
          ),
        ),
        // 图表和数据表
        Expanded(
          child: Row(
            children: [
              // 左侧图表
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.all(AppDesignSystem.space4),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: context.themeColors.borderColor),
                    ),
                  ),
                  child: _buildTableSizeChart(),
                ),
              ),
              // 右侧数据表
              Expanded(flex: 2, child: _buildTableDataTable()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppDesignSystem.space4),
        decoration: BoxDecoration(
          color: context.themeColors.bgSecondary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          border: Border.all(color: context.themeColors.borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: AppDesignSystem.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.themeColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space1),
                  Text(
                    value,
                    style: TextStyle(
                      color: context.themeColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableSizeChart() {
    final l10n = AppLocalizations.of(context)!;
    if (_filteredTables.isEmpty) {
      return Center(
        child: Text(
          l10n.noData,
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }

    // 取前10个最大的表
    final topTables = _filteredTables.take(10).toList();
    final maxSize = topTables
        .map((t) => t.totalSize)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tableSizeDistribution,
          style: TextStyle(
            color: context.themeColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space4),
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxSize * 1.2,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipBorder: BorderSide(
                    color: context.themeColors.borderColor,
                  ),
                  tooltipBgColor: context.themeColors.bgSecondary,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final table = topTables[groupIndex];
                    return BarTooltipItem(
                      '${table.tableName}\n${table.totalSizeFormatted}',
                      TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        _formatBytesShort(value.toInt()),
                        style: TextStyle(
                          color: context.themeColors.textMuted,
                          fontSize: 11,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value >= 0 && value < topTables.length) {
                        return Padding(
                          padding: const EdgeInsets.only(
                            top: AppDesignSystem.space2,
                          ),
                          child: Text(
                            topTables[value.toInt()].tableName.length > 6
                                ? '${topTables[value.toInt()].tableName.substring(0, 6)}...'
                                : topTables[value.toInt()].tableName,
                            style: TextStyle(
                              color: context.themeColors.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                horizontalInterval: maxSize / 5,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: context.themeColors.borderColor.withOpacity(0.3),
                    strokeWidth: 1,
                  );
                },
              ),
              barGroups: topTables.asMap().entries.map((entry) {
                return BarChartGroupData(
                  x: entry.key,
                  barRods: [
                    BarChartRodData(
                      toY: entry.value.totalSize.toDouble(),
                      color: context.themeColors.accentBlue,
                      width: 20,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppDesignSystem.radiusSm),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _formatBytesShort(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}K';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}M';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  Widget _buildTableDataTable() {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(
          context.themeColors.bgTertiary,
        ),
        dataRowColor: WidgetStateProperty.all(context.themeColors.bgPrimary),
        border: TableBorder.all(
          color: context.themeColors.borderColor.withOpacity(0.5),
        ),
        columns: [
          DataColumn(
            label: Text(
              l10n.tableNameLabel,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              l10n.tableEngineLabel,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              l10n.tableRowCountLabel,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              l10n.dataSize,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              l10n.indexSize,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              l10n.tableTotalSizeLabel,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        rows: _filteredTables
            .map(
              (table) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      table.tableName,
                      style: TextStyle(color: context.themeColors.textPrimary),
                    ),
                  ),
                  DataCell(
                    Text(
                      table.engine ?? '-',
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatNumber(table.rowCount),
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      table.dataSizeFormatted,
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      table.indexSizeFormatted,
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      table.totalSizeFormatted,
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }

  // ========== 性能报告 Tab ==========
  Widget _buildReportTab() {
    final l10n = AppLocalizations.of(context)!;
    if (_report == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.chartColumn,
              size: 64,
              color: context.themeColors.textMuted,
            ),
            const SizedBox(height: AppDesignSystem.space4),
            Text(
              l10n.performanceAnalyzerClickGenerateReport,
              style: TextStyle(color: context.themeColors.textMuted),
            ),
            const SizedBox(height: AppDesignSystem.space6),
            ElevatedButton.icon(
              onPressed: _generateReport,
              icon: const Icon(LucideIcons.play),
              label: Text(l10n.performanceAnalyzerGenerateReport),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentBlue,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space8,
                  vertical: AppDesignSystem.space4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 报告头部
          _buildReportHeader(),
          const SizedBox(height: AppDesignSystem.space6),
          // 优化建议
          if (_suggestions.isNotEmpty) ...[
            _buildSuggestionsSection(),
            const SizedBox(height: AppDesignSystem.space6),
          ],
          // 慢查询摘要
          if (_slowQueries.isNotEmpty) ...[
            _buildSlowQueriesSection(),
            const SizedBox(height: AppDesignSystem.space6),
          ],
          // 表统计摘要
          _buildTableStatsSection(),
        ],
      ),
    );
  }

  Widget _buildReportHeader() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space4),
            decoration: BoxDecoration(
              color: context.themeColors.accentBlue.withAlpha(25),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            ),
            child: Icon(
              LucideIcons.chartColumn,
              size: 32,
              color: context.themeColors.accentBlue,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.databasePerformanceReport,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: AppDesignSystem.fontSize3xl,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Text(
                  '${l10n.performanceAnalyzerDatabase}: ${_report!.databaseName}',
                  style: TextStyle(color: context.themeColors.textSecondary),
                ),
                Text(
                  '${l10n.performanceAnalyzerGeneratedAt} ${_report!.generatedAt.toString()}',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildReportBadge(
                l10n.tableCountLabel,
                '${_report!.tableStats.length}',
                context.themeColors.accentBlue,
              ),
              const SizedBox(height: AppDesignSystem.space2),
              _buildReportBadge(
                l10n.slowQueryCountLabel,
                '${_report!.slowQueries.length}',
                context.themeColors.warning,
              ),
              const SizedBox(height: AppDesignSystem.space2),
              _buildReportBadge(
                l10n.suggestionCountLabel,
                '${_report!.suggestions.length}',
                context.themeColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReportBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionsSection() {
    final l10n = AppLocalizations.of(context)!;
    return _buildDetailCard(
      '${l10n.performanceAnalyzerOptimizationSuggestions} (${_suggestions.length})',
      _suggestions.map((s) => _buildSuggestionCard(s)).toList(),
    );
  }

  Widget _buildSuggestionCard(PerformanceSuggestion suggestion) {
    final l10n = AppLocalizations.of(context)!;
    Color impactColor;
    String impactText;

    switch (suggestion.impact) {
      case 'high':
        impactColor = context.themeColors.error;
        impactText = l10n.impactHigh;
        break;
      case 'medium':
        impactColor = context.themeColors.warning;
        impactText = l10n.impactMedium;
        break;
      default:
        impactColor = context.themeColors.success;
        impactText = l10n.impactLow;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                suggestion.typeIcon,
                color: context.themeColors.accentBlue,
                size: 20,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  suggestion.title,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                  vertical: AppDesignSystem.space0_5,
                ),
                decoration: BoxDecoration(
                  color: impactColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  '${l10n.performanceAnalyzerImpact} $impactText',
                  style: TextStyle(color: impactColor, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            suggestion.description,
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: 13,
            ),
          ),
          if (suggestion.recommendation != null) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.bgPrimary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.recommendedAction,
                    style: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: AppDesignSystem.space1),
                  SelectableText(
                    suggestion.recommendation!,
                    style: TextStyle(
                      color: context.themeColors.textPrimary,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (suggestion.affectedTables.isNotEmpty) ...[
            const SizedBox(height: AppDesignSystem.space2),
            Wrap(
              spacing: 8,
              children: suggestion.affectedTables
                  .map(
                    (table) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space2,
                        vertical: AppDesignSystem.space0_5,
                      ),
                      decoration: BoxDecoration(
                        color: context.themeColors.bgTertiary,
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                      child: Text(
                        table,
                        style: TextStyle(
                          color: context.themeColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlowQueriesSection() {
    final l10n = AppLocalizations.of(context)!;
    return _buildDetailCard(
      '${l10n.performanceAnalyzerSlowQueriesTop} ${_slowQueries.take(5).length}',
      _slowQueries
          .take(5)
          .map(
            (q) => Container(
              margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.bgPrimary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDesignSystem.space1_5,
                          vertical: AppDesignSystem.space0_5,
                        ),
                        decoration: BoxDecoration(
                          color: _getTimeColor(q.executionTime),
                          borderRadius: BorderRadius.circular(
                            AppDesignSystem.radiusSm,
                          ),
                        ),
                        child: Text(
                          q.executionTimeFormatted,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppDesignSystem.space2),
                      Text(
                        q.database,
                        style: TextStyle(
                          color: context.themeColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppDesignSystem.space2),
                  Text(
                    q.query.length > 100
                        ? '${q.query.substring(0, 100)}...'
                        : q.query,
                    style: TextStyle(
                      color: context.themeColors.textPrimary,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildTableStatsSection() {
    final l10n = AppLocalizations.of(context)!;
    return _buildDetailCard(l10n.largeTableStats, [
      DataTable(
        headingRowColor: WidgetStateProperty.all(
          context.themeColors.bgTertiary,
        ),
        dataRowColor: WidgetStateProperty.all(context.themeColors.bgPrimary),
        border: TableBorder.all(
          color: context.themeColors.borderColor.withOpacity(0.5),
        ),
        columns: [
          DataColumn(
            label: Text(
              l10n.tableNameLabel,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              l10n.tableRowCountLabel,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              l10n.tableTotalSizeLabel,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              l10n.tableRatioLabel,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        rows: _report!.tableStats.take(10).map((table) {
          final percentage = _summary.totalSize > 0
              ? (table.totalSize / _summary.totalSize * 100).toStringAsFixed(1)
              : '0';
          return DataRow(
            cells: [
              DataCell(
                Text(
                  table.tableName,
                  style: TextStyle(color: context.themeColors.textPrimary),
                ),
              ),
              DataCell(
                Text(
                  _formatNumber(table.rowCount),
                  style: TextStyle(color: context.themeColors.textSecondary),
                ),
              ),
              DataCell(
                Text(
                  table.totalSizeFormatted,
                  style: TextStyle(color: context.themeColors.textSecondary),
                ),
              ),
              DataCell(
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: LinearProgressIndicator(
                        value: double.parse(percentage) / 100,
                        backgroundColor: context.themeColors.bgTertiary,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          double.parse(percentage) > 50
                              ? context.themeColors.error
                              : context.themeColors.accentBlue,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      '$percentage%',
                      style: TextStyle(
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
      // T053 — ConversionGuideRow: slow query panel guide.
      // Wire onAction (was null → dead link) and add lite variant for unconnected
      // repeat users per telemetry-funnel-plan §1.B / FR-039a.
      _buildSlowQueryGuide(context, l10n),
    ]);
  }

  Widget _buildSlowQueryGuide(BuildContext context, AppLocalizations l10n) {
    final isConnected = context.watch<ServerConnectionProvider>().isConnected;
    if (isConnected) {
      return ConversionGuideRow(
        icon: LucideIcons.clock,
        title: l10n.performanceAnalyzerWeeklyReportTitle,
        description: l10n.performanceAnalyzerWeeklyReportDesc,
        actionLabel: l10n.performanceAnalyzerLearnMore,
        guideId: 'slow-query-panel',
        serverConnected: true,
        variant: ConversionGuideVariant.full,
        onAction: _launchLearnMoreUrl,
        actionUrl: _kServerLearnMoreUrl,
      );
    }
    // Lite variant — gated by ≥3 prior opens + remote kill switch + per-guide
    // lifetime exposure cap.
    return FutureBuilder<bool>(
      future: _slowQueryLiteGateFuture,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        // TODO(marketing): lite copy is an EN placeholder pending replacement.
        return ConversionGuideRow(
          icon: LucideIcons.clock,
          title: l10n.touchpointLiteSlowQueryTitle,
          description: l10n.touchpointLiteSlowQueryDesc,
          actionLabel: l10n.touchpointLiteLearnMore,
          guideId: 'slow-query-panel',
          serverConnected: false,
          variant: ConversionGuideVariant.lite,
          onAction: _launchLearnMoreUrl,
          actionUrl: _kServerLearnMoreUrl,
        );
      },
    );
  }

  // ========== 通用组件 ==========
  Widget _buildDetailCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: context.themeColors.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
