import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_panel/confirm_execute_dialog.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void _setLargeScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<ConfirmResult?> _showDialog(
  WidgetTester tester, {
  required String command,
  String? warningReason,
}) async {
  ConfirmResult? result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<ConfirmResult>(
              context: context,
              builder: (_) => ConfirmExecuteDialog(
                command: command,
                warningReason: warningReason,
                l10n: AppLocalizations.of(context)!,
              ),
            );
          },
          child: const Text('Show'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Show'));
  await tester.pumpAndSettle();

  return result;
}

void main() {
  group('ConfirmExecuteDialog', () {
    testWidgets('renders command text', (tester) async {
      _setLargeScreen(tester);
      await _showDialog(tester, command: 'SELECT * FROM users');

      expect(find.text('SELECT * FROM users'), findsOneWidget);
    });

    testWidgets('dangerous operation shows warning reason', (tester) async {
      _setLargeScreen(tester);
      await _showDialog(
        tester,
        command: 'DROP TABLE users',
        warningReason: 'Destructive operation detected',
      );

      expect(find.text('Destructive operation detected'), findsOneWidget);
      expect(find.byIcon(LucideIcons.triangleAlert), findsWidgets);
    });

    testWidgets('cancel button returns ConfirmResult.cancel', (tester) async {
      _setLargeScreen(tester);
      final result = await _showDialog(tester, command: 'SELECT 1');
      expect(result, isNull);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('confirm button returns ConfirmResult.allowOnce', (
      tester,
    ) async {
      _setLargeScreen(tester);
      ConfirmResult? capturedResult;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                capturedResult = await showDialog<ConfirmResult>(
                  context: context,
                  builder: (_) => ConfirmExecuteDialog(
                    command: 'SELECT 1',
                    l10n: AppLocalizations.of(context)!,
                  ),
                );
              },
              child: const Text('Show'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm Execute'));
      await tester.pumpAndSettle();

      expect(capturedResult, ConfirmResult.allowOnce);
    });
  });
}
