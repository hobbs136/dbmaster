//! AI 工作台产物条（T25，ui 规格 design-ai-agent-ui.md §6 面六）。
//!
//! 判定（§6.3）：产物项 ≡ 舞台 tab——本组件是
//! [WorkbenchStageController.pinnedTabs] 的投影，**不持有第二份数据**；
//! 点击项 = 开舞台并激活对应 tab、× / Delete = 取消钉住（tab 保留）、
//! tab 关闭 = 项同步消失。左端常驻舞台开合开关（收起舞台后条是唯一入口）。
//!
//! 数值逐字 ui 规格 §6.1：条高 32（`artifactStripHeight`，bgSecondary +
//! 顶部 1px divider，shell 全宽常驻）；开关 [panelRight/panelRightClose 14 +
//! 11px textSecondary 标签，tooltip 同步]；1px 竖线分隔（高 16 居中 + space2）；
//! 产物项 [类型图标 12 textMuted + 标签 11px 上限 160 ellipsis + tooltip +
//! × 12 textMuted]，项高 24 + padding h space2 + radiusSm，间距 4；
//! 激活项 bgTertiary + 标签 textPrimary（200ms 过渡）；溢出横向滚动不换行、
//! 新项自动滚入视口；空态 11px textMuted 常驻一行；键盘 roving（←/→）
//! + Enter 开舞台激活 + Delete/Backspace 取消钉住，× 独立可聚焦。
//!
//! 动效（§6.2 明示）：结构增删零动效（不引入 AnimatedList），仅激活底色
//! 200ms 过渡。不持久化（shell 级内存态）。类型图标映射与舞台 tab 同一套
//! （§6.1）；舞台侧实现为文件私有，此处按同一映射表落（不跨文件扩其 API）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import 'workbench_stage.dart';

/// 产物条（§6）：舞台 tab pinned 子集投影 + 舞台开合开关。
///
/// 挂载归 T27 shell（底部全宽常驻条）；本组件自身不持任何状态，
/// 全部经 [controller] 读写（§6.3 单一事实源）。
class WorkbenchArtifactStrip extends StatefulWidget {
  const WorkbenchArtifactStrip({super.key, required this.controller});

  /// 舞台状态宿主（与 [WorkbenchStage] 共享同一实例；T27 shell 创建注入，
  /// 测试自建）。
  final WorkbenchStageController controller;

  /// 条容器（§6.4-1 高度/常驻探针）。
  static const Key stripKey = ValueKey('workbench_artifact_strip');

  /// 舞台开合开关。
  static const Key toggleKey = ValueKey('workbench_artifact_toggle');

  /// 空态文案。
  static const Key emptyKey = ValueKey('workbench_artifact_empty');

  /// 单个产物项（几何/顺序探针）。
  static Key itemKey(String tabId) =>
      ValueKey('workbench_artifact_item_$tabId');

  /// 单个产物项的取消钉住钮（×）。
  static Key itemUnpinKey(String tabId) =>
      ValueKey('workbench_artifact_unpin_$tabId');

  @override
  State<WorkbenchArtifactStrip> createState() => _WorkbenchArtifactStripState();
}

class _WorkbenchArtifactStripState extends State<WorkbenchArtifactStrip> {
  final ScrollController _stripScroll = ScrollController();

  /// 每 pinned 项焦点节点（roving tabindex；§0.4 / §6.4-7）。
  final Map<String, FocusNode> _itemFocusNodes = {};

  /// 每 pinned 项定位键（自动滚入视口 + 测试几何探针）。
  final Map<String, GlobalKey> _itemKeys = {};

  /// 上一次 pinned 数量（识别「新增」触发自动滚入；移除不滚）。
  int _lastPinnedCount = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _lastPinnedCount = widget.controller.pinnedTabs.length;
  }

  @override
  void didUpdateWidget(covariant WorkbenchArtifactStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastPinnedCount = widget.controller.pinnedTabs.length;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _stripScroll.dispose();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    _itemFocusNodes.clear();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _pruneItemResources();
    final count = widget.controller.pinnedTabs.length;
    final appended = count > _lastPinnedCount;
    _lastPinnedCount = count;
    setState(() {});
    // 新项自动滚入视口（§6.1 溢出规则）——帧后定位（本帧树未建）；
    // 未溢出 / 已在视口内时 ensureVisible 不产生动画（§6.4-6 零动效前提）。
    if (appended && count > 0) {
      final newestId = widget.controller.pinnedTabs.last.id;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureItemVisible(newestId),
      );
    }
  }

  /// 清理已消失项（取消钉住 / tab 关闭）的焦点节点与键。焦点节点延后一帧
  /// dispose（此刻可能仍 attach 在即将卸载的 Focus 上，立即 dispose 触发
  /// 调试断言）——沿舞台 tab 条同款处理。
  void _pruneItemResources() {
    final liveIds = widget.controller.pinnedTabs.map((t) => t.id).toSet();
    final orphanedNodes = <FocusNode>[];
    _itemFocusNodes.removeWhere((id, node) {
      if (liveIds.contains(id)) return false;
      orphanedNodes.add(node);
      return true;
    });
    _itemKeys.removeWhere((id, _) => !liveIds.contains(id));
    if (orphanedNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in orphanedNodes) {
          node.dispose();
        }
      });
    }
  }

  void _ensureItemVisible(String tabId) {
    if (!mounted) return;
    final ctx = _itemKeys[tabId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppDesignSystem.durationNormal,
      curve: AppDesignSystem.curveDefault,
      alignment: 1.0,
    );
  }

  // ── 项动作（§6.3 行为表）────────────────────────────────────────────

  /// 点项 / Enter：舞台收起时重开舞台并激活该 tab；已展开时仅激活。
  void _activateFromStrip(WorkbenchStageTab tab) {
    if (!widget.controller.stageVisible) {
      widget.controller.setStageVisible(true);
    }
    final index = widget.controller.tabs.indexWhere((t) => t.id == tab.id);
    if (index >= 0) widget.controller.activateTab(index);
  }

  /// × / Delete：仅取消钉住——tab 保留在舞台 tab 条（§6.3）。
  void _unpin(WorkbenchStageTab tab) {
    final index = widget.controller.tabs.indexWhere((t) => t.id == tab.id);
    if (index >= 0) widget.controller.setPinned(index, false);
  }

  void _focusItem(int pinnedIndex) {
    final pinned = widget.controller.pinnedTabs;
    if (pinnedIndex < 0 || pinnedIndex >= pinned.length) return;
    _itemFocusNodes[pinned[pinnedIndex].id]?.requestFocus();
    _ensureItemVisible(pinned[pinnedIndex].id);
  }

  // ── 构建 ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      key: WorkbenchArtifactStrip.stripKey,
      height: AppDesignSystem.artifactStripHeight,
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        border: Border(
          top: BorderSide(
            color: colors.dividerColor,
            width: AppDesignSystem.tabBarDividerHeight,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildToggle(context),
          _buildSeparator(context),
          Expanded(child: _buildItems(context)),
        ],
      ),
    );
  }

  /// 左端舞台开合开关（§6.1）：收起 = panelRight + 「舞台」、展开 =
  /// panelRightClose + 「收起舞台」；icon 14 + 11px textSecondary 标签，
  /// tooltip 同步；内容自适应宽 + padding h space2_5。
  Widget _buildToggle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final visible = widget.controller.stageVisible;
    final label = visible ? l10n.agentStageCollapse : l10n.agentStageToggle;
    return InkWell(
      key: WorkbenchArtifactStrip.toggleKey,
      onTap: () => widget.controller.setStageVisible(!visible),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2_5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                visible ? LucideIcons.panelRightClose : LucideIcons.panelRight,
                size: 14,
                color: colors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 左端分隔：1px 竖线（dividerColor，高 16 居中）+ 两侧 space2（§6.1）。
  Widget _buildSeparator(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      child: Container(width: 1, height: 16, color: colors.dividerColor),
    );
  }

  /// pinned 子集投影（时间序 = 舞台 tab 序，新项追加在右）；空态常驻一行。
  /// 横向滚动不换行（条高恒 32）；非懒构建——roving 键盘要把焦点移到视口外
  /// 项（焦点节点/定位键必须在树上），pinned 数量上界 = 用户钉入量级。
  Widget _buildItems(BuildContext context) {
    final pinned = widget.controller.pinnedTabs;
    if (pinned.isEmpty) return _buildEmpty(context);
    return SingleChildScrollView(
      controller: _stripScroll,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < pinned.length; i++) ...[
            if (i > 0) const SizedBox(width: AppDesignSystem.space1),
            _buildItem(context, pinned[i], i),
          ],
        ],
      ),
    );
  }

  /// 空态（§6.1）：开关右侧一行 11px textMuted「暂无钉住的产物」；
  /// 条不隐藏（常驻保证舞台入口恒在 + 布局稳定）。
  Widget _buildEmpty(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        l10n.agentArtifactEmpty,
        key: WorkbenchArtifactStrip.emptyKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          color: colors.textMuted,
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    WorkbenchStageTab tab,
    int pinnedIndex,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final node = _itemFocusNodes.putIfAbsent(
      tab.id,
      () => FocusNode(debugLabel: 'artifact_item_${tab.id}'),
    );
    final locatedKey = _itemKeys.putIfAbsent(
      tab.id,
      () => GlobalKey(debugLabel: tab.id),
    );
    return _ArtifactItem(
      key: locatedKey,
      itemKey: WorkbenchArtifactStrip.itemKey(tab.id),
      unpinKey: WorkbenchArtifactStrip.itemUnpinKey(tab.id),
      tab: tab,
      isActive: widget.controller.activeTab?.id == tab.id,
      focusNode: node,
      pinnedIndex: pinnedIndex,
      pinnedCount: widget.controller.pinnedTabs.length,
      displayLabel: tab.title ?? _kindLabel(l10n, tab.kind),
      onActivate: () {
        node.requestFocus();
        _activateFromStrip(tab);
      },
      onUnpin: () => _unpin(tab),
      onMoveFocus: _focusItem,
    );
  }

  String _kindLabel(AppLocalizations l10n, WorkbenchStageTabKind kind) {
    switch (kind) {
      case WorkbenchStageTabKind.grid:
        return l10n.agentStageTabGrid;
      case WorkbenchStageTabKind.structure:
        return l10n.agentStageTabStructure;
      case WorkbenchStageTabKind.editor:
        return l10n.agentStageTabEditor;
      case WorkbenchStageTabKind.chart:
        return l10n.agentStageTabChart;
    }
  }
}

/// 产物项（§6.1）：[类型图标 12 textMuted] + 6 + [标签 11px 上限 160
/// ellipsis + tooltip] + 6 + [× 12 textMuted]；项高 24（工作台单行行高）+
/// padding h space2 + radiusSm；激活项 bgTertiary + 标签 textPrimary，
/// 底色 200ms 过渡（AnimatedContainer 只过渡颜色，插入/移除是子列表变更，
/// 零动效——§6.2）。
///
/// 键盘（§6.1）：项 roving（←/→/Home/End 移动）、Enter 开舞台并激活、
/// Delete/Backspace 取消钉住；× 独立可聚焦（InkWell 自带 Enter/Space 激活），
/// 组内顺序 = 项 → ×（OrderedTraversalPolicy 显式定序，保证 Tab 可达 ×）。
class _ArtifactItem extends StatelessWidget {
  const _ArtifactItem({
    super.key,
    required this.itemKey,
    required this.unpinKey,
    required this.tab,
    required this.isActive,
    required this.focusNode,
    required this.pinnedIndex,
    required this.pinnedCount,
    required this.displayLabel,
    required this.onActivate,
    required this.onUnpin,
    required this.onMoveFocus,
  });

  final Key itemKey;
  final Key unpinKey;
  final WorkbenchStageTab tab;
  final bool isActive;
  final FocusNode focusNode;

  /// 本项在 pinned 子集中的下标与子集总数（roving 键盘目标计算）。
  final int pinnedIndex;
  final int pinnedCount;
  final String displayLabel;
  final VoidCallback onActivate;
  final VoidCallback onUnpin;
  final void Function(int targetIndex) onMoveFocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return FocusTraversalGroup(
      policy: _itemTraversalPolicy,
      child: FocusTraversalOrder(
        // 项序 0 必须在 Focus **上方**（焦点节点沿树向上查 order 继承）。
        order: const NumericFocusOrder(0),
        child: Focus(
          focusNode: focusNode,
          onKeyEvent: _onKeyEvent,
          child: GestureDetector(
            onTap: onActivate,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AnimatedContainer(
                key: itemKey,
                duration: AppDesignSystem.durationNormal,
                curve: AppDesignSystem.curveDefault,
                height: AppDesignSystem.workbenchDenseRowHeight,
                constraints: const BoxConstraints(
                  maxWidth: AppDesignSystem.artifactStripItemMaxWidth,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                ),
                decoration: BoxDecoration(
                  color: isActive ? colors.bgTertiary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _kindIcon(tab.kind),
                      size: 12,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Flexible(
                      child: Tooltip(
                        // §0.4：tooltip 承载被截断的全文，hover 与键盘聚焦触发。
                        message: displayLabel,
                        child: Text(
                          displayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppDesignSystem.fontSizeXs,
                            color: isActive
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(1),
                      child: _buildUnpinButton(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 取消钉住钮（§6.1）：× 12 textMuted；tooltip「取消钉住（Delete）」；
  /// 独立可聚焦（InkWell 聚焦后 Enter/Space = 取消钉住）。
  Widget _buildUnpinButton(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Tooltip(
      message: l10n.agentArtifactUnpinHint,
      child: InkWell(
        key: unpinKey,
        onTap: onUnpin,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space0_5,
            vertical: AppDesignSystem.space1,
          ),
          child: Icon(LucideIcons.x, size: 12, color: colors.textMuted),
        ),
      ),
    );
  }

  /// roving 键盘（§0.4 / §6.4-7）：←/→ 相邻移动、Home/End 首末、Enter
  /// 开舞台并激活、Delete/Backspace 取消钉住。越界目标由宿主钳制。
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      onMoveFocus(pinnedIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      onMoveFocus(pinnedIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      onMoveFocus(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      onMoveFocus(pinnedCount - 1);
      return KeyEventResult.handled;
    }
    final isActivate =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (isActivate && node.hasPrimaryFocus) {
      onActivate();
      return KeyEventResult.handled;
    }
    final isUnpin =
        key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace;
    if (isUnpin && node.hasPrimaryFocus) {
      onUnpin();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// 产物项组内遍历策略（项 → ×；OrderedTraversalPolicy 无 const 构造）。
final OrderedTraversalPolicy _itemTraversalPolicy = OrderedTraversalPolicy();

/// 类型图标映射（§6.1：与舞台 tab 同一套）。
IconData _kindIcon(WorkbenchStageTabKind kind) {
  switch (kind) {
    case WorkbenchStageTabKind.grid:
      return LucideIcons.table;
    case WorkbenchStageTabKind.structure:
      return LucideIcons.listTree;
    case WorkbenchStageTabKind.editor:
      return LucideIcons.code;
    case WorkbenchStageTabKind.chart:
      return LucideIcons.chartColumn;
  }
}
