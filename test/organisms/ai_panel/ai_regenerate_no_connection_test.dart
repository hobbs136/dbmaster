// Regression for: AI 助手在未选连接时发送问题，错误消息上的 Regenerate 不起作用。
//
// 根因：_sendMessage 在 guard 失败（无连接/库/apiKey）时只入库错误消息、不入库
// 用户消息 → 错误消息落到 index 0 → _regenerateMessage 的 currentIndex<=0 守卫静默
// no-op。Fix：_sendMessage 在校验前先入库用户消息（recordUserMessage）。
//
// 本测试连真实库无关（guard 在连接前就失败），走 widget 测试：pump AiPanelWidget，
// 不选连接、直接发送，断言消息列表为 [用户消息, 错误消息]（用户消息在前），即
// Regenerate 现在能定位到前置用户消息。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'send without connection records user message before the error reply',
    (tester) async {
      final app = AppProvider();
      final layout = LayoutPreferencesProvider();
      await layout.load();

      await tester.binding.setSurfaceSize(const Size(1400, 900));
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
      await tester.pumpAndSettle();

      // Type a question into the AiInputArea text field.
      final inputField = find.descendant(
        of: find.byType(AiInputArea),
        matching: find.byType(TextField),
      );
      expect(inputField, findsOneWidget, reason: 'AiInputArea text field');
      await tester.enterText(inputField, 'hello');
      await tester.pump();

      // Tap send (LucideIcons.send becomes tappable once input is non-empty).
      final sendButton = find.byIcon(LucideIcons.send);
      expect(sendButton, findsOneWidget, reason: 'send button visible');
      await tester.tap(sendButton);
      await tester.pumpAndSettle();

      // Assert: messages = [user, error]. Without the fix it was [error] only,
      // leaving the error at index 0 and Regenerate silently no-op.
      final messages = app.aiMessages;
      expect(messages, hasLength(2), reason: 'exactly user + error reply');
      expect(
        messages[0].isUser,
        isTrue,
        reason: 'user message must be recorded first (was missing before fix)',
      );
      expect(messages[0].content, 'hello');
      expect(messages[1].isUser, isFalse, reason: 'error reply from guard');
      // The first guard to fire depends on env: no API key → "configure the api key";
      // API key set but no connection → "select a connection". Either is a valid
      // guard-failure reply — what matters is the user message was recorded before it.
      final err = messages[1].content.toLowerCase();
      expect(
        err.contains('api key') || err.contains('connection'),
        isTrue,
        reason: 'should be a guard-failure reply (apiKey or connection)',
      );
      expect(
        err,
        isNot(contains('hello')),
        reason: 'error reply must not echo the user text',
      );
    },
  );
}
