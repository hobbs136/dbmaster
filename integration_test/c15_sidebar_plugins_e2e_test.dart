// ============================================================================
// C15 · MySQL/PG 侧边栏插件真库 E2E（首批 per-type SidebarPlugin）
//
// 覆盖 C15 新运行时链路：
// 1. 插件全局树：连接后 SidebarTree 渲染 MySQL 的 Server/Performance/Users
//    （树分缝 _buildGlobalNodesForType → MysqlSidebarPlugin.buildGlobalTree）；
// 2. 能力项激活：capabilityGroups 的 process.kill / engine.status 项经
//    onActivate 打开进程管理对话框（真 SHOW PROCESSLIST / pg_stat_activity）
//    与 Engine Status 对话框（真 SHOW ENGINE INNODB STATUS）；
// 3. PG 库级树：插件接管 _buildDatabaseObjectsOrSchemaAware（schema 层 +
//    对象分类渲染，连接公共 postgres 库的既有 schema）。
//
// 真库：MySQLTestConfig / PostgreSQLTestConfig（参数经 DBMASTER_* 提供）。
// 全部只读断言（不 kill 真进程——终止语义由树内既有用例与单测覆盖）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mysql_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/postgresql_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/capability/process_manager_dialog.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';

import 'config/mysql_test_config.dart';
import 'config/postgresql_test_config.dart';
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

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady &&
        (!MySQLTestConfig.available || !PostgreSQLTestConfig.available)) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* / DBMASTER_PG_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('C15 MySQL 侧边栏插件（真库）', () {
    late AppProvider provider;
    late DbServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = AppProvider();
      server = DbServer(
        id: 'c15-e2e-mysql',
        type: DatabaseType.mysql,
        name: 'C15 MySQL',
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
    });

    tearDown(() async {
      try {
        await provider.dbService.disconnect();
      } catch (_) {}
    });

    testWidgets('C15-MY-TREE：插件全局树渲染 Server/Performance/Users', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      await tester
          .runAsync(() => provider.connection.saveConnection(server));
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue, reason: '真库连接失败');

      final treeKey = GlobalKey<_ExpandableTreeState>();
      await tester.pumpWidget(
        _host(
          provider,
          child: _ExpandableTree(key: treeKey),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 展开连接节点（全局节点在连接卡片的展开区内）
      final connFinder = find.ancestor(
        of: find.text('C15 MySQL'),
        matching: find.byType(TreeItem),
      );
      expect(connFinder, findsOneWidget, reason: '连接卡片未渲染');
      await tester.tap(connFinder);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);
    });

    testWidgets('C15-MY-KILL：process.kill 项激活 → 进程管理对话框列出真进程', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
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
                  in const MysqlSidebarPlugin().capabilityGroups(context)) {
                for (final item in group.items) {
                  if (item.id == 'process.kill') killItem = item;
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(killItem, isNotNull, reason: 'mysql 插件应提供 process.kill 项');

      await tester.runAsync(() async { killItem!.onActivate!(); });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byType(ProcessManagerDialog), findsOneWidget);
      // 自身会话至少在列（SHOW PROCESSLIST 直查）
      expect(find.textContaining('['), findsAtLeastNWidgets(1));
    });

    testWidgets('C15-MY-ENGINE：engine.status 项激活 → Engine Status 对话框打开', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue);

      SidebarCapabilityItem? engineItem;
      await tester.pumpWidget(
        _host(
          provider,
          child: Builder(
            builder: (context) {
              for (final group
                  in const MysqlSidebarPlugin().capabilityGroups(context)) {
                for (final item in group.items) {
                  if (item.id == 'engine.status') engineItem = item;
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(engineItem, isNotNull);

      await tester.runAsync(() async { engineItem!.onActivate!(); });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.text('Engine Status'), findsAtLeastNWidgets(1));
    });
  });

  group('C15 PG 侧边栏插件（真库）', () {
    late AppProvider provider;
    late DbServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = AppProvider();
      server = DbServer(
        id: 'c15-e2e-pg',
        type: DatabaseType.postgresql,
        name: 'C15 PG',
        host: PostgreSQLTestConfig.host,
        port: PostgreSQLTestConfig.port,
        username: PostgreSQLTestConfig.username,
        password: PostgreSQLTestConfig.password,
        database: PostgreSQLTestConfig.database,
      );
    });

    tearDown(() async {
      try {
        await provider.dbService.disconnect();
      } catch (_) {}
    });

    testWidgets('C15-PG-TREE：插件库级树渲染 schema 层与对象分类', (
      tester,
    ) async {
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue, reason: '真库连接失败');

      // postgres 公共库自带 public schema；直接装配库级树（分缝同路径：
      // SidebarTree → _buildPluginDatabaseTree → PostgresqlSidebarPlugin）
      const plugin = PostgresqlSidebarPlugin();
      await tester.pumpWidget(
        _host(
          provider,
          child: Builder(
            builder: (context) {
              final p = context.read<AppProvider>();
              final nodes = plugin.buildDatabaseTree(
                context,
                SidebarDatabaseTreeContext(
                  provider: p,
                  connectionId: server.id,
                  server: server,
                  databaseName: 'postgres',
                  db: Database(name: 'postgres', schemas: [
                    DbSchema(name: 'public', tables: [DbTable(name: 'pg_tree_probe')])
                  ]),
                  searchQuery: '',
                  expandedItems: const {'c15-e2e-pg:postgres:schema:public'},
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
              return ListView(children: nodes);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('public'), findsOneWidget);
      expect(find.text('Tables (1)'), findsOneWidget);
      expect(find.text('pg_tree_probe'), findsNothing, reason: '分类默认收起');
    });

    testWidgets('C15-PG-KILL：process.kill 项激活 → 对话框列出 pg_stat_activity 会话', (
      tester,
    ) async {
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
                  in const PostgresqlSidebarPlugin().capabilityGroups(context)) {
                for (final item in group.items) {
                  if (item.id == 'process.kill') killItem = item;
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(killItem, isNotNull, reason: 'PG 插件应提供 process.kill 项');

      await tester.runAsync(() async { killItem!.onActivate!(); });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byType(ProcessManagerDialog), findsOneWidget);
      // 非超管至少可见自身会话；超管可见全部（loader 可见性语义同树内节点）
      final rows = find.textContaining('[');
      if (rows.evaluate().isEmpty) {
        final texts = <String>[];
        for (final w in find.byType(Text).evaluate()) {
          final t2 = (w.widget as Text).data ?? '';
          if (t2.isNotEmpty) texts.add(t2);
        }
        fail('PG 会话行为空；对话框文本：$texts');
      }
      expect(rows, findsAtLeastNWidgets(1));
    });
  });
}


/// 有状态树包装：expandedItems 归测试侧持有（tap → toggle → setState 重建）。
class _ExpandableTree extends StatefulWidget {
  const _ExpandableTree({super.key});

  @override
  State<_ExpandableTree> createState() => _ExpandableTreeState();
}

class _ExpandableTreeState extends State<_ExpandableTree> {
  Set<String> expandedItems = {};

  @override
  Widget build(BuildContext context) {
    return SidebarTree(
      expandedItems: expandedItems,
      expandedDatabases: const {},
      expandedTables: const {},
      loadingDatabases: const {},
      onToggleExpand: (key) {
        setState(() {
          expandedItems = expandedItems.contains(key)
              ? ({...expandedItems}..remove(key))
              : {...expandedItems, key};
        });
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
