//! 工作台执行动作编排（T13，design-ai-workbench §6.2 / D9）。
//!
//! 状态机（design §6.2 执行 + 确认时序）：
//! 1. **上下文复核**：执行时 `effectiveWorkbenchContext`（锁定快照优先），
//!    不信任建卡时的上下文快照；不可用 → 错误卡 + 「去设置连接」出口
//!    （SnackBar 动作打开既有 ConnectionDialog，与 T11 芯片未设置态同源）。
//! 2. **空白守卫**：空串/纯空白 SQL 不进确认流（T06 `isWriteSql` 对空白
//!    判写，先于分流拦下）→ 错误卡。
//! 3. **多语句拆分**：`SQLParserService.split`（既有拆分器，extractedCommands
//!    同语义）→ **两遍法**：先对全部语句过写门禁（任一写语句取消则整批
//!    零执行，AC6.1 批量形态），再逐条执行逐条落卡（AC9.5 部分失败可辨识）。
//!    拆分异常（ParseException，如未闭合注释）**fail-closed**：不整块回退
//!    执行（整块过闸会被 gate#1 前缀判读误判只读，fail-open），零执行 +
//!    错误卡（F1）。
//! 4. **写门禁（gate #1）**：`AiToolClassifier.isWriteSql` 分流（只读直接
//!    执行，AC6.4）→ 写语句经会话放行集（`_allowedWriteServers`，key =
//!    connectionId，镜像经典 `_allowedSessionServers` 语义）→ 未放行弹
//!    [ConfirmExecuteDialog]（含 SQL 全文 + 目标连接/库行，AC6.5）→
//!    cancel 零执行 / allowSession 入集 / allowOnce。
//! 5. **执行**：只经 `AppProvider.executeQueryDetailed` facade（既有管线：
//!    DDL/DML 拦截、行限制、embedded 网关路由、只读连接检查全部继承，
//!    M1 不增不减；裁决选项 A detailed 通道在解包层保留 affectedRows，
//!    SELECT PII 脱敏经 TabProvider 层不变）。
//! 6. **双异常路由（gate #2，管线门禁）**：`DdlConfirmationRequiredException`
//!    → [DdlConfirmDialog] + 确认后 `dbService.executeQueryBypassDdl`（双重
//!    门槛）；`DmlConfirmationRequiredException` → [DmlConfirmDialog] + 确认后
//!    `dbService.executeQueryBypassDml`（编辑器侧先例
//!    `lib/core/commands/query_execution_helper.dart`；经典 AI 面板不处理
//!    后者导致裸异常文案——工作台两类都接住，不裸奔）。取消走审计
//!    （logDmlBlocked）+ 「已取消」消息。
//! 7. **落卡 + 统计**：成功 → `WorkbenchResultCardPayload` 落卡（toolName
//!    'workbench'，无同名 toolCall 不被 `_mergeToolMessages` 吞并）+
//!    recordOp/recordCard（§6.4 按语句类型逐条分类：只读→queryGen；DML
//!    写→bulkMaint；DDL/权限类→ddlPerm——批量维度不再整体归 bulkMaint，
//!    判定来源 `AiToolClassifier.opClassOf`）；失败 →
//!    `WorkbenchErrorCardPayload` 错误卡（detail 先过 `redactSecrets`
//!    脱敏——防驱动异常带连接串/token 回显入会话明文持久化，F5），不静默。
//!
//! ③-⑥ 骨架自 T20 起由共享 `SqlStatementGateRunner`
//! （`lib/services/sql_statement_gate_runner.dart`，两消费方：本文件 M1
//! 路径 + A2 `AgentPlanExecutor`）承载；本文件经回调注入对话框（gate #1
//! [ConfirmExecuteDialog] / gate #2 [DdlConfirmDialog] / [DmlConfirmDialog]）
//! 与落卡统计实现——用户可感行为与提取前逐点等价（既有测试零修改为证）。
//!
//! B1（v2 先行批）：`run` 增可选参 `onExecutionBatch`——批末把含写/DDL
//! 的批次投影为 execution tab 数据（R3 推送条件 / R4 单例键 'manual'）；
//! `withAgentQueryHistory` 增可选收集器参数（计划链耗时/行数并联收集，
//! 门控控制流信号不产行）。两处均为**只读投影**——执行语义/确认门/审计
//! 链零改动。
//!
//! 影响行数贯通（2026-09-26 裁决选项 A detailed 通道）：执行/双 bypass
//! 绑定换 `executeQueryDetailed` / `executeQueryBypass{Ddl,Dml}Detailed`
//! 变体（经 AppProvider facade 层，SELECT PII 脱敏保留），投影与历史双
//! 写改读真 affectedRows（不再以 rows.length 冒充）。
//!
//! bypass 取道 `provider.dbService`（经 AppProvider facade 访问，design §6.2
//! 原文「dbService.executeQueryBypassDdl（既有绕行，同经典）」；不经
//! `executeQueryBypassDdlAndUpdateResults`——那会写经典 activeTab 结果，
//! 违反 R7 工作台不写 tab 语义）。

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_message_type.dart';
import '../../models/database_models.dart' show AiMessage, DatabaseType, DbServer;
import '../../models/dml_risk_models.dart';
import '../../models/query_history.dart' show QueryHistorySource;
import '../../providers/app_provider.dart';
import '../../services/ai/ai_tool_classifier.dart';
import '../../services/ai/workbench_context_resolver.dart';
import '../../services/database_service.dart';
import '../../services/query_history/query_history_service.dart';
import '../../services/readonly_guard.dart' show ReadOnlyBlockedException;
import '../../services/sql_statement_gate_runner.dart';
import '../../services/workbench_usage_stats_service.dart';
import '../../utils/app_logger.dart';
import '../../utils/secret_redactor.dart';
import '../connection/connection_dialog.dart';
import '../dialogs/dml_confirm_dialog.dart';
import '../ai_panel/confirm_execute_dialog.dart';
import '../ai_panel/ddl_confirm_dialog.dart';
import 'cards/result_table_card.dart';
import 'workbench_card_payload.dart';
import 'workbench_stage.dart'
    show StageExecutionData, StageExecutionRow, StageExecutionStatus;

/// 工作台 SQL 执行编排（SQL 卡「执行」/ 错误卡「重试」/ 消息级执行共用入口）。
///
/// [allowedWriteServers] 由宿主（shell State）持有并传入——会话放行集随
/// Offstage 保活跨模式存活、应用重启重置（design §6.5，内存语义）。
class WorkbenchExecutionActions {
  WorkbenchExecutionActions._();

  static int _messageCounter = 0;

  /// 执行入口：上下文复核 → 空白守卫 → 写门禁 → 逐条执行逐条落卡。
  ///
  /// [onExecutionBatch]（B1，可选）：批末回调推送 execution tab 投影——
  /// 批内含 ≥1 写/DDL 语句（`AiToolClassifier.isWriteSql` 口径）且有真实
  /// 执行才组装（R3；纯只读批 / 拆分失败 / 全取消零执行不推，永不空开）；
  /// 行 = 批内全部语句（含只读与 skipped）。tabKey 恒
  /// [StageExecutionData.manualTabKey]（R4 单例键，复用刷新）。
  static Future<void> run(
    BuildContext context,
    String sql, {
    required Set<String> allowedWriteServers,
    void Function(StageExecutionData data)? onExecutionBatch,
  }) async {
    final provider = context.read<AppProvider>();
    final l10n = AppLocalizations.of(context)!;

    // ① 上下文复核（执行时，不用建卡时的快照）。
    final ctx = effectiveWorkbenchContext(
      provider.aiPanel.aiConversationService.currentSession,
      provider,
    );
    final connectionId = ctx.connectionId;
    if (connectionId == null) {
      _landErrorCard(provider, sql, l10n.workbenchErrorNoContext, null);
      _showSetupConnectionExit(context);
      return;
    }

    // ② 空白守卫：空 SQL 不进确认流（isWriteSql 对空白判写），直接报错误卡。
    if (sql.trim().isEmpty) {
      _landErrorCard(provider, sql, l10n.workbenchErrorEmptySql, null);
      return;
    }

    // B1 批次收集容器：done/failed 结局在 onStatementResult 既有回调处同步
    // 入集（skipped 不触发回调，批末由终局结果补齐——行须含全批语句，R3）。
    final collected = <int, SqlStatementResult>{};

    // ③④⑤ 拆分 + 两遍法写门禁 + 逐语句执行/双异常路由 → 共享骨架
    //    （T20 `SqlStatementGateRunner`，perStatement 写确认模式）。
    //    对话框/落卡经回调注入，语义与提取前逐点等价（AC6.1/6.2/6.4/
    //    9.5、F1 fail-closed、gate #2 双门）。
    final result = await const SqlStatementGateRunner().run(
      sql: sql,
      deps: SqlGateRunDeps(
        execute: (statement) async {
          // 裁决选项 A detailed 通道：经 AppProvider.executeQueryDetailed
          // （TabProvider 层 SELECT PII 脱敏保留）取 affectedRows。
          final QueryExecutionResult outcome = await provider
              .executeQueryDetailed(
            statement,
            connectionId: ctx.connectionId,
            database: ctx.databaseName,
          );
          return SqlStatementOutcome.fromExecutionResult(outcome);
        },
        writeConfirm: SqlWriteConfirmStrategy.perStatement(
          (statement) => _confirmWrite(
            context,
            statement: statement,
            ctx: ctx,
            connectionId: connectionId,
            allowedWriteServers: allowedWriteServers,
          ),
        ),
        ddlConfirm: (e) => _confirmDdl(context, e),
        dmlConfirm: (e) =>
            _confirmDml(context, provider: provider, ctx: ctx, e: e),
        executeBypassDdl: (statement) async {
          final QueryExecutionResult outcome =
              await provider.dbService.executeQueryBypassDdlDetailed(
            statement,
            connectionId: ctx.connectionId,
            database: ctx.databaseName,
          );
          return SqlStatementOutcome.fromExecutionResult(outcome);
        },
        executeBypassDml: (statement) async {
          final QueryExecutionResult outcome =
              await provider.dbService.executeQueryBypassDmlDetailed(
            statement,
            connectionId: ctx.connectionId,
            database: ctx.databaseName,
          );
          return SqlStatementOutcome.fromExecutionResult(outcome);
        },
        // 每语句执行前的宿主存活探针（原逐语句循环头 mounted 检查）。
        shouldContinue: () => context.mounted,
        onStatementResult: (outcome) {
          // B1：execution tab 批次行同步收集（回调仅 done/failed 触发，
          // runner 契约；skipped 批末由 result.results 补齐）。
          collected[outcome.index] = outcome;
          // 查询历史双写（agent 来源）：done/failed 都记（skipped 不回调，
          // 显式守卫防御）；EXPLAIN/系统查询在双写助手内跳过；写入为
          // unawaited 且内部吞错——历史失败不阻断执行 UI（含 bypass 通道
          // 执行的语句：runner 对 bypass 成功/失败同样回调 done/failed）。
          if (outcome.status == SqlStatementStatus.done ||
              outcome.status == SqlStatementStatus.failed) {
            recordAgentQueryHistory(
              provider,
              sql: outcome.statement,
              connectionId: connectionId,
              connectionName: ctx.connectionName,
              database: ctx.databaseName,
              durationMs: outcome.durationMs,
              // 裁决：历史双写用真 affectedRows（detailed 通道引擎值）；
              // 读语句无影响行概念（引擎 null）回落行数——与拦截器
              // afterExecute 的 rowCount 口径一致
              // （query_result?.affectedRows ?? rows.length）。
              affectedRows: outcome.status == SqlStatementStatus.done
                  ? (outcome.affectedRows ?? outcome.rows?.length ?? 0)
                  : 0,
              error: outcome.status == SqlStatementStatus.failed
                  ? outcome.error?.toString()
                  : null,
            );
          }
          if (outcome.status == SqlStatementStatus.done) {
            final rows = outcome.rows;
            if (rows != null) {
              _landResultCard(
                provider,
                sql: outcome.statement,
                rows: rows,
                durationMs: outcome.durationMs,
              );
            }
          } else if (outcome.status == SqlStatementStatus.failed) {
            _landErrorCard(
              provider,
              outcome.statement,
              l10n.aiPanelExecuteFailed,
              outcome.error?.toString(),
            );
          }
        },
      ),
    );

    // ⑥ 终局映射：中止面 → 消息流/审计/错误卡。中止即批末，落地时序与
    //    提取前等价（拆分失败落错误卡；gate #2 取消落「已取消」消息，
    //    DML 取消先记拦截审计——编辑器侧同款）。
    switch (result.status) {
      case SqlBatchStatus.splitFailed:
        AppLogger.d(
          'WorkbenchExec',
          'statement split failed, fail-closed (nothing executed): '
              '${result.splitError} · ${AppLogger.sqlPreview(sql.trim())}',
        );
        _landErrorCard(
          provider,
          sql,
          l10n.aiPanelExecuteFailed,
          'Unable to split statements safely; nothing was executed',
        );
      case SqlBatchStatus.emptyInput:
        _landErrorCard(provider, sql, l10n.aiPanelExecuteFailed, null);
      case SqlBatchStatus.ddlCancelled:
        // DDL 取消：消息流记「已取消」，目标库零变化（design §6.2）。
        _landCancelledMessage(provider, l10n.aiPanelDdlOperationCancelled);
      case SqlBatchStatus.dmlCancelled:
        final e = result.dmlException;
        if (e != null) {
          // 记录拦截决策（审计，编辑器侧同款）+ 消息流「已取消」。
          provider.dbService.interceptor.logDmlBlocked(
            sql: e.sql,
            connectionId: connectionId,
            riskLevel: e.analysis.riskLevel,
            decision: AuditDecision.cancelled,
          );
        }
        _landCancelledMessage(provider, l10n.operationCancelled);
      case SqlBatchStatus.completed:
      case SqlBatchStatus.writeCancelled:
      case SqlBatchStatus.failureHalt:
      case SqlBatchStatus.aborted:
        break;
    }

    // 批末（终局映射后）B1 execution tab 投影（R3/R4）：批内含 ≥1 写/DDL
    //    且有真实执行 → 组装推送（宿主绑 `_stageController.openExecution`）；
    //    纯只读批 / 拆分失败 / 全取消（零执行）不推（永不空开，v1 §3.7）。
    //    只读执行结果做投影，执行路径一行不改。
    if (onExecutionBatch != null) {
      final batch = _assembleExecutionBatch(result, collected, l10n);
      if (batch != null) onExecutionBatch(batch);
    }
  }

  /// B1 execution tab 批次组装（R3/R4）：null = 不推送。
  ///
  /// 推送条件（R3）：批内含 ≥1 写/DDL 语句（`AiToolClassifier.isWriteSql`
  /// 口径）且批内有真实执行（[collected] 非空 = 至少一条 done/failed）——
  /// 纯只读批（结果卡已承载）/ 拆分失败 / gate #1 全取消（零执行）不推。
  /// 行 = 批内全部语句（[SqlStatementBatchResult.results] 含 skipped 收尾，
  /// 时间序 = 执行序；部分失败的上下文需要全批语句行）。tabKey 恒
  /// [StageExecutionData.manualTabKey]（手动执行无 runId/planId 可锚，
  /// 单例键复用刷新不累积，R4）；标题含时间戳。
  static StageExecutionData? _assembleExecutionBatch(
    SqlStatementBatchResult result,
    Map<int, SqlStatementResult> collected,
    AppLocalizations l10n,
  ) {
    if (collected.isEmpty || result.results.isEmpty) return null;
    final hasWrite = result.results.any(
      (r) => AiToolClassifier.isWriteSql(r.statement),
    );
    if (!hasWrite) return null;
    return StageExecutionData(
      tabKey: StageExecutionData.manualTabKey,
      title: StageExecutionData.titleWithTimestamp(
        l10n.agentStageTabExecution,
        DateTime.now(),
      ),
      rows: [for (final r in result.results) _executionRowOf(r)],
    );
  }

  /// 单语句结局 → execution tab 行（展示语义投影）。
  static StageExecutionRow _executionRowOf(SqlStatementResult r) {
    switch (r.status) {
      case SqlStatementStatus.done:
        return StageExecutionRow(
          sql: r.statement,
          status: StageExecutionStatus.done,
          // 裁决：改读 detailed 通道真 affectedRows（r.affectedRows）——
          // DDL 展示语义（裁决定案）：引擎报 0（MySQL DDL 成功常报 0）时
          // 抑制 chip，仅 >0 显示；DML 直显引擎值；读语句引擎 null 降级
          // 不显。
          affectedRows: _displayAffectedRows(r.statement, r.affectedRows),
          durationMs: r.durationMs,
        );
      case SqlStatementStatus.failed:
        return StageExecutionRow(
          sql: r.statement,
          status: StageExecutionStatus.failed,
          durationMs: r.durationMs,
          // F5 对齐：错误全文入投影前脱敏（防驱动异常带连接串/token 上屏）。
          error: redactSecrets(r.error?.toString() ?? ''),
        );
      case SqlStatementStatus.skipped:
        // 未执行语句：状态 + SQL 无指标（门控取消/中止边界余下语句）。
        return StageExecutionRow(
          sql: r.statement,
          status: StageExecutionStatus.skipped,
        );
    }
  }

  /// DDL 展示语义（裁决定案，写进实现与测试）：引擎报 0（MySQL DDL
  /// 成功常报 0）时抑制 chip（返回 null），仅 >0 显示；DML 直显引擎值
  /// （含 0）；null（读语句/通道缺失）保持 null。DML 判定沿统计三分类
  /// 口径（`AiToolClassifier.opClassOf == bulkMaint`，INSERT/UPDATE/
  /// DELETE/REPLACE 词边界）。
  static int? _displayAffectedRows(String sql, int? affectedRows) {
    if (affectedRows == null) return null;
    final bool isDml =
        AiToolClassifier.opClassOf(sql) == WorkbenchOpClass.bulkMaint;
    if (isDml) return affectedRows;
    return affectedRows > 0 ? affectedRows : null;
  }

  /// gate #1 写确认回调（M1 三态 + 连接级放行集；绑定 [ConfirmExecuteDialog]）。
  /// 连接级放行（会话放行集命中）免弹直接放行——原「break 后续免弹」语义
  /// 的注入侧实现。cancel 落 AppLogger 调试日志；context 失效 → aborted
  /// 静默中止（原 gate 循环 mounted 检查的等价映射）。
  static Future<SqlWriteConfirmDecision> _confirmWrite(
    BuildContext context, {
    required String statement,
    required WorkbenchContextValue ctx,
    required String connectionId,
    required Set<String> allowedWriteServers,
  }) async {
    if (allowedWriteServers.contains(connectionId)) {
      return SqlWriteConfirmDecision.allowOnce; // 连接级放行，免弹
    }
    final result = await showDialog<ConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ConfirmExecuteDialog(
        command: statement,
        warningReason: null, // D9：allowOnce/allowSession/cancel 三态语义
        l10n: AppLocalizations.of(dialogContext)!,
        targetConnection: ctx.connectionName ?? connectionId,
        targetDatabase: ctx.databaseName ?? '—',
      ),
    );
    if (result == ConfirmResult.allowSession) {
      allowedWriteServers.add(connectionId);
    } else if (result != ConfirmResult.allowOnce) {
      // cancel / 关闭：什么都不执行（AC6.2，零 executeQuery 调用）。
      AppLogger.d(
        'WorkbenchExec',
        'write confirm cancelled, nothing executed: '
            '${AppLogger.sqlPreview(statement)}',
      );
      return SqlWriteConfirmDecision.cancel;
    }
    if (!context.mounted) return SqlWriteConfirmDecision.aborted;
    return SqlWriteConfirmDecision.allowOnce;
  }

  /// gate #2 DDL 双门确认回调（绑定 [DdlConfirmDialog]）。context 失效 →
  /// aborted 静默中止（原「return true + 循环头 mounted 拦截」的等价映射）。
  static Future<SqlGateConfirmDecision> _confirmDdl(
    BuildContext context,
    DdlConfirmationRequiredException e,
  ) async {
    if (!context.mounted) return SqlGateConfirmDecision.aborted;
    final result = await showDialog<DdlConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          DdlConfirmDialog(sql: e.sql, impactReport: e.impactReport),
    );
    if (result != DdlConfirmResult.execute) {
      return SqlGateConfirmDecision.cancelled;
    }
    if (!context.mounted) return SqlGateConfirmDecision.aborted;
    return SqlGateConfirmDecision.confirmed;
  }

  /// gate #2 DML 门确认回调（绑定 [DmlConfirmDialog]；取消面审计在终局
  /// 映射落地）。
  static Future<SqlGateConfirmDecision> _confirmDml(
    BuildContext context, {
    required AppProvider provider,
    required WorkbenchContextValue ctx,
    required DmlConfirmationRequiredException e,
  }) async {
    if (!context.mounted) return SqlGateConfirmDecision.aborted;
    final confirmResult = await DmlConfirmDialog.show(
      context,
      analysis: e.analysis,
      statements: e.statements,
      dbType: _dbTypeOf(provider, ctx.connectionId),
    );
    if (confirmResult != DmlConfirmResult.confirm) {
      return SqlGateConfirmDecision.cancelled;
    }
    if (!context.mounted) return SqlGateConfirmDecision.aborted;
    return SqlGateConfirmDecision.confirmed;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 类型解析（语句拆分已下沉共享骨架 SqlStatementGateRunner，T20）
  // ──────────────────────────────────────────────────────────────────────────

  /// DML 确认对话框的数据库类型（savedConnections 命中；未命中回退 mysql，
  /// 编辑器侧同款兜底）。
  static DatabaseType _dbTypeOf(AppProvider provider, String? connectionId) {
    if (connectionId != null) {
      for (final server in provider.connection.savedConnections) {
        if (server.id == connectionId) return server.type;
      }
    }
    return DatabaseType.mysql;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 落卡（消息流）与统计
  // ──────────────────────────────────────────────────────────────────────────

  /// 成功落结果卡 + 统计（§6.4 按语句类型逐条分类：只读→queryGen；DML 写→
  /// bulkMaint；DDL/权限类→ddlPerm——判定来源 `AiToolClassifier.opClassOf`，
  /// 批量维度不参与；SQL 卡执行成功→cards.sqlCard；结果卡生成→cards.resultCard）。
  static void _landResultCard(
    AppProvider provider, {
    required String sql,
    required List<Map<String, dynamic>> rows,
    required int durationMs,
  }) {
    final payload = WorkbenchResultCardPayload(
      sql: sql,
      rowCount: rows.length,
      durationMs: durationMs,
      columns: _columnsOf(rows),
      rows: rows,
      // columnTypes 来自 QueryExecutionResult——detailed 通道已供给
      // affectedRows/executionTimeMs，列类型此层暂不投影（payload 契约
      // 允许 null）。
      columnTypes: null,
    );
    provider.addAiMessage(_cardMessage(payload.toJson()));
    final stats = WorkbenchUsageStatsService.instance;
    stats.recordCard(WorkbenchCardKindStat.sqlCard);
    stats.recordCard(WorkbenchCardKindStat.resultCard);
    stats.recordOp(AiToolClassifier.opClassOf(sql));
  }

  /// 失败落错误卡（AC4.4/AC9.4：错误可见可辨识，不静默）。[summary] 已本地化；
  /// [detail] 为技术详情（异常原文，mono 块呈现），落卡前过 `redactSecrets`
  /// 脱敏（F5）——错误卡随会话明文持久化，防未来驱动异常带连接串/token
  /// 回显入库（与 AppLogger 落盘脱敏同款防御）。
  static void _landErrorCard(
    AppProvider provider,
    String sql,
    String summary,
    String? detail,
  ) {
    final payload = WorkbenchErrorCardPayload(
      sql: sql,
      summary: summary,
      detail: detail == null ? null : redactSecrets(detail),
    );
    provider.addAiMessage(_cardMessage(payload.toJson()));
  }

  /// gate #2 取消的消息流记录（design §6.2「消息流记已取消」；非错误态）。
  static void _landCancelledMessage(AppProvider provider, String content) {
    provider.addAiMessage(
      AiMessage(
        id: _generateMessageId(),
        isUser: false,
        content: content,
        timestamp: DateTime.now(),
        status: AiMessageStatus.cancelled,
      ),
    );
  }

  /// 卡消息（`toolResultData['workbench']` 挂载；toolName 'workbench' 无同名
  /// toolCall，不被 `_mergeToolMessages` 吞并——T12 遗留 1 注记）。
  static AiMessage _cardMessage(Map<String, dynamic> payloadJson) {
    return AiMessage(
      id: _generateMessageId(),
      isUser: false,
      content: '',
      timestamp: DateTime.now(),
      type: AiMessageType.toolResult,
      toolName: 'workbench',
      toolResultData: <String, dynamic>{'workbench': payloadJson},
      status: AiMessageStatus.completed,
    );
  }

  static String _generateMessageId() {
    return 'wb_exec_${DateTime.now().millisecondsSinceEpoch}_${_messageCounter++}';
  }

  /// 列名：首行键序（结果行的键插入序即列序；与卡展示列一致——行缺键显示
  /// NULL，与经典结果格式化同口径）。
  static List<String> _columnsOf(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const [];
    return rows.first.keys.toList(growable: false);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // agent 来源查询历史双写（经典 prefs 历史 + SQLite 历史）
  // ──────────────────────────────────────────────────────────────────────────

  /// 双写单条 agent 执行历史（工作台执行流 `onStatementResult` 与 agent
  /// 计划链执行通道共用）：
  ///
  /// ① 经典可见历史 `QueryHistoryProvider.addQueryHistory`（prefs 单 key，
  ///    source=agent——AI 执行在经典历史面板可辨识、可过滤）；
  /// ② SQLite 历史 `QueryHistoryService.recordQuery`（1000 条/90 天滚动）。
  ///
  /// 两路均 fire-and-forget（unawaited + 全量吞错）：历史写入失败只落
  /// AppLogger，不阻断执行 UI。EXPLAIN / INFORMATION_SCHEMA /
  /// PERFORMANCE_SCHEMA / SHOW 语句跳过（镜像拦截器
  /// `QueryExecutionInterceptor._shouldSkipRecording` 同口径）。
  ///
  /// 连接上下文口径：传入 [connectionId] 优先（锁定快照/执行目标），缺省
  /// 回落 currentServer；连接名/数据库类型只从该连接自身的 savedConnections
  /// 记录解析（显式 id 未命中时不借 currentServer 兜底，防张冠李戴）。
  static void recordAgentQueryHistory(
    AppProvider provider, {
    required String sql,
    String? connectionId,
    String? connectionName,
    String? database,
    required int durationMs,
    required int affectedRows,
    String? error,
    DatabaseType? databaseType,
  }) {
    final String trimmed = sql.trim();
    if (trimmed.isEmpty) return;
    if (_shouldSkipAgentHistoryRecording(trimmed)) return;

    final DbServer? server;
    if (connectionId != null) {
      DbServer? hit;
      for (final DbServer s in provider.savedConnections) {
        if (s.id == connectionId) {
          hit = s;
          break;
        }
      }
      server = hit;
    } else {
      server = provider.connection.currentServer;
    }
    final String effectiveConnectionId = connectionId ?? server?.id ?? '';
    final String? effectiveConnectionName = connectionName ?? server?.name;
    final DatabaseType? effectiveDatabaseType =
        databaseType ?? server?.type;

    unawaited(
      _recordClassicAgentHistory(
        provider,
        sql: trimmed,
        connectionId: effectiveConnectionId,
        connectionName: effectiveConnectionName,
        database: database,
        databaseType: effectiveDatabaseType,
        durationMs: durationMs,
        affectedRows: affectedRows,
        error: error,
      ),
    );
    unawaited(
      _recordSqliteAgentHistory(
        sql: trimmed,
        connectionId: effectiveConnectionId,
        connectionName: effectiveConnectionName,
        database: database,
        databaseType: effectiveDatabaseType,
        durationMs: durationMs,
        affectedRows: affectedRows,
        error: error,
      ),
    );
  }

  /// agent 计划链执行通道包装（`_planExecutionDeps` 三通道共用）：执行成功
  /// 记 done 历史、真执行失败记 failed 历史；门控控制流信号（语句未真正
  /// 执行）不记——经典先例 `AppProvider.executeCurrentQueryAndRecord` 对
  /// 四类控制流异常 rethrow 不记（app_provider.dart:1301-1314）：
  ///
  /// - DDL/DML 确认门（ConfirmationRequired）：确认后经 bypass 通道执行，
  ///   由 bypass 包装记录；取消 = skipped 天然不记；
  /// - DML 警告门（WarningRequired）：未执行；M6 high 步经 bypassDml 重
  ///   执行时由 bypass 包装记录；
  /// - 只读拦截（ReadOnlyBlocked）：永不执行。
  ///
  /// 耗时由本包装自测（stopwatch；runner 的 bypass 段计时口径在计划链无
  /// onStatementResult 出口，此为等价测量）。
  ///
  /// [onStatementExecuted]（B1，可选）：execution tab 计划链并联收集器——
  /// 真实执行的语句（成功/失败）同步产出一条 [StageExecutionRow]（与历史
  /// 双写同点同口径）；门控控制流信号（语句未真正执行）不产生收集行，
  /// skipped 由调用方从 plan.steps 终态读。
  static Future<SqlStatementOutcome> Function(String)
      withAgentQueryHistory(
    AppProvider provider, {
    String? connectionId,
    String? connectionName,
    String? databaseName,
    DatabaseType? databaseType,
    required Future<SqlStatementOutcome> Function(String) execute,
    void Function(StageExecutionRow row)? onStatementExecuted,
  }) {
    return (String statement) async {
      final Stopwatch stopwatch = Stopwatch()..start();
      try {
        final SqlStatementOutcome outcome = await execute(statement);
        stopwatch.stop();
        // 裁决：历史双写用真 affectedRows（detailed 通道引擎值）；读语句
        // 无影响行概念（引擎 null）回落行数——与拦截器 afterExecute 的
        // rowCount 口径一致（affectedRows ?? rows.length）。
        recordAgentQueryHistory(
          provider,
          sql: statement,
          connectionId: connectionId,
          connectionName: connectionName,
          database: databaseName,
          databaseType: databaseType,
          durationMs: stopwatch.elapsedMilliseconds,
          affectedRows: outcome.affectedRows ?? outcome.rows.length,
        );
        onStatementExecuted?.call(
          StageExecutionRow(
            sql: statement,
            status: StageExecutionStatus.done,
            // DDL 展示语义（裁决定案）：引擎报 0 时抑制 chip；DML 直显。
            affectedRows: _displayAffectedRows(
              statement,
              outcome.affectedRows,
            ),
            durationMs: stopwatch.elapsedMilliseconds,
          ),
        );
        return outcome;
      } on DdlConfirmationRequiredException {
        rethrow;
      } on DmlConfirmationRequiredException {
        rethrow;
      } on DmlWarningRequiredException {
        rethrow;
      } on ReadOnlyBlockedException {
        rethrow;
      } catch (e) {
        stopwatch.stop();
        recordAgentQueryHistory(
          provider,
          sql: statement,
          connectionId: connectionId,
          connectionName: connectionName,
          database: databaseName,
          databaseType: databaseType,
          durationMs: stopwatch.elapsedMilliseconds,
          affectedRows: 0,
          error: e.toString(),
        );
        onStatementExecuted?.call(
          StageExecutionRow(
            sql: statement,
            status: StageExecutionStatus.failed,
            durationMs: stopwatch.elapsedMilliseconds,
            // F5 对齐：错误全文入投影前脱敏。
            error: redactSecrets(e.toString()),
          ),
        );
        rethrow;
      }
    };
  }

  /// 经典历史写入（prefs；source=agent）。失败吞错（历史非关键路径）。
  static Future<void> _recordClassicAgentHistory(
    AppProvider provider, {
    required String sql,
    required String connectionId,
    required String? connectionName,
    required String? database,
    required DatabaseType? databaseType,
    required int durationMs,
    required int affectedRows,
    required String? error,
  }) async {
    try {
      await provider.queryHistory.addQueryHistory(
        sql: sql,
        connectionId: connectionId,
        connectionName: connectionName,
        executionTime: durationMs,
        affectedRows: affectedRows,
        error: error,
        database: database,
        databaseType: databaseType,
        source: QueryHistorySource.agent,
      );
    } on Object catch (e, stackTrace) {
      AppLogger.e(
        'WorkbenchExec',
        'agent query history (prefs) write failed: $e',
        e,
        stackTrace,
      );
    }
  }

  /// SQLite 历史写入（QueryHistoryService；initialize 幂等，未初始化时
  /// recordQuery 内部 `_ensureInitialized` 亦会自举）。失败吞错（历史非
  /// 关键路径，不阻断执行 UI）。
  static Future<void> _recordSqliteAgentHistory({
    required String sql,
    required String connectionId,
    required String? connectionName,
    required String? database,
    required DatabaseType? databaseType,
    required int durationMs,
    required int affectedRows,
    required String? error,
  }) async {
    try {
      final QueryHistoryService service = QueryHistoryService();
      await service.initialize(); // 幂等（_initialized 短路）
      await service.recordQuery(
        sqlStatement: sql,
        connectionId: connectionId,
        connectionName: connectionName,
        databaseType: databaseType?.name ?? '',
        databaseName: database,
        executionTimeMs: durationMs,
        rowCount: affectedRows,
        isSuccess: error == null,
        errorMessage: error,
      );
    } on Object catch (e, stackTrace) {
      AppLogger.e(
        'WorkbenchExec',
        'agent query history (sqlite) write failed: $e',
        e,
        stackTrace,
      );
    }
  }

  /// 跳过记录判定（镜像 `QueryExecutionInterceptor._shouldSkipRecording`，
  /// query_execution_interceptor.dart:259-266——原判定为服务私有，取共用
  /// 需改服务面，镜像实现为任务书允许的自决项）。
  static bool _shouldSkipAgentHistoryRecording(String sql) {
    final String normalized = sql.trim().toUpperCase();
    if (normalized.startsWith('EXPLAIN')) return true;
    if (normalized.contains('INFORMATION_SCHEMA')) return true;
    if (normalized.contains('PERFORMANCE_SCHEMA')) return true;
    if (normalized.startsWith('SHOW')) return true;
    return false;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 上下文不可用出口（AC9.4 + 设计「去设置连接」出口）
  // ──────────────────────────────────────────────────────────────────────────

  /// 错误卡落地后的即时出口：SnackBar 动作打开既有 [ConnectionDialog]（与
  /// T11 芯片未设置态 `_openConnectionSetup` 同一对话框）。
  static void _showSetupConnectionExit(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.workbenchErrorNoContext),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: l10n.workbenchErrorSetupConnection,
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (dialogContext) => const ConnectionDialog(),
            );
          },
        ),
      ),
    );
  }
}
