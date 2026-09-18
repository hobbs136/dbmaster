import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/response_parsers/redis_response_parser.dart';

void main() {
  group('RedisResponseParser', () {
    late RedisResponseParser parser;

    setUp(() {
      parser = RedisResponseParser(locale: 'en');
    });

    group('extractExecutableStatements', () {
      test('extracts Redis command from sql tags', () {
        const response = '<sql>GET user:1001</sql>';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('GET user:1001'));
      });

      test('extracts SCAN command from sql tags', () {
        const response = '<sql>SCAN 0 MATCH user:* COUNT 100</sql>';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SCAN 0 MATCH user:* COUNT 100'));
      });

      test('extracts from markdown redis blocks', () {
        const response = '```redis\nHGETALL user:1001\n```';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('HGETALL user:1001'));
      });

      test('falls back to plain Redis commands', () {
        const response = 'LRANGE mylist 0 -1';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('LRANGE mylist 0 -1'));
      });

      test('returns empty for non-Redis content', () {
        const response = 'SELECT * FROM users';
        final statements = parser.extractExecutableStatements(response);

        expect(statements, isEmpty);
      });
    });

    group('isValidCommand', () {
      test('returns true for GET', () {
        expect(parser.isValidCommand('GET key'), isTrue);
      });

      test('returns true for HGETALL', () {
        expect(parser.isValidCommand('HGETALL user:1'), isTrue);
      });

      test('returns true for SCAN', () {
        expect(parser.isValidCommand('SCAN 0 MATCH *'), isTrue);
      });

      test('returns false for SQL', () {
        expect(parser.isValidCommand('SELECT * FROM users'), isFalse);
      });

      test('returns false for MongoDB', () {
        expect(parser.isValidCommand('db.users.find()'), isFalse);
      });
    });
  });
}
