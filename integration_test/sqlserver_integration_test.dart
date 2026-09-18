// ============================================================================
// SQL Server Integration Tests
// Tests: Real SQL Server database operations using a cloud SQL Server instance
// Prerequisites: Set environment variables or update sqlserver_test_config.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'config/sqlserver_test_config.dart';
import 'helpers/ss_gateway_e2e_helper.dart';

// T28：SS 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
// 二进制不可得时全组以可 grep 的 SQLSERVER_E2E_SKIP 跳过（无假绿）。
void main() {
  bool ssE2EGatewayReady = false;
  setUpAll(() async {
    ssE2EGatewayReady = await ensureEmbeddedServerForSsE2E();
    if (ssE2EGatewayReady && !SQLServerTestConfig.available) {
      // ignore: avoid_print
      print('SS_E2E_SKIP: DBMASTER_SQLSERVER_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      ssE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SQL Server Connection', () {
    late SqlServerAdapter adapter;

    setUp(() {
      adapter = SqlServerAdapter();
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

    testWidgets('should connect to SQL Server server successfully', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_1',
        name: 'Test Connection 1',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
        database: SQLServerTestConfig.database,
      );

      try {
        final result = await adapter.connect(connection);
        expect(result, isTrue, reason: 'Connection to ${SQLServerTestConfig.host}:${SQLServerTestConfig.port} failed');
        expect(adapter.isConnected, isTrue);
      } catch (e) {
        fail('Connection failed with error: $e');
      }
    });

    testWidgets('should fail to connect with wrong credentials', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_2',
        name: 'Test Connection 2',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: 'wrong_user',
        password: 'wrong_password',
      );

      try {
        final result = await adapter.connect(connection);
        expect(result, isFalse, reason: 'Expected connection to fail but it succeeded');
        expect(adapter.isConnected, isFalse);
      } catch (e) {
        // Expected to throw
        expect(adapter.isConnected, isFalse);
      }
    });

    testWidgets('should test connection successfully', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_3',
        name: 'Test Connection 3',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
        database: SQLServerTestConfig.database,
      );

      final error = await adapter.testConnection(connection);

      expect(error, isNull);
    });
  });

  group('SQL Server Database Operations', () {
    late SqlServerAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = SqlServerAdapter();
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should create a new database', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final result = await adapter.createDatabase(testDbName);

      expect(result, isTrue);

      final databases = await adapter.getDatabases();
      expect(databases, contains(testDbName));
    });

    testWidgets('should list all databases', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final databases = await adapter.getDatabases();

      expect(databases, isNotEmpty);
      // SQL Server getDatabases excludes system databases
      expect(databases, isNot(contains('master')));
      expect(databases, isNot(contains('tempdb')));
    });

    testWidgets('should switch to a database', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      expect(adapter.currentConnection?.database, equals(testDbName));
    });

    testWidgets('should get database properties', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      await adapter.createDatabase(testDbName);

      final props = await adapter.getDatabaseProperties(testDbName);

      expect(props, isNotNull);
      expect(props!['name'], equals(testDbName));
      expect(props['collation'], isNotNull);
    });

    testWidgets('should drop a database', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      await adapter.createDatabase(testDbName);
      final result = await adapter.dropDatabase(testDbName);

      expect(result, isTrue);

      final databases = await adapter.getDatabases();
      expect(databases, isNot(contains(testDbName)));
    });
  });

  group('SQL Server Table Operations', () {
    late SqlServerAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = SqlServerAdapter();
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      testTableName = 'test_table';
      
      final connection = DatabaseConnection(
        id: 'test_table_conn',
        name: 'Test Table Connection',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should create a table with columns', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(
          name: 'name',
          type: 'VARCHAR(255)',
          isNullable: false,
        ),
        DbColumn(
          name: 'email',
          type: 'VARCHAR(255)',
          isNullable: true,
        ),
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
      expect(tables, anyElement(contains(testTableName)));
    });

    testWidgets('should get table columns', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ];

      await adapter.createTable(testTableName, columns);
      final tableColumns = await adapter.getTableColumns(testTableName);

      expect(tableColumns, hasLength(2));
      expect(tableColumns[0].name, equals('id'));
      expect(tableColumns[0].isPrimaryKey, isTrue);
      expect(tableColumns[1].name, equals('name'));
    });

    testWidgets('should get table indexes', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
      ];

      await adapter.createTable(testTableName, columns);
      await adapter.createIndex(testTableName, 'idx_email', ['email']);
      
      final indexes = await adapter.getTableIndexes(testTableName);

      expect(indexes, isNotEmpty);
      final emailIndex = indexes.firstWhere((idx) => idx.name == 'idx_email');
      expect(emailIndex.columns, contains('email'));
    });

    testWidgets('should drop an index', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
      ];

      await adapter.createTable(testTableName, columns);
      await adapter.createIndex(testTableName, 'idx_email', ['email']);
      
      var indexes = await adapter.getTableIndexes(testTableName);
      expect(indexes.any((idx) => idx.name == 'idx_email'), isTrue);

      final result = await adapter.dropIndex(testTableName, 'idx_email');
      expect(result, isTrue);

      indexes = await adapter.getTableIndexes(testTableName);
      expect(indexes.any((idx) => idx.name == 'idx_email'), isFalse);
    });

    testWidgets('should drop a table', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
      ];

      await adapter.createTable(testTableName, columns);
      final result = await adapter.dropTable(testTableName);

      expect(result, isTrue);

      final tables = await adapter.getTables();
      expect(tables, isNot(anyElement(contains(testTableName))));
    });

    testWidgets('should rename a table', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final newName = 'renamed_table';
      final columns = [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
      ];

      await adapter.createTable(testTableName, columns);
      final result = await adapter.renameTable(testTableName, newName);

      expect(result, isTrue);

      final tables = await adapter.getTables();
      expect(tables, anyElement(contains(newName)));
      expect(tables, isNot(anyElement(contains(testTableName))));
    });

    testWidgets('should truncate a table', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: true),
      ];

      await adapter.createTable(testTableName, columns);
      await adapter.executeQuery(
        "INSERT INTO $testTableName (id, name) VALUES (1, 'Test')",
      );
      
      var countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM $testTableName');
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(1));

      await adapter.truncateTable(testTableName);
      
      countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM $testTableName');
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(0));
    });
  });

  group('SQL Server CRUD Operations', () {
    late SqlServerAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = SqlServerAdapter();
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      testTableName = 'users';
      
      final connection = DatabaseConnection(
        id: 'test_crud_conn',
        name: 'Test CRUD Connection',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
        DbColumn(name: 'age', type: 'INT', isNullable: true),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should insert data', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery(
        "INSERT INTO $testTableName (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );

      expect(result.affectedRows, equals(1));
    });

    testWidgets('should select data', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO $testTableName (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );
      await adapter.executeQuery(
        "INSERT INTO $testTableName (id, name, email, age) VALUES (2, 'Bob', 'bob@example.com', 25)",
      );

      final result = await adapter.executeQuery('SELECT * FROM $testTableName');

      expect(result.rows, hasLength(2));
      expect(result.columns, contains('name'));
      expect(result.rows[0]['name'], equals('Alice'));
    });

    testWidgets('should update data', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO $testTableName (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );

      final result = await adapter.executeQuery(
        "UPDATE $testTableName SET age = 31 WHERE id = 1",
      );

      expect(result.affectedRows, equals(1));

      final selectResult = await adapter.executeQuery(
        'SELECT age FROM $testTableName WHERE id = 1',
      );
      expect(int.parse(selectResult.rows.first['age'].toString()), equals(31));
    });

    testWidgets('should delete data', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO $testTableName (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );

      final result = await adapter.executeQuery(
        "DELETE FROM $testTableName WHERE id = 1",
      );

      expect(result.affectedRows, equals(1));

      final countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM $testTableName');
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(0));
    });

    testWidgets('should get table data with pagination', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      for (var i = 1; i <= 10; i++) {
        await adapter.executeQuery(
          "INSERT INTO $testTableName (id, name, email, age) VALUES ($i, 'User$i', 'user$i@example.com', 20 + $i)",
        );
      }

      final result = await adapter.getTableData(testTableName, limit: 5, offset: 0);

      expect(result.rows, hasLength(5));
    });

    testWidgets('should get table row count', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      for (var i = 1; i <= 5; i++) {
        await adapter.executeQuery(
          "INSERT INTO $testTableName (id, name, email, age) VALUES ($i, 'User$i', 'user$i@example.com', 20 + $i)",
        );
      }

      final count = await adapter.getTableRowCount(testTableName);

      expect(count, equals(5));
    });
  });

  group('SQL Server Advanced Operations', () {
    late SqlServerAdapter adapter;

    setUp(() async {
      adapter = SqlServerAdapter();
      
      final connection = DatabaseConnection(
        id: 'test_adv_conn',
        name: 'Test Advanced Connection',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );
      
      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to SQL Server for advanced operations');
      
      // 创建并切换到测试数据库，确保高级操作有可用数据库
      await adapter.executeQuery("""
        IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'dbmaster_test_advanced')
          CREATE DATABASE dbmaster_test_advanced
      """);
      await adapter.useDatabase('dbmaster_test_advanced');
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS dbmaster_test_advanced');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should get server version', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final version = await adapter.getServerVersion();

      expect(version, isNotNull);
      expect(version!['database'], equals('SQL Server'));
      expect(version['version'], isNotNull);
    });

    testWidgets('should get charsets', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final charsets = await adapter.getCharsets();

      // SQL Server 没有独立的字符集概念，只有排序规则
      expect(charsets, isA<List<String>>());
    });

    testWidgets('should get collations', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final collations = await adapter.getCollations();

      expect(collations, isNotEmpty);
      expect(collations.first['name'], isNotNull);
    });

    testWidgets('should execute complex SQL query', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery(
        "SELECT 1 as num, 'hello' as str, GETDATE() as time",
      );

      expect(result.rows, hasLength(1));
      expect(result.rows[0]['num'].toString(), equals('1'));
      expect(result.rows[0]['str'], equals('hello'));
      expect(result.rows[0]['time'], isNotNull);
    });

    testWidgets('should get explain plan', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      // T28 已知边界：SET SHOWPLAN_XML 是会话级开关，与网关单语句独立连接
      // 模型不兼容——fail-loud 抛 UnsupportedError（不再返回空计划）。
      await expectLater(
        adapter.getExplainPlan('SELECT 1'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    testWidgets('should execute SQL script', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final script = '''
        DROP TABLE IF EXISTS script_test;
        CREATE TABLE script_test (id INT PRIMARY KEY);
        INSERT INTO script_test VALUES (1);
        INSERT INTO script_test VALUES (2);
      ''';

      try {
        final result = await adapter.executeSqlScript(script);
        expect(result, isTrue);
      } catch (e) {
        fail('SQL script execution failed: $e');
      }
    });

    testWidgets('should get views list', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final views = await adapter.getViews();
      expect(views, isA<List<String>>());
    });

    testWidgets('should get procedures list', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final procedures = await adapter.getProcedures();
      expect(procedures, isA<List<String>>());
    });

    testWidgets('should get functions list', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final functions = await adapter.getFunctions();
      expect(functions, isA<List<String>>());
    });
  });

  group('SQL Server Column Operations', () {
    late SqlServerAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = SqlServerAdapter();
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      testTableName = 'alter_test';
      
      final connection = DatabaseConnection(
        id: 'test_col_conn',
        name: 'Test Column Connection',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: true),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should add a column', (tester) async {
      if (!ssE2EGatewayReady) {
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
      if (!ssE2EGatewayReady) {
        return;
      }
      final result = await adapter.dropColumn(testTableName, 'name');
      expect(result, isTrue);

      final columns = await adapter.getTableColumns(testTableName);
      final nameCol = columns.where((col) => col.name == 'name');
      expect(nameCol, isEmpty);
    });

    testWidgets('should modify a column', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final modifiedColumn = DbColumn(
        name: 'name',
        type: 'VARCHAR(200)',
        isNullable: false,
      );

      final result = await adapter.modifyColumn(testTableName, 'name', modifiedColumn);
      expect(result, isTrue);

      final columns = await adapter.getTableColumns(testTableName);
      final nameCol = columns.firstWhere((col) => col.name == 'name');
      expect(nameCol.type, contains('200'));
    });
  });

  group('SQL Server Export and AI Operations', () {
    late SqlServerAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = SqlServerAdapter();
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_export_conn',
        name: 'Test Export Connection',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.createTable('users', [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should export database structure', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final structure = await adapter.exportDatabaseStructure(testDbName);

      expect(structure, isNotEmpty);
      expect(structure, contains('CREATE TABLE'));
      expect(structure, contains('users'));
    });

    testWidgets('should get AI schema summary', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final summary = await adapter.getAiSchemaSummary();

      expect(summary, isNotEmpty);
      expect(summary, contains('SQL Server'));
    });

    testWidgets('should execute AI command', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeAiCommand('SELECT COUNT(*) as cnt FROM users');

      expect(result.success, isTrue);
      expect(result.output, isNotEmpty);
    });

    testWidgets('should validate safe command', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('SELECT * FROM users');

      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.safe));
    });

    testWidgets('should validate dangerous command', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('DROP TABLE users');

      expect(result.allowed, isFalse);
      expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
    });

    testWidgets('should validate warning command', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('DELETE FROM users WHERE id = 1');

      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.warning));
    });
  });

  group('SQL Server Connection Management', () {
    late SqlServerAdapter adapter;

    testWidgets('should disconnect cleanly', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      adapter = SqlServerAdapter();
      
      final connection = DatabaseConnection(
        id: 'test_disc_conn',
        name: 'Test Disconnect Connection',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
        database: SQLServerTestConfig.database,
      );
      
      await adapter.connect(connection);
      expect(adapter.isConnected, isTrue);

      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
    });

    testWidgets('should handle multiple connections', (tester) async {
      if (!ssE2EGatewayReady) {
        return;
      }
      final adapter1 = SqlServerAdapter();
      final adapter2 = SqlServerAdapter();

      final conn1 = DatabaseConnection(
        id: 'multi_1',
        name: 'Multi Connection 1',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
        database: SQLServerTestConfig.database,
      );

      final conn2 = DatabaseConnection(
        id: 'multi_2',
        name: 'Multi Connection 2',
        type: DatabaseType.sqlserver,
        host: SQLServerTestConfig.host,
        port: SQLServerTestConfig.port,
        username: SQLServerTestConfig.username,
        password: SQLServerTestConfig.password,
        database: SQLServerTestConfig.database,
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
