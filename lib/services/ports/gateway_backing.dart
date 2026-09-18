//! GatewayBacking —— DbCapabilityPort 的网关实现（已迁移类型；c01 §4/§5）。
//!
//! 连接语义走 T27 网关 API v1（dbmaster-server crates/gateway）：
//! - 测试连接 = `POST /api/gw/connections/test`（**测试即远程调用**：连通性
//!   反映 server 所在网络位置，草稿不落库）；
//! - 保存 = `POST /api/gw/connections`（凭据入 server vault——AES-256-GCM
//!   密文落 `database_connections.password_encrypted`，响应返回 serverConnId；
//!   客户端经 ConnectionProvider 留 id 镜像，UI 不再持明文凭据）；
//! - 删除 = `DELETE /api/gw/connections/{id}`（幂等，恒 204）。
//!
//! embedded（本地 server，`127.0.0.1:<port>` + 握手 token）与远程 server 两
//! 形态行为一致：形态差异被 [ServerConnection] 的 serverUrl + Bearer token
//! 抽象吸收，本类不区分（server 侧路由同挂、embedded 合成 Licensed 免门控）。
//!
//! 注意网关 wire **不**用其它 server API 的 `{ok,data,error}` 信封：test 响应
//! 直接是 `{ok,elapsedMs,serverVersion?}`，结构化错误统一
//! `{"error":{"code","message"}}`（§4.4 码集）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../models/database_models.dart';
import '../../utils/app_logger.dart';
import '../server_connection.dart';
import 'capability_table.dart';
import 'db_capability_port.dart';
import 'port_types.dart';

class GatewayBacking implements DbCapabilityPort {
  GatewayBacking({ServerConnection? connection, http.Client? httpClient})
    : _connection = connection ?? ServerConnection(),
      _httpClient = httpClient;

  /// 不注入则每请求新建（与 DbGatewayService._send 同策略）。
  final ServerConnection _connection;
  final http.Client? _httpClient;

  @visibleForTesting
  static const Duration requestTimeout = Duration(seconds: 30);

  @override
  bool hasCapability(DatabaseType type, String capabilityId) =>
      CapabilityTable.has(type, capabilityId);

  @override
  Set<String> capabilitiesOf(DatabaseType type) => CapabilityTable.of(type);

  @override
  Future<ConnectionState> connectionState(String connectionId) async {
    final mode =
        _connection.isEmbeddedMode
            ? ConnectionMode.embeddedServer
            : ConnectionMode.remoteServer;
    // readOnly = server 注册值（安全投影列表里带 readOnly，无凭据字段）。
    var readOnly = false;
    try {
      final resp = await _send('GET', '/api/gw/connections');
      final rows = jsonDecode(resp.body) as List<dynamic>;
      for (final row in rows) {
        if (row is Map<String, dynamic> && row['id'] == connectionId) {
          readOnly = row['readOnly'] == true;
          break;
        }
      }
    } catch (e) {
      // 列表查询失败不阻断形态判定（readOnly 退化为 false）。
      AppLogger.w('GatewayBacking', 'connectionState list failed: $e');
    }
    return ConnectionState(mode: mode, readOnly: readOnly);
  }

  @override
  Future<ConnectionTestResult> testConnection(DbServer draft) async {
    final resp = await _send('POST', '/api/gw/connections/test', body: draftBody(draft));
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return ConnectionTestResult(
      ok: body['ok'] == true,
      error: body['error'] as String?,
      elapsedMs: (body['elapsedMs'] as num?)?.toInt() ?? 0,
      serverVersion: body['serverVersion'] as String?,
    );
  }

  @override
  Future<String> persistConnection(DbServer server) async {
    final body = draftBody(server)
      ..['name'] = server.name
      ..['readOnly'] = server.readOnly;
    if (server.charset != null) body['charset'] = server.charset;
    if (server.timezone != null) body['timezone'] = server.timezone;
    final resp = await _send('POST', '/api/gw/connections', body: body);
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final serverConnId = decoded['serverConnId'] as String?;
    if (serverConnId == null || serverConnId.isEmpty) {
      throw const PortException('DB_ERROR', 'register response missing serverConnId');
    }
    return serverConnId;
  }

  @override
  Future<void> removeConnection(String connectionId) async {
    // 幂等：server 对不存在的 id 也回 204；错误（非 2xx）抛 PortException。
    await _send('DELETE', '/api/gw/connections/$connectionId');
  }

  // ── C14 落地（Tier 1 三端点；wire 见 c01 §4.1）──

  @override
  Future<List<String>> listDatabases(String connectionId) =>
      throw UnimplementedError('Tier 1 元数据经 GatewayBacking 落地于 C14');

  @override
  Future<List<TableSummary>> listTables(
    String connectionId, {
    String? database,
    String? schema,
  }) => throw UnimplementedError('Tier 1 元数据经 GatewayBacking 落地于 C14');

  @override
  Future<TableDescription> describeTable(
    String connectionId,
    String table, {
    String? database,
    String? schema,
  }) => throw UnimplementedError('Tier 1 元数据经 GatewayBacking 落地于 C14');

  // ── C13 落地（SSE 流式执行；wire 见 c01 §4.1/§4.2）──

  @override
  ExecutionSession execute(String connectionId, ExecutionRequest request) {
    // X-Execution-Id 须为合法 UUID（server 侧注册表防注入校验；uuid 包
    // 已是依赖）。取消句柄 = 同 id 的 DELETE，任何时刻可发（含流建立前）。
    final executionId = const Uuid().v4();
    return _GatewayExecutionSession(
      chunks: _executionChunks(connectionId, request, executionId),
      executionId: executionId,
      gateway: this,
    );
  }

  /// 单次执行的 SSE 块流：meta → rows* → complete|error（真流式——行批到
  /// 达即下发，不等聚合；与 T28 网关壳的全量聚合消费互补）。流内错误一律
  /// 经 [ExecutionError] 块（含前置 4xx 与传输失败），session 面不抛。
  Stream<ExecutionChunk> _executionChunks(
    String connectionId,
    ExecutionRequest request,
    String executionId,
  ) async* {
    final baseUrl = _connection.serverUrl;
    if (baseUrl == null ||
        _connection.connectionState != ServerConnectionState.connected) {
      yield ExecutionError(
        code: 'CONFIG',
        message: 'not connected to a dbmaster server (gateway unavailable)',
      );
      return;
    }
    final token = await _connection.getAccessToken();
    final uri = Uri.parse('$baseUrl/api/gw/connections/$connectionId/query');
    final req = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['Accept'] = 'text/event-stream'
      ..headers['X-Execution-Id'] = executionId
      ..body = jsonEncode({
        'sql': request.sql,
        if (request.database != null && request.database!.isNotEmpty)
          'database': request.database,
        if (request.schema != null && request.schema!.isNotEmpty)
          'schema': request.schema,
        if (request.rowLimit != null) 'rowLimit': request.rowLimit,
        if (request.timeout != null)
          'timeoutMs': request.timeout!.inMilliseconds,
      });
    if (token != null) req.headers['Authorization'] = 'Bearer $token';

    final client = _httpClient ?? http.Client();
    final ownsClient = _httpClient == null;
    try {
      final response = await client.send(req);
      // 前置校验失败（4xx JSON，流未开始）：{"error":{code,message}}。
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.stream.bytesToString();
        yield _errorFromPreFlight(response.statusCode, text);
        return;
      }

      var pendingEvent = '';
      var pendingData = '';
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) {
          if (pendingData.isNotEmpty) {
            final chunk = _chunkFromEvent(pendingEvent, pendingData);
            if (chunk != null) {
              yield chunk;
              // 终止事件（complete/error）后 server 关流——提前退出释放连接。
              if (chunk is ExecutionComplete || chunk is ExecutionError) {
                return;
              }
            }
          }
          pendingEvent = '';
          pendingData = '';
        } else if (line.startsWith('event:')) {
          pendingEvent = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          pendingData = line.substring(5).trim();
        }
        // `id:`（seq）不消费；keep-alive 注释行（`:…`）忽略。
      }
      // 流裸断（无终态事件）——对齐 T28 壳判级：传输层失败。
      yield ExecutionError(
        code: 'CONNECTION_FAILED',
        message: 'gateway SSE stream ended without a terminal event',
      );
    } on http.ClientException catch (e) {
      yield ExecutionError(
        code: 'CONNECTION_FAILED',
        message: 'gateway unreachable (${e.message})',
      );
    } on TimeoutException {
      yield ExecutionError(
        code: 'CONNECTION_FAILED',
        message: 'gateway query connection timed out',
      );
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// SSE data JSON → 契约 chunk（§4.2 形状；未知事件名/坏 JSON 跳过不抛）。
  ExecutionChunk? _chunkFromEvent(String event, String data) {
    final Map<String, dynamic> chunk;
    try {
      chunk = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    switch (event) {
      case 'meta':
        return ExecutionMeta(
          columns: (chunk['columns'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
        );
      case 'rows':
        return ExecutionRows(
          rows: (chunk['rows'] as List<dynamic>? ?? [])
              .whereType<List<dynamic>>()
              .toList(),
        );
      case 'complete':
        return ExecutionComplete(
          rowCount: (chunk['rowCount'] as num?)?.toInt() ?? 0,
          truncated: chunk['truncated'] == true,
          elapsedMs: (chunk['elapsedMs'] as num?)?.toInt() ?? 0,
        );
      case 'error':
        return ExecutionError(
          code: chunk['code']?.toString() ?? 'DB_ERROR',
          message: chunk['message']?.toString() ?? 'query failed',
          engineCode: chunk['engineCode']?.toString(),
        );
      default:
        return null;
    }
  }

  /// 前置 4xx（流未开始）→ 结构化错误块（401 顺带上报会话失效链路）。
  ExecutionError _errorFromPreFlight(int status, String body) {
    if (status == 401) {
      _connection.reportAuthFailure();
    }
    var code = status == 401
        ? 'UNAUTHORIZED'
        : status == 429
            ? 'RATE_LIMITED'
            : 'DB_ERROR';
    var message = 'gateway query rejected (HTTP $status)';
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final err = decoded['error'];
      if (err is Map<String, dynamic>) {
        code = (err['code'] as String?) ?? code;
        message = (err['message'] as String?) ?? message;
      }
    } catch (_) {
      // 非 JSON 错误体——保留 HTTP 概要。
    }
    return ExecutionError(code: code, message: message);
  }

  /// 取消在途执行（DELETE /api/gw/executions/{id}；幂等 204）。取消后
  /// server 以 error(CANCELLED) 终态事件收流。best-effort：取消请求自身
  /// 失败不抛（流随后自然终态/裸断均有兜底）。
  Future<void> cancelExecution(String executionId) async {
    try {
      await _send('DELETE', '/api/gw/executions/$executionId');
    } catch (_) {}
  }

  // ── 内部 ──

  /// DbServer → 网关 camelCase 草稿体（test 请求体；register 在此之上补
  /// name/readOnly/charset/timezone）。SQLite 的路径在客户端约定于
  /// `DbServer.host`，wire 侧为专用 `filePath` 字段（其余族必须带
  /// host/port/username/password，服务端 validate_draft 校验）。
  @visibleForTesting
  Map<String, dynamic> draftBody(DbServer server) {
    final wireType = kGatewayWireDbTypes[server.type];
    if (wireType == null) {
      throw PortException(
        'UNSUPPORTED_DB_TYPE',
        '${server.type.name} is not gateway-backed yet (wire whitelist: '
        '${kGatewayWireDbTypes.values.join(', ')})',
      );
    }
    final isSqlite = server.type == DatabaseType.sqlite;
    return {
      'dbType': wireType,
      if (isSqlite) 'filePath': server.host else ...{
        'host': server.host,
        'port': server.port,
        'username': server.username ?? '',
        'password': server.password ?? '',
      },
      if (!isSqlite && server.database != null && server.database!.isNotEmpty)
        'defaultDatabase': server.database,
    };
  }

  /// 发送已认证请求。非 2xx 一律转 [PortException]（wire 错误形状
  /// `{"error":{"code","message"}}`；401 顺带上报 ServerConnection 触发既有
  /// 会话失效链路，与其余 *_api_service 同策略）。
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final baseUrl = _connection.serverUrl;
    if (baseUrl == null ||
        _connection.connectionState != ServerConnectionState.connected) {
      throw const PortException(
        'CONFIG',
        'not connected to a dbmaster server (gateway unavailable; the '
        'embedded server binary is a hard dependency in embedded mode)',
      );
    }
    final token = await _connection.getAccessToken();
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse('$baseUrl$path');
    final client = _httpClient ?? http.Client();
    final ownsClient = _httpClient == null;
    http.Response resp;
    try {
      resp = await switch (method) {
        'GET' => client.get(uri, headers: headers),
        'POST' => client.post(
          uri,
          headers: headers,
          body: body == null ? '' : jsonEncode(body),
        ),
        'DELETE' => client.delete(uri, headers: headers),
        _ => throw StateError('Unsupported method: $method'),
      }.timeout(requestTimeout);
    } on TimeoutException {
      throw PortException('TIMEOUT', 'gateway $method $path timed out');
    } on http.ClientException catch (e) {
      // 传输层失败（server 不可达）——消息不含 host/DNS 细节（§4.4 纪律）。
      throw PortException('CONNECTION_FAILED', 'gateway unreachable (${e.message})');
    } finally {
      if (ownsClient) client.close();
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (resp.statusCode == 401) {
        _connection.reportAuthFailure();
      }
      String code = 'DB_ERROR';
      var message = 'gateway $method $path failed (HTTP ${resp.statusCode})';
      try {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        final err = decoded['error'];
        if (err is Map<String, dynamic>) {
          code = (err['code'] as String?) ?? code;
          message = (err['message'] as String?) ?? message;
        }
      } catch (_) {
        // 非 JSON 错误体（如 axum JsonRejection 纯文本）——保留 HTTP 概要。
      }
      throw PortException(code, message);
    }
    return resp;
  }
}

/// 网关流式执行会话：chunks = SSE 块流；cancel = DELETE /executions/{id}
/// （幂等；server 以 error(CANCELLED) 终态收流）。仅取消订阅不触达服务端
/// ——执行会继续跑到终态（契约 §2.1「取消必须可达服务端」）。
class _GatewayExecutionSession implements ExecutionSession {
  final Stream<ExecutionChunk> _chunks;
  final String executionId;
  final GatewayBacking _gateway;
  bool _cancelSent = false;

  _GatewayExecutionSession({
    required Stream<ExecutionChunk> chunks,
    required this.executionId,
    required GatewayBacking gateway,
  }) : _chunks = chunks,
       _gateway = gateway;

  @override
  Stream<ExecutionChunk> get chunks => _chunks;

  @override
  Future<void> cancel() async {
    if (_cancelSent) return; // 幂等
    _cancelSent = true;
    await _gateway.cancelExecution(executionId);
  }
}
