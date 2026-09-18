//! Unit tests for [ReportsApiService]（M2）。Mirrors the standard mock pattern.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:dbmaster/models/report_models.dart';
import 'package:dbmaster/services/reports_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({required String key, Object? iOptions, Object? aOptions, Object? lOptions, Object? webOptions, Object? mOptions, Object? wOptions}) =>
      Future.value(_store[key]);

  @override
  Future<void> write({required String key, required String? value, Object? iOptions, Object? aOptions, Object? lOptions, Object? webOptions, Object? mOptions, Object? wOptions}) {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
    return Future.value();
  }

  @override
  Future<void> delete({required String key, Object? iOptions, Object? aOptions, Object? lOptions, Object? webOptions, Object? mOptions, Object? wOptions}) {
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
    final next =
        _cursor < responses.length ? responses[_cursor] : const _Canned(404, '{}');
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

Map<String, dynamic> _reportRow(String id) => {
      'id': id,
      'task_id': null,
      'report_type': 'slow_query_weekly',
      'title': 'Slow query weekly · 2026-W35',
      'content':
          '{"content_version":1,"report_type":"slow_query_weekly","window_from":"a","window_to":"b","window_truncated":false,"summary":{"total_samples":2,"distinct_digests":1,"total_ms":5000,"error_count":0,"cancelled_count":0,"week_over_week_pct":null},"top":[{"digest":"SELECT SLEEP(?)","db_kind":"mysql","conn_id":"c1","count":2,"total_ms":5000,"avg_ms":2500.0,"max_ms":3000,"sample_sql_text":"SELECT SLEEP(1.5)"}],"by_connection":[{"conn_id":"c1","db_kind":"mysql","count":2,"total_ms":5000}],"by_day":[{"date":"2026-08-27","count":2,"total_ms":5000}]}',
      'generated_at': '2026-08-27T12:00:00+00:00',
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

  test('listReports decodes page + serializes params', () async {
    await primeConnected();
    final mock = _MockClient([
      _Canned(200, _okJson({
        'items': [_reportRow('r1')],
        'total': 1,
        'limit': 50,
        'offset': 0,
      })),
    ]);
    final svc = ReportsApiService(connection: conn, httpClient: mock);
    final page = await svc.listReports(reportType: 'slow_query_weekly');

    expect(page.total, equals(1));
    expect(page.items, hasLength(1));
    final r = page.items.first;
    expect(r.id, equals('r1'));
    expect(r.taskId, isNull);
    expect(r.title, contains('W35'));
    // typed content 解析路径。
    final typed = SlowQueryWeeklyReport.fromDecoded(r.contentDecoded!);
    expect(typed, isNotNull);
    expect(typed!.summary.totalSamples, equals(2));
    expect(typed.top.first.digest, equals('SELECT SLEEP(?)'));
    expect(typed.byDay.first.date, equals('2026-08-27'));

    final qp = mock.requests.single.url.queryParameters;
    expect(qp['report_type'], equals('slow_query_weekly'));
    expect(qp['limit'], equals('50'));
  });

  test('generateWeekly posts and decodes idempotent result', () async {
    await primeConnected();
    final mock = _MockClient([
      _Canned(200, _okJson({'id': 'r1', 'created': false, 'report_type': 'slow_query_weekly'})),
    ]);
    final svc = ReportsApiService(connection: conn, httpClient: mock);
    final result = await svc.generateWeekly();

    expect(result.id, equals('r1'));
    expect(result.created, isFalse);

    final body = jsonDecode(mock.bodies.single) as Map<String, dynamic>;
    expect(body['report_type'], equals('slow_query_weekly'));
  });

  test('generateWeekly surfaces Gated as entitlement exception', () async {
    await primeConnected();
    final mock = _MockClient([
      _Canned(403, jsonEncode({
        'ok': false,
        'data': null,
        'error': {'code': 'ENTITLEMENT_GATED', 'message': 'gated'},
      })),
    ]);
    final svc = ReportsApiService(connection: conn, httpClient: mock);
    await expectLater(
      svc.generateWeekly(),
      throwsA(isA<ReportsApiEntitlementException>()),
    );
  });
}
