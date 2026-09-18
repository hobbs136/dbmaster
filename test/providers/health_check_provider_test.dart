// Tests for HealthCheckProvider's data flow + guards.
//
// Uses a Fake HealthApiService (override methods, no network) and an injected
// `shouldRefresh: () => false` to keep the constructor's auto-evaluate quiet,
// then drives `doRefreshForTesting` / `evaluateForTesting` directly.

import 'package:dbmaster/models/health_summary.dart';
import 'package:dbmaster/providers/health_check_provider.dart';
import 'package:dbmaster/services/health_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake that overrides every method the provider calls — the inherited
/// ServerConnection singleton is never touched (no network).
class _FakeHealthApi extends HealthApiService {
  _FakeHealthApi();
  List<HealthTask> tasks = const [];
  Map<String, List<HealthCheckResultDto>> resultsByTaskId = const {};
  Object? listTasksError;
  Set<String> failingResultTaskIds = const {};
  final List<String> logCalls = [];

  @override
  Future<List<HealthTask>> listHealthTasks() async {
    if (listTasksError != null) throw listTasksError!;
    return tasks;
  }

  @override
  Future<List<HealthCheckResultDto>> listHealthResults(
    String taskId, {
    int limit = 5,
  }) async {
    if (failingResultTaskIds.contains(taskId)) {
      throw const HealthApiException('fetch failed');
    }
    return resultsByTaskId[taskId] ?? const [];
  }

  @override
  void logError(String op, Object error) => logCalls.add(op);
}

HealthTask _task(String id, String connId) => HealthTask(
      id: id,
      name: 'task-$id',
      sourceDbId: connId,
      enabled: true,
      cronExpr: '*/5 * * * *',
    );

HealthCheckResultDto _okResult(String startedAt, {String taskId = 't1'}) =>
    HealthCheckResultDto(
      id: 'r-$startedAt',
      taskId: taskId,
      startedAt: startedAt,
      status: 'success',
      metricsSummaryJson:
          '{"connectivity":{"ok":true,"latency_ms":5,"error":null},"db_type":"mysql"}',
      alertChangesJson: '[]',
      triggeredBy: 'scheduler',
    );

HealthCheckResultDto _failResult(String startedAt, {String taskId = 't1'}) =>
    HealthCheckResultDto(
      id: 'r-$startedAt',
      taskId: taskId,
      startedAt: startedAt,
      status: 'failed',
      metricsSummaryJson:
          '{"connectivity":{"ok":false,"latency_ms":0,"error":"refused"},"db_type":"mysql"}',
      alertChangesJson: '[]',
      triggeredBy: 'scheduler',
    );

HealthCheckResultDto _alertResult(String startedAt,
        {String taskId = 't1', String metric = 'row_count'}) =>
    HealthCheckResultDto(
      id: 'r-$startedAt',
      taskId: taskId,
      startedAt: startedAt,
      status: 'success',
      metricsSummaryJson:
          '{"connectivity":{"ok":true,"latency_ms":5,"error":null},"db_type":"mysql"}',
      alertChangesJson:
          '[{"metric":"$metric","severity":"warning","trigger":"alert"}]',
      triggeredBy: 'scheduler',
    );

void main() {
  late _FakeHealthApi api;
  late HealthCheckProvider provider;

  setUp(() {
    api = _FakeHealthApi();
    // shouldRefresh: false → constructor's _evaluate stays quiet (no auto-refresh).
    provider = HealthCheckProvider(api: api, shouldRefresh: () => false);
  });

  tearDown(() => provider.dispose());

  test('doRefresh populates summary/task/recent per connection', () async {
    api.tasks = [_task('t1', 'conn-1'), _task('t2', 'conn-2')];
    api.resultsByTaskId = {
      't1': [_okResult('2026-08-12T07:00:00Z')],
      't2': [_alertResult('2026-08-12T07:00:00Z')],
    };

    await provider.doRefreshForTesting();

    expect(provider.summaryFor('conn-1')!.status, HealthStatus.healthy);
    expect(provider.summaryFor('conn-2')!.status, HealthStatus.warning);
    expect(provider.taskForConnection('conn-1')!.id, 't1');
    expect(provider.recentForConnection('conn-1').length, 1);
    expect(provider.tasks.length, 2);
  });

  test('alertedConnectionIds lists only warning/critical', () async {
    api.tasks = [_task('t1', 'c-ok'), _task('t2', 'c-warn'), _task('t3', 'c-crit')];
    api.resultsByTaskId = {
      't1': [_okResult('2026-08-12T07:00:00Z', taskId: 't1')],
      't2': [_alertResult('2026-08-12T07:00:00Z', taskId: 't2')],
      't3': [_failResult('2026-08-12T07:00:00Z', taskId: 't3')],
    };

    await provider.doRefreshForTesting();

    expect(provider.alertedConnectionIds, {'c-warn', 'c-crit'});
  });

  test('a single task result fetch failing leaves that conn unknown, others ok', () async {
    api.tasks = [_task('t1', 'c-ok'), _task('t2', 'c-fail')];
    api.failingResultTaskIds = {'t2'};
    api.resultsByTaskId = {
      't1': [_okResult('2026-08-12T07:00:00Z', taskId: 't1')],
      // t2 fetch throws → empty results → inferHealthSummary([]) = unknown
    };

    await provider.doRefreshForTesting();

    expect(provider.summaryFor('c-ok')!.status, HealthStatus.healthy);
    // c-fail: results fetch threw → resultsByTaskId['t2'] absent → [] → unknown.
    expect(provider.summaryFor('c-fail')!.status, HealthStatus.unknown);
    expect(api.logCalls, contains('listHealthResults(t2)'));
  });

  test('listHealthTasks failure keeps previous cache + sets lastError', () async {
    // Prime the cache with a successful refresh first.
    api.tasks = [_task('t1', 'c1')];
    api.resultsByTaskId = {
      't1': [_okResult('2026-08-12T07:00:00Z', taskId: 't1')],
    };
    await provider.doRefreshForTesting();
    expect(provider.summaryFor('c1')!.status, HealthStatus.healthy);

    // Now make listHealthTasks throw — cache must survive.
    api.listTasksError = const HealthApiException('network down');
    await provider.doRefreshForTesting();

    expect(provider.summaryFor('c1')!.status, HealthStatus.healthy); // retained
    expect(provider.lastError, isNotNull);
    expect(api.logCalls, contains('listHealthTasks'));
  });

  test('refresh() is a no-op when shouldRefresh guard returns false', () async {
    api.tasks = [_task('t1', 'c1')];
    api.resultsByTaskId = {
      't1': [_okResult('2026-08-12T07:00:00Z', taskId: 't1')],
    };

    // guard false → public refresh() must not touch the network.
    await provider.refresh();

    expect(provider.summaryFor('c1'), isNull); // unchanged
    expect(provider.lastRefreshAt, isNull);
  });

  test('evaluateForTesting with guard false clears the cache', () async {
    // Prime cache.
    api.tasks = [_task('t1', 'c1')];
    api.resultsByTaskId = {
      't1': [_okResult('2026-08-12T07:00:00Z', taskId: 't1')],
    };
    await provider.doRefreshForTesting();
    expect(provider.summaryFor('c1'), isNotNull);

    // Simulate disconnect: guard flips to false → _evaluate clears.
    provider.evaluateForTesting();

    expect(provider.summaryFor('c1'), isNull);
    expect(provider.tasks, isEmpty);
  });

  test('empty task list yields empty caches (no throw)', () async {
    api.tasks = const [];
    await provider.doRefreshForTesting();
    expect(provider.tasks, isEmpty);
    expect(provider.summaryFor('any'), isNull);
    expect(provider.lastError, isNull);
  });

  test('lastRefreshAt is set after a refresh', () async {
    api.tasks = [_task('t1', 'c1')];
    await provider.doRefreshForTesting();
    expect(provider.lastRefreshAt, isNotNull);
  });

  test('re-entrancy: concurrent doRefresh calls collapse', () async {
    api.tasks = [_task('t1', 'c1')];
    api.resultsByTaskId = {
      't1': [_okResult('2026-08-12T07:00:00Z', taskId: 't1')],
    };
    // Fire two refreshes; _isRefreshing guard makes the second a no-op.
    final f1 = provider.doRefreshForTesting();
    final f2 = provider.doRefreshForTesting();
    await Future.wait([f1, f2]);
    // Cache is populated exactly once; no exception.
    expect(provider.summaryFor('c1')!.status, HealthStatus.healthy);
  });
}
