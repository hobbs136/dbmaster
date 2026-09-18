//! Unit tests for [ApprovalApiService] (#25). Covers the 4 approval endpoints
//! + connections list: list (8-field parse + status), submit (POST body + gated),
//! approve/reject (POST empty body + path), listConnections, not-connected
//! guard. Mock pattern mirrors `saved_query_api_service_test.dart`.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/approval_api_service.dart';
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

String _errJson(int status, String code, String message) => jsonEncode({
      'ok': false,
      'data': null,
      'error': {'code': code, 'message': message},
    });

/// Server-shaped DdlApproval row.
Map<String, dynamic> _row({
  required String id,
  String ddlSql = 'CREATE TABLE t (id INT)',
  String targetDbId = 'conn-1',
  String submitterId = 'u1',
  String? reviewerId,
  String status = 'pending',
  String? resolvedAt,
  String? execStatus,
  String? executedAt,
  String? execError,
}) =>
    {
      'id': id,
      'submitter_id': submitterId,
      'ddl_sql': ddlSql,
      'target_db_id': targetDbId,
      'reviewer_id': reviewerId,
      'status': status,
      'created_at': '2026-08-13T10:00:00Z',
      'resolved_at': resolvedAt,
      'exec_status': execStatus,
      'executed_at': executedAt,
      'exec_error': execError,
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

  group('ApprovalApiService — list', () {
    test('list sends GET /api/approvals and parses 8 fields + status', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson([
          _row(id: 'a1', status: 'pending', ddlSql: 'ALTER TABLE t ADD c INT'),
          _row(
              id: 'a2',
              status: 'approved',
              reviewerId: 'u2',
              resolvedAt: '2026-08-13T11:00:00Z'),
        ])),
      ]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      final list = await svc.list();

      expect(apiMock.requests.single.method, equals('GET'));
      expect(apiMock.requests.single.url.path, equals('/api/approvals'));
      expect(list.length, equals(2));
      expect(list[0].id, equals('a1'));
      expect(list[0].ddlSql, equals('ALTER TABLE t ADD c INT'));
      expect(list[0].targetDbId, equals('conn-1'));
      expect(list[0].submitterId, equals('u1'));
      expect(list[0].reviewerId, isNull);
      expect(list[0].isPending, isTrue);
      expect(list[1].id, equals('a2'));
      expect(list[1].reviewerId, equals('u2'));
      expect(list[1].resolvedAt, equals('2026-08-13T11:00:00Z'));
      expect(list[1].isApproved, isTrue);
      expect(list[1].isResolved, isTrue);
    });

    test('list throws when not connected (caller short-circuits)', () async {
      // No primeConnected() — service throws before HTTP, same as the other
      // server services. Dialogs check `isConnected` before calling.
      final svc = ApprovalApiService(
          connection: conn, httpClient: _MockClient(const []));
      await expectLater(
        () => svc.list(),
        throwsA(isA<ApprovalApiException>()),
      );
    });

    test('list parses exec columns (U10 failure visibility)', () async {
      await primeConnected();
      // A pre-U10 server omits the exec keys entirely — fromJson must treat
      // both explicit nulls and absent keys as "no execution outcome".
      final legacy = Map<String, dynamic>.from(_row(id: 'p1'))
        ..remove('exec_status')
        ..remove('executed_at')
        ..remove('exec_error');
      final apiMock = _MockClient([
        _Canned(200, _okJson([
          _row(
            id: 'f1',
            status: 'failed',
            reviewerId: 'u2',
            resolvedAt: '2026-08-17T11:00:00Z',
            execStatus: 'failed',
            executedAt: '2026-08-17T11:00:05Z',
            execError: 'mysql: syntax error near c',
          ),
          _row(id: 'n1', status: 'pending', execStatus: 'pending'),
          legacy,
        ])),
      ]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      final list = await svc.list();

      expect(list[0].isFailed, isTrue);
      expect(list[0].execStatus, equals('failed'));
      expect(list[0].executedAt, equals('2026-08-17T11:00:05Z'));
      expect(list[0].execError, equals('mysql: syntax error near c'));
      expect(list[0].hasExecError, isTrue);
      expect(list[1].execStatus, equals('pending'));
      expect(list[1].hasExecError, isFalse);
      expect(list[2].execStatus, isNull);
      expect(list[2].execError, isNull);
      expect(list[2].hasExecError, isFalse);
    });
  });

  group('ApprovalApiService — submit', () {
    test('submit POSTs ddl_sql + target_db_id and returns the id', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({'id': 'new-id', 'status': 'pending'})),
      ]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      final id = await svc.submit(
        ddlSql: 'DROP TABLE obsolete',
        targetDbId: 'conn-9',
      );

      expect(id, equals('new-id'));
      expect(apiMock.requests.single.method, equals('POST'));
      expect(apiMock.requests.single.url.path, equals('/api/approvals'));
      final body = jsonDecode(apiMock.bodies.single) as Map<String, dynamic>;
      expect(body, containsPair('ddl_sql', 'DROP TABLE obsolete'));
      expect(body, containsPair('target_db_id', 'conn-9'));
    });

    test('submit 403 ENTITLEMENT_GATED → ApprovalApiEntitlementException',
        () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(403, _errJson(403, 'ENTITLEMENT_GATED', 'gated')),
      ]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      await expectLater(
        () => svc.submit(ddlSql: 'CREATE TABLE x(id INT)', targetDbId: 'c1'),
        throwsA(isA<ApprovalApiEntitlementException>()),
      );
    });
  });

  group('ApprovalApiService — approve/reject', () {
    test('approve POSTs empty body to /:id/approve', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson(
            {'id': 'a1', 'status': 'executing', 'exec_status': 'executing'})),
      ]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      await svc.approve('a1');

      expect(apiMock.requests.single.method, equals('POST'));
      expect(apiMock.requests.single.url.path,
          equals('/api/approvals/a1/approve'));
      // Empty body — approve takes no payload.
      expect(apiMock.bodies.single, isEmpty);
    });

    test('reject POSTs empty body to /:id/reject', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson({'status': 'rejected'})),
      ]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      await svc.reject('a1');

      expect(apiMock.requests.single.method, equals('POST'));
      expect(apiMock.requests.single.url.path,
          equals('/api/approvals/a1/reject'));
      expect(apiMock.bodies.single, isEmpty);
    });

    test('approve ALREADY_RESOLVED surfaces code on the exception', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(409,
            _errJson(409, 'ALREADY_RESOLVED', 'approval is approved, not pending')),
      ]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      try {
        await svc.approve('a1');
        fail('expected ApprovalApiException');
      } on ApprovalApiException catch (e) {
        expect(e.code, equals('ALREADY_RESOLVED'));
        expect(e.statusCode, equals(409));
      }
    });

    test('reject 401 → ApprovalApiAuthException', () async {
      await primeConnected();
      final apiMock = _MockClient([const _Canned(401, '{}')]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      await expectLater(
        () => svc.reject('a1'),
        throwsA(isA<ApprovalApiAuthException>()),
      );
    });
  });

  group('ApprovalApiService — listConnections', () {
    test('listConnections GETs /api/connections and parses rows', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson([
          {
            'id': 'c1',
            'name': 'prod mysql',
            'db_type': 'mysql',
            'host': 'db.host',
            'port': 3306,
            'username': 'root',
            'default_database': 'app',
            'kind': 'collab',
          },
        ])),
      ]);
      final svc = ApprovalApiService(connection: conn, httpClient: apiMock);

      final conns = await svc.listConnections();

      expect(apiMock.requests.single.method, equals('GET'));
      expect(apiMock.requests.single.url.path, equals('/api/connections'));
      expect(conns.length, equals(1));
      expect(conns[0].id, equals('c1'));
      expect(conns[0].name, equals('prod mysql'));
      expect(conns[0].hostLabel, equals('db.host:3306'));
    });
  });
}
