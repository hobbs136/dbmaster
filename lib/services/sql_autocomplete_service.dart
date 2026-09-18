import '../models/database_models.dart';
import 'database_service.dart';
import '../utils/app_logger.dart';

/// 自动补全建议类型
enum SuggestionType {
  keyword, // SQL 关键字
  table, // 表名
  column, // 列名
  function, // 函数
  datatype, // 数据类型
  operator, // 运算符
  // 020-mongo-daily-productivity — Mongo 补全类型 (US1/US2)
  collection, // MongoDB 集合名
  field, // MongoDB 文档字段名
  method, // Mongo shell 方法名
}

/// 自动补全建议
class Suggestion {
  final String text;
  final SuggestionType type;
  final String? detail;
  final int priority;

  Suggestion({
    required this.text,
    required this.type,
    this.detail,
    this.priority = 50,
  });

  @override
  String toString() => text;
}

/// SQL 上下文类型
enum SQLContext {
  none, // 无上下文
  select, // SELECT 语句中
  from, // FROM 子句
  where, // WHERE 子句
  join, // JOIN 子句（表名部分）
  joinOn, // JOIN 子句（ON 条件部分）
  groupBy, // GROUP BY 子句
  orderBy, // ORDER BY 子句
  insert, // INSERT 语句中
  update, // UPDATE 语句中
}

/// SQL 自动补全服务
class SQLAutocompleteService {
  final DatabaseService _dbService;
  final Map<String, List<String>> _cachedTables = {};
  final Map<String, List<String>> _cachedColumns = {};
  final Map<String, List<DbColumn>> _cachedColumnDetails = {};
  final Map<String, List<ForeignKey>> _cachedForeignKeys = {};
  DateTime? _lastCacheUpdate;
  String? _lastDatabaseName;

  SQLAutocompleteService(this._dbService);

  String _getCacheKey(String? databaseName, String? connectionId) {
    final connId = connectionId ?? _dbService.activeConnectionId ?? 'default';
    final dbName = databaseName ?? '';
    return '$connId:$dbName';
  }

  bool _isDatabaseChanged(String? databaseName) {
    if (_lastDatabaseName != databaseName) {
      _lastDatabaseName = databaseName;
      return true;
    }
    return false;
  }

  // ==================== MySQL 关键字 ====================
  static const List<String> _keywords = [
    'SELECT',
    'FROM',
    'WHERE',
    'JOIN',
    'LEFT JOIN',
    'RIGHT JOIN',
    'INNER JOIN',
    'OUTER JOIN',
    'GROUP BY',
    'ORDER BY',
    'LIMIT',
    'OFFSET',
    'HAVING',
    'UNION',
    'UNION ALL',
    'INSERT',
    'INTO',
    'VALUES',
    'UPDATE',
    'SET',
    'DELETE',
    'CREATE',
    'TABLE',
    'DATABASE',
    'INDEX',
    'VIEW',
    'PROCEDURE',
    'FUNCTION',
    'TRIGGER',
    'DROP',
    'ALTER',
    'RENAME',
    'TRUNCATE',
    'DISTINCT',
    'AS',
    'ON',
    'AND',
    'OR',
    'NOT',
    'IN',
    'BETWEEN',
    'LIKE',
    'IS',
    'NULL',
    'PRIMARY KEY',
    'FOREIGN KEY',
    'UNIQUE',
    'REFERENCES',
    'DESC',
    'ASC',
    'CASE',
    'WHEN',
    'THEN',
    'ELSE',
    'END',
    'EXISTS',
    'ALL',
    'ANY',
    'SOME',
    'WITH',
    'RECURSIVE',
    'SHOW',
    'DESCRIBE',
    'EXPLAIN',
    'USE',
  ];

  // ==================== 数据类型 ====================
  static const List<String> _dataTypes = [
    'INT',
    'BIGINT',
    'SMALLINT',
    'TINYINT',
    'MEDIUMINT',
    'VARCHAR',
    'CHAR',
    'TEXT',
    'MEDIUMTEXT',
    'LONGTEXT',
    'TINYTEXT',
    'DATETIME',
    'DATE',
    'TIME',
    'TIMESTAMP',
    'YEAR',
    'DECIMAL',
    'FLOAT',
    'DOUBLE',
    'NUMERIC',
    'BLOB',
    'MEDIUMBLOB',
    'LONGBLOB',
    'TINYBLOB',
    'BOOLEAN',
    'BOOL',
    'JSON',
    'ENUM',
    'SET',
  ];

  // ==================== MySQL 函数（带签名） ====================
  static const Map<String, String> _functions = {
    // 聚合函数
    'COUNT': 'COUNT(expression) - 返回行数',
    'SUM': 'SUM(expression) - 返回表达式之和',
    'AVG': 'AVG(expression) - 返回平均值',
    'MAX': 'MAX(expression) - 返回最大值',
    'MIN': 'MIN(expression) - 返回最小值',
    'GROUP_CONCAT': 'GROUP_CONCAT(expr) - 合并组内值',
    'DISTINCT': 'DISTINCT(expression) - 返回不同的值',

    // 字符串函数
    'CONCAT': 'CONCAT(str1, str2, ...) - 连接字符串',
    'UPPER': 'UPPER(str) - 转换为大写',
    'LOWER': 'LOWER(str) - 转换为小写',
    'SUBSTRING': 'SUBSTRING(str, pos, len) - 提取子串',
    'SUBSTR': 'SUBSTR(str, pos, len) - 提取子串',
    'LENGTH': 'LENGTH(str) - 返回字符串长度',
    'CHAR_LENGTH': 'CHAR_LENGTH(str) - 返回字符长度',
    'TRIM': 'TRIM(str) - 去除首尾空格',
    'LTRIM': 'LTRIM(str) - 去除左侧空格',
    'RTRIM': 'RTRIM(str) - 去除右侧空格',
    'REPLACE': 'REPLACE(str, from, to) - 替换字符串',
    'LEFT': 'LEFT(str, len) - 返回左侧字符',
    'RIGHT': 'RIGHT(str, len) - 返回右侧字符',
    'REVERSE': 'REVERSE(str) - 反转字符串',
    'LOCATE': 'LOCATE(substr, str) - 查找子串位置',
    'POSITION': 'POSITION(substr IN str) - 查找子串位置',
    'STRCMP': 'STRCMP(str1, str2) - 比较字符串',

    // 日期时间函数
    'NOW': 'NOW() - 当前日期时间',
    'CURRENT_DATE': 'CURRENT_DATE() - 当前日期',
    'CURDATE': 'CURDATE() - 当前日期',
    'CURRENT_TIME': 'CURRENT_TIME() - 当前时间',
    'CURTIME': 'CURTIME() - 当前时间',
    'DATE': 'DATE(expr) - 提取日期部分',
    'TIME': 'TIME(expr) - 提取时间部分',
    'YEAR': 'YEAR(date) - 提取年份',
    'MONTH': 'MONTH(date) - 提取月份',
    'DAY': 'DAY(date) - 提取日期',
    'HOUR': 'TIME(time) - 提取小时',
    'MINUTE': 'MINUTE(time) - 提取分钟',
    'SECOND': 'SECOND(time) - 提取秒数',
    'DATE_FORMAT': 'DATE_FORMAT(date, format) - 格式化日期',
    'DATE_ADD': 'DATE_ADD(date, INTERVAL val unit) - 日期加法',
    'DATE_SUB': 'DATE_SUB(date, INTERVAL val unit) - 日期减法',
    'DATEDIFF': 'DATEDIFF(expr1, expr2) - 日期差值',
    'TIMESTAMPDIFF': 'TIMESTAMPDIFF(unit, expr1, expr2) - 时间戳差值',
    'FROM_UNIXTIME': 'FROM_UNIXTIME(unix) - Unix时间转日期',
    'UNIX_TIMESTAMP': 'UNIX_TIMESTAMP(date) - 日期转Unix时间',

    // 数学函数
    'ABS': 'ABS(x) - 绝对值',
    'CEIL': 'CEIL(x) - 向上取整',
    'FLOOR': 'FLOOR(x) - 向下取整',
    'ROUND': 'ROUND(x, d) - 四舍五入',
    'MOD': 'MOD(x, y) - 取模',
    'POWER': 'POWER(x, y) - 幂运算',
    'SQRT': 'SQRT(x) - 平方根',
    'RAND': 'RAND() - 随机数',
    'SIGN': 'SIGN(x) - 符号函数',

    // 条件函数
    'IF': 'IF(expr, true_val, false_val) - 条件判断',
    'IFNULL': 'IFNULL(expr, alt) - 如果为空则返回替代值',
    'COALESCE': 'COALESCE(expr1, expr2, ...) - 返回第一个非空值',
    'NULLIF': 'NULLIF(expr1, expr2) - 如果相等则返回NULL',
    'CASE': 'CASE WHEN ... THEN ... ELSE ... END - 条件表达式',

    // 类型转换
    'CAST': 'CAST(expr AS type) - 类型转换',
    'CONVERT': 'CONVERT(expr, type) - 类型转换',

    // 其他
    'MD5': 'MD5(str) - MD5哈希',
    'SHA1': 'SHA1(str) - SHA1哈希',
    'UUID': 'UUID() - 生成UUID',
  };

  // ==================== 运算符 ====================
  static const List<String> _operators = [
    '=',
    '<',
    '>',
    '<=',
    '>=',
    '!=',
    '<>',
    'LIKE',
    'NOT LIKE',
    'IN',
    'NOT IN',
    'BETWEEN',
    'NOT BETWEEN',
    'IS NULL',
    'IS NOT NULL',
    'REGEXP',
    'NOT REGEXP',
    '&',
    '|',
    '^',
    '~',
    '<<',
    '>>',
    '+',
    '-',
    '*',
    '/',
    '%',
    'DIV',
    'MOD',
  ];

  /// 获取 MySQL 关键字
  List<Suggestion> getMySQLKeywords(String prefix) {
    final upperPrefix = prefix.toUpperCase();
    return _keywords
        .where((kw) => kw.toUpperCase().startsWith(upperPrefix))
        .map(
          (kw) =>
              Suggestion(text: kw, type: SuggestionType.keyword, priority: 80),
        )
        .toList();
  }

  /// 获取数据类型
  List<Suggestion> getDataTypes(String prefix) {
    final upperPrefix = prefix.toUpperCase();
    return _dataTypes
        .where((dt) => dt.toUpperCase().startsWith(upperPrefix))
        .map(
          (dt) =>
              Suggestion(text: dt, type: SuggestionType.datatype, priority: 70),
        )
        .toList();
  }

  /// 获取函数
  List<Suggestion> getFunctions(String prefix) {
    final upperPrefix = prefix.toUpperCase();
    final suggestions = <Suggestion>[];

    _functions.forEach((name, detail) {
      if (name.toUpperCase().startsWith(upperPrefix)) {
        suggestions.add(
          Suggestion(
            text: name,
            type: SuggestionType.function,
            detail: detail,
            priority: 90,
          ),
        );
      }
    });

    return suggestions;
  }

  /// 获取运算符
  List<Suggestion> getOperators(String prefix) {
    final upperPrefix = prefix.toUpperCase();
    return _operators
        .where((op) => op.toUpperCase().startsWith(upperPrefix))
        .map(
          (op) =>
              Suggestion(text: op, type: SuggestionType.operator, priority: 60),
        )
        .toList();
  }

  /// 获取表名（带缓存，支持跨数据库类型）
  Future<List<Suggestion>> getTableNames(
    String prefix, {
    String? databaseName,
    String? connectionId,
  }) async {
    final cid = connectionId ?? _dbService.activeConnectionId;
    if (cid == null || !_dbService.hasConnection(cid)) return [];

    try {
      final cacheKey = _getCacheKey(databaseName, connectionId);
      if (_cachedTables[cacheKey] == null ||
          _isCacheExpired() ||
          _isDatabaseChanged(databaseName)) {
        final tables = await _dbService.getTables(connectionId: cid);
        _cachedTables[cacheKey] = tables;
        _lastCacheUpdate = DateTime.now();
      }

      final tables = _cachedTables[cacheKey]!;
      final lowerPrefix = prefix.toLowerCase();
      return tables
          .where(
            (t) =>
                lowerPrefix.isEmpty || t.toLowerCase().startsWith(lowerPrefix),
          )
          .map(
            (t) => Suggestion(
              text: t,
              type: SuggestionType.table,
              detail: 'Table',
              priority: 100,
            ),
          )
          .toList();
    } catch (e) {
      AppLogger.d('SqlAutocomplete', 'Error getting table names: $e');
      return [];
    }
  }

  /// 获取列名（带缓存）
  Future<List<Suggestion>> getColumnNames(
    String prefix, {
    String? tableName,
    String? databaseName,
    String? connectionId,
  }) async {
    final cid = connectionId ?? _dbService.activeConnectionId;
    if (cid == null || !_dbService.hasConnection(cid)) return [];

    try {
      final baseCacheKey = _getCacheKey(databaseName, connectionId);

      // 如果指定了表名，获取该表的列
      if (tableName != null) {
        final columnCacheKey = '$baseCacheKey:$tableName';

        if (_cachedColumns[columnCacheKey] == null ||
            _isCacheExpired() ||
            _isDatabaseChanged(databaseName)) {
          final columns = await _dbService.getTableColumns(
            tableName,
            connectionId: cid,
            databaseName: databaseName,
          );
          _cachedColumns[columnCacheKey] = columns.map((c) => c.name).toList();
          _cachedColumnDetails[columnCacheKey] = columns;
          _lastCacheUpdate = DateTime.now();
        }

        final columns = _cachedColumns[columnCacheKey]!;
        final columnDetails = _cachedColumnDetails[columnCacheKey]!;

        return columns
            .where((c) => c.toLowerCase().startsWith(prefix.toLowerCase()))
            .map((c) {
              final detail = columnDetails.firstWhere((d) => d.name == c);
              return Suggestion(
                text: prefix + c.substring(prefix.length),
                type: SuggestionType.column,
                detail: '${detail.type}${detail.isPrimaryKey ? ' (PK)' : ''}',
                priority: 100,
              );
            })
            .toList();
      }

      // 如果没有指定表名，尝试从缓存中获取所有列
      return [];
    } catch (e) {
      AppLogger.d('SqlAutocomplete', 'Error getting column names: $e');
      return [];
    }
  }

  /// 获取存储过程和函数名
  Future<List<Suggestion>> getProcedureNames(String prefix) async {
    if (!_dbService.isConnected) return [];

    try {
      final procedures = await _dbService.getProcedures();
      return procedures
          .where((p) => p.toLowerCase().startsWith(prefix.toLowerCase()))
          .map(
            (p) => Suggestion(
              text: prefix + p.substring(prefix.length),
              type: SuggestionType.function,
              detail: 'Stored Procedure',
              priority: 85,
            ),
          )
          .toList();
    } catch (e) {
      AppLogger.d('SqlAutocomplete', 'Error getting procedure names: $e');
      return [];
    }
  }

  /// 解析 SQL 上下文
  SQLContext parseSQLContext(String sql, int cursorPosition) {
    if (sql.isEmpty) return SQLContext.none;

    final beforeCursor = sql.substring(0, cursorPosition).toUpperCase();

    // 检查是否在 INSERT 语句中
    if (beforeCursor.contains('INSERT')) return SQLContext.insert;

    // 检查是否在 UPDATE 语句中
    if (beforeCursor.contains('UPDATE')) return SQLContext.update;

    // 检查是否在 SELECT 语句中
    if (!beforeCursor.contains('SELECT')) return SQLContext.none;

    // 检查是否在 JOIN ON 子句中
    if (_isInJoinOnClause(sql, cursorPosition)) {
      return SQLContext.joinOn;
    }

    // 检查最近的上下文关键词
    final keywords = [
      'ORDER BY',
      'GROUP BY',
      'HAVING',
      'WHERE',
      'FROM',
      'JOIN',
      'LEFT JOIN',
      'RIGHT JOIN',
      'INNER JOIN',
    ];

    String? lastKeyword;
    int lastKeywordPos = -1;

    for (final keyword in keywords) {
      final pos = beforeCursor.lastIndexOf(keyword);
      if (pos > lastKeywordPos) {
        lastKeywordPos = pos;
        lastKeyword = keyword;
      }
    }

    if (lastKeyword == null) return SQLContext.select;

    switch (lastKeyword) {
      case 'FROM':
        return SQLContext.from;
      case 'WHERE':
        return SQLContext.where;
      case 'JOIN':
      case 'LEFT JOIN':
      case 'RIGHT JOIN':
      case 'INNER JOIN':
        return SQLContext.join;
      case 'GROUP BY':
        return SQLContext.groupBy;
      case 'ORDER BY':
        return SQLContext.orderBy;
      case 'HAVING':
        return SQLContext.where;
      default:
        return SQLContext.select;
    }
  }

  /// 检查光标是否在 JOIN ON 子句中
  bool _isInJoinOnClause(String sql, int cursorPosition) {
    // 查找最近的 JOIN ... ON 模式（支持带引号的表名）
    final joinOnPattern = RegExp(
      r'(?:INNER|LEFT|RIGHT|FULL)?\s*JOIN\s+[`"]?[a-zA-Z_][a-zA-Z0-9_]*[`"]?\s+ON\s',
      caseSensitive: false,
    );

    final matches = joinOnPattern
        .allMatches(sql.substring(0, cursorPosition))
        .toList();
    if (matches.isEmpty) return false;

    final lastMatch = matches.last;
    final afterOn = cursorPosition > lastMatch.end;

    // 检查是否在 ON 和下一个 JOIN/WHERE/GROUP BY/ORDER BY 之间
    if (afterOn) {
      return true;
    }

    return false;
  }

  /// 去掉标识符两端的引号（反引号或双引号）
  String _stripQuotes(String identifier) {
    if (identifier.length >= 2) {
      final first = identifier[0];
      final last = identifier[identifier.length - 1];
      if ((first == '`' && last == '`') || (first == '"' && last == '"')) {
        return identifier.substring(1, identifier.length - 1);
      }
    }
    return identifier;
  }

  /// 提取 FROM 子句中的表名
  List<String> extractTableNamesFromSQL(String sql) {
    final tables = <String>[];

    // 支持带引号的表名（反引号、双引号）
    final fromPattern = RegExp(
      r'FROM\s+([`"]?[a-zA-Z_][a-zA-Z0-9_]*[`"]?)',
      caseSensitive: false,
    );
    final joinPattern = RegExp(
      r'(?:INNER|LEFT|RIGHT|FULL)?\s*JOIN\s+([`"]?[a-zA-Z_][a-zA-Z0-9_]*[`"]?)',
      caseSensitive: false,
    );

    for (final match in fromPattern.allMatches(sql)) {
      final table = _stripQuotes(match.group(1) ?? '');
      if (table.isNotEmpty && !tables.contains(table)) {
        tables.add(table);
      }
    }

    for (final match in joinPattern.allMatches(sql)) {
      final table = _stripQuotes(match.group(1) ?? '');
      if (table.isNotEmpty && !tables.contains(table)) {
        tables.add(table);
      }
    }

    return tables;
  }

  /// 获取所有补全建议
  Future<List<Suggestion>> getSuggestions(
    String input,
    int cursorPosition, {
    String? databaseName,
    String? connectionId,
  }) async {
    final suggestions = <Suggestion>[];
    final prefix = _extractPrefix(input, cursorPosition);
    final context = parseSQLContext(input, cursorPosition);

    // 检测光标是否紧跟在 SQL 关键字后（如 "SELECT "、"FROM "、"WHERE " 等）
    // 这种情况下 prefix 为空但用户即将输入——应列出该上下文下的所有可用对象
    final lastWord = _lastWordBeforeCursor(input, cursorPosition).toUpperCase();

    switch (context) {
      case SQLContext.from:
      case SQLContext.join:
        // FROM/JOIN 后：优先显示表名（即使 prefix 为空也列出全部表）
        suggestions.addAll(
          await getTableNames(
            prefix,
            databaseName: databaseName,
            connectionId: connectionId,
          ),
        );
        suggestions.addAll(getMySQLKeywords(prefix));
        break;

      case SQLContext.joinOn:
        final joinTables = _extractJoinTables(input, cursorPosition);
        if (joinTables != null) {
          suggestions.addAll(
            await inferJoinConditions(
              joinTables.leftTable,
              joinTables.rightTable,
              databaseName: databaseName,
            ),
          );
        }
        suggestions.addAll(getMySQLKeywords(prefix));
        break;

      case SQLContext.select:
        // SELECT 后：函数 + 列名（如果已识别表名） + 关键字
        // 也列出表名，因为用户可能想在 SELECT 后先看到可用的表
        suggestions.addAll(getFunctions(prefix));
        suggestions.addAll(getMySQLKeywords(prefix));
        final sqlTables = extractTableNamesFromSQL(input);
        if (sqlTables.isNotEmpty) {
          for (final table in sqlTables) {
            suggestions.addAll(
              await getColumnNames(
                prefix,
                tableName: table,
                databaseName: databaseName,
                connectionId: connectionId,
              ),
            );
          }
        }
        // 如果还没有 FROM 子句，也列出表名以便导航
        if (!input.toUpperCase().contains('FROM')) {
          suggestions.addAll(
            await getTableNames(
              prefix,
              databaseName: databaseName,
              connectionId: connectionId,
            ),
          );
        }
        break;

      case SQLContext.where:
      case SQLContext.groupBy:
      case SQLContext.orderBy:
        final tables = extractTableNamesFromSQL(input);
        for (final table in tables) {
          suggestions.addAll(
            await getColumnNames(
              prefix,
              tableName: table,
              databaseName: databaseName,
              connectionId: connectionId,
            ),
          );
        }
        suggestions.addAll(getOperators(prefix));
        suggestions.addAll(getFunctions(prefix));
        suggestions.addAll(getMySQLKeywords(prefix));
        break;

      case SQLContext.insert:
      case SQLContext.update:
        suggestions.addAll(getDataTypes(prefix));
        suggestions.addAll(getMySQLKeywords(prefix));
        break;

      case SQLContext.none:
        // 无上下文：关键字 + 函数 + 表名（始终显示表名供用户选择）
        suggestions.addAll(getMySQLKeywords(prefix));
        suggestions.addAll(getFunctions(prefix));
        suggestions.addAll(
          await getTableNames(
            prefix,
            databaseName: databaseName,
            connectionId: connectionId,
          ),
        );
        break;
    }

    // 如果 prefix 非空但没有表名结果，且光标紧跟在 FROM/JOIN 后，补全全部表名
    if (prefix.isNotEmpty &&
        suggestions.isEmpty &&
        (lastWord == 'FROM' ||
            lastWord == 'JOIN' ||
            lastWord.contains('JOIN'))) {
      suggestions.addAll(
        await getTableNames(
          prefix,
          databaseName: databaseName,
          connectionId: connectionId,
        ),
      );
    }

    suggestions.sort((a, b) => b.priority.compareTo(a.priority));

    final seen = <String>{};
    final uniqueSuggestions = <Suggestion>[];
    for (final suggestion in suggestions) {
      final key = suggestion.text.toLowerCase();
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueSuggestions.add(suggestion);
      }
    }

    return uniqueSuggestions;
  }

  /// 获取光标前最后一个完整的词（用于检测关键字上下文）
  String _lastWordBeforeCursor(String text, int cursorPosition) {
    final beforeCursor = cursorPosition > text.length
        ? text
        : text.substring(0, cursorPosition);
    final trimmed = beforeCursor.trimRight();
    if (trimmed.isEmpty) return '';
    final lastSpace = trimmed.lastIndexOf(RegExp(r'[\s,()=<>]'));
    if (lastSpace < 0) return trimmed;
    return trimmed.substring(lastSpace + 1);
  }

  /// 提取光标前的单词前缀
  String _extractPrefix(String text, int cursorPosition) {
    if (cursorPosition > text.length) {
      cursorPosition = text.length;
    }

    final beforeCursor = text.substring(0, cursorPosition);

    // 从后往前查找最后一个空白字符
    int lastSpacePos = -1;
    for (int i = beforeCursor.length - 1; i >= 0; i--) {
      final char = beforeCursor[i];
      if (char == ' ' ||
          char == '\n' ||
          char == '\t' ||
          char == ',' ||
          char == '(' ||
          char == ')' ||
          char == '=' ||
          char == '<' ||
          char == '>') {
        lastSpacePos = i;
        break;
      }
    }

    if (lastSpacePos == -1) return beforeCursor;
    return beforeCursor.substring(lastSpacePos + 1);
  }

  /// 检查缓存是否过期
  bool _isCacheExpired() {
    if (_lastCacheUpdate == null) return true;
    final age = DateTime.now().difference(_lastCacheUpdate!);
    return age.inMinutes > 5; // 5分钟过期
  }

  /// 清除缓存
  void clearCache() {
    _cachedTables.clear();
    _cachedColumns.clear();
    _cachedColumnDetails.clear();
    _cachedForeignKeys.clear();
    _lastCacheUpdate = null;
  }

  // ==================== JOIN 条件推断 ====================

  /// 获取表的外键关系
  Future<List<ForeignKey>> getForeignKeys(
    String tableName, {
    String? databaseName,
    String? connectionId,
  }) async {
    final cid = connectionId ?? _dbService.activeConnectionId;
    if (cid == null || !_dbService.hasConnection(cid)) return [];

    final cacheKey =
        '${_getCacheKey(databaseName, connectionId)}:$tableName:fk';

    if (_cachedForeignKeys.containsKey(cacheKey)) {
      return _cachedForeignKeys[cacheKey]!;
    }

    try {
      final adapter = _dbService.currentAdapter;
      if (adapter == null) return [];

      final foreignKeys = await adapter.getForeignKeys(tableName);
      _cachedForeignKeys[cacheKey] = foreignKeys;
      return foreignKeys;
    } catch (e) {
      AppLogger.d('SqlAutocomplete', 'Error getting foreign keys: $e');
      return [];
    }
  }

  /// 推断两个表之间的 JOIN 条件
  Future<List<Suggestion>> inferJoinConditions(
    String leftTable,
    String rightTable, {
    String? databaseName,
  }) async {
    final suggestions = <Suggestion>[];

    // 获取左表的外键（可能引用右表）
    final leftForeignKeys = await getForeignKeys(
      leftTable,
      databaseName: databaseName,
    );
    for (final fk in leftForeignKeys) {
      if (fk.referencedTable.toLowerCase() == rightTable.toLowerCase()) {
        suggestions.add(
          Suggestion(
            text:
                '$leftTable.${fk.column} = $rightTable.${fk.referencedColumn}',
            type: SuggestionType.keyword,
            detail: 'Foreign Key: ${fk.name}',
            priority: 200,
          ),
        );
      }
    }

    // 获取右表的外键（可能引用左表）
    final rightForeignKeys = await getForeignKeys(
      rightTable,
      databaseName: databaseName,
    );
    for (final fk in rightForeignKeys) {
      if (fk.referencedTable.toLowerCase() == leftTable.toLowerCase()) {
        suggestions.add(
          Suggestion(
            text:
                '$rightTable.${fk.column} = $leftTable.${fk.referencedColumn}',
            type: SuggestionType.keyword,
            detail: 'Foreign Key: ${fk.name}',
            priority: 200,
          ),
        );
      }
    }

    // 如果通过外键没找到关系，尝试基于列名匹配（启发式）
    if (suggestions.isEmpty) {
      suggestions.addAll(
        await _heuristicJoinConditions(
          leftTable,
          rightTable,
          databaseName: databaseName,
        ),
      );
    }

    return suggestions;
  }

  /// 启发式 JOIN 条件推断（基于列名相似性）
  Future<List<Suggestion>> _heuristicJoinConditions(
    String leftTable,
    String rightTable, {
    String? databaseName,
  }) async {
    final suggestions = <Suggestion>[];

    try {
      final leftColumns = await getColumnNames(
        '',
        tableName: leftTable,
        databaseName: databaseName,
      );
      final rightColumns = await getColumnNames(
        '',
        tableName: rightTable,
        databaseName: databaseName,
      );

      final rightColumnNames = rightColumns
          .map((s) => s.text.toLowerCase())
          .toSet();

      // 查找同名列
      for (final leftCol in leftColumns) {
        final colName = leftCol.text.toLowerCase();
        if (rightColumnNames.contains(colName)) {
          // 排除常见的非关联列
          if (!_isCommonNonJoinColumn(colName)) {
            suggestions.add(
              Suggestion(
                text:
                    '$leftTable.${leftCol.text} = $rightTable.${leftCol.text}',
                type: SuggestionType.keyword,
                detail: 'Matching column name',
                priority: 150,
              ),
            );
          }
        }
      }

      // 查找可能的 ID 关联（如 user_id = id）
      for (final leftCol in leftColumns) {
        final colName = leftCol.text.toLowerCase();
        if (colName.endsWith('_id')) {
          final baseName = colName.substring(0, colName.length - 3);
          if (rightTable.toLowerCase().contains(baseName) ||
              baseName.contains(rightTable.toLowerCase())) {
            for (final rightCol in rightColumns) {
              if (rightCol.text.toLowerCase() == 'id') {
                suggestions.add(
                  Suggestion(
                    text:
                        '$leftTable.${leftCol.text} = $rightTable.${rightCol.text}',
                    type: SuggestionType.keyword,
                    detail:
                        'Heuristic: ${leftCol.text} references $rightTable.id',
                    priority: 160,
                  ),
                );
              }
            }
          }
        }
      }
    } catch (e) {
      AppLogger.d('SqlAutocomplete', 'Error in heuristic join conditions: $e');
    }

    return suggestions;
  }

  bool _isCommonNonJoinColumn(String columnName) {
    final commonColumns = {
      'id',
      'created_at',
      'updated_at',
      'deleted_at',
      'created_by',
      'updated_by',
      'status',
      'name',
      'description',
      'email',
      'phone',
    };
    return commonColumns.contains(columnName);
  }

  /// 提取 JOIN 语句中的左右表名
  /// 返回 (leftTable, rightTable) 或 null
  ({String leftTable, String rightTable})? _extractJoinTables(
    String sql,
    int cursorPosition,
  ) {
    // 查找最近的 JOIN 语句（支持带引号的表名）
    final joinPattern = RegExp(
      r'(?:INNER|LEFT|RIGHT|FULL)?\s*JOIN\s+([`"]?[a-zA-Z_][a-zA-Z0-9_]*[`"]?)',
      caseSensitive: false,
    );

    String? rightTable;
    int lastJoinPos = -1;

    for (final match in joinPattern.allMatches(
      sql.substring(0, cursorPosition),
    )) {
      final pos = match.start;
      if (pos > lastJoinPos) {
        lastJoinPos = pos;
        rightTable = _stripQuotes(match.group(1) ?? '');
      }
    }

    if (rightTable == null || rightTable.isEmpty) return null;

    // 查找 JOIN 之前的表名（FROM 子句中的表或上一个 JOIN 的表）
    final beforeJoin = sql.substring(0, lastJoinPos);

    // 先尝试找最近的 JOIN 左侧表
    final prevJoinPattern = RegExp(
      r'(?:INNER|LEFT|RIGHT|FULL)?\s*JOIN\s+([`"]?[a-zA-Z_][a-zA-Z0-9_]*[`"]?)\s+(?:ON|USING)',
      caseSensitive: false,
    );

    String? leftTable;
    final prevJoinMatches = prevJoinPattern.allMatches(beforeJoin).toList();
    if (prevJoinMatches.isNotEmpty) {
      leftTable = _stripQuotes(prevJoinMatches.last.group(1) ?? '');
    } else {
      // 从 FROM 子句中找表名
      final fromPattern = RegExp(
        r'FROM\s+([`"]?[a-zA-Z_][a-zA-Z0-9_]*[`"]?(?:\s+[`"]?[a-zA-Z_][a-zA-Z0-9_]*[`"]?)?)',
        caseSensitive: false,
      );
      final fromMatch = fromPattern.firstMatch(beforeJoin);
      if (fromMatch != null) {
        final fromClause = fromMatch.group(1)!.trim();
        // 只取第一个表名（忽略别名）
        leftTable = _stripQuotes(fromClause.split(RegExp(r'\s+')).first);
      }
    }

    if (leftTable == null || leftTable.isEmpty) return null;

    return (leftTable: leftTable, rightTable: rightTable);
  }
}
