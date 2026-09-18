// WritableCteRule 单测（B6 T12）。
// 正例含 dbx 同款用例（WITH t AS (DELETE ... RETURNING)）+ 嵌套 WITH /
// 子查询内 CTE 递归下钻 + 多可写体计数；反例为零误报硬约束（普通 CTE、
// 非 WITH 语句、AS 别名无括号、字符串/注释内伪特征、未闭合括号等
// 边界逐条锁定）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/writable_cte_rule.dart';

SafetyContext _context({DatabaseType dbType = DatabaseType.mysql}) {
  return SafetyContext(
    connectionId: 'test',
    dbType: dbType,
    database: 'testdb',
    schemaCache: null,
    getRowCount: (_) async => null,
    getColumns: (_) async => null,
  );
}

void main() {
  final rule = WritableCteRule();

  group('WritableCteRule 正例', () {
    test('WITH t AS (DELETE ... RETURNING) → medium finding（dbx 同款）',
        () async {
      final findings = await rule.check(
        'WITH t AS (DELETE FROM logs RETURNING id) SELECT * FROM t',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.medium);
      expect(findings.first.ruleId, 'writable_cte');
      expect(findings.first.title, contains('1 个'));
      expect(findings.first.title, contains('DELETE'));
    });

    test('UPDATE 体 CTE（RETURNING 形态）命中', () async {
      final findings = await rule.check(
        'WITH moved AS (UPDATE users SET archived = 1 RETURNING id) '
        'SELECT * FROM moved',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('UPDATE'));
    });

    test('INSERT 体无 RETURNING（INSERT...SELECT）同样命中', () async {
      final findings = await rule.check(
        'WITH ins AS (INSERT INTO summary SELECT * FROM raw) SELECT * FROM ins',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('INSERT'));
    });

    test('MERGE 体命中（体内含嵌套括号）', () async {
      final findings = await rule.check(
        'WITH m AS (MERGE INTO tgt USING src ON (tgt.id = src.id) '
        'WHEN MATCHED THEN UPDATE SET v = 1) SELECT * FROM m',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('MERGE'));
    });

    test('嵌套 WITH 内的可写 CTE 命中（递归下钻）', () async {
      final findings = await rule.check(
        'WITH o AS (WITH i AS (DELETE FROM logs RETURNING id) '
        'SELECT * FROM i) SELECT * FROM o',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('1 个'));
    });

    test('子查询内的可写 CTE 命中（递归下钻）', () async {
      final findings = await rule.check(
        'WITH a AS (SELECT * FROM (WITH b AS (UPDATE t SET x=1 RETURNING id) '
        'SELECT * FROM b) s) SELECT * FROM a',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('UPDATE'));
    });

    test('多个可写 CTE → 单 finding 计数', () async {
      final findings = await rule.check(
        'WITH d AS (DELETE FROM logs), u AS (UPDATE t SET x=1) SELECT 1',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('2 个'));
    });

    test('小写 with/as/delete 同样命中', () async {
      final findings = await rule.check(
        'with t as (delete from logs) select * from t',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('引擎无关语义：PostgreSQL 同样上报', () async {
      final findings = await rule.check(
        'WITH t AS (DELETE FROM logs RETURNING id) SELECT * FROM t',
        _context(dbType: DatabaseType.postgresql),
      );
      expect(findings.length, 1);
    });
  });

  group('WritableCteRule 反例（零误报）', () {
    test('普通 CTE（SELECT 体）不上报', () async {
      final findings = await rule.check(
        'WITH t AS (SELECT id FROM users) SELECT * FROM t',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('WITH RECURSIVE 普通 CTE 不上报', () async {
      final findings = await rule.check(
        'WITH RECURSIVE c AS (SELECT 1 AS n UNION ALL SELECT n+1 FROM c '
        'WHERE n < 10) SELECT * FROM c',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('非 WITH 语句不上报', () async {
      expect(
        await rule.check('SELECT * FROM t WHERE x = 1', _context()),
        isEmpty,
      );
      expect(await rule.check('DELETE FROM logs', _context()), isEmpty);
      expect(
        await rule.check('UPDATE t SET x=1 WHERE id=1', _context()),
        isEmpty,
      );
    });

    test('AS 别名后不跟括号不触发（COUNT(*) AS c）', () async {
      final findings = await rule.check(
        'WITH agg AS (SELECT COUNT(*) AS c FROM logs) SELECT c FROM agg',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('CAST(x AS SIGNED) 类不触发', () async {
      final findings = await rule.check(
        'WITH t AS (SELECT CAST(x AS SIGNED) FROM logs) SELECT * FROM t',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('字符串内伪特征清洗后已剥离，不上报', () async {
      final findings = await rule.check(
        "WITH t AS (SELECT * FROM logs WHERE msg = "
        "'WITH u AS (DELETE FROM x) SELECT 1') SELECT * FROM t",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('注释内伪特征已剥离，不上报', () async {
      final findings = await rule.check(
        'WITH t AS (/* DELETE FROM logs */ SELECT 1) SELECT * FROM t',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('未闭合括号不上报（语句本就不合法）', () async {
      final findings = await rule.check(
        'WITH t AS (SELECT 1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('WITH 开头但主语句是写操作、CTE 体可读，不归本规则', () async {
      final findings = await rule.check(
        'WITH t AS (SELECT 1) DELETE FROM logs',
        _context(),
      );
      expect(findings, isEmpty);
    });
  });
}
