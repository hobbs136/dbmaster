//! Health check task list + recent results dialog (ADR-0004 client integration).
//!
//! Mirrors `drift_task_list_dialog.dart`'s shape (Dialog + RefreshIndicator +
//! FutureBuilder + per-task rows + Run now) plus a create-task entry (header
//! Add button + empty-state CTA → `showHealthCheckCreateTaskDialog`). Each row
//! surfaces the inferred status + last results, with an expandable detail list.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/health_summary.dart';
import '../../../services/health_api_service.dart';
import '../../../theme/app_colors.dart';
import 'health_check_create_task_dialog.dart';
import 'health_check_history_dialog.dart';
import 'health_metrics_summary.dart';
import '../task_edit_dialog.dart';

/// Open the health check task list dialog. [api] is injectable for tests;
/// production callers omit it and the dialog builds its own service.
Future<void> showHealthCheckTaskListDialog(
  BuildContext context, {
  HealthApiService? api,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _HealthCheckTaskListDialog(api: api),
  );
}

class _HealthData {
  final List<HealthTask> tasks;
  final Map<String, List<HealthCheckResultDto>> resultsByTaskId;
  const _HealthData(this.tasks, this.resultsByTaskId);
}

class _HealthCheckTaskListDialog extends StatefulWidget {
  final HealthApiService? api;
  const _HealthCheckTaskListDialog({this.api});
  @override
  State<_HealthCheckTaskListDialog> createState() =>
      _HealthCheckTaskListDialogState();
}

class _HealthCheckTaskListDialogState
    extends State<_HealthCheckTaskListDialog> {
  late final HealthApiService _api = widget.api ?? HealthApiService();
  Future<_HealthData>? _future;
  final Set<String> _runningTaskIds = {};
  final Set<String> _deletingTaskIds = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    final future = _loadAll();
    // 关闭对话框时在途请求的拒绝无 FutureBuilder 监听者 → unhandled zone
    // error 打到 ErrorBoundary（2026-08-22 灰屏事故同类加固）。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  Future<_HealthData> _loadAll() async {
    final tasks = await _api.listHealthTasks();
    final byTask = <String, List<HealthCheckResultDto>>{};
    // Fan out per-task fetches concurrently; a single failure is logged + skipped
    // (mirrors HealthCheckProvider._doRefresh's tolerance).
    await Future.wait(
      tasks.map((t) async {
        try {
          byTask[t.id] = await _api.listHealthResults(t.id, limit: 10);
        } catch (e) {
          _api.logError('listHealthResults(${t.id})', e);
        }
      }),
    );
    return _HealthData(tasks, byTask);
  }

  Future<void> _runNow(HealthTask task) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _runningTaskIds.add(task.id));
    try {
      await _api.runTaskNow(task.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.healthRunQueued),
          duration: const Duration(seconds: 2),
        ),
      );
      // Give the runner time to persist a result row, then refresh once.
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) _refresh();
      });
    } catch (e) {
      _api.logError('runTaskNow(${task.id})', e);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.healthRefreshFailed)));
    } finally {
      if (mounted) setState(() => _runningTaskIds.remove(task.id));
    }
  }

  Future<void> _createTask() async {
    final created = await showHealthCheckCreateTaskDialog(context, api: _api);
    if (created != null) {
      _refresh();
    }
  }

  Future<void> _toggleEnabled(HealthTask task) async {
    try {
      await _api.setEnabled(task.id, !task.enabled);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteTask(HealthTask task) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.taskDeleteTooltip),
        content: Text(l10n.taskDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.healthClose),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.taskDeleteTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deletingTaskIds.add(task.id));
    try {
      await _api.deleteTask(task.id);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _deletingTaskIds.remove(task.id));
    }
  }

  Future<void> _editTask(HealthTask task) async {
    final patched = await showTaskEditDialog(
      context,
      taskName: task.name,
      initialEnabled: task.enabled,
      scheduleField: TaskScheduleField.cron,
      initialCronExpr: task.cronExpr,
      initialWebhook: task.notifyChannels.isNotEmpty
          ? task.notifyChannels.first
          : '',
      onPatch: ({enabled, name, cronExpr, notifyChannels}) => _api.patchTask(
        task.id,
        enabled: enabled,
        name: name,
        cronExpr: cronExpr,
        notifyChannels: notifyChannels,
      ),
    );
    if (patched == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Dialog(
      child: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          children: [
            _header(l10n),
            const Divider(height: 1),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: FutureBuilder<_HealthData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return _loadingView(l10n);
                    }
                    if (snapshot.hasError) {
                      return _errorView(l10n);
                    }
                    final data = snapshot.data!;
                    if (data.tasks.isEmpty) return _emptyView(l10n);
                    return _taskList(data, l10n);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space4,
        vertical: AppDesignSystem.space3,
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.heartPulse,
            size: 20,
            color: context.themeColors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.healthDialogTitle, style: AppTextStyles.bodyLarge),
                Text(
                  l10n.healthDialogSubtitle,
                  style: AppTextStyles.caption.copyWith(
                    color: context.themeColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            tooltip: l10n.healthRefresh,
            onPressed: _refresh,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: _createTask,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text(l10n.healthCreateTaskButton),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 18),
            tooltip: l10n.healthClose,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  // Keep loading/error/empty scrollable so RefreshIndicator still works.
  Widget _loadingView(AppLocalizations l10n) => ListView(
    children: [
      const SizedBox(height: 80),
      Center(child: Text(l10n.healthLoading)),
    ],
  );

  Widget _errorView(AppLocalizations l10n) => ListView(
    children: [
      const SizedBox(height: 60),
      Icon(LucideIcons.circleAlert, size: 36, color: context.themeColors.error),
      const SizedBox(height: 8),
      Center(child: Text(l10n.healthRefreshFailed)),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: _refresh,
          icon: const Icon(LucideIcons.refreshCw, size: 16),
          label: Text(l10n.healthRefresh),
        ),
      ),
    ],
  );

  Widget _emptyView(AppLocalizations l10n) => ListView(
    children: [
      const SizedBox(height: 60),
      Icon(LucideIcons.inbox, size: 36, color: context.themeColors.textMuted),
      const SizedBox(height: 8),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            l10n.healthNoTasks,
            textAlign: TextAlign.center,
            style: AppTextStyles.body,
          ),
        ),
      ),
      const SizedBox(height: 4),
      Center(
        child: Text(
          l10n.healthNoTasksHint,
          style: AppTextStyles.caption.copyWith(
            color: context.themeColors.textMuted,
          ),
        ),
      ),
      const SizedBox(height: AppDesignSystem.space4),
      Center(
        child: ElevatedButton.icon(
          onPressed: _createTask,
          icon: const Icon(LucideIcons.plus, size: 18),
          label: Text(l10n.healthCreateTaskButton),
        ),
      ),
    ],
  );

  Widget _taskList(_HealthData data, AppLocalizations l10n) {
    return ListView.separated(
      itemCount: data.tasks.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = data.tasks[i];
        final results =
            data.resultsByTaskId[t.id] ?? const <HealthCheckResultDto>[];
        return _taskRow(t, results, l10n);
      },
    );
  }

  Widget _taskRow(
    HealthTask task,
    List<HealthCheckResultDto> results,
    AppLocalizations l10n,
  ) {
    // U06 — the task row's last_status backstops the results window (rotated
    // rows / a failed per-task fetch must not read as "unknown").
    final summary = inferHealthSummary(
      results,
      taskLastStatus: task.lastStatus,
      taskLastRunAt: task.lastRunAt,
    );
    final colors = context.themeColors;
    final running = _runningTaskIds.contains(task.id);
    final latest = results.isEmpty ? null : results.first;
    return ExpansionTile(
      initiallyExpanded: false,
      tilePadding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: 0,
      ),
      title: Row(
        children: [
          // status dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _statusColor(colors, summary.status),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(task.name, style: AppTextStyles.body),
                Text(
                  summary.lastRunAt != null
                      ? '${l10n.healthColumnLastCheck}: ${_ago(l10n, summary.lastRunAt!)}'
                      : l10n.healthNoResults,
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _statusLabel(l10n, summary.status),
            style: AppTextStyles.caption.copyWith(
              color: _statusColor(colors, summary.status),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(right: AppDesignSystem.space1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                task.enabled ? LucideIcons.circlePause : LucideIcons.circlePlay,
                size: 18,
              ),
              color: task.enabled ? colors.warning : colors.accentBlue,
              tooltip: task.enabled
                  ? l10n.taskTogglePauseTooltip
                  : l10n.taskToggleResumeTooltip,
              onPressed: () => _toggleEnabled(task),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(LucideIcons.pencil, size: 18),
              tooltip: l10n.taskEditTooltip,
              onPressed: () => _editTask(task),
              visualDensity: VisualDensity.compact,
            ),
            if (_deletingTaskIds.contains(task.id))
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: Icon(
                  LucideIcons.trash2,
                  size: 18,
                  color: colors.textSecondary,
                ),
                tooltip: l10n.taskDeleteTooltip,
                onPressed: () => _deleteTask(task),
                visualDensity: VisualDensity.compact,
              ),
            if (running)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton(
                onPressed: () => _runNow(task),
                child: Text(l10n.healthRunNow),
              ),
          ],
        ),
      ),
      children: [
        if (results.isEmpty)
          ListTile(
            dense: true,
            title: Text(
              l10n.healthNoResults,
              style: AppTextStyles.caption.copyWith(color: colors.textMuted),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space4,
              vertical: AppDesignSystem.space2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in results.take(5)) _resultLine(r, l10n),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => showHealthCheckHistoryDialog(
                      context,
                      api: _api,
                      task: task,
                    ),
                    icon: const Icon(LucideIcons.history, size: 16),
                    label: Text(l10n.healthViewAllHistory),
                  ),
                ),
              ],
            ),
          ),
        // cron + connection id footer
        Padding(
          padding: const EdgeInsets.only(
            left: AppDesignSystem.space4,
            right: AppDesignSystem.space4,
            bottom: AppDesignSystem.space2,
          ),
          child: Text(
            'cron: ${task.cronExpr.isEmpty ? "—" : task.cronExpr}   ·   '
            '${l10n.healthColumnConnection}: ${task.sourceDbId}',
            style: AppTextStyles.code.copyWith(
              color: colors.textMuted,
              fontSize: AppDesignSystem.fontSizeXs,
            ),
          ),
        ),
        if (latest != null && latest.metrics != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space3),
            child: HealthMetricsSummary(metrics: latest.metrics!),
          ),
      ],
    );
  }

  Widget _resultLine(HealthCheckResultDto r, AppLocalizations l10n) {
    final colors = context.themeColors;
    final dt = DateTime.tryParse(r.startedAt);
    final alerts = r.alertChanges.where((c) => c.trigger == 'alert').length;
    final conn = r.metrics?.connectivity;
    final latency = conn?.latencyMs;
    final hasError = r.error != null && r.error!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _resultBadge(r.status, l10n),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                dt != null ? _ago(l10n, dt) : r.startedAt,
                style: AppTextStyles.caption.copyWith(color: colors.textMuted),
              ),
              const SizedBox(width: AppDesignSystem.space2),
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
          // U06 — surface the redacted failure reason inline (single line;
          // the full text lives in the history dialog).
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(left: AppDesignSystem.space2),
              child: Text(
                l10n.healthHistoryError(r.error!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption.copyWith(color: colors.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultBadge(String status, AppLocalizations l10n) {
    final colors = context.themeColors;
    final (label, color) = switch (status) {
      'success' => (l10n.healthResultSuccess, colors.success),
      'partial' => (l10n.healthResultPartial, colors.warning),
      'failed' => (l10n.healthResultFailed, colors.error),
      _ => (status, colors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(color: color, fontSize: 10),
      ),
    );
  }

  // ── helpers ──

  Color _statusColor(ThemeColors c, HealthStatus s) => switch (s) {
    HealthStatus.healthy => c.success,
    HealthStatus.warning => c.warning,
    HealthStatus.critical => c.error,
    HealthStatus.unknown => c.textMuted,
  };

  String _statusLabel(AppLocalizations l, HealthStatus s) => switch (s) {
    HealthStatus.healthy => l.healthStatusHealthy,
    HealthStatus.warning => l.healthStatusWarning,
    HealthStatus.critical => l.healthStatusCritical,
    HealthStatus.unknown => l.healthStatusUnknown,
  };

  String _ago(AppLocalizations l, DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.isNegative || d.inMinutes < 1) return l.healthAgoJustNow;
    if (d.inMinutes < 60) return l.healthAgoMinutes(d.inMinutes);
    if (d.inHours < 24) return l.healthAgoHours(d.inHours);
    return l.healthAgoDays(d.inDays);
  }
}
