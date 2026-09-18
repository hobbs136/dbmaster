//! Typed client for the Server-side connection registry (`/api/connections`).
//!
//! U05 (#32): remote deployments historically had NO writer for
//! `database_connections` (the only one was the embedded-mode mirror), so
//! data_sync / health_check / approval task creation dead-ended against an
//! empty registry. This service backs the "Server connections" management
//! dialog: list / create / in-place edit (PUT, U05 server-side) / delete.
//!
//! Mirrors `DataSyncApiService` structure: Bearer token from
//! [ServerConnection], `{ok,data,error}` envelope, typed exceptions for
//! 401/403+ENTITLEMENT_GATED. Unlike `ConnectionSyncService` (embedded
//! mirror, fire-and-forget), errors here MUST surface — the dialog is the
//! user's management surface.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/drift_models.dart';
import '../utils/app_logger.dart';
import 'server_connection.dart';

/// Exception carrying the Server's stable error `code` when present.
class ServerConnectionsApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const ServerConnectionsApiException(
    this.message, {
    this.code,
    this.statusCode,
  });

  @override
  String toString() =>
      'ServerConnectionsApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class ServerConnectionsApiAuthException extends ServerConnectionsApiException {
  const ServerConnectionsApiAuthException()
    : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// HTTP 403 with `ENTITLEMENT_GATED` — Server is gated; mutations refused.
class ServerConnectionsApiEntitlementException
    extends ServerConnectionsApiException {
  const ServerConnectionsApiEntitlementException()
    : super(
        'License gated. Activate or renew the Server license to manage connections.',
        code: 'ENTITLEMENT_GATED',
        statusCode: 403,
      );
}

/// A scheduled task row in its raw JSON shape (only the reference fields the
/// delete-warning needs: id / name / task_type / source_db_id / target_db_id).
typedef ServerTaskRef = Map<String, dynamic>;

/// Server connection registry client. Cheap to construct; stateless.
class ServerConnectionsApiService {
  final ServerConnection _connection;

  @visibleForTesting
  final http.Client? httpClient;

  ServerConnectionsApiService({ServerConnection? connection, this.httpClient})
    : _connection = connection ?? ServerConnection();

  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  // ── Connections ──

  /// `GET /api/connections` — ALL rows (both `collab` and `source_drift`
  /// kinds); the management dialog renders the kind so read-only drift
  /// sources are visually distinguishable.
  Future<List<DriftSourceConnection>> listConnections() async {
    final data = await _send('GET', '/api/connections');
    if (data is! List) {
      throw const ServerConnectionsApiException('expected JSON array');
    }
    return data
        .map((e) => DriftSourceConnection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/connections` (kind=collab — no source_drift canary, this is
  /// the general registry path). Returns the created row.
  ///
  /// SQLite convention (migration 007): [host]='sqlite', [port]=0,
  /// [username]='sqlite', empty password, real path in [filePath].
  Future<DriftSourceConnection> createConnection({
    required String name,
    required String dbType,
    required String host,
    required int port,
    required String username,
    required String password,
    String? defaultDatabase,
    String? filePath,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'db_type': dbType,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'default_database': defaultDatabase,
      'kind': 'collab',
    };
    if (filePath != null) body['file_path'] = filePath;
    final data = await _sendJson('POST', '/api/connections', body);
    return DriftSourceConnection.fromJson(_asMap(data));
  }

  /// `PUT /api/connections/:id` — in-place partial update (U05 server-side).
  ///
  /// Omitted fields keep their stored values; an empty/absent [password]
  /// keeps the stored ciphertext, so the edit form can omit the secret.
  /// In-place (NOT delete+recreate): the id must stay stable because
  /// scheduled_tasks.source_db_id has ON DELETE CASCADE on the server.
  Future<DriftSourceConnection> updateConnection(
    String id, {
    String? name,
    String? dbType,
    String? host,
    int? port,
    String? username,
    String? password,
    String? defaultDatabase,
    String? filePath,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (dbType != null) body['db_type'] = dbType;
    if (host != null) body['host'] = host;
    if (port != null) body['port'] = port;
    if (username != null) body['username'] = username;
    if (password != null && password.isNotEmpty) body['password'] = password;
    if (defaultDatabase != null) body['default_database'] = defaultDatabase;
    if (filePath != null) body['file_path'] = filePath;
    final data = await _sendJson('PUT', '/api/connections/$id', body);
    return DriftSourceConnection.fromJson(_asMap(data));
  }

  /// `DELETE /api/connections/:id`. Server-side FK semantics: tasks using
  /// this connection as SOURCE are CASCADE-deleted, as TARGET are detached
  /// (target_db_id SET NULL). Callers should warn via [listTaskRefs] first.
  Future<void> deleteConnection(String id) async {
    await _send('DELETE', '/api/connections/$id');
  }

  // ── Task references (delete-warning data) ──

  /// `GET /api/tasks` — all tasks, raw shape. Used to warn before deleting a
  /// connection that scheduled tasks still reference (the server would
  /// CASCADE-delete / detach them).
  Future<List<ServerTaskRef>> listTaskRefs() async {
    final data = await _send('GET', '/api/tasks');
    if (data is! List) {
      throw const ServerConnectionsApiException('expected JSON array');
    }
    return data.cast<Map<String, dynamic>>();
  }

  // ── HTTP plumbing (mirrors DataSyncApiService) ──

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final base = _baseUrl;
    if (base == null || !isConnected) {
      throw const ServerConnectionsApiException('not connected to server');
    }
    final token = await _connection.getAccessToken();
    final uri = Uri.parse('$base$path');
    final client = httpClient ?? http.Client();
    try {
      final req = http.Request(method, uri);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      if (token != null) {
        req.headers['Authorization'] = 'Bearer $token';
      }
      final streamed = await client.send(req);
      final resp = await http.Response.fromStream(streamed);
      return _decode(method, path, resp.statusCode, resp.body);
    } on ServerConnectionsApiException {
      rethrow;
    } catch (e) {
      AppLogger.w('ServerConnectionsApi', '$method $path failed: $e');
      throw ServerConnectionsApiException('network error: $e');
    } finally {
      if (httpClient == null) client.close();
    }
  }

  dynamic _decode(String method, String path, int status, String raw) {
    dynamic json;
    try {
      json = jsonDecode(raw);
    } catch (e) {
      AppLogger.w('ServerConnectionsApi', '$method $path non-JSON: $e');
      throw ServerConnectionsApiException(
        'non-JSON response',
        statusCode: status,
      );
    }
    final envelope = json is Map<String, dynamic> ? json : null;
    final ok = envelope?['ok'] == true;
    if (status == 401) {
      ServerConnection().reportAuthFailure();
      throw const ServerConnectionsApiAuthException();
    }
    final errMap = envelope?['error'] is Map
        ? envelope!['error'] as Map<String, dynamic>
        : null;
    if (status == 403 && errMap?['code'] == 'ENTITLEMENT_GATED') {
      throw const ServerConnectionsApiEntitlementException();
    }
    if (!ok || errMap != null) {
      final code = errMap?['code'] as String?;
      final msg = (errMap?['message'] as String?) ?? 'request failed';
      AppLogger.w(
        'ServerConnectionsApi',
        '$method $path $status ${code ?? "?"}: $msg',
      );
      throw ServerConnectionsApiException(msg, code: code, statusCode: status);
    }
    return envelope?['data'];
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    throw const ServerConnectionsApiException('expected JSON object');
  }

  Future<dynamic> _sendJson(
    String method,
    String path,
    Map<String, dynamic> body,
  ) {
    return _send(method, path, body: body);
  }
}
