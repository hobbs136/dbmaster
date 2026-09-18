import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/query_history/query_history_service.dart';
import 'package:dbmaster/models/query_history/query_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('QueryHistoryService', () {
    late QueryHistoryService service;

    setUp(() async {
      service = QueryHistoryService();
      await service.initialize(customPath: ':memory:');
      await service.clearHistory();
    });

    tearDown(() async {
      await service.close();
    });

    test('records a query successfully', () async {
      final record = await service.recordQuery(
        sqlStatement: 'SELECT * FROM users WHERE id = 1',
        connectionId: 'conn_1',
        connectionName: 'Local MySQL',
        databaseType: 'mysql',
        databaseName: 'test_db',
        executionTimeMs: 45,
        rowCount: 1,
        isSuccess: true,
      );

      expect(record.sqlStatement, equals('SELECT * FROM users WHERE id = 1'));
      expect(record.connectionId, equals('conn_1'));
      expect(record.isSuccess, isTrue);
      expect(record.queryType, equals('SELECT'));
    });

    test('searches queries by keywords', () async {
      // Record some queries
      await service.recordQuery(
        sqlStatement: 'SELECT * FROM users',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 10,
      );
      await service.recordQuery(
        sqlStatement: 'SELECT * FROM orders',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 20,
      );
      await service.recordQuery(
        sqlStatement: 'INSERT INTO users VALUES (1)',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 5,
      );

      // Search for "users"
      final results = await service.search(SearchCriteria(keywords: 'users'));

      expect(results.length, equals(2));
      expect(results.every((r) => r.sqlStatement.contains('users')), isTrue);
    });

    test('filters by query type', () async {
      await service.recordQuery(
        sqlStatement: 'SELECT * FROM users',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 10,
      );
      await service.recordQuery(
        sqlStatement: 'INSERT INTO users VALUES (1)',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 5,
      );

      final results = await service.search(SearchCriteria(queryType: 'SELECT'));

      expect(results.length, equals(1));
      expect(results.first.queryType, equals('SELECT'));
    });

    test('toggles favorite status', () async {
      final record = await service.recordQuery(
        sqlStatement: 'SELECT * FROM users',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 10,
      );

      expect(record.isFavorite, isFalse);

      // Toggle favorite
      await service.toggleFavorite(record.id!);

      // Search for favorites
      final favorites = await service.getFavorites();
      expect(favorites.length, equals(1));
      expect(favorites.first.isFavorite, isTrue);
    });

    test('adds tags to query', () async {
      final record = await service.recordQuery(
        sqlStatement: 'SELECT * FROM users',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 10,
      );

      await service.addTags(record.id!, ['report', 'daily']);

      final results = await service.search(SearchCriteria(tags: ['report']));

      expect(results.length, equals(1));
      expect(results.first.tags, contains('report'));
    });

    test('deletes a record', () async {
      final record = await service.recordQuery(
        sqlStatement: 'SELECT * FROM users',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 10,
      );

      await service.deleteRecord(record.id!);

      final results = await service.search(SearchCriteria());
      expect(results, isEmpty);
    });

    test('gets recent queries', () async {
      // Record multiple queries
      for (var i = 0; i < 5; i++) {
        await service.recordQuery(
          sqlStatement: 'SELECT * FROM table_$i',
          connectionId: 'conn_1',
          databaseType: 'mysql',
          executionTimeMs: 10,
        );
      }

      final recent = await service.getRecentQueries(limit: 3);
      expect(recent.length, equals(3));
    });

    test('returns statistics', () async {
      await service.recordQuery(
        sqlStatement: 'SELECT * FROM users',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 100,
        rowCount: 10,
      );
      await service.recordQuery(
        sqlStatement: 'INSERT INTO users VALUES (1)',
        connectionId: 'conn_1',
        databaseType: 'mysql',
        executionTimeMs: 50,
      );

      final stats = await service.getStatistics();

      expect(stats['totalQueries'], equals(2));
      expect(stats['favoriteQueries'], equals(0));
      expect(stats['typeDistribution'], contains('SELECT'));
      expect(stats['typeDistribution'], contains('INSERT'));
    });

    test('limits results with pagination', () async {
      for (var i = 0; i < 10; i++) {
        await service.recordQuery(
          sqlStatement: 'SELECT * FROM table_$i',
          connectionId: 'conn_1',
          databaseType: 'mysql',
          executionTimeMs: 10,
        );
      }

      final page1 = await service.search(SearchCriteria(limit: 5, offset: 0));
      final page2 = await service.search(SearchCriteria(limit: 5, offset: 5));

      expect(page1.length, equals(5));
      expect(page2.length, equals(5));
      expect(page1.first.id, isNot(equals(page2.first.id)));
    });
  });
}
