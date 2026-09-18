// SidebarWidget 拆分（plan §3.4）：侧边栏局部状态控制器。
//
// 从 `_SidebarWidgetState` 迁移的非 UI 职责：
// - 三份展开集合（items / databases / tables）及持久化 round-trip
// - 键盘导航（↑↓←→ / Enter / Space / Esc / type-to-select / ⌘F）
// - 懒加载触发（database / table schema / schema objects / row counts）
// - 连接事件订阅（ConnectionEstablished → 清子展开 + 自动展开连接节点）
// - 搜索状态（query + PG server-side search 结果缓存）
//
// 不依赖 BuildContext（plan §3.4 验收要求）：AppProvider 经构造注入；
// 密码弹窗经 [promptPassword] 回调注入（widget 层闭包捕获自身 context）；
// 时钟经 [now] 注入（type-to-select 600ms buffer 可测）。
// UI 资源（搜索/树 FocusNode、TextEditingController）随本控制器创建与释放，
// 先例：organisms/editor/sql_editor_controller.dart。
//
// 注意：展开集合采用 immutable Set replacement 模式（T004/T008 系列），
// SidebarTree 通过 Set 引用变化检测状态变更 — 每次变更必须新建 Set，
// getter 直接返回内部引用（不可包 Set.unmodifiable，会破坏引用稳定性）。
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../models/connection_event.dart';
import '../../models/database_models.dart';
import '../../providers/app_provider.dart';
import '../../services/database_abstract.dart' show SchemaAwareAdapter;
import '../../services/ports/capability_table.dart';
import '../../utils/app_logger.dart';
import 'sidebar_visible_nodes.dart';

/// 侧边栏局部状态控制器（展开状态 + 键盘导航 + 懒加载）。
///
/// 生命周期由 SidebarWidget 持有：initState 创建、dispose 释放。
/// 所有状态变更通过 [notifyListeners] 通知（widget addListener → setState）。
class SidebarController extends ChangeNotifier {
  SidebarController({
    required AppProvider appProvider,
    Future<DbServer?> Function(DbServer server)? promptPassword,
    DateTime Function()? now,
  }) : _appProvider = appProvider,
       _promptPassword = promptPassword,
       _now = now ?? DateTime.now;

  final AppProvider _appProvider;
  final Future<DbServer?> Function(DbServer server)? _promptPassword;
  final DateTime Function() _now;

  bool _disposed = false;

  // ==================== 展开状态（immutable Set replacement） ====================

  Set<String> _expandedItems = {};
  Set<String> _expandedDatabases = {};
  Set<String> _expandedTables = {};

  // ==================== 懒加载缓存 / loading ====================

  final Set<String> _loadingDatabases = {};
  final Map<String, DbTable> _loadedTableSchemas = {};
  final Map<String, List<ForeignKey>> _loadedTableForeignKeys = {};
  final Set<String> _loadingTableSchemas = {};
  final Map<String, int> _tableRowCounts = {};
  final Set<String> _loadingRowCounts = {};
  // Track which schemas are currently loading per-schema objects
  final Set<String> _loadingSchemaObjects = {};
  // Server-side search results keyed by connectionId
  final Map<String, List<Map<String, String>>> _serverSearchResults = {};

  // ==================== UI 资源（随控制器创建/释放） ====================

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  final FocusNode treeFocusNode = FocusNode();

  // ==================== 搜索 / 键盘导航状态 ====================

  String _searchQuery = '';

  // Stream subscription for connection events — auto-expands
  // connection node on ConnectionEstablished.
  StreamSubscription<ConnectionEvent>? _connectionEventSubscription;

  // T012 — _treeVersion removed. SidebarTree now uses a stable key
  // and detects state changes via immutable Set replacements.
  String? _rightClickedNodeKey;
  String? _selectedNodeKey;
  final List<String> _visibleNodeKeys = [];
  String _typeSelectBuffer = '';
  DateTime _lastTypeSelectTime = DateTime.now();
  bool _treeFocusRequested = false;

  // ==================== Getters ====================

  /// 展开集合 getter 返回内部引用（SidebarTree 靠引用变化检测，见类注释）。
  Set<String> get expandedItems => _expandedItems;
  Set<String> get expandedDatabases => _expandedDatabases;
  Set<String> get expandedTables => _expandedTables;
  Set<String> get loadingDatabases => _loadingDatabases;
  Map<String, DbTable> get loadedTableSchemas => _loadedTableSchemas;
  Map<String, List<ForeignKey>> get loadedTableForeignKeys =>
      _loadedTableForeignKeys;
  Set<String> get loadingTableSchemas => _loadingTableSchemas;
  Map<String, int> get tableRowCounts => _tableRowCounts;
  Set<String> get loadingRowCounts => _loadingRowCounts;
  Set<String> get loadingSchemaObjects => _loadingSchemaObjects;
  Map<String, List<Map<String, String>>> get serverSearchResults =>
      _serverSearchResults;
  String get searchQuery => _searchQuery;
  String? get selectedNodeKey => _selectedNodeKey;
  String? get rightClickedNodeKey => _rightClickedNodeKey;
  List<String> get visibleNodeKeys => _visibleNodeKeys;

  // ==================== 持久化 round-trip ====================

  Future<void> loadExpandedState() async {
    try {
      final state = await _appProvider.sidebar.loadExpandedState();
      if (_disposed) return;
      // T008 — immutable Set replacement instead of in-place addAll
      // Only restore non-connection items (categories, schemas, tables).
      // Connection IDs from old persisted state would cause auto-expand on launch.
      // Fresh start: tree is fully collapsed.
      _expandedItems = {
        ..._expandedItems,
        ...state.items.where((id) => !_isConnectionId(id)),
      };
      _expandedDatabases = {..._expandedDatabases, ...state.databases};
      _expandedTables = {..._expandedTables, ...state.tables};
      notifyListeners();
    } catch (e) {
      // 忽略加载失败，不影响正常使用
    }
  }

  // Heuristic to detect connection-level keys (plain UUIDs without colons)
  bool _isConnectionId(String key) {
    // Connection keys are bare UUIDs like "abc123-def456"
    // Database keys: "db:cid:dbname", Schema keys: "cid:db:schema:name", etc.
    return !key.contains(':');
  }

  Future<void> saveExpandedState() async {
    try {
      await _appProvider.sidebar.saveExpandedState(
        items: Set.unmodifiable(_expandedItems),
        databases: Set.unmodifiable(_expandedDatabases),
        tables: Set.unmodifiable(_expandedTables),
      );
    } catch (e) {
      // 忽略保存失败，不影响正常使用
    }
  }

  // ==================== 连接事件订阅 ====================

  // Listen for ConnectionEstablished events to auto-expand the
  // connection node. Only expands the connection level — child nodes
  // (databases, schemas, tables) remain collapsed per lazy-loading design.
  // FR-007: Clears any previously-persisted child-node expand state for
  // this connection, ensuring a clean start on every new connection.
  void subscribeToConnectionEvents() {
    _connectionEventSubscription?.cancel();
    _connectionEventSubscription = _appProvider.connection.dbService.events
        .listen(
          (event) {
            if (event is ConnectionEstablished && !_disposed) {
              if (!_appProvider.isConnectionConnected(event.connectionId)) {
                return;
              }
              // T009 — immutable Set replacement instead of in-place removeWhere/add
              // FR-007: Clear stale child-node expand state for this connection
              // so databases/schemas/tables always start collapsed on fresh connect.
              // Keys are formatted as "connectionId:databaseName" or
              // "connectionId:databaseName:schemaName:tableName".
              _expandedDatabases = _expandedDatabases.where(
                (key) => !key.startsWith('${event.connectionId}:'),
              ).toSet();
              _expandedTables = _expandedTables.where(
                (key) => !key.startsWith('${event.connectionId}:'),
              ).toSet();
              // US1: Auto-expand connection node
              _expandedItems = {..._expandedItems, event.connectionId};
              notifyListeners();
              // Persist the cleared child state immediately to prevent
              // stale restoration on next app launch.
              saveExpandedState();
            }
          },
          onError: (Object error) {
            // Log and swallow — stream errors must not crash the sidebar.
            // The lazy-loading error UI (spec 002 FR-009) handles data-load failures.
            AppLogger.e('Sidebar', 'Sidebar connection event stream error: $error');
          },
        );
  }

  // ==================== 搜索 ====================

  /// 更新搜索词（widget 搜索框 onChanged 调用；已 trim + lowercase）。
  /// 非空时对 PostgreSQL 连接触发 server-side search。
  void updateSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
    if (query.isNotEmpty) {
      doServerSideSearch(query);
    } else {
      _serverSearchResults.clear();
    }
  }

  // Server-side search for PostgreSQL — queries pg_catalog directly
  Future<void> doServerSideSearch(String query) async {
    _serverSearchResults.clear();
    for (final conn in _appProvider.connection.savedConnections) {
      if (!_appProvider.isConnectionConnected(conn.id)) continue;
      // pg.serverSearch 位（C19 收编 PG 专有判断）
      if (!CapabilityTable.has(conn.type, 'pg.serverSearch')) continue;
      try {
        final adapter = _appProvider.dbService.getAdapter(conn.id);
        if (adapter is SchemaAwareAdapter) {
          // Use dynamic dispatch — PostgreSQL adapter has searchObjects
          final results = await (adapter as dynamic).searchObjects(
            query,
          ) as List<dynamic>;
          if (results.isNotEmpty && !_disposed) {
            _serverSearchResults[conn.id] = results.cast<Map<String, String>>();
            notifyListeners();
          }
        }
      } catch (_) {
        // Server search failure → fall back to client-side filtering of cached data
      }
    }
  }

  // ==================== 可见节点（↑↓ 导航 / type-to-select 基础） ====================

  /// 构建可见节点的有序 key 列表。由 widget 在 build 期调用（传入 watch 到的
  /// provider），时机与拆分前一致。
  void rebuildVisibleNodeKeys(AppProvider provider) {
    final keys = buildVisibleSidebarNodeKeys(
      provider: provider,
      expandedItems: _expandedItems,
      expandedDatabases: _expandedDatabases,
      expandedTables: _expandedTables,
      loadedTableSchemas: _loadedTableSchemas,
      loadedTableForeignKeys: _loadedTableForeignKeys,
      searchQuery: _searchQuery,
    );
    _visibleNodeKeys
      ..clear()
      ..addAll(keys);
  }

  // ==================== 展开状态管理 ====================

  void collapseAll() {
    // T007 — immutable Set replacement instead of in-place clear
    _expandedItems = {};
    _expandedDatabases = {};
    _expandedTables = {};
    notifyListeners();
    saveExpandedState();
  }

  void toggleExpand(String key) {
    // T004 — immutable Set replacement instead of in-place add/remove
    if (_expandedItems.contains(key)) {
      _expandedItems = _expandedItems.where((e) => e != key).toSet();
    } else {
      _expandedItems = {..._expandedItems, key};
      // Trigger per-schema lazy loading when expanding a schema node.
      // Schema key format: connectionId:databaseName:schema:schemaName
      if (key.contains(':schema:')) {
        final parts = key.split(':');
        final schemaIdx = parts.indexOf('schema');
        if (schemaIdx >= 0 && schemaIdx + 1 < parts.length) {
          final cid = parts[0];
          final db = parts[1];
          final schemaName = parts[schemaIdx + 1];
          final dbObj = _appProvider.connection.getCachedDatabase(cid, db);
          final schema = dbObj?.schemas
              .where((s) => s.name == schemaName)
              .firstOrNull;
          // 展开即重查（与库节点展开语义一致）：loadSchemaObjects 每次展开
          // 都重新拉取该 schema 的对象列表，外部变更即时可见。
          if (schema != null) {
            loadSchemaObjects(cid, db, schemaName);
          }
        }
      }
    }
    notifyListeners();
    saveExpandedState();
  }

  void toggleDatabase(String key) {
    // T005 — immutable Set replacement instead of in-place add/remove
    if (_expandedDatabases.contains(key)) {
      _expandedDatabases = _expandedDatabases.where((e) => e != key).toSet();
    } else {
      _expandedDatabases = {..._expandedDatabases, key};
    }
    notifyListeners();
    saveExpandedState();
  }

  // T010 — helper to remove a dropped database from expanded state
  void removeExpandedDatabase(String connectionId, String dbName) {
    final key = '$connectionId:$dbName';
    if (_expandedDatabases.contains(key)) {
      _expandedDatabases = _expandedDatabases.where((e) => e != key).toSet();
      notifyListeners();
      saveExpandedState();
    }
  }

  // T009 — prune expanded database keys for databases that no longer exist
  void pruneOrphanedExpandedDatabases(AppProvider provider) {
    final orphanedKeys = <String>[];
    for (final key in _expandedDatabases) {
      final parts = key.split(':');
      if (parts.length < 2) {
        orphanedKeys.add(key);
        continue;
      }
      final connId = parts.first;
      final dbName = parts.sublist(1).join(':');
      final dbs = provider.connection.getConnectionDatabases(connId);
      if (!dbs.contains(dbName)) {
        orphanedKeys.add(key);
      }
    }
    if (orphanedKeys.isNotEmpty) {
      for (final key in orphanedKeys) {
        final parts = key.split(':');
        if (parts.length >= 2) {
          // T010 — reuse the targeted removal helper for each orphaned key
          removeExpandedDatabase(parts.first, parts.sublist(1).join(':'));
        }
      }
    }
  }

  void toggleTable(String key) {
    // T006 — immutable Set replacement instead of in-place add/remove
    if (_expandedTables.contains(key)) {
      _expandedTables = _expandedTables.where((e) => e != key).toSet();
    } else {
      _expandedTables = {..._expandedTables, key};
      loadTableSchema(key);
    }
    notifyListeners();
    saveExpandedState();
  }

  // ==================== 节点选择（SidebarTree 回调接线） ====================

  void selectNode(String? key) {
    _selectedNodeKey = key;
    notifyListeners();
  }

  void setRightClickedNodeKey(String? key) {
    _rightClickedNodeKey = key;
    notifyListeners();
  }

  // ==================== 键盘导航 ====================

  void _handleKeyNavigate(int direction) {
    if (_visibleNodeKeys.isEmpty) return;
    final currentIdx = _selectedNodeKey != null
        ? _visibleNodeKeys.indexOf(_selectedNodeKey!)
        : -1;
    int newIdx;
    if (direction < 0) {
      newIdx = currentIdx <= 0 ? _visibleNodeKeys.length - 1 : currentIdx - 1;
    } else {
      newIdx = currentIdx >= _visibleNodeKeys.length - 1 ? 0 : currentIdx + 1;
    }
    _selectedNodeKey = _visibleNodeKeys[newIdx];
    notifyListeners();
  }

  void _handleKeyExpandCollapse(bool expand) {
    final key = _selectedNodeKey;
    if (key == null) return;

    if (key.startsWith('conn:')) {
      final connId = key.substring(5);
      if (expand && !_expandedItems.contains(connId)) {
        // →: 展开连接。离线时尝试建立连接，在线时展开并确保数据库列表已加载
        if (!_appProvider.isConnectionConnected(connId)) {
          _connectAndExpand(connId);
        } else {
          // T019 — immutable Set replacement
          _expandedItems = {..._expandedItems, connId};
          // 展开即刷新（与鼠标路径一致）：重查库列表。
          _onConnectionExpanded(connId);
          notifyListeners();
          saveExpandedState();
        }
      } else if (!expand && _expandedItems.contains(connId)) {
        // T019 — immutable Set replacement
        _expandedItems = _expandedItems.where((e) => e != connId).toSet();
        notifyListeners();
        saveExpandedState();
      }
    } else if (key.startsWith('db:')) {
      final parts = key.substring(3).split(':');
      final cid = parts[0];
      final dbName = parts.length >= 2 ? parts[1] : '';
      // 展开集合存「cid:db」裸格式（树渲染/持久化/prune 的消费契约；
      // C19 修复：键盘路径此前误存「db:cid:db」完整可见 key——树不认、
      // prune 误判孤儿，鼠标/键盘双格式漂移）。
      final dbKey = '$cid:$dbName';
      if (expand && !_expandedDatabases.contains(dbKey)) {
        // →: 展开数据库，先确保 schema 已缓存
        _expandDatabase(cid, dbName, dbKey);
      } else if (!expand && _expandedDatabases.contains(dbKey)) {
        // T019 — immutable Set replacement
        _expandedDatabases = _expandedDatabases.where((e) => e != dbKey).toSet();
        notifyListeners();
        saveExpandedState();
      }
    } else if (key.startsWith('cat:')) {
      // 展开集合存裸 key（剥「cat:」导航前缀）——树装配（泛 SQL 共享树/
      // SavedQueriesSection）按裸 key 查询（C19 统一 key 契约）。
      final storeKey = key.substring(4);
      if (expand && !_expandedItems.contains(storeKey)) {
        // T019 — immutable Set replacement
        _expandedItems = {..._expandedItems, storeKey};
        notifyListeners();
        saveExpandedState();
      } else if (!expand && _expandedItems.contains(storeKey)) {
        // T019 — immutable Set replacement
        _expandedItems = _expandedItems.where((e) => e != storeKey).toSet();
        notifyListeners();
        saveExpandedState();
      }
      // T009 — schema node expand/collapse (same behavior as cat:)
    } else if (key.startsWith('schema:')) {
      // 同上：剥「schema:」前缀（PG 插件树按裸 key「cid:db:schema:name」查询）
      final storeKey = key.substring(7);
      if (expand && !_expandedItems.contains(storeKey)) {
        // T019 — immutable Set replacement
        _expandedItems = {..._expandedItems, storeKey};
        notifyListeners();
        saveExpandedState();
      } else if (!expand && _expandedItems.contains(storeKey)) {
        // T019 — immutable Set replacement
        _expandedItems = _expandedItems.where((e) => e != storeKey).toSet();
        notifyListeners();
        saveExpandedState();
      }
    } else if (key.startsWith('table:')) {
      // ←/→ on table: collapse/expand the table node to toggle detail view
      final tk = key.substring(6); // <cid>:<db>:<tableName> or <cid>:<db>:<schema>:<tableName>
      if (expand && !_expandedTables.contains(tk)) {
        // T019 — immutable Set replacement
        _expandedTables = {..._expandedTables, tk};
        notifyListeners();
        if (!_loadingTableSchemas.contains(tk) &&
            !_loadedTableSchemas.containsKey(tk)) {
          loadTableSchema(tk);
        }
        saveExpandedState();
      } else if (!expand && _expandedTables.contains(tk)) {
        // T019 — immutable Set replacement
        _expandedTables = _expandedTables.where((e) => e != tk).toSet();
        notifyListeners();
        saveExpandedState();
      }
    }
  }

  Future<void> _connectAndExpand(String connId) async {
    // 重入守卫（同 sidebar_tree._connectToServer）：在途连接不再弹密码框。
    if (_appProvider.connection.isConnectionConnecting(connId)) return;
    final servers = _appProvider.connection.savedConnections;
    final idx = servers.indexWhere((s) => s.id == connId);
    if (idx < 0) return;
    final serverWithPassword = _promptPassword != null
        ? await _promptPassword(servers[idx])
        : null;
    if (serverWithPassword == null) return;
    final success = await _appProvider.connectToServer(serverWithPassword);
    // Auto-expand is now handled by the ConnectionEstablished stream
    // listener in subscribeToConnectionEvents(). The connection node will
    // auto-expand after the event fires, revealing databases via lazy loading.
    // T010 — auto-expand handled by ConnectionEstablished stream listener;
    // no local state change needed here.
    if (success && !_disposed) {
      notifyListeners();
    }
  }

  Future<void> _expandDatabase(String cid, String dbName, String dbKey) async {
    _loadingDatabases.add(dbKey);
    notifyListeners();
    // 展开即重查（forceRefresh）：外部新增/删除的表、视图在下次展开时
    // 可见。失败时 loadDatabaseInfo 返回 null 且不落缓存，旧快照保留。
    // Load schemas only on first expand (defer per-schema object loading).
    // The adapter type check ensures schemasOnly only applies to PG/SS.
    final adapter = _appProvider.dbService.getAdapter(cid);
    final isSchemaAware = adapter is SchemaAwareAdapter;
    await _appProvider.loadDatabaseInfo(cid, dbName,
        forceRefresh: true, schemasOnly: isSchemaAware);
    _loadingDatabases.remove(dbKey);
    if (!_disposed) {
      // T010 — immutable Set replacement
      _expandedDatabases = {..._expandedDatabases, dbKey};
      notifyListeners();
      saveExpandedState();
    }
  }

  Future<void> _handleTreeEnter() async {
    final key = _selectedNodeKey;
    if (key == null) return;
    final provider = _appProvider;

    if (key.startsWith('conn:')) {
      final connId = key.substring(5);
      final isConnected = provider.isConnectionConnected(connId);
      if (!isConnected) {
        // Auto-expand is handled by the ConnectionEstablished stream
        // listener. Enter connects; the event-driven expand follows automatically.
        final servers = provider.connection.savedConnections;
        final idx = servers.indexWhere((s) => s.id == connId);
        if (idx >= 0) {
          final serverWithPassword = _promptPassword != null
              ? await _promptPassword(servers[idx])
              : null;
          if (serverWithPassword == null) return;
          final success = await provider.connectToServer(serverWithPassword);
          // T020 — remove _treeVersion++, notify via listeners
          if (success && !_disposed) {
            notifyListeners();
          }
        }
      } else {
        // Toggle expand/collapse (no auto-expand)
        // T020 — immutable Set replacement
        if (_expandedItems.contains(connId)) {
          _expandedItems = _expandedItems.where((e) => e != connId).toSet();
        } else {
          _expandedItems = {..._expandedItems, connId};
          // 展开即刷新（与鼠标路径一致）：重查库列表。
          _onConnectionExpanded(connId);
        }
        notifyListeners();
        saveExpandedState();
      }
    } else if (key.startsWith('db:')) {
      final parts = key.substring(3).split(':');
      final cid = parts[0];
      final dbName = parts.length >= 2 ? parts[1] : '';
      // 展开集合存「cid:db」裸格式（C19 统一 key 契约，见 _handleKeyExpandCollapse）
      final dbKey = '$cid:$dbName';
      if (!_expandedDatabases.contains(dbKey)) {
        // 展开数据库：与鼠标路径同走 _expandDatabase（展开即重查 +
        // schema-aware 懒加载语义一致——此前键盘路径漏传 schemasOnly）。
        await _expandDatabase(cid, dbName, dbKey);
      } else {
        // T020 — immutable Set replacement
        _expandedDatabases = _expandedDatabases.where((e) => e != dbKey).toSet();
        notifyListeners();
        saveExpandedState();
      }
    } else if (key.startsWith('cat:')) {
      // 展开集合存裸 key（剥「cat:」导航前缀，C19 统一 key 契约）
      final storeKey = key.substring(4);
      // T020 — immutable Set replacement
      if (!_expandedItems.contains(storeKey)) {
        _expandedItems = {..._expandedItems, storeKey};
      } else {
        _expandedItems = _expandedItems.where((e) => e != storeKey).toSet();
      }
      notifyListeners();
      saveExpandedState();
      // T009 — schema node Enter behavior (same as cat:)
    } else if (key.startsWith('schema:')) {
      // 同上：剥「schema:」前缀（裸 key「cid:db:schema:name」）
      final storeKey = key.substring(7);
      // T020 — immutable Set replacement
      if (!_expandedItems.contains(storeKey)) {
        _expandedItems = {..._expandedItems, storeKey};
      } else {
        _expandedItems = _expandedItems.where((e) => e != storeKey).toSet();
      }
      notifyListeners();
      saveExpandedState();
    } else if (key.startsWith('table:')) {
      final tk = key.substring(6); // <cid>:<db>:<tableName> or <cid>:<db>:<schema>:<tableName>
      if (_expandedTables.contains(tk)) {
        // 已展开：打开浏览查询（Enter = "go deeper" 到数据层）
        final parts = tk.split(':');
        if (parts.length >= 2) {
          final cid = parts[0];
          final db = parts[1];
          // 4-part key (cid:db:schemaName:tableName) for schema-aware DBs
          // 3-part key (cid:db:tableName) for flat DBs
          final table = parts.length >= 4
              ? '${parts[2]}.${parts[3]}'
              : parts.sublist(2).join(':');
          // Enter（已展开）= 默认打开 → query 编辑器；
          // data 模式仅右键「浏览数据」进入
          provider.openTableQueryTab(cid, db, table);
          provider.recentTables.recordTableAccess(
            connectionId: cid,
            databaseName: db,
            tableName: table,
          );
        }
      } else {
        // 未展开：展开（加载 schema）
        // T020 — immutable Set replacement
        _expandedTables = {..._expandedTables, tk};
        notifyListeners();
        if (!_loadingTableSchemas.contains(tk) &&
            !_loadedTableSchemas.containsKey(tk)) {
          loadTableSchema(tk);
        }
        saveExpandedState();
      }
    } else if (key.startsWith('view:')) {
      final parts = key.substring(5).split(':');
      if (parts.length >= 3) {
        final cid = parts[0];
        final db = parts[1];
        final view = parts.sublist(2).join(':');
        // Enter（已展开）= 默认打开 → query 编辑器（预填默认浏览查询）
        provider.openTableQueryTab(cid, db, view);
      }
    } else if (key.startsWith('proc:')) {
      final parts = key.substring(5).split(':');
      if (parts.length >= 3) {
        final cid = parts[0];
        final db = parts[1];
        final proc = parts.sublist(2).join(':');
        provider.openQueryTab(cid, db, sql: 'CALL $proc();');
      }
    } else if (key.startsWith('func:')) {
      final parts = key.substring(5).split(':');
      if (parts.length >= 3) {
        final cid = parts[0];
        final db = parts[1];
        final fn = parts.sublist(2).join(':');
        // Functions can't be CALLed — use SELECT name().
        provider.openQueryTab(cid, db, sql: 'SELECT `$fn`();');
      }
    } else if (key.startsWith('savedquery:')) {
      final parts = key.substring(11).split(':');
      if (parts.length >= 3) {
        final queryId = parts.sublist(2).join(':');
        final query = provider.getSavedQueryById(queryId);
        if (query != null) {
          provider.openSavedQuery(query);
        }
      }
    } else if (key.startsWith('col:') ||
        key.startsWith('idx:') ||
        key.startsWith('fk:')) {
      // 在 schema 叶子上按 Enter → 把名字插入当前活动编辑器
      final name = key.substring(key.lastIndexOf(':') + 1);
      provider.insertIntoActiveEditor?.call(name);
    }
  }

  void _handleTypeSelect(String char) {
    final now = _now();
    if (now.difference(_lastTypeSelectTime) >
        const Duration(milliseconds: 600)) {
      _typeSelectBuffer = '';
    }
    _lastTypeSelectTime = now;
    _typeSelectBuffer += char.toLowerCase();

    // 在当前已选 node 之后找匹配
    int startIdx = 0;
    if (_selectedNodeKey != null) {
      final idx = _visibleNodeKeys.indexOf(_selectedNodeKey!);
      if (idx >= 0) startIdx = idx + 1;
    }
    if (startIdx >= _visibleNodeKeys.length) startIdx = 0;

    for (var i = startIdx; i < _visibleNodeKeys.length; i++) {
      if (sidebarNodeDisplayName(
        _visibleNodeKeys[i],
        _appProvider,
      ).toLowerCase().startsWith(_typeSelectBuffer)) {
        _selectedNodeKey = _visibleNodeKeys[i];
        notifyListeners();
        return;
      }
    }
    // wrap around
    for (var i = 0; i < startIdx; i++) {
      if (sidebarNodeDisplayName(
        _visibleNodeKeys[i],
        _appProvider,
      ).toLowerCase().startsWith(_typeSelectBuffer)) {
        _selectedNodeKey = _visibleNodeKeys[i];
        notifyListeners();
        return;
      }
    }
    // C19 修复：多字符无匹配时退化为单字符**重试**（原先只重置 buffer 不
    // 重搜——输入「ab」无命中但存在「a…」节点时选中态纹丝不动）。
    _typeSelectBuffer = char.toLowerCase();
    for (var i = 0; i < _visibleNodeKeys.length; i++) {
      if (sidebarNodeDisplayName(
        _visibleNodeKeys[i],
        _appProvider,
      ).toLowerCase().startsWith(_typeSelectBuffer)) {
        _selectedNodeKey = _visibleNodeKeys[i];
        notifyListeners();
        return;
      }
    }
  }

  /// Focus.onKeyEvent: 键盘导航、type-to-select、Esc、⌘F
  KeyEventResult handleTreeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // 当搜索框有焦点时不拦截键盘
    if (searchFocusNode.hasFocus) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    // ⌘F / Ctrl+F: 聚焦搜索框
    if ((ctrl || meta) && key == LogicalKeyboardKey.keyF) {
      searchFocusNode.requestFocus();
      searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: searchController.text.length,
      );
      return KeyEventResult.handled;
    }

    // 不拦截其他带修饰键的组合键（Ctrl+C/V/等）
    if (ctrl || meta || alt) return KeyEventResult.ignored;

    // 方向键导航
    if (key == LogicalKeyboardKey.arrowDown) {
      _handleKeyNavigate(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _handleKeyNavigate(-1);
      return KeyEventResult.handled;
    }
    // ←→ 折叠/展开
    if (key == LogicalKeyboardKey.arrowLeft) {
      _handleKeyExpandCollapse(false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _handleKeyExpandCollapse(true);
      return KeyEventResult.handled;
    }
    // Enter / Space 触发默认操作
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      _handleTreeEnter();
      return KeyEventResult.handled;
    }
    // Esc 取消选中
    if (key == LogicalKeyboardKey.escape) {
      if (_selectedNodeKey != null) {
        _selectedNodeKey = null;
        notifyListeners();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // 字母/数字键 → type-to-select
    final label = key.keyLabel;
    if (label.length == 1 && RegExp(r'[a-zA-Z0-9]').hasMatch(label)) {
      _handleTypeSelect(label);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ==================== 连接点击（折叠态 / 树连接节点共用） ====================

  Future<void> handleConnectionTap(DbServer server) async {
    if (_appProvider.isConnectionConnected(server.id)) {
      final wasExpanded = _expandedItems.contains(server.id);
      toggleExpand(server.id);
      // 展开即刷新语义：折叠态 → 展开是一次显式的「看看现在有什么」。
      if (!wasExpanded) _onConnectionExpanded(server.id);
      if (_appProvider.connection.currentServer?.id != server.id) {
        // tab 上下文同步收在 switchToConnection 代理内（工具栏芯片与
        // 执行同源，2026-08-27 修复）。
        await _appProvider.switchToConnection(server.id);
      }
    } else {
      // 重入守卫：在途连接不再弹密码框（同 sidebar_tree._connectToServer）。
      if (_appProvider.connection.isConnectionConnecting(server.id)) return;
      final serverWithPassword = _promptPassword != null
          ? await _promptPassword(server)
          : null;
      if (serverWithPassword == null) return;
      final success = await _appProvider.connectToServer(serverWithPassword);
      // Auto-expand is now handled by the ConnectionEstablished stream
      // listener. The connection node auto-expands after the event fires.
      if (success && !_disposed) {
        _appProvider.refreshDatabases();
      }
    }
  }

  // 展开即刷新：连接节点展开时重查库列表——其他人经其它客户端在实例上
  // 新建/删除的库要能在下次展开时被看到。refreshDatabases 失败时保留
  // 旧列表（FR-005），完成后自行 notifyListeners。
  void _onConnectionExpanded(String connectionId) {
    if (!_appProvider.isConnectionConnected(connectionId)) return;
    _appProvider.refreshDatabases(connectionId: connectionId);
  }

  // ==================== 懒加载 ====================

  Future<void> loadTableRowCountsForDb(
    String connectionId,
    String databaseName,
  ) async {
    final cacheKey = '$connectionId:$databaseName';
    if (_loadingRowCounts.contains(cacheKey)) return;
    _loadingRowCounts.add(cacheKey);
    try {
      // C19 — per-type SQL 收编 dbService.getTableRowCounts（getProcessList
      // 同款先例）；控制器只组装树消费的键形态。
      final rows = await _appProvider.dbService.getTableRowCounts(
        connectionId,
        databaseName,
      );
      for (final r in rows) {
        // T006 — schema-aware 双键（限定 + 裸名），两种树消费形态都命中
        final schema = r.schema;
        if (schema != null && schema.isNotEmpty) {
          _tableRowCounts['$connectionId:$databaseName:$schema:${r.name}'] =
              r.rows;
        }
        _tableRowCounts['$connectionId:$databaseName:${r.name}'] = r.rows;
      }
    } catch (_) {
      // ignore
    } finally {
      _loadingRowCounts.remove(cacheKey);
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> loadTableSchema(String tableKey) async {
    if (_loadingTableSchemas.contains(tableKey) ||
        _loadedTableSchemas.containsKey(tableKey)) {
      return;
    }
    final parts = tableKey.split(':');
    if (parts.length < 3) return;
    final connectionId = parts[0];
    final databaseName = parts[1];
    // T005 — support 4-segment schema-aware keys (cid:db:schema:table)
    final isSchemaAware = parts.length >= 4;
    final tableName = isSchemaAware
        ? '${parts[2]}.${parts.sublist(3).join(':')}'
        : parts.sublist(2).join(':');

    _loadingTableSchemas.add(tableKey);
    notifyListeners();
    try {
      final dbType = _appProvider.dbService.getDatabaseType(connectionId);
      final columns = await _appProvider.dbService.getTableColumns(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      final indexes = await _appProvider.dbService.getTableIndexes(
        tableName,
        connectionId: connectionId,
        databaseName: databaseName,
      );
      List<ForeignKey>? foreignKeys;
      if (dbType?.supportsForeignKeys ?? false) {
        foreignKeys = await _appProvider.dbService.getForeignKeys(
          tableName,
          connectionId: connectionId,
          databaseName: databaseName,
        );
      }
      if (!_disposed) {
        _loadedTableSchemas[tableKey] = DbTable(
          name: tableName,
          columns: columns,
          indexes: indexes,
        );
        if (foreignKeys != null && foreignKeys.isNotEmpty) {
          _loadedTableForeignKeys[tableKey] = foreignKeys;
        }
        _loadingTableSchemas.remove(tableKey);
        notifyListeners();
      }
    } catch (_) {
      if (!_disposed) {
        _loadingTableSchemas.remove(tableKey);
        notifyListeners();
      }
    }
  }

  // Per-schema lazy loading — loads tables/views/etc. for a single schema
  Future<void> loadSchemaObjects(
    String connectionId,
    String databaseName,
    String schemaName,
  ) async {
    final key = '$connectionId:$databaseName:$schemaName';
    if (_loadingSchemaObjects.contains(key)) return;
    _loadingSchemaObjects.add(key);
    // T011 — remove _treeVersion++, keep notify for loading indicator
    notifyListeners();
    try {
      final adapter = _appProvider.dbService.getAdapter(connectionId);
      if (adapter == null) return;
      final dyn = adapter as dynamic;

      // Load per-schema objects using adapter's schema-aware methods
      final tables = (await dyn.getTables(schemaName: schemaName) as List<String>)
          .map((n) => DbTable(name: n))
          .toList();
      final views = await dyn.getViews(schemaName: schemaName) as List<String>;
      final functions = await dyn.getFunctions(schemaName: schemaName) as List<String>;
      final procedures = await dyn.getProcedures(schemaName: schemaName) as List<String>;
      final matViews = await dyn.getMaterializedViews(schemaName: schemaName) as List<String>;
      final sequences = await dyn.getSequences(schemaName: schemaName) as List<String>;
      final triggers = await dyn.getTriggers(schemaName: schemaName) as List<DbTrigger>;

      // Update the cached Database with this schema's objects
      final db = _appProvider.connection.getCachedDatabase(
        connectionId,
        databaseName,
      );
      if (db != null) {
        final updatedSchemas = db.schemas.map((s) {
          if (s.name == schemaName) {
            return DbSchema(
              name: schemaName,
              tables: tables,
              views: views,
              functions: functions,
              procedures: procedures,
              materializedViews: matViews,
              sequences: sequences,
              triggers: triggers,
            );
          }
          return s;
        }).toList();
        // Rebuild flat union lists from all schemas
        final allTables = updatedSchemas.expand((s) => s.tables).toList();
        final allViews = updatedSchemas.expand((s) => s.views).toList();
        final allFunctions = updatedSchemas.expand((s) => s.functions).toList();
        final allProcedures = updatedSchemas.expand((s) => s.procedures).toList();
        final allMatViews = updatedSchemas
            .expand((s) => s.materializedViews)
            .toList();
        final allSequences = updatedSchemas.expand((s) => s.sequences).toList();
        final allTriggers = updatedSchemas.expand((s) => s.triggers).toList();
        final updated = Database(
          name: db.name,
          tables: allTables,
          views: allViews,
          procedures: [...allFunctions, ...allProcedures],
          triggers: allTriggers,
          events: db.events,
          functions: allFunctions,
          materializedViews: allMatViews,
          sequences: allSequences,
          schemas: updatedSchemas,
        );
        _appProvider.connection.updateCachedDatabase(
          connectionId,
          databaseName,
          updated,
        );
      }
    } catch (_) {
      // Load failure — schema stays with empty children; user can retry via Refresh
    }
    if (!_disposed) {
      _loadingSchemaObjects.remove(key);
      // T011 — remove _treeVersion++, keep notify for schema UI update
      notifyListeners();
    }
  }

  Future<void> loadDatabaseInfo(
    String connectionId,
    String databaseName,
  ) async {
    final key = '$connectionId:$databaseName';
    _loadingDatabases.add(key);
    notifyListeners();
    try {
      // forceRefresh：本 wrapper 服务于树节点的展开/补载路径（鼠标展开、
      // 展开态缺缓存 postFrame 补载）——展开即重查，命中旧缓存没有意义。
      await _appProvider.loadDatabaseInfo(
        connectionId,
        databaseName,
        forceRefresh: true,
      );
      final server = _appProvider.connection.savedConnections.firstWhere(
        (s) => s.id == connectionId,
        orElse: () => throw Exception('连接不存在'),
      );
      // td.supertable 位（C19 收编 TD 专有判断）：库级 SuperTables 对象随库加载
      if (CapabilityTable.has(server.type, 'td.supertable')) {
        await _appProvider.loadSuperTables(connectionId, databaseName);
      }
    } catch (_) {}
    if (!_disposed) {
      _loadingDatabases.remove(key);
      notifyListeners();
    }
  }

  // ==================== 首帧焦点 ====================

  /// 仅在侧边栏首次挂载时请求树焦点，不重复抢占。
  /// 由 widget 的展开态 build 调用（与拆分前时机一致）。
  void ensureInitialTreeFocus() {
    if (_treeFocusRequested) return;
    _treeFocusRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      if (!treeFocusNode.hasFocus && !searchFocusNode.hasFocus) {
        treeFocusNode.requestFocus();
      }
    });
  }

  // ==================== 生命周期 ====================

  @override
  void dispose() {
    _disposed = true;
    // 与拆分前 _SidebarWidgetState.dispose 顺序一致：
    // save 展开态 → cancel 订阅 → 释放 UI 资源。
    saveExpandedState();
    _connectionEventSubscription?.cancel();
    searchController.dispose();
    searchFocusNode.dispose();
    treeFocusNode.dispose();
    super.dispose();
  }
}
