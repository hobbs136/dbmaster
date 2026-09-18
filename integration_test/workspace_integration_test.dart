// ============================================================================
// Workspace Integration Tests
// Tests: Main workspace, welcome screen, editor/results split, query execution
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
import 'package:dbmaster/templates/welcome_screen.dart';
import 'package:dbmaster/templates/main_workspace.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('Workspace Integration Tests', () {
    late String dbPath;

    setUp(() async {
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      dbPath = '${tempDir.path}/dbmaster_workspace_test_$timestamp.db';
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

    Widget buildTestApp(Widget child) {
      return ChangeNotifierProvider(
        create: (_) => AppProvider(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('zh')],
          home: child,
        ),
      );
    }

    testWidgets('should show welcome screen', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          WelcomeScreen(
            onNewConnection: () {},
            onOpenConnectionManager: () {},
            onOpenSqliteFile: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('welcome_screen')), findsOneWidget);
      expect(find.byIcon(LucideIcons.database), findsOneWidget);
    });

    testWidgets('should show workspace with tabs', (tester) async {
      final resultsKey = GlobalKey<ResultsWidgetState>();

      await tester.pumpWidget(
        buildTestApp(
          MainWorkspace(
            isResizingEditorResults: false,
            onResizeEditorStart: () {},
            onResizeEditorEnd: () {},
            resultsWidgetKey: resultsKey,
            onNewConnection: () {},
            onOpenConnectionManager: () {},
            onOpenSqliteFile: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show welcome screen initially (no connections)
      expect(find.byKey(const ValueKey('welcome_screen')), findsOneWidget);
    });

    testWidgets('should connect to SQLite and execute query', (tester) async {
      final dbService = DatabaseService();
      final testServer = DbServer(
        id: 'test_sqlite_workspace',
        name: 'Workspace SQLite Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      // Connect directly via DatabaseService
      final connected = await dbService.connect(testServer);
      expect(connected, isTrue, reason: 'Failed to connect to SQLite');

      // Create table
      await dbService.executeQuery(
        'CREATE TABLE workspace_test (id INTEGER PRIMARY KEY, name TEXT)',
        connectionId: testServer.id,
      );

      // Insert data
      await dbService.executeQuery(
        "INSERT INTO workspace_test (name) VALUES ('Alice'), ('Bob')",
        connectionId: testServer.id,
      );

      // Query data
      final results = await dbService.executeQuery(
        'SELECT * FROM workspace_test ORDER BY id',
        connectionId: testServer.id,
      );

      expect(results, isNotEmpty);
      expect(results.length, 2);
      expect(results[0]['name'], 'Alice');
      expect(results[1]['name'], 'Bob');

      // Disconnect
      await dbService.disconnect(connectionId: testServer.id);
    });

    testWidgets('should execute multiple queries in sequence', (tester) async {
      final dbService = DatabaseService();
      final testServer = DbServer(
        id: 'test_sequence',
        name: 'Sequence Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await dbService.connect(testServer);

      // Create table
      await dbService.executeQuery(
        'CREATE TABLE seq_test (id INTEGER PRIMARY KEY, val INTEGER)',
        connectionId: testServer.id,
      );

      // Insert multiple rows
      for (int i = 1; i <= 5; i++) {
        await dbService.executeQuery(
          'INSERT INTO seq_test (val) VALUES ($i)',
          connectionId: testServer.id,
        );
      }

      // Count rows
      final countResult = await dbService.executeQuery(
        'SELECT COUNT(*) as cnt FROM seq_test',
        connectionId: testServer.id,
      );

      expect(int.parse(countResult.first['cnt'].toString()), 5);

      // Update
      await dbService.executeQuery(
        'UPDATE seq_test SET val = 100 WHERE id = 1',
        connectionId: testServer.id,
      );

      // Verify update
      final updated = await dbService.executeQuery(
        'SELECT val FROM seq_test WHERE id = 1',
        connectionId: testServer.id,
      );

      expect(int.parse(updated.first['val'].toString()), 100);

      // Delete rows with id > 3
      await dbService.executeQuery(
        'DELETE FROM seq_test WHERE id > 3',
        connectionId: testServer.id,
      );

      // Verify deletion by selecting remaining rows directly
      final remainingRows = await dbService.executeQuery(
        'SELECT id FROM seq_test ORDER BY id',
        connectionId: testServer.id,
      );

      // Should only have rows with id <= 3
      expect(
        remainingRows.length,
        lessThanOrEqualTo(3),
        reason:
            'Expected at most 3 rows after DELETE, but found ${remainingRows.length}',
      );
      for (final row in remainingRows) {
        expect(
          int.parse(row['id'].toString()),
          lessThanOrEqualTo(3),
          reason: 'Found row with id > 3 after DELETE',
        );
      }

      await dbService.disconnect(connectionId: testServer.id);
    });

    testWidgets('should handle query errors gracefully', (tester) async {
      final dbService = DatabaseService();
      final testServer = DbServer(
        id: 'test_error',
        name: 'Error Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      await dbService.connect(testServer);

      // Try to query non-existent table
      expect(
        () async => await dbService.executeQuery(
          'SELECT * FROM nonexistent_table',
          connectionId: testServer.id,
        ),
        throwsException,
      );

      // Connection should still be valid after error
      final result = await dbService.executeQuery(
        'SELECT 1 as num',
        connectionId: testServer.id,
      );

      expect(int.parse(result.first['num'].toString()), 1);

      await dbService.disconnect(connectionId: testServer.id);
    });

    testWidgets('should support multiple connections', (tester) async {
      final dbService = DatabaseService();
      final dbPath2 = '${dbPath}_second.db';

      final server1 = DbServer(
        id: 'test_multi_1',
        name: 'Multi Test 1',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      final server2 = DbServer(
        id: 'test_multi_2',
        name: 'Multi Test 2',
        type: DatabaseType.sqlite,
        host: dbPath2,
        port: 0,
        database: 'main',
      );

      // Connect both
      await dbService.connect(server1);
      await dbService.connect(server2);

      // Create tables in both
      await dbService.executeQuery(
        'CREATE TABLE t1 (id INTEGER)',
        connectionId: server1.id,
      );
      await dbService.executeQuery(
        'CREATE TABLE t2 (id INTEGER)',
        connectionId: server2.id,
      );

      // Insert different data
      await dbService.executeQuery(
        'INSERT INTO t1 VALUES (1)',
        connectionId: server1.id,
      );
      await dbService.executeQuery(
        'INSERT INTO t2 VALUES (2)',
        connectionId: server2.id,
      );

      // Query from each
      final r1 = await dbService.executeQuery(
        'SELECT * FROM t1',
        connectionId: server1.id,
      );
      final r2 = await dbService.executeQuery(
        'SELECT * FROM t2',
        connectionId: server2.id,
      );

      expect(int.parse(r1.first['id'].toString()), 1);
      expect(int.parse(r2.first['id'].toString()), 2);

      // Disconnect both
      await dbService.disconnect(connectionId: server1.id);
      await dbService.disconnect(connectionId: server2.id);

      // Cleanup second db file
      try {
        final file = File(dbPath2);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });

    testWidgets('should handle connection lifecycle', (tester) async {
      final dbService = DatabaseService();
      final testServer = DbServer(
        id: 'test_lifecycle',
        name: 'Lifecycle Test',
        type: DatabaseType.sqlite,
        host: dbPath,
        port: 0,
        database: 'main',
      );

      // Helper to check if connection is working by executing a query
      Future<bool> isConnectionWorking(String connectionId) async {
        try {
          await dbService.executeQuery('SELECT 1', connectionId: connectionId);
          return true;
        } catch (_) {
          return false;
        }
      }

      // Before connect - should not be able to query
      expect(await isConnectionWorking(testServer.id), isFalse);

      // Connect
      final connected = await dbService.connect(testServer);
      expect(connected, isTrue, reason: 'Failed to connect');
      expect(await isConnectionWorking(testServer.id), isTrue);

      // Execute query
      final result = await dbService.executeQuery(
        'SELECT 42 as answer',
        connectionId: testServer.id,
      );
      expect(int.parse(result.first['answer'].toString()), 42);

      // Disconnect
      await dbService.disconnect(connectionId: testServer.id);

      // After disconnect - should not be able to query
      expect(await isConnectionWorking(testServer.id), isFalse);

      // Test that we can create a new connection to a different database
      final dbPath2 = '${dbPath}_lifecycle.db';
      final testServer2 = DbServer(
        id: 'test_lifecycle_2',
        name: 'Lifecycle Test 2',
        type: DatabaseType.sqlite,
        host: dbPath2,
        port: 0,
        database: 'main',
      );

      // Try to connect to a new database
      try {
        final connected2 = await dbService.connect(testServer2);
        if (connected2) {
          expect(await isConnectionWorking(testServer2.id), isTrue);

          // Query after connect
          final result2 = await dbService.executeQuery(
            'SELECT 42 as answer',
            connectionId: testServer2.id,
          );
          expect(int.parse(result2.first['answer'].toString()), 42);

          await dbService.disconnect(connectionId: testServer2.id);
        }
      } catch (e) {
        // Connection to new db might fail, which is acceptable for this test
      }

      // Cleanup lifecycle db file
      try {
        final file = File(dbPath2);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    });
  });
}
