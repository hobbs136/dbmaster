import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/code_snippet.dart';
import 'package:dbmaster/organisms/connection/code_snippets_panel.dart';
import 'package:dbmaster/services/code_snippet_service.dart';

/// Minimal service that exposes a single Mongo snippet for selection tests.
/// Avoids relying on scroll position or disambiguating multiple cards.
class _SingleMongoService extends CodeSnippetService {
  final _mongoFind = CodeSnippet(
    id: 'builtin-mongo-find',
    name: 'Mongo Find',
    description: 'Find documents in a collection',
    category: 'Mongo CRUD',
    content: r'db.collection.find({});',
    variables: const [],
    isBuiltIn: true,
    databaseFamily: SnippetDbFamily.mongodb,
  );

  @override
  List<CodeSnippet> getAllSnippets() => [_mongoFind];

  @override
  List<CodeSnippet> searchSnippets(String query) {
    final q = query.toLowerCase();
    return _mongoFind.name.toLowerCase().contains(q) ? [_mongoFind] : [];
  }

  @override
  Future<CodeSnippet?> incrementUsage(String id) async {
    // No-op: the mock service does not track usage counts.
    return null;
  }
}

void main() {
  group('CodeSnippetsPanel (020-mongo UI)', () {
    Future<CodeSnippetService> _initService() async {
      TestWidgetsFlutterBinding.ensureInitialized();
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
      SharedPreferences.setMockInitialValues({});
      final service = CodeSnippetService();
      await service.init();
      return service;
    }

    Widget buildPanel({
      required CodeSnippetService service,
      ValueChanged<CodeSnippet>? onSelected,
    }) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: CodeSnippetsPanel(
              service: service,
              onSnippetSelected: onSelected,
            ),
          ),
        ),
      );
    }

    testWidgets('renders category tabs and Mongo snippets in all category', (
      tester,
    ) async {
      final service = await _initService();
      await tester.pumpWidget(buildPanel(service: service));
      await tester.pumpAndSettle();

      // Category tab labels
      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'DML'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'DDL'), findsOneWidget);

      // Built-in Mongo snippets are below the SQL snippets, so filter to
      // "Mongo" to bring them into the visible viewport.
      await tester.enterText(find.byType(TextField), 'Mongo');
      await tester.pumpAndSettle();

      expect(find.text('Mongo Find'), findsOneWidget);

      // Mongo Aggregate is further down; scroll the snippet list to reveal it.
      await tester.scrollUntilVisible(
        find.text('Mongo Aggregate'),
        120,
        scrollable: find
            .descendant(
              of: find.byType(CodeSnippetsPanel),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(find.text('Mongo Aggregate'), findsOneWidget);
    });

    testWidgets('search filters snippets including Mongo ones', (tester) async {
      final service = await _initService();
      await tester.pumpWidget(buildPanel(service: service));
      await tester.pumpAndSettle();

      // Search narrows the list down to Mongo snippets only.
      await tester.enterText(find.byType(TextField), 'Mongo');
      await tester.pumpAndSettle();

      expect(find.text('Mongo Find'), findsOneWidget);
      expect(find.text('Select All'), findsNothing);
    });

    testWidgets('category tabs filter snippets', (tester) async {
      final service = await _initService();
      await tester.pumpWidget(buildPanel(service: service));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ChoiceChip, 'DDL'));
      await tester.pumpAndSettle();

      expect(find.text('Create Table'), findsOneWidget);
      expect(find.text('Mongo Find'), findsNothing);
    });

    testWidgets('selecting a snippet invokes onSnippetSelected', (
      tester,
    ) async {
      // Use a service that exposes only the Mongo Find snippet so the card's
      // Insert button is unambiguous.
      final service = _SingleMongoService();
      CodeSnippet? selected;
      await tester.pumpWidget(
        buildPanel(service: service, onSelected: (s) => selected = s),
      );
      await tester.pumpAndSettle();

      expect(find.text('Mongo Find'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Insert'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.databaseFamily, SnippetDbFamily.mongodb);
    });
  });
}
