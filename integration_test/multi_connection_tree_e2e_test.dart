// ============================================================================
// T26（J3 多连接长驻树）· 多连接树主体真库 E2E — MySQL 8.0 + PostgreSQL 17 +
// Redis 7 三连接同树。
//
// 覆盖（任务书 T26 真库验证节）：
// - 三根节点同树常驻、各自展开（MySQL/PG 库列表 + Redis 连接级整树）；
// - PG 连接的表双击 → 新 tab connectionId=PG、预填默认浏览查询、
//   currentServer 零切换（跨连接开表）；右键「浏览数据」进 data 模式；
// - 活动 tab 切换 → 树根高亮跟随（activeContextConnection）+ Q1 面板随
//   活动 tab（T25 联动断言）；
// - 断开 PG → 子树灰化不消失、展开记忆随 FR-007 清理；重连 → 自动展开
//   + 子展开清理后重新懒加载；
// - 收藏 A 连接表 + B 连接表 → 树顶区两连接名前缀并陈、点击各自打开
//   正确连接 tab（零切换）；
// - 搜索跨连接命中（输 PG 库名 → PG 连接展开、非匹配连接隐藏）。
//
// 环境：WSL 全矩阵（连接信息唯一来源 `D:\workspace\dbmaster\test_db_local_wsl.txt`，
// 口令经 --dart-define 注入，不入库）；MySQL/PG 网关壳硬依赖 embedded server
//（DBMASTER_SERVER_BIN 为进程 env，非 dart-define）。二进制/配置不可得时
// 全组以可 grep 的 MTREE_E2E_SKIP 跳过（无假绿）。
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
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/organisms/sidebar_widget.dart';
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
import 'config/redis_test_config.dart';
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
      print('MTREE_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供');
      mysqlReady = false;
    }
    // 与 MySQL 共用同一 embedded server 会话（幂等复用）。
    pgReady = await ensureEmbeddedServerForPgE2E();
    if (pgReady && !PostgreSQLTestConfig.available) {
      // ignore: avoid_print
      print('MTREE_E2E_SKIP: DBMASTER_PG_* 未通过 --dart-define 提供');
      pgReady = false;
    }
  });

  group('Multi-Connection Tree E2E (MySQL + PG + Redis, T26)', () {
    late AppProvider appProvider;
    late MySQLAdapter mysqlAdapter;
    late PostgreSQLAdapter pgAdapter;
    late String mysqlDbName;
    late String pgDbName;
    late DbServer mysqlServer;
    late DbServer pgServer;
    late DbServer redisServer;
    bool redisConnected = false;

    const mysqlLabel = 'MTREE MySQL E2E';
    const pgLabel = 'MTREE PG E2E';
    const redisLabel = 'MTREE Redis E2E';

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

      // 1. 种子连接建专用库 + users 表（自建自删）。
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

      // 2. 三连接接入 provider（PG → MySQL → Redis）：currentServer 停在
      //    Redis（最后一次连接），后续导航/开表全部不得动它（J3 零切换
      //    差分锚定）。Redis 直连 TCP（无网关依赖），失败只降级 Redis 断言。
      pgServer = DbServer(
        id: 'mtree_pg_${pgDbName.hashCode}',
        name: pgLabel,
        type: DatabaseType.postgresql,
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: pgDbName,
      );
      await appProvider.connection.saveConnection(pgServer);
      expect(await appProvider.connectToServer(pgServer), isTrue);

      mysqlServer = DbServer(
        id: 'mtree_mysql_${mysqlDbName.hashCode}',
        name: mysqlLabel,
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: mysqlDbName,
      );
      await appProvider.connection.saveConnection(mysqlServer);
      expect(await appProvider.connectToServer(mysqlServer), isTrue);

      redisServer = DbServer(
        id: 'mtree_redis_e2e',
        name: redisLabel,
        type: DatabaseType.redis,
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        username: null,
        password: RedisTestConfig.password.isEmpty ? null : RedisTestConfig.password,
      );
      await appProvider.connection.saveConnection(redisServer);
      try {
        redisConnected = await appProvider.connectToServer(redisServer);
      } catch (_) {
        redisConnected = false;
      }
    });

    tearDown(() async {
      if (!mysqlReady || !pgReady) return;
      try {
        await appProvider.disconnectConnection(connectionId: mysqlServer.id);
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: pgServer.id);
      } catch (_) {}
      if (redisConnected) {
        try {
          await appProvider.disconnectConnection(connectionId: redisServer.id);
        } catch (_) {}
      }
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
      // 清理跨用例 prefs 键（收藏/最近/分组）。
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('recent_tables');
        await prefs.remove('sidebar_favorite_tables');
        await prefs.remove('connection_groups');
      } catch (_) {}
      appProvider.dispose();
    });

    // ==================== harness ====================

    Future<void> pumpSidebar(WidgetTester tester) async {
      // 视口加高（金标准先例）：三连接树多行 + Q1 面板常驻，默认 800×600
      // 装不下；逐测恢复。
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
            home: const Scaffold(body: SidebarWidget()),
          ),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Finder node(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TreeItem),
    );

    Future<void> tapNode(WidgetTester tester, String label) async {
      await tester.ensureVisible(node(label));
      await tester.pumpAndSettle();
      await tester.tap(node(label));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> doubleTapNode(WidgetTester tester, String label) async {
      await tester.ensureVisible(node(label));
      await tester.pumpAndSettle();
      await tester.tap(node(label));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(node(label));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Future<void> rightClickNode(WidgetTester tester, String label) async {
      await tester.ensureVisible(node(label));
      await tester.pumpAndSettle();
      await tester.tap(node(label), buttons: kSecondaryButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    /// 轮询等待文本出现（真库懒加载往返，每秒一拍）。
    Future<void> waitText(WidgetTester tester, Finder finder, String because) async {
      for (var i = 0; i < 15; i++) {
        if (finder.evaluate().isNotEmpty) return;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(finder.evaluate(), isNotEmpty, reason: because);
    }

    /// 带重试的展开点击：重连/刷新后的后台重建churn会偶发吞掉单次 tap
    ///（手势识别中元素被换出）——目标未出现则再点（每轮间隔轮询目标，
    /// 已展开即不再补点，防误折叠）。
    Future<void> tapAndWait(
      WidgetTester tester,
      String label,
      Finder goal,
      String because,
    ) async {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (goal.evaluate().isNotEmpty) return;
        await tapNode(tester, label);
        for (var i = 0; i < 8; i++) {
          if (goal.evaluate().isNotEmpty) return;
          await tester.pump(const Duration(seconds: 1));
        }
      }
      expect(goal.evaluate(), isNotEmpty, reason: because);
    }

    /// 树行查找（排除搜索框 EditableText 的同名文本歧义）。
    Finder rowOf(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(TreeItem),
    );

    /// PG 树展开链（schema-aware）：根 → 库 → public schema → Tables
    /// 分类 → users 行可见。每步等待真库懒加载往返（churn 重试）。
    Future<void> expandPgToUsers(WidgetTester tester) async {
      await tapAndWait(
        tester,
        pgLabel,
        find.text(pgDbName),
        'PG 库列表应渲染',
      );
      await tapAndWait(tester, pgDbName, find.text('public'), 'public schema 行应渲染');
      await tapAndWait(
        tester,
        'public',
        find.textContaining('Tables'),
        '表分类头应渲染',
      );
      await tapAndWait(tester, 'Tables (1)', find.text('users'), 'users 表行应渲染');
    }

    TreeItem rootItem(WidgetTester tester, String label) =>
        tester.widget<TreeItem>(node(label).first);

    // ==================== 场景 ①③：三连接同树 + 活动根高亮/Q1 联动 ====================

    testWidgets('三根节点同树常驻、各自展开；活动 tab 切换 → 根高亮 + Q1 联动', (tester) async {
      if (!mysqlReady || !pgReady) return;
      await pumpSidebar(tester);

      // 三根节点同时可见（J3：全部连接常驻，无需切换）。
      expect(find.text(pgLabel), findsOneWidget);
      expect(find.text(mysqlLabel), findsOneWidget);
      expect(find.text(redisLabel), findsOneWidget);
      expect(rootItem(tester, redisLabel).showArrow, redisConnected,
          reason: 'Redis 连接态');

      // 各自展开（互不影响）：PG 库列表 + MySQL 库列表 + Redis 连接级整树。
      await tapNode(tester, pgLabel);
      await waitText(tester, find.text(pgDbName), 'PG 库列表应渲染');
      await tapNode(tester, mysqlLabel);
      await waitText(tester, find.text(mysqlDbName), 'MySQL 库列表应渲染');
      if (redisConnected) {
        await tapNode(tester, redisLabel);
        // Redis 连接级整树：全局节点 Replication（Redis 专有标签，SQL 连接
        // 树无此词）出现即证明插件整树接管渲染。
        await waitText(
          tester,
          find.text('Replication'),
          'Redis 连接级整树应渲染（全局节点）',
        );
      }
      // 展开态并存（三连接同时展开，互不挤占）。
      expect(find.text(pgDbName), findsOneWidget);
      expect(find.text(mysqlDbName), findsOneWidget);

      // 场景③：活动 tab → 树根高亮跟随（activeContextConnection）+ Q1 联动。
      appProvider.tab.addTab(
        QueryTab(
          id: 't-pg',
          title: 'q-pg',
          sql: 'SELECT 1',
          connectionId: pgServer.id,
          databaseName: pgDbName,
          databaseType: DatabaseType.postgresql,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        rootItem(tester, pgLabel).isSelected,
        isTrue,
        reason: 'PG tab 活动 → PG 根高亮',
      );
      expect(
        rootItem(tester, mysqlLabel).isSelected,
        isFalse,
        reason: '非活动连接根不高亮',
      );
      expect(find.text('Capabilities: PostgreSQL'), findsOneWidget,
          reason: 'Q1 面板随活动 tab（T25 联动）');

      appProvider.tab.addTab(
        QueryTab(
          id: 't-mysql',
          title: 'q-mysql',
          sql: 'SELECT 2',
          connectionId: mysqlServer.id,
          databaseName: mysqlDbName,
          databaseType: DatabaseType.mysql,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(rootItem(tester, mysqlLabel).isSelected, isTrue,
          reason: 'MySQL tab 活动 → MySQL 根高亮');
      expect(rootItem(tester, pgLabel).isSelected, isFalse);
      expect(find.text('Capabilities: MySQL'), findsOneWidget);
      expect(find.text('Capabilities: PostgreSQL'), findsNothing);
    });

    // ==================== 场景 ②⑤：跨连接开表 + 收藏跨连接 ====================

    testWidgets('PG 表双击跨连接开表零切换 + 浏览数据 data 模式 + 收藏跨连接', (tester) async {
      if (!mysqlReady || !pgReady) return;
      await pumpSidebar(tester);

      // 展开 PG → public schema → Tables 分类（schema-aware 展开链）。
      await expandPgToUsers(tester);

      // 场景②：双击 users → 新 tab connectionId=PG + 预填默认浏览查询，
      // currentServer 零切换（浏览连接 B 不劫持执行默认连接）。
      final currentServerIdBefore = appProvider.connection.currentServer?.id;
      final tabCountBefore = appProvider.tab.tabs.length;
      await doubleTapNode(tester, 'users');

      expect(appProvider.tab.tabs.length, tabCountBefore + 1);
      final newTab = appProvider.tab.tabs.last;
      expect(newTab.connectionId, pgServer.id, reason: 'tab 自带 PG 连接上下文');
      expect(newTab.sql, contains('users'), reason: '预填默认浏览查询');
      expect(
        appProvider.connection.currentServer?.id,
        currentServerIdBefore,
        reason: 'J3 导航零全局切换（currentServer 不动）',
      );
      final layout = appProvider.tab.panelLayoutFor(newTab.id);
      expect(layout.editorVisible, isTrue, reason: '双击进 query 模式');

      // 预填的默认浏览查询在 PG 真库可执行（gateway 通道，按 cid 路由）。
      final rows = await appProvider.dbService.executeQuery(
        newTab.sql,
        connectionId: pgServer.id,
        database: pgDbName,
      );
      expect(rows, isNotEmpty, reason: '预填查询在 PG 执行有结果');

      // 右键 users → Browse Data → data 模式（自动执行默认查询）。
      final dataTabsBefore = appProvider.tab.tabs
          .where((t) => appProvider.tab.browseTargetFor(t.id) != null)
          .length;
      await rightClickNode(tester, 'users');
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SidebarWidget)),
      )!;
      final browseItem = find.text(l10n.browseData);
      expect(browseItem, findsOneWidget, reason: '右键菜单 Browse Data 项在');
      await tester.tap(browseItem);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      final dataTabsAfter = appProvider.tab.tabs
          .where((t) => appProvider.tab.browseTargetFor(t.id) != null)
          .length;
      expect(dataTabsAfter, dataTabsBefore + 1, reason: '浏览数据开 data 模式 tab');
      expect(
        appProvider.connection.currentServer?.id,
        currentServerIdBefore,
        reason: '浏览导航全程零全局切换',
      );

      // 场景⑤：跨连接收藏并陈 + 点击各自打开正确连接 tab。
      appProvider.sidebar.toggleFavoriteTable('${pgServer.id}:$pgDbName:users');
      appProvider.sidebar
          .toggleFavoriteTable('${mysqlServer.id}:$mysqlDbName:users');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('$pgLabel · users'), findsOneWidget, reason: 'PG 收藏行');
      expect(find.text('$mysqlLabel · users'), findsOneWidget,
          reason: 'MySQL 收藏行（两连接名前缀并陈树顶）');

      await tapNode(tester, '$mysqlLabel · users');
      expect(appProvider.tab.activeTab?.connectionId, mysqlServer.id,
          reason: '点 MySQL 收藏 → 活动 tab 属 MySQL');
      await tapNode(tester, '$pgLabel · users');
      expect(appProvider.tab.activeTab?.connectionId, pgServer.id,
          reason: '点 PG 收藏 → 活动 tab 属 PG');
      expect(
        appProvider.connection.currentServer?.id,
        currentServerIdBefore,
        reason: '收藏导航全程零全局切换',
      );
    });

    // ==================== 场景④：断开灰化 + 重连 FR-007 ====================

    testWidgets('断开 PG：子树灰化不消失；重连：自动展开 + FR-007 子展开清理重懒加载', (tester) async {
      if (!mysqlReady || !pgReady) return;
      await pumpSidebar(tester);

      // 先展开 PG 到表行（制造「有子树展开记忆」的前置态）。
      await expandPgToUsers(tester);

      // 断开 PG：根节点保留（灰化、不可展开），子树消失。
      await appProvider.disconnectConnection(connectionId: pgServer.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(pgLabel), findsOneWidget, reason: '断开后根节点不消失');
      expect(rootItem(tester, pgLabel).showArrow, isFalse,
          reason: '断开根行灰化（无展开箭头）');
      expect(rowOf(pgDbName).evaluate(), isEmpty, reason: '断开后子树收起');
      expect(find.text(mysqlLabel), findsOneWidget,
          reason: '其它连接不受断开影响');

      // 重连：ConnectionEstablished → 根自动展开（US1）+ FR-007 子展开清理
      //（库/schema/表分类回到折叠、重新懒加载）。
      expect(await appProvider.connectToServer(pgServer), isTrue);
      for (var i = 0; i < 15; i++) {
        if (rowOf(pgDbName).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }
      expect(rootItem(tester, pgLabel).showArrow, isTrue, reason: '重连后可展开');
      expect(rowOf(pgDbName).evaluate(), isNotEmpty,
          reason: '重连自动展开 + 库列表重新装载');
      expect(rowOf('users').evaluate(), isEmpty,
          reason: 'FR-007：子展开清理，表行回到折叠态');

      // 重新展开库 → schema → 表分类 → 表行（懒加载恢复，churn 重试）。
      await tapAndWait(tester, pgDbName, find.text('public'), '重连后 schema 行可再展开');
      await tapAndWait(
        tester,
        'public',
        find.textContaining('Tables'),
        '重连后表分类头可再展开',
      );
      await tapAndWait(tester, 'Tables (1)', find.text('users'), '重连后表行重新懒加载');
    });

    // ==================== 场景⑥：搜索跨连接 ====================

    testWidgets('搜索跨连接命中：输 PG 库名 → PG 连接展开、非匹配连接隐藏', (tester) async {
      if (!mysqlReady || !pgReady) return;
      await pumpSidebar(tester);

      // 侧栏搜索框输入 PG 专用库名（server-side search 异步往返）。
      await tester.enterText(find.byType(TextField), pgDbName);
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        if (rowOf(pgDbName).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text(pgLabel), findsOneWidget, reason: '库名命中的 PG 连接保留');
      expect(rowOf(pgDbName).evaluate(), isNotEmpty,
          reason: '命中连接被置展开（库节点渲染）');
      expect(find.text(mysqlLabel), findsNothing,
          reason: '无匹配 MySQL 连接隐藏');
      expect(find.text(redisLabel), findsNothing,
          reason: '无匹配 Redis 连接隐藏');
    });
  });
}
