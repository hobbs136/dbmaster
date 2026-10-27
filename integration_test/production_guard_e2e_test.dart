// ============================================================================
// 生产守卫真库 E2E（v0.3.5 UI 批4 T9 / B-07 · UI35-E2E-*）
// Tests: production 连接上 DROP / TRUNCATE / 无 WHERE DELETE 全链路真生效
//        （守卫弹窗交互 + 重查数据断言）+ 非 production 回归（既有门不变）。
// Target: real MySQL 8.0（WSL 经 python 转发桥 13306）+ embedded server
//         网关（mysql_gateway_adapter 硬依赖 dbmaster server 会话，D6）。
//
// 运行（凭据不入库：DBMASTER_MYSQL_PASSWORD 经 --dart-define 注入，明文见
// 工作区根 test_db_local_wsl.txt；DBMASTER_SERVER_BIN 走环境变量指向
// dist/Release/dbmaster-server.exe）：
//   flutter test -d windows integration_test/production_guard_e2e_test.dart \
//     --dart-define=DBMASTER_MYSQL_HOST=127.0.0.1 \
//     --dart-define=DBMASTER_MYSQL_PORT=13306 \
//     --dart-define=DBMASTER_MYSQL_USER=root \
//     --dart-define=DBMASTER_MYSQL_PASSWORD=<test_db_local_wsl.txt>
//
// 环境门控：embedded 二进制不可得 / dart-define 缺参 → 可 grep 的
// MYSQL_E2E_SKIP 整组跳过（无假绿，金标准 mysql_sidebar_menu_e2e 同款）。
//
// 用例登记（主代理归档进 docs/test/unified_test_spec.md）：
//   UI35-E2E-001 sidebar DROP（L1）：守卫弹窗 + 错误名锁定 + 表名匹配确认
//                        → 重查 getTables() 断言真删。
//   UI35-E2E-002 sidebar TRUNCATE（L1）：守卫弹窗 + 表名匹配确认 → 重查
//                        COUNT 断言清零、表结构保留。
//   UI35-E2E-003 编辑器无 WHERE DELETE（L2）：守卫弹窗 → 取消重查行数不变
//                        （零执行）；再执行 → 确认 → 重查全删（真生效）。
//   UI35-E2E-004 非 production（testing）回归：同 DROP 动作走既有
//                        type-to-confirm 门（守卫不出现），确认后真删。
// ============================================================================

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/molecules/context_menu.dart';
import 'package:dbmaster/organisms/dialogs/production_guard_dialog.dart';
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/theme/app_theme.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// 专用种子表（每测独立库，setUp 建 / tearDown 删，不碰共享库）。
const _dropTable = 'guard_drop_src';
const _truncTable = 'guard_trunc_src';
const _delTable = 'guard_del_src';
const _nonProdTable = 'guard_nonprod_src';

const _prodLabel = 'Guard E2E Production';
const _testLabel = 'Guard E2E Testing';

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

  group('Production Guard E2E（真 MySQL · embedded 网关）', () {
    late AppProvider appProvider;
    late MySQLAdapter adapter;
    late ThemeProvider themeProvider;
    late LocaleProvider localeProvider;
    late LayoutPreferencesProvider layoutProvider;
    late String testDbName;
    late DbServer prodServer;
    late DbServer testServer;
    late AppLocalizations l10n;

    setUpAll(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    setUp(() async {
      // AG-F-19：prefs 隔离（金标准同款）——mock 存储，杜绝直写真实偏好。
      SharedPreferences.setMockInitialValues({});

      // 1. 种子：专用库 + 四张表（每测各消费一张）。
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      final seedConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}',
        name: 'Seed Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await adapter.connect(seedConn);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      Future<void> seedTable(String table, int rows) async {
        await adapter.createTable(table, [
          DbColumn(
            name: 'id',
            type: 'INT',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'name', type: 'VARCHAR(64)', isNullable: false),
        ]);
        final values = List.generate(
          rows,
          (i) => "(${i + 1}, 'row_$i')",
        ).join(', ');
        await adapter.executeQuery('INSERT INTO `$table` (id, name) VALUES $values');
      }

      await seedTable(_dropTable, 2);
      await seedTable(_truncTable, 3);
      await seedTable(_delTable, 5);
      await seedTable(_nonProdTable, 2);

      // 2. 真实 AppProvider + 两环境连接（同库不同 environment）。
      appProvider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      prodServer = DbServer(
        id: 'guard_prod_${testDbName.hashCode}',
        name: _prodLabel,
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        environment: ConnectionEnvironment.production,
      );
      testServer = DbServer(
        id: 'guard_test_${testDbName.hashCode}',
        name: _testLabel,
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        environment: ConnectionEnvironment.testing,
      );
      await appProvider.connection.saveConnection(prodServer);
      expect(
        await appProvider.connectToServer(prodServer),
        isTrue,
        reason: 'production 连接应建立成功',
      );
      await appProvider.connection.saveConnection(testServer);
      expect(
        await appProvider.connectToServer(testServer),
        isTrue,
        reason: 'testing 连接应建立成功',
      );

      // 3. 编辑器 harness 依赖（b123 同款）。
      themeProvider = ThemeProvider();
      localeProvider = LocaleProvider();
      layoutProvider = LayoutPreferencesProvider();
      await themeProvider.load();
      await localeProvider.load();
      await layoutProvider.load();
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: prodServer.id);
      } catch (_) {}
      try {
        await appProvider.disconnectConnection(connectionId: testServer.id);
      } catch (_) {}
      try {
        appProvider.dispose();
      } catch (_) {}
    });

    // ----------------------------------------------------------------------
    // Helpers（金标准 mysql_sidebar_menu_e2e + multi_connection_tree 手法）
    // ----------------------------------------------------------------------
    Widget buildSidebarApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ServerConnectionProvider>(
            create: (_) => ServerConnectionProvider(),
          ),
          ChangeNotifierProvider.value(value: appProvider),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: _GuardSidebarHarness(provider: appProvider),
        ),
      );
    }

    Widget buildEditorApp() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: appProvider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layoutProvider,
          ),
          Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
        ],
        child: Consumer2<LocaleProvider, ThemeProvider>(
          builder: (context, locale, theme, _) {
            return MaterialApp(
              locale: locale.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(theme.accentColorValue),
              home: const Scaffold(
                body: SizedBox(
                  width: 1280,
                  height: 800,
                  child: QueryEditorWidget(tabIndex: 0),
                ),
              ),
            );
          },
        ),
      );
    }

    Future<void> pumpSidebar(WidgetTester tester) async {
      // 视口加高（金标准同款）：双连接根 + 库 + 表分类全树可见，避免
      // tap 派生 Offset 落视口外不命中、lazy 列表项不构建。
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildSidebarApp());
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    Finder node(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(TreeItem));

    Future<void> tapNode(WidgetTester tester, String label) async {
      await tester.ensureVisible(node(label));
      await tester.pumpAndSettle();
      await tester.tap(node(label));
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> rightClickNode(WidgetTester tester, String label) async {
      await tester.ensureVisible(node(label));
      await tester.pumpAndSettle();
      await tester.tap(node(label), buttons: kSecondaryButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    Future<void> tapMenuItem(WidgetTester tester, String label) async {
      final menuFinder = find.byType(ContextMenu);
      expect(menuFinder, findsOneWidget, reason: 'Context menu not open');
      final finder = find.descendant(
        of: menuFinder,
        matching: find.text(label),
      );
      expect(finder, findsOneWidget, reason: 'Menu item "$label" not found');
      await tester.tap(finder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    /// 带重试的展开点击（multi_connection_tree 同款）：真库懒加载往返
    /// 期间后台重建 churn 会偶发吞掉单次 tap——目标未出现则再点。
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

    Future<void> expandCategory(WidgetTester tester, String prefix) async {
      final headerFinder = find.ancestor(
        of: find.textContaining(prefix),
        matching: find.byType(TreeItem),
      );
      expect(headerFinder, findsOneWidget);
      await tester.ensureVisible(headerFinder);
      await tester.pumpAndSettle();
      await tester.tap(headerFinder);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    /// 展开连接根 → 专用库 → Tables 分类，右键目标表并点菜单项。
    Future<void> rightClickTable(
      WidgetTester tester, {
      required String connectionLabel,
      required String table,
      required String menuLabel,
    }) async {
      await tapAndWait(
        tester,
        connectionLabel,
        find.text(testDbName),
        '连接根展开后应出现专用库 $testDbName',
      );
      await tapAndWait(
        tester,
        testDbName,
        find.textContaining('Tables'),
        '库展开后应出现 Tables 分类',
      );
      await expandCategory(tester, 'Tables');
      await tapAndWait(
        tester,
        'Tables',
        find.text(table),
        'Tables 分类展开后应出现表 $table',
      );
      await rightClickNode(tester, table);
      await tapMenuItem(tester, menuLabel);
    }

    /// 守卫弹窗目标名输入框（弹窗内唯一 TextField）。
    Finder guardNameField() => find.descendant(
          of: find.byType(ProductionGuardDialog),
          matching: find.byType(TextField),
        );

    /// 守卫确认钮 ElevatedButton（onPressed null = 锁定）。
    Finder guardConfirmButton() => find.ancestor(
          of: find.text(l10n.prodGuardConfirmDrop),
          matching: find.byType(ElevatedButton),
        );

    /// 旧门确认钮点击（金标准 tapDialogButton：AlertDialog 内按钮）。
    Future<void> tapDialogButton(WidgetTester tester, String label) async {
      final dialogFinder = find.byType(AlertDialog);
      final finder = find.descendant(
        of: dialogFinder,
        matching: find.widgetWithText(TextButton, label),
      );
      if (finder.evaluate().isNotEmpty) {
        await tester.tap(finder);
      } else {
        final elevatedFinder = find.descendant(
          of: dialogFinder,
          matching: find.widgetWithText(ElevatedButton, label),
        );
        expect(elevatedFinder, findsOneWidget);
        await tester.tap(elevatedFinder);
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    /// 真实网关往返不排帧——轮询直到条件成立或超时（pump 驱动）。
    Future<bool> waitUntil(
      WidgetTester tester,
      bool Function() predicate, {
      Duration timeout = const Duration(seconds: 30),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (!predicate()) {
        if (DateTime.now().isAfter(deadline)) return false;
        await tester.pump(const Duration(milliseconds: 100));
      }
      return true;
    }

    /// 数据真生效轮询（真实时钟，经种子 adapter 重查——独立会话读已提交）。
    Future<bool> waitForDb(
      Future<bool> Function() predicate, {
      Duration timeout = const Duration(seconds: 20),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (true) {
        if (await predicate()) return true;
        if (DateTime.now().isAfter(deadline)) return false;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    Future<int> rowCount(String table) async {
      final res = await adapter.executeQuery(
        'SELECT COUNT(*) AS c FROM `$table`',
      );
      return int.parse(res.rows.first['c'].toString());
    }

    Future<bool> tableExists(String table) async {
      final tables = await adapter.getTables();
      return tables.contains(table);
    }

    // ----------------------------------------------------------------------
    // UI35-E2E-001 · sidebar DROP（L1）
    // ----------------------------------------------------------------------
    testWidgets(
      'UI35-E2E-001 production 右键 Drop → 守卫 L1：错误名锁定 / 表名匹配确认 → 真删',
      (tester) async {
        if (!mysqlE2EGatewayReady) return;

        await pumpSidebar(tester);
        await rightClickTable(
          tester,
          connectionLabel: _prodLabel,
          table: _dropTable,
          menuLabel: l10n.dropTable,
        );

        // 守卫弹窗出现（L1 标题 + SQL 预览），非既有 type-to-confirm 门。
        expect(
          find.byType(ProductionGuardDialog),
          findsOneWidget,
          reason: 'production 连接 Drop 应分流到生产守卫弹窗',
        );
        expect(find.text(l10n.prodGuardTitleL1), findsOneWidget);
        expect(find.text('DROP TABLE `$testDbName`.`$_dropTable`'), findsOneWidget);

        // 错误名 → 确认钮锁定（onPressed null）。
        await tester.enterText(guardNameField(), 'totally_wrong_name');
        await tester.pump();
        expect(
          tester.widget<ElevatedButton>(guardConfirmButton()).onPressed,
          isNull,
          reason: 'L1 目标名不匹配时确认钮必须不可用',
        );

        // 正确表名 → 解锁 → 确认。
        await tester.enterText(guardNameField(), _dropTable);
        await tester.pump();
        expect(
          tester.widget<ElevatedButton>(guardConfirmButton()).onPressed,
          isNotNull,
          reason: 'L1 目标名完全匹配后确认钮应解锁',
        );
        await tester.tap(find.text(l10n.prodGuardConfirmDrop));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 断言真生效：重查 getTables()（非仅弹窗交互）。
        final gone = await waitForDb(() async => !await tableExists(_dropTable));
        expect(gone, isTrue, reason: '守卫确认后 DROP 应真生效（重查表不存在）');
      },
    );

    // ----------------------------------------------------------------------
    // UI35-E2E-002 · sidebar TRUNCATE（L1）
    // ----------------------------------------------------------------------
    testWidgets(
      'UI35-E2E-002 production 右键 Truncate → 守卫 L1：表名匹配确认 → 行数清零（表保留）',
      (tester) async {
        if (!mysqlE2EGatewayReady) return;

        await pumpSidebar(tester);
        await rightClickTable(
          tester,
          connectionLabel: _prodLabel,
          table: _truncTable,
          menuLabel: l10n.truncate,
        );

        expect(
          find.byType(ProductionGuardDialog),
          findsOneWidget,
          reason: 'production 连接 Truncate 应分流到生产守卫弹窗',
        );
        expect(find.text(l10n.prodGuardTitleL1), findsOneWidget);
        expect(
          find.text('TRUNCATE TABLE `$testDbName`.`$_truncTable`'),
          findsOneWidget,
        );

        // 表名匹配 → 确认。
        await tester.enterText(guardNameField(), _truncTable);
        await tester.pump();
        await tester.tap(find.text(l10n.prodGuardConfirmDrop));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 断言真生效：行数清零 + 表结构保留。
        final cleared = await waitForDb(() async => await rowCount(_truncTable) == 0);
        expect(cleared, isTrue, reason: '守卫确认后 TRUNCATE 应清空种子行');
        expect(
          await tableExists(_truncTable),
          isTrue,
          reason: 'TRUNCATE 只清数据，表结构应保留',
        );
      },
    );

    // ----------------------------------------------------------------------
    // UI35-E2E-003 · 编辑器无 WHERE DELETE（L2）
    // ----------------------------------------------------------------------
    testWidgets(
      'UI35-E2E-003 production 编辑器 DELETE FROM 无 WHERE → 守卫 L2：取消零执行 / 确认真删',
      (tester) async {
        if (!mysqlE2EGatewayReady) return;

        // 活动 tab 绑定 production 连接，载入无 WHERE DELETE。
        await appProvider.tab.openQueryTab(
          connectionId: prodServer.id,
          databaseName: testDbName,
        );
        appProvider.setActiveTab(0);
        appProvider.updateTabSql(0, 'DELETE FROM `$_delTable`');

        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(buildEditorApp());
        await tester.pumpAndSettle();

        // 第一次执行 → 守卫弹窗（L2，非 L1、非既有 DML 门）。
        await tester.tap(find.byIcon(LucideIcons.play));
        final shown = await waitUntil(
          tester,
          () => find.byType(ProductionGuardDialog).evaluate().isNotEmpty,
        );
        expect(shown, isTrue, reason: 'production 无 WHERE DELETE 应弹生产守卫');
        expect(find.text(l10n.prodGuardTitleL2), findsOneWidget);
        expect(find.text(l10n.prodGuardTitleL1), findsNothing);

        // 取消 → 零执行（重查行数不变）。
        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(
          find.byType(ProductionGuardDialog),
          findsNothing,
          reason: '守卫弹窗应关闭',
        );
        expect(
          await rowCount(_delTable),
          5,
          reason: '守卫取消 → 零执行，种子行原样',
        );

        // 再次执行 → 确认（L2 免输入）→ 全删（真生效）。
        await tester.tap(find.byIcon(LucideIcons.play));
        final shownAgain = await waitUntil(
          tester,
          () => find.byType(ProductionGuardDialog).evaluate().isNotEmpty,
        );
        expect(shownAgain, isTrue, reason: '再次执行应再次弹守卫');
        await tester.tap(find.text(l10n.prodGuardConfirmDrop));
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final deleted = await waitForDb(() async => await rowCount(_delTable) == 0);
        expect(deleted, isTrue, reason: '守卫确认后 DELETE 应全删（重查为准）');
      },
    );

    // ----------------------------------------------------------------------
    // UI35-E2E-004 · 非 production（testing）回归：既有门不变
    // ----------------------------------------------------------------------
    testWidgets(
      'UI35-E2E-004 testing 连接同 DROP 动作 → 既有 type-to-confirm 门（守卫不出现）→ 真删',
      (tester) async {
        if (!mysqlE2EGatewayReady) return;

        await pumpSidebar(tester);
        await rightClickTable(
          tester,
          connectionLabel: _testLabel,
          table: _nonProdTable,
          menuLabel: l10n.dropTable,
        );

        // 守卫不出现；既有 DropTableConfirmDialog（T018 门）出现。
        expect(
          find.byType(ProductionGuardDialog),
          findsNothing,
          reason: '非 production 连接不得触发生产守卫',
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(l10n.dropTable),
          ),
          findsOneWidget,
          reason: 'testing 连接走既有 type-to-confirm 门（标题 l10n.dropTable）',
        );

        // 沿金标准路径走完旧门：输入表名 + Delete → 真删。
        await tester.enterText(find.byType(TextField), _nonProdTable);
        await tester.pump();
        await tapDialogButton(tester, 'Delete');

        final gone =
            await waitForDb(() async => !await tableExists(_nonProdTable));
        expect(gone, isTrue, reason: '既有门确认后 DROP 应真生效（行为回归）');
      },
    );
  });
}

// =============================================================================
// Minimal SidebarTree harness（金标准 _SidebarTestHarness 同款镜像）。
// =============================================================================
class _GuardSidebarHarness extends StatefulWidget {
  final AppProvider provider;

  const _GuardSidebarHarness({required this.provider});

  @override
  State<_GuardSidebarHarness> createState() => _GuardSidebarHarnessState();
}

class _GuardSidebarHarnessState extends State<_GuardSidebarHarness> {
  Set<String> _expandedItems = {};
  Set<String> _expandedDatabases = {};
  Set<String> _expandedTables = {};
  Set<String> _loadingDatabases = {};
  final Map<String, DbTable> _loadedTableSchemas = {};
  final Map<String, List<ForeignKey>> _loadedTableForeignKeys = {};
  final Set<String> _loadingTableSchemas = {};

  void _toggleExpand(String key) {
    setState(() {
      _expandedItems = _expandedItems.contains(key)
          ? _expandedItems.where((e) => e != key).toSet()
          : {..._expandedItems, key};
    });
  }

  void _toggleDatabase(String key) {
    setState(() {
      _expandedDatabases = _expandedDatabases.contains(key)
          ? _expandedDatabases.where((e) => e != key).toSet()
          : {..._expandedDatabases, key};
    });
  }

  void _toggleTable(String key) {
    final willExpand = !_expandedTables.contains(key);
    setState(() {
      _expandedTables = _expandedTables.contains(key)
          ? _expandedTables.where((e) => e != key).toSet()
          : {..._expandedTables, key};
    });
    if (willExpand) _loadTableSchema(key);
  }

  Future<void> _loadTableSchema(String tableKey) async {
    if (_loadingTableSchemas.contains(tableKey) ||
        _loadedTableSchemas.containsKey(tableKey)) {
      return;
    }
    final parts = tableKey.split(':');
    if (parts.length < 3) return;
    final connectionId = parts[0];
    final databaseName = parts[1];
    final tableName = parts.sublist(2).join(':');

    setState(() => _loadingTableSchemas.add(tableKey));
    try {
      final provider = widget.provider;
      final dbType = provider.dbService.getDatabaseType(connectionId);
      final columns = await provider.dbService.getTableColumns(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      final indexes = await provider.dbService.getTableIndexes(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      List<ForeignKey>? foreignKeys;
      if (dbType?.supportsForeignKeys ?? false) {
        foreignKeys = await provider.dbService.getForeignKeys(
          tableName,
          connectionId: connectionId,
          databaseName: databaseName,
        );
      }
      setState(() {
        _loadedTableSchemas[tableKey] = DbTable(
          name: tableName,
          columns: columns,
          indexes: indexes,
        );
        if (foreignKeys != null && foreignKeys.isNotEmpty) {
          _loadedTableForeignKeys[tableKey] = foreignKeys;
        }
        _loadingTableSchemas.remove(tableKey);
      });
    } catch (_) {
      setState(() => _loadingTableSchemas.remove(tableKey));
    }
  }

  Future<void> _loadDatabaseInfo(String connectionId, String databaseName) async {
    final key = '$connectionId:$databaseName';
    setState(() => _loadingDatabases = {..._loadingDatabases, key});
    try {
      await widget.provider.loadDatabaseInfo(connectionId, databaseName);
    } finally {
      setState(
        () => _loadingDatabases =
            _loadingDatabases.where((e) => e != key).toSet(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SidebarTree(
              expandedItems: _expandedItems,
              expandedDatabases: _expandedDatabases,
              expandedTables: _expandedTables,
              loadingDatabases: _loadingDatabases,
              loadedTableSchemas: _loadedTableSchemas,
              loadedTableForeignKeys: _loadedTableForeignKeys,
              loadingTableSchemas: _loadingTableSchemas,
              onToggleExpand: _toggleExpand,
              onToggleDatabase: _toggleDatabase,
              onToggleTable: _toggleTable,
              onLoadDatabaseInfo: _loadDatabaseInfo,
              onLoadTableSchema: _loadTableSchema,
              onShowConnectionManager: () {},
              onShowSettings: () {},
              onShowERDiagram: () {},
              onShowStoredProcedures: () {},
              onShowTriggers: () {},
              onCollapseAll: () {
                setState(() {
                  _expandedItems = {};
                  _expandedDatabases = {};
                  _expandedTables = {};
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
