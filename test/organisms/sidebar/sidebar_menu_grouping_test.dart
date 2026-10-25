// UIRV-A3 · 树右键菜单三段两分隔线（2026-10-25）。
//
// 验收条款直译（.specs/tasks-ui-review-fixes.md §UIRV-A3）：
// 1. 表菜单三段两 divider，组序 = 常规 → 结构 → 破坏；破坏项恒居末段且
//    isDestructive（error 色 + 危险图标走既有语义）。
// 2. 非表对象菜单：含结构项的（索引）破坏段独立于结构段（两 divider 节奏）；
//    无结构项的（视图）自然两段一 divider；纯浏览菜单不加多余 divider。
// 3. 键盘 ↑/↓ 跳过 divider；disabled 危险项可聚焦读出原因、Enter 不激活
//    （既有机制回归断言，ContextMenu 分子层直测）。
// 4. 不新增/删除任何菜单项（id 集合与改动前一致）。
// 5. divider 视觉 = 1px + 上下各 2px、左右各 8px；菜单上下 padding 4px
//    （按设计稿 A3 规格表 token 对齐，数值经 AppDesignSystem token 断言）。
//
// 纯结构测试：不触真库、不跑 e2e（确认门/动作语义由既有 integration 覆盖，
// 本批只验证组装顺序未破坏其入口）。
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/molecules/context_menu.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/theme/design_system.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';

/// 占位 adapter（hasConnection 判真；本组不触达任何 adapter 方法）。
class _FakeTreeAdapter extends Fake implements DatabaseAdapter {
  @override
  bool get isConnected => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 复用 sidebar_tree_test.dart 2b.4 组的 harness 形态（MySQL/PG 各一），
  /// 扩展：views 分类展开 + 表级 schema（含索引）以触达索引叶子菜单。
  Future<AppProvider> pumpTree(
    WidgetTester tester, {
    required DatabaseType type,
    required Database db,
    required Set<String> expandedItems,
    Set<String> expandedTables = const {},
    Map<String, DbTable> loadedTableSchemas = const {},
  }) async {
    final provider = AppProvider();
    final server = DbServer(
      id: 'conn-a',
      type: type,
      name: 'Tree One',
      host: '192.0.2.1',
      port: type == DatabaseType.postgresql ? 5432 : 3306,
      username: 'root',
      password: 'x',
    );
    provider.connection.addSavedServerForTest(server);
    provider.connection.setCurrentServerForTest(server);
    provider.connection.dbService.registerConnectedServerForTest(server);
    provider.connection.dbService.registerConnectedAdapterForTest(
      'conn-a',
      _FakeTreeAdapter(),
    );
    provider.connection.setConnectionDatabasesForTest(
      'conn-a',
      <String>['db_a'],
      <String>['db_a'],
    );
    provider.connection.setCachedDatabaseForTest('conn-a', 'db_a', db);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<ThemeProvider>(
                create: (_) => ThemeProvider()..load(),
              ),
              ChangeNotifierProvider<ServerConnectionProvider>(
                create: (_) => ServerConnectionProvider(),
              ),
            ],
            child: Scaffold(
              body: SidebarTree(
                expandedItems: expandedItems,
                expandedDatabases: const {'conn-a:db_a'},
                expandedTables: expandedTables,
                loadingDatabases: const {},
                loadedTableSchemas: loadedTableSchemas,
                loadedTableForeignKeys: const {},
                loadingTableSchemas: const {},
                onToggleExpand: (_) {},
                onToggleDatabase: (_) {},
                onToggleTable: (_) {},
                onLoadDatabaseInfo: (a, b) async {},
                onShowConnectionManager: () {},
                onShowSettings: () {},
                onShowERDiagram: () {},
                onShowStoredProcedures: () {},
                onShowTriggers: () {},
                tableRowCounts: const {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return provider;
  }

  /// 打开的上下文菜单原始 items（含 divider；_validItems 过滤前的组装序）。
  List<ContextMenuItem> openedMenuItems(WidgetTester tester) =>
      tester.widget<ContextMenu>(find.byType(ContextMenu)).items;

  /// 提取 id 序列（divider 显示为 'divider'）。
  List<String> idsOf(List<ContextMenuItem> items) =>
      items.map((i) => i.id).toList(growable: false);

  group('UIRV-A3 表菜单三段两 divider（验收 1/4）', () {
    testWidgets('UIRV-A3-001 MySQL 表菜单：常规→结构→破坏，恰两条 divider，破坏居末', (
      tester,
    ) async {
      await pumpTree(
        tester,
        type: DatabaseType.mysql,
        db: Database(
          name: 'db_a',
          tables: <DbTable>[DbTable(name: 'users')],
        ),
        expandedItems: const {'conn-a', 'conn-a:db_a:tables'},
      );

      await tester.tap(find.text('users'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final items = openedMenuItems(tester);
      expect(
        idsOf(items),
        equals(const [
          // 常规段：浏览 / 查看结构 / DDL / 维护 / 分析 / 引擎
          'browse',
          'properties',
          'view_ddl',
          'data_sync',
          'analyze_table',
          'optimize_table',
          'check_table',
          'ai_analyze_table',
          'engine_status',
          'divider',
          // 结构段：建表 / 编辑 / 重命名
          'create_table',
          'edit',
          'rename',
          'divider',
          // 破坏段：Empty / Drop 恒居末
          'truncate',
          'drop',
        ]),
        reason: '组序 = 常规 → 结构 → 破坏，恰两条 divider',
      );
    });

    testWidgets('UIRV-A3-002 破坏项语义与菜单项集合不变（验收 1/4）', (tester) async {
      await pumpTree(
        tester,
        type: DatabaseType.mysql,
        db: Database(
          name: 'db_a',
          tables: <DbTable>[DbTable(name: 'users')],
        ),
        expandedItems: const {'conn-a', 'conn-a:db_a:tables'},
      );

      await tester.tap(find.text('users'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final items = openedMenuItems(tester);
      // 破坏项 = 末两项，恒 isDestructive，动作入口仍在（确认门不回归）。
      final destructive = items.where((i) => i.isDestructive).toList();
      expect(idsOf(destructive), equals(const ['truncate', 'drop']));
      expect(items.last.id, equals('drop'));
      expect(items[items.length - 2].id, equals('truncate'));
      for (final d in destructive) {
        expect(d.onTap, isNotNull, reason: '${d.id} 动作入口保留');
        expect(d.icon, isNotNull, reason: '${d.id} 危险图标保留');
      }
      // 非破坏项不得携带 isDestructive。
      for (final i in items.take(items.length - 2)) {
        expect(i.isDestructive, isFalse, reason: '${i.id} 不应是破坏项');
      }
      // 不新增/删除任何菜单项（改动前 MySQL 表菜单 id 全集）。
      expect(
        idsOf(items.where((i) => !i.isDivider).toList()).toSet(),
        equals(const {
          'browse',
          'create_table',
          'edit',
          'properties',
          'view_ddl',
          'data_sync',
          'analyze_table',
          'optimize_table',
          'check_table',
          'ai_analyze_table',
          'engine_status',
          'rename',
          'truncate',
          'drop',
        }),
      );
    });
  });

  group('UIRV-A3 非表对象菜单分组（验收 2）', () {
    testWidgets('UIRV-A3-003 索引菜单：结构段独立于破坏段（两 divider）', (tester) async {
      final schema = DbTable(
        name: 'users',
        columns: <DbColumn>[
          DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
          DbColumn(name: 'name', type: 'varchar', isPrimaryKey: false),
        ],
        indexes: <DbIndex>[
          DbIndex(name: 'idx_users_name', columns: <String>['name']),
        ],
      );
      await pumpTree(
        tester,
        type: DatabaseType.mysql,
        db: Database(
          name: 'db_a',
          tables: <DbTable>[DbTable(name: 'users')],
        ),
        expandedItems: const {'conn-a', 'conn-a:db_a:tables'},
        expandedTables: const {'conn-a:db_a:users'},
        loadedTableSchemas: {'conn-a:db_a:users': schema},
      );

      // 索引叶子 label 带 "(columns)" 后缀 → textContaining 定位。
      await tester.tap(
        find.textContaining('idx_users_name'),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(
        idsOf(openedMenuItems(tester)),
        equals(const [
          'copyName',
          'insert',
          'divider',
          'editIndex',
          'divider',
          'dropIndex',
        ]),
        reason: '常规（复制/插入）→ 结构（编辑索引）→ 破坏（删除），两 divider 节奏',
      );
    });

    testWidgets('UIRV-A3-004 视图菜单：无结构项自然两段，破坏居末不造空段', (tester) async {
      await pumpTree(
        tester,
        type: DatabaseType.mysql,
        db: Database(
          name: 'db_a',
          tables: const <DbTable>[],
          views: const <String>['v_users'],
        ),
        expandedItems: const {'conn-a', 'conn-a:db_a:views'},
      );

      await tester.tap(find.text('v_users'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final items = openedMenuItems(tester);
      expect(
        idsOf(items),
        equals(const ['browse', 'copyName', 'divider', 'drop']),
        reason: '无结构项 → 自然两段一 divider，不造空段',
      );
      expect(items.last.isDestructive, isTrue);
    });
  });

  group('UIRV-A3 键盘与 disabled 既有机制回归（验收 3）', () {
    testWidgets('UIRV-A3-005 键盘 ↓ 跳过 divider，Enter 激活下一可选项', (tester) async {
      var aActivated = 0;
      var bActivated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem(
                  id: 'a',
                  label: 'A',
                  onTap: () => aActivated++,
                ),
                const ContextMenuItem.divider(),
                ContextMenuItem(
                  id: 'b',
                  label: 'B',
                  onTap: () => bActivated++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(aActivated, equals(0), reason: '首项 A 不应被激活');
      expect(bActivated, equals(1), reason: '↓ 一次应跳过 divider 落到 B');
    });

    testWidgets('UIRV-A3-006 disabled 危险项可聚焦读出原因，Enter 不激活', (tester) async {
      var dropActivated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem(
                  id: 'drop',
                  label: 'Drop',
                  isDestructive: true,
                  enabled: false,
                  disabledReason: 'Read-only connection',
                  onTap: () => dropActivated++,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始焦点落在首项（disabled 可聚焦）并渲染原因 tooltip。
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, equals('Read-only connection'));

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(dropActivated, equals(0), reason: 'disabled 项 Enter 不激活');
    });
  });

  group('UIRV-A3 divider 视觉规格（验收 5）', () {
    testWidgets('UIRV-A3-007 divider 1px/上下2/左右8；菜单上下 padding 4', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContextMenu(
              items: [
                ContextMenuItem(id: 'a', label: 'A', onTap: () {}),
                const ContextMenuItem.divider(),
                ContextMenuItem(id: 'b', label: 'B', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // divider：height 1 + margin(上下 menuDividerVPadding=2, 左右 space2=8)。
      final dividerContainers = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(ContextMenu),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.constraints?.maxHeight == 1,
              ),
            ),
          )
          .toList();
      expect(dividerContainers, hasLength(1));
      expect(
        dividerContainers.first.margin,
        equals(
          const EdgeInsets.symmetric(
            vertical: AppDesignSystem.menuDividerVPadding,
            horizontal: AppDesignSystem.space2,
          ),
        ),
      );

      // 菜单主体列：上下 padding = space1 (4px)。
      final menuPaddings = tester
          .widgetList<Padding>(
            find.descendant(
              of: find.byType(ContextMenu),
              matching: find.byType(Padding),
            ),
          )
          .where(
            (p) =>
                p.padding ==
                const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
          )
          .toList();
      expect(
        menuPaddings,
        hasLength(1),
        reason: '菜单上下 padding 4px（设计稿 A3 规格表）',
      );
    });
  });
}
