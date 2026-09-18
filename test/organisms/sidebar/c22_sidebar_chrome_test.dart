// C22-0 · 侧边栏 chrome 换装专项测试。
//
// 覆盖面：
// - SEL-C22：顶部连接选择器（当前连接名+地址显示 / 空态占位+管理入口 /
//   菜单列出全部连接 / 未连接项走 onConnectionTap 注入流程）；
// - SEC-C22：SidebarSection 统一 section 头（默认展开 / 点击折叠再展开 /
//   计数徽章 / trailing 动作）；
// - SBAR-C22：SidebarWidget 换装冒烟（品牌字标 + 选择器接线 + 折叠 rail
//   展开/设置按钮图标存在）。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_connection_selector.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_footer.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_section.dart';
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

DbServer _server({
  String id = 'sel-conn-001',
  String name = 'Prod MySQL',
  DatabaseType type = DatabaseType.mysql,
  String host = '192.0.2.128',
  int port = 3306,
}) {
  return DbServer(
    id: id,
    type: type,
    name: name,
    host: host,
    port: port,
    username: 'root',
    password: 'x',
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SEL-C22 · SidebarConnectionSelector', () {
    testWidgets('显示当前连接名 + 地址（选中态回退源）', (tester) async {
      final provider = AppProvider();
      final server = _server();
      provider.connection.addSavedServerForTest(server);
      provider.sidebar.selectConnection(server.id);

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarConnectionSelector(
            onManageConnections: () {},
          ),
        ),
      );

      expect(find.text('Prod MySQL - 192.0.2.128:3306'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronsUpDown), findsOneWidget);
    });

    testWidgets('SQLite 地址不拼端口（host 承载文件路径）', (tester) async {
      final provider = AppProvider();
      final server = _server(
        name: 'Local DB',
        type: DatabaseType.sqlite,
        host: 'C:/data/chinook.sqlite',
        port: 0,
      );
      provider.connection.addSavedServerForTest(server);
      provider.sidebar.selectConnection(server.id);

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarConnectionSelector(
            onManageConnections: () {},
          ),
        ),
      );

      expect(
        find.text('Local DB - C:/data/chinook.sqlite'),
        findsOneWidget,
      );
    });

    testWidgets('无已保存连接：占位按钮点击打开管理器', (tester) async {
      final provider = AppProvider();
      var manageCalled = false;

      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarConnectionSelector(
            onManageConnections: () => manageCalled = true,
          ),
        ),
      );

      expect(find.text('No connection'), findsOneWidget);
      await tester.tap(find.text('No connection'));
      await tester.pump();
      expect(manageCalled, isTrue);
    });

    testWidgets('菜单列出全部连接 + 管理入口；未连接项走注入流程', (tester) async {
      final provider = AppProvider();
      final connected = _server(id: 'c1', name: 'Connected One');
      final offline = _server(id: 'c2', name: 'Offline Two');
      provider.connection.addSavedServerForTest(connected);
      provider.connection.addSavedServerForTest(offline);
      provider.connection.dbService.registerConnectedServerForTest(connected);
      provider.sidebar.selectConnection('c1');

      DbServer? tapped;
      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarConnectionSelector(
            onConnectionTap: (s) async => tapped = s,
            onManageConnections: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.chevronsUpDown));
      await tester.pumpAndSettle();

      expect(find.text('Connected One'), findsOneWidget);
      expect(find.text('Offline Two'), findsOneWidget);
      expect(find.text('Manage Connections…'), findsOneWidget);

      // 未连接项 → 注入的连接流程（密码弹窗等副作用留在宿主）
      await tester.tap(find.text('Offline Two'));
      await tester.pumpAndSettle();
      expect(tapped?.id, 'c2');
    });

    testWidgets('空态菜单入口可打开管理器（列表非空路径）', (tester) async {
      final provider = AppProvider();
      final server = _server();
      provider.connection.addSavedServerForTest(server);

      var manageCalled = false;
      await tester.pumpWidget(
        _buildTestApp(
          provider,
          child: SidebarConnectionSelector(
            onManageConnections: () => manageCalled = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.chevronsUpDown));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage Connections…'));
      await tester.pumpAndSettle();
      expect(manageCalled, isTrue);
    });
  });

  group('SEC-C22 · SidebarSection', () {
    testWidgets('默认展开；点击头折叠再展开；计数徽章与 trailing 动作', (
      tester,
    ) async {
      var trailingTapped = false;
      await tester.pumpWidget(
        _buildTestApp(
          AppProvider(),
          child: ListView(
            children: [
              SidebarSection(
                icon: LucideIcons.star,
                label: 'Favorites',
                count: 2,
                trailing: InkWell(
                  onTap: () => trailingTapped = true,
                  child: const Icon(LucideIcons.eraser, size: 13),
                ),
                children: const [
                  Text('child-row-1'),
                  Text('child-row-2'),
                ],
              ),
            ],
          ),
        ),
      );

      expect(find.text('child-row-1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // trailing 动作不冒泡为折叠
      await tester.tap(find.byIcon(LucideIcons.eraser));
      await tester.pump();
      expect(trailingTapped, isTrue);
      expect(find.text('child-row-1'), findsOneWidget);

      // 头部点击折叠 / 再展开
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('child-row-1'), findsNothing);

      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(find.text('child-row-1'), findsOneWidget);
    });
  });

  group('SBAR-C22 · SidebarWidget 换装冒烟', () {
    testWidgets('展开态：品牌字标 + 连接选择器接线 + footer 状态行', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _server(name: 'Smoke MySQL');
      provider.connection.addSavedServerForTest(server);
      provider.connection.dbService.registerConnectedServerForTest(server);
      provider.sidebar.selectConnection(server.id);

      await tester.pumpWidget(
        _buildTestApp(provider, child: SidebarWidget()),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('DbMaster'), findsOneWidget);
      expect(
        find.text('Smoke MySQL - 192.0.2.128:3306'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(SidebarFooter), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('折叠态：展开按钮 + 连接类型图标 rail', (tester) async {
      final provider = AppProvider();
      final server = _server(name: 'Rail MySQL');
      provider.connection.addSavedServerForTest(server);
      provider.connection.dbService.registerConnectedServerForTest(server);
      provider.sidebar.selectConnection(server.id);

      await tester.pumpWidget(
        _buildTestApp(provider, child: const SidebarWidget(isCollapsed: true)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(LucideIcons.panelLeftOpen), findsOneWidget);
      expect(find.byIcon(LucideIcons.settings), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
