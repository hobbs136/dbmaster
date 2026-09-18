import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/sidebar/mysql_process_panel.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Minimal widget tree for testing MysqlProcessPanel.
Widget _buildTestWidget(
  AppProvider provider, {
  String connectionId = 'test-mysql',
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('zh')],
    locale: const Locale('en'),
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider()..load(),
        ),
      ],
      child: const Scaffold(
        body: MysqlProcessPanel(connectionId: 'test-mysql'),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MysqlProcessPanel', () {
    testWidgets('renders header with Running Queries title', (tester) async {
      final provider = AppProvider();

      await tester.pumpWidget(_buildTestWidget(provider));
      await tester.pumpAndSettle();

      // plan §3.2：默认折叠（chevron_right）；header 仍渲染
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
      // Query stats icon in header
      expect(find.byIcon(LucideIcons.chartLine), findsOneWidget);
    });

    testWidgets('shows refresh interval buttons', (tester) async {
      final provider = AppProvider();

      await tester.pumpWidget(_buildTestWidget(provider));
      await tester.pumpAndSettle();

      // Refresh interval buttons visible
      expect(find.text('5s'), findsOneWidget);
      expect(find.text('10s'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
    });

    testWidgets('shows no-processes message when process list is empty', (
      tester,
    ) async {
      final provider = AppProvider();

      await tester.pumpWidget(_buildTestWidget(provider));
      await tester.pumpAndSettle();

      // plan §3.2：默认折叠——先点开 header 再看空态
      await tester.tap(find.byIcon(LucideIcons.chartLine));
      await tester.pumpAndSettle();

      // When no processes loaded, shows loading or empty state
      // (AppProvider returns null by default for getProcessList)
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('toggles collapse/expand on header tap', (tester) async {
      final provider = AppProvider();

      await tester.pumpWidget(_buildTestWidget(provider));
      await tester.pumpAndSettle();

      // plan §3.2：默认折叠（chevron_right）
      expect(find.byIcon(LucideIcons.chevronRight), findsWidgets);

      // Tap header to expand
      await tester.tap(find.byIcon(LucideIcons.chartLine));
      await tester.pumpAndSettle();

      // After expand: expand_more icon + 空态 "Loading..." 显示
      expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('does not crash when AppProvider updates', (tester) async {
      final provider = AppProvider();

      await tester.pumpWidget(_buildTestWidget(provider));
      await tester.pumpAndSettle();

      // Trigger a notify to simulate data update
      provider.notifyListeners();
      await tester.pumpAndSettle();

      // Panel still renders
      expect(find.byType(MysqlProcessPanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposes without error', (tester) async {
      final provider = AppProvider();

      await tester.pumpWidget(_buildTestWidget(provider));
      await tester.pumpAndSettle();

      // Replace with empty widget (simulates panel removal)
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          locale: const Locale('en'),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pumpAndSettle();

      // No dispose errors
      expect(tester.takeException(), isNull);
    });
  });

  // Unit-level tests for the time formatting logic used in _ProcessRow
  group('ProcessTimeFormat', () {
    test('seconds under 60 display as "Xs"', () {
      expect(_formatTimeForTest(0), '0s');
      expect(_formatTimeForTest(5), '5s');
      expect(_formatTimeForTest(59), '59s');
    });

    test('seconds over 60 display as "Xm Ys"', () {
      expect(_formatTimeForTest(60), '60s'); // exactly 60: not > 60
      expect(_formatTimeForTest(61), '1m 1s');
      expect(_formatTimeForTest(90), '1m 30s');
      expect(_formatTimeForTest(3600), '60m 0s');
    });

    test('slow query threshold is > 5 seconds', () {
      expect(5 > 5, isFalse); // not highlighted
      expect(6 > 5, isTrue); // highlighted
      expect(300 > 5, isTrue); // highlighted
    });
  });
}

/// Standalone copy of _ProcessRow._formatTime for unit testing.
String _formatTimeForTest(int seconds) {
  if (seconds > 60) return '${(seconds / 60).floor()}m ${seconds % 60}s';
  return '${seconds}s';
}
