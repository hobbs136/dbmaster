// T16 J4 — 只读对象标签（ER 图 + 表属性进主标签栏）真库 e2e（MySQL + PG）。
//
// 树右键入口路径（Properties/查看 DDL → 对象 tab）由金标准
// mysql/postgresql_sidebar_menu_e2e_test.dart 对应用例断言；本文件聚焦
// 对象 tab 渲染层：主标签栏角标/标题、内容件同源真库数据（列/索引/DDL）、
// 去重复用、DDL 直达、ER 图真库渲染、连接断开清理。
//
// embedded 前置（DBMASTER_SERVER_BIN）与连接信息口径同金标准。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/er_canvas.dart';
import 'package:dbmaster/organisms/connection/object_tabs/er_diagram_content.dart';
import 'package:dbmaster/organisms/connection/object_tabs/table_properties_content.dart';
import 'package:dbmaster/organisms/connection/tabs_bar_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart'
    show ObjectTabKind, ObjectTabRef;
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/templates/editor_results_split.dart';

import 'config/mysql_test_config.dart';
import 'config/postgresql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 工作区 harness：主标签栏 + Editor/Results 分栏（对象 tab 由
  /// EditorResultsSplit 分流占满）。
  Widget buildWorkspaceApp(AppProvider provider) {
    final layoutProvider = LayoutPreferencesProvider();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<LayoutPreferencesProvider>.value(
          value: layoutProvider,
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        locale: const Locale('en'),
        home: Scaffold(
          body: Column(
            children: [
              const TabsBarWidget(),
              Expanded(
                child: EditorResultsSplit(
                  provider: provider,
                  layoutProvider: layoutProvider,
                  isResizing: false,
                  onResizeStart: () {},
                  onResizeEnd: () {},
                  resultsWidgetKey:
                      GlobalKey<ResultsWidgetState>(), // 对象 tab 路径不消费
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  group('Object tabs E2E (MySQL, T16 J4)', () {
    late AppProvider appProvider;
    late MySQLAdapter adapter;
    late String testDbName;
    late DbServer server;
    bool ready = false;

    setUpAll(() async {
      ready = await ensureEmbeddedServerForMysqlE2E();
      if (ready && !MySQLTestConfig.available) {
        // ignore: avoid_print
        print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供');
        ready = false;
      }
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      if (!ready) return;
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
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
      await adapter.createTable('seed_table', [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ]);
      await adapter.executeQuery(
        "INSERT INTO `seed_table` (id, name) VALUES (1, 'Alice')",
      );

      appProvider = AppProvider();
      server = DbServer(
        id: 'obj_tabs_e2e_${testDbName.hashCode}',
        name: 'Object Tabs E2E',
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
      // 表属性 DDL 取数（getCreateTableSql）走连接级活动库，显式选库
      // 对齐树内「展开库」语义（金标准 harness 经 expandDatabase 触发）。
      await appProvider.useDatabase(testDbName, connectionId: server.id);
    });

    tearDown(() async {
      if (!ready) return;
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
        appProvider.dispose();
      } catch (_) {}
    });

    testWidgets('表属性对象 tab：角标 + 标题 + 同源真库数据 + 去重', (
      tester,
    ) async {
      if (!ready) return;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 同对象开两次 → 去重复用（不无限开新）
      final id1 = appProvider.openObjectTab(
        ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: server.id,
          databaseName: testDbName,
          objectName: 'seed_table',
        ),
      );
      final id2 = appProvider.openObjectTab(
        ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: server.id,
          databaseName: testDbName,
          objectName: 'seed_table',
        ),
      );
      expect(id1, id2, reason: '同 kind+connectionId+objectName 复用');
      expect(appProvider.tab.tabs.length, 1);

      await tester.pumpWidget(buildWorkspaceApp(appProvider));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // 主标签栏：对象角标（box）+ 本地化标题
      expect(find.byIcon(LucideIcons.box), findsOneWidget);
      expect(find.text('Table Properties — seed_table'), findsOneWidget);
      // 内容件：表属性同源数据（Info tab 默认渲染行数等真库元数据）
      expect(find.byType(TablePropertiesContent), findsOneWidget);
      expect(find.textContaining('seed_table'), findsWidgets);
    });

    testWidgets('DDL 直达：initialTabIndex 复用覆写 + CREATE 语句真数据', (
      tester,
    ) async {
      if (!ready) return;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appProvider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          objectName: 'unused_seed',
        ),
      ); // 先占位（不同对象，独立 tab）
      final tabId = appProvider.openObjectTab(
        ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: server.id,
          databaseName: testDbName,
          objectName: 'seed_table',
        ),
      );
      // 「查看 DDL」语义：同对象复用 + initialTabIndex 覆写直达 CREATE
      appProvider.openObjectTab(
        ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: server.id,
          databaseName: testDbName,
          objectName: 'seed_table',
          initialTabIndex: 3,
        ),
      );
      expect(appProvider.tab.tabs.length, 2, reason: '两对象两 tab');
      expect(appProvider.tab.objectTabFor(tabId)?.initialTabIndex, 3);

      appProvider.setActiveTab(1); // 聚焦 seed_table 对象 tab
      await tester.pumpWidget(buildWorkspaceApp(appProvider));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // DDL tab 直达激活：CREATE TABLE 语句（MySQL 反引号形态）可见
      expect(find.textContaining('CREATE TABLE'), findsWidgets);
    });

    testWidgets('ER 图对象 tab：真库渲染（ErDiagramContent + ERCanvas）', (
      tester,
    ) async {
      if (!ready) return;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appProvider.openObjectTab(
        ObjectTabRef(
          kind: ObjectTabKind.erDiagram,
          connectionId: server.id,
          databaseName: testDbName,
        ),
      );
      await tester.pumpWidget(buildWorkspaceApp(appProvider));
      await tester.pumpAndSettle(const Duration(seconds: 8));

      expect(find.text('ER Diagram — $testDbName'), findsOneWidget);
      expect(find.byType(ErDiagramContent), findsOneWidget);
      expect(find.byType(ERCanvas), findsOneWidget, reason: '真库 ER 图画布');
      // 无加载失败文案（真库至少一张表 → 节点非空）
      expect(find.textContaining('Failed to load'), findsNothing);
    });

    testWidgets('连接断开 → 对象 tab 随连接关闭清理', (tester) async {
      if (!ready) return;
      appProvider.openObjectTab(
        ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: server.id,
          databaseName: testDbName,
          objectName: 'seed_table',
        ),
      );
      expect(appProvider.tab.tabs.length, 1);

      await appProvider.disconnectConnection(connectionId: server.id);
      expect(
        appProvider.tab.tabs.where((t) => t.connectionId == server.id),
        isEmpty,
        reason: 'disconnectConnection 走 closeTabsForConnection 清理对象 tab',
      );
    });
  });

  group('Object tabs E2E (PostgreSQL, T16 J4)', () {
    late AppProvider appProvider;
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late DbServer server;
    bool ready = false;

    setUpAll(() async {
      ready = await ensureEmbeddedServerForPgE2E();
      if (ready && !PostgreSQLTestConfig.available) {
        // ignore: avoid_print
        print('PG_E2E_SKIP: DBMASTER_POSTGRESQL_* 未通过 --dart-define 提供');
        ready = false;
      }
    });

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      if (!ready) return;
      adapter = PostgreSQLAdapter();
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      final maintenanceConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}',
        name: 'Seed Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      await adapter.connect(maintenanceConn);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      final testDbConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}_db',
        name: 'Seed DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConn);
      await adapter.createTable('seed_table', [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ]);
      await adapter.executeQuery(
        "INSERT INTO \"seed_table\" (id, name) VALUES (1, 'Alice')",
      );

      appProvider = AppProvider();
      server = DbServer(
        id: 'obj_tabs_pg_e2e_${testDbName.hashCode}',
        name: 'Object Tabs PG E2E',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');
      await appProvider.refreshDatabases();
    });

    tearDown(() async {
      if (!ready) return;
      try {
        await adapter.executeQuery('DROP TABLE IF EXISTS "seed_table"');
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    testWidgets('PG 表属性对象 tab：渲染 + DDL 直达（双引号形态）', (
      tester,
    ) async {
      if (!ready) return;
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      appProvider.openObjectTab(
        ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: server.id,
          databaseName: testDbName,
          objectName: 'seed_table',
          initialTabIndex: 3, // PG supportsForeignKeys → DDL 是第 4 个 tab
        ),
      );
      await tester.pumpWidget(buildWorkspaceApp(appProvider));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Table Properties — seed_table'), findsOneWidget);
      expect(find.byType(TablePropertiesContent), findsOneWidget);
      expect(find.textContaining('CREATE TABLE'), findsWidgets);
    });
  });
}
