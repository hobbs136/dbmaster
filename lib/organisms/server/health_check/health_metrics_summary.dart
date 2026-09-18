//! Shared metrics-summary card for health check results (ADR-0004 client
//! integration). Extracted from the task list dialog so the history dialog
//! (U06) can render the same per-run metrics breakdown.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/health_summary.dart';
import '../../../theme/app_colors.dart';

/// Compact 4-row metric breakdown of one [MetricsSnapshot] (connectivity /
/// connection count / missing-PK / top table). Callers fold it under a result
/// row or an expansion tile.
class HealthMetricsSummary extends StatelessWidget {
  final MetricsSnapshot metrics;

  const HealthMetricsSummary({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final m = metrics;
    final rows = <_MetricRow>[
      _MetricRow(l10n.healthMetricConnectivity, [
        Icon(
          m.connectivity.ok ? LucideIcons.check : LucideIcons.x,
          size: 12,
          color: m.connectivity.ok ? colors.success : colors.error,
        ),
        const SizedBox(width: AppDesignSystem.space1),
        Text(l10n.healthLatencyMs(m.connectivity.latencyMs)),
      ]),
      if (m.connectionCount != null)
        _MetricRow(l10n.healthMetricConnectionCount, [
          Text('${m.connectionCount}'),
        ]),
      if (m.missingPkTables != null)
        _MetricRow(l10n.healthMetricMissingPk, [
          Text('${m.missingPkTables!.length}'),
        ]),
      if (m.topTables != null && m.topTables!.isNotEmpty)
        _MetricRow(l10n.healthMetricRowCount, [
          Text(
            '${m.topTables!.first.table} '
            '(${m.topTables!.first.estimatedRows})',
          ),
        ]),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2,
        0,
        AppDesignSystem.space2,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppDesignSystem.space2),
        decoration: BoxDecoration(
          color: colors.bgSecondary.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        r.label,
                        style: AppTextStyles.caption.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    Expanded(
                      child: DefaultTextStyle(
                        style: AppTextStyles.code.copyWith(
                          color: colors.textPrimary,
                          fontSize: AppDesignSystem.fontSizeXs,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: r.value,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow {
  final String label;
  final List<Widget> value;
  const _MetricRow(this.label, this.value);
}
