// Tests for the health check models + the inferHealthSummary pure function.
//
// inferHealthSummary is the indicator's brain — these cover the full state
// matrix (empty / critical / warning / healthy) plus the documented
// sustained-alert blind spot, so the sidebar dot never silently lies.

import 'dart:convert';

import 'package:dbmaster/models/health_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── Test helpers: build DTOs without 30 lines of JSON per case ──

  /// Build a result DTO. `startedAt` doubles as the id. `recent` passed to
  /// inferHealthSummary must be DESC (newest first) — construct accordingly.
  HealthCheckResultDto result({
    required String startedAt,
    String status = 'success',
    bool connectivityOk = true,
    int latencyMs = 5,
    String? connectivityError,
    String alertChangesJson = '[]',
    String metricsExtras = '',
    String? error,
  }) {
    final err = connectivityError == null ? 'null' : '"$connectivityError"';
    final metrics = '{"connectivity":{"ok":$connectivityOk,'
        '"latency_ms":$latencyMs,"error":$err}$metricsExtras}';
    return HealthCheckResultDto(
      id: 'r-$startedAt',
      taskId: 't1',
      startedAt: startedAt,
      status: status,
      metricsSummaryJson: metrics,
      alertChangesJson: alertChangesJson,
      triggeredBy: 'scheduler',
      error: error,
    );
  }

  /// Encode a list of alert-change objects.
  String alerts(List<Map<String, Object?>> list) => jsonEncode(list);

  AlertChange alert(String metric, String trigger,
          {String severity = 'warning'}) =>
      AlertChange(metric: metric, trigger: trigger, severity: severity);

  group('inferHealthSummary', () {
    test('empty window → unknown', () {
      final s = inferHealthSummary(const []);
      expect(s.status, HealthStatus.unknown);
      expect(s.activeAlertMetrics, isEmpty);
      expect(s.lastRunAt, isNull);
    });

    test('latest status=="failed" → critical (runner failure)', () {
      final s = inferHealthSummary([
        result(startedAt: '2026-08-12T07:00:00Z', status: 'failed'),
      ]);
      expect(s.status, HealthStatus.critical);
      expect(s.lastRunAt, DateTime.parse('2026-08-12T07:00:00Z'));
    });

    test('latest connectivity.ok==false → critical with error', () {
      final s = inferHealthSummary([
        result(
          startedAt: '2026-08-12T07:00:00Z',
          connectivityOk: false,
          connectivityError: 'connection refused',
          latencyMs: 0,
        ),
      ]);
      expect(s.status, HealthStatus.critical);
      expect(s.connectivityError, 'connection refused');
      expect(s.latencyMs, 0);
    });

    test('critical wins over warning even if older alerts exist in window', () {
      // newest = failed connectivity; an older row has an unresolved alert.
      final s = inferHealthSummary([
        result(
          startedAt: '2026-08-12T07:00:00Z',
          connectivityOk: false,
          connectivityError: 'timeout',
        ),
        result(
          startedAt: '2026-08-12T06:00:00Z',
          alertChangesJson: alerts([
            {'metric': 'row_count', 'severity': 'warning', 'trigger': 'alert'}
          ]),
        ),
      ]);
      expect(s.status, HealthStatus.critical);
    });

    test('newest alert with no later resolved → warning', () {
      final s = inferHealthSummary([
        result(
          startedAt: '2026-08-12T07:00:00Z',
          alertChangesJson: alerts([
            {'metric': 'row_count', 'severity': 'warning', 'trigger': 'alert'}
          ]),
        ),
      ]);
      expect(s.status, HealthStatus.warning);
      expect(s.activeAlertMetrics, ['row_count']);
      expect(s.lastAlertAt, DateTime.parse('2026-08-12T07:00:00Z'));
    });

    test('alert followed by resolved (newer) → healthy', () {
      // DESC order: newest first → resolved is at index 0.
      final s = inferHealthSummary([
        result(
          startedAt: '2026-08-12T07:00:00Z',
          alertChangesJson: alerts([
            {'metric': 'row_count', 'severity': 'warning', 'trigger': 'resolved'}
          ]),
        ),
        result(
          startedAt: '2026-08-12T06:00:00Z',
          alertChangesJson: alerts([
            {'metric': 'row_count', 'severity': 'warning', 'trigger': 'alert'}
          ]),
        ),
      ]);
      expect(s.status, HealthStatus.healthy);
      // lastAlertAt still records when the alert was last raised (tooltip hint).
      expect(s.lastAlertAt, DateTime.parse('2026-08-12T06:00:00Z'));
    });

    test('no alerts at all → healthy, lastAlertAt null', () {
      final s = inferHealthSummary([
        result(startedAt: '2026-08-12T07:00:00Z'),
      ]);
      expect(s.status, HealthStatus.healthy);
      expect(s.activeAlertMetrics, isEmpty);
      expect(s.lastAlertAt, isNull);
      expect(s.latencyMs, 5);
    });

    test('multiple metrics: one alert one resolved → warning for the firing one', () {
      // Two metrics in the same (newest) row: connectivity resolved, missing_pk alert.
      final s = inferHealthSummary([
        result(
          startedAt: '2026-08-12T07:00:00Z',
          alertChangesJson: alerts([
            {'metric': 'connectivity', 'severity': 'critical', 'trigger': 'resolved'},
            {'metric': 'missing_pk', 'severity': 'warning', 'trigger': 'alert'},
          ]),
        ),
      ]);
      expect(s.status, HealthStatus.warning);
      expect(s.activeAlertMetrics, ['missing_pk']);
    });

    test('activeAlertMetrics sorted alphabetically', () {
      final s = inferHealthSummary([
        result(
          startedAt: '2026-08-12T07:00:00Z',
          alertChangesJson: alerts([
            {'metric': 'row_count', 'severity': 'warning', 'trigger': 'alert'},
            {'metric': 'connection_count', 'severity': 'warning', 'trigger': 'alert'},
            {'metric': 'missing_pk', 'severity': 'warning', 'trigger': 'alert'},
          ]),
        ),
      ]);
      expect(s.activeAlertMetrics, ['connection_count', 'missing_pk', 'row_count']);
    });

    test('documented blind spot: alert older than window reads healthy', () {
      // The alert fired before the fetched window; within the window the metric
      // is silent (no new change). This is the known limitation — documented
      // in inferHealthSummary's dartdoc. Asserting the actual (imperfect)
      // behaviour so a future fix is intentional.
      final s = inferHealthSummary([
        result(startedAt: '2026-08-12T07:00:00Z'), // no alerts in window
        result(startedAt: '2026-08-12T06:00:00Z'),
      ]);
      expect(s.status, HealthStatus.healthy);
    });

    test('lastAlertAt is the newest alert sighting across the window', () {
      // Two alerts in DESC order: 07:00 (newest) and 06:00. lastAlertAt = 07:00.
      final s = inferHealthSummary([
        result(
          startedAt: '2026-08-12T07:00:00Z',
          alertChangesJson: alerts([
            {'metric': 'row_count', 'severity': 'warning', 'trigger': 'alert'}
          ]),
        ),
        result(
          startedAt: '2026-08-12T06:00:00Z',
          alertChangesJson: alerts([
            {'metric': 'row_count', 'severity': 'warning', 'trigger': 'alert'}
          ]),
        ),
      ]);
      expect(s.status, HealthStatus.warning);
      expect(s.lastAlertAt, DateTime.parse('2026-08-12T07:00:00Z'));
    });

    // ── U06: task-level last_status fallback ──

    test('empty window + taskLastStatus=failed → critical (not unknown)', () {
      // Results rotated away / per-task fetch failed while the task row knows
      // the last run failed — the indicator must not read "unknown".
      final s = inferHealthSummary(const [],
          taskLastStatus: 'failed', taskLastRunAt: '2026-08-12T07:00:00Z');
      expect(s.status, HealthStatus.critical);
      expect(s.lastRunAt, DateTime.parse('2026-08-12T07:00:00Z'));
    });

    test('empty window + no lastStatus → unknown (never ran)', () {
      final s = inferHealthSummary(const [], taskLastRunAt: null);
      expect(s.status, HealthStatus.unknown);
    });

    test('window row newer than a failed task last run → window wins', () {
      // A recovery run succeeded AFTER the failed task-level run (e.g. the
      // results row arrived but scheduled_tasks lagged) — healthy, not stuck
      // red from the stale task row.
      final s = inferHealthSummary(
        [result(startedAt: '2026-08-12T08:00:00Z')],
        taskLastStatus: 'failed',
        taskLastRunAt: '2026-08-12T07:00:00Z',
      );
      expect(s.status, HealthStatus.healthy);
    });

    test('window row older than failed task last run → critical (legacy gap)', () {
      // Pre-migration-014 data: the failed run wrote no results row, so the
      // newest window row predates it. Trust the task row.
      final s = inferHealthSummary(
        [result(startedAt: '2026-08-12T06:00:00Z')],
        taskLastStatus: 'failed',
        taskLastRunAt: '2026-08-12T07:00:00Z',
      );
      expect(s.status, HealthStatus.critical);
      expect(s.lastRunAt, DateTime.parse('2026-08-12T07:00:00Z'));
    });

    test('failed row error surfaces as connectivityError', () {
      final s = inferHealthSummary([
        result(startedAt: '2026-08-12T07:00:00Z', status: 'failed',
            error: 'mysql connect failed: refused'),
      ]);
      expect(s.status, HealthStatus.critical);
      expect(s.connectivityError, 'mysql connect failed: refused');
    });

    test('malformed metrics JSON degrades gracefully (connectivity fallback)', () {
      final dto = HealthCheckResultDto(
        id: 'x',
        taskId: 't1',
        startedAt: '2026-08-12T07:00:00Z',
        status: 'success',
        metricsSummaryJson: 'not json',
        alertChangesJson: '[]',
        triggeredBy: 'scheduler',
      );
      // metrics getter returns null → connectivity treated as failed → critical.
      final s = inferHealthSummary([dto]);
      expect(s.status, HealthStatus.critical);
    });
  });

  group('parseMetricsSnapshot', () {
    test('full well-formed snapshot', () {
      const json = '{"connectivity":{"ok":true,"latency_ms":12,"error":null},'
          '"row_count":{"top_tables":[["big",1000000],["small",50]]},'
          '"missing_pk":{"tables":["a","b"]},'
          '"connection_count":42,'
          '"db_type":"mysql",'
          '"unsupported_metrics":[{"metric":"x","reason":"unsupported_db_type"}]}';
      final m = parseMetricsSnapshot(json)!;
      expect(m.connectivity.ok, true);
      expect(m.connectivity.latencyMs, 12);
      expect(m.dbType, 'mysql');
      expect(m.topTables!.length, 2);
      expect(m.topTables![0].table, 'big');
      expect(m.topTables![0].estimatedRows, 1000000);
      expect(m.missingPkTables, ['a', 'b']);
      expect(m.connectionCount, 42);
      expect(m.unsupportedMetrics.length, 1);
      expect(m.unsupportedMetrics[0].metric, 'x');
    });

    test('latency_ms as string (Rust u64 serde edge) is tolerated', () {
      const json = '{"connectivity":{"ok":true,"latency_ms":"7","error":null},'
          '"db_type":"postgres"}';
      final m = parseMetricsSnapshot(json)!;
      expect(m.connectivity.latencyMs, 7);
    });

    test('empty object {} → connectivity fallback (ok=false), not healthy', () {
      const json = '{}';
      final m = parseMetricsSnapshot(json)!;
      expect(m.connectivity.ok, false); // defensive: don't silently show healthy
      expect(m.dbType, 'unknown');
    });

    test('malformed JSON → null', () {
      expect(parseMetricsSnapshot('not json'), isNull);
      expect(parseMetricsSnapshot(''), isNull);
    });

    test('null top_tables / missing_pk / connection_count tolerated', () {
      const json = '{"connectivity":{"ok":true,"latency_ms":1,"error":null},'
          '"db_type":"mysql"}';
      final m = parseMetricsSnapshot(json)!;
      expect(m.topTables, isNull);
      expect(m.missingPkTables, isNull);
      expect(m.connectionCount, isNull);
    });
  });

  group('parseAlertChanges', () {
    test('well-formed list', () {
      const json = '[{"metric":"connectivity","severity":"critical",'
          '"trigger":"alert","detail":{"error":"x"}}]';
      final list = parseAlertChanges(json);
      expect(list.length, 1);
      expect(list[0].metric, 'connectivity');
      expect(list[0].trigger, 'alert');
      expect(list[0].detail!['error'], 'x');
    });

    test('empty array is the steady-state norm', () {
      expect(parseAlertChanges('[]'), isEmpty);
    });

    test('malformed → empty list (never throws)', () {
      expect(parseAlertChanges('not json'), isEmpty);
      expect(parseAlertChanges(''), isEmpty);
      expect(parseAlertChanges('null'), isEmpty);
      expect(parseAlertChanges('{}'), isEmpty); // not a list
    });

    test('skips non-map elements', () {
      const json = '[1,"x",{"metric":"m","severity":"s","trigger":"alert"}]';
      final list = parseAlertChanges(json);
      expect(list.length, 1);
      expect(list[0].metric, 'm');
    });
  });

  group('HealthCheckResultDto.fromJson', () {
    test('maps all fields + defensive defaults for missing JSON columns', () {
      final dto = HealthCheckResultDto.fromJson({
        'id': 'r1',
        'task_id': 't1',
        'started_at': '2026-08-12T07:00:00Z',
        'finished_at': null,
        'status': 'success',
        // metrics_summary / alert_changes omitted → defaults
        'triggered_by': 'manual:u1',
      });
      expect(dto.id, 'r1');
      expect(dto.taskId, 't1');
      expect(dto.status, 'success');
      expect(dto.metricsSummaryJson, '{}');
      expect(dto.alertChangesJson, '[]');
      expect(dto.triggeredBy, 'manual:u1');
      // '{}' → parseMetricsSnapshot returns a defensive snapshot (ok=false),
      // NOT null — so a malformed row never silently reads as healthy.
      expect(dto.metrics, isNotNull);
      expect(dto.metrics!.connectivity.ok, false);
    });

    test('opaque JSON columns round-trip through getters', () {
      final dto = HealthCheckResultDto.fromJson({
        'id': 'r1',
        'task_id': 't1',
        'started_at': '2026-08-12T07:00:00Z',
        'status': 'success',
        'metrics_summary':
            '{"connectivity":{"ok":true,"latency_ms":3,"error":null},"db_type":"mysql"}',
        'alert_changes':
            '[{"metric":"missing_pk","severity":"warning","trigger":"alert"}]',
        'triggered_by': 'scheduler',
      });
      expect(dto.metrics!.connectivity.ok, true);
      expect(dto.alertChanges.length, 1);
      expect(dto.alertChanges[0].metric, 'missing_pk');
    });
  });

  group('HealthTask.fromJson', () {
    test('maps scheduled_tasks row', () {
      final t = HealthTask.fromJson({
        'id': 't1',
        'name': 'prod health',
        'source_db_id': 'conn-42',
        'enabled': true,
        'cron_expr': '*/5 * * * *',
        'last_run_at': '2026-08-12T07:00:00Z',
        'last_status': 'success',
      });
      expect(t.id, 't1');
      expect(t.sourceDbId, 'conn-42');
      expect(t.cronExpr, '*/5 * * * *');
      expect(t.enabled, true);
      expect(t.lastStatus, 'success');
    });

    test('defaults enabled=true and cron_expr="" when absent', () {
      final t = HealthTask.fromJson({
        'id': 't1',
        'name': 'x',
        'source_db_id': 'c1',
      });
      expect(t.enabled, true);
      expect(t.cronExpr, '');
    });
  });

  group('HealthCheckResultDto.fromJson', () {
    test('parses the error column (migration 014 wire shape)', () {
      final dto = HealthCheckResultDto.fromJson(const {
        'id': 'r1',
        'task_id': 't1',
        'started_at': '2026-08-17T10:00:00+00:00',
        'finished_at': '2026-08-17T10:00:01+00:00',
        'status': 'failed',
        'metrics_summary': '{}',
        'alert_changes': '[]',
        'triggered_by': 'scheduler',
        'error': 'mysql connect failed: refused',
      });
      expect(dto.error, 'mysql connect failed: refused');
      expect(dto.status, 'failed');
    });

    test('error defaults to null for legacy rows (no error key)', () {
      final dto = HealthCheckResultDto.fromJson(const {
        'id': 'r2',
        'task_id': 't1',
        'started_at': '2026-08-16T10:00:00+00:00',
        'status': 'success',
        'metrics_summary': '{}',
        'alert_changes': '[]',
        'triggered_by': 'scheduler',
      });
      expect(dto.error, isNull);
    });
  });

  group('HealthCheckTaskConfig', () {
    test('default toJson matches Server defaults (all metrics on)', () {
      final json = const HealthCheckTaskConfig().toJson();
      expect(json['fail_threshold'], 3);
      expect(json['large_table_threshold'], 10000000);
      expect(json['connection_count_threshold'], 100);
      expect(json['retention_days'], 30);
      expect(json['metrics'] as Map<String, dynamic>, {
        'connectivity': true,
        'row_count': true,
        'missing_pk': true,
        'connection_count': true,
      });
    });

    test('custom failThreshold overrides default, others stay default', () {
      final json = const HealthCheckTaskConfig(failThreshold: 7).toJson();
      expect(json['fail_threshold'], 7);
      // Untouched thresholds keep Server defaults.
      expect(json['retention_days'], 30);
      expect((json['metrics'] as Map<String, dynamic>)['row_count'], true);
    });

    test('fail_threshold bounds mirror Server validate()', () {
      expect(HealthCheckTaskConfig.minFailThreshold, 1);
      expect(HealthCheckTaskConfig.maxFailThreshold, 10);
    });
  });
}
