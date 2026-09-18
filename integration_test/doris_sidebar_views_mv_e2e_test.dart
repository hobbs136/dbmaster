// ============================================================================
// Doris Sidebar Widget E2E — Views/MV Category Nodes & Context Menus
// 目标：验证空态分类节点渲染 + Create View / Create MV 右键菜单可达
// 连真实 Doris 3.0.2，使用 root 用户（避免 __internal_schema 权限问题）。
// 每个用例自建自删专用库，不污染共享状态。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/molecules/context_menu.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
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

  group('Doris Sidebar Views/MV E2E (real DB + AppProvider)', () {
    late AppProvider appProvider;
    late String testDbName;
    late DbServer server;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      testDbName = DorisTestConfig.generateTestDatabaseName();

      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      // 与其余 Doris 套件同源凭据（DorisTestConfig）。曾用 root/'' 规避
      // remote_user 的 __internal_schema 权限问题——该凭据现无法连接（历史
      // 5 失败根因：setUp 静默 return → 全树不渲染）；remote_user 已具备
      // 建库能力（doris_create_table 套件同凭据建库通过）。
      server = DbServer(
        id: 'doris_vm_${testDbName.hashCode}',
        name: 'Doris VM E2E',
        type: DatabaseType.doris,
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );
      await appProvider.connection.saveConnection(server);
      final connected = await appProvider.connectToServer(server);
      if (!connected) return; // Tests skip when connection fails

      await appProvider.dbService.createDatabase(testDbName);
      // 顺序敏感：useDatabase 先行（seed 落 testDbName）；refreshDatabases
      // 在后——它会按「当前库桩」（connect 时选的默认库）切换共享连接的
      // 上下文，若 refresh 夹在中间，未限定库名的 DDL 会落错库（曾报
      // seed_t already exists = 落进默认库的历史残留）。
      await appProvider.dbService.useDatabase(testDbName);

      // Seed: one table but ZERO views and ZERO MVs
      await appProvider.dbService.executeQuery(
        'CREATE TABLE `seed_t` (`id` INT NOT NULL, `val` VARCHAR(50) NOT NULL) '
        'DUPLICATE KEY(`id`) '
        'DISTRIBUTED BY HASH(`id`) BUCKETS 1 '
        'PROPERTIES("replication_num" = "1")',
      );
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
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    // =========================================================================
    // Views "(0)" category node renders for empty Doris database
    // =========================================================================
    testWidgets(
      'Views category node renders with "(0)" when database has no views',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpDorisHarness(tester, appProvider);
        await expandDorisConnection(tester, 'Doris VM E2E');
        await expandDorisDatabase(tester, testDbName);

        // Views category node should render even when empty
        // （锚定正则：textContaining('Views') 会连带命中 'Materialized Views'
        // ——两分类头都含该子串，歧义 2 命中）
        final viewsNode = find.ancestor(
          of: find.textContaining(RegExp(r'^Views \(\d+\)$')),
          matching: find.byType(TreeItem),
        );
        expect(viewsNode, findsOneWidget,
            reason: 'Views category header should render even with 0 views');

        expect(find.textContaining(RegExp(r'^Views \(0\)$')), findsOneWidget,
            reason: 'Should show "(0)" for empty Views');
      },
    );

    // =========================================================================
    // Materialized Views "(0)" category node renders
    // =========================================================================
    testWidgets(
      'Materialized Views category node renders with "(0)" when empty',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpDorisHarness(tester, appProvider);
        await expandDorisConnection(tester, 'Doris VM E2E');
        await expandDorisDatabase(tester, testDbName);

        final mvNode = find.ancestor(
          of: find.textContaining('Materialized Views'),
          matching: find.byType(TreeItem),
        );
        expect(mvNode, findsOneWidget,
            reason: 'MV category header should render even with 0 MVs');

        expect(find.textContaining('Materialized Views (0)'), findsOneWidget,
            reason: 'Should show "(0)" for empty Materialized Views');
      },
    );

    // =========================================================================
    // Right-click Views "(0)" → "Create New View" context menu appears
    // =========================================================================
    testWidgets(
      'Right-click Views (0) shows "Create New View" context menu item',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpDorisHarness(tester, appProvider);
        await expandDorisConnection(tester, 'Doris VM E2E');
        await expandDorisDatabase(tester, testDbName);

        // 标签实为 'Views (0)'（带计数）——helper 是精确 text 匹配。
        await rightClickDorisNode(tester, 'Views (0)');

        expect(find.byType(ContextMenu), findsOneWidget,
            reason: 'Context menu should appear on right-click');

        final createViewItem = find.descendant(
          of: find.byType(ContextMenu),
          matching: find.textContaining('Create New View'),
        );
        expect(createViewItem, findsOneWidget,
            reason: '"Create New View" should appear in Views context menu');

        final refreshItem = find.descendant(
          of: find.byType(ContextMenu),
          matching: find.textContaining('Refresh'),
        );
        expect(refreshItem, findsOneWidget,
            reason: 'Refresh should appear in context menu');
      },
    );

    // =========================================================================
    // Right-click MV "(0)" → "Create New Materialized View" context menu
    // =========================================================================
    testWidgets(
      'Right-click Materialized Views (0) shows "Create New Materialized View"',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
        await pumpDorisHarness(tester, appProvider);
        await expandDorisConnection(tester, 'Doris VM E2E');
        await expandDorisDatabase(tester, testDbName);

        // 标签实为 'Materialized Views (0)'（带计数）——helper 是精确 text 匹配。
        await rightClickDorisNode(tester, 'Materialized Views (0)');

        expect(find.byType(ContextMenu), findsOneWidget);

        final createMvItem = find.descendant(
          of: find.byType(ContextMenu),
          matching: find.textContaining('Create New Materialized View'),
        );
        expect(createMvItem, findsOneWidget,
            reason: '"Create New Materialized View" should appear in MV context menu');
      },
    );

    // =========================================================================
    // Non-empty Views category shows actual count after creating a view
    // =========================================================================
    testWidgets(
      'Views category reflects count after creating a view',
      (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      // Create a view via the provider's dbService（显式带库：refresh 后共享
      // 连接上下文在默认库桩上，未限定 DDL 会落错库）。
      await appProvider.dbService.executeQuery(
        'CREATE VIEW `test_v` AS SELECT id, val FROM `seed_t`',
        database: testDbName,
      );
        await appProvider.refreshDatabases();

        await pumpDorisHarness(tester, appProvider);
        await expandDorisConnection(tester, 'Doris VM E2E');
        await expandDorisDatabase(tester, testDbName);
        // 锚定正则避免歧义（同 test 1 注）。
        await expandDorisCategory(tester, RegExp(r'^Views \(\d+\)$'));

        expect(find.textContaining(RegExp(r'^Views \(1\)$')), findsOneWidget,
            reason: 'Views count should update to 1 after creating a view');

        expect(find.text('test_v'), findsOneWidget,
            reason: 'View name should appear as a child node');
      },
    );
  });
}
