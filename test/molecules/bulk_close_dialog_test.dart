import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/molecules/bulk_close_dialog.dart';
import 'package:dbmaster/providers/bulk_close_controller.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

MaterialApp _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('BulkCloseDialog', () {
    late QueryTab tabA;
    late QueryTab tabB;

    setUp(() {
      tabA = QueryTab(id: 'a', title: 'Tab A', sql: 'SELECT 1');
      tabB = QueryTab(id: 'b', title: 'Tab B', sql: 'SELECT 2 FROM users');
    });

    testWidgets('shows save-all, discard-all, and cancel buttons', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(BulkCloseDialog(tabs: [tabA, tabB])));
      await tester.pumpAndSettle();

      expect(find.text('Save All'), findsOneWidget);
      expect(find.text('Discard All'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('lists all unsaved tabs with title and snippet', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(BulkCloseDialog(tabs: [tabA, tabB])));
      await tester.pumpAndSettle();

      expect(find.text('Tab A'), findsOneWidget);
      expect(find.text('Tab B'), findsOneWidget);
      expect(find.text('SELECT 2 FROM users'), findsOneWidget);
    });

    testWidgets('renders without null errors for three unsaved tabs', (
      tester,
    ) async {
      final tabC = QueryTab(id: 'c', title: 'Tab C', sql: 'SELECT 3');

      await tester.pumpWidget(_wrap(BulkCloseDialog(tabs: [tabA, tabB, tabC])));
      await tester.pumpAndSettle();

      expect(find.text('Tab A'), findsOneWidget);
      expect(find.text('Tab B'), findsOneWidget);
      expect(find.text('Tab C'), findsOneWidget);
      expect(find.text('Save All'), findsOneWidget);
      expect(find.text('Discard All'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('cancel returns confirmed=false', (tester) async {
      BulkCloseResult? result;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await showBulkCloseDialog(context, tabs: [tabA]);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.confirmed, isFalse);
    });

    testWidgets('single unsaved tab renders without null errors', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(BulkCloseDialog(tabs: [tabA])));
      await tester.pumpAndSettle();

      expect(find.text('Tab A'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Save All'), findsOneWidget);
      expect(find.text('Discard All'), findsOneWidget);
    });

    testWidgets('discard all returns all discard decisions', (tester) async {
      BulkCloseResult? result;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await showBulkCloseDialog(context, tabs: [tabA, tabB]);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard All'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.confirmed, isTrue);
      expect(result!.decisions['a'], BulkCloseDecision.discard);
      expect(result!.decisions['b'], BulkCloseDecision.discard);
    });

    testWidgets('save all returns all save decisions', (tester) async {
      BulkCloseResult? result;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await showBulkCloseDialog(context, tabs: [tabA, tabB]);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save All'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.confirmed, isTrue);
      expect(result!.decisions['a'], BulkCloseDecision.save);
      expect(result!.decisions['b'], BulkCloseDecision.save);
    });

    testWidgets('bulk actions apply consistently to three tabs', (tester) async {
      final tabC = QueryTab(id: 'c', title: 'Tab C', sql: 'SELECT 3');
      BulkCloseResult? result;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await showBulkCloseDialog(
                    context,
                    tabs: [tabA, tabB, tabC],
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard All'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.confirmed, isTrue);
      expect(result!.decisions.length, 3);
      expect(result!.decisions['a'], BulkCloseDecision.discard);
      expect(result!.decisions['b'], BulkCloseDecision.discard);
      expect(result!.decisions['c'], BulkCloseDecision.discard);
    });

    testWidgets('per-tab decision chips override bulk decision', (tester) async {
      BulkCloseResult? result;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await showBulkCloseDialog(context, tabs: [tabA, tabB]);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Mark tab A to save and tab B to discard.
      final saveChips = find.text('Save');
      final discardChips = find.text('Discard');
      expect(saveChips, findsNWidgets(2));
      expect(discardChips, findsNWidgets(2));

      await tester.tap(saveChips.first);
      await tester.pumpAndSettle();
      await tester.tap(discardChips.last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save All'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.confirmed, isTrue);
      expect(result!.decisions['a'], BulkCloseDecision.save);
      expect(result!.decisions['b'], BulkCloseDecision.discard);
    });
  });
}
