/// ============================================================================
/// 通用组件库 - Common Widgets
/// ============================================================================
///
/// 包含常用的 UI 组件，提升代码复用性
/// 组件：状态徽章、加载遮罩、错误提示、空状态等
///
/// 实际使用（2026-07 审计）：AppStatusBadge（tree_item）、AppEmptyState
/// （results_widget / sidebar_tree / main_workspace / welcome_screen）。
/// 其余组件当前无生产引用，但已全部改为主题感知，可安全复用。
/// ============================================================================
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';

/// ============================================================================
/// 状态徽章 - Status Badge
/// ============================================================================
///
/// 用于显示状态信息的徽章组件
class AppStatusBadge extends StatelessWidget {
  final String text;
  final StatusType type;
  final EdgeInsets? padding;

  const AppStatusBadge({
    super.key,
    required this.text,
    required this.type,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final typeColor = _getTypeColor(context, type);
    return Container(
      padding:
          padding ??
          const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1_5,
            vertical: AppDesignSystem.space0_5,
          ),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          color: typeColor,
          fontWeight: AppDesignSystem.fontWeightSemibold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // 语义色改走 ThemeColors 主题分发（亮色用深一档变体）
  Color _getTypeColor(BuildContext context, StatusType type) {
    final colors = context.themeColors;
    switch (type) {
      case StatusType.success:
        return colors.success;
      case StatusType.warning:
        return colors.warning;
      case StatusType.error:
        return colors.error;
      case StatusType.info:
        return colors.info;
      case StatusType.primary:
        return colors.accentBlue;
    }
  }
}

enum StatusType { success, warning, error, info, primary }

/// ============================================================================
/// 加载遮罩 - Loading Overlay
/// ============================================================================
///
/// 用于显示加载状态的遮罩组件
class AppLoadingOverlay extends StatelessWidget {
  final String? message;
  final bool isLoading;
  final Widget? child;

  const AppLoadingOverlay({
    super.key,
    this.message,
    required this.isLoading,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // 遮罩/文字改主题感知（原暗色常量使亮色模式遮罩为近黑纱）
    final colors = context.themeColors;
    return Stack(
      children: [
        ?child,
        if (isLoading)
          Container(
            color: colors.bgPrimary.withValues(alpha: 0.7),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: context.themeColors.accentBlue,
                    strokeWidth: 3,
                  ),
                  if (message != null) ...[
                    const SizedBox(height: AppDesignSystem.space4),
                    Text(
                      message!,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeMd,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// ============================================================================
/// 空状态 - Empty State
/// ============================================================================
///
/// 用于显示空状态的占位组件
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;
  final double iconSize;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.iconSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    // 图标/标题/描述颜色改主题感知
    final colors = context.themeColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final isCompact = availableHeight < 120;
        final adjustedIconSize = isCompact
            ? (iconSize * 0.6).clamp(24.0, 32.0)
            : iconSize;
        final spacing = isCompact
            ? AppDesignSystem.space1
            : AppDesignSystem.space3;

        return Center(
          child: Padding(
            padding: EdgeInsets.all(
              isCompact ? AppDesignSystem.space2 : AppDesignSystem.space3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: adjustedIconSize, color: colors.textMuted),
                SizedBox(height: spacing),
                if (!isCompact) ...[
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeLg,
                        color: colors.textPrimary,
                        fontWeight: AppDesignSystem.fontWeightMedium,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (description != null) ...[
                    SizedBox(height: AppDesignSystem.space2),
                    Flexible(
                      child: Text(
                        description!,
                        style: TextStyle(
                          fontSize: AppDesignSystem.fontSizeSm,
                          color: colors.textMuted,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (action != null) ...[SizedBox(height: spacing), action!],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ============================================================================
/// 错误提示 - Error Banner
/// ============================================================================
///
/// 用于显示错误信息的横幅组件
class AppErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;
  final ErrorType type;

  const AppErrorBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.onDismiss,
    this.type = ErrorType.error,
  });

  @override
  Widget build(BuildContext context) {
    final errorColor = _getErrorColor(context, type);
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.15),
        border: Border.all(color: errorColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        children: [
          Icon(_getErrorIcon(type), size: 20, color: errorColor),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: errorColor,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(
                '重试',
                style: TextStyle(
                  color: errorColor,
                  fontWeight: AppDesignSystem.fontWeightMedium,
                ),
              ),
            ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(LucideIcons.x, size: 18),
              onPressed: onDismiss,
              color: errorColor,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  IconData _getErrorIcon(ErrorType type) {
    switch (type) {
      case ErrorType.error:
        return LucideIcons.circleAlert;
      case ErrorType.warning:
        return LucideIcons.triangleAlert;
      case ErrorType.info:
        return LucideIcons.info;
    }
  }

  // 语义色改走 ThemeColors 主题分发
  Color _getErrorColor(BuildContext context, ErrorType type) {
    final colors = context.themeColors;
    switch (type) {
      case ErrorType.error:
        return colors.error;
      case ErrorType.warning:
        return colors.warning;
      case ErrorType.info:
        return colors.info;
    }
  }
}

enum ErrorType { error, warning, info }

/// ============================================================================
/// 卡片容器 - Card Container
/// ============================================================================
///
/// 统一的卡片容器组件
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final bool selected;
  final Color? accentColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.selected = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    // 卡片底色/边框改主题感知（原暗色常量使亮色模式卡片为黑卡）
    final colors = context.themeColors;
    final effectiveColor = accentColor ?? context.themeColors.accentBlue;

    return Container(
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: selected
              ? effectiveColor.withValues(alpha: 0.5)
              : colors.borderLight,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(AppDesignSystem.space4),
          child: child,
        ),
      ),
    );
  }
}

/// ============================================================================
/// 分隔线 - Divider
/// ============================================================================
///
/// 统一的分隔线组件
class AppDivider extends StatelessWidget {
  final double? thickness;
  final double? height;
  final Color? color;

  const AppDivider({super.key, this.thickness, this.height, this.color});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: height ?? AppDesignSystem.space3,
      thickness: thickness ?? 1,
      color: color ?? context.themeColors.dividerColor,
    );
  }
}

/// ============================================================================
/// 信息行 - Info Row
/// ============================================================================
///
/// 用于显示标签+值的行
class AppInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final Widget? valueWidget;

  const AppInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueWidget,
  });

  @override
  Widget build(BuildContext context) {
    // 标签/值颜色改主题感知
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              color: colors.textMuted,
            ),
          ),
          const Spacer(),
          valueWidget ??
              Text(
                value,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  color: valueColor ?? colors.textPrimary,
                  fontWeight: AppDesignSystem.fontWeightMedium,
                ),
              ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// 章节标题 - Section Title
/// ============================================================================
///
/// 用于显示章节标题的组件
class AppSectionTitle extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  const AppSectionTitle({
    super.key,
    required this.title,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeLg,
              fontWeight: AppDesignSystem.fontWeightSemibold,
              color: context.themeColors.textPrimary,
            ),
          ),
          if (actionText != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionText!,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  color: context.themeColors.accentBlue,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// 状态指示灯 - Status Dot
/// ============================================================================
///
/// 用于显示状态的小圆点
class AppStatusDot extends StatelessWidget {
  final bool isActive;
  final bool isLoading;
  final double size;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? loadingColor;

  const AppStatusDot({
    super.key,
    required this.isActive,
    this.isLoading = false,
    this.size = 8,
    this.activeColor,
    this.inactiveColor,
    this.loadingColor,
  });

  @override
  Widget build(BuildContext context) {
    // 语义色改走 ThemeColors 主题分发
    final colors = context.themeColors;
    Color color;
    if (isLoading) {
      color = loadingColor ?? colors.warning;
    } else if (isActive) {
      color = activeColor ?? colors.success;
    } else {
      color = inactiveColor ?? colors.error;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: isActive && !isLoading
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: size * 1.5,
                  spreadRadius: size * 0.25,
                ),
              ]
            : null,
      ),
    );
  }
}
