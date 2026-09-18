// C18 · Doris 侧边栏插件单测：全局树两节点（Server/Performance，无 Users
// ——有意省略）+ 能力分组（process.kill，与 core 'advanced' 组合并键）
// + 库级树恒空（分缝回退契约：Doris 走 sidebar_tree 通用装配至 C19）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/plugins/doris_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  group('DorisSidebarPlugin', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Future<void> pumpGlobal(
      WidgetTester tester, {
      Set<String> expandedItems = const {},
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: AppProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Builder(
              builder: (context) {
                final nodes = const DorisSidebarPlugin().buildGlobalTree(
                  context,
                  SidebarTreeContext(
                    provider: context.read<AppProvider>(),
                    connectionId: 'do_conn',
                    expandedItems: expandedItems,
                    onToggleExpand: (_) {},
                  ),
                );
                return ListView(children: nodes);
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('buildGlobalTree 渲染 Server/Performance 两节点（无 Users）', (
      tester,
    ) async {
      await pumpGlobal(tester);

      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Performance'), findsOneWidget);
      // Users 有意省略（Doris mysql.user 列不匹配 / GRANT 权限）
      expect(find.text('Users'), findsNothing);
    });

    testWidgets('buildGlobalTree 展开 Performance 渲染刷新间隔选择器（无崩溃）', (
      tester,
    ) async {
      await pumpGlobal(tester, expandedItems: const {'do_conn:performance'});

      expect(find.text('5s'), findsOneWidget);
      expect(find.text('10s'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
    });

    testWidgets('capabilityGroups：advanced 组含 process.kill（能力键=id）', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              final groups = const DorisSidebarPlugin().capabilityGroups(
                context,
              );
              expect(groups, hasLength(1));
              expect(groups.first.id, 'advanced');
              expect(groups.first.items, hasLength(1));
              final item = groups.first.items.first;
              expect(item.id, 'process.kill');
              expect(item.capabilityId, item.id);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('descriptor：类型限定 doris + databaseType 来源徽章', (tester) async {
      const plugin = DorisSidebarPlugin();
      expect(plugin.descriptor.id, 'doris-sidebar');
      expect(plugin.descriptor.supports(DatabaseType.doris), isTrue);
      expect(plugin.descriptor.supports(DatabaseType.mysql), isFalse);
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
                final tree = const DorisSidebarPlugin().buildDatabaseTree(
                  context,
                  SidebarDatabaseTreeContext(
                    provider: context.read<AppProvider>(),
                    connectionId: 'do_conn',
                    server: DbServer(
                      id: 'do_conn',
                      name: 'T',
                      type: DatabaseType.doris,
                      host: 'h',
                      port: 9030,
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
