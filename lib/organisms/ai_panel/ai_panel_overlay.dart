// ============================================================================
// DbMaster AI Panel Overlay — AI 面板全屏浮层
// ============================================================================
//
// 支持：
//   - 拖拽移动（工具栏）
//   - 任意拖拽缩放（8 个方向手柄：4 边 + 4 角）
//   - 自定义尺寸持久化
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../providers/layout_preferences_provider.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import 'ai_panel_widget.dart';

/// 调整方向
enum _ResizeEdge {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

class AiPanelOverlay extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onToggleDock;

  const AiPanelOverlay({
    super.key,
    required this.onClose,
    required this.onToggleDock,
  });

  @override
  State<AiPanelOverlay> createState() => AiPanelOverlayState();
}

class AiPanelOverlayState extends State<AiPanelOverlay> {
  bool _isHovered = false;
  bool _isResizing = false;

  /// 面板几何（视口绝对坐标，首次布局时懒初始化）。
  ///
  /// 唯一事实源：所有手势与可视区变化都以它为基准做归一化写回，
  /// 渲染态不得与之分叉。
  Rect? _rect;

  /// 存档恢复是否已应用（防重）。
  bool _restoreApplied = false;

  /// 用户是否已在本次挂载中改变过几何（竞态窗口内不覆盖用户操作）
  bool _userModified = false;

  /// 当前渲染尺寸（测试用）
  double _renderedW = 0;
  double _renderedH = 0;

  /// 当前渲染位置（测试用）
  double _renderedLeft = 0;
  double _renderedTop = 0;

  LayoutPreferencesProvider? _prefs;

  static const double _padding = 48.0;
  static const double _minW = 400.0;
  static const double _minH = 300.0;
  static const double _handleSize = 10.0;
  static const double _cornerSize = 14.0;

  /// 默认尺寸占视口比例（首次打开/无自定义时的观感）
  static const double _defaultRatio = 0.65;

  /// 当前渲染宽度（测试用）
  double get debugRenderedWidth => _renderedW;

  /// 当前渲染高度（测试用）
  double get debugRenderedHeight => _renderedH;

  /// 当前渲染左缘（测试用）
  double get debugRenderedLeft => _renderedLeft;

  /// 当前渲染上缘（测试用）
  double get debugRenderedTop => _renderedTop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = context.read<LayoutPreferencesProvider>();
    if (!identical(_prefs, prefs)) {
      _prefs?.removeListener(_onPrefsChanged);
      _prefs = prefs;
      _prefs?.addListener(_onPrefsChanged);
    }
  }

  /// 存档加载完成后恢复一次（load() 为 fire-and-forget，存在竞态——D5）。
  void _onPrefsChanged() {
    if (_restoreApplied) return;
    final prefs = _prefs;
    if (prefs == null || !prefs.isLoaded) return;
    _restoreApplied = true;
    // 竞态窗口内用户已动手 → 以用户几何为准，不覆盖
    if (_userModified || !mounted) return;
    setState(() {
      _rect = null; // 触发 build 懒初始化按已加载存档重建
    });
  }

  @override
  void dispose() {
    _prefs?.removeListener(_onPrefsChanged);
    super.dispose();
  }

  /// 默认/恢复几何（D5/D6）：
  /// full（位置+尺寸存档齐全）→ 原位恢复（clamp 由调用方 _normalized 完成）；
  /// legacy（仅尺寸存档）→ 按存档尺寸居中（含 9.6px 上移）；
  /// fresh（无存档）→ 默认比例居中。
  Rect _defaultRect(double availW, double availH) {
    final savedW = _prefs?.overlayWidth ?? 0.0;
    final savedH = _prefs?.overlayHeight ?? 0.0;
    final hasSavedSize = savedW >= _minW && savedH >= _minH;
    final savedLeft = _prefs?.overlayLeft;
    final savedTop = _prefs?.overlayTop;

    if (hasSavedSize && savedLeft != null && savedTop != null) {
      return Rect.fromLTWH(savedLeft, savedTop, savedW, savedH);
    }

    final w = hasSavedSize ? savedW : math.max(_minW, availW * _defaultRatio);
    final h = hasSavedSize
        ? savedH
        : math.max(_minH, (availH - _padding * 1.5) * _defaultRatio);
    return Rect.fromLTWH(
      (availW - w) / 2,
      (availH - h) / 2 - _padding * 0.2,
      w,
      h,
    );
  }

  /// 归一化到可视区内（D2 状态写回 + D3 位置感知上限）：
  /// 先约束尺寸（不小于最小尺寸、不超过可视区），再约束位置。
  /// 可视区小于最小尺寸时保最小尺寸（I2 优先于 I3 的退化情形）。
  Rect _normalized(Rect r, double availW, double availH) {
    final w = r.width.clamp(_minW, math.max(_minW, availW)).toDouble();
    final h = r.height.clamp(_minH, math.max(_minH, availH)).toDouble();
    final maxLeft = math.max(0.0, availW - w);
    final maxTop = math.max(0.0, availH - h);
    return Rect.fromLTWH(
      r.left.clamp(0.0, maxLeft).toDouble(),
      r.top.clamp(0.0, maxTop).toDouble(),
      w,
      h,
    );
  }

  /// 手势结束时持久化 clamp 后的实际几何（位置+尺寸，单次 notify）。
  void _persistGeometry() {
    final r = _rect;
    final prefs = _prefs;
    if (r == null || prefs == null) return;
    unawaited(
      prefs.setOverlayRect(
        width: r.width,
        height: r.height,
        left: r.left,
        top: r.top,
      ),
    );
  }

  void _applyResize(
    _ResizeEdge edge,
    double dx,
    double dy,
    double maxW,
    double maxH,
  ) {
    final r = _rect;
    if (r == null) return;
    _userModified = true;

    double left = r.left;
    double top = r.top;
    double width = r.width;
    double height = r.height;

    // 每个手柄只写自己那条边；对边以拖拽前坐标为锚，严格不动（D1）。
    // 最小尺寸触限时先 clamp 尺寸、再以拖拽前对边反推 origin。
    switch (edge) {
      case _ResizeEdge.left:
      case _ResizeEdge.topLeft:
      case _ResizeEdge.bottomLeft:
        final right = r.right;
        width = (width - dx).clamp(_minW, right).toDouble();
        left = right - width;
      case _ResizeEdge.right:
      case _ResizeEdge.topRight:
      case _ResizeEdge.bottomRight:
        width = (width + dx).clamp(_minW, maxW - r.left).toDouble();
      case _ResizeEdge.top:
      case _ResizeEdge.bottom:
        break;
    }

    switch (edge) {
      case _ResizeEdge.top:
      case _ResizeEdge.topLeft:
      case _ResizeEdge.topRight:
        final bottom = r.bottom;
        height = (height - dy).clamp(_minH, bottom).toDouble();
        top = bottom - height;
      case _ResizeEdge.bottom:
      case _ResizeEdge.bottomLeft:
      case _ResizeEdge.bottomRight:
        height = (height + dy).clamp(_minH, maxH - r.top).toDouble();
      case _ResizeEdge.left:
      case _ResizeEdge.right:
        break;
    }

    setState(() {
      _rect = _normalized(Rect.fromLTWH(left, top, width, height), maxW, maxH);
    });
  }

  MouseCursor _cursorForEdge(_ResizeEdge edge) {
    return switch (edge) {
      _ResizeEdge.topLeft => SystemMouseCursors.resizeUpLeft,
      _ResizeEdge.top => SystemMouseCursors.resizeUp,
      _ResizeEdge.topRight => SystemMouseCursors.resizeUpRight,
      _ResizeEdge.right => SystemMouseCursors.resizeRight,
      _ResizeEdge.bottomRight => SystemMouseCursors.resizeDownRight,
      _ResizeEdge.bottom => SystemMouseCursors.resizeDown,
      _ResizeEdge.bottomLeft => SystemMouseCursors.resizeDownLeft,
      _ResizeEdge.left => SystemMouseCursors.resizeLeft,
    };
  }

  /// 构建四周 + 四角的手柄
  List<Widget> _buildResizeHandles(double maxW, double maxH) {
    final handleColor = context.themeColors.accentBlue.withValues(
      alpha: _isHovered || _isResizing ? 0.6 : 0.0,
    );
    final hoverColor = context.themeColors.accentBlue.withValues(alpha: 0.35);

    Widget handle({
      required _ResizeEdge edge,
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
    }) {
      return Positioned(
        key: ValueKey('ai_overlay_resize_${edge.name}'),
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: _cursorForEdge(edge),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => setState(() => _isResizing = true),
            onPanUpdate: (d) =>
                _applyResize(edge, d.delta.dx, d.delta.dy, maxW, maxH),
            onPanEnd: (_) {
              setState(() => _isResizing = false);
              _persistGeometry();
            },
            onPanCancel: () {
              setState(() => _isResizing = false);
              _persistGeometry();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              color: handleColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isHorizontal =
                      constraints.maxWidth > constraints.maxHeight;
                  return Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: isHorizontal ? constraints.maxWidth - 4 : 2,
                      height: isHorizontal ? 2 : constraints.maxHeight - 4,
                      decoration: BoxDecoration(
                        color: hoverColor,
                        borderRadius: BorderRadius.circular(
                          1,
                        ), // 特例：拖拽手柄精美元素，不入标尺
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    return [
      // 四边
      handle(
        edge: _ResizeEdge.left,
        left: 0,
        top: _cornerSize,
        bottom: _cornerSize,
        width: _handleSize,
      ),
      handle(
        edge: _ResizeEdge.right,
        left: null,
        top: _cornerSize,
        right: 0,
        bottom: _cornerSize,
        width: _handleSize,
      ),
      handle(
        edge: _ResizeEdge.top,
        left: _cornerSize,
        top: 0,
        right: _cornerSize,
        height: _handleSize,
      ),
      handle(
        edge: _ResizeEdge.bottom,
        left: _cornerSize,
        top: null,
        right: _cornerSize,
        bottom: 0,
        height: _handleSize,
      ),
      // 四角
      handle(
        edge: _ResizeEdge.topLeft,
        left: 0,
        top: 0,
        width: _cornerSize,
        height: _cornerSize,
      ),
      handle(
        edge: _ResizeEdge.topRight,
        left: null,
        top: 0,
        right: 0,
        width: _cornerSize,
        height: _cornerSize,
      ),
      handle(
        edge: _ResizeEdge.bottomLeft,
        left: 0,
        top: null,
        bottom: 0,
        width: _cornerSize,
        height: _cornerSize,
      ),
      handle(
        edge: _ResizeEdge.bottomRight,
        left: null,
        top: null,
        right: 0,
        bottom: 0,
        width: _cornerSize,
        height: _cornerSize,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.themeColors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;

        // 懒初始化 + 归一化写回（纯字段赋值，禁 setState——II.12/D2）。
        // 可视区变化（窗口缩放、执行中心面板开合）后 stored rect 即刻
        // 收敛回可视区，后续手势永远以真实几何为基准。
        var rect = _rect ?? _defaultRect(availW, availH);
        rect = _normalized(rect, availW, availH);
        _rect = rect;
        // 存档已加载时视为恢复完成（几何已是存档/默认计算结果）
        if (_prefs?.isLoaded ?? false) _restoreApplied = true;
        _renderedW = rect.width;
        _renderedH = rect.height;
        _renderedLeft = rect.left;
        _renderedTop = rect.top;

        return Stack(
          children: [
            // 半透明遮罩（点击关闭）
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(color: Colors.black.withValues(alpha: 0.15)),
              ),
            ),
            // 浮层面板
            Positioned(
              key: const ValueKey('ai_overlay_panel'),
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: MouseRegion(
                onEnter: (_) => setState(() => _isHovered = true),
                onExit: (_) => setState(() => _isHovered = false),
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: _isResizing
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _isHovered ? 0.2 : 0.15,
                            ),
                            blurRadius: _isHovered ? 40 : 30,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _isHovered ? 0.08 : 0.05,
                            ),
                            blurRadius: _isHovered ? 15 : 10,
                            spreadRadius: -5,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          decoration: BoxDecoration(
                            color: themeColors.bgSecondary.withValues(
                              alpha: 0.96,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isHovered
                                  ? themeColors.borderLight
                                  : themeColors.borderSubtle,
                            ),
                          ),
                          child: Column(
                            children: [
                              _OverlayToolbar(
                                onToggleDock: widget.onToggleDock,
                                onClose: widget.onClose,
                                onDragUpdate: (dx, dy) => setState(() {
                                  final r = _rect;
                                  if (r == null) return;
                                  _userModified = true;
                                  // clamp-at-input：贴边拖拽无橡皮筋残留（I7）
                                  _rect = _normalized(
                                    r.shift(Offset(dx, dy)),
                                    availW,
                                    availH,
                                  );
                                }),
                                onDragEnd: _persistGeometry,
                              ),
                              const Expanded(
                                child: AiPanelWidget(
                                  isFullscreen: true,
                                  isOverlay: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ..._buildResizeHandles(availW, availH),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ============================================================================
// _OverlayToolbar — 顶部工具栏
// ============================================================================

class _OverlayToolbar extends StatelessWidget {
  final VoidCallback onToggleDock;
  final VoidCallback onClose;
  final void Function(double dx, double dy) onDragUpdate;

  /// 拖拽结束/取消（用于持久化移动后的位置）
  final VoidCallback onDragEnd;

  const _OverlayToolbar({
    required this.onToggleDock,
    required this.onClose,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final themeColors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: (d) => onDragUpdate(d.delta.dx, d.delta.dy),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: () => onDragEnd(),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
        decoration: BoxDecoration(
          color: themeColors.bgSecondary.withValues(alpha: 0.6),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.wandSparkles,
              size: 18,
              color: themeColors.accentPurple,
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              AppLocalizations.of(context)!.aiAssistant,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: themeColors.textPrimary,
              ),
            ),
            const Spacer(),
            // 快捷键帮助
            _ToolbarButton(
              icon: LucideIcons.keyboard,
              tooltip:
                  '${AppLocalizations.of(context)!.shortcutShortcutHelp} (Ctrl+/)',
              onPressed: () => _showAiShortcutsDialog(context),
            ),
            const SizedBox(width: AppDesignSystem.space1),
            // 返回侧边栏
            _ToolbarButton(
              icon: LucideIcons.panelBottom,
              tooltip: l10n.aiPanelOverlaySwitchToSidebar,
              onPressed: onToggleDock,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            // 关闭
            _ToolbarButton(
              icon: LucideIcons.x,
              tooltip: AppLocalizations.of(context)!.commonClose,
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// _ToolbarButton — 工具栏图标按钮
// ============================================================================

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            color: Colors.white.withValues(alpha: 0.05),
          ),
          child: Icon(icon, size: 18, color: context.themeColors.textMuted),
        ),
      ),
    );
  }
}

// ============================================================================
// AI 快捷键帮助对话框
// ============================================================================

void _showAiShortcutsDialog(BuildContext context) {
  final themeColors = context.themeColors;
  final l10n = AppLocalizations.of(context)!;
  final isMac = Platform.isMacOS;
  final mod = isMac ? '⌘' : 'Ctrl';

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.keyboard, size: 20, color: themeColors.accentPurple),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            AppLocalizations.of(context)!.aiPanelOverlay_aiPanelShortcuts,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.w600,
              color: themeColors.textPrimary,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShortcutItem(
              shortcut: '$mod + Shift + A',
              description: l10n.commandDescToggleAiPanel,
            ),
            _ShortcutItem(
              shortcut: '$mod + Shift + F',
              description: l10n.aiPanelOverlayToggleMode,
            ),
            _ShortcutItem(
              shortcut: l10n.aiPanelOverlayDragToolbar,
              description: l10n.aiPanelOverlayMoveOverlay,
            ),
            _ShortcutItem(
              shortcut: l10n.aiPanelOverlayDragEdges,
              description: l10n.aiPanelOverlayResizeOverlay,
            ),
            _ShortcutItem(
              shortcut: l10n.aiPanelOverlayClickMask,
              description: l10n.aiPanelOverlayCloseOverlay,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.commonClose,
            style: TextStyle(color: themeColors.accentPurple),
          ),
        ),
      ],
    ),
  );
}

class _ShortcutItem extends StatelessWidget {
  final String shortcut;
  final String description;
  const _ShortcutItem({required this.shortcut, required this.description});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space0_5,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm / 2),
            ),
            child: Text(
              shortcut,
              style: TextStyle(
                fontSize: 12,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: context.themeColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: context.themeColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
