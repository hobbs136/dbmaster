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
import 'row_edit_dialog.dart';
import 'statistics_panel.dart';
import '../../services/result_statistics_service.dart';
import '../../services/ai_summary_service.dart';
import '../../services/ai_service.dart';
import '../../utils/app_logger.dart';
import 'query_history/result_history_view.dart';
import '../../models/query_history.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../theme/app_colors.dart';

/// T25（L-3 三处收口，J3 地基）：结果网格的上下文连接解析——所属 tab
/// （活动 tab）的 connectionId 从 savedConnections 查表（R1-P2 同模式：
/// currentServer 在多连接场景可能指向另一连接）；tab 无 connectionId 或
/// 指向已删除连接（查不到）→ 降级 [AppProvider.activeContextConnection]
/// （tab → currentServer → 侧栏选中），最终 currentServer 直读兜底（与
/// 旧实现同深度，防御性保持）。消费面：`_supportsSqlExport` /
/// `_getDatabaseType` / `_getQuoteChar`（FU-DBT-4 销项）。
DbServer? _resultsContextServer(AppProvider provider) {
  final cid = provider.tab.activeTab?.connectionId;
  if (cid != null) {
    final server =
        provider.savedConnections.where((s) => s.id == cid).firstOrNull;
    if (server != null) return server;
    // tab 指向已删除连接 → 降级兜底链（不崩不悬空，任务书边界条款）。
  }
  return provider.activeContextConnection ?? provider.connection.currentServer;
}

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

  /// UIRV-A41：工具栏 Filter 入口槽（宿主注入；query 模式不传 → 不渲染）。
  /// 过滤弹层由宿主（editor_results_split 数据模式）承载，本组件只提供
  /// 单一 36px 工具栏的槽位。
  final Widget? filterEntry;

  const ResultsWidget({
    super.key,
    this.onHistoryDoubleTapped,
    this.onHistoryTapped,
    this.showSubTabs = true,
    this.filterEntry,
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

  /// UIRV-A41：视图模式选择（per-result，键 = 结果子标签 id）。
  /// 分段按钮上提到外层工具栏后，per-result 语义由本 map 承载——
  /// 切子标签时读各自的选择，互不影响（原实现靠 ResultTabContent
  /// State 复用保留，上提后显式化）。
  final Map<String, String> _viewModeBySubTabId = <String, String>{};

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
    // 精确选择：仅在 Tab ID / 活跃子标签索引 / 子标签数量 / 活跃子标签
    // 时间戳变化时重建，避免 sidebar / connection / aiPanel 等无关 Provider
    // 变更导致的浪费（C22 M2 走查反馈二轮：语句层并入子标签层，内层结果
    // 索引已移除）。第 4 元（子标签 timestamp）是 J1-a 行编辑刷新批补充：
    // 重跑同形浏览查询时 addResultToTab 原位替换子标签（id 复用、数量与
    // 索引不变），三元组恒等会让网格停留在旧数据——timestamp 每次执行都
    // 新生成，作为「内容已变」的观察面。
    final resultKey = context
        .select<AppProvider, (String?, int, int, DateTime?)>(
          (p) => (
            p.tab.activeTab?.id,
            p.tab.activeResultIndex,
            p.tab.activeResults.length,
            p.tab.activeResultSubTab?.timestamp,
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
            // 单一工具栏（UIRV-A41：视图分段 + Filter 入口 + 批次动作同栏）
            _buildHeader(executionResults, activeSub),
            // 行级搜索框（点击搜索按钮展开，spec 051 R1）
            if (_searchVisible) _buildSearchField(),
            // 内容区
            Expanded(
              child: _buildContent(
                executionResults,
                tabId: currentTabId,
                subTabId: activeSub?.id,
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
    required String? subTabId,
    required bool hasError,
    required String? errorMessage,
  }) {
    if (hasError) {
      return _buildErrorDisplay(errorMessage ?? 'Unknown error');
    }
    if (results.isEmpty) {
      return _buildEmptyState();
    }
    return _buildResultTab(results.first, 0, tabId: tabId, subTabId: subTabId);
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

  /// UIRV-A41：单一 36px 工具栏——左：视图切换分段（per-result 语义，
  /// 见 [_viewModeBySubTabId]）+ 宿主注入的 Filter 入口槽；右：AI/导出/搜索。
  Widget _buildHeader(List<ExecutionResult> results, ResultSubTab? activeSub) {
    final subTabId = activeSub?.id;
    final result = results.isNotEmpty ? results.first : null;
    final renderers = _activeRenderers(result);
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
          // 极窄容器下分段/入口/动作各自收缩缩放（Ahem 测试字体与超窄窗
          // 防 overflow；正常宽度按自然尺寸渲染，FittedBox 不介入）。
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: _buildViewModeSegment(renderers, subTabId),
            ),
          ),
          if (widget.filterEntry != null) ...[
            const SizedBox(width: AppDesignSystem.space2),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: widget.filterEntry!,
              ),
            ),
          ],
          const Spacer(),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildAiAnalyzeButton(results),
                  _buildExportButton(results),
                  _buildSearchButton(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// C11/C12：活跃结果适用的渲染器（注册表 + 形态过滤），供工具栏分段。
  List<ResultRendererPlugin> _activeRenderers(ExecutionResult? result) =>
      defaultPluginRegistry.resultRenderersFor(
        shape: result?.dataShape ?? ResultDataShape.sqlRows,
      );

  /// 生效视图 id：per-result 选择仍适用则用之，否则注册序首个。
  String _effectiveViewModeId(
    List<ResultRendererPlugin> renderers,
    String? subTabId,
  ) {
    final selected = subTabId == null ? null : _viewModeBySubTabId[subTabId];
    if (selected != null && renderers.any((r) => r.viewModeId == selected)) {
      return selected;
    }
    return renderers.first.viewModeId;
  }

  /// UIRV-A41：视图切换分段按钮（自 ResultTabContent 上提；状态 per-result）。
  Widget _buildViewModeSegment(
    List<ResultRendererPlugin> renderers,
    String? subTabId,
  ) {
    if (renderers.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;
    return SegmentedButton<String>(
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
      selected: {_effectiveViewModeId(renderers, subTabId)},
      onSelectionChanged: (selection) {
        final id = subTabId;
        if (id == null) return;
        setState(() => _viewModeBySubTabId[id] = selection.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => colors.textSecondary,
        ),
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

  Widget _buildResultTab(
    ExecutionResult result,
    int index, {
    String? tabId,
    String? subTabId,
  }) {
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
      viewModeId: subTabId == null ? null : _viewModeBySubTabId[subTabId],
      onViewModeChanged: (modeId) {
        final id = subTabId;
        if (id == null) return;
        setState(() => _viewModeBySubTabId[id] = modeId);
      },
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

  /// UIRV-A41：视图模式 id（宿主持有 per-result 状态后下行；null = 取注册序首个）。
  final String? viewModeId;

  /// UIRV-A41：视图切换回调（写入宿主 per-result 状态；null = 只读消费）。
  final ValueChanged<String>? onViewModeChanged;

  const ResultTabContent({
    super.key,
    required this.result,
    this.searchQuery = '',
    this.searchActive = false,
    this.viewModeId,
    this.onViewModeChanged,
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

  // R3: 统计摘要栏折叠状态（默认折叠）。
  bool _showStats = false;

  // Cell editing state
  CellEdit? _activeEdit;
  TextEditingController? _activeController;
  FocusNode? _activeFocusNode;
  final Map<String, CellEdit> _cellEdits = {};

  // ---- J1-a 行级编辑（browse 数据 tab 专属，2026-10-13 用户重开）----
  // PK 元数据缓存（键 = browseTarget）：一轮结果视图内右键只取一次，
  // _initData（数据刷新）时失效。null = 未取。
  List<DbColumn>? _rowEditColumns;
  String? _rowEditColumnsTarget;

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
    // J1-a：结果数据刷新 → 行编辑 PK 元数据缓存失效（表结构可能已变）。
    _rowEditColumns = null;
    _rowEditColumnsTarget = null;

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
        // UIRV-A41：视图切换分段已上提至外层单一工具栏（per-result 状态
        // 由 ResultsWidgetState 持有并经 widget.viewModeId 下行）。
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

  /// 生效的 viewModeId：宿主下行的选择仍在适用列表内用之，否则回退注册序
  /// 首个（形态变化 / 注册表变更后的自愈，不抛错）。
  String _effectiveViewModeId(List<ResultRendererPlugin> renderers) {
    final selected = widget.viewModeId;
    if (selected != null && renderers.any((r) => r.viewModeId == selected)) {
      return selected;
    }
    return renderers.first.viewModeId;
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
    // U07/D1-A + 2026-08-24 拍板「网格永不进编辑态」已于 2026-10-13 由用户
    // 重开（J1 方案 a 显式化路线）：写回改为仅 browse 数据 tab 的行右键
    // 「编辑此行」——行级表单 + UPDATE 预览 + 逐行确认 + 审计（「无假保存」
    // 四铁律，见 _handleCellContextMenu/_openRowEdit 与 row_edit_dialog.dart）。
    // 双击行为维持只读单元格查看器不变（长文本查看/复制的正式入口）；
    // 内联单元格编辑（方案 b）仍不做。
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
      // T25 L-3：按所属 tab 连接解析（多连接下不随 currentServer 串味）。
      final server = _resultsContextServer(provider);
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
              // T25 测试加固：菜单锚点为零宽矩形（fromRect 0×0），窄可用宽
              //（测试字体/极窄窗）下行内容须可收缩——Flexible + 省略号防
              // RenderFlex 溢出（真字体常规宽度下视觉零变化）。
              Flexible(
                child: Text(
                  l10n?.extractFieldAsColumn ?? 'Extract field as column',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
  ///
  /// T25 L-3：按所属 tab 连接解析（`_resultsContextServer`），多连接下
  /// 不随 currentServer 串味。
  DatabaseType _getDatabaseType() {
    try {
      final provider = context.read<AppProvider>();
      return _resultsContextServer(provider)?.type ?? DatabaseType.mysql;
    } catch (_) {
      return DatabaseType.mysql;
    }
  }

  /// J1-a（2026-10-13 用户重开）：行右键「编辑此行」可用性判定，fail-closed。
  ///
  /// ① 活动结果子标签所属 tab 的 `browseTargetFor(tabId)` 非空（手写 SQL
  /// 结果网格天然不开放——禁止用 `_currentTableName()` 正则推断）；
  /// ② `getTableColumns` 成功且 PK 列 ≥1（无 PK 表/视图 → 入口不出现；
  /// browseTarget 指向已删表 → 失败 snackbar + 不出现）；PK 列须全部在
  /// 结果列集（部分投影 → 禁用 + 说明）；
  /// ③ 连接 readonly → 禁用 + 只读说明 tooltip；
  /// ④ 目标行 PK 值非 null 且字面量类型可靠（num/bool/String）→ 否则禁用。
  /// 返回 null = 不出现入口。
  Future<_RowEditMenuState?> _resolveRowEditMenuState(int rowIndex) async {
    final provider = context.read<AppProvider>();
    final l10n = AppLocalizations.of(context)!;
    final tab = provider.tab.activeTab;
    if (tab == null) return null;
    final target = provider.browseTargetFor(tab.id);
    if (target == null) return null;
    final cid = tab.connectionId;
    if (cid == null) return null;
    // R1-P2：readonly 判定按 tab.connectionId 从 savedConnections 解析
    // （与 row_edit_dialog._executeViaDbService 同源；currentServer 在多
    // 连接场景可能指向另一连接）。连接已不存在 → 入口不出现（fail-closed）。
    final server = provider.savedConnections
        .where((s) => s.id == cid)
        .firstOrNull;
    if (server == null) return null;

    // PK 元数据（一轮结果视图缓存；刷新后失效重取）。
    List<DbColumn> columns;
    if (_rowEditColumnsTarget == target && _rowEditColumns != null) {
      columns = _rowEditColumns!;
    } else {
      try {
        columns = await rowEditColumnsFetcher(
          provider,
          cid,
          tab.databaseName,
          target,
        );
      } catch (e) {
        // 任务书边界条款：browseTarget 指向已删表等 → 错误 snackbar +
        // 入口不出现（不吞错、不假可用）。
        AppLogger.e('ResultsWidget', 'J1-a 行编辑元数据获取失败 target=$target', e);
        if (mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            e.toString(),
            duration: const Duration(seconds: 3),
          );
        }
        return null;
      }
      _rowEditColumns = columns;
      _rowEditColumnsTarget = target;
    }

    final pkColumns = columns.where((c) => c.isPrimaryKey).toList();
    if (pkColumns.isEmpty) return null;
    if (rowIndex < 0 || rowIndex >= _filteredData.length) return null;
    final row = _filteredData[rowIndex];

    if (!pkColumns.every((c) => row.containsKey(c.name))) {
      return _RowEditMenuState.disabled(l10n.rowEditNoPrimaryKey);
    }
    if (server.readOnly) {
      return _RowEditMenuState.disabled(l10n.rowEditReadonlyDisabled);
    }
    if (pkColumns.any((c) => !_RowEditMenuState.isLiteralSafe(row[c.name]))) {
      return _RowEditMenuState.disabled(l10n.rowEditNoPrimaryKey);
    }
    return _RowEditMenuState.enabled(columns);
  }

  /// J1-a：打开行编辑 dialog。返回 true（已更新）→ 重跑浏览查询刷新网格。
  Future<void> _openRowEdit(int rowIndex, List<DbColumn> columns) async {
    if (rowIndex < 0 || rowIndex >= _filteredData.length) return;
    final provider = context.read<AppProvider>();
    final tab = provider.tab.activeTab;
    if (tab == null) return;
    final target = provider.browseTargetFor(tab.id);
    final cid = tab.connectionId;
    if (target == null || cid == null) return;
    final row = Map<String, dynamic>.from(_filteredData[rowIndex]);

    final updated = await RowEditDialog.show(
      context,
      connectionId: cid,
      // R1-P3：不伪造空库名——null 交给服务层 `database ?? server.database`
      // 回退（跨库浏览场景 tab.databaseName 为空时回退连接默认库）。
      databaseName: tab.databaseName,
      qualifiedTableName: target,
      tableColumns: columns,
      rowValues: row,
    );
    if (!mounted || !updated) return;
    // 成功 → 成功反馈 + 重跑浏览查询刷新网格（executeCurrentQueryAndRecord
    // 读活动 tab 的浏览 SQL，与 FilterBar Apply 同一刷新路径）。
    AppErrorHandler.showSuccessSnackBar(
      context,
      AppLocalizations.of(context)!.rowEditSuccess,
    );
    try {
      await provider.executeCurrentQueryAndRecord();
    } catch (e) {
      AppLogger.d('ResultsWidget', '行编辑后刷新浏览查询失败: $e');
    }
  }

  Future<void> _handleCellContextMenu(
    int rowIndex,
    String columnName,
    dynamic value,
    Offset position,
  ) async {
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
    // J1-a：可用性判定含异步 PK 元数据取列（browse tab 首次右键取一次，
    // 之后走缓存）；fail-closed：不可用 = 不出现 / 禁用 + tooltip。
    final rowEdit = await _resolveRowEditMenuState(rowIndex);
    if (!mounted) return;
    await showMenu(
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
        // J1-a：行编辑入口（仅 browse 数据 tab 可达；disabled 时 tooltip
        // 说明不可用原因）。
        if (rowEdit != null) ...[
          const PopupMenuDivider(height: _kCompactMenuDividerHeight),
          _buildRowEditMenuItem(rowEdit, rowIndex),
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
        // U07/D1-A：Set NULL 快捷项不做——SQL NULL 置位已并入「编辑此行」
        // 行级表单（J1-a），无编辑态外的静默写路径。
      ],
    );
  }

  /// J1-a：「编辑此行」菜单项（enabled = 可发起；disabled = tooltip 说明）。
  PopupMenuEntry<dynamic> _buildRowEditMenuItem(
    _RowEditMenuState state,
    int rowIndex,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final editColumns = state.columns;
    final label = Row(
      children: [
        Icon(
          LucideIcons.pencilLine,
          size: 16,
          color: state.enabled ? colors.textSecondary : colors.textMuted,
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Text(l10n.rowEditMenuLabel),
      ],
    );
    return CompactPopupMenuItem<dynamic>(
      enabled: state.enabled,
      onTap: state.enabled && editColumns != null
          ? () => unawaited(_openRowEdit(rowIndex, editColumns))
          : null,
      child: state.disabledTooltip == null
          ? label
          : Tooltip(message: state.disabledTooltip, child: label),
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
      // T25 L-3：按所属 tab 连接解析（多连接下不随 currentServer 串味）。
      final server = _resultsContextServer(provider);
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

/// J1-a 行编辑菜单项可用性（`_resolveRowEditMenuState` 产物）：
/// enabled = 携带 PK 元数据可发起；disabled = tooltip 说明原因；null（外层）
/// = 入口不出现。
class _RowEditMenuState {
  final bool enabled;

  /// enabled 时携带（传给 [RowEditDialog]）。
  final List<DbColumn>? columns;
  final String? disabledTooltip;

  const _RowEditMenuState._(this.enabled, this.columns, this.disabledTooltip);

  const _RowEditMenuState.enabled(List<DbColumn> columns)
    : this._(true, columns, null);

  const _RowEditMenuState.disabled(String tooltip)
    : this._(false, null, tooltip);

  /// PK 值字面量可靠性（UPDATE WHERE 锚仅接受 num/bool/String；null 不可）。
  static bool isLiteralSafe(dynamic value) {
    return value != null && (value is num || value is bool || value is String);
  }
}

class ResultTabState {
  final ResultFilterService filterService = ResultFilterService();
  SortState? sortState;
  List<Map<String, dynamic>> filteredData = [];

  void dispose() {
    // 清理资源
  }
}
