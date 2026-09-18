// TautologyPredicateRule 单测（B6 T11）。
// 正例含 dbx 同款用例（WHERE 1=1 / 自比较 id = id / WHERE TRUE）；
// 反例为零误报硬约束（JOIN 条件、BETWEEN、NULL=NULL、字符串比较、
// OR 锚定形态归 SqlInjectionRule 等边界逐条锁定）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/tautology_predicate_rule.dart';

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
  final rule = TautologyPredicateRule();

  group('TautologyPredicateRule 正例', () {
    test('DELETE ... WHERE 1=1 → high finding（dbx 同款）', () async {
      final findings = await rule.check(
        'DELETE FROM users WHERE 1=1',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.high);
      expect(findings.first.ruleId, 'tautology_predicate');
      expect(findings.first.title, contains('1'));
    });

    test('自比较 WHERE id = id → finding（dbx 同款）', () async {
      final findings = await rule.check(
        'SELECT * FROM users WHERE id = id',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('id = id'));
    });

    test('WHERE TRUE → finding', () async {
      final findings = await rule.check(
        'UPDATE logs SET deleted = 1 WHERE TRUE',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('AND 链中段的恒真谓词命中（动态 SQL 惯用形态）', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE status = 1 AND 1=1 AND name = 'x'",
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('1=1'));
    });

    test('同数字变体：2 = 2 / 大小写无关 true = true', () async {
      expect(
        await rule.check('DELETE FROM t WHERE 2 = 2', _context()),
        isNotEmpty,
      );
      expect(
        await rule.check('SELECT 1 FROM t WHERE true = true', _context()),
        isNotEmpty,
      );
    });

    test('反引号标识符自比较', () async {
      final findings = await rule.check(
        'DELETE FROM t WHERE `id` = `id`',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('限定名自比较 t.col = t.col（限定名相同才报）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE t.col = t.col',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('外层括号包裹 (1=1) / ((1=1)) 命中', () async {
      expect(
        await rule.check('SELECT 1 FROM t WHERE (1=1)', _context()),
        isNotEmpty,
      );
      expect(
        await rule.check('SELECT 1 FROM t WHERE ((1=1))', _context()),
        isNotEmpty,
      );
    });

    test('多处恒真 → 单 finding 计数', () async {
      final findings = await rule.check(
        'SELECT 1 FROM t WHERE 1=1 AND id = id',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('2'));
    });

    test('WHERE 后接 ORDER BY 仍命中（子句截取正确）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE 1=1 ORDER BY id',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('恒真是引擎无关语义：PostgreSQL 同样上报', () async {
      final findings = await rule.check(
        'DELETE FROM users WHERE 1=1',
        _context(dbType: DatabaseType.postgresql),
      );
      expect(findings.length, 1);
    });
  });

  group('TautologyPredicateRule 反例（零误报）', () {
    test('JOIN 条件 a.id = b.id（两侧限定名不同）不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM a JOIN b ON a.id = b.id WHERE a.x = 1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('正常谓词与普通列比较不上报', () async {
      expect(
        await rule.check("SELECT * FROM t WHERE id = 5 AND name = 'x'", _context()),
        isEmpty,
      );
      expect(
        await rule.check('SELECT * FROM t WHERE a = b', _context()),
        isEmpty,
      );
    });

    test('BETWEEN 的 AND 拆分碎片不误报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE d BETWEEN 1 AND 5',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('NULL = NULL 结果是 unknown 非恒真，不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE NULL = NULL',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('字符串比较不上报（清洗后不可分辨，归 SqlInjectionRule）', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE 'x' = 'y'",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('不同数字 1 = 2 不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE 1 = 2',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('OR 锚定形态不归本规则（SqlInjectionRule 的检测面）', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE name = 'x' OR 1=1",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('android 内含 and 不是 AND 拆分点', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE android = 1 AND ios = 2',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('NOT TRUE 是否定式，不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE NOT TRUE',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('无 WHERE 子句不上报', () async {
      expect(await rule.check('SELECT 1', _context()), isEmpty);
      expect(await rule.check('UPDATE t SET a = 1', _context()), isEmpty);
    });

    test('HAVING 1=1 不在 v1 检测面（仅 WHERE）', () async {
      final findings = await rule.check(
        'SELECT COUNT(*) AS c FROM t HAVING 1=1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('子查询内 WHERE 1=1 不在 v1 检测面（仅顶层拆分产物）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE x IN (SELECT id FROM u WHERE 1=1)',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('CASE WHEN 内的 AND 不在顶层拆分产物中误报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE CASE WHEN x AND y THEN 1 ELSE 0 END = 1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('未闭合括号不剥、不误报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE (1=1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('比较符形态（<=、!=、<>）不走相等判定', () async {
      expect(
        await rule.check('SELECT * FROM t WHERE a <= 5', _context()),
        isEmpty,
      );
      expect(
        await rule.check('SELECT * FROM t WHERE a != b', _context()),
        isEmpty,
      );
    });
  });
}
