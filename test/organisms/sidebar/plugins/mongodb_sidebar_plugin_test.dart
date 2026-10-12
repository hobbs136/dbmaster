// C17 · MongoDB 侧边栏插件单测：两级树（全局 Server/Replication/Sharding +
// 库级 Collections/Views/GridFS）+ 集合展开 Indexes 节点 + GridFS
// files+chunks 对识别。
// DBT-T7 增补：capabilityGroups 首批 5 项位映射锁定 + 装配可见项数
//（core 2 + 插件 5 = 7）+ 5 个面板项 onActivate 打开断言（私有面板经
// 公共激活路径驱动；真数据交互由 mongodb_capability_panel_e2e_test.dart
// 连 WSL 真库覆盖）。
// DBT-T10 增补（串行链 T7→T10）：+mongo.currentOp 项（位映射/装配计数
// 7→8/激活打开断言）；T7 锁定 5 项顺序不变（currentOp 追加于尾部），
// 真库链路由 mongodb_currentop_killop_e2e_test.dart 覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mongodb_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ports/capability_table.dart';
import 'package:dbmaster/services/ports/db_capability_port.dart';

/// 真值表 fake：委托 CapabilityTable（装配计数 × 真值表面）。
class _TablePort implements DbCapabilityPort {
  @override
  bool hasCapability(DatabaseType type, String capabilityId) =>
      CapabilityTable.has(type, capabilityId);

  @override
  Set<String> capabilitiesOf(DatabaseType type) => CapabilityTable.of(type);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('测试 fake 仅实现能力位查询');
}

void main() {
  group('MongodbSidebarPlugin', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    AppProvider seededProvider() {
      final provider = AppProvider();
      provider.connection.addSavedServerForTest(
        DbServer(
          id: 'mg_conn',
          name: 'MG',
          type: DatabaseType.mongodb,
          host: '127.0.0.1',
          port: 27017,
        ),
      );
      return provider;
    }

    Database sampleDb() => Database(
          name: 'testdb',
          tables: [
            DbTable(
              name: 'users',
              columns: const [],
              indexes: [
                DbIndex(name: '_id_', columns: const ['_id']),
                DbIndex(name: 'email_unique', columns: const ['email'], isUnique: true),
              ],
            ),
            DbTable(name: 'media.files', columns: const []),
            DbTable(name: 'media.chunks', columns: const []),
          ],
          views: const ['v_active_users'],
        );

    Future<void> pumpGlobalTree(WidgetTester tester, AppProvider provider) async {
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
                  final nodes = const MongodbSidebarPlugin().buildGlobalTree(
                    context,
                    SidebarTreeContext(
                      provider: context.read<AppProvider>(),
                      connectionId: 'mg_conn',
                      expandedItems: const {},
                      onToggleExpand: (_) {},
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

    Future<void> pumpDatabaseTree(
      WidgetTester tester, {
      required AppProvider provider,
      required Database db,
      String searchQuery = '',
      Set<String> expandedItems = const {},
      Set<String> expandedTables = const {},
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
                  final nodes = const MongodbSidebarPlugin().buildDatabaseTree(
                    context,
                    SidebarDatabaseTreeContext(
                      provider: context.read<AppProvider>(),
                      connectionId: 'mg_conn',
                      server: DbServer(
                        id: 'mg_conn',
                        name: 'MG',
                        type: DatabaseType.mongodb,
                        host: '127.0.0.1',
                        port: 27017,
                      ),
                      databaseName: 'testdb',
                      db: db,
                      searchQuery: searchQuery,
                      expandedItems: expandedItems,
                      onToggleExpand: (_) {},
                      expandedTables: expandedTables,
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
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('descriptor：mongodb 专属 + databaseType 来源', (tester) async {
      final d = const MongodbSidebarPlugin().descriptor;
      expect(d.id, 'mongodb-sidebar');
      expect(d.supportedTypes, {DatabaseType.mongodb});
      expect(d.source, PluginSource.databaseType);
    });

    testWidgets('capabilityGroups：advanced 组 6 项（T7 5 + T10 追加 1），位映射逐项锁定', (
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
      final groups = const MongodbSidebarPlugin().capabilityGroups(captured!);
      expect(groups, hasLength(1));
      expect(groups.first.id, 'advanced');
      // DBT-T7：id → capabilityId 映射逐项锁定；schemaView 纯导航无位恒显。
      //（mongo.validation/aggregate 复用既有位；indexAdvice/replication 为
      // T0 新登记位。）DBT-T10：mongo.currentOp 追加于尾部（T7 锁定 5 项
      // 顺序不回归），位为 T0 预登记的 mongo.currentOp。
      const expected = <String, String?>{
        'mongo.validation': 'mongo.validation',
        'mongo.aggregate': 'mongo.aggregate',
        'mongo.indexAdvice': 'mongo.indexAdvice',
        'mongo.replication': 'mongo.replication',
        'mongo.schemaView': null,
        'mongo.currentOp': 'mongo.currentOp',
      };
      final items = groups.first.items;
      expect(items.map((i) => i.id).toList(), expected.keys.toList());
      for (final item in items) {
        expect(item.capabilityId, expected[item.id], reason: item.id);
      }
      // 全部项有激活动作（纯展示项 = 装配缺口）。
      expect(items.every((i) => i.onActivate != null), isTrue);
    });

    test('DBT-T7/T10 项位全在 CapabilityTable 对 mongodb 取真（T0 预登记）', () {
      const caps = [
        'mongo.validation',
        'mongo.aggregate',
        'mongo.indexAdvice',
        'mongo.replication',
        'mongo.currentOp',
      ];
      for (final cap in caps) {
        expect(CapabilityTable.has(DatabaseType.mongodb, cap), isTrue,
            reason: cap);
      }
    });

    testWidgets('MongoDB 装配可见项数 = core 2 + 插件 6 = 8（CapabilityTable 门控后）',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              final groups = assembleCapabilityMenu(
                context: context,
                type: DatabaseType.mongodb,
                port: _TablePort(),
                plugins: const [CoreSidebarPlugin(), MongodbSidebarPlugin()],
                l10n: AppLocalizations.of(context)!,
              );
              final ids = [
                for (final g in groups)
                  ...g.items.map((i) => i.item.id),
              ];
              expect(ids, hasLength(8));
              expect(
                ids,
                containsAll(const [
                  // core 2
                  'schema.diff',
                  'ai.assistant',
                  // 插件 5（T7）
                  'mongo.validation',
                  'mongo.aggregate',
                  'mongo.indexAdvice',
                  'mongo.replication',
                  'mongo.schemaView',
                  // 插件 1（DBT-T10）
                  'mongo.currentOp',
                ]),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('buildGlobalTree：Server/Replication/Sharding 三节点恒渲染', (
      tester,
    ) async {
      await pumpGlobalTree(tester, seededProvider());

      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Replication'), findsOneWidget);
      expect(find.text('Sharding'), findsOneWidget);
    });

    testWidgets('buildDatabaseTree：Collections 徽章 + Views + GridFS 识别', (
      tester,
    ) async {
      await pumpDatabaseTree(tester, provider: seededProvider(), db: sampleDb());

      expect(find.text('Collections'), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: '集合数徽章');
      expect(find.text('Views'), findsOneWidget);
      // media.files + media.chunks 配对 → media bucket（非两个独立集合节点）
      expect(find.text('GridFS Buckets'), findsOneWidget);
    });

    testWidgets('Views 空时不渲染 Views 节点', (tester) async {
      final db = Database(name: 'testdb', tables: [DbTable(name: 'users', columns: const [])]);
      await pumpDatabaseTree(tester, provider: seededProvider(), db: db);

      expect(find.text('Collections'), findsOneWidget);
      expect(find.text('Views'), findsNothing);
      expect(find.text('GridFS Buckets'), findsNothing);
    });

    testWidgets('展开 Collections → 集合项；展开集合 → Indexes 计数与索引项', (
      tester,
    ) async {
      await pumpDatabaseTree(
        tester,
        provider: seededProvider(),
        db: sampleDb(),
        expandedItems: {'testdb_collections'},
        expandedTables: {'mg_conn:testdb:users'},
      );

      expect(find.text('users'), findsOneWidget);
      expect(find.text('Indexes (2)'), findsOneWidget);
      expect(find.text('email_unique'), findsOneWidget);
    });

    testWidgets('搜索过滤：集合名命中才渲染', (tester) async {
      await pumpDatabaseTree(
        tester,
        provider: seededProvider(),
        db: sampleDb(),
        searchQuery: 'users',
        expandedItems: {'testdb_collections'},
      );

      expect(find.text('users'), findsOneWidget);
      expect(find.text('media.files'), findsNothing);
    });
  });

  // ── DBT-T7 面板项激活（私有面板经公共 onActivate 路径驱动）──────────
  group('MongodbSidebarPlugin 面板项激活（DBT-T7）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    /// 能力面板驱动壳：装配（core + mongo 插件 × CapabilityTable 门控）后
    /// 把每个可见项渲染为 ListTile，onTap = item.onActivate（与真实菜单
    /// 同一激活闭包）。currentServer 经 @visibleForTesting 钩子注入 = 激活
    /// 锚定可达（resolveCapabilityMenuServer currentServer 分支）。
    Future<AppProvider> pumpHarness(WidgetTester tester) async {
      final provider = AppProvider();
      final server = DbServer(
        id: 'mg_conn',
        name: 'MG',
        type: DatabaseType.mongodb,
        host: '127.0.0.1',
        port: 27017,
      );
      provider.connection.addSavedServerForTest(server);
      provider.connection.setCurrentServerForTest(server);
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
                  final groups = assembleCapabilityMenu(
                    context: context,
                    type: DatabaseType.mongodb,
                    port: _TablePort(),
                    plugins: const [
                      CoreSidebarPlugin(),
                      MongodbSidebarPlugin(),
                    ],
                    l10n: AppLocalizations.of(context)!,
                  );
                  return ListView(
                    children: [
                      for (final group in groups)
                        for (final item in group.items)
                          ListTile(
                            key: Key('${group.id}/${item.item.id}'),
                            title: Text('${group.id}/${item.item.id}'),
                            onTap: item.item.onActivate,
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return provider;
    }

    Future<void> activateItem(WidgetTester tester, String itemId) async {
      await tester.tap(find.byKey(Key('advanced/$itemId')));
      await tester.pump();
      await tester.pumpAndSettle();
    }

    testWidgets('mongo.validation → 打开验证规则浏览器', (tester) async {
      await pumpHarness(tester);
      await activateItem(tester, 'mongo.validation');

      expect(find.text('Validation Rules'), findsWidgets);
      // 库下拉（未连接 provider 下 facade 返回空列表，下拉 hint 仍在）
      expect(find.text('Database'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('mongo.aggregate → 打开聚合 shell 入口；未选库 Confirm 禁用', (
      tester,
    ) async {
      await pumpHarness(tester);
      await activateItem(tester, 'mongo.aggregate');

      expect(find.text('Aggregation Shell'), findsOneWidget);
      final confirm = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Confirm'),
      );
      expect(confirm.onPressed, isNull, reason: '未选库/集合时禁用');
    });

    testWidgets('mongo.indexAdvice → 打开索引建议面板', (tester) async {
      await pumpHarness(tester);
      await activateItem(tester, 'mongo.indexAdvice');

      expect(find.text('Index Advice'), findsOneWidget);
      expect(find.text('Index Suggestion'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('mongo.replication → 打开副本集/分片面板（未连接 = 空态文案）', (
      tester,
    ) async {
      await pumpHarness(tester);
      await activateItem(tester, 'mongo.replication');

      expect(find.text('Replication'), findsWidgets);
      // 未连接 facade 不落缓存 → null 状态按非副本集/非分片呈现
      expect(find.text('Not a replica set'), findsOneWidget);
      expect(find.text('Not a sharded cluster'), findsOneWidget);
    });

    testWidgets('mongo.schemaView → 打开 Schema 视图（库/集合选择 + 内容承载）', (
      tester,
    ) async {
      await pumpHarness(tester);
      await activateItem(tester, 'mongo.schemaView');

      expect(find.text('Schema View'), findsOneWidget);
      expect(find.text('Database'), findsOneWidget);
      expect(find.text('Collections'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('mongo.currentOp → 打开进程面板（DBT-T10；未连接 = 失败态不崩溃）', (
      tester,
    ) async {
      await pumpHarness(tester);
      await activateItem(tester, 'mongo.currentOp');

      // 面板标题渲染；未连接下 loader 抛 StateError → 失败态（错误文案），
      // 真库链路由 mongodb_currentop_killop_e2e_test.dart 覆盖。
      expect(find.text('Current Operations'), findsOneWidget);
      expect(find.textContaining('MongoDB'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });
  });
}
