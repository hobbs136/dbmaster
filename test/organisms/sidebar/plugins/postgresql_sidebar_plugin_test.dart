// C15 · PostgreSQL 侧边栏插件单测：库级 schema 树经 SidebarDatabaseTreeContext
// 装配（迁移前直测 PostgresqlTreeBuilder.buildDatabaseNode 的用例改写，
// 断言保持）；另覆盖全局树节点与能力分组。
// DBT-T4 增补：新增 3 项位映射锁定 + 装配可见项数（core 5 + 插件 4）
// + 表维护聚合入口 dialog（确认门取消 = 零执行 / 确认执行一次）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/table_maintenance_command.dart';
import 'package:dbmaster/molecules/destructive_confirm_dialog.dart';
import 'package:dbmaster/organisms/dialogs/confirm_maintenance_dialog.dart';
import 'package:dbmaster/organisms/dialogs/postgresql_table_maintenance_entry_dialog.dart';
import 'package:dbmaster/organisms/dialogs/table_maintenance_result_dialog.dart';
import 'package:dbmaster/organisms/sidebar/builders/tree_utils.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/postgresql_sidebar_plugin.dart';
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

    testWidgets('DBT-T4 新增项位映射锁定（id 与 T2 徽标集口径一致）', (
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
              // DBT-T4：新增项 capabilityId 映射逐项锁定（pg.vector 复用
              // pg.extension 位 = 扩展管理能力面；pg.queryPlan 主代理裁定
              // 暂缓，本批无该项）。
              const expected = <String, String>{
                'process.kill': 'process.kill',
                'pg.extension': 'pg.extension',
                'pg.vector': 'pg.extension',
                'pg.maintenance': 'table.analyze',
              };
              final items = groups.first.items;
              expect(items.map((i) => i.id).toList(), expected.keys.toList());
              for (final item in items) {
                expect(item.capabilityId, expected[item.id], reason: item.id);
              }
              // 全部项有激活动作（纯展示项 = 装配缺口）。
              expect(items.every((i) => i.onActivate != null), isTrue);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('DBT-T4 项位全在 CapabilityTable 对 postgresql 取真（T0 预登记）', () {
      const caps = [
        'process.kill',
        'pg.extension',
        'table.analyze',
      ];
      for (final cap in caps) {
        expect(CapabilityTable.has(DatabaseType.postgresql, cap), isTrue,
            reason: cap);
      }
    });

    testWidgets('PostgreSQL 装配可见项数 = core 5 + 插件 4 = 9（CapabilityTable 门控后）',
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
                type: DatabaseType.postgresql,
                port: _TablePort(),
                plugins: const [CoreSidebarPlugin(), PostgresqlSidebarPlugin()],
                l10n: AppLocalizations.of(context)!,
              );
              final ids = [
                for (final g in groups)
                  ...g.items.map((i) => i.item.id),
              ];
              expect(ids, hasLength(9));
              expect(
                ids,
                containsAll(const [
                  // core 5
                  'proc.list',
                  'func.list',
                  'trigger.list',
                  'schema.diff',
                  'ai.assistant',
                  // 插件 4
                  'process.kill',
                  'pg.extension',
                  'pg.vector',
                  'pg.maintenance',
                ]),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group('PostgresqlTableMaintenanceEntryDialog（DBT-T4 聚合入口）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget _wrap(PostgresqlTableMaintenanceEntryDialog dialog) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: dialog),
        );

    Future<PostgresqlTableMaintenanceEntryDialog> _pumpEntry(
      WidgetTester tester, {
      required void Function(String table, TableMaintenanceCommand cmd) onRun,
    }) async {
      final dialog = PostgresqlTableMaintenanceEntryDialog(
        connectionId: 'c1',
        loadDatabases: (_) async => ['chinook', 'dbmaster_test'],
        loadTables: (_, __) async => ['artist', 'album', 'track'],
        runMaintenance: (_, __, table, cmd) async {
          onRun(table, cmd);
          return const <Map<String, dynamic>>[];
        },
      );
      await tester.pumpWidget(_wrap(dialog));
      await tester.pumpAndSettle();
      return dialog;
    }

    testWidgets('渲染库下拉 / ANALYZE 动作 chip（T4 单动作，T8 预留位）/ 表清单', (
      tester,
    ) async {
      await _pumpEntry(tester, onRun: (_, _) {});

      expect(find.text('chinook'), findsOneWidget); // 默认选首库
      expect(find.text('Maintenance'), findsOneWidget); // 标题
      expect(find.text('Analyze Table'), findsOneWidget); // 唯一动作 chip
      expect(find.text('artist'), findsOneWidget);
      expect(find.text('Select Tables (leave empty for all)'), findsOneWidget);
      // 未选表 → 执行（Confirm）禁用
      final confirmBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Confirm'),
      );
      expect(confirmBtn.onPressed, isNull);
    });

    testWidgets('确认门取消 = 零执行（runMaintenance 不被调用）', (tester) async {
      var runCount = 0;
      await _pumpEntry(tester, onRun: (_, _) => runCount++);

      await tester.tap(find.text('artist'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
      // 执行中入口按钮是旋转指示器（永不收敛），此处只定长推进帧，
      // 待确认门路由动画完成后断言。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 逐表确认门出现（sidebar_tree 同一 ConfirmMaintenanceDialog）
      expect(find.byType(ConfirmMaintenanceDialog), findsOneWidget);

      // 取消
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.widgetWithText(TextButton, 'Cancel'),
        ),
      );
      // 取消 = 跳过该表，循环走完 → _running 复位 → 旋转指示器消失后可 settle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(runCount, 0);
      expect(find.byType(PostgresqlTableMaintenanceEntryDialog), findsOneWidget);
    });

    testWidgets('确认后执行一次（ANALYZE 命令）并出现既有结果 dialog', (tester) async {
      final executed = <String>[];
      TableMaintenanceCommand? executedCmd;
      await _pumpEntry(
        tester,
        onRun: (table, cmd) {
          executed.add(table);
          executedCmd = cmd;
        },
      );

      await tester.tap(find.text('artist'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 门内确认（scope 到 DestructiveConfirmDialog，避开底层入口的 Confirm）
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 与 sidebar_tree PG 右键同命令（analyze，经 runTableMaintenance 的
      // PG 分支产出 `ANALYZE "table"`）
      expect(executed, ['artist']);
      expect(executedCmd, TableMaintenanceCommand.analyze);
      expect(find.byType(TableMaintenanceResultDialog), findsOneWidget);

      // 关结果 dialog → 循环走完 → 指示器复位
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(TableMaintenanceResultDialog), findsNothing);
      expect(
        find.byType(PostgresqlTableMaintenanceEntryDialog),
        findsOneWidget,
      );
    });
  });
}
