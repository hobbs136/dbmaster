// UI35-443/444 红测（编译红申报）：AI 备份预填通道。
//
// 契约来源：B-07 冻结件——AiPanelProvider 新增 pendingComposerPrefill
// （String? 字段 + 消费即清）；经典 dock composer post-frame 写入；沿
// WorkbenchEntryIntent（R7）先例。纪律：不自动发送、不校验 API key、
// 不 recordAiUsage（沿 analyzeTreeNodeInWorkbench 先例）。
//
// ⚠️ pendingComposerPrefill / requestComposerPrefill / consumeComposerPrefill
// 尚不存在 → 编译错误原文 = 红态证据。request/consume 方法名沿 R7 先例
// （requestWorkbenchEntry / consumeWorkbenchEntryIntent）约定，实现批可按
// 实际命名适配（行为断言语义不变）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/providers/ai_panel_provider.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AI 备份预填通道（UI35-443：provider 通道）', () {
    late AiPanelProvider provider;
    late AppLocalizations l10n;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      provider = AiPanelProvider();
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });
    tearDown(() {
      provider.dispose();
    });

    test('UI35-443a: 初始无预填（pendingComposerPrefill 为 null）', () {
      expect(provider.pendingComposerPrefill, isNull);
    });

    test(
      'UI35-443b: AI 分流后 pendingComposerPrefill = prodGuardAiBackupPrompt 填充 {object} 后的值',
      () {
        final prompt = l10n.prodGuardAiBackupPrompt('orders');
        provider.requestComposerPrefill(prompt);
        expect(
          provider.pendingComposerPrefill,
          prompt,
          reason: '预填值 = prodGuardAiBackupPrompt({object}) 的本地化填充结果',
        );
      },
    );

    test('UI35-443c: 消费即清', () {
      provider.requestComposerPrefill(l10n.prodGuardAiBackupPrompt('orders'));
      provider.consumeComposerPrefill();
      expect(provider.pendingComposerPrefill, isNull, reason: '消费即清');
    });
  });

  group('经典 dock composer 预填落位（UI35-444）', () {
    late AppProvider app;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      app = AppProvider();
    });
    tearDown(() {
      app.dispose();
    });

    Future<void> pumpDock(WidgetTester tester) async {
      final layout = LayoutPreferencesProvider();
      await layout.load();
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });
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
            home: const Scaffold(body: AiPanelWidget()),
          ),
        ),
      );
      // 有界 pump：面板可能存在常驻动画，不用 pumpAndSettle（仓内既有惯例）。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
      'UI35-444: composer 文本就位、不自动发送（消息数不变）、不校验 API key',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpDock(tester);
        final prompt = l10n.prodGuardAiBackupPrompt('orders');

        // 模拟 AI 分流调用方动作（B-07 通道）：挂起预填。AppProvider 内
        // AiConfigProvider 全程未配置任何 API key——预填照常就位即
        // 「不校验 API key」的行为断言。
        app.aiPanel.requestComposerPrefill(prompt);

        // post-frame 写入（B-07：经典 dock composer post-frame 写入）。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(
          find.byType(TextField),
          findsOneWidget,
          reason: '经典 dock 内 composer 输入框唯一',
        );
        final composer = tester.widget<TextField>(find.byType(TextField));
        expect(
          composer.controller?.text,
          prompt,
          reason: '预填文本已 post-frame 就位 composer',
        );

        // 不自动发送：消息数不变（始终为空，无任何 loading 消息）。
        expect(app.aiMessages, isEmpty, reason: '预填不自动发送，消息数不变');

        // 通道消费即清：composer post-frame 消费后 provider 侧挂起值清空
        // （沿 WorkbenchEntryIntent「壳 post-frame 消费后清除」同款语义）。
        expect(
          app.aiPanel.pendingComposerPrefill,
          isNull,
          reason: '消费即清（composer post-frame 消费）',
        );
      },
    );
  });
}
