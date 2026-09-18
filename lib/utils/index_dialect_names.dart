import '../models/database_models.dart';

/// T063 — dialect-aware composition of the (tableName, indexName) args
/// that `provider.dropIndex` / `provider.createIndex` expect, so index DDL
/// resolves for **non-default schemas** on PostgreSQL / SQL Server.
///
/// Background: the adapters are backward-compatible — they accept either bare
/// or schema-qualified names and escape per segment. But each dialect needs the
/// qualifier on a *different* argument:
///   - PostgreSQL `DROP INDEX` has no `ON` clause; the index itself is
///     schema-scoped → the **index name** must be qualified.
///   - SQL Server `DROP/CREATE INDEX ... ON <table>` resolves `<table>` against
///     the login's default schema → the **table name** must be qualified.
///   - MySQL/Doris/SQLite have no schema concept → bare names.
///
/// `createIndex` never needs the *index name* qualified (the index is created in
/// the table's own schema on every dialect); only the table arg may need it.
///
/// Extracted to a pure, unit-testable helper shared by the sidebar tree handler
/// and `EditIndexDialog`.
class IndexDialectNames {
  IndexDialectNames._();

  /// Args for `provider.dropIndex(db, table, index)`:
  /// PG qualifies the index, SQL Server qualifies the table, others stay bare.
  /// [type] 可空（断连时 server 缺失）——null 走无 schema 方言（裸名），
  /// 与旧「断连回退 MySQL」行为等价（C19 sidebar 清零字面量连带）。
  static ({String table, String index}) dropArgs(
    DatabaseType? type,
    String schema,
    String table,
    String index,
  ) {
    final hasSchema = schema.isNotEmpty;
    return (
      table: (hasSchema && type == DatabaseType.sqlserver)
          ? '$schema.$table'
          : table,
      index: (hasSchema && type == DatabaseType.postgresql)
          ? '$schema.$index'
          : index,
    );
  }

  /// Table arg for `provider.createIndex(db, table, ...)`:
  /// PG + SQL Server qualify the table (the new index name stays bare — it is
  /// created in the table's schema on every dialect). Others stay bare.
  static String createTableArg(
    DatabaseType type,
    String schema,
    String table,
  ) {
    final hasSchema = schema.isNotEmpty;
    return (hasSchema &&
            (type == DatabaseType.postgresql ||
                type == DatabaseType.sqlserver))
        ? '$schema.$table'
        : table;
  }
}
