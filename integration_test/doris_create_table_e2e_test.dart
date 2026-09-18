// ============================================================================
// Doris Create-Table E2E Tests
// Tests: Real Doris instance CREATE TABLE behavior for DUPLICATE/UNIQUE models
//        and verifies no MySQL-style ENGINE= clause leaks into generated DDL.
// Prerequisites: Set environment variables or rely on doris_test_config.dart
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/doris_adapter.dart';
import 'config/doris_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// MySQL-specific storage engines that must never leak into Doris DDL.
const _mysqlEngines = <String>[
  'INNODB',
  'MYISAM',
  'MEMORY',
  'ARCHIVE',
  'CSV',
  'BLACKHOLE',
  'FEDERATED',
  'MRG_MYISAM',
  'NDB',
];

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

  group('Doris Create Table E2E', () {
    late DorisAdapter adapter;
    late String testDbName;
    var skipRemaining = false;

    setUp(() async {
      adapter = DorisAdapter();
      testDbName = DorisTestConfig.generateTestDatabaseName();

      final connection = DatabaseConnection(
        id: 'doris_create_table_e2e',
        name: 'Doris Create Table E2E',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      try {
        final connected = await adapter.connect(connection);
        if (!connected || !adapter.isConnected) {
          skipRemaining = true;
          return;
        }
        await adapter.createDatabase(testDbName);
        await adapter.useDatabase(testDbName);
      } catch (e) {
        skipRemaining = true;
      }
    });

    tearDown(() async {
      if (adapter.isConnected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {
          // Ignore cleanup errors so they do not mask real test failures.
        }
        try {
          await adapter.disconnect();
        } catch (_) {
          // Ignore disconnect errors.
        }
      }
    });

    void skipIfNeeded() {
      if (skipRemaining) {
        markTestSkipped(
          'Doris test instance at ${DorisTestConfig.host}:${DorisTestConfig.port} is not reachable',
        );
      }
    }

    void assertNoMySqlEngine(String ddl, String reason) {
      final upper = ddl.toUpperCase();
      for (final engine in _mysqlEngines) {
        expect(
          upper,
          isNot(contains('ENGINE=$engine')),
          reason: '$reason: MySQL engine $engine must not appear in Doris DDL',
        );
      }
    }

    Future<String> fetchCreateTableDdl(String tableName) async {
      final result = await adapter.executeQuery(
        'SHOW CREATE TABLE `$testDbName`.`$tableName`',
      );
      expect(result.rows, isNotEmpty, reason: 'SHOW CREATE TABLE returned no rows');
      final firstRow = result.rows.first;
      String? ddl;
      for (final value in firstRow.values) {
        if (value is String && value.toUpperCase().contains('CREATE TABLE')) {
          ddl = value;
          break;
        }
      }
      expect(ddl, isNotNull, reason: 'SHOW CREATE TABLE did not return a DDL string');
      return ddl!;
    }

    testWidgets('creates a simple table without ENGINE= in DDL', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();

      const tableName = 'simple_table';
      final columns = [
        DbColumn(
          name: 'id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(name: 'name', type: 'VARCHAR(255)', isNullable: true),
      ];

      final created = await adapter.createTable(tableName, columns);
      expect(created, isTrue, reason: 'CREATE TABLE should succeed');

      final ddl = await fetchCreateTableDdl(tableName);
      expect(ddl.toUpperCase(), contains('CREATE TABLE'));
      assertNoMySqlEngine(ddl, 'simple table');
    });

    testWidgets('creates DUPLICATE KEY table and verifies model keyword', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();

      const tableName = 'duplicate_key_table';
      final columns = [
        DbColumn(
          name: 'user_id',
          type: 'INT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(
          name: 'status',
          type: 'VARCHAR(50)',
          isNullable: false,
          defaultValue: 'active',
        ),
      ];

      final created = await adapter.createTable(
        tableName,
        columns,
        options: {'model': 'DUPLICATE'},
      );
      expect(created, isTrue, reason: 'DUPLICATE KEY table creation should succeed');

      final ddl = await fetchCreateTableDdl(tableName);
      expect(ddl.toUpperCase(), contains('DUPLICATE KEY'));
      assertNoMySqlEngine(ddl, 'DUPLICATE KEY table');
    });

    testWidgets('creates UNIQUE KEY table and verifies model keyword', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();

      const tableName = 'unique_key_table';
      final columns = [
        DbColumn(
          name: 'order_id',
          type: 'BIGINT',
          isPrimaryKey: true,
          isNullable: false,
        ),
        DbColumn(
          name: 'remark',
          type: 'VARCHAR(255)',
          isNullable: true,
          defaultValue: 'none',
        ),
      ];

      final created = await adapter.createTable(
        tableName,
        columns,
        options: {'model': 'UNIQUE'},
      );
      expect(created, isTrue, reason: 'UNIQUE KEY table creation should succeed');

      final ddl = await fetchCreateTableDdl(tableName);
      expect(ddl.toUpperCase(), contains('UNIQUE KEY'));
      assertNoMySqlEngine(ddl, 'UNIQUE KEY table');
    });

    testWidgets('uses unique test database name per run', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();

      // The test database name is generated in setUp and follows the
      // DorisTestConfig.generateTestDatabaseName() convention.
      expect(testDbName, startsWith('dbmaster_test_'));
      expect(testDbName.length, greaterThan('dbmaster_test_'.length));
    });
  });
}
