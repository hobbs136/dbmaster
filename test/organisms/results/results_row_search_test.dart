// 行级搜索功能（spec 051-results-row-search）的 widget 测试。
//
// 覆盖：
// - R1 搜索按钮切换搜索框显示/隐藏
// - R2 输入关键词过滤当前 tab 的行（整行任意列 contains）
// - R2 清空搜索词恢复全量
// - R5 无匹配行时显示明确提示
// - R2 搜索框清空按钮（suffix clear icon）工作
//
// 注：R3（与列过滤共存）、R4（切 tab 保留 query）涉及更复杂的表格交互
// （列头过滤器、TabBarView 切换），核心逻辑由 applyRowSearch 单测覆盖，
// 这里聚焦外层 widget 行为。

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'query_history/history_test_helper.dart';

void main() {
  setupHistoryTestBinding();

  group('ResultsWidget row search (spec 051)', () {
    late AppProvider appProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      tabId = 'tab-${Random().nextInt(1000000)}';
    });

    Widget buildResultsWidget() {
      return buildHistoryTestApp(appProvider, child: const ResultsWidget());
    }

    /// 构造一个含 3 行数据的成功 SELECT 结果并渲染 ResultsWidget。
    void seedResults() {
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
              <String, dynamic>{'id': 2, 'name': 'Bob'},
              <String, dynamic>{'id': 3, 'name': 'Charlie'},
            ],
            executionTime: const Duration(milliseconds: 10),
          ),
        ],
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 10),
      );
    }

    testWidgets('search button is visible and initially does nothing', (
      tester,
    ) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      // 搜索按钮存在（按 tooltip 定位，复用既有 resultsSearchBtn key）
      expect(find.byTooltip('Search'), findsOneWidget);
      // 初始搜索框不可见
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('R1: clicking search button toggles search field visible', (
      tester,
    ) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      // 初始：无搜索框
      expect(find.byType(TextField), findsNothing);

      // 点击搜索按钮
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      // 搜索框出现
      expect(find.byType(TextField), findsOneWidget);

      // 再次点击 → 收起
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('R2: typing filters rows by any-column contains', (
      tester,
    ) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      // 展开搜索框
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      // 输入 'alice' → 只剩 Alice 行（name 列匹配，case-insensitive）
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Charlie'), findsNothing);
    });

    testWidgets('R2: case-insensitive matching', (tester) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'BOB');
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Charlie'), findsNothing);
    });

    testWidgets('R2: empty query shows all rows', (tester) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      // 先过滤
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsNothing);

      // 清空输入框文本（保留搜索框展开）
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // 全部行恢复
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('R2: clear (x) suffix button empties the field', (
      tester,
    ) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsNothing);

      // 点击清空按钮（clear icon 的 IconButton）。
      // Lucide 无变体后清空(18) 与结果子标签关闭(12) 同 glyph，按 size 定位
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == LucideIcons.x && w.size == 18,
        ),
      );
      await tester.pumpAndSettle();

      // 搜索框文本清空 → 全部行恢复
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('R5: no match shows explicit no-match message', (tester) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzz_nomatch');
      await tester.pumpAndSettle();

      // 无匹配行提示（en: 'No rows match "zzz_nomatch"'）
      expect(find.text('No rows match "zzz_nomatch"'), findsOneWidget);
      // 原行不显示
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('Charlie'), findsNothing);
    });

    testWidgets('R1: collapsing search button clears the query', (
      tester,
    ) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      // 展开 → 输入 → 过滤生效
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsNothing);

      // 收起搜索框（应同时清空 query）
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      // 搜索框消失，结果恢复全量
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('R1: search field has autofocus when expanded', (tester) async {
      seedResults();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      // TextField 存在且持有焦点
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.autofocus, isTrue);
    });
  });
}
