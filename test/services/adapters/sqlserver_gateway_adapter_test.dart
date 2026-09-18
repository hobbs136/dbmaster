// =============================================================================
// T28 · SQL Server 网关壳 adapter 单元测试（#31 T28 客户端半边）。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例（embedded 握手注入），验证：
// - connect：serverConnId 映射复用 / 现场注册写回 / 失效重注册；
// - executeQuery：SSE meta/rows/complete 聚合（位置数组→列名 map）、
//   4xx 前置校验错误形状、请求形状（X-Execution-Id / timeoutMs / rowLimit /
//   database 路由）；
// - **#30 SS-TIMEOUT-301 结案守卫（单测层）**：SSE error(TIMEOUT) 事件必须
//   上抛（SqlServerGatewayException），不得静默成功——FFI 层 dbsettime 的
//   超时静默成功根因已随 FFI 删除，本守卫锁死网关语义不复发；
// - 只读守卫、断连回调（CONNECTION_FAILED/NOT_FOUND → onDisconnect）、
//   disconnect 的在途取消 best-effort、无 server 会话的引导性错误。
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
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
  final body = events.join('\n\n') + '\n\n';
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
      id: 'local_ss_1',
      name: 'SS Live',
      type: DatabaseType.sqlserver,
      host: '192.0.2.128',
      port: 1433,
      username: 'sa',
      password: 'pw',
      database: 'master',
      readOnly: readOnly,
      extra: timeoutSecs == null ? null : {'timeout': timeoutSecs},
    );

/// 网关注册表列表（id 集合可配）。
http.StreamedResponse _listResponse(Set<String> ids) =>
    _jsonResp([for (final id in ids) {'id': id, 'dbType': 'sqlserver'}], 200);

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

  group('connect：serverConnId 解析', () {
    test('无映射 → 现场注册 + 写回映射', () async {
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
      final adapter = SqlServerAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(adapter.isConnected, isTrue);

      // 注册体形状：sqlserver 草稿族 + name/readOnly。
      final register = client.requests
          .firstWhere((r) => r.method == 'POST' && r.url.path == '/api/gw/connections');
      final body = _sentBody(register);
      expect(body['dbType'], 'sqlserver');
      expect(body['host'], '192.0.2.128');
      expect(body['port'], 1433);
      expect(body['username'], 'sa');
      expect(body['password'], 'pw');
      expect(body['defaultDatabase'], 'master');
      expect(body['name'], 'SS Live');
      expect(body['readOnly'], false);

      // 映射写回（注销链路依赖它）。
      final prefs = await SharedPreferences.getInstance();
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_ss_1'], 'srv-1');
    });

    test('映射有效 → 复用，不重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ss_1': 'srv-existing'}),
      );
      final client = _RecordingClient(
        (req) => _listResponse({'srv-existing'}),
      );
      final adapter = SqlServerAdapter()..httpClient = client;
      await adapter.connect(_conn());

      final posts = client.requests
          .where((r) => r.method == 'POST' && r.url.path == '/api/gw/connections');
      expect(posts, isEmpty, reason: '有效映射不应重新注册');
    });

    test('映射失效（server 上无此 id）→ 重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ss_1': 'srv-stale'}),
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
      final adapter = SqlServerAdapter()..httpClient = client;
      await adapter.connect(_conn());
      expect(registered, isTrue);
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_ss_1'], 'srv-new');
    });
  });

  group('executeQuery：SSE 聚合', () {
    Future<SqlServerAdapter> connectedAdapter(
      http.StreamedResponse Function(http.Request) handler,
    ) async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _listResponse({'srv-1'});
        }
        return handler(req);
      });
      final adapter = SqlServerAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ss_1': 'srv-1'}),
      );
      await adapter.connect(_conn());
      return adapter;
    }

    test('meta/rows/complete → 列名 map + affectedRows + elapsed', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["id","name"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[1,"a"],[2,null]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":2,"truncated":false,"elapsedMs":12,"affectedRows":0}',
        ]),
      );
      final result = await adapter.executeQuery('SELECT id, name FROM t');
      expect(result.columns, ['id', 'name']);
      expect(result.rows, [
        {'id': 1, 'name': 'a'},
        {'id': 2, 'name': null},
      ]);
      expect(result.affectedRows, 0);
      expect(result.executionTime, 12);
    });

    test('DML complete 带 affectedRows、无 meta/rows', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":5,"affectedRows":3}',
        ]),
      );
      final result = await adapter.executeQuery('DELETE FROM t WHERE id=1');
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

    test('#30 守卫：SSE error(TIMEOUT) 必须上抛，不得静默成功', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"TIMEOUT","message":"statement timed out"}',
        ]),
      );
      // FFI 版缺陷（SS-TIMEOUT-301）：WAITFOR 超时后查询正常返回（静默
      // 成功）。网关壳语义：超时以 error 事件到达 = 抛 SqlServerGatewayException
      // ——锁死不复发。
      await expectLater(
        adapter.executeQuery("WAITFOR DELAY '00:00:35'"),
        throwsA(
          isA<SqlServerGatewayException>()
              .having((e) => e.code, 'code', 'TIMEOUT'),
        ),
      );
    });

    test('error(DB_ERROR) 携带 engineCode 上抛', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"DB_ERROR","message":"Invalid object name","engineCode":"208"}',
        ]),
      );
      await expectLater(
        adapter.executeQuery('SELECT * FROM nope'),
        throwsA(
          isA<SqlServerGatewayException>()
              .having((e) => e.engineCode, 'engineCode', '208'),
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
          isA<SqlServerGatewayException>()
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
          isA<SqlServerGatewayException>()
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
        throwsA(isA<SqlServerGatewayException>()),
      );
      expect(fired, isTrue);
    });

    test('请求形状：X-Execution-Id 头 + timeoutMs/rowLimit/database 透传', () async {
      http.Request? queryReq;
      final adapter = await connectedAdapter((req) {
        queryReq = req;
        return _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":1}',
        ]);
      });
      await adapter.connect(_conn(timeoutSecs: 30));
      await adapter.executeQuery('SELECT 1', database: 'northwind');

      final req = queryReq!;
      expect(req.url.path, '/api/gw/connections/srv-1/query');
      expect(req.headers['X-Execution-Id'], matches(
        RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
      ));
      expect(req.headers['Authorization'], 'Bearer emb-token');
      final body = _sentBody(req);
      expect(body['sql'], 'SELECT 1');
      expect(body['database'], 'northwind');
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
  });

  group('只读守卫 / 会话缺失 / 断开', () {
    test('readOnly 连接 + 写语句 → ReadOnlyBlockedException', () async {
      final client = _RecordingClient((req) => _listResponse({'srv-1'}));
      final adapter = SqlServerAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ss_1': 'srv-1'}),
      );
      await adapter.connect(_conn(readOnly: true));

      await expectLater(
        adapter.executeQuery('DELETE FROM t'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('无 server 会话 → connect 抛引导性 StateError（embedded 硬依赖）', () async {
      ServerConnection.resetForTesting();
      final adapter = SqlServerAdapter()
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
      final adapter = SqlServerAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ss_1': 'srv-1'}),
      );
      await adapter.connect(_conn());
      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
      expect(() => adapter.executeQuery('SELECT 1'), throwsA(isA<Exception>()));
    });
  });

  group('元数据方法走网关执行（代表性链路）', () {
    test('getDatabases 过滤系统库（SQL 逐行保持自 FFI 版）', () async {
      http.Request? queryReq;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _listResponse({'srv-1'});
        }
        queryReq = req;
        return _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["name"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["dbmaster_a"],["northwind"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":2,"truncated":false,"elapsedMs":3}',
        ]);
      });
      final adapter = SqlServerAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ss_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      final dbs = await adapter.getDatabases();
      expect(dbs, ['dbmaster_a', 'northwind']);
      // SQL 含系统库排除（master/tempdb/model/msdb）。
      expect(queryReq!.body, contains('sys.databases'));
      expect(queryReq!.body, contains("'master'"));
    });

    test('useDatabase 更新连接目标（后续查询 database 路由）', () async {
      http.Request? queryReq;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _listResponse({'srv-1'});
        }
        queryReq = req;
        return _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":1}',
        ]);
      });
      final adapter = SqlServerAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_ss_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      await adapter.useDatabase('northwind');
      expect(adapter.currentConnection?.database, 'northwind');
      await adapter.executeQuery('SELECT 1');
      expect(_sentBody(queryReq!)['database'], 'northwind');
    });
  });
}
