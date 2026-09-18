import 'dart:developer' as developer;

import '../../models/query_optimizer/execution_plan.dart';
import 'explain_parser.dart';
import 'index_recommendation_engine.dart';
import 'performance_analyzer.dart';
import 'query_rewrite_engine.dart';

export '../../models/query_optimizer/execution_plan.dart';

/// Query Optimizer 服务入口
/// 整合所有优化组件，提供统一的分析接口
class QueryOptimizerService {
  /// 分析查询性能
  ///
  /// [rawExplainResults] 是数据库 EXPLAIN 返回的原始数据
  /// [originalQuery] 是原始 SQL 查询
  /// [databaseType] 是数据库类型（mysql, postgresql, sqlite等）
  /// [tableColumns] 可选：表名 → 列名列表。提供时启用 SELECT * 自动重写为真实列名
  static PerformanceReport analyzeQuery({
    required List<Map<String, dynamic>> rawExplainResults,
    required String originalQuery,
    required String databaseType,
    Map<String, List<String>>? tableColumns,
  }) {
    final startTime = DateTime.now();

    developer.log(
      'Analyzing query performance...',
      name: 'QueryOptimizerService',
    );

    try {
      // 1. 解析 EXPLAIN 结果
      final executionPlan = ExplainParser.parse(
        rawResults: rawExplainResults,
        databaseType: databaseType,
        originalQuery: originalQuery,
      );

      // 2. 识别性能瓶颈
      final bottlenecks = PerformanceAnalyzer.analyze(executionPlan);

      // 3. 生成索引推荐
      final indexRecommendations = IndexRecommendationEngine.recommendIndexes(
        plan: executionPlan,
        originalQuery: originalQuery,
      );

      // 4. 生成查询重写建议
      final queryRewrites = QueryRewriteEngine.suggestRewrites(
        originalQuery: originalQuery,
        plan: executionPlan,
        tableColumns: tableColumns,
      );

      // 5. 生成分析摘要
      final summary = PerformanceAnalyzer.generateSummary(
        executionPlan,
        bottlenecks,
      );

      final analysisDuration = DateTime.now().difference(startTime);

      developer.log(
        'Query analysis completed in ${analysisDuration.inMilliseconds}ms. '
        'Found ${bottlenecks.length} bottlenecks, '
        '${indexRecommendations.length} index recommendations.',
        name: 'QueryOptimizerService',
      );

      return PerformanceReport(
        executionPlan: executionPlan,
        bottlenecks: bottlenecks,
        indexRecommendations: indexRecommendations,
        queryRewrites: queryRewrites,
        summary: summary,
        analysisDuration: analysisDuration,
      );
    } catch (e, stackTrace) {
      developer.log(
        'Error analyzing query: $e',
        name: 'QueryOptimizerService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// 快速分析（用于 AI Tool 调用）
  /// 返回结构化 JSON 数据
  static Map<String, dynamic> analyzeQueryForAI({
    required List<Map<String, dynamic>> rawExplainResults,
    required String originalQuery,
    required String databaseType,
    Map<String, List<String>>? tableColumns,
  }) {
    final report = analyzeQuery(
      rawExplainResults: rawExplainResults,
      originalQuery: originalQuery,
      databaseType: databaseType,
      tableColumns: tableColumns,
    );

    return {
      'success': true,
      'execution_plan': report.executionPlan.toJson(),
      'bottlenecks': report.bottlenecks.map((b) => b.toJson()).toList(),
      'index_recommendations': report.indexRecommendations
          .map((r) => r.toJson())
          .toList(),
      'query_rewrites': report.queryRewrites.map((r) => r.toJson()).toList(),
      'summary': report.summary,
      'highest_severity': report.highestSeverity.name,
      'has_critical_issues': report.hasCriticalIssues,
      'total_estimated_improvement': report.totalEstimatedImprovement,
    };
  }

  /// 格式化分析报告为 AI 友好的文本
  static String formatReportForAI(PerformanceReport report) {
    final buffer = StringBuffer();

    buffer.writeln('## Query Performance Analysis');
    buffer.writeln();
    buffer.writeln('**Database**: ${report.executionPlan.databaseType}');
    buffer.writeln(
      '**Analysis Time**: ${report.analysisDuration.inMilliseconds}ms',
    );
    buffer.writeln();

    // 执行计划
    buffer.writeln('### Execution Plan');
    for (final step in report.executionPlan.steps) {
      buffer.write('- **Table**: ${step.table ?? "N/A"}');
      if (step.scanType != null) {
        buffer.write(' | **Scan**: ${step.scanType!.displayName}');
      }
      if (step.estimatedRows != null) {
        buffer.write(' | **Rows**: ${step.estimatedRows}');
      }
      buffer.writeln();
    }
    buffer.writeln();

    // 瓶颈
    if (report.bottlenecks.isNotEmpty) {
      buffer.writeln('### Performance Issues');
      for (final bottleneck in report.bottlenecks) {
        final emoji = switch (bottleneck.severity) {
          Severity.critical => '🚨',
          Severity.high => '🔴',
          Severity.medium => '🟡',
          Severity.low => '🟢',
          Severity.info => 'ℹ️',
        };
        buffer.writeln(
          '$emoji **[${bottleneck.severity.displayName}]** ${bottleneck.type.name}',
        );
        buffer.writeln('   ${bottleneck.description}');
        if (bottleneck.recommendation != null) {
          buffer.writeln('   💡 ${bottleneck.recommendation}');
        }
        buffer.writeln();
      }
    }

    // 索引推荐
    if (report.indexRecommendations.isNotEmpty) {
      buffer.writeln('### Index Recommendations');
      for (final rec in report.indexRecommendations) {
        buffer.writeln(
          '**${rec.indexName}** on `${rec.tableName}(${rec.columns.join(', ')})`',
        );
        buffer.writeln(rec.reason);
        if (rec.estimatedImprovement != null) {
          buffer.writeln(
            'Estimated improvement: ~${rec.estimatedImprovement!.toStringAsFixed(0)}%',
          );
        }
        buffer.writeln('```sql');
        buffer.writeln(rec.ddlStatement);
        buffer.writeln('```');
        buffer.writeln();
      }
    }

    // 查询重写
    if (report.queryRewrites.isNotEmpty) {
      buffer.writeln('### Query Rewrite Suggestions');
      for (final rewrite in report.queryRewrites) {
        buffer.writeln('**${rewrite.type.name}**');
        buffer.writeln(rewrite.reason);
        buffer.writeln('```sql');
        buffer.writeln(rewrite.rewrittenQuery);
        buffer.writeln('```');
        buffer.writeln();
      }
    }

    return buffer.toString();
  }
}
