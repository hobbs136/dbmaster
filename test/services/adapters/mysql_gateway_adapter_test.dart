// =============================================================================
// T29 · MySQL 协议族网关壳 adapter 单元测试（#31 T29 客户端半边）。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例（embedded 握手注入），验证：
// - connect：serverConnId 映射复用 / 草稿 test → 现场注册写回 / 失效重注册 /
//   失败路径抛 AdapterConnectException（T9a：401 码保留/链保留、envelope
//   map 与字符串两形状）；族成员 wire dbType（mariadb → 'mariadb'）；
// - live（env 门控，MYSQL_LIVE_SKIP）：错误凭据连真实 MySQL → 结构化失败。
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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/connect_failure_dialog.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/embedded_server_service.dart';
import 'package:dbmaster/services/readonly_guard.dart';
import 'package:dbmaster/services/server_connection.dart';
import '../../../integration_test/config/mysql_test_config.dart';

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

/// exe 同目录定位（发布形态：server 二进制随包；对齐
/// helpers/ch_gateway_live_helper.dart，live 组前置用）。
String? _besideExePath() {
  final name = Platform.isWindows ? 'dbmaster-server.exe' : 'dbmaster-server';
  final beside = File(
    '${File(Platform.resolvedExecutable).parent.path}'
    '${Platform.pathSeparator}$name',
  );
  return beside.existsSync() ? beside.path : null;
}

/// 空壳 HttpOverrides：继承基类默认 createHttpClient（返回真实 HttpClient）。
///
/// 文件内任一 testWidgets 注册即初始化 TestWidgetsFlutterBinding，其
/// _MockHttpOverrides 会把 HttpOverrides.global 换成「永远返回空体 400」的
/// mock，且 tester.runAsync 只逃逸 fake-async、不恢复 overrides——live 组的
/// 真实网关请求必须包进本 override 的 zone 才能出真网络。
class _RealHttpOverrides extends HttpOverrides {}

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
      final adapter = MySQLAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having(
                (e) => e.failure.errorCode,
                'errorCode',
                'UNAUTHORIZED',
              )
              .having((e) => e.cause, 'cause', isA<MySqlGatewayException>()),
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
            'error': {'code': 'DB_ERROR', 'message': 'Access denied for user'},
          }, 200);
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
                contains('Access denied'),
              )
              .having((e) => e.failure.target, 'target', '192.0.2.128:3306'),
        ),
      );
      expect(registered, isFalse);
      expect(adapter.isConnected, isFalse);
    });

    test('凭据错误（test ok!=true + error 字符串）→ AdapterConnectException（无稳定码）', () async {
      // server 草稿 test 端点凭据失败的真实 wire 形状：HTTP 200 +
      // `{ok:false, error:<字符串>}`（无稳定码 → errorCode=''）。
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
      final adapter = MySQLAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having((e) => e.failure.rawMessage, 'rawMessage', 'connection refused')
              .having((e) => e.failure.errorCode, 'errorCode', ''),
        ),
      );
      expect(registered, isFalse);
    });

    test('T12s wire：error_code=AUTH_DENIED → AdapterConnectException kind=authFailed', () async {
      // T12c：server 草稿 test 失败响应加性新增顶层 `error_code`（snake_case），
      // error 字符串字段原样保留 → kind 分型 authFailed、errorCode 非空。
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({
            'ok': false,
            'error': 'Access denied for user',
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
      final adapter = MySQLAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having((e) => e.failure.kind, 'kind', ConnectionFailureKind.authFailed)
              .having((e) => e.failure.errorCode, 'errorCode', 'AUTH_DENIED')
              .having(
                (e) => e.failure.rawMessage,
                'rawMessage',
                'Access denied for user',
              )
              .having((e) => e.failure.target, 'target', '192.0.2.128:3306'),
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

  // ==========================================================================
  // 连接失败 UX 重构 T9a · 真实库用例（env 门控，无环境按惯例 skip）。
  //
  // 前置（缺一即以可 grep 的 MYSQL_LIVE_SKIP 跳过，无假绿纪律）：
  // - DBMASTER_SERVER_BIN（或 exe 同目录 dbmaster-server）——embedded server；
  // - --dart-define=DBMASTER_MYSQL_HOST[/PORT/USER]（凭据不入库——密码在
  //   用例内造错，真实凭据失败由 server 草稿 test 端点在线上产生）。
  // 形态对齐 clickhouse_gateway_live_test.dart（Process.start 直启 +
  // EmbeddedHandshake.parse；VM 环境无 path_provider 通道）。
  // ==========================================================================
  group('live：错误凭据连真实 MySQL（env 门控）', () {
    Process? liveServer;
    EmbeddedHandshake? handshake;
    var liveReady = false;

    setUpAll(() async {
      if (!MySQLTestConfig.available) {
        // ignore: avoid_print
        print('MYSQL_LIVE_SKIP: DBMASTER_MYSQL_HOST 未配置');
        return;
      }
      final binaryPath =
          Platform.environment['DBMASTER_SERVER_BIN'] ?? _besideExePath();
      if (binaryPath == null) {
        // ignore: avoid_print
        print('MYSQL_LIVE_SKIP: embedded server 不可得（设 DBMASTER_SERVER_BIN）');
        return;
      }
      final dataDir = await Directory.systemTemp.createTemp('mysql_live_gw_');
      final proc = await Process.start(
        binaryPath,
        ['--embedded', '--data-dir', dataDir.path],
      );
      liveServer = proc;
      // stderr 必须立即持续排空（管道缓冲写满会阻塞握手，实锤见
      // helpers/ch_gateway_live_helper.dart 注释）。
      unawaited(proc.stderr.drain<void>());
      final hs = await proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .map(EmbeddedHandshake.parse)
          .firstWhere((h) => h != null, orElse: () => null)
          .timeout(const Duration(seconds: 15), onTimeout: () => null);
      if (hs == null) {
        proc.kill(ProcessSignal.sigkill);
        liveServer = null;
        // ignore: avoid_print
        print('MYSQL_LIVE_SKIP: embedded server 握手超时');
        return;
      }
      handshake = hs;
      liveReady = true;
    });

    tearDownAll(() {
      liveServer?.kill(ProcessSignal.sigkill);
      liveServer = null;
      ServerConnection.resetForTesting();
    });

    // 真实 IO 必须（1）包进 tester.runAsync 逃逸 fake-async zone，（2）HTTP
    // 再包进 _RealHttpOverrides zone——同文件任一 testWidgets 注册即初始化
    // TestWidgetsFlutterBinding，其 _MockHttpOverrides 让全文件所有
    // HttpClient 永远返回空体 HTTP 400，而 runAsync 不恢复 HttpOverrides。
    // （postgresql_adapter_test.dart 的 live 用例只做了（1），其对 mock 400
    // 不设防——见该文件遗留问题。）
    testWidgets(
      '错误凭据连真实 MySQL → AdapterConnectException（kind=authFailed/unknown + 原始消息非空）',
      (tester) async {
        if (!liveReady) return;
        final adapter = MySQLAdapter();
        AdapterConnectException? typed;
        var skipReason = '';
        await tester.runAsync(() async {
          // TCP 预检：测试服务器近期可能离线——不可达按 env 门控惯例 skip。
          try {
            final sock = await Socket.connect(
              MySQLTestConfig.host,
              MySQLTestConfig.port,
              timeout: const Duration(seconds: 3),
            );
            sock.destroy();
          } on Exception catch (e) {
            skipReason = 'MYSQL_LIVE_SKIP: MySQL 主机不可达'
                '（${MySQLTestConfig.host}:${MySQLTestConfig.port}）: $e';
            return;
          }

          // 外层 setUp 注入的是 fake 端口会话——恢复真实 embedded 握手。
          ServerConnection.resetForTesting();
          final hs = handshake!; // liveReady 仅在握手成功后置 true
          ServerConnection().connectEmbedded(
            port: hs.port,
            accessToken: hs.accessToken,
            refreshToken: hs.refreshToken,
            installUuid: hs.installUuid,
            version: hs.version,
          );

          try {
            // runWithHttpOverrides 以 zone value 直注真实 override（裸
            // HttpOverrides.runZoned 的 scope 会捕获 outer current=mock，
            // 绕不开 mock）。
            await HttpOverrides.runWithHttpOverrides<Future<void>>(
              () async {
                await adapter.connect(
                  DatabaseConnection(
                    id: 'live_mysql_wrongpw',
                    name: 'MySQL Live WrongPw',
                    type: DatabaseType.mysql,
                    host: MySQLTestConfig.host,
                    port: MySQLTestConfig.port,
                    username: MySQLTestConfig.username.isEmpty
                        ? 'root'
                        : MySQLTestConfig.username,
                    password:
                        'wrong-password-${DateTime.now().millisecondsSinceEpoch}',
                  ),
                );
              },
              _RealHttpOverrides(),
            );
          } on AdapterConnectException catch (e) {
            typed = e;
          }
        });
        if (skipReason.isNotEmpty) {
          // ignore: avoid_print
          print(skipReason);
          return;
        }
        expect(typed, isNotNull, reason: '错误凭据应抛 AdapterConnectException');
        final failure = typed!.failure; // 上一行 expect 已确保非空

        // server 有稳定码时 kind=authFailed（AUTH_DENIED）；旧 server/无码
        // envelope 回落 unknown——errorCode 两种形态下均非空。
        expect(
          failure.kind == ConnectionFailureKind.authFailed ||
              failure.kind == ConnectionFailureKind.unknown,
          isTrue,
          reason: '错误凭据分型应为 authFailed（T12s 稳定码）或 unknown（回落）',
        );
        expect(failure.errorCode, isNotEmpty);
        expect(failure.rawMessage, isNotEmpty, reason: '原始引擎错误应保留供展示层分型');
        expect(
          failure.target,
          '${MySQLTestConfig.host}:${MySQLTestConfig.port}',
        );
        expect(failure.occurredAt, isA<DateTime>());
        expect(typed!.cause, isNotNull);
        expect(adapter.isConnected, isFalse);
        // ignore: avoid_print
        print('MYSQL_LIVE_INFO: errorCode="${failure.errorCode}" '
            'raw="${failure.rawMessage}"');
      },
    );
  });

  // ==========================================================================
  // 连接失败 UX 重构 T9a × T5：结构化失败端到端呈现（widget 冒烟）。
  //
  // 真实库 live 用例因测试服务器离线按惯例 skip——此处用 envelope 失败的
  // 确定性形状验证结构化字段（code/rawMessage/target）能经 T5 对话框到达
  // 展示层。人话分型现状：T12c 起按 envelope 稳定码分型（AUTH_DENIED →
  // authFailed、UNREACHABLE → unreachable；DB_ERROR 等未列码 → unknown）。
  // 本组 mock 用 code='DB_ERROR'（非稳定码）→ 仍分型 unknown，人话行为
  // connectFailureUnknown（兜底）；网关专属文案为后续波次裁决点（见 T9a 汇报）。
  // ==========================================================================
  group('T9a × T5：ConnectFailureDialog 呈现网关结构化失败（widget）', () {
    testWidgets('envelope 失败字段进技术详情', (tester) async {
      final failure = gatewayEnvelopeFailure(
        code: 'DB_ERROR',
        message: 'Access denied for user',
        target: '192.168.3.128:3306',
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ConnectFailureDialog(
              failure: failure,
              onRetry: () async => false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 折叠态不渲染详情子树（含 code/target 等技术内容）——先展开。
      await tester.tap(find.text('Technical Details'));
      await tester.pumpAndSettle();

      expect(find.text('DB_ERROR'), findsOneWidget);
      expect(find.textContaining('Access denied for user'), findsWidgets);
      expect(find.text('192.168.3.128:3306'), findsOneWidget);
    });
  });

}
