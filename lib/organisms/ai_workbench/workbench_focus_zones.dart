//! AI 工作台 F6 六区轮转的焦点区注册表（v2 结果面板第一批 A5，任务书 §6.7）。
//!
//! 六区枚举序 = F6 正向轮转序（Shift+F6 逆向）：活动条 → rail 内容页 →
//! 对话列 → 舞台 tab 条 → 舞台内容 → 产物条。各区由所属组件在自身子树
//! 挂载时向壳级注册表登记「聚焦入口」回调、卸载时注销（挂载/卸载随子树
//! 生命周期；壳 Offstage 隐藏、舞台收起不入树、rail 收窄无内容页等场景
//! 的区缺席由「未注册即跳过」统一承载——轮转序列按注册态动态跳过）。
//!
//! 纯 Dart、零 IO、零持久化：本文件不 import 任何库，注册表只是回调的
//! 键值容器；焦点挪移由各区入口回调自行实现（工作台各组件内聚，不在此
//! 引入 widgets 依赖）。

/// F6/Shift+F6 轮转的工作台焦点区。
///
/// 枚举序即轮转序（v2 §8-6：六区循环无死区）；未注册的区（舞台收起 /
/// rail 收窄 / 区内无可聚焦元素导致入口失败）在轮转时被跳过。
enum WorkbenchFocusZone {
  /// 活动条（rail 最左 44 图标条；注册方 = WorkbenchActivityBar）。
  activityBar,

  /// rail 内容页（展开态 196 列；注册方 = WorkbenchSessionRail，收窄态
  /// 不注册）。
  railContentPage,

  /// 对话列（输入框聚焦入口；注册方 = AiWorkbenchShell 自身）。
  chatColumn,

  /// 舞台 tab 条（入口 = 聚焦激活 tab；注册方 = WorkbenchStage，舞台不入
  /// 树时未注册）。
  stageTabBar,

  /// 舞台内容区（入口 = 激活 tab 内容首个可聚焦元素；注册方 =
  /// WorkbenchStage，舞台不入树时未注册）。
  stageContent,

  /// 产物条（入口 = 聚焦首个条目；注册方 = WorkbenchArtifactStrip，条恒在）。
  artifactStrip,
}

/// 区聚焦入口回调：把键盘焦点移入本区，返回是否成功聚焦。
///
/// 返回 false（区内暂无可聚焦元素，如空舞台的 tab 条 / 零条目的产物条）
/// 时，轮转算法继续尝试下一区（无死区：入口失败不阻断循环）。
typedef WorkbenchZoneFocusEntry = bool Function();

/// 壳内焦点区注册表：区 → 聚焦入口回调。
///
/// 归 [AiWorkbenchShell] State 持有（F6 轮转宿主），经构造参数下发各组件；
/// 注册/注销随各区组件子树生命周期成对发生。组件测试可直接自建实例断言
/// 注册态与入口行为。
class WorkbenchFocusZoneRegistry {
  final Map<WorkbenchFocusZone, WorkbenchZoneFocusEntry> _entries =
      <WorkbenchFocusZone, WorkbenchZoneFocusEntry>{};

  /// 区是否已登记聚焦入口。
  bool isRegistered(WorkbenchFocusZone zone) => _entries.containsKey(zone);

  /// 已登记的区集合（只读视图；测试与轮转诊断用）。
  Set<WorkbenchFocusZone> get registeredZones =>
      Set<WorkbenchFocusZone>.unmodifiable(_entries.keys);

  /// 登记区的聚焦入口（同区重复登记以最后一次为准）。
  void register(WorkbenchFocusZone zone, WorkbenchZoneFocusEntry entry) {
    _entries[zone] = entry;
  }

  /// 注销区聚焦入口。**身份比对**：仅当当前登记项就是 [entry] 时移除——
  /// 同区可能由先后重挂载的组件实例登记（如 rail 折叠↔展开时活动条重挂），
  /// 帧内新实例先 initState、旧实例后 dispose，身份比对保证晚卸载的旧
  /// 实例不会清掉新实例的登记。
  void unregister(WorkbenchFocusZone zone, WorkbenchZoneFocusEntry entry) {
    if (identical(_entries[zone], entry)) {
      _entries.remove(zone);
    }
  }

  /// 调用区聚焦入口；未登记返回 false（轮转按未注册跳过）。
  bool focus(WorkbenchFocusZone zone) => _entries[zone]?.call() ?? false;
}
