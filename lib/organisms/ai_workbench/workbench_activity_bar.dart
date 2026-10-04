//! AI 工作台活动条（v2 结果面板第一批 A1，brainstorm-workbench-results-panel-v2
//! §6-1.1）。
//!
//! rail 最左列固定 44 宽图标条：工作台页面（会话 / 保存的查询 / 历史…）的
//! 切换入口。展开态 = `Row[活动条 44 | 内容页 196]`（总宽 240 不变）；
//! 收窄态 = 纯活动条。本组件只上报 [WorkbenchActivityBar.onPageSelected]，
//! 不感知路由（收窄态点击 → 舞台单例 tab 的路由由 A2 接线）。
//!
//! 选中态沿 rail 会话条目既有语法（design-ai-workbench NF3.4）：accentPurple
//! 图标 + 左侧 2px 指示条，未选中指示条用 bgSecondary 占位（不引 Colors.xxx）。
//!
//! A5（v2 先行批）：roving tabindex 键盘导航 + F6 第一区注册——每图标一个
//! State 持有的 FocusNode（debugLabel = `workbench_activity_<pageId>`，节点
//! onKeyEvent 承载 ↑/↓ 相邻、Home/End 首末、Enter 触发 onPageSelected，
//! 越界目标由宿主钳制，对齐舞台 tab 条既有 roving 模式
//! workbench_stage.dart `_StageTabItem._onKeyEvent`；键位语义零改动，只
//! 新增本组件的竖向变体）。焦点节点 map 随页列表增减清理（延后一帧
//! dispose，沿舞台 tab 条同款处理），dispose 全量释放。注册为 F6 第一区
//! [WorkbenchFocusZone.activityBar]：入口 = 聚焦当前选中页图标（对齐舞台
//! tab 条「聚焦激活 tab」语义；未选中回落首图标），挂载注册 / 卸载注销
//! （[WorkbenchFocusZoneRegistry.unregister] 身份比对防重挂竞态）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import 'workbench_focus_zones.dart';

/// 活动条页面枚举（v2 §6-1.1）。
///
/// 终态序 = 会话 / 保存的查询 / 历史（v2 §7-7）：A1 [sessions] → A3
/// [history]（波间序 会话/历史）→ A4 [savedQueries] 插入第二位，波间
/// 中间态收敛为终态。
enum WorkbenchRailPage {
  /// 会话页（rail 内容页既有会话列表）。
  sessions,

  /// 保存的查询页（v2 A4：共享 SavedQueryListView 196 窄列形态，本地段）。
  savedQueries,

  /// 查询历史页（v2 A3：共享 QueryHistoryListView 196 窄列形态）。
  history,
}

/// [WorkbenchRailPage] 的视觉映射（图标 / ValueKey 后缀 / tooltip 文案）。
///
/// 小枚举随组件同文件（任务书 A1 例外条款）。三图标 messageCircle /
/// bookmark / history 均已在确认 Lucide 子集内，无需子集再生成。
extension WorkbenchRailPageVisuals on WorkbenchRailPage {
  /// 页面 id（条目 ValueKey 后缀：`workbench_activity_<pageId>`）。
  String get pageId => switch (this) {
        WorkbenchRailPage.sessions => 'sessions',
        WorkbenchRailPage.savedQueries => 'savedQueries',
        WorkbenchRailPage.history => 'history',
      };

  /// 活动条图标（保存的查询 = bookmark，A4）。
  IconData get icon => switch (this) {
        WorkbenchRailPage.sessions => LucideIcons.messageCircle,
        WorkbenchRailPage.savedQueries => LucideIcons.bookmark,
        WorkbenchRailPage.history => LucideIcons.history,
      };

  /// tooltip / 页标题文案。
  String label(AppLocalizations l10n) => switch (this) {
        WorkbenchRailPage.sessions => l10n.workbenchActivitySessions,
        WorkbenchRailPage.savedQueries => l10n.workbenchActivitySavedQueries,
        WorkbenchRailPage.history => l10n.workbenchActivityHistory,
      };
}

/// AI 工作台活动条：rail 最左列 44 宽页面切换图标条（A5 起 roving 可聚焦）。
class WorkbenchActivityBar extends StatefulWidget {
  const WorkbenchActivityBar({
    super.key,
    required this.pages,
    required this.currentPage,
    required this.onPageSelected,
    this.zoneRegistry,
  });

  /// 可切换页面列表（渲染序 = 列表序）。
  final List<WorkbenchRailPage> pages;

  /// 当前选中页（选中态 = accentPurple 图标 + 左侧 2px 指示条）。
  final WorkbenchRailPage currentPage;

  /// 页面选中回调（收窄态路由接线前，调用方暂以空实现承接——A2）。
  final ValueChanged<WorkbenchRailPage> onPageSelected;

  /// F6 六区注册表（A5；null = 不注册，既有组件面测试零改动）。
  final WorkbenchFocusZoneRegistry? zoneRegistry;

  @override
  State<WorkbenchActivityBar> createState() => _WorkbenchActivityBarState();
}

class _WorkbenchActivityBarState extends State<WorkbenchActivityBar> {
  /// 每图标焦点节点（roving tabindex；A5）。键 = 页面枚举；debugLabel =
  /// `workbench_activity_<pageId>`（测试寻址面）。节点 onKeyEvent 在
  /// FocusNode 级回调（先于树内 Shortcuts/Actions），Enter 在此处理后即
  /// 消费，IconButton 的 ActivateIntent 不再重复触发。
  final Map<WorkbenchRailPage, FocusNode> _pageFocusNodes =
      <WorkbenchRailPage, FocusNode>{};

  /// F6 第一区（activityBar）聚焦入口（身份稳定闭包）。
  late final WorkbenchZoneFocusEntry _zoneEntry = _focusZoneEntry;

  @override
  void initState() {
    super.initState();
    _syncZoneRegistration();
  }

  @override
  void didUpdateWidget(covariant WorkbenchActivityBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 注册表实例变更（防御：壳重建）：旧表注销、新表重登记。
    if (!identical(oldWidget.zoneRegistry, widget.zoneRegistry)) {
      oldWidget.zoneRegistry?.unregister(
        WorkbenchFocusZone.activityBar,
        _zoneEntry,
      );
      _syncZoneRegistration();
    }
    // 页列表增减 → 清理失页焦点节点（roving 目标计算恒以 widget.pages 为准，
    // 残留节点不影响行为，清理只为 dispose 纪律与 map 卫生）。
    if (!_pagesIdentical(oldWidget.pages, widget.pages)) {
      _prunePageNodes();
    }
  }

  @override
  void dispose() {
    widget.zoneRegistry?.unregister(
      WorkbenchFocusZone.activityBar,
      _zoneEntry,
    );
    for (final node in _pageFocusNodes.values) {
      node.dispose();
    }
    _pageFocusNodes.clear();
    super.dispose();
  }

  /// 登记为 F6 第一区（挂载即注册；未注入注册表时跳过）。
  void _syncZoneRegistration() {
    final registry = widget.zoneRegistry;
    if (registry == null) return;
    registry.register(WorkbenchFocusZone.activityBar, _zoneEntry);
  }

  /// 页列表恒等（同实例或逐元素相等）。
  static bool _pagesIdentical(
    List<WorkbenchRailPage> a,
    List<WorkbenchRailPage> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 清理已移除页的焦点节点。节点延后一帧 dispose（此刻可能仍 attach 在
  /// 即将卸载的 Focus 上，立即 dispose 触发调试断言）——沿舞台 tab 条
  /// `_pruneTabResources` 同款处理。
  void _prunePageNodes() {
    final livePages = widget.pages.toSet();
    final orphanedNodes = <FocusNode>[];
    _pageFocusNodes.removeWhere((page, node) {
      if (livePages.contains(page)) return false;
      orphanedNodes.add(node);
      return true;
    });
    if (orphanedNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in orphanedNodes) {
          node.dispose();
        }
      });
    }
  }

  /// 取（或建）页面图标焦点节点。
  FocusNode _nodeFor(WorkbenchRailPage page) {
    return _pageFocusNodes.putIfAbsent(
      page,
      () => FocusNode(
        debugLabel: 'workbench_activity_${page.pageId}',
        onKeyEvent: (node, event) => _onIconKeyEvent(page, node, event),
      ),
    );
  }

  /// roving 键盘（A5；对齐舞台 tab 条 `_StageTabItem._onKeyEvent` 模式）：
  /// ↑/↓ 相邻移动、Home/End 首末、Enter 触发 onPageSelected。越界目标由
  /// [_focusPage] 钳制（不回绕，沿舞台 tab 条语义）。
  KeyEventResult _onIconKeyEvent(
    WorkbenchRailPage page,
    FocusNode node,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final index = widget.pages.indexOf(page);
    if (key == LogicalKeyboardKey.arrowUp) {
      _focusPage(index - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusPage(index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _focusPage(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _focusPage(widget.pages.length - 1);
      return KeyEventResult.handled;
    }
    final isActivate =
        key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter;
    if (isActivate) {
      widget.onPageSelected(page);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// roving 目标聚焦（越界静默忽略——宿主钳制，沿舞台 tab 条 `_focusTab`）。
  void _focusPage(int index) {
    final pages = widget.pages;
    if (index < 0 || index >= pages.length) return;
    _nodeFor(pages[index]).requestFocus();
  }

  /// F6 第一区入口：聚焦当前选中页图标（未选中页不在列表时回落首图标）。
  bool _focusZoneEntry() {
    if (widget.pages.isEmpty) return false;
    final page = widget.pages.contains(widget.currentPage)
        ? widget.currentPage
        : widget.pages.first;
    _nodeFor(page).requestFocus();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDesignSystem.workbenchRailActivityBarWidth,
      color: context.themeColors.bgSecondary,
      child: Column(
        children: [
          for (final page in widget.pages) _buildPageButton(context, page),
        ],
      ),
    );
  }

  Widget _buildPageButton(BuildContext context, WorkbenchRailPage page) {
    final l10n = AppLocalizations.of(context)!;
    final selected = page == widget.currentPage;
    return Container(
      width: AppDesignSystem.workbenchRailActivityBarWidth,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            width: 2,
            // 未选中态用活动条底色占位（NF3.4：不引 Colors.xxx，视觉与
            // transparent 等价——沿 rail 会话条目选中语法）。
            color: selected
                ? context.themeColors.accentPurple
                : context.themeColors.bgSecondary,
          ),
        ),
      ),
      child: IconButton(
        key: ValueKey('workbench_activity_${page.pageId}'),
        focusNode: _nodeFor(page),
        icon: Icon(page.icon, size: 16),
        color: selected
            ? context.themeColors.accentPurple
            : context.themeColors.textMuted,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        tooltip: page.label(l10n),
        onPressed: () => widget.onPageSelected(page),
      ),
    );
  }
}
