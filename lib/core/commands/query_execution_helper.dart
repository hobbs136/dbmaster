// ============================================================================
// QueryExecutionHelper - 查询执行编排单一真相源（spec 040 Phase 2.1）
// ----------------------------------------------------------------------------
// 集中 DML/DDL 确认对话框 + 只读拦截 + bypass 重执的编排，供命令面板执行、全局
// F5 兜底等调用点复用。Provider 不能持有 BuildContext（Provider 禁 import
// material），故对话框编排须在 widget 层；本 helper 为静态工具，可自由用 context。
//
// 编辑器 _executeQuery 因有 DmlWarning banner + 多语句 DDL + 错误历史等独有流程，
// 保留其自身实现（不强制走本 helper，避免行为不等价；见 spec 040 风险项）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart' show DatabaseType;
import '../../models/dml_risk_models.dart';
import '../../services/database_service.dart';
import '../../services/query_execution_interceptor.dart'
    show ProductionGuardRequiredException, QueryExecutionInterceptor;
import '../../services/readonly_guard.dart';
import '../../organisms/connection/error_boundary.dart';
import '../../organisms/dialogs/dml_confirm_dialog.dart';
import '../../organisms/dialogs/production_guard_dialog.dart';
import '../../organisms/ai_panel/ddl_confirm_dialog.dart';
import '../../providers/app_provider.dart';
import '../../utils/app_logger.dart';

class QueryExecutionHelper {
  QueryExecutionHelper._();

  /// 执行当前活动标签页的查询，统一处理 DML/DDL 确认与只读拦截。
  ///
  /// 流程：[AppProvider.executeCurrentQueryAndRecord] →
  /// - [DmlConfirmationRequiredException]：弹 [DmlConfirmDialog]，确认则 bypass 重执，
  ///   取消则 [DatabaseService.interceptor.logDmlBlocked]（审计）；
  /// - [ProductionGuardRequiredException]：弹生产守卫
  ///   `showProductionGuardDialog`（B-07 production 分流，L1/L2 分级 +
  ///   AI 备份胶水），确认则按语句类型走 DDL/DML bypass 重执，取消则审计；
  /// - [DdlConfirmationRequiredException]：弹 [DdlConfirmDialog]，确认则 bypass 重执；
  /// - [ReadOnlyBlockedException]：本地化 warning snackbar；
  /// - 其它异常：debug 日志（不静默）。
  static Future<void> executeWithConfirm(BuildContext context) async {
    final provider = context.read<AppProvider>();
    final tab = provider.activeTab;
    if (tab == null || tab.sql.isEmpty) return;

    try {
      await provider.executeCurrentQueryAndRecord();
    } on DmlConfirmationRequiredException catch (e) {
      if (!context.mounted) return;
      final activeTab = provider.activeTab;
      if (activeTab == null) return;
      final confirmResult = await DmlConfirmDialog.show(
        context,
        analysis: e.analysis,
        statements: e.statements,
        dbType: activeTab.databaseType ?? DatabaseType.mysql,
      );
      if (confirmResult == DmlConfirmResult.confirm && context.mounted) {
        try {
          await provider.executeQueryBypassDmlAndUpdateResults(
            activeTab.sql,
            connectionId: activeTab.connectionId,
            database: activeTab.databaseName,
            sessionId: activeTab.sessionId,
          );
        } catch (execError) {
          AppLogger.d(
            'QueryExecHelper',
            'executeWithConfirm: DML bypass execution failed: $execError',
          );
        }
      } else {
        // 取消：记录拦截决策（审计）
        provider.dbService.interceptor.logDmlBlocked(
          sql: e.sql,
          connectionId: provider.connection.currentServer?.id ?? '',
          riskLevel: e.analysis.riskLevel,
          decision: AuditDecision.cancelled,
        );
      }
    } on ProductionGuardRequiredException catch (e) {
      // B-07 production 分流（UI35-441）：production 连接的阻断级 DML →
      // 生产守卫弹窗（L1/L2 分级），非既有 DML 确认门。镜像上方 DML 分支
      // 结构：guard true → bypass 重执（按语句类型选 DDL/DML bypass，与
      // 既有两分支选择逻辑一致）；false（取消/Esc/AI 分流）→ 审计落
      // logDmlBlocked（与既有 DML 取消路径同一审计出口）。
      if (!context.mounted) return;
      final activeTab = provider.activeTab;
      if (activeTab == null) return;
      final l10n = AppLocalizations.of(context)!;
      final connectionId = provider.connection.currentServer?.id ?? '';
      // estimatedRows 锁面考量（自决记录）：守卫 seam 为同步检查，消费方
      // 无 DatabaseAdapter 句柄（DatabaseService 未公开 adapter 访问面，
      // 不为此新开公开 API）；且 getEstimatedRowCount 的 SQLite 回落是
      // 500ms 超时 COUNT(*)——在守卫要保护的表上先放大读锁面。按 seam
      // 契约回落 null（未知行数，禁 0 冒充）。
      final confirmed = await showProductionGuardDialog(
        context,
        connectionId: connectionId,
        level: e.isL1Destructive
            ? ProductionGuardLevel.l1Destructive
            : ProductionGuardLevel.l2UnboundedWrite,
        sqlPreview: e.sql,
        targetObjectName: e.targetObjectName,
        estimatedRows: null,
        onAiBackup: () {
          // AI 备份胶水（沿 sidebar_tree T9-C 同款）：弹窗自理关闭后开
          // 经典 dock + 预填 prodGuardAiBackupPrompt({object})；不自动
          // 发送、不校验 API key、不 recordAiUsage。
          provider.aiPanel.openAiPanel();
          provider.aiPanel.requestComposerPrefill(
            l10n.prodGuardAiBackupPrompt(e.targetObjectName),
          );
        },
      );
      if (confirmed && context.mounted) {
        try {
          if (QueryExecutionInterceptor.isDdlStatement(activeTab.sql)) {
            await provider.executeQueryBypassDdlAndUpdateResults(
              activeTab.sql,
              connectionId: activeTab.connectionId,
              database: activeTab.databaseName,
              sessionId: activeTab.sessionId,
            );
          } else {
            await provider.executeQueryBypassDmlAndUpdateResults(
              activeTab.sql,
              connectionId: activeTab.connectionId,
              database: activeTab.databaseName,
              sessionId: activeTab.sessionId,
            );
          }
        } catch (execError) {
          AppLogger.d(
            'QueryExecHelper',
            'executeWithConfirm: production guard bypass execution failed: '
                '$execError',
          );
        }
      } else {
        // 取消/Esc/AI 分流（操作未执行）：记录拦截决策（审计，不旁路）。
        provider.dbService.interceptor.logDmlBlocked(
          sql: e.sql,
          connectionId: connectionId,
          riskLevel: DmlRiskLevel.critical,
          decision: AuditDecision.cancelled,
        );
      }
    } on DdlConfirmationRequiredException catch (e) {
      if (!context.mounted) return;
      final result = await showDialog<DdlConfirmResult>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) =>
            DdlConfirmDialog(sql: e.sql, impactReport: e.impactReport),
      );
      if (result == DdlConfirmResult.execute && context.mounted) {
        final activeTab = provider.activeTab;
        if (activeTab == null) return;
        try {
          await provider.executeQueryBypassDdlAndUpdateResults(
            activeTab.sql,
            connectionId: activeTab.connectionId,
            database: activeTab.databaseName,
            sessionId: activeTab.sessionId,
          );
        } catch (execError) {
          AppLogger.d(
            'QueryExecHelper',
            'executeWithConfirm: DDL bypass execution failed: $execError',
          );
        }
      }
    } on ReadOnlyBlockedException catch (_) {
      if (!context.mounted) return;
      AppErrorHandler.showWarningSnackBar(
        context,
        AppLocalizations.of(context)!.readOnlyModeBlocked,
      );
    } catch (e) {
      AppLogger.d('QueryExecHelper', 'executeWithConfirm failed: $e');
    }
  }
}
