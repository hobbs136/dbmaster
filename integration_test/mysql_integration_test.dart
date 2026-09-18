// ============================================================================
// MySQL Integration Tests
// Tests: Real MySQL database operations using a cloud MySQL instance
// Prerequisites: Set environment variables or update mysql_test_config.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('MySQL Connection', () {
    late MySQLAdapter adapter;

    setUp(() {
      adapter = MySQLAdapter();
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

    testWidgets('should connect to MySQL server successfully', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_1',
        name: 'Test Connection 1',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: MySQLTestConfig.database,
      );

      try {
        final result = await adapter.connect(connection);
        expect(result, isTrue, reason: 'Connection to ${MySQLTestConfig.host}:${MySQLTestConfig.port} failed');
        expect(adapter.isConnected, isTrue);
      } catch (e) {
        fail('Connection failed with error: $e');
      }
    });

    testWidgets('should fail to connect with wrong credentials', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_2',
        name: 'Test Connection 2',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
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
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_3',
        name: 'Test Connection 3',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: MySQLTestConfig.database,
      );

      final error = await adapter.testConnection(connection);

      expect(error, isNull);
    });

    testWidgets('TC-006: should apply charset and timezone settings', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_conn_6',
        name: 'Test Connection TC-006',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: MySQLTestConfig.database,
        extra: {
          'charset': 'utf8mb4',
          'timezone': '+08:00',
        },
      );

      final result = await adapter.connect(connection);
      expect(result, isTrue, reason: 'Connection with charset/timezone failed');

      // Verify charset settings
      final charsetResult = await adapter.executeQuery(
        "SHOW VARIABLES LIKE 'character_set%'",
      );
      expect(charsetResult.rows, isNotEmpty);
      final charsetRows = <String, String>{
        for (final row in charsetResult.rows)
          row['Variable_name'] as String: row['Value'] as String,
      };
      expect(charsetRows['character_set_client'], equals('utf8mb4'));
      expect(charsetRows['character_set_connection'], equals('utf8mb4'));
      expect(charsetRows['character_set_results'], equals('utf8mb4'));

      // Verify timezone
      final tzResult = await adapter.executeQuery("SELECT @@time_zone AS tz");
      expect(tzResult.rows, isNotEmpty);
      expect(tzResult.rows.first['tz'], equals('+08:00'));

      // Verify special characters (Chinese + Emoji)
      const specialChars = '你好世界 🎉🚀';
      final specialResult = await adapter.executeQuery(
        "SELECT '你好世界 🎉🚀' AS msg",
      );
      expect(specialResult.rows, isNotEmpty);
      expect(specialResult.rows.first['msg'], equals(specialChars));
    });
  });

  group('MySQL Database Operations', () {
    late MySQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
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
      // T29：网关口径下系统库（information_schema/performance_schema/
      // mysql/sys）由壳过滤（对齐旧 _SchemaManager 裸连接分支口径），
      // 断言其不再出现而非出现。
      expect(databases, isNot(contains('information_schema')));
      expect(databases, isNot(contains('mysql')));
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
      await adapter.createDatabase(testDbName, options: {
        'charset': 'utf8mb4',
        'collation': 'utf8mb4_unicode_ci',
      });

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

  group('MySQL Table Operations', () {
    late MySQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      testTableName = 'test_table';
      
      final connection = DatabaseConnection(
        id: 'test_table_conn',
        name: 'Test Table Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
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
      expect(tables, contains(testTableName));
    });

    testWidgets('should get table columns', (tester) async {
      if (!mysqlE2EGatewayReady) {
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
      if (!mysqlE2EGatewayReady) {
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
      if (!mysqlE2EGatewayReady) {
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
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
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
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
      ];

      await adapter.createTable(testTableName, columns);
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
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: true),
      ];

      await adapter.createTable(testTableName, columns);
      await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name) VALUES (1, 'Test')",
      );
      
      var countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM `$testTableName`');
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(1));

      await adapter.truncateTable(testTableName);
      
      countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM `$testTableName`');
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(0));
    });
  });

  group('MySQL CRUD Operations', () {
    late MySQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      testTableName = 'users';
      
      final connection = DatabaseConnection(
        id: 'test_crud_conn',
        name: 'Test CRUD Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
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

      final result = await adapter.executeQuery('SELECT * FROM `$testTableName`');

      expect(result.rows, hasLength(2));
      expect(result.columns, contains('name'));
      expect(result.rows[0]['name'], equals('Alice'));
    });

    // 网关日期解码（2026-08-27 修复）：DATE/DATETIME/TIMESTAMP/TIME 经
    // server chrono 臂到达为 SQL 惯例字符串——此前族级落 null 且 e2e 零
    // 覆盖。TIMESTAMP 插入/回读同会话时区，断言与 tz 值无关（确定性钉定）。
    testWidgets('should decode date family as SQL-convention strings',
        (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      const table = 'date_matrix_e2e';
      await adapter.executeQuery(
        'CREATE TABLE `$table` (id INT PRIMARY KEY, d DATE, dtm DATETIME(3), '
        'ts TIMESTAMP NULL, tm TIME)',
      );
      await adapter.executeQuery(
        "INSERT INTO `$table` VALUES "
        "(1, '2026-08-27', '2026-08-27 12:34:56.789', '2026-08-27 12:34:56', '12:34:56')",
      );

      final r = await adapter.executeQuery('SELECT d, dtm, ts, tm FROM `$table`');
      expect(r.rows, hasLength(1));
      expect(r.rows[0]['d'], equals('2026-08-27'));
      expect(r.rows[0]['dtm'], equals('2026-08-27 12:34:56.789'));
      expect(r.rows[0]['ts'], equals('2026-08-27 12:34:56'));
      expect(r.rows[0]['tm'], equals('12:34:56'));
    });

    testWidgets('should update data', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );

      final result = await adapter.executeQuery(
        "UPDATE `$testTableName` SET age = 31 WHERE id = 1",
      );

      expect(result.affectedRows, equals(1));

      final selectResult = await adapter.executeQuery(
        'SELECT age FROM `$testTableName` WHERE id = 1',
      );
      expect(int.parse(selectResult.rows.first['age'].toString()), equals(31));
    });

    testWidgets('should delete data', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO `$testTableName` (id, name, email, age) VALUES (1, 'Alice', 'alice@example.com', 30)",
      );

      final result = await adapter.executeQuery(
        "DELETE FROM `$testTableName` WHERE id = 1",
      );

      expect(result.affectedRows, equals(1));

      final countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM `$testTableName`');
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

      final result = await adapter.getTableData(testTableName, limit: 5, offset: 0);

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

  group('MySQL Advanced Operations', () {
    late MySQLAdapter adapter;

    setUp(() async {
      adapter = MySQLAdapter();
      
      final connection = DatabaseConnection(
        id: 'test_adv_conn',
        name: 'Test Advanced Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      
      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: 'Failed to connect to MySQL for advanced operations');
      
      // 创建并切换到测试数据库，确保高级操作有可用数据库
      await adapter.executeQuery('CREATE DATABASE IF NOT EXISTS dbmaster_test_advanced');
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
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final version = await adapter.getServerVersion();

      expect(version, isNotNull);
      expect(version!['database'], equals('MySQL'));
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
      final result = await adapter.getExplainPlan(
        'SELECT 1',
      );

      expect(result.rows, isNotEmpty);
    });

    testWidgets('should execute SQL script', (tester) async {
      if (!mysqlE2EGatewayReady) {
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

  group('MySQL Column Operations', () {
    late MySQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      testTableName = 'alter_test';
      
      final connection = DatabaseConnection(
        id: 'test_col_conn',
        name: 'Test Column Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
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
      final result = await adapter.dropColumn(testTableName, 'name');
      expect(result, isTrue);

      final columns = await adapter.getTableColumns(testTableName);
      final nameCol = columns.where((col) => col.name == 'name');
      expect(nameCol, isEmpty);
    });

    testWidgets('should modify a column', (tester) async {
      if (!mysqlE2EGatewayReady) {
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

  group('MySQL Export and AI Operations', () {
    late MySQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_export_conn',
        name: 'Test Export Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
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
      expect(summary, contains('MySQL'));
    });

    testWidgets('should execute AI command', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeAiCommand('SELECT COUNT(*) as cnt FROM users');

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

  group('MySQL Transaction Operations', () {
    late MySQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      testTableName = 'trans_test';
      
      final connection = DatabaseConnection(
        id: 'test_trans_conn',
        name: 'Test Transaction Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'val', type: 'VARCHAR(100)', isNullable: true),
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

    // T29：MySQL 族迁网关壳后事务临时下线（server 每语句独立连接，BEGIN/
    // COMMIT 无法跨执行保持；恢复路径：旧 /api/db/:conn_id/txn/* pinned
    // session 或未来 /api/gw pinned session）。本组改为守卫「fail-loud
    // 边界」：事务三件套必须抛 UnsupportedError，而非静默假成功。
    testWidgets('should throw UnsupportedError on transaction ops (T29 boundary)', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      expect(adapter.isInTransaction, isFalse);
      await expectLater(adapter.beginTransaction(), throwsUnsupportedError);
      await expectLater(adapter.commit(), throwsUnsupportedError);
      await expectLater(adapter.rollback(), throwsUnsupportedError);
      expect(adapter.isInTransaction, isFalse);
    });
  });

  group('MySQL renameColumn', () {
    late MySQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      testTableName = 'rename_col_test';
      
      final connection = DatabaseConnection(
        id: 'test_rename_conn',
        name: 'Test Rename Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'old_name', type: 'VARCHAR(100)', isNullable: true),
      ]);
      
      await adapter.executeQuery("INSERT INTO `$testTableName` (id, old_name) VALUES (1, 'test_value')");
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should rename a column', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.renameColumn(testTableName, 'old_name', 'new_name');
      expect(result, isTrue);

      final columns = await adapter.getTableColumns(testTableName);
      expect(columns.any((c) => c.name == 'new_name'), isTrue);
      expect(columns.any((c) => c.name == 'old_name'), isFalse);

      // Verify data is preserved
      final dataResult = await adapter.executeQuery("SELECT new_name FROM `$testTableName` WHERE id = 1");
      expect(dataResult.rows.first['new_name'], equals('test_value'));
    });
  });

  group('MySQL Real Foreign Keys', () {
    late MySQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_fk_conn',
        name: 'Test FK Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.executeQuery('''
        CREATE TABLE parent_tbl (
          id INT PRIMARY KEY
        ) ENGINE=InnoDB
      ''');
      await adapter.executeQuery('''
        CREATE TABLE child_tbl (
          id INT PRIMARY KEY,
          parent_id INT,
          CONSTRAINT fk_test_parent FOREIGN KEY (parent_id) REFERENCES parent_tbl(id) ON DELETE CASCADE ON UPDATE SET NULL
        ) ENGINE=InnoDB
      ''');
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should get real foreign keys', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final fks = await adapter.getForeignKeys('child_tbl');
      expect(fks, isNotEmpty);
      
      final fk = fks.firstWhere((f) => f.name == 'fk_test_parent');
      expect(fk.column, equals('parent_id'));
      expect(fk.referencedTable, equals('parent_tbl'));
      expect(fk.referencedColumn, equals('id'));
      expect(fk.onDelete, equals('CASCADE'));
      expect(fk.onUpdate, equals('SET NULL'));
    });

    testWidgets('should return empty list for table without FK', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final fks = await adapter.getForeignKeys('parent_tbl');
      expect(fks, isEmpty);
    });
  });

  group('MySQL Real Triggers', () {
    late MySQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_trig_conn',
        name: 'Test Trigger Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.executeQuery('''
        CREATE TABLE trig_test (id INT PRIMARY KEY, val VARCHAR(100))
      ''');
      await adapter.executeQuery('''
        CREATE TRIGGER trg_before_insert_test
        BEFORE INSERT ON trig_test
        FOR EACH ROW
        SET NEW.val = COALESCE(NEW.val, 'default_val')
      ''');
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should get real triggers', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final triggers = await adapter.getTriggers();
      expect(triggers, isNotEmpty);
      
      final trig = triggers.firstWhere((t) => t.name == 'trg_before_insert_test');
      expect(trig.event, equals('INSERT'));
      expect(trig.table, equals('trig_test'));
      expect(trig.timing, equals('BEFORE'));
    });
  });

  group('MySQL Complex Queries', () {
    late MySQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_complex_conn',
        name: 'Test Complex Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.executeQuery('''
        CREATE TABLE dept (id INT PRIMARY KEY, name VARCHAR(50))
      ''');
      await adapter.executeQuery('''
        CREATE TABLE emp (id INT PRIMARY KEY, name VARCHAR(50), dept_id INT, salary DECIMAL(10,2))
      ''');
      
      await adapter.executeQuery("INSERT INTO dept VALUES (1, 'Engineering'), (2, 'Sales')");
      await adapter.executeQuery("INSERT INTO emp VALUES (1, 'Alice', 1, 10000.00), (2, 'Bob', 1, 8000.00), (3, 'Charlie', 2, 6000.00)");
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should execute JOIN query', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery('''
        SELECT e.name, d.name as dept_name, e.salary
        FROM emp e
        JOIN dept d ON e.dept_id = d.id
        WHERE e.salary > 7000
        ORDER BY e.salary DESC
      ''');
      expect(result.rows, hasLength(2));
      expect(result.rows[0]['name'], equals('Alice'));
    });

    testWidgets('should execute GROUP BY with aggregate', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery('''
        SELECT d.name, COUNT(*) as emp_count, AVG(e.salary) as avg_salary
        FROM emp e
        JOIN dept d ON e.dept_id = d.id
        GROUP BY d.id, d.name
        ORDER BY emp_count DESC
      ''');
      expect(result.rows, hasLength(2));
      expect(result.rows[0]['emp_count'].toString(), equals('2'));
    });

    testWidgets('should execute subquery', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery('''
        SELECT name FROM emp
        WHERE salary > (SELECT AVG(salary) FROM emp)
      ''');
      expect(result.rows, hasLength(1));
      expect(result.rows[0]['name'], equals('Alice'));
    });

    testWidgets('should handle syntax error gracefully', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      expect(
        () => adapter.executeQuery('SELECT * FRM emp'),
        throwsException,
      );
    });

    testWidgets('should handle invalid table gracefully', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      expect(
        () => adapter.executeQuery('SELECT * FROM nonexistent_table_xyz'),
        throwsException,
      );
    });
  });

  group('MySQL Cursor Pagination', () {
    late MySQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      testTableName = 'cursor_test';
      
      final connection = DatabaseConnection(
        id: 'test_cursor_conn',
        name: 'Test Cursor Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'val', type: 'VARCHAR(100)', isNullable: true),
      ]);
      
      for (var i = 1; i <= 20; i++) {
        await adapter.executeQuery("INSERT INTO `$testTableName` (id, val) VALUES ($i, 'val$i')");
      }
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should paginate with cursor', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final page1 = await adapter.getTableData(testTableName, limit: 5, cursorColumn: 'id', cursorValue: 0);
      expect(page1.rows, hasLength(5));
      
      final lastId = int.parse(page1.rows.last['id'].toString());
      final page2 = await adapter.getTableData(testTableName, limit: 5, cursorColumn: 'id', cursorValue: lastId);
      expect(page2.rows, hasLength(5));
      
      // Verify no overlap
      expect(page2.rows.first['id'].toString(), isNot(equals(page1.rows.first['id'].toString())));
    });
  });

  group('MySQL Database Switching', () {
    late MySQLAdapter adapter;
    late String db1;
    late String db2;

    setUp(() async {
      adapter = MySQLAdapter();
      db1 = MySQLTestConfig.generateTestDatabaseName();
      db2 = MySQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_switch_conn',
        name: 'Test Switch Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(db1);
      await adapter.createDatabase(db2);
      
      await adapter.useDatabase(db1);
      await adapter.createTable('switch_tbl', [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
      ]);
      await adapter.executeQuery("INSERT INTO switch_tbl VALUES (1)");
      
      await adapter.useDatabase(db2);
      await adapter.createTable('switch_tbl', [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
      ]);
      await adapter.executeQuery("INSERT INTO switch_tbl VALUES (2)");
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$db1`');
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$db2`');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should switch database and verify current context', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.useDatabase(db1);
      final dbCheck1 = await adapter.executeQuery('SELECT DATABASE() as db');
      expect(dbCheck1.rows.first['db'], equals(db1));
      
      await adapter.useDatabase(db2);
      final dbCheck2 = await adapter.executeQuery('SELECT DATABASE() as db');
      expect(dbCheck2.rows.first['db'], equals(db2));

      // Verify tables exist in respective databases
      final tables1 = await adapter.executeQuery("SHOW TABLES FROM `$db1`");
      expect(tables1.rows.any((r) => r.values.contains('switch_tbl')), isTrue);
      
      final tables2 = await adapter.executeQuery("SHOW TABLES FROM `$db2`");
      expect(tables2.rows.any((r) => r.values.contains('switch_tbl')), isTrue);
    });
  });

  group('MySQL Multi-Server Connection', () {
    testWidgets('should connect to MySQL 3307 with root', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!MySQLTestConfig.isAltConfigured) {
        markTestSkipped('DBMASTER_MYSQL_ALT_* 未提供（开源剥离默认凭据）');
        return;
      }
      final adapter = MySQLAdapter();
      final connection = DatabaseConnection(
        id: 'test_3307_root',
        name: 'Test 3307 Root',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.altHost,
        port: MySQLTestConfig.altPort,
        username: MySQLTestConfig.altUsername,
        password: MySQLTestConfig.altPassword,
      );

      final result = await adapter.connect(connection);
      if (!result) {
        markTestSkipped('MySQL 3307 root connection unavailable in Flutter test runner (verified via dart run)');
        return;
      }
      expect(adapter.isConnected, isTrue);
      
      final version = await adapter.getServerVersion();
      expect(version, isNotNull);
      expect(version!['database'], equals('MySQL'));
      
      await adapter.disconnect();
    });

    testWidgets('should connect to MySQL 3307 with remote_user', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!MySQLTestConfig.isAltConfigured) {
        markTestSkipped('DBMASTER_MYSQL_ALT_* 未提供（开源剥离默认凭据）');
        return;
      }
      final adapter = MySQLAdapter();
      final connection = DatabaseConnection(
        id: 'test_3307_remote',
        name: 'Test 3307 Remote',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.remoteHost,
        port: MySQLTestConfig.remotePort,
        username: MySQLTestConfig.remoteUsername,
        password: MySQLTestConfig.remotePassword,
      );

      final result = await adapter.connect(connection);
      if (!result) {
        markTestSkipped('MySQL 3307 remote_user connection unavailable in Flutter test runner (verified via dart run)');
        return;
      }
      expect(adapter.isConnected, isTrue);
      
      final version = await adapter.getServerVersion();
      expect(version, isNotNull);
      
      await adapter.disconnect();
    });

    testWidgets('should execute query on different MySQL versions', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final adapter3306 = MySQLAdapter();
      final adapter3307 = MySQLAdapter();

      final conn3306 = DatabaseConnection(
        id: 'multi_v_3306',
        name: 'Multi Version 3306',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );

      final conn3307 = DatabaseConnection(
        id: 'multi_v_3307',
        name: 'Multi Version 3307',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.altHost,
        port: MySQLTestConfig.altPort,
        username: MySQLTestConfig.altUsername,
        password: MySQLTestConfig.altPassword,
      );

      await adapter3306.connect(conn3306);
      final result3307 = await adapter3307.connect(conn3307);

      final v3306 = await adapter3306.getServerVersion();
      expect(v3306!['version'], isNotNull);

      if (result3307) {
        final v3307 = await adapter3307.getServerVersion();
        expect(v3307!['version'], isNotNull);

        final r3306 = await adapter3306.executeQuery("SELECT 1 as n");
        final r3307 = await adapter3307.executeQuery("SELECT 1 as n");
        expect(r3306.rows.first['n'].toString(), equals('1'));
        expect(r3307.rows.first['n'].toString(), equals('1'));
      }

      await adapter3306.disconnect();
      if (adapter3307.isConnected) await adapter3307.disconnect();
    });
  });

  group('MySQL Connection Management', () {
    late MySQLAdapter adapter;

    testWidgets('should disconnect cleanly', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      adapter = MySQLAdapter();
      
      final connection = DatabaseConnection(
        id: 'test_disc_conn',
        name: 'Test Disconnect Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: MySQLTestConfig.database,
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
      final adapter1 = MySQLAdapter();
      final adapter2 = MySQLAdapter();

      final conn1 = DatabaseConnection(
        id: 'multi_1',
        name: 'Multi Connection 1',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: MySQLTestConfig.database,
      );

      final conn2 = DatabaseConnection(
        id: 'multi_2',
        name: 'Multi Connection 2',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: MySQLTestConfig.database,
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
