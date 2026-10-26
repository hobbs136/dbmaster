// ============================================================================
// WorkbenchContextPicker 表模式 · 库限定表枚举 E2E（批2.6-C1）
// Tests: Real MySQL/PostgreSQL + real AppProvider + real gateway adapter +
//        WorkbenchContextPicker table mode (onTableSelected != null)
// Cases: 建 A/B 两库各含不同表 → picker 钻取库 B → 右栏出现 B 表、不出现
//        A 表 → 点 B 表 → onTableSelected 收到 (connId, 'B', tableB)
// Target: real MySQL via DBMASTER_MYSQL_*（mysql 现状已正确 → 应绿，回归锁）；
//         real PostgreSQL via DBMASTER_PG_*（实现落地前表枚举落当前库 → 红）
// 环境门控：embedded server 二进制不可得 / dart-define 缺参时整组以可 grep
// 的 MYSQL_E2E_SKIP / PG_E2E_SKIP 跳过（无假绿纪律，金标准同款）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/ai_workbench/workbench_context_picker.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/mysql_test_config.dart';
import 'config/postgresql_test_config.dart';
import 'helpers/ai_session_isolation_helper.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

/// 真实网关往返不排帧——轮询直到条件成立或超时（金标准同款 helper）。
Future<bool> _waitUntil(
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

  // -----------------------------------------------------------------------
  // MySQL（现状已正确：DatabaseQualifiedTablesAdapter 已实现 → 应绿，回归锁）
  // -----------------------------------------------------------------------
  group('WorkbenchContextPicker 表模式 E2E · MySQL', () {
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

    late AppProvider appProvider;
    late MySQLAdapter seedAdapter;
    late String dbA;
    late String dbB;
    late DbServer server;
    final picked = <(String, String, String)>[];

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      if (!mysqlE2EGatewayReady) return;
      picked.clear();
      seedAdapter = MySQLAdapter();
      final stamp = MySQLTestConfig.generateTestDatabaseName();
      dbA = '${stamp}_a';
      dbB = '${stamp}_b';

      // 1. 种子：A/B 两专用库，各含不同表（a_orders / b_users）。
      await seedAdapter.connect(
        DatabaseConnection(
          id: 'seed_$stamp',
          name: 'Seed',
          type: DatabaseType.mysql,
          host: MySQLTestConfig.host,
          port: MySQLTestConfig.port,
          username: MySQLTestConfig.username,
          password: MySQLTestConfig.password,
        ),
      );
      for (final entry in {
        dbA: 'a_orders',
        dbB: 'b_users',
      }.entries) {
        await seedAdapter.createDatabase(entry.key);
        await seedAdapter.useDatabase(entry.key);
        await seedAdapter.createTable(entry.value, [
          DbColumn(name: 'id', type: 'INT', isPrimaryKey: true),
        ]);
      }

      // 2. 真实 AppProvider 连接（真实 DatabaseService + 网关壳 adapter）。
      appProvider = AppProvider(
        aiSessionManager: createIsolatedAiSessionManager(),
      );
      AppProvider.devBypassGates = true;
      server = DbServer(
        id: 'ctx_picker_mysql_$stamp',
        name: 'MySQL Context Picker E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL');
    });

    tearDown(() async {
      if (!mysqlE2EGatewayReady) return;
      try {
        await seedAdapter.executeQuery('DROP DATABASE IF EXISTS `$dbA`');
        await seedAdapter.executeQuery('DROP DATABASE IF EXISTS `$dbB`');
      } catch (_) {}
      try {
        await seedAdapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    testWidgets(
      '钻取库 B → 只见 B 表 → 点表回调三元组 (connId, B, tableB)',
      (tester) async {
        if (!mysqlE2EGatewayReady) return;

        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ChangeNotifierProvider<AppProvider>.value(
            value: appProvider,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Scaffold(
                body: WorkbenchContextPicker(
                  onTableSelected: (connId, dbName, table) =>
                      picked.add((connId, dbName, table)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 点连接行 → 真实 getDatabases 装载库栏。
        await tester.tap(
          find.byKey(ValueKey('workbench_context_picker_conn_${server.id}')),
        );
        final dbBRowLoaded = await _waitUntil(
          tester,
          () => find
              .byKey(ValueKey('workbench_context_picker_db_$dbB'))
              .evaluate()
              .isNotEmpty,
        );
        expect(dbBRowLoaded, isTrue, reason: '库栏应装载出库 B');

        // 点库 B 行 → 钻取表清单（表模式不提交）。
        await tester.ensureVisible(
          find.byKey(ValueKey('workbench_context_picker_db_$dbB')),
        );
        await tester.tap(
          find.byKey(ValueKey('workbench_context_picker_db_$dbB')),
        );
        final tableBRowLoaded = await _waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('workbench_context_picker_table_b_users'))
              .evaluate()
              .isNotEmpty,
        );
        expect(tableBRowLoaded, isTrue, reason: '右栏应出现库 B 的表 b_users');
        expect(
          find.byKey(const ValueKey('workbench_context_picker_table_a_orders')),
          findsNothing,
          reason: '库 B 视图中不得出现库 A 的表 a_orders（库限定枚举）',
        );
        expect(picked, isEmpty, reason: '钻取库行不提交（表模式语义）');

        // 点库 B 的表 → 回调三元组后关闭。
        await tester.tap(
          find.byKey(const ValueKey('workbench_context_picker_table_b_users')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(WorkbenchContextPicker), findsNothing,
            reason: '选表后 picker 应关闭');
        expect(picked, hasLength(1));
        expect(picked.single.$1, server.id, reason: '回调连接 id');
        expect(picked.single.$2, dbB, reason: '回调库名 == 被钻取的库 B');
        expect(picked.single.$3, 'b_users', reason: '回调表名');
      },
    );
  });

  // -----------------------------------------------------------------------
  // PostgreSQL（实现落地前表枚举落当前库 → 断言红；实现后绿）
  // -----------------------------------------------------------------------
  group('WorkbenchContextPicker 表模式 E2E · PostgreSQL', () {
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

    late AppProvider appProvider;
    late PostgreSQLAdapter seedAdapter;
    late String dbA;
    late String dbB;
    late DbServer server;
    final picked = <(String, String, String)>[];

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      if (!pgE2EGatewayReady) return;
      picked.clear();
      seedAdapter = PostgreSQLAdapter();
      final stamp = PostgreSQLTestConfig.generateTestDatabaseName();
      dbA = '${stamp}_a';
      dbB = '${stamp}_b';

      await seedAdapter.connect(
        DatabaseConnection(
          id: 'seed_$stamp',
          name: 'Seed',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: PostgreSQLTestConfig.database,
        ),
      );
      expect(
        await seedAdapter.createDatabase(dbA),
        isTrue,
        reason: '建库 A',
      );
      expect(
        await seedAdapter.createDatabase(dbB),
        isTrue,
        reason: '建库 B',
      );
      // 两库各建不同表（经 executeQuery 信封 database: 路由，各落各库）。
      await seedAdapter.executeQuery(
        'CREATE TABLE a_orders(id INTEGER PRIMARY KEY)',
        database: dbA,
      );
      await seedAdapter.executeQuery(
        'CREATE TABLE b_users(id INTEGER PRIMARY KEY)',
        database: dbB,
      );

      appProvider = AppProvider(
        aiSessionManager: createIsolatedAiSessionManager(),
      );
      AppProvider.devBypassGates = true;
      server = DbServer(
        id: 'ctx_picker_pg_$stamp',
        name: 'PG Context Picker E2E',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');
    });

    tearDown(() async {
      if (!pgE2EGatewayReady) return;
      try {
        await seedAdapter.executeQuery('DROP DATABASE IF EXISTS "$dbA"');
        await seedAdapter.executeQuery('DROP DATABASE IF EXISTS "$dbB"');
      } catch (_) {}
      try {
        await seedAdapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    testWidgets(
      '钻取库 B → 只见 B 表 → 点表回调三元组 (connId, B, tableB)',
      (tester) async {
        if (!pgE2EGatewayReady) return;

        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          ChangeNotifierProvider<AppProvider>.value(
            value: appProvider,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: Scaffold(
                body: WorkbenchContextPicker(
                  onTableSelected: (connId, dbName, table) =>
                      picked.add((connId, dbName, table)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await tester.tap(
          find.byKey(ValueKey('workbench_context_picker_conn_${server.id}')),
        );
        final dbBRowLoaded = await _waitUntil(
          tester,
          () => find
              .byKey(ValueKey('workbench_context_picker_db_$dbB'))
              .evaluate()
              .isNotEmpty,
        );
        expect(dbBRowLoaded, isTrue, reason: '库栏应装载出库 B');

        await tester.ensureVisible(
          find.byKey(ValueKey('workbench_context_picker_db_$dbB')),
        );
        await tester.tap(
          find.byKey(ValueKey('workbench_context_picker_db_$dbB')),
        );
        final tableBRowLoaded = await _waitUntil(
          tester,
          () => find
              .byKey(const ValueKey('workbench_context_picker_table_b_users'))
              .evaluate()
              .isNotEmpty,
        );
        expect(tableBRowLoaded, isTrue,
            reason: '右栏应出现库 B 的表 b_users（实现前落当前库 → 红）');
        expect(
          find.byKey(const ValueKey('workbench_context_picker_table_a_orders')),
          findsNothing,
          reason: '库 B 视图中不得出现库 A 的表 a_orders（库限定枚举）',
        );
        expect(picked, isEmpty, reason: '钻取库行不提交（表模式语义）');

        await tester.tap(
          find.byKey(const ValueKey('workbench_context_picker_table_b_users')),
        );
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.byType(WorkbenchContextPicker), findsNothing,
            reason: '选表后 picker 应关闭');
        expect(picked, hasLength(1));
        expect(picked.single.$1, server.id, reason: '回调连接 id');
        expect(picked.single.$2, dbB, reason: '回调库名 == 被钻取的库 B');
        expect(picked.single.$3, 'b_users', reason: '回调表名');
      },
    );
  });
}
