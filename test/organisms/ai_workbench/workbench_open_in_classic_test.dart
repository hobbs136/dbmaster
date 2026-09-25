// T13 互跳出口组件面测试（design-ai-workbench §6.3/§11.1 R7）。
//
// AC7.1：「在经典中打开」/「在网格中打开」→ 经典模式新 tab 承载 SQL，
// 不覆盖用户既有 tab；AC7.3：目标 tab 的 SQL/连接 = 送出内容（透传）。
// 真库形态归 T15（R7 互跳 e2e）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_open_in_classic.dart';
import 'package:dbmaster/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 泵互跳触发面：按钮经 [WorkbenchOpenInClassic.open] 驱动。
  Future<AppProvider> pumpHarness(
    WidgetTester tester, {
    required String sql,
  }) async {
    final app = AppProvider();
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppProvider>.value(
        value: app,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open'),
                  onPressed: () => WorkbenchOpenInClassic.open(context, sql),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  group('AC7.1/7.3 互跳落新 tab（不覆盖既有）', () {
    testWidgets('锁定上下文 → openQueryTab 新 tab 承载 SQL，既有 tab 不动，退出全屏', (
      tester,
    ) async {
      const sql = 'SELECT a, b FROM orders WHERE id = 7';
      final app = await pumpHarness(tester, sql: sql);

      // 既有 tab（不同 SQL）：互跳不得覆盖。
      await app.addNewTab(connectionId: 'conn-9', databaseName: 'db9');
      app.updateTabSql(app.activeTabIndex, 'SELECT existing');
      final tabsBefore = app.tabs.length;
      final existingTabId = app.activeTab?.id;
      final existingTabIndex = app.activeTabIndex;

      // 工作台可见态（z2 全屏）→ 互跳应退出。
      app.setAiPanelOpen(true);
      app.setAiPanelFullscreen(true);
      await tester.pumpAndSettle();

      // 锁定上下文：互跳目标 = conn-1/db1。
      app.aiPanel.ensureSession();
      app.aiPanel.lockWorkbenchContext('conn-1', 'db1');

      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();

      expect(app.tabs.length, tabsBefore + 1, reason: 'AC7.1：新 tab 承载，不开既有');
      expect(app.activeTab?.sql, sql, reason: 'AC7.3：目标 tab SQL == 送出内容');
      expect(app.activeTab?.connectionId, 'conn-1',
          reason: 'AC7.3：目标 tab 连接 == 生效上下文');
      expect(app.activeTab?.databaseName, 'db1');
      expect(
        app.tabs[existingTabIndex].id,
        existingTabId,
        reason: '既有 tab 未被覆盖（原位原内容）',
      );
      expect(app.tabs[existingTabIndex].sql, 'SELECT existing');
      expect(app.aiPanelFullscreen, isFalse, reason: '互跳后退出工作台全屏');
      expect(find.text(l10n.aiPanelOpenInNewQuery), findsOneWidget,
          reason: '落点反馈不静默');
    });

    testWidgets('上下文不完整 → 新空 tab 兜底仍承载送出 SQL', (tester) async {
      const sql = 'SELECT fallback';
      final app = await pumpHarness(tester, sql: sql);
      // 无锁定、无连接 → 上下文不完整；预置一个未绑定 tab 保证兜底
      // addNewTab 有可跟随的活动上下文（无连接环境无参 addNewTab 是静默
      // 空操作——既有语义）。
      await app.addNewTab(connectionId: 'conn-9', databaseName: 'db9');
      app.aiPanel.ensureSession();

      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();

      expect(app.activeTab?.sql, sql,
          reason: '兜底路径同样保证 SQL == 送出内容');
    });
  });
}
