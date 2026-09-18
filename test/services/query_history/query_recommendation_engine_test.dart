import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/query_history/query_history_service.dart';
import 'package:dbmaster/services/query_history/query_recommendation_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('QueryRecommendationEngine', () {
    late QueryHistoryService historyService;
    late QueryRecommendationEngine engine;

    setUp(() async {
      historyService = QueryHistoryService();
      await historyService.initialize(customPath: ':memory:');
      await historyService.clearHistory();
      engine = QueryRecommendationEngine(historyService);

      // Seed with some test data
      await historyService.recordQuery(
        sqlStatement: 'SELECT * FROM users WHERE status = "active"',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 50,
      );
      await historyService.recordQuery(
        sqlStatement:
            'SELECT id, name FROM users WHERE created_at > "2024-01-01"',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 60,
      );
      await historyService.recordQuery(
        sqlStatement: 'SELECT * FROM orders WHERE user_id = 123',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 30,
      );
      await historyService.recordQuery(
        sqlStatement: 'UPDATE users SET status = "inactive" WHERE id = 5',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 20,
      );
      await historyService.recordQuery(
        sqlStatement: 'SELECT COUNT(*) FROM users',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 40,
      );
    });

    tearDown(() async {
      await historyService.close();
    });

    test('recommends similar queries based on current input', () async {
      final recommendations = await engine.recommendSimilarQueries(
        currentQuery: 'SELECT * FROM users WHERE status = "pending"',
        limit: 3,
      );

      expect(recommendations.isNotEmpty, isTrue);
      // Should recommend queries involving "users" table
      expect(
        recommendations.any((r) => r.record.sqlStatement.contains('users')),
        isTrue,
      );
    });

    test('recommends queries for specific table', () async {
      final recommendations = await engine.recommendForTable(
        tableName: 'users',
        limit: 5,
      );

      expect(recommendations.isNotEmpty, isTrue);
      expect(
        recommendations.every((r) => r.record.sqlStatement.contains('users')),
        isTrue,
      );
    });

    test('returns empty list for unknown table', () async {
      final recommendations = await engine.recommendForTable(
        tableName: 'nonexistent',
        limit: 5,
      );

      expect(recommendations, isEmpty);
    });

    test('similarity scores are between 0 and 1', () async {
      final recommendations = await engine.recommendSimilarQueries(
        currentQuery: 'SELECT * FROM users',
        limit: 5,
      );

      for (final rec in recommendations) {
        expect(rec.similarity, greaterThanOrEqualTo(0.0));
        expect(rec.similarity, lessThanOrEqualTo(1.0));
      }
    });

    test('excludes identical queries from recommendations', () async {
      final query = 'SELECT * FROM users WHERE status = "active"';
      final recommendations = await engine.recommendSimilarQueries(
        currentQuery: query,
        limit: 5,
      );

      expect(
        recommendations.any((r) => r.record.sqlStatement == query),
        isFalse,
      );
    });

    test('includes reason for each recommendation', () async {
      final recommendations = await engine.recommendSimilarQueries(
        currentQuery: 'SELECT * FROM users',
        limit: 3,
      );

      for (final rec in recommendations) {
        expect(rec.reason, isNotEmpty);
      }
    });

    test('returns empty list for short queries', () async {
      final recommendations = await engine.recommendSimilarQueries(
        currentQuery: 'SE',
        limit: 5,
      );

      expect(recommendations, isEmpty);
    });

    test('getFrequentQueries returns most used patterns', () async {
      // Add multiple similar queries to create a pattern
      for (var i = 0; i < 3; i++) {
        await historyService.recordQuery(
          sqlStatement: 'SELECT * FROM products WHERE category = "$i"',
          connectionId: 'conn_1',
          databaseType: 'mysql',
          executionTimeMs: 25,
        );
      }

      final frequent = await engine.getFrequentQueries(limit: 5);

      expect(frequent.isNotEmpty, isTrue);
      // The pattern with 3 occurrences should be ranked high
      expect(
        frequent.any((r) => r.record.sqlStatement.contains('products')),
        isTrue,
      );
    });

    test('recommendations include query metadata', () async {
      final recommendations = await engine.recommendSimilarQueries(
        currentQuery: 'SELECT * FROM orders',
        limit: 2,
      );

      if (recommendations.isNotEmpty) {
        final rec = recommendations.first;
        expect(rec.record.executionTimeMs, isNotNull);
        expect(rec.record.createdAt, isNotNull);
      }
    });
  });
}
