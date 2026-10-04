//! AI 工作台外壳（z2 全屏态宿主，design-ai-workbench §4.1 / D1 / D2）。
//!
//! z2 层（`lib/screens/home/ai_fullscreen_overlay.dart`）的全屏分支渲染本
//! 组件，并以 Offstage 常驻挂载保活（D4：切换不销毁——会话/输入草稿/滚动
//! 位跨模式存活，AC1.4；会话数据本身在 AiPanelProvider，本就与模式无关）。
//!
//! 结构（AC1.3 对话为视觉主体）：
//! `Row[ 会话栏（WorkbenchSessionRail，T11） | 对话列（舞台收起 360-760
//! 居中；舞台可见弹性 [360,520]，见 [_buildStageLayout]） ]`，
//! 对话列 = 上下文芯片行（WorkbenchContextChip，T11）+ 退出按钮 +
//! [WorkbenchChatView]（消息流 + AiInputArea 全参数装配在其内部完成）。
//!
//! 数据：只消费既有 Provider（AppProvider / AiPanelProvider），零新 Provider
//! （D7 同源投影）。T13 已接入：卡动作回调注入（执行编排 / 互跳出口）与
//! `_allowedWriteServers`（写确认会话放行集，Offstage 保活跨模式存活）。
//!
//! T14（A1 合龙）：agent 装配宿主——向 `aiPanel.agentRunner` 注入 run 上下文
//! 快照读取器（effectiveWorkbenchContext + savedConnections 方言/readOnly，
//! D15）与 chat 配置读取器（AppProvider AI 配置面 + locale）；装配
//! [GateCallbacks]（onL05Confirm = 在途 Completer 决策桥——落门卡消息 /
//! awaitingUser 翻转 / 停止取消已由 runner 包装层承担，本壳只供「呈现卡面 +
//! 等决策」的桥；onPlanApproval = A1 reject 占位，§6 计划期发现 #7）。
//!
//! T27（A2 装配枢纽）：持有 [WorkbenchStageController]（舞台单一事实源，
//! State 字段 = Offstage 保活跨模式存活，不持久化）与 [AgentUiPortImpl]
//! （经 chat view 下沉注入 runner.start(uiPort:)——不新建 Provider，沿
//! actions/agentGates 同缝）；三列布局改造（ui 规格 §5.1）：
//! 舞台可见 → `Row[会话栏 240（≤1080 收 44）| 对话列 弹性 [360,520]（走查
//! 缺陷修复 2026-09-25，见 [_buildStageLayout]）| 舞台 Expanded ≥480]`，
//! 收起 → 舞台不入树、对话列恢复 M1 360–760 居中；
//! 底部 [WorkbenchArtifactStrip] 32 全宽常驻（两态均在）。轨迹卡
//! `onOpenResultInStage`（步详情快照入口）与计划注册表（planResolver）
//! 在本壳接线。
//!
//! T28（A2 合龙）：onPlanApproval 真实现（计划决策桥 `_pendingPlanDecisions`
//! + 计划注册表落账 + planId 回填门卡消息；批准 → approve + execute——deps
//! 在本壳装配：execute 通道绑 AppProvider facade、DDL/DML 双门绑
//! DdlConfirmDialog / DmlConfirmDialog、PK 取数绑 dbService；拒绝 → reject
//! 零执行）；L1 会话放行短路（账本 l1 集，AC9.3）；`_buildPlanBlock` 真回调
//! （批准/拒绝 → 决策桥；生成回退 → buildRollbackPlan 合成门卡消息，永不
//! 自动执行；终态重放 → markConsumed）；步结果开舞台优先查 executor 的
//! run 内注册表；`start` 的 uiPort 已转必填（§6 计划期发现 #7 收口）。
//!
//! T30（A3）：芯片行追加会话累计 chip（[_SessionTokensChip]，AC3.2）——
//! 当前会话全部 `agent_run_end` 终局消息 tokens 求和 + 步数合计，投影即
//! 重算（切会话/终局落地随既有通知链刷新，不持久化不建缓存）；tokens 键
//! 缺席的 run 不计入，无任何含 tokens 的 run → 整 chip 隐藏。
//!
//! B3（v1 MVP）：对话列宽度双模持久化（无持久化值 = Fix-L 弹性默认；首次
//! 拖拽/键盘调整后显式宽度落盘，R2）+ 对话列-舞台分隔条拖拽/键盘调整
//! （12px 命中 / 0px 布局占位叠层，R1；缩窗永不自动收起舞台）——见
//! [_buildStageLayout]。
//!
//! A5（v2 先行批）：F6/Shift+F6 六区轮转宿主——壳根包 Focus（不持焦点，
//! 只承接后代未处理键事件的冒泡，R10 不碰全局层）onKeyEvent 处理
//! F6 → 下一区、Shift+F6 → 上一区；State 持
//! [WorkbenchFocusZoneRegistry] + 当前区下标（[_activeZoneIndex]），各区
//! 聚焦入口由 rail/活动条/舞台/产物条随子树生命周期注册/注销（对话列区
//! 由本壳自登记，入口 = 复用 [_findEditableState] 聚焦输入框）。未注册区
//! （舞台收起 / rail 收窄）与入口失败区（空舞台 / 零条目产物条）在轮转中
//! 动态跳过——循环无死区。
//!
//! B1（v2 先行批收口）：execution tab 两推送通道的装配接缝——① 手动卡
//! 执行（[_cardActions].onExecuteSql → [WorkbenchExecutionActions.run]
//! 的 onExecutionBatch 回调 → [_stageController.openExecution]，R4 单例
//! 键 'manual'）；② 计划链（[_executeApprovedPlan] 在 execute 返回后组装
//! 投影推送，去重键 = planId；耗时/影响行数经 [_planExecutionDeps] 的
//! `withAgentQueryHistory` 包装点并联收集，skipped 从 plan.steps 终态
//! 读）。只读执行结果投影——执行语义/确认门/审计链零改动。

import 'dart:async' show Completer, unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_message_type.dart' show AiMessageType;
import '../../models/workbench_entry_intent.dart';
import '../../models/database_models.dart'
    show AiMessage, DatabaseType, DbColumn, DbIndex, DbServer, ForeignKey;
import '../../models/dml_risk_models.dart'
    show DmlConfirmationRequiredException;
import '../../providers/app_provider.dart';
import '../../providers/ai_panel_provider.dart'
    show WorkbenchAgentContextSnapshot;
import '../../providers/layout_preferences_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/tab_provider.dart'
    show DuplicateSavedQueryNameException, QueryTab;
import '../../services/ai/agent/agent_gate_analysis.dart'
    show ReadImpactAnalysis;
import '../../services/ai/agent/agent_loop_runner.dart'
    show AgentChatConfig, AgentLoopRunner, AgentRunStatus;
import '../../services/ai/agent/agent_plan.dart'
    show
        AgentActionPlan,
        AgentPlanExecutionDeps,
        AgentPlanExecutor,
        AgentPlanRollbackDeps,
        AgentPlanStatEvent,
        AgentPlanStepStatus;
import '../../services/ai/agent/agent_tool_executor.dart'
    show AgentPlanApprovalCallback, GateCallbacks;
import '../../services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, GateCardResult;
import '../../services/ai/workbench_context_resolver.dart'
    show WorkbenchContextValue, effectiveWorkbenchContext;
import '../../services/database_service.dart'
    show DdlConfirmationRequiredException, QueryExecutionResult;
import '../../services/sql_statement_gate_runner.dart'
    show SqlGateConfirmDecision, SqlStatementOutcome;
import '../../services/workbench_usage_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_logger.dart';
import '../ai_panel/ddl_confirm_dialog.dart'
    show DdlConfirmDialog, DdlConfirmResult;
import '../connection/error_boundary.dart' show AppErrorHandler;
import '../dialogs/dml_confirm_dialog.dart'
    show DmlConfirmDialog, DmlConfirmResult;
import 'agents/agent_plan_card.dart';
import 'agents/agent_trajectory_card.dart'
    show agentKindOf, agentPayloadOf, agentTrajectoryCompactTokens;
import 'agent_ui_port_impl.dart';
import 'save_query_naming_dialog.dart';
import 'workbench_artifact_strip.dart';
import 'workbench_card_host.dart';
import 'workbench_card_payload.dart' show WorkbenchResultCardPayload;
import 'workbench_chat_view.dart';
import 'workbench_context_chip.dart';
import 'workbench_context_picker.dart';
import 'workbench_execution_actions.dart';
import 'workbench_focus_zones.dart';
import 'workbench_open_in_classic.dart';
import 'workbench_session_rail.dart';
import 'workbench_split_resizer.dart';
import 'workbench_stage.dart';

/// Fix-F ② 停止×计划竞态探针（`AgentPlanExecutionDeps.shouldContinue` 绑定
/// 逻辑的可测面）。
///
/// 竞态链：计划卡批准后（决策 Completer 已 resolve approved）用户点停止 →
/// runner 的 `_hostGateCard` 竞速由停止侧胜出、审计记「人拒」；若计划继续
/// 跑到 done，即产生「审计记人拒但计划实际执行完」的矛盾链。绑定 runner
/// 停止态后，计划在下一个步边界中止（已完成步保持 done、余下 skipped，
/// partialFailed 边界呈现），矛盾消除。
///
/// - [bindRunnerStop] = true（桥路径执行）：`stopping`（已请求停止，当前
///   步收尾中）与 `stoppedByUser`（停止已落定——在途步完成后的下一边界
///   同样中止）均判不可继续；
/// - [bindRunnerStop] = false（直接路径：回退计划卡 / 迟到点击）：不绑
///   停止态——回退计划几乎总是在本 run 结束后才批准执行（status 恒为
///   终态），绑停止态会让「停止后回退」这一安全网结构性失效；
/// - `mounted` = false（壳已卸载）恒不可继续（既有语义）。
bool agentPlanExecutionMayContinue({
  required bool mounted,
  required bool bindRunnerStop,
  required AgentRunStatus runnerStatus,
}) {
  if (!mounted) return false;
  if (!bindRunnerStop) return true;
  return runnerStatus != AgentRunStatus.stopping &&
      runnerStatus != AgentRunStatus.stoppedByUser;
}

/// AI 工作台外壳。z2 全屏态的替代内容（D2 收敛裁决：AI 全屏 = 工作台）。
///
/// 构造保持最小（无外部依赖注入）；T13 的执行动作回调与 T11 的会话栏 /
/// 芯片组件经内部挂点接入，签名按任务书届时扩展。
class AiWorkbenchShell extends StatefulWidget {
  const AiWorkbenchShell({super.key});

  @override
  State<AiWorkbenchShell> createState() => _AiWorkbenchShellState();
}

class _AiWorkbenchShellState extends State<AiWorkbenchShell> {
  AppProvider? _observedProvider;
  bool _workbenchVisible = false;

  /// 已消费的工作台入口 intent id（2b.4 R7 防重入锚：同 id 只调度一次
  /// post-frame 消费；新请求 id 自增 → 新的调度照常）。
  int? _consumedWorkbenchEntryIntentId;

  /// 写确认会话放行集（T13，design §6.2/§6.5）：key = connectionId，镜像
  /// 经典 `_allowedSessionServers`（`ai_panel_widget.dart`）语义——allowSession
  /// 后本连接的写语句本会话免弹。放 shell State：Offstage 保活跨模式存活，
  /// 应用重启重置（不持久化）。
  final Set<String> _allowedWriteServers = <String>{};

  /// 在途门卡决策桥（T14）：key = `'<runId>:<stepNo>'` → Completer。runner
  /// 包装层负责落门卡消息 + awaitingUser 翻转 + 停止取消；本桥只把「卡面
  /// 决策 → runner 的 onL05Confirm future」接通（stepNo 与门卡消息载荷同源
  /// ——executor 计步在 confirm 链之前已完成）。
  final Map<String, Completer<GateCardResult>> _pendingGateDecisions =
      <String, Completer<GateCardResult>>{};

  /// agent 运行器监听（T14）：运行收敛时清理决策桥——迟到的卡面点击因条目
  /// 已移除而安全空转（Completer 无人 await）。
  AgentLoopRunner? _observedAgentRunner;

  /// 舞台状态单一事实源（T27，ui 规格 §6.3）：tab 集合 / pinned 标记 /
  /// 激活态 / 舞台可见性。State 字段（Offstage 保活跨模式存活；不持久化、
  /// 不新建 Provider——产物条与舞台两投影消费同一实例）。
  late final WorkbenchStageController _stageController =
      WorkbenchStageController();

  /// 对话列-舞台分隔条拖拽中的内存显示宽（B3）：`onResizeUpdate` 只改此值、
  /// `onResizeEnd` 一次性落盘（update 期间 provider 零 notify 零写盘）；
  /// null = 非拖拽态，宽度求值走 [_buildStageLayout] 的双模分支。
  double? _dragChatSplitWidth;

  /// 分隔条拖拽进行中（透传 resizer 的 isResizing 视觉态，B3）。
  bool _chatSplitResizing = false;

  /// F6 六区轮转注册表（A5，[WorkbenchFocusZoneRegistry]）：各区由所属组件
  /// 挂载时登记聚焦入口、卸载时注销（对话列区由本壳自登记）；壳 Offstage
  /// 隐藏时子树不可聚焦 = 天然作用域隔离（R10，全局层零触碰）。
  final WorkbenchFocusZoneRegistry _focusZoneRegistry =
      WorkbenchFocusZoneRegistry();

  /// 当前轮转区下标（A5）：初始 = [WorkbenchFocusZone.chatColumn]——进入
  /// 工作台即聚焦输入区（AC1.2），对话列是当前区语义起点。仅轮转消费，
  /// 不驱动重建（无 setState）。
  int _activeZoneIndex = WorkbenchFocusZone.chatColumn.index;

  /// 对话列区聚焦入口（身份稳定闭包：注册/注销成对使用同一实例）。
  late final WorkbenchZoneFocusEntry _chatZoneEntry = _focusChatColumn;

  /// 界面派发端口实现（T27，D8）：经 chat view 下沉注入
  /// `runner.start(uiPort:)`（T28 转必填）。依赖闭包均晚绑定
  /// [_observedProvider]，provider 实例变更（测试重建）无需重建本对象。
  late final AgentUiPortImpl _agentUiPort = AgentUiPortImpl(
    stageController: _stageController,
    structureFetcher: _fetchStageStructure,
    landSuggestionMessage: _landAgentSuggestion,
  );

  /// 计划注册表（T27 建，T28 落账对接）：planId → 活跃计划对象。T28 的
  /// onPlanApproval 落 `agent_plan` 门卡消息时注册；轨迹卡 planResolver 按门卡
  /// 载荷 planId 解析。
  final Map<String, AgentActionPlan> _planRegistry =
      <String, AgentActionPlan>{};

  /// 在途计划卡决策桥（T28）：key = `'<runId>:<stepNo>'`（与门卡消息载荷
  /// 同源）→ Completer。批准/拒绝由计划卡回调 resolve；运行收敛时以
  /// rejected 解决（停止/会话切换 → 计划随运行取消，零执行）。
  final Map<String, Completer<GateCardResult>> _pendingPlanDecisions =
      <String, Completer<GateCardResult>>{};

  /// 计划执行器（T28 装配）：决策（approve/reject 幂等）+ 逐语句执行 +
  /// 审计（默认绑 AuditLogService）+ 统计（AgentPlanStatEvent → 统计服务
  /// 枚举按 name 桥接，T22 文件头桥接说明——两处枚举值需同步）。
  late final AgentPlanExecutor _planExecutor = AgentPlanExecutor(
    recordPlanEvent: (AgentPlanStatEvent event) => WorkbenchUsageStatsService
        .instance
        .recordPlanEvent(AgentPlanStat.values.byName(event.name)),
  );

  @override
  void initState() {
    super.initState();
    // 对话列区（A5）：本壳自登记（对话列两态恒在）；其余五区由 rail/活动条/
    // 舞台/产物条随各自子树生命周期登记。
    _focusZoneRegistry.register(WorkbenchFocusZone.chatColumn, _chatZoneEntry);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppProvider>();
    if (!identical(provider, _observedProvider)) {
      _observedProvider?.removeListener(_onAppProviderChanged);
      _observedProvider = provider;
      provider.addListener(_onAppProviderChanged);
      _bindAgentRunner(provider.aiPanel.agentRunner);
      // T14：run 上下文快照 / chat 配置读取器注入（AppProvider 级解析能力
      // 闭包化供给 provider 层——沿 insertConfirmationCallback「UI 层设置
      // 回调」先例，provider 层不触跨 Provider 引用禁令）。
      provider.aiPanel.agentContextSnapshotReader = _readAgentContextSnapshot;
      provider.aiPanel.agentChatConfigReader = _readAgentChatConfig;
      // 壳由 z2 常驻挂载（Offstage），initState 时未必可见——进入工作台
      //（open && fs 的上升沿）才计 entry（§6.4「每次进入」口径）。
      _syncVisibility();
      // 2b.4 R7：装配面首检 pending intent（意图可能早于壳装配挂载）。
      _checkWorkbenchEntryIntent();
    }
  }

  @override
  void dispose() {
    _observedAgentRunner?.removeListener(_onAgentRunnerChanged);
    _observedAgentRunner = null;
    _observedProvider?.removeListener(_onAppProviderChanged);
    _observedProvider = null;
    _focusZoneRegistry.unregister(
      WorkbenchFocusZone.chatColumn,
      _chatZoneEntry,
    );
    _stageController.dispose();
    super.dispose();
  }

  void _onAppProviderChanged() {
    _syncVisibility();
    // 2b.4 R7：AppProvider 转发 aiPanel 通知 → pending intent 检测（运行时
    // 请求的主路径：三钩子/命令面板在壳常驻挂载期间 set intent）。
    _checkWorkbenchEntryIntent();
  }

  void _bindAgentRunner(AgentLoopRunner runner) {
    if (identical(runner, _observedAgentRunner)) return;
    _observedAgentRunner?.removeListener(_onAgentRunnerChanged);
    _observedAgentRunner = runner;
    runner.addListener(_onAgentRunnerChanged);
  }

  void _onAgentRunnerChanged() {
    if (_observedAgentRunner?.isRunning ?? false) return;
    // 运行收敛（终局 / 复位）：清理在途决策桥。
    _pendingGateDecisions.clear();
    // T28：在途计划决策以 rejected 解决（§6.4：awaitingUser 的 Completer
    // 以 rejected 解决——run 已由 runner 侧收敛，计划未获批准即零执行；
    // _onPlanApproval 的 await 随之返回并 reject 计划）。
    final List<Completer<GateCardResult>> pending =
        List<Completer<GateCardResult>>.of(_pendingPlanDecisions.values);
    _pendingPlanDecisions.clear();
    for (final Completer<GateCardResult> completer in pending) {
      if (!completer.isCompleted) {
        completer.complete(GateCardResult.rejected);
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // agent 装配（T14）：上下文快照 / chat 配置读取器 + GateCallbacks 决策桥
  // ──────────────────────────────────────────────────────────────────────────

  /// run 启动快照缓存（Fix-F ⑥，D15 绑定面）：[_readAgentContextSnapshot]
  /// 是 runner `start` 时 D15 快照的唯一解析点（经 provider
  /// `agentContextSnapshotReader` 注入，一次 run 恰调一次），缓存其产物供
  /// run 内取数消费（结构取数 [_fetchStageStructure]）——run 内回调绑定
  /// 本快照，不随点击时侧栏/tab 漂移。
  WorkbenchAgentContextSnapshot? _runContextSnapshot;

  /// run 上下文快照（D15 一次快照的解析来源）：缓存产物后返回（解析逻辑
  /// 在 [_resolveAgentContextSnapshot]）。
  WorkbenchAgentContextSnapshot? _readAgentContextSnapshot() {
    final WorkbenchAgentContextSnapshot? snapshot =
        _resolveAgentContextSnapshot();
    _runContextSnapshot = snapshot;
    return snapshot;
  }

  /// 快照解析：锁定优先 → 跟随解析（活动 tab → 侧栏），方言 / readOnly 查
  /// savedConnections；无上下文返回 connectionId 空（AC7.4 引导态）。
  WorkbenchAgentContextSnapshot? _resolveAgentContextSnapshot() {
    final provider = _observedProvider;
    if (provider == null) return null;
    final context = effectiveWorkbenchContext(
      provider.aiPanel.sessionManager.currentSession,
      provider,
    );
    final String? connectionId = context.connectionId;
    if (connectionId == null || connectionId.isEmpty) return null;
    DbServer? server;
    for (final DbServer candidate in provider.savedConnections) {
      if (candidate.id == connectionId) {
        server = candidate;
        break;
      }
    }
    return (
      connectionId: connectionId,
      connectionName: context.connectionName,
      databaseName: context.databaseName,
      // 连接不在保存表（已被删除等）→ 方言占位：数据工具经 executeQuery 按
      // connectionId 路由，方言只影响 NoSQL 预拦截与 EXPLAIN 分析。
      dbType: server?.type ?? DatabaseType.mysql,
      // 连接不在保存表 → readOnly 保守取 true（Fix-B T-1：已删除连接的
      // 读写属性无从解析，宁可多拦不可少拦——A2 起 plan 类工具经判定序 ③
      // READONLY_CONNECTION 被拒；在表内的连接仍按真实值）。
      readOnly: server?.readOnly ?? true,
    );
  }

  /// chat 配置（T14）：读 AppProvider AI 配置面 + 当前 locale。
  AgentChatConfig? _readAgentChatConfig() {
    final provider = _observedProvider;
    if (provider == null) return null;
    final selectedProvider = provider.selectedAiProvider;
    final baseUrl = provider.getAiBaseUrl(selectedProvider) ?? '';
    return AgentChatConfig(
      provider: selectedProvider,
      model: provider.selectedAiModel,
      apiKey: provider.getAiApiKey(selectedProvider) ?? '',
      baseUrl: baseUrl.isEmpty ? null : baseUrl,
      timeout: provider.aiTimeout,
      locale: mounted
          ? LocaleProvider.codeOf(Localizations.localeOf(context))
          : 'en',
    );
  }

  /// 门卡回调（design §4.3：由 UI 层实现注入）。runner 包装层已承担落卡消息 /
  /// awaitingUser 翻转 / 停止取消 / 异常兜底（rejected）——本桥只等卡面决策。
  GateCallbacks get _agentGateCallbacks => GateCallbacks(
    onL05Confirm: (ReadImpactAnalysis impact, String sql) {
      final AgentLoopRunner? runner = _observedProvider?.aiPanel.agentRunner;
      final String runId = runner?.activeRunId ?? '';
      final int stepNo = runner?.stepsUsed ?? 0;
      final Completer<GateCardResult> completer = Completer<GateCardResult>();
      _pendingGateDecisions['$runId:$stepNo'] = completer;
      return completer.future;
    },
    // T28 真接线（§6 计划期发现 #7 收口）：计划决策桥——注册表 + planId
    // 回填 + 等 Completer；批准 → approve + execute（deps 本壳装配）；
    // 拒绝 → reject（零执行）。
    onPlanApproval: _onPlanApproval,
  );

  /// L1 计划批准回调（T28）：executor 的 submit 链在 confirm(l1) 后调用，
  /// 阻塞等人直到计划卡决策。**执行语义**（[AgentPlanApprovalCallback]
  /// 注释 / T22 文件头装配说明）：批准后的 approve + execute 在本回调内
  /// 完成——deps（执行通道 + DDL/DML 双门对话框）是 UI 绑定面，只可能
  /// 在装配层注入；计划为就地可变对象，executor 在本回调返回后按 plan
  /// 终态组装回喂。
  Future<GateCardResult> _onPlanApproval(AgentActionPlan plan) async {
    final provider = _observedProvider;
    if (provider == null) {
      // fail-closed：无宿主（壳已卸载）→ 拒绝，零执行。
      await _planExecutor.reject(plan);
      return GateCardResult.rejected;
    }
    final AgentLoopRunner runner = provider.aiPanel.agentRunner;
    final String runId = runner.activeRunId ?? plan.runId;
    final int stepNo = runner.stepsUsed;

    // 注册表 + 门卡消息 planId 回填（轨迹卡 planResolver 寻址面）。
    _planRegistry[plan.planId] = plan;
    _backfillPlanIdIntoGateCard(runId, stepNo, plan.planId);
    WorkbenchUsageStatsService.instance.recordPlanEvent(AgentPlanStat.shown);

    // L1 会话放行短路（AC9.3）：本连接已获放行 → 免卡直接批准执行（返回
    // approvedForSession → executor 审计 allowed_session；逐语句审计仍全量）。
    if (runner.ledger.l1Allowed.contains(plan.ctx.connectionId ?? '')) {
      await _executeApprovedPlan(plan, bindRunnerStop: true);
      return GateCardResult.approvedForSession;
    }

    final Completer<GateCardResult> completer = Completer<GateCardResult>();
    _pendingPlanDecisions['$runId:$stepNo'] = completer;
    final GateCardResult result = await completer.future;
    switch (result) {
      case GateCardResult.rejected:
        await _planExecutor.reject(plan);
      case GateCardResult.approved:
        await _executeApprovedPlan(plan, bindRunnerStop: true);
      case GateCardResult.approvedForSession:
        // 会话放行登记（AC9.3：本会话内后续 L1 计划免卡）。
        runner.ledger.allowL1(plan.ctx.connectionId ?? '');
        await _executeApprovedPlan(plan, bindRunnerStop: true);
    }
    return result;
  }

  /// 批准后的执行装配（T28）：approve（幂等）→ 逐语句执行（deps 绑 shell
  /// 既有确认流 + dbService；DDL 双门不豁免 AC10.4——ddlConfirm 绑
  /// DdlConfirmDialog、dmlConfirm 绑 DmlConfirmDialog；回退推导的 PK 取数
  /// 绑 dbService.getTableColumns）。执行结果不在此回喂——executor 的
  /// submit 链按 plan 终态组装（共享同一计划对象）。
  ///
  /// [bindRunnerStop]（Fix-F ②）：桥路径（run 内批准）= true——批准后用户
  /// 停止时计划在步边界中止，消除「审计记人拒但计划执行完」矛盾链；直接
  /// 路径（回退计划卡 / 迟到点击）= false——run 已结束，回退须保持可用。
  Future<void> _executeApprovedPlan(
    AgentActionPlan plan, {
    required bool bindRunnerStop,
  }) async {
    if (_observedProvider == null) {
      // fail-closed：壳已卸载（provider 脱钩）→ 不执行（计划保持未执行态，
      // 审计由 reject/防重路径承载）。
      AppLogger.w(
        'AiWorkbenchShell',
        'plan ${plan.planId} execution skipped: provider detached',
      );
      return;
    }
    final bool approved = await _planExecutor.approve(
      plan,
      onStateChange: (_) => _refreshPlanCards(),
    );
    if (!approved) {
      // 非 pendingApproval（重复决策 / 终态重放）→ execute 的防重路径
      //（PLAN_ALREADY_EXECUTED + consumed 标记，AC11.4）；照常走 execute
      // 让结构守卫落账，不再有库操作。
      AppLogger.d(
        'AiWorkbenchShell',
        'plan ${plan.planId} approve returned false '
            '(status: ${plan.status.name}); delegating to execute guard',
      );
    }
    // B1 execution tab 收集器：仅本次批准真实推进（approved=true）才收集
    // 推送——终态重放防重路径零库操作不开 tab（永不空开同源）。
    final List<StageExecutionRow>? executionRows = approved
        ? <StageExecutionRow>[]
        : null;
    await _planExecutor.execute(
      plan: plan,
      deps: _planExecutionDeps(
        plan,
        bindRunnerStop: bindRunnerStop,
        onStatementExecuted: executionRows?.add,
      ),
    );
    if (executionRows != null) {
      _pushPlanExecutionTab(plan, executionRows);
    }
  }

  /// B1 计划链 execution tab 推送（R4 去重键 = planId——重跑同计划刷新同
  /// tab，标题带时间戳）：逐语句状态读 plan.steps 终态（门控控制流信号不
  /// 产生收集行——skipped 从此处读），耗时/影响行数读执行通道收集器
  /// （[_planExecutionDeps] 三通道 `withAgentQueryHistory` 同源包装处并联
  /// 收集）。join 以步序对齐（executor 严格串行逐语句执行，收集行序 =
  /// 步序；语句文本比对做防御校验，断裂行降级「状态 + SQL」无指标）。
  void _pushPlanExecutionTab(
    AgentActionPlan plan,
    List<StageExecutionRow> collected,
  ) {
    if (!mounted) return;
    // 零执行不推（批准后首个步边界前中止等形态：无一语句真正执行——
    // 永不空开，v1 §3.7 同源）。
    final bool anyRan = plan.steps.any(
      (s) =>
          s.runtime.status == AgentPlanStepStatus.done ||
          s.runtime.status == AgentPlanStepStatus.failed,
    );
    if (!anyRan) return;
    final List<StageExecutionRow> rows = <StageExecutionRow>[];
    var cursor = 0;
    for (final step in plan.steps) {
      final AgentPlanStepStatus status = step.runtime.status;
      if (status == AgentPlanStepStatus.done ||
          status == AgentPlanStepStatus.failed) {
        StageExecutionRow? record = cursor < collected.length
            ? collected[cursor]
            : null;
        if (record != null && record.sql.trim() == step.sql.trim()) {
          cursor++;
        } else {
          // 对齐断裂（防御，构造性不可达）：该步降级「状态 + SQL」无指标，
          // 游标不推进。
          record = null;
        }
        if (status == AgentPlanStepStatus.done) {
          rows.add(
            record ??
                StageExecutionRow(
                  sql: step.sql,
                  status: StageExecutionStatus.done,
                ),
          );
        } else {
          // 失败行错误全文：优先执行器口径（step.runtime.error，已脱敏）；
          // 缺失回落收集器记录（收集点已脱敏）。
          rows.add(
            StageExecutionRow(
              sql: step.sql,
              status: StageExecutionStatus.failed,
              durationMs: record?.durationMs,
              error: step.runtime.error ?? record?.error,
            ),
          );
        }
      } else {
        // skipped（含防御性 pending/running 归并）：状态 + SQL，无指标。
        rows.add(
          StageExecutionRow(
            sql: step.sql,
            status: StageExecutionStatus.skipped,
          ),
        );
      }
    }
    final AppLocalizations? l10n = AppLocalizations.of(context);
    _stageController.openExecution(
      StageExecutionData(
        tabKey: plan.planId,
        title: StageExecutionData.titleWithTimestamp(
          l10n?.agentStageTabExecution ?? 'Execution',
          DateTime.now(),
        ),
        rows: rows,
      ),
    );
  }

  /// 计划执行环境（[AgentPlanExecutionDeps]）：执行通道 = AppProvider
  /// facade（readOnly 检查 / DML 拦截 / DDL 双门 / 行限 / 网关路由全继承）；
  /// 确认面 = 本壳对话框；shouldContinue = 壳存活 + （桥路径）runner 停止
  /// 态探针（Fix-F ②）。连接/库取**计划自带的 run 快照**（plan.ctx，
  /// D15——全程只读同一快照，不随侧栏/tab 漂移）。三执行通道统一经
  /// `WorkbenchExecutionActions.withAgentQueryHistory` 包装：done/failed
  /// 语句双写查询历史（agent 来源；连接上下文 = run 快照，即 run 启动时
  /// effectiveWorkbenchContext 的冻结值；门控控制流信号不记，skipped
  /// 天然不记）。B1：[onStatementExecuted] 并联收集器经同一包装点透传
  /// （execution tab 投影的耗时/影响行数数据源；真实执行才产行）。
  AgentPlanExecutionDeps _planExecutionDeps(
    AgentActionPlan plan, {
    required bool bindRunnerStop,
    void Function(StageExecutionRow row)? onStatementExecuted,
  }) {
    // 非空已证：调用方 [_executeApprovedPlan] 先行判空返回（MAY-2 例外）。
    final AppProvider provider = _observedProvider!;
    final String? connectionId = plan.ctx.connectionId;
    final String? databaseName = plan.ctx.databaseName;
    return AgentPlanExecutionDeps(
      execute: WorkbenchExecutionActions.withAgentQueryHistory(
        provider,
        connectionId: connectionId,
        connectionName: plan.ctx.connectionName,
        databaseName: databaseName,
        databaseType: plan.ctx.dbType,
        // 裁决选项 A：数据工具绑定换 detailed 变体（经 AppProvider facade
        // 层，SELECT PII 脱敏保留；affectedRows 贯通投影与历史双写）。
        execute: (String statement) async {
          final QueryExecutionResult outcome = await provider
              .executeQueryDetailed(
                statement,
                connectionId: connectionId,
                database: databaseName,
              );
          return SqlStatementOutcome.fromExecutionResult(outcome);
        },
        onStatementExecuted: onStatementExecuted,
      ),
      executeBypassDdl: WorkbenchExecutionActions.withAgentQueryHistory(
        provider,
        connectionId: connectionId,
        connectionName: plan.ctx.connectionName,
        databaseName: databaseName,
        databaseType: plan.ctx.dbType,
        execute: (String statement) async {
          final QueryExecutionResult outcome = await provider.dbService
              .executeQueryBypassDdlDetailed(
                statement,
                connectionId: connectionId,
                database: databaseName,
              );
          return SqlStatementOutcome.fromExecutionResult(outcome);
        },
        onStatementExecuted: onStatementExecuted,
      ),
      executeBypassDml: WorkbenchExecutionActions.withAgentQueryHistory(
        provider,
        connectionId: connectionId,
        connectionName: plan.ctx.connectionName,
        databaseName: databaseName,
        databaseType: plan.ctx.dbType,
        execute: (String statement) async {
          final QueryExecutionResult outcome = await provider.dbService
              .executeQueryBypassDmlDetailed(
                statement,
                connectionId: connectionId,
                database: databaseName,
              );
          return SqlStatementOutcome.fromExecutionResult(outcome);
        },
        onStatementExecuted: onStatementExecuted,
      ),
      ddlConfirm: _confirmPlanDdl,
      dmlConfirm: _confirmPlanDml,
      shouldContinue: () => agentPlanExecutionMayContinue(
        mounted: mounted,
        bindRunnerStop: bindRunnerStop,
        runnerStatus: provider.aiPanel.agentRunner.status,
      ),
      onStepStateChange: (_) => _refreshPlanCards(),
    );
  }

  /// 轨迹卡门卡决策路由（T13 onGateDecision → 本桥 Completer resolve →
  /// runner 包装层回填 outcome 并续跑）。
  void _resolveGateDecision(String runId, int stepNo, GateCardResult decision) {
    _pendingGateDecisions.remove('$runId:$stepNo')?.complete(decision);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // A2 装配（T27）：舞台结构取数 / 建议消息落账 / 步结果开舞台 / 计划注册表
  // ──────────────────────────────────────────────────────────────────────────

  /// describe 四件取数（AgentUiPortImpl.structureFetcher 绑定点）：连接与
  /// 库绑 **run 启动快照**（Fix-F ⑥，D15 一致——结构取数是 run 内工具回
  /// 调，与 run 全程只读同一快照；不读点击时 effectiveWorkbenchContext，
  /// 侧栏/tab 漂移不进入 run 内取数）。无快照（无连接/无 run）抛错
  /// （→ port 层 outcome 失败回喂）。索引/外键/DDL 为方言能力面，取不到置
  /// 空不视为失败（沿 executor describe_table 容忍口径）；列信息失败抛错。
  Future<StageStructureData> _fetchStageStructure(String table) async {
    final provider = _observedProvider;
    if (provider == null) {
      throw StateError('workbench provider not attached');
    }
    final WorkbenchAgentContextSnapshot? snapshot = _runContextSnapshot;
    final String? connectionId = snapshot?.connectionId;
    if (connectionId == null || connectionId.isEmpty) {
      throw StateError('no database connection context');
    }
    final String? databaseName = snapshot?.databaseName;
    final columns = await provider.dbService.getTableColumns(
      table,
      connectionId: connectionId,
      databaseName: databaseName,
    );
    List<DbIndex>? indexes;
    try {
      indexes = await provider.dbService.getTableIndexes(
        table,
        connectionId: connectionId,
        databaseName: databaseName,
      );
    } catch (e) {
      AppLogger.d(
        'AiWorkbenchShell',
        'stage structure: indexes unavailable for "$table": $e',
      );
    }
    List<ForeignKey>? foreignKeys;
    try {
      foreignKeys = await provider.dbService.getForeignKeys(
        table,
        connectionId: connectionId,
        databaseName: databaseName,
      );
    } catch (e) {
      AppLogger.d(
        'AiWorkbenchShell',
        'stage structure: foreign keys unavailable for "$table": $e',
      );
    }
    String? ddl;
    try {
      ddl = await provider.dbService.getCreateTableSql(
        table,
        connectionId: connectionId,
        databaseName: databaseName,
      );
    } catch (e) {
      AppLogger.d(
        'AiWorkbenchShell',
        'stage structure: create table SQL unavailable for "$table": $e',
      );
    }
    return StageStructureData(
      tableName: table,
      columns: columns,
      indexes: indexes ?? const <DbIndex>[],
      foreignKeys: foreignKeys ?? const <ForeignKey>[],
      ddl: ddl,
    );
  }

  /// 建议消息落账（AgentUiPortImpl.landSuggestionMessage 绑定点）：补写
  /// runId/stepNo（T26 `_applySuggestion` 审计对账消费；取 runner 当前态，
  /// 与门卡决策桥的 stepNo 约定同源）后落当前会话。无活跃 run（防御：
  /// uiPort 本为 run 内注入）时按原样落账。
  void _landAgentSuggestion(AiMessage message) {
    final provider = _observedProvider;
    if (provider == null) return;
    final AgentLoopRunner runner = provider.aiPanel.agentRunner;
    final String? runId = runner.activeRunId;
    if (runId == null || runId.isEmpty) {
      provider.aiPanel.sessionManager.addMessage(message);
      return;
    }
    final Map<String, dynamic>? data = message.toolResultData;
    final Object? agent = data?['agent'];
    if (data == null || agent is! Map<String, dynamic>) {
      provider.aiPanel.sessionManager.addMessage(message);
      return;
    }
    provider.aiPanel.sessionManager.addMessage(
      message.copyWith(
        toolResultData: <String, dynamic>{
          ...data,
          'agent': <String, dynamic>{
            ...agent,
            'runId': runId,
            'stepNo': runner.stepsUsed,
          },
        },
      ),
    );
  }

  /// 轨迹卡步详情「在舞台打开」（T13 入口 → T27/T28 接线，签名 = T23 实态
  /// `(runId, stepNo)`）：**优先查 executor 的 run 内注册表**（T28——全量行
  /// 口径，refId 确定性 `res_<stepNo>`）；查不到（run 已切换 / 引用失效）回落
  /// 消息内快照（≤ D19 快照上限）。SQL 取 call 半条参数。
  void _openStepResultInStage(String runId, int stepNo) {
    final provider = _observedProvider;
    if (provider == null) return;
    final AgentResultRef? registered = provider.aiPanel.agentRunner.executor
        .resultRefOf('res_$stepNo');
    if (registered != null) {
      _stageController.openGrid(registered, null);
      return;
    }
    final messages = provider.aiMessages;
    AiMessage? result;
    for (final message in messages) {
      if (message.id == 'agent_tr_${runId}_$stepNo') {
        result = message;
        break;
      }
    }
    if (result == null) {
      AppLogger.w(
        'AiWorkbenchShell',
        'open in stage: step result message not found ($runId:$stepNo)',
      );
      return;
    }
    final Map<String, dynamic> payload =
        agentPayloadOf(result) ?? const <String, dynamic>{};
    final Object? rawRef = payload['resultRef'];
    if (rawRef is! Map<String, dynamic>) {
      AppLogger.w(
        'AiWorkbenchShell',
        'open in stage: step $stepNo carries no resultRef',
      );
      return;
    }
    String sql = '';
    for (final message in messages) {
      if (message.id == 'agent_tc_${runId}_$stepNo') {
        final Object? argSql = message.toolArguments?['sql'];
        if (argSql is String) sql = argSql;
        break;
      }
    }
    final Object? rawRows = rawRef['snapshotRows'];
    final rows = <Map<String, dynamic>>[
      if (rawRows is List)
        for (final Object? row in rawRows)
          if (row is Map<String, dynamic>) row,
    ];
    final ref = AgentResultRef(
      refId: 'res_$stepNo',
      sql: sql,
      rowCount: (rawRef['rowCount'] as num?)?.toInt() ?? rows.length,
      columns: List<String>.from(
        (rawRef['columns'] as List<Object?>? ?? const <Object?>[])
            .whereType<String>(),
      ),
      rows: rows,
    );
    _stageController.openGrid(ref, null);
  }

  /// 计划门卡消息 → 活跃计划对象（T23 planResolver 接线；注册表落账 =
  /// T28 onPlanApproval 真实现）。解析不到（历史会话 / 注册表无此 id）→
  /// null（计划嵌块防御性不渲染）。
  AgentActionPlan? _resolvePlan(AiMessage gateMessage) {
    final Object? planId = agentPayloadOf(gateMessage)?['planId'];
    if (planId is! String) return null;
    return _planRegistry[planId];
  }

  /// 计划嵌块渲染器（T23 planBlockBuilder 接线 → T28 真回调）：批准/拒绝 →
  /// 计划决策桥（仿 [_pendingGateDecisions] 形态）；生成回退 → executor 组装
  /// 新计划（永不自动执行，AC11.3）；终态重放 → markConsumed（终态呈现，
  /// 不产库操作，AC11.4）。
  Widget _buildPlanBlock(
    BuildContext context, {
    required AiMessage gateMessage,
    required AgentActionPlan plan,
  }) {
    final Map<String, dynamic> payload =
        agentPayloadOf(gateMessage) ?? const <String, dynamic>{};
    final Object? rawRunId = payload['runId'];
    final Object? rawStepNo = payload['stepNo'];
    final String runId = rawRunId is String ? rawRunId : plan.runId;
    final int stepNo = rawStepNo is num ? rawStepNo.toInt() : 0;
    return AgentPlanCard(
      plan: plan,
      callbacks: AgentPlanCallbacks(
        // Fix-E：批准回调携带卡面「本会话内允许」勾选态——forSession →
        // approvedForSession 决策（桥内落账 allowL1 + 审计 allowed_session，
        // AC9.3 勾选路径；未勾选维持 approved 单次语义）。
        onApprove: ({required bool forSession}) => _decidePlan(
          runId,
          stepNo,
          plan,
          forSession
              ? GateCardResult.approvedForSession
              : GateCardResult.approved,
        ),
        onReject: () =>
            _decidePlan(runId, stepNo, plan, GateCardResult.rejected),
        onGenerateRollback: () => unawaited(_generateRollbackPlan(plan)),
        onTerminalReplay: () {
          _planExecutor.markConsumed(
            plan,
            onStateChange: (_) => _refreshPlanCards(),
          );
        },
      ),
    );
  }

  /// 计划卡决策路由（T28）：run 内提交链在等（决策桥命中）→ resolve 桥
  /// （执行由 [_onPlanApproval] 闭包接管）；桥不在（回退计划卡 / 迟到点击）
  /// → 直接路径：pendingApproval → approve + execute；终态 → execute 防重
  /// 守卫（PLAN_ALREADY_EXECUTED，零库操作，AC11.4）。
  void _decidePlan(
    String runId,
    int stepNo,
    AgentActionPlan plan,
    GateCardResult decision,
  ) {
    final Completer<GateCardResult>? completer = _pendingPlanDecisions.remove(
      '$runId:$stepNo',
    );
    if (completer != null) {
      if (!completer.isCompleted) completer.complete(decision);
      return;
    }
    unawaited(() async {
      switch (decision) {
        case GateCardResult.rejected:
          await _planExecutor.reject(
            plan,
            onStateChange: (_) => _refreshPlanCards(),
          );
        case GateCardResult.approved:
          await _executeApprovedPlan(plan, bindRunnerStop: false);
        case GateCardResult.approvedForSession:
          // Fix-F ⑤：直接路径的 approvedForSession 同样落账（与桥路径
          // [_onPlanApproval] 一致，AC9.3——否则勾选路径在回退计划卡上
          // 不生效，两路径语义分裂）。连接 id 取计划 run 快照（D15），空
          // 则传空串（ledger.allowL1 对空串忽略，fail-safe）。
          _observedProvider?.aiPanel.agentRunner.ledger.allowL1(
            plan.ctx.connectionId ?? '',
          );
          await _executeApprovedPlan(plan, bindRunnerStop: false);
      }
    }());
  }

  /// 生成补偿回退计划（T22 buildRollbackPlan → AC11.3 永不自动执行）：
  /// 组装产物注册进注册表 + 合成 `agent_plan` 门卡消息落会话（携带新
  /// planId，轨迹卡 planBlock 渲染新卡）——批准动作走 [_decidePlan] 直接
  /// 路径（同一 L1 门语义：卡上批准才执行）。
  Future<void> _generateRollbackPlan(AgentActionPlan sourcePlan) async {
    final provider = _observedProvider;
    if (provider == null) return;
    final AgentActionPlan? rollbackPlan = await _planExecutor.buildRollbackPlan(
      plan: sourcePlan,
      deps: AgentPlanRollbackDeps(
        primaryKeyColumns: (String table) =>
            _planPrimaryKeyColumns(sourcePlan, table),
        onStateChange: (_) => _refreshPlanCards(),
      ),
    );
    if (rollbackPlan == null) return;
    _planRegistry[rollbackPlan.planId] = rollbackPlan;
    WorkbenchUsageStatsService.instance.recordPlanEvent(AgentPlanStat.shown);
    final AgentLoopRunner runner = provider.aiPanel.agentRunner;
    provider.aiPanel.sessionManager.addMessage(
      AiMessage(
        id: 'agent_gc_plan_${rollbackPlan.planId}',
        isUser: false,
        content: '',
        timestamp: DateTime.now(),
        type: AiMessageType.toolResult,
        toolName: 'agent_plan',
        toolResultSummary:
            'rollback plan of ${sourcePlan.planId} '
            'awaiting approval',
        toolResultData: <String, dynamic>{
          'agent': <String, dynamic>{
            'kind': 'agent_plan',
            'runId': sourcePlan.runId,
            'stepNo': runner.stepsUsed,
            'planId': rollbackPlan.planId,
          },
        },
      ),
    );
  }

  /// 回退推导的 PK 取数（[AgentPlanRollbackDeps.primaryKeyColumns] 绑定点）：
  /// describe → isPrimaryKey 投影；连接/库取计划 run 快照（D15 同源）。
  /// 取数失败抛错 → buildRollbackPlan 的 fail-safe 捕获为无 PK 证据，
  /// 不自动生成回退。
  Future<List<String>> _planPrimaryKeyColumns(
    AgentActionPlan plan,
    String table,
  ) async {
    final provider = _observedProvider;
    if (provider == null) return const <String>[];
    final List<DbColumn> columns = await provider.dbService.getTableColumns(
      table,
      connectionId: plan.ctx.connectionId,
      databaseName: plan.ctx.databaseName,
    );
    return <String>[
      for (final DbColumn column in columns)
        if (column.isPrimaryKey) column.name,
    ];
  }

  /// 门卡消息 planId 回填（T28）：runner 包装层先落 `{kind, runId, stepNo}`
  /// 门卡消息（此时计划尚未传入），本回调拿到计划后回填 planId ——轨迹卡
  /// planResolver 的寻址面（updateMessages 同 runner `_backfillGateOutcome`
  /// 刷新机制）。
  void _backfillPlanIdIntoGateCard(String runId, int stepNo, String planId) {
    final provider = _observedProvider;
    if (provider == null) return;
    final sessionManager = provider.aiPanel.sessionManager;
    final List<AiMessage> messages = sessionManager.currentMessages.toList();
    final int index = messages.indexWhere(
      (AiMessage m) => m.id == 'agent_gc_${runId}_$stepNo',
    );
    if (index == -1) return;
    final Map<String, dynamic>? data = messages[index].toolResultData;
    final Map<String, dynamic>? agent = data?['agent'] as Map<String, dynamic>?;
    if (data == null || agent == null) return;
    messages[index] = messages[index].copyWith(
      toolResultData: <String, dynamic>{
        ...data,
        'agent': <String, dynamic>{...agent, 'planId': planId},
      },
    );
    sessionManager.updateMessages(messages);
  }

  /// 计划卡刷新通道（T22 文件头消费说明：回调即通知）：重写消息列触发
  /// provider → 消息流重建 → 计划卡重读 plan 全量。
  void _refreshPlanCards() {
    final provider = _observedProvider;
    if (provider == null) return;
    final sessionManager = provider.aiPanel.sessionManager;
    sessionManager.updateMessages(sessionManager.currentMessages.toList());
  }

  /// 计划内 DDL 双门确认（AC10.4 不豁免；绑 [DdlConfirmDialog]，沿
  /// WorkbenchExecutionActions 同款语义：context 失效 → aborted 静默中止）。
  Future<SqlGateConfirmDecision> _confirmPlanDdl(
    DdlConfirmationRequiredException e,
  ) async {
    if (!mounted) return SqlGateConfirmDecision.aborted;
    final DdlConfirmResult? result = await showDialog<DdlConfirmResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          DdlConfirmDialog(sql: e.sql, impactReport: e.impactReport),
    );
    if (result != DdlConfirmResult.execute) {
      return SqlGateConfirmDecision.cancelled;
    }
    if (!mounted) return SqlGateConfirmDecision.aborted;
    return SqlGateConfirmDecision.confirmed;
  }

  /// 计划内 DML 门确认（DROP TABLE 等管线 critical 形态；绑
  /// [DmlConfirmDialog]，同款语义）。
  Future<SqlGateConfirmDecision> _confirmPlanDml(
    DmlConfirmationRequiredException e,
  ) async {
    if (!mounted) return SqlGateConfirmDecision.aborted;
    final DmlConfirmResult? confirmResult = await DmlConfirmDialog.show(
      context,
      analysis: e.analysis,
      statements: e.statements,
      dbType: _dbTypeOfConnection(),
    );
    if (confirmResult != DmlConfirmResult.confirm) {
      return SqlGateConfirmDecision.cancelled;
    }
    if (!mounted) return SqlGateConfirmDecision.aborted;
    return SqlGateConfirmDecision.confirmed;
  }

  /// DML 确认对话框方言解析（savedConnections 命中；未命中回退 mysql，
  /// WorkbenchExecutionActions._dbTypeOf 同款兜底）。
  DatabaseType _dbTypeOfConnection() {
    final provider = _observedProvider;
    if (provider == null) return DatabaseType.mysql;
    for (final DbServer server in provider.connection.savedConnections) {
      if (server.id == provider.connection.currentServer?.id) {
        return server.type;
      }
    }
    return DatabaseType.mysql;
  }

  /// 工作台可见性跟踪：上升沿记 entry 统计 + 输入区聚焦（AC1.2 键盘入口）。
  void _syncVisibility() {
    final provider = _observedProvider;
    if (provider == null) return;
    final visible = provider.aiPanelOpen && provider.aiPanelFullscreen;
    final entered = visible && !_workbenchVisible;
    _workbenchVisible = visible;
    if (!entered) return;

    WorkbenchUsageStatsService.instance.recordEntry();
    // 进入即聚焦输入区（纯键盘「进入 → 对话」路径，AC1.2）；等本帧
    // Offstage 翻转完成后再聚焦。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_workbenchVisible) return;
      _findEditableState(context as Element)?.requestKeyboard();
    });
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 工作台入口 intent 消费（2b.4 R7：pending intent → post-frame 推 tab +
  // 预填 prompt + 聚焦输入框 + 清除）。**仅此一处**消费 intent——
  // 数据工具绑定段与舞台布局段零触碰。
  // ──────────────────────────────────────────────────────────────────────────

  /// 检测挂起的入口 intent：非空且 id ≠ 已消费 id → 标记 id（防重入锚）
  /// 并调度 post-frame 消费。挂点 = [_onAppProviderChanged]（运行时请求）
  /// 与 [didChangeDependencies]（装配面首检）——AppProvider 转发 aiPanel
  /// 通知，两条路径覆盖「挂载前请求」与「挂载后请求」全部时序。
  void _checkWorkbenchEntryIntent() {
    if (!mounted) return;
    final provider = _observedProvider;
    if (provider == null) return;
    final intent = provider.aiPanel.workbenchEntryIntent;
    if (intent == null || intent.id == _consumedWorkbenchEntryIntentId) {
      return;
    }
    // 防重入：调度前即标记（同一 id 在 post-frame 执行前的重复通知不再
    // 二次调度；后续新请求 id 自增 → 新调度照常）。
    _consumedWorkbenchEntryIntentId = intent.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consumeWorkbenchEntryIntent(intent);
    });
  }

  /// post-frame 消费：推 tab → 清除 intent →（下一帧）预填 prompt + 聚焦。
  void _consumeWorkbenchEntryIntent(WorkbenchEntryIntent intent) {
    if (!mounted) return;
    final provider = _observedProvider;
    if (provider == null) return;
    // pending 单槽：若已被更新的 intent 覆盖（id 不同）→ 本次调度作废，
    // 交给新 intent 的消费回调（避免旧回调误清新 intent）。
    final pending = provider.aiPanel.workbenchEntryIntent;
    if (pending == null || pending.id != intent.id) return;

    switch (intent.tabTarget) {
      case WorkbenchEntryTabTarget.observe:
        _stageController.openObserve();
        break;
      case WorkbenchEntryTabTarget.savedQueries:
        _stageController.openSavedQueries();
        break;
      case WorkbenchEntryTabTarget.history:
        _stageController.openHistory();
        break;
      case WorkbenchEntryTabTarget.none:
        break;
    }

    provider.aiPanel.consumeWorkbenchEntryIntent();

    final prompt = intent.prompt;
    if (prompt == null || prompt.isEmpty) return;
    // 舞台可见翻转 → 对话列子树换形态重建（_buildChatColumn →
    // _buildStageLayout 分支，输入框随子树新建）——写值必须等本帧重建完成
    // 后再下一帧写，否则落进旧输入框随重建丢弃。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _writeEditableText(prompt);
      _chatInputEditableState()?.requestKeyboard();
    });
  }

  /// 对话列输入框定位（剪除会话栏子树——rail 内容页搜索框在树序上先于
  /// 对话列，不剪枝会把预填写进搜索框；同 [_focusChatColumn] 语义）。
  EditableTextState? _chatInputEditableState() {
    final Element root = context as Element;
    final Element? railSlot = _findElementByKey(
      root,
      const ValueKey('workbench_session_rail_slot'),
    );
    return _findEditableState(root, skipSubtree: railSlot);
  }

  /// 把预填 prompt 写入输入框并把光标移到末尾（2b.4 R7；与
  /// workbench_chat_view 的 _setInputText 同款写值逻辑——两文件均不
  /// import 对方私有成员，各持一份）。
  void _writeEditableText(String text) {
    final editable = _chatInputEditableState();
    if (editable == null) return;
    editable.widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// 在壳子树中查找输入区的 [EditableTextState]（BuildContext 只有向上
  /// 查找 API，向下需自行遍历元素树；壳内唯一 EditableText 即对话列
  /// 输入框。与 workbench_chat_view 的同款私有辅助各持一份——两文件均
  /// 不 import 对方私有成员）。
  ///
  /// [skipSubtree]（A5 对话列区入口用）：命中该元素时整枝剪除——rail 内容
  /// 页（保存的查询/历史）含搜索框，展开态在树序上先于对话列，不剪枝会把
  /// F6 对话列入口错落在 rail 搜索框上；AC1.2 既有调用不传（行为零变化）。
  EditableTextState? _findEditableState(Element root, {Element? skipSubtree}) {
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (skipSubtree != null && identical(element, skipSubtree)) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }

  /// 在子树中查找带 [key] 的元素（向下遍历；A5 对话列区入口定位会话栏
  /// 剪枝元素用）。
  Element? _findElementByKey(Element root, Key key) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      if (element.widget.key == key) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // F6 六区轮转（A5，v2 §8-6）：壳根 Focus onKeyEvent 承接后代未处理的
  // F6/Shift+F6；轮转序 = WorkbenchFocusZone 枚举序，未注册区（舞台收起/
  // rail 收窄）与入口失败区（空舞台/零条目）动态跳过——循环无死区。
  // ──────────────────────────────────────────────────────────────────────────

  /// F6 → 下一区、Shift+F6 → 上一区（R10：不碰 GlobalShortcutsWrapper，
  /// 全局层 return false 后自然落焦点树冒泡到本壳根节点）。
  KeyEventResult _onShellKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.f6) {
      return KeyEventResult.ignored;
    }
    final int direction = HardwareKeyboard.instance.isShiftPressed ? -1 : 1;
    return _cycleFocusZone(direction)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// 区轮转：从当前区下标沿 [direction] 逐区推进一整圈（含回绕），首个
  /// 「已注册且入口成功」的区即落点；全圈无落点返回 false（事件放行）。
  /// Dart 整数 `%` 对负操作数返回非负余数，逆向回绕无需特判。
  bool _cycleFocusZone(int direction) {
    final List<WorkbenchFocusZone> zones = WorkbenchFocusZone.values;
    for (var step = 1; step <= zones.length; step++) {
      final WorkbenchFocusZone zone =
          zones[(_activeZoneIndex + direction * step) % zones.length];
      if (!_focusZoneRegistry.isRegistered(zone)) continue;
      if (_focusZoneRegistry.focus(zone)) {
        _activeZoneIndex = zone.index;
        return true;
      }
    }
    return false;
  }

  /// 对话列区入口（A5）：复用 [_findEditableState] 聚焦输入框（任务书 §6.7
  /// 条款 1），无需改 chat view。从壳根遍历但**剪除会话栏子树**（rail 内容
  /// 页搜索框会先于输入框命中，见 [_findEditableState]）；舞台在树序上后于
  /// 对话列，无需剪除。
  bool _focusChatColumn() {
    if (!mounted) return false;
    final Element root = context as Element;
    final Element? railSlot = _findElementByKey(
      root,
      const ValueKey('workbench_session_rail_slot'),
    );
    final EditableTextState? editable = _findEditableState(
      root,
      skipSubtree: railSlot,
    );
    if (editable == null) return false;
    editable.requestKeyboard();
    return true;
  }

  void _exitWorkbench() {
    context.read<AppProvider>().aiPanel.setAiPanelFullscreen(false);
  }

  /// 舞台可见态下会话栏折叠断点（ui 规格 §5.1：240 + 360 + 480 = 1080；
  /// §5.4-2 边界探针：1080 收 44 / 1081 展开 240）。
  static const double _stageRailCollapseBreakpoint =
      AppDesignSystem.workbenchSessionListWidth +
      AppDesignSystem.workbenchChatMinWidth +
      AppDesignSystem.workbenchStageMinWidth;

  @override
  Widget build(BuildContext context) {
    // 结构（ui 规格 §5.1）：Focus（F6 轮转宿主，A5/R10——本节点不持焦点
    // 不参与遍历，只承接后代未处理键事件的冒泡）> Column[ 主区 Expanded |
    // 产物条 32 全宽常驻 ]。主区 = Row[会话栏 | 对话列（+ 舞台）]；断点按
    // 本壳可用宽（LayoutBuilder）判定——Row 非弹性子项主轴约束无界，沿用
    // T10 先例。舞台可见性驱动整树分支（AnimatedBuilder 消费 controller，
    // openXxx/pin/开关均触发）。
    return Focus(
      canRequestFocus: false,
      includeSemantics: false,
      onKeyEvent: _onShellKeyEvent,
      child: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _stageController,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final stageVisible = _stageController.stageVisible;
                  // 会话栏断点：舞台可见 ≤1080 收 44（三列和），收起时保持 M1
                  // <900 断点（既有会话栏行为零回退）。
                  final railCollapsed = stageVisible
                      ? constraints.maxWidth <= _stageRailCollapseBreakpoint
                      : constraints.maxWidth <
                            WorkbenchSessionRail.collapseBreakpoint;
                  return Row(
                    children: [
                      _buildSessionRailSlot(collapsed: railCollapsed),
                      Expanded(
                        child: stageVisible
                            ? _buildStageLayout(context)
                            : _buildChatColumn(context),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          // 产物条（T25 挂载）：shell 底部全宽常驻（舞台开/关两态均在，
          // ui 规格 §6.4-1）；不包紧高度容器（实测坑——条自带 32 高）。
          WorkbenchArtifactStrip(
            controller: _stageController,
            zoneRegistry: _focusZoneRegistry,
          ),
        ],
      ),
    );
  }

  /// 会话栏（T11 接入：`WorkbenchSessionRail`，展开宽
  /// `workbenchSessionListWidth` 240 token，<900 断点收 44 图标 rail）。
  /// 挂点 key 沿 T10 结构位契约（`workbench_session_rail_slot`）。
  /// R6 接缝（v2 A2）：舞台控制器传入 rail——收窄态活动条点击由 rail 直调
  /// `openSessions()` 开舞台会话列表单例 tab；此后 A3/A4 新增 kind 只改
  /// rail + stage，shell 不再为此改签名。
  Widget _buildSessionRailSlot({required bool collapsed}) {
    return WorkbenchSessionRail(
      key: const ValueKey('workbench_session_rail_slot'),
      collapsed: collapsed,
      stageController: _stageController,
      zoneRegistry: _focusZoneRegistry,
    );
  }

  /// 舞台并置态（ui 规格 §5.1；走查缺陷修复 2026-09-25 弹性化；B3 宽度双模）：
  /// `Row[对话列 弹性 | 舞台 Expanded]`，对话列宽求值（R2 双模）：
  /// 1. 持久化值非空 → 显式宽度模式（用户拖拽/键盘调整过，provider 已钳
  ///    [360, 520]）；
  /// 2. 否则弹性默认 = `clamp(workbenchChatMinWidth, workbenchChatSplitMaxWidth,
  ///    可用宽 × workbenchChatSplitRatio)`——Fix-L 公式原样为缺省分支，
  ///    探针零回退（markdown 会话区随窗口变宽同步变宽，≥1685 触顶 520）。
  /// 求值结果统一过窗口感知 clamp `min(宽, max(360, regionWidth − 480))`
  /// ——舞台恒 ≥ workbenchStageMinWidth(480)，压缩时对话列显示侧先让位、
  /// 落盘值不动。
  ///
  /// 不变式（四条）：
  /// 1. 对话列恒在 [workbenchChatMinWidth(360), workbenchChatSplitMaxWidth(520)]；
  /// 2. 舞台恒 ≥ workbenchStageMinWidth(480)——压缩序 = 对话列先触底 360 →
  ///    会话栏 ≤1080 收 44，无死分支；窗口真实最小 800（main.dart
  ///    WindowOptions minimumSize，minWindowWidth=1024 token 无强制点——
  ///    AI-CW 批文档修正，原「<1024 窗口不可达」系假断言）下全域 region
  ///    ≥ 660（900−240 最坏档）> 360，沿 FC-6 先例不做死分支；
  /// 3. 会话栏折叠断点算式不动（[_stageRailCollapseBreakpoint] =
  ///    240+360+480=1080，用的是对话列下限 360；下限不变 → 断点逻辑零改动）；
  /// 4. 「永不自动收起舞台」（B3 守卫）：本布局是纯投影，缩窗/求值路径
  ///    无任何 `setStageVisible(false)` 调用——舞台可见性由四个用户入口
  ///    驱动：产物条展开钮（仅收起态渲染，走查修复批件①收窄）/ 舞台
  ///    tab 条收起钮（展开态，tab 条右端）/ openXxx 自动展开 / 产物条
  ///    pinned 项点击自动展开。
  ///
  /// 可用宽取会话栏右侧 `Expanded` 实得宽（此处嵌套 LayoutBuilder 取
  /// `constraints.maxWidth`；外层 LayoutBuilder 断点判定逻辑不动、不上提合并）。
  /// 舞台保持吃余量（Positioned.fill）。图表不适配出口接 M1 经典跳转
  /// （新 tab 不覆盖）。
  ///
  /// B3 分隔条叠层（R1 零布局占位）：`Stack(clipBehavior: Clip.none)` 包住
  /// 整个 Row，`Positioned(left: chatWidth − 6, width: 12, top/bottom: 0)`
  /// ——12px 命中区居中悬挂在对话列右缘边界、左右各溢出 6px，0px 布局宽。
  /// ⚠ 架构偏差（任务书 §6.6 草图修正，架构师 2026-09-26 批准）：叠层必须挂
  /// 跨两列的公共祖先 Stack，而非任务书原草图「舞台 Expanded 内包 Stack +
  /// Positioned(left: -6)」——边界左侧 6px 的点落在对话列盒子内，被
  /// `RenderBox.hitTest` 的 `_size.contains` 尺寸门派给对话列子树
  /// （rendering/box.dart），舞台侧 Stack 自身尺寸不含该点、永远轮不到
  /// 子节点命中，±5px 双侧命中在原结构下不可能（勿按原草图改回）。
  Widget _buildStageLayout(BuildContext context) {
    final double? persisted = context
        .watch<LayoutPreferencesProvider>()
        .workbenchChatSplitWidth;
    return LayoutBuilder(
      builder: (context, constraints) {
        final double regionWidth = constraints.maxWidth;
        final double chatWidth = _resolveChatSplitWidth(persisted, regionWidth);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  SizedBox(
                    width: chatWidth,
                    child: _buildChatColumnBody(context),
                  ),
                  Expanded(
                    child: WorkbenchStage(
                      controller: _stageController,
                      onOpenInClassic: (sql) => _openInClassic(sql),
                      zoneRegistry: _focusZoneRegistry,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: chatWidth - 6,
              top: 0,
              bottom: 0,
              width: 12,
              child: WorkbenchSplitResizer(
                key: const ValueKey('workbench_split_resizer'),
                isResizing: _chatSplitResizing,
                onResizeStart: () => _beginChatSplitResize(chatWidth),
                onResizeUpdate: _updateChatSplitResize,
                onResizeEnd: _endChatSplitResize,
                onKeyboardResize: (delta) =>
                    _keyboardChatSplitResize(delta, chatWidth),
                onReset: _resetChatSplitWidth,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 对话列宽度求值（R2 双模 + 窗口感知 clamp，语义见 [_buildStageLayout]）。
  double _resolveChatSplitWidth(double? persisted, double regionWidth) {
    final double desired =
        _dragChatSplitWidth ??
        persisted ??
        (regionWidth * AppDesignSystem.workbenchChatSplitRatio)
            .clamp(
              AppDesignSystem.workbenchChatMinWidth,
              AppDesignSystem.workbenchChatSplitMaxWidth,
            )
            .toDouble();
    return math.min(
      desired,
      math.max(
        AppDesignSystem.workbenchChatMinWidth,
        regionWidth - AppDesignSystem.workbenchStageMinWidth,
      ),
    );
  }

  // ── B3：对话列宽度拖拽 / 键盘（WorkbenchSplitResizer 回调装配）──

  /// 拖拽开始：以当前显示宽为基线切入内存显示态（零落盘、零 notify）。
  void _beginChatSplitResize(double baseWidth) {
    setState(() {
      _chatSplitResizing = true;
      _dragChatSplitWidth = baseWidth;
    });
  }

  /// 拖拽中：只改内存显示宽（钳 [360, 520]，与落盘钳制一致——显示值即
  /// 松手后的持久化值）；向右拖对话列变宽。
  void _updateChatSplitResize(double delta) {
    final double? current = _dragChatSplitWidth;
    if (current == null) {
      return;
    }
    setState(() {
      _dragChatSplitWidth = (current + delta).clamp(
        AppDesignSystem.workbenchChatMinWidth,
        AppDesignSystem.workbenchChatSplitMaxWidth,
      );
    });
  }

  /// 拖拽结束：一次性落盘后回双模求值（无位移的纯点击零写入、零模式切换）。
  void _endChatSplitResize() {
    final double? finalWidth = _dragChatSplitWidth;
    setState(() {
      _chatSplitResizing = false;
      _dragChatSplitWidth = null;
    });
    if (finalWidth != null) {
      unawaited(
        context.read<LayoutPreferencesProvider>().setWorkbenchChatSplitWidth(
          finalWidth,
        ),
      );
    }
  }

  /// 键盘步进：即时生效 + 即时落盘（任务书 B3 实施步骤 3）。
  void _keyboardChatSplitResize(double delta, double currentWidth) {
    unawaited(
      context.read<LayoutPreferencesProvider>().setWorkbenchChatSplitWidth(
        currentWidth + delta,
      ),
    );
  }

  /// Home 复位 360（写盘——任务书允许自决项，采「建议写盘 360」）。
  void _resetChatSplitWidth() {
    unawaited(
      context.read<LayoutPreferencesProvider>().setWorkbenchChatSplitWidth(
        AppDesignSystem.workbenchChatMinWidth,
      ),
    );
  }

  /// 舞台收起态对话列（AI-CW 批，2026-09-29：吃满 rail 右侧 region）。
  ///
  /// 原 M1 布局「360–760 居中封顶」在高分屏（逻辑视口 1700–1900+）两侧各空
  /// 350–550，本批删除 `Center + ConstrainedBox` 外壳，列直接吃满 build 里
  /// `Expanded` 提供的 region（rail 右侧全域）。行长可读性改由气泡内层 cap
  /// 承接：[AppDesignSystem.workbenchChatReadableMaxWidth] 经
  /// WorkbenchChatView → AiMessageItem.readableMaxWidth 注入（纯文本气泡
  /// min(0.82×region, 640)，SQL/结果卡继续吃满）。
  ///
  /// region 下限推导（勿写 1024）：rail 展开宽 240（workbenchSessionListWidth），
  /// <900 断点收 44（WorkbenchSessionRail.collapseBreakpoint）。窗口真实最小
  /// 800（main.dart WindowOptions minimumSize；注意 minWindowWidth=1024 token
  /// 无任何强制点）：800 下 rail 恒收 44 → region 756；900 恰触发展开 →
  /// region = 900 − 240 = 660 为全域最坏，均 > workbenchChatMinWidth(360)，
  /// 无下限死区。
  Widget _buildChatColumn(BuildContext context) {
    return _buildChatColumnBody(context);
  }

  /// 对话列本体（两态共用）：顶栏 40 + [WorkbenchChatView]（T27 加注 uiPort /
  /// 在舞台打开 / 计划嵌块三缝，随既有 actions/agentGates 同路由）。
  Widget _buildChatColumnBody(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: WorkbenchChatView(
            actions: _cardActions,
            agentGates: _agentGateCallbacks,
            onGateDecision: _resolveGateDecision,
            uiPort: _agentUiPort,
            onOpenResultInStage: _openStepResultInStage,
            planResolver: _resolvePlan,
            planBlockBuilder: _buildPlanBlock,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 卡动作注入（T13：执行编排 + 互跳出口；T12 的过渡 openQueryTab 接线已替换）
  // ──────────────────────────────────────────────────────────────────────────

  WorkbenchCardActions get _cardActions => WorkbenchCardActions(
    onExecuteSql: (sql) => _runExecution(sql),
    onOpenSqlInClassic: (sql) => _openInClassic(sql),
    onOpenResultInGrid: _openCardResultInStage,
    onOpenResultInClassic: (payload) => _openInClassic(payload.sql),
    onRetryError: (error) => _runExecution(error.sql),
    onOpenErrorInClassic: (error) => _openInClassic(error.sql),
    onSaveQuery: (sql) => unawaited(_saveSqlAsSavedQuery(sql)),
  );

  Future<void> _runExecution(String sql) {
    return WorkbenchExecutionActions.run(
      context,
      sql,
      allowedWriteServers: _allowedWriteServers,
      onExecutionBatch: _pushExecutionBatch,
    );
  }

  /// B1 execution tab 推送入口（手动卡执行通道，R4 单例键 'manual' 复用
  /// 刷新）：批次投影由 [WorkbenchExecutionActions.run] 批末组装（R3 推送
  /// 条件已在组装侧保证），本回调只负责开 tab——纯只读投影，执行路径零
  /// 改动。
  void _pushExecutionBatch(StageExecutionData data) {
    if (!mounted) return;
    _stageController.openExecution(data);
  }

  Future<void> _openInClassic(String sql) {
    return WorkbenchOpenInClassic.open(context, sql);
  }

  /// 结果卡「在舞台打开」（v2 B2 改路由，原 `_openInClassic(payload.sql)`
  /// 过渡接线替换）：组装 [AgentResultRef]（refId = `card_<cardId>`，
  /// cardId = 承载卡的消息 id）→ [_stageController.openGrid]——同 refId
  /// 网格 tab 已存在则复用激活，不重复建 tab。
  ///
  /// R7 快照语义：卡只持 ≤N 行快照（[WorkbenchResultCardPayload.snapshotRows]，
  /// `toolCardSnapshotRows`），经卡打开的舞台网格 tab 呈现**快照全量**——
  /// 不重执行、不补全（自动执行违例，一票否决）；完整数据出口恒为
  /// 「在经典中打开」（[WorkbenchCardActions.onOpenResultInClassic] 原语义
  /// 零变化）。与轨迹卡步详情入口（[_openStepResultInStage]）走同一
  /// controller 方法 [WorkbenchStageController.openGrid]。
  void _openCardResultInStage(
    WorkbenchResultCardPayload payload,
    String cardId,
  ) {
    final ref = AgentResultRef(
      refId: 'card_$cardId',
      sql: payload.sql,
      rowCount: payload.rowCount,
      columns: payload.columns,
      rows: payload.snapshotRows,
    );
    _stageController.openGrid(ref, null);
  }

  /// 「保存为查询」出口（SQL 卡动作）：生效上下文（锁定快照优先，与执行流
  /// 同判据）→ 命名对话框 → 组 [QueryTab]（savedQueryId 空 = 新建）经
  /// AppProvider facade 落 `TabProvider.saveQuery` → 结果 SnackBar。
  ///
  /// 守卫与错误（全部 SnackBar）：空 SQL；无生效连接 → 提示先选择连接 +
  /// 打开既有 [WorkbenchContextPicker]（与芯片未设置态同一出口）；同名冲突
  /// （DuplicateSavedQueryNameException）→ 提示改名重试；其余异常 → 通用
  /// 失败提示（AppErrorHandler 标准错误面）。
  Future<void> _saveSqlAsSavedQuery(String sql) async {
    final AppProvider? provider = _observedProvider;
    if (provider == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;

    // ① 空白守卫（经典 _saveCurrentQuery 同款，防御空卡数据）。
    final String trimmed = sql.trim();
    if (trimmed.isEmpty) {
      AppErrorHandler.showErrorSnackBar(context, l10n.queryEmptyCannotSave);
      return;
    }

    // ② 上下文复核（执行时取值，不信任建卡快照——与执行流同判据）。
    final WorkbenchContextValue ctx = effectiveWorkbenchContext(
      provider.aiPanel.sessionManager.currentSession,
      provider,
    );
    final String? connectionId = ctx.connectionId;
    if (connectionId == null) {
      AppErrorHandler.showWarningSnackBar(
        context,
        l10n.workbenchSaveQuerySelectConnection,
      );
      unawaited(WorkbenchContextPicker.show(context));
      return;
    }

    // ③ 命名（默认名 = SQL 首个非空行截断；取消/空名零保存）。
    final String? title = await showSaveQueryNamingDialog(
      context,
      initialName: _suggestSavedQueryName(trimmed),
    );
    if (title == null || title.isEmpty || !mounted) return;

    final QueryTab savedTab = QueryTab(
      id: 'wb_save_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      sql: trimmed,
      connectionId: connectionId,
      databaseName: ctx.databaseName,
      databaseType: _savedQueryDbTypeOf(provider, connectionId),
    );

    try {
      final bool success = await provider.saveQuery(savedTab);
      if (!mounted) return;
      if (success) {
        AppErrorHandler.showSuccessSnackBar(context, l10n.querySaved(title));
      } else {
        // saveQuery 返回 false = 标题空（已被对话框守卫）——保持可感兜底。
        AppErrorHandler.showWarningSnackBar(
          context,
          l10n.saveQueryLimitReached,
        );
      }
    } on DuplicateSavedQueryNameException catch (e) {
      if (mounted) {
        AppErrorHandler.showWarningSnackBar(
          context,
          l10n.savedQueryNameExists(e.title),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e(
        'AiWorkbenchShell',
        'save sql card as query failed',
        e,
        stackTrace,
      );
      if (mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.saveQueryFailed(e.toString()),
        );
      }
    }
  }

  /// 默认名建议：SQL 首个非空行截断 40 字符（经典 `_generateSavedQueryName`
  /// 同款口径）；全空行回落「Save Query」文案（saveQueryTitle）。
  String _suggestSavedQueryName(String sql) {
    final String firstLine = sql
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim();
    if (firstLine.isEmpty) return AppLocalizations.of(context)!.saveQueryTitle;
    return firstLine.length > 40
        ? '${firstLine.substring(0, 40)}...'
        : firstLine;
  }

  /// 保存查询方言解析（savedConnections 命中取真实 type；未命中 null——
  /// 保存面不虚构方言，打开时由连接上下文补齐）。
  static DatabaseType? _savedQueryDbTypeOf(
    AppProvider provider,
    String connectionId,
  ) {
    for (final DbServer server in provider.savedConnections) {
      if (server.id == connectionId) return server.type;
    }
    return null;
  }

  /// 顶栏：上下文芯片行（T11 接入：`WorkbenchContextChip`）+ 会话累计
  /// chip（T30，AC3.2，落芯片行右侧）+ 退出按钮（AC1.1 ③ z2 内退出回
  /// 经典；IconButton 焦点可达，AC1.2）。
  Widget _buildTopBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          // 芯片行（T11 接入：`WorkbenchContextChip`）。挂点 key 沿 T10
          // 结构位契约（`workbench_context_chip_slot`）。
          const Expanded(
            child: WorkbenchContextChip(
              key: ValueKey('workbench_context_chip_slot'),
            ),
          ),
          const _SessionTokensChip(),
          const SizedBox(width: AppDesignSystem.space1),
          IconButton(
            key: const ValueKey('workbench_exit_button'),
            icon: const Icon(LucideIcons.minimize, size: 16),
            color: context.themeColors.textSecondary,
            onPressed: _exitWorkbench,
            tooltip: l10n.workbenchExit,
          ),
        ],
      ),
    );
  }
}

/// 会话累计 chip（T30，AC3.2）：当前会话全部 `agent_run_end` 终局消息的
/// tokens 求和 + 步数合计。
///
/// 数据源 = 会话消息本身（§5.2 终局消息，会话文件即源）：不持久化、不建
/// 缓存 / 新 Provider——每次 build 从 `provider.aiMessages` 重算投影，切换
/// 会话 / 终局消息落地 / 终局回填经既有通知链（sessionManager →
/// AiPanelProvider → AppProvider）触发重建，天然「切换会话重算」。
///
/// 口径（与 AC3.4 同源降级）：
/// - `tokens` 键缺席的 run 不计入 token 和（提供商未报即无数可累加）；
///   其 `steps` 恒有值，仍计入步数合计；
/// - 无任何含 tokens 的 run（含空会话）→ 整 chip 隐藏（零态自决：芯片行
///   已有上下文芯片，恒显「Session 0 tok」属噪声；单 run 级「—」降级仍在
///   轨迹卡头部承载）。
///
/// 视觉（§6 计划期发现 #5：无专属规格，按 ui 规格 §0.1 既有 chip 语法）：
/// 高 18（padding h space1_5 / v 2，radiusSm）+ bgTertiary 底 + 11px
/// textPrimary w500，数值段 mono（沿轨迹卡 token 文本 mono 先例）；步数
/// 合计以「 · 」衔接（复用 `agentTrajectoryStepsOnly`，不新增 ARB key）。
class _SessionTokensChip extends StatelessWidget {
  const _SessionTokensChip();

  @override
  Widget build(BuildContext context) {
    final AppProvider provider = context.watch<AppProvider>();
    int tokensTotal = 0;
    int stepsTotal = 0;
    bool anyTokens = false;
    for (final AiMessage message in provider.aiMessages) {
      if (agentKindOf(message) != 'agent_run_end') continue;
      final Map<String, dynamic> payload = agentPayloadOf(message)!;
      final Object? steps = payload['steps'];
      if (steps is num) stepsTotal += steps.toInt();
      final Object? tokens = payload['tokens'];
      if (tokens is num) {
        anyTokens = true;
        tokensTotal += tokens.toInt();
      }
    }
    // 零态：无任何含 tokens 的 run → 不渲染（含空会话）。
    if (!anyTokens) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final String label =
        '${l10n.agentSessionTokens(agentTrajectoryCompactTokens(tokensTotal))}'
        ' · ${l10n.agentTrajectoryStepsOnly(stepsTotal)}';
    return Container(
      key: const ValueKey('workbench_session_tokens_chip'),
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
          fontSize: 11,
          fontWeight: FontWeight.w500,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}
