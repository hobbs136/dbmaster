//! Typed models for the Server-side drift API (Phase F desktop UI).
//!
//! Wire shapes mirror `dbmaster-server/crates/automation/src/lib.rs` and
//! `crates/drift/src/snapshot.rs` exactly. The desktop talks to the Server
//! over REST; these models give us static typing on the client side instead
//! of passing raw `Map<String, dynamic>` through the widget tree.
//!
//! SECURITY: the Server returns `password_encrypted` (AES-256-GCM ciphertext)
//! on `GET /api/connections`. We accept the field for round-trip fidelity but
//! NEVER render it — the desktop does not hold source-DB plaintext (hard
//! constraint, brief §硬约束).

import 'dart:convert';

/// One row of `scheduled_tasks` filtered to `task_type = "schema_drift"`.
///
/// `config` and `notify_channels` are server-side JSON strings; parse lazily
/// via [DriftTaskConfig.fromConfigJson] / [notifyChannels].
class DriftTask {
  final String id;
  final String name;
  final String sourceDbId;
  final bool enabled;
  final String configJson;
  final String notifyChannelsJson;
  final String createdAt;
  final String? lastRunAt;
  final String? lastStatus;

  const DriftTask({
    required this.id,
    required this.name,
    required this.sourceDbId,
    required this.enabled,
    required this.configJson,
    required this.notifyChannelsJson,
    required this.createdAt,
    this.lastRunAt,
    this.lastStatus,
  });

  factory DriftTask.fromJson(Map<String, dynamic> json) {
    return DriftTask(
      id: json['id'] as String,
      name: json['name'] as String,
      sourceDbId: json['source_db_id'] as String,
      enabled: (json['enabled'] as bool?) ?? true,
      // DEFENSIVE-NOTE: server stores both as TEXT (JSON); be tolerant of null
      // for legacy rows / partial test fixtures rather than crashing the list.
      configJson: (json['config'] as String?) ?? '{}',
      notifyChannelsJson: (json['notify_channels'] as String?) ?? '[]',
      createdAt: json['created_at'] as String,
      lastRunAt: json['last_run_at'] as String?,
      lastStatus: json['last_status'] as String?,
    );
  }

  /// Parsed `config` JSON (interval_minutes, pg_schemas).
  DriftTaskConfig get config => DriftTaskConfig.fromConfigJson(configJson);

  /// Webhook URLs parsed from the `notify_channels` JSON array column.
  List<String> get notifyChannels {
    final decoded = jsonDecode(notifyChannelsJson);
    if (decoded is List) {
      return decoded.whereType<String>().toList(growable: false);
    }
    return const [];
  }
}

/// Drift-specific keys parsed from `scheduled_tasks.config` JSON.
///
/// Mirrors what `drift::scheduler::task_interval_minutes` and
/// `drift::runner::pg_schemas_from_task_config` actually read on the Server
/// side — keep this in sync with `crates/drift/src/scheduler.rs` /
/// `runner.rs`.
class DriftTaskConfig {
  /// Minutes between scheduled runs. Server clamps to `[1, 1440]`; falls back
  /// to the Server-side default when out of range / absent. `null` here means
  /// "not specified" (the Server default will apply).
  final int? intervalMinutes;

  /// PG-only schema allow-list. `null` / empty ⇒ Server uses `["public"]`.
  final List<String>? pgSchemas;

  const DriftTaskConfig({this.intervalMinutes, this.pgSchemas});

  factory DriftTaskConfig.fromConfigJson(String json) {
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return const DriftTaskConfig();
    }
    if (decoded is! Map<String, dynamic>) return const DriftTaskConfig();
    final interval = decoded['interval_minutes'];
    final schemasRaw = decoded['pg_schemas'];
    return DriftTaskConfig(
      intervalMinutes: interval is num ? interval.toInt() : null,
      pgSchemas: schemasRaw is List
          ? schemasRaw.whereType<String>().toList(growable: false)
          : null,
    );
  }

  /// Serialise back for `POST /api/tasks` `config` field.
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    if (intervalMinutes != null) out['interval_minutes'] = intervalMinutes;
    if (pgSchemas != null && pgSchemas!.isNotEmpty) {
      out['pg_schemas'] = pgSchemas;
    }
    return out;
  }
}

/// A Server-side `database_connections` row. Used to enumerate source_drift
/// connections for the create-task dropdown and to surface host/port in the UI.
///
/// SECURITY: [passwordEncrypted] is the Server-stored ciphertext; never render
/// it. We keep the field only so the model round-trips the wire shape.
class DriftSourceConnection {
  final String id;
  final String name;
  final String dbType;
  final String host;
  final int port;
  final String username;
  final String? defaultDatabase;
  final String kind;
  final String passwordEncrypted;

  /// U05 — SQLite rows carry the real path here (host is the 'sqlite'
  /// sentinel). Only the Server-connections management dialog reads it.
  final String? filePath;

  const DriftSourceConnection({
    required this.id,
    required this.name,
    required this.dbType,
    required this.host,
    required this.port,
    required this.username,
    required this.defaultDatabase,
    required this.kind,
    required this.passwordEncrypted,
    this.filePath,
  });

  factory DriftSourceConnection.fromJson(Map<String, dynamic> json) {
    return DriftSourceConnection(
      id: json['id'] as String,
      name: json['name'] as String,
      dbType: json['db_type'] as String,
      host: json['host'] as String,
      port: (json['port'] as num).toInt(),
      username: json['username'] as String,
      defaultDatabase: json['default_database'] as String?,
      kind: (json['kind'] as String?) ?? 'collab',
      // DEFENSIVE-NOTE: accept but never display — see class doc.
      passwordEncrypted: (json['password_encrypted'] as String?) ?? '',
      filePath: json['file_path'] as String?,
    );
  }

  /// True when this connection is a schema-drift source (not a collab DB).
  bool get isSourceDrift => kind == 'source_drift';

  /// "host:port" label for dropdown rows / list cells. SQLite rows show the
  /// file path instead (host is the 'sqlite' sentinel).
  String get hostLabel =>
      dbType.toLowerCase() == 'sqlite' ? (filePath ?? host) : '$host:$port';
}

/// One row of `task_run_history` for a drift task.
class DriftRunHistoryEntry {
  final String id;
  final String taskId;
  final String startedAt;
  final String? finishedAt;
  final String status; // "running" | "succeeded" | "failed"
  final String? error;
  final String? summaryJson;
  final String triggeredBy;

  const DriftRunHistoryEntry({
    required this.id,
    required this.taskId,
    required this.startedAt,
    required this.finishedAt,
    required this.status,
    required this.error,
    required this.summaryJson,
    required this.triggeredBy,
  });

  factory DriftRunHistoryEntry.fromJson(Map<String, dynamic> json) {
    return DriftRunHistoryEntry(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      startedAt: json['started_at'] as String,
      finishedAt: json['finished_at'] as String?,
      status: json['status'] as String,
      error: json['error'] as String?,
      summaryJson: json['summary'] as String?,
      triggeredBy: json['triggered_by'] as String,
    );
  }

  /// Parsed `summary` JSON written by the runner (`drift_count`, `webhook_status`,
  /// `duration_ms`). Empty map when missing / malformed (defensive).
  Map<String, dynamic> get summary {
    if (summaryJson == null || summaryJson!.isEmpty) return const {};
    try {
      final decoded = jsonDecode(summaryJson!);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through; treated as no-summary.
    }
    return const {};
  }

  int get driftCount => (summary['drift_count'] as num?)?.toInt() ?? 0;

  String get webhookStatus =>
      (summary['webhook_status'] as String?) ?? 'skipped';

  int get durationMs => (summary['duration_ms'] as num?)?.toInt() ?? 0;

  /// U09 — id of the snapshot this run wrote (server `RunSummary.snapshot_id`).
  /// Null on legacy rows written before U09; callers fall back to the
  /// "latest two" default pairing.
  String? get snapshotId => _summaryString('snapshot_id');

  /// U09 — id of the prior snapshot this run compared against. Null on the
  /// first run for a connection (no baseline) and on legacy rows.
  String? get baselineSnapshotId => _summaryString('baseline_snapshot_id');

  String? _summaryString(String key) {
    final v = summary[key];
    return v is String && v.isNotEmpty ? v : null;
  }

  /// `"manual:<user_id>"` → `"manual"`; `"scheduler"` → `"scheduler"`.
  String get triggeredByKind => triggeredBy.split(':').first;
}

/// Metadata-only projection of a snapshot row (list responses omit
/// `schema_json` to bound payload size).
class DriftSnapshotMeta {
  final String id;
  final String connectionId;
  final String capturedAt;
  final String schemaHash;
  final String? priorHash;
  final String? taskId;
  final int changeCount;

  const DriftSnapshotMeta({
    required this.id,
    required this.connectionId,
    required this.capturedAt,
    required this.schemaHash,
    required this.priorHash,
    required this.taskId,
    required this.changeCount,
  });

  factory DriftSnapshotMeta.fromJson(Map<String, dynamic> json) {
    return DriftSnapshotMeta(
      id: json['id'] as String,
      connectionId: json['connection_id'] as String,
      capturedAt: json['captured_at'] as String,
      schemaHash: json['schema_hash'] as String,
      priorHash: json['prior_hash'] as String?,
      taskId: json['task_id'] as String?,
      changeCount: (json['change_count'] as num).toInt(),
    );
  }
}

/// Full snapshot row including the (potentially large) `schema_json` payload.
class DriftSnapshot extends DriftSnapshotMeta {
  final String schemaJson;

  const DriftSnapshot({
    required super.id,
    required super.connectionId,
    required super.capturedAt,
    required super.schemaHash,
    required super.priorHash,
    required super.taskId,
    required super.changeCount,
    required this.schemaJson,
  });

  factory DriftSnapshot.fromJson(Map<String, dynamic> json) {
    return DriftSnapshot(
      id: json['id'] as String,
      connectionId: json['connection_id'] as String,
      capturedAt: json['captured_at'] as String,
      schemaHash: json['schema_hash'] as String,
      priorHash: json['prior_hash'] as String?,
      taskId: json['task_id'] as String?,
      changeCount: (json['change_count'] as num).toInt(),
      schemaJson: json['schema_json'] as String,
    );
  }
}

/// Server entitlement snapshot from `GET /api/entitlement`.
///
/// The Server's license gate (not the desktop's own Pro gate). When `state`
/// is `gated`, the Server refuses mutations with `403 ENTITLEMENT_GATED`.
class ServerEntitlement {
  final String state; // "licensed" | "trial" | "gated"
  final String? reason; // gated only: trial_expired | license_invalid | ...
  final int? daysUntilExpiry;
  final String? expiresAt;

  const ServerEntitlement({
    required this.state,
    required this.reason,
    required this.daysUntilExpiry,
    required this.expiresAt,
  });

  factory ServerEntitlement.fromJson(Map<String, dynamic> json) {
    return ServerEntitlement(
      state: json['state'] as String,
      reason: json['reason'] as String?,
      daysUntilExpiry: (json['days_until_expiry'] as num?)?.toInt(),
      expiresAt: json['expires_at'] as String?,
    );
  }

  bool get isGated => state == 'gated';
}
