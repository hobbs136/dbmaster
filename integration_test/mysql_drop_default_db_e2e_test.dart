// ============================================================================
// MySQL Drop Default Database E2E Tests (DDF 修复批, 2026-10-14)
// Cases: INT-DDF-MY-001 (主) / INT-DDF-MY-002 (对照)
// ============================================================================
//
// 用户报告场景（DDF 任务书 §1.1）：连接配置带默认库 X，删除 X 后 DROP 成功，
// 但客户端连接被整体断开。根因 = 无 database 参数的查询（drop 后的
// refreshDatabases 同步触发 + ≤10s keepalive）在 server 侧回落已删除的
// default_database → open 失败误报 CONNECTION_FAILED → 壳立即撕连接。
//
// 本文件端到端钉死修复效果（T1 server stale 默认库自愈 + T2 壳收窄
// CONNECTION_FAILED 不再立即撕）：删掉默认库后——
//   ① 连接仍已连接（adapter 仍在 dbService、currentServer 未被清）；
//   ② dbService 事件流无 ConnectionDisconnected；
//   ③ 无 database 参数的 executeQuery('SELECT 1')（等价 keepalive 路径）正常；
//   ④ getDatabases() 成功且不含已删库。
//
// 为什么不等真实 10s 心跳：refreshDatabases 在 dropDatabase 返回 true 的
// 途中同步触发（app_provider.dart dropDatabase → connection.refreshDatabases），
// 是比心跳更早的触发点；无库 executeQuery 直连覆盖的是与心跳完全相同的
// 请求路径（壳发 catalog/SELECT 1 均不带 database 字段）。确定性优先。
//
// Requires: real MySQL (DBMASTER_MYSQL_*) + embedded server
// (DBMASTER_SERVER_BIN)。二进制不可得/未配库时以可 grep 的 MYSQL_E2E_SKIP
// 跳过（FR-011 无假绿纪律）。
// ============================================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

void main() {
  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MySQL Drop Default DB E2E (DDF)', () {
    late AppProvider appProvider;
    // 独立种子/清理 adapter：不配默认库（database 省略）——与被测连接隔离，
    // 默认库被删后仍能用它回收残留库。
    late MySQLAdapter cleanupAdapter;
    late String defaultDbName; // 连接配置的默认库 X（001 被删 / 002 保留）
    late String otherDbName; // 对照库 B（002 被删）
    late DbServer server;

    final disconnectedEvents = <ConnectionDisconnected>[];
    final eventStreamErrors = <Object>[];
    StreamSubscription<ConnectionEvent>? eventSub;

    setUp(() async {
      // AG-F-19：prefs 隔离（金标准模板同款）——mock 存储，杜绝直写用户偏好。
      SharedPreferences.setMockInitialValues({});
      if (!mysqlE2EGatewayReady) return;

      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      final rand = Random().nextInt(0x10000).toRadixString(16).padLeft(4, '0');
      final base =
          'dbmaster_ddf_${DateTime.now().millisecondsSinceEpoch}_$rand';
      defaultDbName = base;
      otherDbName = '${base}_b';
      disconnectedEvents.clear();
      eventStreamErrors.clear();

      cleanupAdapter = MySQLAdapter();
      await cleanupAdapter.connect(
        DatabaseConnection(
          id: 'ddf_seed_$base',
          name: 'DDF Seed Connection',
          type: DatabaseType.mysql,
          host: MySQLTestConfig.host,
          port: MySQLTestConfig.port,
          username: MySQLTestConfig.username,
          password: MySQLTestConfig.password,
          // database 省略：种子/清理通道绝不依赖被删的默认库。
        ),
      );
      await cleanupAdapter.createDatabase(defaultDbName);
      await cleanupAdapter.createDatabase(otherDbName);

      // 被测连接：真实 AppProvider + 真实 DatabaseService + 真实网关壳 adapter。
      // 复现条件：DbServer 必须带 database: <默认库名>（区别于不配库的安全路径）。
      appProvider = AppProvider();
      server = DbServer(
        id: 'mysql_ddf_e2e_$base',
        name: 'MySQL DDF E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: defaultDbName,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(
        connected,
        isTrue,
        reason:
            'Failed to connect to MySQL ${MySQLTestConfig.host}:'
            '${MySQLTestConfig.port} (default db=$defaultDbName)',
      );
    });

    tearDown(() async {
      if (!mysqlE2EGatewayReady) return;
      try {
        await eventSub?.cancel();
      } catch (_) {}
      // best-effort 回收残留库（清理 adapter 不配默认库，默认库已删也无碍）。
      try {
        await cleanupAdapter.executeQuery(
          'DROP DATABASE IF EXISTS `$defaultDbName`',
        );
      } catch (_) {}
      try {
        await cleanupAdapter.executeQuery(
          'DROP DATABASE IF EXISTS `$otherDbName`',
        );
      } catch (_) {}
      try {
        await cleanupAdapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    /// 订阅 dbService 连接事件，捕获本连接的 ConnectionDisconnected。
    /// 必须在 drop 动作之前调用。
    void watchConnectionEvents() {
      eventSub = appProvider.connection.dbService.events.listen(
        (ConnectionEvent event) {
          if (event is ConnectionDisconnected &&
              event.connectionId == server.id) {
            disconnectedEvents.add(event);
          }
        },
        onError: eventStreamErrors.add,
      );
    }

    /// drop 之后的公共断言组：连接仍已连接 + 事件流干净。
    /// 调用方需先 await provider.refreshDatabases() + 小延时排空广播事件。
    void expectConnectionIntact() {
      final dbService = appProvider.connection.dbService;
      // ① 连接仍已连接：adapter 仍在 dbService 且底层可用，currentServer
      //    未被清（_handleAdapterDisconnect 三者全清——任一保留即未撕）。
      expect(
        dbService.hasConnection(server.id),
        isTrue,
        reason: 'drop 默认库后连接不应被拆除（adapter 仍在 dbService）',
      );
      final adapter = dbService.getAdapter(server.id);
      if (adapter == null) {
        fail('drop 默认库后 adapter 不应被移除');
      }
      expect(
        adapter.isConnected,
        isTrue,
        reason: 'drop 默认库后 adapter 底层连接应保持可用',
      );
      expect(
        dbService.currentServer?.id,
        server.id,
        reason: 'drop 默认库后 dbService.currentServer 不应被清空',
      );
      expect(
        appProvider.connection.currentServer?.id,
        server.id,
        reason: 'drop 默认库后 Provider 层连接状态不应被清空',
      );
      // ② 事件流无 ConnectionDisconnected、无错误。
      expect(
        disconnectedEvents,
        isEmpty,
        reason: '删默认库不应触发 ConnectionDisconnected 事件（DDF 修复语义）',
      );
      expect(eventStreamErrors, isEmpty, reason: '连接事件流不应有错误');
    }

    testWidgets('INT-DDF-MY-001: 删除默认库后连接保持、无库查询正常',
        (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final dbService = appProvider.connection.dbService;
      watchConnectionEvents();

      final dropped = await appProvider.dropDatabase(defaultDbName);
      expect(dropped, isTrue, reason: 'DROP DATABASE 应成功');

      // dropDatabase 内部的 refreshDatabases 为 fire-and-forget：显式 await
      // 确保刷新完成（这正是本批修复覆盖的最早期触发点），再排空广播事件。
      await appProvider.refreshDatabases();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expectConnectionIntact();

      // ③ 无 database 参数的 executeQuery（等价 keepalive 路径）正常返回。
      final adapter = dbService.getAdapter(server.id);
      if (adapter == null) {
        fail('adapter 不应被移除');
      }
      // adapter 级 executeQuery 返回 QueryResult（行在 .rows）。
      final result = await adapter.executeQuery('SELECT 1');
      expect(result.rows, isNotEmpty, reason: '无库参数 SELECT 1 应正常返回');

      // ④ getDatabases() 成功且不含已删库（Provider 缓存 + 服务层双查）。
      final dbs = await dbService.getDatabases();
      expect(dbs, isNot(contains(defaultDbName)),
          reason: 'getDatabases 结果不应含已删除的默认库');
      expect(appProvider.connection.databases, isNot(contains(defaultDbName)),
          reason: 'refreshDatabases 后 Provider 库列表不应含已删库');
    });

    testWidgets('INT-DDF-MY-002: 删除非默认库不影响连接（对照）', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final dbService = appProvider.connection.dbService;
      watchConnectionEvents();

      // 对照矩阵行「默认库 X 存在，删其它库 Y 不复现」：默认库 X（连接配置）
      // 保留，删除另建的库 B。
      final dropped = await appProvider.dropDatabase(otherDbName);
      expect(dropped, isTrue, reason: 'DROP DATABASE B 应成功');

      await appProvider.refreshDatabases();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expectConnectionIntact();

      final adapter = dbService.getAdapter(server.id);
      if (adapter == null) {
        fail('adapter 不应被移除');
      }
      final result = await adapter.executeQuery('SELECT 1');
      expect(result.rows, isNotEmpty, reason: '删除非默认库后 SELECT 1 应正常返回');

      final dbs = await dbService.getDatabases();
      expect(dbs, isNot(contains(otherDbName)),
          reason: 'getDatabases 结果不应含已删除的库 B');
      expect(dbs, contains(defaultDbName),
          reason: '默认库 A 应仍在库列表中');
    });
  });
}
