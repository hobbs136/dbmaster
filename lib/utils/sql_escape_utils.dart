import '../models/database_models.dart';

/// SQL 转义工具类
///
/// 提供数据库标识符和字符串值的安全转义，防止 SQL 注入。
/// 支持不同数据库的标识符引号风格（MySQL/Doris 用反引号，PostgreSQL/SQLite 用双引号）。
class SqlEscapeUtils {
  SqlEscapeUtils._();

  /// 转义 SQL 标识符（表名、列名、数据库名等）
  ///
  /// [name] 标识符名称
  /// [quote] 引号字符，默认反引号 `` ` ``（MySQL/Doris 风格）
  ///         PostgreSQL/SQLite 使用双引号 `"`
  ///
  /// 示例:
  /// ```dart
  /// SqlEscapeUtils.escapeIdentifier('users'); // => '`users`'
  /// SqlEscapeUtils.escapeIdentifier('order', quote: '"'); // => '"order"'
  /// SqlEscapeUtils.escapeIdentifier('a`b'); // => '`a``b`'
  /// ```
  static String escapeIdentifier(String name, {String quote = '`'}) {
    final escaped = name.replaceAll(quote, quote + quote);
    return '$quote$escaped$quote';
  }

  /// 转义 SQL 字符串值
  ///
  /// [value] 字符串值
  ///
  /// 示例:
  /// ```dart
  /// SqlEscapeUtils.escapeString("it's"); // => "'it''s'"
  /// ```
  static String escapeString(String value) {
    return "'${value.replaceAll("'", "''")}'";
  }

  /// 转义 MySQL/Doris 标识符（反引号风格）
  static String escapeMySqlIdentifier(String name) =>
      escapeIdentifier(name, quote: '`');

  /// 转义 PostgreSQL/SQLite 标识符（双引号风格）
  static String escapePgIdentifier(String name) =>
      escapeIdentifier(name, quote: '"');

  /// 转义可能带 schema 前缀的 PostgreSQL 限定标识符（如 `schema.table`）。
  ///
  /// 按 `.` 拆分后逐段用双引号转义再拼接：`public.users` → `"public"."users"`。
  /// 直接对整串调用 [escapePgIdentifier] 会得到 `"public.users"`（一个名字里带点的
  /// 单标识符），无法定位到 `public` schema 下的 `users` 表。单段名字等价于
  /// [escapePgIdentifier]。
  static String escapePgQualifiedIdentifier(String name) {
    return name.split('.').map(escapePgIdentifier).join('.');
  }

  /// 按方言转义限定标识符（C19 自 sidebar_tree `_escapeQualIdent` 收编）。
  ///
  /// PG 用双引号、SQL Server 用方括号（无 qualified helper，逐段转义拼接，
  /// 内嵌 `]` 按 T-SQL 规则双写）、其余（含 [type] 为 null 的断连兜底）
  /// 走 MySQL 反引号。
  static String escapeQualifiedIdentifier(String name, DatabaseType? type) {
    switch (type) {
      case DatabaseType.postgresql:
        return escapePgQualifiedIdentifier(name);
      case DatabaseType.sqlserver:
        return name
            .split('.')
            .map(escapeSqlServerIdentifier)
            .join('.');
      default:
        return name
            .split('.')
            .map(escapeMySqlIdentifier)
            .join('.');
    }
  }

  /// 转义 SQL Server 标识符（方括号风格）
  ///
  /// SQL Server 中方括号内的 `]` 需要转义为 `]]`
  /// 示例:
  /// ```dart
  /// SqlEscapeUtils.escapeSqlServerIdentifier('users'); // => '[users]'
  /// SqlEscapeUtils.escapeSqlServerIdentifier('a]b'); // => '[a]]b]'
  /// ```
  static String escapeSqlServerIdentifier(String name) {
    final escaped = name.replaceAll(']', ']]');
    return '[$escaped]';
  }

  /// 解包 SQL Server 标识符（去除方括号并还原转义）
  ///
  /// 示例:
  /// ```dart
  /// SqlEscapeUtils.unescapeSqlServerIdentifier('[users]'); // => 'users'
  /// SqlEscapeUtils.unescapeSqlServerIdentifier('[a]]b]'); // => 'a]b'
  /// ```
  static String unescapeSqlServerIdentifier(String name) {
    if (name.startsWith('[') && name.endsWith(']')) {
      final inner = name.substring(1, name.length - 1);
      return inner.replaceAll(']]', ']');
    }
    return name;
  }

  /// 按数据库类型选择正确的标识符引号风格（统一 QuickSearch / 侧栏等处的按类型 dispatch）。
  ///
  /// - MySQL/Doris/TDengine/OceanBase/TiDB/StarRocks/MariaDB/MongoDB/Redis →
  ///   反引号（[escapeMySqlIdentifier]）
  /// - PostgreSQL/SQLite → 双引号（[escapePgIdentifier]）
  /// - SQL Server → 方括号（[escapeSqlServerIdentifier]）
  static String escapeIdentifierForType(String name, DatabaseType type) {
    switch (type) {
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
        return escapePgIdentifier(name);
      case DatabaseType.sqlserver:
        return escapeSqlServerIdentifier(name);
      case DatabaseType.mysql:
      case DatabaseType.doris:
      case DatabaseType.tdengine:
      case DatabaseType.clickhouse:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
      case DatabaseType.mongodb:
      case DatabaseType.redis:
        return escapeMySqlIdentifier(name);
    }
  }
}
