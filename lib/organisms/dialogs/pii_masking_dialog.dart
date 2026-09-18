import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/pii_masker.dart';
import '../../theme/app_theme.dart';

/// PII 数据脱敏设置对话框
class PIIMaskingDialog extends StatefulWidget {
  const PIIMaskingDialog({super.key});

  @override
  State<PIIMaskingDialog> createState() => _PIIMaskingDialogState();
}

class _PIIMaskingDialogState extends State<PIIMaskingDialog> {
  late bool _enabled;
  late Map<String, bool> _patternStates;

  @override
  void initState() {
    super.initState();
    final masker = PIIMasker();
    _enabled = masker.enabled;
    _patternStates = {
      for (final entry in masker.patterns.entries)
        entry.key: entry.value.enabled,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        l10n.piiMaskingTitle,
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 总开关
            SwitchListTile(
              title: Text(
                l10n.piiMaskingEnable,
                style: TextStyle(color: context.themeColors.textPrimary),
              ),
              subtitle: Text(
                l10n.piiMaskingEnableDesc,
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 12,
                ),
              ),
              value: _enabled,
              activeThumbColor: context.themeColors.accentBlue,
              onChanged: (value) {
                setState(() {
                  _enabled = value;
                });
              },
            ),
            const Divider(),
            // 各类 PII 开关
            Text(
              l10n.piiMaskingTypes,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            ..._buildPatternToggles(l10n),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.commonCancel,
            style: TextStyle(color: context.themeColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _saveSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.accentBlue,
          ),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }

  List<Widget> _buildPatternToggles(AppLocalizations l10n) {
    final patternLabels = {
      'email': l10n.piiTypeEmail,
      'phone': l10n.piiTypePhone,
      'id_card': l10n.piiTypeIdCard,
      'credit_card': l10n.piiTypeCreditCard,
      'bank_card': l10n.piiTypeBankCard,
      'password': l10n.piiTypePassword,
      'ip_address': l10n.piiTypeIpAddress,
    };

    return _patternStates.entries.map((entry) {
      final label = patternLabels[entry.key] ?? entry.key;
      return CheckboxListTile(
        title: Text(
          label,
          style: TextStyle(
            color: context.themeColors.textPrimary,
            fontSize: 13,
          ),
        ),
        value: entry.value,
        activeColor: context.themeColors.accentBlue,
        onChanged: _enabled
            ? (value) {
                setState(() {
                  _patternStates[entry.key] = value ?? false;
                });
              }
            : null,
        dense: true,
      );
    }).toList();
  }

  void _saveSettings() {
    final masker = PIIMasker();
    masker.enabled = _enabled;

    for (final entry in _patternStates.entries) {
      masker.setPatternEnabled(entry.key, entry.value);
    }

    Navigator.pop(context, true);
  }
}
