//! Unit tests for [QueryStatsApiService]. Mirrors `health_api_service_test`'s
//! mock pattern: programmable [http.BaseClient] on BOTH the ServerConnection
//! (login seam) AND the service (API-call seam).

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/services/query_stats_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

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

class _MockClient extends http.BaseClient {
  final List<_Canned> responses;
  int _cursor = 0;
  final List<http.BaseRequest> requests = [];

  _MockClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
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

Map<String, dynamic> _summaryData() => {
      'items': [
        {
          'digest': 'SELECT * FROM t WHERE id = ?',
          'db_kind': 'mysql',
          'conn_id': 'c1',
          'count': 3,
          'total_ms': 6000,
          'avg_ms': 2000.0,
          'max_ms': 3000,
          'first_seen': '2026-08-27T10:00:00+00:00',
          'last_seen': '2026-08-27T11:00:00+00:00',
          'sample_sql_text': 'SELECT * FROM t WHERE id = 42',
        },
      ],
      'meta': {
        'threshold_ms': 1000,
        'store_sql': true,
        'retention_days': 14,
        'dropped_total': null,
        'window_from': '2026-08-26T11:00:00+00:00',
      },
    };

Map<String, dynamic> _detailData() => {
      'items': [
        {
          'id': 'r1',
          'source': 'gateway',
          'conn_id': 'c1',
          'db_kind': 'mysql',
          'database': 'chinook',
          'digest': 'SELECT * FROM t WHERE id = ?',
          'sql_text': 'SELECT * FROM t WHERE id = 42',
          'elapsed_ms': 3000,
          'row_count': 10,
          'affected_rows': null,
          'status': 'ok',
          'error_code': null,
          'user_id': 'u1',
          'entry': 'sync_query',
          'captured_at': '2026-08-27T11:00:00+00:00',
        },
      ],
      'total': 1,
      'limit': 50,
      'offset': 0,
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

  group('QueryStatsApiService — summary', () {
    test('fetchSummary decodes items + meta and serializes params', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson(_summaryData())),
      ]);
      final svc = QueryStatsApiService(connection: conn, httpClient: apiMock);
      final summary = await svc.fetchSummary(
        window: QueryStatsWindow.week,
        connId: 'c1',
        sort: QueryStatsSort.count,
        limit: 10,
      );

      expect(summary.items, hasLength(1));
      final item = summary.items.first;
      expect(item.digest, equals('SELECT * FROM t WHERE id = ?'));
      expect(item.count, equals(3));
      expect(item.totalMs, equals(6000));
      expect(item.maxMs, equals(3000));
      expect(item.sampleSqlText, equals('SELECT * FROM t WHERE id = 42'));
      expect(summary.meta.thresholdMs, equals(1000));
      expect(summary.meta.storeSql, isTrue);
      expect(summary.meta.retentionDays, equals(14));

      final uri = apiMock.requests.single.url;
      expect(uri.path, equals('/api/query-stats/summary'));
      expect(
        uri.queryParameters,
        allOf([
          containsPair('window', '7d'),
          containsPair('conn_id', 'c1'),
          containsPair('sort', 'count'),
          containsPair('limit', '10'),
        ]),
      );
      expect(
        apiMock.requests.single.headers['Authorization'],
        equals('Bearer test-token'),
      );
    });

    test('fetchSummary throws typed exception on {ok:false}', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, jsonEncode({
          'ok': false,
          'data': null,
          'error': {'code': 'DB_ERROR', 'message': 'boom'},
        })),
      ]);
      final svc = QueryStatsApiService(connection: conn, httpClient: apiMock);
      await expectLater(
        svc.fetchSummary(),
        throwsA(isA<QueryStatsApiException>()
            .having((e) => e.code, 'code', equals('DB_ERROR'))),
      );
    });

    test('fetchSummary surfaces 401 as auth exception', () async {
      await primeConnected();
      final apiMock = _MockClient([const _Canned(401, '{}')]);
      final svc = QueryStatsApiService(connection: conn, httpClient: apiMock);
      await expectLater(
        svc.fetchSummary(),
        throwsA(isA<QueryStatsApiAuthException>()),
      );
    });
  });

  group('QueryStatsApiService — detail', () {
    test('fetchDetail decodes paged rows and serializes filters', () async {
      await primeConnected();
      final apiMock = _MockClient([
        _Canned(200, _okJson(_detailData())),
      ]);
      final svc = QueryStatsApiService(connection: conn, httpClient: apiMock);
      final page = await svc.fetchDetail(
        window: QueryStatsWindow.oneHour,
        digest: 'SELECT * FROM t WHERE id = ?',
        status: 'ok',
        limit: 25,
        offset: 50,
      );

      expect(page.total, equals(1));
      expect(page.items, hasLength(1));
      final row = page.items.first;
      expect(row.entry, equals('sync_query'));
      expect(row.database, equals('chinook'));
      expect(row.sqlText, equals('SELECT * FROM t WHERE id = 42'));
      expect(row.elapsedMs, equals(3000));

      final qp = apiMock.requests.single.url.queryParameters;
      expect(qp['window'], equals('1h'));
      expect(qp['limit'], equals('25'));
      expect(qp['offset'], equals('50'));
      expect(qp['status'], equals('ok'));
      expect(qp['digest'], equals('SELECT * FROM t WHERE id = ?'));
    });

    test('not connected throws before any request', () async {
      final svc = QueryStatsApiService(connection: conn);
      await expectLater(
        svc.fetchDetail(),
        throwsA(isA<QueryStatsApiException>()),
      );
    });
  });
}
