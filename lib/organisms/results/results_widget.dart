import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../atoms/app_widgets.dart';
import '../../molecules/actionable_error.dart';
import '../../providers/app_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/tab_provider.dart' show ResultSubTab, QueryTab;
import '../../services/export_service.dart';
import '../../models/result_filter.dart';
import '../../models/execution_result.dart';
import '../../models/database_models.dart' hide QueryTab;
import '../../plugins/bootstrap.dart' show defaultPluginRegistry;
import '../../plugins/result_renderer_plugin.dart';
import '../connection/column_filter_widget.dart' show SortState;
import '../connection/error_boundary.dart';
import 'virtualized_data_table.dart';
import 'json_cell_viewer.dart';
import 'cell_value_viewer.dart';
import 'json_field_picker.dart';
import 'pii_export_dialog.dart';
import 'result_subtab_bar.dart';
import 'statistics_panel.dart';
import '../../services/result_statistics_service.dart';
import '../../services/ai_summary_service.dart';
import '../../services/ai_service.dart';
import 'query_history/result_history_view.dart';
import '../../models/query_history.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../theme/app_colors.dart';

/// ResultsWidget - 查询结果展示
///
/// 结构（自顶向下）：
/// - [ResultSubTabBar] — 结果子标签栏（History + Result 1, Result 2…）。
///   C22 M2 走查反馈二轮：语句层并入本层——一次执行 N 条语句扇出
///   N 个 Result 子标签，每标签恰一条结果；语句内层 tab 已移除。
/// - 工具栏行 — AI 分析、导出、搜索按钮
/// - 内容区 — 活跃子标签的单条结果（或 Error/空态视图）
///
/// 数据源从 [TabProvider.activeResults] + [TabProvider.activeResultIndex] 获取，
/// 不再直接读取 `QueryTab.executionResults`。
class ResultsWidget extends StatefulWidget {
  final ValueChanged<QueryHistory>? onHistoryDoubleTapped;
  final ValueChanged<QueryHistory>? onHistoryTapped;

  /// 是否显示 Result/History 子标签栏。spec 041 data 模式传 false → 只显数据网格。
  final bool showSubTabs;

  const ResultsWidget({
    super.key,
    this.onHistoryDoubleTapped,
    this.onHistoryTapped,
    this.showSubTabs = true,
  });

  @override
  ResultsWidgetState createState() => ResultsWidgetState();
}

class ResultsWidgetState extends State<ResultsWidget> {
  final Map<int, ResultTabState> _tabStates = {};

  /// 行级搜索框（外层单例，跨 tab 共享）。
  /// 搜索词直接从 controller.text 读（单一数据源），下行给 ResultTabContent.searchQuery。
  /// 见 spec 051-results-row-search。
  final TextEditingController _searchController = TextEditingController();
  bool _searchVisible = false;

  @override
  void dispose() {
    _searchController.dispose();
    for (var state in _tabStates.values) {
      state.dispose();
    }
    super.dispose();
  }

  /// 当前活跃的 ResultSubTab（非 null 时包含 executionResults）
  ResultSubTab? _activeResultSubTab(AppProvider provider) {
    final results = provider.tab.activeResults;
    final idx = provider.tab.activeResultIndex;
    if (idx < 0 || idx >= results.length) return null;
    return results[idx];
  }

  /// 上一次活跃的 Tab ID —— 用于检测 Tab 切换，清空搜索/过滤缓存
  String? _lastTabId;

  @override
  Widget build(BuildContext context) {
    // 精确选择：仅在 Tab ID / 活跃子标签索引 / 子标签数量变化时重建
    // 避免了 sidebar / connection / aiPanel 等无关 Provider 变更导致的浪费
    // （C22 M2 走查反馈二轮：语句层并入子标签层，内层结果索引已移除）
    final resultKey = context.select<AppProvider, (String?, int, int)>(
      (p) => (
        p.tab.activeTab?.id,
        p.tab.activeResultIndex,
        p.tab.activeResults.length,
      ),
    );
    final currentTabId = resultKey.$1;

    // 非重建读取（已由 resultKey 变化保证数据新鲜）
    final provider = context.read<AppProvider>();
    final activeSub = _activeResultSubTab(provider);
    final isHistoryActive = activeSub?.isHistory ?? false;
    // 扇出后每个子标签恰一条结果；防御性取 first（旧会话数据不持久化，
    // 不存在多语句子标签的存量）。
    final executionResults = activeSub?.executionResults ?? [];
    final hasError = activeSub?.hasError ?? false;

    // 当切换到不同 Query Tab 时，清空搜索/过滤缓存
    if (currentTabId != _lastTabId) {
      _lastTabId = currentTabId;
      for (var state in _tabStates.values) {
        state.dispose();
      }
      _tabStates.clear();
    }

    return Container(
      color: context.themeColors.bgSecondary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 批次级子标签栏 —— data 模式（showSubTabs=false）隐藏，只显数据网格
          if (widget.showSubTabs) const ResultSubTabBar(),
          // History 标签内容
          // data 模式（showSubTabs=false）下 History 子标签仅在新 tab 首执
          // 返回前处于激活态——此时显示全屏历史页会造成明显跳变
          // （先闪 history 再跳结果），改显示执行中 loading。
          if (isHistoryActive)
            Expanded(
              child: widget.showSubTabs
                  ? ResultHistoryView(
                      tabId: currentTabId ?? '',
                      connectionId: provider.tab.activeTab?.connectionId,
                      onHistoryDoubleTapped:
                          widget.onHistoryDoubleTapped ?? (_) {},
                      onHistoryTapped: widget.onHistoryTapped ?? (_) {},
                    )
                  : Center(
                      child: CircularProgressIndicator(
                        color: context.themeColors.accentBlue,
                        strokeWidth: 3,
                      ),
                    ),
            )
          else ...[
            // 工具栏行
            _buildHeader(executionResults),
            // 行级搜索框（点击搜索按钮展开，spec 051 R1）
            if (_searchVisible) _buildSearchField(),
            // 内容区
            Expanded(
              child: _buildContent(
                executionResults,
                tabId: currentTabId,
                hasError: hasError,
                errorMessage: activeSub?.errorMessage,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 内容区：活跃子标签的单条结果直接渲染。
  ///
  /// C22 M2 走查反馈二轮：语句层并入子标签层（一次执行 N 条语句扇出
  /// N 个 Result 子标签），语句内层 TabBar/TabBarView 整体移除。
  ///
  /// [tabId] 用于生成跨 Tab 隔离的 widget key
  Widget _buildContent(
    List<ExecutionResult> results, {
    required String? tabId,
    required bool hasError,
    required String? errorMessage,
  }) {
    if (hasError) {
      return _buildErrorDisplay(errorMessage ?? 'Unknown error');
    }
    if (results.isEmpty) {
      return _buildEmptyState();
    }
    return _buildResultTab(results.first, 0, tabId: tabId);
  }

  Widget _buildErrorDisplay(String message) {
    final provider = context.read<AppProvider>();
    final activeSub = _activeResultSubTab(provider);
    final sql = activeSub?.executedSql;
    final connectionId = provider.tab.activeTab?.connectionId;
    final databaseName = provider.tab.activeTab?.databaseName;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space4),
          child: ActionableError(
            message: message,
            sql: sql,
            connectionId: connectionId,
            databaseName: databaseName,
            onAnalyze: () {
              unawaited(
                provider.analyzeErrorWithAi(
                  errorText: message,
                  sql: sql,
                  connectionId: connectionId,
                  databaseName: databaseName,
                  locale: LocaleProvider.codeOf(
                    Localizations.localeOf(context),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 为结果标签生成跨 Tab 隔离的 key
  Key _resultKey(int index, String? tabId) =>
      ValueKey('result_${tabId ?? 'unknown'}_$index');

  Widget _buildHeader(List<ExecutionResult> results) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          // C22 M2 走查反馈二轮：语句 tab 层移除（并入 ResultSubTabBar 扇出），
          // 工具栏只留动作按钮。
          const Expanded(child: SizedBox.shrink()),
          _buildAiAnalyzeButton(results),
          _buildExportButton(results),
          _buildSearchButton(),
        ],
      ),
    );
  }

  Widget _buildExportButton(List<ExecutionResult> results) {
    final l10n = AppLocalizations.of(context)!;
    final hasData = results.any((r) => r.hasData);
    if (!hasData) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: () => _showExportDialog(results),
      icon: const Icon(LucideIcons.download, size: 16),
      label: Text(l10n.resultsExport),
      style: TextButton.styleFrom(
        foregroundColor: context.themeColors.textSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space1,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildSearchButton() {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      icon: Icon(
        LucideIcons.search,
        size: 18,
        color: _searchVisible
            ? context.themeColors.accentBlue
            : context.themeColors.textSecondary,
      ),
      tooltip: l10n?.resultsSearchBtn,
      onPressed: () {
        setState(() {
          _searchVisible = !_searchVisible;
          if (!_searchVisible && _searchController.text.isNotEmpty) {
            _searchController.clear();
          }
        });
      },
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  /// 行级搜索输入框（点击搜索按钮展开时显示）。
  /// query 直接来自 [_searchController]（单一数据源），onChanged 仅触发 rebuild
  /// 把 [TextEditingController].text 下行给 ResultTabContent。见 spec 051 R1/R2。
  /// UI 模式参考 code_snippets_panel._buildSearchBar。
  Widget _buildSearchField() {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        border: Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: l10n.resultsSearchHint,
          prefixIcon: const Icon(LucideIcons.search, size: 18),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(LucideIcons.x, size: 18),
                  tooltip: l10n.resultsClear,
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
          hintStyle: TextStyle(color: colors.textMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: colors.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: colors.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            borderSide: BorderSide(color: colors.accentPurple),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space2,
          ),
        ),
        style: TextStyle(color: colors.textPrimary, fontSize: 13),
      ),
    );
  }

  Widget _buildAiAnalyzeButton(List<ExecutionResult> results) {
    final l10n = AppLocalizations.of(context)!;
    if (results.isEmpty) {
      return const SizedBox.shrink();
    }
    // 扇出后子标签恰一条结果——分析「当前查看的」= 活跃子标签的结果。
    final result = results.first;
    // AI 分析支持：成功有数据、成功无数据、执行失败
    if (result.statement.sql.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final label = !result.success ? l10n.aiAnalyzeErrorResult : l10n.aiAnalyze;

    return TextButton.icon(
      onPressed: () => _analyzeWithAi(result),
      icon: Icon(
        LucideIcons.wandSparkles,
        size: 16,
        color: context.themeColors.textSecondary,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.themeColors.textSecondary,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: context.themeColors.textSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space1,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  void _analyzeWithAi(ExecutionResult result) {
    final provider = Provider.of<AppProvider>(context, listen: false);
    provider.analyzeExecutionResultWithAi(
      result,
      locale: LocaleProvider.codeOf(Localizations.localeOf(context)),
    );
  }

  Widget _buildResultTab(ExecutionResult result, int index, {String? tabId}) {
    if (!result.success) {
      return _buildErrorView(result);
    }

    if (!result.hasData && result.affectedRows != null) {
      return _buildAffectedRowsView(result);
    }

    if (!result.hasData) {
      return _buildEmptyResultView();
    }

    return ResultTabContent(
      result: result,
      searchQuery: _searchController.text,
      searchActive: _searchVisible,
      key: _resultKey(index, tabId),
    );
  }

  Widget _buildErrorView(ExecutionResult result) {
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.circleAlert,
                color: context.themeColors.accentRed,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.executeFailedError,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.accentRed,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.themeColors.accentRed.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
              border: Border.all(
                color: context.themeColors.accentRed.withValues(alpha: 0.2),
              ),
            ),
            child: SelectableText(
              result.errorMessage ?? l10n.resultsUnknownError,
              style: TextStyle(
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: 12,
                color: context.themeColors.accentRed,
              ),
            ),
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.resultsSqlStatementLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.themeColors.bgPrimary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
              border: Border.all(color: context.themeColors.borderLight),
            ),
            child: SelectableText(
              result.statement.sql,
              style: TextStyle(
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: 12,
                color: context.themeColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAffectedRowsView(ExecutionResult result) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.circleCheckBig,
            size: 48,
            color: context.themeColors.accentGreen,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.resultsExecutionSuccess,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.resultsAffectedRows(result.affectedRows ?? 0),
            style: TextStyle(
              fontSize: 14,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.resultsElapsedMs(result.executionTime.inMilliseconds),
            style: TextStyle(
              fontSize: 12,
              color: context.themeColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResultView() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.circleCheckBig,
            size: 48,
            color: context.themeColors.accentGreen,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.resultsExecutionSuccess,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    return AppEmptyState(
      icon: LucideIcons.table2,
      title: l10n.resultsNoDataTitle,
      description:
          '${l10n.resultsNoDataMessage}\n${l10n.resultsNoDataGuidance}',
      iconSize: 48,
    );
  }

  Future<void> _showExportDialog(List<ExecutionResult> results) async {
    final l10n = AppLocalizations.of(context)!;

    // 只导出当前选中的 tab 的数据（扇出后 = 活跃子标签的单条结果）
    if (results.isEmpty) return;

    final currentResult = results.first;
    if (!currentResult.hasData) {
      AppErrorHandler.showErrorSnackBar(context, l10n.resultsNoDataToExport);
      return;
    }

    final data = currentResult.data!;

    // R4: 走 PII 智能导出对话框（格式 → PII 检测 → 确认，含脱敏 + 审计）。
    // 对话框只收集选择；导出在本 widget（持有活 context）执行——2026-08-17
    // 灰屏事故根因：此前由已 pop 的 dialog context 执行，success/error 反馈
    // 落在失效 context 上抛错，触发 ErrorReporter 级联。
    final selection = await PiiExportDialog.show(
      context,
      data: data,
      sourceSql: currentResult.statement.sql,
    );
    if (selection == null || !mounted) return;
    await ExportService.exportWithMasking(
      data: data,
      context: context,
      format: selection.format,
      columnActions: selection.columnActions,
      sourceSql: currentResult.statement.sql,
    );
  }
}

/// ResultTabContent - 单个结果 Tab 的内容
class ResultTabContent extends StatefulWidget {
  final ExecutionResult result;

  /// 行级搜索关键词（来自外层 ResultsWidgetState 的搜索框，跨 tab 共享）。
  /// 空串表示不过滤。见 spec 051-results-row-search。
  final String searchQuery;

  /// 行级搜索框是否展开（仅用于决定是否显示「无匹配行」提示，不影响过滤逻辑）。
  final bool searchActive;

  const ResultTabContent({
    super.key,
    required this.result,
    this.searchQuery = '',
    this.searchActive = false,
  });

  @override
  State<ResultTabContent> createState() => _ResultTabContentState();
}

class _ResultTabContentState extends State<ResultTabContent> {
  late List<String> _columns;
  late List<Map<String, dynamic>> _data;
  late List<Map<String, dynamic>> _filteredData;

  final ResultFilterService _filterService = ResultFilterService();
  SortState? _sortState;

  /// 行级搜索镜像（来自 widget.searchQuery）。放 state 里让 _applyFiltersAndSort
  /// 不依赖 widget 字段，且 _initData 时能初始化。见 spec 051 R2/R4。
  String _rowSearchQuery = '';

  // R1: 视图模式 id（per-tab 持久化）。C11 起为注册渲染器的 viewModeId
  // 字符串（默认注册 table/chart/card）。null = 未选择，取注册序首个。
  // ResultTabContent 以稳定 key 构建，Flutter element 复用保留各 tab 的
  // State，故切走再切回仍在。
  String? _viewModeId;

  // R3: 统计摘要栏折叠状态（默认折叠）。
  bool _showStats = false;

  // Cell editing state
  CellEdit? _activeEdit;
  TextEditingController? _activeController;
  FocusNode? _activeFocusNode;
  final Map<String, CellEdit> _cellEdits = {};

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didUpdateWidget(ResultTabContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当查询结果变化时重新初始化数据
    if (oldWidget.result.data != widget.result.data) {
      _initData();
    }
    // 行级搜索词变化（外层搜索框输入/清空）→ 重跑过滤管线
    if (oldWidget.searchQuery != widget.searchQuery) {
      _rowSearchQuery = widget.searchQuery;
      _applyFiltersAndSort();
    }
  }

  @override
  void dispose() {
    _activeController?.dispose();
    _activeFocusNode?.dispose();
    for (var edit in _cellEdits.values) {
      edit.controller.dispose();
      edit.focusNode.dispose();
    }
    super.dispose();
  }

  void _initData() {
    _data = widget.result.data ?? [];
    _rowSearchQuery = widget.searchQuery;
    _columns = _data.isNotEmpty ? _data.first.keys.toList() : [];
    _filteredData = List.from(_data);

    if (_columns.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _detectColumnTypes();
      });
    }
    // 若初始就有行级搜索词（切 tab / 首次渲染时外层已输入），立刻过滤。
    if (_rowSearchQuery.isNotEmpty) {
      _filteredData = applyRowSearch(_filteredData, _rowSearchQuery);
    }
  }

  void _detectColumnTypes() {
    for (var col in _columns) {
      // Phase A — pass adapter columnTypes metadata so JSON columns are detected
      final type = ResultFilterService.detectColumnType(
        _data,
        col,
        columnTypes: widget.result.columnTypes,
      );
      _filterService.setColumnType(col, type);
    }
  }

  void _applyFiltersAndSort() {
    var data = _filterService.applyFilters(_data);
    if (_sortState != null) {
      data = _filterService.applySorting(
        data,
        _sortState!.columnName,
        _sortState!.ascending,
      );
    }
    // 行级 post-filter：与列级过滤取交集（spec 051 R3）。
    // 放在排序之后——applySorting 是稳定排序，先后顺序不影响最终结果，
    // 放后面语义更直观（先筛行，再让筛出来的行有序）。
    if (_rowSearchQuery.isNotEmpty) {
      data = applyRowSearch(data, _rowSearchQuery);
    }
    setState(() {
      _filteredData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_data.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context)?.commonNoData ?? 'No data'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_filterService.activeFilterCount > 0) _buildFilterStatusBar(),
        _buildViewModeBar(),
        Expanded(child: _buildActiveView()),
        _buildStatsBar(),
      ],
    );
  }

  /// R3: 底部可折叠统计摘要栏。点击展开/收起 StatisticsPanel。
  Widget _buildStatsBar() {
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 折叠条头部（点击切换）
        InkWell(
          onTap: () => setState(() => _showStats = !_showStats),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.bgTertiary,
              border: Border(top: BorderSide(color: colors.borderLight)),
            ),
            child: Row(
              children: [
                Icon(
                  _showStats
                      ? LucideIcons.chevronDown
                      : LucideIcons.chevronRight,
                  size: 16,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Icon(
                  LucideIcons.chartColumn,
                  size: 14,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n?.statisticsPanelTitle ?? 'Statistics',
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        // 展开内容
        if (_showStats)
          SizedBox(
            height: 240,
            child: StatisticsPanel(
              data: _filteredData,
              columnTypes: _filterService.columnTypes,
              onStatsValueTap: _onStatsValueTap,
              onCategoryColumnTap: _onCategoryColumnTap,
            ),
          ),
      ],
    );
  }

  /// R3: 点击数值统计值 → 生成聚合 SQL 到新 Tab（不自动执行）。
  void _onStatsValueTap(String column, String agg) {
    final sql = ResultStatisticsService.generateStatsSql(
      column: column,
      agg: agg,
      table: _currentTableName(),
    );
    _openSqlInNewTab(sql);
  }

  /// R3: 点击分类列名 → 生成 GROUP BY SQL 到新 Tab。
  void _onCategoryColumnTap(String column) {
    final sql = ResultStatisticsService.generateGroupBySql(
      column: column,
      table: _currentTableName(),
    );
    _openSqlInNewTab(sql);
  }

  /// 尝试从结果 SQL 推断表名（用于生成的 SQL 占位）。
  /// 推断失败返回 null，生成的 SQL 用占位符 `<target_table>`。
  String? _currentTableName() {
    final sql = widget.result.statement.sql;
    // 简单从 FROM/UPDATE/INTO 后提取表名
    final match = RegExp(
      r'\b(?:FROM|UPDATE|INTO)\s+(\w+)',
      caseSensitive: false,
    ).firstMatch(sql);
    return match?.group(1);
  }

  /// 打开新 Tab 填入 SQL（不自动执行，R3 O5 确认）。
  void _openSqlInNewTab(String sql) {
    final provider = context.read<AppProvider>();
    provider.tab.addTab(
      QueryTab(
        id: 'tab-stats-${DateTime.now().millisecondsSinceEpoch}',
        title: 'Statistics Query',
        sql: sql,
      ),
    );
  }

  /// R5: AI 趋势分析回调（注入 ChartView）。
  /// 门控预留：canUseAi 检查（当前整体禁用返回 true，未来恢复门控时生效）。
  /// 取 provider AI 配置调 AiSummaryService.analyzeResultTrend；配置不全降级提示。
  Future<String> _runAiTrend() async {
    final provider = context.read<AppProvider>();
    // 门控预留点（O2：AI 趋势划 Pro，当前不触发）
    final canUseAi = await provider.canUseAi();
    if (!canUseAi) {
      return 'AI 功能不可用（需开通 Pro）';
    }

    final aiProvider = provider.selectedAiProvider;
    final aiModel = provider.selectedAiModel;
    final configs = provider.aiApiConfigs;
    final providerConfig = configs[aiProvider];
    final apiKey = providerConfig?['apiKey'];
    if (apiKey == null || apiKey.isEmpty) {
      return '未配置 AI 服务 API Key，请在设置中配置后使用';
    }

    try {
      final service = AiSummaryService(AiService());
      return await service.analyzeResultTrend(
        data: _filteredData,
        columnTypes: _filterService.columnTypes,
        apiKey: apiKey,
        provider: aiProvider,
        model: aiModel,
        baseUrl: providerConfig?['baseUrl'],
        locale: Localizations.localeOf(context).languageCode,
      );
    } catch (e) {
      return 'AI 分析失败：$e';
    }
  }

  /// C11: 当前结果适用的渲染器（按注册表 + 形态过滤）。C12 起形态来自
  /// 结果元数据（ExecutionResult.dataShape，按连接类型判定）——Mongo 结果
  /// 走文档渲染器、Redis 走键值渲染器、SQL 家族恒行集；null = 历史结果 /
  /// 未标记路径，回退 sqlRows。类型维度过滤（per-type 渲染器）有需求再接线。
  List<ResultRendererPlugin> _availableRenderers() =>
      defaultPluginRegistry.resultRenderersFor(
        shape: widget.result.dataShape ?? ResultDataShape.sqlRows,
      );

  /// 生效的 viewModeId：已选 id 仍在适用列表内用之，否则回退注册序首个
  /// （形态变化 / 注册表变更后的自愈，不抛错）。
  String _effectiveViewModeId(List<ResultRendererPlugin> renderers) {
    final selected = _viewModeId;
    if (selected != null && renderers.any((r) => r.viewModeId == selected)) {
      return selected;
    }
    return renderers.first.viewModeId;
  }

  /// R1: 视图模式切换条（per-result，紧贴数据上方）。
  /// 导出/搜索等批次级操作在外层 _buildHeader；视图切换是单结果级操作，
  /// 放这里避免跨类访问 viewMode 状态。
  /// C11: 模式集合按注册表生成（table/chart/card 为默认注册件），
  /// 图标/文案来自渲染器 descriptor。
  Widget _buildViewModeBar() {
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;
    final renderers = _availableRenderers();
    if (renderers.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SegmentedButton<String>(
            segments: [
              for (final renderer in renderers)
                ButtonSegment(
                  value: renderer.viewModeId,
                  icon: Icon(renderer.descriptor.icon, size: 16),
                  label: Text(
                    l10n != null && renderer.descriptor.displayName != null
                        ? renderer.descriptor.displayName!(l10n)
                        : renderer.viewModeId,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
            selected: {_effectiveViewModeId(renderers)},
            onSelectionChanged: (selection) {
              setState(() => _viewModeId = selection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// R1: 按注册渲染器渲染当前视图。所有视图消费同一份 _filteredData，
  /// 保证过滤/排序在切换视图后仍生效。表格视图独占的编辑/右键/JSON 双击
  /// 交互经 TableViewInteraction 桥下发（切走再切回恢复）。
  Widget _buildActiveView() {
    // R5：行级搜索启用且无匹配行 → 显示明确提示，避免空白困惑。
    if (_rowSearchQuery.isNotEmpty && _filteredData.isEmpty) {
      final l10n = AppLocalizations.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space4),
          child: Text(
            l10n?.resultsSearchNoMatch(_rowSearchQuery) ??
                'No rows match "$_rowSearchQuery"',
            style: TextStyle(
              color: context.themeColors.textSecondary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final renderers = _availableRenderers();
    if (renderers.isEmpty) {
      // 默认注册下不可达（bootstrap 创建即注册三渲染器），防御式兜底。
      return Center(
        child: Text(AppLocalizations.of(context)?.commonNoData ?? 'No data'),
      );
    }
    final modeId = _effectiveViewModeId(renderers);
    final renderer = renderers.firstWhere((r) => r.viewModeId == modeId);
    return renderer.build(context, _buildRenderContext());
  }

  /// C11: 组装渲染上下文——管线产物（过滤/排序/行搜索后）+ 两个交互面
  /// （AI 趋势回调、表格桥）。表格桥字段与迁移前 _buildTableView 的
  /// VirtualizedDataTable 参数逐项对齐。
  ResultRenderContext _buildRenderContext() {
    return ResultRenderContext(
      result: widget.result,
      rows: _filteredData,
      columns: _columns,
      columnTypes: _filterService.columnTypes,
      // M5: AI 趋势分析回调（门控预留 + 配置获取），chart 渲染器消费。
      onAiTrendRequest: _runAiTrend,
      tableView: TableViewInteraction(
        filterService: _filterService,
        sortState: _sortState,
        onFilterChanged: (filter) {
          setState(() {
            _filterService.setFilter(filter);
            _applyFiltersAndSort();
          });
        },
        onFilterCleared: (columnName) {
          setState(() {
            _filterService.removeFilter(columnName);
            _applyFiltersAndSort();
          });
        },
        onSortToggle: (columnName) {
          setState(() {
            if (_sortState?.columnName == columnName) {
              _sortState = SortState(
                columnName: columnName,
                ascending: !_sortState!.ascending,
              );
            } else {
              _sortState = SortState(columnName: columnName, ascending: true);
            }
            _applyFiltersAndSort();
          });
        },
        onCellEdit: _handleCellEdit,
        activeCellEdit: _activeEdit != null
            ? CellEditState(
                cellKey: _activeEdit!.cellKey,
                rowIndex: _activeEdit!.rowIndex,
                colName: _activeEdit!.colName,
                originalValue: _activeEdit!.originalValue,
                newValue: _activeEdit!.newValue,
                controller: _activeEdit!.controller,
                focusNode: _activeEdit!.focusNode,
              )
            : null,
        onEditConfirm: (cellKey, newValue) => _confirmEdit(),
        onEditCancel: (cellKey) => _cancelEdit(),
        pendingEdits: _cellEdits.isNotEmpty
            ? Map.fromEntries(
                _cellEdits.entries.map(
                  (e) => MapEntry(e.key, e.value.newValue),
                ),
              )
            : null,
        onCellContextMenu: _handleCellContextMenu,
        onHeaderContextMenu: _handleHeaderContextMenu,
        // Phase B — double-click JSON cell opens tree viewer
        // HOTFIX: PG driver auto-parses jsonb into Map/List;
        // use jsonEncode to get valid JSON; fall back to toString for raw strings.
        onJsonCellDoubleTap: (rowIndex, columnName, value) {
          final jsonStr = (value is Map || value is List)
              ? jsonEncode(value)
              : value?.toString();
          if (jsonStr != null && jsonStr.isNotEmpty) {
            try {
              showJsonCellViewer(
                context,
                jsonString: jsonStr,
                columnName: columnName,
              );
            } catch (_) {
              // Safety net for unexpected errors.
            }
          }
        },
      ),
    );
  }

  void _handleCellEdit(int rowIndex, String columnName, dynamic value) {
    // U07/D1-A + 2026-08-24 用户拍板：网格写回下线（永不进编辑态，无假保存
    // 风险）。双击改为打开只读单元格查看器——长文本查看/复制的正式入口
    // （原「暂不支持编辑」snackbar 退役，它对只想看内容的用户是噪音）。
    showCellValueViewer(context, columnName: columnName, value: value);
  }

  void _confirmEdit() {
    if (_activeEdit == null) return;

    final newValue = _activeController?.text ?? '';
    _activeEdit!.newValue = newValue;

    if (newValue != _activeEdit!.originalValue?.toString()) {
      _cellEdits[_activeEdit!.cellKey] = _activeEdit!;
    } else {
      _cellEdits.remove(_activeEdit!.cellKey);
    }

    setState(() => _activeEdit = null);
  }

  void _cancelEdit() {
    if (_activeEdit == null) return;

    _activeController?.dispose();
    _activeFocusNode?.dispose();
    _activeController = null;
    _activeFocusNode = null;

    setState(() => _activeEdit = null);
  }

  bool _supportsSqlExport() {
    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final server = provider.connection.currentServer;
      if (server == null) return false;
      switch (server.type) {
        case DatabaseType.mysql:
        case DatabaseType.clickhouse:
        case DatabaseType.postgresql:
        case DatabaseType.sqlite:
        case DatabaseType.doris:
        case DatabaseType.tdengine:
        case DatabaseType.sqlserver:
        case DatabaseType.oceanbase:
        case DatabaseType.tidb:
        case DatabaseType.starrocks:
        case DatabaseType.mariadb:
          return true;
        case DatabaseType.mongodb:
        case DatabaseType.redis:
          return false;
      }
    } catch (e) {
      return false;
    }
  }

  // 右键菜单统一走 CompactPopupMenuItem（行高/内边距取设计 token 默认值）。
  static const double _kCompactMenuDividerHeight = 6;

  CompactPopupMenuItem<T> _compactMenuItem<T>({
    required Widget child,
    required VoidCallback? onTap,
  }) => CompactPopupMenuItem<T>(onTap: onTap, child: child);

  /// US4 T052/T056: 列头右键 → JSON 列弹「Extract field as column」菜单。
  /// 非 JSON 列无菜单（FR-015: 仅 JSONB/JSON 列提供此选项）。
  void _handleHeaderContextMenu(String columnName, Offset position) async {
    // 仅 JSON 列提供提取选项
    final colType = _filterService.getColumnType(columnName);
    if (colType != ColumnDataType.json) return;

    final l10n = AppLocalizations.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'extract',
          child: Row(
            children: [
              Icon(
                LucideIcons.network,
                size: 16,
                color: context.themeColors.accentBlue,
              ),
              const SizedBox(width: 8),
              Text(l10n?.extractFieldAsColumn ?? 'Extract field as column'),
            ],
          ),
        ),
      ],
    );

    if (selected != 'extract') return;
    if (!mounted) return;

    // 采样该列的值（前 50 个非空）
    final samples = _data
        .map((row) => row[columnName])
        .where((v) => v != null)
        .take(50)
        .toList();

    final dbType = _getDatabaseType();
    final sql = await JsonFieldPicker.show(
      context,
      sampleValues: samples,
      columnName: columnName,
      databaseType: dbType,
      sourceTable: _currentTableName(),
      originalColumns: _columns,
    );

    if (sql != null && sql.isNotEmpty) {
      _openSqlInNewTab(sql);
    }
  }

  /// 获取当前连接的数据库类型（US4 SQL 生成需要）。
  DatabaseType _getDatabaseType() {
    try {
      final provider = context.read<AppProvider>();
      return provider.connection.currentServer?.type ?? DatabaseType.mysql;
    } catch (_) {
      return DatabaseType.mysql;
    }
  }

  void _handleCellContextMenu(
    int rowIndex,
    String columnName,
    dynamic value,
    Offset position,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final supportsSqlExport = _supportsSqlExport();
    // Phase C — JSON column detection for context menu
    final isJsonCol =
        _filterService.columnTypes[columnName] == ColumnDataType.json;
    final isJsonValue =
        value != null &&
        (value is Map ||
            (value is String &&
                ((value.trim().startsWith('{') && value.trim().endsWith('}')) ||
                    (value.trim().startsWith('[') &&
                        value.trim().endsWith(']')))));
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: <PopupMenuEntry<dynamic>>[
        _compactMenuItem(
          child: Text(l10n.resultsContextCopyCell),
          onTap: () {
            if (value != null) {
              Clipboard.setData(ClipboardData(text: value.toString()));
            }
          },
        ),
        _compactMenuItem(
          child: Text(l10n.resultsContextCopyRowJson),
          onTap: () {
            final row = _filteredData[rowIndex];
            final jsonStr = row.toString();
            Clipboard.setData(ClipboardData(text: jsonStr));
          },
        ),
        if (supportsSqlExport) ...[
          const PopupMenuDivider(height: _kCompactMenuDividerHeight),
          _compactMenuItem(
            child: Text(l10n.resultsContextExportRowInsert),
            onTap: () => _exportRowAsInsert(rowIndex),
          ),
          _compactMenuItem(
            child: Text(l10n.resultsContextExportAllInsert),
            onTap: () => _exportAllAsInsert(),
          ),
        ],
        // Phase C — JSON-specific context menu items
        if (isJsonValue) ...[
          const PopupMenuDivider(height: _kCompactMenuDividerHeight),
          _compactMenuItem(
            child: Row(
              children: [
                Icon(
                  LucideIcons.braces,
                  size: 16,
                  color: context.themeColors.textSecondary,
                ),
                SizedBox(width: AppDesignSystem.space2),
                Text(l10n.viewJson),
              ],
            ),
            onTap: () {
              // HOTFIX: PG driver auto-parses jsonb into Map/List
              final jsonStr = (value is Map || value is List)
                  ? jsonEncode(value)
                  : value.toString();
              showJsonCellViewer(
                context,
                jsonString: jsonStr,
                columnName: columnName,
              );
            },
          ),
          if (isJsonCol)
            _compactMenuItem(
              child: Row(
                children: [
                  Icon(
                    LucideIcons.gitFork,
                    size: 16,
                    color: context.themeColors.textSecondary,
                  ),
                  SizedBox(width: AppDesignSystem.space2),
                  Text(l10n.extractFieldAsColumn),
                ],
              ),
              onTap: () {
                // HOTFIX: PG driver auto-parses jsonb into Map/List
                final jsonStr = (value is Map || value is List)
                    ? jsonEncode(value)
                    : value.toString();
                _showExtractFieldDialog(columnName, jsonStr);
              },
            ),
        ],
        const PopupMenuDivider(height: _kCompactMenuDividerHeight),
        // U07/D1-A：Set NULL 依赖编辑写回，随编辑态一并停用（完整版恢复）。
      ],
    );
  }

  // Phase C — dialog to extract JSON field path as PG expression
  void _showExtractFieldDialog(String columnName, String jsonString) {
    try {
      final parsed = jsonDecode(jsonString);
      final keys = <String>[];
      if (parsed is Map<String, dynamic>) {
        keys.addAll(parsed.keys.cast<String>());
      }

      if (keys.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.resultsExtractNoKeys),
          ),
        );
        return;
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            AppLocalizations.of(context)!.resultsExtractFieldTitle(columnName),
          ),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: keys.length,
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(LucideIcons.keyRound, size: 18),
                title: Text(
                  keys[i],
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                subtitle: Text(
                  '$columnName->\'${keys[i]}\'',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.themeColors.textMuted,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  ),
                ),
                onTap: () {
                  final expression = '$columnName->\'${keys[i]}\'';
                  Clipboard.setData(ClipboardData(text: expression));
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.resultsCopiedExpression(expression),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.resultsExtractInvalidJson,
          ),
        ),
      );
    }
  }

  Future<void> _exportRowAsInsert(int rowIndex) async {
    final l10n = AppLocalizations.of(context)!;
    final tableName = _extractTableName();
    if (tableName == null) {
      _showExportError(l10n.resultsInsertNoTableName);
      return;
    }

    final row = _filteredData[rowIndex];
    final sql = _generateInsertStatement(tableName, _columns, [row]);

    await Clipboard.setData(ClipboardData(text: sql));
    _showExportSuccess(l10n.resultsInsertRowDone);
  }

  Future<void> _exportAllAsInsert() async {
    final l10n = AppLocalizations.of(context)!;
    final tableName = _extractTableName();
    if (tableName == null) {
      _showExportError(l10n.resultsInsertNoTableName);
      return;
    }

    if (_filteredData.isEmpty) {
      _showExportError(l10n.resultsInsertNoData);
      return;
    }

    final sql = _generateInsertStatement(tableName, _columns, _filteredData);

    await Clipboard.setData(ClipboardData(text: sql));
    _showExportSuccess(l10n.resultsInsertAllDone(_filteredData.length));
  }

  String? _extractTableName() {
    // Fix TC-045: Use original casing SQL, support schema prefix and aliases
    final sql = widget.result.statement.sql;

    // Match: FROM [schema.]table [alias]
    // Supports: unquoted, backtick-quoted (`), double-quote-quoted ("), bracket-quoted ([)
    // Group 2 is the actual table name
    final pattern = RegExp(
      r'FROM\s+(?:[\["`]?(\w+)[\]"`]?\.)?[\["`]?(\w+)[\]"`]?(?:\s+(?:AS\s+)?(\w+))?',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(sql);
    if (match != null && match.group(2) != null) {
      return match.group(2);
    }

    return null;
  }

  String _getQuoteChar() {
    try {
      final provider = Provider.of<AppProvider>(context, listen: false);
      final server = provider.connection.currentServer;
      if (server == null) return '`';
      switch (server.type) {
        case DatabaseType.mysql:
        case DatabaseType.clickhouse:
        case DatabaseType.doris:
          return '`';
        case DatabaseType.postgresql:
        case DatabaseType.sqlite:
          return '"';
        default:
          return '`';
      }
    } catch (e) {
      return '`';
    }
  }

  String _generateInsertStatement(
    String tableName,
    List<String> columns,
    List<Map<String, dynamic>> rows,
  ) {
    final buffer = StringBuffer();
    final quote = _getQuoteChar();

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];

      buffer.write('INSERT INTO $quote$tableName$quote (');
      buffer.write(columns.map((c) => '$quote$c$quote').join(', '));
      buffer.write(') VALUES (');

      final values = columns
          .map((col) {
            final value = row[col];
            return _formatSqlValue(value);
          })
          .join(', ');

      buffer.write(values);
      buffer.writeln(');');
    }

    return buffer.toString();
  }

  String _formatSqlValue(dynamic value) {
    if (value == null) {
      return 'NULL';
    }

    if (value is num) {
      return value.toString();
    }

    if (value is bool) {
      return value ? '1' : '0';
    }

    // Escape single quotes for strings
    final strValue = value.toString().replaceAll("'", "''");
    return "'$strValue'";
  }

  void _showExportSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showExportError(String message) {
    if (!mounted) return;
    AppErrorHandler.showErrorSnackBar(
      context,
      message,
      duration: const Duration(seconds: 3),
    );
  }

  Widget _buildFilterStatusBar() {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1_5,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Text(
            l10n.resultsFilterConditions(_filterService.activeFilterCount),
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.resultsShowingRows(_filteredData.length, _data.length),
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              setState(() {
                _filterService.clearFilters();
                _sortState = null;
                _filteredData = List.from(_data);
              });
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space0_5,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l10n.resultsClearFilter),
          ),
        ],
      ),
    );
  }
}

class CellEdit {
  final String cellKey;
  final int rowIndex;
  final String colName;
  final dynamic originalValue;
  dynamic newValue;
  final TextEditingController controller;
  final FocusNode focusNode;

  CellEdit({
    required this.cellKey,
    required this.rowIndex,
    required this.colName,
    required this.originalValue,
    required this.newValue,
    required this.controller,
    required this.focusNode,
  });

  bool get hasChanged => newValue != originalValue?.toString();
}

class ResultTabState {
  final ResultFilterService filterService = ResultFilterService();
  SortState? sortState;
  List<Map<String, dynamic>> filteredData = [];

  void dispose() {
    // 清理资源
  }
}
