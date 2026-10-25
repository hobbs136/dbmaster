// ============================================================================
// DbMaster Editor Results Split — 可切换上下/左右分栏
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../providers/app_provider.dart';
import '../models/panel_layout.dart'; // spec 041: PanelLayout 类型（面板可见性）
import '../providers/layout_preferences_provider.dart';
import '../organisms/editor/query_editor_widget.dart';
import '../organisms/editor/filter_bar_strip.dart'; // spec 041 US3: FilterBar widget
import '../organisms/results/results_widget.dart';
import '../organisms/connection/object_tabs/object_tab_view.dart';
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

  /// UIRV-A41：过滤弹层开关 + Filter 入口焦点（Esc 关闭后归还焦点）。
  bool _filterPopupOpen = false;
  final FocusNode _filterEntryFocus = FocusNode();

  /// UI35-141~144：FilterBarStrip 上抛的草稿态（draft ≠ applied），
  /// 驱动 Filter 入口的未应用圆点 / tooltip / accent 边框。
  bool _filterHasDraft = false;

  void _onFilterDraftChanged(bool hasDraft) {
    if (hasDraft != _filterHasDraft) {
      setState(() => _filterHasDraft = hasDraft);
    }
  }

  /// 过滤弹层收起并归还焦点到 Filter 入口（弹层 Esc / 关闭钮 / Apply 收起共用）。
  void _closeFilterPopup() {
    // 已关闭时 no-op：弹层常驻挂载（Offstage 保活）后，关闭态下的时间戳
    // 推进仍会触发 onClose，重复执行会把焦点错误抢回 Filter 入口。
    if (!mounted || !_filterPopupOpen) return;
    setState(() => _filterPopupOpen = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _filterEntryFocus.requestFocus();
    });
  }

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
    _filterEntryFocus.dispose();
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
    // T16 J4：活动 tab 为只读对象 tab（ER 图/表属性）→ 内容占满
    // （editor/FilterBar/results 全隐，沿 data 模式先例）。activeTabId
    // 订阅保证对象 tab 之间切换（PanelLayout 值相同）也触发重建。
    final activeTabId = context.select<AppProvider, String?>(
      (p) => p.activeTab?.id,
    );
    if (activeTabId != null) {
      final objectRef = widget.provider.tab.objectTabFor(activeTabId);
      if (objectRef != null) {
        return ObjectTabView(tabId: activeTabId, ref: objectRef);
      }
    }
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
      // data 模式：结果数据网格（无子标签栏、无 editor/工具栏）+ Filter 入口；
      // FilterBarStrip 改为覆盖式弹层承载（UIRV-A41）。
      final filterConditionCount = activeTabId == null
          ? 0
          : context.select<AppProvider, int>(
              (p) => p.filterConditionsFor(activeTabId).length,
            );
      return _buildDataMode(activeTabId, filterConditionCount);
    }
    // query 模式
    return _buildQueryMode(context, layout);
  }

  /// UIRV-A41：data 模式装配——单一结果工具栏（含 Filter 入口）+ 覆盖式过滤
  /// 弹层（Stack，不推挤网格布局）。弹层经 Offstage 常驻挂载（打回修复：
  /// 关闭再开草稿条件行保留；offstage 下不绘制/不命中/零布局占位），
  /// FilterBarStrip 内部条件/combinator/Apply 执行路径零改动。
  Widget _buildDataMode(String? activeTabId, int filterConditionCount) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: _buildResults(
                    showSubTabs: false,
                    filterEntry: _buildFilterEntry(
                      activeTabId,
                      filterConditionCount,
                      _filterHasDraft,
                    ),
                  ),
                ),
              ],
            ),
            if (activeTabId != null)
              Positioned(
                top: 40,
                left: AppDesignSystem.space3,
                // UIRV-A41 打回修复：弹层常驻挂载（Offstage 保活）——关闭时
                // FilterBarStrip 子树状态（未 Apply 的草稿条件行）不丢失；
                // offstage 下不绘制、不命中测试、布局占位为零，不遮挡交互。
                child: Offstage(
                  offstage: !_filterPopupOpen,
                  child: _FilterPopupPanel(
                    key: const ValueKey('uirv-a41-filter-popup'),
                    tabId: activeTabId,
                    open: _filterPopupOpen,
                    maxWidth: math.min(
                      _kFilterPopupMaxWidth,
                      math.max(
                        120.0,
                        constraints.maxWidth - AppDesignSystem.space3 * 2,
                      ),
                    ),
                    onClose: _closeFilterPopup,
                    onDraftChanged: _onFilterDraftChanged,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// UIRV-A41：Filter 入口按钮（工具栏内；显示激活条件数徽标，0 时无徽标）。
  /// UI35-141~144：草稿态追加 6px warning 圆点（不承载语义/数量）+ 草稿
  /// tooltip + accent 边框（不只靠颜色），数字徽标仍只数生效条件。
  Widget _buildFilterEntry(String? tabId, int conditionCount, bool hasDraft) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final button = TextButton.icon(
      key: const ValueKey('uirv-a41-filter-entry'),
      onPressed: tabId == null
          ? null
          : () => setState(() => _filterPopupOpen = !_filterPopupOpen),
      icon: Icon(
        LucideIcons.filter,
        size: 16,
        color: colors.textSecondary,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.resultsFilterEntry,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          if (conditionCount > 0) ...[
            const SizedBox(width: AppDesignSystem.space1),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: colors.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                '$conditionCount',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.accentBlue,
                ),
              ),
            ),
          ],
          if (hasDraft) ...[
            const SizedBox(width: AppDesignSystem.space1),
            // 未应用修改圆点：纯视觉指示，不单独声明 Semantics
            //（语义由按钮 tooltip 承载）。
            Container(
              key: const ValueKey('uirv-a41-filter-draft-dot'),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.warning,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      style: TextButton.styleFrom(
        foregroundColor: colors.textSecondary,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space1,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        // UI35-附加：草稿态 accent 边框与圆点同现（不只靠颜色）。
        side: hasDraft ? BorderSide(color: colors.accentBlue) : null,
      ),
    );
    return Focus(
      focusNode: _filterEntryFocus,
      child: hasDraft
          ? Tooltip(message: l10n.filterDraftDotTooltip, child: button)
          : button,
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

  Widget _buildResults({bool showSubTabs = true, Widget? filterEntry}) {
    return Column(
      children: [
        Expanded(
          child: ResultsWidget(
            key: widget.resultsWidgetKey,
            showSubTabs: showSubTabs,
            filterEntry: filterEntry,
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

// ============================================================================
// _FilterPopupPanel — UIRV-A41 过滤弹层（覆盖式，FilterBarStrip 呈现容器）
// ============================================================================
///
/// 只换呈现容器：内部条件/combinator/Apply → buildFilteredSelect → 执行
/// 守卫/行限/历史/PII 路径全部留在 [FilterBarStrip]，本面板零复制。
/// 收起信号：Apply 成功 = 活跃结果子标签时间戳推进且非失败 → onClose；
/// 执行失败（子标签 errorMessage 或结果 success=false）→ 保持展开并在
/// 面板内呈现失败提示（验收条款 4：不用空白顶替）。
const double _kFilterPopupMaxWidth = 400;

class _FilterPopupPanel extends StatefulWidget {
  final String tabId;

  /// 弹层是否展开（宿主 Offstage 保活：关闭时子树仍在但不可见不可命中；
  /// 打开瞬间经本标志把焦点交给面板，支持 Esc 关闭）。
  final bool open;

  /// 弹层宽度上限（窄窗取宿主可用宽，由装配处预算）。
  final double maxWidth;
  final VoidCallback onClose;

  /// UI35-141~144：FilterBarStrip 草稿态上抛通道（面板只透传，不复制逻辑）。
  final ValueChanged<bool>? onDraftChanged;

  const _FilterPopupPanel({
    super.key,
    required this.tabId,
    required this.open,
    required this.maxWidth,
    required this.onClose,
    this.onDraftChanged,
  });

  @override
  State<_FilterPopupPanel> createState() => _FilterPopupPanelState();
}

class _FilterPopupPanelState extends State<_FilterPopupPanel> {
  /// 打开（或上次执行）时观察到的活跃子标签时间戳——Apply 完成的观察面。
  DateTime? _lastSeenTimestamp;
  bool _showApplyFailed = false;

  /// 面板焦点（打开时接管，Esc 在此关闭；替代常驻化后失效的 autofocus）。
  final FocusNode _panelFocus = FocusNode();

  @override
  void didUpdateWidget(covariant _FilterPopupPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open && !oldWidget.open) {
      _panelFocus.requestFocus();
    }
  }

  @override
  void dispose() {
    _panelFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final timestamp = context.select<AppProvider, DateTime?>(
      (p) => p.tab.activeResultSubTab?.timestamp,
    );
    if (_lastSeenTimestamp == null) {
      _lastSeenTimestamp = timestamp;
    } else if (timestamp != _lastSeenTimestamp) {
      _lastSeenTimestamp = timestamp;
      final provider = context.read<AppProvider>();
      final sub = provider.tab.activeResultSubTab;
      final failed =
          sub?.hasError == true ||
          (sub?.executionResults.any((r) => !r.success) ?? false);
      _showApplyFailed = failed;
      if (!failed && widget.open) {
        // Apply 成功 → 收起弹层（build 期不触发回调，post-frame 执行）。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onClose();
        });
      }
    }

    return Focus(
      focusNode: _panelFocus,
      onKeyEvent: (node, event) {
        if (widget.open &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        color: colors.bgPrimary,
        child: Container(
          width: widget.maxWidth,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(color: colors.borderLight),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 弹层头：标题 + 关闭钮（Esc 的可见等价物）。
              Row(
                children: [
                  Icon(
                    LucideIcons.filter,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  Expanded(
                    child: Text(
                      l10n.resultsFilterEntry,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  InkResponse(
                    onTap: widget.onClose,
                    radius: 12,
                    child: Padding(
                      padding: const EdgeInsets.all(AppDesignSystem.space1),
                      child: Icon(
                        LucideIcons.x,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppDesignSystem.space1),
              // 既有过滤构造器原样挂载（per-tab 实例，内部逻辑零改动）。
              FilterBarStrip(
                key: ValueKey('filterbar:${widget.tabId}'),
                tabId: widget.tabId,
                onDraftChanged: widget.onDraftChanged,
              ),
              if (_showApplyFailed) ...[
                const SizedBox(height: AppDesignSystem.space1),
                Row(
                  children: [
                    Icon(
                      LucideIcons.triangleAlert,
                      size: 14,
                      color: colors.accentRed,
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Expanded(
                      child: Text(
                        l10n.resultsFilterApplyFailed,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.accentRed,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
