import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/ai/prompt_builders/mysql_prompt_builder.dart';
import 'package:dbmaster/services/ai/prompt_builders/postgresql_prompt_builder.dart';
import 'package:dbmaster/services/ai/prompt_builders/sqlserver_prompt_builder.dart';
import 'package:dbmaster/services/ai/prompt_builders/mongodb_prompt_builder.dart';
import 'package:dbmaster/services/ai/prompt_builders/redis_prompt_builder.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/database_abstract.dart';
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
  }) async => [
    DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
  ];
}

void main() {
  group('PromptBuilder system prompts', () {
    late MockDatabaseService mockDb;
    final connection = DatabaseConnection(
      id: 'test',
      name: 'Test Connection',
      type: DatabaseType.mysql,
      host: 'localhost',
      port: 3306,
      username: 'root',
      password: '',
      database: 'test_db',
    );

    setUp(() {
      mockDb = MockDatabaseService();
    });

    test('MySqlPromptBuilder includes MySQL specific rules', () async {
      final builder = MySqlPromptBuilder(mockDb, locale: 'zh');
      final prompt = await builder.buildSystemPrompt(
        connection: connection,
        databaseName: 'test_db',
      );

      expect(prompt, contains('MySQL'));
      expect(prompt, contains('InnoDB'));
      expect(prompt, contains('utf8mb4'));
      expect(prompt, contains('`'));
    });

    test(
      'PostgreSqlPromptBuilder includes PostgreSQL specific rules',
      () async {
        final pgConnection = DatabaseConnection(
          id: 'test',
          name: 'Test Connection',
          type: DatabaseType.postgresql,
          host: 'localhost',
          port: 5432,
          username: 'postgres',
          password: '',
          database: 'test_db',
        );
        final builder = PostgreSqlPromptBuilder(mockDb, locale: 'zh');
        final prompt = await builder.buildSystemPrompt(
          connection: pgConnection,
          databaseName: 'test_db',
        );

        expect(prompt, contains('PostgreSQL'));
        expect(prompt, contains('JSONB'));
        expect(prompt, contains('"'));
      },
    );

    test('SqlServerPromptBuilder uses bracket quotes', () async {
      final sqlServerConnection = DatabaseConnection(
        id: 'test',
        name: 'Test Connection',
        type: DatabaseType.sqlserver,
        host: 'localhost',
        port: 1433,
        username: 'sa',
        password: '',
        database: 'test_db',
      );
      final builder = SqlServerPromptBuilder(mockDb, locale: 'zh');
      final prompt = await builder.buildSystemPrompt(
        connection: sqlServerConnection,
        databaseName: 'test_db',
      );

      expect(prompt, contains('SQL Server'));
      expect(builder.quoteChar, '[');
      expect(builder.getExampleQuery(sqlServerConnection), contains('[id]'));
      expect(builder.getExampleQuery(sqlServerConnection), contains('[users]'));
      expect(
        builder.getExampleQuery(sqlServerConnection),
        isNot(contains('"id"')),
      );
    });

    test('MongoDbPromptBuilder includes MongoDB specific rules', () async {
      final mongoConnection = DatabaseConnection(
        id: 'test',
        name: 'Test Connection',
        type: DatabaseType.mongodb,
        host: 'localhost',
        port: 27017,
        username: '',
        password: '',
        database: 'test_db',
      );
      final builder = MongoDbPromptBuilder(mockDb, locale: 'zh');
      final prompt = await builder.buildSystemPrompt(
        connection: mongoConnection,
        databaseName: 'test_db',
      );

      expect(prompt, contains('MongoDB'));
      expect(prompt, contains('find()'));
      expect(prompt, contains('aggregate()'));
    });

    test('RedisPromptBuilder includes Redis specific rules', () async {
      final redisConnection = DatabaseConnection(
        id: 'test',
        name: 'Test Connection',
        type: DatabaseType.redis,
        host: 'localhost',
        port: 6379,
        username: '',
        password: '',
        database: '0',
      );
      final builder = RedisPromptBuilder(mockDb, locale: 'zh');
      final prompt = await builder.buildSystemPrompt(
        connection: redisConnection,
        databaseName: '0',
      );

      expect(prompt, contains('Redis'));
      expect(prompt, contains('SCAN'));
      expect(prompt, contains('KEYS'));
    });

    test(
      'simplified response format does not require Execution Plan',
      () async {
        final builder = MySqlPromptBuilder(mockDb, locale: 'zh');
        final prompt = await builder.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
        );

        // 新的简化格式不应强制要求 AI 输出 Execution Plan
        expect(prompt, contains('不需要输出 Execution Plan'));
      },
    );

    test('simplified response format does not require Warning', () async {
      final builder = MySqlPromptBuilder(mockDb, locale: 'en');
      final prompt = await builder.buildSystemPrompt(
        connection: connection,
        databaseName: 'test_db',
      );

      expect(prompt, contains('do NOT output Execution Plan'));
    });

    // -------------------------------------------------------------------------
    // 通用数据库 Agent：提示词 agent 化（安全规则措辞 + 自主探索 + 数据修改规范）
    // -------------------------------------------------------------------------
    test('安全规则要求直接产出语句而非反复追问（zh）', () async {
      final builder = MySqlPromptBuilder(mockDb, locale: 'zh');
      final prompt = await builder.buildSystemPrompt(
        connection: connection,
        databaseName: 'test_db',
      );

      expect(prompt, contains('禁止用反复追问代替产出'));
      // 旧措辞（把「先询问用户」当对话动作）不应再出现
      expect(prompt, isNot(contains('必须先询问用户确认')));
    });

    test('safety rules demand direct output, not repeated questions (en)',
        () async {
      final builder = MySqlPromptBuilder(mockDb, locale: 'en');
      final prompt = await builder.buildSystemPrompt(
        connection: connection,
        databaseName: 'test_db',
      );

      expect(prompt, contains('never replace producing statements with asking questions'));
      expect(prompt, isNot(contains('Must ask for user confirmation first')));
    });

    test('包含自主探索工作流 section（get_table_relationships / run_readonly_query）',
        () async {
      final builder = MySqlPromptBuilder(mockDb, locale: 'zh');
      final prompt = await builder.buildSystemPrompt(
        connection: connection,
        databaseName: 'test_db',
      );

      expect(prompt, contains('自主探索'));
      expect(prompt, contains('get_table_relationships'));
      expect(prompt, contains('run_readonly_query'));
      // 最多反问一次
      expect(prompt, contains('最多向用户反问一次'));
    });

    test('包含数据修改请求规范（依赖顺序 + COUNT 预览 + WHERE 一致）', () async {
      final builder = PostgreSqlPromptBuilder(mockDb, locale: 'zh');
      final pgConnection = DatabaseConnection(
        id: 'test',
        name: 'Test Connection',
        type: DatabaseType.postgresql,
        host: 'localhost',
        port: 5432,
        username: 'postgres',
        password: '',
        database: 'test_db',
      );
      final prompt = await builder.buildSystemPrompt(
        connection: pgConnection,
        databaseName: 'test_db',
      );

      expect(prompt, contains('数据修改请求'));
      expect(prompt, contains('SELECT COUNT(*)'));
      expect(prompt, contains('完全一致，不得扩大或缩小范围'));
    });
  });
}
