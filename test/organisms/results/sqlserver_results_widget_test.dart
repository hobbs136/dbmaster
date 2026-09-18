import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/molecules/actionable_error.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/result_subtab_bar.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';

import 'query_history/history_test_helper.dart';

/// Widget tests for SQL Server-specific result rendering.
///
/// These tests verify that the result panel correctly displays:
/// - Server error messages from failed EXEC statements (P0)
/// - Successful EXEC result sets (P0)
/// - Multiple result sets from a single EXEC (P0)
/// - Truncation indicators for varchar(max)/nvarchar(max) columns (P1)
void main() {
  setupHistoryTestBinding();

  group('SQL Server ResultsWidget', () {
    late AppProvider appProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      tabId = 'tab-${Random().nextInt(1000000)}';
    });

    Widget buildResultsWidget() {
      return buildHistoryTestApp(appProvider, child: const ResultsWidget());
    }

    testWidgets(
      'displays the full SQL Server error message for a failed EXEC (TC-SS-EXE-001)',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'SS Tab'));
        appProvider.tab.addErrorMessageToTab(
          tabId,
          "Procedure or function 'p_needparam' expects parameter '@x', which was not supplied.",
          sql: 'EXEC p_needparam;',
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        // 统一错误展示组件 ActionableError 接管了旧的居中 Icon + 'Query failed' 文本
        expect(find.byType(ActionableError), findsOneWidget);
        expect(
          find.textContaining("'p_needparam' expects parameter '@x'"),
          findsOneWidget,
        );
        // The server-provided message must be visible, not just a generic failure.
        expect(find.textContaining('Procedure or function'), findsOneWidget);
      },
    );

    testWidgets(
      'displays a successful EXEC result set with the correct value (TC-SS-EXE-003)',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'SS Tab'));
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql: 'EXEC p_echo @x = 42;',
                type: SQLType.call,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{'v': 42},
              ],
              executionTime: const Duration(milliseconds: 50),
            ),
          ],
          sql: 'EXEC p_echo @x = 42;',
          executionTime: const Duration(milliseconds: 50),
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        expect(find.byType(VirtualizedDataTable), findsOneWidget);
        expect(find.text('v'), findsOneWidget);
        expect(find.text('42'), findsOneWidget);
      },
    );

    testWidgets(
      'displays multiple result set tabs from a multi-result EXEC (TC-SS-EXE-004)',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'SS Tab'));
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql: 'SELECT 1 AS a;',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{'a': 1},
              ],
              executionTime: const Duration(milliseconds: 50),
            ),
            ExecutionResult(
              statement: const SQLStatement(
                index: 1,
                sql: 'SELECT 2 AS b;',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{'b': 2},
              ],
              executionTime: const Duration(milliseconds: 50),
            ),
          ],
          sql: 'EXEC p_multi;',
          executionTime: const Duration(milliseconds: 50),
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ResultSubTabBar), findsOneWidget);
        // C22 M2 走查反馈二轮：语句层并入子标签层——多语句扇出为
        // Result 1 / Result 2 子标签（沿用现有命名），无语句内层 tab。
        expect(find.text('Result 1'), findsOneWidget);
        expect(find.text('Result 2'), findsOneWidget);
        expect(find.byType(TabBar), findsNothing, reason: '语句内层 tab 已移除');
        // The first result grid is visible by default.
        expect(find.byType(VirtualizedDataTable), findsOneWidget);
        expect(find.text('a'), findsOneWidget);
        expect(find.text('1'), findsWidgets);
      },
    );

    testWidgets(
      'renders a plain SELECT result grid with headers and rows (TC-SS-QRY-001)',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'SS Tab'));
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql: 'SELECT id, c_varchar_reg FROM t_types;',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{'id': 1, 'c_varchar_reg': 'row one'},
                <String, dynamic>{'id': 2, 'c_varchar_reg': 'row two'},
              ],
              executionTime: const Duration(milliseconds: 50),
            ),
          ],
          sql: 'SELECT id, c_varchar_reg FROM t_types;',
          executionTime: const Duration(milliseconds: 50),
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        expect(find.byType(VirtualizedDataTable), findsOneWidget);
        expect(find.text('id'), findsOneWidget);
        expect(find.text('c_varchar_reg'), findsOneWidget);
        expect(find.text('row one'), findsOneWidget);
        expect(find.text('row two'), findsOneWidget);
      },
    );

    testWidgets('renders aliased column names from SELECT AS (TC-SS-QRY-004)', (
      tester,
    ) async {
      appProvider.tab.addTab(QueryTab(id: tabId, title: 'SS Tab'));
      appProvider.tab.addResultToTab(
        tabId,
        [
          ExecutionResult(
            statement: const SQLStatement(
              index: 0,
              sql:
                  'SELECT id AS row_id, c_varchar_reg AS text_col FROM t_types;',
              type: SQLType.select,
              lineStart: 1,
              lineEnd: 1,
            ),
            success: true,
            data: <Map<String, dynamic>>[
              <String, dynamic>{'row_id': 1, 'text_col': 'hello'},
            ],
            executionTime: const Duration(milliseconds: 50),
          ),
        ],
        sql: 'SELECT id AS row_id, c_varchar_reg AS text_col FROM t_types;',
        executionTime: const Duration(milliseconds: 50),
      );

      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      expect(find.byType(VirtualizedDataTable), findsOneWidget);
      expect(find.text('row_id'), findsOneWidget);
      expect(find.text('text_col'), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      // Original column names should not appear as headers.
      expect(find.text('id'), findsNothing);
      expect(find.text('c_varchar_reg'), findsNothing);
    });

    testWidgets(
      'shows truncation indicator for varchar(max) / nvarchar(max) columns (TC-SS-TYP-003)',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'SS Tab'));
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql:
                    'SELECT c_varchar_max, c_nvarcharmx, c_varchar_reg FROM t_types;',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{
                  'c_varchar_max': 'A' * 100,
                  'c_nvarcharmx': '文' * 50,
                  'c_varchar_reg': 'short value',
                },
              ],
              executionTime: const Duration(milliseconds: 50),
              truncatedColumns: <String>{'c_varchar_max', 'c_nvarcharmx'},
            ),
          ],
          sql:
              'SELECT c_varchar_max, c_nvarcharmx, c_varchar_reg FROM t_types;',
          executionTime: const Duration(milliseconds: 50),
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        // The data table is built with the truncatedColumns set.
        final table = tester.widget<VirtualizedDataTable>(
          find.byType(VirtualizedDataTable),
        );
        expect(table.truncatedColumns, contains('c_varchar_max'));
        expect(table.truncatedColumns, contains('c_nvarcharmx'));
        expect(table.truncatedColumns, isNot(contains('c_varchar_reg')));
        // The truncation indicator (scissors icon) appears in truncated cells.
        expect(find.text('✂'), findsWidgets);
      },
    );

    testWidgets(
      'renders modern SQL Server date/time and monetary values correctly (TC-SS-TYP-001/002)',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'SS Tab'));
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql:
                    'SELECT c_datetime2, c_date, c_time, c_dtoffset, c_money, c_smallmoney FROM t_types;',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{
                  'c_datetime2': '2026-07-15 13:45:30.1234567',
                  'c_date': '2026-07-15',
                  'c_time': '13:45:30.1234567',
                  'c_dtoffset': '2026-07-15 13:45:30.1234567 +08:00',
                  'c_money': '1234.5678',
                  'c_smallmoney': '1234.56',
                },
              ],
              executionTime: const Duration(milliseconds: 50),
            ),
          ],
          sql:
              'SELECT c_datetime2, c_date, c_time, c_dtoffset, c_money, c_smallmoney FROM t_types;',
          executionTime: const Duration(milliseconds: 50),
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        expect(find.text('2026-07-15 13:45:30.1234567'), findsOneWidget);
        expect(find.text('2026-07-15'), findsOneWidget);
        expect(find.text('13:45:30.1234567'), findsOneWidget);
        expect(find.text('2026-07-15 13:45:30.1234567 +08:00'), findsOneWidget);
        expect(find.text('1234.5678'), findsOneWidget);
        expect(find.text('1234.56'), findsOneWidget);
      },
    );
  });
}
