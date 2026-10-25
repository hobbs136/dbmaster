// C22-1 → J3 多连接长驻树 专项测试（T26 重写为多连接口径）。
//
// 覆盖面：
// - MTREE-J3：多连接长驻树（全部连接根常驻同树、活动根高亮跟随活动
//   上下文连接、无当前锚定不空态闪变）；
// - FTR-C22：footer 全局动作行（AI/主题/设置，AppHeader 下掉后迁入）；
// - BRC-C22：BreadcrumbBar 已于 C21 M3 退役（覆盖见 query_editor_toolbar
//   测试 TRB-C21-005/006）。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/organisms/sidebar/sidebar_footer.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_tree.dart';
import 'package:dbmaster/organisms/sidebar/tree_item.dart';
import 'package:dbmaster/organisms/sidebar_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

Widget _buildTestApp(
  AppProvider provider, {
  Widget? child,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('zh')],
    locale: const Locale('en'),
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider()..load(),
        ),
        ChangeNotifierProvider<ServerConnectionProvider>(
          create: (_) => ServerConnectionProvider(),
        ),
      ],
      child: Scaffold(
        body: SizedBox(
          width: 400,
          height: 800,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

DbServer _server(
  String id,
  String name, {
  DatabaseType type = DatabaseType.mysql,
  String? groupId,
}) {
  return DbServer(
    id: id,
    type: type,
    name: name,
    host: '192.0.2.128',
    port: 3306,
    username: 'root',
    password: 'x',
    groupId: groupId,
  );
}

void _connectForTest(AppProvider provider, DbServer server) {
  provider.connection.dbService.registerConnectedServerForTest(server);
  provider.connection.setConnectionDatabasesForTest(
    server.id,
    ['db_a'],
    ['db_a'],
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MTREE-J3 · 多连接长驻树', () {
    testWidgets('多连接并存：全部连接根节点同树常驻，侧栏选中不再换树', (tester) async {
      final provider = AppProvider();
      final a = _server('conn-a', 'Connection Alpha');
      final b = _server('conn-b', 'Connection Beta');
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a);
      _connectForTest(provider, b);
      provider.sidebar.selectConnection('conn-a');

      await tester.pumpWidget(_buildTestApp(provider, child: SidebarWidget()));
      await tester.pump();
      await tester.pump();

      // 两连接根同时可见（J3：无需切换，树本身即导航）
      expect(find.text('Connection Alpha'), findsOneWidget);
      expect(find.text('Connection Beta'), findsOneWidget);

      // 切侧栏选中 → 树仍双根常驻（不再「切换即换树」）
      provider.sidebar.selectConnection('conn-b');
      await tester.pump();
      await tester.pump();
      expect(find.text('Connection Alpha'), findsOneWidget);
      expect(find.text('Connection Beta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('活动根高亮跟随活动上下文连接（活动 tab 优先于 currentServer）', (tester) async {
      // J3 序位口径（plan §10.1①④）：SST-C22-003 守卫前提（「开着旧连接
      // tab 时经选择器切换」）随切换入口删除而消亡——活动上下文 = 活动
      // tab 的连接 → currentServer → 侧栏选中（T25 activeContextConnection）。
      // 树根高亮跟随该锚点：开着 A 的 tab 时 currentServer=B，高亮在 A。
      final provider = AppProvider();
      final a = _server('conn-a', 'Connection Alpha');
      final b = _server('conn-b', 'Connection Beta');
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a);
      _connectForTest(provider, b);

      // 用户流程：连 A → 浏览表数据（开 A 的查询 tab）→ 连 B（currentServer
      // =B）。switchToConnection 真链路含真库 IO，用 setCurrentServerForTest
      // + 同步 TabProvider.addTab 模拟「currentServer=B、活动 tab 属 A」。
      provider.connection.setCurrentServerForTest(a);
      provider.tab.addTab(
        QueryTab(
          id: 'tab-1',
          title: 'users',
          sql: 'SELECT * FROM users',
          connectionId: 'conn-a',
          databaseName: 'db_a',
          isAutoTitle: true,
        ),
      );
      provider.connection.setCurrentServerForTest(b);

      await tester.pumpWidget(_buildTestApp(provider, child: SidebarWidget()));
      await tester.pump();
      await tester.pump();

      // 双根常驻 + 活动根 = A（活动 tab 所属），非 currentServer 的 B。
      // 文本断言按树根行（TreeItem）收窄：Q1 能力菜单 header 现渲染锚定
      // 连接名，本用例锚定回退 currentServer=B 时面板 header 出现第二个
      // 同文本——本断言对象是树根行本身，菜单渲染不在本用例语义内。
      expect(
        find.byWidgetPredicate(
          (w) => w is TreeItem && w.label == 'Connection Beta',
        ),
        findsOneWidget,
      );
      expect(find.text('Connection Alpha'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is TreeItem && w.isSelected && w.label == 'Connection Alpha',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is TreeItem && w.isSelected && w.label == 'Connection Beta',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('有连接但无任何锚定：树仍全根节点，无空态闪变', (tester) async {
      final provider = AppProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'Connection Alpha'),
      );

      await tester.pumpWidget(_buildTestApp(provider, child: SidebarWidget()));
      await tester.pump();
      await tester.pump();

      // 旧「选择器引导提示」态随多连接树消亡（_buildNoCurrentHint 移除）
      expect(
        find.text('Select a connection from the picker above to start'),
        findsNothing,
      );
      expect(find.text('Connection Alpha'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('FTR-C22 · footer 全局动作行', () {
    testWidgets('AI/主题/设置三键就位；设置走注入回调', (tester) async {
      final provider = AppProvider();
      var settingsCalled = false;

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarFooter(onShowSettings: () => settingsCalled = true),
        ),
      );

      expect(find.byIcon(LucideIcons.sparkles), findsOneWidget);
      expect(find.byIcon(LucideIcons.settings), findsOneWidget);
      // 主题按钮（暗色主题下显示 sun）
      expect(find.byIcon(LucideIcons.sun), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.settings));
      await tester.pump();
      expect(settingsCalled, isTrue);
    });

    testWidgets('AI 键 = 经典 dock 开合（非全屏；tooltip；再点关闭）', (tester) async {
      final provider = AppProvider();

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarFooter(onShowSettings: () {}),
        ),
      );

      // tooltip 口径：开合经典 dock（aiAssistantOpenTooltip），非进入工作台。
      expect(
        find.byTooltip(AppLocalizationsEn().aiAssistantOpenTooltip),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(LucideIcons.sparkles));
      await tester.pump();
      expect(provider.aiPanelOpen, isTrue, reason: '第一击打开经典 dock');
      expect(
        provider.aiPanelFullscreen,
        isFalse,
        reason: 'footer 键不再进入工作台（全屏）',
      );

      await tester.tap(find.byIcon(LucideIcons.sparkles));
      await tester.pump();
      expect(provider.aiPanelOpen, isFalse, reason: '再点关闭 dock');
    });

    testWidgets('工作台入口不受影响：toggleAiPanelFullscreen 后仍进全屏', (tester) async {
      final provider = AppProvider();

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarFooter(onShowSettings: () {}),
        ),
      );

      provider.toggleAiPanel();
      provider.toggleAiPanelFullscreen();
      await tester.pump();
      expect(provider.aiPanelFullscreen, isTrue);
      expect(provider.aiPanelOpen, isTrue);
    });
  });
}
