//! Models for the Server-side health check engine (ADR-0004) and the
//! pure-function status inference that drives the sidebar indicator.
//!
//! Wire contract mirrors `dbmaster-server`:
//! - `GET /api/tasks` (filtered client-side to `task_type == "health_check"`)
//!   → [HealthTask] rows from `scheduled_tasks`.
//! - `GET /api/health-results?task_id=&limit=` → [HealthCheckResultDto] rows
//!   from `health_check_results`. The Server stores `metrics_summary` and
//!   `alert_changes` as opaque TEXT (JSON strings) — the client parses them a
//!   second time via [parseMetricsSnapshot] / [parseAlertChanges].
//!
//! [inferHealthSummary] is a top-level pure function so it can be unit-tested
//! across the full state matrix without a widget or server fixture.

import 'dart:convert';

/// A `health_check` scheduled task row (subset of `scheduled_tasks`).
///
/// Mirrors `DriftTask` field-for-field where they overlap; health tasks are
/// cron-driven (ADR-0004 §3.1), so `cronExpr` is surfaced unlike drift's
/// interval-based config.
class HealthTask {
  final String id;
  final String name;
  final String sourceDbId;
  final bool enabled;
  final String cronExpr;
  final List<String> notifyChannels;
  final String? lastRunAt;
  final String? lastStatus;

  const HealthTask({
    required this.id,
    required this.name,
    required this.sourceDbId,
    required this.enabled,
    required this.cronExpr,
    this.notifyChannels = const [],
    this.lastRunAt,
    this.lastStatus,
  });

  factory HealthTask.fromJson(Map<String, dynamic> json) {
    return HealthTask(
      id: json['id'] as String,
      name: json['name'] as String,
      sourceDbId: json['source_db_id'] as String,
      enabled: (json['enabled'] as bool?) ?? true,
      // cron_expr is NOT NULL on the Server; default to '' defensively.
      cronExpr: (json['cron_expr'] as String?) ?? '',
      notifyChannels: _parseNotifyChannels(json['notify_channels']),
      lastRunAt: json['last_run_at'] as String?,
      lastStatus: json['last_status'] as String?,
    );
  }
}

/// Parse the `notify_channels` column. Tolerant of both decoded `List` and
/// stringified-JSON forms (mirrors [DataSyncTask] / [DriftTask.notifyChannels]).
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

/// Configuration for a `health_check` task — the JSON stored in
/// `scheduled_tasks.config`. Mirrors `health_check::config::HealthCheckTaskConfig`
/// on the Server (all fields `#[serde(default = ...)]`, so an empty `{}` is
/// valid and yields Server defaults).
///
/// The create-task dialog builds a default instance and lets the user tune
/// [failThreshold] (flap-suppression sensitivity); the other thresholds use the
/// Server defaults and are not surfaced in the minimal v1 UI.
class HealthCheckTaskConfig {
  final HealthMetricFlags metrics;
  final int failThreshold;
  final int largeTableThreshold;
  final int connectionCountThreshold;
  final int retentionDays;

  const HealthCheckTaskConfig({
    this.metrics = const HealthMetricFlags(),
    this.failThreshold = defaultFailThreshold,
    this.largeTableThreshold = defaultLargeTableThreshold,
    this.connectionCountThreshold = defaultConnectionCountThreshold,
    this.retentionDays = defaultRetentionDays,
  });

  /// snake_case JSON matching the Server's `HealthCheckTaskConfig` serde shape.
  Map<String, dynamic> toJson() => {
        'metrics': metrics.toJson(),
        'fail_threshold': failThreshold,
        'large_table_threshold': largeTableThreshold,
        'connection_count_threshold': connectionCountThreshold,
        'retention_days': retentionDays,
      };

  // Valid ranges mirror the Server's `validate()` (config.rs). Surfaced as
  // constants so the create-task dialog reuses the exact bounds.
  static const int minFailThreshold = 1;
  static const int maxFailThreshold = 10;
  static const int defaultFailThreshold = 3;
  static const int defaultLargeTableThreshold = 10000000;
  static const int defaultConnectionCountThreshold = 100;
  static const int defaultRetentionDays = 30;
}

/// Per-metric on/off flags. `connectivity` is always treated as enabled by the
/// Server (the core probe) regardless of this flag — kept here for wire
/// completeness. Mirrors `health_check::config::MetricFlags`.
class HealthMetricFlags {
  final bool connectivity;
  final bool rowCount;
  final bool missingPk;
  final bool connectionCount;

  const HealthMetricFlags({
    this.connectivity = true,
    this.rowCount = true,
    this.missingPk = true,
    this.connectionCount = true,
  });

  Map<String, dynamic> toJson() => {
        'connectivity': connectivity,
        'row_count': rowCount,
        'missing_pk': missingPk,
        'connection_count': connectionCount,
      };
}

/// One `health_check_results` row. `metricsSummaryJson` / `alertChangesJson`
/// are the Server's opaque TEXT columns — decode lazily via [metrics] /
/// [alertChanges] getters (tolerant of malformed/empty strings). `error`
/// carries the redacted failure reason on `status == "failed"` rows
/// (server migration 014); null otherwise.
class HealthCheckResultDto {
  final String id;
  final String taskId;
  final String startedAt;
  final String? finishedAt;
  final String status; // "success" | "partial" | "failed"
  final String metricsSummaryJson;
  final String alertChangesJson;
  final String triggeredBy;
  final String? error;

  const HealthCheckResultDto({
    required this.id,
    required this.taskId,
    required this.startedAt,
    required this.status,
    required this.metricsSummaryJson,
    required this.alertChangesJson,
    this.finishedAt,
    required this.triggeredBy,
    this.error,
  });

  factory HealthCheckResultDto.fromJson(Map<String, dynamic> json) {
    return HealthCheckResultDto(
      id: json['id'] as String,
      taskId: json['task_id'] as String,
      startedAt: json['started_at'] as String,
      finishedAt: json['finished_at'] as String?,
      status: json['status'] as String? ?? 'unknown',
      // DEFENSIVE-NOTE: server stores both as TEXT (JSON); tolerate null for
      // partial test fixtures / legacy rows rather than crashing the list.
      metricsSummaryJson: (json['metrics_summary'] as String?) ?? '{}',
      alertChangesJson: (json['alert_changes'] as String?) ?? '[]',
      triggeredBy: json['triggered_by'] as String? ?? '',
      error: json['error'] as String?,
    );
  }

  /// Lazily-parsed metrics snapshot (null if the JSON is absent/malformed).
  MetricsSnapshot? get metrics => parseMetricsSnapshot(metricsSummaryJson);

  /// Lazily-parsed alert-change list (empty if absent/malformed).
  List<AlertChange> get alertChanges => parseAlertChanges(alertChangesJson);
}

/// Parsed `metrics_summary` shape (mirrors `health_check::collector::MetricsSnapshot`).
///
/// `connectivity` is always present (it is the core probe, always collected).
/// The three metric-specific fields are nullable: they are null when the metric
/// is disabled in the task config OR when the DB type degraded to
/// connectivity-only (non-MySQL/PG) — the distinction is encoded in
/// `unsupportedMetrics`.
class MetricsSnapshot {
  final ConnectivityResult connectivity;
  final List<TableRowEntry>? topTables; // row_count metric
  final List<String>? missingPkTables; // missing_pk metric
  final int? connectionCount; // connection_count metric
  final String dbType;
  final List<UnsupportedMetric> unsupportedMetrics;

  const MetricsSnapshot({
    required this.connectivity,
    required this.dbType,
    this.topTables,
    this.missingPkTables,
    this.connectionCount,
    this.unsupportedMetrics = const [],
  });
}

/// Connectivity + latency probe result (always collected).
class ConnectivityResult {
  final bool ok;
  final int latencyMs;
  final String? error;

  const ConnectivityResult({
    required this.ok,
    required this.latencyMs,
    this.error,
  });
}

/// One entry of the `row_count` metric's `top_tables` (serialized by Rust as a
/// 2-tuple `[name, estimated_rows]`, not an object).
class TableRowEntry {
  final String table;
  final int estimatedRows;

  const TableRowEntry({required this.table, required this.estimatedRows});
}

/// One entry of `unsupported_metrics` — a metric that was skipped for this DB
/// type, with the reason (e.g. `unsupported_db_type`).
class UnsupportedMetric {
  final String metric;
  final String reason;

  const UnsupportedMetric({required this.metric, required this.reason});
}

/// One element of `alert_changes` (mirrors `health_check::alert::AlertChange`).
///
/// `detail` is kept as the raw decoded object because its shape varies per
/// metric (connectivity/row_count/missing_pk/connection_count each differ) —
/// the history dialog renders it, the indicator only needs metric + trigger.
class AlertChange {
  final String metric; // connectivity|row_count|missing_pk|connection_count
  final String severity; // critical|warning|info
  final String trigger; // alert|resolved
  final Map<String, dynamic>? detail;

  const AlertChange({
    required this.metric,
    required this.severity,
    required this.trigger,
    this.detail,
  });
}

/// Coarse per-connection health status for the sidebar indicator.
enum HealthStatus {
  /// Last check passed, no active alerts.
  healthy,
  /// At least one metric is in an unresolved alert state (but reachable).
  warning,
  /// Last connectivity probe failed OR the runner itself failed (red).
  critical,
  /// No results yet / no task configured / not connected to Server.
  unknown,
}

/// Inferred per-connection health summary, produced by [inferHealthSummary].
///
/// Deliberately structural (no UI string) — the sidebar widget composes the
/// tooltip from these fields + l10n, keeping this model pure & testable.
class HealthSummary {
  final HealthStatus status;
  final DateTime? lastRunAt;
  final int? latencyMs;
  final List<String> activeAlertMetrics;
  final DateTime? lastAlertAt;
  final String? connectivityError;

  const HealthSummary({
    required this.status,
    required this.activeAlertMetrics,
    this.lastRunAt,
    this.latencyMs,
    this.lastAlertAt,
    this.connectivityError,
  });

  static const HealthSummary empty =
      HealthSummary(status: HealthStatus.unknown, activeAlertMetrics: []);
}

// ── JSON parsing helpers (tolerant of malformed/empty strings) ──

/// Parse a `metrics_summary` JSON string. Returns null on any decode error so
/// callers can degrade to `unknown` instead of crashing the indicator.
MetricsSnapshot? parseMetricsSnapshot(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final connRaw = decoded['connectivity'];
  ConnectivityResult connectivity;
  if (connRaw is Map<String, dynamic>) {
    connectivity = ConnectivityResult(
      ok: (connRaw['ok'] as bool?) ?? false,
      // latency_ms serializes as a u64; tolerate int/double/String.
      latencyMs: _readInt(connRaw['latency_ms']) ?? 0,
      error: connRaw['error'] as String?,
    );
  } else {
    // connectivity should always be present; fall back to a failed probe so
    // the indicator does not silently show "healthy" on a malformed row.
    connectivity = const ConnectivityResult(ok: false, latencyMs: 0);
  }

  List<TableRowEntry>? topTables;
  final rowCount = decoded['row_count'];
  if (rowCount is Map<String, dynamic>) {
    final tt = rowCount['top_tables'];
    if (tt is List) {
      topTables = tt
          .map((e) {
            if (e is List && e.length >= 2) {
              return TableRowEntry(
                table: '${e[0]}',
                estimatedRows: _readInt(e[1]) ?? 0,
              );
            }
            return null;
          })
          .whereType<TableRowEntry>()
          .toList(growable: false);
    }
  }

  List<String>? missingPkTables;
  final missingPk = decoded['missing_pk'];
  if (missingPk is Map<String, dynamic>) {
    final t = missingPk['tables'];
    if (t is List) {
      missingPkTables = t.map((e) => '$e').toList(growable: false);
    }
  }

  final unsupportedRaw = decoded['unsupported_metrics'];
  final unsupported = <UnsupportedMetric>[];
  if (unsupportedRaw is List) {
    for (final e in unsupportedRaw) {
      if (e is Map<String, dynamic>) {
        unsupported.add(UnsupportedMetric(
          metric: '${e['metric'] ?? ''}',
          reason: '${e['reason'] ?? ''}',
        ));
      }
    }
  }

  return MetricsSnapshot(
    connectivity: connectivity,
    dbType: '${decoded['db_type'] ?? 'unknown'}',
    topTables: topTables,
    missingPkTables: missingPkTables,
    connectionCount: _readInt(decoded['connection_count']),
    unsupportedMetrics: unsupported,
  );
}

/// Parse an `alert_changes` JSON string. Returns an empty list on any decode
/// error (an empty list is also the Server's steady-state norm — alert_changes
/// are only emitted on state transitions).
List<AlertChange> parseAlertChanges(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (decoded is! List) return const [];
  final out = <AlertChange>[];
  for (final e in decoded) {
    if (e is Map<String, dynamic>) {
      out.add(AlertChange(
        metric: '${e['metric'] ?? ''}',
        severity: '${e['severity'] ?? ''}',
        trigger: '${e['trigger'] ?? ''}',
        detail: e['detail'] is Map<String, dynamic>
            ? e['detail'] as Map<String, dynamic>
            : null,
      ));
    }
  }
  return out;
}

int? _readInt(Object? v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

DateTime? _parseDate(String? s) {
  if (s == null || s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// PURE FUNCTION — infer the current per-connection health status from a list
/// of recent results.
///
/// `recent` MUST be ordered newest-first (by `started_at` DESC), matching the
/// Server's `ORDER BY started_at DESC` and the natural output of
/// `GET /api/health-results`. The window size is whatever the caller fetched
/// (the Provider uses `limit: 5`).
///
/// Algorithm:
/// 1. Empty window → [HealthStatus.unknown] (no task / no results yet),
///    EXCEPT `taskLastStatus == "failed"` → [HealthStatus.critical] (U06: the
///    task row's last run failed but no result row is visible — rotated away,
///    fetch failed, or pre-migration-014 data).
/// 2. Latest result `status == "failed"` OR `connectivity.ok == false` →
///    [HealthStatus.critical] (unreachable / runner failed = red, highest
///    priority). The result row's redacted `error` surfaces as
///    [HealthSummary.connectivityError] when present.
/// 2b. Newest window row OLDER than `taskLastRunAt` while
///    `taskLastStatus == "failed"` → [HealthStatus.critical] (the failed run
///    left no results row — legacy data; trust the task row).
/// 3. Otherwise walk the whole window. For each metric, the NEWEST
///    `AlertChange` that mentions it decides its current state (`alert` ⇒
///    still firing, `resolved` ⇒ cleared). If any metric is still firing →
///    [HealthStatus.warning].
/// 4. Else → [HealthStatus.healthy].
///
/// Known limitation (documented in the design plan): `alert_changes` are only
/// emitted on state transitions, so a metric that has been firing longer than
/// the fetched window produces no new change and may read as `healthy`. The
/// 5-row window + `lastAlertAt` tooltip mitigate this; full accuracy needs a
/// future Server-side `GET /api/health-alert-state` endpoint (contract change,
/// deferred).
HealthSummary inferHealthSummary(
  List<HealthCheckResultDto> recent, {
  String? taskLastStatus,
  String? taskLastRunAt,
  DateTime? now,
}) {
  // U06 — the task row's last_status is authoritative for the newest run even
  // when the results window cannot see it: rows may have been rotated away by
  // retention, the per-task results fetch may have failed (logged + skipped →
  // empty window), or the run predates server-side failure persistence (rows
  // written before failed runs started getting a results row). A failed last
  // run with no newer result in the window → critical.
  final lastRunFailed = taskLastStatus == 'failed';
  final taskRunAt = _parseDate(taskLastRunAt);

  if (recent.isEmpty) {
    if (lastRunFailed) {
      return HealthSummary(
        status: HealthStatus.critical,
        lastRunAt: taskRunAt,
        activeAlertMetrics: const [],
      );
    }
    return HealthSummary.empty;
  }

  final latest = recent.first;
  final metrics = latest.metrics;
  final conn = metrics?.connectivity;
  final latestRunAt = _parseDate(latest.startedAt);

  // (2) critical: runner failed, OR the connectivity probe was down, OR the
  // metrics payload could not be parsed (do not silently assume healthy when
  // reachability cannot be confirmed — fail loud on the indicator).
  if (latest.status == 'failed' || conn == null || !conn.ok) {
    return HealthSummary(
      status: HealthStatus.critical,
      lastRunAt: latestRunAt,
      latencyMs: conn?.latencyMs,
      connectivityError: conn?.error ?? latest.error,
      activeAlertMetrics: const [],
    );
  }

  // (2b) legacy fallback: the newest WINDOW row is older than the task-level
  // last run and that run failed → the failed run wrote no results row (pre
  // server migration 014 data, or the row was rotated). Trust the task row.
  if (lastRunFailed &&
      (latestRunAt == null ||
          (taskRunAt != null && latestRunAt.isBefore(taskRunAt)))) {
    return HealthSummary(
      status: HealthStatus.critical,
      lastRunAt: taskRunAt ?? latestRunAt,
      activeAlertMetrics: const [],
    );
  }

  // (3) walk the window: newest occurrence per metric wins (recent is DESC,
  // so putIfAbsent records the first = newest sighting of each metric).
  final lastByMetric = <String, AlertChange>{};
  DateTime? lastAlertAt;
  for (final r in recent) {
    final runAt = _parseDate(r.startedAt);
    for (final c in r.alertChanges) {
      if (c.metric.isEmpty) continue;
      lastByMetric.putIfAbsent(c.metric, () => c);
      // Record the newest "alert" sighting time for the tooltip (first hit
      // in DESC order = most recent alert).
      if (c.trigger == 'alert' && lastAlertAt == null) {
        lastAlertAt = runAt;
      }
    }
  }

  final active = lastByMetric.values
      .where((c) => c.trigger == 'alert')
      .map((c) => c.metric)
      .toList()
    ..sort();

  if (active.isNotEmpty) {
    return HealthSummary(
      status: HealthStatus.warning,
      lastRunAt: latestRunAt,
      latencyMs: conn.latencyMs,
      activeAlertMetrics: active,
      lastAlertAt: lastAlertAt,
    );
  }

  // (4) healthy.
  return HealthSummary(
    status: HealthStatus.healthy,
    lastRunAt: latestRunAt,
    latencyMs: conn.latencyMs,
    activeAlertMetrics: const [],
    lastAlertAt: lastAlertAt,
  );
}
