import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/organisms/ai_panel/ai_welcome_state.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _buildWelcomeState({
  String? connectionName,
  String? databaseName,
  Function(String question)? onQuestionTap,
}) {
  return ChangeNotifierProvider<AppProvider>.value(
    value: AppProvider(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: AiWelcomeState(
          connectionName: connectionName,
          databaseName: databaseName,
          onQuestionTap: onQuestionTap,
        ),
      ),
    ),
  );
}

void main() {
  group('AiWelcomeState', () {
    testWidgets('renders header icon and title', (tester) async {
      await tester.pumpWidget(_buildWelcomeState());
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.bot), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('shows connection badge when connectionName is provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildWelcomeState(
          connectionName: 'Local MySQL',
          databaseName: 'test_db',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Local MySQL'), findsOneWidget);
      expect(find.text('test_db'), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleCheckBig), findsOneWidget);
    });

    testWidgets('example question tap invokes onQuestionTap with text', (
      tester,
    ) async {
      String? tappedQuestion;
      await tester.pumpWidget(
        _buildWelcomeState(
          onQuestionTap: (question) => tappedQuestion = question,
        ),
      );
      await tester.pumpAndSettle();

      final cards = find.byType(InkWell);
      expect(cards, findsWidgets);

      await tester.tap(cards.first);
      await tester.pumpAndSettle();

      expect(tappedQuestion, isNotNull);
      expect(tappedQuestion!.isNotEmpty, isTrue);
    });
  });
}
