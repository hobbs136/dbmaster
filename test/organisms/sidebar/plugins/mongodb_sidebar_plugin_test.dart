// C17 · MongoDB 侧边栏插件单测：两级树（全局 Server/Replication/Sharding +
// 库级 Collections/Views/GridFS）+ 集合展开 Indexes 节点 + GridFS
// files+chunks 对识别 + capabilityGroups 恒空（连接级无真实独立入口）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/sidebar/plugins/mongodb_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

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

    testWidgets('capabilityGroups 恒空（连接级无真实独立入口）', (tester) async {
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
        const MongodbSidebarPlugin().capabilityGroups(captured!),
        isEmpty,
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
}
