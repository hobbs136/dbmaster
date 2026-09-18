//! Unit tests for [DataSyncApiService.patchTask] (#27). The generic `_send`
//! path (`http.Request` + `client.send`) is shared with the rest of the
//! service, so this also exercises the PATCH method through data_sync's
//! plumbing. Mock pattern mirrors `health_api_service_test.dart`.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/data_sync_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) =>
      Future.value(_store[key]);

  @override
  Future<void> write({
    required String key,
    required String? value,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
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
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) {
    _store.remove(key);
    return Future.value();
  }
}

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
    conn.testSecureStorage = _FakeSecureStorage();
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

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

  group('DataSyncApiService — patchTask (#27 partial PATCH)', () {
    test('patchTask sends PATCH via the generic _send path', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 's1',
          'name': 'renamed',
          'task_type': 'data_sync',
          'cron_expr': '*/10 * * * *',
          'config': {},
          'source_db_id': 'c1',
          'target_db_id': 'c2',
          'enabled': true,
          'notify_channels': ['https://hook.example/x'],
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null,
          'last_status': null,
        })),
      ]);
      final svc = DataSyncApiService(connection: conn, httpClient: apiMock);
      final updated = await svc.patchTask(
        's1',
        name: 'renamed',
        cronExpr: '*/10 * * * *',
        notifyChannels: const ['https://hook.example/x'],
      );

      expect(updated['name'], equals('renamed'));
      expect(apiMock.requests.single.method, equals('PATCH'));
      expect(apiMock.requests.single.url.path, equals('/api/tasks/s1'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('name', 'renamed'));
      expect(body, containsPair('cron_expr', '*/10 * * * *'));
      expect(body, containsPair('notify_channels', ['https://hook.example/x']));
      // enabled not passed → omitted (server Option<T> + serde(default)).
      expect(body.containsKey('enabled'), isFalse);
    });

    test('setEnabled toggles only the enabled field', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({
          'id': 's1',
          'name': 'n',
          'task_type': 'data_sync',
          'cron_expr': '',
          'config': {},
          'source_db_id': 'c1',
          'target_db_id': null,
          'enabled': false,
          'notify_channels': [],
          'created_at': '2026-01-01T00:00:00Z',
          'last_run_at': null,
          'last_status': null,
        })),
      ]);
      final svc = DataSyncApiService(connection: conn, httpClient: apiMock);
      await svc.setEnabled('s1', false);

      expect(apiMock.requests.single.method, equals('PATCH'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('enabled', false));
      expect(body.length, equals(1));
    });
  });
}
