// C23 走查反馈 e2e 回归：AI 面板「全屏」应真铺满工作区（真实 HomeScreen 路径）。
//
// 用户报告（2026-08-22）：「ai全屏化直接消失了」——点全屏后 AI 面板整体
// 不可见。既有回归（ai_fullscreen_overlay_test.dart）是层隔离 + 状态预置，
// 未覆盖真实交互路径（HomeScreen 4 层 Stack + 点 header maximize 按钮）。
// 本文件按用户操作序列走完整路径：
//   宽窗 → 打开 AI 面板（z0 停靠）→ 有连接（header 有全屏按钮）→
//   点 header maximize → 断言全屏面板存在且铺满工作区 → 点 minimize 退出
//   → 断言回停靠。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_mini_fab.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_overlay.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/approval_provider.dart';
import 'package:dbmaster/providers/health_check_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/task_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/providers/workspace_provider.dart';
import 'package:dbmaster/screens/home_screen.dart';

DbServer _mysql() => DbServer(
  id: 'c1',
  name: 'Local MySQL',
  type: DatabaseType.mysql,
  host: '192.0.2.128',
  port: 3306,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppProvider> pumpHome(
    WidgetTester tester, {
    bool openPanel = true,
  }) async {
    final app = AppProvider();
    // header 全屏按钮仅在「有连接」分支渲染（空态分支无按钮，C23.2 既有行为）。
    app.connection.addSavedServerForTest(_mysql());
    if (openPanel) app.toggleAiPanel(); // 打开 AI 面板（宽窗 → z0 停靠）

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
          ChangeNotifierProvider<AppProvider>.value(value: app),
          ChangeNotifierProvider<TaskProvider>.value(value: TaskProvider()),
          ChangeNotifierProvider<ServerConnectionProvider>.value(
            value: ServerConnectionProvider(),
          ),
          ChangeNotifierProvider<HealthCheckProvider>.value(
            value: HealthCheckProvider(),
          ),
          ChangeNotifierProvider<ApprovalProvider>.value(
            value: ApprovalProvider(),
          ),
          ChangeNotifierProvider<WorkspaceProvider>.value(
            value: WorkspaceProvider(),
          ),
          ChangeNotifierProvider<ThemeProvider>.value(
            value: ThemeProvider()..load(),
          ),
          ChangeNotifierProvider<LocaleProvider>.value(
            value: LocaleProvider()..load(),
          ),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: LayoutPreferencesProvider()..load(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  testWidgets('E2E-FS-001: 停靠面板点全屏 → 面板铺满工作区（不消失）', (tester) async {
    final app = await pumpHome(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;

    // 前置：停靠面板可见，header 有全屏按钮（有连接）。
    expect(find.byType(AiPanelWidget), findsOneWidget, reason: '停靠面板应可见');
    final maximize = find.byTooltip(l10n.aiPanelFullscreen);
    expect(maximize, findsOneWidget, reason: '有连接时 header 应有全屏按钮');

    // 操作：点全屏。
    await tester.tap(maximize);
    await tester.pumpAndSettle();

    // 断言：面板仍存在（不消失）且铺满工作区，不再是浮动窗。
    expect(app.aiPanelFullscreen, isTrue);
    final panel = find.byType(AiPanelWidget);
    expect(panel, findsOneWidget, reason: '全屏后面板必须仍可见（用户报告消失）');
    expect(find.byType(AiPanelOverlay), findsNothing, reason: '全屏非浮动窗');

    final size = tester.getSize(panel);
    expect(
      size,
      const Size(1400, 875),
      reason: '全屏面板应铺满工作区（1400×900 视口减 25px 状态栏）',
    );
  });

  testWidgets('E2E-FS-002: 全屏态点 minimize → 退出回停靠面板', (tester) async {
    final app = await pumpHome(tester);
    final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;

    await tester.tap(find.byTooltip(l10n.aiPanelFullscreen));
    await tester.pumpAndSettle();
    expect(find.byType(AiPanelWidget), findsOneWidget);

    // 退出：全屏 header 的 minimize 按钮。
    await tester.tap(find.byTooltip(l10n.aiPanelExitFullscreen));
    await tester.pumpAndSettle();

    expect(app.aiPanelFullscreen, isFalse);
    expect(
      find.byType(AiPanelWidget),
      findsOneWidget,
      reason: '退出全屏应回到停靠面板，而非消失',
    );
    expect(find.byType(AiMiniFab), findsNothing, reason: '面板仍开，FAB 不出现');
  });

  testWidgets('E2E-FS-003: 面板关闭态点 FAB → 直入全屏（不消失）', (tester) async {
    // FAB onTap = toggleAiPanel + setAiPanelFullscreen(true)——面板从关闭
    // 直入全屏，同一渲染路径（用户「全屏化直接消失」的最可能入口）。
    final app = await pumpHome(tester, openPanel: false);

    final fab = find.byType(AiMiniFab);
    expect(fab, findsOneWidget, reason: '面板关闭时 FAB 应可见');

    await tester.tap(fab);
    await tester.pumpAndSettle();

    expect(app.aiPanelOpen, isTrue);
    expect(app.aiPanelFullscreen, isTrue);
    final panel = find.byType(AiPanelWidget);
    expect(panel, findsOneWidget, reason: 'FAB 直入全屏后面板必须可见');
    expect(tester.getSize(panel), const Size(1400, 875));
  });
}
