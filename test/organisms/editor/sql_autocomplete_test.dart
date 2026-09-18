import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/editor/sql_autocomplete.dart';
import 'package:dbmaster/services/sql_autocomplete_service.dart';

void main() {
  group('SQLAutocomplete (020-mongo UI)', () {
    Widget buildWidget({
      required List<Suggestion> suggestions,
      String title = 'SQL Autocomplete',
      int selectedIndex = 0,
      VoidCallback? onDismiss,
      ValueChanged<Suggestion>? onSelected,
      ValueChanged<int>? onSelectionChanged,
    }) {
      TestWidgetsFlutterBinding.ensureInitialized();
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Stack(
            children: [
              SQLAutocomplete(
                suggestions: suggestions,
                selectedIndex: selectedIndex,
                cursorPosition: Offset.zero,
                title: title,
                onDismiss: onDismiss ?? () {},
                onSelected: onSelected ?? (_) {},
                onSelectionChanged: onSelectionChanged ?? (_) {},
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('renders Mongo title when provided', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          title: 'Mongo Autocomplete',
          suggestions: [Suggestion(text: 'find', type: SuggestionType.method)],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mongo Autocomplete'), findsOneWidget);
      expect(find.text('1 items'), findsOneWidget);
    });

    testWidgets('renders Mongo suggestion type labels', (tester) async {
      await tester.pumpWidget(
        buildWidget(
          title: 'Mongo Autocomplete',
          suggestions: [
            Suggestion(text: 'users', type: SuggestionType.collection),
            Suggestion(text: 'name', type: SuggestionType.field),
            Suggestion(text: 'find', type: SuggestionType.method),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COLLECTION'), findsOneWidget);
      expect(find.text('FIELD'), findsOneWidget);
      expect(find.text('METHOD'), findsOneWidget);
      expect(find.text('users'), findsOneWidget);
      expect(find.text('name'), findsOneWidget);
      expect(find.text('find'), findsOneWidget);
    });

    testWidgets('selecting a suggestion invokes onSelected', (tester) async {
      Suggestion? selected;
      await tester.pumpWidget(
        buildWidget(
          title: 'Mongo Autocomplete',
          suggestions: [
            Suggestion(text: 'find', type: SuggestionType.method),
            Suggestion(text: 'aggregate', type: SuggestionType.method),
          ],
          onSelected: (s) => selected = s,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('aggregate'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.text, 'aggregate');
      expect(selected!.type, SuggestionType.method);
    });

    testWidgets('returns empty SizedBox when suggestions are empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget(suggestions: const []));
      await tester.pumpAndSettle();

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('SQL Autocomplete'), findsNothing);
    });

    testWidgets('dismiss gesture is available', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        buildWidget(
          title: 'Mongo Autocomplete',
          suggestions: [Suggestion(text: 'find', type: SuggestionType.method)],
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      // The translucent overlay captures taps outside the popup.
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });
}
