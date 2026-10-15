// Q1 快捷面板装配框架 widget 测试（2026-10 工具面板补齐批 T2）。
// 覆盖（任务书验收标准 ①~④、⑥）：
// ① 五库型标题带库型名 + 装配内容切换；
// ② 折叠记忆（toggle → 重建 widget 态保持，mock prefs）；
// ③ 「新建」徽标只命中 _releaseNewItemIds（构造命中/不命中 id）；
//    T22 追加：第二程序预登记 4 id 命中面（sqlserver 注入件）。
// ④ Alt+Q 触发折叠切换 + 展开后聚焦面板根；聚焦后数字直达 / ↑↓ 移动 /
//    Enter 激活（Focus 测试；数字直达边界 = 序号超可见项数忽略）。
// ⑤ 无连接自隐藏由既有 sidebar_capability_menu_test.dart 锚定，不重复。
// ⑥ header 主标识 = 锚定连接名（同型双连接锚定切换用例，见「header 锚定
//    连接名」组）；库型名标题沿既有 l10n 输出保留为次级行。
// 用例登记建议编号：DBT-CAPMENU-101~108（回报 T13 汇总）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/core/shortcuts/global_shortcuts_wrapper.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/sidebar/capability/capability_menu_assembly.dart';
import 'package:dbmaster/organisms/sidebar/capability/sidebar_capability_menu.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_abstract.dart' show DatabaseAdapter;
import 'package:dbmaster/theme/app_theme.dart';

/// 测试注入插件（仅 sqlite 命中，注册于 [defaultPluginRegistry]，本文件
/// 进程内全局生效——各用例已计入其后置两行）。两项 capabilityId 均为 null
///（纯导航项，不依赖能力位）；前者 id 取自 `_releaseNewItemIds` 锁定值
///（验徽标命中面，真实消费件归 T3 任务），后者不在集内（作键盘 roving 的
/// 末项边界锚定；徽标不命中面用视口内可见的真实集外行验证，见徽标用例注）。
class _Q1TestSidebarPlugin implements SidebarPlugin {
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'q1-test-sidebar',
        supportedTypes: {DatabaseType.sqlite},
        source: PluginSource.databaseType,
        icon: LucideIcons.wrench,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) => [
        SidebarCapabilityGroup(
          id: 'q1-test',
          label: (l10n) => 'Q1 Test Group',
          icon: LucideIcons.wrench,
          items: [
            SidebarCapabilityItem(
              id: 'mysql.variables',
              label: (l10n) => 'Q1 Test Variables',
              icon: LucideIcons.database,
              onActivate: () => variablesActivated = true,
            ),
            SidebarCapabilityItem(
              id: 'q1.test.nobadge',
              label: (l10n) => 'Q1 Test NoBadge',
              icon: LucideIcons.bot,
              onActivate: () => noBadgeActivated = true,
            ),
          ],
        ),
      ];

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) =>
      const [];

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) =>
      const [];
}

bool variablesActivated = false;
bool noBadgeActivated = false;

/// T22 徽标预登记测试注入件（仅 tdengine 命中）：第二程序预登记 4 id
/// 各挂一个合成项（capabilityId null 纯导航），验 `_releaseNewItemIds`
/// 追加集的徽标命中面。tdengine 插件 capabilityGroups 恒空（见其头注），
/// 装配 = core 2 + 本注入 4 = 6 项（不触碰 sqlite 键盘用例与 sqlserver
/// 数字直达边界用例的前置断言）。
class _Q1T22BadgeTestPlugin implements SidebarPlugin {
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'q1-t22-badge-test-sidebar',
        supportedTypes: {DatabaseType.tdengine},
        source: PluginSource.databaseType,
        icon: LucideIcons.wrench,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) => [
        SidebarCapabilityGroup(
          id: 'q1-t22-test',
          label: (l10n) => 'Q1 T22 Test Group',
          icon: LucideIcons.wrench,
          items: [
            SidebarCapabilityItem(
              id: 'mongo.schemaAnalysis',
              label: (l10n) => 'Q1 T22 SchemaAnalysis',
              icon: LucideIcons.database,
              onActivate: () {},
            ),
            SidebarCapabilityItem(
              id: 'mysql.events',
              label: (l10n) => 'Q1 T22 Events',
              icon: LucideIcons.database,
              onActivate: () {},
            ),
            SidebarCapabilityItem(
              id: 'pg.foreignTable',
              label: (l10n) => 'Q1 T22 ForeignTable',
              icon: LucideIcons.database,
              onActivate: () {},
            ),
            SidebarCapabilityItem(
              id: 'redis.backup',
              label: (l10n) => 'Q1 T22 Backup',
              icon: LucideIcons.database,
              onActivate: () {},
            ),
          ],
        ),
      ];

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) =>
      const [];

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) =>
      const [];
}

DbServer _server(DatabaseType type) => DbServer(
      id: 'conn-${type.name}',
      type: type,
      name: 'Test ${type.name}',
      host: 'localhost',
      port: 5432,
      username: 'u',
      password: 'p',
    );

/// T25 组用：仅 isConnected 取真——hasConnection 检查 adapters（非 servers
/// 态），须注入连接态 adapter 使 isConnectionConnected 为真（沿
/// app_provider_switch_tab_sync_test 同款接缝）。
class _FakeConnectedAdapter implements DatabaseAdapter {
  @override
  bool get isConnected => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _providers(AppProvider provider, Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider()..load(),
        ),
        ChangeNotifierProvider<ServerConnectionProvider>(
          create: (_) => ServerConnectionProvider(),
        ),
      ],
      child: child,
    );

Widget _host(AppProvider provider, {Key? menuKey, bool withWrapper = false}) =>
    MaterialApp(
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      locale: const Locale('en'),
      home: _providers(
        provider,
        Scaffold(
          body: GlobalShortcutsWrapper(
            child: SizedBox(
              width: 260,
              height: 800,
              child: SidebarCapabilityMenu(key: menuKey),
            ),
          ),
        ),
      ),
    );

/// 当前装配的可见项扁平序（与菜单 build 同参同源，跨组连续序号事实源）。
List<AssembledCapabilityItem> _flatItems(
  WidgetTester tester,
  AppProvider provider,
) {
  final server = provider.connection.currentServer;
  if (server == null) fail('测试前置失败：无活动连接');
  final context = tester.element(find.byType(SidebarCapabilityMenu));
  return [
    for (final group in assembleCapabilityMenu(
      context: context,
      type: server.type,
      port: provider.connection.ports.resolveFor(server.type),
      plugins: defaultPluginRegistry.sidebarPluginsFor(server.type),
      l10n: AppLocalizations.of(context)!,
    ))
      ...group.items,
  ];
}

/// Alt+Q 全局键（经 GlobalShortcutsWrapper 的 HardwareKeyboard 管线）。
/// _safeExecute 延迟一帧执行，故补 pump。
Future<void> _sendAltQ(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    variablesActivated = false;
    noBadgeActivated = false;
  });

  setUpAll(() {
    // widget 经全局默认注册表取插件——追加测试注入件（本文件进程内生效）。
    defaultPluginRegistry.registerSidebar(_Q1TestSidebarPlugin());
    defaultPluginRegistry.registerSidebar(_Q1T22BadgeTestPlugin());
  });

  group('Q1 标题带库型名 + 装配内容切换', () {
    testWidgets('mysql：标题 + DATABASE OBJECTS 组在', (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.mysql));
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Capabilities: MySQL'), findsOneWidget);
      expect(find.text('Stored Procedures'), findsOneWidget);
    });

    testWidgets('postgresql：标题 + DATABASE OBJECTS 组在', (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.postgresql));
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Capabilities: PostgreSQL'), findsOneWidget);
      expect(find.text('Stored Procedures'), findsOneWidget);
    });

    testWidgets('sqlite：标题 + 无 proc/func/trigger（内容随型切换）',
        (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.sqlite));
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Capabilities: SQLite'), findsOneWidget);
      expect(find.text('Stored Procedures'), findsNothing);
      expect(find.text('Schema Diff & Sync'), findsOneWidget);
      // 测试注入件（capabilityId null 纯导航）随装配渲染
      expect(find.text('Q1 Test Variables'), findsOneWidget);
    });

    testWidgets('redis：标题 + 无 proc/func/trigger', (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.redis));
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Capabilities: Redis'), findsOneWidget);
      expect(find.text('Stored Procedures'), findsNothing);
    });

    testWidgets('mongodb：标题 + core 两件（插件当前无能力项）', (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.mongodb));
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Capabilities: MongoDB'), findsOneWidget);
      expect(find.text('Schema Diff & Sync'), findsOneWidget);
      expect(find.text('AI Assistant'), findsOneWidget);
      expect(find.text('Stored Procedures'), findsNothing);
    });
  });

  group('Q1 header 锚定连接名（同型实例可辨）', () {
    testWidgets('同型双连接：锚定 A 显 A.name，切 B 显 B.name；库型名标题保留',
        (tester) async {
      final provider = AppProvider();
      // 缺陷场景：两台同类型（mysql×2）连接——旧版 header 仅库型名时
      // 两态外观一致，无法辨认面板锚定谁。
      const aName = 'Prod MySQL';
      const bName = 'Staging MySQL';
      final a = DbServer(
        id: 'conn-a',
        type: DatabaseType.mysql,
        name: aName,
        host: 'host-a',
        port: 3306,
      );
      final b = DbServer(
        id: 'conn-b',
        type: DatabaseType.mysql,
        name: bName,
        host: 'host-b',
        port: 3307,
      );
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServer(a);
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text(aName), findsOneWidget);
      expect(find.text(bName), findsNothing);
      // 库型名次级行沿既有 l10n 调用输出（零改动）。
      expect(find.text('Capabilities: MySQL'), findsOneWidget);
      // 连接名溢出防护沿既有 Tooltip + 省略号模式。
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '') == aName,
        ),
        findsOneWidget,
      );

      // 切锚定到 B：setCurrentServer（改 id）notifyListeners → 经 AppProvider
      // 转发重建（同型切换，旧版渲染应零变化，新版连接名行随之更替）。
      provider.connection.setCurrentServer(b);
      await tester.pump();

      expect(find.text(bName), findsOneWidget);
      expect(find.text(aName), findsNothing);
      expect(find.text('Capabilities: MySQL'), findsOneWidget);
    });
  });

  group('T25 锚定序反转：面板跟随活动 tab（tab → currentServer → 选中）', () {
    testWidgets('活动 tab（已连接）优先于 currentServer；切 tab 面板整体切换',
        (tester) async {
      final provider = AppProvider();
      final mysql = _server(DatabaseType.mysql);
      final pg = _server(DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(mysql);
      provider.connection.addSavedServerForTest(pg);
      provider.dbService.registerConnectedServerForTest(mysql);
      provider.dbService.registerConnectedServerForTest(pg);
      provider.dbService.registerConnectedAdapterForTest(
        mysql.id,
        _FakeConnectedAdapter(),
      );
      provider.dbService.registerConnectedAdapterForTest(
        pg.id,
        _FakeConnectedAdapter(),
      );
      // currentServer 停在 PG（模拟旧「全局切换」语义残留）；活动 tab 属
      // MySQL（已连接）→ 新序按 MySQL 装配（旧序 currentServer 优先会
      // 渲染 PG——本断言在旧代码上失败，锚定序位反转）。
      provider.connection.setCurrentServer(pg);
      provider.tab.addTab(
        QueryTab(
          id: 't-mysql',
          title: 'query',
          sql: 'SELECT 1',
          connectionId: mysql.id,
          databaseName: 'db',
          databaseType: DatabaseType.mysql,
        ),
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Capabilities: MySQL'), findsOneWidget);
      expect(find.text('Variables'), findsOneWidget, reason: 'MySQL 专有项');
      expect(find.text('Capabilities: PostgreSQL'), findsNothing);

      // 切到 PG tab → 标题/内容整体随 tab 切换（验收标准 ④）。
      provider.tab.addTab(
        QueryTab(
          id: 't-pg',
          title: 'query2',
          sql: 'SELECT 2',
          connectionId: pg.id,
          databaseName: 'db',
          databaseType: DatabaseType.postgresql,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Capabilities: PostgreSQL'), findsOneWidget);
      expect(find.text('Extensions'), findsOneWidget, reason: 'PG 专有项');
      expect(find.text('Capabilities: MySQL'), findsNothing);
    });

    testWidgets('活动 tab 未连接 → 回退 currentServer（动作护栏保持）',
        (tester) async {
      final provider = AppProvider();
      final mysql = _server(DatabaseType.mysql);
      final pg = _server(DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(mysql);
      provider.connection.addSavedServerForTest(pg);
      // 仅 PG 注册连接态（server + adapter）；tab 属未连接的 MySQL → 按
      // currentServer=PG 装配。
      provider.dbService.registerConnectedServerForTest(pg);
      provider.dbService.registerConnectedAdapterForTest(
        pg.id,
        _FakeConnectedAdapter(),
      );
      provider.connection.setCurrentServer(pg);
      provider.tab.addTab(
        QueryTab(
          id: 't-mysql',
          title: 'query',
          sql: 'SELECT 1',
          connectionId: mysql.id,
          databaseName: 'db',
          databaseType: DatabaseType.mysql,
        ),
      );

      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Capabilities: PostgreSQL'), findsOneWidget);
      expect(find.text('Capabilities: MySQL'), findsNothing);
    });
  });

  group('Q1 折叠记忆', () {
    testWidgets('toggle 折叠 → 重建 widget 态保持（mock prefs）', (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.mysql));
      await tester.pumpWidget(_host(provider, menuKey: const ValueKey('a')));
      await tester.pump();

      await tester.tap(find.text('Capabilities: MySQL'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('AI Assistant'), findsNothing);

      // 重建 widget（新 key = 新 State）→ post-frame 读持久化值校正后仍折叠
      await tester.pumpWidget(
        _host(provider, menuKey: const ValueKey('b')),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('AI Assistant'), findsNothing);
      expect(find.text('Capabilities: MySQL'), findsOneWidget);
    });
  });

  group('Q1 新建徽标', () {
    testWidgets('徽标只命中 _releaseNewItemIds（命中/不命中各一）',
        (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.sqlite));
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Q1 Test Variables'), findsOneWidget);
      // 按行断言（行 = Tooltip，message 含项标签）：集内 id 行渲染「New」
      // 徽标、集外行无。不做全局计数——路由任务（T5 等）并入的集内真实项
      // 各自带合法徽标，计数随波次变化。
      // 行选取限定在视口内可见行（ListView 有 264px 上限的惰性构建，装配
      // 9 项时末行不入树——探针核实）：合成命中件（mysql.variables）+ 真实
      // T5 命中件（sqlite.maintain）+ 真实不命中件（sqlite.pragma）。
      // 键盘用例不受视口裁剪影响（导航走 _visibleItems，不做命中测试）。
      final hitRow = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('Q1 Test Variables'),
      );
      final realHitRow = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('Maintenance'),
      );
      final missRow = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('PRAGMA Explorer'),
      );
      expect(hitRow, findsOneWidget);
      expect(realHitRow, findsOneWidget);
      expect(missRow, findsOneWidget);
      expect(
        find.descendant(of: hitRow, matching: find.text('New')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: realHitRow, matching: find.text('New')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: missRow, matching: find.text('New')),
        findsNothing,
      );
    });

    testWidgets('T22 预登记 4 id 徽标命中 + 集外既有项不命中（tdengine）',
        (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.tdengine));
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      // 集外既有项（core schema.diff 不在集内）不渲染徽标。
      final missRow = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('Schema Diff'),
      );
      expect(missRow, findsOneWidget);
      expect(
        find.descendant(of: missRow, matching: find.text('New')),
        findsNothing,
      );

      // 4 个预登记 id（T17/T18/T19/T20 消费）全部渲染「New」徽标；
      // 装配 6 项理论上全入 264px 视口，末行超界时拖拽兜底入树。
      for (final label in const [
        'Q1 T22 SchemaAnalysis',
        'Q1 T22 Events',
        'Q1 T22 ForeignTable',
        'Q1 T22 Backup',
      ]) {
        final row = find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').contains(label),
        );
        await tester.dragUntilVisible(
          row,
          find.byType(Scrollable),
          const Offset(0, -40),
        );
        expect(row, findsOneWidget, reason: label);
        expect(
          find.descendant(of: row, matching: find.text('New')),
          findsOneWidget,
          reason: label,
        );
      }
    });
  });

  group('Q1 Alt+Q 全局键 + 面板局部键盘', () {
    testWidgets('Alt+Q 折叠 → 再按展开并聚焦面板根', (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.sqlite));
      await tester.pumpWidget(_host(provider));
      await tester.pump();

      expect(find.text('Q1 Test Variables'), findsOneWidget);
      await _sendAltQ(tester);
      expect(find.text('Q1 Test Variables'), findsNothing);

      await _sendAltQ(tester);
      expect(find.text('Q1 Test Variables'), findsOneWidget);
      // 聚焦断言：primary focus 落在菜单 State 子树（面板根 Focus）
      final primary = FocusManager.instance.primaryFocus;
      expect(primary, isNotNull);
      final inMenu = primary!.context?.findAncestorStateOfType<
          State<SidebarCapabilityMenu>>();
      expect(inMenu, isNotNull);
    });

    testWidgets('面板聚焦后数字直达（跨组连续序号）', (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.sqlite));
      await tester.pumpWidget(_host(provider));
      await tester.pump();
      await _sendAltQ(tester);
      await _sendAltQ(tester);

      final items = _flatItems(tester, provider);
      final target = items.indexWhere((e) => e.item.id == 'mysql.variables');
      expect(target, greaterThanOrEqualTo(0));
      // 数字直达仅覆盖前 9 项（测试注入件在末尾，前置件数变化需保持此前提）
      expect(target, lessThan(9), reason: '数字直达仅覆盖前 9 项');

      // target < 9 已断言 → _digitKey 非空（前证非空，豁免裸 ! 禁令）
      await tester.sendKeyEvent(_digitKey(target + 1)!);
      await tester.pump();
      expect(variablesActivated, isTrue);
      expect(noBadgeActivated, isFalse);
    });

    testWidgets('↑/↓ 项间移动 + Enter 激活当前项（roving）', (tester) async {
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.sqlite));
      await tester.pumpWidget(_host(provider));
      await tester.pump();
      await _sendAltQ(tester);
      await _sendAltQ(tester);

      final items = _flatItems(tester, provider);
      // ↓ 压满到末项（clamp），↑ 回退一项 → 命中测试注入件（无对话框副作用）
      for (var i = 0; i < items.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(variablesActivated, isTrue);
      expect(noBadgeActivated, isFalse);
    });

    testWidgets('数字直达边界：序号超可见项数 = 忽略', (tester) async {
      // 用 sqlserver（capabilityGroups 恒空 = 仅 core 2 项）：压到
      // items.length+1 序号必超界，且可达项不含可观察激活面以外的副作用。
      // （sqlite + 测试注入件已满 9 项，超界序号不存在，不适用本用例；
      // 原主体 mongo 在 DBT-T11 后 core 2 + 插件 7 = 9 项满额，同因换型——
      // sqlserver/tdengine 恒空裁定见各自插件头注。）
      final provider = AppProvider();
      provider.connection.setCurrentServer(_server(DatabaseType.sqlserver));
      await tester.pumpWidget(_host(provider));
      await tester.pump();
      await _sendAltQ(tester);
      await _sendAltQ(tester);

      final items = _flatItems(tester, provider);
      expect(items.length, lessThan(9), reason: '前置：须存在超界数字序号');
      final outOfRange = _digitKey(items.length + 1);
      expect(outOfRange, isNotNull);
      await tester.sendKeyEvent(outOfRange!);
      await tester.pump();

      // 无激活、无崩溃、面板仍在（可达项 ai.assistant 处于 digit2，未被触发）
      expect(provider.aiPanel.aiPanelOpen, isFalse);
      expect(find.text('Capabilities: SQL Server'), findsOneWidget);
    });
  });
}

/// 数字序 → 主键盘 LogicalKeyboardKey（测试辅助）。
LogicalKeyboardKey? _digitKey(int digit) => switch (digit) {
      1 => LogicalKeyboardKey.digit1,
      2 => LogicalKeyboardKey.digit2,
      3 => LogicalKeyboardKey.digit3,
      4 => LogicalKeyboardKey.digit4,
      5 => LogicalKeyboardKey.digit5,
      6 => LogicalKeyboardKey.digit6,
      7 => LogicalKeyboardKey.digit7,
      8 => LogicalKeyboardKey.digit8,
      9 => LogicalKeyboardKey.digit9,
      _ => null,
    };
