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
import '../../services/readonly_guard.dart';
import '../../organisms/connection/error_boundary.dart';
import '../../organisms/dialogs/dml_confirm_dialog.dart';
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
