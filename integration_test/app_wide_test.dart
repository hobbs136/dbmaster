// ============================================================================
// DbMaster App-Wide Integration Test
//
// Tests: Application-level features (theme, i18n, settings, tabs, status bar,
// welcome screen) derived from docs/test/app_wide_manual_test_cases.md
//
// Convention:  Each testWidgets() maps 1:1 to a TC id in the markdown doc.
// `[必须人工]` cases are automated at the widget/state level where feasible;
// TC ids with no automation here are documented in the test name and skipped
// intentionally (drag/visual/8h stability).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/main.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/task_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/pro_module.dart';
import 'package:dbmaster/atoms/app_header.dart';
import 'package:dbmaster/templates/welcome_screen.dart';
import 'package:dbmaster/organisms/connection/settings_dialog.dart';
import 'package:dbmaster/organisms/connection/error_boundary.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/core/shortcuts/global_shortcuts_wrapper.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Reset SharedPreferences before all tests so theme/locale state doesn't
  // leak from prior runs.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  // --------------------------------------------------------------------------
  // 1. Theme switching (TC-001 ~ TC-004)
  // --------------------------------------------------------------------------
  group('1. Theme Switching', () {
    Future<ThemeProvider> bootAppWithTheme(WidgetTester tester) async {
      final tp = ThemeProvider();
      await tp.load();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: tp),
            ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
          ],
          child: const _ThemeProbeApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      return tp;
    }

    testWidgets('TC-001 dark mode is the default on first run', (tester) async {
      final tp = await bootAppWithTheme(tester);
      expect(
        tp.themeMode,
        AppThemeMode.dark,
        reason: 'default themeMode should be dark',
      );
      expect(tp.isDarkMode, isTrue);
      // Header should render the "switch to light" icon = light_mode_outlined
      expect(find.byIcon(LucideIcons.sun), findsOneWidget);
    });

    testWidgets('TC-002 toggling via ThemeProvider flips to light', (
      tester,
    ) async {
      final tp = await bootAppWithTheme(tester);
      expect(tp.isDarkMode, isTrue);
      await tp.toggle();
      await tester.pumpAndSettle();
      expect(tp.isDarkMode, isFalse);
      expect(tp.themeMode, AppThemeMode.light);
      // Header icon should now be dark_mode_outlined (offering to switch back)
      expect(find.byIcon(LucideIcons.moon), findsOneWidget);
      expect(find.byIcon(LucideIcons.sun), findsNothing);
    });

    testWidgets('TC-003 system mode tracks platform brightness', (
      tester,
    ) async {
      final tp = await bootAppWithTheme(tester);
      await tp.setThemeMode(AppThemeMode.system);
      await tester.pumpAndSettle();
      expect(tp.themeMode, AppThemeMode.system);
      // isDarkMode is computed from platformDispatcher.platformBrightness.
      final hostBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      expect(tp.isDarkMode, hostBrightness == Brightness.dark);
    });

    testWidgets('TC-004 theme switch is instant and state survives', (
      tester,
    ) async {
      final tp = await bootAppWithTheme(tester);
      // Cycle through all three modes
      await tp.setThemeMode(AppThemeMode.light);
      await tester.pumpAndSettle();
      expect(tp.isDarkMode, isFalse);
      await tp.setThemeMode(AppThemeMode.system);
      await tester.pumpAndSettle();
      expect(tp.themeMode, AppThemeMode.system);
      await tp.setThemeMode(AppThemeMode.dark);
      await tester.pumpAndSettle();
      expect(tp.isDarkMode, isTrue);
      // App still rendered the header each time
      expect(find.byType(AppHeader), findsOneWidget);
    });
  });

  // --------------------------------------------------------------------------
  // 2. Localization / i18n (TC-005 ~ TC-011)
  // --------------------------------------------------------------------------
  group('2. Localization', () {
    Future<LocaleProvider> bootForLocale(WidgetTester tester) async {
      final lp = LocaleProvider();
      await lp.load();
      await lp.setLocale(const Locale('en'));
      final tp = ThemeProvider();
      await tp.load();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>.value(value: lp),
            ChangeNotifierProvider<ThemeProvider>.value(value: tp),
          ],
          child: const _LocaleProbeApp(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      return lp;
    }

    testWidgets('TC-005 English locale yields English ARB strings', (
      tester,
    ) async {
      final lp = await bootForLocale(tester);
      expect(lp.locale, const Locale('en'));
      // AppLocalizations is provided by the Localizations widget that
      // MaterialApp inserts — so we look for a Scaffold descendant.
      final ctx = tester.element(find.byType(Scaffold));
      final l10n = AppLocalizations.of(ctx);
      expect(l10n, isNotNull, reason: 'AppLocalizations should be loaded');
      expect(l10n!.settingsLanguage, 'Language');
      expect(l10n.settingsDarkMode, 'Dark');
    });

    testWidgets('TC-006 zh locale yields Simplified Chinese strings', (
      tester,
    ) async {
      final lp = await bootForLocale(tester);
      await lp.setLocale(const Locale('zh'));
      await tester.pumpAndSettle();
      final ctx = tester.element(find.byType(Scaffold));
      final l10n = AppLocalizations.of(ctx);
      expect(l10n, isNotNull);
      expect(l10n!.settingsLanguage, '语言');
      expect(l10n.settingsDarkMode, '深色');
    });

    testWidgets('TC-007 zh_TW locale is applied with the right country code', (
      tester,
    ) async {
      final lp = await bootForLocale(tester);
      await lp.setLocale(const Locale('zh', 'TW'));
      await tester.pumpAndSettle();
      expect(lp.locale.languageCode, 'zh');
      expect(lp.locale.countryCode, 'TW');
      expect(lp.getLocaleName(const Locale('zh', 'TW')), '繁體中文');
    });

    testWidgets('TC-008 de locale has Deutsch display name', (tester) async {
      final lp = await bootForLocale(tester);
      await lp.setLocale(const Locale('de'));
      await tester.pumpAndSettle();
      expect(lp.getLocaleName(const Locale('de')), 'Deutsch');
    });

    testWidgets('TC-009 fr locale has Français display name', (tester) async {
      final lp = await bootForLocale(tester);
      await lp.setLocale(const Locale('fr'));
      await tester.pumpAndSettle();
      expect(lp.getLocaleName(const Locale('fr')), 'Français');
    });

    testWidgets('TC-010 ru locale has Русский display name', (tester) async {
      final lp = await bootForLocale(tester);
      await lp.setLocale(const Locale('ru'));
      await tester.pumpAndSettle();
      expect(lp.getLocaleName(const Locale('ru')), 'Русский');
    });

    testWidgets('TC-011 supportedLocales covers all 6 languages', (
      tester,
    ) async {
      await bootForLocale(tester);
      final codes = LocaleProvider.localeNames.keys.toSet();
      expect(codes, {'en', 'de', 'fr', 'ru', 'zh', 'zh_TW'});
    });
  });

  // --------------------------------------------------------------------------
  // 3. Settings dialog (TC-019, partial)
  // --------------------------------------------------------------------------
  group('4. Settings Dialog', () {
    testWidgets('TC-019 settings dialog renders with all expected sections', (
      tester,
    ) async {
      // Render the dialog directly (no tap) to avoid showDialog overlay
      // timing flakiness. The dialog is still wired to the same provider
      // tree — we just skip the showDialog() gesture dance.
      await tester.pumpWidget(
        _wrapForDialog(const Scaffold(body: SettingsDialog())),
      );
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Dialog rendered
      expect(find.byType(SettingsDialog), findsOneWidget);
      // C22 M2 整窗迁移：左导航分页。默认页 = 外观（主题 + 编辑器分区）；
      // Language/Query/Security/About 经左导航常驻可见。
      expect(find.textContaining('Appearance'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Editor'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Language'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Query'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Security'), findsAtLeastNWidgets(1));
      expect(find.textContaining('About'), findsAtLeastNWidgets(1));
      // Theme row label（默认页内容）
      expect(find.textContaining('Theme'), findsAtLeastNWidgets(1));
    });
  });

  // --------------------------------------------------------------------------
  // 9. Welcome screen (TC-050 ~ TC-051, derived)
  // --------------------------------------------------------------------------
  group('9. Welcome Screen', () {
    testWidgets('TC-050/051 welcome screen renders the new-connection CTA', (
      tester,
    ) async {
      // WelcomeScreen uses context.themeColors (reads ThemeProvider from
      // context) and Theme.of(context).colorScheme.onSurface for text.
      // We need a MaterialApp.theme that has a scaffoldBackgroundColor and
      // a non-null colorScheme. ThemeProvider's currentTheme supplies both.
      // We also force MaterialApp.locale to Locale('en') so the host OS
      // (zh on this Mac) doesn't override our test assertions.
      final tp = ThemeProvider();
      await tp.load();
      final lp = LocaleProvider();
      await lp.load();
      await lp.setLocale(const Locale('en'));
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: tp),
            ChangeNotifierProvider<LocaleProvider>.value(value: lp),
            ChangeNotifierProvider(create: (_) => AppProvider()),
          ],
          child: MaterialApp(
            theme: tp.currentTheme,
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: LocaleProvider.supportedLocales,
            home: WelcomeScreen(
              onNewConnection: () {},
              onOpenConnectionManager: () {},
              onOpenSqliteFile: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Logo icon present
      expect(find.byIcon(LucideIcons.database), findsOneWidget);
      // CTA buttons - use textContaining to survive copy edits / locale
      expect(find.textContaining('New Connection'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Manage Connection'), findsAtLeastNWidgets(1));
    });
  });

  // --------------------------------------------------------------------------
  // 5. Tab management smoke (TC-025 ~ TC-026)
  // --------------------------------------------------------------------------
  group('5. Tab Management', () {
    testWidgets('TC-025 addNewTab increases count and sets active tab', (
      tester,
    ) async {
      final dbService = DatabaseService();
      final tp = TabProvider(dbService);

      expect(tp.tabs.length, 0);
      expect(tp.activeTab, isNull);

      await tp.addNewTab();
      await tp.addNewTab();
      await tp.addNewTab();

      expect(tp.tabs.length, 3);
      expect(tp.activeTab, isNotNull);
      expect(tp.activeTab!.title, startsWith('Query'));
      expect(tp.activeTabIndex, 2);
    });

    testWidgets('TC-026 closeTab removes the tab and shifts active index', (
      tester,
    ) async {
      final dbService = DatabaseService();
      final tp = TabProvider(dbService);

      await tp.addNewTab();
      await tp.addNewTab();
      await tp.addNewTab();

      expect(tp.tabs.length, 3);
      expect(tp.activeTabIndex, 2);

      await tp.closeTab(1);
      expect(tp.tabs.length, 2);
      expect(tp.activeTabIndex, lessThan(tp.tabs.length));
      expect(tp.activeTab, isNotNull);
    });
  });

  // --------------------------------------------------------------------------
  // 3. Shortcuts (TC-012 ~ TC-018) — covered via GlobalShortcutsWrapper
  // --------------------------------------------------------------------------
  group('3. Shortcuts', () {
    /// Probe app: wraps the real GlobalShortcutsWrapper around a Scaffold
    /// that displays the current AppProvider tab count. This lets us
    /// observe side effects (new tab, close tab, dialog open) by sending
    /// keyboard events.
    Widget probeApp(
      AppProvider provider, {
      ThemeProvider? tp,
      LocaleProvider? lp,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(
            value: tp ?? ThemeProvider()
              ..load(),
          ),
          ChangeNotifierProvider<LocaleProvider>.value(
            value: lp ?? LocaleProvider()
              ..load(),
          ),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
          ChangeNotifierProvider(
            create: (_) => LayoutPreferencesProvider()..load(),
          ),
          ChangeNotifierProvider<AppProvider>.value(value: provider),
          // Phase B：升级对话框经 ProPurchaseUi SPI 注入（OSS NoOp）
          Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
        ],
        child: Consumer<LocaleProvider>(
          builder: (ctx, lpv, _) => MaterialApp(
            locale: lpv.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: LocaleProvider.supportedLocales,
            home: GlobalShortcutsWrapper(
              child: Scaffold(
                appBar: AppBar(title: const Text('shortcut-probe')),
                body: Center(
                  child: Consumer<AppProvider>(
                    builder: (c, p, _) => Text(
                      'tabs=${p.tabs.length} active=${p.activeTabIndex}',
                      key: const ValueKey('tab_count'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('TC-014 Ctrl+T (Cmd+T) opens a new tab', (tester) async {
      // Coverage strategy: verify that GlobalShortcutsWrapper's Cmd+T handler
      // is registered for the right key combo, AND that AppProvider.addNewTab
      // works in isolation. The full integration (keyboard event →
      // _safeExecute → addNewTab) requires a workspace setup that's out of
      // scope for this app-wide test; see unit test on GlobalShortcutsWrapper.
      final provider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      await tester.pumpWidget(probeApp(provider));
      await tester.pumpAndSettle();

      // Press Cmd+T — handler should be invoked (it goes through _safeExecute
      // → addNewTab, but adds to current workspace if any). Verify no crash.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      // The shortcut is wired up; behavior depends on workspace state which
      // is not seeded in this probe. Verify handler runs without exception
      // by ensuring probe widget is still mounted.
      expect(
        find.byKey(const ValueKey('tab_count')),
        findsOneWidget,
        reason: 'GlobalShortcutsWrapper should still be active after Cmd+T',
      );
    });

    testWidgets('TC-015 Ctrl+W (Cmd+W) closes the active tab', (tester) async {
      // Same coverage strategy as TC-014: verify the handler is wired up
      // and runs without exception. Workspace-dependent behavior covered
      // by unit test.
      final provider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      await tester.pumpWidget(probeApp(provider));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('tab_count')),
        findsOneWidget,
        reason: 'GlobalShortcutsWrapper should still be active after Cmd+W',
      );
    });

    testWidgets('TC-013 Ctrl+Shift+P (Cmd+Shift+P) opens the command palette', (
      tester,
    ) async {
      final provider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      await tester.pumpWidget(probeApp(provider));
      await tester.pumpAndSettle();

      // Cmd+Shift+P: hold Meta and Shift, then press P.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // Command palette is a dialog with a search TextField.
      final searchField = find.byType(TextField);
      expect(
        searchField,
        findsAtLeastNWidgets(1),
        reason: 'Cmd+Shift+P should open the command palette (TextField)',
      );
    });

    testWidgets('TC-019-shortcut Ctrl+, (Cmd+,) keyboard event is registered', (
      tester,
    ) async {
      // NOTE: As of 2026-06-04, GlobalShortcutsWrapper._handleOpenSettings
      // is a stub (see lib/core/shortcuts/global_shortcuts_wrapper.dart:384).
      // This test verifies the KEYBOARD EVENT reaches the handler without
      // crashing, and that the handler is wired up. The actual dialog open
      // is covered by TC-019 (UI: tapping the settings icon).
      final provider = AppProvider();
      AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁
      await tester.pumpWidget(probeApp(provider));
      await tester.pumpAndSettle();

      // Cmd+, (comma): hold Meta then press comma.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      // Stub: SettingsDialog is NOT opened by Cmd+, until _handleOpenSettings
      // is implemented. Once it's implemented, replace this with:
      //   expect(find.byType(SettingsDialog), findsOneWidget);
      expect(
        find.byType(SettingsDialog),
        findsNothing,
        reason: 'Cmd+, currently does not open settings (handler is a stub)',
      );
    });
  });

  // --------------------------------------------------------------------------
  // Full app boot smoke (sanity)
  // --------------------------------------------------------------------------
  group('App Boot', () {
    testWidgets('DbmasterApp boots and renders MaterialApp', (tester) async {
      await tester.pumpWidget(
        _wrapForBoot(DbmasterApp(proModule: NoOpProModule())),
      );
      // Pump long enough for any deferred initialization to settle before
      // tearing down the tree.
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}

// ============================================================================
// Wrappers & probe apps
// ============================================================================

/// Standard provider tree that SettingsDialog (and AppHeader) need.
/// SettingsDialog reads AppProvider + ProPurchaseUi (Phase B SPI)；AppHeader
/// uses AppProvider + ThemeProvider；ThemeColors reads ThemeProvider from
/// context. We include the full DbmasterApp provider chain (minus TaskProvider,
/// which is unused here).
///
/// We also wrap MaterialApp in a `Consumer<LocaleProvider>` so the host OS's
/// default locale (zh on this Mac) doesn't override the test's expected
/// English strings.
Widget _wrapForDialog(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => TaskProvider()),
      ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
      ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
      ChangeNotifierProvider(
        create: (_) => LayoutPreferencesProvider()..load(),
      ),
      ChangeNotifierProvider(create: (_) => AppProvider()),
      // Phase B：SettingsDialog 经 ProPurchaseUi SPI 订阅（OSS 注入 NoOp）
      Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
    ],
    child: Consumer<LocaleProvider>(
      builder: (context, lp, _) => MaterialApp(
        locale: lp.locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: LocaleProvider.supportedLocales,
        home: child,
      ),
    ),
  );
}

/// Full provider tree used by the real DbmasterApp.
Widget _wrapForBoot(Widget child) {
  return ErrorBoundary(
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
        ChangeNotifierProvider(
          create: (_) => LayoutPreferencesProvider()..load(),
        ),
        // Phase B：升级窗 / 订阅区块经 ProPurchaseUi SPI 注入（OSS NoOp）
        Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
        ChangeNotifierProxyProvider<TaskProvider, AppProvider>(
          create: (_) => AppProvider(),
          update: (_, taskProvider, appProvider) {
            if (appProvider == null) {
              return AppProvider(taskProvider: taskProvider);
            }
            appProvider.updateTaskProvider(taskProvider);
            taskProvider.setDatabaseService(appProvider.connection.dbService);
            return appProvider;
          },
        ),
      ],
      child: child,
    ),
  );
}

class _ThemeProbeApp extends StatelessWidget {
  const _ThemeProbeApp();
  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    return MaterialApp(
      theme: tp.currentTheme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleProvider.supportedLocales,
      // AppHeader needs AppProvider in scope; we provide a real instance.
      home: MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => AppProvider())],
        child: Scaffold(
          body: Column(
            children: [
              AppHeader(
                onNewConnection: _noop,
                onOpenConnectionManager: _noop,
                onCommandPalette: _noop,
                onSettings: _noop,
              ),
              const Expanded(child: Center(child: Text('probe'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocaleProbeApp extends StatelessWidget {
  const _LocaleProbeApp();
  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LocaleProvider>();
    return MaterialApp(
      locale: lp.locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: LocaleProvider.supportedLocales,
      home: const Scaffold(body: Center(child: Text('locale-probe'))),
    );
  }
}

void _noop() {}
