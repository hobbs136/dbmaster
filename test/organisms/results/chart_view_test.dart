import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/result_filter.dart';
import 'package:dbmaster/organisms/results/chart_view.dart';
import 'package:dbmaster/services/chart/chart_recommender.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// M2 ChartView Widget 测试（R2 图表视图）。
///
/// 验证：空数据态、推荐生效、类型切换渲染对应 fl_chart 组件、采样提示。
/// 用 MaterialApp + AppLocalizations 包裹（ChartView 依赖 l10n）。
void main() {
  Widget buildChartView({
    required List<Map<String, dynamic>> data,
    Map<String, ColumnDataType>? columnTypes,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: ChartView(data: data, columnTypes: columnTypes),
      ),
    );
  }

  group('ChartView (M2)', () {
    testWidgets('空数据显示空状态', (tester) async {
      await tester.pumpWidget(buildChartView(data: const []));
      await tester.pumpAndSettle();

      // 空状态不渲染任何 fl_chart
      expect(find.byType(BarChart), findsNothing);
      expect(find.byType(LineChart), findsNothing);
      expect(find.byType(PieChart), findsNothing);
      expect(find.byType(ScatterChart), findsNothing);
    });

    testWidgets('日期+数值数据推荐折线图（LineChart 渲染）', (tester) async {
      await tester.pumpWidget(
        buildChartView(
          data: [
            {'date': '2026-01-01', 'amount': 100},
            {'date': '2026-01-02', 'amount': 200},
          ],
          columnTypes: {
            'date': ColumnDataType.dateTime,
            'amount': ColumnDataType.numeric,
          },
        ),
      );
      await tester.pumpAndSettle();

      // 推荐折线图 → LineChart 渲染
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('1分类+1数值（基数≤10）推荐饼图（PieChart 渲染）', (tester) async {
      await tester.pumpWidget(
        buildChartView(
          data: [
            {'category': 'A', 'count': 10},
            {'category': 'B', 'count': 20},
          ],
          columnTypes: {
            'category': ColumnDataType.string,
            'count': ColumnDataType.numeric,
          },
        ),
      );
      await tester.pumpAndSettle();

      // 1 分类 + 1 数值 + 基数 ≤10 → 饼图
      expect(find.byType(PieChart), findsOneWidget);
    });

    testWidgets('多分类+数值推荐柱状图（BarChart 渲染）', (tester) async {
      await tester.pumpWidget(
        buildChartView(
          data: [
            {'region': 'North', 'country': 'CN', 'sales': 100},
            {'region': 'South', 'country': 'US', 'sales': 200},
          ],
          columnTypes: {
            'region': ColumnDataType.string,
            'country': ColumnDataType.string,
            'sales': ColumnDataType.numeric,
          },
        ),
      );
      await tester.pumpAndSettle();

      // 多于 1 个分类列 → 不走饼图，走柱状
      expect(find.byType(BarChart), findsOneWidget);
    });

    testWidgets('2 数值列推荐散点图（ScatterChart 渲染）', (tester) async {
      await tester.pumpWidget(
        buildChartView(
          data: [
            {'x': 1.0, 'y': 2.0},
            {'x': 3.0, 'y': 4.0},
          ],
          columnTypes: {
            'x': ColumnDataType.numeric,
            'y': ColumnDataType.numeric,
          },
        ),
      );
      await tester.pumpAndSettle();

      // 推荐散点图 → ScatterChart 渲染
      expect(find.byType(ScatterChart), findsOneWidget);
    });

    testWidgets('配置栏含 PNG 导出按钮（LucideIcons.download）', (tester) async {
      await tester.pumpWidget(
        buildChartView(
          data: [
            {'a': 1, 'b': 2},
          ],
          columnTypes: {
            'a': ColumnDataType.numeric,
            'b': ColumnDataType.numeric,
          },
        ),
      );
      await tester.pumpAndSettle();

      // 导出 PNG 按钮（LucideIcons.download）
      final downloadButtons = find.byIcon(LucideIcons.download);
      expect(downloadButtons, findsWidgets);
    });

    testWidgets('大数据集（>1000 点）显示采样提示', (tester) async {
      // 造 1200 行数据，触发采样
      final data = List.generate(1200, (i) => {'cat': 'c$i', 'n': i});
      await tester.pumpWidget(
        buildChartView(
          data: data,
          columnTypes: {
            'cat': ColumnDataType.string,
            'n': ColumnDataType.numeric,
          },
        ),
      );
      await tester.pumpAndSettle();

      // 采样提示文本（en: "Large dataset: sampled N points..."）
      final samplingNotice = find.textContaining('sampled');
      expect(samplingNotice, findsOneWidget);
    });
  });
}
