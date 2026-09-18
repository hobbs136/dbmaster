import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import '../models/database_models.dart';
import '../models/connection_event.dart';
import '../models/dml_risk_models.dart';
import '../models/redis_function.dart';
import '../models/result_data_shape.dart';
import '../models/tdengine_models.dart';
import '../models/schema_analyzer/impact_report.dart';
import '../utils/app_logger.dart';
import '../utils/sql_escape_utils.dart';
import '../utils/sql_sanitizer.dart';
import 'database_abstract.dart';
import 'db_gateway_service.dart';
import 'readonly_guard.dart';
import 'adapters/mysql_adapter.dart';
import 'adapters/postgresql_adapter.dart';
import 'adapters/sqlite_adapter.dart';
import 'adapters/redis_adapter.dart';
import 'adapters/mongodb_adapter.dart';
import 'adapters/mongo_cluster_strategy.dart';
import 'adapters/tdengine_adapter.dart';
import 'adapters/sqlserver_adapter.dart';
import 'adapters/clickhouse_adapter.dart';

import 'ssh_tunnel_service.dart';
import 'query_execution_interceptor.dart';
import 'query_settings_service.dart';
import 'sql_parser_service.dart';
import '../models/sql_script_exception.dart';

// ============================================================================
// 内部组件：连接状态
// ============================================================================

/// 会话状态快照
class _SessionSnapshot {
  final String? databaseName;
  final bool inTransaction;
  final DateTime timestamp;

  _SessionSnapshot({
    this.databaseName,
    this.inTransaction = false,
    required this.timestamp,
  });

  bool get isExpired => DateTime.now().difference(timestamp).inMinutes > 30;

  @override
  String toString() =>
      'SessionSnapshot(db=$databaseName, tx=$inTransaction, at=$timestamp)';
}

class _ConnectionState {
  final Map<String, DatabaseAdapter> adapters = {};
  final Map<String, DbServer> servers = {};
  final Set<String> connectingIds = {};
  final Map<String, Completer<void>> connectCompleters = {};
  String? activeConnectionId;
  DbServer? currentServer;
  final SshTunnelManager sshTunnelManager = SshTunnelManager();
  final Map<String, Timer> keepAliveTimers = {};
  final Map<String, int> keepAliveFailures = {};
  final Map<String, int> reconnectAttempts = {};
  static const int maxReconnectAttempts = 5;
  static const List<Duration> reconnectDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  /// Tab 级事务状态（仅历史 MySQL/Doris tab session 使用；T29 网关壳下线
  /// 裸连接 tab session 后，map 保留以兼容 isSessionInTransaction 查询）。
  final Map<String, bool> sessionTransactionStates = {};
  final _sessionTransactionController = StreamController<String>.broadcast();

  // 事务状态跟踪
  final Map<String, bool> transactionStates = {};
  final _transactionController = StreamController<String>.broadcast();

  // S10 事务 session_id（主连接事务走 server 时存）。
  // key = client connectionId, value = server S10 txn sessionId.
  // 非空 = 该连接的主连接事务正走 server S10 端点（非本地 socket）。
  final Map<String, String> txnSessionIds = {};

  /// 当前连接的 S10 事务 session_id，null = 不在 S10 事务中（走本地或无事务）。
  String? txnSessionIdOf(String connectionId) => txnSessionIds[connectionId];

  // 会话状态快照（用于断线重连后恢复）
  final Map<String, _SessionSnapshot> sessionSnapshots = {};

  void saveSessionSnapshot(String connectionId) {
    final server = servers[connectionId];
    if (server == null) return;

    sessionSnapshots[connectionId] = _SessionSnapshot(
      databaseName: server.database,
      inTransaction: transactionStates[connectionId] ?? false,
      timestamp: DateTime.now(),
    );

    AppLogger.d(
      'DatabaseService',
      '会话状态已保存: $connectionId, db=${server.database}, tx=${transactionStates[connectionId] ?? false}',
    );
  }

  _SessionSnapshot? getSessionSnapshot(String connectionId) {
    return sessionSnapshots[connectionId];
  }

  void clearSessionSnapshot(String connectionId) {
    sessionSnapshots.remove(connectionId);
  }

  bool get isConnected => activeConnectionId != null && _hasActiveConnection();

  bool isInTransaction(String connectionId) =>
      transactionStates[connectionId] ?? false;

  void setTransactionState(String connectionId, bool inTransaction) {
    transactionStates[connectionId] = inTransaction;
    _transactionController.add(connectionId);
  }

  Stream<String> get transactionEvents => _transactionController.stream;

  // Tab 级事务状态
  bool isSessionInTransaction(String sessionId) =>
      sessionTransactionStates[sessionId] ?? false;

  void setSessionTransactionState(String sessionId, bool inTransaction) {
    sessionTransactionStates[sessionId] = inTransaction;
    _sessionTransactionController.add(sessionId);
  }

  Stream<String> get sessionTransactionEvents =>
      _sessionTransactionController.stream;

  bool _hasActiveConnection() {
    if (activeConnectionId == null) return false;
    final server = currentServer;
    if (server == null) return false;

    return adapters[activeConnectionId]?.isConnected ?? false;
  }

  List<String> get connectedIds {
    final ids = <String>{};
    for (final entry in adapters.entries) {
      if (entry.value.isConnected) ids.add(entry.key);
    }
    return ids.toList();
  }

  int get connectionCount => connectedIds.length;
}

// ============================================================================
// 内部组件：连接管理器
// ============================================================================

class _ConnectionManager {
  final _ConnectionState _state;
  final _eventsController = StreamController<ConnectionEvent>.broadcast();
  bool _disconnectingAll = false;

  /// open-core Phase B — Mongo 集群策略（Pro 注入；OSS 为 null）。
  final MongoClusterStrategy? _mongoClusterStrategy;

  _ConnectionManager(this._state, {MongoClusterStrategy? mongoClusterStrategy})
    : _mongoClusterStrategy = mongoClusterStrategy;

  Stream<ConnectionEvent> get events => _eventsController.stream;

  // Test-only hook for injecting events into the broadcast stream.
  @visibleForTesting
  void addEventForTest(ConnectionEvent event) => _eventsController.add(event);

  /// 标记连接「在途」（T29 走查修复的重入弹窗守卫测试用）。
  @visibleForTesting
  void markConnectingForTest(String connectionId) {
    _state.connectingIds.add(connectionId);
  }

  // Test-only hook for injecting stream errors to test onError handling.
  @visibleForTesting
  void addErrorForTest(Object error) => _eventsController.addError(error);

  // Test-only hook to inject a pre-connected adapter (see the wrapper
  // comment on DatabaseService.registerConnectedAdapterForTest).
  @visibleForTesting
  void registerConnectedAdapterForTest(
    String connectionId,
    DatabaseAdapter adapter,
  ) {
    _state.adapters[connectionId] = adapter;
  }

  // Test-only hook to register a server as connected without a real
  // database connection. Needed to make hasConnection() / isConnected() return true.
  @visibleForTesting
  void registerConnectedServerForTest(DbServer server) {
    _state.servers[server.id] = server.copyWith(connected: true);
  }

  // open-core Phase B — static final → 实例 late final，使 Mongo 工厂
  // 能闭包注入的集群策略（static lambda 无法捕获实例字段）。
  late final Map<DatabaseType, DatabaseAdapter Function()> _adapterFactories = {
    DatabaseType.mysql: () => MySQLAdapter(),
    DatabaseType.postgresql: () => PostgreSQLAdapter(),
    DatabaseType.sqlite: () => SQLiteAdapter(),
    DatabaseType.doris: () => DorisAdapter(),
    DatabaseType.redis: () => RedisAdapter(),
    DatabaseType.mongodb: () =>
        MongoDBAdapter(clusterStrategy: _mongoClusterStrategy),
    DatabaseType.tdengine: () => TDengineAdapter(),
    DatabaseType.sqlserver: () => SqlServerAdapter(),
    DatabaseType.clickhouse: () => ClickhouseAdapter(),
    // T22-T25 · MySQL 协议族薄适配四成员（复用 MySQL 通道，见 mysql_adapter.dart）。
    DatabaseType.oceanbase: () => OceanbaseAdapter(),
    DatabaseType.tidb: () => TidbAdapter(),
    DatabaseType.starrocks: () => StarrocksAdapter(),
    DatabaseType.mariadb: () => MariadbAdapter(),
  };

  DatabaseAdapter? _getAdapter(DbServer server) {
    return _adapterFactories[server.type]?.call();
  }

  Future<bool> connect(DbServer server) async {
    if (_state.connectingIds.contains(server.id)) {
      AppLogger.d('DatabaseService', '连接已在进行中，跳过');
      return false;
    }

    _state.connectingIds.add(server.id);
    _state.connectCompleters[server.id] = Completer<void>();

    // SSH 隧道配置
    String? dbHost = server.host;
    int? dbPort = server.port;

    try {
      AppLogger.d('DatabaseService', '开始建立连接');

      // 如果启用了 SSH 隧道，先建立隧道。
      // 仅本地直连类型（当前只剩 sqlite，且其不用隧道）走客户端本地隧道；
      // 网关壳类型的 SSH 配置经 DatabaseConnection.fromDbServer 投影进
      // extra['ssh']，由 adapter 随 draft 传给 server 建 server 侧隧道
      // （本地隧道会把 host 改写成 127.0.0.1，server 会连自己的回环）。
      if (server.useSshTunnel &&
          server.sshHost != null &&
          !isServerSideExecutedType(server.type)) {
        AppLogger.d('DatabaseService', '建立 SSH 隧道');
        final localPort = await _state.sshTunnelManager.getOrCreateTunnel(
          connectionId: server.id,
          server: server,
          targetHost: server.host,
          targetPort: server.port,
        );
        dbHost = '127.0.0.1';
        dbPort = localPort;
        AppLogger.d('DatabaseService', 'SSH 隧道建立成功: localhost:$localPort');
      }

      // T29：mysql 族裸连接快路径已删——全类型统一走 adapter（mysql/doris/
      // oceanbase/tidb/starrocks/mariadb 由 mysql_gateway_adapter.dart 网关壳
      // 承载，凭据注册进 server vault，本地无连接）。
      final adapter = _getAdapter(server);
      if (adapter == null) {
        throw Exception('不支持的数据库类型: ${server.type.displayName}');
      }

      if (_state.connectCompleters[server.id]?.isCompleted == true) {
        AppLogger.d('DatabaseService', '连接已取消（适配器阶段）');
        return false;
      }

      // 使用隧道后的 host/port 创建连接配置
      final connection = DatabaseConnection.fromDbServer(
        server,
      ).copyWith(host: dbHost, port: dbPort);
      final success = await adapter.connect(connection);

      if (_state.connectCompleters[server.id]?.isCompleted == true) {
        AppLogger.d('DatabaseService', '连接已取消（适配器连接后）');
        return false;
      }

      if (!success) {
        throw Exception('数据库适配器连接失败');
      }

      adapter.onDisconnect = () => _handleAdapterDisconnect(server.id);
      _state.adapters[server.id] = adapter;
      _state.servers[server.id] = server.copyWith(
        connected: true,
        lastConnected: DateTime.now(),
      );
      _state.activeConnectionId = server.id;
      _state.currentServer = _state.servers[server.id];
      _eventsController.add(
        ConnectionEstablished(server.id, _state.servers[server.id]!),
      );
      AppLogger.i('DatabaseService', '适配器连接成功: ');
      _state.keepAliveFailures[server.id] = 0;
      _state.reconnectAttempts[server.id] = 0;
      startKeepAlive(server.id);

      return true;
    } catch (e) {
      AppLogger.e('DatabaseService', '连接失败: ${server.host}:${server.port}', e);
      // 连接失败时清理 SSH 隧道
      if (server.useSshTunnel) {
        await _state.sshTunnelManager.closeTunnel(server.id);
      }
      _state.adapters.remove(server.id);
      _state.servers.remove(server.id);
      if (_state.activeConnectionId == server.id) {
        _state.activeConnectionId = null;
        _state.currentServer = null;
      }
      if (e.toString().contains('packets out of order')) {
        throw Exception('连接失败: 协议错误，请检查服务器地址和端口是否正确');
      }
      if (e.toString().contains('[RATE_LIMITED]')) {
        // 网关 per-user 限流（默认 600 req/min 滑动窗口）——连接本身是好的，
        // 独立文案防「连接失败」误导（限流根治配套：客户端重路径已批量化）。
        throw Exception(
          '网关限流：每分钟请求配额已用尽，请约 1 分钟后重试'
          '（如频繁出现，可在 server 侧调高 DBMASTER_GW_RATE_LIMIT_PER_MIN）',
        );
      }
      throw Exception('连接失败: $e');
    } finally {
      _state.connectingIds.remove(server.id);
      _state.connectCompleters.remove(server.id);
    }
  }

  void cancelConnect(String connectionId) {
    if (_state.connectCompleters.containsKey(connectionId)) {
      _state.connectCompleters[connectionId]?.complete();
      _state.connectCompleters.remove(connectionId);
    }
    _state.connectingIds.remove(connectionId);
    final server = _state.servers[connectionId];
    _state.adapters.remove(connectionId);
    _state.servers.remove(connectionId);
    if (server != null) {
      _eventsController.add(ConnectionDisconnected(connectionId, server));
    }
    if (_state.activeConnectionId == connectionId) {
      _state.activeConnectionId = null;
      _state.currentServer = null;
    }
  }

  /// 处理适配器底层连接断开事件（由 onClose 回调触发）
  void _handleAdapterDisconnect(String connectionId) {
    AppLogger.w('DatabaseService', '适配器报告底层连接已断开: $connectionId');
    final server = _state.servers[connectionId];
    _state.adapters.remove(connectionId);
    _state.servers.remove(connectionId);
    _state.transactionStates.remove(connectionId);
    _stopKeepAlive(connectionId);
    if (server != null) {
      _eventsController.add(ConnectionDisconnected(connectionId, server));
    }
    if (_state.activeConnectionId == connectionId) {
      _state.activeConnectionId = null;
      _state.currentServer = null;
    }
  }

  void setActiveConnection(String connectionId) {
    if (_state.adapters.containsKey(connectionId)) {
      _state.activeConnectionId = connectionId;
      _state.currentServer = _state.servers[connectionId];
    }
  }

  Future<void> disconnect({String? connectionId}) async {
    final id = connectionId ?? _state.activeConnectionId;
    if (id == null) return;

    final server = _state.servers[id];

    // 如果有未提交的事务，自动回滚
    if (_state.isInTransaction(id)) {
      AppLogger.w('DatabaseService', '连接断开时检测到未提交事务，自动回滚: $id');
      // S10: 若事务走 server session，主动 rollback 清理（防泄漏，不必等 TTL）。
      final txnSid = _state.txnSessionIds.remove(id);
      if (txnSid != null) {
        try {
          final gateway = DbGatewayService.instance;
          final serverConnId = await gateway.lookupServerConnId(id);
          if (serverConnId != null) {
            await gateway.txnRollback(serverConnId, txnSid);
          }
        } catch (e) {
          // best-effort: server TTL sweeper (5 min) will reclaim it anyway.
          AppLogger.w(
            'DatabaseService',
            'S10 txn rollback (disconnect) 失败: $e',
          );
        }
      }
      try {
        final adapter = _state.adapters[id];
        if (adapter != null && adapter.isConnected) {
          await adapter.rollback();
        }
      } catch (e) {
        AppLogger.e('DatabaseService', '事务回滚失败: $e');
      }
      _state.setTransactionState(id, false);
      _eventsController.add(
        TransactionRolledBack(id, 'Connection disconnected'),
      );
    }

    // 保存会话状态快照（用于重连后恢复）
    _state.saveSessionSnapshot(id);

    // 停止心跳定时器
    _stopKeepAlive(id);

    // 关闭底层适配器，忽略错误以确保状态清理始终执行
    try {
      // 关闭 SSH 隧道
      await _state.sshTunnelManager.closeTunnel(id);

      await _state.adapters[id]?.disconnect();
    } catch (e) {
      AppLogger.e('DatabaseService', '断开连接时清理底层连接出错: $e');
    }

    // 强制清理所有状态，即使底层关闭失败
    _state.adapters.remove(id);
    _state.servers.remove(id);
    _state.transactionStates.remove(id);

    if (server != null) {
      _eventsController.add(ConnectionDisconnected(id, server));
    }

    if (_state.activeConnectionId == id) {
      _state.activeConnectionId = _state.adapters.isNotEmpty
          ? _state.adapters.keys.first
          : null;
      _state.currentServer = null;
    }
  }

  Future<void> disconnectAll() async {
    // 防止并发/重入导致重复关闭或 map 并发修改
    if (_disconnectingAll) return;
    _disconnectingAll = true;

    try {
      // 关闭所有 SSH 隧道
      try {
        await _state.sshTunnelManager.closeAllTunnels();
      } catch (e) {
        AppLogger.e('DatabaseService', '关闭所有 SSH 隧道失败: $e');
      }

      // 先对 map 做快照，避免关闭过程中 onDisconnect 回调修改底层 map
      _state.sessionTransactionStates.clear();

      final adaptersSnapshot = _state.adapters.values.toList();
      _state.adapters.clear();
      for (final adapter in adaptersSnapshot) {
        try {
          // 禁用回调，防止已快照的 adapter 在关闭时再次修改状态
          adapter.onDisconnect = null;
          await adapter.disconnect();
        } catch (e) {
          AppLogger.e('DatabaseService', '断开适配器失败: $e');
        }
      }

      // 停止所有心跳定时器
      for (final timer in _state.keepAliveTimers.values.toList()) {
        timer.cancel();
      }
      _state.keepAliveTimers.clear();
      _state.keepAliveFailures.clear();

      _state.activeConnectionId = null;
      _state.currentServer = null;
    } finally {
      _disconnectingAll = false;
    }
  }

  /// 启动连接保活心跳
  void startKeepAlive(
    String connectionId, {
    Duration interval = const Duration(seconds: 10),
  }) {
    // 先停止现有定时器
    _stopKeepAlive(connectionId);

    _state.keepAliveTimers[connectionId] = Timer.periodic(interval, (_) async {
      await _keepAlivePing(connectionId);
    });
  }

  /// 停止连接保活心跳
  void _stopKeepAlive(String connectionId) {
    _state.keepAliveTimers[connectionId]?.cancel();
    _state.keepAliveTimers.remove(connectionId);
    _state.keepAliveFailures.remove(connectionId);
  }

  /// 执行心跳检测
  Future<void> _keepAlivePing(String connectionId) async {
    final server = _state.servers[connectionId];
    if (server == null) return;

    try {
      final adapter = _state.adapters[connectionId];
      if (adapter != null && adapter.isConnected) {
        // Redis/MongoDB 等非 SQL 适配器不应执行 SQL `SELECT 1`。
        // Redis 会把 `SELECT 1` 解析为切换数据库到 db1，导致后续操作写入错误 DB。
        if (server.type == DatabaseType.redis) {
          await (adapter as RedisAdapter).runCommand(['PING']);
        } else {
          await adapter.executeQuery('SELECT 1');
        }
        _state.keepAliveFailures[connectionId] = 0;
      }
    } catch (e) {
      // 切库期间 adapter 主动关闭旧连接，心跳必然失败；不计入失败次数，
      // 否则连续 2 次失败会触发 disconnect+reconnect，干扰正在进行的 useDatabase。
      final adapter = _state.adapters[connectionId];
      if (adapter != null && adapter.isSwitchingDatabase) {
        return;
      }
      AppLogger.e('DatabaseService', '连接心跳失败: $connectionId - $e');
      final failures = (_state.keepAliveFailures[connectionId] ?? 0) + 1;
      _state.keepAliveFailures[connectionId] = failures;

      if (failures >= 2) {
        final reconnectAttempts = _state.reconnectAttempts[connectionId] ?? 0;

        if (reconnectAttempts < _ConnectionState.maxReconnectAttempts) {
          // 尝试自动重连
          _state.reconnectAttempts[connectionId] = reconnectAttempts + 1;
          final delay = _ConnectionState.reconnectDelays[reconnectAttempts];

          AppLogger.w(
            'DatabaseService',
            '连接心跳连续失败 $failures 次，尝试第 ${reconnectAttempts + 1} 次重连 (等待 ${delay.inSeconds}s): $connectionId',
          );

          await Future.delayed(delay);

          final server = _state.servers[connectionId];
          if (server != null && server.autoReconnect) {
            try {
              // 先断开现有连接
              await disconnect(connectionId: connectionId);

              // 尝试重新连接
              final success = await connect(server);

              if (success) {
                AppLogger.i('DatabaseService', '自动重连成功: $connectionId');
                _state.keepAliveFailures[connectionId] = 0;
                _state.reconnectAttempts[connectionId] = 0;

                // 尝试恢复会话状态
                await restoreSessionState(connectionId);
              } else {
                AppLogger.w('DatabaseService', '自动重连失败: $connectionId');
              }
            } catch (reconnectError) {
              AppLogger.e(
                'DatabaseService',
                '自动重连异常: $connectionId - $reconnectError',
              );
            }
          } else {
            AppLogger.w('DatabaseService', '自动重连已禁用或服务器信息缺失: $connectionId');
            await disconnect(connectionId: connectionId);
          }
        } else {
          AppLogger.e(
            'DatabaseService',
            '连接心跳连续失败 $failures 次，重试次数已达上限，断开连接: $connectionId',
          );
          _state.reconnectAttempts[connectionId] = 0;
          await disconnect(connectionId: connectionId);
        }
      }
    }
  }

  /// 恢复会话状态（断线重连后调用）
  Future<void> restoreSessionState(String connectionId) async {
    final snapshot = _state.getSessionSnapshot(connectionId);
    if (snapshot == null) {
      AppLogger.d('DatabaseService', '无会话快照可恢复: $connectionId');
      return;
    }

    if (snapshot.isExpired) {
      AppLogger.w('DatabaseService', '会话快照已过期（>30分钟）: $connectionId');
      _state.clearSessionSnapshot(connectionId);
      return;
    }

    final restoredItems = <String>[];
    final failedItems = <String>[];

    // 恢复当前数据库
    if (snapshot.databaseName != null && snapshot.databaseName!.isNotEmpty) {
      try {
        final server = _state.servers[connectionId];
        if (server != null) {
          final adapter = _state.adapters[connectionId];
          if (adapter != null && adapter.isConnected) {
            await adapter.useDatabase(snapshot.databaseName!);
            restoredItems.add('database: ${snapshot.databaseName}');
            AppLogger.i(
              'DatabaseService',
              '会话状态已恢复 - 数据库: ${snapshot.databaseName}',
            );
          }
        }
      } catch (e) {
        failedItems.add('database: ${snapshot.databaseName} (${e.toString()})');
        AppLogger.e('DatabaseService', '恢复数据库失败: $connectionId - $e');
      }
    }

    // 通知事务状态丢失（断线后事务必然丢失）
    if (snapshot.inTransaction) {
      // 事务状态已在 disconnect 时通过 TransactionRolledBack 事件通知
      // 这里只需记录日志
      AppLogger.w('DatabaseService', '会话状态恢复 - 事务已丢失（断线导致）: $connectionId');
    }

    // 发送恢复事件
    _eventsController.add(
      SessionRestored(
        connectionId,
        databaseName: snapshot.databaseName,
        wasInTransaction: snapshot.inTransaction,
        restoredItems: restoredItems,
        failedItems: failedItems,
      ),
    );

    // 恢复后清除快照
    _state.clearSessionSnapshot(connectionId);
  }

  bool isConnecting(String connectionId) =>
      _state.connectingIds.contains(connectionId);

  bool isConnectionActive(String connectionId) =>
      _state.activeConnectionId == connectionId;

  bool hasConnection(String connectionId) =>
      _state.adapters[connectionId]?.isConnected == true;

  Future<String?> testConnection(DbServer server) async {
    SshTunnelService? tempTunnel;
    try {
      // 如果启用了 SSH 隧道，先建立临时隧道进行测试。
      // 网关壳类型不走本地临时隧道（同 connect：SSH 随 draft 交 server）。
      if (server.useSshTunnel &&
          server.sshHost != null &&
          !isServerSideExecutedType(server.type)) {
        tempTunnel = SshTunnelService();
        final localPort = await tempTunnel.connect(
          server: server,
          targetHost: server.host,
          targetPort: server.port,
        );

        // 使用隧道后的地址进行测试
        final testServer = server.copyWith(host: '127.0.0.1', port: localPort);
        return await _testConnectionDirect(testServer);
      }

      return await _testConnectionDirect(server);
    } catch (e) {
      return e.toString();
    } finally {
      await tempTunnel?.disconnect();
    }
  }

  Future<String?> _testConnectionDirect(DbServer server) async {
    try {
      // T29：mysql 族也统一走 adapter（网关壳 testConnection →
      // POST /api/gw/connections/test），与 pg/sqlite/sqlserver 同路径。
      final adapter = _getAdapter(server);
      if (adapter == null) {
        return '不支持的数据库类型: ${server.type.displayName}';
      }
      final connection = DatabaseConnection.fromDbServer(server);
      return await adapter.testConnection(connection);
    } catch (e) {
      return e.toString();
    }
  }
}

// ============================================================================
// 内部组件：查询执行器
// ============================================================================

/// 内部查询执行结果，包含数据和元数据
class _QueryExecutionResult {
  final List<Map<String, dynamic>> rows;
  final int? affectedRows;
  final int? executionTimeMs;
  final bool isTruncated;
  final int? limitValue;
  final Map<String, String>? columnTypes;
  final Set<String> truncatedColumns; // (max)→capped 截断列名

  _QueryExecutionResult(
    this.rows, {
    this.affectedRows,
    this.executionTimeMs,
    this.isTruncated = false,
    this.limitValue,
    this.columnTypes,
    this.truncatedColumns = const <String>{},
  });
}

class _RowLimitResult {
  final String sql;
  final bool isTruncated;
  final int? limitValue;

  _RowLimitResult(this.sql, {this.isTruncated = false, this.limitValue});
}

/// C21 连接级查询覆盖（会话级，编辑器上下文芯片写入）。
/// 字段 null = 跟随默认；[rowLimit] 0 = 强制关闭自动行限。
class ConnectionQueryOverride {
  final int? rowLimit;
  final int? timeoutSeconds;

  const ConnectionQueryOverride({this.rowLimit, this.timeoutSeconds});
}

class _QueryExecutor {
  final _ConnectionState _state;
  final Map<String, Completer<void>> _queryCancellers = {};

  _QueryExecutor(this._state);

  bool isQueryCancelled(String trackingKey) {
    final canceller = _queryCancellers[trackingKey];
    if (canceller != null && canceller.isCompleted) {
      return true;
    }
    return false;
  }

  void completeCanceller(String trackingKey) {
    final canceller = _queryCancellers[trackingKey];
    if (canceller != null && !canceller.isCompleted) {
      canceller.complete();
    }
  }

  void _startQueryTracking(String trackingKey) {
    _queryCancellers[trackingKey] = Completer<void>();
  }

  void _stopQueryTracking(String trackingKey) {
    _queryCancellers.remove(trackingKey);
    AppLogger.d('DatabaseService', '查询跟踪已停止: $trackingKey');
  }

  /// 执行查询并返回完整元数据
  Future<_QueryExecutionResult> executeQueryWithStats(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    AppLogger.d(
      'DatabaseService',
      '[DatabaseService] executeQuery: targetConnectionId=$targetConnectionId',
    );
    if (targetConnectionId == null) throw Exception('Not connected');

    final server = _state.servers[targetConnectionId];
    if (server == null) throw Exception('Connection not found');

    final currentDatabase = database ?? server.database;

    final trackingKey = sessionId ?? targetConnectionId;
    _startQueryTracking(trackingKey);
    final startTime = DateTime.now();

    try {
      List<Map<String, dynamic>> rows;
      int? affectedRows;
      bool isTruncated = false;
      int? limitValue;
      Map<String, String>? columnTypes;
      Set<String> truncatedColumns = <String>{};

      // route the query through the embedded server
      // gateway when policy allows (embedded + SQL library + non-transactional
      // + server-id mapping exists). Falls back to the local adapter path on
      // any failure, so gateway hiccups are invisible to the user.
      final gateway = DbGatewayService.instance;

      // S10: if this connection has an open server-side transaction session,
      // route the statement through txn/:session_id/query. This branch is
      // intentionally ABOVE the stateless shouldRouteViaGateway path: once a
      // transaction is open on the server, every statement MUST hit that same
      // pinned connection or the transaction semantics break. A failure here
      // is rethrown (NOT silently degraded to local) — the local connection is
      // not in the transaction, so executing there would silently autocommit.
      final txnSid = _state.txnSessionIdOf(targetConnectionId);
      if (txnSid != null && sessionId == null) {
        final serverConnId = await gateway.lookupServerConnId(
          targetConnectionId,
        );
        if (serverConnId != null) {
          final limitResult = await _applyRowLimit(
            sql,
            server.type,
            override: _queryOverrides[targetConnectionId],
          );
          // S10 txn query failure surfaces to the user — do not fall through
          // to a local non-transactional execution.
          final result = await gateway.txnQuery(
            serverConnId,
            txnSid,
            limitResult.sql,
            limit: limitResult.limitValue,
          );
          return _QueryExecutionResult(
            result.rows,
            affectedRows: result.affectedRows,
            executionTimeMs: result.executionTime,
            isTruncated: limitResult.isTruncated,
            limitValue: limitResult.limitValue,
            columnTypes: result.columnTypes,
          );
        }
      }

      final inTx =
          _state.isInTransaction(targetConnectionId) ||
          (sessionId != null && _state.isSessionInTransaction(sessionId));
      if (gateway.shouldRouteViaGateway(server, sql, inTransaction: inTx)) {
        final serverConnId = await gateway.lookupServerConnId(
          targetConnectionId,
        );
        if (serverConnId != null) {
          try {
            final limitResult = await _applyRowLimit(
              sql,
              server.type,
              override: _queryOverrides[targetConnectionId],
            );
            final result = await gateway.executeQuery(
              serverConnId,
              limitResult.sql,
              database: currentDatabase,
              limit: limitResult.limitValue,
            );
            return _QueryExecutionResult(
              result.rows,
              affectedRows: result.affectedRows,
              executionTimeMs: result.executionTime,
              isTruncated: limitResult.isTruncated,
              limitValue: limitResult.limitValue,
              columnTypes: result.columnTypes,
            );
          } catch (e) {
            // Transparent degradation: fall through to the local adapter path.
            AppLogger.w(
              'DatabaseService',
              'gateway query failed, falling back to local: $e',
            );
          }
        }
      }

      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) {
        throw Exception('Not connected');
      }

      // 自动切换数据库上下文（支持连接级别切换的数据库）
      if (currentDatabase != null && currentDatabase != server.database) {
        try {
          AppLogger.d(
            'DatabaseService',
            '[DatabaseService] useDatabase: $currentDatabase',
          );
          await adapter.useDatabase(currentDatabase);
          final updatedServer = server.copyWith(database: currentDatabase);
          _state.servers[targetConnectionId] = updatedServer;
          if (_state.currentServer?.id == targetConnectionId) {
            _state.currentServer = updatedServer;
          }
        } catch (e) {
          AppLogger.e('DatabaseService', '切换数据库失败', e);
          rethrow;
        }
      }

      final limitResult = await _applyRowLimit(
        sql,
        server.type,
        override: _queryOverrides[targetConnectionId],
      );
      sql = limitResult.sql;
      isTruncated = limitResult.isTruncated;
      limitValue = limitResult.limitValue;
      AppLogger.d(
        'DatabaseService',
        '[DatabaseService] adapter.executeQuery: sql=$sql',
      );
      final queryResult = await adapter.executeQuery(sql);
      AppLogger.d(
        'DatabaseService',
        '[DatabaseService] adapter.executeQuery: rows=${queryResult.rows.length}, columns=${queryResult.columns.length}',
      );
      rows = queryResult.rows;
      affectedRows = queryResult.affectedRows;
      columnTypes = queryResult.columnTypes;
      truncatedColumns = queryResult.truncatedColumns;

      final executionTimeMs = DateTime.now()
          .difference(startTime)
          .inMilliseconds;
      return _QueryExecutionResult(
        rows,
        affectedRows: affectedRows,
        executionTimeMs: executionTimeMs,
        isTruncated: isTruncated,
        limitValue: limitValue,
        columnTypes: columnTypes,
        truncatedColumns: truncatedColumns,
      );
    } finally {
      _stopQueryTracking(trackingKey);
    }
  }

  final QuerySettingsService _querySettings = QuerySettingsService();

  // ── C21 会话级 per-connection 查询覆盖（编辑器上下文芯片写入）──
  // 不持久化（会话级）：null 字段 = 跟随全局/连接默认；rowLimit 0 = 强制关。
  final Map<String, ConnectionQueryOverride> _queryOverrides = {};

  /// 设置/更新连接的查询覆盖（增量合并：null 字段保持原值）。
  /// rowLimit 传 0 表示强制关闭自动行限。
  void setQueryOverride(
    String connectionId, {
    int? rowLimit,
    int? timeoutSeconds,
  }) {
    final existing = _queryOverrides[connectionId];
    _queryOverrides[connectionId] = ConnectionQueryOverride(
      rowLimit: rowLimit ?? existing?.rowLimit,
      timeoutSeconds: timeoutSeconds ?? existing?.timeoutSeconds,
    );
  }

  /// 清除连接的全部查询覆盖（回到默认）。
  void clearQueryOverride(String connectionId) =>
      _queryOverrides.remove(connectionId);

  /// 清除单项覆盖（芯片「跟随」项——set 系合并语义，显式清除走这里）。
  void clearRowLimitOverride(String connectionId) {
    final existing = _queryOverrides[connectionId];
    if (existing == null) return;
    if (existing.timeoutSeconds == null) {
      _queryOverrides.remove(connectionId);
    } else {
      _queryOverrides[connectionId] = ConnectionQueryOverride(
        timeoutSeconds: existing.timeoutSeconds,
      );
    }
  }

  void clearTimeoutOverride(String connectionId) {
    final existing = _queryOverrides[connectionId];
    if (existing == null) return;
    if (existing.rowLimit == null) {
      _queryOverrides.remove(connectionId);
    } else {
      _queryOverrides[connectionId] = ConnectionQueryOverride(
        rowLimit: existing.rowLimit,
      );
    }
  }

  /// 当前覆盖（芯片显示用；null = 无覆盖，全部跟随默认）。
  ConnectionQueryOverride? queryOverride(String connectionId) =>
      _queryOverrides[connectionId];

  /// 有效查询超时秒数：覆盖 ?? 连接 timeoutSeconds。
  int effectiveQueryTimeoutSeconds(int fallbackSeconds, String connectionId) =>
      _queryOverrides[connectionId]?.timeoutSeconds ?? fallbackSeconds;

  /// 对读取查询自动添加 LIMIT，避免返回海量数据。
  ///
  /// [override] 为连接级芯片覆盖：0 = 强制关；>0 = 强制值（无视全局开关）；
  /// null = 跟随全局 QuerySettings。
  Future<_RowLimitResult> _applyRowLimit(
    String sql,
    DatabaseType type, {
    ConnectionQueryOverride? override,
  }) async {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return _RowLimitResult(sql);

    final upper = trimmed.toUpperCase();

    // 只处理以 SELECT 或 WITH 开头的读取查询
    if (!upper.startsWith('SELECT') && !upper.startsWith('WITH')) {
      return _RowLimitResult(sql);
    }

    // 连接级覆盖优先：0 = 强制关闭
    final overrideLimit = override?.rowLimit;
    if (overrideLimit == 0) return _RowLimitResult(sql);

    int limitValue;
    if (overrideLimit != null && overrideLimit > 0) {
      limitValue = overrideLimit;
    } else {
      // 读取设置
      final enabled = await _querySettings.getAutoLimitEnabled();
      if (!enabled) return _RowLimitResult(sql);
      limitValue = await _querySettings.getAutoLimitValue();
    }

    switch (type) {
      case DatabaseType.mysql:
      case DatabaseType.doris:
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
      case DatabaseType.tdengine:
      case DatabaseType.clickhouse:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        // 检查是否已有 LIMIT
        if (RegExp(r'\bLIMIT\s+\d+', caseSensitive: false).hasMatch(trimmed)) {
          return _RowLimitResult(sql);
        }
        // 去掉末尾分号，追加 LIMIT
        final withoutSemicolon = trimmed.endsWith(';')
            ? trimmed.substring(0, trimmed.length - 1)
            : trimmed;
        return _RowLimitResult(
          '$withoutSemicolon LIMIT $limitValue;',
          isTruncated: true,
          limitValue: limitValue,
        );
      case DatabaseType.sqlserver:
        // 检查是否已有 TOP
        if (RegExp(r'\bTOP\s+\d+', caseSensitive: false).hasMatch(trimmed)) {
          return _RowLimitResult(sql);
        }
        // 在 SELECT 后插入 TOP（仅处理以 SELECT 开头的情况，CTE 暂不处理）
        final match = RegExp(
          r'^\s*SELECT\s+',
          caseSensitive: false,
        ).firstMatch(trimmed);
        if (match != null) {
          return _RowLimitResult(
            '${trimmed.substring(0, match.end)}TOP $limitValue ${trimmed.substring(match.end)}',
            isTruncated: true,
            limitValue: limitValue,
          );
        }
        return _RowLimitResult(sql);
      case DatabaseType.mongodb:
      case DatabaseType.redis:
        // 非 SQL 数据库，不处理
        return _RowLimitResult(sql);
    }
  }

  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
  }) async {
    final result = await executeQueryWithStats(
      sql,
      connectionId: connectionId,
      database: database,
    );
    return result.rows;
  }

  Future<List<Map<String, dynamic>>> getExplainPlan(
    String sql, {
    String? connectionId,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) throw Exception('Not connected');

    final server = _state.servers[targetConnectionId];
    if (server == null) throw Exception('Connection not found');

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Not connected');
    }
    final result = await adapter.getExplainPlan(sql);
    return result.rows;
  }

  Future<bool> executeSqlScript(String script) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // 全类型统一走 adapter 级脚本解析（mysql 族网关壳实现 SqlScriptAdapter，
    // 与旧裸连接版同为 SQLParserService.split 逐条执行口径）。
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    return await adapter.executeSqlScript(script);
  }
}

// ============================================================================
// 内部组件：Schema 管理器
// ============================================================================

// PG serial/identity 列在 information_schema.columns.column_default
// 里存的是 `nextval('tbl_col_seq'::regclass)`。若原样写进目标库 CREATE TABLE 的 DEFAULT，
// 目标库没有该序列 → `relation "tbl_col_seq" does not exist` → CREATE TABLE 失败 →
// PG 事务整体回滚 → 同步"成功"但目标库无变化。故把 integer/bigint/smallint + nextval
// 默认的列改写为 serial/bigserial/smallserial（PG 自动建序列）。
// 仅 PG 生效；SQLite 的自增语义不同（INTEGER PRIMARY KEY AUTOINCREMENT），不走此路径。
/// 解析单列的 PG serial 转换：PG 整型 + nextval(...) 默认 → serial 系列 + 清空默认值。
/// 其余情况原样返回。CREATE TABLE（database_service）与 ADD COLUMN（schema_sync_service）
/// 共用，避免逻辑重复。导出为顶层函数以便跨 library 复用与单测。
({String type, String? defaultValue}) resolvePgSerialColumn(
  DatabaseType dbType,
  String type,
  String? defaultValue,
) {
  if (dbType != DatabaseType.postgresql ||
      defaultValue == null ||
      !defaultValue.startsWith('nextval(')) {
    return (type: type, defaultValue: defaultValue);
  }
  final serialType = switch (type.toLowerCase().trim()) {
    'integer' || 'int' || 'int4' || 'serial' => 'serial',
    'bigint' || 'int8' || 'bigserial' => 'bigserial',
    'smallint' || 'int2' || 'smallserial' => 'smallserial',
    _ => '',
  };
  if (serialType.isEmpty) {
    return (type: type, defaultValue: defaultValue);
  }
  return (type: serialType, defaultValue: null);
}

// PG/SQLServer 多 schema——本表带 schema 前缀（如 ecommerce.products）
// 时，getForeignKeys 返回的 referencedTable 是裸名（ccu.table_name，如 brands）。
// 若原样输出 REFERENCES "brands"，目标库 search_path 默认 public 解析不到 →
// 42P01 "relation ... does not exist"。故按"同 schema"补限定 → ecommerce.brands。
/// 本表 schema 已知时，把裸名 FK 引用补同 schema 限定；已限定或无 schema 则原样返回。
String resolvePgQualifiedFkReference(
  String ownerTable,
  String referencedTable,
) {
  final dot = ownerTable.indexOf('.');
  final schema = (dot > 0 && dot < ownerTable.length - 1)
      ? ownerTable.substring(0, dot)
      : null;
  if (schema == null || referencedTable.contains('.')) {
    return referencedTable;
  }
  return '$schema.$referencedTable';
}

class _SchemaManager {
  final _ConnectionState _state;

  _SchemaManager(this._state);

  Future<List<String>> getDatabases({String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getDatabases();
  }

  /// spec 050：附加一个 SQLite 数据库文件到当前连接（ATTACH）。
  ///
  /// 仅 SQLite（adapter 需实现 [AttachAwareAdapter]）支持。
  /// [path] 文件绝对路径；[alias] 附加名（调用方经 SqliteAliasValidator 校验）。
  /// 成功后调用方需刷新 getDatabases 缓存以反映新附加库。
  Future<void> attachDatabase(
    String connectionId,
    String path,
    String alias,
  ) async {
    final adapter = _state.adapters[connectionId];
    if (adapter == null || !adapter.isConnected) {
      throw StateError('连接 $connectionId 不存在或未连接');
    }
    if (adapter is! AttachAwareAdapter) {
      throw UnsupportedError('该数据库类型不支持 ATTACH 跨库');
    }
    // is! 已确保 adapter 是 AttachAwareAdapter；显式 as 绕过 Dart 对 map 取值
    // promotion 的限制（adapter 来自 Map 索引，flow analysis 不自动 promote）。
    await (adapter as AttachAwareAdapter).attachDatabase(path, alias);
  }

  /// spec 050：分离一个已附加的 SQLite 数据库（DETACH）。
  Future<void> detachDatabase(String connectionId, String alias) async {
    final adapter = _state.adapters[connectionId];
    if (adapter == null || !adapter.isConnected) {
      throw StateError('连接 $connectionId 不存在或未连接');
    }
    if (adapter is! AttachAwareAdapter) {
      throw UnsupportedError('该数据库类型不支持 ATTACH 跨库');
    }
    await (adapter as AttachAwareAdapter).detachDatabase(alias);
  }

  /// C16 · SQLite Save As（VACUUM INTO 复制，spec 050）——原 sidebar
  /// sqlite_tree_builder 直 cast SQLiteAdapter，区块重建收编至服务层
  /// （UI 侧 adapter 直连清零，铁律 3）。非 SQLite 连接抛 UnsupportedError。
  Future<void> saveDatabaseAs(String connectionId, String destPath) async {
    final adapter = _state.adapters[connectionId];
    if (adapter is! SQLiteAdapter) {
      throw UnsupportedError('Not a SQLite connection');
    }
    await adapter.saveAs(destPath);
  }

  Future<void> useDatabase(
    String dbName, {
    String? connectionId,
    String? sessionId,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return;

    final server = _state.servers[targetConnectionId];
    if (server == null) return;

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return;
    await adapter.useDatabase(dbName);

    // Update server state with new database
    final updatedServer = server.copyWith(database: dbName);
    _state.servers[targetConnectionId] = updatedServer;
    if (_state.currentServer?.id == targetConnectionId) {
      _state.currentServer = updatedServer;
    }

    // 保存会话状态快照
    _state.saveSessionSnapshot(targetConnectionId);
  }

  void updateServerDatabase(String dbName, {String? connectionId}) {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return;

    final server = _state.servers[targetConnectionId];
    if (server == null) return;

    final updatedServer = server.copyWith(database: dbName);
    _state.servers[targetConnectionId] = updatedServer;
    if (_state.currentServer?.id == targetConnectionId) {
      _state.currentServer = updatedServer;
    }
  }

  /// [schemaName]：SQLite ATTACH 附加库 alias（getDatabaseInfo 透传），
  /// 限定到 `<alias>.sqlite_master`；非 SQLite 调用方不传（MySQL/Doris 走
  /// 上方专用分支不受影响）。
  Future<List<String>> getTables({
    String? connectionId,
    String? schemaName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    // 注：`is` 提升后 getTables 成员解析仍落基类签名（接口合并怪癖），
    // 须显式收窄局部变量再带 schemaName 调用。
    final multi =
        schemaName != null &&
            schemaName.isNotEmpty &&
            adapter is MultiSchemaObjectAdapter
        ? adapter as MultiSchemaObjectAdapter
        : null;
    if (multi != null) {
      return await multi.getTables(schemaName: schemaName);
    }
    return await adapter.getTables();
  }

  /// [schemaName]：SQLite ATTACH 附加库 alias（getDatabaseInfo 透传）。
  Future<List<String>> getViews({
    String? connectionId,
    String? schemaName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    final multi =
        schemaName != null &&
            schemaName.isNotEmpty &&
            adapter is MultiSchemaObjectAdapter
        ? adapter as MultiSchemaObjectAdapter
        : null;
    if (multi != null) {
      return await multi.getViews(schemaName: schemaName);
    }
    return await adapter.getViews();
  }

  Future<List<String>> getMaterializedViews({String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getMaterializedViews();
  }

  Future<List<String>> getProcedures({String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getProcedures();
  }

  Future<List<String>> getFunctions({String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getFunctions();
  }

  Future<List<String>> getEvents({String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getEvents();
  }

  Future<List<DbColumn>> getTableColumns(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    // SQLite ATTACH（spec 050）：databaseName 此处承载附加库 alias——
    // 限定 PRAGMA 到该 alias（未限定恒查 main，C16 存量缺陷的列半边）。
    if (server.type == DatabaseType.sqlite &&
        adapter is SQLiteAdapter &&
        databaseName != null &&
        databaseName.isNotEmpty &&
        databaseName != 'main') {
      return await adapter.getTableColumns(tableName, schemaName: databaseName);
    }
    return await adapter.getTableColumns(tableName);
  }

  /// [schemaName]：SQLite ATTACH 附加库 alias（getDatabaseInfo 透传）——
  /// 列表与详情（columns/indexes）两半都限定到该 alias。
  Future<List<DbTable>> getAllTables({
    String? connectionId,
    bool includeDetails = false,
    String? schemaName,
  }) async {
    final tables = <DbTable>[];
    final tableNames = await getTables(
      connectionId: connectionId,
      schemaName: schemaName,
    );

    if (!includeDetails) {
      for (final name in tableNames) {
        tables.add(DbTable(name: name));
      }
      return tables;
    }

    final futures = tableNames.map((name) async {
      final columns = await getTableColumns(
        name,
        connectionId: connectionId,
        databaseName: schemaName,
      );
      final indexes = await getTableIndexes(
        name,
        connectionId: connectionId,
        databaseName: schemaName,
      );
      return DbTable(name: name, columns: columns, indexes: indexes);
    }).toList();

    return await Future.wait(futures);
  }

  // T004 — add SchemaAwareAdapter branch to populate Database.schemas
  Future<Database> getDatabaseInfo(
    String dbName, {
    String? connectionId,
    bool includeTableDetails = false,
    bool schemasOnly = false,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    final server = targetConnectionId != null
        ? _state.servers[targetConnectionId]
        : null;

    // SQLite ATTACH 跨库（spec 050 + C16 存量缺陷修复）：dbName 是库 alias
    // （'main'/附加名）而非真实库名——useDatabase 会把 server.database 错写
    // 成 alias（污染执行路由的当前库状态），且 flat 路径的对象查询必须限定
    // 到该 alias 的 sqlite_master（原先不透传 → 附加库 header 恒列 main 的
    // 对象）。此处特判：跳过 useDatabase + 对象查询带 alias。
    final isSqlite = server?.type == DatabaseType.sqlite;
    if (!isSqlite) {
      await useDatabase(dbName, connectionId: connectionId);
    }
    final sqliteSchema = isSqlite && dbName.isNotEmpty && dbName != 'main'
        ? dbName
        : null;

    final adapter = targetConnectionId != null
        ? _state.adapters[targetConnectionId]
        : null;

    // Schema-aware path: populate per-schema DbSchema objects for PG/SS
    if (adapter != null && adapter is SchemaAwareAdapter) {
      try {
        final schemaNames = await adapter.getSchemas();
        if (schemaNames.isNotEmpty) {
          final schemas = <DbSchema>[];
          final allTables = <DbTable>[];
          final allViews = <String>[];
          final allFunctions = <String>[];
          final allProcedures = <String>[];
          final allMatViews = <String>[];
          final allSequences = <String>[];
          final allTriggers = <DbTrigger>[];

          for (final schemaName in schemaNames) {
            // schemasOnly mode — build empty shells, defer per-schema object loading
            if (schemasOnly) {
              schemas.add(
                DbSchema(
                  name: schemaName,
                  tables: const [],
                  views: const [],
                  materializedViews: const [],
                  functions: const [],
                  procedures: const [],
                  sequences: const [],
                  triggers: const [],
                ),
              );
              continue;
            }

            // Query each object type scoped to this schema (FR-003)
            List<DbTable> schemaTables = [];
            try {
              // Use dynamic dispatch — adapter is guaranteed SchemaAwareAdapter
              // (PG/SS), both accept optional schemaName parameter.
              final names =
                  await (adapter as dynamic).getTables(schemaName: schemaName)
                      as List<String>;
              schemaTables = names.map((name) => DbTable(name: name)).toList();
            } catch (e) {
              AppLogger.w('DatabaseService', '获取 schema $schemaName 表列表失败: $e');
            }

            // Use dynamic dispatch — adapter is guaranteed SchemaAwareAdapter
            final dyn = adapter as dynamic;

            List<String> schemaViews = [];
            try {
              schemaViews =
                  await dyn.getViews(schemaName: schemaName) as List<String>;
            } catch (e) {
              AppLogger.w(
                'DatabaseService',
                '获取 schema $schemaName 视图列表失败: $e',
              );
            }

            List<String> schemaFunctions = [];
            try {
              schemaFunctions =
                  await dyn.getFunctions(schemaName: schemaName)
                      as List<String>;
            } catch (e) {
              AppLogger.w(
                'DatabaseService',
                '获取 schema $schemaName 函数列表失败: $e',
              );
            }

            List<String> schemaProcedures = [];
            try {
              schemaProcedures =
                  await dyn.getProcedures(schemaName: schemaName)
                      as List<String>;
            } catch (e) {
              AppLogger.w(
                'DatabaseService',
                '获取 schema $schemaName 存储过程列表失败: $e',
              );
            }

            List<String> schemaMatViews = [];
            try {
              schemaMatViews =
                  await dyn.getMaterializedViews(schemaName: schemaName)
                      as List<String>;
            } catch (e) {
              AppLogger.w(
                'DatabaseService',
                '获取 schema $schemaName 物化视图列表失败: $e',
              );
            }

            List<String> schemaSequences = [];
            try {
              schemaSequences =
                  await dyn.getSequences(schemaName: schemaName)
                      as List<String>;
            } catch (e) {
              AppLogger.w(
                'DatabaseService',
                '获取 schema $schemaName 序列列表失败: $e',
              );
            }

            List<DbTrigger> schemaTriggers = [];
            try {
              schemaTriggers =
                  await dyn.getTriggers(schemaName: schemaName)
                      as List<DbTrigger>;
            } catch (e) {
              AppLogger.w(
                'DatabaseService',
                '获取 schema $schemaName 触发器列表失败: $e',
              );
            }

            schemas.add(
              DbSchema(
                name: schemaName,
                tables: schemaTables,
                views: schemaViews,
                materializedViews: schemaMatViews,
                functions: schemaFunctions,
                procedures: schemaProcedures,
                sequences: schemaSequences,
                triggers: schemaTriggers,
              ),
            );

            // Accumulate flat union for backward compatibility (FR-002)
            allTables.addAll(schemaTables);
            allViews.addAll(schemaViews);
            allFunctions.addAll(schemaFunctions);
            allProcedures.addAll(schemaProcedures);
            allMatViews.addAll(schemaMatViews);
            allSequences.addAll(schemaSequences);
            allTriggers.addAll(schemaTriggers);
          }

          return Database(
            name: dbName,
            tables: allTables,
            views: allViews,
            procedures: [...allFunctions, ...allProcedures],
            triggers: allTriggers,
            events: [],
            functions: allFunctions,
            materializedViews: allMatViews,
            sequences: allSequences,
            schemas: schemas,
          );
        }
        // schemaNames is empty: fall through to flat path (FR-004)
      } catch (e) {
        AppLogger.w('DatabaseService', 'Schema-aware 加载失败，回退到平面模式: $e');
        // Fall through to flat path (FR-004)
      }
    }

    // Existing flat hierarchy path (non-schema-aware databases)
    // 独立获取各类对象，避免一个失败导致全部失败
    final tables = await getAllTables(
      connectionId: connectionId,
      includeDetails: includeTableDetails,
      schemaName: sqliteSchema,
    );

    List<String> views = [];
    try {
      views = await getViews(
        connectionId: connectionId,
        schemaName: sqliteSchema,
      );
    } catch (e) {
      AppLogger.w('DatabaseService', '获取视图列表失败: $e');
    }

    List<String> materializedViews = [];
    try {
      materializedViews = await getMaterializedViews(
        connectionId: connectionId,
      );
    } catch (e) {
      AppLogger.w('DatabaseService', '获取物化视图列表失败: $e');
    }

    List<String> functions = [];
    try {
      functions = await getFunctions(connectionId: connectionId);
    } catch (e) {
      AppLogger.w('DatabaseService', '获取函数列表失败: $e');
    }

    List<String> procedures = [];
    try {
      procedures = await getProcedures(connectionId: connectionId);
    } catch (e) {
      AppLogger.w('DatabaseService', '获取存储过程列表失败: $e');
    }

    List<DbTrigger> triggers = [];
    try {
      triggers = await getTriggers(
        connectionId: connectionId,
        schemaName: sqliteSchema,
      );
    } catch (e) {
      AppLogger.w('DatabaseService', '获取触发器列表失败: $e');
    }

    List<String> events = [];
    try {
      events = await getEvents(connectionId: connectionId);
    } catch (e) {
      AppLogger.w('DatabaseService', '获取事件列表失败: $e');
    }

    return Database(
      name: dbName,
      tables: tables,
      views: views,
      materializedViews: materializedViews,
      procedures: [...functions, ...procedures],
      triggers: triggers,
      events: events,
      functions: functions,
    );
  }

  /// 分页获取表列表（服务端分页，适用于支持 information_schema 的数据库）
  Future<({List<String> items, int total})> getTablesPaginated({
    String? connectionId,
    String? sessionId,
    String? databaseName,
    int page = 1,
    int pageSize = 100,
    String? search,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return (items: <String>[], total: 0);

    final server = _state.servers[targetConnectionId];
    if (server == null) return (items: <String>[], total: 0);

    final offset = (page - 1) * pageSize;

    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      // Helper: apply client-side search + pagination to a full table list.
      ({List<String> items, int total}) paginate(List<String> tables) {
        var filtered = tables;
        if (search != null && search.isNotEmpty) {
          final lowerSearch = search.toLowerCase();
          filtered = filtered
              .where((t) => t.toLowerCase().contains(lowerSearch))
              .toList();
        }
        final total = filtered.length;
        final items = filtered.skip(offset).take(pageSize).toList();
        return (items: items, total: total);
      }

      // T29：走网关壳 adapter（getTables 内部 SHOW FULL TABLES 过滤 base
      // table，语义同旧 SHOW FULL TABLES 分支）。databaseName 定向经
      // useDatabase 切换壳的当前库上下文。
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) {
        return (items: <String>[], total: 0);
      }
      try {
        if (databaseName != null && databaseName.isNotEmpty) {
          await adapter.useDatabase(databaseName);
        }
        final tables = await adapter.getTables();
        return paginate(tables);
      } catch (e) {
        AppLogger.e('DatabaseService', '分页获取表列表失败', e);
        return (items: <String>[], total: 0);
      }
    } else if (server.type == DatabaseType.postgresql) {
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected)
        return (items: <String>[], total: 0);
      try {
        var whereClause = databaseName != null && databaseName.isNotEmpty
            ? "table_schema = '${databaseName.replaceAll("'", "''")}'"
            : "table_schema = current_schema()";
        if (search != null && search.isNotEmpty) {
          whereClause +=
              " AND table_name ILIKE '%${search.replaceAll("'", "''")}%'";
        }
        final countResults = await adapter.executeQuery(
          "SELECT COUNT(*) as cnt FROM information_schema.tables WHERE $whereClause AND table_type = 'BASE TABLE'",
        );
        final total =
            int.tryParse(countResults.rows.first['cnt']?.toString() ?? '0') ??
            0;
        final results = await adapter.executeQuery(
          "SELECT table_name FROM information_schema.tables WHERE $whereClause AND table_type = 'BASE TABLE' ORDER BY table_name LIMIT $pageSize OFFSET $offset",
        );
        final items = results.rows
            .map((row) => row['table_name']?.toString() ?? '')
            .toList();
        return (items: items, total: total);
      } catch (e) {
        AppLogger.e('DatabaseService', '分页获取表列表失败', e);
        return (items: <String>[], total: 0);
      }
    } else if (server.type == DatabaseType.sqlite) {
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected)
        return (items: <String>[], total: 0);
      try {
        final allTables = await adapter.getTables();
        var filtered = allTables;
        if (search != null && search.isNotEmpty) {
          filtered = allTables
              .where((t) => t.toLowerCase().contains(search.toLowerCase()))
              .toList();
        }
        final total = filtered.length;
        final items = filtered.skip(offset).take(pageSize).toList();
        return (items: items, total: total);
      } catch (e) {
        AppLogger.e('DatabaseService', '分页获取表列表失败', e);
        return (items: <String>[], total: 0);
      }
    } else {
      // MongoDB, Redis, TDengine - 客户端分页
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected)
        return (items: <String>[], total: 0);
      try {
        final allTables = await adapter.getTables();
        var filtered = allTables;
        if (search != null && search.isNotEmpty) {
          filtered = allTables
              .where((t) => t.toLowerCase().contains(search.toLowerCase()))
              .toList();
        }
        final total = filtered.length;
        final items = filtered.skip(offset).take(pageSize).toList();
        return (items: items, total: total);
      } catch (e) {
        AppLogger.e('DatabaseService', '分页获取表列表失败', e);
        return (items: <String>[], total: 0);
      }
    }
  }

  /// MySQL/Doris 专用：只获取指定表的元信息，避免 SHOW TABLE STATUS 全库扫描
  Future<List<DbTableMetadata>> _getMysqlTablesMetadataPaginated({
    required String connectionId,
    String? sessionId,
    required String databaseName,
    required List<String> tableNames,
  }) async {
    // T29：经网关壳 adapter 执行（SQL 与旧裸连接版逐行一致）。
    final adapter = _state.adapters[connectionId];
    if (adapter == null || !adapter.isConnected) return [];

    try {
      final inClause = tableNames
          .map((n) => "'${n.replaceAll("'", "''")}'")
          .join(',');
      final results = await adapter.executeQuery(
        'SELECT table_name, engine, table_rows, data_length, index_length, '
        'table_comment, create_time, update_time '
        'FROM information_schema.tables '
        'WHERE table_schema = \'${databaseName.replaceAll("'", "''")}\' '
        'AND table_name IN ($inClause)',
      );

      return results.rows
          .map((row) {
            final dataLength = _parseInt(row['data_length']);
            final indexLength = _parseInt(row['index_length']);
            return DbTableMetadata(
              name: row['table_name']?.toString() ?? '',
              engine: row['engine']?.toString(),
              rowCount: _parseInt(row['table_rows']),
              dataSize: dataLength != null && indexLength != null
                  ? dataLength + indexLength
                  : null,
              comment: row['table_comment']?.toString(),
              createTime: _parseDateTime(row['create_time']),
              updateTime: _parseDateTime(row['update_time']),
              isApproximateCount: true,
            );
          })
          .where((m) => m.name.isNotEmpty)
          .toList();
    } catch (e) {
      AppLogger.e('DatabaseService', '获取分页表元信息失败', e);
      return tableNames.map((name) => DbTableMetadata(name: name)).toList();
    }
  }

  /// PostgreSQL 专用：只获取指定表的元信息，避免全库 pg_class 扫描
  Future<List<DbTableMetadata>> _getPostgresqlTablesMetadataPaginated({
    required String connectionId,
    required String databaseName,
    required List<String> tableNames,
  }) async {
    final adapter = _state.adapters[connectionId];
    if (adapter == null || !adapter.isConnected) return [];

    try {
      final inClause = tableNames
          .map((n) => "'${n.replaceAll("'", "''")}'")
          .join(',');
      final results = await adapter.executeQuery('''
        SELECT
          c.relname AS table_name,
          c.reltuples::bigint AS row_count,
          pg_total_relation_size(c.oid) AS total_size,
          obj_description(c.oid, 'pg_class') AS comment
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = '${databaseName.replaceAll("'", "''")}'
          AND c.relname IN ($inClause)
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
    } catch (e) {
      AppLogger.e('DatabaseService', '获取 PostgreSQL 分页表元信息失败', e);
      return tableNames.map((name) => DbTableMetadata(name: name)).toList();
    }
  }

  /// MySQL/Doris 专用：生成 fully qualified 表名（带数据库名前缀）
  static String _escapeMySqlTableName(String tableName, String? databaseName) {
    if (databaseName == null || databaseName.isEmpty) {
      return SqlEscapeUtils.escapeMySqlIdentifier(tableName);
    }
    return '${SqlEscapeUtils.escapeMySqlIdentifier(databaseName)}.${SqlEscapeUtils.escapeMySqlIdentifier(tableName)}';
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return int.tryParse(value.toString());
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return DateTime.tryParse(value.toString());
  }

  Future<Map<String, dynamic>?> getServerVersion({String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return null;

    final server = _state.servers[targetConnectionId];
    if (server == null) return null;

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return null;
    return await adapter.getServerVersion();
  }

  /// [schemaName]：SQLite ATTACH 附加库 alias（getDatabaseInfo 透传），
  /// 限定触发器查询到 `<alias>.sqlite_master`。
  Future<List<DbTrigger>> getTriggers({
    String? connectionId,
    String? schemaName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      // T29：走网关壳 adapter（SqlSchemaAdapter.getTriggers，SQL 与旧裸连接
      // 分支同源——壳实现自 mysql_base_adapter 逐行迁入）。
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return [];
      try {
        return await adapter.getTriggers();
      } catch (e) {
        AppLogger.e('DatabaseService', '操作失败', e);
        return [];
      }
    } else if (server.type == DatabaseType.sqlite) {
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return [];
      try {
        if (adapter is SQLiteAdapter &&
            schemaName != null &&
            schemaName.isNotEmpty) {
          return await adapter.getTriggers(schemaName: schemaName);
        }
        return await adapter.getTriggers();
      } catch (e) {
        AppLogger.e('DatabaseService', '获取 SQLite 触发器失败', e);
        return [];
      }
    } else {
      return [];
    }
  }

  Future<Map<String, dynamic>> getServerStatus({String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return {};

    final server = _state.servers[targetConnectionId];
    if (server == null) return {};

    // T29：经网关壳 adapter 执行（SQL 与旧裸连接版逐行一致；行按列序位置取
    // 值——SHOW STATUS 列名为 Variable_name/Value，SELECT VERSION() 单列）。
    if (server.type == DatabaseType.mysql) {
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return {};
      try {
        final varsResult = await adapter.executeQuery(
          "SHOW STATUS WHERE Variable_name IN ('Uptime', 'Threads_connected', 'Threads_running', 'Queries', 'Slow_queries', 'Questions', 'Connections', 'Aborted_connects', 'Bytes_received', 'Bytes_sent')",
        );
        final status = <String, dynamic>{};
        for (final row in varsResult.rows) {
          final values = row.values.toList();
          final name = values.isNotEmpty ? values[0]?.toString() ?? '' : '';
          final value = values.length > 1 ? values[1]?.toString() ?? '' : '';
          status[name] = int.tryParse(value) ?? value;
        }

        final versionResult = await adapter.executeQuery('SELECT VERSION()');
        if (versionResult.rows.isNotEmpty) {
          final values = versionResult.rows.first.values;
          status['Version'] = values.isEmpty ? null : values.first?.toString();
        }

        return status;
      } catch (e) {
        AppLogger.e('DatabaseService', '操作失败', e);
        return {};
      }
    } else if (server.type == DatabaseType.doris) {
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return {};
      try {
        final status = <String, dynamic>{};

        // Doris: SHOW STATUS with MySQL vars returns empty. Use SELECT VERSION() only.
        final versionResult = await adapter.executeQuery('SELECT VERSION()');
        if (versionResult.rows.isNotEmpty) {
          final values = versionResult.rows.first.values;
          status['Version'] = values.isEmpty ? null : values.first?.toString();
        }

        return status;
      } catch (e) {
        AppLogger.e('DatabaseService', '操作失败', e);
        return {};
      }
    } else {
      return {};
    }
  }

  Future<Map<String, dynamic>> getGlobalVariables({
    String? connectionId,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return {};

    final server = _state.servers[targetConnectionId];
    if (server == null) return {};

    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      // T29：经网关壳 adapter 执行（SQL 与旧裸连接版逐行一致；行按列序位置
      // 取值——SHOW GLOBAL VARIABLES 列名为 Variable_name/Value）。
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return {};
      try {
        final results = await adapter.executeQuery('SHOW GLOBAL VARIABLES');
        final variables = <String, dynamic>{};
        for (final row in results.rows) {
          final values = row.values.toList();
          final name = values.isNotEmpty ? values[0]?.toString() ?? '' : '';
          final value = values.length > 1 ? values[1]?.toString() ?? '' : '';
          variables[name] = value;
        }
        return variables;
      } catch (e) {
        AppLogger.e('DatabaseService', '操作失败', e);
        return {};
      }
    } else {
      return {};
    }
  }

  Future<List<Map<String, dynamic>>> getServerUsers({
    String? connectionId,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    if (server.type == DatabaseType.mysql) {
      // T29：经网关壳 adapter 执行（SQL 与旧裸连接版逐行一致；行按列序位置取值）。
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return [];
      try {
        final results = await adapter.executeQuery(
          "SELECT User, Host, plugin, password_expired, account_locked FROM mysql.user",
        );
        final users = <Map<String, dynamic>>[];
        for (final row in results.rows) {
          final values = row.values.toList();
          users.add({
            'User': values.isNotEmpty ? values[0]?.toString() ?? '' : '',
            'Host': values.length > 1 ? values[1]?.toString() ?? '' : '',
            'Plugin': values.length > 2 ? values[2]?.toString() ?? '' : '',
            'PasswordExpired':
                values.length > 3 && values[3]?.toString() == 'Y',
            'AccountLocked': values.length > 4 && values[4]?.toString() == 'Y',
          });
        }
        return users;
      } catch (e) {
        AppLogger.e('DatabaseService', '操作失败', e);
        return [];
      }
    } else {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getProcessList({
    String? connectionId,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    // 按 capability 路由：实现了 ProcessListAdapter 的 adapter（如 SQL Server）
    // 走 adapter.getProcessList()，此前对非 mysql/doris 一律返空。键对齐 MySQL 的 SHOW PROCESSLIST 形状。
    final adapter = _state.adapters[targetConnectionId];
    if (adapter != null && adapter is ProcessListAdapter) {
      final processAdapter = adapter as ProcessListAdapter;
      try {
        return (await processAdapter.getProcessList())
            .map(
              (p) => <String, dynamic>{
                'Id': p.id,
                'User': p.user,
                'Host': p.host,
                'db': p.database,
                'Command': p.command,
                'Time': p.time,
                'State': p.state,
                'Info': p.info ?? '',
              },
            )
            .toList();
      } catch (e) {
        AppLogger.e('DatabaseService', 'getProcessList 操作失败', e);
        return [];
      }
    }
    return [];
  }

  /// 表行数统计（C19 自 SidebarController 内联 SQL 收编——per-type SQL
  /// 归服务层，getProcessList 同款先例）。MySQL/Doris 查
  /// information_schema；PG join pg_namespace 出 per-schema 行数（T006）；
  /// 其余类型返回空。行形状 =（schema 可空，表名，行数），键由调用方自组装。
  Future<List<({String? schema, String name, int rows})>> getTableRowCounts(
    String connectionId,
    String databaseName,
  ) async {
    final server = _state.servers[connectionId];
    if (server == null) return [];
    final adapter = _state.adapters[connectionId];
    if (adapter == null) return [];

    QueryResult result;
    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      result = await adapter.executeQuery(
        "SELECT TABLE_NAME, TABLE_ROWS FROM information_schema.TABLES "
        "WHERE TABLE_SCHEMA = '${databaseName.replaceAll("'", "''")}' AND TABLE_TYPE = 'BASE TABLE'",
      );
    } else if (server.type == DatabaseType.postgresql) {
      // T006 — join pg_namespace for per-schema row counts
      result = await adapter.executeQuery(
        "SELECT n.nspname AS table_schema, c.relname AS TABLE_NAME, "
        "c.reltuples::bigint AS TABLE_ROWS "
        "FROM pg_class c "
        "JOIN pg_namespace n ON n.oid = c.relnamespace "
        "WHERE c.relkind = 'r' "
        "AND n.nspname NOT LIKE 'pg_%' AND n.nspname != 'information_schema'",
      );
    } else {
      return [];
    }
    final out = <({String? schema, String name, int rows})>[];
    for (final row in result.rows) {
      final name = row['TABLE_NAME']?.toString();
      final n = int.tryParse(row['TABLE_ROWS']?.toString() ?? '');
      if (name != null && n != null) {
        out.add((schema: row['table_schema']?.toString(), name: name, rows: n));
      }
    }
    return out;
  }

  // T008 — killProcess via adapter
  Future<bool> killProcess(int processId, {String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return false;
    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null) return false;
    return await adapter.killProcess(processId);
  }

  // T008 — getReplicationStatus via adapter
  Future<ReplicationStatus?> getReplicationStatus({
    String? connectionId,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return null;
    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null) return null;
    return await adapter.getReplicationStatus();
  }

  // T008 — getEngineStatus (MySQL only)
  Future<Map<String, dynamic>?> getEngineStatus({String? connectionId}) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return null;
    final server = _state.servers[targetConnectionId];
    if (server?.type != DatabaseType.mysql) return null;
    try {
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return null;
      final results = await adapter.executeQuery('SHOW ENGINE INNODB STATUS');
      if (results.rows.isEmpty) return null;
      final row = results.rows.first;
      return {
        'engine': row['Engine']?.toString() ?? 'InnoDB',
        'status': row['Status']?.toString() ?? '',
      };
    } catch (e) {
      AppLogger.d('DatabaseService', 'getEngineStatus failed: $e');
      return null;
    }
  }

  Future<bool> createDatabase(
    String dbName, {
    String? charset,
    String? collation,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');
    // read-only 守卫须在服务层 choke point 拦截：此方法不经 executeQuery，
    // executeQuery 里的 read-only 守卫无法兜住 UI/AI/直调路径。
    ensureServerNotReadOnly(server, operation: 'createDatabase');

    // Doris 并入 else(adapter) 分支，服务层不再内联 Doris 方言
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // 透传 charset/collation（PG adapter 映射为 ENCODING/LC_COLLATE；mysql 族
    // 网关壳读 charset/collation 键（CHARACTER SET/COLLATE）；其它 adapter
    // 忽略未识别的 options key，行为不变）
    final options = <String, dynamic>{};
    if (charset != null) {
      options['encoding'] = charset;
      options['charset'] = charset;
    }
    if (collation != null) {
      options['collate'] = collation;
      options['collation'] = collation;
    }
    return await adapter.createDatabase(dbName, options: options);
  }

  Future<bool> dropDatabase(String dbName) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');
    // read-only 守卫须在服务层 choke point 拦截：此方法不经 executeQuery，
    // executeQuery 里的 read-only 守卫无法兜住 UI「Drop Database」/AI/直调路径。
    ensureServerNotReadOnly(server, operation: 'dropDatabase');

    // Doris 并入 else(adapter) 分支，服务层不再内联 Doris 方言
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    return await adapter.dropDatabase(dbName);
  }

  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) async {
    final server = _state.currentServer;
    if (server == null) return null;

    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return null;
    return await adapter.getDatabaseProperties(dbName);
  }

  Future<String> getDatabaseSize(String dbName) async {
    final server = _state.currentServer;
    if (server == null) return 'Unknown';

    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      // T29：经网关壳 adapter 执行（SQL 与旧裸连接版逐行一致）。
      final adapter = _state.adapters[_state.activeConnectionId];
      if (adapter == null || !adapter.isConnected) return 'Unknown';

      try {
        final results = await adapter.executeQuery('''
          SELECT 
            ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
          FROM information_schema.TABLES 
          WHERE table_schema = ${SqlEscapeUtils.escapeString(dbName)}
          GROUP BY table_schema
        ''');

        if (results.rows.isNotEmpty) {
          final values = results.rows.first.values;
          final sizeMb = values.isEmpty ? '0' : values.first?.toString() ?? '0';
          return '$sizeMb MB';
        }
      } catch (e) {
        AppLogger.e('DatabaseService', '操作失败', e);
      }
      return 'Unknown';
    } else {
      return 'N/A';
    }
  }

  Future<String> getCreateDatabaseSql(String dbName) async {
    final server = _state.currentServer;
    if (server == null) return '';

    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      // T29：经网关壳 adapter 执行（SQL 与旧裸连接版逐行一致；行按列序位置
      // 取值——SHOW CREATE DATABASE 第 2 列为建库语句）。
      final adapter = _state.adapters[_state.activeConnectionId];
      if (adapter == null || !adapter.isConnected) return '';

      try {
        final results = await adapter.executeQuery(
          'SHOW CREATE DATABASE ${SqlEscapeUtils.escapeMySqlIdentifier(dbName)}',
        );
        if (results.rows.isNotEmpty) {
          final values = results.rows.first.values.toList();
          return values.length > 1 ? values[1]?.toString() ?? '' : '';
        }
      } catch (e) {
        AppLogger.e('DatabaseService', '操作失败', e);
      }
      return '';
    } else {
      return '-- Not supported for ${server.type.displayName}';
    }
  }

  Future<List<String>> getCharsets() async {
    final server = _state.currentServer;
    if (server == null) return [];

    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getCharsets();
  }

  Future<List<Map<String, String>>> getCollations({String? charset}) async {
    final server = _state.currentServer;
    if (server == null) return [];

    if (server.type == DatabaseType.doris) {
      // Doris 不支持 SHOW COLLATION WHERE Charset = '...' 语法
      return [];
    }

    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getCollations(charset: charset);
  }

  Future<String> exportDatabaseStructure(String dbName) async {
    final server = _state.currentServer;
    if (server == null) return '';

    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return '';
    return await adapter.exportDatabaseStructure(dbName);
  }

  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    String? comment,
    String? engine,
    Map<String, dynamic>? options,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // mysql 族统一走 adapter；建表方言（Doris 分桶/属性/COMMENT）由
    // DorisAdapter 覆写负责，MySQL 壳读 options['engine']/['comment']。
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // MySQL/Doris 经 adapter 建表，透传 comment/engine + 模型/分桶(options)；方言在 adapter
    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      final opts = <String, dynamic>{};
      if (engine != null) opts['engine'] = engine;
      if (comment != null) opts['comment'] = comment;
      if (options != null) opts.addAll(options);
      return await adapter.createTable(tableName, columns, options: opts);
    }
    return await adapter.createTable(tableName, columns);
  }

  Future<bool> dropTable(String tableName, {String? databaseName}) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // Doris 并入 else(adapter) 分支
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // Doris 经 adapter；databaseName 上下文由 useDatabase 保证
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.dropTable(tableName);
  }

  Future<bool> renameTable(
    String oldName,
    String newName, {
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // Doris 并入 else(adapter) 分支，重命名方言由 DorisAdapter 负责
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // Doris 经 adapter；databaseName 上下文由 useDatabase 保证
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.renameTable(oldName, newName);
  }

  Future<bool> truncateTable(String tableName, {String? databaseName}) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // Doris 并入 else(adapter) 分支
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // Doris 经 adapter；databaseName 上下文由 useDatabase 保证
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.truncateTable(tableName);
  }

  Future<List<Map<String, dynamic>>> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return [];

    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    final result = await adapter.getTableData(
      tableName,
      limit: limit,
      offset: offset,
      cursorColumn: cursorColumn,
      cursorValue: cursorValue,
    );
    return result.rows;
  }

  Future<int> getTableRowCount(String tableName, {String? databaseName}) async {
    final server = _state.currentServer;
    if (server == null) return 0;

    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return 0;
    return await adapter.getTableRowCount(tableName);
  }

  /// 获取单表精确行数（支持 connectionId/sessionId/databaseName 隔离）
  Future<int> getTableExactRowCount(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return 0;

    final server = _state.servers[targetConnectionId];
    if (server == null) return 0;

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return 0;
    return await adapter.getTableRowCount(tableName);
  }

  Future<Map<String, dynamic>?> getTableProperties(
    String tableName, {
    String? connectionId,
    String? dbName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return null;

    final server = _state.servers[targetConnectionId];
    if (server == null) return null;

    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      // T29：经网关壳 adapter 执行（SQL 与旧裸连接版逐行一致；行按列序位置取值）。
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return null;

      try {
        // S8c: 读客户端状态，省 SELECT DATABASE() 往返。
        final targetDbName =
            dbName ?? _state.servers[targetConnectionId]?.database ?? 'mysql';

        final results = await adapter.executeQuery('''
          SELECT 
            TABLE_NAME,
            ENGINE,
            TABLE_ROWS,
            AVG_ROW_LENGTH,
            DATA_LENGTH,
            INDEX_LENGTH,
            AUTO_INCREMENT,
            CREATE_TIME,
            UPDATE_TIME,
            TABLE_COLLATION,
            TABLE_COMMENT
          FROM information_schema.TABLES 
          WHERE TABLE_SCHEMA = '${targetDbName.replaceAll("'", "''")}' AND TABLE_NAME = '${tableName.replaceAll("'", "''")}'
        ''');

        if (results.rows.isNotEmpty) {
          final values = results.rows.first.values.toList();
          String? at(int i) => i < values.length ? values[i]?.toString() : null;
          return {
            'name': at(0),
            'engine': at(1),
            'rows': int.tryParse(at(2) ?? '0') ?? 0,
            'avgRowLength': int.tryParse(at(3) ?? '0') ?? 0,
            'dataLength': int.tryParse(at(4) ?? '0') ?? 0,
            'indexLength': int.tryParse(at(5) ?? '0') ?? 0,
            'autoIncrement': at(6),
            'createTime': at(7),
            'updateTime': at(8),
            'collation': at(9),
            'comment': at(10),
          };
        }
      } catch (e) {
        AppLogger.e('DatabaseService', '获取表属性失败: $tableName', e);
      }
      return null;
    } else {
      return null;
    }
  }

  Future<String> getCreateTableSql(
    String tableName, {
    String? connectionId,
    String? databaseName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return '';

    final server = _state.servers[targetConnectionId];
    if (server == null) return '';

    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      // T29：经网关壳 adapter 执行（SQL 与旧裸连接版逐行一致；行按列序位置
      // 取值——SHOW CREATE TABLE 第 2 列为建表语句）。
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return '';

      try {
        final results = await adapter.executeQuery(
          'SHOW CREATE TABLE ${_escapeMySqlTableName(tableName, databaseName)}',
        );
        if (results.rows.isNotEmpty) {
          final values = results.rows.first.values.toList();
          return values.length > 1 ? values[1]?.toString() ?? '' : '';
        }
      } catch (e) {
        AppLogger.e('DatabaseService', '操作失败', e);
      }
      return '';
    } else if (server.type == DatabaseType.postgresql ||
        server.type == DatabaseType.sqlite) {
      final adapter = _state.adapters[targetConnectionId];
      if (adapter == null || !adapter.isConnected) return '';

      try {
        final columns = await adapter.getTableColumns(tableName);
        final indexes = await adapter.getTableIndexes(tableName);
        final foreignKeys = await adapter.getForeignKeys(tableName);
        final q = server.type == DatabaseType.sqlite ? '"' : '"';
        return _buildCreateTableSql(
          tableName,
          columns,
          indexes,
          foreignKeys,
          q,
          server.type,
        );
      } catch (e) {
        AppLogger.e('DatabaseService', 'getCreateTableSql failed', e);
        return '';
      }
    } else {
      return '-- Not supported for ${server.type.displayName}';
    }
  }

  String _buildCreateTableSql(
    String tableName,
    List<DbColumn> columns,
    List<DbIndex> indexes,
    List<ForeignKey>? foreignKeys,
    String q,
    DatabaseType dbType,
  ) {
    final buf = StringBuffer();
    // 表名按 schema.table 逐段转义（PG/SQLite 的 q='"'），避免 "schema.table"
    // 被当成含点的单标识符。复用 SqlEscapeUtils.escapePgQualifiedIdentifier。
    final quotedTable = SqlEscapeUtils.escapePgQualifiedIdentifier(tableName);
    buf.writeln('CREATE TABLE $quotedTable (');

    final pkColumns = columns.where((c) => c.isPrimaryKey).toList();
    final hasCompositePk = pkColumns.length > 1;

    // PG/SQLite 的 CREATE TABLE 内只允许 PRIMARY KEY / UNIQUE(约束) /
    // CHECK / FOREIGN KEY，不接受内联 INDEX（MySQL 语法，会导致新增表同步必报语法错误）。
    // 主键 backing index（<表>_pkey / sqlite_autoindex_ / PRIMARY）跳过；唯一索引改为
    // 表级 UNIQUE 约束（底层自动建唯一索引）；非唯一索引不在此输出——它们由
    // SchemaSyncService 经 compareSnapshots 的 indexDiffs 以独立 CREATE INDEX 同步。
    bool isPkBackingIndex(DbIndex i) =>
        i.name == 'PRIMARY' ||
        i.name.endsWith('_pkey') ||
        i.name.startsWith('sqlite_autoindex_');
    final uniqueConstraints = indexes
        .where((i) => i.isUnique && !isPkBackingIndex(i))
        .toList();
    final fks = foreignKeys ?? [];
    final hasMoreAfterColumns =
        hasCompositePk || uniqueConstraints.isNotEmpty || fks.isNotEmpty;

    for (int i = 0; i < columns.length; i++) {
      final col = columns[i];
      // PG serial/identity 列——integer/bigint/smallint 且默认为
      // nextval('...') 时转为 serial/bigserial/smallserial 并去掉 DEFAULT，让 PG 自动
      // 建序列。否则目标库不存在该序列，CREATE TABLE 失败致整批回滚（见 resolvePgSerialColumn）。
      final resolved = resolvePgSerialColumn(
        dbType,
        col.type,
        col.defaultValue,
      );
      buf.write('  $q${col.name}$q ${resolved.type}');
      if (!col.isNullable) buf.write(' NOT NULL');
      if (col.isPrimaryKey && !hasCompositePk) buf.write(' PRIMARY KEY');
      if (resolved.defaultValue != null) {
        buf.write(' DEFAULT ${resolved.defaultValue}');
      }
      final isLastColumn = i == columns.length - 1;
      if (!isLastColumn || hasMoreAfterColumns) buf.write(',');
      buf.writeln();
    }

    // Composite primary key as table constraint
    if (hasCompositePk) {
      final pkColList = pkColumns.map((c) => '$q${c.name}$q').join(', ');
      buf.write('  PRIMARY KEY ($pkColList)');
      if (uniqueConstraints.isNotEmpty || fks.isNotEmpty) buf.write(',');
      buf.writeln();
    }

    // Unique indexes → table-level UNIQUE constraints (valid in PG/SQLite)
    for (int i = 0; i < uniqueConstraints.length; i++) {
      final idx = uniqueConstraints[i];
      final colList = idx.columns.map((c) => '$q$c$q').join(', ');
      buf.write('  UNIQUE ($colList)');
      if (i < uniqueConstraints.length - 1 || fks.isNotEmpty) buf.write(',');
      buf.writeln();
    }

    // Foreign key constraints
    // 多 schema——裸名 FK 引用补同 schema 限定（见 resolvePgQualifiedFkReference），
    // 否则目标库 search_path 默认 public → 42P01 "relation ... does not exist"。
    // DEFENSIVE-NOTE: ForeignKey 无 referencedSchema 字段，按"同 schema"启发式限定；
    // 跨 schema 裸引用（products→other_schema.tbl）为已知限制，仍可能解析失败。
    for (int i = 0; i < fks.length; i++) {
      final fk = fks[i];
      final refTable = resolvePgQualifiedFkReference(
        tableName,
        fk.referencedTable,
      );
      buf.write(
        '  FOREIGN KEY ($q${fk.column}$q) REFERENCES ${SqlEscapeUtils.escapePgQualifiedIdentifier(refTable)} ($q${fk.referencedColumn}$q)',
      );
      if (i < fks.length - 1) buf.write(',');
      buf.writeln();
    }

    buf.write(');');
    return buf.toString();
  }

  Future<List<DbIndex>> getTableIndexes(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    // SQLite ATTACH（spec 050）：databaseName 承载附加库 alias（同
    // getTableColumns 的 sqlite 分支）。
    if (server.type == DatabaseType.sqlite &&
        adapter is SQLiteAdapter &&
        databaseName != null &&
        databaseName.isNotEmpty &&
        databaseName != 'main') {
      return await adapter.getTableIndexes(tableName, schemaName: databaseName);
    }
    return await adapter.getTableIndexes(tableName);
  }

  Future<List<ForeignKey>> getForeignKeys(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getForeignKeys(tableName);
  }

  /// 反向外键查询：返回引用 [tableName] 的外键（其他表 → 本表）。
  /// AI 关联删除分析与 FK 影响面查询的入口（详见 DatabaseAdapter 文档）。
  Future<List<ForeignKey>> getReferencingForeignKeys(
    String tableName, {
    String? connectionId,
    String? databaseName,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) return [];

    final server = _state.servers[targetConnectionId];
    if (server == null) return [];

    final adapter = _state.adapters[targetConnectionId];
    if (adapter == null || !adapter.isConnected) return [];
    return await adapter.getReferencingForeignKeys(tableName);
  }

  Future<bool> addColumn(
    String tableName,
    DbColumn column, {
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // Doris 并入 else(adapter) 分支
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // Doris 经 adapter；databaseName 上下文由 useDatabase 保证
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.addColumn(tableName, column);
  }

  Future<bool> dropColumn(
    String tableName,
    String columnName, {
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // Doris 并入 else(adapter) 分支
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // Doris 经 adapter；databaseName 上下文由 useDatabase 保证
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.dropColumn(tableName, columnName);
  }

  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn, {
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // Doris 并入 else(adapter) 分支
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // Doris 经 adapter；databaseName 上下文由 useDatabase 保证
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.modifyColumn(tableName, oldColumnName, newColumn);
  }

  // renameColumn facade — 连接列重命名 UI 到适配器层
  // DorisAdapter 已正确覆写 (ALTER TABLE t RENAME COLUMN old new)，
  // 但此前无服务层路径可达。
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName, {
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // MySQL 走 adapter.renameColumn (基类 CHANGE COLUMN 方言)
    // Doris 和其它类型统一经 adapter
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.renameColumn(tableName, oldColumnName, newColumnName);
  }

  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // Doris 并入 else(adapter) 分支，索引倒排方言由 DorisAdapter 负责
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // Doris 经 adapter；databaseName 上下文由 useDatabase 保证
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.createIndex(
      tableName,
      indexName,
      columns,
      unique: unique,
    );
  }

  Future<bool> dropIndex(
    String tableName,
    String indexName, {
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return false;
    ensureServerNotReadOnly(server, operation: 'schemaWrite');

    // Doris 并入 else(adapter) 分支，删索引方言由 DorisAdapter 负责
    final adapter = _state.adapters[_state.activeConnectionId];
    if (adapter == null || !adapter.isConnected) return false;
    // Doris 经 adapter；databaseName 上下文由 useDatabase 保证
    if ((server.type == DatabaseType.mysql ||
            server.type == DatabaseType.doris) &&
        databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.dropIndex(tableName, indexName);
  }

  Future<String> exportTableData(
    String tableName, {
    int limit = 1000,
    String? databaseName,
  }) async {
    final server = _state.currentServer;
    if (server == null) return '';

    if (server.type == DatabaseType.mysql ||
        server.type == DatabaseType.doris) {
      // T29：网关壳 adapter 连通性检查（数据获取走下方 getTableData →
      // adapter.getTableData）。
      final adapter = _state.adapters[_state.activeConnectionId];
      if (adapter == null || !adapter.isConnected) return '';

      try {
        final data = await getTableData(
          tableName,
          limit: limit,
          databaseName: databaseName,
        );
        if (data.isEmpty) return '';

        final buffer = StringBuffer();
        buffer.writeln('-- DBMaster Table Data Export');
        buffer.writeln('-- Table: $tableName');
        buffer.writeln('-- Generated: ${DateTime.now().toIso8601String()}');
        buffer.writeln('');

        final columns = data.first.keys.toList();

        for (final row in data) {
          final values = columns
              .map((col) {
                final val = row[col];
                if (val == null) return 'NULL';
                return SqlSanitizer.value(
                  val,
                ).substring(1, SqlSanitizer.value(val).length - 1);
              })
              .join(', ');

          buffer.writeln(
            'INSERT INTO ${SqlEscapeUtils.escapeMySqlIdentifier(tableName)} (${columns.map((c) => SqlEscapeUtils.escapeMySqlIdentifier(c)).join(', ')}) VALUES ($values);',
          );
        }

        return buffer.toString();
      } catch (e) {
        AppLogger.e('DatabaseService', '导出表数据失败: $tableName', e);
        rethrow;
      }
    } else {
      return '-- Export not supported for ${server.type.displayName}';
    }
  }
}

// ============================================================================
// DatabaseService Facade（保持原有接口不变，内部委托给各个 Manager）
// ============================================================================

class DatabaseService {
  /// open-core Phase B — Pro 经此注入 Mongo 集群策略；OSS 默认 null。
  DatabaseService({MongoClusterStrategy? mongoClusterStrategy})
    : _mongoClusterStrategy = mongoClusterStrategy;

  final MongoClusterStrategy? _mongoClusterStrategy;
  final _ConnectionState _state = _ConnectionState();
  late final _ConnectionManager _connMgr = _ConnectionManager(
    _state,
    mongoClusterStrategy: _mongoClusterStrategy,
  );
  late final _QueryExecutor _queryExecutor = _QueryExecutor(_state);
  late final _SchemaManager _schemaMgr = _SchemaManager(_state);
  final QueryExecutionInterceptor _interceptor = QueryExecutionInterceptor();

  // 最后一次查询的截断信息
  bool _lastQueryWasTruncated = false;
  int? _lastQueryLimitValue;
  Map<String, String>? _lastColumnTypes;
  Set<String> _lastTruncatedColumns = <String>{};
  // C12：最后一次查询的结果形态（按连接类型判定，供 ExecutionResult 装配
  // 读取——与 lastColumnTypes 同款「执行后暂存」契约）。
  ResultDataShape? _lastDataShape;
  bool get lastQueryWasTruncated => _lastQueryWasTruncated;
  int? get lastQueryLimitValue => _lastQueryLimitValue;
  Map<String, String>? get lastColumnTypes => _lastColumnTypes;
  Set<String> get lastTruncatedColumns => _lastTruncatedColumns;
  ResultDataShape? get lastDataShape => _lastDataShape;

  // 代理属性
  bool get isConnected => _state.isConnected;
  DbServer? get currentServer => _state.currentServer;

  // ── C21 连接级查询覆盖（编辑器上下文芯片；转发 _QueryExecutor）──
  void setQueryOverride(
    String connectionId, {
    int? rowLimit,
    int? timeoutSeconds,
  }) => _queryExecutor.setQueryOverride(
    connectionId,
    rowLimit: rowLimit,
    timeoutSeconds: timeoutSeconds,
  );

  void clearQueryOverride(String connectionId) =>
      _queryExecutor.clearQueryOverride(connectionId);

  void clearRowLimitOverride(String connectionId) =>
      _queryExecutor.clearRowLimitOverride(connectionId);

  void clearTimeoutOverride(String connectionId) =>
      _queryExecutor.clearTimeoutOverride(connectionId);

  ConnectionQueryOverride? queryOverride(String connectionId) =>
      _queryExecutor.queryOverride(connectionId);

  int effectiveQueryTimeoutSeconds(int fallbackSeconds, String connectionId) =>
      _queryExecutor.effectiveQueryTimeoutSeconds(
        fallbackSeconds,
        connectionId,
      );

  /// feature 039 D3：原子刷新连接 readOnly（运行时开关实时生效，避免双源不同步）。
  /// 同更 `_state.servers[id]` / `currentServer` + 活跃 adapter.currentConnection。
  void toggleReadOnly(String connectionId, bool value) {
    final server = _state.servers[connectionId];
    if (server == null) return;
    final updated = server.copyWith(readOnly: value);
    _state.servers[connectionId] = updated;
    if (_state.currentServer?.id == connectionId) {
      _state.currentServer = updated;
    }
    _state.adapters[connectionId]?.updateReadOnly(value);
  }

  String? get activeConnectionId => _state.activeConnectionId;
  List<String> get connectedIds => _state.connectedIds;
  int get connectionCount => _state.connectionCount;
  DatabaseAdapter? get currentAdapter =>
      getAdapter(_state.activeConnectionId ?? '');
  DatabaseAdapter? getAdapter(String connectionId) =>
      _state.adapters[connectionId];

  // 连接状态查询
  bool isConnecting(String connectionId) => _connMgr.isConnecting(connectionId);

  /// 标记连接「在途」（T29 走查修复的重入弹窗守卫测试用）。
  @visibleForTesting
  void markConnectingForTest(String connectionId) =>
      _connMgr.markConnectingForTest(connectionId);
  bool isConnectionActive(String connectionId) =>
      _connMgr.isConnectionActive(connectionId);
  bool hasConnection(String connectionId) =>
      _connMgr.hasConnection(connectionId);
  Stream<ConnectionEvent> get events => _connMgr.events;

  // Test-only hook to inject ConnectionEstablished events into the
  // broadcast stream without requiring a real database connection.
  @visibleForTesting
  void addEventForTest(ConnectionEvent event) =>
      _connMgr.addEventForTest(event);

  // Test-only hook to inject stream errors for onError handling tests.
  @visibleForTesting
  void addErrorForTest(Object error) => _connMgr.addErrorForTest(error);

  // Test-only hook to register a server as connected without a real
  // database connection.
  @visibleForTesting
  void registerConnectedServerForTest(DbServer server) =>
      _connMgr.registerConnectedServerForTest(server);

  // Test-only hook to register a pre-connected adapter without a real
  // database connection. registerConnectedServerForTest only marks the
  // server state; hasConnection() checks adapters, so
  // callers that need hasConnection()/isConnectionConnected() to return
  // true should inject a connected adapter here.
  @visibleForTesting
  void registerConnectedAdapterForTest(
    String connectionId,
    DatabaseAdapter adapter,
  ) => _connMgr.registerConnectedAdapterForTest(connectionId, adapter);

  // 事务状态
  bool isInTransaction(String? connectionId) =>
      _state.isInTransaction(connectionId ?? _state.activeConnectionId ?? '');
  Stream<String> get transactionEvents => _state.transactionEvents;

  bool isSessionInTransaction(String sessionId) =>
      _state.isSessionInTransaction(sessionId);
  Stream<String> get sessionTransactionEvents =>
      _state.sessionTransactionEvents;

  // 事务管理
  Future<void> beginTransaction({
    String? connectionId,
    String? sessionId,
  }) async {
    final id = connectionId ?? _state.activeConnectionId;
    if (id == null) throw Exception('Not connected');

    final server = _state.servers[id];
    if (server == null) throw Exception('Connection not found');

    final adapter = getAdapter(id);
    if (adapter == null) throw Exception('Adapter not found');

    // S10: route the main-connection transaction through the server's
    // session-pinned txn endpoint when policy allows (embedded + mysql/doris
    // + server-id mapping). Falls back to the local adapter on any failure.
    final gateway = DbGatewayService.instance;
    if (sessionId == null && gateway.isBrowseGatewayReady(server)) {
      final serverConnId = await gateway.lookupServerConnId(id);
      if (serverConnId != null) {
        try {
          final txnSid = await gateway.txnBegin(
            serverConnId,
            db: server.database,
          );
          if (txnSid != null) {
            _state.txnSessionIds[id] = txnSid;
            _state.setTransactionState(id, true);
            AppLogger.i('DatabaseService', 'S10 事务已开始 (server): $id');
            return;
          }
          // txnBegin returned null (e.g. CH UNSUPPORTED_TXN) → fall through
          // to local. For CH the local adapter also can't transact, but the
          // error surfaces there rather than as a silent no-op.
        } catch (e) {
          AppLogger.w('DatabaseService', 'S10 txn begin 失败，回退本地: $e');
          // fall through to local adapter
        }
      }
    }

    await adapter.beginTransaction();
    _state.setTransactionState(id, true);
    AppLogger.i('DatabaseService', '事务已开始: $id');
  }

  Future<void> commit({String? connectionId, String? sessionId}) async {
    final id = connectionId ?? _state.activeConnectionId;
    if (id == null) throw Exception('Not connected');

    final server = _state.servers[id];
    if (server == null) throw Exception('Connection not found');

    final adapter = getAdapter(id);
    if (adapter == null) throw Exception('Adapter not found');

    // S10: commit the server-side transaction session if one is open.
    final txnSid = _state.txnSessionIds.remove(id);
    if (txnSid != null) {
      final gateway = DbGatewayService.instance;
      final serverConnId = await gateway.lookupServerConnId(id);
      if (serverConnId != null) {
        try {
          await gateway.txnCommit(serverConnId, txnSid);
          _state.setTransactionState(id, false);
          AppLogger.i('DatabaseService', 'S10 事务已提交 (server): $id');
          return;
        } catch (e) {
          AppLogger.w('DatabaseService', 'S10 txn commit 失败，回退本地: $e');
          // fall through to local adapter (best-effort; the server session
          // may already be committed or expired — local commit is a no-op
          // for data already committed server-side, but harmless).
        }
      }
    }

    await adapter.commit();
    _state.setTransactionState(id, false);
    AppLogger.i('DatabaseService', '事务已提交: $id');
  }

  Future<void> rollback({String? connectionId, String? sessionId}) async {
    final id = connectionId ?? _state.activeConnectionId;
    if (id == null) throw Exception('Not connected');

    final server = _state.servers[id];
    if (server == null) throw Exception('Connection not found');

    final adapter = getAdapter(id);
    if (adapter == null) throw Exception('Adapter not found');

    // S10: rollback the server-side transaction session if one is open.
    final txnSid = _state.txnSessionIds.remove(id);
    if (txnSid != null) {
      final gateway = DbGatewayService.instance;
      final serverConnId = await gateway.lookupServerConnId(id);
      if (serverConnId != null) {
        try {
          await gateway.txnRollback(serverConnId, txnSid);
          _state.setTransactionState(id, false);
          AppLogger.i('DatabaseService', 'S10 事务已回滚 (server): $id');
          return;
        } catch (e) {
          AppLogger.w('DatabaseService', 'S10 txn rollback 失败，回退本地: $e');
          // fall through to local adapter
        }
      }
    }

    await adapter.rollback();
    _state.setTransactionState(id, false);
    AppLogger.i('DatabaseService', '事务已回滚: $id');
  }

  // 连接生命周期管理
  Future<bool> connect(DbServer server) => _connMgr.connect(server);
  void cancelConnect(String connectionId) =>
      _connMgr.cancelConnect(connectionId);
  void setActiveConnection(String connectionId) =>
      _connMgr.setActiveConnection(connectionId);
  Future<void> disconnect({String? connectionId}) =>
      _connMgr.disconnect(connectionId: connectionId);
  Future<void> disconnectAll() => _connMgr.disconnectAll();
  Future<String?> testConnection(DbServer server) =>
      _connMgr.testConnection(server);

  // 查询执行
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
    bool skipDdlAnalysis = false,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    AppLogger.d(
      'DatabaseService',
      '[DatabaseService] executeQuery: sql=${AppLogger.sqlPreview(sql)}, connectionId=$connectionId, targetConnectionId=$targetConnectionId, database=$database, sessionId=$sessionId',
    );
    if (targetConnectionId == null) throw Exception('Not connected');

    final server = _state.servers[targetConnectionId];
    if (server == null) throw Exception('Connection not found');

    // 只读模式检查
    if (server.readOnly && _isWriteQuery(sql)) {
      throw Exception('只读模式下禁止执行修改操作');
    }

    final currentDatabase = database ?? server.database;
    AppLogger.d(
      'DatabaseService',
      '[DatabaseService] executeQuery: currentDatabase=$currentDatabase, server.database=${server.database}',
    );

    // DML 安全检查（拦截）— 在 DDL 分析之前执行
    if (_interceptor.enableDmlCheck) {
      try {
        _interceptor.checkDmlSafety(
          sql: sql,
          dbType: server.type,
          connectionId: targetConnectionId,
        );
      } on DmlConfirmationRequiredException {
        rethrow;
      } on DmlWarningRequiredException {
        rethrow;
      } catch (_) {
        // Non-DML exceptions from checkDmlSafety pass through silently;
        // DML safety check failures should never block execution.
      }
    }

    // Doris UPDATE 模型守卫——DUP/AGG 模型不支持 UPDATE（警告不阻断）
    if (server.type == DatabaseType.doris) {
      try {
        await _interceptor.checkDorisUpdateGuard(
          sql: sql,
          dbType: server.type,
          executeQuery: (query) async {
            final adapter = _state.adapters[targetConnectionId];
            if (adapter != null && adapter.isConnected) {
              return (await adapter.executeQuery(query)).rows;
            }
            throw Exception('Not connected');
          },
        );
      } on DmlWarningRequiredException {
        rethrow;
      } catch (_) {
        // 守卫检测失败 → 降级，不阻断执行
      }
    }

    // DDL 影响分析（拦截）。skipDdlAnalysis=true 时跳过——调用方已在更高层
    // （如执行门）确认过，避免重复分析（链路统一，见第四阶段后续）。
    if (!skipDdlAnalysis && QueryExecutionInterceptor.isDdlStatement(sql)) {
      final impactReport = await _interceptor.beforeExecute(
        sql: sql,
        databaseType: server.type,
        connectionId: targetConnectionId,
        executeQuery: (query) async {
          // 使用适配器执行查询，避免递归
          final adapter = _state.adapters[targetConnectionId];
          if (adapter != null && adapter.isConnected) {
            final result = await adapter.executeQuery(query);
            return result.rows;
          }

          throw Exception('Not connected');
        },
        getServerVersion: () async {
          final v = await getServerVersion(connectionId: targetConnectionId);
          return v?['version'] as String?;
        },
      );

      if (impactReport != null) {
        throw DdlConfirmationRequiredException(
          sql: sql,
          impactReport: impactReport,
        );
      }
    }

    // 执行查询
    final startTime = DateTime.now();
    _QueryExecutionResult? queryResult;
    bool isSuccess = true;
    String? errorMessage;

    try {
      queryResult = await _queryExecutor.executeQueryWithStats(
        sql,
        connectionId: targetConnectionId,
        database: currentDatabase,
        sessionId: sessionId,
      );
      _lastQueryWasTruncated = queryResult.isTruncated;
      _lastQueryLimitValue = queryResult.limitValue;
      _lastColumnTypes = queryResult.columnTypes;
      _lastTruncatedColumns = queryResult.truncatedColumns;
      _lastDataShape = ResultDataShape.shapeForDatabaseType(server.type);
      return queryResult.rows;
    } catch (e) {
      isSuccess = false;
      errorMessage = e.toString();
      // 检测连接是否已实际丢失，如果是则自动清理状态避免 UI 显示已连接但实际不可用
      // 切库期间（adapter 主动 close 旧连接）在途查询必然失败，但其错误
      // 含 connection/closed 等关键词会被 isConnectionLostError 命中；若此时 disconnect，
      // 会把 adapter 从 _state.adapters 移除并 _currentConnection 置 null，破坏正在进行的
      // useDatabase。故切库期间跳过自动断开。
      final switchingAdapter = _state.adapters[targetConnectionId];
      if (isConnectionLostError(errorMessage) &&
          !(switchingAdapter?.isSwitchingDatabase ?? false)) {
        AppLogger.w('DatabaseService', '检测到连接已丢失，自动断开: $targetConnectionId');
        try {
          await disconnect(connectionId: targetConnectionId);
        } catch (_) {
          // 忽略断开时的错误，确保原始查询异常能正常抛出
        }
      }
      rethrow;
    } finally {
      // 记录查询历史（不抛异常，避免掩盖原始错误）
      try {
        final executionTimeMs = DateTime.now()
            .difference(startTime)
            .inMilliseconds;
        await _interceptor.afterExecute(
          sql: sql,
          connectionId: targetConnectionId,
          connectionName: server.name,
          databaseType: server.type,
          databaseName: currentDatabase,
          executionTimeMs: executionTimeMs,
          isSuccess: isSuccess,
          errorMessage: errorMessage,
          rowCount: queryResult?.affectedRows ?? queryResult?.rows.length,
        );
      } catch (historyError) {
        // 历史记录失败不应影响查询执行结果
        developer.log(
          'Failed to record query history: $historyError',
          name: 'DatabaseService',
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> getExplainPlan(
    String sql, {
    String? connectionId,
  }) => _queryExecutor.getExplainPlan(sql, connectionId: connectionId);

  /// 绕过 DDL 检查执行查询（用于用户确认后执行）
  Future<List<Map<String, dynamic>>> executeQueryBypassDdl(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    final wasEnabled = _interceptor.enableDdlAnalysis;
    _interceptor.enableDdlAnalysis = false;
    try {
      return await executeQuery(
        sql,
        connectionId: connectionId,
        database: database,
        sessionId: sessionId,
      );
    } finally {
      _interceptor.enableDdlAnalysis = wasEnabled;
    }
  }

  Future<bool> executeSqlScriptBypassDdl(
    String script, {
    String? connectionId,
  }) async {
    final wasEnabled = _interceptor.enableDdlAnalysis;
    _interceptor.enableDdlAnalysis = false;
    try {
      return await executeSqlScript(script, connectionId: connectionId);
    } finally {
      _interceptor.enableDdlAnalysis = wasEnabled;
    }
  }

  /// 绕过 DML 安全检查执行查询（用于用户确认后执行）
  Future<List<Map<String, dynamic>>> executeQueryBypassDml(
    String sql, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) async {
    final wasDmlEnabled = _interceptor.enableDmlCheck;
    final wasDdlEnabled = _interceptor.enableDdlAnalysis;
    _interceptor.enableDmlCheck = false;
    _interceptor.enableDdlAnalysis = false;
    try {
      return await executeQuery(
        sql,
        connectionId: connectionId,
        database: database,
        sessionId: sessionId,
      );
    } finally {
      _interceptor.enableDmlCheck = wasDmlEnabled;
      _interceptor.enableDdlAnalysis = wasDdlEnabled;
    }
  }

  /// Expose the interceptor for audit logging and configuration by external callers.
  QueryExecutionInterceptor get interceptor => _interceptor;

  /// 判断 SQL 是否为写入操作
  bool _isWriteQuery(String sql) {
    final upper = sql.trim().toUpperCase();
    // INSERT, UPDATE, DELETE, DROP, CREATE, ALTER, TRUNCATE, REPLACE
    final writeKeywords = [
      'INSERT',
      'UPDATE',
      'DELETE',
      'DROP',
      'CREATE',
      'ALTER',
      'TRUNCATE',
      'REPLACE',
      'GRANT',
      'REVOKE',
    ];
    for (final keyword in writeKeywords) {
      // startsWith 覆盖常规形态；\b 正则覆盖 CTE（WITH ... INSERT）/ 前置
      // 注释等不以关键字开头的写语句。注意 raw 字符串必须单反斜杠——此前
      // r'\\b' 是字面反斜杠+b 的死子句（U17 修复），只读闸门曾漏判这类语句。
      if (upper.startsWith(keyword) ||
          RegExp(r'\b' + keyword + r'\b').hasMatch(upper)) {
        return true;
      }
    }
    return false;
  }

  /// 判断错误信息是否表示连接已丢失。
  ///
  /// 仅匹配真正的错误消息，先剥离 sqflite 回显的 SQL 尾部。sqflite/
  /// sqflite_ffi 会在错误后追加 "Causing statement:" 起的整段回显 SQL（含
  /// 任意用户数据，如 JSON key "connection"），整串匹配会把含该词的普通 SQL
  /// 错误误判为"连接丢失"并自动断开。剥离后用户数据不再干扰判定。
  static bool isConnectionLostError(String errorMessage) {
    final lower = _stripEchoedSql(errorMessage).toLowerCase();
    final connectionErrorKeywords = [
      'not connected',
      'connection',
      'socket',
      'broken pipe',
      'connection reset',
      'connection refused',
      'network',
      'timeout',
      'closed',
      'unreachable',
      'failed to connect',
      'connection closed',
      'errno',
      'no route to host',
      'host is down',
    ];
    return connectionErrorKeywords.any((keyword) => lower.contains(keyword));
  }

  /// 剥离错误串中回显的 SQL（"Causing statement:" 起及其后的 `sql '<SQL>'`），
  /// 仅保留真正的错误消息，避免用户数据（表名/列名/值）误触连接丢失关键字。
  static String _stripEchoedSql(String message) {
    const markers = ['causing statement', " sql '", ' sql "'];
    final lower = message.toLowerCase();
    int? earliest;
    for (final marker in markers) {
      final idx = lower.indexOf(marker);
      if (idx > 0 && (earliest == null || idx < earliest)) {
        earliest = idx;
      }
    }
    return earliest == null ? message : message.substring(0, earliest);
  }

  Future<bool> executeSqlScript(
    String script, {
    String? connectionId,
    bool skipDdlAnalysis = false,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null) throw Exception('Not connected');

    final server = _state.servers[targetConnectionId];
    if (server == null) throw Exception('Connection not found');

    final currentDatabase = server.database;

    // U08：SQL-aware 分割（与编辑器主执行路径 _QueryExecutor/TabProvider 同一
    // 分割器）——朴素 split(';') 会被字符串/注释里的分号截断语句，导致 DDL
    // 影响分析作用在残缺片段上（残片不以 DDL 关键字开头 = 分析被绕过）；
    // 以 `--` 开头的语句（前导注释行）会被整条漏掉。
    final statements = SQLParserService.split(script);

    // 检查 DDL 语句并进行影响分析。skipDdlAnalysis=true 时跳过（调用方已确认）。
    for (final statement in statements) {
      if (!skipDdlAnalysis &&
          QueryExecutionInterceptor.isDdlStatement(statement.sql)) {
        final impactReport = await _interceptor.beforeExecute(
          sql: statement.sql,
          databaseType: server.type,
          connectionId: targetConnectionId,
          executeQuery: (query) async {
            // 使用适配器执行查询，避免递归
            final adapter = _state.adapters[targetConnectionId];
            if (adapter != null && adapter.isConnected) {
              final result = await adapter.executeQuery(query);
              return result.rows;
            }

            throw Exception('Not connected');
          },
          getServerVersion: () async {
            final v = await getServerVersion(connectionId: targetConnectionId);
            return v?['version'] as String?;
          },
        );

        if (impactReport != null) {
          throw DdlConfirmationRequiredException(
            sql: statement.sql,
            impactReport: impactReport,
          );
        }
      }
    }

    // 执行脚本
    final startTime = DateTime.now();
    bool isSuccess = true;
    String? errorMessage;

    try {
      // S8b: 网关优先（admin/script 端点，server 端用真正的 SQL 分割器）。
      // DDL 分析已在上面完成（客户端 split + beforeExecute）；这里只把执行
      // 切到网关。失败降级到本地 _queryExecutor.executeSqlScript。
      final gateway = DbGatewayService.instance;
      if (gateway.isBrowseGatewayReady(server)) {
        final serverConnId = await gateway.lookupServerConnId(
          targetConnectionId,
        );
        if (serverConnId != null) {
          try {
            final results = await gateway.adminScript(
              serverConnId,
              script,
              db: currentDatabase,
            );
            // 任一语句失败视为整体失败（与本地 executeSqlScript 遇错 rethrow
            // 的语义一致）；返回 true 让 UI 认为脚本已跑。
            final failedIndex = results.indexWhere((r) => !r.ok);
            if (failedIndex >= 0) {
              final failed = results[failedIndex];
              throw SqlScriptExecutionException(
                statementIndex: failedIndex,
                statementSql: failed.sql,
                cause: failed.error ?? 'unknown error',
                committedCount: results
                    .take(failedIndex)
                    .where((r) => r.ok)
                    .length,
              );
            }
            return true;
          } catch (e) {
            AppLogger.w('DatabaseService', 'admin/script 网关失败，回退本地: $e');
            // fall through to local
          }
        }
      }
      final result = await _queryExecutor.executeSqlScript(script);
      return result;
    } catch (e) {
      isSuccess = false;
      errorMessage = e.toString();
      rethrow;
    } finally {
      // 记录脚本执行历史
      try {
        final executionTimeMs = DateTime.now()
            .difference(startTime)
            .inMilliseconds;
        await _interceptor.afterExecute(
          sql: '-- SQL Script (${statements.length} statements)',
          connectionId: targetConnectionId,
          connectionName: server.name,
          databaseType: server.type,
          databaseName: currentDatabase,
          executionTimeMs: executionTimeMs,
          isSuccess: isSuccess,
          errorMessage: errorMessage,
        );
      } catch (historyError) {
        developer.log(
          'Failed to record script history: $historyError',
          name: 'DatabaseService',
        );
      }
    }
  }

  bool isQueryCancelled(String connectionId) =>
      _queryExecutor.isQueryCancelled(connectionId);

  /// 通过断开主连接并重连来强制取消查询
  Future<bool> _cancelByReconnect(String connectionId, DbServer server) async {
    AppLogger.i('DatabaseService', '通过断开重连取消查询: $connectionId');
    try {
      _state.saveSessionSnapshot(connectionId);
      await _connMgr.disconnect(connectionId: connectionId);
      final success = await _connMgr.connect(server);
      if (!success) {
        AppLogger.e('DatabaseService', '取消后重连失败: $connectionId');
        return false;
      }
      await _connMgr.restoreSessionState(connectionId);
      AppLogger.i('DatabaseService', '断开重连完成，查询已取消: $connectionId');
      return true;
    } catch (e) {
      AppLogger.e('DatabaseService', '断开重连取消失败: $connectionId', e);
      return false;
    }
  }

  Future<bool> cancelQuery(String trackingKey) async {
    AppLogger.d('DatabaseService', '取消查询: $trackingKey');

    // 1. 标记取消状态
    _queryExecutor.completeCanceller(trackingKey);

    // 2. T29：tab session（裸连接时代 MySQL/Doris 专属）已随网关壳下线，
    // trackingKey 即 connectionId——与 pg/ss 等其它类型同一机制：断开重连
    // 强制取消（网关壳 disconnect 会 best-effort 取消在途执行）。
    final server = _state.servers[trackingKey];
    if (server == null) {
      AppLogger.w('DatabaseService', '无法解析 trackingKey，跳过取消: $trackingKey');
      return false;
    }

    return await _cancelByReconnect(trackingKey, server);
  }

  // Schema 元数据查询
  Future<List<String>> getDatabases({String? connectionId}) =>
      _schemaMgr.getDatabases(connectionId: connectionId);

  // spec 050：ATTACH 跨库委托
  Future<void> attachDatabase(String connectionId, String path, String alias) =>
      _schemaMgr.attachDatabase(connectionId, path, alias);
  Future<void> detachDatabase(String connectionId, String alias) =>
      _schemaMgr.detachDatabase(connectionId, alias);
  Future<void> saveDatabaseAs(String connectionId, String destPath) =>
      _schemaMgr.saveDatabaseAs(connectionId, destPath);
  Future<void> useDatabase(
    String dbName, {
    String? connectionId,
    String? sessionId,
  }) => _schemaMgr.useDatabase(
    dbName,
    connectionId: connectionId,
    sessionId: sessionId,
  );
  void updateServerDatabase(String dbName, {String? connectionId}) =>
      _schemaMgr.updateServerDatabase(dbName, connectionId: connectionId);
  Future<List<String>> getTables({String? connectionId}) =>
      _schemaMgr.getTables(connectionId: connectionId);
  Future<List<String>> getViews({String? connectionId}) =>
      _schemaMgr.getViews(connectionId: connectionId);
  Future<List<String>> getMaterializedViews({String? connectionId}) =>
      _schemaMgr.getMaterializedViews(connectionId: connectionId);
  Future<List<String>> getProcedures({String? connectionId}) =>
      _schemaMgr.getProcedures(connectionId: connectionId);
  Future<List<String>> getFunctions({String? connectionId}) =>
      _schemaMgr.getFunctions(connectionId: connectionId);
  Future<List<String>> getEvents({String? connectionId}) =>
      _schemaMgr.getEvents(connectionId: connectionId);
  Future<List<DbColumn>> getTableColumns(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) => _schemaMgr.getTableColumns(
    tableName,
    connectionId: connectionId,
    sessionId: sessionId,
    databaseName: databaseName,
  );
  Future<List<DbTable>> getAllTables({
    String? connectionId,
    bool includeDetails = false,
  }) => _schemaMgr.getAllTables(
    connectionId: connectionId,
    includeDetails: includeDetails,
  );
  Future<({List<String> items, int total})> getTablesPaginated({
    String? connectionId,
    String? sessionId,
    String? databaseName,
    int page = 1,
    int pageSize = 100,
    String? search,
  }) => _schemaMgr.getTablesPaginated(
    connectionId: connectionId,
    sessionId: sessionId,
    databaseName: databaseName,
    page: page,
    pageSize: pageSize,
    search: search,
  );

  Future<({List<DbTableMetadata> items, int total})>
  getTablesWithMetadataPaginated({
    String? connectionId,
    String? sessionId,
    String? databaseName,
    int page = 1,
    int pageSize = 100,
    String? search,
  }) async {
    final targetConnectionId = connectionId ?? _state.activeConnectionId;
    if (targetConnectionId == null)
      return (items: <DbTableMetadata>[], total: 0);

    final server = _state.servers[targetConnectionId];
    if (server == null) return (items: <DbTableMetadata>[], total: 0);

    final effectiveDbName = databaseName ?? server.database;

    // 先获取当前页表名（使用已优化的 getTablesPaginated）
    final paginated = await getTablesPaginated(
      connectionId: connectionId,
      sessionId: sessionId,
      databaseName: databaseName,
      page: page,
      pageSize: pageSize,
      search: search,
    );
    if (paginated.items.isEmpty) {
      return (items: <DbTableMetadata>[], total: paginated.total);
    }

    try {
      // MySQL/Doris: 只查当前页表的元信息，避免 SHOW TABLE STATUS 全库扫描
      if (server.type == DatabaseType.mysql ||
          server.type == DatabaseType.doris) {
        if (effectiveDbName != null && effectiveDbName.isNotEmpty) {
          final metadata = await _schemaMgr._getMysqlTablesMetadataPaginated(
            connectionId: targetConnectionId,
            sessionId: sessionId,
            databaseName: effectiveDbName,
            tableNames: paginated.items,
          );
          return (items: metadata, total: paginated.total);
        }
      }

      // PostgreSQL: 只查当前页表的元信息，避免全库 pg_class 扫描
      if (server.type == DatabaseType.postgresql) {
        if (effectiveDbName != null && effectiveDbName.isNotEmpty) {
          final metadata = await _schemaMgr
              ._getPostgresqlTablesMetadataPaginated(
                connectionId: targetConnectionId,
                databaseName: effectiveDbName,
                tableNames: paginated.items,
              );
          return (items: metadata, total: paginated.total);
        }
      }

      // 其他数据库走 adapter（默认全库后内存分页，后续可逐 adapter 优化）
      final adapter = _state.adapters[targetConnectionId];
      List<DbTableMetadata> allMetadata;
      if (adapter != null && adapter.isConnected) {
        allMetadata = await adapter.getTablesWithMetadata(
          database: effectiveDbName,
        );
      } else {
        return (
          items: paginated.items
              .map((name) => DbTableMetadata(name: name))
              .toList(),
          total: paginated.total,
        );
      }

      // 搜索过滤 + 内存分页
      var filtered = allMetadata;
      if (search != null && search.isNotEmpty) {
        final lowerSearch = search.toLowerCase();
        filtered = allMetadata.where((m) {
          return m.name.toLowerCase().contains(lowerSearch) ||
              (m.comment?.toLowerCase().contains(lowerSearch) ?? false);
        }).toList();
      }
      filtered.sort((a, b) => a.name.compareTo(b.name));

      final total = filtered.length;
      final offset = (page - 1) * pageSize;
      final items = filtered.skip(offset).take(pageSize).toList();
      return (items: items, total: total);
    } catch (e) {
      AppLogger.e('DatabaseService', '分页获取带元信息表列表失败', e);
      return (
        items: paginated.items
            .map((name) => DbTableMetadata(name: name))
            .toList(),
        total: paginated.total,
      );
    }
  }

  Future<Database> getDatabaseInfo(
    String dbName, {
    String? connectionId,
    bool includeTableDetails = false,
    bool schemasOnly = false,
  }) => _schemaMgr.getDatabaseInfo(
    dbName,
    connectionId: connectionId,
    includeTableDetails: includeTableDetails,
    schemasOnly: schemasOnly,
  );
  Future<Map<String, dynamic>?> getServerVersion({String? connectionId}) =>
      _schemaMgr.getServerVersion(connectionId: connectionId);
  Future<List<DbTrigger>> getTriggers({String? connectionId}) =>
      _schemaMgr.getTriggers(connectionId: connectionId);
  Future<Map<String, dynamic>> getServerStatus({String? connectionId}) =>
      _schemaMgr.getServerStatus(connectionId: connectionId);
  Future<Map<String, dynamic>> getGlobalVariables({String? connectionId}) =>
      _schemaMgr.getGlobalVariables(connectionId: connectionId);
  Future<List<Map<String, dynamic>>> getServerUsers({String? connectionId}) =>
      _schemaMgr.getServerUsers(connectionId: connectionId);
  Future<List<Map<String, dynamic>>> getProcessList({String? connectionId}) =>
      _schemaMgr.getProcessList(connectionId: connectionId);

  /// 表行数统计（C19 收编自 SidebarController，见 _SchemaManager 实现）。
  Future<List<({String? schema, String name, int rows})>> getTableRowCounts(
    String connectionId,
    String databaseName,
  ) => _schemaMgr.getTableRowCounts(connectionId, databaseName);
  Future<bool> killProcess(int processId, {String? connectionId}) =>
      _schemaMgr.killProcess(processId, connectionId: connectionId);
  Future<ReplicationStatus?> getReplicationStatus({String? connectionId}) =>
      _schemaMgr.getReplicationStatus(connectionId: connectionId);
  Future<Map<String, dynamic>?> getEngineStatus({String? connectionId}) =>
      _schemaMgr.getEngineStatus(connectionId: connectionId);

  // 数据库 DDL
  Future<bool> createDatabase(
    String dbName, {
    String? charset,
    String? collation,
  }) =>
      _schemaMgr.createDatabase(dbName, charset: charset, collation: collation);
  Future<bool> dropDatabase(String dbName) => _schemaMgr.dropDatabase(dbName);
  Future<Map<String, dynamic>?> getDatabaseProperties(String dbName) =>
      _schemaMgr.getDatabaseProperties(dbName);
  Future<String> getDatabaseSize(String dbName) =>
      _schemaMgr.getDatabaseSize(dbName);
  Future<String> getCreateDatabaseSql(String dbName) =>
      _schemaMgr.getCreateDatabaseSql(dbName);
  Future<List<String>> getCharsets() => _schemaMgr.getCharsets();
  Future<List<Map<String, String>>> getCollations({String? charset}) =>
      _schemaMgr.getCollations(charset: charset);
  Future<String> exportDatabaseStructure(String dbName) =>
      _schemaMgr.exportDatabaseStructure(dbName);

  // 表 DDL
  Future<bool> createTable(
    String tableName,
    List<DbColumn> columns, {
    String? comment,
    String? engine,
    Map<String, dynamic>? options,
  }) => _schemaMgr.createTable(
    tableName,
    columns,
    comment: comment,
    engine: engine,
    options: options,
  );
  Future<bool> dropTable(String tableName, {String? databaseName}) =>
      _schemaMgr.dropTable(tableName, databaseName: databaseName);
  Future<bool> renameTable(
    String oldName,
    String newName, {
    String? databaseName,
  }) => _schemaMgr.renameTable(oldName, newName, databaseName: databaseName);
  Future<bool> truncateTable(String tableName, {String? databaseName}) =>
      _schemaMgr.truncateTable(tableName, databaseName: databaseName);
  Future<List<Map<String, dynamic>>> getTableData(
    String tableName, {
    int limit = 100,
    int offset = 0,
    String? cursorColumn,
    dynamic cursorValue,
    String? databaseName,
  }) => _schemaMgr.getTableData(
    tableName,
    limit: limit,
    offset: offset,
    cursorColumn: cursorColumn,
    cursorValue: cursorValue,
    databaseName: databaseName,
  );
  Future<int> getTableRowCount(String tableName, {String? databaseName}) =>
      _schemaMgr.getTableRowCount(tableName, databaseName: databaseName);
  Future<int> getTableExactRowCount(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) => _schemaMgr.getTableExactRowCount(
    tableName,
    connectionId: connectionId,
    sessionId: sessionId,
    databaseName: databaseName,
  );
  Future<Map<String, dynamic>?> getTableProperties(
    String tableName, {
    String? connectionId,
    String? dbName,
  }) => _schemaMgr.getTableProperties(
    tableName,
    connectionId: connectionId,
    dbName: dbName,
  );
  Future<String> getCreateTableSql(
    String tableName, {
    String? connectionId,
    String? databaseName,
  }) => _schemaMgr.getCreateTableSql(
    tableName,
    connectionId: connectionId,
    databaseName: databaseName,
  );
  Future<List<DbIndex>> getTableIndexes(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) => _schemaMgr.getTableIndexes(
    tableName,
    connectionId: connectionId,
    sessionId: sessionId,
    databaseName: databaseName,
  );
  Future<List<ForeignKey>> getForeignKeys(
    String tableName, {
    String? connectionId,
    String? sessionId,
    String? databaseName,
  }) => _schemaMgr.getForeignKeys(
    tableName,
    connectionId: connectionId,
    sessionId: sessionId,
    databaseName: databaseName,
  );

  DatabaseType? getDatabaseType(String? connectionId) {
    final id = connectionId ?? _state.activeConnectionId;
    if (id == null) return null;
    return _state.servers[id]?.type;
  }

  // 列 DDL
  Future<bool> addColumn(
    String tableName,
    DbColumn column, {
    String? databaseName,
  }) => _schemaMgr.addColumn(tableName, column, databaseName: databaseName);
  Future<bool> dropColumn(
    String tableName,
    String columnName, {
    String? databaseName,
  }) =>
      _schemaMgr.dropColumn(tableName, columnName, databaseName: databaseName);
  Future<bool> modifyColumn(
    String tableName,
    String oldColumnName,
    DbColumn newColumn, {
    String? databaseName,
  }) => _schemaMgr.modifyColumn(
    tableName,
    oldColumnName,
    newColumn,
    databaseName: databaseName,
  );
  // renameColumn 公开 API — 连接 EditTableDialog 到适配器 RENAME COLUMN
  Future<bool> renameColumn(
    String tableName,
    String oldColumnName,
    String newColumnName, {
    String? databaseName,
  }) => _schemaMgr.renameColumn(
    tableName,
    oldColumnName,
    newColumnName,
    databaseName: databaseName,
  );

  // 索引 DDL
  Future<bool> createIndex(
    String tableName,
    String indexName,
    List<String> columns, {
    bool unique = false,
    String? databaseName,
  }) => _schemaMgr.createIndex(
    tableName,
    indexName,
    columns,
    unique: unique,
    databaseName: databaseName,
  );
  Future<bool> dropIndex(
    String tableName,
    String indexName, {
    String? databaseName,
  }) => _schemaMgr.dropIndex(tableName, indexName, databaseName: databaseName);

  // 导出
  Future<String> exportTableData(
    String tableName, {
    int limit = 1000,
    String? databaseName,
  }) => _schemaMgr.exportTableData(
    tableName,
    limit: limit,
    databaseName: databaseName,
  );

  // Redis 专用方法
  RedisAdapter? _getRedisAdapter(String connectionId) {
    final adapter = getAdapter(connectionId);
    if (adapter is RedisAdapter) return adapter;
    return null;
  }

  Future<Map<String, String>> getRedisServerInfo({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    return await adapter.getServerInfo();
  }

  Future<Map<String, String>> getRedisMemoryInfo({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    return await adapter.getMemoryInfo();
  }

  Future<Map<String, dynamic>> getRedisClientInfo({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    final info = await adapter.getServerInfo();
    final clients = <Map<String, String>>[];
    try {
      final clientList = await adapter.runCommand(['CLIENT', 'LIST']);
      if (clientList is String) {
        for (final line in clientList.split('\n')) {
          if (line.isEmpty) continue;
          final client = <String, String>{};
          for (final pair in line.split(' ')) {
            final kv = pair.split('=');
            if (kv.length == 2) client[kv[0]] = kv[1];
          }
          if (client.isNotEmpty) clients.add(client);
        }
      }
    } catch (_) {}
    return {
      'info': {
        'connected_clients': info['connected_clients'] ?? '0',
        'blocked_clients': info['blocked_clients'] ?? '0',
      },
      'clients': clients,
    };
  }

  Future<Map<String, String>> getRedisStats({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    final result = await adapter.runCommand(['INFO', 'stats']) as String;
    final stats = <String, String>{};
    for (final line in result.split('\n')) {
      if (line.contains(':') && !line.startsWith('#')) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          stats[parts[0]] = parts.sublist(1).join(':').trim();
        }
      }
    }
    return stats;
  }

  Future<Map<String, Map<String, dynamic>>> getRedisKeyspaceInfo({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    final result = await adapter.runCommand(['INFO', 'keyspace']) as String;
    final keyspace = <String, Map<String, dynamic>>{};
    for (final line in result.split('\n')) {
      if (line.startsWith('db')) {
        final dbParts = line.split(':');
        if (dbParts.length >= 2) {
          final dbName = dbParts[0];
          final meta = <String, dynamic>{};
          for (final pair in dbParts[1].split(',')) {
            final kv = pair.split('=');
            if (kv.length == 2) {
              final v = kv[1].trim();
              meta[kv[0]] = int.tryParse(v) ?? v;
            }
          }
          keyspace[dbName] = meta;
        }
      }
    }
    return keyspace;
  }

  Future<Map<String, String>> getRedisConfig({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    try {
      final result = await adapter.runCommand(['CONFIG', 'GET', '*']);
      final config = <String, String>{};
      if (result is List) {
        for (var i = 0; i < result.length - 1; i += 2) {
          config[result[i].toString()] = result[i + 1].toString();
        }
      }
      return config;
    } catch (_) {
      return {};
    }
  }

  // D1 — 复制信息(INFO replication)
  Future<Map<String, String>> getRedisReplicationInfo({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    try {
      return await adapter.getReplicationInfo();
    } catch (_) {
      return {};
    }
  }

  // B4 — CONFIG SET(走 runCommand 绕过 forbidden 校验)
  Future<bool> setRedisConfig({
    required String connectionId,
    required Map<String, String> keyValuePairs,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return false;
    try {
      final args = <String>['CONFIG', 'SET'];
      keyValuePairs.forEach((k, v) => args.addAll([k, v]));
      final result = await adapter.runCommand(args);
      return result == 'OK';
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getRedisSlowLog({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return [];
    try {
      final result = await adapter.runCommand(['SLOWLOG', 'GET', '20']);
      if (result is! List) return [];
      return result
          .map((entry) {
            if (entry is List && entry.length >= 4) {
              final command = entry[3] is List
                  ? (entry[3] as List).join(' ')
                  : entry[3].toString();
              return {
                'id': entry[0],
                'timestamp': entry[1],
                'duration': entry[2],
                'command': command,
              };
            }
            return <String, dynamic>{};
          })
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>> getRedisDatabaseKeyInfo(
    String dbName, {
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    try {
      // Keys 与 TTL 两个侧边栏节点共享同一份增量 SCAN 采样（adapter 页
      // 缓存，按 db+pattern）——后展开的节点只补扫缺口；TYPE 走批量
      // pipeline（≤2 请求）。UI 的「Scanned N keys (sampling)」与 hasMore
      // 语义不变。
      await adapter.useDatabase(dbName);
      final typeCount = <String, int>{};
      final typeSamples = <String, List<String>>{};
      final namespaceCount = <String, int>{};
      final namespaceSamples = <String, List<String>>{};

      final sample = await adapter.sampleKeys(limit: 500);
      final sampledKeys = sample.keys;

      final types = await adapter.getKeyTypes(sampledKeys);
      for (var i = 0; i < sampledKeys.length; i++) {
        final key = sampledKeys[i];

        // Namespace analysis (fast, no additional Redis call)
        final ns = key.contains(':') ? key.substring(0, key.indexOf(':')) : key;
        namespaceCount[ns] = (namespaceCount[ns] ?? 0) + 1;
        namespaceSamples.putIfAbsent(ns, () => []);
        if (namespaceSamples[ns]!.length < 5) {
          namespaceSamples[ns]!.add(key);
        }

        // Type analysis（批量 pipeline，不再逐 key 请求）
        final type = types[i];
        typeCount[type] = (typeCount[type] ?? 0) + 1;
        typeSamples.putIfAbsent(type, () => []);
        if (typeSamples[type]!.length < 5) {
          typeSamples[type]!.add(key);
        }
      }

      return {
        'typeCount': typeCount,
        'typeSamples': typeSamples,
        'namespaceCount': namespaceCount,
        'namespaceSamples': namespaceSamples,
        'totalScanned': sampledKeys.length,
        'hasMore': sample.hasMore,
      };
    } catch (_) {
      return {};
    }
  }

  /// Expiring Soon 节点（TTL 明细）：**采样口径**——Redis 无原生「按 TTL
  /// 查 key」，明细只能 SCAN+逐 key TTL（穷举不可扩展），故列表只承诺
  /// 「样本内快过期」；精确口径（keys/expires/avg_ttl，O(1) 零枚举）随
  /// 结果一并提供，供面板头部展示。采样与 Keys 节点共享同一份
  /// sampleKeys 页（limit 500）。
  Future<Map<String, dynamic>> getRedisTTLKeys(
    String dbName, {
    required String connectionId,
    int thresholdSeconds = 300,
  }) async {
    const empty = {
      'keys': <Map<String, dynamic>>[],
      'sampled': 0,
      'hasMoreSample': false,
      'totalKeys': 0,
      'expires': 0,
      'avgTtlMs': 0,
    };
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return empty;
    try {
      await adapter.useDatabase(dbName);
      final sample = await adapter.sampleKeys(limit: 500);
      final ttls = await adapter.getTTLs(sample.keys);
      final ttlKeys = <Map<String, dynamic>>[];
      for (var i = 0; i < sample.keys.length; i++) {
        final ttl = ttls[i];
        if (ttl > 0 && ttl <= thresholdSeconds) {
          ttlKeys.add({'key': sample.keys[i], 'ttl': ttl});
        }
      }
      ttlKeys.sort((a, b) => (a['ttl'] as int).compareTo(b['ttl'] as int));
      final agg = await adapter.getKeyspaceAggregate();
      return {
        'keys': ttlKeys,
        'sampled': sample.keys.length,
        'hasMoreSample': sample.hasMore,
        'totalKeys': agg.keys,
        'expires': agg.expires,
        'avgTtlMs': agg.avgTtlMs,
      };
    } catch (_) {
      return empty;
    }
  }

  /// DB Info 节点：精确聚合（DBSIZE 口径的 keys + INFO keyspace 的
  /// expires/avg_ttl，O(1) 零枚举）。旧实现从扁平 INFO 里取
  /// `info['avg_ttl']`——该字段实际嵌在 `dbN:` 行的值里永远取不到
  ///（Avg TTL 行从未渲染过的既有 bug），随 TTL 面板重定性一并修复。
  Future<Map<String, dynamic>> getRedisDBStats(
    String dbName, {
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return {};
    try {
      await adapter.useDatabase(dbName);
      final agg = await adapter.getKeyspaceAggregate();
      return {
        'keyCount': agg.keys,
        'dbName': dbName,
        'expires': agg.expires,
        'avgTtlMs': agg.avgTtlMs,
      };
    } catch (_) {
      return {};
    }
  }

  Future<List<String>> searchRedisKeys(
    String pattern, {
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return [];
    return await adapter.searchKeys(pattern);
  }

  Future<dynamic> evalRedisLua(
    String script, {
    required String connectionId,
    List<String> keys = const [],
    List<String> args = const [],
    String? sha,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) throw Exception('Redis adapter not found');
    // C1 — 透传 sha,启用 EVALSHA(B3 接线)
    return await adapter.evalLua(script, keys, args, sha: sha);
  }

  // C1 — 任意命令执行(走 runCommand,绕过 executeQuery 黑名单/解析)
  Future<dynamic> runRedisCommand({
    required String connectionId,
    required List<String> args,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) throw Exception('Redis adapter not found');
    return await adapter.runCommand(args);
  }

  Future<List<RedisFunctionLibrary>> getRedisFunctions({
    required String connectionId,
  }) async {
    final adapter = _getRedisAdapter(connectionId);
    if (adapter == null) return [];
    return await adapter.getRedisFunctions();
  }

  // ========== TDengine 特有操作 ==========

  TDengineAdapter? _getTDengineAdapter(String? connectionId) {
    if (connectionId == null) return null;
    final adapter = getAdapter(connectionId);
    if (adapter is TDengineAdapter) return adapter;
    return null;
  }

  Future<List<TdSuperTable>> getSuperTables({
    String? connectionId,
    String? databaseName,
  }) async {
    final adapter = _getTDengineAdapter(connectionId);
    if (adapter == null) return [];
    if (databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.getSuperTables();
  }

  Future<TdSuperTable?> getSuperTableDetail(
    String name, {
    String? connectionId,
    String? databaseName,
  }) async {
    final adapter = _getTDengineAdapter(connectionId);
    if (adapter == null) return null;
    if (databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.getSuperTableDetail(name);
  }

  Future<bool> dropSuperTable(
    String name, {
    String? connectionId,
    String? databaseName,
  }) async {
    final adapter = _getTDengineAdapter(connectionId);
    if (adapter == null) return false;
    if (databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.dropSuperTable(name);
  }

  Future<bool> dropSubTable(
    String name, {
    String? connectionId,
    String? databaseName,
  }) async {
    final adapter = _getTDengineAdapter(connectionId);
    if (adapter == null) return false;
    if (databaseName != null) {
      await adapter.useDatabase(databaseName);
    }
    return await adapter.dropSubTable(name);
  }
}

/// DDL 执行需要用户确认异常
class DdlConfirmationRequiredException implements Exception {
  final String sql;
  final ImpactReport impactReport;

  DdlConfirmationRequiredException({
    required this.sql,
    required this.impactReport,
  });

  @override
  String toString() {
    return 'DDL Confirmation Required: ${impactReport.riskLevel.displayName} risk detected for ${impactReport.ddlType}';
  }
}
