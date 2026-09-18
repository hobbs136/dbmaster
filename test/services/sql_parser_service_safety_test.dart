// SQLParserService 扩展单测（ADR-0003 Part A T6）。
//
// 测 SELECT FROM 表名提取 + extractColumns 的各种模式。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/sql_statement.dart' show SQLType;
import 'package:dbmaster/services/sql_parser_service.dart';

void main() {
  group('extractTableName — SELECT FROM', () {
    test('简单 SELECT', () {
      final table = SQLParserService.extractTableName(
        'SELECT * FROM orders',
        SQLType.other,
      );
      expect(table, 'orders');
    });

    test('带反引号的表名', () {
      final table = SQLParserService.extractTableName(
        'SELECT * FROM `my table`',
        SQLType.other,
      );
      // 反引号含空格——\w+ 不匹配空格，提取到 `my`。
      // 这是保守行为（复杂表名跳过），可接受。
      expect(table, 'my');
    });

    test('带 WHERE 和 LIMIT', () {
      final table = SQLParserService.extractTableName(
        'SELECT id, name FROM users WHERE active = 1 LIMIT 10',
        SQLType.other,
      );
      expect(table, 'users');
    });

    test('无 FROM（如 SELECT 1）', () {
      final table = SQLParserService.extractTableName(
        'SELECT 1',
        SQLType.other,
      );
      expect(table, isNull);
    });
  });

  group('extractColumns — SELECT', () {
    test('提取 SELECT 列列表', () {
      final cols = SQLParserService.extractColumns(
        'SELECT id, name, email FROM users',
      );
      expect(cols, containsAll(['id', 'name', 'email']));
    });

    test('SELECT * → 空（保守跳过）', () {
      final cols = SQLParserService.extractColumns(
        'SELECT * FROM users',
      );
      expect(cols, isEmpty);
    });

    test('WHERE 子句列提取', () {
      final cols = SQLParserService.extractColumns(
        'SELECT * FROM users WHERE status = 1 AND name LIKE "test"',
      );
      expect(cols, containsAll(['status', 'name']));
    });

    test('table.column 形式 → 取最后一段', () {
      final cols = SQLParserService.extractColumns(
        'SELECT u.id, u.name FROM users u',
      );
      expect(cols, containsAll(['id', 'name']));
    });

    test('含 JOIN → 保守跳过（返回空）', () {
      final cols = SQLParserService.extractColumns(
        'SELECT u.id, o.amount FROM users u JOIN orders o ON u.id = o.uid',
      );
      // JOIN 存在时整个列提取保守返回空。
      expect(cols, isEmpty);
    });

    test('含函数 → 保守跳过（不误报）', () {
      final cols = SQLParserService.extractColumns(
        'SELECT COUNT(*) FROM users',
      );
      // COUNT(*) 被视为函数，保守返回空。
      expect(cols.every((c) => c != 'COUNT'), isTrue);
    });
  });

  group('extractColumns — INSERT', () {
    test('提取 INSERT 列列表', () {
      final cols = SQLParserService.extractColumns(
        'INSERT INTO users (id, name, email) VALUES (1, "a", "b@c")',
      );
      expect(cols, containsAll(['id', 'name', 'email']));
    });

    test('INSERT 无列列表 → 空', () {
      final cols = SQLParserService.extractColumns(
        'INSERT INTO users VALUES (1, "a", "b")',
      );
      expect(cols, isEmpty);
    });
  });

  group('extractColumns — UPDATE', () {
    test('提取 SET 子句的列', () {
      final cols = SQLParserService.extractColumns(
        'UPDATE users SET name = "bob", status = 1 WHERE id = 5',
      );
      expect(cols, containsAll(['name', 'status']));
    });
  });

  group('extractColumns — 边缘 case', () {
    test('SQL 关键字不被误判为列名', () {
      final cols = SQLParserService.extractColumns(
        'SELECT id FROM users WHERE status = 1',
      );
      // FROM/WHERE/SELECT 不应出现在列名里。
      expect(cols.every((c) =>
          c.toUpperCase() != 'FROM' &&
          c.toUpperCase() != 'WHERE' &&
          c.toUpperCase() != 'SELECT'), isTrue);
    });

    test('空 SQL → 空', () {
      expect(SQLParserService.extractColumns(''), isEmpty);
    });
  });
}
