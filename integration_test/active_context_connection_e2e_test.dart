// ============================================================================
// T25（J3 多连接长驻树地基）·「活动上下文连接」真库 E2E — MySQL 8.0 +
// PostgreSQL 17 双连接。
//
// 覆盖（任务书 T25 真库验证节）：
// - 双连接各开一个查询 tab → 切活动 tab 断言 Q1 面板标题/内容随库型整体
//   切换（MySQL ↔ PG 口径；专有项互斥锚定）；
// - PG tab 内执行（浏览）查询 → 结果网格右键导出项在 + 剪贴板 INSERT
//   引号按 PG 双引号，不随 MySQL currentServer 串味（夹具刻意把
//   currentServer 停在 MySQL——旧实现在此场景取反引号，差分锚定）。
//
// 环境：WSL 全矩阵（连接信息唯一来源 `D:\workspace\dbmaster\test_db_local_wsl.txt`，
// 口令经 --dart-define 注入，不入库）；MySQL/PG 网关壳硬依赖 embedded server
//（DBMASTER_SERVER_BIN 为进程 env，非 dart-define）。二进制/配置不可得时
// 全组以可 grep 的 ACTX_MYSQL_E2E_SKIP / ACTX_PG_E2E_SKIP 跳过（无假绿）。
// ============================================================================

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/organisms/sidebar/capability/sidebar_capability_menu.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/theme/app_theme.dart';

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
      print('ACTX_MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供');
      mysqlReady = false;
    }
    // MySQL 与 PG 共用同一 embedded server 会话（幂等：已在跑则复用）。
    pgReady = await ensureEmbeddedServerForPgE2E();
    if (pgReady && !PostgreSQLTestConfig.available) {
      // ignore: avoid_print
      print('ACTX_PG_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供');
      pgReady = false;
    }
  });

  group('Active Context Connection E2E (MySQL + PG, T25)', () {
    late AppProvider appProvider;
    late MySQLAdapter mysqlAdapter;
    late PostgreSQLAdapter pgAdapter;
    late String mysqlDbName;
    late String pgDbName;
    late DbServer mysqlServer;
    late DbServer pgServer;

    setUp(() async {
      // AG-F-19：prefs 隔离——mock 存储，杜绝直写用户真实偏好。
      SharedPreferences.setMockInitialValues({});
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过门禁
      appProvider = AppProvider();
      mysqlAdapter = MySQLAdapter();
      pgAdapter = PostgreSQLAdapter();
      if (!mysqlReady || !pgReady) return;
      mysqlDbName = MySQLTestConfig.generateTestDatabaseName();
      pgDbName = PostgreSQLTestConfig.generateTestDatabaseName();

      // 1. 种子连接建专用库 + users 表（各自引擎，自建自删）。
      final mysqlConn = DatabaseConnection(
        id: 'seed_${mysqlDbName.hashCode}',
        name: 'Seed MySQL',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await mysqlAdapter.connect(mysqlConn);
      await mysqlAdapter.createDatabase(mysqlDbName);
      await mysqlAdapter.useDatabase(mysqlDbName);
      await mysqlAdapter.executeQuery(
        'CREATE TABLE `users` (id INT PRIMARY KEY, name VARCHAR(100))',
      );
      await mysqlAdapter.executeQuery(
        "INSERT INTO `users` (id, name) VALUES (1, 'Alice')",
      );

      final pgMaintenance = DatabaseConnection(
        id: 'seed_${pgDbName.hashCode}',
        name: 'Seed PG Maintenance',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: 'postgres',
      );
      await pgAdapter.connect(pgMaintenance);
      await pgAdapter.createDatabase(pgDbName);
      await pgAdapter.disconnect();
      final pgConn = DatabaseConnection(
        id: 'seed_${pgDbName.hashCode}_db',
        name: 'Seed PG',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: pgDbName,
      );
      await pgAdapter.connect(pgConn);
      await pgAdapter.executeQuery(
        'CREATE TABLE users (id INT PRIMARY KEY, name VARCHAR(100))',
      );
      await pgAdapter.executeQuery(
        "INSERT INTO users (id, name) VALUES (1, 'Alice')",
      );

      // 2. 双连接接入 provider：**先 PG 后 MySQL**——currentServer 停在
      //    MySQL（最后一次连接），而后续活动 tab 属 PG：正是「活动 tab ≠
      //    currentServer」的多连接串味场景（T25 的收口对象）。
      pgServer = DbServer(
        id: 'actx_pg_e2e_${pgDbName.hashCode}',
        name: 'ACTX PG E2E',
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: pgDbName,
      );
      await appProvider.connection.saveConnection(pgServer);
      expect(
        await appProvider.connectToServer(pgServer),
        isTrue,
        reason: 'Failed to connect to PostgreSQL',
      );
      mysqlServer = DbServer(
        id: 'actx_mysql_e2e_${mysqlDbName.hashCode}',
        name: 'ACTX MySQL E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: mysqlDbName,
      );
      await appProvider.connection.saveConnection(mysqlServer);
      expect(
        await appProvider.connectToServer(mysqlServer),
        isTrue,
        reason: 'Failed to connect to MySQL',
      );
      expect(
        appProvider.connection.currentServer?.id,
        mysqlServer.id,
        reason: '夹具前置：currentServer 停在 MySQL（后连）',
      );
    });

    tearDown(() async {
      if (!mysqlReady || !pgReady) return;
      try {
        await appProvider.disconnectConnection(connectionId: mysqlServer.id);
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: pgServer.id);
      } catch (_) {}
      try {
        await mysqlAdapter.executeQuery(
          'DROP DATABASE IF EXISTS `$mysqlDbName`',
        );
      } catch (_) {}
      try {
        await mysqlAdapter.disconnect();
      } catch (_) {}
      // PG 不能 drop 当前连接库：经维护库（postgres）回收。
      try {
        await pgAdapter.disconnect();
        await pgAdapter.connect(
          DatabaseConnection(
            id: 'teardown_${pgDbName.hashCode}',
            name: 'Teardown PG',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: 'postgres',
          ),
        );
        await pgAdapter.executeQuery('DROP DATABASE IF EXISTS $pgDbName');
      } catch (_) {}
      try {
        await pgAdapter.disconnect();
      } catch (_) {}
      appProvider.dispose();
    });

    /// Q1 面板宿主（真实连接态经 provider；面板本体与生产装配同源）。
    Future<void> pumpMenuHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppProvider>.value(value: appProvider),
            ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider()..load(),
            ),
            ChangeNotifierProvider<ServerConnectionProvider>(
              create: (_) => ServerConnectionProvider(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            locale: const Locale('en'),
            home: const Scaffold(
              body: SizedBox(
                width: 260,
                height: 900,
                child: SidebarCapabilityMenu(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> pumpResultsHost(WidgetTester tester) async {
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

    testWidgets('Q1 面板随活动 tab 整体切换（currentServer 停在 MySQL）', (
      tester,
    ) async {
      if (!mysqlReady || !pgReady) return;

      // MySQL tab 活动 → 面板按 MySQL（标题 + MySQL 专有项 Variables）。
      appProvider.tab.addTab(
        QueryTab(
          id: 't-mysql',
          title: 'q-mysql',
          sql: 'SELECT 1',
          connectionId: mysqlServer.id,
          databaseName: mysqlDbName,
          databaseType: DatabaseType.mysql,
        ),
      );
      await pumpMenuHost(tester);

      expect(find.text('Capabilities: MySQL'), findsOneWidget);
      expect(find.text('Variables'), findsOneWidget, reason: 'MySQL 专有项');
      expect(find.text('Extensions'), findsNothing, reason: 'PG 专有项不应在');
      // currentServer=MySQL 旧序下面板恒 MySQL——切 PG tab 后的断言在旧
      // 代码上失败（差分锚定）。

      // PG tab 激活（addTab 置尾并激活）→ 面板整体切换为 PG。
      appProvider.tab.addTab(
        QueryTab(
          id: 't-pg',
          title: 'q-pg',
          sql: 'SELECT 2',
          connectionId: pgServer.id,
          databaseName: pgDbName,
          databaseType: DatabaseType.postgresql,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Capabilities: PostgreSQL'), findsOneWidget);
      expect(find.text('Extensions'), findsOneWidget, reason: 'PG 专有项');
      expect(find.text('Variables'), findsNothing, reason: 'MySQL 专有项退场');
      expect(find.text('Stored Procedures'), findsOneWidget, reason: 'core 共项');

      // 切回 MySQL tab → 面板切回（双向）。
      appProvider.tab.setActiveTab(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Capabilities: MySQL'), findsOneWidget);
      expect(find.text('Capabilities: PostgreSQL'), findsNothing);
    });

    testWidgets('PG 浏览 tab 结果网格：导出项在 + INSERT 引号按 PG 双引号', (
      tester,
    ) async {
      if (!mysqlReady || !pgReady) return;
      // 不覆写 view 尺寸：live binding 下沿 row_edit e2e 先例用默认窗口
      //（本用例含右键与菜单点击的输入派发）。

      // PG 连接上开浏览数据 tab（自动执行默认查询）；currentServer 保持
      // MySQL 不动（setUp 已保证）——活动 tab 属 PG。
      await appProvider.openBrowseDataTab(pgServer.id, pgDbName, 'users');
      await pumpResultsHost(tester);
      for (var i = 0; i < 20; i++) {
        if (find.text('Alice').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(
        find.text('Alice'),
        findsWidgets,
        reason: 'PG 浏览查询自动执行后网格应渲染 Alice',
      );
      expect(
        appProvider.tab.activeTab?.connectionId,
        pgServer.id,
        reason: '前置：活动 tab 属 PG 连接',
      );

      // 行右键 → 导出项出现（PG 支持 SQL 导出；tab 侧解析）。
      // 与 row_edit e2e 同一交互形态（tester.tap + kSecondaryButton）。
      await tester.tap(find.text('Alice').first, buttons: kSecondaryButton);
      // 菜单在 await 行编辑可用性判定（真库 getTableColumns 网关往返）之后
      // 才开——长轮询等待（每秒一拍，至多 15s）；断出后必须 pumpAndSettle
      // 把 popup 入场过渡 pump 完（ModalRoute 过渡未完成时整棵 modal 处于
      // IgnorePointer——可见但不可点）。
      for (var i = 0; i < 15; i++) {
        if (find.text('Copy Cell').evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      // 菜单已开（导出项在 = _supportsSqlExport 按 tab 侧 PG 取真）。
      final exportRowItem = find.text('Export Row as SQL INSERT');
      expect(exportRowItem, findsOneWidget);

      // 执行导出 → 剪贴板 INSERT 按 PG 双引号（旧实现读 currentServer=
      // MySQL 会生成反引号——差分锚定）。
      await tester.tap(exportRowItem);
      await tester.pumpAndSettle();
      final data = await Clipboard.getData('text/plain');
      expect(data?.text, isNotNull, reason: '导出应写入剪贴板');
      expect(
        data!.text,
        contains('"users"'),
        reason: 'PG 方言双引号（不随 MySQL currentServer 串味）',
      );
      expect(data.text, isNot(contains('`users`')));
      expect(data.text, contains('INSERT INTO "users"'));
    });
  });
}
