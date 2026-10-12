// C15 · MySQL 侧边栏插件单测：全局树三节点（Server/Performance/Users）
// + 能力分组（engine.status / process.kill，与 core 'advanced' 组合并键）
// + 库级树恒空（分缝回退契约：MySQL 走 sidebar_tree 通用装配至 C19）。
// DBT-T3 增补：新增 4 项位映射锁定 + 装配可见项数（core 5 + 插件 6）
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
import 'package:dbmaster/organisms/dialogs/mysql_table_maintenance_entry_dialog.dart';
import 'package:dbmaster/organisms/dialogs/table_maintenance_result_dialog.dart';
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/core_sidebar_plugin.dart';
import 'package:dbmaster/organisms/sidebar/plugins/mysql_sidebar_plugin.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
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

    testWidgets('capabilityGroups：advanced 组 6 项，位映射逐项锁定', (
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
              // DBT-T3：新增项 capabilityId 与 id 不同构，映射逐项锁定
              //（id 与 T2 _releaseNewItemIds 锁定值一致）。
              const expected = <String, String>{
                'process.kill': 'process.kill',
                'engine.status': 'engine.status',
                'mysql.variables': 'server.variables',
                'mysql.maintenance': 'table.analyze',
                'mysql.performance': 'ai.analyze',
                'mysql.backup': 'io.export',
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

    test('DBT-T3 项位全在 CapabilityTable 对 mysql 取真（T0 预登记）', () {
      const caps = [
        'process.kill',
        'engine.status',
        'server.variables',
        'table.analyze',
        'ai.analyze',
        'io.export',
      ];
      for (final cap in caps) {
        expect(CapabilityTable.has(DatabaseType.mysql, cap), isTrue,
            reason: cap);
      }
    });

    testWidgets('MySQL 装配可见项数 = core 5 + 插件 6 = 11（CapabilityTable 门控后）',
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
                type: DatabaseType.mysql,
                port: _TablePort(),
                plugins: const [CoreSidebarPlugin(), MysqlSidebarPlugin()],
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
                  // 插件 6
                  'process.kill',
                  'engine.status',
                  'mysql.variables',
                  'mysql.maintenance',
                  'mysql.performance',
                  'mysql.backup',
                ]),
              );
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

  group('MysqlTableMaintenanceEntryDialog（DBT-T3 聚合入口）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget _wrap(MysqlTableMaintenanceEntryDialog dialog) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: dialog),
        );

    Future<MysqlTableMaintenanceEntryDialog> _pumpEntry(WidgetTester tester,
        {required void Function(String table, TableMaintenanceCommand cmd)
            onRun}) async {
      final dialog = MysqlTableMaintenanceEntryDialog(
        connectionId: 'c1',
        loadDatabases: (_) async => ['chinook', 'dbmaster_test'],
        loadTables: (_, __) async => ['Artist', 'Album', 'Track'],
        runMaintenance: (_, __, table, cmd) async {
          onRun(table, cmd);
          return const <Map<String, dynamic>>[
            {'Table': 'x', 'Op': 'analyze', 'Msg_type': 'status', 'Msg_text': 'OK'},
          ];
        },
      );
      await tester.pumpWidget(_wrap(dialog));
      await tester.pumpAndSettle();
      return dialog;
    }

    testWidgets('渲染库下拉 / 动作 chips / 表清单与全选头', (tester) async {
      await _pumpEntry(tester, onRun: (_, _) {});

      expect(find.text('chinook'), findsOneWidget); // 默认选首库
      expect(find.text('Analyze Table'), findsOneWidget);
      expect(find.text('Optimize Table'), findsOneWidget);
      expect(find.text('Check Table'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
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

      await tester.tap(find.text('Artist'));
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
      expect(find.byType(MysqlTableMaintenanceEntryDialog), findsOneWidget);
    });

    testWidgets('确认后执行一次并出现既有结果 dialog', (tester) async {
      final executed = <String>[];
      TableMaintenanceCommand? executedCmd;
      await _pumpEntry(
        tester,
        onRun: (table, cmd) {
          executed.add(table);
          executedCmd = cmd;
        },
      );

      await tester.tap(find.text('Artist'));
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

      expect(executed, ['Artist']);
      expect(executedCmd, TableMaintenanceCommand.analyze);
      expect(find.byType(TableMaintenanceResultDialog), findsOneWidget);

      // 关结果 dialog → 循环走完 → 指示器复位
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(TableMaintenanceResultDialog), findsNothing);
      expect(find.byType(MysqlTableMaintenanceEntryDialog), findsOneWidget);
    });
  });
}
