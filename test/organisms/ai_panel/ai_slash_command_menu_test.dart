import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_panel/ai_slash_command_menu.dart';

void main() {
  group('SlashCommandMenu', () {
    testWidgets('renders all commands when filter is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SlashCommandMenu(filter: '', onCommandSelected: (a, b) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('filters commands by command text', (tester) async {
      String? selectedAction;
      String? selectedCommand;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SlashCommandMenu(
              filter: 'opt',
              onCommandSelected: (action, command) {
                selectedAction = action;
                selectedCommand = command;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('/optimize'), findsOneWidget);
      expect(find.text('/explain'), findsNothing);

      await tester.tap(find.text('/optimize'));
      await tester.pumpAndSettle();

      expect(selectedAction, 'optimize_sql');
      expect(selectedCommand, '/optimize');
    });

    testWidgets('returns empty SizedBox when no commands match', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: SlashCommandMenu(
              filter: 'xyz123',
              onCommandSelected: (a, b) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });
  });
}
