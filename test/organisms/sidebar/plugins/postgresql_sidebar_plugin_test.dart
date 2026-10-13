// C15 · PostgreSQL 侧边栏插件单测：库级 schema 树经 SidebarDatabaseTreeContext
// 装配（迁移前直测 PostgresqlTreeBuilder.buildDatabaseNode 的用例改写，
// 断言保持）；另覆盖全局树节点与能力分组。
// DBT-T4 增补：新增 3 项位映射锁定 + 装配可见项数（core 5 + 插件 4）
// + 表维护聚合入口 dialog（确认门取消 = 零执行 / 确认执行一次）。
// DBT-T8 增补：pg.locks 项位（装配 10 项）+ VACUUM/REINDEX 动作位
// （确认门取消 = 零执行零审计 / 执行+审计+结果行 / 失败路径 / 库级
// VACUUM）+ R4-d PopScope 执行中不可关。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              // pg.extension 位 = 扩展管理能力面；pg.queryPlan 已销项——
              // R2 裁定，呈报包 #11 备查，本批无该项；DBT-T8 增 pg.locks；
              // DBT-T19 增 pg.foreignTable——id/cap 均为 T22 预登记值）。
              const expected = <String, String>{
                'process.kill': 'process.kill',
                'pg.extension': 'pg.extension',
                'pg.vector': 'pg.extension',
                'pg.maintenance': 'table.analyze',
                'pg.locks': 'pg.locks',
                'pg.foreignTable': 'pg.foreignTable',
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
        // DBT-T8：锁分析位（T0 预登记，本批接线消费）。
        'pg.locks',
        // DBT-T19：外部表位（T22 预登记，本批接线消费）。
        'pg.foreignTable',
      ];
      for (final cap in caps) {
        expect(CapabilityTable.has(DatabaseType.postgresql, cap), isTrue,
            reason: cap);
      }
    });

    testWidgets('PostgreSQL 装配可见项数 = core 5 + 插件 6 = 11（CapabilityTable 门控后）',
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
              expect(ids, hasLength(11));
              expect(
                ids,
                containsAll(const [
                  // core 5
                  'proc.list',
                  'func.list',
                  'trigger.list',
                  'schema.diff',
                  'ai.assistant',
                  // 插件 6（DBT-T8 增 pg.locks；DBT-T19 增 pg.foreignTable）
                  'process.kill',
                  'pg.extension',
                  'pg.vector',
                  'pg.maintenance',
                  'pg.locks',
                  'pg.foreignTable',
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

    testWidgets('渲染库下拉 / 三动作 chip（ANALYZE + T8 VACUUM/REINDEX）/ 表清单', (
      tester,
    ) async {
      await _pumpEntry(tester, onRun: (_, _) {});

      expect(find.text('chinook'), findsOneWidget); // 默认选首库
      expect(find.text('Maintenance'), findsOneWidget); // 标题
      expect(find.text('Analyze Table'), findsOneWidget); // T4 既有动作 chip
      expect(find.text('VACUUM'), findsOneWidget); // DBT-T8 扩展动作位
      expect(find.text('REINDEX'), findsOneWidget); // DBT-T8 扩展动作位
      expect(find.text('artist'), findsOneWidget);
      expect(find.text('Select Tables (leave empty for all)'), findsOneWidget);
      // 未选表 + 默认 ANALYZE → 执行（Confirm）禁用
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

  group('PostgresqlTableMaintenanceEntryDialog VACUUM/REINDEX（DBT-T8）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget _wrap(Widget child) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: child),
        );

    Future<void> _pumpOps(
      WidgetTester tester, {
      required PgMaintenanceExecutor execute,
      required PgMaintenanceAuditor audit,
    }) async {
      await tester.pumpWidget(
        _wrap(PostgresqlTableMaintenanceEntryDialog(
          connectionId: 'c1',
          loadDatabases: (_) async => ['chinook', 'dbmaster_test'],
          loadTables: (_, __) async => ['artist', 'album', 'track'],
          runMaintenance: (_, __, ___, ____) async =>
              const <Map<String, dynamic>>[],
          executeMaintenance: execute,
          auditMaintenance: audit,
        )),
      );
      await tester.pumpAndSettle();
    }

    /// 选动作 chip → 勾表 → 执行 → 到达专属确认门（返回是否已出现）。
    Future<bool> _startOp(WidgetTester tester, String chipLabel) async {
      await tester.tap(find.text(chipLabel));
      await tester.pump();
      await tester.tap(find.text('artist'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return tester.any(find.byType(DestructiveConfirmDialog));
    }

    testWidgets('VACUUM 确认门取消 = 零执行零审计（执行计数断言）', (tester) async {
      var execCount = 0;
      var auditCount = 0;
      await _pumpOps(
        tester,
        execute: (_, __, ___) async => execCount++,
        audit: (_) async => auditCount++,
      );

      expect(await _startOp(tester, 'VACUUM'), isTrue,
          reason: '专属确认门应出现');
      expect(find.text('Run VACUUM on artist?'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.widgetWithText(TextButton, 'Cancel'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(execCount, 0, reason: '取消 = 零执行');
      expect(auditCount, 0, reason: '取消 = 零审计');
      expect(find.byType(PostgresqlTableMaintenanceEntryDialog), findsOneWidget);
    });

    testWidgets('VACUUM 确认后执行一次 + 审计落账（SQL 逐字断言）+ 结果行', (
      tester,
    ) async {
      final executedSql = <String>[];
      final audits = <PgMaintenanceAuditRecord>[];
      await _pumpOps(
        tester,
        execute: (_, __, sql) async => executedSql.add(sql),
        audit: (r) async => audits.add(r),
      );

      expect(await _startOp(tester, 'VACUUM'), isTrue);
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // SQL 与 runTableMaintenance 内 buildSql PG 分支同源（标识符双引号）。
      expect(executedSql, ['VACUUM "artist"']);
      expect(audits, hasLength(1));
      expect(audits.first.sql, 'VACUUM "artist"');
      expect(audits.first.databaseName, 'chinook');
      expect(audits.first.connectionId, 'c1');
      expect(audits.first.success, isTrue);
      expect(audits.first.errorMessage, isNull);
      // 成功结果行（pgMaintainSuccess + 目标 + 耗时）。
      expect(find.textContaining('VACUUM completed'), findsOneWidget);
      expect(find.textContaining('artist'), findsWidgets);
    });

    testWidgets('REINDEX 执行 REINDEX TABLE 形态 + 审计', (tester) async {
      final executedSql = <String>[];
      await _pumpOps(
        tester,
        execute: (_, __, sql) async => executedSql.add(sql),
        audit: (_) async {},
      );

      expect(await _startOp(tester, 'REINDEX'), isTrue);
      expect(find.text('Run REINDEX on artist?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(executedSql, ['REINDEX TABLE "artist"']);
      expect(find.textContaining('REINDEX completed'), findsOneWidget);
    });

    testWidgets('失败路径：引擎错误原文进结果行 + 审计 success=false', (tester) async {
      final audits = <PgMaintenanceAuditRecord>[];
      await _pumpOps(
        tester,
        execute: (_, __, ___) async => throw StateError('engine boom'),
        audit: (r) async => audits.add(r),
      );

      expect(await _startOp(tester, 'VACUUM'), isTrue);
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(audits, hasLength(1));
      expect(audits.first.success, isFalse);
      expect(audits.first.errorMessage, contains('engine boom'));
      // 失败结果行（pgMaintainFailed + SelectableText 错误原文）。
      expect(find.textContaining('VACUUM failed'), findsOneWidget);
      expect(find.textContaining('engine boom'), findsOneWidget);
    });

    testWidgets('库级 VACUUM：未选表可执行，SQL = 裸 VACUUM，确认门明示库名', (
      tester,
    ) async {
      final executedSql = <String>[];
      await _pumpOps(
        tester,
        execute: (_, __, sql) async => executedSql.add(sql),
        audit: (_) async {},
      );

      // 切 VACUUM chip，不勾任何表。
      await tester.tap(find.text('VACUUM'));
      await tester.pump();
      final confirmBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Confirm'),
      );
      expect(confirmBtn.onPressed, isNotNull,
          reason: 'VACUUM 未选表 = 库级全量，应可执行');

      await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      // 确认门 target = 当前所选库（默认首库 chinook）；库级形态文案与
      // 表级区分（pgVacuumConfirmDb 明示「所有表」，收口追加批）。
      expect(
        find.text('Run VACUUM on all tables in database chinook?'),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(executedSql, ['VACUUM']);
      expect(find.textContaining('VACUUM completed'), findsOneWidget);
    });

    testWidgets('REINDEX 未选表 = 无目标（按钮禁用，防御性返回）', (tester) async {
      var execCount = 0;
      await _pumpOps(
        tester,
        execute: (_, __, ___) async => execCount++,
        audit: (_) async {},
      );

      await tester.tap(find.text('REINDEX'));
      await tester.pump();
      final confirmBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Confirm'),
      );
      expect(confirmBtn.onPressed, isNull, reason: 'REINDEX 无库级形态');
      expect(execCount, 0);
    });

    testWidgets('默认执行器路径（不注入接缝）经 AppProvider.executeQuery', (
      tester,
    ) async {
      // 生产默认 executor = context.read<AppProvider>().executeQuery——
      // e2e 曾暴露 tear-off 签名错配只在默认路径可现（接缝注入的单测覆盖
      // 不到），此处锁默认路径的接线（未连接库 → 引擎侧报 Not connected
      // 进失败结果行 = 默认路径真实触达 provider 执行面的证据）。
      final audits = <PgMaintenanceAuditRecord>[];
      final provider = AppProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: PostgresqlTableMaintenanceEntryDialog(
                connectionId: 'c1',
                loadDatabases: (_) async => ['chinook'],
                loadTables: (_, __) async => ['artist'],
                runMaintenance: (_, __, ___, ____) async =>
                    const <Map<String, dynamic>>[],
                auditMaintenance: (r) async => audits.add(r),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('VACUUM'));
      await tester.pump();
      await tester.tap(find.text('artist'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // 未连接库 → 默认执行器触达 provider.executeQuery 并以失败收口
      // （失败行 + 审计 success=false；NoSuchMethodError 类接线缺陷不会
      // 产生该形态——错误原文为引擎/服务层异常文本）。
      expect(find.textContaining('VACUUM failed'), findsOneWidget);
      expect(audits, hasLength(1));
      expect(audits.first.success, isFalse);
      expect(audits.first.errorMessage, isNotNull);
    });

    testWidgets('R4-d：执行中 PopScope 拦 Esc/屏障，完成后 Cancel 可关', (
      tester,
    ) async {
      // 经 showDialog 路由泵（barrierDismissible:false 沿插件生产形态），
      // 执行器挂起以稳定处于 _running 态。
      final executorGate = Completer<void>();
      late StateSetter dialogHostSetState;
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                dialogHostSetState = setState;
                return TextButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => PostgresqlTableMaintenanceEntryDialog(
                        connectionId: 'c1',
                        loadDatabases: (_) async => ['chinook'],
                        loadTables: (_, __) async => ['artist'],
                        runMaintenance: (_, __, ___, ____) async =>
                            const <Map<String, dynamic>>[],
                        executeMaintenance: (_, __, ___) => executorGate.future,
                        auditMaintenance: (_) async {},
                      ),
                    );
                    setState(() => opened = true);
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(PostgresqlTableMaintenanceEntryDialog), findsOneWidget);

      // 进入执行中态：勾表 → Confirm → 门内确认 → executor 挂起。
      await tester.tap(find.text('VACUUM'));
      await tester.pump();
      await tester.tap(find.text('artist'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.descendant(
          of: find.byType(DestructiveConfirmDialog),
          matching: find.text('Confirm'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DestructiveConfirmDialog), findsNothing,
          reason: '门已确认，进入执行中');

      // 执行中：Esc 与屏障点击都不关（PopScope canPop:false 拦 maybePop）。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.byType(PostgresqlTableMaintenanceEntryDialog), findsOneWidget,
          reason: '执行中不可 Esc/屏障关闭');

      // 放行 executor → 结果行 → Cancel 正常关闭（canPop 复位）。
      executorGate.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('VACUUM completed'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(PostgresqlTableMaintenanceEntryDialog), findsNothing);
      // 防御：StatefulBuilder 变量闭合使用（避免未用告警）。
      dialogHostSetState(() => opened = opened);
      expect(opened, isTrue);
    });
  });
}
