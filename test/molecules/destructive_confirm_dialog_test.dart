import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/atoms/app_loading.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/molecules/destructive_confirm_dialog.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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

Widget _dialog({
  VoidCallback? onConfirm,
  String? impactDescription = 'This operation cannot be undone.',
  String? requireTypedConfirmation,
}) {
  return DestructiveConfirmDialog(
    icon: LucideIcons.triangleAlert,
    title: 'Delete Table',
    impactDescription: impactDescription,
    impactTone: DestructiveTone.error,
    confirmLabel: 'Delete',
    onConfirm: onConfirm ?? () {},
    requireTypedConfirmation: requireTypedConfirmation,
  );
}

/// 用例登记：10.2 — UM-DEST-001..006
void main() {
  group('DestructiveConfirmDialog', () {
    testWidgets(
      'UM-DEST-001 renders icon, title, impact text and both buttons',
      (tester) async {
        await tester.pumpWidget(_wrap(_dialog()));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
        expect(find.text('Delete Table'), findsOneWidget);
        expect(find.text('This operation cannot be undone.'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        // 确认钮走契约 C2 的 LoadingButton 层
        expect(find.byType(LoadingButton), findsOneWidget);
      },
    );

    testWidgets('UM-DEST-002 cancel button sits left of confirm button', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(_dialog()));
      await tester.pumpAndSettle();

      final cancelX = tester.getCenter(find.text('Cancel')).dx;
      final confirmX = tester.getCenter(find.text('Delete')).dx;
      expect(cancelX, lessThan(confirmX));
    });

    testWidgets('UM-DEST-003 tapping confirm fires onConfirm', (tester) async {
      var confirmed = 0;
      await tester.pumpWidget(_wrap(_dialog(onConfirm: () => confirmed++)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(confirmed, 1);
    });

    testWidgets('UM-DEST-004 cancel pops the dialog with false', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => _dialog(),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });

    testWidgets(
      'UM-DEST-005 requireTypedConfirmation keeps confirm disabled until '
      'the typed text matches case-insensitively',
      (tester) async {
        var confirmed = 0;
        await tester.pumpWidget(
          _wrap(
            _dialog(
              onConfirm: () => confirmed++,
              requireTypedConfirmation: 'my_table',
            ),
          ),
        );
        await tester.pumpAndSettle();

        ElevatedButton confirmButton() => tester.widget<ElevatedButton>(
          find.descendant(
            of: find.byType(LoadingButton),
            matching: find.byType(ElevatedButton),
          ),
        );

        // 初始：确认钮禁用
        expect(confirmButton().onPressed, isNull);

        // 输入不匹配文本：仍禁用
        await tester.enterText(find.byType(TextField), 'other_table');
        await tester.pump();
        expect(confirmButton().onPressed, isNull);

        // 输入匹配文本（大小写不敏感）：解禁并可触发
        await tester.enterText(find.byType(TextField), 'MY_TABLE');
        await tester.pump();
        expect(confirmButton().onPressed, isNotNull);

        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(confirmed, 1);
      },
    );

    testWidgets(
      'UM-DEST-006 hides the impact container when impactDescription is null',
      (tester) async {
        await tester.pumpWidget(_wrap(_dialog(impactDescription: null)));
        await tester.pumpAndSettle();

        expect(find.text('This operation cannot be undone.'), findsNothing);
        expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
      },
    );
  });
}
