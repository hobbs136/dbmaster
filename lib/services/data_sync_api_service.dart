//! Typed client for the Server-side data_sync REST API (一期).
//!
//! Mirrors `DriftApiService` structure: Bearer token from [ServerConnection],
//! `{ok,data,error}` envelope, typed exceptions for 401/403+ENTITLEMENT_GATED.
//!
//! Endpoints (all under `/api/tasks`):
//! - POST   /api/tasks                       — create a data_sync task.
//! - POST   /api/tasks/:id/run               — manual run-now (202 async).
//! - POST   /api/tasks/:id/cancel            — request cancel of running run.
//! - PATCH  /api/tasks/:id                   — partial update (enabled/name/cron_expr/notify_channels).
//! - DELETE /api/tasks/:id                   — delete the task.
//! - GET    /api/tasks                       — list (client filters data_sync).
//! - GET    /api/tasks/:id/data-sync-runs    — run history with progress/cursor.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/data_sync_api_models.dart';
import '../models/drift_models.dart' show ServerEntitlement;
import '../utils/app_logger.dart';
import 'server_connection.dart';

/// Exception carrying the Server's stable error `code` when present.
class DataSyncApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const DataSyncApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'DataSyncApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class DataSyncApiAuthException extends DataSyncApiException {
  const DataSyncApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// HTTP 403 with `ENTITLEMENT_GATED` — Server is gated; mutations refused.
class DataSyncApiEntitlementException extends DataSyncApiException {
  const DataSyncApiEntitlementException()
      : super(
          'License gated. Activate or renew the Server license to run data_sync.',
          code: 'ENTITLEMENT_GATED',
          statusCode: 403,
        );
}

/// Typed data_sync REST client. Cheap to construct; the desktop can hold a
/// long-lived singleton or build per-feature.
class DataSyncApiService {
  final ServerConnection _connection;

  @visibleForTesting
  final http.Client? httpClient;

  DataSyncApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  // ── Tasks ──

  /// Create a data_sync task. `config` is the task's JSON config (see
  /// Rust `DataSyncTaskConfig`). `cronExpr` empty = run-once. Returns the
  /// created task (with its server-assigned id).
  Future<DataSyncTask> createTask({
    required String name,
    required Map<String, dynamic> config,
    required String sourceDbId,
    required String targetDbId,
    String cronExpr = '',
    List<String> notifyChannels = const [],
  }) async {
    final body = await _postJson('/api/tasks', {
      'name': name,
      'task_type': 'data_sync',
      'cron_expr': cronExpr,
      'config': config,
      'source_db_id': sourceDbId,
      'target_db_id': targetDbId,
      'notify_channels': notifyChannels,
    });
    return DataSyncTask.fromJson(_asMap(body));
  }

  /// Trigger an immediate run. Returns 202 immediately; the runner works
  /// async and writes progress to `data_sync_runs`.
  Future<void> runTaskNow(String taskId) async {
    await _postEmpty('/api/tasks/$taskId/run');
  }

  /// Request cancellation of the currently-running run for [taskId].
  /// Idempotent: returns 200 even if nothing is running.
  Future<void> cancelTask(String taskId) async {
    await _postEmpty('/api/tasks/$taskId/cancel');
  }

  /// Partial PATCH a task's schedule fields (server-side #5 partial PATCH).
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

  /// Delete a task.
  Future<void> deleteTask(String taskId) async {
    await _delete('/api/tasks/$taskId');
  }

  /// List all tasks, filtered client-side to `task_type == 'data_sync'`.
  Future<List<DataSyncTask>> listTasks() async {
    final data = await _getList('/api/tasks');
    return data
        .map((j) => DataSyncTask.fromJson(j as Map<String, dynamic>))
        .where((t) => t.taskType == 'data_sync')
        .toList();
  }

  /// Fetch recent data_sync_runs for [taskId] (progress / cursor / status).
  Future<List<DataSyncRunStatus>> listRuns(String taskId, {int limit = 20}) async {
    final data = await _getList('/api/tasks/$taskId/data-sync-runs?limit=$limit');
    return data
        .map((j) => DataSyncRunStatus.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// 与 DriftApiService 共享同一端点（entitlement 是 server 级别，非 feature 级别），
  /// 复用 drift_models 的 ServerEntitlement 模型避免重复定义。
  Future<ServerEntitlement> fetchEntitlement() async {
    final v = await _send('GET', '/api/entitlement');
    return ServerEntitlement.fromJson(_asMap(v));
  }

  // ── HTTP plumbing (mirrors DriftApiService) ──

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final base = _baseUrl;
    if (base == null || !isConnected) {
      throw const DataSyncApiException('not connected to server');
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
    } on DataSyncApiException {
      rethrow;
    } catch (e) {
      DataSyncApiServiceLog.logError('$method $path', e);
      throw DataSyncApiException('network error: $e');
    } finally {
      if (httpClient == null) client.close();
    }
  }

  dynamic _decode(String method, String path, int status, String raw) {
    dynamic json;
    try {
      json = jsonDecode(raw);
    } catch (e) {
      DataSyncApiServiceLog.logError('$method $path non-JSON', e);
      throw DataSyncApiException('non-JSON response', statusCode: status);
    }
    final envelope = json is Map<String, dynamic> ? json : null;
    final ok = envelope?['ok'] == true;
    if (status == 401) {
      ServerConnection().reportAuthFailure();
      throw const DataSyncApiAuthException();
    }
    final errMap = envelope?['error'] is Map
        ? envelope!['error'] as Map<String, dynamic>
        : null;
    if (status == 403 && errMap?['code'] == 'ENTITLEMENT_GATED') {
      throw const DataSyncApiEntitlementException();
    }
    if (!ok || errMap != null) {
      final code = errMap?['code'] as String?;
      final msg = (errMap?['message'] as String?) ?? 'request failed';
      DataSyncApiServiceLog.logError('$method $path $status ${code ?? "?"}', msg);
      throw DataSyncApiException(msg, code: code, statusCode: status);
    }
    return envelope?['data'];
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    throw const DataSyncApiException('expected JSON object');
  }

  Future<List<dynamic>> _getList(String path) async {
    final v = await _send('GET', path);
    if (v is List) return v;
    throw const DataSyncApiException('expected JSON array');
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body) async =>
      _asMap(await _send('POST', path, body: body));

  Future<Map<String, dynamic>> _patchJson(String path, Map<String, dynamic> body) async =>
      _asMap(await _send('PATCH', path, body: body));

  Future<void> _postEmpty(String path) async {
    await _send('POST', path);
  }

  Future<void> _delete(String path) async {
    await _send('DELETE', path);
  }
}

/// Redacted error logger (mirrors DriftApiServiceLog). Never logs the body.
class DataSyncApiServiceLog {
  static void logError(String op, Object error) {
    if (error is DataSyncApiException) {
      AppLogger.w('DataSyncApi', '$op failed: ${error.statusCode} ${error.code}: ${error.message}');
    } else {
      AppLogger.w('DataSyncApi', '$op failed: $error');
    }
  }
}
