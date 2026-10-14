// =============================================================================
// sleep-resume 修复批 T3 · SSE 主查询通道三层超时测试（D3 语义）。
// =============================================================================
// 注入桩 + 缩短的 SseTimeouts 常量，真实时间跑（亚秒级），不依赖真库慢查询、
// 不依赖 fake_async。编号 SSE-TO-001..014（T9 登记；任务书预分配 001..012，
// 实际 14 例——「其余 6 adapter 各 ≥1 例 + redis 两处各 1 例」最小覆盖 7 例，
// 叠加 mysql/gateway_backing 两组模板深化超配额 2 例，见 T3 汇报）。
//
// 分组与断言面：
// - mysql（聚合版模板，SSE-TO-001..004）：
//   ① send 永挂 → first-byte 超时 → CONNECTION_FAILED（含层名）+ onDisconnect；
//   ② 流首包后停发 → idle 超时 → CONNECTION_FAILED + onDisconnect；
//   ③ 守卫例：流持续发 `:` keep-alive 注释行 + 长于 idle 的时长无事件 →
//      仍在等待（不误杀）；终态到达 → 健康收尾成功；
//   ④ total 兜底：keep-alive 永流 + 永无终态 → totalFor（缩短注入值）处失败
//      （防「一刀切 total」回潮的对照例——total 只兜病态，不截健康慢流）。
// - gateway_backing（生成器版模板，SSE-TO-005..007）：
//   first-byte / idle 超时 → yield ExecutionError(CONNECTION_FAILED)（激活
//   既有 on TimeoutException 分支）；keep-alive 持续泵过聚合版 total 等效
//   时长仍无 error（生成器版不接 total 层——D3 已裁决，防一刀切回潮守卫例）。
// - 其余 6 个网关壳 adapter（SSE-TO-008..014）：流首包后停发 → idle 超时
//   → 该库 typed exception CONNECTION_FAILED + onDisconnect（redis 两处
//   调用点各 1 例：runCommand + pipeline/getKeyTypes）。
//
// 环境说明：ServerConnection.connectEmbedded 会起 30s heartbeat
// Timer.periodic——注入 testHttpClient（恒 200）隔离；测试时长（≈1s/例）
// 远小于心跳周期，不触发；SseTimeouts 缩短值在每例 finally 内恢复。
//
// 时序纪律（真实时间）：
// - 用纯 test()（非 testWidgets）——fake_async 下 Stream.timeout 的
//   addError 传播与 testWidgets 收尾交互会挂死（T3 排障实证：body 完成后
//   10 分钟超时），真实时间无此问题且单例预算 <1.5s。
// - 错误断言用 expectLater 紧跟 future 创建挂接（真实时间下超时错误在
//   ≥200ms 后才产生，expectLater 同步挂接必然先于错误）。
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/services/adapters/clickhouse_adapter.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'package:dbmaster/services/adapters/tdengine_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/ports/gateway_backing.dart';
import 'package:dbmaster/services/ports/port_types.dart';
import 'package:dbmaster/services/server_connection.dart';
import 'package:dbmaster/services/sse_timeout.dart';

const Map<String, String> _sseHeaders = {'content-type': 'text/event-stream'};

http.StreamedResponse _jsonBody(Object body, int status) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: const {'content-type': 'application/json'},
    );

http.StreamedResponse _sseFromStream(Stream<List<int>> bytes) =>
    http.StreamedResponse(bytes, 200, headers: _sseHeaders);

/// 流首包（一条 keep-alive 行）后停发的开放流——idle 层注入桩。
/// 非 broadcast controller：add 先于 listen 会缓冲，listen 即投递并武装
/// idle 看门狗；永不 close → 流保持打开。
http.StreamedResponse _stalledSseResponse() {
  final controller = StreamController<List<int>>();
  controller.add(utf8.encode(': keep-alive\n'));
  return _sseFromStream(controller.stream);
}

/// 永续 keep-alive 注释行流（间隔须 < 缩短后的 idle——看门狗持续被重置；
/// 永不终态）。adapter 侧超时取消后上游订阅连带取消，Stream.periodic
/// 定时器随取消停止，无泄漏。
Stream<List<int>> _keepAliveForever() => Stream<List<int>>.periodic(
      const Duration(milliseconds: 50),
      (i) => utf8.encode(': keep-alive $i\n'),
    );

/// 心跳隔离桩：任何请求恒 200（ServerConnection.testHttpClient 注入——
/// embedded heartbeat 每 30s GET /api/health，恒 200 保持 connected，
/// 不产生真实 IO）。
class _OkHealthClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      _jsonBody({'status': 'ok'}, 200);
}

/// 网关壳注入桩：连接管理路由（GET/POST /api/gw/connections、test、
/// DELETE executions）返回即时成功；`/query` 按构造参数行为——
/// [hangQuery] 为真则 send 永挂（first-byte 桩），否则每次调用
/// [queryHandler] 取新响应（idle/keep-alive 桩）。
class _SseFakeClient extends http.BaseClient {
  _SseFakeClient({
    required this.wireDbType,
    this.queryHandler,
    this.hangQuery = false,
  });

  final String wireDbType;
  final http.StreamedResponse Function()? queryHandler;
  final bool hangQuery;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path == '/api/gw/connections' && request.method == 'GET') {
      return _jsonBody([
        {'id': 'srv-1', 'dbType': wireDbType},
      ], 200);
    }
    if (path == '/api/gw/connections/test') {
      return _jsonBody({'ok': true, 'elapsedMs': 1}, 200);
    }
    if (path == '/api/gw/connections' && request.method == 'POST') {
      return _jsonBody({'serverConnId': 'srv-1'}, 200);
    }
    if (path.endsWith('/query')) {
      if (hangQuery) {
        return Completer<http.StreamedResponse>().future;
      }
      final handler = queryHandler;
      if (handler == null) {
        return _jsonBody(
          {'error': {'code': 'X', 'message': 'no handler'}},
          500,
        );
      }
      return handler();
    }
    return _jsonBody({}, 204);
  }
}

void _bindServer() {
  ServerConnection.resetForTesting();
  ServerConnection().testHttpClient = _OkHealthClient();
  ServerConnection().connectEmbedded(
    port: 45673,
    accessToken: 'emb-token',
    refreshToken: 'emb-refresh',
    installUuid: 'uuid',
    version: '0.1.0',
  );
}

Future<void> _bindConnMap(String localId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'connection_server_id_map',
    jsonEncode({localId: 'srv-1'}),
  );
}

/// 无 database 的连接（避开 mysql/pg 的 stale 库自愈重试——超时映射的
/// CONNECTION_FAILED 会触发带库路由重试一次，混入第二发请求）。
DatabaseConnection _conn(DatabaseType type, String id) => DatabaseConnection(
      id: id,
      name: 'T3 ${type.name}',
      type: type,
      host: '127.0.0.1',
      port: 3306,
      username: 'u',
      password: 'p',
    );

/// 测试态超时常量快照/恢复（每例 finally 内调用）。
void _resetSseTimeouts() {
  SseTimeouts.firstByte = const Duration(seconds: 30);
  SseTimeouts.idle = const Duration(seconds: 45);
  SseTimeouts.serverCeiling = const Duration(seconds: 600);
  SseTimeouts.buffer = const Duration(seconds: 30);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _bindServer();
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  group('mysql 聚合版（模板深化）', () {
    test('SSE-TO-001 send 永挂 → first-byte 超时 → CONNECTION_FAILED + onDisconnect', () async {
      SseTimeouts.firstByte = const Duration(milliseconds: 200);
      try {
        final adapter = MySQLAdapter()
          ..httpClient = _SseFakeClient(wireDbType: 'mysql', hangQuery: true);
        await _bindConnMap('local_mysql_1');
        await adapter.connect(_conn(DatabaseType.mysql, 'local_mysql_1'));
        var disconnected = false;
        adapter.onDisconnect = () => disconnected = true;

        final future = adapter.executeQuery('SELECT 1');
        await expectLater(
          future,
          throwsA(
            isA<MySqlGatewayException>()
                .having((e) => e.code, 'code', 'CONNECTION_FAILED')
                .having((e) => e.message, 'message', contains('first-byte')),
          ),
        );
        expect(disconnected, isTrue, reason: '超时与传输级失败同判：触发 onDisconnect 撕裂');
      } finally {
        _resetSseTimeouts();
      }
    });

    test('SSE-TO-002 流首包后停发 → idle 超时 → CONNECTION_FAILED + onDisconnect', () async {
      SseTimeouts.idle = const Duration(milliseconds: 200);
      try {
        final adapter = MySQLAdapter()
          ..httpClient = _SseFakeClient(
            wireDbType: 'mysql',
            queryHandler: _stalledSseResponse,
          );
        await _bindConnMap('local_mysql_1');
        await adapter.connect(_conn(DatabaseType.mysql, 'local_mysql_1'));
        var disconnected = false;
        adapter.onDisconnect = () => disconnected = true;

        final future = adapter.executeQuery('SELECT 1');
        await expectLater(
          future,
          throwsA(
            isA<MySqlGatewayException>()
                .having((e) => e.code, 'code', 'CONNECTION_FAILED')
                .having((e) => e.message, 'message', contains('idle')),
          ),
        );
        expect(disconnected, isTrue);
      } finally {
        _resetSseTimeouts();
      }
    });

    test('SSE-TO-003 守卫例：keep-alive 持续重置看门狗不误杀；终态到达健康收尾', () async {
      SseTimeouts.idle = const Duration(milliseconds: 400);
      try {
        final controller = StreamController<List<int>>();
        final adapter = MySQLAdapter()
          ..httpClient = _SseFakeClient(
            wireDbType: 'mysql',
            queryHandler: () => _sseFromStream(controller.stream),
          );
        await _bindConnMap('local_mysql_1');
        await adapter.connect(_conn(DatabaseType.mysql, 'local_mysql_1'));

        var state = 'pending';
        Object? err;
        final future = adapter.executeQuery('SELECT 1').then<void>(
          (_) {
            state = 'ok';
          },
          onError: (Object e) {
            err = e;
            state = 'error';
          },
        );

        // 10 个 idle 窗口的 2.5 倍时长（每 100ms 一条 `:` keep-alive 注释行，
        // 间隔 < idle=400ms，看门狗持续重置）。
        for (var i = 0; i < 10; i++) {
          controller.add(utf8.encode(': keep-alive\n'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          state,
          'pending',
          reason: '守卫例③：keep-alive 行持续重置 idle 看门狗——长于 idle 的'
              '时长（1s = 2.5×idle）后仍在等待，不误杀慢查询',
        );

        // 终态到达 + 流关闭 → 健康收尾（total 不截健康慢流）。聚合版
        // toList 等流 done——complete 事件后必须 close 控制器才能收尾。
        controller.add(utf8.encode(
          'event: complete\n'
          'data: {"kind":"sql","type":"complete","rowCount":0,'
          '"truncated":false,"elapsedMs":1}\n\n',
        ));
        await controller.close();
        await future;
        expect(state, 'ok');
        expect(err, isNull);
      } finally {
        _resetSseTimeouts();
      }
    });

    test('SSE-TO-004 total 兜底：只发 keep-alive 永不终态 → total 处 CONNECTION_FAILED', () async {
      // idle 拉长（2s）防先触发；total 缩短注入（400+100=500ms）。
      SseTimeouts.idle = const Duration(seconds: 2);
      SseTimeouts.serverCeiling = const Duration(milliseconds: 400);
      SseTimeouts.buffer = const Duration(milliseconds: 100);
      try {
        final adapter = MySQLAdapter()
          ..httpClient = _SseFakeClient(
            wireDbType: 'mysql',
            queryHandler: () => _sseFromStream(_keepAliveForever()),
          );
        await _bindConnMap('local_mysql_1');
        await adapter.connect(_conn(DatabaseType.mysql, 'local_mysql_1'));

        var state = 'pending';
        Object? err;
        final future = adapter.executeQuery('SELECT 1').then<void>(
          (_) {
            state = 'ok';
          },
          onError: (Object e) {
            err = e;
            state = 'error';
          },
        );

        // 无 extra.timeout → totalFor(null) = 缩短注入 400ms+100ms = 500ms。
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(
          state,
          'pending',
          reason: 'keep-alive 持续期间不被 total 提前截断（不误杀）',
        );

        await future.timeout(const Duration(seconds: 3));
        expect(state, 'error');
        expect(
          err,
          isA<MySqlGatewayException>()
              .having((e) => e.code, 'code', 'CONNECTION_FAILED')
              .having((e) => e.message, 'message', contains('total')),
          reason: '「只发 keep-alive 永不终态」的极端病态由 total 层兜底',
        );
      } finally {
        _resetSseTimeouts();
      }
    });
  });

  group('gateway_backing 生成器版（模板深化）', () {
    test('SSE-TO-005 send 永挂 → first-byte 超时 → ExecutionError(CONNECTION_FAILED)', () async {
      SseTimeouts.firstByte = const Duration(milliseconds: 200);
      try {
        final backing = GatewayBacking(
          httpClient: _SseFakeClient(wireDbType: 'mysql', hangQuery: true),
        );
        final session = backing.execute(
          'srv-1',
          const ExecutionRequest(sql: 'SELECT 1'),
        );
        final chunks = <ExecutionChunk>[];
        final sub = session.chunks.listen(chunks.add);

        // first-byte 200ms + 余量；listen 的 onError 由 chunks 流自身承载
        // （生成器版超时经 catch 转 ExecutionError yield，非流错误）。
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await sub.cancel();

        final errors = chunks.whereType<ExecutionError>().toList();
        expect(errors, hasLength(1), reason: '激活既有 on TimeoutException 分支');
        expect(errors.first.code, 'CONNECTION_FAILED');
        expect(errors.first.message, contains('first-byte'));
      } finally {
        _resetSseTimeouts();
      }
    });

    test('SSE-TO-006 流首包后停发 → idle 超时 → ExecutionError(CONNECTION_FAILED)', () async {
      SseTimeouts.idle = const Duration(milliseconds: 200);
      try {
        final backing = GatewayBacking(
          httpClient: _SseFakeClient(
            wireDbType: 'mysql',
            queryHandler: _stalledSseResponse,
          ),
        );
        final session = backing.execute(
          'srv-1',
          const ExecutionRequest(sql: 'SELECT 1'),
        );
        final chunks = <ExecutionChunk>[];
        final sub = session.chunks.listen(chunks.add);

        await Future<void>.delayed(const Duration(milliseconds: 800));
        await sub.cancel();

        final errors = chunks.whereType<ExecutionError>().toList();
        expect(errors, hasLength(1));
        expect(errors.first.code, 'CONNECTION_FAILED');
        expect(errors.first.message, contains('idle'));
      } finally {
        _resetSseTimeouts();
      }
    });

    test('SSE-TO-007 守卫例：keep-alive 持续泵流仍无 total 超时（生成器版无 total 层）', () async {
      // idle 拉长防干扰；泵流 700ms。serverCeiling/buffer 缩短注入使
      // 「若存在 total 层（400ms）必触发」——生成器版刻意不接 total 层
      // （D3 裁决），keep-alive 持续时永不 total 超时。
      // 终态用健康 complete 收尾而非 sub.cancel()——规避 async* 生成器
      // 驻留 await-for 时取消的挂起面（实证会卡死 30s 测试超时）。
      SseTimeouts.idle = const Duration(seconds: 2);
      SseTimeouts.serverCeiling = const Duration(milliseconds: 300);
      SseTimeouts.buffer = const Duration(milliseconds: 100);
      final controller = StreamController<List<int>>();
      Timer? kaTimer;
      StreamSubscription<ExecutionChunk>? sub;
      try {
        var kaCount = 0;
        kaTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
          kaCount++;
          controller.add(utf8.encode(': keep-alive\n'));
        });
        final backing = GatewayBacking(
          httpClient: _SseFakeClient(
            wireDbType: 'mysql',
            queryHandler: () => _sseFromStream(controller.stream),
          ),
        );
        final session = backing.execute(
          'srv-1',
          const ExecutionRequest(sql: 'SELECT 1'),
        );
        final chunks = <ExecutionChunk>[];
        final done = Completer<void>();
        sub = session.chunks.listen(
          chunks.add,
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );

        // 泵过「若存在 total 层（注入 400ms）必触发」的时长。
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(
          chunks.whereType<ExecutionError>(),
          isEmpty,
          reason: '生成器版无 total 层：keep-alive 持续时不得抛 total 超时',
        );
        expect(
          kaCount,
          greaterThan(10),
          reason: '行持续被消费 = 流与生成器全程存活',
        );

        // 健康终态收尾：complete 事件 + 关流 → 生成器 yield
        // ExecutionComplete 后返回，chunks 流正常 done。
        kaTimer.cancel();
        kaTimer = null;
        controller.add(utf8.encode(
          'event: complete\n'
          'data: {"kind":"sql","type":"complete","rowCount":0,'
          '"truncated":false,"elapsedMs":1}\n\n',
        ));
        await controller.close();
        await done.future.timeout(const Duration(seconds: 3));
        expect(chunks.whereType<ExecutionError>(), isEmpty);
        expect(
          chunks.whereType<ExecutionComplete>(),
          hasLength(1),
          reason: 'keep-alive 长跑后健康终态正常到达',
        );
      } finally {
        kaTimer?.cancel();
        // 不 await：生成器正常路径已在 done.future 收尾；异常路径下
        // cancel 若遇 async* 驻留面也不拖挂 finally。
        unawaited(sub?.cancel());
        _resetSseTimeouts();
      }
    });
  });

  group('其余 6 个网关壳 adapter（stall 注入，各 ≥1 例）', () {
    // 动态分派仅限本脚手架（7 个 adapter 的 connect/onDisconnect/查询入口
    // 无公共基类面；typed exception 断言经 T/codeOf/messageOf 保持静态类型）。
    // ignore_for_file: avoid_dynamic_calls
    //
    // [wrappedInGenericException]：mongodb 的 executeQuery 把所有异常包进
    // `Exception('MongoDB 查询执行失败: $e')`（既有行为，本批不动）——
    // 该路径断言外层 Exception 的文本同时含 CONNECTION_FAILED 与层名；
    // onDisconnect 在内层 catch 已先于包装触发，照常断言。
    void registerIdleStallCase<T extends Exception>({
      required String number,
      required String dbName,
      required DatabaseType dbType,
      required String wireDbType,
      required String localId,
      required dynamic Function(http.Client client) makeAdapter,
      required String Function(T e) codeOf,
      required String Function(T e) messageOf,
      required Future<dynamic> Function(dynamic adapter) runQuery,
      bool wrappedInGenericException = false,
    }) {
      test('$number $dbName：流首包后停发 → idle 超时 CONNECTION_FAILED + onDisconnect', () async {
        SseTimeouts.idle = const Duration(milliseconds: 200);
        try {
          final adapter = makeAdapter(
            _SseFakeClient(
              wireDbType: wireDbType,
              queryHandler: _stalledSseResponse,
            ),
          );
          await _bindConnMap(localId);
          await adapter.connect(_conn(dbType, localId));
          var disconnected = false;
          adapter.onDisconnect = () => disconnected = true;

          final future = runQuery(adapter);
          if (wrappedInGenericException) {
            await expectLater(
              future,
              throwsA(
                isA<Exception>()
                    .having(
                      (e) => e.toString(),
                      'text',
                      contains('CONNECTION_FAILED'),
                    )
                    .having((e) => e.toString(), 'text', contains('idle')),
              ),
            );
          } else {
            await expectLater(
              future,
              throwsA(
                isA<T>()
                    .having((e) => codeOf(e), 'code', 'CONNECTION_FAILED')
                    .having((e) => messageOf(e), 'message', contains('idle')),
              ),
            );
          }
          expect(disconnected, isTrue);
        } finally {
          _resetSseTimeouts();
        }
      });
    }

    registerIdleStallCase<PostgreSqlGatewayException>(
      number: 'SSE-TO-008',
      dbName: 'postgresql',
      dbType: DatabaseType.postgresql,
      wireDbType: 'postgresql',
      localId: 'local_pg_1',
      makeAdapter: (client) => PostgreSQLAdapter()..httpClient = client,
      codeOf: (e) => e.code,
      messageOf: (e) => e.message,
      runQuery: (adapter) => adapter.executeQuery('SELECT 1'),
    );
    registerIdleStallCase<SqlServerGatewayException>(
      number: 'SSE-TO-009',
      dbName: 'sqlserver',
      dbType: DatabaseType.sqlserver,
      wireDbType: 'sqlserver',
      localId: 'local_ss_1',
      makeAdapter: (client) => SqlServerAdapter()..httpClient = client,
      codeOf: (e) => e.code,
      messageOf: (e) => e.message,
      runQuery: (adapter) => adapter.executeQuery('SELECT 1'),
    );
    registerIdleStallCase<ClickhouseGatewayException>(
      number: 'SSE-TO-010',
      dbName: 'clickhouse',
      dbType: DatabaseType.clickhouse,
      wireDbType: 'clickhouse',
      localId: 'local_ch_1',
      makeAdapter: (client) => ClickhouseAdapter()..httpClient = client,
      codeOf: (e) => e.code,
      messageOf: (e) => e.message,
      runQuery: (adapter) => adapter.executeQuery('SELECT 1'),
    );
    registerIdleStallCase<MongoGatewayException>(
      number: 'SSE-TO-011',
      dbName: 'mongodb',
      dbType: DatabaseType.mongodb,
      wireDbType: 'mongodb',
      localId: 'local_mongo_1',
      makeAdapter: (client) => MongoDBAdapter()..httpClient = client,
      codeOf: (e) => e.code,
      messageOf: (e) => e.message,
      runQuery: (adapter) => adapter.executeQuery('db.users.find()'),
      wrappedInGenericException: true,
    );
    registerIdleStallCase<TdengineGatewayException>(
      number: 'SSE-TO-012',
      dbName: 'tdengine',
      dbType: DatabaseType.tdengine,
      wireDbType: 'tdengine',
      localId: 'local_td_1',
      makeAdapter: (client) => TDengineAdapter()..httpClient = client,
      codeOf: (e) => e.code,
      messageOf: (e) => e.message,
      runQuery: (adapter) => adapter.executeQuery('SELECT 1'),
    );
    registerIdleStallCase<RedisGatewayException>(
      number: 'SSE-TO-013',
      dbName: 'redis runCommand',
      dbType: DatabaseType.redis,
      wireDbType: 'redis',
      localId: 'local_redis_1',
      makeAdapter: (client) => RedisAdapter()..httpClient = client,
      codeOf: (e) => e.code,
      messageOf: (e) => e.message,
      runQuery: (adapter) => adapter.runCommand(['PING']),
    );
    registerIdleStallCase<RedisGatewayException>(
      number: 'SSE-TO-014',
      dbName: 'redis pipeline（getKeyTypes）',
      dbType: DatabaseType.redis,
      wireDbType: 'redis',
      localId: 'local_redis_1',
      makeAdapter: (client) => RedisAdapter()..httpClient = client,
      codeOf: (e) => e.code,
      messageOf: (e) => e.message,
      runQuery: (adapter) => adapter.getKeyTypes(['k1']),
    );
  });
}
