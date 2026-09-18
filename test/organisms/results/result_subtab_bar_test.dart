import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/organisms/results/result_subtab_bar.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ============================================================================
// ResultSubTabBar Widget Tests
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(AppProvider appProvider, {required Widget child}) {
    return ChangeNotifierProvider<AppProvider>.value(
      value: appProvider,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: child),
      ),
    );
  }

  group('MAN-RES-003: 结果子标签切换', () {
    testWidgets('无结果时应不渲染内容', (tester) async {
      final appProvider = AppProvider();

      await tester.pumpWidget(
        buildTestableWidget(appProvider, child: const ResultSubTabBar()),
      );
      await tester.pumpAndSettle();

      // ResultSubTabBar returns SizedBox.shrink when no active tab or no results
      expect(find.byType(ResultSubTabBar), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleCheckBig), findsNothing);
      expect(find.byIcon(LucideIcons.circleAlert), findsNothing);
    });

    testWidgets('应渲染多个结果子标签', (tester) async {
      final appProvider = AppProvider();
      appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
      appProvider.tab.getResultsForTab('t1').addAll([
        ResultSubTab(id: 'r1', label: 'Result 1'),
        ResultSubTab(id: 'r2', label: 'Result 2'),
      ]);

      await tester.pumpWidget(
        buildTestableWidget(appProvider, child: const ResultSubTabBar()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Result 1'), findsOneWidget);
      expect(find.text('Result 2'), findsOneWidget);
    });

    testWidgets('点击子标签应切换活跃结果', (tester) async {
      final appProvider = AppProvider();
      appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
      appProvider.tab.getResultsForTab('t1').addAll([
        ResultSubTab(id: 'r1', label: 'Result 1'),
        ResultSubTab(id: 'r2', label: 'Result 2'),
      ]);

      await tester.pumpWidget(
        buildTestableWidget(appProvider, child: const ResultSubTabBar()),
      );
      await tester.pumpAndSettle();

      // Initially active result is index 0
      expect(appProvider.tab.activeResultIndex, 0);

      // Tap on second result tab
      await tester.tap(find.text('Result 2'));
      await tester.pumpAndSettle();

      expect(
        appProvider.tab.activeResultIndex,
        1,
        reason: '点击 Result 2 应将其设为活跃结果',
      );
    });

    testWidgets('错误结果应显示错误图标', (tester) async {
      final appProvider = AppProvider();
      appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
      appProvider.tab.getResultsForTab('t1').addAll([
        ResultSubTab(id: 'r1', label: 'OK'),
        ResultSubTab(id: 'r2', label: 'Error', errorMessage: 'Syntax error'),
      ]);

      await tester.pumpWidget(
        buildTestableWidget(appProvider, child: const ResultSubTabBar()),
      );
      await tester.pumpAndSettle();

      expect(
        find.byIcon(LucideIcons.circleAlert),
        findsOneWidget,
        reason: '错误结果应显示错误图标',
      );
      expect(
        find.byIcon(LucideIcons.circleCheckBig),
        findsOneWidget,
        reason: '正常结果应显示成功图标',
      );
    });

    testWidgets('点击 Pin 图标应固定/取消固定结果', (tester) async {
      final appProvider = AppProvider();
      appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
      appProvider.tab.getResultsForTab('t1').addAll([
        ResultSubTab(id: 'r1', label: 'Result 1'),
      ]);

      await tester.pumpWidget(
        buildTestableWidget(appProvider, child: const ResultSubTabBar()),
      );
      await tester.pumpAndSettle();

      // Initially not pinned
      expect(appProvider.tab.activeResults.first.isPinned, isFalse);
      expect(find.byIcon(LucideIcons.pin), findsOneWidget);

      // Tap pin icon
      await tester.tap(find.byIcon(LucideIcons.pin));
      await tester.pumpAndSettle();

      expect(
        appProvider.tab.activeResults.first.isPinned,
        isTrue,
        reason: '点击 Pin 后结果应被固定',
      );
      expect(
        find.byIcon(LucideIcons.pin),
        findsOneWidget,
        reason: '固定后应显示实心 Pin 图标',
      );
    });

    testWidgets('点击 Close 图标应关闭结果', (tester) async {
      final appProvider = AppProvider();
      appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
      appProvider.tab.getResultsForTab('t1').addAll([
        ResultSubTab(id: 'r1', label: 'Result 1'),
        ResultSubTab(id: 'r2', label: 'Result 2'),
      ]);

      await tester.pumpWidget(
        buildTestableWidget(appProvider, child: const ResultSubTabBar()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Result 1'), findsOneWidget);
      expect(find.text('Result 2'), findsOneWidget);

      // Close the first result
      final closeIcons = find.byIcon(LucideIcons.x);
      expect(closeIcons, findsNWidgets(2));
      await tester.tap(closeIcons.first);
      await tester.pumpAndSettle();

      expect(find.text('Result 1'), findsNothing, reason: '关闭后 Result 1 不应再显示');
      expect(find.text('Result 2'), findsOneWidget);
    });

    testWidgets('点击 pinned history 子标签应切换回历史视图', (tester) async {
      final appProvider = AppProvider();
      appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
      appProvider.tab.ensureHistorySubTab('t1');
      appProvider.tab.addResultToTab(
        't1',
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

      await tester.pumpWidget(
        buildTestableWidget(appProvider, child: const ResultSubTabBar()),
      );
      await tester.pumpAndSettle();

      expect(
        appProvider.tab.getActiveSubTabType('t1'),
        ResultSubTabType.result,
      );
      expect(find.text('History'), findsOneWidget);

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(
        appProvider.tab.getActiveSubTabType('t1'),
        ResultSubTabType.history,
      );
    });

    testWidgets('点击 ClearAll 应关闭所有结果', (tester) async {
      final appProvider = AppProvider();
      appProvider.tab.addTab(QueryTab(id: 't1', title: 'Tab 1'));
      appProvider.tab.getResultsForTab('t1').addAll([
        ResultSubTab(id: 'r1', label: 'Result 1'),
        ResultSubTab(id: 'r2', label: 'Result 2'),
      ]);

      await tester.pumpWidget(
        buildTestableWidget(appProvider, child: const ResultSubTabBar()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Result 1'), findsOneWidget);
      expect(find.text('Result 2'), findsOneWidget);

      // Tap clear_all toolbar icon
      await tester.tap(find.byIcon(LucideIcons.eraser));
      await tester.pumpAndSettle();

      expect(find.text('Result 1'), findsNothing);
      expect(find.text('Result 2'), findsNothing);
    });
  });
}
