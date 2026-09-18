// ============================================================================
// PostgreSQL Sidebar Menu End-to-End Integration Tests
// Tests: Real PostgreSQL server + full SidebarTree widget + context menus + dialogs
// Target: real PostgreSQL via DBMASTER_PG_* (see config/postgresql_test_config.dart)
// ============================================================================

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
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/schema_diff/schema_diff_service.dart';
import 'package:dbmaster/services/schema_diff/schema_snapshot_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

  group('PostgreSQL Sidebar Menu E2E', () {
    late AppProvider appProvider;
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late String syncTargetDbName;
    late String diffTargetDbName;
    late DbServer server;

    const connectionLabel = 'PostgreSQL Sidebar E2E';

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();

      // 1. Create the test database through the maintenance 'postgres' DB.
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

      // 2. Reconnect to the new test DB and seed schema objects.
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
        DbColumn(
          name: 'id',
          type: 'SERIAL',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ]);
      await adapter.executeQuery(
        "INSERT INTO \"seed_table\" (id, name) VALUES (1, 'Alice'), (2, 'Bob')",
      );
      await adapter.executeQuery(
        'CREATE INDEX "idx_seed_name" ON "seed_table" (name)',
      );
      await adapter.executeQuery('DROP TABLE IF EXISTS "seed_fk_table"');
      await adapter.executeQuery(
        'CREATE TABLE "seed_fk_table" (id SERIAL PRIMARY KEY, seed_id INTEGER)',
      );
      await adapter.executeQuery(
        'ALTER TABLE "seed_fk_table" ADD CONSTRAINT "fk_seed_id" '
        'FOREIGN KEY ("seed_id") REFERENCES "seed_table" ("id")',
      );

      // View, procedure, function, trigger, sequence, materialized view.
      await adapter.executeQuery(
        'CREATE OR REPLACE VIEW "seed_view" AS SELECT id, name FROM "seed_table"',
      );
      await adapter.executeQuery(
        'CREATE OR REPLACE FUNCTION "seed_fn"() RETURNS integer LANGUAGE plpgsql '
        'AS \$\$ BEGIN RETURN 1; END; \$\$',
      );
      await adapter.executeQuery(
        'CREATE OR REPLACE PROCEDURE "seed_proc"() LANGUAGE plpgsql '
        'AS \$\$ BEGIN NULL; END; \$\$',
      );
      await adapter.executeQuery(
        'CREATE OR REPLACE FUNCTION "seed_trigger_fn"() RETURNS trigger LANGUAGE plpgsql '
        'AS \$\$ BEGIN NEW.name = UPPER(NEW.name); RETURN NEW; END; \$\$',
      );
      await adapter.executeQuery(
        'DROP TRIGGER IF EXISTS "seed_trg" ON "seed_table"',
      );
      await adapter.executeQuery(
        'CREATE TRIGGER "seed_trg" BEFORE INSERT ON "seed_table" '
        'FOR EACH ROW EXECUTE FUNCTION "seed_trigger_fn"()',
      );
      await adapter.executeQuery(
        'CREATE SEQUENCE IF NOT EXISTS "seed_seq" START 1',
      );
      await adapter.executeQuery(
        'CREATE MATERIALIZED VIEW "seed_matview" AS SELECT id, name FROM "seed_table"',
      );

      // 3. Prepare auxiliary databases for Data Sync and Schema Diff tests.
      syncTargetDbName = '${testDbName}_sync';
      diffTargetDbName = '${testDbName}_diff';
      // Reconnect to postgres to create aux DBs.
      await adapter.disconnect();
      await adapter.connect(maintenanceConn);
      await adapter.executeQuery('DROP DATABASE IF EXISTS "$syncTargetDbName"');
      await adapter.executeQuery('CREATE DATABASE "$syncTargetDbName"');
      await adapter.executeQuery('DROP DATABASE IF EXISTS "$diffTargetDbName"');
      await adapter.executeQuery('CREATE DATABASE "$diffTargetDbName"');
      await adapter.disconnect();

      // Seed target table for Data Sync.
      await adapter.connect(
        DatabaseConnection(
          id: 'seed_sync_${testDbName.hashCode}',
          name: 'Seed Sync Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: syncTargetDbName,
        ),
      );
      await adapter.executeQuery(
        'CREATE TABLE "seed_table" (id INTEGER PRIMARY KEY, name VARCHAR(100))',
      );
      await adapter.disconnect();

      // Reconnect the seed adapter to the test database so helper queries
      // (tableExists, viewExists, etc.) have a live connection.
      await adapter.connect(
        DatabaseConnection(
          id: 'seed_${testDbName.hashCode}_verify',
          name: 'Verify Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: testDbName,
        ),
      );

      // 4. Now connect the provider so it picks up the seeded database.
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      server = DbServer(
        id: 'pg_sidebar_e2e_${testDbName.hashCode}',
        name: connectionLabel,
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: 'Failed to connect to PostgreSQL');
      await appProvider.refreshDatabases();
    });

    tearDown(() async {
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        final maintenanceConn = DatabaseConnection(
          id: 'cleanup_${testDbName.hashCode}',
          name: 'Cleanup Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        );
        await adapter.connect(maintenanceConn);
        await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
        await adapter.executeQuery(
          'DROP DATABASE IF EXISTS "$syncTargetDbName"',
        );
        await adapter.executeQuery(
          'DROP DATABASE IF EXISTS "$diffTargetDbName"',
        );
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
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
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
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
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
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
      await tester.ensureVisible(finder.last);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
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
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandDatabase(WidgetTester tester, String dbName) async {
      await tapNode(tester, dbName);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandSchema(WidgetTester tester, String schemaName) async {
      await tapNode(tester, schemaName);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> expandCategory(
      WidgetTester tester,
      String categoryPrefix,
    ) async {
      final headerFinder = find.ancestor(
        of: find.byWidgetPredicate((widget) {
          if (widget is Text) {
            final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
            return text == categoryPrefix ||
                text.startsWith('$categoryPrefix (');
          }
          return false;
        }),
        matching: find.byType(TreeItem),
      );
      expect(headerFinder, findsOneWidget);
      await tester.ensureVisible(headerFinder);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(headerFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<bool> databaseExists(String dbName) async {
      // T29 第二批：网关壳无持久连接态——drop 当前库后 isConnected 仍 true，
      // 但路由库已不存在（server 按路由库开池 → CONNECTION_FAILED）。
      // 恒重连维护库再核验（旧直连版靠 isConnected=false 触发重连）。
      final maintenanceConn = DatabaseConnection(
        id: 'verify_${testDbName.hashCode}',
        name: 'Verify Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      await adapter.connect(maintenanceConn);
      final dbs = await adapter.getDatabases();
      return dbs.contains(dbName);
    }

    Future<bool> tableExists(String tableName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.tables "
        "WHERE table_schema = 'public' AND table_name = '$tableName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> viewExists(String viewName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.views "
        "WHERE table_schema = 'public' AND table_name = '$viewName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> procedureExists(String procName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.routines "
        "WHERE routine_schema = 'public' AND routine_name = '$procName' "
        "AND routine_type = 'PROCEDURE'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> indexExists(String indexName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM pg_indexes "
        "WHERE schemaname = 'public' AND indexname = '$indexName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<bool> columnExists(String tableName, String columnName) async {
      final result = await adapter.executeQuery(
        "SELECT 1 FROM information_schema.columns "
        "WHERE table_schema = 'public' AND table_name = '$tableName' "
        "AND column_name = '$columnName'",
      );
      return result.rows.isNotEmpty;
    }

    Future<void> doubleTapNode(WidgetTester tester, String label) async {
      final finder = find.ancestor(
        of: find.text(label),
        matching: find.byType(TreeItem),
      );
      expect(finder, findsOneWidget, reason: 'Node "$label" not found');
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
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
      await tester.ensureVisible(finder.last);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(finder.last);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(finder.last);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    void setClipboardMock(
      WidgetTester tester,
      void Function(String?) onCaptured,
    ) {
      String? captured;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            captured = call.arguments['text'] as String?;
            onCaptured(captured);
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
    }

    // ----------------------------------------------------------------------
    // Connection node menu: Create Database
    // ----------------------------------------------------------------------
    testWidgets(
      'connection menu > Create Database creates a database and refreshes tree',
      (tester) async {
        if (!pgE2EGatewayReady) {
          return;
        }
        await pumpHarness(tester);
        await expandConnection(tester);

        final newDbName = '${testDbName}_created';

        await rightClickNode(tester, connectionLabel);
        await tapMenuItem(tester, 'Create Database');

        final nameField = find.byType(TextField).first;
        await tester.enterText(nameField, newDbName);
        await tester.pump();
        await tapDialogButton(tester, 'Create');

        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(await databaseExists(newDbName), isTrue);

        await adapter.disconnect();
        final maintenanceConn = DatabaseConnection(
          id: 'cleanup_created_${testDbName.hashCode}',
          name: 'Cleanup Created',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        );
        await adapter.connect(maintenanceConn);
        await adapter.executeQuery('DROP DATABASE IF EXISTS "$newDbName"');
      },
    );

    // ----------------------------------------------------------------------
    // Database node menu: Drop Database
    // ----------------------------------------------------------------------
    testWidgets('database menu > Drop Database drops the selected database', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, testDbName);
      await tapMenuItem(tester, 'Drop Database');

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
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);

      await rightClickNode(tester, testDbName);
      await tapMenuItem(tester, 'New Table');

      const newTableName = 'e2e_new_table';

      // CreatePostgresTableDialog: first TextFormField is the table name.
      final tableNameField = find.byType(TextFormField).first;
      await tester.enterText(tableNameField, newTableName);
      await tester.pump();

      // Rename the default column.
      final columnNameField = find.byType(TextFormField).at(2);
      await tester.enterText(columnNameField, 'col_a');
      await tester.pump();

      await tapDialogButton(tester, 'Add');

      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(await tableExists(newTableName), isTrue);
    });

    // ----------------------------------------------------------------------
    // Table node menu: Browse Data
    // ----------------------------------------------------------------------
    testWidgets(
      'table menu > Browse Data opens a query tab with SELECT results',
      (tester) async {
        if (!pgE2EGatewayReady) {
          return;
        }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);
        await expandSchema(tester, 'public');
        await expandCategory(tester, 'Tables');

        await rightClickNode(tester, 'seed_table');
        await tapMenuItem(tester, 'Browse Data');

        await tester.pumpAndSettle(const Duration(seconds: 3));

        // spec 041 US2 (T021)：browse 预设断言（PG）
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
          reason: 'browse tab FilterBar 应默认显示（PG 属 SQL 系）',
        );
        expect(
          appProvider.tab.browseTargetFor(activeId),
          contains('seed_table'),
          reason: 'browseTarget 应含表名',
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
      },
    );

    // ----------------------------------------------------------------------
    // Table node menu: Drop Table
    // ----------------------------------------------------------------------
    testWidgets(
      'table menu > Drop Table removes the table after confirmation',
      (tester) async {
        if (!pgE2EGatewayReady) {
          return;
        }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);
        await expandSchema(tester, 'public');
        await expandCategory(tester, 'Tables');

        await adapter.executeQuery('DROP TABLE IF EXISTS "seed_fk_table"');
        // seed_view and seed_matview reference seed_table and would block the
        // plain DROP TABLE in PostgreSQL, so remove them first.
        await adapter.executeQuery('DROP VIEW IF EXISTS "seed_view"');
        await adapter.executeQuery(
          'DROP MATERIALIZED VIEW IF EXISTS "seed_matview"',
        );

        // PostgreSQL dropTable uses the active connection's current database,
        // so make sure we are on the target database first.
        await appProvider.dbService.useDatabase(
          testDbName,
          connectionId: server.id,
        );

        await rightClickNode(tester, 'seed_table');
        await tapMenuItem(tester, 'Drop Table');

        // The drop-table confirmation dialog requires typing the table name.
        final dialogFinder = find.byType(AlertDialog);
        final confirmField = find.descendant(
          of: dialogFinder,
          matching: find.byType(TextField),
        );
        expect(confirmField, findsOneWidget);
        await tester.enterText(confirmField, 'seed_table');
        await tester.pump();

        await tapDialogButton(tester, 'Delete');
        await tester.pumpAndSettle(const Duration(seconds: 3));

        expect(await tableExists('seed_table'), isFalse);
      },
    );

    // ----------------------------------------------------------------------
    // Table node menu: Truncate Table
    // ----------------------------------------------------------------------
    testWidgets('table menu > Truncate clears table data but keeps structure', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');

      await adapter.executeQuery('DROP TABLE IF EXISTS "seed_fk_table"');

      await appProvider.dbService.useDatabase(
        testDbName,
        connectionId: server.id,
      );

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Truncate');

      await tapDialogButton(tester, 'Truncate');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final countResult = await adapter.executeQuery(
        'SELECT COUNT(*) AS c FROM "seed_table"',
      );
      expect(int.parse(countResult.rows.first['c'].toString()), 0);
      expect(await tableExists('seed_table'), isTrue);
    });

    // ----------------------------------------------------------------------
    // View node menu: Drop View
    // ----------------------------------------------------------------------
    testWidgets('view menu > Delete removes the view', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Views');

      await rightClickNode(tester, 'seed_view');
      await tapMenuItem(tester, 'Delete');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(await viewExists('seed_view'), isFalse);
    });

    // ----------------------------------------------------------------------
    // Procedure node menu: Drop Procedure
    // ----------------------------------------------------------------------
    testWidgets('procedure menu > Delete removes the procedure', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Stored Procedures');

      await rightClickNode(tester, 'seed_proc');
      await tapMenuItem(tester, 'Delete');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(await procedureExists('seed_proc'), isFalse);
    });

    // ----------------------------------------------------------------------
    // Global nodes
    // ----------------------------------------------------------------------
    testWidgets('Server global node expands and loads server info', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandCategory(tester, 'Server');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(find.textContaining('PostgreSQL'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Uptime:'), findsAtLeastNWidgets(1));
      expect(find.textContaining('connections'), findsAtLeastNWidgets(1));
    });

    testWidgets('Process List global node expands and shows process list', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandCategory(tester, 'Process List');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      final hasProcesses = find.textContaining(' · ').evaluate().isNotEmpty;
      final hasEmpty = find.textContaining('No sessions').evaluate().isNotEmpty;
      expect(hasProcesses || hasEmpty, isTrue);

      // PG has no auto-refresh interval chips.
      expect(find.text('5s'), findsNothing);
      expect(find.text('Off'), findsNothing);
    });

    testWidgets('Users global node expands and shows user list', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await expandCategory(tester, 'Users');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final hasUsers = find
          .textContaining(PostgreSQLTestConfig.username)
          .evaluate()
          .isNotEmpty;
      final hasEmpty = find.textContaining('No users').evaluate().isNotEmpty;
      expect(hasUsers || hasEmpty, isTrue);
    });

    testWidgets('user leaf > Copy Name copies correct text', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      String? captured;
      setClipboardMock(tester, (value) => captured = value);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandCategory(tester, 'Users');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // The default 'postgres' database node also contains the username text,
      // so target the last matching leaf under the expanded Users category.
      final userFinder = find.ancestor(
        of: find.textContaining(PostgreSQLTestConfig.username),
        matching: find.byType(TreeItem),
      );
      expect(userFinder, findsAtLeastNWidgets(1));

      final userLeaf = userFinder.last;
      await tester.ensureVisible(userLeaf);
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(userLeaf, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tapMenuItem(tester, 'Copy Name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, isNotNull);
      expect(captured, PostgreSQLTestConfig.username);
    });

    // ----------------------------------------------------------------------
    // Table node: double-click opens query editor tab
    // ----------------------------------------------------------------------
    testWidgets('table double-click opens query editor tab', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');

      final initialTabCount = appProvider.tab.tabs.length;
      await doubleTapNode(tester, 'seed_table');

      expect(appProvider.tab.tabs.length, initialTabCount + 1);
      final newTab = appProvider.tab.tabs.last;
      final layout = appProvider.tab.panelLayoutFor(newTab.id);
      expect(layout.editorVisible, isTrue, reason: '双击应进 query 模式（editor 可见）');
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
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
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
        reason: 'data 模式 FilterBar 应显示（PG 属 SQL 系）',
      );
      expect(
        appProvider.tab.browseTargetFor(newTab.id),
        'seed_view',
        reason: 'browseTarget 应为视图名（public schema 传裸名）',
      );
    });

    // ----------------------------------------------------------------------
    // Procedure node menu: Call
    // ----------------------------------------------------------------------
    testWidgets('procedure menu > Call opens CALL query tab', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Stored Procedures');

      final initialTabCount = appProvider.tab.tabs.length;
      await rightClickNode(tester, 'seed_proc');
      await tapMenuItem(tester, 'Call seed_proc');

      expect(appProvider.tab.tabs.length, initialTabCount + 1);
      final activeTab = appProvider.tab.activeTab;
      expect(activeTab?.sql.contains('CALL "seed_proc"'), isTrue);
    });

    // ----------------------------------------------------------------------
    // Function node: double-click opens SELECT query tab
    // ----------------------------------------------------------------------
    testWidgets('function double-click opens SELECT query tab', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Functions');

      final initialTabCount = appProvider.tab.tabs.length;
      await doubleTapNode(tester, 'seed_fn');

      expect(appProvider.tab.tabs.length, initialTabCount + 1);
      expect(appProvider.tab.activeTab?.sql, contains('SELECT seed_fn'));
    });

    // ----------------------------------------------------------------------
    // Materialized View node: double-click opens query editor tab
    // ----------------------------------------------------------------------
    testWidgets('materialized view double-click opens query editor tab', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Materialized Views');

      final initialTabCount = appProvider.tab.tabs.length;
      await doubleTapNode(tester, 'seed_matview');

      expect(appProvider.tab.tabs.length, initialTabCount + 1);
      final newTab = appProvider.tab.tabs.last;
      expect(
        appProvider.tab.panelLayoutFor(newTab.id).editorVisible,
        isTrue,
        reason: '双击物化视图应进 query 模式（editor 可见）',
      );
    });

    // ----------------------------------------------------------------------
    // Table node menu: Rename Table
    // ----------------------------------------------------------------------
    testWidgets('table menu > Rename renames the table', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');

      await adapter.executeQuery('DROP TABLE IF EXISTS "seed_fk_table"');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Rename');

      const newName = 'seed_table_renamed';
      final field = find.byType(TextField);
      await tester.enterText(field, newName);
      await tester.pump();
      await tapDialogButton(tester, 'Confirm');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(await tableExists('seed_table'), isFalse);
      expect(await tableExists(newName), isTrue);
    });

    // ----------------------------------------------------------------------
    // Connection node menu: Refresh / Disconnect / Connect
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Refresh refreshes database list', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
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
        if (!pgE2EGatewayReady) {
          return;
        }
        await pumpHarness(tester);
        await expandConnection(tester);

        const disconnectedLabel = 'PostgreSQL Sidebar E2E Disconnected';
        final disconnectedServer = DbServer(
          id: '${server.id}_disconnected',
          name: disconnectedLabel,
          type: DatabaseType.postgresql,
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
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      const secondLabel = 'PostgreSQL Sidebar E2E Second';
      final secondServer = DbServer(
        id: '${server.id}_second',
        name: secondLabel,
        type: DatabaseType.postgresql,
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
        if (!pgE2EGatewayReady) {
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

        // C22-1：根行双击在未连接态走连接流程。
        await doubleTapNode(tester, connectionLabel);
        await tester.pumpAndSettle(const Duration(seconds: 4));

        expect(appProvider.isConnectionConnected(server.id), isTrue);
      },
    );

    // ----------------------------------------------------------------------
    // Database node menu: Select Database / Refresh / Properties
    // ----------------------------------------------------------------------
    testWidgets('database menu > Select Database switches current database', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
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

    testWidgets('database menu > Properties opens properties dialog', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
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
    // Index leaf menu: Drop Index
    // ----------------------------------------------------------------------
    testWidgets('index leaf menu > Delete drops the index', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');

      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'idx_seed_name');
      await tapMenuItem(tester, 'Delete');

      await tapDialogButton(tester, 'Delete');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(await indexExists('idx_seed_name'), isFalse);
    });

    // ----------------------------------------------------------------------
    // Expand table node reveals Columns / Indexes / Foreign Keys
    // ----------------------------------------------------------------------
    testWidgets(
      'expanding a table node reveals columns, indexes and foreign keys',
      (tester) async {
        if (!pgE2EGatewayReady) {
          return;
        }
        await pumpHarness(tester);
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);
        await expandSchema(tester, 'public');
        await expandCategory(tester, 'Tables');

        await tapNode(tester, 'seed_table');
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.text('id'), findsWidgets);
        expect(find.text('name'), findsWidgets);
        expect(find.textContaining('Indexes'), findsWidgets);

        await tapNode(tester, 'seed_fk_table');
        await tester.pumpAndSettle(const Duration(seconds: 2));
        expect(find.textContaining('Foreign Keys'), findsWidgets);

        expect(await columnExists('seed_table', 'id'), isTrue);
        expect(await columnExists('seed_table', 'name'), isTrue);
      },
    );

    // ----------------------------------------------------------------------
    // Column / Index / FK leaf menus presence
    // ----------------------------------------------------------------------
    testWidgets('column leaf menu shows Copy Name / Type / All', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
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
      if (!pgE2EGatewayReady) {
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

      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await doubleTapNode(tester, 'id');
      expect(inserted, 'id');
    });

    testWidgets('index leaf menu shows Copy Name / Insert into Editor', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'idx_seed_name');

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy index name'), findsOneWidget);
      expect(find.text('Insert into editor'), findsOneWidget);
      expect(find.text('Edit Index'), findsOneWidget);
    });

    testWidgets('foreign key leaf menu shows Copy Name / Insert into Editor', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_fk_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'fk_seed_id');

      expect(find.byType(ContextMenu), findsOneWidget);
      expect(find.text('Copy foreign key name'), findsOneWidget);
      expect(find.text('Insert into editor'), findsOneWidget);
    });

    testWidgets(
      'foreign key leaf double-click inserts name into active editor',
      (tester) async {
        if (!pgE2EGatewayReady) {
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

        await expandSchema(tester, 'public');
        await expandCategory(tester, 'Tables');
        await tapNode(tester, 'seed_fk_table');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await doubleTapNodeContaining(tester, 'fk_seed_id');
        expect(inserted, 'fk_seed_id');
      },
    );

    // ----------------------------------------------------------------------
    // Connection node menu: Toggle Read-Only / Collapse All / Delete
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Toggle Read-Only changes read-only flag', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Enable Read-Only');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(appProvider.connection.getServerById(server.id)?.readOnly, isTrue);
    });

    testWidgets('connection menu > Collapse All collapses expanded nodes', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);

      expect(find.text(testDbName), findsWidgets);

      await rightClickNode(tester, connectionLabel);
      await tapMenuItem(tester, 'Collapse All');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text(testDbName), findsNothing);
    });

    testWidgets('connection menu > Delete removes the saved connection', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
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
    // View / Procedure / Sequence / Trigger node: Copy Name
    // ----------------------------------------------------------------------
    testWidgets('view menu > Copy Name copies correct text', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      String? captured;
      setClipboardMock(tester, (value) => captured = value);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Views');

      await rightClickNode(tester, 'seed_view');
      await tapMenuItem(tester, 'Copy Name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'seed_view');
    });

    testWidgets('procedure menu > Copy Name copies correct text', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      String? captured;
      setClipboardMock(tester, (value) => captured = value);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Stored Procedures');

      await rightClickNode(tester, 'seed_proc');
      await tapMenuItem(tester, 'Copy Name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'seed_proc');
    });

    testWidgets('sequence menu > Copy Name copies correct text', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      String? captured;
      setClipboardMock(tester, (value) => captured = value);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Sequences');

      await rightClickNode(tester, 'seed_seq');
      await tapMenuItem(tester, 'Copy Name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'seed_seq');
    });

    testWidgets('trigger menu > Copy Name copies correct text', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      String? captured;
      setClipboardMock(tester, (value) => captured = value);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Triggers');

      await rightClickNodeContaining(tester, 'seed_trg');
      await tapMenuItem(tester, 'Copy Name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'seed_trg');
    });

    // ----------------------------------------------------------------------
    // Tables category folder menu: Refresh
    // ----------------------------------------------------------------------
    testWidgets('Tables folder menu > Refresh reloads objects', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
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
      expect(find.text('Create Table'), findsNothing);

      await tapMenuItem(tester, 'Refresh');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('seed_table'), findsWidgets);
    });

    // ----------------------------------------------------------------------
    // Connection advanced actions
    // ----------------------------------------------------------------------
    testWidgets('connection menu > Edit Connection opens ConnectionDialog', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
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
        if (!pgE2EGatewayReady) {
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
        if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Properties');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(TablePropertiesDialog), findsOneWidget);
    });

    testWidgets('table menu > Edit Table opens edit table dialog', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Edit Table');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      expect(find.byType(EditTableDialog), findsOneWidget);

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
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');

      await rightClickNode(tester, 'seed_table');
      await tapMenuItem(tester, 'Edit Table');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      final dialogFinder = find.byType(EditTableDialog);
      expect(dialogFinder, findsOneWidget);

      await tester.tap(
        find.descendant(
          of: dialogFinder,
          matching: find.byIcon(LucideIcons.plus),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

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
      if (!pgE2EGatewayReady) {
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
        databaseType: DatabaseType.postgresql,
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

      await appProvider.openSavedQuery(query);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(appProvider.tab.tabs, isNotEmpty);

      await appProvider.renameSavedQuery(query.id, 'Renamed Query');
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('Renamed Query'), findsOneWidget);
      expect(find.text('My Saved Query'), findsNothing);

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
      if (!pgE2EGatewayReady) {
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

      final clearAllFinder = find.byIcon(LucideIcons.eraser);
      expect(clearAllFinder, findsOneWidget);
      await tester.tap(clearAllFinder);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('Favorite table section appears and can be unfavorited', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      final tableKey = '${server.id}:$testDbName:public.seed_table';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('sidebar_favorite_tables', [tableKey]);
      appProvider.sidebar.toggleFavoriteTable(tableKey);
      appProvider.notifyListeners();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.sidebar.favoriteTables, contains(tableKey));
      expect(find.byIcon(LucideIcons.star), findsWidgets);
      final favoriteRowFinder = find.ancestor(
        of: find.textContaining('seed_table'),
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
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);

      final tableKey = '${server.id}:$testDbName:public.seed_table';
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
      if (!pgE2EGatewayReady) {
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
        databaseType: DatabaseType.postgresql,
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
      await tester.tap(queryRow);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(queryRow);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(appProvider.tab.tabs, isNotEmpty);
      expect(appProvider.tab.tabs.last.sql, contains('SELECT 2'));
    });

    // ----------------------------------------------------------------------
    // Schema Diff & Sync
    // ----------------------------------------------------------------------
    testWidgets('database menu > Schema Diff & Sync opens Schema Diff dialog', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);

      await rightClickNode(tester, testDbName);
      await tapMenuItem(tester, 'Schema Diff & Sync');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(SchemaDiffDialog), findsOneWidget);
    });

    // ----------------------------------------------------------------------
    // Schema leaf copy actions
    // ----------------------------------------------------------------------
    testWidgets('column leaf > Copy column name copies correct text', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      String? captured;
      setClipboardMock(tester, (value) => captured = value);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNode(tester, 'name');
      await tapMenuItem(tester, 'Copy column name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'name');
    });

    testWidgets('index leaf > Copy index name copies correct text', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      String? captured;
      setClipboardMock(tester, (value) => captured = value);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await rightClickNodeContaining(tester, 'idx_seed_name');
      await tapMenuItem(tester, 'Copy index name');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, 'idx_seed_name');
    });

    // ----------------------------------------------------------------------
    // Schema leaf selection
    // ----------------------------------------------------------------------
    testWidgets('column leaf single-click selects the leaf node', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
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
      if (!pgE2EGatewayReady) {
        return;
      }
      await pumpHarness(tester);
      await expandConnection(tester);
      await expandDatabase(tester, testDbName);
      await expandSchema(tester, 'public');
      await expandCategory(tester, 'Tables');
      await tapNode(tester, 'seed_fk_table');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final fkFinder = find.ancestor(
        of: find.textContaining('fk_seed_id'),
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
        if (!pgE2EGatewayReady) {
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

        await snapshotService.deleteSnapshot(latest.id);
      },
    );

    // ----------------------------------------------------------------------
    // Process leaf real actions
    // ----------------------------------------------------------------------
    testWidgets('process leaf menu > Copy Query copies the running query', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final queryAdapter = PostgreSQLAdapter();
      // T29 第二批：SET application_name 在网关下不跨语句（每语句独立连接），
      // 旧标记失效；server 侧网关会话统一打 application_name='dbmaster-gw'
      //（PG 可观测性改进），进程树叶标签 = 'user · dbmaster-gw (state)'，
      // 慢查询窗口内唯一 active 行即目标。
      const activeMarker = 'dbmaster-gw (active';
      await queryAdapter.connect(
        DatabaseConnection(
          id: 'query_copy_${testDbName.hashCode}',
          name: 'Query Copy Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        ),
      );
      final sleepFuture = queryAdapter.executeQuery('SELECT pg_sleep(15)');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      String? captured;
      setClipboardMock(tester, (value) => captured = value);

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandCategory(tester, 'Process List');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      final rowFinder = find.ancestor(
        of: find.textContaining(activeMarker),
        matching: find.byType(TreeItem),
      );
      expect(rowFinder, findsOneWidget);
      await tester.ensureVisible(rowFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(rowFinder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tapMenuItem(tester, 'Copy Query');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(captured, isNotNull);
      expect(captured!.toUpperCase(), contains('PG_SLEEP'));

      // Locate the pid and kill the slow query to avoid waiting.
      //（网关口径：application_name='dbmaster-gw' + active 态定位）
      final processes = await appProvider.executeQuery(
        "SELECT pid FROM pg_stat_activity WHERE application_name = 'dbmaster-gw' AND state = 'active'",
        connectionId: server.id,
      );
      if (processes.isNotEmpty) {
        final pid = int.parse(processes.first['pid'].toString());
        await appProvider.killProcess(server.id, pid);
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
      await queryAdapter.disconnect();
      try {
        await sleepFuture;
      } catch (_) {}
    });

    testWidgets('process leaf menu > Kill Query terminates a running query', (
      tester,
    ) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final victimAdapter = PostgreSQLAdapter();
      // 同 Copy Query 测试：网关下 SET application_name 不跨语句，
      // 用 server 侧 'dbmaster-gw' + active 态定位受害者行。
      const activeMarker = 'dbmaster-gw (active';
      await victimAdapter.connect(
        DatabaseConnection(
          id: 'victim_${testDbName.hashCode}',
          name: 'Kill Victim Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        ),
      );
      final sleepFuture = victimAdapter.executeQuery('SELECT pg_sleep(15)');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await pumpHarness(tester);
      await expandConnection(tester);
      await expandCategory(tester, 'Process List');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      final rowFinder = find.ancestor(
        of: find.textContaining(activeMarker),
        matching: find.byType(TreeItem),
      );
      expect(rowFinder, findsOneWidget);
      await tester.ensureVisible(rowFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(rowFinder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      await tapMenuItem(tester, 'Kill Query');
      await tapDialogButton(tester, 'Kill Query');
      await tester.pumpAndSettle(const Duration(seconds: 4));

      // 终止后：不再有 active 的网关会话。`pid <> pg_backend_pid()` 排除
      // 本验证查询自身（执行瞬间它是 active 的网关会话，第一轮漏排实锤）。
      final after = await appProvider.executeQuery(
        "SELECT 1 FROM pg_stat_activity WHERE application_name = 'dbmaster-gw' AND state = 'active' AND pid <> pg_backend_pid()",
        connectionId: server.id,
      );
      expect(after, isEmpty);

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
      if (!pgE2EGatewayReady) {
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
        name: 'PostgreSQL Sidebar E2E In Group',
        type: DatabaseType.postgresql,
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
      expect(find.text('PostgreSQL Sidebar E2E In Group'), findsOneWidget);
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
    final schemaName = parts[2];
    final tableNameOnly = parts.sublist(3).join(':');
    final qualifiedTableName = '$schemaName.$tableNameOnly';

    setState(() => _loadingTableSchemas.add(tableKey));
    try {
      final server = widget.provider.connection.getServerById(connectionId);
      if (server == null) return;

      // PostgreSQL has no USE database; the shared DatabaseService schema
      // helpers ignore databaseName. Open a dedicated adapter to the target DB.
      final adapter = PostgreSQLAdapter();
      await adapter.connect(
        DatabaseConnection(
          id: 'schema_load_${tableKey.hashCode}',
          name: 'Schema Load',
          type: DatabaseType.postgresql,
          host: server.host,
          port: server.port,
          username: server.username,
          password: server.password,
          database: databaseName,
        ),
      );
      final columns = await adapter.getTableColumns(qualifiedTableName);
      final indexes = await adapter.getTableIndexes(qualifiedTableName);
      final foreignKeys = await adapter.getForeignKeys(qualifiedTableName);
      await adapter.disconnect();

      setState(() {
        _loadedTableSchemas[tableKey] = DbTable(
          name: qualifiedTableName,
          columns: columns,
          indexes: indexes,
        );
        if (foreignKeys.isNotEmpty) {
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
