import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/utils/sql_escape_utils.dart';

void main() {
  group('SqlEscapeUtils.escapeIdentifier', () {
    test('默认应使用反引号', () {
      expect(SqlEscapeUtils.escapeIdentifier('users'), '`users`');
    });

    test('应转义内部反引号', () {
      expect(SqlEscapeUtils.escapeIdentifier('a`b'), '`a``b`');
    });

    test('应支持自定义引号字符', () {
      expect(SqlEscapeUtils.escapeIdentifier('users', quote: '"'), '"users"');
    });

    test('应转义自定义引号字符', () {
      expect(SqlEscapeUtils.escapeIdentifier('a"b', quote: '"'), '"a""b"');
    });
  });

  group('SqlEscapeUtils.escapeString', () {
    test('应加单引号', () {
      expect(SqlEscapeUtils.escapeString('hello'), "'hello'");
    });

    test('应转义单引号', () {
      expect(SqlEscapeUtils.escapeString("it's"), "'it''s'");
    });

    test('空字符串应返回两个单引号', () {
      expect(SqlEscapeUtils.escapeString(''), "''");
    });
  });

  group('SqlEscapeUtils.escapeMySqlIdentifier', () {
    test('应使用反引号', () {
      expect(SqlEscapeUtils.escapeMySqlIdentifier('users'), '`users`');
    });
  });

  group('SqlEscapeUtils.escapePgIdentifier', () {
    test('应使用双引号', () {
      expect(SqlEscapeUtils.escapePgIdentifier('users'), '"users"');
    });
  });

  group('SqlEscapeUtils.escapePgQualifiedIdentifier', () {
    test('单段名字等价于 escapePgIdentifier', () {
      expect(SqlEscapeUtils.escapePgQualifiedIdentifier('users'), '"users"');
    });

    test('应按点拆分 schema.table 并逐段转义', () {
      expect(
        SqlEscapeUtils.escapePgQualifiedIdentifier('public.users'),
        '"public"."users"',
      );
    });

    test('应支持三段名 schema.table... 仅按点逐段转义', () {
      expect(
        SqlEscapeUtils.escapePgQualifiedIdentifier('a.b.c'),
        '"a"."b"."c"',
      );
    });

    test('应转义每段内部的双引号', () {
      expect(
        SqlEscapeUtils.escapePgQualifiedIdentifier('a"b.c"d'),
        '"a""b"."c""d"',
      );
    });
  });

  group('SqlEscapeUtils.escapeSqlServerIdentifier', () {
    test('应使用方括号', () {
      expect(SqlEscapeUtils.escapeSqlServerIdentifier('users'), '[users]');
    });

    test('应转义内部方括号', () {
      expect(SqlEscapeUtils.escapeSqlServerIdentifier('a]b'), '[a]]b]');
    });
  });

  // spec 040 T006 — QuickSearch 表名按库类型正确引用（修写死反引号 bug）
  group('SqlEscapeUtils.escapeIdentifierForType', () {
    test('MySQL/Doris/TDengine/MongoDB/Redis 应使用反引号', () {
      expect(
        SqlEscapeUtils.escapeIdentifierForType('users', DatabaseType.mysql),
        '`users`',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('users', DatabaseType.doris),
        '`users`',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('users', DatabaseType.tdengine),
        '`users`',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('users', DatabaseType.mongodb),
        '`users`',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('users', DatabaseType.redis),
        '`users`',
      );
    });

    test('PostgreSQL/SQLite 应使用双引号', () {
      expect(
        SqlEscapeUtils.escapeIdentifierForType('users', DatabaseType.postgresql),
        '"users"',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('users', DatabaseType.sqlite),
        '"users"',
      );
    });

    test('SQL Server 应使用方括号', () {
      expect(
        SqlEscapeUtils.escapeIdentifierForType('users', DatabaseType.sqlserver),
        '[users]',
      );
    });

    test('应按各类型规则转义内部特殊字符', () {
      expect(
        SqlEscapeUtils.escapeIdentifierForType('a`b', DatabaseType.mysql),
        '`a``b`',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('a"b', DatabaseType.postgresql),
        '"a""b"',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('a]b', DatabaseType.sqlserver),
        '[a]]b]',
      );
    });

    test('保留字 order 在各类型下应被安全引用', () {
      expect(
        SqlEscapeUtils.escapeIdentifierForType('order', DatabaseType.mysql),
        '`order`',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('order', DatabaseType.postgresql),
        '"order"',
      );
      expect(
        SqlEscapeUtils.escapeIdentifierForType('order', DatabaseType.sqlserver),
        '[order]',
      );
    });
  });
}
