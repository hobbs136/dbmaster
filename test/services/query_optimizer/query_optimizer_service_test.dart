import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/query_optimizer/query_optimizer_service.dart';

// ============================================================================
// QueryOptimizerService Tests
// ============================================================================

void main() {
  group('QueryOptimizerService', () {
    final rawExplainResults = [
      {
        'id': 1,
        'select_type': 'SIMPLE',
        'table': 'users',
        'type': 'ALL',
        'possible_keys': null,
        'key': null,
        'key_len': null,
        'ref': null,
        'rows': 100000,
        'Extra': 'Using where',
      },
    ];

    const originalQuery = 'SELECT * FROM users WHERE age > 18';
    const databaseType = 'mysql';

    group('analyzeQuery', () {
      test('应返回包含执行计划的 PerformanceReport', () {
        final report = QueryOptimizerService.analyzeQuery(
          rawExplainResults: rawExplainResults,
          originalQuery: originalQuery,
          databaseType: databaseType,
        );

        expect(report.executionPlan, isNotNull);
        expect(report.executionPlan.databaseType, equals(databaseType));
        expect(report.executionPlan.steps, isNotEmpty);
        expect(report.bottlenecks, isNotNull);
        expect(report.indexRecommendations, isNotNull);
        expect(report.queryRewrites, isNotNull);
        expect(report.summary, isNotNull);
        expect(report.analysisDuration, isNotNull);
        expect(report.analysisDuration.inMilliseconds, greaterThanOrEqualTo(0));
      });

      test('执行计划应包含正确的表信息', () {
        final report = QueryOptimizerService.analyzeQuery(
          rawExplainResults: rawExplainResults,
          originalQuery: originalQuery,
          databaseType: databaseType,
        );

        final step = report.executionPlan.steps.first;
        expect(step.table, equals('users'));
        expect(step.scanType, isNotNull);
      });

      test('应识别全表扫描瓶颈', () {
        final report = QueryOptimizerService.analyzeQuery(
          rawExplainResults: rawExplainResults,
          originalQuery: originalQuery,
          databaseType: databaseType,
        );

        final hasFullScan = report.bottlenecks.any(
          (b) => b.type == BottleneckType.fullTableScan,
        );
        expect(hasFullScan, isTrue, reason: 'ALL 扫描类型应被识别为全表扫描瓶颈');
      });

      test('空 EXPLAIN 结果不应崩溃', () {
        final report = QueryOptimizerService.analyzeQuery(
          rawExplainResults: const [],
          originalQuery: originalQuery,
          databaseType: databaseType,
        );

        expect(report.executionPlan.steps, isEmpty);
        // bottlenecks may still be generated from query analysis even without EXPLAIN
        expect(report.bottlenecks, isNotNull);
      });
    });

    group('analyzeQueryForAI', () {
      test('应返回结构化的 JSON 数据', () {
        final result = QueryOptimizerService.analyzeQueryForAI(
          rawExplainResults: rawExplainResults,
          originalQuery: originalQuery,
          databaseType: databaseType,
        );

        expect(result['success'], isTrue);
        expect(result['execution_plan'], isNotNull);
        expect(result['bottlenecks'], isA<List>());
        expect(result['index_recommendations'], isA<List>());
        expect(result['query_rewrites'], isA<List>());
        expect(result['summary'], isNotNull);
        expect(result['highest_severity'], isA<String>());
        expect(result['has_critical_issues'], isA<bool>());
        expect(result['total_estimated_improvement'], isA<num>());
      });

      test('无瓶颈时应返回空列表', () {
        final result = QueryOptimizerService.analyzeQueryForAI(
          rawExplainResults: const [],
          originalQuery: 'SELECT 1',
          databaseType: databaseType,
        );

        expect(result['bottlenecks'], isEmpty);
        expect(result['index_recommendations'], isEmpty);
      });
    });

    group('formatReportForAI', () {
      test('应返回非空的格式化字符串', () {
        final report = QueryOptimizerService.analyzeQuery(
          rawExplainResults: rawExplainResults,
          originalQuery: originalQuery,
          databaseType: databaseType,
        );

        final formatted = QueryOptimizerService.formatReportForAI(report);

        expect(formatted, isNotEmpty);
        expect(formatted, contains('Query Performance Analysis'));
        expect(formatted, contains(databaseType));
      });

      test('应包含瓶颈描述（如果有）', () {
        final report = QueryOptimizerService.analyzeQuery(
          rawExplainResults: rawExplainResults,
          originalQuery: originalQuery,
          databaseType: databaseType,
        );

        final formatted = QueryOptimizerService.formatReportForAI(report);

        if (report.bottlenecks.isNotEmpty) {
          expect(formatted, contains('Performance Issues'));
        }
      });

      test('空报告应返回基本结构', () {
        final report = QueryOptimizerService.analyzeQuery(
          rawExplainResults: const [],
          originalQuery: 'SELECT 1',
          databaseType: databaseType,
        );

        final formatted = QueryOptimizerService.formatReportForAI(report);

        expect(formatted, contains('Query Performance Analysis'));
        expect(formatted, contains('Execution Plan'));
      });
    });
  });
}
