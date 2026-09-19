//! T29 第三批 · ClickHouse 网关壳 adapter（/api/gw 形态）。
//!
//! **形态**：与 T28 `sqlserver_gateway_adapter.dart` / T29 首批
//! `mysql_gateway_adapter.dart` / 第二批 `postgresql_gateway_adapter.dart`
//! 同构——实现 `DatabaseAdapter` 接口、底层执行走 T27 网关 API
//! （`POST /api/gw/connections/{id}/query` SSE 流式）的壳。
//!
//! **沿革**：CH 无本地 Dart 驱动——本适配器自始就是网关代理（ADR-0003 S6
//! 「唯一真正瘦的库」），但此前走旧一代 `DbGatewayService`（`/api/db/*`）。
//! 本批（T29 第三批）收编到 `_gatewayBackedTypes` 统一走 `/api/gw`：
//! connect/test/浏览/执行全量改道，旧 `DbGatewayService` 消费面清零。
//! server 侧执行腿 = CH MySQL 兼容口（9004）+ COM_STMT_PREPARE
//! （stream_query.rs `Family::Clickhouse`，实机钉定）。
//!
//! **行为边界（沿用前两批口径 + CH 固有）**：
//! - 事务：**不支持**——CH 引擎层无事务；不 implements
//!   `TransactionalAdapter`（UI 门控自动隐藏），误调用 fail-loud 抛
//!   [UnsupportedError]（对齐前两批，防假回滚）。
//! - useDatabase：**record-only**——只记录目标库，查询经 executeQuery 的
//!   database 参数路由（server 每语句独立开池，无会话态）。
//! - columnTypes：server 经 MySQL 口拿到的是 MySQL wire 类型名
//!   （CHAR/INT UNSIGNED…），非 CH 原生名——本壳不消费（不收
//!   columnTypes）；原生名需 server 走 HTTP 8123 路线，后续增强。
//! - Date/DateTime/DateTime64：server chrono 臂解码为 SQL 惯例字符串
//!   （"YYYY-MM-DD" / "YYYY-MM-DD HH:MM:SS[.fff]"；DateTime64(9) 纳秒
//!   截断到微秒——MySQL 口精度上限，实机钉定于 gw_clickhouse e2e）。
//! - TLS/useSSL：不透传（网关 draft/register body 无 TLS 字段，与前两批
//!   同边界）。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../database_abstract.dart';
import '../server_connection.dart';
import '../../models/connection_failure.dart';
import '../../models/database_models.dart' show DbColumn, DbTable;
import '../../utils/app_logger.dart';
import '../../utils/sql_escape_utils.dart';
import 'ai_adapter_mixin.dart';

/// 网关查询错误（SSE error 事件 / 4xx 前置校验失败）。`code` 对齐
/// c01 §4.4 稳定码集（TIMEOUT/CANCELLED/DB_ERROR/NOT_FOUND/…），
/// `engineCode` 透传引擎原始错误号。与 `PostgreSqlGatewayException` /
/// `MySqlGatewayException` 同形（各自独立类型，避免跨族耦合）。
class ClickhouseGatewayException implements Exception {
  final String code;
  final String message;
  final String? engineCode;

  const ClickhouseGatewayException(this.code, this.message, {this.engineCode});

  @override
  String toString() {
    final eng = engineCode == null ? '' : ' (engine $engineCode)';
    return '[$code]$eng $message';
  }
}

/// ClickHouse 适配器（网关壳实现：执行走 T27 网关 API，无本地驱动）。
class ClickhouseAdapter extends DatabaseAdapter
    with AiAdapterMixin, DisconnectAware {
  /// serverConnId 映射表 key（与 ConnectionProvider / 其它网关壳同源的
  /// 本地 id → 网关注册 id 映射；共享同一 SharedPreferences key）。
  static const String _kServerIdMapKey = 'connection_server_id_map';

  static const String _tag = 'ClickhouseAdapter';

  /// 测试注入的 HTTP 客户端（null = 每请求新建）。
  @visibleForTesting
  http.Client? httpClient;

  String? _serverConnId;
  DatabaseConnection? _currentConnection;

  /// 在途执行的取消句柄（disconnect / 显式取消用）。
  String? _inFlightExecutionId;

  @override
  bool get isConnected => _serverConnId != null;

  @override
  DatabaseType get databaseType => DatabaseType.clickhouse;

  @override
  DatabaseConnection? get currentConnection => _currentConnection;

  /// feature 039 D3：刷新连接 readOnly（运行时开关实时生效）。
  @override
  void updateReadOnly(bool value) {
    _currentConnection = _currentConnection?.copyWith(readOnly: value);
  }

  // ==========================================================================
  // 连接管理（网关：注册/复用 serverConnId，无本地连接）
  // ==========================================================================

  @override
  Future<bool> connect(DatabaseConnection connection) async {
    _currentConnection = connection;
    final server = _requireServerSession();

    // 连接失败 UX 重构 T9a：失败不再吞掉（原草稿 test 失败 return false、
    // 途中网关异常裸抛），统一抛 AdapterConnectException 供上层分型展示；
    // envelope 解析走 T1 纯函数 gatewayEnvelopeFailure。target 契约 =
    // 「网关族 host:port」。与 mysql_gateway_adapter 同构。
    final target = '${connection.host}:${connection.port}';

    try {
      // 1) 已有镜像映射 → 验证注册仍存在且类型一致（server 换库/重置后 id
      //    可能失效；同 localId 跨类型复用会把查询打去错误的引擎）。
      final mapped = await _lookupServerIdMapping(connection.id);
      if (mapped != null) {
        final known = await _registeredTypes(server);
        final mappedType = known[mapped];
        if (mappedType != null && mappedType == 'clickhouse') {
          _serverConnId = mapped;
          return true;
        }
        AppLogger.w(
          _tag,
          mappedType == null
              ? 'mapped serverConnId $mapped not found on server, re-registering'
              : 'mapped serverConnId $mapped type mismatch '
                    '(registered=$mappedType, want clickhouse), re-registering',
        );
      }

      // 2) 凭据草稿测试（对齐「真连」语义——凭据错误时 connect 失败即抛，
      //    而非注册成功把失败推迟到首次查询）。
      final testResp = await _sendNoBody(
        'POST',
        '/api/gw/connections/test',
        body: _draftBody(connection),
      );
      final testBody = jsonDecode(testResp.body) as Map<String, dynamic>;
      if (testBody['ok'] != true) {
        AppLogger.w(_tag, 'gateway credential test failed: ${testBody['error']}');
        throw AdapterConnectException(
          _draftEnvelopeFailure(testBody, target: target),
          // 无异常对象的失败源：envelope error 原体作 cause 保链。
          testBody['error'] ?? testBody,
        );
      }

      // 3) 现场注册（凭据入 vault）+ 写回映射（删除连接的注销链路依赖它）。
      final registered = await _registerConnection(connection);
      await _rememberServerIdMapping(connection.id, registered);
      _serverConnId = registered;
      return true;
    } on ClickhouseGatewayException catch (e) {
      // connect 途中抛出的网关异常（草稿 test 被拒 / 注册失败等）→
      // 结构化包装，原始异常经 cause 保留。
      throw AdapterConnectException(
        gatewayEnvelopeFailure(
          code: e.code,
          engineCode: e.engineCode,
          message: e.message,
          target: target,
        ),
        e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    // best-effort 取消在途执行（网关幂等 204；无在途则 no-op）。
    final executionId = _inFlightExecutionId;
    if (executionId != null) {
      _inFlightExecutionId = null;
      unawaited(
        _sendNoBody('DELETE', '/api/gw/executions/$executionId').catchError(
          (_) => http.Response('', 500),
        ),
      );
    }
    _serverConnId = null;
  }

  @override
  Future<String?> testConnection(DatabaseConnection connection) async {
    // 网关 test 端点草稿不落库（取代旧 createConnectionRaw→db_test→
    // deleteConnection 临时连接三连）。返回 null 成功 / 错误串失败。
    try {
      _requireServerSession();
      final resp = await _sendNoBody(
        'POST',
        '/api/gw/connections/test',
        body: _draftBody(connection),
      );
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      if (decoded['ok'] == true) return null;
      return decoded['error']?.toString() ?? '连接失败';
    } catch (e) {
      return e.toString();
    }
  }

  // ==========================================================================
  // 事务（CH 引擎层无事务——误调用 fail-loud，防假回滚）
  // ==========================================================================

  @override
  bool get isInTransaction => false;

  @override
  Future<void> beginTransaction() async {
    throw UnsupportedError('ClickHouse 不支持事务（引擎层无事务语义）');
  }

  @override
  Future<void> commit() async {
    throw UnsupportedError('ClickHouse 不支持事务（引擎层无事务语义）');
  }

  @override
  Future<void> rollback() async {
    throw UnsupportedError('ClickHouse 不支持事务（引擎层无事务语义）');
  }

  // ==========================================================================
  // 查询执行（SSE 流式全量聚合）
  // ==========================================================================

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    // feature 039 只读守卫——query-tab SQL 经此处汇聚。
    guardReadOnlyQuery(sql, operation: 'executeQuery');
    _assertConnected();

    final startTime = DateTime.now();
    final effectiveDb = database ?? _currentConnection?.database;
    // 超时来源与其它壳一致（extra['timeout'] 秒 → 网关 timeoutMs；缺省
    // 用 server 默认 gw_query_timeout_secs）。超时由 server 侧墙钟强制，
    // SSE error(TIMEOUT) 上抛，不静默成功。
    final timeoutSecs = _currentConnection?.extra?['timeout'];
    final timeoutMs = timeoutSecs is num ? (timeoutSecs * 1000).round() : null;

    final executionId = _newExecutionId();
    _inFlightExecutionId = executionId;

    try {
      try {
        return await _executeViaGateway(
          sql: sql,
          database: effectiveDb,
          timeoutMs: timeoutMs,
          executionId: executionId,
          startTime: startTime,
        );
      } on ClickhouseGatewayException catch (e) {
        // T29 — stale 库自愈（与 mysql/pg 壳同款）：当前记录库被外部删除
        // 后，带 database 路由的每语句开池失败 → CONNECTION_FAILED。清掉
        // 本地记录库并无库重试一次（真·连接故障时重试同样失败，错误原样
        // 上抛，无静默吞错）。
        if (e.code == 'CONNECTION_FAILED' &&
            effectiveDb != null &&
            effectiveDb.isNotEmpty) {
          AppLogger.w(
            _tag,
            'query with database=$effectiveDb hit CONNECTION_FAILED; '
            'clearing stale db and retrying without database',
          );
          if (_currentConnection?.database == effectiveDb) {
            _clearRecordedDatabase();
          }
          return await _executeViaGateway(
            sql: sql,
            database: null,
            timeoutMs: timeoutMs,
            executionId: executionId,
            startTime: startTime,
          );
        }
        rethrow;
      }
    } finally {
      if (_inFlightExecutionId == executionId) {
        _inFlightExecutionId = null;
      }
    }
  }

  /// 清空记录库（`copyWith(database: null)` 的 `??` 语义无法置空，需显式
  /// 重建）。用于 stale 库自愈。
  void _clearRecordedDatabase() {
    final c = _currentConnection;
    if (c == null) return;
    _currentConnection = DatabaseConnection(
      id: c.id,
      name: c.name,
      type: c.type,
      host: c.host,
      port: c.port,
      username: c.username,
      password: c.password,
      connected: c.connected,
      connectedAt: c.connectedAt,
      readOnly: c.readOnly,
      extra: c.extra,
    );
  }

  Future<QueryResult> _executeViaGateway({
    required String sql,
    required String? database,
    required int? timeoutMs,
    required String executionId,
    required DateTime startTime,
  }) async {
    final server = _requireServerSession();
    final uri = Uri.parse(
      '${server.serverUrl}/api/gw/connections/$_serverConnId/query',
    );
    final token = await server.getAccessToken();

    final body = jsonEncode({
      'sql': sql,
      if (database != null && database.isNotEmpty) 'database': database,
      // 行限 = server 上限（gw_query_max_rows，默认 10000）：限行语义由
      // SQL 自身（LIMIT / UI 行限）控制，壳侧不额外收窄。
      'rowLimit': 10000,
      'timeoutMs': ?timeoutMs,
    });

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..headers['X-Execution-Id'] = executionId
      ..body = body;
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final response = await client.send(request);

      // 前置校验失败（4xx JSON，流未开始）：错误形状 {"error":{code,message}}。
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.stream.bytesToString();
        throw _decodeErrResponse(response.statusCode, text);
      }

      // SSE 流聚合：meta → rows* → complete | error。
      final lines = await response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      return _parseSse(lines, startTime: startTime);
    } on ClickhouseGatewayException catch (e) {
      // 传输/连接级失败 → 触发 onDisconnect（对齐其它壳语义；SQL 错误
      // （DB_ERROR 等）不撕连接）。
      if (e.code == 'CONNECTION_FAILED' || e.code == 'NOT_FOUND') {
        onDisconnect?.call();
      }
      rethrow;
    } on http.ClientException catch (e) {
      onDisconnect?.call();
      throw ClickhouseGatewayException(
        'CONNECTION_FAILED',
        'gateway unreachable (${e.message})',
      );
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// SSE 事件块解析（`event:`/`id:`/`data:` 行 + 空行分隔，契约 §4.2）。
  QueryResult _parseSse(List<String> lines, {required DateTime startTime}) {
    List<String> columns = const [];
    final rows = <Map<String, dynamic>>[];
    int? affectedRows;
    var sawComplete = false;
    int? serverElapsedMs;
    var truncated = false;

    String pendingEvent = '';
    String pendingData = '';

    void handleEvent(String event, String data) {
      if (data.isEmpty) return;
      final Map<String, dynamic> chunk;
      try {
        chunk = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      switch (event) {
        case 'meta':
          columns = (chunk['columns'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
          // columnTypes 不消费：server 经 MySQL 口上报的是 MySQL wire
          // 类型名（非 CH 原生名），见文件头「行为边界」。
        case 'rows':
          final batch = chunk['rows'] as List<dynamic>? ?? [];
          for (final raw in batch) {
            if (raw is List) {
              rows.add(_positionalRowToMap(raw, columns));
            }
          }
        case 'complete':
          sawComplete = true;
          truncated = chunk['truncated'] == true;
          affectedRows = (chunk['affectedRows'] as num?)?.toInt();
          serverElapsedMs = (chunk['elapsedMs'] as num?)?.toInt();
        case 'error':
          throw ClickhouseGatewayException(
            chunk['code']?.toString() ?? 'DB_ERROR',
            chunk['message']?.toString() ?? 'query failed',
            engineCode: chunk['engineCode']?.toString(),
          );
      }
    }

    for (final line in lines) {
      if (line.isEmpty) {
        handleEvent(pendingEvent, pendingData);
        pendingEvent = '';
        pendingData = '';
      } else if (line.startsWith('event:')) {
        pendingEvent = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        pendingData = line.substring(5).trim();
      }
      // `id:`（seq）不消费；keep-alive 注释行（`:…`）忽略。
    }
    // 流尾无空行收尾的残余事件（防御）。
    handleEvent(pendingEvent, pendingData);

    if (!sawComplete) {
      throw const ClickhouseGatewayException(
        'CONNECTION_FAILED',
        'gateway SSE stream ended without a complete event',
      );
    }
    if (truncated) {
      AppLogger.w(
        _tag,
        'gateway row limit reached (rowLimit=10000) — results truncated',
      );
    }

    return QueryResult(
      columns: columns,
      rows: rows,
      affectedRows: affectedRows,
      executionTime:
          serverElapsedMs ?? DateTime.now().difference(startTime).inMilliseconds,
    );
  }

  /// 位置数组行 → 列名 map（SSE rows chunk 是 `[[v,v],…]`，meta 给列序）。
  Map<String, dynamic> _positionalRowToMap(
    List<dynamic> positional,
    List<String> columns,
  ) {
    final row = <String, dynamic>{};
    for (var i = 0; i < columns.length && i < positional.length; i++) {
      row[columns[i]] = positional[i];
    }
    return row;
  }

  // ==========================================================================
  // 浏览（经 executeQuery 的 CH 方言）
  // ==========================================================================

  @override
  Future<List<String>> getDatabases() async {
    // 显式 database:'' 不带当前库路由（防 stale default 把目录查询打死）。
    final r = await executeQuery('SHOW DATABASES', database: '');
    return r.rows
        .map((row) => row.values.firstOrNull?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        // 与 server metadata.rs CH 分支同款滤噪：INFORMATION_SCHEMA 大小写
        // 双别名 + system_metadata（旧 /api/db listDatabases 端点的口径，
        // 改走 executeQuery 后由客户端侧保持）。
        .where((n) =>
            n.toLowerCase() != 'information_schema' && n != 'system_metadata')
        .toList();
  }

  @override
  Future<void> useDatabase(String dbName) async {
    // record-only：网关无状态单语句，无 USE 语义——只记录目标库，后续
    // 查询经 executeQuery 的 database 参数路由（与其它壳同口径）。
    _currentConnection = _currentConnection?.copyWith(database: dbName);
  }

  @override
  Future<List<String>> getTables() async {
    final r = await executeQuery('SHOW TABLES');
    return r.rows
        .map((row) => row.values.firstOrNull?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  @override
  Future<List<DbColumn>> getTableColumns(String tableName) async {
    // v1 边界（沿用旧代理形态）：列元数据不经 adapter（server 侧 describe
    // 端点已有 CH 方言，客户端浏览链路当前不消费 DbColumn）。
    return [];
  }

  @override
  Future<DbTable> getTableDetails(String tableName) async =>
      DbTable(name: tableName);

  @override
  Future<QueryResult> getExplainPlan(String sql) async =>
      QueryResult(columns: const [], rows: const []);

  @override
  Future<QueryResult> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
  }) async {
    final table = SqlEscapeUtils.escapeMySqlIdentifier(tableName);
    return executeQuery('SELECT * FROM $table LIMIT $limit');
  }

  @override
  Future<int> getTableRowCount(String tableName) async {
    final table = SqlEscapeUtils.escapeMySqlIdentifier(tableName);
    final r = await executeQuery('SELECT count() AS c FROM $table');
    if (r.rows.isNotEmpty) {
      final v = r.rows.first['c'];
      if (v is int) return v;
      if (v is num) return v.toInt();
      // CH count() 经 MySQL 口为 BIGINT UNSIGNED —— u64 臂已覆盖；防御
      // 文本形态（不同 server 版本）。
      if (v is String) return int.tryParse(v) ?? 0;
    }
    return 0;
  }

  @override
  Future<Map<String, dynamic>?> getServerVersion() async => {};

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async =>
      {};

  @override
  String getDefaultBrowseQuery(String tableName, {int limit = 100}) {
    final escaped = SqlEscapeUtils.escapeMySqlIdentifier(tableName);
    return 'SELECT * FROM $escaped LIMIT $limit';
  }

  // ── AI stubs（v1 边界沿用旧代理形态；gateway 不暴露 CH AI schema summary）──

  @override
  Future<String> getAiSchemaSummary({
    String? target,
    String? databaseName,
    String locale = 'en',
  }) async =>
      '';

  @override
  Future<AiExecutionResult> executeAiCommand(
    String command, {
    String locale = 'en',
  }) async =>
      AiExecutionResult(
        success: false,
        output: '',
        error: 'ClickHouse AI commands not supported via gateway',
      );

  @override
  SecurityCheckResult validateCommand(String command) =>
      SecurityCheckResult.ok;

  // ==========================================================================
  // 网关 plumbing（认证 / 注册 / 映射 / 错误形状）
  // ==========================================================================

  void _assertConnected() {
    if (!isConnected) throw Exception('未连接到数据库');
  }

  /// server 会话前置：网关模式硬依赖 dbmaster server（embedded 或远程）。
  ServerConnection _requireServerSession() {
    final server = ServerConnection();
    final baseUrl = server.serverUrl;
    if (baseUrl == null ||
        server.connectionState != ServerConnectionState.connected) {
      throw StateError(
        'ClickHouse 网关模式需要已连接的 dbmaster server（未检测到会话；'
        'embedded 模式下请确认 dbmaster-server.exe 随包可用）',
      );
    }
    return server;
  }

  /// 连接草稿体（网关 wire：camelCase）。注：draft/test body 无 TLS 字段
  /// （见文件头「行为边界」）。server 侧 SSH 隧道对象（extra['ssh']）
  /// 存在时原样透传。
  Map<String, dynamic> _draftBody(DatabaseConnection connection) => {
        'dbType': 'clickhouse',
        'host': connection.host,
        'port': connection.port,
        'username': connection.username ?? '',
        'password': connection.password ?? '',
        if (connection.database != null && connection.database!.isNotEmpty)
          'defaultDatabase': connection.database,
        'ssh': ?gatewaySshWire(connection),
      };

  /// 现场注册（凭据入 server vault），返回 serverConnId。
  Future<String> _registerConnection(DatabaseConnection connection) async {
    final resp = await _sendNoBody(
      'POST',
      '/api/gw/connections',
      body: {
        ..._draftBody(connection),
        'name': connection.name,
        'readOnly': connection.readOnly,
      },
    );
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final id = decoded['serverConnId'] as String?;
    if (id == null || id.isEmpty) {
      throw StateError('网关注册响应缺少 serverConnId');
    }
    return id;
  }

  /// 网关已注册连接的 id → db_type 映射（connect 时验证映射有效性——
  /// id 存在且类型一致才复用）。
  Future<Map<String, String>> _registeredTypes(ServerConnection server) async {
    try {
      final resp = await _sendNoBody('GET', '/api/gw/connections');
      final rows = jsonDecode(resp.body) as List<dynamic>;
      return {
        for (final row in rows.whereType<Map<String, dynamic>>())
          if ((row['id']?.toString() ?? '').isNotEmpty)
            row['id'].toString(): row['dbType']?.toString() ?? '',
      };
    } catch (e) {
      AppLogger.w(_tag, 'list gateway connections failed: $e');
      return const {};
    }
  }

  /// 已认证的网关请求（非 SSE 族：注册/列表/测试/取消）。
  Future<http.Response> _sendNoBody(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final server = _requireServerSession();
    final token = await server.getAccessToken();
    final uri = Uri.parse('${server.serverUrl}$path');
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final resp = await switch (method) {
        'GET' => client.get(uri, headers: headers),
        'POST' => client.post(
            uri,
            headers: headers,
            body: body == null ? '' : jsonEncode(body),
          ),
        'DELETE' => client.delete(uri, headers: headers),
        _ => throw StateError('Unsupported method: $method'),
      }.timeout(const Duration(seconds: 30));
      if (resp.statusCode == 401) {
        server.reportAuthFailure();
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw _decodeErrResponse(resp.statusCode, resp.body);
      }
      return resp;
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// 4xx/5xx JSON 错误体 → [ClickhouseGatewayException]（非 JSON 保 HTTP 概要）。
  ClickhouseGatewayException _decodeErrResponse(int status, String text) {
    var code = 'DB_ERROR';
    var message = 'gateway request failed (HTTP $status)';
    try {
      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final err = decoded['error'];
      if (err is Map<String, dynamic>) {
        code = (err['code'] as String?) ?? code;
        message = (err['message'] as String?) ?? message;
      }
    } catch (_) {
      // 非 JSON 错误体——保留 HTTP 概要。
    }
    return ClickhouseGatewayException(code, message);
  }

  /// 草稿 test envelope（`{ok:false, error:...}`）→ [ConnectionFailure]
  /// （连接失败 UX 重构 T9a，与 mysql_gateway_adapter 同构）。容错（任务书
  /// 允许自决项）：error 为 Map 时取 code/engineCode/message；为字符串时
  /// 整串作 message（server 草稿 test 端点凭据失败即此形状，无稳定码 →
  /// errorCode=''）；缺失/类型异常 → unknown 兜底。分型映射走 T1 纯函数
  /// gatewayEnvelopeFailure，不在 adapter 内散写 if-chain。T12c：顶层
  /// `error_code` 稳定码（snake_case 新键）优先于旧 `error.code`，缺省
  /// 回落既有解析。
  static ConnectionFailure _draftEnvelopeFailure(
    Map<String, dynamic> body, {
    required String? target,
  }) {
    final err = body['error'];
    String? code;
    String? engineCode;
    String message;
    if (err is Map<String, dynamic>) {
      code = err['code']?.toString();
      engineCode = err['engineCode']?.toString();
      message = err['message']?.toString() ?? err.toString();
    } else if (err is String && err.isNotEmpty) {
      message = err;
    } else {
      message = 'gateway credential test failed';
    }
    return gatewayEnvelopeFailure(
      code: body['error_code']?.toString() ?? code,
      engineCode: engineCode,
      message: message,
      target: target,
    );
  }

  /// v4 uuid（执行取消句柄预置；server 端校验 uuid 合法性）。
  String _newExecutionId() {
    final rng = Random.secure();
    String hex(int n) =>
        List.generate(n, (_) => rng.nextInt(16).toRadixString(16)).join();
    final variant = (rng.nextInt(4) + 8).toRadixString(16);
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
  }

  Future<void> _rememberServerIdMapping(String localId, String serverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kServerIdMapKey);
      final map = raw == null
          ? <String, String>{}
          : (jsonDecode(raw) as Map).cast<String, String>();
      map[localId] = serverId;
      await prefs.setString(_kServerIdMapKey, jsonEncode(map));
    } catch (e) {
      AppLogger.w(_tag, 'failed to save server-id map: $e');
    }
  }

  Future<String?> _lookupServerIdMapping(String localId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kServerIdMapKey);
      if (raw == null) return null;
      final map = (jsonDecode(raw) as Map).cast<String, String>();
      return map[localId];
    } catch (_) {
      return null;
    }
  }
}
