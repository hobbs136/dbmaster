//! Typed client for the Server's MCP personal-token REST API (dbx-response
//! T04b / decision D7). Mirrors `SavedQueryApiService` structure: Bearer
//! token from [ServerConnection], `{ok,data,error}` envelope, typed
//! exceptions for 401.
//!
//! Endpoints (all under `/api/mcp/tokens`, authenticated via access JWT —
//! MCP tokens themselves are NOT accepted here, only `/mcp` is):
//! - GET    /api/mcp/tokens      — list live tokens (prefix only, no secret).
//! - POST   /api/mcp/tokens      — create; plaintext returned exactly once.
//! - DELETE /api/mcp/tokens/:id  — revoke (soft delete, audited server-side).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/mcp_token.dart';
import 'server_connection.dart';

/// Exception carrying the Server's stable error `code` when present.
class McpTokenApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const McpTokenApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() => 'McpTokenApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class McpTokenApiAuthException extends McpTokenApiException {
  const McpTokenApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// Typed MCP-token REST client. Cheap to construct; the management dialog
/// builds one per open.
class McpTokenApiService {
  final ServerConnection _connection;

  @visibleForTesting
  final http.Client? httpClient;

  McpTokenApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  /// GET /api/mcp/tokens — the caller's live tokens (no secrets).
  Future<List<McpTokenInfo>> list() async {
    final data = await _get('/api/mcp/tokens');
    if (data is! List) return const [];
    return data
        .map((e) => McpTokenInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/mcp/tokens — mint a token. [name] is a display label
  /// ("claude-code-mac"); empty falls back to the server default.
  /// The returned plaintext is shown once and never retrievable again.
  Future<McpTokenCreated> create({String? name}) async {
    final body = await _postJson('/api/mcp/tokens', {
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
    });
    return McpTokenCreated.fromJson(body);
  }

  /// DELETE /api/mcp/tokens/:id — revoke. Throws with code NOT_FOUND when
  /// the id is unknown/already revoked (or owned by someone else).
  Future<void> revoke(String id) async {
    await _delete('/api/mcp/tokens/${Uri.encodeComponent(id)}');
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

  Future<void> _delete(String path) async {
    final resp = await _send('DELETE', path);
    _decodeEnvelope(resp, 'DELETE', path);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
  }) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || !isConnected) {
      throw const McpTokenApiException('Not connected to a DbMaster server.');
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
          throw McpTokenApiException('Unsupported HTTP method: $method');
      }
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Decode the `{ok, data, error}` envelope and return the `data` field.
  /// Throws typed exceptions for 401 / any non-envelope error shape.
  dynamic _decodeEnvelope(http.Response resp, String method, String path) {
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const McpTokenApiAuthException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw McpTokenApiException(
        '$method $path: non-JSON response (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw McpTokenApiException(
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
      throw McpTokenApiException(
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
    throw McpTokenApiException(
      '$method $path: expected JSON object, got ${data?.runtimeType ?? "null"}',
      statusCode: resp.statusCode,
    );
  }
}
