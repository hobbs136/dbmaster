//! Widget tests for the slow-query stats dialog (reports-M1 / #29). Mirrors
//! `health_check_task_list_dialog_test`'s fake-service pattern.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/drift_models.dart';
import 'package:dbmaster/models/query_stats_models.dart';
import 'package:dbmaster/organisms/server/slow_query/slow_query_dialog.dart';
import 'package:dbmaster/services/query_stats_api_service.dart';
import 'package:dbmaster/services/server_connections_api_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

QueryStatsDigestSummary _item(String digest, {int count = 2}) =>
    QueryStatsDigestSummary(
      digest: digest,
      dbKind: 'mysql',
      connId: 'c1',
      count: count,
      totalMs: 6000,
      avgMs: 2000,
      maxMs: 3000,
      firstSeen: '2026-08-27T10:00:00+00:00',
      lastSeen: '2026-08-27T11:00:00+00:00',
      sampleSqlText: 'SELECT * FROM t WHERE id = 42',
    );

class _FakeApi extends QueryStatsApiService {
  final QueryStatsSummary? summary;
  final QueryStatsDetailPage detail;
  final Object? summaryError;

  _FakeApi({this.summary, this.summaryError})
      : detail = QueryStatsDetailPage(
          items: [
            QueryStatsRecord(
              id: 'r1',
              source: 'gateway',
              connId: 'c1',
              dbKind: 'mysql',
              database: 'chinook',
              digest: 'SELECT * FROM t WHERE id = ?',
              sqlText: 'SELECT * FROM t WHERE id = 42',
              elapsedMs: 3000,
              rowCount: 10,
              affectedRows: null,
              status: 'ok',
              errorCode: null,
              userId: 'u1',
              entry: 'sync_query',
              capturedAt: '2026-08-27T11:00:00+00:00',
            ),
          ],
          total: 1,
          limit: 50,
          offset: 0,
        );

  @override
  Future<QueryStatsSummary> fetchSummary({
    String window = QueryStatsWindow.day,
    String? connId,
    String sort = QueryStatsSort.totalMs,
    int limit = 20,
  }) async {
    if (summaryError != null) throw summaryError!;
    return summary ??
        const QueryStatsSummary(
          items: [],
          meta: QueryStatsMeta(thresholdMs: 1000, storeSql: true, retentionDays: 14),
        );
  }

  @override
  Future<QueryStatsDetailPage> fetchDetail({
    String window = QueryStatsWindow.day,
    String? connId,
    String? digest,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async =>
      detail;
}

class _FakeConnectionsApi extends ServerConnectionsApiService {
  @override
  Future<List<DriftSourceConnection>> listConnections() async => [
        const DriftSourceConnection(
          id: 'c1',
          name: 'prod mysql',
          dbType: 'mysql',
          host: '192.0.2.128',
          port: 3306,
          username: 'root',
          defaultDatabase: 'mysql',
          kind: 'collab',
          passwordEncrypted: 'CIPHER',
        ),
      ];
}

Future<void> _pumpApp(
  WidgetTester tester, {
  QueryStatsApiService? api,
  ServerConnectionsApiService? connectionsApi,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showSlowQueryDialog(
              context,
              api: api,
              connectionsApi: connectionsApi,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders title, scope banner and digest cards', (tester) async {
    await _pumpApp(
      tester,
      api: _FakeApi(
        summary: QueryStatsSummary(
          items: [_item('SELECT * FROM t WHERE id = ?')],
          meta: const QueryStatsMeta(
              thresholdMs: 1000, storeSql: true, retentionDays: 14),
        ),
      ),
      connectionsApi: _FakeConnectionsApi(),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Title + scope banner carry the capture-scope caveat (R4 口径横幅).
    expect(find.text('Slow Query Stats'), findsOneWidget);
    expect(
      find.textContaining('slower than 1000 ms'),
      findsOneWidget,
    );
    // Digest card: monospace digest + stats line with the formatted numbers.
    expect(find.textContaining('SELECT * FROM t WHERE id = ?'), findsWidgets);
    expect(find.textContaining('2 calls'), findsOneWidget);
    expect(find.textContaining('mysql'), findsWidgets);
  });

  testWidgets('empty window renders the empty view', (tester) async {
    await _pumpApp(
      tester,
      api: _FakeApi(),
      connectionsApi: _FakeConnectionsApi(),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('No slow queries'), findsOneWidget);
  });

  testWidgets('load failure renders the error view with retry', (tester) async {
    await _pumpApp(
      tester,
      api: _FakeApi(summaryError: const QueryStatsApiException('boom')),
      connectionsApi: _FakeConnectionsApi(),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(find.text('Failed to load slow query stats.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('tapping a digest card opens the detail drill-down', (tester) async {
    await _pumpApp(
      tester,
      api: _FakeApi(
        summary: QueryStatsSummary(
          items: [_item('SELECT * FROM t WHERE id = ?')],
          meta: const QueryStatsMeta(
              thresholdMs: 1000, storeSql: true, retentionDays: 14),
        ),
      ),
      connectionsApi: _FakeConnectionsApi(),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Tap the digest card (the card InkWell covers the monospace text).
    await tester.tap(find.textContaining('SELECT * FROM t WHERE id = ?').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Detail dialog shows the sample row: plaintext SQL + copy affordance +
    // entry label.
    expect(find.textContaining('sync_query'), findsOneWidget);
    expect(find.text('Copy SQL'), findsOneWidget);
    expect(find.byIcon(LucideIcons.copy), findsOneWidget);
  });
}
