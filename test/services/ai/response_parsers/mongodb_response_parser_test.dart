import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/response_parsers/mongodb_response_parser.dart';

void main() {
  group('MongoDbResponseParser', () {
    late MongoDbResponseParser parser;

    setUp(() {
      parser = MongoDbResponseParser(locale: 'en');
    });

    group('extractExecutableStatements', () {
      test('extracts MongoDB query from sql tags', () {
        const response = "<sql>db.users.find({age: {\$gt: 25}})</sql>";
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('db.users.find({age: {\$gt: 25}})'));
      });

      test('extracts aggregate from sql tags', () {
        const response =
            "<sql>db.orders.aggregate([{\$match: {status: 'done'}}, {\$group: {_id: null, total: {\$sum: 1}}}])</sql>";
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], contains('db.orders.aggregate'));
      });

      test('extracts from markdown javascript blocks', () {
        const response = '```javascript\ndb.users.find()\n```';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('db.users.find()'));
      });

      test('falls back to plain MongoDB syntax', () {
        const response = 'db.users.find({status: "active"}).limit(10)';
        final statements = parser.extractExecutableStatements(response);

        expect(statements.length, equals(1));
        expect(
          statements[0],
          equals('db.users.find({status: "active"}).limit(10)'),
        );
      });

      test('returns empty for non-MongoDB content', () {
        const response = 'SELECT * FROM users';
        final statements = parser.extractExecutableStatements(response);

        expect(statements, isEmpty);
      });
    });

    group('isValidCommand', () {
      test('returns true for find', () {
        expect(parser.isValidCommand('db.users.find()'), isTrue);
      });

      test('returns true for aggregate', () {
        expect(parser.isValidCommand('db.orders.aggregate([])'), isTrue);
      });

      test('returns true for insertOne', () {
        expect(parser.isValidCommand('db.users.insertOne({})'), isTrue);
      });

      test('returns false for SQL', () {
        expect(parser.isValidCommand('SELECT * FROM users'), isFalse);
      });

      test('returns false for non-db prefix', () {
        expect(parser.isValidCommand('console.log("test")'), isFalse);
      });
    });
  });
}
