//! Typed client for the Server-side workspace REST API (#26). Mirrors the
//! structure of `ApprovalApiService` / `SavedQueryApiService`, but with a
//! **different response decoder**: the workspace endpoints (core router, same
//! as `/api/entitlement` / `/api/auth`) return the payload **directly**, NOT
//! wrapped in the `{ok,data,error}` envelope used by the automation routes.
//! Errors everywhere are `{error:{code,message}}`.
//!
//! Endpoints (all JWT-auth, NOT license-gated):
//! - GET    /api/workspaces                — list workspaces I'm a member of.
//! - POST   /api/workspaces                — create (creator becomes admin).
//! - GET    /api/workspaces/:id            — detail + full member list.
//! - DELETE /api/workspaces/:id            — delete (admin only).
//! - POST   /api/workspaces/:id/join       — join via invite code (body).
//! - POST   /api/workspaces/:id/leave      — leave (last admin refused).
//! - DELETE /api/workspaces/:id/members/:uid — remove a member (admin only).
//!
//! Server-side notes the client adapts to (no contract change here):
//! - There is NO role-promotion / workspace-rename / invite-regen endpoint.
//! - join needs BOTH the workspace `:id` (path) AND `invite_code` (body) —
//!   the route is shaped `:id/join`, so a share-invite must carry both.
//! - leave + remove_member refuse to remove the last admin (422
//!   BUSINESS_RULE_VIOLATION).
//! - Invalid invite code / already-a-member surface as 409 CONFLICT.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/workspace.dart';
import 'server_connection.dart';

/// Exception carrying the Server's stable error `code` when present.
class WorkspaceApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const WorkspaceApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'WorkspaceApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class WorkspaceApiAuthException extends WorkspaceApiException {
  const WorkspaceApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// Typed workspace REST client. Cheap to construct; the [WorkspaceProvider]
/// holds a long-lived instance and the dialogs build short-lived per-use ones.
class WorkspaceApiService {
  final ServerConnection _connection;

  @visibleForTesting
  final http.Client? httpClient;

  WorkspaceApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  /// GET /api/workspaces — workspaces the caller is a member of (newest first).
  /// Returns `[]` when not connected (caller short-circuits).
  Future<List<Workspace>> list() async {
    final data = await _get('/api/workspaces');
    // Raw payload: `{workspaces: [...]}`.
    if (data is! Map<String, dynamic>) return const [];
    final arr = data['workspaces'];
    if (arr is! List) return const [];
    return arr
        .whereType<Map<String, dynamic>>()
        .map(Workspace.fromJson)
        .toList();
  }

  /// POST /api/workspaces — create a workspace. The caller becomes admin.
  /// Server validates name length 1–100 (after trim); mirroring client-side is
  /// advisory — the Server is the source of truth.
  Future<Workspace> create(String name) async {
    final body = await _postJson('/api/workspaces', {'name': name});
    return Workspace.fromJson(body);
  }

  /// GET /api/workspaces/:id — workspace detail + full member list. Throws
  /// FORBIDDEN if the caller is not a member.
  Future<WorkspaceDetail> get(String id) async {
    final data =
        await _get('/api/workspaces/${Uri.encodeComponent(id)}');
    return WorkspaceDetail.fromJson(data as Map<String, dynamic>);
  }

  /// DELETE /api/workspaces/:id — delete a workspace (admin only). Cascades to
  /// memberships. Throws FORBIDDEN (non-admin) / NOT_FOUND.
  Future<void> delete(String id) async {
    await _delete('/api/workspaces/${Uri.encodeComponent(id)}');
  }

  /// POST /api/workspaces/:id/join — join via invite code. Needs BOTH the
  /// workspace id (path) and the invite code (body). Throws CONFLICT on
  /// already-a-member or invalid code (Server returns a generic message to
  /// avoid revealing whether the workspace exists).
  Future<void> join(String id, String inviteCode) async {
    await _postJson(
      '/api/workspaces/${Uri.encodeComponent(id)}/join',
      {'invite_code': inviteCode},
    );
  }

  /// POST /api/workspaces/:id/leave — leave a workspace. Throws
  /// BUSINESS_RULE_VIOLATION if the caller is the last admin (must delete or
  /// promote first — but the Server has no promote endpoint, so effectively
  /// must delete).
  Future<void> leave(String id) async {
    await _postEmpty('/api/workspaces/${Uri.encodeComponent(id)}/leave');
  }

  /// DELETE /api/workspaces/:id/members/:uid — remove a member (admin only).
  /// Throws FORBIDDEN / NOT_FOUND / BUSINESS_RULE_VIOLATION (last admin).
  Future<void> removeMember(String workspaceId, String userId) async {
    await _delete(
      '/api/workspaces/${Uri.encodeComponent(workspaceId)}/members/'
      '${Uri.encodeComponent(userId)}',
    );
  }

  // ── Low-level HTTP plumbing ──
  //
  // Distinct from the automation services: workspace endpoints return the raw
  // payload (no `{ok,data}` envelope), so `_decodeRaw` parses 2xx bodies
  // directly and only consults `{error:{code,message}}` on non-2xx.

  Future<dynamic> _get(String path) async {
    final resp = await _send('GET', path);
    return _decodeRaw(resp, 'GET', path);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final resp = await _send('POST', path, body: jsonEncode(payload));
    return _decodeRawMap(resp, 'POST', path);
  }

  /// POST with an empty body (leave has no request payload).
  Future<void> _postEmpty(String path) async {
    final resp = await _send('POST', path, body: '');
    _decodeRaw(resp, 'POST', path);
  }

  Future<void> _delete(String path) async {
    final resp = await _send('DELETE', path);
    _decodeRaw(resp, 'DELETE', path);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
  }) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || !isConnected) {
      throw const WorkspaceApiException('Not connected to a DbMaster server.');
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
        default:
          throw WorkspaceApiException('Unsupported HTTP method: $method');
      }
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Decode a raw workspace response. 2xx → the parsed body (Map/List/`null`
  /// for 204). Non-2xx → parse `{error:{code,message}}` and throw.
  dynamic _decodeRaw(http.Response resp, String method, String path) {
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const WorkspaceApiAuthException();
    }
    // 204 No Content (delete/leave/remove_member) → empty body, return null.
    if (resp.statusCode == 204 || resp.body.isEmpty) {
      if (resp.statusCode >= 200 && resp.statusCode < 300) return null;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw WorkspaceApiException(
        '$method $path: non-JSON response (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return decoded;
    }
    // Error path: `{error:{code,message}}`.
    if (decoded is Map<String, dynamic>) {
      final error = decoded['error'];
      if (error is Map<String, dynamic>) {
        final code = error['code'] as String?;
        final message = (error['message'] as String?) ?? 'Unknown error';
        throw WorkspaceApiException(
          '$method $path: $message',
          code: code,
          statusCode: resp.statusCode,
        );
      }
    }
    throw WorkspaceApiException(
      '$method $path: error (status ${resp.statusCode})',
      statusCode: resp.statusCode,
    );
  }

  Map<String, dynamic> _decodeRawMap(
    http.Response resp,
    String method,
    String path,
  ) {
    final data = _decodeRaw(resp, method, path);
    if (data is Map<String, dynamic>) return data;
    throw WorkspaceApiException(
      '$method $path: expected JSON object, got ${data?.runtimeType ?? "null"}',
      statusCode: resp.statusCode,
    );
  }
}
