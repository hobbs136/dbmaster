import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/main.dart' show appNavigatorKey;
import 'package:dbmaster/molecules/bulk_close_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/providers/task_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/utils/close_decision_applier.dart';

/// In-test re-implementation of the close-guard logic.
///
/// The real `_WindowCloseGuard` is private inside `lib/main.dart`. We exercise
/// the same navigator-key pattern here to verify that using
/// `appNavigatorKey.currentState!.context` for `showBulkCloseDialog` avoids the
/// original null-check crash.
class _TestCloseFlow extends StatefulWidget {
  const _TestCloseFlow();

  @override
  State<_TestCloseFlow> createState() => _TestCloseFlowState();
}

class _TestCloseFlowState extends State<_TestCloseFlow> {
  bool showingDialog = false;
  bool closing = false;
  bool closeRequested = false;

  Future<void> onWindowClose() async {
    if (closing || showingDialog) return;
    if (!mounted) return;

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    final appProvider = context.read<AppProvider>();
    final unsavedTabs = appProvider.tabs.where((t) {
      return (!t.isSaved && t.sql.trim().isNotEmpty) ||
          (t.isSaved && t.isModified);
    }).toList();

    if (unsavedTabs.isEmpty) {
      closeRequested = true;
      return;
    }

    showingDialog = true;
    final result = await showBulkCloseDialog(
      navigator.context,
      tabs: unsavedTabs,
    );
    showingDialog = false;

    if (!navigator.context.mounted) return;
    if (!result.confirmed) return;

    await CloseDecisionApplier.applyDecisions(
      tabs: List.unmodifiable(appProvider.tabs),
      saveTab: appProvider.saveQuery,
      closeTabAtIndex: appProvider.forceCloseTab,
      result: result,
    );
    closeRequested = true;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpTree(
    WidgetTester tester, {
    required AppProvider appProvider,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appProvider),
          ChangeNotifierProvider(create: (_) => TaskProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
          ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
          ChangeNotifierProvider(
            create: (_) => LayoutPreferencesProvider()..load(),
          ),
        ],
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const Scaffold(body: _TestCloseFlow()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppProvider createAppProvider() {
    // Provide a dedicated DatabaseService so AppProvider's TabProvider does not
    // share global connection state across tests.
    return AppProvider(
      taskProvider: TaskProvider(),
      connectionProvider: ConnectionProvider(dbService: DatabaseService()),
    );
  }

  group('WindowCloseGuard navigator key fix', () {
    testWidgets('closing with unsaved tabs shows bulk close dialog', (
      tester,
    ) async {
      final appProvider = createAppProvider();
      await pumpTree(tester, appProvider: appProvider);

      appProvider.tab.addTab(QueryTab(id: 'a', title: 'Tab A', sql: 'SELECT 1'));
      await tester.pump();

      final flow = tester.state<_TestCloseFlowState>(
        find.byType(_TestCloseFlow),
      );
      unawaited(flow.onWindowClose());
      await tester.pumpAndSettle();

      // The dialog uses the English ARB string when locale is 'en'.
      expect(find.text('The following tabs have unsaved changes:'), findsOneWidget);
      expect(find.text('Tab A'), findsOneWidget);
    });

    testWidgets('cancel keeps window open and preserves tab state', (
      tester,
    ) async {
      final appProvider = createAppProvider();
      await pumpTree(tester, appProvider: appProvider);

      appProvider.tab.addTab(QueryTab(id: 'b', title: 'Tab B', sql: 'SELECT 2'));
      await tester.pump();

      final flow = tester.state<_TestCloseFlowState>(
        find.byType(_TestCloseFlow),
      );
      unawaited(flow.onWindowClose());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(flow.closeRequested, isFalse);
      expect(appProvider.tabs.length, 1);
      expect(appProvider.tabs.first.sql, 'SELECT 2');
    });

    testWidgets('discard all closes without exceptions', (tester) async {
      final appProvider = createAppProvider();
      await pumpTree(tester, appProvider: appProvider);

      appProvider.tab.addTab(QueryTab(id: 'c', title: 'Tab C', sql: 'SELECT 3'));
      await tester.pump();

      final flow = tester.state<_TestCloseFlowState>(
        find.byType(_TestCloseFlow),
      );
      unawaited(flow.onWindowClose());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Discard All'));
      await tester.pumpAndSettle();

      expect(flow.closeRequested, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('closing with all tabs saved does not show dialog', (
      tester,
    ) async {
      final appProvider = createAppProvider();
      await pumpTree(tester, appProvider: appProvider);

      appProvider.tab.addTab(
        QueryTab(
          id: 'd',
          title: 'Saved Tab',
          sql: 'SELECT 4',
          isSaved: true,
        ),
      );
      await tester.pump();

      final flow = tester.state<_TestCloseFlowState>(
        find.byType(_TestCloseFlow),
      );
      await flow.onWindowClose();
      await tester.pumpAndSettle();

      expect(find.text('The following tabs have unsaved changes:'), findsNothing);
      expect(flow.closeRequested, isTrue);
    });

    testWidgets('second close event while dialog is open is ignored', (
      tester,
    ) async {
      final appProvider = createAppProvider();
      await pumpTree(tester, appProvider: appProvider);

      appProvider.tab.addTab(QueryTab(id: 'e', title: 'Tab E', sql: 'SELECT 5'));
      await tester.pump();

      final flow = tester.state<_TestCloseFlowState>(
        find.byType(_TestCloseFlow),
      );
      unawaited(flow.onWindowClose());
      await tester.pump();

      // Dialog is now building; trigger a second close event.
      unawaited(flow.onWindowClose());
      await tester.pumpAndSettle();

      expect(find.text('The following tabs have unsaved changes:'), findsOneWidget);
      expect(find.text('Tab E'), findsOneWidget);
    });
  });
}
