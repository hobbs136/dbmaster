import '../models/database_models.dart';
import 'mongodb_shell_parser.dart';

/// Mongo 查询优化建议优先级（镜像 SqlOptimizerService 的 Priority）。
enum MongoOptimizationPriority { high, medium, low }

/// 单条优化建议。镜像 SqlOptimizationSuggestion 的结构，便于 AI 面板统一渲染。
class MongoOptimizationSuggestion {
  final String type;
  final String description;
  final String suggestion;
  final MongoOptimizationPriority priority;
  final String? beforeExample;
  final String? afterExample;

  MongoOptimizationSuggestion({
    required this.type,
    required this.description,
    required this.suggestion,
    required this.priority,
    this.beforeExample,
    this.afterExample,
  });
}

/// MongoDB 查询/聚合优化分析（纯函数，无副作用）。
///
/// 镜像 SqlOptimizerService 的公开形状，覆盖 research D5 列出的启发式规则：
/// 全表扫描、`$match` 未前置、`$skip` 先于 `$limit`、`$lookup` 开销、缺失投影、
/// 已弃用的 `count()`。
class MongoOptimizerService {
  List<MongoOptimizationSuggestion> analyze(
    String query, {
    List<DbIndex>? existingIndexes,
  }) {
    final suggestions = <MongoOptimizationSuggestion>[];
    final parsed = MongoShellQueryParser.parseQuery(query);

    if (parsed == null) {
      suggestions.add(
        MongoOptimizationSuggestion(
          type: '解析提示',
          description: '无法识别该 Mongo shell 语句',
          suggestion: '请使用 db.collection.find(...) 或 db.collection.aggregate([...]) 语法',
          priority: MongoOptimizationPriority.low,
        ),
      );
      return suggestions;
    }

    final isAggregate = parsed['isAggregate'] == true;
    if (isAggregate) {
      _analyzeAggregate(parsed, suggestions);
    } else {
      _analyzeFind(parsed, suggestions, existingIndexes);
    }

    return suggestions;
  }

  void _analyzeFind(
    Map<String, dynamic> parsed,
    List<MongoOptimizationSuggestion> suggestions,
    List<DbIndex>? existingIndexes,
  ) {
    final filter = parsed['filter'] as Map<String, dynamic>? ?? {};
    final projection = parsed['projection'];

    // 全表扫描：有过滤条件，但缺索引（或无法确认索引覆盖）
    if (filter.isNotEmpty) {
      final filterFields = filter.keys.where((k) => k != '_id').toList();
      final indexedFields = existingIndexes?.expand((i) => i.columns).toSet();
      final covered = indexedFields == null
          ? null
          : filterFields.any((f) => indexedFields.contains(f));
      if (covered == false) {
        suggestions.add(
          MongoOptimizationSuggestion(
            type: '索引缺失',
            description: '查询过滤字段 ${filterFields.join(", ")} 上未检测到索引，可能触发全集合扫描',
            suggestion: '为高频过滤字段创建索引：db.${parsed["collection"]}.createIndex({field: 1})',
            priority: MongoOptimizationPriority.high,
            afterExample:
                'db.${parsed["collection"]}.createIndex({${filterFields.first}: 1})',
          ),
        );
      }
    }

    // 缺失投影：find 不带 projection 会回传全部字段
    if (projection == null) {
      suggestions.add(
        MongoOptimizationSuggestion(
          type: '投影优化',
          description: 'find 未指定 projection，将回传完整文档（含不需要的字段）',
          suggestion: '通过第二个参数限定返回字段，减少网络与内存开销',
          priority: MongoOptimizationPriority.medium,
          beforeExample: 'db.users.find({active: true})',
          afterExample: 'db.users.find({active: true}, {name: 1, email: 1, _id: 0})',
        ),
      );
    }

    // 大 skip 翻页
    final skip = parsed['skip'];
    if (skip is int && skip > 1000) {
      suggestions.add(
        MongoOptimizationSuggestion(
          type: '分页优化',
          description: 'skip($skip) 在大偏移下性能差（Mongo 需扫描并丢弃前 $skip 条）',
          suggestion: '基于游标（_id / 排序键）做范围分页，而非 skip+limit',
          priority: MongoOptimizationPriority.medium,
          beforeExample: 'db.coll.find().sort({_id:1}).skip(50000).limit(20)',
          afterExample: 'db.coll.find({_id: {\$gt: lastId}}).sort({_id:1}).limit(20)',
        ),
      );
    }

    // 已弃用的 count()
    final method = parsed['method']?.toString();
    if (method == 'count') {
      suggestions.add(
        MongoOptimizationSuggestion(
          type: 'API 迁移',
          description: 'db.collection.count() 在新版驱动中已弃用',
          suggestion: '改用 countDocuments()（精确）或 estimatedDocumentCount()（估算，更快）',
          priority: MongoOptimizationPriority.low,
          beforeExample: 'db.users.count({active: true})',
          afterExample: 'db.users.countDocuments({active: true})',
        ),
      );
    }
  }

  void _analyzeAggregate(
    Map<String, dynamic> parsed,
    List<MongoOptimizationSuggestion> suggestions,
  ) {
    final pipeline = parsed['pipeline'] as List<dynamic>? ?? [];
    if (pipeline.isEmpty) return;

    final stageTypes = <String>[];
    for (final stage in pipeline) {
      if (stage is Map<String, dynamic>) {
        stageTypes.addAll(stage.keys);
      }
    }

    // $match 未前置
    final firstMatchIndex = stageTypes.indexOf('\$match');
    if (firstMatchIndex > 0) {
      suggestions.add(
        MongoOptimizationSuggestion(
          type: '管道顺序',
          description: '\$match 不在管道最前，之前存在 ${stageTypes.sublist(0, firstMatchIndex).join(", ")} 阶段，导致对全量文档计算后才过滤',
          suggestion: '将 \$match 尽量前移，使其能利用索引并尽早缩减文档数量',
          priority: MongoOptimizationPriority.high,
        ),
      );
    }

    // $skip 先于 $limit
    final skipIndex = stageTypes.indexOf('\$skip');
    final limitIndex = stageTypes.indexOf('\$limit');
    if (skipIndex != -1 && limitIndex != -1 && skipIndex < limitIndex) {
      suggestions.add(
        MongoOptimizationSuggestion(
          type: '管道顺序',
          description: '\$skip 出现在 \$limit 之前，会先跳过再截断，可能放大内存压力',
          suggestion: '若仅需分页，确保 sort → limit/skip 顺序合理；大数据集考虑游标分页',
          priority: MongoOptimizationPriority.medium,
        ),
      );
    }

    // $lookup 开销
    if (stageTypes.contains('\$lookup')) {
      suggestions.add(
        MongoOptimizationSuggestion(
          type: '连接开销',
          description: '管道包含 \$lookup（集合连接），每条文档都会触发一次子查询',
          suggestion: '确保 localField / foreignField 有索引；考虑预嵌入或反范式化高频访问数据',
          priority: MongoOptimizationPriority.medium,
        ),
      );
    }

    // 无 $match 的全表聚合
    if (!stageTypes.contains('\$match') && !stageTypes.contains('\$limit')) {
      suggestions.add(
        MongoOptimizationSuggestion(
          type: '过滤缺失',
          description: '聚合管道无 \$match 也无 \$limit，将对整个集合执行所有阶段',
          suggestion: '在管道开头加 \$match 限定范围，或在末尾加 \$limit 控制结果规模',
          priority: MongoOptimizationPriority.high,
        ),
      );
    }
  }

  /// 生成可读报告，格式与 SqlOptimizerService.generateOptimizationReport 对齐。
  String generateOptimizationReport(
    String query,
    List<MongoOptimizationSuggestion> suggestions,
  ) {
    if (suggestions.isEmpty) {
      return '✅ Mongo 查询看起来不错，没有发现明显的优化点！';
    }

    final buffer = StringBuffer();
    buffer.writeln('📊 Mongo 查询优化分析报告');
    buffer.writeln('=' * 50);
    buffer.writeln();
    buffer.writeln('原始查询:');
    buffer.writeln('```javascript');
    buffer.writeln(query);
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln('发现 ${suggestions.length} 条优化建议：');
    buffer.writeln();

    for (var i = 0; i < suggestions.length; i++) {
      final s = suggestions[i];
      buffer.writeln('### ${i + 1}. ${s.type} [${s.priority}优先级]');
      buffer.writeln();
      buffer.writeln('**问题描述**: ${s.description}');
      buffer.writeln();
      buffer.writeln('**优化建议**: ${s.suggestion}');

      if (s.beforeExample != null) {
        buffer.writeln();
        buffer.writeln('**优化前**:');
        buffer.writeln('```javascript');
        buffer.writeln(s.beforeExample);
        buffer.writeln('```');
      }
      if (s.afterExample != null) {
        buffer.writeln();
        buffer.writeln('**优化后**:');
        buffer.writeln('```javascript');
        buffer.writeln(s.afterExample);
        buffer.writeln('```');
      }
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }
}
