//! Timeout wiring tests for the 11 server API service families
//! (sleep-resume fix batch T6 / D5 — test ids SVC-API-001..011, registered
//! in `docs/test/unified_test_spec.md` by the batch's registration task).
//!
//! Pattern per test (mirrors `drift_api_service_test.dart`):
//! 1. Prime `ServerConnection` into `connected` via a canned 200 login
//!    (fake secure storage — no platform channel in unit tests).
//! 2. Inject a [_HangingClient] whose `send` returns a never-completing
//!    future — simulates a server that accepts nothing (sleep/resume hang).
//! 3. Shorten [ApiHttpTimeouts.request] to a 20ms budget and assert `_send`
//!    fails within that budget with the service's EXISTING transport error
//!    type (D5: typed exception where the file has one, StateError where it
//!    doesn't), and that the message carries method+path but never the host.
//!
//! A hanging future can only settle via the wired timeout, so if the
//! `.timeout()` wiring regresses the test hangs and fails on the per-test
//! timeout — bounded behavior is asserted by construction. (`fake_async` was
//! considered but is not a declared dev dependency; importing a transitive
//! package would trip `depend_on_referenced_packages`.)

import 'dart:async';

import 'package:dbmaster/services/api_http_timeout.dart';
import 'package:dbmaster/services/approval_api_service.dart';
import 'package:dbmaster/services/connection_sync_service.dart';
import 'package:dbmaster/services/data_sync_api_service.dart';
import 'package:dbmaster/services/drift_api_service.dart';
import 'package:dbmaster/services/health_api_service.dart';
import 'package:dbmaster/services/mcp_token_api_service.dart';
import 'package:dbmaster/services/query_stats_api_service.dart';
import 'package:dbmaster/services/reports_api_service.dart';
import 'package:dbmaster/services/saved_query_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';
import 'package:dbmaster/services/server_connections_api_service.dart';
import 'package:dbmaster/services/workspace_api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Shortened per-request budget injected into [ApiHttpTimeouts.request].
const Duration _testBudget = Duration(milliseconds: 20);

/// In-memory `FlutterSecureStorage` fake (same as `drift_api_service_test`):
/// ServerConnection persists the refresh token via a MethodChannel that does
/// not exist under `flutter_tester`.
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) =>
      Future.value(_store[key]);

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
    return Future.value();
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    _store.remove(key);
    return Future.value();
  }
}

/// Fake client whose `send` never completes — the sleep/resume hang shape.
/// Works for both dispatch styles in the family: `client.get/post/...`
/// (which funnel into `send`) and the streamed `client.send(request)`.
class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

void main() {
  late ServerConnection conn;

  setUp(() {
    ServerConnection.resetForTesting();
    conn = ServerConnection();
    conn.testSecureStorage = _FakeSecureStorage();
    ApiHttpTimeouts.request = _testBudget;
  });

  tearDown(() {
    ApiHttpTimeouts.request = const Duration(seconds: 30);
    ServerConnection.resetForTesting();
  });

  /// Drive the singleton through `connect(...)` with a canned 200 login so
  /// every service sees `isConnected == true` (same seam as the per-service
  /// test files).
  Future<void> primeConnected() async {
    conn.testHttpClient = _LoginMockClient();
    await conn.connect('https://test.example', 'a@b.c', 'pw');
  }

  /// Matcher: fails with the service's typed transport error whose message
  /// carries method+path and never the host.
  Matcher transportError<T extends Object>(String methodAndPath) =>
      isA<T>().having(
        (e) => (e as dynamic).message as String,
        'message',
        allOf(contains(methodAndPath), isNot(contains('test.example'))),
      );

  group('server API family _send timeout (T6 / D5, SVC-API-001..011)', () {
    test('SVC-API-001 connection_sync: hanging request → StateError within '
        'budget', () async {
      await primeConnected();
      final svc = ConnectionSyncService.instance;
      svc.httpClient = _HangingClient();
      try {
        await expectLater(
          svc.listConnections(),
          throwsA(transportError<StateError>('GET /api/connections')),
        );
      } finally {
        svc.httpClient = null;
      }
    });

    test('SVC-API-002 drift: hanging request → DriftApiException within '
        'budget', () async {
      await primeConnected();
      final svc = DriftApiService(connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.listConnections(),
        throwsA(transportError<DriftApiException>('GET /api/connections')),
      );
    });

    test('SVC-API-003 data_sync: hanging request → DataSyncApiException '
        'within budget', () async {
      await primeConnected();
      final svc =
          DataSyncApiService(connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.listTasks(),
        throwsA(transportError<DataSyncApiException>('GET /api/tasks')),
      );
    });

    test('SVC-API-004 health: hanging request → HealthApiException within '
        'budget', () async {
      await primeConnected();
      final svc =
          HealthApiService(connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.listHealthTasks(),
        throwsA(transportError<HealthApiException>('GET /api/tasks')),
      );
    });

    test('SVC-API-005 saved_query: hanging request → SavedQueryApiException '
        'within budget', () async {
      await primeConnected();
      final svc = SavedQueryApiService(
          connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.list(),
        throwsA(transportError<SavedQueryApiException>('GET /api/queries')),
      );
    });

    test('SVC-API-006 mcp_token: hanging request → McpTokenApiException '
        'within budget', () async {
      await primeConnected();
      final svc =
          McpTokenApiService(connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.list(),
        throwsA(transportError<McpTokenApiException>('GET /api/mcp/tokens')),
      );
    });

    test('SVC-API-007 query_stats: hanging request → QueryStatsApiException '
        'within budget', () async {
      await primeConnected();
      final svc = QueryStatsApiService(
          connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.fetchSummary(),
        throwsA(transportError<QueryStatsApiException>(
            'GET /api/query-stats/summary')),
      );
    });

    test('SVC-API-008 reports: hanging request → ReportsApiException within '
        'budget', () async {
      await primeConnected();
      final svc =
          ReportsApiService(connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.listReports(),
        throwsA(transportError<ReportsApiException>('GET /api/reports')),
      );
    });

    test('SVC-API-009 workspace: hanging request → WorkspaceApiException '
        'within budget', () async {
      await primeConnected();
      final svc =
          WorkspaceApiService(connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.list(),
        throwsA(transportError<WorkspaceApiException>('GET /api/workspaces')),
      );
    });

    test('SVC-API-010 approval: hanging request → ApprovalApiException within '
        'budget', () async {
      await primeConnected();
      final svc =
          ApprovalApiService(connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.list(),
        throwsA(transportError<ApprovalApiException>('GET /api/approvals')),
      );
    });

    test('SVC-API-011 server_connections: hanging request → '
        'ServerConnectionsApiException within budget', () async {
      await primeConnected();
      final svc = ServerConnectionsApiService(
          connection: conn, httpClient: _HangingClient());
      await expectLater(
        svc.listConnections(),
        throwsA(
            transportError<ServerConnectionsApiException>('GET /api/connections')),
      );
    });
  });
}

/// One-shot 200 login mock used only to prime [ServerConnection] into
/// `connected` (same seam as the per-service test files).
class _LoginMockClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream.value(
        '{"access_token":"test-token","refresh_token":"test-refresh",'
        '"user":{"id":"u1","email":"a@b.c","display_name":"A"}}'
            .codeUnits,
      ),
      200,
    );
  }
}
