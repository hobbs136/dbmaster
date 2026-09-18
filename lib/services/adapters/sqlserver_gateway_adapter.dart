//! T28 · SQL Server 网关壳 adapter（#31 T28 客户端半边，2026-08-19）。
//!
//! **形态**（c01_port_contract §6.3）：实现 `DatabaseAdapter` 接口、底层
//! 执行走 T27 网关 API（`POST /api/gw/connections/{id}/query` SSE 流式）
//! 的过渡壳——port（GatewayBacking）Tier 1/执行通道落地后，本壳的逻辑
//! 上移为 GatewayBacking，UI 零改动（铁律 4）。
//!
//! **取代**（FFI/sybdb 整体下线）：原 `sqlserver_adapter_native.dart`
//! （FreeTDS DB-Library FFI）删除——#30 SS-TIMEOUT-301 的根因层（dbsettime
//! 进程级全局超时在多连接下被覆盖 → 超时静默成功）随之消失。超时语义
//! 改由网关 `statement_timeout`（tokio 墙钟包执行）承载：壳把连接级
//! `extra['timeout']` 透传为 `timeoutMs`，超时以 SSE error 事件
//! （code=TIMEOUT）上抛，不再静默成功。
//!
//! **连接模型**：本地不再持有 TDS 连接——凭据经网关注册入 server vault
//! （`POST /api/gw/connections`，与 ConnectionProvider C10 镜像同一
//! `connection_server_id_map` 映射表），每次执行由 server 开专用 tiberius
//! 连接（T28 server 侧语义：取消/超时后 sys.dm_exec_requests 零残留）。
//! embedded（本地 server 子进程）与远程 server 两形态由 [ServerConnection]
//! 的 serverUrl + Bearer 吸收，本壳不区分。
//!
//! **行为边界（v1，相对 FFI 版的已知差异）**：
//! - 事务：网关无状态单语句，BEGIN/COMMIT 不能跨执行保持——不再
//!   `implements TransactionalAdapter`（UI 经 `is TransactionalAdapter`
//!   门控自动降级），误调用时 fail-loud 抛错而非假成功。
//! - 执行计划：`SET SHOWPLAN_XML` 是会话级开关，逐语句独立连接下无法
//!   生效——getExplainPlan 显式抛错（登记 T28 已知边界）。
//! - FreeTDS 专有 workaround（varmax CAST/dbnextrow gap 分页）随 FFI 层
//!   消失：tiberius 解码链无此类缺陷（T28 server 侧已真库验证）。
//! - 多语句：网关单语句约束（MULTI_STATEMENT 4xx）——编辑器多语句脚本
//!   走 executeSqlScript（GO 批分割逐条执行），与 FFI 版口径一致。
//!
//! **元数据/DDL 方法**：自 native 版逐行迁入（T-SQL 构造 + 行解析零
//! 改动），底层 `executeQuery` 自动走网关。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../database_abstract.dart';
import '../server_connection.dart';
import '../../models/database_models.dart';
import '../../models/sql_script_exception.dart'
    show SqlScriptExecutionException;
import '../../utils/app_logger.dart';
import '../../utils/sql_escape_utils.dart';
import '../../utils/sql_server_batch_splitter.dart';
import 'ai_adapter_mixin.dart';

/// 网关查询错误（SSE error 事件 / 4xx 前置校验失败）。`code` 对齐
/// c01 §4.4 稳定码集（TIMEOUT/CANCELLED/DB_ERROR/NOT_FOUND/…），
/// `engineCode` 透传 TDS 引擎原始错误号。
class SqlServerGatewayException implements Exception {
  final String code;
  final String message;
  final String? engineCode;

  const SqlServerGatewayException(this.code, this.message, {this.engineCode});

  @override
  String toString() {
    final eng = engineCode == null ? '' : ' (engine $engineCode)';
    return '[$code]$eng $message';
  }
}

/// SQL Server 适配器（网关壳实现：执行走 T27 网关 API）。
class SqlServerAdapter extends DatabaseAdapter
    with AiAdapterMixin, DisconnectAware
    implements
        SqlSchemaAdapter,
        DdlAdapter,
        SqlScriptAdapter,
        SchemaAwareAdapter,
        MultiSchemaObjectAdapter,
        // getCharsets/getCollations 已实现，补声明以支持 `is CharsetAdapter` 路由
        CharsetAdapter,
        // 进程列表/kill，支持服务层 `is ProcessListAdapter` 路由
        ProcessListAdapter,
        ReplicationAdapter,
        JsonAdapter {
  /// serverConnId 映射表 key（与 ConnectionProvider / DbGatewayService 同源
  /// 的本地 id → 网关注册 id 映射；三方共享同一 SharedPreferences key）。
  static const String _kServerIdMapKey = 'connection_server_id_map';

  /// 测试注入的 HTTP 客户端（null = 每请求新建）。
  @visibleForTesting
  http.Client? httpClient;

  String? _serverConnId;
  DatabaseConnection? _currentConnection;
  String? _currentSchema;

  /// 在途执行的取消句柄（disconnect / 显式取消用）。
  String? _inFlightExecutionId;

  SqlServerAdapter();

  @override
  bool get isConnected => _serverConnId != null;

  @override
  DatabaseType get databaseType => DatabaseType.sqlserver;

  @override
  DatabaseConnection? get currentConnection => _currentConnection;

  /// feature 039 D3：刷新连接 readOnly（运行时开关实时生效）。
  @override
  void updateReadOnly(bool value) {
    _currentConnection = _currentConnection?.copyWith(readOnly: value);
  }

  @override
  bool get supportsSchemaOperations => true;

  @override
  bool get supportsSchemaNamespace => true;

  @override
  String getDefaultBrowseQuery(String tableName, {int limit = 100}) {
    final escaped = tableName
        .split('.')
        .map(SqlEscapeUtils.escapeSqlServerIdentifier)
        .join('.');
    return 'SELECT TOP $limit * FROM $escaped;';
  }

  // ==========================================================================
  // 连接管理（网关：注册/复用 serverConnId，无本地 TDS 连接）
  // ==========================================================================

  @override
  Future<bool> connect(DatabaseConnection connection) async {
    _currentConnection = connection;
    final server = _requireServerSession();

    // 1) 已有镜像映射 → 验证注册仍存在（server 换库/重置后 id 可能失效）。
    //    映射复用信任注册时凭据（注册前已经草稿测试验证）。
    final mapped = await _lookupServerIdMapping(connection.id);
    if (mapped != null) {
      final known = await _registeredTypes(server);
      final mappedType = known[mapped];
      if (mappedType != null && mappedType == 'sqlserver') {
        _serverConnId = mapped;
        return true;
      }
      AppLogger.w(
        'SqlServerAdapter',
        mappedType == null
            ? 'mapped serverConnId $mapped not found on server, re-registering'
            : 'mapped serverConnId $mapped type mismatch '
                  '(registered=$mappedType, want sqlserver), re-registering',
      );
    }

    // 2) 凭据草稿测试（对齐 FFI connect 的「真连」语义——凭据错误时
    //    connect 返回 false，而非注册成功把失败推迟到首次查询）。
    final testResp = await _sendNoBody(
      'POST',
      '/api/gw/connections/test',
      body: _draftBody(connection),
    );
    final testBody = jsonDecode(testResp.body) as Map<String, dynamic>;
    if (testBody['ok'] != true) {
      AppLogger.w(
        'SqlServerAdapter',
        'gateway credential test failed: ${testBody['error']}',
      );
      return false;
    }

    // 3) 现场注册（凭据入 vault）+ 写回映射（删除连接的注销链路依赖它）。
    final registered = await _registerConnection(connection);
    await _rememberServerIdMapping(connection.id, registered);
    _serverConnId = registered;
    return true;
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
    _currentSchema = null;
  }

  @override
  Future<String?> testConnection(DatabaseConnection connection) async {
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
  // 事务（网关无状态单语句——能力降级为「类型不支持」，误调用 fail-loud）
  // ==========================================================================

  @override
  Future<void> beginTransaction() async {
    throw UnsupportedError(
      'SQL Server 网关模式暂不支持手动事务（server 每语句独立连接，'
      'BEGIN/COMMIT 无法跨执行保持；网关 v2 事务端点落地后恢复）',
    );
  }

  @override
  Future<void> commit() async {
    throw UnsupportedError('SQL Server 网关模式暂不支持手动事务');
  }

  @override
  Future<void> rollback() async {
    throw UnsupportedError('SQL Server 网关模式暂不支持手动事务');
  }

  // ==========================================================================
  // 查询执行（SSE 流式全量聚合）
  // ==========================================================================

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    // feature 039 只读守卫——query-tab SQL + sidebar/AI DDL 经此处汇聚。
    guardReadOnlyQuery(sql, operation: 'executeQuery');
    _assertConnected();

    // T29 — USE 拦截（与 mysql 壳同款）：网关每语句独立连接，USE 无法
    // 保持会话态；先发给网关验证库存在，成功后更新本地记录库。
    final useTarget = _parseUseStatement(sql);
    if (useTarget != null) {
      await _executeViaGateway(
        sql: sql,
        database: database ?? _currentConnection?.database,
        timeoutMs: null,
        executionId: _newExecutionId(),
        startTime: DateTime.now(),
      );
      _currentConnection = _currentConnection?.copyWith(database: useTarget);
      return QueryResult(columns: const [], rows: const [], affectedRows: 0);
    }

    final startTime = DateTime.now();
    final effectiveDb = database ?? _currentConnection?.database;
    // 超时来源与 FFI 版一致（extra['timeout'] 秒 → 网关 timeoutMs；缺省
    // 用 server 默认 gw_query_timeout_secs）。#30 语义：超时由 server
    // statement_timeout 强制，SSE error(TIMEOUT) 上抛，不静默成功。
    final timeoutSecs = _currentConnection?.extra?['timeout'];
    final timeoutMs = timeoutSecs is num ? (timeoutSecs * 1000).round() : null;

    final executionId = _newExecutionId();
    _inFlightExecutionId = executionId;

    try {
      return await _executeViaGateway(
        sql: sql,
        database: effectiveDb,
        timeoutMs: timeoutMs,
        executionId: executionId,
        startTime: startTime,
      );
    } finally {
      if (_inFlightExecutionId == executionId) {
        _inFlightExecutionId = null;
      }
    }
  }

  /// 解析 `USE <db>` 语句（SS 方言：`USE [db]` / `USE db`）。仅匹配整句
  /// 单 USE 形态，解析不出返回 null 走正常网关执行。
  static final RegExp _useRe = RegExp(
    r'^\s*USE\s+(?:\[([^\]]+)\]|([A-Za-z0-9_\$#@]+))\s*;?\s*$',
    caseSensitive: false,
  );

  String? _parseUseStatement(String sql) {
    final m = _useRe.firstMatch(sql);
    if (m == null) return null;
    return m.group(1) ?? m.group(2);
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
      // 行限 = server 上限（gw_query_max_rows，默认 10000）：元数据查询与
      // 编辑器 SELECT 的限行语义由 SQL 自身（TOP / UI 行限）控制，壳侧不
      // 额外收窄（FFI 版无行限，行为保持）。
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
      final lines =
          await response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
      return _parseSse(lines, startTime: startTime);
    } on SqlServerGatewayException catch (e) {
      // 传输/连接级失败 → 触发 onDisconnect（对齐 FFI 版 dbdead 语义；
      // SQL 错误（DB_ERROR 等）不撕连接）。
      if (e.code == 'CONNECTION_FAILED' || e.code == 'NOT_FOUND') {
        onDisconnect?.call();
      }
      rethrow;
    } on http.ClientException catch (e) {
      onDisconnect?.call();
      throw SqlServerGatewayException(
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
    bool sawComplete = false;
    int? serverElapsedMs;
    bool truncated = false;

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
          throw SqlServerGatewayException(
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
      throw const SqlServerGatewayException(
        'CONNECTION_FAILED',
        'gateway SSE stream ended without a complete event',
      );
    }
    if (truncated) {
      AppLogger.w(
        'SqlServerAdapter',
        'gateway row limit reached (rowLimit=10000) — results truncated',
      );
    }

    return QueryResult(
      columns: columns,
      rows: rows,
      affectedRows: affectedRows,
      executionTime:
          serverElapsedMs ??
          DateTime.now().difference(startTime).inMilliseconds,
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

  @override
  Future<QueryResult> getExplainPlan(String sql) async {
    // SET SHOWPLAN_XML 是会话级开关；网关逐语句独立连接下无法生效（T28
    // 已知边界，登记任务手册）。fail-loud 而非返回空计划。
    throw UnsupportedError(
      'SQL Server 网关模式暂不支持执行计划（SHOWPLAN 为会话级开关，'
      '与网关单语句独立连接模型不兼容）',
    );
  }

  // ==========================================================================
  // Schema 发现（自 FFI 版逐行迁入，T-SQL 与解析零改动）
  // ==========================================================================

  @override
  Future<List<String>> getSchemas({String? database}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final results = await executeQuery(
      "SELECT name FROM sys.schemas "
      "WHERE name NOT IN ('sys', 'INFORMATION_SCHEMA', 'db_owner', 'db_accessadmin', "
      "'db_securityadmin', 'db_ddladmin', 'db_backupoperator', 'db_datareader', "
      "'db_datawriter', 'db_denydatareader', 'db_denydatawriter') "
      "ORDER BY name",
    );
    return results.rows.map((row) => row['name'] as String).toList();
  }

  @override
  String? getCurrentSchema() => _currentSchema;

  @override
  Future<void> setSearchPath(List<String> schemas) async {
    if (!isConnected) throw Exception('未连接到数据库');
    if (schemas.isNotEmpty) {
      _currentSchema = schemas.first;
    }
  }

  @override
  Future<void> setSchema(String schemaName) async {
    await setSearchPath([schemaName]);
  }

  @override
  Future<List<String>> getDatabases() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('''
      SELECT name FROM sys.databases 
      WHERE state = 0 AND name NOT IN ('master', 'tempdb', 'model', 'msdb')
      ORDER BY name
    ''');
    return results.rows.map((row) => row['name'] as String).toList();
  }

  @override
  Future<void> useDatabase(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // 网关无本地连接可切换——记录目标库，后续执行经 query 的 database
    // 字段路由（server 每语句按 defaultDatabase/database 选库）。
    if (_currentConnection?.database?.toLowerCase() == dbName.toLowerCase()) {
      return;
    }
    if (_currentConnection != null) {
      _currentConnection = _currentConnection!.copyWith(database: dbName);
    }
  }

  @override
  Future<List<String>> getTables({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // schema-scoped overload — bare names filtered to one schema
    if (schemaName != null) {
      final scoped = await executeQuery('''
        SELECT TABLE_NAME
        FROM INFORMATION_SCHEMA.TABLES
        WHERE TABLE_TYPE = 'BASE TABLE'
          AND TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(schemaName)}
        ORDER BY TABLE_NAME
      ''');
      return scoped.rows.map((row) => row['TABLE_NAME'] as String).toList();
    }

    final results = await executeQuery('''
      SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS full_name
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_TYPE = 'BASE TABLE'
      ORDER BY TABLE_SCHEMA, TABLE_NAME
    ''');
    return results.rows.map((row) => row['full_name'] as String).toList();
  }

  @override
  Future<List<DbTableMetadata>> getTablesWithMetadata({
    String? database,
  }) async {
    final tableNames = await getTables();
    return tableNames.map((name) => DbTableMetadata(name: name)).toList();
  }

  @override
  Future<DbTableMetadata> getTableMetadata(String tableName) async {
    return DbTableMetadata(name: tableName);
  }

  @override
  Future<List<String>> getViews({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // schema-scoped overload — bare names filtered to one schema
    if (schemaName != null) {
      final scoped = await executeQuery('''
        SELECT TABLE_NAME
        FROM INFORMATION_SCHEMA.VIEWS
        WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(schemaName)}
        ORDER BY TABLE_NAME
      ''');
      return scoped.rows.map((row) => row['TABLE_NAME'] as String).toList();
    }

    final results = await executeQuery('''
      SELECT TABLE_SCHEMA + '.' + TABLE_NAME AS full_name
      FROM INFORMATION_SCHEMA.VIEWS
      ORDER BY TABLE_SCHEMA, TABLE_NAME
    ''');
    return results.rows.map((row) => row['full_name'] as String).toList();
  }

  @override
  Future<List<String>> getProcedures({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // schema-scoped overload — bare names filtered to one schema
    if (schemaName != null) {
      final scoped = await executeQuery('''
        SELECT name
        FROM sys.procedures
        WHERE is_ms_shipped = 0
          AND SCHEMA_NAME(schema_id) = ${SqlEscapeUtils.escapeString(schemaName)}
        ORDER BY name
      ''');
      return scoped.rows.map((row) => row['name'] as String).toList();
    }

    final results = await executeQuery('''
      SELECT SCHEMA_NAME(schema_id) + '.' + name AS full_name
      FROM sys.procedures
      WHERE is_ms_shipped = 0
      ORDER BY SCHEMA_NAME(schema_id), name
    ''');
    return results.rows.map((row) => row['full_name'] as String).toList();
  }

  /// SQL Server 函数查询 SQL（包含标量函数、表值函数、聚合函数、CLR 函数）
  static const String functionsSql = '''
    SELECT SCHEMA_NAME(schema_id) + '.' + name AS full_name
    FROM sys.objects
    WHERE type IN ('FN', 'IF', 'TF', 'AF', 'FS', 'FT') AND is_ms_shipped = 0
    ORDER BY SCHEMA_NAME(schema_id), name
  ''';

  @override
  Future<List<String>> getFunctions({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // schema-scoped overload — bare names filtered to one schema
    if (schemaName != null) {
      final scoped = await executeQuery('''
        SELECT name
        FROM sys.objects
        WHERE type IN ('FN', 'IF', 'TF', 'AF', 'FS', 'FT')
          AND is_ms_shipped = 0
          AND SCHEMA_NAME(schema_id) = ${SqlEscapeUtils.escapeString(schemaName)}
        ORDER BY name
      ''');
      return scoped.rows.map((row) => row['name'] as String).toList();
    }

    final results = await executeQuery(functionsSql);
    return results.rows.map((row) => row['full_name'] as String).toList();
  }

  @override
  Future<List<String>> getEvents() async {
    // SQL Server 没有 MySQL 风格的事件调度器，返回空列表
    return [];
  }

  @override
  Future<List<String>> getSequences() async {
    if (!isConnected) throw Exception('未连接到数据库');
    final results = await executeQuery('''
      SELECT SCHEMA_NAME(schema_id) + '.' + name AS full_name
      FROM sys.sequences
      WHERE is_ms_shipped = 0
      ORDER BY SCHEMA_NAME(schema_id), name
    ''');
    return results.rows.map((row) => row['full_name'] as String).toList();
  }

  @override
  Future<List<String>> getMaterializedViews() async {
    if (!isConnected) throw Exception('未连接到数据库');
    // SQL Server 无独立「物化视图」类型；以「索引视图」（带唯一聚集索引的视图）近似。
    final results = await executeQuery('''
      SELECT SCHEMA_NAME(v.schema_id) + '.' + v.name AS full_name
      FROM sys.views v
      WHERE EXISTS (
        SELECT 1 FROM sys.indexes i
        WHERE i.object_id = v.object_id AND i.type = 1 AND i.is_unique = 1
      )
      ORDER BY SCHEMA_NAME(v.schema_id), v.name
    ''');
    return results.rows.map((row) => row['full_name'] as String).toList();
  }

  @override
  Future<List<DbTrigger>> getTriggers() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('''
      SELECT 
        t.name,
        OBJECT_NAME(t.parent_id) AS table_name,
        CASE WHEN t.is_instead_of_trigger = 1 THEN 'INSTEAD OF' ELSE 'AFTER' END AS timing,
        CASE 
          WHEN t.is_insert = 1 AND t.is_update = 1 AND t.is_delete = 1 THEN 'INSERT, UPDATE, DELETE'
          WHEN t.is_insert = 1 AND t.is_update = 1 THEN 'INSERT, UPDATE'
          WHEN t.is_insert = 1 AND t.is_delete = 1 THEN 'INSERT, DELETE'
          WHEN t.is_update = 1 AND t.is_delete = 1 THEN 'UPDATE, DELETE'
          WHEN t.is_insert = 1 THEN 'INSERT'
          WHEN t.is_update = 1 THEN 'UPDATE'
          WHEN t.is_delete = 1 THEN 'DELETE'
          ELSE 'UNKNOWN'
        END AS event,
        m.definition AS statement
      FROM sys.triggers t
      LEFT JOIN sys.sql_modules m ON t.object_id = m.object_id
      WHERE t.is_ms_shipped = 0
      ORDER BY t.name
    ''');

    return results.rows
        .map(
          (row) => DbTrigger(
            name: row['name'] as String? ?? '',
            event: row['event'] as String? ?? '',
            table: row['table_name'] as String? ?? '',
            timing: row['timing'] as String? ?? '',
            statement: row['statement'] as String?,
          ),
        )
        .toList();
  }

  /// 格式化 SQL Server 列类型显示
  ///
  /// 对于 varchar(max)/nvarchar(max)/varbinary(max) 等大值类型，
  /// SQL Server 的 CHARACTER_MAXIMUM_LENGTH 返回 -1，应显示为 (max)。
  static String formatColumnType(String dataType, dynamic maxLength) {
    if (maxLength != null) {
      final len = maxLength is int
          ? maxLength
          : int.tryParse(maxLength.toString());
      if (len == -1) {
        return '$dataType(max)';
      }
      if (len != null) {
        return '$dataType($len)';
      }
    }
    return dataType;
  }

  @override
  Future<List<DbColumn>> getTableColumns(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // 解析 schema.table
    final parts = tableName.split('.');
    final schema = parts.length > 1 ? parts[0] : 'dbo';
    final table = parts.length > 1 ? parts[1] : parts[0];

    final results = await executeQuery('''
      SELECT 
        c.COLUMN_NAME,
        c.DATA_TYPE,
        c.CHARACTER_MAXIMUM_LENGTH,
        c.IS_NULLABLE,
        c.COLUMN_DEFAULT,
        CASE WHEN pk.COLUMN_NAME IS NOT NULL THEN 1 ELSE 0 END AS is_primary_key
      FROM INFORMATION_SCHEMA.COLUMNS c
      LEFT JOIN (
        SELECT ku.COLUMN_NAME, ku.TABLE_SCHEMA, ku.TABLE_NAME
        FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
        JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku 
          ON tc.CONSTRAINT_NAME = ku.CONSTRAINT_NAME
          AND tc.TABLE_SCHEMA = ku.TABLE_SCHEMA
          AND tc.TABLE_NAME = ku.TABLE_NAME
        WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
      ) pk ON c.COLUMN_NAME = pk.COLUMN_NAME 
        AND c.TABLE_SCHEMA = pk.TABLE_SCHEMA 
        AND c.TABLE_NAME = pk.TABLE_NAME
      WHERE c.TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(schema)}
        AND c.TABLE_NAME = ${SqlEscapeUtils.escapeString(table)}
      ORDER BY c.ORDINAL_POSITION
    ''');

    return results.rows.map((row) {
      final type = formatColumnType(
        row['DATA_TYPE'] as String,
        row['CHARACTER_MAXIMUM_LENGTH'],
      );

      return DbColumn(
        name: row['COLUMN_NAME'] as String,
        type: type,
        isPrimaryKey: (row['is_primary_key'] as int? ?? 0) == 1,
        isNullable: (row['IS_NULLABLE'] as String) == 'YES',
        defaultValue: row['COLUMN_DEFAULT']?.toString(),
      );
    }).toList();
  }

  @override
  Future<List<DbIndex>> getTableIndexes(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final parts = tableName.split('.');
    final schema = parts.length > 1 ? parts[0] : 'dbo';
    final table = parts.length > 1 ? parts[1] : parts[0];

    final results = await executeQuery('''
      SELECT 
        i.name AS index_name,
        c.name AS column_name,
        i.is_unique
      FROM sys.indexes i
      JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
      JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
      JOIN sys.tables t ON i.object_id = t.object_id
      JOIN sys.schemas s ON t.schema_id = s.schema_id
      WHERE s.name = ${SqlEscapeUtils.escapeString(schema)}
        AND t.name = ${SqlEscapeUtils.escapeString(table)}
        AND i.type > 0
      ORDER BY i.name, ic.key_ordinal
    ''');

    final indexMap = <String, List<String>>{};
    final uniqueMap = <String, bool>{};

    for (final row in results.rows) {
      final indexName = row['index_name'] as String? ?? '';
      final columnName = row['column_name'] as String? ?? '';
      final isUniqueValue = row['is_unique'];
      final isUnique = isUniqueValue is bool
          ? isUniqueValue
          : (isUniqueValue as int? ?? 0) == 1;

      indexMap.putIfAbsent(indexName, () => []);
      indexMap[indexName]!.add(columnName);
      uniqueMap[indexName] = isUnique;
    }

    return indexMap.entries
        .map(
          (entry) => DbIndex(
            name: entry.key,
            columns: entry.value,
            isUnique: uniqueMap[entry.key] ?? false,
          ),
        )
        .toList();
  }

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final parts = tableName.split('.');
    final schema = parts.length > 1 ? parts[0] : 'dbo';
    final table = parts.length > 1 ? parts[1] : parts[0];

    final results = await executeQuery('''
      SELECT 
        fk.name AS constraint_name,
        c1.name AS column_name,
        OBJECT_NAME(fk.referenced_object_id) AS referenced_table,
        c2.name AS referenced_column,
        fk.delete_referential_action_desc AS on_delete,
        fk.update_referential_action_desc AS on_update
      FROM sys.foreign_keys fk
      JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
      JOIN sys.columns c1 ON fkc.parent_object_id = c1.object_id AND fkc.parent_column_id = c1.column_id
      JOIN sys.columns c2 ON fkc.referenced_object_id = c2.object_id AND fkc.referenced_column_id = c2.column_id
      JOIN sys.tables t ON fk.parent_object_id = t.object_id
      JOIN sys.schemas s ON t.schema_id = s.schema_id
      WHERE s.name = ${SqlEscapeUtils.escapeString(schema)}
        AND t.name = ${SqlEscapeUtils.escapeString(table)}
    ''');

    return results.rows
        .map(
          (row) => ForeignKey(
            name: row['constraint_name']?.toString() ?? '',
            table: tableName,
            column: row['column_name']?.toString() ?? '',
            referencedTable: row['referenced_table']?.toString() ?? '',
            referencedColumn: row['referenced_column']?.toString() ?? '',
            onUpdate: row['on_update']?.toString(),
            onDelete: row['on_delete']?.toString(),
          ),
        )
        .toList();
  }

  @override
  Future<DbTable> getTableDetails(String tableName) async {
    final columns = await getTableColumns(tableName);
    final indexes = await getTableIndexes(tableName);

    return DbTable(name: tableName, columns: columns, indexes: indexes);
  }

  // ==========================================================================
  // 服务器信息
  // ==========================================================================

  @override
  Future<Map<String, dynamic>?> getServerVersion() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('SELECT @@VERSION AS version');
    if (results.rows.isEmpty) return null;

    return {'version': results.rows.first['version'], 'database': 'SQL Server'};
  }

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // 网关按 database 参数路由查询目标库（无本地连接上下文可切换）。
    final results = await executeQuery('''
        SELECT 
          name,
          collation_name,
          (SELECT COUNT(*) FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name != 'sys' AND t.is_ms_shipped = 0) AS table_count
        FROM sys.databases
        WHERE name = ${SqlEscapeUtils.escapeString(dbName)}
      ''', database: dbName);

    if (results.rows.isEmpty) return null;

    final row = results.rows.first;
    return {
      'name': row['name'],
      'collation': row['collation_name'],
      'tableCount': int.tryParse(row['table_count']?.toString() ?? '0') ?? 0,
    };
  }

  // ==========================================================================
  // DDL 操作
  // ==========================================================================

  @override
  Future<bool> createDatabase(
    String dbName, {
    Map<String, dynamic>? options,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final escapedName = SqlEscapeUtils.escapeSqlServerIdentifier(dbName);
      String sql = 'CREATE DATABASE $escapedName';
      if (options != null && options['collation'] != null) {
        sql += ' COLLATE ${options['collation']}';
      }
      await executeQuery(sql);
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '创建数据库失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropDatabase(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final escapedName = SqlEscapeUtils.escapeSqlServerIdentifier(dbName);
    try {
      // 网关逐语句独立连接：不存在「本连接绑定目标库」的 3702 场景，
      // 直接置 SINGLE_USER 回滚其它连接后 DROP（原 FFI 版 master 切换
      // 仅为此场景服务，网关模型下天然满足）。
      await executeQuery(
        'ALTER DATABASE $escapedName SET SINGLE_USER WITH ROLLBACK IMMEDIATE',
      );
      await executeQuery('DROP DATABASE $escapedName');
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '删除数据库失败', e);
      return false;
    }
  }

  @override
  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    Map<String, dynamic>? options,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final columnDefs = columns
          .map((col) {
            String def =
                '${SqlEscapeUtils.escapeSqlServerIdentifier(col.name)} ${col.type}';
            if (col.isPrimaryKey) def += ' PRIMARY KEY';
            if (!col.isNullable) def += ' NOT NULL';
            if (col.defaultValue != null) def += ' DEFAULT ${col.defaultValue}';
            return def;
          })
          .join(', ');

      final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
      final sql = 'CREATE TABLE $escapedTable ($columnDefs)';
      await executeQuery(sql);
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '创建表失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropTable(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
      await executeQuery('DROP TABLE $escapedTable');
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '删除表失败', e);
      return false;
    }
  }

  @override
  Future<bool> renameTable(String oldName, String newName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      // T063 — sp_rename parses its @objname/@newname params itself and
      // does NOT accept bracket-delimited qualified names ('[s1].[t1]' fails;
      // 's1.t1' works). Pass the raw names, single-quote-escaped only, so both
      // default-schema ('t1') and non-default ('s1.t1') resolve. newName stays
      // bare — sp_rename keeps the table in its existing schema.
      final safeOld = oldName.replaceAll("'", "''");
      final safeNew = newName.replaceAll("'", "''");
      await executeQuery("EXEC sp_rename '$safeOld', '$safeNew'");
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '重命名表失败', e);
      return false;
    }
  }

  @override
  Future<bool> truncateTable(
    String tableName, {
    TruncateOptions? options,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
      await executeQuery('TRUNCATE TABLE $escapedTable');
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '清空表失败', e);
      return false;
    }
  }

  // ==========================================================================
  // DML / 数据操作
  // ==========================================================================

  @override
  Future<QueryResult> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // tiberius 解码链无 FreeTDS varmax/dbdatlen 缺陷（T28 server 侧真库
    // 验证），直接 SELECT *（原 FFI 版的 CAST 列 workaround 随 FFI 下线）。
    final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
    if (cursorColumn != null && cursorValue != null) {
      final escapedColumn = SqlEscapeUtils.escapeSqlServerIdentifier(
        cursorColumn,
      );
      final cursorValueStr = cursorValue is String
          ? SqlEscapeUtils.escapeString(cursorValue)
          : cursorValue.toString();
      return await executeQuery(
        'SELECT * FROM $escapedTable WHERE $escapedColumn > $cursorValueStr ORDER BY $escapedColumn OFFSET 0 ROWS FETCH NEXT $limit ROWS ONLY',
      );
    }
    return await executeQuery(
      'SELECT * FROM $escapedTable ORDER BY (SELECT NULL) OFFSET $offset ROWS FETCH NEXT $limit ROWS ONLY',
    );
  }

  @override
  Future<int> getTableRowCount(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
    final results = await executeQuery(
      'SELECT COUNT(*) AS cnt FROM $escapedTable',
    );
    return int.parse(results.rows.first['cnt'].toString());
  }

  // ==========================================================================
  // 列操作
  // ==========================================================================

  @override
  Future<bool> addColumn(String tableName, DbColumn column) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
      final escapedCol = SqlEscapeUtils.escapeSqlServerIdentifier(column.name);
      String def = 'ALTER TABLE $escapedTable ADD $escapedCol ${column.type}';
      if (!column.isNullable) def += ' NOT NULL';
      if (column.defaultValue != null) def += ' DEFAULT ${column.defaultValue}';

      await executeQuery(def);
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '添加列失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropColumn(String tableName, String columnName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
      final escapedCol = SqlEscapeUtils.escapeSqlServerIdentifier(columnName);
      await executeQuery('ALTER TABLE $escapedTable DROP COLUMN $escapedCol');
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '删除列失败', e);
      return false;
    }
  }

  @override
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  ) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
      // A9：改名——oldColumnName 非空且与新名不同时，先 sp_rename（镜像 renameColumn）。
      if (oldColumnName.isNotEmpty && oldColumnName != newColumn.name) {
        final unescapedTable = SqlEscapeUtils.unescapeSqlServerIdentifier(
          tableName,
        );
        await executeQuery(
          "EXEC sp_rename '${unescapedTable.replaceAll("'", "''")}.${oldColumnName.replaceAll("'", "''")}', '${newColumn.name.replaceAll("'", "''")}', 'COLUMN'",
        );
      }
      // 类型/约束变更：ALTER COLUMN（仅当给出了类型）。
      if (newColumn.type.isNotEmpty) {
        final escapedCol = SqlEscapeUtils.escapeSqlServerIdentifier(
          newColumn.name,
        );
        String def =
            'ALTER TABLE $escapedTable ALTER COLUMN $escapedCol ${newColumn.type}';
        if (!newColumn.isNullable) def += ' NOT NULL';
        await executeQuery(def);
      }
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '修改列失败', e);
      return false;
    }
  }

  @override
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName,
  ) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final unescapedTable = SqlEscapeUtils.unescapeSqlServerIdentifier(
        tableName,
      );
      await executeQuery(
        "EXEC sp_rename '${unescapedTable.replaceAll("'", "''")}.${oldColumnName.replaceAll("'", "''")}', '${newColumnName.replaceAll("'", "''")}', 'COLUMN'",
      );
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '重命名列失败', e);
      return false;
    }
  }

  // ==========================================================================
  // 索引操作
  // ==========================================================================

  // T063 — escape a possibly schema-qualified SQL Server identifier by
  // splitting on '.' and bracket-escaping each segment (doubling embedded ']').
  // Bare "orders"→[orders] (== escapeSqlServerIdentifier, backward-compatible);
  // "sales.orders"→[sales].[orders]. Used by index DDL so non-default-schema
  // tables resolve in the ON clause.
  String _escapeSqlServerQualifiedIdentifier(String name) {
    return name.split('.').map(SqlEscapeUtils.escapeSqlServerIdentifier).join('.');
  }

  @override
  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      // T063 — split-escape qualified table (mirror dropIndex) so
      // CREATE INDEX on a non-default-schema table resolves. Backward-compatible.
      final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
      final escapedIndex = SqlEscapeUtils.escapeSqlServerIdentifier(indexName);
      final colNames = columns
          .map((c) => SqlEscapeUtils.escapeSqlServerIdentifier(c))
          .join(', ');
      final uniqueStr = unique ? 'UNIQUE ' : '';
      await executeQuery(
        'CREATE ${uniqueStr}INDEX $escapedIndex ON $escapedTable ($colNames)',
      );
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '创建索引失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropIndex(String tableName, String indexName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final escapedIndex = SqlEscapeUtils.escapeSqlServerIdentifier(indexName);
      // T063 — split-escape a possibly schema-qualified table for the
      // ON clause. Bare "orders"→[orders] (unchanged, backward-compatible),
      // "sales.orders"→[sales].[orders] so non-default-schema drops resolve.
      final escapedTable = _escapeSqlServerQualifiedIdentifier(tableName);
      await executeQuery('DROP INDEX $escapedIndex ON $escapedTable');
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '删除索引失败', e);
      return false;
    }
  }

  // ==========================================================================
  // 导出/脚本
  // ==========================================================================

  @override
  Future<String> exportDatabaseStructure(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final sb = StringBuffer();
    sb.writeln('-- Database: $dbName');
    sb.writeln('-- Generated by DBMaster SQL Server');
    sb.writeln('-- Date: ${DateTime.now().toIso8601String()}');
    sb.writeln();

    // 网关按 database 参数路由（无本地连接切换/恢复——原 useDatabase 往返
    // 在独立连接模型下无对应操作）。
    Future<QueryResult> scoped(String sql) => executeQuery(sql, database: dbName);

    try {
      // 获取所有表
      final tables = await getTables();

      for (final table in tables) {
        final parts = table.split('.');
        final schema = parts[0];
        final tableName = parts[1];

        // 获取表结构
        final details = await getTableDetails(table);
        final fks = await getForeignKeys(table);

        sb.writeln('-- Table: $table');
        sb.writeln(
          buildCreateTableExportSql(
            schema,
            tableName,
            details.columns,
            details.indexes,
            fks,
          ),
        );
        sb.writeln();
      }

      // 获取视图
      final views = await getViews();
      for (final view in views) {
        sb.writeln('-- View: $view');
        final viewDef = await scoped('''
          SELECT definition 
          FROM sys.sql_modules m
          JOIN sys.views v ON m.object_id = v.object_id
          JOIN sys.schemas s ON v.schema_id = s.schema_id
          WHERE s.name + '.' + v.name = ${SqlEscapeUtils.escapeString(view)}
        ''');
        if (viewDef.rows.isNotEmpty) {
          sb.writeln(viewDef.rows.first['definition'] ?? '');
          sb.writeln();
        }
      }

      // A7：存储过程 / 函数 / 触发器（sys.sql_modules definition）
      final modules = await scoped('''
        SELECT SCHEMA_NAME(o.schema_id) + '.' + o.name AS full_name,
               o.type AS otype,
               m.definition
        FROM sys.sql_modules m
        JOIN sys.objects o ON m.object_id = o.object_id
        WHERE o.is_ms_shipped = 0
          AND o.type IN ('P', 'FN', 'IF', 'TF', 'AF', 'FS', 'FT', 'TR')
        ORDER BY o.type, SCHEMA_NAME(o.schema_id), o.name
      ''');
      for (final row in modules.rows) {
        final t = row['otype']?.toString().trim(); // sys.objects.type 是 char(2)，需 trim
        final label = const {
          'P': 'Procedure',
          'FN': 'Function',
          'IF': 'Function',
          'TF': 'Function',
          'AF': 'Function',
          'FS': 'Function',
          'FT': 'Function',
          'TR': 'Trigger',
        }[t] ??
            'Object';
        sb.writeln('-- $label: ${row['full_name']}');
        sb.writeln(row['definition'] ?? '');
        sb.writeln('GO');
        sb.writeln();
      }
    } finally {
      // 无本地连接上下文需要恢复（database 路由是无状态参数）。
    }

    return sb.toString();
  }

  String buildCreateTableExportSql(
    String schema,
    String tableName,
    List<DbColumn> columns,
    List<DbIndex> indexes,
    List<ForeignKey> foreignKeys,
  ) {
    final buf = StringBuffer();
    buf.writeln('CREATE TABLE [$schema].[$tableName] (');

    final pkColumns = columns.where((c) => c.isPrimaryKey).toList();
    final hasCompositePk = pkColumns.length > 1;
    final filteredIndexes = indexes.where((i) => i.name != 'PRIMARY').toList();

    final parts = <String>[];
    for (final col in columns) {
      String def = '  [${col.name}] ${col.type}';
      if (col.isPrimaryKey && !hasCompositePk) def += ' PRIMARY KEY';
      if (!col.isNullable) def += ' NOT NULL';
      if (col.defaultValue != null) def += ' DEFAULT ${col.defaultValue}';
      parts.add(def);
    }
    if (hasCompositePk) {
      final pkColList = pkColumns.map((c) => '[${c.name}]').join(', ');
      parts.add('  PRIMARY KEY ($pkColList)');
    }
    for (final fk in foreignKeys) {
      parts.add(
        '  FOREIGN KEY ([${fk.column}]) REFERENCES [${fk.referencedTable}] ([${fk.referencedColumn}])',
      );
    }
    buf.writeln(parts.join(',\n'));
    buf.write(');');

    // SQL Server 不支持在 CREATE TABLE 列定义中内联 INDEX，使用独立的 CREATE INDEX 语句
    for (final idx in filteredIndexes) {
      final unique = idx.isUnique ? 'UNIQUE ' : '';
      final colList = idx.columns.map((c) => '[$c]').join(', ');
      buf.writeln();
      buf.write(
        'CREATE ${unique}INDEX [${idx.name}] ON [$schema].[$tableName] ($colList);',
      );
    }

    return buf.toString();
  }

  /// 执行 SQL 脚本（按 `GO` 批分隔符切分，见 [_splitSqlBatches]）
  ///
  /// U08：失败不再吞错返回 false，按批序号抛 [SqlScriptExecutionException]
  /// （GO 批无行级定位，行号为 null），携带失败前已执行生效的批数。
  @override
  Future<bool> executeSqlScript(String script) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final batches = _splitSqlBatches(script);
    var executed = 0;
    try {
      for (final batch in batches) {
        try {
          await executeQuery(batch);
        } catch (e) {
          throw SqlScriptExecutionException(
            statementIndex: executed,
            statementSql: batch,
            cause: e.toString(),
            committedCount: executed,
          );
        }
        executed++;
      }
      return true;
    } catch (e) {
      AppLogger.e('SqlServerAdapter', '执行脚本失败', e);
      rethrow;
    }
  }

  /// A8：按 `GO` 批分隔符切分 T-SQL 脚本（行首 GO，大小写不敏感，可选 `GO N` 重复）。
  /// GO 是批分隔符而非语句——存储过程/触发器体含 `;`，必须用 GO 分批。
  List<String> _splitSqlBatches(String script) => splitSqlServerBatches(script);

  // ==========================================================================
  // 字符集/排序规则
  // ==========================================================================

  @override
  Future<List<String>> getCharsets() async {
    // SQL Server 没有字符集概念，只有排序规则
    return [];
  }

  @override
  Future<List<Map<String, String>>> getCollations({String? charset}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('''
      SELECT name, description
      FROM sys.fn_helpcollations()
      ${charset != null ? "WHERE name LIKE '${charset.replaceAll("'", "''")}%'" : ''}
      ORDER BY name
    ''');

    return results.rows
        .map(
          (row) => {
            'name': row['name']?.toString() ?? '',
            'charset': row['description']?.toString() ?? '',
          },
        )
        .toList();
  }

  // SQL Server 进程列表（活跃会话），镜像 MySQL ProcessListAdapter 模式。
  // 读 sys.dm_exec_sessions（LEFT JOIN requests）；权限：读需 VIEW SERVER STATE，KILL 需
  // sysadmin/processadmin。无权限/失败时优雅返空（仿 getReplicationStatus 降级，不抛）。
  @override
  Future<List<ProcessInfo>> getProcessList() async {
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      final results = await executeQuery('''
        SELECT s.session_id AS sid,
               s.login_name AS login_name,
               s.host_name AS host_name,
               DB_NAME(s.database_id) AS db_name,
               COALESCE(r.command, '') AS cmd,
               COALESCE(r.total_elapsed_time, 0) AS elapsed,
               COALESCE(r.status, s.status) AS status,
               r.wait_type AS wait_type
        FROM sys.dm_exec_sessions s
        LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
        WHERE s.is_user_process = 1
        ORDER BY s.session_id
      ''');
      return results.rows
          .map(
            (row) => ProcessInfo(
              id: int.tryParse(row['sid']?.toString() ?? '') ?? 0,
              user: row['login_name']?.toString() ?? '',
              host: row['host_name']?.toString() ?? '',
              database: row['db_name']?.toString() ?? '',
              command: row['cmd']?.toString() ?? '',
              time: int.tryParse(row['elapsed']?.toString() ?? '') ?? 0,
              state: row['status']?.toString() ?? '',
              info: row['wait_type']?.toString(),
            ),
          )
          .toList();
    } catch (e) {
      AppLogger.w('SqlServerAdapter', 'getProcessList failed (权限?): $e');
      return [];
    }
  }

  // 注意：SQL Server 是 `KILL <spid>`，无 `CONNECTION` 关键字（与 MySQL 不同）。
  @override
  Future<bool> killProcess(int processId) async {
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      await executeQuery('KILL $processId');
      return true;
    } catch (e) {
      AppLogger.w('SqlServerAdapter', 'killProcess($processId) failed: $e');
      return false;
    }
  }

  // A2：SQL Server 复制 = AlwaysOn 可用性副本（HADR）。standalone 实例无 AG → 返 null（不抛）。
  // ReplicationStatus 是 MySQL 形状，这里 best-effort 映射 + raw 保留 DMV 全字段。
  @override
  Future<ReplicationStatus?> getReplicationStatus() async {
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      final results = await executeQuery('''
        SELECT ar.replica_server_name,
               rs.role_desc,
               rs.operational_state_desc,
               rs.connected_state_desc,
               rs.synchronization_health_desc
        FROM sys.dm_hadr_availability_replica_states rs
        JOIN sys.availability_replicas ar ON rs.replica_id = ar.replica_id
      ''');
      if (results.rows.isEmpty) return null;
      final row = results.rows.first;
      return ReplicationStatus(
        slaveIoRunning: row['connected_state_desc']?.toString(),
        slaveSqlRunning: row['synchronization_health_desc']?.toString(),
        masterLogFile: row['replica_server_name']?.toString(),
        raw: Map<String, dynamic>.from(row),
      );
    } catch (e) {
      AppLogger.w(
          'SqlServerAdapter', 'getReplicationStatus failed (权限/无AG?): $e');
      return null;
    }
  }

  // A3：JSON 列检测——nvarchar(max) 列中抽样 ISJSON()>0 视为 JSON 列。
  @override
  Future<List<String>> getJsonColumns(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      final dot = tableName.lastIndexOf('.');
      final schemaPart = dot >= 0 ? tableName.substring(0, dot) : null;
      final tblPart = dot >= 0 ? tableName.substring(dot + 1) : tableName;
      final unescapedTbl = SqlEscapeUtils.unescapeSqlServerIdentifier(tblPart);
      final escapedTbl = SqlEscapeUtils.escapeSqlServerIdentifier(unescapedTbl);
      final schemaFilter = schemaPart != null
          ? 'AND TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(SqlEscapeUtils.unescapeSqlServerIdentifier(schemaPart))}'
          : '';
      final cols = await executeQuery(
        'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS '
        "WHERE TABLE_NAME = ${SqlEscapeUtils.escapeString(unescapedTbl)} $schemaFilter "
        "AND DATA_TYPE = 'nvarchar' AND CHARACTER_MAXIMUM_LENGTH = -1",
      );
      final jsonCols = <String>[];
      for (final row in cols.rows) {
        final col = row['COLUMN_NAME'] as String;
        final escCol = SqlEscapeUtils.escapeSqlServerIdentifier(col);
        final check = await executeQuery(
          'SELECT TOP 1 ISJSON($escCol) AS j FROM $escapedTbl '
          'WHERE $escCol IS NOT NULL',
        );
        if (check.rows.isNotEmpty) {
          final j = check.rows.first['j'];
          if (j != null && j.toString() != '0') {
            jsonCols.add(col);
          }
        }
      }
      return jsonCols;
    } catch (e) {
      AppLogger.w('SqlServerAdapter', 'getJsonColumns failed: $e');
      return [];
    }
  }

  @override
  Future<bool> isJsonColumn(String tableName, String columnName) async {
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      final cols = await getJsonColumns(tableName);
      return cols.any((c) => c.toLowerCase() == columnName.toLowerCase());
    } catch (e) {
      return false;
    }
  }

  // ==========================================================================
  // 网关 plumbing（认证 / 注册 / 映射 / 错误形状）
  // ==========================================================================

  void _assertConnected() {
    if (!isConnected) throw Exception('未连接到数据库');
  }

  /// server 会话前置：网关模式硬依赖 dbmaster server（embedded 或远程；
  /// D6 拍板：embedded exe 随包）。
  ServerConnection _requireServerSession() {
    final server = ServerConnection();
    final baseUrl = server.serverUrl;
    if (baseUrl == null ||
        server.connectionState != ServerConnectionState.connected) {
      throw StateError(
        'SQL Server 网关模式需要已连接的 dbmaster server（未检测到会话；'
        'embedded 模式下请确认 dbmaster-server.exe 随包可用）',
      );
    }
    return server;
  }

  /// 连接草稿体（网关 wire：camelCase，sqlserver 走 host/port/凭据族）。
  /// server 侧 SSH 隧道对象（extra['ssh']）存在时原样透传。
  Map<String, dynamic> _draftBody(DatabaseConnection connection) => {
        'dbType': 'sqlserver',
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
  /// id 存在且类型一致才复用；同 localId 跨类型复用会把查询打去错误的
  /// 引擎，例如共享 SharedPreferences 镜像的测试机/换类型重建场景）。
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
      AppLogger.w('SqlServerAdapter', 'list gateway connections failed: $e');
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

  /// 4xx/5xx JSON 错误体 → [SqlServerGatewayException]（非 JSON 保 HTTP 概要）。
  SqlServerGatewayException _decodeErrResponse(int status, String text) {
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
    return SqlServerGatewayException(code, message);
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
      AppLogger.w('SqlServerAdapter', 'failed to save server-id map: $e');
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
