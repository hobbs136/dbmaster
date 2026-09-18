import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/schema_analyzer/dependency_analyzer.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';

/// Mock query executor that returns predefined results
class _MockQueryExecutor {
  final Map<String, List<Map<String, dynamic>>> _responses = {};

  void setResponse(String sql, List<Map<String, dynamic>> data) {
    _responses[sql] = data;
  }

  Future<List<Map<String, dynamic>>> call(String sql) async {
    // Try exact match first, then partial match
    if (_responses.containsKey(sql)) {
      return _responses[sql]!;
    }
    // Return empty for unknown queries
    return [];
  }
}

void main() {
  group('DependencyAnalyzer', () {
    late _MockQueryExecutor executor;

    setUp(() {
      executor = _MockQueryExecutor();
    });

    group('analyzeTableDependencies', () {
      test('finds view dependencies for MySQL', () async {
        final deps = await DependencyAnalyzer.analyzeTableDependencies(
          tableName: 'users',
          executeQuery: (sql) async {
            if (sql.contains('INFORMATION_SCHEMA.VIEWS') &&
                sql.contains('users')) {
              return [
                {
                  'view_name': 'user_summary',
                  'view_definition': 'SELECT id, name FROM users',
                },
              ];
            }
            return [];
          },
          databaseType: 'mysql',
        );
        expect(deps.any((d) => d.dependentObject == 'user_summary'), true);
      });

      // CHANGE: P0-2 — regression: table `user` must NOT be flagged as
      // referenced by a view that only mentions `users` / `user_log` (the
      // substring LIKE false positive the old query produced).
      test(
        'view dependency is NOT flagged for substring table-name match (user vs users)',
        () async {
          final deps = await DependencyAnalyzer.analyzeTableDependencies(
            tableName: 'user',
            executeQuery: (sql) async {
              if (sql.contains('INFORMATION_SCHEMA.VIEWS')) {
                return [
                  {
                    'view_name': 'v_users',
                    'view_definition': 'SELECT id, name FROM users',
                  },
                  {
                    'view_name': 'v_user',
                    'view_definition': 'SELECT * FROM user WHERE id = 1',
                  },
                  {
                    'view_name': 'v_user_log',
                    'view_definition':
                        'SELECT * FROM user_log WHERE ts > NOW()',
                  },
                ];
              }
              return [];
            },
            databaseType: 'mysql',
          );
          // table `user` must NOT match views referencing `users` or `user_log`
          expect(deps.any((d) => d.dependentObject == 'v_users'), isFalse);
          expect(deps.any((d) => d.dependentObject == 'v_user_log'), isFalse);
          // but MUST match the view actually referencing `user`
          expect(deps.any((d) => d.dependentObject == 'v_user'), isTrue);
        },
      );

      test('finds foreign key dependencies for MySQL', () async {
        final deps = await DependencyAnalyzer.analyzeTableDependencies(
          tableName: 'users',
          executeQuery: (sql) async {
            if (sql.contains('REFERENCED_TABLE_NAME')) {
              return [
                {'table_name': 'orders', 'constraint_name': 'fk_orders_users'},
              ];
            }
            return [];
          },
          databaseType: 'mysql',
        );
        final fkDep = deps.where(
          (d) => d.dependentType == AffectedObjectType.foreignKey,
        );
        expect(fkDep.any((d) => d.dependentObject == 'orders'), true);
      });

      test('finds trigger dependencies for MySQL', () async {
        final deps = await DependencyAnalyzer.analyzeTableDependencies(
          tableName: 'users',
          executeQuery: (sql) async {
            if (sql.contains('INFORMATION_SCHEMA.TRIGGERS')) {
              return [
                {'trigger_name': 'before_insert_users'},
              ];
            }
            return [];
          },
          databaseType: 'mysql',
        );
        final trgDep = deps.where(
          (d) => d.dependentType == AffectedObjectType.trigger,
        );
        expect(
          trgDep.any((d) => d.dependentObject == 'before_insert_users'),
          true,
        );
      });

      test('handles query errors gracefully', () async {
        final deps = await DependencyAnalyzer.analyzeTableDependencies(
          tableName: 'users',
          executeQuery: (_) => throw Exception('Connection lost'),
          databaseType: 'mysql',
        );
        expect(deps, isEmpty);
      });

      test('returns empty for unsupported database types', () async {
        final deps = await DependencyAnalyzer.analyzeTableDependencies(
          tableName: 'users',
          executeQuery: (_) => throw Exception('Should not be called'),
          databaseType: 'mongodb',
        );
        expect(deps, isEmpty);
      });
    });

    group('analyzeColumnDependencies', () {
      test('finds index dependencies for MySQL', () async {
        final deps = await DependencyAnalyzer.analyzeColumnDependencies(
          tableName: 'users',
          columnName: 'email',
          executeQuery: (sql) async {
            if (sql.contains('INFORMATION_SCHEMA.STATISTICS')) {
              return [
                {'index_name': 'idx_email'},
                {'index_name': 'PRIMARY'},
              ];
            }
            return [];
          },
          databaseType: 'mysql',
        );
        final idxDep = deps.where(
          (d) => d.dependentType == AffectedObjectType.index_,
        );
        expect(idxDep.length, 1); // PRIMARY should be filtered
        expect(idxDep.first.dependentObject, 'idx_email');
      });

      test('finds constraint dependencies for MySQL', () async {
        final deps = await DependencyAnalyzer.analyzeColumnDependencies(
          tableName: 'users',
          columnName: 'email',
          executeQuery: (sql) async {
            if (sql.contains('INFORMATION_SCHEMA.TABLE_CONSTRAINTS')) {
              return [
                {'constraint_name': 'uq_email', 'constraint_type': 'UNIQUE'},
              ];
            }
            return [];
          },
          databaseType: 'mysql',
        );
        final constDep = deps.where(
          (d) => d.dependentType == AffectedObjectType.constraint,
        );
        expect(constDep.any((d) => d.dependentObject == 'uq_email'), true);
      });

      test('handles query errors gracefully', () async {
        final deps = await DependencyAnalyzer.analyzeColumnDependencies(
          tableName: 'users',
          columnName: 'email',
          executeQuery: (_) => throw Exception('Timeout'),
          databaseType: 'mysql',
        );
        expect(deps, isEmpty);
      });
    });

    group('SchemaDependency from analysis', () {
      test('has correct relationship descriptions', () async {
        final deps = await DependencyAnalyzer.analyzeTableDependencies(
          tableName: 'products',
          executeQuery: (sql) async {
            if (sql.contains('VIEWS')) {
              return [
                {
                  'view_name': 'product_catalog',
                  'view_definition': 'SELECT * FROM products',
                },
              ];
            }
            return [];
          },
          databaseType: 'mysql',
        );
        final viewDep = deps.firstWhere(
          (d) => d.dependentObject == 'product_catalog',
        );
        expect(viewDep.sourceTable, 'products');
        expect(viewDep.relationship, 'View references table');
      });
    });
  });
}
