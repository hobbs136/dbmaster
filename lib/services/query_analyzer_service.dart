import 'dart:developer' as developer;

class ExecutionPlanStep {
  final int id;
  final String selectType;
  final String table;
  final String? partitions;
  final String type;
  final String? possibleKeys;
  final String? key;
  final String? keyLen;
  final String? ref;
  final String rows;
  final String? filtered;
  final String extra;

  ExecutionPlanStep({
    required this.id,
    required this.selectType,
    required this.table,
    this.partitions,
    required this.type,
    this.possibleKeys,
    this.key,
    this.keyLen,
    this.ref,
    required this.rows,
    this.filtered,
    required this.extra,
  });

  factory ExecutionPlanStep.fromMap(Map<String, dynamic> map) {
    return ExecutionPlanStep(
      id: map['id'] as int? ?? 0,
      selectType: map['select_type']?.toString() ?? '',
      table: map['table']?.toString() ?? '',
      partitions: map['partitions']?.toString(),
      type: map['type']?.toString() ?? '',
      possibleKeys: map['possible_keys']?.toString(),
      key: map['key']?.toString(),
      keyLen: map['key_len']?.toString(),
      ref: map['ref']?.toString(),
      rows: map['rows']?.toString() ?? '0',
      filtered: map['filtered']?.toString(),
      extra: map['Extra']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'select_type': selectType,
    'table': table,
    'partitions': partitions,
    'type': type,
    'possible_keys': possibleKeys,
    'key': key,
    'key_len': keyLen,
    'ref': ref,
    'rows': rows,
    'filtered': filtered,
    'Extra': extra,
  };
}

class QueryAnalysisResult {
  final List<ExecutionPlanStep> steps;
  final List<String> warnings;
  final List<String> suggestions;
  final double? estimatedRows;
  final bool usesIndex;
  final bool usesFullTableScan;

  QueryAnalysisResult({
    required this.steps,
    required this.warnings,
    required this.suggestions,
    this.estimatedRows,
    required this.usesIndex,
    required this.usesFullTableScan,
  });

  Map<String, dynamic> toJson() => {
    'steps': steps.map((s) => s.toJson()).toList(),
    'warnings': warnings,
    'suggestions': suggestions,
    'estimatedRows': estimatedRows,
    'usesIndex': usesIndex,
    'usesFullTableScan': usesFullTableScan,
  };
}

class QueryAnalyzerService {
  static final QueryAnalyzerService _instance =
      QueryAnalyzerService._internal();
  factory QueryAnalyzerService() => _instance;
  QueryAnalyzerService._internal();

  QueryAnalysisResult analyzeExecutionPlan(
    List<Map<String, dynamic>> planData,
  ) {
    developer.log('🔍 开始执行计划分析', name: 'QueryAnalyzerService');

    final steps = planData
        .map((data) => ExecutionPlanStep.fromMap(data))
        .toList();
    final warnings = <String>[];
    final suggestions = <String>[];
    var totalRows = 0.0;
    var hasIndex = false;
    var hasFullScan = false;

    for (final step in steps) {
      totalRows += double.tryParse(step.rows) ?? 0;

      if (step.type == 'ALL') {
        hasFullScan = true;
        warnings.add('表 ${step.table} 使用了全表扫描 (type=ALL)');
        suggestions.add('考虑为表 ${step.table} 添加适当的索引');
      }

      if (step.key != null && step.key!.isNotEmpty) {
        hasIndex = true;
      }

      if (step.extra.contains('Using filesort')) {
        warnings.add('表 ${step.table} 需要额外的排序操作 (Using filesort)');
        suggestions.add('考虑为 ORDER BY 字段添加索引');
      }

      if (step.extra.contains('Using temporary')) {
        warnings.add('表 ${step.table} 使用了临时表 (Using temporary)');
        suggestions.add('考虑优化查询以避免使用临时表');
      }

      if (step.extra.contains('Using join buffer')) {
        warnings.add('表 ${step.table} 使用了连接缓冲区 (Using join buffer)');
        suggestions.add('考虑为连接字段添加索引');
      }

      if (step.type == 'index') {
        warnings.add('表 ${step.table} 执行了全索引扫描 (type=index)');
        suggestions.add('全索引扫描可能比全表扫描更慢，考虑优化查询');
      }

      if (step.possibleKeys != null &&
          step.possibleKeys!.isNotEmpty &&
          step.key == null) {
        warnings.add('表 ${step.table} 有可用索引但未使用');
        suggestions.add('检查索引是否适合当前查询条件');
      }
    }

    if (totalRows > 10000) {
      warnings.add('查询可能返回大量数据 (估计 $totalRows 行)');
      suggestions.add('考虑添加 LIMIT 或更严格的 WHERE 条件');
    }

    developer.log('✅ 执行计划分析完成', name: 'QueryAnalyzerService');

    return QueryAnalysisResult(
      steps: steps,
      warnings: warnings,
      suggestions: suggestions,
      estimatedRows: totalRows,
      usesIndex: hasIndex,
      usesFullTableScan: hasFullScan,
    );
  }

  String generateAnalysisReport(QueryAnalysisResult result) {
    final buffer = StringBuffer();

    buffer.writeln('📊 执行计划分析报告');
    buffer.writeln('=' * 60);
    buffer.writeln();

    buffer.writeln('### 基本信息');
    buffer.writeln('- 是否使用索引: ${result.usesIndex ? "✅ 是" : "❌ 否"}');
    buffer.writeln('- 是否全表扫描: ${result.usesFullTableScan ? "⚠️ 是" : "✅ 否"}');
    if (result.estimatedRows != null) {
      buffer.writeln('- 预估扫描行数: ${result.estimatedRows!.toInt()}');
    }
    buffer.writeln();

    if (result.steps.isNotEmpty) {
      buffer.writeln('### 执行步骤详情');
      buffer.writeln();

      for (var i = 0; i < result.steps.length; i++) {
        final step = result.steps[i];
        buffer.writeln('#### 步骤 ${i + 1}');
        buffer.writeln('- **表名**: ${step.table}');
        buffer.writeln('- **查询类型**: ${step.selectType}');
        buffer.writeln('- **访问类型**: ${step.type}');

        if (step.possibleKeys != null && step.possibleKeys!.isNotEmpty) {
          buffer.writeln('- **可能使用的索引**: ${step.possibleKeys}');
        }

        if (step.key != null && step.key!.isNotEmpty) {
          buffer.writeln('- **实际使用的索引**: ${step.key}');
          buffer.writeln('- **索引长度**: ${step.keyLen}');
        }

        buffer.writeln('- **扫描行数**: ${step.rows}');

        if (step.extra.isNotEmpty) {
          buffer.writeln('- **额外信息**: ${step.extra}');
        }

        buffer.writeln();
      }
    }

    if (result.warnings.isNotEmpty) {
      buffer.writeln('### ⚠️ 警告 (${result.warnings.length})');
      buffer.writeln();
      for (final warning in result.warnings) {
        buffer.writeln('- $warning');
      }
      buffer.writeln();
    }

    if (result.suggestions.isNotEmpty) {
      buffer.writeln('### 💡 优化建议 (${result.suggestions.length})');
      buffer.writeln();
      for (final suggestion in result.suggestions) {
        buffer.writeln('- $suggestion');
      }
      buffer.writeln();
    }

    if (result.warnings.isEmpty && result.suggestions.isEmpty) {
      buffer.writeln('✅ 查询执行计划看起来不错！');
    }

    return buffer.toString();
  }

  String explainAccessType(String type) {
    switch (type) {
      case 'system':
        return '表只有一行（系统表），这是最快的连接类型';
      case 'const':
        return '表最多有一个匹配行，在查询开始时读取，非常快';
      case 'eq_ref':
        return '对于每个来自前面表的行组合，从此表中读取一行';
      case 'ref':
        return '对于每个来自前面表的行组合，从此表中读取所有匹配的行';
      case 'fulltext':
        return '使用 FULLTEXT 索引进行连接';
      case 'ref_or_null':
        return '类似于 ref，但还会搜索 NULL 值';
      case 'index_merge':
        return '使用索引合并优化';
      case 'unique_subquery':
        return '替换 IN 子查询，效率更高';
      case 'index_subquery':
        return '类似于 unique_subquery，但返回非唯一值';
      case 'range':
        return '只检索给定范围内的行，使用索引选择行';
      case 'index':
        return '全索引扫描，比 ALL 稍快';
      case 'ALL':
        return '全表扫描，最慢的连接类型，需要优化';
      default:
        return '未知类型: $type';
    }
  }
}
