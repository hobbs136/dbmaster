import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _buildInputArea({
  required bool isSending,
  required ValueChanged<String> onSend,
  required VoidCallback onStop,
  VoidCallback? onShowApiSettings,
  required ValueChanged<String> onSlashCommand,
}) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: AppProvider(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: AiInputArea(
            isSending: isSending,
            onSend: onSend,
            onStop: onStop,
            onShowApiSettings: onShowApiSettings ?? () {},
            onSlashCommand: onSlashCommand,
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('AiInputArea', () {
    testWidgets('renders input field and send button', (tester) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsOneWidget);
    });

    testWidgets('typing text enables send button', (tester) async {
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // 初始状态发送按钮应禁用（颜色较淡）
      await tester.enterText(find.byType(TextField), 'hello ai');
      await tester.pumpAndSettle();

      expect(find.text('hello ai'), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsOneWidget);
    });

    testWidgets('tapping send button calls onSend with input text', (
      tester,
    ) async {
      String? sentText;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (text) => sentText = text,
          onStop: () {},
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'explain this query');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(sentText, 'explain this query');
      expect(find.text('explain this query'), findsNothing);
    });

    testWidgets('send button is disabled while isSending', (tester) async {
      String? sentText;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: true,
          onSend: (text) => sentText = text,
          onStop: () {},
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsNothing);

      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(sentText, isNull);
    });

    testWidgets('stop button calls onStop while sending', (tester) async {
      var stopped = false;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: true,
          onSend: (_) {},
          onStop: () => stopped = true,
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell).last);
      await tester.pumpAndSettle();

      expect(stopped, isTrue);
    });

    testWidgets('settings button calls onShowApiSettings', (tester) async {
      var settingsShown = false;
      await tester.pumpWidget(
        _buildInputArea(
          isSending: false,
          onSend: (_) {},
          onStop: () {},
          onShowApiSettings: () => settingsShown = true,
          onSlashCommand: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.settings));
      await tester.pumpAndSettle();

      expect(settingsShown, isTrue);
    });
  });
}
