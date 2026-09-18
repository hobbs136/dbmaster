//! Typed client for the Server-side DDL approval REST API (#25). Mirrors
//! `SavedQueryApiService` structure: Bearer token from [ServerConnection],
//! `{ok,data,error}` envelope, typed exceptions for 401 / 403+ENTITLEMENT_GATED.
//!
//! Endpoints (all under `/api/approvals`):
//! - GET    /api/approvals                — list (newest first; read-only, no gate).
//! - POST   /api/approvals                — submit DDL for review (gated).
//! - POST   /api/approvals/:id/approve    — claim + async-execute DDL (gated).
//! - POST   /api/approvals/:id/reject     — reject without executing (gated).
//!
//! Server-side notes the client adapts to (no contract change here):
//! - There is NO single-row GET; callers list + filter by id client-side.
//! - approve returns `{id,status:"executing",exec_status:"executing"}` and the
//!   DDL runs in a spawned task; the client polls [list] to observe the
//!   `approved`/`failed` transition.
//! - reject does NOT validate the current status, set reviewer_id, or roll
//!   back an already-executed DDL — callers should confirm with the user first.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/ddl_approval.dart';
import '../models/drift_models.dart' show DriftSourceConnection, ServerEntitlement;
import 'server_connection.dart';

/// Exception carrying the Server's stable error `code` when present.
class ApprovalApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const ApprovalApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'ApprovalApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class ApprovalApiAuthException extends ApprovalApiException {
  const ApprovalApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// HTTP 403 with `ENTITLEMENT_GATED` — Server is gated; mutations refused.
class ApprovalApiEntitlementException extends ApprovalApiException {
  const ApprovalApiEntitlementException()
      : super(
          'License gated. Activate or renew the Server license to manage DDL approvals.',
          code: 'ENTITLEMENT_GATED',
          statusCode: 403,
        );
}

/// Typed DDL-approval REST client. Cheap to construct; the
/// [ApprovalProvider] holds a long-lived instance and the dialogs build
/// short-lived per-use instances.
class ApprovalApiService {
  final ServerConnection _connection;

  @visibleForTesting
  final http.Client? httpClient;

  ApprovalApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  /// GET /api/approvals — list all DDL approvals (newest first). The Server
  /// returns all rows visible to the workspace; no server-side status filter.
  /// Returns `[]` when not connected (caller short-circuits).
  Future<List<DdlApproval>> list() async {
    final data = await _get('/api/approvals');
    if (data is! List) return const [];
    return data
        .map((e) => DdlApproval.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/approvals — submit a DDL for review (gated). The Server
  /// returns `{id, status:"pending"}` (not the full row), so callers should
  /// [list] to refresh. Returns the new approval's id.
  Future<String> submit({
    required String ddlSql,
    required String targetDbId,
  }) async {
    final body = await _postJson('/api/approvals', {
      'ddl_sql': ddlSql,
      'target_db_id': targetDbId,
    });
    final id = body['id'] as String?;
    if (id == null) {
      throw const ApprovalApiException('submit: server returned no id');
    }
    return id;
  }

  /// POST /api/approvals/:id/approve — claim the approval and trigger async
  /// DDL execution (gated). The Server returns `{id,status:"executing",
  /// exec_status:"executing"}` immediately; poll [list] for the terminal
  /// `approved`/`failed` state. Throws on ALREADY_RESOLVED / CONFLICT /
  /// APPROVAL_NOT_FOUND / ENTITLEMENT_GATED.
  Future<void> approve(String id) async {
    await _postEmpty('/api/approvals/${Uri.encodeComponent(id)}/approve');
  }

  /// POST /api/approvals/:id/reject — reject without executing (gated). The
  /// Server does not validate the current status, so callers should confirm
  /// with the user (see [ApprovalApiException] notes). Throws on
  /// APPROVAL_NOT_FOUND / ENTITLEMENT_GATED.
  Future<void> reject(String id) async {
    await _postEmpty('/api/approvals/${Uri.encodeComponent(id)}/reject');
  }

  /// GET /api/connections — all database_connections rows (the Server does not
  /// filter by kind; approvals may target any collab/source connection). Reuses
  /// `DriftSourceConnection` (generic id/name/dbType/host/port shape), same as
  /// the health_check create-task flow.
  Future<List<DriftSourceConnection>> listConnections() async {
    final data = await _get('/api/connections');
    if (data is! List) return const [];
    return data
        .map((e) => DriftSourceConnection.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/entitlement — license/trial/gated state. Shared Server-wide
  /// state (same as drift/data_sync/health/saved_query).
  Future<ServerEntitlement> fetchEntitlement() async {
    final data = await _get('/api/entitlement');
    return ServerEntitlement.fromJson(data as Map<String, dynamic>);
  }

  // ── Low-level HTTP plumbing (mirrors SavedQueryApiService) ──

  Future<dynamic> _get(String path) async {
    final resp = await _send('GET', path);
    return _decodeEnvelope(resp, 'GET', path);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final resp = await _send('POST', path, body: jsonEncode(payload));
    return _decodeEnvelopeMap(resp, 'POST', path);
  }

  /// POST with an empty body (for approve/reject — no request payload). Decodes
  /// the envelope so `{ok:false}` surfaces as [ApprovalApiException].
  Future<void> _postEmpty(String path) async {
    final resp = await _send('POST', path, body: '');
    _decodeEnvelope(resp, 'POST', path);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
  }) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || !isConnected) {
      throw const ApprovalApiException('Not connected to a DbMaster server.');
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
        default:
          throw ApprovalApiException('Unsupported HTTP method: $method');
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
      throw const ApprovalApiAuthException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw ApprovalApiException(
        '$method $path: non-JSON response (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApprovalApiException(
        '$method $path: unexpected response shape',
        statusCode: resp.statusCode,
      );
    }
    final ok = decoded['ok'] as bool? ?? false;
    final error = decoded['error'];
    if (!ok) {
      final code =
          error is Map<String, dynamic> ? error['code'] as String? : null;
      final message = error is Map<String, dynamic>
          ? (error['message'] as String?) ?? 'Unknown error'
          : 'Unknown error';
      if (resp.statusCode == 403 && code == 'ENTITLEMENT_GATED') {
        throw const ApprovalApiEntitlementException();
      }
      throw ApprovalApiException(
        '$method $path: $message',
        code: code,
        statusCode: resp.statusCode,
      );
    }
    return decoded['data'];
  }

  Map<String, dynamic> _decodeEnvelopeMap(
    http.Response resp,
    String method,
    String path,
  ) {
    final data = _decodeEnvelope(resp, method, path);
    if (data is Map<String, dynamic>) return data;
    throw ApprovalApiException(
      '$method $path: expected JSON object, got ${data?.runtimeType ?? "null"}',
      statusCode: resp.statusCode,
    );
  }
}
