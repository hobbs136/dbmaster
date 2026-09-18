//! Widget tests for the health-check create dialog's connection dropdown
//! (U05): read-only `source_drift` rows are filtered out, and the empty
//! state routes to the Server-connections management dialog.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/drift_models.dart';
import 'package:dbmaster/organisms/server/health_check/health_check_create_task_dialog.dart';
import 'package:dbmaster/services/health_api_service.dart';
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

class _FakeApi extends HealthApiService {
  _FakeApi({this.conns = const []});

  final List<DriftSourceConnection> conns;

  @override
  Future<List<DriftSourceConnection>> listConnections() async => conns;

  @override
  Future<ServerEntitlement> fetchEntitlement() async {
    throw Exception('offline'); // soft-fail → assume open
  }
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required HealthApiService api,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showHealthCheckCreateTaskDialog(context, api: api),
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

  testWidgets('source dropdown lists collab rows only (U05 kind filter)', (
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

    expect(find.textContaining('conn-c1'), findsOneWidget);
    expect(find.textContaining('conn-c2'), findsNothing);
  });

  testWidgets('empty registry routes to the management dialog', (tester) async {
    await _pumpDialog(tester, api: _FakeApi(conns: const []));

    expect(
      find.textContaining('No database connections on the server yet'),
      findsOneWidget,
    );
    expect(find.text('Server connections'), findsOneWidget);
  });
}
