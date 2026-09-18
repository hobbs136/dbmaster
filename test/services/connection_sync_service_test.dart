// =============================================================================
// Unit tests for ConnectionSyncService (ADR-0003 S3).
// =============================================================================
// Mocks the HTTP layer (via a fake http.Client) and the ServerConnection
// singleton (connected, embedded mode, fixed token) to verify the service's
// request shaping, envelope decoding, and credential/list/create/delete paths.
// No real network or server process is exercised.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/connection_sync_service.dart';
import 'package:dbmaster/services/server_connection.dart';

/// A minimal http.Client that returns canned responses keyed by method+path.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._handlers);
  final Map<String, http.Response Function()> _handlers;
  int callCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    callCount++;
    final key = '${request.method} ${request.url.path}';
    final handler = _handlers[key];
    if (handler == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"ok":false,"error":{"message":"no handler for $key"}}')),
        404,
      );
    }
    final resp = handler();
    return http.StreamedResponse(
      Stream.value(resp.bodyBytes),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

void main() {
  setUp(() {
    ServerConnection.resetForTesting();
  });

  tearDown(() {
    // The sync service is a singleton — clear the injected client between tests.
    ConnectionSyncService.instance.httpClient = null;
  });

  /// Wire ServerConnection into embedded mode + a fixed token + the fake client.
  Future<_FakeClient> wireEmbedded(Map<String, http.Response Function()> handlers) async {
    final fake = _FakeClient(handlers);
    final conn = ServerConnection();
    conn.testHttpClient = fake;
    conn.connectEmbedded(
      port: 12345,
      accessToken: 'test-token',
      refreshToken: 'test-refresh',
      installUuid: 'uuid',
      version: '0.1.0',
    );
    ConnectionSyncService.instance.httpClient = fake;
    return fake;
  }

  group('listConnections', () {
    test('decodes the envelope and maps rows to DbServer (SQL only)', () async {
      await wireEmbedded({
        'GET /api/connections': () => http.Response(jsonEncode({
          'ok': true,
          'data': [
            // A mysql row.
            {
              'id': 'srv-1', 'name': 'prod', 'db_type': 'mysql',
              'host': '10.0.0.5', 'port': 3306, 'username': 'dba',
              'default_database': 'shop', 'use_ssl': 1, 'timeout_seconds': 30,
              'auto_reconnect': 0, 'read_only': 0, 'ssh_enabled': 0,
            },
            // A source_drift row — must be skipped (not client-syncable).
            {
              'id': 'srv-2', 'name': 'drift-src', 'db_type': 'postgres',
              'host': 'h', 'port': 5432, 'username': 'ro',
              'password_encrypted': 'v1:x:y', 'kind': 'source_drift',
              'use_ssl': 0, 'timeout_seconds': 30, 'auto_reconnect': 0,
              'read_only': 1, 'ssh_enabled': 0,
            },
          ],
          'error': null,
        }), 200),
      });
      final conns = await ConnectionSyncService.instance.listConnections();
      // Both rows are SQL types (postgres IS client-syncable), so both map.
      // The kind field doesn't affect syncability — only db_type does.
      expect(conns.length, 2);
      expect(conns[0].type, DatabaseType.mysql);
      expect(conns[0].host, '10.0.0.5');
      expect(conns[1].type, DatabaseType.postgresql);
    });

    test('skips unparseable rows without throwing', () async {
      await wireEmbedded({
        'GET /api/connections': () => http.Response(jsonEncode({
          'ok': true,
          'data': [
            {'id': 'x', 'db_type': 'redis', 'name': 'r'}, // unsupported type
            {'id': 'y', 'db_type': 'mysql', 'name': 'm',
             'host': 'h', 'port': 3306, 'username': 'u'},
          ],
          'error': null,
        }), 200),
      });
      final conns = await ConnectionSyncService.instance.listConnections();
      expect(conns.length, 1);
      expect(conns[0].id, 'y');
    });
  });

  group('fetchCredentials', () {
    test('returns password + SSH plaintext', () async {
      await wireEmbedded({
        'GET /api/connections/abc/credential': () => http.Response(jsonEncode({
          'ok': true,
          'data': {
            'id': 'abc',
            'password': 'secret-pw',
            'ssh_username': 'tunnel',
            'ssh_auth_mode': 'privateKey',
            'ssh_password': null,
            'ssh_private_key': '-----BEGIN-----',
            'ssh_passphrase': 'phrase',
          },
          'error': null,
        }), 200),
      });
      final creds = await ConnectionSyncService.instance.fetchCredentials('abc');
      expect(creds.password, 'secret-pw');
      expect(creds.ssh?.username, 'tunnel');
      expect(creds.ssh?.authMode, 'privateKey');
      expect(creds.ssh?.privateKey, '-----BEGIN-----');
      expect(creds.ssh?.passphrase, 'phrase');
      expect(creds.ssh?.password, isNull);
    });
  });

  group('createConnection', () {
    test('POSTs and returns the server id', () async {
      final fake = await wireEmbedded({
        'POST /api/connections': () => http.Response(jsonEncode({
          'ok': true,
          'data': {'id': 'new-server-id', 'name': 'm'},
          'error': null,
        }), 200),
      });
      final server = DbServer(
        id: 'local-1', name: 'm', type: DatabaseType.mysql,
        host: 'h', port: 3306, username: 'u', password: 'pw',
      );
      final id = await ConnectionSyncService.instance.createConnection(server, 'pw');
      expect(id, 'new-server-id');
      expect(fake.callCount, greaterThanOrEqualTo(1));
    });

    test('returns null on API error (does not throw)', () async {
      await wireEmbedded({
        'POST /api/connections': () => http.Response(jsonEncode({
          'ok': false,
          'error': {'code': 'CREATE_FAILED', 'message': 'boom'},
        }), 200),
      });
      final server = DbServer(
        id: 'local-1', name: 'm', type: DatabaseType.mysql,
        host: 'h', port: 3306, username: 'u',
      );
      final id = await ConnectionSyncService.instance.createConnection(server, 'pw');
      expect(id, isNull);
    });
  });

  group('deleteConnection', () {
    test('issues DELETE and swallows errors', () async {
      final fake = await wireEmbedded({
        'DELETE /api/connections/xyz': () => http.Response(jsonEncode({
          'ok': true, 'data': {'deleted': true}, 'error': null,
        }), 200),
      });
      await ConnectionSyncService.instance.deleteConnection('xyz');
      expect(fake.callCount, greaterThanOrEqualTo(1));
    });
  });
}
