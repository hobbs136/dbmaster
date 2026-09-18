//! Wire models for the Server-side data_sync REST API (一期).
//!
//! Mirror of the Rust `scheduled_tasks` + `data_sync_runs` rows the desktop
//! reads/writes via `DataSyncApiService`. Field names match the JSON the Server
//! emits (snake_case wire format, camelCase Dart getters where helpful).
//!
//! Keep this file dependency-free (only dart core + json) so it stays cheap
//! to import from both the dialog and the task-list panel.

import 'dart:convert';

/// A `data_sync` task row from `GET /api/tasks` (filtered client-side to
/// `task_type == 'data_sync'`).
class DataSyncTask {
  final String id;
  final String name;
  final String taskType;
  final String cronExpr;
  final Map<String, dynamic> config;
  final String sourceDbId;
  final String? targetDbId;
  final bool enabled;
  final List<String> notifyChannels;
  final String? lastRunAt;
  final String? lastStatus;
  final String createdAt;

  const DataSyncTask({
    required this.id,
    required this.name,
    required this.taskType,
    required this.cronExpr,
    required this.config,
    required this.sourceDbId,
    this.targetDbId,
    required this.enabled,
    this.notifyChannels = const [],
    this.lastRunAt,
    this.lastStatus,
    required this.createdAt,
  });

  factory DataSyncTask.fromJson(Map<String, dynamic> j) => DataSyncTask(
        id: j['id'] as String,
        name: j['name'] as String,
        taskType: (j['task_type'] as String?) ?? 'data_sync',
        cronExpr: (j['cron_expr'] as String?) ?? '',
        config: (j['config'] is String)
            ? (jsonDecode(j['config'] as String) as Map<String, dynamic>)
                .cast<String, dynamic>()
            : (j['config'] as Map<String, dynamic>?) ?? const {},
        sourceDbId: j['source_db_id'] as String,
        targetDbId: j['target_db_id'] as String?,
        enabled: (j['enabled'] as int?) == 1 || j['enabled'] == true,
        notifyChannels: _parseNotifyChannels(j['notify_channels']),
        lastRunAt: j['last_run_at'] as String?,
        lastStatus: j['last_status'] as String?,
        createdAt: j['created_at'] as String,
      );
}

/// Parse the `notify_channels` column. The Server persists it as JSON; be
/// tolerant of both decoded `List` and stringified-JSON forms (the wire shape
/// varies slightly across task types / server versions). Mirrors the parsing
/// in [HealthTask] and [DriftTask.notifyChannels].
List<String> _parseNotifyChannels(dynamic raw) {
  Object? decoded = raw;
  if (raw is String) {
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is List) {
    return decoded.whereType<String>().toList(growable: false);
  }
  return const [];
}

/// One row of `data_sync_runs` — the per-invocation progress/status trail.
class DataSyncRunStatus {
  final String id;
  final String taskId;
  final String startedAt;
  final String? finishedAt;
  final String status; // running | succeeded | failed | canceled
  final int progress; // 0..100
  final String? cursor;
  final int processedRows;
  final int failedRows;
  final String? error;
  final Map<String, dynamic>? summary;
  final String triggeredBy;

  const DataSyncRunStatus({
    required this.id,
    required this.taskId,
    required this.startedAt,
    this.finishedAt,
    required this.status,
    required this.progress,
    this.cursor,
    required this.processedRows,
    required this.failedRows,
    this.error,
    this.summary,
    required this.triggeredBy,
  });

  factory DataSyncRunStatus.fromJson(Map<String, dynamic> j) => DataSyncRunStatus(
        id: j['id'] as String,
        taskId: j['task_id'] as String,
        startedAt: j['started_at'] as String,
        finishedAt: j['finished_at'] as String?,
        status: j['status'] as String,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        cursor: j['cursor'] as String?,
        processedRows: (j['processed_rows'] as num?)?.toInt() ?? 0,
        failedRows: (j['failed_rows'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
        summary: j['summary'] is String
            ? (jsonDecode(j['summary'] as String) as Map<String, dynamic>)
                .cast<String, dynamic>()
            : (j['summary'] as Map<String, dynamic>?),
        triggeredBy: j['triggered_by'] as String,
      );

  bool get isRunning => status == 'running';
  bool get isDone => status == 'succeeded' || status == 'failed' || status == 'canceled';
}
