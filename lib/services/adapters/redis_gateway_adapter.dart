//! T29 非 SQL 批次（B4，ADR-0006 §2.3/§2.5/§2.7）· Redis 网关壳 adapter。
//!
//! **形态**：与 `mysql/mongodb` 网关壳同构——类名/接口与直连版完全一致
//! （`RedisAdapter`），DatabaseService 工厂与 UI `is RedisAdapter` 强转消费
//! 零改动（铁律 4）。本地不再持有 redis.dart 连接，凭据经网关注册入
//! server vault，执行走 **kind:"redis"** 通道（`POST /api/gw/connections/
//! {id}/query` SSE）。
//!
//! **取代**：原 `redis_adapter.dart`（redis.dart 直连，2,363 行）。
//! `_RedisSafeParser`/`_RedisSafeBinaryParser`/`_authenticateAndSelect`/
//! Pub/Sub 专用双连接全部下线。
//!
//! **旧形状重建（`_commandRaw`）**：server 对白名单结构化命令（SCAN 族/
//! HGETALL/ZRANGE WITHSCORES…）返回语义列行——本壳在边界**重建旧 RESP
//! 形状**（SCAN 族 → `[cursor,[items]]`、成对列 → 平铺数组、单列 → 数组；
//! fallback 单列即整值 JSON）。由此 `RedisResultFormatter` 与全部类型化
//! 方法（getHash 配对/getSet SSCAN 循环/_parseScanResult…）**逐字保留**，
//! workbench/pipeline/事务面板零改动。SCAN 空批由 server 回落 fallback
//! 保真 cursor（否则大库迭代提前终止——server 侧实机钉定）。
//!
//! **行为边界（v1，相对直连版的已知差异）**：
//! - **Pub/Sub 重订式**：server 订阅端点在连接时给定全量 channels/patterns
//!   ——动态订阅/退订由壳**重建整条订阅 SSE**（旧版在同一条专用连接上
//!   增量 sub/unsub）。`pubSubMessageStream` broadcast 形状与
//!   `pubSubSubscribe/Unsubscribe` 签名不变；重订窗口内消息可能丢失
//!   （毫秒级，UI 场景可接受）。
//! - **WATCH/UNWATCH/DISCARD fail-loud**（跨请求连接亲和，对齐 SQL 族事务
//!   先例 + 用户拍板）；`multiExec` 经网关 pipeline `atomic:true`
//!   （server 侧 MULTI/EXEC + QUEUED 校验由 redis-rs pipe.atomic 承担）。
//! - **pipeStart/pipeEnd 为 no-op**：旧版是 redis.dart 的 Nagle 合并优化，
//!   网关模型下无意义（每命令独立 HTTP）；pipeline 面板的批量原子路径
//!   走 multiExec。
//! - **getRawBytes 非真二进制**：server 侧 RESP→JSON 以 utf8-lossy 落字符串
//!   ——非 UTF-8 字节序列的十六进制展示有损（已知边界）。
//! - **db 路由**：`database` 请求参数 = db index（`'db0'`/`'0'` 双格式解析）
//!   ——`useDatabase` record-only；`getDatabaseProperties`/`dropDatabase`
//!   经参数路由目标库（旧版 SELECT 切换）。
//! - **read_only**：server 侧硬执行（静态表 + ACL CAT；READONLY engineCode）
//!   + 本地 guardReadOnly 双保险（与旧版一致保留）。
//! - **timeout**：`extra['timeout']` 秒 → 网关 timeoutMs（缺省 30s，旧版
//!   `.timeout` 同款）。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/database_models.dart';
import '../../models/redis_function.dart';
import '../../models/redis_geo_member.dart';
import '../../models/redis_key_models.dart';
import '../../models/redis_pubsub_message.dart';
import '../../utils/app_logger.dart';
import '../database_abstract.dart';
import '../redis_result_formatter.dart';
import '../server_connection.dart';
import 'ai_adapter_mixin.dart';

/// 网关查询错误（SSE error 事件 / 4xx 前置校验失败）。`code` 对齐 c01 §4.4
/// 稳定码集，`engineCode` 透传引擎原始码（Redis 为错误前缀，如
/// WRONGTYPE/READONLY）。与 `MySqlGatewayException` 等同形。
class RedisGatewayException implements Exception {
  final String code;
  final String message;
  final String? engineCode;

  const RedisGatewayException(this.code, this.message, {this.engineCode});

  @override
  String toString() {
    final eng = engineCode == null ? '' : ' (engine $engineCode)';
    return '[$code]$eng $message';
  }
}

/// 增量 SCAN 分页缓存的一页进度（某 pattern 下已收集的 keys + 游标）。
class _RedisScanPage {
  final List<String> keys = [];
  int cursor = 0;
  bool exhausted = false;
}

/// Redis 适配器（网关壳实现：执行走 kind:"redis" 命令/pipeline 通道）。
class RedisAdapter extends DatabaseAdapter
    with AiAdapterMixin, DisconnectAware {
  /// serverConnId 映射表 key（与 ConnectionProvider / DbGatewayService 三方
  /// 共享同一 SharedPreferences key）。
  static const String _kServerIdMapKey = 'connection_server_id_map';

  static const String _tag = 'RedisAdapter';

  /// 测试注入的 HTTP 客户端（null = 每请求新建）。
  @visibleForTesting
  http.Client? httpClient;

  String? _serverConnId;
  DatabaseConnection? _currentConnection;

  /// 当前 db index（useDatabase record-only 记录位；命令经 database 参数
  /// 路由——'db0'/'0' 双格式解析）。
  int _dbIndex = 0;

  /// 在途执行的取消句柄（disconnect / 显式取消用）。
  String? _inFlightExecutionId;

  /// 增量 SCAN 分页缓存（key = `'<dbIndex>:<pattern>'`）。真分页取数：
  /// 要多少扫多少（首页只发一轮 SCAN），翻页沿游标续扫；跨调用期间
  /// key 集合稳定（SCAN 游标迭代的常规语义——期间新增 key 可能错过，
  /// 与其它 Redis GUI 行为一致），写命令经 [_invalidateScanPagesIfWrite]
  /// 失效。
  final Map<String, _RedisScanPage> _scanPages = {};

  // ── Pub/Sub（订阅转发 SSE 的重订式消费，§2.5）──

  StreamController<PubSubMessage>? _pubSubController;
  final Set<String> _subscribedChannels = {};
  final Set<String> _subscribedPatterns = {};
  StreamSubscription<String>? _subLineSub;
  http.Client? _subClient;
  bool _subOwnsClient = false;
  int _subGeneration = 0;

  RedisAdapter();

  @override
  bool get isConnected => _serverConnId != null;

  @override
  DatabaseType get databaseType => DatabaseType.redis;

  @override
  String getDefaultBrowseQuery(String tableName, {int limit = 100}) {
    return 'SCAN 0 MATCH "$tableName:*" COUNT $limit';
  }

  @override
  DatabaseConnection? get currentConnection => _currentConnection;

  /// feature 039 D3：刷新连接 readOnly（运行时开关实时生效；server 侧
  /// 注册行 read_only 为写命令硬执行位——改 readOnly 需重连重新注册才对
  /// server 生效，与 SQL 族壳一致）。
  @override
  void updateReadOnly(bool value) {
    _currentConnection = _currentConnection?.copyWith(readOnly: value);
  }

  @override
  bool get supportsSchemaOperations => false;

  // ==========================================================================
  // 连接管理（网关：注册/复用 serverConnId，无本地 Redis 连接）
  // ==========================================================================

  @override
  Future<bool> connect(DatabaseConnection connection) async {
    _currentConnection = connection;
    _dbIndex = int.tryParse(
          connection.database?.replaceAll('db', '') ?? '0',
        ) ??
        0;
    final server = _requireServerSession();
    final prevServerConnId = _serverConnId;

    // 1) 已有镜像映射 → 验证注册仍存在且 dbType 匹配。
    final mapped = await _lookupServerIdMapping(connection.id);
    if (mapped != null) {
      final known = await _registeredTypes(server);
      if (known[mapped] == 'redis') {
        _serverConnId = mapped;
        _currentConnection = connection.copyWith(
          connected: true,
          connectedAt: DateTime.now(),
          database: 'db$_dbIndex',
        );
        if (_serverConnId != prevServerConnId) _scanPages.clear();
        return true;
      }
      AppLogger.w(_tag, 'mapped serverConnId $mapped invalid, re-registering');
    }

    // 2) 凭据草稿测试（对齐旧版 connect 的「真连」语义）。
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

    // 3) 现场注册 + 写回映射。
    final registered = await _registerConnection(connection);
    await _rememberServerIdMapping(connection.id, registered);
    _serverConnId = registered;
    _currentConnection = connection.copyWith(
      connected: true,
      connectedAt: DateTime.now(),
      database: 'db$_dbIndex',
    );
    if (_serverConnId != prevServerConnId) _scanPages.clear();
    return true;
  }

  @override
  Future<void> disconnect() async {
    // 联动释放订阅流（对齐旧版 disposePubSub）。
    await disposePubSub();
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
    _currentConnection = null;
    _scanPages.clear();
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
  // 执行核心（kind:"redis" → SSE 聚合 → 旧 RESP 形状重建）
  // ==========================================================================

  int? get _timeoutMsFromExtra {
    final secs = _currentConnection?.extra?['timeout'];
    return secs is num ? (secs * 1000).round() : null;
  }

  /// 旧版缺省 30s（send_object 无内建超时，executeQuery 显式 .timeout）。
  int get _timeoutMs => _timeoutMsFromExtra ?? 30000;

  /// 经网关执行一条 Redis 命令，返回聚合 [QueryResult]（meta 可能是
  /// fallback 单列或语义列，见 `_reconstructLegacy`）。
  Future<QueryResult> _runRedisCommand(
    List<String> command, {
    String? database,
    int? timeoutMs,
  }) async {
    final server = _requireServerSession();
    _assertConnected();
    final startTime = DateTime.now();
    final executionId = _newExecutionId();
    _inFlightExecutionId = executionId;

    final uri = Uri.parse(
      '${server.serverUrl}/api/gw/connections/$_serverConnId/query',
    );
    final token = await server.getAccessToken();
    final body = jsonEncode({
      'kind': 'redis',
      'command': command,
      'database': ?database,
      'rowLimit': 10000,
      'timeoutMs': timeoutMs ?? _timeoutMs,
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.stream.bytesToString();
        throw _decodeErrResponse(response.statusCode, text);
      }
      final lines =
          await response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
      final result = _parseSse(lines, startTime: startTime);
      _invalidateScanPagesIfWrite([command]);
      return result;
    } on RedisGatewayException catch (e) {
      if (e.code == 'CONNECTION_FAILED' || e.code == 'NOT_FOUND') {
        onDisconnect?.call();
      }
      rethrow;
    } on http.ClientException catch (e) {
      onDisconnect?.call();
      throw RedisGatewayException(
        'CONNECTION_FAILED',
        'gateway unreachable (${e.message})',
      );
    } finally {
      if (_inFlightExecutionId == executionId) {
        _inFlightExecutionId = null;
      }
      if (ownsClient) client.close();
    }
  }

  /// SSE 事件块解析（与 SQL 族壳同构）。
  QueryResult _parseSse(List<String> lines, {required DateTime startTime}) {
    List<String> columns = const [];
    final rows = <Map<String, dynamic>>[];
    bool sawComplete = false;
    int? serverElapsedMs;

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
            if (raw is List) rows.add(_positionalRowToMap(raw, columns));
          }
        case 'complete':
          sawComplete = true;
          serverElapsedMs = (chunk['elapsedMs'] as num?)?.toInt();
        case 'error':
          throw RedisGatewayException(
            chunk['code']?.toString() ?? 'DB_ERROR',
            chunk['message']?.toString() ?? 'redis command failed',
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
    }
    handleEvent(pendingEvent, pendingData);

    if (!sawComplete) {
      throw const RedisGatewayException(
        'CONNECTION_FAILED',
        'gateway SSE stream ended without a complete event',
      );
    }
    return QueryResult(
      columns: columns,
      rows: rows,
      executionTime:
          serverElapsedMs ??
          DateTime.now().difference(startTime).inMilliseconds,
    );
  }

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

  /// **旧 RESP 形状重建**：语义列行 → 旧版 `send_object` 返回形状。
  /// - fallback 单列 `result` → 整值（scalar/array/null 的 JSON 形态）；
  /// - SCAN 族（cursor 列打头）→ `[cursor, [items...]]`（HSCAN/ZSCAN 的
  ///   多元素列平铺）；
  /// - 成对列（field/value、member/score、parameter/value）→ 平铺
  ///   `[k,v,k,v,…]`；
  /// - 单列列表（key/member/element/value）→ `[v1,v2,…]`。
  dynamic _reconstructLegacy(QueryResult result) {
    final cols = result.columns;
    if (cols.length == 1 && cols[0] == 'result') {
      return result.rows.isEmpty ? null : result.rows.first['result'];
    }
    if (cols.isNotEmpty && cols[0] == 'cursor') {
      if (result.rows.isEmpty) return ['0', <dynamic>[]];
      final cursor = result.rows.first['cursor']?.toString() ?? '0';
      final items = <dynamic>[];
      for (final row in result.rows) {
        for (var i = 1; i < cols.length; i++) {
          items.add(row[cols[i]]);
        }
      }
      return [cursor, items];
    }
    if (cols.length == 2) {
      final flat = <dynamic>[];
      for (final row in result.rows) {
        flat.add(row[cols[0]]);
        flat.add(row[cols[1]]);
      }
      return flat;
    }
    if (cols.length == 1) {
      return [for (final row in result.rows) row[cols[0]]];
    }
    return result.rows;
  }

  /// 通用命令执行（旧 `send_object` 的网关替身）：guard + db 路由 + 旧形状
  /// 重建。类型化方法与 runCommand 的统一底座。
  Future<dynamic> _commandRaw(
    List<String> args, {
    String? database,
    int? timeoutMs,
  }) async {
    final result = await _runRedisCommand(
      args,
      database: database ?? '$_dbIndex',
      timeoutMs: timeoutMs,
    );
    return _reconstructLegacy(result);
  }

  /// 单请求 pipeline 命令数上限。server 行限 10000 行/请求（pipeline 模式
  /// 每命令一行），400 让单块响应体与失败重试的爆炸半径可控。
  static const int _pipelineChunkSize = 400;

  /// pipeline 批量入口：非 atomic 时按 [_pipelineChunkSize] 自动分块（多块
  /// 顺序发出、结果按序拼接）。网关模型下每命令原为一请求，批量底座
  /// （getTableData/export/Top-N 等）据此把「每 key 数请求」收敛为「每页
  /// 常数请求」——per-user 600 req/min 限流下不再打爆配额。MULTI/EXEC
  /// 必须单请求原子执行，永不分块。
  Future<List<dynamic>> _pipelineRaw(
    List<List<String>> commands, {
    bool atomic = false,
  }) async {
    if (atomic || commands.length <= _pipelineChunkSize) {
      return _pipelineRawSingle(commands, atomic: atomic);
    }
    final out = <dynamic>[];
    for (var i = 0; i < commands.length; i += _pipelineChunkSize) {
      final end = min(i + _pipelineChunkSize, commands.length);
      out.addAll(await _pipelineRawSingle(commands.sublist(i, end)));
    }
    return out;
  }

  /// 单请求 pipeline（网关 `pipeline` 通道；atomic = MULTI/EXEC）→ 按序
  /// 结果数组（server 每命令一行 `[index, result]`，按 index 归位）。
  Future<List<dynamic>> _pipelineRawSingle(
    List<List<String>> commands, {
    bool atomic = false,
  }) async {
    final server = _requireServerSession();
    _assertConnected();
    final startTime = DateTime.now();
    final executionId = _newExecutionId();
    _inFlightExecutionId = executionId;

    final uri = Uri.parse(
      '${server.serverUrl}/api/gw/connections/$_serverConnId/query',
    );
    final token = await server.getAccessToken();
    final body = jsonEncode({
      'kind': 'redis',
      'pipeline': commands,
      if (atomic) 'atomic': true,
      'database': '$_dbIndex',
      'rowLimit': 10000,
      'timeoutMs': _timeoutMs,
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.stream.bytesToString();
        throw _decodeErrResponse(response.statusCode, text);
      }
      final lines =
          await response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
      final result = _parseSse(lines, startTime: startTime);
      // pipeline 行 = [index, result]，按 index 归位。
      final out = List<dynamic>.filled(commands.length, null);
      for (final row in result.rows) {
        final idx = (row['index'] as num?)?.toInt();
        if (idx != null && idx >= 0 && idx < out.length) {
          out[idx] = row['result'];
        }
      }
      _invalidateScanPagesIfWrite(commands);
      return out;
    } on RedisGatewayException catch (e) {
      if (e.code == 'CONNECTION_FAILED' || e.code == 'NOT_FOUND') {
        onDisconnect?.call();
      }
      rethrow;
    } on http.ClientException catch (e) {
      onDisconnect?.call();
      throw RedisGatewayException(
        'CONNECTION_FAILED',
        'gateway unreachable (${e.message})',
      );
    } finally {
      if (_inFlightExecutionId == executionId) {
        _inFlightExecutionId = null;
      }
      if (ownsClient) client.close();
    }
  }

  // ==========================================================================
  // 库/命名空间发现
  // ==========================================================================

  @override
  Future<List<String>> getDatabases() async {
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final result = await _commandRaw(['CONFIG', 'GET', 'databases']);
      int dbCount = 16;
      if (result is List && result.length >= 2) {
        dbCount = int.tryParse(result[1].toString()) ?? 16;
      }
      if (dbCount > 256) dbCount = 256;
      return List.generate(dbCount, (i) => 'db$i');
    } catch (e) {
      return List.generate(16, (i) => 'db$i');
    }
  }

  @override
  Future<void> useDatabase(String dbName) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    // record-only：命令经 database 参数路由（见文件头「行为边界」）。
    // db 切换 = 另一个 keyspace，游标缓存作废；同 db 重复切换保留——
    // Keys/TTL 两个侧边栏节点共享同一份 SCAN 采样依赖这一点。
    final newIdx = int.tryParse(dbName.replaceAll('db', '')) ?? 0;
    final dbChanged = newIdx != _dbIndex;
    _dbIndex = newIdx;
    _currentConnection = _currentConnection?.copyWith(database: dbName);
    if (dbChanged) _scanPages.clear();
  }

  /// Get databases that have keys (non-empty)
  Future<List<String>> getNonEmptyDatabases() async {
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final info = (await _commandRaw(['INFO', 'keyspace']))?.toString() ?? '';
      final nonEmptyDbs = <String>[];

      for (final line in info.split('\n')) {
        if (line.startsWith('db')) {
          final dbParts = line.split(':');
          if (dbParts.length >= 2) {
            final dbName = dbParts[0];
            final meta = dbParts[1];
            final keysMatch = RegExp(r'keys=(\d+)').firstMatch(meta);
            if (keysMatch != null) {
              final keyCount = int.tryParse(keysMatch.group(1)!) ?? 0;
              if (keyCount > 0) {
                nonEmptyDbs.add(dbName);
              }
            }
          }
        }
      }
      return nonEmptyDbs;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<String>> getTables() async {
    if (!isConnected) throw Exception('未连接到 Redis');

    final keys = await scanKeys();
    final namespaces = <String>{};

    for (final keyStr in keys) {
      final colonIndex = keyStr.indexOf(':');
      if (colonIndex > 0) {
        namespaces.add(keyStr.substring(0, colonIndex));
      } else {
        namespaces.add('(无前缀)');
      }
    }

    final result = namespaces.toList()..sort();
    if (result.isEmpty) result.add('(无前缀)');
    return result;
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

  Future<List<String>> getAllKeys({String? pattern, int limit = 1000}) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    final keys = await scanKeys(pattern: pattern ?? '*');
    return keys.take(limit).toList();
  }

  /// 获取 key 的类型
  Future<String> getKeyType(String key) async {
    final result = await _commandRaw(['TYPE', key]);
    return result.toString();
  }

  /// 批量获取 key 类型（pipeline 分块；顺序与入参一致，失败单元 'none'）。
  /// 侧边栏 Keys 节点采样统计的消费口（旧版逐 key TYPE 扇出 → 单请求）。
  Future<List<String>> getKeyTypes(List<String> keys) async {
    if (keys.isEmpty) return const [];
    final results = await _pipelineRaw([
      for (final key in keys) ['TYPE', key],
    ]);
    return [for (final r in results) r?.toString() ?? 'none'];
  }

  /// 批量获取 TTL（pipeline 分块；顺序与入参一致，解析失败 -2）。
  /// TTL 面板采样消费口（旧版逐 key TTL 扇出 → 单请求）。
  Future<List<int>> getTTLs(List<String> keys) async {
    if (keys.isEmpty) return const [];
    final results = await _pipelineRaw([
      for (final key in keys) ['TTL', key],
    ]);
    return [for (final r in results) int.tryParse(r?.toString() ?? '') ?? -2];
  }

  // ==========================================================================
  // 类型化读写（命令映射与旧版逐一对应）
  // ==========================================================================

  Future<String?> getString(String key) async {
    final result = await _commandRaw(['GET', key]);
    return result?.toString();
  }

  Future<bool> setString(String key, String value, {Duration? ttl}) async {
    // feature 039 只读守卫：STRING SET 写路径
    guardReadOnly(operation: 'setString');
    try {
      final cmd = ttl != null
          ? await _commandRaw(['SET', key, value, 'EX', '${ttl.inSeconds}'])
          : await _commandRaw(['SET', key, value]);
      return cmd.toString() == 'OK';
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, String>> getHash(
    String key, {
    int maxFields = 10000,
  }) async {
    final result = await _commandRaw(['HGETALL', key]);
    final map = <String, String>{};
    if (result is! List) return map;
    final limit = result.length.clamp(0, maxFields * 2);
    for (int i = 0; i < limit - 1; i += 2) {
      map[result[i].toString()] = result[i + 1].toString();
    }
    return map;
  }

  Future<List<String>> getList(String key, {int maxElements = 10000}) async {
    final end = maxElements - 1;
    final result = await _commandRaw(['LRANGE', key, '0', '$end']);
    if (result is! List) return [];
    return result.map((e) => e.toString()).toList();
  }

  Future<Set<String>> getSet(String key, {int maxMembers = 10000}) async {
    final members = <String>{};
    var cursor = 0;
    var iterations = 0;
    const maxIterations = 50;
    do {
      final result = await _commandRaw([
        'SSCAN',
        key,
        '$cursor',
        'COUNT',
        '200',
      ]);
      if (result is! List || result.length < 2) break;
      cursor = int.tryParse(result[0].toString()) ?? 0;
      final items = result[1];
      if (items is List) {
        for (final item in items) {
          members.add(item.toString());
          if (members.length >= maxMembers) break;
        }
      }
      iterations++;
    } while (cursor != 0 &&
        iterations < maxIterations &&
        members.length < maxMembers);
    return members;
  }

  Future<List<String>> getZSet(String key, {int maxItems = 10000}) async {
    final end = maxItems - 1;
    final result = await _commandRaw(['ZRANGE', key, '0', '$end']);
    if (result is! List) return [];
    return result.map((e) => e.toString()).toList();
  }

  Future<List<Map<String, String>>> getZSetWithScores(
    String key, {
    int maxItems = 10000,
  }) async {
    final end = maxItems - 1;
    final result = await _commandRaw([
      'ZRANGE',
      key,
      '0',
      '$end',
      'WITHSCORES',
    ]);
    final list = <Map<String, String>>[];
    if (result is! List) return list;
    for (int i = 0; i < result.length - 1; i += 2) {
      list.add({
        'member': result[i].toString(),
        'score': result[i + 1].toString(),
      });
    }
    return list;
  }

  // ---------------------------------------------------------------------------
  // 轻量级元数据读取（O(1)，不会阻塞 Redis）
  // ---------------------------------------------------------------------------

  Future<int> getStringLength(String key) async {
    final result = await _commandRaw(['STRLEN', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<int> getHashLength(String key) async {
    final result = await _commandRaw(['HLEN', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<Map<String, String>> getHashPreview(
    String key, {
    int maxFields = 3,
  }) async {
    final result = await _commandRaw([
      'HSCAN',
      key,
      '0',
      'COUNT',
      '${maxFields * 2}',
    ]);
    final map = <String, String>{};
    if (result is! List || result.length < 2) return map;
    final items = result[1];
    if (items is! List) return map;
    for (int i = 0; i < items.length - 1 && map.length < maxFields; i += 2) {
      map[items[i].toString()] = items[i + 1].toString();
    }
    return map;
  }

  Future<int> getListLength(String key) async {
    final result = await _commandRaw(['LLEN', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<List<String>> getListPreview(
    String key, {
    int maxElements = 5,
  }) async {
    final end = maxElements - 1;
    final result = await _commandRaw(['LRANGE', key, '0', '$end']);
    if (result is! List) return [];
    return result.map((e) => e.toString()).toList();
  }

  Future<int> getSetLength(String key) async {
    final result = await _commandRaw(['SCARD', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<List<String>> getSetPreview(
    String key, {
    int maxMembers = 5,
  }) async {
    final result = await _commandRaw([
      'SRANDMEMBER',
      key,
      '$maxMembers',
    ]);
    if (result is! List) return [];
    return result.map((e) => e.toString()).toList();
  }

  Future<int> getZSetLength(String key) async {
    final result = await _commandRaw(['ZCARD', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<List<String>> getZSetPreview(
    String key, {
    int maxItems = 5,
  }) async {
    final end = maxItems - 1;
    final result = await _commandRaw(['ZRANGE', key, '0', '$end']);
    if (result is! List) return [];
    return result.map((e) => e.toString()).toList();
  }

  Future<int> getTTL(String key) async {
    final result = await _commandRaw(['TTL', key]);
    return int.tryParse(result.toString()) ?? -2;
  }

  Future<int> getStreamLength(String key) async {
    final result = await _commandRaw(['XLEN', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<List<Map<String, String>>> getStreamEntries(
    String key, {
    int count = 100,
  }) async {
    final result = await _commandRaw([
      'XRANGE',
      key,
      '-',
      '+',
      'COUNT',
      '$count',
    ]);
    if (result is! List) return [];
    final entries = <Map<String, String>>[];
    for (final entry in result) {
      if (entry is! List || entry.length < 2) continue;
      final id = entry[0].toString();
      final fields = entry[1];
      final map = <String, String>{'id': id};
      if (fields is List) {
        for (int i = 0; i < fields.length - 1; i += 2) {
          map[fields[i].toString()] = fields[i + 1].toString();
        }
      }
      entries.add(map);
    }
    return entries;
  }

  // A4 — Stream 写操作 + 消费者组管理(走 runCommand)
  Future<String> streamAdd(
    String key,
    Map<String, String> fields, {
    String id = '*',
  }) async {
    // feature 039 只读守卫：Stream XADD 写路径
    guardReadOnly(operation: 'streamAdd');
    final args = <String>['XADD', key, id];
    fields.forEach((f, v) => args.addAll([f, v]));
    final result = await runCommand(args);
    return result.toString();
  }

  Future<int> streamDelete(String key, List<String> ids) async {
    // feature 039 只读守卫：Stream XDEL 写路径
    guardReadOnly(operation: 'streamDelete');
    if (ids.isEmpty) return 0;
    final result = await runCommand(['XDEL', key, ...ids]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<int> streamTrim(String key, int maxLen) async {
    // feature 039 只读守卫：Stream XTRIM 写路径
    guardReadOnly(operation: 'streamTrim');
    final result = await runCommand(['XTRIM', key, 'MAXLEN', '~', '$maxLen']);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<Map<String, String>> xinfoStream(String key) async {
    final result = await runCommand(['XINFO', 'STREAM', key]);
    return _parseFlatKv(result);
  }

  Future<List<Map<String, String>>> xinfoGroups(String key) async {
    final result = await runCommand(['XINFO', 'GROUPS', key]);
    final groups = <Map<String, String>>[];
    if (result is! List) return groups;
    for (final g in result) {
      if (g is List) groups.add(_parseFlatKv(g));
    }
    return groups;
  }

  Future<bool> streamGroupCreate(
    String key,
    String group, {
    String id = r'$',
  }) async {
    // feature 039 只读守卫：XGROUP CREATE 写路径
    guardReadOnly(operation: 'streamGroupCreate');
    try {
      final result = await runCommand(['XGROUP', 'CREATE', key, group, id]);
      return result == 'OK';
    } catch (_) {
      return false;
    }
  }

  Future<bool> streamGroupDestroy(String key, String group) async {
    // feature 039 只读守卫：XGROUP DESTROY 写路径
    guardReadOnly(operation: 'streamGroupDestroy');
    final result = await runCommand(['XGROUP', 'DESTROY', key, group]);
    return (int.tryParse(result.toString()) ?? 0) > 0;
  }

  /// 解析 Redis 扁平 key-value 数组为 Map(供 XINFO 等复用)。
  Map<String, String> _parseFlatKv(dynamic result) {
    final map = <String, String>{};
    if (result is! List) return map;
    for (var i = 0; i < result.length - 1; i += 2) {
      map[result[i].toString()] = result[i + 1].toString();
    }
    return map;
  }

  Future<int> getBitCount(String key) async {
    final result = await _commandRaw(['BITCOUNT', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  // A1 — Bitmap 读写(GETBIT/SETBIT/BITPOS)
  Future<int> getBit(String key, int offset) async {
    final result = await runCommand(['GETBIT', key, '$offset']);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<int> setBit(String key, int offset, int value) async {
    // feature 039 只读守卫：SETBIT 写路径
    guardReadOnly(operation: 'setBit');
    final result = await runCommand([
      'SETBIT',
      key,
      '$offset',
      value == 0 ? '0' : '1',
    ]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<int> bitPos(String key, int bit) async {
    final result = await runCommand(['BITPOS', key, bit == 0 ? '0' : '1']);
    return int.tryParse(result.toString()) ?? 0;
  }

  // A2 — BITFIELD 复合操作
  Future<List<dynamic>> bitfield(String key, List<String> operations) async {
    // feature 039 只读守卫：BITFIELD 复合写路径
    guardReadOnly(operation: 'bitfield');
    final result = await runCommand(['BITFIELD', key, ...operations]);
    if (result is List) return result;
    return [result];
  }

  /// 获取 key 的内存占用(字节)。[samples] > 0 时传 SAMPLES 子命令。
  Future<int> getMemoryUsage(String key, {int samples = 0}) async {
    try {
      final args = <String>['MEMORY', 'USAGE', key];
      if (samples > 0) args.addAll(['SAMPLES', '$samples']);
      final result = await _commandRaw(args);
      return int.tryParse(result.toString()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<String> memoryDoctor() async {
    try {
      final result = await runCommand(['MEMORY', 'DOCTOR']);
      return result?.toString() ?? '(unavailable)';
    } catch (e) {
      return 'MEMORY DOCTOR unavailable: $e';
    }
  }

  Future<dynamic> memoryStats() async {
    try {
      return await runCommand(['MEMORY', 'STATS']);
    } catch (_) {
      return null;
    }
  }

  Future<String> memoryMallocStats() async {
    try {
      final result = await runCommand(['MEMORY', 'MALLOC-STATS']);
      return result?.toString() ?? '(unavailable)';
    } catch (e) {
      return 'MEMORY MALLOC-STATS unavailable (needs jemalloc): $e';
    }
  }

  // D2 — Top-N 大 key(SCAN 当前 db + MEMORY USAGE,降序,maxScan 上限)。
  // 限流根治：SCAN 单轮 COUNT 1000 + 该批 key 的 MEMORY USAGE 合并为一条
  // pipeline（旧版逐 key 一请求，千级库一次 Top-N 即打爆网关限流）。
  Future<List<Map<String, dynamic>>> getTopKeysByMemory({int limit = 20}) async {
    if (!isConnected) throw Exception('未连接到 Redis');
    try {
      final items = <Map<String, dynamic>>[];
      var cursor = 0;
      int scanned = 0;
      const maxScan = 1000;
      do {
        final result = await runCommand(['SCAN', '$cursor', 'COUNT', '1000']);
        if (result is! List || result.length < 2) break;
        cursor = int.tryParse(result[0].toString()) ?? 0;
        final keys = result[1];
        if (keys is! List) break;
        scanned += keys.length;
        final mems = keys.isEmpty
            ? const <dynamic>[]
            : await _pipelineRaw([
                for (final keyObj in keys)
                  ['MEMORY', 'USAGE', keyObj.toString()],
              ]);
        for (var i = 0; i < keys.length && i < mems.length; i++) {
          final bytes = int.tryParse(mems[i]?.toString() ?? '') ?? 0;
          if (bytes > 0) items.add({'key': keys[i].toString(), 'bytes': bytes});
        }
      } while (cursor != 0 && scanned < maxScan);
      items.sort((a, b) => (b['bytes'] as int).compareTo(a['bytes'] as int));
      return items.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  // D4 — ACL 管理(Redis 6.0+;<6 时各方法友好降级返回空/false)
  Future<List<String>> aclList() async {
    try {
      final r = await runCommand(['ACL', 'LIST']);
      return r is List ? r.map((e) => e.toString()).toList() : [];
    } catch (_) {
      return [];
    }
  }

  Future<String> aclWhoami() async {
    try {
      final r = await runCommand(['ACL', 'WHOAMI']);
      return r?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<List<String>> aclCat([String? category]) async {
    try {
      final args = <String>['ACL', 'CAT'];
      if (category != null) args.add(category);
      final r = await runCommand(args);
      return r is List ? r.map((e) => e.toString()).toList() : [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, String>> aclGetuser(String name) async {
    try {
      final r = await runCommand(['ACL', 'GETUSER', name]);
      final map = <String, String>{};
      if (r is! List) return map;
      for (var i = 0; i < r.length - 1; i += 2) {
        final v = r[i + 1];
        map[r[i].toString()] =
            v is List ? v.map((e) => e.toString()).join(', ') : v.toString();
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<bool> aclSetUser(String name, List<String> rules) async {
    // feature 039 只读守卫：ACL SETUSER 写路径
    guardReadOnly(operation: 'aclSetUser');
    try {
      final r = await runCommand(['ACL', 'SETUSER', name, ...rules]);
      return r == 'OK';
    } catch (_) {
      return false;
    }
  }

  Future<bool> aclDelUser(String name) async {
    // feature 039 只读守卫：ACL DELUSER 写路径
    guardReadOnly(operation: 'aclDelUser');
    try {
      final r = await runCommand(['ACL', 'DELUSER', name]);
      return (int.tryParse(r.toString()) ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  /// 获取 JSON 值（RedisJSON 模块）
  Future<String?> getJson(String key) async {
    try {
      final result = await _commandRaw(['JSON.GET', key]);
      return result?.toString();
    } catch (_) {
      return null;
    }
  }

  /// 获取 Geo 成员（底层为 zset）
  Future<List<String>> getGeo(String key, {int maxItems = 10000}) async {
    final end = maxItems - 1;
    final result = await _commandRaw(['ZRANGE', key, '0', '$end']);
    if (result is! List) return [];
    return result.map((e) => e.toString()).toList();
  }

  Future<Map<String, List<double>>> getGeoPositions(
    String key,
    List<String> members,
  ) async {
    if (members.isEmpty) return {};
    final result = await _commandRaw(['GEOPOS', key, ...members]);
    final map = <String, List<double>>{};
    if (result is! List) return map;
    for (int i = 0; i < result.length && i < members.length; i++) {
      final pos = result[i];
      if (pos is List && pos.length >= 2) {
        final lon = double.tryParse(pos[0].toString()) ?? 0;
        final lat = double.tryParse(pos[1].toString()) ?? 0;
        map[members[i]] = [lon, lat];
      }
    }
    return map;
  }

  // A3 — Geo 写操作(GEOADD/GEODIST,删除用 ZREM)
  Future<int> geoAdd(String key, List<GeoMember> members) async {
    // feature 039 只读守卫：GEOADD 写路径
    guardReadOnly(operation: 'geoAdd');
    if (members.isEmpty) return 0;
    final args = <String>['GEOADD', key];
    for (final m in members) {
      args.addAll([m.lng.toString(), m.lat.toString(), m.name]);
    }
    final result = await runCommand(args);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<double?> geoDist(
    String key,
    String m1,
    String m2, {
    String unit = 'm',
  }) async {
    final result = await runCommand(['GEODIST', key, m1, m2, unit]);
    if (result == null) return null;
    return double.tryParse(result.toString());
  }

  Future<bool> geoRemove(String key, String member) async {
    // feature 039 只读守卫：Geo ZREM 写路径
    guardReadOnly(operation: 'geoRemove');
    final result = await runCommand(['ZREM', key, member]);
    return (int.tryParse(result.toString()) ?? 0) > 0;
  }

  Future<int> getHyperLogLogCount(String key) async {
    final result = await _commandRaw(['PFCOUNT', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  /// 获取 key 的「原始字节」（用于 Bitmap/Bitfield 的十六进制展示）。
  /// **网关边界**：server 侧 RESP→JSON 以 utf8-lossy 落字符串——此处经
  /// utf8 编码回字节，非 UTF-8 序列有损（见文件头「行为边界」）。
  Future<List<int>?> getRawBytes(String key) async {
    final result = await _commandRaw(['GET', key]);
    if (result == null) return null;
    return utf8.encode(result.toString());
  }

  // ==========================================================================
  // 基类元数据退化实现（与旧版一致）
  // ==========================================================================

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
    if (!isConnected) throw Exception('未连接到 Redis');

    return [
      DbColumn(
        name: 'key',
        type: 'STRING',
        isPrimaryKey: true,
        isNullable: false,
      ),
      DbColumn(name: 'type', type: 'STRING', isNullable: false),
      DbColumn(name: 'value', type: 'STRING', isNullable: true),
      DbColumn(name: 'ttl', type: 'INTEGER', isNullable: true),
      DbColumn(name: 'size', type: 'INTEGER', isNullable: true),
    ];
  }

  @override
  Future<List<DbIndex>> getTableIndexes(String tableName) async => [];

  @override
  Future<List<ForeignKey>> getForeignKeys(String tableName) async => [];

  @override
  Future<DbTable> getTableDetails(String tableName) async {
    final columns = await getTableColumns(tableName);
    return DbTable(name: tableName, columns: columns, indexes: []);
  }

  // ==========================================================================
  // 查询执行（_parseCommand → _commandRaw → RedisResultFormatter）
  // ==========================================================================

  @override
  Future<QueryResult> executeQuery(String command, {String? database}) async {
    // feature 039 只读守卫：query-tab 写命令（DEL/SET/FLUSHDB 等）拦截。
    guardReadOnlyQuery(command, operation: 'executeQuery');
    if (!isConnected) throw Exception('未连接到 Redis');

    final startTime = DateTime.now();

    try {
      final parts = _parseCommand(command);
      if (parts.isEmpty) {
        return QueryResult.empty();
      }

      final result = await _commandRaw(
        parts,
        timeoutMs: _timeoutMs,
      );

      // 格式化结果（旧形状重建后，formatter 与直连版完全一致地工作）。
      final rows = _formatResult(
        result,
        parts.isNotEmpty ? parts[0].toUpperCase() : '',
      );
      final columns = rows.isNotEmpty ? rows.first.keys.toList() : ['result'];

      return QueryResult(
        columns: columns,
        rows: rows.isNotEmpty
            ? rows
            : [
                {'result': result?.toString() ?? '(nil)'},
              ],
        executionTime: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      throw Exception('Redis 命令执行失败: $e');
    }
  }

  List<String> _parseCommand(String command) {
    final parts = <String>[];
    var current = StringBuffer();
    var inQuotes = false;
    var quoteChar = '';

    for (int i = 0; i < command.length; i++) {
      final char = command[i];
      if ((char == '"' || char == "'") && !inQuotes) {
        inQuotes = true;
        quoteChar = char;
      } else if (char == quoteChar && inQuotes) {
        inQuotes = false;
        quoteChar = '';
      } else if (char == ' ' && !inQuotes) {
        if (current.isNotEmpty) {
          parts.add(current.toString());
          current = StringBuffer();
        }
      } else {
        current.write(char);
      }
    }

    if (current.isNotEmpty) {
      parts.add(current.toString());
    }

    return parts;
  }

  // C1 — 委托 RedisResultFormatter(供 Workbench/Pipeline/事务器复用)
  List<Map<String, dynamic>> _formatResult(Object? result, String command) {
    return RedisResultFormatter.format(result, command);
  }

  @override
  Future<QueryResult> getExplainPlan(String sql) async {
    return QueryResult(
      columns: ['info'],
      rows: [
        {'info': 'Redis 不支持 EXPLAIN，使用 INFO 命令查看服务器信息'},
      ],
    );
  }

  @override
  Future<Map<String, dynamic>?> getServerVersion() async {
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final result = await _commandRaw(['INFO', 'server']);
      final lines = result.toString().split('\n');
      String? version;
      String? os;
      int? connectedClients;
      String? usedMemory;

      for (final line in lines) {
        if (line.startsWith('redis_version:')) {
          version = line.split(':')[1].trim();
        } else if (line.startsWith('os:')) {
          os = line.split(':')[1].trim();
        } else if (line.startsWith('connected_clients:')) {
          connectedClients = int.tryParse(line.split(':')[1].trim());
        } else if (line.startsWith('used_memory_human:')) {
          usedMemory = line.split(':').skip(1).join(':').trim();
        }
      }

      return {
        'version': version ?? 'unknown',
        'database': 'Redis',
        'os': os,
        'connected_clients': connectedClients,
        'used_memory': usedMemory,
      };
    } catch (e) {
      return {'version': 'unknown', 'database': 'Redis'};
    }
  }

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final dbIndex = int.tryParse(dbName.replaceAll('db', '')) ?? _dbIndex;
      final info = await _commandRaw([
        'INFO',
        'keyspace',
      ], database: '$dbIndex');
      return {'name': dbName, 'info': info?.toString() ?? ''};
    } catch (e) {
      return null;
    }
  }

  @override
  Future<bool> dropDatabase(String dbName) async {
    // feature 039 只读守卫：FLUSHDB 写路径
    guardReadOnly(operation: 'dropDatabase');
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final dbIndex = int.tryParse(dbName.replaceAll('db', '')) ?? _dbIndex;
      await _runRedisCommand(['FLUSHDB'], database: '$dbIndex');
      return true;
    } catch (e) {
      AppLogger.d(_tag, '清空数据库失败: $e');
      return false;
    }
  }

  @override
  Future<bool> dropTable(String tableName) async {
    // feature 039 只读守卫：DEL 命名空间写路径
    guardReadOnly(operation: 'dropTable');
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final pattern = tableName == '(无前缀)' ? '*' : '$tableName:*';
      final keys = await scanKeys(pattern: pattern);

      if (keys.isNotEmpty) {
        await runCommand(['DEL', ...keys]);
      }
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除命名空间失败: $e');
      return false;
    }
  }

  @override
  Future<bool> renameTable(String oldName, String newName) async {
    // feature 039 只读守卫：RENAME 命名空间写路径
    guardReadOnly(operation: 'renameTable');
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final pattern = oldName == '(无前缀)' ? '*' : '$oldName:*';
      final keys = await scanKeys(pattern: pattern);

      // 批量重命名经 pipeline（原子性不必须，减少往返）。
      if (keys.isNotEmpty) {
        final commands = [
          for (final oldKey in keys)
            ['RENAME', oldKey, oldKey.replaceFirst('$oldName:', '$newName:')],
        ];
        await _pipelineRaw(commands.map((c) => c.cast<String>()).toList());
      }
      return true;
    } catch (e) {
      AppLogger.d(_tag, '重命名命名空间失败: $e');
      return false;
    }
  }

  @override
  Future<bool> truncateTable(
    String tableName, {
    TruncateOptions? options,
  }) async {
    // feature 039 只读守卫：TRUNCATE 走 dropTable 写路径(双保险)
    guardReadOnly(operation: 'truncateTable');
    return await dropTable(tableName);
  }

  @override
  Future<QueryResult> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
  }) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final pattern = tableName == '(无前缀)' ? '*' : '$tableName:*';
      // 真分页：只扫本页需要的 key 数（首页一轮 SCAN；翻页沿游标补扫），
      // 不再全 keyspace 扫完再切片（旧版大库一次翻页 = 最多 50 轮 SCAN）。
      final keys = await _scanKeysIncremental(pattern, offset + limit);
      final keyList = keys.skip(offset).take(limit).toList();

      // 限流根治：旧版每 key 逐命令一请求（TYPE+TTL+值+长度 ≈ 4N/页），
      // per-user 600 req/min 下一次翻页即打爆。改两相 pipeline——整页恒定
      // 2 请求（+ SCAN）：① 全页 TYPE+TTL；② 按类型排布值/长度命令。
      final types = List<String>.filled(keyList.length, 'none');
      final ttls = List<int>.filled(keyList.length, -2);
      if (keyList.isNotEmpty) {
        final phase1 = await _pipelineRaw([
          for (final key in keyList) ...[
            ['TYPE', key],
            ['TTL', key],
          ],
        ]);
        for (var i = 0; i < keyList.length; i++) {
          types[i] = phase1[2 * i]?.toString() ?? 'none';
          ttls[i] = int.tryParse(phase1[2 * i + 1].toString()) ?? -2;
        }
      }

      // ② 值/长度命令按类型排布（命令序列与旧版逐 key 版一一对应，
      //    行格式化语义零变化）。
      final valueCmds = <List<String>>[];
      final cmdCounts = <int>[];
      for (var i = 0; i < keyList.length; i++) {
        final key = keyList[i];
        var n = 0;
        void plan(List<String> c) {
          valueCmds.add(c);
          n++;
        }

        switch (types[i]) {
          case 'string':
            plan(['GET', key]);
            plan(['STRLEN', key]);
          case 'list':
            plan(['LLEN', key]);
            plan(['LRANGE', key, '0', '4']);
          case 'set':
            plan(['SCARD', key]);
            plan(['SRANDMEMBER', key, '5']);
          case 'zset':
            plan(['ZCARD', key]);
            plan(['ZRANGE', key, '0', '4']);
          case 'hash':
            plan(['HLEN', key]);
            plan(['HSCAN', key, '0', 'COUNT', '6']);
          case 'stream':
            plan(['XLEN', key]);
          case 'bitmap':
            plan(['STRLEN', key]);
            plan(['BITCOUNT', key]);
          case 'geo':
            plan(['ZCARD', key]);
          case 'bitfield':
            plan(['STRLEN', key]);
          case 'hyperloglog':
            plan(['STRLEN', key]);
            plan(['PFCOUNT', key]);
          case 'json':
          case 'rejson-rl':
            plan(['JSON.GET', key]);
          case 'none':
            break; // key 已消失：无值命令（与旧版一致）
          default:
            plan(['MEMORY', 'USAGE', key]);
        }
        cmdCounts.add(n);
      }
      final values = valueCmds.isEmpty
          ? const <dynamic>[]
          : await _pipelineRaw(valueCmds);

      final rows = <Map<String, dynamic>>[];
      var valueCursor = 0;
      for (var i = 0; i < keyList.length; i++) {
        final key = keyList[i];
        final type = types[i];
        final ttl = ttls[i];
        final base = valueCursor;
        valueCursor += cmdCounts[i];
        dynamic r(int j) => values[base + j];

        String? value;
        int? size;

        switch (type) {
          case 'string':
            final strValue = r(0)?.toString();
            final len = int.tryParse(r(1).toString()) ?? 0;
            size = len;
            if (strValue != null && strValue.length > 1024) {
              value = '${strValue.substring(0, 1024)}... ($len chars total)';
            } else {
              value = strValue;
            }
          case 'list':
            final len = int.tryParse(r(0).toString()) ?? 0;
            final preview = r(1) is List
                ? (r(1) as List).map((e) => e.toString()).toList()
                : <String>[];
            value =
                '[$len items] ${preview.join(", ")}${len > preview.length ? "..." : ""}';
            size = len;
          case 'set':
            final len = int.tryParse(r(0).toString()) ?? 0;
            final preview = r(1) is List
                ? (r(1) as List).map((e) => e.toString()).toList()
                : <String>[];
            value =
                '[$len members] ${preview.join(", ")}${len > preview.length ? "..." : ""}';
            size = len;
          case 'zset':
            final len = int.tryParse(r(0).toString()) ?? 0;
            final preview = r(1) is List
                ? (r(1) as List).map((e) => e.toString()).toList()
                : <String>[];
            value =
                '[$len items] ${preview.join(", ")}${len > preview.length ? "..." : ""}';
            size = len;
          case 'hash':
            final len = int.tryParse(r(0).toString()) ?? 0;
            final map = <String, String>{};
            final scan = r(1);
            if (scan is List && scan.length > 1 && scan[1] is List) {
              final items = scan[1] as List;
              for (
                var j = 0;
                j < items.length - 1 && map.length < 3;
                j += 2
              ) {
                map[items[j].toString()] = items[j + 1].toString();
              }
            }
            value =
                '[$len fields] ${map.entries.map((e) => "${e.key}=${e.value}").join(", ")}${len > map.length ? "..." : ""}';
            size = len;
          case 'stream':
            final len = int.tryParse(r(0).toString()) ?? 0;
            value = '[$len entries] (stream)';
            size = len;
          case 'bitmap':
            final len = int.tryParse(r(0).toString()) ?? 0;
            final bitCount = int.tryParse(r(1).toString()) ?? 0;
            value = '[$len B, $bitCount bits set] (bitmap)';
            size = len;
          case 'geo':
            final len = int.tryParse(r(0).toString()) ?? 0;
            value = '[$len items] (geo)';
            size = len;
          case 'bitfield':
            final len = int.tryParse(r(0).toString()) ?? 0;
            value = '[$len B] (bitfield)';
            size = len;
          case 'hyperloglog':
            final len = int.tryParse(r(0).toString()) ?? 0;
            final count = int.tryParse(r(1).toString()) ?? 0;
            value = '[$len B, ~$count cardinality] (hyperloglog)';
            size = len;
          case 'json':
          case 'rejson-rl':
            final json = r(0)?.toString();
            final len = json != null ? json.length : 0;
            value = '[$len chars] (json)';
            size = len;
          case 'none':
            value = '(key不存在)';
            break;
          default:
            value = '($type)';
            size = int.tryParse(r(0).toString()) ?? 0;
        }

        rows.add({
          'key': key,
          'type': type,
          'value': value,
          'ttl': ttl == -1 ? '无过期' : (ttl == -2 ? '不存在' : '${ttl}s'),
          'size': size,
        });
      }

      return QueryResult(
        columns: ['key', 'type', 'value', 'ttl', 'size'],
        rows: rows,
        executionTime: 0,
      );
    } catch (e) {
      throw Exception('获取数据失败: $e');
    }
  }

  @override
  Future<int> getTableRowCount(String tableName) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      // 全库口径走 DBSIZE（O(1) 精确，替代全 keyspace SCAN 计数）；
      // 命名空间口径仍需 SCAN（Redis 无按前缀计数的 O(1) 命令）。
      if (tableName == '(无前缀)') {
        return await getDatabaseSize();
      }
      final pattern = '$tableName:*';
      final keys = await scanKeys(pattern: pattern);
      return keys.length;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<String> exportDatabaseStructure(String dbName) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    const maxKeys = 5000;
    const maxElementsPerKey = 1000;

    final sb = StringBuffer();
    sb.writeln('# Redis Database Export');
    sb.writeln('# Database: $dbName');
    sb.writeln('# Date: ${DateTime.now().toIso8601String()}');
    sb.writeln(
      '# WARNING: Export is capped at $maxKeys keys and $maxElementsPerKey elements per key to avoid blocking Redis.',
    );
    sb.writeln();

    try {
      final keys = await scanKeys();
      final totalKeys = keys.length;
      final keysToExport = keys.take(maxKeys).toList();

      if (totalKeys > maxKeys) {
        sb.writeln('# Note: Only exporting $maxKeys of $totalKeys keys.');
        sb.writeln();
      }

      // 限流根治：旧版逐 key「TYPE + 值命令」各一请求（5000 key ≈ 1.5 万
      // 请求，必打爆网关限流）。改三相 pipeline（分块在 _pipelineRaw 内）：
      // ① TYPE 全量；② 确定性类型取值（每 key 一条）；③ geo 的 GEOPOS
      // （依赖② members）。set 的 SSCAN 游标循环依赖上一轮 cursor，保留
      // 逐 key（走 getSet）。输出行格式与旧版逐字一致。
      final types = List<String>.filled(keysToExport.length, 'none');
      final typeResults = keysToExport.isEmpty
          ? const <dynamic>[]
          : await _pipelineRaw([
              for (final keyStr in keysToExport) ['TYPE', keyStr],
            ]);
      for (var i = 0; i < keysToExport.length; i++) {
        types[i] = typeResults[i]?.toString() ?? 'none';
      }

      final valueCmds = <List<String>>[];
      final valueKeyIdx = <int>[];
      for (var i = 0; i < keysToExport.length; i++) {
        final keyStr = keysToExport[i];
        switch (types[i]) {
          case 'string':
          case 'bitmap':
          case 'bitfield':
          case 'hyperloglog':
            valueCmds.add(['GET', keyStr]);
            valueKeyIdx.add(i);
          case 'hash':
            valueCmds.add(['HGETALL', keyStr]);
            valueKeyIdx.add(i);
          case 'list':
            valueCmds.add(['LRANGE', keyStr, '0', '${maxElementsPerKey - 1}']);
            valueKeyIdx.add(i);
          case 'zset':
            valueCmds.add([
              'ZRANGE',
              keyStr,
              '0',
              '${maxElementsPerKey - 1}',
              'WITHSCORES',
            ]);
            valueKeyIdx.add(i);
          case 'stream':
            valueCmds.add([
              'XRANGE',
              keyStr,
              '-',
              '+',
              'COUNT',
              '$maxElementsPerKey',
            ]);
            valueKeyIdx.add(i);
          case 'geo':
            valueCmds.add(['ZRANGE', keyStr, '0', '${maxElementsPerKey - 1}']);
            valueKeyIdx.add(i);
          case 'json':
          case 'rejson-rl':
            valueCmds.add(['JSON.GET', keyStr]);
            valueKeyIdx.add(i);
        }
      }
      final valueResults = valueCmds.isEmpty
          ? const <dynamic>[]
          : await _pipelineRaw(valueCmds);
      final valueByKey = <int, dynamic>{
        for (var k = 0; k < valueKeyIdx.length; k++)
          valueKeyIdx[k]: valueResults[k],
      };

      // ③ geo 成员坐标（每 geo key 一条 GEOPOS，仅 geo key 参与）。
      final geoPosCmds = <List<String>>[];
      final geoPosKeyIdx = <int>[];
      for (var i = 0; i < keysToExport.length; i++) {
        if (types[i] != 'geo') continue;
        final membersRaw = valueByKey[i];
        final members = membersRaw is List
            ? membersRaw.map((m) => m.toString()).toList()
            : <String>[];
        if (members.isEmpty) continue;
        geoPosCmds.add(['GEOPOS', keysToExport[i], ...members]);
        geoPosKeyIdx.add(i);
      }
      final geoPosResults = geoPosCmds.isEmpty
          ? const <dynamic>[]
          : await _pipelineRaw(geoPosCmds);
      final geoPosByKey = <int, dynamic>{
        for (var k = 0; k < geoPosKeyIdx.length; k++)
          geoPosKeyIdx[k]: geoPosResults[k],
      };

      for (var i = 0; i < keysToExport.length; i++) {
        final keyStr = keysToExport[i];
        final type = types[i];

        switch (type) {
          case 'string':
            final value = valueByKey[i]?.toString();
            sb.writeln("SET '$keyStr' '${_escapeString(value ?? "")}'");
            break;
          case 'hash':
            final flat = valueByKey[i] as List? ?? const [];
            // 与旧版 getHash(maxFields: maxElementsPerKey) 同一上限契约。
            final cap = flat.length.clamp(0, maxElementsPerKey * 2);
            for (var j = 0; j + 1 < cap; j += 2) {
              sb.writeln(
                "HSET '$keyStr' '${flat[j]}' '${_escapeString(flat[j + 1].toString())}'",
              );
            }
            break;
          case 'list':
            final list = valueByKey[i] is List
                ? (valueByKey[i] as List).map((item) => item.toString())
                : const <String>[];
            for (final item in list) {
              sb.writeln("RPUSH '$keyStr' '${_escapeString(item)}'");
            }
            break;
          case 'set':
            final set = await getSet(keyStr, maxMembers: maxElementsPerKey);
            for (final member in set) {
              sb.writeln("SADD '$keyStr' '${_escapeString(member)}'");
            }
            break;
          case 'zset':
            final flat = valueByKey[i] as List? ?? const [];
            for (var j = 0; j + 1 < flat.length; j += 2) {
              sb.writeln(
                "ZADD '$keyStr' ${flat[j + 1]} '${_escapeString(flat[j].toString())}'",
              );
            }
            break;
          case 'stream':
            final entries = valueByKey[i] as List? ?? const [];
            for (final entry in entries) {
              if (entry is! List || entry.length < 2) continue;
              final id = entry[0].toString();
              final fields = entry[1];
              final map = <String, String>{'id': id};
              if (fields is List) {
                for (var j = 0; j + 1 < fields.length; j += 2) {
                  map[fields[j].toString()] = fields[j + 1].toString();
                }
              }
              final rest = map.entries
                  .where((e) => e.key != 'id')
                  .map((e) => "${e.key} ${_escapeString(e.value)}")
                  .join(' ');
              sb.writeln("XADD '$keyStr' $id $rest");
            }
            break;
          case 'bitmap':
          case 'bitfield':
            final rawValue = valueByKey[i];
            if (rawValue != null) {
              final raw = utf8.encode(rawValue.toString());
              sb.writeln("# $type type: $keyStr (binary data, $raw bytes)");
            }
            break;
          case 'geo':
            final membersRaw = valueByKey[i];
            final members = membersRaw is List
                ? membersRaw.map((m) => m.toString()).toList()
                : <String>[];
            final posResult = geoPosByKey[i];
            final positions = <String, List<double>>{};
            if (posResult is List) {
              for (var j = 0; j < posResult.length && j < members.length; j++) {
                final pos = posResult[j];
                if (pos is List && pos.length >= 2) {
                  final lon = double.tryParse(pos[0].toString()) ?? 0;
                  final lat = double.tryParse(pos[1].toString()) ?? 0;
                  positions[members[j]] = [lon, lat];
                }
              }
            }
            for (final member in members) {
              final pos = positions[member];
              if (pos != null) {
                sb.writeln(
                  "GEOADD '$keyStr' ${pos[0]} ${pos[1]} '${_escapeString(member)}'",
                );
              }
            }
            break;
          case 'json':
          case 'rejson-rl':
            final json = valueByKey[i]?.toString();
            if (json != null) {
              sb.writeln("JSON.SET '$keyStr' '\$' '${_escapeString(json)}'");
            }
            break;
          case 'hyperloglog':
            final rawValue = valueByKey[i];
            if (rawValue != null) {
              final raw = utf8.encode(rawValue.toString());
              sb.writeln(
                "# HyperLogLog type: $keyStr (probabilistic data, ${raw.length} bytes)",
              );
            }
            break;
          default:
            sb.writeln("# Unsupported type '$type' for key: $keyStr");
        }
      }
    } catch (e) {
      sb.writeln('# Export error: $e');
    }

    return sb.toString();
  }

  String _escapeString(String s) {
    return s
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
  }

  @override
  Future<bool> executeSqlScript(String script) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final lines = script
          .split('\n')
          .where(
            (l) =>
                l.trim().isNotEmpty &&
                !l.startsWith('#') &&
                !l.startsWith('--'),
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
  // SCAN 族（旧形状 [cursor, [items]] 经 _commandRaw 重建直通）
  // ==========================================================================

  // B1 — HSCAN/SSCAN/ZSCAN 对外分页(cursor 由调用方持有,大 key 增量加载)
  Future<RedisScanResult> sscanCursor(
    String key, {
    required int cursor,
    int count = 200,
    String match = '*',
  }) async {
    final result = await runCommand([
      'SSCAN',
      key,
      '$cursor',
      'MATCH',
      match,
      'COUNT',
      '$count',
    ]);
    return _parseScanResult(result);
  }

  Future<RedisHashScanResult> hscanCursor(
    String key, {
    required int cursor,
    int count = 200,
    String match = '*',
  }) async {
    final result = await runCommand([
      'HSCAN',
      key,
      '$cursor',
      'MATCH',
      match,
      'COUNT',
      '$count',
    ]);
    final parsed = _parseScanResult(result);
    final fields = <MapEntry<String, String>>[];
    for (var i = 0; i < parsed.keys.length - 1; i += 2) {
      fields.add(MapEntry(parsed.keys[i], parsed.keys[i + 1]));
    }
    return RedisHashScanResult(cursor: parsed.cursor, fields: fields);
  }

  Future<RedisZSetScanResult> zscanCursor(
    String key, {
    required int cursor,
    int count = 200,
    String match = '*',
  }) async {
    final result = await runCommand([
      'ZSCAN',
      key,
      '$cursor',
      'MATCH',
      match,
      'COUNT',
      '$count',
    ]);
    final parsed = _parseScanResult(result);
    final members = <MapEntry<String, double>>[];
    for (var i = 0; i < parsed.keys.length - 1; i += 2) {
      members.add(
        MapEntry(parsed.keys[i], double.tryParse(parsed.keys[i + 1]) ?? 0),
      );
    }
    return RedisZSetScanResult(cursor: parsed.cursor, members: members);
  }

  /// 解析 SCAN 族返回的 [cursor, [items]]。
  RedisScanResult _parseScanResult(dynamic result) {
    if (result is! List || result.length < 2) {
      return const RedisScanResult(cursor: 0, keys: []);
    }
    final nextCursor = int.tryParse(result[0].toString()) ?? 0;
    final arr = result[1];
    final keys = <String>[];
    if (arr is List) {
      for (final e in arr) {
        keys.add(e.toString());
      }
    }
    return RedisScanResult(cursor: nextCursor, keys: keys);
  }

  Future<List<String>> scanKeys({
    String pattern = '*',
    // COUNT 是 hint（增量、非阻塞），调大以降低网关往返轮数（限流根治：
    // 旧默认 200 × 大库 = 每次 key 发现最多 50 请求吃掉 1/12 配额）。
    int count = 1000,
    int maxIterations = 50,
  }) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    final allKeys = <String>[];
    var cursor = 0;
    var iterations = 0;

    do {
      final result = await _commandRaw([
        'SCAN',
        '$cursor',
        'MATCH',
        pattern,
        'COUNT',
        '$count',
      ]);
      if (result is! List || result.length < 2) break;
      cursor = int.tryParse(result[0].toString()) ?? 0;
      final keys = result[1];
      if (keys is List) {
        for (final key in keys) {
          allKeys.add(key.toString());
        }
      }
      iterations++;
    } while (cursor != 0 && iterations < maxIterations);

    return allKeys;
  }

  /// 增量取 key（真分页底座）：直到攒够 [needed] 个或扫尽 keyspace，
  /// 沿 [_RedisScanPage] 游标跨调用续扫。每轮 COUNT 随缺口自适应
  /// （100..1000），空批容忍上限 10 轮（大库稀疏游标的常规防御）。
  /// getTableData 首页 = 一轮 SCAN；翻页只补扫缺口部分。
  Future<List<String>> _scanKeysIncremental(String pattern, int needed) async {
    final page = _scanPages.putIfAbsent(
      '$_dbIndex:$pattern',
      _RedisScanPage.new,
    );
    var rounds = 0;
    while (page.keys.length < needed && !page.exhausted && rounds < 10) {
      final gap = (needed - page.keys.length).clamp(100, 1000);
      final result = await _commandRaw([
        'SCAN',
        '${page.cursor}',
        'MATCH',
        pattern,
        'COUNT',
        '$gap',
      ]);
      if (result is! List || result.length < 2) {
        page.exhausted = true;
        break;
      }
      page.cursor = int.tryParse(result[0].toString()) ?? 0;
      final keys = result[1];
      if (keys is List) {
        page.keys.addAll(keys.map((k) => k.toString()));
      }
      if (page.cursor == 0) page.exhausted = true;
      rounds++;
    }
    return page.keys;
  }

  /// 侧边栏采样口（'*' 全库口径）：取至多 [limit] 个 key。Keys 与 TTL
  /// 两个节点共享同一份 [_RedisScanPage]（同 db 同 pattern）——先展开的
  /// 节点建立采样，后展开的只补扫缺口（页够时零 SCAN）；TTL 值不缓存，
  /// 每次展开经批量 pipeline 现取。返回可能多于 [limit]（页内已收集的
  /// 全量，见 [_scanKeysIncremental]），统计口径取更大样本无害。
  Future<({List<String> keys, bool hasMore})> sampleKeys({
    int limit = 500,
  }) async {
    _assertConnected();
    final keys = await _scanKeysIncremental('*', limit);
    final page = _scanPages['$_dbIndex:*'];
    return (keys: keys, hasMore: !(page?.exhausted ?? false));
  }

  /// 会改变 key 集合的命令（SCAN 分页缓存失效判据；漏判只是缓存陈旧到
  /// 下一次失效，无正确性风险——TTL/值变化不影响缓存，缓存只存 key 名）。
  static const Set<String> _keyspaceWriteCommands = {
    'DEL', 'UNLINK', 'SET', 'SETEX', 'SETNX', 'PSETEX', 'MSET', 'GETSET',
    'APPEND', 'SETRANGE', 'SETBIT', 'HSET', 'HMSET', 'HDEL', 'LPUSH',
    'RPUSH', 'LPOP', 'RPOP', 'LREM', 'LTRIM', 'LINSERT', 'LSET', 'SADD',
    'SPOP', 'SMOVE', 'SREM', 'ZADD', 'ZINCRBY', 'ZPOPMIN', 'ZPOPMAX',
    'ZREM', 'XADD', 'XTRIM', 'RENAME', 'RENAMENX', 'COPY', 'RESTORE',
    'FLUSHDB', 'FLUSHALL', 'BITFIELD',
  };

  void _invalidateScanPagesIfWrite(List<List<String>> commands) {
    for (final cmd in commands) {
      if (cmd.isNotEmpty &&
          _keyspaceWriteCommands.contains(cmd.first.toUpperCase())) {
        _scanPages.clear();
        return;
      }
    }
  }

  /// 分页 SCAN（外部控制 cursor，适用于 UI 增量加载）
  Future<RedisScanResult> scanKeysCursor({
    required int cursor,
    String pattern = '*',
    int count = 200,
  }) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    final result = await _commandRaw([
      'SCAN',
      '$cursor',
      'MATCH',
      pattern,
      'COUNT',
      '$count',
    ]);
    if (result is! List || result.length < 2) {
      return const RedisScanResult(cursor: 0, keys: []);
    }

    final nextCursor = int.tryParse(result[0].toString()) ?? 0;
    final keys = result[1];
    final keyList = keys is List
        ? keys.map((k) => k.toString()).toList()
        : <String>[];

    return RedisScanResult(cursor: nextCursor, keys: keyList);
  }

  /// 重命名 key
  Future<bool> renameKey(String oldKey, String newKey) async {
    // feature 039 只读守卫：RENAME 写路径
    guardReadOnly(operation: 'renameKey');
    if (!isConnected) throw Exception('未连接到 Redis');
    try {
      final result = await _commandRaw(['RENAME', oldKey, newKey]);
      return result.toString() == 'OK';
    } catch (e) {
      return false;
    }
  }

  // ==========================================================================
  // 通用命令 / 只读判定 / Pipeline / 事务
  // ==========================================================================

  /// 执行 Redis 命令（原始接口；keep-alive PING / workbench / 通用路径）。
  /// 只读写判定（feature 039）：复用 validateCommand 的写分类（Redis 无 stub 陷阱）。
  @override
  bool isWriteCommand(String query) =>
      validateCommand(query).riskLevel != CommandRiskLevel.safe;

  Future<dynamic> runCommand(List<String> args) async {
    // feature 039 只读守卫：workbench/pipeline/keyspace/key-editor 通用路径。
    guardReadOnlyQuery(
      args.isNotEmpty ? args[0] : '',
      operation: 'runCommand',
    );
    if (!isConnected) throw Exception('未连接到 Redis');
    return await _commandRaw(args);
  }

  // C4 — Pipeline 管道缓冲（旧版为 redis.dart 的 Nagle 合并优化）。
  /// **网关模型下为 no-op**（每命令独立 HTTP；批量原子路径走 [multiExec]）。
  void pipeStart() {}

  /// 同 [pipeStart]——no-op（签名保留，pipeline 面板零改动）。
  void pipeEnd() {}

  // C5 — MULTI/EXEC 事务
  /// 原子执行事务：网关 pipeline `atomic:true`（server 侧 MULTI/EXEC +
  /// QUEUED 校验由 redis-rs pipe.atomic 承担）。
  /// 返回 EXEC 的结果数组(按命令顺序)。
  Future<List<dynamic>> multiExec(List<List<String>> commands) async {
    // feature 039 只读守卫：MULTI/EXEC 事务写路径
    guardReadOnly(operation: 'multiExec');
    if (!isConnected) throw Exception('未连接到 Redis');
    if (commands.isEmpty) return [];
    return await _pipelineRaw(commands, atomic: true);
  }

  /// WATCH keys(乐观锁)——**网关模式 fail-loud**（跨请求连接亲和，
  /// ADR-0006 §2.3 / 用户拍板；恢复路径与 SQL 族事务同表登记）。
  Future<void> watch(List<String> keys) async {
    guardReadOnly(operation: 'watch');
    throw UnsupportedError(
      'Redis 网关模式暂不支持 WATCH（跨请求连接亲和；原子批量请用 multiExec）',
    );
  }

  /// 取消 WATCH——网关模式 fail-loud（见 [watch]）。
  Future<void> unwatch() async {
    guardReadOnly(operation: 'unwatch');
    throw UnsupportedError(
      'Redis 网关模式暂不支持 UNWATCH（跨请求连接亲和；原子批量请用 multiExec）',
    );
  }

  /// DISCARD 事务——网关模式 fail-loud（见 [watch]）。
  Future<void> discardTx() async {
    guardReadOnly(operation: 'discardTx');
    throw UnsupportedError(
      'Redis 网关模式暂不支持 DISCARD（跨请求连接亲和；原子批量请用 multiExec）',
    );
  }

  // ==========================================================================
  // INFO 族 / 库信息
  // ==========================================================================

  // D1 — 解析 INFO 文本为扁平 K:V(过滤 # 注释)
  Map<String, String> _parseInfoText(String text) {
    final info = <String, String>{};
    for (final line in text.split('\n')) {
      if (line.contains(':') && !line.startsWith('#')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          info[parts[0]] = parts.sublist(1).join(':').trim();
        }
      }
    }
    return info;
  }

  /// 获取服务器信息
  Future<Map<String, String>> getServerInfo() async {
    if (!isConnected) throw Exception('未连接到 Redis');
    final result = await _commandRaw(['INFO']);
    return _parseInfoText(result?.toString() ?? '');
  }

  /// 获取数据库大小
  Future<int> getDatabaseSize() async {
    if (!isConnected) throw Exception('未连接到 Redis');
    final result = await _commandRaw(['DBSIZE']);
    return int.tryParse(result.toString()) ?? 0;
  }

  /// 获取内存使用信息
  Future<Map<String, String>> getMemoryInfo() async {
    if (!isConnected) throw Exception('未连接到 Redis');
    final result = await _commandRaw(['INFO', 'memory']);
    return _parseInfoText(result?.toString() ?? '');
  }

  /// 当前 db 的精确聚合（`INFO keyspace` 对应 db 行：keys/expires/avg_ttl
  /// ——O(1) 零枚举，Redis 对「多少 key 带过期、平均活多久」的原生答案，
  /// TTL 面板/DB Info 头部的口径源；avg_ttl 为毫秒；db 空或行缺失全 0）。
  Future<({int keys, int expires, int avgTtlMs})> getKeyspaceAggregate() async {
    final result = await _commandRaw(['INFO', 'keyspace']);
    final line = (result?.toString() ?? '')
        .split('\n')
        .map((l) => l.trim())
        .firstWhere(
          (l) => l.startsWith('db$_dbIndex:'),
          orElse: () => '',
        );
    if (line.isEmpty) return (keys: 0, expires: 0, avgTtlMs: 0);
    int field(String name) =>
        int.tryParse(RegExp('$name=(\\d+)').firstMatch(line)?.group(1) ?? '') ??
        0;
    return (
      keys: field('keys'),
      expires: field('expires'),
      avgTtlMs: field('avg_ttl'),
    );
  }

  /// 获取指定 INFO section(replication/memory/clients/stats/keyspace 等)。
  Future<Map<String, String>> getInfoSection(String section) async {
    if (!isConnected) throw Exception('未连接到 Redis');
    final result = await _commandRaw(['INFO', section]);
    return _parseInfoText(result?.toString() ?? '');
  }

  /// 获取复制信息(INFO replication:role/master/slaves)。
  Future<Map<String, String>> getReplicationInfo() =>
      getInfoSection('replication');

  /// 当前 db 索引(D3 键空间通知拼 channel / D2 Top-N 用)
  int get currentDbIndex => _dbIndex;

  Future<List<String>> searchKeys(String pattern) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    return await scanKeys(pattern: pattern);
  }

  // ==========================================================================
  // key 级写操作（TTL 族）
  // ==========================================================================

  Future<int> deleteKey(String key) async {
    // feature 039 只读守卫：DEL 写路径
    guardReadOnly(operation: 'deleteKey');
    if (!isConnected) throw Exception('未连接到 Redis');

    final result = await _commandRaw(['DEL', key]);
    return int.tryParse(result.toString()) ?? 0;
  }

  Future<bool> setTTL(String key, Duration ttl) async {
    // feature 039 只读守卫：EXPIRE 写路径
    guardReadOnly(operation: 'setTTL');
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final result = await _commandRaw(['EXPIRE', key, '${ttl.inSeconds}']);
      return result.toString() == '1';
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeTTL(String key) async {
    // feature 039 只读守卫：PERSIST 写路径
    guardReadOnly(operation: 'removeTTL');
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final result = await _commandRaw(['PERSIST', key]);
      return result.toString() == '1';
    } catch (e) {
      return false;
    }
  }

  // B2 — 毫秒级 / 绝对时间 TTL
  Future<int> getPTTL(String key) async {
    if (!isConnected) throw Exception('未连接到 Redis');
    final result = await _commandRaw(['PTTL', key]);
    return int.tryParse(result.toString()) ?? -2;
  }

  Future<bool> setPTTL(String key, Duration ttl) async {
    // feature 039 只读守卫：PEXPIRE 写路径
    guardReadOnly(operation: 'setPTTL');
    if (!isConnected) throw Exception('未连接到 Redis');
    try {
      final result = await _commandRaw([
        'PEXPIRE',
        key,
        '${ttl.inMilliseconds}',
      ]);
      return result.toString() == '1';
    } catch (_) {
      return false;
    }
  }

  Future<bool> expireAt(String key, DateTime time) async {
    // feature 039 只读守卫：EXPIREAT 写路径
    guardReadOnly(operation: 'expireAt');
    if (!isConnected) throw Exception('未连接到 Redis');
    try {
      final result = await _commandRaw([
        'EXPIREAT',
        key,
        '${time.toUtc().millisecondsSinceEpoch ~/ 1000}',
      ]);
      return result.toString() == '1';
    } catch (_) {
      return false;
    }
  }

  Future<bool> pExpireAt(String key, DateTime time) async {
    // feature 039 只读守卫：PEXPIREAT 写路径
    guardReadOnly(operation: 'pExpireAt');
    if (!isConnected) throw Exception('未连接到 Redis');
    try {
      final result = await _commandRaw([
        'PEXPIREAT',
        key,
        '${time.toUtc().millisecondsSinceEpoch}',
      ]);
      return result.toString() == '1';
    } catch (_) {
      return false;
    }
  }

  // ==========================================================================
  // Lua / Functions
  // ==========================================================================

  /// 执行 Lua 脚本（EVAL/EVALSHA + NOSCRIPT 透明 fallback——与旧版一致）。
  Future<dynamic> evalLua(
    String script,
    List<String> keys,
    List<String> args, {
    String? sha,
  }) async {
    // feature 039 只读守卫：EVAL/EVALSHA Lua 脚本写路径
    guardReadOnly(operation: 'evalLua');
    if (!isConnected) throw Exception('未连接到 Redis');

    if (sha != null) {
      try {
        return await evalSha(sha, keys, args);
      } catch (e) {
        if (!e.toString().toUpperCase().contains('NOSCRIPT')) rethrow;
        await scriptLoad(script); // 重新加载后重试
        return await evalSha(sha, keys, args);
      }
    }

    return await _commandRaw([
      'EVAL',
      script,
      keys.length.toString(),
      ...keys,
      ...args,
    ]);
  }

  Future<String> scriptLoad(String script) async {
    // feature 039 只读守卫：SCRIPT LOAD 写入服务端缓存
    guardReadOnly(operation: 'scriptLoad');
    final result = await runCommand(['SCRIPT', 'LOAD', script]);
    return result.toString();
  }

  Future<dynamic> evalSha(
    String sha,
    List<String> keys,
    List<String> args,
  ) async {
    // feature 039 只读守卫：EVALSHA Lua 脚本写路径
    guardReadOnly(operation: 'evalSha');
    return await runCommand([
      'EVALSHA',
      sha,
      keys.length.toString(),
      ...keys,
      ...args,
    ]);
  }

  Future<List<bool>> scriptExists(List<String> shas) async {
    if (shas.isEmpty) return [];
    final result = await runCommand(['SCRIPT', 'EXISTS', ...shas]);
    if (result is! List) return List.filled(shas.length, false);
    return result.map((e) => e.toString() == '1').toList();
  }

  Future<bool> scriptFlush() async {
    // feature 039 只读守卫：SCRIPT FLUSH 写路径
    guardReadOnly(operation: 'scriptFlush');
    final result = await runCommand(['SCRIPT', 'FLUSH']);
    return result == 'OK';
  }

  /// 获取 Redis Functions（Redis 7.0+；不支持时返回空列表）。
  Future<List<RedisFunctionLibrary>> getRedisFunctions({
    bool withCode = false,
  }) async {
    if (!isConnected) throw Exception('未连接到 Redis');

    try {
      final result = await _commandRaw(
        withCode
            ? ['FUNCTION', 'LIST', 'WITHCODE']
            : ['FUNCTION', 'LIST'],
      );
      return _parseFunctionList(result, withCode: withCode);
    } catch (e) {
      return [];
    }
  }

  /// 取单个 library 的 Lua 源码（FUNCTION LIST WITHCODE LIBRARYNAME）。
  Future<String?> getRedisFunctionSource(String libraryName) async {
    if (!isConnected) throw Exception('未连接到 Redis');
    try {
      final result = await _commandRaw([
        'FUNCTION',
        'LIST',
        'WITHCODE',
        'LIBRARYNAME',
        libraryName,
      ]);
      final libs = _parseFunctionList(result, withCode: true);
      return libs.isEmpty ? null : libs.first.sourceCode;
    } catch (e) {
      return null;
    }
  }

  /// 调用一个 Redis Function（FCALL / FCALL_RO）。
  Future<dynamic> callRedisFunction(
    String name, {
    List<String> keys = const [],
    List<String> args = const [],
    bool readOnly = false,
  }) async {
    if (!readOnly) guardReadOnly(operation: 'callRedisFunction');
    final cmd = readOnly ? 'FCALL_RO' : 'FCALL';
    return await runCommand([cmd, name, keys.length.toString(), ...keys, ...args]);
  }

  List<RedisFunctionLibrary> _parseFunctionList(
    dynamic result, {
    bool withCode = false,
  }) {
    final libraries = <RedisFunctionLibrary>[];
    if (result is! List) return libraries;

    for (final libData in result) {
      if (libData is! List) continue;
      String? name;
      String? engine;
      List<RedisFunctionInfo>? functions;
      String? sourceCode;

      for (int i = 0; i < libData.length - 1; i += 2) {
        final key = libData[i].toString();
        final value = libData[i + 1];
        switch (key) {
          case 'library_name':
            name = value.toString();
            break;
          case 'engine':
            engine = value.toString();
            break;
          case 'functions':
            functions = _parseFunctions(value);
            break;
          case 'library_code':
            if (withCode && value is String) sourceCode = value;
            break;
        }
      }

      if (name != null && engine != null && functions != null) {
        libraries.add(
          RedisFunctionLibrary(
            name: name,
            engine: engine,
            functions: functions,
            sourceCode: sourceCode,
          ),
        );
      }
    }
    return libraries;
  }

  List<RedisFunctionInfo> _parseFunctions(dynamic result) {
    final functions = <RedisFunctionInfo>[];
    if (result is! List) return functions;

    for (final funcData in result) {
      if (funcData is! List) continue;
      String? name;
      String? description;
      List<String> flags = [];

      for (int i = 0; i < funcData.length - 1; i += 2) {
        final key = funcData[i].toString();
        final value = funcData[i + 1];
        switch (key) {
          case 'name':
            name = value.toString();
            break;
          case 'description':
            if (value != null) description = value.toString();
            break;
          case 'flags':
            if (value is List) {
              flags = value.map((e) => e.toString()).toList();
            }
            break;
        }
      }

      if (name != null) {
        functions.add(
          RedisFunctionInfo(name: name, description: description, flags: flags),
        );
      }
    }
    return functions;
  }

  /// 载入 Redis Function 库(FUNCTION LOAD)。
  Future<bool> loadRedisFunction(String luaBody, {bool replace = false}) async {
    // feature 039 只读守卫：FUNCTION LOAD 写路径
    guardReadOnly(operation: 'loadRedisFunction');
    final args = <String>[
      'FUNCTION',
      'LOAD',
      if (replace) 'REPLACE',
      luaBody,
    ];
    final result = await runCommand(args);
    // 成功时返回库名(如 'mylib')而非 'OK';错误回复以 'ERR' 开头。
    return result is String && result.isNotEmpty && !result.startsWith('ERR');
  }

  /// 删除 Redis Function 库(FUNCTION DELETE)。
  Future<bool> deleteRedisFunction(String libraryName) async {
    // feature 039 只读守卫：FUNCTION DELETE 写路径
    guardReadOnly(operation: 'deleteRedisFunction');
    final result = await runCommand(['FUNCTION', 'DELETE', libraryName]);
    return result is String && result == 'OK';
  }

  // ==========================================================================
  // Pub/Sub（订阅转发 SSE 的重订式消费，§2.5）
  // ==========================================================================

  /// Pub/Sub 消息流(broadcast)。首次访问时惰性创建 controller。
  Stream<PubSubMessage> get pubSubMessageStream {
    _ensurePubSubController();
    return _pubSubController!.stream;
  }

  void _ensurePubSubController() {
    _pubSubController ??= StreamController<PubSubMessage>.broadcast();
  }

  /// 建立 Pub/Sub 通道（惰性；连接在首个订阅时建立——重订式模型下
  /// 「专用连接」即订阅 SSE 流）。
  Future<void> pubSubEnsureConnected() async {
    if (!isConnected) throw Exception('未连接到 Redis');
    _ensurePubSubController();
  }

  /// 订阅频道(或模式)——加入目标集并重建订阅 SSE（见文件头「行为边界」）。
  Future<void> pubSubSubscribe(String channel, {bool isPattern = false}) async {
    await pubSubEnsureConnected();
    if (isPattern) {
      _subscribedPatterns.add(channel);
    } else {
      _subscribedChannels.add(channel);
    }
    await _reconnectSubscription();
  }

  /// 取消订阅频道(或模式)——目标集移除并重建（空集则断开订阅流）。
  Future<void> pubSubUnsubscribe(
    String channel, {
    bool isPattern = false,
  }) async {
    if (isPattern) {
      _subscribedPatterns.remove(channel);
    } else {
      _subscribedChannels.remove(channel);
    }
    if (_subscribedChannels.isEmpty && _subscribedPatterns.isEmpty) {
      await _cancelSubscriptionStream();
      return;
    }
    await _reconnectSubscription();
  }

  /// 发布消息(走命令通道,返回收到消息的客户端数)。
  Future<int> publish(String channel, String message) async {
    // feature 039 只读守卫：PUBLISH 发布消息(外部副作用)写路径
    guardReadOnly(operation: 'publish');
    final result = await runCommand(['PUBLISH', channel, message]);
    if (result is int) return result;
    if (result is num) return result.toInt();
    return int.tryParse(result.toString()) ?? 0;
  }

  /// 释放订阅流与 controller。幂等,可重复调用。
  Future<void> disposePubSub() async {
    await _cancelSubscriptionStream();
    _subscribedChannels.clear();
    _subscribedPatterns.clear();
    final controller = _pubSubController;
    _pubSubController = null;
    if (controller != null) {
      await controller.close();
    }
  }

  Future<void> _cancelSubscriptionStream() async {
    await _subLineSub?.cancel();
    _subLineSub = null;
    final client = _subClient;
    _subClient = null;
    if (client != null && _subOwnsClient) {
      client.close();
    }
  }

  /// 以当前目标集重建订阅 SSE（server 端点在连接时给定全量 channels/
  /// patterns——动态增删由整流重建承载）。generation 守卫丢弃重订窗口内
  /// 旧流的迟到消息。
  Future<void> _reconnectSubscription() async {
    final generation = ++_subGeneration;
    await _cancelSubscriptionStream();

    final channels = _subscribedChannels.toList()..sort();
    final patterns = _subscribedPatterns.toList()..sort();
    if (channels.isEmpty && patterns.isEmpty) return;

    final server = _requireServerSession();
    final token = await server.getAccessToken();
    final query = <String>[
      for (final c in channels)
        'channels=${Uri.encodeQueryComponent(c)}',
      for (final p in patterns)
        'patterns=${Uri.encodeQueryComponent(p)}',
    ].join('&');
    final uri = Uri.parse(
      '${server.serverUrl}/api/gw/connections/$_serverConnId/redis/subscriptions?$query',
    );
    final request = http.Request('GET', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    final client = httpClient ?? http.Client();
    _subClient = client;
    _subOwnsClient = httpClient == null;
    try {
      final response = await client.send(request);
      if (response.statusCode != 200) {
        final text = await response.stream.bytesToString();
        if (_subOwnsClient) client.close();
        _subClient = null;
        throw _decodeErrResponse(response.statusCode, text);
      }
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      String pendingEvent = '';
      String pendingData = '';

      void handleEvent(String event, String data) {
        if (generation != _subGeneration) return; // 迟到的旧流
        if (data.isEmpty) return;
        if (event == 'message') {
          final Map<String, dynamic> chunk;
          try {
            chunk = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          _pubSubController?.add(
            PubSubMessage(
              channel: chunk['channel']?.toString() ?? '',
              payload: chunk['payload']?.toString() ?? '',
              isPattern: chunk['pattern'] != null,
              pattern: chunk['pattern']?.toString(),
              timestamp: DateTime.now(),
            ),
          );
        }
        // subscribed 回执不转发到 UI（与旧版 subscribe 确认帧口径一致）。
      }

      _subLineSub = lines.listen(
        (line) {
          if (line.isEmpty) {
            handleEvent(pendingEvent, pendingData);
            pendingEvent = '';
            pendingData = '';
          } else if (line.startsWith('event:')) {
            pendingEvent = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            pendingData = line.substring(5).trim();
          }
        },
        onError: (Object e, StackTrace st) {
          if (generation == _subGeneration) {
            AppLogger.e(_tag, '订阅 SSE 流错误', e, st);
          }
        },
        onDone: () {
          if (generation == _subGeneration) {
            AppLogger.w(_tag, '订阅 SSE 流结束（server 连接删除或断开）');
          }
        },
      );
    } catch (e) {
      if (_subClient == client) {
        _subClient = null;
        if (_subOwnsClient) client.close();
      }
      rethrow;
    }
  }

  // ==========================================================================
  // 本地命令校验（validateCommand / 危险黑名单——与旧版逐字一致）
  // ==========================================================================

  @override
  SecurityCheckResult validateCommand(String command) {
    final parts = _parseCommand(command);
    if (parts.isEmpty) return SecurityCheckResult.ok;
    final cmd = parts.first.toUpperCase();

    final forbidden = [
      'FLUSHALL',
      'FLUSHDB',
      'CONFIG',
      'DEBUG',
      'SHUTDOWN',
      'MONITOR',
      'SAVE',
      'BGSAVE',
    ];
    if (forbidden.contains(cmd)) {
      return SecurityCheckResult(
        false,
        CommandRiskLevel.dangerous,
        reason: 'Redis dangerous command: $cmd',
      );
    }
    if (cmd == 'KEYS') {
      return SecurityCheckResult(
        false,
        CommandRiskLevel.dangerous,
        reason: 'KEYS 会阻塞 Redis，请使用 SCAN 代替',
      );
    }
    final writeCmds = [
      'SET',
      'DEL',
      'HSET',
      'HMSET',
      'LPUSH',
      'RPUSH',
      'SADD',
      'ZADD',
      'INCR',
      'DECR',
      'INCRBY',
      'DECRBY',
      'EXPIRE',
      'PEXPIRE',
      'RENAME',
      'RENAMENX',
      'LPOP',
      'RPOP',
      'SPOP',
      'ZREM',
      'HDEL',
      'LTRIM',
      'FLUSH',
      'MSET',
      'APPEND',
      'SETEX',
      'PSETEX',
      'SETNX',
    ];
    if (writeCmds.contains(cmd)) {
      return SecurityCheckResult(
        true,
        CommandRiskLevel.warning,
        reason: 'Redis 写操作需要确认',
      );
    }
    return SecurityCheckResult.ok;
  }

  // ==========================================================================
  // 网关 plumbing（认证 / 注册 / 映射 / 错误形状——与 SQL 族壳同构）
  // ==========================================================================

  void _assertConnected() {
    if (!isConnected) throw Exception('未连接到 Redis');
  }

  /// server 会话前置：网关模式硬依赖 dbmaster server（embedded 或远程）。
  ServerConnection _requireServerSession() {
    final server = ServerConnection();
    final baseUrl = server.serverUrl;
    if (baseUrl == null ||
        server.connectionState != ServerConnectionState.connected) {
      throw StateError(
        'Redis 网关模式需要已连接的 dbmaster server（未检测到会话；'
        'embedded 模式下请确认 dbmaster-server.exe 随包可用）',
      );
    }
    return server;
  }

  /// 连接草稿体（redis：凭据可选——空值不下发；auth 三态由凭据存在性
  /// 推导；defaultDatabase = db index；TLS 两键走 extra；server 侧 SSH
  /// 隧道对象原样透传）。
  Map<String, dynamic> _draftBody(DatabaseConnection connection) {
    final username = connection.username;
    final password = connection.password;
    final tlsWire = gatewayTlsWire(connection.extra);
    return {
      'dbType': 'redis',
      'host': connection.host,
      'port': connection.port,
      if (username != null && username.isNotEmpty) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      'defaultDatabase': '$_dbIndex',
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

  RedisGatewayException _decodeErrResponse(int status, String text) {
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
    return RedisGatewayException(code, message);
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
