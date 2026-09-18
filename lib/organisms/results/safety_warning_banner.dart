import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';

/// Non-blocking warning banner for high-risk DML operations and EXPLAIN warnings.
///
/// Displays a yellow/amber-themed warning with action buttons.
/// The "Confirm" button has a configurable cooldown timer.
class SafetyWarningBanner extends StatefulWidget {
  final String warningText;
  final String? detailText;
  final VoidCallback onConfirm;
  final VoidCallback? onAddLimit;
  final VoidCallback onCancel;
  final int cooldownSeconds;

  const SafetyWarningBanner({
    super.key,
    required this.warningText,
    this.detailText,
    required this.onConfirm,
    this.onAddLimit,
    required this.onCancel,
    this.cooldownSeconds = 2,
  });

  @override
  State<SafetyWarningBanner> createState() => _SafetyWarningBannerState();
}

class _SafetyWarningBannerState extends State<SafetyWarningBanner> {
  Timer? _cooldownTimer;
  int _remainingSeconds = 0;
  bool _cooldownActive = false;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _remainingSeconds = widget.cooldownSeconds;
    _cooldownActive = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds--;
        if (_remainingSeconds <= 0) {
          _cooldownActive = false;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 橙色 shade 硬编码 → warning 令牌族（F-15，亮暗自动分发）
    final l10n = AppLocalizations.of(context)!;
    final warning = context.themeColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space2_5,
      ),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.08),
        border: Border(
          top: BorderSide(color: warning.withValues(alpha: 0.5), width: 2),
          bottom: BorderSide(color: warning.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 22, color: warning),
          const SizedBox(width: AppDesignSystem.space2_5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.warningText,
                  style: TextStyle(
                    color: warning,
                    fontWeight: FontWeight.w600,
                    fontSize: AppDesignSystem.fontSizeMd,
                  ),
                ),
                if (widget.detailText != null) ...[
                  const SizedBox(height: AppDesignSystem.space0_5),
                  Text(
                    widget.detailText!,
                    style: TextStyle(
                      color: warning,
                      fontSize: AppDesignSystem.fontSizeSm,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          if (widget.onAddLimit != null)
            TextButton(
              onPressed: widget.onAddLimit,
              style: TextButton.styleFrom(
                foregroundColor: warning,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space3,
                ),
              ),
              child: Text(l10n.safetyBannerAddLimit),
            ),
          const SizedBox(width: AppDesignSystem.space1),
          FilledButton(
            onPressed: _cooldownActive ? null : widget.onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: warning,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3 + AppDesignSystem.space1,
              ),
            ),
            child: Text(
              _cooldownActive
                  ? l10n.safetyBannerCooldown(_remainingSeconds)
                  : l10n.commonConfirm,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1),
          TextButton(
            onPressed: widget.onCancel,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
              ),
            ),
            child: Text(l10n.commonCancel),
          ),
        ],
      ),
    );
  }
}
