import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/molecules/actionable_error.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'query_history/history_test_helper.dart';

/// 记录 AI 分析调用，避免触发真实 AI 网络 / 面板打开。
///
/// 两条错误→AI 路径分别走不同入口：
/// - 整体异常（`ResultSubTab.errorMessage`）→ [analyzeErrorWithAi]
/// - 单条语句失败（`ExecutionResult` !success）→ [analyzeExecutionResultWithAi]
class _RecordingAppProvider extends AppProvider {
  // analyzeErrorWithAi（整体异常路径）入参快照
  String? lastErrorText;
  String? lastErrorSql;
  String? lastErrorConnectionId;
  String? lastErrorDatabaseName;

  // analyzeExecutionResultWithAi（单条语句失败路径）入参快照
  ExecutionResult? lastAnalyzedResult;

  @override
  Future<void> analyzeErrorWithAi({
    required String errorText,
    String? title,
    String? sql,
    String? connectionId,
    String? databaseName,
    String locale = 'en',
  }) async {
    lastErrorText = errorText;
    lastErrorSql = sql;
    lastErrorConnectionId = connectionId;
    lastErrorDatabaseName = databaseName;
  }

  @override
  Future<void> analyzeExecutionResultWithAi(
    ExecutionResult result, {
    String locale = 'en',
  }) async {
    lastAnalyzedResult = result;
  }
}

void main() {
  setupHistoryTestBinding();

  // 改动 1：整体异常（catch 块 → ResultSubTab.errorMessage）就地送 AI。
  // 旧实现 _buildErrorDisplay 只是居中 Icon+Text，无任何操作入口。
  group('整体异常错误视图 AI 分析（ResultSubTab.errorMessage）', () {
    testWidgets(
      '错误子标签渲染 ActionableError，点击触发 analyzeErrorWithAi 并带上 sql/连接上下文',
      (tester) async {
        final provider = _RecordingAppProvider();
        final tabId = 'tab-${Random().nextInt(1000000)}';
        provider.tab.addTab(
          QueryTab(
            id: tabId,
            title: 'Tab 1',
            connectionId: 'conn-1',
            databaseName: 'db-1',
          ),
        );
        provider.tab.addErrorMessageToTab(
          tabId,
          'syntax error near SELECT',
          sql: 'SELECT FROM',
        );

        await tester.pumpWidget(
          buildHistoryTestApp(provider, child: const ResultsWidget()),
        );
        await tester.pumpAndSettle();

        // 统一错误展示组件接管了旧的居中 Icon+Text
        expect(find.byType(ActionableError), findsOneWidget);

        // ActionableError 的 AI 按钮用 auto_awesome 图标
        final aiButton = find.widgetWithIcon(TextButton, LucideIcons.sparkles);
        expect(aiButton, findsOneWidget);

        await tester.tap(aiButton);
        await tester.pumpAndSettle();

        // 错误文本与执行 SQL 一并送出
        expect(provider.lastErrorText, 'syntax error near SELECT');
        expect(provider.lastErrorSql, 'SELECT FROM');
        // 连接上下文从当前 tab 取（tab 级隔离，子标签不跨连接）
        expect(provider.lastErrorConnectionId, 'conn-1');
        expect(provider.lastErrorDatabaseName, 'db-1');
      },
    );
  });

  // 回归：单条语句失败（ExecutionResult !success）的 AI 入口在工具栏
  // （_buildAiAnalyzeButton 的 !success 分支，文案 aiAnalyzeErrorResult），而非
  // _buildErrorView 内部——后者在 _buildResultTab 提前返回、只渲染错误详情。
  // 整体异常（ResultSubTab.errorMessage）因 executionResults 为空、工具栏按钮
  // shrink 才真正缺入口（见上一 group）。锁定此区分，防止重复添加按钮。
  group('单条语句失败 AI 分析（工具栏入口回归）', () {
    testWidgets('失败结果经工具栏 AI 按钮触发 analyzeExecutionResultWithAi', (
      tester,
    ) async {
      final provider = _RecordingAppProvider();
      final tabId = 'tab-${Random().nextInt(1000000)}';
      provider.tab.addTab(QueryTab(id: tabId, title: 'Tab 1'));
      final failResult = ExecutionResult(
        statement: const SQLStatement(
          index: 0,
          sql: 'SELECT * FROM nonexistent',
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
        success: false,
        errorMessage: 'relation "nonexistent" does not exist',
        executionTime: const Duration(milliseconds: 1),
      );
      provider.tab.addResultToTab(
        tabId,
        [failResult],
        sql: 'SELECT * FROM nonexistent',
        executionTime: const Duration(milliseconds: 1),
      );

      await tester.pumpWidget(
        buildHistoryTestApp(provider, child: const ResultsWidget()),
      );
      await tester.pumpAndSettle();

      // _buildErrorView 的 AI 按钮用 auto_fix_high_outlined（与成功工具栏一致）
      final aiButton = find.widgetWithIcon(
        TextButton,
        LucideIcons.wandSparkles,
      );
      expect(aiButton, findsOneWidget);

      await tester.tap(aiButton);
      await tester.pumpAndSettle();

      expect(provider.lastAnalyzedResult, failResult);
    });
  });
}
