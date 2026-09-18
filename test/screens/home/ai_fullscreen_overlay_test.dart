// C23 走查反馈修复回归：AI 面板「全屏」应真铺满工作区。
//
// 根因：AiFullscreenOverlay 曾把 aiFullscreen 与 aiAsOverlay 两种形态都
// 渲染成 AiPanelOverlay 浮动窗（默认 65% 视口、可拖拽）——「全屏」名不
// 符实。修复：ai.fs = true → 自撑满真全屏（AiPanelWidget 直铺）；
// 浮窗仅留给窗口过窄的布局降级（aiAsOverlay && !fs）。
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

  Future<void> pumpLayer(
    WidgetTester tester, {
    required Size surface,
    required bool fullscreen,
  }) async {
    final app = AppProvider();
    app.toggleAiPanel(); // open
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
  }

  testWidgets('全屏态：AiPanelWidget 直铺整个工作区，无浮动窗', (tester) async {
    await pumpLayer(tester, surface: const Size(1200, 800), fullscreen: true);

    expect(find.byType(AiPanelOverlay), findsNothing, reason: '全屏不再是浮动窗');
    final panel = find.byType(AiPanelWidget);
    expect(panel, findsOneWidget);

    final size = tester.getSize(panel);
    expect(size, const Size(1200, 800), reason: '全屏面板铺满整个视口');
  });

  testWidgets('全屏态退出：关 fs 后不再渲染全屏面板', (tester) async {
    await pumpLayer(tester, surface: const Size(1200, 800), fullscreen: false);

    expect(find.byType(AiPanelOverlay), findsNothing);
    // fs=false + 宽度充足：aiAsOverlay=false → 层内不渲染（面板归停靠侧栏，
    // 由 MainWorkspaceLayer 负责，不在本层）
    expect(find.byType(AiPanelWidget), findsNothing);
  });

  testWidgets('窄窗降级（fs=false + 宽度不足）：渲染浮动窗', (tester) async {
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
}
