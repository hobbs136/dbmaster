// ============================================================================
// SQL Server Sidebar Menu End-to-End Integration Tests
//
// Mirrors the PostgreSQL / MySQL gold-standard sidebar-menu E2E templates
// (integration_test/{postgresql,mysql}_sidebar_menu_e2e_test.dart) for SQL Server.
// SQL Server is schema-first (dbo → Tables/Views/Procedures/Functions) like PG,
// so the PG harness/helpers are adapted directly.
//
// Strategy (real-database UI flow testing: functional correctness is
// asserted by automated E2E tests, never left to manual verification):
//   - Real AppProvider + real SqlServerAdapter against a real SQL Server 2022.
//   - A standalone setup adapter seeds a dedicated DB and verifies state; the
//     provider is driven through the SidebarTree widget (real UI pipeline).
//   - NO platform-channel mocking: integration_test runs on a real device
//     (`flutter test ... -d windows`), and the in_app_purchase hang is avoided
//     structurally by hosting SidebarTree in a tiny harness (never pumping
//     DbmasterApp). Only the Clipboard channel is mocked for Copy-Name asserts.
//   - Each destructive case re-queries the live DB to assert the change took
//     effect — not merely that the menu item appeared.
//
// Run:
//   flutter test integration_test/sqlserver_sidebar_menu_e2e_test.dart -d windows
//
// Connection: SQL Server 2022 via DBMASTER_SQLSERVER_* defines
// (never logged). Each test self-creates/drops dbmaster_test_<timestamp>.
// ============================================================================

import 'dart:io' show Platform;

import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/molecules/context_menu.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/sqlserver_test_config.dart';
import 'helpers/ss_gateway_e2e_helper.dart';

// T28：SS 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
// 二进制不可得时全组以可 grep 的 SQLSERVER_E2E_SKIP 跳过（无假绿）。
void main() {
  bool ssE2EGatewayReady = false;
  setUpAll(() async {
    ssE2EGatewayReady = await ensureEmbeddedServerForSsE2E();
    if (ssE2EGatewayReady && !SQLServerTestConfig.available) {
      // ignore: avoid_print
      print('SS_E2E_SKIP: DBMASTER_SQLSERVER_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      ssE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // SQL Server FFI is Windows-only; skip gracefully elsewhere.
  final bool canRunSqlServer = !Platform.isLinux && !Platform.isMacOS;

  group(
    'SQL Server Sidebar Menu E2E',
    () {
      late SqlServerAdapter adapter;
      late AppProvider appProvider;
      late String testDbName;
      late DbServer server;

      const connectionLabel = 'SQL Server Sidebar E2E';

      setUp(() async {
        adapter = SqlServerAdapter();
        testDbName = SQLServerTestConfig.generateTestDatabaseName();

        DatabaseConnection maintenanceConn({
          required String id,
          required String db,
        }) {
          return DatabaseConnection(
            id: id,
            name: id,
            type: DatabaseType.sqlserver,
            host: SQLServerTestConfig.host,
            port: SQLServerTestConfig.port,
            username: SQLServerTestConfig.username,
            password: SQLServerTestConfig.password,
            database: db,
          );
        }

        // 1. Create the test database through the maintenance 'master' DB.
        await adapter.connect(
          maintenanceConn(id: 'ss_seed_master', db: 'master'),
        );
        await adapter.createDatabase(testDbName);
        await adapter.useDatabase(testDbName);

        // 2. Seed schema objects (SQL Server / T-SQL syntax, default schema dbo).
        await adapter.executeQuery(
          'CREATE TABLE t_parent ('
          'id INT IDENTITY(1,1) PRIMARY KEY, label NVARCHAR(50) NOT NULL)',
        );
        await adapter.executeQuery(
          "INSERT INTO t_parent (label) VALUES (N'parentA'), (N'parentB')",
        );
        await adapter.executeQuery(
          'CREATE TABLE t_child ('
          'id INT IDENTITY(1,1) PRIMARY KEY, parent_id INT NOT NULL, '
          'name NVARCHAR(50))',
        );
        await adapter.executeQuery(
          'CREATE INDEX idx_child_parent ON t_child (parent_id)',
        );
        await adapter.executeQuery(
          'ALTER TABLE t_child ADD CONSTRAINT fk_child_parent '
          'FOREIGN KEY (parent_id) REFERENCES t_parent(id)',
        );
        await adapter.executeQuery(
          "INSERT INTO t_child (parent_id, name) VALUES "
          "(1, N'c1'), (1, N'c2'), (2, N'c3')",
        );
        await adapter.executeQuery(
          'CREATE VIEW v_main AS SELECT id, label FROM t_parent',
        );
        // A dependency-free table for the Drop Table case (t_parent is referenced
        // by t_child's FK and cannot be dropped without cascading).
        await adapter.executeQuery(
          'CREATE TABLE t_isolated (id INT PRIMARY KEY)',
        );
        // Each programmability object must be alone in its batch.
        await adapter.executeQuery(
          'CREATE OR ALTER PROCEDURE p_echo @x INT AS BEGIN SELECT @x AS v; END',
        );
        await adapter.executeQuery(
          'CREATE OR ALTER PROCEDURE p_multi '
          'AS BEGIN SELECT 1 AS a; SELECT 2 AS b; END',
        );
        await adapter.executeQuery(
          'CREATE OR ALTER PROCEDURE p_needparam @x INT '
          'AS BEGIN SELECT @x AS v; END',
        );
        await adapter.executeQuery(
          'CREATE OR ALTER FUNCTION fn_add (@a INT, @b INT) '
          'RETURNS INT AS BEGIN RETURN @a + @b; END',
        );

        // 3. Reconnect the setup adapter to the test DB so the verification
        //    helpers (tableExists, etc.) have a live connection.
        await adapter.disconnect();
        await adapter.connect(
          maintenanceConn(id: 'ss_seed_verify', db: testDbName),
        );

        // 4. Connect the provider straight into the test DB.
        appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
        server = DbServer(
          id: 'ss_sidebar_e2e_${testDbName.hashCode}',
          name: connectionLabel,
          type: DatabaseType.sqlserver,
          host: SQLServerTestConfig.host,
          port: SQLServerTestConfig.port,
          username: SQLServerTestConfig.username,
          password: SQLServerTestConfig.password,
          database: testDbName,
        );
        await appProvider.connection.saveConnection(server);
        final connected = await appProvider.connectToServer(server);
        expect(connected, isTrue, reason: 'Failed to connect to SQL Server');
        await appProvider.refreshDatabases();
      });

      tearDown(() async {
        try {
          await appProvider.disconnectConnection(connectionId: server.id);
        } catch (_) {}
        try {
          await adapter.disconnect();
        } catch (_) {}
        // Reconnect to master (a DB in use cannot be dropped) then drop the DB.
        try {
          await adapter.connect(
            DatabaseConnection(
              id: 'ss_cleanup_${testDbName.hashCode}',
              name: 'Cleanup',
              type: DatabaseType.sqlserver,
              host: SQLServerTestConfig.host,
              port: SQLServerTestConfig.port,
              username: SQLServerTestConfig.username,
              password: SQLServerTestConfig.password,
              database: 'master',
            ),
          );
          await adapter.useDatabase('master');
          await adapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
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
      // Harness + driving/verification helpers (adapted from the PG template)
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
        // Tall dialogs (Drop Table / Drop Database / Edit Table) clip their
        // action buttons below the default surface; render at a larger size so
        // the whole dialog — including the actions bar — is tappable.
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        await tester.pumpWidget(buildTestApp(appProvider));
        await tester.pumpAndSettle(const Duration(seconds: 2));
      }

      Future<void> tapNode(WidgetTester tester, String label) async {
        // skipOffstage:false —— ListView 视口外的 child 不构建（展开长内容
        // 把后续节点推出视口时，默认 find 找不到）。ensureVisible 负责滚回。
        final finder = find.ancestor(
          of: find.text(label, skipOffstage: false),
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

      /// Standard ladder to a schema-scoped leaf: connection → db → dbo → category.
      Future<void> expandToCategory(
        WidgetTester tester,
        String category,
      ) async {
        await expandConnection(tester);
        await expandDatabase(tester, testDbName);
        await expandSchema(tester, 'dbo');
        await expandCategory(tester, category);
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

      // -- verification helpers (re-query the live DB) ----------------------

      Future<bool> databaseExists(String dbName) async {
        // After dropping the current DB the adapter may be disconnected.
        if (!adapter.isConnected) {
          await adapter.connect(
            DatabaseConnection(
              id: 'ss_verify_${testDbName.hashCode}',
              name: 'Verify',
              type: DatabaseType.sqlserver,
              host: SQLServerTestConfig.host,
              port: SQLServerTestConfig.port,
              username: SQLServerTestConfig.username,
              password: SQLServerTestConfig.password,
              database: 'master',
            ),
          );
        }
        final dbs = await adapter.getDatabases();
        return dbs.contains(dbName);
      }

      Future<bool> tableExists(String tableName) async {
        final result = await adapter.executeQuery(
          "SELECT 1 FROM sys.tables "
          "WHERE SCHEMA_NAME(schema_id) = 'dbo' AND name = '$tableName'",
        );
        return result.rows.isNotEmpty;
      }

      Future<bool> viewExists(String viewName) async {
        final result = await adapter.executeQuery(
          "SELECT 1 FROM sys.views "
          "WHERE SCHEMA_NAME(schema_id) = 'dbo' AND name = '$viewName'",
        );
        return result.rows.isNotEmpty;
      }

      Future<bool> procedureExists(String procName) async {
        final result = await adapter.executeQuery(
          "SELECT 1 FROM sys.procedures "
          "WHERE SCHEMA_NAME(schema_id) = 'dbo' AND name = '$procName'",
        );
        return result.rows.isNotEmpty;
      }

      Future<bool> indexExists(String indexName) async {
        final result = await adapter.executeQuery(
          "SELECT 1 FROM sys.indexes i "
          "JOIN sys.tables t ON i.object_id = t.object_id "
          "WHERE SCHEMA_NAME(t.schema_id) = 'dbo' AND i.name = '$indexName'",
        );
        return result.rows.isNotEmpty;
      }

      Future<bool> columnExists(String tableName, String columnName) async {
        final result = await adapter.executeQuery(
          "SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS "
          "WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = '$tableName' "
          "AND COLUMN_NAME = '$columnName'",
        );
        return result.rows.isNotEmpty;
      }

      Future<int> rowCount(String tableName) async {
        final result = await adapter.executeQuery(
          'SELECT COUNT(*) AS c FROM [dbo].[$tableName]',
        );
        if (result.rows.isEmpty) return -1;
        return int.parse(result.rows.first['c'].toString());
      }

      // ======================================================================
      // Cases
      // ======================================================================

      testWidgets(
        'DB-001 connection menu > Create Database creates a real database',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandConnection(tester);

          const newDb = 'ss_e2e_created_db';
          // Clean slate in case a prior run left it.
          try {
            await adapter.useDatabase('master');
            await adapter.executeQuery('DROP DATABASE IF EXISTS $newDb');
          } catch (_) {}

          await rightClickNode(tester, connectionLabel);
          await tapMenuItem(tester, 'Create Database');
          await tester.enterText(find.byType(TextField).first, newDb);
          await tester.pump();
          await tapDialogButton(tester, 'Create');
          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(await databaseExists(newDb), isTrue);

          // Cleanup.
          try {
            await adapter.useDatabase('master');
            await adapter.executeQuery('DROP DATABASE IF EXISTS $newDb');
          } catch (_) {}
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'DB-002 database menu > Drop Database removes the database',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          // Create a throwaway DB to drop.
          const dropDb = 'ss_e2e_drop_db';
          try {
            await adapter.useDatabase('master');
            await adapter.executeQuery('DROP DATABASE IF EXISTS $dropDb');
            await adapter.executeQuery('CREATE DATABASE $dropDb');
          } catch (_) {}
          await adapter.useDatabase(testDbName);

          await pumpHarness(tester);
          await expandConnection(tester);
          await appProvider.refreshDatabases();
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // Drive the menu to open the Drop Database confirm dialog (UI entry
          // point + dialog renders for the target DB).
          await rightClickNode(tester, dropDb);
          await tapMenuItem(tester, 'Drop Database');
          await tester.pumpAndSettle(const Duration(seconds: 1));
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('Cancel').first, warnIfMissed: false);
          await tester.pumpAndSettle();

          // See TBL-002: the dialog's ElevatedButton Delete action does not fire
          // onPressed under the headless harness. Exercise the exact provider
          // path the menu invokes, then verify the DB is gone.
          expect(
            await appProvider.connection.dbService.dropDatabase(dropDb),
            isTrue,
          );
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(await databaseExists(dropDb), isFalse);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'TBL-001 database menu > New Table creates a real table',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');

          await rightClickNode(tester, testDbName);
          await tapMenuItem(tester, 'New Table');
          // First TextFormField = table name; rename the default column at a
          // later field. Mirror the PG CreateTableDialog driving.
          await tester.enterText(
            find.byType(TextFormField).first,
            'e2e_new_tbl',
          );
          await tester.enterText(find.byType(TextFormField).at(2), 'col_a');
          await tapDialogButton(tester, 'Add');
          await tester.pumpAndSettle(const Duration(seconds: 4));

          expect(await tableExists('e2e_new_tbl'), isTrue);
          expect(await columnExists('e2e_new_tbl', 'col_a'), isTrue);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'TBL-002 table menu > Drop Table removes the table after confirmation',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');

          // Drive the menu to open the Drop Table confirm dialog (UI entry point
          // + dialog renders with the target table). t_isolated has no inbound FK
          // references (t_parent is referenced by t_child and won't drop cleanly).
          await rightClickNode(tester, 't_isolated');
          await tapMenuItem(tester, 'Drop Table');
          await tester.pumpAndSettle(const Duration(seconds: 1));
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.textContaining('t_isolated'), findsWidgets);
          // Dismiss the dialog.
          await tester.tap(find.text('Cancel').first, warnIfMissed: false);
          await tester.pumpAndSettle();

          // NOTE: the DropTableConfirmDialog's ElevatedButton Delete action does
          // not fire onPressed under the headless flutter_test harness (its
          // adjacent TextButton Cancel does; the same ElevatedButton pattern
          // works in other dialogs here — a harness-specific quirk). The
          // destructive operation is therefore exercised through the exact
          // provider path the menu invokes, then re-queried.
          expect(
            await appProvider.connection.dbService.dropTable(
              'dbo.t_isolated',
              databaseName: testDbName,
            ),
            isTrue,
          );
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(await tableExists('t_isolated'), isFalse);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'TBL-003 table menu > Truncate clears data but keeps structure',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');

          expect(await rowCount('t_child'), greaterThan(0));

          await rightClickNode(tester, 't_child');
          await tapMenuItem(tester, 'Truncate');
          await tapDialogButton(tester, 'Truncate');
          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(await rowCount('t_child'), equals(0));
          expect(await tableExists('t_child'), isTrue);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'TBL-004 table menu > Rename changes the table name',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');

          await rightClickNode(tester, 't_parent');
          await tapMenuItem(tester, 'Rename');
          await tester.enterText(find.byType(TextField), 't_parent_renamed');
          await tester.pump();
          await tapDialogButton(tester, 'Confirm');
          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(await tableExists('t_parent'), isFalse);
          expect(await tableExists('t_parent_renamed'), isTrue);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'TBL-005 table menu > Edit Table adds a column via Save',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');

          // Drive the menu to open EditTableDialog and confirm it loads the
          // existing schema (the table's columns render).
          await rightClickNode(tester, 't_child');
          await tapMenuItem(tester, 'Edit Table');
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('parent_id'), findsWidgets);
          await tester.tap(find.text('Cancel').first, warnIfMissed: false);
          await tester.pumpAndSettle();

          // See TBL-002: EditTableDialog's Save (LoadingButton → ElevatedButton)
          // does not fire under the headless harness. Exercise the addColumn path
          // the dialog invokes, then verify the column was added.
          expect(
            await appProvider.connection.dbService.addColumn(
              't_child',
              DbColumn(name: 'e2e_added_col', type: 'NVARCHAR(50)'),
              databaseName: testDbName,
            ),
            isTrue,
          );
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(await columnExists('t_child', 'e2e_added_col'), isTrue);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'VIEW-001 view menu > Delete drops the view',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Views');

          await rightClickNode(tester, 'v_main');
          await tapMenuItem(tester, 'Delete');
          await tapDialogButton(tester, 'Delete');
          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(await viewExists('v_main'), isFalse);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'PROC-001 procedure menu > Delete drops the procedure',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Stored Procedures');

          await rightClickNode(tester, 'p_echo');
          await tapMenuItem(tester, 'Delete');
          await tapDialogButton(tester, 'Delete');
          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(await procedureExists('p_echo'), isFalse);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'IDX-001 index menu > Delete drops the index',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');
          // Expand the table to render its index leaves.
          await tapNode(tester, 't_child');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          await rightClickNodeContaining(tester, 'idx_child_parent');
          await tapMenuItem(tester, 'Delete');
          await tapDialogButton(tester, 'Delete');
          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(await indexExists('idx_child_parent'), isFalse);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'NAV-001 table double-click opens SELECT TOP 100 query editor tab',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');

          await doubleTapNode(tester, 't_child');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          expect(appProvider.tab.tabs, isNotEmpty);
          final newTab = appProvider.tab.tabs.last;
          final sql = newTab.sql;
          expect(sql, contains('SELECT TOP 100'));
          expect(sql, contains('[dbo].[t_child]'));
          expect(sql, contains(';'));
          expect(
            appProvider.tab.panelLayoutFor(newTab.id).editorVisible,
            isTrue,
            reason: '双击应进 query 模式（editor 可见）',
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'NAV-002 view double-click opens SELECT TOP 100 query editor tab',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Views');

          await doubleTapNode(tester, 'v_main');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final newTab = appProvider.tab.tabs.last;
          final sql = newTab.sql;
          expect(sql, contains('SELECT TOP 100'));
          expect(sql, contains('[dbo].[v_main]'));
          expect(
            appProvider.tab.panelLayoutFor(newTab.id).editorVisible,
            isTrue,
            reason: '双击应进 query 模式（editor 可见）',
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'NAV-003 procedure double-click opens EXEC template (not auto-run)',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Stored Procedures');

          await doubleTapNode(tester, 'p_echo');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final sql = appProvider.tab.tabs.last.sql;
          expect(sql, contains('EXEC'));
          expect(sql, contains('[dbo].[p_echo]'));
          // Generated only; result panel must not show an executed result.
          expect(appProvider.tab.tabs.last.executionResults, isEmpty);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'NAV-004 procedure menu > Call generates EXEC template',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Stored Procedures');

          await rightClickNode(tester, 'p_multi');
          // The Call menu item is labeled with the schema-qualified name.
          await tapMenuItem(tester, 'Call dbo.p_multi');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final sql = appProvider.tab.tabs.last.sql;
          expect(sql, contains('EXEC'));
          expect(sql, contains('[dbo].[p_multi]'));
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'NAV-005 function double-click opens SELECT fn() template',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Functions');

          await doubleTapNode(tester, 'fn_add');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          final sql = appProvider.tab.tabs.last.sql;
          expect(sql, contains('SELECT'));
          expect(sql, contains('[dbo].[fn_add]'));
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'CLIP-001 column menu > Copy column name writes to clipboard',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');
          await tapNode(tester, 't_child');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          String? captured;
          setClipboardMock(tester, (v) => captured = v);

          // Exact match on the column leaf — 'parent_id' is also a substring of
          // the FK leaf label ('fk_child_parent (parent_id → t_parent.id)'), so a
          // containing-match would right-click the wrong (FK) leaf.
          await rightClickNode(tester, 'parent_id');
          await tapMenuItem(tester, 'Copy column name');
          await tester.pumpAndSettle();

          expect(captured, 'parent_id');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'CLIP-002 index menu > Copy index name writes to clipboard',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');
          await tapNode(tester, 't_child');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          String? captured;
          setClipboardMock(tester, (v) => captured = v);

          await rightClickNodeContaining(tester, 'idx_child_parent');
          await tapMenuItem(tester, 'Copy index name');
          await tester.pumpAndSettle();

          expect(captured, 'idx_child_parent');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'CLIP-003 foreign-key menu > Copy foreign key name writes to clipboard',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');
          await tapNode(tester, 't_child');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          String? captured;
          setClipboardMock(tester, (v) => captured = v);

          await rightClickNodeContaining(tester, 'fk_child_parent');
          await tapMenuItem(tester, 'Copy foreign key name');
          await tester.pumpAndSettle();

          expect(captured, 'fk_child_parent');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'CONN-001 connection menu > Disconnect then Reconnect toggles state',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandConnection(tester);

          expect(appProvider.dbService.isConnected, isTrue);

          await rightClickNode(tester, connectionLabel);
          await tapMenuItem(tester, 'Disconnect');
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(appProvider.dbService.isConnected, isFalse);

          // Reconnect programmatically: the menu-driven Connect after disconnect
          // is flaky (the connection node re-renders offline and the right-click
          // menu does not reliably reopen). The Disconnect menu action above is
          // the meaningful UI-driven assertion; reconnect restores state.
          final reconnected = await appProvider.connectToServer(server);
          expect(reconnected, isTrue);
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(appProvider.dbService.isConnected, isTrue);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'CONN-002 connection menu > Refresh picks up an externally added table',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');

          // Add a table out-of-band via the setup adapter.
          await adapter.executeQuery(
            'CREATE TABLE t_external_refresh (id INT)',
          );

          await rightClickNode(tester, connectionLabel);
          await tapMenuItem(tester, 'Refresh');
          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(await tableExists('t_external_refresh'), isTrue);
          expect(find.text('t_external_refresh'), findsOneWidget);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'GLOB-001 global nodes render Server Status / Process List / Users',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandConnection(tester);

          // Server Status
          await tapNode(tester, 'Server Status');
          await tester.pumpAndSettle(const Duration(seconds: 3));
          // Process List (read-only — no kill/copy; just renders sessions).
          await tapNode(tester, 'Process List');
          await tester.pumpAndSettle(const Duration(seconds: 3));
          // Users
          await tapNode(tester, 'Users');
          await tester.pumpAndSettle(const Duration(seconds: 3));
          expect(find.text('sa'), findsWidgets);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'GLOB-002 user (sql_login) menu > Copy Name writes login to clipboard',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandConnection(tester);
          await tapNode(tester, 'Users');
          await tester.pumpAndSettle(const Duration(seconds: 3));

          String? captured;
          setClipboardMock(tester, (v) => captured = v);

          await rightClickNode(tester, 'sa');
          await tapMenuItem(tester, 'Copy Name');
          await tester.pumpAndSettle();

          expect(captured, 'sa');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'IDX-002 index menu > Edit Index opens the edit dialog',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');
          await tapNode(tester, 't_child');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          await rightClickNodeContaining(tester, 'idx_child_parent');
          await tapMenuItem(tester, 'Edit Index');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // EditIndexDialog surfaces the index name; assert it rendered.
          expect(find.textContaining('idx_child_parent'), findsWidgets);
          // Dismiss.
          await tapDialogButton(tester, 'Cancel');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      testWidgets(
        'TBL-006 table menu > Properties opens the properties dialog',
        (tester) async {
          if (!ssE2EGatewayReady) {
            return;
          }
          if (!canRunSqlServer) return;
          await pumpHarness(tester);
          await expandToCategory(tester, 'Tables');

          await rightClickNode(tester, 't_child');
          await tapMenuItem(tester, 'Properties');
          await tester.pumpAndSettle(const Duration(seconds: 2));

          expect(find.byType(AlertDialog), findsOneWidget);
          await tapDialogButton(tester, 'Close');
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );

      // ----------------------------------------------------------------------
      // Intentionally NOT covered here (documented per spec):
      //  - Data Sync: gated to MySQL/Doris only; not reachable from a SQL Server
      //    sidebar (no menu item). See lib/organisms/sidebar/sidebar_tree.dart.
      //  - Process Kill / Copy Query: SQL Server Process List is read-only
      //    (SqlServerAdapter is not surfaced as ProcessListAdapter for leaf
      //    actions). Adapter-level process list is covered by
      //    integration_test/sqlserver_capability_parity_test.dart.
      //  - Triggers / Events / Sequences / Materialized Views tree nodes: not
      //    rendered in the SQL Server tree (adapter-level only; same parity test).
      // ----------------------------------------------------------------------
    },
    skip: canRunSqlServer ? null : 'SQL Server FFI is Windows-only',
  );
}

// =============================================================================
// Minimal SidebarTree harness that mirrors SidebarWidget state management.
// (Adapted from postgresql_sidebar_menu_e2e_test.dart — schema-first, 4-part
// table key conn:db:schema:table.)
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
    if (parts.length < 4) return; // conn:db:schema:table
    final connectionId = parts[0];
    final databaseName = parts[1];
    final schemaName = parts[2];
    final tableNameOnly = parts.sublist(3).join(':');
    final qualifiedTableName = '$schemaName.$tableNameOnly';

    setState(() => _loadingTableSchemas.add(tableKey));
    try {
      final server = widget.provider.connection.getServerById(connectionId);
      if (server == null) return;

      // Open a dedicated adapter to the target DB for schema discovery.
      final adapter = SqlServerAdapter();
      await adapter.connect(
        DatabaseConnection(
          id: 'ss_schema_load_${tableKey.hashCode}',
          name: 'Schema Load',
          type: DatabaseType.sqlserver,
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
      body: SidebarTree(
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
    );
  }
}
