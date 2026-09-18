import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/query_optimizer/explain_parser.dart';
import 'package:dbmaster/models/query_optimizer/execution_plan.dart';

void main() {
  group('ExplainParser', () {
    test('parses MySQL EXPLAIN results correctly', () {
      final rawResults = [
        {
          'id': 1,
          'select_type': 'SIMPLE',
          'table': 'users',
          'type': 'ALL',
          'possible_keys': null,
          'key': null,
          'key_len': null,
          'ref': null,
          'rows': 50000,
          'Extra': 'Using where',
        },
        {
          'id': 1,
          'select_type': 'SIMPLE',
          'table': 'orders',
          'type': 'ref',
          'possible_keys': 'idx_user_id',
          'key': 'idx_user_id',
          'key_len': '4',
          'ref': 'db.users.id',
          'rows': 10,
          'Extra': null,
        },
      ];

      final plan = ExplainParser.parse(
        rawResults: rawResults,
        databaseType: 'mysql',
        originalQuery:
            'SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u.status = "active"',
      );

      expect(plan.databaseType, equals('mysql'));
      expect(plan.steps.length, equals(2));
      expect(plan.steps[0].table, equals('users'));
      expect(plan.steps[0].scanType, equals(ScanType.fullTable));
      expect(plan.steps[0].estimatedRows, equals(50000));
      expect(plan.steps[1].table, equals('orders'));
      expect(plan.steps[1].scanType, equals(ScanType.ref));
      expect(plan.hasFullTableScan, isTrue);
    });

    test('parses PostgreSQL EXPLAIN results correctly', () {
      final rawResults = [
        {
          'QUERY PLAN':
              'Seq Scan on users  (cost=0.00..1234.56 rows=50000 width=100)',
        },
        {
          'QUERY PLAN':
              'Index Scan using idx_user_id on orders  (cost=0.29..8.30 rows=10 width=50)',
        },
      ];

      final plan = ExplainParser.parse(
        rawResults: rawResults,
        databaseType: 'postgresql',
        originalQuery:
            'SELECT * FROM users u JOIN orders o ON u.id = o.user_id',
      );

      expect(plan.databaseType, equals('postgresql'));
      expect(plan.steps.length, equals(2));
      expect(plan.steps[0].scanType, equals(ScanType.seqScan));
      expect(plan.steps[1].scanType, equals(ScanType.indexScan));
    });

    test('parses SQLite EXPLAIN results correctly', () {
      final rawResults = [
        {'id': 2, 'parent': 0, 'notused': 0, 'detail': 'SCAN TABLE users'},
        {
          'id': 3,
          'parent': 0,
          'notused': 0,
          'detail': 'SEARCH TABLE orders USING INDEX idx_user_id (user_id=?)',
        },
      ];

      final plan = ExplainParser.parse(
        rawResults: rawResults,
        databaseType: 'sqlite',
        originalQuery:
            'SELECT * FROM users JOIN orders ON users.id = orders.user_id',
      );

      expect(plan.databaseType, equals('sqlite'));
      expect(plan.steps.length, equals(2));
      expect(plan.steps[0].scanType, equals(ScanType.fullTable));
      expect(plan.steps[1].scanType, equals(ScanType.index_));
    });

    test('handles empty results gracefully', () {
      final plan = ExplainParser.parse(
        rawResults: [],
        databaseType: 'mysql',
        originalQuery: 'SELECT 1',
      );

      expect(plan.steps, isEmpty);
      expect(plan.hasFullTableScan, isFalse);
    });

    test('handles unknown database type with generic parser', () {
      final rawResults = [
        {
          'id': 1,
          'select_type': 'SIMPLE',
          'table': 'test',
          'type': 'ALL',
          'rows': 100,
        },
      ];

      final plan = ExplainParser.parse(
        rawResults: rawResults,
        databaseType: 'unknown_db',
        originalQuery: 'SELECT * FROM test',
      );

      expect(plan.steps.length, equals(1));
      expect(plan.steps[0].table, equals('test'));
    });
  });

  group('ScanType', () {
    test('fromCode parses MySQL scan types', () {
      expect(ScanType.fromCode('ALL'), equals(ScanType.fullTable));
      expect(ScanType.fromCode('index'), equals(ScanType.index_));
      expect(ScanType.fromCode('range'), equals(ScanType.range));
      expect(ScanType.fromCode('ref'), equals(ScanType.ref));
      expect(ScanType.fromCode('eq_ref'), equals(ScanType.eqRef));
      expect(ScanType.fromCode('const'), equals(ScanType.const_));
    });

    test('fromCode handles PostgreSQL scan types', () {
      expect(ScanType.fromCode('Seq Scan'), equals(ScanType.seqScan));
      expect(ScanType.fromCode('Index Scan'), equals(ScanType.indexScan));
      expect(
        ScanType.fromCode('Bitmap Heap Scan'),
        equals(ScanType.bitmapHeapScan),
      );
    });

    test('efficiency flags work correctly', () {
      expect(ScanType.const_.isEfficient, isTrue);
      expect(ScanType.eqRef.isEfficient, isTrue);
      expect(ScanType.fullTable.isEfficient, isFalse);
      expect(ScanType.fullTable.isInefficient, isTrue);
      expect(ScanType.seqScan.isInefficient, isTrue);
    });
  });
}
