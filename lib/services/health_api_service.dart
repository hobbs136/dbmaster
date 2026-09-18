//! Typed client for the Server-side health check REST API (ADR-0004 §5 M5 T29).
//!
//! Endpoints:
//! - `GET /api/tasks` (filtered client-side to `task_type == "health_check"`)
//!   → [HealthTask] rows. The Server has no query filter; health/drift/data_sync
//!   share `/api/tasks`, so the client filters by `task_type`.
//! - `GET /api/health-results?task_id=&limit=` → [HealthCheckResultDto] rows.
//!   No gate (read-only; visible-but-locked under Gated) — only the token is
//!   required.
//! - `POST /api/tasks/:id/run` → manual trigger (gate_blocked; 403 under Gated).
//!
//! Bearer token comes from [ServerConnection]; the desktop never stores or
//! transmits Server-DB credentials. Error model mirrors `DriftApiService`:
//! - Network / non-JSON → [HealthApiException] (generic, carries Server `code`).
//! - HTTP 401 → [HealthApiAuthException] (caller prompts reconnect).
//! - HTTP 403 + `ENTITLEMENT_GATED` → [HealthApiEntitlementException].

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/drift_models.dart';
import '../models/health_summary.dart';
import '../utils/app_logger.dart';
import 'server_connection.dart';

/// Exception shape carrying the Server's stable error `code` when present.
class HealthApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const HealthApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'HealthApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class HealthApiAuthException extends HealthApiException {
  const HealthApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// HTTP 403 with `ENTITLEMENT_GATED` — Server is gated; mutations refused.
class HealthApiEntitlementException extends HealthApiException {
  const HealthApiEntitlementException()
      : super(
          'License gated. Activate or renew the Server license to perform this action.',
          code: 'ENTITLEMENT_GATED',
          statusCode: 403,
        );
}

/// Typed health check REST client. One instance is cheap; the
/// [HealthCheckProvider] holds a long-lived singleton. All requests route
/// through [ServerConnection.getAccessToken], so a just-expired session
/// surfaces [HealthApiAuthException].
class HealthApiService {
  final ServerConnection _connection;

  /// Test-only HTTP client injection. When null, uses a per-call client (the
  /// Server-connection-owned pool is not exposed here).
  @visibleForTesting
  final http.Client? httpClient;

  HealthApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  /// True when the desktop has a server session (caller can short-circuit
  /// rather than round-tripping every request).
  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  // ── Tasks ──

  /// `GET /api/tasks` filtered client-side to `task_type == "health_check"`.
  /// Mirrors `DriftApiService.listDriftTasks`: the Server returns all task
  /// types, so the filter happens here.
  Future<List<HealthTask>> listHealthTasks() async {
    final data = await _get('/api/tasks');
    final list = data as List<dynamic>;
    final out = <HealthTask>[];
    for (final e in list) {
      final raw = e as Map<String, dynamic>;
      if ((raw['task_type'] as String?) == 'health_check') {
        out.add(HealthTask.fromJson(raw));
      }
    }
    return out;
  }

  /// `GET /api/health-results?task_id=...&limit=...`. Server requires `task_id`
  /// (returns `[]` — not 404 — when the task has no rows). `limit` defaults to
  /// 5: the indicator only needs the recent window for status inference.
  Future<List<HealthCheckResultDto>> listHealthResults(
    String taskId, {
    int limit = 5,
  }) async {
    final data = await _get(
      '/api/health-results?task_id=${Uri.encodeQueryComponent(taskId)}'
      '&limit=$limit',
    );
    final list = data as List<dynamic>;
    return list
        .map((e) => HealthCheckResultDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /api/tasks/:id/run` — queue a manual run. Returns immediately (202).
  /// Caller polls [listHealthResults] for the newest row. Gate_blocked (403)
  /// surfaces as [HealthApiEntitlementException].
  Future<void> runTaskNow(String taskId) async {
    await _postEmpty('/api/tasks/$taskId/run');
  }

  // ── Entitlement ──

  /// `GET /api/entitlement` — license/trial/gated state. Drives the create-task
  /// gate (same Server-wide state as drift/data_sync). Mirrors
  /// `DriftApiService.fetchEntitlement`.
  Future<ServerEntitlement> fetchEntitlement() async {
    final data = await _get('/api/entitlement');
    return ServerEntitlement.fromJson(data as Map<String, dynamic>);
  }

  // ── Connections ──

  /// `GET /api/connections`. Returns ALL rows (health_check accepts any
  /// `database_connections` row — unlike drift's source_drift kind filter).
  /// Reuses `DriftSourceConnection` (generic id/name/dbType/host/port shape).
  Future<List<DriftSourceConnection>> listConnections() async {
    final data = await _get('/api/connections');
    final list = data as List<dynamic>;
    return list
        .map((e) => DriftSourceConnection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ── Task creation ──

  /// `POST /api/tasks` — create a health_check task.
  ///
  /// [config] is the `HealthCheckTaskConfig` JSON (all fields serde-defaulted
  /// on the Server, so an empty `{}` is valid). [cronExpr] is required (health
  /// is cron-driven, unlike drift's interval config). [notifyChannels] is the
  /// webhook URL list (Server reads the first URL). `target_db_id` is always
  /// null — health_check inspects a single source connection.
  Future<HealthTask> createTask({
    required String name,
    required String sourceDbId,
    required String cronExpr,
    Map<String, dynamic> config = const {},
    List<String> notifyChannels = const [],
  }) async {
    final request = <String, dynamic>{
      'name': name,
      'task_type': 'health_check',
      'cron_expr': cronExpr,
      'config': config,
      'source_db_id': sourceDbId,
      // health_check has no target; the column is nullable.
      'target_db_id': null,
      'notify_channels': notifyChannels,
    };
    final body = await _postJson('/api/tasks', request);
    return HealthTask.fromJson(body);
  }

  /// `PATCH /api/tasks/:id` — partial update (#5 server-side partial PATCH).
  /// Only non-null fields are sent; null means "leave unchanged" (server
  /// `Option<T>` + `#[serde(default)]`). Returns the full updated task object
  /// so callers can refresh their cache without a separate GET.
  ///
  /// Note: `config` and `target_db_id` are intentionally not exposed — editing
  /// them mid-flight is risky (re-validation, connection re-bind) and out of
  /// scope for the toggle/edit UI. Use task recreate for those.
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

  /// Enable or disable a task's schedule (pause/resume cron). Thin wrapper
  /// over [patchTask]. Mutation.
  Future<void> setEnabled(String taskId, bool enabled) async {
    await patchTask(taskId, enabled: enabled);
  }

  /// `DELETE /api/tasks/:id` — delete a health_check task (#28). The Server
  /// returns `200 {ok:true,data:{deleted:true}}` (not 204), so the standard
  /// envelope decode applies. Mirrors `DataSyncApiService.deleteTask` /
  /// `DriftApiService.deleteTask`.
  Future<void> deleteTask(String taskId) async {
    await _delete('/api/tasks/$taskId');
  }

  // ── Low-level HTTP plumbing (mirrors DriftApiService) ──

  Future<dynamic> _get(String path) async {
    final resp = await _send('GET', path);
    return _decodeEnvelope(resp, 'GET', path);
  }

  Future<void> _postEmpty(String path) async {
    final resp = await _send('POST', path, body: '');
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const HealthApiAuthException();
    }
    if (resp.statusCode >= 400) {
      try {
        _decodeEnvelope(resp, 'POST', path);
      } on HealthApiException {
        rethrow;
      } catch (e) {
        throw HealthApiException(
          'POST $path failed (${resp.statusCode})',
          statusCode: resp.statusCode,
        );
      }
    }
  }

  /// DELETE with no body — decodes the `{ok,data,error}` envelope so a
  /// `{ok:false}` surfaces as [HealthApiException] (mirrors `_postEmpty`).
  Future<void> _delete(String path) async {
    final resp = await _send('DELETE', path);
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const HealthApiAuthException();
    }
    if (resp.statusCode >= 400) {
      try {
        _decodeEnvelope(resp, 'DELETE', path);
      } on HealthApiException {
        rethrow;
      } catch (e) {
        throw HealthApiException(
          'DELETE $path failed (${resp.statusCode})',
          statusCode: resp.statusCode,
        );
      }
    }
  }

  /// Wrap the request with auth headers + dispatch through the injected or a
  /// per-call HTTP client.
  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
  }) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || !isConnected) {
      throw const HealthApiException('Not connected to a DbMaster server.');
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
        case 'PATCH':
          return await client.patch(uri, headers: headers, body: body ?? '');
        case 'DELETE':
          return await client.delete(uri, headers: headers);
        default:
          throw HealthApiException('Unsupported HTTP method: $method');
      }
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Decode the `{ok, data, error}` envelope and return the `data` field.
  /// Throws typed exceptions for 401 / 403-entitlement / any `{ok:false}`.
  dynamic _decodeEnvelope(http.Response resp, String method, String path) {
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const HealthApiAuthException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw HealthApiException(
        '$method $path: non-JSON response (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw HealthApiException(
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
        throw const HealthApiEntitlementException();
      }
      throw HealthApiException(
        '$method $path: $message',
        code: code,
        statusCode: resp.statusCode,
      );
    }
    return decoded['data'];
  }

  /// Variant for endpoints that always return a single JSON object (POST
  /// create-* handlers). Throws a clear error if the Server returns null /
  /// unexpected shape. Mirrors `DriftApiService._decodeEnvelopeMap`.
  Map<String, dynamic> _decodeEnvelopeMap(
    http.Response resp,
    String method,
    String path,
  ) {
    final data = _decodeEnvelope(resp, method, path);
    if (data is Map<String, dynamic>) return data;
    throw HealthApiException(
      '$method $path: expected JSON object, got ${data?.runtimeType ?? "null"}',
      statusCode: resp.statusCode,
    );
  }

  /// POST a JSON body and decode the `{ok, data, error}` envelope into a Map.
  /// Mirrors `DriftApiService._postJson`.
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

  /// Logging helper — logs a coarse redacted line without leaking credentials.
  ///
  /// Instance method (not an extension) so tests can override it with a fake
  /// that records calls — Dart extension methods are statically dispatched and
  /// cannot be overridden by a test subclass.
  void logError(String op, Object error) {
    if (error is HealthApiException) {
      AppLogger.w(
        'HealthApi',
        '$op failed (${error.statusCode} ${error.code ?? "?"})',
      );
    } else {
      AppLogger.w('HealthApi', '$op failed: $error');
    }
  }
}
