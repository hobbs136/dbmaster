import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sql_validator_service.dart';

void main() {
  group('SQLValidatorService', () {
    group('validate - 空输入', () {
      test('空字符串应返回空错误列表', () {
        final errors = SQLValidatorService.validate('');
        expect(errors, isEmpty);
      });

      test('空白字符串应返回空错误列表', () {
        final errors = SQLValidatorService.validate('   \n  ');
        expect(errors, isEmpty);
      });
    });

    group('validate - 括号匹配', () {
      test('匹配的括号应无错误', () {
        final errors = SQLValidatorService.validate(
          'SELECT * FROM users WHERE (id = 1)',
        );
        expect(errors.where((e) => e.message.contains('parenthesis')), isEmpty);
      });

      test('未闭合的左括号应报错', () {
        final errors = SQLValidatorService.validate(
          'SELECT * FROM users WHERE (id = 1',
        );
        final parenErrors = errors
            .where((e) => e.message.contains('parenthesis'))
            .toList();
        expect(parenErrors, isNotEmpty);
      });

      test('多余的右括号应报错', () {
        final errors = SQLValidatorService.validate(
          'SELECT * FROM users WHERE id = 1)',
        );
        final parenErrors = errors
            .where((e) => e.message.contains('parenthesis'))
            .toList();
        expect(parenErrors, isNotEmpty);
      });

      test('嵌套括号应正确匹配', () {
        final errors = SQLValidatorService.validate(
          'SELECT * FROM users WHERE ((id = 1) AND (name = "x"))',
        );
        expect(errors.where((e) => e.message.contains('parenthesis')), isEmpty);
      });
    });

    group('validate - 引号匹配', () {
      test('未闭合的单引号应报错', () {
        final errors = SQLValidatorService.validate(
          "SELECT * FROM users WHERE name = 'Alice",
        );
        final quoteErrors = errors
            .where((e) => e.message.contains('quote'))
            .toList();
        expect(quoteErrors, isNotEmpty);
      });

      test('闭合的单引号应无错误', () {
        final errors = SQLValidatorService.validate(
          "SELECT * FROM users WHERE name = 'Alice'",
        );
        final quoteErrors = errors
            .where((e) => e.message.contains('quote'))
            .toList();
        expect(quoteErrors, isEmpty);
      });

      test('转义的单引号不应视为未闭合', () {
        final errors = SQLValidatorService.validate(
          r"SELECT * FROM users WHERE name = 'It\'s ok'",
        );
        final quoteErrors = errors
            .where((e) => e.message.contains('Unclosed single'))
            .toList();
        expect(quoteErrors, isEmpty);
      });
    });

    group('validate - SELECT * 警告', () {
      test('SELECT * 应产生 info 警告', () {
        final errors = SQLValidatorService.validate('SELECT * FROM users');
        final selectAllErrors = errors
            .where((e) => e.message.contains('SELECT *'))
            .toList();
        expect(selectAllErrors, isNotEmpty);
        expect(selectAllErrors.first.severity, ErrorSeverity.info);
      });

      test('SELECT 具体列不应产生警告', () {
        final errors = SQLValidatorService.validate(
          'SELECT id, name FROM users',
        );
        final selectAllErrors = errors
            .where((e) => e.message.contains('SELECT *'))
            .toList();
        expect(selectAllErrors, isEmpty);
      });

      test('大小写不敏感', () {
        final errors = SQLValidatorService.validate('select * from users');
        final selectAllErrors = errors
            .where((e) => e.message.contains('SELECT *'))
            .toList();
        expect(selectAllErrors, isNotEmpty);
      });
    });

    group('validate - 关键字拼写', () {
      test('SELEC 应提示 SELECT', () {
        final errors = SQLValidatorService.validate('SELEC * FROM users');
        final spellingErrors = errors
            .where((e) => e.message.contains('Did you mean'))
            .toList();
        expect(spellingErrors, isNotEmpty);
        expect(spellingErrors.any((e) => e.message.contains('SELECT')), isTrue);
      });

      test('WHER 应提示 WHERE', () {
        final errors = SQLValidatorService.validate(
          'SELECT * FROM users WHER id = 1',
        );
        final spellingErrors = errors
            .where((e) => e.message.contains('Did you mean'))
            .toList();
        expect(spellingErrors, isNotEmpty);
        expect(spellingErrors.any((e) => e.message.contains('WHERE')), isTrue);
      });

      test('正确拼写不应产生警告', () {
        final errors = SQLValidatorService.validate(
          'SELECT * FROM users WHERE id = 1',
        );
        final spellingErrors = errors
            .where((e) => e.message.contains('Did you mean'))
            .toList();
        expect(spellingErrors, isEmpty);
      });
    });

    group('isValid', () {
      test('有效 SQL 应返回 true', () {
        expect(SQLValidatorService.isValid('SELECT id FROM users'), isTrue);
      });

      test('有空格的有效 SQL 应返回 true', () {
        expect(SQLValidatorService.isValid('  SELECT id FROM users  '), isTrue);
      });

      test('有错误的 SQL 应返回 false', () {
        expect(
          SQLValidatorService.isValid('SELECT * FROM users WHERE (id = 1'),
          isFalse,
        );
      });
    });

    group('getErrorsForLine', () {
      test('应按行号过滤错误', () {
        final sql = 'SELECT * FROM users\nWHERE (id = 1';
        final errors = SQLValidatorService.validate(sql);
        expect(errors, isNotEmpty);

        final line1Errors = SQLValidatorService.getErrorsForLine(errors, 1);
        final line2Errors = SQLValidatorService.getErrorsForLine(errors, 2);

        // SELECT * 警告应在第1行
        expect(line1Errors.any((e) => e.message.contains('SELECT *')), isTrue);
        // 括号错误应在第2行
        expect(
          line2Errors.any((e) => e.message.contains('parenthesis')),
          isTrue,
        );
      });

      test('不存在的行应返回空列表', () {
        final sql = 'SELECT * FROM users';
        final errors = SQLValidatorService.validate(sql);
        expect(SQLValidatorService.getErrorsForLine(errors, 99), isEmpty);
      });
    });

    group('SqlValidationError', () {
      test('toString 应包含行号和列号', () {
        const error = SqlValidationError(
          line: 5,
          column: 10,
          message: 'Test error',
          severity: ErrorSeverity.error,
        );
        expect(error.toString(), contains('Line 5'));
        expect(error.toString(), contains('Col 10'));
        expect(error.toString(), contains('Test error'));
      });
    });

    group('ErrorSeverity', () {
      test('应有 3 个级别', () {
        expect(ErrorSeverity.values.length, 3);
        expect(
          ErrorSeverity.values,
          containsAll([
            ErrorSeverity.info,
            ErrorSeverity.warning,
            ErrorSeverity.error,
          ]),
        );
      });
    });
  });
}
