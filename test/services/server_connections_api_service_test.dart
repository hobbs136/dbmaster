//! Unit tests for [ServerConnectionsApiService] (U05): the server-side
//! connection registry client backing the management dialog. Mock pattern
//! mirrors `data_sync_api_service_test.dart` (canned `_MockClient` +
//! `ServerConnection.testHttpClient` after a primed login).

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/server_connections_api_service.dart';
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
  }) => Future.value(_store[key]);

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

Map<String, dynamic> _row(String id, {String kind = 'collab'}) => {
  'id': id,
  'name': 'conn-$id',
  'db_type': 'mysql',
  'host': '127.0.0.1',
  'port': 3306,
  'username': 'u',
  'password_encrypted': 'ct',
  'default_database': null,
  'kind': kind,
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

  Future<void> primeConnected() async {
    final loginMock = _MockClient([
      _Canned(
        200,
        jsonEncode({
          'access_token': 'test-token',
          'refresh_token': 'test-refresh',
          'user': {'id': 'u1', 'email': 'a@b.c', 'display_name': 'A'},
        }),
      ),
    ]);
    conn.testHttpClient = loginMock;
    await conn.connect('https://test.example', 'a@b.c', 'pw');
  }

  test('listConnections parses rows including kind and filePath', () async {
    await primeConnected();
    final api = ServerConnectionsApiService(
      httpClient: _MockClient([
        _Canned(
          200,
          _okJson([
            _row('c1'),
            {..._row('c2'), 'kind': 'source_drift'},
            {
              ..._row('c3'),
              'db_type': 'sqlite',
              'host': 'sqlite',
              'port': 0,
              'file_path': '/data/chinook.sqlite',
            },
          ]),
        ),
      ]),
    );

    final rows = await api.listConnections();

    expect(rows, hasLength(3));
    expect(rows[0].isSourceDrift, isFalse);
    expect(rows[1].isSourceDrift, isTrue);
    expect(rows[2].filePath, '/data/chinook.sqlite');
    // SQLite rows label with the file path, not the sentinel host.
    expect(rows[2].hostLabel, '/data/chinook.sqlite');
    expect(rows[0].hostLabel, '127.0.0.1:3306');
  });

  test('createConnection sends kind=collab and file_path', () async {
    await primeConnected();
    final mock = _MockClient([_Canned(200, _okJson(_row('new-1')))]);
    final api = ServerConnectionsApiService(httpClient: mock);

    await api.createConnection(
      name: 'prod',
      dbType: 'mysql',
      host: '10.0.0.1',
      port: 3306,
      username: 'u',
      password: 'secret',
      defaultDatabase: 'app',
      filePath: null,
    );

    expect(mock.requests.single.url.path, '/api/connections');
    final body = jsonDecode(mock.bodies.single) as Map<String, dynamic>;
    expect(body['kind'], 'collab');
    expect(body['db_type'], 'mysql');
    expect(body['default_database'], 'app');
  });

  test('updateConnection omits empty password, keeps other fields', () async {
    await primeConnected();
    final mock = _MockClient([_Canned(200, _okJson(_row('c1')))]);
    final api = ServerConnectionsApiService(httpClient: mock);

    await api.updateConnection(
      'c1',
      name: 'renamed',
      password: '', // blank = keep the stored ciphertext server-side
      host: '10.0.0.2',
    );

    expect(mock.requests.single.method, 'PUT');
    expect(mock.requests.single.url.path, '/api/connections/c1');
    final body = jsonDecode(mock.bodies.single) as Map<String, dynamic>;
    expect(
      body.containsKey('password'),
      isFalse,
      reason: 'empty password must be omitted, not sent as ""',
    );
    expect(body['name'], 'renamed');
    expect(body['host'], '10.0.0.2');
  });

  test('updateConnection sends a supplied (non-empty) password', () async {
    await primeConnected();
    final mock = _MockClient([_Canned(200, _okJson(_row('c1')))]);
    final api = ServerConnectionsApiService(httpClient: mock);

    await api.updateConnection('c1', password: 'new-secret');

    final body = jsonDecode(mock.bodies.single) as Map<String, dynamic>;
    expect(body['password'], 'new-secret');
  });

  test('deleteConnection issues DELETE on the row path', () async {
    await primeConnected();
    final mock = _MockClient([
      _Canned(200, _okJson({'deleted': true})),
    ]);
    final api = ServerConnectionsApiService(httpClient: mock);

    await api.deleteConnection('c1');

    expect(mock.requests.single.method, 'DELETE');
    expect(mock.requests.single.url.path, '/api/connections/c1');
  });

  test('listTaskRefs returns raw task maps', () async {
    await primeConnected();
    final api = ServerConnectionsApiService(
      httpClient: _MockClient([
        _Canned(
          200,
          _okJson([
            {
              'id': 't1',
              'name': 'sync',
              'task_type': 'data_sync',
              'source_db_id': 'c1',
              'target_db_id': 'c2',
            },
          ]),
        ),
      ]),
    );

    final refs = await api.listTaskRefs();

    expect(refs, hasLength(1));
    expect(refs.first['source_db_id'], 'c1');
  });

  test('envelope error surfaces as typed exception with code', () async {
    await primeConnected();
    final api = ServerConnectionsApiService(
      httpClient: _MockClient([
        _Canned(
          404,
          jsonEncode({
            'ok': false,
            'data': null,
            'error': {'code': 'NOT_FOUND', 'message': 'connection not found'},
          }),
        ),
      ]),
    );

    await expectLater(
      api.updateConnection('gone', name: 'x'),
      throwsA(
        isA<ServerConnectionsApiException>().having(
          (e) => e.code,
          'code',
          'NOT_FOUND',
        ),
      ),
    );
  });

  test('401 surfaces as ServerConnectionsApiAuthException', () async {
    await primeConnected();
    final api = ServerConnectionsApiService(
      httpClient: _MockClient([
        const _Canned(401, '{"ok":false,"data":null,"error":null}'),
      ]),
    );

    await expectLater(
      api.listConnections(),
      throwsA(isA<ServerConnectionsApiAuthException>()),
    );
  });

  test('403 ENTITLEMENT_GATED surfaces as entitlement exception', () async {
    await primeConnected();
    final api = ServerConnectionsApiService(
      httpClient: _MockClient([
        _Canned(
          403,
          jsonEncode({
            'ok': false,
            'data': null,
            'error': {'code': 'ENTITLEMENT_GATED', 'message': 'gated'},
          }),
        ),
      ]),
    );

    await expectLater(
      api.createConnection(
        name: 'x',
        dbType: 'mysql',
        host: 'h',
        port: 3306,
        username: 'u',
        password: 'p',
      ),
      throwsA(isA<ServerConnectionsApiEntitlementException>()),
    );
  });
}
