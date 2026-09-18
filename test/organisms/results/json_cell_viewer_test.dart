// Phase F — tests for JSON cell viewer widget
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/organisms/results/json_cell_viewer.dart';
import 'package:dbmaster/theme/app_theme.dart';

void main() {
  group('JsonCellViewer', () {
    // Helper: pump the dialog directly for reliable testing
    Future<void> pumpViewer(
      WidgetTester tester, {
      String jsonString = '{}',
      String columnName = 'data',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showJsonCellViewer(
                  context,
                  jsonString: jsonString,
                  columnName: columnName,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    testWidgets('dialog opens with column name in title', (tester) async {
      await pumpViewer(tester, jsonString: '{"a": 1}', columnName: 'metadata');

      // AlertDialog must be visible
      expect(find.byType(AlertDialog), findsOneWidget);
      // Title text contains column name
      expect(find.text('metadata'), findsOneWidget);
    });

    testWidgets('renders JSON object with top-level keys visible', (tester) async {
      await pumpViewer(tester, jsonString: '{"name": "test", "count": 42}');

      // Root expanded, keys appear with ": " suffix
      expect(find.text('name: '), findsOneWidget);
      expect(find.text('count: '), findsOneWidget);
      // Values: strings quoted, numbers unquoted
      expect(find.text('"test"'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });

    testWidgets('renders JSON array with indexed entries', (tester) async {
      await pumpViewer(tester,
          jsonString: '[1, 2, 3]', columnName: 'items');

      // Root expanded, array indices appear as [0]:, [1]:, etc.
      expect(find.text('[0]: '), findsOneWidget);
      expect(find.text('[1]: '), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // the value 1 (at depth 1)
    });

    testWidgets('handles empty object without crashing', (tester) async {
      await pumpViewer(tester, jsonString: '{}');

      // Root container label should show
      expect(find.text('{} (root)'), findsOneWidget);
      // AlertDialog still present (no crash)
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('handles null value in JSON', (tester) async {
      await pumpViewer(tester, jsonString: '{"key": null}');

      expect(find.text('key: '), findsOneWidget);
      expect(find.text('null'), findsOneWidget);
    });

    testWidgets('handles boolean values with correct colors', (tester) async {
      await pumpViewer(tester,
          jsonString: '{"active": true, "deleted": false}');

      expect(find.text('true'), findsOneWidget);
      expect(find.text('false'), findsOneWidget);
    });

    testWidgets('handles invalid JSON with error display', (tester) async {
      await pumpViewer(tester, jsonString: 'not valid json');

      // Error message should be shown
      expect(find.text('Invalid JSON'), findsOneWidget);
      // Raw text should also be visible
      expect(find.text('not valid json'), findsOneWidget);
    });

    testWidgets('search field is present in tree view', (tester) async {
      await pumpViewer(tester, jsonString: '{"name": "test"}');

      // Search TextField should be present
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Close button dismisses dialog', (tester) async {
      await pumpViewer(tester, jsonString: '{"a": 1}');

      // Tap the "Close" TextButton
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('columnName appears in dialog title', (tester) async {
      await pumpViewer(tester,
          jsonString: '{"x": 1}', columnName: 'user_profile');

      expect(find.text('user_profile'), findsOneWidget);
    });

    // HOTFIX regression: HStore-like content (unquoted keys) must not crash
    testWidgets('handles HStore-like invalid JSON without crashing',
        (tester) async {
      await pumpViewer(tester,
          jsonString: '{brand:logitech,color:black,layout:87key}');

      // Error UI should be shown, not crash
      expect(find.text('Invalid JSON'), findsOneWidget);
      // Raw text displayed in error section
      expect(
        find.text('{brand:logitech,color:black,layout:87key}'),
        findsOneWidget,
      );
    });

    // HOTFIX regression: mixed brackets must not crash
    testWidgets('handles mixed bracket invalid JSON without crashing',
        (tester) async {
      await pumpViewer(tester,
          jsonString: '{brand:logitech,color:black]');

      expect(find.text('Invalid JSON'), findsOneWidget);
      // Still shows the dialog (no crash)
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    // HOTFIX #2: valid jsonEncode output from Dart Map (PG driver behavior)
    testWidgets('renders valid JSON from jsonEncode(Map)', (tester) async {
      final mapValue = <String, dynamic>{
        'brand': 'logitech',
        'color': 'black',
        'layout': '87key',
      };
      // Simulate what the fixed onJsonCellDoubleTap does
      final jsonString = jsonEncode(mapValue);
      await pumpViewer(tester, jsonString: jsonString);

      // Valid JSON: keys with quotes rendered
      expect(find.text('brand: '), findsOneWidget);
      expect(find.text('"logitech"'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });
}
