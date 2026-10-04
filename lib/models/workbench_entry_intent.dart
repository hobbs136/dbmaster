/// 工作台入口意图（2b.4 / 任务书 §6.5 R7）：pending intent 机制的数据件。
///
/// 由 [AiPanelProvider.requestWorkbenchEntry] 挂载、工作台壳 post-frame 消费
/// 后经 [AiPanelProvider.consumeWorkbenchEntryIntent] 清除。经典 AI dock 路径
/// 零感知——intent 只挂在 AiPanelProvider，不新建面板体系。
///
/// [id] 单调自增 = 壳侧防重入锚（同一 intent 只消费一次；被后续请求覆盖的
/// 旧 intent 在消费回调内按 id 判废，不会误清新 intent）。
library;

/// 工作台入口要推开的舞台 tab 目标。
enum WorkbenchEntryTabTarget {
  /// 不开任何 tab（仅开工作台/预填 prompt；表/库钩子产物走各自既有链）。
  none,

  /// 实例观察 tab（`WorkbenchStageController.openObserve`，2b.1）。
  observe,

  /// 保存的查询 tab（`openSavedQueries`，先行批 A4 抽屉舞台同源）。
  savedQueries,

  /// 查询历史 tab（`openHistory`，先行批 A3）。
  history,
}

/// 一次「进入工作台 + 可选预填 + 可选推 tab」的待办意图。
class WorkbenchEntryIntent {
  /// 防重入锚：每次请求自增，消费后同 id 不再二次消费。
  final int id;

  /// 预填进对话列输入框的 prompt；null/空 = 不预填（预填**不自动发送**）。
  final String? prompt;

  /// 要推开的舞台 tab 目标。
  final WorkbenchEntryTabTarget tabTarget;

  const WorkbenchEntryIntent({
    required this.id,
    this.prompt,
    this.tabTarget = WorkbenchEntryTabTarget.none,
  });
}
