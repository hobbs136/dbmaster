import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_message_type.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/organisms/ai_panel/ai_message_item.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _buildMessageItem({
  required AiMessage message,
  Function(String sql, bool isDangerous)? onExecuteSql,
  Function(String sql)? onOpenInNewQuery,
  Function(String messageId)? onToggleBookmark,
  Function(String messageId, String content)? onBranchFromMessage,
  VoidCallback? onRegenerate,
  VoidCallback? onContinue,
}) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: AppProvider(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: AiMessageItem(
          message: message,
          onExecuteSql: onExecuteSql ?? (a, b) {},
          onOpenInNewQuery: onOpenInNewQuery ?? (_) {},
          onToggleBookmark: onToggleBookmark ?? (_) {},
          onBranchFromMessage: onBranchFromMessage ?? (a, b) {},
          onRegenerate: onRegenerate,
          onContinue: onContinue,
        ),
      ),
    ),
  );
}

AiMessage _message({
  required String id,
  required bool isUser,
  required String content,
  AiMessageStatus status = AiMessageStatus.sent,
  bool isDangerous = false,
}) {
  return AiMessage(
    id: id,
    isUser: isUser,
    content: content,
    timestamp: DateTime.now(),
    status: status,
    isDangerous: isDangerous,
  );
}

void main() {
  group('AiMessageItem', () {
    testWidgets('renders user message with person avatar', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(id: 'm1', isUser: true, content: 'Hello AI'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello AI'), findsOneWidget);
      expect(find.byIcon(LucideIcons.user), findsOneWidget);
    });

    testWidgets('renders AI message with robot avatar', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(id: 'm2', isUser: false, content: 'Hello user'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Hello user'), findsOneWidget);
      expect(find.byIcon(LucideIcons.bot), findsOneWidget);
    });

    testWidgets('shows completed status indicator', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(
            id: 'm3',
            isUser: false,
            content: 'Done',
            status: AiMessageStatus.completed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.circleCheckBig), findsOneWidget);
    });

    testWidgets('shows failed status indicator', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(
            id: 'm4',
            isUser: false,
            content: 'Oops',
            status: AiMessageStatus.failed,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.circleAlert), findsWidgets);
    });

    testWidgets('shows regenerate button and invokes callback', (tester) async {
      var regenerated = false;
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(id: 'm5', isUser: false, content: 'Need retry'),
          onRegenerate: () => regenerated = true,
        ),
      );
      await tester.pumpAndSettle();

      final regenerateButton = find.widgetWithText(InkWell, 'Regenerate');
      expect(regenerateButton, findsOneWidget);

      await tester.tap(regenerateButton);
      await tester.pumpAndSettle();

      expect(regenerated, isTrue);
    });

    testWidgets('shows continue button for interrupted message', (
      tester,
    ) async {
      var continued = false;
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(
            id: 'm6',
            isUser: false,
            content: 'Interrupted',
            status: AiMessageStatus.interrupted,
          ),
          onContinue: () => continued = true,
        ),
      );
      await tester.pumpAndSettle();

      final continueButton = find.widgetWithText(InkWell, 'Continue');
      expect(continueButton, findsOneWidget);

      await tester.tap(continueButton);
      await tester.pumpAndSettle();

      expect(continued, isTrue);
    });

    testWidgets('shows danger badge for dangerous operation', (tester) async {
      await tester.pumpWidget(
        _buildMessageItem(
          message: _message(
            id: 'm7',
            isUser: false,
            content: 'DROP TABLE users;',
            isDangerous: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    });
  });
}
