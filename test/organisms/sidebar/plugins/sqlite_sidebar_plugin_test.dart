// C16 · SQLite 侧边栏插件单测：整树连接级（单库扁平 / ATTACH 多库 header）
// + 搜索过滤（SidebarTreeContext.searchQuery 消费）+ 能力分组
// （sqlite.attach / sqlite.pragma，与 core 'advanced' 组合并键）
// + 库级树恒空（拆法裁定：SQLite 无库级分缝，C19 删旧路径无需反转）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/plugins/sqlite_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  group('SqliteSidebarPlugin', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    AppProvider seededProvider({
      List<String> databases = const ['main'],
      Map<String, Database> cached = const {},
    }) {
      final provider = AppProvider();
      provider.connection.addSavedServerForTest(
        DbServer(
          id: 'lt_conn',
          name: 'LT',
          type: DatabaseType.sqlite,
          host: 'C:/tmp/test.db',
          port: 0,
        ),
      );
      provider.connection.setConnectionDatabasesForTest(
        'lt_conn',
        databases,
        databases,
      );
      for (final e in cached.entries) {
        provider.connection.setCachedDatabaseForTest(
          'lt_conn',
          e.key,
          e.value,
        );
      }
      return provider;
    }

    Database sampleDb() => Database(
          name: 'main',
          tables: [
            DbTable(
              name: 'users',
              columns: [
                DbColumn(
                  name: 'id',
                  type: 'INTEGER',
                  isPrimaryKey: true,
                ),
              ],
            ),
            DbTable(name: 'orders', columns: const []),
          ],
          views: const ['v_users'],
          triggers: [
            DbTrigger(
              name: 'trg_guard',
              event: 'INSERT',
              table: 'users',
              timing: 'BEFORE',
            ),
          ],
        );

    Future<void> pumpTree(
      WidgetTester tester, {
      required AppProvider provider,
      Set<String> expandedItems = const {},
      Set<String> expandedTables = const {},
      String searchQuery = '',
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            // Scaffold 提供 Material 祖先（表节点收藏星标 InkWell 需要）
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final nodes = const SqliteSidebarPlugin().buildGlobalTree(
                    context,
                    SidebarTreeContext(
                      provider: context.read<AppProvider>(),
                      connectionId: 'lt_conn',
                      expandedItems: expandedItems,
                      onToggleExpand: (_) {},
                      searchQuery: searchQuery,
                      expandedTables: expandedTables,
                      onToggleTable: (_) {},
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

    testWidgets('buildGlobalTree 单库扁平：分类头直出、无 main header', (
      tester,
    ) async {
      await pumpTree(
        tester,
        provider: seededProvider(cached: {'main': sampleDb()}),
      );

      expect(find.text('Tables'), findsOneWidget);
      expect(find.text('Views'), findsOneWidget);
      expect(find.text('Indexes'), findsOneWidget);
      expect(find.text('Triggers'), findsOneWidget);
      expect(find.text('Database Info'), findsOneWidget);
      // 扁平化：main 不渲染独立 header 节点
      expect(find.text('main'), findsNothing);
      // 分类默认收起：表叶子不可见
      expect(find.text('users'), findsNothing);
    });

    testWidgets('buildGlobalTree 展开表分类 + 表级展开渲染列徽章', (tester) async {
      await pumpTree(
        tester,
        provider: seededProvider(cached: {'main': sampleDb()}),
        expandedItems: {'lt_conn:main:tables'},
        expandedTables: {'lt_conn:main:users'},
      );

      // 收藏置顶 + 字典序：users / orders 均可见
      expect(find.text('users'), findsOneWidget);
      expect(find.text('orders'), findsOneWidget);
      // 表级展开 → 列叶子 + PK 徽章
      expect(find.text('id'), findsOneWidget);
      expect(find.text('PK'), findsOneWidget);
    });

    testWidgets('buildGlobalTree ATTACH 多库：每库 header 节点（含 main）', (
      tester,
    ) async {
      await pumpTree(
        tester,
        provider: seededProvider(
          databases: ['main', 'extra'],
          cached: {
            'main': sampleDb(),
            'extra': Database(name: 'extra', tables: const []),
          },
        ),
      );

      // 多库场景：main 也作为 header 节点出现；收起态只渲染 header
      expect(find.text('main'), findsOneWidget);
      expect(find.text('extra'), findsOneWidget);
      expect(find.text('Tables'), findsNothing);
    });

    testWidgets('buildGlobalTree ATTACH 多库展开附加库子树', (tester) async {
      await pumpTree(
        tester,
        provider: seededProvider(
          databases: ['main', 'extra'],
          cached: {
            'main': sampleDb(),
            'extra': Database(
              name: 'extra',
              tables: [DbTable(name: 'ext_table', columns: const [])],
            ),
          },
        ),
        expandedItems: {'lt_conn:db:extra', 'lt_conn:extra:tables'},
      );

      expect(find.text('Tables'), findsOneWidget);
      expect(find.text('ext_table'), findsOneWidget);
      // 附加库不显示 Database Info（PRAGMA 信息仅 main 展示）
      expect(find.text('Database Info'), findsNothing);
    });

    testWidgets('buildGlobalTree searchQuery 过滤表叶子', (tester) async {
      await pumpTree(
        tester,
        provider: seededProvider(cached: {'main': sampleDb()}),
        expandedItems: {'lt_conn:main:tables'},
        searchQuery: 'order',
      );

      expect(find.text('orders'), findsOneWidget);
      expect(find.text('users'), findsNothing);
    });

    testWidgets('capabilityGroups：advanced 组含 sqlite.attach + sqlite.pragma', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              final groups =
                  const SqliteSidebarPlugin().capabilityGroups(context);
              expect(groups, hasLength(1));
              expect(groups.first.id, 'advanced');
              final ids = groups.first.items.map((i) => i.id).toSet();
              expect(ids, contains('sqlite.attach'));
              expect(ids, contains('sqlite.pragma'));
              // 能力键 = id（port 门控键，SQLite 专有位）
              for (final item in groups.first.items) {
                expect(item.capabilityId, item.id);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('descriptor：类型限定 sqlite + databaseType 来源徽章', () {
      const plugin = SqliteSidebarPlugin();
      expect(plugin.descriptor.id, 'sqlite-sidebar');
      expect(plugin.descriptor.supports(DatabaseType.sqlite), isTrue);
      expect(plugin.descriptor.supports(DatabaseType.mysql), isFalse);
      expect(plugin.descriptor.source, PluginSource.databaseType);
    });

    testWidgets('buildDatabaseTree 恒空（SQLite 整树连接级，无库级分缝）', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: AppProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) {
                final tree = const SqliteSidebarPlugin().buildDatabaseTree(
                  context,
                  SidebarDatabaseTreeContext(
                    provider: context.read<AppProvider>(),
                    connectionId: 'lt_conn',
                    server: DbServer(
                      id: 'lt_conn',
                      name: 'T',
                      type: DatabaseType.sqlite,
                      host: 'h',
                      port: 0,
                    ),
                    databaseName: 'main',
                    db: Database(name: 'main'),
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
                expect(tree, isEmpty);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });
  });
}
