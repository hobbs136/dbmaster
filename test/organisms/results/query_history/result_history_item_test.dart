import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/query_history.dart';
import 'package:dbmaster/molecules/compact_popup_menu_item.dart';
import 'package:dbmaster/organisms/results/query_history/result_history_item.dart';
import 'package:dbmaster/providers/app_provider.dart';

import 'history_test_helper.dart';

void main() {
  setupHistoryTestBinding();

  group('ResultHistoryItem', () {
    final history = QueryHistory(
      id: 'h1',
      sql: 'SELECT * FROM users',
      timestamp: DateTime(2026, 7, 7, 10, 30),
      connectionId: 'conn-1',
    );

    Widget buildItem({
      required VoidCallback onDoubleTap,
      VoidCallback? onDelete,
      QueryHistory? item,
    }) {
      return buildHistoryTestApp(
        AppProvider(),
        child: ResultHistoryItem(
          history: item ?? history,
          onDoubleTap: onDoubleTap,
          onDelete: onDelete,
        ),
      );
    }

    testWidgets('renders SQL preview and timestamp', (tester) async {
      await tester.pumpWidget(buildItem(onDoubleTap: () {}));
      await tester.pumpAndSettle();

      expect(find.text('SELECT * FROM users'), findsOneWidget);
      expect(find.text('07-07 10:30'), findsOneWidget);
    });

    testWidgets('renders Mongo query preview', (tester) async {
      final mongoHistory = QueryHistory(
        id: 'h2',
        sql: "db.users.find({age: {\$gte: 18}})",
        timestamp: DateTime(2026, 7, 7, 11, 30),
        connectionId: 'conn-1',
        databaseType: DatabaseType.mongodb,
      );

      await tester.pumpWidget(buildItem(onDoubleTap: () {}, item: mongoHistory));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('db.users.find'),
        findsOneWidget,
      );
      expect(find.text('07-07 11:30'), findsOneWidget);
    });

    testWidgets('double-tap invokes onHistoryDoubleTapped callback', (
      tester,
    ) async {
      var doubleTapped = false;
      await tester.pumpWidget(
        buildItem(onDoubleTap: () => doubleTapped = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ResultHistoryItem));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(ResultHistoryItem));
      await tester.pumpAndSettle();

      expect(doubleTapped, isTrue);
    });

    testWidgets('double-tap callback completes within 2 seconds', (
      tester,
    ) async {
      var doubleTapped = false;
      await tester.pumpWidget(
        buildItem(onDoubleTap: () => doubleTapped = true),
      );
      await tester.pumpAndSettle();

      final stopwatch = Stopwatch()..start();
      await tester.tap(find.byType(ResultHistoryItem));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(ResultHistoryItem));
      await tester.pumpAndSettle();
      stopwatch.stop();

      expect(doubleTapped, isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });

    testWidgets('right-click opens delete context menu', (tester) async {
      var deleted = false;
      await tester.pumpWidget(
        buildItem(onDoubleTap: () {}, onDelete: () => deleted = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(ResultHistoryItem),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.byType(CompactPopupMenuItem<void>), findsOneWidget);

      await tester.tap(find.byType(CompactPopupMenuItem<void>));
      await tester.pumpAndSettle();

      expect(deleted, isTrue);
    });
  });
}
