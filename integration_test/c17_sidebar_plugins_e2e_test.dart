// ============================================================================
// C17 · MongoDB/Redis 侧边栏插件真库 E2E（per-type SidebarPlugin 第二批）
//
// 覆盖 C17 新运行时链路：
// 1. Redis 整树连接级：连接后 SidebarTree 经 _buildGlobalNodesForType 分缝
//    → RedisSidebarPlugin.buildGlobalTree（逻辑库列表 + 全局节点）；
//    Server 节点展开出真 INFO 数据（版本叶子）；
// 2. Redis 能力项激活：advanced 组 redis.config 项经 onActivate 打开
//    Edit Config 对话框（真 CONFIG GET/SET 通路入口）；
// 3. Mongo 两级树：全局 Server/Replication/Sharding 经插件分缝渲染 +
//    Server 展开出真 serverStatus 版本叶子；
// 4. Mongo 库级树：插件 buildDatabaseTree 消费 SidebarDatabaseTreeContext
//    （连接 admin 库既有集合）；
// 5. Mongo 验证规则数据通路：provider.getMongoCollectionOptions 真
//    listCollections（C17 新增，验证规则查看器数据源）。
//
// 真库：RedisTestConfig / MongoDBTestConfig（参数经 DBMASTER_* 提供）。
// 全部只读断言（不写键/不建集合/不 CONFIG SET）。
// ============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mongodb_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/redis_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/redis_dialogs/redis_edit_config_dialog.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';

import 'config/mongodb_test_config.dart';
import 'config/redis_test_config.dart';

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

/// 有状态树包装：expandedItems / expandedDatabases 归测试侧持有
/// （tap → toggle → setState 重建），Redis 库节点与分类节点双轨展开。
class _ExpandableTree extends StatefulWidget {
  const _ExpandableTree();

  @override
  State<_ExpandableTree> createState() => _ExpandableTreeState();
}

class _ExpandableTreeState extends State<_ExpandableTree> {
  Set<String> expandedItems = {};
  Set<String> expandedDatabases = {};

  Set<String> _toggle(Set<String> set, String key) => set.contains(key)
      ? ({...set}..remove(key))
      : {...set, key};

  @override
  Widget build(BuildContext context) {
    return SidebarTree(
      expandedItems: expandedItems,
      expandedDatabases: expandedDatabases,
      expandedTables: const {},
      loadingDatabases: const {},
      onToggleExpand: (key) {
        setState(() => expandedItems = _toggle(expandedItems, key));
      },
      onToggleDatabase: (key) {
        setState(() => expandedDatabases = _toggle(expandedDatabases, key));
      },
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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('C17 Redis 侧边栏插件（真库）', () {
    late AppProvider provider;
    late DbServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = AppProvider();
      server = DbServer(
        id: 'c17-e2e-redis',
        type: DatabaseType.redis,
        name: 'C17 Redis',
        host: RedisTestConfig.host,
        port: RedisTestConfig.port,
        password: RedisTestConfig.password,
        database: RedisTestConfig.database,
      );
    });

    tearDown(() async {
      try {
        await provider.dbService.disconnect();
      } catch (_) {}
    });

    testWidgets('C17-RD-TREE：插件整树渲染逻辑库 + 全局节点', (tester) async {
      if (!RedisTestConfig.available) {
        markTestSkipped(
            'DBMASTER_REDIS_* 未通过 --dart-define 提供（开源剥离默认凭据）');
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

      // 展开连接卡片（整树在连接卡展开区）
      final connFinder = find.ancestor(
        of: find.text('C17 Redis'),
        matching: find.byType(TreeItem),
      );
      expect(connFinder, findsOneWidget, reason: '连接卡片未渲染');
      await tester.tap(connFinder);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 全局节点（插件 _buildGlobalNodes 逐项）
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Replication'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
      expect(find.text('Slow Log'), findsOneWidget);
      expect(find.text('Workbench'), findsOneWidget);
      expect(find.text('Pub/Sub'), findsOneWidget);
      // 逻辑库节点至少一个（db0-15 中有数据的）
      expect(find.textContaining(RegExp(r'^db\d+$')), findsAtLeastNWidgets(1));
    });

    testWidgets('C17-RD-SERVER：Server 节点展开出真 INFO 版本叶子', (
      tester,
    ) async {
      if (!RedisTestConfig.available) {
        markTestSkipped(
            'DBMASTER_REDIS_* 未通过 --dart-define 提供（开源剥离默认凭据）');
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
        of: find.text('C17 Redis'),
        matching: find.byType(TreeItem),
      );
      await tester.tap(connFinder);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 展开 Server 全局节点 → loadRedisServerInfo → 版本/模式叶子
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.textContaining('Redis '), findsAtLeastNWidgets(1));
      expect(find.textContaining('Mode'), findsAtLeastNWidgets(1));
    });

    testWidgets('C17-RD-CAP：redis.config 项激活 → Edit Config 对话框打开', (
      tester,
    ) async {
      if (!RedisTestConfig.available) {
        markTestSkipped(
            'DBMASTER_REDIS_* 未通过 --dart-define 提供（开源剥离默认凭据）');
        return;
      }
      await tester
          .runAsync(() => provider.connection.saveConnection(server));
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue);

      SidebarCapabilityItem? configItem;
      await tester.pumpWidget(
        _host(
          provider,
          child: Builder(
            builder: (context) {
              for (final group
                  in const RedisSidebarPlugin().capabilityGroups(context)) {
                for (final item in group.items) {
                  if (item.id == 'redis.config') configItem = item;
                }
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(configItem, isNotNull, reason: 'redis 插件应提供 redis.config 项');

      await tester.runAsync(() async { configItem!.onActivate!(); });
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.byType(RedisEditConfigDialog), findsOneWidget);
      expect(find.text('Edit Config'), findsAtLeastNWidgets(1));
    });
  });

  group('C17 MongoDB 侧边栏插件（真库）', () {
    late AppProvider provider;
    late DbServer server;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = AppProvider();
      server = DbServer(
        id: 'c17-e2e-mongo',
        type: DatabaseType.mongodb,
        name: 'C17 Mongo',
        host: MongoDBTestConfig.host,
        port: MongoDBTestConfig.port,
        username: MongoDBTestConfig.username,
        password: MongoDBTestConfig.password,
        database: MongoDBTestConfig.authDatabase,
      );
    });

    tearDown(() async {
      try {
        await provider.dbService.disconnect();
      } catch (_) {}
    });

    testWidgets('C17-MG-GLOBAL：插件全局树渲染 + Server 展开真版本', (
      tester,
    ) async {
      if (!MongoDBTestConfig.available) {
        markTestSkipped(
            'DBMASTER_MONGO_* 未通过 --dart-define 提供（开源剥离默认凭据）');
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
        of: find.text('C17 Mongo'),
        matching: find.byType(TreeItem),
      );
      expect(connFinder, findsOneWidget, reason: '连接卡片未渲染');
      await tester.tap(connFinder);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // 插件全局节点三件（经 _buildGlobalNodesForType → 插件分缝）
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Replication'), findsOneWidget);
      expect(find.text('Sharding'), findsOneWidget);

      // 展开 Server → loadMongoDBServerInfo → 版本叶子（真 serverStatus）
      await tester.tap(find.text('Server'));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.textContaining('MongoDB '), findsAtLeastNWidgets(1));
    });

    testWidgets('C17-MG-DBTREE：插件库级树渲染 Collections（admin 真集合）', (
      tester,
    ) async {
      if (!MongoDBTestConfig.available) {
        markTestSkipped(
            'DBMASTER_MONGO_* 未通过 --dart-define 提供（开源剥离默认凭据）');
        return;
      }
      await tester
          .runAsync(() => provider.connection.saveConnection(server));
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue);

      // 真加载 admin 库集合列表（分缝同路径：宿主 → 插件 buildDatabaseTree）
      final db = await tester.runAsync(
        () async {
          await provider.loadDatabaseInfo(server.id, 'admin');
          return provider.getCachedDatabase(server.id, 'admin');
        },
      );
      expect(db, isNotNull, reason: 'admin 库信息加载失败');

      const plugin = MongodbSidebarPlugin();
      await tester.pumpWidget(
        _host(
          provider,
          child: Builder(
            builder: (context) {
              final nodes = plugin.buildDatabaseTree(
                context,
                SidebarDatabaseTreeContext(
                  provider: context.read<AppProvider>(),
                  connectionId: server.id,
                  server: server,
                  databaseName: 'admin',
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
              return ListView(children: nodes);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Collections'), findsOneWidget);
      if (db!.tables.isNotEmpty) {
        expect(find.text('${db.tables.length}'), findsOneWidget,
            reason: '集合数徽章');
      }
    });

    testWidgets('C17-MG-VALIDATE：getMongoCollectionOptions 真链路（listCollections）', (
      tester,
    ) async {
      if (!MongoDBTestConfig.available) {
        markTestSkipped(
            'DBMASTER_MONGO_* 未通过 --dart-define 提供（开源剥离默认凭据）');
        return;
      }
      await tester
          .runAsync(() => provider.connection.saveConnection(server));
      final connected = await tester
          .runAsync(() => provider.connection.connectToServer(server));
      expect(connected, isTrue);

      // admin.system.version 是 MongoDB 内建集合，恒存在
      final options = await tester.runAsync(
        () => provider.getMongoCollectionOptions(
          server.id,
          'admin',
          'system.version',
        ),
      );

      expect(options, isNotNull, reason: 'listCollections 未返回目标集合');
      expect(options!['name'], 'system.version');
      // options 结构契约（验证规则查看器消费）
      expect(options['options'], isA<Map>());
      expect(options['type'], isNotNull);
    });

    testWidgets(
      'C17-MG-BROWSE：集合右键 Browse Documents → 数据浏览 tab（隐 editor/FilterBar + 自动执行 → nosqlDocument）',
      (tester) async {
        const probeCollection = 'c17_browse_probe';
        if (!MongoDBTestConfig.available) {
          markTestSkipped(
              'DBMASTER_MONGO_* 未通过 --dart-define 提供（开源剥离默认凭据）');
          return;
        }
        await tester
            .runAsync(() => provider.connection.saveConnection(server));
        final connected = await tester
            .runAsync(() => provider.connection.connectToServer(server));
        expect(connected, isTrue);

        // admin 的集合全是 system.*（getTables 过滤）——insert 自建探针集合。
        final inserted = await tester.runAsync(
          () => provider.insertMongoDocument(
            server.id,
            'admin',
            probeCollection,
            {'name': 'alice', 'age': 30},
          ),
        );
        expect(inserted, isTrue, reason: '探针文档插入失败');

        final db = await tester.runAsync(
          () async {
            await provider.loadDatabaseInfo(server.id, 'admin');
            return provider.getCachedDatabase(server.id, 'admin');
          },
        );
        expect(db, isNotNull, reason: 'admin 库信息加载失败');
        expect(db!.tables.any((t) => t.name == probeCollection), isTrue,
            reason: '探针集合应出现在集合列表');

        const plugin = MongodbSidebarPlugin();
        await tester.pumpWidget(
          _host(
            provider,
            child: Builder(
              builder: (context) {
                final nodes = plugin.buildDatabaseTree(
                  context,
                  SidebarDatabaseTreeContext(
                    provider: context.read<AppProvider>(),
                    connectionId: server.id,
                    server: server,
                    databaseName: 'admin',
                    db: db,
                    searchQuery: '',
                    // 展开 Collections 分类（key = '<db>_collections'）渲染集合行
                    expandedItems: const {'admin_collections'},
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

        // 集合行右键 → Browse Documents（走查反馈修复面：应直接看数据，
        // 不再塞未执行的 find 进查询编辑器）
        final rowFinder = find.ancestor(
          of: find.text(probeCollection),
          matching: find.byType(TreeItem),
        );
        expect(rowFinder, findsOneWidget, reason: '探针集合行未渲染');
        await tester.tap(rowFinder, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Browse Documents'));
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 1) 新 tab：预填 find 查询（方言感知 getDefaultBrowseQuery）
        final tab = provider.tab.activeTab;
        expect(tab, isNotNull, reason: '浏览应打开新 tab');
        expect(tab!.connectionId, server.id);
        expect(tab.databaseName, 'admin');
        expect(tab.sql, 'db.$probeCollection.find().limit(100)');

        // 2) 数据浏览布局：editor 隐、FilterBar 隐（Mongo 非 SQL 系——
        //    FilterBar 的 Apply 是 SQL WHERE 拼装，对 Mongo 会生成非法查询）
        final layout = provider.tab.panelLayoutFor(tab.id);
        expect(layout.editorVisible, isFalse, reason: '浏览模式 editor 应隐藏');
        expect(layout.filterBarVisible, isFalse,
            reason: 'Mongo 浏览不应显示 SQL FilterBar');

        // 3) 自动执行链（真库）：integration binding 下 runAsync 之外启动的
        //    真实 IO future 不推进（unawaited 的 _runBrowseAutoExecute 挂起，
        //    与 SQL 浏览路径同款应用内行为）——此处 runAsync 内驱动同一条
        //    executeCurrentQueryAndRecord 调用验证结果与形态。
        final results = await tester.runAsync(
          () => provider.executeCurrentQueryAndRecord(overrideSql: tab.sql),
        );
        expect(results, isNotEmpty, reason: '浏览 find 执行无结果');
        final first = results!.first;
        expect(first.success, isTrue,
            reason: 'find 执行失败: ${first.errorMessage}');
        expect(first.dataShape?.name, 'nosqlDocument');
        expect(first.data, isNotEmpty);
        expect(first.data!.first['name'], 'alice');

        // 清理探针集合（当前活跃连接即本测试的 mongo 连接）
        await tester.runAsync(
          () => provider.dropTable('admin', probeCollection),
        );
      },
    );
  });
}
