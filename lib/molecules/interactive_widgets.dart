import 'package:flutter/material.dart';
import '../../theme/design_system.dart';
import '../theme/app_colors.dart';

/// ============================================================================
/// InteractiveContainer - 带交互反馈的容器
/// ============================================================================
///
/// 提供统一的交互反馈效果：
/// - 悬停效果（背景色变化）
/// - 点击涟漪
/// - 按下效果
///
/// 用法：
/// ```dart
/// InteractiveContainer(
///   onTap: () {},
///   child: Text('点击我'),
/// )
/// ```
/// ============================================================================
class InteractiveContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final Color? hoverColor;
  final Color? activeColor;
  final Color? rippleColor;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final Duration? animationDuration;

  const InteractiveContainer({
    super.key,
    required this.child,
    this.onTap,
    this.onSecondaryTap,
    this.hoverColor,
    this.activeColor,
    this.rippleColor,
    this.borderRadius,
    this.padding,
    this.animationDuration,
  });

  @override
  State<InteractiveContainer> createState() => _InteractiveContainerState();
}

class _InteractiveContainerState extends State<InteractiveContainer>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.animationDuration ?? AppDesignSystem.durationFast,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(curve: Curves.easeOut, parent: _animationController),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveHoverColor = widget.hoverColor ?? AppDesignSystem.bgTertiary;
    final effectiveActiveColor =
        widget.activeColor ?? AppDesignSystem.bgTertiary;
    final effectiveRippleColor =
        widget.rippleColor ?? context.themeColors.accentBlue.withOpacity(0.1);

    final currentColor = _isPressed
        ? effectiveActiveColor
        : (_isHovered ? effectiveHoverColor : Colors.transparent);

    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTap: widget.onSecondaryTap,
      child: MouseRegion(
        onEnter: (_) {
          if (!_isHovered) {
            setState(() => _isHovered = true);
          }
        },
        onExit: (_) {
          if (_isHovered) {
            setState(() => _isHovered = false);
          }
        },
        child: AnimatedContainer(
          duration: widget.animationDuration ?? AppDesignSystem.durationFast,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: currentColor,
            borderRadius: widget.borderRadius,
          ),
          child: ScaleTransition(
            scale: _isPressed
                ? _scaleAnimation
                : const AlwaysStoppedAnimation(1.0),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onSecondaryTap: widget.onSecondaryTap,
                splashColor: effectiveRippleColor,
                highlightColor: effectiveRippleColor.withOpacity(0.5),
                borderRadius: widget.borderRadius,
                customBorder: widget.borderRadius != null
                    ? RoundedRectangleBorder(borderRadius: widget.borderRadius!)
                    : null,
                onTapDown: (_) {
                  setState(() {
                    _isPressed = true;
                    _animationController.forward();
                  });
                },
                onTapUp: (_) {
                  setState(() {
                    _isPressed = false;
                    _animationController.reverse();
                  });
                },
                onTapCancel: () {
                  setState(() {
                    _isPressed = false;
                    _animationController.reverse();
                  });
                },
                child: Padding(
                  padding: widget.padding ?? EdgeInsets.zero,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// InteractiveCard - 带交互反馈的卡片
/// ============================================================================
///
/// 结合了 Material Card 的完整卡片，包含边框、阴影、圆角
/// 用法：
/// ```dart
/// InteractiveCard(
///   onTap: () {},
///   title: '卡片标题',
///   subtitle: '卡片描述',
///   leading: Icon(LucideIcons.star),
///   trailing: Icon(LucideIcons.chevronRight),
/// )
/// ```
/// ============================================================================
class InteractiveCard extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final bool isSelected;
  final Color? activeColor;
  final EdgeInsets? contentPadding;

  const InteractiveCard({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onSecondaryTap,
    this.isSelected = false,
    this.activeColor,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor =
        activeColor ?? context.themeColors.accentBlue.withOpacity(0.1);

    return Container(
      decoration: BoxDecoration(
        color: isSelected ? effectiveActiveColor : AppDesignSystem.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: isSelected
              ? context.themeColors.accentBlue
              : AppDesignSystem.borderLight,
          width: 1,
        ),
        boxShadow: isSelected ? AppDesignSystem.shadowFloat : null,
      ),
      child: InteractiveContainer(
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        child: Padding(
          padding: contentPadding ?? EdgeInsets.all(AppDesignSystem.space4),
          child: Row(
            children: [
              if (leading != null) ...[
                leading!,
                SizedBox(width: AppDesignSystem.space3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: AppDesignSystem.fontSizeMd,
                        fontWeight: AppDesignSystem.fontWeightSemibold,
                        color: AppDesignSystem.textPrimary,
                        height: AppDesignSystem.lineHeightTight,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: AppDesignSystem.space1),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: AppDesignSystem.fontSizeSm,
                          fontWeight: AppDesignSystem.fontWeightRegular,
                          color: AppDesignSystem.textSecondary,
                          height: AppDesignSystem.lineHeightNormal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                SizedBox(width: AppDesignSystem.space3),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// PressableIcon - 可按压的图标
/// ============================================================================
///
/// 带悬停、点击、涟漪效果的图标按钮
/// 用法：
/// ```dart
/// PressableIcon(
///   icon: LucideIcons.chevronRight,
///   onTap: () {},
///   size: 24,
/// )
/// ```
/// ============================================================================
class PressableIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? hoverColor;
  final double size;
  final String? tooltip;
  final EdgeInsets? padding;

  const PressableIcon({
    super.key,
    required this.icon,
    this.onTap,
    this.iconColor,
    this.hoverColor,
    this.size = 24.0,
    this.tooltip,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveIconColor = iconColor ?? AppDesignSystem.textSecondary;
    final effectiveHoverColor = hoverColor ?? AppDesignSystem.bgTertiary;

    return InteractiveContainer(
      onTap: onTap,
      hoverColor: effectiveHoverColor,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      padding: padding ?? EdgeInsets.all(AppDesignSystem.space2),
      child: Tooltip(
        message: tooltip ?? '',
        child: Icon(icon, size: size, color: effectiveIconColor),
      ),
    );
  }
}

/// ============================================================================
/// PressableListTile - 可按压的列表项
/// ============================================================================
///
/// 带完整交互反馈的列表项，包含悬停、选中、涟漪效果
/// 用法：
/// ```dart
/// PressableListTile(
///   leading: Icon(LucideIcons.database),
///   title: '数据库名称',
///   subtitle: '数据库描述',
///   onTap: () {},
///   isSelected: true,
/// )
/// ```
/// ============================================================================
class PressableListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final bool isSelected;
  final bool isHovered;
  final EdgeInsets? contentPadding;

  const PressableListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onSecondaryTap,
    this.isSelected = false,
    this.isHovered = false,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePadding =
        contentPadding ??
        EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        );

    return InteractiveContainer(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      padding: effectivePadding,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            SizedBox(width: AppDesignSystem.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppDesignSystem.fontSizeMd,
                    fontWeight: AppDesignSystem.fontWeightMedium,
                    color: AppDesignSystem.textPrimary,
                    height: AppDesignSystem.lineHeightTight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  SizedBox(height: AppDesignSystem.space1),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: AppDesignSystem.fontSizeSm,
                      fontWeight: AppDesignSystem.fontWeightRegular,
                      color: AppDesignSystem.textSecondary,
                      height: AppDesignSystem.lineHeightNormal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: AppDesignSystem.space3),
            trailing!,
          ],
        ],
      ),
    );
  }
}
