//! agent 运行轨迹卡（tasks-ai-agent.md T13 / design-ai-agent.md D9、§5.2 /
//! design-ai-agent-ui.md §1 全节 + §0 通则为唯一视觉依据，数值逐字执行）。
//!
//! 三件事：
//! 1. **分组纯函数** [agentTrajectoryGrouping]：把会话消息流按 `runId` 折叠为
//!    「锚点..终局」区间组（多 run 各一组；无终局 = 中断态组），非 agent 消息
//!    原样平铺（时间序保持），供 T14 的 itemBuilder 消费；`agent_suggest` 类
//!    kind 的排除规则**留 A2**（T26 接线）——本函数只留 [excludeFromRun]
//!    参数化判断点，不写死 A2 分支（FC-6）。
//! 2. **卡体** [AgentTrajectoryCard]：run 级折叠轨迹卡。折叠态（终局默认）只
//!    构建 header + 终局汇报行（60px）——步列表与步详情 `findsNothing`
//!    （NF1.1 懒构建写死，不得改为预构建）；展开态步摘要行 24（标记例外制：
//!    无标记 = 默认成功）+ 步详情懒构建（仅该步展开时构建）+ 单一滚动区
//!    （卡体上限 360，不嵌套滚动）；completed 终局的「模型回复」区渲染于
//!    滚动区内、步列表之前（附录 2 M1，长回复不突破 360 上限）。
//! 3. **内嵌块宿主机制**（§1.6）：门卡消息在触发它的那一步的详情位渲染嵌块
//!    ——`agent_confirm` 经 [AgentTrajectoryCard.gateBlockBuilder] 渲染
//!    [AgentConfirmCard]（决策回调经 [AgentTrajectoryCard.onGateDecision]
//!    注入）；`agent_plan` 经 [AgentTrajectoryCard.planBlockBuilder] 渲染
//!    [AgentPlanCard]（T23 加法，同缝参数化：计划对象经
//!    [AgentTrajectoryCard.planResolver] 解析、回调闭包宿主注入，决策后收
//!    进 submit 步详情位同 confirm 模式）。
//!    awaitingUser 时：卡强制展开、折叠开关禁用、未决嵌块不可折叠、自动滚入
//!    视口（§5.2 结构保证）。
//!
//! 实时计数（AC3.1）：header 的 chip / `n/max` / token 经 `ListenableBuilder`
//! 读注入的 [AgentTrajectoryCard.runner]（null = 历史/中断态静态渲染）——卡**不
//! 重写消息 JSON**（消息对象 id 不变，§1.8-3 断言目标）。
//!
//! 10 态状态清单（§1.2 状态表）：running / awaitingUser / stopping（实时态，
//! 来自 runner）+ completed / stoppedByUser / stoppedByLimit / stoppedByFailures
//! / failed（终局态，来自终局消息 status）+ interrupted（派生态：有锚点无终局
//! ——只显 `n 步`、token「—」、maxSteps 自锚点 contextSnapshot 恢复进视图模型）
//! + Unknown（终局 status 不可解析的兜底）。
//!
//! 卡面语言沿 §0.1 / M1（bgSecondary 卡框 + 1px borderStrong 描边 + 3px 状态
//! 左色条 + header 34）；文字只用中性三档（+ error 告警，§0.2 铁律）。本文件
//! 不 import providers（runner 经构造注入）；不碰 ARB（key 引用 T03）。

import 'dart:convert' show jsonEncode;
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/ai_message_type.dart' show AiMessageType;
import '../../../models/database_models.dart' show AiMessage;
import '../../../services/ai/agent/agent_gate_analysis.dart'
    show ReadImpactAnalysis;
import '../../../services/ai/agent/agent_loop_runner.dart'
    show AgentLoopRunner, AgentRunStatus;
import '../../../services/ai/agent/agent_plan.dart'
    show AgentActionPlan, AgentPlanStatus;
import '../../../services/ai/agent/agent_ui_port.dart' show GateCardResult;
import '../../../theme/app_colors.dart';
import '../cards/result_snapshot_table.dart';
import 'agent_confirm_card.dart';
import 'agent_plan_card.dart';

// ── 分组纯函数（T14 itemBuilder 消费面）──────────────────────────────────────

/// 消息的 agent 载荷（`toolResultData['agent']`）；null = 非 agent 消息。
Map<String, dynamic>? agentPayloadOf(AiMessage message) =>
    message.toolResultData?['agent'] is Map<String, dynamic>
    ? message.toolResultData!['agent'] as Map<String, dynamic>
    : null;

/// agent 载荷 kind（`agent_run` / `agent_step` / `agent_confirm` /
/// `agent_plan`（A2）/ `agent_run_end` / `agent_suggest`（A2））；null = 非
/// agent 消息。
String? agentKindOf(AiMessage message) =>
    agentPayloadOf(message)?['kind'] is String
    ? agentPayloadOf(message)!['kind'] as String
    : null;

/// 消息载荷内的 stepNo（门卡/步消息用；缺省 null）。
int? agentStepNoOf(AiMessage message) =>
    (agentPayloadOf(message)?['stepNo'] as num?)?.toInt();

/// 一次 agent run 的折叠组（分组输出）：`[锚点..终局]` 区间内全部消息
/// （锚点 / 步消息对 / 门卡 / 终局），时间序；[terminal] 为 null = 中断态组
/// （有锚点无终局，AC15.6）。
///
/// [messages] / [terminal] 在分组过程中可变（累积器语义），分组返回后视为
/// 冻结；[anchor] 为惰性 getter（首条 `agent_run` 消息，防御缺失）。
class AgentTrajectoryRunGroup {
  AgentTrajectoryRunGroup({required this.runId, List<AiMessage>? messages})
    : messages = messages ?? <AiMessage>[];

  final String runId;

  /// 区间内全部消息（含锚点与终局；步消息对 = toolCall + toolResult 两条）。
  final List<AiMessage> messages;

  /// 终局消息（`kind == 'agent_run_end'`）；null = 中断态组。
  AiMessage? terminal;

  /// 锚点消息（`kind == 'agent_run'`；防御：缺失时回退首条 agent 消息或首条）。
  AiMessage get anchor {
    for (final AiMessage m in messages) {
      if (agentKindOf(m) == 'agent_run') return m;
    }
    for (final AiMessage m in messages) {
      if (agentPayloadOf(m) != null) return m;
    }
    return messages.first;
  }
}

/// 对话流分段：要么是一个 agent run 折叠组（[run]），要么是一条平铺消息
/// （[message]，走既有渲染路径）。
class AgentTrajectorySegment {
  const AgentTrajectorySegment._({this.run, this.message})
    : assert(
        (run == null) != (message == null),
        'segment must carry exactly one of run/message',
      );

  /// 非 null = agent run 组（渲染为一张轨迹卡）。
  final AgentTrajectoryRunGroup? run;

  /// 非 null = 平铺消息（用户消息 / 经典消息 / 排除出折叠区间的 kind）。
  final AiMessage? message;

  bool get isRun => run != null;
}

/// 会话消息流 → 轨迹分段序列（纯函数，不修改调用方列表）。
///
/// 规则（design §5.2 / D9）：
/// - 带 agent 载荷且带 runId 的消息折叠进其 run 组（多 run 各一组，组序 = 锚点
///   首次出现序）；
/// - 步消息对吸收：紧跟 agent 步消息（`agent_step` / 门卡）之前的 `toolCall`
///   消息一并入组（executor 落账恒成对连续；经典 toolCall 不匹配则原样平铺）；
/// - [excludeFromRun]（FC-6 参数化判断点，A2 T26 接 `agent_suggest`）：命中
///   的 kind **不进折叠区间**，按消息位置平铺为顶级消息；本函数不写死任何
///   具体排除分支；
/// - 非 agent 消息原样平铺，时间序保持。
List<AgentTrajectorySegment> agentTrajectoryGrouping(
  List<AiMessage> messages, {
  bool Function(String kind)? excludeFromRun,
}) {
  final List<AgentTrajectorySegment> segments = <AgentTrajectorySegment>[];
  final Map<String, AgentTrajectoryRunGroup> groups =
      <String, AgentTrajectoryRunGroup>{};
  AiMessage? bufferedCall;

  void flushBufferedCall() {
    final AiMessage? buffered = bufferedCall;
    if (buffered != null) {
      bufferedCall = null;
      segments.add(AgentTrajectorySegment._(message: buffered));
    }
  }

  void pushPlain(AiMessage message) {
    flushBufferedCall();
    segments.add(AgentTrajectorySegment._(message: message));
  }

  for (final AiMessage m in messages) {
    final Map<String, dynamic>? payload = agentPayloadOf(m);
    if (payload == null) {
      if (m.type == AiMessageType.toolCall) {
        // 步消息对的 call 半条：暂存，待下一条 agent 步消息认领。
        flushBufferedCall();
        bufferedCall = m;
      } else {
        pushPlain(m);
      }
      continue;
    }
    final String? kind = payload['kind'] is String
        ? payload['kind'] as String?
        : null;
    // FC-6 参数化判断点：命中的 kind 排除出折叠区间（A2 T26 接线，本任务
    // 默认 null = 不排除任何 kind）。
    if (kind != null && excludeFromRun != null && excludeFromRun(kind)) {
      pushPlain(m);
      continue;
    }
    final String? runId = payload['runId'] is String
        ? payload['runId'] as String?
        : null;
    if (runId == null) {
      pushPlain(m); // 防御：缺 runId 的 agent 载荷不折叠
      continue;
    }
    final AgentTrajectoryRunGroup group = groups.putIfAbsent(runId, () {
      final AgentTrajectoryRunGroup g = AgentTrajectoryRunGroup(runId: runId);
      segments.add(AgentTrajectorySegment._(run: g));
      return g;
    });
    if (kind == 'agent_run_end' && group.terminal == null) {
      group.terminal = m;
    }
    final AiMessage? call = bufferedCall;
    if (call != null) {
      bufferedCall = null;
      group.messages.add(call);
    }
    group.messages.add(m);
  }
  flushBufferedCall();
  return segments;
}

// ── token 紧凑格式（§1.2：<1000 原值 / ≥1000 一位小数 k / ≥1M 一位小数 M）──

/// token 计数紧凑格式（公开供 A3 T30 会话级 chip 复用同源口径）。
String agentTrajectoryCompactTokens(int value) {
  if (value < 1000) return value.toString();
  if (value < 1000000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '${(value / 1000000).toStringAsFixed(1)}M';
}

// ── 卡体 ─────────────────────────────────────────────────────────────────────

/// 门卡内嵌块渲染器（参数化宿主机制，§1.6）：默认渲染 [AgentConfirmCard]
/// （[buildDefaultAgentGateBlock]），只服务 `agent_confirm` kind；
/// `agent_plan` kind 走 [AgentPlanGateBlockBuilder]（T23 同缝加法）。
typedef AgentGateBlockBuilder =
    Widget Function(
      BuildContext context, {
      required AiMessage gateMessage,
      required GateCardResult? outcome,
      required void Function(GateCardResult decision) onDecision,
    });

/// 默认门卡嵌块：从门卡消息载荷重建 [ReadImpactAnalysis] + SQL 渲染
/// [AgentConfirmCard]（缺 impact 字段的防御态 → analysisUnavailable 保守档）。
Widget buildDefaultAgentGateBlock(
  BuildContext context, {
  required AiMessage gateMessage,
  required GateCardResult? outcome,
  required void Function(GateCardResult decision) onDecision,
}) {
  final Map<String, dynamic> payload = agentPayloadOf(gateMessage) ?? const {};
  final Object? rawImpact = payload['impact'];
  final Map<String, dynamic> impactMap = rawImpact is Map<String, dynamic>
      ? rawImpact
      : const <String, dynamic>{};
  final ReadImpactAnalysis impact = ReadImpactAnalysis(
    estimatedRows: (impactMap['estimatedRows'] as num?)?.toInt(),
    fullScan: impactMap['fullScan'] is bool
        ? impactMap['fullScan']! as bool
        : false,
    scannedTables: List<String>.from(
      (impactMap['scannedTables'] as List<Object?>? ?? const <Object?>[])
          .whereType<String>(),
    ),
    indexSummary: impactMap['indexSummary'] is String
        ? impactMap['indexSummary'] as String?
        : null,
    analysisUnavailable: impactMap['analysisUnavailable'] is bool
        ? impactMap['analysisUnavailable'] as bool
        : true, // 缺分析数据 → 保守档（AC8.6 fail-closed 同语义）
  );
  return AgentConfirmCard(
    impact: impact,
    sql: payload['sql'] is String ? payload['sql']! as String : '',
    outcome: outcome,
    onDecision: onDecision,
  );
}

/// 计划嵌块渲染器（T23 加法，与门卡嵌块渲染器同缝参数化，§1.6/§3.1）：宿主
/// （T27/T28）注入，闭包内持有 [AgentPlanCallbacks]（批准/拒绝/生成回退的
/// 执行在宿主）；[plan] = 宿主按门卡消息解析出的活跃计划对象（就地可变，
/// 卡每次重建重读全量——刷新通道 = `AgentPlanExecutionDeps
/// .onStepStateChange` 触发携带轨迹卡的子树重建）。
typedef AgentPlanGateBlockBuilder =
    Widget Function(
      BuildContext context, {
      required AiMessage gateMessage,
      required AgentActionPlan plan,
    });

/// agent 轨迹卡（ui 规格 §1；接口草案：`runMessages` + 可选 `runner`）。
///
/// [runMessages] = 分组函数产出的组内消息（`group.messages`）；[runner] 为
/// 运行中的实时态来源（null = 历史/中断态静态渲染，卡不重写消息 JSON）。
class AgentTrajectoryCard extends StatefulWidget {
  const AgentTrajectoryCard({
    super.key,
    required this.runMessages,
    this.runner,
    this.gateBlockBuilder = buildDefaultAgentGateBlock,
    this.planResolver,
    this.planBlockBuilder,
    this.onGateDecision,
    this.onOpenResultInStage,
    this.onViewFailureBoundary,
  });

  /// 一个 run 的区间消息（锚点起、终局止；中断组无终局）。
  final List<AiMessage> runMessages;

  /// 实时态来源（status/stepsUsed/maxSteps/tokenUsage/activeRunId）；
  /// null = 历史/中断态静态渲染。
  final AgentLoopRunner? runner;

  /// 门卡内嵌块渲染器（默认 [buildDefaultAgentGateBlock]，渲染
  /// `agent_confirm`；`agent_plan` kind 走 [planBlockBuilder]，不经本渲染器）。
  final AgentGateBlockBuilder gateBlockBuilder;

  /// 计划门卡消息 → 活跃计划对象（T23 加法；宿主 T27/T28 按 payload planId
  /// 从计划注册表解析）。null 返回 = 未接线 / 历史会话无对象——计划嵌块
  /// 防御性不渲染；pending 判定（未决强制展开）同样经它读
  /// `plan.status == pendingApproval`。
  final AgentActionPlan? Function(AiMessage gateMessage)? planResolver;

  /// 计划嵌块渲染器（T23；与 [planResolver] 成对注入。未注入时 `agent_plan`
  /// 门卡不渲染嵌块——A1 目录无计划工具，该分支不可达）。
  final AgentPlanGateBlockBuilder? planBlockBuilder;

  /// 门卡决策回调（T14 接 shell 的在途 Completer；未注入时卡面回调为空转，
  /// 消息 outcome 回填归宿主）。
  final void Function(String runId, int stepNo, GateCardResult decision)?
  onGateDecision;

  /// 步详情「在舞台打开」动作（A2 T24 舞台接线；未注入时按钮照常渲染不
  /// 禁用——沿 M1 SqlToolCard 接口预留先例）。
  final void Function(String runId, int stepNo)? onOpenResultInStage;

  /// 终局汇报行 [查看失败边界] 入口（A2 预留：仅当终局 status 为
  /// partialFailed / rollbackOffered 且回调注入时渲染，A1 默认不渲染）。
  final VoidCallback? onViewFailureBoundary;

  /// header 整行（折叠热区 + 焦点宿主）。
  static const Key headerKey = ValueKey('agent_trajectory_card_header');

  /// 状态 chip。
  static const Key statusChipKey = ValueKey(
    'agent_trajectory_card_status_chip',
  );

  /// 状态 chip 前置图标（10px）。
  static const Key chipIconKey = ValueKey('agent_trajectory_card_chip_icon');

  /// header 步数计数（`n/max`；中断态为 `Steps: n`）。
  static const Key stepsCounterKey = ValueKey('agent_trajectory_card_steps');

  /// header token 计数（紧凑格式；usage 缺失 = 「—」）。
  static const Key tokenCounterKey = ValueKey('agent_trajectory_card_tokens');

  /// 折叠开关 chevron。
  static const Key chevronKey = ValueKey('agent_trajectory_card_chevron');

  /// 终局汇报行（终局/中断态恒显，不被折叠吃掉）。
  static const Key reportRowKey = ValueKey('agent_trajectory_card_report_row');

  /// 终局「模型回复」区（附录 2 M1：completed 且正文非空且 ≠ summary 时，
  /// 展开态渲染于卡体滚动区内、步列表之前；折叠态零构建）。
  static const Key finalReplyKey = ValueKey(
    'agent_trajectory_card_final_reply',
  );

  /// 展开态步列表滚动区（单一滚动区；懒构建守护断言目标，NF1.1）。
  static const Key stepsScrollKey = ValueKey(
    'agent_trajectory_card_steps_scroll',
  );

  /// 步摘要行（按 stepNo）。
  static Key stepRowKey(int stepNo) =>
      ValueKey('agent_trajectory_step_row_$stepNo');

  /// 步详情块（按 stepNo；懒构建守护断言目标）。
  static Key stepDetailKey(int stepNo) =>
      ValueKey('agent_trajectory_step_detail_$stepNo');

  /// 门卡内嵌块（按门卡消息 id）。
  static Key gateBlockKey(String messageId) =>
      ValueKey('agent_trajectory_gate_block_$messageId');

  /// 步详情「在舞台打开」动作（按 stepNo）。
  static Key openInStageKey(int stepNo) =>
      ValueKey('agent_trajectory_open_in_stage_$stepNo');

  @override
  State<AgentTrajectoryCard> createState() => _AgentTrajectoryCardState();
}

// ── 运行视图（消息解析，只读）────────────────────────────────────────────────

/// 单步数据（toolCall + toolResult 对；`agent_step` 载荷在 result 消息）。
class _StepData {
  const _StepData({required this.result, this.call});

  /// toolCall 半条（参数来源）；null = 历史档缺对（防御）。
  final AiMessage? call;

  /// toolResult 半条（载荷所在）。
  final AiMessage result;

  Map<String, dynamic> get payload => agentPayloadOf(result) ?? const {};

  int get stepNo => (payload['stepNo'] as num?)?.toInt() ?? 0;

  String get tool =>
      payload['tool'] is String ? payload['tool']! as String : '';

  String? get gateLevel =>
      payload['gateLevel'] is String ? payload['gateLevel']! as String? : null;

  String get gateDecision => payload['gateDecision'] is String
      ? payload['gateDecision']! as String
      : '';

  String get summary => result.toolResultSummary ?? result.content;

  int get durationMs => (payload['durationMs'] as num?)?.toInt() ?? 0;

  Map<String, dynamic> get resultRef =>
      payload['resultRef'] is Map<String, dynamic>
      ? payload['resultRef']! as Map<String, dynamic>
      : const <String, dynamic>{};

  int? get rowCount => (resultRef['rowCount'] as num?)?.toInt();

  List<String> get columns => List<String>.from(
    (resultRef['columns'] as List<Object?>? ?? const <Object?>[])
        .whereType<String>(),
  );

  List<Map<String, dynamic>> get snapshotRows {
    final Object? raw = resultRef['snapshotRows'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final Object? row in raw)
        if (row is Map<String, dynamic>) row,
    ];
  }

  String? get errorCode {
    final Object? raw = payload['error'];
    if (raw is Map<String, dynamic> && raw['code'] is String) {
      return raw['code']! as String?;
    }
    return null;
  }

  String? get errorMessage {
    final Object? raw = payload['error'];
    if (raw is Map<String, dynamic> && raw['message'] is String) {
      return raw['message']! as String?;
    }
    return null;
  }

  bool get hasError => errorCode != null || errorMessage != null;

  /// 工具调用参数（call 半条；历史缺对时空表）。
  Map<String, dynamic> get args =>
      call?.toolArguments ?? const <String, dynamic>{};

  /// 参数中的 SQL（execute_readonly_sql / get_sample_data 等）。
  String? get argSql => args['sql'] is String ? args['sql']! as String : null;
}

/// 一个 run 的解析视图（State 持有；消息变更时重解析，只读消费）。
class _RunView {
  _RunView._({
    required this.runId,
    required this.anchor,
    required this.steps,
    required this.gateCards,
    required this.terminal,
    required this.anchorMaxSteps,
  });

  final String runId;
  final AiMessage anchor;
  final List<_StepData> steps; // stepNo 升序
  final List<AiMessage> gateCards; // 时间序
  final AiMessage? terminal;
  final int? anchorMaxSteps;

  static _RunView parse(List<AiMessage> messages) {
    String? runId;
    AiMessage? anchor;
    AiMessage? terminal;
    int? anchorMaxSteps;
    final Map<int, _StepData> steps = <int, _StepData>{};
    final List<AiMessage> gates = <AiMessage>[];
    AiMessage? pendingCall;

    for (final AiMessage m in messages) {
      final Map<String, dynamic> payload = agentPayloadOf(m) ?? const {};
      if (payload.isEmpty) {
        if (m.type == AiMessageType.toolCall) {
          pendingCall = m;
        }
        continue;
      }
      final String? kind = payload['kind'] is String
          ? payload['kind'] as String?
          : null;
      final String? msgRunId = payload['runId'] is String
          ? payload['runId']! as String
          : null;
      runId = msgRunId ?? runId;
      switch (kind) {
        case 'agent_run':
          anchor = anchor ?? m;
          final Object? snap = payload['contextSnapshot'];
          if (snap is Map<String, dynamic> && snap['maxSteps'] is num) {
            anchorMaxSteps = (snap['maxSteps']! as num).toInt();
          }
        case 'agent_step':
          final int stepNo = (payload['stepNo'] as num?)?.toInt() ?? 0;
          steps.putIfAbsent(
            stepNo,
            () => _StepData(result: m, call: pendingCall),
          );
          pendingCall = null;
        case 'agent_confirm':
        case 'agent_plan':
          gates.add(m);
          pendingCall = null;
        case 'agent_run_end':
          terminal = terminal ?? m;
        default:
          break; // agent_suggest（A2）等未知 kind 不入卡视图
      }
    }
    // 防御：消息序异常（无锚点）时首条消息兜底为锚点；空列表合成占位消息
    //（卡构造前置保证非空，此处仅防崩）。
    anchor =
        anchor ??
        (messages.isEmpty
            ? AiMessage(
                id: 'agent_anchor_empty',
                isUser: false,
                content: '',
                timestamp: DateTime.now(),
              )
            : messages.first);
    return _RunView._(
      runId: runId ?? '',
      anchor: anchor,
      steps: steps.values.toList()
        ..sort((_StepData a, _StepData b) => a.stepNo.compareTo(b.stepNo)),
      gateCards: gates,
      terminal: terminal,
      anchorMaxSteps: anchorMaxSteps,
    );
  }

  /// 该步的门卡（按 stepNo 匹配；A1 每步至多一卡）。
  AiMessage? gateForStep(int stepNo) {
    for (final AiMessage gate in gateCards) {
      if (agentStepNoOf(gate) == stepNo) return gate;
    }
    return null;
  }

  /// 无匹配步行的门卡（在途未决：步消息对尚未落账）。
  List<AiMessage> get gatesWithoutStep {
    final Set<int> stepNos = steps.map((_StepData s) => s.stepNo).toSet();
    return gateCards
        .where((AiMessage gate) => !stepNos.contains(agentStepNoOf(gate) ?? -1))
        .toList();
  }

  /// 终局 payload（无终局空表）。
  Map<String, dynamic> get terminalPayload =>
      terminal == null ? const {} : agentPayloadOf(terminal!) ?? const {};

  String get terminalStatus => terminalPayload['status'] is String
      ? terminalPayload['status']! as String
      : '';

  /// 终局 steps 计数（缺省回退解析步数）。
  int get terminalSteps =>
      (terminalPayload['steps'] as num?)?.toInt() ?? steps.length;

  /// 终局 summary 文本（与汇报行同源解析链；M1 回复区的判重基准）。
  String get terminalSummaryText {
    final Object? raw = terminalPayload['summaryText'];
    if (raw is String) return raw;
    return terminal?.toolResultSummary ?? terminal?.content ?? '';
  }

  /// 终局正文「模型回复」区渲染条件（附录 2 M1）：completed + 正文非空 +
  /// 正文 ≠ summary（相同 = 汇报行已承载，不重复渲染）。
  bool get hasFinalReply {
    if (terminalStatus != 'completed') return false;
    final String body = (terminal?.content ?? '').trim();
    return body.isNotEmpty && body != terminalSummaryText.trim();
  }
}

/// 卡显示态（§1.2 状态表 + Unknown 兜底 = 10 态）。
enum _DisplayState {
  running,
  awaitingUser,
  stopping,
  completed,
  stoppedByUser,
  stoppedByLimit,
  stoppedByFailures,
  failed,
  interrupted, // 派生态：有锚点无终局（AC15.6）
  unknown,
}

/// 步行标记规格（例外制，§1.3）。
class _MarkerSpec {
  const _MarkerSpec({
    required this.icon,
    required this.colorRole,
    required this.tooltip,
    this.label,
  });

  final IconData icon;
  final _MarkerColorRole colorRole;
  final String tooltip;
  final String? label;
}

enum _MarkerColorRole { accent, error }

/// 终局正文的分段（附录 2 M1）：散文段或围栏段二选一。
class _FinalReplySegment {
  const _FinalReplySegment({required this.isCode, required this.text});

  /// true = ``` 围栏代码段；false = 散文段。
  final bool isCode;

  /// 段文本（围栏段 = 两围栏行之间的原文；散文段 = 首尾去空白）。
  final String text;
}

/// 终局 content 按 ``` 围栏行级分段（附录 2 M1，纯函数）：围栏行 = 去左空白
/// 后以 ``` 开头的行（```sql 等语言标记同判）；围栏段内容 = 两围栏行之间的
/// 行原样保留（复制 = 围栏内全文）；散文段首尾去空白、空段跳过；未闭合围栏
/// 防御 = 余下全文收为围栏段。
List<_FinalReplySegment> _splitFinalReplySegments(String content) {
  final List<_FinalReplySegment> segments = <_FinalReplySegment>[];
  final List<String> prose = <String>[];
  final List<String> code = <String>[];
  bool inFence = false;

  void flushProse() {
    if (prose.isEmpty) return;
    final String text = prose.join('\n').trim();
    prose.clear();
    if (text.isNotEmpty) {
      segments.add(_FinalReplySegment(isCode: false, text: text));
    }
  }

  void flushCode() {
    if (code.isEmpty) return;
    segments.add(_FinalReplySegment(isCode: true, text: code.join('\n')));
    code.clear();
  }

  for (final String line in content.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      if (inFence) {
        flushCode();
      } else {
        flushProse();
      }
      inFence = !inFence;
      continue;
    }
    (inFence ? code : prose).add(line);
  }
  flushCode(); // 未闭合围栏防御：余下全文收为围栏段
  flushProse();
  return segments;
}

class _AgentTrajectoryCardState extends State<AgentTrajectoryCard> {
  late _RunView _view;

  /// 卡级折叠态（终局默认折叠；运行中默认展开；awaitingUser 计算性强制展开）。
  late bool _expanded;

  /// 展开了详情的步（懒构建：仅命中步构建详情）。
  final Set<int> _expandedSteps = <int>{};

  /// 展开了技术详情的错误步。
  final Set<int> _expandedErrorDetails = <int>{};

  /// SQL 块复制反馈（2s 复位，M1 同款语义）。
  int? _copiedSqlStep;

  /// 终局回复围栏段复制反馈（按段序号；2s 复位，同 _copySql 语义）。
  int? _copiedFinalSegment;

  late final FocusNode _headerFocus;
  final Map<int, FocusNode> _stepFocusNodes = <int, FocusNode>{};

  /// 未决门卡嵌块的定位锚（自动滚入视口用，§1.6）。
  final GlobalKey _pendingGateKey = GlobalKey(
    debugLabel: 'agent_trajectory_pending_gate',
  );

  /// 计划嵌块失败边界的定位锚（T23：终局汇报行 [查看失败边界] 滚动目标，
  /// §1.5——只挂最后一个计划嵌块，避免同 GlobalKey 双挂）。
  final GlobalKey _planBoundaryKey = GlobalKey(
    debugLabel: 'agent_trajectory_plan_boundary',
  );

  String? _lastPendingGateId;

  AgentLoopRunner? _subscribedRunner;
  AgentRunStatus? _lastSeenLiveStatus;

  // ── 生命周期 ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _view = _RunView.parse(widget.runMessages);
    _expanded = _isLive;
    _headerFocus = FocusNode(onKeyEvent: _onHeaderKeyEvent);
    _headerFocus.addListener(_onFocusChanged);
    _attachRunner();
    _maybeSchedulePendingScroll();
  }

  @override
  void didUpdateWidget(AgentTrajectoryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _view = _RunView.parse(widget.runMessages);
    if (widget.runner != _subscribedRunner) {
      _detachRunner();
      _attachRunner();
    }
    _maybeSchedulePendingScroll();
  }

  @override
  void dispose() {
    _detachRunner();
    _headerFocus.removeListener(_onFocusChanged);
    _headerFocus.dispose();
    for (final FocusNode node in _stepFocusNodes.values) {
      node.dispose();
    }
    _stepFocusNodes.clear();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _attachRunner() {
    final AgentLoopRunner? runner = widget.runner;
    if (runner == null) return;
    _subscribedRunner = runner;
    _lastSeenLiveStatus = runner.status;
    runner.addListener(_onRunnerNotify);
  }

  void _detachRunner() {
    final AgentLoopRunner? runner = _subscribedRunner;
    if (runner != null) runner.removeListener(_onRunnerNotify);
    _subscribedRunner = null;
  }

  /// 实时态翻转（status 变化）才整卡重建；步数/token 增量由 header 的
  /// ListenableBuilder 局部重建承担（AC3.1，不重写消息 JSON）。
  void _onRunnerNotify() {
    final AgentLoopRunner? runner = _subscribedRunner;
    if (runner == null) return;
    if (runner.status != _lastSeenLiveStatus) {
      _lastSeenLiveStatus = runner.status;
      if (mounted) setState(() {});
    }
  }

  // ── 派生态 ────────────────────────────────────────────────────────────────

  /// 本卡对应的 run 是否正在运行（runner 持有本 runId 且 isRunning）。
  bool get _isLive {
    final AgentLoopRunner? runner = widget.runner;
    return runner != null &&
        runner.activeRunId == _view.runId &&
        runner.isRunning;
  }

  _DisplayState get _displayState {
    if (_isLive) {
      switch (widget.runner!.status) {
        case AgentRunStatus.running:
          return _DisplayState.running;
        case AgentRunStatus.awaitingUser:
          return _DisplayState.awaitingUser;
        case AgentRunStatus.stopping:
          return _DisplayState.stopping;
        default:
          break; // isRunning 不变式下不可达，落静态派生
      }
    }
    if (_view.terminal != null) {
      switch (_view.terminalStatus) {
        case 'completed':
          return _DisplayState.completed;
        case 'stoppedByUser':
          return _DisplayState.stoppedByUser;
        case 'stoppedByLimit':
          return _DisplayState.stoppedByLimit;
        case 'stoppedByFailures':
          return _DisplayState.stoppedByFailures;
        case 'failed':
          return _DisplayState.failed;
        default:
          return _DisplayState.unknown;
      }
    }
    return _DisplayState.interrupted;
  }

  bool get _awaiting => _displayState == _DisplayState.awaitingUser;

  bool get _effectiveExpanded => _expanded || _awaiting;

  /// 门卡结论（载荷 outcome；未决且非实时 → 中断态既定降级 rejected =
  /// 「已随运行取消」，不改 payload，§5.2）。
  GateCardResult? _gateOutcome(AiMessage gate) {
    final Object? raw = agentPayloadOf(gate)?['outcome'];
    switch (raw) {
      case 'approved':
        return GateCardResult.approved;
      case 'approvedForSession':
        return GateCardResult.approvedForSession;
      case 'rejected':
        return GateCardResult.rejected;
      default:
        return _isLive ? null : GateCardResult.rejected;
    }
  }

  /// 首个未决门卡（实时态才有；自动滚入视口目标）。`agent_plan` kind 的
  /// 未决判定 = 解析出的活跃计划仍处 pendingApproval（计划状态在 plan 对象，
  /// 不在消息 payload，T23）。
  AiMessage? get _pendingGate {
    if (!_isLive) return null;
    for (final AiMessage gate in _view.gateCards) {
      if (agentKindOf(gate) == 'agent_plan') {
        final AgentActionPlan? plan = widget.planResolver?.call(gate);
        if (plan != null && plan.status == AgentPlanStatus.pendingApproval) {
          return gate;
        }
        continue;
      }
      if (agentPayloadOf(gate)?['outcome'] == null) return gate;
    }
    return null;
  }

  /// 门卡是否未决（嵌块强制渲染条件，§1.6）：confirm = 载荷无 outcome；
  /// plan = 活跃计划仍 pendingApproval（宿主未接线/计划不可解析 → 视为
  /// 已决，不做强制渲染——防御）。
  bool _gatePending(AiMessage gate) {
    if (agentKindOf(gate) == 'agent_plan') {
      final AgentActionPlan? plan = widget.planResolver?.call(gate);
      return plan != null && plan.status == AgentPlanStatus.pendingApproval;
    }
    return _gateOutcome(gate) == null;
  }

  /// 未决门卡出现时自动滚入视口（§1.6 结构保证：ensureVisible 走通全部祖先
  /// 滚动区——卡体与对话列两层）。
  void _maybeSchedulePendingScroll() {
    final AiMessage? pending = _pendingGate;
    if (pending == null || pending.id == _lastPendingGateId) return;
    _lastPendingGateId = pending.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? ctx = _pendingGateKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.2,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  /// 终局汇报行 [查看失败边界]（§1.5，T23 接线）：展开卡体 + 展开边界目标
  /// 计划所在的 submit 步详情（决策后计划嵌块收在步详情位，§1.6——只展开
  /// 卡体不展开详情时嵌块不可见，滚动目标落空）→ 滚动定位；宿主回调（若
  /// 注入）照常通知。
  void _onViewFailureBoundary() {
    widget.onViewFailureBoundary?.call();
    final AiMessage? gate = _boundaryPlanGate;
    final int? boundaryStepNo = gate == null ? null : agentStepNoOf(gate);
    final bool needExpand =
        !_effectiveExpanded ||
        (boundaryStepNo != null && !_expandedSteps.contains(boundaryStepNo));
    if (needExpand && mounted) {
      setState(() {
        _expanded = true;
        if (boundaryStepNo != null) _expandedSteps.add(boundaryStepNo);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? ctx = _planBoundaryKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.1,
          duration: const Duration(milliseconds: 200),
        );
      }
    });
  }

  /// 失败边界滚动目标：时间序最后一个计划门卡（多计划 run 下落点 = 最新
  /// 计划——失败计划本身或其回退计划，§1.5「滚动到计划块」语义）。
  AiMessage? get _boundaryPlanGate {
    for (final AiMessage gate in _view.gateCards.reversed) {
      if (agentKindOf(gate) == 'agent_plan') return gate;
    }
    return null;
  }

  // ── 交互 ──────────────────────────────────────────────────────────────────

  void _toggleHeader() {
    if (_awaiting) return; // 未决禁折叠（§1.2：onTap 空 + tooltip）
    setState(() => _expanded = !_expanded);
  }

  void _toggleStep(int stepNo) => setState(() {
    if (_expandedSteps.contains(stepNo)) {
      _expandedSteps.remove(stepNo);
    } else {
      _expandedSteps.add(stepNo);
    }
  });

  void _toggleErrorDetail(int stepNo) => setState(() {
    if (_expandedErrorDetails.contains(stepNo)) {
      _expandedErrorDetails.remove(stepNo);
    } else {
      _expandedErrorDetails.add(stepNo);
    }
  });

  /// 卡头键：Space/Enter 折叠（与整行点击同效）；Esc 从后代冒泡回卡头（§0.4）。
  KeyEventResult _onHeaderKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    final bool isActivate =
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (isActivate && node.hasPrimaryFocus) {
      _toggleHeader();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && !node.hasPrimaryFocus) {
      _headerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 卡体 Esc：详情区（行外焦点，如 SQL 选择文本/动作钮）回卡头（§1.8-8）。
  KeyEventResult _onBodyKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _headerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 步行键：←/↑/→/↓ roving 移动；Enter/Space 展开详情；Esc 回卡头（§1.3）。
  KeyEventResult _onStepKeyEvent(
    FocusNode node,
    int stepNo,
    int index,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final LogicalKeyboardKey key = event.logicalKey;
    final List<_StepData> steps = _view.steps;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      if (index > 0) _stepNode(steps[index - 1].stepNo).requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      if (index < steps.length - 1) {
        _stepNode(steps[index + 1].stepNo).requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (node.hasPrimaryFocus) _toggleStep(stepNo);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _headerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 步行焦点节点（懒建 + 焦点监听驱动行左缘 2px 竖条重建，§1.3）。
  FocusNode _stepNode(int stepNo) {
    return _stepFocusNodes.putIfAbsent(stepNo, () {
      final FocusNode node = FocusNode();
      node.addListener(_onFocusChanged);
      return node;
    });
  }

  Future<void> _copySql(int stepNo, String sql) async {
    await Clipboard.setData(ClipboardData(text: sql));
    if (!mounted) return;
    setState(() => _copiedSqlStep = stepNo);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _copiedSqlStep == stepNo) {
        setState(() => _copiedSqlStep = null);
      }
    });
  }

  /// 终局回复围栏段复制（反馈语义同 [_copySql]，按段序号记位）。
  Future<void> _copyFinalSegment(int index, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copiedFinalSegment = index);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _copiedFinalSegment == index) {
        setState(() => _copiedFinalSegment = null);
      }
    });
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final _DisplayState state = _displayState;
    final bool headerFocused = _headerFocus.hasFocus;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        // 焦点 1.5px accentBlue 替换 1px borderStrong（无发光无位移，§0.1）。
        border: Border.all(
          color: headerFocused ? colors.accentBlue : colors.borderStrong,
          width: headerFocused ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 3px 状态左色条（替换左边描边，随左圆角裁剪，§0.1/§0.3）。
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: Container(width: 3, color: _barColor(context, state)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context, state),
                if (_hasReportRow) _buildReportRow(context, state),
                // 懒构建（NF1.1 写死）：折叠态不构建步列表与步详情。
                if (_effectiveExpanded && _hasBody) _buildBody(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasReportRow =>
      _view.terminal != null || _displayState == _DisplayState.interrupted;

  bool get _hasBody =>
      _view.hasFinalReply ||
      _view.steps.isNotEmpty ||
      _view.gatesWithoutStep.isNotEmpty;

  // ── header（34，§1.2）────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, _DisplayState state) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return SizedBox(
      key: AgentTrajectoryCard.headerKey,
      height: AppDesignSystem.toolCardHeaderHeight,
      child: InkWell(
        focusNode: _headerFocus,
        // 点击即聚焦（InkWell 不自动 requestFocus）：整行可点折叠 + 后续
        // Space/Enter 键盘操作可达（沿 M1 sql_tool_card 先例）。
        onTap: () {
          _headerFocus.requestFocus();
          _toggleHeader();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.route,
                size: 16,
                color: _barColor(context, state),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Flexible(
                child: Tooltip(
                  message: l10n.agentTrajectoryTitle,
                  child: Text(
                    l10n.agentTrajectoryTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              // T27 缺陷修复配套：元信息区包 Flexible（窄列下与标题共享收缩）。
              Flexible(child: _buildHeaderMeta(context)),
              const SizedBox(width: AppDesignSystem.space1),
              _buildChevron(context),
            ],
          ),
        ),
      ),
    );
  }

  /// header 元信息区（chip + n/max + token）：runner 注入时经
  /// ListenableBuilder 实时读（AC3.1——不重写消息 JSON）；否则静态渲染。
  Widget _buildHeaderMeta(BuildContext context) {
    final AgentLoopRunner? runner = widget.runner;
    if (runner == null) return _headerMetaValues(context);
    return ListenableBuilder(
      listenable: runner,
      builder: (BuildContext context, _) => _headerMetaValues(context),
    );
  }

  Widget _headerMetaValues(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final _DisplayState state = _displayState;
    final AgentLoopRunner? runner = widget.runner;
    final bool live = _isLive;

    // 计数三源（§1.2）：实时 = runner；终局 = 终局消息 + 锚点 max；中断 =
    // stepsOnly + 「—」（maxSteps 自锚点恢复进视图模型，中断态不显 /max）。
    final int stepsCount;
    final int maxSteps;
    final int? tokens;
    if (live && runner != null) {
      stepsCount = runner.stepsUsed;
      maxSteps = runner.maxSteps;
      tokens = runner.tokenUsage?.totalTokens;
    } else if (_view.terminal != null) {
      stepsCount = _view.terminalSteps;
      maxSteps = _view.anchorMaxSteps ?? stepsCount;
      tokens = (_view.terminalPayload['tokens'] as num?)?.toInt();
    } else {
      stepsCount = _view.steps.length;
      maxSteps = _view.anchorMaxSteps ?? stepsCount;
      tokens = null;
    }

    final String stepsText = state == _DisplayState.interrupted
        ? l10n.agentTrajectoryStepsOnly(stepsCount)
        : l10n.agentTrajectorySteps(stepsCount, maxSteps);
    final String tokenText = tokens == null
        ? '—'
        : l10n.agentTrajectoryTokens(agentTrajectoryCompactTokens(tokens));

    final Widget tokenWidget = tokens == null
        ? Text(
            key: AgentTrajectoryCard.tokenCounterKey,
            tokenText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _monoStyle(context, colors.textSecondary),
          )
        : Tooltip(
            message: NumberFormat.decimalPattern().format(tokens),
            child: Text(
              key: AgentTrajectoryCard.tokenCounterKey,
              tokenText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _monoStyle(context, colors.textSecondary),
            ),
          );

    // T27 缺陷修复（舞台并置态对话列恒 360）：三件均 Flexible + ellipsis，
    // 窄列下元信息可收缩（宽屏 ≥ M1 实宽时各取固有宽，渲染零变化）。
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: _buildStatusChip(context, state)),
        const SizedBox(width: AppDesignSystem.space2),
        Flexible(
          child: Text(
            key: AgentTrajectoryCard.stepsCounterKey,
            stepsText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _monoStyle(context, colors.textSecondary),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Flexible(child: tokenWidget),
      ],
    );
  }

  TextStyle _monoStyle(BuildContext context, Color color) => TextStyle(
    fontSize: 11,
    fontFamily: AppDesignSystem.monoFontFamily,
    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    color: color,
  );

  /// 状态 chip（高 18：底 bgTertiary + 前置 10px 语义图标 + 11px textPrimary
  /// w500，§1.2）。
  Widget _buildStatusChip(BuildContext context, _DisplayState state) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final String label = switch (state) {
      _DisplayState.running => l10n.agentTrajectoryStatusRunning,
      _DisplayState.awaitingUser => l10n.agentTrajectoryAwaiting,
      _DisplayState.stopping => l10n.agentStopping,
      _DisplayState.completed => l10n.agentTrajectoryCompleted,
      _DisplayState.stoppedByUser => l10n.agentStoppedByUser,
      _DisplayState.stoppedByLimit => l10n.agentStoppedByLimit,
      _DisplayState.stoppedByFailures => l10n.agentStoppedByFailures(
        _view.terminalSteps,
      ),
      _DisplayState.failed => l10n.agentRunFailed,
      _DisplayState.interrupted => l10n.agentRunInterrupted,
      _DisplayState.unknown => l10n.agentTrajectoryUnknown,
    };
    final IconData icon = switch (state) {
      _DisplayState.running => LucideIcons.loader, // _SpinnerIcon 旋转呈现
      _DisplayState.awaitingUser => LucideIcons.hourglass,
      _DisplayState.stopping => LucideIcons.square,
      _DisplayState.completed => LucideIcons.circleCheck,
      _DisplayState.stoppedByUser => LucideIcons.square,
      _DisplayState.stoppedByLimit => LucideIcons.gauge,
      _DisplayState.stoppedByFailures => LucideIcons.triangleAlert,
      _DisplayState.failed => LucideIcons.circleX,
      _DisplayState.interrupted => LucideIcons.clockFading,
      _DisplayState.unknown => LucideIcons.helpCircle,
    };
    final Widget iconChild = state == _DisplayState.running
        ? _SpinnerIcon(size: 10, color: colors.accentBlue)
        : Icon(icon, size: 10, color: _chipIconColor(context, state));
    return Container(
      key: AgentTrajectoryCard.statusChipKey,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(key: AgentTrajectoryCard.chipIconKey, child: iconChild),
          const SizedBox(width: AppDesignSystem.space1),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// chevron（恒显 16 textMuted；awaitingUser 禁用 = textDisabled + tooltip，
  /// §1.2——缺专用 key，tooltip 沿用 agentTrajectoryAwaiting，登记偏差）。
  Widget _buildChevron(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final Widget chevron = Icon(
      key: AgentTrajectoryCard.chevronKey,
      _effectiveExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
      size: 16,
      color: _awaiting ? colors.textDisabled : colors.textMuted,
    );
    return _awaiting
        ? Tooltip(message: l10n.agentTrajectoryAwaiting, child: chevron)
        : chevron;
  }

  /// 左色条色（§0.3 状态映射）。
  Color _barColor(BuildContext context, _DisplayState state) {
    final colors = context.themeColors;
    return switch (state) {
      _DisplayState.running => colors.accentBlue,
      _DisplayState.awaitingUser => colors.warning,
      _DisplayState.stopping => colors.accentBlue,
      _DisplayState.completed => colors.success,
      _DisplayState.stoppedByUser => colors.borderStrong,
      _DisplayState.stoppedByLimit => colors.warning,
      _DisplayState.stoppedByFailures => colors.error,
      _DisplayState.failed => colors.error,
      _DisplayState.interrupted => colors.warning,
      _DisplayState.unknown => colors.borderStrong,
    };
  }

  Color _chipIconColor(BuildContext context, _DisplayState state) {
    final colors = context.themeColors;
    return switch (state) {
      _DisplayState.running => colors.accentBlue,
      _DisplayState.awaitingUser => colors.warning,
      _DisplayState.stopping => colors.textMuted,
      _DisplayState.completed => colors.success,
      _DisplayState.stoppedByUser => colors.textMuted,
      _DisplayState.stoppedByLimit => colors.warning,
      _DisplayState.stoppedByFailures => colors.error,
      _DisplayState.failed => colors.error,
      _DisplayState.interrupted => colors.warning,
      _DisplayState.unknown => colors.textMuted,
    };
  }

  // ── 终局汇报行（24 / 长文 36，恒显不被折叠吃掉，§1.5）───────────────────

  Widget _buildReportRow(BuildContext context, _DisplayState state) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final bool failureClass =
        state == _DisplayState.failed ||
        state == _DisplayState.stoppedByFailures;
    final String text = state == _DisplayState.interrupted
        ? l10n.agentRunInterrupted
        : _view.terminalPayload['summaryText'] is String
        ? _view.terminalPayload['summaryText']! as String
        : _view.terminal?.toolResultSummary ??
              _view.terminal?.content ??
              l10n.agentTrajectoryUnknown;
    final IconData icon = switch (state) {
      _DisplayState.completed => LucideIcons.circleCheck,
      _DisplayState.stoppedByUser => LucideIcons.square,
      _DisplayState.stoppedByLimit => LucideIcons.gauge,
      _DisplayState.stoppedByFailures => LucideIcons.triangleAlert,
      _DisplayState.failed => LucideIcons.circleX,
      _DisplayState.interrupted => LucideIcons.clockFading,
      _ => LucideIcons.helpCircle,
    };
    final Color iconColor = failureClass
        ? colors.error
        : _chipIconColor(context, state);

    // A2 预留：partialFailed / rollbackOffered 的 [查看失败边界] 入口（A1 终局
    // status 不可达，回调默认 null → 不渲染）。
    final bool failureBoundary =
        widget.onViewFailureBoundary != null &&
        (_view.terminalStatus == 'partialFailed' ||
            _view.terminalStatus == 'rollbackOffered');

    return ConstrainedBox(
      key: AgentTrajectoryCard.reportRowKey,
      constraints: const BoxConstraints(
        minHeight: AppDesignSystem.workbenchDenseRowHeight,
        maxHeight: 36,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
        child: Row(
          children: [
            Icon(icon, size: 12, color: iconColor),
            const SizedBox(width: AppDesignSystem.space1_5),
            Expanded(
              child: Tooltip(
                message: text,
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: failureClass
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                ),
              ),
            ),
            if (failureBoundary)
              Padding(
                padding: const EdgeInsets.only(left: AppDesignSystem.space2),
                child: InkWell(
                  onTap: _onViewFailureBoundary,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: iconColor),
                      const SizedBox(width: AppDesignSystem.space1),
                      Text(
                        l10n.agentTrajectoryViewBoundary,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 卡体（单一滚动区，上限 360，§1.1）───────────────────────────────────

  Widget _buildBody(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxHeight: AppDesignSystem.toolCardContentMaxHeight,
      ),
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _onBodyKeyEvent,
        child: SingleChildScrollView(
          key: AgentTrajectoryCard.stepsScrollKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 终局「模型回复」区（M1）：滚动区内、步列表之前——长回复
              // 随卡体单一滚动区，不突破 360 上限。
              if (_view.hasFinalReply) _buildFinalReply(context),
              ..._buildStepSequence(context),
            ],
          ),
        ),
      ),
    );
  }

  // ── 终局「模型回复」区（附录 2 M1）───────────────────────────────────────

  /// completed 终局的模型全文呈现（纯呈现面，无执行语义——不走 SQL 卡拦截
  /// 层，门在 SQL 卡执行时自然生效，AC9.4 链路不变）：散文段 = [MarkdownBody]
  /// 渲染（Fix-K：消费项目既有 flutter_markdown 管线，形态对齐经典面板
  /// ai_message_item._buildMarkdownContent；`selectable: true` 保留可选中
  /// 语义，`softLineBreak: true` 保持 Fix-A 以来的行级排版），样式见
  /// [_finalReplyMarkdownStyle]（正文 12 textSecondary 本卡基调）；围栏段 =
  /// 步 SQL 块同款视觉（[_codeBlock]，右上复制 2s 反馈）。[MarkdownBody]
  /// 非滚动组件，卡体 360 单一滚动区不变式不受影响。
  Widget _buildFinalReply(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final List<_FinalReplySegment> segments = _splitFinalReplySegments(
      _view.terminal?.content ?? '',
    );
    return Column(
      key: AgentTrajectoryCard.finalReplyKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, thickness: 1, color: colors.dividerColor),
        Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.agentFinalReply,
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
              const SizedBox(height: AppDesignSystem.space1),
              for (int i = 0; i < segments.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppDesignSystem.space1),
                if (segments[i].isCode)
                  _codeBlock(
                    context,
                    segments[i].text,
                    copied: _copiedFinalSegment == i,
                    onCopy: () => _copyFinalSegment(i, segments[i].text),
                  )
                else
                  MarkdownBody(
                    data: segments[i].text,
                    selectable: true,
                    softLineBreak: true,
                    styleSheet: _finalReplyMarkdownStyle(context),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 终局回复散文段的 Markdown 样式（Fix-K）：字段面沿用经典面板
  /// ai_message_item.dart `_buildMarkdownContent` 的既有语汇（p/h1-h3/strong/
  /// em/code/blockquote/listBullet/table*），数值收敛到本卡语境——正文 12
  /// textSecondary（Fix-A 基调），标题 textPrimary 收缩档；行内/围栏代码向
  /// [_codeBlock] 靠拢（codeBlockBg + mono 11 textPrimary），保证散文段内
  /// 行内代码与围栏段观感一致。中性三档 token（§0.2），不新增视觉语言。
  MarkdownStyleSheet _finalReplyMarkdownStyle(BuildContext context) {
    final colors = context.themeColors;
    return MarkdownStyleSheet(
      p: TextStyle(fontSize: 12, color: colors.textSecondary, height: 1.5),
      h1: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      h2: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      h3: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      h4: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      h5: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      h6: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      strong: TextStyle(
        fontWeight: FontWeight.bold,
        color: colors.textSecondary,
      ),
      em: TextStyle(fontStyle: FontStyle.italic, color: colors.textSecondary),
      del: TextStyle(
        decoration: TextDecoration.lineThrough,
        color: colors.textSecondary,
      ),
      code: TextStyle(
        fontSize: 11,
        fontFamily: AppDesignSystem.monoFontFamily,
        fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        color: colors.textPrimary,
        backgroundColor: colors.codeBlockBg,
      ),
      codeblockPadding: const EdgeInsets.all(AppDesignSystem.space2),
      codeblockDecoration: BoxDecoration(
        color: colors.codeBlockBg,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      blockquote: TextStyle(
        fontSize: 12,
        color: colors.textSecondary,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.borderStrong, width: 3)),
      ),
      listBullet: TextStyle(fontSize: 12, color: colors.textSecondary),
      tableHead: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
      tableBody: TextStyle(fontSize: 11, color: colors.textSecondary),
      tableBorder: TableBorder.all(color: colors.borderStrong, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space0_5,
      ),
    );
  }

  /// 步行序列：步行（24）→（展开时）步详情 →（未决或详情展开时）门卡嵌块；
  /// 在途未决门卡（步消息对未落账）按其 stepNo 追加在对应位置之后（时间序
  /// 正确，§1.6）。plan 嵌块（T23）：未决（plan 仍 pendingApproval）恒渲染，
  /// 决策后收进 submit 步详情位（同 confirm 决策后模式）。
  List<Widget> _buildStepSequence(BuildContext context) {
    final List<Widget> children = <Widget>[];
    final List<_StepData> steps = _view.steps;
    for (int i = 0; i < steps.length; i++) {
      final _StepData step = steps[i];
      children.add(
        Semantics(
          label: AppLocalizations.of(context)!.agentTrajectoryStep(step.tool),
          child: _buildStepRow(context, step, i),
        ),
      );
      final bool detailOpen = _expandedSteps.contains(step.stepNo);
      if (detailOpen) {
        children.add(_buildStepDetail(context, step));
      }
      final AiMessage? gate = _view.gateForStep(step.stepNo);
      if (gate != null) {
        if (detailOpen || _gatePending(gate)) {
          children.add(_buildGateBlock(context, gate));
        }
      }
    }
    for (final AiMessage gate in _view.gatesWithoutStep) {
      children.add(_buildGateBlock(context, gate));
    }
    return children;
  }

  // ── 步摘要行（24，标记例外制，§1.3）─────────────────────────────────────

  Widget _buildStepRow(BuildContext context, _StepData step, int index) {
    final colors = context.themeColors;
    final FocusNode node = _stepNode(step.stepNo);
    node.onKeyEvent = (FocusNode n, KeyEvent e) =>
        _onStepKeyEvent(n, step.stepNo, index, e);
    final bool focused = node.hasFocus;
    final _MarkerSpec? marker = _markerFor(context, step);
    return Container(
      key: AgentTrajectoryCard.stepRowKey(step.stepNo),
      height: AppDesignSystem.workbenchDenseRowHeight,
      decoration: BoxDecoration(
        border: focused
            ? Border(left: BorderSide(color: colors.accentBlue, width: 2))
            : null,
      ),
      child: InkWell(
        focusNode: node,
        onTap: () => _toggleStep(step.stepNo),
        hoverColor: colors.bgTertiary,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '${step.stepNo}',
                  textAlign: TextAlign.right,
                  style: _monoStyle(context, colors.textMuted),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Icon(_toolIcon(step.tool), size: 12, color: colors.textMuted),
              const SizedBox(width: AppDesignSystem.space1_5),
              Flexible(
                flex: 3,
                child: Tooltip(
                  message: '${step.tool} · ${step.gateLevel ?? '-'}',
                  child: Text(
                    step.tool,
                    overflow: TextOverflow.ellipsis,
                    style: _monoStyle(context, colors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Flexible(
                flex: 4,
                child: Tooltip(
                  message: step.summary,
                  child: Text(
                    step.summary,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ),
              ),
              if (marker != null) ..._buildMarker(context, marker),
            ],
          ),
        ),
      ),
    );
  }

  /// 标记例外制（§1.3 标记表）：成功步无标记；人确认/会话放行 = shieldCheck
  /// accentBlue；门拦 = shieldX；人拒 = ban；工具失败 = circleAlert（后三者带
  /// 11px error 文案，maxWidth 96 + ellipsis）。
  _MarkerSpec? _markerFor(BuildContext context, _StepData step) {
    final l10n = AppLocalizations.of(context)!;
    final String decision = step.gateDecision;
    if (decision == 'confirmed') {
      return _MarkerSpec(
        icon: LucideIcons.shieldCheck,
        colorRole: _MarkerColorRole.accent,
        tooltip: l10n.agentStepGateConfirmed,
      );
    }
    if (decision == 'allowed_session') {
      return _MarkerSpec(
        icon: LucideIcons.shieldCheck,
        colorRole: _MarkerColorRole.accent,
        tooltip: l10n.agentStepGateSession,
      );
    }
    if (decision == 'blocked') {
      return _MarkerSpec(
        icon: LucideIcons.shieldX,
        colorRole: _MarkerColorRole.error,
        tooltip: step.errorMessage ?? step.errorCode ?? l10n.agentStepBlocked,
        label: l10n.agentStepBlocked,
      );
    }
    if (decision == 'rejected_by_user') {
      return _MarkerSpec(
        icon: LucideIcons.ban,
        colorRole: _MarkerColorRole.error,
        tooltip: step.errorMessage ?? step.errorCode ?? l10n.agentStepRejected,
        label: l10n.agentStepRejected,
      );
    }
    if (step.hasError) {
      return _MarkerSpec(
        icon: LucideIcons.circleAlert,
        colorRole: _MarkerColorRole.error,
        tooltip: step.errorMessage ?? step.errorCode ?? l10n.agentStepError,
        label: step.errorCode,
      );
    }
    return null; // allow + 成功 = 无标记（默认成功）
  }

  List<Widget> _buildMarker(BuildContext context, _MarkerSpec marker) {
    final colors = context.themeColors;
    final Color color = marker.colorRole == _MarkerColorRole.accent
        ? colors.accentBlue
        : colors.error;
    return <Widget>[
      const SizedBox(width: AppDesignSystem.space1_5),
      Tooltip(
        message: marker.tooltip,
        child: Icon(marker.icon, size: 12, color: color),
      ),
      if (marker.label != null) ...<Widget>[
        const SizedBox(width: AppDesignSystem.space1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 96),
          child: Tooltip(
            message: marker.tooltip,
            child: Text(
              marker.label!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.error),
            ),
          ),
        ),
      ],
    ];
  }

  // ── 步详情（懒构建：仅该步展开时构建，§1.4）─────────────────────────────

  Widget _buildStepDetail(BuildContext context, _StepData step) {
    final colors = context.themeColors;
    final Map<String, dynamic> nonSqlArgs = Map<String, dynamic>.from(step.args)
      ..remove('sql');
    final String? sql = step.argSql;
    return Column(
      key: AgentTrajectoryCard.stepDetailKey(step.stepNo),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(height: 1, thickness: 1, color: colors.dividerColor),
        Padding(
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nonSqlArgs.isNotEmpty)
                _fieldRow(context, 'args', _argsValue(context, nonSqlArgs)),
              if (sql != null && sql.isNotEmpty)
                _buildSqlBlock(context, step, sql),
              if (step.hasError)
                ..._buildErrorDetail(context, step)
              else if (step.resultRef.isNotEmpty)
                ..._buildResultDetail(context, step),
            ],
          ),
        ),
      ],
    );
  }

  /// 字段行骨架：行高 24 + 标签列 56 + 值列 Flexible（§1.4）。
  Widget _fieldRow(BuildContext context, String labelKey, Widget value) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final String labelText = switch (labelKey) {
      'args' => l10n.agentStepArgs,
      'sql' => l10n.agentStepSql,
      'snapshot' => l10n.agentStepSnapshot,
      'error' => l10n.agentStepError,
      _ => labelKey,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppDesignSystem.workbenchDenseRowHeight,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              labelText,
              maxLines: 2,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(child: value),
        ],
      ),
    );
  }

  /// 参数值：非 SQL 参数压成 `k=v · k=v`，mono 11 textSecondary，maxLines 2 +
  /// ellipsis + tooltip 全文（§1.4）。
  Widget _argsValue(BuildContext context, Map<String, dynamic> args) {
    final String text = _argsText(args);
    return Tooltip(
      message: text,
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _monoStyle(context, context.themeColors.textSecondary),
      ),
    );
  }

  String _argsText(Map<String, dynamic> args) => args.entries
      .map((MapEntry<String, dynamic> e) => '${e.key}=${_argValue(e.value)}')
      .join(' · ');

  String _argValue(Object? value) => value is String
      ? value
      : value is num || value is bool
      ? value.toString()
      : jsonEncode(value);

  /// 代码块视觉（步 SQL 块与终局回复围栏段共用，M1）：codeBlockBg 块
  /// （mono 11 / 1.4 / SelectableText 全文不截断）+ 块右上「复制」钮
  /// （copied 态 2s 反馈，由调用方记位）。
  Widget _codeBlock(
    BuildContext context,
    String text, {
    required bool copied,
    required VoidCallback onCopy,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.codeBlockBg,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              color: colors.textPrimary,
            ),
          ),
        ),
        Positioned(
          top: AppDesignSystem.space1,
          right: AppDesignSystem.space1,
          child: InkWell(
            onTap: onCopy,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1,
                vertical: AppDesignSystem.space0_5,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    copied ? LucideIcons.check : LucideIcons.copy,
                    size: 12,
                    color: copied ? colors.success : colors.textMuted,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Text(
                    copied ? l10n.messageCopied : l10n.aiPanelCopy,
                    style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// SQL 块：标签 + 代码块视觉（§1.4）。
  Widget _buildSqlBlock(BuildContext context, _StepData step, String sql) {
    return _fieldRow(
      context,
      'sql',
      _codeBlock(
        context,
        sql,
        copied: _copiedSqlStep == step.stepNo,
        onCopy: () => _copySql(step.stepNo, sql),
      ),
    );
  }

  /// 结果行 + 快照（§1.4）：meta mono 11 textSecondary；「在舞台打开」仅
  /// rowCount > 快照上限时出现（AC5.4 定律 5「截断给完整值入口」）；快照复用
  /// [ResultSnapshotTable]（≤10 行）；截断时表尾计数注记。
  List<Widget> _buildResultDetail(BuildContext context, _StepData step) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final int rowCount = step.rowCount ?? step.snapshotRows.length;
    final bool truncated = rowCount > AppDesignSystem.toolCardSnapshotRows;
    return <Widget>[
      SizedBox(
        height: AppDesignSystem.workbenchDenseRowHeight,
        child: Row(
          children: [
            Flexible(
              child: Text(
                l10n.agentStepResultMeta(
                  rowCount,
                  step.columns.length,
                  step.durationMs,
                ),
                overflow: TextOverflow.ellipsis,
                style: _monoStyle(context, colors.textSecondary),
              ),
            ),
            if (truncated) ...<Widget>[
              const SizedBox(width: AppDesignSystem.space2),
              InkWell(
                key: AgentTrajectoryCard.openInStageKey(step.stepNo),
                onTap: () =>
                    widget.onOpenResultInStage?.call(_view.runId, step.stepNo),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space1,
                    vertical: AppDesignSystem.space0_5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.externalLink,
                        size: 12,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: AppDesignSystem.space1),
                      Text(
                        l10n.agentStepOpenInStage,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      if (step.snapshotRows.isNotEmpty) ...<Widget>[
        _fieldRow(context, 'snapshot', const SizedBox.shrink()),
        ResultSnapshotTable(
          columns: step.columns,
          rows: _snapshotCells(step.columns, step.snapshotRows),
        ),
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(top: AppDesignSystem.space0_5),
            child: Text(
              l10n.agentStepTruncated(step.snapshotRows.length, rowCount),
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ),
      ],
    ];
  }

  List<List<String>> _snapshotCells(
    List<String> columns,
    List<Map<String, dynamic>> rows,
  ) => <List<String>>[
    for (final Map<String, dynamic> row in rows)
      <String>[for (final String c in columns) _cellToString(row[c])],
  ];

  String _cellToString(Object? value) => value == null
      ? 'NULL'
      : value is String
      ? value
      : value is num || value is bool
      ? value.toString()
      : jsonEncode(value);

  /// 错误态（§1.4：替换结果/快照）：circleAlert + 错误码 mono 11 error +
  /// 摘要 12px textPrimary（maxLines 2）+ 可折技术详情（默认折叠）。
  List<Widget> _buildErrorDetail(BuildContext context, _StepData step) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    final bool detailOpen = _expandedErrorDetails.contains(step.stepNo);
    return <Widget>[
      SizedBox(
        height: AppDesignSystem.workbenchDenseRowHeight,
        child: Row(
          children: [
            Icon(LucideIcons.circleAlert, size: 12, color: colors.error),
            const SizedBox(width: AppDesignSystem.space1_5),
            Flexible(
              child: Text(
                step.errorCode ?? l10n.agentStepError,
                overflow: TextOverflow.ellipsis,
                style: _monoStyle(context, colors.error),
              ),
            ),
            if (step.errorMessage != null) ...<Widget>[
              const SizedBox(width: AppDesignSystem.space2),
              Tooltip(
                message: l10n.agentStepError,
                child: InkWell(
                  onTap: () => _toggleErrorDetail(step.stepNo),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  child: Icon(
                    detailOpen
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 12,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      SizedBox(
        width: double.infinity,
        child: Text(
          step.summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: colors.textPrimary),
        ),
      ),
      if (detailOpen && step.errorMessage != null)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: colors.codeBlockBg,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SelectableText(
            step.errorMessage!,
            style: _monoStyle(context, colors.textSecondary),
          ),
        ),
    ];
  }

  // ── 门卡内嵌块宿主（§1.6；agent_plan 分支 = T23 加法）────────────────────

  Widget _buildGateBlock(BuildContext context, AiMessage gate) {
    final int stepNo = agentStepNoOf(gate) ?? 0;
    final bool pending = _gatePending(gate);
    final Widget block;
    if (agentKindOf(gate) == 'agent_plan') {
      // 计划分支（T23）：经 planResolver 解析活跃计划对象后交宿主注入的
      // planBlockBuilder 渲染（回调闭包宿主持有）。未接线 / 历史会话解析
      // 不到计划对象 → 防御性不渲染（A1 目录无计划工具，常态不可达）。
      final AgentActionPlan? plan = widget.planResolver?.call(gate);
      final AgentPlanGateBlockBuilder? builder = widget.planBlockBuilder;
      if (plan == null || builder == null) return const SizedBox.shrink();
      block = builder(context, gateMessage: gate, plan: plan);
    } else {
      block = widget.gateBlockBuilder(
        context,
        gateMessage: gate,
        outcome: _gateOutcome(gate),
        onDecision: (GateCardResult decision) =>
            widget.onGateDecision?.call(_view.runId, stepNo, decision),
      );
    }
    Widget wrapped = Padding(
      key: AgentTrajectoryCard.gateBlockKey(gate.id),
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2,
        0,
        AppDesignSystem.space2,
        AppDesignSystem.space1,
      ),
      child: block,
    );
    // 未决嵌块挂定位锚（自动滚入视口，§1.6）；最后一个计划嵌块挂失败边界
    // 锚（终局汇报行 [查看失败边界] 的滚动目标，§1.5——只挂一个防同
    // GlobalKey 双挂）。
    if (pending) {
      wrapped = KeyedSubtree(key: _pendingGateKey, child: wrapped);
    } else if (agentKindOf(gate) == 'agent_plan' &&
        gate.id == _boundaryPlanGate?.id) {
      wrapped = KeyedSubtree(key: _planBoundaryKey, child: wrapped);
    }
    return wrapped;
  }

  IconData _toolIcon(String tool) => switch (tool) {
    'execute_readonly_sql' => LucideIcons.code,
    'list_tables' => LucideIcons.table,
    'describe_table' => LucideIcons.database,
    'get_sample_data' => LucideIcons.scanSearch,
    'explain_plan' => LucideIcons.gauge,
    'get_current_context' => LucideIcons.crosshair,
    _ => LucideIcons.wrench,
  };
}

/// running 态 chip 前置旋转 spinner（10×10，stroke 1.5，§1.2）。
class _SpinnerIcon extends StatefulWidget {
  const _SpinnerIcon({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  State<_SpinnerIcon> createState() => _SpinnerIconState();
}

class _SpinnerIconState extends State<_SpinnerIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) => Transform.rotate(
        angle: _controller.value * 2 * pi,
        child: CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _ArcPainter(color: widget.color),
        ),
      ),
    );
  }
}

/// 3/4 圆弧（stroke 1.5，round cap）——lucide loader 的自绘等价实现。
class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Offset.zero & size, -pi / 2, pi * 1.5, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color;
}
