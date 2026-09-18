import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/ai_panel/ai_conversation_list.dart';
import 'package:dbmaster/providers/ai_panel_provider.dart';
import 'package:dbmaster/providers/app_provider.dart';

class MockAppProvider extends AppProvider {
  @override
  bool get isAiPanelOverlay => false;
}

void main() {
  testWidgets('search filters sessions', (tester) async {
    final provider = AiPanelProvider();
    provider.aiConversationService.createSession(title: 'Alpha Query');
    provider.aiConversationService.createSession(title: 'Beta Backup');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: ChangeNotifierProvider<AppProvider>.value(
          value: MockAppProvider(),
          child: MaterialApp(
            localizationsDelegates: const [
              ...AppLocalizations.localizationsDelegates,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 400,
                child: AiConversationList(
                  sessions: provider.aiConversationService.sessions,
                  currentSessionId:
                      provider.aiConversationService.currentSession?.id,
                  onSessionSelected: (_) {},
                  onSessionDeleted: (_) {},
                  onSessionsDeleted: (_) {},
                  onSessionRestored: (_) {},
                  onSessionArchived: (_) {},
                  onSessionRenamed: (_, _) {},
                  onNewSession: () {},
                  isFullPanel: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alpha Query'), findsOneWidget);
    expect(find.text('Beta Backup'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pumpAndSettle();

    expect(find.text('Alpha Query'), findsOneWidget);
    expect(find.text('Beta Backup'), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
    addTearDown(() => provider.dispose());
  });
}
