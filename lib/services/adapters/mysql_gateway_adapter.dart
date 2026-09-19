//! T29 · MySQL 协议族网关壳 adapter（#31 T29 客户端半边）。
//!
//! **形态**：与 T28 `sqlserver_gateway_adapter.dart` 1:1 同构——实现
//! `DatabaseAdapter` 接口、底层执行走 T27 网关 API
//! （`POST /api/gw/connections/{id}/query` SSE 流式）的过渡壳；port
//! （GatewayBacking）Tier 1/执行通道落地后，本壳逻辑上移为
//! GatewayBacking，UI 零改动（铁律 4）。
//!
//! **取代**：原 `mysql_base_adapter.dart` + `mysql_adapter.dart` +
//! `doris_adapter.dart`（Dart `mysql_client` 裸连接族）。本地不再持有
//! MySQL 连接——凭据经网关注册入 server vault
//! （`POST /api/gw/connections`，与 ConnectionProvider C10 镜像同一
//! `connection_server_id_map` 映射表），每次执行由 server 开专用连接。
//! embedded（本地 server 子进程）与远程 server 两形态由
//! [ServerConnection] 的 serverUrl + Bearer 吸收，本壳不区分。
//!
//! **元数据/DDL 方法**：自 `mysql_base_adapter.dart` 逐行迁入（SQL 构造 +
//! 行解析零改动），Doris 方言覆写自 `doris_adapter.dart` 逐行迁入，
//! 底层 `executeQuery` 自动走网关。
//!
//! **行为边界（v1，相对裸连接版的已知差异）**：
//! - 事务：**T29 临时下线**——网关无状态单语句，BEGIN/COMMIT 不能跨执行
//!   保持；不再 `implements TransactionalAdapter`（UI 经
//!   `is TransactionalAdapter` 门控自动降级），beginTransaction/commit/
//!   rollback 误调用时 fail-loud 抛 [UnsupportedError]。恢复路径：旧
//!   `/api/db/:conn_id/txn/*` pinned session 或未来 `/api/gw` pinned
//!   session。
//! - SSH 隧道：**descoped**——远程 server 形态下网关从 server 侧发起连接，
//!   够不到仅 SSH 可达的实例（客户端本地隧道无意义）；embedded 本地
//!   server 不受影响（与目标库同机）。恢复路径待后续阶段拍板。
//! - TLS/useSSL：网关 register/test body（server `RegisterBody` /
//!   `ConnectionDraftBody`）**无 TLS 字段**——连接 `extra['useSSL']`
//!   暂不透传（server 侧按默认非 TLS 拨号），登记为 T29 已知边界。
//! - charset/timezone：不再由客户端 SET NAMES / SET time_zone——注册时经
//!   register body 的 `charset`/`timezone` 字段交给 server，server 侧
//!   按 profile 在每语句连接上做会话初始化（Doris 自动跳过 time_zone，
//!   见 automation `mysql_family.rs`）。草稿 test body 无此二字段，
//!   测试连接不应用会话变量（不影响凭据校验语义）。
//! - JSON 列类型检测：旧版靠驱动结果集列 type code 0xf5 填
//!   `QueryResult.columnTypes`；网关 SSE meta 只携带列名（无列类型），
//!   该通道随裸连接下线（columnTypes 恒 null）。`getJsonColumns`/
//!   `isJsonColumn` 走 information_schema SQL，不受影响，逐行保留。
//! - 多语句：网关单语句约束（MULTI_STATEMENT 4xx）——编辑器多语句脚本
//!   走 executeSqlScript（SQLParserService.split 逐条执行），与裸连接版
//!   口径一致。
//! - Doris `executeQuery(database:)` 的 useDatabase 切换覆写不再需要：
//!   基类把 `database` 作为网关 query 参数路由（server 每语句按
//!   defaultDatabase/database 选库），无本地会话可切换。
//! - 值解码：server `decode_cell_mysql` 产出 text/int/float/bool/JSON/
//!   DECIMAL 字符串 + 日期时间族（DATE/TIME/DATETIME/TIMESTAMP，SQL
//!   惯例空格分隔字符串；TIMESTAMP 按注册 timezone 的 UTC 墙钟渲染，
//!   2026-08-27 网关日期解码修复——此前族级落 null）；TIME 负值/跨日
//!   （超出 00:00:00-23:59:59）仍落 null（chrono NaiveTime 表示域）。

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
import '../ports/port_types.dart';
import '../../models/connection_failure.dart';
import '../../models/database_models.dart';
import '../../models/sql_script_exception.dart'
    show SqlScriptExecutionException;
import '../../utils/app_logger.dart';
import '../../utils/sql_escape_utils.dart';
import '../../utils/sql_parser.dart';
import 'ai_adapter_mixin.dart';

/// 网关查询错误（SSE error 事件 / 4xx 前置校验失败）。`code` 对齐
/// c01 §4.4 稳定码集（TIMEOUT/CANCELLED/DB_ERROR/NOT_FOUND/…），
/// `engineCode` 透传引擎原始错误号。与 T28 `SqlServerGatewayException`
/// 同形（各自独立类型，避免跨族耦合）。
class MySqlGatewayException implements Exception {
  final String code;
  final String message;
  final String? engineCode;

  const MySqlGatewayException(this.code, this.message, {this.engineCode});

  @override
  String toString() {
    final eng = engineCode == null ? '' : ' (engine $engineCode)';
    return '[$code]$eng $message';
  }
}

/// MySQL 协议族网关壳基类 —— 抽取 MySQL/Doris/OceanBase/TiDB/StarRocks/
/// MariaDB 的公共逻辑（对应旧 `MySQLBaseAdapter`，底层执行换网关）。
abstract class MySQLGatewayBaseAdapter extends DatabaseAdapter
    with AiAdapterMixin, DisconnectAware
    implements
        SqlSchemaAdapter,
        DdlAdapter,
        SqlScriptAdapter,
        CharsetAdapter,
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

  /// 在途执行的取消句柄（disconnect / 显式取消用）。
  String? _inFlightExecutionId;

  MySQLGatewayBaseAdapter();

  /// 日志标签，子类覆写（如 'MySQLAdapter' / 'DorisAdapter'）。
  String get adapterName;

  @override
  DatabaseType get databaseType;

  @override
  bool get isConnected => _serverConnId != null;

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
  String getDefaultBrowseQuery(String tableName, {int limit = 100}) {
    final escaped = tableName
        .split('.')
        .map(SqlEscapeUtils.escapeMySqlIdentifier)
        .join('.');
    return 'SELECT * FROM $escaped LIMIT $limit;';
  }

  // ==========================================================================
  // 连接管理（网关：注册/复用 serverConnId，无本地 MySQL 连接）
  // ==========================================================================

  @override
  Future<bool> connect(DatabaseConnection connection) async {
    _currentConnection = connection;
    final server = _requireServerSession();

    // 连接失败 UX 重构 T9a：失败不再吞掉（原草稿 test 失败 return false、
    // 途中网关异常裸抛），统一抛 AdapterConnectException 供上层分型展示；
    // envelope 解析走 T1 纯函数 gatewayEnvelopeFailure。target 契约 =
    // 「网关族 host:port」。
    final target = '${connection.host}:${connection.port}';

    try {
      // 1) 已有镜像映射 → 验证注册仍存在（server 换库/重置后 id 可能失效）。
      //    映射复用信任注册时凭据（注册前已经草稿测试验证）。
      final mapped = await _lookupServerIdMapping(connection.id);
      if (mapped != null) {
        final known = await _registeredTypes(server);
        final mappedType = known[mapped];
        if (mappedType != null && mappedType == _wireDbType) {
          _serverConnId = mapped;
          return true;
        }
        AppLogger.w(
          adapterName,
          mappedType == null
              ? 'mapped serverConnId $mapped not found on server, re-registering'
              : 'mapped serverConnId $mapped type mismatch '
                    '(registered=$mappedType, want $_wireDbType), re-registering',
        );
      }

      // 2) 凭据草稿测试（对齐裸连接 connect 的「真连」语义——凭据错误时
      //    connect 失败即抛，而非注册成功把失败推迟到首次查询）。
      final testResp = await _sendNoBody(
        'POST',
        '/api/gw/connections/test',
        body: _draftBody(connection),
      );
      final testBody = jsonDecode(testResp.body) as Map<String, dynamic>;
      if (testBody['ok'] != true) {
        AppLogger.w(
          adapterName,
          'gateway credential test failed: ${testBody['error']}',
        );
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
    } on MySqlGatewayException catch (e) {
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
        _sendNoBody(
          'DELETE',
          '/api/gw/executions/$executionId',
        ).catchError((_) => http.Response('', 500)),
      );
    }
    _serverConnId = null;
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
  Future<void> beginTransaction() async {
    throw UnsupportedError(
      'MySQL 族网关模式暂不支持手动事务（T29 临时下线：server 每语句独立连接，'
      'BEGIN/COMMIT 无法跨执行保持；恢复路径：旧 /api/db/:conn_id/txn/* '
      'pinned session 或未来 /api/gw pinned session）',
    );
  }

  @override
  Future<void> commit() async {
    throw UnsupportedError('MySQL 族网关模式暂不支持手动事务（T29 临时下线）');
  }

  @override
  Future<void> rollback() async {
    throw UnsupportedError('MySQL 族网关模式暂不支持手动事务（T29 临时下线）');
  }

  // ==========================================================================
  // 查询执行（SSE 流式全量聚合）
  // ==========================================================================

  /// 解析 `USE <db>` 语句（MySQL 族切库）。仅匹配「整句单 USE」形态
  /// （允许反引号/尾分号/空白），解析不出返回 null 走正常网关执行。
  static final RegExp _useRe = RegExp(
    r'^\s*USE\s+(?:`([^`]+)`|([A-Za-z0-9_\$#]+))\s*;?\s*$',
    caseSensitive: false,
  );

  String? _parseUseStatement(String sql) {
    final m = _useRe.firstMatch(sql);
    if (m == null) return null;
    return m.group(1) ?? m.group(2);
  }

  @override
  Future<QueryResult> executeQuery(String sql, {String? database}) async {
    // feature 039 只读守卫——query-tab SQL + sidebar/AI DDL 经此处汇聚。
    guardReadOnlyQuery(sql, operation: 'executeQuery');
    _assertConnected();

    // T29 — USE 拦截：网关每语句独立连接，裸发 USE 无法保持会话态（旧裸
    // 连接的 USE 影响后续语句）。这里先发给网关验证库存在（未知库 1049
    // 照常报错），成功后更新本地记录库，后续查询经 database 字段路由。
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
    // 超时来源与裸连接版一致（extra['timeout'] 秒 → 网关 timeoutMs；缺省
    // 用 server 默认 gw_query_timeout_secs）。超时由 server
    // statement_timeout 强制，SSE error(TIMEOUT) 上抛，不静默成功。
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
      } on MySqlGatewayException catch (e) {
        // T29 — stale 库自愈：当前库被 drop（或外部删除）后，带 database
        // 路由的每语句建连会 1049 → CONNECTION_FAILED。裸连接时代连接存活
        // 仅失 schema；这里清掉本地记录库并无库重试一次（真·连接故障时
        // 重试同样失败，错误原样上抛，无静默吞错）。
        if (e.code == 'CONNECTION_FAILED' &&
            effectiveDb != null &&
            effectiveDb.isNotEmpty) {
          AppLogger.w(
            adapterName,
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
    } on MySqlGatewayException catch (e) {
      // 传输/连接级失败 → 触发 onDisconnect（对齐裸连接版 onClose 语义；
      // SQL 错误（DB_ERROR 等）不撕连接）。
      if (e.code == 'CONNECTION_FAILED' || e.code == 'NOT_FOUND') {
        onDisconnect?.call();
      }
      rethrow;
    } on http.ClientException catch (e) {
      onDisconnect?.call();
      throw MySqlGatewayException(
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
    // T031 JSON 列识别数据源（旧裸连接 0xf5 通道的替代）；只收 json 族。
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
                (columnTypes ??= {})[columns[i]] = 'json';
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
          throw MySqlGatewayException(
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
      throw const MySqlGatewayException(
        'CONNECTION_FAILED',
        'gateway SSE stream ended without a complete event',
      );
    }
    if (truncated) {
      AppLogger.w(
        adapterName,
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

    // MySQL 的 EXPLAIN 是普通语句前缀（非 SS 的会话级 SHOWPLAN 开关），
    // 网关单语句模型下直接可用。
    return await executeQuery('EXPLAIN $sql');
  }

  // ==========================================================================
  // Schema 发现（自裸连接版逐行迁入，SQL 与解析零改动）
  // ==========================================================================

  /// MySQL 族「schema」= 数据库（information_schema.SCHEMATA）。
  ///
  /// 注意：刻意**不** implements SchemaAwareAdapter——该 marker 是 PG/SS
  /// 多 schema UI 路径的门（sidebar/getDatabaseInfo 按 `is SchemaAwareAdapter`
  /// 分流），旧裸连接版 MySQLBaseAdapter 也未实现；MySQL 族保持平面
  /// database 树。下方 getCurrentSchema/setSearchPath 仅为基类默认之外的
  /// 便捷方法，非 marker 实现。
  @override
  Future<List<String>> getSchemas({String? database}) => getDatabases();

  String? getCurrentSchema() => _currentConnection?.database;

  Future<void> setSearchPath(List<String> schemas) async {
    if (!isConnected) throw Exception('未连接到数据库');
    if (schemas.isNotEmpty) {
      await useDatabase(schemas.first);
    }
  }

  @override
  Future<void> setSchema(String schemaName) async {
    await setSearchPath([schemaName]);
  }

  @override
  Future<List<String>> getDatabases() async {
    if (!isConnected) throw Exception('未连接到数据库');

    // catalog 级查询不带当前库路由——当前库可能刚被 drop（bare-conn 时代
    // 连接仍在；网关模型下 stale default 会让每语句建连直接 1049）。
    final results = await executeQuery('SHOW DATABASES', database: '');
    // 过滤系统库——对齐 T29 前 _SchemaManager.getDatabases 裸连接分支的
    // 排除口径（sidebar 库列表不展示引擎内部库）。
    const systemDbs = {
      'information_schema',
      'performance_schema',
      'mysql',
      'sys',
    };
    return results.rows
        .map((row) => row['Database'] as String)
        .where((db) => !systemDbs.contains(db))
        .toList();
  }

  @override
  Future<void> useDatabase(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // 网关无本地连接可切换——记录目标库，后续执行经 query 的 database
    // 字段路由（server 每语句按 defaultDatabase/database 选库）。裸连接版
    // 的 USE 语句在独立连接模型下无对应操作。
    if (_currentConnection?.database == dbName) {
      return;
    }
    if (_currentConnection != null) {
      _currentConnection = _currentConnection!.copyWith(database: dbName);
    }
  }

  @override
  Future<List<String>> getTables() async {
    if (!isConnected) throw Exception('未连接到数据库');

    // SHOW FULL TABLES 返回 Table_type 列，过滤掉视图
    // 注意：某些 MySQL 版本返回小写的 'base table'
    final results = await executeQuery('SHOW FULL TABLES');
    final tables = <String>[];
    for (final row in results.rows) {
      final values = row.values.toList();
      if (values.length >= 2) {
        final tableType = (values[1] as String).toLowerCase();
        if (tableType == 'base table') {
          tables.add(values[0] as String);
        }
      }
    }
    return tables;
  }

  @override
  Future<List<DbTableMetadata>> getTablesWithMetadata({
    String? database,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = database ?? _currentConnection?.database;
    final results = await executeQuery(
      'SHOW TABLE STATUS${dbName != null ? ' FROM `$dbName`' : ''}',
    );

    // 先解析 SHOW TABLE STATUS 结果
    var metadataList = results.rows
        .map((row) {
          final dataLength = parseInt(row['Data_length']);
          final indexLength = parseInt(row['Index_length']);
          final dataSize = dataLength != null && indexLength != null
              ? dataLength + indexLength
              : null;
          final rowCount = parseInt(row['Rows']);
          return DbTableMetadata(
            name: row['Name']?.toString() ?? '',
            engine: row['Engine']?.toString(),
            rowCount: rowCount,
            dataSize: dataSize,
            comment: row['Comment']?.toString(),
            createTime: parseDateTime(row['Create_time']),
            updateTime: parseDateTime(row['Update_time']),
            isApproximateCount: true,
          );
        })
        .where((m) => m.name.isNotEmpty)
        .toList();

    return metadataList;
  }

  @override
  Future<DbTableMetadata> getTableMetadata(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = _currentConnection?.database;
    final results = await executeQuery(
      'SHOW TABLE STATUS${dbName != null ? ' FROM `$dbName`' : ''} WHERE Name = ${SqlEscapeUtils.escapeString(tableName)}',
    );
    if (results.rows.isEmpty) return DbTableMetadata(name: tableName);
    final row = results.rows.first;
    final dataLength = parseInt(row['Data_length']);
    final indexLength = parseInt(row['Index_length']);
    return DbTableMetadata(
      name: row['Name']?.toString() ?? tableName,
      engine: row['Engine']?.toString(),
      rowCount: parseInt(row['Rows']),
      dataSize: dataLength != null && indexLength != null
          ? dataLength + indexLength
          : null,
      comment: row['Comment']?.toString(),
      createTime: parseDateTime(row['Create_time']),
      updateTime: parseDateTime(row['Update_time']),
    );
  }

  static int? parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Future<List<String>> getViews() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = _currentConnection?.database ?? 'mysql';
    final results = await executeQuery('''
      SELECT TABLE_NAME
      FROM INFORMATION_SCHEMA.VIEWS
      WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
    ''');
    return results.rows.map((row) => row['TABLE_NAME'] as String).toList();
  }

  @override
  Future<List<String>> getProcedures() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = _currentConnection?.database ?? 'mysql';
    final results = await executeQuery('''
      SELECT ROUTINE_NAME
      FROM INFORMATION_SCHEMA.ROUTINES
      WHERE ROUTINE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
        AND ROUTINE_TYPE = 'PROCEDURE'
    ''');
    return results.rows.map((row) => row['ROUTINE_NAME'] as String).toList();
  }

  @override
  Future<List<String>> getFunctions() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = _currentConnection?.database ?? 'mysql';
    final results = await executeQuery('''
      SELECT ROUTINE_NAME
      FROM INFORMATION_SCHEMA.ROUTINES
      WHERE ROUTINE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
        AND ROUTINE_TYPE = 'FUNCTION'
    ''');
    return results.rows.map((row) => row['ROUTINE_NAME'] as String).toList();
  }

  @override
  Future<List<String>> getEvents() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = _currentConnection?.database ?? 'mysql';
    final results = await executeQuery('''
      SELECT EVENT_NAME
      FROM INFORMATION_SCHEMA.EVENTS
      WHERE EVENT_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
    ''');
    return results.rows.map((row) => row['EVENT_NAME'] as String).toList();
  }

  @override
  Future<List<DbTrigger>> getTriggers() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = _currentConnection?.database ?? 'mysql';
    final results = await executeQuery('''
      SELECT TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_TIMING, ACTION_STATEMENT
      FROM INFORMATION_SCHEMA.TRIGGERS
      WHERE TRIGGER_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
    ''');
    return results.rows
        .map(
          (row) => DbTrigger(
            name: row['TRIGGER_NAME'] as String? ?? '',
            event: row['EVENT_MANIPULATION'] as String? ?? '',
            table: row['EVENT_OBJECT_TABLE'] as String? ?? '',
            timing: row['ACTION_TIMING'] as String? ?? '',
            statement: row['ACTION_STATEMENT'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<List<DbColumn>> getTableColumns(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = _currentConnection?.database ?? 'mysql';
    final results = await executeQuery('''
      SELECT
        COLUMN_NAME,
        DATA_TYPE,
        CHARACTER_MAXIMUM_LENGTH,
        IS_NULLABLE,
        COLUMN_DEFAULT,
        COLUMN_KEY,
        EXTRA
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
        AND TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
      ORDER BY ORDINAL_POSITION
    ''');

    final columns = <DbColumn>[];
    for (final row in results.rows) {
      String type = row['DATA_TYPE'] as String;
      if (row['CHARACTER_MAXIMUM_LENGTH'] != null) {
        type += '(${row['CHARACTER_MAXIMUM_LENGTH']})';
      }

      final columnKey = row['COLUMN_KEY'] as String?;
      final isPrimaryKey = columnKey == 'PRI';
      final isNullable = (row['IS_NULLABLE'] as String) == 'YES';

      columns.add(
        DbColumn(
          name: row['COLUMN_NAME'] as String,
          type: type,
          isPrimaryKey: isPrimaryKey,
          isNullable: isNullable,
          defaultValue: row['COLUMN_DEFAULT']?.toString(),
        ),
      );
    }

    return columns;
  }

  @override
  Future<List<DbIndex>> getTableIndexes(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = _currentConnection?.database ?? 'mysql';

    // 获取外键约束名，用于在索引列表中明确标识外键索引
    final fkResults = await executeQuery('''
      SELECT DISTINCT CONSTRAINT_NAME
      FROM information_schema.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
        AND TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
        AND REFERENCED_TABLE_NAME IS NOT NULL
    ''');
    final fkNames = <String>{};
    for (final row in fkResults.rows) {
      fkNames.add(row['CONSTRAINT_NAME']?.toString() ?? '');
    }

    final results = await executeQuery('''
      SHOW INDEX FROM ${SqlEscapeUtils.escapeMySqlIdentifier(dbName)}.${SqlEscapeUtils.escapeMySqlIdentifier(tableName)}
    ''');

    final indexMap = <String, List<String>>{};
    final uniqueSet = <String>{};

    for (final row in results.rows) {
      final indexName = row['Key_name'] as String;
      final columnName = row['Column_name'] as String;
      final isUnique = int.parse(row['Non_unique'].toString()) == 0;

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
            isForeignKey: fkNames.contains(entry.key),
          ),
        )
        .toList();
  }

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      // 使用 SHOW CREATE TABLE 解析外键（比 information_schema 更可靠）
      final result = await executeQuery(
        'SHOW CREATE TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)}',
      );
      if (result.rows.isEmpty) return [];
      final createSql = result.rows.first['Create Table']?.toString() ?? '';
      return SqlParser.parseForeignKeys(createSql, tableName);
    } catch (e) {
      AppLogger.e(adapterName, 'getForeignKeys failed', e);
      return [];
    }
  }

  /// 反向外键快路径：information_schema 单查（KEY_COLUMN_USAGE 按
  /// REFERENCED_TABLE_NAME 反查 + REFERENTIAL_CONSTRAINTS 取 ON DELETE/UPDATE
  /// 动作），避免基类默认实现 O(表数) 次 SHOW CREATE TABLE 扫描。
  @override
  Future<List<ForeignKey>> getReferencingForeignKeys(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      final db = currentConnection?.database;
      if (db == null || db.isEmpty) {
        return await super.getReferencingForeignKeys(tableName);
      }
      final results = await executeQuery('''
        SELECT
          kcu.CONSTRAINT_NAME,
          kcu.TABLE_NAME,
          kcu.COLUMN_NAME,
          kcu.REFERENCED_COLUMN_NAME,
          rc.DELETE_RULE,
          rc.UPDATE_RULE
        FROM information_schema.KEY_COLUMN_USAGE kcu
        LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS rc
          ON rc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
          AND rc.CONSTRAINT_SCHEMA = kcu.CONSTRAINT_SCHEMA
        WHERE kcu.TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(db)}
          AND kcu.REFERENCED_TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
          AND kcu.REFERENCED_COLUMN_NAME IS NOT NULL
        ORDER BY kcu.TABLE_NAME, kcu.CONSTRAINT_NAME, kcu.ORDINAL_POSITION
      ''');

      return results.rows
          .map(
            (row) => ForeignKey(
              name: row['CONSTRAINT_NAME']?.toString() ?? '',
              table: row['TABLE_NAME']?.toString() ?? '',
              column: row['COLUMN_NAME']?.toString() ?? '',
              referencedTable: tableName,
              referencedColumn: row['REFERENCED_COLUMN_NAME']?.toString() ?? '',
              onUpdate: row['UPDATE_RULE']?.toString(),
              onDelete: row['DELETE_RULE']?.toString(),
            ),
          )
          .toList();
    } catch (e) {
      AppLogger.e(
        adapterName,
        'getReferencingForeignKeys failed, fallback to default scan',
        e,
      );
      return await super.getReferencingForeignKeys(tableName);
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

    final results = await executeQuery('SELECT VERSION() as version');
    return {'version': results.rows.first['version'], 'database': 'MySQL'};
  }

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('''
      SELECT
        DEFAULT_CHARACTER_SET_NAME as charset,
        DEFAULT_COLLATION_NAME as collation
      FROM INFORMATION_SCHEMA.SCHEMATA
      WHERE SCHEMA_NAME = ${SqlEscapeUtils.escapeString(dbName)}
    ''');

    if (results.rows.isEmpty) return null;

    final row = results.rows.first;
    return {'charset': row['charset'], 'collation': row['collation']};
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

    try {
      String sql =
          'CREATE DATABASE ${SqlEscapeUtils.escapeMySqlIdentifier(dbName)}';
      if (options != null) {
        if (options['charset'] != null) {
          sql += ' CHARACTER SET ${options['charset']}';
        }
        if (options['collation'] != null) {
          sql += ' COLLATE ${options['collation']}';
        }
      }
      await executeQuery(sql);
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropDatabase(String dbName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropDatabase');
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      await executeQuery(
        'DROP DATABASE ${SqlEscapeUtils.escapeMySqlIdentifier(dbName)}',
      );
      // 裸连接语义对齐：drop 当前库后连接存活但无 schema——网关模型下清掉
      // 本地记录库，避免后续每语句建连带 stale default 直接 1049。
      if (_currentConnection?.database == dbName) {
        _clearRecordedDatabase();
      }
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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
            String def =
                '${SqlEscapeUtils.escapeMySqlIdentifier(col.name)} ${col.type}';
            if (col.isPrimaryKey) def += ' PRIMARY KEY';
            if (!col.isNullable) def += ' NOT NULL';
            if (col.defaultValue != null) def += ' DEFAULT ${col.defaultValue}';
            return def;
          })
          .join(', ');

      String sql =
          'CREATE TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} ($columnDefs)';
      await executeQuery(sql);
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropTable(String tableName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropTable');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await executeQuery(
        'DROP TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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
        'RENAME TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(oldName)} TO ${SqlEscapeUtils.escapeMySqlIdentifier(newName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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
      await executeQuery(
        'TRUNCATE TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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

    final escapedTable = SqlEscapeUtils.escapeMySqlIdentifier(tableName);
    if (cursorColumn != null && cursorValue != null) {
      final escapedColumn = SqlEscapeUtils.escapeMySqlIdentifier(cursorColumn);
      return await executeQuery(
        'SELECT * FROM $escapedTable WHERE $escapedColumn > ${SqlEscapeUtils.escapeString(cursorValue.toString())} ORDER BY $escapedColumn LIMIT $limit',
      );
    }
    return await executeQuery(
      'SELECT * FROM $escapedTable LIMIT $limit OFFSET $offset',
    );
  }

  @override
  Future<int> getTableRowCount(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = (await executeQuery(
      'SELECT COUNT(*) as count FROM ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)}',
    )).rows.first['count'];
    return int.parse(results.toString());
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
          'ADD COLUMN ${SqlEscapeUtils.escapeMySqlIdentifier(column.name)} ${column.type}';
      if (!column.isNullable) def += ' NOT NULL';
      if (column.defaultValue != null) def += ' DEFAULT ${column.defaultValue}';

      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} $def',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} DROP COLUMN ${SqlEscapeUtils.escapeMySqlIdentifier(columnName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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
      String def =
          'MODIFY COLUMN ${SqlEscapeUtils.escapeMySqlIdentifier(newColumn.name)} ${newColumn.type}';
      if (!newColumn.isNullable) def += ' NOT NULL';
      if (newColumn.defaultValue != null)
        def += ' DEFAULT ${newColumn.defaultValue}';

      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} $def',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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
      // 获取原列的类型信息
      final columns = await getTableColumns(tableName);
      final oldColumn = columns.firstWhere(
        (c) => c.name == oldColumnName,
        orElse: () => throw Exception('列 "$oldColumnName" 不存在'),
      );

      String def =
          'CHANGE COLUMN ${SqlEscapeUtils.escapeMySqlIdentifier(oldColumnName)} ${SqlEscapeUtils.escapeMySqlIdentifier(newColumnName)} ${oldColumn.type}';
      if (!oldColumn.isNullable) def += ' NOT NULL';
      if (oldColumn.defaultValue != null)
        def += ' DEFAULT ${oldColumn.defaultValue}';
      if (oldColumn.isPrimaryKey) def += ' PRIMARY KEY';

      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} $def',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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
      final colNames = columns
          .map((c) => SqlEscapeUtils.escapeMySqlIdentifier(c))
          .join(', ');
      final uniqueStr = unique ? 'UNIQUE ' : '';
      await executeQuery(
        'CREATE ${uniqueStr}INDEX ${SqlEscapeUtils.escapeMySqlIdentifier(indexName)} ON ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} ($colNames)',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropIndex(String tableName, String indexName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropIndex');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      await executeQuery(
        'DROP INDEX ${SqlEscapeUtils.escapeMySqlIdentifier(indexName)} ON ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '操作失败', e);
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
    sb.writeln('-- Generated by DBMaster MySQL');
    sb.writeln('-- Date: ${DateTime.now().toIso8601String()}');
    sb.writeln();

    // useDatabase 在网关形态下是路由上下文切换（记录目标库，后续执行经
    // query 的 database 字段路由）——导出后恢复原库即可，无会话副作用。
    final oldDb = _currentConnection?.database;
    await useDatabase(dbName);

    final tables = await getTables();

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
          ? 'CREATE TABLE `$table` (${fks.map((fk) => 'FOREIGN KEY (`${fk.column}`) REFERENCES `${fk.referencedTable}` (`${fk.referencedColumn}`)').join(', ')})'
          : 'CREATE TABLE `$table` (id INT)';
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

    if (oldDb != null) {
      await useDatabase(oldDb);
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
    buf.writeln('CREATE TABLE `$tableName` (');

    final pkColumns = columns.where((c) => c.isPrimaryKey).toList();
    final hasCompositePk = pkColumns.length > 1;
    final filteredIndexes = indexes.where((i) => i.name != 'PRIMARY').toList();

    final parts = <String>[];
    for (final col in columns) {
      String def = '  `${col.name}` ${col.type}';
      if (col.isPrimaryKey && !hasCompositePk) def += ' PRIMARY KEY';
      if (!col.isNullable) def += ' NOT NULL';
      if (col.defaultValue != null) def += ' DEFAULT ${col.defaultValue}';
      parts.add(def);
    }
    if (hasCompositePk) {
      final pkColList = pkColumns.map((c) => '`${c.name}`').join(', ');
      parts.add('  PRIMARY KEY ($pkColList)');
    }
    for (final idx in filteredIndexes) {
      final unique = idx.isUnique ? 'UNIQUE ' : '';
      final colList = idx.columns.map((c) => '`$c`').join(', ');
      parts.add('  ${unique}INDEX `${idx.name}` ($colList)');
    }
    for (final fk in foreignKeys) {
      parts.add(
        '  FOREIGN KEY (`${fk.column}`) REFERENCES `${fk.referencedTable}` (`${fk.referencedColumn}`)',
      );
    }
    buf.writeln(parts.join(',\n'));
    buf.write(');');
    return buf.toString();
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
      AppLogger.e(adapterName, '操作失败', e);
      rethrow;
    }
  }

  // ==========================================================================
  // 字符集/排序规则
  // ==========================================================================

  @override
  Future<List<String>> getCharsets() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('SHOW CHARACTER SET');
    return results.rows.map((row) => row['Charset'] as String).toList();
  }

  @override
  Future<List<Map<String, String>>> getCollations({String? charset}) async {
    if (!isConnected) throw Exception('未连接到数据库');

    String sql = 'SHOW COLLATION';
    if (charset != null) {
      // charset 是标识符，MySQL 的 SHOW COLLATION 支持 LIKE 模式，需转义单引号
      sql += ' LIKE ${SqlEscapeUtils.escapeString('$charset%')}';
    }

    final results = await executeQuery(sql);
    return results.rows
        .map(
          (row) => {
            'name': row['Collation'] as String,
            'charset': row['Charset'] as String,
          },
        )
        .toList();
  }

  // ==========================================================================
  // T005 — ProcessListAdapter implementation
  // ==========================================================================

  @override
  Future<List<ProcessInfo>> getProcessList() async {
    if (!isConnected) return [];
    final results = await executeQuery('SHOW PROCESSLIST');
    return results.rows.map((row) {
      return ProcessInfo(
        id: int.tryParse(row['Id']?.toString() ?? '') ?? 0,
        user: row['User']?.toString() ?? '',
        host: row['Host']?.toString() ?? '',
        database: row['db']?.toString() ?? '',
        command: row['Command']?.toString() ?? '',
        time: int.tryParse(row['Time']?.toString() ?? '') ?? 0,
        state: row['State']?.toString() ?? '',
        info: row['Info']?.toString(),
      );
    }).toList();
  }

  @override
  Future<bool> killProcess(int processId) async {
    if (!isConnected) return false;
    try {
      await executeQuery('KILL CONNECTION $processId');
      return true;
    } catch (e) {
      AppLogger.e(adapterName, 'Failed to kill process $processId', e);
      return false;
    }
  }

  // ==========================================================================
  // T006 — ReplicationAdapter implementation
  // ==========================================================================

  @override
  Future<ReplicationStatus?> getReplicationStatus() async {
    if (!isConnected) return null;
    try {
      final results = await executeQuery('SHOW SLAVE STATUS');
      if (results.rows.isEmpty) return null;
      return ReplicationStatus.fromMap(results.rows.first);
    } catch (e) {
      AppLogger.d(adapterName, 'SHOW SLAVE STATUS failed: $e');
      return null;
    }
  }

  // ==========================================================================
  // T007 — Engine-specific helper methods
  // ==========================================================================

  Future<Map<String, dynamic>?> getEngineStatus() async {
    if (!isConnected) return null;
    try {
      final results = await executeQuery('SHOW ENGINE INNODB STATUS');
      if (results.rows.isEmpty) return null;
      final row = results.rows.first;
      return {
        'engine': row['Engine']?.toString() ?? 'InnoDB',
        'status': row['Status']?.toString() ?? '',
      };
    } catch (e) {
      AppLogger.d(adapterName, 'SHOW ENGINE INNODB STATUS failed: $e');
      return null;
    }
  }

  /// Extended table properties query returning Row Format and Create Options
  Future<Map<String, dynamic>?> getExtendedTableProperties(
    String tableName,
  ) async {
    if (!isConnected) return null;
    try {
      final dbName = _currentConnection?.database;
      if (dbName == null) return null;
      final sql =
          '''
        SELECT ROW_FORMAT, CREATE_OPTIONS
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = '${dbName.replaceAll("'", "\\'")}'
          AND TABLE_NAME = '${tableName.replaceAll("'", "\\'")}'
      ''';
      final results = await executeQuery(sql);
      if (results.rows.isEmpty) return null;
      final row = results.rows.first;
      return {
        'rowFormat': row['ROW_FORMAT']?.toString(),
        'createOptions': row['CREATE_OPTIONS']?.toString(),
      };
    } catch (e) {
      AppLogger.d(adapterName, 'getExtendedTableProperties failed: $e');
      return null;
    }
  }

  // ==========================================================================
  // Phase D — JsonAdapter for JSON column detection
  // ==========================================================================

  @override
  Future<List<String>> getJsonColumns(String tableName) async {
    if (!isConnected) return [];
    try {
      final dbName = _currentConnection?.database;
      if (dbName == null || dbName.isEmpty) return [];
      final results = await executeQuery('''
        SELECT COLUMN_NAME
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
          AND TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
          AND DATA_TYPE = 'json'
        ORDER BY ORDINAL_POSITION
      ''');
      return results.rows
          .map((r) => r['COLUMN_NAME']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (e) {
      AppLogger.e(adapterName, 'getJsonColumns($tableName) failed', e);
      return [];
    }
  }

  @override
  Future<bool> isJsonColumn(String tableName, String columnName) async {
    if (!isConnected) return false;
    try {
      final dbName = _currentConnection?.database;
      if (dbName == null || dbName.isEmpty) return false;
      final results = await executeQuery('''
        SELECT DATA_TYPE
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
          AND TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
          AND COLUMN_NAME = ${SqlEscapeUtils.escapeString(columnName)}
      ''');
      if (results.rows.isNotEmpty) {
        final dt = results.rows.first['DATA_TYPE']?.toString() ?? '';
        return dt == 'json';
      }
    } catch (e) {
      AppLogger.e(adapterName, 'isJsonColumn failed', e);
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
        'MySQL 族网关模式需要已连接的 dbmaster server（未检测到会话；'
        'embedded 模式下请确认 dbmaster-server.exe 随包可用）',
      );
    }
    return server;
  }

  /// 网关 wire 的小写 db_type 字符串（§4.5）。mysql/doris 查
  /// [kGatewayWireDbTypes]；四个薄适配成员（oceanbase/tidb/starrocks/
  /// mariadb）尚未进该表，wire 值与枚举名一致，回退 `databaseType.name`
  /// （server 侧白名单已含，见 gateway handlers.rs SUPPORTED_DB_TYPES）。
  String get _wireDbType =>
      kGatewayWireDbTypes[databaseType] ?? databaseType.name;

  /// 连接草稿体（网关 wire：camelCase，mysql 族走 host/port/凭据族）。
  /// 注：draft/test body（server `ConnectionDraftBody`）无 charset/timezone/
  /// TLS 字段——charset/timezone 只在注册体（`RegisterBody`）携带；
  /// `extra['useSSL']` 因无 TLS 字段暂不透传（见文件头「行为边界」）。
  /// server 侧 SSH 隧道对象（extra['ssh']）存在时原样透传。
  Map<String, dynamic> _draftBody(DatabaseConnection connection) => {
    'dbType': _wireDbType,
    'host': connection.host,
    'port': connection.port,
    'username': connection.username ?? '',
    'password': connection.password ?? '',
    if (connection.database != null && connection.database!.isNotEmpty)
      'defaultDatabase': connection.database,
    'ssh': ?gatewaySshWire(connection),
  };

  /// 现场注册（凭据入 server vault），返回 serverConnId。
  /// charset/timezone 自连接 `extra` 透传（server 侧按 profile 在每语句
  /// 连接上做 SET NAMES / SET time_zone 会话初始化；Doris 自动跳过
  /// time_zone，见 automation mysql_family.rs）。
  Future<String> _registerConnection(DatabaseConnection connection) async {
    final charset = connection.extra?['charset'] as String?;
    final timezone = connection.extra?['timezone'] as String?;
    final resp = await _sendNoBody(
      'POST',
      '/api/gw/connections',
      body: {
        ..._draftBody(connection),
        'name': connection.name,
        'readOnly': connection.readOnly,
        if (charset != null && charset.isNotEmpty) 'charset': charset,
        if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
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
      AppLogger.w(adapterName, 'list gateway connections failed: $e');
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

  /// 4xx/5xx JSON 错误体 → [MySqlGatewayException]（非 JSON 保 HTTP 概要）。
  MySqlGatewayException _decodeErrResponse(int status, String text) {
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
    return MySqlGatewayException(code, message);
  }

  /// 草稿 test envelope（`{ok:false, error:...}`）→ [ConnectionFailure]
  /// （连接失败 UX 重构 T9a）。容错（任务书允许自决项）：error 为 Map 时取
  /// code/engineCode/message；为字符串时整串作 message（server 草稿 test
  /// 端点凭据失败即此形状，无稳定码 → errorCode=''）；缺失/类型异常 →
  /// unknown 兜底。分型映射走 T1 纯函数 gatewayEnvelopeFailure，不在
  /// adapter 内散写 if-chain。T12c：顶层 `error_code` 稳定码（snake_case
  /// 新键）优先于旧 `error.code`，缺省回落既有解析。
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
      AppLogger.w(adapterName, 'failed to save server-id map: $e');
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

// ============================================================================
// 具体适配器（类名与旧 mysql_adapter.dart / doris_adapter.dart 一致——
// T29 后续 shim 阶段直接换底层基类即可）
// ============================================================================

/// MySQL 适配器（网关壳实现：执行走 T27 网关 API）。
class MySQLAdapter extends MySQLGatewayBaseAdapter {
  @override
  String get adapterName => 'MySQLAdapter';

  @override
  DatabaseType get databaseType => DatabaseType.mysql;
}

/// Doris 适配器（网关壳实现）—— 方言覆写自旧 `doris_adapter.dart`
/// 逐行迁入，SQL 构造零改动。
class DorisAdapter extends MySQLGatewayBaseAdapter {
  @override
  String get adapterName => 'DorisAdapter';

  @override
  DatabaseType get databaseType => DatabaseType.doris;

  @override
  Future<List<String>> getTables() async {
    if (!isConnected) throw Exception('未连接到数据库');

    // Doris SHOW FULL TABLES 返回的 Table_type 不一定是 'base table'，
    // 因此只要不是 'view' 就视为表。
    final results = await executeQuery('SHOW FULL TABLES');
    final tables = <String>[];
    for (final row in results.rows) {
      final values = row.values.toList();
      if (values.length >= 2) {
        final tableType = (values[1] as String).toLowerCase();
        if (tableType != 'view') {
          tables.add(values[0] as String);
        }
      }
    }
    return tables;
  }

  // ==========================================================================
  // 程序性对象 —— Doris 不支持
  // ==========================================================================

  @override
  Future<List<String>> getProcedures() async => [];

  @override
  Future<List<String>> getFunctions() async => [];

  @override
  Future<List<String>> getEvents() async => [];

  @override
  Future<List<DbTrigger>> getTriggers() async => [];

  // ==========================================================================
  // 表元数据 —— 带精确行数优化和 Doris 特有的键类型判断
  // ==========================================================================

  @override
  Future<List<DbTableMetadata>> getTablesWithMetadata({
    String? database,
  }) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = database ?? currentConnection?.database;
    final results = await executeQuery(
      'SHOW TABLE STATUS${dbName != null ? ' FROM `$dbName`' : ''}',
    );

    var metadataList = results.rows
        .map((row) {
          final dataLength = MySQLGatewayBaseAdapter.parseInt(
            row['Data_length'],
          );
          final indexLength = MySQLGatewayBaseAdapter.parseInt(
            row['Index_length'],
          );
          final dataSize = dataLength != null && indexLength != null
              ? dataLength + indexLength
              : null;
          return DbTableMetadata(
            name: row['Name']?.toString() ?? '',
            engine: row['Engine']?.toString(),
            rowCount: MySQLGatewayBaseAdapter.parseInt(row['Rows']),
            dataSize: dataSize,
            comment: row['Comment']?.toString(),
            createTime: MySQLGatewayBaseAdapter.parseDateTime(
              row['Create_time'],
            ),
            updateTime: MySQLGatewayBaseAdapter.parseDateTime(
              row['Update_time'],
            ),
            isApproximateCount: true,
          );
        })
        .where((m) => m.name.isNotEmpty)
        .toList();

    // 对小表（< 1MB）执行 COUNT(*) 获取精确行数
    final smallTables = metadataList
        .where((m) => (m.dataSize ?? 0) < 1024 * 1024)
        .toList();
    if (smallTables.isNotEmpty) {
      const batchSize = 5;
      for (var i = 0; i < smallTables.length; i += batchSize) {
        final batch = smallTables.skip(i).take(batchSize);
        final futures = batch.map((m) async {
          try {
            final countResult = await executeQuery(
              'SELECT COUNT(*) as cnt FROM `${m.name}`',
            );
            final exactCount = int.tryParse(
              countResult.rows.first['cnt']?.toString() ?? '',
            );
            return (name: m.name, exactCount: exactCount);
          } catch (_) {
            return (name: m.name, exactCount: null);
          }
        });
        final batchResults = await Future.wait(futures);
        final countMap = {
          for (final r in batchResults)
            if (r.exactCount != null) r.name: r.exactCount!,
        };
        metadataList = metadataList.map((m) {
          final exact = countMap[m.name];
          if (exact != null) {
            return m.copyWith(rowCount: exact, isApproximateCount: false);
          }
          return m;
        }).toList();
      }
    }

    return metadataList;
  }

  @override
  Future<List<DbColumn>> getTableColumns(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = currentConnection?.database ?? 'doris';
    final results = await executeQuery('''
      SELECT
        COLUMN_NAME,
        DATA_TYPE,
        CHARACTER_MAXIMUM_LENGTH,
        IS_NULLABLE,
        COLUMN_DEFAULT,
        COLUMN_KEY,
        EXTRA
      FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
        AND TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
      ORDER BY ORDINAL_POSITION
    ''');

    final columns = <DbColumn>[];
    for (final row in results.rows) {
      String type = row['DATA_TYPE'] as String;
      if (row['CHARACTER_MAXIMUM_LENGTH'] != null) {
        type += '(${row['CHARACTER_MAXIMUM_LENGTH']})';
      }

      final columnKey = row['COLUMN_KEY'] as String?;
      // Doris COLUMN_KEY: DUP (duplicate), AGG (aggregate), UNI (unique), PRI (primary)
      final isPrimaryKey =
          columnKey != null &&
          (columnKey == 'PRI' ||
              columnKey == 'UNI' ||
              columnKey == 'AGG' ||
              columnKey == 'DUP');
      final isNullable = (row['IS_NULLABLE'] as String) == 'YES';

      columns.add(
        DbColumn(
          name: row['COLUMN_NAME'] as String,
          type: type,
          isPrimaryKey: isPrimaryKey,
          isNullable: isNullable,
          defaultValue: row['COLUMN_DEFAULT']?.toString(),
        ),
      );
    }

    return columns;
  }

  @override
  Future<List<DbIndex>> getTableIndexes(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    final dbName = currentConnection?.database ?? 'doris';

    // 获取外键约束名，用于在索引列表中明确标识外键索引
    final fkResults = await executeQuery('''
      SELECT DISTINCT CONSTRAINT_NAME
      FROM information_schema.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
        AND TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
        AND REFERENCED_TABLE_NAME IS NOT NULL
    ''');
    final fkNames = <String>{};
    for (final row in fkResults.rows) {
      fkNames.add(row['CONSTRAINT_NAME']?.toString() ?? '');
    }

    final results = await executeQuery('''
      SHOW INDEX FROM `$dbName`.`$tableName`
    ''');

    final indexMap = <String, List<String>>{};
    final uniqueSet = <String>{};

    for (final row in results.rows) {
      final indexName = row['Key_name'] as String;
      final columnName = row['Column_name'] as String;
      final isUnique = int.parse(row['Non_unique'].toString()) == 0;

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
            isForeignKey: fkNames.contains(entry.key),
          ),
        )
        .toList();
  }

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      // 使用 SHOW CREATE TABLE 解析外键（比 information_schema 更可靠）
      final result = await executeQuery(
        'SHOW CREATE TABLE `${currentConnection?.database ?? 'doris'}`.`$tableName`',
      );
      if (result.rows.isEmpty) return [];
      final createSql = result.rows.first['Create Table']?.toString() ?? '';
      return SqlParser.parseForeignKeys(createSql, tableName);
    } catch (e) {
      AppLogger.d(adapterName, 'getForeignKeys failed: $e');
      return [];
    }
  }

  // ==========================================================================
  // 查询执行 —— 旧裸连接版的 Doris executeQuery 覆写（useDatabase 切换）
  // 不再需要：基类把 database 作为网关 query 参数路由（见文件头）。
  // ==========================================================================

  // ==========================================================================
  // DDL —— Doris 特有语法
  // ==========================================================================

  @override
  Future<bool> createDatabase(
    String dbName, {
    Map<String, dynamic>? options,
  }) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'createDatabase');
    if (!isConnected) throw Exception('未连接到数据库');

    try {
      String sql = 'CREATE DATABASE IF NOT EXISTS `$dbName`';
      // Doris 不支持 CHARACTER SET 和 COLLATE，记录日志但忽略
      if (options != null) {
        if (options['charset'] != null) {
          AppLogger.d(
            adapterName,
            'Doris 不支持 CREATE DATABASE CHARACTER SET，忽略 charset 选项',
          );
        }
        if (options['collation'] != null) {
          AppLogger.d(
            adapterName,
            'Doris 不支持 CREATE DATABASE COLLATE，忽略 collation 选项',
          );
        }
      }
      await executeQuery(sql);
      return true;
    } catch (e) {
      AppLogger.d(adapterName, '创建数据库失败: $e');
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
      // 支持表模型选择（DUP/UNIQUE/PK/AGGREGATE）+ 结构化分桶；键列前置（Doris 要求键列为列前缀）
      final model = (options?['model']?.toString() ?? 'DUPLICATE')
          .toUpperCase();
      final isAggModel = model == 'AGGREGATE';
      final aggregateColumns =
          options?['aggregateColumns'] as Map<String, dynamic>?;

      // 键列：isPrimaryKey 列（保持顺序）；无则回落首列
      final keyCols = columns.where((c) => c.isPrimaryKey).toList();
      final keyColNames = keyCols.isNotEmpty
          ? keyCols.map((c) => '`${c.name}`').join(', ')
          : '`${columns.first.name}`';
      final keyColForDist = keyCols.isNotEmpty
          ? keyCols.first.name
          : columns.first.name;

      // 列定义：键列前置，非键列其后（Doris 键模型要求键列为列前缀）
      final ordered = <DbColumn>[
        ...columns.where((c) => c.isPrimaryKey),
        ...columns.where((c) => !c.isPrimaryKey),
      ];
      final columnDefs = ordered
          .map((col) {
            String def = '`${col.name}` ${col.type}';
            // AGGREGATE 值列（非键）聚合函数紧跟类型（Doris 语法：TYPE AGGFUNC [NOT NULL] [DEFAULT]）
            if (isAggModel && !col.isPrimaryKey) {
              final agg = (aggregateColumns?[col.name] ?? 'SUM').toString();
              def += ' $agg';
            }
            if (!col.isNullable) def += ' NOT NULL';
            if (col.defaultValue != null) {
              def += ' DEFAULT ${_formatDefaultValue(col.defaultValue!)}';
            }
            return def;
          })
          .join(', ');

      String sql = 'CREATE TABLE `$tableName` ($columnDefs)';

      // Doris 无 MySQL 式存储引擎概念，忽略任何 engine 选项
      // （曾在这里追加 ENGINE=... 会导致建表失败）

      // 模型关键字子句
      // 注：Doris 无独立 PRIMARY KEY 关键字——「主键模型」= UNIQUE KEY + Merge-on-Write 属性
      final isPkModel = model == 'PRIMARY KEY';
      final modelClause = isAggModel
          ? 'AGGREGATE KEY($keyColNames)'
          : (model == 'UNIQUE' || isPkModel
                ? 'UNIQUE KEY($keyColNames)'
                : 'DUPLICATE KEY($keyColNames)');
      sql += ' $modelClause';

      // RANGE 分区（有配置时在 modelClause 后、distribution 前发）
      if (options != null && options['partitionColumn'] != null) {
        final partCol = options['partitionColumn'].toString();
        final parts = options['partitions'] as List<dynamic>?;
        if (parts != null && parts.isNotEmpty) {
          final partDefs = parts
              .map((p) {
                final m = p as Map<String, dynamic>;
                return "PARTITION `${m['name']}` VALUES LESS THAN ('${m['lessThan']}')";
              })
              .join(', ');
          sql += ' PARTITION BY RANGE(`$partCol`) ($partDefs)';
        }
      }

      // 分桶：hashColumn/buckets 优先；其次 distribution(verbatim)；再否则自动默认
      if (options != null && options['hashColumn'] != null) {
        final hc = options['hashColumn'].toString();
        final bk = options['buckets']?.toString() ?? '1';
        sql += ' DISTRIBUTED BY HASH(`$hc`) BUCKETS $bk';
      } else if (options != null && options['distribution'] != null) {
        sql += ' ${options['distribution']}';
      } else {
        sql += ' DISTRIBUTED BY HASH(`$keyColForDist`) BUCKETS 1';
      }

      // 透传 options['comment'] 为表注释（放在 DISTRIBUTED BY 之前、PROPERTIES 之前，符合 Doris 语法）
      if (options != null && options['comment'] != null) {
        sql +=
            " COMMENT '${options['comment'].toString().replaceAll("'", "\\'")}'";
      }

      // PROPERTIES（主键模型 = UNIQUE KEY + Merge-on-Write）
      if (options != null && options['properties'] != null) {
        sql += ' PROPERTIES (${options['properties']})';
      } else {
        final propEntries = <String>['"replication_num" = "1"'];
        if (isPkModel) {
          propEntries.add('"enable_unique_key_merge_on_write" = "true"');
        }
        sql += ' PROPERTIES (${propEntries.join(', ')})';
      }

      await executeQuery(sql);
      return true;
    } catch (e) {
      AppLogger.d(adapterName, '创建表失败: $e');
      return false;
    }
  }

  @override
  Future<List<String>> getJsonColumns(String tableName) async {
    if (!isConnected) return [];
    try {
      final dbName = currentConnection?.database;
      if (dbName == null || dbName.isEmpty) return [];
      final results = await executeQuery('''
        SELECT COLUMN_NAME
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
          AND TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
          AND UPPER(DATA_TYPE) = 'JSON'
        ORDER BY ORDINAL_POSITION
      ''');
      return results.rows
          .map((r) => r['COLUMN_NAME']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (e) {
      AppLogger.e(adapterName, 'getJsonColumns($tableName) failed', e);
      return [];
    }
  }

  @override
  Future<bool> isJsonColumn(String tableName, String columnName) async {
    if (!isConnected) return false;
    try {
      final dbName = currentConnection?.database;
      if (dbName == null || dbName.isEmpty) return false;
      final results = await executeQuery('''
        SELECT DATA_TYPE
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = ${SqlEscapeUtils.escapeString(dbName)}
          AND TABLE_NAME = ${SqlEscapeUtils.escapeString(tableName)}
          AND COLUMN_NAME = ${SqlEscapeUtils.escapeString(columnName)}
      ''');
      if (results.rows.isNotEmpty) {
        final dt = results.rows.first['DATA_TYPE']?.toString() ?? '';
        return dt.toUpperCase() == 'JSON';
      }
    } catch (e) {
      AppLogger.e(adapterName, 'isJsonColumn failed', e);
    }
    return false;
  }

  /// 格式化 Doris 列默认值
  ///
  /// 数字、NULL、CURRENT_TIMESTAMP 保持原样；其余按字符串字面量转义并加单引号。
  static String _formatDefaultValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return "''";
    final upper = trimmed.toUpperCase();
    if (upper == 'NULL') return 'NULL';
    if (upper == 'CURRENT_TIMESTAMP') return 'CURRENT_TIMESTAMP';
    if (num.tryParse(trimmed) != null) return trimmed;
    return SqlEscapeUtils.escapeString(trimmed);
  }

  // ==========================================================================
  // DDL 方言覆写 —— Doris 语法与 MySQL 不同（现代 Doris 3.x 能力）
  // ==========================================================================

  @override
  Future<bool> renameTable(String oldName, String newName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'renameTable');
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      // Doris 用 ALTER TABLE ... RENAME（非 MySQL 的 RENAME TABLE ... TO ...）
      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(oldName)} RENAME ${SqlEscapeUtils.escapeMySqlIdentifier(newName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '重命名表失败', e);
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
      // Doris 用 ALTER TABLE ... RENAME COLUMN old new（非 MySQL 的 CHANGE COLUMN）
      // 需 light_schema_change=true（Doris 2.0+ 默认开启）
      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} RENAME COLUMN ${SqlEscapeUtils.escapeMySqlIdentifier(oldColumnName)} ${SqlEscapeUtils.escapeMySqlIdentifier(newColumnName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '重命名列失败', e);
      return false;
    }
  }

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
      // Doris 索引语义为倒排/bitmap（非 MySQL b-tree）；默认 INVERTED，忽略 unique
      final colNames = columns
          .map((c) => SqlEscapeUtils.escapeMySqlIdentifier(c))
          .join(', ');
      await executeQuery(
        'CREATE INDEX ${SqlEscapeUtils.escapeMySqlIdentifier(indexName)} ON ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} ($colNames) USING INVERTED',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '创建索引失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropIndex(String tableName, String indexName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropIndex');
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      // Doris 删索引走 ALTER TABLE ... DROP INDEX（非 MySQL 的 DROP INDEX ... ON ...）
      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} DROP INDEX ${SqlEscapeUtils.escapeMySqlIdentifier(indexName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '删除索引失败', e);
      return false;
    }
  }

  // Doris DDL 覆写 —— 替代基类 MySQL 方言，使用 _formatDefaultValue 引用默认值
  // 并增加键列保护（Doris 不允许删除唯一键列、不允许随意修改键列类型）。

  @override
  Future<bool> addColumn(String tableName, DbColumn column) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'addColumn');
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      String def =
          'ADD COLUMN ${SqlEscapeUtils.escapeMySqlIdentifier(column.name)} ${column.type}';
      if (!column.isNullable) def += ' NOT NULL';
      if (column.defaultValue != null) {
        def += ' DEFAULT ${_formatDefaultValue(column.defaultValue!)}';
      }
      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} $def',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '添加列失败', e);
      return false;
    }
  }

  @override
  Future<bool> dropColumn(String tableName, String columnName) async {
    // feature 039 只读守卫（双保险；executeQuery 已兜住）。
    guardReadOnly(operation: 'dropColumn');
    if (!isConnected) throw Exception('未连接到数据库');
    try {
      // Guard: Doris 表至少需要一个键列，防止删除最后一个键列
      try {
        final columns = await getTableColumns(tableName);
        final targetCol = columns
            .where((c) => c.name == columnName)
            .firstOrNull;
        if (targetCol != null && targetCol.isPrimaryKey) {
          final keyCount = columns.where((c) => c.isPrimaryKey).length;
          if (keyCount <= 1) {
            AppLogger.w(adapterName, 'Doris 表至少需要一个键列，无法删除唯一的键列: $columnName');
            return false;
          }
        }
      } catch (_) {
        // 获取列信息失败时降级为直接尝试（Doris 服务端会拒绝非法操作）
      }
      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} DROP COLUMN ${SqlEscapeUtils.escapeMySqlIdentifier(columnName)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '删除列失败', e);
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
      // Guard: 键列类型修改受限，记录警告（Doris 仅允许有限类型拓宽）
      try {
        final columns = await getTableColumns(tableName);
        final oldCol = columns
            .where((c) => c.name == oldColumnName)
            .firstOrNull;
        if (oldCol != null &&
            oldCol.isPrimaryKey &&
            oldCol.type != newColumn.type) {
          AppLogger.w(
            adapterName,
            'Doris 键列类型修改受限: $oldColumnName ($oldCol.type → ${newColumn.type})',
          );
        }
      } catch (_) {
        // 降级：直接尝试执行
      }
      // Doris MODIFY COLUMN 使用 oldColumnName 定位（不支持 CHANGE COLUMN 改名+改类型）
      String def =
          'MODIFY COLUMN ${SqlEscapeUtils.escapeMySqlIdentifier(oldColumnName)} ${newColumn.type}';
      if (!newColumn.isNullable) def += ' NOT NULL';
      if (newColumn.defaultValue != null) {
        def += ' DEFAULT ${_formatDefaultValue(newColumn.defaultValue!)}';
      }
      await executeQuery(
        'ALTER TABLE ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} $def',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, '修改列失败', e);
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> getServerVersion() async {
    if (!isConnected) throw Exception('未连接到数据库');

    final results = await executeQuery('SELECT VERSION() as version');
    return {'version': results.rows.first['version'], 'database': 'Doris'};
  }

  @override
  Future<String> exportDatabaseStructure(String dbName) async {
    if (!isConnected) throw Exception('未连接到数据库');

    // 逐表 SHOW CREATE TABLE 直出——Doris 返回的即合法可回灌 DDL
    // （含模型关键字 + DISTRIBUTED BY HASH + PROPERTIES），
    // 不再用基类 _buildCreateTableExportSql（MySQL 风格，不可回灌）。
    final sb = StringBuffer();
    sb.writeln('-- Database: $dbName (Doris)');
    sb.writeln('-- Generated by DBMaster Doris');
    sb.writeln('-- Date: ${DateTime.now().toIso8601String()}');
    sb.writeln();

    // useDatabase 在网关形态下是路由上下文切换（见基类注释）。
    final oldDb = currentConnection?.database;
    await useDatabase(dbName);
    try {
      final tables = await getTables();
      for (final table in tables) {
        final escapedTable = SqlEscapeUtils.escapeMySqlIdentifier(table);
        final createResult = await executeQuery(
          'SHOW CREATE TABLE $escapedTable',
        );
        if (createResult.rows.isEmpty) continue;
        final createSql =
            createResult.rows.first['Create Table']?.toString() ?? '';
        if (createSql.isEmpty) continue;
        sb.writeln('-- Table: $table');
        sb.writeln('$createSql;');
        sb.writeln();
      }
    } finally {
      if (oldDb != null && oldDb != dbName) {
        await useDatabase(oldDb);
      }
    }

    return sb.toString();
  }

  // 物化视图发现与管理

  @override
  Future<List<String>> getMaterializedViews() async {
    if (!isConnected) return [];
    try {
      final result = await executeQuery('SHOW MATERIALIZED VIEW');
      return result.rows
          .map((row) => row.values.first?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (e) {
      AppLogger.d(adapterName, 'getMaterializedViews failed: $e');
      return [];
    }
  }

  Future<bool> dropMaterializedView(String name) async {
    if (!isConnected) return false;
    try {
      await executeQuery(
        'DROP MATERIALIZED VIEW IF EXISTS ${SqlEscapeUtils.escapeMySqlIdentifier(name)}',
      );
      return true;
    } catch (e) {
      AppLogger.e(adapterName, 'dropMaterializedView failed', e);
      return false;
    }
  }

  Future<bool> refreshMaterializedView(String name) async {
    if (!isConnected) return false;
    try {
      await executeQuery(
        'REFRESH MATERIALIZED VIEW ${SqlEscapeUtils.escapeMySqlIdentifier(name)} COMPLETE',
      );
      return true;
    } catch (e) {
      // Sync MVs auto-refresh; REFRESH may error — best-effort
      AppLogger.d(adapterName, 'refreshMaterializedView (best-effort): $e');
      return false;
    }
  }

  Future<String> getMaterializedViewDefinition(String name) async {
    if (!isConnected) return '';
    try {
      final result = await executeQuery(
        'SHOW CREATE MATERIALIZED VIEW ${SqlEscapeUtils.escapeMySqlIdentifier(name)}',
      );
      if (result.rows.isEmpty) return '';
      final values = result.rows.first.values.toList();
      return values.length >= 2
          ? values[1].toString()
          : values.first?.toString() ?? '';
    } catch (e) {
      AppLogger.d(adapterName, 'getMaterializedViewDefinition failed: $e');
      return '';
    }
  }
}

// ── MySQL 协议族薄适配四成员（dbx-response M7 T22-T25）──
//
// 客户端零新适配逻辑：四库均走 MySQL wire（网关执行通道），与 server 侧
// 薄适配（automation mysql_family.rs）同构——只声明身份，差异收敛在
// server 网关 profile。wire db_type = 枚举名（kGatewayWireDbTypes 未含
// 四成员，基类 _wireDbType 回退 databaseType.name；server 侧白名单已含）。

/// OceanBase 适配器（MySQL 模式租户口，网关壳）
class OceanbaseAdapter extends MySQLGatewayBaseAdapter {
  @override
  String get adapterName => 'OceanbaseAdapter';

  @override
  DatabaseType get databaseType => DatabaseType.oceanbase;
}

/// TiDB 适配器（网关壳）
class TidbAdapter extends MySQLGatewayBaseAdapter {
  @override
  String get adapterName => 'TidbAdapter';

  @override
  DatabaseType get databaseType => DatabaseType.tidb;
}

/// StarRocks 适配器（FE MySQL 口，网关壳）
class StarrocksAdapter extends MySQLGatewayBaseAdapter {
  @override
  String get adapterName => 'StarrocksAdapter';

  @override
  DatabaseType get databaseType => DatabaseType.starrocks;
}

/// MariaDB 适配器（网关壳）
class MariadbAdapter extends MySQLGatewayBaseAdapter {
  @override
  String get adapterName => 'MariadbAdapter';

  @override
  DatabaseType get databaseType => DatabaseType.mariadb;
}
