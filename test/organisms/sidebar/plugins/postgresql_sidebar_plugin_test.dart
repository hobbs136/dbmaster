// C15 · PostgreSQL 侧边栏插件单测：库级 schema 树经 SidebarDatabaseTreeContext
// 装配（迁移前直测 PostgresqlTreeBuilder.buildDatabaseNode 的用例改写，
// 断言保持）；另覆盖全局树节点与能力分组。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/builders/tree_utils.dart';
import 'package:dbmaster/organisms/sidebar/plugins/postgresql_sidebar_plugin.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

DbServer _server() => DbServer(
      id: 'pg_conn',
      name: 'Test PG',
      type: DatabaseType.postgresql,
      host: 'localhost',
      port: 5432,
    );

SidebarDatabaseTreeContext _dbContext(
  AppProvider provider, {
  required Database database,
  Set<String> expandedItems = const {},
  Set<String> expandedTables = const {},
  String searchQuery = '',
  Map<String, DbTable> loadedTableSchemas = const {},
  Map<String, List<ForeignKey>> loadedTableForeignKeys = const {},
}) {
  return SidebarDatabaseTreeContext(
    provider: provider,
    connectionId: 'pg_conn',
    server: _server(),
    databaseName: 'test_db',
    db: database,
    searchQuery: searchQuery,
    expandedItems: expandedItems,
    onToggleExpand: (_) {},
    expandedTables: expandedTables,
    onToggleTable: (_) {},
    loadedTableSchemas: loadedTableSchemas,
    loadedTableForeignKeys: loadedTableForeignKeys,
    loadingTableSchemas: const {},
    tableRowCounts: const {},
    onShowTableMenu: (_, _, _) async {},
    onSelectNode: (_) {},
    onInsertName: (_) {},
  );
}

class _Harness extends StatelessWidget {
  final SidebarDatabaseTreeContext dbContext;

  const _Harness({required this.dbContext});

  @override
  Widget build(BuildContext context) {
    final nodes = const PostgresqlSidebarPlugin().buildDatabaseTree(
      context,
      dbContext,
    );
    return ListView(children: nodes);
  }
}

class _GlobalHarness extends StatelessWidget {
  const _GlobalHarness();

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AppProvider>();
    final nodes = const PostgresqlSidebarPlugin().buildGlobalTree(
      context,
      SidebarTreeContext(
        provider: provider,
        connectionId: 'pg_conn',
        expandedItems: const {},
        onToggleExpand: (_) {},
      ),
    );
    return ListView(children: nodes);
  }
}

void main() {
  group('PostgresqlSidebarPlugin', () {
    late Database testDb;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      testDb = Database(
        name: 'test_db',
        schemas: [
          DbSchema(
            name: 'public',
            tables: [
              DbTable(name: 'users'),
              DbTable(name: 'orders'),
            ],
            views: ['active_users'],
            materializedViews: ['mv_user_stats'],
            functions: ['fn_total'],
            procedures: ['sp_create_user'],
            sequences: ['users_id_seq'],
            triggers: [
              DbTrigger(
                name: 'trg_users_update',
                event: 'UPDATE',
                table: 'users',
                timing: 'BEFORE',
              ),
            ],
          ),
          DbSchema(
            name: 'analytics',
            tables: [DbTable(name: 'events')],
          ),
        ],
      );
    });

    Future<void> pumpDb(
      WidgetTester tester,
      SidebarDatabaseTreeContext dbContext,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: AppProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(body: _Harness(dbContext: dbContext)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('buildDatabaseTree renders schema nodes', (tester) async {
      final provider = AppProvider();
      await pumpDb(tester, _dbContext(provider, database: testDb));

      expect(find.text('public'), findsOneWidget);
      expect(find.text('analytics'), findsOneWidget);
    });

    testWidgets(
      'buildDatabaseTree expands schema and shows object categories',
      (tester) async {
        final provider = AppProvider();
        await pumpDb(
          tester,
          _dbContext(
            provider,
            database: testDb,
            expandedItems: const {'pg_conn:test_db:schema:public'},
          ),
        );

        expect(find.text('Tables (2)'), findsOneWidget);
        expect(find.text('Views (1)'), findsOneWidget);
        expect(find.text('Materialized Views (1)'), findsOneWidget);
        expect(find.text('Functions (1)'), findsOneWidget);
        expect(find.text('Stored Procedures (1)'), findsOneWidget);
        expect(find.text('Sequences (1)'), findsOneWidget);
        expect(find.text('Triggers (1)'), findsOneWidget);

        // Categories are collapsed; individual objects are not visible yet.
        expect(find.text('users'), findsNothing);
      },
    );

    testWidgets('buildDatabaseTree expands tables category and shows tables', (
      tester,
    ) async {
      final provider = AppProvider();
      await pumpDb(
        tester,
        _dbContext(
          provider,
          database: testDb,
          expandedItems: const {
            'pg_conn:test_db:schema:public',
            'pg_conn:test_db:schema:public:tables',
          },
        ),
      );

      expect(find.text('users'), findsOneWidget);
      expect(find.text('orders'), findsOneWidget);
    });

    testWidgets('展开表时渲染扁平交互式列叶子', (tester) async {
      final provider = AppProvider();
      await pumpDb(
        tester,
        _dbContext(
          provider,
          database: testDb,
          expandedItems: const {
            'pg_conn:test_db:schema:public',
            'pg_conn:test_db:schema:public:tables',
          },
          expandedTables: const {'pg_conn:test_db:public:users'},
          loadedTableSchemas: {
            'pg_conn:test_db:public:users': DbTable(
              name: 'public.users',
              columns: <DbColumn>[
                DbColumn(name: 'id', type: 'int4', isPrimaryKey: true),
                DbColumn(name: 'email', type: 'varchar'),
              ],
              indexes: <DbIndex>[DbIndex(name: 'users_email_idx', columns: <String>['email'])],
            ),
          },
          loadedTableForeignKeys: {
            'pg_conn:test_db:public:users': <ForeignKey>[
              ForeignKey(
                name: 'fk_orders_user',
                table: 'users',
                column: 'id',
                referencedTable: 'orders',
                referencedColumn: 'user_id',
              ),
            ],
          },
        ),
      );

      // 扁平列直接渲染（无 Columns 组头）
      expect(find.text('email'), findsOneWidget);
      expect(find.text('id'), findsOneWidget);
      // 索引分组头仍在
      expect(find.text('Indexes'), findsOneWidget);
      // 字段↔索引、索引↔外键 各一条分割线
      expect(find.byType(SchemaSectionDivider), findsNWidgets(2));
    });

    testWidgets('buildDatabaseTree filters by search query', (tester) async {
      final provider = AppProvider();
      await pumpDb(
        tester,
        _dbContext(provider, database: testDb, searchQuery: 'users'),
      );

      // Schema "public" contains matching table "users".
      expect(find.text('public'), findsOneWidget);
      // Schema "analytics" does not contain "users".
      expect(find.text('analytics'), findsNothing);
    });

    testWidgets('空 schema 库返回「无数据」叶子（恒非空 = 恒接管分缝）', (
      tester,
    ) async {
      final provider = AppProvider();
      await pumpDb(
        tester,
        _dbContext(provider, database: Database(name: 'test_db')),
      );

      expect(find.text('No Data'), findsOneWidget);
    });

    testWidgets('buildGlobalTree renders Server/Process/Users 三节点', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: AppProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const Scaffold(body: _GlobalHarness()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Process List'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);
    });

    testWidgets('capabilityGroups 提供 process.kill（advanced 组合并键）', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              final groups = const PostgresqlSidebarPlugin()
                  .capabilityGroups(context);
              expect(groups, hasLength(1));
              expect(groups.first.id, 'advanced');
              final ids = groups.first.items.map((i) => i.id).toList();
              expect(ids, contains('process.kill'));
              // 能力键与 id 一致（port 门控键）
              for (final item in groups.first.items) {
                expect(item.capabilityId, isNotNull);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
