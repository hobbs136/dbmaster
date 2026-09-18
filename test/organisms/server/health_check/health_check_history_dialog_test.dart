//! Widget tests for the health check run-history dialog (U06 — failure
//! visibility): failed rows surface the redacted error text, success rows
//! render metrics, and the empty state shows the no-results copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/health_summary.dart';
import 'package:dbmaster/organisms/server/health_check/health_check_history_dialog.dart';
import 'package:dbmaster/services/health_api_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

HealthTask _task() => HealthTask(
  id: 'task-1',
  name: 'prod health',
  sourceDbId: 'conn-1',
  enabled: true,
  cronExpr: '*/5 * * * *',
  lastRunAt: '2026-08-17T10:00:00Z',
  lastStatus: 'failed',
);

HealthCheckResultDto _failedRow() => HealthCheckResultDto(
  id: 'r-failed',
  taskId: 'task-1',
  startedAt: '2026-08-17T10:00:00Z',
  finishedAt: '2026-08-17T10:00:01Z',
  status: 'failed',
  metricsSummaryJson: '{}',
  alertChangesJson: '[]',
  triggeredBy: 'scheduler',
  error: 'mysql connect failed: connection refused',
);

HealthCheckResultDto _successRow() => const HealthCheckResultDto(
  id: 'r-success',
  taskId: 'task-1',
  startedAt: '2026-08-17T09:00:00Z',
  finishedAt: '2026-08-17T09:00:01Z',
  status: 'success',
  metricsSummaryJson:
      '{"connectivity":{"ok":true,"latency_ms":5,"error":null},'
      '"db_type":"mysql","unsupported_metrics":[]}',
  alertChangesJson: '[]',
  triggeredBy: 'manual:u1',
);

class _FakeApi extends HealthApiService {
  _FakeApi({this.results = const [], this.shouldThrow = false});

  final List<HealthCheckResultDto> results;
  final bool shouldThrow;

  @override
  Future<List<HealthCheckResultDto>> listHealthResults(
    String taskId, {
    int? limit,
  }) async {
    if (shouldThrow) {
      throw const HealthApiException(
        'backend down',
        code: 'NETWORK',
        statusCode: 502,
      );
    }
    return results;
  }
}

Future<void> _pumpDialog(WidgetTester tester, {required HealthApiService api}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () =>
                showHealthCheckHistoryDialog(context, api: api, task: _task()),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('failed row surfaces the redacted error text', (tester) async {
    await _pumpDialog(
      tester,
      api: _FakeApi(results: [_failedRow(), _successRow()]),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Run History'), findsOneWidget);
    expect(find.text('prod health'), findsOneWidget);
    // The error line is rendered verbatim behind the localized prefix.
    expect(
      find.textContaining('mysql connect failed: connection refused'),
      findsOneWidget,
    );
    // Trigger chips distinguish scheduler vs manual runs.
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
  });

  testWidgets('success row renders the metrics breakdown', (tester) async {
    await _pumpDialog(tester, api: _FakeApi(results: [_successRow()]));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Connectivity row from HealthMetricsSummary.
    expect(find.textContaining('5 ms'), findsWidgets);
  });

  testWidgets('empty history shows the no-results empty state', (tester) async {
    await _pumpDialog(tester, api: _FakeApi(results: const []));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('No results yet'), findsOneWidget);
  });

  testWidgets('load failure shows the error message with retry', (
    tester,
  ) async {
    await _pumpDialog(tester, api: _FakeApi(shouldThrow: true));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('backend down'), findsOneWidget);
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
  });
}
