import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SidebarProvider - 导航侧边栏的独立选择状态
///
/// 职责：管理数据库导航树中当前选中的连接和数据库。
/// 注意：这不代表全局活跃连接，各模块（Tab、AI面板）有自己的选择状态。
class SidebarProvider extends ChangeNotifier {
  String? _selectedConnectionId;
  String? _selectedDatabaseName;
  String? _expandedConnectionId;
  String? _sidebarExpandRequest;
  final Set<String> _favoriteTables = {};

  String? get selectedConnectionId => _selectedConnectionId;
  String? get selectedDatabaseName => _selectedDatabaseName;
  String? get expandedConnectionId => _expandedConnectionId;

  /// 一次性展开请求信号（2b.1 observe escalation 通道，R3）：observe 的
  /// 「在经典中管理」请求展开经典进程面板挂载键（`'$connectionId:performance'`），
  /// 由 SidebarWidget 消费后补展开并清除。**一次性、不持久化**（非展开状态
  /// 快照，不进 SharedPreferences）。
  String? get sidebarExpandRequest => _sidebarExpandRequest;
  Set<String> get favoriteTables => Set.unmodifiable(_favoriteTables);

  SidebarProvider() {
    _loadFavorites();
  }

  // ==================== 收藏持久化 ====================

  static const String _favoritesKey = 'sidebar_favorite_tables';

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_favoritesKey);
      if (saved != null) {
        _favoriteTables.addAll(saved);
        notifyListeners();
      }
    } catch (e) {
      // ignore load errors
    }
  }

  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoritesKey, _favoriteTables.toList());
    } catch (e) {
      // ignore save errors
    }
  }

  // ==================== 最后选库持久化（按连接） ====================

  /// 按连接持久化最后选中的库：键 = `sidebar_last_db_<connectionId>`。
  /// 键归属连接而非会话内选择——clearSelection 不清键；连接删除时由
  /// AppProvider.deleteConnection 显式清除；重启后经
  /// AppProvider.restoreSidebarDatabaseSelection 校验恢复。
  static const String _lastDbKeyPrefix = 'sidebar_last_db_';

  String _lastDbKey(String connectionId) => '$_lastDbKeyPrefix$connectionId';

  /// 纯判定（可单测）：persisted 非空且在 availableDatabases 内 → 返回之；
  /// 否则 null（键缺失 / 空串损坏 / 库已不在列表——含 SQLite 无库列表语义
  /// 的连接，availableDatabases 为空自然返回 null）。
  static String? resolveRestorableDatabase({
    required String? persisted,
    required List<String> availableDatabases,
  }) {
    final name = persisted;
    if (name == null || name.isEmpty) return null;
    if (!availableDatabases.contains(name)) return null;
    return name;
  }

  /// 读取指定连接持久化的最后选库。prefs 缺键 / 值损坏（非字符串转型失败）/
  /// 读失败一律返回 null（静默忽略，沿 _loadFavorites 的吞错风格）。
  Future<String?> getPersistedLastDatabase(String connectionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_lastDbKey(connectionId));
    } catch (e) {
      return null;
    }
  }

  /// 清除指定连接的持久化键（连接删除 / 持久化库已不存在时调用）。
  Future<void> clearPersistedLastDatabase(String connectionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastDbKey(connectionId));
    } catch (e) {
      // ignore clear errors
    }
  }

  Future<void> _persistLastDatabase(
    String connectionId,
    String databaseName,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastDbKey(connectionId), databaseName);
    } catch (e) {
      // ignore persist errors
    }
  }

  // ==================== 展开状态持久化 ====================

  static const String _expandedItemsKey = 'sidebar_expanded_items';
  static const String _expandedDatabasesKey = 'sidebar_expanded_databases';
  static const String _expandedTablesKey = 'sidebar_expanded_tables';

  /// 从 SharedPreferences 恢复展开状态
  Future<({Set<String> items, Set<String> databases, Set<String> tables})>
  loadExpandedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = prefs.getStringList(_expandedItemsKey);
      final databases = prefs.getStringList(_expandedDatabasesKey);
      final tables = prefs.getStringList(_expandedTablesKey);
      return (
        items: items?.toSet() ?? <String>{},
        databases: databases?.toSet() ?? <String>{},
        tables: tables?.toSet() ?? <String>{},
      );
    } catch (e) {
      return (items: <String>{}, databases: <String>{}, tables: <String>{});
    }
  }

  /// 持久化展开状态到 SharedPreferences
  Future<void> saveExpandedState({
    required Set<String> items,
    required Set<String> databases,
    required Set<String> tables,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setStringList(_expandedItemsKey, items.toList()),
        prefs.setStringList(_expandedDatabasesKey, databases.toList()),
        prefs.setStringList(_expandedTablesKey, tables.toList()),
      ]);
    } catch (e) {
      // ignore save errors
    }
  }

  // ==================== 选择状态 ====================

  void selectConnection(String? connectionId) {
    if (_selectedConnectionId != connectionId) {
      _selectedConnectionId = connectionId;
      _expandedConnectionId = connectionId;
      // 库选择隶属于连接（Fix-J 归属不变式）：换连接时旧库选择失效清空，
      // 防 selectedDatabaseName 残留错挂新连接（张冠李戴）。配对调用点
      // （树库节点 / 收藏 / 最近 / focus 定位）随后即以 selectDatabase 重设
      // 新连接的库；裸 selectConnection 调用点（SQLite 打开成功定位 /
      // 欢迎页连接芯片）正是本守卫的对象。
      _selectedDatabaseName = null;
      notifyListeners();
    }
  }

  void selectDatabase(String? databaseName) {
    if (_selectedDatabaseName != databaseName) {
      _selectedDatabaseName = databaseName;
      // 最后选库落盘（键按连接归属）：已选连接时写入/清除持久化键。
      // null（显式取消选库）清对应键；未选连接不写（键属于连接，Fix-J）。
      // fire-and-forget：写失败静默，不影响内存选择语义。
      final connectionId = _selectedConnectionId;
      if (connectionId != null) {
        if (databaseName != null) {
          unawaited(_persistLastDatabase(connectionId, databaseName));
        } else {
          unawaited(clearPersistedLastDatabase(connectionId));
        }
      }
      notifyListeners();
    }
  }

  void expandConnection(String? connectionId) {
    if (_expandedConnectionId != connectionId) {
      _expandedConnectionId = connectionId;
      notifyListeners();
    }
  }

  /// 发起一次性展开请求（2b.1 R3）：每次调用均 notify（重复请求覆盖旧值，
  /// 消费方只处理最新请求）。
  void requestSidebarExpand(String key) {
    _sidebarExpandRequest = key;
    notifyListeners();
  }

  /// 消费（清除）展开请求（SidebarWidget 补展开后调用；无请求时零副作用
  /// 不通知，防通知风暴）。
  void consumeSidebarExpandRequest() {
    if (_sidebarExpandRequest == null) return;
    _sidebarExpandRequest = null;
    notifyListeners();
  }

  void toggleFavoriteTable(String tableKey) {
    if (_favoriteTables.contains(tableKey)) {
      _favoriteTables.remove(tableKey);
    } else {
      _favoriteTables.add(tableKey);
    }
    _saveFavorites();
    notifyListeners();
  }

  bool isFavoriteTable(String tableKey) {
    return _favoriteTables.contains(tableKey);
  }

  void clearSelection() {
    _selectedConnectionId = null;
    _selectedDatabaseName = null;
    _expandedConnectionId = null;
    notifyListeners();
  }
}
