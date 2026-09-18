//! Schema Drift Alerts task list — the hub of the Phase F desktop UI.
//!
//! Lists `scheduled_tasks` filtered to `task_type == "schema_drift"`, with
//! actions: create task, run now (queue), view run history, view diff,
//! delete. The dialog is reachable from the Server status bar's connected
//! menu (see `server_status_bar.dart`).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/rfc3339.dart';
import '../../../models/drift_models.dart';
import '../../../services/drift_api_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/app_logger.dart';
import '../../connection/error_boundary.dart';
import 'drift_create_task_dialog.dart';
import 'drift_diff_page.dart';
import 'drift_run_history_dialog.dart';
import '../task_edit_dialog.dart';

/// Shows the drift task list dialog (the entry point for the drift UI).
/// [api] is injectable for tests; defaults to a live [DriftApiService].
Future<void> showDriftTaskListDialog(
  BuildContext context, {
  DriftApiService? api,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 900,
        height: 600,
        child: _DriftTaskListDialog(api: api),
      ),
    ),
  );
}

class _DriftTaskListDialog extends StatefulWidget {
  final DriftApiService? api;

  const _DriftTaskListDialog({this.api});

  @override
  State<_DriftTaskListDialog> createState() => _DriftTaskListDialogState();
}

class _DriftTaskListDialogState extends State<_DriftTaskListDialog> {
  late final DriftApiService _api = widget.api ?? DriftApiService();
  Future<_TaskListData>? _future;
  // Manual-run in-flight tracking — drives a per-row spinner + auto-refresh.
  final Set<String> _runningTaskIds = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final future = _loadAll();
    // 关闭对话框时在途请求的拒绝无 FutureBuilder 监听者 → unhandled zone
    // error 打到 ErrorBoundary（2026-08-22 灰屏事故同类加固）。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  /// Fetch tasks and source connections in parallel so a single dialog
  /// refresh has only one round-trip's worth of latency (vs. N+1 lookups
  /// when rendering each row's source name).
  Future<_TaskListData> _loadAll() async {
    final tasks = await _api.listDriftTasks();
    final connections = await _api.listSourceDriftConnections();
    return _TaskListData(tasks: tasks, connections: connections);
  }

  Future<void> _createTask() async {
    final created = await showDriftCreateTaskDialog(context, api: _api);
    if (created != null) {
      _refresh();
    }
  }

  Future<void> _runNow(DriftTask task) async {
    setState(() => _runningTaskIds.add(task.id));
    final l10n = AppLocalizations.of(context)!;
    try {
      await _api.runTaskNow(task.id);
      if (mounted) {
        AppErrorHandler.showSuccessSnackBar(context, l10n.driftRunQueued);
        // 202 returns immediately; the actual run takes ~seconds (network to
        // source DB + canary + snapshot + diff). Poll the run to a terminal
        // state so the row reflects the real outcome instead of a blind
        // fixed-delay refresh that usually lands too early or too late.
        await _pollRunCompletion(task);
      }
    } on DriftApiException catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          e is DriftApiEntitlementException
              ? l10n.driftGatedBody
              : l10n.driftRunFailed(e.message),
        );
      }
    } catch (e) {
      AppLogger.w('DriftTaskList', 'runNow failed: $e');
    } finally {
      if (mounted) {
        setState(() => _runningTaskIds.remove(task.id));
      }
    }
  }

  /// Watches the newest run-history row until this manual run reaches a
  /// terminal state, then refreshes the task list. Bounded (2s × 30 attempts)
  /// so a wedged source DB can't spin forever; a drained budget still
  /// refreshes once — the user sees the last known state and can retry.
  Future<void> _pollRunCompletion(DriftTask task) async {
    // Anchor: the newest row counts as "this run" only when it started after
    // the previous last_run_at (both server-clock timestamps). A task that
    // never ran (null) treats any row as new.
    final anchor = DateTime.tryParse(task.lastRunAt ?? '');
    for (var attempt = 0; attempt < 30; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final rows = await _api.listRunHistory(task.id, limit: 1);
        final top = rows.firstOrNull;
        if (top == null || top.status == 'running') continue;
        final started = DateTime.tryParse(top.startedAt);
        final isNewRun =
            anchor == null || (started != null && started.isAfter(anchor));
        if (isNewRun) break;
      } on DriftApiException {
        // Transient poll failure — retry within the attempt budget.
      }
    }
    if (mounted) _refresh();
  }

  Future<void> _deleteTask(DriftTask task) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.driftDeleteTaskButton),
        content: Text('${task.name} — ${l10n.driftDeleteTaskButton}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.driftClose),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.driftDeleteTaskButton),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.deleteTask(task.id);
      _refresh();
    } on DriftApiException catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, e.message);
      }
    }
  }

  Future<void> _toggleEnabled(DriftTask task) async {
    try {
      await _api.setEnabled(task.id, !task.enabled);
      _refresh();
    } on DriftApiException catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(context, e.message);
      }
    }
  }

  Future<void> _editTask(DriftTask task) async {
    final patched = await showTaskEditDialog(
      context,
      taskName: task.name,
      initialEnabled: task.enabled,
      scheduleField: TaskScheduleField.none,
      // U17：全部 URL 逗号拼接进编辑框——此前只装载第一个，patch 整体替换
      // 会静默丢弃第 2+ 个 URL（notify_channels 是数组，wire 上支持多个）。
      initialWebhook: task.notifyChannels.join(', '),
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

  /// U09 — edit the check interval in place. The Server replaces `config`
  /// wholesale on PATCH, so we rebuild it from the parsed current config with
  /// only `interval_minutes` overridden (`pg_schemas` survives; those are the
  /// only two keys the drift scheduler/runner read).
  Future<void> _editInterval(DriftTask task) async {
    final l10n = AppLocalizations.of(context)!;
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) =>
          _DriftIntervalEditDialog(initialMinutes: task.config.intervalMinutes),
    );
    if (minutes == null) return;
    try {
      final newConfig = DriftTaskConfig(
        intervalMinutes: minutes,
        pgSchemas: task.config.pgSchemas,
      ).toJson();
      await _api.patchTaskConfig(task.id, newConfig);
      if (mounted) {
        AppErrorHandler.showSuccessSnackBar(context, l10n.driftIntervalUpdated);
        _refresh();
      }
    } on DriftApiException catch (e) {
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          e is DriftApiEntitlementException ? l10n.driftGatedBody : e.message,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        _header(l10n),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: FutureBuilder<_TaskListData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final msg = snapshot.error is DriftApiException
                      ? (snapshot.error as DriftApiException).message
                      : snapshot.error.toString();
                  return _errorView(msg, l10n);
                }
                final data = snapshot.data!;
                if (data.tasks.isEmpty) {
                  return _emptyView(data, l10n);
                }
                return _taskList(data, l10n);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(AppLocalizations l10n) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      child: Row(
        children: [
          Icon(LucideIcons.bellRing, color: colors.accentBlue, size: 18),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              l10n.driftTaskListTitle,
              style: AppTextStyles.h3.copyWith(color: colors.textPrimary),
            ),
          ),
          IconButton(
            tooltip: l10n.driftRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: _refresh,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          ElevatedButton.icon(
            onPressed: _createTask,
            icon: const Icon(LucideIcons.plus, size: 18),
            label: Text(l10n.driftCreateTaskButton),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonLabel,
            icon: const Icon(LucideIcons.x),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _errorView(String message, AppLocalizations l10n) {
    final colors = context.themeColors;
    return ListView(
      // Keep the list scrollable even with one item so RefreshIndicator works.
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Icon(
                LucideIcons.circleAlert,
                size: 48,
                color: colors.error.withValues(alpha: 0.6),
              ),
              const SizedBox(height: AppDesignSystem.space3),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space6,
                ),
                child: SelectableText(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.error),
                ),
              ),
              const SizedBox(height: AppDesignSystem.space3),
              ElevatedButton(onPressed: _refresh, child: Text(l10n.driftRetry)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyView(_TaskListData data, AppLocalizations l10n) {
    final colors = context.themeColors;
    return ListView(
      children: [
        const SizedBox(height: 60),
        Center(
          child: Column(
            children: [
              Icon(
                LucideIcons.bell,
                size: 64,
                color: colors.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: AppDesignSystem.space3),
              Padding(
                padding: const EdgeInsets.all(AppDesignSystem.space4),
                child: Text(
                  l10n.driftTaskListEmpty,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h4.copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space6,
                ),
                child: Text(
                  l10n.driftTaskListEmptyHint,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: AppDesignSystem.space4),
              ElevatedButton.icon(
                onPressed: _createTask,
                icon: const Icon(LucideIcons.plus, size: 18),
                label: Text(l10n.driftCreateTaskButton),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _taskList(_TaskListData data, AppLocalizations l10n) {
    return ListView.separated(
      itemCount: data.tasks.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: context.themeColors.borderSubtle,
      ),
      itemBuilder: (context, i) {
        final task = data.tasks[i];
        final connection = data.connections
            .where((c) => c.id == task.sourceDbId)
            .firstOrNull;
        return _taskRow(task, connection, data, l10n);
      },
    );
  }

  Widget _taskRow(
    DriftTask task,
    DriftSourceConnection? connection,
    _TaskListData data,
    AppLocalizations l10n,
  ) {
    final colors = context.themeColors;
    final isRunning = _runningTaskIds.contains(task.id);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // While a manual run is being polled, show the running state even
          // though scheduled_tasks.last_status hasn't been rewritten yet.
          _statusIcon(isRunning ? 'running' : task.lastStatus, colors),
          const SizedBox(width: AppDesignSystem.space3),
          // Name + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.name,
                        style: AppTextStyles.body.copyWith(
                          fontWeight: AppDesignSystem.fontWeightSemibold,
                          color: colors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    _intervalChip(task, l10n, colors),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space1),
                Row(
                  children: [
                    Icon(
                      LucideIcons.database,
                      size: 12,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        connection == null
                            ? task.sourceDbId
                            : '${connection.name} (${connection.hostLabel})',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (task.lastRunAt != null) ...[
                  const SizedBox(height: AppDesignSystem.space1),
                  Text(
                    '${l10n.driftColLastRun}: ${_formatTimestamp(task.lastRunAt!)}',
                    style: AppTextStyles.caption.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Actions
          _iconButton(
            tooltip: task.enabled
                ? l10n.taskTogglePauseTooltip
                : l10n.taskToggleResumeTooltip,
            icon: Icon(
              task.enabled ? LucideIcons.circlePause : LucideIcons.circlePlay,
              size: 18,
            ),
            onPressed: () => _toggleEnabled(task),
            color: task.enabled ? colors.warning : colors.accentBlue,
          ),
          _iconButton(
            tooltip: l10n.taskEditTooltip,
            icon: const Icon(LucideIcons.pencil, size: 18),
            onPressed: () => _editTask(task),
          ),
          _iconButton(
            tooltip: l10n.driftRunNowButton,
            icon: isRunning
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.play, size: 18),
            onPressed: isRunning ? null : () => _runNow(task),
          ),
          if (connection != null)
            _iconButton(
              tooltip: l10n.driftHistoryButton,
              icon: const Icon(LucideIcons.history, size: 18),
              onPressed: () => showDriftRunHistoryDialog(
                context,
                api: _api,
                task: task,
                connection: connection,
              ),
            ),
          if (connection != null)
            _iconButton(
              tooltip: l10n.driftViewDiffButton,
              icon: const Icon(LucideIcons.arrowRightLeft, size: 18),
              onPressed: () => showDriftDiffDialog(
                context,
                api: _api,
                connection: connection,
              ),
            ),
          _iconButton(
            tooltip: l10n.driftDeleteTaskButton,
            icon: const Icon(LucideIcons.trash2, size: 18),
            onPressed: () => _deleteTask(task),
            color: colors.error,
          ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required Widget icon,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return IconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      color: color,
      iconSize: 18,
    );
  }

  Widget _statusIcon(String? status, ThemeColors colors) {
    final (icon, color) = switch (status) {
      'succeeded' => (LucideIcons.circleCheckBig, colors.success),
      'failed' => (LucideIcons.circleAlert, colors.error),
      'running' => (LucideIcons.hourglass, colors.warning),
      _ => (LucideIcons.circle, colors.textSecondary),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _intervalChip(
    DriftTask task,
    AppLocalizations l10n,
    ThemeColors colors,
  ) {
    final mins = task.config.intervalMinutes;
    final label = mins == null
        ? l10n.driftIntervalUnknown
        : (mins >= 60 && mins % 60 == 0
              ? l10n.driftIntervalHours((mins ~/ 60).toString())
              : l10n.driftIntervalMinutes(mins.toString()));
    // U09 — the interval is editable in place (PATCH config); the chip is the
    // affordance. Tooltip + edit icon signal clickability without adding a
    // fourth action button to the row.
    return Tooltip(
      message: l10n.driftEditIntervalTooltip,
      child: InkWell(
        onTap: () => _editInterval(task),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: colors.accentBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: colors.accentBlue.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.clock, size: 12, color: colors.accentBlue),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(color: colors.accentBlue),
              ),
              const SizedBox(width: 4),
              Icon(LucideIcons.pencil, size: 11, color: colors.accentBlue),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(String iso) => formatRfc3339Local(iso);
}

/// Aggregated payload for the list view: tasks plus their source connections
/// (so each row can render the connection name without an N+1 lookup).
class _TaskListData {
  final List<DriftTask> tasks;
  final List<DriftSourceConnection> connections;

  const _TaskListData({required this.tasks, required this.connections});
}

/// U09 — one-field dialog for editing a drift task's check interval.
/// Validation mirrors the create dialog (1-1440 minutes, the Server clamps to
/// the same range). Pops with the parsed minutes, or null on cancel.
class _DriftIntervalEditDialog extends StatefulWidget {
  final int? initialMinutes;

  const _DriftIntervalEditDialog({this.initialMinutes});

  @override
  State<_DriftIntervalEditDialog> createState() =>
      _DriftIntervalEditDialogState();
}

class _DriftIntervalEditDialogState extends State<_DriftIntervalEditDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Prefill with the current interval; fall back to the create dialog's
    // default (5) when the task predates an explicit interval (server default
    // applies) so the user edits a concrete number.
    _controller = TextEditingController(
      text: (widget.initialMinutes ?? 5).toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(int.parse(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return AlertDialog(
      title: Row(
        children: [
          Icon(LucideIcons.clock, color: colors.accentBlue, size: 22),
          const SizedBox(width: AppDesignSystem.space2),
          Text(l10n.driftEditIntervalTitle),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.driftCreateTaskInterval,
                  prefixIcon: const Icon(LucideIcons.timer, size: 18),
                  border: const OutlineInputBorder(),
                  suffixText: 'min',
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n < 1 || n > 1440) {
                    return l10n.driftCreateTaskInvalidInterval;
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.driftClose),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(LucideIcons.save, size: 18),
          label: Text(l10n.taskEditSubmit),
        ),
      ],
    );
  }
}
