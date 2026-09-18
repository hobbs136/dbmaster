// QueryPlanVisualizer widget 测试（B2：索引推荐接入安全审查）。
//
// 覆盖：
// - onApplyDdl 回调触发（点「应用此索引」按钮 → 回调收到 DDL）
// - onApplyDdl=null 时不渲染按钮（纯展示场景）
// - ddlStatement=null 的推荐不渲染按钮
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/query_optimizer/execution_plan.dart';
import 'package:dbmaster/organisms/query_optimizer/query_plan_visualizer.dart';

/// 构造最小可用 PerformanceReport（含一条索引推荐）。
PerformanceReport _report({
  IndexRecommendation? recommendation,
}) {
  return PerformanceReport(
    executionPlan: ExecutionPlan(
      databaseType: 'mysql',
      originalQuery: 'SELECT * FROM t',
      steps: const [],
      rawData: const {},
      analyzedAt: DateTime(2026, 1, 1),
    ),
    bottlenecks: const [],
    indexRecommendations: [
      recommendation ??
          const IndexRecommendation(
            tableName: 'orders',
            indexName: 'idx_orders_user_id',
            columns: ['user_id'],
            reason: 'full table scan on WHERE',
            ddlStatement: 'CREATE INDEX idx_orders_user_id ON orders (user_id);',
          ),
    ],
    queryRewrites: const [],
    summary: 'test',
    analysisDuration: const Duration(milliseconds: 1),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData.light(),
    home: Scaffold(body: child),
  );
}

void main() {
  group('QueryPlanVisualizer B2: 应用此索引按钮', () {
    testWidgets('onApplyDdl 非 null 且 ddlStatement 存在 → 渲染按钮，点击触发回调',
        (tester) async {
      String? receivedDdl;
      await tester.pumpWidget(_wrap(QueryPlanVisualizer(
        report: _report(),
        onApplyDdl: (ddl) => receivedDdl = ddl,
      )));

      // 按钮存在。
      final button = find.text('Apply This Index');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      expect(
        receivedDdl,
        equals('CREATE INDEX idx_orders_user_id ON orders (user_id);'),
      );
    });

    testWidgets('onApplyDdl=null → 不渲染按钮（纯展示场景）', (tester) async {
      await tester.pumpWidget(_wrap(QueryPlanVisualizer(
        report: _report(),
        onApplyDdl: null,
      )));

      expect(find.text('Apply This Index'), findsNothing);
    });

    testWidgets('推荐无 ddlStatement → 不渲染按钮（即使 onApplyDdl 非 null）',
        (tester) async {
      await tester.pumpWidget(_wrap(QueryPlanVisualizer(
        report: _report(
          recommendation: const IndexRecommendation(
            tableName: 't',
            indexName: 'idx_t',
            columns: ['c'],
            reason: 'no ddl',
            ddlStatement: null, // 无 DDL
          ),
        ),
        onApplyDdl: (_) {},
      )));

      expect(find.text('Apply This Index'), findsNothing);
    });
  });
}
