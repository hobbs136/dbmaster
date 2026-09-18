//! Widget tests for the Server connections management dialog (U05). Mirrors
//! `mcp_token_dialog_test.dart` (not-connected smoke) and adds list/kind-chip
//! and delete-warning coverage via a fake API subclass.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/drift_models.dart';
import 'package:dbmaster/organisms/server/connections/server_connections_dialog.dart';
import 'package:dbmaster/services/server_connections_api_service.dart';
import 'package:dbmaster/services/server_connection.dart';

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

DriftSourceConnection _conn(String id, {String kind = 'collab'}) =>
    DriftSourceConnection(
      id: id,
      name: 'conn-$id',
      dbType: 'mysql',
      host: '127.0.0.1',
      port: 3306,
      username: 'u',
      defaultDatabase: null,
      kind: kind,
      passwordEncrypted: 'ct',
    );

class _FakeApi extends ServerConnectionsApiService {
  _FakeApi({this.conns = const [], this.taskRefs = const []});

  List<DriftSourceConnection> conns;
  final List<Map<String, dynamic>> taskRefs;
  final List<String> deleted = [];

  @override
  bool get isConnected => true;

  @override
  Future<List<DriftSourceConnection>> listConnections() async => conns;

  @override
  Future<List<Map<String, dynamic>>> listTaskRefs() async => taskRefs;

  @override
  Future<void> deleteConnection(String id) async {
    deleted.add(id);
    conns = conns.where((c) => c.id != id).toList();
  }
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  ServerConnectionsApiService? api,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showServerConnectionsDialog(context, api: api),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ServerConnection.resetForTesting();
    ServerConnection().testSecureStorage = _FakeSecureStorage();
  });

  tearDown(() {
    ServerConnection.resetForTesting();
  });

  testWidgets('renders title + not-connected state gracefully', (tester) async {
    // No api → default service against a disconnected singleton.
    await _pumpDialog(tester);

    expect(find.text('Server connections'), findsOneWidget);
    expect(find.text('Not connected to a server.'), findsOneWidget);
  });

  testWidgets('lists rows with kind chips for collab and drift sources', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      api: _FakeApi(
        conns: [
          _conn('c1'),
          _conn('c2', kind: 'source_drift'),
        ],
      ),
    );

    expect(find.text('conn-c1'), findsOneWidget);
    expect(find.text('conn-c2'), findsOneWidget);
    // Kind chips distinguish read-only drift sources from collab rows.
    expect(find.text('collab'), findsOneWidget);
    expect(find.text('drift source (read-only)'), findsOneWidget);
  });

  testWidgets('empty registry shows the empty hint + Add affordance', (
    tester,
  ) async {
    await _pumpDialog(tester, api: _FakeApi());

    expect(find.textContaining('No server connections yet'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('delete warns about referencing tasks before deleting', (
    tester,
  ) async {
    final api = _FakeApi(
      conns: [_conn('c1')],
      taskRefs: [
        {
          'id': 't1',
          'name': 'sync-job',
          'task_type': 'data_sync',
          'source_db_id': 'c1',
          'target_db_id': null,
        },
      ],
    );
    await _pumpDialog(tester, api: api);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    // Confirm dialog names the connection and warns about the task count.
    expect(find.textContaining('Delete server connection'), findsOneWidget);
    expect(
      find.textContaining('1 task(s) reference this connection'),
      findsOneWidget,
    );
    expect(find.textContaining('sync-job'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(api.deleted, ['c1']);
    // List refreshed: the row is gone.
    expect(find.text('conn-c1'), findsNothing);
  });
}
