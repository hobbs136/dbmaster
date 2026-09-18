//! T29 第二批 · PostgreSQL 网关壳 adapter（#31 T29 客户端半边）。
//!
//! **形态**：与 T28 `sqlserver_gateway_adapter.dart` / T29 首批
//! `mysql_gateway_adapter.dart` 同构——实现 `DatabaseAdapter` 接口、
//! 底层执行走 T27 网关 API（`POST /api/gw/connections/{id}/query`
//! SSE 流式）的过渡壳；port（GatewayBacking）Tier 1/执行通道落地后，
//! 本壳逻辑上移为 GatewayBacking，UI 零改动（铁律 4）。
//!
//! **取代**：原 `postgresql_adapter.dart`（Dart `package:postgres`
//! 裸连接）。本地不再持有 PG 连接——凭据经网关注册入 server vault
//! （`POST /api/gw/connections`，与 ConnectionProvider C10 镜像同一
//! `connection_server_id_map` 映射表），每次执行由 server 侧
//! `open_pg_db` 按查询 db 参数开专用池（wire dbType = 'postgresql'）。
//! embedded（本地 server 子进程）与远程 server 两形态由
//! [ServerConnection] 的 serverUrl + Bearer 吸收，本壳不区分。
//!
//! **元数据/DDL 方法**：自裸连接版逐行迁入（SQL 构造 + 结果映射零改动），
//! 仅行解析处按网关元组（JSON 值格）做类型适配（bool 兼容 true/'t'、
//! int 兼容数字/文本）。
//!
//! **行为边界（v1，相对裸连接版的已知差异）**：
//! - 事务：**T29 临时下线**——网关无状态单语句，BEGIN/COMMIT 不能跨执行
//!   保持；不再 `implements TransactionalAdapter`（UI 经
//!   `is TransactionalAdapter` 门控自动降级），beginTransaction/commit/
//!   rollback 误调用时 fail-loud 抛 [UnsupportedError]。恢复路径：旧
//!   `/api/db/:conn_id/txn/*` pinned session 或未来 `/api/gw` pinned
//!   session 端点。
//! - `SET search_path` 不持久：**record-only**——setSearchPath/setSchema
//!   只更新本地 `_currentSchema`（供元数据 SQL 内插），不发 SET；网关
//!   每语句独立连接，会话级 SET 不跨语句（与 MySQL 族 SET SESSION 同类
//!   边界）。无 schema 前缀的裸表名按 server 默认 search_path 解析。
//! - useDatabase：**record-only**——PG 无 USE 语句，旧版靠 close+reopen
//!   换库；网关模型下只记录目标库，查询经 executeQuery 的 database 参数
//!   路由（server `open_pg_db` 按 db 开池）。`isSwitchingDatabase` 守卫
//!   随之不再需要（不再有「主动关旧连接」窗口）。
//! - TLS/useSSL：**当前不生效**——server 侧 `open_pg`/`open_pg_db`
//!   （automation `db_handler.rs`）无 TLS 选项，`PgConnectOptions::new()`
//!   按 sqlx 默认 ssl-mode 拨号；连接 `extra['useSSL']` 不透传
//!   （register/draft body 亦无 TLS 字段）。登记为已知边界，不阻塞。
//! - TLS 之外的网络瞬态：旧版 createDatabase 的「Connection is closing
//!   down 竞态 → 侧连接核验库存在」链路随裸连接下线——网关每语句独立
//!   池，不存在该竞态，失败即 false。
//! - dropDatabase：旧版的「连维护库的侧连接」改为网关 database 路由
//!   （terminate backends + DROP 语句路由到 postgres/template1）；drop
//!   当前记录库后清本地记录（后续查询回落 server 注册的默认库）。
//! - JSON 列类型检测：旧版靠驱动结果集列 typeOid（114/3802）填
//!   `QueryResult.columnTypes`；网关 SSE meta 的 columnTypes wire
//!   扩展（server TypeInfo::name()，PG 路径已带）恢复该通道——
//!   只收 json/jsonb 列。
//! - 值解码：server `decode_cell_pg` 产出 text/int/float/bool/JSON/
//!   NUMERIC 字符串 + 日期时间族（DATE/TIME/TIMESTAMP/TIMESTAMPTZ，
//!   SQL 惯例空格分隔字符串；TIMESTAMPTZ 按 UTC 墙钟渲染——服务端无
//!   客户端时区概念）+ uuid 字符串（2026-08-27 网关日期解码修复）；
//!   bytea/数组等其余类型仍归一为 null（server 侧已知边界）；元数据
//!   查询受影响列均为文本/数字/bool。
//! - 多语句：网关单语句约束（MULTI_STATEMENT 4xx）——编辑器多语句脚本
//!   走 executeSqlScript（SQLParserService.split 逐条执行），与裸连接版
//!   口径一致。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../database_abstract.dart';
import '../server_connection.dart';
import '../schema_diff/table_dependency_sorter.dart';
import '../sql_parser_service.dart';
import '../../models/database_models.dart';
import '../../models/sql_script_exception.dart'
    show SqlScriptExecutionException;
import '../../utils/app_logger.dart';
import '../../utils/sql_escape_utils.dart';
import 'ai_adapter_mixin.dart';

/// 网关查询错误（SSE error 事件 / 4xx 前置校验失败）。`code` 对齐
/// c01 §4.4 稳定码集（TIMEOUT/CANCELLED/DB_ERROR/NOT_FOUND/…），
/// `engineCode` 透传引擎原始错误号。与 `MySqlGatewayException` /
/// `SqlServerGatewayException` 同形（各自独立类型，避免跨族耦合）。
class PostgreSqlGatewayException implements Exception {
  final String code;
  final String message;
  final String? engineCode;

  const PostgreSqlGatewayException(this.code, this.message, {this.engineCode});

  @override
  String toString() {
    final eng = engineCode == null ? '' : ' (engine $engineCode)';
    return '[$code]$eng $message';
  }
}

/// PostgreSQL 适配器（网关壳实现：执行走 T27 网关 API）。
class PostgreSQLAdapter extends DatabaseAdapter
    with AiAdapterMixin, DisconnectAware
    implements
        SqlSchemaAdapter,
        DdlAdapter,
        SqlScriptAdapter,
        SchemaAwareAdapter,
        MultiSchemaObjectAdapter,
        ExtensionAdapter,
        JsonAdapter {
  /// serverConnId 映射表 key（与 ConnectionProvider / DbGatewayService 同源
  /// 的本地 id → 网关注册 id 映射；三方共享同一 SharedPreferences key）。
  static const String _kServerIdMapKey = 'connection_server_id_map';

  static const String _tag = 'PostgreSQLAdapter';

  /// 测试注入的 HTTP 客户端（null = 每请求新建）。
  @visibleForTesting
  http.Client? httpClient;

  String? _serverConnId;
  DatabaseConnection? _currentConnection;
  String? _currentSchema;

  /// 在途执行的取消句柄（disconnect / 显式取消用）。
  String? _inFlightExecutionId;

  PostgreSQLAdapter();

  // 覆盖基类 killProcess（默认返回 false）以支持进程终止；
  // 不正式 implements ProcessListAdapter（getProcessList 由 builder 直接查
  // pg_stat_activity）——与裸连接版口径一致。

  @override
  bool get isConnected => _serverConnId != null;

  @override
  DatabaseType get databaseType => DatabaseType.postgresql;

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
    // 复用共享限定标识符转义（原先内联 split 与 DDL 路径不一致）
    final escaped = SqlEscapeUtils.escapePgQualifiedIdentifier(tableName);
    return 'SELECT * FROM $escaped LIMIT $limit;';
  }

  /// 返回安全转义后的当前 schema 名称（单引号已转义），可直接用于 SQL 内插。
  String get _currentSchemaSafe =>
      (_currentSchema ?? 'public').replaceAll("'", "''");

  @override
  String? getCurrentSchema() => _currentSchema;

  /// 转义 PostgreSQL 标识符（表名、列名等），防止 SQL 注入
  String _escapeIdentifier(String name) =>
      SqlEscapeUtils.escapePgIdentifier(name);

  /// 转义可能带 schema 前缀的限定表名（`schema.table`）。
  /// `_escapeIdentifier('public.users')` 会得到 `"public.users"`（名字含点的单标识符），
  /// 无法定位到目标 schema；DDL 表名位置必须用本方法拆分逐段转义。
  String _escapeQualifiedIdentifier(String name) =>
      SqlEscapeUtils.escapePgQualifiedIdentifier(name);

  /// 转义 PostgreSQL 字符串值
  String _escapeValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is num) return value.toString();
    if (value is bool) return value ? 'TRUE' : 'FALSE';
    String str = value.toString();
    str = str.replaceAll('\\', '\\\\');
    str = str.replaceAll("'", "''");
    return "'$str'";
  }

  /// 拆分可能带 schema 前缀的表名（`schema.table`）。
  /// `public.users` → `('public', 'users')`；`users` → `(null, 'users')`。
  // 侧栏 _loadTableSchema 传入 schema 限定名（如 'public.users'），
  /// 而 information_schema 的 table_name 仅是表名，故需拆分。
  static (String?, String) splitSchemaTable(String name) {
    final dot = name.indexOf('.');
    if (dot <= 0 || dot >= name.length - 1) return (null, name);
    return (name.substring(0, dot), name.substring(dot + 1));
  }

  /// 解析表名为（已转义的 schema, 纯表名），供 information_schema 查询使用。
  ({String schema, String table}) _resolveSchemaTable(String tableName) {
    final (parsedSchema, pureTable) = splitSchemaTable(tableName);
    final schema = (parsedSchema ?? _currentSchema ?? 'public').replaceAll(
      "'",
      "''",
    );
    return (schema: schema, table: pureTable);
  }

  /// 网关布尔格解析（server decode_cell_pg：bool → JSON true/false；
  /// 防御性兼容文本 't'/'true'/'1'）。
  static bool _truthy(dynamic value) {
    if (value is bool) return value;
    final s = value?.toString().toLowerCase();
    return s == 't' || s == 'true' || s == '1';
  }

  // ==========================================================================
  // 连接管理（网关：注册/复用 serverConnId，无本地 PG 连接）
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
      if (mappedType != null && mappedType == 'postgresql') {
        _serverConnId = mapped;
        _currentSchema = 'public';
        return true;
      }
      AppLogger.w(
        _tag,
        mappedType == null
            ? 'mapped serverConnId $mapped not found on server, re-registering'
            : 'mapped serverConnId $mapped type mismatch '
                  '(registered=$mappedType, want postgresql), re-registering',
      );
    }

    // 2) 凭据草稿测试（对齐裸连接 connect 的「真连」语义——凭据错误时
    //    connect 返回 false，而非注册成功把失败推迟到首次查询）。
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
    _currentSchema = 'public';
    return true;
  }

  @override
  Future<void> disconnect() async {
    // best-effort 取消在途执行（网关幂等 204；无在途则 no-op）。
    final executionId = _inFlightExecutionId;
    if (executionId != null) {
      _inFlightExecutionId = null;
      unawaited(
        _sendNoBody(
          'DELETE',
          '/api/gw/executions/$executionId',
        ).catchError((_) => http.Response('', 500)),
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
  // 事务（T29 临时下线——网关无状态单语句，误调用 fail-loud）
  // ==========================================================================

  @override
  bool get isInTransaction => false;

  @override
  Future<void> beginTransaction() async {
    throw UnsupportedError(
      'PostgreSQL 网关模式暂不支持手动事务（T29 临时下线：server 每语句独立连接，'
      'BEGIN/COMMIT 无法跨执行保持；恢复路径：旧 /api/db/:conn_id/txn/* '
      'pinned session 或未来 /api/gw pinned session 端点）',
    );
  }

  @override
  Future<void> commit() async {
    throw UnsupportedError('PostgreSQL 网关模式暂不支持手动事务（T29 临时下线）');
  }

  @override
  Future<void> rollback() async {
    throw UnsupportedError('PostgreSQL 网关模式暂不支持手动事务（T29 临时下线）');
  }

  // ==========================================================================
  // 查询执行（SSE 流式全量聚合）
  // ==========================================================================

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    // feature 039 只读守卫——query-tab SQL + sidebar/AI DDL 经此处汇聚。
    guardReadOnlyQuery(sql, operation: 'executeQuery');
    _assertConnected();

    final startTime = DateTime.now();
    final effectiveDb = database ?? _currentConnection?.database;
    // 超时来源与裸连接版一致（extra['timeout'] 秒 → 网关 timeoutMs；缺省
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
      } on PostgreSqlGatewayException catch (e) {
        // T29 — stale 库自愈（与 mysql 壳同款）：当前记录库被 drop（或外部
        // 删除）后，带 database 路由的每语句开池会 3D000 → CONNECTION_FAILED。
        // 裸连接时代连接存活仅失库上下文；这里清掉本地记录库并无库重试一次
        // （server 回落注册的默认库 / postgres 维护库；真·连接故障时重试
        // 同样失败，错误原样上抛，无静默吞错）。
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
  /// 重建）。用于 dropDatabase 当前库 / stale 库自愈两处。
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
      // 行限 = server 上限（gw_query_max_rows，默认 10000）：元数据查询与
      // 编辑器 SELECT 的限行语义由 SQL 自身（LIMIT / UI 行限）控制，壳侧
      // 不额外收窄（裸连接版无行限，行为保持）。
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
    } on PostgreSqlGatewayException catch (e) {
      // 传输/连接级失败 → 触发 onDisconnect（对齐裸连接版 onClose 语义；
      // SQL 错误（DB_ERROR 等）不撕连接）。
      if (e.code == 'CONNECTION_FAILED' || e.code == 'NOT_FOUND') {
        onDisconnect?.call();
      }
      rethrow;
    } on http.ClientException catch (e) {
      onDisconnect?.call();
      throw PostgreSqlGatewayException(
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
    // T29 — server meta 事件的 columnTypes wire 扩展（列类型名），恢复
    // 裸连接驱动 typeOid（114 json / 3802 jsonb）通道的替代；只收 json 族。
    Map<String, String>? columnTypes;

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
          final metaTypes = chunk['columnTypes'] as List<dynamic>?;
          if (metaTypes != null && metaTypes.length == columns.length) {
            for (var i = 0; i < columns.length; i++) {
              final t = metaTypes[i]?.toString().toLowerCase() ?? '';
              if (t == 'json' || t == 'jsonb') {
                (columnTypes ??= {})[columns[i]] = t;
              }
            }
          }
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
          throw PostgreSqlGatewayException(
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
      throw const PostgreSqlGatewayException(
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
          serverElapsedMs ??
          DateTime.now().difference(startTime).inMilliseconds,
      columnTypes: columnTypes,
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
    if (!isConnected) throw Exception('未连接到数据库');

    // PG 的 EXPLAIN 是普通语句前缀（非会话级开关），网关单语句模型下直接可用。
    return await executeQuery('EXPLAIN $sql');
  }

  // ==========================================================================
  // Schema 发现（自裸连接版逐行迁入，SQL 与结果映射零改动）
  // ==========================================================================

  @override
  Future<List<String>> getSchemas({String? database}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final results = await executeQuery(
      "SELECT schema_name FROM information_schema.schemata "
      "WHERE schema_name NOT LIKE 'pg_%' AND schema_name != 'information_schema' "
      "ORDER BY schema_name",
    );
    return results.rows.map((row) => row['schema_name'] as String).toList();
  }

  /// Server-side search across all schemas — avoids eager-loading all metadata.
  /// Queries pg_catalog for tables/views matching [pattern] via ILIKE.
  Future<List<Map<String, String>>> searchObjects(String pattern) async {
    if (!isConnected) return [];
    final safe = pattern.replaceAll("'", "''");
    final results = await executeQuery(
      "SELECT schemaname AS schema_name, tablename AS object_name, 'table' AS object_type "
      "FROM pg_catalog.pg_tables "
      "WHERE schemaname NOT IN ('pg_catalog', 'information_schema') "
      "AND tablename ILIKE '%$safe%' "
      "UNION ALL "
      "SELECT schemaname AS schema_name, viewname AS object_name, 'view' AS object_type "
      "FROM pg_catalog.pg_views "
      "WHERE schemaname NOT IN ('pg_catalog', 'information_schema') "
      "AND viewname ILIKE '%$safe%' "
      "ORDER BY schema_name, object_name "
      "LIMIT 200",
    );
    return results.rows
        .map(
          (r) => {
            'schemaName': r['schema_name'] as String? ?? '',
            'objectName': r['object_name'] as String? ?? '',
            'objectType': r['object_type'] as String? ?? 'table',
          },
        )
        .toList();
  }

  /// T29 — record-only：只更新本地记录 schema（供元数据 SQL 内插），
  /// 不发 `SET search_path`（网关每语句独立连接，会话级 SET 不跨语句——
  /// 见文件头「行为边界」）。
  @override
  Future<void> setSearchPath(List<String> schemas) async {
    if (!isConnected) throw Exception('未连接到数据库');
    if (schemas.isNotEmpty) {
      _currentSchema = schemas.first;
    } else {
      _currentSchema = null;
    }
  }

  @override
  Future<void> setSchema(String schemaName) async {
    await setSearchPath([schemaName]);
  }

  @override
  Future<List<String>> getDatabases() async {
    if (!isConnected) throw Exception('未连接到数据库');

    // pg_database 是集群级 catalog，任一库可见；不带当前库路由——当前库可能
    // 刚被 drop（裸连接时代连接仍在；网关模型下 stale default 会让每语句开池
    // 直接 3D000）。
    final results = await executeQuery(
      "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname",
      database: '',
    );
    return results.rows.map((row) => row['datname'] as String).toList();
  }

  @override
  Future<void> useDatabase(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // T29 — record-only 切库：网关无本地连接可 close+reopen（PG 无 USE
    // 语句）。存在性经 getDatabases 验证（对齐裸连接版 Connection.open
    // 失败的语义），通过后记录目标库，后续查询经 executeQuery 的 database
    // 参数路由（server open_pg_db 按 db 开池）。
    if (_currentConnection?.database == dbName) {
      _currentSchema = 'public';
      return;
    }
    final databases = await getDatabases();
    if (!databases.contains(dbName)) {
      throw Exception('数据库 "$dbName" 不存在');
    }
    _currentConnection = _currentConnection?.copyWith(database: dbName);
    _currentSchema = 'public';
  }

  // T002 — add optional schemaName param for per-schema object discovery
  @override
  Future<List<String>> getTables({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final schema = (schemaName ?? _currentSchema ?? 'public').replaceAll(
      "'",
      "''",
    );

    final results = await executeQuery(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = '$schema' AND table_type = 'BASE TABLE' ORDER BY table_name",
    );
    return results.rows.map((row) => row['table_name'] as String).toList();
  }

  @override
  Future<List<DbTableMetadata>> getTablesWithMetadata({
    String? database,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = database ?? _currentConnection?.database ?? 'public';
    final results = await executeQuery('''
      SELECT
        c.relname AS table_name,
        c.reltuples::bigint AS row_count,
        pg_total_relation_size(c.oid) AS total_size,
        obj_description(c.oid, 'pg_class') AS comment,
        t.spcname AS tablespace,
        c.relkind AS kind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
      WHERE n.nspname = ${_escapeValue(dbName)}
        AND c.relkind = 'r'
      ORDER BY c.relname
    ''');
    return results.rows
        .map(
          (row) => DbTableMetadata(
            name: row['table_name']?.toString() ?? '',
            rowCount: row['row_count'] is int
                ? row['row_count'] as int
                : int.tryParse(row['row_count']?.toString() ?? ''),
            dataSize: row['total_size'] is int
                ? row['total_size'] as int
                : int.tryParse(row['total_size']?.toString() ?? ''),
            comment: row['comment']?.toString(),
            isApproximateCount: true,
          ),
        )
        .where((m) => m.name.isNotEmpty)
        .toList();
  }

  @override
  Future<DbTableMetadata> getTableMetadata(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('''
      SELECT
        c.relname AS table_name,
        c.reltuples::bigint AS row_count,
        pg_total_relation_size(c.oid) AS total_size,
        obj_description(c.oid, 'pg_class') AS comment
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = '$_currentSchemaSafe'
        AND c.relkind = 'r'
        AND c.relname = ${_escapeValue(tableName)}
    ''');
    if (results.rows.isEmpty) return DbTableMetadata(name: tableName);
    final row = results.rows.first;
    return DbTableMetadata(
      name: row['table_name']?.toString() ?? tableName,
      rowCount: row['row_count'] is int
          ? row['row_count'] as int
          : int.tryParse(row['row_count']?.toString() ?? ''),
      dataSize: row['total_size'] is int
          ? row['total_size'] as int
          : int.tryParse(row['total_size']?.toString() ?? ''),
      comment: row['comment']?.toString(),
    );
  }

  // T002 — add optional schemaName param
  @override
  Future<List<String>> getViews({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final schema = (schemaName ?? _currentSchema ?? 'public').replaceAll(
      "'",
      "''",
    );

    final results = await executeQuery(
      "SELECT table_name FROM information_schema.views WHERE table_schema = '$schema' ORDER BY table_name",
    );
    return results.rows.map((row) => row['table_name'] as String).toList();
  }

  // T002 — add optional schemaName param
  @override
  Future<List<String>> getProcedures({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final schema = (schemaName ?? _currentSchema ?? 'public').replaceAll(
      "'",
      "''",
    );

    final results = await executeQuery(
      "SELECT routine_name FROM information_schema.routines WHERE routine_schema = '$schema' AND routine_type = 'PROCEDURE' ORDER BY routine_name",
    );
    return results.rows.map((row) => row['routine_name'] as String).toList();
  }

  // T002 — add optional schemaName param
  @override
  Future<List<String>> getFunctions({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final schema = (schemaName ?? _currentSchema ?? 'public').replaceAll(
      "'",
      "''",
    );

    final results = await executeQuery(
      "SELECT routine_name FROM information_schema.routines WHERE routine_schema = '$schema' AND routine_type = 'FUNCTION' ORDER BY routine_name",
    );
    return results.rows.map((row) => row['routine_name'] as String).toList();
  }

  @override
  Future<List<String>> getEvents() async {
    // PostgreSQL 没有原生 Event Scheduler（可用 pg_cron 扩展，但不统一支持）
    return [];
  }

  // T002 — add optional schemaName param
  @override
  Future<List<String>> getMaterializedViews({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final schema = (schemaName ?? _currentSchema ?? 'public').replaceAll(
      "'",
      "''",
    );

    final results = await executeQuery(
      "SELECT matviewname FROM pg_matviews WHERE schemaname = '$schema' ORDER BY matviewname",
    );
    return results.rows.map((row) => row['matviewname'] as String).toList();
  }

  // T002 — add optional schemaName param
  @override
  Future<List<String>> getSequences({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final schema = (schemaName ?? _currentSchema ?? 'public').replaceAll(
      "'",
      "''",
    );

    final results = await executeQuery(
      "SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = '$schema' ORDER BY sequence_name",
    );
    return results.rows.map((row) => row['sequence_name'] as String).toList();
  }

  // T002 — add optional schemaName param
  @override
  Future<List<DbTrigger>> getTriggers({String? schemaName}) async {
    if (!isConnected) throw Exception('未连接到数据库');
    final schema = (schemaName ?? _currentSchema ?? 'public').replaceAll(
      "'",
      "''",
    );

    final results = await executeQuery('''
      SELECT trigger_name, event_manipulation, event_object_table, action_timing, action_statement
      FROM information_schema.triggers
      WHERE trigger_schema = '$schema'
    ''');
    return results.rows
        .map(
          (row) => DbTrigger(
            name: row['trigger_name'] as String? ?? '',
            event: row['event_manipulation'] as String? ?? '',
            table: row['event_object_table'] as String? ?? '',
            timing: row['action_timing'] as String? ?? '',
            statement: row['action_statement'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<List<DbColumn>> getTableColumns(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final st = _resolveSchemaTable(tableName);
    final results = await executeQuery('''
      SELECT
        column_name,
        data_type,
        character_maximum_length,
        is_nullable,
        column_default
      FROM information_schema.columns
      WHERE table_schema = '${st.schema}'
        AND table_name = ${_escapeValue(st.table)}
      ORDER BY ordinal_position
    ''');

    final columns = <DbColumn>[];
    for (final row in results.rows) {
      String type = row['data_type'] as String;
      if (row['character_maximum_length'] != null) {
        type += '(${row['character_maximum_length']})';
      }

      columns.add(
        DbColumn(
          name: row['column_name'] as String,
          type: type,
          isPrimaryKey: false,
          isNullable: (row['is_nullable'] as String) == 'YES',
          defaultValue: row['column_default']?.toString(),
        ),
      );
    }

    final pkResults = await executeQuery('''
      SELECT a.attname
      FROM pg_index i
      JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
      WHERE i.indrelid = (SELECT oid FROM pg_class WHERE relname = ${_escapeValue(st.table)} AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '${st.schema}'))
        AND i.indisprimary
    ''');

    final pkColumns = pkResults.rows
        .map((row) => row['attname'] as String)
        .toSet();

    return columns
        .map(
          (col) => DbColumn(
            name: col.name,
            type: col.type,
            isPrimaryKey: pkColumns.contains(col.name),
            isNullable: col.isNullable,
            defaultValue: col.defaultValue,
          ),
        )
        .toList();
  }

  @override
  Future<List<DbIndex>> getTableIndexes(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final st = _resolveSchemaTable(tableName);
    final results = await executeQuery('''
      SELECT
        i.relname as index_name,
        a.attname as column_name,
        ix.indisunique as is_unique
      FROM pg_class t
      JOIN pg_index ix ON t.oid = ix.indrelid
      JOIN pg_class i ON i.oid = ix.indexrelid
      JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
      WHERE t.relname = ${_escapeValue(st.table)}
        AND t.relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = '${st.schema}')
      ORDER BY i.relname, a.attnum
    ''');

    final indexMap = <String, List<String>>{};
    final uniqueSet = <String>{};

    for (final row in results.rows) {
      final indexName = row['index_name'] as String;
      final columnName = row['column_name'] as String;
      // 网关元组布尔格适配（裸连接版为驱动原生 bool）。
      final isUnique = _truthy(row['is_unique']);

      indexMap.putIfAbsent(indexName, () => []);
      indexMap[indexName]!.add(columnName);
      if (isUnique) uniqueSet.add(indexName);
    }

    return indexMap.entries
        .map(
          (entry) => DbIndex(
            name: entry.key,
            columns: entry.value,
            isUnique: uniqueSet.contains(entry.key),
          ),
        )
        .toList();
  }

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final st = _resolveSchemaTable(tableName);
      final results = await executeQuery('''
        SELECT
          tc.constraint_name,
          kcu.column_name,
          ccu.table_name AS referenced_table_name,
          ccu.column_name AS referenced_column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
          AND tc.table_name = kcu.table_name
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = tc.constraint_name
          AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.table_name = ${_escapeValue(st.table)}
          AND tc.table_schema = '${st.schema}'
        ORDER BY tc.constraint_name, kcu.ordinal_position
      ''');

      final fks = <ForeignKey>[];
      for (final row in results.rows) {
        fks.add(
          ForeignKey(
            name: row['constraint_name']?.toString() ?? '',
            table: tableName,
            column: row['column_name']?.toString() ?? '',
            referencedTable: row['referenced_table_name']?.toString() ?? '',
            referencedColumn: row['referenced_column_name']?.toString() ?? '',
          ),
        );
      }
      return fks;
    } catch (e) {
      AppLogger.d(_tag, 'getForeignKeys failed: $e');
      return [];
    }
  }

  /// 反向外键快路径：information_schema 单查（constraint_column_usage 按
  /// 被引用表反查 + referential_constraints 取 ON DELETE/UPDATE 动作），
  /// 避免基类默认实现 O(表数) 次元数据扫描。正向 [getForeignKeys] 的
  /// 查询不含 referential_constraints join，动作规则仅在此反查路径提供。
  @override
  Future<List<ForeignKey>> getReferencingForeignKeys(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final st = _resolveSchemaTable(tableName);
      final results = await executeQuery('''
        SELECT
          tc.constraint_name,
          tc.table_name,
          kcu.column_name,
          ccu.column_name AS referenced_column_name,
          rc.delete_rule,
          rc.update_rule
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
          AND tc.table_schema = kcu.table_schema
          AND tc.table_name = kcu.table_name
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = tc.constraint_name
          AND ccu.table_schema = tc.table_schema
        JOIN information_schema.referential_constraints rc
          ON rc.constraint_name = tc.constraint_name
          AND rc.constraint_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND ccu.table_name = ${_escapeValue(st.table)}
          AND tc.table_schema = ${_escapeValue(st.schema)}
        ORDER BY tc.table_name, tc.constraint_name, kcu.ordinal_position
      ''');

      final fks = <ForeignKey>[];
      for (final row in results.rows) {
        fks.add(
          ForeignKey(
            name: row['constraint_name']?.toString() ?? '',
            table: row['table_name']?.toString() ?? '',
            column: row['column_name']?.toString() ?? '',
            referencedTable: tableName,
            referencedColumn: row['referenced_column_name']?.toString() ?? '',
            onUpdate: row['update_rule']?.toString(),
            onDelete: row['delete_rule']?.toString(),
          ),
        );
      }
      return fks;
    } catch (e) {
      AppLogger.d(_tag, 'getReferencingForeignKeys failed: $e');
      return [];
    }
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

    final results = await executeQuery('SELECT version() as version');
    final version = results.rows.first['version'] as String;

    return {'version': version, 'database': 'PostgreSQL'};
  }

  // ProcessListAdapter —— pg_terminate_backend 终止后端进程
  //（pid 来自 pg_stat_activity，整型数值内插无注入风险）。
  // 网关模型下 SQL 经 server 侧每语句池执行，pg_terminate_backend 杀的是
  // 目标实例上的后端（含本 app 网关在途语句所开的后端），语义不变。
  @override
  Future<bool> killProcess(int processId) async {
    if (!isConnected) return false;
    try {
      // pg_terminate_backend 返回布尔——权限不足或 pid 不存在时返回 false
      // 而不抛异常；若不读取返回值，会把"实际未终止"误报为成功。
      final results = await executeQuery(
        'SELECT pg_terminate_backend($processId) AS ok',
      );
      if (results.rows.isEmpty) return false;
      // 网关布尔格适配：bool / 't' / 'true' 均视为真。
      return _truthy(results.rows.first['ok']);
    } catch (e) {
      AppLogger.e(_tag, 'killProcess failed (pid=$processId)', e);
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('''
      SELECT
        pg_database.datname as name,
        pg_size_pretty(pg_database_size(pg_database.datname)) as size,
        pg_encoding_to_char(pg_database.encoding) as encoding,
        pg_database.datcollate as collate,
        pg_database.datctype as ctype
      FROM pg_database
      WHERE pg_database.datname = ${_escapeValue(dbName)}
    ''');

    if (results.rows.isEmpty) return null;

    final row = results.rows.first;
    return {
      'name': row['name'],
      'size': row['size'],
      'encoding': row['encoding'],
      'collate': row['collate'],
      'ctype': row['ctype'],
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
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'createDatabase');
    if (!isConnected) throw Exception('未连接到数据库');

    String buildCreateSql() {
      String sql = 'CREATE DATABASE ${_escapeIdentifier(dbName)}';
      if (options != null) {
        if (options['encoding'] != null) {
          sql += ' ENCODING ${_escapeValue(options['encoding'])}';
        }
        if (options['collate'] != null) {
          sql += ' LC_COLLATE ${_escapeValue(options['collate'])}';
        }
        if (options['ctype'] != null) {
          sql += ' LC_CTYPE ${_escapeValue(options['ctype'])}';
        }
      }
      return sql;
    }

    try {
      await executeQuery(buildCreateSql());
      return true;
    } catch (e) {
      // 裸连接版的「closing down 竞态 → 侧连接核验存在性」链路随网关下线
      // （每语句独立池无该竞态；明确错误即 false）——见文件头「行为边界」。
      AppLogger.w(_tag, '创建数据库异常: $dbName - $e');
      return false;
    }
  }

  @override
  Future<bool> dropDatabase(String dbName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropDatabase');
    if (!isConnected) throw Exception('未连接到数据库');

    // PG 不允许删除仍有连接的库。裸连接版用连维护库的临时侧连接执行；
    // 网关模型下改为 database 路由（语句在维护库的每语句池上执行）：
    // 先终止目标库所有其它后端，再 DROP（WITH (FORCE) 优先，PG<13 回退
    // 普通 DROP）。
    final conn = _currentConnection;
    if (conn == null) return false;
    final maintenanceDb = (dbName == 'postgres') ? 'template1' : 'postgres';

    try {
      // 1) 终止目标库的其它后端（含本 app 可能存在的在途查询后端）
      await executeQuery(
        'SELECT pg_terminate_backend(pid) FROM pg_stat_activity '
        'WHERE datname = ${_escapeValue(dbName)} AND pid <> pg_backend_pid()',
        database: maintenanceDb,
      );

      // 2) 优先 WITH (FORCE)（PG>=13）；旧版本语法不支持则回退普通 DROP
      try {
        await executeQuery(
          'DROP DATABASE ${_escapeIdentifier(dbName)} WITH (FORCE)',
          database: maintenanceDb,
        );
      } catch (e) {
        AppLogger.d(_tag, 'DROP WITH (FORCE) 失败，回退普通 DROP: $e');
        await executeQuery(
          'DROP DATABASE ${_escapeIdentifier(dbName)}',
          database: maintenanceDb,
        );
      }

      // 3) 裸连接版此处把主连接重连到维护库；网关模型下清掉本地记录库，
      //    后续查询回落 server 注册的默认库（避免带 stale db 路由直接失败）。
      if (conn.database == dbName) {
        _clearRecordedDatabase();
        _currentSchema = 'public';
      }

      AppLogger.i(_tag, '数据库已删除: $dbName');
      return true;
    } catch (e) {
      AppLogger.e(_tag, '删除数据库失败: $dbName', e);
      return false;
    }
  }

  @override
  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    Map<String, dynamic>? options,
  }) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'createTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final columnDefs = columns
          .map((col) {
            String def = '${_escapeIdentifier(col.name)} ${col.type}';
            if (col.isPrimaryKey) def += ' PRIMARY KEY';
            if (!col.isNullable) def += ' NOT NULL';
            if (col.defaultValue != null) def += ' DEFAULT ${col.defaultValue}';
            return def;
          })
          .join(', ');

      // 表名可能带 schema 前缀，须用限定转义（_escapeIdentifier 会把 'public.users' 当单标识符）
      String sql =
          'CREATE TABLE ${_escapeQualifiedIdentifier(tableName)} ($columnDefs)';
      await executeQuery(sql);
      return true;
    } catch (e) {
      AppLogger.d(_tag, '创建表失败: $e');
      return false;
    }
  }

  @override
  Future<bool> dropTable(String tableName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await executeQuery('DROP TABLE ${_escapeQualifiedIdentifier(tableName)}');
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除表失败: $e');
      return false;
    }
  }

  @override
  Future<bool> renameTable(String oldName, String newName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'renameTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await executeQuery(
        'ALTER TABLE ${_escapeQualifiedIdentifier(oldName)} RENAME TO ${_escapeIdentifier(newName)}',
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
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'truncateTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final parts = <String>[
        'TRUNCATE TABLE',
        _escapeQualifiedIdentifier(tableName),
      ];
      if (options?.cascade == true) parts.add('CASCADE');
      if (options?.restartIdentity == true) {
        parts.add('RESTART IDENTITY');
      } else if (options?.restartIdentity == false) {
        parts.add('CONTINUE IDENTITY');
      }
      await executeQuery(parts.join(' '));
      return true;
    } catch (e) {
      AppLogger.d(_tag, '清空表失败: $e');
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

    final escapedTable = _escapeQualifiedIdentifier(tableName);
    if (cursorColumn != null && cursorValue != null) {
      final escapedColumn = _escapeIdentifier(cursorColumn);
      return await executeQuery(
        'SELECT * FROM $escapedTable WHERE $escapedColumn > ${_escapeValue(cursorValue)} ORDER BY $escapedColumn LIMIT $limit',
      );
    }
    return await executeQuery(
      'SELECT * FROM $escapedTable LIMIT $limit OFFSET $offset',
    );
  }

  @override
  Future<int> getTableRowCount(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery(
      'SELECT COUNT(*) as count FROM ${_escapeQualifiedIdentifier(tableName)}',
    );
    // 网关元组数字格适配（JSON number 或文本均可）。
    return int.parse(results.rows.first['count'].toString());
  }

  // ==========================================================================
  // 列操作
  // ==========================================================================

  @override
  Future<bool> addColumn(String tableName, DbColumn column) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'addColumn');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      String def =
          'ADD COLUMN ${_escapeIdentifier(column.name)} ${column.type}';
      if (!column.isNullable) def += ' NOT NULL';
      if (column.defaultValue != null) def += ' DEFAULT ${column.defaultValue}';

      await executeQuery(
        'ALTER TABLE ${_escapeQualifiedIdentifier(tableName)} $def',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '添加列失败: $e');
      return false;
    }
  }

  @override
  Future<bool> dropColumn(String tableName, String columnName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropColumn');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await executeQuery(
        'ALTER TABLE ${_escapeQualifiedIdentifier(tableName)} DROP COLUMN ${_escapeIdentifier(columnName)}',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除列失败: $e');
      return false;
    }
  }

  @override
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  ) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'modifyColumn');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      if (oldColumnName != newColumn.name) {
        await executeQuery(
          'ALTER TABLE ${_escapeQualifiedIdentifier(tableName)} RENAME COLUMN ${_escapeIdentifier(oldColumnName)} TO ${_escapeIdentifier(newColumn.name)}',
        );
      }

      String def =
          'ALTER COLUMN ${_escapeIdentifier(newColumn.name)} TYPE ${newColumn.type}';
      if (!newColumn.isNullable) {
        def +=
            ', ALTER COLUMN ${_escapeIdentifier(newColumn.name)} SET NOT NULL';
      }
      if (newColumn.defaultValue != null) {
        def +=
            ', ALTER COLUMN ${_escapeIdentifier(newColumn.name)} SET DEFAULT ${newColumn.defaultValue}';
      }

      await executeQuery(
        'ALTER TABLE ${_escapeQualifiedIdentifier(tableName)} $def',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '修改列失败: $e');
      return false;
    }
  }

  @override
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName,
  ) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'renameColumn');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await executeQuery(
        'ALTER TABLE ${_escapeQualifiedIdentifier(tableName)} RENAME COLUMN ${_escapeIdentifier(oldColumnName)} TO ${_escapeIdentifier(newColumnName)}',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '重命名列失败: $e');
      return false;
    }
  }

  // ==========================================================================
  // 索引操作
  // ==========================================================================

  @override
  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
  }) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'createIndex');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final colNames = columns.map((c) => _escapeIdentifier(c)).join(', ');
      final uniqueStr = unique ? 'UNIQUE ' : '';
      await executeQuery(
        'CREATE ${uniqueStr}INDEX ${_escapeIdentifier(indexName)} ON ${_escapeQualifiedIdentifier(tableName)} ($colNames)',
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '创建索引失败: $e');
      return false;
    }
  }

  @override
  Future<bool> dropIndex(String tableName, String indexName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropIndex');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      // T063 — schema-qualify the index name. PG indexes are
      // schema-scoped and DROP INDEX has no ON clause, so a bare "idx" resolves
      // against search_path and fails for any non-default schema.
      // _escapeQualifiedIdentifier splits on '.': bare "idx"→"idx" (unchanged,
      // backward-compatible with bare-name callers), "s.idx"→"s"."idx".
      await executeQuery('DROP INDEX ${_escapeQualifiedIdentifier(indexName)}');
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除索引失败: $e');
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
    sb.writeln('-- Generated by DBMaster');
    sb.writeln('-- Date: ${DateTime.now().toIso8601String()}');
    sb.writeln();

    // 遍历所有用户 schema（原先仅 getTables() 取当前/public schema，静默漏掉其它 schema 的表）
    final schemas = await getSchemas();
    final tables = <String>[];
    for (final schema in schemas) {
      final schemaTables = await getTables(schemaName: schema);
      for (final t in schemaTables) {
        tables.add('$schema.$t');
      }
    }

    // Collect FK dependencies for topological sort
    final fksMap = <String, List<ForeignKey>>{};
    for (final table in tables) {
      fksMap[table] = await getForeignKeys(table);
    }

    // Build dependency map for the topological sorter
    final sortMap = <String, String>{};
    for (final table in tables) {
      final fks = fksMap[table] ?? [];
      sortMap[table] = fks.isNotEmpty
          ? 'CREATE TABLE ${_escapeQualifiedIdentifier(table)} (${fks.map((fk) => 'FOREIGN KEY ("${fk.column}") REFERENCES ${_qualifiedRef(table, fk.referencedTable)} ("${fk.referencedColumn}")').join(', ')})'
          : 'CREATE TABLE ${_escapeQualifiedIdentifier(table)} (id INT)';
    }

    final sortedTables = TableDependencySorter.sortByCreateOrder(sortMap);

    for (final table in sortedTables) {
      final details = await getTableDetails(table);
      final fks = fksMap[table] ?? [];
      sb.writeln('-- Table: $table');
      sb.writeln(
        _buildCreateTableExportSql(
          table,
          details.columns,
          details.indexes,
          fks,
        ),
      );
      sb.writeln();
    }

    return sb.toString();
  }

  String _buildCreateTableExportSql(
    String tableName,
    List<DbColumn> columns,
    List<DbIndex> indexes,
    List<ForeignKey> foreignKeys,
  ) {
    final buf = StringBuffer();
    // 表名按 schema.table 限定转义
    buf.writeln('CREATE TABLE ${_escapeQualifiedIdentifier(tableName)} (');

    final pkColumns = columns.where((c) => c.isPrimaryKey).toList();
    final hasCompositePk = pkColumns.length > 1;
    final filteredIndexes = indexes.where((i) => i.name != 'PRIMARY').toList();

    final parts = <String>[];
    for (final col in columns) {
      String def = '  "${col.name}" ${col.type}';
      if (col.isPrimaryKey && !hasCompositePk) def += ' PRIMARY KEY';
      if (!col.isNullable) def += ' NOT NULL';
      if (col.defaultValue != null) def += ' DEFAULT ${col.defaultValue}';
      parts.add(def);
    }
    if (hasCompositePk) {
      final pkColList = pkColumns.map((c) => '"${c.name}"').join(', ');
      parts.add('  PRIMARY KEY ($pkColList)');
    }
    for (final idx in filteredIndexes) {
      final unique = idx.isUnique ? 'UNIQUE ' : '';
      final colList = idx.columns.map((c) => '"$c"').join(', ');
      parts.add('  ${unique}INDEX "${idx.name}" ($colList)');
    }
    for (final fk in foreignKeys) {
      parts.add(
        '  FOREIGN KEY ("${fk.column}") REFERENCES ${_qualifiedRef(tableName, fk.referencedTable)} ("${fk.referencedColumn}")',
      );
    }
    buf.writeln(parts.join(',\n'));
    buf.write(');');
    return buf.toString();
  }

  /// 返回 FK 引用表的限定转义名（供导出 DDL 使用）。
  /// DEFENSIVE-NOTE: ForeignKey 仅含 referencedTable（裸名），无法获知被引表所在 schema；
  /// 这里以 FK 所属表的 schema 限定——同 schema FK（绝大多数场景）正确，跨 schema FK 为已知限制。
  String _qualifiedRef(String ownerTable, String referencedTable) {
    if (referencedTable.contains('.')) {
      return _escapeQualifiedIdentifier(referencedTable);
    }
    final (schema, _) = splitSchemaTable(ownerTable);
    return _escapeQualifiedIdentifier(
      schema == null ? referencedTable : '$schema.$referencedTable',
    );
  }

  /// 执行 SQL 脚本（SQL-aware 分割 + 逐条执行）。
  ///
  /// U08：失败不再吞错返回 false，抛 [SqlScriptExecutionException]
  /// （语句序号/行号/已执行条数定位）。网关单语句约束（MULTI_STATEMENT
  /// 4xx）下逐条执行与裸连接版口径一致。
  @override
  Future<bool> executeSqlScript(String script) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final statements = SQLParserService.split(script);
    var executed = 0;
    try {
      for (final statement in statements) {
        try {
          await executeQuery(statement.sql);
        } catch (e) {
          throw SqlScriptExecutionException(
            statementIndex: statement.index,
            lineStart: statement.lineStart,
            lineEnd: statement.lineEnd,
            statementSql: statement.sql,
            cause: e.toString(),
            committedCount: executed,
          );
        }
        executed++;
      }
      return true;
    } catch (e) {
      AppLogger.d(_tag, '执行SQL脚本失败: $e');
      rethrow;
    }
  }

  // ==========================================================================
  // 字符集/排序规则
  // ==========================================================================

  @override
  Future<List<String>> getCharsets() async {
    return [
      'UTF8',
      'LATIN1',
      'SQL_ASCII',
      'EUC_JP',
      'EUC_KR',
      'EUC_TW',
      'WIN866',
      'WIN874',
      'WIN1250',
      'WIN1251',
      'WIN1252',
      'WIN1256',
      'WIN1258',
      'GBK',
      'BIG5',
      'GB18030',
    ];
  }

  @override
  Future<List<Map<String, String>>> getCollations({String? charset}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    String sql = 'SELECT collname, collencoding FROM pg_collation';
    if (charset != null) {
      sql += " WHERE pg_catalog.pg_encoding_to_char(collencoding) = ''";
    }
    sql += ' ORDER BY collname';

    final results = await executeQuery(sql);
    return results.rows
        .map(
          (row) => {
            'name': row['collname'] as String,
            'encoding': row['collencoding']?.toString() ?? '',
          },
        )
        .toList();
  }

  // ==========================================================================
  // ExtensionAdapter
  // ==========================================================================

  @override
  Future<List<PgExtension>> getExtensions() async {
    if (!isConnected) return [];

    try {
      final results = await executeQuery('''
        SELECT extname, extversion,
               extnamespace::regnamespace AS schema,
               extrelocatable,
               obj_description(oid, 'pg_extension') AS comment
        FROM pg_extension
        ORDER BY extname
      ''');

      return results.rows.map((row) {
        return PgExtension.fromMap(row);
      }).toList();
    } catch (e) {
      AppLogger.e(_tag, 'getExtensions failed', e);
      return [];
    }
  }

  Future<List<PgExtensionMember>> _getExtensionTypes(String extName) async {
    try {
      final results = await executeQuery('''
        SELECT t.typname AS name,
               t.typnamespace::regnamespace AS schema,
               format_type(t.oid, NULL) AS signature
        FROM pg_type t
        JOIN pg_depend d ON d.objid = t.oid
        JOIN pg_extension e ON d.refobjid = e.oid
        WHERE e.extname = '${extName.replaceAll("'", "''")}'
          AND d.deptype = 'e'
        ORDER BY schema, name
      ''');
      return results.rows
          .map(
            (row) => PgExtensionMember.fromMap(row, PgExtensionMemberKind.type),
          )
          .toList();
    } catch (e) {
      AppLogger.e(_tag, '_getExtensionTypes($extName) failed', e);
      return [];
    }
  }

  Future<List<PgExtensionMember>> _getExtensionFunctions(String extName) async {
    try {
      final results = await executeQuery('''
        SELECT p.proname AS name,
               p.pronamespace::regnamespace AS schema,
               pg_get_function_arguments(p.oid) AS signature
        FROM pg_proc p
        JOIN pg_depend d ON d.objid = p.oid
        JOIN pg_extension e ON d.refobjid = e.oid
        WHERE e.extname = '${extName.replaceAll("'", "''")}'
          AND d.deptype = 'e'
        ORDER BY schema, name
      ''');
      return results.rows
          .map(
            (row) =>
                PgExtensionMember.fromMap(row, PgExtensionMemberKind.function),
          )
          .toList();
    } catch (e) {
      AppLogger.e(_tag, '_getExtensionFunctions($extName) failed', e);
      return [];
    }
  }

  Future<List<PgExtensionMember>> _getExtensionOperators(String extName) async {
    try {
      final results = await executeQuery('''
        SELECT o.oprname AS name,
               o.oprnamespace::regnamespace AS schema,
               format_type(o.oprleft, NULL) || ' → ' ||
                 format_type(o.oprright, NULL) || ' → ' ||
                 format_type(o.oprresult, NULL) AS signature
        FROM pg_operator o
        JOIN pg_depend d ON d.objid = o.oid
        JOIN pg_extension e ON d.refobjid = e.oid
        WHERE e.extname = '${extName.replaceAll("'", "''")}'
          AND d.deptype = 'e'
        ORDER BY schema, name
      ''');
      return results.rows
          .map(
            (row) =>
                PgExtensionMember.fromMap(row, PgExtensionMemberKind.operator),
          )
          .toList();
    } catch (e) {
      AppLogger.e(_tag, '_getExtensionOperators($extName) failed', e);
      return [];
    }
  }

  /// Convenience method to load all extension details (members) at once.
  Future<Map<String, List<PgExtensionMember>>> getExtensionMembers(
    String extName,
  ) async {
    final results = await Future.wait([
      _getExtensionTypes(extName),
      _getExtensionFunctions(extName),
      _getExtensionOperators(extName),
    ]);
    return {
      'types': results[0],
      'functions': results[1],
      'operators': results[2],
    };
  }

  @override
  Future<List<VectorIndex>> getVectorIndexes() async {
    if (!isConnected) return [];

    try {
      final results = await executeQuery('''
        SELECT
            c.relname AS index_name,
            t.relname AS table_name,
            a.attname AS column_name,
            am.amname,
            i.reloptions AS index_options
        FROM pg_index x
        JOIN pg_class c ON c.oid = x.indexrelid
        JOIN pg_class t ON t.oid = x.indrelid
        JOIN pg_am am ON am.oid = c.relam
        JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(x.indkey)
        WHERE am.amname IN ('ivfflat', 'hnsw')
      ''');

      return results.rows.map((row) {
        final options = _parseRelOptions(row['index_options']);
        return VectorIndex(
          name: row['index_name']?.toString() ?? '',
          tableName: row['table_name']?.toString() ?? '',
          columnName: row['column_name']?.toString() ?? '',
          indexType: row['amname']?.toString() == 'hnsw'
              ? VectorIndexType.hnsw
              : VectorIndexType.ivfflat,
          distanceFunction: options['distance'],
          dimensions: int.tryParse(options['dimensions'] ?? ''),
          options: options,
        );
      }).toList();
    } catch (e) {
      AppLogger.e(_tag, 'getVectorIndexes failed', e);
      return [];
    }
  }

  /// Parse PostgreSQL reloptions text array into a Map.
  Map<String, String> _parseRelOptions(dynamic reloptions) {
    final map = <String, String>{};
    if (reloptions == null) return map;
    final text = reloptions.toString();

    // reloptions is returned as {key1=value1,key2=value2,...} from PostgreSQL
    final cleaned = text.replaceAll(RegExp(r'[{}]'), '');
    for (final part in cleaned.split(',')) {
      final kv = part.trim().split('=');
      if (kv.length == 2) {
        map[kv[0].trim()] = kv[1].trim();
      }
    }
    return map;
  }

  // ==========================================================================
  // JsonAdapter
  // ==========================================================================

  @override
  Future<List<String>> getJsonColumns(String tableName) async {
    if (!isConnected) return [];
    try {
      final parts = tableName.split('.');
      final schema = parts.length > 1 ? parts[0] : 'public';
      final table = parts.length > 1 ? parts[1] : tableName;
      final results = await executeQuery('''
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = '${schema.replaceAll("'", "''")}'
          AND table_name = '${table.replaceAll("'", "''")}'
          AND data_type IN ('json', 'jsonb')
        ORDER BY ordinal_position
      ''');
      return results.rows
          .map((r) => r['column_name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (e) {
      AppLogger.e(_tag, 'getJsonColumns($tableName) failed', e);
      return [];
    }
  }

  @override
  Future<bool> isJsonColumn(String tableName, String columnName) async {
    if (!isConnected) return false;
    try {
      final parts = tableName.split('.');
      final schema = parts.length > 1 ? parts[0] : 'public';
      final table = parts.length > 1 ? parts[1] : tableName;
      final results = await executeQuery('''
        SELECT data_type FROM information_schema.columns
        WHERE table_schema = '${schema.replaceAll("'", "''")}'
          AND table_name = '${table.replaceAll("'", "''")}'
          AND column_name = '${columnName.replaceAll("'", "''")}'
      ''');
      if (results.rows.isNotEmpty) {
        final dt = results.rows.first['data_type']?.toString() ?? '';
        return dt == 'json' || dt == 'jsonb';
      }
    } catch (e) {
      AppLogger.e(_tag, 'isJsonColumn failed', e);
    }
    return false;
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
        'PostgreSQL 网关模式需要已连接的 dbmaster server（未检测到会话；'
        'embedded 模式下请确认 dbmaster-server.exe 随包可用）',
      );
    }
    return server;
  }

  /// 连接草稿体（网关 wire：camelCase，PG 走 host/port/凭据族）。
  /// 注：draft/test body（server `ConnectionDraftBody`）无 TLS 字段——
  /// `extra['useSSL']` 暂不透传（见文件头「行为边界」）。
  /// server 侧 SSH 隧道对象（extra['ssh']）存在时原样透传。
  Map<String, dynamic> _draftBody(DatabaseConnection connection) => {
    'dbType': 'postgresql',
    'host': connection.host,
    'port': connection.port,
    'username': connection.username ?? '',
    'password': connection.password ?? '',
    if (connection.database != null && connection.database!.isNotEmpty)
      'defaultDatabase': connection.database,
    'ssh': ?gatewaySshWire(connection),
  };

  /// 现场注册（凭据入 server vault），返回 serverConnId。
  /// PG 无 charset/timezone 会话初始化字段（与 mysql 族不同），注册体
  /// 与草稿体同形 + name/readOnly。
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

  /// 4xx/5xx JSON 错误体 → [PostgreSqlGatewayException]（非 JSON 保 HTTP 概要）。
  PostgreSqlGatewayException _decodeErrResponse(int status, String text) {
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
    return PostgreSqlGatewayException(code, message);
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
