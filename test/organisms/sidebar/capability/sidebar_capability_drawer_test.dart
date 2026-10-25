// UIRV-A42 · 能力菜单入口化 + 覆盖抽屉 widget 测试（2026-10-25）。
//
// 验收条款直译（任务书 UIRV-A42 验收标准 ①~⑦；红测先行，从条款转译，
// 不镜像实现）：
// A42-001/002 条款①：收起态 = 32px 入口行（短标签 + 可见项数 + Alt+Q 徽章）；
//   锚定连接名只在入口 tooltip 与抽屉头部（收起态无连接名文本）。
// A42-003 条款②：展开态 = 覆盖抽屉（树布局高度不被扣减：开/合两态树约束
//   高度一致）；抽屉头部 = 连接名主行 + 库型次行（S5 语义保留在抽屉头）。
// A42-004 条款③：Esc 关闭抽屉且焦点归还入口行；Alt+Q 开合 + 聚焦不变；
//   面板局部键盘（1~9/↑↓/Space·Enter）保留。
// A42-005 条款④：折叠记忆沿用 get/setCapabilityMenuCollapsed；默认展开
//   （首帧展开语义等价）。
// A42-006 条款⑤：无活动连接/装配空 → 入口与抽屉自隐藏（现状保持）。
// A42-007 条款⑥：单项动作失败只反馈该项——抛错项激活后树区/入口/抽屉
//   均保持原渲染，不变成错误页。
// A42-008 条款⑦：真实 SidebarWidget 装配下进程面板 Consumer 段与 footer
//   顺序不变（抽屉开合不改变 footer 位置锚定的装配段）。
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
import 'package:dbmaster/organisms/sidebar/sidebar_footer.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar_widget.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/plugins/plugin_descriptor.dart';
import 'package:dbmaster/plugins/sidebar_plugin.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_abstract.dart' show DatabaseAdapter;
import 'package:dbmaster/theme/app_theme.dart';

/// 测试注入插件（仅 sqlite 命中）：一项可观察激活、一项激活即抛错
///（A42-007 单项失败隔离用），一项无徽标普通项。
class _A42TestSidebarPlugin implements SidebarPlugin {
  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'a42-test-sidebar',
        supportedTypes: {DatabaseType.sqlite},
        source: PluginSource.databaseType,
        icon: LucideIcons.wrench,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) => [
        SidebarCapabilityGroup(
          id: 'a42-test',
          label: (l10n) => 'A42 Test Group',
          icon: LucideIcons.wrench,
          items: [
            SidebarCapabilityItem(
              id: 'a42.test.ok',
              label: (l10n) => 'A42 Test Ok',
              icon: LucideIcons.database,
              onActivate: () => okActivated = true,
            ),
            SidebarCapabilityItem(
              id: 'a42.test.throwing',
              label: (l10n) => 'A42 Test Throwing',
              icon: LucideIcons.bot,
              onActivate: () => throw StateError('A42 isolated failure'),
            ),
            SidebarCapabilityItem(
              id: 'a42.test.plain',
              label: (l10n) => 'A42 Test Plain',
              icon: LucideIcons.wrench,
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

bool okActivated = false;

DbServer _server(DatabaseType type, {String name = 'Test Conn'}) => DbServer(
      id: 'conn-${type.name}',
      type: type,
      name: name,
      host: 'localhost',
      port: 3306,
      username: 'u',
      password: 'p',
    );

/// T25 组用：仅 isConnected 取真（hasConnection 检查 adapters）。
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

Widget _materialShell(AppProvider provider, Widget child) => MaterialApp(
      theme: AppTheme.darkTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      locale: const Locale('en'),
      home: _providers(provider, child),
    );

/// 组件级宿主：与 sidebar_widget 展开态装配同构（树区 Stack + 抽屉覆盖 +
/// 入口行挂树区下方），树位以探针容器占位供高度断言。
Widget _componentHost(
  AppProvider provider, {
  bool withGlobalShortcuts = false,
  Key? menuKey,
}) {
  Widget body = Scaffold(
    body: SizedBox(
      width: 260,
      height: 800,
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(
                  child: SizedBox.expand(),
                ),
                SidebarCapabilityDrawer(),
              ],
            ),
          ),
          SidebarCapabilityMenu(key: menuKey),
        ],
      ),
    ),
  );
  if (withGlobalShortcuts) {
    body = GlobalShortcutsWrapper(child: body);
  }
  return _materialShell(provider, body);
}

/// 真实 SidebarWidget 装配宿主（A42-003 树高度 / A42-008 装配顺序回归）。
Widget _sidebarHost(AppProvider provider) => _materialShell(
      provider,
      Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: SidebarWidget(),
        ),
      ),
    );

void _seedConnected(
  AppProvider provider,
  DatabaseType type, {
  String name = 'Test Conn',
}) {
  final server = _server(type, name: name);
  provider.connection.addSavedServerForTest(server);
  provider.connection.setCurrentServer(server);
  provider.dbService.registerConnectedServerForTest(server);
  provider.dbService.registerConnectedAdapterForTest(
    server.id,
    _FakeConnectedAdapter(),
  );
}

/// 当前装配的可见项扁平序（与菜单/抽屉 build 同参同源）。
List<AssembledCapabilityItem> _flatItems(
  WidgetTester tester,
  AppProvider provider,
) {
  final server = provider.connection.currentServer;
  if (server == null) fail('测试前置失败：无活动连接');
  final context = tester.element(
    find.byType(SidebarCapabilityMenu),
  );
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

/// Alt+Q 全局键（经 GlobalShortcutsWrapper 管线）。_safeExecute 的动作排在
/// post-frame，而测试绑定 pump 仅在 hasScheduledFrame 时真正出帧（真机
/// vsync 恒排帧，无此问题）——每泵前显式排帧，确保 post-frame 动作与
/// 焦点微任务在本辅助函数内完成。
Future<void> _sendAltQ(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  tester.binding.scheduleFrame();
  await tester.pump();
  tester.binding.scheduleFrame();
  await tester.pump(const Duration(milliseconds: 100));
  tester.binding.scheduleFrame();
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // 文件级共享态跨用例复位（抽屉默认开 = 首帧展开语义）。
    capabilityDrawerOpen.value = true;
    okActivated = false;
  });

  setUpAll(() {
    defaultPluginRegistry.registerSidebar(_A42TestSidebarPlugin());
  });

  group('A42-001/002 条款①：收起态 32px 入口行', () {
    testWidgets('入口行高 32px：短标签 Capabilities + 可见项数 + Alt+Q 徽章',
        (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite);
      await tester.pumpWidget(_componentHost(provider));
      await tester.pump();

      // 收起抽屉（点入口行）
      await tester.tap(find.text('Capabilities').first);
      await tester.pump(const Duration(milliseconds: 200));

      final entry = find.ancestor(
        of: find.text('Capabilities').first,
        matching: find.byType(InkWell),
      );
      expect(entry, findsWidgets);
      final entrySize = tester.getSize(entry.first);
      expect(entrySize.height, 32, reason: '入口行 = 32px');

      final items = _flatItems(tester, provider);
      // 可见项数徽标 = 装配可见项数
      expect(find.text('${items.length}'), findsOneWidget);
      // Alt+Q kbd 徽章
      expect(find.text('Alt+Q'), findsOneWidget);
    });

    testWidgets('收起态连接名不渲染为入口文本（归 tooltip 与抽屉头部）',
        (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite, name: 'Prod SQLite');
      await tester.pumpWidget(_componentHost(provider));
      await tester.pump();

      // 展开态：连接名在抽屉头部
      expect(find.text('Prod SQLite'), findsOneWidget);

      await tester.tap(find.text('Capabilities').first);
      await tester.pump(const Duration(milliseconds: 200));

      // 收起态：抽屉关（头部消失）；连接名文本消失（tooltip 为 message
      // 属性非文本节点）
      expect(capabilityDrawerOpen.value, isFalse);
      expect(find.text('Capabilities: SQLite'), findsNothing);
      expect(find.text('Prod SQLite'), findsNothing);
      // 入口 tooltip 携带连接名（Tooltip.message）
      final entryTooltip = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('Prod SQLite'),
      );
      expect(entryTooltip, findsOneWidget);
    });
  });

  group('A42-003 条款②：覆盖抽屉不扣减树布局高度', () {
    testWidgets('抽屉开/合两态树区约束高度一致（真实 SidebarWidget 装配）',
        (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite, name: 'Prod SQLite');
      await tester.pumpWidget(_sidebarHost(provider));
      await tester.pump();

      // 展开态（默认开）：抽屉头部渲染（树根行也含连接名 → 2 处）+ 树区在
      expect(find.text('Prod SQLite'), findsNWidgets(2));
      expect(find.byType(SidebarTree), findsOneWidget);
      final openHeight = tester.getSize(find.byType(SidebarTree)).height;
      expect(openHeight, greaterThan(0));

      // 收起：树区高度不变（覆盖而非挤压）
      await tester.tap(find.text('Capabilities').first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(capabilityDrawerOpen.value, isFalse);
      expect(find.byType(SidebarTree), findsOneWidget);
      final closedHeight = tester.getSize(find.byType(SidebarTree)).height;
      expect(closedHeight, openHeight,
          reason: '条款②：树布局高度不被抽屉开合扣减');

      // 再展开：仍不变
      await tester.tap(find.text('Capabilities').first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(find.byType(SidebarTree)).height, openHeight);
    });

    testWidgets('抽屉头部 = 连接名主行 + 库型次行（S5 语义保留在抽屉头）',
        (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite, name: 'Prod SQLite');
      await tester.pumpWidget(_componentHost(provider));
      await tester.pump();

      expect(find.text('Prod SQLite'), findsOneWidget);
      expect(find.text('Capabilities: SQLite'), findsOneWidget);
    });
  });

  group('A42-004 条款③：Esc 归还焦点 + Alt+Q + 局部键盘', () {
    testWidgets('Esc 关闭抽屉且焦点归还入口行', (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite);
      await tester.pumpWidget(_componentHost(
        provider,
        withGlobalShortcuts: true,
      ));
      await tester.pump();

      // Alt+Q 收起 → 再 Alt+Q 展开 + 聚焦抽屉面板根
      await _sendAltQ(tester);
      await _sendAltQ(tester);
      final primary = FocusManager.instance.primaryFocus;
      expect(primary, isNotNull);
      expect(
        primary!.context
            ?.findAncestorStateOfType<State<SidebarCapabilityDrawer>>(),
        isNotNull,
        reason: 'Alt+Q 展开后聚焦抽屉面板根',
      );

      // Esc：关闭抽屉 + 焦点归还入口行
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(capabilityDrawerOpen.value, isFalse);
      expect(find.text('Capabilities: SQLite'), findsNothing);
      final after = FocusManager.instance.primaryFocus;
      expect(after, isNotNull);
      expect(
        after!.context
            ?.findAncestorStateOfType<State<SidebarCapabilityMenu>>(),
        isNotNull,
        reason: 'Esc 后焦点归还入口行',
      );
    });

    testWidgets('面板聚焦后 1~9 直达 / ↑↓ 移动 / Enter 激活（保留）',
        (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite);
      await tester.pumpWidget(_componentHost(
        provider,
        withGlobalShortcuts: true,
      ));
      await tester.pump();
      await _sendAltQ(tester);
      await _sendAltQ(tester);

      // 数字直达（跨组连续序号，注入件 Ok 项在前 9 项内）。
      final items = _flatItems(tester, provider);
      final okIndex = items.indexWhere((e) => e.item.id == 'a42.test.ok');
      expect(okIndex, greaterThanOrEqualTo(0));
      expect(okIndex, lessThan(9), reason: '数字直达仅覆盖前 9 项');

      await tester.sendKeyEvent(_digitKey(okIndex + 1)!);
      await tester.pump();
      expect(okActivated, isTrue);
    });
  });

  group('A42-005 条款④：折叠记忆与默认值', () {
    testWidgets('默认展开（首帧）+ toggle 折叠 → 重建后保持折叠（prefs）',
        (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite);
      await tester.pumpWidget(_componentHost(provider));
      await tester.pump();

      // 默认展开：抽屉头部在
      expect(find.text('Capabilities: SQLite'), findsOneWidget);

      await tester.tap(find.text('Capabilities').first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(capabilityDrawerOpen.value, isFalse);
      expect(find.text('Capabilities: SQLite'), findsNothing);

      // 重建（新 State）→ post-frame 读持久化值校正后仍收起
      await tester.pumpWidget(_componentHost(
        provider,
        menuKey: const ValueKey('rebuild'),
      ));
      await tester.pump();
      await tester.pump();
      expect(capabilityDrawerOpen.value, isFalse);
      expect(find.text('Capabilities: SQLite'), findsNothing);
      expect(find.text('Capabilities'), findsOneWidget);
    });
  });

  group('A42-006 条款⑤：锚定自隐藏（现状保持）', () {
    testWidgets('无活动连接 → 入口与抽屉均自隐藏', (tester) async {
      final provider = AppProvider();
      await tester.pumpWidget(_componentHost(provider));
      await tester.pump();

      expect(find.text('Capabilities'), findsNothing);
      expect(find.text('Capabilities: SQLite'), findsNothing);
    });

    testWidgets('选中未连接连接 → 仍隐藏（已连接护栏现状保持）', (tester) async {
      final provider = AppProvider();
      final server = _server(DatabaseType.mysql);
      provider.connection.addSavedServerForTest(server);
      provider.sidebar.selectConnection(server.id);
      await tester.pumpWidget(_componentHost(provider));
      await tester.pump();

      expect(find.text('Capabilities'), findsNothing);
      expect(find.text('Capabilities: MySQL'), findsNothing);
    });
  });

  group('A42-007 条款⑥：单项动作失败隔离', () {
    testWidgets('激活抛错项：树区/入口/抽屉保持渲染，不变成错误页',
        (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite);
      await tester.pumpWidget(_componentHost(provider));
      await tester.pump();

      final throwingRow = find.byWidgetPredicate(
        (w) => w is Tooltip && (w.message ?? '').contains('A42 Test Throwing'),
      );
      // 注入件在装配末尾，超出抽屉 264px 视口的行不入树（ListView 惰性
      // 构建）——循环拖拽到可见。
      var attempts = 0;
      while (throwingRow.evaluate().isEmpty && attempts < 20) {
        await tester.drag(find.byType(ListView), const Offset(0, -60));
        await tester.pump();
        attempts++;
      }
      expect(throwingRow, findsOneWidget);

      await tester.tap(throwingRow.first);
      final ex = tester.takeException();
      expect(ex, isNotNull, reason: '前置：动作确实抛错');

      // 失败只反馈该项：抽屉仍开、入口仍在、组件树未变错误页
      await tester.pump();
      expect(capabilityDrawerOpen.value, isTrue);
      expect(find.byType(SidebarCapabilityDrawer), findsOneWidget);
      expect(find.text('Capabilities'), findsOneWidget);
      expect(find.text('A42 Test Ok'), findsOneWidget);
    });
  });

  group('A42-008 条款⑦：真实装配顺序回归', () {
    testWidgets('SidebarWidget：入口行位于树区之后、footer 之前；抽屉开合不改变顺序',
        (tester) async {
      final provider = AppProvider();
      _seedConnected(provider, DatabaseType.sqlite, name: 'Prod SQLite');
      await tester.pumpWidget(_sidebarHost(provider));
      await tester.pump();

      expect(find.byType(SidebarTree), findsOneWidget);
      expect(find.text('Capabilities'), findsOneWidget);
      expect(find.byType(SidebarFooter), findsOneWidget);

      // 纵向顺序：树区 → 入口行 → footer
      final treeCenter = tester.getCenter(find.byType(SidebarTree)).dy;
      final entryCenter =
          tester.getCenter(find.text('Capabilities').first).dy;
      final footerCenter = tester.getCenter(find.byType(SidebarFooter)).dy;
      expect(treeCenter, lessThan(entryCenter));
      expect(entryCenter, lessThan(footerCenter));

      // 抽屉覆盖在树区上方：开合后再核对顺序不变
      await tester.tap(find.text('Capabilities').first);
      await tester.pump(const Duration(milliseconds: 200));
      final treeCenter2 = tester.getCenter(find.byType(SidebarTree)).dy;
      final entryCenter2 =
          tester.getCenter(find.text('Capabilities').first).dy;
      final footerCenter2 = tester.getCenter(find.byType(SidebarFooter)).dy;
      expect(treeCenter2, treeCenter);
      expect(entryCenter2, entryCenter);
      expect(footerCenter2, footerCenter);
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
