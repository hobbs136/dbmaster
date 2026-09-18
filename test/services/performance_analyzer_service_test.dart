import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/performance_analyzer_service.dart';
import 'package:dbmaster/services/database_service.dart';

class MockDatabaseService extends DatabaseService {
  dynamic _response;
  Exception? _error;

  void setResponse(dynamic response) {
    _response = response;
    _error = null;
  }

  void setError(Exception error) {
    _error = error;
    _response = null;
  }

  @override
  String? get activeConnectionId => 'conn-1';

  @override
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    if (_error != null) throw _error!;
    if (_response is Function) {
      final result = (_response as Function)(sql);
      return result as List<Map<String, dynamic>>;
    }
    return (_response as List<Map<String, dynamic>>?) ?? [];
  }
}

void main() {
  group('PerformanceAnalyzerService', () {
    late PerformanceAnalyzerService service;
    late MockDatabaseService mockDb;

    setUp(() {
      mockDb = MockDatabaseService();
      service = PerformanceAnalyzerService(mockDb);
    });

    group('analyzeSlowQueries', () {
      test(
        'returns empty list when slow_log and performance_schema are unavailable',
        () async {
          mockDb.setError(Exception('no permission'));

          final result = await service.analyzeSlowQueries();

          expect(result, isEmpty);
        },
      );

      test('reads from slow_log when access is available', () async {
        mockDb.setResponse(<Map<String, dynamic>>[]);

        final result = await service.analyzeSlowQueries();
        expect(result, isEmpty);
      });
    });

    group('getIndexUsage', () {
      test('returns index usage mapped from STATISTICS', () async {
        mockDb.setResponse((String sql) {
          if (sql.contains('information_schema.STATISTICS')) {
            return <Map<String, dynamic>>[
              {
                'TABLE_NAME': 'users',
                'INDEX_NAME': 'idx_email',
                'CARDINALITY': '1000',
                'NON_UNIQUE': '1',
                'column_list': 'email',
              },
            ];
          }
          throw Exception('no permission');
        });

        final result = await service.getIndexUsage('users');

        expect(result.length, equals(1));
        expect(result.first.tableName, equals('users'));
        expect(result.first.indexName, equals('idx_email'));
        expect(result.first.columns, equals(['email']));
        expect(result.first.isUnique, isFalse);
      });

      test('returns empty list on error', () async {
        mockDb.setError(Exception('fail'));

        final result = await service.getIndexUsage('users');
        expect(result, isEmpty);
      });
    });

    group('getAllIndexUsage', () {
      test('returns all indexes with zero usage count', () async {
        mockDb.setResponse(<Map<String, dynamic>>[
          {
            'TABLE_NAME': 'orders',
            'INDEX_NAME': 'PRIMARY',
            'CARDINALITY': '5000',
            'NON_UNIQUE': '0',
            'column_list': 'id',
          },
        ]);

        final result = await service.getAllIndexUsage();

        expect(result.length, equals(1));
        expect(result.first.indexName, equals('PRIMARY'));
        expect(result.first.isPrimary, isTrue);
        expect(result.first.usageCount, equals(0));
      });
    });

    group('findUnusedIndexes', () {
      test('returns unused indexes', () async {
        mockDb.setResponse(<Map<String, dynamic>>[
          {
            'TABLE_NAME': 'users',
            'INDEX_NAME': 'idx_unused',
            'CARDINALITY': '10',
            'NON_UNIQUE': '1',
            'column_list': 'name',
            'usage_count': '0',
          },
        ]);

        final result = await service.findUnusedIndexes();

        expect(result.length, equals(1));
        expect(result.first.indexName, equals('idx_unused'));
        expect(result.first.isUsed, isFalse);
      });
    });

    group('suggestIndexes', () {
      test('suggests primary key for large tables without PK', () async {
        mockDb.setResponse((String sql) {
          if (sql.contains('KEY_COLUMN_USAGE')) {
            return <Map<String, dynamic>>[
              {
                'TABLE_NAME': 'big_table',
                'TABLE_ROWS': '5000',
                'ENGINE': 'InnoDB',
              },
            ];
          }
          return <Map<String, dynamic>>[];
        });

        final result = await service.suggestIndexes();

        final pkSuggestion = result.firstWhere((s) => s.title.contains('主键'));
        expect(pkSuggestion.impact, equals('high'));
        expect(pkSuggestion.affectedTables, equals(['big_table']));
      });

      test('suggests more indexes for large tables with few indexes', () async {
        mockDb.setResponse((String sql) {
          if (sql.contains('KEY_COLUMN_USAGE')) {
            return <Map<String, dynamic>>[];
          }
          return <Map<String, dynamic>>[
            {
              'TABLE_NAME': 'huge_table',
              'TABLE_ROWS': '50000',
              'index_count': '1',
            },
          ];
        });

        final result = await service.suggestIndexes();

        final indexSuggestion = result.firstWhere(
          (s) => s.title.contains('索引不足'),
        );
        expect(indexSuggestion.impact, equals('medium'));
      });
    });

    group('getTableStatistics', () {
      test('returns table statistics mapped from TABLES', () async {
        mockDb.setResponse(<Map<String, dynamic>>[
          {
            'TABLE_NAME': 'users',
            'TABLE_ROWS': '1000',
            'DATA_LENGTH': '16384',
            'INDEX_LENGTH': '8192',
            'UPDATE_TIME': '2024-06-01 10:00:00',
            'ENGINE': 'InnoDB',
            'TABLE_COLLATION': 'utf8mb4',
            'AUTO_INCREMENT': '1001',
            'CREATE_TIME': '2024-01-01 10:00:00',
            'AVG_ROW_LENGTH': '16',
          },
        ]);

        final result = await service.getTableStatistics();

        expect(result.length, equals(1));
        expect(result.first.tableName, equals('users'));
        expect(result.first.rowCount, equals(1000));
        expect(result.first.engine, equals('InnoDB'));
      });
    });

    group('getDatabaseSummary', () {
      test('returns summary from aggregate query', () async {
        mockDb.setResponse(<Map<String, dynamic>>[
          {
            'total_rows': '10000',
            'total_data': '1048576',
            'total_index': '524288',
            'table_count': '5',
          },
        ]);

        final result = await service.getDatabaseSummary();

        expect(result.totalRows, equals(10000));
        expect(result.totalDataSize, equals(1048576));
        expect(result.totalIndexSize, equals(524288));
        expect(result.tableCount, equals(5));
      });

      test('returns default summary on error', () async {
        mockDb.setError(Exception('fail'));

        final result = await service.getDatabaseSummary();

        expect(result.totalRows, equals(0));
        expect(result.tableCount, equals(0));
      });
    });

    group('getExecutionPlan', () {
      test('returns execution plan mapped from EXPLAIN', () async {
        mockDb.setResponse(<Map<String, dynamic>>[
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'ALL',
            'rows': '1000',
            'Extra': 'Using where',
          },
        ]);

        final result = await service.getExecutionPlan('SELECT * FROM users');

        expect(result.length, equals(1));
        expect(result.first.table, equals('users'));
        expect(result.first.type, equals('ALL'));
      });

      test('strips semicolons from query', () async {
        String? capturedSql;
        mockDb.setResponse((String sql) {
          capturedSql = sql;
          return <Map<String, dynamic>>[];
        });

        await service.getExecutionPlan('SELECT * FROM users;');

        expect(capturedSql, equals('EXPLAIN SELECT * FROM users'));
      });
    });

    group('generateReport', () {
      test('aggregates all sections into a report', () async {
        mockDb.setResponse((String sql) {
          if (sql.contains('mysql.slow_log') ||
              sql.contains(
                'performance_schema.events_statements_summary_by_digest',
              )) {
            throw Exception('no permission');
          }
          if (sql.contains('SELECT DATABASE()')) {
            return <Map<String, dynamic>>[
              {'db': 'test_db'},
            ];
          }
          return <Map<String, dynamic>>[];
        });

        final report = await service.generateReport();

        expect(report.databaseName, equals('test_db'));
        expect(report.generatedAt, isNotNull);
        expect(report.tableStats, isEmpty);
        expect(report.indexUsage, isEmpty);
        expect(report.slowQueries, isEmpty);
        expect(report.suggestions, isEmpty);
        expect(report.summary, isNotNull);
      });
    });

    group('exportReportToJson', () {
      test('serializes report to JSON', () async {
        mockDb.setResponse((String sql) {
          if (sql.contains('mysql.slow_log') ||
              sql.contains(
                'performance_schema.events_statements_summary_by_digest',
              )) {
            throw Exception('no permission');
          }
          if (sql.contains('SELECT DATABASE()')) {
            return <Map<String, dynamic>>[
              {'db': 'test_db'},
            ];
          }
          return <Map<String, dynamic>>[];
        });

        final report = await service.generateReport();
        final json = service.exportReportToJson(report);

        expect(json, contains('test_db'));
        expect(json, contains('generatedAt'));
        expect(json, contains('totalTables'));
        expect(json, contains('slowQueryCount'));
      });
    });

    group('exportReportToMarkdown', () {
      test('serializes report to Markdown', () async {
        mockDb.setResponse((String sql) {
          if (sql.contains('mysql.slow_log') ||
              sql.contains(
                'performance_schema.events_statements_summary_by_digest',
              )) {
            throw Exception('no permission');
          }
          if (sql.contains('SELECT DATABASE()')) {
            return <Map<String, dynamic>>[
              {'db': 'test_db'},
            ];
          }
          return <Map<String, dynamic>>[];
        });

        final report = await service.generateReport();
        final markdown = service.exportReportToMarkdown(report);

        expect(markdown, contains('# 数据库性能分析报告'));
        expect(markdown, contains('test_db'));
        expect(markdown, contains('## 汇总'));
      });
    });
  });
}
