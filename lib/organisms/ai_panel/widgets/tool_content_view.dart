import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// 工具内容展示组件 - 纯内容展示，不含标题栏和折叠功能
class ToolContentView extends StatelessWidget {
  final String? arguments;
  final String? result;
  final bool isCall;

  const ToolContentView({super.key, this.arguments, this.result, required this.isCall});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (arguments != null) ...[
          _buildToolSection(
            context,
            title: AppLocalizations.of(context)!.toolParamLabel,
            icon: LucideIcons.logIn,
            content: arguments!,
            isDark: isDark,
          ),
          const SizedBox(height: AppDesignSystem.space2),
        ],
        if (result != null && result!.isNotEmpty)
          _buildToolSection(
            context,
            title: AppLocalizations.of(context)!.toolResultLabel,
            icon: LucideIcons.squareTerminal,
            content: result!,
            isDark: isDark,
          ),
      ],
    );
  }

  Widget _buildToolSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String content,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.themeColors.codeBlockBg,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: context.themeColors.textMuted),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          SelectableText(
            content,
            style: TextStyle(
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: 11,
              color: context.themeColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
