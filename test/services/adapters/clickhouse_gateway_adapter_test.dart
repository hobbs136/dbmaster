// =============================================================================
// T29 第三批 · ClickHouse 网关壳 adapter 单元测试。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例（embedded 握手注入），验证：
// - connect：serverConnId 映射复用 / 草稿 test → 现场注册写回 / 失效重注册 /
//   dbType 不匹配重注册 / 失败路径抛 AdapterConnectException（T9a：401 码
//   保留/链保留、envelope map 与字符串两形状）；
// - testConnection：单发 /api/gw/connections/test（草稿不落库）；
// - executeQuery：SSE meta/rows/complete 聚合（位置数组→列名 map）、
//   4xx 前置校验错误形状、请求形状（X-Execution-Id / timeoutMs / rowLimit /
//   database 路由）；
// - SSE error(TIMEOUT/DB_ERROR) 事件上抛（ClickhouseGatewayException），
//   不静默成功；NOT_FOUND/CONNECTION_FAILED 触发 onDisconnect；
// - stale 库自愈（CONNECTION_FAILED + 有 database 路由 → 清库无库重试一次）；
// - 浏览：getDatabases（SHOW DATABASES + information_schema/system_metadata
//   滤噪）/ getTables（SHOW TABLES）/ useDatabase record-only；
// - 只读守卫、无 server 会话引导性错误、disconnect 在途取消 best-effort；
// - 事务 fail-loud（CH 引擎层无事务，防假回滚）。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/services/adapters/clickhouse_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/readonly_guard.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 记录全部请求并按路径规则回放的客户端。
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this._handler);

  final http.StreamedResponse Function(http.Request request) _handler;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final req = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;
    requests.add(req);
    return _handler(req);
  }
}

http.StreamedResponse _sse(List<String> events, {int status = 200}) {
  final body = '${events.join('\n\n')}\n\n';
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    status,
    headers: const {'content-type': 'text/event-stream'},
  );
}

http.StreamedResponse _jsonResp(Object body, int status) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _sentBody(http.Request req) =>
    jsonDecode(req.body) as Map<String, dynamic>;

DatabaseConnection _conn({bool readOnly = false, int? timeoutSecs}) =>
    DatabaseConnection(
      id: 'local_ch_1',
      name: 'CH Live',
      type: DatabaseType.clickhouse,
      host: '192.0.2.128',
      port: 9004,
      username: 'ch_test',
      password: 'pw',
      database: 'ch_test_db',
      readOnly: readOnly,
      extra: timeoutSecs == null ? null : {'timeout': timeoutSecs},
    );

/// 网关注册表列表（id 集合可配）。
http.StreamedResponse _listResponse(Set<String> ids) =>
    _jsonResp([for (final id in ids) {'id': id, 'dbType': 'clickhouse'}], 200);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerConnection.resetForTesting();
    ServerConnection().connectEmbedded(
      port: 45673,
      accessToken: 'emb-token',
      refreshToken: 'emb-refresh',
      installUuid: 'uuid',
      version: '0.1.0',
    );
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  /// 映射有效（srv-1）的已连接壳；handler 处理非 list 请求。
  Future<ClickhouseAdapter> connectedAdapter(
    http.StreamedResponse Function(http.Request) handler,
  ) async {
    final client = _RecordingClient((req) {
      if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
        return _listResponse({'srv-1'});
      }
      return handler(req);
    });
    final adapter = ClickhouseAdapter()..httpClient = client;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'connection_server_id_map',
      jsonEncode({'local_ch_1': 'srv-1'}),
    );
    await adapter.connect(_conn());
    return adapter;
  }

  group('connect：serverConnId 解析', () {
    test('无映射 → 草稿 test → 现场注册 + 写回映射', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true, 'elapsedMs': 5}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'POST') {
          return _jsonResp({'serverConnId': 'srv-1'}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({});
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'unmapped'}}, 500);
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(adapter.isConnected, isTrue);

      final draft = client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test');
      final draftBody = _sentBody(draft);
      expect(draftBody['dbType'], 'clickhouse');
      expect(draftBody['host'], '192.0.2.128');
      expect(draftBody['port'], 9004);
      expect(draftBody['username'], 'ch_test');
      expect(draftBody['password'], 'pw');
      expect(draftBody['defaultDatabase'], 'ch_test_db');

      final register = client.requests.firstWhere(
          (r) => r.method == 'POST' && r.url.path == '/api/gw/connections');
      final body = _sentBody(register);
      expect(body['dbType'], 'clickhouse');
      expect(body['name'], 'CH Live');
      expect(body['readOnly'], false);

      final prefs = await SharedPreferences.getInstance();
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_ch_1'], 'srv-1');
    });

    test('映射有效且 dbType 一致 → 复用，不重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-existing'}),
      );
      final client = _RecordingClient(
        (req) => _listResponse({'srv-existing'}),
      );
      final adapter = ClickhouseAdapter()..httpClient = client;
      await adapter.connect(_conn());

      final posts = client.requests.where(
          (r) => r.method == 'POST' && r.url.path == '/api/gw/connections');
      expect(posts, isEmpty, reason: '有效映射不应重新注册');
    });

    test('映射失效（server 上无此 id）→ 重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-stale'}),
      );
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true, 'elapsedMs': 5}, 200);
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          registered = true;
          return _jsonResp({'serverConnId': 'srv-new'}, 200);
        }
        return _listResponse({'srv-other'});
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      await adapter.connect(_conn());
      expect(registered, isTrue);
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_ch_1'], 'srv-new');
    });

    test('映射 dbType 不匹配（同 localId 跨类型复用）→ 重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-mysql'}),
      );
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true, 'elapsedMs': 5}, 200);
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          registered = true;
          return _jsonResp({'serverConnId': 'srv-ch'}, 200);
        }
        // server 上该 id 注册的是 mysql —— 类型不匹配必须重注册。
        return _jsonResp([
          {'id': 'srv-mysql', 'dbType': 'mysql'}
        ], 200);
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      await adapter.connect(_conn());
      expect(registered, isTrue);
    });

    test('401（草稿 test 被拒）→ AdapterConnectException（码保留/链保留），不注册', () async {
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp(
            {'error': {'code': 'UNAUTHORIZED', 'message': 'bad token'}},
            401,
          );
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          registered = true;
          return _jsonResp({'serverConnId': 'srv-x'}, 200);
        }
        return _listResponse({});
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having(
                (e) => e.failure.errorCode,
                'errorCode',
                'UNAUTHORIZED',
              )
              .having(
                (e) => e.cause,
                'cause',
                isA<ClickhouseGatewayException>(),
              ),
        ),
      );
      expect(registered, isFalse);
      expect(adapter.isConnected, isFalse);
    });

    test('凭据错误（test ok!=true + error map）→ AdapterConnectException 携带 envelope code', () async {
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({
            'ok': false,
            'error': {'code': 'DB_ERROR', 'message': 'user is denied'},
          }, 200);
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          registered = true;
          return _jsonResp({'serverConnId': 'srv-x'}, 200);
        }
        return _listResponse({});
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having(
                (e) => e.failure.kind,
                'kind',
                ConnectionFailureKind.unknown,
              )
              .having((e) => e.failure.errorCode, 'errorCode', 'DB_ERROR')
              .having(
                (e) => e.failure.rawMessage,
                'rawMessage',
                contains('denied'),
              )
              .having((e) => e.failure.target, 'target', '192.0.2.128:9004'),
        ),
      );
      expect(registered, isFalse);
      expect(adapter.isConnected, isFalse);
    });

    test('凭据错误（test ok!=true，字符串 error）→ AdapterConnectException，不注册', () async {
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': false, 'error': 'connection refused'}, 200);
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          registered = true;
          return _jsonResp({'serverConnId': 'srv-x'}, 200);
        }
        return _listResponse({});
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having((e) => e.failure.kind, 'kind', ConnectionFailureKind.unknown)
              .having(
                (e) => e.failure.rawMessage,
                'rawMessage',
                'connection refused',
              )
              .having((e) => e.failure.errorCode, 'errorCode', ''),
        ),
      );
      expect(registered, isFalse);
      expect(adapter.isConnected, isFalse);
    });

    test('T12s wire：error_code=AUTH_DENIED → AdapterConnectException kind=authFailed', () async {
      // T12c：server 草稿 test 失败响应加性新增顶层 `error_code`（snake_case），
      // error 字符串字段原样保留 → kind 分型 authFailed、errorCode 非空。
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({
            'ok': false,
            'error': 'user is denied',
            'error_code': 'AUTH_DENIED',
            'elapsedMs': 12,
          }, 200);
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          registered = true;
          return _jsonResp({'serverConnId': 'srv-x'}, 200);
        }
        return _listResponse({});
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having((e) => e.failure.kind, 'kind', ConnectionFailureKind.authFailed)
              .having((e) => e.failure.errorCode, 'errorCode', 'AUTH_DENIED')
              .having((e) => e.failure.rawMessage, 'rawMessage', 'user is denied')
              .having((e) => e.failure.target, 'target', '192.0.2.128:9004'),
        ),
      );
      expect(registered, isFalse);
      expect(adapter.isConnected, isFalse);
    });
  });

  group('testConnection（草稿不落库单发）', () {
    test('ok:true → null', () async {
      final client = _RecordingClient((req) {
        expect(req.url.path, '/api/gw/connections/test');
        return _jsonResp({'ok': true, 'serverVersion': '26.7.3.19'}, 200);
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      expect(await adapter.testConnection(_conn()), isNull);
      expect(client.requests, hasLength(1));
    });

    test('ok:false → 错误串', () async {
      final client = _RecordingClient(
        (req) => _jsonResp({'ok': false, 'error': 'connection refused'}, 200),
      );
      final adapter = ClickhouseAdapter()..httpClient = client;
      expect(await adapter.testConnection(_conn()), 'connection refused');
    });
  });

  group('executeQuery：SSE 聚合', () {
    test('meta/rows/complete → 列名 map + elapsed', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["id","name"],"columnTypes":["INT UNSIGNED","CHAR"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[1,"a"],[2,null]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":2,"truncated":false,"elapsedMs":12}',
        ]),
      );
      final result = await adapter.executeQuery('SELECT id, name FROM t');
      expect(result.columns, ['id', 'name']);
      expect(result.rows, [
        {'id': 1, 'name': 'a'},
        {'id': 2, 'name': null},
      ]);
      expect(result.executionTime, 12);
    });

    test('DML complete 带 affectedRows、无 meta/rows', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":5,"affectedRows":3}',
        ]),
      );
      final result = await adapter.executeQuery('INSERT INTO t VALUES (1)');
      expect(result.rows, isEmpty);
      expect(result.affectedRows, 3);
    });

    test('rows 分批（多 chunk）聚合', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["n"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[1]]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[2],[3]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":3,"truncated":false,"elapsedMs":2}',
        ]),
      );
      final result = await adapter.executeQuery('SELECT n FROM t');
      expect(result.rows.length, 3);
    });

    test('SSE error(TIMEOUT) 必须上抛，不得静默成功', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"TIMEOUT","message":"statement timed out"}',
        ]),
      );
      await expectLater(
        adapter.executeQuery('SELECT sleep(3)'),
        throwsA(
          isA<ClickhouseGatewayException>()
              .having((e) => e.code, 'code', 'TIMEOUT'),
        ),
      );
    });

    test('error(DB_ERROR) 携带 engineCode 上抛', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"DB_ERROR","message":"Unknown table","engineCode":"60"}',
        ]),
      );
      await expectLater(
        adapter.executeQuery('SELECT * FROM nope'),
        throwsA(
          isA<ClickhouseGatewayException>()
              .having((e) => e.engineCode, 'engineCode', '60'),
        ),
      );
    });

    test('流无 complete → 断连语义（CONNECTION_FAILED）', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["x"]}',
        ]),
      );
      await expectLater(
        adapter.executeQuery('SELECT x FROM t'),
        throwsA(
          isA<ClickhouseGatewayException>()
              .having((e) => e.code, 'code', 'CONNECTION_FAILED'),
        ),
      );
    });

    test('4xx 前置校验（MULTI_STATEMENT）→ 错误形状上抛', () async {
      final adapter = await connectedAdapter(
        (req) => _jsonResp(
          {'error': {'code': 'MULTI_STATEMENT', 'message': 'exactly one statement'}},
          400,
        ),
      );
      await expectLater(
        adapter.executeQuery('SELECT 1; SELECT 2'),
        throwsA(
          isA<ClickhouseGatewayException>()
              .having((e) => e.code, 'code', 'MULTI_STATEMENT'),
        ),
      );
    });

    test('NOT_FOUND 错误触发 onDisconnect（断连回调语义）', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"NOT_FOUND","message":"connection gone"}',
        ]),
      );
      var fired = false;
      adapter.onDisconnect = () => fired = true;
      await expectLater(
        adapter.executeQuery('SELECT 1'),
        throwsA(isA<ClickhouseGatewayException>()),
      );
      expect(fired, isTrue);
    });

    test('请求形状：X-Execution-Id 头 + timeoutMs/rowLimit/database 透传', () async {
      http.Request? queryReq;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        queryReq = req;
        return _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":1}',
        ]);
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-1'}),
      );
      await adapter.connect(_conn(timeoutSecs: 30));
      await adapter.executeQuery('SELECT 1', database: 'ch_test_db');

      final req = queryReq!;
      expect(req.url.path, '/api/gw/connections/srv-1/query');
      expect(
        req.headers['X-Execution-Id'],
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
      expect(req.headers['Authorization'], 'Bearer emb-token');
      final body = _sentBody(req);
      expect(body['sql'], 'SELECT 1');
      expect(body['database'], 'ch_test_db');
      expect(body['timeoutMs'], 30000);
      expect(body['rowLimit'], 10000);
    });

    test('连接无 extra.timeout → 请求不带 timeoutMs（server 默认）', () async {
      http.Request? queryReq;
      final adapter = await connectedAdapter((req) {
        queryReq = req;
        return _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":1}',
        ]);
      });
      await adapter.executeQuery('SELECT 1');
      expect(_sentBody(queryReq!).containsKey('timeoutMs'), isFalse);
    });

    test('stale 库自愈：CONNECTION_FAILED + 有 database 路由 → 清库无库重试一次',
        () async {
      final bodies = <Map<String, dynamic>>[];
      var first = true;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        bodies.add(_sentBody(req));
        if (first) {
          first = false;
          return _sse([
            'event: error\ndata: {"kind":"sql","type":"error","code":"CONNECTION_FAILED","message":"database connection failed"}',
          ]);
        }
        return _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["x"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[1]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":1,"truncated":false,"elapsedMs":2}',
        ]);
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      final r = await adapter.executeQuery('SELECT 1'); // conn 默认 database=ch_test_db
      expect(r.rows, [
        {'x': 1},
      ]);
      expect(bodies[0]['database'], 'ch_test_db'); // 首发带库
      expect(bodies[1].containsKey('database'), isFalse); // 重试无库
      expect(adapter.currentConnection?.database, isNull); // 记录已清
    });
  });

  group('浏览（CH 方言经 executeQuery）', () {
    test('getDatabases：SHOW DATABASES + 滤 information_schema/system_metadata',
        () async {
      http.Request? queryReq;
      final adapter = await connectedAdapter((req) {
        queryReq = req;
        return _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["name"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["ch_test_db"],["INFORMATION_SCHEMA"],["default"],["information_schema"],["system"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":5,"truncated":false,"elapsedMs":3}',
        ]);
      });

      final dbs = await adapter.getDatabases();
      expect(dbs, ['ch_test_db', 'default', 'system']);
      expect(_sentBody(queryReq!).containsKey('database'), isFalse,
          reason: '目录查询不带当前库路由（防 stale default）');
      expect(queryReq!.body, contains('SHOW DATABASES'));
    });

    test('getTables：SHOW TABLES 经当前库路由', () async {
      http.Request? queryReq;
      final adapter = await connectedAdapter((req) {
        queryReq = req;
        return _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["name"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["t1"],["t2"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":2,"truncated":false,"elapsedMs":3}',
        ]);
      });

      final tables = await adapter.getTables();
      expect(tables, ['t1', 't2']);
      final body = _sentBody(queryReq!);
      expect(body['sql'], contains('SHOW TABLES'));
      expect(body['database'], 'ch_test_db');
    });

    test('useDatabase record-only：更新记录库 + 后续查询 database 路由', () async {
      http.Request? queryReq;
      final adapter = await connectedAdapter((req) {
        queryReq = req;
        return _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":1}',
        ]);
      });

      await adapter.useDatabase('default');
      expect(adapter.currentConnection?.database, 'default');
      await adapter.executeQuery('SELECT 1');
      expect(_sentBody(queryReq!)['database'], 'default');
    });

    test('getTableRowCount：SELECT count() 聚合解析', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["c"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[42]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":1,"truncated":false,"elapsedMs":3}',
        ]),
      );
      expect(await adapter.getTableRowCount('gw_ch_rows'), 42);
    });
  });

  group('只读守卫 / 会话缺失 / 断开 / 事务', () {
    test('readOnly 连接 + 写语句 → ReadOnlyBlockedException', () async {
      final client = _RecordingClient((req) => _listResponse({'srv-1'}));
      final adapter = ClickhouseAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-1'}),
      );
      await adapter.connect(_conn(readOnly: true));

      await expectLater(
        adapter.executeQuery('INSERT INTO t VALUES (1)'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('无 server 会话 → connect 抛引导性 StateError（embedded 硬依赖）', () async {
      ServerConnection.resetForTesting();
      final adapter = ClickhouseAdapter()
        ..httpClient = _RecordingClient((req) => _jsonResp({}, 200));
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('dbmaster server'),
          ),
        ),
      );
      expect(adapter.isConnected, isFalse);
    });

    test('disconnect 清空连接态', () async {
      final client = _RecordingClient((req) => _listResponse({'srv-1'}));
      final adapter = ClickhouseAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-1'}),
      );
      await adapter.connect(_conn());
      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
      expect(() => adapter.executeQuery('SELECT 1'), throwsA(isA<Exception>()));
    });

    test('disconnect 对在途执行发 best-effort DELETE 取消', () async {
      final gate = Completer<void>();
      final deletePaths = <String>[];
      String? inFlightId;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.method == 'DELETE') {
          deletePaths.add(req.url.path);
          return _jsonResp({}, 204);
        }
        // query：挂起的 SSE 流（gate 完成前不出数据）。
        inFlightId = req.headers['X-Execution-Id'];
        return http.StreamedResponse(
          gate.future.then((_) => utf8.encode('')).asStream(),
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      });
      final adapter = ClickhouseAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      final queryFuture = adapter.executeQuery('SELECT sleep(60)');
      await pumpEventQueue();
      expect(inFlightId, isNotNull);

      await adapter.disconnect();
      await pumpEventQueue();
      expect(deletePaths, contains('/api/gw/executions/$inFlightId'));

      // 收尾：放开挂起的流（无 complete → CONNECTION_FAILED），避免泄漏。
      gate.complete();
      await expectLater(queryFuture, throwsA(isA<ClickhouseGatewayException>()));
    });

    test('事务 fail-loud：beginTransaction/commit/rollback 抛 UnsupportedError',
        () async {
      final client = _RecordingClient((req) => _listResponse({'srv-1'}));
      final adapter = ClickhouseAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ch_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      await expectLater(
          adapter.beginTransaction(), throwsA(isA<UnsupportedError>()));
      await expectLater(adapter.commit(), throwsA(isA<UnsupportedError>()));
      await expectLater(adapter.rollback(), throwsA(isA<UnsupportedError>()));
      expect(adapter.isInTransaction, isFalse);
    });
  });
}
