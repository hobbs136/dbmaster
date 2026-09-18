// ComplementaryOrRule 单测（B6 T12）。
// 正例含 dbx 同款用例（IS NULL 互补 / x=1 OR x<>1 / 单值 IN 互补）；
// 反例为零误报硬约束（OR 锚定 1=1 归 SqlInjectionRule、同列不同值、
// 多值 IN、嵌套括号形态、NULL 作值等边界逐条锁定）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/complementary_or_rule.dart';

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
  final rule = ComplementaryOrRule();

  group('ComplementaryOrRule 正例', () {
    test('x IS NULL OR x IS NOT NULL → high finding（dbx 同款）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE x IS NULL OR x IS NOT NULL',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.high);
      expect(findings.first.ruleId, 'complementary_or');
      expect(findings.first.title, contains('x IS NULL OR x IS NOT NULL'));
    });

    test('DELETE ... WHERE x=1 OR x<>1 → finding（dbx 同款）', () async {
      final findings = await rule.check(
        'DELETE FROM logs WHERE x=1 OR x<>1',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('x=1 OR x<>1'));
    });

    test('!= 形态 x=1 OR x!=1 同样命中', () async {
      final findings = await rule.check(
        'SELECT 1 FROM t WHERE x=1 OR x!=1',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('单值 IN 互补 x IN (1) OR x NOT IN (1) 命中', () async {
      final findings = await rule.check(
        'SELECT 1 FROM t WHERE x IN (1) OR x NOT IN (1)',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('不等式互补 x<5 OR x>=5 / x>5 OR x<=5 命中', () async {
      expect(
        await rule.check('SELECT 1 FROM t WHERE x<5 OR x>=5', _context()),
        isNotEmpty,
      );
      expect(
        await rule.check('SELECT 1 FROM t WHERE x>5 OR x<=5', _context()),
        isNotEmpty,
      );
    });

    test('数值等价 x=1 OR x<>1.0 命中（1 与 1.0 数值相同）', () async {
      final findings = await rule.check(
        'SELECT 1 FROM t WHERE x=1 OR x<>1.0',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('反引号限定名 t.`flag` IS NULL 互补命中', () async {
      final findings = await rule.check(
        'SELECT 1 FROM t WHERE t.`flag` IS NULL OR t.`flag` IS NOT NULL',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('OR 链混入普通支仍命中（y=2 OR x=1 OR x<>1 → 1 处）', () async {
      final findings = await rule.check(
        'SELECT 1 FROM t WHERE y=2 OR x=1 OR x<>1',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('1 处'));
    });

    test('两对互补 → 单 finding 计数 2', () async {
      final findings = await rule.check(
        'SELECT 1 FROM t WHERE x=1 OR x<>1 OR y IS NULL OR y IS NOT NULL',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('2 处'));
    });

    test('括号包裹支 (x = 1) OR (x <> 1) 命中', () async {
      final findings = await rule.check(
        'SELECT 1 FROM t WHERE (x = 1) OR (x <> 1)',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('大小写无关 where X is null or X is not null 命中', () async {
      final findings = await rule.check(
        'select 1 from t where X is null or X is not null',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('WHERE 后接 ORDER BY 仍命中（子句截取正确）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE x=1 OR x<>1 ORDER BY id',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('互补恒真是引擎无关语义：PostgreSQL 同样上报', () async {
      final findings = await rule.check(
        'DELETE FROM users WHERE id IS NULL OR id IS NOT NULL',
        _context(dbType: DatabaseType.postgresql),
      );
      expect(findings.length, 1);
    });
  });

  group('ComplementaryOrRule 反例（零误报）', () {
    test('普通 OR 条件（status=1 OR status=2，同符不同值）不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE status=1 OR status=2',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('OR 锚定 1=1 不是互补对（SqlInjectionRule 检测面）', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE name = 'x' OR 1=1",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('两支列不同（x=1 OR y<>1）不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE x=1 OR y<>1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('AND 混合无顶层 OR 不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE a=1 AND b=2',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('括号内嵌套 OR 支（复杂形态 v1 不报）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE (a=1 OR a<>1) AND b=2',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('多值 IN 互补 v1 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE x IN (1,2) OR x NOT IN (1,2)',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('非互补操作符组合不上报', () async {
      expect(
        await rule.check('SELECT * FROM t WHERE x<5 OR x<=5', _context()),
        isEmpty,
      );
      expect(
        await rule.check('SELECT * FROM t WHERE x=1 OR x>1', _context()),
        isEmpty,
      );
    });

    test('值不匹配（x=1 OR x<>2）不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE x=1 OR x<>2',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('NULL 作值两支皆 unknown 非恒真，不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE x=NULL OR x<>NULL',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('JOIN ON 里的 OR 不在 WHERE 检测面', () async {
      final findings = await rule.check(
        'SELECT * FROM a JOIN b ON a.id = 1 OR b.id <> 1 WHERE a.x = 5',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('字符串内伪特征清洗后已剥离，不上报', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE msg = 'x IS NULL OR x IS NOT NULL'",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('password 内含 or 不是 OR 拆分点', () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE password = 'a' OR username = 'b'",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('无 WHERE 子句不上报', () async {
      expect(await rule.check('SELECT 1', _context()), isEmpty);
      expect(await rule.check('UPDATE t SET a = 1', _context()), isEmpty);
    });

    test('HAVING 里的互补 OR 不在 v1 检测面（仅 WHERE）', () async {
      final findings = await rule.check(
        'SELECT COUNT(*) AS c FROM t GROUP BY g HAVING x IS NULL OR x IS NOT NULL',
        _context(),
      );
      expect(findings, isEmpty);
    });
  });
}
