import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/ai_parser_factory.dart';
import 'package:dbmaster/services/ai/response_parsers/sql_response_parser.dart';
import 'package:dbmaster/services/ai/response_parsers/mongodb_response_parser.dart';
import 'package:dbmaster/services/ai/response_parsers/redis_response_parser.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('AiParserFactory', () {
    test('creates SqlResponseParser for mysql', () {
      final parser = AiParserFactory.createParser(type: DatabaseType.mysql);
      expect(parser, isA<SqlResponseParser>());
    });

    test('creates SqlResponseParser for postgresql', () {
      final parser = AiParserFactory.createParser(
        type: DatabaseType.postgresql,
      );
      expect(parser, isA<SqlResponseParser>());
    });

    test('creates SqlResponseParser for sqlite', () {
      final parser = AiParserFactory.createParser(type: DatabaseType.sqlite);
      expect(parser, isA<SqlResponseParser>());
    });

    test('creates SqlResponseParser for doris', () {
      final parser = AiParserFactory.createParser(type: DatabaseType.doris);
      expect(parser, isA<SqlResponseParser>());
    });

    test('creates SqlResponseParser for tdengine', () {
      final parser = AiParserFactory.createParser(type: DatabaseType.tdengine);
      expect(parser, isA<SqlResponseParser>());
    });

    test('creates SqlResponseParser for sqlserver', () {
      final parser = AiParserFactory.createParser(type: DatabaseType.sqlserver);
      expect(parser, isA<SqlResponseParser>());
    });

    test('creates MongoDbResponseParser for mongodb', () {
      final parser = AiParserFactory.createParser(type: DatabaseType.mongodb);
      expect(parser, isA<MongoDbResponseParser>());
    });

    test('creates RedisResponseParser for redis', () {
      final parser = AiParserFactory.createParser(type: DatabaseType.redis);
      expect(parser, isA<RedisResponseParser>());
    });

    test('passes locale correctly', () {
      final parser = AiParserFactory.createParser(
        type: DatabaseType.mysql,
        locale: 'zh',
      );
      expect(parser, isNotNull);
    });
  });
}
