//! ChangeNotifier that periodically pulls the caller's workspaces from the
//! Server and caches them for the Workspaces manager dialog (#26).
//!
//! Refresh cadence: 60s. Workspaces change on human timescale (created / joined
//! / left by a person), so the client need not poll faster. The manager dialog
//! runs its own manual refresh on open + after each mutating action; this
//! provider's 60s cycle keeps a background cache warm for any future consumer.
//!
//! Mirrors `ApprovalProvider`: listens to `ServerConnection.state`, reacts on
//! transition to `connected` (non-embedded). The refresh guard is injected
//! ([shouldRefresh]) so unit tests can exercise the data flow
//! ([doRefreshForTesting]) without driving the ServerConnection singleton.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/workspace.dart';
import '../services/server_connection.dart';
import '../services/workspace_api_service.dart';
import '../utils/app_logger.dart';

class WorkspaceProvider extends ChangeNotifier {
  final WorkspaceApiService _api;
  final ServerConnection _connection;
  final bool Function() _shouldRefreshFn;

  List<Workspace> _workspaces = const [];
  Timer? _timer;
  bool _isRefreshing = false;
  DateTime? _lastRefreshAt;
  Object? _lastError;

  /// Polling interval. Workspaces change on human timescale; 60s keeps the
  /// cache fresh without hammering the read endpoint.
  static const Duration _refreshInterval = Duration(seconds: 60);

  WorkspaceProvider({
    WorkspaceApiService? api,
    ServerConnection? connection,
    bool Function()? shouldRefresh,
  })  : _api = api ?? WorkspaceApiService(),
        _connection = connection ?? ServerConnection(),
        _shouldRefreshFn = shouldRefresh ?? _defaultShouldRefresh {
    _connection.state.addListener(_onConnectionChanged);
    // Pick up an already-connected session (mirrors ApprovalProvider).
    _evaluate();
  }

  static bool _defaultShouldRefresh() {
    final c = ServerConnection();
    return c.connectionState == ServerConnectionState.connected &&
        !c.isEmbeddedMode;
  }

  // ── Getters ──

  /// All cached workspaces the caller is a member of (newest first).
  List<Workspace> get workspaces => List<Workspace>.unmodifiable(_workspaces);

  DateTime? get lastRefreshAt => _lastRefreshAt;
  Object? get lastError => _lastError;
  bool get isRefreshing => _isRefreshing;

  // ── Actions ──

  /// Force a refresh now (e.g. dialog opened, after a create/join/leave).
  /// Self-guards on the refresh pre-condition + re-entrancy.
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
      _workspaces = list;
      _lastError = null;
    } catch (e) {
      // Keep the previous cache (avoid flicker on a transient blip).
      AppLogger.w('WorkspaceProvider', 'list failed: $e');
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
    if (_workspaces.isEmpty) return; // nothing to clear; skip notify.
    _workspaces = const [];
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
