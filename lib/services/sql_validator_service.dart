import 'dart:collection';

/// T011: 轻量级 SQL 语法校验器
/// 使用正则表达式检查常见语法错误，无需额外依赖
class SQLValidatorService {
  static final _keywords = {
    'SELECT',
    'INSERT',
    'UPDATE',
    'DELETE',
    'FROM',
    'WHERE',
    'JOIN',
    'LEFT',
    'RIGHT',
    'INNER',
    'OUTER',
    'ON',
    'GROUP',
    'BY',
    'ORDER',
    'HAVING',
    'LIMIT',
    'OFFSET',
    'UNION',
    'ALL',
    'DISTINCT',
    'CREATE',
    'TABLE',
    'ALTER',
    'DROP',
    'INDEX',
    'VIEW',
    'AND',
    'OR',
    'NOT',
    'NULL',
    'IS',
    'IN',
    'BETWEEN',
    'LIKE',
    'EXISTS',
    'CASE',
    'WHEN',
    'THEN',
    'ELSE',
    'END',
    'AS',
    'ASC',
    'DESC',
    'VALUES',
    'SET',
  };

  /// 校验 SQL 语句，返回错误列表
  static List<SqlValidationError> validate(String sql) {
    final errors = <SqlValidationError>[];
    if (sql.trim().isEmpty) return errors;

    // 检查括号匹配
    errors.addAll(_checkParentheses(sql));

    // 检查引号匹配
    errors.addAll(_checkQuotes(sql));

    // 检查分号使用
    errors.addAll(_checkSemicolons(sql));

    // 检查关键字拼写（简单的常见错误）
    errors.addAll(_checkKeywordSpelling(sql));

    // 检查 SELECT * 警告
    errors.addAll(_checkSelectAll(sql));

    return errors;
  }

  /// 快速校验：只返回是否有错误
  static bool isValid(String sql) {
    return validate(sql).isEmpty;
  }

  /// 获取指定行的错误
  static List<SqlValidationError> getErrorsForLine(
    List<SqlValidationError> errors,
    int lineNumber,
  ) {
    return errors.where((e) => e.line == lineNumber).toList();
  }

  static List<SqlValidationError> _checkParentheses(String sql) {
    final errors = <SqlValidationError>[];
    final stack = Queue<int>();
    final lines = sql.split('\n');

    for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final line = lines[lineIdx];
      for (int i = 0; i < line.length; i++) {
        final char = line[i];
        if (char == '(') {
          stack.addLast(lineIdx + 1);
        } else if (char == ')') {
          if (stack.isEmpty) {
            errors.add(
              SqlValidationError(
                line: lineIdx + 1,
                column: i + 1,
                message: 'Unexpected closing parenthesis',
                severity: ErrorSeverity.error,
              ),
            );
          } else {
            stack.removeLast();
          }
        }
      }
      // lineOffset tracking removed — was write-only, never read
    }

    // 未闭合的括号
    for (final line in stack) {
      errors.add(
        SqlValidationError(
          line: line,
          column: 1,
          message: 'Unclosed parenthesis',
          severity: ErrorSeverity.error,
        ),
      );
    }

    return errors;
  }

  static List<SqlValidationError> _checkQuotes(String sql) {
    final errors = <SqlValidationError>[];
    final lines = sql.split('\n');

    for (int lineIdx = 0; lineIdx < lines.length; lineIdx++) {
      final line = lines[lineIdx];
      bool inSingleQuote = false;
      bool inDoubleQuote = false;

      for (int i = 0; i < line.length; i++) {
        final char = line[i];
        final prev = i > 0 ? line[i - 1] : '';

        if (char == "'" && prev != '\\') {
          inSingleQuote = !inSingleQuote;
        } else if (char == '"' && prev != '\\') {
          inDoubleQuote = !inDoubleQuote;
        }
      }

      if (inSingleQuote) {
        errors.add(
          SqlValidationError(
            line: lineIdx + 1,
            column: line.length,
            message: 'Unclosed single quote',
            severity: ErrorSeverity.error,
          ),
        );
      }
      if (inDoubleQuote) {
        errors.add(
          SqlValidationError(
            line: lineIdx + 1,
            column: line.length,
            message: 'Unclosed double quote',
            severity: ErrorSeverity.warning,
          ),
        );
      }
    }

    return errors;
  }

  static List<SqlValidationError> _checkSemicolons(String sql) {
    final errors = <SqlValidationError>[];
    final trimmed = sql.trim();

    if (trimmed.isEmpty) return errors;

    // 检查是否以分号结尾（多条语句时）
    final statements = trimmed.split(';');
    if (statements.length > 2) {
      // 多条语句，最后一条可能是空的
      final lastNonEmpty = statements
          .where((s) => s.trim().isNotEmpty)
          .lastOrNull;
      if (lastNonEmpty != null && !trimmed.endsWith(';')) {
        final lines = sql.split('\n');
        errors.add(
          SqlValidationError(
            line: lines.length,
            column: lines.last.length,
            message: 'Multiple statements should end with semicolon',
            severity: ErrorSeverity.warning,
          ),
        );
      }
    }

    return errors;
  }

  static List<SqlValidationError> _checkKeywordSpelling(String sql) {
    final errors = <SqlValidationError>[];

    // H2 FIX: 逐字符遍历，准确跟踪行列位置
    int line = 1;
    int col = 1;
    int wordStartCol = 1;
    int wordStartLine = 1;
    final currentWord = StringBuffer();

    for (int i = 0; i < sql.length; i++) {
      final char = sql[i];

      if (char == '\n') {
        // 处理当前单词
        _checkWord(currentWord.toString(), wordStartLine, wordStartCol, errors);
        currentWord.clear();
        line++;
        col = 1;
        wordStartCol = 1;
        wordStartLine = line;
      } else if (_isWordSeparator(char)) {
        // 分隔符
        _checkWord(currentWord.toString(), wordStartLine, wordStartCol, errors);
        currentWord.clear();
        wordStartCol = col + 1;
        wordStartLine = line;
        col++;
      } else {
        // 单词字符
        if (currentWord.isEmpty) {
          wordStartLine = line;
          wordStartCol = col;
        }
        currentWord.write(char);
        col++;
      }
    }

    // 处理最后一个单词
    _checkWord(currentWord.toString(), wordStartLine, wordStartCol, errors);

    return errors;
  }

  /// 单词分隔符（原正则 `[\s\(\),;]` 的直接字符比较——循环内每字符调用，
  /// 禁止在循环里构造 RegExp，MB 级文本上是显著开销）。
  static bool _isWordSeparator(String char) {
    return char == ' ' ||
        char == '\t' ||
        char == '\r' ||
        char == '\n' ||
        char == '\f' ||
        char == '\v' ||
        char == '(' ||
        char == ')' ||
        char == ',' ||
        char == ';';
  }

  /// 关键词表中最长关键词的长度（词长超出 longest+1 时编辑距离不可能为 1）。
  static final int _maxKeywordLength = _keywords
      .map((k) => k.length)
      .reduce((a, b) => a > b ? a : b);

  static void _checkWord(
    String word,
    int wordLine,
    int wordCol,
    List<SqlValidationError> errors,
  ) {
    if (word.length < 3) return;
    // 长词剪枝：编辑距离为 1 要求长度差 ≤ 1。长注释串/长标识符（中文
    // COMMENT 里整段引号内容会被当一个词）直接跳过，否则每词 × 全关键词
    // 表的 Levenshtein DP 在大文本上是秒级开销。
    if (word.length > _maxKeywordLength + 1) return;

    final upper = word.toUpperCase();
    if (_keywords.contains(upper)) return;

    // 检查是否是关键字拼写错误（编辑距离为1）
    for (final keyword in _keywords) {
      if ((upper.length - keyword.length).abs() > 1) continue;
      if (_levenshteinDistance(upper, keyword) == 1) {
        errors.add(
          SqlValidationError(
            line: wordLine,
            column: wordCol,
            message: 'Did you mean "$keyword"?',
            severity: ErrorSeverity.warning,
          ),
        );
        break;
      }
    }
  }

  static List<SqlValidationError> _checkSelectAll(String sql) {
    final errors = <SqlValidationError>[];
    final selectAllPattern = RegExp(r'SELECT\s+\*', caseSensitive: false);
    final lines = sql.split('\n');

    for (int i = 0; i < lines.length; i++) {
      if (selectAllPattern.hasMatch(lines[i])) {
        errors.add(
          SqlValidationError(
            line: i + 1,
            column: lines[i].toUpperCase().indexOf('SELECT') + 1,
            message: 'Avoid SELECT * in production code',
            severity: ErrorSeverity.info,
          ),
        );
      }
    }

    return errors;
  }

  /// 计算编辑距离
  static int _levenshteinDistance(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    final v0 = List<int>.filled(t.length + 1, 0);
    final v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = s[i] == t[j] ? 0 : 1;
        // 行内取最小值，避免每单元格分配临时 List（大文本热路径）。
        var min = v1[j] + 1;
        final b = v0[j + 1] + 1;
        if (b < min) min = b;
        final c = v0[j] + cost;
        if (c < min) min = c;
        v1[j + 1] = min;
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[t.length];
  }
}

/// SQL 校验错误
class SqlValidationError {
  final int line;
  final int column;
  final String message;
  final ErrorSeverity severity;

  const SqlValidationError({
    required this.line,
    required this.column,
    required this.message,
    required this.severity,
  });

  @override
  String toString() => 'Line $line, Col $column: $message';
}

/// 错误严重程度
enum ErrorSeverity { info, warning, error }
