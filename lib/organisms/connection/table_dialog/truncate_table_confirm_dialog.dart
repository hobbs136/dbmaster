import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../theme/app_colors.dart';

/// Return value from [TruncateTableConfirmDialog].
class TruncateDialogResult {
  final bool confirmed;
  final TruncateOptions options;
  const TruncateDialogResult({
    required this.confirmed,
    this.options = const TruncateOptions(),
  });
}

class TruncateTableConfirmDialog extends StatefulWidget {
  final String tableName;
  final bool showPostgresOptions;

  const TruncateTableConfirmDialog({
    super.key,
    required this.tableName,
    this.showPostgresOptions = false,
  });

  @override
  State<TruncateTableConfirmDialog> createState() =>
      _TruncateTableConfirmDialogState();
}

class _TruncateTableConfirmDialogState
    extends State<TruncateTableConfirmDialog> {
  bool _cascade = false;
  bool _restartIdentity = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(LucideIcons.brushCleaning, color: context.themeColors.warning),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.truncateTableData,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Are you sure you want to truncate all data in table "${widget.tableName}"?',
            style: TextStyle(
              color: context.themeColors.textPrimary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Container(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            decoration: BoxDecoration(
              color: context.themeColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.info,
                  size: 16,
                  color: context.themeColors.warning,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    'This operation will delete all data in the table but keep the table structure.',
                    style: TextStyle(
                      color: context.themeColors.warning.withValues(alpha: 0.9),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.showPostgresOptions) ...[
            const SizedBox(height: AppDesignSystem.space3),
            _buildPostgreSqlOptions(context),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const TruncateDialogResult(confirmed: false),
          ),
          child: Text(l10n.commonCancel),
        ),
        ElevatedButton(
          onPressed: () {
            final options = TruncateOptions(
              cascade: _cascade,
              restartIdentity: widget.showPostgresOptions
                  ? (_restartIdentity ? true : null)
                  : null,
            );
            Navigator.pop(
              context,
              TruncateDialogResult(confirmed: true, options: options),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.warning,
          ),
          child: Text(l10n.connTruncate),
        ),
      ],
    );
  }

  Widget _buildPostgreSqlOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PostgreSQL Options',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1),
        StatefulBuilder(
          builder: (context, setLocalState) {
            return Column(
              children: [
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'CASCADE',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Automatically truncate tables with foreign-key references',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textMuted,
                    ),
                  ),
                  value: _cascade,
                  onChanged: (v) {
                    setState(() => _cascade = v ?? false);
                    setLocalState(() {});
                  },
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'RESTART IDENTITY',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Restart sequences owned by columns of the truncated table',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textMuted,
                    ),
                  ),
                  value: _restartIdentity,
                  onChanged: (v) {
                    setState(() => _restartIdentity = v ?? false);
                    setLocalState(() {});
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
