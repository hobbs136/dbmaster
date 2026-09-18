import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

enum ConfirmResult { cancel, allowOnce, allowSession }

/// ConfirmExecuteDialog - SQL/Command执行确认对话框
class ConfirmExecuteDialog extends StatelessWidget {
  final String command;
  final String? warningReason;
  final AppLocalizations l10n;

  const ConfirmExecuteDialog({
    super.key,
    required this.command,
    this.warningReason,
    required this.l10n,
  });

  bool get isDangerous => warningReason != null && warningReason!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Icon(
            isDangerous ? LucideIcons.triangleAlert : LucideIcons.play,
            color: isDangerous
                ? context.themeColors.error
                : context.themeColors.success,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            isDangerous
                ? l10n.aiPanelConfirmDangerousOperation
                : l10n.aiPanelConfirmExecuteSql,
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDangerous)
            Container(
              padding: EdgeInsets.all(AppDesignSystem.space2),
              margin: EdgeInsets.only(bottom: AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(color: context.themeColors.error),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
                    color: context.themeColors.error,
                    size: 16,
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Expanded(
                    child: Text(
                      warningReason!,
                      style: TextStyle(
                        color: context.themeColors.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(AppDesignSystem.space2),
              child: Text(
                command,
                style: TextStyle(
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 11,
                  color: context.themeColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ConfirmResult.cancel),
          child: Text(l10n.commonCancel),
        ),
        if (!isDangerous)
          TextButton(
            onPressed: () => Navigator.pop(context, ConfirmResult.allowSession),
            child: Text(
              l10n.aiPanelAllowSession,
              style: TextStyle(color: context.themeColors.success),
            ),
          ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, ConfirmResult.allowOnce),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDangerous
                ? context.themeColors.error
                : context.themeColors.success,
          ),
          child: Text(l10n.aiPanelConfirmExecute),
        ),
      ],
    );
  }
}
