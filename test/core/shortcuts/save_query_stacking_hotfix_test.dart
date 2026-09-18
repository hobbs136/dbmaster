// Regression test for hotfix/save-query-name-dialog-stuck.
//
// Bug: Ctrl+S was captured by BOTH (1) the global HardwareKeyboard handler
// (GlobalShortcutsWrapper, focus-tree independent) and (2) the focused editor's
// own onKeyEvent (QueryEditorWidget, focus chain). Each opened its own
// _showSaveQueryNamingDialog -> two stacked AlertDialogs. Clicking "Save"
// dismissed only the top one, leaving the bottom one visible, so the naming
// dialog appeared to "not disappear". It also fired provider.saveQuery twice.
//
// Fix: GlobalShortcutsWrapper._handleSaveExport now returns early when
// _isDialogOpen() is true. Since the global handler runs deferred (next frame,
// via _safeExecute) while the editor pushes its dialog synchronously during the
// key event, the editor's (live _controller.text) path wins and no second
// dialog is stacked.
//
// This test faithfully reproduces the double-fire by wrapping QueryEditorWidget
// inside GlobalShortcutsWrapper (the pre-existing query_editor_shortcuts_test
// does NOT wrap it, which is why it never caught this bug). Without the fix it
// sees two AlertDialogs; with the fix, exactly one.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/core/shortcuts/global_shortcuts_wrapper.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/editor/re_sql_editor.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock in_app_purchase Pigeon channels so AppProvider can be constructed in a
  // widget test without hanging on platform channels.
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi',
      (message) async =>
          const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
    );
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchaseApi',
      (message) async =>
          const StandardMessageCodec().encodeMessage(<String, dynamic>{}),
    );
  });

  testWidgets(
      'Ctrl+S with editor focused opens exactly ONE naming dialog (no stacking)',
      (tester) async {
    // Large surface to avoid layout overflow noise from the editor + wrapper.
    tester.binding.setSurfaceSize(const Size(1920, 1080));

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    final layoutProvider = LayoutPreferencesProvider();
    await themeProvider.load();
    await localeProvider.load();
    await layoutProvider.load();

    // Provider with a saved (non-readOnly) connection + one query tab holding
    // SQL — exactly the state _handleSaveExport needs to reach its dialog.
    final provider = AppProvider();
    provider.connection.saveConnection(
      DbServer(
        id: 'test-conn',
        name: 'Test Connection',
        host: 'localhost',
        port: 8123,
        type: DatabaseType.sqlite, // T29 第三批：CH 已 gateway-backed，占位切 sqlite（AdapterBacking 豁免型）
      ),
    );
    await provider.tab.openQueryTab(
      connectionId: 'test-conn',
      databaseName: 'test-db',
    );
    provider.updateTabSql(0, 'SELECT * FROM users');
    provider.setActiveTab(0);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layoutProvider,
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
                // QueryEditorWidget INSIDE GlobalShortcutsWrapper is what
                // reproduces the double-fire (both handlers active).
                body: GlobalShortcutsWrapper(
                  child: SizedBox(
                    width: 800,
                    height: 600,
                    child: QueryEditorWidget(tabIndex: 0),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(provider.tab.savedQueries.length, 0, reason: '初始无已保存查询');

    // Focus the editor so its onKeyEvent (focus chain) is active and will also
    // receive Ctrl+S alongside the global HardwareKeyboard handler.
    await tester.tap(find.byType(ReSqlEditor));
    await tester.pump();

    // Fire Ctrl+S once.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    // Regression assertion: exactly ONE naming dialog — not two stacked.
    // Without the fix, the global handler stacks a second AlertDialog here.
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'Ctrl+S 应只弹出一个命名对话框；修复前全局处理器会叠堆第二个',
    );
  });
}
