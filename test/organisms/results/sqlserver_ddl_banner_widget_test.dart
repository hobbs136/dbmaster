import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/results/safety_warning_banner.dart';

/// Widget tests for the DDL/DML safety confirmation banner.
///
/// Verifies that destructive SQL statements trigger a banner with
/// Confirm, Add Limit, and Cancel actions (TC-SS-QRY-002).
/// C22 M2：按钮文案 l10n 化后经 AppLocalizations 断言（默认 en locale）。
void main() {
  group('SafetyWarningBanner', () {
    testWidgets(
      'renders Confirm, Add Limit, and Cancel actions for DDL statements',
      (tester) async {
        var confirmed = false;
        var cancelled = false;
        var addLimitCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SafetyWarningBanner(
                warningText:
                    'This statement will modify the database structure.',
                detailText: 'CREATE TABLE t_ddl_test (id INT)',
                onConfirm: () => confirmed = true,
                onAddLimit: () => addLimitCalled = true,
                onCancel: () => cancelled = true,
                cooldownSeconds: 0,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        // Wait for the confirm-button cooldown to expire.
        await tester.pump(const Duration(seconds: 2));

        final l10n = AppLocalizations.of(
          tester.element(find.byType(SafetyWarningBanner)),
        )!;

        expect(
          find.text('This statement will modify the database structure.'),
          findsOneWidget,
        );
        expect(find.textContaining('CREATE TABLE t_ddl_test'), findsOneWidget);

        // The banner should expose all three actions (l10n 文案)。
        expect(find.text(l10n.commonConfirm), findsOneWidget);
        expect(find.text(l10n.safetyBannerAddLimit), findsOneWidget);
        expect(find.text(l10n.commonCancel), findsOneWidget);

        await tester.tap(find.text(l10n.commonCancel));
        await tester.pumpAndSettle();
        expect(cancelled, isTrue);
        expect(confirmed, isFalse);
        expect(addLimitCalled, isFalse);
      },
    );

    testWidgets('cooldown 期间确认按钮显示倒计时并禁用', (tester) async {
      var confirmed = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SafetyWarningBanner(
              warningText: 'w',
              onConfirm: () => confirmed = true,
              onCancel: () {},
              cooldownSeconds: 3,
            ),
          ),
        ),
      );
      await tester.pump();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(SafetyWarningBanner)),
      )!;
      // 倒计时文案（C22 M2：l10n 占位键）。
      expect(find.text(l10n.safetyBannerCooldown(3)), findsOneWidget);
      await tester.tap(find.text(l10n.safetyBannerCooldown(3)));
      await tester.pump();
      expect(confirmed, isFalse, reason: '冷却期内点击确认不应触发回调');
    });
  });
}
