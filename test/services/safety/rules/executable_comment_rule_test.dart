// ExecutableCommentRule 单测（B6 T10）。
// 覆盖正例（版本注释内嵌语句 = dbx 同款用例）+ 反例（普通注释/提示/
// 空内容/未闭合/字符串内伪特征/非 MySQL 协议族，零误报硬约束）。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/rules/executable_comment_rule.dart';

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
  final rule = ExecutableCommentRule();

  group('ExecutableCommentRule 正例（MySQL 协议族）', () {
    test('/*! DROP TABLE */ → high finding', () async {
      final findings = await rule.check(
        '/*! DROP TABLE users */',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.high);
      expect(findings.first.ruleId, 'executable_comment');
    });

    test('带版本前缀 /*!40000 DELETE ... */ → high finding（dbx 同款）', () async {
      final findings = await rule.check(
        'SELECT 1; /*!40000 DELETE FROM logs */',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.severity, Severity.high);
      expect(findings.first.title, contains('1'));
    });

    test('语句中间的可执行注释也命中', () async {
      final findings = await rule.check(
        'SELECT /*! SQL_NO_CACHE */ * FROM t',
        _context(),
      );
      expect(findings.length, 1);
    });

    test('多处可执行注释 → 单 finding 计数', () async {
      final findings = await rule.check(
        '/*! SET @a=1 */ SELECT 1 /*! SET @b=2 */',
        _context(),
      );
      expect(findings.length, 1);
      expect(findings.first.title, contains('2'));
    });

    test('Doris（MySQL 协议族）同样上报', () async {
      final findings = await rule.check(
        '/*!50003 TRUNCATE TABLE t */',
        _context(dbType: DatabaseType.doris),
      );
      expect(findings.length, 1);
    });
  });

  group('ExecutableCommentRule 反例（零误报）', () {
    test('普通块注释不上报', () async {
      final findings = await rule.check(
        '/* DROP TABLE users */ SELECT 1',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('优化器提示 /*+ */ 不上报', () async {
      final findings = await rule.check(
        'SELECT /*+ INDEX(t idx) */ * FROM t',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('空内容与纯版本号不上报', () async {
      expect(
        await rule.check('/*!*/ SELECT 1', _context()),
        isEmpty,
      );
      expect(
        await rule.check('/*!50003*/ SELECT 1', _context()),
        isEmpty,
      );
    });

    test('未闭合的可执行注释不上报（引擎会拒）', () async {
      final findings = await rule.check(
        '/*! DROP TABLE x',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('字符串字面量内的 /*! 是数据，不上报', () async {
      final findings = await rule.check(
        "SELECT '/*! hidden */' FROM t",
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('行注释内的 /*! 是注释文字，不上报', () async {
      expect(
        await rule.check('-- /*! not real */\nSELECT 1', _context()),
        isEmpty,
      );
      expect(
        await rule.check('# /*! not real */\nSELECT 1', _context()),
        isEmpty,
      );
    });

    test('反引号标识符内的伪特征不上报', () async {
      final findings = await rule.check(
        'SELECT `col /*! weird */` FROM t',
        _context(),
      );
      expect(findings, isEmpty);
    });

    test('非 MySQL 协议族不上报（/*! 在其它引擎是普通注释）', () async {
      final sql = '/*! DROP TABLE users */';
      expect(
        await rule.check(sql, _context(dbType: DatabaseType.postgresql)),
        isEmpty,
      );
      expect(
        await rule.check(sql, _context(dbType: DatabaseType.sqlite)),
        isEmpty,
      );
    });
  });
}
