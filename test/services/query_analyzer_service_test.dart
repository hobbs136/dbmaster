import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/query_analyzer_service.dart';

void main() {
  group('QueryAnalyzerService', () {
    late QueryAnalyzerService analyzer;

    setUp(() {
      analyzer = QueryAnalyzerService();
    });

    group('analyzeExecutionPlan', () {
      test('detects full table scan', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'ALL',
            'rows': '10000',
            'Extra': '',
          },
        ]);

        expect(result.usesFullTableScan, isTrue);
        expect(result.usesIndex, isFalse);
        expect(result.warnings, anyElement(contains('全表扫描')));
        expect(result.suggestions, anyElement(contains('索引')));
      });

      test('detects index usage', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'ref',
            'key': 'idx_email',
            'rows': '10',
            'Extra': '',
          },
        ]);

        expect(result.usesIndex, isTrue);
        expect(result.usesFullTableScan, isFalse);
        expect(result.warnings, isEmpty);
      });

      test('detects filesort warning', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'orders',
            'type': 'ALL',
            'rows': '100',
            'Extra': 'Using filesort',
          },
        ]);

        expect(result.warnings, anyElement(contains('filesort')));
        expect(result.suggestions, anyElement(contains('ORDER BY')));
      });

      test('detects temporary table warning', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'logs',
            'type': 'ALL',
            'rows': '100',
            'Extra': 'Using temporary',
          },
        ]);

        expect(result.warnings, anyElement(contains('临时表')));
        expect(result.suggestions, anyElement(contains('临时表')));
      });

      test('detects join buffer warning', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'items',
            'type': 'ALL',
            'rows': '100',
            'Extra': 'Using join buffer',
          },
        ]);

        expect(result.warnings, anyElement(contains('连接缓冲区')));
        expect(result.suggestions, anyElement(contains('连接字段')));
      });

      test('detects full index scan warning', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'index',
            'rows': '1000',
            'Extra': '',
          },
        ]);

        expect(result.warnings, anyElement(contains('全索引扫描')));
      });

      test('detects possible keys not used', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'ALL',
            'possible_keys': 'idx_email,idx_name',
            'key': null,
            'rows': '1000',
            'Extra': '',
          },
        ]);

        expect(result.warnings, anyElement(contains('可用索引但未使用')));
      });

      test('warns when estimated rows exceed threshold', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'index',
            'rows': '50000',
            'Extra': '',
          },
        ]);

        expect(result.warnings, anyElement(contains('大量数据')));
        expect(result.suggestions, anyElement(contains('LIMIT')));
      });

      test('returns empty warnings and suggestions for good plan', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'const',
            'key': 'PRIMARY',
            'rows': '1',
            'Extra': '',
          },
        ]);

        expect(result.warnings, isEmpty);
        expect(result.suggestions, isEmpty);
        expect(result.usesIndex, isTrue);
        expect(result.usesFullTableScan, isFalse);
      });

      test('sums estimated rows across steps', () {
        final result = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'a',
            'type': 'ALL',
            'rows': '100',
            'Extra': '',
          },
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'b',
            'type': 'ALL',
            'rows': '200',
            'Extra': '',
          },
        ]);

        expect(result.estimatedRows, equals(300));
      });
    });

    group('generateAnalysisReport', () {
      test('includes basic info and steps', () {
        final analysis = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'ref',
            'key': 'idx_email',
            'key_len': '100',
            'rows': '10',
            'Extra': '',
          },
        ]);

        final report = analyzer.generateAnalysisReport(analysis);

        expect(report, contains('执行计划分析报告'));
        expect(report, contains('是否使用索引'));
        expect(report, contains('users'));
        expect(report, contains('idx_email'));
        expect(report, contains('扫描行数'));
      });

      test('includes warnings and suggestions sections', () {
        final analysis = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'ALL',
            'rows': '1000',
            'Extra': 'Using filesort',
          },
        ]);

        final report = analyzer.generateAnalysisReport(analysis);

        expect(report, contains('警告'));
        expect(report, contains('优化建议'));
        expect(report, contains('全表扫描'));
      });

      test('shows success message when no issues', () {
        final analysis = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'const',
            'key': 'PRIMARY',
            'rows': '1',
            'Extra': '',
          },
        ]);

        final report = analyzer.generateAnalysisReport(analysis);

        expect(report, contains('看起来不错'));
      });
    });

    group('explainAccessType', () {
      test('describes known access types', () {
        expect(analyzer.explainAccessType('system'), contains('只有一行'));
        expect(analyzer.explainAccessType('const'), contains('一个匹配行'));
        expect(analyzer.explainAccessType('eq_ref'), contains('读取一行'));
        expect(analyzer.explainAccessType('ref'), contains('匹配的行'));
        expect(analyzer.explainAccessType('range'), contains('范围内'));
        expect(analyzer.explainAccessType('index'), contains('全索引扫描'));
        expect(analyzer.explainAccessType('ALL'), contains('全表扫描'));
      });

      test('returns unknown message for unrecognized type', () {
        expect(analyzer.explainAccessType('unknown'), contains('未知类型'));
      });
    });

    group('toJson', () {
      test('serializes analysis result to JSON', () {
        final analysis = analyzer.analyzeExecutionPlan([
          {
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'users',
            'type': 'ALL',
            'rows': '100',
            'Extra': '',
          },
        ]);

        final json = analysis.toJson();

        expect(json['usesIndex'], isFalse);
        expect(json['usesFullTableScan'], isTrue);
        expect(json['estimatedRows'], equals(100));
        expect(json['steps'], isA<List>());
        expect(json['warnings'], isA<List>());
        expect(json['suggestions'], isA<List>());
      });
    });
  });
}
