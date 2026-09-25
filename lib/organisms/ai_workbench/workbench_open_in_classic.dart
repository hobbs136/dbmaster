//! 工作台互跳出口（T13，design-ai-workbench §6.3 / AC7.1 / AC7.3）。
//!
//! 「在经典中打开」/「在网格中打开」共用出口：SQL 送经典模式**新 tab**
//! （`openQueryTab` 每次新开，不覆盖既有 tab）→ 退出工作台全屏让用户看到
//! 落点 → SnackBar 反馈。结果卡「在网格中打开」同语义（完整结果集不入卡，
//! design §5.2——SQL 送新 tab 后由经典管线取得全量）。
//!
//! 目标连接/库：执行时 `effectiveWorkbenchContext` 复核（与执行编排同一
//! 判据，锁定快照优先）；上下文不完整时回退「新空 tab + 写 SQL」（经典
//! `_openInNewQuery` 同款兜底）。AC7.3：目标 tab 的 SQL = 用户送出的内容
//! （参数透传，不加工）。

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../services/ai/workbench_context_resolver.dart';

/// 工作台 → 经典 互跳出口。
class WorkbenchOpenInClassic {
  WorkbenchOpenInClassic._();

  /// 在经典模式新 tab 中打开 [sql]（不覆盖既有 tab，AC7.1），随后退出
  /// 工作台全屏（z2 盖住经典界面，需切回让落点可见）。
  static Future<void> open(BuildContext context, String sql) async {
    final provider = context.read<AppProvider>();
    final l10n = AppLocalizations.of(context)!;

    final ctx = effectiveWorkbenchContext(
      provider.aiPanel.aiConversationService.currentSession,
      provider,
    );
    final connectionId = ctx.connectionId;
    final databaseName = ctx.databaseName;

    if (connectionId != null && databaseName != null) {
      await provider.openQueryTab(connectionId, databaseName, sql: sql);
    } else {
      // 上下文不完整（无连接或无库）：新空 tab 兜底承载 SQL（经典同款）。
      await provider.addNewTab();
      provider.updateTabSql(provider.activeTabIndex, sql);
    }

    provider.aiPanel.setAiPanelFullscreen(false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.aiPanelOpenInNewQuery),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}
