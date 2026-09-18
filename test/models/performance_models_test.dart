import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/performance_models.dart';

void main() {
  group('SlowQuery', () {
    test('fromMap parses correctly', () {
      final q = SlowQuery.fromMap({
        'sql_text': 'SELECT * FROM large_table',
        'query_time': '2.5',
        'start_time': '2026-06-01 12:00:00',
        'db': 'test_db',
        'rows_examined': '100000',
        'rows_sent': '10',
      });
      expect(q.query, 'SELECT * FROM large_table');
      expect(q.executionTime, 2.5);
      expect(q.database, 'test_db');
      expect(q.rowsExamined, 100000);
      expect(q.rowsSent, 10);
    });

    test('fromMap handles missing fields', () {
      final q = SlowQuery.fromMap({});
      expect(q.query, '');
      expect(q.executionTime, 0.0);
      expect(q.database, '');
    });

    test('executionTimeFormatted for seconds', () {
      final q = SlowQuery(
        query: 'x',
        executionTime: 3.5,
        timestamp: DateTime.now(),
        database: 'db',
      );
      expect(q.executionTimeFormatted, contains('3.50 s'));
    });

    test('executionTimeFormatted for milliseconds', () {
      final q = SlowQuery(
        query: 'x',
        executionTime: 0.05,
        timestamp: DateTime.now(),
        database: 'db',
      );
      expect(q.executionTimeFormatted, contains('ms'));
    });
  });

  group('IndexUsage', () {
    test('fromMap parses correctly', () {
      final i = IndexUsage.fromMap({
        'TABLE_NAME': 'users',
        'INDEX_NAME': 'idx_email',
        'usage_count': '500',
        'CARDINALITY': '1000',
        'NON_UNIQUE': '1',
      });
      expect(i.tableName, 'users');
      expect(i.indexName, 'idx_email');
      expect(i.usageCount, 500);
      expect(i.isUsed, true);
      expect(i.isUnique, false);
      expect(i.isPrimary, false);
    });

    test('fromMap detects primary key', () {
      final i = IndexUsage.fromMap({
        'TABLE_NAME': 'users',
        'INDEX_NAME': 'PRIMARY',
        'usage_count': '0',
        'NON_UNIQUE': '0',
      });
      expect(i.isPrimary, true);
      expect(i.isUsed, false);
    });

    test('sizeFormatted returns N/A when null', () {
      final i = IndexUsage(
        tableName: 't',
        indexName: 'i',
        usageCount: 0,
        isUsed: false,
      );
      expect(i.sizeFormatted, 'N/A');
    });
  });

  group('TableStatistics', () {
    test('fromMap parses correctly', () {
      final s = TableStatistics.fromMap({
        'TABLE_NAME': 'users',
        'TABLE_ROWS': '10000',
        'DATA_LENGTH': '1024000',
        'INDEX_LENGTH': '512000',
        'UPDATE_TIME': '2026-06-01 12:00:00',
        'ENGINE': 'InnoDB',
        'TABLE_COLLATION': 'utf8mb4_general_ci',
        'AUTO_INCREMENT': '10001',
      });
      expect(s.tableName, 'users');
      expect(s.rowCount, 10000);
      expect(s.dataSize, 1024000);
      expect(s.indexSize, 512000);
      expect(s.engine, 'InnoDB');
      expect(s.autoIncrement, 10001);
    });

    test('totalSize is sum of data and index', () {
      final s = TableStatistics(
        tableName: 't',
        rowCount: 100,
        dataSize: 1000,
        indexSize: 500,
        lastUpdate: DateTime.now(),
      );
      expect(s.totalSize, 1500);
    });

    test('dataSizeFormatted returns formatted bytes', () {
      final s = TableStatistics(
        tableName: 't',
        rowCount: 0,
        dataSize: 512,
        indexSize: 0,
        lastUpdate: DateTime.now(),
      );
      expect(s.dataSizeFormatted, '512 B');
    });
  });

  group('DatabaseSummary', () {
    test('fromMap parses correctly', () {
      final s = DatabaseSummary.fromMap({
        'total_rows': '50000',
        'total_data': '10485760',
        'total_index': '2097152',
        'table_count': '20',
        'index_count': '35',
        'queries_per_sec': '25.5',
      });
      expect(s.totalRows, 50000);
      expect(s.totalDataSize, 10485760);
      expect(s.totalIndexSize, 2097152);
      expect(s.tableCount, 20);
      expect(s.indexCount, 35);
      expect(s.avgQueriesPerSecond, 25.5);
    });

    test('totalSize is sum of data and index', () {
      final s = DatabaseSummary(totalDataSize: 1000, totalIndexSize: 500);
      expect(s.totalSize, 1500);
    });
  });

  group('PerformanceSuggestion', () {
    test('fromMap parses correctly', () {
      final s = PerformanceSuggestion.fromMap({
        'type': 'index',
        'title': 'Missing index on users.email',
        'description': 'Add index to improve lookup',
        'impact': 'high',
        'sql': 'CREATE INDEX idx_email ON users(email)',
        'affected_tables': ['users'],
        'recommendation': 'Execute the index creation immediately',
      });
      expect(s.type, 'index');
      expect(s.title, 'Missing index on users.email');
      expect(s.impact, 'high');
      expect(s.sql, 'CREATE INDEX idx_email ON users(email)');
      expect(s.affectedTables, ['users']);
    });

    test('impactColor returns Color for each level', () {
      final high = PerformanceSuggestion(
        type: 'q',
        title: 't',
        description: 'd',
        impact: 'high',
        affectedTables: [],
      );
      final medium = PerformanceSuggestion(
        type: 'q',
        title: 't',
        description: 'd',
        impact: 'medium',
        affectedTables: [],
      );
      final low = PerformanceSuggestion(
        type: 'q',
        title: 't',
        description: 'd',
        impact: 'low',
        affectedTables: [],
      );
      expect(high.impactColor, isNotNull);
      expect(medium.impactColor, isNotNull);
      expect(low.impactColor, isNotNull);
    });

    test('typeIcon returns IconData for each type', () {
      final types = ['index', 'query', 'table', 'configuration', 'general'];
      for (final t in types) {
        final s = PerformanceSuggestion(
          type: t,
          title: 't',
          description: 'd',
          impact: 'medium',
          affectedTables: [],
        );
        expect(s.typeIcon, isNotNull);
      }
    });
  });

  group('QueryExecutionPlan', () {
    test('fromMap parses correctly', () {
      final plan = QueryExecutionPlan.fromMap({
        'id': '1',
        'select_type': 'SIMPLE',
        'table': 'users',
        'type': 'ALL',
        'possible_keys': 'idx_email',
        'key': null,
        'rows': '10000',
        'Extra': 'Using where',
      });
      expect(plan.id, 1);
      expect(plan.selectType, 'SIMPLE');
      expect(plan.table, 'users');
      expect(plan.type, 'ALL');
      expect(plan.isFullTableScan, true);
      expect(plan.isUsingIndex, false);
      expect(plan.rows, 10000);
    });

    test('isUsingIndex returns true when key is set', () {
      final plan = QueryExecutionPlan.fromMap({
        'id': '1',
        'select_type': 'SIMPLE',
        'table': 'users',
        'type': 'ref',
        'key': 'idx_email',
      });
      expect(plan.isUsingIndex, true);
      expect(plan.isFullTableScan, false);
    });
  });
}
