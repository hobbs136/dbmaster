// ============================================================================
// DbMaster Editor Results Split — 可切换上下/左右分栏
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/app_provider.dart';
import '../models/panel_layout.dart'; // spec 041: PanelLayout 类型（面板可见性）
import '../providers/layout_preferences_provider.dart';
import '../organisms/editor/query_editor_widget.dart';
import '../organisms/editor/filter_bar_strip.dart'; // spec 041 US3: FilterBar widget
import '../organisms/results/results_widget.dart';
import '../molecules/resizer_widgets.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class EditorResultsSplit extends StatefulWidget {
  final AppProvider provider;
  final LayoutPreferencesProvider layoutProvider;
  final bool isResizing;
  final VoidCallback onResizeStart;
  final VoidCallback onResizeEnd;
  final GlobalKey<ResultsWidgetState> resultsWidgetKey;

  /// 命令面板入口（C21 M3：透传给编辑器工具栏，随 BreadcrumbBar 退役迁入）。
  final VoidCallback? onCommandPalette;

  const EditorResultsSplit({
    super.key,
    required this.provider,
    required this.layoutProvider,
    required this.isResizing,
    required this.onResizeStart,
    required this.onResizeEnd,
    required this.resultsWidgetKey,
    this.onCommandPalette,
  });

  @override
  State<EditorResultsSplit> createState() => _EditorResultsSplitState();
}

class _EditorResultsSplitState extends State<EditorResultsSplit> {
  /// One [GlobalKey] per [QueryTab] so the result panel can invoke editor
  /// methods (e.g. append SQL from history) on the active tab.
  final Map<String, GlobalKey<QueryEditorWidgetState>> _editorKeys = {};

  GlobalKey<QueryEditorWidgetState> _editorKeyFor(String tabId) {
    return _editorKeys.putIfAbsent(
      tabId,
      GlobalKey<QueryEditorWidgetState>.new,
    );
  }

  @override
  void initState() {
    super.initState();
    // 注册侧栏 → 活动编辑器 光标处插入 的桥接回调
    widget.provider.insertIntoActiveEditor = _insertIntoActiveEditor;
  }

  @override
  void dispose() {
    // 清理桥接回调，避免悬空引用（仅当仍指向本实例时置空）
    if (widget.provider.insertIntoActiveEditor == _insertIntoActiveEditor) {
      widget.provider.insertIntoActiveEditor = null;
    }
    super.dispose();
  }

  /// 把 [text] 插入到当前活动 tab 的查询编辑器光标处；无活动 tab 则 no-op。
  // 侧栏双击列名插入编辑器的实际执行点
  void _insertIntoActiveEditor(String text) {
    final activeTab = widget.provider.tab.activeTab;
    if (activeTab == null) return;
    final key = _editorKeys[activeTab.id];
    key?.currentState?.insertAtCursor(text);
  }

  void _onHistoryDoubleTapped(String sql) {
    final activeTab = widget.provider.tab.activeTab;
    if (activeTab == null) return;
    final key = _editorKeys[activeTab.id];
    if (key == null) return;
    key.currentState?.appendSql(sql);
  }

  void _onHistoryTapped(String sql) {
    final activeTab = widget.provider.tab.activeTab;
    if (activeTab == null) return;
    final key = _editorKeys[activeTab.id];
    if (key == null) return;
    key.currentState?.setSql(sql);
  }

  @override
  Widget build(BuildContext context) {
    // spec 041：固定模式（不切换）。data 模式 = FilterBar + 数据网格；
    // query 模式 = editor + 工具栏 + 结果(子标签)。context.select 精确订阅。
    final layout = context.select<AppProvider, PanelLayout>(
      (p) => p.activePanelLayout,
    );
    final supportsFilterBar = context.select<AppProvider, bool>(
      (p) => p.activeSupportsFilterBar,
    );
    final isDataMode = layout.filterBarVisible && supportsFilterBar;
    if (isDataMode) {
      // data 模式：FilterBar + 结果数据网格（无子标签栏、无 editor/工具栏）
      return Column(
        children: [
          _buildFilterBarRegion(),
          Expanded(child: _buildResults(showSubTabs: false)),
        ],
      );
    }
    // query 模式
    return _buildQueryMode(context, layout);
  }

  /// Region-1 FilterBar：per-tab 实例（IndexedStack，各 tab 自持控制器，非跨 tab 单例）。
  /// 仅在 active tab 的 filterBarVisible && supportsFilterBar 时由 build 渲染本区域。
  Widget _buildFilterBarRegion() {
    final tabs = widget.provider.tabs;
    if (tabs.isEmpty) return const SizedBox.shrink();
    return IndexedStack(
      index: widget.provider.activeTabIndex.clamp(0, tabs.length - 1),
      children: tabs
          .map(
            (tab) => FilterBarStrip(
              key: ValueKey('filterbar:${tab.id}'),
              tabId: tab.id,
            ),
          )
          .toList(),
    );
  }

  /// query 模式：editor 恒显；results 按 resultsVisible（首次执行前 editor 占满）。
  Widget _buildQueryMode(BuildContext context, PanelLayout layout) {
    if (layout.resultsVisible) {
      final isHorizontal =
          widget.layoutProvider.editorResultsOrientation ==
          EditorResultsOrientation.horizontal;
      return isHorizontal
          ? _buildHorizontalSplit(context)
          : _buildVerticalSplit(context);
    }
    // results 未显（新 query tab 首次执行前）→ editor 占满
    return _buildEditor();
  }

  // ============================================================================
  // 上下分栏（默认）
  // ============================================================================
  Widget _buildVerticalSplit(BuildContext context) {
    final ratio = widget.layoutProvider.editorResultsRatio.clamp(0.2, 0.8);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        const resizerHeight = 12.0; // plan §3.3：8→12，更易命中
        final availableHeight = math.max(0.0, totalHeight - resizerHeight);
        const minPanelHeight = 120.0; // plan §3.3：50→120，结果区不可压到不可读
        final maxEditorHeight = math.max(
          minPanelHeight,
          availableHeight - minPanelHeight,
        );
        final editorHeight = (availableHeight * ratio).clamp(
          minPanelHeight,
          maxEditorHeight,
        );
        final resultsHeight = math.max(0.0, availableHeight - editorHeight);

        return Column(
          children: [
            // Query Editor
            SizedBox(height: editorHeight, child: _buildEditor()),
            // Resizer
            SizedBox(
              height: resizerHeight,
              child: _buildResizer(editorHeight, availableHeight),
            ),
            // Results
            SizedBox(height: resultsHeight, child: _buildResults()),
          ],
        );
      },
    );
  }

  // ============================================================================
  // 左右分栏（宽屏）
  // ============================================================================
  Widget _buildHorizontalSplit(BuildContext context) {
    final ratio = widget.layoutProvider.editorResultsRatio.clamp(0.2, 0.8);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        const resizerWidth = 12.0; // plan §3.3：8→12，更易命中
        final availableWidth = math.max(0.0, totalWidth - resizerWidth);
        const minPanelWidth = 280.0; // plan §3.3：200→280
        final maxEditorWidth = math.max(
          minPanelWidth,
          availableWidth - minPanelWidth,
        );
        final editorWidth = (availableWidth * ratio).clamp(
          minPanelWidth,
          maxEditorWidth,
        );
        final resultsWidth = math.max(0.0, availableWidth - editorWidth);

        return Row(
          children: [
            // Query Editor
            SizedBox(width: editorWidth, child: _buildEditor()),
            // Resizer
            SizedBox(
              width: resizerWidth,
              child: _buildHorizontalResizer(editorWidth, availableWidth),
            ),
            // Results
            SizedBox(width: resultsWidth, child: _buildResults()),
          ],
        );
      },
    );
  }

  // ============================================================================
  // 共享子组件
  // ============================================================================

  Widget _buildEditor() {
    return IndexedStack(
      index: widget.provider.activeTabIndex,
      children: widget.provider.tabs.asMap().entries.map((entry) {
        final tab = entry.value;
        return QueryEditorWidget(
          key: _editorKeyFor(tab.id),
          tabIndex: entry.key,
          resultsWidgetKey: widget.resultsWidgetKey,
          onCommandPalette: widget.onCommandPalette,
        );
      }).toList(),
    );
  }

  Widget _buildResults({bool showSubTabs = true}) {
    return Column(
      children: [
        Expanded(
          child: ResultsWidget(
            key: widget.resultsWidgetKey,
            showSubTabs: showSubTabs,
            onHistoryDoubleTapped: (history) =>
                _onHistoryDoubleTapped(history.sql),
            onHistoryTapped: (history) => _onHistoryTapped(history.sql),
          ),
        ),
        const ExecutionStatusBar(),
      ],
    );
  }

  Widget _buildResizer(double editorHeight, double availableHeight) {
    return EditorResultsResizer(
      isResizing: widget.isResizing,
      onResizeStart: widget.onResizeStart,
      onResizeUpdate: (delta) {
        final newRatio = (editorHeight + delta) / availableHeight;
        widget.layoutProvider.setEditorResultsRatio(newRatio);
      },
      onResizeEnd: widget.onResizeEnd,
    );
  }

  Widget _buildHorizontalResizer(double editorWidth, double availableWidth) {
    return EditorResultsResizer(
      isResizing: widget.isResizing,
      isHorizontal: true,
      onResizeStart: widget.onResizeStart,
      onResizeUpdate: (delta) {
        final newRatio = (editorWidth + delta) / availableWidth;
        widget.layoutProvider.setEditorResultsRatio(newRatio);
      },
      onResizeEnd: widget.onResizeEnd,
    );
  }
}

// ============================================================================
// ExecutionStatusBar — 执行状态栏
// ============================================================================
///
/// 显示当前 ResultSubTab 的查询执行摘要。
/// 数据源：`TabProvider.activeResults[activeResultIndex]`
///
/// 含手动关闭按钮（X icon）：点击后隐藏，结果变更时自动恢复显示。
class ExecutionStatusBar extends StatefulWidget {
  const ExecutionStatusBar({super.key});

  @override
  State<ExecutionStatusBar> createState() => _ExecutionStatusBarState();
}

class _ExecutionStatusBarState extends State<ExecutionStatusBar> {
  bool _dismissed = false;
  Object? _lastResultsIdentity;

  void _resetIfChanged(List<dynamic> results) {
    final id = identityHashCode(results);
    if (_lastResultsIdentity != id) {
      _lastResultsIdentity = id;
      _dismissed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final activeResults = provider.tab.activeResults;
        final activeIdx = provider.tab.activeResultIndex;
        final activeSub = (activeIdx >= 0 && activeIdx < activeResults.length)
            ? activeResults[activeIdx]
            : null;

        final executionResults = activeSub?.executionResults ?? [];
        if (executionResults.isEmpty) {
          _dismissed = false;
          _lastResultsIdentity = null;
          return const SizedBox.shrink();
        }

        _resetIfChanged(executionResults);
        if (_dismissed) return const SizedBox.shrink();

        final successCount = executionResults.where((r) => r.success).length;
        final errorCount = executionResults.length - successCount;
        final totalTime = executionResults.fold<Duration>(
          Duration.zero,
          (sum, r) => sum + r.executionTime,
        );
        final totalRows = executionResults
            .where((r) => r.hasData)
            .fold<int>(0, (sum, r) => sum + r.data!.length);

        final hasErrors = errorCount > 0;

        return Container(
          height: 28,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          decoration: BoxDecoration(
            // plan §3.3：成功态无彩色背景（文字+图标即可），错误态保留彩色背景
            color: hasErrors
                ? context.themeColors.accentRed.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border(
              top: BorderSide(
                color: hasErrors
                    ? context.themeColors.accentRed.withValues(alpha: 0.2)
                    : context.themeColors.dividerColor,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                hasErrors
                    ? LucideIcons.triangleAlert
                    : LucideIcons.circleCheckBig,
                size: 14,
                color: hasErrors
                    ? context.themeColors.accentRed
                    : context.themeColors.accentGreen,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                hasErrors
                    ? l10n.statementsPartialSuccessShort(
                        successCount,
                        executionResults.length,
                        errorCount,
                      )
                    : l10n.statementsAllSuccess(executionResults.length),
                style: TextStyle(
                  fontSize: 11,
                  color: hasErrors
                      ? context.themeColors.accentRed
                      : context.themeColors.accentGreen,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space4),
              Text(
                '${totalTime.inMilliseconds}ms',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textSecondary,
                ),
              ),
              if (totalRows > 0) ...[
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  '·',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textMuted,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  l10n.executionStatusBarRows(totalRows),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ],
              const Spacer(),
              // 提示文本长文案（六语）下弹性收缩 + 省略号，保证关闭按钮
              // 恒在视口内可命中（800px 最小窗口测试视口实测约束）。
              if (hasErrors)
                Flexible(
                  child: Text(
                    l10n.executionStatusBarErrorHint,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              InkResponse(
                onTap: () => setState(() => _dismissed = true),
                radius: 12,
                child: Padding(
                  padding: const EdgeInsets.only(left: AppDesignSystem.space2),
                  child: Icon(
                    LucideIcons.x,
                    size: 14,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
