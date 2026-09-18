// ============================================================================
// C13 · port 执行通道真库 E2E（embedded server + T27 网关 SSE）。
// ----------------------------------------------------------------------------
// GatewayBacking.execute 的流式语义在真实链路上的守卫（单测 mock 之外的
// server 实行为）：
// - C13-SSE-001 流式块序：meta 先于 rows/complete 到达、行批累计 =
//   complete.rowCount、位置数组行与 meta 列序对齐；
// - C13-CXL-001 取消语义：WAITFOR 长查询进行中 cancel() → server 以
//   error(CANCELLED) 终态收流（契约 §2.1「取消必须可达服务端」）。
//
// 前置：embedded dbmaster-server（DBMASTER_SERVER_BIN）+ 测试库
// 真实 SQL Server 可达（DBMASTER_SQLSERVER_* 提供）；缺任一则以可 grep 的 C13_E2E_SKIP 跳过。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/ports/gateway_backing.dart';
import 'package:dbmaster/services/ports/port_types.dart';
import 'config/sqlserver_test_config.dart';
import 'helpers/ss_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool ready = false;
  setUpAll(() async {
    ready = await ensureEmbeddedServerForSsE2E();
    if (ready && !SQLServerTestConfig.available) {
      // ignore: avoid_print
      print('SS_E2E_SKIP: DBMASTER_SQLSERVER_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      ready = false;
    }
  });

  testWidgets('C13-SSE-001: streaming chunks (meta first, rows accumulate to complete)', (tester) async {
    if (!ready) return;
    final backing = GatewayBacking();

    final serverConnId = await _registerSsConnection(backing);
    if (serverConnId == null) {
      // ignore: avoid_print
      print('C13_E2E_SKIP: register SS connection failed');
      return;
    }

    try {
      final session = backing.execute(
        serverConnId,
        const ExecutionRequest(
          // sys.all_columns 在任意库可见（master 系统表列数上千）——rowLimit
          // 600 让 server 分批下发多 rows 块 + truncated 语义可见。
          sql: 'SELECT column_id, name FROM sys.all_columns',
          database: 'master',
          rowLimit: 600,
        ),
      );

      final chunks = await session.chunks.toList();
      final types = chunks.map((c) => c.type).toList();

      // 块序契约：首块 meta，终块 complete，中间 rows ≥ 1 批。
      expect(types.first, ExecutionChunkType.meta,
          reason: 'meta 必须先于一切数据块');
      expect(types.last, ExecutionChunkType.complete);
      expect(types.where((t) => t == ExecutionChunkType.rows).length,
          greaterThanOrEqualTo(1));

      final meta = chunks.first as ExecutionMeta;
      expect(meta.columns, ['column_id', 'name']);

      // 行批累计 = complete.rowCount；位置数组长度 = 列数。
      var accumulated = 0;
      for (final chunk in chunks) {
        if (chunk is ExecutionRows) {
          for (final row in chunk.rows) {
            expect(row.length, 2, reason: '位置数组行与 meta 列序对齐');
          }
          accumulated += chunk.rows.length;
        }
      }
      final complete = chunks.last as ExecutionComplete;
      expect(complete.rowCount, accumulated,
          reason: 'complete.rowCount 必须等于累计行数');
      expect(complete.rowCount, 600,
          reason: 'sys.all_columns 行数充足，应被 rowLimit 截到 600');
      expect(complete.truncated, isTrue,
          reason: 'rowCount >= rowLimit 的保守截断判据');
    } finally {
      await _cleanup(backing, serverConnId);
    }
  });

  testWidgets('C13-CXL-001: cancel() aborts long query with error(CANCELLED)', (tester) async {
    if (!ready) return;
    final backing = GatewayBacking();

    final serverConnId = await _registerSsConnection(backing);
    if (serverConnId == null) {
      // ignore: avoid_print
      print('C13_E2E_SKIP: register SS connection failed');
      return;
    }

    try {
      final session = backing.execute(
        serverConnId,
        const ExecutionRequest(
          sql: "WAITFOR DELAY '00:01:00'",
          database: 'master',
          timeout: Duration(seconds: 60),
        ),
      );

      final watch = Stopwatch()..start();
      // 流启动后短暂等待（执行任务注册 + 开始计时）再取消。
      final chunksFuture = session.chunks.toList();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await session.cancel();
      final chunks = await chunksFuture.timeout(
        const Duration(seconds: 15),
        onTimeout: () => fail('cancel 后流未在 15s 内终态'),
      );
      watch.stop();

      expect(chunks.whereType<ExecutionError>().length, 1,
          reason: '取消应以单个 error 终态事件收流');
      final err = chunks.whereType<ExecutionError>().single;
      expect(err.code, 'CANCELLED',
          reason: 'server 取消路径的稳定码（stream_query.rs cancelled()）');
      // WAITFOR 60s 未跑满即被取消（含执行启动余量；对照 #30 守卫口径放宽上限）。
      expect(watch.elapsed.inSeconds, lessThan(50),
          reason: 'cancel 应即时中断长查询，实际耗时 ${watch.elapsed}');
    } finally {
      await _cleanup(backing, serverConnId);
    }
  });
}

/// 注册 SS 连接到网关（凭据入 vault），返回 serverConnId；失败返回 null。
Future<String?> _registerSsConnection(GatewayBacking backing) async {
  try {
    return await backing.persistConnection(DbServer(
      id: 'c13_e2e_ss',
      name: 'c13_e2e_ss',
      type: DatabaseType.sqlserver,
      host: SQLServerTestConfig.host,
      port: SQLServerTestConfig.port,
      username: SQLServerTestConfig.username,
      password: SQLServerTestConfig.password,
      database: 'master',
    ));
  } catch (_) {
    return null;
  }
}

Future<void> _cleanup(GatewayBacking backing, String serverConnId) async {
  try {
    await backing.removeConnection(serverConnId);
  } catch (_) {}
}
