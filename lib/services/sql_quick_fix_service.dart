import 'dart:async';
import 'database_service.dart';
import 'sql_formatter_service.dart';
import '../models/formatter_models.dart';
import '../utils/app_logger.dart';

/// SQL 快速修复服务
/// 提供自动修复 SQL 问题的功能
class SQLQuickFixService {
  final DatabaseService _dbService;

  SQLQuickFixService(this._dbService);

  /// 应用快速修复
  Future<String?> applyFix(
    String sql,
    String action, {
    Map<String, dynamic>? parameters,
  }) async {
    try {
      switch (action) {
        case 'add_limit':
          return _addLimitClause(sql);
        case 'expand_select_star':
          return await _expandSelectStar(sql);
        case 'convert_to_join':
          return _convertSubqueryToJoin(sql);
        case 'add_index_hint':
          return _addIndexHint(sql);
        case 'parameterize_query':
          return _parameterizeQuery(sql);
        case 'suggest_fulltext_index':
          return _suggestFulltextIndex(sql);
        case 'use_explicit_join':
          return _useExplicitJoin(sql);
        case 'add_table_alias':
          return _addTableAlias(sql);
        case 'format_sql':
          return _formatSQL(sql);
        default:
          AppLogger.w('SQLQuickFix', '未知的修复操作: $action');
          return null;
      }
    } catch (e) {
      AppLogger.e('SQLQuickFix', '应用修复失败: $e');
      return null;
    }
  }

  /// 添加 LIMIT 子句
  String _addLimitClause(String sql) {
    final upperSql = sql.toUpperCase().trim();

    // 检查是否已有 LIMIT
    if (upperSql.contains('LIMIT')) {
      return sql;
    }

    // 检查是否以分号结尾
    final hasSemicolon = sql.trim().endsWith(';');
    final baseSql = hasSemicolon
        ? sql.trim().substring(0, sql.trim().length - 1)
        : sql.trim();

    // 添加 LIMIT
    return '$baseSql\nLIMIT 100${hasSemicolon ? ';' : ''}';
  }

  /// 展开 SELECT *
  Future<String?> _expandSelectStar(String sql) async {
    if (!_dbService.isConnected) return null;

    // 提取表名
    final tableMatch = RegExp(
      r'FROM\s+(\w+)',
      caseSensitive: false,
    ).firstMatch(sql);

    if (tableMatch == null) return null;

    final tableName = tableMatch.group(1)!;

    try {
      // 获取表的列信息
      final columns = await _dbService.getTableColumns(tableName);
      if (columns.isEmpty) return null;

      // 构建列名字符串
      final columnNames = columns.map((c) => c.name).join(', ');

      // 替换 SELECT *
      return sql.replaceFirst(
        RegExp(r'SELECT\s+\*', caseSensitive: false),
        'SELECT $columnNames',
      );
    } catch (e) {
      AppLogger.w('SQLQuickFix', '展开 SELECT * 失败: $e');
      return null;
    }
  }

  /// 转换子查询为 JOIN
  String _convertSubqueryToJoin(String sql) {
    // 简单的 IN 子查询转 JOIN
    // 示例: SELECT * FROM a WHERE id IN (SELECT id FROM b)
    // 转为: SELECT DISTINCT a.* FROM a JOIN b ON a.id = b.id

    final inSubqueryPattern = RegExp(
      r'(\w+)\s+IN\s*\(\s*SELECT\s+(\w+)\s+FROM\s+(\w+)\s*\)',
      caseSensitive: false,
    );

    var result = sql;
    final matches = inSubqueryPattern.allMatches(sql);

    for (final match in matches) {
      final column = match.group(1)!;
      final subColumn = match.group(2)!;
      final subTable = match.group(3)!;

      // 提取主表名（简化处理）
      final fromMatch = RegExp(
        r'FROM\s+(\w+)',
        caseSensitive: false,
      ).firstMatch(sql);
      if (fromMatch == null) continue;

      final mainTable = fromMatch.group(1)!;

      // 构建 JOIN 语句
      final joinClause =
          'JOIN $subTable ON $mainTable.$column = $subTable.$subColumn';

      // 替换 WHERE 子句中的 IN 条件
      result = result.replaceFirst(
        match.group(0)!,
        '1=1', // 简化处理，实际需要更复杂的逻辑
      );

      // 在 FROM 后添加 JOIN
      result = result.replaceFirst(
        RegExp(r'(FROM\s+\w+)', caseSensitive: false),
        '\$1 $joinClause',
      );
    }

    return result;
  }

  /// 添加索引提示
  String _addIndexHint(String sql) {
    // 提取 WHERE 子句中的列
    final whereMatch = RegExp(
      r'WHERE\s+(.+?)(?:ORDER|GROUP|LIMIT|$)',
      caseSensitive: false,
    ).firstMatch(sql);

    if (whereMatch == null) return sql;

    final whereClause = whereMatch.group(1)!;

    // 提取列名
    final columnPattern = RegExp(r'(\w+)\s*[=<>]');
    final columns = columnPattern
        .allMatches(whereClause)
        .map((m) => m.group(1))
        .where((c) => c != null)
        .toList();

    if (columns.isEmpty) return sql;

    // 添加索引提示注释
    final indexHint = '-- 建议为这些列添加索引: ${columns.join(', ')}\n';
    return indexHint + sql;
  }

  /// 参数化查询
  String _parameterizeQuery(String sql) {
    var result = sql;
    var paramIndex = 1;

    // 替换字符串字面量为参数占位符
    final stringPattern = RegExp(r"'[^']*'");
    final matches = stringPattern.allMatches(sql).toList().reversed;

    for (final match in matches) {
      // 检查是否是表名或列名（简化判断）
      final before = sql.substring(0, match.start).trim();
      if (before.endsWith('LIKE') ||
          before.endsWith('=') ||
          before.endsWith('IN') ||
          before.endsWith('>') ||
          before.endsWith('<')) {
        result = result.replaceRange(
          match.start,
          match.end,
          '?', // 使用 ? 作为参数占位符
        );
        paramIndex++;
      }
    }

    // 添加参数说明注释
    if (paramIndex > 1) {
      final paramComment = '-- 参数化查询: 需要 ${paramIndex - 1} 个参数\n';
      result = paramComment + result;
    }

    return result;
  }

  /// 建议全文索引
  String _suggestFulltextIndex(String sql) {
    // 提取 LIKE 模式
    final likeMatch = RegExp(
      r"LIKE\s+'([^']+)'",
      caseSensitive: false,
    ).firstMatch(sql);

    if (likeMatch == null) return sql;

    final pattern = likeMatch.group(1)!;

    // 检查是否是前导通配符
    if (!pattern.startsWith('%')) return sql;

    // 提取列名
    final columnMatch = RegExp(
      r'(\w+)\s+LIKE',
      caseSensitive: false,
    ).firstMatch(sql);

    if (columnMatch == null) return sql;

    final column = columnMatch.group(1)!;

    // 添加全文索引建议注释
    final suggestion =
        '''-- 建议为列 '$column' 添加全文索引:
-- ALTER TABLE table_name ADD FULLTEXT INDEX idx_fulltext_$column ($column);
-- 然后使用 MATCH ... AGAINST 替代 LIKE:
-- WHERE MATCH($column) AGAINST('${pattern.replaceAll('%', '')}' IN NATURAL LANGUAGE MODE)

$sql''';
    return suggestion;
  }

  /// 使用显式 JOIN 语法
  String _useExplicitJoin(String sql) {
    // 将逗号分隔的 FROM 子句转换为 JOIN
    // 示例: FROM a, b WHERE a.id = b.id
    // 转为: FROM a JOIN b ON a.id = b.id

    final commaFromPattern = RegExp(
      r'FROM\s+(\w+)\s*,\s*(\w+)',
      caseSensitive: false,
    );

    var result = sql;
    final matches = commaFromPattern.allMatches(sql);

    for (final match in matches) {
      final table1 = match.group(1)!;
      final table2 = match.group(2)!;

      // 查找 WHERE 子句中的连接条件
      final joinConditionPattern = RegExp(
        '$table1\\.(\\w+)\\s*=\\s*$table2\\.(\\w+)',
        caseSensitive: false,
      );

      final conditionMatch = joinConditionPattern.firstMatch(sql);

      if (conditionMatch != null) {
        final col1 = conditionMatch.group(1)!;
        final col2 = conditionMatch.group(2)!;

        // 替换为显式 JOIN
        result = result.replaceFirst(
          match.group(0)!,
          'FROM $table1 JOIN $table2 ON $table1.$col1 = $table2.$col2',
        );

        // 移除 WHERE 中的连接条件
        result = result.replaceFirst(conditionMatch.group(0)!, '1=1');
      }
    }

    return result;
  }

  /// 添加表别名
  String _addTableAlias(String sql) {
    // 为长表名添加别名
    final longTablePattern = RegExp(
      r'FROM\s+([a-z_]{20,})',
      caseSensitive: false,
    );

    var result = sql;
    final matches = longTablePattern.allMatches(sql);

    for (final match in matches) {
      final tableName = match.group(1)!;

      // 生成别名（取前3个字母）
      final alias = tableName.substring(0, 3).toLowerCase();

      // 替换表引用
      result = result.replaceAll(
        RegExp('\\b$tableName\\.', caseSensitive: false),
        '$alias.',
      );

      // 在 FROM 中添加别名
      result = result.replaceFirst(
        'FROM $tableName',
        'FROM $tableName AS $alias',
      );
    }

    return result;
  }

  /// 格式化 SQL
  String _formatSQL(String sql) {
    // 委托给 SqlFormatterService 进行专业格式化
    final formatter = SqlFormatterService();
    return formatter.format(sql, const FormatterOptions());
  }

  /// 获取所有可用的快速修复
  List<QuickFixAction> getAvailableFixes(String sql) {
    final fixes = <QuickFixAction>[];
    final upperSql = sql.toUpperCase();

    // 检查 SELECT *
    if (RegExp(r'SELECT\s+\*').hasMatch(upperSql)) {
      fixes.add(
        QuickFixAction(
          id: 'expand_select_star',
          label: '展开 SELECT * 为具体列名',
          description: '将 * 替换为表的所有列名',
        ),
      );
    }

    // 检查缺少 LIMIT
    if (upperSql.contains('SELECT') && !upperSql.contains('LIMIT')) {
      fixes.add(
        QuickFixAction(
          id: 'add_limit',
          label: '添加 LIMIT 子句',
          description: '添加 LIMIT 100 防止返回大量数据',
        ),
      );
    }

    // 检查子查询
    if (upperSql.contains('(SELECT')) {
      fixes.add(
        QuickFixAction(
          id: 'convert_to_join',
          label: '转换为 JOIN',
          description: '将子查询转换为 JOIN 语法',
        ),
      );
    }

    // 检查逗号 JOIN
    if (RegExp(r'FROM\s+\w+\s*,\s*\w+').hasMatch(upperSql)) {
      fixes.add(
        QuickFixAction(
          id: 'use_explicit_join',
          label: '使用显式 JOIN',
          description: '将逗号分隔的表转换为 JOIN 语法',
        ),
      );
    }

    // 检查 LIKE 前导通配符
    if (RegExp("LIKE\\s+[\\'\"]%").hasMatch(upperSql)) {
      fixes.add(
        QuickFixAction(
          id: 'suggest_fulltext_index',
          label: '建议全文索引',
          description: '为前导通配符 LIKE 添加全文索引建议',
        ),
      );
    }

    // 始终可用的修复
    fixes.add(
      QuickFixAction(
        id: 'format_sql',
        label: '格式化 SQL',
        description: '自动格式化 SQL 代码',
      ),
    );

    return fixes;
  }
}

/// 快速修复操作
class QuickFixAction {
  final String id;
  final String label;
  final String description;

  QuickFixAction({
    required this.id,
    required this.label,
    required this.description,
  });
}
