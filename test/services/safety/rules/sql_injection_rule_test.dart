// SqlInjectionRule 单测（第二阶段 T7）。
// 覆盖正例（永真式 + 注释截断 + hex）+ 反例（正常 SQL 零误报，NF5 硬约束）。
// 注入指控重，宁可漏报不误报。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/sql_injection_rule.dart';

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
  final rule = SqlInjectionRule();

  group('SqlInjectionRule 永真式', () {
    test('OR 1=1 → high finding', () async {
      final findings = await rule.check(
        'SELECT * FROM users WHERE id = 1 OR 1=1',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.high);
      expect(findings.first.ruleId, 'sql_injection');
    });

    test("OR 'x'='x' → high finding", () async {
      final findings = await rule.check(
        "SELECT * FROM users WHERE name = 'a' OR 'x'='x'",
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.high);
    });

    test('OR true → high finding', () async {
      final findings = await rule.check(
        'SELECT * FROM users WHERE id = 1 OR true',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('OR 1（单独数字）→ high finding', () async {
      final findings = await rule.check(
        'SELECT * FROM users WHERE id = 1 OR 1',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('永真式大小写不敏感（or 1=1）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE a = 1 or 1=1',
        _context(),
      );
      expect(findings.length, 1);
    });
  });

  group('SqlInjectionRule 注释截断', () {
    test("'; -- → high finding（引号后行注释）", () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE name = 'a'; -- drop",
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.high);
    });

    test("') # → high finding（括号后 # 注释）", () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE id IN (1) # x",
        _context(),
      );
      expect(findings.length, 1);
    });

    test('/* block comment */ → high finding', () async {
      final findings = await rule.check(
        'SELECT * FROM /* x */ t WHERE 1=1',
        _context(),
      );
      // /* */ 匹配注释截断模式。
      expect(findings.any((f) => f.title.contains('注释截断')), isTrue);
    });
  });

  group('SqlInjectionRule 可疑 hex 编码', () {
    test('0x + 20 位 hex → high finding', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE payload = 0x3c7363726970743e3c2f7363726970743e',
        _context(),
      );
      expect(findings.any((f) => f.title.contains('十六进制')), isTrue);
    });

    test('字符串内的长 hex → 不报（cleaned 剥离）', () async {
      // note 的值是数据，不是注入载荷。cleanForAnalysis 剥掉字符串内容。
      final findings = await rule.check(
        "SELECT * FROM t WHERE note = '0x3c7363726970743e3c2f7363726970743e'",
        _context(),
      );
      expect(findings.where((f) => f.title.contains('十六进制')), isEmpty);
    });
  });

  group('SqlInjectionRule 反例（零误报）', () {
    test('正常不等式 WHERE a = 1 OR b = 2 → 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE a = 1 OR b = 2',
        _context(),
      );
      // OR b = 2 不是永真式（b 不一定等于 2）。
      expect(findings, isEmpty);
    });

    test('正常行注释 -- 查询用户 → 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM users -- 查询用户\nWHERE id = 1',
        _context(),
      );
      // 注释前无引号/分号/括号，不是截断模式。
      expect(findings, isEmpty);
    });

    test('短 hex 0xFF → 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE flag = 0xFF',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('中等 hex 0xFFFF → 不报（< 16 位阈值）', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE flag = 0xFFFF',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('正常 SELECT 1 → 不报', () async {
      final findings = await rule.check('SELECT 1', _context());
      expect(findings, isEmpty);
    });

    test('正常多条件 WHERE → 不报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE a = 1 AND b = 2 OR c > 3',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('正常 INSERT → 不报', () async {
      final findings = await rule.check(
        "INSERT INTO t (a, b) VALUES (1, 'hello')",
        _context(),
      );
      expect(findings, isEmpty);
    });
  });

  group('SqlInjectionRule 可配置阈值', () {
    test('自定义 hex 阈值 = 4 → 短 hex 也报', () async {
      final customRule = SqlInjectionRule(hexLengthThreshold: 4);
      final findings = await customRule.check(
        'SELECT * FROM t WHERE flag = 0xABCD',
        _context(),
      );
      expect(findings.any((f) => f.title.contains('十六进制')), isTrue);
    });
  });

  group('SqlInjectionRule id', () {
    test('id = sql_injection', () {
      expect(rule.id, 'sql_injection');
    });
  });
}
