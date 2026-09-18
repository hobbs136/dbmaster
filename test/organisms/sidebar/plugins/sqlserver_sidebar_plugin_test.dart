// C20 · SQL Server 侧边栏插件单测：库级 schema-first 树经
// SidebarDatabaseTreeContext 装配（迁移前直测 SqlServerTreeBuilder 的
// 两个测试文件用例合并改写，断言保持）；另覆盖全局树三节点、descriptor
// 与能力分组恒空契约。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/builders/tree_utils.dart';
import 'package:dbmaster/organisms/sidebar/plugins/sqlserver_sidebar_plugin.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';

import '../../results/query_history/history_test_helper.dart';

DbServer _server() => DbServer(
      id: 'ss_conn',
      name: 'Test SS',
      type: DatabaseType.sqlserver,
      host: 'localhost',
      port: 1433,
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
    connectionId: 'ss_conn',
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

class _DbHarness extends StatelessWidget {
  final SidebarDatabaseTreeContext dbContext;

  const _DbHarness({required this.dbContext});

  @override
  Widget build(BuildContext context) {
    final nodes = const SqlserverSidebarPlugin().buildDatabaseTree(
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
    final nodes = const SqlserverSidebarPlugin().buildGlobalTree(
      context,
      SidebarTreeContext(
        provider: provider,
        connectionId: 'ss_conn',
        expandedItems: {},
        onToggleExpand: (_) {},
      ),
    );
    return ListView(children: nodes);
  }
}

void main() {
  setupHistoryTestBinding();

  group('SqlserverSidebarPlugin descriptor / 恒空契约', () {
    test('descriptor 身份与适用类型', () {
      final d = const SqlserverSidebarPlugin().descriptor;
      expect(d.id, 'sqlserver-sidebar');
      expect(d.supportedTypes, {DatabaseType.sqlserver});
    });

    testWidgets('capabilityGroups 恒空（process.kill 位不含 ss——进程只读）', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: AppProvider(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      final groups = const SqlserverSidebarPlugin().capabilityGroups(
        tester.element(find.byType(SizedBox)),
      );
      expect(groups, isEmpty);
    });

    testWidgets('buildGlobalTree 渲染三节点（Server Status/Process List/Users）', (
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
      // 沿旧 builder 硬编码英文（行为逐行保持，TD 同款裁定）。
      expect(find.text('Server Status'), findsOneWidget);
      expect(find.text('Process List'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);
    });
  });

  group('SqlserverSidebarPlugin 库级 schema 树（原 builder 测试改写）', () {
    late AppProvider appProvider;
    late Database testDb;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      setupHistoryTestBinding();
      appProvider = AppProvider();
      testDb = Database(
        name: 'test_db',
        schemas: [
          // schemaName-scoped 加载后 views/procs/functions 为裸名
          DbSchema(
            name: 'dbo',
            tables: [DbTable(name: 'customers'), DbTable(name: 'orders')],
            views: ['active_customers'],
            procedures: ['sp_get_customer'],
            functions: ['fn_total'],
          ),
          DbSchema(name: 'sales', tables: [DbTable(name: 'invoices')]),
        ],
      );
    });

    Future<void> pumpHarness(
      WidgetTester tester, {
      required Database database,
      Set<String> expandedItems = const {},
      Set<String> expandedTables = const {},
      String searchQuery = '',
      Map<String, DbTable> loadedTableSchemas = const {},
      Map<String, List<ForeignKey>> loadedTableForeignKeys = const {},
    }) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: appProvider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: _DbHarness(
                dbContext: _dbContext(
                  appProvider,
                  database: database,
                  expandedItems: expandedItems,
                  expandedTables: expandedTables,
                  searchQuery: searchQuery,
                  loadedTableSchemas: loadedTableSchemas,
                  loadedTableForeignKeys: loadedTableForeignKeys,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders schema nodes', (tester) async {
      await pumpHarness(tester, database: testDb);

      expect(find.text('dbo'), findsOneWidget);
      expect(find.text('sales'), findsOneWidget);
    });

    testWidgets('expands schema and shows object categories', (tester) async {
      await pumpHarness(
        tester,
        database: testDb,
        expandedItems: const {'ss_conn:test_db:schema:dbo'},
      );

      expect(find.text('Tables (2)'), findsOneWidget);
      expect(find.text('Views (1)'), findsOneWidget);
      expect(find.text('Stored Procedures (1)'), findsOneWidget);
      expect(find.text('Functions (1)'), findsOneWidget);

      // Categories collapsed; individual objects not yet visible.
      expect(find.text('customers'), findsNothing);
    });

    testWidgets('expands tables category and shows tables', (tester) async {
      await pumpHarness(
        tester,
        database: testDb,
        expandedItems: const {
          'ss_conn:test_db:schema:dbo',
          'ss_conn:test_db:schema:dbo:tables',
        },
      );

      expect(find.text('customers'), findsOneWidget);
      expect(find.text('orders'), findsOneWidget);
    });

    testWidgets('展开表时渲染扁平交互式列叶子（4-segment schema key）', (
      tester,
    ) async {
      await pumpHarness(
        tester,
        database: testDb,
        expandedItems: const {
          'ss_conn:test_db:schema:dbo',
          'ss_conn:test_db:schema:dbo:tables',
        },
        expandedTables: const {'ss_conn:test_db:dbo:customers'},
        loadedTableSchemas: {
          'ss_conn:test_db:dbo:customers': DbTable(
            name: 'dbo.customers',
            columns: <DbColumn>[
              DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
              DbColumn(name: 'email', type: 'nvarchar'),
            ],
            indexes: <DbIndex>[
              DbIndex(name: 'PK_customers', columns: <String>['id']),
            ],
          ),
        },
        loadedTableForeignKeys: {
          'ss_conn:test_db:dbo:customers': <ForeignKey>[
            ForeignKey(
              name: 'fk_orders_customer',
              table: 'customers',
              column: 'id',
              referencedTable: 'orders',
              referencedColumn: 'customer_id',
            ),
          ],
        },
      );

      // 扁平列直接渲染（无 Columns 组头）
      expect(find.text('email'), findsOneWidget);
      expect(find.text('id'), findsOneWidget);
      // 索引分组头 + 外键分组头仍在
      expect(find.text('Indexes'), findsOneWidget);
      expect(find.text('Foreign Keys'), findsOneWidget);
      // 字段↔索引、索引↔外键 各一条分割线
      expect(find.byType(SchemaSectionDivider), findsNWidgets(2));
    });

    testWidgets('filters by search query', (tester) async {
      await pumpHarness(
        tester,
        database: testDb,
        searchQuery: 'customers',
      );

      // Schema "dbo" contains matching table "customers".
      expect(find.text('dbo'), findsOneWidget);
      // Schema "sales" has no "customers".
      expect(find.text('sales'), findsNothing);
    });

    testWidgets(
      'double-clicking a stored procedure opens a query tab with EXEC template (TC-SS-EXE-005)',
      (tester) async {
        final procedureDb = Database(
          name: 'test_db',
          schemas: const [DbSchema(name: 'dbo', procedures: ['p_needparam'])],
        );
        await pumpHarness(
          tester,
          database: procedureDb,
          expandedItems: const {
            'ss_conn:test_db:schema:dbo',
            'ss_conn:test_db:schema:dbo:procedures',
          },
        );

        expect(find.text('p_needparam'), findsOneWidget);

        final center = tester.getCenter(find.text('p_needparam'));
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(appProvider.tab.tabs.length, equals(1));
        final tab = appProvider.tab.tabs.first;
        expect(tab.sql, contains('EXEC'));
        expect(tab.sql, contains('[dbo].[p_needparam]'));
        expect(tab.sql, contains(';'));
        expect(tab.connectionId, equals('ss_conn'));
        expect(tab.databaseName, equals('test_db'));
      },
    );

    testWidgets(
      'double-clicking a table opens a query editor tab (TC-SS-BRW-001)',
      (tester) async {
        final tableDb = Database(
          name: 'test_db',
          schemas: [
            DbSchema(name: 'dbo', tables: [DbTable(name: 't_types')]),
          ],
        );
        await pumpHarness(
          tester,
          database: tableDb,
          expandedItems: const {
            'ss_conn:test_db:schema:dbo',
            'ss_conn:test_db:schema:dbo:tables',
          },
        );

        expect(find.text('t_types'), findsOneWidget);

        final center = tester.getCenter(find.text('t_types'));
        await tester.tapAt(center);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(center);
        await tester.pumpAndSettle();

        expect(appProvider.tab.tabs.length, equals(1));
        final tab = appProvider.tab.tabs.first;
        expect(tab.connectionId, equals('ss_conn'));
        expect(tab.databaseName, equals('test_db'));
        // 双击 → openTableQueryTab → query 模式（editor 可见、不自动执行）；
        // data 模式仅右键「浏览数据」进入。
        expect(tab.sql, isNotEmpty);
        final layout = appProvider.tab.panelLayoutFor(tab.id);
        expect(layout.editorVisible, isTrue,
            reason: '双击应进 query 模式（editor 可见）');
        expect(layout.filterBarVisible, isFalse,
            reason: 'query 模式 FilterBar 默认隐藏');
        expect(appProvider.tab.browseTargetFor(tab.id), isNull,
            reason: '双击不应挂 browseTarget');
      },
    );

    testWidgets(
      'expanding a table renders columns, indexes and foreign keys (TC-SS-BRW-002)',
      (tester) async {
        const tableKey = 'ss_conn:test_db:dbo:t_types';
        final db = Database(
          name: 'test_db',
          schemas: [
            DbSchema(
              name: 'dbo',
              tables: [
                DbTable(
                  name: 't_types',
                  columns: [
                    DbColumn(name: 'id', type: 'INT', isPrimaryKey: true),
                    DbColumn(name: 'c_varchar_reg', type: 'VARCHAR(100)'),
                  ],
                  indexes: [
                    DbIndex(
                      name: 'PK_t_types',
                      columns: const ['id'],
                      isUnique: true,
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        await pumpHarness(
          tester,
          database: db,
          expandedItems: const {
            'ss_conn:test_db:schema:dbo',
            'ss_conn:test_db:schema:dbo:tables',
          },
          expandedTables: const {tableKey},
          loadedTableSchemas: {
            tableKey: DbTable(
              name: 't_types',
              columns: [
                DbColumn(name: 'id', type: 'INT', isPrimaryKey: true),
                DbColumn(name: 'c_varchar_reg', type: 'VARCHAR(100)'),
              ],
              indexes: [
                DbIndex(
                  name: 'PK_t_types',
                  columns: const ['id'],
                  isUnique: true,
                ),
              ],
            ),
          },
        );

        expect(find.text('t_types'), findsOneWidget);
        expect(find.text('id'), findsWidgets);
        expect(find.text('c_varchar_reg'), findsWidgets);
        expect(find.textContaining('PK_t_types'), findsOneWidget);
      },
    );
  });
}
