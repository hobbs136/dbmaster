//! Unit tests for [ConnectionProvider.resolveServerConnectionId] (U05):
//! the local-id → server-id translation data-sync submits depend on.
//!
//! Covers the three resolution outcomes: persisted-mapping hit (no network),
//! natural-key match against the live server list (remote-mode self-heal),
//! and no counterpart (null → caller refuses to submit).

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:dbmaster/services/connection_sync_service.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/server_connection.dart';

class _MockDatabaseService extends DatabaseService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Canned-response client for ConnectionSyncService (keyed by method+path).
class _FakeClient extends http.BaseClient {
  _FakeClient(this._handlers);
  final Map<String, http.Response Function()> _handlers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final handler = _handlers['${request.method} ${request.url.path}'];
    if (handler == null) {
      return http.StreamedResponse(
        Stream.value(
          utf8.encode('{"ok":false,"error":{"message":"no handler"}}'),
        ),
        404,
      );
    }
    final resp = handler();
    return http.StreamedResponse(Stream.value(resp.bodyBytes), resp.statusCode);
  }
}

DbServer _savedConn(
  String id, {
  String name = 'prod',
  String host = '10.0.0.5',
}) => DbServer(
  id: id,
  name: name,
  type: DatabaseType.mysql,
  host: host,
  port: 3306,
  username: 'dba',
  password: null,
);

Future<void> _seedSavedConnections(List<DbServer> conns) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'saved_connections',
    jsonEncode(conns.map((c) => c.toJson()).toList()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async => null,
        );
    ServerConnection.resetForTesting();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        );
    ConnectionSyncService.instance.httpClient = null;
    ServerConnection.resetForTesting();
  });

  test('persisted mapping resolves without any network round-trip', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'connection_server_id_map',
      jsonEncode({'local-1': 'srv-1'}),
    );
    await _seedSavedConnections([_savedConn('local-1')]);
    final provider = ConnectionProvider(dbService: _MockDatabaseService());
    await provider.loadSavedConnections();

    // No fake client wired — a network attempt would fail the resolution.
    final resolved = await provider.resolveServerConnectionId('local-1');

    expect(resolved, 'srv-1');
  });

  test(
    'no mapping: natural-key match resolves and persists the mapping',
    () async {
      await _seedSavedConnections([_savedConn('local-2')]);
      // Remote-mode-style connected session + server list with a same
      // name/type/host row carrying a different id.
      final conn = ServerConnection();
      conn.testHttpClient = _FakeClient({});
      conn.connectEmbedded(
        port: 12345,
        accessToken: 'test-token',
        refreshToken: 'test-refresh',
        installUuid: 'uuid',
        version: '0.1.0',
      );
      ConnectionSyncService.instance.httpClient = _FakeClient({
        'GET /api/connections': () => http.Response(
          jsonEncode({
            'ok': true,
            'data': [
              {
                'id': 'srv-9',
                'name': 'prod',
                'db_type': 'mysql',
                'host': '10.0.0.5',
                'port': 3306,
                'username': 'dba',
                'default_database': null,
                'use_ssl': 0,
                'timeout_seconds': 30,
                'auto_reconnect': 0,
                'read_only': 0,
                'ssh_enabled': 0,
              },
            ],
            'error': null,
          }),
          200,
        ),
      });
      final provider = ConnectionProvider(dbService: _MockDatabaseService());
      await provider.loadSavedConnections();

      final resolved = await provider.resolveServerConnectionId('local-2');

      expect(resolved, 'srv-9');
      // Self-heal: the match is persisted so the next call skips the GET.
      final prefs = await SharedPreferences.getInstance();
      final map =
          (jsonDecode(prefs.getString('connection_server_id_map') ?? '{}')
              as Map);
      expect(map['local-2'], 'srv-9');
    },
  );

  test('natural-key mismatch on name does not resolve', () async {
    await _seedSavedConnections([_savedConn('local-3', name: 'other-name')]);
    final conn = ServerConnection();
    conn.testHttpClient = _FakeClient({});
    conn.connectEmbedded(
      port: 12345,
      accessToken: 'test-token',
      refreshToken: 'test-refresh',
      installUuid: 'uuid',
      version: '0.1.0',
    );
    ConnectionSyncService.instance.httpClient = _FakeClient({
      'GET /api/connections': () => http.Response(
        jsonEncode({
          'ok': true,
          'data': [
            {
              'id': 'srv-x',
              'name': 'prod', // different name than the local row
              'db_type': 'mysql',
              'host': '10.0.0.5',
              'port': 3306,
              'username': 'dba',
              'default_database': null,
              'use_ssl': 0,
              'timeout_seconds': 30,
              'auto_reconnect': 0,
              'read_only': 0,
              'ssh_enabled': 0,
            },
          ],
          'error': null,
        }),
        200,
      ),
    });
    final provider = ConnectionProvider(dbService: _MockDatabaseService());
    await provider.loadSavedConnections();

    expect(await provider.resolveServerConnectionId('local-3'), isNull);
  });

  test('unknown local id resolves to null', () async {
    final provider = ConnectionProvider(dbService: _MockDatabaseService());
    await provider.loadSavedConnections();

    expect(await provider.resolveServerConnectionId('nope'), isNull);
  });
}
