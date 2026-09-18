//! Unit tests for [HealthApiService]. Mirrors `drift_api_service_test`'s mock
//! pattern: programmable [http.BaseClient] on BOTH the ServerConnection (login
//! seam) AND the service (API-call seam). Helper duplication across service
//! tests is explicitly allowed by the project test patterns.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/models/health_summary.dart';
import 'package:dbmaster/services/health_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

/// In-memory `FlutterSecureStorage` fake (same shape as the drift service test).
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

/// Programmable mock: serves a queue of canned responses in order and records
/// every request seen (modeled on drift_api_service_test's `_MockClient`).
class _MockClient extends http.BaseClient {
  final List<_Canned> responses;
  int _cursor = 0;
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];

  _MockClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(request is http.Request ? request.body : '');
    final next = _cursor < responses.length
        ? responses[_cursor]
        : const _Canned(404, '{}');
    _cursor++;
    return http.StreamedResponse(
      Stream.value(utf8.encode(next.body)),
      next.status,
    );
  }
}

class _Canned {
  final int status;
  final String body;
  const _Canned(this.status, this.body);
}

String _okJson(Object? data) =>
    jsonEncode({'ok': true, 'data': data, 'error': null});

/// Minimal `database_connections` row shape (matches what the Server returns
/// and what `DriftSourceConnection.fromJson` consumes).
Map<String, dynamic> _connRow({
  required String id,
  required String name,
  required String dbType,
  required String host,
  required int port,
  String kind = 'collab',
}) =>
    {
      'id': id,
      'name': name,
      'db_type': dbType,
      'host': host,
      'port': port,
      'username': 'u',
      'password_encrypted': 'CIPHER',
      'default_database': 'db',
      'kind': kind,
      'created_by': 'u1',
      'created_at': '2026-01-01T00:00:00Z',
    };

void main() {
  late ServerConnection conn;

  setUp(() {
    ServerConnection.resetForTesting();
    conn = ServerConnection();
    conn.testSecureStorage = _FakeSecureStorage();
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  /// Drive the singleton through `connect(...)` with a canned 200 login so the
  /// service sees `isConnected == true` and a non-null access token.
  Future<void> primeConnected() async {
    final loginMock = _MockClient([
      _Canned(200, jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'user': {'id': 'u1', 'email': 'a@b.c', 'display_name': 'A'},
      })),
    ]);
    conn.testHttpClient = loginMock;
    await conn.connect('https://test.example', 'a@b.c', 'pw');
  }

  group('HealthApiService — create task', () {
    test('createTask posts health_check envelope with target_db_id null',
        () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 'h1',
          'name': 'my probe',
          'task_type': 'health_check',
          'source_db_id': 'c1',
          'enabled': true,
          'cron_expr': '*/5 * * * *',
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null,
          'last_status': null,
        })),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);
      final task = await svc.createTask(
        name: 'my probe',
        sourceDbId: 'c1',
        cronExpr: '*/5 * * * *',
        config: const HealthCheckTaskConfig(failThreshold: 5).toJson(),
        notifyChannels: const ['https://hook.example/x'],
      );

      expect(task.id, equals('h1'));
      expect(task.cronExpr, equals('*/5 * * * *'));
      expect(task.sourceDbId, equals('c1'));

      // Body shape matches the Server's CreateTaskRequest.
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body['name'], equals('my probe'));
      expect(body['task_type'], equals('health_check'));
      expect(body['cron_expr'], equals('*/5 * * * *'));
      expect(body['source_db_id'], equals('c1'));
      // health_check inspects a single source; target is always null.
      expect(body['target_db_id'], isNull);
      expect(
          body['config'],
          equals({
            'metrics': {
              'connectivity': true,
              'row_count': true,
              'missing_pk': true,
              'connection_count': true,
            },
            'fail_threshold': 5,
            'large_table_threshold': 10000000,
            'connection_count_threshold': 100,
            'retention_days': 30,
          }));
      expect(body['notify_channels'], equals(['https://hook.example/x']));

      // Auth header attached.
      expect(apiMock.requests.single.headers['Authorization'],
          equals('Bearer test-token'));
    });
  });

  group('HealthApiService — list endpoints', () {
    test('listConnections returns ALL rows (no kind filter, unlike drift)',
        () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson([
          _connRow(id: 'c1', name: 'src', dbType: 'mysql', host: 'h', port: 3306,
              kind: 'source_drift'),
          _connRow(id: 'c2', name: 'prod', dbType: 'postgres', host: 'p',
              port: 5432, kind: 'collab'),
        ])),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);
      final conns = await svc.listConnections();

      // Both kinds returned — health_check accepts any database_connection.
      expect(conns.length, equals(2));
      expect(conns.first.id, equals('c1'));
      expect(conns.first.hostLabel, equals('h:3306'));
      expect(conns.last.id, equals('c2'));
    });

    test('fetchEntitlement parses gated state', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({'state': 'gated', 'reason': 'trial_expired'})),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);
      final ent = await svc.fetchEntitlement();
      expect(ent.isGated, isTrue);
    });
  });

  group('HealthApiService — error mapping', () {
    test('403 ENTITLEMENT_GATED → HealthApiEntitlementException', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(403, jsonEncode({
          'ok': false,
          'data': null,
          'error': {'code': 'ENTITLEMENT_GATED', 'message': 'gated'},
        })),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);
      await expectLater(
        () => svc.createTask(
          name: 'x',
          sourceDbId: 'c1',
          cronExpr: '*/5 * * * *',
        ),
        throwsA(isA<HealthApiEntitlementException>()),
      );
    });

    test('401 → HealthApiAuthException', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(401, jsonEncode({
          'ok': false,
          'data': null,
          'error': {'code': 'AUTH', 'message': 'expired'},
        })),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);
      await expectLater(
        () => svc.listConnections(),
        throwsA(isA<HealthApiAuthException>()),
      );
    });
  });

  group('HealthApiService — not connected', () {
    test('throws HealthApiException when no server session', () async {
      // No primeConnected — singleton stays disconnected.
      final svc = HealthApiService(connection: conn, httpClient: _MockClient([]));
      await expectLater(
        () => svc.listConnections(),
        throwsA(isA<HealthApiException>()),
      );
    });
  });

  group('HealthApiService — patchTask (#27 partial PATCH)', () {
    test('patchTask sends PATCH with only non-null fields', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 'h1',
          'name': 'renamed',
          'task_type': 'health_check',
          'source_db_id': 'c1',
          'enabled': false,
          'cron_expr': '0 * * * *',
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null,
          'last_status': null,
          'notify_channels': ['https://hook.example/x'],
        })),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);
      final updated = await svc.patchTask(
        'h1',
        name: 'renamed',
        enabled: false,
        cronExpr: '0 * * * *',
        notifyChannels: const ['https://hook.example/x'],
      );

      // Server returns the full task object.
      expect(updated['name'], equals('renamed'));
      expect(updated['enabled'], equals(false));

      // Request shape: PATCH /api/tasks/h1 with only the patched fields.
      expect(apiMock.requests.single.method, equals('PATCH'));
      expect(apiMock.requests.single.url.path, equals('/api/tasks/h1'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('name', 'renamed'));
      expect(body, containsPair('enabled', false));
      expect(body, containsPair('cron_expr', '0 * * * *'));
      expect(body, containsPair('notify_channels', ['https://hook.example/x']));
      // Absent fields are omitted (server Option<T> + serde(default)).
      expect(body.containsKey('config'), isFalse);
      expect(body.containsKey('target_db_id'), isFalse);
    });

    test('setEnabled is a thin wrapper over patchTask', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 'h1',
          'name': 'n',
          'task_type': 'health_check',
          'source_db_id': 'c1',
          'enabled': false,
          'cron_expr': '*/5 * * * *',
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null,
          'last_status': null,
        })),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);
      await svc.setEnabled('h1', false);

      expect(apiMock.requests.single.method, equals('PATCH'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('enabled', false));
      // Only enabled is sent by the wrapper.
      expect(body.length, equals(1));
    });
  });

  group('HealthApiService — deleteTask (#28)', () {
    test('deleteTask sends DELETE /api/tasks/:id and tolerates the ok envelope',
        () async {
      await primeConnected();
      // Server returns 200 {ok:true,data:{deleted:true}} (NOT 204) — see
      // automation/src/handler.rs::delete_task.
      final apiMock = _MockClient([
        _Canned(200, _okJson({'deleted': true})),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);

      await svc.deleteTask('h1');

      expect(apiMock.requests.single.method, equals('DELETE'));
      expect(apiMock.requests.single.url.path, equals('/api/tasks/h1'));
      // DELETE has no body.
      expect(apiMock.bodies.single, isEmpty);
    });

    test('deleteTask surfaces 401 as HealthApiAuthException', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(401, jsonEncode({'ok': false, 'error': {'code': 'UNAUTHORIZED'}})),
      ]);
      final svc = HealthApiService(connection: conn, httpClient: apiMock);

      await expectLater(
          () => svc.deleteTask('h1'), throwsA(isA<HealthApiAuthException>()));
    });
  });
}
