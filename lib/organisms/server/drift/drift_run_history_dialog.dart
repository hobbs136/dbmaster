//! Run-history dialog for a single drift task. Lists `task_run_history` rows
//! with parsed summary fields (drift count, webhook status, duration) and a
//! "View Diff" affordance on rows that detected drift.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/rfc3339.dart';
import '../../../models/drift_models.dart';
import '../../../services/drift_api_service.dart';
import '../../../theme/app_colors.dart';
import 'drift_diff_page.dart';

/// Shows the run-history dialog for [task]. [connection] is the source
/// connection the task points at — needed to open the diff viewer.
Future<void> showDriftRunHistoryDialog(
  BuildContext context, {
  required DriftApiService api,
  required DriftTask task,
  required DriftSourceConnection connection,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.7,
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: _DriftRunHistoryDialog(
          api: api,
          task: task,
          connection: connection,
        ),
      ),
    ),
  );
}

class _DriftRunHistoryDialog extends StatefulWidget {
  final DriftApiService api;
  final DriftTask task;
  final DriftSourceConnection connection;

  const _DriftRunHistoryDialog({
    required this.api,
    required this.task,
    required this.connection,
  });

  @override
  State<_DriftRunHistoryDialog> createState() => _DriftRunHistoryDialogState();
}

class _DriftRunHistoryDialogState extends State<_DriftRunHistoryDialog> {
  late Future<List<DriftRunHistoryEntry>> _future;

  // U17：加载更多（此前固定 50 条静默截断；server 端 clamp 上限 200）。
  int _limit = 50;

  @override
  void initState() {
    super.initState();
    _future = widget.api.listRunHistory(widget.task.id, limit: _limit)
      ..ignore();
  }

  void _refresh() {
    final future = widget.api.listRunHistory(widget.task.id, limit: _limit);
    // 关闭对话框时在途请求的拒绝无监听者 → unhandled zone error（灰屏事故同类加固）。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  void _loadMore() {
    final future = widget.api.listRunHistory(
      widget.task.id,
      limit: _limit + 50,
    );
    future.ignore();
    setState(() {
      _limit += 50;
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
        Container(
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
                      l10n.driftHistoryTitle,
                      style: AppTextStyles.h3.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      '${widget.task.name} · ${widget.connection.name}',
                      style: AppTextStyles.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.driftRetry,
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
          child: FutureBuilder<List<DriftRunHistoryEntry>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final msg = snapshot.error is DriftApiException
                    ? (snapshot.error as DriftApiException).message
                    : snapshot.error.toString();
                return _CenteredMessage(
                  icon: LucideIcons.circleAlert,
                  color: colors.error,
                  message: msg,
                  actionLabel: l10n.driftRetry,
                  onAction: _refresh,
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return _CenteredMessage(
                  icon: LucideIcons.history,
                  color: colors.textSecondary,
                  message: l10n.driftStatusNever,
                );
              }
              return _historyList(rows, l10n, colors);
            },
          ),
        ),
      ],
    );
  }

  Widget _historyList(
    List<DriftRunHistoryEntry> rows,
    AppLocalizations l10n,
    ThemeColors colors,
  ) {
    // 恰好取满 limit 才可能还有下一页（正好等于时多点一次，结果不变即止）。
    final hasMore = rows.length >= _limit;
    return Scrollbar(
      child: ListView.separated(
        itemCount: rows.length + (hasMore ? 1 : 0),
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
          final row = rows[i];
          return _historyRow(row, l10n, colors);
        },
      ),
    );
  }

  Widget _historyRow(
    DriftRunHistoryEntry row,
    AppLocalizations l10n,
    ThemeColors colors,
  ) {
    final hasDrift = row.driftCount > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status icon
          _statusIcon(row.status, colors),
          const SizedBox(width: AppDesignSystem.space3),
          // Main content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _formatTimestamp(row.startedAt),
                      style: AppTextStyles.body.copyWith(
                        fontWeight: AppDesignSystem.fontWeightSemibold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    _triggerChip(row, l10n, colors),
                    const Spacer(),
                    if (row.durationMs > 0)
                      Text(
                        '${row.durationMs} ms',
                        style: AppTextStyles.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Row(
                  children: [
                    if (row.status == 'failed')
                      // U17：错误可点展开全文（此前 maxLines:2 截断）。
                      Expanded(
                        child: _ExpandableErrorText(
                          l10n.driftHistoryError(row.error ?? 'Unknown error'),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: colors.error,
                          ),
                        ),
                      )
                    else
                      _driftChip(
                        hasDrift,
                        row.driftCount,
                        l10n,
                        colors,
                        isBaseline: row.baselineSnapshotId == null,
                      ),
                    if (row.status == 'succeeded') ...[
                      const SizedBox(width: AppDesignSystem.space2),
                      _webhookChip(row.webhookStatus, colors),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (hasDrift && row.status == 'succeeded')
            TextButton.icon(
              // U09: open exactly the snapshot pair this run compared (the
              // runner writes both ids into the run summary). Legacy rows
              // without ids fall back to the "latest two" default inside the
              // diff dialog.
              onPressed: () => showDriftDiffDialog(
                context,
                api: widget.api,
                connection: widget.connection,
                initialNewerId: row.snapshotId,
                initialOlderId: row.baselineSnapshotId,
              ),
              icon: const Icon(LucideIcons.arrowRightLeft, size: 18),
              label: Text(l10n.driftViewDiffButton),
            ),
        ],
      ),
    );
  }

  Widget _statusIcon(String status, ThemeColors colors) {
    final (icon, color) = switch (status) {
      'succeeded' => (LucideIcons.circleCheckBig, colors.success),
      'failed' => (LucideIcons.circleAlert, colors.error),
      'running' => (LucideIcons.hourglass, colors.warning),
      _ => (LucideIcons.circleHelp, colors.textSecondary),
    };
    return Icon(icon, color: color, size: 20);
  }

  Widget _triggerChip(
    DriftRunHistoryEntry row,
    AppLocalizations l10n,
    ThemeColors colors,
  ) {
    final isManual = row.triggeredByKind == 'manual';
    final label = isManual
        ? l10n.driftTriggerManual
        : l10n.driftTriggerScheduler;
    final icon = isManual ? LucideIcons.pointer : LucideIcons.clock;
    return _chip(label, icon, colors.textSecondary, colors);
  }

  Widget _driftChip(
    bool hasDrift,
    int count,
    AppLocalizations l10n,
    ThemeColors colors, {
    bool isBaseline = false,
  }) {
    // U17：首次 run 建立基线（无前置快照可比）——「无漂移」对它是误导，
    // 实际上漂移检测从第二个快照才开始。
    if (isBaseline) {
      return _chip(
        l10n.driftHistoryBaseline,
        LucideIcons.flag,
        colors.accentBlue,
        colors,
      );
    }
    if (!hasDrift) {
      return _chip(
        l10n.driftHistoryNoDrift,
        LucideIcons.check,
        colors.success,
        colors,
      );
    }
    return _chip(
      l10n.driftHistoryHasDrift(count.toString()),
      LucideIcons.triangleAlert,
      colors.warning,
      colors,
    );
  }

  Widget _webhookChip(String status, ThemeColors colors) {
    final (label, color) = switch (status) {
      'ok' => ('Webhook: ok', colors.success),
      'failed' => ('Webhook: failed', colors.error),
      _ => ('Webhook: skipped', colors.textSecondary),
    };
    return _chip(label, LucideIcons.webhook, color, colors);
  }

  Widget _chip(String label, IconData icon, Color color, ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: 2,
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
          Text(label, style: AppTextStyles.caption.copyWith(color: color)),
        ],
      ),
    );
  }

  String _formatTimestamp(String iso) =>
      formatRfc3339Local(iso, withSeconds: true);
}

/// 可点展开/收起的错误文本（U17：历史行错误不再被 maxLines:2 截断）。
class _ExpandableErrorText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _ExpandableErrorText(this.text, {required this.style});

  @override
  State<_ExpandableErrorText> createState() => _ExpandableErrorTextState();
}

class _ExpandableErrorTextState extends State<_ExpandableErrorText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: _expanded ? null : 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
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
