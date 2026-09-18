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

/// 记录 AI 分析传入的 [ExecutionResult]，避免触发真实 AI 网络 / 面板打开。
/// [ResultsWidget._analyzeWithAi] 经 `Provider.of<AppProvider>` 调到本覆盖。
class _RecordingAppProvider extends AppProvider {
  ExecutionResult? lastAnalyzedResult;

  @override
  Future<void> analyzeExecutionResultWithAi(
    ExecutionResult result, {
    String locale = 'en',
  }) async {
    lastAnalyzedResult = result;
  }
}

/// 构造一条成功的 SELECT 结果，[mark] 用于在数据里区分不同语句。
ExecutionResult _selectResult({
  required int index,
  required String sql,
  required int mark,
}) {
  return ExecutionResult(
    statement: SQLStatement(
      index: index,
      sql: sql,
      type: SQLType.select,
      lineStart: 1,
      lineEnd: 1,
    ),
    success: true,
    data: <Map<String, dynamic>>[
      <String, dynamic>{'mark': mark},
    ],
    executionTime: const Duration(milliseconds: 1),
  );
}

void main() {
  setupHistoryTestBinding();

  group('AI 分析当前结果（多语句批次 → 扇出子标签）', () {
    late _RecordingAppProvider provider;
    late String tabId;
    final r0 = _selectResult(index: 0, sql: 'SELECT 100 AS mark', mark: 100);
    final r1 = _selectResult(index: 1, sql: 'SELECT 200 AS mark', mark: 200);

    setUp(() {
      provider = _RecordingAppProvider();
      tabId = 'tab-${Random().nextInt(1000000)}';
      provider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
      provider.tab.addResultToTab(
        tabId,
        [r0, r1],
        sql: 'SELECT 100 AS mark; SELECT 200 AS mark',
        executionTime: const Duration(milliseconds: 2),
      );
    });

    Widget buildApp() =>
        buildHistoryTestApp(provider, child: const ResultsWidget());

    testWidgets('默认分析第 1 条；切到 Result 2 子标签后分析第 2 条', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // 扇出契约：两语句 → 两个 Result 子标签，各恰一条结果。
      final subs = provider.tab.getResultsForTab(tabId);
      expect(subs.length, 2);
      expect(subs[0].executionResults, [r0]);
      expect(subs[1].executionResults, [r1]);
      expect(subs[0].label, 'Result 1');
      expect(subs[1].label, 'Result 2');

      // 健全性检查：默认活跃子标签 0 → AI 分析 r0
      await tester.tap(
        find.widgetWithIcon(TextButton, LucideIcons.wandSparkles),
      );
      await tester.pumpAndSettle();
      expect(provider.lastAnalyzedResult, r0);

      // 切到第 2 个 Result 子标签（C22 M2 走查反馈二轮：语句层并入子标签层）
      await tester.tap(find.text('Result 2'));
      await tester.pumpAndSettle();

      // Provider 活跃子标签索引已同步为 1
      expect(provider.tab.activeResultIndex, 1);

      // 回归核心断言：现在 AI 分析的应是 r1
      provider.lastAnalyzedResult = null;
      await tester.tap(
        find.widgetWithIcon(TextButton, LucideIcons.wandSparkles),
      );
      await tester.pumpAndSettle();
      expect(provider.lastAnalyzedResult, r1);
    });
  });

  group('扇出与整批替换（addResultToTab 语义）', () {
    late _RecordingAppProvider provider;
    late String tabId;

    setUp(() {
      provider = _RecordingAppProvider();
      tabId = 'tab-${Random().nextInt(1000000)}';
      provider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
    });

    test('再执行整批替换未 Pin 子标签；Pin 的保留', () {
      provider.tab.addResultToTab(
        tabId,
        [
          _selectResult(index: 0, sql: 'SELECT 1', mark: 1),
          _selectResult(index: 1, sql: 'SELECT 2', mark: 2),
        ],
        sql: 'SELECT 1; SELECT 2',
        executionTime: const Duration(milliseconds: 1),
      );
      var subs = provider.tab.getResultsForTab(tabId);
      expect(subs.length, 2, reason: '两语句扇出两个子标签');

      // Pin 第二个（语句级 pin），再执行单语句批次
      provider.tab.pinResult(tabId, 1);
      provider.tab.addResultToTab(
        tabId,
        [_selectResult(index: 0, sql: 'SELECT 3', mark: 3)],
        sql: 'SELECT 3',
        executionTime: const Duration(milliseconds: 1),
      );

      subs = provider.tab.getResultsForTab(tabId);
      expect(subs.length, 2, reason: 'Pin 的语句子标签保留 + 新批次 1 个');
      expect(subs[0].executionResults.single.statement.sql, 'SELECT 3');
      expect(subs[1].isPinned, isTrue);
      expect(subs[1].executionResults.single.statement.sql, 'SELECT 2');
    });

    test('executedSql 为语句级 SQL（非整脚本）', () {
      provider.tab.addResultToTab(
        tabId,
        [
          _selectResult(index: 0, sql: 'SELECT 1', mark: 1),
          _selectResult(index: 1, sql: 'SELECT 2', mark: 2),
        ],
        sql: 'SELECT 1; SELECT 2',
        executionTime: const Duration(milliseconds: 1),
      );
      final subs = provider.tab.getResultsForTab(tabId);
      expect(subs[0].executedSql, 'SELECT 1');
      expect(subs[1].executedSql, 'SELECT 2');
    });

    test('closeResult 后活跃索引 clamp', () {
      provider.tab.addResultToTab(
        tabId,
        [
          _selectResult(index: 0, sql: 'SELECT 1', mark: 1),
          _selectResult(index: 1, sql: 'SELECT 2', mark: 2),
        ],
        sql: 'SELECT 1; SELECT 2',
        executionTime: const Duration(milliseconds: 1),
      );
      final subId = provider.tab.getResultsForTab(tabId)[0].id;
      provider.tab.setActiveResult(tabId, 1);
      expect(provider.tab.activeResultIndex, 1);

      provider.tab.closeResult(tabId, 1);
      // 关掉末位后活跃索引回退到合法范围
      expect(provider.tab.activeResultIndex, 0);
      expect(provider.tab.getResultsForTab(tabId).length, 1);
      expect(subId, isNotEmpty);
    });
  });
}
