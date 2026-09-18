// =============================================================================
// T29 非 SQL 批次（B4）· Redis 网关壳 adapter 单元测试。
// =============================================================================
// Mock HTTP 层 + ServerConnection 单例（embedded 握手注入），验证：
// - connect：serverConnId 映射复用 / 草稿 test → 现场注册写回 / 失效重注册 /
//   test 失败返 false / 凭据可选（auth 三态由存在性推导）；
// - 命令通道（kind:"redis"）：**旧 RESP 形状重建**（fallback 单列整值 /
//   SCAN 族 [cursor,[items]] / 成对列平铺 / 单列数组）——getHash/getSet/
//   _parseScanResult 等类型化方法按旧形状消费；请求形状（X-Execution-Id /
//   database=db 路由 / timeoutMs）；SSE error 包装上抛（engineCode）；
// - pipeline：[index, result] 按序归位；multiExec 走 atomic:true；
//   watch/unwatch/discardTx fail-loud；
// - 只读守卫（validateCommand 本地黑名单）+ 断连回调 + Pub/Sub 重订式
//  （订阅目标集 → SSE 重建 → message → PubSubMessage）。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
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

/// fallback 单列的 SSE 三事件（整值 JSON 单元格）。
List<String> _resultEvents(dynamic value) => [
  'event: meta\ndata: {"kind":"redis","type":"meta","columns":["result"]}',
  'event: rows\ndata: {"kind":"redis","type":"rows","rows":${jsonEncode([[value]])}}',
  'event: complete\ndata: {"kind":"redis","type":"complete","rowCount":1,"truncated":false,"elapsedMs":3}',
];

/// 语义列（N 列）SSE 三事件。
List<String> _semanticEvents(
  List<String> cols,
  List<List<dynamic>> rows,
) => [
  'event: meta\ndata: {"kind":"redis","type":"meta","columns":${jsonEncode(cols)}}',
  if (rows.isNotEmpty)
    'event: rows\ndata: {"kind":"redis","type":"rows","rows":${jsonEncode(rows)}}',
  'event: complete\ndata: {"kind":"redis","type":"complete","rowCount":${rows.length},"truncated":false,"elapsedMs":3}',
];

DatabaseConnection _conn({
  bool readOnly = false,
  int? timeoutSecs,
  String database = 'db0',
}) =>
    DatabaseConnection(
      id: 'local_redis_1',
      name: 'Redis Live',
      type: DatabaseType.redis,
      host: '192.0.2.128',
      port: 6379,
      username: 'default',
      password: 'pw',
      database: database,
      readOnly: readOnly,
      extra: timeoutSecs == null ? null : {'timeout': timeoutSecs},
    );

http.StreamedResponse _listResponse(Set<String> ids) =>
    _jsonResp([for (final id in ids) {'id': id, 'dbType': 'redis'}], 200);

/// server pipeline 模式每命令一行 [index, result]（原始 RESP→JSON）。
List<String> _pipelineEvents(List<dynamic> results) => _semanticEvents(
      ['index', 'result'],
      [
        for (var i = 0; i < results.length; i++) [i, results[i]],
      ],
    );

bool _isPipeline(http.Request req) => _sentBody(req)['pipeline'] != null;

List<List<String>> _pipelineCmds(http.Request req) => [
      for (final c in _sentBody(req)['pipeline'] as List)
        (c as List).cast<String>(),
    ];

/// 已连接 adapter（预置映射 srv-1，connect 走复用路径）。
Future<RedisAdapter> _connectedAdapter(_RecordingClient client) async {
  SharedPreferences.setMockInitialValues({
    'connection_server_id_map': jsonEncode({'local_redis_1': 'srv-1'}),
  });
  final adapter = RedisAdapter()..httpClient = client;
  final ok = await adapter.connect(_conn());
  expect(ok, isTrue, reason: 'fixture adapter must connect');
  return adapter;
}

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
          return _jsonResp({'ok': true, 'elapsedMs': 4}, 200);
        }
        if (req.url.path == '/api/gw/connections' && req.method == 'POST') {
          return _jsonResp({'serverConnId': 'srv-9'}, 200);
        }
        return _listResponse({});
      });
      final adapter = RedisAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(adapter.isConnected, isTrue);

      final draft = client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test');
      final draftBody = _sentBody(draft);
      expect(draftBody['dbType'], 'redis');
      expect(draftBody['host'], '192.0.2.128');
      expect(draftBody['port'], 6379);
      expect(draftBody['username'], 'default');
      expect(draftBody['password'], 'pw');
      // defaultDatabase = 连接 db index（'db0' → '0'）。
      expect(draftBody['defaultDatabase'], '0');

      final register = client.requests.firstWhere(
        (r) => r.method == 'POST' && r.url.path == '/api/gw/connections',
      );
      expect(_sentBody(register)['name'], 'Redis Live');
      expect(_sentBody(register)['readOnly'], false);

      final prefs = await SharedPreferences.getInstance();
      final map =
          jsonDecode(prefs.getString('connection_server_id_map')!) as Map;
      expect(map['local_redis_1'], 'srv-9');
    });

    test('映射有效 → 复用不重注册', () async {
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_redis_1': 'srv-1'}),
      });
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'unmapped'}}, 500);
      });
      final adapter = RedisAdapter()..httpClient = client;
      final ok = await adapter.connect(_conn());
      expect(ok, isTrue);
      expect(
        client.requests.any(
          (r) => r.method == 'POST' && r.url.path.contains('connections'),
        ),
        isFalse,
      );
    });

    test('凭据 test 失败 → connect false 且不注册', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections/test') {
          return _jsonResp({'ok': false, 'error': 'auth failed'}, 200);
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = RedisAdapter()..httpClient = client;
      expect(await adapter.connect(_conn()), isFalse);
      expect(adapter.isConnected, isFalse);
    });

    test('db index 双格式解析（db3 → database 路由 3）', () async {
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_redis_1': 'srv-1'}),
      });
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_resultEvents('OK'));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = RedisAdapter()..httpClient = client;
      await adapter.connect(_conn(database: 'db3'));
      expect(adapter.currentDbIndex, 3);
      await adapter.runCommand(['PING']);
      final body = _sentBody(client.requests
          .firstWhere((r) => r.url.path.endsWith('/query')));
      expect(body['database'], '3');
    });
  });

  group('命令通道：旧 RESP 形状重建', () {
    test('fallback 单列 → 整值（GET/SET/DEL/TTL）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final cmd = (_sentBody(req)['command'] as List).cast<String>();
          if (cmd[0] == 'SET') return _sse(_resultEvents('OK'));
          if (cmd[0] == 'GET') return _sse(_resultEvents('hello'));
          if (cmd[0] == 'DEL') return _sse(_resultEvents(1));
          if (cmd[0] == 'TTL') return _sse(_resultEvents(-1));
          if (cmd[0] == 'HGETALL') {
            return _sse(_semanticEvents(['field', 'value'], [
              ['a', 1],
              ['b', 2],
            ]));
          }
          return _sse(_resultEvents('PONG'));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      expect(await adapter.setString('k', 'v'), isTrue);
      expect(await adapter.getString('k'), 'hello');
      expect(await adapter.deleteKey('k'), 1);
      expect(await adapter.getTTL('k'), -1);

      // HGETALL 语义列 → 平铺对 → getHash 配对。
      final hash = await adapter.getHash('k');
      expect(hash, {'a': '1', 'b': '2'});
    });

    test('SCAN 族语义列 → [cursor, [items]]（scanKeys/getTables）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final cmd = (_sentBody(req)['command'] as List).cast<String>();
          if (cmd[0] == 'SCAN') {
            final cursorArg = cmd[1];
            if (cursorArg == '0') {
              return _sse(_semanticEvents(['cursor', 'key'], [
                ['17', 'user:1'],
                ['17', 'session:a'],
              ]));
            }
            // 第二轮：空批（server 回落 fallback → 整值 [cursor, []]）。
            return _sse(_resultEvents(['0', []]));
          }
          return _sse(_resultEvents('none'));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final keys = await adapter.scanKeys();
      expect(keys, ['user:1', 'session:a']);

      // 命名空间聚合（getTables）。
      final tables = await adapter.getTables();
      expect(tables, ['session', 'user']);
    });

    test('scanKeysCursor 外部 cursor 分页', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_semanticEvents(['cursor', 'key'], [
            ['42', 'a'],
            ['42', 'b'],
          ]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);
      final page = await adapter.scanKeysCursor(cursor: 0);
      expect(page.cursor, 42);
      expect(page.keys, ['a', 'b']);
    });

    test('executeQuery：SCAN → formatter 游标展开行', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_resultEvents(['17', ['k1', 'k2']]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final result = await adapter.executeQuery('SCAN 0 MATCH * COUNT 100');
      // RedisResultFormatter：首行 cursor + 每键一行（旧形状直通）。
      expect(result.rows.first['cursor'], '17');
      expect(result.rows.length, 3);
      expect(result.rows[1]['value'], 'k1');
    });

    test('请求形状：X-Execution-Id + timeoutMs（extra.timeout）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_resultEvents('PONG'));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_redis_1': 'srv-1'}),
      });
      final adapter = RedisAdapter()..httpClient = client;
      await adapter.connect(_conn(timeoutSecs: 45));
      await adapter.runCommand(['PING']);

      final req =
          client.requests.firstWhere((r) => r.url.path.endsWith('/query'));
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(req.headers['X-Execution-Id'] ?? ''),
        isTrue,
      );
      final body = _sentBody(req);
      expect(body['kind'], 'redis');
      expect(body['command'], ['PING']);
      expect(body['timeoutMs'], 45000);
      expect(body['rowLimit'], 10000);
    });

    test('SSE error → 包装上抛（Redis 命令执行失败 + engineCode）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse([
            'event: error\ndata: {"kind":"redis","type":"error","code":"DB_ERROR","message":"WRONGTYPE Operation","engineCode":"WRONGTYPE"}',
          ]);
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);
      await expectLater(
        adapter.executeQuery('LPUSH mystring x'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('Redis 命令执行失败'), contains('WRONGTYPE')),
          ),
        ),
      );
    });

    test('CONNECTION_FAILED → onDisconnect；命令错误不撕连接', () async {
      var code = 'DB_ERROR';
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse([
            'event: error\ndata: {"kind":"redis","type":"error","code":"$code","message":"x"}',
          ]);
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);
      var disconnected = 0;
      adapter.onDisconnect = () => disconnected++;

      // 命令错误（DB_ERROR）不撕连接（getDatabases 内部吞错回落 16 库）。
      await expectLater(adapter.getDatabases(), completion(hasLength(16)));
      expect(disconnected, 0);

      code = 'CONNECTION_FAILED';
      await expectLater(adapter.runCommand(['PING']), throwsException);
      expect(disconnected, 1);
    });
  });

  group('pipeline / 事务', () {
    test('multiExec → pipeline atomic:true，[index,result] 按序归位', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_semanticEvents(['index', 'result'], [
            [0, 1],
            [1, 2],
            [2, 'OK'],
          ]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final results = await adapter.multiExec([
        ['INCR', 'c'],
        ['INCR', 'c'],
        ['SET', 'k', 'v'],
      ]);
      expect(results, [1, 2, 'OK']);

      final body = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(body['pipeline'], [
        ['INCR', 'c'],
        ['INCR', 'c'],
        ['SET', 'k', 'v'],
      ]);
      expect(body['atomic'], true);
      expect(body.containsKey('command'), isFalse);
    });

    test('watch/unwatch/discardTx fail-loud（UnsupportedError）', () async {
      final adapter =
          await _connectedAdapter(_RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      }));
      await expectLater(adapter.watch(['k']), throwsA(isA<UnsupportedError>()));
      await expectLater(adapter.unwatch(), throwsA(isA<UnsupportedError>()));
      await expectLater(
        adapter.discardTx(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('pipeStart/pipeEnd 为 no-op（不抛不请求）', () async {
      final adapter =
          await _connectedAdapter(_RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      }));
      adapter.pipeStart();
      adapter.pipeEnd();
      expect(adapter.isConnected, isTrue);
    });
  });

  group('只读守卫（本地 validateCommand）', () {
    test('readOnly + SET → ReadOnlyBlockedException（guard 拦截，不发请求）',
        () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      SharedPreferences.setMockInitialValues({
        'connection_server_id_map': jsonEncode({'local_redis_1': 'srv-1'}),
      });
      final adapter = RedisAdapter()..httpClient = client;
      await adapter.connect(_conn(readOnly: true));
      // guard 在 try 外（与旧版一致）——readOnly 下直接抛守卫异常。
      await expectLater(
        adapter.setString('k', 'v'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
      await expectLater(
        adapter.runCommand(['DEL', 'k']),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
      // KEYS 属危险黑名单 → validateCommand dangerous → 拦截。
      await expectLater(
        adapter.runCommand(['KEYS', '*']),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
      // 无 query 请求发出（只有 connect 的 GET list）。
      expect(
        client.requests.where((r) => r.url.path.endsWith('/query')),
        isEmpty,
      );
    });
  });

  group('Pub/Sub（订阅 SSE 重订式）', () {
    test('订阅 → SSE 重建 → message → PubSubMessage broadcast', () async {
      // 每次订阅请求一条独立流（重订式：第二次订阅 = 第二条 SSE）。
      final subStreams = <StreamController<List<int>>>[];
      int subRequests = 0;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/redis/subscriptions')) {
          subRequests++;
          final stream = StreamController<List<int>>();
          subStreams.add(stream);
          return http.StreamedResponse(
            stream.stream,
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_resultEvents(1));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final messages = <String>[];
      adapter.pubSubMessageStream.listen((m) => messages.add(m.payload));

      await adapter.pubSubSubscribe('news');
      expect(subRequests, 1);
      // 订阅 URL：channels 参数（编码）。
      final subReq = client.requests
          .firstWhere((r) => r.url.path.endsWith('/redis/subscriptions'));
      expect(subReq.url.query, 'channels=news');

      // 注入 subscribed 回执（不转发 UI）+ message。
      subStreams[0].add(utf8.encode(
        'event: subscribed\ndata: {"type":"subscribed","channels":["news"],"patterns":[]}\n\n',
      ));
      await Future<void>.delayed(Duration.zero);
      subStreams[0].add(utf8.encode(
        'event: message\ndata: {"type":"message","channel":"news","pattern":null,"payload":"hello"}\n\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(messages, ['hello']);

      // 追加 pattern 订阅 → 目标集变化 → 重建（第二条 SSE）。
      await adapter.pubSubSubscribe('news.*', isPattern: true);
      expect(subRequests, 2);
      final second = client.requests
          .lastWhere((r) => r.url.path.endsWith('/redis/subscriptions'));
      expect(second.url.query, contains('channels=news'));
      expect(second.url.query, contains('patterns=news.%2A'));

      // pattern 消息（isPattern + pattern 字段）。
      final patternMessages = <bool>[];
      adapter.pubSubMessageStream.listen((m) {
        patternMessages.add(m.isPattern);
      });
      subStreams[1].add(utf8.encode(
        'event: message\ndata: {"type":"message","channel":"news.tech","pattern":"news.*","payload":"pm"}\n\n',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(patternMessages, contains(true));

      // 退订 news（仍有 pattern）→ 重订为 patterns-only（第三次 SSE）；
      // 再退 pattern 至空集 → 断开（无第四次请求）。
      await adapter.pubSubUnsubscribe('news');
      expect(subRequests, 3);
      final third = client.requests
          .lastWhere((r) => r.url.path.endsWith('/redis/subscriptions'));
      expect(third.url.query, 'patterns=news.%2A');
      await adapter.pubSubUnsubscribe('news.*', isPattern: true);
      expect(subRequests, 3);
      for (final stream in subStreams) {
        await stream.close();
      }
      await adapter.disposePubSub();
    });

    test('publish 走命令通道（PUBLISH）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_resultEvents(2));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);
      expect(await adapter.publish('news', 'hello'), 2);
      final body = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(body['command'], ['PUBLISH', 'news', 'hello']);
    });
  });

  group('db 路由 / keep-alive / 断开', () {
    test('useDatabase record-only → database 路由切换', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_resultEvents('PONG'));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);
      await adapter.useDatabase('db5');
      expect(adapter.currentDbIndex, 5);
      expect(adapter.currentConnection?.database, 'db5');
      await adapter.runCommand(['PING']);
      final body = _sentBody(
        client.requests.firstWhere((r) => r.url.path.endsWith('/query')),
      );
      expect(body['database'], '5');
    });

    test('keep-alive PING 经 runCommand（DatabaseService 契约）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_resultEvents('PONG'));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);
      expect(await adapter.runCommand(['PING']), 'PONG');
    });

    test('无 server 会话 → 引导性 StateError', () async {
      ServerConnection.resetForTesting();
      final adapter = RedisAdapter();
      await expectLater(adapter.connect(_conn()), throwsA(isA<StateError>()));
    });

    test('disconnect → 清空连接态', () async {
      final adapter = await _connectedAdapter(_RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      }));
      expect(adapter.isConnected, isTrue);
      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
      expect(adapter.currentConnection, isNull);
    });
  });

  group('validateCommand（本地黑名单，与旧版逐字一致）', () {
    test('危险/写/读分类', () {
      final adapter = RedisAdapter();
      expect(
        adapter.validateCommand('FLUSHALL').riskLevel,
        CommandRiskLevel.dangerous,
      );
      expect(
        adapter.validateCommand('KEYS *').riskLevel,
        CommandRiskLevel.dangerous,
      );
      expect(
        adapter.validateCommand('SET k v').riskLevel,
        CommandRiskLevel.warning,
      );
      expect(adapter.validateCommand('GET k').riskLevel, CommandRiskLevel.safe);
      expect(adapter.isWriteCommand('DEL k'), isTrue);
      expect(adapter.isWriteCommand('GET k'), isFalse);
    });
  });
  // 网关 TLS 透传 + server 侧 SSH 隧道：draft/test body 形状（字段来自
  // DatabaseConnection.fromDbServer 的 extra 投影——useTls 两键与 ssh 对象）。
  group('draft body：TLS 透传 + server 侧 SSH 隧道', () {
    final sshWire = {
      'host': 'jump.example.com',
      'port': 2222,
      'username': 'deploy',
      'authMode': 'password',
      'password': 'hunter2',
    };

    test('useTls 开启 → extra 两键；ssh 对象原样透传', () async {
      final client = _RecordingClient((req) =>
          _jsonResp({'ok': true, 'elapsedMs': 4}, 200));
      final adapter = RedisAdapter()..httpClient = client;
      await adapter.testConnection(DatabaseConnection(
        id: 'local_redis_1',
        name: 'Redis Live',
        type: DatabaseType.redis,
        host: '192.0.2.128',
        port: 6379,
        database: 'db0',
        extra: {'useTls': true, 'tlsInsecure': true, 'ssh': sshWire},
      ));

      final body = _sentBody(client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test'));
      expect(body['extra'], {'useTls': true, 'tlsInsecure': true});
      expect(body['ssh'], sshWire);
    });

    test('useTls 关闭 / 无 ssh → 两键均不下发', () async {
      final client = _RecordingClient((req) =>
          _jsonResp({'ok': true, 'elapsedMs': 4}, 200));
      final adapter = RedisAdapter()..httpClient = client;
      await adapter.testConnection(DatabaseConnection(
        id: 'local_redis_1',
        name: 'Redis Live',
        type: DatabaseType.redis,
        host: '192.0.2.128',
        port: 6379,
        database: 'db0',
        extra: {'useTls': false, 'tlsInsecure': true, 'timeout': 5},
      ));

      final body = _sentBody(client.requests
          .firstWhere((r) => r.url.path == '/api/gw/connections/test'));
      expect(body.containsKey('extra'), isFalse);
      expect(body.containsKey('ssh'), isFalse);
    });
  });

  group('批量底座（限流根治）', () {
    test('getTableData 两相 pipeline：整页恒定 3 请求，行形状逐字不变', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          if (!_isPipeline(req)) {
            return _sse(_semanticEvents(['cursor', 'key'], [
              ['0', 'app:user:1'],
              ['0', 'app:cfg'],
            ]));
          }
          final cmds = _pipelineCmds(req);
          if (cmds.first[0] == 'TYPE') {
            expect(cmds, [
              ['TYPE', 'app:user:1'],
              ['TTL', 'app:user:1'],
              ['TYPE', 'app:cfg'],
              ['TTL', 'app:cfg'],
            ]);
            return _sse(_pipelineEvents(['string', 120, 'hash', -1]));
          }
          expect(cmds, [
            ['GET', 'app:user:1'],
            ['STRLEN', 'app:user:1'],
            ['HLEN', 'app:cfg'],
            ['HSCAN', 'app:cfg', '0', 'COUNT', '6'],
          ]);
          return _sse(_pipelineEvents([
            'hello',
            5,
            2,
            ['0', ['f1', 'v1', 'f2', 'v2']],
          ]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final result = await adapter.getTableData('app');

      final queryReqs = client.requests
          .where((r) => r.url.path.endsWith('/query'))
          .toList();
      expect(queryReqs.length, 3, reason: 'SCAN + TYPE/TTL 相 + 值相，恒定 3 请求');
      expect(result.columns, ['key', 'type', 'value', 'ttl', 'size']);
      expect(result.rows, [
        {
          'key': 'app:user:1',
          'type': 'string',
          'value': 'hello',
          'ttl': '120s',
          'size': 5,
        },
        {
          'key': 'app:cfg',
          'type': 'hash',
          'value': '[2 fields] f1=v1, f2=v2',
          'ttl': '无过期',
          'size': 2,
        },
      ]);
    });

    test('getTableData string >1024 截断与 (key不存在) 语义保留', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          if (!_isPipeline(req)) {
            return _sse(_semanticEvents(['cursor', 'key'], [
              ['0', 'big'],
              ['0', 'gone'],
            ]));
          }
          final cmds = _pipelineCmds(req);
          if (cmds.first[0] == 'TYPE') {
            return _sse(_pipelineEvents(['string', -1, 'none', -2]));
          }
          return _sse(_pipelineEvents(['x' * 1100, 1100]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final result = await adapter.getTableData('*');
      expect(result.rows, [
        {
          'key': 'big',
          'type': 'string',
          'value': '${'x' * 1024}... (1100 chars total)',
          'ttl': '无过期',
          'size': 1100,
        },
        {
          'key': 'gone',
          'type': 'none',
          'value': '(key不存在)',
          'ttl': '不存在',
          'size': null,
        },
      ]);
    });

    test('exportDatabaseStructure：TYPE/取值分块 pipeline（≤400 命令/请求）',
        () async {
      const n = 900;
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          if (!_isPipeline(req)) {
            return _sse(_semanticEvents(
              ['cursor', 'key'],
              [
                for (var i = 0; i < n; i++) ['0', 'k$i'],
              ],
            ));
          }
          final cmds = _pipelineCmds(req);
          if (cmds.first[0] == 'TYPE') {
            return _sse(_pipelineEvents([
              for (final _ in cmds) 'string',
            ]));
          }
          return _sse(_pipelineEvents([
            for (final c in cmds) 'v${c[1].substring(1)}',
          ]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final out = await adapter.exportDatabaseStructure('db0');

      final pipelineReqs = client.requests
          .where((r) => r.url.path.endsWith('/query') && _isPipeline(r))
          .toList();
      expect(
        pipelineReqs.map((r) => _pipelineCmds(r).length).toList(),
        [400, 400, 100, 400, 400, 100],
        reason: 'TYPE 3 块 + GET 3 块（900 = 400+400+100）',
      );
      expect(_pipelineCmds(pipelineReqs.first).first, ['TYPE', 'k0']);
      expect(out, contains("SET 'k0' 'v0'"));
      expect(out, contains("SET 'k899' 'v899'"));
    });

    test('getTopKeysByMemory：SCAN COUNT 1000 + MEMORY USAGE 单 pipeline',
        () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          if (!_isPipeline(req)) {
            return _sse(_resultEvents(['0', ['k0', 'k1', 'k2']]));
          }
          expect(_pipelineCmds(req), [
            ['MEMORY', 'USAGE', 'k0'],
            ['MEMORY', 'USAGE', 'k1'],
            ['MEMORY', 'USAGE', 'k2'],
          ]);
          return _sse(_pipelineEvents([10, 300, 20]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final top = await adapter.getTopKeysByMemory();
      expect(top, [
        {'key': 'k1', 'bytes': 300},
        {'key': 'k2', 'bytes': 20},
        {'key': 'k0', 'bytes': 10},
      ]);

      final scanReq = client.requests
          .firstWhere((r) => r.url.path.endsWith('/query') && !_isPipeline(r));
      expect(_sentBody(scanReq)['command'], ['SCAN', '0', 'COUNT', '1000']);
      expect(
        client.requests.where((r) => r.url.path.endsWith('/query')).length,
        2,
        reason: 'SCAN 一请求 + MEMORY USAGE 一 pipeline',
      );
    });

    test('multiExec 超分块阈值仍单请求（MULTI/EXEC 永不分块）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          return _sse(_pipelineEvents([
            for (var i = 0; i < 401; i++) 'PONG',
          ]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final results = await adapter.multiExec([
        for (var i = 0; i < 401; i++) ['PING'],
      ]);
      expect(results.length, 401);

      final pipelines =
          client.requests.where((r) => r.url.path.endsWith('/query')).toList();
      expect(pipelines.length, 1, reason: '原子事务必须单请求执行');
      expect(_sentBody(pipelines.first)['atomic'], true);
      expect(_pipelineCmds(pipelines.first).length, 401);
    });
  });

  group('增量 SCAN 分页（keys 真分页）', () {
    List<String> scanCmdOf(http.Request req) =>
        (_sentBody(req)['command'] as List).cast<String>();

    test('首页只发一轮 SCAN（要多少扫多少），翻页沿游标续扫', () async {
      // keyspace 共 12 个 ns key：首轮 SCAN 回 4 个 + 游标 7；续扫回 8 个
      // + 游标 0（扫尽）。页大小 10。
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          if (!_isPipeline(req)) {
            final cmd = scanCmdOf(req);
            if (cmd[0] == 'SCAN') {
              if (cmd[1] == '0') {
                return _sse(_semanticEvents(['cursor', 'key'], [
                  ['7', 'ns:k1'],
                  ['7', 'ns:k2'],
                  ['7', 'ns:k3'],
                  ['7', 'ns:k4'],
                ]));
              }
              expect(cmd[1], '7', reason: '翻页必须沿游标续扫');
              return _sse(_semanticEvents(['cursor', 'key'], [
                ['0', 'ns:k5'],
                ['0', 'ns:k6'],
                ['0', 'ns:k7'],
                ['0', 'ns:k8'],
                ['0', 'ns:k9'],
                ['0', 'ns:k10'],
                ['0', 'ns:k11'],
                ['0', 'ns:k12'],
              ]));
            }
            return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
          }
          final cmds = _pipelineCmds(req);
          if (cmds.first[0] == 'TYPE') return _sse(_pipelineEvents([]));
          return _sse(_pipelineEvents([]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      // 首页（limit 10 > 首轮 4 个）→ 需要第二轮补扫：首页即 2 轮 SCAN。
      // 更贴近「第一次只获取一部分」的是 limit ≤ 首轮批量：用两页验证。
      final page1 = await adapter.getTableData('ns', limit: 4, offset: 0);
      expect(page1.rows.map((r) => r['key']), [
        'ns:k1',
        'ns:k2',
        'ns:k3',
        'ns:k4',
      ]);
      final scansAfterPage1 = client.requests
          .where(
            (r) =>
                r.url.path.endsWith('/query') &&
                !_isPipeline(r) &&
                scanCmdOf(r)[0] == 'SCAN',
          )
          .length;
      expect(scansAfterPage1, 1, reason: '首页只扫到够本页为止（1 轮）');

      // 第二页（offset 4, limit 4）→ 沿游标 7 续扫一轮。
      final page2 = await adapter.getTableData('ns', limit: 4, offset: 4);
      expect(page2.rows.map((r) => r['key']), [
        'ns:k5',
        'ns:k6',
        'ns:k7',
        'ns:k8',
      ]);
      final scansAfterPage2 = client.requests
          .where(
            (r) =>
                r.url.path.endsWith('/query') &&
                !_isPipeline(r) &&
                scanCmdOf(r)[0] == 'SCAN',
          )
          .length;
      expect(scansAfterPage2, 2, reason: '翻页只补一轮 SCAN');

      // 第三页（offset 8）→ 缓存已扫尽（游标 0），不再发 SCAN。
      final page3 = await adapter.getTableData('ns', limit: 4, offset: 8);
      expect(page3.rows.map((r) => r['key']), [
        'ns:k9',
        'ns:k10',
        'ns:k11',
        'ns:k12',
      ]);
      final scansAfterPage3 = client.requests
          .where(
            (r) =>
                r.url.path.endsWith('/query') &&
                !_isPipeline(r) &&
                scanCmdOf(r)[0] == 'SCAN',
          )
          .length;
      expect(scansAfterPage3, 2, reason: '扫尽后翻页零 SCAN');

      // 首页 SCAN 的 COUNT = 缺口自适应（needed 4 → clamp 下限 100）。
      final firstScan = client.requests.firstWhere(
        (r) =>
            r.url.path.endsWith('/query') &&
            !_isPipeline(r) &&
            scanCmdOf(r)[0] == 'SCAN',
      );
      expect(scanCmdOf(firstScan), ['SCAN', '0', 'MATCH', 'ns:*', 'COUNT', '100']);
    });

    test('写命令（DEL）后缓存失效 → 下一页从头重扫', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          if (!_isPipeline(req)) {
            final cmd = scanCmdOf(req);
            if (cmd[0] == 'SCAN') {
              return _sse(_semanticEvents(['cursor', 'key'], [
                ['0', 'ns:k1'],
                ['0', 'ns:k2'],
              ]));
            }
            if (cmd[0] == 'DEL') {
              return _sse(_resultEvents(1));
            }
            return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
          }
          return _sse(_pipelineEvents([]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      await adapter.getTableData('ns', limit: 10, offset: 0);
      await adapter.deleteKey('ns:k1'); // 写路径 → 缓存失效
      await adapter.getTableData('ns', limit: 10, offset: 0); // 失效后重扫

      final scanCursors = client.requests
          .where(
            (r) =>
                r.url.path.endsWith('/query') &&
                !_isPipeline(r) &&
                scanCmdOf(r)[0] == 'SCAN',
          )
          .map((r) => scanCmdOf(r)[1])
          .toList();
      expect(scanCursors, ['0', '0'], reason: 'DEL 后重扫从游标 0 开始');
    });

    test('getKeyTypes / getTTLs 批量（pipeline，顺序保持）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final cmds = _pipelineCmds(req);
          if (cmds.first[0] == 'TYPE') {
            expect(cmds, [
              ['TYPE', 'a'],
              ['TYPE', 'b'],
            ]);
            return _sse(_pipelineEvents(['string', null]));
          }
          expect(cmds, [
            ['TTL', 'a'],
            ['TTL', 'b'],
          ]);
          return _sse(_pipelineEvents([120, -2]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      expect(await adapter.getKeyTypes(['a', 'b']), ['string', 'none']);
      expect(await adapter.getTTLs(['a', 'b']), [120, -2]);
    });

    test('getTableRowCount 全库口径走 DBSIZE（零 SCAN）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          expect(_sentBody(req)['command'], ['DBSIZE']);
          return _sse(_resultEvents(42));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      expect(await adapter.getTableRowCount('(无前缀)'), 42);
    });

    test('sampleKeys：Keys/TTL 节点共享同一 SCAN 进度（后展开只补缺口）',
        () async {
      // SCAN '0' → 4 keys + 游标 '7'；SCAN '7' → 4 keys + 游标 '0'（扫尽）。
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final cmd = scanCmdOf(req);
          if (cmd[1] == '0') {
            return _sse(_semanticEvents(['cursor', 'key'], [
              ['7', 'ns:k1'],
              ['7', 'ns:k2'],
              ['7', 'ns:k3'],
              ['7', 'ns:k4'],
            ]));
          }
          expect(cmd[1], '7');
          return _sse(_semanticEvents(['cursor', 'key'], [
            ['0', 'ns:k5'],
            ['0', 'ns:k6'],
            ['0', 'ns:k7'],
            ['0', 'ns:k8'],
          ]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      int scanCount() => client.requests
          .where((r) => r.url.path.endsWith('/query') && scanCmdOf(r)[0] == 'SCAN')
          .length;

      // Keys 节点：首采 4 个（一轮 SCAN）。
      final keys = await adapter.sampleKeys(limit: 4);
      expect(keys.keys, ['ns:k1', 'ns:k2', 'ns:k3', 'ns:k4']);
      expect(keys.hasMore, isTrue);
      expect(scanCount(), 1);

      // 同 db 重复 useDatabase（侧边栏每次加载都会调）不得清掉共享采样。
      await adapter.useDatabase('db0');

      // TTL 节点：要 1000 个 → 页内只有 4，补扫一轮后扫尽。
      final ttl = await adapter.sampleKeys(limit: 1000);
      expect(ttl.keys.length, 8);
      expect(ttl.hasMore, isFalse);
      expect(scanCount(), 2, reason: '只补扫一轮缺口');

      // 扫尽后再次展开：零 SCAN。
      final again = await adapter.sampleKeys(limit: 1000);
      expect(again.keys.length, 8);
      expect(scanCount(), 2, reason: '页扫尽后零 SCAN');
    });

    test('sampleKeys：换 db 才失效共享采样（同 db 保留）', () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final cmd = scanCmdOf(req);
          final db = _sentBody(req)['database'].toString();
          if (db == '0') {
            return _sse(_semanticEvents(['cursor', 'key'], [
              ['0', 'k0a'],
              ['0', 'k0b'],
            ]));
          }
          expect(db, '3');
          return _sse(_semanticEvents(['cursor', 'key'], [
            ['0', 'k3a'],
          ]));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      List<String> scanCursors() => client.requests
          .where((r) => r.url.path.endsWith('/query') && scanCmdOf(r)[0] == 'SCAN')
          .map((r) => scanCmdOf(r)[1])
          .toList();

      final db0 = await adapter.sampleKeys(limit: 10);
      expect(db0.keys, ['k0a', 'k0b']);

      await adapter.useDatabase('db0'); // 同 db → 共享采样保留
      final reused = await adapter.sampleKeys(limit: 10);
      expect(reused.keys, ['k0a', 'k0b']);
      expect(scanCursors(), ['0'], reason: '同 db 零 SCAN');

      await adapter.useDatabase('db3'); // 换 db → 失效重扫
      final db3 = await adapter.sampleKeys(limit: 10);
      expect(db3.keys, ['k3a']);
      expect(scanCursors(), ['0', '0'], reason: '换 db 从游标 0 重扫');
    });

    test('getKeyspaceAggregate：解析 INFO keyspace 当前 db 行（精确口径）',
        () async {
      final client = _RecordingClient((req) {
        if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
          return _listResponse({'srv-1'});
        }
        if (req.url.path.endsWith('/query')) {
          final cmd = (_sentBody(req)['command'] as List).cast<String>();
          expect(cmd, ['INFO', 'keyspace']);
          final infoText = [
            '# Keyspace',
            'db0:keys=10,expires=4,avg_ttl=0',
            'db3:keys=21134,expires=312,avg_ttl=3600000',
          ].join('\n');
          return _sse(_resultEvents(infoText));
        }
        return _jsonResp({'error': {'code': 'X', 'message': 'x'}}, 500);
      });
      final adapter = await _connectedAdapter(client);

      final agg0 = await adapter.getKeyspaceAggregate();
      expect(agg0.keys, 10);
      expect(agg0.expires, 4);
      expect(agg0.avgTtlMs, 0);

      await adapter.useDatabase('db3');
      final agg3 = await adapter.getKeyspaceAggregate();
      expect(agg3.keys, 21134);
      expect(agg3.expires, 312);
      expect(agg3.avgTtlMs, 3600000);
    });
  });

}
