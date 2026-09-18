// spec 041 US3: FilterBar WHERE 拼装纯函数。
//
// 把可视化筛选条件拼成完整 SELECT，注入基础查询后走 executeCurrentQueryAndRecord。
// 安全（MVP 最小合规，完整转义矩阵 defer 到后续 spec）：
//   - 标识符先过白名单 ^[A-Za-z_][A-Za-z0-9_]*$（不符跳过 + AppLogger.w）
//   - 标识符按 dbType dispatch 转义（反引号/双引号/方括号）
//   - 值强制 escapeString（'→''）
//   - 显式方言 dispatch：SQLServer 用 SELECT TOP N，其余用尾部 LIMIT N
//     （绝不切片 getDefaultBrowseQuery，否则 SQLServer TOP 会错位）

import '../models/database_models.dart';
import '../models/filter_condition.dart';
import 'app_logger.dart';
import 'sql_escape_utils.dart';

/// 合法标识符白名单（defense-in-depth，转义前的预过滤）。
final RegExp _identifierWhitelist = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// 按 [FilterCondition] 列表 + 组合器拼装带 WHERE 的完整 SELECT。
///
/// - [qualifiedTable] 目标表/视图名（PG/SQLServer 可为 `schema.table`）。
/// - [conditions] 筛选条件；非法列名/空值（需值操作符）会被跳过。
/// - [combinator] 多条件 AND/OR。
/// - [dbType] 数据库类型，决定标识符引号风格与 LIMIT/TOP 方言。
/// - [limit] 行数上限，默认 3000（对齐 executeCurrentQueryAndRecord 行限）。
///
/// 返回带结尾分号的完整 SQL。无有效条件时返回无 WHERE 的全表查询。
String buildFilteredSelect({
  required String qualifiedTable,
  required List<FilterCondition> conditions,
  required FilterCombinator combinator,
  required DatabaseType dbType,
  int limit = 3000,
}) {
  final escTable = _escapeTable(qualifiedTable, dbType);
  final fragments = <String>[];
  for (final condition in conditions) {
    final fragment = _buildFragment(condition, dbType);
    if (fragment != null) fragments.add(fragment);
  }
  final where = fragments.isEmpty
      ? ''
      : ' WHERE ${fragments.join(combinator == FilterCombinator.and ? ' AND ' : ' OR ')}';

  // 显式方言 dispatch：SQLServer 的 TOP 位于 SELECT 与 * 之间，无 LIMIT 子句。
  if (dbType == DatabaseType.sqlserver) {
    return 'SELECT TOP $limit * FROM $escTable$where;';
  }
  return 'SELECT * FROM $escTable$where LIMIT $limit;';
}

/// 拼单个条件的 WHERE 片段；非法列名或空值（需值操作符）返回 null（跳过）。
String? _buildFragment(FilterCondition condition, DatabaseType dbType) {
  final field = condition.field;
  if (!_identifierWhitelist.hasMatch(field)) {
    AppLogger.w(
      'FilterQueryBuilder',
      '筛选条件列名不符白名单，已跳过: "$field"',
    );
    return null;
  }
  final escCol = SqlEscapeUtils.escapeIdentifierForType(field, dbType);

  switch (condition.op) {
    case FilterOperator.isNull:
      return '$escCol IS NULL';
    case FilterOperator.isNotNull:
      return '$escCol IS NOT NULL';
    case FilterOperator.eq:
    case FilterOperator.ne:
    case FilterOperator.gt:
    case FilterOperator.gte:
    case FilterOperator.lt:
    case FilterOperator.lte:
    case FilterOperator.like:
    case FilterOperator.notLike:
      if (condition.value.isEmpty) return null; // 需值操作符空值跳过
      // boolean 类型按 dbType 输出裸值（PG TRUE/FALSE、其余 1/0）；其余 escapeString 加引号。
      final rhs = condition.kind == FilterValueKind.boolean
          ? _booleanToken(condition.value, dbType)
          : SqlEscapeUtils.escapeString(condition.value);
      return '$escCol ${_opSql(condition.op)} $rhs';
  }
}

/// 布尔值按 dbType 编码为**裸值**（不加引号，避免 'true' 字符串在 PG 报类型错）。
/// PG 用 `TRUE`/`FALSE`（不接受 `boolean = integer`）；其余用 `1`/`0`。
/// 值限定 true/false/1/0（由 FilterBar 下拉产生），无注入面。
String _booleanToken(String value, DatabaseType dbType) {
  final isTrue = value.toLowerCase() == 'true' || value == '1';
  if (dbType == DatabaseType.postgresql) {
    return isTrue ? 'TRUE' : 'FALSE';
  }
  return isTrue ? '1' : '0';
}

/// 操作符 → SQL 片段（值操作符；isNull/isNotNull 在上层单独处理）。
String _opSql(FilterOperator op) {
  switch (op) {
    case FilterOperator.eq:
      return '=';
    case FilterOperator.ne:
      return '!=';
    case FilterOperator.gt:
      return '>';
    case FilterOperator.gte:
      return '>=';
    case FilterOperator.lt:
      return '<';
    case FilterOperator.lte:
      return '<=';
    case FilterOperator.like:
      return 'LIKE';
    case FilterOperator.notLike:
      return 'NOT LIKE';
    case FilterOperator.isNull:
    case FilterOperator.isNotNull:
      return ''; // 不取值，不会到达（isNull/isNotNull 在 _buildFragment 单独处理）
  }
}

/// 按 dbType 转义表/视图标识符。
String _escapeTable(String name, DatabaseType dbType) {
  switch (dbType) {
    case DatabaseType.postgresql:
    case DatabaseType.sqlite:
      // 含 schema 时按 '.' 拆段双引号：public.users → "public"."users"
      return SqlEscapeUtils.escapePgQualifiedIdentifier(name);
    case DatabaseType.sqlserver:
      return SqlEscapeUtils.escapeSqlServerIdentifier(name);
    case DatabaseType.mysql:
    case DatabaseType.doris:
    case DatabaseType.tdengine:
    case DatabaseType.clickhouse:
    case DatabaseType.oceanbase:
    case DatabaseType.tidb:
    case DatabaseType.starrocks:
    case DatabaseType.mariadb:
      return SqlEscapeUtils.escapeMySqlIdentifier(name);
    case DatabaseType.mongodb:
    case DatabaseType.redis:
      // FilterBar 仅 SQL 系，此处不应到达；兜底反引号。
      return SqlEscapeUtils.escapeMySqlIdentifier(name);
  }
}
