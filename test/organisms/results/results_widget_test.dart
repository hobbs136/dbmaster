import 'dart:math';

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/query_history/result_history_view.dart';
import 'package:dbmaster/organisms/results/result_subtab_bar.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';

import '../results/query_history/history_test_helper.dart';

void main() {
  setupHistoryTestBinding();

  group('ResultsWidget', () {
    late AppProvider appProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      tabId = 'tab-${Random().nextInt(1000000)}';
    });

    Widget buildResultsWidget() {
      return buildHistoryTestApp(appProvider, child: const ResultsWidget());
    }

    // 回归：失败结果视图的标题与未知错误回退须走 AppLocalizations（en），
    // 不再出现硬编码中文。旧实现写死 '执行失败'/'未知错误'，下列断言在旧代码上失败。
    testWidgets(
      'error view shows localized failed title and unknown-error fallback',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
        appProvider.tab.ensureHistorySubTab(tabId);
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql: 'SELECT bad',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: false,
              executionTime: const Duration(milliseconds: 1),
            ),
          ],
          sql: 'SELECT bad',
          executionTime: const Duration(milliseconds: 1),
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        expect(find.text('Execution failed'), findsOneWidget);
        expect(find.text('Unknown error'), findsOneWidget);
        expect(find.text('执行失败'), findsNothing);
        expect(find.text('未知错误'), findsNothing);
      },
    );

    testWidgets(
      'renders ResultHistoryView and keeps ResultSubTabBar visible when history subtab is active',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
        appProvider.tab.ensureHistorySubTab(tabId);

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ResultHistoryView), findsOneWidget);
        expect(find.byType(ResultSubTabBar), findsOneWidget);
      },
    );

    // U07/D1-A + 2026-08-24 用户拍板：网格写回下线，双击数据单元格不进
    // 编辑态；双击打开只读单元格查看器（长文本查看/复制的正式入口），
    // 原「暂不支持编辑」snackbar 退役。
    testWidgets(
      'double-tapping a data cell opens the read-only cell viewer, never the editor',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
        appProvider.tab.ensureHistorySubTab(tabId);
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql: 'SELECT * FROM users',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{'id': 1, 'name': 'Alice'},
              ],
              executionTime: const Duration(milliseconds: 10),
            ),
          ],
          sql: 'SELECT * FROM users',
          executionTime: const Duration(milliseconds: 10),
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        final cell = find.text('Alice');
        expect(cell, findsOneWidget);
        await tester.tap(cell);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(cell);
        await tester.pump();

        expect(find.byType(TextField), findsNothing);
        expect(
          find.text(
            'Cell editing is not available yet — edits cannot be saved back to the database',
          ),
          findsNothing,
        );

        // 只读查看器打开：标题 = 列名，内容 = 完整单元格值。
        expect(find.byType(Dialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('name'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Alice'),
          ),
          findsOneWidget,
        );

        await tester.pumpAndSettle();
      },
    );

    // 回归：Browse Data 跳变——data 模式（showSubTabs=false）下 History 子标签
    // 仅在新 tab 首执返回前激活，旧实现会闪出全屏 ResultHistoryView
    // （先跳 history 再跳结果），应显示执行中 loading。
    testWidgets(
      'data 模式（showSubTabs=false）history 激活态显示 loading 而非历史页',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
        appProvider.tab.ensureHistorySubTab(tabId);

        await tester.pumpWidget(
          buildHistoryTestApp(
            appProvider,
            child: const ResultsWidget(showSubTabs: false),
          ),
        );
        await tester.pump();

        expect(find.byType(ResultHistoryView), findsNothing);
        expect(find.byType(ResultSubTabBar), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets('switches from history view to result view after execution', (
      tester,
    ) async {
      appProvider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
      appProvider.tab.ensureHistorySubTab(tabId);
      appProvider.tab.addResultToTab(
        tabId,
        [
          ExecutionResult(
            statement: const SQLStatement(
              index: 0,
              sql: 'SELECT * FROM users',
              type: SQLType.select,
              lineStart: 1,
              lineEnd: 1,
            ),
            success: true,
            data: <Map<String, dynamic>>[
              <String, dynamic>{'id': 1},
            ],
            executionTime: const Duration(milliseconds: 10),
          ),
        ],
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 10),
      );

      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      expect(find.byType(ResultHistoryView), findsNothing);
      expect(find.byType(ResultSubTabBar), findsOneWidget);
      // C22 M2 走查反馈：单语句批次不渲染语句 tab 层（SQL 在编辑器里），
      // 数据直接呈现（旧契约断言语句 tab 的 SQL 文本）。
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('id'), findsWidgets, reason: '单语句数据表头直接渲染');
    });

    testWidgets(
      'history to result view switch completes within 500 milliseconds',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
        appProvider.tab.ensureHistorySubTab(tabId);
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql: 'SELECT 1',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{'x': 1},
              ],
              executionTime: const Duration(milliseconds: 1),
            ),
          ],
          sql: 'SELECT 1',
          executionTime: const Duration(milliseconds: 1),
        );
        // Switch back to history first.
        appProvider.tab.setActiveResult(tabId, 0);

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        expect(find.byType(ResultHistoryView), findsOneWidget);

        final stopwatch = Stopwatch()..start();
        appProvider.tab.setActiveResult(tabId, 1);
        await tester.pumpAndSettle();
        stopwatch.stop();

        expect(find.byType(ResultHistoryView), findsNothing);
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
      },
    );

    // 右键数据单元格弹出紧凑菜单：验证菜单项经 _compactMenuItem 改造后仍存在。
    // U07/D1-A：Set NULL 依赖编辑写回，随编辑态停用移除（完整版恢复）。
    testWidgets(
      '右键数据单元格弹出菜单，含 Copy Cell / Copy Row (JSON)，不含 Set NULL',
      (tester) async {
        appProvider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
        appProvider.tab.ensureHistorySubTab(tabId);
        appProvider.tab.addResultToTab(
          tabId,
          [
            ExecutionResult(
              statement: const SQLStatement(
                index: 0,
                sql: 'SELECT * FROM users',
                type: SQLType.select,
                lineStart: 1,
                lineEnd: 1,
              ),
              success: true,
              data: <Map<String, dynamic>>[
                <String, dynamic>{'id': 1, 'name': 'Alice'},
              ],
              executionTime: const Duration(milliseconds: 1),
            ),
          ],
          sql: 'SELECT * FROM users',
          executionTime: const Duration(milliseconds: 1),
        );

        await tester.pumpWidget(buildResultsWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('Alice'), buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        expect(find.text('Copy Cell'), findsOneWidget);
        expect(find.text('Copy Row (JSON)'), findsOneWidget);
        expect(find.text('Set NULL'), findsNothing);
      },
    );
  });
}
