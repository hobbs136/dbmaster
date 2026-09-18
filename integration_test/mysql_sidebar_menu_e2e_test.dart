// ============================================================================
// MySQL Sidebar Menu End-to-End Integration Tests
// Tests: Real MySQL server + full SidebarTree widget + context menus + dialogs
// Target: real MySQL via DBMASTER_MYSQL_* (see config/mysql_test_config.dart)
// ============================================================================

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/atoms/app_loading.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/models/filter_condition.dart';
import 'package:dbmaster/utils/filter_query_builder.dart';
import 'package:dbmaster/molecules/context_menu.dart';
import 'package:dbmaster/organisms/connection/connection_dialog.dart';
import 'package:dbmaster/organisms/connection/connection_export_import_dialog.dart';
import 'package:dbmaster/organisms/connection/schema_diff_dialog.dart';
import 'package:dbmaster/organisms/connection/table_dialog/edit_table_dialog.dart';
import 'package:dbmaster/organisms/connection/table_dialog/table_properties_dialog.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_connection_selector.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/schema_diff/schema_diff_service.dart';
import 'package:dbmaster/services/schema_diff/schema_snapshot_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  group('MySQL Sidebar Menu E2E', () {
    late AppProvider appProvider;
    late MySQLAdapter adapter;
    late String testDbName;
    late String syncTargetDbName;
    late String diffTargetDbName;
    late DbServer server;

    const connectionLabel = 'MySQL Sidebar E2E';

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();

      // 1. Seed the test database through a dedicated adapter connection
      //    before connecting the provider, so the provider's database list
      //    already contains the test database.
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
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ]);
      await adapter.executeQuery(
        "INSERT INTO `seed_table` (id, name) VALUES (1, 'Alice'), (2, 'Bob')",
      );
      await adapter.executeQuery(
        'CREATE INDEX `idx_seed_name` ON `seed_table` (name)',
      );
      await adapter.executeQuery('DROP TABLE IF EXISTS `seed_fk_table`');
      await adapter.executeQuery(
        'CREATE TABLE `seed_fk_table` (id INT PRIMARY KEY, seed_id INT)',
      );
      await adapter.executeQuery(
        'ALTER TABLE `seed_fk_table` ADD CONSTRAINT `fk_seed_id` '
        'FOREIGN KEY (`seed_id`) REFERENCES `seed_table` (`id`)',
      );

      // Also create a view, procedure, trigger and event for menu tests.
      await adapter.executeQuery(
        'CREATE OR REPLACE VIEW `seed_view` AS SELECT id, name FROM `seed_table`',
      );
      await adapter.executeQuery('DROP PROCEDURE IF EXISTS `seed_proc`');
      await adapter.executeQuery(
        'CREATE PROCEDURE `seed_proc`() BEGIN SELECT 1 AS one; END',
      );
      await adapter.executeQuery('DROP TRIGGER IF EXISTS `seed_trg`');
      await adapter.executeQuery(
        'CREATE TRIGGER `seed_trg` BEFORE INSERT ON `seed_table` '
        'FOR EACH ROW SET NEW.name = UPPER(NEW.name)',
      );
      await adapter.executeQuery('DROP EVENT IF EXISTS `seed_event`');
      await adapter.executeQuery(
        "CREATE EVENT `seed_event` ON SCHEDULE EVERY 1 DAY DO SELECT 1",
      );

      // 3. Prepare auxiliary databases for Data Sync and Schema Diff tests.
      syncTargetDbName = '${testDbName}_sync';
      diffTargetDbName = '${testDbName}_diff';
      await adapter.executeQuery('DROP DATABASE IF EXISTS `$syncTargetDbName`');
      await adapter.executeQuery('CREATE DATABASE `$syncTargetDbName`');
      await adapter.executeQuery('USE `$syncTargetDbName`');
      await adapter.executeQuery(
        'CREATE TABLE `seed_table` (id INT PRIMARY KEY, name VARCHAR(100))',
      );
      await adapter.executeQuery('DROP DATABASE IF EXISTS `$diffTargetDbName`');
      await adapter.executeQuery('CREATE DATABASE `$diffTargetDbName`');
      await adapter.executeQuery('USE `$testDbName`');

      // 4. Now connect the provider so it picks up the seeded database.
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      server = DbServer(
        id: 'mysql_sidebar_e2e_${testDbName.hashCode}',
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
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
      } catch (_) {}
      try {
        await adapter.executeQuery(
          'DROP DATABASE IF EXISTS `$syncTargetDbName`',
        );
      } catch (_) {}
      try {
        await adapter.executeQuery(
          'DROP DATABASE IF EXISTS `$diffTargetDbName`',
        );
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      // Clear SharedPreferences keys that cross test boundaries.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_queries');
        await prefs.remove('recent_tables');
        await prefs.remove('sidebar_favorite_tables');
        await prefs.remove('connection_groups');
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    // ----------------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------------
    Widget buildTestApp(AppProvider provider) {
      return MultiProvider(
        providers: [
          // 树内连接状态点（server-platform M1 起）watch 团队服务器连接态；
          // 本 harness 不涉团队服务器，供断开态实例即可。
          ChangeNotifierProvider<ServerConnectionProvider>(
            create: (_) => ServerConnectionProvider(),
          ),
          ChangeNotifierProvider.value(value: provider),
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
          home: _SidebarTestHarness(provider: provider),
        ),
      );
    }

    Future<void> pumpHarness(WidgetTester tester) async {
      // 视口加高：金标准树的全局节点（Performance y≈980 / Users y≈1006）与
      // 多连接场景的第二张连接卡都在默认 800×600 折叠线以下——tap 派生
      // Offset 落在视口外不命中（历史 10 失败的根因），lazy 列表项也不构建。
      // 1280×1600 全树可见；逐测恢复。
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildTestApp(appProvider));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> tapNode(WidgetTester tester, String label) async {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(TreeItem),
      );
      expect(finder, findsOneWidget, reason: 'Node "$label" not found');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> rightClickNode(WidgetTester tester, String label) async {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(TreeItem),
      );
      expect(finder, findsOneWidget, reason: 'Node "$label" not found');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> rightClickNodeContaining(
      WidgetTester tester,
      String text,
    ) async {
      final finder = find.ancestor(
        of: find.textContaining(text),
        matching: find.byType(TreeItem),
      );
      expect(
        finder,
        findsAtLeastNWidgets(1),
        reason: 'Node containing "$text" not found',
      );
      await tester.tap(finder.last, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> tapMenuItem(WidgetTester tester, String label) async {
      final menuFinder = find.byType(ContextMenu);
      expect(menuFinder, findsOneWidget, reason: 'Context menu not open');
      final finder = find.descendant(
        of: menuFinder,
        matching: find.text(label),
      );
      expect(finder, findsOneWidget, reason: 'Menu item "$label" not found');
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> tapDialogButton(WidgetTester tester, String label) async {
      final dialogFinder = find.byType(AlertDialog);
      final finder = find.descendant(
        of: dialogFinder,
        matching: find.widgetWithText(TextButton, label),
      );
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder);
      } else {
        final elevatedFinder = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(ElevatedButton, label),
        );
        expect(elevatedFinder, findsOneWidget);
        await tester.tap(elevatedFinder);
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandConnection(WidgetTester tester) async {
      await tapNode(tester, connectionLabel);
      // Wait for database list to render.
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandDatabase(WidgetTester tester, String dbName) async {
      await tapNode(tester, dbName);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandCategory(
      WidgetTester tester,
      String categoryPrefix,
    ) async {
      final headerFinder = find.ancestor(
        of: find.textContaining(categoryPrefix),
        matching: find.byType(TreeItem),
      );
      expect(headerFinder, findsOneWidget);
      await tester.ensureVisible(headerFinder);
      await tester.pumpAndSettle();
      await tester.tap(headerFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<bool> databaseExists(String dbName) async {
      final dbs = await adapter.getDatabases();
      return dbs.contains(dbName);
    }

    Future<bool> tableExists(String tableName) async {
      final tables = await adapter.getTables();
      return tables.contains(tableName);
    }

    Future<bool> viewExists(String viewName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.VIEWS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '$viewName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> procedureExists(String procName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.ROUTINES "
        "WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = '$procName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> triggerExists(String trgName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.TRIGGERS "
        "WHERE TRIGGER_SCHEMA = DATABASE() AND TRIGGER_NAME = '$trgName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> eventExists(String eventName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.EVENTS "
        "WHERE EVENT_SCHEMA = DATABASE() AND EVENT_NAME = '$eventName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> indexExists(String indexName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.STATISTICS "
        "WHERE TABLE_SCHEMA = DATABASE() AND INDEX_NAME = '$indexName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> columnExists(String tableName, String columnName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.COLUMNS "
        "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '$tableName' "
        "AND COLUMN_NAME = '$columnName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<void> doubleTapNode(WidgetTester tester, String label) async {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(TreeItem),
      );
      expect(finder, findsOneWidget, reason: 'Node "$label" not found');
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> doubleTapNodeContaining(
      WidgetTester tester,
      String text,
    ) async {
      final finder = find.ancestor(
        of: find.textContaining(text),
        matching: find.byType(TreeItem),
      );
      expect(
        finder,
        findsAtLeastNWidgets(1),
        reason: 'Node containing "$text" not found',
      );
      await tester.tap(finder.last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(finder.last);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // ----------------------------------------------------------------------
    // Connection node menu: Create Database
    // ----------------------------------------------------------------------
    testWidgets(
      'connection menu > Create Database creates a database and refreshes tree',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);

        final newDbName = '${testDbName}_created';

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Create Database');

        // Fill CreateDatabaseDialog
        final nameField = find.byType(TextField).first;
        await tester.enterText(nameField, newDbName);
        await tester.pump();
        await tapDialogButton(tester, 'Create');

        // Wait for snackbar and tree refresh.
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(await databaseExists(newDbName), isTrue);

        // Cleanup inside the test so subsequent tests are not affected.
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$newDbName`');
      },
    );

    // ----------------------------------------------------------------------
    // Database node menu: Drop Database
    // ----------------------------------------------------------------------
    testWidgets('database menu > Drop Database drops the selected database', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, testDbName);
      await tapMenuItem(tester, 'Drop Database');

      // Confirm by typing the database name.
      final field = find.byType(TextField);
      await tester.enterText(field, testDbName);
      await tester.pump();
      await tapDialogButton(tester, 'Delete');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(await databaseExists(testDbName), isFalse);
    });

    // ----------------------------------------------------------------------
    // Database node menu: Create Table
    // ----------------------------------------------------------------------
    testWidgets('database menu > New Table creates a table via the dialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);

      await rightClickNode(tester, testDbName);
      await tapMenuItem(tester, 'New Table');

      const newTableName = 'e2e_new_table';

      // Fill CreateTableDialog: table name.
      final tableNameField = find.byType(TextFormField).first;
      await tester.enterText(tableNameField, newTableName);
      await tester.pump();

      // Fill the default column name (first row, first column field).
      final columnNameField = find.byType(TextFormField).at(2);
      await tester.enterText(columnNameField, 'col_a');
      await tester.pump();

      await tapDialogButton(tester, 'Add');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      await adapter.useDatabase(testDbName);
      expect(await tableExists(newTableName), isTrue);
    });

    // ----------------------------------------------------------------------
    // Table node menu: Browse Data
    // ----------------------------------------------------------------------
    testWidgets(
      'table menu > Browse Data opens a query tab with SELECT results',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);
        await expandCategory(tester, 'Tables');

        await rightClickNode(tester, 'seed_table');
        await tapMenuItem(tester, 'Browse Data');

        await tester.pumpAndSettle(const Duration(seconds: 3));

        // spec 041 US2 (T021)：断言 browse 预设真生效（非仅点开菜单）
        expect(appProvider.tab.tabs, isNotEmpty);
        final activeId = appProvider.tab.activeTab?.id ?? '';
        expect(activeId, isNotEmpty, reason: '应激活一个 tab');
        final layout = appProvider.tab.panelLayoutFor(activeId);
        expect(
          layout.editorVisible,
          isFalse,
          reason: 'browse tab editor 应默认隐藏',
        );
        expect(
          layout.filterBarVisible,
          isTrue,
          reason: 'browse tab FilterBar 应默认显示（MySQL 属 SQL 系）',
        );
        expect(
          appProvider.tab.browseTargetFor(activeId),
          'seed_table',
          reason: 'browseTarget 应为表名（FilterBar 字段来源）',
        );
        expect(
          layout.resultsVisible,
          isTrue,
          reason: 'auto-run 后 resultsVisible 应为 true',
        );
        expect(
          appProvider.tab.activeResults,
          isNotEmpty,
          reason: 'auto-run 应返回数据行',
        );
        // spec 041 US3 fix：FilterBar 字段能加载（service 级 getTableColumns 按 databaseName 限定，
        // 不再误用连接默认库）
        final columns = await appProvider.getTableColumnsForBrowse(activeId);
        expect(columns, isNotEmpty, reason: 'FilterBar 应能加载表字段');
        expect(
          columns.any((c) => c.name == 'name'),
          isTrue,
          reason: '应含 name 列',
        );
      },
    );

    // ----------------------------------------------------------------------
    // FilterBar SQL (spec 041 US3 / T026) — buildFilteredSelect 输出在真库执行 + 过滤 + 转义
    // ----------------------------------------------------------------------
    test('FilterBar SQL: eq/AND/OR/恶意值转义 在真库执行正确', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.useDatabase(testDbName);

      // eq: name='Alice' → 1 行
      var sql = buildFilteredSelect(
        qualifiedTable: 'seed_table',
        conditions: [
          FilterCondition(field: 'name', op: FilterOperator.eq, value: 'Alice'),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      var res = await adapter.executeQuery(sql);
      expect(res.rows.length, 1, reason: 'name=Alice 应 1 行');

      // AND: id=1 AND name='Alice' → 1 行
      sql = buildFilteredSelect(
        qualifiedTable: 'seed_table',
        conditions: [
          FilterCondition(field: 'id', op: FilterOperator.eq, value: '1'),
          FilterCondition(field: 'name', op: FilterOperator.eq, value: 'Alice'),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      res = await adapter.executeQuery(sql);
      expect(res.rows.length, 1, reason: 'id=1 AND name=Alice 应 1 行');

      // OR: id=99 OR name='Bob' → 1 行
      sql = buildFilteredSelect(
        qualifiedTable: 'seed_table',
        conditions: [
          FilterCondition(field: 'id', op: FilterOperator.eq, value: '99'),
          FilterCondition(field: 'name', op: FilterOperator.eq, value: 'Bob'),
        ],
        combinator: FilterCombinator.or,
        dbType: DatabaseType.mysql,
      );
      res = await adapter.executeQuery(sql);
      expect(res.rows.length, 1, reason: 'id=99 OR name=Bob 应 1 行');

      // 恶意值 O'Brien 被转义 → 0 行（无此数据），不报错不注入
      sql = buildFilteredSelect(
        qualifiedTable: 'seed_table',
        conditions: [
          FilterCondition(
            field: 'name',
            op: FilterOperator.eq,
            value: "O'Brien",
          ),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      res = await adapter.executeQuery(sql);
      expect(res.rows.length, 0, reason: "O'Brien 转义后应 0 行、不注入");

      // 非法列名跳过 → 仅合法条件生效；表仍在（注入未生效）
      sql = buildFilteredSelect(
        qualifiedTable: 'seed_table',
        conditions: [
          FilterCondition(field: 'name', op: FilterOperator.eq, value: 'Alice'),
          FilterCondition(
            field: 'bad; DROP TABLE seed_table',
            op: FilterOperator.eq,
            value: 'x',
          ),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      res = await adapter.executeQuery(sql);
      expect(res.rows.length, 1, reason: '非法列名跳过，仅 name=Alice 生效');
      expect(await tableExists('seed_table'), isTrue, reason: '注入未生效，表仍在');
    });

    test('FilterBar boolean 值在真库执行正确（MySQL tinyint(1) → 裸值 1/0）', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.useDatabase(testDbName);
      await adapter.executeQuery('DROP TABLE IF EXISTS `bool_test`');
      await adapter.executeQuery(
        'CREATE TABLE `bool_test` (id INT, active TINYINT(1))',
      );
      await adapter.executeQuery(
        "INSERT INTO `bool_test` (id, active) VALUES (1, 1), (2, 0), (3, 1)",
      );

      // active=true → 2 行（id 1,3）
      var sql = buildFilteredSelect(
        qualifiedTable: 'bool_test',
        conditions: [
          FilterCondition(
            field: 'active',
            op: FilterOperator.eq,
            value: 'true',
            kind: FilterValueKind.boolean,
          ),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      var res = await adapter.executeQuery(sql);
      expect(res.rows.length, 2, reason: 'active=true → 2 行');

      // active=false → 1 行（id 2）
      sql = buildFilteredSelect(
        qualifiedTable: 'bool_test',
        conditions: [
          FilterCondition(
            field: 'active',
            op: FilterOperator.eq,
            value: 'false',
            kind: FilterValueKind.boolean,
          ),
        ],
        combinator: FilterCombinator.and,
        dbType: DatabaseType.mysql,
      );
      res = await adapter.executeQuery(sql);
      expect(res.rows.length, 1, reason: 'active=false → 1 行');

      await adapter.executeQuery('DROP TABLE IF EXISTS `bool_test`');
    });

    // ----------------------------------------------------------------------
    // Table node menu: Drop Table
    // ----------------------------------------------------------------------
    testWidgets(
      'table menu > Drop Table removes the table after confirmation',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);
        await expandCategory(tester, 'Tables');

        // Drop the dependent table first so seed_table can be dropped.
        await adapter.executeQuery('DROP TABLE IF EXISTS `seed_fk_table`');

        await rightClickNode(tester, 'seed_table');
        await tapMenuItem(tester, 'Drop Table');

        final field = find.byType(TextField);
        await tester.enterText(field, 'seed_table');
        await tester.pump();
        await tapDialogButton(tester, 'Delete');

        await tester.pumpAndSettle(const Duration(seconds: 3));

        await adapter.useDatabase(testDbName);
        expect(await tableExists('seed_table'), isFalse);
      },
    );

    // ----------------------------------------------------------------------
    // Table node menu: Truncate Table
    // ----------------------------------------------------------------------
    testWidgets('table menu > Truncate clears table data but keeps structure', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      // Remove the FK dependency so seed_table can be truncated.
      await adapter.executeQuery('DROP TABLE IF EXISTS `seed_fk_table`');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Truncate');

      await tapDialogButton(tester, 'Truncate');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await adapter.useDatabase(testDbName);
      final countResult = await adapter.executeQuery(
        'SELECT COUNT(*) AS c FROM `seed_table`',
      );
      expect(int.parse(countResult.rows.first['c'].toString()), 0);
      expect(await tableExists('seed_table'), isTrue);
    });

    // ----------------------------------------------------------------------
    // View node menu: Drop View
    // ----------------------------------------------------------------------
    testWidgets('view menu > Delete removes the view', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Views');

      await rightClickNode(tester, 'seed_view');
      await tapMenuItem(tester, 'Delete');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await adapter.useDatabase(testDbName);
      expect(await viewExists('seed_view'), isFalse);
    });

    // ----------------------------------------------------------------------
    // Procedure node menu: Drop Procedure
    // ----------------------------------------------------------------------
    testWidgets('procedure menu > Delete removes the procedure', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Procedures');

      await rightClickNode(tester, 'seed_proc');
      await tapMenuItem(tester, 'Delete');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await adapter.useDatabase(testDbName);
      expect(await procedureExists('seed_proc'), isFalse);
    });

    // ----------------------------------------------------------------------
    // Trigger node menu: Drop Trigger
    // ----------------------------------------------------------------------
    testWidgets('trigger menu > Delete removes the trigger', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Triggers');

      // Trigger label includes timing/event: "seed_trig  (BEFORE INSERT)".
      await rightClickNodeContaining(tester, 'seed_trg');
      await tapMenuItem(tester, 'Delete Trigger');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await adapter.useDatabase(testDbName);
      expect(await triggerExists('seed_trg'), isFalse);
    });

    // ----------------------------------------------------------------------
    // Event node menu: Drop Event
    // ----------------------------------------------------------------------
    testWidgets('event menu > Delete removes the event', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Events');

      await rightClickNode(tester, 'seed_event');
      await tapMenuItem(tester, 'Drop Event');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await adapter.useDatabase(testDbName);
      expect(await eventExists('seed_event'), isFalse);
    });

    // ----------------------------------------------------------------------
    // Process list node menu: Kill Query (menu only, no actual kill)
    // ----------------------------------------------------------------------
    testWidgets('process node menu opens Kill Query / Copy Query', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      // Expand Performance node.
      await expandCategory(tester, 'Performance');

      // Right-click the first process row.
      final processFinder = find.ancestor(
        of: find.textContaining('root'),
        matching: find.byType(TreeItem),
      );
      expect(processFinder, findsAtLeastNWidgets(1));

      await tester.tap(processFinder.first, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Kill Query'), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // User node menu: Copy Name / Refresh
    // ----------------------------------------------------------------------
    testWidgets('user node menu opens Copy Name / Refresh', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      // Expand Users node.
      await expandCategory(tester, 'Users');

      // Right-click the first user row (label format "user@host").
      final userFinder = find.ancestor(
        of: find.textContaining('@'),
        matching: find.byType(TreeItem),
      );
      expect(userFinder, findsAtLeastNWidgets(1));

      await tester.tap(userFinder.first, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy Name'), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('Server global node expands and loads server status', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandCategory(tester, 'Server');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(find.textContaining('MySQL'), findsAtLeastNWidgets(1));
    });

    testWidgets(
      'Performance global node expands and shows process list / refresh selector',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);

        await expandCategory(tester, 'Performance');
        await tester.pumpAndSettle(const Duration(seconds: 4));

        // The auto-refresh interval selector is always rendered.
        expect(find.text('5s'), findsOneWidget);
        expect(find.text('Off'), findsOneWidget);

        // Either processes loaded or the empty-state leaf appears.
        final hasProcesses = find.textContaining('[').evaluate().isNotEmpty;
        final hasEmpty = find
            .textContaining('No active processes')
            .evaluate()
            .isNotEmpty;
        expect(hasProcesses || hasEmpty, isTrue);
      },
    );

    testWidgets('Users global node expands and shows user list', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandCategory(tester, 'Users');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final hasUsers = find.textContaining('@').evaluate().isNotEmpty;
      final hasEmpty = find
          .textContaining('No users found')
          .evaluate()
          .isNotEmpty;
      expect(hasUsers || hasEmpty, isTrue);
    });

    testWidgets('user leaf > Copy Name copies correct text', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            captured = call.arguments['text'] as String?;
            return null;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandCategory(tester, 'Users');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final userFinder = find.ancestor(
        of: find.textContaining('@'),
        matching: find.byType(TreeItem),
      );
      expect(userFinder, findsAtLeastNWidgets(1));

      await tester.tap(userFinder.first, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tapMenuItem(tester, 'Copy Name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, isNotNull);
      expect(captured, contains('@'));
    });

    // ----------------------------------------------------------------------
    // Table node: double-click opens query editor tab
    // ----------------------------------------------------------------------
    testWidgets('table double-click opens query editor tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      final initialTabCount = appProvider.tab.tabs.length;
      await doubleTapNode(tester, 'seed_table');

      expect(appProvider.tab.tabs.length, initialTabCount + 1);
      final newTab = appProvider.tab.tabs.last;
      final layout = appProvider.tab.panelLayoutFor(newTab.id);
      expect(layout.editorVisible, isTrue, reason: '双击应进 query 模式（editor 可见）');
      expect(
        layout.filterBarVisible,
        isFalse,
        reason: 'query 模式 FilterBar 默认隐藏',
      );
      expect(
        appProvider.tab.browseTargetFor(newTab.id),
        isNull,
        reason: '双击不应挂 browseTarget（data 模式仅右键浏览进入）',
      );
      expect(newTab.sql, contains('seed_table'), reason: '应预填默认浏览查询');
    });

    // ----------------------------------------------------------------------
    // Database node: double-click opens query tab
    // ----------------------------------------------------------------------
    testWidgets('database double-click opens query tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      final initialTabCount = appProvider.tab.tabs.length;
      await doubleTapNode(tester, testDbName);

      expect(appProvider.tab.tabs.length, initialTabCount + 1);
    });

    // ----------------------------------------------------------------------
    // View node menu: Browse Data
    // ----------------------------------------------------------------------
    testWidgets('view menu > Browse Data opens data tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Views');

      final initialTabCount = appProvider.tab.tabs.length;
      await rightClickNode(tester, 'seed_view');
      await tapMenuItem(tester, 'Browse Data');

      expect(appProvider.tab.tabs.length, initialTabCount + 1);
      final newTab = appProvider.tab.tabs.last;
      final layout = appProvider.tab.panelLayoutFor(newTab.id);
      expect(
        layout.editorVisible,
        isFalse,
        reason: '右键浏览应进 data 模式（editor 隐藏）',
      );
      expect(
        layout.filterBarVisible,
        isTrue,
        reason: 'data 模式 FilterBar 应显示（MySQL 属 SQL 系）',
      );
      expect(
        appProvider.tab.browseTargetFor(newTab.id),
        'seed_view',
        reason: 'browseTarget 应为视图名（FilterBar 字段来源）',
      );
    });

    // ----------------------------------------------------------------------
    // Procedure node menu: Call
    // ----------------------------------------------------------------------
    testWidgets('procedure menu > Call opens CALL query tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Procedures');

      final initialTabCount = appProvider.tab.tabs.length;
      await rightClickNode(tester, 'seed_proc');
      await tapMenuItem(tester, 'Call seed_proc');

      expect(appProvider.tab.tabs.length, initialTabCount + 1);
      final activeTab = appProvider.tab.activeTab;
      expect(activeTab?.sql.contains('CALL `seed_proc`'), isTrue);
    });

    // ----------------------------------------------------------------------
    // Trigger node menu: View Definition
    // ----------------------------------------------------------------------
    testWidgets('trigger menu > View Definition opens definition dialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Triggers');

      await rightClickNodeContaining(tester, 'seed_trg');
      await tapMenuItem(tester, 'View Definition');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining('seed_trg'), findsWidgets);
    });

    testWidgets('trigger node double-click opens View Definition dialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Triggers');

      await doubleTapNodeContaining(tester, 'seed_trg');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining('seed_trg'), findsWidgets);
    });

    // ----------------------------------------------------------------------
    // Table node menu: Analyze / Optimize / Check
    // ----------------------------------------------------------------------
    testWidgets('table menu > Analyze Table runs maintenance command', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Analyze Table');

      await tapDialogButton(tester, 'Confirm');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('ANALYZE'), findsWidgets);
      await tapDialogButton(tester, 'Close');
    });

    testWidgets('table menu > Optimize Table runs maintenance command', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Optimize Table');

      await tapDialogButton(tester, 'Confirm');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('OPTIMIZE'), findsWidgets);
      await tapDialogButton(tester, 'Close');
    });

    testWidgets('table menu > Check Table runs maintenance command', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Check Table');

      await tapDialogButton(tester, 'Confirm');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('CHECK'), findsWidgets);
      await tapDialogButton(tester, 'Close');
    });

    // ----------------------------------------------------------------------
    // Table node menu: Rename Table
    // ----------------------------------------------------------------------
    testWidgets('table menu > Rename renames the table', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      // Drop the dependent table to avoid FK conflicts during rename.
      await adapter.executeQuery('DROP TABLE IF EXISTS `seed_fk_table`');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Rename');

      const newName = 'seed_table_renamed';
      final field = find.byType(TextField);
      await tester.enterText(field, newName);
      await tester.pump();
      await tapDialogButton(tester, 'Confirm');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      await adapter.useDatabase(testDbName);
      expect(await tableExists('seed_table'), isFalse);
      expect(await tableExists(newName), isTrue);
    });

    // ----------------------------------------------------------------------
    // Connection node menu: Refresh / Disconnect / Connect
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Refresh refreshes database list', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Refresh');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.isConnectionConnected(server.id), isTrue);
    });

    testWidgets('connection menu > Disconnect disconnects the connection', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Disconnect');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.isConnectionConnected(server.id), isFalse);
    });

    testWidgets(
      'connection selector connects a saved disconnected server',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);

        // Add a second saved connection that is not connected.
        const disconnectedLabel = 'MySQL Sidebar E2E Disconnected';
        final disconnectedServer = DbServer(
          id: '${server.id}_disconnected',
          name: disconnectedLabel,
          type: DatabaseType.mysql,
          host: server.host,
          port: server.port,
          username: server.username,
          password: server.password,
        );
        await appProvider.connection.saveConnection(disconnectedServer);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(
          appProvider.isConnectionConnected(disconnectedServer.id),
          isFalse,
        );

        // C22-1 单实例树：未连接的已保存连接不在树里，入口是顶部选择器下拉
        //（点下拉箭头打开；find.byType(PopupMenuItem) 精确匹配不到
        // PopupMenuItem<String> 实例，点项用 find.text 的 overlay 命中）。
        await tester.tap(find.byIcon(LucideIcons.chevronsUpDown));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.tap(find.text(disconnectedLabel).last);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        expect(
          appProvider.isConnectionConnected(disconnectedServer.id),
          isTrue,
        );
      },
    );

    testWidgets('connection selector switches active connection', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      const secondLabel = 'MySQL Sidebar E2E Second';
      final secondServer = DbServer(
        id: '${server.id}_second',
        name: secondLabel,
        type: DatabaseType.mysql,
        host: server.host,
        port: server.port,
        username: server.username,
        password: server.password,
      );
      await appProvider.connection.saveConnection(secondServer);
      final connected = await appProvider.connectToServer(secondServer);
      expect(connected, isTrue);
      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(appProvider.connection.currentServer?.id, secondServer.id);

      // C22-1 单实例树：切换当前连接的 UI 入口 = 选择器下拉已连接项。
      await tester.tap(find.byIcon(LucideIcons.chevronsUpDown));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.text(connectionLabel).last);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.connection.currentServer?.id, server.id);
    });

    testWidgets(
      'connection root row double-click reconnects a disconnected connection',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);

        // 断开当前连接（右键菜单 Disconnect）。
        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Disconnect');
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(appProvider.isConnectionConnected(server.id), isFalse);

        // 断开后树可能失去 currentServer 锚定——显式选中保住根行渲染。
        appProvider.sidebar.selectConnection(server.id);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // C22-1：根行双击在未连接态走连接流程（onDoubleTap → _connectToServer）。
        await doubleTapNode(tester, connectionLabel);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        expect(appProvider.isConnectionConnected(server.id), isTrue);
      },
    );

    // ----------------------------------------------------------------------
    // Database node menu: Select Database
    // ----------------------------------------------------------------------
    testWidgets('database menu > Select Database switches current database', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, testDbName);
      await tapMenuItem(tester, 'Select Database');

      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.connection.currentDatabase?.name, testDbName);
    });

    testWidgets('database menu > Refresh reloads database objects', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, testDbName);
      await tapMenuItem(tester, 'Refresh');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.isConnectionConnected(server.id), isTrue);
      expect(find.text(testDbName), findsWidgets);
    });

    // ----------------------------------------------------------------------
    // Index leaf menu: Drop Index
    // ----------------------------------------------------------------------
    testWidgets('index leaf menu > Delete drops the index', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      // Expand seed_table to reveal its schema children (columns, indexes, FKs).
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'idx_seed_name');
      await tapMenuItem(tester, 'Delete');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await adapter.useDatabase(testDbName);
      expect(await indexExists('idx_seed_name'), isFalse);
    });

    // ----------------------------------------------------------------------
    // Expand table node reveals Columns / Indexes / Foreign Keys
    // ----------------------------------------------------------------------
    testWidgets(
      'expanding a table node reveals columns, indexes and foreign keys',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);
        await expandCategory(tester, 'Tables');

        // seed_table: columns + indexes.
        await tapNode(tester, 'seed_table');
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.text('id'), findsWidgets);
        expect(find.text('name'), findsWidgets);
        expect(find.textContaining('Indexes'), findsWidgets);

        // seed_fk_table: foreign keys.
        await tapNode(tester, 'seed_fk_table');
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.textContaining('Foreign Keys'), findsWidgets);

        await adapter.useDatabase(testDbName);
        expect(await columnExists('seed_table', 'id'), isTrue);
        expect(await columnExists('seed_table', 'name'), isTrue);
      },
    );

    // ----------------------------------------------------------------------
    // Column leaf menu: Insert into Editor (menu presence)
    // ----------------------------------------------------------------------
    testWidgets('column leaf menu shows Insert into Editor', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNode(tester, 'id');

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Insert into editor'), findsOneWidget);
      expect(find.text('Copy column name'), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // Index leaf menu: Copy Name / Insert into Editor (menu presence)
    // ----------------------------------------------------------------------
    testWidgets('index leaf menu shows Copy Name / Insert into Editor', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'idx_seed_name');

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy index name'), findsOneWidget);
      expect(find.text('Insert into editor'), findsOneWidget);
      expect(find.text('Edit Index'), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // Foreign key leaf menu: Copy Name / Insert into Editor (menu presence)
    // ----------------------------------------------------------------------
    testWidgets('foreign key leaf menu shows Copy Name / Insert into Editor', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_fk_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'fk_seed_id  (seed_id');

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy foreign key name'), findsOneWidget);
      expect(find.text('Insert into editor'), findsOneWidget);
    });

    testWidgets(
      'foreign key leaf double-click inserts name into active editor',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);

        await appProvider.openQueryTab(server.id, testDbName, sql: 'SELECT 1');
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(appProvider.tab.activeTab, isNotNull);

        String? inserted;
        appProvider.insertIntoActiveEditor = (name) => inserted = name;

        await expandCategory(tester, 'Tables');
        await tapNode(tester, 'seed_fk_table');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await doubleTapNodeContaining(tester, 'fk_seed_id');
        expect(inserted, 'fk_seed_id');
      },
    );

    // ----------------------------------------------------------------------
    // Connection node menu: Toggle Read-Only
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Toggle Read-Only changes read-only flag', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Enable Read-Only');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.connection.getServerById(server.id)?.readOnly, isTrue);
    });

    // ----------------------------------------------------------------------
    // Connection node menu: Collapse All
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Collapse All collapses expanded nodes', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);

      // Verify child database is visible before collapse.
      expect(find.text(testDbName), findsWidgets);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Collapse All');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // After collapse the database node should no longer be visible.
      expect(find.text(testDbName), findsNothing);
    });

    // ----------------------------------------------------------------------
    // Connection node menu: Delete Connection
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Delete removes the saved connection', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Delete Connection');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final saved = appProvider.connection.savedConnections;
      expect(saved.any((s) => s.id == server.id), isFalse);
    });

    // ----------------------------------------------------------------------
    // Database node menu: Properties
    // ----------------------------------------------------------------------
    testWidgets('database menu > Properties opens properties dialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, testDbName);
      await tapMenuItem(tester, 'Properties');

      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining(testDbName), findsWidgets);
    });

    // ----------------------------------------------------------------------
    // Table node menu: Engine Status
    // ----------------------------------------------------------------------
    testWidgets('table menu > Engine Status opens engine status dialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Engine Status');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // View / Procedure / Trigger / Event node: Copy Name menu presence
    // ----------------------------------------------------------------------
    testWidgets('view menu shows Copy Name', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Views');

      await rightClickNode(tester, 'seed_view');

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy Name'), findsOneWidget);
    });

    testWidgets('procedure menu shows Copy Name', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Procedures');

      await rightClickNode(tester, 'seed_proc');

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy Name'), findsOneWidget);
    });

    testWidgets('trigger menu shows Copy Name', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Triggers');

      await rightClickNodeContaining(tester, 'seed_trg');

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy Name'), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // Tables category folder menu: Refresh
    // ----------------------------------------------------------------------
    testWidgets('Tables folder menu > Refresh reloads objects', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      final headerFinder = find.ancestor(
        of: find.textContaining('Tables'),
        matching: find.byType(TreeItem),
      );
      expect(headerFinder, findsOneWidget);
      await tester.tap(headerFinder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Refresh'), findsOneWidget);

      await tapMenuItem(tester, 'Refresh');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // After refresh the table list should still render.
      expect(find.text('seed_table'), findsWidgets);
    });

    // ----------------------------------------------------------------------
    // Schema leaf menus: column / index / trigger / event
    // ----------------------------------------------------------------------
    testWidgets('column leaf menu shows Copy Name / Type / All', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNode(tester, 'id');
      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Insert into editor'), findsOneWidget);
      expect(find.text('Copy column name'), findsOneWidget);
      expect(find.text('Copy column type'), findsOneWidget);
      expect(find.text('Copy all column names'), findsOneWidget);
    });

    testWidgets('column double-click inserts name into active editor', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);

      // Open a query tab so there is an active editor to receive the name.
      await appProvider.openQueryTab(server.id, testDbName, sql: 'SELECT 1');
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(appProvider.tab.activeTab, isNotNull);

      String? inserted;
      appProvider.insertIntoActiveEditor = (name) => inserted = name;

      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await doubleTapNode(tester, 'id');
      expect(inserted, 'id');
    });

    testWidgets('trigger menu shows Insert into Editor', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Triggers');

      await rightClickNodeContaining(tester, 'seed_trg');
      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Insert into editor'), findsOneWidget);
    });

    testWidgets('event menu shows Copy Name / Insert into Editor', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Events');

      await rightClickNodeContaining(tester, 'seed_event');
      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy Name'), findsOneWidget);
      expect(find.text('Insert into editor'), findsOneWidget);
    });

    testWidgets('event node single-click copies name to clipboard', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            captured = call.arguments['text'] as String?;
            return null;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Events');

      await tapNode(tester, 'seed_event');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(captured, 'seed_event');
    });

    testWidgets('index leaf menu shows Edit Index', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'idx_seed_name');
      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Edit Index'), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // Double-click on view / procedure
    // ----------------------------------------------------------------------
    testWidgets('view single-click opens query editor tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Views');

      await tapNode(tester, 'seed_view');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs, isNotEmpty);
      final newTab = appProvider.tab.tabs.last;
      expect(
        appProvider.tab.panelLayoutFor(newTab.id).editorVisible,
        isTrue,
        reason: '单击视图应进 query 模式（editor 可见）',
      );
    });

    testWidgets('view double-click opens query editor tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Views');

      await doubleTapNode(tester, 'seed_view');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs, isNotEmpty);
      final newTab = appProvider.tab.tabs.last;
      final layout = appProvider.tab.panelLayoutFor(newTab.id);
      expect(
        layout.editorVisible,
        isTrue,
        reason: '双击视图应进 query 模式（editor 可见）',
      );
      expect(newTab.sql, contains('seed_view'), reason: '应预填默认浏览查询');
    });

    testWidgets('procedure single-click opens CALL query tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Procedures');

      await tapNode(tester, 'seed_proc');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs, isNotEmpty);
      expect(appProvider.tab.activeTab?.sql ?? '', contains('CALL'));
    });

    testWidgets('procedure double-click opens CALL query tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Procedures');

      await doubleTapNode(tester, 'seed_proc');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs, isNotEmpty);
      expect(appProvider.tab.activeTab?.sql ?? '', contains('CALL'));
    });

    // ----------------------------------------------------------------------
    // Connection advanced actions
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Edit Connection opens ConnectionDialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Edit Connection');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(ConnectionDialog), findsOneWidget);
    });

    testWidgets('connection menu > Clone Connection clones the server', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      final beforeCount = appProvider.connection.savedConnections.length;
      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Clone Connection');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final afterCount = appProvider.connection.savedConnections.length;
      expect(afterCount, beforeCount + 1);
      expect(
        appProvider.connection.savedConnections.any(
          (c) => c.name.contains('副本') || c.name.contains('Copy'),
        ),
        isTrue,
      );
    });

    testWidgets(
      'connection menu > Export This Connection opens export dialog',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Export This Connection');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        expect(find.byType(ConnectionExportImportDialog), findsOneWidget);
      },
    );

    testWidgets(
      'connection menu > Move to Group moves and removes the connection',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);

        const groupName = 'Test Group';
        final groupId = 'test_group_${testDbName.hashCode}';
        await appProvider.addConnectionGroup(
          ConnectionGroup(id: groupId, name: groupName, color: '#FF0000'),
        );
        await tester.pumpAndSettle(const Duration(seconds: 1));

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Move to $groupName');
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(
          appProvider.connection.savedConnections
              .firstWhere((s) => s.id == server.id)
              .groupId,
          groupId,
        );

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Remove from Group');
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(
          appProvider.connection.savedConnections
              .firstWhere((s) => s.id == server.id)
              .groupId,
          isNull,
        );
      },
    );

    // ----------------------------------------------------------------------
    // Table advanced actions
    // ----------------------------------------------------------------------
    testWidgets('table menu > Properties opens table properties dialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Properties');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(TablePropertiesDialog), findsOneWidget);
    });

    testWidgets('table menu > Edit Table opens edit table dialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Edit Table');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(find.byType(EditTableDialog), findsOneWidget);

      // Close the dialog so it does not leak into the next test.
      await tester.tap(
        find.descendant(
          of: find.byType(EditTableDialog),
          matching: find.widgetWithText(TextButton, 'Cancel'),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });

    testWidgets('table menu > Edit Table adds a column and saves changes', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Edit Table');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      final dialogFinder = find.byType(EditTableDialog);
      expect(dialogFinder, findsOneWidget);

      // Tap "Add Column" inside the dialog.
      await tester.tap(
        find.descendant(
          of: dialogFinder,
          matching: find.byIcon(LucideIcons.plus),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Each column row has a name field and a default-value field.
      // The new row's name field is the second-to-last TextFormField inside
      // the dialog's ListView.
      final listViewFinder = find.descendant(
        of: dialogFinder,
        matching: find.byType(ListView),
      );
      final nameFields = find.descendant(
        of: listViewFinder,
        matching: find.byType(TextFormField),
      );
      expect(nameFields, findsAtLeastNWidgets(4));
      final fieldCount = nameFields.evaluate().length;
      final newNameField = nameFields.at(fieldCount - 2);
      await tester.ensureVisible(newNameField);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.enterText(newNameField, 'new_col');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Tap Save (the LoadingButton inside the EditTableDialog).
      final saveFinder = find.descendant(
        of: dialogFinder,
        matching: find.widgetWithText(LoadingButton, 'Save'),
      );
      await tester.ensureVisible(saveFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(saveFinder);
      await tester.pumpAndSettle(const Duration(seconds: 6));

      expect(find.byType(EditTableDialog), findsNothing);

      final columns = await appProvider.dbService.getTableColumns(
        'seed_table',
        connectionId: server.id,
        databaseName: testDbName,
      );
      expect(columns.any((c) => c.name == 'new_col'), isTrue);
    });

    // ----------------------------------------------------------------------
    // Saved queries
    // ----------------------------------------------------------------------
    testWidgets('saved query lifecycle > create, open, rename and delete', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      final query = QueryTab(
        id: 'sq_${testDbName.hashCode}',
        title: 'My Saved Query',
        sql: 'SELECT 1',
        connectionId: server.id,
        databaseName: testDbName,
        databaseType: DatabaseType.mysql,
        isSaved: true,
      );
      await appProvider.saveQuery(query);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final savedQueriesHeader = find.ancestor(
        of: find.textContaining('Saved Queries'),
        matching: find.byType(TreeItem),
      );
      expect(savedQueriesHeader, findsOneWidget);
      await tester.tap(savedQueriesHeader);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('My Saved Query'), findsOneWidget);

      // Open via provider and verify a tab is created.
      await appProvider.openSavedQuery(query);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(appProvider.tab.tabs, isNotEmpty);

      // Rename via provider and verify UI updates.
      await appProvider.renameSavedQuery(query.id, 'Renamed Query');
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Renamed Query'), findsOneWidget);
      expect(find.text('My Saved Query'), findsNothing);

      // Delete via provider and verify UI updates.
      await appProvider.deleteSavedQuery(query.id);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Renamed Query'), findsNothing);
    });

    // ----------------------------------------------------------------------
    // Recent / Favorite tables
    // ----------------------------------------------------------------------
    testWidgets('Recent Tables section appears and Clear All clears', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await appProvider.recentTables.recordTableAccess(
        connectionId: server.id,
        databaseName: testDbName,
        tableName: 'seed_table',
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Recent'), findsOneWidget);
      // The recent row is rendered with RichText, so just verify the header.

      final clearAllFinder = find.byIcon(LucideIcons.eraser);
      expect(clearAllFinder, findsOneWidget);
      await tester.tap(clearAllFinder);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('Favorite table section appears and can be unfavorited', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      final tableKey = '${server.id}:$testDbName:seed_table';
      // Seed SharedPreferences so the async favorites load will pick it up,
      // and also toggle in-memory to cover either timing.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sidebar_favorite_tables', [tableKey]);
      appProvider.sidebar.toggleFavoriteTable(tableKey);
      appProvider.notifyListeners();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.sidebar.favoriteTables, contains(tableKey));
      expect(find.byIcon(LucideIcons.star), findsWidgets);
      final favoriteRowFinder = find.ancestor(
        of: find.textContaining('$connectionLabel · seed_table'),
        matching: find.byType(TreeItem),
      );
      expect(favoriteRowFinder, findsOneWidget);

      final starFinder = find.descendant(
        of: favoriteRowFinder,
        matching: find.byIcon(LucideIcons.star),
      );
      expect(starFinder, findsOneWidget);
      await tester.tap(starFinder);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Favorites'), findsNothing);
    });

    testWidgets('Recent table row click opens query editor tab', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await appProvider.recentTables.recordTableAccess(
        connectionId: server.id,
        databaseName: testDbName,
        tableName: 'seed_table',
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Recent rows are InkWell children with a RichText label, not TreeItems.
      final recentRowFinder = find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains(' · seed_table'),
      );
      expect(recentRowFinder, findsOneWidget);
      await tester.tap(recentRowFinder);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.tab.tabs, isNotEmpty);
      expect(appProvider.tab.tabs.last.sql.toLowerCase(), contains('select'));
      expect(
        appProvider.tab
            .panelLayoutFor(appProvider.tab.tabs.last.id)
            .editorVisible,
        isTrue,
        reason: '最近表行点击应进 query 模式（editor 可见）',
      );
    });

    testWidgets('Favorite table row click opens query editor tab', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      final tableKey = '${server.id}:$testDbName:seed_table';
      appProvider.sidebar.toggleFavoriteTable(tableKey);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final favoriteRowFinder = find.ancestor(
        of: find.textContaining('seed_table'),
        matching: find.byType(TreeItem),
      );
      expect(favoriteRowFinder, findsOneWidget);
      await tester.tap(favoriteRowFinder);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.tab.tabs, isNotEmpty);
      expect(appProvider.tab.tabs.last.sql.toLowerCase(), contains('select'));
      expect(
        appProvider.tab
            .panelLayoutFor(appProvider.tab.tabs.last.id)
            .editorVisible,
        isTrue,
        reason: '收藏表行点击应进 query 模式（editor 可见）',
      );
    });

    testWidgets('saved query row click opens query tab', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      final query = QueryTab(
        id: 'sq_click_${testDbName.hashCode}',
        title: 'Clickable Query',
        sql: 'SELECT 2',
        connectionId: server.id,
        databaseName: testDbName,
        databaseType: DatabaseType.mysql,
        isSaved: true,
      );
      await appProvider.saveQuery(query);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final savedQueriesHeader = find.ancestor(
        of: find.textContaining('Saved Queries'),
        matching: find.byType(TreeItem),
      );
      await tester.tap(savedQueriesHeader);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final queryRow = find.ancestor(
        of: find.text('Clickable Query'),
        matching: find.byType(TreeItem),
      );
      expect(queryRow, findsOneWidget);
      // Saved-query rows open on double-tap; single-tap only selects the node.
      await tester.tap(queryRow);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(queryRow);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.tab.tabs, isNotEmpty);
      expect(appProvider.tab.tabs.last.sql, contains('SELECT 2'));
    });

    testWidgets(
      'database menu > Schema Diff compares source and target databases',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);

        await rightClickNode(tester, testDbName);
        await tapMenuItem(tester, 'Schema Diff & Sync');
        await tester.pumpAndSettle(const Duration(seconds: 3));

        final dialogFinder = find.byType(SchemaDiffDialog);
        expect(dialogFinder, findsOneWidget);

        Future<void> selectDropdown(int index, String itemText) async {
          final dropdownFinder = find
              .descendant(
                of: dialogFinder,
                matching: find.byType(DropdownButtonFormField<String>),
              )
              .at(index);
          await tester.ensureVisible(dropdownFinder);
          await tester.pumpAndSettle(const Duration(seconds: 1));
          await tester.tap(dropdownFinder);
          await tester.pumpAndSettle(const Duration(seconds: 1));
          final itemFinder = find.descendant(
            of: find.byType(DropdownMenuItem<String>),
            matching: find.text(itemText),
          );
          await tester.tap(itemFinder.last);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }

        // Select target connection (source is already selected).
        await selectDropdown(2, connectionLabel);

        // Select target database.
        await selectDropdown(3, diffTargetDbName);

        // Compare.
        final compareFinder = find.text('Compare').last;
        await tester.ensureVisible(compareFinder);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        await tester.tap(compareFinder);
        await tester.pumpAndSettle(const Duration(seconds: 8));

        // The diff tree should appear with source tables missing from target.
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('Schema Objects'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: dialogFinder, matching: find.text('seed_table')),
          findsAtLeastNWidgets(1),
        );
      },
    );

    testWidgets('column leaf > Copy column name copies correct text', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            captured = call.arguments['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': captured};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // MySQL returns the column type lower-cased in the schema cache.
      await rightClickNodeContaining(tester, 'varchar(100)');
      await tapMenuItem(tester, 'Copy column name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'name');
    });

    testWidgets('index leaf > Copy index name copies correct text', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            captured = call.arguments['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': captured};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'idx_seed_name');
      await tapMenuItem(tester, 'Copy index name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'idx_seed_name');
    });

    testWidgets('view node > Copy Name copies correct text', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            captured = call.arguments['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': captured};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Views');

      await rightClickNode(tester, 'seed_view');
      await tapMenuItem(tester, 'Copy Name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'seed_view');
    });

    testWidgets('procedure node > Copy Name copies correct text', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            captured = call.arguments['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': captured};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Procedures');

      await rightClickNode(tester, 'seed_proc');
      await tapMenuItem(tester, 'Copy Name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'seed_proc');
    });

    // ----------------------------------------------------------------------
    // Schema leaf selection
    // ----------------------------------------------------------------------
    testWidgets('column leaf single-click selects the leaf node', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final columnFinder = find.ancestor(
        of: find.text('id'),
        matching: find.byType(TreeItem),
      );
      expect(columnFinder, findsOneWidget);

      await tester.tap(columnFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final columnItem = tester.widget<TreeItem>(columnFinder);
      expect(columnItem.isSelected, isTrue);
    });

    testWidgets('foreign key leaf single-click selects the leaf node', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_fk_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final fkFinder = find.ancestor(
        of: find.textContaining('fk_seed_id  (seed_id →'),
        matching: find.byType(TreeItem),
      );
      expect(fkFinder, findsOneWidget);

      await tester.tap(fkFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final fkItem = tester.widget<TreeItem>(fkFinder);
      expect(fkItem.isSelected, isTrue);
    });

    // ----------------------------------------------------------------------
    // Save Schema Snapshot — real persistence
    // ----------------------------------------------------------------------
    testWidgets(
      'database menu > Save Schema Snapshot persists a snapshot file',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);

        final diffService = SchemaDiffService(appProvider.dbService);
        final snapshotService = SchemaSnapshotService(diffService);
        final before = await snapshotService.listSnapshots();

        await rightClickNode(tester, testDbName);
        await tapMenuItem(tester, 'Save Schema Snapshot');
        await tester.pumpAndSettle(const Duration(seconds: 6));

        final after = await snapshotService.listSnapshots();
        expect(after.length, greaterThan(before.length));

        final latest = after.first;
        expect(latest.name, contains(connectionLabel));
        expect(latest.name, contains(testDbName));
        expect(await File(latest.filePath).exists(), isTrue);

        // Cleanup so snapshots do not accumulate across runs.
        await snapshotService.deleteSnapshot(latest.id);
      },
    );

    // ----------------------------------------------------------------------
    // Performance node auto-refresh
    // ----------------------------------------------------------------------
    testWidgets(
      'Performance node interval selector starts and stops auto-refresh',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandCategory(tester, 'Performance');
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Expanding Performance defaults to a 10-second refresh interval.
        expect(appProvider.getProcessListAutoRefreshInterval(server.id), 10);

        final chip5s = find.text('5s').last;
        await tester.ensureVisible(chip5s);
        await tester.tap(chip5s);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(appProvider.getProcessListAutoRefreshInterval(server.id), 5);

        final chipOff = find.text('Off').last;
        await tester.ensureVisible(chipOff);
        await tester.tap(chipOff);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(
          appProvider.getProcessListAutoRefreshInterval(server.id),
          isNull,
        );
      },
    );

    // ----------------------------------------------------------------------
    // Process leaf real actions
    // ----------------------------------------------------------------------
    testWidgets('process leaf menu > Copy Query copies the running query', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // Start a long-running query from a separate connection.
      final queryAdapter = MySQLAdapter();
      await queryAdapter.connect(
        DatabaseConnection(
          id: 'query_copy_${testDbName.hashCode}',
          name: 'Query Copy Connection',
          type: DatabaseType.mysql,
          host: MySQLTestConfig.host,
          port: MySQLTestConfig.port,
          username: MySQLTestConfig.username,
          password: MySQLTestConfig.password,
        ),
      );
      final sleepFuture = queryAdapter.executeQuery('SELECT SLEEP(15)');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            captured = call.arguments['text'] as String?;
            return null;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandCategory(tester, 'Performance');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final processes = appProvider.getProcessList(server.id);
      expect(processes, isNotNull);
      final target = processes!.firstWhere(
        (p) =>
            (p['Info']?.toString() ?? '').toUpperCase().contains('SLEEP') &&
            p['Id'] != null,
        orElse: () => throw StateError('No SLEEP process found in $processes'),
      );
      final pid = int.parse(target['Id'].toString());

      final rowFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TreeItem && (widget.label?.startsWith('[$pid]') ?? false),
      );
      expect(rowFinder, findsOneWidget);
      await tester.ensureVisible(rowFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(rowFinder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tapMenuItem(tester, 'Copy Query');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, isNotNull);
      expect(captured!.toUpperCase(), contains('SLEEP'));

      // Clean up the slow query so the test does not have to wait.
      await appProvider.killProcess(server.id, pid);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await queryAdapter.disconnect();
      try {
        await sleepFuture;
      } catch (_) {}
    });

    testWidgets('process leaf menu > Kill Query terminates a running query', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final victimAdapter = MySQLAdapter();
      await victimAdapter.connect(
        DatabaseConnection(
          id: 'victim_${testDbName.hashCode}',
          name: 'Kill Victim Connection',
          type: DatabaseType.mysql,
          host: MySQLTestConfig.host,
          port: MySQLTestConfig.port,
          username: MySQLTestConfig.username,
          password: MySQLTestConfig.password,
        ),
      );
      final sleepFuture = victimAdapter.executeQuery('SELECT SLEEP(15)');
      // T29：网关模型下 kill 经服务端断链/SSE error 上抛（旧裸连接是
      // 1317 中断异常）。错误落点可能早于末尾的 await，先挂吞吃防
      // unhandled async error 污染测试框架；语义断言不依赖该异常值。
      unawaited(
        sleepFuture.catchError(
          (Object _) => QueryResult(columns: const [], rows: const []),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandCategory(tester, 'Performance');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final processes = appProvider.getProcessList(server.id);
      expect(processes, isNotNull);
      final target = processes!.firstWhere(
        (p) =>
            (p['Info']?.toString() ?? '').toUpperCase().contains('SLEEP') &&
            p['Id'] != null,
        orElse: () => throw StateError('No SLEEP process found in $processes'),
      );
      final pid = int.parse(target['Id'].toString());

      final rowFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TreeItem && (widget.label?.startsWith('[$pid]') ?? false),
      );
      expect(rowFinder, findsOneWidget);
      await tester.ensureVisible(rowFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(rowFinder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tapMenuItem(tester, 'Kill Query');
      await tapDialogButton(tester, 'Kill Query');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // The query should no longer appear in the process list.
      final after = appProvider.getProcessList(server.id);
      expect(after?.any((p) => int.parse(p['Id'].toString()) == pid), isFalse);

      await victimAdapter.disconnect();
      try {
        await sleepFuture;
      } catch (_) {}
    });

    // ----------------------------------------------------------------------
    // Connection grouping (C22-1: 树内拖拽随连接卡下线，分组迁选择器下拉)
    // ----------------------------------------------------------------------
    testWidgets('connection grouping via menu shows in selector dropdown', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      const groupName = 'Drag Test Group';
      final groupId = 'drag_group_${testDbName.hashCode}';
      await appProvider.addConnectionGroup(
        ConnectionGroup(id: groupId, name: groupName, color: '#00FF00'),
      );

      final secondServer = DbServer(
        id: '${server.id}_ingroup',
        name: 'MySQL Sidebar E2E In Group',
        type: DatabaseType.mysql,
        host: server.host,
        port: server.port,
        username: server.username,
        password: server.password,
        groupId: groupId,
      );
      await appProvider.connection.saveConnection(secondServer);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        appProvider.connection.savedConnections
            .firstWhere((s) => s.id == server.id)
            .groupId,
        isNull,
      );

      // 主连接经根行右键菜单移入分组（拖拽路径已下线，菜单是唯一入口）。
      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Move to $groupName');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        appProvider.connection.savedConnections
            .firstWhere((s) => s.id == server.id)
            .groupId,
        groupId,
      );

      // 选择器下拉按组分区：组头 + 组内成员可见。
      await tester.tap(find.byIcon(LucideIcons.chevronsUpDown));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text(groupName), findsOneWidget);
      expect(find.text('MySQL Sidebar E2E In Group'), findsOneWidget);
    });
  });
}

// =============================================================================
// Minimal SidebarTree harness that mirrors SidebarWidget state management.
// =============================================================================
class _SidebarTestHarness extends StatefulWidget {
  final AppProvider provider;

  const _SidebarTestHarness({required this.provider});

  @override
  State<_SidebarTestHarness> createState() => _SidebarTestHarnessState();
}

class _SidebarTestHarnessState extends State<_SidebarTestHarness> {
  Set<String> _expandedItems = {};
  Set<String> _expandedDatabases = {};
  Set<String> _expandedTables = {};
  Set<String> _loadingDatabases = {};
  final Map<String, DbTable> _loadedTableSchemas = {};
  final Map<String, List<ForeignKey>> _loadedTableForeignKeys = {};
  final Set<String> _loadingTableSchemas = {};
  String? _rightClickedNodeKey;
  String? _selectedNodeKey;

  void _toggleExpand(String key) {
    setState(() {
      if (_expandedItems.contains(key)) {
        _expandedItems = _expandedItems.where((e) => e != key).toSet();
      } else {
        _expandedItems = {..._expandedItems, key};
      }
    });
  }

  void _toggleDatabase(String key) {
    setState(() {
      if (_expandedDatabases.contains(key)) {
        _expandedDatabases = _expandedDatabases.where((e) => e != key).toSet();
      } else {
        _expandedDatabases = {..._expandedDatabases, key};
      }
    });
  }

  void _toggleTable(String key) {
    final willExpand = !_expandedTables.contains(key);
    setState(() {
      if (_expandedTables.contains(key)) {
        _expandedTables = _expandedTables.where((e) => e != key).toSet();
      } else {
        _expandedTables = {..._expandedTables, key};
      }
    });
    if (willExpand) _loadTableSchema(key);
  }

  Future<void> _loadTableSchema(String tableKey) async {
    if (_loadingTableSchemas.contains(tableKey) ||
        _loadedTableSchemas.containsKey(tableKey)) {
      return;
    }
    final parts = tableKey.split(':');
    if (parts.length < 3) return;
    final connectionId = parts[0];
    final databaseName = parts[1];
    final tableName = parts.sublist(2).join(':');

    setState(() => _loadingTableSchemas.add(tableKey));
    try {
      final provider = widget.provider;
      final dbType = provider.dbService.getDatabaseType(connectionId);
      final columns = await provider.dbService.getTableColumns(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      final indexes = await provider.dbService.getTableIndexes(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      List<ForeignKey>? foreignKeys;
      if (dbType?.supportsForeignKeys ?? false) {
        foreignKeys = await provider.dbService.getForeignKeys(
          tableName,
          connectionId: connectionId,
          databaseName: databaseName,
        );
      }
      setState(() {
        _loadedTableSchemas[tableKey] = DbTable(
          name: tableName,
          columns: columns,
          indexes: indexes,
        );
        if (foreignKeys != null && foreignKeys.isNotEmpty) {
          _loadedTableForeignKeys[tableKey] = foreignKeys;
        }
        _loadingTableSchemas.remove(tableKey);
      });
    } catch (_) {
      setState(() => _loadingTableSchemas.remove(tableKey));
    }
  }

  Future<void> _loadDatabaseInfo(
    String connectionId,
    String databaseName,
  ) async {
    final key = '$connectionId:$databaseName';
    setState(() => _loadingDatabases = {..._loadingDatabases, key});
    try {
      await widget.provider.loadDatabaseInfo(connectionId, databaseName);
    } finally {
      setState(
        () => _loadingDatabases = _loadingDatabases
            .where((e) => e != key)
            .toSet(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // C22-1：树只渲染当前连接——连接/切换已保存服务器的入口是顶部
      // 选择器下拉（镜像 sidebar_widget 的组合与 onConnectionTap 接线）。
      body: Column(
        children: [
          SidebarConnectionSelector(
            onConnectionTap: (server) async {
              final ok = await widget.provider.connectToServer(server);
              if (ok) await widget.provider.refreshDatabases();
            },
            onManageConnections: () {},
          ),
          Expanded(
            child: SidebarTree(
              expandedItems: _expandedItems,
              expandedDatabases: _expandedDatabases,
              expandedTables: _expandedTables,
              loadingDatabases: _loadingDatabases,
              loadedTableSchemas: _loadedTableSchemas,
              loadedTableForeignKeys: _loadedTableForeignKeys,
              loadingTableSchemas: _loadingTableSchemas,
              onToggleExpand: _toggleExpand,
              onToggleDatabase: _toggleDatabase,
              onToggleTable: _toggleTable,
              onLoadDatabaseInfo: _loadDatabaseInfo,
              onLoadTableSchema: _loadTableSchema,
              onShowConnectionManager: () {},
              onShowSettings: () {},
              onShowERDiagram: () {},
              onShowStoredProcedures: () {},
              onShowTriggers: () {},
              onCollapseAll: () {
                setState(() {
                  _expandedItems = {};
                  _expandedDatabases = {};
                  _expandedTables = {};
                });
              },
              rightClickedNodeKey: _rightClickedNodeKey,
              onRightClickTargetChanged: (key) {
                setState(() => _rightClickedNodeKey = key);
              },
              selectedNodeKey: _selectedNodeKey,
              onSelectNode: (key) {
                setState(() => _selectedNodeKey = key);
              },
            ),
          ),
        ],
      ),
    );
  }
}
