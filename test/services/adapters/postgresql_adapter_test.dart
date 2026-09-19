// =============================================================================
// T29 第二批 · PostgreSQL 网关壳 adapter 单元测试（#31 T29 客户端半边）。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例（embedded 握手注入），验证：
// - connect：serverConnId 映射复用 / 草稿 test → 现场注册写回 / 失效重注册 /
//   401 错误形状上抛；wire dbType = 'postgresql'；
// - executeQuery：SSE meta/rows/complete 聚合（位置数组→列名 map）、
//   4xx 前置校验错误形状、请求形状（X-Execution-Id / timeoutMs / rowLimit /
//   database 路由）；
// - SSE error(TIMEOUT) 事件必须上抛（PostgreSqlGatewayException），不得静默
//   成功；
// - 只读守卫、断连回调（CONNECTION_FAILED/NOT_FOUND → onDisconnect）、
//   disconnect 的在途取消 best-effort（DELETE /api/gw/executions/{id}）、
//   无 server 会话的引导性错误；
// - 事务 T29 临时下线：beginTransaction/commit/rollback fail-loud 抛
//   UnsupportedError，isInTransaction 恒 false；
// - useDatabase record-only（存在性经 getDatabases 验证 + database 路由）、
//   setSchema record-only（不发 SET search_path）。
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/connect_failure_dialog.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/readonly_guard.dart';
import 'package:dbmaster/services/server_connection.dart';

import '../../../integration_test/config/postgresql_test_config.dart';
import '../../helpers/pg_gateway_live_helper.dart';

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
      id: 'local_pg_1',
      name: 'PG Live',
      type: DatabaseType.postgresql,
      host: '192.0.2.128',
      port: 5432,
      username: 'postgres',
      password: 'pw',
      database: 'postgres',
      readOnly: readOnly,
      extra: timeoutSecs == null ? null : {'timeout': timeoutSecs},
    );

/// 网关注册表列表（id 集合可配）。
http.StreamedResponse _listResponse(Set<String> ids) =>
    _jsonResp([for (final id in ids) {'id': id, 'dbType': 'postgresql'}], 200);

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

  /// 以有效映射直接连上（跳过注册流程），handler 兜底处理查询请求。
  Future<PostgreSQLAdapter> connectedAdapter(
    http.StreamedResponse Function(http.Request) handler,
  ) async {
    final client = _RecordingClient((req) {
      if (req.url.path == '/api/gw/connections') {
        return _listResponse({'srv-1'});
      }
      return handler(req);
    });
    final adapter = PostgreSQLAdapter()..httpClient = client;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'connection_server_id_map',
      jsonEncode({'local_pg_1': 'srv-1'}),
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
      final adapter = PostgreSQLAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(adapter.isConnected, isTrue);

      // 草稿 test 体形状：host/port/凭据族 + dbType；wire dbType 锁死
      // 'postgresql'；PG 无 charset/timezone 会话字段。
      final draft = client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test');
      final draftBody = _sentBody(draft);
      expect(draftBody['dbType'], 'postgresql');
      expect(draftBody['host'], '192.0.2.128');
      expect(draftBody['port'], 5432);
      expect(draftBody['username'], 'postgres');
      expect(draftBody['password'], 'pw');
      expect(draftBody['defaultDatabase'], 'postgres');

      // 注册体形状：草稿字段 + name/readOnly。
      final register = client.requests.firstWhere(
        (r) => r.method == 'POST' && r.url.path == '/api/gw/connections',
      );
      final body = _sentBody(register);
      expect(body['dbType'], 'postgresql');
      expect(body['name'], 'PG Live');
      expect(body['readOnly'], false);

      // 映射写回（注销链路依赖它）。
      final prefs = await SharedPreferences.getInstance();
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_pg_1'], 'srv-1');
    });

    test('映射有效 → 复用，不重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_pg_1': 'srv-existing'}),
      );
      final client = _RecordingClient(
        (req) => _listResponse({'srv-existing'}),
      );
      final adapter = PostgreSQLAdapter()..httpClient = client;
      await adapter.connect(_conn());

      final posts = client.requests.where(
        (r) => r.method == 'POST' && r.url.path == '/api/gw/connections',
      );
      expect(posts, isEmpty, reason: '有效映射不应重新注册');
    });

    test('映射失效（server 上无此 id）→ 重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_pg_1': 'srv-stale'}),
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
      final adapter = PostgreSQLAdapter()..httpClient = client;
      await adapter.connect(_conn());
      expect(registered, isTrue);
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map')!) as Map)
              .cast<String, String>();
      expect(map['local_pg_1'], 'srv-new');
    });

    test('映射类型不符（同 localId 跨类型）→ 重注册', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_pg_1': 'srv-mysql'}),
      );
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true, 'elapsedMs': 5}, 200);
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          registered = true;
          return _jsonResp({'serverConnId': 'srv-pg'}, 200);
        }
        // server 上该 id 注册的是 mysql 类型 → 不得复用。
        return _jsonResp([
          {'id': 'srv-mysql', 'dbType': 'mysql'},
        ], 200);
      });
      final adapter = PostgreSQLAdapter()..httpClient = client;
      await adapter.connect(_conn());
      expect(registered, isTrue);
    });

    test('401（草稿 test 被拒）→ AdapterConnectException 携带网关错误码，不注册', () async {
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
      final adapter = PostgreSQLAdapter()..httpClient = client;
      // 连接失败 UX 重构 T9b：connect 途中的网关异常包装为 typed
      // AdapterConnectException（code/message 经 gatewayEnvelopeFailure，
      // 原始异常保留在 cause）。
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having((e) => e.failure.errorCode, 'errorCode', 'UNAUTHORIZED')
              .having((e) => e.failure.rawMessage, 'rawMessage', 'bad token')
              .having(
                (e) => e.failure.target,
                'target',
                '192.0.2.128:5432',
              )
              .having((e) => e.cause, 'cause', isA<PostgreSqlGatewayException>()),
        ),
      );
      expect(registered, isFalse);
      expect(adapter.isConnected, isFalse);
    });

    test('草稿 test 失败（envelope ok:false）→ AdapterConnectException 且不注册', () async {
      var registered = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({
            'ok': false,
            'error': {
              'code': 'DB_ERROR',
              'message': 'password authentication failed for user "postgres"',
            },
          }, 200);
        }
        if (req.method == 'POST' && req.url.path == '/api/gw/connections') {
          registered = true;
          return _jsonResp({'serverConnId': 'srv-x'}, 200);
        }
        return _listResponse({});
      });
      final adapter = PostgreSQLAdapter()..httpClient = client;
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
                contains('password authentication failed'),
              )
              .having(
                (e) => e.failure.target,
                'target',
                '192.0.2.128:5432',
              ),
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
            'error': 'password authentication failed for user "postgres"',
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
      final adapter = PostgreSQLAdapter()..httpClient = client;
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having(
                (e) => e.failure.kind,
                'kind',
                ConnectionFailureKind.authFailed,
              )
              .having((e) => e.failure.errorCode, 'errorCode', 'AUTH_DENIED')
              .having(
                (e) => e.failure.rawMessage,
                'rawMessage',
                contains('password authentication failed'),
              )
              .having(
                (e) => e.failure.target,
                'target',
                '192.0.2.128:5432',
              ),
        ),
      );
      expect(registered, isFalse);
      expect(adapter.isConnected, isFalse);
    });
  });

  group('executeQuery：SSE 聚合', () {
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

    test('SSE error(TIMEOUT) 必须上抛，不得静默成功', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"TIMEOUT","message":"statement timed out"}',
        ]),
      );
      await expectLater(
        adapter.executeQuery('SELECT pg_sleep(35)'),
        throwsA(
          isA<PostgreSqlGatewayException>()
              .having((e) => e.code, 'code', 'TIMEOUT'),
        ),
      );
    });

    test('error(DB_ERROR) 携带 engineCode 上抛', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: error\ndata: {"kind":"sql","type":"error","code":"DB_ERROR","message":"syntax error at or near","engineCode":"42601"}',
        ]),
      );
      await expectLater(
        adapter.executeQuery('SELECT * FROM nope'),
        throwsA(
          isA<PostgreSqlGatewayException>()
              .having((e) => e.engineCode, 'engineCode', '42601'),
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
          isA<PostgreSqlGatewayException>()
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
          isA<PostgreSqlGatewayException>()
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
        throwsA(isA<PostgreSqlGatewayException>()),
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

    test('meta columnTypes wire 扩展 → json/jsonb 列识别（驱动 oid 通道替代）', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["id","profile","tags"],"columnTypes":["INT4","JSONB","JSON"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[1,"{\\"age\\":30}","[]"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":1,"truncated":false,"elapsedMs":2}',
        ]),
      );
      final r = await adapter.executeQuery('SELECT * FROM t');
      expect(r.columnTypes, {'profile': 'jsonb', 'tags': 'json'});
    });
  });

  group('只读守卫 / 会话缺失 / 断开', () {
    test('readOnly 连接 + 写语句 → ReadOnlyBlockedException', () async {
      final client = _RecordingClient((req) => _listResponse({'srv-1'}));
      final adapter = PostgreSQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_pg_1': 'srv-1'}),
      );
      await adapter.connect(_conn(readOnly: true));

      await expectLater(
        adapter.executeQuery('DELETE FROM t'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });

    test('无 server 会话 → connect 抛引导性 StateError（embedded 硬依赖）', () async {
      ServerConnection.resetForTesting();
      final adapter = PostgreSQLAdapter()
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
      final adapter = await connectedAdapter(
        (req) => _jsonResp({}, 500),
      );
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
      final adapter = PostgreSQLAdapter()..httpClient = client;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'connection_server_id_map',
        jsonEncode({'local_pg_1': 'srv-1'}),
      );
      await adapter.connect(_conn());

      final queryFuture = adapter.executeQuery('SELECT pg_sleep(60)');
      await pumpEventQueue();
      expect(inFlightId, isNotNull);

      await adapter.disconnect();
      await pumpEventQueue();
      expect(deletePaths, contains('/api/gw/executions/$inFlightId'));

      // 收尾：放开挂起的流（无 complete → CONNECTION_FAILED），避免泄漏。
      gate.complete();
      await expectLater(queryFuture, throwsA(isA<PostgreSqlGatewayException>()));
    });
  });

  group('事务（T29 临时下线，fail-loud）', () {
    test('beginTransaction/commit/rollback 均抛 UnsupportedError，isInTransaction 恒 false', () async {
      final adapter = await connectedAdapter(
        (req) => _jsonResp({}, 500),
      );

      expect(adapter.isInTransaction, isFalse);
      await expectLater(adapter.beginTransaction(), throwsA(isA<UnsupportedError>()));
      await expectLater(adapter.commit(), throwsA(isA<UnsupportedError>()));
      await expectLater(adapter.rollback(), throwsA(isA<UnsupportedError>()));
      expect(adapter.isInTransaction, isFalse);
    });
  });

  group('库/schema 上下文（record-only）', () {
    /// getDatabases 的 SSE 应答（pg_database 列表）。
    http.StreamedResponse _databasesSse() => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["datname"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["postgres"],["northwind"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":2,"truncated":false,"elapsedMs":2}',
        ]);

    test('useDatabase：getDatabases 验证存在 + record-only + 后续查询 database 路由', () async {
      final bodies = <Map<String, dynamic>>[];
      final adapter = await connectedAdapter((req) {
        final body = _sentBody(req);
        bodies.add(body);
        final sql = body['sql'] as String;
        if (sql.contains('pg_database')) return _databasesSse();
        return _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":1}',
        ]);
      });

      await adapter.useDatabase('northwind');
      expect(adapter.currentConnection?.database, 'northwind');
      expect(adapter.getCurrentSchema(), 'public');

      await adapter.executeQuery('SELECT 1');
      expect(bodies.last['database'], 'northwind');
    });

    test('useDatabase 未知库 → 抛错，记录库不变', () async {
      final adapter = await connectedAdapter(
        (req) => _databasesSse(),
      );
      await expectLater(
        adapter.useDatabase('no_such_db'),
        throwsA(isA<Exception>()),
      );
      expect(adapter.currentConnection?.database, 'postgres');
    });

    test('useDatabase 同库幂等（不发任何请求）', () async {
      var queryCount = 0;
      final adapter = await connectedAdapter((req) {
        queryCount++;
        return _sse([
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":0,"truncated":false,"elapsedMs":1}',
        ]);
      });
      await adapter.useDatabase('postgres'); // 与连接 database 相同
      expect(queryCount, 0, reason: '同库切换应为 no-op');
      expect(adapter.getCurrentSchema(), 'public');
    });

    test('setSchema/setSearchPath：record-only 更新当前 schema，不发 SET', () async {
      var queryCount = 0;
      final adapter = await connectedAdapter((req) {
        queryCount++;
        return _jsonResp({}, 500);
      });

      await adapter.setSchema('analytics');
      expect(adapter.getCurrentSchema(), 'analytics');
      expect(queryCount, 0, reason: '网关无状态：不发 SET search_path');
    });
  });

  group('元数据方法走网关执行（代表性链路）', () {
    test('getTables 按当前 schema 过滤（information_schema SQL 逐行保持）', () async {
      http.Request? queryReq;
      final adapter = await connectedAdapter((req) {
        queryReq = req;
        return _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["table_name"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["users"],["orders"]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":2,"truncated":false,"elapsedMs":3}',
        ]);
      });

      final tables = await adapter.getTables();
      expect(tables, ['users', 'orders']);
      expect(queryReq!.body, contains('information_schema.tables'));
      expect(queryReq!.body, contains("table_schema = 'public'"));
    });

    test('getTableIndexes：布尔格（JSON true）→ isUnique 解析', () async {
      final adapter = await connectedAdapter(
        (req) => _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["index_name","column_name","is_unique"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[["users_pkey","id",true],["idx_email","email",false]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":2,"truncated":false,"elapsedMs":3}',
        ]),
      );
      final indexes = await adapter.getTableIndexes('users');
      expect(indexes.length, 2);
      expect(indexes.firstWhere((i) => i.name == 'users_pkey').isUnique, isTrue);
      expect(indexes.firstWhere((i) => i.name == 'idx_email').isUnique, isFalse);
    });

    test('killProcess：pg_terminate_backend SQL 走网关 + 布尔格解析', () async {
      http.Request? queryReq;
      final adapter = await connectedAdapter((req) {
        queryReq = req;
        return _sse([
          'event: meta\ndata: {"kind":"sql","type":"meta","columns":["ok"]}',
          'event: rows\ndata: {"kind":"sql","type":"rows","rows":[[true]]}',
          'event: complete\ndata: {"kind":"sql","type":"complete","rowCount":1,"truncated":false,"elapsedMs":1}',
        ]);
      });
      expect(await adapter.killProcess(1234), isTrue);
      expect(queryReq!.body, contains('pg_terminate_backend(1234)'));
    });

    test('stale 库自愈：CONNECTION_FAILED + 有 database 路由 → 清库无库重试一次', () async {
      final bodies = <Map<String, dynamic>>[];
      var first = true;
      final adapter = await connectedAdapter((req) {
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

      final r = await adapter.executeQuery('SELECT 1'); // conn 默认 database=postgres
      expect(r.rows, [
        {'x': 1},
      ]);
      expect(bodies[0]['database'], 'postgres'); // 首发带库
      expect(bodies[1].containsKey('database'), isFalse); // 重试无库
      expect(adapter.currentConnection?.database, isNull); // 记录已清
    });
  });

  // ==========================================================================
  // 连接失败 UX 重构 T9b · live：错误凭据连真实 PG（env 门控，无环境 skip）。
  //
  // 前置：DBMASTER_SERVER_BIN（或 exe 同目录二进制，embedded server）+
  // PG 真库（--dart-define=DBMASTER_PG_*，见
  // integration_test/config/postgresql_test_config.dart）。前置不可得时以
  // 可 grep 的 PG_LIVE_SKIP 打印并跳过（无假绿纪律）。
  // ==========================================================================
  group('live：错误凭据 → typed failure（真库经 embedded /api/gw）', () {
    testWidgets(
      '错误凭据 → AdapterConnectException（kind/errorCode 非空）+ 对话框结构化详情',
      (tester) async {
        if (!PostgreSQLTestConfig.available) {
          // ignore: avoid_print
          print('PG_LIVE_SKIP: 未配置 PG 真库（--dart-define=DBMASTER_PG_*）');
          return;
        }
        ConnectionFailure? caught;
        var skipReason = '';
        await tester.runAsync(() async {
          // 本文件 per-test setUp 注入的是 fake embedded 会话——清掉后
          // 直启真 server（Process.start + 握手注入）。
          ServerConnection.resetForTesting();
          if (!await ensureEmbeddedServerForPgLive()) {
            skipReason =
                'PG_LIVE_SKIP: embedded server 不可得（构建 server 并设 '
                'DBMASTER_SERVER_BIN）';
            return;
          }
          try {
            final adapter = PostgreSQLAdapter();
            final wrong = DatabaseConnection(
              id: 'live_pg_bad_1',
              name: 'PG Live Wrong Creds',
              type: DatabaseType.postgresql,
              host: PostgreSQLTestConfig.host,
              port: PostgreSQLTestConfig.port,
              username: PostgreSQLTestConfig.username,
              password: '${PostgreSQLTestConfig.password}_wrong',
              database: PostgreSQLTestConfig.database,
            );
            try {
              // runWithHttpOverrides 以 zone value 直注真实 override（裸
              // HttpOverrides.runZoned 的 scope 会捕获 outer current=mock，
              // 绕不开 mock）——本文件 testWidgets 注册的 _MockHttpOverrides
              // 会让裸请求拿到空体 400，断言宽松时假绿（对齐 mysql live 组）。
              await HttpOverrides.runWithHttpOverrides<Future<void>>(
                () async {
                  await adapter.connect(wrong);
                  skipReason = '';
                },
                _RealHttpOverrides(),
              );
            } on AdapterConnectException catch (e) {
              caught = e.failure;
            }
          } finally {
            await stopEmbeddedServerForPgLive();
          }
        });
        if (skipReason.isNotEmpty) {
          // ignore: avoid_print
          print(skipReason);
          return;
        }
        // connect 成功返回（未抛）= 契约破坏，直接判红。
        expect(caught, isNotNull,
            reason: '错误凭据必须抛 AdapterConnectException（T9b typed 管道）');

        final failure = caught!;
        // live 实跑真库：T12s 起 server 对 PG 28P01 返回稳定码
        // error_code=AUTH_DENIED → kind=authFailed。回落形状（unknown/空码）
        // 已由上方 mock 组覆盖，live 组不再容忍——否则 mock 400 也假绿。
        expect(
          failure.kind,
          ConnectionFailureKind.authFailed,
          reason: '真实 PG 错误凭据（28P01）应分型 authFailed，'
              '实测 kind=${failure.kind} errorCode=${failure.errorCode}',
        );
        expect(
          failure.errorCode,
          'AUTH_DENIED',
          reason: '真实 PG 28P01 经 T12s server 应得 error_code=AUTH_DENIED，'
              '实测 errorCode=${failure.errorCode}',
        );
        expect(failure.rawMessage, isNotEmpty);
        expect(
          failure.target,
          '${PostgreSQLTestConfig.host}:${PostgreSQLTestConfig.port}',
        );
        // ignore: avoid_print
        print('PG_LIVE_INFO: errorCode="${failure.errorCode}" '
            'raw="${failure.rawMessage}"');

        // widget 层：ConnectFailureDialog 携带该 live failure。headline 按
        // kind 分型（authFailed 或 unknown 兜底，均为设计文案）；非兜底的
        // 结构化信息（真实错误码 + 原始消息）经「Technical Details」直达 UI。
        final themeProvider = ThemeProvider();
        await themeProvider.load();
        await tester.pumpWidget(
          ChangeNotifierProvider<ThemeProvider>.value(
            value: themeProvider,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: ConnectFailureDialog(
                failure: failure,
                onRetry: () async => false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // 分型 headline：authFailed（新 server 稳定码）或 unknown（回落兜底），
        // 两者均为设计文案（connectFailureAuthFailed / connectFailureUnknown）。
        final unknownHeadline = find.text('Could not connect to the database.');
        final authHeadline = find.text(
          'Authentication failed. Check the username and password.',
        );
        expect(
          unknownHeadline.evaluate().isNotEmpty ||
              authHeadline.evaluate().isNotEmpty,
          isTrue,
          reason: 'headline 应为 authFailed 或 unknown 分型的设计文案',
        );
        // 展开技术详情 → 真实 envelope 错误码与原始消息可见（非兜底）。
        await tester.tap(find.text('Technical Details'));
        await tester.pumpAndSettle();
        expect(find.text('Error Code'), findsOneWidget);
        expect(find.text(failure.errorCode), findsWidgets);
        expect(find.text('Raw Error'), findsOneWidget);
      },
    );
  });
}
