// C19 · 泛 SQL 库级共享树单测（SB-PLG-055~062）。
//
// 锚定 core 插件库级树（buildGenericSqlDatabaseTree）的分缝反转契约：
// MySQL/Doris/CH 等 per-type 恒空类型由 core 兜底渲染六分类；SS/非 SQL
// 排除（回退宿主 legacy 分支/专属插件）；菜单路由经 context 回调透传且
// 携带分类语义（offerCreateTable/categoryType/isMaterializedView/
// isFunction——C19 扩参，防旧装配丢参回归）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/capability/generic_sql_database_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DbServer server;
  late List<(Offset, bool, String?)> categoryMenuCalls;
  late List<(String, Offset, bool)> viewMenuCalls;
  late List<(String, Offset, bool)> procedureMenuCalls;

  Database dbOf({
    List<DbTable>? tables,
    List<String>? views,
    List<String>? mvs,
    List<String>? procedures,
    List<String>? functions,
    List<DbTrigger>? triggers,
    List<String>? events,
  }) => Database(
    name: 'd',
    tables: tables ?? [],
    views: views ?? [],
    procedures: procedures ?? [],
    functions: functions ?? [],
    materializedViews: mvs ?? [],
    triggers: triggers ?? [],
    events: events ?? [],
  );

  Future<List<TreeItem>> pumpTree(
    WidgetTester tester, {
    required DatabaseType type,
    required Database db,
    String searchQuery = '',
    Set<String> expandedItems = const {},
  }) async {
    server = DbServer(id: 'c1', name: 'S', type: type, host: 'h', port: 1);
    categoryMenuCalls = [];
    viewMenuCalls = [];
    procedureMenuCalls = [];
    final appProvider = AppProvider();
    appProvider.connection.addSavedServerForTest(server);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: appProvider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              final nodes = buildGenericSqlDatabaseTree(
                context,
                SidebarDatabaseTreeContext(
                  provider: context.read<AppProvider>(),
                  connectionId: server.id,
                  server: server,
                  databaseName: 'd',
                  db: db,
                  searchQuery: searchQuery,
                  expandedItems: expandedItems,
                  onToggleExpand: (_) {},
                  expandedTables: const {},
                  onToggleTable: (_) {},
                  loadedTableSchemas: const {},
                  loadedTableForeignKeys: const {},
                  loadingTableSchemas: const {},
                  tableRowCounts: const {},
                  onShowTableMenu: (_, _, _) async {},
                  onInsertName: (_) {},
                  onShowViewMenu: (name, pos, isMv) =>
                      viewMenuCalls.add((name, pos, isMv)),
                  onShowProcedureMenu: (name, pos, isFn) =>
                      procedureMenuCalls.add((name, pos, isFn)),
                  onShowCategoryMenu: (pos, offerCreateTable, categoryType) =>
                      categoryMenuCalls.add(
                        (pos, offerCreateTable, categoryType),
                      ),
                ),
              );
              return Scaffold(body: ListView(children: nodes));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester
        .widgetList<TreeItem>(find.byType(TreeItem))
        .toList(growable: false);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('C19 泛 SQL 共享树（core 插件库级兜底）', () {
    testWidgets('SB-PLG-055 MySQL 全五分类渲染（tables/views/procedures/triggers/events）', (
      tester,
    ) async {
      final items = await pumpTree(
        tester,
        type: DatabaseType.mysql,
        db: dbOf(
          tables: [DbTable(name: 'users')],
          views: ['v1'],
          procedures: ['do_thing'],
          triggers: [
            DbTrigger(name: 'trg', timing: 'BEFORE', event: 'INSERT', table: 'users'),
          ],
          events: ['ev_daily'],
        ),
        // 分类默认收起——显式展开五分类（原用搜索词强制展开，但搜索词
        // 须命中对象名，改为 expandedItems 更直白）
        expandedItems: {
          'c1:d:tables',
          'c1:d:views',
          'c1:d:procedures',
          'c1:d:triggers',
          'c1:d:events',
        },
      );
      final labels = items.map((t) => t.label ?? '').toList();
      expect(
        labels.any((l) => l.startsWith('Tables (1')),
        isTrue,
        reason: 'Tables 分类头应渲染',
      );
      expect(labels.any((l) => l.startsWith('Views (1')), isTrue);
      expect(labels.any((l) => l.startsWith('Stored Procedures (1')), isTrue);
      expect(labels.any((l) => l.startsWith('Triggers (1')), isTrue);
      expect(labels.any((l) => l.startsWith('Events (1')), isTrue);
      // 表叶子
      expect(labels, contains('users'));
      // 触发器叶子带 timing/event 后缀
      expect(labels.any((l) => l.contains('trg')), isTrue);
    });

    testWidgets('SB-PLG-056 Doris 渲染 MV 分类；triggers/events 能力位裁剪', (
      tester,
    ) async {
      final items = await pumpTree(
        tester,
        type: DatabaseType.doris,
        db: dbOf(
          views: ['v'],
          mvs: ['mv1'],
          // Doris 无 trigger/event 能力——即使数据误有也不渲染该分类
          triggers: [
            DbTrigger(name: 't', timing: 'AFTER', event: 'INSERT', table: 'x'),
          ],
          events: ['e'],
        ),
        expandedItems: {
          'c1:d:views',
          'c1:d:materialized_views',
        },
      );
      final labels = items.map((t) => t.label ?? '').toList();
      expect(labels.any((l) => l.startsWith('Materialized Views (1')), isTrue);
      expect(labels.any((l) => l.startsWith('Triggers')), isFalse);
      expect(labels.any((l) => l.startsWith('Events')), isFalse);
    });

    testWidgets('SB-PLG-057 ClickHouse 走共享树；procedures 能力位裁剪', (
      tester,
    ) async {
      final items = await pumpTree(
        tester,
        type: DatabaseType.clickhouse,
        db: dbOf(
          tables: [DbTable(name: 'ch_t')],
          // CH 无 proc 能力——即使数据误有也不渲染
          procedures: ['p'],
        ),
        expandedItems: {'c1:d:tables', 'c1:d:procedures'},
      );
      final labels = items.map((t) => t.label ?? '').toList();
      expect(labels, contains('ch_t'));
      expect(labels.any((l) => l.startsWith('Stored Procedures')), isFalse);
    });

    testWidgets('SB-PLG-058 SS 与非 SQL 类型返回空（回退宿主/专属插件）', (
      tester,
    ) async {
      expect(
        await pumpTree(
          tester,
          type: DatabaseType.sqlserver,
          db: dbOf(tables: [DbTable(name: 't')]),
          searchQuery: 'x',
        ),
        isEmpty,
        reason: 'SS 排除（schema-aware 树走宿主 legacy 分支，C20 迁插件）',
      );
      expect(
        await pumpTree(
          tester,
          type: DatabaseType.mongodb,
          db: dbOf(tables: [DbTable(name: 't')]),
          searchQuery: 'x',
        ),
        isEmpty,
        reason: '非 SQL 防御排除（Mongo 由 per-type 插件接管）',
      );
      expect(
        await pumpTree(
          tester,
          type: DatabaseType.redis,
          db: dbOf(),
          searchQuery: 'x',
        ),
        isEmpty,
      );
    });

    testWidgets('SB-PLG-059 搜索过滤：表名命中过滤其余分类', (tester) async {
      final items = await pumpTree(
        tester,
        type: DatabaseType.mysql,
        db: dbOf(
          tables: [DbTable(name: 'users'), DbTable(name: 'orders')],
          views: ['v_users'],
        ),
        searchQuery: 'users',
      );
      final labels = items.map((t) => t.label ?? '').toList();
      expect(labels, contains('users'));
      expect(labels, isNot(contains('orders')));
      expect(labels.any((l) => l.startsWith('Views (1)')), isTrue);
    });

    testWidgets('SB-PLG-060 分类头菜单路由携带分类语义（offerCreateTable/categoryType）', (
      tester,
    ) async {
      // MySQL：tables/views/procedures 三分类头（MySQL 无 MV 能力位）
      final myItems = await pumpTree(
        tester,
        type: DatabaseType.mysql,
        db: dbOf(
          tables: [DbTable(name: 't')],
          views: ['v'],
          procedures: ['p'],
          functions: ['f'],
        ),
        expandedItems: {
          'c1:d:tables',
          'c1:d:views',
          'c1:d:procedures',
        },
      );
      final myHeaders = myItems.where((t) => t.level == 3).toList();
      expect(myHeaders.length, 3, reason: 'tables/views/procedures 三分类头');
      for (final h in myHeaders) {
        h.onContextMenu!(Offset.zero);
      }
      // tables → (true, null)；views → (false,'view')；procedures → (false,null)
      expect(categoryMenuCalls, contains((Offset.zero, true, null)));
      expect(categoryMenuCalls, contains((Offset.zero, false, 'view')));
      expect(categoryMenuCalls, contains((Offset.zero, false, null)));

      // Doris：materialized_views 分类头 → (false,'materialized_view')
      final doItems = await pumpTree(
        tester,
        type: DatabaseType.doris,
        db: dbOf(mvs: ['mv']),
        expandedItems: {'c1:d:materialized_views'},
      );
      // Views 分类空列表也渲染（"(0)"，Create View 菜单可达设计）
      final doHeaders = doItems.where((t) => t.level == 3).toList();
      expect(doHeaders.length, 2, reason: 'Doris 空 Views(0) + MV 两分类头');
      for (final h in doHeaders) {
        h.onContextMenu!(Offset.zero);
      }
      expect(
        categoryMenuCalls,
        contains((Offset.zero, false, 'materialized_view')),
      );
    });

    testWidgets('SB-PLG-061 视图/MV 叶子菜单透传 isMaterializedView', (
      tester,
    ) async {
      final items = await pumpTree(
        tester,
        type: DatabaseType.doris,
        db: dbOf(views: ['v'], mvs: ['mv']),
        expandedItems: {'c1:d:views', 'c1:d:materialized_views'},
      );
      final leaves = items.where((t) => t.level == 4).toList();
      expect(leaves.map((t) => t.label), containsAll(['v', 'mv']));
      for (final leaf in leaves) {
        leaf.onContextMenu!(Offset.zero);
      }
      expect(
        viewMenuCalls,
        containsAll([
          ('v', Offset.zero, false),
          ('mv', Offset.zero, true),
        ]),
      );
    });

    testWidgets('SB-PLG-062 过程叶子菜单透传 isFunction（函数折入语义保持）', (
      tester,
    ) async {
      final items = await pumpTree(
        tester,
        type: DatabaseType.mysql,
        db: dbOf(procedures: ['do_thing', 'calc_x'], functions: ['calc_x']),
        expandedItems: {'c1:d:procedures'},
      );
      final leaves = items.where((t) => t.level == 4).toList();
      for (final leaf in leaves) {
        leaf.onContextMenu!(Offset.zero);
      }
      expect(
        procedureMenuCalls,
        containsAll([
          ('do_thing', Offset.zero, false),
          ('calc_x', Offset.zero, true),
        ]),
      );
    });
  });
}
