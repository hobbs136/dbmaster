import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';

/// ============================================================================
/// 品牌化加载指示器 - Branded Loading Indicator
/// ============================================================================
class AppBrandedLoading extends StatefulWidget {
  final double size;
  final double strokeWidth;
  final Color? color;
  final String? label;

  const AppBrandedLoading({
    super.key,
    this.size = 40,
    this.strokeWidth = 3,
    this.color,
    this.label,
  });

  @override
  State<AppBrandedLoading> createState() => _AppBrandedLoadingState();
}

class _AppBrandedLoadingState extends State<AppBrandedLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.themeColors.accentBlue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: widget.strokeWidth,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.all(widget.strokeWidth),
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  strokeWidth: widget.strokeWidth,
                ),
              ),
            );
          },
        ),
        if (widget.label != null) ...[
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            widget.label ?? '',
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// ============================================================================
/// 页面级加载状态 - Page Loading State
/// ============================================================================
class AppPageLoading extends StatelessWidget {
  final String? message;
  final bool showLogo;

  const AppPageLoading({super.key, this.message, this.showLogo = true});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLogo) ...[
            Icon(
              LucideIcons.database,
              size: 48,
              color: context.themeColors.accentBlue.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppDesignSystem.space6),
          ],
          AppBrandedLoading(label: message),
        ],
      ),
    );
  }
}

class LoadingButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? backgroundColor;
  final Color? textColor;
  final double? height;
  final double? minWidth;
  final EdgeInsets? padding;
  final IconData? icon;

  const LoadingButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.backgroundColor,
    this.textColor,
    this.height,
    this.minWidth,
    this.padding,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? context.themeColors.accentBlue,
        foregroundColor: textColor ?? Colors.white,
        minimumSize: minWidth != null || height != null
            ? Size(minWidth ?? double.infinity, height ?? 36)
            : null,
        padding:
            padding ??
            const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space4,
              vertical: AppDesignSystem.space2,
            ),
      ),
      child: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  textColor ?? Colors.white,
                ),
              ),
            )
          : icon != null
          ? Row(
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: AppDesignSystem.space2),
                Text(label),
              ],
            )
          : Text(label),
    );
  }
}

class LoadingTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Color? textColor;
  final IconData? icon;

  const LoadingTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: textColor ?? context.themeColors.textSecondary,
      ),
      child: isLoading
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  textColor ?? context.themeColors.textSecondary,
                ),
              ),
            )
          : icon != null
          ? Row(
              children: [
                Icon(icon, size: 14),
                const SizedBox(width: AppDesignSystem.space1_5),
                Text(label),
              ],
            )
          : Text(label),
    );
  }
}
