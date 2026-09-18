// FileWriteRule 单测（B6 T11）。
// 正例含 dbx 同款用例（INTO OUTFILE / INTO DUMPFILE / LOAD_FILE）；
// 反例为零误报硬约束（字符串/注释内伪特征、非 MySQL 协议族门控）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/file_write_rule.dart';

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
  final rule = FileWriteRule();

  group('FileWriteRule 正例（MySQL 协议族）', () {
    test("SELECT ... INTO OUTFILE → high finding（dbx 同款）", () async {
      final findings = await rule.check(
        "SELECT * FROM users INTO OUTFILE '/tmp/users.csv'",
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.high);
      expect(findings.first.ruleId, 'file_write');
    });

    test("SELECT ... INTO DUMPFILE → finding（dbx 同款）", () async {
      final findings = await rule.check(
        "SELECT * FROM t INTO DUMPFILE '/tmp/x.bin'",
        _context(),
      );
      expect(findings.length, 1);
    });

    test("LOAD_FILE() → finding（dbx 同款）", () async {
      final findings = await rule.check(
        "SELECT LOAD_FILE('/etc/passwd') AS x",
        _context(),
      );
      expect(findings.length, 1);
    });

    test('大小写无关 + 括号前空白容忍', () async {
      expect(
        await rule.check("select * from t into outfile '/tmp/x'", _context()),
        isNotEmpty,
      );
      expect(
        await rule.check("SELECT LOAD_FILE ('/a')", _context()),
        isNotEmpty,
      );
    });

    test('Doris（MySQL 协议族）同样上报', () async {
      final findings = await rule.check(
        "SELECT * FROM t INTO OUTFILE '/tmp/x'",
        _context(dbType: DatabaseType.doris),
      );
      expect(findings.length, 1);
    });

    test('可执行注释内的载荷仍可见（T10 解包保留的纵深）', () async {
      final findings = await rule.check(
        "SELECT /*! INTO OUTFILE '/tmp/x' */ 1",
        _context(),
      );
      expect(findings.length, 1);
    });

    test('多处命中 → 单 finding 计数', () async {
      final findings = await rule.check(
        "SELECT LOAD_FILE('/a') INTO OUTFILE '/b'",
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('2'));
    });
  });

  group('FileWriteRule 反例（零误报）', () {
    test("字符串字面量内的 INTO OUTFILE 是数据，不上报", () async {
      final findings = await rule.check(
        "SELECT * FROM t WHERE note = 'INTO OUTFILE is dangerous'",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('注释内的伪特征不上报', () async {
      expect(
        await rule.check("-- INTO OUTFILE /tmp/x\nSELECT 1", _context()),
        isEmpty,
      );
      expect(
        await rule.check("/* LOAD_FILE('/x') */ SELECT 1", _context()),
        isEmpty,
      );
    });

    test('普通查询不上报', () async {
      final findings = await rule.check(
        'SELECT * FROM t WHERE id = 1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('非 MySQL 协议族不上报（该语法不可执行，上报即误报）', () async {
      final sql = "SELECT * FROM t INTO OUTFILE '/tmp/x'";
      expect(
        await rule.check(sql, _context(dbType: DatabaseType.postgresql)),
        isEmpty,
      );
      expect(
        await rule.check(sql, _context(dbType: DatabaseType.sqlite)),
        isEmpty,
      );
      expect(
        await rule.check(sql, _context(dbType: DatabaseType.clickhouse)),
        isEmpty,
      );
    });

    test('标识符含子串不误报（intofile 单词无 INTO 词边界）', () async {
      final findings = await rule.check(
        'SELECT * FROM intofile',
        _context(),
      );
      expect(findings, isEmpty);
    });
  });
}
