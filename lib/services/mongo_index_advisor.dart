import '../models/database_models.dart';
import 'mongodb_shell_parser.dart';

/// 索引建议的用途分类（ESR 规则）。
enum IndexRecommendationReason { equality, sort, range, compound }

/// 单条索引建议。镜像 IndexOptimizerService 的建议结构。
class IndexRecommendation {
  /// 建议的索引键（有序，ESR：等值 → 排序 → 范围）。
  final Map<String, dynamic> key;

  /// 该建议命中的原因。
  final IndexRecommendationReason reason;

  /// 与既有索引重复（既有索引已覆盖该键集前缀）时为 true。
  final bool duplicateOfExisting;

  final String explanation;

  IndexRecommendation({
    required this.key,
    required this.reason,
    required this.duplicateOfExisting,
    required this.explanation,
  });
}

/// MongoDB 索引顾问（纯函数，无副作用）。
///
/// 从 find 过滤条件 / 聚合 \$match / \$sort 中抽取等值、排序、范围字段，
/// 按 ESR 规则（Equality → Sort → Range）合成复合索引建议，
/// 并与既有索引去重（research D7）。
class MongoIndexAdvisorService {
  /// 范围操作符——其字段应归入 ESR 的 R（Range）段。
  static const _rangeOperators = {
    '\$gt',
    '\$gte',
    '\$lt',
    '\$lte',
    '\$in',
    '\$nin',
    '\$ne',
    '\$regex',
  };

  List<IndexRecommendation> analyzeForIndex(
    String query, {
    required List<DbIndex> existingIndexes,
    String? collection,
  }) {
    final parsed = MongoShellQueryParser.parseQuery(query);
    if (parsed == null) {
      return [
        IndexRecommendation(
          key: {},
          reason: IndexRecommendationReason.equality,
          duplicateOfExisting: false,
          explanation: '无法解析该 Mongo shell 语句，跳过索引建议。',
        ),
      ];
    }

    final equalityFields = <String>{};
    final rangeFields = <String>{};
    final sortFields = <String, int>{};

    final isAggregate = parsed['isAggregate'] == true;
    if (isAggregate) {
      _extractFromAggregate(parsed, equalityFields, rangeFields, sortFields);
    } else {
      _extractFromFind(parsed, equalityFields, rangeFields, sortFields);
    }

    // 合成 ESR 复合索引键
    final esrKey = <String, dynamic>{};
    for (final f in _sorted(equalityFields)) {
      esrKey[f] = 1;
    }
    sortFields.forEach((f, dir) => esrKey[f] = dir);
    for (final f in _sorted(rangeFields)) {
      if (!esrKey.containsKey(f)) esrKey[f] = 1;
    }

    if (esrKey.isEmpty) {
      return [
        IndexRecommendation(
          key: {},
          reason: IndexRecommendationReason.equality,
          duplicateOfExisting: false,
          explanation: '查询无可索引字段（无过滤/排序条件），无需额外索引。',
        ),
      ];
    }

    final duplicate = _isCoveredByExisting(esrKey, existingIndexes);
    final reason = equalityFields.isNotEmpty
        ? IndexRecommendationReason.equality
        : (sortFields.isNotEmpty
              ? IndexRecommendationReason.sort
              : IndexRecommendationReason.range);

    final collName = collection ?? parsed['collection']?.toString() ?? 'collection';
    final buildCmd = esrKey.length == 1
        ? 'db.$collName.createIndex(${_keyToString(esrKey)})'
        : 'db.$collName.createIndex(${_keyToString(esrKey)})';

    return [
      IndexRecommendation(
        key: esrKey,
        reason: reason,
        duplicateOfExisting: duplicate,
        explanation: duplicate
            ? '已有索引覆盖该键集，无需重复创建。'
            : '建议创建索引：$buildCmd',
      ),
    ];
  }

  void _extractFromFind(
    Map<String, dynamic> parsed,
    Set<String> equality,
    Set<String> range,
    Map<String, int> sort,
  ) {
    final filter = parsed['filter'] as Map<String, dynamic>? ?? {};
    _classifyFilterFields(filter, equality, range);

    final parsedSort = parsed['sort'] as Map<String, dynamic>?;
    if (parsedSort != null) {
      parsedSort.forEach((field, dir) {
        sort[field] = (dir == -1 || dir == '-1') ? -1 : 1;
      });
    }
  }

  void _extractFromAggregate(
    Map<String, dynamic> parsed,
    Set<String> equality,
    Set<String> range,
    Map<String, int> sort,
  ) {
    final pipeline = parsed['pipeline'] as List<dynamic>? ?? [];
    for (final stage in pipeline) {
      if (stage is! Map<String, dynamic>) continue;
      if (stage.containsKey('\$match')) {
        final match = stage['\$match'];
        if (match is Map<String, dynamic>) {
          _classifyFilterFields(match, equality, range);
        }
      } else if (stage.containsKey('\$sort')) {
        final sortSpec = stage['\$sort'];
        if (sortSpec is Map<String, dynamic>) {
          sortSpec.forEach((field, dir) {
            sort[field] = (dir == -1 || dir == '-1') ? -1 : 1;
          });
        }
      }
    }
  }

  /// 将过滤条件中的字段分类为等值（E）或范围（R）。
  void _classifyFilterFields(
    Map<String, dynamic> filter,
    Set<String> equality,
    Set<String> range,
  ) {
    for (final entry in filter.entries) {
      final field = entry.key;
      if (field.startsWith('\$')) continue; // 逻辑操作符层级，跳过
      final value = entry.value;
      if (value is Map<String, dynamic> &&
          value.keys.any((k) => k.startsWith('\$'))) {
        // 含操作符的对象 → 判断是否范围操作符
        if (value.keys.any((k) => _rangeOperators.contains(k))) {
          range.add(field);
        } else {
          // 纯等值类操作符（$eq 等）仍按等值
          equality.add(field);
        }
      } else {
        equality.add(field);
      }
    }
  }

  /// 判断建议键集是否已被既有索引覆盖（既有键集是建议键集的前缀，或反之）。
  bool _isCoveredByExisting(
    Map<String, dynamic> proposedKey,
    List<DbIndex> existing,
  ) {
    final proposedFields = proposedKey.keys.toList();
    for (final idx in existing) {
      final idxFields = idx.columns;
      // 完全相同，或既有索引是建议的前缀（既有索引足以服务该查询）
      if (_listStartsWith(idxFields, proposedFields) ||
          _listStartsWith(proposedFields, idxFields)) {
        return true;
      }
    }
    return false;
  }

  bool _listStartsWith(List<String> list, List<String> prefix) {
    if (prefix.length > list.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (list[i] != prefix[i]) return false;
    }
    return true;
  }

  List<String> _sorted(Set<String> fields) =>
      fields.toList()..sort();

  String _keyToString(Map<String, dynamic> key) {
    final entries = key.entries.map((e) => '${e.key}: ${e.value}').join(', ');
    return '{ $entries }';
  }

  /// 生成可读建议报告。
  String generateReport(String query, List<IndexRecommendation> recommendations) {
    final buffer = StringBuffer();
    buffer.writeln('📇 Mongo 索引建议报告');
    buffer.writeln('=' * 50);
    buffer.writeln();
    buffer.writeln('原始查询:');
    buffer.writeln('```javascript');
    buffer.writeln(query);
    buffer.writeln('```');
    buffer.writeln();

    final actionable = recommendations.where((r) => !r.duplicateOfExisting).toList();
    final duplicates = recommendations.where((r) => r.duplicateOfExisting).toList();

    if (actionable.isEmpty) {
      buffer.writeln('✅ 当前查询已被既有索引覆盖，无需新增索引。');
    } else {
      buffer.writeln('建议新增 ${actionable.length} 个索引：');
      buffer.writeln();
      for (var i = 0; i < actionable.length; i++) {
        final r = actionable[i];
        buffer.writeln('### ${i + 1}. ${_reasonLabel(r.reason)}');
        buffer.writeln(r.explanation);
        buffer.writeln();
      }
    }

    if (duplicates.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('ℹ️ ${duplicates.length} 条建议与既有索引重复，已跳过。');
    }

    return buffer.toString().trimRight();
  }

  String _reasonLabel(IndexRecommendationReason reason) {
    switch (reason) {
      case IndexRecommendationReason.equality:
        return '等值查询索引（E）';
      case IndexRecommendationReason.sort:
        return '排序索引（S）';
      case IndexRecommendationReason.range:
        return '范围查询索引（R）';
      case IndexRecommendationReason.compound:
        return '复合索引（ESR）';
    }
  }
}
