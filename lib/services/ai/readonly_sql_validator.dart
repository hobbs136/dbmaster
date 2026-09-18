/// AI 通用只读查询工具（run_readonly_query）的 SQL 安全闸门。
///
/// 校验原则：白名单放行 + 黑名单拦截，双层校验，任何不确定的情况一律拒绝。
/// 只做语法面校验（首关键字 / 子句 / 词级扫描），不做语义分析；执行侧另有
/// 各 adapter 的只读连接守卫（guardReadOnlyQuery）作为第二道防线。
///
/// 已知边界（有意为之的保守取舍）：
/// - SELECT ... INTO（建表 / 写文件 / 写变量）全拒——合法只读语句不需要 INTO；
/// - WITH CTE 与 EXPLAIN 语句做词级 DML 扫描——PostgreSQL 允许
///   `WITH x AS (DELETE ...) SELECT`、`EXPLAIN ANALYZE UPDATE ...` 会真执行；
/// - PRAGMA 仅对 SQLite 开放且仅只读名单（PRAGMA 可改库级状态）。
library;

/// 校验结果：allowed 为 true 放行；否则 reason 说明拒绝原因（模型可读）。
class ReadonlySqlCheck {
  const ReadonlySqlCheck.ok() : allowed = true, reason = null;

  const ReadonlySqlCheck.denied(String this.reason) : allowed = false;

  final bool allowed;
  final String? reason;
}

class ReadonlySqlValidator {
  ReadonlySqlValidator._();

  /// 允许的首关键字。PRAGMA 单独走 [validate] 的 SQLite 分支。
  static const Set<String> _allowedPrefixes = {
    'SELECT',
    'WITH',
    'SHOW',
    'EXPLAIN',
    'DESCRIBE',
    'DESC',
  };

  /// SQLite 允许的只读 PRAGMA 名单（可枚举元数据；其余 PRAGMA 可写库状态）。
  static const Set<String> _allowedSqlitePragmas = {
    'TABLE_INFO',
    'TABLE_LIST',
    'FOREIGN_KEY_LIST',
    'INDEX_LIST',
    'INDEX_INFO',
    'INDEX_XINFO',
    'DATABASE_LIST',
    'COLLATION_LIST',
    'FUNCTION_LIST',
    'MODULE_LIST',
    'PRAGMA_LIST',
  };

  /// 全语句黑名单子句（对放行的前缀也生效）。
  static final List<RegExp> _bannedClausePatterns = [
    RegExp(r'\bINTO\b', caseSensitive: false),
    RegExp(r'\bFOR\s+UPDATE\b', caseSensitive: false),
    RegExp(r'\bFOR\s+SHARE\b', caseSensitive: false),
    RegExp(r'\bLOCK\s+IN\s+SHARE\s+MODE\b', caseSensitive: false),
    // MySQL 会话变量赋值（SELECT @a := ...，写会话状态）
    RegExp(r':=', caseSensitive: false),
  ];

  /// WITH / EXPLAIN 前缀语句的词级禁词（CTE 可藏 DML；EXPLAIN ANALYZE 会真执行）。
  static const List<String> _dmlWords = [
    'INSERT',
    'UPDATE',
    'DELETE',
    'MERGE',
    'REPLACE',
    'TRUNCATE',
    'CREATE',
    'ALTER',
    'DROP',
    'GRANT',
    'REVOKE',
    'CALL',
    'EXEC',
    'EXECUTE',
    'SET',
    'USE',
    'ATTACH',
    'DETACH',
    'REINDEX',
    'VACUUM',
    'ANALYZE',
    'PRAGMA',
    'INTO',
    'LOAD',
    'COPY',
  ];

  /// 校验 [sql] 是否为允许 AI 执行的单条只读语句。
  ///
  /// [isSqlite] 控制 PRAGMA 是否放行（仅 SQLite 且仅只读名单）。
  static ReadonlySqlCheck validate(String sql, {required bool isSqlite}) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) {
      return const ReadonlySqlCheck.denied('Statement is empty');
    }

    final masked = _maskLiterals(trimmed);

    // 单语句约束：去掉尾部多余分号后，句中不得再出现分号
    var body = masked;
    while (body.endsWith(';')) {
      body = body.substring(0, body.length - 1).trimRight();
    }
    if (RegExp(';').hasMatch(body)) {
      return const ReadonlySqlCheck.denied(
        'Only a single statement is allowed',
      );
    }

    final prefixMatch = RegExp(r'^[A-Za-z]+').firstMatch(body);
    if (prefixMatch == null) {
      return const ReadonlySqlCheck.denied(
        'Statement must start with a SQL keyword',
      );
    }
    final prefix = prefixMatch.group(0)!.toUpperCase();

    if (prefix == 'PRAGMA') {
      if (!isSqlite) {
        return const ReadonlySqlCheck.denied(
          'PRAGMA is only allowed on SQLite connections',
        );
      }
      final nameMatch = RegExp(
        r'^\s*PRAGMA\s+([A-Za-z0-9_]+)',
      ).firstMatch(body);
      final pragma = nameMatch?.group(1)?.toUpperCase() ?? '';
      if (!_allowedSqlitePragmas.contains(pragma)) {
        return ReadonlySqlCheck.denied(
          'PRAGMA $pragma is not in the read-only allowlist',
        );
      }
      return const ReadonlySqlCheck.ok();
    }

    if (!_allowedPrefixes.contains(prefix)) {
      return ReadonlySqlCheck.denied(
        '"$prefix" is not a read-only statement; only '
        'SELECT / WITH ... SELECT / SHOW / EXPLAIN / DESCRIBE are allowed',
      );
    }

    for (final pattern in _bannedClausePatterns) {
      if (pattern.hasMatch(body)) {
        return ReadonlySqlCheck.denied(
          'Read-only statements must not contain "${pattern.pattern}"',
        );
      }
    }

    if (prefix == 'WITH' || prefix == 'EXPLAIN') {
      for (final word in _dmlWords) {
        if (RegExp('\\b$word\\b', caseSensitive: false).hasMatch(body)) {
          return ReadonlySqlCheck.denied(
            '"$word" is not allowed inside a $prefix statement',
          );
        }
      }
    }

    return const ReadonlySqlCheck.ok();
  }

  /// 把 SQL 中的字符串字面量 / 引号标识符 / 注释内容替换为等长空格，
  /// 使后续结构扫描（分号 / 关键词）不受字面量与注释内容干扰——
  /// 否则 `WHERE note = 'please delete me'` 或 `/* ; */` 会误伤/漏判。
  static String _maskLiterals(String sql) {
    final buf = StringBuffer();
    var i = 0;
    while (i < sql.length) {
      final ch = sql[i];
      if (ch == "'" || ch == '"' || ch == '`') {
        var j = i + 1;
        while (j < sql.length) {
          if (sql[j] == ch) {
            // 引号转义（'' / "" / ``）仍在字面量内
            if (j + 1 < sql.length && sql[j + 1] == ch) {
              j += 2;
              continue;
            }
            break;
          }
          if (sql[j] == r'\' && ch != '`' && j + 1 < sql.length) {
            j += 2; // 反斜杠转义
            continue;
          }
          j++;
        }
        buf.write(ch);
        for (var k = i + 1; k < j && k < sql.length; k++) {
          buf.write(' ');
        }
        if (j < sql.length) buf.write(ch);
        i = j + 1;
      } else if (ch == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
        var j = i;
        while (j < sql.length && sql[j] != '\n') {
          j++;
        }
        for (var k = i; k < j; k++) {
          buf.write(' ');
        }
        i = j;
      } else if (ch == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
        var j = i + 2;
        while (j + 1 < sql.length && !(sql[j] == '*' && sql[j + 1] == '/')) {
          j++;
        }
        final end = j + 1 < sql.length ? j + 2 : sql.length;
        for (var k = i; k < end; k++) {
          buf.write(' ');
        }
        i = end;
      } else {
        buf.write(ch);
        i++;
      }
    }
    return buf.toString();
  }
}
