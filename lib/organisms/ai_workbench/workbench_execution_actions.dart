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
//! 5. **执行**：只经 `AppProvider.executeQuery` facade（既有管线：DDL/DML
//!    拦截、行限制、embedded 网关路由、只读连接检查全部继承，M1 不增不减）。
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
//! bypass 取道 `provider.dbService`（经 AppProvider facade 访问，design §6.2
//! 原文「dbService.executeQueryBypassDdl（既有绕行，同经典）」；不经
//! `executeQueryBypassDdlAndUpdateResults`——那会写经典 activeTab 结果，
//! 违反 R7 工作台不写 tab 语义）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_message_type.dart';
import '../../models/database_models.dart' show AiMessage, DatabaseType;
import '../../models/dml_risk_models.dart';
import '../../providers/app_provider.dart';
import '../../services/ai/ai_tool_classifier.dart';
import '../../services/ai/workbench_context_resolver.dart';
import '../../services/database_service.dart';
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

/// 工作台 SQL 执行编排（SQL 卡「执行」/ 错误卡「重试」/ 消息级执行共用入口）。
///
/// [allowedWriteServers] 由宿主（shell State）持有并传入——会话放行集随
/// Offstage 保活跨模式存活、应用重启重置（design §6.5，内存语义）。
class WorkbenchExecutionActions {
  WorkbenchExecutionActions._();

  static int _messageCounter = 0;

  /// 执行入口：上下文复核 → 空白守卫 → 写门禁 → 逐条执行逐条落卡。
  static Future<void> run(
    BuildContext context,
    String sql, {
    required Set<String> allowedWriteServers,
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

    // ③④⑤ 拆分 + 两遍法写门禁 + 逐语句执行/双异常路由 → 共享骨架
    //    （T20 `SqlStatementGateRunner`，perStatement 写确认模式）。
    //    对话框/落卡经回调注入，语义与提取前逐点等价（AC6.1/6.2/6.4/
    //    9.5、F1 fail-closed、gate #2 双门）。
    final result = await const SqlStatementGateRunner().run(
      sql: sql,
      deps: SqlGateRunDeps(
        execute: (statement) => provider.executeQuery(
          statement,
          connectionId: ctx.connectionId,
          database: ctx.databaseName,
        ),
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
        executeBypassDdl: (statement) => provider.dbService.executeQueryBypassDdl(
          statement,
          connectionId: ctx.connectionId,
          database: ctx.databaseName,
        ),
        executeBypassDml: (statement) => provider.dbService.executeQueryBypassDml(
          statement,
          connectionId: ctx.connectionId,
          database: ctx.databaseName,
        ),
        // 每语句执行前的宿主存活探针（原逐语句循环头 mounted 检查）。
        shouldContinue: () => context.mounted,
        onStatementResult: (outcome) {
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
      // columnTypes 来自 _QueryExecutionResult——executeQuery facade 只返回
      // 行数据，此层未提供（payload 契约允许 null）。
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
