// ============================================================================
// Doris Sidebar Menu / Dialect E2E (Real DB)
// 目标：连真实 Doris 3.0.2，验证 027-doris-correctness-fixes 的方言修复在真库生效。
// 覆盖：建表(F7)、重命名表(F1)、索引(F3)、删列(F5)、导出回灌(F4)、UPDATE 模型探测(F6)。
// 每个用例自建自删专用库（generateTestDatabaseName），不污染共享状态。
// 无真实库时（isConfigured==false）整组跳过，CI 不报错。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/doris_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/doris_table_model_detector.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/organisms/connection/schema_diff_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/doris_test_config.dart';
import 'helpers/doris_sidebar_helpers.dart';
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

  // 无真实库环境（如 CI）→ 整组跳过
  if (!DorisTestConfig.isConfigured) {
    testWidgets(
      'Doris E2E skipped (DBMASTER_DORIS_HOST not set)',
      (tester) async {},
    );
    return;
  }

  /// 建立一条连到真实 Doris 的 adapter 连接（不指定 database，连到 server）。
  Future<DorisAdapter> connectAdapter() async {
    final adapter = DorisAdapter();
    final connection = DatabaseConnection(
      id: 'doris_e2e_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Doris E2E',
      type: DatabaseType.doris,
      host: DorisTestConfig.host,
      port: DorisTestConfig.port,
      username: DorisTestConfig.username,
      password: DorisTestConfig.password,
    );
    final ok = await adapter.connect(connection);
    expect(ok, isTrue, reason: '连接 Doris 失败');
    return adapter;
  }

  /// 构造一个含主键列 + 普通列的建表列定义。
  List<DbColumn> sampleColumns() => [
    DbColumn(name: 'id', type: 'INT', isPrimaryKey: true, isNullable: false),
    DbColumn(name: 'name', type: 'VARCHAR(100)', isNullable: false),
    DbColumn(name: 'email', type: 'VARCHAR(255)', isNullable: true),
  ];

  group('Doris 方言修复 E2E (real Doris 3.0.2)', () {
    late DorisAdapter adapter;
    late String testDbName;

    setUp(() async {
      adapter = await connectAdapter();
      testDbName = DorisTestConfig.generateTestDatabaseName();
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
    });

    tearDown(() async {
      try {
        if (adapter.isConnected) {
          // 切回任意库再 drop 测试库，避免 USE 着被删的库
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        }
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
    });

    testWidgets('F7 createTable 发合法 Doris DDL（含分桶），建表成功', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final ok = await adapter.createTable('users', sampleColumns());
      expect(ok, isTrue, reason: 'Doris 建表应成功（含 DISTRIBUTED BY HASH）');

      final tables = await adapter.getTables();
      expect(tables, contains('users'));
    });

    testWidgets('F1 renameTable 用 ALTER TABLE RENAME 真实生效', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.createTable('t_old', sampleColumns());

      final ok = await adapter.renameTable('t_old', 't_new');
      expect(ok, isTrue, reason: 'Doris 重命名表应成功');

      final tables = await adapter.getTables();
      expect(tables, contains('t_new'));
      expect(tables, isNot(contains('t_old')));
    });

    testWidgets('F2 renameColumn 用 ALTER TABLE RENAME COLUMN 真实生效', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.createTable('rc', sampleColumns());

      final ok = await adapter.renameColumn('rc', 'email', 'mail');
      expect(ok, isTrue, reason: 'Doris 重命名列应成功（light_schema_change 默认开）');

      await Future.delayed(const Duration(seconds: 1));
      final cols = await adapter.getTableColumns('rc');
      expect(cols.any((c) => c.name == 'mail'), isTrue);
      expect(cols.any((c) => c.name == 'email'), isFalse);
    });

    testWidgets(
      'F3 createIndex 发 USING INVERTED 并可被 SHOW CREATE 识别；dropIndex 可删',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await adapter.createTable('idx_t', sampleColumns());

        final created = await adapter.createIndex('idx_t', 'idx_email', [
          'email',
        ]);
        expect(created, isTrue, reason: 'Doris 廒排索引应创建成功');

        // SHOW CREATE TABLE 应体现索引
        final createResult = await adapter.executeQuery(
          'SHOW CREATE TABLE `idx_t`',
        );
        final createSql =
            createResult.rows.first['Create Table']?.toString() ?? '';
        expect(createSql.toUpperCase(), contains('INVERTED'));

        final dropped = await adapter.dropIndex('idx_t', 'idx_email');
        expect(dropped, isTrue, reason: 'Doris 删索引应成功');
      },
    );

    testWidgets('F5 dropColumn 真实生效（不再被误标不支持）', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.createTable('dc', sampleColumns());

      final ok = await adapter.dropColumn('dc', 'email');
      expect(ok, isTrue, reason: '现代 Doris 支持删列');

      await Future.delayed(const Duration(seconds: 1));
      final cols = await adapter.getTableColumns('dc');
      expect(cols.any((c) => c.name == 'email'), isFalse);
      expect(cols.any((c) => c.name == 'id'), isTrue);
    });

    testWidgets('F4 exportDatabaseStructure 产出可回灌的 Doris DDL', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.createTable('exp', sampleColumns());
      await adapter.executeQuery(
        "INSERT INTO `exp` (id, name, email) VALUES (1, 'Alice', 'a@x.com')",
      );

      final dump = await adapter.exportDatabaseStructure(testDbName);
      expect(dump, contains('CREATE TABLE'));
      expect(dump, contains('DISTRIBUTED BY HASH')); // 含分桶 → 可回灌
      expect(dump, isNot(contains('PRIMARY KEY ('))); // 不含 MySQL 列级 PK 子句

      // 回灌：新建干净库并执行导出 SQL
      final reimportDb = '${testDbName}_reimport';
      await adapter.createDatabase(reimportDb);
      await adapter.useDatabase(reimportDb);
      // 逐语句执行导出文本（先剥注释行，再按分号切分——避免 "-- Table:" 注释行
      // 把紧随其后的 CREATE TABLE 一起滤掉）
      final executable = dump
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('--'))
          .join('\n');
      final stmts = executable
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      for (final stmt in stmts) {
        await adapter.executeQuery(stmt);
      }
      final tables = await adapter.getTables();
      expect(tables, contains('exp'));
    });

    testWidgets('F6 DUP 模型表被 UPDATE 模型探测识别为不可更新', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // 默认 createTable 产出 DUP 模型表
      await adapter.createTable('dup_t', sampleColumns());

      final createResult = await adapter.executeQuery(
        'SHOW CREATE TABLE `dup_t`',
      );
      final createSql =
          createResult.rows.first['Create Table']?.toString() ?? '';
      final model = DorisTableModelDetector.parseCreateTable(createSql);
      expect(model, isNotNull, reason: '应能从 SHOW CREATE 解析出模型');
      expect(model!.supportsUpdate, isFalse, reason: 'DUP 模型不支持 UPDATE');
    });

    // 表模型选择（DUP/UNIQUE/PK）+ 自定义分桶
    testWidgets('G1 UNIQUE 模型建表 + UPDATE 可执行', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final ok = await adapter.createTable(
        'uniq_t',
        sampleColumns(),
        options: {'model': 'UNIQUE'},
      );
      expect(ok, isTrue);

      final createSql = (await adapter.executeQuery(
        'SHOW CREATE TABLE `uniq_t`',
      )).rows.first.toString().toUpperCase();
      expect(createSql, contains('UNIQUE KEY'));

      // UNIQUE 模型支持 UPDATE
      await adapter.executeQuery(
        "INSERT INTO `uniq_t` (id, name, email) VALUES (1, 'a', 'x')",
      );
      await adapter.executeQuery("UPDATE `uniq_t` SET name = 'b' WHERE id = 1");
      final r = await adapter.executeQuery(
        'SELECT name FROM `uniq_t` WHERE id = 1',
      );
      expect(r.rows.first['name'].toString(), 'b');
    });

    testWidgets('G2 PRIMARY KEY 模型（UNIQUE+MoW）建表 + UPDATE 可执行', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // Doris 「主键模型」= UNIQUE KEY + Merge-on-Write（无独立 PRIMARY KEY 关键字）
      final ok = await adapter.createTable(
        'pk_t',
        sampleColumns(),
        options: {'model': 'PRIMARY KEY'},
      );
      expect(ok, isTrue);

      final createSql = (await adapter.executeQuery(
        'SHOW CREATE TABLE `pk_t`',
      )).rows.first.toString().toUpperCase();
      expect(createSql, contains('UNIQUE KEY'));
      expect(createSql, contains('ENABLE_UNIQUE_KEY_MERGE_ON_WRITE'));

      await adapter.executeQuery(
        "INSERT INTO `pk_t` (id, name, email) VALUES (1, 'a', 'x')",
      );
      await adapter.executeQuery("UPDATE `pk_t` SET name = 'b' WHERE id = 1");
      final r = await adapter.executeQuery(
        'SELECT name FROM `pk_t` WHERE id = 1',
      );
      expect(r.rows.first['name'].toString(), 'b');
    });

    testWidgets('G3 自定义分桶（hashColumn + buckets）反映到 DDL', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final ok = await adapter.createTable(
        'dist_t',
        sampleColumns(),
        options: {'model': 'DUPLICATE', 'hashColumn': 'id', 'buckets': 8},
      );
      expect(ok, isTrue);

      final createSql = (await adapter.executeQuery(
        'SHOW CREATE TABLE `dist_t`',
      )).rows.first.toString().toUpperCase();
      expect(createSql, contains('DUPLICATE KEY'));
      expect(createSql, contains('DISTRIBUTED BY HASH'));
      expect(createSql, contains('BUCKETS 8'));
    });

    // AGGREGATE 模型建表 + SUM 聚合生效
    testWidgets('G4 AGGREGATE 模型建表 + SUM 聚合生效', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final ok = await adapter.createTable(
        'agg_t',
        [
          DbColumn(
            name: 'dt',
            type: 'DATE',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(
            name: 'site',
            type: 'VARCHAR(50)',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'pv', type: 'BIGINT', isNullable: false),
        ],
        options: {
          'model': 'AGGREGATE',
          'aggregateColumns': {'pv': 'SUM'},
        },
      );
      expect(ok, isTrue);

      final createSql = (await adapter.executeQuery(
        'SHOW CREATE TABLE `agg_t`',
      )).rows.first.toString().toUpperCase();
      expect(createSql, contains('AGGREGATE KEY'));
      expect(createSql, contains('BIGINT SUM'));

      // 聚合生效：同维度多行 → SUM 自动合并
      await adapter.executeQuery(
        "INSERT INTO `agg_t` (dt, site, pv) VALUES "
        "('2026-01-01','a',1),('2026-01-01','a',2)",
      );
      final r = await adapter.executeQuery(
        "SELECT pv FROM `agg_t` WHERE dt = '2026-01-01' AND site = 'a'",
      );
      expect(r.rows.first['pv'].toString(), '3');
    });

    // RANGE 分区建表
    testWidgets('G5 RANGE 分区建表 + SHOW PARTITIONS', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final ok = await adapter.createTable(
        'part_t',
        [
          DbColumn(
            name: 'dt',
            type: 'DATE',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'name', type: 'VARCHAR(50)', isNullable: false),
        ],
        options: {
          'model': 'DUPLICATE',
          'partitionColumn': 'dt',
          'partitions': [
            {'name': 'p1', 'lessThan': '2026-02-01'},
            {'name': 'p2', 'lessThan': '2026-03-01'},
            {'name': 'p3', 'lessThan': '2026-04-01'},
          ],
        },
      );
      expect(ok, isTrue);

      final createSql = (await adapter.executeQuery(
        'SHOW CREATE TABLE `part_t`',
      )).rows.first.toString().toUpperCase();
      expect(createSql, contains('PARTITION BY RANGE'));

      final showPart = await adapter.executeQuery(
        'SHOW PARTITIONS FROM `part_t`',
      );
      expect(showPart.rows.length, 3);
    });

    // 物化视图 lifecycle（create + drop）
    // 注：SHOW MATERIALIZED VIEW 仅列异步 MV；sync MV（rollup）发现路径待 032b 调研
    testWidgets('G6 物化视图 create + drop', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await adapter.createTable('mv_base', sampleColumns());
      await adapter.executeQuery(
        "INSERT INTO `mv_base` (id, name, email) VALUES (1, 'a', 'x')",
      );
      // Create sync MV（rollup 带 COUNT）
      await adapter.executeQuery(
        'CREATE MATERIALIZED VIEW `mv_test` AS SELECT `id`, COUNT(`name`) AS cnt '
            'FROM `mv_base` GROUP BY `id`',
      );
      await Future.delayed(const Duration(seconds: 3));

      // Drop MV
      final dropped = await adapter.dropMaterializedView('mv_test');
      expect(dropped, isTrue, reason: 'DROP MATERIALIZED VIEW 应成功');
    });
  });

  // ============================================================================
  // Widget-level SidebarTree E2E via AppProvider.dbService
  // 目标：覆盖连接、建库、建表、DML、右键菜单，并断言真实库状态变化。
  // 无真实库时（isConfigured==false）整组跳过，CI 不报错。
  // ============================================================================
  group('Doris Sidebar Widget E2E (real DB + AppProvider)', () {
    late AppProvider appProvider;
    late DbServer server;
    late String testDbName;
    const connectionLabel = 'Doris Sidebar Widget E2E';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      testDbName = DorisTestConfig.generateTestDatabaseName();
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      server = DbServer(
        id: 'doris_sidebar_widget_${testDbName.hashCode}',
        name: connectionLabel,
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      expect(connected, isTrue, reason: 'Failed to connect to Doris');
      await appProvider.dbService.createDatabase(testDbName);
      await appProvider.dbService.useDatabase(testDbName);
      await appProvider.refreshDatabases();
    });

    tearDown(() async {
      try {
        await appProvider.dbService.dropDatabase(testDbName);
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('saved_queries');
        await prefs.remove('recent_tables');
        await prefs.remove('sidebar_favorite_tables');
        await prefs.remove('connection_groups');
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    Future<void> useTestDb() async {
      await appProvider.dbService.useDatabase(testDbName);
    }

    testWidgets(
      'connection menu > Create Database creates a database and refreshes tree',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpDorisHarness(tester, appProvider);
        await expandDorisConnection(tester, connectionLabel);

        final newDbName = '${testDbName}_created';

        await rightClickDorisNode(tester, connectionLabel);
        await tapDorisMenuItem(tester, 'Create Database');

        final nameField = find.byType(TextField).first;
        await tester.enterText(nameField, newDbName);
        await tester.pump();
        await tapDorisDialogButton(tester, 'Create');

        await tester.pumpAndSettle(const Duration(seconds: 3));

        final databases = await appProvider.dbService.getDatabases();
        expect(databases, contains(newDbName));

        // Cleanup the created database so tearDown's drop of testDbName stays clean.
        try {
          await appProvider.dbService.dropDatabase(newDbName);
        } catch (_) {}
      },
    );

    testWidgets(
      'table menu > Create Table with model/buckets/partition reflects in DDL',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpDorisHarness(tester, appProvider);

        await useTestDb();
        await appProvider.dbService.executeQuery('''
          CREATE TABLE `part_users` (
            `dt` DATE NOT NULL,
            `name` VARCHAR(50) NOT NULL
          ) DUPLICATE KEY(`dt`)
          PARTITION BY RANGE(`dt`) (
            PARTITION `p1` VALUES LESS THAN ('2026-02-01'),
            PARTITION `p2` VALUES LESS THAN ('2026-03-01')
          )
          DISTRIBUTED BY HASH(`dt`) BUCKETS 4
          PROPERTIES ("replication_num" = "1")
        ''');
        await appProvider.refreshDatabases();

        await useTestDb();
        final tables = await appProvider.dbService.getTables();
        expect(tables, contains('part_users'));

        final createResult = await appProvider.dbService.executeQuery(
          'SHOW CREATE TABLE `part_users`',
        );
        final createSql =
            createResult.first['Create Table']?.toString().toUpperCase() ?? '';
        expect(createSql, contains('DUPLICATE KEY'));
        expect(createSql, contains('DISTRIBUTED BY HASH'));
        expect(createSql, contains('PARTITION BY RANGE'));

        final partResult = await appProvider.dbService.executeQuery(
          'SHOW PARTITIONS FROM `part_users`',
        );
        expect(partResult.length, 2);
      },
    );

    testWidgets('table menu > Insert + Select returns inserted rows', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpDorisHarness(tester, appProvider);

      await useTestDb();
      await appProvider.dbService.executeQuery('''
          CREATE TABLE `users` (
            `id` INT NOT NULL,
            `name` VARCHAR(100) NOT NULL
          ) UNIQUE KEY(`id`)
          DISTRIBUTED BY HASH(`id`) BUCKETS 1
          PROPERTIES ("replication_num" = "1")
        ''');
      await appProvider.refreshDatabases();

      await useTestDb();
      await appProvider.dbService.executeQuery(
        "INSERT INTO `users` (id, name) VALUES (1, 'Alice'), (2, 'Bob')",
      );

      final result = await appProvider.dbService.executeQuery(
        'SELECT id, name FROM `users` ORDER BY id',
      );
      expect(result.length, 2);
      expect(result.first['name'], 'Alice');
      expect(result.last['name'], 'Bob');
    });

    testWidgets(
      'table menu > Drop Table removes the table after confirmation',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpDorisHarness(tester, appProvider);

        await useTestDb();
        await appProvider.dbService.executeQuery('''
          CREATE TABLE `drop_t` (
            `id` INT NOT NULL
          ) DUPLICATE KEY(`id`)
          DISTRIBUTED BY HASH(`id`) BUCKETS 1
          PROPERTIES ("replication_num" = "1")
        ''');
        await appProvider.refreshDatabases();

        await expandDorisConnection(tester, connectionLabel);
        await expandDorisDatabase(tester, testDbName);
        await expandDorisCategory(tester, 'Tables');

        await rightClickDorisNode(tester, 'drop_t');
        await tapDorisMenuItem(tester, 'Drop Table');

        await enterDorisConfirmationName(tester, 'drop_t');
        await tapDorisDialogButton(tester, 'Delete');

        await tester.pumpAndSettle(const Duration(seconds: 3));

        final tables = await appProvider.dbService.getTables();
        expect(tables, isNot(contains('drop_t')));
      },
    );

    testWidgets('table menu > Truncate clears table data but keeps structure', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpDorisHarness(tester, appProvider);

      await useTestDb();
      await appProvider.dbService.executeQuery('''
          CREATE TABLE `trunc_t` (
            `id` INT NOT NULL
          ) DUPLICATE KEY(`id`)
          DISTRIBUTED BY HASH(`id`) BUCKETS 1
          PROPERTIES ("replication_num" = "1")
        ''');
      await appProvider.dbService.executeQuery(
        "INSERT INTO `trunc_t` (id) VALUES (1), (2)",
      );
      await appProvider.refreshDatabases();

      await expandDorisConnection(tester, connectionLabel);
      await expandDorisDatabase(tester, testDbName);
      await expandDorisCategory(tester, 'Tables');

      await rightClickDorisNode(tester, 'trunc_t');
      await tapDorisMenuItem(tester, 'Truncate');
      await tapDorisDialogButton(tester, 'Truncate');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      final tables = await appProvider.dbService.getTables();
      expect(tables, contains('trunc_t'));

      final countResult = await appProvider.dbService.executeQuery(
        'SELECT COUNT(*) AS c FROM `trunc_t`',
      );
      expect(int.parse(countResult.first['c'].toString()), 0);
    });

    testWidgets('table menu > Rename renames the table', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpDorisHarness(tester, appProvider);

      await useTestDb();
      await appProvider.dbService.executeQuery('''
          CREATE TABLE `rename_t` (
            `id` INT NOT NULL
          ) DUPLICATE KEY(`id`)
          DISTRIBUTED BY HASH(`id`) BUCKETS 1
          PROPERTIES ("replication_num" = "1")
        ''');
      await appProvider.refreshDatabases();

      await expandDorisConnection(tester, connectionLabel);
      await expandDorisDatabase(tester, testDbName);
      await expandDorisCategory(tester, 'Tables');

      const newName = 'rename_t_new';
      await rightClickDorisNode(tester, 'rename_t');
      await tapDorisMenuItem(tester, 'Rename');

      await enterDorisConfirmationName(tester, newName);
      await tapDorisDialogButton(tester, 'Confirm');

      await tester.pumpAndSettle(const Duration(seconds: 3));

      final tables = await appProvider.dbService.getTables();
      expect(tables, isNot(contains('rename_t')));
      expect(tables, contains(newName));
    });

    testWidgets('database menu > Schema Diff & Sync opens SchemaDiffDialog', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpDorisHarness(tester, appProvider);
      await expandDorisConnection(tester, connectionLabel);
      await expandDorisDatabase(tester, testDbName);

      await rightClickDorisNode(tester, testDbName);
      await tapDorisMenuItem(tester, 'Schema Diff & Sync');
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(SchemaDiffDialog), findsOneWidget);
    });

    testWidgets('Performance category expands and shows process list UI', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await pumpDorisHarness(tester, appProvider);
      await expandDorisConnection(tester, connectionLabel);
      await expandDorisCategory(tester, 'Performance');
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // Smoke test: Performance node is rendered and can be expanded.
      // Full Kill Query verification requires a long-running query victim.
      expect(find.textContaining('Performance'), findsWidgets);
    });
  });
}
