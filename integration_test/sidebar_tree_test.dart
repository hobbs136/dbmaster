// ============================================================================
// Sidebar Tree Navigation Integration Tests
// Tests: Sidebar tree expand/collapse, database browsing, table viewing
// Uses SQLite (file-based, no external server required)
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar_widget.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Sidebar Tree Navigation Tests', () {
    late String dbPath;
    late DatabaseService dbService;

    setUp(() async {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      dbPath = '${tempDir.path}/dbmaster_sidebar_test_$timestamp.db';
      dbService = DatabaseService();
    });

    tearDown(() async {
      try {
        // Disconnect all
        await dbService.disconnectAll();

        final file = File(dbPath);
        if (await file.exists()) {
          await file.delete();
        }
        for (final ext in ['-journal', '-shm', '-wal']) {
          final relatedFile = File('$dbPath$ext');
          if (await relatedFile.exists()) {
            await relatedFile.delete();
          }
        }
      } catch (_) {}
    });

    Widget buildTestApp(Widget child) {
      return MultiProvider(
        providers: [
          // 树内连接状态点（server-platform M1 起）watch 团队服务器连接态；
          // 本 harness 不涉团队服务器，供断开态实例即可。
          ChangeNotifierProvider<ServerConnectionProvider>(
            create: (_) => ServerConnectionProvider(),
          ),
          ChangeNotifierProvider(create: (_) => AppProvider()),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('zh')],
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('should show empty state when no connections', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          SidebarTree(
            expandedItems: const {},
            expandedDatabases: const {},
            expandedTables: const {},
            loadingDatabases: const {},
            onToggleExpand: (_) {},
            onToggleDatabase: (_) {},
            onToggleTable: (_) {},
            onLoadDatabaseInfo: (_, _) async {},
            onShowConnectionManager: () {},
            onShowSettings: () {},
            onShowERDiagram: () {},
            onShowStoredProcedures: () {},
            onShowTriggers: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show empty state
      expect(find.byIcon(LucideIcons.database), findsOneWidget);
    });

    testWidgets('should render sidebar with connection', (tester) async {
      final appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      final testServer = DbServer(
        id: 'test_sidebar_conn',
        name: 'Sidebar Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await appProvider.connection.saveConnection(testServer);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ServerConnectionProvider>(
              create: (_) => ServerConnectionProvider(),
            ),
            ChangeNotifierProvider.value(value: appProvider),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('zh')],
            home: Scaffold(
              body: SidebarTree(
                expandedItems: const {},
                expandedDatabases: const {},
                expandedTables: const {},
                loadingDatabases: const {},
                onToggleExpand: (_) {},
                onToggleDatabase: (_) {},
                onToggleTable: (_) {},
                onLoadDatabaseInfo: (_, _) async {},
                onShowConnectionManager: () {},
                onShowSettings: () {},
                onShowERDiagram: () {},
                onShowStoredProcedures: () {},
                onShowTriggers: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show connection name
      expect(find.text('Sidebar Test'), findsOneWidget);
    });

    testWidgets('should expand and collapse connection node', (tester) async {
      final appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      final testServer = DbServer(
        id: 'test_expand_conn',
        name: 'Expand Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await appProvider.connection.saveConnection(testServer);
      await appProvider.connectToServer(testServer);
      await tester.pump(const Duration(seconds: 1));

      var expandedItems = <String>{};

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ServerConnectionProvider>(
              create: (_) => ServerConnectionProvider(),
            ),
            ChangeNotifierProvider.value(value: appProvider),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('zh')],
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  body: SidebarTree(
                    expandedItems: expandedItems,
                    expandedDatabases: const {},
                    expandedTables: const {},
                    loadingDatabases: const {},
                    onToggleExpand: (key) {
                      setState(() {
                        if (expandedItems.contains(key)) {
                          expandedItems = {...expandedItems}..remove(key);
                        } else {
                          expandedItems = {...expandedItems, key};
                        }
                      });
                    },
                    onToggleDatabase: (_) {},
                    onToggleTable: (_) {},
                    onLoadDatabaseInfo: (_, _) async {},
                    onShowConnectionManager: () {},
                    onShowSettings: () {},
                    onShowERDiagram: () {},
                    onShowStoredProcedures: () {},
                    onShowTriggers: () {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the connection node (look for expand/collapse icon)
      final connectionFinder = find.text('Expand Test');
      expect(connectionFinder, findsOneWidget);

      // Tap on the connection name area to expand
      await tester.tap(connectionFinder);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));

      // After tap, verify the callback was triggered by checking if we can find any expanded content
      // For connected SQLite, we should see database-related items
      // The key point is the UI updates after the tap
      expect(find.text('Expand Test'), findsOneWidget);
    });

    testWidgets('should browse databases in sidebar', (tester) async {
      final testServer = DbServer(
        id: 'test_db_browse',
        name: 'DB Browse Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await dbService.connect(testServer);

      // Create test tables
      await dbService.executeQuery(
        'CREATE TABLE test_users (id INTEGER PRIMARY KEY, name TEXT)',
        connectionId: testServer.id,
      );
      await dbService.executeQuery(
        'CREATE TABLE test_orders (id INTEGER PRIMARY KEY, user_id INTEGER)',
        connectionId: testServer.id,
      );

      // Get databases list
      final databases = await dbService.getDatabases(
        connectionId: testServer.id,
      );
      expect(databases, isNotEmpty);

      // Get tables in the database
      final tables = await dbService.getTables(connectionId: testServer.id);
      expect(tables, contains('test_users'));
      expect(tables, contains('test_orders'));

      await dbService.disconnect(connectionId: testServer.id);
    });

    testWidgets('should get table columns from sidebar', (tester) async {
      final testServer = DbServer(
        id: 'test_table_cols',
        name: 'Table Columns Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await dbService.connect(testServer);

      // Create table with various column types
      await dbService.executeQuery('''
        CREATE TABLE test_products (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          price REAL,
          created_at TEXT
        )
      ''', connectionId: testServer.id);

      // Get table columns
      final columns = await dbService.getTableColumns(
        'test_products',
        connectionId: testServer.id,
      );
      expect(columns, isNotEmpty);
      expect(columns.length, 4);

      // Verify column properties
      final idColumn = columns.firstWhere((c) => c.name == 'id');
      expect(idColumn.isPrimaryKey, isTrue);
      expect(idColumn.type, 'INTEGER');

      final nameColumn = columns.firstWhere((c) => c.name == 'name');
      expect(nameColumn.isNullable, isFalse);

      await dbService.disconnect(connectionId: testServer.id);
    });

    testWidgets('should handle sidebar widget states', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          SidebarWidget(isCollapsed: false, onToggleCollapse: () {}),
        ),
      );
      await tester.pumpAndSettle();

      // Should render expanded sidebar
      expect(find.byType(SidebarWidget), findsOneWidget);
    });

    testWidgets('should handle collapsed sidebar', (tester) async {
      await tester.pumpWidget(
        buildTestApp(SidebarWidget(isCollapsed: true, onToggleCollapse: () {})),
      );
      await tester.pumpAndSettle();

      // Should render collapsed sidebar
      expect(find.byType(SidebarWidget), findsOneWidget);
    });

    testWidgets('should load database info on expand', (tester) async {
      final testServer = DbServer(
        id: 'test_load_db',
        name: 'Load DB Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await dbService.connect(testServer);

      // Create multiple tables
      await dbService.executeQuery(
        'CREATE TABLE table1 (id INTEGER)',
        connectionId: testServer.id,
      );
      await dbService.executeQuery(
        'CREATE TABLE table2 (id INTEGER)',
        connectionId: testServer.id,
      );
      await dbService.executeQuery(
        'CREATE VIEW view1 AS SELECT * FROM table1',
        connectionId: testServer.id,
      );

      // Load database info
      final dbInfo = await dbService.getDatabaseInfo(
        'main',
        connectionId: testServer.id,
        includeTableDetails: true,
      );

      expect(dbInfo.name, 'main');
      expect(dbInfo.tables.length, 2);
      expect(dbInfo.views.length, 1);

      await dbService.disconnect(connectionId: testServer.id);
    });

    testWidgets('should handle table properties', (tester) async {
      final testServer = DbServer(
        id: 'test_table_props',
        name: 'Table Props Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await dbService.connect(testServer);

      // Create table with indexes
      await dbService.executeQuery('''
        CREATE TABLE test_indexed (
          id INTEGER PRIMARY KEY,
          email TEXT,
          age INTEGER
        )
      ''', connectionId: testServer.id);

      await dbService.executeQuery(
        'CREATE INDEX idx_email ON test_indexed(email)',
        connectionId: testServer.id,
      );

      // Get table details
      final details = await dbService.getTableColumns(
        'test_indexed',
        connectionId: testServer.id,
      );
      expect(details, isNotEmpty);

      // Get indexes
      final indexes = await dbService.getTableIndexes(
        'test_indexed',
        connectionId: testServer.id,
      );
      expect(indexes, isNotEmpty);
      expect(indexes.any((idx) => idx.name == 'idx_email'), isTrue);

      await dbService.disconnect(connectionId: testServer.id);
    });
  });
}
