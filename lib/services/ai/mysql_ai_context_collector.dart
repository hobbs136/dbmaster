import '../../services/database_service.dart';
import '../../utils/app_logger.dart';
import 'ai_service_localizations.dart';

/// MySQL/Doris 专用 AI 上下文收集器。
///
/// 设计原则：
/// - 只收集元数据，不读取表内真实数据行。
/// - 行数使用 `SHOW TABLE STATUS` / `INFORMATION_SCHEMA.TABLES` 的近似统计，
///   避免大表执行 `SELECT COUNT(*)` 导致全表扫描。
class MysqlAiContextCollector {
  final DatabaseService dbService;

  MysqlAiContextCollector(this.dbService);

  /// 收集表级上下文（结构、近似行数、索引）。
  Future<String> collectTableContext(
    String connectionId,
    String databaseName,
    String tableName, {
    String locale = 'en',
  }) async {
    final l = AiServiceLocalizations(locale);
    final buffer = StringBuffer();
    buffer.writeln(l.mysqlContextDbTypeMysql);
    buffer.writeln(l.contextCurrentDatabase(databaseName));
    buffer.writeln(l.mysqlContextTargetTable(tableName));

    // 1. Schema 摘要（列 + 索引）
    final adapter = dbService.getAdapter(connectionId);
    if (adapter != null) {
      try {
        final schemaSummary = await adapter.getAiSchemaSummary(
          target: tableName,
          databaseName: databaseName,
          locale: locale,
        );
        buffer.writeln('\n$schemaSummary');
      } catch (e) {
        AppLogger.d('MysqlAiContextCollector', 'Schema summary failed: $e');
        buffer.writeln(l.mysqlContextSchemaSummaryFailed(e.toString()));
      }
    }

    // 2. 近似行数（SHOW TABLE STATUS，不扫描全表）
    try {
      final statusRows = await dbService.executeQuery(
        "SHOW TABLE STATUS LIKE '${_escapeLike(tableName)}'",
        connectionId: connectionId,
        database: databaseName,
      );
      if (statusRows.isNotEmpty) {
        final row = statusRows.first;
        final rows = row['Rows'];
        final dataLength = row['Data_length'];
        final indexLength = row['Index_length'];
        final engine = row['Engine'];
        final collation = row['Collation'];
        buffer.writeln(l.mysqlContextTableStatsHeader);
        buffer.writeln(l.mysqlContextEngine(engine ?? 'N/A'));
        buffer.writeln(l.mysqlContextApproxRows(rows ?? 'N/A'));
        buffer.writeln(l.mysqlContextDataSize(_formatBytes(dataLength)));
        buffer.writeln(l.mysqlContextIndexSize(_formatBytes(indexLength)));
        buffer.writeln(l.mysqlContextCollation(collation ?? 'N/A'));
      }
    } catch (e) {
      AppLogger.d('MysqlAiContextCollector', 'Table status failed: $e');
    }

    // 3. 执行计划（EXPLAIN，只返回执行计划不执行查询）
    try {
      final explainRows = await dbService.executeQuery(
        'EXPLAIN SELECT * FROM `${_escapeIdentifier(tableName)}`',
        connectionId: connectionId,
        database: databaseName,
      );
      if (explainRows.isNotEmpty) {
        buffer.writeln(l.mysqlContextExplainHeader);
        for (final row in explainRows) {
          buffer.writeln('  ${row.toString()}');
        }
      }
    } catch (e) {
      AppLogger.d('MysqlAiContextCollector', 'EXPLAIN failed: $e');
    }

    return buffer.toString();
  }

  /// 收集数据库级上下文（表列表 + 各表近似行数）。
  Future<String> collectDatabaseContext(
    String connectionId,
    String databaseName, {
    String locale = 'en',
  }) async {
    final l = AiServiceLocalizations(locale);
    final buffer = StringBuffer();
    buffer.writeln(l.mysqlContextDbTypeMysql);
    buffer.writeln(l.contextCurrentDatabase(databaseName));

    try {
      final rows = await dbService.executeQuery(
        "SELECT TABLE_NAME, TABLE_ROWS, DATA_LENGTH, INDEX_LENGTH, ENGINE "
        "FROM INFORMATION_SCHEMA.TABLES "
        "WHERE TABLE_SCHEMA = '${_escapeString(databaseName)}' "
        "ORDER BY TABLE_NAME",
        connectionId: connectionId,
        database: databaseName,
      );

      buffer.writeln(l.mysqlContextTableListHeader);
      if (rows.isEmpty) {
        buffer.writeln(l.mysqlContextNoTables);
      } else {
        for (final row in rows) {
          final name = row['TABLE_NAME'];
          final tableRows = row['TABLE_ROWS'];
          final dataLen = row['DATA_LENGTH'];
          final idxLen = row['INDEX_LENGTH'];
          final engine = row['ENGINE'];
          buffer.writeln(
            l.mysqlContextTableRow(
              '$name',
              '$tableRows',
              _formatBytes(dataLen),
              _formatBytes(idxLen),
              '$engine',
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.d('MysqlAiContextCollector', 'Database context failed: $e');
      buffer.writeln(l.mysqlContextDatabaseStatsFailed(e.toString()));
    }

    return buffer.toString();
  }

  /// 收集连接/服务器级上下文（关键状态与配置）。
  Future<String> collectServerContext(
    String connectionId, {
    String locale = 'en',
  }) async {
    final l = AiServiceLocalizations(locale);
    final buffer = StringBuffer();
    buffer.writeln(l.mysqlContextDbTypeMysql);

    const statusVars = [
      'Threads_connected',
      'Threads_running',
      'Queries',
      'Slow_queries',
      'Uptime',
      'Innodb_buffer_pool_size',
      'Max_used_connections',
    ];
    const variableVars = [
      'version',
      'max_connections',
      'innodb_buffer_pool_size',
      'character_set_server',
      'collation_server',
      'sql_mode',
    ];

    try {
      final statusRows = await dbService.executeQuery(
        "SHOW GLOBAL STATUS WHERE Variable_name IN (${statusVars.map(_quoteString).join(',')})",
        connectionId: connectionId,
      );
      buffer.writeln(l.mysqlContextServerStatusHeader);
      for (final row in statusRows) {
        buffer.writeln('  ${row['Variable_name']}: ${row['Value']}');
      }
    } catch (e) {
      AppLogger.d('MysqlAiContextCollector', 'Server status failed: $e');
    }

    try {
      final varRows = await dbService.executeQuery(
        "SHOW GLOBAL VARIABLES WHERE Variable_name IN (${variableVars.map(_quoteString).join(',')})",
        connectionId: connectionId,
      );
      buffer.writeln(l.mysqlContextServerVariablesHeader);
      for (final row in varRows) {
        buffer.writeln('  ${row['Variable_name']}: ${row['Value']}');
      }
    } catch (e) {
      AppLogger.d('MysqlAiContextCollector', 'Server variables failed: $e');
    }

    return buffer.toString();
  }

  static String _escapeIdentifier(String identifier) {
    return identifier.replaceAll('`', '``');
  }

  static String _escapeString(String value) {
    return value.replaceAll("'", "''");
  }

  static String _escapeLike(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }

  static String _quoteString(String value) => "'$value'";

  static String _formatBytes(Object? bytes) {
    final b = bytes is int
        ? bytes
        : int.tryParse(bytes?.toString() ?? '0') ?? 0;
    if (b >= 1073741824) return '${(b / 1073741824).toStringAsFixed(1)} GB';
    if (b >= 1048576) return '${(b / 1048576).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }
}
