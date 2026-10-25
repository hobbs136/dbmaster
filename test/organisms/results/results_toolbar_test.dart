import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/card_view.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/organisms/results/virtualized_data_table.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';

import 'query_history/history_test_helper.dart';

/// UIRV-A41：数据网格顶栏合并——默认 chrome = tab 行 + 单一 36px 工具栏。
///
/// 从任务书验收条款直译（非镜像实现）：
/// - 条款 1：视图切换分段按钮、Filter 入口、AI Analyze、Export、Search 同栏。
/// - 条款 5：视图切换 per-result 语义不变（多结果时仍切当前结果子标签的视图）。
void main() {
  setupHistoryTestBinding();

  /// Ahem 测试字体下标签宽度失真，统一放大测试视口消除无关 overflow 噪音。
  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('UIRV-A41 · 单一工具栏（验收条款 1）', () {
    late AppProvider appProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      tabId = 'tab-uirv41-${Random().nextInt(1000000)}';
    });

    void seedResult() {
      appProvider.tab.addTab(
        QueryTab(id: tabId, title: 'Tab 1', databaseType: DatabaseType.mysql),
      );
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

    Widget buildWidget() {
      return buildHistoryTestApp(
        appProvider,
        child: ResultsWidget(
          // Filter 入口由宿主（editor_results_split 数据模式）注入；
          // 此处用探针件验证槽位渲染。
          filterEntry: const Text('FILTER-ENTRY-PROBE'),
        ),
      );
    }

    testWidgets('视图分段 + Filter 入口 + AI/Export/Search 同栏，且只有一个分段控件', (
      tester,
    ) async {
      useLargeSurface(tester);
      seedResult();
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      // 五个控件同处一棵工具栏（find 全部命中即同栏可见）
      expect(find.text('Table'), findsOneWidget);
      expect(find.text('Chart'), findsOneWidget);
      expect(find.text('Card'), findsOneWidget);
      expect(find.text('FILTER-ENTRY-PROBE'), findsOneWidget);
      expect(find.text('AI Analyze'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.byIcon(LucideIcons.search), findsOneWidget);

      // 「单一工具栏」：全树只有一个视图分段控件（原 per-result 32px 条已上提合并）
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
    });

    testWidgets('Filter 入口未注入时不渲染（query 模式无 Filter 入口）', (tester) async {
      useLargeSurface(tester);
      seedResult();
      await tester.pumpWidget(
        buildHistoryTestApp(appProvider, child: const ResultsWidget()),
      );
      await tester.pumpAndSettle();

      expect(find.text('FILTER-ENTRY-PROBE'), findsNothing);
      // 工具栏其余控件仍在
      expect(find.text('AI Analyze'), findsOneWidget);
    });

    testWidgets('条款 1 后半：网格照常渲染（工具栏合并不吞内容区）', (tester) async {
      useLargeSurface(tester);
      seedResult();
      await tester.pumpWidget(buildWidget());
      await tester.pumpAndSettle();

      expect(find.byType(VirtualizedDataTable), findsOneWidget);
    });
  });

  group('UIRV-A41 · 视图切换 per-result 语义（验收条款 5）', () {
    late AppProvider appProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      tabId = 'tab-uirv41b-${Random().nextInt(1000000)}';
    });

    /// 一次执行扇出两个结果子标签（Result 1 / Result 2）。
    void seedTwoResults() {
      appProvider.tab.addTab(
        QueryTab(id: tabId, title: 'Tab 1', databaseType: DatabaseType.mysql),
      );
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
              <String, dynamic>{'id': 1, 'name': 'A'},
            ],
            executionTime: const Duration(milliseconds: 5),
          ),
          ExecutionResult(
            statement: const SQLStatement(
              index: 1,
              sql: 'SELECT 2',
              type: SQLType.select,
              lineStart: 2,
              lineEnd: 2,
            ),
            success: true,
            data: <Map<String, dynamic>>[
              <String, dynamic>{'id': 2, 'name': 'B'},
            ],
            executionTime: const Duration(milliseconds: 5),
          ),
        ],
        sql: 'SELECT 1; SELECT 2;',
        executionTime: const Duration(milliseconds: 10),
      );
    }

    testWidgets('工具栏切视图只影响当前子标签；切走再切回视图保留', (tester) async {
      useLargeSurface(tester);
      seedTwoResults();
      await tester.pumpWidget(
        buildHistoryTestApp(appProvider, child: const ResultsWidget()),
      );
      await tester.pumpAndSettle();

      // 当前子标签 = Result 1，默认 table
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
      // History 子标签 pinned 占首序，扇出子标签标签从 Result 2 起
      expect(find.text('Result 2'), findsOneWidget);
      expect(find.text('Result 3'), findsOneWidget);

      // 经工具栏分段切到 Card
      await tester.tap(find.text('Card'));
      await tester.pumpAndSettle();
      expect(find.byType(CardView), findsOneWidget);
      expect(find.byType(VirtualizedDataTable), findsNothing);

      // 切到第二个子标签（Result 3）→ 该子标签仍默认 table
      await tester.tap(find.text('Result 3'));
      await tester.pumpAndSettle();
      expect(find.byType(VirtualizedDataTable), findsOneWidget);
      expect(find.byType(CardView), findsNothing);

      // 切回 Result 2 → Card 视图保留（per-result）
      await tester.tap(find.text('Result 2'));
      await tester.pumpAndSettle();
      expect(find.byType(CardView), findsOneWidget);
      expect(find.byType(VirtualizedDataTable), findsNothing);
    });
  });
}
