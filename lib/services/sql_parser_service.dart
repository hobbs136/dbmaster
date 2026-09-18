import 'package:dbmaster/models/sql_statement.dart';

/// Exception thrown when SQL parsing fails
class ParseException implements Exception {
  final String message;
  final int line;
  final int column;

  ParseException(this.message, {this.line = 0, this.column = 0});

  @override
  String toString() =>
      'ParseException: $message (line: $line, column: $column)';
}

/// Service for parsing and splitting SQL statements
class SQLParserService {
  /// Splits SQL text into individual statements
  ///
  /// Handles:
  /// - Semicolons inside strings
  /// - Escaped quotes
  /// - Line comments (--)
  /// - Block comments (/* */)
  /// - DELIMITER directive
  /// - Backtick identifiers
  /// - Unclosed structure detection
  static List<SQLStatement> split(String sql) {
    if (sql.trim().isEmpty) {
      return [];
    }

    final parser = _SQLParser(sql);
    return parser.parse();
  }

  /// Detects the SQL statement type from the SQL text.
  ///
  /// Cleans comments/strings first so leading comments and verbatim
  /// executable comments (kept by [split]) don't mask the leading keyword —
  /// a leading `--` comment used to make detectType return `other`.
  static SQLType detectType(String sql) {
    final trimmed = cleanForAnalysis(sql).trim().toUpperCase();

    if (trimmed.startsWith('SELECT')) {
      return SQLType.select;
    } else if (trimmed.startsWith('INSERT')) {
      return SQLType.insert;
    } else if (trimmed.startsWith('UPDATE')) {
      return SQLType.update;
    } else if (trimmed.startsWith('DELETE')) {
      return SQLType.delete;
    } else if (trimmed.startsWith('CALL') || trimmed.startsWith('EXEC')) {
      return SQLType.call;
    } else if (trimmed.startsWith('CREATE') ||
        trimmed.startsWith('ALTER') ||
        trimmed.startsWith('DROP') ||
        trimmed.startsWith('TRUNCATE')) {
      return SQLType.ddl;
    } else {
      return SQLType.other;
    }
  }

  /// Sub-classification within SQLType.ddl. Cleans first for the same
  /// reason as [detectType] (executable comments must not mask the keyword).
  static DdlSubType detectDdlSubType(String sql) {
    final trimmed = cleanForAnalysis(sql).trim().toUpperCase();
    if (trimmed.startsWith('DROP DATABASE') || trimmed.startsWith('DROP SCHEMA')) {
      return DdlSubType.dropDatabase;
    } else if (trimmed.startsWith('DROP TABLE')) {
      return DdlSubType.dropTable;
    } else if (trimmed.startsWith('TRUNCATE')) {
      return DdlSubType.truncate;
    } else if (trimmed.startsWith('ALTER TABLE') && _containsDropColumn(sql)) {
      return DdlSubType.alterDropColumn;
    } else if (trimmed.startsWith('ALTER')) {
      return DdlSubType.alterOther;
    } else if (trimmed.startsWith('CREATE')) {
      return DdlSubType.create;
    } else {
      return DdlSubType.unknown;
    }
  }

  /// Check if the SQL is a DELETE statement.
  static bool isDeleteStatement(String sql) =>
      detectType(sql) == SQLType.delete;

  /// Check if the SQL is an UPDATE statement.
  static bool isUpdateStatement(String sql) =>
      detectType(sql) == SQLType.update;

  /// Check if the SQL is a DROP statement.
  static bool isDropStatement(String sql) {
    final upper = sql.trim().toUpperCase();
    return upper.startsWith('DROP ');
  }

  /// Check if the SQL is a TRUNCATE statement.
  static bool isTruncateStatement(String sql) {
    final upper = sql.trim().toUpperCase();
    return upper.startsWith('TRUNCATE');
  }

  /// Check if the SQL contains a WHERE clause (outside comments and string literals).
  static bool hasWhereClause(String sql) {
    final cleaned = cleanForAnalysis(sql);
    return RegExp(r'\bWHERE\b', caseSensitive: false).hasMatch(cleaned);
  }

  /// Check if the SQL contains a LIMIT clause with a numeric value (outside comments and strings).
  static bool hasLimitClause(String sql) {
    final cleaned = cleanForAnalysis(sql);
    return RegExp(r'\bLIMIT\s+\d+', caseSensitive: false).hasMatch(cleaned);
  }

  /// Check if the SQL contains an ORDER BY clause (outside comments and string literals).
  static bool hasOrderClause(String sql) {
    final cleaned = cleanForAnalysis(sql);
    return RegExp(r'\bORDER\s+BY\b', caseSensitive: false).hasMatch(cleaned);
  }

  /// Extract the row-count value of the LIMIT clause (outside comments and strings).
  ///
  /// Returns the **count**, not the offset:
  /// - `LIMIT n` → n
  /// - `LIMIT offset, n` (MySQL) → n
  /// - `LIMIT n OFFSET m` (PostgreSQL) → n
  ///
  /// Returns null when there is no numeric LIMIT. Consumed by the EXPLAIN
  /// safety rules (R9/R10) to cap estimated rows against an existing LIMIT.
  static int? extractLimitValue(String sql) {
    final cleaned = cleanForAnalysis(sql);
    final match = RegExp(
      r'\bLIMIT\s+(\d+)(?:\s*,\s*(\d+))?',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (match == null) return null;
    // MySQL `LIMIT offset, count` 形式：第二个数字才是行数。
    final count = match.group(2) ?? match.group(1) ?? '';
    return int.tryParse(count);
  }

  /// Check whether the query's outer select list is a bare aggregate without
  /// GROUP BY — i.e. it always returns exactly one row regardless of table
  /// size (`SELECT COUNT(*) FROM t`), so a LIMIT clause is meaningless.
  ///
  /// Heuristic, same class as [hasLimitClause]/[extractLimitValue]: operates
  /// on the comment/string-stripped text ([cleanForAnalysis]); only a
  /// depth-0 aggregate call of the outer select list counts, so aggregates
  /// inside scalar subqueries don't trigger a false "single row". Window
  /// functions (`OVER (`) and UNION are treated conservatively as multi-row.
  /// Consumed by the safety rules (R3 missing_limit, R9/R10 EXPLAIN) to
  /// skip single-row aggregates before any DB roundtrip.
  static bool isSingleRowAggregate(String sql) {
    final cleaned = cleanForAnalysis(sql);
    final upper = cleaned.toUpperCase();

    // 带 GROUP BY 的聚合返回多行，LIMIT 仍有意义。
    if (RegExp(r'\bGROUP\s+BY\b').hasMatch(upper)) return false;
    // 窗口函数保守按多行处理（SUM(x) OVER (...) 返回行数 = 输入行数）。
    if (RegExp(r'\bOVER\s*\(').hasMatch(upper)) return false;

    // 外层 select 列表 = 顶层（括号深度 0）第一个 FROM 之前的片段。
    final fromAt = _topLevelFromIndex(upper);
    if (fromAt < 0) return false;

    return _hasDepthZeroAggregate(upper.substring(0, fromAt));
  }

  static final RegExp _aggregateFuncPrefix =
      RegExp(r'\b(COUNT|SUM|AVG|MIN|MAX)\s*\(');

  /// Index of the first top-level (paren depth 0) FROM in [upper], or -1.
  static int _topLevelFromIndex(String upper) {
    var depth = 0;
    for (var i = 0; i < upper.length; i++) {
      final ch = upper[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0 &&
          ch == 'F' &&
          upper.startsWith('FROM', i) &&
          _isWordBoundaryBefore(upper, i)) {
        return i;
      }
    }
    return -1;
  }

  /// Whether [segment] contains an aggregate function call at paren depth 0.
  static bool _hasDepthZeroAggregate(String segment) {
    var depth = 0;
    for (var i = 0; i < segment.length; i++) {
      final ch = segment[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0 &&
          _aggregateFuncPrefix.matchAsPrefix(segment, i) != null) {
        return true;
      }
    }
    return false;
  }

  /// Word-boundary check for keyword matching at [index] (preceding char is
  /// not a letter/digit/underscore).
  static bool _isWordBoundaryBefore(String text, int index) {
    if (index == 0) return true;
    final prev = text.codeUnitAt(index - 1);
    final isWord = (prev >= 0x30 && prev <= 0x39) ||
        (prev >= 0x41 && prev <= 0x5A) ||
        (prev >= 0x61 && prev <= 0x7A) ||
        prev == 0x5F;
    return !isWord;
  }

  /// Extract the content of the WHERE clause (up to GROUP/ORDER/LIMIT/HAVING/EOF).
  ///
  /// Returns `null` when there is no WHERE clause. Based on the comment/string
  /// stripped text so keywords inside comments or string literals don't fool
  /// the matcher. Consumed by [extractColumns] and safety rules
  /// (e.g. `FullTableScanRule`) that need to inspect WHERE predicates.
  static String? extractWhereClause(String sql) {
    final cleaned = cleanForAnalysis(sql);
    final match = RegExp(
      r'\bWHERE\s+(.+?)(?:\bGROUP\b|\bORDER\b|\bLIMIT\b|\bHAVING\b|$)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(cleaned);
    return match?.group(1);
  }

  /// Extract the target table name from a DML/DDL statement.
  /// Returns `null` if the table name cannot be reliably extracted.
  static String? extractTableName(String sql, SQLType type) {
    final cleaned = cleanForAnalysis(sql);
    final upper = cleaned.toUpperCase().trim();

    final tablePatterns = <String, RegExp>{
      'DELETE': RegExp(r'DELETE\s+FROM\s+`?(\w+)`?', caseSensitive: false),
      'UPDATE': RegExp(r'UPDATE\s+`?(\w+)`?', caseSensitive: false),
      'INSERT': RegExp(r'INSERT\s+INTO\s+`?(\w+)`?', caseSensitive: false),
      'DROP_TABLE': RegExp(r'DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?`?(\w+)`?', caseSensitive: false),
      'DROP_DATABASE': RegExp(r'DROP\s+(?:DATABASE|SCHEMA)\s+(?:IF\s+EXISTS\s+)?`?(\w+)`?', caseSensitive: false),
      'TRUNCATE': RegExp(r'TRUNCATE\s+(?:TABLE\s+)?`?(\w+)`?', caseSensitive: false),
    };

    String? matchPattern(String key) {
      final match = tablePatterns[key]!.firstMatch(cleaned);
      return match?.group(1);
    }

    switch (type) {
      case SQLType.delete:
        return matchPattern('DELETE');
      case SQLType.update:
        return matchPattern('UPDATE');
      case SQLType.insert:
        return matchPattern('INSERT');
      case SQLType.ddl:
        final upper2 = upper;
        if (upper2.startsWith('DROP TABLE')) return matchPattern('DROP_TABLE');
        if (upper2.startsWith('DROP DATABASE') || upper2.startsWith('DROP SCHEMA')) {
          return matchPattern('DROP_DATABASE');
        }
        if (upper2.startsWith('TRUNCATE')) return matchPattern('TRUNCATE');
        return null;
      default:
        // SELECT/其他：尝试提取 FROM 子句的表名。
        final fromMatch = RegExp(
          r'\bFROM\s+`?(\w+)`?',
          caseSensitive: false,
        ).firstMatch(cleaned);
        return fromMatch?.group(1);
    }
  }

  /// 提取 SQL 中引用的列名（用于 schema 兼容性检查）。
  ///
  /// 覆盖模式：
  /// - `SELECT col1, col2 FROM` → [col1, col2]
  /// - `SELECT * FROM` → []（无法提取，保守跳过）
  /// - `WHERE col = ...` → [col]
  /// - `INSERT INTO t (col1, col2)` → [col1, col2]
  ///
  /// **保守策略**：子查询/JOIN/别名/函数包裹的列不提取（返回空），
  /// 避免误报。宁可漏报也不误报——误报会降低用户对审查的信任。
  static List<String> extractColumns(String sql) {
    final cleaned = cleanForAnalysis(sql);
    final upper = cleaned.toUpperCase().trim();
    final columns = <String>[];

    // INSERT INTO t (col1, col2) VALUES ...
    if (upper.startsWith('INSERT')) {
      final insertMatch = RegExp(
        r'INSERT\s+INTO\s+`?\w+`?\s*\(([^)]+)\)',
        caseSensitive: false,
      ).firstMatch(cleaned);
      if (insertMatch != null) {
        final colList = insertMatch.group(1)!;
        for (final col in colList.split(',')) {
          final name = col.trim().replaceAll('`', '');
          if (name.isNotEmpty && _isValidColumnName(name)) {
            columns.add(name);
          }
        }
      }
      return columns;
    }

    // SELECT col1, col2 FROM ...（不含子查询/JOIN 的简单 SELECT）
    if (upper.startsWith('SELECT')) {
      // 含 JOIN → 保守返回空（JOIN 的多表列归属复杂，避免误判）。
      if (upper.contains(' JOIN ')) return [];
      // SELECT * → 跳过 SELECT 列区段提取（但 WHERE 列仍提取）。
      final isSelectStar = RegExp(r'SELECT\s+\*', caseSensitive: false)
          .hasMatch(cleaned.substring(0, cleaned.length > 12 ? 12 : cleaned.length));
      if (!isSelectStar) {
        final selectMatch = RegExp(
          r'SELECT\s+(.+?)\s+FROM\s+',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(cleaned);
        if (selectMatch != null) {
          final colSection = selectMatch.group(1)!;
          // 列区段含 '(' 视为函数/子查询，跳过整个 SELECT 列提取。
          if (!colSection.contains('(')) {
            for (final col in colSection.split(',')) {
              final name = col.trim().replaceAll('`', '');
              final parts = name.split('.');
              final colName = parts.last.trim();
              if (colName.isNotEmpty &&
                  _isValidColumnName(colName) &&
                  !colName.toUpperCase().contains(' AS ')) {
                columns.add(colName);
              }
            }
          }
        }
      }

      // WHERE 子句的列：col = / col IN / col LIKE 等。
      // 保守提取：WHERE 后的 `\w+ =` 或 `\w+ IN` 或 `\w+ LIKE` 模式。
      final whereClause = extractWhereClause(sql);
      if (whereClause != null) {
        // 提取 `word =` / `word IN` / `word LIKE` / `word >` / `word <` 模式。
        final colPattern = RegExp(r'`?(\w+)`?\s*(?:=|IN|LIKE|>|<|!=|IS|BETWEEN)', caseSensitive: false);
        for (final match in colPattern.allMatches(whereClause)) {
          final name = match.group(1)!;
          if (_isValidColumnName(name) && !columns.contains(name)) {
            columns.add(name);
          }
        }
      }

      return columns;
    }

    // UPDATE ... SET col1 = ..., col2 = ...
    if (upper.startsWith('UPDATE')) {
      final setMatch = RegExp(
        r'\bSET\s+(.+?)(?:\bWHERE\b|$)',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(cleaned);
      if (setMatch != null) {
        final setClause = setMatch.group(1)!;
        for (final part in setClause.split(',')) {
          final match = RegExp(r'`?(\w+)`?\s*=').firstMatch(part.trim());
          if (match != null) {
            final name = match.group(1)!;
            if (_isValidColumnName(name)) columns.add(name);
          }
        }
      }
      return columns;
    }

    return [];
  }

  /// 判断是否有效的列名（字母/数字/下划线，不以数字开头）。
  /// 用于过滤正则误提取的 SQL 关键字（如 SELECT、FROM、WHERE）。
  static bool _isValidColumnName(String name) {
    if (name.isEmpty) return false;
    // 过滤 SQL 关键字（不会被误判为列名）。
    const sqlKeywords = {
      'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'NULL',
      'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE',
      'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON',
      'GROUP', 'ORDER', 'BY', 'HAVING', 'LIMIT', 'AS',
      'DISTINCT', 'COUNT', 'SUM', 'AVG', 'MIN', 'MAX',
    };
    if (sqlKeywords.contains(name.toUpperCase())) return false;
    return RegExp(r'^[a-zA-Z_]\w*$').hasMatch(name);
  }

  /// Strip comments and string literals so keyword detection is not fooled by
  /// keywords appearing in comments or string values.
  ///
  /// Public so safety rules (e.g. `SqlInjectionRule`) can run their checks on
  /// the same cleaned text the parser uses. Note: comments (`--`, `/* */`) and
  /// quoted string contents are removed — rules that need to detect patterns
  /// *inside* comments or quotes (e.g. tautology `'x'='x'`) must operate on the
  /// raw SQL, not the cleaned output.
  ///
  /// MySQL executable comments are the exception: `/*! ... */` (incl. the
  /// versioned `/*!50003 ... */` form) has its content **executed** by MySQL,
  /// so the content is kept (markers and version prefix dropped). Stripping
  /// them as noise would hide statements from keyword detection (B6
  /// `executable_comment`).
  static String cleanForAnalysis(String sql) {
    final buffer = StringBuffer();
    int i = 0;
    while (i < sql.length) {
      final char = sql[i];

      // Line comment --
      if (char == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
        i += 2;
        while (i < sql.length && sql[i] != '\n') {
          i++;
        }
        buffer.write(' '); // preserve token boundary
        continue;
      }

      // Block comment /* */
      if (char == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
        final executable = i + 2 < sql.length && sql[i + 2] == '!';
        i += 2; // skip /*
        if (executable) {
          i++; // skip !
          // Skip the version prefix digits (engine directive, not SQL
          // content), e.g. /*!50003 ... */.
          while (i < sql.length && _isAsciiDigit(sql[i])) {
            i++;
          }
          final contentStart = i;
          while (i + 1 < sql.length &&
              !(sql[i] == '*' && sql[i + 1] == '/')) {
            i++;
          }
          if (i + 1 >= sql.length) {
            // Unterminated — MySQL rejects the statement; treat as noise.
            buffer.write(' ');
            i = sql.length;
            continue;
          }
          buffer.write(' '); // boundary before
          buffer.write(sql.substring(contentStart, i));
          buffer.write(' '); // boundary after
          i += 2; // skip */
          continue;
        }
        while (i + 1 < sql.length && !(sql[i] == '*' && sql[i + 1] == '/')) {
          i++;
        }
        if (i + 1 < sql.length) i += 2; // skip */
        buffer.write(' '); // preserve token boundary
        continue;
      }

      // Single-quoted string
      if (char == "'") {
        buffer.write("' '"); // placeholder for token boundary
        i++;
        while (i < sql.length) {
          if (sql[i] == '\\' && i + 1 < sql.length) {
            i += 2;
            continue;
          }
          if (sql[i] == "'") {
            if (i + 1 < sql.length && sql[i + 1] == "'") {
              i += 2; // escaped quote
              continue;
            }
            i++;
            break;
          }
          i++;
        }
        continue;
      }

      // Double-quoted string / identifier
      if (char == '"') {
        buffer.write('" "');
        i++;
        while (i < sql.length) {
          if (sql[i] == '\\' && i + 1 < sql.length) {
            i += 2;
            continue;
          }
          if (sql[i] == '"') {
            i++;
            break;
          }
          i++;
        }
        continue;
      }

      buffer.write(char);
      i++;
    }
    return buffer.toString();
  }

  /// 判断是否为 ASCII 数字（版本注释前缀扫描用）。
  static bool _isAsciiDigit(String char) {
    return char.length == 1 && char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;
  }

  static bool _containsDropColumn(String sql) {
    final cleaned = cleanForAnalysis(sql);
    return RegExp(r'\bDROP\s+COLUMN\b', caseSensitive: false).hasMatch(cleaned);
  }
}

/// Sub-type of DDL statement for fine-grained risk assessment.
enum DdlSubType {
  create,
  dropTable,
  dropDatabase,
  truncate,
  alterDropColumn,
  alterOther,
  unknown,
}

class _SQLParser {
  final String sql;
  final List<SQLStatement> statements = [];
  final StringBuffer currentStatement = StringBuffer();

  int currentLine = 1;
  int statementStartLine = -1;
  int i = 0;
  String delimiter = ';';

  _SQLParser(this.sql);

  List<SQLStatement> parse() {
    while (i < sql.length) {
      final char = sql[i];

      // Track line numbers and handle newlines as whitespace
      if (char == '\n') {
        currentLine++;
        // Add space for newline to separate tokens, but not if it's leading whitespace
        if (currentStatement.isNotEmpty) {
          currentStatement.write(' ');
        }
        i++;
        continue;
      }

      // Handle line comments
      if (char == '-' && _peek(1) == '-') {
        _skipLineComment();
        continue;
      }

      // Handle block comments — MySQL executable comments /*! ... */ are
      // kept verbatim in the statement: the engine (not the splitter)
      // decides their semantics (MySQL executes the content, other engines
      // ignore it). Stripping them silently dropped mysqldump-style
      // /*!40000 SET ... */ statements from execution and blinded safety
      // review (B6 executable_comment).
      if (char == '/' && _peek(1) == '*') {
        if (_peek(2) == '!') {
          _copyExecutableComment();
        } else {
          _skipBlockComment();
        }
        continue;
      }

      // Skip leading whitespace (spaces, tabs) and newlines before statement starts
      if ((char == ' ' || char == '\t' || char == '\r') &&
          currentStatement.isEmpty) {
        i++;
        continue;
      }

      // Set statement start line if not already set
      if (statementStartLine == -1) {
        statementStartLine = currentLine;
      }

      // Handle strings (single quotes)
      if (char == "'") {
        _parseString("'");
        continue;
      }

      // Handle strings (double quotes)
      if (char == '"') {
        _parseString('"');
        continue;
      }

      // Handle backtick identifiers
      if (char == '`') {
        _parseBacktickIdentifier();
        continue;
      }

      // Handle DELIMITER directive
      if (_isDelimiterDirective()) {
        _handleDelimiter();
        continue;
      }

      // Check for statement delimiter
      if (_matchesDelimiter()) {
        _endStatement();
        i += delimiter.length;
        continue;
      }

      currentStatement.write(char);
      i++;
    }

    // Handle last statement if exists
    if (currentStatement.toString().trim().isNotEmpty) {
      _endStatement();
    }

    return statements;
  }

  String? _peek(int offset) {
    final pos = i + offset;
    if (pos < 0 || pos >= sql.length) return null;
    return sql[pos];
  }

  void _skipLineComment() {
    // Skip -- and everything until end of line
    i += 2;
    while (i < sql.length && sql[i] != '\n') {
      i++;
    }
    if (i < sql.length && sql[i] == '\n') {
      currentLine++;
      i++;
    }
  }

  void _skipBlockComment() {
    // Skip /*
    i += 2;
    final startLine = currentLine;

    while (i < sql.length - 1) {
      if (sql[i] == '\n') {
        currentLine++;
      }
      if (sql[i] == '*' && sql[i + 1] == '/') {
        i += 2;
        return;
      }
      i++;
    }

    throw ParseException('Unclosed block comment', line: startLine);
  }

  /// Copies a MySQL executable comment `/*! ... */` verbatim (markers
  /// included) into the current statement. Delimiters inside are not split
  /// points — the comment is one atomic token for the splitter; how its
  /// content is treated is the engine's call.
  void _copyExecutableComment() {
    final startLine = currentLine;

    while (i < sql.length - 1) {
      final char = sql[i];
      if (char == '*' && sql[i + 1] == '/') {
        currentStatement.write('*/');
        i += 2;
        return;
      }
      if (char == '\n') {
        currentLine++;
        currentStatement.write(' '); // newline → token boundary
      } else {
        currentStatement.write(char);
      }
      i++;
    }

    throw ParseException('Unclosed block comment', line: startLine);
  }

  void _parseString(String quoteChar) {
    final startLine = currentLine;
    currentStatement.write(quoteChar);
    i++;

    while (i < sql.length) {
      final char = sql[i];

      if (char == '\n') {
        currentLine++;
      }

      currentStatement.write(char);

      // Handle backslash escape sequences (e.g., \', \", \\)
      if (char == '\\' && i + 1 < sql.length) {
        final nextChar = sql[i + 1];
        if (nextChar == quoteChar || nextChar == '\\') {
          i += 2;
          currentStatement.write(nextChar);
          continue;
        }
      }

      // Handle end of string or doubled quote escape (SQL standard)
      if (char == quoteChar) {
        if (i + 1 < sql.length && sql[i + 1] == quoteChar) {
          // Doubled quote is an escape sequence
          i += 2;
          currentStatement.write(quoteChar);
          continue;
        } else {
          // End of string
          i++;
          return;
        }
      }

      i++;
    }

    throw ParseException('Unclosed string literal', line: startLine);
  }

  void _parseBacktickIdentifier() {
    final startLine = currentLine;
    currentStatement.write('`');
    i++;

    while (i < sql.length) {
      final char = sql[i];
      currentStatement.write(char);

      if (char == '`') {
        // Check for escaped backtick (``)
        if (i + 1 < sql.length && sql[i + 1] == '`') {
          i += 2;
          currentStatement.write('`');
          continue;
        } else {
          i++;
          return;
        }
      }

      if (char == '\n') {
        currentLine++;
      }

      i++;
    }

    throw ParseException('Unclosed backtick identifier', line: startLine);
  }

  bool _isDelimiterDirective() {
    // 逐字符大小写无关比较，禁止 substring(i)+toUpperCase——那会为每个
    // 字符拷贝整个剩余文本，MB 级脚本上是 O(n²)（主循环每字符调用一次）。
    const kw = 'DELIMITER';
    // 指令必须后随分隔符值（至少一个字符），关键字顶到输入末尾即非指令。
    if (i + kw.length >= sql.length) return false;
    // 词边界（U08）：DELIMITER 只在语句开头生效，且后随空白——否则
    // `delimiter_table` 这类以 DELIMITER 为前缀的标识符会被误判成指令，
    // 语句被拦腰截断、分隔符被改成 "_table ..."。
    if (currentStatement.isNotEmpty) return false;
    final after = sql[i + kw.length];
    if (!_isWhitespace(after)) return false;
    for (var k = 0; k < kw.length; k++) {
      if (sql[i + k].toUpperCase() != kw[k]) return false;
    }
    return true;
  }

  void _handleDelimiter() {
    // First, end any current statement
    if (currentStatement.toString().trim().isNotEmpty) {
      _endStatement();
    }

    // Skip 'DELIMITER'
    i += 'DELIMITER'.length;

    // Skip whitespace
    while (i < sql.length && _isWhitespace(sql[i])) {
      if (sql[i] == '\n') {
        currentLine++;
      }
      i++;
    }

    // Read new delimiter - can be any character(s) until whitespace or end of line
    final newDelimiter = StringBuffer();
    while (i < sql.length && !_isWhitespace(sql[i])) {
      newDelimiter.write(sql[i]);
      i++;
    }

    if (newDelimiter.isEmpty) {
      throw ParseException(
        'DELIMITER directive requires a delimiter value',
        line: currentLine,
      );
    }

    delimiter = newDelimiter.toString();

    // Skip to end of line (including consuming the newline if present)
    while (i < sql.length && sql[i] != '\n') {
      i++;
    }
    if (i < sql.length && sql[i] == '\n') {
      currentLine++;
      i++;
    }

    // Reset statement start line for next statement
    statementStartLine = -1;
  }

  bool _matchesDelimiter() {
    final len = delimiter.length;
    if (i + len > sql.length) {
      return false;
    }
    // 主循环每字符调用，避免 substring 分配；长度通常为 1（';'）。
    for (var k = 0; k < len; k++) {
      if (sql[i + k] != delimiter[k]) return false;
    }
    return true;
  }

  void _endStatement() {
    final stmt = currentStatement.toString().trim();
    if (stmt.isNotEmpty) {
      statements.add(
        SQLStatement(
          index: statements.length,
          sql: stmt,
          type: SQLParserService.detectType(stmt),
          lineStart: statementStartLine,
          lineEnd: currentLine,
        ),
      );
    }
    currentStatement.clear();
    // Don't set statementStartLine here - it will be set when we encounter
    // the first non-whitespace character of the next statement
    statementStartLine = -1; // Mark as unset
  }

  bool _isWhitespace(String char) {
    return char == ' ' || char == '\t' || char == '\n' || char == '\r';
  }
}
