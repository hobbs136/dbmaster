import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/molecules/tab_close_confirm_dialog.dart';
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
  testWidgets('shows single-tab semantics: title, message with tab title, and save/discard/cancel', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const TabCloseConfirmDialog(tabTitle: 'Query 1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unsaved Changes'), findsOneWidget);
    expect(
      find.text('Do you want to save the changes made to "Query 1" before closing?'),
      findsOneWidget,
    );
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // 单 Tab 语义：不应出现批量弹框的「全部」级按钮。
    expect(find.text('Save All'), findsNothing);
    expect(find.text('Discard All'), findsNothing);
  });

  testWidgets('save returns TabCloseDecision.save', (tester) async {
    TabCloseDecision? decision;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                decision = await showTabCloseConfirmDialog(
                  context,
                  tabTitle: 'Query 1',
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(decision, TabCloseDecision.save);
  });

  testWidgets('discard returns TabCloseDecision.discard', (tester) async {
    TabCloseDecision? decision;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                decision = await showTabCloseConfirmDialog(
                  context,
                  tabTitle: 'Query 1',
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(decision, TabCloseDecision.discard);
  });

  testWidgets('cancel returns null and keeps tab open in caller terms', (
    tester,
  ) async {
    TabCloseDecision? decision;

    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                decision = await showTabCloseConfirmDialog(
                  context,
                  tabTitle: 'Query 1',
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(decision, isNull);
  });
}
