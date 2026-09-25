import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// 工具组视图 - 显示多个工具的参数和结果
class ToolGroupView extends StatelessWidget {
  final int toolCount;
  final List<Map<String, dynamic>> tools;

  const ToolGroupView({super.key, required this.toolCount, required this.tools});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 工具数量统计
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.themeColors.bgSecondary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: context.themeColors.borderLight),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.wandSparkles,
                size: 14,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                AppLocalizations.of(context)!.toolGroupSummary(toolCount),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppDesignSystem.space3),
        // 每个工具的详细内容
        ...tools.asMap().entries.map((entry) {
          final index = entry.key;
          final tool = entry.value;
          final toolName = tool['toolName'] as String? ?? 'unknown';
          final arguments = tool['toolArguments'] as Map<String, dynamic>?;
          final result = tool['result'] as String? ?? '';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (index > 0) const Divider(height: 16, thickness: 0.5),
              _buildToolSection(
                context,
                title: AppLocalizations.of(
                  context,
                )!.toolGroupItemTitle(index + 1, toolName),
                icon: LucideIcons.wrench,
                content: arguments != null
                    ? const JsonEncoder.withIndent('  ').convert(arguments)
                    : AppLocalizations.of(context)!.toolNoParams,
                isDark: isDark,
              ),
              const SizedBox(height: AppDesignSystem.space1_5),
              _buildToolSection(
                context,
                title: AppLocalizations.of(context)!.toolResultLabel,
                icon: LucideIcons.squareTerminal,
                content: result,
                isDark: isDark,
              ),
            ],
          );
        }),
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
