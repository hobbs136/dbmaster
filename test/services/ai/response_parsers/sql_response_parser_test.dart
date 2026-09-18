import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/response_parsers/sql_response_parser.dart';

void main() {
  group('SqlResponseParser', () {
    late SqlResponseParser parser;

    setUp(() {
      parser = SqlResponseParser(locale: 'zh');
    });

    group('extractExecutableStatements', () {
      test('extracts SQL from sql tags', () {
        const response = '<sql>SELECT * FROM users WHERE id = 1</sql>';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT * FROM users WHERE id = 1'));
      });

      test('extracts multiple SQL statements from sql tags', () {
        const response = '''
<sql>SELECT * FROM users;</sql>
<sql>INSERT INTO logs (msg) VALUES ('test');</sql>
''';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(2));
        expect(statements[0], equals('SELECT * FROM users'));
        expect(statements[1], equals("INSERT INTO logs (msg) VALUES ('test')"));
      });

      test('extracts SQL from markdown code blocks', () {
        const response = '```sql\nSELECT * FROM orders\n```';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT * FROM orders'));
      });

      test('prefers sql tags over markdown blocks', () {
        const response = '''
```sql
SELECT * FROM old_table
```
<sql>SELECT * FROM new_table</sql>
''';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT * FROM new_table'));
      });

      test('falls back to plain SQL when no tags', () {
        const response = 'SELECT * FROM users WHERE active = 1';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT * FROM users WHERE active = 1'));
      });

      test('returns empty list for non-SQL content', () {
        const response = 'This is just a regular message with no SQL.';
        final statements = parser.extractExecutableStatements(response);

        expect(statements, isEmpty);
      });

      test('cleans Chinese text mixed in sql tags', () {
        const response = '''
<sql>
查询示例：
SELECT * FROM users;
</sql>
''';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT * FROM users'));
      });

      test('handles sql tags with extra whitespace', () {
        const response = '<sql>\n  \n  SELECT 1  \n  \n</sql>';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT 1'));
      });
    });

    group('isValidCommand', () {
      test('returns true for SELECT', () {
        expect(parser.isValidCommand('SELECT * FROM users'), isTrue);
      });

      test('returns true for INSERT', () {
        expect(
          parser.isValidCommand("INSERT INTO users (name) VALUES ('test')"),
          isTrue,
        );
      });

      test('returns true for UPDATE', () {
        expect(
          parser.isValidCommand('UPDATE users SET name = \'test\''),
          isTrue,
        );
      });

      test('returns true for DELETE', () {
        expect(parser.isValidCommand('DELETE FROM users WHERE id = 1'), isTrue);
      });

      test('returns true for CREATE', () {
        expect(parser.isValidCommand('CREATE TABLE test (id INT)'), isTrue);
      });

      test('returns false for non-SQL text', () {
        expect(parser.isValidCommand('Hello world foo bar'), isFalse);
      });

      test('returns false for empty string', () {
        expect(parser.isValidCommand(''), isFalse);
      });
    });
  });
}
