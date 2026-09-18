// ============================================================================
// Query Workflow Integration Test
// Tests: Connect to DB -> Create table -> Insert data -> Query -> Verify results
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

  group('Query Workflow', () {
    late String dbPath;

    setUp(() async {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      dbPath = '${tempDir.path}/dbmaster_query_workflow_test_$timestamp.db';
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

    testWidgets('complete query workflow with SQLite', (tester) async {
      final appProvider = await setupApp(tester);

      final testServer = DbServer(
        id: 'test_sqlite_query_workflow',
        name: 'SQLite Query Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      // Save connection and connect
      await appProvider.connection.saveConnection(testServer);
      final connected = await appProvider.connectToServer(testServer);
      expect(connected, isTrue, reason: 'Failed to connect to SQLite database');
      await tester.pump(const Duration(seconds: 1));

      // Verify workspace is shown
      expect(find.byKey(const ValueKey('main_workspace')), findsOneWidget);

      // Verify a tab was created
      expect(find.textContaining('Query'), findsWidgets);

      // Step 1: Create a test table via SQL
      const createTableSql = '''
        CREATE TABLE test_users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT,
          age INTEGER
        )
      ''';

      appProvider.updateTabSql(appProvider.activeTabIndex, createTableSql);
      await tester.pump();

      final createResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(createResults, isNotEmpty);
      expect(createResults.first.success, isTrue);

      // Step 2: Insert test data
      const insertSql = '''
        INSERT INTO test_users (name, email, age) VALUES 
        ('Alice', 'alice@example.com', 30),
        ('Bob', 'bob@example.com', 25),
        ('Charlie', 'charlie@example.com', 35)
      ''';

      appProvider.updateTabSql(appProvider.activeTabIndex, insertSql);
      await tester.pump();

      final insertResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(insertResults, isNotEmpty);
      expect(insertResults.first.success, isTrue);
      expect(insertResults.first.affectedRows, 3);

      // Step 3: Query the data
      const selectSql = 'SELECT * FROM test_users ORDER BY id';

      appProvider.updateTabSql(appProvider.activeTabIndex, selectSql);
      await tester.pump();

      final selectResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(selectResults, isNotEmpty);
      expect(selectResults.first.success, isTrue);
      expect(selectResults.first.data, isNotEmpty);
      expect(selectResults.first.data!.length, 3);

      // Verify data content
      final firstRow = selectResults.first.data!.first;
      expect(firstRow['name'], 'Alice');
      expect(firstRow['email'], 'alice@example.com');
      expect(firstRow['age'], 30);

      // Step 4: Update data
      const updateSql = "UPDATE test_users SET age = 31 WHERE name = 'Alice'";

      appProvider.updateTabSql(appProvider.activeTabIndex, updateSql);
      await tester.pump();

      final updateResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(updateResults, isNotEmpty);
      expect(updateResults.first.success, isTrue);
      expect(updateResults.first.affectedRows, 1);

      // Step 5: Verify update
      appProvider.updateTabSql(appProvider.activeTabIndex, selectSql);
      await tester.pump();

      final verifyResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(verifyResults.first.data!.first['age'], 31);

      // Step 6: Delete data
      const deleteSql = "DELETE FROM test_users WHERE name = 'Bob'";

      appProvider.updateTabSql(appProvider.activeTabIndex, deleteSql);
      await tester.pump();

      final deleteResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(deleteResults, isNotEmpty);
      expect(deleteResults.first.success, isTrue);
      expect(deleteResults.first.affectedRows, 1);

      // Step 7: Verify deletion
      appProvider.updateTabSql(appProvider.activeTabIndex, selectSql);
      await tester.pump();

      final finalResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(finalResults.first.data!.length, 2);

      // Verify results are displayed in UI
      expect(find.byKey(const ValueKey('result_0')), findsOneWidget);

      // Disconnect
      await appProvider.disconnectConnection(connectionId: testServer.id);
      await tester.pump();
    });

    testWidgets('query with join and aggregation', (tester) async {
      final appProvider = await setupApp(tester);

      final testServer = DbServer(
        id: 'test_sqlite_join_${DateTime.now().millisecondsSinceEpoch}',
        name: 'SQLite Join Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await appProvider.connection.saveConnection(testServer);
      final connected = await appProvider.connectToServer(testServer);
      expect(connected, isTrue);
      await tester.pump(const Duration(seconds: 1));

      // Create departments table
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'CREATE TABLE departments (id INTEGER PRIMARY KEY, name TEXT)',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Create employees table
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, dept_id INTEGER, salary REAL)',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Insert departments
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        "INSERT INTO departments (name) VALUES ('Engineering'), ('Sales'), ('Marketing')",
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Insert employees
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        '''INSERT INTO employees (name, dept_id, salary) VALUES 
           ('Alice', 1, 80000),
           ('Bob', 1, 90000),
           ('Charlie', 2, 70000),
           ('Diana', 3, 75000)''',
      );
      await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      // Test JOIN query
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        '''SELECT e.name, d.name as department, e.salary 
           FROM employees e 
           JOIN departments d ON e.dept_id = d.id 
           ORDER BY e.salary DESC''',
      );
      final joinResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(joinResults.first.success, isTrue);
      expect(joinResults.first.data!.length, 4);
      expect(joinResults.first.data!.first['name'], 'Bob'); // Highest salary

      // Test aggregation query
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        '''SELECT d.name as department, COUNT(*) as count, AVG(e.salary) as avg_salary
           FROM employees e
           JOIN departments d ON e.dept_id = d.id
           GROUP BY d.name
           ORDER BY avg_salary DESC''',
      );
      final aggResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(aggResults.first.success, isTrue);
      expect(aggResults.first.data!.length, 3);

      // Engineering should have highest average
      final engRow = aggResults.first.data!.firstWhere(
        (r) => r['department'] == 'Engineering',
      );
      expect(engRow['count'], 2);

      await appProvider.disconnectConnection(connectionId: testServer.id);
      await tester.pump();
    });

    testWidgets('query error handling', (tester) async {
      final appProvider = await setupApp(tester);

      final testServer = DbServer(
        id: 'test_sqlite_error_${DateTime.now().millisecondsSinceEpoch}',
        name: 'SQLite Error Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await appProvider.connection.saveConnection(testServer);
      final connected = await appProvider.connectToServer(testServer);
      expect(connected, isTrue);
      await tester.pump(const Duration(seconds: 1));

      // Execute invalid SQL
      appProvider.updateTabSql(
        appProvider.activeTabIndex,
        'SELECT * FROM nonexistent_table',
      );
      final errorResults = await appProvider.tab.executeCurrentQuery();
      await tester.pump();

      expect(errorResults, isNotEmpty);
      expect(errorResults.first.success, isFalse);
      expect(errorResults.first.errorMessage, isNotNull);
      expect(errorResults.first.errorMessage!.toLowerCase(), contains('no such table'));

      await appProvider.disconnectConnection(connectionId: testServer.id);
      await tester.pump();
    });
  });
}
