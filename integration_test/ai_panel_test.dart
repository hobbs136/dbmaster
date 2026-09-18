// ============================================================================
// AI Panel Integration Test
// Tests: AiPanelWidget, AiWelcomeState, AiSettingsDialog
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/organisms/ai_panel/ai_panel_widget.dart';
import 'package:dbmaster/organisms/ai_panel/ai_welcome_state.dart';
import 'package:dbmaster/organisms/ai_panel/ai_settings_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('AI Panel Tests', () {
    Widget buildTestApp(Widget child, {AppProvider? provider}) {
      return MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('zh'),
        ],
        home: provider != null
            ? ChangeNotifierProvider.value(
                value: provider,
                child: Scaffold(body: child),
              )
            : Scaffold(body: child),
      );
    }

    // ========================================================================
    // AI WELCOME STATE TESTS
    // ========================================================================
    group('AiWelcomeState', () {
      testWidgets('should render welcome state without connection', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(const AiWelcomeState(), provider: appProvider),
          ),
        );
        await tester.pumpAndSettle();

        // Verify welcome state is displayed
        expect(find.byType(AiWelcomeState), findsOneWidget);

        // Verify center alignment widget exists
        expect(find.byType(Center), findsAtLeastNWidgets(1));
      });

      testWidgets('should render welcome state with connection', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(
              const AiWelcomeState(
                connectionName: 'Test Connection',
                databaseName: 'test_db',
              ),
              provider: appProvider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify connection badge is shown (look for the connection name)
        expect(find.textContaining('Test Connection'), findsOneWidget);
      });

      testWidgets('should render quick action buttons', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(
              AiWelcomeState(
                onOptimizeSql: () {},
                onSecurityAnalysis: () {},
                onExecutionPlan: () {},
                onIndexSuggestions: () {},
              ),
              provider: appProvider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify quick actions are rendered (look for chips/buttons)
        expect(find.byType(SingleChildScrollView), findsAtLeastNWidgets(1));
      });
    });

    // ========================================================================
    // AI PANEL WIDGET TESTS
    // ========================================================================
    group('AiPanelWidget', () {
      testWidgets('should render AI panel widget', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(
              SizedBox(
                height: 600,
                child: const AiPanelWidget(),
              ),
              provider: appProvider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify AI panel is displayed
        expect(find.byType(AiPanelWidget), findsOneWidget);

        // Verify input area exists
        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('should render AI panel in fullscreen mode', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(
              SizedBox(
                height: 800,
                child: const AiPanelWidget(isFullscreen: true),
              ),
              provider: appProvider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify AI panel is displayed in fullscreen
        expect(find.byType(AiPanelWidget), findsOneWidget);
      });

      testWidgets('should show input area buttons', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(
              SizedBox(
                height: 600,
                child: const AiPanelWidget(),
              ),
              provider: appProvider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify action buttons exist (IconButton or TextButton)
        expect(find.byType(IconButton), findsAtLeastNWidgets(1));
      });

      testWidgets('should allow typing in input field', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(
              SizedBox(
                height: 600,
                child: const AiPanelWidget(),
              ),
              provider: appProvider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Type in the input field
        await tester.enterText(find.byType(TextField), 'Hello AI');
        await tester.pump();

        // Verify text was entered
        expect(find.text('Hello AI'), findsOneWidget);
      });
    });

    // ========================================================================
    // AI SETTINGS DIALOG TESTS
    // ========================================================================
    group('AiSettingsDialog', () {
      testWidgets('should render settings dialog', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(
              AiSettingsDialog(
                providers: [
                  {
                    'name': 'DeepSeek',
                    'icon': '🤖',
                    'color': Colors.blue.value,
                    'models': ['deepseek-chat', 'deepseek-coder'],
                  },
                ],
                selectedProvider: 'DeepSeek',
              ),
              provider: appProvider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify dialog is displayed
        expect(find.byType(AiSettingsDialog), findsOneWidget);

        // Verify provider selection exists
        expect(find.text('DeepSeek'), findsAtLeastNWidgets(1));
      });

      testWidgets('should show configuration UI elements', (tester) async {
        final appProvider = AppProvider();
        AppProvider.devBypassGates = true; // 集成测试测全功能，绕过 Free/Pro 门禁

        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: appProvider,
            child: buildTestApp(
              AiSettingsDialog(
                providers: [
                  {
                    'name': 'DeepSeek',
                    'icon': '🤖',
                    'color': Colors.blue.value,
                    'models': ['deepseek-chat'],
                  },
                ],
                selectedProvider: 'DeepSeek',
              ),
              provider: appProvider,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify the dialog renders with the provider name
        expect(find.text('DeepSeek'), findsAtLeastNWidgets(1));
      });
    });
  });
}
