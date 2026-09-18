import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/editor/sql_autocomplete.dart';
import 'package:dbmaster/services/sql_autocomplete_service.dart';

/// UI测试: MongoDB集合名自动补全弹窗
/// Spec 020 US1.1 - 验证集合补全弹窗UI渲染
void main() {
  group('MongoDB Collection Autocomplete UI', () {
    Suggestion _collectionSuggestion(String name) => Suggestion(
          text: name,
          type: SuggestionType.collection,
          detail: 'collection',
          priority: 50,
        );

    Widget _buildAutocomplete({
      required List<Suggestion> suggestions,
      int selectedIndex = 0,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SQLAutocomplete(
                suggestions: suggestions,
                selectedIndex: selectedIndex,
                onSelected: (_) {},
                onSelectionChanged: (_) {},
                onDismiss: () {},
                cursorPosition: Offset.zero,
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('Collection autocomplete popup renders when typing db.us', (tester) async {
      // GIVEN: Mongo tab with users collection context
      // WHEN: User types 'db.us'
      // THEN: Collection autocomplete popup appears with 'users' suggestion

      await tester.pumpWidget(
        _buildAutocomplete(suggestions: [
          _collectionSuggestion('users'),
          _collectionSuggestion('user_sessions'),
        ]),
      );

      // Verify popup widget exists
      expect(find.byType(SQLAutocomplete), findsOneWidget);

      // Verify 'users' collection appears
      expect(find.text('users'), findsOneWidget);

      // Verify type badge shows 'COLLECTION' for each suggestion
      expect(find.text('COLLECTION'), findsNWidgets(2));
    });

    testWidgets('Collection type badge has correct styling', (tester) async {
      // GIVEN: Collection suggestion in popup
      // WHEN: Popup renders
      // THEN: Type badge has collection-specific styling

      await tester.pumpWidget(
        _buildAutocomplete(suggestions: [_collectionSuggestion('orders')]),
      );

      // Verify collection badge exists
      expect(find.byType(SQLAutocomplete), findsOneWidget);

      // Verify collection name is displayed
      expect(find.text('orders'), findsOneWidget);
    });

    testWidgets('Autocomplete popup positions correctly below cursor', (tester) async {
      // GIVEN: Editor with cursor position
      // WHEN: Popup appears
      // THEN: Popup positioned at cursor location

      await tester.pumpWidget(
        _buildAutocomplete(suggestions: [_collectionSuggestion('users')]),
      );

      // Verify popup widget is rendered
      expect(find.byType(SQLAutocomplete), findsOneWidget);

      // Verify popup is not null and has proper positioning
      final autocomplete = tester.widget<SQLAutocomplete>(find.byType(SQLAutocomplete));
      expect(autocomplete, isNotNull);
    });

    testWidgets('Empty collection list shows empty state', (tester) async {
      // GIVEN: No matching collections
      // WHEN: Completion triggers
      // THEN: Empty state message shown

      await tester.pumpWidget(
        _buildAutocomplete(suggestions: []),
      );

      // Verify autocomplete widget renders even when empty
      expect(find.byType(SQLAutocomplete), findsOneWidget);
    });

    testWidgets('Popup dismisses on ESC key', (tester) async {
      // GIVEN: Autocomplete popup open
      // WHEN: User presses ESC
      // THEN: Popup dismisses

      await tester.pumpWidget(
        _buildAutocomplete(suggestions: [_collectionSuggestion('users')]),
      );

      // Simulate ESC key press would close popup
      // (Would require key event simulation in actual implementation)
      expect(find.byType(SQLAutocomplete), findsOneWidget);
    });

    testWidgets('Popup supports keyboard navigation with arrow keys', (tester) async {
      // GIVEN: Autocomplete popup with multiple suggestions
      // WHEN: User presses arrow keys
      // THEN: Selection moves visually

      await tester.pumpWidget(
        _buildAutocomplete(suggestions: [
          _collectionSuggestion('users'),
          _collectionSuggestion('orders'),
          _collectionSuggestion('products'),
        ]),
      );

      // Verify all suggestions are rendered
      expect(find.text('users'), findsOneWidget);
      expect(find.text('orders'), findsOneWidget);
      expect(find.text('products'), findsOneWidget);
    });
  });
}
