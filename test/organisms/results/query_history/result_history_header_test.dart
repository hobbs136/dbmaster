import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/organisms/results/query_history/result_history_header.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'history_test_helper.dart';

void main() {
  setupHistoryTestBinding();

  group('ResultHistoryHeader', () {
    testWidgets('clear-all button triggers confirmation callback', (
      tester,
    ) async {
      var cleared = false;
      await tester.pumpWidget(
        buildHistoryTestApp(
          AppProvider(),
          child: ResultHistoryHeader(
            searchQuery: '',
            onSearchChanged: (_) {},
            onClearAll: () => cleared = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.brushCleaning));
      await tester.pumpAndSettle();

      expect(cleared, isTrue);
    });

    testWidgets('typing in search field invokes onSearchChanged', (
      tester,
    ) async {
      var lastQuery = '';
      await tester.pumpWidget(
        buildHistoryTestApp(
          AppProvider(),
          child: ResultHistoryHeader(
            searchQuery: '',
            onSearchChanged: (value) => lastQuery = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'users');
      await tester.pumpAndSettle();

      expect(lastQuery, 'users');
    });
  });
}
