//! AI 工作台舞台（T24，ui 规格 design-ai-agent-ui.md §5 面五）。
//!
//! A2 净新增结构：tab 体系（增删切 / 关闭 / pin 标记 / dirty 标记 /
//! tab 条 32 / tab 标签上限 200）+ 内容槽（网格 / 结构卡 / 编辑器槽 /
//! 图表 / 会话列表）+ 空态三元素 + 常驻开合控制语义（[WorkbenchStageController.stageVisible]，
//! 由 T27 shell 消费布局，本组件自身不因可见性消失——是否入树由宿主决定）。
//!
//! 单一事实源（ui 规格 §6.3 判定）：[WorkbenchStageController] 持有 tab 集合 /
//! pinned 标记 / 激活态 / 舞台可见性；舞台 tab 条与产物条（T25）是同一集合的
//! 两个投影，产物条不复制数据。状态宿主为 ChangeNotifier（不新建 Provider，
//! T27 shell 装配时创建并注入）。
//!
//! 数值逐字 ui 规格 §5：tab 条 32（底 bgSecondary + 底部 1px divider）/
//! tab 项 [图标 14 + 6 + 标签 12 ellipsis + 6 + 关闭 12]、内边距 h 10、上限宽
//! 200（不设最小宽）/ 激活底 primaryContainer + 200ms 过渡 / 非激活 textSecondary
//! + hover bgTertiary / 未保存 6px accentBlue 点（标签前）/ 内容区 bgPrimary +
//! padding space3 + 无卡框。四类 tab：网格只读消费 result_renderer_plugin 注册表
//! （零契约改动）；结构卡 describe 四件（列/索引/外键/DDL）；编辑器槽载入
//! ReSqlEditor 不自动执行（AC5.2）+ 未保存点 + 关闭确认（AC5.5）；图表复用
//! ChartView 语义，列型不适配 → 内联错误 + [在经典中打开] 出口不弹窗（AC5.3）。
//! v2 先行批扩展 kind：sessionList / history / savedQueries（抽屉单例 tab，
//! A2–A4）+ execution（B1 写入/DDL 执行结果摘要，纯只读投影）——图标/标签
//! 映射在 `workbench_stage_tab_visuals.dart` 单源注册表。
//! 2b 批：observe（2b.1 实例观察）+ structure×Mongo（2b.2b——structure kind
//! 增加 Mongo 集合分支：数据载体 [StageMongoStructureData] → 内容件
//! [WorkbenchMongoSchemaView]，SQL 表分支（[StageStructureData]）原样）+
//! optimization（2b.3 查询优化三层内容：数据载体 [StageOptimizationData] →
//! [_StageOptimizationContent]（SQL 上下文头 + [QueryPlanVisualizer] 零改动
//! 复用），推送源 = agent explain_plan L0 通道旁挂推送，R6）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../models/execution_result.dart';
import '../../models/query_optimizer/execution_plan.dart'
    show PerformanceReport;
import '../../models/result_data_shape.dart';
import '../../models/result_filter.dart'
    show ColumnDataType, ResultFilterService;
import '../../models/sql_statement.dart';
import '../../molecules/compact_popup_menu_item.dart';
import '../../plugins/bootstrap.dart' show defaultPluginRegistry;
import '../../plugins/plugin_registry.dart';
import '../../plugins/result_renderer_plugin.dart' show ResultRenderContext;
import '../../services/ai/agent/agent_ui_port.dart' show AgentResultRef;
import '../../theme/app_colors.dart';
import '../editor/re_sql_editor.dart';
import '../editor/re_sql_editor_controller.dart';
import '../query_optimizer/query_plan_visualizer.dart';
import '../results/chart_view.dart';
import 'workbench_focus_zones.dart';
import 'workbench_mongo_schema_view.dart';
import 'workbench_observe_content.dart';
import 'workbench_query_history_view.dart';
import 'workbench_saved_query_list_view.dart';
import 'workbench_session_list_view.dart';
import 'workbench_stage_tab_visuals.dart';

/// 舞台 tab 类型（§5.2）。
///
/// 类型 → 图标/标签映射的唯一事实源 = [WorkbenchStageTabKindVisuals]
/// （workbench_stage_tab_visuals.dart，C1 注册化）；本枚举只定义类型集合。
/// `sessionList`（v2 A2，R5 补录）：会话列表单例 tab（收窄态活动条点击
/// 开启），内容 = 共享 SessionListView 全宽形态。
/// `history`（v2 A3）：查询历史单例 tab（收窄态活动条历史图标点击开启），
/// 内容 = 共享 QueryHistoryListView 全宽形态（载入绑 openEditorSlot）。
/// `savedQueries`（v2 A4）：保存的查询单例 tab（收窄态活动条保存的查询
/// 图标点击开启），内容 = 共享 SavedQueryListView 全宽形态（本地段，
/// 载入绑 openEditorSlot）。
/// `execution`（v2 B1）：写入/DDL 批次执行结果摘要 tab（手动卡执行批
/// 与 agent 计划链两通道推送），内容 = [_StageExecutionContent] 逐语句
/// 状态投影（纯只读，零动作按钮）。
/// `observe`（2b.1）：实例观察 tab——单例跟随锁定连接（R1：连接快照不进
/// tab 数据，内容每次 build 从 effectiveWorkbenchContext 派生）；内容 =
/// [WorkbenchObserveContent]（左段导航按引擎出段 + 右只读内容 + 手动刷新
/// + 时间戳恒显，零写手势）。
/// `optimization`（2b.3）：查询优化三层内容 tab（计划树 + 瓶颈 + 索引推荐
/// + 重写建议，[QueryPlanVisualizer] 零改动复用承载）+ SQL 上下文头。
/// 去重键 = 原 SQL 精确串（R6：同 SQL 重解释复用刷新；不同连接同 SQL 复用
/// 同 tab 属 MVP 已知语义）。推送源 = agent `explain_plan` 只读通道旁挂
/// 推送；「应用此索引」= 填编辑器槽不执行（零自动写）。
enum WorkbenchStageTabKind {
  grid,
  structure,
  editor,
  chart,
  sessionList,
  history,
  savedQueries,
  execution,
  observe,
  optimization,
}

/// 结构卡内容（describe_table 四件：列 / 索引 / 外键 / DDL）。
///
/// 值对象由 T27 port 实现（`showTableStructure`）从 adapter 取数后组装；
/// 舞台只读消费，不触发任何数据库访问。
class StageStructureData {
  /// 常量构造；字段不可变。
  const StageStructureData({
    required this.tableName,
    required this.columns,
    required this.indexes,
    required this.foreignKeys,
    this.ddl,
  });

  /// 表名（tab 标签默认值）。
  final String tableName;

  /// 列定义（describe 四件之一）。
  final List<DbColumn> columns;

  /// 索引定义（describe 四件之二）。
  final List<DbIndex> indexes;

  /// 外键定义（describe 四件之三）。
  final List<ForeignKey> foreignKeys;

  /// CREATE TABLE 语句（describe 四件之四；null = 无 DDL 段）。
  final String? ddl;
}

/// 结构卡 Mongo 集合分支数据载体（2b.2b）：{ connectionId, databaseName,
/// collectionName }（不可变值对象，沿 [StageStructureData] 先例）。
///
/// 本批无生产入口（入口通道 = m3「mongo 读三件套」工具/后续批次）；测试
/// 路径直开。舞台只读消费，schema 加载由内容件 [WorkbenchMongoSchemaView]
/// 经 AppProvider per-connection facade 自行完成（R5 接缝）。
class StageMongoStructureData {
  /// 常量构造；字段不可变。
  const StageMongoStructureData({
    required this.connectionId,
    required this.databaseName,
    required this.collectionName,
  });

  /// Mongo 连接 id（去重键之一；per-connection facade 的路由锚）。
  final String connectionId;

  /// 集合所在库名（透传 `loadMongoDBSchema`；facade 按连接+集合键缓存）。
  final String databaseName;

  /// 集合名（去重键之一 + tab 标签默认值）。
  final String collectionName;
}

/// execution tab 逐语句行状态（B1）：投影自执行通道结局
/// （`SqlStatementStatus` / 计划步终态），本枚举是舞台侧的展示语义。
enum StageExecutionStatus {
  /// 执行成功。
  done,

  /// 执行失败（错误全文随行携带，行尾「详情」可展开）。
  failed,

  /// 未执行（中止边界后的余下语句 / 计划门控跳过）。
  skipped,
}

/// execution tab 单语句行（不可变值对象；B1）。
///
/// [affectedRows] / [durationMs] 可空：执行通道数据缺失时降级为「状态 +
/// SQL」无指标行（任务书 §6.8 防御条款）——facade `executeQuery` 通道对
/// 写语句不回传行（网关 affectedRows 在公共 facade 解包层丢失），空行集
/// 视为行数缺失，不显示可能误导的 0。
class StageExecutionRow {
  /// 常量构造；字段不可变。
  const StageExecutionRow({
    required this.sql,
    required this.status,
    this.affectedRows,
    this.durationMs,
    this.error,
  });

  /// 语句文本（拆分产物，已 trim）。
  final String sql;

  /// 行状态。
  final StageExecutionStatus status;

  /// 影响行数（null = 数据缺失，降级不显示）。
  final int? affectedRows;

  /// 执行耗时（毫秒；null = 数据缺失——如门控取消未真正执行的语句）。
  final int? durationMs;

  /// 失败错误全文（仅 failed 非 null；入投影前已过 `redactSecrets` 脱敏，
  /// F5 对齐——防驱动异常带连接串/token 上屏）。
  final String? error;
}

/// execution tab 数据载荷（B1，R3/R4）：一批写入/DDL 语句的执行结果投影。
///
/// 推送条件（R3）：批内含 ≥1 写/DDL 语句（`AiToolClassifier.isWriteSql`
/// 口径）且有真实执行才组装——纯只读批 / 拆分失败 / 全取消（零执行）不推
/// （永不空开，v1 §3.7）。[rows] 恒为批内**全部**语句（含只读与 skipped，
/// 时间序 = 执行序；部分失败的上下文需要全批语句行）。
class StageExecutionData {
  /// 常量构造；字段不可变。
  const StageExecutionData({
    required this.tabKey,
    required this.title,
    required this.rows,
  });

  /// 手动卡执行批的单例去重键（R4：无 runId/planId 可锚，单例键避免每次
  /// 执行累积新 tab；重复执行复用刷新同一 tab）。
  static const String manualTabKey = 'manual';

  /// 去重键（R4）：agent 计划链 = planId（重跑同计划刷新同 tab）；手动卡
  /// 执行 = [manualTabKey]。
  final String tabKey;

  /// tab 标题（含时间戳；复用刷新时以新值为准）。
  final String title;

  /// 批内全部语句行（含只读与 skipped；时间序 = 执行序）。
  final List<StageExecutionRow> rows;

  /// 含时间戳的 tab 标题（R4「标题含时间戳」口径：`HH:MM:SS` 本地时，
  /// 两通道共用同一格式）。
  static String titleWithTimestamp(String baseLabel, DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '$baseLabel ${two(time.hour)}:${two(time.minute)}:'
        '${two(time.second)}';
  }
}

/// optimization tab 数据载荷（2b.3，R6）：{ sql, PerformanceReport report }。
///
/// 不可变值对象（沿 [StageStructureData] 先例）；由 agent executor 的
/// explain_plan 旁挂推送组装（`QueryOptimizerService.analyzeQuery`）后经
/// AgentUiPort 加性方法推入。舞台只读消费：report 纯展示渲染（内容槽
/// [QueryPlanVisualizer] 零改动复用），**零执行语义**——「应用此索引」
/// 只把 DDL 填进编辑器槽（[WorkbenchStageController.openEditorSlot]），
/// 不触发任何语句执行（任务书 §6.4 一票否决项）。
class StageOptimizationData {
  /// 常量构造；字段不可变。
  const StageOptimizationData({required this.sql, required this.report});

  /// 原始 SQL（去重键 = 精确串，R6：同 SQL 重解释复用刷新）。
  final String sql;

  /// 组装完成的性能分析报告（计划树/瓶颈/索引推荐/重写建议四层）。
  final PerformanceReport report;
}

/// 舞台 tab 项（不可变值对象；状态变更经 controller copyWith 替换实例，
/// 保证内容槽 didUpdateWidget 的装载/重建判定可靠）。
///
/// 构造私有：tab 只能由 [WorkbenchStageController] 创建（单一事实源）；
/// T25 产物条只读消费字段。编辑器槽的 [dirty] 由内容组件经
/// `markEditorDirty` 回写（文本 ≠ 载入 SQL 即脏）。
@immutable
class WorkbenchStageTab {
  const WorkbenchStageTab._({
    required this.id,
    required this.kind,
    required this.initialSql,
    this.title,
    this.resultRef,
    this.structure,
    this.mongoStructure,
    this.execution,
    this.optimization,
    this.chartKind,
    this.pinned = false,
    this.dirty = false,
  });

  /// run 内唯一 tab 标识（`stage_tab_<seq>`，controller 单调生成）。
  final String id;

  /// tab 类型。
  final WorkbenchStageTabKind kind;

  /// 标签；null = 渲染层回退类型标签（agentStageTabGrid/Structure/Editor/Chart）。
  final String? title;

  /// 网格 / 图表 tab 的结果引用（内存引用，不复制）。
  final AgentResultRef? resultRef;

  /// 结构卡 tab 的 describe 数据。
  final StageStructureData? structure;

  /// 结构卡 tab 的 Mongo 集合 schema 数据（2b.2b；与 [structure] 互斥——
  /// SQL 表走 [structure]，Mongo 集合走本字段；mongo tab 的 structure 恒
  /// null，SQL 分支 match `structure?.tableName` 与 mongo tab 天然互斥）。
  final StageMongoStructureData? mongoStructure;

  /// execution tab 的执行结果投影（B1；复用刷新时整载荷替换）。
  final StageExecutionData? execution;

  /// optimization tab 的性能分析报告（2b.3；同 SQL 复用刷新时整载荷替换）。
  final StageOptimizationData? optimization;

  /// 图表 tab 的请求类型（line/bar/pie/scatter；null = 推荐模式）。
  final String? chartKind;

  /// 编辑器槽的载入 SQL（非编辑器 tab 为空串）。
  final String initialSql;

  /// 钉入产物条标记（§6.3：产物条 = pinned 子集投影）。
  final bool pinned;

  /// 编辑器槽未保存标记（tab 上 6px 点 + 关闭确认的判据，AC5.5）。
  final bool dirty;

  /// 字段替换（controller 内部状态迁移专用）。
  WorkbenchStageTab copyWith({
    String? title,
    String? chartKind,
    String? initialSql,
    StageExecutionData? execution,
    StageMongoStructureData? mongoStructure,
    StageOptimizationData? optimization,
    bool? pinned,
    bool? dirty,
  }) => WorkbenchStageTab._(
    id: id,
    kind: kind,
    title: title ?? this.title,
    resultRef: resultRef,
    structure: structure,
    mongoStructure: mongoStructure ?? this.mongoStructure,
    execution: execution ?? this.execution,
    optimization: optimization ?? this.optimization,
    chartKind: chartKind ?? this.chartKind,
    initialSql: initialSql ?? this.initialSql,
    pinned: pinned ?? this.pinned,
    dirty: dirty ?? this.dirty,
  );
}

/// 舞台状态单一事实源（ui 规格 §6.3 判定：tab 集合 / pinned 标记 / 激活态 /
/// 舞台可见性；tab 条与产物条两投影消费，产物条不复制数据）。
///
/// 消费方：舞台本体（本文件）、T25 产物条、T27 `agent_ui_port_impl`
/// （AgentUiPort 前五方法的操作目标）。打开语义（§5.3 工具级规则）：
/// openXxx → 舞台可见 + 激活新 tab；`pinArtifact` → 仅钉入，不改可见性。
class WorkbenchStageController extends ChangeNotifier {
  final List<WorkbenchStageTab> _tabs = <WorkbenchStageTab>[];
  int _activeIndex = -1;
  int _seq = 0;
  bool _stageVisible = false;

  /// 最近关闭栈（LIFO；[recentlyClosedTabsMax] 封顶，超出逐出栈底；
  /// 内存态不持久化）。tab 对象数据自持（resultRef 为行限内全量行内存
  /// 引用），重开无需重取数。
  final List<WorkbenchStageTab> _recentlyClosed = <WorkbenchStageTab>[];

  // ── 投影（只读）──────────────────────────────────────────────────────

  /// tab 时间序快照（不可变视图；产物条顺序 = 本序 pinned 子集）。
  List<WorkbenchStageTab> get tabs => List.unmodifiable(_tabs);

  /// 当前激活 tab 下标；空舞台 = -1。
  int get activeTabIndex => _activeIndex;

  /// 当前激活 tab；空舞台 = null。
  WorkbenchStageTab? get activeTab =>
      (_activeIndex >= 0 && _activeIndex < _tabs.length)
      ? _tabs[_activeIndex]
      : null;

  /// pinned 子集（时间序；T25 产物条投影数据源）。
  List<WorkbenchStageTab> get pinnedTabs =>
      List.unmodifiable(_tabs.where((t) => t.pinned));

  /// 舞台可见性（断点布局状态；T27 shell 消费：可见 = 对话列固定 360 +
  /// 舞台 Expanded ≥480，不可见 = 对话列 360–760 居中）。
  bool get stageVisible => _stageVisible;

  /// 重开栈封顶（超出逐出栈底）。
  static const int recentlyClosedTabsMax = 10;

  /// 最近关闭栈只读视图（栈顶在前 = 最近关闭在最前；重开菜单显示序）。
  List<WorkbenchStageTab> get recentlyClosedTabs =>
      List.unmodifiable(_recentlyClosed);

  /// 按 id 重开栈中项：出栈 + 追加 [_tabs] 末尾 + 激活 + 置舞台可见。
  /// **不走 openXxx 去重路径**（保对象身份：重开项与后续同 refId 新 tab
  /// 允许并存）。id 不在栈中（菜单快照过期）→ 返回 null 静默。
  WorkbenchStageTab? reopenClosedTab(String tabId) {
    final index = _recentlyClosed.indexWhere((t) => t.id == tabId);
    if (index < 0) return null;
    final tab = _recentlyClosed.removeAt(index);
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _stageVisible = true;
    notifyListeners();
    return tab;
  }

  /// 舞台开合（产物条左端开关 / T25 点项重开舞台的消费入口）。
  void setStageVisible(bool value) {
    if (_stageVisible == value) return;
    _stageVisible = value;
    notifyListeners();
  }

  // ── 打开（自动开舞台 + 激活；§5.3 打开时机）──────────────────────────

  /// 网格 tab：呈现结果引用全量行（行限内）。同 refId 网格 tab 已存在 →
  /// 复用并激活（tab 标题以新值为准），不重复建 tab。
  WorkbenchStageTab openGrid(AgentResultRef ref, String? title) {
    return _openTab(
      kind: WorkbenchStageTabKind.grid,
      title: title,
      resultRef: ref,
      match: (t) =>
          t.kind == WorkbenchStageTabKind.grid &&
          t.resultRef?.refId == ref.refId,
    );
  }

  /// 结构卡 tab：按表名去重（同表重开 = 复用激活）。
  WorkbenchStageTab openStructure(StageStructureData data) {
    return _openTab(
      kind: WorkbenchStageTabKind.structure,
      // 表名即默认标签（比类型标签「结构」信息量高）。
      title: data.tableName,
      structure: data,
      match: (t) =>
          t.kind == WorkbenchStageTabKind.structure &&
          t.structure?.tableName == data.tableName,
    );
  }

  /// 结构卡 tab（Mongo 集合分支，2b.2b）：match = kind == structure 且
  /// mongoStructure 非空且 connectionId + collectionName 双等——同集合同
  /// 连接重开 = 复用刷新（tab 恒 1，载荷替换，title 以新值为准）；不同
  /// 连接或不同集合各开各的。title 默认 = collectionName。
  ///
  /// 与 SQL 表分支零串味：SQL match 走 `structure?.tableName`，mongo tab
  /// 的 structure 恒 null、SQL tab 的 mongoStructure 恒 null，同表/集合名
  /// 也各自独立成 tab（零改动）。
  ///
  /// 复用分支自写（沿 [openExecution] B1 先例，任务书 §6.3 允许自决项）：
  /// 复用需替换 [StageMongoStructureData] 载荷，[_openTab] 既有复用语义
  /// （只换 title/chartKind）保持不变——grid/structure/chart 零变化。
  WorkbenchStageTab openMongoStructure(StageMongoStructureData data) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final StageMongoStructureData? existing = t.mongoStructure;
      if (t.kind != WorkbenchStageTabKind.structure || existing == null) {
        continue;
      }
      if (existing.connectionId == data.connectionId &&
          existing.collectionName == data.collectionName) {
        final reused = t.copyWith(
          title: data.collectionName,
          mongoStructure: data,
        );
        _tabs[i] = reused;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return reused;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      kind: WorkbenchStageTabKind.structure,
      title: data.collectionName,
      mongoStructure: data,
      initialSql: '',
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _stageVisible = true;
    notifyListeners();
    return tab;
  }

  /// 编辑器槽：载入 SQL 不自动执行（AC5.2；执行语义不在本组件）。
  /// AC5.5 槽策略：目标槽（最近一个编辑器槽）有未保存修改 → 新开槽，
  /// 绝不覆盖用户未保存内容；干净则复用装载。
  WorkbenchStageTab openEditorSlot(String sql) {
    for (final tab in _tabs.reversed) {
      if (tab.kind != WorkbenchStageTabKind.editor) continue;
      if (tab.dirty) break; // 目标槽脏 → 走新开槽（AC5.5）
      final reloaded = tab.copyWith(initialSql: sql, dirty: false);
      _tabs[_tabs.indexOf(tab)] = reloaded;
      _activeIndex = _tabs.indexOf(reloaded);
      _stageVisible = true;
      notifyListeners();
      return reloaded;
    }
    return _openTab(
      kind: WorkbenchStageTabKind.editor,
      title: null,
      initialSql: sql,
    );
  }

  /// 图表 tab：同 refId 图表 tab 已存在 → 复用激活（kind 以新请求为准）。
  WorkbenchStageTab openChart(AgentResultRef ref, String? kind) {
    return _openTab(
      kind: WorkbenchStageTabKind.chart,
      title: null,
      resultRef: ref,
      chartKind: kind,
      match: (t) =>
          t.kind == WorkbenchStageTabKind.chart &&
          t.resultRef?.refId == ref.refId,
    );
  }

  /// 会话列表 tab（v2 A2，R5 补录 kind）：单例——match = kind 即命中，
  /// 重复打开（收窄态活动条重复点击会话图标）复用激活既有 tab 不重复建
  /// （§8-2）；舞台不可见时自动可见（沿 [_openTab] 既有语义）。
  WorkbenchStageTab openSessions() {
    return _openTab(
      kind: WorkbenchStageTabKind.sessionList,
      title: null,
      match: (t) => t.kind == WorkbenchStageTabKind.sessionList,
    );
  }

  /// 查询历史 tab（v2 A3）：单例——match = kind 即命中，重复打开（收窄态
  /// 活动条重复点击历史图标）复用激活既有 tab 不重复建（§8-2，沿
  /// [openSessions] 既有单例模式）；舞台不可见时自动可见。
  WorkbenchStageTab openHistory() {
    return _openTab(
      kind: WorkbenchStageTabKind.history,
      title: null,
      match: (t) => t.kind == WorkbenchStageTabKind.history,
    );
  }

  /// 保存的查询 tab（v2 A4）：单例——match = kind 即命中，重复打开（收窄态
  /// 活动条重复点击保存的查询图标）复用激活既有 tab 不重复建（§8-2，沿
  /// [openSessions] 既有单例模式）；舞台不可见时自动可见。
  WorkbenchStageTab openSavedQueries() {
    return _openTab(
      kind: WorkbenchStageTabKind.savedQueries,
      title: null,
      match: (t) => t.kind == WorkbenchStageTabKind.savedQueries,
    );
  }

  /// execution tab（v2 B1，R4 去重键语义）：match = kind + `tabKey` 命中 →
  /// 复用并**替换数据载荷刷新**（标题以新值为准——时间戳随批次更新）；
  /// 未命中 → 新建追加激活。均置舞台可见。
  ///
  /// 复用分支自写（不走 [_openTab]）：既有复用语义只换 title/chartKind，
  /// execution 需替换数据载荷——自写分支保持 grid/structure/chart 既有
  /// 复用语义零变化（任务书 §6.8 允许自决项）。
  WorkbenchStageTab openExecution(StageExecutionData data) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final StageExecutionData? existing = t.execution;
      if (t.kind == WorkbenchStageTabKind.execution &&
          existing != null &&
          existing.tabKey == data.tabKey) {
        final reused = t.copyWith(title: data.title, execution: data);
        _tabs[i] = reused;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return reused;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      kind: WorkbenchStageTabKind.execution,
      title: data.title,
      execution: data,
      initialSql: '',
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _stageVisible = true;
    notifyListeners();
    return tab;
  }

  /// observe tab（2b.1，R1）：单例跟随锁定连接——match = kind 即命中，
  /// 重复打开（命令面板/活动条重复触发）复用激活既有 tab 不重复建
  /// （§8-2，沿 [openSessions] 既有单例模式）；舞台不可见时自动可见。
  /// 内容每次 build 从 effectiveWorkbenchContext 派生（连接快照不进 tab
  /// 数据），锁切换语义由 [WorkbenchObserveContent] 承担。
  WorkbenchStageTab openObserve() {
    return _openTab(
      kind: WorkbenchStageTabKind.observe,
      title: null,
      match: (t) => t.kind == WorkbenchStageTabKind.observe,
    );
  }

  /// optimization tab（2b.3，R6 去重键语义）：match = kind == optimization
  /// 且 `optimization.sql == data.sql`（原 SQL 精确串）→ 复用并**替换数据
  /// 载荷刷新**（同 SQL 重解释 = 同 tab 刷新不累积）；未命中 → 新建追加
  /// 激活。均置舞台可见。title 缺省 null = 渲染层回退类型标签
  /// （agentStageTabOptimization）。
  ///
  /// 复用分支自写（沿 [openExecution] B1 先例，任务书 §6.4 允许自决项）：
  /// 复用需替换 [StageOptimizationData] 载荷，[_openTab] 既有复用语义
  /// （只换 title/chartKind）保持不变——grid/structure/chart 零变化。
  WorkbenchStageTab openOptimization(StageOptimizationData data) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final StageOptimizationData? existing = t.optimization;
      if (t.kind == WorkbenchStageTabKind.optimization &&
          existing != null &&
          existing.sql == data.sql) {
        final reused = t.copyWith(optimization: data);
        _tabs[i] = reused;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return reused;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      kind: WorkbenchStageTabKind.optimization,
      title: null,
      optimization: data,
      initialSql: '',
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _stageVisible = true;
    notifyListeners();
    return tab;
  }

  /// 产物条钉住（§6.3）：该 ref 无网格 tab → 建一个 pinned 网格 tab；
  /// 已有 → 置 pinned。**不改舞台可见性**（T27 `pinArtifact` 的操作目标）。
  WorkbenchStageTab pinArtifact(AgentResultRef ref, String? label) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      if (t.kind == WorkbenchStageTabKind.grid &&
          t.resultRef?.refId == ref.refId) {
        if (t.pinned && t.title == (label ?? t.title)) return t; // 已钉住：幂等
        final pinnedTab = t.copyWith(title: label ?? t.title, pinned: true);
        _tabs[i] = pinnedTab;
        notifyListeners();
        return pinnedTab;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      kind: WorkbenchStageTabKind.grid,
      title: label,
      resultRef: ref,
      pinned: true,
      initialSql: '',
    );
    _tabs.add(tab);
    // 无 tab 时激活补位；有 tab 时不动激活（钉入不打断当前工作）。
    if (_activeIndex < 0) _activeIndex = 0;
    notifyListeners();
    return tab;
  }

  // ── tab 操作 ─────────────────────────────────────────────────────────

  /// 激活 tab（越界静默忽略）。
  void activateTab(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    notifyListeners();
  }

  /// 钉住 / 取消钉住（产物条 × 与右键菜单共用入口）。
  void setPinned(int tabIndex, bool pinned) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    if (_tabs[tabIndex].pinned == pinned) return;
    _tabs[tabIndex] = _tabs[tabIndex].copyWith(pinned: pinned);
    notifyListeners();
  }

  /// 关闭 tab（原始移除；**不含未保存确认**——确认是 UI 语义，由舞台/
  /// shell 层在调用前执行）。关闭后激活态自动补位。
  ///
  /// 被移除对象**全 kind 统一压入最近关闭栈**（含 sessionList 等单例类；
  /// [recentlyClosedTabsMax] 封顶逐出栈底）。编辑器 tab 压栈前丢弃脏标记
  /// （copyWith(dirty: false)）——关闭确认已放弃未保存编辑，复活对象不得
  /// 带脏点；其余字段原样。重开 = 对象原样重新入列（[reopenClosedTab]，
  /// 不走 openXxx 去重路径）。
  void closeTab(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    final removed = _tabs.removeAt(tabIndex);
    _recentlyClosed.insert(
      0,
      removed.kind == WorkbenchStageTabKind.editor && removed.dirty
          ? removed.copyWith(dirty: false)
          : removed,
    );
    if (_recentlyClosed.length > recentlyClosedTabsMax) {
      _recentlyClosed.removeLast(); // 逐出栈底（最先关闭者）
    }
    if (_tabs.isEmpty) {
      _activeIndex = -1;
    } else if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    } else if (tabIndex < _activeIndex) {
      _activeIndex--;
    }
    notifyListeners();
  }

  /// 编辑器槽内容组件回写未保存标记（文本 ≠ 载入 SQL 即脏；仅翻转时通知，
  /// 避免每次击键触发全舞台重建）。
  void markEditorDirty(String tabId, bool dirty) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      if (t.id == tabId && t.dirty != dirty) {
        _tabs[i] = t.copyWith(dirty: dirty);
        notifyListeners();
        return;
      }
    }
  }

  // ── 图表适配判定（AC5.3；与 T27 port renderChart 的 outcome 失败同源）──

  /// 列型是否适配图表渲染：至少一列可检出数值列（图表语义的最小公共
  /// 前提——line/bar/pie/scatter 均需数值度量）。空数据不算不适配
  /// （沿 ChartView 既有空态呈现）。
  static bool isChartable(AgentResultRef ref) {
    if (ref.rows.isEmpty || ref.columns.isEmpty) return true;
    for (final column in ref.columns) {
      if (ResultFilterService.detectColumnType(ref.rows, column) ==
          ColumnDataType.numeric) {
        return true;
      }
    }
    return false;
  }

  // ── 内部 ─────────────────────────────────────────────────────────────

  String _nextId() => 'stage_tab_${_seq++}';

  /// 打开通用路径：命中 [match] → 复用激活；否则新建追加激活。均置舞台可见。
  WorkbenchStageTab _openTab({
    required WorkbenchStageTabKind kind,
    required String? title,
    String? chartKind,
    String? initialSql,
    AgentResultRef? resultRef,
    StageStructureData? structure,
    bool Function(WorkbenchStageTab tab)? match,
  }) {
    if (match != null) {
      for (var i = 0; i < _tabs.length; i++) {
        if (!match(_tabs[i])) continue;
        final reused = _tabs[i].copyWith(
          title: title ?? _tabs[i].title,
          chartKind: chartKind ?? _tabs[i].chartKind,
        );
        _tabs[i] = reused;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return reused;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      kind: kind,
      title: title,
      resultRef: resultRef,
      structure: structure,
      chartKind: chartKind,
      initialSql: initialSql ?? '',
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _stageVisible = true;
    notifyListeners();
    return tab;
  }
}

/// 舞台组件：tab 条 32 + 内容区（bgPrimary / padding space3 / 无卡框）。
///
/// 布局断点（≥480 / 对话列 360 固定）由 T27 shell 消费 controller 可见性
/// 状态实现；本组件只保证自身内容在 1024×768 下无溢出（§5.4-1 的舞台侧）。
/// 内容用 IndexedStack 保活——编辑器槽的未保存内容在 tab 切换间不丢（AC5.5
/// 的前提）；网格按虚拟化表格自身滚动，结构卡单滚动区，DDL 块内部滚动。
class WorkbenchStage extends StatefulWidget {
  const WorkbenchStage({
    super.key,
    required this.controller,
    this.registry,
    this.onOpenInClassic,
    this.zoneRegistry,
  });

  /// 舞台状态宿主（T27 shell 创建注入；测试自建）。
  final WorkbenchStageController controller;

  /// 结果渲染器注册表（网格 tab 只读消费；null = `defaultPluginRegistry`）。
  final PluginRegistry? registry;

  /// [在经典中打开] 出口（图表不适配 / 兜底出口用；参数 = 该结果的原 SQL）。
  /// T27 接线 `WorkbenchOpenInClassic.open`；未注入时按钮照常渲染为 no-op
  /// （沿 sql_tool_card 接口预留先例，不禁用不假实现）。
  final void Function(String sql)? onOpenInClassic;

  /// F6 六区注册表（A5；null = 不注册，既有组件面测试零改动）。本组件登记
  /// tab 条区 + 内容区两区（舞台不入树 = 未挂载 = 两区未注册——shell 布局
  /// 仅在舞台可见时构建本组件，可见性动态跳过由此天然成立）。
  final WorkbenchFocusZoneRegistry? zoneRegistry;

  /// tab 条容器（§5.4-4 高度探针 / §5.4-5 滚动探针目标）。
  static const Key tabBarKey = ValueKey('workbench_stage_tab_bar');

  /// 内容区容器。
  static const Key contentAreaKey = ValueKey('workbench_stage_content');

  /// 空态（§5.4-7 三元素探针目标）。
  static const Key emptyStateKey = ValueKey('workbench_stage_empty');

  /// 图表不适配内联错误块（§5.4-8）。
  static const Key chartMismatchKey = ValueKey(
    'workbench_stage_chart_mismatch',
  );

  /// 图表不适配 [在经典中打开] 出口。
  static const Key openInClassicButtonKey = ValueKey(
    'workbench_stage_open_in_classic',
  );

  /// 单个 tab 项（几何 / 键盘探针用）。
  static Key tabItemKey(String tabId) => ValueKey('workbench_stage_tab_$tabId');

  /// 单个 tab 的关闭钮。
  static Key tabCloseKey(String tabId) =>
      ValueKey('workbench_stage_tab_close_$tabId');

  /// 编辑器槽未保存 6px 点。
  static Key dirtyDotKey(String tabId) =>
      ValueKey('workbench_stage_tab_dirty_$tabId');

  /// tab 条右端收起钮（收起入口自产物条移位至此，走查修复批件①）。
  static const Key collapseKey = ValueKey('workbench_stage_collapse');

  /// tab 条右端重开钮（最近关闭栈入口，走查修复批件②）。
  static const Key reopenButtonKey = ValueKey('workbench_stage_reopen');

  /// 重开菜单中单个栈项。
  static Key reopenItemKey(String tabId) =>
      ValueKey('workbench_stage_reopen_item_$tabId');

  @override
  State<WorkbenchStage> createState() => _WorkbenchStageState();
}

class _WorkbenchStageState extends State<WorkbenchStage> {
  final ScrollController _tabScroll = ScrollController();

  /// 每 tab 焦点节点（roving tabindex；§0.4 / §5.4-5）。
  final Map<String, FocusNode> _tabFocusNodes = {};

  /// tab 条尾部两钮焦点节点（重开 / 收起；roving 序列 [tabs…, 重开, 收起]
  /// 的尾部两项，走查修复批 S9）。与每 tab 节点同生命周期（State 持有）。
  late final FocusNode _reopenFocusNode = FocusNode(
    debugLabel: 'stage_reopen_button',
  );
  late final FocusNode _collapseFocusNode = FocusNode(
    debugLabel: 'stage_collapse_button',
  );

  /// 每 tab 定位键（自动滚入视口 + 测试几何探针）。
  final Map<String, GlobalKey> _tabKeys = {};

  /// 每 tab 内容槽定位键（A5 内容区入口的遍历根——IndexedStack 全量构建
  /// 各槽，遍历须限定**激活槽**子树，KeyedSubtree + GlobalKey 稳定寻址）。
  final Map<String, GlobalKey> _slotKeys = {};

  /// F6 两区（tab 条 / 内容区）聚焦入口（身份稳定闭包：注册/注销成对使用
  /// 同一实例）。
  late final WorkbenchZoneFocusEntry _tabBarZoneEntry = _focusActiveTab;
  late final WorkbenchZoneFocusEntry _contentZoneEntry = _focusActiveSlot;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // A5：舞台挂载（= 舞台可见，shell 仅在可见态构建本组件）注册两区。
    _syncZoneRegistration();
    // 挂载即有 tab（T27 重装配 / 测试直开）时把激活项滚入视口。
    final active = widget.controller.activeTab;
    if (active != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureTabVisible(active.id),
      );
    }
  }

  @override
  void didUpdateWidget(covariant WorkbenchStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    // 注册表实例变更（防御）：旧表注销、新表重登记。
    if (!identical(oldWidget.zoneRegistry, widget.zoneRegistry)) {
      _unregisterZones(oldWidget.zoneRegistry);
      _syncZoneRegistration();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _unregisterZones(widget.zoneRegistry);
    _tabScroll.dispose();
    _reopenFocusNode.dispose();
    _collapseFocusNode.dispose();
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    _tabFocusNodes.clear();
    super.dispose();
  }

  /// 两区注册（未注入注册表时跳过）。
  void _syncZoneRegistration() {
    final registry = widget.zoneRegistry;
    if (registry == null) return;
    registry.register(WorkbenchFocusZone.stageTabBar, _tabBarZoneEntry);
    registry.register(WorkbenchFocusZone.stageContent, _contentZoneEntry);
  }

  /// 两区注销（[registry] 为 null 或不含本实例条目时安全空转——身份比对）。
  void _unregisterZones(WorkbenchFocusZoneRegistry? registry) {
    if (registry == null) return;
    registry.unregister(WorkbenchFocusZone.stageTabBar, _tabBarZoneEntry);
    registry.unregister(WorkbenchFocusZone.stageContent, _contentZoneEntry);
  }

  // ── F6 两区入口（A5）──────────────────────────────────────────────────

  /// tab 条区入口：聚焦激活 tab；空舞台 → 聚焦**重开钮**（禁用态可聚焦
  /// ——死档①消除：空舞台不再整区跳过，走查修复批 S5a；架构师裁决回退
  /// 目标 = 重开钮）。
  bool _focusActiveTab() {
    final tab = widget.controller.activeTab;
    if (tab == null) {
      _reopenFocusNode.requestFocus();
      return true;
    }
    final node = _tabFocusNodes[tab.id];
    if (node == null) return false;
    node.requestFocus();
    return true;
  }

  /// 内容区入口：聚焦**激活 tab 内容**首个可聚焦元素（无激活 tab / 槽未
  /// 建树 / 槽内无可聚焦元素 → false，轮转动态跳过）。
  bool _focusActiveSlot() {
    final tab = widget.controller.activeTab;
    if (tab == null) return false;
    final context = _slotKeys[tab.id]?.currentContext;
    if (context == null) return false;
    final FocusNode? first = _firstFocusableDescendant(context);
    if (first == null) return false;
    first.requestFocus();
    return true;
  }

  /// 在 [anchor] 子树内找首个可聚焦 [FocusNode]（ReadingOrderTraversalPolicy
  /// 的简化投影：按焦点节点矩形 (top, left) 升序——工作台各区内部均为简单
  /// 纵列/横行，该投影与真实遍历序一致）。
  ///
  /// 与 `workbench_session_rail.dart` 的同构私有辅助各持一份（两文件均不
  /// import 对方私有成员；注册表文件保持纯 Dart 不引 widgets）。
  FocusNode? _firstFocusableDescendant(BuildContext anchor) {
    final FocusScopeNode scope = FocusScope.of(anchor);
    final Element anchorElement = anchor as Element;
    FocusNode? best;
    Rect? bestRect;
    for (final FocusNode node in scope.traversalDescendants) {
      final BuildContext? nodeContext = node.context;
      if (nodeContext == null) continue;
      if (!_isWithinSubtree(nodeContext, anchorElement)) continue;
      final rect = node.rect;
      if (bestRect == null ||
          rect.top < bestRect.top ||
          (rect.top == bestRect.top && rect.left < bestRect.left)) {
        best = node;
        bestRect = rect;
      }
    }
    return best;
  }

  /// [context] 是否位于 [ancestor] 子树内。
  static bool _isWithinSubtree(BuildContext context, Element ancestor) {
    if (identical(context, ancestor)) return true;
    var found = false;
    (context as Element).visitAncestorElements((element) {
      if (identical(element, ancestor)) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _pruneTabResources();
    setState(() {});
    // 激活项 / 新开项自动滚入视口（§5.2 溢出规则）——帧后定位（本帧树未建）。
    final active = widget.controller.activeTab;
    if (active != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureTabVisible(active.id),
      );
    }
  }

  /// 清理已关闭 tab 的焦点节点与键。焦点节点延后一帧 dispose（此刻可能仍
  /// attach 在即将卸载的 Focus 上，立即 dispose 触发调试断言）。
  void _pruneTabResources() {
    final liveIds = widget.controller.tabs.map((t) => t.id).toSet();
    final orphanedNodes = <FocusNode>[];
    _tabFocusNodes.removeWhere((id, node) {
      if (liveIds.contains(id)) return false;
      orphanedNodes.add(node);
      return true;
    });
    _tabKeys.removeWhere((id, _) => !liveIds.contains(id));
    _slotKeys.removeWhere((id, _) => !liveIds.contains(id));
    if (orphanedNodes.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final node in orphanedNodes) {
          node.dispose();
        }
      });
    }
  }

  void _ensureTabVisible(String tabId) {
    if (!mounted) return;
    final ctx = _tabKeys[tabId]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppDesignSystem.durationNormal,
      curve: AppDesignSystem.curveDefault,
      alignment: 0.5,
    );
  }

  // ── tab 条 ───────────────────────────────────────────────────────────

  Widget _buildTabBar(BuildContext context) {
    final colors = context.themeColors;
    final tabs = widget.controller.tabs;
    return Container(
      key: WorkbenchStage.tabBarKey,
      height: AppDesignSystem.tabBarHeight,
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        border: Border(
          bottom: BorderSide(
            color: colors.dividerColor,
            width: AppDesignSystem.tabBarDividerHeight,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            // 非懒构建（SingleChildScrollView + Row）：roving 键盘要能把焦点移到
            // 视口外的 tab（焦点节点/定位键必须在树上），懒列表会漏建——本面 tab
            // 数上界 = agent 运行步数（§5.4-5 的 20 tab 量级），全量构建代价可接受。
            child: SingleChildScrollView(
              controller: _tabScroll,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    _buildTabItem(
                      context,
                      tabs[i],
                      i == widget.controller.activeTabIndex,
                      i,
                    ),
                ],
              ),
            ),
          ),
          // 尾部控件簇（走查修复批 S2）：[重开钮 rotateCcw] [收起钮
          // panelRightClose]——收起钮贴最右缘、重开在左；空舞台（零 tab）
          // 恒渲染。
          _buildReopenButton(context, tabs.length),
          _buildCollapseButton(context, tabs.length),
        ],
      ),
    );
  }

  /// 重开钮（S7）：rotateCcw 14 textSecondary；栈空 = 禁用态渲染（降透明度
  /// 不隐藏、tooltip 照常、可聚焦、Enter/Space/↓ 空转、点击不开菜单）。
  /// tooltip = agentStageReopenClosedTab。
  Widget _buildReopenButton(BuildContext context, int tabCount) {
    final l10n = AppLocalizations.of(context)!;
    return _StageBarAction(
      actionKey: WorkbenchStage.reopenButtonKey,
      focusNode: _reopenFocusNode,
      itemIndex: tabCount,
      barItemCount: tabCount + 2,
      icon: LucideIcons.rotateCcw,
      tooltip: l10n.agentStageReopenClosedTab,
      enabled: widget.controller.recentlyClosedTabs.isNotEmpty,
      onActivate: _openReopenMenuOrNoop,
      openMenuOnArrowDown: true,
      onMoveFocus: _focusTab,
    );
  }

  /// 收起钮（S3）：panelRightClose 14 textSecondary（功能性控件不用
  /// textMuted——FU-11 对比度坑）；tooltip = agentStageCollapse；收起舞台。
  Widget _buildCollapseButton(BuildContext context, int tabCount) {
    final l10n = AppLocalizations.of(context)!;
    return _StageBarAction(
      actionKey: WorkbenchStage.collapseKey,
      focusNode: _collapseFocusNode,
      itemIndex: tabCount + 1,
      barItemCount: tabCount + 2,
      icon: LucideIcons.panelRightClose,
      tooltip: l10n.agentStageCollapse,
      onActivate: () => widget.controller.setStageVisible(false),
      onMoveFocus: _focusTab,
    );
  }

  /// 重开菜单入口：空栈空转；非空弹菜单（锚定重开钮下方、右对齐舞台右缘）。
  void _openReopenMenuOrNoop() {
    if (widget.controller.recentlyClosedTabs.isEmpty) return; // 空栈空转
    _showReopenMenu();
  }

  /// 重开菜单（S8，沿 [_showTabMenu] 的 showMenu + CompactPopupMenuItem
  /// value-then 先例）：显示序 = 栈序（最近关闭在最上）；项 = [kind 图标 14
  /// （workbench_stage_tab_visuals 注册表单源消费）] + [标题 12px 上限
  /// 240px ellipsis（title 回退 kind.label）]；不加时间戳。项 tap/Enter →
  /// [WorkbenchStageController.reopenClosedTab]（按 id 查栈，菜单快照过期
  /// miss → null 静默）；Esc/遮罩关闭零副作用。
  Future<void> _showReopenMenu() async {
    final controller = widget.controller;
    final position = _reopenMenuPosition();
    if (position == null) return;
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final value = await showMenu<String>(
      context: context,
      position: position,
      color: colors.bgTertiary,
      items: [
        for (final tab in controller.recentlyClosedTabs)
          CompactPopupMenuItem<String>(
            key: WorkbenchStage.reopenItemKey(tab.id),
            value: tab.id,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(tab.kind.icon, size: 14, color: colors.textSecondary),
                const SizedBox(width: AppDesignSystem.space1_5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    tab.title ?? tab.kind.label(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeSm,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (!mounted || value == null) return; // Esc / 遮罩：零副作用
    controller.reopenClosedTab(value); // miss → null 静默（快照防御）
  }

  /// 重开菜单锚定矩形（自决项 4）：重开钮下方起点 + 右对齐舞台右缘。
  /// 任一渲染对象不可用（理论不可达：按钮已挂载才可能触发）→ null 不弹。
  RelativeRect? _reopenMenuPosition() {
    final RenderObject? stageRender = context.findRenderObject();
    if (stageRender is! RenderBox || !stageRender.hasSize) return null;
    final BuildContext? buttonContext = _reopenFocusNode.context;
    if (buttonContext == null) return null;
    final RenderObject? buttonRender = buttonContext.findRenderObject();
    if (buttonRender is! RenderBox || !buttonRender.hasSize) return null;
    // Overlay.of 无 Overlay 时抛错（MaterialApp 面恒存在，理论不可达）。
    final OverlayState overlay = Overlay.of(context);
    final RenderObject? overlayRender = overlay.context.findRenderObject();
    if (overlayRender is! RenderBox || !overlayRender.hasSize) return null;
    final Rect stageRect =
        stageRender.localToGlobal(Offset.zero) & stageRender.size;
    final Rect buttonRect =
        buttonRender.localToGlobal(Offset.zero) & buttonRender.size;
    return RelativeRect.fromLTRB(
      buttonRect.left,
      buttonRect.bottom,
      overlayRender.size.width - stageRect.right, // 右缘贴舞台右缘
      0,
    );
  }

  Widget _buildTabItem(
    BuildContext context,
    WorkbenchStageTab tab,
    bool isActive,
    int index,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final node = _tabFocusNodes.putIfAbsent(
      tab.id,
      () => FocusNode(debugLabel: 'stage_tab_${tab.id}'),
    );
    final tabKey = _tabKeys.putIfAbsent(
      tab.id,
      () => GlobalKey(debugLabel: tab.id),
    );
    return _StageTabItem(
      key: tabKey,
      itemKey: WorkbenchStage.tabItemKey(tab.id),
      tab: tab,
      isActive: isActive,
      focusNode: node,
      tabIndex: index,
      // 条内项总数 = tab 数 + 尾部两钮（重开/收起）——End 落收起钮（S9）。
      barItemCount: widget.controller.tabs.length + 2,
      displayLabel: tab.title ?? tab.kind.label(l10n),
      onActivate: () {
        node.requestFocus();
        widget.controller.activateTab(index);
      },
      onRequestClose: () => _requestCloseTab(tab, index),
      onMoveFocus: _focusTab,
      onContextMenu: (position) => _showTabMenu(context, tab, index, position),
    );
  }

  /// 条内 roving 焦点解析（S9 泛化，自决项 3）：索引域 = [0, n+1]——
  /// [0, n-1] = tab、n = 重开钮、n+1 = 收起钮（Home = 首 tab、End = 收起钮）。
  /// 越界（<0 或 >n+1）钳制不动。
  void _focusTab(int index) {
    final tabs = widget.controller.tabs;
    if (index >= 0 && index < tabs.length) {
      final node = _tabFocusNodes[tabs[index].id];
      node?.requestFocus();
      _ensureTabVisible(tabs[index].id);
      return;
    }
    if (index == tabs.length) {
      _reopenFocusNode.requestFocus();
      return;
    }
    if (index == tabs.length + 1) {
      _collapseFocusNode.requestFocus();
      return;
    }
    // 越界：钳制（焦点留在原位）。
  }

  /// 关闭请求：编辑器槽未保存 → 先确认（AC5.5：确认前 tab 不消失），
  /// 其余类型直接关。
  Future<void> _requestCloseTab(WorkbenchStageTab tab, int index) async {
    if (tab.kind == WorkbenchStageTabKind.editor && tab.dirty) {
      final l10n = AppLocalizations.of(context)!;
      final label = tab.title ?? l10n.agentStageTabEditor;
      final discard = await _confirmDiscardEditorClose(context, label);
      if (!discard) return; // 取消 / 遮罩 / Esc：tab 保留
    }
    widget.controller.closeTab(index);
  }

  /// 未保存关闭确认：沿既有 `TabCloseConfirmDialog` 文案语义（标题/正文/
  /// 取消/放弃），但不提供「保存」——舞台编辑器槽无保存目的地（经典 tab
  /// 才有），内容出口是显式复制 / 在经典中打开。
  Future<bool> _confirmDiscardEditorClose(BuildContext context, String label) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.bgSecondary,
        title: Text(
          l10n.unsavedChangesTitle,
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          l10n.tabCloseConfirmMessage(label),
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.discardChanges,
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  /// tab 右键 / 菜单键菜单（沿经典 tab `onSecondaryTapDown` + showMenu 先例）：
  /// [钉入产物条 / 取消钉住]、[关闭]（§5.2）。
  void _showTabMenu(
    BuildContext context,
    WorkbenchStageTab tab,
    int index,
    Offset globalPosition,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      color: colors.bgTertiary,
      items: [
        CompactPopupMenuItem<String>(
          value: 'pin',
          child: Text(
            tab.pinned ? l10n.agentStageTabUnpin : l10n.agentStageTabPin,
          ),
        ),
        CompactPopupMenuItem<String>(
          value: 'close',
          child: Text(l10n.agentStageTabClose),
        ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      if (value == 'pin') {
        widget.controller.setPinned(index, !tab.pinned);
      } else if (value == 'close') {
        _requestCloseTab(tab, index);
      }
    });
  }

  // ── 内容区 ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final controller = widget.controller;
    return Column(
      children: [
        _buildTabBar(context),
        Expanded(
          child: Container(
            key: WorkbenchStage.contentAreaKey,
            color: colors.bgPrimary,
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            child: controller.tabs.isEmpty
                ? _buildEmpty(context)
                : _buildContent(context),
          ),
        ),
      ],
    );
  }

  /// 空态三元素：panelRight 32 textMuted + 「舞台为空」13 textSecondary +
  /// hint 11 textMuted；无插画无按钮（§5.3）。
  Widget _buildEmpty(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Center(
      key: WorkbenchStage.emptyStateKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.panelRight, size: 32, color: colors.textMuted),
          const SizedBox(height: AppDesignSystem.space2_5),
          Text(
            l10n.agentStageEmptyTitle,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeMd,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            l10n.agentStageEmptyHint,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// 内容槽（IndexedStack 保活：编辑器未保存内容跨 tab 切换不丢）。各槽包
  /// KeyedSubtree（A5：内容区入口的遍历根，[_slotKeys] 限定激活槽子树，
  /// 排除 IndexedStack 全量构建的其它槽）。
  Widget _buildContent(BuildContext context) {
    final controller = widget.controller;
    final tabs = controller.tabs;
    final index = controller.activeTabIndex.clamp(0, tabs.length - 1);
    return IndexedStack(
      index: index,
      children: [
        for (final tab in tabs)
          KeyedSubtree(
            key: _slotKeys.putIfAbsent(
              tab.id,
              () => GlobalKey(debugLabel: 'stage_slot_${tab.id}'),
            ),
            child: _buildSlot(context, tab),
          ),
      ],
    );
  }

  Widget _buildSlot(BuildContext context, WorkbenchStageTab tab) {
    switch (tab.kind) {
      case WorkbenchStageTabKind.grid:
        return _StageGridContent(tab: tab, registry: widget.registry);
      case WorkbenchStageTabKind.structure:
        final mongo = tab.mongoStructure;
        if (mongo != null) {
          // Mongo 集合 schema（2b.2b，R5）：内容件消费 AppProvider
          // per-connection facade，本件只透传三参；零写路径。
          return WorkbenchMongoSchemaView(
            connectionId: mongo.connectionId,
            databaseName: mongo.databaseName,
            collectionName: mongo.collectionName,
          );
        }
        return _StageStructureContent(tab: tab);
      case WorkbenchStageTabKind.editor:
        return _StageEditorContent(
          tab: tab,
          stageController: widget.controller,
        );
      case WorkbenchStageTabKind.chart:
        return _StageChartContent(
          tab: tab,
          onOpenInClassic: widget.onOpenInClassic,
        );
      case WorkbenchStageTabKind.sessionList:
        // 会话列表全宽形态（v2 §8-5 同源）：与 rail 内容页同一组件，
        // 头栏（含新建钮）随 tab 形态保留。
        return SessionListView(showHeader: true);
      case WorkbenchStageTabKind.history:
        // 查询历史全宽形态（v2 A3 / §8-5 同源）：与 rail 历史页同一组件，
        // 宽空间增强 = 元信息列更全（narrow=false 分支），不加 rail 没有的
        // 能力；载入回调绑本 controller 的 openEditorSlot（AC5.5 脏槽保护
        // 既有；载入不执行）。
        return QueryHistoryListView(
          onLoadIntoEditor: widget.controller.openEditorSlot,
        );
      case WorkbenchStageTabKind.savedQueries:
        // 保存的查询全宽形态（v2 A4 / §8-5 同源，本地段 only）：与 rail
        // 保存的查询页同一组件；载入回调绑本 controller 的 openEditorSlot
        // （AC5.5 脏槽保护既有；载入不执行，无任何执行入口）。
        return SavedQueryListView(
          onLoadIntoEditor: widget.controller.openEditorSlot,
        );
      case WorkbenchStageTabKind.execution:
        // 执行结果摘要（v2 B1）：纯只读投影——零动作按钮（无重跑/编辑/
        // 导出，v1 §4 守卫 + §5 纪律 6）。
        return _StageExecutionContent(tab: tab);
      case WorkbenchStageTabKind.observe:
        // 实例观察（2b.1，R1）：零数据载荷——内容每次 build 从
        // effectiveWorkbenchContext 派生锁定连接（单例跟随锁定连接）。
        return const WorkbenchObserveContent();
      case WorkbenchStageTabKind.optimization:
        // 查询优化（2b.3，R6）：SQL 上下文头 + QueryPlanVisualizer 零改动
        // 复用；「应用此索引」= openEditorSlot 填槽不执行（零自动写）。
        return _StageOptimizationContent(
          tab: tab,
          stageController: widget.controller,
        );
    }
  }
}

/// tab 项（§5.2）：[类型图标 14 textSecondary] + 6 + [未保存 6px accentBlue 点
/// （标签前）] + [标签 12 ellipsis] + 6 + [关闭 12]；内边距 h 10；上限宽 200
/// 不设最小宽；激活 primaryContainer（200ms 过渡）/ 非激活透明 + hover
/// bgTertiary；右键菜单 + roving 键盘（←/→/Home/End 移动、Enter/Space 激活、
/// 菜单键弹菜单）。
class _StageTabItem extends StatefulWidget {
  const _StageTabItem({
    super.key,
    required this.itemKey,
    required this.tab,
    required this.isActive,
    required this.focusNode,
    required this.tabIndex,
    required this.barItemCount,
    required this.displayLabel,
    required this.onActivate,
    required this.onRequestClose,
    required this.onMoveFocus,
    required this.onContextMenu,
  });

  final Key itemKey;
  final WorkbenchStageTab tab;
  final bool isActive;
  final FocusNode focusNode;

  /// 本 tab 在集合中的下标与条内项总数（roving 键盘的目标计算；条内项
  /// 总数 = tab 数 + 尾部两钮，End 落收起钮——走查修复批 S9 语义变更）。
  final int tabIndex;
  final int barItemCount;
  final String displayLabel;
  final VoidCallback onActivate;
  final VoidCallback onRequestClose;
  final void Function(int targetIndex) onMoveFocus;
  final void Function(Offset globalPosition) onContextMenu;

  @override
  State<_StageTabItem> createState() => _StageTabItemState();
}

class _StageTabItemState extends State<_StageTabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final active = widget.isActive;
    final tab = widget.tab;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        onTap: widget.onActivate,
        onSecondaryTapDown: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: Tooltip(
          // §0.4：tooltip 同时承载 hover 与键盘聚焦（被截断的全文）。
          message: widget.displayLabel,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedContainer(
              key: widget.itemKey,
              duration: AppDesignSystem.durationNormal,
              curve: AppDesignSystem.curveDefault,
              height: AppDesignSystem.tabBarHeight,
              constraints: const BoxConstraints(
                maxWidth: AppDesignSystem.workbenchStageTabMaxWidth,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2_5,
              ),
              decoration: BoxDecoration(
                color: active
                    ? colors.primaryContainer
                    : (_hovered ? colors.bgTertiary : Colors.transparent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tab.kind.icon,
                    size: 14,
                    color: colors.textSecondary, // §5.2：恒 textSecondary
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  if (tab.dirty) ...[
                    Tooltip(
                      message: l10n.agentStageTabDirty,
                      child: Container(
                        key: WorkbenchStage.dirtyDotKey(tab.id),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.accentBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space1),
                  ],
                  Flexible(
                    child: Text(
                      widget.displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeSm,
                        color: active
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  _buildCloseButton(context, tab.id),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context, String tabId) {
    final colors = context.themeColors;
    return InkWell(
      key: WorkbenchStage.tabCloseKey(tabId),
      onTap: widget.onRequestClose,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space0_5,
          vertical: AppDesignSystem.space1,
        ),
        child: Icon(LucideIcons.x, size: 12, color: colors.textMuted),
      ),
    );
  }

  /// roving 键盘（§0.4 / §5.4-5）：←/→ 相邻移动、Home/End 首末、Enter/Space
  /// 激活（tab 行自身持焦点时）、菜单键弹上下文菜单。越界目标由宿主钳制。
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onMoveFocus(widget.tabIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onMoveFocus(widget.tabIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      widget.onMoveFocus(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      // End = 条内最后一项 = 收起钮（S9 语义变更：原末 tab）。
      widget.onMoveFocus(widget.barItemCount - 1);
      return KeyEventResult.handled;
    }
    final isActivate =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if ((isActivate || key == LogicalKeyboardKey.space) &&
        node.hasPrimaryFocus) {
      widget.onActivate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.contextMenu) {
      final rect = node.rect;
      widget.onContextMenu(Offset(rect.left, rect.bottom));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// tab 条尾部动作钮（重开 / 收起，走查修复批 S3/S7/S9）：14px 图标 +
/// textSecondary；hover bgTertiary；命中区 = tab 条全高 32 × 宽 28；roving
/// 焦点序列尾部两项（←/→/Home/End 经 [onMoveFocus] 由宿主 [_focusTab]
/// 钳制解析）。
///
/// 禁用态（自决项 2）：降透明度**不隐藏**、tooltip 照常、节点可聚焦、
/// Enter/Space/↓ 空转（仍返回 handled）、点击不开菜单——不用
/// IgnorePointer（会连带禁聚焦）。空栈重开钮是唯一禁用消费方。
class _StageBarAction extends StatefulWidget {
  const _StageBarAction({
    required this.actionKey,
    required this.focusNode,
    required this.itemIndex,
    required this.barItemCount,
    required this.icon,
    required this.tooltip,
    required this.onActivate,
    required this.onMoveFocus,
    this.openMenuOnArrowDown = false,
    this.enabled = true,
  });

  final Key actionKey;
  final FocusNode focusNode;

  /// 本钮在条内 roving 序列中的下标与条内项总数（tab 数 + 2）。
  final int itemIndex;
  final int barItemCount;
  final IconData icon;
  final String tooltip;

  /// Enter/Space 行为（重开钮 = 开菜单[空栈空转] / 收起钮 = 收起舞台）；
  /// [openMenuOnArrowDown] 为真时 ↓ 同入口。
  final VoidCallback onActivate;
  final void Function(int targetIndex) onMoveFocus;
  final bool openMenuOnArrowDown;
  final bool enabled;

  @override
  State<_StageBarAction> createState() => _StageBarActionState();
}

class _StageBarActionState extends State<_StageBarAction> {
  bool _hovered = false;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.onMoveFocus(widget.itemIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.onMoveFocus(widget.itemIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      widget.onMoveFocus(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      widget.onMoveFocus(widget.barItemCount - 1);
      return KeyEventResult.handled;
    }
    final isActivate =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    if (isActivate) {
      // 空栈空转也 handled（S9 边界：不开菜单、不冒泡）。
      widget.onActivate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown && widget.openMenuOnArrowDown) {
      widget.onActivate(); // ↓ 在重开钮 = 开菜单（空栈空转）
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final enabled = widget.enabled;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        // 禁用态点击不开菜单：onTap 空转（节点保持可聚焦 / tooltip 照常）。
        onTap: enabled ? widget.onActivate : () {},
        child: Tooltip(
          // §0.4：tooltip 同时承载 hover 与键盘聚焦。
          message: widget.tooltip,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: AnimatedContainer(
                key: widget.actionKey,
                duration: AppDesignSystem.durationNormal,
                curve: AppDesignSystem.curveDefault,
                width: 28,
                height: AppDesignSystem.tabBarHeight,
                color: enabled && _hovered ? colors.bgTertiary : Colors.transparent,
                child: Center(
                  child: Icon(
                    widget.icon,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 列型检测（网格 / 图表槽共用；沿 results_widget `_detectColumnTypes` 口径，
/// 纯静态计算）。采样上限由 detectColumnType 自身保证（500 行）。
Map<String, ColumnDataType> _detectColumnTypes(AgentResultRef ref) {
  final types = <String, ColumnDataType>{};
  for (final column in ref.columns) {
    types[column] = ResultFilterService.detectColumnType(ref.rows, column);
  }
  return types;
}

/// 网格内容槽：只读消费 result_renderer_plugin 注册表（sqlRows 形态注册序
/// 首个 = 默认视图 table 渲染器），零契约改动；容器不套卡框，0 行沿既有
/// 「No data」空态（results_widget 同款）。
class _StageGridContent extends StatefulWidget {
  const _StageGridContent({required this.tab, this.registry});

  final WorkbenchStageTab tab;
  final PluginRegistry? registry;

  @override
  State<_StageGridContent> createState() => _StageGridContentState();
}

class _StageGridContentState extends State<_StageGridContent> {
  Map<String, ColumnDataType> _columnTypes = const {};

  @override
  void initState() {
    super.initState();
    final ref = widget.tab.resultRef;
    if (ref != null) {
      _columnTypes = _detectColumnTypes(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ref = widget.tab.resultRef;
    if (ref == null || ref.rows.isEmpty) {
      return Center(child: Text(l10n.commonNoData));
    }
    final registry = widget.registry ?? defaultPluginRegistry;
    final renderers = registry.resultRenderersFor(
      shape: ResultDataShape.sqlRows,
    );
    if (renderers.isEmpty) {
      return Center(child: Text(l10n.commonError));
    }
    final result = ExecutionResult(
      statement: SQLStatement(
        index: 0,
        sql: ref.sql,
        type: SQLType.select,
        lineStart: 0,
        lineEnd: 0,
      ),
      success: true,
      data: ref.rows,
      executionTime: Duration.zero,
    );
    return renderers.first.build(
      context,
      ResultRenderContext(
        result: result,
        rows: ref.rows,
        columns: ref.columns,
        columnTypes: _columnTypes,
      ),
    );
  }
}

/// 结构卡内容槽（§5.3）：分组标题 11 w600 textMuted（列/索引/外键/DDL）；
/// 数据行 24（workbenchDenseRowHeight）：列名 mono 12 textPrimary + 类型
/// mono 11 textSecondary + 徽标（PK / NN / 默认值，bgTertiary + 11
/// textSecondary）；DDL 块 codeBlockBg / mono 11 / 上限 360 内滚。
/// 单滚动区（结构分组共享一个 SingleChildScrollView，不嵌套外层滚动）。
class _StageStructureContent extends StatelessWidget {
  const _StageStructureContent({required this.tab});

  final WorkbenchStageTab tab;

  @override
  Widget build(BuildContext context) {
    final data = tab.structure;
    if (data == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            context,
            tableColumnsLabel(context),
            data.columns.map((c) => _StructureColumnRow(column: c)),
          ),
          if (data.indexes.isNotEmpty)
            _buildSection(
              context,
              tableIndexesLabel(context),
              data.indexes.map((i) => _StructureIndexRow(index: i)),
            ),
          if (data.foreignKeys.isNotEmpty)
            _buildSection(
              context,
              foreignKeysLabel(context),
              data.foreignKeys.map((f) => _StructureFkRow(foreignKey: f)),
            ),
          if (data.ddl != null && data.ddl!.isNotEmpty)
            _buildDdlSection(context, data.ddl!),
        ],
      ),
    );
  }

  // 分组标签复用既有 l10n key（本任务禁改 ARB）：
  String tableColumnsLabel(BuildContext context) =>
      AppLocalizations.of(context)!.tableColumns;
  String tableIndexesLabel(BuildContext context) =>
      AppLocalizations.of(context)!.tableIndexes;
  String foreignKeysLabel(BuildContext context) =>
      AppLocalizations.of(context)!.sidebarForeignKeys;

  Widget _buildSection(
    BuildContext context,
    String title,
    Iterable<Widget> rows,
  ) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space2_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
            child: Text(
              title,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  Widget _buildDdlSection(BuildContext context, String ddl) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space2_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
            child: Text(
              l10n.snippetCategoryDDL,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                fontWeight: FontWeight.w600,
                color: colors.textMuted,
              ),
            ),
          ),
          _StructureDdlBlock(ddl: ddl),
        ],
      ),
    );
  }

  /// 结构行徽标：bgTertiary + 11 textSecondary + radiusSm（沿类型徽标语法）。
  static Widget badge(BuildContext context, String text) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          color: colors.textSecondary,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        ),
      ),
    );
  }
}

/// DDL 块（_buildDdlSection 的正文部分）。
class _StructureDdlBlock extends StatelessWidget {
  const _StructureDdlBlock({required this.ddl});

  final String ddl;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: AppDesignSystem.toolCardContentMaxHeight,
      ),
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.codeBlockBg,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SelectableText(
            ddl,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              height: 1.4,
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// 列数据行：列名 mono 12 textPrimary + 类型 mono 11 textSecondary +
/// 徽标（PK / NN / 默认值）。
class _StructureColumnRow extends StatelessWidget {
  const _StructureColumnRow({required this.column});

  final DbColumn column;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final mono = TextStyle(
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    );
    return SizedBox(
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              column.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              column.type,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (column.isPrimaryKey) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _StageStructureContent.badge(context, 'PK'),
          ],
          if (!column.isNullable) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _StageStructureContent.badge(context, 'NN'),
          ],
          if (column.defaultValue != null &&
              column.defaultValue!.isNotEmpty) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _StageStructureContent.badge(context, column.defaultValue!),
          ],
        ],
      ),
    );
  }
}

/// 索引数据行：名称 + 列集合 + UNIQUE 徽标（技术字符串不参与 l10n）。
class _StructureIndexRow extends StatelessWidget {
  const _StructureIndexRow({required this.index});

  final DbIndex index;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final mono = TextStyle(
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    );
    return SizedBox(
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              index.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Flexible(
            child: Text(
              index.columns.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          if (index.isUnique) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _StageStructureContent.badge(context, 'UNIQUE'),
          ],
        ],
      ),
    );
  }
}

/// 外键数据行：`列 → 引用表.引用列`。
class _StructureFkRow extends StatelessWidget {
  const _StructureFkRow({required this.foreignKey});

  final ForeignKey foreignKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final mono = TextStyle(
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    );
    return SizedBox(
      height: AppDesignSystem.workbenchDenseRowHeight,
      child: Row(
        children: [
          Expanded(
            child: Text(
              foreignKey.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space1_5),
          Flexible(
            child: Text(
              '${foreignKey.column} → '
              '${foreignKey.referencedTable}.${foreignKey.referencedColumn}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono.copyWith(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 编辑器内容槽：既有 SQL 编辑器组件（ReSqlEditor）载入不自动执行
/// （AC5.2——本组件不含任何执行入口）；未保存判定 = 当前文本 ≠ 载入 SQL，
/// 经 controller 回写 tab.dirty（tab 上 6px 点 + 关闭确认的判据）。
class _StageEditorContent extends StatefulWidget {
  const _StageEditorContent({required this.tab, required this.stageController});

  final WorkbenchStageTab tab;
  final WorkbenchStageController stageController;

  @override
  State<_StageEditorContent> createState() => _StageEditorContentState();
}

class _StageEditorContentState extends State<_StageEditorContent> {
  late final ReSqlEditorController _editor;

  @override
  void initState() {
    super.initState();
    _editor = ReSqlEditorController(text: widget.tab.initialSql);
    _editor.addTextChangeListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant _StageEditorContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // AC5.5 复用装载：controller 替换实例（initialSql 变化）→ 不可撤销重载
    // （光标归零清历史，沿经典 tab 切换装载语义）。dirty 已在 open 侧归零。
    if (oldWidget.tab.initialSql != widget.tab.initialSql) {
      _editor.loadText(widget.tab.initialSql);
    }
  }

  @override
  void dispose() {
    _editor.removeTextChangeListener(_onTextChanged);
    _editor.dispose();
    super.dispose();
  }

  void _onTextChanged(String text) {
    widget.stageController.markEditorDirty(
      widget.tab.id,
      text != widget.tab.initialSql,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReSqlEditor(controller: _editor);
  }
}

/// 图表内容槽：复用 ChartView（chart_result_renderer 能力语义）；
/// 列型不适配（无数值列，`WorkbenchStageController.isChartable`）→ 内联错误：
/// circleAlert 12 error + agentStageChartMismatch 11 textPrimary +
/// [在经典中打开] 出口（回调注入，T27 接线 WorkbenchOpenInClassic），
/// **不弹窗**（AC5.3）。
class _StageChartContent extends StatelessWidget {
  const _StageChartContent({required this.tab, this.onOpenInClassic});

  final WorkbenchStageTab tab;
  final void Function(String sql)? onOpenInClassic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ref = tab.resultRef;
    if (ref == null || !WorkbenchStageController.isChartable(ref)) {
      return _buildMismatch(context, l10n, ref?.sql ?? '');
    }
    return ChartView(data: ref.rows, columnTypes: _detectColumnTypes(ref));
  }

  Widget _buildMismatch(
    BuildContext context,
    AppLocalizations l10n,
    String sql,
  ) {
    final colors = context.themeColors;
    return Center(
      key: WorkbenchStage.chartMismatchKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.circleAlert, size: 12, color: colors.error),
              const SizedBox(width: AppDesignSystem.space1),
              Flexible(
                child: Text(
                  l10n.agentStageChartMismatch,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space3),
          // 出口：icon 12 accentBlue（图形线）+ 文字 textPrimary（§0.2）。
          InkWell(
            key: WorkbenchStage.openInClassicButtonKey,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            onTap: () => onOpenInClassic?.call(sql),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.externalLink,
                    size: 12,
                    color: colors.accentBlue,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Text(
                    l10n.workbenchActionOpenInClassic,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 执行结果摘要内容槽（v2 B1，任务书 §6.8 内容规格）：写入/DDL 批次的逐
/// 语句执行投影。
///
/// 结构：顶部摘要条（`workbenchExecutionSummary` 三占位符：总语句数 /
/// 失败数 / 总耗时；部分失败 = 条左侧 error 图标 + accentRed 边框）+ 逐
/// 语句行列表（行高 [AppDesignSystem.workbenchDenseRowHeight] 24 密排）。
/// 失败行**置顶**（组内保持原执行序）；跳过行弱化（textMuted）。
///
/// 对比度红线（v1 §3.6 / §5-5）：状态语义只由图标与边框承载——绿/红仅作
/// 图标色与边框色，正文文字恒 textPrimary（跳过行 textMuted 弱化）。
/// 纯只读投影：零动作按钮（无重跑/编辑/导出入口）。
class _StageExecutionContent extends StatelessWidget {
  const _StageExecutionContent({required this.tab});

  final WorkbenchStageTab tab;

  /// 摘要条（测试探针）。
  static const Key summaryKey = ValueKey('workbench_execution_summary');

  /// 语句行（[index] = 展示序下标，失败置顶后的序）。
  static Key rowKey(int index) => ValueKey('workbench_execution_row_$index');

  /// 失败行「详情」展开开关（[index] = 展示序下标）。
  static Key detailToggleKey(int index) =>
      ValueKey('workbench_execution_detail_$index');

  /// 失败行错误全文块（[index] = 展示序下标）。
  static Key errorBlockKey(int index) =>
      ValueKey('workbench_execution_error_$index');

  @override
  Widget build(BuildContext context) {
    final data = tab.execution;
    if (data == null || data.rows.isEmpty) {
      return const SizedBox.shrink();
    }
    // 失败行置顶（稳定分组：两组内各自保持原执行序）。
    final ordered = <StageExecutionRow>[
      for (final row in data.rows)
        if (row.status == StageExecutionStatus.failed) row,
      for (final row in data.rows)
        if (row.status != StageExecutionStatus.failed) row,
    ];
    var failedCount = 0;
    var totalMs = 0;
    for (final row in data.rows) {
      if (row.status == StageExecutionStatus.failed) failedCount++;
      totalMs += row.durationMs ?? 0;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryBar(context, data.rows.length, failedCount, totalMs),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: ListView.builder(
            itemCount: ordered.length,
            itemBuilder: (context, index) => _StageExecutionRowTile(
              key: rowKey(index),
              row: ordered[index],
              detailToggleKey: detailToggleKey(index),
              errorBlockKey: errorBlockKey(index),
            ),
          ),
        ),
      ],
    );
  }

  /// 摘要条：bgSecondary 底 + 1px 边框（部分失败翻 accentRed + 左侧 error
  /// 图标）；摘要文字恒 textPrimary（状态语义不由正文色承载）。
  Widget _buildSummaryBar(
    BuildContext context,
    int total,
    int failedCount,
    int totalMs,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final hasFailure = failedCount > 0;
    return Container(
      key: summaryKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: AppDesignSystem.space1_5,
      ),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: hasFailure ? colors.accentRed : colors.dividerColor,
        ),
      ),
      child: Row(
        children: [
          if (hasFailure) ...[
            Icon(LucideIcons.triangleAlert, size: 12, color: colors.accentRed),
            const SizedBox(width: AppDesignSystem.space1),
          ],
          Expanded(
            child: Text(
              l10n.workbenchExecutionSummary(total, failedCount, totalMs),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// execution tab 逐语句行（24 密排）：[状态图标 12] + mono SQL 单行
/// ellipsis（tooltip 全文）+ 影响行数（`workbenchExecutionAffectedRows`）
/// + 耗时 ms；失败行行尾「详情」开关展开错误全文（mono 11 codeBlockBg 可
/// 折块——形态沿 result_table_card `_ErrorDetailBlock` 语法自写，不抽取
/// 复用：该文件归 B2 领土，重复留待日后清理，已知项入汇报）。
class _StageExecutionRowTile extends StatefulWidget {
  const _StageExecutionRowTile({
    super.key,
    required this.row,
    required this.detailToggleKey,
    required this.errorBlockKey,
  });

  final StageExecutionRow row;

  /// 「详情」开关探针 key（父级按展示序生成）。
  final Key detailToggleKey;

  /// 错误全文块探针 key（父级按展示序生成）。
  final Key errorBlockKey;

  @override
  State<_StageExecutionRowTile> createState() => _StageExecutionRowTileState();
}

class _StageExecutionRowTileState extends State<_StageExecutionRowTile> {
  /// 错误全文块展开态（默认收起：多失败行全展开噪音大；点「详情」展开）。
  bool _expanded = false;

  /// 状态图标（子集内选型）：done=circleCheckBig / failed=triangleAlert /
  /// skipped=skipForward（沿 schema_sync_executor skipped 同款映射先例）。
  static IconData _statusIcon(StageExecutionStatus status) {
    return switch (status) {
      StageExecutionStatus.done => LucideIcons.circleCheckBig,
      StageExecutionStatus.failed => LucideIcons.triangleAlert,
      StageExecutionStatus.skipped => LucideIcons.skipForward,
    };
  }

  /// 状态图标色（语义承载面：done=success / failed=error / skipped=
  /// textMuted——绿/红仅作图标色，不作正文色，v1 §3.6）。
  static Color _statusColor(ThemeColors colors, StageExecutionStatus status) {
    return switch (status) {
      StageExecutionStatus.done => colors.success,
      StageExecutionStatus.failed => colors.error,
      StageExecutionStatus.skipped => colors.textMuted,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final row = widget.row;
    final failed = row.status == StageExecutionStatus.failed;
    final skipped = row.status == StageExecutionStatus.skipped;
    final affectedRows = row.affectedRows;
    final durationMs = row.durationMs;
    final error = row.error;
    final mono = TextStyle(
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: AppDesignSystem.workbenchDenseRowHeight,
          child: Row(
            children: [
              Icon(
                _statusIcon(row.status),
                size: 12,
                color: _statusColor(colors, row.status),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Tooltip(
                  message: row.sql,
                  child: Text(
                    row.sql,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono.copyWith(
                      fontSize: AppDesignSystem.fontSizeSm,
                      color: skipped ? colors.textMuted : colors.textPrimary,
                    ),
                  ),
                ),
              ),
              if (affectedRows != null) ...[
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  l10n.workbenchExecutionAffectedRows(affectedRows),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textMuted,
                  ),
                ),
              ],
              if (durationMs != null) ...[
                const SizedBox(width: AppDesignSystem.space2),
                // 耗时为技术数值（「N ms」沿结果卡元信息行字面量口径）。
                Text(
                  '$durationMs ms',
                  maxLines: 1,
                  style: mono.copyWith(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textMuted,
                  ),
                ),
              ],
              if (failed) ...[
                const SizedBox(width: AppDesignSystem.space2),
                _buildDetailToggle(l10n, colors),
              ],
            ],
          ),
        ),
        if (failed && _expanded && error != null && error.isNotEmpty)
          _buildErrorBlock(colors, error),
      ],
    );
  }

  /// 「详情」开关（失败行行尾；错误全文块初始收起）。
  Widget _buildDetailToggle(AppLocalizations l10n, ThemeColors colors) {
    return InkWell(
      key: widget.detailToggleKey,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.workbenchErrorDetail,
              maxLines: 1,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textSecondary,
              ),
            ),
            Icon(
              _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 12,
              color: colors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  /// 错误全文块（mono 11 / codeBlockBg / 上限高内滚，沿 `_ErrorDetailBlock`
  /// 与 `_StructureDdlBlock` 同款语法；SelectableText 可复制）。
  Widget _buildErrorBlock(ThemeColors colors, String error) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: AppDesignSystem.toolCardContentMaxHeight,
        ),
        child: SingleChildScrollView(
          child: Container(
            key: widget.errorBlockKey,
            width: double.infinity,
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            decoration: BoxDecoration(
              color: colors.codeBlockBg,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SelectableText(
              error,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                height: 1.4,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// optimization 内容槽（2b.3，R6）：查询优化三层内容 tab——顶部 SQL 上下文
/// 块（mono SelectableText，沿 [_StructureDdlBlock] 形态自写不抽取）+ 下方
/// [QueryPlanVisualizer] 零改动复用承载（计划树 + 瓶颈 + 索引推荐 + 重写
/// 建议四层，R6 双头维护禁令）。
///
/// 零写手势（任务书 §6.4 一票否决项）：「应用此索引」= 回调填
/// [WorkbenchStageController.openEditorSlot]（编辑器槽载入不自动执行，
/// AC5.5 脏槽保护既有）——填槽不执行，无任何 SQL 执行入口。visualizer
/// 内部英文硬编码属既有经典组件面，l10n 改造登记跟进项不并入本批。
class _StageOptimizationContent extends StatelessWidget {
  const _StageOptimizationContent({
    required this.tab,
    required this.stageController,
  });

  final WorkbenchStageTab tab;
  final WorkbenchStageController stageController;

  @override
  Widget build(BuildContext context) {
    final data = tab.optimization;
    if (data == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSqlContextBlock(context, data.sql),
        const SizedBox(height: AppDesignSystem.space2_5),
        Expanded(
          // 单滚动区（沿 query_editor_widget.dart:2002-2009 经典计划 dialog
          // 同款包裹）：visualizer 自身无内滚，大载荷需外层滚动。
          child: SingleChildScrollView(
            child: QueryPlanVisualizer(
              report: data.report,
              // 填编辑器槽不执行（R6：「应用此索引」的唯一合法落点）。
              onApplyDdl: stageController.openEditorSlot,
            ),
          ),
        ),
      ],
    );
  }

  /// SQL 上下文头（mono SelectableText + codeBlockBg + 上限高内滚——沿
  /// [_StructureDdlBlock] 同款语法自写不抽取；上限高为任务书允许自决项，
  /// 采建议值 [AppDesignSystem.toolCardContentMaxHeight]）。
  Widget _buildSqlContextBlock(BuildContext context, String sql) {
    final colors = context.themeColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: AppDesignSystem.toolCardContentMaxHeight,
      ),
      child: SingleChildScrollView(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.codeBlockBg,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SelectableText(
            sql,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              height: 1.4,
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
