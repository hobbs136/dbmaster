import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

class DefinitionViewDialog extends StatelessWidget {
  final String title;
  final String definition;
  final String? language;

  const DefinitionViewDialog({
    super.key,
    required this.title,
    required this.definition,
    this.language = 'sql',
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.themeColors.bgSecondary,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDesignSystem.space4),
                child: _buildCodeView(context),
              ),
            ),
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.code,
            color: context.themeColors.accentPurple,
            size: 20,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            title,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSize2xl,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(LucideIcons.x, color: context.themeColors.textMuted),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeView(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: context.themeColors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: SelectableText(
        definition,
        style: TextStyle(
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          fontSize: 12,
          color: context.themeColors.textPrimary,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.themeColors.borderLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: definition));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.connCopiedToClipboard),
                  backgroundColor: context.themeColors.success,
                ),
              );
            },
            icon: const Icon(LucideIcons.copy, size: 16),
            label: Text(l10n.connCopy),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.themeColors.textSecondary,
              side: BorderSide(color: context.themeColors.borderLight),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space4,
                vertical: AppDesignSystem.space2,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space5,
                vertical: AppDesignSystem.space2,
              ),
            ),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }
}
