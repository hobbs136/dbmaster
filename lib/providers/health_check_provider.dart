//! ChangeNotifier that periodically pulls health-check task results from the
//! Server and caches a per-connection [HealthSummary] for the sidebar
//! indicator + history dialog.
//!
//! Refresh cadence: 60s (health_check is minute-cron; clients need not poll
//! faster). Embedded mode + disconnected states never refresh — health_check
//! is a Server-only, remote-mode feature (embedded uses NoopHealthCheckRunner,
//! ADR-0004 §2.6).
//!
//! Mirrors `ServerConnectionProvider`'s "listen to ServerConnection.state +
//! react" pattern: a transition to `connected` (non-embedded) starts the timer
//! + an immediate refresh; anything else stops the timer and clears the cache
//! so the indicator returns to `unknown`.
//!
//! Testability: the refresh guard is injected ([shouldRefresh]) so unit tests
//! can exercise the data flow ([doRefreshForTesting]) without driving the
//! ServerConnection singleton into a connected state.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/health_summary.dart';
import '../services/health_api_service.dart';
import '../services/server_connection.dart';

class HealthCheckProvider extends ChangeNotifier {
  final HealthApiService _api;
  final ServerConnection _connection;
  final bool Function() _shouldRefreshFn;

  /// Per-connection inferred status (key = `source_db_id` = sidebar connection id).
  final Map<String, HealthSummary> _summaryByConnId = {};

  /// Per-connection health task (for the history dialog header).
  final Map<String, HealthTask> _taskByConnId = {};

  /// Per-connection recent results window (limit = [_windowLimit]).
  final Map<String, List<HealthCheckResultDto>> _recentByConnId = {};

  Timer? _timer;
  bool _isRefreshing = false;
  DateTime? _lastRefreshAt;
  Object? _lastError;

  /// Polling interval. health_check runs on minute-cron server-side; 60s on the
  /// client is frequent enough to surface a new result without hammering.
  static const Duration _refreshInterval = Duration(seconds: 60);

  /// How many recent results to fetch per task. Drives [inferHealthSummary]'s
  /// window — 5 balances accuracy against request volume.
  static const int _windowLimit = 5;

  HealthCheckProvider({
    HealthApiService? api,
    ServerConnection? connection,
    bool Function()? shouldRefresh,
  })  : _api = api ?? HealthApiService(),
        _connection = connection ?? ServerConnection(),
        _shouldRefreshFn = shouldRefresh ?? _defaultShouldRefresh {
    _connection.state.addListener(_onConnectionChanged);
    // Pick up an already-connected session (e.g. embedded restore that happened
    // before this provider existed) — mirrors ServerConnectionProvider._syncFromService.
    _evaluate();
  }

  static bool _defaultShouldRefresh() {
    final c = ServerConnection();
    return c.connectionState == ServerConnectionState.connected &&
        !c.isEmbeddedMode;
  }

  // ── Getters ──

  /// Summary for a sidebar connection, or null if no health task covers it
  /// (caller renders the `unknown` indicator).
  HealthSummary? summaryFor(String connectionId) =>
      _summaryByConnId[connectionId];

  /// Task for a connection (history dialog header), or null.
  HealthTask? taskForConnection(String connectionId) =>
      _taskByConnId[connectionId];

  /// Recent results window for a connection (history dialog body), empty if none.
  List<HealthCheckResultDto> recentForConnection(String connectionId) =>
      _recentByConnId[connectionId] ?? const [];

  /// All cached health tasks (e.g. for a global status menu).
  List<HealthTask> get tasks => _taskByConnId.values.toList(growable: false);

  /// Connection ids that currently have an active alert (warning/critical) —
  /// useful for a sidebar footer badge count.
  Set<String> get alertedConnectionIds => _summaryByConnId.entries
      .where((e) =>
          e.value.status == HealthStatus.warning ||
          e.value.status == HealthStatus.critical)
      .map((e) => e.key)
      .toSet();

  DateTime? get lastRefreshAt => _lastRefreshAt;
  Object? get lastError => _lastError;
  bool get isRefreshing => _isRefreshing;

  // ── Actions ──

  /// Force a refresh now (e.g. dialog opened, manual pull). Self-guards on the
  /// refresh pre-condition + re-entrancy; returns immediately if the desktop
  /// is not in a refreshable state or a refresh is already in flight.
  Future<void> refresh() async {
    if (!_shouldRefresh) return;
    await _doRefresh();
  }

  /// Test-only entry point that bypasses the [_shouldRefresh] guard, so unit
  /// tests can exercise the data flow without driving ServerConnection into a
  /// connected state. Still respects re-entrancy (_isRefreshing).
  @visibleForTesting
  Future<void> doRefreshForTesting() => _doRefresh();

  Future<void> _doRefresh() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();
    try {
      final tasks = await _api.listHealthTasks();

      // Fan out per-task result fetches concurrently (N tasks → N parallel
      // requests; task counts are typically single-digit). A single task's
      // fetch failing is logged + skipped; the rest still update.
      final resultsByTaskId = <String, List<HealthCheckResultDto>>{};
      await Future.wait(tasks.map((t) async {
        try {
          resultsByTaskId[t.id] =
              await _api.listHealthResults(t.id, limit: _windowLimit);
        } catch (e) {
          _api.logError('listHealthResults(${t.id})', e);
        }
      }));

      // Rebuild caches keyed by connection id.
      _summaryByConnId.clear();
      _taskByConnId.clear();
      _recentByConnId.clear();
      for (final t in tasks) {
        final connId = t.sourceDbId;
        _taskByConnId[connId] = t;
        final results = resultsByTaskId[t.id] ?? const <HealthCheckResultDto>[];
        _recentByConnId[connId] = results;
        // U06 — the task row's last_status backstops the results window
        // (rotated rows / failed fetches surface as critical, not unknown).
        _summaryByConnId[connId] = inferHealthSummary(
          results,
          taskLastStatus: t.lastStatus,
          taskLastRunAt: t.lastRunAt,
        );
      }
      _lastError = null;
    } catch (e) {
      // listHealthTasks itself failed (auth/network) — keep the previous cache
      // (avoid indicator flicker on a transient blip) and record the error.
      _api.logError('listHealthTasks', e);
      _lastError = e;
    } finally {
      _isRefreshing = false;
      _lastRefreshAt = DateTime.now();
      notifyListeners();
    }
  }

  // ── Timer + connection-state wiring ──

  bool get _shouldRefresh => _shouldRefreshFn();

  void _onConnectionChanged() => _evaluate();

  @visibleForTesting
  void evaluateForTesting() => _evaluate();

  void _evaluate() {
    if (_shouldRefresh) {
      _startTimerIfNeeded();
      // Fire-and-forget; _doRefresh guards itself on re-entrancy.
      refresh();
    } else {
      _stopTimer();
      _clear();
    }
  }

  void _startTimerIfNeeded() {
    if (_timer != null) return;
    _timer = Timer.periodic(_refreshInterval, (_) => _doRefresh());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _clear() {
    if (_summaryByConnId.isEmpty &&
        _taskByConnId.isEmpty &&
        _recentByConnId.isEmpty) {
      return; // nothing to clear; skip notify.
    }
    _summaryByConnId.clear();
    _taskByConnId.clear();
    _recentByConnId.clear();
    _lastError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _connection.state.removeListener(_onConnectionChanged);
    _stopTimer();
    super.dispose();
  }
}
