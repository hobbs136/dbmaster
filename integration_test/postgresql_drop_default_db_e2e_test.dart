// ============================================================================
// INT-DDF-PG-001/002 — DDF 批（2026-10-14）：删除已注册默认库后连接必须不断开
// （PostgreSQL 真库 e2e，与 MySQL 侧 T5 同构）。
//
// 用户报告（任务书 .specs/tasks-drop-db-disconnect-fix.md §1）：连接配置默认库
// X，DROP X 成功，但客户端连接状态被断开。因果链：drop 成功后的
// refreshDatabases()（≤10s 后 keepalive 同路径）发起无库 catalog 查询 →
// server 回落注册的 stale default_database → open_pg_db 3D000 →
// CONNECTION_FAILED → 壳把每语句 DB open 失败误当会话死亡撕连接。
//
// 被测修复（前置 T1+T3，均已落地）：
//   T1 server：客户端未指定 database 且注册默认库 open 失败 → 无库重试一次
//     （PG 回落 postgres 维护库，stream_query.rs stale_default_retry_eligible）；
//   T3 壳：postgresql_gateway_adapter 仅 NOT_FOUND 立即撕连接，
//     CONNECTION_FAILED 降级为查询级错误（交外层自愈 + keepalive 收口）。
//
// INT-DDF-PG-001（主用例）：默认库 = 专用库 dbmaster_ddf_<ts>，drop 它 →
//   连接仍已连接、事件流无 ConnectionDisconnected、无库 SELECT 1 正常
//   （keepalive 同路径）、getDatabases() 成功且不含该库。
// INT-DDF-PG-002（对照）：默认库 A + 另建库 B，drop B → 连接不断、查询正常
//   （钉住矩阵「删非默认库不受影响」行）。
//
// PG 特有（任务书 T6 节）：所有种子/清理连接必须显式 database:'postgres'
// （PG 无「无库」语义）；drop 由壳内部走维护库路由，测试只调
// provider.dropDatabase。
//
// 确定性说明（任务书 T5/T6 要点 4）：不等真实 10s 心跳 tick——refreshDatabases
// 在 drop 途中被同步触发即覆盖最早期触发点，用例内再显式 await 同一通路 +
// 无库 executeQuery 直连覆盖 keepalive 同路径。
//
// 清理结构说明：清理写在用例体末尾而非 tearDown——排干 fire-and-forget 刷新
// 需要 tester.pumpAndSettle（网关时序，同 mysql_readonly_drop_database_test
// 惯例），tearDown 拿不到 tester。
// Target: real PostgreSQL via DBMASTER_PG_* (see config/postgresql_test_config.dart)
// ============================================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/postgresql_test_config.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

void main() {
  // T29 第二批：PG 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 PG_E2E_SKIP 跳过（无假绿）。
  bool pgE2EGatewayReady = false;
  setUpAll(() async {
    pgE2EGatewayReady = await ensureEmbeddedServerForPgE2E();
    if (pgE2EGatewayReady && !PostgreSQLTestConfig.available) {
      // ignore: avoid_print
      print('PG_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      pgE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 专用库名：DDF 批次前缀 + 时间戳（任务书 T6 要点：dbmaster_ddf_<ts>）。
  String generateDdfDatabaseName() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'dbmaster_ddf_$ts';
  }

  /// 经维护库连接（显式 database:'postgres'）建专用库；返回的 adapter 留作
  /// 存在性核验与清理复用。
  Future<PostgreSQLAdapter> seedDatabase(String dbName) async {
    final adapter = PostgreSQLAdapter();
    await adapter.connect(
      DatabaseConnection(
        id: 'ddf_seed_${dbName.hashCode}',
        name: 'DDF Seed',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      ),
    );
    await adapter.createDatabase(dbName);
    return adapter;
  }

  Future<bool> databaseExists(PostgreSQLAdapter adapter, String dbName) async {
    final dbs = await adapter.getDatabases();
    return dbs.contains(dbName);
  }

  /// 构造 AppProvider 并以「默认库 = <dbName>」注册连接——这正是复现条件：
  /// server 侧 default_database 指向将被删除的库。
  Future<({AppProvider provider, DbServer server})>
      connectProviderWithDefaultDatabase(String dbName) async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppProvider();
    AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
    final server = DbServer(
      id: 'pg_ddf_${dbName.hashCode}',
      name: 'PG DDF Test',
      type: DatabaseType.postgresql,
      host: PostgreSQLTestConfig.host,
      port: PostgreSQLTestConfig.port,
      username: PostgreSQLTestConfig.username,
      password: PostgreSQLTestConfig.password,
      database: dbName,
    );
    await provider.connection.saveConnection(server);
    final connected = await provider.connectToServer(server);
    expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');
    await provider.refreshDatabases();
    return (provider: provider, server: server);
  }

  /// 订阅 dbService 连接事件广播流；同时收集流级错误（listen 必须带 onError，
  /// 记录下来在存活断言里一并核验为空）。
  StreamSubscription<ConnectionEvent> subscribeConnectionEvents(
    AppProvider provider,
    List<ConnectionEvent> events,
    List<Object> streamErrors,
  ) {
    return provider.dbService.events.listen(events.add, onError: streamErrors.add);
  }

  /// 核销「删库后连接存活」四断言（任务书 T5/T6 要点 2）：
  /// ① adapter 仍在 dbService 且连接态未拆（UI 状态非断开）
  /// ② 事件流无 ConnectionDisconnected、无流级错误
  /// ③ 无库 SELECT 1 正常（database_service 心跳即
  ///    adapter.executeQuery('SELECT 1') 无库参数，等价 keepalive 路径）
  /// ④ getDatabases() 成功且不含被删库（[stillPresent] 提供时额外断言仍在）
  Future<void> assertConnectionSurvivedDrop({
    required AppProvider provider,
    required DbServer server,
    required String droppedDb,
    required List<ConnectionEvent> events,
    required List<Object> streamErrors,
    String? stillPresent,
  }) async {
    // ①
    final adapter = provider.dbService.getAdapter(server.id);
    expect(adapter, isNotNull, reason: '删库后 adapter 仍应注册在 dbService');
    // 上方 expect 已证非空（AGENTS.md MAY：可证明非空的谨慎 !）。
    expect(adapter!.isConnected, isTrue, reason: '删库后 adapter 连接态不应拆除');
    expect(
      provider.isConnectionConnected(server.id),
      isTrue,
      reason: 'UI 连接状态不应显示断开',
    );

    // ②
    final disconnects = events.whereType<ConnectionDisconnected>().toList();
    expect(
      disconnects,
      isEmpty,
      reason: '不应广播任何 ConnectionDisconnected 事件'
          '（${disconnects.map((e) => e.connectionId).toList()}）',
    );
    expect(streamErrors, isEmpty, reason: '连接事件流不应出错');

    // ③
    final result = await adapter.executeQuery('SELECT 1');
    expect(result.rows, isNotEmpty, reason: '无库 SELECT 1 应正常返回');

    // ④
    final dbs = await provider.dbService.getDatabases();
    expect(
      dbs,
      isNot(contains(droppedDb)),
      reason: 'getDatabases 应成功且不含已删除的库',
    );
    if (stillPresent != null) {
      expect(dbs, contains(stillPresent), reason: '默认库 $stillPresent 应仍在');
    }
  }

  /// Best-effort 清场：排干在途异步 → 取消订阅 → 断开 provider → 显式
  /// database:'postgres' 维护连接回收残留库 → dispose。绝不依赖用例间顺序。
  Future<void> cleanupDdf({
    required WidgetTester tester,
    required PostgreSQLAdapter cleanupAdapter,
    required AppProvider provider,
    required DbServer server,
    required StreamSubscription<ConnectionEvent> subscription,
    required List<String> dbNames,
  }) async {
    // 网关时序：dropDatabase 成功后 fire-and-forget 的 refreshDatabases 是
    // 异步 HTTP，落点晚于 cleanup 的 dispose——先 pump 干净再清场。
    try {
      await tester.pumpAndSettle(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await subscription.cancel();
    } catch (_) {}
    try {
      await provider.disconnectConnection(connectionId: server.id);
    } catch (_) {}
    for (final db in dbNames) {
      try {
        await cleanupAdapter.executeQuery('DROP DATABASE IF EXISTS "$db"');
      } catch (_) {}
    }
    try {
      await cleanupAdapter.disconnect();
    } catch (_) {}
    try {
      provider.dispose();
    } catch (_) {}
  }

  group('PostgreSQL drop default DB keeps connection (DDF)', () {
    testWidgets('INT-DDF-PG-001: dropping the registered default database '
        'does not disconnect', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final defaultDb = generateDdfDatabaseName();
      final cleanupAdapter = await seedDatabase(defaultDb);
      final (:provider, :server) =
          await connectProviderWithDefaultDatabase(defaultDb);

      final events = <ConnectionEvent>[];
      final streamErrors = <Object>[];
      final subscription =
          subscribeConnectionEvents(provider, events, streamErrors);

      // 删默认库（壳内部走维护库路由，测试只调 provider.dropDatabase）。
      final dropped = await provider.dropDatabase(defaultDb);
      expect(dropped, isTrue, reason: 'dropDatabase 应成功');

      // 确定性：refreshDatabases 已在 drop 途中同步触发（最早期触发点），
      // 显式 await 同一通路完整结算，再排干在途异步后断言。
      await provider.refreshDatabases();
      try {
        await tester.pumpAndSettle(const Duration(seconds: 3));
      } catch (_) {}

      await assertConnectionSurvivedDrop(
        provider: provider,
        server: server,
        droppedDb: defaultDb,
        events: events,
        streamErrors: streamErrors,
      );
      expect(
        await databaseExists(cleanupAdapter, defaultDb),
        isFalse,
        reason: '专用库应确实被删除（drop 真生效，而非测试空转）',
      );

      await cleanupDdf(
        tester: tester,
        cleanupAdapter: cleanupAdapter,
        provider: provider,
        server: server,
        subscription: subscription,
        dbNames: [defaultDb],
      );
    });

    testWidgets('INT-DDF-PG-002: dropping a non-default database keeps the '
        'connection (control)', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final defaultDb = generateDdfDatabaseName();
      final otherDb = '${defaultDb}_b';
      final cleanupAdapter = await seedDatabase(defaultDb);
      await cleanupAdapter.createDatabase(otherDb);
      final (:provider, :server) =
          await connectProviderWithDefaultDatabase(defaultDb);

      final events = <ConnectionEvent>[];
      final streamErrors = <Object>[];
      final subscription =
          subscribeConnectionEvents(provider, events, streamErrors);

      // 删非默认库 B（默认库 A 不动）。
      final dropped = await provider.dropDatabase(otherDb);
      expect(dropped, isTrue, reason: 'dropDatabase(B) 应成功');

      await provider.refreshDatabases();
      try {
        await tester.pumpAndSettle(const Duration(seconds: 3));
      } catch (_) {}

      await assertConnectionSurvivedDrop(
        provider: provider,
        server: server,
        droppedDb: otherDb,
        events: events,
        streamErrors: streamErrors,
        stillPresent: defaultDb,
      );

      await cleanupDdf(
        tester: tester,
        cleanupAdapter: cleanupAdapter,
        provider: provider,
        server: server,
        subscription: subscription,
        dbNames: [defaultDb, otherDb],
      );
    });
  });
}
