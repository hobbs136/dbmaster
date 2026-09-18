import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/table_maintenance_command.dart';
import 'package:dbmaster/organisms/dialogs/confirm_maintenance_dialog.dart';
import 'package:dbmaster/organisms/dialogs/table_maintenance_result_dialog.dart';

void main() {
  group('ConfirmMaintenanceDialog', () {
    testWidgets('displays analyze confirmation and returns true on confirm', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ConfirmMaintenanceDialog(
                    tableName: 'users',
                    command: TableMaintenanceCommand.analyze,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Analyze Table users'), findsOneWidget);
      expect(find.textContaining('update index statistics'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('displays optimize warning and returns false on cancel', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ConfirmMaintenanceDialog(
                    tableName: 'users',
                    command: TableMaintenanceCommand.optimize,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Optimize Table users'), findsOneWidget);
      expect(find.textContaining('lock the table'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets('displays check confirmation', (tester) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ConfirmMaintenanceDialog(
                    tableName: 'users',
                    command: TableMaintenanceCommand.check,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Check Table users'), findsOneWidget);
      expect(find.textContaining('check table'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });
  });

  group('TableMaintenanceResultDialog', () {
    testWidgets('displays executed SQL and result rows', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const TableMaintenanceResultDialog(
                    tableName: 'users',
                    command: TableMaintenanceCommand.analyze,
                    sql: 'ANALYZE TABLE `db`.`users`',
                    results: [
                      {
                        'Table': 'db.users',
                        'Op': 'analyze',
                        'Msg_type': 'status',
                        'Msg_text': 'OK',
                      },
                    ],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('ANALYZE TABLE `db`.`users`'), findsOneWidget);
      expect(find.text('status'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('displays no information when results are empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => const TableMaintenanceResultDialog(
                    tableName: 'users',
                    command: TableMaintenanceCommand.check,
                    sql: 'CHECK TABLE `db`.`users`',
                    results: [],
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('No information'), findsOneWidget);
    });
  });
}
