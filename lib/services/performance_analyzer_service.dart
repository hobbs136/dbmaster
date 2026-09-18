/// Performance Analyzer Service
/// 性能分析服务 - 提供慢查询分析、索引统计、表统计和性能报告生成功能
library;

import 'dart:convert';
import '../utils/app_logger.dart';
import '../models/performance_models.dart';
import 'database_service.dart';

class PerformanceAnalyzerService {
  final DatabaseService _dbService;

  PerformanceAnalyzerService(this._dbService);

  /// 获取当前连接ID
  String? get _currentConnectionId => _dbService.activeConnectionId;

  /// 分析慢查询
  /// [threshold] - 执行时间阈值（秒），默认为1.0秒
  /// [limit] - 返回的查询数量限制
  Future<List<SlowQuery>> analyzeSlowQueries({
    double threshold = 1.0,
    int limit = 100,
  }) async {
    try {
      // 首先检查是否有权限访问 slow_log 表
      final hasSlowLogAccess = await _checkSlowLogAccess();

      if (hasSlowLogAccess) {
        // 从 mysql.slow_log 表获取慢查询
        return await _getSlowQueriesFromTable(threshold, limit);
      } else {
        // 如果没有权限，尝试从 performance_schema 获取
        return await _getSlowQueriesFromPerformanceSchema(threshold, limit);
      }
    } catch (e) {
      AppLogger.d('PerformanceAnalyzer', 'DEBUG: analyzeSlowQueries error: $e');
      // Never surface fabricated "mock" slow queries (trust bug).
      // The inner _checkSlowLogAccess / _getSlowQueries* already swallow errors
      // and return []/false, so this outer catch is rarely reached; but it must
      // not be a landmine that returns fake data if an inner method is ever
      // refactored to throw. Empty is honest; the error is logged above.
      return [];
    }
  }

  /// 检查是否有慢查询日志表访问权限
  Future<bool> _checkSlowLogAccess() async {
    try {
      await _dbService.executeQuery(
        "SELECT 1 FROM mysql.slow_log LIMIT 1",
        connectionId: _currentConnectionId,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 从 mysql.slow_log 表获取慢查询
  Future<List<SlowQuery>> _getSlowQueriesFromTable(
    double threshold,
    int limit,
  ) async {
    try {
      final results = await _dbService.executeQuery('''
        SELECT 
          sql_text as query,
          query_time as execution_time,
          start_time as timestamp,
          db as database_name,
          rows_examined,
          rows_sent,
          user_host
        FROM mysql.slow_log
        WHERE query_time >= $threshold
        ORDER BY start_time DESC
        LIMIT $limit
      ''', connectionId: _currentConnectionId);

      return results
          .map(
            (row) =>
                SlowQuery.fromMap({...row, 'db': row['database_name'] ?? ''}),
          )
          .toList();
    } catch (e) {
      AppLogger.d(
        'PerformanceAnalyzer',
        'DEBUG: _getSlowQueriesFromTable error: $e',
      );
      return [];
    }
  }

  /// 从 performance_schema 获取慢查询
  Future<List<SlowQuery>> _getSlowQueriesFromPerformanceSchema(
    double threshold,
    int limit,
  ) async {
    try {
      // 尝试从 performance_schema.events_statements_history_long 获取
      final results = await _dbService.executeQuery('''
        SELECT 
          DIGEST_TEXT as sql_text,
          AVG_TIMER_WAIT / 1000000000000 as query_time,
          NOW() as start_time,
          SCHEMA_NAME as db,
          ROWS_EXAMINED as rows_examined,
          ROWS_SENT as rows_sent
        FROM performance_schema.events_statements_summary_by_digest
        WHERE AVG_TIMER_WAIT / 1000000000000 >= $threshold
        ORDER BY AVG_TIMER_WAIT DESC
        LIMIT $limit
      ''', connectionId: _currentConnectionId);

      return results.map((row) => SlowQuery.fromMap(row)).toList();
    } catch (e) {
      AppLogger.d(
        'PerformanceAnalyzer',
        'DEBUG: _getSlowQueriesFromPerformanceSchema error: $e',
      );
      return [];
    }
  }

  /// 获取指定表的索引使用情况
  Future<List<IndexUsage>> getIndexUsage(String tableName) async {
    try {
      // 获取表的索引统计信息
      final results = await _dbService.executeQuery('''
        SELECT 
          TABLE_NAME,
          INDEX_NAME,
          CARDINALITY,
          NON_UNIQUE,
          GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) as column_list
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() 
          AND TABLE_NAME = '$tableName'
        GROUP BY TABLE_NAME, INDEX_NAME, CARDINALITY, NON_UNIQUE
        ORDER BY INDEX_NAME
      ''', connectionId: _currentConnectionId);

      // 尝试获取索引使用统计（如果 performance_schema 可用）
      Map<String, int> usageStats = {};
      try {
        final usageResults = await _dbService.executeQuery('''
          SELECT 
            OBJECT_NAME as table_name,
            INDEX_NAME,
            COUNT_READ as usage_count
          FROM performance_schema.table_io_waits_summary_by_index_usage
          WHERE OBJECT_SCHEMA = DATABASE()
            AND OBJECT_NAME = '$tableName'
        ''', connectionId: _currentConnectionId);

        for (final row in usageResults) {
          final key = '${row['table_name']}.${row['INDEX_NAME']}';
          usageStats[key] =
              int.tryParse(row['usage_count']?.toString() ?? '0') ?? 0;
        }
      } catch (e) {
        AppLogger.d(
          'PerformanceAnalyzer',
          'DEBUG: Performance schema not available for index usage: $e',
        );
      }

      return results.map((row) {
        final key = '${row['TABLE_NAME']}.${row['INDEX_NAME']}';
        final usageCount = usageStats[key] ?? 0;
        return IndexUsage.fromMap({...row, 'usage_count': usageCount});
      }).toList();
    } catch (e) {
      AppLogger.d('PerformanceAnalyzer', 'DEBUG: getIndexUsage error: $e');
      return [];
    }
  }

  /// 获取所有索引使用情况
  Future<List<IndexUsage>> getAllIndexUsage() async {
    try {
      final results = await _dbService.executeQuery('''
        SELECT 
          TABLE_NAME,
          INDEX_NAME,
          CARDINALITY,
          NON_UNIQUE,
          GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) as column_list
        FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
        GROUP BY TABLE_NAME, INDEX_NAME, CARDINALITY, NON_UNIQUE
        ORDER BY TABLE_NAME, INDEX_NAME
      ''', connectionId: _currentConnectionId);

      return results
          .map(
            (row) => IndexUsage.fromMap({
              ...row,
              'usage_count': 0, // 默认未知使用情况
            }),
          )
          .toList();
    } catch (e) {
      AppLogger.d('PerformanceAnalyzer', 'DEBUG: getAllIndexUsage error: $e');
      return [];
    }
  }

  /// 检测未使用的索引
  Future<List<IndexUsage>> findUnusedIndexes() async {
    try {
      final results = await _dbService.executeQuery('''
        SELECT 
          s.TABLE_NAME,
          s.INDEX_NAME,
          s.CARDINALITY,
          s.NON_UNIQUE,
          GROUP_CONCAT(s.COLUMN_NAME ORDER BY s.SEQ_IN_INDEX) as column_list,
          IFNULL(p.COUNT_READ, 0) as usage_count
        FROM information_schema.STATISTICS s
        LEFT JOIN performance_schema.table_io_waits_summary_by_index_usage p
          ON s.TABLE_SCHEMA = p.OBJECT_SCHEMA 
          AND s.TABLE_NAME = p.OBJECT_NAME 
          AND s.INDEX_NAME = p.INDEX_NAME
        WHERE s.TABLE_SCHEMA = DATABASE()
          AND s.INDEX_NAME != 'PRIMARY'
          AND IFNULL(p.COUNT_READ, 0) = 0
        GROUP BY s.TABLE_NAME, s.INDEX_NAME, s.CARDINALITY, s.NON_UNIQUE
        ORDER BY s.TABLE_NAME, s.INDEX_NAME
      ''', connectionId: _currentConnectionId);

      return results.map((row) => IndexUsage.fromMap(row)).toList();
    } catch (e) {
      AppLogger.d('PerformanceAnalyzer', 'DEBUG: findUnusedIndexes error: $e');
      return [];
    }
  }

  /// 建议添加的索引
  Future<List<PerformanceSuggestion>> suggestIndexes() async {
    final suggestions = <PerformanceSuggestion>[];

    try {
      // 获取没有主键的表
      final noPKResults = await _dbService.executeQuery('''
        SELECT 
          t.TABLE_NAME,
          t.TABLE_ROWS,
          t.ENGINE
        FROM information_schema.TABLES t
        LEFT JOIN information_schema.KEY_COLUMN_USAGE k
          ON t.TABLE_SCHEMA = k.TABLE_SCHEMA 
          AND t.TABLE_NAME = k.TABLE_NAME 
          AND k.CONSTRAINT_NAME = 'PRIMARY'
        WHERE t.TABLE_SCHEMA = DATABASE()
          AND t.TABLE_TYPE = 'BASE TABLE'
          AND k.COLUMN_NAME IS NULL
        ORDER BY t.TABLE_ROWS DESC
      ''', connectionId: _currentConnectionId);

      for (final row in noPKResults) {
        final rowCount =
            int.tryParse(row['TABLE_ROWS']?.toString() ?? '0') ?? 0;
        if (rowCount > 1000) {
          suggestions.add(
            PerformanceSuggestion(
              type: 'table',
              title: '缺少主键',
              description:
                  '表 ${row['TABLE_NAME']} 有 $rowCount 行数据但没有主键，这会影响查询性能和数据完整性。',
              impact: 'high',
              affectedTables: [row['TABLE_NAME']?.toString() ?? ''],
              recommendation:
                  '建议为表添加一个自增主键列：ALTER TABLE `${row['TABLE_NAME']}` ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY;',
            ),
          );
        }
      }

      // 获取大表但没有足够索引的
      final largeTableResults = await _dbService.executeQuery('''
        SELECT 
          t.TABLE_NAME,
          t.TABLE_ROWS,
          COUNT(DISTINCT s.INDEX_NAME) as index_count
        FROM information_schema.TABLES t
        LEFT JOIN information_schema.STATISTICS s
          ON t.TABLE_SCHEMA = s.TABLE_SCHEMA 
          AND t.TABLE_NAME = s.TABLE_NAME
        WHERE t.TABLE_SCHEMA = DATABASE()
          AND t.TABLE_TYPE = 'BASE TABLE'
          AND t.TABLE_ROWS > 10000
        GROUP BY t.TABLE_NAME, t.TABLE_ROWS
        HAVING index_count <= 2
      ''', connectionId: _currentConnectionId);

      for (final row in largeTableResults) {
        final rowCount =
            int.tryParse(row['TABLE_ROWS']?.toString() ?? '0') ?? 0;
        final indexCount =
            int.tryParse(row['index_count']?.toString() ?? '0') ?? 0;
        suggestions.add(
          PerformanceSuggestion(
            type: 'index',
            title: '索引不足',
            description:
                '表 ${row['TABLE_NAME']} 有 $rowCount 行数据但只有 $indexCount 个索引。',
            impact: 'medium',
            affectedTables: [row['TABLE_NAME']?.toString() ?? ''],
            recommendation: '建议分析常用的查询条件，为 WHERE、JOIN 和 ORDER BY 子句中的列添加索引。',
          ),
        );
      }

      return suggestions;
    } catch (e) {
      AppLogger.d('PerformanceAnalyzer', 'DEBUG: suggestIndexes error: $e');
      return suggestions;
    }
  }

  /// 获取表统计信息
  Future<List<TableStatistics>> getTableStatistics() async {
    try {
      final results = await _dbService.executeQuery('''
        SELECT 
          TABLE_NAME,
          TABLE_ROWS,
          DATA_LENGTH,
          INDEX_LENGTH,
          UPDATE_TIME,
          ENGINE,
          TABLE_COLLATION,
          AUTO_INCREMENT,
          CREATE_TIME,
          AVG_ROW_LENGTH
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_TYPE = 'BASE TABLE'
        ORDER BY DATA_LENGTH + INDEX_LENGTH DESC
      ''', connectionId: _currentConnectionId);

      return results.map((row) => TableStatistics.fromMap(row)).toList();
    } catch (e) {
      AppLogger.d('PerformanceAnalyzer', 'DEBUG: getTableStatistics error: $e');
      return [];
    }
  }

  /// 获取数据库汇总信息
  Future<DatabaseSummary> getDatabaseSummary() async {
    try {
      final results = await _dbService.executeQuery('''
        SELECT 
          SUM(TABLE_ROWS) as total_rows,
          SUM(DATA_LENGTH) as total_data,
          SUM(INDEX_LENGTH) as total_index,
          COUNT(*) as table_count
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_TYPE = 'BASE TABLE'
      ''', connectionId: _currentConnectionId);

      if (results.isNotEmpty) {
        return DatabaseSummary.fromMap(results.first);
      }
    } catch (e) {
      AppLogger.d('PerformanceAnalyzer', 'DEBUG: getDatabaseSummary error: $e');
    }
    return DatabaseSummary();
  }

  /// 获取查询执行计划
  Future<List<QueryExecutionPlan>> getExecutionPlan(String query) async {
    try {
      // 移除查询中的分号以避免语法错误
      final cleanQuery = query.replaceAll(';', '');
      final results = await _dbService.executeQuery(
        'EXPLAIN $cleanQuery',
        connectionId: _currentConnectionId,
      );

      return results.map((row) => QueryExecutionPlan.fromMap(row)).toList();
    } catch (e) {
      AppLogger.d('PerformanceAnalyzer', 'DEBUG: getExecutionPlan error: $e');
      return [];
    }
  }

  /// 生成性能报告
  Future<PerformanceReport> generateReport() async {
    final stopwatch = Stopwatch()..start();

    // 并行获取所有数据
    final results = await Future.wait([
      getTableStatistics(),
      getAllIndexUsage(),
      analyzeSlowQueries(threshold: 0.5, limit: 50),
      suggestIndexes(),
      getDatabaseSummary(),
    ]);

    stopwatch.stop();
    AppLogger.d(
      'PerformanceAnalyzer',
      'DEBUG: Performance report generated in ${stopwatch.elapsedMilliseconds}ms',
    );

    final currentDatabase = await _getCurrentDatabase();

    return PerformanceReport(
      generatedAt: DateTime.now(),
      databaseName: currentDatabase,
      tableStats: results[0] as List<TableStatistics>,
      indexUsage: results[1] as List<IndexUsage>,
      slowQueries: results[2] as List<SlowQuery>,
      suggestions: results[3] as List<PerformanceSuggestion>,
      summary: results[4] as DatabaseSummary,
    );
  }

  /// 获取当前数据库名称
  Future<String> _getCurrentDatabase() async {
    try {
      final result = await _dbService.executeQuery(
        'SELECT DATABASE() as db',
        connectionId: _currentConnectionId,
      );
      if (result.isNotEmpty) {
        return result.first['db']?.toString() ?? 'unknown';
      }
    } catch (e) {
      AppLogger.d(
        'PerformanceAnalyzer',
        'DEBUG: _getCurrentDatabase error: $e',
      );
    }
    return 'unknown';
  }

  /// 导出报告为JSON
  String exportReportToJson(PerformanceReport report) {
    final data = {
      'generatedAt': report.generatedAt.toIso8601String(),
      'databaseName': report.databaseName,
      'summary': {
        'totalTables': report.tableStats.length,
        'totalRows': report.summary.totalRows,
        'totalDataSize': report.summary.totalDataSizeFormatted,
        'totalIndexSize': report.summary.totalIndexSizeFormatted,
        'slowQueryCount': report.slowQueries.length,
        'suggestionCount': report.suggestions.length,
      },
      'tables': report.tableStats
          .map(
            (t) => {
              'name': t.tableName,
              'rows': t.rowCount,
              'dataSize': t.dataSizeFormatted,
              'indexSize': t.indexSizeFormatted,
              'engine': t.engine,
            },
          )
          .toList(),
      'slowQueries': report.slowQueries
          .map(
            (q) => {
              'query': q.query,
              'executionTime': q.executionTime,
              'database': q.database,
              'rowsExamined': q.rowsExamined,
              'timestamp': q.timestamp.toIso8601String(),
            },
          )
          .toList(),
      'suggestions': report.suggestions
          .map(
            (s) => {
              'type': s.type,
              'title': s.title,
              'description': s.description,
              'impact': s.impact,
              'recommendation': s.recommendation,
            },
          )
          .toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 导出报告为Markdown
  String exportReportToMarkdown(PerformanceReport report) {
    final buffer = StringBuffer();

    buffer.writeln('# 数据库性能分析报告');
    buffer.writeln('');
    buffer.writeln('**数据库**: ${report.databaseName}  ');
    buffer.writeln('**生成时间**: ${report.generatedAt.toString()}  ');
    buffer.writeln('');

    // 汇总
    buffer.writeln('## 汇总');
    buffer.writeln('');
    buffer.writeln('- 表数量: ${report.tableStats.length}');
    buffer.writeln('- 总行数: ${report.summary.totalRows}');
    buffer.writeln('- 数据大小: ${report.summary.totalDataSizeFormatted}');
    buffer.writeln('- 索引大小: ${report.summary.totalIndexSizeFormatted}');
    buffer.writeln('- 慢查询数量: ${report.slowQueries.length}');
    buffer.writeln('- 优化建议: ${report.suggestions.length} 条');
    buffer.writeln('');

    // 表统计
    buffer.writeln('## 表统计');
    buffer.writeln('');
    buffer.writeln('| 表名 | 行数 | 数据大小 | 索引大小 | 引擎 |');
    buffer.writeln('|------|------|----------|----------|------|');
    for (final table in report.tableStats.take(20)) {
      buffer.writeln(
        '| ${table.tableName} | ${table.rowCount} | ${table.dataSizeFormatted} | ${table.indexSizeFormatted} | ${table.engine} |',
      );
    }
    buffer.writeln('');

    // 慢查询
    if (report.slowQueries.isNotEmpty) {
      buffer.writeln('## 慢查询 Top 10');
      buffer.writeln('');
      for (var i = 0; i < report.slowQueries.take(10).length; i++) {
        final query = report.slowQueries[i];
        buffer.writeln(
          '### ${i + 1}. ${query.executionTime.toStringAsFixed(2)}s',
        );
        buffer.writeln('');
        buffer.writeln('```sql');
        buffer.writeln(query.query);
        buffer.writeln('```');
        buffer.writeln('');
        if (query.rowsExamined != null) {
          buffer.writeln('- 扫描行数: ${query.rowsExamined}');
        }
        if (query.executionPlan != null) {
          buffer.writeln('- 执行计划: ${query.executionPlan}');
        }
        buffer.writeln('');
      }
    }

    // 优化建议
    if (report.suggestions.isNotEmpty) {
      buffer.writeln('## 优化建议');
      buffer.writeln('');
      for (var i = 0; i < report.suggestions.length; i++) {
        final suggestion = report.suggestions[i];
        buffer.writeln(
          '### ${i + 1}. [${suggestion.impact.toUpperCase()}] ${suggestion.title}',
        );
        buffer.writeln('');
        buffer.writeln(suggestion.description);
        buffer.writeln('');
        if (suggestion.recommendation != null) {
          buffer.writeln('**建议**: ${suggestion.recommendation}');
          buffer.writeln('');
        }
      }
    }

    return buffer.toString();
  }
}
