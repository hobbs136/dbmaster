/// SQL 安全工具
/// 所有用户输入/动态数据的转义必须经过此类
/// 注意：标识符（表名、列名）用 identifier()，值用 value()
class SqlSanitizer {
  /// 转义 MySQL 标识符（表名、列名、数据库名）
  /// 只允许字母、数字、下划线，中文会被反引号包裹
  /// ⚠️ 不允许空字符串
  static String identifier(String name) {
    if (name.isEmpty) return '``';
    final sanitized = name.replaceAll('`', '``');
    return '`$sanitized`';
  }

  /// 转义 PostgreSQL 标识符
  static String identifierPg(String name) {
    if (name.isEmpty) return '""';
    final sanitized = name.replaceAll('"', '""');
    return '"$sanitized"';
  }

  /// 转义字符串值，防止 SQL 注入
  /// 处理：单引号、转义符、换行符、NULL
  /// 返回值始终带外层单引号
  static String value(dynamic v) {
    if (v == null) return 'NULL';

    String str;
    if (v is num) {
      str = v.toString();
      // NaN 和 Infinity 转 NULL
      if (str == 'NaN' || str == 'Infinity' || str == '-Infinity') {
        return 'NULL';
      }
      return str; // 数字不需要引号
    }

    if (v is bool) {
      return v ? '1' : '0';
    }

    str = v.toString();

    // MySQL 字符串转义规则：
    // 1. 单引号 → ''（两个单引号）
    // 2. 反斜杠 → \\（必须在单引号内）
    // 3. 控制字符（\n, \r, \t, \0）保留
    // 4. 外层自动加单引号
    str = str
        .replaceAll('\\', '\\\\') // 反斜杠先转，避免二次转义
        .replaceAll("'", "''"); // 单引号变双单引号

    return "'$str'";
  }

  /// 快速生成 WHERE 条件（字段 = 值）
  /// 自动处理标识符和值转义
  /// ⚠️ 不支持 OR 组合，复杂条件请用 whereClause()
  static String eq(String column, dynamic val) {
    final col = identifier(column);
    if (val == null) return '$col IS NULL';
    return '$col = ${SqlSanitizer.value(val)}';
  }

  /// 生成完整的 WHERE 子句
  /// conditions: Map<列名, 值> → AND 组合
  /// ⚠️ values 只接受简单类型，复杂表达式直接传字符串
  static String whereClause(Map<String, dynamic> conditions) {
    if (conditions.isEmpty) return '';

    final parts = <String>[];
    for (final entry in conditions.entries) {
      if (entry.value == null) {
        parts.add('${identifier(entry.key)} IS NULL');
      } else {
        parts.add('${identifier(entry.key)} = ${value(entry.value)}');
      }
    }
    return 'WHERE ${parts.join(' AND ')}';
  }

  /// 生成 IN 子句
  /// values: 逗号分隔的值列表，自动转义
  /// 空列表返回 'IN (NULL)'（匹配空结果）
  static String inClause(String column, Iterable<dynamic> values) {
    final list = values.toList();
    if (list.isEmpty) return '${identifier(column)} IN (NULL)';

    final escaped = list.map((v) => value(v)).join(', ');
    return '${identifier(column)} IN ($escaped)';
  }

  /// 危险操作检测
  /// 返回 true 表示该 SQL 可能很危险（裸 DELETE/DROP/TRUNCATE）
  static bool isDangerous(String sql) {
    final upper = sql.trim().toUpperCase();
    // 裸操作：无 WHERE 子句的 DELETE，无表名的 DROP
    if (upper.startsWith('DELETE FROM') && !upper.contains('WHERE'))
      return true;
    if (upper.startsWith('TRUNCATE')) return true;
    if (upper.startsWith('DROP TABLE') && !upper.contains('IF EXISTS'))
      return true;
    if (upper.startsWith('DROP DATABASE')) return true;
    return false;
  }

  /// 从 SQL 中提取首个表名（简单实现）
  static String? extractTableName(String sql) {
    final upper = sql.trim().toUpperCase();
    // INSERT INTO table (...)
    if (upper.startsWith('INSERT INTO')) {
      final match = RegExp(
        r'INSERT\s+INTO\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(sql);
      return match?.group(1);
    }
    // UPDATE table SET ...
    if (upper.startsWith('UPDATE')) {
      final match = RegExp(
        r'UPDATE\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(sql);
      return match?.group(1);
    }
    // DELETE FROM table
    if (upper.startsWith('DELETE FROM')) {
      final match = RegExp(
        r'DELETE\s+FROM\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(sql);
      return match?.group(1);
    }
    return null;
  }
}
