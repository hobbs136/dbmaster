//! Typed client for the Server-side slow-query stats REST API (reports-M1 /
//! #29, migration 016).
//!
//! Endpoints (both read-only, Claims auth, no entitlement gate — the server
//! keeps them visible-but-locked under Gated):
//! - `GET /api/query-stats/summary?window=&conn_id=&sort=&limit=` →
//!   [QueryStatsSummary] (Top N by digest + `meta` for the scope banner).
//! - `GET /api/query-stats?window=&conn_id=&digest=&status=&limit=&offset=` →
//!   [QueryStatsDetailPage] (paged raw samples).
//!
//! Bearer token comes from [ServerConnection]. Error model mirrors
//! `HealthApiService`:
//! - Network / non-JSON / `{ok:false}` → [QueryStatsApiException] (carries
//!   the Server's stable `code`).
//! - HTTP 401 → [QueryStatsApiAuthException] (caller prompts reconnect).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/query_stats_models.dart';
import '../utils/app_logger.dart';
import 'server_connection.dart';

/// Exception shape carrying the Server's stable error `code` when present.
class QueryStatsApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const QueryStatsApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'QueryStatsApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class QueryStatsApiAuthException extends QueryStatsApiException {
  const QueryStatsApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// 时间窗 preset（server 端白名单：`1h` / `24h` / `7d`；非法值回退 24h）。
class QueryStatsWindow {
  static const oneHour = '1h';
  static const day = '24h';
  static const week = '7d';
}

/// summary 排序维度（server 端白名单）。
class QueryStatsSort {
  static const totalMs = 'total_ms';
  static const count = 'count';
  static const avgMs = 'avg_ms';
  static const maxMs = 'max_ms';
}

/// Typed slow-query stats REST client. One instance is cheap; the dialog
/// constructs one per opening (no provider — the view is on-demand only).
class QueryStatsApiService {
  final ServerConnection _connection;

  /// Test-only HTTP client injection.
  @visibleForTesting
  final http.Client? httpClient;

  QueryStatsApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  /// Top N 聚合 + meta。
  Future<QueryStatsSummary> fetchSummary({
    String window = QueryStatsWindow.day,
    String? connId,
    String sort = QueryStatsSort.totalMs,
    int limit = 20,
  }) async {
    final query = 'window=${Uri.encodeQueryComponent(window)}'
        '&sort=${Uri.encodeQueryComponent(sort)}'
        '&limit=$limit'
        '${connId != null ? '&conn_id=${Uri.encodeQueryComponent(connId)}' : ''}';
    final resp = await _send('GET', '/api/query-stats/summary?$query');
    final data = _decodeEnvelope(resp, 'GET', '/api/query-stats/summary');
    if (data is Map<String, dynamic>) {
      return QueryStatsSummary.fromJson(data);
    }
    throw QueryStatsApiException(
      'GET /api/query-stats/summary: unexpected response shape',
      statusCode: resp.statusCode,
    );
  }

  /// 明细分页。
  Future<QueryStatsDetailPage> fetchDetail({
    String window = QueryStatsWindow.day,
    String? connId,
    String? digest,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = 'window=${Uri.encodeQueryComponent(window)}'
        '&limit=$limit&offset=$offset'
        '${connId != null ? '&conn_id=${Uri.encodeQueryComponent(connId)}' : ''}'
        '${digest != null ? '&digest=${Uri.encodeQueryComponent(digest)}' : ''}'
        '${status != null ? '&status=${Uri.encodeQueryComponent(status)}' : ''}';
    final resp = await _send('GET', '/api/query-stats?$query');
    final data = _decodeEnvelope(resp, 'GET', '/api/query-stats');
    if (data is Map<String, dynamic>) {
      return QueryStatsDetailPage.fromJson(data);
    }
    throw QueryStatsApiException(
      'GET /api/query-stats: unexpected response shape',
      statusCode: resp.statusCode,
    );
  }

  /// Wrap the request with auth headers + dispatch through the injected or a
  /// per-call HTTP client.
  Future<http.Response> _send(String method, String path) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || !isConnected) {
      throw const QueryStatsApiException(
          'Not connected to a DbMaster server.');
    }
    final token = await _connection.getAccessToken();
    final headers = <String, String>{
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse('$baseUrl$path');
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      return await client.get(uri, headers: headers);
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Decode the `{ok, data, error}` envelope and return the `data` field.
  dynamic _decodeEnvelope(http.Response resp, String method, String path) {
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const QueryStatsApiAuthException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw QueryStatsApiException(
        '$method $path: non-JSON response (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw QueryStatsApiException(
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
      throw QueryStatsApiException(
        '$method $path: $message',
        code: code,
        statusCode: resp.statusCode,
      );
    }
    return decoded['data'];
  }

  /// Logging helper — logs a coarse redacted line without leaking credentials.
  void logError(String op, Object error) {
    if (error is QueryStatsApiException) {
      AppLogger.w(
        'QueryStatsApi',
        '$op failed (${error.statusCode} ${error.code ?? "?"})',
      );
    } else {
      AppLogger.w('QueryStatsApi', '$op failed: $error');
    }
  }
}
