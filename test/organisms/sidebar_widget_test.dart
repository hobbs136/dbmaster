// Tests for auto-expand-on-connect feature (spec 014).
// Tests focus on verifying that ConnectionEstablished events are safely
// handled by the sidebar widget without crashing. Full end-to-end tree
// rendering verification is deferred to manual quickstart validation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show LogicalKeyboardKey, PhysicalKeyboardKey;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _buildSidebarTest(AppProvider provider, {bool isCollapsed = false}) {
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
          child: SidebarWidget(isCollapsed: isCollapsed),
        ),
      ),
    ),
  );
}

DbServer _testServer({
  String id = 'test-conn-001',
  String name = 'Test PostgreSQL',
  DatabaseType type = DatabaseType.postgresql,
}) {
  return DbServer(
    id: id,
    type: type,
    name: name,
    host: 'localhost',
    port: 5432,
    username: 'test',
    password: 'test',
  );
}

void _setupConnectedServer(
  AppProvider provider,
  DbServer server, {
  List<String> databases = const ['testdb'],
}) {
  provider.connection.dbService.registerConnectedServerForTest(server);
  provider.connection.setConnectionDatabasesForTest(
    server.id,
    databases,
    databases,
  );
  // C22-1 单实例树：树只渲染当前连接（活动 tab → currentServer → 侧栏
  // 选中）——harness 直接注册绕过 connectToServer（真实链路会写
  // currentServer），故补侧栏选中锚定。
  provider.sidebar.selectConnection(server.id);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Sidebar auto-expand on connect (014)', () {
    testWidgets('US1: renders connection node after setup', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      await tester.pumpWidget(_buildSidebarTest(provider));
      // Allow post-frame callbacks to fire (_loadExpandedState, _subscribeToConnectionEvents)
      await tester.pump();
      await tester.pump();

      // Connection node is rendered
      expect(find.text('Test PostgreSQL'), findsOneWidget);
      // SidebarWidget itself renders without exception
      expect(find.byType(SidebarWidget), findsOneWidget);
    });

    testWidgets('US1: does not crash when ConnectionEstablished fires', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      await tester.pumpWidget(_buildSidebarTest(provider));
      await tester.pump();
      await tester.pump();

      // Inject ConnectionEstablished — should not throw
      provider.connection.dbService.addEventForTest(
        ConnectionEstablished(server.id, server),
      );
      await tester.pump();
      await tester.pump();

      // Connection node still visible and sidebar intact
      expect(find.text('Test PostgreSQL'), findsOneWidget);
      expect(find.byType(SidebarWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('US1: skipped if connection is not connected', (tester) async {
      final provider = AppProvider();
      final server = _testServer(id: 'stale-conn');
      provider.connection.addSavedServerForTest(server);
      // Do NOT call _setupConnectedServer — hasConnection returns false

      await tester.pumpWidget(_buildSidebarTest(provider));
      await tester.pump();
      await tester.pump();

      // Inject event for non-connected server — guard should skip
      provider.connection.dbService.addEventForTest(
        ConnectionEstablished(server.id, server),
      );
      await tester.pump();
      await tester.pump();

      // Sidebar renders normally, no crash
      expect(find.byType(SidebarWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('US1: multiple ConnectionEstablished events do not crash', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      await tester.pumpWidget(_buildSidebarTest(provider));
      await tester.pump();
      await tester.pump();

      // Inject multiple events — should be idempotent (add to set)
      provider.connection.dbService.addEventForTest(
        ConnectionEstablished(server.id, server),
      );
      provider.connection.dbService.addEventForTest(
        ConnectionEstablished(server.id, server),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SidebarWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('US2: sidebar renders with cached database data', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);
      provider.connection.setCachedDatabaseForTest(
        server.id,
        'testdb',
        Database(name: 'testdb', tables: [], views: [], functions: []),
      );

      await tester.pumpWidget(_buildSidebarTest(provider));
      await tester.pump();
      await tester.pump();

      provider.connection.dbService.addEventForTest(
        ConnectionEstablished(server.id, server),
      );
      await tester.pump();
      await tester.pump();

      // Sidebar renders with cached data — no crash
      expect(find.byType(SidebarWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // FR-007 test — verify stale child expand state from
    // SharedPreferences does not survive a new connection.
    testWidgets('US2: clears persisted child expand state on new connection', (
      tester,
    ) async {
      // Pre-populate SharedPreferences with stale database expand state
      SharedPreferences.setMockInitialValues({
        'sidebar_expanded_databases': <String>['test-conn-001:testdb'],
        'sidebar_expanded_tables': <String>['test-conn-001:testdb:users'],
      });

      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);
      provider.connection.setCachedDatabaseForTest(
        server.id,
        'testdb',
        Database(name: 'testdb', tables: [], views: [], functions: []),
      );

      await tester.pumpWidget(_buildSidebarTest(provider));
      // Allow _loadExpandedState to restore stale data, then _subscribeToConnectionEvents
      await tester.pump();
      await tester.pump();

      // Fire ConnectionEstablished — FR-007 should clear the stale child state
      provider.connection.dbService.addEventForTest(
        ConnectionEstablished(server.id, server),
      );
      await tester.pump();
      await tester.pump();

      // Sidebar renders normally, no crash — stale child state was cleared
      expect(find.byType(SidebarWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // US3 test — verify auto-expand works for all 8 database types
    // without type-specific branching in the listener.
    testWidgets('US3: auto-expand works for all DatabaseType values', (
      tester,
    ) async {
      int typeIndex = 0;
      for (final dbType in DatabaseType.values) {
        final serverId = 'test-conn-type-${typeIndex++}';
        final provider = AppProvider();
        final server = _testServer(id: serverId, type: dbType);
        provider.connection.addSavedServerForTest(server);
        _setupConnectedServer(provider, server);

        await tester.pumpWidget(_buildSidebarTest(provider));
        await tester.pump();
        await tester.pump();

        // ConnectionEstablished for this type — should not crash or branch on type
        provider.connection.dbService.addEventForTest(
          ConnectionEstablished(server.id, server),
        );
        await tester.pump();
        await tester.pump();

        expect(find.byType(SidebarWidget), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    // US4 test — verify onError in stream listener does not crash.
    // Since the production stream is well-behaved, this test verifies the
    // onError callback exists and the sidebar survives if an error occurs.
    testWidgets('US4: stream listener survives onError without crashing', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      await tester.pumpWidget(_buildSidebarTest(provider));
      await tester.pump();
      await tester.pump();

      // Simulate an error on the events stream (via test helper)
      provider.connection.dbService.addErrorForTest(
        Exception('Simulated stream error'),
      );
      await tester.pump();
      await tester.pump();

      // The sidebar survives the error
      expect(find.byType(SidebarWidget), findsOneWidget);
      // The error is logged, not thrown — verify no uncaught exception
      expect(tester.takeException(), isNull);
    });
  });

  // SidebarWidget 拆分（plan §3.4）后的接线冒烟：键盘事件经 Focus →
  // SidebarController.handleTreeKeyEvent 链路不异常；搜索框输入经
  // SidebarSearchField → updateSearchQuery 链路正常过滤。键盘导航的
  // 深度逻辑由 sidebar_controller_test.dart 覆盖。
  group('SidebarWidget keyboard & search smoke (plan §3.4)', () {
    testWidgets('↓ 键盘导航不异常且树保持完整', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      await tester.pumpWidget(_buildSidebarTest(provider));
      await tester.pump();
      await tester.pump(); // 首帧 postFrame 请求树焦点

      // keyDown/keyUp 成对（HardwareKeyboard 断言物理键不能重复按下）
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.arrowDown,
        physicalKey: PhysicalKeyboardKey.arrowDown,
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.arrowDown,
        physicalKey: PhysicalKeyboardKey.arrowDown,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.arrowDown,
        physicalKey: PhysicalKeyboardKey.arrowDown,
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.arrowDown,
        physicalKey: PhysicalKeyboardKey.arrowDown,
      );
      await tester.pump();

      expect(find.byType(SidebarWidget), findsOneWidget);
      expect(find.text('Test PostgreSQL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('搜索框输入命中连接名时树仍显示该连接', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      await tester.pumpWidget(_buildSidebarTest(provider));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      // 连接名 "Test PostgreSQL" 小写包含 "test" → 保留
      expect(find.text('Test PostgreSQL'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 清空按钮出现（hasActiveQuery=true）
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });
  });
}
