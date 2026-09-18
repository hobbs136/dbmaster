// ============================================================================
// Results Display Integration Test
// Tests: ResultsWidget, ResultTabContent, VirtualizedDataTable
//        Empty state, Error view, Affected rows view, Data table view
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Results Display Tests', () {
    Widget buildTestApp(Widget child) {
      return MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: Scaffold(body: child),
      );
    }

    // ========================================================================
    // VIRTUALIZED DATA TABLE TESTS
    // ========================================================================
    group('VirtualizedDataTable', () {
      testWidgets('should render data table with columns and rows', (
        tester,
      ) async {
        final columns = ['id', 'name', 'email', 'age'];
        final data = [
          {'id': 1, 'name': 'John', 'email': 'john@example.com', 'age': 30},
          {'id': 2, 'name': 'Jane', 'email': 'jane@example.com', 'age': 25},
          {'id': 3, 'name': 'Bob', 'email': 'bob@example.com', 'age': 35},
        ];

        await tester.pumpWidget(
          buildTestApp(VirtualizedDataTable(columns: columns, data: data)),
        );
        await tester.pumpAndSettle();

        // Verify column headers are displayed
        expect(find.text('id'), findsOneWidget);
        expect(find.text('name'), findsOneWidget);
        expect(find.text('email'), findsOneWidget);
        expect(find.text('age'), findsOneWidget);

        // Verify data rows are displayed
        expect(find.text('John'), findsOneWidget);
        expect(find.text('Jane'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
      });

      testWidgets('should render empty data table', (tester) async {
        await tester.pumpWidget(
          buildTestApp(const VirtualizedDataTable(columns: [], data: [])),
        );
        await tester.pumpAndSettle();

        // Should show "无数据" (no data) text
        expect(find.text('无数据'), findsOneWidget);
      });

      testWidgets('should render table with row numbers', (tester) async {
        final columns = ['name'];
        final data = [
          {'name': 'Alice'},
          {'name': 'Bob'},
        ];

        await tester.pumpWidget(
          buildTestApp(
            VirtualizedDataTable(
              columns: columns,
              data: data,
              showRowNumbers: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify data is displayed
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
      });
    });

    // ========================================================================
    // RESULTS WIDGET TESTS
    // ========================================================================
    group('ResultsWidget', () {
      testWidgets('should show empty state when no results', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(const ResultsWidget()),
          ),
        );
        await tester.pumpAndSettle();

        // Should show empty state with table icon
        expect(find.byIcon(LucideIcons.table2), findsOneWidget);
      });

      testWidgets('should display success result with data', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        // Add a tab first
        appProvider.tab.addNewTab();

        // Create a mock execution result with data
        final result = ExecutionResult(
          statement: const SQLStatement(
            index: 0,
            sql: 'SELECT * FROM users',
            type: SQLType.select,
            lineStart: 0,
            lineEnd: 0,
          ),
          success: true,
          data: [
            {'id': 1, 'name': 'John', 'age': 30},
            {'id': 2, 'name': 'Jane', 'age': 25},
          ],
          executionTime: const Duration(milliseconds: 100),
        );

        // Add result to the active tab
        appProvider.tab.updateTabExecutionResults(appProvider.activeTabIndex, [
          result,
        ]);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(const ResultsWidget()),
          ),
        );
        await tester.pumpAndSettle();

        // Verify result tab is shown
        expect(find.text('SELECT * FROM users'), findsOneWidget);

        // Verify data count badge (should find at least the badge with '2')
        expect(find.text('2'), findsAtLeastNWidgets(1));

        // Verify success icon
        expect(
          find.byIcon(LucideIcons.circleCheckBig),
          findsAtLeastNWidgets(1),
        );
      });

      testWidgets('should display error result', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        // Add a tab first
        appProvider.tab.addNewTab();

        final result = ExecutionResult(
          statement: const SQLStatement(
            index: 0,
            sql: 'SELECT * FROM nonexistent',
            type: SQLType.select,
            lineStart: 0,
            lineEnd: 0,
          ),
          success: false,
          executionTime: const Duration(milliseconds: 50),
          errorMessage: 'Table nonexistent does not exist',
        );

        appProvider.tab.updateTabExecutionResults(appProvider.activeTabIndex, [
          result,
        ]);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(const ResultsWidget()),
          ),
        );
        await tester.pumpAndSettle();

        // Verify error icon
        expect(find.byIcon(LucideIcons.circleAlert), findsAtLeastNWidgets(1));

        // Verify error message is displayed
        expect(find.textContaining('does not exist'), findsOneWidget);
      });

      testWidgets('should display affected rows result', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        // Add a tab first
        appProvider.tab.addNewTab();

        final result = ExecutionResult(
          statement: const SQLStatement(
            index: 0,
            sql: 'UPDATE users SET age = 30',
            type: SQLType.update,
            lineStart: 0,
            lineEnd: 0,
          ),
          success: true,
          affectedRows: 5,
          executionTime: const Duration(milliseconds: 200),
        );

        appProvider.tab.updateTabExecutionResults(appProvider.activeTabIndex, [
          result,
        ]);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(const ResultsWidget()),
          ),
        );
        await tester.pumpAndSettle();

        // Verify success icon
        expect(
          find.byIcon(LucideIcons.circleCheckBig),
          findsAtLeastNWidgets(1),
        );

        // Verify affected rows text (Chinese)
        expect(find.textContaining('影响'), findsOneWidget);
      });

      testWidgets('should show multiple result tabs', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        // Add a tab first
        appProvider.tab.addNewTab();

        final result1 = ExecutionResult(
          statement: const SQLStatement(
            index: 0,
            sql: 'SELECT * FROM users',
            type: SQLType.select,
            lineStart: 0,
            lineEnd: 0,
          ),
          success: true,
          data: [
            {'id': 1, 'name': 'John'},
          ],
          executionTime: const Duration(milliseconds: 100),
        );

        final result2 = ExecutionResult(
          statement: const SQLStatement(
            index: 1,
            sql: 'SELECT * FROM orders',
            type: SQLType.select,
            lineStart: 0,
            lineEnd: 0,
          ),
          success: true,
          data: [
            {'id': 1, 'total': 100},
            {'id': 2, 'total': 200},
          ],
          executionTime: const Duration(milliseconds: 150),
        );

        appProvider.tab.updateTabExecutionResults(appProvider.activeTabIndex, [
          result1,
          result2,
        ]);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(const ResultsWidget()),
          ),
        );
        await tester.pumpAndSettle();

        // Verify both tabs are shown
        expect(find.text('SELECT * FROM users'), findsOneWidget);
        expect(find.text('SELECT * FROM orders'), findsOneWidget);

        // Verify data counts (at least one occurrence for each)
        expect(find.text('1'), findsAtLeastNWidgets(1));
        expect(find.text('2'), findsAtLeastNWidgets(1));
      });

      testWidgets('should show export button when data exists', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        // Add a tab first
        appProvider.tab.addNewTab();

        final result = ExecutionResult(
          statement: const SQLStatement(
            index: 0,
            sql: 'SELECT * FROM users',
            type: SQLType.select,
            lineStart: 0,
            lineEnd: 0,
          ),
          success: true,
          data: [
            {'id': 1, 'name': 'John'},
          ],
          executionTime: const Duration(milliseconds: 100),
        );

        appProvider.tab.updateTabExecutionResults(appProvider.activeTabIndex, [
          result,
        ]);

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(const ResultsWidget()),
          ),
        );
        await tester.pumpAndSettle();

        // Verify export button is shown
        expect(find.byIcon(LucideIcons.download), findsOneWidget);
      });
    });
  });
}
