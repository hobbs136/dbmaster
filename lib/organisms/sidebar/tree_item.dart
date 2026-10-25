import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../atoms/app_widgets.dart';

class TreeItem extends StatefulWidget {
  final int level;
  final IconData? icon;
  final Color iconColor;
  final String? label; // 改可选，供 labelWidget 模式下省略
  final Widget? labelWidget; // 非空时替代默认 label（列/索引/FK 叶子复用本组件交互脚手架）
  final Color? labelColor; // 默认 label 文本色覆盖
  final String? badge;
  final bool isExpanded;
  final bool isSelected;
  final bool isLoading;
  final bool showArrow;
  final Widget? trailing;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final void Function(Offset position)? onContextMenu;
  final double? iconSize;

  /// S9（J3 多连接长驻树）：连接根行左缘 3px 环境色竖条；null 不渲染。
  /// 色值 = `ConnectionEnvironment.badgeColor`（与活动标签色条/状态栏
  /// 徽章三处同源）；渲染在行卡片外侧 gutter，不与选中态左指示条叠压。
  final Color? environmentBarColor;

  /// UIRV-B5：连接根行副信息（host:port / SQLite 文件路径）；null 时
  /// 行为与旧单行完全一致（level 1 高 28）。非空时根行 36px（28+8）双行。
  final String? subtitle;

  /// 副行 Tooltip 全值（socket 型 = 「连接名 · host:port」、SQLite =
  /// 完整路径）；null 回退用 subtitle 本身（ellipsis 时悬停可读全值）。
  final String? subtitleTooltip;

  const TreeItem({
    super.key,
    required this.level,
    this.icon,
    required this.iconColor,
    this.label,
    this.labelWidget,
    this.labelColor,
    this.badge,
    this.subtitle,
    this.subtitleTooltip,
    this.isExpanded = false,
    this.isSelected = false,
    this.isLoading = false,
    this.showArrow = true,
    this.trailing,
    required this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.iconSize,
    this.environmentBarColor,
  });

  @override
  State<TreeItem> createState() => _TreeItemState();
}

class _TreeItemState extends State<TreeItem> {
  bool _isHovered = false;

  double get _itemHeight {
    switch (widget.level) {
      case 1:
        // UIRV-B5：双行根行 36（28 主行 + 8 副行），单行维持 28。
        return widget.subtitle != null ? 36 : 28;
      case 2:
        return 24;
      case 3:
        return 22;
      default:
        return 20;
    }
  }

  double get _fontSize {
    switch (widget.level) {
      case 1:
        return 13;
      case 2:
        return 12;
      default:
        return 11;
    }
  }

  FontWeight get _fontWeight {
    switch (widget.level) {
      case 1:
        return FontWeight.w600;
      case 2:
        return FontWeight.w500;
      default:
        return FontWeight.w400;
    }
  }

  double get _iconSize {
    switch (widget.level) {
      case 1:
      case 2:
        return 16;
      default:
        return 14;
    }
  }

  bool get _hasBackground => widget.level == 1 || widget.level == 2;

  Color _getBackgroundColor(BuildContext context) {
    final colors = context.themeColors;

    if (widget.isSelected) {
      return _hasBackground
          ? context.themeColors.accentBlue.withValues(alpha: 0.15)
          : context.themeColors.accentBlue.withValues(alpha: 0.1);
    }

    if (_isHovered) {
      return colors.bgTertiary.withValues(alpha: _hasBackground ? 0.8 : 0.6);
    }

    if (_hasBackground) {
      return widget.level == 1
          ? colors.bgTertiary.withValues(alpha: 0.5)
          : colors.bgTertiary.withValues(alpha: 0.3);
    }

    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    Widget row = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        // 菜单在抬升沿打开（与 ContextMenuUtils.gestureDetector 同款）：
        // 按下沿同步 push 菜单路由会打断本手势的完成链，TapGestureRecognizer
        // 停留在 sent-tap-down 不复位，同一行的下一次右键被吞（E2E 实锤：
        // 移组用例对同一行右键两次，第二次菜单不开）。
        onSecondaryTapUp: widget.onContextMenu != null
            ? (details) => widget.onContextMenu!(details.globalPosition)
            : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: _itemHeight,
          margin: _hasBackground
              ? EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: 1,
                )
              : null,
          padding: EdgeInsets.only(
            left: _hasBackground
                ? AppDesignSystem.space2
                : AppDesignSystem.space3,
            right: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            color: _getBackgroundColor(context),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            // plan §4.2：选中态左侧 3px primary 指示条（配合背景 tint）
            border: widget.isSelected
                ? Border(
                    left: BorderSide(
                      color: context.themeColors.accentBlue,
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: _buildContent(context),
        ),
      ),
    );

    // S9：环境色条挂在行卡片外侧左 gutter（mockup .tnode .env 形态：
    // left:0 / top:3 / bottom:3 / 3px / radius 2）——不挤占内容、不与
    // 选中态 3px 指示条（卡片内缘）叠压。
    if (widget.environmentBarColor == null) return row;
    return Stack(
      children: [
        row,
        Positioned(
          left: 0,
          top: 3,
          bottom: 3,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: widget.environmentBarColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }

  /// 行内容：单行模式（subtitle == null）= 原 Row 布局；双行根行模式
  /// （UIRV-B5）= 主行 Row + 副行 mono host 信息。GestureDetector 覆盖
  /// 整卡（含副行）——副行与主行共享同一手势，不是独立交互入口。
  Widget _buildContent(BuildContext context) {
    final colors = context.themeColors;
    final row = Row(
      children: [
        ..._buildTreeConnectors(context),
        if (widget.showArrow) ...[
          if (widget.isLoading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.themeColors.accentBlue,
              ),
            )
          else
            AnimatedRotation(
              duration: const Duration(milliseconds: 200),
              curve: AppDesignSystem.curveDefault,
              turns: widget.isExpanded ? 0.25 : 0,
              child: Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: colors.textMuted,
              ),
            ),
          const SizedBox(width: AppDesignSystem.space1),
        ] else ...[
          SizedBox(width: 14 + AppDesignSystem.space1),
        ],
        // emoji 图标分支已移除，统一用 Material 矢量图标
        if (widget.icon != null)
          Icon(
            widget.icon,
            size: widget.iconSize ?? _iconSize,
            color: widget.iconColor,
          ),
        const SizedBox(width: AppDesignSystem.space2),
        // 支持 labelWidget（列/索引/FK 叶子复用本组件的悬停/选中/点击/双击/右键脚手架）
        Expanded(
          child:
              widget.labelWidget ??
              Tooltip(
                // ellipsis 截断时悬停可见完整名（契约 C6）；label 为空时不触发
                message: widget.label ?? '',
                child: Text(
                  widget.label ?? '',
                  style: TextStyle(
                    fontSize: _fontSize,
                    fontWeight: _fontWeight,
                    color: widget.labelColor ?? colors.textPrimary,
                    height: 1.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ),
        if (widget.badge != null)
          AppStatusBadge(text: widget.badge!, type: StatusType.info),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppDesignSystem.space1),
          widget.trailing!,
        ],
      ],
    );

    final subtitle = widget.subtitle;
    if (subtitle == null || subtitle.isEmpty) return row;

    // UIRV-B5 副行：mono 单行 ellipsis（mockup B5 规格表：
    // textSecondary + JetBrains Mono fallback / line-height 1.25）；
    // 窄侧栏副行自行截断，不挤掉名称/状态/类型（主行 Expanded 优先）。
    final tooltipMessage =
        (widget.subtitleTooltip != null && widget.subtitleTooltip!.isNotEmpty)
        ? widget.subtitleTooltip!
        : subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        const SizedBox(height: AppDesignSystem.space0_5),
        Tooltip(
          message: tooltipMessage,
          child: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              height: 1.25,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildTreeConnectors(BuildContext context) {
    if (widget.level <= 1) return [];

    final connectors = <Widget>[];
    for (int i = 1; i < widget.level; i++) {
      connectors.add(
        Container(
          width: AppDesignSystem.treeNodeIndent,
          height: _itemHeight,
          alignment: Alignment.center,
          child: Container(
            width: 1,
            height: double.infinity,
            color: context.themeColors.borderSubtle,
          ),
        ),
      );
    }
    return connectors;
  }
}
