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
  final Set<String> _favoriteTables = {};

  String? get selectedConnectionId => _selectedConnectionId;
  String? get selectedDatabaseName => _selectedDatabaseName;
  String? get expandedConnectionId => _expandedConnectionId;
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
      notifyListeners();
    }
  }

  void selectDatabase(String? databaseName) {
    if (_selectedDatabaseName != databaseName) {
      _selectedDatabaseName = databaseName;
      notifyListeners();
    }
  }

  void expandConnection(String? connectionId) {
    if (_expandedConnectionId != connectionId) {
      _expandedConnectionId = connectionId;
      notifyListeners();
    }
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
