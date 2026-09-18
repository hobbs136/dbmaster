import 'database_service.dart';
import 'sql_autocomplete_service.dart' show Suggestion, SuggestionType;
import 'adapters/mongodb_adapter.dart';
import '../utils/app_logger.dart';

/// Mongo shell 光标上下文（基于光标前文本分类，非整句解析）。
enum MongoShellCompletionContext {
  none, // 起始 / 未识别 → 方法 + $operator
  afterDbDot, // db.<partial> → 集合名
  afterCollectionDot, // db.<coll>.<partial> → 方法名
  afterMethodParen, // 在 method(…) 参数内（非过滤对象）→ $operator
  afterDollar, // 紧跟 '$' → $operator
  insideFilterKey, // 过滤对象内的键位 → 字段（US2）
}

/// MongoDB 自动补全服务（镜像 SqlAutocompleteService，仅 Mongo 使用）。
class MongoAutocompleteService {
  final DatabaseService _dbService;

  // 缓存（镜像 SqlAutocompleteService 的缓存模式 :50/:784）
  final Map<String, List<String>> _cachedCollections = {};
  final Map<String, Map<String, dynamic>> _cachedFields = {}; // US2: conn:db:coll → fields
  DateTime? _lastCacheUpdate;
  static const _cacheTtl = Duration(minutes: 5);

  MongoAutocompleteService(this._dbService);

  // ==================== Mongo shell 方法 ====================
  static const List<String> _methods = [
    'find',
    'findOne',
    'findMany',
    'aggregate',
    'count',
    'countDocuments',
    'estimatedDocumentCount',
    'distinct',
    'insertOne',
    'insertMany',
    'updateOne',
    'updateMany',
    'replaceOne',
    'deleteOne',
    'deleteMany',
    'findOneAndUpdate',
    'findOneAndReplace',
    'findOneAndDelete',
    'createIndex',
    'dropIndex',
    'getIndexes',
    'createCollection',
    'drop',
    'rename',
    'bulkWrite',
    'stats',
  ];

  // ==================== $-operator（查询 + 聚合阶段） ====================
  static const List<String> _dollarOperators = [
    // 比较
    '\$gte',
    '\$gt',
    '\$lte',
    '\$lt',
    '\$eq',
    '\$ne',
    '\$in',
    '\$nin',
    // 逻辑
    '\$and',
    '\$or',
    '\$not',
    '\$nor',
    // 元素 / 数组
    '\$exists',
    '\$type',
    '\$size',
    '\$all',
    '\$elemMatch',
    // 字符串
    '\$regex',
    '\$text',
    // 聚合阶段
    '\$match',
    '\$group',
    '\$sort',
    '\$limit',
    '\$skip',
    '\$project',
    '\$lookup',
    '\$unwind',
    '\$count',
    '\$bucket',
    '\$facet',
    '\$addFields',
    '\$set',
    '\$unset',
    '\$out',
    '\$merge',
  ];

  /// 获取 Mongo 方法建议
  List<Suggestion> getMethods(String prefix) {
    final lowerPrefix = prefix.toLowerCase();
    return _methods
        .where((m) => lowerPrefix.isEmpty || m.startsWith(lowerPrefix))
        .map(
          (m) => Suggestion(text: m, type: SuggestionType.method, priority: 90),
        )
        .toList();
  }

  /// 获取 $-operator 建议
  List<Suggestion> getDollarOperators(String prefix) {
    return _dollarOperators
        .where((op) => prefix.isEmpty || op.startsWith(prefix))
        .map(
          (op) =>
              Suggestion(text: op, type: SuggestionType.operator, priority: 80),
        )
        .toList();
  }

  /// 获取集合名（带缓存，走通用 DatabaseService.getTables）
  Future<List<Suggestion>> getCollectionNames(
    String prefix, {
    String? databaseName,
    String? connectionId,
  }) async {
    final cid = connectionId ?? _dbService.activeConnectionId;
    if (cid == null || !_dbService.hasConnection(cid)) return [];

    try {
      final cacheKey = _getCacheKey(databaseName, connectionId);
      if (_cachedCollections[cacheKey] == null || _isCacheExpired()) {
        final tables = await _dbService.getTables(connectionId: cid);
        _cachedCollections[cacheKey] = tables;
        _lastCacheUpdate = DateTime.now();
      }

      final tables = _cachedCollections[cacheKey]!;
      final lowerPrefix = prefix.toLowerCase();
      return tables
          .where(
            (t) =>
                lowerPrefix.isEmpty || t.toLowerCase().startsWith(lowerPrefix),
          )
          .map(
            (t) => Suggestion(
              text: t,
              type: SuggestionType.collection,
              detail: 'Collection',
              priority: 100,
            ),
          )
          .toList();
    } catch (e) {
      AppLogger.d('MongoAutocomplete', 'Error getting collection names: $e');
      return [];
    }
  }

  /// 字段补全（US2）：基于采样推断 `inferDocumentSchema`，带 per-collection 缓存 + 超时降级。
  /// 见 contracts/autocomplete-service.md §3 / research.md D3。
  Future<List<Suggestion>> getFieldNames(
    String prefix, {
    required String collection,
    String? databaseName,
    String? connectionId,
  }) async {
    if (collection.isEmpty) return [];
    final cid = connectionId ?? _dbService.activeConnectionId;
    if (cid == null || !_dbService.hasConnection(cid)) return [];

    final cacheKey = '${_getCacheKey(databaseName, connectionId)}:$collection';
    try {
      Map<String, dynamic> schema;
      if (_cachedFields[cacheKey] != null && !_isCacheExpired()) {
        schema = _cachedFields[cacheKey]!;
      } else {
        final adapter = _dbService.currentAdapter;
        if (adapter is! MongoDBAdapter) return [];
        // 采样推断 + 3s 超时降级（采不到则返回空 schema → 无字段建议）
        schema = await adapter
            .inferDocumentSchema(collection)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () => <String, dynamic>{},
            );
        _cachedFields[cacheKey] = schema;
        _lastCacheUpdate = DateTime.now();
      }
      return buildFieldSuggestions(schema, prefix);
    } catch (e) {
      AppLogger.d('MongoAutocomplete', 'Error getting field names: $e');
      return [];
    }
  }

  /// 由采样 schema 构造字段建议（纯函数，便于单测）。US2。
  /// schema 形如 {collectionName, totalSampled, fields:{name→{type,occurrence,...}}}。
  static List<Suggestion> buildFieldSuggestions(
    Map<String, dynamic> schema,
    String prefix,
  ) {
    final totalSampled = (schema['totalSampled'] as num?)?.toInt() ?? 0;
    final fields = schema['fields'];
    if (fields is! Map) return [];
    final lowerPrefix = prefix.toLowerCase();
    final suggestions = <Suggestion>[];
    fields.forEach((name, info) {
      final fieldName = name.toString();
      if (lowerPrefix.isEmpty ||
          fieldName.toLowerCase().startsWith(lowerPrefix)) {
        final infoMap = info is Map<String, dynamic>
            ? info
            : <String, dynamic>{};
        final type = (infoMap['type'] as String?) ?? 'unknown';
        final occurrence = (infoMap['occurrence'] as num?)?.toInt() ?? 0;
        final coverage = totalSampled > 0
            ? (occurrence * 100 ~/ totalSampled)
            : 0;
        suggestions.add(
          Suggestion(
            text: fieldName,
            type: SuggestionType.field,
            detail: 'sampled · $type · $coverage%',
            priority: 95,
          ),
        );
      }
    });
    return suggestions;
  }

  /// 主入口：按光标上下文分派建议
  Future<List<Suggestion>> getSuggestions(
    String input,
    int cursorPosition, {
    String? databaseName,
    String? connectionId,
  }) async {
    final suggestions = <Suggestion>[];
    final prefix = _extractPrefix(input, cursorPosition);
    final context = _classifyContext(input, cursorPosition);

    switch (context) {
      case MongoShellCompletionContext.afterDbDot:
        suggestions.addAll(
          await getCollectionNames(
            prefix,
            databaseName: databaseName,
            connectionId: connectionId,
          ),
        );
        suggestions.addAll(getMethods(prefix));
        break;
      case MongoShellCompletionContext.afterCollectionDot:
        suggestions.addAll(getMethods(prefix));
        break;
      case MongoShellCompletionContext.afterDollar:
      case MongoShellCompletionContext.afterMethodParen:
        suggestions.addAll(getDollarOperators(prefix));
        break;
      case MongoShellCompletionContext.insideFilterKey:
        // US1: 字段补全尚未实现，过滤键位暂不返回 $operator（避免误导）；US2 填充字段。
        suggestions.addAll(
          await getFieldNames(
            prefix,
            collection: _extractCollectionName(input, cursorPosition) ?? '',
            databaseName: databaseName,
            connectionId: connectionId,
          ),
        );
        break;
      case MongoShellCompletionContext.none:
        suggestions.addAll(getMethods(prefix));
        suggestions.addAll(getDollarOperators(prefix));
        break;
    }

    // 排序 + 去重（镜像 SqlAutocompleteService.getSuggestions 末尾处理）
    suggestions.sort((a, b) => b.priority.compareTo(a.priority));
    final seen = <String>{};
    return suggestions
        .where((s) => seen.add(s.text.toLowerCase()))
        .toList();
  }

  // ==================== 光标上下文分类 ====================

  /// 基于光标前文本分类；任何不确定都返回 [none]（安全默认：宁可不补也不补错）。
  MongoShellCompletionContext _classifyContext(
    String text,
    int cursorPosition,
  ) {
    if (cursorPosition < 0) cursorPosition = 0;
    if (cursorPosition > text.length) cursorPosition = text.length;
    final before = text.substring(0, cursorPosition);
    final trimmed = before.trimRight();
    if (trimmed.isEmpty) return MongoShellCompletionContext.none;

    // 1. 紧跟 '$' → $operator
    if (trimmed.endsWith('\$')) return MongoShellCompletionContext.afterDollar;

    // 2. 在未闭合的 '(' 内（method 参数区）
    final lastOpen = trimmed.lastIndexOf('(');
    final lastClose = trimmed.lastIndexOf(')');
    if (lastOpen > lastClose) {
      // 在过滤对象 { } 内？
      final lastBraceOpen = trimmed.lastIndexOf('{');
      final lastBraceClose = trimmed.lastIndexOf('}');
      if (lastBraceOpen > lastBraceClose) {
        return MongoShellCompletionContext.insideFilterKey;
      }
      return MongoShellCompletionContext.afterMethodParen;
    }

    // 3. db.<coll>.<partial> → 方法名
    if (RegExp(r'db\.[A-Za-z0-9_]+\.[A-Za-z0-9_]*$').hasMatch(trimmed)) {
      return MongoShellCompletionContext.afterCollectionDot;
    }

    // 4. db.<partial> → 集合名
    if (RegExp(r'db\.[A-Za-z0-9_]*$').hasMatch(trimmed)) {
      return MongoShellCompletionContext.afterDbDot;
    }

    return MongoShellCompletionContext.none;
  }

  /// 从光标前提取正在输入的 token 前缀（遇分隔符停止）
  String _extractPrefix(String text, int cursorPosition) {
    if (cursorPosition > text.length) cursorPosition = text.length;
    if (cursorPosition < 0) cursorPosition = 0;
    final before = text.substring(0, cursorPosition);
    int i = before.length - 1;
    while (i >= 0) {
      final ch = before[i];
      if (ch == ' ' ||
          ch == '\n' ||
          ch == '\t' ||
          ch == '(' ||
          ch == ')' ||
          ch == '{' ||
          ch == '}' ||
          ch == '[' ||
          ch == ']' ||
          ch == ',' ||
          ch == ':' ||
          ch == ';' ||
          ch == '.') {
        break;
      }
      i--;
    }
    return before.substring(i + 1);
  }

  /// 从 `db.<coll>.method(...)` 中提取集合名（US2 字段补全用）；解析失败返回 null。
  String? _extractCollectionName(String text, int cursorPosition) {
    if (cursorPosition > text.length) cursorPosition = text.length;
    final before = text.substring(0, cursorPosition);
    final match = RegExp(r'db\.([A-Za-z0-9_]+)\.').firstMatch(before);
    return match?.group(1);
  }

  // ==================== 缓存工具 ====================

  String _getCacheKey(String? databaseName, String? connectionId) {
    final connId = connectionId ?? _dbService.activeConnectionId ?? 'default';
    final dbName = databaseName ?? '';
    return '$connId:$dbName';
  }

  bool _isCacheExpired() {
    if (_lastCacheUpdate == null) return true;
    return DateTime.now().difference(_lastCacheUpdate!) > _cacheTtl;
  }

  /// 清除缓存（侧边栏刷新 / 执行后调用）
  void clearCache() {
    _cachedCollections.clear();
    _cachedFields.clear();
    _lastCacheUpdate = null;
  }
}
