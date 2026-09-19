import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/database_models.dart';
import '../models/connection_event.dart';
import '../models/connection_failure.dart';
import '../services/database_service.dart';
import '../services/sqlite_alias_validator.dart';
import '../services/adapters/redis_adapter.dart';
import '../services/secure_storage_service.dart';
import '../services/server_connection.dart' show ServerConnection;
import '../services/connection_sync_service.dart';
import '../services/connection_mapping.dart' as mapping;
import '../services/ports/db_service_ports.dart';
import '../utils/app_logger.dart';

enum ConnectionImportConflictStrategy { skip, rename, overwrite }

/// ConnectionProvider - 专注连接管理
/// 职责：保存连接、连接/断开、切换连接、管理数据库列表
class ConnectionProvider extends ChangeNotifier {
  final DatabaseService _dbService;

  ConnectionProvider({DatabaseService? dbService})
    : _dbService = dbService ?? DatabaseService() {
    // 连接失败 UX 重构 T10 · 意外断连感知：订阅 dbService 连接事件流，
    // 维护每连接未处置失败（状态栏指示点 / 选择器失败态 / 树根状态点共用）。
    _eventSubscription = _dbService.events.listen(
      _onConnectionEvent,
      onError: (Object error, StackTrace stackTrace) {
        AppLogger.e(
          'ConnectionProvider',
          'Connection event stream error',
          error,
          stackTrace,
        );
      },
    );
  }

  /// C10 · port 层：连接语义（测试/注册/注销/连接态）统一经
  /// DbCapabilityPort 双形态路由——AdapterBacking = 现状本地直连，
  /// GatewayBacking = 网关（embedded 本地 server 与远程两形态行为一致）。
  /// UI 侧 AppProvider 门面签名不变。
  late final DbServicePorts _ports = DbServicePorts(
    adapterDbService: _dbService,
    connectionLookup: (id) =>
        _savedConnections.where((s) => s.id == id).firstOrNull,
  );

  /// port 层访问点（C10 连接语义；C14+ 侧边栏能力位/元数据经此消费）。
  DbServicePorts get ports => _ports;

  // 连接列表
  List<DbServer> _savedConnections = [];
  List<ConnectionGroup> _connectionGroups = [];

  // 当前连接状态
  DbServer? _currentServer;
  Database? _currentDatabase;
  List<String> _databases = [];
  bool _isConnecting = false;
  String? _errorMessage;

  // 连接失败 UX 重构 T3：最近一次连接失败的结构化描述（与 _errorMessage
  // 并行维护——后者为兼容保留，非连接路径仍在写）。
  ConnectionFailure? _lastConnectFailure;

  // 连接失败 UX 重构 T10：每连接未处置失败（connect 失败 / 意外断连）。
  // key = 连接 id；重试成功清除，acknowledgeFailure 处置清除。
  final Map<String, ConnectionFailure> _lastFailureByConnectionId = {};

  // T10 · 用户主动断开标记：dbService 事件流的 ConnectionDisconnected
  // 无法区分主动/意外，主动断开路径（disconnectConnection /
  // disconnectAllConnections / deleteConnection）先打标记，由事件处理器
  // 消费；无标记的断连按意外断连近似（精度说明见任务汇报）。
  final Set<String> _manualDisconnectIds = {};

  // T10 · 连接事件流订阅（dispose 时释放）。
  StreamSubscription<ConnectionEvent>? _eventSubscription;

  // 每个连接独立的数据库缓存
  final Map<String, List<String>> _connectionDatabases = {};
  final Map<String, List<String>> _connectionNonEmptyDatabases = {};
  final Map<String, Database?> _connectionCurrentDatabase = {};
  final Map<String, Map<String, Database>> _databaseCache = {};

  // 每个数据库的表分页状态缓存（按连接/数据库）
  final Map<String, Map<String, TablePaginationState>> _tablePaginationCache =
      {};

  // 是否显示空数据库（按连接）
  final Map<String, bool> _showEmptyDatabases = {};

  // 全局服务器信息缓存
  final Map<String, Map<String, dynamic>> _serverStatusCache = {};
  final Map<String, Map<String, dynamic>> _globalVariablesCache = {};
  final Map<String, List<Map<String, dynamic>>> _serverUsersCache = {};
  final Map<String, List<Map<String, dynamic>>> _processListCache = {};

  // T009 — Replication & engine status caches
  final Map<String, ReplicationStatus?> _replicationStatusCache = {};
  final Map<String, Map<String, dynamic>?> _engineStatusCache = {};
  final Map<String, Timer> _processListTimers = {};
  final Map<String, int> _processListIntervals =
      {}; // seconds, for UI highlight

  // Redis 信息缓存
  final Map<String, Map<String, String>> _redisServerInfoCache = {};
  final Map<String, Map<String, String>> _redisMemoryCache = {};
  final Map<String, Map<String, dynamic>> _redisClientCache = {};
  final Map<String, Map<String, String>> _redisStatsCache = {};
  final Map<String, Map<String, Map<String, dynamic>>> _redisKeyspaceCache = {};
  final Map<String, Map<String, String>> _redisConfigCache = {};
  // D1 — 复制信息缓存
  final Map<String, Map<String, String>> _redisReplicationCache = {};
  final Map<String, List<Map<String, dynamic>>> _redisSlowLogCache = {};
  final Map<String, Map<String, Map<String, dynamic>>> _redisDbKeyInfoCache =
      {};
  final Map<String, Map<String, Map<String, dynamic>>> _redisTTLKeysCache = {};
  final Map<String, Map<String, Map<String, dynamic>>> _redisDBStatsCache = {};

  // ==================== Getters ====================

  DatabaseService get dbService => _dbService;
  List<DbServer> get savedConnections => List.unmodifiable(_savedConnections);
  List<ConnectionGroup> get connectionGroups =>
      List.unmodifiable(_connectionGroups);
  List<String> get databases => List.unmodifiable(_databases);
  DbServer? get currentServer => _currentServer;
  Database? get currentDatabase => _currentDatabase;
  bool get isConnecting => _isConnecting;

  /// 最近一次连接失败的结构化描述；成功连接后为 null（T3）。
  ///
  /// 连接失败的展示与诊断请用本 getter（按 kind 分型呈现）；
  /// [errorMessage] 为兼容保留，新代码不要依赖其文本格式。
  ConnectionFailure? get lastConnectFailure => _lastConnectFailure;

  /// T10 · 单个连接的未处置连接失败（connect 失败 / 意外断连）；null = 无。
  ///
  /// 重试成功自动清除；[acknowledgeFailure] 用户处置清除。
  ConnectionFailure? lastFailureFor(String connectionId) =>
      _lastFailureByConnectionId[connectionId];

  /// T10 · 是否存在任一连接的未处置失败（状态栏指示点的显示条件）。
  bool get hasUnacknowledgedFailures => _lastFailureByConnectionId.isNotEmpty;

  /// T10 · 最新一条未处置失败（状态栏 tooltip「最新人话」的取值来源）。
  ConnectionFailure? get latestUnacknowledgedFailure {
    ConnectionFailure? latest;
    for (final failure in _lastFailureByConnectionId.values) {
      if (latest == null || failure.occurredAt.isAfter(latest.occurredAt)) {
        latest = failure;
      }
    }
    return latest;
  }

  /// T10 · 处置（清除）单个连接的失败条目（幂等：无条目时为 no-op）。
  void acknowledgeFailure(String connectionId) {
    if (_lastFailureByConnectionId.remove(connectionId) != null) {
      notifyListeners();
    }
  }

  /// T10 · 处置全部未处置失败（状态栏指示点点击时调用）。
  void acknowledgeAllFailures() {
    if (_lastFailureByConnectionId.isEmpty) return;
    _lastFailureByConnectionId.clear();
    notifyListeners();
  }

  /// T10 · 连接事件 → 失败条目维护。
  ///
  /// - ConnectionEstablished（重试/后台重连成功）→ 清除该连接失败条目；
  /// - ConnectionDisconnected → 有主动断开标记 = 用户主动断开（不产生
  ///   失败态，顺带幂等清残留条目）；无标记 = 意外断连 → 记录失败条目。
  void _onConnectionEvent(ConnectionEvent event) {
    switch (event) {
      case final ConnectionEstablished established:
        _manualDisconnectIds.remove(established.connectionId);
        if (_lastFailureByConnectionId.remove(established.connectionId) !=
            null) {
          notifyListeners();
        }
      case final ConnectionDisconnected disconnected:
        if (_manualDisconnectIds.remove(disconnected.connectionId)) {
          if (_lastFailureByConnectionId.remove(disconnected.connectionId) !=
              null) {
            notifyListeners();
          }
        } else {
          final server = disconnected.server;
          _lastFailureByConnectionId[disconnected.connectionId] =
              ConnectionFailure(
                kind: ConnectionFailureKind.unknown,
                errorCode: '',
                target: server == null ? null : '${server.host}:${server.port}',
                rawMessage: 'Connection lost unexpectedly',
                occurredAt: DateTime.now(),
              );
          notifyListeners();
        }
      default:
        break;
    }
  }

  /// 兼容保留的错误消息（非连接路径如保存/克隆/删除连接仍在写）。
  ///
  /// 连接失败请用 [lastConnectFailure]（结构化分型）；本 getter 为兼容
  /// 保留（app_provider 镜像与 AI 面板仍消费），不加 @Deprecated。
  String? get errorMessage => _errorMessage;
  int get activeConnectionCount => _dbService.connectionCount;
  List<String> get connectedIds => _dbService.connectedIds;

  /// 通过 ID 查找保存的服务器连接
  DbServer? getServerById(String? id) {
    if (id == null) return null;
    try {
      return _savedConnections.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  bool isConnectionConnecting(String connectionId) =>
      _dbService.isConnecting(connectionId);

  bool isConnectionActive(String connectionId) =>
      _dbService.isConnectionActive(connectionId);

  bool isConnectionConnected(String connectionId) =>
      _dbService.hasConnection(connectionId);

  List<String> getConnectionDatabases(String connectionId) {
    final allDbs = _connectionDatabases[connectionId] ?? [];
    final nonEmptyDbs = _connectionNonEmptyDatabases[connectionId] ?? [];

    // If showing empty databases or no non-empty data available, return all
    if (_showEmptyDatabases[connectionId] == true || nonEmptyDbs.isEmpty) {
      return allDbs;
    }

    // Otherwise return only non-empty databases
    return nonEmptyDbs;
  }

  bool isShowingEmptyDatabases(String connectionId) {
    return _showEmptyDatabases[connectionId] == true;
  }

  void toggleShowEmptyDatabases(String connectionId) {
    _showEmptyDatabases[connectionId] =
        !(_showEmptyDatabases[connectionId] ?? false);
    notifyListeners();
  }

  int getTotalDatabaseCount(String connectionId) {
    return _connectionDatabases[connectionId]?.length ?? 0;
  }

  int getNonEmptyDatabaseCount(String connectionId) {
    return _connectionNonEmptyDatabases[connectionId]?.length ?? 0;
  }

  Database? getConnectionCurrentDatabase(String connectionId) {
    return _connectionCurrentDatabase[connectionId];
  }

  /// 默认库选取：跳过引擎内部库（Doris `__internal_schema` 等——USE/操作
  /// 被 FE 以 1105 拒绝；SHOW DATABASES 的 `__` 前缀库恒排最前，旧的首库
  /// 选取会在 connect 存桩 + refresh 的 getDatabaseInfo 里 USE 它即炸）。
  /// 全为内部库时退回首库（保持有值语义）。
  static String _pickDefaultDatabase(List<String> dbs) {
    for (final db in dbs) {
      if (!db.startsWith('__')) return db;
    }
    return dbs.first;
  }

  Database? getCachedDatabase(String connectionId, String databaseName) {
    return _databaseCache[connectionId]?[databaseName];
  }

  // Replace cached database entry (used after per-schema lazy loading updates)
  void updateCachedDatabase(
    String connectionId,
    String databaseName,
    Database db,
  ) {
    _databaseCache[connectionId]?[databaseName] = db;
  }

  void invalidateDatabaseCache(String connectionId, String databaseName) {
    _databaseCache[connectionId]?.remove(databaseName);
    notifyListeners();
  }

  Map<String, dynamic>? getServerStatus(String connectionId) {
    return _serverStatusCache[connectionId];
  }

  Map<String, dynamic>? getGlobalVariables(String connectionId) {
    return _globalVariablesCache[connectionId];
  }

  List<Map<String, dynamic>>? getServerUsers(String connectionId) {
    return _serverUsersCache[connectionId];
  }

  List<Map<String, dynamic>>? getProcessList(String connectionId) {
    return _processListCache[connectionId];
  }

  // T009 — replication & engine getters
  ReplicationStatus? getReplicationStatus(String connectionId) =>
      _replicationStatusCache[connectionId];

  Map<String, dynamic>? getEngineStatus(String connectionId) =>
      _engineStatusCache[connectionId] ?? null;

  Future<Database?> loadDatabaseInfo(
    String connectionId,
    String databaseName, {
    bool forceRefresh = false,
    bool schemasOnly = false,
  }) async {
    // 用 ??= 原子地确保内层 map 存在，避免裸 `!`。
    final dbMap = _databaseCache[connectionId] ??= <String, Database>{};

    final cachedDb = dbMap[databaseName];
    if (cachedDb != null && !forceRefresh) {
      return cachedDb;
    }

    final needsSwitch = _currentServer?.id != connectionId;
    final originalServer = needsSwitch ? _currentServer : null;
    final originalDatabase = needsSwitch ? _currentDatabase : null;
    final originalDatabases = needsSwitch
        ? List<String>.from(_databases)
        : null;
    // 保存 dbService 层全局 active 连接；后台连接的元数据加载结束后必须归还，
    // 否则 active 被偷走会导致其他链路（changeDatabase/refreshDatabases）
    // 把查询路由到错误连接。
    final originalActiveId = needsSwitch ? _dbService.activeConnectionId : null;

    try {
      if (needsSwitch) {
        await switchToConnection(connectionId);
      }
      final dbInfo = await _dbService.getDatabaseInfo(
        databaseName,
        connectionId: connectionId,
        schemasOnly: schemasOnly,
      );
      // 两次 await 后 _databaseCache[connectionId] 可能被并发
      // remove（connect/refreshDatabases/_clearConnectionCaches），重新取/建内层 map 再写入，
      // 避免裸 `!` 崩溃。
      (_databaseCache[connectionId] ??= <String, Database>{})[databaseName] =
          dbInfo;

      if (needsSwitch && originalServer != null) {
        _currentServer = originalServer;
        _currentDatabase = originalDatabase;
        _databases = originalDatabases!;
      }
      _restoreActiveConnection(originalActiveId);

      notifyListeners();

      return dbInfo;
    } catch (e) {
      if (needsSwitch && originalServer != null) {
        _currentServer = originalServer;
        _currentDatabase = originalDatabase;
        _databases = originalDatabases!;
        notifyListeners();
      }
      _restoreActiveConnection(originalActiveId);
      return null;
    }
  }

  /// 归还 dbService 层全局 active 连接（loadDatabaseInfo 后台切换的配套恢复）。
  void _restoreActiveConnection(String? originalActiveId) {
    if (originalActiveId != null &&
        originalActiveId != _dbService.activeConnectionId &&
        _dbService.hasConnection(originalActiveId)) {
      _dbService.setActiveConnection(originalActiveId);
    }
  }

  Future<void> loadTablesPaginated(
    String connectionId,
    String databaseName, {
    int page = 1,
    int pageSize = 100,
    String? search,
    bool append = false,
  }) async {
    final cacheKey = '$connectionId::$databaseName';
    try {
      final dbInfo = await loadDatabaseInfo(connectionId, databaseName);
      final allTables = dbInfo?.tables ?? <DbTable>[];
      final filtered = search == null || search.isEmpty
          ? allTables
          : allTables
                .where(
                  (t) => t.name.toLowerCase().contains(search.toLowerCase()),
                )
                .toList();

      final total = filtered.length;
      final start = (page - 1) * pageSize;
      final end = start + pageSize > total ? total : start + pageSize;
      final pageTables = start < total
          ? filtered.sublist(start, end)
          : <DbTable>[];

      final current = _tablePaginationCache[connectionId]?[databaseName];
      final mergedTables = append && current != null
          ? [...current.tables, ...pageTables]
          : pageTables;

      _tablePaginationCache.putIfAbsent(connectionId, () => {});
      _tablePaginationCache[connectionId]![databaseName] = TablePaginationState(
        tables: mergedTables,
        page: page,
        pageSize: pageSize,
        total: total,
        search: search,
      );
      notifyListeners();
    } catch (e) {
      AppLogger.e(
        'ConnectionProvider',
        'Failed to load paginated tables for $cacheKey',
        e,
      );
    }
  }

  TablePaginationState? getTablePaginationState(
    String connectionId,
    String databaseName,
  ) {
    return _tablePaginationCache[connectionId]?[databaseName];
  }

  void setCurrentServer(DbServer? server) {
    if (_currentServer?.id != server?.id) {
      _currentServer = server;
      notifyListeners();
    }
  }

  void setCurrentDatabase(Database? database) {
    if (_currentDatabase?.name != database?.name) {
      _currentDatabase = database;
      notifyListeners();
    }
  }

  void setError(String? error) {
    _errorMessage = error;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void setIsConnecting(bool value) {
    _isConnecting = value;
    notifyListeners();
  }

  // ==================== 持久化 ====================

  Future<void> loadSavedConnections() async {
    final sw = Stopwatch()..start();
    void mark(String stage) => AppLogger.d(
      'ConnectionProvider',
      'loadSavedConnections:$stage ${sw.elapsedMilliseconds}ms',
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      mark('prefs');

      final connectionsJson = prefs.getString('saved_connections');
      if (connectionsJson != null) {
        try {
          final List<dynamic> list = jsonDecode(connectionsJson);
          _savedConnections = list
              .where((e) {
                final typeName = (e as Map<String, dynamic>)['type'] as String?;
                final isSupported =
                    typeName != null &&
                    DatabaseType.tryFromName(typeName) != null;
                if (!isSupported) {
                  AppLogger.w(
                    'ConnectionProvider',
                    'Skipping saved connection with unsupported type: $typeName',
                  );
                }
                return isSupported;
              })
              .map((e) => DbServer.fromJson(e as Map<String, dynamic>))
              .toList();

          // 从保险箱一次性读取所有密码/SSH 凭据。旧版单独存储的 key 会自动迁移到保险箱。
          final vault = await SecureStorageService.readCredentialsVault(
            _savedConnections.map((s) => s.id).toList(),
          );
          final passwords =
              (vault['passwords'] as Map<String, dynamic>?)
                  ?.cast<String, String>() ??
              <String, String>{};
          final sshVault =
              (vault['ssh'] as Map<String, dynamic>?)
                  ?.cast<String, Map<String, dynamic>>() ??
              <String, Map<String, dynamic>>{};

          for (var i = 0; i < _savedConnections.length; i++) {
            try {
              final id = _savedConnections[i].id;
              final password = passwords[id];
              if (password != null && password.isNotEmpty) {
                _savedConnections[i] = _savedConnections[i].copyWith(
                  password: password,
                );
              }

              // Load SSH credentials if SSH tunnel is enabled
              if (_savedConnections[i].useSshTunnel &&
                  sshVault.containsKey(id)) {
                final sshCreds = sshVault[id]!;
                _savedConnections[i] = _savedConnections[i].copyWith(
                  sshPassword: sshCreds['password'] as String?,
                  sshPrivateKey: sshCreds['privateKey'] as String?,
                  sshPassphrase: sshCreds['passphrase'] as String?,
                );
              }
            } catch (e) {
              AppLogger.e(
                'ConnectionProvider',
                'Failed to load credentials for ${_savedConnections[i].id}',
                e,
              );
            }
          }
        } catch (e) {
          AppLogger.e('ConnectionProvider', 'Failed to load connections', e);
          _savedConnections = [];
        }
      }

      final groupsJson = prefs.getString('connection_groups');
      if (groupsJson != null) {
        try {
          final List<dynamic> list = jsonDecode(groupsJson);
          _connectionGroups = list
              .map((e) => ConnectionGroup.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (e) {
          AppLogger.e('ConnectionProvider', 'Failed to load groups', e);
          _connectionGroups = [];
        }
      }

      // in embedded mode, merge any server-stored
      // connections that aren't yet in the local list. This makes connections
      // created in a previous embedded session reappear even if the local
      // prefs were cleared, and reconciles the server-id mapping. Credentials
      // are fetched lazily at connect time (the row only carries ciphertext).
      if (ServerConnection().isEmbeddedMode) {
        await _mergeServerConnections();
        mark('merge');
      }
    } catch (e) {
      AppLogger.e('ConnectionProvider', 'Failed to initialize', e);
    } finally {
      notifyListeners();
    }
  }

  Future<void> saveConnection(DbServer server) async {
    try {
      // C10 · port 连接语义：gateway-backed 类型先经网关注册（凭据入 server
      // vault，返回 serverConnId，本地留 id 镜像——c01 §5 凭据去向）。
      // AdapterBacking 为 no-op 返回原 id：本地 keychain + prefs 仍是主存储，
      // 本地保存流程不变。注册失败即保存失败（凭据未入 vault 时网关查询不可用）。
      final registeredId = await _ports
          .resolveFor(server.type)
          .persistConnection(server);
      if (registeredId != server.id) {
        await _rememberServerIdMapping(server.id, registeredId);
      }
      final existingIndex = _savedConnections.indexWhere(
        (s) => s.id == server.id,
      );
      if (existingIndex >= 0) {
        _savedConnections[existingIndex] = server;
      } else {
        _savedConnections.add(server);
      }

      // 把数据库密码和 SSH 凭据统一保存到保险箱
      try {
        await SecureStorageService.saveConnection(server);
      } on SecureStorageException catch (e) {
        AppLogger.w(
          'ConnectionProvider',
          'Failed to save credentials securely: $e',
        );
        _errorMessage = '凭据未能安全保存，请检查钥匙串访问权限：$e';
      }

      await _persistConnections();
      // feature 039 D3：若该连接已激活，原子刷新运行态 readOnly（侧栏开关实时生效，无需重连）。
      _dbService.toggleReadOnly(server.id, server.readOnly);
      // mirror SQL-library connections to the embedded
      // server so server-side features (data_sync/drift) can see them and they
      // persist across embedded-server restarts. Non-SQL types stay keychain-
      // only. Fire-and-forget: a mirror failure does NOT fail the save (the
      // connection is already safe in the local keychain + prefs).
      unawaited(_mirrorToServer(server));
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.e(
        'ConnectionProvider',
        'Failed to save connection: $e\n$stackTrace',
      );
      _errorMessage = '保存连接失败: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cloneConnection(DbServer server) async {
    try {
      final clonedServer = server.copyWith(
        id: 'conn_${DateTime.now().millisecondsSinceEpoch}',
        name: '${server.name} (副本)',
        connected: false,
        lastConnected: null,
      );
      _savedConnections.add(clonedServer);
      await _persistConnections();
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.e(
        'ConnectionProvider',
        'Failed to clone connection: $e\n$stackTrace',
      );
      _errorMessage = '克隆连接失败: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> importConnections(
    List<DbServer> connections, {
    required ConnectionImportConflictStrategy strategy,
  }) async {
    final batchPrefix = DateTime.now().millisecondsSinceEpoch;
    final existingNames = _savedConnections.map((c) => c.name).toSet();

    try {
      for (var i = 0; i < connections.length; i++) {
        final conn = connections[i];
        var newName = conn.name;

        if (existingNames.contains(newName)) {
          switch (strategy) {
            case ConnectionImportConflictStrategy.skip:
              continue;
            case ConnectionImportConflictStrategy.rename:
              newName = _makeUniqueName(newName, existingNames);
              existingNames.add(newName);
              break;
            case ConnectionImportConflictStrategy.overwrite:
              final existingIndex = _savedConnections.indexWhere(
                (c) => c.name == newName,
              );
              if (existingIndex >= 0) {
                final existing = _savedConnections[existingIndex];
                final existingId = existing.id;
                if (_dbService.hasConnection(existingId)) {
                  await _dbService.disconnect(connectionId: existingId);
                }
                await SecureStorageService.deleteConnection(existingId);
                _clearConnectionCaches(existingId);
                // Reuse existing ID so references in groups/history remain valid
                final imported = conn.copyWith(
                  id: existingId,
                  name: newName,
                  connected: false,
                  clearLastConnected: true,
                );
                await SecureStorageService.saveConnection(imported);
                _savedConnections[existingIndex] = imported;
                existingNames.add(newName);
                continue; // skip the default add at the bottom
              }
              break;
          }
        }

        final newId = 'conn_${batchPrefix}_$i';
        final imported = conn.copyWith(
          id: newId,
          name: newName,
          connected: false,
          clearLastConnected: true,
        );

        await SecureStorageService.saveConnection(imported);
        _savedConnections.add(imported);
        existingNames.add(newName);
      }

      await _persistConnections();
      notifyListeners();
    } catch (e, st) {
      AppLogger.e('ConnectionProvider', 'Import connections failed', e, st);
      // Secure-storage rollback is best-effort on import failure.
      await loadSavedConnections();
      rethrow;
    }
  }

  void _clearConnectionCaches(String connectionId) {
    _databaseCache.remove(connectionId);
    _connectionDatabases.remove(connectionId);
    _connectionNonEmptyDatabases.remove(connectionId);
    _connectionCurrentDatabase.remove(connectionId);
    _serverStatusCache.remove(connectionId);
    _globalVariablesCache.remove(connectionId);
    _serverUsersCache.remove(connectionId);
    _processListCache.remove(connectionId);
    _replicationStatusCache.remove(connectionId);
    _engineStatusCache.remove(connectionId);
    _processListTimers[connectionId]?.cancel();
    _processListTimers.remove(connectionId);
    _processListIntervals.remove(connectionId);
    _showEmptyDatabases.remove(connectionId);
    // Redis caches
    _redisServerInfoCache.remove(connectionId);
    _redisMemoryCache.remove(connectionId);
    _redisClientCache.remove(connectionId);
    _redisStatsCache.remove(connectionId);
    _redisKeyspaceCache.remove(connectionId);
    _redisConfigCache.remove(connectionId);
    _redisSlowLogCache.remove(connectionId);
    _redisDbKeyInfoCache.remove(connectionId);
    _redisTTLKeysCache.remove(connectionId);
    _redisDBStatsCache.remove(connectionId);
  }

  // 重名时最多尝试 1000 次派生唯一名称，防止理论上无限循环。
  static const int _maxRenameAttempts = 1000;

  String _makeUniqueName(String baseName, Set<String> existingNames) {
    var index = 1;
    var candidate = '$baseName-imported-$index';
    while (existingNames.contains(candidate)) {
      index++;
      if (index > _maxRenameAttempts) {
        throw StateError(
          'Cannot generate unique name for "$baseName" after $_maxRenameAttempts attempts',
        );
      }
      candidate = '$baseName-imported-$index';
    }
    return candidate;
  }

  Future<void> deleteConnection(String id) async {
    try {
      // T10 · 主动断开标记 + 失败条目随删除清除（防僵尸条目）。
      if (_dbService.hasConnection(id)) _manualDisconnectIds.add(id);
      _lastFailureByConnectionId.remove(id);
      if (_dbService.hasConnection(id)) {
        await _dbService.disconnect(connectionId: id);
      }
      // also delete the server mirror (best-effort).
      // The server id may differ from the local id; we look it up by the
      // local id via listConnections matching (the mirror stores local id in
      // `group_id` for exact reconciliation — see _mirrorToServer).
      final server = _savedConnections.where((s) => s.id == id).firstOrNull;
      if (server != null) unawaited(_deleteServerMirror(id));
      // C10 · port 连接语义：gateway-backed 类型同步注销网关注册表（凭据在
      // server vault，必须显式清理；AdapterBacking no-op）。best-effort，同旧
      // 镜像删除策略——失败只记日志，不阻断本地删除。
      if (server != null && DbServicePorts.isGatewayBacked(server.type)) {
        unawaited(_removeFromGatewayRegistry(server.type, id));
      }
      _savedConnections.removeWhere((s) => s.id == id);
      await SecureStorageService.deleteConnection(id);
      await _persistConnections();
      notifyListeners();
    } catch (e, stackTrace) {
      AppLogger.e(
        'ConnectionProvider',
        'Failed to delete connection: $e\n$stackTrace',
      );
      _errorMessage = '删除连接失败: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ── ADR-0003 S3 — embedded server connection mirroring ──
  //
  // Design: rather than a hard cutover from keychain → server (which would
  // require reconciling client/server ids across active connections), S3
  // *mirrors* SQL-library connections to the embedded server. The local
  // keychain + prefs remain the primary store; the server mirror makes the
  // connection visible to server-side features (data_sync/drift) and gives
  // embedded-mode persistence. The server row's `group_id` carries the local
  // client id so we can reconcile on edit/delete without id churn.

  /// True only in embedded mode AND for server-syncable (SQL) connections.
  /// C10: gateway-backed 类型走新网关注册表（persistConnection），不再叠加旧
  /// S3 镜像，防两套注册写同一张 id 映射表。
  bool _isEmbeddedAndSyncable(DbServer server) {
    final conn = ServerConnection();
    if (!conn.isEmbeddedMode) return false;
    if (DbServicePorts.isGatewayBacked(server.type)) return false;
    return mapping.isServerSyncable(server);
  }

  /// Mirror (create or replace) a connection on the embedded server.
  /// Fire-and-forget: failures are logged but never surface to the user (the
  /// local keychain copy is already the source of truth).
  Future<void> _mirrorToServer(DbServer server) async {
    if (!_isEmbeddedAndSyncable(server)) return;
    final password = server.password ?? '';
    try {
      final newId = await ConnectionSyncService.instance.replaceConnection(
        server,
        password,
      );
      if (newId != null && newId != server.id) {
        AppLogger.d(
          'ConnectionProvider',
          'mirrored connection ${server.id} → server $newId',
        );
        // Remember the mapping so a later edit/delete can target the right row.
        await _rememberServerIdMapping(server.id, newId);
      }
    } catch (e) {
      AppLogger.w('ConnectionProvider', 'server mirror failed: $e');
    }
  }

  Future<void> _deleteServerMirror(String localId) async {
    final conn = ServerConnection();
    if (!conn.isEmbeddedMode) return;
    final serverId = await _lookupServerIdMapping(localId);
    try {
      if (serverId != null) {
        await ConnectionSyncService.instance.deleteConnection(serverId);
      }
    } catch (e) {
      AppLogger.w('ConnectionProvider', 'server mirror delete failed: $e');
    } finally {
      await _rememberServerIdMapping(localId, null); // clear mapping
    }
  }

  /// C10：注销网关注册表（`DELETE /api/gw/connections/{serverConnId}`）。
  /// gateway-backed 类型专用——id 空间是 serverConnId（经映射表反查），注册表
  /// 幂等。失败不抛（本地连接已删，注册行成孤儿可由对账清理）。
  Future<void> _removeFromGatewayRegistry(
    DatabaseType type,
    String localId,
  ) async {
    try {
      final serverConnId = await _lookupServerIdMapping(localId) ?? localId;
      await _ports.resolveFor(type).removeConnection(serverConnId);
    } catch (e) {
      AppLogger.w('ConnectionProvider', 'gateway registry remove failed: $e');
    } finally {
      await _rememberServerIdMapping(localId, null); // clear mapping
    }
  }

  /// Persist the local-id → server-id mapping in SharedPreferences so it
  /// survives app restarts (the server row persists too). `null` clears it.
  static const _serverIdMapKey = 'connection_server_id_map';
  Future<void> _rememberServerIdMapping(
    String localId,
    String? serverId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_serverIdMapKey);
      final map = raw == null
          ? <String, String>{}
          : (jsonDecode(raw) as Map).cast<String, String>();
      if (serverId == null) {
        map.remove(localId);
      } else {
        map[localId] = serverId;
      }
      await prefs.setString(_serverIdMapKey, jsonEncode(map));
    } catch (e) {
      AppLogger.w('ConnectionProvider', 'failed to save server-id map: $e');
    }
  }

  Future<String?> _lookupServerIdMapping(String localId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_serverIdMapKey);
      if (raw == null) return null;
      final map = (jsonDecode(raw) as Map).cast<String, String>();
      return map[localId];
    } catch (_) {
      return null;
    }
  }

  /// U05 (#32): resolve the server-side connection id for a locally saved
  /// connection, for task payloads that the server validates against its own
  /// `database_connections` table (data_sync source/target).
  ///
  /// Lookup order:
  /// 1. the persisted local-id → server-id mapping (embedded mirror/merge);
  /// 2. a natural-key match (name + db_type + host, the same key
  ///    `_mergeServerConnections` uses) against the live server list — this
  ///    covers remote mode where the user registered the connection via the
  ///    Server-connections dialog and no mapping exists yet. A match is
  ///    persisted so later lookups skip the round-trip.
  ///
  /// Returns null when the connection has no server-side counterpart — the
  /// caller should refuse to submit and point the user at the management
  /// dialog instead of letting the server reject an opaque id.
  Future<String?> resolveServerConnectionId(String localId) async {
    final mapped = await _lookupServerIdMapping(localId);
    if (mapped != null) return mapped;
    final server = _savedConnections.where((s) => s.id == localId).firstOrNull;
    if (server == null) return null;
    try {
      final rows = await ConnectionSyncService.instance.listConnections();
      for (final row in rows) {
        if (row.name == server.name &&
            row.type == server.type &&
            row.host == server.host) {
          await _rememberServerIdMapping(localId, row.id);
          return row.id;
        }
      }
    } catch (e) {
      AppLogger.w('ConnectionProvider', 'server id resolution failed: $e');
    }
    return null;
  }

  /// Drop a stale local-id → server-id mapping (e.g. the server rejected the
  /// id with CONNECTION_NOT_FOUND because the row was deleted server-side);
  /// the next [resolveServerConnectionId] re-matches instead of reusing it.
  Future<void> forgetServerConnectionId(String localId) =>
      _rememberServerIdMapping(localId, null);

  /// Pull server-stored SQL connections into the local list.
  ///
  /// Match policy: a server row matches an existing local connection when
  /// `name + db_type + host` agree (a stable natural key). Unmatched server
  /// rows are imported as new local connections (id = server id); the local
  /// list keeps them so the user sees a unified view. Credentials are NOT
  /// fetched here — `connectToServer` does that on demand.
  // embedded-mode server→client merge.
  Future<void> _mergeServerConnections() async {
    try {
      final msw = Stopwatch()..start();
      final serverConns = await ConnectionSyncService.instance
          .listConnections();
      AppLogger.d(
        'ConnectionProvider',
        'merge:listConnections ${msw.elapsedMilliseconds}ms (${serverConns.length} rows)',
      );
      if (serverConns.isEmpty) return;
      bool changed = false;
      // 映射写回批量收集，循环结束后单次落盘——逐行写 SharedPreferences
      // 在 vault 累积数百行时是 O(n) 次全量读改写（实测 873 行 = 8.9s
      // 启动卡顿，T29 走查）。
      final mappingDelta = <String, String>{};
      for (final sc in serverConns) {
        final matches = _savedConnections.where(
          (local) =>
              local.name == sc.name &&
              local.type == sc.type &&
              local.host == sc.host,
        );
        if (matches.isEmpty) {
          // New server-side connection not yet local — import it. Give it a
          // fresh local id but remember the server id mapping.
          final localId =
              'conn_${DateTime.now().millisecondsSinceEpoch}_${sc.id.substring(0, 8)}';
          final imported = sc.copyWith(id: localId);
          _savedConnections.add(imported);
          mappingDelta[localId] = sc.id;
          changed = true;
        } else {
          // Already local — just record the mapping so connectToServer can
          // fetch credentials by server id.
          final local = matches.first;
          mappingDelta[local.id] = sc.id;
        }
      }
      if (mappingDelta.isNotEmpty) {
        await _rememberServerIdMappings(mappingDelta);
      }
      if (changed) {
        await _persistConnections();
        notifyListeners();
      }
    } catch (e) {
      AppLogger.w('ConnectionProvider', 'server connection merge failed: $e');
    }
  }

  /// [_rememberServerIdMapping] 的批量版：单次读改写落盘。
  Future<void> _rememberServerIdMappings(Map<String, String> delta) async {
    if (delta.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_serverIdMapKey);
      final map = raw == null
          ? <String, String>{}
          : (jsonDecode(raw) as Map).cast<String, String>();
      map.addAll(delta);
      await prefs.setString(_serverIdMapKey, jsonEncode(map));
    } catch (e) {
      AppLogger.w('ConnectionProvider', 'failed to save server-id map: $e');
    }
  }

  Future<void> _persistConnections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'saved_connections',
      jsonEncode(_savedConnections.map((e) => e.toJson()).toList()),
    );
    await prefs.setString(
      'connection_groups',
      jsonEncode(_connectionGroups.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> addConnectionGroup(ConnectionGroup group) async {
    _connectionGroups.add(group);
    await _persistConnections();
    notifyListeners();
  }

  Future<void> deleteConnectionGroup(String groupId) async {
    _connectionGroups.removeWhere((g) => g.id == groupId);
    for (var i = 0; i < _savedConnections.length; i++) {
      if (_savedConnections[i].groupId == groupId) {
        _savedConnections[i] = _savedConnections[i].copyWith(groupId: null);
      }
    }
    await _persistConnections();
    notifyListeners();
  }

  Future<void> moveConnectionToGroup(
    String connectionId,
    String? groupId,
  ) async {
    final index = _savedConnections.indexWhere((s) => s.id == connectionId);
    if (index >= 0) {
      final old = _savedConnections[index];
      // 直接创建新对象，避免 copyWith 的 ?? 运算符导致 null 无法设置的问题
      _savedConnections[index] = DbServer(
        id: old.id,
        name: old.name,
        type: old.type,
        host: old.host,
        port: old.port,
        username: old.username,
        password: old.password,
        database: old.database,
        connected: old.connected,
        useSSL: old.useSSL,
        timeoutSeconds: old.timeoutSeconds,
        autoReconnect: old.autoReconnect,
        charset: old.charset,
        groupId: groupId, // 这里可以正确设置为 null
        lastConnected: old.lastConnected,
        environment: old.environment,
        readOnly: old.readOnly,
        useSshTunnel: old.useSshTunnel,
        sshHost: old.sshHost,
        sshPort: old.sshPort,
        sshUsername: old.sshUsername,
        sshAuthMode: old.sshAuthMode,
        sshPassword: old.sshPassword,
        sshPrivateKey: old.sshPrivateKey,
        sshPassphrase: old.sshPassphrase,
        useTls: old.useTls,
        tlsInsecure: old.tlsInsecure,
      );
      await _persistConnections();
      notifyListeners();
    }
  }

  Future<void> renameConnectionGroup(String groupId, String newName) async {
    final index = _connectionGroups.indexWhere((g) => g.id == groupId);
    if (index >= 0) {
      _connectionGroups[index] = ConnectionGroup(
        id: groupId,
        name: newName,
        color: _connectionGroups[index].color,
        order: _connectionGroups[index].order,
      );
      await _persistConnections();
      notifyListeners();
    }
  }

  // ==================== 连接操作 ====================

  Future<bool> connectToServer(
    DbServer server, {
    bool switchToConnection = true,
  }) async {
    if (_dbService.isConnecting(server.id)) {
      AppLogger.d(
        'ConnectionProvider',
        'Connection ${server.id} is already connecting, skipping',
      );
      return false;
    }

    if (_dbService.hasConnection(server.id)) {
      AppLogger.d(
        'ConnectionProvider',
        'Connection ${server.id} already exists, switching to it',
      );
      if (switchToConnection) {
        final switched = await this.switchToConnection(server.id);
        return switched;
      }
      return true;
    }

    _isConnecting = true;
    notifyListeners();

    try {
      AppLogger.d(
        'ConnectionProvider',
        'Connecting to ${server.host}:${server.port}',
      );
      // in embedded mode, if the password is missing
      // (e.g. loaded from the server list which only carries ciphertext),
      // fetch plaintext credentials from the embedded server before opening
      // the local adapter connection. The local adapter still connects
      // directly; this just hydrates the secret.
      if (ServerConnection().isEmbeddedMode &&
          mapping.isServerSyncable(server) &&
          (server.password == null || server.password!.isEmpty)) {
        final serverId = await _lookupServerIdMapping(server.id) ?? server.id;
        try {
          final creds = await ConnectionSyncService.instance.fetchCredentials(
            serverId,
          );
          // Hydrate the in-memory server with plaintext for the adapter.
          final sshMode = creds.ssh?.authMode == 'privateKey'
              ? SshAuthMode.privateKey
              : (creds.ssh?.authMode == 'password'
                    ? SshAuthMode.password
                    : server.sshAuthMode);
          server = server.copyWith(
            password: creds.password.isNotEmpty ? creds.password : null,
            sshUsername: creds.ssh?.username ?? server.sshUsername,
            sshAuthMode: sshMode,
            sshPassword: creds.ssh?.password ?? server.sshPassword,
            sshPrivateKey: creds.ssh?.privateKey ?? server.sshPrivateKey,
            sshPassphrase: creds.ssh?.passphrase ?? server.sshPassphrase,
          );
        } catch (e) {
          AppLogger.w(
            'ConnectionProvider',
            'credential fetch failed; proceeding with local creds: $e',
          );
        }
      }
      final connected = await _dbService.connect(server);
      if (!connected) {
        throw Exception('数据库连接失败');
      }
      AppLogger.d('ConnectionProvider', 'Connected successfully');

      await Future.delayed(const Duration(milliseconds: 100));

      final newDatabases = await _dbService.getDatabases(
        connectionId: server.id,
      );
      AppLogger.d('ConnectionProvider', 'Got ${newDatabases.length} databases');

      // For Redis, also get non-empty databases
      List<String> nonEmptyDatabases = [];
      if (server.type == DatabaseType.redis) {
        try {
          final redisAdapter = _dbService.getAdapter(server.id);
          if (redisAdapter is RedisAdapter) {
            nonEmptyDatabases = await redisAdapter.getNonEmptyDatabases();
            AppLogger.d(
              'ConnectionProvider',
              'Got ${nonEmptyDatabases.length} non-empty databases',
            );
          }
        } catch (e) {
          AppLogger.d(
            'ConnectionProvider',
            'Failed to get non-empty databases: $e',
          );
        }
      }

      // Defer full database info loading to when the user expands the tree node.
      // Previously this eagerly loaded ALL schema/table metadata, freezing the UI on large DBs.
      // Now only the database name list is loaded here; per-schema objects load lazily.
      Database? newCurrentDatabase;
      if (newDatabases.isNotEmpty) {
        final defaultDb = server.database ?? _pickDefaultDatabase(newDatabases);
        // Create a lightweight stub — full metadata loads when user expands the DB node
        newCurrentDatabase = Database(
          name: defaultDb,
          tables: const [],
          views: const [],
          procedures: const [],
          functions: const [],
          events: const [],
          triggers: const [],
          schemas: const [],
        );
      }

      _connectionDatabases[server.id] = newDatabases;
      _connectionNonEmptyDatabases[server.id] = nonEmptyDatabases;
      _connectionCurrentDatabase[server.id] = newCurrentDatabase;
      // 清除该连接的数据库缓存，确保重新加载最新表结构
      _databaseCache.remove(server.id);

      if (switchToConnection) {
        _currentServer = _dbService.currentServer;
        _databases = newDatabases;
        _currentDatabase = newCurrentDatabase;
      }

      _isConnecting = false;
      _errorMessage = null;
      _lastConnectFailure = null;
      // T10 · 重试成功 → 清除该连接的未处置失败条目。
      _lastFailureByConnectionId.remove(server.id);
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.e('ConnectionProvider', 'Connection error', e);
      _isConnecting = false;
      _errorMessage = e.toString();
      // 连接失败 UX 重构 T3：typed failure 直接取异常携带的结构；非 typed
      // （如取消路径的「数据库连接失败」）构造 unknown 兜底，保证
      // lastConnectFailure 与失败结果同生共死。
      final failure = e is AdapterConnectException
          ? e.failure
          : ConnectionFailure(
              kind: ConnectionFailureKind.unknown,
              errorCode: '',
              target: '${server.host}:${server.port}',
              rawMessage: e.toString(),
              occurredAt: DateTime.now(),
            );
      _lastConnectFailure = failure;
      // T10 · 与既有 _lastConnectFailure 一并写入每连接失败 map。
      _lastFailureByConnectionId[server.id] = failure;
      notifyListeners();
      return false;
    }
  }

  // ==================== SQLite 文件打开 ====================
  // SQLite 零摩擦打开（拖拽 / Open SQLite File 按钮）。

  /// 受支持的 SQLite 文件扩展名（与 sqlite-connection-plugin 表单一致）。
  static const List<String> sqliteFileExtensions = [
    'db',
    'sqlite',
    'sqlite3',
    'db3',
  ];

  /// 规范化 SQLite 文件路径用于去重比对：统一为正斜杠 + 小写盘符。
  // DEFENSIVE-NOTE: 非完整 canonical 化（不解析符号链接 / 短文件名）。
  // OS 的文件选择器与拖放返回一致的绝对路径，此处覆盖大小写与分隔符差异。
  static String normalizeSqlitePath(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    if (normalized.length >= 2 && normalized[1] == ':') {
      normalized = normalized[0].toLowerCase() + normalized.substring(1);
    }
    return normalized;
  }

  /// 判断路径是否具有受支持的 SQLite 文件扩展名。
  static bool isSqliteFilePath(String path) {
    final lower = path.toLowerCase();
    return sqliteFileExtensions.any((ext) => lower.endsWith('.$ext'));
  }

  /// 从一组路径中返回第一个受支持的 SQLite 文件路径；无则返回 null。
  // 拖拽入口的路径筛选（纯函数，规避 platform channel 单测）。
  static String? firstSqlitePath(Iterable<String> paths) {
    for (final p in paths) {
      if (isSqliteFilePath(p)) {
        return p;
      }
    }
    return null;
  }

  /// 从文件路径派生显示名（去扩展名的文件名）。
  static String sqliteDisplayName(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  /// 为 SQLite 文件构造一个新的 [DbServer]（id 规则同连接表单模块）。
  static DbServer buildSqliteServer(String path, {required DateTime now}) {
    return DbServer(
      id: 'sqlite_${now.millisecondsSinceEpoch}',
      name: sqliteDisplayName(path),
      type: DatabaseType.sqlite,
      host: path,
      port: 0,
      username: null,
      password: null,
      database: null,
      useSSL: false,
      timeoutSeconds: 30,
      autoReconnect: false,
      lastConnected: now,
    );
  }

  /// 在 [all] 中查找 host（规范化后）匹配 [normalizedPath] 的 SQLite 连接。
  static DbServer? findExistingSqlite(
    Iterable<DbServer> all,
    String normalizedPath,
  ) {
    for (final server in all) {
      if (server.type == DatabaseType.sqlite &&
          normalizeSqlitePath(server.host) == normalizedPath) {
        return server;
      }
    }
    return null;
  }

  /// 将 [all] 中的 SQLite 连接按 [DbServer.lastConnected] 降序排序（最近在前），
  /// null 排末尾，最多返回 [limit] 条。结果不可变。
  static List<DbServer> sortRecentSqlite(
    Iterable<DbServer> all, {
    int limit = 8,
  }) {
    final files = all.where((s) => s.type == DatabaseType.sqlite).toList()
      ..sort((a, b) {
        final la = a.lastConnected;
        final lb = b.lastConnected;
        if (la == null && lb == null) {
          return 0;
        } else if (la == null) {
          return 1;
        } else if (lb == null) {
          return -1;
        }
        return lb.compareTo(la);
      });
    final capped = files.length > limit ? files.sublist(0, limit) : files;
    return List.unmodifiable(capped);
  }

  /// 最近打开的 SQLite 文件（最多 8 条，最近在前）。
  List<DbServer> get recentSqliteFiles => sortRecentSqlite(_savedConnections);

  /// 通过文件路径打开 SQLite 数据库：复用或新建保存的连接，再连接。
  /// 供拖拽打开与「Open SQLite File…」按钮调用；成功返回 true。
  Future<bool> openSqliteFile(
    String path, {
    bool switchToConnection = true,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty || !isSqliteFilePath(trimmed)) {
      final message = 'Not a supported SQLite file: $path';
      _errorMessage = message;
      // T3：与 _errorMessage 同步写结构化失败（打开前置校验失败属
      // unknown 型，无 target）。
      _lastConnectFailure = ConnectionFailure(
        kind: ConnectionFailureKind.unknown,
        errorCode: '',
        rawMessage: message,
        occurredAt: DateTime.now(),
      );
      AppLogger.w('ConnectionProvider', message);
      notifyListeners();
      return false;
    }

    try {
      final now = DateTime.now();
      final normalized = normalizeSqlitePath(trimmed);
      final existing = findExistingSqlite(_savedConnections, normalized);
      final server = existing != null
          ? existing.copyWith(lastConnected: now)
          : buildSqliteServer(trimmed, now: now);

      // 复用 / 新建保存连接并持久化（含 lastConnected 更新）。
      await saveConnection(server);

      return await connectToServer(
        server,
        switchToConnection: switchToConnection,
      );
    } catch (e) {
      AppLogger.e('ConnectionProvider', 'openSqliteFile failed for "$path"', e);
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// 切换到指定连接，返回是否成功
  /// 如果底层连接已断开（半开连接），会自动清理状态并返回 false
  Future<bool> switchToConnection(String connectionId) async {
    if (!_dbService.hasConnection(connectionId)) return false;

    _dbService.setActiveConnection(connectionId);

    // 验证连接活性：底层连接可能已断开但 hasConnection 仍返回 true（半开连接）
    try {
      // 尝试获取数据库列表来验证连接是否真正可用。
      // 显式传 connectionId，避免 await 期间全局 active 被并发链路
      // 偷走后把查询路由到错误连接
      final dbs = await _dbService.getDatabases(connectionId: connectionId);
      if (dbs.isEmpty) {
        // 空结果可能是正常的（如权限限制），也可能是连接已断开
        // 通过检查服务器对象是否存在来区分
        final server = _dbService.currentServer;
        if (server == null) {
          // 服务器对象已丢失，连接不可用
          AppLogger.w('ConnectionProvider', '切换连接时服务器对象丢失: $connectionId');
          await _dbService.disconnect(connectionId: connectionId);
          _currentServer = null;
          _databases = [];
          _currentDatabase = null;
          notifyListeners();
          return false;
        }
      }
    } catch (e) {
      // 切库期间（PG useDatabase 重连）getDatabases 可能命中正在关闭的旧连接而失败。
      // 这不是真正的连接失活——不 disconnect，保留连接让后续查询重试。
      // （与 keep-alive 的 isSwitchingDatabase guard 同理。）
      final adapter = _dbService.getAdapter(connectionId);
      if (adapter != null && adapter.isSwitchingDatabase) {
        AppLogger.w('ConnectionProvider', '连接活性验证失败（切库中，跳过 disconnect）: $e');
      } else {
        AppLogger.w('ConnectionProvider', '连接活性验证失败: $e');
        await _dbService.disconnect(connectionId: connectionId);
        _currentServer = null;
        _databases = [];
        _currentDatabase = null;
        notifyListeners();
      }
      return false;
    }

    _currentServer = _dbService.currentServer;

    if (_connectionDatabases.containsKey(connectionId)) {
      _databases = _connectionDatabases[connectionId]!;
      _currentDatabase = _connectionCurrentDatabase[connectionId];
    } else {
      _databases = await _dbService.getDatabases(connectionId: connectionId);
      _connectionDatabases[connectionId] = _databases;
      if (_databases.isNotEmpty) {
        _currentDatabase = await _dbService.getDatabaseInfo(
          _databases.first,
          connectionId: connectionId,
        );
        _connectionCurrentDatabase[connectionId] = _currentDatabase;
      }
    }

    notifyListeners();
    return true;
  }

  Future<void> disconnectConnection({String? connectionId}) async {
    final id = connectionId ?? _currentServer?.id;
    if (id == null) return;

    // T10 · 主动断开标记：仅在有活跃底层连接时打（disconnect 早退不发
    // 事件，避免标记泄漏误吞后续意外断连判定）。
    if (_dbService.hasConnection(id)) _manualDisconnectIds.add(id);

    try {
      await _dbService.disconnect(connectionId: id);
    } catch (e) {
      AppLogger.e('ConnectionProvider', '断开连接失败: $e');
    }

    // 清除该连接的所有缓存，确保下次连接时重新加载
    _databaseCache.remove(id);
    _connectionDatabases.remove(id);
    _connectionNonEmptyDatabases.remove(id);
    _connectionCurrentDatabase.remove(id);
    _serverStatusCache.remove(id);
    _globalVariablesCache.remove(id);
    _serverUsersCache.remove(id);
    _processListCache.remove(id);
    _showEmptyDatabases.remove(id);
    // Redis 缓存
    _redisServerInfoCache.remove(id);
    _redisMemoryCache.remove(id);
    _redisClientCache.remove(id);
    _redisStatsCache.remove(id);
    _redisKeyspaceCache.remove(id);
    _redisConfigCache.remove(id);
    _redisSlowLogCache.remove(id);
    _redisDbKeyInfoCache.remove(id);
    _redisTTLKeysCache.remove(id);
    _redisDBStatsCache.remove(id);

    if (connectionId == null || connectionId == _currentServer?.id) {
      try {
        final remainingConnectionIds = _dbService.connectedIds;
        if (remainingConnectionIds.isNotEmpty) {
          await switchToConnection(remainingConnectionIds.first);
        } else {
          _currentServer = null;
          _currentDatabase = null;
          _databases = [];
        }
      } catch (e) {
        AppLogger.e('ConnectionProvider', '切换剩余连接失败: $e');
        _currentServer = null;
        _currentDatabase = null;
        _databases = [];
      }
    }

    notifyListeners();
  }

  Future<void> disconnectAllConnections() async {
    // T10 · 全部标记为用户主动断开（逐连接事件由事件处理器消费）。
    _manualDisconnectIds.addAll(_dbService.connectedIds);
    await _dbService.disconnectAll();
    _currentServer = null;
    _currentDatabase = null;
    _databases = [];
    // 清除所有缓存
    _databaseCache.clear();
    _connectionDatabases.clear();
    _connectionNonEmptyDatabases.clear();
    _connectionCurrentDatabase.clear();
    _serverStatusCache.clear();
    _globalVariablesCache.clear();
    _serverUsersCache.clear();
    _processListCache.clear();
    _showEmptyDatabases.clear();
    // Redis 缓存
    _redisServerInfoCache.clear();
    _redisMemoryCache.clear();
    _redisClientCache.clear();
    _redisStatsCache.clear();
    _redisKeyspaceCache.clear();
    _redisConfigCache.clear();
    _redisSlowLogCache.clear();
    _redisDbKeyInfoCache.clear();
    _redisTTLKeysCache.clear();
    _redisDBStatsCache.clear();
    notifyListeners();
  }

  Future<void> changeDatabase(String dbName, {String? connectionId}) async {
    // 显式解析目标连接并全程传递，禁止静默回退到全局 active 连接——
    // 侧边栏点击的库节点所属连接才是目标
    final targetConnectionId = connectionId ?? _currentServer?.id;
    try {
      _currentDatabase = await _dbService.getDatabaseInfo(
        dbName,
        connectionId: targetConnectionId,
      );
      if (targetConnectionId != null) {
        _connectionCurrentDatabase[targetConnectionId] = _currentDatabase;
        if (_currentServer?.id == targetConnectionId &&
            _dbService.currentServer?.id == targetConnectionId) {
          _currentServer = _dbService.currentServer;
        }
      }
      // T017 — update cache to prevent stale table data after DDL operations
      if (_currentDatabase != null && targetConnectionId != null) {
        _databaseCache[targetConnectionId] ??= {};
        _databaseCache[targetConnectionId]![dbName] = _currentDatabase!;
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// spec 050：附加一个 SQLite 数据库文件到指定连接（ATTACH）。
  ///
  /// 流程：alias 校验 → 调 dbService.attachDatabase → 成功后刷新 getDatabases 缓存。
  /// [path] 文件绝对路径；[alias] 附加名。
  ///
  /// 返回 `(success, errorKey)`：
  /// - 成功：`(true, null)`，缓存已刷新（getConnectionDatabases 即时反映）。
  /// - 失败：`(false, errorKey)`，errorKey 是本地化错误 key（见 SqliteAliasValidator）
  ///   或 null（表示底层抛错，错误信息用 e.toString()，由 UI 层直接显示）。
  Future<({bool success, String? errorKey, String? errorDetail})>
  attachDatabase(String connectionId, String path, String alias) async {
    // 前置 alias 校验（UI 层应已校验，这里双保险）。
    final existing = _connectionDatabases[connectionId] ?? const [];
    final errKey = SqliteAliasValidator.validate(alias, existing: existing);
    if (errKey != null) {
      return (success: false, errorKey: errKey, errorDetail: null);
    }
    try {
      await _dbService.attachDatabase(connectionId, path, alias);
      // 刷新数据库列表缓存，让侧边栏树即时反映新附加库。
      await refreshDatabases(connectionId: connectionId);
      return (success: true, errorKey: null, errorDetail: null);
    } catch (e) {
      AppLogger.e('ConnectionProvider', 'ATTACH 失败: $alias ($path)', e);
      return (success: false, errorKey: null, errorDetail: e.toString());
    }
  }

  /// spec 050：分离一个已附加的 SQLite 数据库（DETACH）。
  ///
  /// 成功后清理该 alias 的 Database 缓存 + 刷新 getDatabases 缓存。
  Future<({bool success, String? errorDetail})> detachDatabase(
    String connectionId,
    String alias,
  ) async {
    try {
      await _dbService.detachDatabase(connectionId, alias);
      // 清理该 alias 的 Database 缓存（避免悬空引用）。
      _databaseCache[connectionId]?.remove(alias);
      // 刷新数据库列表缓存。
      await refreshDatabases(connectionId: connectionId);
      return (success: true, errorDetail: null);
    } catch (e) {
      AppLogger.e('ConnectionProvider', 'DETACH 失败: $alias', e);
      return (success: false, errorDetail: e.toString());
    }
  }

  Future<void> refreshDatabases({String? connectionId}) async {
    try {
      final targetConnectionId = connectionId ?? _currentServer?.id;
      if (targetConnectionId == null) return;

      // T024 — guard against rapid concurrent calls; sequential calls
      // (drop→recreate via user interaction) are handled correctly by fresh fetch each time
      final dbs = await _dbService.getDatabases(
        connectionId: targetConnectionId,
      );

      // Clear cache AFTER successful fetch — preserves cache on failure (FR-005)
      _databaseCache.remove(targetConnectionId);
      _connectionDatabases[targetConnectionId] = dbs;

      if (targetConnectionId == _currentServer?.id) {
        _databases = dbs;
        if (_databases.isNotEmpty && _currentDatabase == null) {
          // 本分支三处 getDatabaseInfo 均显式传 targetConnectionId，避免落到全局 active
          _currentDatabase = await _dbService.getDatabaseInfo(
            _pickDefaultDatabase(_databases),
            connectionId: targetConnectionId,
          );
          // Reinitialize per-connection cache map before storing (fixes null-aware no-op)
          _databaseCache[targetConnectionId] ??= {};
          _databaseCache[targetConnectionId]![_currentDatabase!.name] =
              _currentDatabase!;
        } else if (_currentDatabase != null) {
          final dbName = _currentDatabase!.name;
          if (_databases.contains(dbName)) {
            // Refresh current database info (tables, views, etc.)
            _currentDatabase = await _dbService.getDatabaseInfo(
              dbName,
              connectionId: targetConnectionId,
            );
            // Ensure cache map exists before storing (fixes null-aware no-op)
            _databaseCache[targetConnectionId] ??= {};
            _databaseCache[targetConnectionId]![dbName] = _currentDatabase!;
          } else {
            // Current database no longer exists (e.g., was dropped)
            _currentDatabase = null;
            // T023 — FR-007: fall back to first available database if any remain
            if (_databases.isNotEmpty) {
              _currentDatabase = await _dbService.getDatabaseInfo(
                _pickDefaultDatabase(_databases),
                connectionId: targetConnectionId,
              );
              _databaseCache[targetConnectionId] ??= {};
              _databaseCache[targetConnectionId]![_databases.first] =
                  _currentDatabase!;
            }
          }
        }
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<String?> testConnection(DbServer server) async {
    // C10：经 port 双形态——AdapterBacking = 现状本地直连（SSH 隧道特判与
    // mysql/doris 快路径都在 DatabaseService 内保留）；GatewayBacking = 远程
    // POST /api/gw/connections/test（测试即远程调用）。null=成功语义保持。
    final result = await _ports.resolveFor(server.type).testConnection(server);
    return result.ok ? null : (result.error ?? 'connection test failed');
  }

  // ==================== 跨连接操作 ====================

  Future<T> withConnection<T>(
    String connectionId,
    String? databaseName,
    Future<T> Function() action,
  ) async {
    final originalServer = _currentServer;
    final originalDatabase = _currentDatabase;
    final originalDatabases = List<String>.from(_databases);
    final originalConnectionId = _dbService.activeConnectionId;
    final originalDbName = originalDatabase?.name;

    try {
      if (connectionId != originalConnectionId) {
        _dbService.setActiveConnection(connectionId);
        _currentServer = _savedConnections.firstWhere(
          (s) => s.id == connectionId,
          orElse: () =>
              _currentServer ?? (throw StateError('No current server')),
        );
        _databases = _connectionDatabases[connectionId] ?? [];
      }

      if (databaseName != null && databaseName != _currentDatabase?.name) {
        _currentDatabase = await _dbService.getDatabaseInfo(
          databaseName,
          connectionId: connectionId,
        );
      }

      notifyListeners();
      return await action();
    } finally {
      if (originalConnectionId != null &&
          originalConnectionId != _dbService.activeConnectionId) {
        _dbService.setActiveConnection(originalConnectionId);
      }
      if (originalDbName != null && originalConnectionId != null) {
        try {
          await _dbService.useDatabase(
            originalDbName,
            connectionId: originalConnectionId,
          );
        } catch (e) {
          // 忽略恢复数据库时的错误
        }
      }
      _currentServer = originalServer;
      _currentDatabase = originalDatabase;
      _databases = originalDatabases;
      notifyListeners();
    }
  }

  // ==================== 全局服务器信息加载 ====================

  Future<void> loadServerStatus(String connectionId) async {
    try {
      final status = await _dbService.getServerStatus(
        connectionId: connectionId,
      );
      _serverStatusCache[connectionId] = status;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载服务器状态失败', e);
    }
  }

  Future<void> loadGlobalVariables(String connectionId) async {
    try {
      final variables = await _dbService.getGlobalVariables(
        connectionId: connectionId,
      );
      _globalVariablesCache[connectionId] = variables;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载全局变量失败', e);
    }
  }

  Future<void> loadServerUsers(String connectionId) async {
    try {
      final users = await _dbService.getServerUsers(connectionId: connectionId);
      _serverUsersCache[connectionId] = users;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载用户列表失败', e);
    }
  }

  Future<void> loadProcessList(String connectionId) async {
    try {
      final processes = await _dbService.getProcessList(
        connectionId: connectionId,
      );
      _processListCache[connectionId] = processes;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载进程列表失败', e);
    }
  }

  // T009 — killProcess
  Future<bool> killProcess(String connectionId, int processId) async {
    try {
      final success = await _dbService.killProcess(
        processId,
        connectionId: connectionId,
      );
      if (success) {
        await loadProcessList(connectionId);
      }
      return success;
    } catch (e) {
      AppLogger.e('ConnectionProvider', 'Kill process failed', e);
      return false;
    }
  }

  // T009 — replication status loading
  Future<void> loadReplicationStatus(String connectionId) async {
    try {
      final status = await _dbService.getReplicationStatus(
        connectionId: connectionId,
      );
      _replicationStatusCache[connectionId] = status;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', 'Load replication status failed', e);
    }
  }

  // T009 — engine status loading
  Future<void> loadEngineStatus(String connectionId) async {
    try {
      final status = await _dbService.getEngineStatus(
        connectionId: connectionId,
      );
      _engineStatusCache[connectionId] = status;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', 'Load engine status failed', e);
    }
  }

  // T009 — process list auto-refresh timer management
  int? getProcessListAutoRefreshInterval(String connectionId) =>
      _processListIntervals[connectionId];

  void startProcessListAutoRefresh(
    String connectionId, {
    Duration interval = const Duration(seconds: 10),
  }) {
    stopProcessListAutoRefresh(connectionId);
    final secs = interval.inSeconds;
    _processListIntervals[connectionId] = secs;
    // T002 — notify listeners immediately so UI shows selection feedback
    // without waiting for the first timer tick; also trigger an immediate fetch
    notifyListeners();
    unawaited(loadProcessList(connectionId));
    _processListTimers[connectionId] = Timer.periodic(interval, (_) {
      loadProcessList(connectionId);
    });
  }

  void stopProcessListAutoRefresh(String connectionId) {
    _processListTimers[connectionId]?.cancel();
    _processListTimers.remove(connectionId);
    _processListIntervals.remove(connectionId);
    // T001 — notify listeners so UI updates immediately on interval change
    notifyListeners();
  }

  void clearGlobalCache(String connectionId) {
    _serverStatusCache.remove(connectionId);
    _globalVariablesCache.remove(connectionId);
    _serverUsersCache.remove(connectionId);
    _processListCache.remove(connectionId);
    _redisServerInfoCache.remove(connectionId);
    _redisMemoryCache.remove(connectionId);
    _redisClientCache.remove(connectionId);
    _redisStatsCache.remove(connectionId);
    _redisKeyspaceCache.remove(connectionId);
    _redisConfigCache.remove(connectionId);
    _redisSlowLogCache.remove(connectionId);
    _redisDbKeyInfoCache.remove(connectionId);
    _redisTTLKeysCache.remove(connectionId);
    _redisDBStatsCache.remove(connectionId);
    notifyListeners();
  }

  // ==================== Redis 信息加载 ====================

  Map<String, String>? getRedisServerInfo(String connectionId) =>
      _redisServerInfoCache[connectionId];

  Map<String, String>? getRedisMemoryInfo(String connectionId) =>
      _redisMemoryCache[connectionId];

  Map<String, dynamic>? getRedisClientInfo(String connectionId) =>
      _redisClientCache[connectionId];

  Map<String, String>? getRedisStats(String connectionId) =>
      _redisStatsCache[connectionId];

  // D1 — 复制信息
  Map<String, String>? getRedisReplicationInfo(String connectionId) =>
      _redisReplicationCache[connectionId];

  Map<String, Map<String, dynamic>>? getRedisKeyspaceInfo(
    String connectionId,
  ) => _redisKeyspaceCache[connectionId];

  Map<String, String>? getRedisConfig(String connectionId) =>
      _redisConfigCache[connectionId];

  List<Map<String, dynamic>>? getRedisSlowLog(String connectionId) =>
      _redisSlowLogCache[connectionId];

  Map<String, dynamic>? getRedisDatabaseKeyInfo(
    String connectionId,
    String dbName,
  ) => _redisDbKeyInfoCache[connectionId]?[dbName];

  Map<String, dynamic>? getRedisTTLKeys(String connectionId, String dbName) =>
      _redisTTLKeysCache[connectionId]?[dbName];

  Map<String, dynamic>? getRedisDBStats(String connectionId, String dbName) =>
      _redisDBStatsCache[connectionId]?[dbName];

  Future<void> loadRedisServerInfo(String connectionId) async {
    try {
      final info = await _dbService.getRedisServerInfo(
        connectionId: connectionId,
      );
      _redisServerInfoCache[connectionId] = info;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 服务器信息失败', e);
    }
  }

  Future<void> loadRedisMemoryInfo(String connectionId) async {
    try {
      final info = await _dbService.getRedisMemoryInfo(
        connectionId: connectionId,
      );
      _redisMemoryCache[connectionId] = info;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 内存信息失败', e);
    }
  }

  Future<void> loadRedisClientInfo(String connectionId) async {
    try {
      final info = await _dbService.getRedisClientInfo(
        connectionId: connectionId,
      );
      _redisClientCache[connectionId] = info;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 客户端信息失败', e);
    }
  }

  Future<void> loadRedisStats(String connectionId) async {
    try {
      final stats = await _dbService.getRedisStats(connectionId: connectionId);
      _redisStatsCache[connectionId] = stats;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 统计信息失败', e);
    }
  }

  // D1 — 复制信息
  Future<void> loadRedisReplication(String connectionId) async {
    try {
      final info = await _dbService.getRedisReplicationInfo(
        connectionId: connectionId,
      );
      _redisReplicationCache[connectionId] = info;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 复制信息失败', e);
    }
  }

  Future<void> loadRedisKeyspaceInfo(String connectionId) async {
    try {
      final info = await _dbService.getRedisKeyspaceInfo(
        connectionId: connectionId,
      );
      _redisKeyspaceCache[connectionId] = info;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis Keyspace 信息失败', e);
    }
  }

  Future<void> loadRedisConfig(String connectionId) async {
    try {
      final config = await _dbService.getRedisConfig(
        connectionId: connectionId,
      );
      _redisConfigCache[connectionId] = config;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 配置失败', e);
    }
  }

  // B4 — CONFIG SET 并刷新缓存
  Future<bool> setRedisConfig(
    String connectionId,
    Map<String, String> kv,
  ) async {
    final ok = await _dbService.setRedisConfig(
      connectionId: connectionId,
      keyValuePairs: kv,
    );
    if (ok) {
      await loadRedisConfig(connectionId); // 刷新缓存以反映变更
    }
    return ok;
  }

  Future<void> loadRedisSlowLog(String connectionId) async {
    try {
      final logs = await _dbService.getRedisSlowLog(connectionId: connectionId);
      _redisSlowLogCache[connectionId] = logs;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 慢日志失败', e);
    }
  }

  Future<void> loadRedisDatabaseKeyInfo(
    String connectionId,
    String dbName,
  ) async {
    try {
      final info = await _dbService.getRedisDatabaseKeyInfo(
        dbName,
        connectionId: connectionId,
      );
      if (!_redisDbKeyInfoCache.containsKey(connectionId)) {
        _redisDbKeyInfoCache[connectionId] = {};
      }
      _redisDbKeyInfoCache[connectionId]![dbName] = info;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 数据库 Key 信息失败', e);
    }
  }

  Future<void> loadRedisTTLKeys(
    String connectionId,
    String dbName, {
    int thresholdSeconds = 300,
  }) async {
    try {
      final keys = await _dbService.getRedisTTLKeys(
        dbName,
        connectionId: connectionId,
        thresholdSeconds: thresholdSeconds,
      );
      if (!_redisTTLKeysCache.containsKey(connectionId)) {
        _redisTTLKeysCache[connectionId] = {};
      }
      _redisTTLKeysCache[connectionId]![dbName] = keys;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis TTL Key 信息失败', e);
    }
  }

  Future<void> loadRedisDBStats(String connectionId, String dbName) async {
    try {
      final stats = await _dbService.getRedisDBStats(
        dbName,
        connectionId: connectionId,
      );
      if (!_redisDBStatsCache.containsKey(connectionId)) {
        _redisDBStatsCache[connectionId] = {};
      }
      _redisDBStatsCache[connectionId]![dbName] = stats;
      notifyListeners();
    } catch (e) {
      AppLogger.e('ConnectionProvider', '加载 Redis 数据库统计失败', e);
    }
  }

  Future<List<String>> searchRedisKeys(
    String pattern, {
    required String connectionId,
  }) async {
    try {
      return await _dbService.searchRedisKeys(
        pattern,
        connectionId: connectionId,
      );
    } catch (e) {
      AppLogger.e('ConnectionProvider', '搜索 Redis Key 失败', e);
      return [];
    }
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    super.dispose();
  }

  // Test-only hook to add a server to savedConnections without
  // triggering SecureStorageService (which hangs on FlutterSecureStorage).
  @visibleForTesting
  void addSavedServerForTest(DbServer server) {
    _savedConnections.add(server);
  }

  /// Test-only hook：模拟 switchToConnection 成功后的 currentServer 状态
  /// （C22-1 切换 bug 回归守卫用——switchToConnection 真链路含真库 IO，
  /// 单测不可行）。
  @visibleForTesting
  void setCurrentServerForTest(DbServer server) {
    _currentServer = server;
  }

  @visibleForTesting
  void setConnectionDatabasesForTest(
    String connectionId,
    List<String> allDatabases,
    List<String> nonEmptyDatabases,
  ) {
    _connectionDatabases[connectionId] = allDatabases;
    _connectionNonEmptyDatabases[connectionId] = nonEmptyDatabases;
  }

  @visibleForTesting
  void setCachedDatabaseForTest(
    String connectionId,
    String databaseName,
    Database database,
  ) {
    if (!_databaseCache.containsKey(connectionId)) {
      _databaseCache[connectionId] = {};
    }
    _databaseCache[connectionId]![databaseName] = database;
  }
}

/// 数据库表分页状态。
class TablePaginationState {
  final List<DbTable> tables;
  final int page;
  final int pageSize;
  final int total;
  final String? search;

  const TablePaginationState({
    required this.tables,
    required this.page,
    required this.pageSize,
    required this.total,
    this.search,
  });
}
