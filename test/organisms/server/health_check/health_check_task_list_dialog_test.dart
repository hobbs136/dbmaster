//! Widget smoke test for the health check task list dialog. Verifies the
//! dialog pumps under a minimal MaterialApp, renders the title, and surfaces a
//! graceful error path when no Server session is configured (mirrors
//! drift_task_list_dialog_test's shape).

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/health_summary.dart';
import 'package:dbmaster/organisms/server/health_check/health_check_task_list_dialog.dart';
import 'package:dbmaster/services/health_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// In-memory FlutterSecureStorage fake (same shape as the drift dialog test).
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) => Future.value(_store[key]);

  @override
  Future<void> write({
    required String key,
    required String? value,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) {
    if (value == null) {
      _store.remove(key);
    } else {
      _store[key] = value;
    }
    return Future.value();
  }

  @override
  Future<void> delete({
    required String key,
    Object? iOptions,
    Object? aOptions,
    Object? lOptions,
    Object? webOptions,
    Object? mOptions,
    Object? wOptions,
  }) {
    _store.remove(key);
    return Future.value();
  }
}

/// Fake service returning one task whose last run failed (U06 scenario).
class _FakeApi extends HealthApiService {
  @override
  Future<List<HealthTask>> listHealthTasks() async => [
    HealthTask(
      id: 'task-1',
      name: 'prod health',
      sourceDbId: 'conn-1',
      enabled: true,
      cronExpr: '*/5 * * * *',
      lastRunAt: '2026-08-17T10:00:00Z',
      lastStatus: 'failed',
    ),
  ];

  @override
  Future<List<HealthCheckResultDto>> listHealthResults(
    String taskId, {
    int? limit,
  }) async {
    return [
      HealthCheckResultDto(
        id: 'r1',
        taskId: taskId,
        startedAt: '2026-08-17T10:00:00Z',
        status: 'failed',
        metricsSummaryJson: '{}',
        alertChangesJson: '[]',
        triggeredBy: 'scheduler',
        error: 'mysql connect failed: connection refused',
      ),
    ];
  }
}

Future<void> _pumpApp(WidgetTester tester, {HealthApiService? api}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showHealthCheckTaskListDialog(context, api: api),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    ServerConnection.resetForTesting();
    ServerConnection().testSecureStorage = _FakeSecureStorage();
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  testWidgets('renders title and surfaces not-connected error gracefully', (
    tester,
  ) async {
    await _pumpApp(tester);

    // Open the dialog.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Title is visible (healthDialogTitle).
    expect(find.text('Health Check'), findsOneWidget);
    // Header close button present. (Refresh is NOT asserted here — the error
    // view also has a refresh button, so there'd be two once the future
    // rejects, which listHealthTasks does synchronously when not connected.)
    expect(find.byIcon(LucideIcons.x), findsOneWidget);
    // Header create-task (Add) button — present in the header only (the error
    // view has no add affordance), so the count is exactly one.
    expect(find.byIcon(LucideIcons.plus), findsOneWidget);

    // The HealthApiService short-circuits with a HealthApiException when not
    // connected; the dialog renders an error view after the future rejects.
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Failed to load health results.'), findsOneWidget);
  });

  testWidgets(
    'U06: failed task shows critical status, inline error, and history entry',
    (tester) async {
      await _pumpApp(tester, api: _FakeApi());
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The task row renders with the critical label (healthStatusCritical).
      expect(find.text('Check failing'), findsOneWidget);
      expect(find.text('prod health'), findsOneWidget);

      // Expand the row: the failed result line + its error text appear.
      await tester.tap(find.text('prod health'));
      await tester.pumpAndSettle();
      expect(find.text('Failed'), findsOneWidget);
      expect(
        find.textContaining('mysql connect failed: connection refused'),
        findsOneWidget,
      );

      // The full-history affordance is present and opens the history dialog.
      expect(find.text('View full history'), findsOneWidget);
      await tester.tap(find.text('View full history'));
      await tester.pumpAndSettle();
      expect(find.text('Run History'), findsOneWidget);
    },
  );
}
