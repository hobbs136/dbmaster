//! Widget tests for the drift task list dialog. Covers:
//! - smoke render + graceful not-connected error (original case);
//! - U09 interval edit: the chip opens a one-field dialog and submits a whole
//!   replacement `config` (pg_schemas preserved) via `patchTaskConfig`;
//! - U09 run-now polling: after the 202, the dialog polls run history until
//!   the run reaches a terminal state instead of a blind fixed delay.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/drift_models.dart';
import 'package:dbmaster/organisms/server/drift/drift_task_list_dialog.dart';
import 'package:dbmaster/services/drift_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// In-memory FlutterSecureStorage fake (same shape as the one in
/// drift_api_service_test.dart — duplicated because the test patterns
/// explicitly allow reasonable duplication across test helpers).
class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.value(_store[key]);

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
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
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    _store.remove(key);
    return Future.value();
  }
}

DriftTask _task({
  String configJson = '{"interval_minutes":5,"pg_schemas":["public","audit"]}',
  String? lastRunAt = '2026-08-17T09:00:00Z',
}) {
  return DriftTask.fromJson({
    'id': 't1',
    'name': 'prod watch',
    'source_db_id': 'c1',
    'enabled': true,
    'config': configJson,
    'notify_channels': '[]',
    'created_at': '2026-08-01T00:00:00Z',
    'last_run_at': lastRunAt,
    'last_status': 'succeeded',
  });
}

DriftSourceConnection get _conn => DriftSourceConnection.fromJson({
  'id': 'c1',
  'name': 'prod mysql',
  'db_type': 'mysql',
  'host': 'db.example',
  'port': 3306,
  'username': 'ro',
  'kind': 'source_drift',
  'password_encrypted': '',
});

DriftRunHistoryEntry _runRow({
  required String startedAt,
  required String status,
  String? summaryJson,
}) {
  return DriftRunHistoryEntry.fromJson({
    'id': 'run-x',
    'task_id': 't1',
    'started_at': startedAt,
    'finished_at': status == 'running' ? null : startedAt,
    'status': status,
    'error': null,
    'summary': summaryJson,
    'triggered_by': 'manual:u1',
  });
}

/// Stateful fake: counts refreshes, mirrors interval patches into the served
/// task, and serves a programmable run-history sequence for the polling test.
class _FakeApi extends DriftApiService {
  int listCalls = 0;
  int runNowCalls = 0;
  Map<String, dynamic>? patchedConfig;
  final List<DriftRunHistoryEntry> Function() runHistory;
  DriftTask task = _task();

  _FakeApi({List<DriftRunHistoryEntry> Function()? runHistory})
    : runHistory = runHistory ?? (() => const []);

  @override
  Future<List<DriftTask>> listDriftTasks() async {
    listCalls++;
    return [task];
  }

  @override
  Future<List<DriftSourceConnection>> listSourceDriftConnections() async => [
    _conn,
  ];

  @override
  Future<void> runTaskNow(String taskId) async {
    runNowCalls++;
  }

  @override
  Future<List<DriftRunHistoryEntry>> listRunHistory(
    String taskId, {
    int limit = 50,
  }) async {
    return runHistory();
  }

  @override
  Future<Map<String, dynamic>> patchTaskConfig(
    String taskId,
    Map<String, dynamic> config,
  ) async {
    patchedConfig = config;
    // Mirror the whole-config replacement so the next refresh shows the new
    // interval, like the real Server does.
    task = _task(configJson: jsonEncode(config));
    return {'id': taskId, 'config': jsonEncode(config)};
  }
}

Future<void> _pumpApp(WidgetTester tester, {DriftApiService? api}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showDriftTaskListDialog(context, api: api),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
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
    await _openDialog(tester);

    // Title is visible.
    expect(find.text('Schema Drift Alerts'), findsOneWidget);
    // Refresh + Create buttons present in header.
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
    expect(find.byIcon(LucideIcons.plus), findsOneWidget);

    // The DriftApiService short-circuits with a DriftApiException when not
    // connected; the dialog renders an error view with a Retry button after
    // the future resolves. The exact message comes from the service constant.
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.text('Retry'), findsWidgets);
  });

  testWidgets('U09: interval chip opens the edit dialog and submits a whole '
      'replacement config preserving pg_schemas', (tester) async {
    final api = _FakeApi();
    await _pumpApp(tester, api: api);
    await _openDialog(tester);

    // The chip renders the current interval and an edit affordance.
    expect(find.text('Every 5 min'), findsOneWidget);

    // The whole chip is the tap target (its edit icon is ambiguous with the
    // row's edit-task button under byIcon).
    await tester.tap(find.text('Every 5 min'));
    await tester.pumpAndSettle();

    // One-field dialog prefilled with the current interval.
    expect(find.text('Edit Check Interval'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '5'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '15');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(api.patchedConfig, isNotNull);
    // Whole-config replacement: interval overridden, sibling key preserved.
    expect(api.patchedConfig!['interval_minutes'], 15);
    expect(api.patchedConfig!['pg_schemas'], ['public', 'audit']);
    // The list refreshed after the patch (initial load + post-patch).
    expect(api.listCalls, 2);
    // Chip now shows the new interval.
    expect(find.text('Every 15 min'), findsOneWidget);
  });

  testWidgets('U09: interval edit rejects out-of-range values', (tester) async {
    final api = _FakeApi();
    await _pumpApp(tester, api: api);
    await _openDialog(tester);

    await tester.tap(find.text('Every 5 min'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '9999');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    // Validation message shown; dialog still open; nothing patched.
    expect(
      find.text('Interval must be between 1 and 1440 minutes.'),
      findsOneWidget,
    );
    expect(api.patchedConfig, isNull);
  });

  testWidgets(
    'U09: run-now polls run history to a terminal state, then refreshes '
    '(no blind delay)',
    (tester) async {
      // Sequence: first poll sees the running row, second sees it finished.
      var poll = 0;
      final api = _FakeApi(
        runHistory: () {
          poll++;
          return poll == 1
              ? [_runRow(startedAt: '2026-08-17T10:00:00Z', status: 'running')]
              : [
                  _runRow(
                    startedAt: '2026-08-17T10:00:00Z',
                    status: 'succeeded',
                    summaryJson:
                        '{"drift_count":1,"snapshot_id":"snap-2","baseline_snapshot_id":"snap-1"}',
                  ),
                ];
        },
      );
      await _pumpApp(tester, api: api);
      await _openDialog(tester);
      expect(api.listCalls, 1);

      await tester.tap(find.byIcon(LucideIcons.play));
      await tester.pump(); // 202 handled, snackbar queued, poll loop scheduled.

      // First poll tick (2s): still running → loop continues. NOTE: plain pump,
      // not pumpAndSettle — the row spinner keeps scheduling frames, and
      // pumpAndSettle would fast-forward the fake clock straight through the
      // remaining poll ticks.
      await tester.pump(const Duration(seconds: 2));
      expect(poll, 1);
      // Run not yet terminal → no refresh beyond the initial load.
      expect(api.listCalls, 1);

      // Second poll tick: terminal row newer than the anchor (09:00) →
      // refresh fires and the spinner clears.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(); // flush the refresh microtasks
      expect(poll, 2);
      expect(api.listCalls, 2);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
