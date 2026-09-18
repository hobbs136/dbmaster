import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/organisms/results/query_history/result_history_pagination.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'history_test_helper.dart';

void main() {
  setupHistoryTestBinding();

  group('ResultHistoryPagination', () {
    testWidgets('is hidden when totalPages is 1', (tester) async {
      await tester.pumpWidget(
        buildHistoryTestApp(
          AppProvider(),
          child: ResultHistoryPagination(
            currentPage: 1,
            totalPages: 1,
            onPageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ResultHistoryPagination), findsOneWidget);
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.text('1 / 1'), findsNothing);
    });

    testWidgets('renders controls when totalPages is greater than 1', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildHistoryTestApp(
          AppProvider(),
          child: ResultHistoryPagination(
            currentPage: 1,
            totalPages: 3,
            onPageChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 / 3'), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronsLeft), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronsRight), findsOneWidget);
    });

    testWidgets('page switching invokes onPageChanged', (tester) async {
      var newPage = 0;
      await tester.pumpWidget(
        buildHistoryTestApp(
          AppProvider(),
          child: ResultHistoryPagination(
            currentPage: 1,
            totalPages: 3,
            onPageChanged: (page) => newPage = page,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.chevronsRight));
      await tester.pumpAndSettle();

      expect(newPage, 3);
    });
  });
}
