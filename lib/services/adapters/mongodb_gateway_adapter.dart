//! T29 非 SQL 批次（B2，ADR-0006 §2.4/§2.7）· MongoDB 网关壳 adapter。
//!
//! **形态**：与 `mysql_gateway_adapter.dart` / `postgresql_gateway_adapter.dart`
//! 同构——类名/接口与直连版完全一致（`MongoDBAdapter`），DatabaseService
//! 工厂表与 UI `is MongoDBAdapter` 强转消费零改动（铁律 4）。本地不再持有
//! mongo_dart 连接，凭据经网关注册入 server vault（`POST /api/gw/connections`
//! + `extra` 集群四模式透传），执行一律走 **kind:"mongo" 的 runCommand 单
//! 形状**（`POST /api/gw/connections/{id}/query` SSE）——服务端分类：
//! 游标命令（find/aggregate/…）展平为文档行（单列 "doc"），非游标命令单
//! 文档单列 "result"，写命令（insert/update/delete/…）走 affectedRows
//! （响应 "n"）。embedded（本地 server 子进程）与远程 server 两形态由
//! [ServerConnection] 吸收。
//!
//! **取代**：原 `mongodb_adapter.dart`（mongo_dart 直连实现，2493 行）。
//! 断线自愈（`_withReconnect`/`_shouldReconnect` 瞬态码表）、`_dbCache`、
//! keep-alive 参与权、自装 URI 构建全部下线——网关每执行独立连接，
//! 无连接态可自愈；keep-alive 的 `SELECT 1` 通用分支在本壳被拦截为
//! `{ping:1}`（真实健康信号经网关回传）。
//!
//! **行为边界（v1，相对直连版的已知差异）**：
//! - **值的到达形态**：BSON 扩展类型经 server 转扩展 JSON 子文档
//!   （`{$oid}`/`{$date}`/`{$numberDecimal}`/…）；本壳的 `_convertCell`
//!   在展示行上解包（ObjectId→24 位 hex 串、Date→ISO 字符串…，对齐旧版
//!   `_convertValue` 展示语义），schema 推断（`inferDocumentSchema`）在
//!   **原始 JSON 形态**上做类型识别（`$oid` → ObjectId 等）。Binary 到达
//!   为 `{$binary:{base64,subType}}` 子文档（旧版为 hexString）——展示层
//!   罕见路径，不再转换（已知边界）。
//! - **集群 URI 构建**：direct/replicaSet/sharded/advanced 四模式经注册
//!   `extra` 透传，server 侧组 ClientOptions（凭据分离注入）；Pro
//!   `MongoClusterStrategy` 的客户端 URI 构建职责随直连下线（构造参数
//!   保留以兼容 DatabaseService 工厂注入，当前不参与执行）。
//! - **PD-5 副本集名校验**（hello setName 比对）下线——拓扑由 server 驱动
//!   发现；名不匹配将在 server 侧以 ServerSelection 错误显式失败。
//! - **useDatabase record-only**：记录目标库，命令经 `database` 参数路由；
//!   不再预开目标库连接（存在性由后续命令的 NamespaceNotFound 显式失败，
//!   旧版隐式失败于 open）。`createDatabase` 同为 record-only（Mongo 惰性
//!   建库语义不变）。
//! - **事务**：保持旧版 no-op（Mongo 不 implements TransactionalAdapter，
//!   UI 无事务入口；与 SQL 族的 fail-loud 先例不同——旧版语义即 no-op）。
//! - **stale 库自愈不适用**：find 对不存在库返回空集而非连接错误（无
//!   PG 3D000 等价物）；CONNECTION_FAILED 一律按真连接故障走
//!   onDisconnect，不重试。
//! - **extended JSON 入向不解析**：命令文档值为普通 JSON（客户端
//!   shell 解析器产普通值）；`{$oid}` 等扩展类型的**入向**表达随直连
//!   下线（旧版经 mongo_dart 类型系统），构造 ObjectId 需经插入让服务端
//!   生成（`_id` 留空即自动）。
//! - **TLS/useSSL 不透传**（server ClientOptions 暂无 TLS 位，与 SQL 族
//!   同款已知边界）。

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/database_models.dart';
import '../../utils/app_logger.dart';
import '../database_abstract.dart';
import '../mongodb_shell_parser.dart';
import '../server_connection.dart';
import 'ai_adapter_mixin.dart';
import 'mongo_cluster_strategy.dart';
import 'parsed_mongo_uri.dart';

/// 网关查询错误（SSE error 事件 / 4xx 前置校验失败）。`code` 对齐
/// c01 §4.4 稳定码集，`engineCode` 透传引擎原始码（Mongo 为错误
/// codeName，如 Unauthorized/NamespaceNotFound/READONLY）。与
/// `MySqlGatewayException` / `PostgreSqlGatewayException` 同形。
class MongoGatewayException implements Exception {
  final String code;
  final String message;
  final String? engineCode;

  const MongoGatewayException(this.code, this.message, {this.engineCode});

  @override
  String toString() {
    final eng = engineCode == null ? '' : ' (engine $engineCode)';
    return '[$code]$eng $message';
  }
}

/// MongoDB 适配器（网关壳实现：执行走 kind:"mongo" runCommand 通道）。
class MongoDBAdapter extends DatabaseAdapter
    with AiAdapterMixin, DisconnectAware {
  /// serverConnId 映射表 key（与 ConnectionProvider / DbGatewayService
  /// 三方共享同一 SharedPreferences key）。
  static const String _kServerIdMapKey = 'connection_server_id_map';

  static const String _tag = 'MongoDBAdapter';

  /// 测试注入的 HTTP 客户端（null = 每请求新建）。
  @visibleForTesting
  http.Client? httpClient;

  String? _serverConnId;
  DatabaseConnection? _currentConnection;

  /// 当前目标库（record-only useDatabase 的记录位；命令经 database 参数
  /// 路由）。缺省 = 连接的 database 字段（= auth 库），再缺省 'test'
  /// （对齐旧版 connect 的 targetDatabase 缺省）。
  String? _currentDatabase;

  /// 认证库（连接 database 字段缺省 admin——注册为 defaultDatabase，
  /// server 侧作为 Credential source；dropDatabase 当前库后回落此位）。
  String _authDatabase = 'admin';

  /// 在途执行的取消句柄（disconnect / 显式取消用）。
  String? _inFlightExecutionId;

  /// Pro 集群策略（构造兼容参数；集群组装已迁 server 侧 extra 透传，
  /// 见文件头「行为边界」）。
  // ignore: unused_field
  final MongoClusterStrategy? _clusterStrategy;

  MongoDBAdapter({MongoClusterStrategy? clusterStrategy})
      : _clusterStrategy = clusterStrategy;

  @override
  bool get isConnected => _serverConnId != null;

  @override
  DatabaseType get databaseType => DatabaseType.mongodb;

  @override
  String getDefaultBrowseQuery(String tableName, {int limit = 100}) {
    return 'db.$tableName.find().limit($limit)';
  }

  @override
  DatabaseConnection? get currentConnection => _currentConnection;

  /// feature 039 D3：刷新连接 readOnly（运行时开关实时生效；server 侧
  /// 注册行 read_only 为写命令硬执行位，本地仅记录——改 readOnly 需重连
  /// 重新注册才对 server 生效，与 SQL 族壳一致）。
  @override
  void updateReadOnly(bool value) {
    _currentConnection = _currentConnection?.copyWith(readOnly: value);
  }

  @override
  bool get isInTransaction => false;

  @override
  bool get supportsSchemaOperations => true;

  /// 解析 MongoDB 连接串（薄委托 → [ParsedMongoUri.parse]，C08 移库）。
  static ParsedMongoUri parseConnectionString(String raw) =>
      ParsedMongoUri.parse(raw);

  // ==========================================================================
  // 连接管理（网关：注册/复用 serverConnId，无本地 Mongo 连接）
  // ==========================================================================

  @override
  Future<bool> connect(DatabaseConnection connection) async {
    _currentConnection = connection;
    _authDatabase = connection.database?.isNotEmpty == true
        ? connection.database!
        : 'admin';
    _currentDatabase = connection.database?.isNotEmpty == true
        ? connection.database!
        : 'test';
    final server = _requireServerSession();

    // 1) 已有镜像映射 → 验证注册仍存在且 dbType 匹配（server 重置后失效）。
    final mapped = await _lookupServerIdMapping(connection.id);
    if (mapped != null) {
      final known = await _registeredTypes(server);
      final mappedType = known[mapped];
      if (mappedType == 'mongodb') {
        _serverConnId = mapped;
        return true;
      }
      AppLogger.w(
        _tag,
        mappedType == null
            ? 'mapped serverConnId $mapped not found on server, re-registering'
            : 'mapped serverConnId $mapped type mismatch '
                  '(registered=$mappedType, want mongodb), re-registering',
      );
    }

    // 2) 凭据草稿测试（对齐旧版 connect 的「真连」语义——凭据错误返回
    //    false 而非注册成功把失败推迟到首条命令）。
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

    // 3) 现场注册（凭据 + 集群 extra 入 server vault）+ 写回映射。
    final registered = await _registerConnection(connection);
    await _rememberServerIdMapping(connection.id, registered);
    _serverConnId = registered;
    return true;
  }

  @override
  Future<void> disconnect() async {
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
    _currentDatabase = null;
    // 旧直连版契约：disconnect 后 currentConnection 归 null（集成测试钉住）。
    _currentConnection = null;
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

  // 事务：保持旧版 no-op（Mongo 无 TransactionalAdapter 入口，见文件头）。

  @override
  Future<void> beginTransaction() async {}

  @override
  Future<void> commit() async {}

  @override
  Future<void> rollback() async {}

  // ==========================================================================
  // 执行核心（kind:"mongo" runCommand → SSE 聚合）
  // ==========================================================================

  /// 经网关执行一条 Mongo 命令文档，返回聚合 [QueryResult]。
  ///
  /// 服务端分类（ADR-0006 §2.4）：游标命令 → 单列 "doc" 文档行；非游标
  /// 命令 → 单列 "result" 单行；写命令 → 无行、affectedRows = 响应 "n"。
  Future<QueryResult> _runCommand(
    Map<String, dynamic> command, {
    String? database,
    int? rowLimit,
    int? timeoutMs,
  }) async {
    final server = _requireServerSession();
    _assertConnected();
    final startTime = DateTime.now();
    final executionId = _newExecutionId();
    _inFlightExecutionId = executionId;

    final effectiveDb = (database == null || database.isEmpty)
        ? _currentDatabase
        : database;
    final uri = Uri.parse(
      '${server.serverUrl}/api/gw/connections/$_serverConnId/query',
    );
    final token = await server.getAccessToken();
    final body = jsonEncode({
      'kind': 'mongo',
      'command': _prepareForWire(command),
      if (effectiveDb != null && effectiveDb.isNotEmpty)
        'database': effectiveDb,
      // 行限 = server 上限（gw_query_max_rows 默认 10000）：find 自带
      // limit 的语义由命令自身控制，壳侧不额外收窄（旧版无行限）。
      'rowLimit': rowLimit ?? 10000,
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
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final text = await response.stream.bytesToString();
        throw _decodeErrResponse(response.statusCode, text);
      }
      final lines =
          await response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .toList();
      return _parseSse(lines, startTime: startTime);
    } on MongoGatewayException catch (e) {
      // 传输/连接级失败 → 触发 onDisconnect（对齐旧版死 socket 语义；
      // 命令错误（DB_ERROR/codeName）不撕连接）。
      if (e.code == 'CONNECTION_FAILED' || e.code == 'NOT_FOUND') {
        onDisconnect?.call();
      }
      rethrow;
    } on http.ClientException catch (e) {
      onDisconnect?.call();
      throw MongoGatewayException(
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

  /// SSE 事件块解析（与 SQL 族壳同构；kind 判别字段不消费）。
  QueryResult _parseSse(List<String> lines, {required DateTime startTime}) {
    List<String> columns = const [];
    final rows = <Map<String, dynamic>>[];
    int? affectedRows;
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
          affectedRows = (chunk['affectedRows'] as num?)?.toInt();
          serverElapsedMs = (chunk['elapsedMs'] as num?)?.toInt();
        case 'error':
          throw MongoGatewayException(
            chunk['code']?.toString() ?? 'DB_ERROR',
            chunk['message']?.toString() ?? 'mongo command failed',
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
      throw const MongoGatewayException(
        'CONNECTION_FAILED',
        'gateway SSE stream ended without a complete event',
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

  /// 非游标命令 → 单响应文档（column "result"；无行/非对象 → 空映射）。
  Future<Map<String, dynamic>> _commandDoc(
    Map<String, dynamic> command, {
    String? database,
    int? timeoutMs,
  }) async {
    final result = await _runCommand(command, database: database, timeoutMs: timeoutMs);
    if (result.rows.isEmpty) return <String, dynamic>{};
    final doc = result.rows.first['result'];
    return doc is Map<String, dynamic>
        ? doc
        : (doc is Map ? Map<String, dynamic>.from(doc) : <String, dynamic>{});
  }

  /// 游标命令 → 文档列表（**原始 JSON 形态**，扩展类型子文档保留——
  /// schema 推断依赖；展示行另经 [_convertCell]）。
  Future<List<Map<String, dynamic>>> _cursorDocs(
    Map<String, dynamic> command, {
    String? database,
    int? rowLimit,
    int? timeoutMs,
  }) async {
    final result = await _runCommand(
      command,
      database: database,
      rowLimit: rowLimit,
      timeoutMs: timeoutMs,
    );
    return result.rows
        .map((r) => r['doc'])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// server 行限上限（gw_query_max_rows 默认 10000）。
  static const int _kGatewayMaxRows = 10000;

  /// find 族取数：desired ≤ 上限单发；超限走 **skip 分页**（每页 ≤ 上限，
  /// 游标耗尽即止）。多页时缺省补 `_id` 排序——自然序不稳定，排序是
  /// skip 分页正确性的前提（单页不隐式排序，保持旧版行为）。aggregate
  /// 的游标不走本路径（大结果聚合为已知上限边界）。
  Future<List<Map<String, dynamic>>> _findDocsPaged(
    Map<String, dynamic> command, {
    String? database,
    int? timeoutMs,
  }) async {
    final desired = command['limit'] as int? ?? _kGatewayMaxRows;
    if (desired <= _kGatewayMaxRows) {
      return _cursorDocs(
        command,
        database: database,
        rowLimit: desired,
        timeoutMs: timeoutMs,
      );
    }
    final hasSort = command['sort'] is Map;
    final sort = hasSort ? command['sort'] : <String, dynamic>{'_id': 1};
    var offset = (command['skip'] as int?) ?? 0;
    final docs = <Map<String, dynamic>>[];
    while (docs.length < desired) {
      final pageSize = min(_kGatewayMaxRows, desired - docs.length);
      final page = await _cursorDocs(
        {...command, 'sort': sort, 'skip': offset, 'limit': pageSize},
        database: database,
        rowLimit: pageSize,
        timeoutMs: timeoutMs,
      );
      docs.addAll(page);
      if (page.length < pageSize) break; // 游标耗尽
      offset += page.length;
    }
    return docs;
  }

  int? get _timeoutMsFromExtra {
    final secs = _currentConnection?.extra?['timeout'];
    return secs is num ? (secs * 1000).round() : null;
  }

  /// 旧版缺省 30s（mongo_dart `.timeout`）；网关侧由 server 墙钟强制。
  int get _timeoutMs => _timeoutMsFromExtra ?? 30000;

  /// 命令值预编码（wire 可 JSON 化）：DateTime → `{$date: ISO}`（server 侧
  /// 反解回 BSON Date，扩展 JSON 入向与出向对称）；其余类型原样（Date
  /// 之外的 Dart 专有类型不出现于命令面）。
  dynamic _prepareForWire(dynamic value) {
    if (value is DateTime) {
      return {'\$date': value.toUtc().toIso8601String()};
    }
    if (value is Map) {
      return {
        for (final e in value.entries) e.key.toString(): _prepareForWire(e.value),
      };
    }
    if (value is List) return [for (final item in value) _prepareForWire(item)];
    return value;
  }

  // ==========================================================================
  // 查询执行（MongoShellQueryParser → runCommand；SELECT 1 → ping 拦截）
  // ==========================================================================

  @override
  Future<QueryResult> executeQuery(String query, {String? database}) async {
    // feature 039 只读守卫：JSON 命令路径写操作（insert/update/delete/...）拦截。
    guardReadOnlyQuery(query, operation: 'executeQuery');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    final startTime = DateTime.now();

    // keep-alive 通用分支（DatabaseService `_keepAlivePing` 的 SELECT 1）
    // 拦截为真实 ping——经网关回传健康信号（旧版该输入落入「无法解析」
    // 信息行，永远假活）。
    if (query.trim().toUpperCase() == 'SELECT 1') {
      try {
        final result = await _runCommand(
          {'ping': 1},
          database: 'admin',
          timeoutMs: _timeoutMs,
        );
        return QueryResult(
          columns: result.columns,
          rows: result.rows,
          affectedRows: result.affectedRows,
          executionTime: result.executionTime,
        );
      } catch (e) {
        throw Exception('MongoDB 查询执行失败: $e');
      }
    }

    try {
      final parsed = MongoShellQueryParser.parseQuery(query);
      if (parsed != null) {
        final collectionName =
            parsed['collection'] as String? ?? _currentDatabase ?? 'test';
        final filter =
            (parsed['filter'] is Map
                ? Map<String, dynamic>.from(parsed['filter'] as Map)
                : null) ??
            <String, dynamic>{};
        final projection = parsed['projection'] is Map
            ? Map<String, dynamic>.from(parsed['projection'] as Map)
            : null;
        final limit = parsed['limit'] as int? ?? 100;
        final isCount = parsed['isCount'] as bool? ?? false;
        final isAggregate = parsed['isAggregate'] as bool? ?? false;
        final isDistinct = parsed['isDistinct'] as bool? ?? false;
        final method = parsed['method'] as String? ?? '';

        if (isCount) {
          // estimatedDocumentCount = 不带 query 的 count（元数据估计）。
          final cmd = <String, dynamic>{'count': collectionName};
          if (method != 'estimateddocumentcount' && filter.isNotEmpty) {
            cmd['query'] = filter;
          }
          final doc = await _commandDoc(cmd, timeoutMs: _timeoutMs);
          final count = (doc['n'] as num?)?.toInt() ?? 0;
          return QueryResult(
            columns: ['count'],
            rows: [
              {'count': count},
            ],
            executionTime: DateTime.now().difference(startTime).inMilliseconds,
          );
        }

        if (isAggregate) {
          final pipeline =
              (parsed['pipeline'] as List<dynamic>?)
                  ?.map(
                    (stage) => stage is Map
                        ? Map<String, dynamic>.from(stage)
                        : <String, dynamic>{},
                  )
                  .toList() ??
              <Map<String, dynamic>>[];
          return await aggregate(collectionName, pipeline);
        }

        if (isDistinct) {
          final field = parsed['field'] as String? ?? '';
          final cmd = <String, dynamic>{'distinct': collectionName, 'key': field};
          if (filter.isNotEmpty) cmd['query'] = filter;
          final doc = await _commandDoc(cmd, timeoutMs: _timeoutMs);
          final values = (doc['values'] as List<dynamic>?) ?? [];
          final rows = values
              .map<Map<String, dynamic>>((v) => {field: _convertCell(v)})
              .toList();
          return QueryResult(
            columns: [field],
            rows: rows.isNotEmpty
                ? rows
                : [
                    {field: '无匹配值'},
                  ],
            affectedRows: rows.length,
            executionTime: DateTime.now().difference(startTime).inMilliseconds,
          );
        }

        // find / findOne：find 命令参数化（projection/sort/skip/limit 全
        // 部下推服务端——旧版 modernFind 的服务端 sort/skip 语义）。
        final cmd = <String, dynamic>{
          'find': collectionName,
          'filter': filter,
          'limit': limit,
        };
        if (projection != null && projection.isNotEmpty) {
          cmd['projection'] = projection;
        }
        final sortRaw = parsed['sort'];
        if (sortRaw is Map) cmd['sort'] = Map<String, dynamic>.from(sortRaw);
        final skip = parsed['skip'];
        if (skip is int) cmd['skip'] = skip;

        // 行限超 server 上限时壳侧 skip 分页（见 _findDocsPaged）。
        final docs = await _findDocsPaged(cmd, timeoutMs: _timeoutMs);
        final rows = [
          for (final doc in docs) _documentToMap(doc),
        ];
        final columns = rows.isNotEmpty ? _extractColumns(rows) : ['result'];

        return QueryResult(
          columns: columns,
          rows: rows.isNotEmpty
              ? rows
              : [
                  {'result': '查询成功，无匹配文档'},
                ],
          affectedRows: rows.length,
          executionTime: DateTime.now().difference(startTime).inMilliseconds,
        );
      }

      return QueryResult(
        columns: ['result'],
        rows: [
          {
            'result':
                '请使用 JSON 格式查询: {"collection":"name","filter":{"field":"value"}} 或 MongoDB Shell 语法: db.collection.find({})',
          },
        ],
        executionTime: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      throw Exception('MongoDB 查询执行失败: $e');
    }
  }

  /// 展示行转换：文档 → map（值经 [_convertCell] 解包扩展 JSON 形态；
  /// projection 已在命令侧下推，此处不再过滤）。
  Map<String, dynamic> _documentToMap(Map<String, dynamic> doc) {
    return {
      for (final entry in doc.entries) entry.key: _convertCell(entry.value),
    };
  }

  /// 扩展 JSON 值 → 展示值（对齐旧版 `_convertValue` 的展示语义）：
  /// ObjectId→hex 串、Date→ISO 串、Decimal128→十进制串、Timestamp/Code/
  /// RegExp→字面量、嵌套文档/数组递归。
  dynamic _convertCell(dynamic value) {
    if (value is Map) {
      if (value.length == 1) {
        if (value.containsKey('\$oid')) return value['\$oid']?.toString();
        if (value.containsKey('\$date')) return value['\$date']?.toString();
        if (value.containsKey('\$numberDecimal')) {
          return value['\$numberDecimal']?.toString();
        }
        if (value.containsKey('\$timestamp')) return value.toString();
        if (value.containsKey('\$code')) {
          return (value['\$code'] ?? '').toString();
        }
        if (value.containsKey('\$regex')) {
          return value['\$regex']?.toString();
        }
        if (value.containsKey('\$ref')) return value;
      }
      return _documentToMap(Map<String, dynamic>.from(value));
    }
    if (value is List) return value.map(_convertCell).toList();
    return value;
  }

  List<String> _extractColumns(List<Map<String, dynamic>> rows) {
    final columns = <String>{};
    for (final row in rows) {
      columns.addAll(row.keys);
    }
    return columns.toList();
  }

  /// 原始 JSON 值的 BSON 类型名（对齐旧版 `_inferBsonType` 的名字面）：
  /// 扩展 JSON 子文档按键判型（$oid→ObjectId 等），普通 Map→Document。
  String _inferJsonBsonType(dynamic value) {
    if (value == null) return 'Null';
    if (value is String) return 'String';
    if (value is num) return 'Number';
    if (value is bool) return 'Boolean';
    if (value is List) return 'Array';
    if (value is Map) {
      if (value.containsKey('\$oid')) return 'ObjectId';
      if (value.containsKey('\$date')) return 'Date';
      if (value.containsKey('\$numberDecimal')) return 'Decimal128';
      if (value.containsKey('\$timestamp')) return 'Timestamp';
      if (value.containsKey('\$code')) return 'Code';
      if (value.containsKey('\$regex')) return 'RegExp';
      if (value.containsKey('\$ref')) return 'DBRef';
      return 'Document';
    }
    return value.runtimeType.toString();
  }

  @override
  Future<QueryResult> getExplainPlan(String query) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    final parsed = MongoShellQueryParser.parseQuery(query);
    if (parsed == null) {
      return QueryResult(
        columns: ['info'],
        rows: [
          {'info': '无法解析该 Mongo shell 语句，请使用 db.collection.find(...) 或 aggregate([...]) 语法后查看执行计划'},
        ],
      );
    }

    final collectionName =
        parsed['collection'] as String? ?? _currentDatabase ?? 'test';

    try {
      // 构造真正的 explain 命令（research D4）——与旧版同形。
      final explainCmd = <String, dynamic>{'verbosity': 'allPlansExecution'};

      final isAggregate = parsed['isAggregate'] as bool? ?? false;
      if (isAggregate) {
        final pipeline =
            (parsed['pipeline'] as List<dynamic>?)
                ?.map(
                  (stage) => stage is Map
                      ? Map<String, dynamic>.from(stage)
                      : <String, dynamic>{},
                )
                .toList() ??
            <Map<String, dynamic>>[];
        explainCmd['explain'] = {
          'aggregate': collectionName,
          'pipeline': pipeline,
          'cursor': {},
        };
      } else {
        final filter = parsed['filter'] is Map
            ? Map<String, dynamic>.from(parsed['filter'] as Map)
            : <String, dynamic>{};
        final findCmd = <String, dynamic>{
          'find': collectionName,
          'filter': filter,
        };
        final sortRaw = parsed['sort'];
        if (sortRaw is Map) findCmd['sort'] = Map<String, dynamic>.from(sortRaw);
        final skip = parsed['skip'];
        if (skip is int) findCmd['skip'] = skip;
        final limit = parsed['limit'];
        if (limit is int) findCmd['limit'] = limit;
        explainCmd['explain'] = findCmd;
      }

      final result = await _commandDoc(explainCmd, timeoutMs: _timeoutMs);
      return _formatExplainResult(result);
    } catch (e) {
      AppLogger.d(_tag, '获取执行计划失败: $e');
      return QueryResult(
        columns: ['info'],
        rows: [
          {'info': '获取执行计划失败: $e。请确认查询语法正确，且连接的账号具有 explain 权限。'},
        ],
      );
    }
  }

  /// explain 结果格式化（高亮摘要 + 原始 JSON，与旧版同形）。
  QueryResult _formatExplainResult(Map<String, dynamic> result) {
    final queryPlanner =
        result['queryPlanner'] is Map
            ? Map<String, dynamic>.from(result['queryPlanner'] as Map)
            : <String, dynamic>{};
    final executionStats =
        result['executionStats'] is Map
            ? Map<String, dynamic>.from(result['executionStats'] as Map)
            : <String, dynamic>{};

    final winningPlan = queryPlanner['winningPlan'] is Map
        ? Map<String, dynamic>.from(queryPlanner['winningPlan'] as Map)
        : null;
    final stage = winningPlan?['stage']?.toString() ?? 'unknown';
    final indexUsed = _extractIndexFromPlan(winningPlan);

    final nReturned = executionStats['nReturned']?.toString() ?? 'N/A';
    final totalDocsExamined =
        executionStats['totalDocsExamined']?.toString() ?? 'N/A';
    final executionTimeMillis =
        executionStats['executionTimeMillis']?.toString() ?? 'N/A';

    final rows = <Map<String, dynamic>>[
      {'阶段': 'winningPlan.stage', '值': stage},
      {'阶段': '使用索引', '值': indexUsed.isEmpty ? '(集合扫描)' : indexUsed},
      {'阶段': '返回文档数(nReturned)', '值': nReturned},
      {'阶段': '扫描文档数(totalDocsExamined)', '值': totalDocsExamined},
      {'阶段': '耗时(ms)', '值': executionTimeMillis},
      {'阶段': '完整计划(JSON)', '值': _prettyJson(result)},
    ];

    return QueryResult(columns: ['阶段', '值'], rows: rows);
  }

  String _extractIndexFromPlan(Map<String, dynamic>? plan) {
    if (plan == null) return '';
    if (plan['indexName'] is String) return plan['indexName'] as String;
    final inputStage = plan['inputStage'] is Map
        ? Map<String, dynamic>.from(plan['inputStage'] as Map)
        : null;
    if (inputStage != null) {
      final idx = _extractIndexFromPlan(inputStage);
      if (idx.isNotEmpty) return idx;
    }
    final shards = plan['shards'];
    if (shards is List) {
      for (final shard in shards) {
        if (shard is Map) {
          final winning = shard['winningPlan'] is Map
              ? Map<String, dynamic>.from(shard['winningPlan'] as Map)
              : null;
          final idx = _extractIndexFromPlan(winning);
          if (idx.isNotEmpty) return idx;
        }
      }
    }
    return '';
  }

  String _prettyJson(Map<String, dynamic> data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(_makeJsonSafe(data));
    } catch (_) {
      return data.toString();
    }
  }

  dynamic _makeJsonSafe(dynamic value) {
    if (value is Map) {
      return value.map(
        (k, v) => MapEntry<String, dynamic>(k.toString(), _makeJsonSafe(v)),
      );
    }
    if (value is List) return value.map(_makeJsonSafe).toList();
    return value;
  }

  // ==========================================================================
  // 库/集合发现（元数据经 listDatabases/listCollections 命令）
  // ==========================================================================

  @override
  Future<List<String>> getDatabases() async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final doc = await _commandDoc({'listDatabases': 1}, database: 'admin');
      final dbs = doc['databases'] as List<dynamic>? ?? [];
      return dbs
          .whereType<Map>()
          .map((d) => d['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
    } catch (e) {
      return ['admin', 'local', 'config', 'test'];
    }
  }

  @override
  Future<void> useDatabase(String dbName) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    // record-only：记录目标库，命令经 database 参数路由（见文件头）。
    _currentDatabase = dbName;
    _currentConnection = _currentConnection?.copyWith(database: dbName);
  }

  @override
  Future<List<String>> getTables() async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final docs = await _cursorDocs(
        {'listCollections': 1},
        timeoutMs: _timeoutMs,
      );
      return docs
          .map((c) => c['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty && !name.startsWith('system.'))
          .toList()
        ..sort();
    } catch (e) {
      return [];
    }
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
  Future<List<String>> getViews() async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final docs = await _cursorDocs(
        {'listCollections': 1, 'filter': {'type': 'view'}},
        timeoutMs: _timeoutMs,
      );
      final views = <String>[];
      for (final doc in docs) {
        final name = doc['name'];
        if (name is String && name.isNotEmpty) views.add(name);
      }
      views.sort();
      return views;
    } catch (e) {
      AppLogger.d(_tag, '获取视图列表失败: $e');
      return [];
    }
  }

  @override
  Future<List<DbColumn>> getTableColumns(String tableName) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      // 采样一条文档推断字段（旧版 findOne；类型识别在原始 JSON 形态上）。
      final docs = await _cursorDocs(
        {'find': tableName, 'limit': 1},
        timeoutMs: _timeoutMs,
      );
      final sample = docs.isNotEmpty ? docs.first : null;
      if (sample == null || sample.isEmpty) {
        return [
          DbColumn(
            name: '_id',
            type: 'ObjectId',
            isPrimaryKey: true,
            isNullable: false,
          ),
        ];
      }

      final columns = <DbColumn>[
        DbColumn(
          name: '_id',
          type: 'ObjectId',
          isPrimaryKey: true,
          isNullable: false,
        ),
      ];
      for (final entry in sample.entries) {
        if (entry.key == '_id') continue;
        columns.add(
          DbColumn(
            name: entry.key,
            type: _inferJsonBsonType(entry.value),
            isPrimaryKey: false,
            isNullable: true,
          ),
        );
      }
      return columns;
    } catch (e) {
      AppLogger.d(_tag, '获取集合列信息失败: $e');
      return [
        DbColumn(
          name: '_id',
          type: 'ObjectId',
          isPrimaryKey: true,
          isNullable: false,
        ),
      ];
    }
  }

  @override
  Future<List<DbIndex>> getTableIndexes(String tableName) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final docs = await _cursorDocs(
        {'listIndexes': tableName},
        timeoutMs: _timeoutMs,
      );
      return docs.map((idx) {
        final key = idx['key'];
        final columns = key is Map
            ? key.keys.map((k) => k.toString()).toList()
            : <String>[];
        return DbIndex(
          name: idx['name']?.toString() ?? 'unknown',
          columns: columns,
          isUnique: idx['unique'] == true,
        );
      }).toList();
    } catch (e) {
      return [
        DbIndex(name: '_id_', columns: ['_id'], isUnique: true),
      ];
    }
  }

  @override
  Future<DbTable> getTableDetails(String tableName) async {
    final columns = await getTableColumns(tableName);
    final indexes = await getTableIndexes(tableName);
    return DbTable(name: tableName, columns: columns, indexes: indexes);
  }

  @override
  Future<Map<String, dynamic>?> getServerVersion() async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final result = await _commandDoc(
        {'buildInfo': 1},
        database: 'admin',
        timeoutMs: _timeoutMs,
      );
      return {
        'version': result['version'] ?? 'unknown',
        'database': 'MongoDB',
        'gitVersion': result['gitVersion'],
        'maxBsonObjectSize': result['maxBsonObjectSize'],
      };
    } catch (e) {
      return {'version': 'unknown', 'database': 'MongoDB'};
    }
  }

  @override
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final collections = await getTables();
      int totalDocs = 0;
      for (final coll in collections) {
        try {
          final doc = await _commandDoc({'count': coll}, timeoutMs: _timeoutMs);
          totalDocs += (doc['n'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }
      return {
        'name': dbName,
        'collections': collections.length,
        'documents': totalDocs,
      };
    } catch (e) {
      return null;
    }
  }

  // ==========================================================================
  // 库/集合 DDL（命令族；Mongo 惰性建库语义）
  // ==========================================================================

  @override
  Future<bool> createDatabase(
    String dbName, {
    Map<String, dynamic>? options,
  }) async {
    guardReadOnly(operation: 'createDatabase');
    if (!isConnected) throw Exception('未连接到 MongoDB');
    // record-only（Mongo 首写建库，与旧版一致）。
    await useDatabase(dbName);
    return true;
  }

  @override
  Future<bool> dropDatabase(String dbName) async {
    guardReadOnly(operation: 'dropDatabase');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      await _runCommand(
        {'dropDatabase': 1},
        database: dbName,
        timeoutMs: _timeoutMs,
      );
      // 当前目标库被删 → 回落认证库（后续命令不再路由到已删库）。
      if (_currentDatabase == dbName) {
        _currentDatabase = _authDatabase;
      }
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
    guardReadOnly(operation: 'createTable');
    if (!isConnected) throw Exception('未连接到 MongoDB');
    // MongoDB 是无模式的，无需创建（与旧版一致）。
    return true;
  }

  @override
  Future<bool> dropTable(String tableName) async {
    guardReadOnly(operation: 'dropTable');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      await _runCommand({'drop': tableName}, timeoutMs: _timeoutMs);
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除集合失败: $e');
      return false;
    }
  }

  @override
  Future<bool> renameTable(String oldName, String newName) async {
    guardReadOnly(operation: 'renameTable');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      // renameCollection 是 admin 命令（旧版在目标库上跑大多静默失败）。
      final ns = _currentDatabase ?? 'test';
      await _runCommand(
        {
          'renameCollection': '$ns.$oldName',
          'to': '$ns.$newName',
          'dropTarget': false,
        },
        database: 'admin',
        timeoutMs: _timeoutMs,
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '重命名集合失败: $e');
      return false;
    }
  }

  @override
  Future<bool> truncateTable(
    String tableName, {
    TruncateOptions? options,
  }) async {
    guardReadOnly(operation: 'truncateTable');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      await _runCommand(
        {
          'delete': tableName,
          'deletes': [
            {'q': {}, 'limit': 0},
          ],
        },
        timeoutMs: _timeoutMs,
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '清空集合失败: $e');
      return false;
    }
  }

  // ==========================================================================
  // 数据读写
  // ==========================================================================

  @override
  Future<QueryResult> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
  }) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    final startTime = DateTime.now();

    try {
      // find 命令参数化：skip/limit 服务端分页（超 server 行限上限时壳侧
      // 再分页，见 _findDocsPaged）。
      final cmd = <String, dynamic>{
        'find': tableName,
        'limit': limit,
        if (offset > 0) 'skip': offset,
      };
      final docs = await _findDocsPaged(cmd, timeoutMs: _timeoutMs);
      final rows = [for (final doc in docs) _documentToMap(doc)];
      final columns = rows.isNotEmpty ? _extractColumns(rows) : ['_id'];

      return QueryResult(
        columns: columns,
        rows: rows.isNotEmpty
            ? rows
            : [
                {'_id': '(空集合)'},
              ],
        affectedRows: rows.length,
        executionTime: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      throw Exception('获取数据失败: $e');
    }
  }

  @override
  Future<int> getTableRowCount(String tableName) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final doc = await _commandDoc({'count': tableName}, timeoutMs: _timeoutMs);
      return (doc['n'] as num?)?.toInt() ?? 0;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<bool> addColumn(String tableName, DbColumn column) async {
    guardReadOnly(operation: 'addColumn');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      // 无模式：$set 为所有文档设默认值（默认值合成与旧版逐行一致）。
      dynamic defaultValue;
      final typeLower = column.type.toLowerCase();
      if (typeLower.contains('string') || typeLower.contains('text')) {
        defaultValue = '';
      } else if (typeLower.contains('int') || typeLower.contains('number')) {
        defaultValue = 0;
      } else if (typeLower.contains('bool')) {
        defaultValue = false;
      } else if (typeLower.contains('date') || typeLower.contains('time')) {
        defaultValue = DateTime.now().toIso8601String();
      } else if (typeLower.contains('array') || typeLower.contains('list')) {
        defaultValue = [];
      } else if (typeLower.contains('document') ||
          typeLower.contains('map') ||
          typeLower.contains('object')) {
        defaultValue = {};
      } else {
        defaultValue = null;
      }

      await _runCommand(
        {
          'update': tableName,
          'updates': [
            {
              'q': {},
              'u': {
                r'$set': {column.name: defaultValue},
              },
            },
          ],
        },
        timeoutMs: _timeoutMs,
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '添加字段失败: $e');
      return false;
    }
  }

  @override
  Future<bool> dropColumn(String tableName, String columnName) async {
    guardReadOnly(operation: 'dropColumn');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      await _runCommand(
        {
          'update': tableName,
          'updates': [
            {
              'q': {},
              'u': {
                r'$unset': {columnName: ''},
              },
            },
          ],
        },
        timeoutMs: _timeoutMs,
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除字段失败: $e');
      return false;
    }
  }

  @override
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn,
  ) async {
    guardReadOnly(operation: 'modifyColumn');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final targetField = newColumn.name;
      final typeLower = newColumn.type.toLowerCase();

      // 1) 重命名（如果名称变了）。
      if (oldColumnName != newColumn.name) {
        await _runCommand(
          {
            'update': tableName,
            'updates': [
              {
                'q': {},
                'u': {
                  r'$rename': {oldColumnName: newColumn.name},
                },
              },
            ],
          },
          timeoutMs: _timeoutMs,
        );
      }

      // 2) 管道类型转换（$toString/$toInt/…，与旧版同形）。
      final conversion = <String, String>{
        'string': r'$toString',
        'text': r'$toString',
        'int': r'$toInt',
        'double': r'$toDouble',
        'float': r'$toDouble',
        'bool': r'$toBool',
        'date': r'$toDate',
        'time': r'$toDate',
      };
      for (final key in conversion.keys) {
        if (typeLower.contains(key)) {
          await _runCommand(
            {
              'update': tableName,
              'updates': [
                {
                  'q': {
                    targetField: {r'$exists': true},
                  },
                  'u': [
                    {
                      r'$set': {
                        targetField: {conversion[key]: r'$' + targetField},
                      },
                    },
                  ],
                },
              ],
            },
            timeoutMs: _timeoutMs,
          );
          break;
        }
      }
      return true;
    } catch (e) {
      AppLogger.d(_tag, '修改字段失败: $e');
      return false;
    }
  }

  @override
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName,
  ) async {
    guardReadOnly(operation: 'renameColumn');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      await _runCommand(
        {
          'update': tableName,
          'updates': [
            {
              'q': {},
              'u': {
                r'$rename': {oldColumnName: newColumnName},
              },
            },
          ],
        },
        timeoutMs: _timeoutMs,
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '重命名字段失败: $e');
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
    guardReadOnly(operation: 'createIndex');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final keys = <String, dynamic>{};
      for (final col in columns) {
        keys[col] = 1;
      }
      await _runCommand(
        {
          'createIndexes': tableName,
          'indexes': [
            {
              'key': keys,
              'name': indexName,
              if (unique) 'unique': true,
            },
          ],
        },
        timeoutMs: _timeoutMs,
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '创建索引失败: $e');
      return false;
    }
  }

  @override
  Future<bool> dropIndex(String tableName, String indexName) async {
    guardReadOnly(operation: 'dropIndex');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      await _runCommand(
        {'dropIndexes': tableName, 'index': indexName},
        timeoutMs: _timeoutMs,
      );
      return true;
    } catch (e) {
      AppLogger.d(_tag, '删除索引失败: $e');
      return false;
    }
  }

  @override
  Future<String> exportDatabaseStructure(String dbName) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    final sb = StringBuffer();
    sb.writeln('// MongoDB Database Export');
    sb.writeln('// Database: $dbName');
    sb.writeln('// Date: ${DateTime.now().toIso8601String()}');
    sb.writeln();

    try {
      final collections = await getTables();
      for (final coll in collections) {
        sb.writeln('// Collection: $coll');
        final columns = await getTableColumns(coll);
        for (final col in columns) {
          sb.writeln(
            '//   - ${col.name}: ${col.type} ${col.isPrimaryKey ? "(PK)" : ""}',
          );
        }
        final indexes = await getTableIndexes(coll);
        for (final idx in indexes) {
          sb.writeln(
            '//   Index: ${idx.name} on ${idx.columns.join(", ")} ${idx.isUnique ? "(unique)" : ""}',
          );
        }
        sb.writeln();
      }
    } catch (e) {
      sb.writeln('// Export error: $e');
    }

    sb.writeln('// 使用 mongodump 命令导出完整数据');
    return sb.toString();
  }

  @override
  Future<bool> executeSqlScript(String script) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final lines = script
          .split('\n')
          .where(
            (l) =>
                l.trim().isNotEmpty &&
                !l.startsWith('//') &&
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
  // MongoDB 特有操作（面板/AI/可视化消费面，签名零改动）
  // ==========================================================================

  /// 插入单个文档。
  Future<bool> insertOne(
    String collectionName,
    Map<String, dynamic> document,
  ) async {
    guardReadOnly(operation: 'insertOne');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final result = await _runCommand(
        {
          'insert': collectionName,
          'documents': [document],
        },
        timeoutMs: _timeoutMs,
      );
      return (result.affectedRows ?? 0) >= 1;
    } catch (e) {
      AppLogger.d(_tag, '插入文档失败: $e');
      return false;
    }
  }

  /// 插入多个文档。
  Future<bool> insertMany(
    String collectionName,
    List<Map<String, dynamic>> documents,
  ) async {
    guardReadOnly(operation: 'insertMany');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final result = await _runCommand(
        {'insert': collectionName, 'documents': documents},
        timeoutMs: _timeoutMs,
      );
      return (result.affectedRows ?? 0) >= 1;
    } catch (e) {
      AppLogger.d(_tag, '批量插入失败: $e');
      return false;
    }
  }

  // AI 写/运维工具对应的 adapter 方法（research D8/D9/D10）。

  /// 导入（插入）一组文档，委托给 [insertMany]。
  Future<bool> importDocuments(
    String collectionName,
    List<Map<String, dynamic>> documents,
  ) async {
    guardReadOnly(operation: 'importDocuments');
    return insertMany(collectionName, documents);
  }

  /// 基于推断的 schema 生成测试文档并插入，返回实际插入条数。
  Future<int> generateTestData(String collectionName, int count) async {
    guardReadOnly(operation: 'generateTestData');
    if (!isConnected) throw Exception('未连接到 MongoDB');
    if (count <= 0) return 0;

    try {
      final schema = await inferDocumentSchema(collectionName);
      final fields = (schema['fields'] as Map<String, dynamic>?) ?? {};
      final documents = <Map<String, dynamic>>[];
      for (var i = 0; i < count; i++) {
        documents.add(_synthesizeDocument(fields, i));
      }
      final ok = await insertMany(collectionName, documents);
      return ok ? documents.length : 0;
    } catch (e) {
      AppLogger.d(_tag, '生成测试数据失败: $e');
      return 0;
    }
  }

  /// 根据字段类型合成单个测试文档（_id 留给服务端自动生成）。
  Map<String, dynamic> _synthesizeDocument(
    Map<String, dynamic> fields,
    int index,
  ) {
    final doc = <String, dynamic>{};
    for (final entry in fields.entries) {
      if (entry.key == '_id') continue;
      final fieldSpec = entry.value;
      final type = (fieldSpec is Map ? fieldSpec['type'] : null)?.toString() ??
          'string';
      doc[entry.key] = _sampleValueForType(type, entry.key, index);
    }
    return doc;
  }

  dynamic _sampleValueForType(String bsonType, String field, int index) {
    switch (bsonType) {
      case 'int':
      case 'long':
      case 'Number':
        return index;
      case 'double':
        return index.toDouble();
      case 'bool':
      case 'Boolean':
        return index.isEven;
      case 'date':
      case 'datetime':
      case 'Date':
        return DateTime.now().subtract(Duration(seconds: index)).toIso8601String();
      case 'array':
      case 'Array':
        return <dynamic>[];
      case 'object':
      case 'document':
      case 'Document':
        return <String, dynamic>{};
      case 'null':
      case 'Null':
        return null;
      case 'objectId':
      case 'ObjectId':
        return null; // 让服务端生成
      case 'string':
      case 'String':
      default:
        return 'test_${field}_$index';
    }
  }

  /// 导出集合为 JSON 或 CSV 文本（research D9）。
  Future<String> exportCollection(
    String collectionName, {
    Map<String, dynamic>? filter,
    int? limit,
    required String format,
  }) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');
    final fmt = format.toLowerCase();

    try {
      final cap = limit ?? 1000;
      final cmd = <String, dynamic>{
        'find': collectionName,
        'limit': cap,
        if (filter != null && filter.isNotEmpty) 'filter': filter,
      };
      final docs = await _cursorDocs(
        cmd,
        rowLimit: cap < 10000 ? cap : null,
        timeoutMs: _timeoutMs,
      );

      if (fmt == 'csv') {
        return _docsToCsv([for (final doc in docs) _documentToMap(doc)]);
      }
      return const JsonEncoder.withIndent('  ').convert(
        _makeJsonSafe([for (final doc in docs) _documentToMap(doc)]),
      );
    } catch (e) {
      AppLogger.d(_tag, '导出集合失败: $e');
      return '[]';
    }
  }

  String _docsToCsv(List<Map<String, dynamic>> docs) {
    if (docs.isEmpty) return '';
    final header = <String>[];
    final headerSet = <String>{};
    for (final doc in docs) {
      for (final key in doc.keys) {
        if (headerSet.add(key)) header.add(key);
      }
    }
    final buffer = StringBuffer();
    buffer.writeln(header.map(_csvEscape).join(','));
    for (final doc in docs) {
      final row = header
          .map((k) => _csvEscape(_csvValue(doc[k])))
          .join(',');
      buffer.writeln(row);
    }
    return buffer.toString();
  }

  String _csvValue(dynamic value) {
    if (value == null) return '';
    if (value is Map || value is List) {
      return const JsonEncoder().convert(_makeJsonSafe(value));
    }
    return value.toString();
  }

  String _csvEscape(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }

  /// 导出前分析：原生 Mongo 统计 + 抽样（research D9）。
  Future<Map<String, dynamic>> analyzeExport(
    String collectionName, {
    int sampleLimit = 3,
  }) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final stats = await getCollectionStats(collectionName);
      final sample = await _cursorDocs(
        {'find': collectionName, 'limit': sampleLimit},
        timeoutMs: _timeoutMs,
      );
      return {
        'stats': stats,
        'sample': [for (final doc in sample) _documentToMap(doc)],
      };
    } catch (e) {
      AppLogger.d(_tag, '导出分析失败: $e');
      return {'stats': <String, dynamic>{}, 'sample': <Map<String, dynamic>>[]};
    }
  }

  /// 数据质量分析：基于推断 schema 的每字段完整度/类型一致性（research D10）。
  Future<List<Map<String, dynamic>>> analyzeDataQuality(
    String collectionName,
  ) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final schema = await inferDocumentSchema(collectionName);
      final totalSampled = (schema['totalSampled'] as int?) ?? 0;
      final fields = (schema['fields'] as Map<String, dynamic>?) ?? {};

      if (totalSampled == 0 || fields.isEmpty) {
        return [
          {
            'collection': collectionName,
            'note': '集合为空或无样本文档，无法分析数据质量',
          },
        ];
      }

      final reports = <Map<String, dynamic>>[];
      for (final entry in fields.entries) {
        final spec = entry.value;
        final occurrence = (spec is Map ? spec['occurrence'] : null) as int? ?? 0;
        final type = (spec is Map ? spec['type'] : null)?.toString() ?? 'unknown';
        final completeness = occurrence / totalSampled;
        reports.add({
          'field': entry.key,
          'type': type,
          'present': occurrence,
          'sampled': totalSampled,
          'completeness': '${(completeness * 100).toStringAsFixed(1)}%',
          'missing': totalSampled - occurrence,
        });
      }
      return reports;
    } catch (e) {
      AppLogger.d(_tag, '数据质量分析失败: $e');
      return [];
    }
  }

  /// 更新单个文档。**wire 边界**：update 是写命令——server 走 affectedRows
  /// 通道（响应 "n"，无 result 行），nModified 不上 wire；本方法返回 n
  /// （匹配数，旧版优先 nModified 的差异为已知边界）。
  Future<int> updateOne(
    String collectionName,
    Map<String, dynamic> filter,
    Map<String, dynamic> update,
  ) async {
    guardReadOnly(operation: 'updateOne');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      return await _runUpdate(collectionName, filter, update, multi: false);
    } catch (e) {
      AppLogger.d(_tag, '更新文档失败: $e');
      return 0;
    }
  }

  /// 更新多个文档（计数语义同 [updateOne]：n = 匹配数）。
  Future<int> updateMany(
    String collectionName,
    Map<String, dynamic> filter,
    Map<String, dynamic> update,
  ) async {
    guardReadOnly(operation: 'updateMany');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      return await _runUpdate(collectionName, filter, update, multi: true);
    } catch (e) {
      AppLogger.d(_tag, '批量更新失败: $e');
      return 0;
    }
  }

  Future<int> _runUpdate(
    String collectionName,
    Map<String, dynamic> filter,
    Map<String, dynamic> update, {
    required bool multi,
  }) async {
    final result = await _runCommand(
      {
        'update': collectionName,
        'updates': [
          {'q': filter, 'u': update, 'multi': multi},
        ],
      },
      timeoutMs: _timeoutMs,
    );
    return result.affectedRows ?? 0;
  }

  /// 删除单个文档（limit: 1）。
  Future<int> deleteOne(
    String collectionName,
    Map<String, dynamic> filter,
  ) async {
    guardReadOnly(operation: 'deleteOne');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      return await _runDelete(collectionName, filter, limit: 1);
    } catch (e) {
      AppLogger.d(_tag, '删除文档失败: $e');
      return 0;
    }
  }

  /// 删除多个文档（limit: 0 = 全部）。
  Future<int> deleteMany(
    String collectionName,
    Map<String, dynamic> filter,
  ) async {
    guardReadOnly(operation: 'deleteMany');
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      return await _runDelete(collectionName, filter, limit: 0);
    } catch (e) {
      AppLogger.d(_tag, '批量删除失败: $e');
      return 0;
    }
  }

  Future<int> _runDelete(
    String collectionName,
    Map<String, dynamic> filter, {
    required int limit,
  }) async {
    // delete 是写命令：n 经 affectedRows 通道（无 result 行）。
    final result = await _runCommand(
      {
        'delete': collectionName,
        'deletes': [
          {'q': filter, 'limit': limit},
        ],
      },
      timeoutMs: _timeoutMs,
    );
    return result.affectedRows ?? 0;
  }

  /// 统计文档数量。
  Future<int> countDocuments(
    String collectionName, {
    Map<String, dynamic>? filter,
  }) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final cmd = <String, dynamic>{'count': collectionName};
      if (filter != null && filter.isNotEmpty) cmd['query'] = filter;
      final doc = await _commandDoc(cmd, timeoutMs: _timeoutMs);
      return (doc['n'] as num?)?.toInt() ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// 聚合查询。
  Future<QueryResult> aggregate(
    String collectionName,
    List<Map<String, dynamic>> pipeline,
  ) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    final startTime = DateTime.now();

    try {
      final docs = await _cursorDocs(
        {'aggregate': collectionName, 'pipeline': pipeline, 'cursor': {}},
        timeoutMs: _timeoutMs,
      );
      final rows = [for (final doc in docs) _documentToMap(doc)];
      final columns = rows.isNotEmpty ? _extractColumns(rows) : ['result'];

      return QueryResult(
        columns: columns,
        rows: rows.isNotEmpty
            ? rows
            : [
                {'result': '聚合查询完成，无结果'},
              ],
        affectedRows: rows.length,
        executionTime: DateTime.now().difference(startTime).inMilliseconds,
      );
    } catch (e) {
      throw Exception('聚合查询失败: $e');
    }
  }

  /// 只读写判定（feature 039，只读守卫用）：复用 [validateCommand] 的写分类。
  @override
  bool isWriteCommand(String query) =>
      validateCommand(query).riskLevel != CommandRiskLevel.safe;

  @override
  SecurityCheckResult validateCommand(String command) {
    final lower = command.toLowerCase();
    final forbidden = [
      'dropdatabase',
      'dropuser',
      'shutdownserver',
      'eval',
      'revoke',
    ];
    for (final f in forbidden) {
      if (lower.contains(f)) {
        return SecurityCheckResult(
          false,
          CommandRiskLevel.dangerous,
          reason: 'Dangerous operation detected: $f',
        );
      }
    }
    final writeOps = [
      'insert',
      'update',
      'delete',
      'drop',
      'remove',
      'createcollection',
      'renamecollection',
    ];
    for (final w in writeOps) {
      if (lower.contains(w)) {
        return SecurityCheckResult(
          true,
          CommandRiskLevel.warning,
          reason: '写操作 $w 需要确认',
        );
      }
    }
    return SecurityCheckResult.ok;
  }

  // ========== MongoDB 导航扩展方法 ==========

  /// 获取数据库的集合列表（包含类型/选项信息）。[dbName] 为目标库（经
  /// database 参数路由；旧版经 useDatabase 切换活动 Db，等价）。
  Future<List<Map<String, dynamic>>> listCollections(String dbName) async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final docs = await _cursorDocs(
        {'listCollections': 1, 'nameOnly': false},
        database: dbName,
        timeoutMs: _timeoutMs,
      );
      return docs.map((item) {
        final name = item['name'] as String? ?? '';
        final type = item['type'] as String? ?? 'collection';
        final options = item['options'] is Map
            ? Map<String, dynamic>.from(item['options'] as Map)
            : <String, dynamic>{};
        return {
          'name': name,
          'type': type,
          'options': options,
          'isCapped': options['capped'] == true,
          'isView': type == 'view',
          'isTimeSeries': options['timeseries'] != null,
          'viewOn': options['viewOn'] as String?,
        };
      }).toList();
    } catch (e) {
      AppLogger.d(_tag, '获取集合列表失败: $e');
      return [];
    }
  }

  /// 获取集合统计信息。
  Future<Map<String, dynamic>> getCollectionStats(String collectionName) async {
    if (!isConnected) {
      return {
        'documentCount': 0,
        'storageSize': 0,
        'size': 0,
        'isCapped': false,
      };
    }

    try {
      final result = await _commandDoc(
        {'collStats': collectionName},
        timeoutMs: _timeoutMs,
      );
      return {
        'ns': result['ns']?.toString() ?? '',
        'documentCount': result['count'] ?? 0,
        'storageSize': result['storageSize'] ?? 0,
        'size': result['size'] ?? 0,
        'avgObjSize': result['avgObjSize'] ?? 0,
        'indexCount': result['nindexes'] ?? 0,
        'totalIndexSize': result['totalIndexSize'] ?? 0,
        'isCapped': result['capped'] == true,
        'maxSize': result['maxSize'],
      };
    } catch (e) {
      AppLogger.d(_tag, '获取集合统计信息失败: $e');
      return {
        'documentCount': 0,
        'storageSize': 0,
        'size': 0,
        'isCapped': false,
      };
    }
  }

  /// 推断集合的文档结构（Schema；类型识别在原始 JSON 形态上）。
  Future<Map<String, dynamic>> inferDocumentSchema(
    String collectionName, {
    int sampleSize = 100,
  }) async {
    if (!isConnected) {
      return {
        'collectionName': collectionName,
        'totalSampled': 0,
        'fields': <String, dynamic>{},
      };
    }

    try {
      final docs = await _cursorDocs(
        {'find': collectionName, 'limit': sampleSize},
        rowLimit: sampleSize < 10000 ? sampleSize : null,
        timeoutMs: _timeoutMs,
      );
      final schema = <String, dynamic>{};
      for (final doc in docs) {
        _mergeDocumentSchema(schema, doc);
      }
      return {
        'collectionName': collectionName,
        'totalSampled': docs.length,
        'fields': schema,
      };
    } catch (e) {
      AppLogger.d(_tag, '推断文档结构失败: $e');
      return {
        'collectionName': collectionName,
        'totalSampled': 0,
        'fields': <String, dynamic>{},
      };
    }
  }

  /// 递归合并文档 Schema（occurrence / Mixed 逻辑与旧版一致）。
  void _mergeDocumentSchema(
    Map<String, dynamic> schema,
    Map<String, dynamic> doc,
  ) {
    for (final entry in doc.entries) {
      final fieldName = entry.key;
      final value = entry.value;
      final bsonType = _inferJsonBsonType(value);

      if (!schema.containsKey(fieldName)) {
        schema[fieldName] = {'type': bsonType, 'occurrence': 1};

        if (value is Map && value.isNotEmpty && bsonType == 'Document') {
          final subSchema = <String, dynamic>{};
          _mergeDocumentSchema(subSchema, Map<String, dynamic>.from(value));
          schema[fieldName]['subFields'] = subSchema;
        } else if (value is List && value.isNotEmpty && bsonType == 'Array') {
          final elementTypes = <String>{};
          for (final element in value.take(10)) {
            elementTypes.add(_inferJsonBsonType(element));
          }
          schema[fieldName]['elementTypes'] = elementTypes.toList();

          final firstDoc = value.firstWhere(
            (e) => e is Map,
            orElse: () => null,
          );
          if (firstDoc != null) {
            final subSchema = <String, dynamic>{};
            _mergeDocumentSchema(
              subSchema,
              Map<String, dynamic>.from(firstDoc as Map),
            );
            schema[fieldName]['subFields'] = subSchema;
          }
        }
      } else {
        final currentOccurrence =
            (schema[fieldName]['occurrence'] as int?) ?? 1;
        schema[fieldName]['occurrence'] = currentOccurrence + 1;

        final existingType = schema[fieldName]['type'] as String?;
        if (existingType != null &&
            existingType != bsonType &&
            existingType != 'Mixed') {
          schema[fieldName]['type'] = 'Mixed';
        }
      }
    }
  }

  /// 获取 MongoDB 服务器状态（serverStatus，回退 buildInfo——与旧版同形）。
  Future<Map<String, dynamic>> getServerStatus() async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final result = await _commandDoc(
        {'serverStatus': 1},
        database: 'admin',
        timeoutMs: _timeoutMs,
      );

      final hostFromStatus = result['host'] as String?;
      final hostFromConn = _currentConnection?.host ?? 'unknown';
      final portFromConn = _currentConnection?.port ?? 0;
      final hostDisplay =
          hostFromStatus ??
          (portFromConn > 0 ? '$hostFromConn:$portFromConn' : hostFromConn);

      String storageEngine = 'unknown';
      final se = result['storageEngine'];
      if (se is Map) {
        storageEngine = se['name']?.toString() ?? 'unknown';
      }

      return {
        'version': result['version'] ?? 'unknown',
        'uptime': result['uptime'] ?? 0,
        'host': hostDisplay,
        'process': result['process'] ?? 'unknown',
        'connections': {
          'current': _nestedNum(result, ['connections', 'current']) ?? 0,
          'available': _nestedNum(result, ['connections', 'available']) ?? 0,
          'totalCreated':
              _nestedNum(result, ['connections', 'totalCreated']) ?? 0,
        },
        'memory': {
          'resident': _nestedNum(result, ['mem', 'resident']) ?? 0,
          'virtual': _nestedNum(result, ['mem', 'virtual']) ?? 0,
        },
        'storageEngine': storageEngine,
        'ok': result['ok'] == 1.0 || result['ok'] == 1,
      };
    } catch (e) {
      AppLogger.d(_tag, 'serverStatus 失败，尝试回退到 buildInfo: $e');
      try {
        final buildInfo = await _commandDoc(
          {'buildInfo': 1},
          database: 'admin',
          timeoutMs: _timeoutMs,
        );
        final hostFromUri = _currentConnection?.host ?? 'unknown';
        final portFromUri = _currentConnection?.port.toString() ?? '';
        final hostDisplay = portFromUri.isNotEmpty
            ? '$hostFromUri:$portFromUri'
            : hostFromUri;

        return {
          'version': buildInfo['version'] ?? 'unknown',
          'uptime': 0,
          'host': hostDisplay,
          'process': 'mongod',
          'connections': {'current': 0, 'available': 0, 'totalCreated': 0},
          'memory': {'resident': 0, 'virtual': 0},
          'storageEngine': _firstEngine(buildInfo['storageEngines']),
          'ok': true,
          'fallback': true,
        };
      } catch (fallbackError) {
        AppLogger.d(_tag, 'buildInfo 回退也失败: $fallbackError');
        return {
          'version': 'unknown',
          'uptime': 0,
          'host': _currentConnection?.host ?? 'unknown',
          'ok': false,
        };
      }
    }
  }

  /// 嵌套数字读取（serverStatus 的 connections/mem 子文档）。
  int? _nestedNum(Map<String, dynamic> doc, List<String> path) {
    dynamic current = doc;
    for (final key in path) {
      if (current is! Map) return null;
      current = current[key];
    }
    return current is num ? current.toInt() : null;
  }

  /// storageEngines 列表首项（缺省 'unknown'）。
  String _firstEngine(dynamic engines) {
    if (engines is List && engines.isNotEmpty) {
      return engines.first.toString();
    }
    return 'unknown';
  }

  /// 获取 MongoDB 构建信息。
  Future<Map<String, dynamic>> getBuildInfo() async {
    if (!isConnected) throw Exception('未连接到 MongoDB');

    try {
      final result = await _commandDoc(
        {'buildInfo': 1},
        database: 'admin',
        timeoutMs: _timeoutMs,
      );
      return {
        'version': result['version'] ?? 'unknown',
        'gitVersion': result['gitVersion'] ?? 'unknown',
        'targetMinOS': result['targetMinOS'],
        'buildEnvironment': result['buildEnvironment'],
        'storageEngines': result['storageEngines'] as List<dynamic>?,
        'javascriptEngine': result['javascriptEngine'],
        'maxBsonObjectSize': result['maxBsonObjectSize'] ?? 16777216,
        'bits': result['bits'] ?? 64,
        'debug': result['debug'] ?? false,
        'maxConnections': result['maxBsonObjectSize'] ?? 819,
      };
    } catch (e) {
      AppLogger.d(_tag, '获取构建信息失败: $e');
      return {'version': 'unknown', 'maxBsonObjectSize': 16777216};
    }
  }

  /// 获取 GridFS Buckets 列表（files+chunks 集合对探测）。
  Future<List<Map<String, dynamic>>> getGridFSBuckets() async {
    if (!isConnected) return [];

    try {
      final collections = await getTables();
      final buckets = <String>{};
      for (final coll in collections) {
        if (coll.endsWith('.files')) {
          final bucket = coll.substring(0, coll.length - 6);
          if (collections.contains('$bucket.chunks')) {
            buckets.add(bucket);
          }
        }
      }
      return buckets
          .map(
            (bucket) => <String, String>{
              'name': bucket,
              'filesCollection': '$bucket.files',
              'chunksCollection': '$bucket.chunks',
            },
          )
          .toList();
    } catch (e) {
      AppLogger.d(_tag, '获取 GridFS Buckets 失败: $e');
      return [];
    }
  }

  /// 获取 GridFS Bucket 统计信息。
  Future<Map<String, dynamic>> getGridFSBucketStats(String bucketName) async {
    if (!isConnected) return {};

    try {
      final filesStats = await getCollectionStats('$bucketName.files');
      final chunksStats = await getCollectionStats('$bucketName.chunks');
      return {
        'bucketName': bucketName,
        'filesCount': filesStats['documentCount'] ?? 0,
        'chunksCount': chunksStats['documentCount'] ?? 0,
        'filesSize': filesStats['size'] ?? 0,
        'chunksSize': chunksStats['size'] ?? 0,
        'totalSize': (filesStats['size'] ?? 0) + (chunksStats['size'] ?? 0),
      };
    } catch (e) {
      AppLogger.d(_tag, '获取 GridFS Bucket 统计失败: $e');
      return {};
    }
  }

  /// 获取副本集状态（replSetGetStatus 为 admin 命令——database 路由 admin；
  /// 非副本集/无权限返回 null，与旧版一致）。
  Future<Map<String, dynamic>?> getReplicaSetStatus() async {
    if (!isConnected) return null;

    try {
      final result = await _commandDoc(
        {'replSetGetStatus': 1},
        database: 'admin',
        timeoutMs: _timeoutMs,
      );
      if (result['ok'] != 1.0 && result['ok'] != 1) return null;

      final members = (result['members'] as List<dynamic>?)
          ?.map(
            (m) => <String, dynamic>{
              'name': m is Map ? m['name'] ?? 'unknown' : 'unknown',
              'state': m is Map ? m['stateStr'] ?? 'UNKNOWN' : 'UNKNOWN',
              'stateCode': m is Map ? m['state'] ?? -1 : -1,
              'health': m is Map ? m['health'] ?? 0 : 0,
              'uptime': m is Map ? m['uptime'] ?? 0 : 0,
              'optimeDate': m is Map ? m['optimeDate']?.toString() : null,
            },
          )
          .toList();

      return {
        'setName': result['set'] ?? 'unknown',
        'myState': result['myState'] ?? -1,
        'members': members ?? [],
      };
    } catch (e) {
      AppLogger.d(_tag, '不是副本集或获取副本集状态失败: $e');
      return null;
    }
  }

  /// 获取分片集群状态（listShards 为 admin 命令）。
  Future<Map<String, dynamic>?> getShardingStatus() async {
    if (!isConnected) return null;

    try {
      final result = await _commandDoc(
        {'listShards': 1},
        database: 'admin',
        timeoutMs: _timeoutMs,
      );
      if (result['ok'] != 1.0 && result['ok'] != 1) return null;

      final shards = (result['shards'] as List<dynamic>?)
          ?.map(
            (s) => <String, dynamic>{
              'id': s is Map ? s['_id'] ?? 'unknown' : 'unknown',
              'host': s is Map ? s['host'] ?? 'unknown' : 'unknown',
              'state': s is Map ? s['state'] ?? 0 : 0,
            },
          )
          .toList();

      return {'shards': shards ?? [], 'totalShards': shards?.length ?? 0};
    } catch (e) {
      AppLogger.d(_tag, '不是分片集群或获取分片状态失败: $e');
      return null;
    }
  }

  // ==========================================================================
  // 网关 plumbing（认证 / 注册 / 映射 / 错误形状——与 SQL 族壳同构）
  // ==========================================================================

  void _assertConnected() {
    if (!isConnected) throw Exception('未连接到 MongoDB');
  }

  /// server 会话前置：网关模式硬依赖 dbmaster server（embedded 或远程）。
  ServerConnection _requireServerSession() {
    final server = ServerConnection();
    final baseUrl = server.serverUrl;
    if (baseUrl == null ||
        server.connectionState != ServerConnectionState.connected) {
      throw StateError(
        'MongoDB 网关模式需要已连接的 dbmaster server（未检测到会话；'
        'embedded 模式下请确认 dbmaster-server.exe 随包可用）',
      );
    }
    return server;
  }

  /// 连接草稿体（mongodb：凭据可选——空值不下发；defaultDatabase = 认证库；
  /// extra = 集群四模式键**嵌套对象** + TLS 两键透传，server 侧组
  /// ClientOptions；server 侧 SSH 隧道对象原样透传）。
  Map<String, dynamic> _draftBody(DatabaseConnection connection) {
    final authDb = connection.database?.isNotEmpty == true
        ? connection.database!
        : 'admin';
    final username = connection.username;
    final password = connection.password;
    final extraWire = _mongoExtraWire(connection);
    return {
      'dbType': 'mongodb',
      'host': connection.host,
      'port': connection.port,
      if (username != null && username.isNotEmpty) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      'defaultDatabase': authDb,
      if (extraWire.isNotEmpty) 'extra': extraWire,
      'ssh': ?gatewaySshWire(connection),
    };
  }

  /// extra 中 Mongo 集群键的 wire 投影（其余键 useSSL/timeout 等不透传）；
  /// 网关 TLS 透传两键（useTls 开启时固定携带）合并入同一段 extra。
  Map<String, dynamic> _mongoExtraWire(DatabaseConnection connection) {
    final extra = connection.extra;
    if (extra == null) return const {};
    const keys = [
      'mongoConnectionMode',
      'mongoHosts',
      'mongoReplicaSet',
      'mongoConnectionString',
    ];
    return {
      for (final key in keys)
        if (extra[key] != null) key: extra[key],
      ...gatewayTlsWire(extra),
    };
  }

  /// 现场注册（凭据 + 集群 extra 入 server vault），返回 serverConnId。
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

  MongoGatewayException _decodeErrResponse(int status, String text) {
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
    return MongoGatewayException(code, message);
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
