// ============================================================================
// T14（J1-a）· 网格写回真库全链路 E2E — MySQL 8.0 + PostgreSQL 17
//
// 覆盖（任务书 T14 真库验证节）：
// - 右键「浏览数据」→ 行右键「编辑此行」→ 改 1 列 → 预览 UPDATE 与手写期望
//   逐字一致 → 确认 → 重查断言该行新值 + 仅该行变化（他行不变）；
// - 取消路径 = 库内容前后逐行一致；
// - 无 PK 表 / 手写 SQL 结果网格 = 入口不出现；
// - readonly 连接 = 入口禁用（MySQL / PG 各一次）；
// - 网格成功后刷新（重跑浏览查询）。
//
// 环境：WSL 全矩阵（连接信息唯一来源 `D:\workspace\dbmaster\test_db_local_wsl.txt`，
// 口令经 --dart-define 注入，不入库）；MySQL/PG 网关壳硬依赖 embedded server
// （DBMASTER_SERVER_BIN → dist/Release/dbmaster-server.exe）。二进制/配置不可得
// 时全组以可 grep 的 ROWEDIT_MYSQL_E2E_SKIP / ROWEDIT_PG_E2E_SKIP 跳过（无假绿）。
// ============================================================================

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/molecules/compact_popup_menu_item.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/mysql_test_config.dart';
import 'config/postgresql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';
import 'helpers/pg_gateway_e2e_helper.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  bool mysqlReady = false;
  bool pgReady = false;
  setUpAll(() async {
    mysqlReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('ROWEDIT_MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供');
      mysqlReady = false;
    }
    // MySQL 与 PG 共用同一 embedded server 会话（幂等：已在跑则复用）。
    pgReady = await ensureEmbeddedServerForPgE2E();
    if (pgReady && !PostgreSQLTestConfig.available) {
      // ignore: avoid_print
      print('ROWEDIT_PG_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供');
      pgReady = false;
    }
  });

  // ==========================================================================
  // MySQL 8.0
  // ==========================================================================
  group('MySQL Row Edit Writeback E2E', () {
    late AppProvider appProvider;
    late MySQLAdapter adapter;
    late String testDbName;
    late DbServer server;

    setUp(() async {
      // AG-F-19：prefs 隔离——mock 存储，杜绝直写用户真实偏好。
      SharedPreferences.setMockInitialValues({});
      adapter = MySQLAdapter();
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      if (!mysqlReady) return;
      testDbName = MySQLTestConfig.generateTestDatabaseName();

      // 1. 种子连接（独立 adapter）建专用库 + 两张表（有 PK / 无 PK）。
      //    连接不带 database（库尚未建——网关 connect 的校验查询会失败）。
      final dbConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}',
        name: 'Seed Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await adapter.connect(dbConn);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      await adapter.executeQuery(
        'CREATE TABLE `rowedit_t` ('
        'id INT PRIMARY KEY, name VARCHAR(100) NOT NULL, '
        'memo VARCHAR(200) NULL, age INT NULL)',
      );
      await adapter.executeQuery(
        "INSERT INTO `rowedit_t` (id, name, memo, age) VALUES "
        "(1, 'Alice', 'm1', 30), (2, 'Bob', 'm2', 40), (3, 'Carol', NULL, 50)",
      );
      await adapter.executeQuery(
        'CREATE TABLE `rowedit_nopk` (a INT, b VARCHAR(10))',
      );
      await adapter.executeQuery(
        "INSERT INTO `rowedit_nopk` (a, b) VALUES (1, 'x1')",
      );

      // 2. 连接 provider（database 指向测试库——元数据与网关路由同库）。
      server = DbServer(
        id: 'mysql_rowedit_e2e_${testDbName.hashCode}',
        name: 'MySQL RowEdit E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: testDbName,
      );
      await appProvider.connection.saveConnection(server);
      expect(
        await appProvider.connectToServer(server),
        isTrue,
        reason: 'Failed to connect to MySQL',
      );
    });

    tearDown(() async {
      if (!mysqlReady) return;
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      appProvider.dispose();
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: appProvider,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            locale: const Locale('en'),
            home: const Scaffold(body: ResultsWidget()),
          ),
        ),
      );
    }

    /// 打开浏览数据 tab 并等到网格出现目标单元格文本（自动执行完成）。
    Future<void> openBrowseAndWait(
      WidgetTester tester,
      String table,
      String cellText,
    ) async {
      await appProvider.openBrowseDataTab(server.id, testDbName, table);
      await pumpApp(tester);
      for (var i = 0; i < 20; i++) {
        if (find.text(cellText).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.text(cellText),
        findsWidgets,
        reason: '浏览数据自动执行后网格应渲染 $cellText',
      );
    }

    Future<void> rightClickCell(WidgetTester tester, String text) async {
      await tester.tap(find.text(text).first, buttons: kSecondaryButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    CompactPopupMenuItem<dynamic>? rowEditItem() {
      final finder = find
          .widgetWithText(CompactPopupMenuItem<dynamic>, 'Edit Row…')
          .evaluate();
      if (finder.isEmpty) return null;
      return finder.first.widget as CompactPopupMenuItem<dynamic>;
    }

    Future<Map<int, String>> fetchNames() async {
      final result = await adapter.executeQuery(
        'SELECT id, name FROM `rowedit_t` ORDER BY id',
      );
      return {
        for (final row in result.rows)
          (row['id'] as num).toInt(): row['name'] as String,
      };
    }

    testWidgets('行编辑全链路：改 1 列 → 预览与期望逐字一致 → 确认 → 仅该行变化 + 网格刷新；取消路径零变更', (
      tester,
    ) async {
      if (!mysqlReady) return;
      await openBrowseAndWait(tester, 'rowedit_t', 'Alice');

      // ---- 确认路径（行 1：Alice → Alicia）----
      await rightClickCell(tester, 'Alice');
      final item = rowEditItem();
      expect(item, isNotNull, reason: 'browse tab + PK 就绪 → 入口出现');
      expect(item!.enabled, isTrue);

      await tester.tap(find.text('Edit Row…'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Edit Row — rowedit_t'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      await tester.pumpAndSettle();
      const expectedSql =
          "UPDATE `rowedit_t` SET `name` = 'Alicia' WHERE `id` = 1";
      // 预览与手写期望逐字一致。
      expect(find.text(expectedSql), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // 确认门内嵌同一 SQL 预览。
      expect(
        find.text('This will update one row in rowedit_t. Continue?'),
        findsOneWidget,
      );
      expect(find.text(expectedSql), findsWidgets);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      for (var i = 0; i < 15; i++) {
        if (find.text('Alicia').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }

      // 重查断言：该行新值 + 他行不变（仅该行变化）。
      final names = await fetchNames();
      expect(names[1], 'Alicia', reason: '目标行已更新');
      expect(names[2], 'Bob', reason: '他行不受影响');
      expect(names[3], 'Carol', reason: '他行不受影响');
      // 网格已刷新（重跑浏览查询）。
      expect(find.text('Alicia'), findsWidgets);

      // ---- 取消路径（行 2：Bob → 改而取消 → 库内容前后一致）----
      final before = await fetchNames();
      await rightClickCell(tester, 'Bob');
      await tester.tap(find.text('Edit Row…'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.enterText(find.widgetWithText(TextField, 'Bob'), 'Robert');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // 确认门取消 = 零执行。
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // 表单再取消关闭。
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final afterCancel = await fetchNames();
      expect(afterCancel, before, reason: '取消路径库内容逐行一致');
    });

    testWidgets('无 PK 表：浏览网格右键不出现「编辑此行」', (tester) async {
      if (!mysqlReady) return;
      await openBrowseAndWait(tester, 'rowedit_nopk', 'x1');

      await rightClickCell(tester, 'x1');
      expect(rowEditItem(), isNull, reason: '无 PK 表入口不出现（fail-closed）');
    });

    testWidgets('手写 SQL 结果网格（无 browseTarget）：入口不出现', (tester) async {
      if (!mysqlReady) return;
      await appProvider.openQueryTab(
        server.id,
        testDbName,
        sql: 'SELECT * FROM `rowedit_t`',
      );
      await appProvider.executeCurrentQueryAndRecord();
      await pumpApp(tester);
      for (var i = 0; i < 20; i++) {
        if (find.text('Alice').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Alice'), findsWidgets);

      await rightClickCell(tester, 'Alice');
      expect(rowEditItem(), isNull, reason: '手写 SQL 结果网格不开放写回');
    });

    testWidgets('readonly 连接：入口禁用 + 点击零副作用', (tester) async {
      if (!mysqlReady) return;
      final roServer = DbServer(
        id: 'mysql_rowedit_ro_${testDbName.hashCode}',
        name: 'MySQL RowEdit RO',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: testDbName,
        readOnly: true,
      );
      await appProvider.connection.saveConnection(roServer);
      expect(await appProvider.connectToServer(roServer), isTrue);

      try {
        await appProvider.openBrowseDataTab(
          roServer.id,
          testDbName,
          'rowedit_t',
        );
        await pumpApp(tester);
        for (var i = 0; i < 20; i++) {
          if (find.text('Alice').evaluate().isNotEmpty) break;
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.pumpAndSettle(const Duration(seconds: 1));

        await rightClickCell(tester, 'Alice');
        final item = rowEditItem();
        expect(item, isNotNull, reason: 'readonly = 禁用 + 说明，不是隐藏');
        expect(item!.enabled, isFalse);

        await tester.tap(find.text('Edit Row…'));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(
          find.text('Edit Row — rowedit_t'),
          findsNothing,
          reason: '禁用项点击不得打开写回入口',
        );
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: roServer.id);
        } catch (_) {}
      }
    });
  });

  // ==========================================================================
  // PostgreSQL 17
  // ==========================================================================
  group('PostgreSQL Row Edit Writeback E2E', () {
    late AppProvider appProvider;
    late PostgreSQLAdapter adapter;
    late String testDbName;
    late DbServer server;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      adapter = PostgreSQLAdapter();
      appProvider = AppProvider();
      AppProvider.devBypassGates = true;
      if (!pgReady) return;
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();

      // 1. 维护库（postgres）建库 → 重连测试库播种。
      final maintenanceConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}',
        name: 'Seed Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      await adapter.connect(maintenanceConn);
      await adapter.createDatabase(testDbName);
      await adapter.disconnect();

      final testDbConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}_db',
        name: 'Seed DB Connection',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await adapter.connect(testDbConn);
      await adapter.executeQuery(
        'CREATE TABLE rowedit_t ('
        'id INT PRIMARY KEY, name VARCHAR(100) NOT NULL, '
        'memo TEXT NULL, age INT NULL)',
      );
      await adapter.executeQuery(
        "INSERT INTO rowedit_t (id, name, memo, age) VALUES "
        "(1, 'Alice', 'm1', 30), (2, 'Bob', 'm2', 40)",
      );
      await adapter.executeQuery(
        'CREATE TABLE rowedit_nopk (a INT, b VARCHAR(10))',
      );
      await adapter.executeQuery(
        "INSERT INTO rowedit_nopk (a, b) VALUES (1, 'x1')",
      );

      server = DbServer(
        id: 'pg_rowedit_e2e_${testDbName.hashCode}',
        name: 'PG RowEdit E2E',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
      );
      await appProvider.connection.saveConnection(server);
      expect(
        await appProvider.connectToServer(server),
        isTrue,
        reason: 'Failed to connect to PostgreSQL',
      );
    });

    tearDown(() async {
      if (!pgReady) return;
      try {
        await appProvider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      // PG 不能 drop 当前连接库：断开后经维护库（postgres）回收。
      try {
        await adapter.disconnect();
        await adapter.connect(
          DatabaseConnection(
            id: 'teardown_${testDbName.hashCode}',
            name: 'Teardown Connection',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: 'postgres',
          ),
        );
        await adapter.executeQuery('DROP DATABASE IF EXISTS $testDbName');
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
    });

    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: appProvider,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            locale: const Locale('en'),
            home: const Scaffold(body: ResultsWidget()),
          ),
        ),
      );
    }

    Future<void> openBrowseAndWait(
      WidgetTester tester,
      String table,
      String cellText,
    ) async {
      await appProvider.openBrowseDataTab(server.id, testDbName, table);
      await pumpApp(tester);
      for (var i = 0; i < 20; i++) {
        if (find.text(cellText).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text(cellText), findsWidgets);
    }

    Future<void> rightClickCell(WidgetTester tester, String text) async {
      await tester.tap(find.text(text).first, buttons: kSecondaryButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    CompactPopupMenuItem<dynamic>? rowEditItem() {
      final finder = find
          .widgetWithText(CompactPopupMenuItem<dynamic>, 'Edit Row…')
          .evaluate();
      if (finder.isEmpty) return null;
      return finder.first.widget as CompactPopupMenuItem<dynamic>;
    }

    testWidgets('行编辑全链路（PG 方言双引号 + memo 置 NULL）', (tester) async {
      if (!pgReady) return;
      await openBrowseAndWait(tester, 'rowedit_t', 'Alice');

      await rightClickCell(tester, 'Alice');
      final item = rowEditItem();
      expect(item, isNotNull);
      expect(item!.enabled, isTrue);

      await tester.tap(find.text('Edit Row…'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('Edit Row — rowedit_t'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Alice'), 'Alicia');
      // memo 勾选 NULL 置位（m1 → SQL NULL，跨方言 NULL 字面量链路）。
      // 两个可空列（memo/age）各有一个 NULL 置位，.first = 声明序靠前的 memo。
      await tester.tap(find.text('NULL').first);
      await tester.pumpAndSettle();
      const expectedSql =
          'UPDATE "rowedit_t" SET "name" = \'Alicia\', "memo" = NULL '
          'WHERE "id" = 1';
      expect(find.text(expectedSql), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      for (var i = 0; i < 15; i++) {
        if (find.text('Alicia').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }

      final rows = await adapter.executeQuery(
        'SELECT id, name, memo FROM rowedit_t ORDER BY id',
      );
      expect(rows.rows[0]['name'], 'Alicia');
      expect(rows.rows[0]['memo'], isNull, reason: 'NULL 置位生效');
      expect(rows.rows[1]['name'], 'Bob', reason: '他行不受影响');
      expect(find.text('Alicia'), findsWidgets, reason: '网格已刷新');
    });

    testWidgets('无 PK 表 + readonly 连接（PG 侧 fail-closed）', (tester) async {
      if (!pgReady) return;
      await openBrowseAndWait(tester, 'rowedit_nopk', 'x1');
      await rightClickCell(tester, 'x1');
      expect(rowEditItem(), isNull, reason: '无 PK 表入口不出现');
      // 关闭首段右键菜单（否则 overlay 遮挡后续交互）。
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final roServer = DbServer(
        id: 'pg_rowedit_ro_${testDbName.hashCode}',
        name: 'PG RowEdit RO',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: testDbName,
        readOnly: true,
      );
      await appProvider.connection.saveConnection(roServer);
      expect(await appProvider.connectToServer(roServer), isTrue);
      try {
        await appProvider.openBrowseDataTab(
          roServer.id,
          testDbName,
          'rowedit_t',
        );
        await pumpApp(tester);
        for (var i = 0; i < 20; i++) {
          if (find.text('Alice').evaluate().isNotEmpty) break;
          await tester.pump(const Duration(seconds: 1));
        }
        await tester.pumpAndSettle(const Duration(seconds: 1));

        await rightClickCell(tester, 'Alice');
        final item = rowEditItem();
        expect(item, isNotNull);
        expect(item!.enabled, isFalse, reason: 'readonly 入口禁用（PG 覆盖）');
      } finally {
        try {
          await appProvider.disconnectConnection(connectionId: roServer.id);
        } catch (_) {}
      }
    });
  });
}
