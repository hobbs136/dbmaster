// ============================================================================
// DbMaster Resizer Widgets — Unified AppResizer
// ============================================================================
///
/// 合并了三个重复的 Resizer 组件（Sidebar / EditorResults / AiPanel）
/// 为一个 `AppResizer`，通过参数控制方向、光标、尺寸。
///
/// 用法：
/// ```dart
/// // 垂直分隔条（侧边栏 / AI 面板）
/// AppResizer(
///   isResizing: _isResizingSidebar,
///   onResizeStart: ..., onResizeUpdate: ..., onResizeEnd: ...,
///   grabBarSize: const Size(1, 24),  // 默认
/// )
///
/// // 水平分隔条（上下分栏）
/// AppResizer(
///   direction: Axis.vertical,
///   ...,
///   grabBarSize: const Size(40, 3),
/// )
/// ```
// ============================================================================
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/design_system.dart';
import '../theme/app_colors.dart';

// ============================================================================
// AppResizer — 统一的拖拽分隔条
// ============================================================================

class AppResizer extends StatefulWidget {
  /// 拖拽方向
  ///
  /// - `Axis.horizontal`（默认）：沿 X 轴拖拽，光标 `resizeColumn`，SizedBox 宽 12
  /// - `Axis.vertical`：沿 Y 轴拖拽，光标 `resizeRow`，SizedBox 高 12
  final Axis direction;

  /// 是否正在拖拽中（由父组件传入）
  final bool isResizing;

  final VoidCallback onResizeStart;
  final ValueChanged<double> onResizeUpdate;
  final VoidCallback onResizeEnd;

  /// grab bar 尺寸（居中绘制的小装饰线）
  ///
  /// - 垂直分隔条（侧边栏 / AI）：`Size(1, 24)` — 细竖线
  /// - 水平分隔条（上下分栏）：`Size(40, 3)` — 宽横线
  /// - 垂直分隔条（左右分栏）：`Size(3, 40)` — 粗竖线
  final Size grabBarSize;

  /// SizedBox 的宽度（默认 12，仅 direction=horizontal 时生效）
  final double width;

  /// SizedBox 的高度（默认 12，仅 direction=vertical 时生效）
  final double height;

  /// 是否让交互区填充交叉轴（用于 editor/results 的分隔条占满整行/列；
  /// false 时交互区保持 12px 交叉轴区段，静止态通栏线不受影响）
  final bool fillCrossAxis;

  /// C21（原型 editor-results-split）：抓取手柄形态——true 时 grab bar
  /// 渲染为居中 grip chip（bgQuaternary 圆角块 + grip 图标），替代装饰线。
  final bool gripHandle;

  /// C21：静止态通栏线的粗细（默认 1px；editor/results 分隔条 = 4px bar）。
  final double restLineThickness;

  /// C21：静止态通栏线用 borderLight（可辨识边框）而非 divider（默认 false）。
  final bool restLineStrong;

  const AppResizer({
    super.key,
    this.direction = Axis.horizontal,
    required this.isResizing,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    this.grabBarSize = const Size(1, 24),
    this.width = 12.0,
    this.height = 12.0,
    this.fillCrossAxis = false,
    this.gripHandle = false,
    this.restLineThickness = 1.0,
    this.restLineStrong = false,
  });

  @override
  State<AppResizer> createState() => _AppResizerState();
}

class _AppResizerState extends State<AppResizer> {
  bool _isHovered = false;
  double _accumulatedDelta = 0.0;
  static const double _sensitivityFactor = 0.8;
  static const double _threshold = 1.0;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.direction == Axis.horizontal;

    // P0-2b：静止态 1px 线沿交叉轴通栏——外层 SizedBox 交叉轴充满仅用于画线；
    // 命中区/hover/grab bar 仍收敛在居中的原尺寸交互区内，布局尺寸约束不变
    return SizedBox(
      width: isHorizontal ? widget.width : double.infinity,
      height: isHorizontal ? double.infinity : widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 通栏线：仅绘制，不参与命中
          Center(child: _buildRestLine(context, isHorizontal)),
          Center(
            child: SizedBox(
              width: _getSize(isHorizontal, widget.width, widget.fillCrossAxis),
              height: _getSize(
                !isHorizontal,
                widget.height,
                widget.fillCrossAxis,
              ),
              child: _buildInteractionZone(isHorizontal),
            ),
          ),
        ],
      ),
    );
  }

  /// 交互区：光标/hover 底色/拖拽手势/grab bar，尺寸与原布局完全一致
  Widget _buildInteractionZone(bool isHorizontal) {
    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) {
          _accumulatedDelta = 0.0;
          widget.onResizeStart();
        },
        onPanUpdate: (details) {
          final delta = isHorizontal ? details.delta.dx : details.delta.dy;
          _accumulatedDelta += delta * _sensitivityFactor;
          if (_accumulatedDelta.abs() >= _threshold) {
            widget.onResizeUpdate(_accumulatedDelta);
            _accumulatedDelta = 0.0;
          }
        },
        onPanEnd: (_) {
          if (_accumulatedDelta.abs() > 0) {
            widget.onResizeUpdate(_accumulatedDelta);
          }
          widget.onResizeEnd();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _getHandleColor(),
          // 保留 Stack 的 hardEdge 裁剪语义：grab bar（如 1x24）超出
          // 交互区交叉轴的部分按原行为裁掉，视觉与重构前一致
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: widget.gripHandle
                    ? _buildGripChip()
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: widget.grabBarSize.width,
                        height: widget.grabBarSize.height,
                        decoration: BoxDecoration(
                          color: _getBarColor(),
                          borderRadius: BorderRadius.circular(
                            AppDesignSystem.radiusSm,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 静止态通栏线：垂直分隔条画 1px 宽竖线，水平分隔条画 1px 高横线；
  /// 颜色引用全局 divider token（P0-1 收敛，随亮/暗主题分发）
  Widget _buildRestLine(BuildContext context, bool isHorizontal) {
    return Container(
      width: isHorizontal ? widget.restLineThickness : double.infinity,
      height: isHorizontal ? double.infinity : widget.restLineThickness,
      color: widget.restLineStrong
          ? context.themeColors.borderLight
          : context.themeColors.dividerColor,
    );
  }

  /// C21 grip 手柄 chip（原型 splitter handle）：bgQuaternary 圆角块 +
  /// grip 图标；hover/拖拽 accent 化。沿分隔条方向 28px、垂直方向撑满
  /// 12px 交互区（上下分栏 = 宽 28 满高；左右分栏 = 满宽 高 28）。
  Widget _buildGripChip() {
    final isResizing = widget.isResizing;
    final isVerticalBar = widget.direction == Axis.horizontal;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: isVerticalBar ? double.infinity : 28,
      height: isVerticalBar ? 28 : double.infinity,
      decoration: BoxDecoration(
        color: isResizing
            ? context.themeColors.accentSubtle
            : context.themeColors.bgQuaternary,
        border: Border.all(
          color: isResizing
              ? context.themeColors.accentBlue
              : (_isHovered
                    ? context.themeColors.accentBlue.withValues(alpha: 0.5)
                    : context.themeColors.borderLight),
        ),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Center(
        child: Icon(
          LucideIcons.grip,
          size: 12,
          color: isResizing
              ? context.themeColors.accentBlue
              : context.themeColors.textSecondary,
        ),
      ),
    );
  }

  double _getSize(bool isMainAxis, double defaultSize, bool fillCrossAxis) {
    if (isMainAxis) return defaultSize;
    return fillCrossAxis ? double.infinity : defaultSize;
  }

  Color _getHandleColor() {
    if (widget.isResizing)
      return context.themeColors.accentBlue.withValues(alpha: 0.3);
    if (_isHovered) return context.themeColors.accentBlue.withValues(alpha: 0.1);
    return Colors.transparent;
  }

  Color _getBarColor() {
    if (widget.isResizing) return context.themeColors.accentBlue;
    if (_isHovered) return context.themeColors.accentBlue.withValues(alpha: 0.5);
    return AppDesignSystem.borderDefault;
  }
}

// ============================================================================
// Legacy 类型别名（向后兼容，零破坏性迁移）
// ============================================================================

typedef SidebarResizer = AppResizer;
typedef AiPanelResizer = AppResizer;

/// `EditorResultsResizer` 保留为独立构造，因为它有 `isHorizontal` 语义
class EditorResultsResizer extends AppResizer {
  const EditorResultsResizer({
    super.key,
    required super.isResizing,
    required super.onResizeStart,
    required super.onResizeUpdate,
    required super.onResizeEnd,
    bool isHorizontal = false,
  }) : super(
         direction: isHorizontal ? Axis.horizontal : Axis.vertical,
         grabBarSize: isHorizontal ? const Size(3, 40) : const Size(40, 3),
         fillCrossAxis: true,
         // C21（原型 editor-results-split）：4px 静止 bar + grip chip 手柄
         gripHandle: true,
         restLineThickness: 4,
         restLineStrong: true,
       );}
