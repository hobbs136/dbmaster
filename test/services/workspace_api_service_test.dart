//! Unit tests for [WorkspaceApiService] (#26). Covers all 7 workspace
//! endpoints. **Key difference from the approval/saved-query tests**: the
//! workspace endpoints (core router) return the payload **directly** — NOT
//! wrapped in the `{ok,data,error}` envelope — so the canned responses here
//! are raw shapes (`{workspaces:[...]}`, the item object, empty 204, etc.).
//! Errors are `{error:{code,message}}`. Mock pattern mirrors
//! `approval_api_service_test.dart`.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/server_connection.dart';
import 'package:dbmaster/services/workspace_api_service.dart';

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

/// Raw error shape used by the workspace (core) router: `{error:{code,msg}}`
/// WITHOUT the `{ok,data}` envelope the automation routes use.
String _errJson(String code, String message) =>
    jsonEncode({'error': {'code': code, 'message': message}});

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

  group('WorkspaceApiService — list', () {
    test('GET /api/workspaces unwraps raw {workspaces:[...]} and parses fields',
        () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, jsonEncode({
          'workspaces': [
            {
              'id': 'w1',
              'name': 'Data Platform',
              'owner_id': 'u1',
              'invite_code': 'ABC234',
              'member_count': 3,
              'role': 'admin',
              'created_at': '2026-08-13T10:00:00Z',
            },
            {
              'id': 'w2',
              'name': 'Analytics',
              'owner_id': 'u9',
              'invite_code': 'XYZ567',
              'member_count': 7,
              'role': 'member',
              'created_at': '2026-08-12T10:00:00Z',
            },
          ],
        })),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      final list = await svc.list();

      expect(apiMock.requests.single.method, equals('GET'));
      expect(apiMock.requests.single.url.path, equals('/api/workspaces'));
      expect(list.length, equals(2));
      expect(list[0].id, equals('w1'));
      expect(list[0].name, equals('Data Platform'));
      expect(list[0].memberCount, equals(3));
      expect(list[0].role, equals('admin'));
      expect(list[0].isAdmin, isTrue);
      expect(list[1].id, equals('w2'));
      expect(list[1].isAdmin, isFalse);
      expect(list[1].inviteCode, equals('XYZ567'));
    });

    test('list returns [] on empty workspaces array', () async {
      await primeConnected();
      final apiMock =
          _MockClient([_Canned(200, jsonEncode({'workspaces': <Object>[]}))]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      expect(await svc.list(), isEmpty);
    });

    test('list throws when not connected (caller short-circuits)', () async {
      final svc = WorkspaceApiService(
          connection: conn, httpClient: _MockClient(const []));
      await expectLater(() => svc.list(),
          throwsA(isA<WorkspaceApiException>()));
    });
  });

  group('WorkspaceApiService — create', () {
    test('POSTs {name} and parses the raw item (201)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(201, jsonEncode({
          'id': 'w-new',
          'name': 'New Team',
          'owner_id': 'u1',
          'invite_code': 'NEW123',
          'member_count': 1,
          'role': 'admin',
          'created_at': '2026-08-13T10:00:00Z',
        })),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      final ws = await svc.create('New Team');

      expect(apiMock.requests.single.method, equals('POST'));
      expect(apiMock.requests.single.url.path, equals('/api/workspaces'));
      expect(jsonDecode(apiMock.bodies.single),
          containsPair('name', 'New Team'));
      expect(ws.id, equals('w-new'));
      expect(ws.isAdmin, isTrue);
      expect(ws.inviteCode, equals('NEW123'));
    });
  });

  group('WorkspaceApiService — get', () {
    test('GET /api/workspaces/:id parses detail + members', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, jsonEncode({
          'id': 'w1',
          'name': 'Data Platform',
          'owner_id': 'u1',
          'invite_code': 'ABC234',
          'created_at': '2026-08-13T10:00:00Z',
          'members': [
            {
              'user_id': 'u1',
              'display_name': 'Alice',
              'email': 'a@b.c',
              'role': 'admin',
              'joined_at': '2026-08-13T10:00:00Z',
            },
            {
              'user_id': 'u2',
              'display_name': 'Bob',
              'email': 'b@b.c',
              'role': 'member',
              'joined_at': '2026-08-13T11:00:00Z',
            },
          ],
        })),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      final detail = await svc.get('w1');

      expect(apiMock.requests.single.url.path, equals('/api/workspaces/w1'));
      expect(detail.name, equals('Data Platform'));
      expect(detail.members.length, equals(2));
      expect(detail.members[0].displayName, equals('Alice'));
      expect(detail.members[0].isAdmin, isTrue);
      expect(detail.members[1].isAdmin, isFalse);
    });
  });

  group('WorkspaceApiService — delete', () {
    test('DELETE /api/workspaces/:id tolerates empty 204 body', () async {
      await primeConnected();
      final apiMock = _MockClient([const _Canned(204, '')]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      await svc.delete('w1');

      expect(apiMock.requests.single.method, equals('DELETE'));
      expect(apiMock.requests.single.url.path, equals('/api/workspaces/w1'));
    });

    test('delete 403 (non-admin) surfaces FORBIDDEN code', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(403, _errJson('FORBIDDEN', 'Only workspace admins can delete.')),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      try {
        await svc.delete('w1');
        fail('expected WorkspaceApiException');
      } on WorkspaceApiException catch (e) {
        expect(e.code, equals('FORBIDDEN'));
        expect(e.statusCode, equals(403));
      }
    });
  });

  group('WorkspaceApiService — join', () {
    test('POSTs {invite_code} to /:id/join', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, jsonEncode({
          'workspace_id': 'w1',
          'user_id': 'u1',
          'role': 'member',
          'joined_at': '2026-08-13T10:00:00Z',
        })),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      await svc.join('w1', 'ABC234');

      expect(apiMock.requests.single.method, equals('POST'));
      expect(apiMock.requests.single.url.path,
          equals('/api/workspaces/w1/join'));
      expect(jsonDecode(apiMock.bodies.single),
          containsPair('invite_code', 'ABC234'));
    });

    test('join already-a-member → CONFLICT (409) surfaces code', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(409,
            _errJson('CONFLICT', 'You are already a member of this workspace.')),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      try {
        await svc.join('w1', 'ABC234');
        fail('expected WorkspaceApiException');
      } on WorkspaceApiException catch (e) {
        expect(e.code, equals('CONFLICT'));
        expect(e.statusCode, equals(409));
      }
    });

    test('join invalid code → generic CONFLICT (server hides existence)',
        () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(409, _errJson('CONFLICT', 'Invalid invite code.')),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      try {
        await svc.join('w1', 'WRONG1');
        fail('expected WorkspaceApiException');
      } on WorkspaceApiException catch (e) {
        expect(e.code, equals('CONFLICT'));
      }
    });
  });

  group('WorkspaceApiService — leave', () {
    test('POSTs empty body to /:id/leave (204)', () async {
      await primeConnected();
      final apiMock = _MockClient([const _Canned(204, '')]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      await svc.leave('w1');

      expect(apiMock.requests.single.method, equals('POST'));
      expect(apiMock.requests.single.url.path,
          equals('/api/workspaces/w1/leave'));
      expect(apiMock.bodies.single, isEmpty);
    });

    test('leave last-admin → BUSINESS_RULE_VIOLATION (422)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(422, _errJson('BUSINESS_RULE_VIOLATION',
            'You are the last admin of this workspace.')),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      try {
        await svc.leave('w1');
        fail('expected WorkspaceApiException');
      } on WorkspaceApiException catch (e) {
        expect(e.code, equals('BUSINESS_RULE_VIOLATION'));
        expect(e.statusCode, equals(422));
      }
    });
  });

  group('WorkspaceApiService — removeMember', () {
    test('DELETE /api/workspaces/:id/members/:uid (204)', () async {
      await primeConnected();
      final apiMock = _MockClient([const _Canned(204, '')]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      await svc.removeMember('w1', 'u2');

      expect(apiMock.requests.single.method, equals('DELETE'));
      expect(apiMock.requests.single.url.path,
          equals('/api/workspaces/w1/members/u2'));
    });

    test('removeMember last-admin → BUSINESS_RULE_VIOLATION (422)', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(422, _errJson('BUSINESS_RULE_VIOLATION',
            'Cannot remove the last admin of the workspace.')),
      ]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      try {
        await svc.removeMember('w1', 'u2');
        fail('expected WorkspaceApiException');
      } on WorkspaceApiException catch (e) {
        expect(e.code, equals('BUSINESS_RULE_VIOLATION'));
      }
    });
  });

  group('WorkspaceApiService — auth', () {
    test('401 → WorkspaceApiAuthException', () async {
      await primeConnected();
      final apiMock = _MockClient([const _Canned(401, '{}')]);
      final svc = WorkspaceApiService(connection: conn, httpClient: apiMock);

      await expectLater(
          () => svc.list(), throwsA(isA<WorkspaceApiAuthException>()));
    });
  });
}
