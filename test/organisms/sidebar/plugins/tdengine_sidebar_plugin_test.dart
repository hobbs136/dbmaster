// C18 · TDengine 侧边栏插件单测：库级树（SuperTables 分类 → 超级表叶子
// → Columns/Tags 分组）+ 全局恒空（刻意省略 server 级节点）
// + capabilityGroups 恒空（连接级无真实独立入口，同 Mongo 裁定）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/tdengine_models.dart';
import 'package:dbmaster/organisms/sidebar/plugins/tdengine_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  group('TdengineSidebarPlugin', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    /// [superTables] 传 null 表示不 seed（模拟 loadSuperTables 从未调用、
    /// 缓存为 null 的现场）；默认 `const []` 会把缓存落成非 null 空表。
    AppProvider seededProvider({List<TdSuperTable>? superTables}) {
      final provider = AppProvider();
      provider.connection.addSavedServerForTest(
        DbServer(
          id: 'td_conn',
          name: 'TD',
          type: DatabaseType.tdengine,
          host: '127.0.0.1',
          port: 6041,
        ),
      );
      if (superTables != null) {
        provider.seedSuperTablesForTest('td_conn', 'testdb', superTables);
      }
      return provider;
    }

    TdSuperTable meters() => TdSuperTable(
          name: 'meters',
          columns: [
            TdColumn(name: 'ts', type: 'TIMESTAMP', isPrimaryKey: true),
            TdColumn(name: 'current', type: 'FLOAT'),
          ],
          tags: [TdTag(name: 'location', type: 'BINARY')],
        );

    Future<void> pumpDatabaseTree(
      WidgetTester tester, {
      required AppProvider provider,
      String searchQuery = '',
      Set<String> expandedItems = const {},
      Set<String> expandedTables = const {},
      void Function(String key)? onToggleExpand,
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
                  final nodes = const TdengineSidebarPlugin().buildDatabaseTree(
                    context,
                    SidebarDatabaseTreeContext(
                      provider: context.read<AppProvider>(),
                      connectionId: 'td_conn',
                      server: DbServer(
                        id: 'td_conn',
                        name: 'TD',
                        type: DatabaseType.tdengine,
                        host: '127.0.0.1',
                        port: 6041,
                      ),
                      databaseName: 'testdb',
                      db: Database(name: 'testdb'),
                      searchQuery: searchQuery,
                      expandedItems: expandedItems,
                      onToggleExpand: onToggleExpand ?? (_) {},
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

    testWidgets('descriptor：类型限定 tdengine + databaseType 来源徽章', (tester) async {
      const plugin = TdengineSidebarPlugin();
      expect(plugin.descriptor.id, 'tdengine-sidebar');
      expect(plugin.descriptor.supports(DatabaseType.tdengine), isTrue);
      expect(plugin.descriptor.supports(DatabaseType.doris), isFalse);
      expect(plugin.descriptor.source, PluginSource.databaseType);
    });

    testWidgets('capabilityGroups 恒空（连接级无真实独立入口，同 Mongo 裁定）', (tester) async {
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
      expect(
        const TdengineSidebarPlugin().capabilityGroups(captured!),
        isEmpty,
      );
    });

    testWidgets('buildGlobalTree 恒空（刻意省略 server 级节点）', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: seededProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) {
                final tree = const TdengineSidebarPlugin().buildGlobalTree(
                  context,
                  SidebarTreeContext(
                    provider: context.read<AppProvider>(),
                    connectionId: 'td_conn',
                    expandedItems: const {},
                    onToggleExpand: (_) {},
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

    testWidgets('buildDatabaseTree：SuperTables 头恒渲染（badge=超表数）', (tester) async {
      await pumpDatabaseTree(
        tester,
        provider: seededProvider(superTables: [meters()]),
      );

      expect(find.text('SuperTables'), findsOneWidget);
      expect(find.text('1'), findsOneWidget, reason: '超表数徽章');
      // 未展开分类 → 不渲染超级表叶子
      expect(find.text('meters'), findsNothing);
    });

    testWidgets('展开 SuperTables → 超级表叶子（badge "N cols, M tags"）', (tester) async {
      await pumpDatabaseTree(
        tester,
        provider: seededProvider(superTables: [meters()]),
        expandedItems: {'td_conn:testdb:super_tables'},
      );

      expect(find.text('meters'), findsOneWidget);
      expect(find.text('2 cols, 1 tags'), findsOneWidget);
    });

    testWidgets('展开超级表 → Columns/Tags 分组 + 列（PK 徽章）与标签叶子', (tester) async {
      await pumpDatabaseTree(
        tester,
        provider: seededProvider(superTables: [meters()]),
        expandedItems: {'td_conn:testdb:super_tables'},
        expandedTables: {'td_conn:testdb:meters'},
      );

      expect(find.text('Columns (2)'), findsOneWidget);
      expect(find.text('Tags (1)'), findsOneWidget);
      expect(find.text('ts  TIMESTAMP [PK]'), findsOneWidget);
      expect(find.text('current  FLOAT'), findsOneWidget);
      expect(find.text('location  BINARY'), findsOneWidget);
    });

    testWidgets('搜索过滤：超级表名命中才渲染', (tester) async {
      await pumpDatabaseTree(
        tester,
        provider: seededProvider(superTables: [meters()]),
        expandedItems: {'td_conn:testdb:super_tables'},
        searchQuery: 'meters',
      );

      expect(find.text('meters'), findsOneWidget);

      await pumpDatabaseTree(
        tester,
        provider: seededProvider(superTables: [meters()]),
        expandedItems: {'td_conn:testdb:super_tables'},
        searchQuery: 'weather',
      );
      expect(find.text('meters'), findsNothing);
    });

    // ── 回归：「展开即重查」自愈 ──────────────────────────────────────
    // 现场（2026-09-08 用户反馈「超级表节点无法展开」）：库缓存由绕过
    // wrapper 的路径填充时，SuperTables 缓存恒 null——分类头展开后子树
    // 空，且点击只切展开态不加载，永远无法恢复。

    testWidgets('缓存 null + 展开态 → 渲染分类头但子树空（症状现场）', (tester) async {
      // 不 seed：模拟 loadSuperTables 从未被调用
      final bare = seededProvider();
      await pumpDatabaseTree(
        tester,
        provider: bare,
        expandedItems: {'td_conn:testdb:super_tables'},
      );

      expect(find.text('SuperTables'), findsOneWidget);
      expect(bare.getSuperTables('td_conn', 'testdb'), isNull);
    });

    testWidgets('点击展开 SuperTables（缓存 null）→ 触发 loadSuperTables 自愈', (tester) async {
      final bare = seededProvider();
      expect(bare.getSuperTables('td_conn', 'testdb'), isNull);

      final toggled = <String>[];
      await pumpDatabaseTree(
        tester,
        provider: bare,
        onToggleExpand: toggled.add,
      );

      await tester.tap(find.text('SuperTables'));
      await tester.pumpAndSettle();

      expect(toggled, ['td_conn:testdb:super_tables']);
      // 无真连接时 adapter 为 null → getSuperTables 返回 [] 落缓存：
      // null → 非 null 即证明加载链路被触发
      expect(bare.getSuperTables('td_conn', 'testdb'), isNotNull);
      expect(bare.getSuperTables('td_conn', 'testdb'), isEmpty);
    });

    testWidgets('点击折叠 SuperTables → 不触发加载（缓存保持 null）', (tester) async {
      final bare = seededProvider();
      final toggled = <String>[];
      await pumpDatabaseTree(
        tester,
        provider: bare,
        expandedItems: {'td_conn:testdb:super_tables'},
        onToggleExpand: toggled.add,
      );

      await tester.tap(find.text('SuperTables'));
      await tester.pumpAndSettle();

      expect(toggled, ['td_conn:testdb:super_tables']);
      expect(bare.getSuperTables('td_conn', 'testdb'), isNull);
    });
  });
}
