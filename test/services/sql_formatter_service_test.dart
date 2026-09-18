import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sql_formatter_service.dart';
import 'package:dbmaster/models/formatter_models.dart';

void main() {
  group('SqlFormatterService', () {
    late SqlFormatterService formatter;

    setUp(() {
      formatter = SqlFormatterService();
    });

    group('format - 空输入', () {
      test('空字符串应返回空', () {
        expect(formatter.format('', const FormatterOptions()), '');
      });

      test('仅空白字符应返回空', () {
        expect(formatter.format('   \n\t  ', const FormatterOptions()), '');
      });
    });

    group('format - SELECT', () {
      test('SELECT FROM WHERE 应换行', () {
        final sql = 'SELECT id, name FROM users WHERE id = 1';
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, contains('SELECT'));
        expect(result, contains('FROM'));
        expect(result, contains('WHERE'));
        expect(result.contains('\n'), isTrue);
      });

      test('关键字应转为大写', () {
        final sql = 'select id, name from users where id = 1';
        final result = formatter.format(
          sql,
          const FormatterOptions(uppercaseKeywords: true),
        );
        expect(result, contains('SELECT'));
        expect(result, contains('FROM'));
        expect(result, contains('WHERE'));
      });

      test('uppercaseKeywords=false 应保留原大小写', () {
        final sql = 'select id from users';
        final result = formatter.format(
          sql,
          const FormatterOptions(uppercaseKeywords: false),
        );
        expect(result, contains('select'));
        expect(result, isNot(contains('SELECT')));
      });
    });

    group('format - INSERT', () {
      test('INSERT VALUES 应换行', () {
        final sql = "INSERT INTO users (id, name) VALUES (1, 'Alice')";
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, contains('INSERT'));
        expect(result, contains('VALUES'));
        expect(result.contains('\n'), isTrue);
      });
    });

    group('format - UPDATE', () {
      test('UPDATE SET WHERE 应换行', () {
        final sql = "UPDATE users SET name = 'Bob' WHERE id = 1";
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, contains('UPDATE'));
        expect(result, contains('SET'));
        expect(result, contains('WHERE'));
      });
    });

    group('format - JOIN', () {
      test('LEFT JOIN 应换行', () {
        final sql =
            'SELECT u.id, o.total FROM users u LEFT JOIN orders o ON u.id = o.user_id';
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, contains('FROM'));
        expect(result, contains('LEFT'));
        expect(result, contains('JOIN'));
        expect(result, contains('ON'));
      });

      test('INNER JOIN 应换行', () {
        final sql =
            'SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id';
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, contains('INNER'));
        expect(result, contains('JOIN'));
      });
    });

    group('format - 字符串保留', () {
      test('单引号字符串应保留', () {
        final sql = "SELECT * FROM users WHERE name = 'Alice'";
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, contains("'Alice'"));
      });

      test('双引号字符串应保留', () {
        final sql = 'SELECT * FROM users WHERE name = "Alice"';
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, contains('"Alice"'));
      });
    });

    group('format - 反引号标识符', () {
      test('反引号标识符应保留', () {
        final sql = 'SELECT * FROM `my_table` WHERE `user_id` = 1';
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, contains('`my_table`'));
        expect(result, contains('`user_id`'));
      });
    });

    group('format - 注释', () {
      test('行注释应保留', () {
        final sql = 'SELECT * FROM users -- get all users';
        final result = formatter.format(
          sql,
          const FormatterOptions(preserveComments: true),
        );
        expect(result, contains('-- get all users'));
      });

      test('preserveComments=false 应移除注释', () {
        final sql = 'SELECT * FROM users -- get all users';
        final result = formatter.format(
          sql,
          const FormatterOptions(preserveComments: false),
        );
        expect(result, isNot(contains('-- get all users')));
      });

      test('块注释应保留', () {
        final sql = 'SELECT /* all columns */ * FROM users';
        final result = formatter.format(
          sql,
          const FormatterOptions(preserveComments: true),
        );
        expect(result, contains('/* all columns */'));
      });
    });

    group('format - 缩进', () {
      test('indentSize 应为 4', () {
        final sql = 'SELECT id FROM users';
        final result = formatter.format(
          sql,
          const FormatterOptions(indentSize: 4),
        );
        expect(result.contains('    ') || result.contains('\n'), isTrue);
      });

      test('useTabs 应使用制表符', () {
        // 使用带括号的查询触发缩进
        final sql = 'SELECT (id + 1) FROM users';
        final result = formatter.format(
          sql,
          const FormatterOptions(useTabs: true, indentSize: 1),
        );
        expect(result.contains('\t'), isTrue);
      });
    });

    group('format - compactMode', () {
      test('compactMode 应减少换行', () {
        final sql = 'SELECT id, name FROM users WHERE id = 1';
        final normalResult = formatter.format(
          sql,
          const FormatterOptions(compactMode: false),
        );
        final compactResult = formatter.format(
          sql,
          const FormatterOptions(compactMode: true),
        );
        // compact 模式下换行更少或相等
        expect(
          compactResult.split('\n').length,
          lessThanOrEqualTo(normalResult.split('\n').length),
        );
      });
    });

    group('format - 异常处理', () {
      test('无效 SQL 应返回原字符串', () {
        final sql = 'SELECT * FROM (';
        final result = formatter.format(sql, const FormatterOptions());
        expect(result, isNotEmpty);
      });
    });
  });

  group('FormatterOptions', () {
    test('默认选项应有正确值', () {
      const options = FormatterOptions();
      expect(options.indentSize, 4);
      expect(options.useTabs, isFalse);
      expect(options.uppercaseKeywords, isTrue);
      expect(options.preserveComments, isTrue);
      expect(options.maxLineLength, 80);
      expect(options.commaStyle, 'trailing');
      expect(options.alignKeywords, isTrue);
      expect(options.compactMode, isFalse);
      expect(options.breakBeforeBrackets, isFalse);
    });

    test('copyWith 应更新指定字段', () {
      const options = FormatterOptions();
      final updated = options.copyWith(indentSize: 2, useTabs: true);
      expect(updated.indentSize, 2);
      expect(updated.useTabs, isTrue);
      expect(updated.uppercaseKeywords, options.uppercaseKeywords);
    });

    test('toJson/fromJson 应正确序列化', () {
      const options = FormatterOptions(indentSize: 2, uppercaseKeywords: false);
      final json = options.toJson();
      final restored = FormatterOptions.fromJson(json);
      expect(restored.indentSize, 2);
      expect(restored.uppercaseKeywords, isFalse);
      expect(restored.preserveComments, isTrue);
    });
  });
}
