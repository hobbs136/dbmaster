//! Typed client for the reports hub REST API (#29 reports 管道 M2).
//!
//! Endpoints:
//! - `GET /api/reports?report_type=&limit=&offset=` → [ReportsPage]（分页新
//!   形状，M2 起）。
//! - `GET /api/reports/:id` → [Report]。
//! - `POST /api/reports/generate` → [GenerateReportResult]（手动生成本期
//!   周报；幂等。mutation → 远程 Gated 态 403，embedded 不受影响）。
//!
//! Bearer token / 错误模型与 `QueryStatsApiService` 同构。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/report_models.dart';
import '../utils/app_logger.dart';
import 'server_connection.dart';

/// Exception shape carrying the Server's stable error `code` when present.
class ReportsApiException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const ReportsApiException(this.message, {this.code, this.statusCode});

  @override
  String toString() =>
      'ReportsApiException($statusCode ${code ?? "?"}: $message)';
}

/// HTTP 401 — access token rejected; caller should prompt reconnect.
class ReportsApiAuthException extends ReportsApiException {
  const ReportsApiAuthException()
      : super('Server session expired. Please reconnect.', statusCode: 401);
}

/// HTTP 403 + `ENTITLEMENT_GATED` — Server is gated; mutations refused.
class ReportsApiEntitlementException extends ReportsApiException {
  const ReportsApiEntitlementException()
      : super(
          'License gated. Activate or renew the Server license to perform this action.',
          code: 'ENTITLEMENT_GATED',
          statusCode: 403,
        );
}

class ReportsApiService {
  final ServerConnection _connection;

  @visibleForTesting
  final http.Client? httpClient;

  ReportsApiService({ServerConnection? connection, this.httpClient})
      : _connection = connection ?? ServerConnection();

  bool get isConnected =>
      _connection.connectionState == ServerConnectionState.connected;

  String? get _baseUrl => _connection.serverUrl;

  /// 报告列表（`report_type` 空则全类型——报告中心 hub 语义）。
  Future<ReportsPage> listReports({
    String? reportType,
    int limit = 50,
    int offset = 0,
  }) async {
    final query = 'limit=$limit&offset=$offset'
        '${reportType != null ? '&report_type=${Uri.encodeQueryComponent(reportType)}' : ''}';
    final resp = await _send('GET', '/api/reports?$query');
    final data = _decodeEnvelope(resp, 'GET', '/api/reports');
    if (data is Map<String, dynamic>) return ReportsPage.fromJson(data);
    throw ReportsApiException(
      'GET /api/reports: unexpected response shape',
      statusCode: resp.statusCode,
    );
  }

  /// 单份报告（含 content 原文）。
  Future<Report> getReport(String id) async {
    final resp = await _send('GET', '/api/reports/$id');
    final data = _decodeEnvelope(resp, 'GET', '/api/reports/:id');
    if (data is Map<String, dynamic>) return Report.fromJson(data);
    throw ReportsApiException(
      'GET /api/reports/$id: unexpected response shape',
      statusCode: resp.statusCode,
    );
  }

  /// 手动生成本期慢查询周报（幂等：本窗口已有 → created=false）。
  Future<GenerateReportResult> generateWeekly() async {
    final resp = await _send(
      'POST',
      '/api/reports/generate',
      body: jsonEncode({'report_type': 'slow_query_weekly'}),
    );
    final data = _decodeEnvelope(resp, 'POST', '/api/reports/generate');
    if (data is Map<String, dynamic>) return GenerateReportResult.fromJson(data);
    throw ReportsApiException(
      'POST /api/reports/generate: unexpected response shape',
      statusCode: resp.statusCode,
    );
  }

  Future<http.Response> _send(String method, String path, {String? body}) async {
    final baseUrl = _baseUrl;
    if (baseUrl == null || !isConnected) {
      throw const ReportsApiException('Not connected to a DbMaster server.');
    }
    final token = await _connection.getAccessToken();
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
          return await client.post(uri, headers: headers, body: body ?? '');
        default:
          throw ReportsApiException('Unsupported HTTP method: $method');
      }
    } finally {
      if (ownsClient) client.close();
    }
  }

  dynamic _decodeEnvelope(http.Response resp, String method, String path) {
    if (resp.statusCode == 401) {
      ServerConnection().reportAuthFailure();
      throw const ReportsApiAuthException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(resp.body);
    } catch (_) {
      throw ReportsApiException(
        '$method $path: non-JSON response (status ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ReportsApiException(
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
        throw const ReportsApiEntitlementException();
      }
      throw ReportsApiException(
        '$method $path: $message',
        code: code,
        statusCode: resp.statusCode,
      );
    }
    return decoded['data'];
  }

  void logError(String op, Object error) {
    if (error is ReportsApiException) {
      AppLogger.w(
        'ReportsApi',
        '$op failed (${error.statusCode} ${error.code ?? "?"})',
      );
    } else {
      AppLogger.w('ReportsApi', '$op failed: $error');
    }
  }
}
