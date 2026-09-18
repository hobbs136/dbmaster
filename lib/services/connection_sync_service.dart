//! Connection synchronization between the client and the embedded server
//! (ADR-0003 S3).
//!
//! In embedded mode, SQL-library connections (mysql/postgres/sqlite) are
//! stored on the server (POST /api/connections) instead of the local keychain,
//! so the same connections are visible to server-side features (data_sync,
//! drift). This service owns that HTTP plumbing; the storage-routing decision
//! (server vs keychain) lives in [connection_mapping.isServerSyncable] and is
//! enforced by [ConnectionProvider].
//!
//! Credentials: the server stores only ciphertext. Plaintext is fetched on
//! demand via the embedded-only `GET /api/connections/:id/credential` endpoint
//! — see [fetchCredentials].

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/database_models.dart';
import '../utils/app_logger.dart';
import 'connection_mapping.dart';
import 'server_connection.dart';

/// Plaintext DB password + SSH credentials for one connection.
///
/// The shape returned by `GET /api/connections/:id/credential` (data field).
class ConnectionCredentials {
  final String password;
  final SshCredentials? ssh;

  const ConnectionCredentials({required this.password, this.ssh});
}

/// Result of an [ConnectionSyncService.upsert] call.
enum UpsertResult { created, failed }

/// Singleton that talks to `/api/connections` on the embedded server.
///
/// Mirrors the structural pattern of [DriftApiService] (reads the
/// [ServerConnection] singleton for base URL + token). Not a Provider — no UI
/// state; the [ConnectionProvider] owns the in-memory connection list.
class ConnectionSyncService {
  ConnectionSyncService._();
  static final ConnectionSyncService instance = ConnectionSyncService._();

  /// Test-only HTTP client injection (mirrors the codebase's test seams).
  @visibleForTesting
  http.Client? httpClient;

  /// Send an authenticated request to the embedded server.
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final conn = ServerConnection();
    final baseUrl = conn.serverUrl;
    if (baseUrl == null ||
        conn.connectionState != ServerConnectionState.connected) {
      throw StateError('Not connected to a server (embedded sync unavailable).');
    }
    final token = await conn.getAccessToken();
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse('$baseUrl$path');
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      switch (method) {
        case 'GET':
          return await client.get(uri, headers: headers);
        case 'POST':
          return await client.post(uri,
              headers: headers, body: body == null ? '' : jsonEncode(body));
        case 'DELETE':
          return await client.delete(uri, headers: headers);
        default:
          throw StateError('Unsupported HTTP method: $method');
      }
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Decode the `{ok, data, error}` envelope, throwing on transport/API errors.
  dynamic _unwrap(http.Response resp, String what) {
    if (resp.statusCode == 401) {
      throw StateError('Server auth failed during $what (token expired?).');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['ok'] != true) {
      final err = body['error'];
      final msg = err is Map ? err['message'] : 'unknown error';
      throw StateError('$what failed: $msg');
    }
    return body['data'];
  }

  /// List the server-stored connections that map to client SQL libraries.
  ///
  /// Returns each row WITHOUT plaintext credentials (the row only carries
  /// ciphertext). Call [fetchCredentials] per connection before opening it.
  // server→client list. Filters out unsupported db_types
  /// (drift source_drift rows, future server-only types) defensively.
  Future<List<DbServer>> listConnections() async {
    final resp = await _send('GET', '/api/connections');
    final data = _unwrap(resp, 'list connections');
    final rows = (data as List).cast<Map<String, dynamic>>();
    final result = <DbServer>[];
    for (final row in rows) {
      final type = clientDbTypeFromServer(row['db_type'] as String?);
      if (type == null) continue; // skip unsupported (source_drift, etc.)
      try {
        result.add(fromServerRow(row));
      } catch (e) {
        AppLogger.w('ConnectionSyncService', 'skipping unparseable row: $e');
      }
    }
    return result;
  }

  /// Fetch the plaintext credentials for a connection (embedded-only endpoint).
  ///
  /// The server returns `NOT_EMBEDDED` if invoked against a remote deployment;
  /// this service is only used in embedded mode, so that path surfaces as an
  /// error the caller can handle (e.g. prompt the user to re-enter the password).
  Future<ConnectionCredentials> fetchCredentials(String connId) async {
    final resp = await _send('GET', '/api/connections/$connId/credential');
    final data = _unwrap(resp, 'fetch credentials') as Map<String, dynamic>;
    return ConnectionCredentials(
      password: (data['password'] as String?) ?? '',
      ssh: SshCredentials(
        username: data['ssh_username'] as String?,
        authMode: data['ssh_auth_mode'] as String?,
        password: data['ssh_password'] as String?,
        privateKey: data['ssh_private_key'] as String?,
        passphrase: data['ssh_passphrase'] as String?,
      ),
    );
  }

  /// Create a connection on the server. Returns the assigned server id on
  /// success, or null on failure (caller keeps the connection in keychain).
  ///
  /// [plaintextPassword] is the DB password (server encrypts it). SSH secrets
  /// are read from the [server].
  // client→server create. The server returns the created
  /// row; we surface just the id so ConnectionProvider can reconcile.
  Future<String?> createConnection(DbServer server, String plaintextPassword) async {
    final body = toCreateBody(server, plaintextPassword);
    try {
      final resp = await _send('POST', '/api/connections', body: body);
      final data = _unwrap(resp, 'create connection') as Map<String, dynamic>;
      return data['id'] as String?;
    } catch (e) {
      AppLogger.w('ConnectionSyncService',
          'createConnection failed (connection stays local): $e');
      return null;
    }
  }

  /// Delete a connection from the server. Idempotent: a missing row is a
  /// success (DELETE returns {deleted:true} regardless).
  Future<void> deleteConnection(String connId) async {
    try {
      final resp = await _send('DELETE', '/api/connections/$connId');
      // unwrap throws on error; {ok:true} is the success path.
      _unwrap(resp, 'delete connection');
    } catch (e) {
      AppLogger.w('ConnectionSyncService', 'deleteConnection failed: $e');
    }
  }

  /// Upsert by delete-then-create (the server has no PATCH in S3).
  ///
  /// Returns the new server id on success. The caller is responsible for
  /// updating the in-memory [DbServer.id] to the new value, since the old id
  /// pointed at the deleted row.
  Future<String?> replaceConnection(
      DbServer server, String plaintextPassword) async {
    // Best-effort delete the old row (id may not yet exist on the server).
    await deleteConnection(server.id);
    return createConnection(server, plaintextPassword);
  }
}
