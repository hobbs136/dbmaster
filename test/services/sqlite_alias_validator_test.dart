// SPDX-License-Identifier: Apache-2.0
//
// spec 050：SQLite ATTACH alias 校验器单测。
//
// alias 是 ATTACH 路径唯一的注入面（SQLite 标识符不能参数化），
// 校验器覆盖：合法标识符、非法字符、内置库名、保留字、重复、大小写不敏感。
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sqlite_alias_validator.dart';

void main() {
  group('SqliteAliasValidator', () {
    group('合法 alias', () {
      test('简单字母名通过', () {
        expect(SqliteAliasValidator.validate('archive'), isNull);
      });

      test('字母+数字组合通过', () {
        expect(SqliteAliasValidator.validate('db1'), isNull);
        expect(SqliteAliasValidator.validate('archive2'), isNull);
      });

      test('下划线开头/包含通过', () {
        expect(SqliteAliasValidator.validate('_temp'), isNull);
        expect(SqliteAliasValidator.validate('my_db'), isNull);
        expect(SqliteAliasValidator.validate('_'), isNull);
      });

      test('长名通过', () {
        expect(SqliteAliasValidator.validate('aVeryLongAliasName123'), isNull);
      });
    });

    group('非法字符（sqliteAttachAliasInvalid）', () {
      test('空串拒绝', () {
        expect(
          SqliteAliasValidator.validate(''),
          equals('sqliteAttachAliasInvalid'),
        );
      });

      test('数字开头拒绝', () {
        expect(
          SqliteAliasValidator.validate('1db'),
          equals('sqliteAttachAliasInvalid'),
        );
        expect(
          SqliteAliasValidator.validate('2archive'),
          equals('sqliteAttachAliasInvalid'),
        );
      });

      test('含连字符拒绝', () {
        expect(
          SqliteAliasValidator.validate('a-b'),
          equals('sqliteAttachAliasInvalid'),
        );
      });

      test('含空格拒绝', () {
        expect(
          SqliteAliasValidator.validate('a b'),
          equals('sqliteAttachAliasInvalid'),
        );
      });

      test('含点拒绝', () {
        expect(
          SqliteAliasValidator.validate('a.b'),
          equals('sqliteAttachAliasInvalid'),
        );
      });

      test('含特殊符号拒绝', () {
        expect(
          SqliteAliasValidator.validate('a\$b'),
          equals('sqliteAttachAliasInvalid'),
        );
        expect(
          SqliteAliasValidator.validate("a'b"),
          equals('sqliteAttachAliasInvalid'),
        );
        expect(
          SqliteAliasValidator.validate('a;b'),
          equals('sqliteAttachAliasInvalid'),
        );
        expect(
          SqliteAliasValidator.validate('a"b'),
          equals('sqliteAttachAliasInvalid'),
        );
      });

      test('注入尝试拒绝', () {
        // 尝试用 alias 注入额外 SQL
        expect(
          SqliteAliasValidator.validate("a'); DROP TABLE--"),
          equals('sqliteAttachAliasInvalid'),
        );
        expect(
          SqliteAliasValidator.validate('a; DETACH'),
          equals('sqliteAttachAliasInvalid'),
        );
      });
    });

    group('内置库名（sqliteAttachAliasReserved）', () {
      test('main 拒绝', () {
        expect(
          SqliteAliasValidator.validate('main'),
          equals('sqliteAttachAliasReserved'),
        );
      });

      test('temp 拒绝', () {
        expect(
          SqliteAliasValidator.validate('temp'),
          equals('sqliteAttachAliasReserved'),
        );
      });

      test('大小写不敏感：MAIN/Temp 拒绝', () {
        expect(
          SqliteAliasValidator.validate('MAIN'),
          equals('sqliteAttachAliasReserved'),
        );
        expect(
          SqliteAliasValidator.validate('Temp'),
          equals('sqliteAttachAliasReserved'),
        );
        expect(
          SqliteAliasValidator.validate('MAIN'),
          isNot(equals('sqliteAttachAliasInvalid')),
        );
      });
    });

    group('保留字（sqliteAttachAliasKeyword）', () {
      test('DDL 关键字拒绝', () {
        expect(
          SqliteAliasValidator.validate('table'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('index'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('view'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('trigger'),
          equals('sqliteAttachAliasKeyword'),
        );
      });

      test('DML 关键字拒绝', () {
        expect(
          SqliteAliasValidator.validate('select'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('insert'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('update'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('delete'),
          equals('sqliteAttachAliasKeyword'),
        );
      });

      test('ATTACH/DETACH 自身关键字拒绝', () {
        expect(
          SqliteAliasValidator.validate('attach'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('detach'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('database'),
          equals('sqliteAttachAliasKeyword'),
        );
      });

      test('大小写不敏感：TABLE/Select 拒绝', () {
        expect(
          SqliteAliasValidator.validate('TABLE'),
          equals('sqliteAttachAliasKeyword'),
        );
        expect(
          SqliteAliasValidator.validate('Select'),
          equals('sqliteAttachAliasKeyword'),
        );
      });
    });

    group('重复（sqliteAttachAliasDuplicate）', () {
      test('与 existing 列表重名拒绝', () {
        expect(
          SqliteAliasValidator.validate('archive', existing: ['main', 'archive']),
          equals('sqliteAttachAliasDuplicate'),
        );
      });

      test('大小写不敏感重名拒绝', () {
        expect(
          SqliteAliasValidator.validate(
            'ARCHIVE',
            existing: ['main', 'archive'],
          ),
          equals('sqliteAttachAliasDuplicate'),
        );
      });

      test('不重名通过', () {
        expect(
          SqliteAliasValidator.validate('newdb', existing: ['main', 'archive']),
          isNull,
        );
      });

      test('existing 含保留字也不影响校验顺序——保留字优先', () {
        // 'table' 是保留字，即使不在 existing 列表，也应返回 keyword 而非 duplicate
        expect(
          SqliteAliasValidator.validate('table', existing: ['table']),
          equals('sqliteAttachAliasKeyword'),
        );
      });
    });

    group('校验顺序', () {
      test('非法字符优先于保留字（如 "ta ble"）', () {
        expect(
          SqliteAliasValidator.validate('ta ble'),
          equals('sqliteAttachAliasInvalid'),
        );
      });

      test('reserved 优先于 keyword（main 既是内置也曾在关键字列表）', () {
        // main 不在 _keywords 列表，但即使假设在，reserved 应优先
        expect(
          SqliteAliasValidator.validate('main'),
          equals('sqliteAttachAliasReserved'),
        );
      });
    });
  });
}
