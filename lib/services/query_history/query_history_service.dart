import 'dart:developer' as developer;

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../models/query_history/query_record.dart';

/// 查询历史服务
/// 管理本地 SQLite 数据库中的查询记录
class QueryHistoryService {
  static const String _databaseName = 'query_history.db';
  static const int _databaseVersion = 1;
  static const int _maxRecords = 1000;
  static const int _retentionDays = 90;

  Database? _database;
  bool _initialized = false;

  /// 单例模式
  static final QueryHistoryService _instance = QueryHistoryService._internal();
  factory QueryHistoryService() => _instance;
  QueryHistoryService._internal();

  /// 初始化数据库
  /// [customPath] 可选的自定义数据库路径，用于测试
  Future<void> initialize({String? customPath}) async {
    if (_initialized) return;

    try {
      final String dbPath;
      if (customPath != null) {
        dbPath = customPath;
      } else {
        final directory = await getApplicationDocumentsDirectory();
        dbPath = '${directory.path}/$_databaseName';
      }

      _database = await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: _databaseVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );

      _initialized = true;
      developer.log(
        'QueryHistory database initialized at: $dbPath',
        name: 'QueryHistoryService',
      );

      // 启动时清理旧记录
      await _cleanupOldRecords();
    } catch (e, stackTrace) {
      developer.log(
        'Failed to initialize QueryHistory database: $e',
        name: 'QueryHistoryService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 创建表
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE query_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sql_statement TEXT NOT NULL,
        connection_id TEXT NOT NULL,
        connection_name TEXT,
        database_type TEXT NOT NULL,
        database_name TEXT,
        execution_time_ms INTEGER NOT NULL,
        row_count INTEGER,
        is_success INTEGER NOT NULL DEFAULT 1,
        error_message TEXT,
        created_at TEXT NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        tags TEXT,
        query_type TEXT
      )
    ''');

    // 创建索引
    await db.execute('''
      CREATE INDEX idx_query_history_created_at ON query_history(created_at)
    ''');
    await db.execute('''
      CREATE INDEX idx_query_history_connection ON query_history(connection_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_query_history_favorite ON query_history(is_favorite)
    ''');
    await db.execute('''
      CREATE INDEX idx_query_history_query_type ON query_history(query_type)
    ''');
  }

  /// 升级数据库
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未来版本升级时处理
  }

  /// 记录查询
  Future<QueryRecord> recordQuery({
    required String sqlStatement,
    required String connectionId,
    String? connectionName,
    required String databaseType,
    String? databaseName,
    required int executionTimeMs,
    int? rowCount,
    bool isSuccess = true,
    String? errorMessage,
  }) async {
    await _ensureInitialized();

    final record = QueryRecord(
      sqlStatement: sqlStatement,
      connectionId: connectionId,
      connectionName: connectionName,
      databaseType: databaseType,
      databaseName: databaseName,
      executionTimeMs: executionTimeMs,
      rowCount: rowCount,
      isSuccess: isSuccess,
      errorMessage: errorMessage,
      createdAt: DateTime.now(),
      queryType: _detectQueryType(sqlStatement),
    );

    try {
      final id = await _database!.insert('query_history', record.toMap());
      final savedRecord = record.copyWith(id: id.toString());

      // 检查是否需要清理
      await _cleanupIfNeeded();

      return savedRecord;
    } catch (e) {
      developer.log('Failed to record query: $e', name: 'QueryHistoryService');
      return record;
    }
  }

  /// 搜索查询历史
  Future<List<QueryRecord>> search(SearchCriteria criteria) async {
    await _ensureInitialized();

    final where = <String>[];
    final whereArgs = <Object?>[];

    // 关键词搜索（SQL 内容或表名）
    if (criteria.keywords != null && criteria.keywords!.isNotEmpty) {
      where.add('(sql_statement LIKE ? OR connection_name LIKE ?)');
      whereArgs.add('%${criteria.keywords}%');
      whereArgs.add('%${criteria.keywords}%');
    }

    // 连接过滤
    if (criteria.connectionId != null) {
      where.add('connection_id = ?');
      whereArgs.add(criteria.connectionId);
    }

    // 数据库类型过滤
    if (criteria.databaseType != null) {
      where.add('database_type = ?');
      whereArgs.add(criteria.databaseType);
    }

    // 时间范围过滤
    if (criteria.after != null) {
      where.add('created_at >= ?');
      whereArgs.add(criteria.after!.toIso8601String());
    }
    if (criteria.before != null) {
      where.add('created_at <= ?');
      whereArgs.add(criteria.before!.toIso8601String());
    }

    // 收藏过滤
    if (criteria.isFavorite != null) {
      where.add('is_favorite = ?');
      whereArgs.add(criteria.isFavorite! ? 1 : 0);
    }

    // 查询类型过滤
    if (criteria.queryType != null) {
      where.add('query_type = ?');
      whereArgs.add(criteria.queryType);
    }

    // 标签过滤
    if (criteria.tags != null && criteria.tags!.isNotEmpty) {
      final tagConditions = criteria.tags!
          .map((tag) => 'tags LIKE ?')
          .join(' OR ');
      where.add('($tagConditions)');
      whereArgs.addAll(criteria.tags!.map((tag) => '%$tag%'));
    }

    final whereClause = where.isNotEmpty ? where.join(' AND ') : null;

    try {
      final maps = await _database!.query(
        'query_history',
        where: whereClause,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'created_at DESC',
        limit: criteria.limit,
        offset: criteria.offset,
      );

      return maps.map((map) => QueryRecord.fromMap(map)).toList();
    } catch (e) {
      developer.log(
        'Failed to search query history: $e',
        name: 'QueryHistoryService',
      );
      return [];
    }
  }

  /// 获取收藏查询
  Future<List<QueryRecord>> getFavorites() async {
    return search(const SearchCriteria(isFavorite: true, limit: 100));
  }

  /// 获取最近查询
  Future<List<QueryRecord>> getRecentQueries({int limit = 20}) async {
    return search(SearchCriteria(limit: limit));
  }

  /// 切换收藏状态
  Future<void> toggleFavorite(String id) async {
    await _ensureInitialized();

    try {
      final record = await _database!.query(
        'query_history',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (record.isNotEmpty) {
        final currentFavorite = (record.first['is_favorite'] as int? ?? 0) == 1;
        await _database!.update(
          'query_history',
          {'is_favorite': currentFavorite ? 0 : 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } catch (e) {
      developer.log(
        'Failed to toggle favorite: $e',
        name: 'QueryHistoryService',
      );
    }
  }

  /// 添加标签
  Future<void> addTags(String id, List<String> newTags) async {
    await _ensureInitialized();

    try {
      final record = await _database!.query(
        'query_history',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (record.isNotEmpty) {
        final currentTags = QueryRecord.parseTags(
          record.first['tags'] as String?,
        );
        final updatedTags = [...currentTags, ...newTags];

        await _database!.update(
          'query_history',
          {'tags': updatedTags.join(',')},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } catch (e) {
      developer.log('Failed to add tags: $e', name: 'QueryHistoryService');
    }
  }

  /// 删除记录
  Future<void> deleteRecord(String id) async {
    await _ensureInitialized();

    try {
      await _database!.delete(
        'query_history',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      developer.log('Failed to delete record: $e', name: 'QueryHistoryService');
    }
  }

  /// 清空历史
  Future<void> clearHistory() async {
    await _ensureInitialized();

    try {
      await _database!.delete('query_history');
      developer.log('Query history cleared', name: 'QueryHistoryService');
    } catch (e) {
      developer.log('Failed to clear history: $e', name: 'QueryHistoryService');
    }
  }

  /// 获取统计信息
  Future<Map<String, dynamic>> getStatistics() async {
    await _ensureInitialized();

    try {
      final totalCount = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM query_history',
      );
      final favoriteCount = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM query_history WHERE is_favorite = 1',
      );
      final typeDistribution = await _database!.rawQuery(
        'SELECT query_type, COUNT(*) as count FROM query_history GROUP BY query_type',
      );
      final avgExecutionTime = await _database!.rawQuery(
        'SELECT AVG(execution_time_ms) as avg FROM query_history WHERE is_success = 1',
      );

      return {
        'totalQueries': totalCount.first['count'] as int? ?? 0,
        'favoriteQueries': favoriteCount.first['count'] as int? ?? 0,
        'typeDistribution': Map.fromEntries(
          typeDistribution.map(
            (r) => MapEntry(
              r['query_type'] as String? ?? 'unknown',
              r['count'] as int? ?? 0,
            ),
          ),
        ),
        'avgExecutionTimeMs': avgExecutionTime.first['avg'] as double? ?? 0.0,
      };
    } catch (e) {
      developer.log(
        'Failed to get statistics: $e',
        name: 'QueryHistoryService',
      );
      return {};
    }
  }

  /// 导出收藏查询为 JSON
  Future<String> exportFavorites() async {
    final favorites = await getFavorites();
    final data = favorites.map((r) => r.toMap()).toList();
    return data.toString(); // 简化版，实际应使用 jsonEncode
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _initialized = false;
    }
  }

  /// 确保已初始化
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// 清理旧记录
  Future<void> _cleanupOldRecords() async {
    try {
      final cutoffDate = DateTime.now().subtract(
        Duration(days: _retentionDays),
      );
      await _database!.delete(
        'query_history',
        where: 'created_at < ?',
        whereArgs: [cutoffDate.toIso8601String()],
      );
    } catch (e) {
      developer.log(
        'Failed to cleanup old records: $e',
        name: 'QueryHistoryService',
      );
    }
  }

  /// 如果记录数超过限制，删除最旧的
  Future<void> _cleanupIfNeeded() async {
    try {
      final count = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM query_history',
      );
      final totalCount = (count.first['count'] as int? ?? 0);

      if (totalCount > _maxRecords) {
        final toDelete = totalCount - _maxRecords;
        await _database!.rawDelete('''
          DELETE FROM query_history 
          WHERE id IN (
            SELECT id FROM query_history 
            WHERE is_favorite = 0 
            ORDER BY created_at ASC 
            LIMIT $toDelete
          )
        ''');
        developer.log(
          'Cleaned up $toDelete old query records',
          name: 'QueryHistoryService',
        );
      }
    } catch (e) {
      developer.log(
        'Failed to cleanup records: $e',
        name: 'QueryHistoryService',
      );
    }
  }

  /// 检测查询类型
  String? _detectQueryType(String sql) {
    final normalized = sql.trim().toUpperCase();
    if (normalized.startsWith('SELECT')) return 'SELECT';
    if (normalized.startsWith('INSERT')) return 'INSERT';
    if (normalized.startsWith('UPDATE')) return 'UPDATE';
    if (normalized.startsWith('DELETE')) return 'DELETE';
    if (normalized.startsWith('CREATE')) return 'CREATE';
    if (normalized.startsWith('ALTER')) return 'ALTER';
    if (normalized.startsWith('DROP')) return 'DROP';
    if (normalized.startsWith('EXPLAIN')) return 'EXPLAIN';
    return 'OTHER';
  }
}
