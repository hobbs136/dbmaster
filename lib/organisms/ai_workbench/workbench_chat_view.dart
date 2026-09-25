//! AI 工作台对话列（design-ai-workbench §2.2 / D7 / §7.4 / §7.8）。
//!
//! 与经典 `AiPanelWidget` 是**同一状态源的两个投影**（D7）：消息流直接消费
//! `AppProvider.aiPanel`（同一本账，AC2.3 同源），渲染层复用公开组件
//! `AiMessageItem`（消息气泡 + 工具卡血脉）与 `AiInputArea`（输入区 / 斜杠
//! 技能 / `@` 表引用）。经典侧 3040 行重组件不整体搬入。
//!
//! T12 已接入：`itemBuilder` 经 `WorkbenchCardHost.tryBuild` 分发工作台卡
//! （workbench payload / AI 回复 code 块拦截），非卡消息复用 `AiMessageItem`
//! 既有路径。T13 已接入：卡动作经宿主（shell）注入 [WorkbenchCardActions]
//! （执行编排 `WorkbenchExecutionActions` / 互跳 `WorkbenchOpenInClassic`），
//! 消息级「执行 / 在新查询打开」同路由（T10 过渡 openQueryTab 接线已替换）。
//!
//! T14（A1 合龙）：发送路径从 orchestrator 切到 `agentRunner.start`（design
//! §2.3——`allowTools` 行随切换消亡，agent 不经 Pro SPI，AC1.5）；`_preflight`
//! agent 路径只留 API key 守卫（AC1.4），上下文缺失不阻断发送（AC7.4 纯对话，
//! 数据类工具运行时 CONTEXT_REQUIRED + 聊天流内「去设置上下文」出口）；
//! 停止 = `requestStop()`（AC1.3）；isRunning 期间发送按钮 = 停止（D17）。
//! 消息流渲染经 T13 `agentTrajectoryGrouping` 分组：agent run → 一张轨迹卡，
//! 非 agent 消息走既有路径零变化；`_mergeToolMessages` 对带 agent 载荷的
//! 消息不合并（design §2.3）。
//!
//! T15（R12 技能入口）：`/` 菜单（`AiInputArea` 自带浮层，复用经典
//! `SlashCommandMenu`）选中技能 → 以技能模板为 userMessage 走统一发送路径
//! `_sendMessage`（AC12.1 模板文本作为用户消息落会话可观察；AC12.2 执行统一
//! 走 agent 工具链，无独立单轮技能执行路径）；经典面板技能路径零改动。
//!
//! T26（R6 建议级出口）：分组接入 `excludeFromRun: (kind) => kind ==
//! 'agent_suggest'`（宿主裁决，§6 计划期发现 #10——建议卡排除出 run 折叠
//! 区间），`agent_suggest` 消息按消息位置平铺为顶级 [AgentSuggestionCard]
//! （ui 规格 §4）。应用动作在 UI 层接线（卡片点击是用户动作）：open_in_classic
//! → `WorkbenchOpenInClassic.open`（M1 出口，新 tab 不覆盖，AC6.2）；
//! focus_sidebar → 侧栏选中入口定位（不切活跃连接）；应用落审计
//! （`recordAgentEvent`，gateDecision na / success true，工具名 = 动作名，
//! AC6.4）；应用/忽略状态回填消息载荷（`_backfillGateOutcome` 同款机制），
//! 三态徽标跨会话重开保持。
//!
//! T27（A2 装配缝）：新增 [uiPort]（随 `runner.start(uiPort:)` 注入，shell
//! 下沉）/ [onOpenResultInStage]（轨迹卡步详情「在舞台打开」）/ [planResolver]
//! + [planBlockBuilder]（计划嵌块，注册表在 shell）四参，全部可选缺省 null
//! ——独立泵本组件的既有测试零回退。

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_message_type.dart';
import '../../models/audit_log_entry.dart' show AgentGateDecision;
import '../../models/database_models.dart';
import '../../plugins/bootstrap.dart';
import '../../providers/app_provider.dart';
import '../../services/ai/agent/agent_loop_runner.dart'
    show AgentLoopRunner;
import '../../services/ai/agent/agent_plan.dart' show AgentActionPlan;
import '../../services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolErrorCodes;
import '../../services/ai/agent/agent_tool_executor.dart'
    show GateCallbacks;
import '../../services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort, GateCardResult;
import '../../services/ai/workbench_context_resolver.dart'
    show effectiveWorkbenchContext;
import '../../services/ai_service.dart';
import '../../services/audit_log_service.dart' show AuditLogService;
import '../../services/database_abstract.dart';
import '../../services/workbench_usage_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/app_logger.dart';
import '../ai_panel/ai_message_item.dart';
import '../ai_panel/ai_panel_widget.dart';
import '../ai_panel/ai_settings_dialog.dart';
import '../ai_panel/ai_welcome_state.dart';
import '../pro/pro_purchase_ui.dart';
import 'agents/agent_suggestion_card.dart';
import 'agents/agent_trajectory_card.dart';
import 'workbench_card_host.dart';
import 'workbench_context_picker.dart';
import 'workbench_open_in_classic.dart';

/// AI 工作台对话列：消息流（复用 `AiMessageItem`）+ 输入区（`AiInputArea`
/// 全参数装配，`enableTableMention: true`）。
///
/// [actions] 由宿主（shell）注入——shell 持有 `_allowedWriteServers` 会话
/// 放行集（design §6.5），执行编排与互跳出口闭包在 shell 侧组装。
/// [agentGates] / [onGateDecision]（T14）：门卡回调与决策桥，由 shell 装配
/// （runner 包装层承担落卡消息与 awaitingUser 翻转，shell 只供「呈现卡面 +
/// 等决策」的桥）。缺省 null = confirm 档 fail-closed（无门 UI 不放行）。
/// [uiPort] / [onOpenResultInStage] / [planResolver] / [planBlockBuilder]
/// （T27）：界面派发端口（传 `runner.start(uiPort:)`，T28 转必填）、轨迹卡
/// 「在舞台打开」与计划嵌块接线，均由 shell 下沉注入（沿 actions 同缝，
/// 不新建 Provider）。
/// 未接线端口（T28）：宿主未注入 [WorkbenchChatView.uiPort] 时的缺省占位
/// ——全部派发以失败 outcome 回喂（AC15.1 自纠通路，消息与 executor 侧
/// fail-closed 同义：装配缺位不静默空转）。生产路径（shell 装配）恒有真端口。
class _DetachedUiPort implements AgentUiPort {
  const _DetachedUiPort();

  static const String _reason =
      'the workbench UI port is not attached; interface tools cannot dispatch '
      'anything (failing closed)';

  @override
  Future<AgentUiOutcome> openResultGrid(AgentResultRef ref, String? title) =>
      Future.value(const AgentUiOutcome.failure(_reason));

  @override
  Future<AgentUiOutcome> showTableStructure(String table) =>
      Future.value(const AgentUiOutcome.failure(_reason));

  @override
  Future<AgentUiOutcome> openSqlEditor(String sql) =>
      Future.value(const AgentUiOutcome.failure(_reason));

  @override
  Future<AgentUiOutcome> renderChart(AgentResultRef ref, String? chartKind) =>
      Future.value(const AgentUiOutcome.failure(_reason));

  @override
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label) =>
      Future.value(const AgentUiOutcome.failure(_reason));

  @override
  Future<AgentUiOutcome> suggestOpenInClassic(String sql) =>
      Future.value(const AgentUiOutcome.failure(_reason));

  @override
  Future<AgentUiOutcome> suggestFocusSidebar({
    String? database,
    String? table,
  }) => Future.value(const AgentUiOutcome.failure(_reason));
}

class WorkbenchChatView extends StatefulWidget {
  const WorkbenchChatView({
    super.key,
    required this.actions,
    this.agentGates,
    this.onGateDecision,
    this.uiPort,
    this.onOpenResultInStage,
    this.planResolver,
    this.planBlockBuilder,
  });

  /// 卡动作（T13 注入：执行 / 互跳 / 错误重试出口）。
  final WorkbenchCardActions actions;

  /// agent 门卡回调（T14 shell 装配：L0.5 确认 + L1 计划 reject 占位）。
  final GateCallbacks? agentGates;

  /// 门卡决策桥（T14）：轨迹卡 `onGateDecision(runId, stepNo, decision)` →
  /// shell 在途 Completer resolve → runner 回填 outcome 续跑。
  final void Function(String runId, int stepNo, GateCardResult decision)?
  onGateDecision;

  /// 界面派发端口（T27 shell 装配）：传 `runner.start(uiPort:)`——agent 运行
  /// 期的界面五工具 / 建议两工具经此派发到舞台与会话。
  final AgentUiPort? uiPort;

  /// 轨迹卡步详情「在舞台打开」（T27）：`runId + stepNo` 寻址，shell 侧解析
  /// 步结果引用后开舞台网格。
  final void Function(String runId, int stepNo)? onOpenResultInStage;

  /// 计划门卡消息 → 活跃计划对象（T27 shell 计划注册表解析；null 返回 =
  /// 防御性不渲染计划嵌块）。
  final AgentActionPlan? Function(AiMessage gateMessage)? planResolver;

  /// 计划嵌块渲染器（T27 与 [planResolver] 成对注入）。
  final AgentPlanGateBlockBuilder? planBlockBuilder;

  @override
  State<WorkbenchChatView> createState() => _WorkbenchChatViewState();
}

class _WorkbenchChatViewState extends State<WorkbenchChatView> {
  /// uiPort 缺省占位（T28：start 必填——未注入时 fail-closed 回喂）。
  static const AgentUiPort _detachedUiPort = _DetachedUiPort();

  // 滚动位随 Offstage 保活跨模式存活（keepScrollOffset，AC1.4）。
  final ScrollController _scrollController = ScrollController(
    keepScrollOffset: true,
  );
  bool _isSending = false;
  int _messageIdCounter = 0;

  bool _shouldAutoScroll = true;
  int _previousMessageCount = 0;

  /// 分页：先渲染最近 50 条，滚到顶部加载更多（沿经典
  /// `AiPanelWidgetState._loadedMessageCount` 同款语义，AC2.2 长会话）。
  int _loadedMessageCount = 50;

  /// agent 运行器监听（T14）：isRunning 翻转驱动 composer 双态 / 骨架可见性
  /// （D17）。会话切换在途复位时 `start()` 可能仍挂在旧 await 上未返回——
  /// 此监听保证发送态不悬挂。
  AgentLoopRunner? _observedAgentRunner;
  bool _agentRunning = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final AgentLoopRunner runner =
        context.read<AppProvider>().aiPanel.agentRunner;
    _observedAgentRunner = runner;
    _agentRunning = runner.isRunning;
    runner.addListener(_onAgentRunnerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AppProvider>().loadAiConfig();
    });
  }

  @override
  void dispose() {
    _observedAgentRunner?.removeListener(_onAgentRunnerChanged);
    _observedAgentRunner = null;
    _scrollController.dispose();
    super.dispose();
  }

  void _onAgentRunnerChanged() {
    final bool running = _observedAgentRunner?.isRunning ?? false;
    if (running == _agentRunning) return;
    _agentRunning = running;
    if (!mounted) return;
    if (!running && _isSending) {
      // 运行收敛但 start() 未返回（在途复位等）——发送态先行复位。
      setState(() {
        _isSending = false;
      });
    } else {
      setState(() {});
    }
  }

  String _generateMessageId() {
    return 'wb_${DateTime.now().millisecondsSinceEpoch}_${_messageIdCounter++}';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 滚动 / 分页（镜像经典同款语义）
  // ──────────────────────────────────────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.userScrollDirection != ScrollDirection.idle) {
      _shouldAutoScroll = false;
    }
    if (!_shouldAutoScroll &&
        position.pixels >= position.maxScrollExtent - 50) {
      _shouldAutoScroll = true;
    }
    if (position.pixels <= 100 &&
        _loadedMessageCount < context.read<AppProvider>().aiMessages.length) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    final totalCount = context.read<AppProvider>().aiMessages.length;
    setState(() {
      _loadedMessageCount = (_loadedMessageCount + 50).clamp(0, totalCount);
    });
  }

  void _scrollToBottomIfNeeded() {
    if (!_shouldAutoScroll || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll < 200) {
      _scrollController.animateTo(
        maxScroll,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 发送流（T14：agent 路径——design §2.3 发送切换；经典守卫链本体保留，
  // agent 调用点放宽为 key-only；成功路径用户消息由 runner 自落）
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _sendMessage(String text) async {
    if (text.isEmpty) return;
    final provider = context.read<AppProvider>();
    final AgentLoopRunner runner = provider.aiPanel.agentRunner;
    // D17（AC1.7）：运行中发送按钮 = 停止，此处为不可达防御——不产生并行
    // 第二运行（runner.start 内另有同款守卫）。
    if (runner.isRunning) return;

    setState(() {
      _isSending = true;
      _shouldAutoScroll = true;
    });

    // 统计（§6.4）：工作台内新建会话（首条消息触发 ensureSession 建会话）。
    final hadSession =
        provider.aiPanel.aiConversationService.currentSession != null;
    provider.aiPanel.ensureSession();
    if (!hadSession) {
      WorkbenchUsageStatsService.instance.recordSession();
    }

    // 默认标题会话用首条消息前 30 字符命名（经典同款）。
    final currentSession =
        provider.aiPanel.aiConversationService.currentSession;
    if (currentSession != null &&
        (currentSession.title.startsWith('New Chat') ||
            currentSession.title.startsWith('新对话'))) {
      final newTitle = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      provider.aiPanel.aiConversationService.updateSessionTitle(
        currentSession.id,
        newTitle,
      );
    }

    // agent 路径守卫（AC1.4/AC7.4 放宽）：只保留 API key 守卫——上下文缺失
    // 不阻断发送，数据类工具运行时 CONTEXT_REQUIRED + 出口引导。
    final String? preflightError = _preflight(
      provider,
      requireConnection: false,
    ).error;
    if (preflightError != null) {
      _landSendBlocked(provider, text, preflightError);
      return;
    }

    // 配额检查与经典同一入口（AC1.5：不新增也不放宽付费门控语义）。
    final canUseAi = await provider.canUseAi();
    if (!canUseAi) {
      if (mounted) {
        context.read<ProPurchaseUi>().showUpgradeDialog(context);
      }
      _landSendBlocked(provider, text, null);
      return;
    }

    try {
      // 用户消息 + 轨迹锚点由 runner 落账（T14：发送方不再预入，防重复）。
      // uiPort 随 start 注入（T27 下沉；T28 起必填——§6 计划期发现 #7 收口）。
      await runner.start(
        userMessage: text,
        uiPort: widget.uiPort ?? _detachedUiPort,
        gates: widget.agentGates,
      );
      await provider.recordAiUsage();
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      // AC9.3：请求失败 → 消息流错误态（status=failed 可辨识），
      // onRegenerate 即重试出口（AiMessageItem 既有资产）。
      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: '${l10n.generationFailed}: $e',
          timestamp: DateTime.now(),
          status: AiMessageStatus.failed,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  /// 发送被阻断（守卫 / 配额）时的 M1 语义落流：用户消息先行（guard 失败时
  /// 错误消息有前置用户消息，Regenerate 才能定位重发，AC9.3 不静默）。
  /// 成功路径用户消息由 runner 落（`agent_u_<runId>`），此处只在失败路径补，
  /// 避免成功路径重复入库。[error] 为 null 时只落用户消息（配额路径走弹窗）。
  void _landSendBlocked(AppProvider provider, String text, String? error) {
    provider.addAiMessage(
      AiMessage(
        id: 'u_${DateTime.now().millisecondsSinceEpoch}',
        isUser: true,
        content: text,
        timestamp: DateTime.now(),
        type: AiMessageType.chat,
        status: AiMessageStatus.sent,
      ),
    );
    if (error != null) {
      provider.addAiMessage(
        AiMessage(
          id: _generateMessageId(),
          isUser: false,
          content: error,
          timestamp: DateTime.now(),
          status: AiMessageStatus.failed,
        ),
      );
    }
    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }

  /// 发送前置守卫（经典守卫链本体保留；agent 调用点经 [requireConnection]
  /// 参数化放宽——经典语义不变，design §2.3）。返回 `error == null` 即通过；
  /// 否则 error 为消息流错误文案（AC9.3 错误不静默）。adapter 仅经典
  /// orchestrator 路径消费，agent 路径不取连接（D15 运行时快照解析）。
  ({String? error, DatabaseAdapter? adapter}) _preflight(
    AppProvider provider, {
    bool requireConnection = true,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final selectedProvider = provider.selectedAiProvider;
    final apiKey = provider.getAiApiKey(selectedProvider) ?? '';

    if (apiKey.isEmpty) {
      return (error: l10n.configureApiKeyFirst(selectedProvider), adapter: null);
    }

    // agent 路径（AC7.4）：无连接 / 无库不阻断发送——纯对话可用，数据类
    // 工具运行时返回 CONTEXT_REQUIRED 引导 + 聊天流内「去设置上下文」出口。
    if (!requireConnection) {
      return (error: null, adapter: null);
    }

    final selectedId = provider.aiPanel.selectedConnectionId;
    final currentServer = selectedId != null
        ? provider.connection.savedConnections.cast<DbServer?>().firstWhere(
            (s) => s!.id == selectedId,
            orElse: () => null,
          )
        : null;
    if (currentServer == null) {
      return (error: l10n.aiPanelSelectConnectionFirst, adapter: null);
    }

    final adapter = provider.connection.dbService.getAdapter(currentServer.id);
    if (adapter == null || !adapter.isConnected) {
      return (
        error: l10n.aiPanelConnectionNotAvailable(currentServer.name),
        adapter: null,
      );
    }

    if (provider.aiPanel.selectedDatabaseName == null) {
      return (error: l10n.aiPanelSelectDatabaseRequired, adapter: null);
    }
    return (error: null, adapter: adapter);
  }

  /// 停止（T14 / AC1.3）：不再发起新工具调用；awaitingUser 的门卡 Completer
  /// 由 runner 以 rejected 解决；终局汇报消息由 runner 落账。
  void _stopAI() {
    context.read<AppProvider>().aiPanel.agentRunner.requestStop();
  }

  void _regenerateMessage(String messageId, List<AiMessage> allMessages) {
    final currentIndex = allMessages.indexWhere((m) => m.id == messageId);
    if (currentIndex <= 0) return;

    int userMessageIndex = -1;
    for (int i = currentIndex - 1; i >= 0; i--) {
      if (allMessages[i].isUser) {
        userMessageIndex = i;
        break;
      }
    }
    if (userMessageIndex < 0) return;

    final userMessage = allMessages[userMessageIndex];
    final provider = context.read<AppProvider>();
    // 截断到该用户消息**之前**（含消息本身移除）——agent 路径的用户消息由
    // runner 落账，重发即由 start 重新入库（可见结果与经典等价）。
    final newMessages = allMessages.sublist(0, userMessageIndex);
    provider.aiPanel.sessionManager.updateMessages(newMessages);

    _sendMessage(userMessage.content);
  }

  void _branchCurrentConversation() {
    final provider = context.read<AppProvider>();
    final messages = provider.aiMessages;
    if (messages.isEmpty) return;

    final lastMessage = messages.last;
    provider.aiPanel.aiConversationService.branchFromMessage(
      lastMessage.id,
      lastMessage.content,
      locale: Localizations.localeOf(context).languageCode,
    );
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.aiPanelBranchConversationCreated),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 输入区外部控制（AiInputArea 无公开控制 API；经公开 EditableTextState，
  // 不改 ai_panel_widget.dart —— T10 约束）
  // ──────────────────────────────────────────────────────────────────────────

  /// 在本组件子树中查找输入区的 [EditableTextState]（BuildContext 只有
  /// 向上查找 API，向下需自行遍历元素树；本子树内唯一 EditableText 即
  /// AiInputArea 的输入框）。
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

  /// 把文本写入输入框并把光标移到末尾（欢迎态示例问题 / 消息引用续写）。
  void _setInputText(String text) {
    final editable = _findEditableState(context as Element);
    if (editable == null) return;
    editable.widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _requestInputFocus() {
    _findEditableState(context as Element)?.requestKeyboard();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 斜杠技能（T15 / R12：`/` 菜单由 AiInputArea 自带；选中技能 = 以模板启动
  // agent run，不走独立单轮技能执行路径）
  // ──────────────────────────────────────────────────────────────────────────

  void _executeSlashCommandAction(String action) {
    switch (action) {
      case 'branch_conversation':
        _branchCurrentConversation();
        break;
      case 'optimize_sql':
        _sendSkillTemplate('query-optimizer-plugin');
        break;
      case 'explain_query':
        _sendSkillTemplate('sql-explain-plugin');
        break;
      case 'analyze_table':
        _sendSkillTemplate('index-suggest-plugin');
        break;
      // show_history / show_bookmarks / generate_crud：经典侧为编辑器/抽屉型
      // 交互（AiPanelWidgetState 私有对话框），工作台等价物不在 T10 范围
      // （与经典 generate_crud 空实现同待遇），留待后续任务补全。
      default:
        break;
    }
  }

  /// 选中技能 → 以技能模板为 userMessage 走统一发送路径（T15 / R12）：
  /// AC12.1 模板文本作为用户消息落会话可观察；AC12.2 执行统一走 agent 工具链
  /// ——key 守卫 / 配额 / 统计 / D17 全链继承 `_sendMessage`，无独立单轮
  /// 技能执行路径。技能注册表只读消费，零新增技能（`ai_skill_plugin.dart`
  /// 契约不动）。
  void _sendSkillTemplate(String skillId) {
    final l10n = AppLocalizations.of(context)!;
    for (final skill in defaultPluginRegistry.aiSkills) {
      if (skill.descriptor.id == skillId) {
        final template = skill.promptTemplate?.call(l10n);
        if (template != null && template.isNotEmpty) {
          unawaited(_sendMessage(template));
        }
        return;
      }
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // `@` 表引用候选（T07 装配面；宿主闭包经 AppProvider 查表清单）
  // ──────────────────────────────────────────────────────────────────────────

  /// [connectionId] / [databaseName] 由输入区从
  /// `aiPanel.selectedConnectionId/selectedDatabaseName` 取参传入（未设置
  /// 传空串）。无连接返回空列表（getTables 自身对未知连接也返回 []）。
  Future<List<String>> _queryTableMention(
    String connectionId,
    String databaseName,
    String prefix,
  ) async {
    if (connectionId.isEmpty) return const [];
    try {
      final tables = await context.read<AppProvider>().dbService.getTables(
        connectionId: connectionId,
      );
      if (prefix.isEmpty) return tables;
      final lower = prefix.toLowerCase();
      return tables
          .where((t) => t.toLowerCase().startsWith(lower))
          .toList();
    } catch (e) {
      AppLogger.w('WorkbenchChatView', 'table mention query failed: $e');
      return const [];
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // AI 设置对话框（providers 列表构造镜像经典 _providers，对话框为公开组件）
  // ──────────────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _buildProviderOptions(AppProvider appProvider) {
    final official = AiApiProviders.all.values
        .map(
          (p) => <String, dynamic>{
            'name': p.name,
            'icon': p.icon,
            'color': Color(p.color),
            'models':
                appProvider.getFetchedModelsForProvider(p.name) ?? p.models,
          },
        )
        .toList();
    final customModels = ['custom-model'];
    if (appProvider.selectedAiProvider == AiApiProviders.customModelKey &&
        appProvider.selectedAiModel != 'custom-model' &&
        appProvider.selectedAiModel.isNotEmpty) {
      customModels.add(appProvider.selectedAiModel);
    }
    official.add(<String, dynamic>{
      'name': AiApiProviders.customModelKey,
      'icon': LucideIcons.settings,
      'color': context.themeColors.accentPurple,
      'models': customModels,
      'isCustom': true,
    });
    return official;
  }

  void _showApiSettings() {
    final provider = context.read<AppProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AiSettingsDialog(
        providers: _buildProviderOptions(provider),
        selectedProvider: provider.selectedAiProvider,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 互跳 / 执行出口（T13：经宿主注入的 [WorkbenchCardActions]——执行走
  // WorkbenchExecutionActions 编排（写确认 + 双异常路由），互跳走
  // WorkbenchOpenInClassic（新 tab + 退出工作台，AC7.1/7.3）。T10 的
  // 过渡 openQueryTab 接线已被替换；消息级回调在 itemBuilder 内联路由。
  // ──────────────────────────────────────────────────────────────────────────

  // ──────────────────────────────────────────────────────────────────────────
  // 工具消息合并（镜像 AiPanelWidgetState._mergeToolMessages——私有成员不可
  // 引用，T10 禁改该文件故暂携等价副本；算法逐行对齐经典实现）。
  // T14：带 agent 载荷的消息不经该合并（design §2.3——渲染层由轨迹卡分组
  // 先行拦截，非 agent 的经典式 toolCall/toolResult 照旧合并）。
  // ──────────────────────────────────────────────────────────────────────────

  /// agent 步消息对的 call 半条识别：executor 落账的 call 消息无 agent 载荷，
  /// id 形如 `agent_tc_<runId>_<stepNo>`；或其紧邻下一条即带载荷的 agent 步
  /// 消息（call/result 成对连续落账——两次 addMessage 各自 notify，中间存在
  /// 重建窗口，id 前缀是窗口期的兜底判据）。
  bool _isAgentToolCall(AiMessage message, List<AiMessage> messages, int index) {
    if (message.type != AiMessageType.toolCall) return false;
    if (message.id.startsWith('agent_tc_')) return true;
    final int next = index + 1;
    return next < messages.length && agentPayloadOf(messages[next]) != null;
  }

  List<AiMessage> _mergeToolMessages(List<AiMessage> messages) {
    final result = <AiMessage>[];

    int i = 0;
    while (i < messages.length) {
      final message = messages[i];

      // agent 载荷消息（锚点 / 步结果 / 门卡 / 终局）：原样平铺，交分组函数。
      if (agentPayloadOf(message) != null) {
        result.add(message);
        i++;
        continue;
      }

      // agent 步消息对的 call 半条：原样平铺，由分组函数的 bufferedCall 认领。
      if (_isAgentToolCall(message, messages, i)) {
        result.add(message);
        i++;
        continue;
      }

      if (message.type == AiMessageType.toolCall) {
        int segmentEnd = i + 1;
        while (segmentEnd < messages.length &&
            !messages[segmentEnd].isUser &&
            agentPayloadOf(messages[segmentEnd]) == null) {
          segmentEnd++;
        }

        final segmentMessages = messages.sublist(i, segmentEnd);

        final tools = <Map<String, dynamic>>[];
        final toolCallIndices = <int>{};
        final consumedResultIndices = <int>{};

        for (int j = 0; j < segmentMessages.length; j++) {
          if (segmentMessages[j].type == AiMessageType.toolCall) {
            AiMessage? toolResult;
            for (int k = j + 1; k < segmentMessages.length; k++) {
              if (segmentMessages[k].type == AiMessageType.toolResult &&
                  segmentMessages[k].toolName == segmentMessages[j].toolName &&
                  !consumedResultIndices.contains(k)) {
                toolResult = segmentMessages[k];
                consumedResultIndices.add(k);
                break;
              }
            }

            tools.add({
              'toolName': segmentMessages[j].toolName,
              'toolArguments': segmentMessages[j].toolArguments,
              'result': toolResult?.content ?? '',
              'status':
                  toolResult?.status.toString() ??
                  segmentMessages[j].status.toString(),
            });
            toolCallIndices.add(j);
          }
        }

        if (tools.isNotEmpty) {
          final firstToolIndex = toolCallIndices.reduce(
            (a, b) => a < b ? a : b,
          );

          for (int j = 0; j < firstToolIndex; j++) {
            if (!toolCallIndices.contains(j) &&
                !consumedResultIndices.contains(j)) {
              result.add(segmentMessages[j]);
            }
          }

          if (tools.length == 1) {
            result.add(
              AiMessage(
                id: segmentMessages[firstToolIndex].id,
                isUser: false,
                content: tools.first['result'] as String,
                timestamp: segmentMessages[firstToolIndex].timestamp,
                type: AiMessageType.toolResult,
                toolName: tools.first['toolName'] as String?,
                toolArguments:
                    tools.first['toolArguments'] as Map<String, dynamic>?,
                status: AiMessageStatus.completed,
              ),
            );
          } else {
            result.add(
              AiMessage(
                // 复用首个 toolCall 的真 id（Regenerate 的 indexWhere 命中）。
                id: segmentMessages[firstToolIndex].id,
                isUser: false,
                content: '',
                timestamp: segmentMessages[firstToolIndex].timestamp,
                type: AiMessageType.toolResult,
                toolName: null,
                toolArguments: null,
                toolResultData: {
                  'isToolGroup': true,
                  'toolCount': tools.length,
                  'tools': tools,
                },
                status: AiMessageStatus.completed,
              ),
            );
          }

          for (int j = firstToolIndex + 1; j < segmentMessages.length; j++) {
            if (!toolCallIndices.contains(j) &&
                !consumedResultIndices.contains(j)) {
              result.add(segmentMessages[j]);
            }
          }
        }

        i = segmentEnd;
      } else {
        result.add(message);
        i++;
      }
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 构建
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _buildMessageList()),
        _buildComposer(),
      ],
    );
  }

  Widget _buildMessageList() {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final messages = provider.aiMessages;

        // AC9.1：空会话 → 欢迎态（复用既有资产，含引导示例）。
        if (messages.isEmpty) {
          final selectedConnId = provider.aiPanel.selectedConnectionId;
          final currentServer = selectedConnId != null
              ? provider.connection.savedConnections
                    .cast<DbServer?>()
                    .firstWhere(
                      (s) => s!.id == selectedConnId,
                      orElse: () => null,
                    )
              : null;

          return AiWelcomeState(
            connectionName: currentServer?.name,
            databaseName: provider.aiPanel.selectedDatabaseName,
            onQuestionTap: (question) {
              _setInputText(question);
              _requestInputFocus();
            },
          );
        }

        final displayCount = messages.length > _loadedMessageCount
            ? _loadedMessageCount
            : messages.length;
        final displayMessages = messages.length > _loadedMessageCount
            ? messages.sublist(messages.length - displayCount)
            : messages;

        if (messages.length != _previousMessageCount) {
          _previousMessageCount = messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottomIfNeeded();
          });
        }

        final AgentLoopRunner runner = provider.aiPanel.agentRunner;
        // T14 消费 T13 分组：先经典合并（agent 消息守卫在内），再按 runId
        // 折叠——agent run → 一张轨迹卡；非 agent 消息既有路径零变化。
        // T26：`agent_suggest` 排除出折叠区间（宿主裁决，§6 计划期发现
        // #10），按消息位置平铺为顶级建议卡。
        final segments = agentTrajectoryGrouping(
          _mergeToolMessages(displayMessages),
          excludeFromRun: (String kind) => kind == 'agent_suggest',
        );
        // D17/AC9.2：agent run 进行中由轨迹卡呈现进度（锚点即落，无白屏），
        // 不叠加载骨架；发起与 running 翻转之间的空窗仍以骨架占位。
        final bool showSkeleton = _isSending && !runner.isRunning;

        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: false,
          thickness: 6.0,
          radius: const Radius.circular(AppDesignSystem.radiusSm),
          child: ListView.builder(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              decelerationRate: ScrollDecelerationRate.fast,
            ),
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            itemCount: segments.length + (showSkeleton ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == segments.length) {
                return const WorkbenchChatLoading();
              }
              final segment = segments[index];
              final AgentTrajectoryRunGroup? runGroup = segment.run;
              if (runGroup != null) {
                return _buildAgentRunSegment(runGroup, runner);
              }
              final AiMessage? message = segment.message;
              if (message == null) {
                return const SizedBox.shrink(); // 结构不可达防御
              }
              // T26 建议卡（ui 规格 §4）：agent_suggest 消息平铺为顶级建议
              // 卡（建议级 ≠ 已执行，卡渲染零副作用——AC6.1/AC6.3）。
              if (agentKindOf(message) == 'agent_suggest') {
                return Padding(
                  key: ValueKey(message.id),
                  padding: const EdgeInsets.only(
                    bottom: AppDesignSystem.space3,
                  ),
                  child: _buildSuggestionCard(message),
                );
              }
              // T12 卡分发（design §4.4）：workbench payload / AI 回复 code
              // 块 → 工作台卡；其余消息走既有 AiMessageItem 路径。
              final card = WorkbenchCardHost.tryBuild(
                context: context,
                message: message,
                actions: widget.actions,
              );
              if (card != null) {
                // 卡间距 12 复用 space3（design §8【二】）。
                return Padding(
                  key: ValueKey(message.id),
                  padding: const EdgeInsets.only(
                    bottom: AppDesignSystem.space3,
                  ),
                  child: card,
                );
              }
              return AiMessageItem(
                key: ValueKey(message.id),
                message: message,
                // T13：消息级「执行 / 在新查询打开」与卡动作同路由（执行编
                // 排复核上下文与读写判定；互跳 = 新 tab + 退出工作台，
                // AC7.1 出口语义，不覆盖既有 tab）。
                onExecuteSql: (code, isDangerous) =>
                    widget.actions.onExecuteSql?.call(code),
                onOpenInNewQuery: (code) =>
                    widget.actions.onOpenSqlInClassic?.call(code),
                onToggleBookmark: (messageId) {
                  provider.toggleBookmark(messageId);
                },
                onBranchFromMessage: (messageId, content) {
                  _setInputText('> $content\n');
                  _requestInputFocus();
                },
                onRegenerate: message.isUser
                    ? null
                    : () => _regenerateMessage(message.id, messages),
              );
            },
          ),
        );
      },
    );
  }

  /// agent run 分段渲染（T13 分组消费）：一张轨迹卡（运行中注入 runner 实时
  /// 态，AC3.1；历史/中断态静态渲染）+ CONTEXT_REQUIRED 出口（AC7.4，沿 M1
  /// 错误卡出口语汇挂在该 run 的错误消息下方）。
  Widget _buildAgentRunSegment(
    AgentTrajectoryRunGroup group,
    AgentLoopRunner runner,
  ) {
    final bool live = group.runId == runner.activeRunId && runner.isRunning;
    return Padding(
      key: ValueKey('agent_run_${group.runId}'),
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentTrajectoryCard(
            runMessages: group.messages,
            runner: live ? runner : null,
            gateBlockBuilder: buildDefaultAgentGateBlock,
            planResolver: widget.planResolver,
            planBlockBuilder: widget.planBlockBuilder,
            onGateDecision: widget.onGateDecision,
            onOpenResultInStage: widget.onOpenResultInStage,
          ),
          if (_runHasContextRequired(group)) _buildContextRequiredExit(context),
        ],
      ),
    );
  }

  /// 该 run 是否含 CONTEXT_REQUIRED 工具错误（数据类工具在无上下文快照上的
  /// 运行时出口，AC7.4）。
  bool _runHasContextRequired(AgentTrajectoryRunGroup group) {
    for (final AiMessage m in group.messages) {
      final Object? error = agentPayloadOf(m)?['error'];
      if (error is Map<String, dynamic> &&
          error['code'] == AgentToolErrorCodes.contextRequired) {
        return true;
      }
    }
    return false;
  }

  /// 「去设置上下文」出口（AC7.4；呈现沿 M1 错误卡出口语汇：error 图标 +
  /// 引导文案 + 动作入口，动作 = 打开既有 WorkbenchContextPicker）。
  Widget _buildContextRequiredExit(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Padding(
      key: const ValueKey('workbench_agent_context_required_exit'),
      padding: const EdgeInsets.only(
        top: AppDesignSystem.space1,
        bottom: AppDesignSystem.space1,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 12, color: colors.error),
          const SizedBox(width: AppDesignSystem.space1_5),
          Expanded(
            child: Text(
              l10n.agentContextRequired,
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          InkWell(
            key: const ValueKey('workbench_agent_context_required_button'),
            onTap: () => WorkbenchContextPicker.show(context),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: AppDesignSystem.space0_5,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.crosshair, size: 12, color: colors.accentBlue),
                  const SizedBox(width: AppDesignSystem.space1),
                  Text(
                    l10n.workbenchContextPickerTitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.accentBlue,
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

  // ──────────────────────────────────────────────────────────────────────────
  // 跨经典建议卡（T26 / ui 规格 §4 / R6）：渲染分发 + 应用/忽略接线
  // ──────────────────────────────────────────────────────────────────────────

  /// 消息 → 建议卡（三态自消息载荷解析：`applied` / `dismissed`，T28 落账
  /// 初值 `applied: false`）。回调只发信号到本 State 的接线方法。
  Widget _buildSuggestionCard(AiMessage message) {
    final Map<String, dynamic> payload =
        agentPayloadOf(message) ?? const <String, dynamic>{};
    final Object? rawAction = payload['action'];
    final Object? rawInner = payload['payload'];
    return AgentSuggestionCard(
      action: rawAction is String ? rawAction : '',
      payload: rawInner is Map<String, dynamic>
          ? rawInner
          : const <String, dynamic>{},
      applied: payload['applied'] == true,
      dismissed: payload['dismissed'] == true,
      onApply: () => _applySuggestion(message),
      onDismiss: () => _backfillSuggestionState(message.id, dismissed: true),
    );
  }

  /// 应用（点击 = 执行点；AC6.2/AC6.4）：动作执行 → 审计 → 状态回填。
  /// 忽略（AC6.3）零副作用——只回填状态，不审计不导航。
  void _applySuggestion(AiMessage message) {
    final Map<String, dynamic> payload =
        agentPayloadOf(message) ?? const <String, dynamic>{};
    final Object? rawAction = payload['action'];
    final String action = rawAction is String ? rawAction : '';
    final Object? rawInner = payload['payload'];
    final Map<String, dynamic> target = rawInner is Map<String, dynamic>
        ? rawInner
        : const <String, dynamic>{};
    final AppProvider provider = context.read<AppProvider>();

    // 动作执行：open_in_classic 复用 M1 出口（新 tab 不覆盖既有 tab，AC6.2）；
    // focus_sidebar 走侧栏选中入口定位（不切活跃连接，无库会话变化）。
    switch (action) {
      case 'open_in_classic':
        final Object? sql = target['sql'];
        if (sql is String && sql.isNotEmpty) {
          unawaited(WorkbenchOpenInClassic.open(context, sql));
        }
      case 'focus_sidebar':
        _focusSidebarTarget(provider, target);
      default:
        break;
    }

    // 审计（AC6.4）：调用点在 UI 层（卡片点击是用户动作，T26 任务书授权，
    // 沿 M1 出口先例）；gateDecision na / success true / 工具名 = 动作名；
    // sql 不入档（建议级为 UI 工具，§4.7「数据/计划类才有」）。
    final ctx = effectiveWorkbenchContext(
      provider.aiPanel.aiConversationService.currentSession,
      provider,
    );
    final Object? rawRunId = payload['runId'];
    final Object? rawStepNo = payload['stepNo'];
    unawaited(
      AuditLogService().recordAgentEvent(
        connectionId: ctx.connectionId ?? '',
        connectionName: ctx.connectionName,
        databaseName: ctx.databaseName,
        runId: rawRunId is String ? rawRunId : '',
        step: rawStepNo is num ? rawStepNo.toInt() : 0,
        tool: action,
        gateLevel: AgentGateLevel.suggest,
        gateDecision: AgentGateDecision.na,
        success: true,
      ),
    );

    _backfillSuggestionState(message.id, applied: true);
  }

  /// focus_sidebar 定位：侧栏选中入口（`SidebarProvider.selectConnection /
  /// selectDatabase`，`SidebarTree._selectDatabase` 同款序列）+ 表高亮
  /// （`AppProvider.setSelectedTable`）。只做展示层定位——不切活跃连接、
  /// 不触发 useDatabase（建议级一次点击 = 一个定位动作）。
  void _focusSidebarTarget(AppProvider provider, Map<String, dynamic> target) {
    final Object? rawDatabase = target['database'];
    final Object? rawTable = target['table'];
    final String? database =
        rawDatabase is String && rawDatabase.isNotEmpty ? rawDatabase : null;
    final String? table =
        rawTable is String && rawTable.isNotEmpty ? rawTable : null;
    if (database == null && table == null) return;
    final ctx = effectiveWorkbenchContext(
      provider.aiPanel.aiConversationService.currentSession,
      provider,
    );
    final String? connectionId = ctx.connectionId;
    if (connectionId != null) {
      provider.sidebar.selectConnection(connectionId);
    }
    if (database != null) {
      provider.sidebar.selectDatabase(database);
    }
    if (table != null) {
      provider.setSelectedTable(table);
    }
  }

  /// 建议状态回填（copyWith + 整列替换——`updateMessage` 不支持
  /// toolResultData，runner `_backfillGateOutcome` 同款机制）：applied /
  /// dismissed 落回消息载荷，卡随 Consumer 重建翻三态，会话切换/重开保持。
  void _backfillSuggestionState(
    String messageId, {
    bool applied = false,
    bool dismissed = false,
  }) {
    final AppProvider provider = context.read<AppProvider>();
    final List<AiMessage> messages = provider.aiMessages.toList();
    final int index = messages.indexWhere((AiMessage m) => m.id == messageId);
    if (index == -1) return;
    final Map<String, dynamic>? data = messages[index].toolResultData;
    final Map<String, dynamic>? agent = data?['agent'] as Map<String, dynamic>?;
    if (data == null || agent == null) return;
    messages[index] = messages[index].copyWith(
      toolResultData: <String, dynamic>{
        ...data,
        'agent': <String, dynamic>{
          ...agent,
          if (applied) 'applied': true,
          if (dismissed) 'dismissed': true,
        },
      },
    );
    provider.aiPanel.sessionManager.updateMessages(messages);
  }

  Widget _buildComposer() {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppDesignSystem.workbenchComposerMinHeight,
        maxHeight: AppDesignSystem.workbenchComposerMaxHeight,
      ),
      child: AiInputArea(
        isSending: _isSending,
        onSend: _sendMessage,
        onStop: _stopAI,
        onShowApiSettings: _showApiSettings,
        onSlashCommand: _executeSlashCommandAction,
        enableTableMention: true,
        onTableMentionQuery: _queryTableMention,
      ),
    );
  }
}

/// AC9.2 加载骨架：AI 请求进行中的对话列占位（公开小组件，供组件测试与
/// 发送态复用；仿经典骨架语义新建轻量实现——§7.8 不提级经典私有类）。
class WorkbenchChatLoading extends StatelessWidget {
  const WorkbenchChatLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: context.themeColors.accentPurple,
            child: const Icon(LucideIcons.bot, size: 14, color: Colors.white),
          ),
          const SizedBox(width: AppDesignSystem.space2_5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        l10n.workbenchLoadingState,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.themeColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: context.themeColors.accentPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDesignSystem.space2),
                _skeletonLine(context, width: 200),
                const SizedBox(height: AppDesignSystem.space1_5),
                _skeletonLine(context, width: double.infinity),
                const SizedBox(height: AppDesignSystem.space1_5),
                _skeletonLine(context, width: 150),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _skeletonLine(BuildContext context, {required double width}) {
    return Container(
      width: width,
      height: 10,
      decoration: BoxDecoration(
        color: context.themeColors.textMuted.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
    );
  }
}
