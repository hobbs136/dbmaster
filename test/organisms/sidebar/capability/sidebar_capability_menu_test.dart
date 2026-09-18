// C14 · 侧边栏能力菜单 widget 测试：渲染 / port 门控 / 徽章 / 折叠 /
// 激活动作（AI 面板）/ 活动连接锚定（currentServer 优先 + 回退）。
//
// 用例登记：「侧边栏能力菜单（CAP-MENU）」。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/capability/sidebar_capability_menu.dart';
import 'package:dbmaster/plugins/bootstrap.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

DbServer _server(DatabaseType type) => DbServer(
      id: 'conn-${type.name}',
      type: type,
      name: 'Test ${type.name}',
      host: 'localhost',
      port: 3306,
      username: 'u',
      password: 'p',
    );

Widget _host(AppProvider provider) => MaterialApp(
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
        child: const Scaffold(
          body: SizedBox(
            width: 260,
            height: 800,
            child: SidebarCapabilityMenu(),
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() {
    // widget 经全局默认注册表取插件——注册表创建即含默认件（C15 起自注册，
    // 见 bootstrap.dart），无需也不可重复注册。
  });

  testWidgets('无活动连接 → 整段隐藏', (tester) async {
    final provider = AppProvider();
    await tester.pumpWidget(_host(provider));
    await tester.pump();

    expect(find.text('Capabilities'), findsNothing);
  });

  testWidgets('回退锚定：选中节点未连接 → 仍隐藏（动作假定活连接）', (tester) async {
    final provider = AppProvider();
    final server = _server(DatabaseType.mysql);
    provider.connection.addSavedServerForTest(server);
    provider.sidebar.selectConnection(server.id);

    await tester.pumpWidget(_host(provider));
    await tester.pump();

    expect(find.text('Capabilities'), findsNothing);
  });

  testWidgets('mysql：分组 + 项 + core 徽章 + AI 高亮渲染', (tester) async {
    final provider = AppProvider();
    provider.connection.setCurrentServer(_server(DatabaseType.mysql));
    await tester.pumpWidget(_host(provider));
    await tester.pump();

    expect(find.text('Capabilities'), findsOneWidget);
    expect(find.text('DATABASE OBJECTS'), findsOneWidget);
    expect(find.text('ADVANCED'), findsOneWidget);
    expect(find.text('Stored Procedures'), findsOneWidget);
    expect(find.text('Functions'), findsOneWidget);
    expect(find.text('Triggers'), findsOneWidget);
    expect(find.text('Schema Diff & Sync'), findsOneWidget);
    expect(find.text('AI Assistant'), findsOneWidget);
    // 来源徽章：core 件全 core 徽章（ai.assistant 位恒真但来源是 core 插件）
    expect(find.text('core'), findsNWidgets(5));
  });

  testWidgets('redis：无 proc/func/trigger 位 → 对象组整组隐藏', (tester) async {
    final provider = AppProvider();
    provider.connection.setCurrentServer(_server(DatabaseType.redis));
    await tester.pumpWidget(_host(provider));
    await tester.pump();

    expect(find.text('Capabilities'), findsOneWidget);
    expect(find.text('DATABASE OBJECTS'), findsNothing);
    expect(find.text('Stored Procedures'), findsNothing);
    expect(find.text('Schema Diff & Sync'), findsOneWidget);
    expect(find.text('AI Assistant'), findsOneWidget);
  });

  testWidgets('点击 AI Assistant → 激活 onActivate（切换 AI 面板）', (tester) async {
    final provider = AppProvider();
    provider.connection.setCurrentServer(_server(DatabaseType.mysql));
    await tester.pumpWidget(_host(provider));
    await tester.pump();

    expect(provider.aiPanel.aiPanelOpen, isFalse);
    await tester.tap(find.text('AI Assistant'));
    await tester.pump();
    expect(provider.aiPanel.aiPanelOpen, isTrue);
  });

  testWidgets('折叠：点头部隐藏项、保留段头', (tester) async {
    final provider = AppProvider();
    provider.connection.setCurrentServer(_server(DatabaseType.mysql));
    await tester.pumpWidget(_host(provider));
    await tester.pump();

    await tester.tap(find.text('Capabilities'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Capabilities'), findsOneWidget);
    expect(find.text('Stored Procedures'), findsNothing);
    expect(find.text('AI Assistant'), findsNothing);
  });
}
