import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/query_optimizer/execution_plan.dart';

void main() {
  group('ScanType', () {
    test('has correct number of values', () {
      expect(ScanType.values.length, 14);
    });

    test('all have code, displayName, description', () {
      for (final t in ScanType.values) {
        expect(t.code, isNotEmpty);
        expect(t.displayName, isNotEmpty);
        expect(t.description, isNotEmpty);
      }
    });

    test('fromCode returns correct type', () {
      expect(ScanType.fromCode('ALL'), ScanType.fullTable);
      expect(ScanType.fromCode('range'), ScanType.range);
      expect(ScanType.fromCode('ref'), ScanType.ref);
      expect(ScanType.fromCode('eq_ref'), ScanType.eqRef);
      expect(ScanType.fromCode('const'), ScanType.const_);
      expect(ScanType.fromCode(null), ScanType.unknown);
      expect(ScanType.fromCode('nonexistent'), ScanType.unknown);
    });

    test('isEfficient identifies efficient scan types', () {
      expect(ScanType.const_.isEfficient, true);
      expect(ScanType.eqRef.isEfficient, true);
      expect(ScanType.system.isEfficient, true);
      expect(ScanType.range.isEfficient, false);
    });

    test('isInefficient identifies inefficient scan types', () {
      expect(ScanType.fullTable.isInefficient, true);
      expect(ScanType.fullIndex.isInefficient, true);
      expect(ScanType.seqScan.isInefficient, true);
      expect(ScanType.range.isInefficient, false);
    });
  });

  group('PlanStep', () {
    test('fields can be set', () {
      final step = PlanStep(
        id: 1,
        selectType: 'SIMPLE',
        table: 'users',
        scanType: ScanType.range,
        possibleKeys: 'idx_age',
        key: 'idx_age',
        keyLen: '5',
        ref: 'const',
        estimatedRows: 100,
        cost: 10.5,
        extra: 'Using where',
      );
      expect(step.id, 1);
      expect(step.table, 'users');
      expect(step.scanType, ScanType.range);
      expect(step.estimatedRows, 100);
      expect(step.cost, closeTo(10.5, 0.01));
    });

    test('toJson produces correct map', () {
      final step = PlanStep(
        id: 1,
        table: 'users',
        scanType: ScanType.range,
        estimatedRows: 100,
        cost: 10.5,
      );
      final json = step.toJson();
      expect(json['id'], 1);
      expect(json['table'], 'users');
      expect(json['scanType'], 'range');
      expect(json['estimatedRows'], 100);
      expect(json['cost'], closeTo(10.5, 0.01));
    });
  });

  group('ExecutionPlan', () {
    final plan = ExecutionPlan(
      databaseType: 'mysql',
      originalQuery: 'SELECT * FROM users WHERE age > 30',
      steps: [
        PlanStep(
          id: 1,
          selectType: 'SIMPLE',
          table: 'users',
          scanType: ScanType.fullTable,
          estimatedRows: 10000,
          cost: 100.0,
          extra: 'Using where; Using filesort',
        ),
        PlanStep(
          id: 2,
          selectType: 'SIMPLE',
          table: 'orders',
          scanType: ScanType.range,
          estimatedRows: 500,
          cost: 20.0,
        ),
      ],
      rawData: {},
      analyzedAt: DateTime(2026, 6, 1, 12, 0),
    );

    test('hasFullTableScan detects full table scan', () {
      expect(plan.hasFullTableScan, true);
    });

    test('totalRows sums estimated rows', () {
      expect(plan.totalRows, 10500);
    });

    test('hasTemporaryTable detects temporary table', () {
      expect(plan.hasTemporaryTable, false);
    });

    test('hasFileSort detects file sort', () {
      expect(plan.hasFileSort, true);
    });

    test('mostExpensiveStep returns highest cost', () {
      final expensive = plan.mostExpensiveStep;
      expect(expensive, isNotNull);
      expect(expensive!.cost, closeTo(100.0, 0.01));
      expect(expensive.table, 'users');
    });

    test('mostExpensiveStep returns null for empty steps', () {
      final emptyPlan = ExecutionPlan(
        databaseType: 'mysql',
        originalQuery: '',
        steps: [],
        rawData: {},
        analyzedAt: DateTime.now(),
      );
      expect(emptyPlan.mostExpensiveStep, isNull);
    });

    test('toJson includes computed properties', () {
      final json = plan.toJson();
      expect(json['databaseType'], 'mysql');
      expect(json['originalQuery'], 'SELECT * FROM users WHERE age > 30');
      expect(json['steps'], isA<List>());
      expect(json['hasFullTableScan'], true);
      expect(json['totalRows'], 10500);
      expect(json['hasTemporaryTable'], false);
      expect(json['hasFileSort'], true);
    });
  });

  group('Bottleneck', () {
    test('fields are correctly set', () {
      final b = Bottleneck(
        type: BottleneckType.fullTableScan,
        description: 'Full table scan detected on users',
        affectedTable: 'users',
        affectedRows: 10000,
        recommendation: 'Add index on age column',
        severity: Severity.high,
      );
      expect(b.type, BottleneckType.fullTableScan);
      expect(b.severity, Severity.high);
    });

    test('toJson produces correct map', () {
      final b = Bottleneck(
        type: BottleneckType.missingIndex,
        description: 'Missing index',
        severity: Severity.medium,
      );
      final json = b.toJson();
      expect(json['type'], 'missingIndex');
      expect(json['severity'], 'medium');
    });
  });

  group('Severity', () {
    test('has 5 values', () {
      expect(Severity.values.length, 5);
    });

    test('level ordering', () {
      expect(Severity.critical.level, greaterThan(Severity.high.level));
      expect(Severity.high.level, greaterThan(Severity.medium.level));
      expect(Severity.medium.level, greaterThan(Severity.low.level));
      expect(Severity.low.level, greaterThan(Severity.info.level));
    });

    test('isCritical', () {
      expect(Severity.critical.isCritical, true);
      expect(Severity.high.isCritical, true);
      expect(Severity.medium.isCritical, false);
    });
  });

  group('IndexRecommendation', () {
    test('toJson produces correct map', () {
      final rec = IndexRecommendation(
        tableName: 'users',
        indexName: 'idx_users_age',
        columns: ['age'],
        reason: 'Frequent filtering by age',
        ddlStatement: 'CREATE INDEX idx_users_age ON users(age)',
        estimatedImprovement: 85.0,
      );
      final json = rec.toJson();
      expect(json['tableName'], 'users');
      expect(json['columns'], ['age']);
      expect(json['estimatedImprovement'], closeTo(85.0, 0.01));
    });
  });

  group('QueryRewrite', () {
    test('toJson produces correct map', () {
      final qr = QueryRewrite(
        originalQuery: 'SELECT * FROM users',
        rewrittenQuery: 'SELECT id, name, email FROM users',
        reason: 'Avoid SELECT *',
        type: RewriteType.selectStarToColumns,
      );
      final json = qr.toJson();
      expect(json['originalQuery'], 'SELECT * FROM users');
      expect(json['type'], 'selectStarToColumns');
    });
  });

  group('PerformanceReport', () {
    final plan = ExecutionPlan(
      databaseType: 'mysql',
      originalQuery: 'SELECT * FROM users',
      steps: [],
      rawData: {},
      analyzedAt: DateTime.now(),
    );
    final report = PerformanceReport(
      executionPlan: plan,
      bottlenecks: [
        Bottleneck(
          type: BottleneckType.fullTableScan,
          description: 'Full table scan',
          severity: Severity.high,
        ),
      ],
      indexRecommendations: [
        IndexRecommendation(
          tableName: 'users',
          indexName: 'idx_age',
          columns: ['age'],
          reason: 'Filter on age',
          estimatedImprovement: 75.0,
        ),
      ],
      queryRewrites: [],
      summary: 'One bottleneck found',
      analysisDuration: const Duration(milliseconds: 250),
    );

    test('highestSeverity returns max severity', () {
      expect(report.highestSeverity, Severity.high);
    });

    test('hasCriticalIssues detects critical bottlenecks', () {
      expect(report.hasCriticalIssues, true);
    });

    test('hasCriticalIssues false with no critical', () {
      final lowReport = PerformanceReport(
        executionPlan: plan,
        bottlenecks: [
          Bottleneck(
            type: BottleneckType.selectStar,
            description: 'd',
            severity: Severity.low,
          ),
        ],
        indexRecommendations: [],
        queryRewrites: [],
        summary: '',
        analysisDuration: Duration.zero,
      );
      expect(lowReport.hasCriticalIssues, false);
    });

    test('highestSeverity returns info when no bottlenecks', () {
      final emptyReport = PerformanceReport(
        executionPlan: plan,
        bottlenecks: [],
        indexRecommendations: [],
        queryRewrites: [],
        summary: '',
        analysisDuration: Duration.zero,
      );
      expect(emptyReport.highestSeverity, Severity.info);
    });

    test('totalEstimatedImprovement sums improvements', () {
      expect(report.totalEstimatedImprovement, closeTo(75.0, 0.01));
    });

    test('totalEstimatedImprovement null when no recommendations', () {
      final noRec = PerformanceReport(
        executionPlan: plan,
        bottlenecks: [],
        indexRecommendations: [],
        queryRewrites: [],
        summary: '',
        analysisDuration: Duration.zero,
      );
      expect(noRec.totalEstimatedImprovement, isNull);
    });

    test('toJson includes computed properties', () {
      final json = report.toJson();
      expect(json['summary'], 'One bottleneck found');
      expect(json['highestSeverity'], 'high');
      expect(json['hasCriticalIssues'], true);
      expect(json['totalEstimatedImprovement'], closeTo(75.0, 0.01));
      expect(json['analysisDurationMs'], 250);
    });
  });
}
