//! 脚本 DDL 影响分析器（P3 长尾收口，2026-08-25）。
//!
//! 执行门的 DDL 分析腿此前对整段脚本只调一次 [SchemaAnalyzer.analyzeDdl]
//! ——`extractTargetTable` 是 regex firstMatch，402 条 CREATE 脚本只命中
//! 第一条的目标表，语义不精确（COMPLETED_LOG 2026-08-14「明确不做」段
//! 遗留）。本 helper 复用执行门已 split 的语句列表逐条分析（预算内），
//! 每条高风险 DDL 产出独立的 `ddl_impact` finding（带 statementIndex +
//! lineStart，B3 行级红点链路自动受益）。
//!
//! 预算语义对齐 [SafetyReviewService.reviewScript] 的 explainSelectBudget：
//! 每条 analyzeDdl 含 SELECT COUNT(*) + 依赖查询等真实网络往返，脚本 DDL
//! 条数无上限时必须有预算。超预算的剩余语句记日志跳过（不加 low finding
//! ——弹窗与红点策略都不展示 low，加了也不可见）。

import '../../models/schema_analyzer/ddl_algorithm.dart';
import '../../models/sql_statement.dart';
import '../../utils/app_logger.dart';
import '../query_execution_interceptor.dart';
import '../schema_analyzer/schema_analyzer.dart';
import 'safety_finding.dart';

class DdlScriptAnalyzer {
  /// 默认 DDL 分析预算（对齐 SafetyReviewService.reviewScript 的
  /// explainSelectBudget=10 先例）。
  static const defaultBudget = 10;

  /// 逐条分析脚本中的 DDL 语句，返回需展示的 `ddl_impact` findings
  /// （高风险或 COPY 全表锁才产出，与既有执行门聚合策略一致）。
  ///
  /// [statements] 为执行门已 split 的语句列表（不重新 split）。
  /// [statementIndex] 语义与 reviewScript 一致：多语句从 1 开始，
  /// 单语句脚本标 0。
  static Future<List<SafetyFinding>> analyzeScript({
    required List<SQLStatement> statements,
    required String databaseType,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    Future<String?> Function()? getServerVersion,
    int inplaceMediumRowThreshold = 100000,
    int ddlAnalysisBudget = defaultBudget,
  }) async {
    final findings = <SafetyFinding>[];
    final isScript = statements.length > 1;
    var ddlTotal = 0;
    var analyzed = 0;
    for (var i = 0; i < statements.length; i++) {
      final stmt = statements[i];
      if (!QueryExecutionInterceptor.isDdlStatement(stmt.sql)) continue;
      ddlTotal++;
      if (analyzed >= ddlAnalysisBudget) continue;
      analyzed++;
      try {
        final report = await SchemaAnalyzer.analyzeDdl(
          ddlStatement: stmt.sql,
          databaseType: databaseType,
          executeQuery: executeQuery,
          getServerVersion: getServerVersion,
          inplaceMediumRowThreshold: inplaceMediumRowThreshold,
        );
        // 聚合为 SafetyFinding：高风险或全表锁（COPY）时才追加，
        // 避免 INSTANT 操作（秒级无锁）也弹窗。
        if (report.riskLevel.isHighOrAbove ||
            report.ddlAlgorithm == DdlAlgorithm.copy) {
          final severity = report.riskLevel.isHighOrAbove
              ? Severity.high
              : Severity.medium;
          final tableHint =
              report.targetTable != 'unknown' ? '（表 ${report.targetTable}）' : '';
          findings.add(
            SafetyFinding(
              ruleId: 'ddl_impact',
              severity: severity,
              title: 'DDL 影响分析：${report.lockType ?? report.ddlType}',
              description: '${report.algorithmNote ?? ""}$tableHint',
              affectedTable:
                  report.targetTable != 'unknown' ? report.targetTable : null,
              statementIndex: isScript ? i + 1 : 0,
              lineStart: stmt.lineStart,
            ),
          );
        }
      } catch (e) {
        // 网关/embedded 模式查询失败等 → 降级跳过该条（不阻断执行，
        // 与既有执行门降级语义一致）。
        AppLogger.w(
          'DdlScriptAnalyzer',
          'DDL 影响分析失败（语句 ${i + 1}），降级跳过: $e',
        );
      }
    }
    if (ddlTotal > analyzed) {
      AppLogger.w(
        'DdlScriptAnalyzer',
        '脚本含 $ddlTotal 条 DDL，超预算 $ddlAnalysisBudget，'
        '其余 ${ddlTotal - analyzed} 条跳过影响分析',
      );
    }
    return findings;
  }
}
