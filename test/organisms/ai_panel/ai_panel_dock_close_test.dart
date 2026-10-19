// T1 · dock 形态 AI 面板头部关闭钮单测。
//
// 覆盖：dock 头部 x 关闭钮点击收起面板（provider.aiPanelOpen → false）；
// overlay 形态不渲染该钮（防双关闭钮回归）；maximize 邻钮不回归，
// 且关闭钮不依赖 showSideEntry 条件（宽/窄面均出现）。
// 泵送范式照抄 ai_panel_three_column_test.dart（MultiProvider + Scaffold）。
// 用例登记：docs/test/unified_test_spec.md §6.3（UAI-W-007~009）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppProvider> pumpPanel(
    WidgetTester tester,
    Size surface, {
    bool isOverlay = false,
  }) async {
    final app = AppProvider();
    // 种一条已存连接：header 按钮行只在没有连接空态分支之外渲染。
    app.connection.addSavedServerForTest(
      DbServer(
        id: 'c1',
        name: 'Local MySQL',
        type: DatabaseType.mysql,
        host: '192.0.2.128',
        port: 3306,
      ),
    );
    final layout = LayoutPreferencesProvider();
    await layout.load();

    await tester.binding.setSurfaceSize(surface);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layout,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(body: AiPanelWidget(isOverlay: isOverlay)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('UAI-W-007 dock 头部关闭钮：点击收起面板', (tester) async {
    final app = await pumpPanel(tester, const Size(400, 800));
    // 前置：面板处于打开态（dock 可见）。
    app.aiPanel.setAiPanelOpen(true);
    await tester.pumpAndSettle();

    final closeButton = find.widgetWithIcon(IconButton, LucideIcons.x);
    expect(closeButton, findsOneWidget, reason: 'dock 头部存在关闭钮');

    await tester.tap(closeButton);
    await tester.pumpAndSettle();

    expect(
      app.aiPanel.aiPanelOpen,
      isFalse,
      reason: '关闭钮点击后面板收起（closeAiPanel 幂等收起）',
    );
  });

  testWidgets('UAI-W-008 overlay 形态：面板自身不渲染关闭钮（防双关闭钮）',
      (tester) async {
    await pumpPanel(tester, const Size(400, 800), isOverlay: true);

    expect(
      find.byIcon(LucideIcons.x),
      findsNothing,
      reason: 'overlay 面板不渲染关闭钮（工具栏关闭钮归 overlay 组件自身）',
    );
  });

  testWidgets('UAI-W-009 dock 邻钮不回归：maximize 存在 + 宽面关闭钮仍在',
      (tester) async {
    // 宽面（showSideEntry=false）：关闭钮不依赖 showSideEntry 条件。
    await pumpPanel(tester, const Size(1000, 800));

    expect(
      find.byIcon(LucideIcons.maximize),
      findsOneWidget,
      reason: 'maximize 邻钮不回归',
    );
    expect(
      find.widgetWithIcon(IconButton, LucideIcons.x),
      findsOneWidget,
      reason: '宽面（showSideEntry=false）关闭钮仍出现',
    );
  });
}
