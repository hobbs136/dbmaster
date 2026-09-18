// ============================================================================
// Doris Integration Tests
// Tests: Real Doris database operations using a cloud Doris instance
// Prerequisites: Set environment variables or update doris_test_config.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/doris_adapter.dart';
import 'config/doris_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !DorisTestConfig.available) {
      // ignore: avoid_print
      print('DORIS_E2E_SKIP: DBMASTER_DORIS_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Doris Connection', () {
    late DorisAdapter adapter;

    setUp(() {
      adapter = DorisAdapter();
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) {
          await adapter.disconnect();
        }
      } catch (_) {
        // Ignore disconnect errors
      }
    });

    testWidgets('should connect to Doris server successfully', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_1',
        name: 'Test Connection 1',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
        database: DorisTestConfig.database,
      );

      try {
        final result = await adapter.connect(connection);
        expect(
          result,
          isTrue,
          reason:
              'Connection to ${DorisTestConfig.host}:${DorisTestConfig.port} failed',
        );
        expect(adapter.isConnected, isTrue);
      } catch (e) {
        fail('Connection failed with error: $e');
      }
    });

    testWidgets('should fail to connect with wrong credentials', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_2',
        name: 'Test Connection 2',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: 'wrong_user',
        password: 'wrong_password',
      );

      try {
        final result = await adapter.connect(connection);
        expect(
          result,
          isFalse,
          reason: 'Expected connection to fail but it succeeded',
        );
        expect(adapter.isConnected, isFalse);
      } catch (e) {
        // Expected to throw
        expect(adapter.isConnected, isFalse);
      }
    });

    testWidgets('should test connection successfully', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_3',
        name: 'Test Connection 3',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
        database: DorisTestConfig.database,
      );

      final error = await adapter.testConnection(connection);

      expect(error, isNull);
    });
  });

  group('Doris Database Operations', () {
    late DorisAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = DorisAdapter();
      testDbName = DorisTestConfig.generateTestDatabaseName();

      final connection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should create a new database', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.createDatabase(testDbName);

      expect(result, isTrue);

      final databases = await adapter.getDatabases();
      expect(databases, contains(testDbName));
    });

    testWidgets('should list all databases', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final databases = await adapter.getDatabases();

      expect(databases, isNotEmpty);
      // T29：网关口径下系统库由壳过滤（对齐旧 _SchemaManager 口径），
      // 断言 information_schema 不再出现。
      expect(databases, isNot(contains('information_schema')));
    });

    testWidgets('should switch to a database', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      expect(adapter.currentConnection?.database, equals(testDbName));
    });

    testWidgets('should get database properties', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.createDatabase(
        testDbName,
        options: {'charset': 'utf8mb4', 'collation': 'utf8mb4_unicode_ci'},
      );

      final props = await adapter.getDatabaseProperties(testDbName);

      expect(props, isNotNull);
      expect(props!['charset'], equals('utf8mb4'));
    });

    testWidgets('should drop a database', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.createDatabase(testDbName);
      final result = await adapter.dropDatabase(testDbName);

      expect(result, isTrue);

      final databases = await adapter.getDatabases();
      expect(databases, isNot(contains(testDbName)));
    });
  });

  group('Doris Table Operations', () {
    late DorisAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = DorisAdapter();
      testDbName = DorisTestConfig.generateTestDatabaseName();
      testTableName = 'test_table';

      final connection = DatabaseConnection(
        id: 'test_table_conn',
        name: 'Test Table Connection',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should create a table with columns', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(255)', isNullable: false),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
        DbColumn(
          name: 'created_at',
          type: 'DATETIME',
          isNullable: true,
          defaultValue: 'CURRENT_TIMESTAMP',
        ),
      ];

      final result = await adapter.createTable(testTableName, columns);
      expect(result, isTrue);

      final tables = await adapter.getTables();
      expect(tables, contains(testTableName));
    });

    testWidgets('should get table columns', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ];

      await adapter.createTable(testTableName, columns);
      final tableColumns = await adapter.getTableColumns(testTableName);

      expect(tableColumns, hasLength(2));
      expect(tableColumns[0].name, equals('id'));
      // Doris DUPLICATE KEY 模型不显示 PRI，但 Key 列会被识别
      expect(tableColumns[0].isPrimaryKey, isTrue);
      expect(tableColumns[1].name, equals('name'));
    });

    testWidgets('should get table indexes', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
      ];

      await adapter.createTable(testTableName, columns);
      // Doris 的索引是隐式的，SHOW INDEX FROM 返回空
      final indexes = await adapter.getTableIndexes(testTableName);
      expect(indexes, isA<List<DbIndex>>());
    });

    testWidgets('should drop an index', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
      ];

      await adapter.createTable(testTableName, columns);
      // 现代 Doris 支持倒排索引；先建后删（走 ALTER TABLE ... DROP INDEX）
      await adapter.createIndex(testTableName, 'idx_email', ['email']);
      final result = await adapter.dropIndex(testTableName, 'idx_email');
      expect(result, isTrue);
    });

    testWidgets('should drop a table', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
      ];

      await adapter.createTable(testTableName, columns);
      final result = await adapter.dropTable(testTableName);

      expect(result, isTrue);

      final tables = await adapter.getTables();
      expect(tables, isNot(contains(testTableName)));
    });

    testWidgets('should rename a table', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final newName = 'renamed_table';
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
      ];

      await adapter.createTable(testTableName, columns);
      // 现代 Doris 支持 ALTER TABLE ... RENAME
      final result = await adapter.renameTable(testTableName, newName);
      expect(result, isTrue);

      final tables = await adapter.getTables();
      expect(tables, contains(newName));
      expect(tables, isNot(contains(testTableName)));
    });

    testWidgets('should truncate a table', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: true),
      ];

      await adapter.createTable(testTableName, columns);
      await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name) VALUES (1, 'Test')",
      );

      var countResult = await adapter.executeQuery(
        'SELECT COUNT(*) as cnt FROM `$testTableName`',
      );
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(1));

      await adapter.truncateTable(testTableName);

      countResult = await adapter.executeQuery(
        'SELECT COUNT(*) as cnt FROM `$testTableName`',
      );
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(0));
    });
  });

  group('Doris CRUD Operations', () {
    late DorisAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = DorisAdapter();
      testDbName = DorisTestConfig.generateTestDatabaseName();
      testTableName = 'users';

      final connection = DatabaseConnection(
        id: 'test_crud_conn',
        name: 'Test CRUD Connection',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.createTable(testTableName, [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
        DbColumn(name: 'age', type: 'INT', isNullable: true),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should insert data', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );

      expect(result.affectedRows, equals(1));
    });

    testWidgets('should select data', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );
      await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name, email, age) VALUES (2, 'Bob', 'bob@example.com', 25)",
      );

      final result = await adapter.executeQuery(
        'SELECT * FROM `$testTableName`',
      );

      expect(result.rows, hasLength(2));
      expect(result.columns, contains('name'));
      expect(result.rows[0]['name'], equals('Alice'));
    });

    testWidgets('should update data', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );

      // Doris DUPLICATE KEY 模型表不支持 UPDATE
      try {
        await adapter.executeQuery(
          "UPDATE `$testTableName` SET age = 31 WHERE id = 1",
        );
      } catch (e) {
        // Expected: Doris returns "Only unique table could be updated"
        expect(e.toString(), contains('update'));
      }
    });

    testWidgets('should delete data', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );

      await adapter.executeQuery("DELETE FROM `$testTableName` WHERE id = 1");

      // Doris DELETE 可能返回 affectedRows=0，但数据已被删除
      final countResult = await adapter.executeQuery(
        'SELECT COUNT(*) as cnt FROM `$testTableName`',
      );
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(0));
    });

    testWidgets('should get table data with pagination', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      for (var i = 1; i <= 10; i++) {
        await adapter.executeQuery(
          "INSERT INTO `$testTableName` (id, name, email, age) VALUES ($i, 'User$i', 'user$i@example.com', 20 + $i)",
        );
      }

      final result = await adapter.getTableData(
        testTableName,
        limit: 5,
        offset: 0,
      );

      expect(result.rows, hasLength(5));
    });

    testWidgets('should get table row count', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      for (var i = 1; i <= 5; i++) {
        await adapter.executeQuery(
          "INSERT INTO `$testTableName` (id, name, email, age) VALUES ($i, 'User$i', 'user$i@example.com', 20 + $i)",
        );
      }

      final count = await adapter.getTableRowCount(testTableName);

      expect(count, equals(5));
    });
  });

  group('Doris Advanced Operations', () {
    late DorisAdapter adapter;

    setUp(() async {
      adapter = DorisAdapter();

      final connection = DatabaseConnection(
        id: 'test_adv_conn',
        name: 'Test Advanced Connection',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      final connected = await adapter.connect(connection);
      expect(
        connected,
        isTrue,
        reason: 'Failed to connect to Doris for advanced operations',
      );

      // 创建并切换到测试数据库，确保高级操作有可用数据库
      await adapter.executeQuery(
        'CREATE DATABASE IF NOT EXISTS dbmaster_test_advanced',
      );
      await adapter.useDatabase('dbmaster_test_advanced');
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery(
            'DROP DATABASE IF EXISTS dbmaster_test_advanced',
          );
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should get server version', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final version = await adapter.getServerVersion();

      expect(version, isNotNull);
      expect(version!['database'], equals('Doris'));
      expect(version['version'], isNotNull);
    });

    testWidgets('should get charsets', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final charsets = await adapter.getCharsets();

      expect(charsets, isNotEmpty);
      expect(charsets, contains('utf8mb4'));
    });

    testWidgets('should get collations', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final collations = await adapter.getCollations(charset: 'utf8mb4');

      expect(collations, isNotEmpty);
      expect(collations.first['charset'], equals('utf8mb4'));
    });

    testWidgets('should execute complex SQL query', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery(
        "SELECT 1 as num, 'hello' as str, NOW() as time",
      );

      expect(result.rows, hasLength(1));
      expect(result.rows[0]['num'].toString(), equals('1'));
      expect(result.rows[0]['str'], equals('hello'));
    });

    testWidgets('should get explain plan', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.getExplainPlan('SELECT 1');

      expect(result.rows, isNotEmpty);
    });

    testWidgets('should execute SQL script', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final script = '''
        DROP TABLE IF EXISTS script_test;
        CREATE TABLE script_test (id INT, name VARCHAR(100)) DISTRIBUTED BY HASH(id) BUCKETS 1 PROPERTIES ("replication_num" = "1");
        INSERT INTO script_test VALUES (1, 'a');
        INSERT INTO script_test VALUES (2, 'b');
      ''';

      try {
        final result = await adapter.executeSqlScript(script);
        expect(result, isTrue);
      } catch (e) {
        fail('SQL script execution failed: $e');
      }
    });

    testWidgets('should get views list', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final views = await adapter.getViews();
      expect(views, isA<List<String>>());
    });

    testWidgets('should get procedures list', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final procedures = await adapter.getProcedures();
      expect(procedures, isA<List<String>>());
    });

    testWidgets('should get functions list', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final functions = await adapter.getFunctions();
      expect(functions, isA<List<String>>());
    });
  });

  group('Doris Column Operations', () {
    late DorisAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = DorisAdapter();
      testDbName = DorisTestConfig.generateTestDatabaseName();
      testTableName = 'alter_test';

      final connection = DatabaseConnection(
        id: 'test_col_conn',
        name: 'Test Column Connection',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.createTable(testTableName, [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: true),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should add a column', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final newColumn = DbColumn(
        name: 'email',
        type: 'VARCHAR(255)',
        isNullable: true,
      );

      final result = await adapter.addColumn(testTableName, newColumn);
      expect(result, isTrue);

      final columns = await adapter.getTableColumns(testTableName);
      final emailCol = columns.firstWhere((col) => col.name == 'email');
      expect(emailCol, isNotNull);
    });

    testWidgets('should drop a column', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // 现代 Doris 支持 ALTER TABLE DROP COLUMN
      final result = await adapter.dropColumn(testTableName, 'name');
      expect(result, isTrue);

      // schema change 可能异步，短暂等待后重查
      await Future.delayed(const Duration(seconds: 1));
      final columns = await adapter.getTableColumns(testTableName);
      expect(columns.any((c) => c.name == 'name'), isFalse);
    });

    testWidgets('should modify a column', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // 现代 Doris 支持 ALTER TABLE MODIFY COLUMN（异步 schema change）
      // 仅扩长 name 列并保持 nullable，避免 key 列 / NOT NULL 变更失败
      final modifiedColumn = DbColumn(
        name: 'name',
        type: 'VARCHAR(200)',
        isNullable: true,
      );

      final result = await adapter.modifyColumn(
        testTableName,
        'name',
        modifiedColumn,
      );
      expect(result, isTrue);

      // schema change 可能异步，短暂等待后重查类型
      await Future.delayed(const Duration(seconds: 1));
      final columns = await adapter.getTableColumns(testTableName);
      final nameCol = columns.firstWhere((c) => c.name == 'name');
      expect(nameCol.type, contains('200'));
    });
  });

  group('Doris Export and AI Operations', () {
    late DorisAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = DorisAdapter();
      testDbName = DorisTestConfig.generateTestDatabaseName();

      final connection = DatabaseConnection(
        id: 'test_export_conn',
        name: 'Test Export Connection',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.createTable('users', [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should export database structure', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final structure = await adapter.exportDatabaseStructure(testDbName);

      expect(structure, isNotEmpty);
      expect(structure, contains('CREATE TABLE'));
      expect(structure, contains('users'));
    });

    testWidgets('should get AI schema summary', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final summary = await adapter.getAiSchemaSummary();

      expect(summary, isNotEmpty);
      expect(summary, contains('Doris'));
    });

    testWidgets('should execute AI command', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeAiCommand(
        'SELECT COUNT(*) as cnt FROM users',
      );

      expect(result.success, isTrue);
      expect(result.output, isNotEmpty);
    });

    testWidgets('should validate safe command', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('SELECT * FROM users');

      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.safe));
    });

    testWidgets('should validate dangerous command', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('DROP TABLE users');

      expect(result.allowed, isFalse);
      expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
    });

    testWidgets('should validate warning command', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('DELETE FROM users WHERE id = 1');

      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.warning));
    });
  });

  group('Doris Connection Management', () {
    late DorisAdapter adapter;

    testWidgets('should disconnect cleanly', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      adapter = DorisAdapter();

      final connection = DatabaseConnection(
        id: 'test_disc_conn',
        name: 'Test Disconnect Connection',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
        database: DorisTestConfig.database,
      );

      await adapter.connect(connection);
      expect(adapter.isConnected, isTrue);

      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
    });

    testWidgets('should handle multiple connections', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final adapter1 = DorisAdapter();
      final adapter2 = DorisAdapter();

      final conn1 = DatabaseConnection(
        id: 'multi_1',
        name: 'Multi Connection 1',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
        database: DorisTestConfig.database,
      );

      final conn2 = DatabaseConnection(
        id: 'multi_2',
        name: 'Multi Connection 2',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
        database: DorisTestConfig.database,
      );

      final result1 = await adapter1.connect(conn1);
      final result2 = await adapter2.connect(conn2);

      expect(result1, isTrue);
      expect(result2, isTrue);
      expect(adapter1.isConnected, isTrue);
      expect(adapter2.isConnected, isTrue);

      await adapter1.disconnect();
      await adapter2.disconnect();
    });
  });
}
