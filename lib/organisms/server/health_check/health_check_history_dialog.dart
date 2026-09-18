//! Run-history dialog for a single health check task (U06 — health failure
//! visibility). The task list dialog only inlines the newest 5 rows; this
//! dialog fetches a wider window (50) and surfaces the per-run error text on
//! failed rows (server migration 014). Mirrors `drift_run_history_dialog`'s
//! shape (header + FutureBuilder list + status chips).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/health_summary.dart';
import '../../../services/health_api_service.dart';
import '../../../theme/app_colors.dart';
import 'health_metrics_summary.dart';

/// How many runs to fetch. Mirrors the server's default limit for history
/// lists (50, capped at 200) — enough for a "why did it fail last night"
/// scroll without pulling the full retention window.
const int _historyLimit = 50;

/// Shows the run-history dialog for [task].
Future<void> showHealthCheckHistoryDialog(
  BuildContext context, {
  required HealthApiService api,
  required HealthTask task,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 640,
        height: 540,
        child: _HealthCheckHistoryDialog(api: api, task: task),
      ),
    ),
  );
}

class _HealthCheckHistoryDialog extends StatefulWidget {
  final HealthApiService api;
  final HealthTask task;

  const _HealthCheckHistoryDialog({required this.api, required this.task});

  @override
  State<_HealthCheckHistoryDialog> createState() =>
      _HealthCheckHistoryDialogState();
}

class _HealthCheckHistoryDialogState extends State<_HealthCheckHistoryDialog> {
  Future<List<HealthCheckResultDto>>? _future;

  /// U17：加载更多——初始 50 步进到 server clamp 上限 200（此前固定 50 静默
  /// 截断）。
  int _limit = _historyLimit;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final future = widget.api.listHealthResults(widget.task.id, limit: _limit);
    // 关闭对话框时在途请求的拒绝无监听者 → unhandled zone error（灰屏事故同类加固）。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  void _loadMore() {
    final future = widget.api.listHealthResults(
      widget.task.id,
      limit: _limit + _historyLimit,
    );
    future.ignore();
    setState(() {
      _limit += _historyLimit;
      _future = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space3),
          child: Row(
            children: [
              Icon(LucideIcons.history, color: colors.accentBlue, size: 22),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.healthHistoryTitle,
                      style: AppTextStyles.h3.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      widget.task.name,
                      style: AppTextStyles.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.healthRefresh,
                icon: const Icon(LucideIcons.refreshCw, size: 20),
                onPressed: _refresh,
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                icon: const Icon(LucideIcons.x),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Body
        Expanded(
          child: FutureBuilder<List<HealthCheckResultDto>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final msg = snapshot.error is HealthApiException
                    ? (snapshot.error as HealthApiException).message
                    : snapshot.error.toString();
                return _CenteredMessage(
                  icon: LucideIcons.circleAlert,
                  color: colors.error,
                  message: msg,
                  actionLabel: l10n.healthRefresh,
                  onAction: _refresh,
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return _CenteredMessage(
                  icon: LucideIcons.history,
                  color: colors.textSecondary,
                  message: l10n.healthNoResults,
                );
              }
              return Scrollbar(
                child: ListView.separated(
                  // 恰好取满 limit 才可能还有下一页（server clamp 200 后
                  // 不足 _limit 即止）。
                  itemCount: rows.length + (rows.length >= _limit ? 1 : 0),
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: colors.borderSubtle,
                  ),
                  itemBuilder: (context, i) {
                    if (i == rows.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDesignSystem.space2,
                        ),
                        child: Center(
                          child: TextButton.icon(
                            onPressed: _loadMore,
                            icon: const Icon(LucideIcons.chevronDown, size: 18),
                            label: Text(l10n.historyLoadMore),
                          ),
                        ),
                      );
                    }
                    return _historyRow(rows[i], l10n);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _historyRow(HealthCheckResultDto r, AppLocalizations l10n) {
    final colors = context.themeColors;
    final dt = DateTime.tryParse(r.startedAt)?.toLocal();
    final alerts = r.alertChanges.where((c) => c.trigger == 'alert').length;
    final conn = r.metrics?.connectivity;
    final latency = conn?.latencyMs;
    final metrics = r.metrics;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusIcon(r.status, colors),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                dt != null ? _formatTimestamp(dt) : r.startedAt,
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              _triggerChip(r.triggeredBy, l10n, colors),
              const Spacer(),
              if (latency != null && r.status != 'failed')
                Text(
                  l10n.healthLatencyMs(latency),
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              if (alerts > 0) ...[
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  l10n.healthAlertsCount(alerts),
                  style: AppTextStyles.caption.copyWith(color: colors.warning),
                ),
              ],
            ],
          ),
          if (r.error != null && r.error!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: AppDesignSystem.space3 + 2,
                top: AppDesignSystem.space1,
              ),
              child: Text(
                l10n.healthHistoryError(r.error!),
                style: AppTextStyles.caption.copyWith(color: colors.error),
              ),
            ),
          // Failed rows have no metrics payload ('{}'); only render the
          // breakdown when there is something to show.
          if (metrics != null && r.status != 'failed')
            Padding(
              padding: const EdgeInsets.only(top: AppDesignSystem.space2),
              child: HealthMetricsSummary(metrics: metrics),
            ),
        ],
      ),
    );
  }

  Widget _statusIcon(String status, ThemeColors colors) {
    final (icon, color) = switch (status) {
      'success' => (LucideIcons.circleCheckBig, colors.success),
      'partial' => (LucideIcons.triangleAlert, colors.warning),
      'failed' => (LucideIcons.circleAlert, colors.error),
      _ => (LucideIcons.circleHelp, colors.textSecondary),
    };
    return Icon(icon, color: color, size: 18);
  }

  Widget _triggerChip(
    String triggeredBy,
    AppLocalizations l10n,
    ThemeColors colors,
  ) {
    final isManual = triggeredBy.startsWith('manual');
    final label = isManual
        ? l10n.healthTriggerManual
        : l10n.healthTriggerScheduler;
    final icon = isManual ? LucideIcons.pointer : LucideIcons.clock;
    final color = colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }
}

class _CenteredMessage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _CenteredMessage({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: color.withValues(alpha: 0.6)),
          const SizedBox(height: AppDesignSystem.space3),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: color),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppDesignSystem.space3),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
