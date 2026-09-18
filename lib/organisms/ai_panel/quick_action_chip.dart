import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class QuickActionChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? activeColor;

  const QuickActionChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.isActive = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = activeColor ?? context.themeColors.accentPurple;

    return Material(
      color: isActive
          ? chipColor.withValues(alpha: 0.15)
          : context.themeColors.bgTertiary,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space1_5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isActive ? chipColor : context.themeColors.textMuted,
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isActive
                      ? chipColor
                      : context.themeColors.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
