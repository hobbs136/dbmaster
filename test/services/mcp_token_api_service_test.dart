//! Unit tests for [McpTokenApiService] (T04b). Covers list/create/revoke
//! against the `{ok,data,error}` envelope, typed 401, NOT_FOUND surfacing,
//! and the not-connected short-circuit. Mock pattern mirrors
//! `saved_query_api_service_test.dart`.
//!
//! Additionally: an env-gated end-to-end group (`--dart-define=
//! DBMASTER_MCP_E2E=1` + a live local dbmaster-server on
//! `--dart-define=DBMASTER_MCP_E2E_URL=...`) walks the real
//! create→list→revoke lifecycle with the real HTTP stack.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/mcp_token_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

const bool _e2eEnabled = bool.fromEnvironment('DBMASTER_MCP_E2E');
const String _e2eUrl = String.fromEnvironment(
  'DBMASTER_MCP_E2E_URL',
  defaultValue: 'http://127.0.0.1:3999',
);

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

class _Canned {
  final int status;
  final String body;
  const _Canned(this.status, this.body);
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

String _okJson(Object data) =>
    jsonEncode({'ok': true, 'data': data, 'error': null});

Map<String, dynamic> _row({
  required String id,
  String name = 'claude-code',
  String prefix = 'dbm_mcp_9f2a',
  String? lastUsed,
}) =>
    {
      'id': id,
      'name': name,
      'token_prefix': prefix,
      'created_at': '2026-08-15T10:00:00+00:00',
      'last_used_at': lastUsed,
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
      _Canned(200, jsonEncode({
        'access_token': 'test-token',
        'refresh_token': 'test-refresh',
        'user': {'id': 'u1', 'email': 'a@b.c', 'display_name': 'A'},
      })),
    ]);
    conn.testHttpClient = loginMock;
    await conn.connect('https://test.example', 'a@b.c', 'pw');
  }

  group('McpTokenApiService — list', () {
    test('sends GET and parses envelope rows (no secret fields)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson([
          _row(id: 't1', lastUsed: '2026-08-15T11:00:00+00:00'),
          _row(id: 't2', name: 'cursor'),
        ])),
      ]);
      final svc = McpTokenApiService(connection: conn, httpClient: apiMock);

      final tokens = await svc.list();

      expect(apiMock.requests.single.method, equals('GET'));
      expect(apiMock.requests.single.url.path, equals('/api/mcp/tokens'));
      expect(tokens.length, equals(2));
      expect(tokens[0].id, equals('t1'));
      expect(tokens[0].name, equals('claude-code'));
      expect(tokens[0].tokenPrefix, equals('dbm_mcp_9f2a'));
      expect(tokens[0].lastUsedAt, isNotNull);
      expect(tokens[1].lastUsedAt, isNull);
    });

    test('non-list data degrades to empty list', () async {
      await primeConnected();
      final apiMock =
          _MockClient([_Canned(200, _okJson({'unexpected': 'map'}))]);
      final svc = McpTokenApiService(connection: conn, httpClient: apiMock);
      expect(await svc.list(), isEmpty);
    });
  });

  group('McpTokenApiService — create', () {
    test('POSTs name and parses the one-time plaintext', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(201, _okJson({
          'id': 't9',
          'name': 'claude-code-mac',
          'token': 'dbm_mcp_f4c4f66260d0',
          'created_at': '2026-08-15T10:55:38+00:00',
        })),
      ]);
      final svc = McpTokenApiService(connection: conn, httpClient: apiMock);

      final created = await svc.create(name: 'claude-code-mac');

      expect(apiMock.requests.single.method, equals('POST'));
      expect(
          jsonDecode(apiMock.bodies.single),
          equals({'name': 'claude-code-mac'}));
      expect(created.id, equals('t9'));
      expect(created.token, equals('dbm_mcp_f4c4f66260d0'));
    });

    test('blank name sends an empty body (server default applies)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(201, _okJson({
          'id': 't10',
          'name': 'MCP token',
          'token': 'dbm_mcp_x',
          'created_at': '2026-08-15T10:55:38+00:00',
        })),
      ]);
      final svc = McpTokenApiService(connection: conn, httpClient: apiMock);

      await svc.create(name: '   ');

      expect(jsonDecode(apiMock.bodies.single), equals({}));
    });
  });

  group('McpTokenApiService — revoke', () {
    test('sends DELETE for the id', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({'revoked': true})),
      ]);
      final svc = McpTokenApiService(connection: conn, httpClient: apiMock);

      await svc.revoke('t1');

      expect(apiMock.requests.single.method, equals('DELETE'));
      expect(apiMock.requests.single.url.path, equals('/api/mcp/tokens/t1'));
    });

    test('surfaces NOT_FOUND error code', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(404, jsonEncode({
          'ok': false,
          'data': null,
          'error': {'code': 'NOT_FOUND', 'message': 'MCP token not found'},
        })),
      ]);
      final svc = McpTokenApiService(connection: conn, httpClient: apiMock);

      await expectLater(
        svc.revoke('someone-elses'),
        throwsA(isA<McpTokenApiException>()
            .having((e) => e.code, 'code', equals('NOT_FOUND'))),
      );
    });
  });

  group('McpTokenApiService — auth & connection states', () {
    test('401 maps to McpTokenApiAuthException', () async {
      await primeConnected();
      final apiMock = _MockClient([const _Canned(401, '{"error":{}}')]);
      final svc = McpTokenApiService(connection: conn, httpClient: apiMock);
      await expectLater(svc.list(), throwsA(isA<McpTokenApiAuthException>()));
    });

    test('not connected short-circuits without HTTP', () async {
      final apiMock = _MockClient(const []);
      final svc = McpTokenApiService(connection: conn, httpClient: apiMock);
      await expectLater(
          svc.list(), throwsA(isA<McpTokenApiException>()));
      expect(apiMock.requests, isEmpty);
    });
  });

  // ── 真 server 闭环（验收：创建→列表→吊销→列表为空）──
  // 运行：flutter test test/services/mcp_token_api_service_test.dart \
  //   --dart-define=DBMASTER_MCP_E2E=1 \
  //   --dart-define=DBMASTER_MCP_E2E_URL=http://127.0.0.1:3999 \
  //   --dart-define=DBMASTER_MCP_E2E_EMAIL=... --dart-define=DBMASTER_MCP_E2E_PASSWORD=...
  group('McpTokenApiService — live server lifecycle', skip: !_e2eEnabled
      ? 'set DBMASTER_MCP_E2E=1 against a live local server to run'
      : false, () {
    test('create → list → revoke → list empty', () async {
      final email =
          const String.fromEnvironment('DBMASTER_MCP_E2E_EMAIL');
      final password =
          const String.fromEnvironment('DBMASTER_MCP_E2E_PASSWORD');
      expect(email, isNotEmpty, reason: 'DBMASTER_MCP_E2E_EMAIL required');
      expect(password, isNotEmpty,
          reason: 'DBMASTER_MCP_E2E_PASSWORD required');

      await conn.connect(_e2eUrl, email, password);
      expect(
        conn.connectionState,
        equals(ServerConnectionState.connected),
      );

      final svc = McpTokenApiService(connection: conn);

      final created =
          await svc.create(name: 'e2e-walkthrough-${DateTime.now().millisecondsSinceEpoch}');
      expect(created.token, startsWith('dbm_mcp_'));

      final listed = await svc.list();
      expect(listed.any((t) => t.id == created.id), isTrue,
          reason: 'created token must appear in list');
      final row = listed.firstWhere((t) => t.id == created.id);
      expect(row.tokenPrefix, startsWith('dbm_mcp_'));
      expect(row.tokenPrefix.length, lessThan(created.token.length),
          reason: 'list must only carry the short prefix');

      await svc.revoke(created.id);

      final after = await svc.list();
      expect(after.any((t) => t.id == created.id), isFalse,
          reason: 'revoked token must disappear from list');
    });
  });
}
