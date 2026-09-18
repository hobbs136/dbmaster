import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/results/statistics_panel.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('StatisticsPanel', () {
    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: AppTheme.darkTheme,
        home: Scaffold(body: child),
      );
    }

    testWidgets('空数据应显示空状态', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(const StatisticsPanel(data: [])),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StatisticsPanel), findsOneWidget);
    });

    testWidgets('应渲染 KPI 卡片', (tester) async {
      final data = [
        {'id': 1, 'name': 'Alice', 'age': 30, 'score': 85.5},
        {'id': 2, 'name': 'Bob', 'age': 25, 'score': 92.0},
      ];

      await tester.pumpWidget(buildTestableWidget(StatisticsPanel(data: data)));
      await tester.pumpAndSettle();

      // 应找到 3 个 KPI 卡片（总行数、数值列数、文本列数）
      // _KpiCard 是 Container，查找 Icon 来确认 KPI 卡片存在
      expect(find.byIcon(LucideIcons.clipboardList), findsOneWidget);
      expect(find.byIcon(LucideIcons.pin), findsOneWidget);
      expect(find.byIcon(LucideIcons.type), findsOneWidget);
    });

    testWidgets('应正确统计数值列', (tester) async {
      final data = [
        {'id': 1, 'name': 'Alice', 'age': 30},
        {'id': 2, 'name': 'Bob', 'age': 25},
      ];

      await tester.pumpWidget(buildTestableWidget(StatisticsPanel(data: data)));
      await tester.pumpAndSettle();

      // 数值列：id, age = 2；文本列：name = 1
      expect(find.text('2'), findsWidgets);
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('应渲染数值统计表格', (tester) async {
      final data = [
        {'id': 1, 'age': 30},
        {'id': 2, 'age': 25},
        {'id': 3, 'age': 35},
      ];

      await tester.pumpWidget(buildTestableWidget(StatisticsPanel(data: data)));
      await tester.pumpAndSettle();

      // 应找到 DataTable
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('应处理混合数据类型', (tester) async {
      final data = [
        {'id': 1, 'name': 'Alice', 'active': true, 'score': 85.5},
        {'id': 2, 'name': 'Bob', 'active': false, 'score': 92.0},
      ];

      await tester.pumpWidget(buildTestableWidget(StatisticsPanel(data: data)));
      await tester.pumpAndSettle();

      // 数值列：id, score = 2；布尔值和文本不统计
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('应处理 null 值', (tester) async {
      final data = [
        {'id': 1, 'age': null},
        {'id': 2, 'age': 25},
      ];

      await tester.pumpWidget(buildTestableWidget(StatisticsPanel(data: data)));
      await tester.pumpAndSettle();

      // 应正常渲染，不崩溃
      expect(find.byType(StatisticsPanel), findsOneWidget);
    });

    testWidgets('单行数据应正确统计', (tester) async {
      final data = [
        {'value': 100},
      ];

      await tester.pumpWidget(buildTestableWidget(StatisticsPanel(data: data)));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsWidgets); // 总行数 = 1
    });

    testWidgets('大量数据应正确统计总数', (tester) async {
      final data = List.generate(1000, (i) => {'id': i, 'value': i * 2});

      await tester.pumpWidget(buildTestableWidget(StatisticsPanel(data: data)));
      await tester.pumpAndSettle();

      // 应找到 1000 的总行数显示（KPI 卡片中的大字体文本）
      expect(find.text('1000'), findsWidgets);
    });
  });
}
