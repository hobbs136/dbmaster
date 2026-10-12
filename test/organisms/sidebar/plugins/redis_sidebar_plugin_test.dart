// C17 · Redis 侧边栏插件单测：整树连接级（逻辑库列表 + 全局节点 + 空 db
// 显隐开关）+ 库节点展开四分类 + 能力分组（keyspace 新建键 / advanced 面板
// 项 / more 次要项归并——DBT-T6）+ 装配门控（core + 插件 × CapabilityTable）
// + 库级树恒空（拆法裁定：Redis 无库级分缝，C19 无需反转）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/redis_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

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

    testWidgets('capabilityGroups：三组装配（keyspace 1 + advanced 7 + more 4）',
      (tester) async {
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

      // DBT-T6：advanced 收缩（次要 4 项迁出）+ 新增 slowlog/expiring，
      // more 组归并次要项——组重排不增减项。
      expect(groups.map((g) => g.id), ['keyspace', 'advanced', 'more']);

      final keyspace = groups.first;
      expect(keyspace.items, hasLength(1));
      expect(keyspace.items.single.id, 'redis.key.new');
      expect(keyspace.items.single.capabilityId, isNull);

      final advanced = groups[1];
      expect(advanced.items, hasLength(7));
      expect(
        advanced.items.map((i) => i.id).toSet(),
        {
          'redis.cli',
          'redis.pubsub',
          'redis.memory',
          'redis.acl',
          'redis.config',
          'redis.slowlog',
          'redis.expiring',
        },
      );
      // port 门控键逐项核对（无键项 = redis 连接恒真的基础操作）
      final byId = {
        for (final item in advanced.items) item.id: item,
      };
      expect(byId['redis.cli']!.capabilityId, 'redis.cli');
      expect(byId['redis.pubsub']!.capabilityId, 'redis.pubsub');
      expect(byId['redis.config']!.capabilityId, 'redis.config');
      // DBT-T6 新增项位门控：既有位（capability_table redis.slowlog /
      // redis.keyspace.expiring，T0 前已在册）。
      expect(byId['redis.slowlog']!.capabilityId, 'redis.slowlog');
      expect(byId['redis.expiring']!.capabilityId, 'redis.keyspace.expiring');
      expect(byId['redis.memory']!.capabilityId, isNull);
      expect(byId['redis.acl']!.capabilityId, isNull);

      final more = groups.last;
      // 「更多」组含且仅含 4 项（项 id 不变，仅组归属调整）。
      expect(more.items, hasLength(4));
      expect(more.items.map((i) => i.id).toSet(), {
        'redis.lua',
        'redis.pipeline',
        'redis.transaction',
        'redis.keyspace.notifications',
      });
      for (final item in more.items) {
        // 位键不变（组重排仅移动归属）：lua 既有位键 redis.lua，其余无键。
        expect(item.capabilityId, item.id == 'redis.lua' ? 'redis.lua' : isNull,
            reason: '${item.id} 位键不应变化');
      }

      // 全部面板项带激活动作（真键位纪律）
      for (final group in groups) {
        for (final item in group.items) {
          expect(item.onActivate, isNotNull, reason: '${item.id} 缺激活回调');
        }
      }
    });

    testWidgets('capabilityGroups：项 id 不变（既有 10 + 新 2 = 12，无增减）',
      (tester) async {
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
      final allIds = [
        for (final g in groups) for (final i in g.items) i.id,
      ];
      expect(allIds.toSet(), {
        // 既有 10（组重排零增减）：
        'redis.key.new',
        'redis.cli',
        'redis.pubsub',
        'redis.lua',
        'redis.pipeline',
        'redis.transaction',
        'redis.memory',
        'redis.keyspace.notifications',
        'redis.acl',
        'redis.config',
        // DBT-T6 新 2：
        'redis.slowlog',
        'redis.expiring',
      });
      expect(allIds.length, 12, reason: '项 id 无重复');
    });

    testWidgets('装配门控：core 2 + 插件 12 = 14 项可见（CapabilityTable 实表）',
      (tester) async {
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

      final groups = assembleCapabilityMenu(
        context: captured!,
        type: DatabaseType.redis,
        port: const _TablePort(),
        plugins: const [CoreSidebarPlugin(), RedisSidebarPlugin()],
        l10n: AppLocalizations.of(captured!)!,
      );

      // 验收口径：可见项数 = 既有 12（core schema.diff/ai.assistant + 插件
      // 10）+ 新 2 = 14；proc/func/trigger 位不含 redis，core 其余项不可见。
      final visible = [
        for (final g in groups) ...g.items.map((i) => i.item.id),
      ];
      expect(visible, hasLength(14));
      expect(visible, containsAll(<String>['schema.diff', 'ai.assistant']));
      expect(
        visible,
        isNot(anyOf(<String>['proc.list', 'func.list', 'trigger.list'])),
      );
      expect(visible, contains('redis.slowlog'));
      expect(visible, contains('redis.expiring'));

      // 「更多」组装配后含且仅含 4 项；advanced 装配 = core 2 + 插件 7。
      final moreGroup = groups.singleWhere((g) => g.id == 'more');
      expect(moreGroup.items, hasLength(4));
      final advancedGroup = groups.singleWhere((g) => g.id == 'advanced');
      expect(advancedGroup.items, hasLength(9));
    });
  });
}

/// CapabilityTable 委托真值表（与生产装配同面）。
class _TablePort implements DbCapabilityPort {
  const _TablePort();

  @override
  bool hasCapability(DatabaseType type, String capabilityId) =>
      CapabilityTable.has(type, capabilityId);

  @override
  Set<String> capabilitiesOf(DatabaseType type) => CapabilityTable.of(type);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('单测 fake 仅实现能力位查询');
}
