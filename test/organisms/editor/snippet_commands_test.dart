import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/editor/snippet_commands.dart';
import 'package:dbmaster/models/code_snippet.dart' show SnippetDbFamily;

void main() {
  group('SnippetCommands family (US3)', () {
    test('Mongo commands present and tagged mongodb', () {
      final mongo = SnippetCommands.commands
          .where((c) => c.family == SnippetDbFamily.mongodb)
          .toList();
      expect(mongo.any((c) => c.command == 'mfind'), isTrue);
      expect(mongo.any((c) => c.command == 'magg'), isTrue);
      expect(mongo.any((c) => c.command == 'midx'), isTrue);
      expect(mongo.length, greaterThanOrEqualTo(7));
    });

    test('SQL commands default to sql family', () {
      final sql = SnippetCommands.commands
          .where((c) => c.family == SnippetDbFamily.sql)
          .toList();
      expect(sql.any((c) => c.command == 'sel'), isTrue);
      expect(sql.any((c) => c.command == 'ins'), isTrue);
    });

    test('no command left in all family', () {
      expect(
        SnippetCommands.commands
            .where((c) => c.family == SnippetDbFamily.all)
            .length,
        0,
      );
    });
  });

  group('SnippetCommandsOverlay (020-mongo UI)', () {
    Widget buildOverlay({
      String filter = '',
      SnippetDbFamily? currentFamily,
      ValueChanged<SnippetCommand>? onSelected,
      VoidCallback? onDismiss,
    }) {
      TestWidgetsFlutterBinding.ensureInitialized();
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Stack(
            children: [
              SnippetCommandsOverlay(
                filter: filter,
                cursorPosition: Offset.zero,
                currentFamily: currentFamily,
                onSelected: onSelected ?? (_) {},
                onDismiss: onDismiss ?? () {},
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('with mongodb family only shows Mongo commands', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildOverlay(currentFamily: SnippetDbFamily.mongodb),
      );
      await tester.pumpAndSettle();

      expect(find.text('/mfind'), findsOneWidget);
      expect(find.text('/sel'), findsNothing);
      expect(find.text('/ins'), findsNothing);
    });

    testWidgets('with sql family only shows SQL commands', (tester) async {
      await tester.pumpWidget(buildOverlay(currentFamily: SnippetDbFamily.sql));
      await tester.pumpAndSettle();

      expect(find.text('/sel'), findsOneWidget);
      expect(find.text('/ins'), findsOneWidget);
      expect(find.text('/mfind'), findsNothing);
      expect(find.text('/magg'), findsNothing);
    });

    testWidgets('with null family shows all commands', (tester) async {
      await tester.pumpWidget(buildOverlay());
      await tester.pumpAndSettle();

      expect(find.text('/sel'), findsOneWidget);
      // Total command count label reflects all commands.
      expect(
        find.text('${SnippetCommands.commands.length} items'),
        findsOneWidget,
      );

      // Mongo commands are below the fold; scroll the overlay list to reveal.
      await tester.scrollUntilVisible(
        find.text('/mfind'),
        80,
        scrollable: find.descendant(
          of: find.byType(SnippetCommandsOverlay),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('/mfind'), findsOneWidget);
    });

    testWidgets('filter narrows visible commands', (tester) async {
      await tester.pumpWidget(
        buildOverlay(filter: 'mfind', currentFamily: SnippetDbFamily.mongodb),
      );
      await tester.pumpAndSettle();

      expect(find.text('/mfind'), findsOneWidget);
      expect(find.text('/magg'), findsNothing);
    });

    testWidgets('selecting a command invokes onSelected', (tester) async {
      SnippetCommand? selected;
      await tester.pumpWidget(
        buildOverlay(
          currentFamily: SnippetDbFamily.mongodb,
          onSelected: (c) => selected = c,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('/mfind'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.command, 'mfind');
      expect(selected!.family, SnippetDbFamily.mongodb);
    });

    testWidgets('dismiss gesture is available', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        buildOverlay(
          currentFamily: SnippetDbFamily.mongodb,
          onDismiss: () => dismissed = true,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    });
  });
}
