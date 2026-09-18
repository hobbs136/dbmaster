import '../../models/query_optimizer/execution_plan.dart';

/// 性能分析器
/// 基于 EXPLAIN 结果识别性能瓶颈
class PerformanceAnalyzer {
  /// 分析执行计划，识别所有性能瓶颈
  static List<Bottleneck> analyze(ExecutionPlan plan) {
    final bottlenecks = <Bottleneck>[];

    for (final step in plan.steps) {
      // 1. 全表扫描检测
      if (step.scanType?.isInefficient ?? false) {
        final rows = step.estimatedRows ?? 0;
        final severity = rows > 10000
            ? Severity.high
            : rows > 1000
            ? Severity.medium
            : Severity.low;

        bottlenecks.add(
          Bottleneck(
            type: BottleneckType.fullTableScan,
            description:
                'Table ${step.table} is using a full table scan (${step.scanType?.displayName})',
            affectedTable: step.table,
            affectedRows: rows,
            recommendation: rows > 1000
                ? 'Consider adding an index on frequently queried columns'
                : 'Small table, full scan may be acceptable',
            severity: severity,
          ),
        );
      }

      // 2. 大表扫描检测
      if ((step.estimatedRows ?? 0) > 10000 &&
          !(step.scanType?.isEfficient ?? false)) {
        bottlenecks.add(
          Bottleneck(
            type: BottleneckType.largeTableScan,
            description:
                'Large table scan on ${step.table} with ${step.estimatedRows} estimated rows',
            affectedTable: step.table,
            affectedRows: step.estimatedRows,
            recommendation:
                'Add appropriate indexes or optimize query conditions',
            severity: Severity.high,
          ),
        );
      }

      // 3. 缺少索引检测
      if (step.possibleKeys == null &&
          step.key == null &&
          step.table != null &&
          step.table != 'NULL') {
        bottlenecks.add(
          Bottleneck(
            type: BottleneckType.missingIndex,
            description:
                'No index is being used for table ${step.table}. Possible keys: none',
            affectedTable: step.table,
            recommendation:
                'Add an index on columns used in WHERE, JOIN, or ORDER BY clauses',
            severity: Severity.medium,
          ),
        );
      }

      // 4. 文件排序检测
      if (step.extra?.contains('Using filesort') ?? false) {
        bottlenecks.add(
          Bottleneck(
            type: BottleneckType.fileSort,
            description: 'MySQL is using filesort for table ${step.table}',
            affectedTable: step.table,
            recommendation:
                'Add an index on ORDER BY columns or reduce result set size',
            severity: Severity.medium,
          ),
        );
      }

      // 5. 临时表检测
      if (step.extra?.contains('Using temporary') ?? false) {
        bottlenecks.add(
          Bottleneck(
            type: BottleneckType.temporaryTable,
            description:
                'Query requires a temporary table for table ${step.table}',
            affectedTable: step.table,
            recommendation:
                'Optimize GROUP BY or ORDER BY to avoid temporary tables',
            severity: Severity.medium,
          ),
        );
      }
    }

    // 6. SELECT * 检测（从原始查询中）
    if (_hasSelectStar(plan.originalQuery)) {
      bottlenecks.add(
        Bottleneck(
          type: BottleneckType.selectStar,
          description:
              'Query uses SELECT * which retrieves all columns unnecessarily',
          recommendation:
              'Specify only the columns you need to reduce I/O and memory usage',
          severity: Severity.low,
        ),
      );
    }

    // 7. OFFSET 分页检测
    if (_hasOffsetPagination(plan.originalQuery)) {
      bottlenecks.add(
        Bottleneck(
          type: BottleneckType.offsetPagination,
          description:
              'Query uses OFFSET for pagination which becomes slower as offset increases',
          recommendation:
              'Consider using keyset pagination (cursor-based) for large offsets',
          severity: Severity.low,
        ),
      );
    }

    return bottlenecks;
  }

  /// 生成性能分析摘要
  static String generateSummary(
    ExecutionPlan plan,
    List<Bottleneck> bottlenecks,
  ) {
    final buffer = StringBuffer();

    if (bottlenecks.isEmpty) {
      buffer.writeln(
        'No significant performance issues detected in this query.',
      );
      buffer.writeln('The query appears to be well-optimized.');
      return buffer.toString();
    }

    // 统计各严重程度的问题数量
    final criticalCount = bottlenecks
        .where((b) => b.severity == Severity.critical)
        .length;
    final highCount = bottlenecks
        .where((b) => b.severity == Severity.high)
        .length;
    final mediumCount = bottlenecks
        .where((b) => b.severity == Severity.medium)
        .length;
    final lowCount = bottlenecks
        .where((b) => b.severity == Severity.low)
        .length;

    buffer.writeln('Performance Analysis Summary:');
    buffer.writeln();

    if (criticalCount > 0) {
      buffer.writeln(
        '⚠️  Found $criticalCount critical issue(s) that need immediate attention.',
      );
    }
    if (highCount > 0) {
      buffer.writeln(
        '🔴 Found $highCount high severity issue(s) that should be addressed.',
      );
    }
    if (mediumCount > 0) {
      buffer.writeln(
        '🟡 Found $mediumCount medium severity issue(s) for optimization.',
      );
    }
    if (lowCount > 0) {
      buffer.writeln(
        '🟢 Found $lowCount low severity suggestion(s) for improvement.',
      );
    }

    buffer.writeln();
    buffer.writeln('Key Findings:');

    // 列出最重要的 3 个问题
    final sortedBottlenecks = List<Bottleneck>.from(bottlenecks)
      ..sort((a, b) => b.severity.level.compareTo(a.severity.level));

    for (var i = 0; i < sortedBottlenecks.length && i < 3; i++) {
      final b = sortedBottlenecks[i];
      buffer.writeln('  ${i + 1}. ${b.description}');
      if (b.recommendation != null) {
        buffer.writeln('     → ${b.recommendation}');
      }
    }

    if (sortedBottlenecks.length > 3) {
      buffer.writeln('  ... and ${sortedBottlenecks.length - 3} more issue(s)');
    }

    return buffer.toString();
  }

  /// 生成 AI 友好的分析文本
  static String generateAIAnalysisText(
    ExecutionPlan plan,
    List<Bottleneck> bottlenecks,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('Query Performance Analysis:');
    buffer.writeln('Database: ${plan.databaseType}');
    buffer.writeln();

    // 执行计划概览
    buffer.writeln('Execution Plan Overview:');
    for (final step in plan.steps) {
      buffer.write('  - Table: ${step.table ?? "N/A"}');
      if (step.scanType != null) {
        buffer.write(', Scan: ${step.scanType!.displayName}');
      }
      if (step.estimatedRows != null) {
        buffer.write(', Rows: ${step.estimatedRows}');
      }
      if (step.key != null && step.key!.isNotEmpty) {
        buffer.write(', Index: ${step.key}');
      }
      buffer.writeln();
    }
    buffer.writeln();

    // 瓶颈详情
    if (bottlenecks.isNotEmpty) {
      buffer.writeln('Performance Issues Found:');
      for (final bottleneck in bottlenecks) {
        buffer.writeln(
          '  [${bottleneck.severity.displayName}] ${bottleneck.type.name}',
        );
        buffer.writeln('    ${bottleneck.description}');
        if (bottleneck.recommendation != null) {
          buffer.writeln('    Recommendation: ${bottleneck.recommendation}');
        }
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  // === 私有辅助方法 ===

  static bool _hasSelectStar(String query) {
    final normalized = query.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.contains('SELECT *') || normalized.contains('SELECT\t*');
  }

  static bool _hasOffsetPagination(String query) {
    final normalized = query.toUpperCase();
    return normalized.contains('OFFSET') && normalized.contains('LIMIT');
  }
}
