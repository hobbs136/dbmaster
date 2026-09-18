// ExplainEstimatedRowsRule 单测（第三阶段 T6）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/explain_estimated_rows_rule.dart';

SafetyContext _context({
  List<Map<String, dynamic>>? Function()? explainData,
  bool unsupported = false,
  Object? throwOnExplain,
}) {
  return SafetyContext(
    connectionId: 'test',
    dbType: DatabaseType.mysql,
    database: 'testdb',
    schemaCache: null,
    getRowCount: (_) async => null,
    getColumns: (_) async => null,
    getExplainPlan: unsupported
        ? null
        : (sql) {
            if (throwOnExplain != null) throw throwOnExplain;
            final data = explainData?.call();
            if (data == null) return null;
            return Future.value(data);
          },
  );
}

/// MySQL EXPLAIN 行（走索引但返回行数可控）。
List<Map<String, dynamic>> _mysqlRows(int rows) => [
      {
        'id': 1,
        'select_type': 'SIMPLE',
        'table': 't',
        'type': 'range',
        'possible_keys': 'idx',
        'key': 'idx',
        'rows': rows,
        'Extra': null,
      },
    ];

void main() {
  final rule = ExplainEstimatedRowsRule(rowThreshold: 100000);

  group('ExplainEstimatedRowsRule 正例', () {
    test('预估 50 万行 → medium finding + LIMIT 建议', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE date > "2020-01-01"',
        _context(explainData: () => _mysqlRows(500000)),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.medium);
      expect(findings.first.ruleId, 'explain_estimated_rows');
      expect(findings.first.title, contains('500,000'));
      expect(findings.first.suggestion, isNotNull);
      expect(findings.first.suggestion, contains('LIMIT 1000'));
    });
  });

  group('ExplainEstimatedRowsRule 反例', () {
    test('预估 < 阈值 → 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(explainData: () => _mysqlRows(50000)),
      );
      expect(findings, isEmpty);
    });

    test('不支持 EXPLAIN → 跳过', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(unsupported: true),
      );
      expect(findings, isEmpty);
    });

    test('非 SELECT → 跳过', () async {
      final findings = await rule.check(
        'UPDATE t SET a = 1',
        _context(explainData: () => _mysqlRows(500000)),
      );
      expect(findings, isEmpty);
    });

    test('EXPLAIN 抛异常 → 静默跳过', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(
          explainData: () => _mysqlRows(500000),
          throwOnExplain: Exception('fail'),
        ),
      );
      expect(findings, isEmpty);
    });
  });

  group('ExplainEstimatedRowsRule suggestion 分号处理', () {
    test('原 SQL 有分号 → 建议去掉再追加 LIMIT', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE x = 1;',
        _context(explainData: () => _mysqlRows(500000)),
      );
      expect(findings.first.suggestion, 'SELECT * FROM t WHERE x = 1 LIMIT 1000');
    });
  });

  group('ExplainEstimatedRowsRule 已有 LIMIT（回归：不产生 LIMIT a LIMIT b）', () {
    test('已有小 LIMIT（min(估值, LIMIT) < 阈值）→ 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM `events` LIMIT 100',
        _context(explainData: () => _mysqlRows(2986232)),
      );
      expect(findings, isEmpty);
    });

    test('MySQL offset 形式 LIMIT 0, 100 → 取 count 判定，不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t LIMIT 0, 100',
        _context(explainData: () => _mysqlRows(500000)),
      );
      expect(findings, isEmpty);
    });

    test('已有大 LIMIT（≥ 阈值）→ 仍报，建议原地替换 LIMIT 值而非追加', () async {
      final findings = await rule.check(
        'SELECT * FROM t LIMIT 500000',
        _context(explainData: () => _mysqlRows(500000)),
      );
      expect(findings.length, 1);
      expect(findings.first.suggestion, 'SELECT * FROM t LIMIT 1000');
      expect(findings.first.suggestion, isNot(contains('LIMIT 500000 LIMIT')));
      expect(findings.first.title, contains('500,000'));
      expect(findings.first.description, contains('已含 LIMIT 500,000'));
    });

    test('已有大 LIMIT + 分号 → 建议去掉分号并替换 LIMIT', () async {
      final findings = await rule.check(
        'SELECT * FROM t LIMIT 500000;',
        _context(explainData: () => _mysqlRows(500000)),
      );
      expect(findings.first.suggestion, 'SELECT * FROM t LIMIT 1000');
    });
  });

  // 用户报告衍生：COUNT 类统计查询恒返回单行，EXPLAIN 扫描估值不代表
  // 返回行数——「预估返回 X 行」对它是误报。豁免应在 EXPLAIN 往返之前。
  group('ExplainEstimatedRowsRule 整查询聚合豁免', () {
    test('SELECT COUNT(*) → 不报（EXPLAIN 不应被调用）', () async {
      var explainCalls = 0;
      final ctx = SafetyContext(
        connectionId: 'test',
        dbType: DatabaseType.mysql,
        database: 'testdb',
        schemaCache: null,
        getRowCount: (_) async => null,
        getColumns: (_) async => null,
        getExplainPlan: (sql) {
          explainCalls++;
          return Future.value(_mysqlRows(500000));
        },
      );
      final findings = await rule.check('SELECT COUNT(*) FROM big_table', ctx);
      expect(findings, isEmpty);
      expect(explainCalls, 0, reason: '豁免应在 EXPLAIN 往返之前短路');
    });

    test('GROUP BY 聚合 → 不豁免，照常检查', () async {
      final findings = await rule.check(
        'SELECT dept, COUNT(*) FROM t GROUP BY dept',
        _context(explainData: () => _mysqlRows(500000)),
      );
      expect(findings.length, 1);
    });
  });

  group('ExplainEstimatedRowsRule id', () {
    test('id = explain_estimated_rows', () {
      expect(rule.id, 'explain_estimated_rows');
    });
  });
}
