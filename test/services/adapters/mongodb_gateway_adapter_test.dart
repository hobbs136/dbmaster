// =============================================================================
// T29 非 SQL 批次（B2）· MongoDB 网关壳 adapter 单元测试。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例（embedded 握手注入），验证：
// - connect：serverConnId 映射复用 / 草稿 test → 现场注册写回 / 类型不匹配
//   重注册 / test 失败返 false / 集群 extra 四键透传 / 空凭据省略；
// - executeQuery（kind:"mongo" runCommand 通道）：find 文档行展开（扩展
//   JSON 解包）、count/distinct/aggregate 命令形状、无法解析引导行、
//   SELECT 1 → ping 拦截、请求形状（X-Execution-Id/database/rowLimit/
//   timeoutMs）；
// - SSE error 事件包装上抛；CONNECTION_FAILED/NOT_FOUND → onDisconnect；
// - 元数据：getTables（system.* 过滤排序）/ getTableColumns（采样 + 类型
//   推断）/ getTableIndexes / useDatabase record-only 路由 / dropDatabase
//   路由与当前库回落 / renameTable admin 路由；
// - Mongo 特有面：insertOne/updateOne/deleteMany（命令形状 + n 语义）、
//   getReplicaSetStatus（admin + members 映射 / 错误 → null）、
//   inferDocumentSchema（occurrence/Mixed）、getCollectionStats；
// - 只读守卫、无 server 会话引导错误、disconnect 在途取消。
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
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

/// 游标命令的 SSE 三事件（单列 doc）。
List<String> _cursorEvents(List<Map<String, dynamic>> docs) => [
  'event: meta\ndata: {"kind":"mongo","type":"meta","columns":["doc"]}',
  if (docs.isNotEmpty)
    'event: rows\ndata: {"kind":"mongo","type":"rows","rows":${jsonEncode([
      for (final d in docs) [d],
    ])}}',
  'event: complete\ndata: {"kind":"mongo","type":"complete","rowCount":${docs.length},"truncated":false,"elapsedMs":5}',
];

/// 非游标命令的 SSE 三事件（单列 result）。
List<String> _resultEvents(Map<String, dynamic> doc) => [
  'event: meta\ndata: {"kind":"mongo","type":"meta","columns":["result"]}',
  'event: rows\ndata: {"kind":"mongo","type":"rows","rows":${jsonEncode([
    [doc],
  ])}}',
  'event: complete\ndata: {"kind":"mongo","type":"complete","rowCount":1,"truncated":false,"elapsedMs":4}',
];

/// 写命令的 SSE（无行，affectedRows）。
String _completeEvent(int affected) =>
    'event: complete\ndata: {"kind":"mongo","type":"complete","rowCount":0,"truncated":false,"affectedRows":$affected,"elapsedMs":3}';

DatabaseConnection _conn({
  bool readOnly = false,
  int? timeoutSecs,
  Map<String, dynamic>? extra,
}) => DatabaseConnection(
  id: 'local_mongo_1',
  name: 'Mongo Live',
  type: DatabaseType.mongodb,
  host: '192.0.2.128',
  port: 27017,
  username: 'admin',
  password: 'pw',
  database: 'admin',
  readOnly: readOnly,
  extra: {
    'mongoConnectionMode': 'direct',
    if (timeoutSecs != null) 'timeout': timeoutSecs,
    ...?extra,
  },
);

http.StreamedResponse _listResponse(Set<String> ids) => _jsonResp([
  for (final id in ids) {'id': id, 'dbType': 'mongodb'},
], 200);

/// connect 走通（无映射 → test → 注册）的公共回放。
_RecordingClient _freshConnectClient() => _RecordingClient((req) {
  if (req.url.path == '/api/gw/connections/test') {
    return _jsonResp({'ok': true, 'elapsedMs': 5}, 200);
  }
  if (req.url.path == '/api/gw/connections' && req.method == 'POST') {
    return _jsonResp({'serverConnId': 'srv-1'}, 200);
  }
  if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
    return _listResponse({});
  }
  return _jsonResp({
    'error': {'code': 'X', 'message': 'unmapped'},
  }, 500);
});

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
      final client = _freshConnectClient();
      final adapter = MongoDBAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(adapter.isConnected, isTrue);

      // 草稿体形状：mongodb 凭据族 + defaultDatabase=认证库 + extra 四键。
      final draft = client.requests.firstWhere(
        (r) => r.url.path == '/api/gw/connections/test',
      );
      final draftBody = _sentBody(draft);
      expect(draftBody['dbType'], 'mongodb');
      expect(draftBody['host'], '192.0.2.128');
      expect(draftBody['port'], 27017);
      expect(draftBody['username'], 'admin');
      expect(draftBody['password'], 'pw');
      expect(draftBody['defaultDatabase'], 'admin');
      expect(draftBody['extra'], {'mongoConnectionMode': 'direct'});

      // 注册体 = 草稿 + name/readOnly。
      final register = client.requests.firstWhere(
        (r) => r.method == 'POST' && r.url.path == '/api/gw/connections',
      );
      final body = _sentBody(register);
      expect(body['name'], 'Mongo Live');
      expect(body['readOnly'], false);

      // 映射写回。
      final prefs = await SharedPreferences.getInstance();
      final map = jsonDecode(prefs.getString('connection_server_id_map')!);
      expect(map['local_mongo_1'], 'srv-1');
    });

    test('映射有效 → 复用不重注册', () async {
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_mongo_1': 'srv-9'}),
      });
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-9'});
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'unmapped'},
        }, 500);
      });
      final adapter = MongoDBAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(
        client.requests.where(
          (r) => r.method == 'POST' && r.url.path.contains('connections'),
        ),
        isEmpty,
        reason: 'mapped id must be reused without re-register/test',
      );
    });

    test('映射 dbType 不匹配 → 重注册', () async {
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_mongo_1': 'srv-other'}),
      });
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          // 注册行类型是 mysql——不匹配，必须重注册。
          return _jsonResp([
            {'id': 'srv-other', 'dbType': 'mysql'},
          ], 200);
        }
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'POST') {
          return _jsonResp({'serverConnId': 'srv-2'}, 200);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = MongoDBAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(
        client.requests.any(
          (r) => r.method == 'POST' && r.url.path == '/api/gw/connections',
        ),
        isTrue,
      );
    });

    test('凭据 test 失败（error 非对象）→ AdapterConnectException 兜底且不注册', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': false, 'error': 'auth failed'}, 200);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = MongoDBAdapter()..httpClient = client;
      // 连接失败 UX 重构 T9b：失败不再吞掉（原 return false）。error 为
      // 字符串（非对象）→ unknown 兜底（errorCode 空），message 保留原文。
      await expectLater(
        adapter.connect(_conn()),
        throwsA(
          isA<AdapterConnectException>()
              .having(
                (e) => e.failure.kind,
                'kind',
                ConnectionFailureKind.unknown,
              )
              .having((e) => e.failure.errorCode, 'errorCode', '')
              .having(
                (e) => e.failure.rawMessage,
                'rawMessage',
                contains('auth failed'),
              ),
        ),
      );
      expect(adapter.isConnected, isFalse);
      expect(
        client.requests.any(
          (r) => r.method == 'POST' && r.url.path == '/api/gw/connections',
        ),
        isFalse,
      );
    });

    test(
      '凭据 test 失败（envelope ok:false code/message）→ AdapterConnectException 且不注册',
      () async {
        final client = _RecordingClient((req) {
          if (req.url.path == '/api/gw/connections/test') {
            return _jsonResp({
              'ok': false,
              'error': {
                'code': 'DB_ERROR',
                'message': 'Authentication failed (engine code: Unauthorized)',
              },
            }, 200);
          }
          return _jsonResp({
            'error': {'code': 'X', 'message': 'x'},
          }, 500);
        });
        final adapter = MongoDBAdapter()..httpClient = client;
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
                  contains('Authentication failed'),
                )
                .having((e) => e.failure.target, 'target', '192.0.2.128:27017'),
          ),
        );
        expect(
          client.requests.any(
            (r) => r.method == 'POST' && r.url.path == '/api/gw/connections',
          ),
          isFalse,
        );
        expect(adapter.isConnected, isFalse);
      },
    );

    test(
      'T12s wire：error_code=AUTH_DENIED → AdapterConnectException kind=authFailed',
      () async {
        // T12c：server 草稿 test 失败响应加性新增顶层 `error_code`（snake_case），
        // error 字符串字段原样保留 → kind 分型 authFailed、errorCode 非空。
        final client = _RecordingClient((req) {
          if (req.url.path == '/api/gw/connections/test') {
            return _jsonResp({
              'ok': false,
              'error': 'Authentication failed',
              'error_code': 'AUTH_DENIED',
              'elapsedMs': 12,
            }, 200);
          }
          return _jsonResp({
            'error': {'code': 'X', 'message': 'x'},
          }, 500);
        });
        final adapter = MongoDBAdapter()..httpClient = client;
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
                  contains('Authentication failed'),
                )
                .having((e) => e.failure.target, 'target', '192.0.2.128:27017'),
          ),
        );
        expect(
          client.requests.any(
            (r) => r.method == 'POST' && r.url.path == '/api/gw/connections',
          ),
          isFalse,
        );
        expect(adapter.isConnected, isFalse);
      },
    );

    test('集群 extra 四键透传 + 空凭据省略', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': true}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'POST') {
          return _jsonResp({'serverConnId': 'srv-1'}, 200);
        }
        return _listResponse({});
      });
      final adapter = MongoDBAdapter()..httpClient = client;
      final conn = _conn(
        extra: {
          'mongoConnectionMode': 'replicaSet',
          'mongoHosts': ['h1:27017', 'h2:27017'],
          'mongoReplicaSet': 'rs0',
          // 非 mongo 键不透传。
          'useSSL': true,
          'timeout': 10,
        },
      );
      // 无凭据连接（无认证实例合法）。
      final credsFree = DatabaseConnection(
        id: conn.id,
        name: conn.name,
        type: conn.type,
        host: conn.host,
        port: conn.port,
        database: conn.database,
        extra: conn.extra,
      );
      await adapter.connect(credsFree);

      final draft = client.requests.firstWhere(
        (r) => r.url.path == '/api/gw/connections/test',
      );
      final draftBody = _sentBody(draft);
      expect(draftBody['extra'], {
        'mongoConnectionMode': 'replicaSet',
        'mongoHosts': ['h1:27017', 'h2:27017'],
        'mongoReplicaSet': 'rs0',
      });
      expect(draftBody.containsKey('username'), isFalse);
      expect(draftBody.containsKey('password'), isFalse);
      expect(draftBody.containsKey('mongoConnectionString'), isFalse);
    });
  });

  group('executeQuery：runCommand 通道', () {
    test('find：文档行展开 + 扩展 JSON 解包（\$oid → hex 串）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(
            _cursorEvents([
              {
                '_id': {'\$oid': '010101010101010101010101'},
                'name': 'alice',
                'when': {'\$date': '2026-01-01T00:00:00.000Z'},
              },
              {
                '_id': {'\$oid': '020202020202020202020202'},
                'name': 'bob',
              },
            ]),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);

      final result = await adapter.executeQuery('db.users.find()');
      expect(result.rows.length, 2);
      expect(result.rows[0]['_id'], '010101010101010101010101');
      expect(result.rows[0]['name'], 'alice');
      expect(result.rows[0]['when'], '2026-01-01T00:00:00.000Z');
      expect(result.affectedRows, 2);

      // 命令形状：find + limit 默认 100 + database 路由（_currentDatabase
      // 缺省 = 连接 database 字段）。
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['kind'], 'mongo');
      expect(cmd['command'], {'find': 'users', 'filter': {}, 'limit': 100});
      expect(cmd['database'], 'admin');
    });

    test('findOne 空结果 → 引导行；多批 rows 聚合', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          // 首查空、次查两批。
          final body = _sentBody(req);
          final limit = (body['command'] as Map)['limit'];
          if (limit == 1) {
            return _sse(_cursorEvents([]));
          }
          return _sse([
            'event: meta\ndata: {"kind":"mongo","type":"meta","columns":["doc"]}',
            'event: rows\ndata: {"kind":"mongo","type":"rows","rows":[[{"n": 1}]]}',
            'event: rows\ndata: {"kind":"mongo","type":"rows","rows":[[{"n": 2}]]}',
            'event: complete\ndata: {"kind":"mongo","type":"complete","rowCount":2,"truncated":false,"elapsedMs":6}',
          ]);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);

      final one = await adapter.executeQuery('db.users.findOne({})');
      expect(one.rows, [
        {'result': '查询成功，无匹配文档'},
      ]);

      final many = await adapter.executeQuery('db.users.find({}).sort({n: 1})');
      expect(many.rows.length, 2);
      // sort 下传命令。
      final cmd = _sentBody(
        client.requests.lastWhere((r) => r.url.path.endsWith('/query')),
      );
      expect((cmd['command'] as Map)['sort'], {'n': 1});
    });

    test('count / distinct：单 result 文档映射', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final cmd = (_sentBody(req)['command'] as Map)
              .cast<String, dynamic>();
          if (cmd.containsKey('count')) {
            return _sse(_resultEvents({'n': 7, 'ok': 1}));
          }
          return _sse(
            _resultEvents({
              'values': ['a', 'b'],
              'ok': 1,
            }),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);

      final count = await adapter.executeQuery(
        'db.users.countDocuments({x: 1})',
      );
      expect(count.rows, [
        {'count': 7},
      ]);
      final countCmd = _sentBody(
        client.requests.where((r) => r.url.path.endsWith('/query')).first,
      );
      expect(countCmd['command'], {
        'count': 'users',
        'query': {'x': 1},
      });

      final distinct = await adapter.executeQuery('db.users.distinct("city")');
      expect(distinct.rows, [
        {'city': 'a'},
        {'city': 'b'},
      ]);
      final distinctCmd = _sentBody(
        client.requests.lastWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(distinctCmd['command'], {'distinct': 'users', 'key': 'city'});
    });

    test('aggregate → aggregate 命令 + cursor:{}', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(
            _cursorEvents([
              {'_id': 'a', 'total': 3},
            ]),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);

      final result = await adapter.executeQuery(
        r'db.orders.aggregate([{"$group": {"_id": "$name", "total": {"$sum": "$n"}}}])',
      );
      expect(result.rows, [
        {'_id': 'a', 'total': 3},
      ]);
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['command']['aggregate'], 'orders');
      expect(cmd['command']['cursor'], {});
      expect(cmd['command']['pipeline'], isA<List<dynamic>>());
    });

    test('SELECT 1（keep-alive）→ ping 到 admin', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_resultEvents({'ok': 1}));
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);

      final result = await adapter.executeQuery('SELECT 1');
      expect(result.rows[0]['result'], {'ok': 1});
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['command'], {'ping': 1});
      expect(cmd['database'], 'admin');
    });

    test('无法解析 → 引导信息行（不抛）', () async {
      final adapter = await _connectedAdapter(_noQueryClient());
      final result = await adapter.executeQuery('SELECT * FROM users');
      expect(result.rows.first['result'], contains('JSON 格式查询'));
    });

    test('请求形状：X-Execution-Id 头 + timeoutMs 透传', () async {
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_mongo_1': 'srv-1'}),
      });
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_cursorEvents([]));
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = MongoDBAdapter()..httpClient = client;
      await adapter.connect(_conn(timeoutSecs: 45));
      await adapter.executeQuery('db.users.find()');

      final req = client.requests.firstWhere(
        (r) => r.url.path.endsWith('/query'),
      );
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(req.headers['X-Execution-Id'] ?? ''),
        isTrue,
      );
      final body = _sentBody(req);
      expect(body['timeoutMs'], 45000);
      expect(body['rowLimit'], 100);
      expect(body['kind'], 'mongo');
    });

    test('SSE error 事件 → 包装上抛（MongoDB 查询执行失败 + engineCode）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse([
            'event: error\ndata: {"kind":"mongo","type":"error","code":"DB_ERROR","message":"ns not found","engineCode":"NamespaceNotFound"}',
          ]);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      await expectLater(
        adapter.executeQuery('db.users.find()'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('MongoDB 查询执行失败'), contains('NamespaceNotFound')),
          ),
        ),
      );
    });
  });

  group('连接级错误与断连语义', () {
    test('CONNECTION_FAILED → onDisconnect；命令错误不撕连接', () async {
      var failWith = 'DB_ERROR';
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse([
            'event: error\ndata: {"kind":"mongo","type":"error","code":"$failWith","message":"x"}',
          ]);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      var disconnected = 0;
      adapter.onDisconnect = () => disconnected++;

      // 命令错误（DB_ERROR）不撕连接。
      await expectLater(adapter.getTables(), completion(isEmpty));
      expect(disconnected, 0);

      failWith = 'CONNECTION_FAILED';
      await expectLater(
        adapter.executeQuery('db.users.find()'),
        throwsException,
      );
      expect(disconnected, 1);
    });

    test('无 server 会话 → 引导性 StateError', () async {
      ServerConnection.resetForTesting();
      final adapter = MongoDBAdapter();
      await expectLater(adapter.connect(_conn()), throwsA(isA<StateError>()));
    });

    test('disconnect → 清空连接态 + best-effort 取消在途', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          // 不返回（模拟在途）——断言用请求记录即可。
          return _sse(_cursorEvents([]));
        }
        if (req.method == 'DELETE' && req.url.path.contains('/executions/')) {
          return _jsonResp({}, 204);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      expect(adapter.isConnected, isTrue);
      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
    });
  });

  group('元数据方法', () {
    test('getTables：listCollections + system.* 过滤 + 排序', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(
            _cursorEvents([
              {'name': 'users'},
              {'name': 'system.views'},
              {'name': 'audit'},
            ]),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      expect(await adapter.getTables(), ['audit', 'users']);
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['command'], {'listCollections': 1});
    });

    // ========================================================================
    // 批2.6-C1 红测：getTables 库限定路由（DatabaseQualifiedTablesAdapter）。
    // 契约：database 非空 → listCollections 经 _cursorDocs(database:)
    // 落目标库；无参 = 现行为逐字节不变。
    // ========================================================================
    group('getTables 库限定路由（批2.6-C1）', () {
      test('应实现 DatabaseQualifiedTablesAdapter（服务层门拾取前置）', () async {
        final adapter = await _connectedAdapter(_noQueryClient());
        expect(adapter, isA<DatabaseQualifiedTablesAdapter>());
      });

      test('database 非空 → listCollections 落 target_db', () async {
        final client = _RecordingClient((req) {
          if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
            return _listResponse({'srv-1'});
          }
          if (req.url.path.endsWith('/query')) {
            return _sse(_cursorEvents([
              {'name': 'orders'},
              {'name': 'users'},
            ]));
          }
          return _jsonResp({
            'error': {'code': 'X', 'message': 'x'},
          }, 500);
        });
        final adapter = await _connectedAdapter(client);

        final tables =
            await (adapter as DatabaseQualifiedTablesAdapter).getTables(
          database: 'target_db',
        );
        expect(tables, ['orders', 'users']);
        final cmd = _sentBody(
          client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
        );
        expect(cmd['command'], {'listCollections': 1});
        expect(cmd['database'], 'target_db');
      });

      test('回归锁：无参 → listCollections 落连接当前库 admin（排序不变）', () async {
        final client = _RecordingClient((req) {
          if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
            return _listResponse({'srv-1'});
          }
          if (req.url.path.endsWith('/query')) {
            return _sse(_cursorEvents([
              {'name': 'users'},
              {'name': 'audit'},
            ]));
          }
          return _jsonResp({
            'error': {'code': 'X', 'message': 'x'},
          }, 500);
        });
        final adapter = await _connectedAdapter(client);

        expect(await adapter.getTables(), ['audit', 'users']);
        final cmd = _sentBody(
          client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
        );
        expect(cmd['database'], 'admin');
      });
    });

    test('getTableColumns：采样 + _id 主键 + 扩展类型名', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(
            _cursorEvents([
              {
                '_id': {'\$oid': 'aaaa'},
                'name': 'x',
                'age': 3,
                'when': {'\$date': '2026-01-01T00:00:00.000Z'},
                'tags': [1],
              },
            ]),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      final cols = await adapter.getTableColumns('users');
      final types = {for (final c in cols) c.name: c.type};
      expect(types['_id'], 'ObjectId');
      expect(types['name'], 'String');
      expect(types['age'], 'Number');
      expect(types['when'], 'Date');
      expect(types['tags'], 'Array');
      expect(cols.first.isPrimaryKey, isTrue);
    });

    test('getTableIndexes：listIndexes 映射', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(
            _cursorEvents([
              {
                'name': '_id_',
                'key': {'_id': 1},
              },
              {
                'name': 'uq_name',
                'key': {'name': 1},
                'unique': true,
              },
            ]),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      final indexes = await adapter.getTableIndexes('users');
      expect(indexes.length, 2);
      expect(indexes[1].name, 'uq_name');
      expect(indexes[1].isUnique, isTrue);
      expect(indexes[1].columns, ['name']);
    });

    test('useDatabase record-only → 命令 database 路由切换', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_cursorEvents([]));
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      await adapter.useDatabase('sales');
      await adapter.getTables();
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['database'], 'sales');
    });

    test('dropDatabase → 命令路由目标库 + 当前库回落认证库', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse([_completeEvent(1)]);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      await adapter.useDatabase('sales');
      expect(await adapter.dropDatabase('sales'), isTrue);
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['command'], {'dropDatabase': 1});
      expect(cmd['database'], 'sales');
      // 后续命令回落认证库（admin）。
      await adapter.getTables();
      final next = _sentBody(
        client.requests.lastWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(next['database'], 'admin');
    });

    test('renameTable → renameCollection 走 admin', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse([_completeEvent(1)]);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      expect(await adapter.renameTable('a', 'b'), isTrue);
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['command']['renameCollection'], 'admin.a');
      expect(cmd['command']['to'], 'admin.b');
      expect(cmd['database'], 'admin');
    });
  });

  group('Mongo 特有操作面', () {
    test('insertOne / updateOne / deleteMany：命令形状 + n 语义', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final body = _sentBody(req);
          final cmd = body['command'] as Map;
          if (cmd.containsKey('insert')) {
            return _sse([_completeEvent(1)]);
          }
          if (cmd.containsKey('update')) {
            return _sse([_completeEvent(0)]);
          }
          return _sse([_completeEvent(3)]);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);

      expect(await adapter.insertOne('users', {'name': 'x'}), isTrue);
      var cmd = _sentBody(
        client.requests
            .where((r) => r.url.path.endsWith('/query'))
            .elementAt(0),
      );
      expect(cmd['command']['insert'], 'users');
      expect(cmd['command']['documents'], [
        {'name': 'x'},
      ]);

      // update 命令：affectedRows 是响应 n（含未修改匹配）；updateOne 返回
      // nModified。
      expect(
        await adapter.updateOne(
          'users',
          {'a': 1},
          {
            r'$set': {'b': 2},
          },
        ),
        0,
      );
      cmd = _sentBody(
        client.requests
            .where((r) => r.url.path.endsWith('/query'))
            .elementAt(1),
      );
      expect(cmd['command']['update'], 'users');
      expect(cmd['command']['updates'], [
        {
          'q': {'a': 1},
          'u': {
            r'$set': {'b': 2},
          },
          'multi': false,
        },
      ]);

      expect(await adapter.deleteMany('users', {}), 3);
      cmd = _sentBody(
        client.requests
            .where((r) => r.url.path.endsWith('/query'))
            .elementAt(2),
      );
      expect(cmd['command']['delete'], 'users');
      expect(cmd['command']['deletes'], [
        {'q': {}, 'limit': 0},
      ]);
    });

    test('getReplicaSetStatus：admin 路由 + members 映射；错误 → null', () async {
      var fail = false;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          if (fail) {
            return _sse([
              'event: error\ndata: {"kind":"mongo","type":"error","code":"DB_ERROR","message":"not replset"}',
            ]);
          }
          return _sse(
            _resultEvents({
              'ok': 1.0,
              'set': 'rs0',
              'myState': 1,
              'members': [
                {
                  'name': 'h1:27017',
                  'stateStr': 'PRIMARY',
                  'state': 1,
                  'health': 1,
                  'uptime': 99,
                },
              ],
            }),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);

      final status = await adapter.getReplicaSetStatus();
      expect(status!['setName'], 'rs0');
      expect(status['members'].length, 1);
      expect((status['members'] as List).first['state'], 'PRIMARY');
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['command'], {'replSetGetStatus': 1});
      expect(cmd['database'], 'admin');

      fail = true;
      expect(await adapter.getReplicaSetStatus(), isNull);
    });

    test('inferDocumentSchema：occurrence/Mixed + 原始形态类型识别', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(
            _cursorEvents([
              {
                '_id': {'\$oid': 'x'},
                'name': 'a',
                'score': 1,
              },
              {
                '_id': {'\$oid': 'y'},
                'name': 'b',
                'score': 2,
              },
              {
                '_id': {'\$oid': 'z'},
                'name': 'c',
                'score': 'oops',
              },
            ]),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      final schema = await adapter.inferDocumentSchema('users', sampleSize: 3);
      expect(schema['totalSampled'], 3);
      final fields = schema['fields'] as Map<String, dynamic>;
      expect((fields['name'] as Map)['occurrence'], 3);
      expect((fields['name'] as Map)['type'], 'String');
      // score: 两个 Number + 一个 String → Mixed。
      expect((fields['score'] as Map)['type'], 'Mixed');
      expect((fields['_id'] as Map)['type'], 'ObjectId');
      // find limit = sampleSize。
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['command']['limit'], 3);
    });

    test('getCollectionStats：collStats 映射', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(
            _resultEvents({
              'ns': 'test.users',
              'count': 42,
              'storageSize': 4096,
              'size': 2048,
              'nindexes': 2,
              'totalIndexSize': 8192,
              'capped': false,
              'ok': 1.0,
            }),
          );
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client);
      final stats = await adapter.getCollectionStats('users');
      expect(stats['documentCount'], 42);
      expect(stats['indexCount'], 2);
      expect(stats['isCapped'], isFalse);
      final cmd = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(cmd['command'], {'collStats': 'users'});
    });
  });

  group('只读守卫', () {
    test('readOnly + 写命令 JSON → ReadOnlyBlockedException', () async {
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_mongo_1': 'srv-1'}),
      });
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = MongoDBAdapter()..httpClient = client;
      await adapter.connect(_conn(readOnly: true));
      await expectLater(
        adapter.executeQuery('{"insert": "users", "documents": [{"a": 1}]}'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
    });
  });

  group('DBT-T21 · GridFS 上传写面', () {
    const fixedOid = '65f1a2b3c4d5e6f7081921aa';
    const chunkSize = MongoDBAdapter.kGridFsUploadChunkSize;

    /// 按 insert 目标集合回放（affectedRows = n；可指定失败集合与错误）。
    _RecordingClient _uploadClient({
      Set<String> failInserts = const {},
      bool failDelete = false,
      bool failFilesInsert = false,
    }) => _RecordingClient((req) {
      if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
        return _listResponse({'srv-1'});
      }
      if (req.url.path.endsWith('/query')) {
        final cmd = (_sentBody(req)['command'] as Map);
        final target =
            cmd['insert']?.toString() ??
            (cmd.containsKey('delete') ? 'delete:${cmd['delete']}' : '?');
        if (cmd.containsKey('delete')) {
          return failDelete
              ? _sse([
                  'event: error\ndata: {"kind":"mongo","type":"error","code":"DB_ERROR","message":"delete denied"}',
                ])
              : _sse([_completeEvent(0)]);
        }
        if (failInserts.contains(target) ||
            (failFilesInsert && target.endsWith('.files'))) {
          return _sse([
            'event: error\ndata: {"kind":"mongo","type":"error","code":"DB_ERROR","message":"E11000 duplicate key"}',
          ]);
        }
        final docs = (cmd['documents'] as List).length;
        return _sse([_completeEvent(docs)]);
      }
      return _jsonResp({
        'error': {'code': 'X', 'message': 'x'},
      }, 500);
    });

    List<Map<String, dynamic>> _queryBodies(_RecordingClient client) => [
      for (final r in client.requests.where(
        (r) => r.url.path.endsWith('/query'),
      ))
        _sentBody(r)['command'] as Map<String, dynamic>,
    ];

    test(
      'chunk 组装：\$binary base64/n 序/files_id 一致 + files 收尾 + 返回 hex',
      () async {
        final client = _uploadClient();
        final adapter = await _connectedAdapter(client)
          ..gridFsFilesIdFactory = () => fixedOid;
        final bytes = [1, 2, 3, 4, 5];

        final hex = await adapter.uploadGridFsFile(
          'media',
          database: 'db1',
          filename: 'hello.bin',
          bytes: bytes,
          contentType: 'application/octet-stream',
        );

        expect(hex, fixedOid);
        final cmds = _queryBodies(client);
        expect(cmds.length, 2, reason: '一批 chunks + files 收尾');

        // chunk 文档：files_id $oid 一致 + n=0 + $binary base64 逐字节。
        expect(cmds[0]['insert'], 'media.chunks');
        final chunk = (cmds[0]['documents'] as List).single as Map;
        expect(chunk['files_id'], {r'$oid': fixedOid});
        expect(chunk['n'], 0);
        expect(chunk['data'][r'$binary']['base64'], base64Encode(bytes));
        expect(chunk['data'][r'$binary']['subType'], '00');

        // files 文档：_id/length/chunkSize/uploadDate($date)/filename/contentType。
        expect(cmds[1]['insert'], 'media.files');
        final files = (cmds[1]['documents'] as List).single as Map;
        expect(files['_id'], {r'$oid': fixedOid});
        expect(files['length'], 5);
        expect(files['chunkSize'], chunkSize);
        expect(
          (files['uploadDate'] as Map).containsKey(r'$date'),
          isTrue,
          reason: 'DateTime 经 _prepareForWire 预编码为 \$date',
        );
        expect(files['filename'], 'hello.bin');
        expect(files['contentType'], 'application/octet-stream');

        // database 路由。
        final bodies = [
          for (final r in client.requests.where(
            (r) => r.url.path.endsWith('/query'),
          ))
            _sentBody(r),
        ];
        expect(bodies.every((b) => b['database'] == 'db1'), isTrue);
      },
    );

    test('分批边界（字节预算）：6 chunks → 两批 [5,1]，n 跨批连续', () async {
      final client = _uploadClient();
      final adapter = await _connectedAdapter(client)
        ..gridFsFilesIdFactory = () => fixedOid;
      // 6×chunkSize 字节 → 6 个满片；5 个满片 JSON ≈ 1.74MB < 1.9MB 预算，
      // 第 6 个满片（累计 ≈ 2.09MB）触发分批 → [5,1]。
      final bytes = Uint8List(6 * chunkSize);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = i & 0xFF;
      }

      final hex = await adapter.uploadGridFsFile(
        'media',
        filename: 'big.bin',
        bytes: bytes,
      );
      expect(hex, fixedOid);

      final cmds = _queryBodies(client);
      final chunkCmds = cmds
          .where((c) => c['insert'] == 'media.chunks')
          .toList();
      expect(chunkCmds.length, 2, reason: '字节预算分批：[5,1]');
      expect((chunkCmds[0]['documents'] as List).length, 5);
      expect((chunkCmds[1]['documents'] as List).length, 1);
      // n 序跨批连续且 base64 与源切片一致（抽验首片与末片）。
      final firstBatch = (chunkCmds[0]['documents'] as List).cast<Map>();
      final lastBatch = (chunkCmds[1]['documents'] as List).cast<Map>();
      expect([for (final d in firstBatch) d['n']], [0, 1, 2, 3, 4]);
      expect(lastBatch.single['n'], 5);
      expect(
        firstBatch.first['data'][r'$binary']['base64'],
        base64Encode(bytes.sublist(0, chunkSize)),
      );
      expect(
        lastBatch.single['data'][r'$binary']['base64'],
        base64Encode(bytes.sublist(5 * chunkSize)),
      );
      // files 收尾在最后。
      expect(cmds.last['insert'], 'media.files');
    });

    test('groupGridFsChunkDocsIntoBatches：docs 数上限 100（字节预算恒先绑定的保险位）', () {
      // 微型 docs（jsonEncode ~110B）→ 101 docs 仍 < 1.9MB 预算 → 数量上限
      // 绑定：[100, 1]。
      Map<String, dynamic> tiny(int n) => {
        'files_id': {r'$oid': fixedOid},
        'n': n,
        'data': {
          r'$binary': {
            'base64': base64Encode([n & 0xFF]),
            'subType': '00',
          },
        },
      };
      final batches = MongoDBAdapter.groupGridFsChunkDocsIntoBatches([
        for (var i = 0; i < 101; i++) tiny(i),
      ]);
      expect(batches.length, 2);
      expect(batches[0].length, 100);
      expect(batches[1].length, 1);
      expect(MongoDBAdapter.groupGridFsChunkDocsIntoBatches(const []), isEmpty);
    });

    test('失败回滚：批 2 失败 → delete 本 files_id 全部 chunks；files 恒不写', () async {
      // 时序回放：批 1 chunks 成功 → 批 2 chunks E11000 → delete 回滚。
      var chunksInsertCount = 0;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final cmd = (_sentBody(req)['command'] as Map);
          if (cmd.containsKey('delete')) return _sse([_completeEvent(0)]);
          final target = cmd['insert'].toString();
          final docs = (cmd['documents'] as List).length;
          if (target == 'media.chunks') {
            chunksInsertCount++;
            if (chunksInsertCount == 2) {
              return _sse([
                'event: error\ndata: {"kind":"mongo","type":"error","code":"DB_ERROR","message":"E11000 duplicate key"}',
              ]);
            }
          }
          return _sse([_completeEvent(docs)]);
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = await _connectedAdapter(client)
        ..gridFsFilesIdFactory = () => fixedOid;
      final bytes = Uint8List(6 * chunkSize);

      await expectLater(
        adapter.uploadGridFsFile('media', filename: 'boom.bin', bytes: bytes),
        throwsA(
          isA<MongoGridFsUploadException>().having(
            (e) => e.rollbackComplete,
            'rollbackComplete',
            isTrue,
          ),
        ),
      );

      final cmds = _queryBodies(client);
      // 序列：批 1 insert（成功）→ 批 2 insert（E11000）→ delete 回滚；无 files insert。
      expect(cmds[0]['insert'], 'media.chunks');
      expect(cmds[1]['insert'], 'media.chunks');
      expect(cmds[2].containsKey('delete'), isTrue);
      expect(cmds[2]['delete'], 'media.chunks');
      expect(cmds[2]['deletes'], [
        {
          'q': {
            'files_id': {r'$oid': fixedOid},
          },
          'limit': 0,
        },
      ]);
      expect(
        cmds.any((c) => c['insert'] == 'media.files'),
        isFalse,
        reason: 'files 恒不写（零孤儿 files）',
      );
      expect(cmds.length, 3);
    });

    test('回滚失败 → rollbackComplete=false（孤儿 chunks 风险标记）', () async {
      final client = _uploadClient(
        failInserts: {'media.chunks'},
        failDelete: true,
      );
      final adapter = await _connectedAdapter(client)
        ..gridFsFilesIdFactory = () => fixedOid;

      await expectLater(
        adapter.uploadGridFsFile('media', filename: 'boom.bin', bytes: [1, 2]),
        throwsA(
          isA<MongoGridFsUploadException>().having(
            (e) => e.rollbackComplete,
            'rollbackComplete',
            isFalse,
          ),
        ),
      );
    });

    test('files 收尾失败 → 回滚 chunks + 上抛', () async {
      final client = _uploadClient(failFilesInsert: true);
      final adapter = await _connectedAdapter(client)
        ..gridFsFilesIdFactory = () => fixedOid;

      await expectLater(
        adapter.uploadGridFsFile('media', filename: 'no-files.bin', bytes: [9]),
        throwsA(isA<MongoGridFsUploadException>()),
      );
      final cmds = _queryBodies(client);
      expect(cmds[0]['insert'], 'media.chunks');
      expect(cmds[1]['insert'], 'media.files', reason: 'files 尝试过但失败');
      expect(cmds[2]['delete'], 'media.chunks', reason: '回滚已插 chunks');
    });

    test('空文件（0 字节）：0 chunks + files 行直插（GridFS 规范兼容）', () async {
      final client = _uploadClient();
      final adapter = await _connectedAdapter(client)
        ..gridFsFilesIdFactory = () => fixedOid;

      final hex = await adapter.uploadGridFsFile(
        'media',
        filename: 'empty.bin',
        bytes: const [],
      );
      expect(hex, fixedOid);
      final cmds = _queryBodies(client);
      expect(cmds.length, 1, reason: '仅 files 一条（无 chunks）');
      final files = (cmds[0]['documents'] as List).single as Map;
      expect(files['length'], 0);
    });

    test('超 50 MB 上限 → ArgumentError，零 /query 请求', () async {
      final client = _uploadClient();
      final adapter = await _connectedAdapter(client);
      final huge = Uint8List(MongoDBAdapter.kGridFsUploadMaxBytes + 1);

      await expectLater(
        adapter.uploadGridFsFile('media', filename: 'huge.bin', bytes: huge),
        throwsArgumentError,
      );
      expect(
        client.requests.where((r) => r.url.path.endsWith('/query')),
        isEmpty,
      );
    });

    test('guardReadOnly：readOnly 连接 → ReadOnlyBlockedException（零请求）', () async {
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_mongo_1': 'srv-1'}),
      });
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        return _jsonResp({
          'error': {'code': 'X', 'message': 'x'},
        }, 500);
      });
      final adapter = MongoDBAdapter()..httpClient = client;
      await adapter.connect(_conn(readOnly: true));

      await expectLater(
        adapter.uploadGridFsFile('media', filename: 'x.bin', bytes: [1]),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
      expect(
        client.requests.where((r) => r.url.path.endsWith('/query')),
        isEmpty,
      );
    });
  });
}

// ── 公共 helper ──

/// 已连接 adapter（预置 local → srv-1 映射，connect 走复用路径，
/// 单测焦点保持在 /query 端点）。
Future<MongoDBAdapter> _connectedAdapter(_RecordingClient client) async {
  SharedPreferences.setMockInitialValues({
    'connection_server_id_map': jsonEncode({'local_mongo_1': 'srv-1'}),
  });
  final adapter = MongoDBAdapter()..httpClient = client;
  final ok = await adapter.connect(_conn());
  expect(ok, isTrue, reason: 'fixture adapter must connect');
  return adapter;
}

/// 查询端点直接 500 的回放（无 server 交互断言用）。
_RecordingClient _noQueryClient() => _RecordingClient((req) {
  if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
    return _listResponse({'srv-1'});
  }
  return _jsonResp({
    'error': {'code': 'X', 'message': 'unreachable'},
  }, 500);
  // 网关 TLS 透传 + server 侧 SSH 隧道：draft/test body 形状（TLS 两键
  // 与集群四模式键合并同一段 extra）。
  group('draft body：TLS 透传 + server 侧 SSH 隧道', () {
    final sshWire = {
      'host': 'jump.example.com',
      'port': 22,
      'username': 'deploy',
      'authMode': 'password',
      'password': 'hunter2',
    };

    test('useTls 开启 → extra 含 TLS 两键（与集群键合并）；ssh 透传', () async {
      final client = _freshConnectClient();
      final adapter = MongoDBAdapter()..httpClient = client;
      await adapter.testConnection(
        DatabaseConnection(
          id: 'local_mongo_1',
          name: 'Mongo Live',
          type: DatabaseType.mongodb,
          host: '192.0.2.128',
          port: 27017,
          username: 'admin',
          password: 'pw',
          database: 'admin',
          extra: {
            'mongoConnectionMode': 'replicaSet',
            'useTls': true,
            'tlsInsecure': true,
            'ssh': sshWire,
          },
        ),
      );

      final body = _sentBody(
        client.requests.firstWhere(
          (r) => r.url.path == '/api/gw/connections/test',
        ),
      );
      expect(body['extra'], {
        'mongoConnectionMode': 'replicaSet',
        'useTls': true,
        'tlsInsecure': true,
      });
      expect(body['ssh'], sshWire);
    });

    test('useTls 关闭 / 无 ssh → 不带 TLS 键与 ssh 键', () async {
      final client = _freshConnectClient();
      final adapter = MongoDBAdapter()..httpClient = client;
      await adapter.testConnection(
        DatabaseConnection(
          id: 'local_mongo_1',
          name: 'Mongo Live',
          type: DatabaseType.mongodb,
          host: '192.0.2.128',
          port: 27017,
          username: 'admin',
          password: 'pw',
          database: 'admin',
          extra: {
            'mongoConnectionMode': 'direct',
            'useTls': false,
            'tlsInsecure': true,
          },
        ),
      );

      final body = _sentBody(
        client.requests.firstWhere(
          (r) => r.url.path == '/api/gw/connections/test',
        ),
      );
      expect(body['extra'], {'mongoConnectionMode': 'direct'});
      expect(body.containsKey('ssh'), isFalse);
    });
  });
});
