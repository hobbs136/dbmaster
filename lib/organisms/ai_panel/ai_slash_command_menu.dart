import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

class SlashCommandMenu extends StatelessWidget {
  final String filter;
  final Function(String action, String command) onCommandSelected;

  const SlashCommandMenu({
    super.key,
    required this.filter,
    required this.onCommandSelected,
  });

  List<Map<String, dynamic>> _commands(AppLocalizations l10n) =>
      <Map<String, dynamic>>[
        {
          'action': 'optimize_sql',
          'command': '/optimize',
          'desc': l10n.aiCmdOptimizeSql,
          'icon': LucideIcons.gauge,
        },
        {
          'action': 'explain_query',
          'command': '/explain',
          'desc': l10n.aiCmdExplainQuery,
          'icon': LucideIcons.chartColumn,
        },
        {
          'action': 'generate_crud',
          'command': '/generate',
          'desc': l10n.aiCmdGenerateCrud,
          'icon': LucideIcons.sparkles,
        },
        {
          'action': 'analyze_table',
          'command': '/analyze',
          'desc': l10n.aiCmdAnalyzeTable,
          'icon': LucideIcons.table2,
        },
        {
          'action': 'show_history',
          'command': '/history',
          'desc': l10n.aiCmdShowHistory,
          'icon': LucideIcons.history,
        },
        {
          'action': 'show_bookmarks',
          'command': '/bookmarks',
          'desc': l10n.aiCmdShowBookmarks,
          'icon': LucideIcons.bookmark,
        },
        {
          'action': 'branch_conversation',
          'command': '/branch',
          'desc': l10n.aiCmdBranchConversation,
          'icon': LucideIcons.network,
        },
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final commands = _commands(l10n);
    final filterLower = filter.toLowerCase();
    final filtered = filterLower.isEmpty
        ? commands
        : commands.where((c) {
            return (c['command'] as String).toLowerCase().contains(
                  filterLower,
                ) ||
                (c['desc'] as String).toLowerCase().contains(filterLower);
          }).toList();

    if (filtered.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final cmd = filtered[index];
          return InkWell(
            onTap: () => onCommandSelected(
              cmd['action'] as String,
              cmd['command'] as String,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space2,
              ),
              child: Row(
                children: [
                  Icon(
                    cmd['icon'] as IconData,
                    size: 16,
                    color: context.themeColors.accentPurple,
                  ),
                  const SizedBox(width: AppDesignSystem.space2_5),
                  Text(
                    cmd['command'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: context.themeColors.textPrimary,
                      fontFamily: AppDesignSystem.monoFontFamily,

                      fontFamilyFallback:
                          AppDesignSystem.monoFontFamilyFallback,
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space2_5),
                  Expanded(
                    child: Text(
                      cmd['desc'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.themeColors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
