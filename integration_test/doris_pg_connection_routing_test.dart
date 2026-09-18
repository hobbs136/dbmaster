// ============================================================================
// Doris ↔ PostgreSQL Cross-Connection Routing Regression Tests (Real DB)
//
// Bug: 连接 Doris（只读账号）执行查询后，再连接 PostgreSQL 并单击展开库
// pg_test，弹出 "MySQLServerException [1044]: Access denied ... to database
// 'lykrflow_test'" —— PG 的元数据链路未显式传 connectionId，静默回退到全局
// activeConnectionId，而该全局状态会被并发的 Doris 懒加载链路偷走。
//
// 本文件用真实 Doris 3.0.2 + PostgreSQL 17 验证修复：
//   1. changeDatabase 显式 connectionId 绝不打到错误连接；
//   2. loadDatabaseInfo 后台加载结束后归还全局 active 连接；
//   3. switchToConnection 内部元数据查询路由到目标连接；
//   4. 用户场景完整回放（点击 PG 库与 Doris 懒加载并发）不再弹错。
//
// 目标：真实测试库（参数见 config/doris_test_config.dart /
//       config/postgresql_test_config.dart，可用 DBMASTER_* 环境变量覆盖）
// 每个用例自建自删专用库，不污染共享状态。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/doris_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/doris_test_config.dart';
import 'config/postgresql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady &&
        (!DorisTestConfig.available || !PostgreSQLTestConfig.available)) {
      // ignore: avoid_print
      print('DORIS_E2E_SKIP: DBMASTER_DORIS_* / DBMASTER_PG_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Doris↔PG cross-connection routing (real DB)', () {
    late DorisAdapter dorisSeed;
    late PostgreSQLAdapter pgSeed;
    late AppProvider appProvider;
    late DbServer dorisServer;
    late DbServer pgServer;
    late String dorisDb;
    late String pgDb;

    var dorisReady = false;
    var pgReady = false;

    setUp(() async {
      dorisSeed = DorisAdapter();
      pgSeed = PostgreSQLAdapter();
      dorisReady = false;
      pgReady = false;

      final ts = DateTime.now().millisecondsSinceEpoch;
      dorisDb = 'dbmaster_route_d_$ts';
      pgDb = 'dbmaster_route_p_$ts';

      // 1. Seed Doris: dedicated database + one table.
      try {
        final connected = await dorisSeed.connect(
          DatabaseConnection(
            id: 'route_seed_doris_$ts',
            name: 'Route Seed Doris',
            type: DatabaseType.doris,
            host: DorisTestConfig.host,
            port: DorisTestConfig.port,
            username: DorisTestConfig.username,
            password: DorisTestConfig.password,
          ),
        );
        if (connected && dorisSeed.isConnected) {
          await dorisSeed.createDatabase(dorisDb);
          await dorisSeed.useDatabase(dorisDb);
          await dorisSeed.executeQuery(
            'CREATE TABLE `seed_table` ('
            '`id` INT NOT NULL, '
            '`name` VARCHAR(100) NULL) '
            'DUPLICATE KEY(`id`) '
            'DISTRIBUTED BY HASH(`id`) BUCKETS 1 '
            'PROPERTIES("replication_num" = "1")',
          );
          dorisReady = true;
        }
      } catch (_) {
        dorisReady = false;
      }

      // 2. Seed PostgreSQL: dedicated database + one table inside it.
      try {
        final connected = await pgSeed.connect(
          DatabaseConnection(
            id: 'route_seed_pg_$ts',
            name: 'Route Seed PG',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: PostgreSQLTestConfig.database,
          ),
        );
        if (connected && pgSeed.isConnected) {
          await pgSeed.createDatabase(pgDb);
          await pgSeed.useDatabase(pgDb);
          await pgSeed.executeQuery(
            'CREATE TABLE seed_table (id INT PRIMARY KEY, name VARCHAR(64))',
          );
          pgReady = true;
        }
      } catch (_) {
        pgReady = false;
      }

      if (!dorisReady || !pgReady) return;

      // 3. Provider-level fixture：先连 Doris 并执行一次查询（复现用户步骤），
      //    再连 PostgreSQL（全局 active 最终落在 PG）。
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      dorisServer = DbServer(
        id: 'route_doris_$ts',
        name: 'Route Doris',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );
      pgServer = DbServer(
        id: 'route_pg_$ts',
        name: 'Route PG',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );
      await appProvider.connection.saveConnection(dorisServer);
      await appProvider.connection.saveConnection(pgServer);

      final dorisConnected = await appProvider.connectToServer(dorisServer);
      expect(dorisConnected, isTrue, reason: 'Failed to connect to Doris');
      // 用户在 Doris 上"点击查询并得出结果"
      await appProvider.dbService.executeQuery(
        'SELECT 1',
        connectionId: dorisServer.id,
      );

      final pgConnected = await appProvider.connectToServer(pgServer);
      expect(pgConnected, isTrue, reason: 'Failed to connect to PostgreSQL');
    });

    tearDown(() async {
      try {
        await appProvider.connection.disconnectAllConnections();
      } catch (_) {}
      try {
        await appProvider.connection.deleteConnection(dorisServer.id);
        await appProvider.connection.deleteConnection(pgServer.id);
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}

      if (dorisSeed.isConnected) {
        try {
          await dorisSeed.executeQuery('DROP DATABASE IF EXISTS `$dorisDb`');
        } catch (_) {}
        try {
          await dorisSeed.disconnect();
        } catch (_) {}
      }
      if (pgSeed.isConnected) {
        try {
          // 先切回默认库再 DROP（不能删当前所在库）；FORCE 兜底在途会话
          await pgSeed.useDatabase(PostgreSQLTestConfig.database);
          await pgSeed.executeQuery(
            'DROP DATABASE IF EXISTS "$pgDb" WITH (FORCE)',
          );
        } catch (_) {}
        try {
          await pgSeed.disconnect();
        } catch (_) {}
      }

      // Clear SharedPreferences keys that cross test boundaries.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_queries');
        await prefs.remove('recent_tables');
        await prefs.remove('sidebar_favorite_tables');
        await prefs.remove('connection_groups');
      } catch (_) {}
    });

    void skipIfNeeded() {
      if (!dorisReady) {
        markTestSkipped(
          'Doris at ${DorisTestConfig.host}:${DorisTestConfig.port} unreachable',
        );
      }
      if (!pgReady) {
        markTestSkipped(
          'PostgreSQL at ${PostgreSQLTestConfig.host}:${PostgreSQLTestConfig.port} unreachable',
        );
      }
    }

    testWidgets(
      'changeDatabase with explicit connectionId never hits the stolen global active connection',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        skipIfNeeded();

        // 模拟全局 active 被并发链路偷到 Doris
        appProvider.dbService.setActiveConnection(dorisServer.id);

        await appProvider.connection.changeDatabase(
          pgDb,
          connectionId: pgServer.id,
        );

        // 修复前：USE 打到 Doris → MySQLServerException 写入 errorMessage
        expect(appProvider.connection.errorMessage, isNull);
        expect(appProvider.connection.currentDatabase?.name, pgDb);
        expect(
          appProvider.connection.getCachedDatabase(pgServer.id, pgDb),
          isNotNull,
        );
        // 显式路由不偷换全局 active
        expect(appProvider.dbService.activeConnectionId, dorisServer.id);

        // PG 侧元数据确实可用（断言功能真生效）
        final info = await appProvider.dbService.getDatabaseInfo(
          pgDb,
          connectionId: pgServer.id,
        );
        expect(info.tables.map((t) => t.name), contains('seed_table'));
      },
    );

    testWidgets(
      'loadDatabaseInfo returns the stolen global active connection afterwards',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        skipIfNeeded();

        // 当前停在 PG（用户正在浏览 PG）
        final switched = await appProvider.connection.switchToConnection(
          pgServer.id,
        );
        expect(switched, isTrue);
        expect(appProvider.dbService.activeConnectionId, pgServer.id);

        // 后台懒加载 Doris 节点的库信息（如侧边栏持久化展开态触发）
        final info = await appProvider.connection.loadDatabaseInfo(
          dorisServer.id,
          dorisDb,
        );

        expect(info, isNotNull);
        expect(info!.tables.map((t) => t.name), contains('seed_table'));
        // 关键断言：后台加载结束后全局 active 必须归还给 PG
        expect(appProvider.dbService.activeConnectionId, pgServer.id);
        expect(appProvider.connection.currentServer?.id, pgServer.id);
      },
    );

    testWidgets(
      'switchToConnection routes metadata to the target connection while global active is elsewhere',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        skipIfNeeded();

        // 全局 active 停在 Doris
        appProvider.dbService.setActiveConnection(dorisServer.id);

        final ok = await appProvider.connection.switchToConnection(pgServer.id);

        expect(ok, isTrue);
        expect(appProvider.connection.errorMessage, isNull);
        expect(appProvider.connection.databases, contains(pgDb));
        expect(appProvider.connection.currentServer?.id, pgServer.id);
      },
    );

    testWidgets(
      'user scenario replay: expanding a PG database while a Doris node lazy-loads concurrently',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        skipIfNeeded();

        // 复现用户操作序列：单击 PG 库节点会并发触发
        //  (a) 选中链路 switchToConnection + changeDatabase
        //  (b) Doris 持久化展开节点的懒加载 loadDatabaseInfo
        await Future.wait([
          (() async {
            await appProvider.connection.switchToConnection(pgServer.id);
            await appProvider.connection.changeDatabase(
              pgDb,
              connectionId: pgServer.id,
            );
          })(),
          appProvider.connection.loadDatabaseInfo(dorisServer.id, dorisDb),
        ]);

        // 用户所见症状：errorMessage 弹出 MySQLServerException —— 必须为空
        expect(appProvider.connection.errorMessage, isNull);
        // 并发结束后状态确定的部分
        expect(appProvider.dbService.activeConnectionId, pgServer.id);
        expect(appProvider.connection.currentServer?.id, pgServer.id);
        expect(
          appProvider.connection.getCachedDatabase(pgServer.id, pgDb),
          isNotNull,
        );
        expect(
          appProvider.connection.getCachedDatabase(dorisServer.id, dorisDb),
          isNotNull,
        );
      },
    );
  });
}
