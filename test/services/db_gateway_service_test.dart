// =============================================================================
// Unit tests for DbGatewayService (ADR-0003 S4).
// =============================================================================
// Verifies the routing policy (embedded + SQL library + non-transactional),
// the gateway request/response mapping (including the columnTypes array→Map
// conversion and null/affectedRows handling), and transaction-control-statement
// detection. HTTP is mocked via a fake client; no real server is exercised.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/db_gateway_service.dart';
import 'package:dbmaster/services/server_connection.dart';

/// A minimal http.Client returning a canned response for the next call.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._resp);
  final http.Response _resp;
  int callCount = 0;
  String? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    if (request is http.Request) lastBody = request.body;
    return http.StreamedResponse(
      Stream.value(_resp.bodyBytes),
      _resp.statusCode,
      headers: _resp.headers,
    );
  }
}

void main() {
  DbServer mysql() => DbServer(
      id: 'c1', name: 'm', type: DatabaseType.mysql, host: 'h', port: 3306);
  DbServer redis() => DbServer(
      id: 'c2', name: 'r', type: DatabaseType.redis, host: 'h', port: 6379);
  // T29 第二批：pg 已 gateway-backed，路由阳性 fixture 改用仍为旧 /api/db
  // 通道的 sqlite（server-syncable 且非 _gatewayBackedTypes）。
  DbServer pg() => DbServer(
      id: 'c3', name: 'p', type: DatabaseType.sqlite, host: 'h', port: 0);

  setUp(() {
    ServerConnection.resetForTesting();
    SharedPreferences.setMockInitialValues({});
    DbGatewayService.instance.resetForTesting();
  });

  tearDown(() {
    DbGatewayService.instance.resetForTesting();
  });

  /// Wire ServerConnection into embedded mode + a fixed token for gateway calls.
  void wireEmbedded() {
    final conn = ServerConnection();
    conn.connectEmbedded(
      port: 12345,
      accessToken: 'test-token',
      refreshToken: 'r',
      installUuid: 'u',
      version: '0.1.0',
    );
    DbGatewayService.instance.testEmbeddedMode = true;
  }

  group('shouldRouteViaGateway', () {
    test('true only for embedded + SQL library + non-tx + plain query', () {
      wireEmbedded();
      // T29：mysql 族已 gateway-backed（/api/gw 壳），不再走旧 /api/db 网关。
      expect(DbGatewayService.instance.shouldRouteViaGateway(mysql(), 'SELECT 1'),
          isFalse);
      expect(DbGatewayService.instance.shouldRouteViaGateway(pg(), 'SELECT * FROM t'),
          isTrue);
      // T29 第二批：postgresql 亦 gateway-backed，不走旧网关。
      final pgGw = DbServer(
          id: 'c4', name: 'pg', type: DatabaseType.postgresql, host: 'h', port: 5432);
      expect(DbGatewayService.instance.shouldRouteViaGateway(pgGw, 'SELECT * FROM t'),
          isFalse);
      // T29 第三批：clickhouse 亦 gateway-backed，不走旧网关。
      final chGw = DbServer(
          id: 'c5', name: 'ch', type: DatabaseType.clickhouse, host: 'h', port: 9004);
      expect(DbGatewayService.instance.shouldRouteViaGateway(chGw, 'SELECT 1'),
          isFalse);
    });

    test('false when not embedded', () {
      // testEmbeddedMode stays false (no wireEmbedded)
      expect(DbGatewayService.instance.shouldRouteViaGateway(mysql(), 'SELECT 1'),
          isFalse);
    });

    test('false for non-SQL library (redis)', () {
      wireEmbedded();
      expect(DbGatewayService.instance.shouldRouteViaGateway(redis(), 'GET k'),
          isFalse);
    });

    test('false when in a transaction', () {
      wireEmbedded();
      expect(
        DbGatewayService.instance
            .shouldRouteViaGateway(mysql(), 'SELECT 1', inTransaction: true),
        isFalse,
      );
    });

    test('false for transaction-control statements (BEGIN/COMMIT/ROLLBACK)', () {
      wireEmbedded();
      for (final sql in [
        'BEGIN',
        'begin',
        'COMMIT',
        'ROLLBACK',
        'START TRANSACTION',
        'SET AUTOCOMMIT = 0',
        'SAVEPOINT sp1',
        'RELEASE SAVEPOINT sp1',
      ]) {
        expect(
          DbGatewayService.instance.shouldRouteViaGateway(mysql(), sql),
          isFalse,
          reason: '"$sql" should bypass the gateway',
        );
      }
      // Plain queries with leading whitespace still route (sqlite；mysql 族 /
      // pg T29 起 gateway-backed，不走旧网关——见上一条用例）。
      expect(
        DbGatewayService.instance.shouldRouteViaGateway(pg(), '   SELECT 1'),
        isTrue,
      );
    });
  });

  group('lookupServerConnId', () {
    test('returns the mapped id when present', () async {
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': '{"c1": "srv-uuid-1"}',
      });
      expect(await DbGatewayService.instance.lookupServerConnId('c1'), 'srv-uuid-1');
    });

    test('returns null when no mapping exists', () async {
      expect(await DbGatewayService.instance.lookupServerConnId('nope'), isNull);
    });
  });

  group('executeQuery', () {
    test('POSTs the body and decodes a SELECT result', () async {
      wireEmbedded();
      DbGatewayService.instance.httpClient = _FakeClient(http.Response(jsonEncode({
        'ok': true,
        'data': {
          'columns': ['id', 'name'],
          'columnTypes': [
            {'name': 'id', 'type': 'BIGINT'},
            {'name': 'name', 'type': 'VARCHAR(255)'},
          ],
          'rows': [
            {'id': 1, 'name': 'alice'},
            {'id': 2, 'name': null},
          ],
          'executionTimeMs': 7,
        },
        'error': null,
      }), 200));

      final result = await DbGatewayService.instance
          .executeQuery('srv-1', 'SELECT id, name FROM users', database: 'shop');

      expect(result.columns, ['id', 'name']);
      expect(result.rows.length, 2);
      expect(result.rows[0], {'id': 1, 'name': 'alice'});
      expect(result.rows[1]['name'], isNull); // NULL preserved
      expect(result.columnTypes, {'id': 'BIGINT', 'name': 'VARCHAR(255)'});
      expect(result.executionTime, 7);
    });

    test('decodes a non-SELECT result (affectedRows, no columnTypes)', () async {
      wireEmbedded();
      DbGatewayService.instance.httpClient = _FakeClient(http.Response(jsonEncode({
        'ok': true,
        'data': {
          'columns': [],
          'rows': [],
          'affectedRows': 3,
          'executionTimeMs': 4,
        },
        'error': null,
      }), 200));

      final result = await DbGatewayService.instance
          .executeQuery('srv-1', 'DELETE FROM t WHERE x < 10');

      expect(result.columns, isEmpty);
      expect(result.rows, isEmpty);
      expect(result.affectedRows, 3);
      expect(result.executionTime, 4);
      expect(result.columnTypes, isNull); // server omits it for non-SELECT
    });

    test('includes db + limit in the request body when provided', () async {
      wireEmbedded();
      final fake = _FakeClient(http.Response(jsonEncode({
        'ok': true,
        'data': {'columns': [], 'rows': [], 'affectedRows': 0},
        'error': null,
      }), 200));
      DbGatewayService.instance.httpClient = fake;

      await DbGatewayService.instance
          .executeQuery('srv-1', 'SELECT 1', database: 'shop', limit: 50);

      expect(fake.callCount, 1);
      final body = jsonDecode(fake.lastBody!) as Map<String, dynamic>;
      expect(body['db'], 'shop');
      expect(body['sql'], 'SELECT 1');
      expect(body['limit'], 50);
    });

    test('throws on server error (caller falls back)', () async {
      wireEmbedded();
      DbGatewayService.instance.httpClient = _FakeClient(http.Response(jsonEncode({
        'ok': false,
        'data': null,
        'error': {'code': 'QUERY_FAILED', 'message': 'syntax error near...'},
      }), 200));

      expect(
        () => DbGatewayService.instance.executeQuery('srv-1', 'BAD SQL'),
        throwsA(isA<StateError>()),
      );
    });

    test('throws on auth failure (401)', () async {
      wireEmbedded();
      DbGatewayService.instance.httpClient =
          _FakeClient(http.Response('Unauthorized', 401));
      expect(
        () => DbGatewayService.instance.executeQuery('srv-1', 'SELECT 1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
