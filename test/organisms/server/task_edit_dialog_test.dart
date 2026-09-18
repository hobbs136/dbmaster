//! Widget tests for [TaskEditDialog] (#27). Verifies field prefill, onPatch
//! submission wiring, cron-required validation (health), scheduleField.none
//! hiding the cron field (drift), and cronOptional allowing empty (data_sync).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/server/task_edit_dialog.dart';

void main() {
  // Common MaterialApp shell with l10n wired (TaskEditDialog reads
  // AppLocalizations.of(context)! for every label).
  Widget harness({required void Function(BuildContext) open}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () => open(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  group('TaskEditDialog', () {
    testWidgets('prefills fields and submits via onPatch (cron mode)',
        (tester) async {
      Map<String, dynamic>? captured;
      await tester.pumpWidget(harness(open: (ctx) => showTaskEditDialog(
            ctx,
            taskName: 'my task',
            initialEnabled: true,
            scheduleField: TaskScheduleField.cron,
            initialCronExpr: '*/5 * * * *',
            initialWebhook: 'https://hook.example/x',
            onPatch: ({enabled, name, cronExpr, notifyChannels}) async {
              captured = {
                if (enabled != null) 'enabled': enabled,
                if (name != null) 'name': name,
                if (cronExpr != null) 'cron_expr': cronExpr,
                if (notifyChannels != null) 'notify_channels': notifyChannels,
              };
              return {'id': 't1', 'name': name};
            },
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Prefilled values visible in the text fields.
      expect(find.text('my task'), findsOneWidget);
      expect(find.text('*/5 * * * *'), findsOneWidget);
      expect(find.text('https://hook.example/x'), findsOneWidget);

      // Submit (Save Changes button).
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!['name'], equals('my task'));
      expect(captured!['enabled'], isTrue);
      expect(captured!['cron_expr'], equals('*/5 * * * *'));
      expect(captured!['notify_channels'], equals(['https://hook.example/x']));
    });

    testWidgets('cron required blocks submit when empty (health)',
        (tester) async {
      var submitted = false;
      await tester.pumpWidget(harness(open: (ctx) => showTaskEditDialog(
            ctx,
            taskName: 't',
            initialEnabled: true,
            scheduleField: TaskScheduleField.cron,
            initialCronExpr: '', // empty → invalid for health (cron required)
            onPatch: ({enabled, name, cronExpr, notifyChannels}) async {
              submitted = true;
              return {};
            },
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Validator rejected the empty cron → onPatch never called.
      expect(submitted, isFalse);
      // taskEditInvalidCron error text rendered under the cron field.
      expect(find.text('Enter 5 space-separated fields'), findsOneWidget);
    });

    testWidgets('scheduleField.none hides cron field (drift)',
        (tester) async {
      await tester.pumpWidget(harness(open: (ctx) => showTaskEditDialog(
            ctx,
            taskName: 'drift task',
            initialEnabled: true,
            scheduleField: TaskScheduleField.none,
            onPatch: ({enabled, name, cronExpr, notifyChannels}) async => {},
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // No cron field: only name + webhook TextFormFields (2 total).
      expect(find.byType(TextFormField), findsNWidgets(2));
      // Cron helper hint absent.
      expect(find.textContaining('minute hour day'), findsNothing);
    });

    testWidgets('scheduleField.cronOptional allows empty cron (data_sync)',
        (tester) async {
      var submitted = false;
      await tester.pumpWidget(harness(open: (ctx) => showTaskEditDialog(
            ctx,
            taskName: 'sync task',
            initialEnabled: true,
            scheduleField: TaskScheduleField.cronOptional,
            initialCronExpr: '', // empty OK for data_sync (run-once)
            onPatch: ({enabled, name, cronExpr, notifyChannels}) async {
              submitted = true;
              return {};
            },
          )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Empty cron accepted for cronOptional → submit fires.
      expect(submitted, isTrue);
    });
  });
}
