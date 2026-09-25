// C23 走查反馈修复回归：AI 面板「全屏」应真铺满工作区。
//
// 根因：AiFullscreenOverlay 曾把 aiFullscreen 与 aiAsOverlay 两种形态都
// 渲染成 AiPanelOverlay 浮动窗（默认 65% 视口、可拖拽）——「全屏」名不
// 符实。修复：ai.fs = true → 自撑满真全屏；浮窗仅留给窗口过窄的布局
// 降级（aiAsOverlay && !fs）。
//
// T10（design D1/D2/D4，2026-09-22）：全屏分支由 AiPanelWidget(isFullscreen)
// 改为 AiWorkbenchShell（AI 全屏 = 工作台收敛），并 Offstage+TickerMode
// 常驻保活——退出仅隐藏不销毁（AC1.4：会话/输入草稿/滚动位跨模式存活）。
//
// ⚠ 本文件是层隔离 + 状态预置测试——本 harness 的 Stack(fit: expand)
// 恰好掩盖了「全屏态兄弟层全 shrink → loose Stack 塌 0 宽」的缺陷
// （2026-08-22 用户走查反馈「全屏化直接消失」，曾用 Positioned.fill 时
// 复现）。真实路径回归见 ai_fullscreen_e2e_test.dart（HomeScreen 四层
// Stack + 点按钮交互）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/execution_center_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/screens/home/ai_fullscreen_overlay.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_overlay.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppProvider> pumpLayer(
    WidgetTester tester, {
    required Size surface,
    required bool fullscreen,
    bool openPanel = true,
  }) async {
    final app = AppProvider();
    if (openPanel) app.toggleAiPanel(); // open
    if (fullscreen) app.toggleAiPanelFullscreen();
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
          ChangeNotifierProvider<ExecutionCenterProvider>.value(
            value: ExecutionCenterProvider(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                AiFullscreenOverlay(
                  constraints: BoxConstraints.tight(surface),
                  onToggleFullscreen: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('全屏态：AiWorkbenchShell 直铺整个工作区，无浮动窗', (tester) async {
    await pumpLayer(tester, surface: const Size(1200, 800), fullscreen: true);

    expect(find.byType(AiPanelOverlay), findsNothing, reason: '全屏不再是浮动窗');
    expect(
      find.byType(AiPanelWidget),
      findsNothing,
      reason: '旧「经典面板全屏」形态已退役（D2 收敛为工作台）',
    );
    final shell = find.byType(AiWorkbenchShell);
    expect(shell, findsOneWidget);

    final size = tester.getSize(shell);
    expect(size, const Size(1200, 800), reason: '工作台铺满整个视口');
  });

  testWidgets('非全屏态（fs=false）：工作台隐藏但保活挂载（AC1.4 / D4）', (tester) async {
    await pumpLayer(tester, surface: const Size(1200, 800), fullscreen: false);

    expect(find.byType(AiPanelOverlay), findsNothing);
    expect(
      find.byType(AiWorkbenchShell),
      findsNothing,
      reason: '默认经典：工作台不可见（AC1.1 启动默认经典）',
    );
    expect(
      find.byType(AiWorkbenchShell, skipOffstage: false),
      findsOneWidget,
      reason: 'Offstage 常驻挂载：State 保留（草稿/滚动位不销毁，D4）',
    );
    // fs=false + 宽度充足：aiAsOverlay=false → 浮窗不渲染（面板归停靠侧栏，
    // 由 MainWorkspaceLayer 负责，不在本层）
    expect(find.byType(AiPanelWidget), findsNothing);
  });

  testWidgets('窄窗降级（fs=false + 宽度不足）：渲染浮动窗，行为不变', (tester) async {
    // 800 宽：折叠侧栏(44) + ai 面板(400) 后 356 < 480 → aiAsOverlay
    await pumpLayer(tester, surface: const Size(800, 600), fullscreen: false);

    final overlay = find.byType(AiPanelOverlay);
    expect(overlay, findsOneWidget, reason: '窗口过窄时降级为浮动窗');
    // 浮窗本体（ai_overlay_panel Positioned）是 65% 视口默认尺寸，非铺满
    final panel = find.byKey(const ValueKey('ai_overlay_panel'));
    expect(panel, findsOneWidget);
    final size = tester.getSize(panel);
    expect(size.width < 800, isTrue, reason: '浮动窗默认 65% 视口，非铺满');
  });

  testWidgets('AC1.4：进→发→退→进，输入草稿与滚动位仍在（Offstage 保活）', (tester) async {
    // 预置会话与 30 条消息（足够撑出滚动范围）
    final app = AppProvider();
    app.toggleAiPanel();
    app.toggleAiPanelFullscreen();
    app.aiPanel.ensureSession();
    for (var i = 0; i < 30; i++) {
      app.addAiMessage(
        AiMessage(
          id: 'm$i',
          isUser: i % 2 == 0,
          content: 'message $i',
          timestamp: DateTime.now(),
          type: AiMessageType.chat,
        ),
      );
    }

    final layout = LayoutPreferencesProvider();
    await layout.load();
    const surface = Size(1200, 800);
    await tester.binding.setSurfaceSize(surface);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layout,
          ),
          ChangeNotifierProvider<ExecutionCenterProvider>.value(
            value: ExecutionCenterProvider(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                AiFullscreenOverlay(
                  constraints: BoxConstraints.tight(surface),
                  onToggleFullscreen: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 进入工作台：输入草稿 + 滚动消息流（滚到非底部位置——若 State 被销毁
    // 重建，重建后自动跟随会滚回底部，本断言即失守）。直接驱动控制器：
    // 消息气泡内含 SelectableText 会吃掉手势 drag，模拟手势不稳定。
    const draft = 'draft that must survive mode switch';
    await tester.enterText(find.byType(TextField), draft);
    await tester.pumpAndSettle();
    final listBefore = tester.widget<ListView>(find.byType(ListView));
    final controllerBefore = listBefore.controller;
    final maxBefore = controllerBefore?.position.maxScrollExtent ?? 0;
    expect(maxBefore, greaterThan(300), reason: '前置：30 条消息可滚动');
    controllerBefore?.jumpTo(300);
    await tester.pumpAndSettle();

    final offsetBefore = controllerBefore?.position.pixels ?? 0;
    expect(offsetBefore, 300, reason: '前置：滚动位在非底部位置');

    // 退出工作台（fs=false → Offstage 隐藏）
    app.toggleAiPanelFullscreen();
    await tester.pumpAndSettle();
    expect(find.byType(AiWorkbenchShell), findsNothing);

    // 再进：会话 / 草稿 / 滚动位仍在
    app.toggleAiPanelFullscreen();
    await tester.pumpAndSettle();
    expect(find.byType(AiWorkbenchShell), findsOneWidget);

    expect(
      app.aiMessages.length,
      30,
      reason: '会话消息跨模式存活（provider 域，本就与模式无关）',
    );
    expect(find.text(draft), findsOneWidget, reason: '输入草稿保留（AC1.4）');
    final listAfter = tester.widget<ListView>(find.byType(ListView));
    final offsetAfter = listAfter.controller?.position.pixels ?? 0;
    expect(offsetAfter, offsetBefore, reason: '滚动位保留（AC1.4）');
  });
}
