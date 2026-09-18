//! Reusable dismissable guide row for conversion touchpoints.
//!
//! Each touchpoint renders either when connected to a server (default
//! behaviour, FR-033..FR-038) or — for the lite variant only — when the
//! user is NOT connected but has used the corresponding feature ≥3 times
//! (FR-039a / D1=B; see `telemetry-funnel-plan.md` §1.B). Dismissal is
//! session-scoped: dismissed guides re-appear on app restart.
//!
//! Telemetry hooks:
//!   * On first render of a non-dismissed instance, fires `touchpoint_exposed`.
//!   * Wraps [onAction] so the wrapped callback fires `touchpoint_clicked`
//!     before the caller's action.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/telemetry_service.dart';
import '../../theme/app_colors.dart';

/// Visual variant for [ConversionGuideRow].
enum ConversionGuideVariant {
  /// Full guide shown to server-connected users (FR-033..FR-038).
  full,

  /// Subtle one-line guide shown to unconnected repeat users
  /// (FR-039a / D1=B). The lite variant has different copy and a softer
  /// surface so it does not alienate free users.
  lite,
}

/// A single conversion guide row with icon, title, description, and action.
///
/// Dismissal is session-scoped — the guide re-appears on app restart.
class ConversionGuideRow extends StatefulWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;
  final String guideId;

  /// Whether the desktop is currently connected to a DbMaster server.
  /// Injected from the caller's [ServerConnectionProvider]; kept here as a
  /// plain bool so this widget does not need a Provider dependency.
  final bool serverConnected;

  /// Visual + telemetry variant. Defaults to [ConversionGuideVariant.full].
  final ConversionGuideVariant variant;

  /// Optional URL launched by the default lite-touchpoint action when
  /// [onAction] is null. Only used by the lite variant.
  final String? actionUrl;

  const ConversionGuideRow({
    super.key,
    required this.icon,
    this.iconColor,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onAction,
    required this.guideId,
    this.serverConnected = true,
    this.variant = ConversionGuideVariant.full,
    this.actionUrl,
  });

  /// Reset session-scoped dismissals for clean test runs.
  @visibleForTesting
  static void resetDismissedGuides() {
    _ConversionGuideRowState._dismissedGuides.clear();
  }

  @override
  State<ConversionGuideRow> createState() => _ConversionGuideRowState();
}

class _ConversionGuideRowState extends State<ConversionGuideRow> {
  static final Set<String> _dismissedGuides = {};
  bool _dismissed = false;
  bool _exposureEmitted = false;

  @override
  void initState() {
    super.initState();
    _dismissed = _dismissedGuides.contains(widget.guideId);
    if (!_dismissed) {
      // Fire exposure after the first frame so we know the row actually
      // entered the widget tree (avoids counting overlays that were
      // culled during build).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_exposureEmitted && mounted && !_dismissed) {
          _exposureEmitted = true;
          TelemetryService.instance.logTouchpointExposed(
            widget.guideId,
            serverConnected: widget.serverConnected,
          );
        }
      });
    }
  }

  void _handleAction() {
    TelemetryService.instance.logTouchpointClick(
      widget.guideId,
      serverConnected: widget.serverConnected,
      targetUrl: widget.actionUrl,
    );
    widget.onAction?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final colors = context.themeColors;
    final isLite = widget.variant == ConversionGuideVariant.lite;

    final surfaceColor = (isLite ? colors.accentBlue : colors.accentBlue)
        .withValues(alpha: isLite ? 0.04 : 0.06);
    final borderColor = colors.accentBlue.withValues(
      alpha: isLite ? 0.10 : 0.15,
    );

    return Container(
      margin: const EdgeInsets.only(top: AppDesignSystem.space2),
      padding: EdgeInsets.all(
        isLite ? AppDesignSystem.space2 : AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            widget.icon,
            size: isLite ? 16 : 18,
            color: widget.iconColor ?? colors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: AppDesignSystem.fontWeightSemibold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space0_5),
                Text(
                  widget.description,
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textSecondary,
                    fontSize: isLite ? 10 : 11,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space1_5),
                InkWell(
                  onTap: _handleAction,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space2,
                      vertical: AppDesignSystem.space0_5,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colors.accentBlue.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    child: Text(
                      widget.actionLabel,
                      style: AppTextStyles.caption.copyWith(
                        color: colors.accentBlue,
                        fontWeight: AppDesignSystem.fontWeightMedium,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          InkWell(
            onTap: () {
              setState(() {
                _dismissed = true;
                _dismissedGuides.add(widget.guideId);
              });
            },
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(LucideIcons.x, size: 14, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
