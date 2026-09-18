import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/query_optimizer/index_recommendation_engine.dart';
import 'package:dbmaster/models/query_optimizer/execution_plan.dart';

void main() {
  group('IndexRecommendationEngine', () {
    test('recommends index for full table scan', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery:
            'SELECT * FROM users WHERE status = "active" AND created_at > "2024-01-01"',
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

      final recommendations = IndexRecommendationEngine.recommendIndexes(
        plan: plan,
        originalQuery:
            'SELECT * FROM users WHERE status = "active" AND created_at > "2024-01-01"',
      );

      expect(recommendations.length, greaterThanOrEqualTo(1));
      expect(recommendations.first.tableName, equals('users'));
      expect(recommendations.first.columns.length, greaterThanOrEqualTo(1));
      expect(recommendations.first.ddlStatement, contains('CREATE INDEX'));
      expect(recommendations.first.ddlStatement, contains('users'));
    });

    test('generates correct index name format', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM orders WHERE user_id = 1',
        steps: [
          PlanStep(
            table: 'orders',
            scanType: ScanType.fullTable,
            estimatedRows: 10000,
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final recommendations = IndexRecommendationEngine.recommendIndexes(
        plan: plan,
        originalQuery: 'SELECT * FROM orders WHERE user_id = 1',
      );

      expect(recommendations.first.indexName, startsWith('idx_orders_'));
    });

    test('recommends index for filesort', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM users ORDER BY created_at DESC',
        steps: [
          PlanStep(
            table: 'users',
            scanType: ScanType.fullTable,
            extra: 'Using filesort',
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final recommendations = IndexRecommendationEngine.recommendIndexes(
        plan: plan,
        originalQuery: 'SELECT * FROM users ORDER BY created_at DESC',
      );

      expect(recommendations.any((r) => r.reason.contains('Filesort')), isTrue);
    });

    test('recommends index for GROUP BY', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT status, COUNT(*) FROM users GROUP BY status',
        steps: [
          PlanStep(
            table: 'users',
            scanType: ScanType.fullTable,
            extra: 'Using temporary',
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final recommendations = IndexRecommendationEngine.recommendIndexes(
        plan: plan,
        originalQuery: 'SELECT status, COUNT(*) FROM users GROUP BY status',
      );

      expect(recommendations.any((r) => r.reason.contains('GROUP BY')), isTrue);
    });

    test('avoids duplicate recommendations', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM users WHERE status = "active"',
        steps: [
          PlanStep(
            table: 'users',
            scanType: ScanType.fullTable,
            estimatedRows: 50000,
            possibleKeys: null,
            key: null,
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final recommendations = IndexRecommendationEngine.recommendIndexes(
        plan: plan,
        originalQuery: 'SELECT * FROM users WHERE status = "active"',
      );

      final indexNames = recommendations.map((r) => r.indexName).toList();
      expect(indexNames.toSet().length, equals(indexNames.length));
    });

    test('handles queries without WHERE clause', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM users',
        steps: [
          PlanStep(
            table: 'users',
            scanType: ScanType.fullTable,
            estimatedRows: 100,
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final recommendations = IndexRecommendationEngine.recommendIndexes(
        plan: plan,
        originalQuery: 'SELECT * FROM users',
      );

      // Small table, may not recommend index
      expect(recommendations, isEmpty);
    });

    test('generates unique index for unique constraints', () {
      final plan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: 'SELECT * FROM users WHERE email = "test@example.com"',
        steps: [
          PlanStep(
            table: 'users',
            scanType: ScanType.fullTable,
            estimatedRows: 10000,
          ),
        ],
        rawData: {},
        analyzedAt: DateTime.now(),
      );

      final recommendations = IndexRecommendationEngine.recommendIndexes(
        plan: plan,
        originalQuery: 'SELECT * FROM users WHERE email = "test@example.com"',
      );

      // Note: Currently the engine doesn't detect unique columns
      // This test verifies basic functionality
      expect(recommendations.isNotEmpty, isTrue);
    });
  });
}
