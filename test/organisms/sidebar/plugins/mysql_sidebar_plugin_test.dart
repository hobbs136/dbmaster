// C15 · MySQL 侧边栏插件单测：全局树三节点（Server/Performance/Users）
// + 能力分组（engine.status / process.kill，与 core 'advanced' 组合并键）
// + 库级树恒空（分缝回退契约：MySQL 走 sidebar_tree 通用装配至 C19）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mysql_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  group('MysqlSidebarPlugin', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpGlobal(WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: AppProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) {
                final provider = context.read<AppProvider>();
                final nodes = const MysqlSidebarPlugin().buildGlobalTree(
                  context,
                  SidebarTreeContext(
                    provider: provider,
                    connectionId: 'my_conn',
                    expandedItems: const {},
                    onToggleExpand: (_) {},
                  ),
                );
                return ListView(children: nodes);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('buildGlobalTree renders Server/Performance/Users 三节点', (
      tester,
    ) async {
      await pumpGlobal(tester);

      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);
    });

    testWidgets('buildGlobalTree 展开 Performance 触发进程列表按需加载（无崩溃）', (
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
                final provider = context.read<AppProvider>();
                final nodes = const MysqlSidebarPlugin().buildGlobalTree(
                  context,
                  SidebarTreeContext(
                    provider: provider,
                    connectionId: 'my_conn',
                    expandedItems: const {'my_conn:performance'},
                    onToggleExpand: (_) {},
                  ),
                );
                return ListView(children: nodes);
              },
            ),
          ),
        ),
      );
      // 进程未返回（未连接）→ loading 叶 + 刷新间隔选择器仍渲染
      await tester.pump();
      expect(find.text('5s'), findsOneWidget);
      expect(find.text('10s'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
    });

    testWidgets('capabilityGroups：advanced 组含 process.kill + engine.status', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              final groups = const MysqlSidebarPlugin().capabilityGroups(
                context,
              );
              expect(groups, hasLength(1));
              expect(groups.first.id, 'advanced');
              final ids = groups.first.items.map((i) => i.id).toSet();
              expect(ids, contains('process.kill'));
              expect(ids, contains('engine.status'));
              // 能力键 = id（port 门控键，含 MySQL 专有 engine.status）
              for (final item in groups.first.items) {
                expect(item.capabilityId, item.id);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('descriptor：类型限定 mysql + databaseType 来源徽章', () {
      const plugin = MysqlSidebarPlugin();
      expect(plugin.descriptor.id, 'mysql-sidebar');
      expect(plugin.descriptor.supports(DatabaseType.mysql), isTrue);
      expect(plugin.descriptor.supports(DatabaseType.postgresql), isFalse);
      expect(plugin.descriptor.source, PluginSource.databaseType);
    });

    testWidgets('buildDatabaseTree 恒空（分缝回退契约，C19 前走通用装配）', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: AppProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) {
                final tree = const MysqlSidebarPlugin().buildDatabaseTree(
                  context,
                  SidebarDatabaseTreeContext(
                    provider: context.read<AppProvider>(),
                    connectionId: 'my_conn',
                    server: DbServer(
                      id: 'my_conn',
                      name: 'T',
                      type: DatabaseType.mysql,
                      host: 'h',
                      port: 3306,
                    ),
                    databaseName: 'd',
                    db: Database(name: 'd'),
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
