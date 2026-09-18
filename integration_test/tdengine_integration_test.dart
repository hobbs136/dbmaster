// ============================================================================
// TDengine Integration Tests
// Tests: Real TDengine database operations using a TDengine instance
// Prerequisites: Set environment variables or update tdengine_test_config.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/tdengine_adapter.dart';
import 'package:dbmaster/models/tdengine_models.dart';
import 'config/tdengine_test_config.dart';
import 'helpers/td_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // T29 TDengine 批次：TDengine 网关壳硬依赖 dbmaster server 会话（embedded
  // 前置，D6）。二进制不可得时全组以可 grep 的 TD_E2E_SKIP 跳过（无假绿
  // 纪律，对齐 mongo/redis 批次）。
  var tdE2EGatewayReady = false;
  setUpAll(() async {
    tdE2EGatewayReady = await ensureEmbeddedServerForTdE2E();
    if (tdE2EGatewayReady && !TDengineTestConfig.available) {
      // ignore: avoid_print
      print('TD_E2E_SKIP: DBMASTER_TDENGINE_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      tdE2EGatewayReady = false;
    }
  });

  group('TDengine Connection', () {
    late TDengineAdapter adapter;

    setUp(() {
      adapter = TDengineAdapter();
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) {
          await adapter.disconnect();
        }
      } catch (_) {}
    });

    testWidgets('should connect to TDengine server successfully', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'test_td_conn_1',
        name: 'Test TDengine Connection 1',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
        database: TDengineTestConfig.database,
      );

      try {
        final result = await adapter.connect(connection);
        expect(result, isTrue, reason: 'Connection to ${TDengineTestConfig.host}:${TDengineTestConfig.port} failed');
        expect(adapter.isConnected, isTrue);
      } catch (e) {
        fail('Connection failed with error: $e');
      }
    });

    testWidgets('should fail to connect with wrong credentials', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'test_td_conn_2',
        name: 'Test TDengine Connection 2',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: 'wrong_user',
        password: 'wrong_password',
      );

      final result = await adapter.connect(connection);
      expect(result, isFalse);
      expect(adapter.isConnected, isFalse);
    });

    testWidgets('should test connection successfully', (tester) async {
      if (!tdE2EGatewayReady) return;
      final connection = DatabaseConnection(
        id: 'test_td_conn_3',
        name: 'Test TDengine Connection 3',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      final error = await adapter.testConnection(connection);
      expect(error, isNull);
    });
  });

  group('TDengine Database Operations', () {
    late TDengineAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = TDengineAdapter();
      testDbName = TDengineTestConfig.generateTestDatabaseName();

      final connection = DatabaseConnection(
        id: 'test_td_db_conn',
        name: 'Test TDengine DB Connection',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.dropDatabase(testDbName);
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should list databases', (tester) async {
      if (!tdE2EGatewayReady) return;
      final databases = await adapter.getDatabases();
      expect(databases, isA<List<String>>());
    });

    testWidgets('should create and drop a database', (tester) async {
      if (!tdE2EGatewayReady) return;
      final createResult = await adapter.createDatabase(testDbName);
      expect(createResult, isTrue);

      final databases = await adapter.getDatabases();
      expect(databases, contains(testDbName));

      final dropResult = await adapter.dropDatabase(testDbName);
      expect(dropResult, isTrue);

      final databasesAfter = await adapter.getDatabases();
      expect(databasesAfter, isNot(contains(testDbName)));
    });

    testWidgets('should switch to a database', (tester) async {
      if (!tdE2EGatewayReady) return;
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      expect(adapter.currentConnection?.database, equals(testDbName));
    });

    testWidgets('should get database properties', (tester) async {
      if (!tdE2EGatewayReady) return;
      await adapter.createDatabase(testDbName);
      final props = await adapter.getDatabaseProperties(testDbName);
      expect(props, isNotNull);
      expect(props!['name'], equals(testDbName));
    });
  });

  group('TDengine SuperTable Operations', () {
    late TDengineAdapter adapter;
    late String testDbName;
    late String testStName;

    setUp(() async {
      adapter = TDengineAdapter();
      testDbName = TDengineTestConfig.generateTestDatabaseName();
      testStName = TDengineTestConfig.generateTestSuperTableName();

      final connection = DatabaseConnection(
        id: 'test_td_st_conn',
        name: 'Test TDengine ST Connection',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.dropDatabase(testDbName);
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should create a super table', (tester) async {
      if (!tdE2EGatewayReady) return;
      final result = await adapter.createSuperTable(
        name: testStName,
        columns: [
          TdColumn(name: 'ts', type: 'TIMESTAMP'),
          TdColumn(name: 'temperature', type: 'FLOAT'),
          TdColumn(name: 'humidity', type: 'FLOAT'),
        ],
        tags: [
          TdTag(name: 'location', type: 'BINARY(64)'),
          TdTag(name: 'device_id', type: 'BINARY(32)'),
        ],
      );
      expect(result, isTrue);

      final stables = await adapter.getSuperTables();
      final names = stables.map((s) => s.name).toList();
      expect(names, contains(testStName));
    });

    testWidgets('should get super table detail', (tester) async {
      if (!tdE2EGatewayReady) return;
      await adapter.createSuperTable(
        name: testStName,
        columns: [
          TdColumn(name: 'ts', type: 'TIMESTAMP'),
          TdColumn(name: 'value', type: 'DOUBLE'),
        ],
        tags: [
          TdTag(name: 'tag1', type: 'BINARY(32)'),
        ],
      );

      final detail = await adapter.getSuperTableDetail(testStName);
      expect(detail, isNotNull);
      expect(detail!.name, equals(testStName));
      expect(detail.columns, isNotEmpty);
      expect(detail.tags, isNotEmpty);
    });

    testWidgets('should drop a super table', (tester) async {
      if (!tdE2EGatewayReady) return;
      await adapter.createSuperTable(
        name: testStName,
        columns: [
          TdColumn(name: 'ts', type: 'TIMESTAMP'),
          TdColumn(name: 'current', type: 'FLOAT'),
        ],
        tags: [
          TdTag(name: 'groupId', type: 'INT'),
        ],
      );

      final dropResult = await adapter.dropSuperTable(testStName);
      expect(dropResult, isTrue);

      final stables = await adapter.getSuperTables();
      final names = stables.map((s) => s.name).toList();
      expect(names, isNot(contains(testStName)));
    });
  });

  group('TDengine SubTable Operations', () {
    late TDengineAdapter adapter;
    late String testDbName;
    late String testStName;
    late String testSubName;

    setUp(() async {
      adapter = TDengineAdapter();
      testDbName = TDengineTestConfig.generateTestDatabaseName();
      testStName = TDengineTestConfig.generateTestSuperTableName();
      testSubName = TDengineTestConfig.generateTestSubTableName();

      final connection = DatabaseConnection(
        id: 'test_td_sub_conn',
        name: 'Test TDengine Sub Connection',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      // Create super table for sub table tests
      await adapter.createSuperTable(
        name: testStName,
        columns: [
          TdColumn(name: 'ts', type: 'TIMESTAMP'),
          TdColumn(name: 'temperature', type: 'FLOAT'),
        ],
        tags: [
          TdTag(name: 'location', type: 'BINARY(64)'),
        ],
      );
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.dropDatabase(testDbName);
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should create a sub table', (tester) async {
      if (!tdE2EGatewayReady) return;
      final result = await adapter.createSubTable(
        name: testSubName,
        superTableName: testStName,
        tagValues: {'location': 'Beijing'},
      );
      expect(result, isTrue);

      // 子表不在 SHOW STABLES 列表（那是超级表视图）；TBNAME 是扫描型
      // 伪列——空子表不出行，先插一行再断言（实机钉定）。
      await adapter.executeQuery('INSERT INTO $testSubName VALUES (NOW, 23.5)');
      final subTables = await adapter.executeQuery(
        'SELECT TBNAME FROM $testStName LIMIT 100',
      );
      final names = subTables.rows
          .map((r) => r.values.firstOrNull?.toString() ?? '')
          .toList();
      expect(names, contains(testSubName));
    });

    testWidgets('should insert and query data in sub table', (tester) async {
      if (!tdE2EGatewayReady) return;
      await adapter.createSubTable(
        name: testSubName,
        superTableName: testStName,
        tagValues: {'location': 'Shanghai'},
      );

      // Insert data
      final insertResult = await adapter.executeQuery(
        "INSERT INTO $testSubName VALUES (NOW, 23.5)",
      );
      expect(insertResult.rows, isNotNull);

      // Query data
      final queryResult = await adapter.executeQuery(
        'SELECT * FROM $testSubName LIMIT 10',
      );
      expect(queryResult.rows, isNotEmpty);
      expect(queryResult.columns, contains('temperature'));
    });

    testWidgets('should drop a sub table', (tester) async {
      if (!tdE2EGatewayReady) return;
      await adapter.createSubTable(
        name: testSubName,
        superTableName: testStName,
        tagValues: {'location': 'Guangzhou'},
      );

      final dropResult = await adapter.dropSubTable(testSubName);
      expect(dropResult, isTrue);

      final tables = await adapter.getTables();
      expect(tables, isNot(contains(testSubName)));
    });
  });

  group('TDengine Query Operations', () {
    late TDengineAdapter adapter;
    late String testDbName;
    late String testStName;
    late String testSubName;

    setUp(() async {
      adapter = TDengineAdapter();
      testDbName = TDengineTestConfig.generateTestDatabaseName();
      testStName = TDengineTestConfig.generateTestSuperTableName();
      testSubName = TDengineTestConfig.generateTestSubTableName();

      final connection = DatabaseConnection(
        id: 'test_td_query_conn',
        name: 'Test TDengine Query Connection',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.createSuperTable(
        name: testStName,
        columns: [
          TdColumn(name: 'ts', type: 'TIMESTAMP'),
          TdColumn(name: 'current', type: 'FLOAT'),
          TdColumn(name: 'voltage', type: 'INT'),
        ],
        tags: [
          TdTag(name: 'device', type: 'BINARY(32)'),
        ],
      );

      await adapter.createSubTable(
        name: testSubName,
        superTableName: testStName,
        tagValues: {'device': 'meter_01'},
      );

      // Insert test data
      for (var i = 0; i < 5; i++) {
        await adapter.executeQuery(
          "INSERT INTO $testSubName VALUES (NOW + ${i}s, ${10.0 + i}, ${220 + i})",
        );
      }
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.dropDatabase(testDbName);
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should execute SELECT query', (tester) async {
      if (!tdE2EGatewayReady) return;
      final result = await adapter.executeQuery(
        'SELECT * FROM $testSubName LIMIT 10',
      );
      expect(result.rows, isNotEmpty);
      expect(result.columns, isNotEmpty);
    });

    testWidgets('should get table data with pagination', (tester) async {
      if (!tdE2EGatewayReady) return;
      final result = await adapter.getTableData(testSubName, limit: 3, offset: 0);
      expect(result.rows.length, lessThanOrEqualTo(3));
    });

    testWidgets('should get table row count', (tester) async {
      if (!tdE2EGatewayReady) return;
      final count = await adapter.getTableRowCount(testSubName);
      expect(count, equals(5));
    });

    testWidgets('should get table columns', (tester) async {
      if (!tdE2EGatewayReady) return;
      final columns = await adapter.getTableColumns(testSubName);
      expect(columns, isNotEmpty);
      expect(columns.map((c) => c.name), contains('ts'));
      expect(columns.map((c) => c.name), contains('current'));
    });

    testWidgets('should get table indexes', (tester) async {
      if (!tdE2EGatewayReady) return;
      final indexes = await adapter.getTableIndexes(testSubName);
      expect(indexes, isNotEmpty);
    });

    testWidgets('should get explain plan', (tester) async {
      if (!tdE2EGatewayReady) return;
      final result = await adapter.getExplainPlan('SELECT * FROM $testSubName');
      expect(result.columns, contains('info'));
    });
  });

  group('TDengine Server Info', () {
    late TDengineAdapter adapter;

    setUp(() async {
      adapter = TDengineAdapter();

      final connection = DatabaseConnection(
        id: 'test_td_info_conn',
        name: 'Test TDengine Info Connection',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      await adapter.connect(connection);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
    });

    testWidgets('should get server version', (tester) async {
      if (!tdE2EGatewayReady) return;
      final version = await adapter.getServerVersion();
      expect(version, isNotNull);
      expect(version!['database'], equals('TDengine'));
    });

    testWidgets('should get charsets', (tester) async {
      if (!tdE2EGatewayReady) return;
      final charsets = await adapter.getCharsets();
      expect(charsets, isNotEmpty);
      expect(charsets, contains('UTF-8'));
    });

    testWidgets('should get empty collations', (tester) async {
      if (!tdE2EGatewayReady) return;
      final collations = await adapter.getCollations();
      expect(collations, isEmpty);
    });

    testWidgets('should get empty views', (tester) async {
      if (!tdE2EGatewayReady) return;
      final views = await adapter.getViews();
      expect(views, isEmpty);
    });

    testWidgets('should get empty procedures', (tester) async {
      if (!tdE2EGatewayReady) return;
      final procedures = await adapter.getProcedures();
      expect(procedures, isEmpty);
    });

    testWidgets('should get empty functions', (tester) async {
      if (!tdE2EGatewayReady) return;
      final functions = await adapter.getFunctions();
      expect(functions, isEmpty);
    });

    testWidgets('should get empty events', (tester) async {
      if (!tdE2EGatewayReady) return;
      final events = await adapter.getEvents();
      expect(events, isEmpty);
    });

    testWidgets('should get empty triggers', (tester) async {
      if (!tdE2EGatewayReady) return;
      final triggers = await adapter.getTriggers();
      expect(triggers, isEmpty);
    });

    testWidgets('should get empty foreign keys', (tester) async {
      if (!tdE2EGatewayReady) return;
      final fks = await adapter.getForeignKeys('any_table');
      expect(fks, isEmpty);
    });
  });

  group('TDengine Export and Script', () {
    late TDengineAdapter adapter;
    late String testDbName;
    late String testStName;

    setUp(() async {
      adapter = TDengineAdapter();
      testDbName = TDengineTestConfig.generateTestDatabaseName();
      testStName = TDengineTestConfig.generateTestSuperTableName();

      final connection = DatabaseConnection(
        id: 'test_td_export_conn',
        name: 'Test TDengine Export Connection',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);

      await adapter.createSuperTable(
        name: testStName,
        columns: [
          TdColumn(name: 'ts', type: 'TIMESTAMP'),
          TdColumn(name: 'value', type: 'DOUBLE'),
        ],
        tags: [
          TdTag(name: 'name', type: 'BINARY(32)'),
        ],
      );
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.dropDatabase(testDbName);
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should export database structure', (tester) async {
      if (!tdE2EGatewayReady) return;
      final structure = await adapter.exportDatabaseStructure(testDbName);
      expect(structure, isNotEmpty);
      expect(structure, contains('TDengine Database Export'));
      expect(structure, contains('CREATE STABLE'));
    });

    testWidgets('should execute SQL script', (tester) async {
      if (!tdE2EGatewayReady) return;
      final script = '''
-- Comment line
CREATE TABLE t1 USING $testStName TAGS ('test');
'''.trim();

      final result = await adapter.executeSqlScript(script);
      expect(result, isTrue);
    });
  });

  group('TDengine Security', () {
    testWidgets('should validate safe command', (tester) async {
      if (!tdE2EGatewayReady) return;
      final adapter = TDengineAdapter();
      final result = adapter.validateCommand('SELECT * FROM meter');
      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.safe));
    });

    testWidgets('should validate dangerous command', (tester) async {
      if (!tdE2EGatewayReady) return;
      final adapter = TDengineAdapter();
      final result = adapter.validateCommand('DROP DATABASE test');
      expect(result.allowed, isFalse);
      expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
    });

    testWidgets('should validate warning command', (tester) async {
      if (!tdE2EGatewayReady) return;
      final adapter = TDengineAdapter();
      final result = adapter.validateCommand('INSERT INTO t VALUES (NOW, 1)');
      expect(result.allowed, isTrue);
      expect(result.riskLevel, equals(CommandRiskLevel.warning));
    });
  });

  group('TDengine AI Operations', () {
    late TDengineAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = TDengineAdapter();
      testDbName = TDengineTestConfig.generateTestDatabaseName();

      final connection = DatabaseConnection(
        id: 'test_td_ai_conn',
        name: 'Test TDengine AI Connection',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      await adapter.connect(connection);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.dropDatabase(testDbName);
        } catch (_) {}
        await adapter.disconnect();
      }
    });

    testWidgets('should get AI schema summary', (tester) async {
      if (!tdE2EGatewayReady) return;
      final summary = await adapter.getAiSchemaSummary();
      expect(summary, isNotEmpty);
      expect(summary, contains('TDengine'));
    });

    testWidgets('should execute AI command', (tester) async {
      if (!tdE2EGatewayReady) return;
      final result = await adapter.executeAiCommand('SHOW DATABASES');
      expect(result.success, isTrue);
    });
  });

  group('TDengine Connection Management', () {
    testWidgets('should disconnect cleanly', (tester) async {
      if (!tdE2EGatewayReady) return;
      final adapter = TDengineAdapter();

      final connection = DatabaseConnection(
        id: 'test_td_disc_conn',
        name: 'Test TDengine Disconnect Connection',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      await adapter.connect(connection);
      expect(adapter.isConnected, isTrue);

      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
    });

    testWidgets('should handle multiple connections', (tester) async {
      if (!tdE2EGatewayReady) return;
      final adapter1 = TDengineAdapter();
      final adapter2 = TDengineAdapter();

      final conn1 = DatabaseConnection(
        id: 'multi_1',
        name: 'Multi Connection 1',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
      );

      final conn2 = DatabaseConnection(
        id: 'multi_2',
        name: 'Multi Connection 2',
        type: DatabaseType.tdengine,
        host: TDengineTestConfig.host,
        port: TDengineTestConfig.port,
        username: TDengineTestConfig.username,
        password: TDengineTestConfig.password,
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
