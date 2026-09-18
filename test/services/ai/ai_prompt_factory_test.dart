import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/ai_prompt_factory.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/models/database_models.dart';

class MockDatabaseService extends DatabaseService {
  @override
  Future<List<String>> getTables({String? connectionId}) async => ['users'];

  @override
  Future<List<DbColumn>> getTableColumns(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async => [];
}

void main() {
  group('AiPromptFactory', () {
    late MockDatabaseService mockDb;

    setUp(() {
      mockDb = MockDatabaseService();
    });

    test('creates MySqlPromptBuilder for mysql', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.mysql,
        dbService: mockDb,
      );
      expect(builder, isNotNull);
      expect(builder.quoteChar, equals('`'));
    });

    test('creates PostgreSqlPromptBuilder for postgresql', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.postgresql,
        dbService: mockDb,
      );
      expect(builder, isNotNull);
      expect(builder.quoteChar, equals('"'));
    });

    test('creates SqlitePromptBuilder for sqlite', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.sqlite,
        dbService: mockDb,
      );
      expect(builder, isNotNull);
      expect(builder.quoteChar, equals('"'));
    });

    test('creates DorisPromptBuilder for doris', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.doris,
        dbService: mockDb,
      );
      expect(builder, isNotNull);
      expect(builder.quoteChar, equals('`'));
    });

    test('creates TdenginePromptBuilder for tdengine', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.tdengine,
        dbService: mockDb,
      );
      expect(builder, isNotNull);
      expect(builder.quoteChar, equals('`'));
    });

    test('creates SqlServerPromptBuilder for sqlserver', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.sqlserver,
        dbService: mockDb,
      );
      expect(builder, isNotNull);
      expect(builder.quoteChar, equals('['));
    });

    test('creates MongoDbPromptBuilder for mongodb', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.mongodb,
        dbService: mockDb,
      );
      expect(builder, isNotNull);
      expect(builder.quoteChar, isEmpty);
    });

    test('creates RedisPromptBuilder for redis', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.redis,
        dbService: mockDb,
      );
      expect(builder, isNotNull);
      expect(builder.quoteChar, isEmpty);
    });

    test('passes locale correctly', () {
      final builder = AiPromptFactory.createBuilder(
        type: DatabaseType.mysql,
        dbService: mockDb,
        locale: 'zh',
      );
      expect(builder, isNotNull);
    });
  });
}
