//! Unit tests for [SavedQueryApiService] (#24). Covers the 4 endpoints:
//! list (tag/q params + tags-JSON decode), create (POST body + gated),
//! get (NOT_FOUND → null), delete (idempotent on NOT_FOUND). Mock pattern
//! mirrors `health_api_service_test.dart`.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/saved_query_api_service.dart';
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

/// Server-shaped saved query row (tags as a JSON-encoded string column, matching
/// the wire contract from #4).
Map<String, dynamic> _row({
  required String id,
  required String title,
  required String sqlText,
  String tags = '[]',
  String createdBy = 'u1',
}) =>
    {
      'id': id,
      'title': title,
      'sql_text': sqlText,
      'tags': tags,
      'workspace_id': 'default',
      'created_by': createdBy,
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

  group('SavedQueryApiService — list', () {
    test('list sends GET and parses rows (tags JSON string decoded)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson([
          _row(id: 'q1', title: 'top users', sqlText: 'SELECT * FROM users',
              tags: '["analytics","users"]'),
          _row(id: 'q2', title: 'orders', sqlText: 'SELECT 1', tags: '[]'),
        ])),
      ]);
      final svc = SavedQueryApiService(connection: conn, httpClient: apiMock);

      final queries = await svc.list();

      expect(apiMock.requests.single.method, equals('GET'));
      expect(apiMock.requests.single.url.path, equals('/api/queries'));
      expect(queries.length, equals(2));
      expect(queries[0].id, equals('q1'));
      // tags JSON string column is parsed into a List<String>.
      expect(queries[0].tags, equals(['analytics', 'users']));
      expect(queries[1].tags, isEmpty);
    });

    test('list applies tag + q query params server-side', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson([_row(id: 'q1', title: 'x', sqlText: 'SELECT 1')])),
      ]);
      final svc = SavedQueryApiService(connection: conn, httpClient: apiMock);

      await svc.list(tag: 'analytics', q: 'users');

      final path = apiMock.requests.single.url.path;
      final query = apiMock.requests.single.url.query;
      expect(path, equals('/api/queries'));
      expect(query, contains('tag=analytics'));
      expect(query, contains('q=users'));
    });
  });

  group('SavedQueryApiService — create', () {
    test('create POSTs title/sql_text/tags and returns the id', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({'id': 'new-id', 'saved': true})),
      ]);
      final svc = SavedQueryApiService(connection: conn, httpClient: apiMock);

      final id = await svc.create(
        title: 'my query',
        sqlText: 'SELECT 1',
        tags: const ['report'],
      );

      expect(id, equals('new-id'));
      expect(apiMock.requests.single.method, equals('POST'));
      expect(apiMock.requests.single.url.path, equals('/api/queries'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('title', 'my query'));
      expect(body, containsPair('sql_text', 'SELECT 1'));
      expect(body, containsPair('tags', ['report']));
    });

    test('create 403 ENTITLEMENT_GATED → SavedQueryApiEntitlementException',
        () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(403, jsonEncode({
          'ok': false,
          'data': null,
          'error': {'code': 'ENTITLEMENT_GATED', 'message': 'gated'},
        })),
      ]);
      final svc = SavedQueryApiService(connection: conn, httpClient: apiMock);

      await expectLater(
        () => svc.create(title: 'x', sqlText: 'SELECT 1'),
        throwsA(isA<SavedQueryApiEntitlementException>()),
      );
    });
  });

  group('SavedQueryApiService — get/delete', () {
    test('get returns null on NOT_FOUND (200 + ok:false)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, jsonEncode({
          'ok': false,
          'data': null,
          'error': {'code': 'NOT_FOUND', 'message': 'Saved query not found'},
        })),
      ]);
      final svc = SavedQueryApiService(connection: conn, httpClient: apiMock);

      final result = await svc.get('gone-id');
      expect(result, isNull);
    });

    test('delete is idempotent on NOT_FOUND (no throw)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, jsonEncode({
          'ok': false,
          'data': null,
          'error': {'code': 'NOT_FOUND', 'message': 'Saved query not found'},
        })),
      ]);
      final svc = SavedQueryApiService(connection: conn, httpClient: apiMock);

      // Should complete without throwing.
      await svc.delete('gone-id');
      expect(apiMock.requests.single.method, equals('DELETE'));
      expect(apiMock.requests.single.url.path, equals('/api/queries/gone-id'));
    });
  });
}
