//! Typed client for the Server-side drift REST API (Phase F desktop UI).
//!
//! All endpoints under `/api/tasks`, `/api/connections`, `/api/run-history`,
//! `/api/snapshots`, `/api/entitlement`. Bearer token comes from
//! [ServerConnection] — the desktop never stores or transmits Server-DB
//! credentials.
//!
//! Error model:
//! - Network / non-JSON response → [DriftApiException] (generic).
//! - `{ok:false, error:{code,message}}` envelope → [DriftApiException] with the
//!   Server's `code` (e.g. `ENTITLEMENT_GATED`, `CANARY_REJECTED`).
//! - HTTP 401 → [DriftApiAuthException] (caller should prompt reconnect).
//! - HTTP 403 + `ENTITLEMENT_GATED` → [DriftApiEntitlementException] (caller
//!   shows activation prompt and disables mutations).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/drift_models.dart';
import '../utils/app_logger.dart';
import 'server_connection.dart';

/// Exception shape carrying the Server's stable error `code` when present.
class DriftApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const DriftApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'DriftApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class DriftApiAuthException extends DriftApiException {
  const DriftApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// HTTP 403 with `ENTITLEMENT_GATED` — Server is gated; mutations refused.
class DriftApiEntitlementException extends DriftApiException {
  const DriftApiEntitlementException()
      : super(
          'License gated. Activate or renew the Server license to perform this action.',
          code: 'ENTITLEMENT_GATED',
          statusCode: 403,
        );
}

/// Typed drift REST client. One instance is cheap; the desktop can construct
/// per-feature or hold a long-lived singleton. All requests go through
/// [ServerConnection.getAccessToken], so a session that just expired surfaces
/// [DriftApiAuthException].
class DriftApiService {
  final ServerConnection _connection;

  /// Test-only HTTP client injection. When null, uses the Server-connection-
  /// owned client (same one the auth flow uses) — avoids a second socket pool.
  @visibleForTesting
  final http.Client? httpClient;

  DriftApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  /// True when the desktop has no server session (caller can short-circuit
  /// rather than round-tripping every request).
  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  // ── Entitlement ──

  /// `GET /api/entitlement` — license/trial/gated state. Drives the create-task
  /// gate. Unauthenticated endpoint on the Server side, but we still attach the
  /// token when connected (harmless; lets a future authenticated entitlement
  /// work without a client change).
  Future<ServerEntitlement> fetchEntitlement() async {
    final data = await _get('/api/entitlement');
    return ServerEntitlement.fromJson(data as Map<String, dynamic>);
  }

  // ── Tasks ──

  /// `GET /api/tasks` filtered client-side to `task_type == "schema_drift"`.
  /// The Server has no query filter yet (single-tenant v1); filtering on the
  /// client keeps the wire contract minimal.
  Future<List<DriftTask>> listDriftTasks() async {
    final data = await _get('/api/tasks');
    final list = data as List<dynamic>;
    final out = <DriftTask>[];
    for (final e in list) {
      final raw = e as Map<String, dynamic>;
      // Only schema_drift rows belong to this UI; the Server returns all
      // task types so the filter has to happen here.
      if ((raw['task_type'] as String?) == 'schema_drift') {
        out.add(DriftTask.fromJson(raw));
      }
    }
    return out;
  }

  /// `POST /api/tasks` — create a schema_drift task.
  ///
  /// [config] is sent as a JSON object (Server stores as TEXT); [webhookUrls]
  /// goes into the `notify_channels` array column (Server reads the first URL
  /// only in v1 — `drift::runner::first_webhook_url`).
  Future<DriftTask> createDriftTask({
    required String name,
    required String sourceDbId,
    required DriftTaskConfig config,
    List<String> webhookUrls = const [],
  }) async {
    final request = <String, dynamic>{
      'name': name,
      'task_type': 'schema_drift',
      // cron_expr is required by the Server schema but unused for drift
      // (the drift scheduler is interval-driven, not cron-driven; see
      // scheduler.rs SCAN_SQL). Send an empty string — matches the existing
      // contract used by other clients.
      'cron_expr': '',
      'config': config.toJson(),
      'source_db_id': sourceDbId,
      'notify_channels': webhookUrls,
    };
    final body = await _postJson('/api/tasks', request);
    return DriftTask.fromJson(body);
  }

  /// `POST /api/tasks/:id/run` — queue a manual run. Returns immediately (202).
  /// Caller polls [listDriftTasks] for `last_status` or
  /// [listRunHistory] for the per-run trail.
  Future<void> runTaskNow(String taskId) async {
    await _postEmpty('/api/tasks/$taskId/run');
  }

  /// `DELETE /api/tasks/:id`.
  Future<void> deleteTask(String taskId) async {
    await _delete('/api/tasks/$taskId');
  }

  /// `PATCH /api/tasks/:id` — partial update (#5 server-side partial PATCH).
  /// Only non-null fields are sent; null means "leave unchanged" (server
  /// `Option<T>` + `#[serde(default)]`). Returns the full updated task object
  /// so callers can refresh their cache without a separate GET.
  ///
  /// Note: `config` and `target_db_id` are intentionally not exposed here —
  /// use [patchTaskConfig] for whole-config replacement (drift interval edit)
  /// and task recreate for target re-bind.
  Future<Map<String, dynamic>> patchTask(
    String taskId, {
    bool? enabled,
    String? name,
    String? cronExpr,
    List<String>? notifyChannels,
  }) async {
    final body = <String, dynamic>{};
    if (enabled != null) body['enabled'] = enabled;
    if (name != null) body['name'] = name;
    if (cronExpr != null) body['cron_expr'] = cronExpr;
    if (notifyChannels != null) body['notify_channels'] = notifyChannels;
    return _patchJson('/api/tasks/$taskId', body);
  }

  /// `PATCH /api/tasks/:id` with a replacement `config` object (U09 interval
  /// edit). The Server replaces `config` **wholesale** — no merge — so callers
  /// must send the complete desired config, typically the parsed current
  /// `DriftTask.config` with `intervalMinutes` overridden so sibling keys
  /// (`pg_schemas`) survive. Returns the full updated task object.
  Future<Map<String, dynamic>> patchTaskConfig(
    String taskId,
    Map<String, dynamic> config,
  ) async {
    return _patchJson('/api/tasks/$taskId', {'config': config});
  }

  /// Enable or disable a task's schedule (pause/resume cron). Thin wrapper
  /// over [patchTask]. Mutation.
  Future<void> setEnabled(String taskId, bool enabled) async {
    await patchTask(taskId, enabled: enabled);
  }

  // ── Connections ──

  /// `GET /api/connections`. Returns ALL rows; caller filters by `kind`.
  Future<List<DriftSourceConnection>> listConnections() async {
    final data = await _get('/api/connections');
    final list = data as List<dynamic>;
    return list
        .map((e) => DriftSourceConnection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Convenience: only `kind == "source_drift"` rows.
  Future<List<DriftSourceConnection>> listSourceDriftConnections() async {
    final all = await listConnections();
    return all.where((c) => c.isSourceDrift).toList(growable: false);
  }

  /// `POST /api/connections` with `kind = "source_drift"`. The Server runs a
  /// create-time canary and refuses writable accounts with `CANARY_REJECTED`.
  Future<DriftSourceConnection> createSourceDriftConnection({
    required String name,
    required String dbType,
    required String host,
    required int port,
    required String username,
    required String password,
    String? defaultDatabase,
  }) async {
    final request = <String, dynamic>{
      'name': name,
      'db_type': dbType,
      'host': host,
      'port': port,
      'username': username,
      'password': password,
      'default_database': defaultDatabase,
      'kind': 'source_drift',
    };
    final body = await _postJson('/api/connections', request);
    return DriftSourceConnection.fromJson(body);
  }

  // ── Run history + snapshots (read-only) ──

  /// `GET /api/run-history?task_id=...&limit=...`. Server requires `task_id`.
  Future<List<DriftRunHistoryEntry>> listRunHistory(
    String taskId, {
    int limit = 50,
  }) async {
    final data = await _get(
      '/api/run-history?task_id=${Uri.encodeQueryComponent(taskId)}'
      '&limit=$limit',
    );
    final list = data as List<dynamic>;
    return list
        .map((e) => DriftRunHistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/snapshots?connection_id=...&limit=...`. Metadata-only.
  Future<List<DriftSnapshotMeta>> listSnapshots(
    String connectionId, {
    int limit = 50,
  }) async {
    final data = await _get(
      '/api/snapshots?connection_id=${Uri.encodeQueryComponent(connectionId)}'
      '&limit=$limit',
    );
    final list = data as List<dynamic>;
    return list
        .map((e) => DriftSnapshotMeta.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /api/snapshots/:id`. Full row including `schema_json`.
  Future<DriftSnapshot> getSnapshot(String snapshotId) async {
    final data = await _get('/api/snapshots/${Uri.encodeComponent(snapshotId)}');
    return DriftSnapshot.fromJson(data as Map<String, dynamic>);
  }

  // ── Low-level HTTP plumbing ──

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final resp = await _send('POST', path, body: jsonEncode(payload));
    return _decodeEnvelopeMap(resp, 'POST', path);
  }

  /// PATCH a JSON body and decode the `{ok, data, error}` envelope into a Map.
  /// Mirrors `_postJson` for the PATCH method (server returns the full updated
  /// task object — callers can refresh their cache from the response).
  Future<Map<String, dynamic>> _patchJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final resp = await _send('PATCH', path, body: jsonEncode(payload));
    return _decodeEnvelopeMap(resp, 'PATCH', path);
  }

  Future<void> _postEmpty(String path) async {
    final resp = await _send('POST', path, body: '');
    // 202 has no body to parse; just confirm it wasn't an error envelope.
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const DriftApiAuthException();
    }
    if (resp.statusCode >= 400) {
      // Try to surface a structured envelope if the Server sent one.
      try {
        _decodeEnvelope(resp, 'POST', path);
      } on DriftApiException {
        rethrow;
      } catch (e) {
        throw DriftApiException(
          'POST $path failed (${resp.statusCode})',
          statusCode: resp.statusCode,
        );
      }
    }
  }

  Future<dynamic> _get(String path) async {
    final resp = await _send('GET', path);
    return _decodeEnvelope(resp, 'GET', path);
  }

  Future<void> _delete(String path) async {
    final resp = await _send('DELETE', path);
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const DriftApiAuthException();
    }
    if (resp.statusCode >= 400) {
      try {
        _decodeEnvelope(resp, 'DELETE', path);
      } on DriftApiException {
        rethrow;
      } catch (_) {
        throw DriftApiException(
          'DELETE $path failed (${resp.statusCode})',
          statusCode: resp.statusCode,
        );
      }
    }
  }

  /// Wrap the request with auth headers + dispatch through the injected or
  /// Server-owned HTTP client.
  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
  }) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || !isConnected) {
      throw const DriftApiException(
        'Not connected to a DbMaster server.',
      );
    }
    final token = await _connection.getAccessToken();
    final headers = <String, String>{
      if (body != null && body.isNotEmpty) 'Content-Type': 'application/json',
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
          return await client.post(uri, headers: headers, body: body ?? '');
        case 'DELETE':
          return await client.delete(uri, headers: headers);
        case 'PATCH':
          return await client.patch(uri, headers: headers, body: body ?? '');
        default:
          throw DriftApiException('Unsupported HTTP method: $method');
      }
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Decode the `{ok, data, error}` envelope and return the `data` field
  /// (Map or List — caller casts). Throws typed exceptions for 401 /
  /// 403-entitlement / any `{ok:false}` envelope.
  dynamic _decodeEnvelope(http.Response resp, String method, String path) {
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const DriftApiAuthException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw DriftApiException(
        '$method $path: non-JSON response (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw DriftApiException(
        '$method $path: unexpected response shape',
        statusCode: resp.statusCode,
      );
    }
    final ok = decoded['ok'] as bool? ?? false;
    final error = decoded['error'];
    if (!ok) {
      final code = error is Map<String, dynamic>
          ? error['code'] as String?
          : null;
      final message = error is Map<String, dynamic>
          ? (error['message'] as String?) ?? 'Unknown error'
          : 'Unknown error';
      if (resp.statusCode == 403 && code == 'ENTITLEMENT_GATED') {
        throw const DriftApiEntitlementException();
      }
      throw DriftApiException(
        '$method $path: $message',
        code: code,
        statusCode: resp.statusCode,
      );
    }
    return decoded['data'];
  }

  /// Variant for endpoints that always return a single JSON object (POST
  /// create-* handlers). Throws a clear error if the Server returns null /
  /// unexpected shape.
  Map<String, dynamic> _decodeEnvelopeMap(
    http.Response resp,
    String method,
    String path,
  ) {
    final data = _decodeEnvelope(resp, method, path);
    if (data is Map<String, dynamic>) return data;
    throw DriftApiException(
      '$method $path: expected JSON object, got ${data?.runtimeType ?? "null"}',
      statusCode: resp.statusCode,
    );
  }
}

/// Logging-only extension to keep [DriftApiException] out of the hot path;
/// callers can log a coarse redacted line without leaking credentials.
extension DriftApiServiceLog on DriftApiService {
  void logError(String op, Object error) {
    if (error is DriftApiException) {
      AppLogger.w(
        'DriftApi',
        '$op failed (${error.statusCode} ${error.code ?? "?"})',
      );
    } else {
      AppLogger.w('DriftApi', '$op failed: $error');
    }
  }
}
