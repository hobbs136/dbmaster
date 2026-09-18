import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/query_history.dart';
import 'package:dbmaster/organisms/results/query_history/result_history_empty.dart';
import 'package:dbmaster/organisms/results/query_history/result_history_table.dart';
import 'package:dbmaster/organisms/results/query_history/result_history_view.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'history_test_helper.dart';

void main() {
  setupHistoryTestBinding();

  group('ResultHistoryView', () {
    late AppProvider appProvider;
    late String tabId;

    setUp(() {
      appProvider = AppProvider();
      tabId = 'tab-${Random().nextInt(1000000)}';
    });

    Widget buildView({String? connectionId}) {
      return buildHistoryTestApp(
        appProvider,
        child: ResultHistoryView(
          tabId: tabId,
          connectionId: connectionId,
          onHistoryDoubleTapped: (_) {},
        ),
      );
    }

    testWidgets('renders empty state when no history exists', (tester) async {
      await tester.pumpWidget(buildView(connectionId: 'conn-empty'));
      await tester.pumpAndSettle();

      expect(find.byType(ResultHistoryEmpty), findsOneWidget);
    });

    testWidgets('renders history entries as a table with expected columns', (
      tester,
    ) async {
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-a',
        sql: 'SELECT today',
        databaseType: DatabaseType.mysql,
      );
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-a',
        sql: 'SELECT yesterday',
        databaseType: DatabaseType.mysql,
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
      );

      await tester.pumpWidget(buildView(connectionId: 'conn-a'));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ResultHistoryView)),
      )!;
      expect(find.byType(ResultHistoryTable), findsOneWidget);
      expect(find.text(l10n.queryHistoryExecutedAt), findsOneWidget);
      expect(find.text(l10n.queryHistorySqlPreview), findsOneWidget);
      expect(find.text(l10n.queryHistoryDuration), findsOneWidget);
      expect(find.text(l10n.queryHistoryRowCount), findsOneWidget);
      expect(find.text(l10n.status), findsOneWidget);
      expect(find.text('SELECT today'), findsOneWidget);
      expect(find.text('SELECT yesterday'), findsOneWidget);
    });

    testWidgets('invokes onHistoryTapped when a table row is tapped', (
      tester,
    ) async {
      QueryHistory? tappedHistory;
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-a',
        sql: 'SELECT tap_test',
        databaseType: DatabaseType.mysql,
      );

      await tester.pumpWidget(
        buildHistoryTestApp(
          appProvider,
          child: ResultHistoryView(
            tabId: tabId,
            connectionId: 'conn-a',
            onHistoryDoubleTapped: (_) {},
            onHistoryTapped: (history) => tappedHistory = history,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SELECT tap_test'));
      // When both onTap and onDoubleTap are registered, InkWell waits for the
      // double-tap timeout before firing onTap.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(tappedHistory, isNotNull);
      expect(tappedHistory!.sql, 'SELECT tap_test');
    });

    testWidgets('search filters visible history entries', (tester) async {
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-a',
        sql: 'SELECT alpha',
        databaseType: DatabaseType.mysql,
      );
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-a',
        sql: 'SELECT beta',
        databaseType: DatabaseType.mysql,
      );

      await tester.pumpWidget(buildView(connectionId: 'conn-a'));
      await tester.pumpAndSettle();

      expect(find.text('SELECT alpha'), findsOneWidget);
      expect(find.text('SELECT beta'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pumpAndSettle();

      expect(find.text('SELECT alpha'), findsOneWidget);
      expect(find.text('SELECT beta'), findsNothing);
    });

    testWidgets('empty search result state is shown', (tester) async {
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-a',
        sql: 'SELECT alpha',
        databaseType: DatabaseType.mysql,
      );

      await tester.pumpWidget(buildView(connectionId: 'conn-a'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nomatch');
      await tester.pumpAndSettle();

      expect(find.text('SELECT alpha'), findsNothing);
      expect(find.byType(ResultHistoryEmpty), findsOneWidget);
    });

    testWidgets('pagination switches visible records', (tester) async {
      final base = DateTime.now();
      for (var i = 0; i < 55; i++) {
        await appProvider.queryHistory.addQueryHistory(
          connectionId: 'conn-a',
          sql: 'SELECT item $i',
          databaseType: DatabaseType.mysql,
          timestamp: base.subtract(Duration(milliseconds: i)),
        );
      }

      expect(appProvider.queryHistory.historyCount, 55);
      await tester.pumpWidget(buildView(connectionId: 'conn-a'));
      await tester.pumpAndSettle();

      expect(find.text('SELECT item 0'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.chevronsRight));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('SELECT item 0'), findsNothing);
    });

    testWidgets(
      'invokes onHistoryDoubleTapped when a table row is double-tapped',
      (tester) async {
        QueryHistory? doubleTappedHistory;
        await appProvider.queryHistory.addQueryHistory(
          connectionId: 'conn-a',
          sql: 'SELECT double_tap_test',
          databaseType: DatabaseType.mysql,
        );

        await tester.pumpWidget(
          buildHistoryTestApp(
            appProvider,
            child: ResultHistoryView(
              tabId: tabId,
              connectionId: 'conn-a',
              onHistoryDoubleTapped: (history) => doubleTappedHistory = history,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('SELECT double_tap_test'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('SELECT double_tap_test'));
        await tester.pumpAndSettle();

        expect(doubleTappedHistory, isNotNull);
        expect(doubleTappedHistory!.sql, 'SELECT double_tap_test');
      },
    );

    testWidgets('loads 500 history entries within 1 second', (tester) async {
      final stopwatch = Stopwatch()..start();
      final base = DateTime.now();
      for (var i = 0; i < 500; i++) {
        await appProvider.queryHistory.addQueryHistory(
          connectionId: 'conn-a',
          sql: 'SELECT load $i',
          databaseType: DatabaseType.mysql,
          timestamp: base.subtract(Duration(milliseconds: i)),
        );
      }

      await tester.pumpWidget(buildView(connectionId: 'conn-a'));
      await tester.pumpAndSettle();
      stopwatch.stop();

      expect(find.text('SELECT load 0'), findsOneWidget);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    testWidgets('search filtering completes within 300 milliseconds', (
      tester,
    ) async {
      final base = DateTime.now();
      for (var i = 0; i < 100; i++) {
        await appProvider.queryHistory.addQueryHistory(
          connectionId: 'conn-a',
          sql: 'SELECT val $i',
          databaseType: DatabaseType.mysql,
          timestamp: base.subtract(Duration(milliseconds: i)),
        );
      }

      await tester.pumpWidget(buildView(connectionId: 'conn-a'));
      await tester.pumpAndSettle();

      final stopwatch = Stopwatch()..start();
      await tester.enterText(find.byType(TextField), 'val 99');
      await tester.pumpAndSettle();
      stopwatch.stop();

      expect(find.text('SELECT val 99'), findsOneWidget);
      expect(stopwatch.elapsedMilliseconds, lessThan(300));
    });

    testWidgets('renders Mongo query history entries', (tester) async {
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-mongo',
        sql: "db.users.find({age: {\$gte: 18}})",
        databaseType: DatabaseType.mongodb,
      );
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-mongo',
        sql:
            "db.orders.updateOne({status: 'pending'}, {\$set: {status: 'shipped'}})",
        databaseType: DatabaseType.mongodb,
      );

      await tester.pumpWidget(buildView(connectionId: 'conn-mongo'));
      await tester.pumpAndSettle();

      expect(find.byType(ResultHistoryTable), findsOneWidget);
      expect(find.textContaining('db.users.find'), findsOneWidget);
      expect(find.textContaining('db.orders.updateOne'), findsOneWidget);
    });

    testWidgets('search filters Mongo query history entries', (tester) async {
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-mongo',
        sql: "db.users.find({age: {\$gte: 18}})",
        databaseType: DatabaseType.mongodb,
      );
      await appProvider.queryHistory.addQueryHistory(
        connectionId: 'conn-mongo',
        sql:
            "db.orders.updateOne({status: 'pending'}, {\$set: {status: 'shipped'}})",
        databaseType: DatabaseType.mongodb,
      );

      await tester.pumpWidget(buildView(connectionId: 'conn-mongo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('db.users.find'), findsOneWidget);
      expect(find.textContaining('db.orders.updateOne'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'users');
      await tester.pumpAndSettle();

      expect(find.textContaining('db.users.find'), findsOneWidget);
      expect(find.textContaining('db.orders.updateOne'), findsNothing);
    });
  });
}
