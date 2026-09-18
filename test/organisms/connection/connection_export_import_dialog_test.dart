import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/connection_export_import_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

// ============================================================================
// ConnectionExportImportDialog Widget Tests
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConnectionExportImportDialog', () {
    Future<ThemeProvider> loadThemeProvider() async {
      final provider = ThemeProvider();
      await provider.load();
      return provider;
    }

    Future<void> pumpDialog(WidgetTester tester, Widget dialog) async {
      final themeProvider = await loadThemeProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
            ChangeNotifierProvider<AppProvider>(
              create: (_) =>
                  AppProvider(connectionProvider: ConnectionProvider()),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: dialog,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    AppLocalizations l10n(WidgetTester tester) {
      return AppLocalizations.of(
        tester.element(find.byType(ConnectionExportImportDialog)),
      )!;
    }

    testWidgets('export mode disables submit when passwords do not match', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        ConnectionExportImportDialog(
          mode: ConnectionExportImportMode.export,
          connectionsToExport: [
            DbServer(id: 'c1', name: 'test', host: 'localhost', port: 3306),
          ],
        ),
      );

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      await tester.enterText(textFields.first, 'pw1');
      await tester.enterText(textFields.last, 'pw2');
      await tester.pump();

      final loc = l10n(tester);
      final submitButton = find.widgetWithText(
        ElevatedButton,
        loc.toolbarExport,
      );
      expect(submitButton, findsOneWidget);
      expect(tester.widget<ElevatedButton>(submitButton).enabled, isFalse);
      expect(find.text(loc.passwordsDoNotMatch), findsOneWidget);
    });

    testWidgets('export mode disables submit when no connections to export', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        const ConnectionExportImportDialog(
          mode: ConnectionExportImportMode.export,
          connectionsToExport: [],
        ),
      );

      final loc = l10n(tester);
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      await tester.enterText(textFields.first, 'pw1');
      await tester.enterText(textFields.last, 'pw1');
      await tester.pump();

      final submitButton = find.widgetWithText(
        ElevatedButton,
        loc.toolbarExport,
      );
      expect(submitButton, findsOneWidget);
      expect(tester.widget<ElevatedButton>(submitButton).enabled, isFalse);
      expect(find.text(loc.noConnectionsToExport), findsOneWidget);
    });

    testWidgets('export mode enables submit when passwords match', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        ConnectionExportImportDialog(
          mode: ConnectionExportImportMode.export,
          connectionsToExport: [
            DbServer(id: 'c1', name: 'test', host: 'localhost', port: 3306),
          ],
        ),
      );

      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));

      await tester.enterText(textFields.first, 'matching_pw');
      await tester.enterText(textFields.last, 'matching_pw');
      await tester.pump();

      final loc = l10n(tester);
      final submitButton = find.widgetWithText(
        ElevatedButton,
        loc.toolbarExport,
      );
      expect(submitButton, findsOneWidget);
      expect(tester.widget<ElevatedButton>(submitButton).enabled, isTrue);
      expect(find.text(loc.passwordsDoNotMatch), findsNothing);
    });

    testWidgets('import mode shows file picker button', (tester) async {
      await pumpDialog(
        tester,
        const ConnectionExportImportDialog(
          mode: ConnectionExportImportMode.import,
        ),
      );

      expect(find.byIcon(LucideIcons.folderOpen), findsOneWidget);
    });
  });
}
