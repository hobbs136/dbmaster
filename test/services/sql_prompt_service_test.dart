import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sql_prompt_service.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/models/database_models.dart';

class MockDatabaseService extends DatabaseService {
  @override
  Future<List<String>> getTables({String? connectionId}) async => [
    'users',
    'orders',
    'products',
  ];

  @override
  Future<List<DbColumn>> getTableColumns(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async {
    if (tableName == 'users') {
      return [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
      ];
    }
    return [];
  }
}

void main() {
  group('SqlPromptService', () {
    late SqlPromptService service;
    late MockDatabaseService mockDb;

    setUp(() {
      mockDb = MockDatabaseService();
      service = SqlPromptService(mockDb);
    });

    group('System Prompt', () {
      test('buildSystemPrompt includes connection info', () async {
        final connection = DatabaseConnection(
          id: 'test',
          name: 'Test Connection',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
          database: 'test_db',
        );

        final prompt = await service.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
        );

        expect(prompt, contains('DbMaster AI'));
        expect(prompt, contains('MySQL'));
        expect(prompt, contains('localhost:3306'));
        expect(prompt, contains('test_db'));
        expect(prompt, contains('Test Connection'));
      });

      test('buildSystemPrompt includes schema when requested', () async {
        final connection = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
        );

        final prompt = await service.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
          includeSchema: true,
        );

        expect(prompt, contains('users'));
        expect(prompt, contains('orders'));
        expect(prompt, contains('products'));
      });

      test('buildSystemPrompt omits schema when not requested', () async {
        final connection = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
        );

        final prompt = await service.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
          includeSchema: false,
        );

        expect(prompt, isNot(contains('Database Schema')));
      });

      test('includes sql tag format requirement', () async {
        final connection = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
        );

        final prompt = await service.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
        );

        expect(prompt, contains('<sql>'));
        expect(prompt, contains('</sql>'));
        expect(prompt, contains('Response Format'));
      });

      test('includes safety rules', () async {
        final connection = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
        );

        final prompt = await service.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
        );

        expect(prompt, contains('Safety Rules'));
        expect(prompt, contains('NEVER violate'));
      });

      test('includes performance rules for MySQL', () async {
        final connection = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
        );

        final prompt = await service.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
        );

        expect(prompt, contains('Performance Rules'));
        expect(prompt, contains('InnoDB'));
        expect(prompt, contains('COUNT(*)'));
        expect(prompt, contains('全表扫描'));
      });

      test('uses correct quote char for MySQL', () async {
        final connection = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
        );

        final prompt = await service.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
        );

        expect(prompt, contains('`'));
      });

      test('uses correct quote char for PostgreSQL', () async {
        final connection = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.postgresql,
          host: 'localhost',
          port: 5432,
        );

        final prompt = await service.buildSystemPrompt(
          connection: connection,
          databaseName: 'test_db',
        );

        expect(prompt, contains('"'));
      });

      test('includes database-specific guidelines', () async {
        final mysqlConn = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
        );

        final mysqlPrompt = await service.buildSystemPrompt(
          connection: mysqlConn,
          databaseName: 'test_db',
        );

        expect(mysqlPrompt, contains('InnoDB'));
        expect(mysqlPrompt, contains('EXPLAIN'));
      });

      test('includes Redis-specific performance rules', () async {
        final redisConn = DatabaseConnection(
          id: 'test',
          name: 'Test',
          type: DatabaseType.redis,
          host: 'localhost',
          port: 6379,
        );

        final redisPrompt = await service.buildSystemPrompt(
          connection: redisConn,
          databaseName: 'test_db',
        );

        expect(redisPrompt, contains('O(N)'));
        expect(redisPrompt, contains('KEYS'));
        expect(redisPrompt, contains('SCAN'));
      });
    });

    group('Extract SQL Statements', () {
      test('extracts single sql statement', () {
        const response =
            'Here is the query:\n<sql>\nSELECT * FROM users;\n</sql>';
        final statements = service.extractSqlStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT * FROM users'));
      });

      test('extracts multiple sql statements', () async {
        const response = '''
Create tables:
<sql>
CREATE TABLE users (id INT PRIMARY KEY);
</sql>
<sql>
CREATE TABLE orders (id INT PRIMARY KEY);
</sql>
        ''';
        final statements = service.extractSqlStatements(response);

        expect(statements.length, equals(2));
        expect(
          statements[0],
          equals('CREATE TABLE users (id INT PRIMARY KEY)'),
        );
        expect(
          statements[1],
          equals('CREATE TABLE orders (id INT PRIMARY KEY)'),
        );
      });

      test('returns empty list when no sql tags', () {
        const response = 'Here is some text without SQL.';
        final statements = service.extractSqlStatements(response);

        expect(statements, isEmpty);
      });

      test('ignores empty sql tags', () {
        const response = '<sql>   </sql>';
        final statements = service.extractSqlStatements(response);

        expect(statements, isEmpty);
      });

      test('handles sql tags with extra whitespace', () {
        const response = '<sql>\n  \n  SELECT 1;  \n  \n</sql>';
        final statements = service.extractSqlStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT 1'));
      });

      test('handles unclosed sql tag', () {
        const response = '''
获取近似行数：
<sql>
SELECT COUNT(*) FROM orders;
        ''';
        final statements = service.extractSqlStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT COUNT(*) FROM orders'));
      });

      test('cleans Chinese text mixed in sql', () {
        const response = '''
<sql>
查询示例：
SELECT * FROM users;
</sql>
        ''';
        final statements = service.extractSqlStatements(response);

        expect(statements.length, equals(1));
        expect(statements[0], equals('SELECT * FROM users'));
      });
    });
  });
}
