// ============================================================================
// Table Management Integration Test
// Tests: Connect -> Create table -> Verify in sidebar -> Insert data -> 
//        Modify table -> Drop table -> Verify removed
// Uses SQLite (file-based, no external server required)
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/main.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/pro_module.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Table Management', () {
    late String dbPath;

    setUp(() async {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      dbPath = '${tempDir.path}/dbmaster_table_mgmt_test_$timestamp.db';
    });

    tearDown(() async {
      try {
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

    Future<AppProvider> setupApp(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
            ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
            ChangeNotifierProvider(
              create: (_) => LayoutPreferencesProvider()..load(),
            ),
          ],
          child: DbmasterApp(proModule: NoOpProModule()),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      
      final context = tester.element(find.byType(MaterialApp));
      return Provider.of<AppProvider>(context, listen: false);
    }

    testWidgets('create table and verify in database', (tester) async {
      final appProvider = await setupApp(tester);

      final testServer = DbServer(
        id: 'test_sqlite_table_mgmt',
        name: 'SQLite Table Mgmt Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      // Save and connect
      await appProvider.connection.saveConnection(testServer);
      final connected = await appProvider.connectToServer(testServer);
      expect(connected, isTrue, reason: 'Failed to connect to SQLite');
      await tester.pump(const Duration(seconds: 1));

      // Verify workspace is shown
      expect(find.byKey(const ValueKey('main_workspace')), findsOneWidget);

      // Load database info to populate sidebar
      await appProvider.loadDatabaseInfo(testServer.id, 'main');
      await tester.pump();

      // Verify database is loaded
      final db = appProvider.getCachedDatabase(testServer.id, 'main');
      expect(db, isNotNull);
      expect(db!.tables, isEmpty);

      // Step 1: Create a table via SQL
      const createTableSql = '''
        CREATE TABLE test_products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          price REAL,
          category TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      ''';

      appProvider.updateTabSql(appProvider.activeTabIndex, createTableSql);
      final createResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(createResult, isNotEmpty);
      expect(createResult.first.success, isTrue);

      // Reload database info to verify table appears
      await appProvider.loadDatabaseInfo(testServer.id, 'main');
      await tester.pump();

      final dbAfterCreate = appProvider.getCachedDatabase(testServer.id, 'main');
      expect(dbAfterCreate, isNotNull);
      expect(dbAfterCreate!.tables.length, 1);
      expect(dbAfterCreate.tables.first.name, 'test_products');

      // Step 2: Insert data
      const insertSql = '''
        INSERT INTO test_products (name, price, category) VALUES 
        ('Laptop', 999.99, 'Electronics'),
        ('Mouse', 29.99, 'Electronics'),
        ('Desk', 299.99, 'Furniture')
      ''';

      appProvider.updateTabSql(appProvider.activeTabIndex, insertSql);
      final insertResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(insertResult.first.success, isTrue);
      expect(insertResult.first.affectedRows, 3);

      // Step 3: Verify table structure via query
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        "PRAGMA table_info(test_products)",
      );
      final schemaResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(schemaResult.first.success, isTrue);
      expect(schemaResult.first.data!.length, 5); // 5 columns

      // Verify column names
      final columnNames = schemaResult.first.data!
          .map((r) => r['name'] as String)
          .toList();
      expect(columnNames, contains('id'));
      expect(columnNames, contains('name'));
      expect(columnNames, contains('price'));
      expect(columnNames, contains('category'));
      expect(columnNames, contains('created_at'));

      // Step 4: Add a column (ALTER TABLE)
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'ALTER TABLE test_products ADD COLUMN stock INTEGER DEFAULT 0',
      );
      final alterResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(alterResult.first.success, isTrue);

      // Verify new column exists
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        "PRAGMA table_info(test_products)",
      );
      final schemaAfterAlter = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(schemaAfterAlter.first.data!.length, 6); // Now 6 columns
      final newColumnNames = schemaAfterAlter.first.data!
          .map((r) => r['name'] as String)
          .toList();
      expect(newColumnNames, contains('stock'));

      // Step 5: Update data in new column
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        "UPDATE test_products SET stock = 10 WHERE name = 'Laptop'",
      );
      final updateResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(updateResult.first.success, isTrue);
      expect(updateResult.first.affectedRows, 1);

      // Step 6: Verify data with new column
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'SELECT * FROM test_products WHERE name = "Laptop"',
      );
      final verifyResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(verifyResult.first.data!.first['stock'], 10);

      // Step 7: Drop the table
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'DROP TABLE test_products',
      );
      final dropResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(dropResult.first.success, isTrue);

      // Reload and verify table is gone
      await appProvider.loadDatabaseInfo(testServer.id, 'main');
      await tester.pump();

      final dbAfterDrop = appProvider.getCachedDatabase(testServer.id, 'main');
      expect(dbAfterDrop!.tables, isEmpty);

      // Verify table no longer queryable
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'SELECT * FROM test_products',
      );
      final errorResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(errorResult.first.success, isFalse);

      await appProvider.disconnectConnection(connectionId: testServer.id);
      await tester.pump();
    });

    testWidgets('create multiple tables with relationships', (tester) async {
      final appProvider = await setupApp(tester);

      final testServer = DbServer(
        id: 'test_sqlite_relations_${DateTime.now().millisecondsSinceEpoch}',
        name: 'SQLite Relations Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await appProvider.connection.saveConnection(testServer);
      final connected = await appProvider.connectToServer(testServer);
      expect(connected, isTrue);
      await tester.pump(const Duration(seconds: 1));

      // Create customers table
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        '''CREATE TABLE customers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT UNIQUE
        )''',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Create orders table with FK
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        '''CREATE TABLE orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER,
          total REAL,
          status TEXT DEFAULT 'pending',
          FOREIGN KEY (customer_id) REFERENCES customers(id)
        )''',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Reload database info
      await appProvider.loadDatabaseInfo(testServer.id, 'main');
      await tester.pump();

      final db = appProvider.getCachedDatabase(testServer.id, 'main');
      expect(db!.tables.length, 2);
      final tableNames = db.tables.map((t) => t.name).toList()..sort();
      expect(tableNames, equals(['customers', 'orders']));

      // Insert customers
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        "INSERT INTO customers (name, email) VALUES ('John', 'john@example.com'), ('Jane', 'jane@example.com')",
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Insert orders
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        '''INSERT INTO orders (customer_id, total, status) VALUES 
           (1, 150.00, 'completed'),
           (1, 75.50, 'pending'),
           (2, 200.00, 'completed')''',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Test foreign key constraint (should fail if enabled)
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'PRAGMA foreign_keys = ON',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'INSERT INTO orders (customer_id, total) VALUES (999, 50.00)',
      );
      final fkResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // With FK enabled, this should fail
      expect(fkResult.first.success, isFalse);

      // Test query with join
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        '''SELECT c.name, COUNT(o.id) as order_count, SUM(o.total) as total_spent
           FROM customers c
           LEFT JOIN orders o ON c.id = o.customer_id
           GROUP BY c.id
           ORDER BY total_spent DESC''',
      );
      final joinResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(joinResult.first.success, isTrue);
      expect(joinResult.first.data!.length, 2);

      // John should have more total (150 + 75.50 = 225.50)
      expect(joinResult.first.data!.first['name'], 'John');
      expect(joinResult.first.data!.first['order_count'], 2);

      // Drop tables
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'DROP TABLE orders',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'DROP TABLE customers',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Verify both tables are gone
      await appProvider.loadDatabaseInfo(testServer.id, 'main');
      await tester.pump();

      final dbAfterDrop = appProvider.getCachedDatabase(testServer.id, 'main');
      expect(dbAfterDrop!.tables, isEmpty);

      await appProvider.disconnectConnection(connectionId: testServer.id);
      await tester.pump();
    });

    testWidgets('table rename and index management', (tester) async {
      final appProvider = await setupApp(tester);

      final testServer = DbServer(
        id: 'test_sqlite_rename_${DateTime.now().millisecondsSinceEpoch}',
        name: 'SQLite Rename Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await appProvider.connection.saveConnection(testServer);
      final connected = await appProvider.connectToServer(testServer);
      expect(connected, isTrue);
      await tester.pump(const Duration(seconds: 1));

      // Create table
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'CREATE TABLE old_name (id INTEGER PRIMARY KEY, data TEXT)',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Insert data
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        "INSERT INTO old_name (data) VALUES ('test data')",
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Rename table
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'ALTER TABLE old_name RENAME TO new_name',
      );
      final renameResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(renameResult.first.success, isTrue);

      // Verify old name doesn't work
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'SELECT * FROM old_name',
      );
      final oldNameResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(oldNameResult.first.success, isFalse);

      // Verify new name works
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'SELECT * FROM new_name',
      );
      final newNameResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(newNameResult.first.success, isTrue);
      expect(newNameResult.first.data!.first['data'], 'test data');

      // Create index
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'CREATE INDEX idx_data ON new_name(data)',
      );
      final indexResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(indexResult.first.success, isTrue);

      // Verify index exists
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'SELECT name FROM sqlite_master WHERE type = "index" AND tbl_name = "new_name"',
      );
      final indexesResult = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(indexesResult.first.data!.length, 1);
      expect(indexesResult.first.data!.first['name'], 'idx_data');

      // Drop index
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'DROP INDEX idx_data',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Drop table
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'DROP TABLE new_name',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      await appProvider.disconnectConnection(connectionId: testServer.id);
      await tester.pump();
    });
  });
}
