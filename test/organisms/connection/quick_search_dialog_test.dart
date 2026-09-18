// Regression tests for the Ctrl+N / Ctrl+K Windows hang (hotfix
// ctrl-n-hang-windows). The QuickSearchDialog used to (a) throw a debug
// `Container(color + decoration)` assertion and (b) share one FocusNode across
// a deprecated KeyboardListener and the TextField, which triggered a Windows
// focus/IME feedback loop in release. These tests lock in the fix.
//
// The Ctrl+N/Ctrl+K -> handler -> dialog wiring is already covered by
// test/core/shortcuts/global_shortcuts_test.dart; here we verify the dialog
// itself builds cleanly and that key handling still works after the
// KeyboardListener -> FocusNode.onKeyEvent refactor.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/core/shortcuts/global_shortcuts_wrapper.dart';
import 'package:dbmaster/organisms/connection/quick_search_dialog.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/task_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  /// Minimal harness mirroring test/core/shortcuts/global_shortcuts_test.dart.
  /// Does NOT pump the full DbmasterApp (would hit Pigeon in_app_purchase
  /// channels and hang flutter_test).
  Future<BuildContext> pumpApp(WidgetTester tester) async {
    tester.binding.setSurfaceSize(const Size(1920, 1080));
    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    final layoutProvider = LayoutPreferencesProvider();
    final taskProvider = TaskProvider();
    await themeProvider.load();
    await localeProvider.load();
    await layoutProvider.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TaskProvider>.value(value: taskProvider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layoutProvider,
          ),
          ChangeNotifierProxyProvider<TaskProvider, AppProvider>(
            create: (_) => AppProvider(),
            update: (_, task, app) {
              if (app == null) return AppProvider(taskProvider: task);
              app.updateTaskProvider(task);
              return app;
            },
          ),
        ],
        child: Consumer2<LocaleProvider, ThemeProvider>(
          builder: (context, locale, theme, _) {
            return MaterialApp(
              locale: locale.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(theme.accentColorValue),
              home: const Scaffold(
                body: GlobalShortcutsWrapper(child: SizedBox.expand()),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Context below MaterialApp's Localizations, suitable for showDialog.
    return tester.element(find.byType(GlobalShortcutsWrapper));
  }

  // Regression: the dialog must build WITHOUT the prior
  // `Container(color + decoration)` assertion (container.dart:277). Before the
  // fix this threw in debug and aborted the build — masking the release hang.
  testWidgets('HOTFIX-CTRLN-1: dialog builds with no Container assertion',
      (tester) async {
    final ctx = await pumpApp(tester);

    QuickSearchDialog.show(ctx);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      tester.takeException(),
      isNull,
      reason: 'QuickSearchDialog must build without the color+decoration '
          'assertion (the debug gate that masked the Windows release hang).',
    );
    expect(find.byType(QuickSearchDialog), findsOneWidget);
  });

  // Regression: after the focus refactor (onKeyEvent on the FocusNode instead
  // of a deprecated KeyboardListener wrapper), list-navigation keys still
  // route to _onKeyEvent without throwing.
  testWidgets('HOTFIX-CTRLN-2: arrow-key navigation reaches onKeyEvent',
      (tester) async {
    final ctx = await pumpApp(tester);

    QuickSearchDialog.show(ctx);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(QuickSearchDialog), findsOneWidget);
    tester.takeException(); // drain

    // The TextField's FocusNode has focus; arrow keys must be handled by
    // _onKeyEvent (handled -> no caret move) without throwing.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'Arrow keys must route via FocusNode.onKeyEvent without '
            'crashing after the KeyboardListener removal.');
    expect(find.byType(QuickSearchDialog), findsOneWidget);
  });
}
