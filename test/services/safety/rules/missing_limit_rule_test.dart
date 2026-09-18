// MissingLimitRule 单测（ADR-0003 Part A T10）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/models/sql_statement.dart' show SQLType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/missing_limit_rule.dart';

SafetyContext _context({required int? rowCount}) {
  return SafetyContext(
    connectionId: 'test',
    dbType: DatabaseType.mysql,
    database: 'testdb',
    schemaCache: null,
    getRowCount: (_) async => rowCount,
    getColumns: (_) async => null,
  );
}

void main() {
  final rule = MissingLimitRule(threshold: 100000, suggestedLimit: 1000);

  test('SELECT 无 LIMIT + 大表（> 10万）→ medium finding + suggestion', () async {
    final findings = await rule.check(
      'SELECT * FROM orders',
      _context(rowCount: 5000000),
    );
    expect(findings.length, 1);
    expect(findings.first.severity, Severity.medium);
    expect(findings.first.suggestion, isNotNull);
    expect(findings.first.suggestion, contains('LIMIT 1000'));
    expect(findings.first.affectedTable, 'orders');
  });

  test('SELECT 有 LIMIT → 无 finding', () async {
    final findings = await rule.check(
      'SELECT * FROM orders LIMIT 100',
      _context(rowCount: 5000000),
    );
    expect(findings, isEmpty);
  });

  test('小表（< 10万）→ 无 finding', () async {
    final findings = await rule.check(
      'SELECT * FROM small_table',
      _context(rowCount: 50000),
    );
    expect(findings, isEmpty);
  });

  test('行数 null → 跳过', () async {
    final findings = await rule.check(
      'SELECT * FROM unknown',
      _context(rowCount: null),
    );
    expect(findings, isEmpty);
  });

  test('非 SELECT 语句 → 跳过', () async {
    final findings = await rule.check(
      'UPDATE orders SET status = 1',
      _context(rowCount: 5000000),
    );
    expect(findings, isEmpty);
  });

  // 用户报告：大表 SELECT COUNT(*) 也弹 LIMIT 警告——聚合查询恒返回
  // 单行，LIMIT 无意义。且豁免应发生在行数查询之前（省一次往返）。
  group('整查询聚合豁免（isSingleRowAggregate）', () {
    test('SELECT COUNT(*) 大表 → 无 finding', () async {
      var rowCountCalls = 0;
      final ctx = SafetyContext(
        connectionId: 'test',
        dbType: DatabaseType.mysql,
        database: 'testdb',
        schemaCache: null,
        getRowCount: (_) async {
          rowCountCalls++;
          return 5000000;
        },
        getColumns: (_) async => null,
      );
      final findings = await rule.check('SELECT COUNT(*) FROM orders', ctx);
      expect(findings, isEmpty);
      expect(rowCountCalls, 0, reason: '豁免应在 getTableRowCount 之前短路');
    });

    test('SELECT SUM/AVG/MIN/MAX 大表 → 无 finding', () async {
      for (final sql in [
        'SELECT SUM(amount) FROM orders',
        'SELECT AVG(amount) FROM orders',
        'SELECT MIN(id) FROM orders',
        'SELECT MAX(id) FROM orders',
      ]) {
        final findings = await rule.check(sql, _context(rowCount: 5000000));
        expect(findings, isEmpty, reason: sql);
      }
    });

    test('隐式聚合（聚合 + 非聚合列，无 GROUP BY）→ 也只返回一行，豁免', () async {
      final findings = await rule.check(
        'SELECT dept, COUNT(*) FROM emp',
        _context(rowCount: 5000000),
      );
      expect(findings, isEmpty);
    });

    test('GROUP BY 聚合 → 不豁免（返回多行），照常检查', () async {
      final findings = await rule.check(
        'SELECT dept, COUNT(*) FROM emp GROUP BY dept',
        _context(rowCount: 5000000),
      );
      expect(findings.length, 1);
    });
  });

  test('suggestion 处理已有分号', () async {
    final findings = await rule.check(
      'SELECT * FROM orders;',
      _context(rowCount: 5000000),
    );
    expect(findings.length, 1);
    // 建议 SQL 不应以 ; 开头追加 LIMIT。
    expect(findings.first.suggestion, 'SELECT * FROM orders LIMIT 1000');
  });

  test('行数格式化', () async {
    final findings = await rule.check(
      'SELECT * FROM big_table',
      _context(rowCount: 5000000),
    );
    expect(findings.first.title, contains('5,000,000'));
  });
}
