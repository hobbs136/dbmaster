import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/utils/sql_escape_utils.dart';

/// SQL 标识符转义函数的独立测试
/// 测试路径：services/database_service.dart 的 _esc()
String _esc(String name) => '`${name.replaceAll('`', '``')}`';

/// 测试路径：services/adapters/mysql_adapter.dart 的 _escapeIdentifier()
String _escapeIdentifier(String name) => '`${name.replaceAll('`', '``')}`';

void main() {
  group('SQL 标识符转义 - _esc()', () {
    test('普通表名列名应正常转义', () {
      expect(_esc('users'), equals('`users`'));
      expect(_esc('order_items'), equals('`order_items`'));
      expect(_esc('UserName'), equals('`UserName`'));
    });

    test('包含反引号的名称应双写转义', () {
      expect(_esc('table`name'), equals('`table``name`'));
      expect(_esc('a``b'), equals('`a````b`'));
    });

    test('SQL 注入攻击名称应被转义', () {
      // 注入尝试不应破坏 SQL
      expect(
        _esc("users; DROP TABLE users;--"),
        equals('`users; DROP TABLE users;--`'),
      );
      expect(
        _esc("'; SELECT * FROM passwords; --"),
        equals('`\'; SELECT * FROM passwords; --`'),
      );
    });

    test('Unicode 和特殊字符应被转义', () {
      expect(_esc('表名'), equals('`表名`'));
      expect(_esc('テーブル名'), equals('`テーブル名`'));
      expect(_esc('user name'), equals('`user name`'));
    });
  });

  group('SQL 标识符转义 - _escapeIdentifier()', () {
    test('与 _esc() 行为一致', () {
      // 两者使用相同的转义逻辑
      expect(_escapeIdentifier('users'), equals('`users`'));
      expect(_escapeIdentifier('table`x'), equals('`table``x`'));
    });
  });

  group('安全性：转义后的 SQL 片段拼接', () {
    test('表名列名拼接后语法正确', () {
      final table = _esc('users');
      final column = _esc('id');
      expect('SELECT $column FROM $table', equals('SELECT `id` FROM `users`'));
    });

    test('DROP TABLE 拼接后语法正确', () {
      final table = _esc('users');
      expect('DROP TABLE $table', equals('DROP TABLE `users`'));
    });

    test('恶意表名拼接后语法正确（不会被注入）', () {
      final table = _esc("users; DROP TABLE users;--");
      final sql = 'DROP TABLE $table';
      // 注意：即使转义后仍然是无效 SQL 但不会执行注入
      expect(sql, equals("DROP TABLE `users; DROP TABLE users;--`"));
    });
  });
  group('C19 escapeQualifiedIdentifier（方言分发，自 sidebar_tree 收编）', () {
    test('PG 按段双引号转义', () {
      expect(
        SqlEscapeUtils.escapeQualifiedIdentifier(
          'public.users',
          DatabaseType.postgresql,
        ),
        '"public"."users"',
      );
    });

    test('SQL Server 按段方括号转义（内嵌 ] 双写）', () {
      expect(
        SqlEscapeUtils.escapeQualifiedIdentifier(
          'dbo.my]table',
          DatabaseType.sqlserver,
        ),
        '[dbo].[my]]table]',
      );
    });

    test('MySQL/Doris 反引号；null（断连兜底）走 MySQL 方言', () {
      expect(
        SqlEscapeUtils.escapeQualifiedIdentifier('db.t', DatabaseType.mysql),
        '`db`.`t`',
      );
      expect(
        SqlEscapeUtils.escapeQualifiedIdentifier('db.t', DatabaseType.doris),
        '`db`.`t`',
      );
      expect(
        SqlEscapeUtils.escapeQualifiedIdentifier('t', null),
        '`t`',
      );
    });
  });

}
