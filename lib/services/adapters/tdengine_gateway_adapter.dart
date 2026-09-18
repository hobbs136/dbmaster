//! T29 TDengine 批次 · TDengine 网关壳 adapter（/api/gw 形态）。
//!
//! **形态**：与 T29 各壳（`clickhouse_adapter.dart` 原地重写版 /
//! `mongodb_gateway_adapter.dart` / `redis_gateway_adapter.dart`）同构——
//! 实现 `DatabaseAdapter` 接口、底层执行走 T27 网关 API
//! （`POST /api/gw/connections/{id}/query` SSE 流式，**kind:"tdengine"**）。
//! server 侧执行腿 = taosAdapter REST（:6041）+ Basic auth
//! （stream_query.rs `run_stream_tdengine`，见 `tdengine_leg.rs`）。
//!
//! **沿革**：旧适配器（本文件前身）REST 直连 taosAdapter；本批收编到网关
//! ——SQL/元数据语义零漂移（同一 REST 通道，只是从客户端本地发起改为
//! server 侧发起）。旧 `tdengine_adapter.dart` 改 3 行 re-export shim。
//!
//! **行为边界**：
//! - 事务：**不支持**——TDengine 引擎层无事务；不 implements
//!   `TransactionalAdapter`（UI 门控自动隐藏），误调用 fail-loud 抛
//!   [UnsupportedError]（对齐 CH/B 批次口径，取代旧适配器的静默 no-op
//!   ——防假回滚）。
//! - useDatabase：**record-only**——TDengine REST 无会话态，库经 URL 路径
//!   路由；壳记录目标库，查询经 executeQuery 的 database 参数路由。
//! - columnTypes：**消费**——TDengine column_meta 自带原生类型名
//!   （TIMESTAMP/VARCHAR…），壳按其格式化 TIMESTAMP 列（RFC3339 → 本地
//!   "YYYY-MM-DD HH:MM:SS"，保旧适配器行为；CH 批次经 MySQL 口拿不到
//!   原生名的缺口在 TD 不存在）。
//! - 写响应：server 写通道（INSERT/DDL）affectedRows = 实际行数（DDL 0），
//!   无数据事件——QueryResult(columns:[], rows:[], affectedRows:n)。旧
//!   适配器受 REST 形状所限 INSERT 两行报 1（`rows` 键），此为修正。
//! - DESCRIBE 解析：TAG 标记读 **note 列**（实机钉定 7 列布局——旧代码
//!   读 index 4 判 TAG 是死代码，那是 encode 列）。
//! - TLS/useSSL：不透传（网关 draft/register body 无 TLS 字段，与各壳
//!   同边界）。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../database_abstract.dart';
import '../server_connection.dart';
import '../../models/database_models.dart';
import '../../models/tdengine_models.dart';
import '../../utils/app_logger.dart';
import '../../utils/sql_sanitizer.dart';
import 'ai_adapter_mixin.dart';

/// 网关查询错误（SSE error 事件 / 4xx 前置校验失败）。`code` 对齐
/// c01 §4.4 稳定码集（TIMEOUT/CANCELLED/DB_ERROR/CONNECTION_FAILED/…），
/// `engineCode` 透传 TDengine 原始错误号（如 9731 表不存在）。与各壳的
/// GatewayException 同形（各自独立类型，避免跨族耦合）。
class TdengineGatewayException implements Exception {
  final String code;
  final String message;
  final String? engineCode;

  const TdengineGatewayException(this.code, this.message, {this.engineCode});

  @override
  String toString() {
    final eng = engineCode == null ? '' : ' (engine $engineCode)';
    return '[$code]$eng $message';
  }
}

/// TDengine 适配器（网关壳实现：执行走 T27 网关 API，无本地驱动）。
///
/// 能力声明：SqlSchema/Ddl/SqlScript 与旧适配器一致；**TransactionalAdapter
/// 刻意不再 implements**（旧适配器是静默 no-op 假事务；TD 引擎层无事务，
/// fail-loud 对齐 CH/B 批次——UI 经 `is TransactionalAdapter` 门控自动隐藏）。
class TDengineAdapter extends DatabaseAdapter
    with AiAdapterMixin, DisconnectAware
    implements SqlSchemaAdapter, DdlAdapter, SqlScriptAdapter {
  /// serverConnId 映射表 key（与 ConnectionProvider / 其它网关壳同源的
  /// 本地 id → 网关注册 id 映射；共享同一 SharedPreferences key）。
  static const String _kServerIdMapKey = 'connection_server_id_map';

  static const String _tag = 'TDengineAdapter';

  /// 测试注入的 HTTP 客户端（null = 每请求新建）。
  @visibleForTesting
  http.Client? httpClient;

  TDengineAdapter({this.httpClient});

  String? _serverConnId;
  DatabaseConnection? _currentConnection;

  /// 在途执行的取消句柄（disconnect / 显式取消用）。
  String? _inFlightExecutionId;

  @override
  bool get isConnected => _serverConnId != null;

  @override
  DatabaseType get databaseType => DatabaseType.tdengine;

  @override
  DatabaseConnection? get currentConnection => _currentConnection;

  /// feature 039 D3：刷新连接 readOnly（运行时开关实时生效；server 侧
  /// 只读硬执行同源——注册时 readOnly 落 vault，执行腿拒写）。
  @override
  void updateReadOnly(bool value) {
    _currentConnection = _currentConnection?.copyWith(readOnly: value);
  }

  @override
  String getDefaultBrowseQuery(String tableName, {int limit = 100}) {
    final escaped = SqlSanitizer.identifier(tableName);
    return 'SELECT * FROM $escaped LIMIT $limit';
  }

  // ==========================================================================
  // 连接管理（网关：注册/复用 serverConnId，无本地连接）
  // ==========================================================================

  @override
  Future<bool> connect(DatabaseConnection connection) async {
    _currentConnection = connection;
    final server = _requireServerSession();

    // 1) 已有镜像映射 → 验证注册仍存在且类型一致（vault 根治① 的幂等
    //    注册语义下，同指纹连接复用 serverConnId——这里再按类型校验一道）。
    final mapped = await _lookupServerIdMapping(connection.id);
    if (mapped != null) {
      final known = await _registeredTypes(server);
      final mappedType = known[mapped];
      if (mappedType != null && mappedType == 'tdengine') {
        _serverConnId = mapped;
        return true;
      }
      AppLogger.w(
        _tag,
        mappedType == null
            ? 'mapped serverConnId $mapped not found on server, re-registering'
            : 'mapped serverConnId $mapped type mismatch '
                  '(registered=$mappedType, want tdengine), re-registering',
      );
    }

    // 2) 凭据草稿测试（对齐「真连」语义——凭据错误时 connect 返回 false，
    //    而非注册成功把失败推迟到首次查询）。
    final testResp = await _sendNoBody(
      'POST',
      '/api/gw/connections/test',
      body: _draftBody(connection),
    );
    final testBody = jsonDecode(testResp.body) as Map<String, dynamic>;
    if (testBody['ok'] != true) {
      AppLogger.w(_tag, 'gateway credential test failed: ${testBody['error']}');
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
  }

  @override
  Future<String?> testConnection(DatabaseConnection connection) async {
    // 网关 test 端点草稿不落库。返回 null 成功 / 错误串失败。
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
  // 事务（TDengine 引擎层无事务——误调用 fail-loud，防假回滚）
  // ==========================================================================

  @override
  bool get isInTransaction => false;

  /// DdlAdapter 能力标记（与旧适配器一致——DDL 面板可见；各方法按引擎
  /// 实情返回 false/抛错，如 addColumn 不支持）。
  @override
  bool get supportsSchemaOperations => true;

  @override
  Future<void> beginTransaction() async {
    throw UnsupportedError('TDengine 不支持事务（引擎层无事务语义）');
  }

  @override
  Future<void> commit() async {
    throw UnsupportedError('TDengine 不支持事务（引擎层无事务语义）');
  }

  @override
  Future<void> rollback() async {
    throw UnsupportedError('TDengine 不支持事务（引擎层无事务语义）');
  }

  // ==========================================================================
  // 查询执行（SSE 流式全量聚合，kind:"tdengine"）
  // ==========================================================================

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    // feature 039 只读守卫——query-tab SQL + sidebar/AI DDL 经此汇聚。
    guardReadOnlyQuery(sql, operation: 'executeQuery');
    _assertConnected();

    final startTime = DateTime.now();
    final effectiveDb = database ?? _currentConnection?.database;
    // 超时来源与其它壳一致（extra['timeout'] 秒 → 网关 timeoutMs；缺省用
    // server 默认 gw_query_timeout_secs）。超时由 server 侧墙钟强制。
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
    } on TdengineGatewayException catch (e) {
      // 传输/连接级失败 → 触发 onDisconnect（对齐其它壳语义；SQL 错误
      // （DB_ERROR 等）不撕连接）。
      if (e.code == 'CONNECTION_FAILED' || e.code == 'NOT_FOUND') {
        onDisconnect?.call();
      }
      rethrow;
    } on http.ClientException catch (e) {
      onDisconnect?.call();
      throw TdengineGatewayException(
        'CONNECTION_FAILED',
        'gateway unreachable (${e.message})',
      );
    } finally {
      if (_inFlightExecutionId == executionId) {
        _inFlightExecutionId = null;
      }
    }
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
      'kind': 'tdengine',
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

      // 前置校验失败（4xx JSON，流未开始）：{"error":{code,message}}。
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.stream.bytesToString();
        throw _decodeErrResponse(response.statusCode, text);
      }

      final lines = await response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .toList();
      return _parseSse(lines, startTime: startTime);
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// SSE 事件块解析（`event:`/`id:`/`data:` 行 + 空行分隔，契约 §4.2）。
  /// columnTypes **消费**：原生类型名驱动 TIMESTAMP 列格式化。
  QueryResult _parseSse(List<String> lines, {required DateTime startTime}) {
    List<String> columns = const [];
    List<String> columnTypes = const [];
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
          columnTypes = (chunk['columnTypes'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
        case 'rows':
          final batch = chunk['rows'] as List<dynamic>? ?? [];
          for (final raw in batch) {
            if (raw is List) {
              rows.add(_positionalRowToMap(raw, columns, columnTypes));
            }
          }
        case 'complete':
          sawComplete = true;
          truncated = chunk['truncated'] == true;
          affectedRows = (chunk['affectedRows'] as num?)?.toInt();
          serverElapsedMs = (chunk['elapsedMs'] as num?)?.toInt();
        case 'error':
          throw TdengineGatewayException(
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
    handleEvent(pendingEvent, pendingData);

    if (!sawComplete) {
      throw const TdengineGatewayException(
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

  /// 位置数组行 → 列名 map；TIMESTAMP 列值格式化为本地时间字符串（保旧
  /// 适配器行为——REST 返回 RFC3339 字符串或 epoch 整数两形态都处理）。
  Map<String, dynamic> _positionalRowToMap(
    List<dynamic> positional,
    List<String> columns,
    List<String> columnTypes,
  ) {
    final row = <String, dynamic>{};
    for (var i = 0; i < columns.length && i < positional.length; i++) {
      var value = positional[i];
      final ty = i < columnTypes.length ? columnTypes[i] : '';
      if ((ty == 'TIMESTAMP' || ty == '0') && value != null) {
        value = _formatTimestampValue(value);
      }
      row[columns[i]] = value;
    }
    return row;
  }

  /// TDengine 时间值 → 本地时间字符串（RFC3339 字符串 / 毫秒 / 微秒 epoch）。
  String _formatTimestampValue(dynamic value) {
    try {
      DateTime dt;
      if (value is int) {
        // 微秒时间戳通常大于 9999999999999（约 2286 年）。
        if (value.abs() > 9999999999999) {
          dt = DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
        } else {
          dt = DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
        }
      } else if (value is String) {
        dt = DateTime.parse(value);
      } else {
        return value.toString();
      }
      final local = dt.toLocal();
      String p2(int v) => v.toString().padLeft(2, '0');
      return '${local.year.toString().padLeft(4, '0')}-${p2(local.month)}-${p2(local.day)} '
          '${p2(local.hour)}:${p2(local.minute)}:${p2(local.second)}';
    } catch (_) {
      return value.toString();
    }
  }

  // ==========================================================================
  // 浏览（经 executeQuery 的 TDengine 方言，与旧适配器同 SQL）
  // ==========================================================================

  @override
  Future<List<String>> getDatabases() async {
    // 显式 database:'' 不带当前库路由（防 stale default 把目录查询打死）。
    final r = await executeQuery('SHOW DATABASES', database: '');
    final system = {'information_schema', 'performance_schema'};
    return r.rows
        .map((row) => row.values.firstOrNull?.toString() ?? '')
        .where((n) => n.isNotEmpty && !system.contains(n.toLowerCase()))
        .toList();
  }

  @override
  Future<void> useDatabase(String dbName) async {
    // record-only：TDengine REST 无会话态，库经 executeQuery 的 database
    // 参数路由（与旧适配器「URL 路径指定」同语义）。
    _currentConnection = _currentConnection?.copyWith(database: dbName);
  }

  @override
  Future<List<String>> getTables() async {
    final dbName = _currentConnection?.database;
    // 系统库是系统视图（SHOW TABLES）；用户库上树的是超级表（SHOW STABLES）
    // ——与旧适配器双路径同口径，server metadata 臂同源。
    final lower = dbName?.toLowerCase();
    final sql = (lower == 'information_schema' || lower == 'performance_schema')
        ? 'SHOW TABLES'
        : 'SHOW STABLES';
    final r = await executeQuery(sql);
    return r.rows
        .map((row) => row.values.firstOrNull?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toList();
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
  Future<Map<String, dynamic>?> getServerVersion() async {
    try {
      final r = await executeQuery('SELECT SERVER_VERSION()', database: '');
      if (r.rows.isNotEmpty) {
        final version = r.rows.first.values.firstOrNull?.toString();
        return {'version': version ?? 'unknown', 'database': 'TDengine'};
      }
      return {'version': 'unknown', 'database': 'TDengine'};
    } catch (_) {
      return {'version': 'unknown', 'database': 'TDengine'};
    }
  }

  @override
  Future<List<String>> getViews() async => [];

  @override
  Future<List<String>> getProcedures() async => [];

  @override
  Future<List<String>> getFunctions() async => [];

  @override
  Future<List<String>> getEvents() async => [];

  @override
  Future<List<DbTrigger>> getTriggers() async => [];

  @override
  Future<List<DbColumn>> getTableColumns(String tableName) async {
    try {
      final r = await executeQuery(
        'DESCRIBE ${SqlSanitizer.identifier(tableName)}',
      );
      // 实机钉定 7 列：field/type/length/note/encode/compress/level——TAG
      // 标记在 note（旧代码读 index 4 是 encode 列，死代码已修）。
      return r.rows.map((row) {
        final note = row['note']?.toString() ?? '';
        return DbColumn(
          name: row['field']?.toString() ?? '',
          type: row['type']?.toString() ?? '',
          isPrimaryKey: note == 'PRIMARY KEY',
          isNullable: note != 'NO',
          defaultValue: note.isNotEmpty && note != 'TAG' ? note : null,
          isTag: note == 'TAG',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<DbIndex>> getTableIndexes(String tableName) async {
    // TDengine 自动索引：主键（时间戳）+ 标签列（说明性信息，保旧语义）。
    try {
      final columns = await getTableColumns(tableName);
      final indexes = <DbIndex>[];
      final pkColumn = columns.firstWhere(
        (c) => c.isPrimaryKey,
        orElse: () => columns.first,
      );
      indexes.add(
        DbIndex(
          name: '${tableName}_pk',
          columns: [pkColumn.name],
          isUnique: true,
        ),
      );
      for (final col in columns.where((c) => c.isTag == true)) {
        indexes.add(
          DbIndex(
            name: '${tableName}_${col.name}_idx',
            columns: [col.name],
            isUnique: false,
          ),
        );
      }
      return indexes;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async => [];

  @override
  Future<DbTable> getTableDetails(String tableName) async {
    final columns = await getTableColumns(tableName);
    final indexes = await getTableIndexes(tableName);
    return DbTable(name: tableName, columns: columns, indexes: indexes);
  }

  @override
  Future<QueryResult> getExplainPlan(String sql) async {
    return QueryResult(
      columns: ['info'],
      rows: [
        {'info': 'TDengine 使用 EXPLAIN 命令查看执行计划'},
      ],
    );
  }

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async {
    try {
      final r = await executeQuery(
        'SHOW CREATE DATABASE ${SqlSanitizer.identifier(dbName)}',
        database: '',
      );
      return {'name': dbName, 'info': r.toString()};
    } catch (_) {
      return null;
    }
  }

  // ==========================================================================
  // 库/表 DDL（guardReadOnly 语义保留——server 侧只读硬执行双保险）
  // ==========================================================================

  @override
  Future<bool> createDatabase(
    String dbName, {
    Map<String, dynamic>? options,
  }) async {
    guardReadOnly(operation: 'createDatabase');
    try {
      await executeQuery(
        'CREATE DATABASE IF NOT EXISTS ${SqlSanitizer.identifier(dbName)}',
        database: '',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '创建数据库失败: $e');
      return false;
    }
  }

  @override
  Future<bool> dropDatabase(String dbName) async {
    guardReadOnly(operation: 'dropDatabase');
    try {
      await executeQuery(
        'DROP DATABASE IF EXISTS ${SqlSanitizer.identifier(dbName)}',
        database: '',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除数据库失败: $e');
      return false;
    }
  }

  @override
  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    Map<String, dynamic>? options,
  }) async {
    throw Exception('TDengine 使用超级表，请使用 createSuperTable 方法');
  }

  @override
  Future<bool> dropTable(String tableName) async {
    guardReadOnly(operation: 'dropTable');
    try {
      await executeQuery(
        'DROP TABLE IF EXISTS ${SqlSanitizer.identifier(tableName)}',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除表失败: $e');
      return false;
    }
  }

  @override
  Future<bool> renameTable(String oldName, String newName) async {
    guardReadOnly(operation: 'renameTable');
    // TDengine 3.x 不支持 RENAME TABLE——普通表/子表变通：建新表 + 复制 +
    // 删旧表；超级表直接拒（保旧语义）。
    try {
      final stables = await getSuperTables();
      final isStable = stables.any((s) => s.name == oldName);
      if (isStable) {
        AppLogger.d(_tag, '超级表不支持重命名: $oldName');
        return false;
      }
      await executeQuery(
        'CREATE TABLE ${SqlSanitizer.identifier(newName)} AS SELECT * FROM ${SqlSanitizer.identifier(oldName)}',
      );
      await executeQuery(
        'DROP TABLE IF EXISTS ${SqlSanitizer.identifier(oldName)}',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '重命名表失败: $e');
      return false;
    }
  }

  @override
  Future<bool> truncateTable(
    String tableName, {
    TruncateOptions? options,
  }) async {
    guardReadOnly(operation: 'truncateTable');
    // TDengine 不支持 TRUNCATE，使用 DELETE FROM 变通（保旧语义）。
    try {
      await executeQuery('DELETE FROM ${SqlSanitizer.identifier(tableName)}');
      return true;
    } catch (e) {
      AppLogger.d(_tag, '清空表失败: $e');
      return false;
    }
  }

  @override
  Future<QueryResult> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
  }) async {
    final escapedTable = SqlSanitizer.identifier(tableName);
    if (cursorColumn != null && cursorValue != null) {
      final escapedColumn = SqlSanitizer.identifier(cursorColumn);
      return executeQuery(
        'SELECT * FROM $escapedTable WHERE $escapedColumn > ${SqlSanitizer.value(cursorValue)} ORDER BY $escapedColumn LIMIT $limit',
      );
    }
    return executeQuery(
      'SELECT * FROM $escapedTable LIMIT $limit OFFSET $offset',
    );
  }

  @override
  Future<int> getTableRowCount(String tableName) async {
    // 别名避开保留字：TDengine 3.3.x 拒 `as count`（9728 语法错，实机钉定）。
    final result = await executeQuery(
      'SELECT COUNT(*) AS cnt FROM ${SqlSanitizer.identifier(tableName)}',
    );
    if (result.rows.isNotEmpty) {
      return int.tryParse(result.rows.first['cnt']?.toString() ?? '0') ?? 0;
    }
    return 0;
  }

  @override
  Future<bool> addColumn(String tableName, DbColumn column) async {
    // TDengine 3.x 不支持 ALTER TABLE ADD COLUMN（超级表结构固定）。
    AppLogger.d(_tag, 'TDengine 不支持添加列: $tableName.${column.name}');
    return false;
  }

  @override
  Future<bool> dropColumn(String tableName, String columnName) async {
    AppLogger.d(_tag, 'TDengine 不支持删除列: $tableName.$columnName');
    return false;
  }

  @override
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  ) async {
    AppLogger.d(_tag, 'TDengine 不支持修改列: $tableName.$oldColumnName');
    return false;
  }

  @override
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName,
  ) async {
    AppLogger.d(_tag, 'TDengine 不支持重命名列: $tableName.$oldColumnName');
    return false;
  }

  @override
  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
  }) async {
    // TDengine 自动为主键和标签创建索引，无需手动创建。
    AppLogger.d(_tag, 'TDengine 自动索引，无需手动创建: $tableName.$indexName');
    return false;
  }

  @override
  Future<bool> dropIndex(String tableName, String indexName) async {
    AppLogger.d(_tag, 'TDengine 不支持删除索引: $tableName.$indexName');
    return false;
  }

  @override
  Future<String> exportDatabaseStructure(String dbName) async {
    final sb = StringBuffer();
    sb.writeln('-- TDengine Database Export');
    sb.writeln('-- Database: $dbName');
    sb.writeln('-- Date: ${DateTime.now().toIso8601String()}');
    sb.writeln();

    try {
      final dbResult = await executeQuery(
        'SHOW CREATE DATABASE ${SqlSanitizer.identifier(dbName)}',
        database: '',
      );
      if (dbResult.rows.isNotEmpty) {
        final createDb = dbResult.rows.first.values.firstOrNull?.toString();
        if (createDb != null) {
          sb.writeln('$createDb;');
          sb.writeln();
        }
      }

      final stables = await getSuperTables();
      for (final stable in stables) {
        final detail = await getSuperTableDetail(stable.name);
        if (detail == null) continue;

        final columnDefs = detail.columns
            .map((c) => '${SqlSanitizer.identifier(c.name)} ${c.type}')
            .join(', ');
        final tagDefs = detail.tags
            .map((t) => '${SqlSanitizer.identifier(t.name)} ${t.type}')
            .join(', ');

        sb.writeln(
          'CREATE STABLE IF NOT EXISTS ${SqlSanitizer.identifier(detail.name)} (',
        );
        sb.writeln('  $columnDefs');
        sb.writeln(') TAGS (');
        sb.writeln('  $tagDefs');
        sb.writeln(');');
        sb.writeln();

        // 导出子表（标签值重建 USING 语句，上限 1000——保旧语义）。
        try {
          final subResult = await executeQuery(
            'SELECT TBNAME FROM ${SqlSanitizer.identifier(detail.name)} LIMIT 1000',
          );
          for (final row in subResult.rows) {
            final subName = row.values.firstOrNull?.toString();
            if (subName == null) continue;
            final tagResult = await executeQuery(
              'SELECT * FROM ${SqlSanitizer.identifier(detail.name)} WHERE TBNAME = ${SqlSanitizer.value(subName)} LIMIT 1',
            );
            if (tagResult.rows.isNotEmpty) {
              final tagRow = tagResult.rows.first;
              // 跳过数据列，取标签值（列名对齐 detail.tags）。
              final tagValues = detail.tags
                  .map((t) => SqlSanitizer.value(tagRow[t.name]))
                  .join(', ');
              sb.writeln(
                'CREATE TABLE IF NOT EXISTS ${SqlSanitizer.identifier(subName)} USING ${SqlSanitizer.identifier(detail.name)} TAGS ($tagValues);',
              );
            }
          }
          sb.writeln();
        } catch (e) {
          AppLogger.d(_tag, '导出子表失败: $e');
        }
      }
    } catch (e) {
      sb.writeln('-- Export error: $e');
    }

    sb.writeln();
    sb.writeln('-- 使用 taosdump 工具导出完整数据');
    return sb.toString();
  }

  @override
  Future<bool> executeSqlScript(String script) async {
    try {
      final lines = script
          .split('\n')
          .where(
            (l) =>
                l.trim().isNotEmpty &&
                !l.startsWith('--') &&
                !l.startsWith('#'),
          );
      for (final line in lines) {
        await executeQuery(line.trim());
      }
      return true;
    } catch (e) {
      AppLogger.d(_tag, '执行脚本失败: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getCharsets() async => ['UTF-8'];

  @override
  Future<List<Map<String, String>>> getCollations({String? charset}) async =>
      [];

  // ==========================================================================
  // TDengine 特有操作（超表/子表——消费面 database_service TDengine 节）
  // ==========================================================================

  /// 获取所有超级表（仅名称，避免 N+1 查询；详情按需 getSuperTableDetail）。
  Future<List<TdSuperTable>> getSuperTables() async {
    try {
      final r = await executeQuery('SHOW STABLES');
      return r.rows
          .map((row) {
            final name = row.values.firstOrNull?.toString() ?? '';
            return TdSuperTable(name: name, columns: [], tags: []);
          })
          .where((st) => st.name.isNotEmpty)
          .toList();
    } catch (e) {
      AppLogger.d(_tag, '获取超级表列表失败: $e');
      return [];
    }
  }

  /// 获取超级表详情（DESCRIBE——TAG 标记读 note 列，实机钉定）。
  Future<TdSuperTable?> getSuperTableDetail(String name) async {
    try {
      final r = await executeQuery(
        'DESCRIBE ${SqlSanitizer.identifier(name)}',
      );
      final columns = <TdColumn>[];
      final tags = <TdTag>[];
      for (final row in r.rows) {
        final field = row['field']?.toString() ?? '';
        final type = row['type']?.toString() ?? '';
        final note = row['note']?.toString() ?? '';
        if (note == 'TAG') {
          tags.add(TdTag(name: field, type: type));
        } else {
          columns.add(
            TdColumn(
              name: field,
              type: type,
              isPrimaryKey: note == 'PRIMARY KEY',
            ),
          );
        }
      }
      return TdSuperTable(name: name, columns: columns, tags: tags);
    } catch (e) {
      AppLogger.d(_tag, '获取超级表详情失败: $e');
      return null;
    }
  }

  /// 创建超级表。
  Future<bool> createSuperTable({
    required String name,
    required List<TdColumn> columns,
    required List<TdTag> tags,
    String? comment,
  }) async {
    guardReadOnly(operation: 'createSuperTable');
    try {
      String defWithLength(TdColumn c) =>
          '${SqlSanitizer.identifier(c.name)} ${c.type}'
          '${c.length != null && (c.type.contains('BINARY') || c.type.contains('NCHAR')) ? '(${c.length})' : ''}';
      String tagWithLength(TdTag t) =>
          '${SqlSanitizer.identifier(t.name)} ${t.type}'
          '${t.length != null && (t.type.contains('BINARY') || t.type.contains('NCHAR')) ? '(${t.length})' : ''}';
      final columnDefs = columns.map(defWithLength).join(', ');
      final tagDefs = tags.map(tagWithLength).join(', ');

      var sql =
          'CREATE STABLE IF NOT EXISTS ${SqlSanitizer.identifier(name)} ($columnDefs) TAGS ($tagDefs)';
      if (comment != null && comment.isNotEmpty) {
        sql += ' COMMENT ${SqlSanitizer.value(comment)}';
      }
      await executeQuery(sql);
      return true;
    } catch (e) {
      AppLogger.d(_tag, '创建超级表失败: $e');
      return false;
    }
  }

  /// 删除超级表（会级联删除所有子表）。
  Future<bool> dropSuperTable(String name) async {
    guardReadOnly(operation: 'dropSuperTable');
    try {
      await executeQuery(
        'DROP STABLE IF EXISTS ${SqlSanitizer.identifier(name)}',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除超级表失败: $e');
      return false;
    }
  }

  /// 创建子表。
  Future<bool> createSubTable({
    required String name,
    required String superTableName,
    required Map<String, dynamic> tagValues,
  }) async {
    guardReadOnly(operation: 'createSubTable');
    try {
      final tagList = tagValues.entries
          .map((e) {
            if (e.value is String) {
              return "'${e.value}'";
            }
            return e.value.toString();
          })
          .join(', ');
      await executeQuery(
        'CREATE TABLE ${SqlSanitizer.identifier(name)} USING ${SqlSanitizer.identifier(superTableName)} TAGS ($tagList)',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '创建子表失败: $e');
      return false;
    }
  }

  /// 删除子表。
  Future<bool> dropSubTable(String name) async {
    guardReadOnly(operation: 'dropSubTable');
    try {
      await executeQuery(
        'DROP TABLE IF EXISTS ${SqlSanitizer.identifier(name)}',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除子表失败: $e');
      return false;
    }
  }

  // ==========================================================================
  // 网关 plumbing（认证 / 注册 / 映射 / 错误形状——各壳同源）
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
        'TDengine 网关模式需要已连接的 dbmaster server（未检测到会话；'
        'embedded 模式下请确认 dbmaster-server.exe 随包可用）',
      );
    }
    return server;
  }

  /// 连接草稿体（网关 wire：camelCase）。TLS 两键走 extra；server 侧
  /// SSH 隧道对象原样透传。
  Map<String, dynamic> _draftBody(DatabaseConnection connection) {
    final tlsWire = gatewayTlsWire(connection.extra);
    return {
      'dbType': 'tdengine',
      'host': connection.host,
      'port': connection.port,
      'username': connection.username ?? '',
      'password': connection.password ?? '',
      if (connection.database != null && connection.database!.isNotEmpty)
        'defaultDatabase': connection.database,
      if (tlsWire.isNotEmpty) 'extra': tlsWire,
      'ssh': ?gatewaySshWire(connection),
    };
  }

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

  /// 网关已注册连接的 id → db_type 映射（connect 时验证映射有效性）。
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

  /// 4xx/5xx JSON 错误体 → [TdengineGatewayException]（非 JSON 保 HTTP 概要）。
  TdengineGatewayException _decodeErrResponse(int status, String text) {
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
    return TdengineGatewayException(code, message);
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
