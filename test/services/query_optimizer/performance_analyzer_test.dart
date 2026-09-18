import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/query_optimizer/performance_analyzer.dart';
import 'package:dbmaster/models/query_optimizer/execution_plan.dart';

void main() {
  group('PerformanceAnalyzer', () {
    test('detects full table scan bottleneck', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM users WHERE status = "active"',
        steps: [
          PlanStep(
            id: 1,
            table: 'users',
            scanType: ScanType.fullTable,
            estimatedRows: 50000,
            extra: 'Using where',
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final bottlenecks = PerformanceAnalyzer.analyze(plan);

      expect(bottlenecks.length, greaterThanOrEqualTo(1));
      expect(
        bottlenecks.any((b) => b.type == BottleneckType.fullTableScan),
        isTrue,
      );
      expect(bottlenecks.first.severity, equals(Severity.high));
    });

    test('detects missing index', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM products WHERE category_id = 5',
        steps: [
          PlanStep(
            id: 1,
            table: 'products',
            scanType: ScanType.fullTable,
            estimatedRows: 10000,
            possibleKeys: null,
            key: null,
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final bottlenecks = PerformanceAnalyzer.analyze(plan);

      expect(
        bottlenecks.any((b) => b.type == BottleneckType.missingIndex),
        isTrue,
      );
    });

    test('detects SELECT * usage', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM users',
        steps: [
          PlanStep(
            id: 1,
            table: 'users',
            scanType: ScanType.index_,
            estimatedRows: 100,
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final bottlenecks = PerformanceAnalyzer.analyze(plan);

      expect(
        bottlenecks.any((b) => b.type == BottleneckType.selectStar),
        isTrue,
      );
      expect(
        bottlenecks
            .firstWhere((b) => b.type == BottleneckType.selectStar)
            .severity,
        equals(Severity.low),
      );
    });

    test('detects OFFSET pagination', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT id FROM users LIMIT 10 OFFSET 1000',
        steps: [PlanStep(id: 1, table: 'users', scanType: ScanType.index_)],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final bottlenecks = PerformanceAnalyzer.analyze(plan);

      expect(
        bottlenecks.any((b) => b.type == BottleneckType.offsetPagination),
        isTrue,
      );
    });

    test('detects filesort', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM users ORDER BY created_at',
        steps: [
          PlanStep(
            id: 1,
            table: 'users',
            scanType: ScanType.fullTable,
            extra: 'Using filesort',
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final bottlenecks = PerformanceAnalyzer.analyze(plan);

      expect(bottlenecks.any((b) => b.type == BottleneckType.fileSort), isTrue);
    });

    test('detects temporary table', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT status, COUNT(*) FROM users GROUP BY status',
        steps: [
          PlanStep(
            id: 1,
            table: 'users',
            scanType: ScanType.fullTable,
            extra: 'Using temporary; Using filesort',
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final bottlenecks = PerformanceAnalyzer.analyze(plan);

      expect(
        bottlenecks.any((b) => b.type == BottleneckType.temporaryTable),
        isTrue,
      );
    });

    test('generates summary correctly', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM users',
        steps: [
          PlanStep(
            table: 'users',
            scanType: ScanType.fullTable,
            estimatedRows: 50000,
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final bottlenecks = PerformanceAnalyzer.analyze(plan);
      final summary = PerformanceAnalyzer.generateSummary(plan, bottlenecks);

      expect(summary, contains('Performance Analysis Summary'));
      expect(summary, contains('users'));
      expect(summary, contains('full table scan'));
    });

    test('returns empty list for optimized query', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT id, name FROM users WHERE id = 1',
        steps: [
          PlanStep(
            id: 1,
            table: 'users',
            scanType: ScanType.const_,
            key: 'PRIMARY',
            estimatedRows: 1,
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final bottlenecks = PerformanceAnalyzer.analyze(plan);

      expect(bottlenecks, isEmpty);
    });
  });
}
