//! Widget tests for the drift diff dialog (U09):
//! - opened from a run-history row it preselects that run's snapshot pair and
//!   auto-compares (no manual "Compare" click needed);
//! - the third panel renders the shared migration-DDL preview for the selected
//!   object (same widget as the local Schema Diff page).

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/drift_models.dart';
import 'package:dbmaster/organisms/server/drift/drift_diff_page.dart';
import 'package:dbmaster/services/drift_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

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
  }) =>
      Future.value(_store[key]);

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

/// Minimal server-shaped schema_json (BTreeMap-keyed, no views/procs). The
/// older snapshot carries an extra `email` column so the compare produces a
/// modified table with an added-column diff.
String _schemaJson({required bool withEmail}) => '''
{
  "tables": {
    "public.users": {
      "columns": {
        "id": {"ordinal": 1, "data_type": "int", "is_nullable": false},
        ${withEmail ? '"email": {"ordinal": 2, "data_type": "varchar", "char_max_length": 255, "is_nullable": true},' : ''}
        "name": {"ordinal": 3, "data_type": "varchar", "char_max_length": 80, "is_nullable": true}
      },
      "indexes": {},
      "primary_key": {"columns": ["id"]}
    }
  }
}
''';

class _FakeApi extends DriftApiService {
  final List<String> fetchedSnapshotIds = [];

  @override
  Future<List<DriftSnapshotMeta>> listSnapshots(String connectionId,
      {int limit = 50}) async {
    return [
      DriftSnapshotMeta.fromJson({
        'id': 'snap-new',
        'connection_id': connectionId,
        'captured_at': '2026-08-17T10:00:00Z',
        'schema_hash': 'h-new',
        'prior_hash': 'h-old',
        'task_id': 't1',
        'change_count': 1,
      }),
      DriftSnapshotMeta.fromJson({
        'id': 'snap-old',
        'connection_id': connectionId,
        'captured_at': '2026-08-17T09:00:00Z',
        'schema_hash': 'h-old',
        'prior_hash': null,
        'task_id': 't1',
        'change_count': 0,
      }),
    ];
  }

  @override
  Future<DriftSnapshot> getSnapshot(String snapshotId) async {
    fetchedSnapshotIds.add(snapshotId);
    return DriftSnapshot.fromJson({
      'id': snapshotId,
      'connection_id': 'c1',
      'captured_at':
          snapshotId == 'snap-new' ? '2026-08-17T10:00:00Z' : '2026-08-17T09:00:00Z',
      'schema_hash': snapshotId == 'snap-new' ? 'h-new' : 'h-old',
      'prior_hash': null,
      'task_id': 't1',
      'change_count': 0,
      // Older side (source) has email; newer (target) does not → added column.
      'schema_json': _schemaJson(withEmail: snapshotId == 'snap-old'),
    });
  }
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

Future<void> _pumpDiff(
  WidgetTester tester, {
  required DriftApiService api,
  String? initialNewerId,
  String? initialOlderId,
}) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showDriftDiffDialog(
              context,
              api: api,
              connection: _conn,
              initialNewerId: initialNewerId,
              initialOlderId: initialOlderId,
            ),
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

  testWidgets(
      'U09: initial pair from a run row auto-compares without clicking '
      'Compare', (tester) async {
    final api = _FakeApi();
    await _pumpDiff(tester,
        api: api, initialNewerId: 'snap-new', initialOlderId: 'snap-old');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Both rows of the requested pair were fetched (auto-compare ran).
    expect(api.fetchedSnapshotIds, containsAll(['snap-new', 'snap-old']));
    // The compare result is visible: the modified table shows in the tree.
    expect(find.text('public.users'), findsOneWidget);
  });

  testWidgets(
      'U09: DDL preview panel renders migration DDL for the selected object',
      (tester) async {
    // The third panel needs a wide layout (fixed 280 + 360px panels) — size
    // the view like a real desktop window so it is shown. (Set both physical
    // size and DPR: setSurfaceSize alone is physical pixels, and the test
    // binding's default DPR of 3 would shrink it right back.)
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FakeApi();
    await _pumpDiff(tester,
        api: api, initialNewerId: 'snap-new', initialOlderId: 'snap-old');
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Select the modified table in the tree.
    await tester.tap(find.text('public.users'));
    await tester.pumpAndSettle();

    // Third panel: the shared DDL preview header + the added-column DDL for
    // `email` (present on the source side, absent on the target side).
    expect(find.text('Migration DDL'), findsOneWidget);
    expect(find.text('ADD COLUMN'), findsOneWidget);
    expect(find.textContaining('email'), findsWidgets);
    expect(find.textContaining('users'), findsWidgets);
  });

  testWidgets('without an initial pair nothing is fetched until Compare',
      (tester) async {
    final api = _FakeApi();
    await _pumpDiff(tester, api: api);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    // Snapshots listed, defaults preselected, but no auto-compare: the
    // "pick snapshots" placeholder is still showing.
    expect(api.fetchedSnapshotIds, isEmpty);
    expect(find.text('Pick two snapshots to compare'), findsOneWidget);
  });
}
