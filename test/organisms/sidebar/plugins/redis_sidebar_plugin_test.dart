// C17 · Redis 侧边栏插件单测：整树连接级（逻辑库列表 + 全局节点 + 空 db
// 显隐开关）+ 库节点展开四分类 + 能力分组（keyspace 新建键 / advanced
// 9 面板项）+ 库级树恒空（拆法裁定：Redis 无库级分缝，C19 无需反转）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/plugins/redis_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  group('RedisSidebarPlugin', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    AppProvider seededProvider({
      List<String> databases = const ['db0', 'db1'],
      List<String> nonEmpty = const ['db0'],
    }) {
      final provider = AppProvider();
      provider.connection.addSavedServerForTest(
        DbServer(
          id: 'rd_conn',
          name: 'RD',
          type: DatabaseType.redis,
          host: '127.0.0.1',
          port: 6379,
        ),
      );
      provider.connection.setConnectionDatabasesForTest(
        'rd_conn',
        databases,
        nonEmpty,
      );
      return provider;
    }

    Future<void> pumpTree(
      WidgetTester tester, {
      required AppProvider provider,
      List<String> databases = const ['db0', 'db1'],
      Set<String> expandedItems = const {},
      Set<String> expandedDatabases = const {},
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final nodes = const RedisSidebarPlugin().buildGlobalTree(
                    context,
                    SidebarTreeContext(
                      provider: context.read<AppProvider>(),
                      connectionId: 'rd_conn',
                      expandedItems: expandedItems,
                      onToggleExpand: (_) {},
                      expandedDatabases: expandedDatabases,
                      onToggleDatabase: (_) {},
                      databases: databases,
                    ),
                  );
                  return ListView(children: nodes);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('descriptor：redis 专属 + databaseType 来源', (tester) async {
      final d = const RedisSidebarPlugin().descriptor;
      expect(d.id, 'redis-sidebar');
      expect(d.supportedTypes, {DatabaseType.redis});
      expect(d.source, PluginSource.databaseType);
    });

    testWidgets('buildGlobalTree 整树：库节点 + 全局节点一次渲染', (tester) async {
      await pumpTree(tester, provider: seededProvider());

      // 逻辑库节点（来自 context.databases 载荷）
      expect(find.text('db0'), findsOneWidget);
      expect(find.text('db1'), findsOneWidget);
      // 全局节点（硬编码英文标签，与旧 builder 逐字保持）
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Replication'), findsOneWidget);
      expect(find.text('Memory'), findsOneWidget);
      expect(find.text('Stats'), findsOneWidget);
      expect(find.text('Clients'), findsOneWidget);
      expect(find.text('Config'), findsOneWidget);
      expect(find.text('Slow Log'), findsOneWidget);
      expect(find.text('Workbench'), findsOneWidget);
      expect(find.text('Pipeline'), findsOneWidget);
      expect(find.text('Pub/Sub'), findsOneWidget);
    });

    testWidgets('库总数 ≤16：无空库显隐开关（c04 §7 哨兵语义）', (tester) async {
      await pumpTree(tester, provider: seededProvider());
      expect(find.textContaining('Show empty'), findsNothing);
    });

    testWidgets('库总数 >16：空库显隐开关渲染', (tester) async {
      final dbs = List.generate(17, (i) => 'db$i');
      await pumpTree(
        tester,
        provider: seededProvider(databases: dbs, nonEmpty: ['db0']),
        databases: ['db0'],
      );
      expect(find.text('Show empty (1 / 17)'), findsOneWidget);
    });

    testWidgets('库节点展开：Keys/Namespaces/Expiring Soon/DB Info 四分类', (
      tester,
    ) async {
      await pumpTree(
        tester,
        provider: seededProvider(),
        expandedDatabases: {'rd_conn:db0'},
      );

      expect(find.text('Keys'), findsOneWidget);
      expect(find.text('Namespaces'), findsOneWidget);
      expect(find.text('Expiring Soon'), findsOneWidget);
      expect(find.text('DB Info'), findsOneWidget);
    });

    testWidgets('Keys 分类展开：无缓存 → loading 叶子', (tester) async {
      await pumpTree(
        tester,
        provider: seededProvider(),
        expandedDatabases: {'rd_conn:db0'},
        expandedItems: {'rd_conn:db0:keys'},
      );
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('buildDatabaseTree 恒空（无库级分缝契约）', (tester) async {
      final provider = seededProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final nodes = const RedisSidebarPlugin().buildDatabaseTree(
                    context,
                    SidebarDatabaseTreeContext(
                      provider: context.read<AppProvider>(),
                      connectionId: 'rd_conn',
                      server: DbServer(
                        id: 'rd_conn',
                        name: 'RD',
                        type: DatabaseType.redis,
                        host: '127.0.0.1',
                        port: 6379,
                      ),
                      databaseName: 'db0',
                      db: Database(name: 'db0'),
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
                  expect(nodes, isEmpty);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
    });

    testWidgets('capabilityGroups：keyspace 组新建键 + advanced 组 9 面板项', (
      tester,
    ) async {
      BuildContext? captured;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      final groups = const RedisSidebarPlugin().capabilityGroups(captured!);

      expect(groups.map((g) => g.id), ['keyspace', 'advanced']);

      final keyspace = groups.first;
      expect(keyspace.items, hasLength(1));
      expect(keyspace.items.single.id, 'redis.key.new');
      expect(keyspace.items.single.capabilityId, isNull);

      final advanced = groups.last;
      expect(advanced.items, hasLength(9));
      // port 门控键逐项核对（无键项 = redis 连接恒真的基础操作）
      final byId = {
        for (final item in advanced.items) item.id: item,
      };
      expect(byId['redis.cli']!.capabilityId, 'redis.cli');
      expect(byId['redis.pubsub']!.capabilityId, 'redis.pubsub');
      expect(byId['redis.lua']!.capabilityId, 'redis.lua');
      expect(byId['redis.config']!.capabilityId, 'redis.config');
      expect(byId['redis.pipeline']!.capabilityId, isNull);
      expect(byId['redis.transaction']!.capabilityId, isNull);
      expect(byId['redis.memory']!.capabilityId, isNull);
      expect(byId['redis.keyspace.notifications']!.capabilityId, isNull);
      expect(byId['redis.acl']!.capabilityId, isNull);
      // 全部面板项带激活动作（真键位纪律）
      for (final item in [...keyspace.items, ...advanced.items]) {
        expect(item.onActivate, isNotNull, reason: '${item.id} 缺激活回调');
      }
    });
  });
}
