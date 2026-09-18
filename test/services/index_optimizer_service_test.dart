import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/index_optimizer_service.dart';
import 'package:dbmaster/services/sql_optimizer_service.dart';

// ignore: deprecated_member_use_from_same_package
void main() {
  group('IndexOptimizerService', () {
    late IndexOptimizerService optimizer;

    setUp(() {
      // ignore: deprecated_member_use_from_same_package
      optimizer = IndexOptimizerService();
    });

    group('analyzeForIndex', () {
      test('suggests index for WHERE column without index', () {
        final suggestions = optimizer.analyzeForIndex(
          'SELECT * FROM users WHERE users.id = 1',
          [
            {'table': 'users', 'indexes': <Map<String, dynamic>>[]},
          ],
        );

        final whereSuggestion = suggestions.firstWhere(
          (s) => s.reason.contains('WHERE'),
        );
        expect(whereSuggestion.tableName, equals('users'));
        expect(whereSuggestion.columns, equals(['id']));
        expect(whereSuggestion.priority, equals(Priority.high));
        expect(
          whereSuggestion.createStatement,
          contains('CREATE INDEX idx_users_id'),
        );
      });

      test('suggests index for JOIN column without index', () {
        final suggestions = optimizer.analyzeForIndex(
          'SELECT * FROM users JOIN orders ON orders.user_id = users.id',
          [
            {'table': 'orders', 'indexes': <Map<String, dynamic>>[]},
          ],
        );

        final joinSuggestion = suggestions.firstWhere(
          (s) => s.reason.contains('JOIN'),
        );
        expect(joinSuggestion.tableName, equals('orders'));
        expect(joinSuggestion.columns, equals(['user_id']));
        expect(joinSuggestion.priority, equals(Priority.high));
      });

      test('suggests index for ORDER BY column without index', () {
        final suggestions = optimizer.analyzeForIndex(
          'SELECT * FROM users ORDER BY users.name',
          [
            {'table': 'users', 'indexes': <Map<String, dynamic>>[]},
          ],
        );

        final orderSuggestion = suggestions.firstWhere(
          (s) => s.reason.contains('ORDER BY'),
        );
        expect(orderSuggestion.tableName, equals('users'));
        expect(orderSuggestion.columns, equals(['name']));
        expect(orderSuggestion.priority, equals(Priority.medium));
      });

      test('suggests index for GROUP BY column without index', () {
        final suggestions = optimizer.analyzeForIndex(
          'SELECT * FROM users GROUP BY users.status',
          [
            {'table': 'users', 'indexes': <Map<String, dynamic>>[]},
          ],
        );

        final groupSuggestion = suggestions.firstWhere(
          (s) => s.reason.contains('GROUP BY'),
        );
        expect(groupSuggestion.tableName, equals('users'));
        expect(groupSuggestion.columns, equals(['status']));
        expect(groupSuggestion.priority, equals(Priority.medium));
      });

      test('does not suggest index when column already indexed', () {
        final suggestions = optimizer.analyzeForIndex(
          'SELECT * FROM users WHERE users.email = \'a@b.com\'',
          [
            {
              'table': 'users',
              'indexes': [
                {
                  'columns': ['email'],
                },
              ],
            },
          ],
        );

        expect(suggestions.where((s) => s.columns.contains('email')), isEmpty);
      });

      test('suggests composite index for multiple WHERE columns', () {
        final suggestions = optimizer.analyzeForIndex(
          'SELECT * FROM users WHERE users.a = 1 AND users.b = 2 AND users.c = 3',
          [
            {'table': 'users', 'indexes': <Map<String, dynamic>>[]},
          ],
        );

        final compositeSuggestion = suggestions.firstWhere(
          (s) => s.columns.length > 1,
        );
        expect(compositeSuggestion.columns, equals(['a', 'b', 'c']));
        expect(compositeSuggestion.createStatement, contains('a, b, c'));
        expect(compositeSuggestion.priority, equals(Priority.medium));
      });

      test('does not suggest composite index when it already exists', () {
        final suggestions = optimizer.analyzeForIndex(
          'SELECT * FROM users WHERE users.a = 1 AND users.b = 2 AND users.c = 3',
          [
            {
              'table': 'users',
              'indexes': [
                {
                  'columns': ['a', 'b', 'c'],
                },
              ],
            },
          ],
        );

        expect(suggestions.where((s) => s.columns.length > 1), isEmpty);
      });

      test('skips tables with null table name', () {
        final suggestions = optimizer.analyzeForIndex(
          'SELECT * FROM users WHERE users.id = 1',
          [
            {'table': null, 'indexes': <Map<String, dynamic>>[]},
          ],
        );

        expect(suggestions, isEmpty);
      });
    });

    group('generateIndexReport', () {
      test('returns success message for empty suggestions', () {
        final report = optimizer.generateIndexReport([]);
        expect(report, contains('看起来不错'));
      });

      test('categorizes high and medium priorities', () {
        final suggestions = [
          IndexSuggestion(
            tableName: 'users',
            columns: ['id'],
            reason: 'WHERE',
            priority: Priority.high,
            createStatement: 'CREATE INDEX idx_users_id ON users(id);',
          ),
          IndexSuggestion(
            tableName: 'orders',
            columns: ['created_at'],
            reason: 'ORDER BY',
            priority: Priority.medium,
            createStatement:
                'CREATE INDEX idx_orders_created_at ON orders(created_at);',
          ),
        ];

        final report = optimizer.generateIndexReport(suggestions);

        expect(report, contains('高优先级'));
        expect(report, contains('中优先级'));
        expect(report, contains('idx_users_id'));
        expect(report, contains('idx_orders_created_at'));
        expect(report, contains('索引设计原则'));
      });
    });

    group('IndexInfo.fromMap', () {
      test('maps SHOW INDEX result row', () {
        final info = IndexInfo.fromMap({
          'Table': 'users',
          'Key_name': 'PRIMARY',
          'Column_name': 'id',
          'Non_unique': '0',
          'Index_type': 'BTREE',
        });

        expect(info.table, equals('users'));
        expect(info.name, equals('PRIMARY'));
        expect(info.columns, equals(['id']));
        expect(info.isUnique, isTrue);
        expect(info.isPrimary, isTrue);
        expect(info.indexType, equals('BTREE'));
      });
    });

    group('IndexSuggestion.toJson', () {
      test('serializes suggestion to JSON', () {
        final suggestion = IndexSuggestion(
          tableName: 'users',
          columns: ['id'],
          reason: 'WHERE',
          priority: Priority.high,
          createStatement: 'CREATE INDEX idx_users_id ON users(id);',
          impact: 'fast',
        );

        final json = suggestion.toJson();

        expect(json['tableName'], equals('users'));
        expect(json['columns'], equals(['id']));
        expect(json['priority'], equals('high'));
        expect(json['createStatement'], contains('CREATE INDEX'));
        expect(json['impact'], equals('fast'));
      });
    });
  });
}
