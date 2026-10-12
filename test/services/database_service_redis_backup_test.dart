// T20（W-17）· 服务层单测 —— getRedisPersistenceInfo / triggerRedisBgsave。
//
// 形态沿 redis_gateway_adapter_test（真 RedisAdapter + mock HTTP 网关壳 +
// embedded ServerConnection 握手注入），经 DatabaseService
// setAdapterFactoryForTest 走真实 connect 流程——验证「服务层薄方法 →
// adapter runCommand 既有面」全链路：
// - INFO persistence 解析（扁平 Map，`#` 注释行跳过）+ LASTSAVE 合并
//   （`lastsave` 键 = unix 秒字符串）；
// - readonly 连接：INFO/LASTSAVE（safe 级）放行；BGSAVE（forbidden 表 →
//   dangerous ≠ safe）由 adapter runCommand 首行 guardReadOnlyQuery
//   fail-closed 拦截抛 ReadOnlyBlockedException（既有面测试锚定，零新增
//   拦截面——任务书 T20 约束条款）；
// - 连接缺失：读锚定空 Map（状态区空态）/ 触发 fail-loud。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/readonly_guard.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 记录全部请求并按路径规则回放的客户端（redis_gateway_adapter_test 同款）。
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

http.StreamedResponse _sse(List<String> events) {
  final body = '${events.join('\n\n')}\n\n';
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    200,
    headers: const {'content-type': 'text/event-stream'},
  );
}

http.StreamedResponse _jsonResp(Object body, int status) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: const {'content-type': 'application/json'},
    );

Map<String, dynamic> _sentBody(http.Request req) =>
    jsonDecode(req.body) as Map<String, dynamic>;

/// fallback 单列 SSE 三事件（整值 JSON 单元格）。
List<String> _resultEvents(dynamic value) => [
      'event: meta\ndata: {"kind":"redis","type":"meta","columns":["result"]}',
      'event: rows\ndata: {"kind":"redis","type":"rows","rows":${jsonEncode([[value]])}}',
      'event: complete\ndata: {"kind":"redis","type":"complete","rowCount":1,"truncated":false,"elapsedMs":3}',
    ];

const String _infoPersistenceText = '# Persistence\n'
    'loading:0\n'
    'rdb_changes_since_last_save:42\n'
    'rdb_bgsave_in_progress:0\n'
    'rdb_last_save_time:1760000000\n'
    'rdb_last_bgsave_status:ok\n'
    'rdb_last_bgsave_time_sec:3\n'
    'rdb_current_bgsave_time_sec:-1\n'
    'aof_enabled:1\n'
    'aof_rewrite_in_progress:0\n';

/// 命令通道路由（按 body.command 首元素分发）。
http.StreamedResponse Function(http.Request) _commandHandler({
  required Object? Function(List<String> command) replies,
}) {
  return (req) {
    if (req.url.path == '/api/gw/connections' && req.method == 'GET') {
      return _jsonResp(
        [for (final id in const {'srv-1'}) {'id': id, 'dbType': 'redis'}],
        200,
      );
    }
    if (req.url.path.endsWith('/query')) {
      final command =
          (_sentBody(req)['command'] as List).cast<String>().toList();
      final reply = replies(command);
      if (reply case final Object value?) {
        return _sse(_resultEvents(value));
      }
      return _jsonResp({
        'error': {'code': 'DB_ERROR', 'message': 'unexpected command'},
      }, 500);
    }
    return _jsonResp({
      'error': {'code': 'X', 'message': 'unmapped endpoint'},
    }, 500);
  };
}

Future<DatabaseService> _connectedService(
  _RecordingClient client, {
  bool readOnly = false,
}) async {
  SharedPreferences.setMockInitialValues({
    'connection_server_id_map': jsonEncode({'local_redis_1': 'srv-1'}),
  });
  final service = DatabaseService();
  service.setAdapterFactoryForTest(
    DatabaseType.redis,
    () => RedisAdapter()..httpClient = client,
  );
  final server = DbServer(
    id: 'local_redis_1',
    name: 'Redis Live',
    type: DatabaseType.redis,
    host: '192.0.2.128',
    port: 6379,
    password: 'pw',
    database: 'db15',
    readOnly: readOnly,
  );
  final ok = await service.connect(server);
  expect(ok, isTrue, reason: 'fixture service must connect');
  return service;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ServerConnection.resetForTesting();
    ServerConnection().connectEmbedded(
      port: 45675,
      accessToken: 'emb-token',
      refreshToken: 'emb-refresh',
      installUuid: 'uuid',
      version: '0.1.0',
    );
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  group('getRedisPersistenceInfo（W-17）', () {
    test('INFO persistence 解析 + LASTSAVE 合并（lastsave 键 = unix 秒）',
        () async {
      final sentCommands = <List<String>>[];
      final client = _RecordingClient(
        _commandHandler(
          replies: (command) {
            sentCommands.add(command);
            if (command.isNotEmpty && command[0] == 'INFO') {
              return _infoPersistenceText;
            }
            if (command.isNotEmpty && command[0] == 'LASTSAVE') {
              return 1760000000;
            }
            return null;
          },
        ),
      );
      final service = await _connectedService(client);

      final info = await service.getRedisPersistenceInfo(
        connectionId: 'local_redis_1',
      );

      // 两条既有通道命令：INFO persistence + LASTSAVE（零新执行通道）。
      expect(sentCommands, [
        ['INFO', 'persistence'],
        ['LASTSAVE'],
      ]);
      // `#` 注释行跳过；字段扁平解析；LASTSAVE 合并进同 Map。
      expect(info['rdb_changes_since_last_save'], '42');
      expect(info['rdb_bgsave_in_progress'], '0');
      expect(info['rdb_last_save_time'], '1760000000');
      expect(info['rdb_last_bgsave_status'], 'ok');
      expect(info['rdb_last_bgsave_time_sec'], '3');
      expect(info['rdb_current_bgsave_time_sec'], '-1');
      expect(info['aof_enabled'], '1');
      expect(info['lastsave'], '1760000000');
      expect(info.containsKey('# Persistence'), isFalse);
    });

    test('readonly 连接放行（INFO/LASTSAVE 为 safe 级，不在 forbidden 表）',
        () async {
      final client = _RecordingClient(
        _commandHandler(
          replies: (command) {
            if (command.isNotEmpty && command[0] == 'INFO') {
              return _infoPersistenceText;
            }
            if (command.isNotEmpty && command[0] == 'LASTSAVE') {
              return 1760000000;
            }
            return null;
          },
        ),
      );
      final service = await _connectedService(client, readOnly: true);

      final info = await service.getRedisPersistenceInfo(
        connectionId: 'local_redis_1',
      );
      expect(info['rdb_last_bgsave_status'], 'ok');
      expect(info['lastsave'], '1760000000');
    });

    test('连接缺失 → 锚定空 Map（状态区空态，不抛）', () async {
      final client = _RecordingClient(
        _commandHandler(replies: (_) => null),
      );
      final service = await _connectedService(client);

      final info = await service.getRedisPersistenceInfo(
        connectionId: 'no_such_conn',
      );
      expect(info, isEmpty);
    });
  });

  group('triggerRedisBgsave（W-17，服务器写操作 ◆）', () {
    test('可写连接：BGSAVE 经 runCommand 既有面发出，返回原始回复', () async {
      final sentCommands = <List<String>>[];
      final client = _RecordingClient(
        _commandHandler(
          replies: (command) {
            sentCommands.add(command);
            if (command.isNotEmpty && command[0] == 'BGSAVE') {
              return 'Background saving started';
            }
            return null;
          },
        ),
      );
      final service = await _connectedService(client);

      final reply = await service.triggerRedisBgsave(
        connectionId: 'local_redis_1',
      );

      expect(reply, 'Background saving started');
      expect(sentCommands, [
        ['BGSAVE'],
      ]);
    });

    test('readonly 连接：adapter 守卫 fail-closed 抛 ReadOnlyBlockedException'
        '（既有面锚定，命令不出客户端）', () async {
      final sentCommands = <List<String>>[];
      final client = _RecordingClient(
        _commandHandler(
          replies: (command) {
            sentCommands.add(command);
            return null;
          },
        ),
      );
      final service = await _connectedService(client, readOnly: true);

      await expectLater(
        service.triggerRedisBgsave(connectionId: 'local_redis_1'),
        throwsA(isA<ReadOnlyBlockedException>()),
      );
      // 守卫在请求发出前拦截（无 query 请求）。
      expect(sentCommands, isEmpty);
      expect(
        client.requests.where((r) => r.url.path.endsWith('/query')),
        isEmpty,
      );
    });

    test('连接缺失 → fail-loud 抛（触发路径不静默）', () async {
      final client = _RecordingClient(
        _commandHandler(replies: (_) => null),
      );
      final service = await _connectedService(client);

      await expectLater(
        service.triggerRedisBgsave(connectionId: 'no_such_conn'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
