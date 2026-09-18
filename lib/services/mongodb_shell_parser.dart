/// MongoDB Shell 查询语法解析器
/// 负责解析 db.collection.find({}) 等 MongoDB Shell 语法
class MongoShellQueryParser {
  MongoShellQueryParser._();

  /// 解析查询字符串，返回结构化数据
  static Map<String, dynamic>? parseQuery(String query) {
    try {
      if (!query.trim().startsWith('{')) {
        return _parseSimpleQuery(query);
      }

      return _parseJson(query.trim());
    } catch (e) {
      return _parseSimpleQuery(query);
    }
  }

  static Map<String, dynamic>? _parseSimpleQuery(String query) {
    query = query.trim();

    // 统一解析 db.collection.method(...) 格式
    // 使用非贪婪匹配，避免链式调用时把方法名吞进 collection name
    final dbMatch = RegExp(
      r'^db\.([^.]+(?:\.[^.]+)*?)\.(\w+)\s*\(',
      caseSensitive: false,
    ).firstMatch(query);
    if (dbMatch != null) {
      final collectionName = dbMatch.group(1);
      final methodName = dbMatch.group(2)!.toLowerCase();
      final argsStart = dbMatch.end;
      final argsEnd = _findClosingParen(query, argsStart - 1);
      if (argsEnd == -1) return null;
      final argsStr = query.substring(argsStart, argsEnd).trim();

      switch (methodName) {
        case 'find':
          return _parseFindArgs(collectionName!, argsStr, query, argsEnd);
        case 'findone':
          return _parseFindOneArgs(collectionName!, argsStr);
        case 'countdocuments':
        case 'count':
        case 'estimateddocumentcount':
          return _parseCountArgs(collectionName!, argsStr, methodName);
        case 'aggregate':
          return _parseAggregateArgs(collectionName!, argsStr);
        case 'distinct':
          return _parseDistinctArgs(collectionName!, argsStr);
      }
    }

    // 格式: find(collection, filter)
    final findMatch = RegExp(
      "^find\\s*\\(\\s*['\"]?(\\w+)['\"]?\\s*(?:,\\s*(.+))?\\)",
      caseSensitive: false,
    ).firstMatch(query);
    if (findMatch != null) {
      final filterStr = findMatch.group(2);
      Map<String, dynamic>? filter;
      if (filterStr != null && filterStr.trim().isNotEmpty) {
        filter = _parseJson(filterStr.trim());
      }
      return {
        'collection': findMatch.group(1),
        'filter': filter ?? <String, dynamic>{},
        'limit': 100,
      };
    }

    // 格式: count(collection, filter?)
    final countMatch = RegExp(
      "^count\\s*\\(\\s*['\"]?(\\w+)['\"]?\\s*(?:,\\s*(.+))?\\)",
      caseSensitive: false,
    ).firstMatch(query);
    if (countMatch != null) {
      final filterStr = countMatch.group(2);
      Map<String, dynamic>? filter;
      if (filterStr != null && filterStr.trim().isNotEmpty) {
        filter = _parseJson(filterStr.trim());
      }
      return {
        'collection': countMatch.group(1),
        'filter': filter ?? <String, dynamic>{},
        'isCount': true,
      };
    }

    return null;
  }

  static int _findClosingParen(String str, int openParenIndex) {
    var depth = 0;
    var inString = false;
    var stringChar = '';
    for (var i = openParenIndex; i < str.length; i++) {
      final ch = str[i];
      if (inString) {
        if (ch == stringChar && (i == 0 || str[i - 1] != r'\')) {
          inString = false;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        inString = true;
        stringChar = ch;
        continue;
      }
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static Map<String, dynamic> _parseFindArgs(
    String collectionName,
    String argsStr,
    String fullQuery,
    int argsEnd,
  ) {
    final args = _splitArgs(argsStr);
    final filter = args.isNotEmpty && args[0].trim().isNotEmpty
        ? _parseJson(args[0].trim()) ?? <String, dynamic>{}
        : <String, dynamic>{};
    final projection = args.length > 1 ? _parseJson(args[1].trim()) : null;
    final chainPart = fullQuery.substring(argsEnd);

    final limitMatch = RegExp(
      r'\.limit\s*\(\s*(\d+)\s*\)',
      caseSensitive: false,
    ).firstMatch(chainPart);
    final limit = limitMatch != null
        ? int.tryParse(limitMatch.group(1)!) ?? 100
        : 100;

    // 提取 .sort({...})
    Map<String, dynamic>? sort;
    final sortArg = _extractChainArg(chainPart, 'sort');
    if (sortArg != null) {
      sort = _parseJson(sortArg) ?? <String, dynamic>{};
    }

    // 提取 .skip(n)
    final skipMatch = RegExp(
      r'\.skip\s*\(\s*(\d+)\s*\)',
      caseSensitive: false,
    ).firstMatch(chainPart);
    final skip = skipMatch != null ? int.tryParse(skipMatch.group(1)!) : null;

    return {
      'collection': collectionName,
      'filter': filter,
      'projection': projection,
      'limit': limit,
      'sort': sort,
      'skip': skip,
    };
  }

  /// 从链式调用部分提取某个方法的参数内容
  /// 例如 chainPart = '.sort({a:1}).limit(10)'，method = 'sort' → 返回 '{a:1}'
  static String? _extractChainArg(String chainPart, String methodName) {
    final methodPattern = RegExp(
      r'\.' + RegExp.escape(methodName) + r'\s*\(',
      caseSensitive: false,
    );
    final startMatch = methodPattern.firstMatch(chainPart);
    if (startMatch == null) return null;
    final openParenIndex = startMatch.end - 1;
    final closeParenIndex = _findClosingParen(chainPart, openParenIndex);
    if (closeParenIndex == -1) return null;
    return chainPart.substring(openParenIndex + 1, closeParenIndex).trim();
  }

  static Map<String, dynamic> _parseFindOneArgs(
    String collectionName,
    String argsStr,
  ) {
    final args = _splitArgs(argsStr);
    final filter = args.isNotEmpty && args[0].trim().isNotEmpty
        ? _parseJson(args[0].trim()) ?? <String, dynamic>{}
        : <String, dynamic>{};
    return {'collection': collectionName, 'filter': filter, 'limit': 1};
  }

  static Map<String, dynamic> _parseCountArgs(
    String collectionName,
    String argsStr,
    String methodName,
  ) {
    final args = _splitArgs(argsStr);
    final filter = args.isNotEmpty && args[0].trim().isNotEmpty
        ? _parseJson(args[0].trim()) ?? <String, dynamic>{}
        : <String, dynamic>{};
    return {
      'collection': collectionName,
      'filter': filter,
      'isCount': true,
      'method': methodName,
    };
  }

  static Map<String, dynamic> _parseAggregateArgs(
    String collectionName,
    String argsStr,
  ) {
    final pipeline = _parseJsonArray(argsStr.trim()) ?? [];
    return {
      'collection': collectionName,
      'pipeline': pipeline,
      'isAggregate': true,
    };
  }

  static Map<String, dynamic> _parseDistinctArgs(
    String collectionName,
    String argsStr,
  ) {
    final args = _splitArgs(argsStr);
    final field = args.isNotEmpty
        ? args[0].trim().replaceAll(RegExp('^[\'"]|[\'"]\$'), '')
        : '';
    final filter = args.length > 1
        ? _parseJson(args[1].trim()) ?? <String, dynamic>{}
        : <String, dynamic>{};
    return {
      'collection': collectionName,
      'field': field,
      'filter': filter,
      'isDistinct': true,
    };
  }

  static List<String> _splitArgs(String argsStr) {
    final args = <String>[];
    var depth = 0;
    var inString = false;
    var stringChar = '';
    var current = '';
    for (var i = 0; i < argsStr.length; i++) {
      final ch = argsStr[i];
      if (inString) {
        current += ch;
        if (ch == stringChar && (i == 0 || argsStr[i - 1] != r'\')) {
          inString = false;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        current += ch;
        inString = true;
        stringChar = ch;
        continue;
      }
      if (ch == '(' || ch == '[' || ch == '{') {
        depth++;
        current += ch;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        depth--;
        current += ch;
      } else if (ch == ',' && depth == 0) {
        args.add(current.trim());
        current = '';
      } else {
        current += ch;
      }
    }
    if (current.trim().isNotEmpty) {
      args.add(current.trim());
    }
    return args;
  }

  static List<Map<String, dynamic>>? _parseJsonArray(String jsonStr) {
    jsonStr = jsonStr.trim();
    if (!jsonStr.startsWith('[') || !jsonStr.endsWith(']')) {
      final single = _parseJson(jsonStr.trim());
      if (single != null) return [single];
      return null;
    }
    final inner = jsonStr.substring(1, jsonStr.length - 1).trim();
    if (inner.isEmpty) return [];
    final items = <Map<String, dynamic>>[];
    var depth = 0;
    var inString = false;
    var stringChar = '';
    var current = '';
    for (var i = 0; i < inner.length; i++) {
      final ch = inner[i];
      if (inString) {
        current += ch;
        if (ch == stringChar && (i == 0 || inner[i - 1] != r'\')) {
          inString = false;
        }
        continue;
      }
      if (ch == '"' || ch == "'") {
        current += ch;
        inString = true;
        stringChar = ch;
        continue;
      }
      if (ch == '{' || ch == '[' || ch == '(') {
        depth++;
        current += ch;
      } else if (ch == '}' || ch == ']' || ch == ')') {
        depth--;
        current += ch;
      } else if (ch == ',' && depth == 0) {
        final parsed = _parseJson(current.trim());
        if (parsed != null) items.add(parsed);
        current = '';
      } else {
        current += ch;
      }
    }
    if (current.trim().isNotEmpty) {
      final parsed = _parseJson(current.trim());
      if (parsed != null) items.add(parsed);
    }
    return items;
  }

  static Map<String, dynamic>? _parseJson(String json) {
    try {
      json = json.trim();
      if (json.startsWith('{') && json.endsWith('}')) {
        json = json.substring(1, json.length - 1);
      }

      final result = <String, dynamic>{};
      var i = 0;
      var key = '';

      while (i < json.length) {
        while (i < json.length && ' \t\n\r'.contains(json[i])) {
          i++;
        }
        if (i >= json.length) break;

        if (json[i] == '"') {
          i++;
          final keyEnd = json.indexOf('"', i);
          if (keyEnd == -1) break;
          key = json.substring(i, keyEnd);
          i = keyEnd + 1;
        } else {
          final keyStart = i;
          while (i < json.length && json[i] != ':') {
            i++;
          }
          key = json.substring(keyStart, i).trim();
          i++;
        }

        while (i < json.length &&
            (json[i] == ':' || ' \t\n\r'.contains(json[i]))) {
          i++;
        }
        if (i >= json.length) break;

        final valueResult = _parseJsonValue(json, i);
        if (valueResult.$1 != null) {
          result[key] = valueResult.$1;
          i = valueResult.$2;
        } else {
          break;
        }

        while (i < json.length && ' \t\n\r,'.contains(json[i])) {
          i++;
        }
      }

      return result;
    } catch (e) {
      return null;
    }
  }

  static (dynamic, int) _parseJsonValue(String json, int start) {
    var i = start;
    while (i < json.length && ' \t\n\r'.contains(json[i])) {
      i++;
    }
    if (i >= json.length) return (null, i);

    final char = json[i];

    if (char == '"') {
      i++;
      final end = json.indexOf('"', i);
      if (end == -1) return (json.substring(i), json.length);
      final value = json.substring(i, end);
      return (value, end + 1);
    }

    if (char == '{') {
      var depth = 1;
      var j = i + 1;
      while (j < json.length && depth > 0) {
        if (json[j] == '{') depth++;
        if (json[j] == '}') depth--;
        j++;
      }
      final inner = json.substring(i + 1, j - 1);
      final parsed = _parseJson(inner);
      return (parsed ?? <String, dynamic>{}, j);
    }

    if (char == '[') {
      final items = <dynamic>[];
      var depth = 1;
      final startInner = i + 1;
      i = startInner;

      while (i < json.length && depth > 0) {
        if (json[i] == '[') depth++;
        if (json[i] == ']') depth--;
        i++;
      }

      final arrContent = json.substring(startInner, i - 1);
      var j = 0;
      while (j < arrContent.length) {
        while (j < arrContent.length && ' \t\n\r,'.contains(arrContent[j])) {
          j++;
        }
        if (j >= arrContent.length) break;
        final item = _parseJsonValue(arrContent, j);
        if (item.$1 != null) {
          items.add(item.$1);
          j = item.$2;
        } else {
          break;
        }
        while (j < arrContent.length && ' \t\n\r,'.contains(arrContent[j])) {
          j++;
        }
      }

      return (items, i);
    }

    if (char == 't' && json.substring(i).startsWith('true')) {
      return (true, i + 4);
    }
    if (char == 'f' && json.substring(i).startsWith('false')) {
      return (false, i + 5);
    }
    if (char == 'n' && json.substring(i).startsWith('null')) {
      return (null, i + 4);
    }

    final sub = json.substring(i);
    final numEnd = RegExp(r'[^0-9.eE+-]').firstMatch(sub);
    final endIdx = numEnd != null ? numEnd.start : sub.length;
    final numStr = sub.substring(0, endIdx).trim();

    if (numStr.contains('.') || numStr.contains('e') || numStr.contains('E')) {
      return (double.tryParse(numStr) ?? 0.0, i + endIdx);
    }
    return (int.tryParse(numStr) ?? 0, i + endIdx);
  }
}
