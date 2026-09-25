/// Agent 会话放行账本（tasks-ai-agent.md T06 / design-ai-agent.md D12）。
///
/// AC8.5 / AC9.3 的执法点：用户在 L0.5 确认卡 / L1 计划卡勾选「本会话内
/// 允许」（GateCardResult.approvedForSession）后，对应 connectionId 记入
/// 相应集合：
/// - L0.5 集：`AgentGate.evaluate` 判定序 ⑤ 消费——`confirm(l05)` 候选且
///   账本命中该连接 → `allow`（审计记 `allowed_session`，design §4.2）；
/// - L1 集：A2 计划链路消费（T28：免卡仍逐语句审计，AC9.3）。
///
/// 账本跨 run 保留（同一会话内多次运行共享放行）。
///
/// 失效三路径（D12）：会话切换 / lockWorkbenchContext 变更 → [clearAll]
/// （清空触发方在 runner / shell 合龙任务 T14 接线，本类只提供入口）；
/// 应用重启 = 进程内对象消亡——内存态不持久化（沿 M1 `_allowedWriteServers`
/// 先例，`ai_workbench_shell.dart:50`）。
///
/// L2 无会话放行 = 本类无 L2 集合（AC10.3：结构上不可表达——DDL 双门必
/// 逐次过，design §4.2 末段）。
///
/// 纯内存结构：零 IO、零 UI 依赖；services 层禁 import material。
library;

import 'dart:collection' show UnmodifiableSetView;

/// 会话放行账本：L0.5 与 L1 各一个 `Set<String>`（key = connectionId）。
class AgentPermissionLedger {
  final Set<String> _l05Allowed = <String>{};
  final Set<String> _l1Allowed = <String>{};

  /// L0.5 会话放行连接集（只读视图；查询形态 `l05Allowed.contains(id)`，
  /// design §4.2 ⑤ 原文用法）。变更只走 [allowL05] / [clearAll]。
  Set<String> get l05Allowed => UnmodifiableSetView<String>(_l05Allowed);

  /// L1 会话放行连接集（只读视图）。变更只走 [allowL1] / [clearAll]。
  Set<String> get l1Allowed => UnmodifiableSetView<String>(_l1Allowed);

  /// 记录 L0.5 会话放行（确认卡「本会话内允许」决策落地）。空串 =
  /// 无上下文占位（T07 审计语义），不可成为放行键——忽略。
  void allowL05(String connectionId) {
    if (connectionId.isEmpty) return;
    _l05Allowed.add(connectionId);
  }

  /// 记录 L1 会话放行（计划卡「本会话内允许」决策落地）。空串忽略，
  /// 同 [allowL05]。
  void allowL1(String connectionId) {
    if (connectionId.isEmpty) return;
    _l1Allowed.add(connectionId);
  }

  /// 全量清空两集（会话切换 / lockWorkbenchContext 变更两个失效路径共用
  /// 入口；触发方在 runner / shell，T14 接线）。应用重启路径 = 进程内对象
  /// 消亡，无需调用。
  void clearAll() {
    _l05Allowed.clear();
    _l1Allowed.clear();
  }
}
