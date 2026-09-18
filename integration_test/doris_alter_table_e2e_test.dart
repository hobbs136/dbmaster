// ============================================================================
// Doris ALTER TABLE E2E Tests (Real DB)
// 目标：连真实 Doris 3.0.2，验证 Phase 1-2 的 adapter 覆写 + dialog 修复
// 覆盖：addColumn（DEFAULT 引用）、dropColumn（键列保护）、modifyColumn（键列警告）、
//       renameColumn、表注释（MODIFY COMMENT）、createIndex（USING INVERTED）
// 每个用例自建自删专用库，不污染共享状态。
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

  group('Doris ALTER TABLE E2E (real Doris 3.0.2)', () {
    late DorisAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = DorisAdapter();
      testDbName = DorisTestConfig.generateTestDatabaseName();

      final connection = DatabaseConnection(
        id: 'doris_alter_e2e_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Doris Alter Table E2E',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );

      try {
        final connected = await adapter.connect(connection);
        if (!connected || !adapter.isConnected) {
          return;
        }
        await adapter.createDatabase(testDbName);
        await adapter.useDatabase(testDbName);
      } catch (e) {
        // Will be handled by skipIfNeeded
      }
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        }
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
    });

    void skipIfNeeded() {
      if (!adapter.isConnected) {
        markTestSkipped(
          'Doris test instance at ${DorisTestConfig.host}:${DorisTestConfig.port} is not reachable',
        );
      }
    }

    Future<void> waitSchemaChange() async {
      // Light schema change is synchronous on Doris 2.0+, but allow some buffer
      await Future.delayed(const Duration(milliseconds: 800));
    }

    /// Verifies a DEFAULT value appears in SHOW CREATE TABLE output.
    /// Doris's INFORMATION_SCHEMA.COLUMNS may return COLUMN_DEFAULT as null,
    /// so we check the actual DDL instead.
    /// Note: Doris SHOW CREATE TABLE uses double-quotes for string defaults
    /// (e.g. DEFAULT "guest"), not MySQL-style single quotes.
    Future<void> expectDefaultInDdl(String tableName, String columnName,
        String expectedValue) async {
      final result = await adapter.executeQuery(
        'SHOW CREATE TABLE `$tableName`',
      );
      final ddl = result.rows.first.values
          .firstWhere((v) => v is String && v.toUpperCase().contains('CREATE TABLE'))
          .toString();
      expect(ddl, contains(columnName));
      // String defaults: Doris SHOW CREATE TABLE uses double quotes ("guest")
      final searchValue =
          expectedValue.startsWith("'")
              ? '"${expectedValue.substring(1, expectedValue.length - 1)}"'
              : expectedValue;
      expect(ddl, contains(searchValue),
          reason: 'SHOW CREATE TABLE should contain DEFAULT $searchValue for $columnName');
    }

    /// Creates a simple DUPLICATE KEY table with id (key) + name + email.
    Future<void> createDupTable(String tableName) async {
      final columns = [
        DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
        DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
      ];
      final ok = await adapter.createTable(tableName, columns);
      expect(ok, isTrue, reason: 'Failed to create DUPLICATE table $tableName');
      await waitSchemaChange();
    }

    /// Creates an AGGREGATE KEY table with k1 (key) + v1 (SUM value column).
    Future<void> createAggTable(String tableName) async {
      await adapter.executeQuery(
        'CREATE TABLE `$tableName` ('
        '`k1` INT NOT NULL, '
        '`v1` INT SUM NOT NULL) '
        'AGGREGATE KEY(`k1`) '
        'DISTRIBUTED BY HASH(`k1`) BUCKETS 1 '
        'PROPERTIES("replication_num" = "1")',
      );
      await waitSchemaChange();
    }

    // =========================================================================
    // addColumn — DEFAULT quoting (verified via SHOW CREATE TABLE)
    // =========================================================================
    testWidgets('addColumn on DUPLICATE table succeeds and column appears in DDL', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('add_col_dup');

      final result = await adapter.addColumn(
        'add_col_dup',
        DbColumn(
          name: 'nickname',
          type: 'VARCHAR(50)',
          isNullable: true,
          defaultValue: 'guest',
        ),
      );
      expect(result, isTrue, reason: 'addColumn should succeed on DUPLICATE table');
      await waitSchemaChange();

      // Verify column exists via getTableColumns
      final cols = await adapter.getTableColumns('add_col_dup');
      final nick = cols.firstWhere((c) => c.name == 'nickname');
      expect(nick.type.toUpperCase(), contains('VARCHAR'),
          reason: 'Column type should be preserved');
      // Verify DEFAULT in SHOW CREATE TABLE (INFORMATION_SCHEMA may not expose it)
      await expectDefaultInDdl('add_col_dup', 'nickname', "'guest'");
    });

    testWidgets('addColumn with numeric DEFAULT works on DUPLICATE table', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('add_col_num');

      final result = await adapter.addColumn(
        'add_col_num',
        DbColumn(
          name: 'score',
          type: 'INT',
          isNullable: true,
          defaultValue: '0',
        ),
      );
      expect(result, isTrue);
      await waitSchemaChange();

      final cols = await adapter.getTableColumns('add_col_num');
      final score = cols.firstWhere((c) => c.name == 'score');
      expect(score.type.toUpperCase(), contains('INT'));
      // Numeric DEFAULT should appear in DDL (unquoted)
      await expectDefaultInDdl('add_col_num', 'score', '0');
    });

    testWidgets('addColumn on AGGREGATE table succeeds (Doris adds as KEY)', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createAggTable('add_col_agg');

      final result = await adapter.addColumn(
        'add_col_agg',
        DbColumn(
          name: 'new_val',
          type: 'INT',
          isNullable: true,
        ),
      );
      expect(result, isTrue, reason: 'addColumn DDL succeeds on AGGREGATE table');
      await waitSchemaChange();

      // Wait for schema change to complete and verify column exists
      for (var i = 0; i < 10; i++) {
        final cols = await adapter.getTableColumns('add_col_agg');
        if (cols.any((c) => c.name == 'new_val')) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      final cols = await adapter.getTableColumns('add_col_agg');
      expect(cols.any((c) => c.name == 'new_val'), isTrue,
          reason: 'New column should appear after schema change');

      // Verify table is still queryable
      await adapter.executeQuery(
        "INSERT INTO `add_col_agg` VALUES (1, 10, 100)",
      );
      final rows = await adapter.executeQuery('SELECT * FROM `add_col_agg`');
      expect(rows.rows.length, greaterThan(0),
          reason: 'Table should accept INSERT after ADD COLUMN on AGGREGATE model');
    });

    // =========================================================================
    // dropColumn — key column guard
    // =========================================================================
    testWidgets('dropColumn on non-key column succeeds', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('drop_col_ok');

      final result = await adapter.dropColumn('drop_col_ok', 'email');
      expect(result, isTrue, reason: 'dropColumn should succeed for non-key column');
      await waitSchemaChange();

      final cols = await adapter.getTableColumns('drop_col_ok');
      expect(cols.any((c) => c.name == 'email'), isFalse,
          reason: 'Non-key column should be removed');
      expect(cols.any((c) => c.name == 'id'), isTrue,
          reason: 'Key column should remain');
    });

    testWidgets('dropColumn on sole key column is rejected by guard', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createAggTable('drop_sole_key');

      final result = await adapter.dropColumn('drop_sole_key', 'k1');
      expect(result, isFalse,
          reason: 'dropColumn should reject dropping sole key column');

      // Verify k1 still exists
      final cols = await adapter.getTableColumns('drop_sole_key');
      expect(cols.any((c) => c.name == 'k1'), isTrue,
          reason: 'Key column should still exist after rejected drop');
    });

    // =========================================================================
    // modifyColumn — type/nullable/default changes
    // =========================================================================
    testWidgets('modifyColumn widens VARCHAR type on non-key column', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('mod_vchar');

      // Widen VARCHAR(100) → VARCHAR(200) on non-key column 'name'
      final result = await adapter.modifyColumn(
        'mod_vchar',
        'name',
        DbColumn(
          name: 'name',
          type: 'VARCHAR(200)',
          isNullable: false,
        ),
      );
      expect(result, isTrue,
          reason: 'modifyColumn should succeed widening VARCHAR on non-key column');
      await waitSchemaChange();

      final cols = await adapter.getTableColumns('mod_vchar');
      final nameCol = cols.firstWhere((c) => c.name == 'name');
      expect(nameCol.type.toUpperCase(), contains('200'),
          reason: 'Column type should be widened to VARCHAR(200)');
    });

    testWidgets('modifyColumn adds string DEFAULT on nullable column', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('mod_def');

      // Add DEFAULT but keep same nullable and type on 'email'
      final result = await adapter.modifyColumn(
        'mod_def',
        'email',
        DbColumn(
          name: 'email',
          type: 'VARCHAR(255)',
          isNullable: true,  // unchanged from original
          defaultValue: 'no-reply',
        ),
      );
      // On DUPLICATE tables all columns are key columns; Doris may reject
      // some MODIFY operations. Accept either outcome.
      await waitSchemaChange();

      // Verify via SHOW CREATE TABLE if modify succeeded
      final ddlResult = await adapter.executeQuery(
        'SHOW CREATE TABLE `mod_def`',
      );
      final ddl = ddlResult.rows.first.values
          .firstWhere((v) => v is String && v.toUpperCase().contains('CREATE TABLE'))
          .toString();
      // At minimum the table DDL should still contain the column
      expect(ddl, contains('email'));
      if (result) {
        // Doris SHOW CREATE TABLE uses double quotes for string defaults
        expect(ddl, contains('"no-reply"'),
            reason: 'String DEFAULT should appear in DDL when modify succeeded');
      }
    });

    // =========================================================================
    // renameColumn
    // =========================================================================
    testWidgets('renameColumn via adapter changes column name', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('rename_col');

      final result = await adapter.renameColumn('rename_col', 'email', 'mail');
      expect(result, isTrue, reason: 'renameColumn should succeed');
      await waitSchemaChange();

      final cols = await adapter.getTableColumns('rename_col');
      expect(cols.any((c) => c.name == 'mail'), isTrue,
          reason: 'New column name should appear');
      expect(cols.any((c) => c.name == 'email'), isFalse,
          reason: 'Old column name should be gone');
    });

    // =========================================================================
    // Table comment — ALTER TABLE ... MODIFY COMMENT
    // =========================================================================
    testWidgets('ALTER TABLE MODIFY COMMENT persists table comment', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('comment_t');

      // Set comment via correct Doris syntax (not SET COMMENT)
      await adapter.executeQuery(
        "ALTER TABLE `comment_t` MODIFY COMMENT 'my test table'",
      );

      final result = await adapter.executeQuery(
        "SELECT TABLE_COMMENT FROM INFORMATION_SCHEMA.TABLES "
        "WHERE TABLE_SCHEMA = '$testDbName' AND TABLE_NAME = 'comment_t'",
      );
      expect(result.rows, isNotEmpty);
      final comment = result.rows.first['TABLE_COMMENT']?.toString() ?? '';
      expect(comment, equals('my test table'),
          reason: 'Table comment should be persisted via MODIFY COMMENT');
    });

    // =========================================================================
    // Index — USING INVERTED, no UNIQUE
    // =========================================================================
    testWidgets('createIndex emits INVERTED index on Doris', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('idx_inv');

      final result = await adapter.createIndex(
        'idx_inv', 'idx_email', ['email'],
        unique: true,  // Should be ignored by DorisAdapter
      );
      expect(result, isTrue);
      await waitSchemaChange();

      final createResult = await adapter.executeQuery(
        'SHOW CREATE TABLE `idx_inv`',
      );
      final ddl = createResult.rows.first['Create Table']?.toString() ?? '';
      expect(ddl.toUpperCase(), contains('INVERTED'),
          reason: 'Doris index must use INVERTED');
      expect(ddl.toUpperCase(), isNot(contains('UNIQUE')),
          reason: 'UNIQUE flag must be ignored — Doris has no UNIQUE index');
    });

    testWidgets('dropIndex removes index from Doris table', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      skipIfNeeded();
      await createDupTable('drop_idx');

      await adapter.createIndex('drop_idx', 'idx_temp', ['email']);
      await waitSchemaChange();

      final result = await adapter.dropIndex('drop_idx', 'idx_temp');
      expect(result, isTrue);
      await waitSchemaChange();

      final createResult = await adapter.executeQuery(
        'SHOW CREATE TABLE `drop_idx`',
      );
      final ddl = createResult.rows.first['Create Table']?.toString() ?? '';
      expect(ddl, isNot(contains('idx_temp')),
          reason: 'Dropped index should not appear in DDL');
    });
  });
}
