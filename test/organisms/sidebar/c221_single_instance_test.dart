// C22-1 · 单实例专注树 + AppHeader 下掉迁置 专项测试。
//
// 覆盖面：
// - SST-C22：单实例树（只渲染当前连接 / 切换选中即换树 / 无当前提示）；
// - SEL-C22-G：选择器下拉按组分区（组头 + 成员 + 孤儿组回退）；
// - FTR-C22：footer 全局动作行（AI/主题/设置，AppHeader 下掉后迁入）；
// - BRC-C22：BreadcrumbBar 已于 C21 M3 退役（连接/库并入工具栏右端上下文
//   芯片、命令面板入口随迁——覆盖见 query_editor_toolbar_test TRB-C21-005/006）。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/organisms/sidebar/sidebar_connection_selector.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_footer.dart';
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

  group('SST-C22 · 单实例专注树', () {
    testWidgets('多连接并存：树只渲染当前连接，切换选中即换树', (tester) async {
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

      expect(find.text('Connection Alpha'), findsOneWidget);
      expect(find.text('Connection Beta'), findsNothing);

      // 切选中 → 树换成 B
      provider.sidebar.selectConnection('conn-b');
      await tester.pump();
      await tester.pump();
      expect(find.text('Connection Beta'), findsOneWidget);
      expect(find.text('Connection Alpha'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('回归：开着 A 连接的 tab 时切换 B，树跟 currentServer 走', (
      tester,
    ) async {
      // 2026-08-20 走查反馈：切换 PG 浏览表数据（开 tab）后切 MySQL，
      // 树不切换——根因 = resolver 曾把活动 tab 排在 currentServer 前，
      // tab 恒属旧连接导致切换永远被抢回。守卫：currentServer 优先。
      final provider = AppProvider();
      final a = _server('conn-a', 'Connection Alpha');
      final b = _server('conn-b', 'Connection Beta');
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a);
      _connectForTest(provider, b);

      // 用户流程：连 A → 浏览表数据（开 A 的查询 tab）→ 选择器切 B。
      // switchToConnection/openQueryTab 真链路含真库 IO（测试库不可达会
      // hang），用 setCurrentServerForTest + 同步 TabProvider.addTab 模拟
      // 「切换成功后 currentServer=B、活动 tab 属 A」的冲突状态。
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

      // 树根必须显示 B（currentServer），而非 tab 所属的 A
      expect(find.text('Connection Beta'), findsOneWidget);
      expect(find.text('Connection Alpha'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('有连接但无当前锚定：显示选择器引导提示', (tester) async {
      final provider = AppProvider();
      provider.connection.addSavedServerForTest(
        _server('conn-a', 'Connection Alpha'),
      );

      await tester.pumpWidget(_buildTestApp(provider, child: SidebarWidget()));
      await tester.pump();
      await tester.pump();

      expect(find.text('Select a connection from the picker above to start'), findsOneWidget);
      expect(find.text('Connection Alpha'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('SEL-C22-G · 选择器下拉按组分区', () {
    testWidgets('未分组在前，分组以组头分区展示', (tester) async {
      final provider = AppProvider();
      await provider.addConnectionGroup(
        ConnectionGroup(id: 'g1', name: 'Production'),
      );
      provider.connection.addSavedServerForTest(
        _server('c1', 'Ungrouped One'),
      );
      provider.connection.addSavedServerForTest(
        _server('c2', 'Grouped Two', groupId: 'g1'),
      );
      provider.connection.addSavedServerForTest(
        _server('c3', 'Orphan Three', groupId: 'deleted-group'),
      );
      provider.sidebar.selectConnection('c1');

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarConnectionSelector(
            onManageConnections: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.chevronsUpDown));
      await tester.pumpAndSettle();

      expect(find.text('Production'), findsOneWidget); // 组头
      expect(find.text('Ungrouped One'), findsOneWidget);
      expect(find.text('Grouped Two'), findsOneWidget);
      expect(find.text('Orphan Three'), findsOneWidget); // 孤儿回退未分组
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

    testWidgets('AI 按钮点击切换 aiPanelOpen（激活高亮）', (tester) async {
      final provider = AppProvider();

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarFooter(onShowSettings: () {}),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.sparkles));
      await tester.pump();
      expect(provider.aiPanelOpen, isTrue);
    });
  });
}
