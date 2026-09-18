import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/organisms/connection/settings_dialog.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';

// ============================================================================
// i18n Overflow Detection Tests
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Helper to detect layout overflow in a widget tree.
  Future<void> expectNoOverflow(
    WidgetTester tester,
    Widget widget, {
    Size viewportSize = const Size(900, 700),
  }) async {
    FlutterErrorDetails? capturedError;
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('overflowed by') || msg.contains('Overflow')) {
        capturedError = details;
      }
      // Don't print to console to keep test output clean
    };

    await tester.binding.setSurfaceSize(viewportSize);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();

    FlutterError.onError = originalOnError;

    if (capturedError != null) {
      fail('Layout overflow detected:\n${capturedError!.exceptionAsString()}');
    }
  }

  group('MAN-I18N-001~007: 多语言界面溢出检测', () {
    for (final locale in LocaleProvider.supportedLocales) {
      testWidgets('SettingsDialog 在 ${locale.toLanguageTag()} 下无溢出', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        final appProvider = AppProvider();
        final localeProvider = LocaleProvider();
        await localeProvider.load();
        final themeProvider = ThemeProvider();
        await themeProvider.load();

        await expectNoOverflow(
          tester,
          MultiProvider(
            providers: [
              ChangeNotifierProvider<AppProvider>.value(value: appProvider),
              ChangeNotifierProvider<LocaleProvider>.value(
                value: localeProvider,
              ),
              ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
              Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: locale,
              home: const Scaffold(body: Center(child: Text('Trigger'))),
            ),
          ),
        );

        // Open the settings dialog
        showDialog(
          context: tester.element(find.text('Trigger')),
          builder: (_) => const SettingsDialog(),
        );
        await tester.pumpAndSettle();

        // The dialog should render without throwing overflow
        expect(find.byType(SettingsDialog), findsOneWidget);
      });
    }
  });

  group('MAN-I18N: 语言切换验证', () {
    testWidgets('LocaleProvider 支持全部 6 种语言切换', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final localeProvider = LocaleProvider();
      await localeProvider.load();

      await tester.pumpWidget(
        ChangeNotifierProvider<LocaleProvider>.value(
          value: localeProvider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: localeProvider.locale,
            home: const Scaffold(body: Center(child: Text('Home'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final locale in LocaleProvider.supportedLocales) {
        await localeProvider.setLocale(locale);
        await tester.pumpAndSettle();

        expect(
          localeProvider.locale,
          locale,
          reason: '应成功切换到 ${locale.toLanguageTag()}',
        );
      }
    });

    testWidgets('不支持的语 locale 应被忽略', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final localeProvider = LocaleProvider();
      await localeProvider.load();

      final originalLocale = localeProvider.locale;
      await localeProvider.setLocale(const Locale('ja'));

      expect(
        localeProvider.locale,
        originalLocale,
        reason: '不支持的 locale 不应改变当前语言',
      );
    });
  });
}
