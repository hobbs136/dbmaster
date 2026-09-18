//! ChangeNotifier that periodically pulls DDL approvals from the Server and
//! caches them for the status-bar pending badge + the approval queue dialog.
//!
//! Refresh cadence: 60s (approvals are event-driven — submitted or resolved by
//! a person — so the client need not poll faster than human reaction time). The
//! [ApprovalListDialog] runs its own faster 3s poll while open to surface the
//! `executing → approved/failed` transition; this provider's 60s cycle keeps
//! the closed-window badge fresh. Embedded mode + disconnected states never
//! refresh — approvals are a Server-only, remote-mode feature (DDL execution
//! requires the Server's decrypted credentials + spawn runtime).
//!
//! Mirrors `HealthCheckProvider`: listens to `ServerConnection.state`, reacts
//! on transition to `connected` (non-embedded). The refresh guard is injected
//! ([shouldRefresh]) so unit tests can exercise the data flow
//! ([doRefreshForTesting]) without driving the ServerConnection singleton.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ddl_approval.dart';
import '../services/approval_api_service.dart';
import '../services/server_connection.dart';
import '../utils/app_logger.dart';

class ApprovalProvider extends ChangeNotifier {
  final ApprovalApiService _api;
  final ServerConnection _connection;
  final bool Function() _shouldRefreshFn;

  List<DdlApproval> _approvals = const [];
  Timer? _timer;
  bool _isRefreshing = false;
  DateTime? _lastRefreshAt;
  Object? _lastError;

  /// Polling interval. Approvals change on human timescale; 60s keeps the
  /// status-bar badge fresh without hammering the read endpoint.
  static const Duration _refreshInterval = Duration(seconds: 60);

  ApprovalProvider({
    ApprovalApiService? api,
    ServerConnection? connection,
    bool Function()? shouldRefresh,
  })  : _api = api ?? ApprovalApiService(),
        _connection = connection ?? ServerConnection(),
        _shouldRefreshFn = shouldRefresh ?? _defaultShouldRefresh {
    _connection.state.addListener(_onConnectionChanged);
    // Pick up an already-connected session (mirrors HealthCheckProvider).
    _evaluate();
  }

  static bool _defaultShouldRefresh() {
    final c = ServerConnection();
    return c.connectionState == ServerConnectionState.connected &&
        !c.isEmbeddedMode;
  }

  // ── Getters ──

  /// All cached approvals (newest first, as returned by the Server).
  List<DdlApproval> get approvals =>
      List<DdlApproval>.unmodifiable(_approvals);

  /// Count of approvals awaiting review — drives the status-bar badge.
  int get pendingCount =>
      _approvals.where((a) => a.isPending).length;

  /// Count of approvals whose DDL is currently executing — used by the dialog
  /// to decide whether to keep its fast poll running.
  int get executingCount =>
      _approvals.where((a) => a.isExecuting).length;

  DateTime? get lastRefreshAt => _lastRefreshAt;
  Object? get lastError => _lastError;
  bool get isRefreshing => _isRefreshing;

  // ── Actions ──

  /// Force a refresh now (e.g. dialog opened, manual pull). Self-guards on the
  /// refresh pre-condition + re-entrancy.
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
      final list = await _api.list();
      _approvals = list;
      _lastError = null;
    } catch (e) {
      // Keep the previous cache (avoid badge flicker on a transient blip).
      AppLogger.w('ApprovalProvider', 'list failed: $e');
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
    if (_approvals.isEmpty) return; // nothing to clear; skip notify.
    _approvals = const [];
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
