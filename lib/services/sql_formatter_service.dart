import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/formatter_models.dart';

/// SQL 格式化服务
/// 提供 SQL 代码格式化、解析和语法高亮功能
class SqlFormatterService {
  static const String _presetsKey = 'sql_formatter_presets';
  static const String _historyKey = 'sql_formatter_history';
  static const int _maxHistoryItems = 50;

  // SQL 关键字列表
  static const Set<String> _keywords = {
    'SELECT',
    'FROM',
    'WHERE',
    'INSERT',
    'UPDATE',
    'DELETE',
    'CREATE',
    'DROP',
    'ALTER',
    'TABLE',
    'INDEX',
    'VIEW',
    'JOIN',
    'INNER',
    'OUTER',
    'LEFT',
    'RIGHT',
    'FULL',
    'CROSS',
    'ON',
    'AND',
    'OR',
    'NOT',
    'NULL',
    'IS',
    'IN',
    'EXISTS',
    'BETWEEN',
    'LIKE',
    'GROUP',
    'BY',
    'ORDER',
    'HAVING',
    'LIMIT',
    'OFFSET',
    'UNION',
    'ALL',
    'DISTINCT',
    'AS',
    'CASE',
    'WHEN',
    'THEN',
    'ELSE',
    'END',
    'IF',
    'ELSEIF',
    'WHILE',
    'FOR',
    'LOOP',
    'RETURN',
    'DECLARE',
    'SET',
    'VALUES',
    'INTO',
    'PRIMARY',
    'KEY',
    'FOREIGN',
    'REFERENCES',
    'UNIQUE',
    'CHECK',
    'DEFAULT',
    'AUTO_INCREMENT',
    'NOT NULL',
    'INT',
    'VARCHAR',
    'TEXT',
    'DATE',
    'DATETIME',
    'TIMESTAMP',
    'DECIMAL',
    'FLOAT',
    'DOUBLE',
    'BOOL',
    'BOOLEAN',
    'CHAR',
    'BLOB',
    'JSON',
    'ENUM',
    'SHOW',
    'DESCRIBE',
    'EXPLAIN',
    'USE',
    'DATABASE',
    'SCHEMA',
    'TRUNCATE',
    'COMMIT',
    'ROLLBACK',
    'BEGIN',
    'TRANSACTION',
    'GRANT',
    'REVOKE',
    'PRIVILEGES',
    'LOCK',
    'UNLOCK',
  };

  // 函数关键字列表
  static const Set<String> _functions = {
    'COUNT',
    'SUM',
    'AVG',
    'MAX',
    'MIN',
    'CONCAT',
    'SUBSTRING',
    'LENGTH',
    'UPPER',
    'LOWER',
    'TRIM',
    'LTRIM',
    'RTRIM',
    'REPLACE',
    'NOW',
    'CURDATE',
    'CURTIME',
    'DATE',
    'TIME',
    'YEAR',
    'MONTH',
    'DAY',
    'HOUR',
    'MINUTE',
    'SECOND',
    'DATE_FORMAT',
    'STR_TO_DATE',
    'CAST',
    'CONVERT',
    'COALESCE',
    'IFNULL',
    'NULLIF',
    'CASE',
    'WHEN',
    'ROUND',
    'FLOOR',
    'CEILING',
    'ABS',
    'POWER',
    'SQRT',
    'MOD',
    'RAND',
    'UUID',
    'MD5',
    'SHA1',
    'SHA2',
    'INET_ATON',
    'INET_NTOA',
    'JSON_EXTRACT',
    'JSON_ARRAY',
    'JSON_OBJECT',
    'ROW_NUMBER',
    'RANK',
    'DENSE_RANK',
    'LEAD',
    'LAG',
    'FIRST_VALUE',
    'LAST_VALUE',
  };

  // 运算符列表
  static const Set<String> _operators = {
    '=',
    '<',
    '>',
    '<=',
    '>=',
    '<>',
    '!=',
    '+',
    '-',
    '*',
    '/',
    '%',
    '||',
    '&&',
    '!',
    '~',
    '&',
    '|',
    '^',
    '<<',
    '>>',
  };

  /// 格式化 SQL 代码
  String format(String sql, FormatterOptions options) {
    if (sql.trim().isEmpty) return '';

    try {
      // 解析 SQL 为 token 列表
      final tokens = _tokenize(sql);

      // 应用格式化
      return _applyFormat(tokens, options);
    } catch (e) {
      // 格式化失败时返回原 SQL
      return sql;
    }
  }

  /// 将 SQL 解析为 token 列表
  List<SqlToken> _tokenize(String sql) {
    final tokens = <SqlToken>[];
    final buffer = StringBuffer();
    var i = 0;
    var inString = false;
    var stringChar = '';
    var inComment = false;
    var commentType = ''; // '--', '/*'
    var inBacktick = false;

    while (i < sql.length) {
      final char = sql[i];
      final nextChar = i + 1 < sql.length ? sql[i + 1] : '';

      // 处理字符串
      if ((char == "'" || char == '"') && !inComment && !inBacktick) {
        if (!inString) {
          if (buffer.isNotEmpty) {
            tokens.add(_createToken(buffer.toString()));
            buffer.clear();
          }
          inString = true;
          stringChar = char;
          buffer.write(char);
        } else if (stringChar == char) {
          // 检查是否是转义
          if (buffer.toString().endsWith('\\')) {
            buffer.write(char);
          } else {
            buffer.write(char);
            tokens.add(
              SqlToken(type: TokenType.string, value: buffer.toString()),
            );
            buffer.clear();
            inString = false;
          }
        } else {
          buffer.write(char);
        }
        i++;
        continue;
      }

      if (inString) {
        buffer.write(char);
        i++;
        continue;
      }

      // 处理反引号标识符
      if (char == '`' && !inComment) {
        if (!inBacktick) {
          if (buffer.isNotEmpty) {
            tokens.add(_createToken(buffer.toString()));
            buffer.clear();
          }
          inBacktick = true;
          buffer.write(char);
        } else {
          buffer.write(char);
          tokens.add(
            SqlToken(type: TokenType.identifier, value: buffer.toString()),
          );
          buffer.clear();
          inBacktick = false;
        }
        i++;
        continue;
      }

      if (inBacktick) {
        buffer.write(char);
        i++;
        continue;
      }

      // 处理注释
      if (!inComment && char == '-' && nextChar == '-') {
        if (buffer.isNotEmpty) {
          tokens.add(_createToken(buffer.toString()));
          buffer.clear();
        }
        inComment = true;
        commentType = '--';
        buffer.write(char);
        i++;
        continue;
      }

      if (!inComment && char == '/' && nextChar == '*') {
        if (buffer.isNotEmpty) {
          tokens.add(_createToken(buffer.toString()));
          buffer.clear();
        }
        inComment = true;
        commentType = '/*';
        buffer.write(char);
        i++;
        continue;
      }

      if (inComment) {
        buffer.write(char);
        if (commentType == '--' && char == '\n') {
          tokens.add(
            SqlToken(type: TokenType.comment, value: buffer.toString().trim()),
          );
          buffer.clear();
          inComment = false;
        } else if (commentType == '/*' && char == '*' && nextChar == '/') {
          buffer.write(nextChar);
          tokens.add(
            SqlToken(type: TokenType.comment, value: buffer.toString()),
          );
          buffer.clear();
          inComment = false;
          i += 2;
          continue;
        }
        i++;
        continue;
      }

      // 处理空白字符
      if (char.trim().isEmpty) {
        if (buffer.isNotEmpty) {
          tokens.add(_createToken(buffer.toString()));
          buffer.clear();
        }
        i++;
        continue;
      }

      // 处理特殊字符
      if ('(),;'.contains(char)) {
        if (buffer.isNotEmpty) {
          tokens.add(_createToken(buffer.toString()));
          buffer.clear();
        }
        tokens.add(SqlToken(type: TokenType.punctuation, value: char));
        i++;
        continue;
      }

      buffer.write(char);
      i++;
    }

    // 处理剩余的 buffer
    if (buffer.isNotEmpty) {
      if (inString) {
        tokens.add(SqlToken(type: TokenType.string, value: buffer.toString()));
      } else if (inBacktick) {
        tokens.add(
          SqlToken(type: TokenType.identifier, value: buffer.toString()),
        );
      } else if (inComment) {
        tokens.add(
          SqlToken(type: TokenType.comment, value: buffer.toString().trim()),
        );
      } else {
        tokens.add(_createToken(buffer.toString()));
      }
    }

    return tokens;
  }

  /// 创建 token
  SqlToken _createToken(String value) {
    final upperValue = value.toUpperCase();

    if (_keywords.contains(upperValue)) {
      return SqlToken(
        type: TokenType.keyword,
        value: value,
        normalized: upperValue,
      );
    }
    if (_functions.contains(upperValue)) {
      return SqlToken(
        type: TokenType.function,
        value: value,
        normalized: upperValue,
      );
    }
    if (_operators.contains(value)) {
      return SqlToken(type: TokenType.operator, value: value);
    }
    if (int.tryParse(value) != null || double.tryParse(value) != null) {
      return SqlToken(type: TokenType.number, value: value);
    }

    return SqlToken(type: TokenType.identifier, value: value);
  }

  /// 应用格式化
  String _applyFormat(List<SqlToken> tokens, FormatterOptions options) {
    final result = StringBuffer();
    var indentLevel = 0;
    var afterSelect = false;
    var selectColumnCount = 0;

    String getIndent() {
      if (options.useTabs) {
        return '\t' * indentLevel;
      }
      return ' ' * (options.indentSize * indentLevel);
    }

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final prevToken = i > 0 ? tokens[i - 1] : null;
      final nextToken = i < tokens.length - 1 ? tokens[i + 1] : null;

      // 跳过注释（如果不保留）
      if (token.type == TokenType.comment && !options.preserveComments) {
        continue;
      }

      // 处理关键字大小写
      var value = token.value;
      if (token.type == TokenType.keyword && options.uppercaseKeywords) {
        value = token.normalized ?? value.toUpperCase();
      } else if (token.type == TokenType.function &&
          options.uppercaseKeywords) {
        value = token.normalized ?? value.toUpperCase();
      }

      // 主要关键字换行和缩进
      if (token.type == TokenType.keyword) {
        final keyword = (token.normalized ?? token.value.toUpperCase());

        // 需要在新行开始的关键字
        final newLineKeywords = {
          'SELECT',
          'FROM',
          'WHERE',
          'GROUP',
          'ORDER',
          'HAVING',
          'LIMIT',
          'INSERT',
          'UPDATE',
          'DELETE',
          'CREATE',
          'ALTER',
          'DROP',
          'LEFT',
          'RIGHT',
          'INNER',
          'OUTER',
          'FULL',
          'JOIN',
          'CROSS',
          'UNION',
          'INTERSECT',
          'EXCEPT',
          'VALUES',
          'SET',
          'ON',
        };

        if (newLineKeywords.contains(keyword)) {
          // 处理 AND 和 OR 在行内的特殊情况
          if ((keyword == 'AND' || keyword == 'OR') &&
              prevToken != null &&
              prevToken.type != TokenType.punctuation) {
            // 在行内的 AND/OR，不需要额外换行
          } else {
            if (result.isNotEmpty) {
              result.write('\n');
            }
            // JOIN 关键字缩进级别
            if ([
              'LEFT',
              'RIGHT',
              'INNER',
              'OUTER',
              'FULL',
              'JOIN',
              'CROSS',
            ].contains(keyword)) {
              // JOIN 与 FROM 同级
            } else if (keyword == 'SELECT') {
              afterSelect = true;
              selectColumnCount = 0;
            } else if (keyword == 'FROM') {
              afterSelect = false;
            }
            result.write(getIndent());
          }
        } else if (result.isNotEmpty && !result.toString().endsWith(' ')) {
          result.write(' ');
        }

        result.write(value);

        // SELECT 后面特殊处理
        if (keyword == 'SELECT') {
          result.write(' ');
        }
        continue;
      }

      // 处理标点符号
      if (token.type == TokenType.punctuation) {
        if (value == '(') {
          result.write(value);
          indentLevel++;
          if (nextToken != null && nextToken.type != TokenType.punctuation) {
            result.write('\n${getIndent()}');
          }
        } else if (value == ')') {
          indentLevel = indentLevel > 0 ? indentLevel - 1 : 0;
          if (prevToken != null && prevToken.value != '(') {
            result.write('\n${getIndent()}');
          }
          result.write(value);
        } else if (value == ',') {
          result.write(value);
          if (afterSelect) {
            selectColumnCount++;
            if (selectColumnCount % 3 == 0) {
              // 每3个列换行
              result.write('\n${getIndent()}');
            } else {
              result.write(' ');
            }
          } else {
            result.write('\n${getIndent()}');
          }
        } else if (value == ';') {
          result.write(value);
          result.write('\n');
          indentLevel = 0;
          afterSelect = false;
        }
        continue;
      }

      // 处理注释
      if (token.type == TokenType.comment) {
        if (result.isNotEmpty &&
            !result.toString().endsWith('\n') &&
            !result.toString().endsWith(' ')) {
          result.write(' ');
        }
        result.write(value);
        result.write('\n${getIndent()}');
        continue;
      }

      // 其他 token
      if (result.isNotEmpty &&
          !result.toString().endsWith(' ') &&
          !result.toString().endsWith('\n') &&
          !result.toString().endsWith('(')) {
        result.write(' ');
      }
      result.write(value);
    }

    return result.toString().trim();
  }

  /// 获取语法高亮的 SQL
  String getHighlightedSql(String sql, {SqlHighlightStyle? style}) {
    final tokens = _tokenize(sql);
    final highlightStyle = style ?? const SqlHighlightStyle();
    final result = StringBuffer();

    for (final token in tokens) {
      String color;
      switch (token.type) {
        case TokenType.keyword:
          color = highlightStyle.keywordColor;
          break;
        case TokenType.string:
          color = highlightStyle.stringColor;
          break;
        case TokenType.number:
          color = highlightStyle.numberColor;
          break;
        case TokenType.comment:
          color = highlightStyle.commentColor;
          break;
        case TokenType.function:
          color = highlightStyle.functionColor;
          break;
        case TokenType.operator:
          color = highlightStyle.operatorColor;
          break;
        case TokenType.identifier:
          color = highlightStyle.identifierColor;
          break;
        default:
          color = '#D4D4D4';
      }

      // 转义 HTML 特殊字符
      var value = token.value
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');

      result.write('<span style="color: $color">$value</span>');
    }

    return result.toString();
  }

  /// 验证 SQL 语法
  bool validate(String sql) {
    try {
      final tokens = _tokenize(sql);

      // 检查括号匹配
      var parenCount = 0;
      for (final token in tokens) {
        if (token.value == '(') parenCount++;
        if (token.value == ')') parenCount--;
        if (parenCount < 0) return false;
      }

      return parenCount == 0;
    } catch (e) {
      return false;
    }
  }

  /// 获取内置预设
  List<FormatterPreset> getBuiltInPresets() {
    return [
      FormatterPreset(
        id: 'default',
        name: '默认',
        description: '标准格式化，4空格缩进',
        options: const FormatterOptions(),
        isBuiltIn: true,
      ),
      FormatterPreset(
        id: 'compact',
        name: '紧凑',
        description: '紧凑模式，适合查看长查询',
        options: const FormatterOptions(
          indentSize: 2,
          compactMode: true,
          maxLineLength: 120,
        ),
        isBuiltIn: true,
      ),
      FormatterPreset(
        id: 'mysql',
        name: 'MySQL 风格',
        description: 'MySQL 官方推荐格式',
        options: const FormatterOptions(
          indentSize: 4,
          uppercaseKeywords: true,
          commaStyle: 'trailing',
          alignKeywords: true,
        ),
        isBuiltIn: true,
      ),
      FormatterPreset(
        id: 'readable',
        name: '可读性优先',
        description: '最大化可读性',
        options: const FormatterOptions(
          indentSize: 4,
          uppercaseKeywords: true,
          preserveComments: true,
          maxLineLength: 60,
          alignKeywords: true,
          breakBeforeBrackets: true,
        ),
        isBuiltIn: true,
      ),
    ];
  }

  /// 加载所有预设（内置 + 自定义）
  Future<List<FormatterPreset>> loadPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final presets = <FormatterPreset>[...getBuiltInPresets()];

    final customPresetsJson = prefs.getStringList(_presetsKey);
    if (customPresetsJson != null) {
      for (final json in customPresetsJson) {
        try {
          final preset = FormatterPreset.fromJson(
            Map<String, dynamic>.from(jsonDecode(json)),
          );
          presets.add(preset);
        } catch (e) {
          // 忽略无效的预设
        }
      }
    }

    return presets;
  }

  /// 保存自定义预设
  Future<void> savePreset(FormatterPreset preset) async {
    if (preset.isBuiltIn) return; // 不保存内置预设

    final prefs = await SharedPreferences.getInstance();
    final existingPresets = await loadPresets();

    // 查找并替换或添加
    final index = existingPresets.indexWhere(
      (p) => p.id == preset.id && !p.isBuiltIn,
    );
    final customPresets = existingPresets.where((p) => !p.isBuiltIn).toList();

    if (index >= 0) {
      customPresets[customPresets.indexWhere((p) => p.id == preset.id)] =
          preset;
    } else {
      customPresets.add(preset);
    }

    // 保存到 SharedPreferences
    final jsonList = customPresets.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_presetsKey, jsonList);
  }

  /// 删除自定义预设
  Future<void> deletePreset(String presetId) async {
    final prefs = await SharedPreferences.getInstance();
    final existingPresets = await loadPresets();

    final customPresets = existingPresets
        .where((p) => !p.isBuiltIn && p.id != presetId)
        .toList();

    final jsonList = customPresets.map((p) => jsonEncode(p.toJson())).toList();
    await prefs.setStringList(_presetsKey, jsonList);
  }

  /// 添加格式化历史记录
  Future<void> addHistory(
    String originalSql,
    String formattedSql,
    FormatterOptions options,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadHistory();

    final item = FormatHistory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      originalSql: originalSql,
      formattedSql: formattedSql,
      options: options,
      timestamp: DateTime.now(),
    );

    history.insert(0, item);

    // 限制历史记录数量
    while (history.length > _maxHistoryItems) {
      history.removeLast();
    }

    final jsonList = history.map((h) => jsonEncode(h.toJson())).toList();
    await prefs.setStringList(_historyKey, jsonList);
  }

  /// 加载格式化历史记录
  Future<List<FormatHistory>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey);

    if (historyJson == null) return [];

    final history = <FormatHistory>[];
    for (final json in historyJson) {
      try {
        final item = FormatHistory.fromJson(
          Map<String, dynamic>.from(jsonDecode(json)),
        );
        history.add(item);
      } catch (e) {
        // 忽略无效的历史记录
      }
    }

    return history;
  }

  /// 清除历史记录
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  /// 导出预设为 JSON
  String exportPresetToJson(FormatterPreset preset) {
    return jsonEncode(preset.toJson());
  }

  /// 从 JSON 导入预设
  FormatterPreset? importPresetFromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      return FormatterPreset.fromJson(data);
    } catch (e) {
      return null;
    }
  }
}

/// SQL Token 类型
enum TokenType {
  keyword,
  identifier,
  string,
  number,
  comment,
  operator,
  punctuation,
  function,
  unknown,
}

/// SQL Token
class SqlToken {
  final TokenType type;
  final String value;
  final String? normalized;

  SqlToken({required this.type, required this.value, this.normalized});
}
