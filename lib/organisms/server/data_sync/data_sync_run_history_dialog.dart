//! Data Sync 单任务运行历史对话框（二期）。
//!
//! 展示某 task 的历次 data_sync_runs：开始时间、状态、进度、已处理/失败
//! 行数、耗时、cursor。点"历史"按钮从任务列表面板打开。
//!
//! 模板：drift_run_history_dialog.dart（FutureBuilder 四态）。

import 'package:flutter/material.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/data_sync_api_models.dart';
import 'package:dbmaster/services/data_sync_api_service.dart';
import 'package:dbmaster/theme/app_colors.dart';
import 'package:dbmaster/theme/design_system.dart';
import 'package:dbmaster/utils/rfc3339.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 打开 [taskId] 的运行历史。`taskName` 仅用于标题展示。
Future<void> showDataSyncRunHistoryDialog(
  BuildContext context,
  String taskId,
  String taskName,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: SizedBox(
        width: 700,
        height: 500,
        child: _DataSyncRunHistoryDialog(taskId: taskId, taskName: taskName),
      ),
    ),
  );
}

class _DataSyncRunHistoryDialog extends StatefulWidget {
  final String taskId;
  final String taskName;
  const _DataSyncRunHistoryDialog({
    required this.taskId,
    required this.taskName,
  });

  @override
  State<_DataSyncRunHistoryDialog> createState() =>
      _DataSyncRunHistoryDialogState();
}

class _DataSyncRunHistoryDialogState extends State<_DataSyncRunHistoryDialog> {
  late final DataSyncApiService _api;
  Future<List<DataSyncRunStatus>>? _future;

  @override
  void initState() {
    super.initState();
    _api = DataSyncApiService();
    _refresh();
  }

  /// U17：加载更多（此前固定 50 静默截断）。
  int _limit = 50;

  void _refresh() {
    final future = _api.listRuns(widget.taskId, limit: _limit);
    // 对话框关闭时在途请求的拒绝无 FutureBuilder 监听者 → unhandled zone
    // error 打到 ErrorBoundary（见 data_sync_task_list_dialog 同款注释）。
    future.ignore();
    setState(() {
      _future = future;
    });
  }

  void _loadMore() {
    final future = _api.listRuns(widget.taskId, limit: _limit + 50);
    future.ignore();
    setState(() {
      _limit += 50;
      _future = future;
    });
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _l10n.dataSyncHistoryTitle(widget.taskName),
                  style: AppTextStyles.h3.copyWith(
                    color: context.themeColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw),
                tooltip: _l10n.dataSyncRefresh,
                onPressed: _refresh,
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: AppDesignSystem.space2),
          Expanded(
            child: FutureBuilder<List<DataSyncRunStatus>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final msg = snapshot.error is DataSyncApiException
                      ? (snapshot.error as DataSyncApiException).message
                      : snapshot.error.toString();
                  return _centered(msg, colors);
                }
                final runs = snapshot.data ?? const [];
                if (runs.isEmpty) {
                  return _centered(_l10n.dataSyncHistoryEmpty, colors);
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    itemCount: runs.length + (runs.length >= _limit ? 1 : 0),
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: colors.borderSubtle,
                    ),
                    itemBuilder: (context, i) {
                      if (i == runs.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppDesignSystem.space2,
                          ),
                          child: Center(
                            child: TextButton.icon(
                              onPressed: _loadMore,
                              icon: const Icon(
                                LucideIcons.chevronDown,
                                size: 18,
                              ),
                              label: Text(_l10n.historyLoadMore),
                            ),
                          ),
                        );
                      }
                      return _runRow(runs[i], colors);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_l10n.commonClose),
            ),
          ),
        ],
      ),
    );
  }

  Widget _runRow(DataSyncRunStatus run, ThemeColors colors) {
    final durationMs = run.summary?['duration_ms'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusIcon(run.status, colors),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatRfc3339Local(run.startedAt)}  ·  ${_statusLabel(run.status)}'
                  '${run.progress > 0 && run.progress < 100 ? " (${run.progress}%)" : ""}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _detailLine(run, durationMs),
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                if (run.cursor != null && run.status == 'canceled')
                  Text(
                    'cursor: ${run.cursor}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                if (run.error != null && run.status == 'failed')
                  Text(
                    run.error!,
                    style: TextStyle(fontSize: 11, color: colors.error),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _detailLine(DataSyncRunStatus run, dynamic durationMs) {
    final parts = <String>[];
    if (run.processedRows > 0) {
      parts.add(_l10n.dataSyncRunRowsOnly(run.processedRows));
    }
    if (run.failedRows > 0) {
      parts.add('failed: ${run.failedRows}');
    }
    if (durationMs is num) {
      parts.add(_l10n.dataSyncHistoryDuration(durationMs.toInt()));
    }
    parts.add(run.triggeredBy);
    return parts.join(' · ');
  }

  Widget _statusIcon(String status, ThemeColors colors) {
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

  Widget _centered(String message, ThemeColors colors) {
    return ListView(
      children: [
        const SizedBox(height: 60),
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
