import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:dbmaster/templates/editor_results_split.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

ExecutionResult _errorResult([int idx = 0]) => ExecutionResult(
  statement: SQLStatement(
    index: idx,
    sql: 'SELECT * FROM nonexistent',
    type: SQLType.select,
    lineStart: 0,
    lineEnd: 0,
  ),
  success: false,
  data: null,
  executionTime: const Duration(milliseconds: 150),
  errorMessage: 'Table does not exist',
);

ExecutionResult _successResult([int idx = 0]) => ExecutionResult(
  statement: SQLStatement(
    index: idx,
    sql: 'SELECT 1',
    type: SQLType.select,
    lineStart: 0,
    lineEnd: 0,
  ),
  success: true,
  data: [
    {'1': 1},
  ],
  executionTime: const Duration(milliseconds: 5),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppProvider.devBypassGates = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.in_app_purchase_android.InAppPurchaseApi',
      (message) async => null,
    );
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchaseApi',
      (message) async => null,
    );
  });

  Widget _wrap(AppProvider provider) {
    return ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ExecutionStatusBar(),
          ),
        ),
      ),
    );
  }

  group('ExecutionStatusBar dismiss regression', () {
    testWidgets('shows error bar with close button when results have errors', (
      tester,
    ) async {
      final provider = AppProvider();
      final tabId = 't1';
      provider.tab.addTab(QueryTab(id: tabId, title: 'Q1'));
      provider.tab.addResultToTab(
        tabId,
        [_errorResult()],
        sql: 'SELECT * FROM nonexistent',
        executionTime: const Duration(milliseconds: 150),
      );

      await tester.pumpWidget(_wrap(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });

    testWidgets('tapping close button hides the status bar', (tester) async {
      final provider = AppProvider();
      final tabId = 't2';
      provider.tab.addTab(QueryTab(id: tabId, title: 'Q2'));
      provider.tab.addResultToTab(
        tabId,
        [_errorResult()],
        sql: 'SELECT * FROM nonexistent',
        executionTime: const Duration(milliseconds: 150),
      );

      await tester.pumpWidget(_wrap(provider));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);
      expect(find.byIcon(LucideIcons.x), findsNothing);
    });

    testWidgets('bar reappears when new results arrive after dismiss', (
      tester,
    ) async {
      final provider = AppProvider();
      final tabId = 't3';
      provider.tab.addTab(QueryTab(id: tabId, title: 'Q3'));
      provider.tab.addResultToTab(
        tabId,
        [_errorResult()],
        sql: 'SELECT * FROM nonexistent',
        executionTime: const Duration(milliseconds: 150),
      );

      await tester.pumpWidget(_wrap(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);

      provider.tab.addResultToTab(
        tabId,
        [_errorResult(1), _successResult(2)],
        sql: 'SELECT 1; SELECT * FROM nonexistent',
        executionTime: const Duration(milliseconds: 200),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });

    testWidgets('green bar for success, red for errors', (tester) async {
      final provider = AppProvider();
      final tabId = 't4';
      provider.tab.addTab(QueryTab(id: tabId, title: 'Q4'));

      provider.tab.addResultToTab(
        tabId,
        [_errorResult()],
        sql: 'E',
        executionTime: const Duration(milliseconds: 10),
      );
      await tester.pumpWidget(_wrap(provider));
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      provider.tab.addResultToTab(
        tabId,
        [_successResult()],
        sql: 'S',
        executionTime: const Duration(milliseconds: 5),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.circleCheckBig), findsOneWidget);
    });

    testWidgets('no bar when results are empty', (tester) async {
      final provider = AppProvider();
      final tabId = 't5';
      provider.tab.addTab(QueryTab(id: tabId, title: 'Q5'));

      await tester.pumpWidget(_wrap(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.triangleAlert), findsNothing);
      expect(find.byIcon(LucideIcons.x), findsNothing);
      expect(find.byIcon(LucideIcons.circleCheckBig), findsNothing);
    });
  });
}
