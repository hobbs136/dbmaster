//! Unit tests for [DriftApiService]. Uses programmable [http.BaseClient]
//! mocks on BOTH the ServerConnection (for the login seam) AND the
//! DriftApiService (for the API-call seam) — they are independent HTTP
//! clients in production too (ServerConnection owns its own, the service
//! injects a fresh one per call when not provided).

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/models/drift_models.dart';
import 'package:dbmaster/services/drift_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

/// In-memory `FlutterSecureStorage` fake. The production ServerConnection
/// persists the refresh token via FlutterSecureStorage, which uses a
/// MethodChannel that is not available in unit tests (per project test
/// conventions). This fake provides
/// the read/write/delete semantics without the platform channel.
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

/// Programmable mock: serves a queue of canned responses in order and
/// records every request seen. Modeled on the `_ProgrammableMockClient`
/// pattern in `test/services/ai/ai_client_claude_tools_test.dart`.
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

void main() {
  late ServerConnection conn;

  setUp(() {
    ServerConnection.resetForTesting();
    conn = ServerConnection();
    // Inject a fake secure storage — ServerConnection uses FlutterSecureStorage
    // to persist the refresh token, which has no MethodChannel in unit tests.
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

  group('DriftApiService — list endpoints', () {
    test('listDriftTasks filters to schema_drift rows', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson([
          {'id': 't1', 'name': 'drift 1', 'task_type': 'schema_drift',
            'source_db_id': 'c1', 'enabled': true,
            'config': '{"interval_minutes": 5}',
            'notify_channels': '["https://hook.example/x"]',
            'created_at': '2026-01-01T00:00:00Z',
            'last_run_at': null, 'last_status': null},
          {'id': 't2', 'name': 'other', 'task_type': 'data_sync',
            'source_db_id': 'c1', 'enabled': true, 'config': '{}',
            'notify_channels': '[]', 'created_at': '2026-01-01T00:00:00Z'},
        ])),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      final tasks = await svc.listDriftTasks();

      expect(tasks.length, equals(1));
      expect(tasks.first.id, equals('t1'));
      expect(tasks.first.config.intervalMinutes, equals(5));
      expect(tasks.first.notifyChannels, equals(['https://hook.example/x']));

      // Auth header was attached.
      final req = apiMock.requests.single;
      expect(req.headers['Authorization'], equals('Bearer test-token'));
    });

    test('listSourceDriftConnections filters by kind', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson([
          {'id': 'c1', 'name': 'src', 'db_type': 'mysql', 'host': 'h',
            'port': 3306, 'username': 'u', 'password_encrypted': 'CIPHER',
            'default_database': 'db', 'kind': 'source_drift',
            'created_by': 'u1', 'created_at': '2026-01-01T00:00:00Z'},
          {'id': 'c2', 'name': 'collab', 'db_type': 'mysql', 'host': 'h',
            'port': 3306, 'username': 'u', 'password_encrypted': 'CIPHER',
            'default_database': 'db', 'kind': 'collab',
            'created_by': 'u1', 'created_at': '2026-01-01T00:00:00Z'},
        ])),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      final srcs = await svc.listSourceDriftConnections();

      expect(srcs.length, equals(1));
      expect(srcs.first.id, equals('c1'));
      expect(srcs.first.isSourceDrift, isTrue);
      // SECURITY: ciphertext is parsed but never displayed by UI; sanity-check
      // it isn't accidentally dropped from the model.
      expect(srcs.first.passwordEncrypted, equals('CIPHER'));
      expect(srcs.first.hostLabel, equals('h:3306'));
    });
  });

  group('DriftApiService — create task', () {
    test('createDriftTask posts the expected envelope and parses row', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 'new1', 'name': 'my task', 'task_type': 'schema_drift',
          'source_db_id': 'c1', 'enabled': true,
          'config': '{"interval_minutes":10}',
          'notify_channels': '["https://hook.example/x"]',
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null, 'last_status': null,
        })),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      final task = await svc.createDriftTask(
        name: 'my task',
        sourceDbId: 'c1',
        config: const DriftTaskConfig(intervalMinutes: 10),
        webhookUrls: const ['https://hook.example/x'],
      );

      expect(task.id, equals('new1'));
      // Body shape matches the Server's CreateTaskRequest.
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body['name'], equals('my task'));
      expect(body['task_type'], equals('schema_drift'));
      expect(body['cron_expr'], equals(''));
      expect(body['source_db_id'], equals('c1'));
      expect(body['config'], equals({'interval_minutes': 10}));
      expect(body['notify_channels'], equals(['https://hook.example/x']));
    });

    test('runTaskNow tolerates empty 202 body', () async {
      await primeConnected();
      final apiMock = _MockClient([
        const _Canned(202, ''),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      await svc.runTaskNow('t1');
      expect(apiMock.requests.single.method, equals('POST'));
      expect(apiMock.requests.single.url.path, contains('/api/tasks/t1/run'));
    });
  });

  group('DriftApiService — error mapping', () {
    test('403 ENTITLEMENT_GATED → DriftApiEntitlementException', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(403, jsonEncode({
          'ok': false, 'data': null,
          'error': {'code': 'ENTITLEMENT_GATED', 'message': 'gated'},
        })),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      await expectLater(
        () => svc.createDriftTask(
          name: 'x',
          sourceDbId: 'c1',
          config: const DriftTaskConfig(intervalMinutes: 5),
        ),
        throwsA(isA<DriftApiEntitlementException>()),
      );
    });

    test('401 → DriftApiAuthException', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(401, jsonEncode({'ok': false, 'data': null,
          'error': {'code': 'AUTH', 'message': 'expired'}})),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      await expectLater(
        () => svc.listDriftTasks(),
        throwsA(isA<DriftApiAuthException>()),
      );
    });

    test('CANARY_REJECTED surfaces as DriftApiException with code', () async {
      // The Server's create_connection handler returns Ok(...) with ok=false
      // even for canary failures (HTTP 200, error envelope); the service
      // should still surface the structured error.
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, jsonEncode({
          'ok': false, 'data': null,
          'error': {'code': 'CANARY_REJECTED',
            'message': 'source account is writable'},
        })),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      late DriftApiException caught;
      try {
        await svc.createSourceDriftConnection(
          name: 'src', dbType: 'mysql', host: 'h', port: 3306,
          username: 'u', password: 'p',
        );
        fail('expected exception');
      } on DriftApiException catch (e) {
        caught = e;
      }
      expect(caught.code, equals('CANARY_REJECTED'));
      expect(caught.message, contains('source account is writable'));
    });
  });

  group('DriftApiService — not connected', () {
    test('throws DriftApiException when no server session', () async {
      // No primeConnected call — singleton stays disconnected.
      final svc = DriftApiService(connection: conn, httpClient: _MockClient([]));
      await expectLater(
        () => svc.listDriftTasks(),
        throwsA(isA<DriftApiException>()),
      );
    });
  });

  group('DriftApiService — patchTask (#27 partial PATCH)', () {
    test('patchTask sends PATCH with non-null fields only', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 'd1',
          'name': 'renamed',
          'task_type': 'schema_drift',
          'source_db_id': 'c1',
          'enabled': false,
          'config': '{}',
          'notify_channels': '[]',
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null,
          'last_status': null,
        })),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      final updated = await svc.patchTask(
        'd1',
        name: 'renamed',
        enabled: false,
        notifyChannels: const ['https://hook.example/x'],
      );

      expect(updated['name'], equals('renamed'));
      expect(apiMock.requests.single.method, equals('PATCH'));
      expect(apiMock.requests.single.url.path, equals('/api/tasks/d1'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('name', 'renamed'));
      expect(body, containsPair('enabled', false));
      expect(body, containsPair('notify_channels', ['https://hook.example/x']));
      // drift is interval-driven; cron_expr/config/target omitted.
      expect(body.containsKey('cron_expr'), isFalse);
      expect(body.containsKey('config'), isFalse);
    });

    test('setEnabled toggles only the enabled field', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 'd1',
          'name': 'n',
          'task_type': 'schema_drift',
          'source_db_id': 'c1',
          'enabled': true,
          'config': '{}',
          'notify_channels': '[]',
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null,
          'last_status': null,
        })),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      await svc.setEnabled('d1', true);

      expect(apiMock.requests.single.method, equals('PATCH'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('enabled', true));
      expect(body.length, equals(1));
    });

    test('patchTaskConfig sends the replacement config object (U09)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 'd1',
          'name': 'n',
          'task_type': 'schema_drift',
          'source_db_id': 'c1',
          'enabled': true,
          'config':
              '{"interval_minutes":15,"pg_schemas":["public","audit"]}',
          'notify_channels': '[]',
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null,
          'last_status': null,
        })),
      ]);
      final svc = DriftApiService(connection: conn, httpClient: apiMock);
      final updated = await svc.patchTaskConfig('d1', {
        'interval_minutes': 15,
        'pg_schemas': ['public', 'audit'],
      });

      expect(updated['config'], contains('15'));
      expect(apiMock.requests.single.method, equals('PATCH'));
      expect(apiMock.requests.single.url.path, equals('/api/tasks/d1'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      // Whole-config replacement — no other task fields may ride along.
      expect(
        body,
        containsPair('config', {
          'interval_minutes': 15,
          'pg_schemas': ['public', 'audit'],
        }),
      );
      expect(body.length, equals(1));
    });
  });
}
