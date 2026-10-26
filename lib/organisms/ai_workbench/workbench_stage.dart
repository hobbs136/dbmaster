//! AI 工作台舞台（T24，ui 规格 design-ai-agent-ui.md §5 面五；
//! 批3 T7 容器收敛重构，.specs/tasks-v3.5-ui.md §3-B01 + §4-P3）。
//!
//! A2 净新增结构：tab 体系（增删切 / 关闭 / pin 标记 / dirty 标记 /
//! tab 条 32 / tab 标签上限 200）+ 内容槽 + 空态三元素 + 常驻开合控制语义
//! （[WorkbenchStageController.stageVisible]，由 T27 shell 消费布局，本组件
//! 自身不因可见性消失——是否入树由宿主决定）。
//!
//! **容器模型（B-01，10 kind → 4 容器）**：tab 类型 =
//! [WorkbenchStageContainerKind]（sqlStudio / dataViz / schema / diagnostics
//! 四容器），每容器内再分 [WorkbenchStageSubKind] 子态（分段控件切换，
//! 子视图 IndexedStack 保活）。旧 10 kind 的归属映射（冻结）：
//! editor→sqlStudio/edit；optimization→sqlStudio/diff；grid→dataViz/grid；
//! chart→dataViz/chart；structure→schema（默认 columns）；execution→
//! diagnostics/explainPlan；observe→diagnostics/liveMonitor；
//! sessionList/history/savedQueries **退出舞台枚举**（左侧 196 内容栏承载，
//! 收窄态活动条点击 = 展开 rail 抽屉，见 workbench_session_rail.dart）。
//! 无持久化（内存态），不保留旧枚举、不写运行时映射表——Dart 枚举编译期
//! 完备，消费方经编译错误驱动全仓迁移。
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
//! padding space3 + 无卡框。tab 条标签恒为**容器级标签**（注册表单源）；
//! payload title 只进产物芯片与重开菜单。容器内容（design-v3.5-ui §2.3
//! Task 3.1）：分段控件 h22 / 条 32，选中 primaryContainer + accent 边。
//! dataViz：grid/chart 共享同一结果集（chart 仅换渲染**不重新取数**，子视图
//! IndexedStack 保活，chart 子态浮现 32px 轴条）；sqlStudio：edit=编辑器槽 /
//! diff=优化对比 + 可折叠 Optimization Summary（默认展开当有变更）；schema：
//! columns/indexes/ddl 三子段 + AI 推测字段虚线框（不写回）+ Mongo 集合分支
//! （2b.2b，单视图无分段）；diagnostics：explainPlan（execution 静态投影）/
//! liveMonitor（observe 实时语义，2b.1）。
//! 图表列型不适配 → 内联错误 + [在经典中打开] 出口不弹窗（AC5.3）。

import 'dart:math' as math;

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
import 'workbench_stage_tab_visuals.dart';

/// 舞台容器类型（§5.2；批3 B-01：10 kind → 4 容器收敛）。
///
/// 类型 → 图标/标签映射的唯一事实源 = [WorkbenchStageContainerKindVisuals]
/// （workbench_stage_tab_visuals.dart，C1 注册化）；本枚举只定义类型集合。
/// 容器内子态见各容器专属枚举（[SqlStudioSubKind] / [DataVizSubKind] /
/// [SchemaSubKind] / [DiagnosticsSubKind]，统一实现 [WorkbenchStageSubKind]
/// 标记接口——分段路由的公共类型面）。
///
/// 旧 kind 归属（冻结映射）：editor→sqlStudio/edit；
/// optimization→sqlStudio/diff；grid→dataViz/grid；chart→dataViz/chart；
/// structure→schema（默认 columns）；execution→diagnostics/explainPlan；
/// observe→diagnostics/liveMonitor；sessionList/history/savedQueries 退出
/// 舞台枚举（左侧 196 内容栏承载）。
enum WorkbenchStageContainerKind { sqlStudio, dataViz, schema, diagnostics }

/// 容器子态标记接口（B-01）：四容器子枚举共同实现，作为
/// [WorkbenchStageTab.subKind] 与分段路由的公共类型面。禁止枚举外的实现
/// （舞台路由按四容器子枚举完备 switch）。
abstract interface class WorkbenchStageSubKind {}

/// SQL Studio 容器子态：edit = 编辑器槽（ReSqlEditor，载入不自动执行）；
/// diff = 优化对比（Optimization Summary + 计划可视化，2b.3 语义）。
enum SqlStudioSubKind implements WorkbenchStageSubKind { edit, diff }

/// Data & Viz 容器子态：grid = 结果网格；chart = 图表（共享同一结果集，
/// chart 仅换渲染不重新取数）。
enum DataVizSubKind implements WorkbenchStageSubKind { grid, chart }

/// Schema 容器子态：columns = 列（含 AI 推测字段虚线框）；indexes = 索引
/// （含外键）；ddl = CREATE TABLE 语句。
enum SchemaSubKind implements WorkbenchStageSubKind { columns, indexes, ddl }

/// Diagnostics 容器子态：explainPlan = execution 静态投影（写入/DDL 批次
/// 执行结果摘要）；liveMonitor = observe 实时观察（现 2b.1 observe 语义）。
enum DiagnosticsSubKind implements WorkbenchStageSubKind {
  explainPlan,
  liveMonitor,
}

/// AI 推测字段值对象（批3 P3-1 步骤 3）：schema/columns 子段的虚线框行——
/// AI 从数据/文档推测出的列（区别于 describe 四件实查列），**不写回
/// schema**（纯展示，无任何写路径）。
class StageAiInferredColumn {
  /// 常量构造；字段不可变。
  const StageAiInferredColumn({required this.column, required this.note});

  /// 推测列的形态描述（复用 [DbColumn] 值对象：名称/类型/可空性）。
  final DbColumn column;

  /// 推测依据注记（经 [AppLocalizations.agentStageAiInferred] 上屏）。
  final String note;
}

/// 结构卡内容（describe_table 四件：列 / 索引 / 外键 / DDL + AI 推测字段）。
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
    this.aiInferredColumns = const [],
  });

  /// 表名（tab 标签默认值）。
  final String tableName;

  /// 列定义（describe 四件之一）。
  final List<DbColumn> columns;

  /// 索引定义（describe 四件之二）。
  final List<DbIndex> indexes;

  /// 外键定义（describe 四件之三；schema 容器归入 indexes 子段呈现）。
  final List<ForeignKey> foreignKeys;

  /// CREATE TABLE 语句（describe 四件之四；null = 无 DDL 段）。
  final String? ddl;

  /// AI 推测字段（批3 P3：默认空 = 无推测；虚线框呈现，不写回 schema）。
  final List<StageAiInferredColumn> aiInferredColumns;
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
/// 批3 B-01：tab 身份 = [container]（容器级），[subKind] 为容器内当前选中
/// 子态（分段控件切换经 [WorkbenchStageController.selectSubKind] 回写）。
/// 同容器多 tab 允许并存（各持各的载荷：多结果集 / 多编辑器槽 / 多表结构
/// ——去重键沿用旧 open 语义，见各 openXxx 注释）。
///
/// 构造私有：tab 只能由 [WorkbenchStageController] 创建（单一事实源）；
/// T25 产物条只读消费字段。编辑器槽的 [dirty] 由内容组件经
/// `markEditorDirty` 回写（文本 ≠ 载入 SQL 即脏）。
@immutable
class WorkbenchStageTab {
  const WorkbenchStageTab._({
    required this.id,
    required this.container,
    required this.subKind,
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

  /// 容器类型（tab 条身份与图标/标签的唯一依据）。
  final WorkbenchStageContainerKind container;

  /// 容器内当前选中子态（分段控件状态；产物芯片路由恢复位）。
  final WorkbenchStageSubKind subKind;

  /// 标签；null = 产物芯片/重开菜单回退容器标签（注册表单源）。tab 条恒
  /// 显示容器标签（B-01：容器收敛后同容器 tab 以容器身份呈现）。
  final String? title;

  /// dataViz 容器 tab 的结果引用（内存引用，不复制；grid/chart 子态共享）。
  final AgentResultRef? resultRef;

  /// schema 容器 tab 的 describe 数据（SQL 表分支）。
  final StageStructureData? structure;

  /// schema 容器 tab 的 Mongo 集合 schema 数据（2b.2b；与 [structure] 互斥——
  /// SQL 表走 [structure]，Mongo 集合走本字段；mongo tab 的 structure 恒
  /// null，SQL 分支 match `structure?.tableName` 与 mongo tab 天然互斥）。
  final StageMongoStructureData? mongoStructure;

  /// diagnostics 容器 tab 的执行结果投影（B1 explainPlan 子态；复用刷新时
  /// 整载荷替换）。
  final StageExecutionData? execution;

  /// sqlStudio 容器 tab 的性能分析报告（2b.3 diff 子态；同 SQL 复用刷新时
  /// 整载荷替换）。
  final StageOptimizationData? optimization;

  /// chart 子态的请求类型（line/bar/pie/scatter；null = 推荐模式）。
  final String? chartKind;

  /// 编辑器槽（edit 子态）的载入 SQL（非 sqlStudio tab 为空串）。
  final String initialSql;

  /// 钉入产物条标记（§6.3：产物条 = pinned 子集投影）。
  final bool pinned;

  /// 编辑器槽未保存标记（tab 上 6px 点 + 关闭确认的判据，AC5.5）。
  final bool dirty;

  /// 字段替换（controller 内部状态迁移专用）。
  WorkbenchStageTab copyWith({
    String? title,
    WorkbenchStageSubKind? subKind,
    String? chartKind,
    String? initialSql,
    StageStructureData? structure,
    StageMongoStructureData? mongoStructure,
    StageExecutionData? execution,
    StageOptimizationData? optimization,
    bool? pinned,
    bool? dirty,
  }) => WorkbenchStageTab._(
    id: id,
    container: container,
    subKind: subKind ?? this.subKind,
    title: title ?? this.title,
    resultRef: resultRef,
    structure: structure ?? this.structure,
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

  // ── 打开（自动开舞台 + 激活；§5.3 打开时机；B-01 容器路由）──────────

  /// dataViz 容器 tab（grid 子态）：呈现结果引用全量行（行限内）。同 refId
  /// 的 dataViz tab 已存在 → 复用并激活（切回 grid 子态；tab 标题以新值为
  /// 准），不重复建 tab。
  WorkbenchStageTab openGrid(AgentResultRef ref, String? title) {
    return _openTab(
      container: WorkbenchStageContainerKind.dataViz,
      subKind: DataVizSubKind.grid,
      title: title,
      resultRef: ref,
      match: (t) =>
          t.container == WorkbenchStageContainerKind.dataViz &&
          t.resultRef?.refId == ref.refId,
    );
  }

  /// dataViz 容器 tab（chart 子态）：同 refId 的 dataViz tab（无论当前子态）
  /// → 复用并切到 chart 子态（**收敛为单容器 tab**，B-01 UI35-306a：grid
  /// 与 chart 共享同一结果集，chart 仅换渲染不重新取数）；未命中 → 新建。
  /// chartKind 以新请求为准。
  WorkbenchStageTab openChart(AgentResultRef ref, String? kind) {
    return _openTab(
      container: WorkbenchStageContainerKind.dataViz,
      subKind: DataVizSubKind.chart,
      title: null,
      resultRef: ref,
      chartKind: kind,
      match: (t) =>
          t.container == WorkbenchStageContainerKind.dataViz &&
          t.resultRef?.refId == ref.refId,
    );
  }

  /// schema 容器 tab（columns 子态）：按表名去重（同表重开 = 复用刷新载荷
  /// + 回 columns 子态）；表名即默认标签（比容器标签信息量高——产物芯片与
  /// 重开菜单消费）。
  WorkbenchStageTab openStructure(StageStructureData data) {
    return _openTab(
      container: WorkbenchStageContainerKind.schema,
      subKind: SchemaSubKind.columns,
      // 表名即默认标签（芯片/重开菜单回退值）。
      title: data.tableName,
      structure: data,
      match: (t) =>
          t.container == WorkbenchStageContainerKind.schema &&
          t.structure?.tableName == data.tableName,
    );
  }

  /// schema 容器 tab（Mongo 集合分支，2b.2b）：match = 容器 schema 且
  /// mongoStructure 非空且 connectionId + collectionName 双等——同集合同
  /// 连接重开 = 复用刷新（载荷替换，title 以新值为准）；不同连接或不同集合
  /// 各开各的。title 默认 = collectionName。
  ///
  /// 与 SQL 表分支零串味：SQL match 走 `structure?.tableName`，mongo tab
  /// 的 structure 恒 null、SQL tab 的 mongoStructure 恒 null，同表/集合名
  /// 也各自独立成 tab（零改动）。
  ///
  /// 复用分支自写（沿 [openExecution] 先例，任务书 §6.3 允许自决项）：
  /// 复用需替换 [StageMongoStructureData] 载荷，[_openTab] 既有复用语义
  /// （只换 title/chartKind）保持不变——grid/structure 零变化。
  WorkbenchStageTab openMongoStructure(StageMongoStructureData data) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final StageMongoStructureData? existing = t.mongoStructure;
      if (t.container != WorkbenchStageContainerKind.schema ||
          existing == null) {
        continue;
      }
      if (existing.connectionId == data.connectionId &&
          existing.collectionName == data.collectionName) {
        final reused = t.copyWith(
          title: data.collectionName,
          structure: null,
          mongoStructure: data,
          subKind: SchemaSubKind.columns,
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
      container: WorkbenchStageContainerKind.schema,
      subKind: SchemaSubKind.columns,
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

  /// sqlStudio 容器 tab（edit 子态）：载入 SQL 不自动执行（AC5.2；执行语义
  /// 不在本组件）。AC5.5 槽策略：目标槽（最近一个 sqlStudio tab）有未保存
  /// 修改 → 新开槽，绝不覆盖用户未保存内容；干净则复用装载（optimization
  /// 落地的容器 tab 同样持有空编辑槽，可被复用——容器语义：一个 SQL Studio
  /// 工作面同时承载编辑与 Diff）。
  WorkbenchStageTab openEditorSlot(String sql) {
    for (final tab in _tabs.reversed) {
      if (tab.container != WorkbenchStageContainerKind.sqlStudio) continue;
      if (tab.dirty) break; // 目标槽脏 → 走新开槽（AC5.5）
      final reloaded = tab.copyWith(
        initialSql: sql,
        dirty: false,
        subKind: SqlStudioSubKind.edit,
      );
      _tabs[_tabs.indexOf(tab)] = reloaded;
      _activeIndex = _tabs.indexOf(reloaded);
      _stageVisible = true;
      notifyListeners();
      return reloaded;
    }
    return _openTab(
      container: WorkbenchStageContainerKind.sqlStudio,
      subKind: SqlStudioSubKind.edit,
      title: null,
      initialSql: sql,
    );
  }

  /// sqlStudio 容器 tab（diff 子态，2b.3 R6 去重键语义）：match = 容器
  /// sqlStudio 且 `optimization.sql == data.sql`（原 SQL 精确串）→ 复用并
  /// **替换数据载荷刷新**（同 SQL 重解释 = 同 tab 刷新不累积）；未命中且
  /// 存在**无 optimization 载荷**的 sqlStudio tab → 落地该 tab（容器收敛：
  /// 编辑与 Diff 同容器）；否则新建追加激活。均置舞台可见。
  WorkbenchStageTab openOptimization(StageOptimizationData data) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final StageOptimizationData? existing = t.optimization;
      if (t.container == WorkbenchStageContainerKind.sqlStudio &&
          existing != null &&
          existing.sql == data.sql) {
        final reused = t.copyWith(
          optimization: data,
          subKind: SqlStudioSubKind.diff,
        );
        _tabs[i] = reused;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return reused;
      }
    }
    // 容器收敛落地：最后一个无 optimization 载荷的 sqlStudio tab。
    for (var i = _tabs.length - 1; i >= 0; i--) {
      final t = _tabs[i];
      if (t.container == WorkbenchStageContainerKind.sqlStudio &&
          t.optimization == null) {
        final landed = t.copyWith(
          optimization: data,
          subKind: SqlStudioSubKind.diff,
        );
        _tabs[i] = landed;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return landed;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      container: WorkbenchStageContainerKind.sqlStudio,
      subKind: SqlStudioSubKind.diff,
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

  /// diagnostics 容器 tab（explainPlan 子态，v2 B1 R4 去重键语义）：match =
  /// 容器 diagnostics 且 `execution.tabKey` 命中 → 复用并**替换数据载荷
  /// 刷新**（标题以新值为准——时间戳随批次更新）；未命中且存在**无
  /// execution 载荷**的 diagnostics tab（openObserve 建的 liveMonitor 面）
  /// → 落地该 tab（容器收敛：Explain Plan 与 Live Monitor 同容器双态）；
  /// 否则新建追加激活。均置舞台可见。
  WorkbenchStageTab openExecution(StageExecutionData data) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      final StageExecutionData? existing = t.execution;
      if (t.container == WorkbenchStageContainerKind.diagnostics &&
          existing != null &&
          existing.tabKey == data.tabKey) {
        final reused = t.copyWith(
          title: data.title,
          execution: data,
          subKind: DiagnosticsSubKind.explainPlan,
        );
        _tabs[i] = reused;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return reused;
      }
    }
    // 容器收敛落地：最后一个无 execution 载荷的 diagnostics tab。
    for (var i = _tabs.length - 1; i >= 0; i--) {
      final t = _tabs[i];
      if (t.container == WorkbenchStageContainerKind.diagnostics &&
          t.execution == null) {
        final landed = t.copyWith(
          title: data.title,
          execution: data,
          subKind: DiagnosticsSubKind.explainPlan,
        );
        _tabs[i] = landed;
        _activeIndex = i;
        _stageVisible = true;
        notifyListeners();
        return landed;
      }
    }
    final tab = WorkbenchStageTab._(
      id: _nextId(),
      container: WorkbenchStageContainerKind.diagnostics,
      subKind: DiagnosticsSubKind.explainPlan,
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

  /// diagnostics 容器 tab（liveMonitor 子态，2b.1 R1）：已有 diagnostics
  /// tab → 复用切到 liveMonitor 子态（execution 载荷保留——双态共存）；
  /// 无 → 新建。重复打开（命令面板重复触发）复用激活不重复建（§8-2）；
  /// 舞台不可见时自动可见。内容每次 build 从 effectiveWorkbenchContext
  /// 派生（连接快照不进 tab 数据），锁切换语义由 [WorkbenchObserveContent]
  /// 承担。
  WorkbenchStageTab openObserve() {
    return _openTab(
      container: WorkbenchStageContainerKind.diagnostics,
      subKind: DiagnosticsSubKind.liveMonitor,
      title: null,
      match: (t) => t.container == WorkbenchStageContainerKind.diagnostics,
    );
  }

  /// 产物条钉住（§6.3）：该 ref 无 dataViz tab → 建一个 pinned dataViz tab
  /// （grid 子态）；已有 → 置 pinned（子态保留当前值）。**不改舞台可见性**
  /// （T27 `pinArtifact` 的操作目标）。
  WorkbenchStageTab pinArtifact(AgentResultRef ref, String? label) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      if (t.container == WorkbenchStageContainerKind.dataViz &&
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
      container: WorkbenchStageContainerKind.dataViz,
      subKind: DataVizSubKind.grid,
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
  /// 被移除对象**全容器统一压入最近关闭栈**；[recentlyClosedTabsMax] 封顶
  /// 逐出栈底。sqlStudio tab（编辑器槽所在容器）压栈前丢弃脏标记
  /// （copyWith(dirty: false)）——关闭确认已放弃未保存编辑，复活对象不得
  /// 带脏点；其余字段原样。重开 = 对象原样重新入列（[reopenClosedTab]，
  /// 不走 openXxx 去重路径）。
  void closeTab(int tabIndex) {
    if (tabIndex < 0 || tabIndex >= _tabs.length) return;
    final removed = _tabs.removeAt(tabIndex);
    _recentlyClosed.insert(
      0,
      removed.container == WorkbenchStageContainerKind.sqlStudio &&
              removed.dirty
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

  /// 容器内子态切换（分段控件回写；B-01）：按 id 定位 tab，subKind 变化才
  /// 通知。子视图 IndexedStack 保活——切换只影响展示层，不重建载荷。
  void selectSubKind(String tabId, WorkbenchStageSubKind subKind) {
    for (var i = 0; i < _tabs.length; i++) {
      final t = _tabs[i];
      if (t.id == tabId && t.subKind != subKind) {
        _tabs[i] = t.copyWith(subKind: subKind);
        notifyListeners();
        return;
      }
    }
  }

  /// B-02：还原 pinned 产物（Exit 保留内存槽 → 新 controller）——对象
  /// 原样追加（不走 openXxx 去重路径，沿 [reopenClosedTab] 先例）；无 tab
  /// 时激活补位，**不改舞台可见性**（还原不打断经典界面）。
  void restorePinnedTab(WorkbenchStageTab tab) {
    if (_tabs.any((t) => t.id == tab.id)) return;
    _tabs.add(tab);
    if (_activeIndex < 0) _activeIndex = 0;
    notifyListeners();
  }

  /// B-02：按 id 激活 + 置舞台可见（经典 dock「Pinned artifacts」芯片的
  /// 重进路由；容器 + subKind 随 tab 对象原样恢复）。miss 静默。
  void activateTabById(String tabId) {
    final index = _tabs.indexWhere((t) => t.id == tabId);
    if (index < 0) return;
    _activeIndex = index;
    _stageVisible = true;
    notifyListeners();
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

  /// 打开通用路径（B-01 容器版）：命中 [match] → 复用激活 + 切子态
  /// （title/chartKind 以新值为准，载荷字段沿用旧值——载荷替换语义由各自
  /// openXxx 的自写复用分支承担）；否则新建追加激活。均置舞台可见。
  WorkbenchStageTab _openTab({
    required WorkbenchStageContainerKind container,
    required WorkbenchStageSubKind subKind,
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
          subKind: subKind,
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
      container: container,
      subKind: subKind,
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

/// Exit 跨形态 pinned 产物内存槽（批3 E3.2 / B-02：Exit Workbench 后
/// pinned 状态保留 + 经典 dock「Pinned artifacts」行的数据源）。
///
/// 生命周期：进程级**内存态**（不持久化、应用重启即清）；工作台壳
/// （`ai_workbench_shell.dart`）dispose 时把 controller.pinnedTabs 全量
/// 写回（replaceWith），（重）挂载时还原进新 controller；经典 dock 行
/// 只读消费 [entries]。重进请求（dock 芯片点击）经 [requestReopen] 挂起
/// id——壳挂载态即时消费（激活对应 tab + 置舞台可见），未挂载态由挂载后
/// 的还原流程消费（consumeReopenRequest）。
class WorkbenchPinnedArtifactMemory extends ChangeNotifier {
  List<WorkbenchStageTab> _entries = const <WorkbenchStageTab>[];
  String? _reopenRequestId;

  /// 当前的 pinned 产物快照（时间序；不可变视图）。
  List<WorkbenchStageTab> get entries => List.unmodifiable(_entries);

  /// 是否有待重进请求。
  bool get hasReopenRequest => _reopenRequestId != null;

  /// 全量替换（壳持续同步 / 兜底写回）。元素序列**恒等**（对象身份逐一
  /// 相同）时跳过通知——非 pin 变更（开 tab / 切激活）不打扰 dock 行重建。
  void replaceWith(List<WorkbenchStageTab> tabs) {
    var same = _entries.length == tabs.length;
    if (same) {
      for (var i = 0; i < tabs.length; i++) {
        if (!identical(_entries[i], tabs[i])) {
          same = false;
          break;
        }
      }
    }
    if (same) return;
    _entries = List<WorkbenchStageTab>.unmodifiable(tabs);
    notifyListeners();
  }

  /// 挂起重进请求（dock 芯片点击）。
  void requestReopen(String tabId) {
    _reopenRequestId = tabId;
    notifyListeners();
  }

  /// 取走挂起的重进请求（无则 null）。
  String? consumeReopenRequest() {
    final id = _reopenRequestId;
    _reopenRequestId = null;
    return id;
  }

  /// 清空（测试复位用）。
  void clear() {
    _entries = const <WorkbenchStageTab>[];
    _reopenRequestId = null;
    notifyListeners();
  }
}

/// 进程级单例（不持久化；经典 dock 与工作台壳共用的唯一实例）。
final WorkbenchPinnedArtifactMemory workbenchPinnedArtifactMemory =
    WorkbenchPinnedArtifactMemory();

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

  /// 收起钮（批3 E3.2 / B-02：迁容器 tab 条右端 24×24——原走查修复批 S3
  /// 28 宽收窄）：panelRightClose 14 textSecondary（功能性控件不用
  /// textMuted——FU-11 对比度坑）；tooltip = workbenchCollapseStage
  /// （小写 s，新键；旧 agentStageCollapse 随迁退役）；收起舞台。
  Widget _buildCollapseButton(BuildContext context, int tabCount) {
    final l10n = AppLocalizations.of(context)!;
    return _StageBarAction(
      actionKey: WorkbenchStage.collapseKey,
      focusNode: _collapseFocusNode,
      itemIndex: tabCount + 1,
      barItemCount: tabCount + 2,
      icon: LucideIcons.panelRightClose,
      tooltip: l10n.workbenchCollapseStage,
      onActivate: () => widget.controller.setStageVisible(false),
      onMoveFocus: _focusTab,
      size: 24,
    );
  }

  /// 重开菜单入口：空栈空转；非空弹菜单（锚定重开钮下方、右对齐舞台右缘）。
  void _openReopenMenuOrNoop() {
    if (widget.controller.recentlyClosedTabs.isEmpty) return; // 空栈空转
    _showReopenMenu();
  }

  /// 重开菜单（S8，沿 [_showTabMenu] 的 showMenu + CompactPopupMenuItem
  /// value-then 先例）：显示序 = 栈序（最近关闭在最上）；项 = [容器图标 14
  /// （workbench_stage_tab_visuals 注册表单源消费）] + [标题 12px 上限
  /// 240px ellipsis（title 回退 container.label）]；不加时间戳。项 tap/Enter →
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
                Icon(
                  tab.container.icon,
                  size: 14,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    tab.title ?? tab.container.label(l10n),
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
      // B-01：tab 条标签恒为容器级标签（注册表单源）；payload title 只进
      // 产物芯片与重开菜单（同容器多 tab 以容器身份呈现）。
      displayLabel: tab.container.label(l10n),
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

  /// 关闭请求：sqlStudio tab（编辑器槽所在容器）未保存 → 先确认（AC5.5：
  /// 确认前 tab 不消失），其余类型直接关。
  Future<void> _requestCloseTab(WorkbenchStageTab tab, int index) async {
    if (tab.container == WorkbenchStageContainerKind.sqlStudio &&
        tab.dirty) {
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

  /// 内容槽路由（B-01：container×subKind 两级——外层按容器分发，子态由
  /// 容器内容件内的分段控件管理；C1 纪律：新增 kind 只改枚举 + 注册表 +
  /// 本 switch 三触点）。
  Widget _buildSlot(BuildContext context, WorkbenchStageTab tab) {
    switch (tab.container) {
      case WorkbenchStageContainerKind.sqlStudio:
        // SQL Studio：edit=编辑器槽 / diff=优化对比 + Optimization Summary；
        // 两子态 IndexedStack 保活（编辑未保存内容跨分段切换不丢）。
        return _StageSqlStudioContent(
          tab: tab,
          stageController: widget.controller,
        );
      case WorkbenchStageContainerKind.dataViz:
        // Data & Viz：grid/chart 共享同一结果集（chart 仅换渲染不重新取数，
        // UI35-306）；chart 子态浮现 32px 轴配置条。
        return _StageDataVizContent(
          tab: tab,
          stageController: widget.controller,
          registry: widget.registry,
          onOpenInClassic: widget.onOpenInClassic,
        );
      case WorkbenchStageContainerKind.schema:
        // Schema：Mongo 集合分支 = 单视图（2b.2b，无分段）；SQL 表分支 =
        // columns/indexes/ddl 三子段 + AI 推测字段虚线框（不写回）。
        return _StageSchemaContent(tab: tab);
      case WorkbenchStageContainerKind.diagnostics:
        // Diagnostics：explainPlan = execution 静态投影（纯只读）；
        // liveMonitor = observe 实时（2b.1 语义，零写手势）。
        return _StageDiagnosticsContent(tab: tab);
    }
  }
}

/// 容器子态分段控件（design-v3.5-ui §2.3：分段 h 22 / 条 32；选中
/// primaryContainer + accent 边；先例 results_widget.dart:357 视图切换分段
/// ——自决实现为轻量 InkWell 分段，不用 SegmentedButton（Material 默认高
/// 度压不进 22，且需避开 IconButton 类型面以保「纯只读投影零动作按钮」
/// 断言）。
class _StageSubKindSegments<T extends WorkbenchStageSubKind>
    extends StatelessWidget {
  const _StageSubKindSegments({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  /// 分段全集（渲染序）。
  final List<T> values;

  /// 当前选中子态。
  final T selected;

  /// 分段标签（注册表单源消费）。
  final String Function(T value) labelOf;

  /// 选中回调（回写 [WorkbenchStageController.selectSubKind]）。
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: AppDesignSystem.space1),
            _buildSegment(context, colors, values[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context,
    ThemeColors colors,
    T value,
  ) {
    final isActive = value == selected;
    return InkWell(
      onTap: () => onSelect(value),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: AnimatedContainer(
        duration: AppDesignSystem.durationNormal,
        curve: AppDesignSystem.curveDefault,
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
        decoration: BoxDecoration(
          color: isActive ? colors.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          border: Border.all(
            color: isActive ? colors.accentBlue : colors.dividerColor,
          ),
        ),
        child: Center(
          child: Text(
            labelOf(value),
            maxLines: 1,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              color: isActive ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// SQL Studio 容器内容：分段 [Editor | Diff] + 子视图访问保活
/// （[_SubKindKeepAlive] 模式：子视图仅在首次被选中时构建，此后 IndexedStack
/// 常驻保活——避免隐藏构建 [QueryPlanVisualizer] 的无谓成本）。
///
/// edit 子态 = 编辑器槽（[_StageEditorContent]，载入不自动执行 AC5.2 +
/// 脏标记回写 AC5.5）；diff 子态 = 优化对比（[_StageDiffContent]：可折叠
/// Optimization Summary + SQL 上下文头 + [QueryPlanVisualizer] 零改动复用）。
class _StageSqlStudioContent extends StatefulWidget {
  const _StageSqlStudioContent({
    required this.tab,
    required this.stageController,
  });

  final WorkbenchStageTab tab;
  final WorkbenchStageController stageController;

  @override
  State<_StageSqlStudioContent> createState() => _StageSqlStudioContentState();
}

class _StageSqlStudioContentState extends State<_StageSqlStudioContent> {
  final _SubKindKeepAlive<SqlStudioSubKind> _keepAlive =
      _SubKindKeepAlive<SqlStudioSubKind>();

  @override
  void dispose() {
    _keepAlive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected =
        widget.tab.subKind is SqlStudioSubKind
            ? widget.tab.subKind as SqlStudioSubKind
            : SqlStudioSubKind.edit;
    _keepAlive.visit(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageSubKindSegments<SqlStudioSubKind>(
          values: SqlStudioSubKind.values,
          selected: selected,
          labelOf: (v) => v.label(l10n),
          onSelect: (v) =>
              widget.stageController.selectSubKind(widget.tab.id, v),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: IndexedStack(
            index: selected.index,
            children: [
              _keepAlive.guard(
                SqlStudioSubKind.edit,
                _StageEditorContent(
                  tab: widget.tab,
                  stageController: widget.stageController,
                ),
              ),
              _keepAlive.guard(
                SqlStudioSubKind.diff,
                _StageDiffContent(
                  tab: widget.tab,
                  stageController: widget.stageController,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 子视图访问保活（容器内容件共用模式，批3）：子视图仅在所属子态**首次
/// 选中**时构建（未访问子态以 SizedBox 占位），此后常驻 IndexedStack 保活
/// ——隐藏子视图不再无谓构建（chart 的 fl_chart / diff 的 visualizer /
/// liveMonitor 的 provider 依赖面），保活语义（编辑未保存内容跨分段切换
/// 不丢）不受影响。
class _SubKindKeepAlive<T> {
  final Set<T> _visited = <T>{};

  /// 标记 [kind] 已访问（build 期调用，零通知）。
  void visit(T kind) => _visited.add(kind);

  /// [kind] 已访问 → 返回 [child]；未访问 → SizedBox 占位（下次选中时
  /// 首建）。
  Widget guard(T kind, Widget child) =>
      _visited.contains(kind) ? child : const SizedBox.shrink();

  /// 释放（宿主 State.dispose）。
  void dispose() => _visited.clear();
}

/// Data & Viz 容器内容：分段 [Grid | Chart] + 子视图访问保活
/// （[_SubKindKeepAlive]：chart 首次选中才构建）——两子态消费**同一**
/// [WorkbenchStageTab.resultRef]（共享结果集：chart 仅换渲染不重新取数，
/// UI35-306）；chart 子态在图表上方浮现 32px 轴配置条（X/Y 列型检测投影，
/// 只读）。
class _StageDataVizContent extends StatefulWidget {
  const _StageDataVizContent({
    required this.tab,
    required this.stageController,
    this.registry,
    this.onOpenInClassic,
  });

  final WorkbenchStageTab tab;
  final WorkbenchStageController stageController;
  final PluginRegistry? registry;
  final void Function(String sql)? onOpenInClassic;

  @override
  State<_StageDataVizContent> createState() => _StageDataVizContentState();
}

class _StageDataVizContentState extends State<_StageDataVizContent> {
  final _SubKindKeepAlive<DataVizSubKind> _keepAlive =
      _SubKindKeepAlive<DataVizSubKind>();

  @override
  void dispose() {
    _keepAlive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected =
        widget.tab.subKind is DataVizSubKind
            ? widget.tab.subKind as DataVizSubKind
            : DataVizSubKind.grid;
    _keepAlive.visit(selected);
    final isChart = selected == DataVizSubKind.chart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageSubKindSegments<DataVizSubKind>(
          values: DataVizSubKind.values,
          selected: selected,
          labelOf: (v) => v.label(l10n),
          onSelect: (v) =>
              widget.stageController.selectSubKind(widget.tab.id, v),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: IndexedStack(
            index: isChart ? 1 : 0,
            children: [
              _keepAlive.guard(
                DataVizSubKind.grid,
                _StageGridContent(tab: widget.tab, registry: widget.registry),
              ),
              _keepAlive.guard(
                DataVizSubKind.chart,
                _StageChartPane(
                  tab: widget.tab,
                  onOpenInClassic: widget.onOpenInClassic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// chart 子态窗格（dataViz 容器内）：32px 轴配置条（X/Y 列型检测投影，
/// 只读）+ 图表内容（列型不适配 → 内联错误 + [在经典中打开] 出口不弹窗，
/// AC5.3）。
class _StageChartPane extends StatelessWidget {
  const _StageChartPane({required this.tab, this.onOpenInClassic});

  final WorkbenchStageTab tab;
  final void Function(String sql)? onOpenInClassic;

  @override
  Widget build(BuildContext context) {
    final ref = tab.resultRef;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAxisBar(context, ref),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: _StageChartContent(tab: tab, onOpenInClassic: onOpenInClassic),
        ),
      ],
    );
  }

  /// 轴配置条（design-v3.5-ui §2.3：仅 chart 子态出现，高 32；X/Y/Series
  /// 三 chip——X = 首个非数值列，Y = 首个数值列，Series = 数值列全集；
  /// 列型检测投影只读，交互式轴选择不入本批）。
  Widget _buildAxisBar(BuildContext context, AgentResultRef? ref) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    String? xAxis;
    String? yAxis;
    final seriesColumns = <String>[];
    if (ref != null && ref.columns.isNotEmpty) {
      final types = _detectColumnTypes(ref);
      for (final column in ref.columns) {
        if (types[column] == ColumnDataType.numeric) {
          seriesColumns.add(column);
          yAxis ??= column;
        } else {
          xAxis ??= column;
        }
      }
    }
    Widget chip(String label) {
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
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: AppDesignSystem.fontSizeXs,
            fontFamily: AppDesignSystem.monoFontFamily,
            fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Text(
            l10n.agentStageAxisConfig,
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeXs,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Flexible(child: chip('X: ${xAxis ?? '—'}')),
          const SizedBox(width: AppDesignSystem.space1),
          Flexible(child: chip('Y: ${yAxis ?? '—'}')),
          if (seriesColumns.length > 1) ...[
            const SizedBox(width: AppDesignSystem.space1),
            Flexible(child: chip('Series: ${seriesColumns.length}')),
          ],
        ],
      ),
    );
  }
}

/// Schema 容器内容：Mongo 集合分支 = [WorkbenchMongoSchemaView] 单视图
/// （2b.2b，无分段——mongo schema 无列/索引/DDL 三段语义）；SQL 表分支 =
/// 分段 [Columns | Indexes | DDL] + 三子段 IndexedStack 保活。分段标签即
/// 子段标题（内容不重复渲染节标题，B-01）。AI 推测字段虚线框落在 columns
/// 子段实查列之后（不写回 schema）。
class _StageSchemaContent extends StatelessWidget {
  const _StageSchemaContent({required this.tab});

  final WorkbenchStageTab tab;

  @override
  Widget build(BuildContext context) {
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
    final l10n = AppLocalizations.of(context)!;
    final selected =
        tab.subKind is SchemaSubKind
            ? tab.subKind as SchemaSubKind
            : SchemaSubKind.columns;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageSubKindSegments<SchemaSubKind>(
          values: SchemaSubKind.values,
          selected: selected,
          labelOf: (v) => v.label(l10n),
          // Schema 容器分段切换是纯展示态切换——无 controller 注入面时
          // （本件由舞台构建，controller 经 [WorkbenchStage.widget] 不可直
          // 达），子态保存在本内容件 State 之外的最小方案 = 由舞台侧统一
          // 回写。此处经 InheritedWidget 之外的直接途径：舞台把 selectSubKind
          // 绑定在 tab 上不可行（tab 不可变），故分段回调走
          // [_StageSchemaSlotHost]（舞台壳提供的回写桥）。
          onSelect: (v) => _onSelect(context, v),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(child: _buildSelectedSection(context, selected)),
      ],
    );
  }

  /// 分段回写：经祖先 [_WorkbenchStageState] 取 controller（内容件由舞台
  /// 唯一装配，祖先恒在树内）。
  void _onSelect(BuildContext context, SchemaSubKind value) {
    final state = context.findAncestorStateOfType<_WorkbenchStageState>();
    state?.widget.controller.selectSubKind(tab.id, value);
  }

  Widget _buildSelectedSection(BuildContext context, SchemaSubKind selected) {
    final data = tab.structure;
    if (data == null) return const SizedBox.shrink();
    return IndexedStack(
      index: selected.index,
      children: [
        _buildColumnsSection(context, data),
        _buildIndexesSection(context, data),
        _buildDdlSection(context, data),
      ],
    );
  }

  /// columns 子段：实查列行 + AI 推测字段虚线框（不写回）。
  Widget _buildColumnsSection(
    BuildContext context,
    StageStructureData data,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final column in data.columns)
            _StructureColumnRow(column: column),
          for (final inferred in data.aiInferredColumns)
            _AiInferredColumnRow(entry: inferred),
        ],
      ),
    );
  }

  /// indexes 子段：索引行 + 外键行（键族归并呈现——外键无独立子段，
  /// B-01 三子段语义）。
  Widget _buildIndexesSection(
    BuildContext context,
    StageStructureData data,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final index in data.indexes) _StructureIndexRow(index: index),
          for (final foreignKey in data.foreignKeys)
            _StructureFkRow(foreignKey: foreignKey),
        ],
      ),
    );
  }

  /// ddl 子段：CREATE TABLE 语句块（mono / codeBlockBg / 上限高内滚）。
  Widget _buildDdlSection(BuildContext context, StageStructureData data) {
    final ddl = data.ddl;
    if (ddl == null || ddl.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topLeft,
      child: _StructureDdlBlock(ddl: ddl),
    );
  }
}

/// AI 推测字段行（虚线框，批3 P3）：列形态行 + 推测依据注记——**不写回
/// schema**（纯展示，无任何写路径；「不写回」由构造性保证：本行无按钮无
/// 回调）。虚线边框 = 自绘 painter（Flutter 无原生 dashed border，不引依赖）。
class _AiInferredColumnRow extends StatelessWidget {
  const _AiInferredColumnRow({required this.entry});

  final StageAiInferredColumn entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final mono = TextStyle(
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    );
    final column = entry.column;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space0_5),
      child: CustomPaint(
        foregroundPainter: _DashedBorderPainter(
          color: colors.accentBlue.withValues(alpha: 0.55),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1_5,
            vertical: AppDesignSystem.space1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                ],
              ),
              const SizedBox(height: 2),
              Text(
                l10n.agentStageAiInferred(entry.note),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppDesignSystem.fontSizeXs,
                  color: colors.accentBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 虚线边框 painter（AI 推测字段虚线框专用；四边等距短划）。
class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});

  final Color color;

  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
    void dashedLine(Offset from, Offset to) {
      var dx = 0.0;
      final length = (to - from).distance;
      final direction = (to - from) / (length == 0 ? 1 : length);
      while (dx < length) {
        final start = from + direction * dx;
        final end = from + direction * math.min(dx + _dash, length);
        canvas.drawLine(start, end, paint);
        dx += _dash + _gap;
      }
    }

    final tl = Offset.zero;
    final tr = Offset(size.width, 0);
    final br = Offset(size.width, size.height);
    final bl = Offset(0, size.height);
    dashedLine(tl, tr);
    dashedLine(tr, br);
    dashedLine(br, bl);
    dashedLine(bl, tl);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Diagnostics 容器内容：分段 [Explain Plan | Live Monitor] + 双子视图
/// 访问保活（[_SubKindKeepAlive]：liveMonitor 首次选中才构建——observe
/// 内容件消费 AppProvider，隐藏构建会在无 Provider 测试环境抛
/// ProviderNotFoundException）。explainPlan = [_StageExecutionContent] 静态
/// 投影（无载荷时空占位）；liveMonitor = [WorkbenchObserveContent]（2b.1
/// 实时观察语义，单例跟随锁定连接，零写手势）。
class _StageDiagnosticsContent extends StatefulWidget {
  const _StageDiagnosticsContent({required this.tab});

  final WorkbenchStageTab tab;

  @override
  State<_StageDiagnosticsContent> createState() =>
      _StageDiagnosticsContentState();
}

class _StageDiagnosticsContentState extends State<_StageDiagnosticsContent> {
  final _SubKindKeepAlive<DiagnosticsSubKind> _keepAlive =
      _SubKindKeepAlive<DiagnosticsSubKind>();

  @override
  void dispose() {
    _keepAlive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected =
        widget.tab.subKind is DiagnosticsSubKind
            ? widget.tab.subKind as DiagnosticsSubKind
            : DiagnosticsSubKind.explainPlan;
    _keepAlive.visit(selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageSubKindSegments<DiagnosticsSubKind>(
          values: DiagnosticsSubKind.values,
          selected: selected,
          labelOf: (v) => v.label(l10n),
          onSelect: (v) => _onSelect(context, v),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: IndexedStack(
            index: selected.index,
            children: [
              _keepAlive.guard(
                DiagnosticsSubKind.explainPlan,
                _buildExplainPlan(context),
              ),
              _keepAlive.guard(
                DiagnosticsSubKind.liveMonitor,
                const WorkbenchObserveContent(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 分段回写：经祖先 [_WorkbenchStageState] 取 controller（内容件由舞台
  /// 唯一装配，祖先恒在树内）。
  void _onSelect(BuildContext context, DiagnosticsSubKind value) {
    final state = context.findAncestorStateOfType<_WorkbenchStageState>();
    state?.widget.controller.selectSubKind(widget.tab.id, value);
  }

  Widget _buildExplainPlan(BuildContext context) {
    final data = widget.tab.execution;
    if (data == null || data.rows.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      final colors = context.themeColors;
      return Center(
        child: Text(
          l10n.commonNoData,
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }
    return _StageExecutionContent(tab: widget.tab);
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
                    tab.container.icon,
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

/// tab 条尾部动作钮（重开 / 收起，走查修复批 S3/S7/S9；批3 E3.2）：图标 +
/// textSecondary；hover bgTertiary；命中高 = tab 条全高 32，宽默认 28
///（[size] 覆写——批3 舞台开合钮迁容器 tab 条右端 24×24，B-02）；roving
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
    this.size = 28,
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

  /// 命中区宽（默认 28；批3 收起钮 = 24——B-02「容器 tab 条右端 24×24」）。
  final double size;

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
                width: widget.size,
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

/// 结构行徽标（schema 容器列/索引行共用）：bgTertiary + 11 textSecondary +
/// radiusSm（沿类型徽标语法；原 _StageStructureContent.badge 随容器重构
/// 提为顶层函数）。
Widget _structureBadge(BuildContext context, String text) {
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
            _structureBadge(context, 'PK'),
          ],
          if (!column.isNullable) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _structureBadge(context, 'NN'),
          ],
          if (column.defaultValue != null &&
              column.defaultValue!.isNotEmpty) ...[
            const SizedBox(width: AppDesignSystem.space1),
            _structureBadge(context, column.defaultValue!),
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
            _structureBadge(context, 'UNIQUE'),
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
    final ref = tab.resultRef;
    if (ref == null || !WorkbenchStageController.isChartable(ref) ||
        !_columnsMatchRows(ref)) {
      return _buildMismatch(context, AppLocalizations.of(context)!, ref?.sql ?? '');
    }
    return ChartView(data: ref.rows, columnTypes: _detectColumnTypes(ref));
  }

  /// 列集一致性守卫（批3 容器收敛新增防御）：dataViz 容器下 chart 子视图
  /// 随 IndexedStack 隐藏构建（子态保活）——[ChartView] 的轴下拉项取自
  /// `data.first.keys`，而列类型检测按 [AgentResultRef.columns]——两者
  /// 不一致（卡快照列集 ≠ 行键集）时 DropdownButton 值不在项集内触发
  /// 断言。不一致 → 按不适配处理（内联错误 + 经典出口），不建 ChartView。
  static bool _columnsMatchRows(AgentResultRef ref) {
    if (ref.rows.isEmpty) return true;
    final rowKeys = ref.rows.first.keys.toSet();
    return ref.columns.every(rowKeys.contains);
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

/// sqlStudio/diff 子态内容（2b.3 R6 + 批3 P3）：可折叠 Optimization
/// Summary 卡（默认展开当有变更——索引推荐或瓶颈非空；头 26 + 体内容）+
/// SQL 上下文块（mono SelectableText，沿 [_StructureDdlBlock] 形态自写不
/// 抽取）+ 下方 [QueryPlanVisualizer] 零改动复用承载（计划树 + 瓶颈 + 索引
/// 推荐 + 重写建议四层，R6 双头维护禁令）。载荷为空（Diff 分段无产物）→
/// 「No data」空占位。
///
/// 零写手势（任务书 §6.4 一票否决项）：「应用此索引」= 回调填
/// [WorkbenchStageController.openEditorSlot]（编辑器槽载入不自动执行，
/// AC5.5 脏槽保护既有）——填槽不执行，无任何 SQL 执行入口。visualizer
/// 内部英文硬编码属既有经典组件面，l10n 改造登记跟进项不并入本批。
class _StageDiffContent extends StatefulWidget {
  const _StageDiffContent({
    required this.tab,
    required this.stageController,
  });

  final WorkbenchStageTab tab;
  final WorkbenchStageController stageController;

  @override
  State<_StageDiffContent> createState() => _StageDiffContentState();
}

class _StageDiffContentState extends State<_StageDiffContent> {
  /// Summary 折叠态（默认 = 有变更展开：索引推荐或瓶颈非空）。
  late bool _summaryExpanded = _hasChanges(widget.tab.optimization);

  @override
  void didUpdateWidget(covariant _StageDiffContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 复用刷新（载荷对象替换）→ 折叠态按新载荷重定默认（新报告有变更
    // → 展开，让用户看到新建议）。
    if (oldWidget.tab.optimization != widget.tab.optimization) {
      _summaryExpanded = _hasChanges(widget.tab.optimization);
    }
  }

  static bool _hasChanges(StageOptimizationData? data) {
    if (data == null) return false;
    return data.report.indexRecommendations.isNotEmpty ||
        data.report.bottlenecks.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.tab.optimization;
    if (data == null) {
      final l10n = AppLocalizations.of(context)!;
      final colors = context.themeColors;
      return Center(
        child: Text(
          l10n.commonNoData,
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSummaryCard(context, data),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          // 单滚动区（沿 query_editor_widget.dart:2002-2009 经典计划 dialog
          // 同款包裹）：visualizer 自身无内滚，大载荷需外层滚动。
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSqlContextBlock(context, data.sql),
                const SizedBox(height: AppDesignSystem.space2_5),
                QueryPlanVisualizer(
                  report: data.report,
                  // 填编辑器槽不执行（R6：「应用此索引」的唯一合法落点）。
                  onApplyDdl: widget.stageController.openEditorSlot,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Optimization Summary 卡（批3 P3：头 26 = 折叠开关 + 标题；体 = 报告
  /// 摘要文本 + 推荐索引 DDL 块）。行扫描对比行（agentStageRowsScanned）
  /// 需要「优化后估算行数」数据位——当前 [PerformanceReport] 无该字段
  /// （索引推荐仅 estimatedImprovement 百分比），不虚构数值，暂不渲染
  /// （自决申报：键位保留待模型扩位后启用）。
  Widget _buildSummaryCard(BuildContext context, StageOptimizationData data) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final recommendation = data.report.indexRecommendations.isNotEmpty
        ? data.report.indexRecommendations.first
        : null;
    return Container(
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头 26：折叠开关（chevron）+ 标题。
          InkWell(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(AppDesignSystem.radiusSm),
              topRight: Radius.circular(AppDesignSystem.radiusSm),
            ),
            onTap: () => setState(() => _summaryExpanded = !_summaryExpanded),
            child: SizedBox(
              height: 26,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space2,
                ),
                child: Row(
                  children: [
                    Icon(
                      _summaryExpanded
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronRight,
                      size: 12,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: AppDesignSystem.space1),
                    Text(
                      l10n.agentStageOptimizationSummary,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeXs,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_summaryExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesignSystem.space2,
                0,
                AppDesignSystem.space2,
                AppDesignSystem.space2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.report.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      color: colors.textSecondary,
                    ),
                  ),
                  if (recommendation != null &&
                      recommendation.ddlStatement != null) ...[
                    const SizedBox(height: AppDesignSystem.space1_5),
                    Text(
                      l10n.agentStageRecommendedIndex,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeXs,
                        fontWeight: FontWeight.w600,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppDesignSystem.space1),
                    _StructureDdlBlock(ddl: recommendation.ddlStatement!),
                  ],
                ],
              ),
            ),
        ],
      ),
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
