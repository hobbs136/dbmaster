/// Agent 回路运行器（tasks-ai-agent.md T11 / design-ai-agent.md §4.3、§5.1、
/// §5.2、§6.4、§6.5、D11、D15、D17、D18、D19）。
///
/// 核心状态机（ChangeNotifier，UI 经 ListenableBuilder 监听，AC3.1）：
///
/// ```
/// idle ──start()──► running ──┬─ tool_calls 空 ──────────────► completed
///                             ├─ 门 confirm ──► awaitingUser ─┬─ 决策 ──► running
///                             │              （停止 → rejected）└────────► stoppedByUser
///                             ├─ requestStop（当前步完成）──► stopping ──► stoppedByUser
///                             ├─ 预算耗尽 ───────────────────► stoppedByLimit
///                             ├─ 连续失败 ≥5 ────────────────► stoppedByFailures
///                             ├─ 上下文缺失（②a/②b CONTEXT_REQUIRED）──► stoppedByContext
///                             └─ chat() 抛出 ────────────────► failed
/// 所有终态 ──新 start()──► running（新 runId；账本跨 run 保留、随会话/连接失效）
/// ```
///
/// 不变式（§6.5）：`isRunning ⇔ status ∈ {running, awaitingUser, stopping}`
/// （AC1.7 发送守卫读此值）；任何终态必有终局消息（崩溃除外——由 §5.2
/// 中断态渲染兜底，runner 不从消息恢复运行态，FC-6）。
///
/// 五停止源统一收敛（§6.4 四源 + T2 方案 B 上下文缺失终止，全部落终局消息）：
/// - 用户停止（AC1.3）：在途工具调用**完成**（结果保留）；awaitingUser 的
///   Completer 以 rejected 解决（卡上「已随运行取消」）；不再发起新轮；
/// - 超限（AC2.2）：派发前预算检查——预算内调用执行完（部分执行语义），
///   剩余 tool_calls 不派发（回喂 `STEP_LIMIT_REACHED` 占位保持协议完整）；
///   **不自动请求继续**（AC2.4：用户发新指令接续，新 run seed 自会话历史）；
/// - 失败自纠上限（D18/NF3.2）：连续 5 个失败工具调用即停；成功清零；
///   chat 层提供商错误**不走此计数**（→ failed 态，AC15.5）；
/// - 上下文缺失（T2 方案 B / FU-10 收口）：数据类工具被门 ②a/②b 以
///   `CONTEXT_REQUIRED` 拒绝 → 立即终止 `stoppedByContext` + 终局引导选库
///   （顶部上下文芯片）；同批剩余 tool_calls 回喂 CONTEXT_REQUIRED 占位
///   （协议完整，不执行不计步）——不再进入下一轮让模型用 information_schema /
///   系统库绕行烧满步限；
/// - 提供商错误：`chat()` 抛出（chat 层重试 3 次后）→ 运行级失败。
///
/// 消息流（§5.2，D2 落同一会话账本）：runner 落**用户消息 / 轨迹锚点 /
/// 门卡宿主 / 终局**四类 + executor 步消息对（callMessage/resultMessage，
/// T10 产出、本类经 sessionManager.addMessage 落账）。运行内 LLM 消息列
/// （含 D19 双上限截断的 20 行快照）只进内存，不落会话文件（防膨胀）。
///
/// 构造注入面：executor / sessionManager / run 上下文快照解析 / chat 配置
/// 解析为生产装配必填（T14 闭包装配——runner 不 import providers，组件级
/// §0-8 跨 Provider 通信禁令）；chat / maxSteps / 统计有生产默认（测试注入
/// fake，NF5.3）。
///
/// 本文件不 import material（ChangeNotifier 用 foundation，组件级 §0
/// MUST NOT 2）；不触经典路径（AiSessionOrchestrator 零改动）；不绕过
/// executor 直接执行工具（D3）；应用退出即对象消亡（无 isolate/timer，
/// NF3.3）。
library;

import 'dart:async' show Completer;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../../models/ai_memory_item.dart' show AiMemoryItem;
import '../../../models/ai_message_type.dart'
    show AiMessageStatus, AiMessageType;
import '../../../models/ai_models.dart' show ChatResponse, TokenUsage;
import '../../../models/database_models.dart' show AiMessage;
import '../../../utils/app_logger.dart' show AppLogger;
import '../../../utils/secret_redactor.dart' show redactSecrets;
import '../../ai/ai_memory_service.dart' show AiMemoryService;
import '../../ai_service.dart' show AiService;
import '../../query_settings_service.dart' show QuerySettingsService;
import '../../workbench_usage_stats_service.dart'
    show WorkbenchUsageStatsService;
import '../ai_context_builder.dart' show AiContextBuilder, BuildContextResult;
import '../ai_session_manager.dart' show AiSessionManager;
import 'agent_gate.dart' show AgentRunContext;
import 'agent_gate_analysis.dart' show ReadImpactAnalysis;
import 'agent_permission_ledger.dart' show AgentPermissionLedger;
import 'agent_plan.dart' show AgentActionPlan;
import 'agent_tool_catalog.dart' show AgentToolCatalog, AgentToolErrorCodes;
import 'agent_tool_executor.dart'
    show AgentToolCall, AgentToolExecutor, AgentToolOutcome, GateCallbacks;
import 'agent_ui_port.dart' show AgentUiPort, GateCardResult;

/// agent 运行状态（design §4.3 枚举原文；T2 方案 B 尾部追加
/// [stoppedByContext]——既有值与序不动）。
enum AgentRunStatus {
  idle,
  running,
  awaitingUser, // 门卡/计划卡等待人决策
  stopping, // 已请求停止，当前步收尾中
  completed,
  stoppedByUser,
  stoppedByLimit,
  stoppedByFailures,
  failed, // AI 提供商错误（AC15.5）
  stoppedByContext, // 上下文缺失终止（T2 方案 B：门 ②a/②b CONTEXT_REQUIRED）
}

/// 一次 chat 调用的配置（生产由 T14 闭包解析自 AppProvider 的 AI 配置面；
/// runner 不 import providers——组件级 §0-8 跨 Provider 通信禁令）。
class AgentChatConfig {
  const AgentChatConfig({
    required this.provider,
    required this.model,
    required this.apiKey,
    this.baseUrl,
    this.timeout = const Duration(seconds: 60),
    this.locale = 'en',
  });

  final String provider;
  final String model;
  final String apiKey;
  final String? baseUrl;

  /// AiClient.chat 的 timeout（沿 provider.aiTimeout 语义）。
  final Duration timeout;

  /// 汇报文案语言（AiServiceLocalizations 先例：'zh' 回中文，其余英文）。
  final String locale;
}

/// chat 调用函数类型（签名 = `AiClient.chat` 命名参数子集；生产默认 =
/// `AiService().client.chat` tear-off，测试注入脚本化 fake）。
typedef AgentChatFn =
    Future<ChatResponse> Function({
      required String provider,
      required String model,
      required String apiKey,
      String? baseUrl,
      required String message,
      String? systemPrompt,
      List<Map<String, dynamic>>? history,
      Duration timeout,
      List<Map<String, dynamic>>? tools,
    });

/// run 启动上下文快照解析函数（D15：一次快照全程只读——AC7.2 运行中
/// 切侧栏/tab 读取来源不漂移的结构保证）。生产由 T14 闭包绑
/// `effectiveWorkbenchContext` + savedConnections（dbType/readOnly）。
typedef AgentRunContextResolver = AgentRunContext Function(String runId);

/// chat 配置解析函数（start 时读一次）。
typedef AgentChatConfigResolver = AgentChatConfig Function();

/// maxSteps 解析函数（AC2.1：启动时读，运行中不改；生产默认 =
/// `QuerySettingsService.getAgentMaxSteps`）。
typedef AgentMaxStepsResolver = Future<int> Function();

/// 系统提示词记忆块快照（T4）：全局 + 锁定连接两作用域，各自按 updatedAt
/// 新→旧（AiMemoryService 清单语义；注入 fake 时由调用方保证同序——
/// 截断按序取最新）。
class AgentMemorySnapshot {
  const AgentMemorySnapshot({
    this.global = const <AiMemoryItem>[],
    this.connection = const <AiMemoryItem>[],
  });

  /// 全局作用域记忆（新→旧）。
  final List<AiMemoryItem> global;

  /// 锁定连接作用域记忆（新→旧；无锁定连接为空列）。
  final List<AiMemoryItem> connection;

  bool get isEmpty => global.isEmpty && connection.isEmpty;
}

/// 记忆解析函数（T4）：run 启动时按锁定连接取一次快照注入系统提示词。
/// 生产默认 = [AiMemoryService] 单例；测试注入 fake 隔离 prefs。
typedef AgentMemoryResolver =
    Future<AgentMemorySnapshot> Function(String? connectionId);

/// 生产默认记忆解析（initialize 幂等且内部容错——prefs 不可达时降级空态，
/// 不阻断 run 启动）。
Future<AgentMemorySnapshot> _defaultMemoryResolver(String? connectionId) async {
  final AiMemoryService service = AiMemoryService();
  await service.initialize();
  return AgentMemorySnapshot(
    global: service.listGlobal(),
    connection: connectionId == null
        ? const <AiMemoryItem>[]
        : service.listForConnection(connectionId),
  );
}

/// 运行级统计回调集（T08 四方法；生产默认绑 WorkbenchUsageStatsService
/// 单例，测试注入 spy）。
class AgentRunStatsCallbacks {
  const AgentRunStatsCallbacks({
    this.onSessionStart,
    this.onActiveDay,
    this.onRunEnd,
    this.onLimitStop,
  });

  final void Function()? onSessionStart;
  final void Function()? onActiveDay;
  final void Function({required int steps, int? tokens})? onRunEnd;
  final void Function()? onLimitStop;
}

/// 生产默认统计接线（WorkbenchUsageStatsService() factory 返回单例）。
AgentRunStatsCallbacks _defaultStats() => AgentRunStatsCallbacks(
  onSessionStart: WorkbenchUsageStatsService().recordAgentSessionStart,
  onActiveDay: WorkbenchUsageStatsService().recordAgentActiveDay,
  onRunEnd: ({required int steps, int? tokens}) => WorkbenchUsageStatsService()
      .recordAgentRunEnd(steps: steps, tokens: tokens),
  onLimitStop: WorkbenchUsageStatsService().recordLimitStop,
);

/// 默认 maxSteps 解析（QuerySettingsService，D16；读失败回默认值——配置面
/// 异常不阻断运行）。
Future<int> _defaultMaxSteps() async {
  try {
    return await QuerySettingsService().getAgentMaxSteps();
  } catch (_) {
    return QuerySettingsService.defaultAgentMaxSteps;
  }
}

/// 停止原因（用户停止走终局汇报；会话切换走静默拆除——无终局消息，旧会话
/// 消息已落账、终局不应落进新会话，§5.2 边界清单）。
enum _StopCause { userStop, sessionSwitch }

/// 回路运行器（design §4.3 类签名原文；构造注入见 library 注释）。
///
/// 持有 [ledger]（§5.1 会话放行账本——跨 run 保留，会话切换 /
/// lockWorkbenchContext 变更由 T14 调 [resetForSessionSwitch] /
/// `ledger.clearAll()` 失效，D12）。
class AgentLoopRunner extends ChangeNotifier {
  AgentLoopRunner({
    required AgentToolExecutor executor,
    required AiSessionManager sessionManager,
    required AgentRunContextResolver resolveRunContext,
    required AgentChatConfigResolver resolveChatConfig,
    AgentChatFn? chat,
    AgentMaxStepsResolver? resolveMaxSteps,
    AgentRunStatsCallbacks? stats,
    AgentMemoryResolver? memoryResolver,
  }) : _executor = executor,
       _sessionManager = sessionManager,
       _resolveRunContext = resolveRunContext,
       _resolveChatConfig = resolveChatConfig,
       _chat = chat ?? AiService().client.chat,
       _resolveMaxSteps = resolveMaxSteps ?? _defaultMaxSteps,
       _stats = stats ?? _defaultStats(),
       _memoryResolver = memoryResolver ?? _defaultMemoryResolver;

  /// D18：连续失败工具调用上限（任何成功即清零；chat 层错误不计入 → failed）。
  static const int maxConsecutiveFailures = 5;

  static int _runSeq = 0;

  final AgentToolExecutor _executor;
  final AiSessionManager _sessionManager;
  final AgentRunContextResolver _resolveRunContext;
  final AgentChatConfigResolver _resolveChatConfig;
  final AgentChatFn _chat;
  final AgentMaxStepsResolver _resolveMaxSteps;
  final AgentRunStatsCallbacks _stats;

  /// T4：记忆解析（系统提示词记忆块数据源；启动时取一次，run 内不刷新——
  /// 与 D15 上下文快照同节奏）。
  final AgentMemoryResolver _memoryResolver;

  /// 会话放行账本（D12；跨 run 保留，随会话/连接失效——失效触发方在
  /// T14 接线，本类只持有并传递给 executor）。
  final AgentPermissionLedger ledger = AgentPermissionLedger();

  AgentRunStatus _status = AgentRunStatus.idle;
  int _maxSteps = QuerySettingsService.defaultAgentMaxSteps;
  TokenUsage? _tokenUsage;
  bool _usageUnknown = false;
  String? _activeRunId;

  /// A1 期可空注记已随 T28 收口（§6 计划期发现 #7）：`start` 的 uiPort 已转
  /// 必填，运行期内恒非空。
  AgentUiPort? _activeUiPort;

  /// 运行内 LLM 消息列（D19：只进内存，不落会话文件；首条 = 用户消息）。
  List<Map<String, dynamic>> _runLlmMessages = const [];

  int _consecutiveFailures = 0;
  String? _lastFailureTool;
  String? _lastFailureDetail;

  /// 在途门卡等待的 Completer（awaitingUser 期间非空；停止/会话切换时以
  /// rejected 解决，§6.4 / 风险 2）。
  Completer<GateCardResult>? _pendingGate;

  _StopCause? _stopCause;

  /// run 代数：start() / resetForSessionSwitch() 自增；被拆散的旧 run 以
  /// 代数不等**静默退出**（无终局消息、无状态改写——runner 可能仍挂在
  /// chat/execute 的 await 上，靠本判据收敛）。
  int _generation = 0;

  AgentRunStatus get status => _status;

  /// D10 口径步数（与轨迹卡/审计对账，AC2.3）——直接读 executor 计数器，
  /// 同源保证（start 时 resetSteps 对账归零）。
  int get stepsUsed => _executor.stepsUsed;

  /// 步数上限（AC2.1：启动时读 QuerySettingsService，运行中不改）。
  int get maxSteps => _maxSteps;

  /// D11 token 累计；null = 提供商未报（任一轮缺失 → 整 run 降级「—」，
  /// AC3.4——已知部分和无从补全，不显示误导性总数）。
  TokenUsage? get tokenUsage => _usageUnknown ? null : _tokenUsage;

  /// 当前（或最近一次）run 的 ID；从未运行为 null。
  String? get activeRunId => _activeRunId;

  /// 当前 run 持有的界面派发端口（T28 起 `start` 必填注入——A2 界面七工具
  /// 的派发通道）。
  AgentUiPort? get activeUiPort => _activeUiPort;

  /// 工具执行器暴露（T28：shell 的轨迹卡「在舞台打开」经
  /// [AgentToolExecutor.resultRefOf] 优先查 run 内 result_ref 注册表——
  /// 全量行口径）。只读消费，不绕 D3 链执行工具。
  AgentToolExecutor get executor => _executor;

  /// §6.5 不变式：isRunning ⇔ status ∈ {running, awaitingUser, stopping}。
  bool get isRunning =>
      status == AgentRunStatus.running ||
      status == AgentRunStatus.awaitingUser ||
      status == AgentRunStatus.stopping;

  /// 启动一次运行（design §4.3 原文签名；[uiPort] T28 转必填——§6 计划期
  /// 发现 #7 收口：A2 界面/建议工具经此端口派发，[gates] 为 null 时 executor
  /// 对 confirm 档 fail-closed，T10）。
  ///
  /// [userMessage] 可为技能模板（R12）；runner 自己落用户消息（§5.2 流首
  /// 节点——T14 的 agent 发送路径**不要再重复入库**）。历史 seed 经
  /// AiContextBuilder.buildContext（跳过 toolCall/toolResult、保留 chat，
  /// D19）。D17：运行中再 start 静默拒绝（发送按钮此时是停止）。
  Future<void> start({
    required String userMessage,
    required AgentUiPort uiPort,
    GateCallbacks? gates,
  }) async {
    if (isRunning) return; // D17 守卫

    final String runId =
        'run_${DateTime.now().millisecondsSinceEpoch}_${++_runSeq}';

    // run 态复位（对账基准：executor 计步归零，AC2.3；与 _generation++ 同
    // 步块——旧 run 静默退出不会读到新 run 的计步）。Fix-F ④：result_ref
    // 注册表同步清空（与 resetSteps 同挂点）——原惰性清理靠下个 execute
    // 的 runId 切换，两次 run 之间的空窗期同名 refId（res_<stepNo>）会
    // 解析到上一 run 的引用（T09 跨 run 契约）。
    _generation++;
    _activeRunId = runId;
    _activeUiPort = uiPort;
    _executor.resetSteps();
    _executor.resetResultRefs();
    _tokenUsage = null;
    _usageUnknown = false;
    _consecutiveFailures = 0;
    _lastFailureTool = null;
    _lastFailureDetail = null;
    _stopCause = null;
    _pendingGate = null;
    _runLlmMessages = <Map<String, dynamic>>[
      <String, dynamic>{'role': 'user', 'content': userMessage},
    ];

    // maxSteps 启动时读（AC2.1）。
    _maxSteps = await _resolveMaxSteps();

    final AgentChatConfig cfg = _resolveChatConfig();
    final AgentRunContext runCtx = _resolveRunContext(runId); // D15 一次快照

    if (_sessionManager.currentSession == null) {
      _sessionManager.createSession(locale: cfg.locale);
    }

    // seed（D19 裁剪产物）：在落用户消息/锚点**之前**取历史——本轮消息走
    // _runLlmMessages，不进 seed。T4：记忆块同点取一次快照（解析失败降级
    // 空态——记忆是提示词增强面，不阻断 run 启动）。
    final AgentMemorySnapshot memory = await _resolveMemorySnapshot(
      runCtx.connectionId,
    );
    final String systemPrompt = _AgentSystemPrompt.build(
      locale: cfg.locale,
      runCtx: runCtx,
      memory: memory,
    );
    final BuildContextResult seed = AiContextBuilder.buildContext(
      fixedSystemPrompt: systemPrompt,
      allMessages: _sessionManager.currentMessages,
      goalSummary: _sessionManager.currentSession?.goalSummary,
      model: cfg.model,
      locale: cfg.locale,
    );

    // §5.2：用户消息 + 轨迹锚点。
    final _RunnerText text = _RunnerText.forLocale(cfg.locale);
    _sessionManager.addMessage(
      AiMessage(
        id: 'agent_u_$runId',
        isUser: true,
        content: userMessage,
        timestamp: DateTime.now(),
        type: AiMessageType.chat,
        status: AiMessageStatus.sent,
      ),
    );
    _sessionManager.addMessage(
      AiMessage(
        id: 'agent_anchor_$runId',
        isUser: false,
        content: '',
        timestamp: DateTime.now(),
        type: AiMessageType.toolResult,
        toolName: 'agent_run',
        toolResultSummary: text.anchorSummary(_maxSteps),
        toolResultData: <String, dynamic>{
          'agent': <String, dynamic>{
            'kind': 'agent_run',
            'runId': runId,
            'goal': userMessage,
            'contextSnapshot': <String, dynamic>{
              'conn': runCtx.connectionName ?? runCtx.connectionId ?? '',
              'db': runCtx.databaseName ?? '',
              'readOnly': runCtx.readOnly,
              'maxSteps': _maxSteps,
            },
          },
        },
      ),
    );

    // 统计（§6.1：run 启动即记）。
    _stats.onSessionStart?.call();
    _stats.onActiveDay?.call();

    _setStatus(AgentRunStatus.running);
    await _runLoop(
      runId: runId,
      runCtx: runCtx,
      cfg: cfg,
      gates: gates,
      uiPort: uiPort,
      seedHistory: seed.messages,
      systemPrompt: seed.systemPrompt,
      generation: _generation,
    );
  }

  /// AC1.3：不再发起新工具调用/新轮；awaitingUser 的门卡以 rejected 解决
  /// （卡上呈现「已随运行取消」）；在途调用完成（结果保留）。
  void requestStop() {
    if (!isRunning) return;
    _stopCause = _StopCause.userStop;
    final Completer<GateCardResult>? pending = _pendingGate;
    if (status == AgentRunStatus.awaitingUser &&
        pending != null &&
        !pending.isCompleted) {
      pending.complete(GateCardResult.rejected);
    }
    _setStatus(AgentRunStatus.stopping);
  }

  /// 会话切换复位（AC8.5 / 风险 2；T14 在 `_onSessionChange` 路径接线）：
  /// idle + 账本清空 + 在途 Completer 解决为 rejected。被拆散的旧 run 以
  /// 代数不等**静默退出**——不落终局消息（旧会话消息已落账，终局不应落进
  /// 新会话；中断态由 §5.2 中断渲染兜底）；统计在复位时点即记（步数是
  /// 真实发生量，且此刻计步仍属旧 run）。
  void resetForSessionSwitch() {
    if (isRunning) {
      _stats.onRunEnd?.call(
        steps: _executor.stepsUsed,
        tokens: tokenUsage?.totalTokens,
      );
      _stopCause = _StopCause.sessionSwitch;
      final Completer<GateCardResult>? pending = _pendingGate;
      if (pending != null && !pending.isCompleted) {
        pending.complete(GateCardResult.rejected);
      }
    }
    _generation++; // 旧 run 静默退出判据
    _status = AgentRunStatus.idle;
    _activeRunId = null;
    _activeUiPort = null;
    _runLlmMessages = const [];
    _pendingGate = null;
    ledger.clearAll();
    notifyListeners();
  }

  // ── 主循环（§4.3 伪代码逐行）────────────────────────────────────────────

  Future<void> _runLoop({
    required String runId,
    required AgentRunContext runCtx,
    required AgentChatConfig cfg,
    required GateCallbacks? gates,
    required AgentUiPort uiPort,
    required List<Map<String, dynamic>> seedHistory,
    required String systemPrompt,
    required int generation,
  }) async {
    final List<Map<String, dynamic>> tools = AgentToolCatalog.llmToolsFor(
      milestone: AgentToolCatalog.activeMilestone,
    );
    final GateCallbacks? wrappedGates = _wrapGates(
      gates,
      cfg.locale,
      generation,
    );
    // 本 run 的 LLM 消息列（字段引用的所有权局部化：复位/新 run 替换字段后，
    // 被拆散的旧 run 仍可安全追加自己的列——只进内存、随 run 消亡）。
    final List<Map<String, dynamic>> llm = _runLlmMessages;

    while (true) {
      // 停止/复位检查点（§6.8：状态检查点在每步边界 + 派发前/轮前）。
      if (_silentExit(generation)) return;
      if (_stopCause == _StopCause.userStop) {
        await _finalizeUserStop(runId, cfg, generation);
        return;
      }

      final ChatResponse resp;
      try {
        resp = await _chat(
          provider: cfg.provider,
          model: cfg.model,
          apiKey: cfg.apiKey,
          baseUrl: cfg.baseUrl,
          // 用户消息固定在 llm[0]，无需 message 参数重复携带。
          message: '',
          systemPrompt: systemPrompt,
          history: <Map<String, dynamic>>[...seedHistory, ...llm],
          timeout: cfg.timeout,
          tools: tools,
        );
      } catch (e) {
        // §6.4 提供商错误：运行级失败（不走 D18 失败计数，AC15.5）。
        await _finalizeFailed(runId, cfg, generation, e);
        return;
      }

      // 代数/复位检查：会话切换或新 run 已接管——静默退出（统计已在复位
      // 时点记过，不重复）。
      if (_silentExit(generation)) return;

      // token 逐轮累加（D11 / AC3.1 实时；null → 该轮不计 + 整 run 降级）。
      final TokenUsage? usage = resp.usage;
      if (usage == null) {
        _usageUnknown = true;
      } else {
        _tokenUsage = (_tokenUsage ?? const TokenUsage()) + usage;
      }
      notifyListeners();

      if (_silentExit(generation)) return;
      if (_stopCause == _StopCause.userStop) {
        // 响应已到但未派发任何调用：直接收敛，不消费响应内容。
        await _finalizeUserStop(runId, cfg, generation);
        return;
      }

      if (resp.toolCalls.isEmpty) {
        // 终局：模型最终回复 = 终局消息正文（completed）。
        await _finalizeCompleted(runId, cfg, generation, resp.content);
        return;
      }

      // 派发前预算检查（AC2.2）：预算内照常执行完（部分执行语义），剩余
      // tool_calls 不派发、回喂 STEP_LIMIT_REACHED 占位（协议完整）。
      final int budget = _maxSteps - _executor.stepsUsed;
      final bool overLimit = resp.toolCalls.length > budget;

      // assistant tool_calls 消息先进 LLM 消息列（协议：role:'tool' 结果须
      // 跟随其发起的 tool_calls 消息）。
      llm.add(<String, dynamic>{
        'role': 'assistant',
        'content': resp.content ?? '',
        'tool_calls': <Map<String, dynamic>>[
          for (final tc in resp.toolCalls) tc.toJson(),
        ],
      });

      for (int i = 0; i < resp.toolCalls.length; i++) {
        final call = resp.toolCalls[i];
        if (overLimit && i >= budget) {
          // 预算外：占位回喂（不执行、不计步——D10 只计进入执行管线的调用）。
          llm.add(_placeholderToolMessage(call.id));
          continue;
        }
        if (_silentExit(generation)) return; // 每步边界检查（AC1.3）
        if (_stopCause != null) break; // 用户停止：本步已完整，收敛

        final AgentToolCall toolCall = AgentToolCall.fromAiToolCall(call);
        AgentToolOutcome outcome;
        try {
          outcome = await _executor.execute(
            call: toolCall,
            runCtx: runCtx,
            ledger: ledger,
            gates: wrappedGates,
            uiPort: uiPort,
          );
        } catch (e) {
          // Fix-B 中-1：execute 链本身抛出（门 evaluate 崩溃 / 结构守卫
          // StateError 等 unforeseen 路径）——异常不得冒穿 _runLoop（否则
          // 状态卡死 running，isRunning 永不翻 false）。兜底转为同构失败步：
          // 补齐该步审计与步消息（EXECUTION_FAILED / blocked 形态，AC13.1
          // 「每次调用至少一条审计」），走 D18 失败计数收敛（连续达上限 →
          // stoppedByFailures；模型自纠成功 → run 继续）。
          AppLogger.e(
            'AgentLoopRunner',
            'executor.execute threw; rescued as failed step (run continues)',
            e,
          );
          outcome = await _executor.rescueOutcome(
            call: toolCall,
            runCtx: runCtx,
            errorMessage: e.toString(),
          );
        }

        // Fix-B 低-1：execute/rescue 在途期间会话已切换（代数不等）——旧
        // run 步消息不再写进新会话（终局与统计同理由复位方接管，静默退出）。
        if (_silentExit(generation)) return;

        // D2 消息落账：步消息对由 executor 产出、runner 落会话。
        _sessionManager.addMessage(outcome.callMessage);
        _sessionManager.addMessage(outcome.resultMessage);
        llm.add(<String, dynamic>{
          'role': 'tool',
          'tool_call_id': call.id,
          'content': outcome.toLLMJson(),
        });
        notifyListeners(); // stepsUsed 已变（AC3.1 实时对账）

        // T2 方案 B 检查点（FU-10 收口）：CONTEXT_REQUIRED 拒绝 → run 立即
        // 终止（stoppedByContext + 终局引导选库），同批剩余 tool_calls 回喂
        // CONTEXT_REQUIRED 占位保持协议完整——不再进入下一轮让模型经
        // information_schema / 系统库绕行烧满步限。用户停止优先（§6.4）：
        // requestStop 与本检查点同帧时按既有 _stopCause 检查顺序收敛
        // stoppedByUser（循环尾的 userStop 分支接管）。
        if (!outcome.ok &&
            outcome.errorCode == AgentToolErrorCodes.contextRequired) {
          if (_stopCause == _StopCause.userStop) {
            break; // 用户停止语义不被上下文终止抢占
          }
          for (int j = i + 1; j < resp.toolCalls.length; j++) {
            llm.add(_contextPlaceholderToolMessage(resp.toolCalls[j].id));
          }
          await _finalizeStoppedByContext(runId, cfg, runCtx, generation);
          return;
        }

        // D18 失败计数：任何成功即清零。
        if (outcome.ok) {
          _consecutiveFailures = 0;
        } else {
          _consecutiveFailures++;
          _lastFailureTool = call.functionName;
          _lastFailureDetail = outcome.errorMessage ?? outcome.errorCode ?? '';
        }
        if (_consecutiveFailures >= maxConsecutiveFailures) {
          await _finalizeStoppedByFailures(runId, cfg, generation);
          return;
        }
      }

      if (overLimit) {
        await _finalizeStoppedByLimit(runId, cfg, generation);
        return;
      }
      if (_silentExit(generation)) return;
      if (_stopCause == _StopCause.userStop) {
        await _finalizeUserStop(runId, cfg, generation);
        return;
      }
      // 下一轮（循环顶部检查点先行）。
    }
  }

  /// 静默退出判据：run 已被复位/新 run 接管（代数不等）或复位方为会话切换
  /// （无终局消息路径）。终局统计不在此记——复位时点已记（见
  /// [resetForSessionSwitch]）。
  bool _silentExit(int generation) =>
      generation != _generation || _stopCause == _StopCause.sessionSwitch;

  // ── 终局收敛（§6.4 四源 + T2 方案 B 上下文缺失终止：全部落终局消息 +
  //    统计 + 状态收敛）──────────────────────────────────────────────────────

  Future<void> _finalizeCompleted(
    String runId,
    AgentChatConfig cfg,
    int generation,
    String? modelText,
  ) async {
    if (generation != _generation) return;
    final _RunnerText t = _RunnerText.forLocale(cfg.locale);
    final String summary = t.completedSummary(
      _executor.stepsUsed,
      tokenUsage?.totalTokens,
    );
    await _landTerminal(
      runId: runId,
      cfg: cfg,
      status: AgentRunStatus.completed,
      content: (modelText == null || modelText.trim().isEmpty)
          ? summary
          : modelText,
      summaryText: summary,
    );
  }

  Future<void> _finalizeUserStop(
    String runId,
    AgentChatConfig cfg,
    int generation,
  ) async {
    if (generation != _generation) return;
    final _RunnerText t = _RunnerText.forLocale(cfg.locale);
    final String summary = t.stoppedByUserSummary(_executor.stepsUsed);
    await _landTerminal(
      runId: runId,
      cfg: cfg,
      status: AgentRunStatus.stoppedByUser,
      content: summary,
      summaryText: summary,
    );
  }

  Future<void> _finalizeStoppedByLimit(
    String runId,
    AgentChatConfig cfg,
    int generation,
  ) async {
    if (generation != _generation) return;
    _stats.onLimitStop?.call(); // 字段 9（超限停止计数）
    final _RunnerText t = _RunnerText.forLocale(cfg.locale);
    final String summary = t.stoppedByLimitSummary(
      _executor.stepsUsed,
      _maxSteps,
    );
    await _landTerminal(
      runId: runId,
      cfg: cfg,
      status: AgentRunStatus.stoppedByLimit,
      content: summary,
      summaryText: summary,
    );
  }

  /// T2 方案 B 终局（FU-10 收口）：上下文缺失终止。照
  /// [_finalizeStoppedByLimit] 同构——**不新增统计字段**
  /// （workbench_usage_stats_service.dart 零改动）。
  Future<void> _finalizeStoppedByContext(
    String runId,
    AgentChatConfig cfg,
    AgentRunContext runCtx,
    int generation,
  ) async {
    if (generation != _generation) return;
    final _RunnerText t = _RunnerText.forLocale(cfg.locale);
    final String conn = runCtx.connectionName ?? runCtx.connectionId ?? '';
    final bool hasConnection =
        runCtx.connectionId != null && runCtx.connectionId!.isNotEmpty;
    final String summary = t.stoppedByContextSummary(
      connectionLabel: conn,
      hasConnection: hasConnection,
    );
    await _landTerminal(
      runId: runId,
      cfg: cfg,
      status: AgentRunStatus.stoppedByContext,
      content: summary,
      summaryText: summary,
    );
  }

  Future<void> _finalizeStoppedByFailures(
    String runId,
    AgentChatConfig cfg,
    int generation,
  ) async {
    if (generation != _generation) return;
    final _RunnerText t = _RunnerText.forLocale(cfg.locale);
    final String summary = t.stoppedByFailuresSummary(
      _consecutiveFailures,
      _lastFailureTool,
      _lastFailureDetail,
    );
    await _landTerminal(
      runId: runId,
      cfg: cfg,
      status: AgentRunStatus.stoppedByFailures,
      content: summary,
      summaryText: summary,
    );
  }

  Future<void> _finalizeFailed(
    String runId,
    AgentChatConfig cfg,
    int generation,
    Object error,
  ) async {
    if (generation != _generation) return;
    final _RunnerText t = _RunnerText.forLocale(cfg.locale);
    // NF2.2：错误明细过 redactSecrets（不进消息/日志的敏感面）。
    final String detail = redactSecrets(error.toString());
    await _landTerminal(
      runId: runId,
      cfg: cfg,
      status: AgentRunStatus.failed,
      content: t.failedSummary(detail),
      summaryText: t.failedSummary(detail),
      errorMessage: detail,
    );
  }

  /// 落终局消息（§5.2：type chat + toolResultData['agent'] =
  /// `{kind:'agent_run_end', runId, status, steps, tokens?, summaryText}`；
  /// tokens 缺席 = 提供商未报，AC3.4）+ 统计 runEnd + 状态收敛。
  Future<void> _landTerminal({
    required String runId,
    required AgentChatConfig cfg,
    required AgentRunStatus status,
    required String content,
    required String summaryText,
    String? errorMessage,
  }) async {
    final int steps = _executor.stepsUsed;
    final int? tokens = tokenUsage?.totalTokens;
    _sessionManager.addMessage(
      AiMessage(
        id: 'agent_end_$runId',
        isUser: false,
        content: content,
        timestamp: DateTime.now(),
        type: AiMessageType.chat,
        status: status == AgentRunStatus.failed
            ? AiMessageStatus.failed
            : AiMessageStatus.completed,
        errorMessage: errorMessage,
        toolResultSummary: summaryText,
        toolResultData: <String, dynamic>{
          'agent': <String, dynamic>{
            'kind': 'agent_run_end',
            'runId': runId,
            'status': status.name,
            'steps': steps,
            'tokens': ?tokens,
            'summaryText': summaryText,
          },
        },
      ),
    );
    _stats.onRunEnd?.call(steps: steps, tokens: tokens);
    _setStatus(status);
  }

  // ── 门卡宿主（§5.2 门卡消息 + awaitingUser + 停止协同）──────────────────

  /// 包装 shell 注入的 GateCallbacks：落门卡宿主消息（kind
  /// `agent_confirm` / `agent_plan`，决策后回填 outcome）+ awaitingUser
  /// 状态翻转 + 停止/会话切换时以 rejected 解决在途等待（§6.4 / 风险 2）。
  /// shell 回调异常 → rejected（fail-closed，不崩 run——沿 AgentUiPort 的
  /// 「异常转化为失败结论」纪律）。
  GateCallbacks? _wrapGates(
    GateCallbacks? gates,
    String locale,
    int generation,
  ) {
    if (gates == null) return null; // executor 对 confirm 档 fail-closed
    return GateCallbacks(
      onL05Confirm: (ReadImpactAnalysis impact, String sql) => _hostGateCard(
        decide: () => gates.onL05Confirm(impact, sql),
        kind: 'agent_confirm',
        impact: impact,
        sql: sql,
        locale: locale,
        generation: generation,
      ),
      // T28 真接线：A2 起 `submit_action_plan` 可达（milestone 2），本包装
      // 生效（宿主消息 + awaitingUser + 停止协同）；参数类型随
      // AgentPlanApprovalCallback 收口为 AgentActionPlan。
      onPlanApproval: (AgentActionPlan plan) => _hostGateCard(
        decide: () => gates.onPlanApproval(plan),
        kind: 'agent_plan',
        impact: null,
        sql: '',
        locale: locale,
        generation: generation,
      ),
    );
  }

  Future<GateCardResult> _hostGateCard({
    required Future<GateCardResult> Function() decide,
    required String kind,
    required ReadImpactAnalysis? impact,
    required String sql,
    required String locale,
    required int generation,
  }) async {
    final String runId = _activeRunId ?? '';
    // wrapper 在 executor.execute 链内被调，计步已含触发本卡的工具步。
    final int stepNo = _executor.stepsUsed;
    final String cardId = 'agent_gc_${runId}_$stepNo';
    final _RunnerText text = _RunnerText.forLocale(locale);

    // §5.2 门卡宿主消息（决策前 outcome 缺席 = 未决，T12/T13 据此渲染）。
    _sessionManager.addMessage(
      AiMessage(
        id: cardId,
        isUser: false,
        content: '',
        timestamp: DateTime.now(),
        type: AiMessageType.toolResult,
        toolName: kind,
        status: AiMessageStatus.completed,
        toolResultSummary: text.gateCardSummary(kind, sql),
        toolResultData: <String, dynamic>{
          'agent': <String, dynamic>{
            'kind': kind,
            'runId': runId,
            'stepNo': stepNo,
            if (impact != null) 'sql': sql, // agent_plan 的语句面在计划对象内（A2 T22/T23）
            if (impact != null)
              'impact': <String, dynamic>{
                'estimatedRows': impact.estimatedRows,
                'fullScan': impact.fullScan,
                'scannedTables': impact.scannedTables,
                'indexSummary': impact.indexSummary,
                'analysisUnavailable': impact.analysisUnavailable,
              },
          },
        },
      ),
    );

    _setStatus(AgentRunStatus.awaitingUser);
    final Completer<GateCardResult> stopper = _pendingGate =
        Completer<GateCardResult>();
    GateCardResult result;
    try {
      // shell 回调（呈现卡面 + 等用户决策）与停止取消赛跑（§6.4）。
      result = await Future.any<GateCardResult>(<Future<GateCardResult>>[
        decide(),
        stopper.future,
      ]);
    } catch (e) {
      AppLogger.e(
        'AgentLoopRunner',
        'gate callback failed, failing closed to rejected',
        e,
      );
      result = GateCardResult.rejected;
    } finally {
      _pendingGate = null;
      // 决策落定回 running（停止已请求时保持 stopping——步边界随即收敛）；
      // run 已被复位/新 run 接管时**不触碰状态**（复位方已收敛 idle——见
      // [resetForSessionSwitch]，否则旧 run 收尾会覆盖复位结果）。
      if (generation == _generation) {
        _setStatus(
          _stopCause == null ? AgentRunStatus.running : AgentRunStatus.stopping,
        );
      }
    }

    _backfillGateOutcome(cardId, result);
    return result;
  }

  /// 决策回填（updateMessage 不支持 toolResultData，走 copyWith + 整列替换；
  /// 会话已切换时消息列不在——跳过回填，静默）。
  void _backfillGateOutcome(String cardId, GateCardResult result) {
    final List<AiMessage> messages = _sessionManager.currentMessages.toList();
    final int index = messages.indexWhere((AiMessage m) => m.id == cardId);
    if (index == -1) return;
    final Map<String, dynamic>? data = messages[index].toolResultData;
    final Map<String, dynamic>? agent = data?['agent'] as Map<String, dynamic>?;
    if (data == null || agent == null) return;
    messages[index] = messages[index].copyWith(
      toolResultData: <String, dynamic>{
        ...data,
        'agent': <String, dynamic>{...agent, 'outcome': result.name},
      },
    );
    _sessionManager.updateMessages(messages);
  }

  // ── 私有辅助 ────────────────────────────────────────────────────────────

  /// T4：记忆快照解析（容错封装——解析异常降级空快照，run 照常启动）。
  Future<AgentMemorySnapshot> _resolveMemorySnapshot(
    String? connectionId,
  ) async {
    try {
      return await _memoryResolver(connectionId);
    } catch (e) {
      AppLogger.e(
        'AgentLoopRunner',
        'memory snapshot resolution failed (run continues without memory block)',
        e,
      );
      return const AgentMemorySnapshot();
    }
  }

  /// STEP_LIMIT_REACHED 占位回喂（§6.4 超限行：协议完整；不执行不计步）。
  Map<String, dynamic> _placeholderToolMessage(String callId) =>
      <String, dynamic>{
        'role': 'tool',
        'tool_call_id': callId,
        'content':
            '{"ok":false,"error":{"code":"'
            '${AgentToolErrorCodes.stepLimitReached}'
            '","message":"step budget exhausted; run stopped before '
            'dispatching this call"}}',
      };

  /// T2 方案 B：上下文缺失终止时同批剩余 tool_calls 的占位回喂（沿
  /// [_placeholderToolMessage] 模式——协议完整、不执行不计步；错误码与
  /// 终止步同源 CONTEXT_REQUIRED，区别于超限占位的 STEP_LIMIT_REACHED）。
  Map<String, dynamic> _contextPlaceholderToolMessage(String callId) =>
      <String, dynamic>{
        'role': 'tool',
        'tool_call_id': callId,
        'content':
            '{"ok":false,"error":{"code":"'
            '${AgentToolErrorCodes.contextRequired}'
            '","message":"run stopped: no locked database context; this call '
            'was not dispatched"}}',
      };

  void _setStatus(AgentRunStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }
}

/// agent 系统提示词（§4.6 骨架：身份 / 上下文注入 / 行为规则；英文为体、
/// 指令 l10n 化——沿 AiServiceLocalizations 的 locale 参数模式。ARB 集中制
/// 下本文件不触 ARB（T03/T21/T33 专属）。
class _AgentSystemPrompt {
  /// 组装系统提示词（runCtx 快照注入上下文段，§4.6；[memory] 为 T4 记忆
  /// 块快照——null 或空态整段省略）。
  static String build({
    required String locale,
    required AgentRunContext runCtx,
    AgentMemorySnapshot? memory,
  }) {
    final bool zh = locale == 'zh';
    // P3-1：空串同视为未设置（与 gate ②b 谓词 agentToolRequiresDatabaseContext
    // 同语义；局部变量收窄避免裸 !）。
    final String? databaseName = runCtx.databaseName;
    final String? memoryBlock = memory == null || memory.isEmpty
        ? null
        : _memoryBlock(zh, memory);
    return <String>[
      zh
          ? '你是 DbMaster 工作台 agent。工具目录即你的全部能力边界——目录'
                '之外没有任何直接执行通道。'
          : 'You are the DbMaster workbench agent. The tool catalog is your '
                'complete capability boundary — there is no execution channel '
                'outside it.',
      '',
      zh
          ? '当前运行上下文（run 启动时锁定，全程不变）：'
          : 'Current run context '
                '(locked at run start, immutable for the whole run):',
      _contextLine(runCtx),
      // Fix-J：缺 database 时注入缺口引导，指向真实可用路径（顶部上下文
      // 芯片 → 选择器），掐断模型幻觉出的「请先在侧边栏选中一个 database」。
      if (databaseName == null || databaseName.isEmpty)
        _missingDatabaseGuide(zh),
      '',
      if (memoryBlock != null) ...<String>[memoryBlock, ''],
      zh ? _rulesZh() : _rulesEn(),
    ].join('\n');
  }

  /// 上下文注入行（锁定连接/库/方言/readOnly；无连接 = 引导态如实呈现，
  /// AC7.4）。
  static String _contextLine(AgentRunContext runCtx) {
    final String conn =
        runCtx.connectionName ?? runCtx.connectionId ?? 'no connection';
    // P3-1：空串同视为未设置（与 gate ②b 谓词同语义），渲染占位 `-`。
    final String? databaseName = runCtx.databaseName;
    final String db = databaseName == null || databaseName.isEmpty
        ? '-'
        : databaseName;
    final String mode = runCtx.readOnly ? 'read-only' : 'writable';
    return '- locked connection: $conn · database: $db · dialect: '
        '${runCtx.dbType.name} · mode: $mode';
  }

  /// 上下文缺失引导（Fix-J）：database 未设置（上方为 `-`）时的唯一正确
  /// 指引 = 顶部上下文芯片 → 上下文选择器设置数据库；明确禁止指引用户去
  /// 侧边栏树选库（侧栏树选库对芯片/agent 上下文不生效的误导曾实报）。
  /// T2 方案 B 补终止语义：设置前调用数据类工具会立即终止本次运行。
  static String _missingDatabaseGuide(bool zh) => zh
      ? '上下文缺失引导：database 为 - 表示未设置。若任务需要指定库，请指引'
            '用户点顶部上下文芯片、在上下文选择器中设置数据库——不要指引用户'
            '去侧边栏树选库。未设置前调用数据类工具会立即终止本次运行。'
      : 'Missing-context guidance: database "-" means unset. If the task '
            'needs a specific database, direct the user to the context chip '
            'at the top and set the database in the context picker — never '
            'direct the user to the sidebar tree to pick a database. Calling '
            'a data tool before it is set terminates this run immediately.';

  /// T4 记忆块总字符预算（含标题；超限按序截断——清单本身 updatedAt 新→旧，
  /// 截断即保最新）。
  static const int _memoryBlockBudgetChars = 2000;

  /// 记忆块（T4）：全局 + 锁定连接两段，条目 `- [subject] content`；总字符
  /// ≤ [_memoryBlockBudgetChars]（放不下的截断并以省略标记收尾——塞不下的
  /// 一定是最旧条目，marker 放不进去时直接收束）。
  static String _memoryBlock(bool zh, AgentMemorySnapshot memory) {
    final String heading = zh
        ? '已知记忆（你与用户此前沉淀的事实，优先采信；过时条目勿盲从）：'
        : 'Known memories (facts saved earlier by you or the user; trust them, '
              'but do not follow stale entries blindly):';
    final String globalTitle = zh ? '全局记忆：' : 'Global memories:';
    final String connectionTitle = zh
        ? '当前连接记忆：'
        : 'Locked-connection memories:';
    const String moreMarker = '- …';

    final List<String> lines = <String>[heading];
    int used = heading.length;
    bool truncated = false;

    void emit(String title, List<AiMemoryItem> items) {
      if (items.isEmpty || truncated) return;
      if (used + title.length + 1 > _memoryBlockBudgetChars) {
        truncated = true;
        return;
      }
      lines.add(title);
      used += title.length + 1;
      for (final AiMemoryItem item in items) {
        final String? subject = item.subject;
        final String line =
            '- ${subject == null ? '' : '[$subject] '}${item.content}';
        if (used + line.length + 1 > _memoryBlockBudgetChars) {
          truncated = true;
          return;
        }
        lines.add(line);
        used += line.length + 1;
      }
    }

    emit(globalTitle, memory.global);
    emit(connectionTitle, memory.connection);
    if (truncated && used + moreMarker.length + 1 <= _memoryBlockBudgetChars) {
      lines.add(moreMarker);
    }
    return lines.join('\n');
  }

  /// 行为规则（zh）。规则 3 含 A1 兜底引导：目录无 submit_action_plan 时
  /// 写语句进回复文本、交用户走既有确认流（AC9.4 中间态）。
  static String _rulesZh() => const <String>[
    '行为规则：',
    '1. 只读探索优先：按 list_tables → describe_table → get_sample_data '
        '的钻取序了解结构，再决定查询。',
    '2. 读前分析是系统行为：执行前的代价分析（全表扫描/无索引/大结果集）'
        '由系统自动完成，无需自行 EXPLAIN 即可获知；仍可用 explain_plan 自查。',
    '3. 写意图必须走 submit_action_plan（行动计划提交，每步须带回滚方案或'
        '不可逆声明，须人批准才执行，提交本身零执行）。当前目录若没有该工具，'
        '就把完整写语句与风险说明放进回复文本，交由用户手动执行确认流。',
    '4. 不确定时问用户，不要猜。',
    '5. 结果大时先采样（小 LIMIT），不要一次拉全量。',
    '6. 界面工具用于呈现，不要堆砌：同类产物先 pin 再新开。',
    '7. 用户纠正字段含义、业务规则或偏好时，主动用 save_memory 沉淀'
        '（subject 用 table.column 形态，describe_table 会直接展示）；'
        '保存前先 list_memories 查重。',
    '8. 上下文缺失（无锁定连接或无库）时，不要调用任何数据类工具，也不要'
        '尝试用 information_schema 或系统库绕行——此类调用会立即终止本次'
        '运行；直接在回复中引导用户点顶部上下文芯片设置。',
  ].join('\n');

  /// 行为规则（en，英文为体）。
  static String _rulesEn() => const <String>[
    'Behavior rules:',
    '1. Explore read-only first: drill down via list_tables → '
        'describe_table → get_sample_data before deciding what to query.',
    '2. Pre-read analysis is a system behavior: cost analysis (full scan / '
        'missing index / large result set) runs automatically before reads '
        'execute — you do not need to EXPLAIN first, though explain_plan '
        'remains available for self-checks.',
    '3. Write intent MUST go through submit_action_plan (a plan submission '
        'carrying per-step rollback or an irreversible declaration per step; '
        'submission never executes anything — execution starts only after human '
        'approval). If that tool is not in the current catalog, put the '
        'complete write statement and a risk note in your reply text so the '
        'user can run it through the manual confirmation flow.',
    '4. When uncertain, ask the user instead of guessing.',
    '5. Sample first (small LIMIT) when results may be large.',
    '6. Presentation tools are for presenting, not piling up: pin an '
        'existing artifact before opening a new one.',
    '7. When the user corrects a field meaning, a business rule or a '
        'preference, proactively persist it with save_memory (use a '
        'table.column subject so describe_table surfaces it); check '
        'list_memories first to avoid duplicates.',
    '8. When context is missing (no locked connection or no database), do '
        'not call any data tool and do not try to work around it via '
        'information_schema or system catalogs — such calls terminate this '
        'run immediately; instead, direct the user to set it via the context '
        'chip at the top.',
  ].join('\n');
}

/// 汇报文案（终局 summaryText / 锚点 / 门卡兜底文本；zh/en 双语，沿
/// AiServiceLocalizations 先例——技术字符串（status 名/错误码/kind）不走
/// l10n，design §4.8 纪律）。
class _RunnerText {
  const _RunnerText._(this.zh);

  final bool zh;

  static _RunnerText forLocale(String locale) => _RunnerText._(locale == 'zh');

  String anchorSummary(int maxSteps) => zh
      ? 'agent 运行开始（步数上限 $maxSteps）'
      : 'Agent run started (step limit $maxSteps)';

  String completedSummary(int steps, int? tokens) => zh
      ? '已完成 · $steps 步${tokens == null ? '' : ' · $tokens tokens'}'
      : 'Completed · $steps step(s)${tokens == null ? '' : ' · $tokens tokens'}';

  String stoppedByUserSummary(int steps) => zh
      ? '已由用户停止 · 已完成 $steps 步（产出见上方轨迹）'
      : 'Stopped by user · $steps step(s) completed (see trajectory above)';

  String stoppedByLimitSummary(int steps, int maxSteps) => zh
      ? '已达步数上限（$steps/$maxSteps）停止 · 可直接发送新指令接续'
      : 'Step limit reached ($steps/$maxSteps) · send a new message to '
            'continue';

  String stoppedByFailuresSummary(int failures, String? tool, String? detail) {
    final String tail = tool == null
        ? ''
        : zh
        ? '（最后失败：$tool — $detail）'
        : ' (last failure: $tool — $detail)';
    return zh
        ? '连续 $failures 次工具调用失败，运行停止$tail'
        : 'Stopped after $failures consecutive tool failures$tail';
  }

  /// T2 方案 B 终局文案（zh/en 对称，沿 _RunnerText 双语模式——不进 ARB，
  /// 既有终局 summary 同此前例）。无连接时换引导变体（选择连接与数据库）。
  String stoppedByContextSummary({
    required String connectionLabel,
    required bool hasConnection,
  }) {
    if (!hasConnection) {
      return zh
          ? '本次运行已终止：数据类工具需要锁定数据库上下文，但当前上下文'
                '未设置连接。请点顶部上下文芯片选择连接与数据库后，重新发送'
                '你的指令。'
          : 'Run stopped: data tools require a locked database context, but '
                'no connection is set. Pick a connection and a database via '
                'the context chip at the top, then resend your instruction.';
    }
    return zh
        ? '本次运行已终止：数据类工具需要锁定数据库上下文，但当前上下文'
              '未设置数据库（连接：$connectionLabel）。请点顶部上下文芯片选择'
              '数据库后，重新发送你的指令。'
        : 'Run stopped: data tools require a locked database context, but no '
              'database is set (connection: $connectionLabel). Pick a database '
              'via the context chip at the top, then resend your instruction.';
  }

  String failedSummary(String detail) =>
      zh ? 'AI 提供商错误，运行失败：$detail' : 'Run failed (AI provider error): $detail';

  String gateCardSummary(String kind, String sql) {
    final String label = kind == 'agent_plan'
        ? (zh ? '行动计划待批准' : 'Action plan awaiting approval')
        : (zh ? '读取确认待决策' : 'Read confirmation awaiting decision');
    return sql.isEmpty ? label : '$label: $sql';
  }
}
