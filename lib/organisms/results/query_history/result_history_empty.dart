import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// Empty state for the result-panel query history view.
class ResultHistoryEmpty extends StatelessWidget {
  const ResultHistoryEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.history, size: 32, color: colors.textMuted),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              l10n?.queryHistoryEmpty ?? 'No query history',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              l10n?.queryHistoryEmptyHint ??
                  'Run a query with Ctrl+Enter or F5 and it will appear here automatically',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
