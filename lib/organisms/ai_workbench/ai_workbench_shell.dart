//! AI 工作台外壳（z2 全屏态宿主，design-ai-workbench §4.1 / D1 / D2）。
//!
//! z2 层（`lib/screens/home/ai_fullscreen_overlay.dart`）的全屏分支渲染本
//! 组件，并以 Offstage 常驻挂载保活（D4：切换不销毁——会话/输入草稿/滚动
//! 位跨模式存活，AC1.4；会话数据本身在 AiPanelProvider，本就与模式无关）。
//!
//! 结构（AC1.3 对话为视觉主体）：
//! `Row[ 会话栏（WorkbenchSessionRail，T11） | 对话列（360-760 居中） ]`，
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
//! 舞台可见 → `Row[会话栏 240（≤1080 收 44）| 对话列 360 固定 | 舞台
//! Expanded ≥480]`，收起 → 舞台不入树、对话列恢复 M1 360–760 居中；
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

import 'dart:async' show Completer, unawaited;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_message_type.dart' show AiMessageType;
import '../../models/database_models.dart'
    show AiMessage, DatabaseType, DbColumn, DbIndex, DbServer, ForeignKey;
import '../../models/dml_risk_models.dart'
    show DmlConfirmationRequiredException;
import '../../providers/app_provider.dart';
import '../../providers/ai_panel_provider.dart'
    show WorkbenchAgentContextSnapshot;
import '../../providers/locale_provider.dart';
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
        AgentPlanStatEvent;
import '../../services/ai/agent/agent_tool_executor.dart'
    show AgentPlanApprovalCallback, GateCallbacks;
import '../../services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, GateCardResult;
import '../../services/ai/workbench_context_resolver.dart'
    show effectiveWorkbenchContext;
import '../../services/database_service.dart'
    show DdlConfirmationRequiredException;
import '../../services/sql_statement_gate_runner.dart'
    show SqlGateConfirmDecision;
import '../../services/workbench_usage_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_logger.dart';
import '../ai_panel/ddl_confirm_dialog.dart'
    show DdlConfirmDialog, DdlConfirmResult;
import '../dialogs/dml_confirm_dialog.dart'
    show DmlConfirmDialog, DmlConfirmResult;
import 'agents/agent_plan_card.dart';
import 'agents/agent_trajectory_card.dart'
    show agentKindOf, agentPayloadOf, agentTrajectoryCompactTokens;
import 'agent_ui_port_impl.dart';
import 'workbench_artifact_strip.dart';
import 'workbench_card_host.dart';
import 'workbench_chat_view.dart';
import 'workbench_context_chip.dart';
import 'workbench_execution_actions.dart';
import 'workbench_open_in_classic.dart';
import 'workbench_session_rail.dart';
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
  late final WorkbenchStageController _stageController = WorkbenchStageController();

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
  final Map<String, AgentActionPlan> _planRegistry = <String, AgentActionPlan>{};

  /// 在途计划卡决策桥（T28）：key = `'<runId>:<stepNo>'`（与门卡消息载荷
  /// 同源）→ Completer。批准/拒绝由计划卡回调 resolve；运行收敛时以
  /// rejected 解决（停止/会话切换 → 计划随运行取消，零执行）。
  final Map<String, Completer<GateCardResult>> _pendingPlanDecisions =
      <String, Completer<GateCardResult>>{};

  /// 计划执行器（T28 装配）：决策（approve/reject 幂等）+ 逐语句执行 +
  /// 审计（默认绑 AuditLogService）+ 统计（AgentPlanStatEvent → 统计服务
  /// 枚举按 name 桥接，T22 文件头桥接说明——两处枚举值需同步）。
  late final AgentPlanExecutor _planExecutor = AgentPlanExecutor(
    recordPlanEvent: (AgentPlanStatEvent event) =>
        WorkbenchUsageStatsService.instance.recordPlanEvent(
          AgentPlanStat.values.byName(event.name),
        ),
  );

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
    }
  }

  @override
  void dispose() {
    _observedAgentRunner?.removeListener(_onAgentRunnerChanged);
    _observedAgentRunner = null;
    _observedProvider?.removeListener(_onAppProviderChanged);
    _observedProvider = null;
    _stageController.dispose();
    super.dispose();
  }

  void _onAppProviderChanged() {
    _syncVisibility();
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
    final List<Completer<GateCardResult>> pending = List<
      Completer<GateCardResult>
    >.of(_pendingPlanDecisions.values);
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
      final Completer<GateCardResult> completer =
          Completer<GateCardResult>();
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
    WorkbenchUsageStatsService.instance.recordPlanEvent(
      AgentPlanStat.shown,
    );

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
    await _planExecutor.execute(
      plan: plan,
      deps: _planExecutionDeps(plan, bindRunnerStop: bindRunnerStop),
    );
  }

  /// 计划执行环境（[AgentPlanExecutionDeps]）：执行通道 = AppProvider
  /// facade（readOnly 检查 / DML 拦截 / DDL 双门 / 行限 / 网关路由全继承）；
  /// 确认面 = 本壳对话框；shouldContinue = 壳存活 + （桥路径）runner 停止
  /// 态探针（Fix-F ②）。连接/库取**计划自带的 run 快照**（plan.ctx，
  /// D15——全程只读同一快照，不随侧栏/tab 漂移）。
  AgentPlanExecutionDeps _planExecutionDeps(
    AgentActionPlan plan, {
    required bool bindRunnerStop,
  }) {
    // 非空已证：调用方 [_executeApprovedPlan] 先行判空返回（MAY-2 例外）。
    final AppProvider provider = _observedProvider!;
    final String? connectionId = plan.ctx.connectionId;
    final String? databaseName = plan.ctx.databaseName;
    return AgentPlanExecutionDeps(
      execute: (String statement) =>
          provider.executeQuery(statement, connectionId: connectionId, database: databaseName),
      executeBypassDdl: (String statement) => provider.dbService
          .executeQueryBypassDdl(
            statement,
            connectionId: connectionId,
            database: databaseName,
          ),
      executeBypassDml: (String statement) => provider.dbService
          .executeQueryBypassDml(
            statement,
            connectionId: connectionId,
            database: databaseName,
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
  void _resolveGateDecision(
    String runId,
    int stepNo,
    GateCardResult decision,
  ) {
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
          _planExecutor.markConsumed(plan, onStateChange: (_) => _refreshPlanCards());
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
          await _planExecutor.reject(plan, onStateChange: (_) => _refreshPlanCards());
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
        toolResultSummary: 'rollback plan of ${sourcePlan.planId} '
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
  void _backfillPlanIdIntoGateCard(
    String runId,
    int stepNo,
    String planId,
  ) {
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

  /// 在壳子树中查找输入区的 [EditableTextState]（BuildContext 只有向上
  /// 查找 API，向下需自行遍历元素树；壳内唯一 EditableText 即对话列
  /// 输入框。与 workbench_chat_view 的同款私有辅助各持一份——两文件均
  /// 不 import 对方私有成员）。
  EditableTextState? _findEditableState(Element root) {
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
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
    // 结构（ui 规格 §5.1）：Column[ 主区 Expanded | 产物条 32 全宽常驻 ]。
    // 主区 = Row[会话栏 | 对话列（+ 舞台）]；断点按本壳可用宽（LayoutBuilder）
    // 判定——Row 非弹性子项主轴约束无界，沿用 T10 先例。舞台可见性驱动整树
    // 分支（AnimatedBuilder 消费 controller，openXxx/pin/开关均触发）。
    return Column(
      children: [
        Expanded(
          child: AnimatedBuilder(
            animation: _stageController,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                final stageVisible = _stageController.stageVisible;
                // 会话栏断点：舞台可见 ≤1080 收 44（三列和），收起时保持 M1
                // <900 断点（既有会话栏行为零回退）。
                final railCollapsed =
                    stageVisible
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
        WorkbenchArtifactStrip(controller: _stageController),
      ],
    );
  }

  /// 会话栏（T11 接入：`WorkbenchSessionRail`，展开宽
  /// `workbenchSessionListWidth` 240 token，<900 断点收 44 图标 rail）。
  /// 挂点 key 沿 T10 结构位契约（`workbench_session_rail_slot`）。
  Widget _buildSessionRailSlot({required bool collapsed}) {
    return WorkbenchSessionRail(
      key: const ValueKey('workbench_session_rail_slot'),
      collapsed: collapsed,
    );
  }

  /// 舞台并置态（ui 规格 §5.1）：`Row[对话列 360 固定 | 舞台 Expanded]`。
  /// 舞台 ≥480 由断点算式保证（会话栏 ≤1080 折叠后 1024 窗口下舞台实得
  /// 1024 − 44 − 360 = 620；<884 输入不可达，FC-6 不做死分支）。图表不适配
  /// 出口接 M1 经典跳转（新 tab 不覆盖）。
  Widget _buildStageLayout(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: AppDesignSystem.workbenchChatMinWidth,
          child: _buildChatColumnBody(context),
        ),
        Expanded(
          child: WorkbenchStage(
            controller: _stageController,
            onOpenInClassic: (sql) => _openInClassic(sql),
          ),
        ),
      ],
    );
  }

  /// 舞台收起态（M1 布局零回退）：对话列 360–760 居中。
  Widget _buildChatColumn(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        // §8【二】：对话列 360-760，超出居中（舞台可见时改固定 360，见
        // [_buildStageLayout]）。
        constraints: const BoxConstraints(
          minWidth: AppDesignSystem.workbenchChatMinWidth,
          maxWidth: AppDesignSystem.workbenchChatMaxWidth,
        ),
        child: _buildChatColumnBody(context),
      ),
    );
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
    onOpenResultInGrid: (payload) => _openInClassic(payload.sql),
    onOpenResultInClassic: (payload) => _openInClassic(payload.sql),
    onRetryError: (error) => _runExecution(error.sql),
    onOpenErrorInClassic: (error) => _openInClassic(error.sql),
  );

  Future<void> _runExecution(String sql) {
    return WorkbenchExecutionActions.run(
      context,
      sql,
      allowedWriteServers: _allowedWriteServers,
    );
  }

  Future<void> _openInClassic(String sql) {
    return WorkbenchOpenInClassic.open(context, sql);
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
