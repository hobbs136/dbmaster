import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 最近访问表记录
class RecentTableEntry {
  final String connectionId;
  final String databaseName;
  final String tableName;
  final DateTime accessedAt;

  RecentTableEntry({
    required this.connectionId,
    required this.databaseName,
    required this.tableName,
    required this.accessedAt,
  });

  String get key => '$connectionId:$databaseName:$tableName';

  Map<String, dynamic> toJson() => {
    'connectionId': connectionId,
    'databaseName': databaseName,
    'tableName': tableName,
    'accessedAt': accessedAt.toIso8601String(),
  };

  factory RecentTableEntry.fromJson(Map<String, dynamic> json) =>
      RecentTableEntry(
        connectionId: json['connectionId'] as String,
        databaseName: json['databaseName'] as String,
        tableName: json['tableName'] as String,
        accessedAt: DateTime.parse(json['accessedAt'] as String),
      );
}

/// 最近访问表服务
class RecentTablesService {
  static const String _recentTablesKey = 'recent_tables';
  static const int _maxEntries = 20;

  Future<List<RecentTableEntry>> getRecentTables() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_recentTablesKey);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> list = jsonDecode(jsonString);
      return list
          .map((e) => RecentTableEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> recordTableAccess({
    required String connectionId,
    required String databaseName,
    required String tableName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var entries = await getRecentTables();

    final newEntry = RecentTableEntry(
      connectionId: connectionId,
      databaseName: databaseName,
      tableName: tableName,
      accessedAt: DateTime.now(),
    );

    // 去重：移除同一表的历史记录
    entries.removeWhere(
      (e) =>
          e.connectionId == connectionId &&
          e.databaseName == databaseName &&
          e.tableName == tableName,
    );

    // 新记录插入头部
    entries.insert(0, newEntry);

    // 限制数量
    if (entries.length > _maxEntries) {
      entries = entries.sublist(0, _maxEntries);
    }

    final jsonString = jsonEncode(entries.map((e) => e.toJson()).toList());
    await prefs.setString(_recentTablesKey, jsonString);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_recentTablesKey);
  }

  /// 清除指定连接（及可选数据库）的最近访问记录
  Future<void> clearForConnection(
    String connectionId, {
    String? databaseName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var entries = await getRecentTables();

    entries.removeWhere((e) {
      if (e.connectionId != connectionId) return false;
      if (databaseName != null && e.databaseName != databaseName) return false;
      return true;
    });

    if (entries.isEmpty) {
      await prefs.remove(_recentTablesKey);
    } else {
      final jsonString = jsonEncode(entries.map((e) => e.toJson()).toList());
      await prefs.setString(_recentTablesKey, jsonString);
    }
  }
}
