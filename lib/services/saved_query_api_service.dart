//! Typed client for the Server-side saved queries REST API (#4 read/delete +
//! #24 team-library wiring). Mirrors `DriftApiService` structure: Bearer token
//! from [ServerConnection], `{ok,data,error}` envelope, typed exceptions for
//! 401 / 403+ENTITLEMENT_GATED.
//!
//! Endpoints (all under `/api/queries`):
//! - GET    /api/queries          — list (optional ?tag=&q=&limit= filters).
//! - POST   /api/queries          — create (gated under ENTITLEMENT_GATED).
//! - GET    /api/queries/:id      — single (NOT_FOUND → 200 + ok:false).
//! - DELETE /api/queries/:id      — delete (gated; NOT_FOUND → 200 + ok:false).
//!
//! Note: the Server has NO PATCH/update endpoint — editing a team query is
//! delete + recreate.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/saved_query.dart';
import '../models/drift_models.dart' show ServerEntitlement;
import 'server_connection.dart';

/// Exception carrying the Server's stable error `code` when present.
class SavedQueryApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const SavedQueryApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'SavedQueryApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class SavedQueryApiAuthException extends SavedQueryApiException {
  const SavedQueryApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// HTTP 403 with `ENTITLEMENT_GATED` — Server is gated; writes refused.
class SavedQueryApiEntitlementException extends SavedQueryApiException {
  const SavedQueryApiEntitlementException()
      : super(
          'License gated. Activate or renew the Server license to manage team queries.',
          code: 'ENTITLEMENT_GATED',
          statusCode: 403,
        );
}

/// Typed saved-queries REST client. Cheap to construct; callers (the team
/// library dialog + the editor's save-to-team flow) build per-use or hold a
/// short-lived instance.
class SavedQueryApiService {
  final ServerConnection _connection;

  @visibleForTesting
  final http.Client? httpClient;

  SavedQueryApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  /// GET /api/queries — list team queries. Optional [tag] (exact JSON element
  /// match) + [q] (case-insensitive substring on title/sql_text) filters are
  /// applied server-side. Returns `[]` when not connected (caller short-circuits).
  Future<List<SavedQuery>> list({String? tag, String? q, int? limit}) async {
    final qs = <String, String>{};
    if (tag != null && tag.isNotEmpty) qs['tag'] = tag;
    if (q != null && q.isNotEmpty) qs['q'] = q;
    if (limit != null) qs['limit'] = limit.toString();
    final path = qs.isEmpty
        ? '/api/queries'
        : '/api/queries?${_encodeQuery(qs)}';
    final data = await _get(path);
    if (data is! List) return const [];
    return data
        .map((e) => SavedQuery.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// POST /api/queries — create a team query (gated). The Server returns
  /// `{id, saved:true}` (not the full row), so callers should [list] to refresh
  /// the library view. Returns the new query's id.
  Future<String> create({
    required String title,
    required String sqlText,
    List<String> tags = const [],
  }) async {
    final body = await _postJson('/api/queries', {
      'title': title,
      'sql_text': sqlText,
      'tags': tags,
    });
    final id = body['id'] as String?;
    if (id == null) {
      throw const SavedQueryApiException('create: server returned no id');
    }
    return id;
  }

  /// GET /api/queries/:id — single team query. Returns `null` when the Server
  /// reports NOT_FOUND (signaled as 200 + ok:false, not 404).
  Future<SavedQuery?> get(String id) async {
    try {
      final data = await _get('/api/queries/${Uri.encodeComponent(id)}');
      if (data is Map<String, dynamic>) return SavedQuery.fromJson(data);
      return null;
    } on SavedQueryApiException catch (e) {
      if (e.code == 'NOT_FOUND') return null;
      rethrow;
    }
  }

  /// DELETE /api/queries/:id — delete a team query (gated). Idempotent: a
  /// NOT_FOUND response (200 + ok:false) is treated as success.
  Future<void> delete(String id) async {
    try {
      await _delete('/api/queries/${Uri.encodeComponent(id)}');
    } on SavedQueryApiException catch (e) {
      if (e.code == 'NOT_FOUND') return;
      rethrow;
    }
  }

  /// GET /api/entitlement — license/trial/gated state. Shared Server-wide
  /// state (same as drift/data_sync/health).
  Future<ServerEntitlement> fetchEntitlement() async {
    final data = await _get('/api/entitlement');
    return ServerEntitlement.fromJson(data as Map<String, dynamic>);
  }

  // ── Low-level HTTP plumbing (mirrors DriftApiService) ──

  String _encodeQuery(Map<String, String> qs) {
    return qs.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }

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
    // DELETE always goes through the envelope so a 200+ok:false (DB_ERROR,
    // ENTITLEMENT_GATED) surfaces; NOT_FOUND is caught by the public [delete].
    _decodeEnvelope(resp, 'DELETE', path);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    String? body,
  }) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || !isConnected) {
      throw const SavedQueryApiException('Not connected to a DbMaster server.');
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
          throw SavedQueryApiException('Unsupported HTTP method: $method');
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
      throw const SavedQueryApiAuthException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw SavedQueryApiException(
        '$method $path: non-JSON response (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw SavedQueryApiException(
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
        throw const SavedQueryApiEntitlementException();
      }
      throw SavedQueryApiException(
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
    throw SavedQueryApiException(
      '$method $path: expected JSON object, got ${data?.runtimeType ?? "null"}',
      statusCode: resp.statusCode,
    );
  }
}
