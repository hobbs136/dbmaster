// ExplainFullScanRule 单测（第三阶段 T4）。
// mock getExplainPlan 返回构造的 MySQL EXPLAIN 行数据。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/models/sql_statement.dart' show SQLType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/explain_full_scan_rule.dart';

/// 构造测试 context。
/// [explainData] 非 null → getExplainPlan 返回该数据（async）。
/// [explainData] = null 且 [unsupported] = false → getExplainPlan 返回 null Future（EXPLAIN 无结果）。
/// [unsupported] = true → getExplainPlan 字段本身为 null（不支持 EXPLAIN）。
/// [throwOnExplain] 非 null → getExplainPlan 抛异常。
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
            // data null → 返回 null（Future<List<Map>>? 的 null 分支：无法获取计划）。
            if (data == null) return null;
            return Future.value(data);
          },
  );
}

/// MySQL EXPLAIN 全表扫描行（type=ALL, 大行数）。
List<Map<String, dynamic>> _mysqlFullScan({required int rows, String table = 'big_table'}) => [
      {
        'id': 1,
        'select_type': 'SIMPLE',
        'table': table,
        'type': 'ALL',
        'possible_keys': null,
        'key': null,
        'rows': rows,
        'Extra': 'Using where',
      },
    ];

/// MySQL EXPLAIN 走索引行（type=ref）。
List<Map<String, dynamic>> _mysqlIndexScan({required int rows, String table = 't'}) => [
      {
        'id': 1,
        'select_type': 'SIMPLE',
        'table': table,
        'type': 'ref',
        'possible_keys': 'idx',
        'key': 'idx',
        'rows': rows,
        'Extra': null,
      },
    ];

void main() {
  final rule = ExplainFullScanRule(rowThreshold: 10000);

  group('ExplainFullScanRule 正例', () {
    test('EXPLAIN 显示全表扫 + 大行数 → medium finding', () async {
      final findings = await rule.check(
        'SELECT * FROM big_table WHERE non_indexed = 1',
        _context(explainData: () => _mysqlFullScan(rows: 50000)),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.medium);
      expect(findings.first.ruleId, 'explain_full_scan');
      expect(findings.first.affectedTable, 'big_table');
      expect(findings.first.title, contains('50,000'));
    });

    test('finding 描述含扫描类型', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE a = 1',
        _context(explainData: () => _mysqlFullScan(rows: 20000)),
      );
      expect(findings.length, 1);
      expect(findings.first.description, contains('Full Table Scan'));
    });
  });

  group('ExplainFullScanRule 反例（零误报）', () {
    test('走索引（type=ref）→ 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE indexed_col = 1',
        _context(explainData: () => _mysqlIndexScan(rows: 50000)),
      );
      expect(findings, isEmpty);
    });

    test('小表全表扫（行数 < 阈值）→ 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM small_table',
        _context(explainData: () => _mysqlFullScan(rows: 100)),
      );
      expect(findings, isEmpty);
    });

    test('getExplainPlan 字段为 null（不支持 EXPLAIN）→ 跳过', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(unsupported: true),
      );
      expect(findings, isEmpty);
    });

    test('非 SELECT（UPDATE）→ 跳过', () async {
      final findings = await rule.check(
        'UPDATE t SET a = 1',
        _context(explainData: () => _mysqlFullScan(rows: 50000)),
      );
      expect(findings, isEmpty);
    });

    test('EXPLAIN 返回 null → 跳过', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(), // 无 explainData → 返回 null Future
      );
      expect(findings, isEmpty);
    });

    test('EXPLAIN 返回空列表 → 跳过', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(explainData: () => []),
      );
      expect(findings, isEmpty);
    });

    test('EXPLAIN 抛异常 → 静默跳过', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(
          explainData: () => [],
          throwOnExplain: Exception('permission denied'),
        ),
      );
      expect(findings, isEmpty);
    });
  });

  group('ExplainFullScanRule 阈值边界', () {
    test('行数 = 阈值 → 报（>= 阈值）', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(explainData: () => _mysqlFullScan(rows: 10000)),
      );
      expect(findings.length, 1);
    });

    test('行数 = 阈值 - 1 → 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(explainData: () => _mysqlFullScan(rows: 9999)),
      );
      expect(findings, isEmpty);
    });

    test('自定义阈值', () async {
      final customRule = ExplainFullScanRule(rowThreshold: 100);
      final findings = await customRule.check(
        'SELECT * FROM t',
        _context(explainData: () => _mysqlFullScan(rows: 200)),
      );
      expect(findings.length, 1);
    });
  });

  group('ExplainFullScanRule WITH 查询', () {
    test('WITH (CTE) 查询 → 触发 EXPLAIN', () async {
      final findings = await rule.check(
        'WITH cte AS (SELECT * FROM big_table) SELECT * FROM cte',
        _context(explainData: () => _mysqlFullScan(rows: 50000)),
      );
      expect(findings.length, 1);
    });
  });

  // 用户报告衍生：COUNT 类统计查询的全表扫是统计语义本身，不是优化缺陷。
  // 无 WHERE → 豁免（且不付 EXPLAIN 往返）；带 WHERE → 维持检查。
  group('ExplainFullScanRule 整查询聚合豁免', () {
    test('SELECT COUNT(*) 无 WHERE → 不报（EXPLAIN 不应被调用）', () async {
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
          return Future.value(_mysqlFullScan(rows: 50000));
        },
      );
      final findings = await rule.check('SELECT COUNT(*) FROM big_table', ctx);
      expect(findings, isEmpty);
      expect(explainCalls, 0, reason: '豁免应在 EXPLAIN 往返之前短路');
    });

    test('SELECT COUNT(*) 带 WHERE → 照常检查（慢扫有诊断价值）', () async {
      final findings = await rule.check(
        'SELECT COUNT(*) FROM big_table WHERE non_indexed = 1',
        _context(explainData: () => _mysqlFullScan(rows: 50000)),
      );
      expect(findings.length, 1);
    });

    test('GROUP BY 聚合 → 不豁免，照常检查', () async {
      final findings = await rule.check(
        'SELECT dept, COUNT(*) FROM big_table GROUP BY dept',
        _context(explainData: () => _mysqlFullScan(rows: 50000)),
      );
      expect(findings.length, 1);
    });
  });

  group('ExplainFullScanRule LIMIT 截断（回归：大表 + 小 LIMIT 不误报）', () {
    test('LIMIT 100 无 ORDER BY → 实际扫描被截断，不报', () async {
      final findings = await rule.check(
        'SELECT * FROM `events` LIMIT 100',
        _context(explainData: () => _mysqlFullScan(rows: 2986232)),
      );
      expect(findings, isEmpty);
    });

    test('LIMIT 100 有 ORDER BY → 无索引仍需全表扫 + filesort，照报', () async {
      final findings = await rule.check(
        'SELECT * FROM `events` ORDER BY created_at LIMIT 100',
        _context(explainData: () => _mysqlFullScan(rows: 2986232)),
      );
      expect(findings.length, 1);
    });

    test('大 LIMIT（有效行数 ≥ 阈值）→ 报，标题显示封顶后的行数', () async {
      final findings = await rule.check(
        'SELECT * FROM big_table LIMIT 50000',
        _context(explainData: () => _mysqlFullScan(rows: 2986232)),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('50,000'));
      expect(findings.first.title, isNot(contains('2,986,232')));
    });
  });

  group('ExplainFullScanRule id', () {
    test('id = explain_full_scan', () {
      expect(rule.id, 'explain_full_scan');
    });
  });
}
