// 批3 T7-R 红测先行：工作台 Exit 产物保留 + 经典 dock「Pinned artifacts」行
// （.specs/tasks-v3.5-ui.md §3-B02，UI35-316/317）。
//
// 行为目标：工作台 pin 产物 → Exit → pinned 保留；经典 dock（非矮档）底部
// 出现「Pinned artifacts」行（h≈28，chip 22，workbenchPinnedArtifacts /
// workbenchReopenArtifact）；点芯片 = 重进工作台并路由容器；矮档（面板
// <420）不渲染该行。
//
// 方法论约束：全程文本/几何断言，不引用新类型名。当前运行红态 = dock 无
// 该行（现实现：shell 私有 controller，Exit 即随 shell 卸载丢弃）。
// 矮档负例（<420 不渲染）在当前实现下恒绿（无该行可渲染），作为实现后
// 回归守卫 + 前置几何断言（面板高 <420 成立才判 findsNothing）。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_artifact_strip.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
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
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart';

DbServer _mysql() => DbServer(
  id: 'c1',
  name: 'Local MySQL',
  type: DatabaseType.mysql,
  host: '192.0.2.128',
  port: 3306,
);

/// 吞咽窄窗口下经典工作区布局的测试字体溢出伪影（沿
/// ai_workbench_shell_test.dart suppressOverflowArtifacts 先例；
/// 只吞 RenderFlex overflowed，其余原样转交）。
void suppressOverflowArtifacts() {
  final previousHandler = FlutterError.onError;
  addTearDown(() => FlutterError.onError = previousHandler);
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().contains('RenderFlex overflowed')) {
      return;
    }
    previousHandler?.call(details);
  };
}

Future<AppProvider> pumpHome(
  WidgetTester tester, {
  required Size surface,
}) async {
  final app = AppProvider();
  // header 全屏按钮仅在「有连接」分支渲染（C23.2 既有行为）。
  app.connection.addSavedServerForTest(_mysql());
  app.toggleAiPanel(); // 打开 AI 面板（宽窗 → z0 停靠）
  await tester.binding.setSurfaceSize(surface);
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

AgentResultRef _ref(String refId) => AgentResultRef(
  refId: refId,
  sql: 'EXPLAIN SELECT 1',
  rowCount: 1,
  columns: const ['id'],
  rows: const [
    {'id': 1},
  ],
);

/// 进工作台 → 经产物条拿到共享 controller → pin → Exit。
/// 返回 pinned tab（controller 断言用）。
Future<WorkbenchStageTab> pinThenExit(WidgetTester tester, AppProvider app) async {
  final l10n = AppLocalizations.of(tester.element(find.byType(HomeScreen)))!;
  await tester.tap(find.byTooltip(l10n.aiPanelFullscreen));
  await tester.pumpAndSettle();
  expect(app.aiPanelFullscreen, isTrue, reason: '前置：已进工作台');

  // 产物条恒挂载（shell 底部）→ 经其 widget 拿壳内 controller。
  final strip = tester.widget<WorkbenchArtifactStrip>(
    find.byType(WorkbenchArtifactStrip),
  );
  final tab = strip.controller.pinArtifact(_ref('res_explain'), 'Explain plan A');
  await tester.pump();

  // UI35-316（前半）：Exit 前 pinned 可查（controller 断言）。
  expect(
    strip.controller.pinnedTabs.map((t) => t.id),
    contains(tab.id),
    reason: 'pin 后 pinned 投影含该产物',
  );

  await tester.tap(find.byKey(const ValueKey('workbench_exit_button')));
  await tester.pumpAndSettle();
  expect(app.aiPanelFullscreen, isFalse, reason: '前置：已 Exit 回经典');
  return tab;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('UI35-316 Exit 保留 + 经典 dock「Pinned artifacts」行（非矮档）', () {
    testWidgets('pin → Exit → dock 底部行 + 芯片；点芯片重进工作台', (tester) async {
      final app = await pumpHome(tester, surface: const Size(1400, 900));
      await pinThenExit(tester, app);

      // RED：经典 dock 底部「Pinned artifacts」行（workbenchPinnedArtifacts）。
      expect(
        find.text('Pinned artifacts'),
        findsOneWidget,
        reason: 'Exit 后经典 dock 底部应渲染「Pinned artifacts」行',
      );
      // 芯片：pinned 产物标签（workbenchReopenArtifact 语义）。
      expect(
        find.text('Explain plan A'),
        findsOneWidget,
        reason: '行内芯片呈现 pinned 产物标签',
      );

      // 点芯片 = 重进工作台并路由容器。
      await tester.tap(find.text('Explain plan A'));
      await tester.pumpAndSettle();
      expect(app.aiPanelFullscreen, isTrue, reason: '点芯片重进工作台');
      expect(find.byType(AiWorkbenchShell), findsOneWidget);
      // grid pin 产物 → Data & Viz 容器（EXPLAIN 源产物的 Diagnostics 路由
      // 子例归组件面 UI35-315；此处断言重入 + 容器路由出现）。
      expect(find.text('Data & Viz'), findsOneWidget);
    });
  });

  group('UI35-317 矮档（<420）经典 dock 不渲染该行', () {
    testWidgets('Exit 后窗口收窄至面板 <420 → 行消失（前置几何断言）', (tester) async {
      final app = await pumpHome(tester, surface: const Size(1400, 900));
      await pinThenExit(tester, app);

      suppressOverflowArtifacts();
      await tester.binding.setSurfaceSize(const Size(1400, 380));
      await tester.pumpAndSettle();

      // 前置：面板确实处于矮档（<420），负例才有判定力。
      final panelRect = tester.getRect(find.byType(AiPanelWidget));
      expect(panelRect.height, lessThan(420.0), reason: '前置：面板矮档成立');

      expect(
        find.text('Pinned artifacts'),
        findsNothing,
        reason: '矮档 <420 经典 dock 不渲染「Pinned artifacts」行',
      );
    });
  });
}
