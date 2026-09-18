// ============================================================================
// C18 · Doris/TDengine/ClickHouse 侧边栏插件真库 E2E（per-type SidebarPlugin
// 第三批）。
//
// 覆盖 C18 新运行时链路（Doris，真库参数经 DBMASTER_DORIS_* 提供）：
// 1. 全局树插件分缝：连接展开后 SidebarTree 经 _buildGlobalNodesForType
//    → DorisSidebarPlugin.buildGlobalTree（Server/Performance，无 Users）；
// 2. Server 节点展开出真 version_comment 叶子（Doris 版本）；
// 3. process.kill 能力项激活 → 进程管理对话框列出真进程
//    （SHOW PROCESSLIST 经 provider 缓存，MY 同款 loader）；
// 4. 库级树恒空契约：buildDatabaseTree 返回空 = 宿主回退共享泛 SQL 装配
//    （Doris Tables/Views/MV 分类走 sidebar_tree 通用路径，C19 收编）。
//
// TDengine：测试库服务在但凭据未知（常见默认密码均
// 401），真库链路待凭据补齐后补跑；树结构行为已由
// tdengine_sidebar_plugin_test 7 用例（seed 缓存）锚定。
//
// ClickHouse：gateway-backed 类型（adapter 全代理网关，无本地驱动），
// 真库链路已由 T29 第三批（2026-08-26）收口——见
// integration_test/clickhouse_integration_test.dart；C18 侧共享路径类型层
// 守卫见 test/organisms/sidebar/clickhouse_shared_path_test.dart。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/plugins/doris_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/capability/process_manager_dialog.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';

import 'config/doris_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

Widget _host(AppProvider provider, {Widget? child}) {
  return MultiProvider(
    providers: [
      // 树内连接状态点（server-platform M1 起）watch 团队服务器连接态；
      // 本 E2E 不涉团队服务器，供断开态实例即可。
      ChangeNotifierProvider<ServerConnectionProvider>(
        create: (_) => ServerConnectionProvider(),
      ),
      ChangeNotifierProvider<AppProvider>.value(value: provider),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      locale: const Locale('en'),
      home: Scaffold(body: child ?? const SizedBox.shrink()),
    ),
  );
}

/// 有状态树包装：expandedItems 归测试侧持有（tap → toggle → setState 重建）。
class _ExpandableTree extends StatefulWidget {
  const _ExpandableTree();

  @override
  State<_ExpandableTree> createState() => _ExpandableTreeState();
}

class _ExpandableTreeState extends State<_ExpandableTree> {
  Set<String> expandedItems = {};

  Set<String> _toggle(Set<String> set, String key) => set.contains(key)
      ? ({...set}..remove(key))
      : {...set, key};

  @override
  Widget build(BuildContext context) {
    return SidebarTree(
      expandedItems: expandedItems,
      expandedDatabases: const {},
      expandedTables: const {},
      loadingDatabases: const {},
      onToggleExpand: (key) {
        setState(() => expandedItems = _toggle(expandedItems, key));
      },
      onToggleDatabase: (_) {},
      onToggleTable: (_) {},
      onLoadDatabaseInfo: (_, _) async {},
      onShowConnectionManager: () {},
      onShowSettings: () {},
      onShowERDiagram: () {},
      onShowStoredProcedures: () {},
      onShowTriggers: () {},
    );
  }
}

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

  group('C18 Doris 侧边栏插件（真库）', () {
    late AppProvider provider;
    late DbServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = AppProvider();
      server = DbServer(
        id: 'c18-e2e-doris',
        type: DatabaseType.doris,
        name: 'C18 Doris',
        host: DorisTestConfig.host,
        port: DorisTestConfig.port,
        username: DorisTestConfig.username,
        password: DorisTestConfig.password,
      );
    });

    tearDown(() async {
      try {
        await provider.dbService.disconnect();
      } catch (_) {}
    });

    testWidgets('C18-DO-TREE：插件全局树渲染 Server/Performance（无 Users）', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await tester
          .runAsync(() => provider.connection.saveConnection(server));
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue, reason: '真库连接失败');

      await tester.pumpWidget(
        _host(provider, child: const _ExpandableTree()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final connFinder = find.ancestor(
        of: find.text('C18 Doris'),
        matching: find.byType(TreeItem),
      );
      expect(connFinder, findsOneWidget, reason: '连接卡片未渲染');
      await tester.tap(connFinder);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 插件全局节点两件（经 _buildGlobalNodesForType → 插件分缝）
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      // Users 有意省略（mysql.user 列不匹配 / GRANT 权限）
      expect(find.text('Users'), findsNothing);
    });

    testWidgets('C18-DO-SERVER：Server 展开出真 version_comment 叶子', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await tester
          .runAsync(() => provider.connection.saveConnection(server));
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue);

      await tester.pumpWidget(
        _host(provider, child: const _ExpandableTree()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final connFinder = find.ancestor(
        of: find.text('C18 Doris'),
        matching: find.byType(TreeItem),
      );
      await tester.tap(connFinder);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 展开 Server → loadServerStatus/loadGlobalVariables → 版本叶子
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Doris version_comment 含 "Doris" 字样（真 SHOW VARIABLES 通路）
      expect(find.textContaining('Doris'), findsAtLeastNWidgets(1));
    });

    testWidgets('C18-DO-KILL：process.kill 项激活 → 进程管理对话框列出真进程', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await tester
          .runAsync(() => provider.connection.saveConnection(server));
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue);

      SidebarCapabilityItem? killItem;
      await tester.pumpWidget(
        _host(
          provider,
          child: Builder(
            builder: (context) {
              for (final group
                  in const DorisSidebarPlugin().capabilityGroups(context)) {
                for (final item in group.items) {
                  if (item.id == 'process.kill') killItem = item;
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(killItem, isNotNull, reason: 'doris 插件应提供 process.kill 项');

      await tester.runAsync(() async { killItem!.onActivate!(); });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byType(ProcessManagerDialog), findsOneWidget);
      // 自身会话至少在列（SHOW PROCESSLIST 直查，与 MySQL 同 loader 路径）
      expect(find.textContaining('['), findsAtLeastNWidgets(1));
    });

    testWidgets('C18-DO-DBTREE：库级树恒空 + 共享装配路径真加载', (tester) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await tester
          .runAsync(() => provider.connection.saveConnection(server));
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue);

      // 库列表真加载（连接卡数据面）
      final databases = await tester.runAsync(
        () => provider
            .refreshDatabases(connectionId: server.id)
            .then((_) => provider.getConnectionDatabases(server.id)),
      );
      expect(databases, isNotEmpty, reason: 'Doris 库列表为空');

      // 共享泛 SQL 装配的数据面：information_schema 恒在且可加载
      final db = await tester.runAsync(
        () async {
          await provider.loadDatabaseInfo(server.id, 'information_schema');
          return provider.getCachedDatabase(server.id, 'information_schema');
        },
      );
      expect(db, isNotNull, reason: 'information_schema 库信息加载失败');

      // 插件库级恒空契约（分缝回退共享 _buildDatabaseObjects，C19 收编）
      const plugin = DorisSidebarPlugin();
      List<Widget> pluginTree = const [];
      await tester.pumpWidget(
        _host(
          provider,
          child: Builder(
            builder: (context) {
              pluginTree = plugin.buildDatabaseTree(
                context,
                SidebarDatabaseTreeContext(
                  provider: context.read<AppProvider>(),
                  connectionId: server.id,
                  server: server,
                  databaseName: 'information_schema',
                  db: db!,
                  searchQuery: '',
                  expandedItems: const {},
                  onToggleExpand: (_) {},
                  expandedTables: const {},
                  onToggleTable: (_) {},
                  loadedTableSchemas: const {},
                  loadedTableForeignKeys: const {},
                  loadingTableSchemas: const {},
                  tableRowCounts: const {},
                  onShowTableMenu: (_, _, _) async {},
                  onInsertName: (_) {},
                ),
              );
              return ListView(children: pluginTree);
            },
          ),
        ),
      );
      await tester.pump();
      expect(pluginTree, isEmpty, reason: 'Doris 库级恒空 = 宿主回退共享装配');
    });
  });
}
