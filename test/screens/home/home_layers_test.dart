// ============================================================================
// layer 显隐测试（layout plan §3.1）
// ============================================================================
//
// 验证 4 个 layer 的 z-order 显隐条件与重构前 home_screen.dart 内联 Stack
// 逐字一致（见 design §2.2）。每个 layer 独立 pump + 断言 findsNothing /
// findsOneWidget。effective 降级态（aiAsOverlay / ecAsFloating）用窄宽度触发。
//
// layers 的 constraints 是构造参数——直接传 BoxConstraints，无需 tester.view。

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_panel/ai_mini_fab.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_overlay.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/execution_center/execution_center_panel.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/execution_center_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/task_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/screens/home/ai_fullscreen_overlay.dart';
import 'package:dbmaster/screens/home/ai_mini_fab_layer.dart';
import 'package:dbmaster/screens/home/execution_center_overlay.dart';
import 'package:dbmaster/screens/home/main_workspace_layer.dart';
import 'package:dbmaster/templates/main_workspace.dart';
import 'package:dbmaster/theme/app_theme.dart';

void _noop() {}

/// 通用 harness：MaterialApp(darkTheme 提供 themeColors) + l10n + 5 provider +
/// SizedStack 承载 layer（positioned 与非 positioned 层均可）。
Widget _harness(
  Widget layer, {
  required AppProvider app,
  LayoutPreferencesProvider? lp,
  ExecutionCenterProvider? ec,
  double width = 1600,
  double height = 900,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: app),
        ChangeNotifierProvider<LayoutPreferencesProvider>.value(
          value: lp ?? LayoutPreferencesProvider(),
        ),
        ChangeNotifierProvider<ExecutionCenterProvider>.value(
          value: ec ?? ExecutionCenterProvider(),
        ),
        ChangeNotifierProvider<TaskProvider>.value(value: TaskProvider()),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: Scaffold(
        body: SizedBox(
          width: width,
          height: height,
          child: Stack(children: [layer]),
        ),
      ),
    ),
  );
}

BoxConstraints _c(double w) => BoxConstraints(maxWidth: w, maxHeight: 900);

MainWorkspaceLayer _workspaceLayer(double w) => MainWorkspaceLayer(
      constraints: _c(w),
      onToggleSidebar: _noop,
      onShowConnectionDialog: _noop,
      onShowConnectionManager: _noop,
      onOpenSqliteFile: _noop,
      onCommandPalette: _noop,
    );

void main() {
  group('z3 AiMiniFabLayer', () {
    testWidgets('hidden when AI panel open', (tester) async {
      final app = AppProvider()..toggleAiPanel(); // open
      await tester.pumpWidget(_harness(const AiMiniFabLayer(), app: app));
      await tester.pumpAndSettle();
      expect(find.byType(AiMiniFab), findsNothing);
    });

    testWidgets('shown when AI panel closed', (tester) async {
      final app = AppProvider(); // closed (default)
      await tester.pumpWidget(_harness(const AiMiniFabLayer(), app: app));
      await tester.pumpAndSettle();
      expect(find.byType(AiMiniFab), findsOneWidget);
    });
  });

  group('z0 MainWorkspaceLayer', () {
    testWidgets('skipped (hidden) when AI fullscreen', (tester) async {
      final app = AppProvider()
        ..toggleAiPanel()
        ..setAiPanelFullscreen(true);
      await tester.pumpWidget(_harness(_workspaceLayer(1600), app: app));
      await tester.pumpAndSettle();
      expect(find.byType(MainWorkspace), findsNothing);
    });

    testWidgets('shown when AI not fullscreen', (tester) async {
      final app = AppProvider(); // AI closed
      // 用 800 宽（< 断点 900）使 sidebar 自动折叠为 icon rail，避开
      // SidebarHeader 在测试字体下的 RenderFlex 溢出（与重构无关，旧 Stack 同样）。
      // 仍验证核心逻辑：非全屏时 MainWorkspaceLayer 挂载 MainWorkspace。
      await tester.pumpWidget(_harness(_workspaceLayer(800),
          app: app, width: 800));
      await tester.pumpAndSettle();
      expect(find.byType(MainWorkspace), findsOneWidget);
    });
  });

  group('z1 ExecutionCenterOverlay', () {
    testWidgets('hidden when EC closed', (tester) async {
      final ec = ExecutionCenterProvider(); // closed
      await tester.pumpWidget(_harness(
        ExecutionCenterOverlay(constraints: _c(1600)),
        app: AppProvider(),
        ec: ec,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ExecutionCenterPanel), findsNothing);
    });

    testWidgets('hidden when EC pinned + wide (docked, not floating)',
        (tester) async {
      final ec = ExecutionCenterProvider()..open(); // pinned default, wide
      await tester.pumpWidget(_harness(
        ExecutionCenterOverlay(constraints: _c(1600)),
        app: AppProvider(),
        ec: ec,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ExecutionCenterPanel), findsNothing);
    });

    testWidgets('shown when EC floating (!pinned)', (tester) async {
      final ec = ExecutionCenterProvider()
        ..open()
        ..togglePin(); // floating
      await tester.pumpWidget(_harness(
        ExecutionCenterOverlay(constraints: _c(1600)),
        app: AppProvider(),
        ec: ec,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ExecutionCenterPanel), findsOneWidget);
    });

    testWidgets('shown when EC pinned but degraded to floating (narrow)',
        (tester) async {
      // 宽 800：sidebar(240→collapse 44) + ec docked(360) = 404 < 480 → ecAsFloating
      final ec = ExecutionCenterProvider()..open(); // pinned, narrow
      await tester.pumpWidget(_harness(
        ExecutionCenterOverlay(constraints: _c(800)),
        app: AppProvider(),
        ec: ec,
        width: 800,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ExecutionCenterPanel), findsOneWidget);
    });
  });

  group('z2 AiFullscreenOverlay', () {
    testWidgets('hidden when AI closed', (tester) async {
      final app = AppProvider(); // closed
      await tester.pumpWidget(_harness(
        AiFullscreenOverlay(constraints: _c(1600), onToggleFullscreen: _noop),
        app: app,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AiPanelOverlay), findsNothing);
    });

    testWidgets('hidden when AI docked + wide (no overlay)', (tester) async {
      final app = AppProvider()..toggleAiPanel(); // open, not fullscreen, wide
      await tester.pumpWidget(_harness(
        AiFullscreenOverlay(constraints: _c(1600), onToggleFullscreen: _noop),
        app: app,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AiPanelOverlay), findsNothing);
    });

    testWidgets('shown when AI fullscreen', (tester) async {
      // C23 走查反馈修复：全屏 = 真铺满（AiPanelWidget 直铺），非浮动窗
      final app = AppProvider()
        ..toggleAiPanel()
        ..setAiPanelFullscreen(true);
      await tester.pumpWidget(_harness(
        AiFullscreenOverlay(constraints: _c(1600), onToggleFullscreen: _noop),
        app: app,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AiPanelOverlay), findsNothing);
      expect(find.byType(AiPanelWidget), findsOneWidget);
    });

    testWidgets('shown when AI degraded to overlay (narrow)', (tester) async {
      // 宽 700：sidebar(240)+ai docked(默认 ~320) 已使 workspace < 480 → aiAsOverlay
      final app = AppProvider()..toggleAiPanel(); // open, not fullscreen, narrow
      await tester.pumpWidget(_harness(
        AiFullscreenOverlay(constraints: _c(700), onToggleFullscreen: _noop),
        app: app,
        width: 700,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AiPanelOverlay), findsOneWidget);
    });
  });
}
