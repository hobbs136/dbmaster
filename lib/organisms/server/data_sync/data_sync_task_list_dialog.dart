//! Data Sync 服务端任务列表面板（二期）。
//!
//! 展示 Server 上所有 `task_type == 'data_sync'` 的任务：状态、cron、上次
//! 运行时间；running 任务显示进度条 + 已处理行数 + cursor。操作：立即运行、
//! 取消、查看历史、删除。running 任务每 3 秒轮询进度，全部完成后自动停止。
//!
//! 模板：drift_task_list_dialog.dart（FutureBuilder + RefreshIndicator）。
//! 区别：data_sync 有真实 progress（0..100），需要 Timer.periodic 轮询；
//! drift 只有 lastStatus 字符串，靠 5s 单次延迟刷新。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/data_sync_api_models.dart';
import 'package:dbmaster/pro/data_sync/data_sync_dialog.dart';
import 'package:dbmaster/services/data_sync_api_service.dart';
import 'package:dbmaster/theme/app_colors.dart';
import 'package:dbmaster/theme/design_system.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'data_sync_run_history_dialog.dart';
import '../task_edit_dialog.dart';

/// 打开 data_sync 任务列表面板。
Future<void> showDataSyncTaskListDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const Dialog(
      child: SizedBox(
        width: 900,
        height: 600,
        child: _DataSyncTaskListDialog(),
      ),
    ),
  );
}

class _DataSyncTaskListDialog extends StatefulWidget {
  const _DataSyncTaskListDialog();

  @override
  State<_DataSyncTaskListDialog> createState() =>
      _DataSyncTaskListDialogState();
}

class _DataSyncTaskListDialogState extends State<_DataSyncTaskListDialog> {
  late final DataSyncApiService _api;
  Future<List<DataSyncTask>>? _future;
  List<DataSyncTask> _lastTasks = const [];
  final Map<String, DataSyncRunStatus> _latestRuns = {};
  Timer? _pollTimer;
  final Set<String> _actionInFlight = {}; // taskId 正在执行 run/cancel/delete

  @override
  void initState() {
    super.initState();
    _api = DataSyncApiService();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    // Not connected: build() renders the not-connected message and
    // short-circuits before FutureBuilder can consume `_future`, so skip the
    // round-trip — it would only reject and leave an unhandled Future error.
    if (!_api.isConnected) return;
    final future = _api.listTasks().then((tasks) {
      _lastTasks = tasks;
      // P1-3：收敛 _latestRuns——删掉已不存在的任务 id，避免反复创建/删除
      // 任务时 map 无界增长（面板长期开着才显现；关闭时整体 dispose 释放）。
      final liveIds = tasks.map((t) => t.id).toSet();
      _latestRuns.removeWhere((id, _) => !liveIds.contains(id));
      // 启动/重启轮询（基于当前任务集）。对话框已关闭时不再起 Timer
      // （dispose 已跑过，Timer 只能靠回调里的 !mounted 自灭）。
      if (mounted) _startPollingIfNeeded();
      return tasks;
    });
    // 关闭面板时在途请求的拒绝没有 FutureBuilder 监听者，会变成 unhandled
    // zone error 打到 ErrorBoundary（2026-08-22 灰屏卡死事故的触发路径：
    // 关闭后在途 listTasks 收到 401）。ignore() 只兜无监听者的错误，
    // FutureBuilder 自身的监听与错误分支不受影响。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  /// 每 3 秒轮询所有任务的最新 run。全部 done 后停止以节省请求。
  void _startPollingIfNeeded() {
    _pollTimer?.cancel();
    if (_lastTasks.isEmpty) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) {
        _pollTimer?.cancel();
        return;
      }
      var anyRunning = false;
      for (final task in _lastTasks) {
        try {
          final runs = await _api.listRuns(task.id, limit: 1);
          if (runs.isNotEmpty) {
            final run = runs.first;
            if (run.isRunning) anyRunning = true;
            if (mounted) {
              setState(() => _latestRuns[task.id] = run);
            }
          }
        } catch (_) {
          // 单个任务轮询失败不中断整体（可能是 entitlement gate / 网络抖动）。
        }
      }
      // 全部 done → 停止轮询（下次手动 _refresh 会重启）
      if (!anyRunning) {
        _pollTimer?.cancel();
      }
    });
  }

  Future<void> _runNow(DataSyncTask task) async {
    setState(() => _actionInFlight.add(task.id));
    try {
      await _api.runTaskNow(task.id);
      // 立即重启轮询以捕获 running 状态
      _startPollingIfNeeded();
    } on DataSyncApiEntitlementException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l10n.dataSyncServerEntitlementGated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(task.id));
    }
  }

  Future<void> _cancelTask(DataSyncTask task) async {
    setState(() => _actionInFlight.add(task.id));
    try {
      await _api.cancelTask(task.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_l10n.dataSyncTaskCancelRequested)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _actionInFlight.remove(task.id));
    }
  }

  Future<void> _deleteTask(DataSyncTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.dataSyncTaskDelete),
        content: Text(_l10n.dataSyncTaskDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_l10n.dataSyncTaskDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _actionInFlight.add(task.id));
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
      if (mounted) setState(() => _actionInFlight.remove(task.id));
    }
  }

  Future<void> _toggleEnabled(DataSyncTask task) async {
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

  Future<void> _editTask(DataSyncTask task) async {
    final patched = await showTaskEditDialog(
      context,
      taskName: task.name,
      initialEnabled: task.enabled,
      scheduleField: TaskScheduleField.cronOptional,
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

  Future<void> _createTask() async {
    // Reuse the full DataSyncDialog — it is already wired to POST /api/tasks
    // with source/target/join/strategy config + entitlement handling. Opening
    // with no preset lets the user pick source + target inside the dialog.
    await DataSyncDialog.show(context);
    // DataSyncDialog manages its own submit + SnackBar; re-list on return to
    // surface the new row (a harmless no-op refresh if the user cancelled).
    _refresh();
  }

  AppLocalizations get _l10n => AppLocalizations.of(context)!;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Row(
            children: [
              Expanded(
                child: Text(
                  _l10n.dataSyncTaskListTitle,
                  style: AppTextStyles.h3.copyWith(
                    color: context.themeColors.textPrimary,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _createTask,
                icon: const Icon(LucideIcons.plus, size: 18),
                label: Text(_l10n.dataSyncCreateTaskButton),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw),
                tooltip: _l10n.dataSyncRefresh,
                onPressed: _refresh,
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: AppDesignSystem.space2),
          // 列表区
          Expanded(
            child: !_api.isConnected
                ? _centeredMessage(_l10n.dataSyncNotConnected, colors)
                : FutureBuilder<List<DataSyncTask>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        final msg = snapshot.error is DataSyncApiException
                            ? (snapshot.error as DataSyncApiException).message
                            : snapshot.error.toString();
                        return _centeredMessage(msg, colors);
                      }
                      final tasks = snapshot.data ?? const [];
                      if (tasks.isEmpty) {
                        return _centeredMessage(
                          _l10n.dataSyncTaskListEmpty,
                          colors,
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: () async => _refresh(),
                        child: ListView.separated(
                          itemCount: tasks.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: colors.borderSubtle,
                          ),
                          itemBuilder: (context, i) =>
                              _taskRow(tasks[i], colors),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _taskRow(DataSyncTask task, ThemeColors colors) {
    final run = _latestRuns[task.id];
    final isRunning = run?.isRunning ?? false;
    final inFlight = _actionInFlight.contains(task.id);
    final taskName =
        '${task.config['source']?['table'] ?? '?'} → '
        '${task.config['target']?['table'] ?? '?'}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：状态图标 + 任务名 + 操作按钮
          Row(
            children: [
              _statusIcon(run?.status, colors),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taskName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _rowSubtitle(task, run),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // 操作按钮
              if (inFlight)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                IconButton(
                  icon: Icon(
                    task.enabled
                        ? LucideIcons.circlePause
                        : LucideIcons.circlePlay,
                    size: 18,
                    color: task.enabled ? colors.warning : colors.accentBlue,
                  ),
                  tooltip: task.enabled
                      ? _l10n.taskTogglePauseTooltip
                      : _l10n.taskToggleResumeTooltip,
                  onPressed: () => _toggleEnabled(task),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    LucideIcons.pencil,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  tooltip: _l10n.taskEditTooltip,
                  onPressed: () => _editTask(task),
                  visualDensity: VisualDensity.compact,
                ),
                if (isRunning)
                  IconButton(
                    icon: Icon(
                      LucideIcons.circleStop,
                      size: 18,
                      color: colors.error,
                    ),
                    tooltip: _l10n.dataSyncTaskCancel,
                    onPressed: () => _cancelTask(task),
                    visualDensity: VisualDensity.compact,
                  )
                else
                  IconButton(
                    icon: Icon(
                      LucideIcons.play,
                      size: 20,
                      color: colors.success,
                    ),
                    tooltip: _l10n.dataSyncTaskRun,
                    onPressed: () => _runNow(task),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  icon: Icon(
                    LucideIcons.history,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  tooltip: _l10n.dataSyncTaskHistory,
                  onPressed: () =>
                      showDataSyncRunHistoryDialog(context, task.id, taskName),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  tooltip: _l10n.dataSyncTaskDelete,
                  onPressed: () => _deleteTask(task),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          // 第二行：进度条（仅 running 时）
          if (isRunning && run != null) ...[
            const SizedBox(height: AppDesignSystem.space1),
            LinearProgressIndicator(
              value: (run.progress / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: colors.bgTertiary,
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Text(
              '${_l10n.dataSyncRunProgress(run.progress)} · '
              '${_l10n.dataSyncRunRowsOnly(run.processedRows)}'
              '${run.cursor != null ? ' · cursor: ${run.cursor}' : ''}',
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  String _rowSubtitle(DataSyncTask task, DataSyncRunStatus? run) {
    final parts = <String>[];
    if (task.cronExpr.isNotEmpty) {
      parts.add('cron: ${task.cronExpr}');
    } else {
      parts.add(_l10n.dataSyncScheduleImmediate);
    }
    if (!task.enabled) {
      parts.add('(${_l10n.dataSyncTaskPaused})');
    }
    if (run == null) {
      parts.add(_l10n.dataSyncTaskNeverRun);
    } else {
      parts.add(_statusLabel(run.status));
      if (run.processedRows > 0) {
        parts.add(_l10n.dataSyncRunRowsOnly(run.processedRows));
      }
    }
    return parts.join(' · ');
  }

  Widget _statusIcon(String? status, ThemeColors colors) {
    switch (status) {
      case 'succeeded':
        return Icon(
          LucideIcons.circleCheckBig,
          size: 16,
          color: colors.success,
        );
      case 'failed':
        return Icon(LucideIcons.circleAlert, size: 16, color: colors.error);
      case 'running':
        return Icon(LucideIcons.hourglass, size: 16, color: colors.warning);
      case 'canceled':
        return Icon(
          LucideIcons.circlePause,
          size: 16,
          color: colors.textSecondary,
        );
      default:
        return Icon(LucideIcons.circle, size: 16, color: colors.textSecondary);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'running':
        return _l10n.dataSyncStatusRunning;
      case 'succeeded':
        return _l10n.dataSyncStatusSucceeded;
      case 'failed':
        return _l10n.dataSyncStatusFailed;
      case 'canceled':
        return _l10n.dataSyncStatusCanceled;
      default:
        return status;
    }
  }

  /// 居中消息（用 ListView 兼容 RefreshIndicator 的可滚动要求）。
  Widget _centeredMessage(String message, ThemeColors colors) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppDesignSystem.space4),
            child: Text(
              message,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
