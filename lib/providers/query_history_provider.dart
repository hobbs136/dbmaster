import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/database_models.dart' show DatabaseType;
import '../models/query_history.dart';
import '../utils/app_logger.dart';

/// QueryHistoryProvider - 专注查询历史管理
/// 职责：记录、搜索、过滤查询历史
class QueryHistoryProvider extends ChangeNotifier {
  static const int _maxHistorySize = 500;

  /// 历史记录单条 SQL 截断上限。历史经 SharedPreferences 整文件读写
  /// （jsonEncode 全量 + setString 重写），不截断时用户反复执行的 MB 级
  /// 脚本会把 prefs 撑到 ~10MB——之后每次新增历史都是一次 10MB 级重写，
  /// 多语句执行逐条写入时 UI 线程阻塞数十秒（实测 39.7s）。
  static const int _maxSqlChars = 2000;
  static const String _truncatedSuffix = r'-- ...(历史记录截断，全文请在编辑器/脚本文件中获取)';

  static String _truncateSql(String sql) {
    if (sql.length <= _maxSqlChars) return sql;
    return sql.substring(0, _maxSqlChars) + _truncatedSuffix;
  }

  final List<QueryHistory> _queryHistory = [];
  bool _isLoading = false;

  // ==================== Getters ====================

  List<QueryHistory> get queryHistory => List.unmodifiable(_queryHistory);
  int get historyCount => _queryHistory.length;
  bool get isLoading => _isLoading;

  // ==================== 持久化 ====================

  Future<void> loadQueryHistory() async {
    _isLoading = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('query_history');
    if (historyJson != null) {
      try {
        final List<dynamic> list = jsonDecode(historyJson);
        _queryHistory.clear();
        _queryHistory.addAll(
          list.map((e) => QueryHistory.fromJson(e as Map<String, dynamic>)),
        );
        // 存量修复：旧版本未截断，超大 SQL 会把 prefs 撑到 ~10MB，拖慢
        // 之后每一次历史写入。加载时截断并立即回写一次。
        if (_queryHistory.any((h) => h.sql.length > _maxSqlChars)) {
          for (var i = 0; i < _queryHistory.length; i++) {
            final h = _queryHistory[i];
            if (h.sql.length > _maxSqlChars) {
              _queryHistory[i] = h.copyWith(sql: _truncateSql(h.sql));
            }
          }
          await _persistQueryHistory();
        }
      } catch (e, stackTrace) {
        AppLogger.e(
          'QueryHistoryProvider',
          'Failed to load query history',
          e,
          stackTrace,
        );
        _queryHistory.clear();
      }
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addQueryHistory({
    required String sql,
    required String connectionId,
    String? connectionName,
    int executionTime = 0,
    int affectedRows = 0,
    String? error,
    String? database,
    DatabaseType? databaseType,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    final history = QueryHistory(
      id: '${now.millisecondsSinceEpoch}',
      sql: _truncateSql(sql.trim()),
      timestamp: now,
      connectionId: connectionId,
      connectionName: connectionName,
      database: database,
      databaseType: databaseType,
      executionTime: executionTime,
      affectedRows: affectedRows,
      error: error,
    );

    // 去重：相同的 SQL + connectionId 移到最前面
    _queryHistory.removeWhere(
      (h) => h.sql == history.sql && h.connectionId == history.connectionId,
    );
    _queryHistory.insert(0, history);

    // 限制最大数量
    if (_queryHistory.length > _maxHistorySize) {
      _queryHistory.removeRange(_maxHistorySize, _queryHistory.length);
    }

    await _persistQueryHistory();
    notifyListeners();
  }

  /// 手动保存当前查询（Ctrl+S）。如果相同连接下已存在完全相同的 SQL，则更新该记录。
  Future<void> saveQueryToHistory({
    required String sql,
    required String connectionId,
    String? connectionName,
    String? database,
    DatabaseType? databaseType,
  }) async {
    final trimmedSql = sql.trim();
    if (trimmedSql.isEmpty) return;

    final now = DateTime.now();
    final existingIndex = _queryHistory.indexWhere(
      (h) => h.sql == trimmedSql && h.connectionId == connectionId,
    );

    if (existingIndex >= 0) {
      final existing = _queryHistory[existingIndex];
      _queryHistory[existingIndex] = existing.copyWith(
        updatedAt: now,
        database: database ?? existing.database,
        databaseType: databaseType ?? existing.databaseType,
        connectionName: connectionName ?? existing.connectionName,
      );
      // 移到最前面以反映最近使用
      final updated = _queryHistory.removeAt(existingIndex);
      _queryHistory.insert(0, updated);
    } else {
      final history = QueryHistory(
        id: '${now.millisecondsSinceEpoch}',
        sql: trimmedSql,
        timestamp: now,
        updatedAt: now,
        connectionId: connectionId,
        connectionName: connectionName,
        database: database,
        databaseType: databaseType,
        source: QueryHistorySource.saved,
      );
      _queryHistory.insert(0, history);

      if (_queryHistory.length > _maxHistorySize) {
        _queryHistory.removeRange(_maxHistorySize, _queryHistory.length);
      }
    }

    await _persistQueryHistory();
    notifyListeners();
  }

  Future<void> _persistQueryHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'query_history',
      jsonEncode(_queryHistory.map((h) => h.toJson()).toList()),
    );
  }

  Future<void> clearQueryHistory() async {
    _queryHistory.clear();
    await _persistQueryHistory();
    notifyListeners();
  }

  Future<void> clearQueryHistoryByConnection(String connectionId) async {
    _queryHistory.removeWhere((h) => h.connectionId == connectionId);
    await _persistQueryHistory();
    notifyListeners();
  }

  Future<void> deleteQueryHistory(String id) async {
    _queryHistory.removeWhere((h) => h.id == id);
    await _persistQueryHistory();
    notifyListeners();
  }

  Future<void> renameQueryHistory(String id, String newTitle) async {
    final index = _queryHistory.indexWhere((h) => h.id == id);
    if (index < 0) return;
    final existing = _queryHistory[index];
    _queryHistory[index] = existing.copyWith(
      displayTitle: newTitle.trim(),
      updatedAt: DateTime.now(),
    );
    await _persistQueryHistory();
    notifyListeners();
  }

  // ==================== 查询 ====================

  List<QueryHistory> queryHistoryForConnection(String connectionId) {
    return _queryHistory.where((h) => h.connectionId == connectionId).toList();
  }

  /// Alias for [queryHistoryForConnection] to match feature contract naming.
  List<QueryHistory> getQueryHistoryByConnection(String connectionId) {
    return queryHistoryForConnection(connectionId);
  }

  List<QueryHistory> searchQueryHistory(String query, {String? connectionId}) {
    var list = _queryHistory;
    if (connectionId != null) {
      list = list.where((h) => h.connectionId == connectionId).toList();
    }
    if (query.isEmpty) return list;

    final lowerQuery = query.toLowerCase();
    return list.where((h) {
      final searchable = <String?>[
        h.sql,
        h.displayTitle,
        h.database,
        h.connectionName,
        h.timestamp.toIso8601String(),
      ];
      return searchable.any(
        (field) => field != null && field.toLowerCase().contains(lowerQuery),
      );
    }).toList();
  }

  /// Connection-scoped search helper to match feature contract naming.
  List<QueryHistory> searchQueryHistoryByConnection(
    String connectionId,
    String query,
  ) {
    return searchQueryHistory(query, connectionId: connectionId);
  }

  List<QueryHistory> filterQueryHistoryByDatabase(String? dbName) {
    if (dbName == null) return _queryHistory;
    return _queryHistory.where((h) => h.database == dbName).toList();
  }

  List<QueryHistory> filterQueryHistoryByDate(DateTime date) {
    return _queryHistory
        .where(
          (h) =>
              h.timestamp.year == date.year &&
              h.timestamp.month == date.month &&
              h.timestamp.day == date.day,
        )
        .toList();
  }

  List<QueryHistory> filterQueryHistoryByError(bool hasError) {
    if (hasError) {
      return _queryHistory.where((h) => h.error != null).toList();
    }
    return _queryHistory.where((h) => h.error == null).toList();
  }

  List<QueryHistory> filterQueryHistoryByType(DatabaseType? dbType) {
    if (dbType == null) return _queryHistory;
    return _queryHistory.where((h) => h.databaseType == dbType).toList();
  }

  @override
  void dispose() {
    // No async resources to dispose.
    super.dispose();
  }
}
