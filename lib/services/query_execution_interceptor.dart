import 'dart:developer' as developer;

import '../models/database_models.dart';
import '../models/dml_risk_models.dart';
import '../models/schema_analyzer/ddl_algorithm.dart';
import '../models/sql_statement.dart';
import 'dml_safety_service.dart';
import 'doris_table_model_detector.dart';
import 'query_history/query_history_service.dart';
import 'schema_analyzer/schema_analyzer.dart';
import 'sql_parser_service.dart';

/// 查询执行拦截器
/// 在查询执行前后进行：
/// 1. DML 安全检查（NEW）
/// 2. DDL 影响分析
/// 3. 查询历史记录
class QueryExecutionInterceptor {
  final QueryHistoryService _historyService;
  final DmlSafetyService _dmlSafetyService;

  QueryExecutionInterceptor({
    QueryHistoryService? historyService,
    DmlSafetyService? dmlSafetyService,
  })  : _historyService = historyService ?? QueryHistoryService(),
        _dmlSafetyService = dmlSafetyService ?? DmlSafetyService();

  /// 是否启用 DDL 分析
  bool enableDdlAnalysis = true;

  /// 是否启用历史记录
  bool enableHistoryRecording = true;

  /// 是否启用 DML 安全检查 (default: true)
  bool enableDmlCheck = true;

  /// 是否启用 EXPLAIN 预检 (default: true)
  bool enableExplainPreflight = true;

  /// Preflight cache: normalized SQL hash → result, with 60s TTL.
  final Map<String, _CachedPreflightResult> _preflightCache = {};

  static const _preflightCacheTtl = Duration(seconds: 60);

  /// 检查是否为 DDL 语句
  static bool isDdlStatement(String sql) {
    final normalized = sql.trim().toUpperCase();
    return normalized.startsWith('CREATE') ||
        normalized.startsWith('ALTER') ||
        normalized.startsWith('DROP') ||
        normalized.startsWith('TRUNCATE') ||
        normalized.startsWith('RENAME');
  }

  /// 检查是否为影响数据的 DDL
  static bool isDataModifyingDdl(String sql) {
    final normalized = sql.trim().toUpperCase();
    return normalized.startsWith('DROP') ||
        normalized.startsWith('TRUNCATE') ||
        (normalized.startsWith('ALTER') &&
            (normalized.contains('DROP COLUMN') ||
                normalized.contains('MODIFY') ||
                normalized.contains('ALTER COLUMN')));
  }

  /// 执行前拦截（DDL 分析）
  /// 返回 null 表示可以继续执行
  /// 返回 ImpactReport 表示需要用户确认
  ///
  /// [getServerVersion] 可选回调（SELECT VERSION() 结果），用于 MySQL DDL
  /// 锁语义推断。不传时锁字段为 unknown（向后兼容，行为同未接入锁语义前）。
  /// 统一执行门语义：与 query_editor_widget 的执行门路径一致，
  /// 高风险（high/critical）**或** 全表锁（COPY）时返回报告要求确认——
  /// COPY 即使评级 medium 也阻塞生产写，应让用户确认。
  Future<ImpactReport?> beforeExecute({
    required String sql,
    required DatabaseType databaseType,
    required String connectionId,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
    Future<String?> Function()? getServerVersion,
  }) async {
    if (!enableDdlAnalysis) return null;
    if (!isDdlStatement(sql)) return null;

    try {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: sql,
        databaseType: databaseType.name,
        executeQuery: executeQuery,
        getServerVersion: getServerVersion,
      );

      // 风险等级高，或全表锁（COPY，阻塞生产写）→ 返回报告要求确认。
      // 与 query_editor_widget 执行门路径过滤条件一致（链路统一）。
      if (report.requiresConfirmation ||
          report.ddlAlgorithm == DdlAlgorithm.copy) {
        developer.log(
          'DDL requires confirmation: ${report.ddlType} on ${report.targetTable} '
          '(Risk: ${report.riskLevel.displayName}, Algorithm: ${report.ddlAlgorithm.name})',
          name: 'QueryExecutionInterceptor',
        );
        return report;
      }

      return null;
    } catch (e) {
      developer.log(
        'DDL analysis failed: $e',
        name: 'QueryExecutionInterceptor',
      );
      // 分析失败时，允许继续执行（安全优先）
      return null;
    }
  }

  /// 执行后拦截（历史记录）
  Future<void> afterExecute({
    required String sql,
    required String connectionId,
    required String? connectionName,
    required DatabaseType databaseType,
    required String? databaseName,
    required int executionTimeMs,
    required bool isSuccess,
    String? errorMessage,
    int? rowCount,
  }) async {
    if (!enableHistoryRecording) return;

    try {
      // 跳过某些查询类型
      if (_shouldSkipRecording(sql)) return;

      await _historyService.recordQuery(
        sqlStatement: sql,
        connectionId: connectionId,
        connectionName: connectionName,
        databaseType: databaseType.name,
        databaseName: databaseName,
        executionTimeMs: executionTimeMs,
        rowCount: rowCount,
        isSuccess: isSuccess,
        errorMessage: errorMessage,
      );

      developer.log(
        'Query recorded to history: ${sql.substring(0, sql.length > 50 ? 50 : sql.length)}...',
        name: 'QueryExecutionInterceptor',
      );
    } catch (e) {
      developer.log(
        'Failed to record query history: $e',
        name: 'QueryExecutionInterceptor',
      );
    }
  }

  /// DML safety check — runs BEFORE DDL analysis in the pipeline.
  ///
  /// Returns `null` if safe to proceed, otherwise throws the appropriate
  /// exception for the caller to catch and handle via UI dialogs/banners.
  ///
  /// [environment] 为目标连接的环境（B-07/UI35-441 production 分流 seam）：
  /// `ConnectionEnvironment.production` 时阻断级（critical）DML 不再抛
  /// [DmlConfirmationRequiredException]，改抛 [ProductionGuardRequiredException]
  /// 由 UI 消费方弹生产守卫（L1/L2）；testing/development/null（含不传参，
  /// 即既有全部调用方）行为零变化——既有确认门逐字节不变。
  ///
  /// Pipeline order: DML check → DDL analysis → EXPLAIN preflight → Execute
  Object? checkDmlSafety({
    required String sql,
    required DatabaseType dbType,
    required String connectionId,
    ConnectionEnvironment? environment,
  }) {
    if (!enableDmlCheck) return null;

    final statements = SQLParserService.split(sql);
    final analysis = _dmlSafetyService.analyze(statements, dbType);

    if (analysis.riskLevel.isBlocking) {
      // B-07/UI35-441 production 分流：production 连接的阻断级 DML 改走生产
      // 守卫信号（非旧确认门异常，也非静默放行）；非 production 路径下方
      // 既有 critical 门保持原样。
      if (environment == ConnectionEnvironment.production) {
        throw ProductionGuardRequiredException(
          sql: sql,
          analysis: analysis,
          statements: statements,
        );
      }
      // Critical risk — throw to trigger modal confirmation
      throw DmlConfirmationRequiredException(
        sql: sql,
        analysis: analysis,
        statements: statements,
      );
    }

    if (analysis.riskLevel == DmlRiskLevel.high) {
      // High risk — throw to trigger non-blocking warning banner
      throw DmlWarningRequiredException(
        sql: sql,
        analysis: analysis,
      );
    }

    // Normal — proceed silently
    return null;
  }

  /// Doris UPDATE 模型守卫——DUPLICATE/AGGREGATE 模型不支持 UPDATE，会触发服务端报错。
  /// 检测到非可更新模型时抛 [DmlWarningRequiredException]（高风险警告，**非阻断**；
  /// UI 以非阻塞横幅呈现）。模型检测失败则降级（不守卫、不阻断）。
  ///
  /// [DmlSafetyService.analyze] 为同步且无连接上下文，模型检测需异步查
  /// `SHOW CREATE TABLE`，故独立为 async 守卫，在执行管线中于 DML 检查之后调用。
  Future<void> checkDorisUpdateGuard({
    required String sql,
    required DatabaseType dbType,
    required Future<List<Map<String, dynamic>>> Function(String) executeQuery,
  }) async {
    if (!enableDmlCheck) return;
    if (dbType != DatabaseType.doris) return;

    final type = SQLParserService.detectType(sql);
    if (type != SQLType.update) return;

    final tableName = SQLParserService.extractTableName(sql, type);
    if (tableName == null || tableName.isEmpty) return;

    final model = await DorisTableModelDetector.detect(tableName, executeQuery);
    if (model != null && !model.supportsUpdate) {
      throw DmlWarningRequiredException(
        sql: sql,
        analysis: RiskAnalysisResult(
          riskLevel: DmlRiskLevel.high,
          triggers: const [RiskTrigger.dorisUpdateOnNonUpdatableModel],
          affectedObjects: [tableName],
        ),
      );
    }
  }

  /// Log a blocked DML operation (user cancelled or mismatched).
  void logDmlBlocked({
    required String sql,
    required String connectionId,
    required DmlRiskLevel riskLevel,
    required AuditDecision decision,
  }) {
    final snippet = sql.length > 200 ? sql.substring(0, 200) : sql;
    final entry = AuditLogEntry(
      timestamp: DateTime.now(),
      connectionId: connectionId,
      sqlSnippet: snippet,
      riskLevel: riskLevel,
      decision: decision,
    );
    _dmlSafetyService.logBlockedOperation(entry);
  }

  /// Invalidate preflight cache entries related to a table name
  /// (called after DDL execution that modifies schema).
  void invalidatePreflightCacheForTable(String tableName) {
    _preflightCache.removeWhere((key, _) => key.contains(tableName));
  }

  /// Clear the entire preflight cache.
  void clearPreflightCache() {
    _preflightCache.clear();
  }

  /// 跳过某些不需要记录的查询
  bool _shouldSkipRecording(String sql) {
    final normalized = sql.trim().toUpperCase();
    // 跳过 EXPLAIN 查询
    if (normalized.startsWith('EXPLAIN')) return true;
    // 跳过系统查询
    if (normalized.contains('INFORMATION_SCHEMA')) return true;
    if (normalized.contains('PERFORMANCE_SCHEMA')) return true;
    // 跳过 SHOW 查询
    if (normalized.startsWith('SHOW')) return true;
    return false;
  }
}

/// 生产守卫分流信号（B-07 / UI35-441）：production 连接的阻断级 DML 不走
/// [DmlConfirmationRequiredException] 既有确认门，由 UI 消费方捕获本异常弹
/// `showProductionGuardDialog`（L1/L2 分级）。本类只承载信号与守卫参数推导，
/// 不含 UI 依赖（services 层不 import organisms 类型）。
///
/// UI 消费方契约（B-07 分流）：
/// - 守卫分级：[isL1Destructive] == true → `ProductionGuardLevel.l1Destructive`
///   （type-to-confirm，目标名 = [targetObjectName]）；false →
///   `l2UnboundedWrite`（免输入，estimatedRows 见下）。
/// - 确认后链路：guard 返回 true → 走与既有 DML 确认门通过后一致的执行链路
///   （bypass 重执），不得绕过既有执行/审计链。
/// - 审计不旁路：guard 返回 false（取消/Esc/AI 分流，操作未执行）→ 调
///   [QueryExecutionInterceptor.logDmlBlocked]（decision: cancelled），与既有
///   `DmlConfirmationRequiredException` 取消路径同一审计出口。
/// - AI 备份：onAiBackup → openAiPanel + requestComposerPrefill(
///   prodGuardAiBackupPrompt([targetObjectName]))——弹窗回调由消费方注入。
/// - estimatedRows：本 seam 为同步检查，行数估算不可得 → null（禁 0 冒充）；
///   消费方弹窗前可选用 `DmlSafetyService.getEstimatedRowCount`（MySQL/PG/
///   SQL Server 走 information_schema 元数据读、SQLite 走 500ms 超时
///   COUNT——只读且不放大目标表锁面；失败回落 null）。
class ProductionGuardRequiredException implements Exception {
  final String sql;
  final RiskAnalysisResult analysis;
  final List<SQLStatement> statements;

  const ProductionGuardRequiredException({
    required this.sql,
    required this.analysis,
    required this.statements,
  });

  /// B-07 分级映射：DROP TABLE/DROP DATABASE/TRUNCATE 族触发器 → L1 破坏性
  /// （目标名输入匹配）；无 WHERE 的 DELETE/UPDATE 族（及其它组合升级到
  /// critical 的情况）→ L2 无范围写（免输入）。
  bool get isL1Destructive => analysis.triggers.any(
    (t) =>
        t == RiskTrigger.dropTable ||
        t == RiskTrigger.dropDatabase ||
        t == RiskTrigger.truncateTable,
  );

  /// 守卫目标对象名（L1 输入匹配 / AI 备份 prompt 的 {object} 填充值）；
  /// 分析器未能提取对象名时为空串（L1 场景实际不会发生——DROP/TRUNCATE
  /// 均可提取；防御性兜底）。
  String get targetObjectName =>
      analysis.affectedObjects.isNotEmpty ? analysis.affectedObjects.first : '';

  @override
  String toString() =>
      'ProductionGuardRequiredException(risk: ${analysis.riskLevel}, '
      'triggers: ${analysis.triggers}, objects: ${analysis.affectedObjects})';
}

/// Cached EXPLAIN preflight result with TTL.
class _CachedPreflightResult {
  final Object? result;
  final DateTime timestamp;
  const _CachedPreflightResult({required this.result, required this.timestamp});
  bool get isExpired =>
      DateTime.now().difference(timestamp) >
      QueryExecutionInterceptor._preflightCacheTtl;
}
