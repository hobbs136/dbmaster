import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/card_view.dart';
import 'package:dbmaster/organisms/results/chart_view.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/plugins/result_renderer_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';

import 'query_history/history_test_helper.dart';

/// 视图模式切换测试（M1 R1；C11 起模式集合按注册表生成）。
///
/// 验证：默认表格视图 → 切换条存在 → 切到 card/chart 渲染对应视图。
/// per-tab 持久化（切内层 tab 各自保留）靠 ResultTabContent 稳定 key +
/// State 复用，属于 Flutter 框架行为，单测难覆盖，放 M6 集成验证。
void main() {
  setupHistoryTestBinding();

  group('ResultsWidget 视图模式切换 (M1 · C11 注册化)', () {
    late AppProvider appProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      tabId = 'tab-${Random().nextInt(1000000)}';
    });

    Widget buildResultsWidget() {
      return buildHistoryTestApp(appProvider, child: const ResultsWidget());
    }

    /// 造一个有数据的结果 tab（一条 SELECT 成功结果）。
    void seedResult() {
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
            ],
            executionTime: const Duration(milliseconds: 10),
          ),
        ],
        sql: 'SELECT * FROM users',
        executionTime: const Duration(milliseconds: 10),
      );
    }

    testWidgets('默认渲染表格视图，视图切换条可见', (tester) async {
      seedResult();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      // 默认 table 模式 → VirtualizedDataTable 存在
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
      // 视图切换条三个 label 可见（en: Table/Chart/Card——经渲染器
      // descriptor.displayName 提供的同一组 l10n 键）
      expect(find.text('Table'), findsOneWidget);
      expect(find.text('Chart'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
    });

    testWidgets('切到 Card 视图渲染 CardView，表格消失', (tester) async {
      seedResult();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      // 初始表格视图
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
      expect(find.byType(CardView), findsNothing);

      // 点 Card 切换
      await tester.tap(find.text('Card'));
      await tester.pumpAndSettle();

      // 切换后：CardView 出现，表格消失
      expect(find.byType(CardView), findsOneWidget);
      expect(find.byType(VirtualizedDataTable), findsNothing);
    });

    testWidgets('切到 Chart 视图渲染 ChartView（M2 已接入）', (tester) async {
      seedResult();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chart'));
      await tester.pumpAndSettle();

      // M2 接入后：渲染真实 ChartView，表格消失
      expect(find.byType(ChartView), findsOneWidget);
      expect(find.byType(VirtualizedDataTable), findsNothing);
    });

    testWidgets('切到 Card 再切回 Table，表格恢复', (tester) async {
      seedResult();
      await tester.pumpWidget(buildResultsWidget());
      await tester.pumpAndSettle();

      // Table → Card → Table
      await tester.tap(find.text('Card'));
      await tester.pumpAndSettle();
      expect(find.byType(CardView), findsOneWidget);

      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
      expect(find.byType(CardView), findsNothing);
    });
  });

  group('视图模式注册表（C11）', () {
    test('默认注册含 table/chart/card 三个渲染器，viewModeId 对齐原枚举名', () {
      final renderers = defaultPluginRegistry.resultRenderersFor(
        shape: ResultDataShape.sqlRows,
      );
      final modeIds = renderers.map((r) => r.viewModeId).toList();
      expect(modeIds, containsAll(<String>['table', 'chart', 'card']));
      // 注册序首个 = 默认视图（table）
      expect(modeIds.first, 'table');
    });

    test('默认值是 table（宿主 _viewModeId null 时取注册序首个）', () {
      final renderers = defaultPluginRegistry.resultRenderersFor(
        shape: ResultDataShape.sqlRows,
      );
      // 注册序即 bootstrap 声明序：Table → Chart → Card
      expect(renderers.first.viewModeId, 'table');
    });
  });

  group('ResultsWidget 形态默认视图（C12）', () {
    late AppProvider appProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      tabId = 'tab-c12-${DateTime.now().microsecondsSinceEpoch}';
    });

    /// 造带形态标记的结果 tab（模拟 Mongo/Redis 连接执行后的 ExecutionResult）。
    void seedShapedResult(ResultDataShape shape, List<Map<String, dynamic>> data) {
      appProvider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
      appProvider.tab.ensureHistorySubTab(tabId);
      appProvider.tab.addResultToTab(
        tabId,
        [
          ExecutionResult(
            statement: const SQLStatement(
              index: 0,
              sql: 'find',
              type: SQLType.select,
              lineStart: 1,
              lineEnd: 1,
            ),
            success: true,
            data: data,
            executionTime: const Duration(milliseconds: 10),
            dataShape: shape,
          ),
        ],
        sql: 'find',
        executionTime: const Duration(milliseconds: 10),
      );
    }

    testWidgets('nosqlDocument 结果默认文档视图（表格消失、可切回）', (tester) async {
      seedShapedResult(ResultDataShape.nosqlDocument, const [
        {'_id': '507f1f77bcf86cd799439011', 'name': 'Alice'},
      ]);
      await tester.pumpWidget(
        buildHistoryTestApp(appProvider, child: const ResultsWidget()),
      );
      await tester.pumpAndSettle();

      // 切换条按 nosqlDocument 形态生成：Documents/JSON Tree/Table（无 Chart/Card）
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('JSON Tree'), findsOneWidget);
      expect(find.text('Table'), findsOneWidget);
      expect(find.text('Chart'), findsNothing);
      expect(find.text('Card'), findsNothing);
      // 默认 = 注册序首个（document）→ 表格不在，文档头值在
      expect(find.byType(VirtualizedDataTable), findsNothing);
      expect(find.text('507f1f77bcf86cd799439011'), findsOneWidget);

      // 切回 Table 兜底可用
      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
    });

    testWidgets('redisKeyValue 结果默认键值视图', (tester) async {
      seedShapedResult(ResultDataShape.redisKeyValue, const [
        {'result': 'hello'},
      ]);
      await tester.pumpWidget(
        buildHistoryTestApp(appProvider, child: const ResultsWidget()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Key-Value'), findsOneWidget);
      expect(find.text('JSON Tree'), findsOneWidget);
      expect(find.byType(VirtualizedDataTable), findsNothing);
      expect(find.text('String'), findsOneWidget);
    });

    testWidgets('无形态标记（历史结果）回退 sqlRows：Table/Chart/Card', (tester) async {
      seedShapedResult(ResultDataShape.sqlRows, const [
        {'id': 1},
      ]);
      await tester.pumpWidget(
        buildHistoryTestApp(appProvider, child: const ResultsWidget()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Table'), findsOneWidget);
      expect(find.text('Chart'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('Documents'), findsNothing);
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
    });
  });
}
