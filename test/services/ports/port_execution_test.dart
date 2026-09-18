// =============================================================================
// C13 · port 执行通道单测（GatewayBacking 真 SSE 流式 / AdapterBacking 包装）。
// =============================================================================
// Mock HTTP 层（可分段推送的 SSE 假流 + 请求记录），验证：
// - 请求形状：POST /api/gw/connections/{id}/query + X-Execution-Id（合法
//   UUID，server 侧注册表校验）+ camelCase 体（sql/database/schema/rowLimit/
//   timeoutMs）+ Bearer；
// - 块流语义：meta → rows*（真流式——行批到达即下发）→ complete|error 终态
//   关流；前置 4xx → ExecutionError 块（不抛）；流裸断 → CONNECTION_FAILED；
// - 取消：cancel() → DELETE /api/gw/executions/{id}（幂等，二次不再发）；
// - AdapterBacking：executeQuery 现状结果 → 单批 meta/rows/complete 块流，
//   异常 → ExecutionError(DB_ERROR)；cancel 幂等 no-op。
// =============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/ports/adapter_backing.dart';
import 'package:dbmaster/services/ports/gateway_backing.dart';
import 'package:dbmaster/services/ports/port_types.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 可编程 SSE 假流客户端：handler 收到请求后返回一个由 [StreamController]
/// 驱动的 body 流（测试逐步推事件，验证「行批到达即下发」的真流式语义）。
class _SseClient extends http.BaseClient {
  _SseClient(this.onRequest);

  final Future<void> Function(
    http.Request request,
    StreamController<List<int>> sink,
  ) onRequest;

  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final req = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;
    requests.add(req);

    final controller = StreamController<List<int>>();
    unawaited(onRequest(req, controller));
    return http.StreamedResponse(
      controller.stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}

/// SSE 事件行（契约 §4.2：event:/data: + 空行分隔）。
List<int> sse(String event, Object data) =>
    utf8.encode('event: $event\ndata: ${jsonEncode(data)}\n\n');

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

/// 简单 JSON 响应客户端（前置 4xx 等非流场景 + DELETE 取消）。
class _JsonClient extends http.BaseClient {
  _JsonClient(this.handler);

  final http.Response Function(http.Request request) handler;
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();
    final req = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bodyBytes;
    requests.add(req);
    final resp = handler(req);
    return http.StreamedResponse(
      Stream.value(resp.bodyBytes),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

GatewayBacking _embedded(http.Client client, {int port = 45673}) {
  ServerConnection.resetForTesting();
  ServerConnection().connectEmbedded(
    port: port,
    accessToken: 'emb-token',
    refreshToken: 'emb-refresh',
    installUuid: 'uuid',
    version: '0.1.0',
  );
  return GatewayBacking(httpClient: client);
}

/// 只覆写 executeQuery 的 DatabaseService 假体（C13 包装路径的现状语义）。
class _FakeDatabaseService extends DatabaseService {
  List<Map<String, dynamic>>? nextRows;
  Object? nextError;

  String? lastSql;
  String? lastConnectionId;
  String? lastDatabase;

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    lastSql = sql;
    lastConnectionId = connectionId;
    lastDatabase = database;
    if (nextError != null) throw nextError!;
    return nextRows ?? const [];
  }
}

void main() {
  setUp(() => ServerConnection.resetForTesting());
  tearDown(() => ServerConnection.resetForTesting());

  group('GWY-C13 · execute 请求形状', () {
    test('POST /api/gw/connections/{id}/query + 合法 UUID + camelCase 体', () async {
      String? seenExecutionId;
      late http.Request captured;
      final client = _SseClient((req, sink) async {
        captured = req;
        seenExecutionId = req.headers['X-Execution-Id'];
        sink.add(sse('meta', {
          'kind': 'sql',
          'type': 'meta',
          'columns': ['x'],
        }));
        await sink.close();
      });
      final backing = _embedded(client);

      final session = backing.execute(
        'srv_conn_1',
        const ExecutionRequest(
          sql: 'SELECT x FROM t',
          database: 'appdb',
          schema: 'dbo',
          rowLimit: 500,
          timeout: Duration(seconds: 30),
        ),
      );
      await session.chunks.toList();

      expect(captured.method, 'POST');
      expect(
        captured.url.toString(),
        'http://127.0.0.1:45673/api/gw/connections/srv_conn_1/query',
      );
      expect(captured.headers['Authorization'], 'Bearer emb-token');
      expect(seenExecutionId, matches(_uuidPattern),
          reason: 'X-Execution-Id 须为合法 UUID（server 注册表校验）');
      expect(jsonDecode(captured.body), {
        'sql': 'SELECT x FROM t',
        'database': 'appdb',
        'schema': 'dbo',
        'rowLimit': 500,
        'timeoutMs': 30000,
      });
    });
  });

  group('GWY-C13 · 块流语义', () {
    test('meta → rows* → complete 终态关流（契约 §4.2 四事件）', () async {
      final client = _SseClient((req, sink) async {
        sink.add(sse('meta', {
          'kind': 'sql',
          'type': 'meta',
          'columns': ['id', 'name'],
        }));
        sink.add(sse('rows', {
          'kind': 'sql',
          'type': 'rows',
          'rows': [
            [1, 'Alice'],
            [2, 'Bob'],
          ],
        }));
        sink.add(sse('rows', {
          'kind': 'sql',
          'type': 'rows',
          'rows': [
            [3, null],
          ],
        }));
        sink.add(sse('complete', {
          'kind': 'sql',
          'type': 'complete',
          'rowCount': 3,
          'truncated': false,
          'elapsedMs': 42,
        }));
        await sink.close();
      });
      final backing = _embedded(client);
      final session = backing.execute(
        'srv_conn_1',
        const ExecutionRequest(sql: 'SELECT 1'),
      );
      final chunks = await session.chunks.toList();

      expect(chunks.length, 4);
      final meta = chunks[0] as ExecutionMeta;
      expect(meta.columns, ['id', 'name']);
      final batch1 = chunks[1] as ExecutionRows;
      expect(batch1.rows, [
        [1, 'Alice'],
        [2, 'Bob'],
      ]);
      final batch2 = chunks[2] as ExecutionRows;
      expect(batch2.rows.first, [3, null]);
      final complete = chunks[3] as ExecutionComplete;
      expect(complete.rowCount, 3);
      expect(complete.truncated, isFalse);
      expect(complete.elapsedMs, 42);
    });

    test('真流式：meta 块在终态事件下发前即可收到（不等全量聚合）', () async {
      // 服务端 hold 终态事件直到消费侧确认收到 meta——若实现是「聚合后
      // 一次性下发」，metaSeen 会等到超时。
      final gate = Completer<void>();
      final client = _SseClient((req, sink) async {
        sink.add(sse('meta', {
          'kind': 'sql',
          'type': 'meta',
          'columns': ['x'],
        }));
        await gate.future;
        sink.add(sse('complete', {
          'kind': 'sql',
          'type': 'complete',
          'rowCount': 0,
          'truncated': false,
          'elapsedMs': 1,
        }));
        await sink.close();
      });
      final backing = _embedded(client);
      final session = backing.execute(
        'srv_conn_1',
        const ExecutionRequest(sql: 'SELECT 1'),
      );

      final metaSeen = Completer<void>();
      final done = Completer<void>();
      session.chunks.listen((chunk) {
        if (chunk is ExecutionMeta && !metaSeen.isCompleted) {
          metaSeen.complete();
        }
      }, onDone: () {
        if (!done.isCompleted) done.complete();
      });

      await metaSeen.future.timeout(const Duration(seconds: 2),
          onTimeout: () => fail('meta 未在终态事件前下发（聚合实现回归）'));
      gate.complete();
      await done.future.timeout(const Duration(seconds: 2));
    });

    test('error 事件 → ExecutionError(code/engineCode) 后流关闭', () async {
      final client = _SseClient((req, sink) async {
        sink.add(sse('error', {
          'kind': 'sql',
          'type': 'error',
          'code': 'DB_ERROR',
          'message': 'Syntax error near FROM',
          'engineCode': '102',
        }));
        await sink.close();
      });
      final backing = _embedded(client);
      final chunks = await backing
          .execute('srv_conn_1', const ExecutionRequest(sql: 'BROKEN'))
          .chunks
          .toList();

      expect(chunks.length, 1);
      final err = chunks.single as ExecutionError;
      expect(err.code, 'DB_ERROR');
      expect(err.message, 'Syntax error near FROM');
      expect(err.engineCode, '102');
    });

    test('前置 4xx（流未开始）→ ExecutionError 块，session 面不抛', () async {
      final client = _JsonClient(
        (req) => http.Response(
          jsonEncode({
            'error': {'code': 'MULTI_STATEMENT', 'message': 'one statement only'},
          }),
          400,
          headers: const {'content-type': 'application/json'},
        ),
      );
      final backing = _embedded(client);
      final chunks = await backing
          .execute('srv_conn_1', const ExecutionRequest(sql: 'A; B'))
          .chunks
          .toList();

      expect(chunks.single, isA<ExecutionError>()
          .having((e) => e.code, 'code', 'MULTI_STATEMENT'));
    });

    test('流裸断（无终态事件）→ ExecutionError(CONNECTION_FAILED)', () async {
      final client = _SseClient((req, sink) async {
        sink.add(sse('meta', {
          'kind': 'sql',
          'type': 'meta',
          'columns': ['x'],
        }));
        // 无 complete/error 直接关流。
        await sink.close();
      });
      final backing = _embedded(client);
      final chunks = await backing
          .execute('srv_conn_1', const ExecutionRequest(sql: 'SELECT 1'))
          .chunks
          .toList();

      expect(chunks.last, isA<ExecutionError>()
          .having((e) => e.code, 'code', 'CONNECTION_FAILED'));
    });

    test('未连接 server → CONFIG 错误块（不抛）', () async {
      ServerConnection.resetForTesting();
      final backing = GatewayBacking(httpClient: _JsonClient((_) => http.Response('', 500)));
      final chunks = await backing
          .execute('srv_conn_1', const ExecutionRequest(sql: 'SELECT 1'))
          .chunks
          .toList();
      expect(chunks.single, isA<ExecutionError>()
          .having((e) => e.code, 'code', 'CONFIG'));
    });
  });

  group('GWY-C13 · 取消', () {
    test('cancel() → DELETE /api/gw/executions/{id}（同 X-Execution-Id；幂等）', () async {
      String? queryExecId;
      final client = _JsonClient((req) {
        if (req.url.path.endsWith('/query')) {
          queryExecId = req.headers['X-Execution-Id'];
          // 空 body 流（无终态事件）→ 裸断兜底块后流结束，不挂测试。
          return http.Response('', 200);
        }
        return http.Response('', 204); // DELETE /executions/{id} 幂等 204
      });
      final backing = _embedded(client);
      final session = backing.execute(
        'srv_conn_1',
        const ExecutionRequest(sql: "WAITFOR DELAY '00:01:00'"),
      );

      // chunks 惰性（async* 不订阅不发出）——先启动流让查询请求落地。
      final chunks = await session.chunks.toList();
      expect(chunks.last, isA<ExecutionError>(),
          reason: '空流应走裸断兜底');
      expect(queryExecId, matches(_uuidPattern));

      await session.cancel();
      await session.cancel(); // 幂等：二次不再发
      final deletes = client.requests
          .where((r) => r.method == 'DELETE')
          .toList();
      expect(deletes.length, 1);
      expect(
        deletes.single.url.path.endsWith('/api/gw/executions/$queryExecId'),
        isTrue,
        reason: '取消句柄与查询的 X-Execution-Id 同源',
      );
    });
  });

  group('ADP-C13 · AdapterBacking 包装块流', () {
    test('现状结果 → meta + 单批 rows + complete（列序 = 首行 keys）', () async {
      final db = _FakeDatabaseService()
        ..nextRows = const [
          {'id': 1, 'name': 'Alice'},
          {'id': 2, 'name': 'Bob'},
        ];
      final backing = AdapterBacking(dbService: db);

      final chunks = await backing
          .execute(
        'conn_local',
        const ExecutionRequest(sql: 'SELECT id, name FROM t', database: 'appdb'),
      )
          .chunks
          .toList();

      // 透传语义：executeQuery 收到原始参数。
      expect(db.lastSql, 'SELECT id, name FROM t');
      expect(db.lastConnectionId, 'conn_local');
      expect(db.lastDatabase, 'appdb');

      expect(chunks.length, 3);
      expect((chunks[0] as ExecutionMeta).columns, ['id', 'name']);
      expect((chunks[1] as ExecutionRows).rows, [
        [1, 'Alice'],
        [2, 'Bob'],
      ]);
      final complete = chunks[2] as ExecutionComplete;
      expect(complete.rowCount, 2);
      expect(complete.truncated, isFalse);
    });

    test('异常 → ExecutionError(DB_ERROR)，不抛', () async {
      final db = _FakeDatabaseService()
        ..nextError = Exception('Connection refused (10061)');
      final backing = AdapterBacking(dbService: db);

      final chunks = await backing
          .execute('conn_local', const ExecutionRequest(sql: 'SELECT 1'))
          .chunks
          .toList();

      expect(chunks.single, isA<ExecutionError>()
          .having((e) => e.code, 'code', 'DB_ERROR')
          .having((e) => e.message, 'message',
              contains('Connection refused')));
    });

    test('空结果 → meta 空列 + 空 rows 批 + complete(0)', () async {
      final backing = AdapterBacking(dbService: _FakeDatabaseService());
      final chunks = await backing
          .execute('conn_local', const ExecutionRequest(sql: 'SELECT 1'))
          .chunks
          .toList();
      expect((chunks[0] as ExecutionMeta).columns, isEmpty);
      expect((chunks[1] as ExecutionRows).rows, isEmpty);
      expect((chunks[2] as ExecutionComplete).rowCount, 0);
    });

    test('cancel 幂等 no-op（本地路径取消走既有 KILL 链路）', () async {
      final backing = AdapterBacking(dbService: _FakeDatabaseService());
      final session = backing
          .execute('conn_local', const ExecutionRequest(sql: 'SELECT 1'));
      await expectLater(session.cancel(), completes);
      await expectLater(session.cancel(), completes);
    });
  });
}
