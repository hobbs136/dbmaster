//! AI 工作台「运行中改选上下文」提示（T6，D15 快照契约的显示面）。
//!
//! 契约背景：agent run 启动即对生效上下文做一次快照（design-ai-agent D15），
//! run 进行中用户改选上下文（选择即锁定，R2）只影响**下一次** run，进行中的
//! run 仍用启动时快照——但改选即时生效的观感会误导用户，故在改选动作点
//! （picker 两提交点 + 芯片解锁）run 活跃时以 info snackbar 提示。

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../organisms/connection/error_boundary.dart';
import '../../providers/ai_panel_provider.dart';

/// 运行中改选上下文的提示器（无状态静态出口）。
class WorkbenchContextChangeHint {
  const WorkbenchContextChangeHint._();

  /// [aiPanel] 的 agent run 活跃（isRunning ⇔ status ∈ {running,
  /// awaitingUser, stopping}）时，展示「改选将在下次运行生效」info snackbar；
  /// 未运行时零副作用。重复触发先清队列再展示（覆盖而非排队叠加，不阻断）。
  static void showIfRunActive(BuildContext context, AiPanelProvider aiPanel) {
    if (!aiPanel.agentRunner.isRunning) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    AppErrorHandler.showInfoSnackBar(
      context,
      AppLocalizations.of(context)!.workbenchContextChangeWhileRunning,
    );
  }
}
