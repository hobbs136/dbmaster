// ============================================================================
// PostgreSQL Integration Tests
// Tests: Real PostgreSQL database operations using a cloud PostgreSQL instance
// Prerequisites: Set environment variables or update postgresql_test_config.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'config/postgresql_test_config.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

void main() {

  // T29 第二批：PG 网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 PG_E2E_SKIP 跳过（无假绿）。
  bool pgE2EGatewayReady = false;
  setUpAll(() async {
    pgE2EGatewayReady = await ensureEmbeddedServerForPgE2E();
    if (pgE2EGatewayReady && !PostgreSQLTestConfig.available) {
      // ignore: avoid_print
      print('PG_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      pgE2EGatewayReady = false;
    }
  });
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('PostgreSQL Connection', () {
    late PostgreSQLAdapter adapter;

    setUp(() {
      adapter = PostgreSQLAdapter();
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

    testWidgets('should connect to PostgreSQL server successfully', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_pg_conn_1',
        name: 'Test PG Connection 1',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );

      try {
        final result = await adapter.connect(connection);
        expect(result, isTrue, reason: 'Connection to ${PostgreSQLTestConfig.host}:${PostgreSQLTestConfig.port} failed');
        expect(adapter.isConnected, isTrue);
      } catch (e) {
        fail('Connection failed with error: $e');
      }
    });

    testWidgets('should fail to connect with wrong credentials', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_pg_conn_2',
        name: 'Test PG Connection 2',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
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
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_pg_conn_3',
        name: 'Test PG Connection 3',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );

      final error = await adapter.testConnection(connection);

      expect(error, isNull);
    });
  });

  group('PostgreSQL Database Operations', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_pg_db_conn',
        name: 'Test PG DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          // Disconnect from test db if connected
          await adapter.disconnect();
          
          // Reconnect to postgres to drop test database
          final cleanupConnection = DatabaseConnection(
            id: 'cleanup_conn',
            name: 'Cleanup Connection',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: 'postgres',
          );
          await adapter.connect(cleanupConnection);
          await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should create a new database', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final result = await adapter.createDatabase(testDbName);

      expect(result, isTrue);

      final databases = await adapter.getDatabases();
      expect(databases, contains(testDbName));
    });

    testWidgets('should list all databases', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final databases = await adapter.getDatabases();

      expect(databases, isNotEmpty);
      expect(databases, contains('postgres'));
    });

    testWidgets('should get database properties', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await adapter.createDatabase(testDbName, options: {
        'encoding': 'UTF8',
      });

      final props = await adapter.getDatabaseProperties(testDbName);

      expect(props, isNotNull);
      expect(props!['name'], equals(testDbName));
      expect(props['encoding'], isNotNull);
    });

    testWidgets('should drop a database', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await adapter.createDatabase(testDbName);
      
      // Need to disconnect from the database before dropping it
      await adapter.disconnect();
      
      // Reconnect to postgres database to drop
      final postgresConn = DatabaseConnection(
        id: 'drop_conn',
        name: 'Drop Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      await adapter.connect(postgresConn);
      
      final result = await adapter.dropDatabase(testDbName);

      expect(result, isTrue);

      final databases = await adapter.getDatabases();
      expect(databases, isNot(contains(testDbName)));
    });
  });

  group('PostgreSQL Table Operations', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      testTableName = 'test_table';
      
      final connection = DatabaseConnection(
        id: 'test_pg_table_conn',
        name: 'Test PG Table Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      // Reconnect to the test database
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
        
        // Cleanup: reconnect to postgres and drop test db
        try {
          final cleanupConnection = DatabaseConnection(
            id: 'cleanup_conn',
            name: 'Cleanup Connection',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: 'postgres',
          );
          await adapter.connect(cleanupConnection);
          await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should create a table with columns', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(
          name: 'id',
          type: 'SERIAL',
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
          type: 'TIMESTAMP',
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
      if (!pgE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
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
      if (!pgE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
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
      if (!pgE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
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
      if (!pgE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
      ];

      await adapter.createTable(testTableName, columns);
      final result = await adapter.dropTable(testTableName);

      expect(result, isTrue);

      final tables = await adapter.getTables();
      expect(tables, isNot(contains(testTableName)));
    });

    testWidgets('should rename a table', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final newName = 'renamed_table';
      final columns = [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
      ];

      await adapter.createTable(testTableName, columns);
      final result = await adapter.renameTable(testTableName, newName);

      expect(result, isTrue);

      final tables = await adapter.getTables();
      expect(tables, contains(newName));
      expect(tables, isNot(contains(testTableName)));
    });

    testWidgets('should truncate a table', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final columns = [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: true),
      ];

      await adapter.createTable(testTableName, columns);
      await adapter.executeQuery(
        "INSERT INTO \"$testTableName\" (name) VALUES ('Test')",
      );
      
      var countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM "$testTableName"');
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(1));

      await adapter.truncateTable(testTableName);
      
      countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM "$testTableName"');
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(0));
    });
  });

  group('PostgreSQL CRUD Operations', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      testTableName = 'users';
      
      final connection = DatabaseConnection(
        id: 'test_pg_crud_conn',
        name: 'Test PG CRUD Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      // Reconnect to the test database
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
        DbColumn(name: 'age', type: 'INTEGER', isNullable: true),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
        
        try {
          final cleanupConnection = DatabaseConnection(
            id: 'cleanup_conn',
            name: 'Cleanup Connection',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: 'postgres',
          );
          await adapter.connect(cleanupConnection);
          await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should insert data', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final result = await adapter.executeQuery(
        "INSERT INTO \"$testTableName\" (name, email, age) VALUES ('Alice', 'alice@example.com', 30)",
      );

      expect(result.affectedRows, equals(1));
    });

    testWidgets('should select data', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO \"$testTableName\" (name, email, age) VALUES ('Alice', 'alice@example.com', 30)",
      );
      await adapter.executeQuery(
        "INSERT INTO \"$testTableName\" (name, email, age) VALUES ('Bob', 'bob@example.com', 25)",
      );

      final result = await adapter.executeQuery('SELECT * FROM "$testTableName"');

      expect(result.rows, hasLength(2));
      expect(result.columns, contains('name'));
      expect(result.rows[0]['name'], equals('Alice'));
    });

    // 网关日期解码（2026-08-27 修复）：timestamp/timestamptz/date/time/uuid
    // 经 server chrono/uuid 臂到达为字符串——此前归一为 null（适配器头注
    // 已登记边界）。TIMESTAMPTZ 按 UTC 墙钟渲染（服务端无客户端时区），
    // 用零偏移字面量钉定；gen_random_uuid() 需 pgcrypto/13+ 内建。
    testWidgets('should decode timestamp/uuid family as strings',
        (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final r = await adapter.executeQuery(
        "SELECT DATE '2026-08-27' AS d, "
        "TIMESTAMP '2026-08-27 12:34:56.789' AS ts, "
        "TIMESTAMPTZ '2026-08-27 12:34:56+00' AS tstz, "
        "TIME '12:34:56' AS tm, "
        "'123e4567-e89b-12d3-a456-426614174000'::uuid AS uu",
      );
      expect(r.rows, hasLength(1));
      expect(r.rows[0]['d'], equals('2026-08-27'));
      expect(r.rows[0]['ts'], equals('2026-08-27 12:34:56.789'));
      expect(r.rows[0]['tstz'], equals('2026-08-27 12:34:56'));
      expect(r.rows[0]['tm'], equals('12:34:56'));
      expect(r.rows[0]['uu'],
          equals('123e4567-e89b-12d3-a456-426614174000'));
    });

    testWidgets('should update data', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO \"$testTableName\" (name, email, age) VALUES ('Alice', 'alice@example.com', 30)",
      );

      final result = await adapter.executeQuery(
        "UPDATE \"$testTableName\" SET age = 31 WHERE name = 'Alice'",
      );

      expect(result.affectedRows, equals(1));

      final selectResult = await adapter.executeQuery(
        "SELECT age FROM \"$testTableName\" WHERE name = 'Alice'",
      );
      expect(int.parse(selectResult.rows.first['age'].toString()), equals(31));
    });

    testWidgets('should delete data', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery(
        "INSERT INTO \"$testTableName\" (name, email, age) VALUES ('Alice', 'alice@example.com', 30)",
      );

      final result = await adapter.executeQuery(
        "DELETE FROM \"$testTableName\" WHERE name = 'Alice'",
      );

      expect(result.affectedRows, equals(1));

      final countResult = await adapter.executeQuery('SELECT COUNT(*) as cnt FROM "$testTableName"');
      expect(int.parse(countResult.rows.first['cnt'].toString()), equals(0));
    });

    testWidgets('should get table data with pagination', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      for (var i = 1; i <= 10; i++) {
        await adapter.executeQuery(
          "INSERT INTO \"$testTableName\" (name, email, age) VALUES ('User$i', 'user$i@example.com', 20 + $i)",
        );
      }

      final result = await adapter.getTableData(testTableName, limit: 5, offset: 0);

      expect(result.rows, hasLength(5));
    });

    testWidgets('should get table row count', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      for (var i = 1; i <= 5; i++) {
        await adapter.executeQuery(
          "INSERT INTO \"$testTableName\" (name, email, age) VALUES ('User$i', 'user$i@example.com', 20 + $i)",
        );
      }

      final count = await adapter.getTableRowCount(testTableName);

      expect(count, equals(5));
    });
  });

  group('PostgreSQL Advanced Operations', () {
    late PostgreSQLAdapter adapter;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      
      final connection = DatabaseConnection(
        id: 'test_pg_adv_conn',
        name: 'Test PG Advanced Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
    });

    testWidgets('should get server version', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final version = await adapter.getServerVersion();

      expect(version, isNotNull);
      expect(version!['database'], equals('PostgreSQL'));
      expect(version['version'], isNotNull);
    });

    testWidgets('should get charsets', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final charsets = await adapter.getCharsets();

      expect(charsets, isNotEmpty);
      expect(charsets, contains('UTF8'));
    });

    testWidgets('should get collations', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final collations = await adapter.getCollations(charset: 'UTF8');

      expect(collations, isNotEmpty);
    });

    testWidgets('should execute complex SQL query', (tester) async {
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
        return;
      }
      final result = await adapter.getExplainPlan(
        'SELECT 1',
      );

      expect(result.rows, isNotEmpty);
    });

    testWidgets('should execute SQL script', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final script = '''
        DROP TABLE IF EXISTS script_test;
        CREATE TABLE script_test (id SERIAL PRIMARY KEY);
        INSERT INTO script_test DEFAULT VALUES;
        INSERT INTO script_test DEFAULT VALUES;
      ''';

      try {
        final result = await adapter.executeSqlScript(script);
        expect(result, isTrue);
      } catch (e) {
        fail('SQL script execution failed: $e');
      }
    });

    testWidgets('should get views list', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final views = await adapter.getViews();
      expect(views, isA<List<String>>());
    });

    testWidgets('should get procedures list', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final procedures = await adapter.getProcedures();
      expect(procedures, isA<List<String>>());
    });

    testWidgets('should get functions list', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final functions = await adapter.getFunctions();
      expect(functions, isA<List<String>>());
    });
  });

  group('PostgreSQL Column Operations', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      testTableName = 'alter_test';
      
      final connection = DatabaseConnection(
        id: 'test_pg_col_conn',
        name: 'Test PG Column Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      // Reconnect to the test database
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: true),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
        
        try {
          final cleanupConnection = DatabaseConnection(
            id: 'cleanup_conn',
            name: 'Cleanup Connection',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: 'postgres',
          );
          await adapter.connect(cleanupConnection);
          await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should add a column', (tester) async {
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
        return;
      }
      final result = await adapter.dropColumn(testTableName, 'name');
      expect(result, isTrue);

      final columns = await adapter.getTableColumns(testTableName);
      final nameCol = columns.where((col) => col.name == 'name');
      expect(nameCol, isEmpty);
    });

    testWidgets('should modify a column', (tester) async {
      if (!pgE2EGatewayReady) {
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

  group('PostgreSQL Export and AI Operations', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_pg_export_conn',
        name: 'Test PG Export Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      // Reconnect to the test database
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.createTable('users', [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
        
        try {
          final cleanupConnection = DatabaseConnection(
            id: 'cleanup_conn',
            name: 'Cleanup Connection',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: 'postgres',
          );
          await adapter.connect(cleanupConnection);
          await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should export database structure', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final structure = await adapter.exportDatabaseStructure(testDbName);

      expect(structure, isNotEmpty);
      expect(structure, contains('CREATE TABLE'));
      expect(structure, contains('users'));
    });

    testWidgets('should get AI schema summary', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final summary = await adapter.getAiSchemaSummary();

      expect(summary, isNotEmpty);
      expect(summary, contains('PostgreSQL'));
    });

    testWidgets('should execute AI command', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      await adapter.executeQuery("INSERT INTO \"users\" (name) VALUES ('Test User')");
      
      final result = await adapter.executeAiCommand('SELECT COUNT(*) as cnt FROM users');

      expect(result.success, isTrue);
      expect(result.output, isNotEmpty);
    });

    testWidgets('should validate safe command', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('SELECT * FROM users');

      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.safe));
    });

    testWidgets('should validate dangerous command', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('DROP TABLE users');

      expect(result.allowed, isFalse);
      expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
    });

    testWidgets('should validate warning command', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final result = adapter.validateCommand('DELETE FROM users WHERE id = 1');

      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.warning));
    });
  });

  group('PostgreSQL Transaction Operations', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      testTableName = 'trans_test';
      
      final connection = DatabaseConnection(
        id: 'test_pg_trans_conn',
        name: 'Test PG Transaction Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'val', type: 'VARCHAR(100)', isNullable: true),
      ]);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
      try {
        final cleanupConnection = DatabaseConnection(
          id: 'cleanup_conn',
          name: 'Cleanup Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        );
        await adapter.connect(cleanupConnection);
        await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
      } catch (_) {}
      await adapter.disconnect();
    });

    // T29 第二批：PG 迁网关壳后事务临时下线（server 每语句独立连接，
    // BEGIN/COMMIT 无法跨执行保持；恢复路径：旧 /api/db/:conn_id/txn/*
    // pinned session 或未来 /api/gw pinned session）。本组改为守卫
    // 「fail-loud 边界」：事务三件套必须抛 UnsupportedError，而非静默
    // 假成功（与 MySQL 族首批同口径）。
    testWidgets('should throw UnsupportedError on transaction ops (T29 boundary)', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      expect(adapter.isInTransaction, isFalse);
      await expectLater(adapter.beginTransaction(), throwsUnsupportedError);
      await expectLater(adapter.commit(), throwsUnsupportedError);
      await expectLater(adapter.rollback(), throwsUnsupportedError);
      expect(adapter.isInTransaction, isFalse);
    });
  });

  group('PostgreSQL renameColumn', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      testTableName = 'rename_col_test';
      
      final connection = DatabaseConnection(
        id: 'test_pg_rename_conn',
        name: 'Test PG Rename Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'SERIAL', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'old_name', type: 'VARCHAR(100)', isNullable: true),
      ]);
      
      await adapter.executeQuery("INSERT INTO \"$testTableName\" (old_name) VALUES ('test_value')");
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
      try {
        final cleanupConnection = DatabaseConnection(
          id: 'cleanup_conn',
          name: 'Cleanup Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        );
        await adapter.connect(cleanupConnection);
        await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
      } catch (_) {}
      await adapter.disconnect();
    });

    testWidgets('should rename a column', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final result = await adapter.renameColumn(testTableName, 'old_name', 'new_name');
      expect(result, isTrue);

      final columns = await adapter.getTableColumns(testTableName);
      expect(columns.any((c) => c.name == 'new_name'), isTrue);
      expect(columns.any((c) => c.name == 'old_name'), isFalse);

      // Verify data is preserved
      final dataResult = await adapter.executeQuery("SELECT new_name FROM \"$testTableName\" WHERE new_name = 'test_value'");
      expect(dataResult.rows, hasLength(1));
    });
  });

  group('PostgreSQL Real Foreign Keys', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_pg_fk_conn',
        name: 'Test PG FK Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.executeQuery('''
        CREATE TABLE parent_tbl (
          id INTEGER PRIMARY KEY
        )
      ''');
      await adapter.executeQuery('''
        CREATE TABLE child_tbl (
          id INTEGER PRIMARY KEY,
          parent_id INTEGER,
          CONSTRAINT fk_test_parent FOREIGN KEY (parent_id) REFERENCES parent_tbl(id) ON DELETE CASCADE
        )
      ''');
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
      try {
        final cleanupConnection = DatabaseConnection(
          id: 'cleanup_conn',
          name: 'Cleanup Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        );
        await adapter.connect(cleanupConnection);
        await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
      } catch (_) {}
      await adapter.disconnect();
    });

    testWidgets('should get real foreign keys', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final fks = await adapter.getForeignKeys('child_tbl');
      expect(fks, isNotEmpty);
      
      final fk = fks.firstWhere((f) => f.name == 'fk_test_parent');
      expect(fk.column, equals('parent_id'));
      expect(fk.referencedTable, equals('parent_tbl'));
      expect(fk.referencedColumn, equals('id'));
    });

    testWidgets('should return empty list for table without FK', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final fks = await adapter.getForeignKeys('parent_tbl');
      expect(fks, isEmpty);
    });
  });

  group('PostgreSQL Real Triggers', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_pg_trig_conn',
        name: 'Test PG Trigger Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.executeQuery('''
        CREATE TABLE trig_test (id INTEGER PRIMARY KEY, val VARCHAR(100))
      ''');
      await adapter.executeQuery('''
        CREATE OR REPLACE FUNCTION set_default_val()
        RETURNS TRIGGER AS \$\$
        BEGIN
          NEW.val := COALESCE(NEW.val, 'default_val');
          RETURN NEW;
        END;
        \$\$ LANGUAGE plpgsql;
      ''');
      await adapter.executeQuery('''
        CREATE TRIGGER trg_before_insert_test
        BEFORE INSERT ON trig_test
        FOR EACH ROW
        EXECUTE FUNCTION set_default_val()
      ''');
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
      try {
        final cleanupConnection = DatabaseConnection(
          id: 'cleanup_conn',
          name: 'Cleanup Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        );
        await adapter.connect(cleanupConnection);
        await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
      } catch (_) {}
      await adapter.disconnect();
    });

    testWidgets('should get real triggers', (tester) async {
      if (!pgE2EGatewayReady) {
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

  group('PostgreSQL Complex Queries', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      
      final connection = DatabaseConnection(
        id: 'test_pg_complex_conn',
        name: 'Test PG Complex Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.executeQuery('''
        CREATE TABLE dept (id INTEGER PRIMARY KEY, name VARCHAR(50))
      ''');
      await adapter.executeQuery('''
        CREATE TABLE emp (id INTEGER PRIMARY KEY, name VARCHAR(50), dept_id INTEGER, salary NUMERIC(10,2))
      ''');
      
      await adapter.executeQuery("INSERT INTO dept VALUES (1, 'Engineering'), (2, 'Sales')");
      await adapter.executeQuery("INSERT INTO emp VALUES (1, 'Alice', 1, 10000.00), (2, 'Bob', 1, 8000.00), (3, 'Charlie', 2, 6000.00)");
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
      try {
        final cleanupConnection = DatabaseConnection(
          id: 'cleanup_conn',
          name: 'Cleanup Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        );
        await adapter.connect(cleanupConnection);
        await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
      } catch (_) {}
      await adapter.disconnect();
    });

    testWidgets('should execute JOIN query', (tester) async {
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
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
      if (!pgE2EGatewayReady) {
        return;
      }
      expect(
        () => adapter.executeQuery('SELECT * FRM emp'),
        throwsException,
      );
    });

    testWidgets('should handle invalid table gracefully', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      expect(
        () => adapter.executeQuery('SELECT * FROM nonexistent_table_xyz'),
        throwsException,
      );
    });
  });

  group('PostgreSQL Cursor Pagination', () {
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late String testTableName;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      testTableName = 'cursor_test';
      
      final connection = DatabaseConnection(
        id: 'test_pg_cursor_conn',
        name: 'Test PG Cursor Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      
      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();
      
      final testDbConnection = DatabaseConnection(
        id: 'test_db_conn',
        name: 'Test DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConnection);
      
      await adapter.createTable(testTableName, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'val', type: 'VARCHAR(100)', isNullable: true),
      ]);
      
      for (var i = 1; i <= 20; i++) {
        await adapter.executeQuery("INSERT INTO \"$testTableName\" (id, val) VALUES ($i, 'val$i')");
      }
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
      try {
        final cleanupConnection = DatabaseConnection(
          id: 'cleanup_conn',
          name: 'Cleanup Connection',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: 'postgres',
        );
        await adapter.connect(cleanupConnection);
        await adapter.executeQuery('DROP DATABASE IF EXISTS "$testDbName"');
      } catch (_) {}
      await adapter.disconnect();
    });

    testWidgets('should paginate with cursor', (tester) async {
      if (!pgE2EGatewayReady) {
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

  group('PostgreSQL Events', () {
    late PostgreSQLAdapter adapter;

    setUp(() async {
      adapter = PostgreSQLAdapter();
      if (!pgE2EGatewayReady) {
        return;
      }
      final connection = DatabaseConnection(
        id: 'test_pg_events_conn',
        name: 'Test PG Events Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );
      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
    });

    testWidgets('should return empty events list', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final events = await adapter.getEvents();
      expect(events, isEmpty);
    });
  });

  group('PostgreSQL Connection Management', () {
    late PostgreSQLAdapter adapter;

    testWidgets('should disconnect cleanly', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      adapter = PostgreSQLAdapter();
      
      final connection = DatabaseConnection(
        id: 'test_pg_disc_conn',
        name: 'Test PG Disconnect Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );
      
      await adapter.connect(connection);
      expect(adapter.isConnected, isTrue);

      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
    });

    testWidgets('should handle multiple connections', (tester) async {
      if (!pgE2EGatewayReady) {
        return;
      }
      final adapter1 = PostgreSQLAdapter();
      final adapter2 = PostgreSQLAdapter();

      final conn1 = DatabaseConnection(
        id: 'multi_1',
        name: 'Multi Connection 1',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );

      final conn2 = DatabaseConnection(
        id: 'multi_2',
        name: 'Multi Connection 2',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
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
