// ============================================================================
// 2b.1 observe kind 真库 E2E（任务书 §6.1 步骤 4；harness 沿
// workbench_mysql_e2e_test.dart + config 环境变量 + skip 纪律）。
//
// ① MySQL（真实网关壳连接 + embedded dbmaster server 会话）：
//    - 进程列表非空（真实 SHOW PROCESSLIST：恒含自身连接）；
//    - 手动刷新后时间戳文本变化（跨秒界轮询，R2 时间戳 = 最近成功加载时刻）；
//    - 引擎状态文本非空（真实 SHOW ENGINE INNODB STATUS）。
// ② Redis（直接 adapter 直连，spec「（直接 adapter）」口径）：
//    - db15 专用测试库 FLUSHDB 自清 + 种子大键 → getTopKeysByMemory 非空，
//      tearDown 再 FLUSHDB 自删（自建自删专用库纪律，§5 纪律 10）。
//
// skip 纪律：embedded 二进制不可得 / DBMASTER_* 未提供时以可 grep 的
// OBSERVE_E2E_SKIP 跳过（无假绿）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/ai_workbench/workbench_observe_content.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_observe_engine_status_segment.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_observe_process_list_segment.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/redis_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/mysql_test_config.dart';
import 'config/redis_test_config.dart';
import 'helpers/ai_session_isolation_helper.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';
import 'helpers/redis_gateway_e2e_helper.dart';

/// 轮询直到 [predicate] 成立（真实网络往返不排帧）。
Future<bool> waitUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) return false;
    await tester.pump(const Duration(milliseconds: 100));
  }
  return true;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ── ① MySQL ─────────────────────────────────────────────────────────────

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得 / DBMASTER_MYSQL_* 未提供时整组以可 grep 的
  // OBSERVE_E2E_SKIP 跳过（FR-011 无假绿纪律）。
  bool mysqlReady = false;
  setUpAll(() async {
    mysqlReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print(
        'OBSERVE_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
        '（开源剥离默认凭据，缺参即跳过）',
      );
      mysqlReady = false;
    }
  });

  group('Workbench Observe E2E (MySQL)', () {
    late AppProvider appProvider;
    late MySQLAdapter adapter;
    late String testDbName;
    late DbServer server;

    const connectionLabel = 'Observe E2E MySQL';

    setUp(() async {
      if (!mysqlReady) return; // 无环境：整组跳过（标记已打印）
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();

      // 1. 种子专用 adapter 连接（金标准模式：先建库，再连 provider）。
      final dbConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}',
        name: 'Seed Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await adapter.connect(dbConn);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      // 2. 真实 AppProvider 连接（真实 DatabaseService + 网关壳 adapter）。
      appProvider = AppProvider(
        aiSessionManager: createIsolatedAiSessionManager(),
      );
      AppProvider.devBypassGates = true;
      appProvider.aiPanel.ensureSession();
      server = DbServer(
        id: 'observe_e2e_mysql_${testDbName.hashCode}',
        name: connectionLabel,
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');
      await appProvider.refreshDatabases();

      // 3. 工作台上下文：显式开一个绑定上下文的 query tab——
      // resolveWorkbenchContext 继承序「活动 tab 优先」的真实形态。
      await appProvider.openQueryTab(server.id, testDbName, sql: 'SELECT 1');
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_queries');
        await prefs.remove('recent_tables');
        await prefs.remove('sidebar_favorite_tables');
        await prefs.remove('connection_groups');
        await prefs.remove('workbench_stats_v1');
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    Widget buildTestApp() {
      return ChangeNotifierProvider<AppProvider>.value(
        value: appProvider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: WorkbenchObserveContent()),
        ),
      );
    }

    Future<void> pumpObserve(WidgetTester tester) async {
      // 视口加高（金标准先例）：进程行 8 列 + escalation 按钮需要宽度。
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    testWidgets('MySQL 进程列表非空 + 手动刷新后时间戳文本变化 + 引擎状态文本非空', (tester) async {
      if (!mysqlReady) return;
      await pumpObserve(tester);

      // ── 进程列表非空（真实 SHOW PROCESSLIST 恒含自身连接）────────────
      final loaded = await waitUntil(
        tester,
        () => (appProvider.connection.getProcessList(server.id) ?? const [])
            .isNotEmpty,
      );
      expect(loaded, isTrue, reason: '进程列表应在 30s 内非空');
      expect(find.text('No Data'), findsNothing);
      expect(
        find.byKey(WorkbenchObserveProcessListSegment.tableKey),
        findsOneWidget,
      );

      // ── 时间戳恒显：成功加载后 = Last updated（段 onLoaded 晚于缓存落
      // 地一帧，轮询等待）───────────────────────────────────────────────
      String timestampText() =>
          tester
              .widget<Text>(find.byKey(WorkbenchObserveContent.timestampKey))
              .data ??
          '';
      final tsReady = await waitUntil(
        tester,
        () => timestampText().startsWith('Last updated: '),
        timeout: const Duration(seconds: 15),
      );
      expect(tsReady, isTrue, reason: '时间戳应为 Last updated 格式');

      // ── 手动刷新 → 时间戳文本变化（R2：时间戳 = 最近成功加载时刻；
      // HH:mm:ss 精度下跨秒界变化，轮询至变化）─────────────────────────
      final before = timestampText();
      await tester.tap(find.byKey(WorkbenchObserveContent.refreshButtonKey));
      final changed = await waitUntil(
        tester,
        () => timestampText() != before,
        timeout: const Duration(seconds: 15),
      );
      expect(changed, isTrue, reason: '手动刷新后时间戳文本应变化');

      // ── 引擎状态文本非空（真实 SHOW ENGINE INNODB STATUS）───────────
      await tester.tap(
        find.byKey(const ValueKey('workbench_observe_segment_engineStatus')),
      );
      await tester.pumpAndSettle();
      final engineOk = await waitUntil(tester, () {
        final status = appProvider.connection.getEngineStatus(server.id);
        final text = status?['status']?.toString() ?? '';
        return text.isNotEmpty;
      }, timeout: const Duration(seconds: 30));
      expect(engineOk, isTrue, reason: '引擎状态文本应非空');
      expect(
        find.byKey(WorkbenchObserveEngineStatusSegment.textKey),
        findsOneWidget,
      );
      final engineText = tester.widget<SelectableText>(
        find.byKey(WorkbenchObserveEngineStatusSegment.textKey),
      );
      expect(engineText.data, isNotEmpty);
    });
  });

  // ── ② Redis（直接 adapter）───────────────────────────────────────────────

  // T29 非 SQL 批次（B4）：Redis 网关壳硬依赖 dbmaster server 会话。
  bool redisReady = false;
  setUpAll(() async {
    redisReady = await ensureEmbeddedServerForRedisE2E();
    if (redisReady && !RedisTestConfig.available) {
      // ignore: avoid_print
      print(
        'OBSERVE_E2E_SKIP: DBMASTER_REDIS_* 未通过 --dart-define 提供'
        '（开源剥离默认凭据，缺参即跳过）',
      );
      redisReady = false;
    }
  });

  group('Workbench Observe E2E (Redis)', () {
    testWidgets('Redis Top-N 加载非空（直接 adapter；自建自删专用库）', (tester) async {
      if (!redisReady) return;
      final adapter = RedisAdapter();
      final prefix = RedisTestConfig.generateTestKeyPrefix();
      final dbConn = DatabaseConnection(
        id: 'seed_${prefix.hashCode}',
        name: 'Seed Redis',
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
      // 环境不可达（测试库网络/服务未起）→ 可 grep 跳过不假绿（§5 纪律 10：
      // 不可达 skip 打印；仅连接阶段豁免，数据阶段断言照常全量生效）。
      try {
        await adapter.connect(dbConn);
      } catch (e) {
        // ignore: avoid_print
        print('OBSERVE_E2E_SKIP: Redis 环境不可达（连接失败：$e）——跳过');
        return;
      }
      try {
        // 专用测试库（config 默认 db15）自清 + 种子大键（带内存数据的键）。
        await adapter.runCommand(['FLUSHDB']);
        for (var i = 0; i < 3; i++) {
          await adapter.runCommand([
            'SET',
            '${prefix}_key_$i',
            'x' * (256 * 1024),
          ]);
        }
        final topN = await adapter.getTopKeysByMemory();
        expect(topN, isNotEmpty, reason: '种子大键后 Top-N 应非空');
        // 形状 = 经典三方法同源口径（key/bytes 字段）。
        expect(topN.first.containsKey('key'), isTrue);
        expect(topN.first.containsKey('bytes'), isTrue);
      } finally {
        try {
          await adapter.runCommand(['FLUSHDB']);
        } catch (_) {}
        try {
          await adapter.disconnect();
        } catch (_) {}
      }
    });
  });
}
