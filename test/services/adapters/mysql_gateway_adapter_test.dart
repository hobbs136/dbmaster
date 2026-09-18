// =============================================================================
// T29 · MySQL 协议族网关壳 adapter 单元测试（#31 T29 客户端半边）。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例（embedded 握手注入），验证：
// - connect：serverConnId 映射复用 / 草稿 test → 现场注册写回 / 失效重注册 /
//   401 错误形状上抛；族成员 wire dbType（mariadb → 'mariadb'）；
// - executeQuery：SSE meta/rows/complete 聚合（位置数组→列名 map）、
//   4xx 前置校验错误形状、请求形状（X-Execution-Id / timeoutMs / rowLimit /
//   database 路由）；
// - SSE error(TIMEOUT) 事件必须上抛（MySqlGatewayException），不得静默成功；
// - 只读守卫、断连回调（CONNECTION_FAILED/NOT_FOUND → onDisconnect）、
//   disconnect 的在途取消 best-effort（DELETE /api/gw/executions/{id}）、
//   无 server 会话的引导性错误；
// - 事务 T29 临时下线：beginTransaction/commit/rollback fail-loud 抛
//   UnsupportedError。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
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
      id: 'local_mysql_1',
      name: 'MySQL Live',
      type: DatabaseType.mysql,
      host: '192.0.2.128',
      port: 3306,
      username: 'root',
      password: 'pw',
      database: 'test',
      readOnly: readOnly,
      extra: timeoutSecs == null ? null : {'timeout': timeoutSecs},
    );

/// 网关注册表列表（id 集合可配）。
http.StreamedResponse _listResponse(Set<String> ids) =>
    _jsonResp([for (final id in ids) {'id': id, 'dbType': 'mysql'}], 200);

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
      final adapter = MySQLAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(adapter.isConnected, isTrue);

      // 草稿 test 体形状：host/port/凭据族 + dbType；无 charset/timezone
      // （draft body 契约不含会话变量字段）。
      final draft = client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test');
      final draftBody = _sentBody(draft);
      expect(draftBody['dbType'], 'mysql');
      expect(draftBody['host'], '192.0.2.128');
      expect(draftBody['port'], 3306);
      expect(draftBody['username'], 'root');
      expect(draftBody['password'], 'pw');
      expect(draftBody['defaultDatabase'], 'test');
      expect(draftBody.containsKey('charset'), isFalse);
      expect(draftBody.containsKey('timezone'), isFalse);

      // 注册体形状：草稿字段 + name/readOnly。
      final register = client.requests
          .firstWhere((r) => r.method == 'POST' && r.url.path == '/api/gw/connections');
      final body = _sentBody(register);
      expect(body['dbType'], 'mysql');
      expect(body['host'], '192.0.2.128');
      expect(body['port'], 3306);
      expect(body['username'], 'root');
      expect(body['password'], 'pw');
      expect(body['defaultDatabase'], 'test');
      expect(body['name'], 'MySQL Live');
      expect(body['readOnly'], false);

      // 映射写回（注销链路依赖它）。
      final prefs = await SharedPreferences.getInstance();
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_mysql_1'], 'srv-1');
    });

    test('映射有效 → 复用，不重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-existing'}),
      );
      final client = _RecordingClient(
        (req) => _listResponse({'srv-existing'}),
      );
      final adapter = MySQLAdapter()..httpClient = client;
      await adapter.connect(_conn());

      final posts = client.requests
          .where((r) => r.method == 'POST' && r.url.path == '/api/gw/connections');
      expect(posts, isEmpty, reason: '有效映射不应重新注册');
    });

    test('映射失效（server 上无此 id）→ 重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-stale'}),
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
      final adapter = MySQLAdapter()..httpClient = client;
      await adapter.connect(_conn());
      expect(registered, isTrue);
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_mysql_1'], 'srv-new');
    });

    test('401（草稿 test 被拒）→ 错误形状上抛，不注册', () async {
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
      final adapter = MySQLAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<MySqlGatewayException>()
              .having((e) => e.code, 'code', 'UNAUTHORIZED'),
        ),
      );
      expect(registered, isFalse);
      expect(adapter.isConnected, isFalse);
    });

    test('族成员 wire dbType：mariadb → "mariadb"', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true, 'elapsedMs': 5}, 200);
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          return _jsonResp({'serverConnId': 'srv-maria'}, 200);
        }
        return _listResponse({});
      });
      final adapter = MariadbAdapter()..httpClient = client;
      final conn = DatabaseConnection(
        id: 'local_mariadb_1',
        name: 'MariaDB Live',
        type: DatabaseType.mariadb,
        host: '192.0.2.128',
        port: 3307,
        username: 'root',
        password: 'pw',
      );
      final ok = await adapter.connect(conn);
      expect(ok, isTrue);

      final register = client.requests
          .firstWhere((r) => r.method == 'POST' && r.url.path == '/api/gw/connections');
      final body = _sentBody(register);
      expect(body['dbType'], 'mariadb');
      expect(body['port'], 3307);
      // 未指定 database → 不带 defaultDatabase。
      expect(body.containsKey('defaultDatabase'), isFalse);
    });
  });

  group('executeQuery：SSE 聚合', () {
    Future<MySQLAdapter> connectedAdapter(
      http.StreamedResponse Function(http.Request) handler,
    ) async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _listResponse({'srv-1'});
        }
        return handler(req);
      });
      final adapter = MySQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
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

    test('SSE error(TIMEOUT) 必须上抛，不得静默成功', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"TIMEOUT","message":"statement timed out"}',
        ]),
      );
      // 网关壳语义：超时以 error 事件到达 = 抛 MySqlGatewayException——
      // 锁死「超时不静默成功」不复发。
      await expectLater(
        adapter.executeQuery('SELECT SLEEP(35)'),
        throwsA(
          isA<MySqlGatewayException>()
              .having((e) => e.code, 'code', 'TIMEOUT'),
        ),
      );
    });

    test('error(DB_ERROR) 携带 engineCode 上抛', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"DB_ERROR","message":"You have an error in your SQL syntax","engineCode":"1064"}',
        ]),
      );
      await expectLater(
        adapter.executeQuery('SELECT * FROM nope'),
        throwsA(
          isA<MySqlGatewayException>()
              .having((e) => e.engineCode, 'engineCode', '1064'),
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
          isA<MySqlGatewayException>()
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
          isA<MySqlGatewayException>()
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
        throwsA(isA<MySqlGatewayException>()),
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
      final adapter = MySQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
      );
      await adapter.connect(_conn(readOnly: true));

      await expectLater(
        adapter.executeQuery('DELETE FROM t'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('无 server 会话 → connect 抛引导性 StateError（embedded 硬依赖）', () async {
      ServerConnection.resetForTesting();
      final adapter = MySQLAdapter()
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
      final adapter = MySQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
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
        if (req.url.path == '/api/gw/connections') {
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
      final adapter = MySQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      final queryFuture = adapter.executeQuery('SELECT SLEEP(60)');
      await pumpEventQueue();
      expect(inFlightId, isNotNull);

      await adapter.disconnect();
      await pumpEventQueue();
      expect(deletePaths, contains('/api/gw/executions/$inFlightId'));

      // 收尾：放开挂起的流（无 complete → CONNECTION_FAILED），避免泄漏。
      gate.complete();
      await expectLater(queryFuture, throwsA(isA<MySqlGatewayException>()));
    });
  });

  group('事务（T29 临时下线，fail-loud）', () {
    test('beginTransaction/commit/rollback 均抛 UnsupportedError', () async {
      final client = _RecordingClient((req) => _listResponse({'srv-1'}));
      final adapter = MySQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      await expectLater(adapter.beginTransaction(), throwsA(isA<UnsupportedError>()));
      await expectLater(adapter.commit(), throwsA(isA<UnsupportedError>()));
      await expectLater(adapter.rollback(), throwsA(isA<UnsupportedError>()));
    });
  });

  group('元数据方法走网关执行（代表性链路）', () {
    test('getDatabases 过滤系统库（SHOW DATABASES 逐行保持自裸连接版）', () async {
      http.Request? queryReq;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _listResponse({'srv-1'});
        }
        queryReq = req;
        return _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["Database"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["dbmaster_a"],["mysql"],["information_schema"],["northwind"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":4,"truncated":false,"elapsedMs":3}',
        ]);
      });
      final adapter = MySQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      final dbs = await adapter.getDatabases();
      expect(dbs, ['dbmaster_a', 'northwind']);
      expect(queryReq!.body, contains('SHOW DATABASES'));
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
      final adapter = MySQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      await adapter.useDatabase('northwind');
      expect(adapter.currentConnection?.database, 'northwind');
      await adapter.executeQuery('SELECT 1');
      expect(_sentBody(queryReq!)['database'], 'northwind');
    });
  });

  group('T29 网关口径语义补丁', () {
    Future<MySQLAdapter> connectedAdapter(_RecordingClient client) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_mysql_1': 'srv-1'}),
      );
      final adapter = MySQLAdapter()..httpClient = client;
      await adapter.connect(_conn());
      return adapter;
    }

    test('USE 语句拦截：发网关验证存在性 + 更新本地记录库 + 后续查询路由', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _listResponse({'srv-1'});
        }
        bodies.add(_sentBody(req));
        return _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":1}',
        ]);
      });
      final adapter = await connectedAdapter(client);

      await adapter.executeQuery('USE `other_db`');
      expect(bodies.last['sql'], contains('USE'));
      expect(adapter.currentConnection?.database, 'other_db');
      await adapter.executeQuery('SELECT 1');
      expect(bodies.last['database'], 'other_db');
    });

    test('stale 库自愈：CONNECTION_FAILED + 有 database 路由 → 清库无库重试一次', () async {
      final bodies = <Map<String, dynamic>>[];
      var first = true;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
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
      final adapter = await connectedAdapter(client);

      final r = await adapter.executeQuery('SELECT 1'); // conn 默认 database=test
      expect(r.rows, [
        {'x': 1},
      ]);
      expect(bodies[0]['database'], 'test'); // 首发带库
      expect(bodies[1].containsKey('database'), isFalse); // 重试无库
      expect(adapter.currentConnection?.database, isNull); // 记录已清
    });

    test('meta columnTypes wire 扩展 → json 列识别（T031 数据源恢复）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections') {
          return _listResponse({'srv-1'});
        }
        return _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["id","profile","name"],"columnTypes":["INT","JSON","VARCHAR"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[1,{"age":30},"a"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":1,"truncated":false,"elapsedMs":2}',
        ]);
      });
      final adapter = await connectedAdapter(client);

      final r = await adapter.executeQuery('SELECT * FROM t');
      expect(r.columnTypes, {'profile': 'json'});
      expect(r.rows.first['profile'], {'age': 30});
    });
  });
  // server 侧 SSH 隧道：draft/test body 形状（SQL 族不带 TLS 两键——
  // useTls 仅 Redis/Mongo/TDengine 三类网关连接生效）。
  group('draft body：server 侧 SSH 隧道', () {
    test('ssh 对象存在 → 原样透传；无 ssh → 不带键', () async {
      final sshWire = {
        'host': 'jump.example.com',
        'port': 22,
        'username': 'deploy',
        'authMode': 'password',
        'password': 'hunter2',
      };
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true, 'elapsedMs': 5}, 200);
        }
        return _jsonResp({'serverConnId': 'srv-x'}, 200);
      });
      final adapter = MySQLAdapter()..httpClient = client;
      await adapter.testConnection(DatabaseConnection(
        id: 'local_mysql_1',
        name: 'MySQL Live',
        type: DatabaseType.mysql,
        host: '192.0.2.128',
        port: 3306,
        username: 'root',
        password: 'pw',
        database: 'test',
        extra: {'useTls': true, 'ssh': sshWire},
      ));

      final withSsh = _sentBody(client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test'));
      expect(withSsh['ssh'], sshWire);
      // useTls 对 SQL 族不透传（无 extra 键）
      expect(withSsh.containsKey('extra'), isFalse);

      final client2 = _RecordingClient((req) =>
          _jsonResp({'ok': true, 'elapsedMs': 5}, 200));
      final adapter2 = MySQLAdapter()..httpClient = client2;
      await adapter2.testConnection(_conn());
      final noSsh = _sentBody(client2.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test'));
      expect(noSsh.containsKey('ssh'), isFalse);
    });
  });

}
