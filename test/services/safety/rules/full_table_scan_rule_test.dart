// FullTableScanRule 单测（第二阶段 T5）。
// 覆盖正例（函数包裹列 + LIKE 通配）+ 反例（正常 SQL 零误报，NF5 硬约束）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/full_table_scan_rule.dart';

SafetyContext _context() {
  return SafetyContext(
    connectionId: 'test',
    dbType: DatabaseType.mysql,
    database: 'testdb',
    schemaCache: null,
    getRowCount: (_) async => null,
    getColumns: (_) async => null,
  );
}

void main() {
  final rule = FullTableScanRule();

  group('FullTableScanRule 函数包裹列', () {
    test('WHERE YEAR(col) → medium finding', () async {
      final findings = await rule.check(
        'SELECT * FROM orders WHERE YEAR(create_time) = 2024',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.medium);
      expect(findings.first.ruleId, 'full_table_scan');
      // 标题用小写函数名（清单是小写）。
      expect(findings.first.title.toLowerCase(), contains('year'));
    });

    test('WHERE LOWER(col) → medium finding', () async {
      final findings = await rule.check(
        "SELECT * FROM users WHERE LOWER(name) = 'abc'",
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.medium);
    });

    test('WHERE SUBSTRING(col,1,2) → medium finding', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE SUBSTRING(code, 1, 2) = 'AB'",
        _context(),
      );
      expect(findings.length, 1);
    });

    test('函数在大小写不敏感下匹配（year/YEAR/Year）', () async {
      for (final sql in [
        'SELECT * FROM t WHERE year(d) = 2024',
        'SELECT * FROM t WHERE Year(d) = 2024',
      ]) {
        final findings = await rule.check(sql, _context());
        expect(findings, isNotEmpty, reason: '应匹配: $sql');
      }
    });

    test('一条语句多个函数 → 只报一次（避免 finding 泛滥）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE YEAR(a) = 2024 AND LOWER(b) = "x"',
        _context(),
      );
      expect(findings.length, 1);
    });
  });

  group('FullTableScanRule LIKE 前缀通配', () {
    test("LIKE '%abc' → medium finding", () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE name LIKE '%abc'",
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.medium);
      expect(findings.first.title, contains('LIKE'));
    });

    test("LIKE '%abc%' → medium finding（双通配）", () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE name LIKE '%abc%'",
        _context(),
      );
      expect(findings.length, 1);
    });

    test('LIKE "abc%" → 不报（后缀通配可用索引）', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE name LIKE 'abc%'",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('双引号 LIKE "%abc" → medium finding', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE name LIKE "%abc"',
        _context(),
      );
      expect(findings.length, 1);
    });
  });

  group('FullTableScanRule 反例（零误报）', () {
    test('正常 WHERE col = 1 → 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE id = 1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('正常多条件 WHERE → 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE a = 1 AND b = 2 OR c = 3',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('无 WHERE 的 SELECT → 不报（由 MISSING_LIMIT 管）', () async {
      final findings = await rule.check(
        'SELECT * FROM t',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('无 WHERE 的 UPDATE → 不报（由 DmlSafetyService 管）', () async {
      final findings = await rule.check(
        'UPDATE t SET a = 1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('SELECT 1（无表）→ 不报', () async {
      final findings = await rule.check('SELECT 1', _context());
      expect(findings, isEmpty);
    });

    test('正常范围查询 WHERE col >= ... AND col < ... → 不报', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE create_time >= '2024-01-01' "
            "AND create_time < '2025-01-01'",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('IN 子查询的 WHERE → 不误报（保守）', () async {
      // IN 列表里的值不是函数包裹列。
      final findings = await rule.check(
        'SELECT * FROM t WHERE id IN (SELECT id FROM u WHERE x = 1)',
        _context(),
      );
      // 子查询里的 WHERE x = 1 不含函数，不应报。
      // 注意：若子查询含函数，当前实现会检测到（保守策略，子查询函数同样有害）。
      expect(findings, isEmpty);
    });
  });

  group('FullTableScanRule 可配置函数清单', () {
    test('自定义空清单 → 不检测函数', () async {
      final customRule = FullTableScanRule(indexBreakingFunctions: {});
      final findings = await customRule.check(
        'SELECT * FROM t WHERE YEAR(d) = 2024',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('自定义新增函数 → 检测', () async {
      final customRule = FullTableScanRule(
        indexBreakingFunctions: {'my_custom_fn'},
      );
      final findings = await customRule.check(
        'SELECT * FROM t WHERE my_custom_fn(col) = 1',
        _context(),
      );
      expect(findings.length, 1);
    });
  });

  group('FullTableScanRule id', () {
    test('id = full_table_scan', () {
      expect(rule.id, 'full_table_scan');
    });
  });
}
