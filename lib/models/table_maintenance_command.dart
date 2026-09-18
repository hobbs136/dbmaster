import 'package:dbmaster/utils/sql_escape_utils.dart';

import 'database_models.dart';

/// 表维护命令枚举（MySQL/Doris + PostgreSQL）。
///
/// MySQL/Doris 命令：
/// - [analyze]  -> ANALYZE TABLE
/// - [optimize] -> OPTIMIZE TABLE
/// - [check]    -> CHECK TABLE
///
/// PostgreSQL 命令：
/// - [vacuum]              -> VACUUM
/// - [vacuumFull]          -> VACUUM FULL
/// - [pgAnalyze]           -> ANALYZE（与 MySQL analyze 区分）
/// - [reindex]             -> REINDEX TABLE
/// - [reindexConcurrently] -> REINDEX TABLE CONCURRENTLY
/// - [cluster]             -> CLUSTER
///
/// PG 命令的 SQL 关键字与 MySQL 语法差异较大，buildSql() 按 dbType 分支。
enum TableMaintenanceCommand {
  // MySQL/Doris
  analyze,
  optimize,
  check,

  // PostgreSQL
  vacuum,
  vacuumFull,
  pgAnalyze,
  reindex,
  reindexConcurrently,
  cluster;

  /// 是否为 PostgreSQL 专属维护命令。
  bool get isPostgreSql => switch (this) {
    vacuum ||
    vacuumFull ||
    pgAnalyze ||
    reindex ||
    reindexConcurrently ||
    cluster => true,
    _ => false,
  };

  /// 命令的 SQL 关键字（大写）。
  String get sqlKeyword {
    switch (this) {
      case TableMaintenanceCommand.analyze:
        return 'ANALYZE';
      case TableMaintenanceCommand.optimize:
        return 'OPTIMIZE';
      case TableMaintenanceCommand.check:
        return 'CHECK';
      case TableMaintenanceCommand.vacuum:
        return 'VACUUM';
      case TableMaintenanceCommand.vacuumFull:
        return 'VACUUM FULL';
      case TableMaintenanceCommand.pgAnalyze:
        return 'ANALYZE';
      case TableMaintenanceCommand.reindex:
        return 'REINDEX';
      case TableMaintenanceCommand.reindexConcurrently:
        return 'REINDEX CONCURRENTLY';
      case TableMaintenanceCommand.cluster:
        return 'CLUSTER';
    }
  }

  /// 构建完整的维护 SQL 语句。
  ///
  /// MySQL 示例（反引号转义）：
  /// ```dart
  /// TableMaintenanceCommand.analyze.buildSql('my_db', 'my_table');
  /// // => 'ANALYZE TABLE `my_db`.`my_table`'
  /// ```
  ///
  /// PostgreSQL 示例（双引号转义，不带 db 前缀）：
  /// ```dart
  /// TableMaintenanceCommand.vacuum.buildSql('public', 'my_table', dbType: DatabaseType.postgresql);
  /// // => 'VACUUM "my_table"'
  /// ```
  String buildSql(
    String databaseName,
    String tableName, {
    DatabaseType dbType = DatabaseType.mysql,
  }) {
    if (dbType == DatabaseType.postgresql) {
      return _buildPostgreSql(tableName);
    }
    return _buildMySql(databaseName, tableName);
  }

  String _buildMySql(String databaseName, String tableName) {
    final quotedDb = _quoteMySql(databaseName);
    final quotedTable = _quoteMySql(tableName);
    return '$sqlKeyword TABLE $quotedDb.$quotedTable';
  }

  String _buildPostgreSql(String tableName) {
    final quoted = SqlEscapeUtils.escapePgIdentifier(tableName);
    // REINDEX 和 REINDEX CONCURRENTLY 需要 TABLE 关键字在中间
    if (this == TableMaintenanceCommand.reindex) {
      return 'REINDEX TABLE $quoted';
    }
    if (this == TableMaintenanceCommand.reindexConcurrently) {
      return 'REINDEX TABLE CONCURRENTLY $quoted';
    }
    // VACUUM / VACUUM FULL / ANALYZE / CLUSTER 直接跟表名
    return '$sqlKeyword $quoted';
  }

  static String _quoteMySql(String identifier) {
    final escaped = identifier.replaceAll('`', '``');
    return '`$escaped`';
  }
}
