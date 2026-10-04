// T13 AgentTrajectoryCard 测试（ui 规格 design-ai-agent-ui.md §1.8 九条验收
// 逐条 + §1.2/§1.3/§1.4/§1.5/§1.6 结构面 + 分组纯函数单测）。
//
// 覆盖：
// - 分组纯函数：多 run 各一组 / 无终局中断组 / 平铺区间边界（时间序）/
//   步消息对吸收（agent 对进组、经典 toolCall 不受影响）/ excludeFromRun
//   参数化判断点预留（agent_suggest 排除规则留 A2，FC-6）；
// - §1.8-1 折叠态只构建 header + 汇报行（步列表/步详情 findsNothing，
//   NF1.1 懒构建守护）+ 终局折叠 60 几何；
// - §1.8-2 展开态 3 步 = 34+24+3×24+2 几何；
// - §1.8-3 running 下每步刷新 n/max 与 token 且消息对象 id 不变（真实
//   AgentLoopRunner 驱动，脚本化 chat/门/db，沿 T11 测试台形态；stale 消息
//   列表 + 实时计数 = ListenableBuilder 读 runner 的直证）；
// - §1.8-4 10 态 chip 文案/图标逐态键断言（9 spec 态 + Unknown 兜底）+
//   token 紧凑格式三档 + usage 缺失「—」；
// - stoppedByContext 第五终止源显示态接线（标签 l10n 新键 / unplug 图标 /
//   n/max 计数同构，非 unknown 降级）；
// - §1.8-5 25 步单滚动区（卡体 ≤362、单 Scrollable、可滚动）；
// - §1.8-6 awaitingUser 强制展开 + chevron 禁用（tap 无效）+ 未决嵌块
//   可见（几何在视口内）；
// - §1.8-7 摘要行标记例外制（成功步无标记 / 门拦 shieldX / 失败 circleAlert）；
// - §1.8-8 键盘：Tab 进步列表、↓ roving、Enter 展开、Esc 回卡头；
// - §1.8-9 rowCount > 10 存在「在舞台打开」，≤ 10 findsNothing；
// - §1.6 内嵌宿主：默认 builder 重建确认卡 / 自定义 builder 注入 /
//   决策回调 onGateDecision / 决策后结论行（真实 runner 回填驱动）/
//   中断态未决门卡既定降级「已随运行取消」；
// - M1 终局「模型回复」区四条验收（design-ai-agent.md 附录 2 M1）：
//   ① completed + ```sql 围栏 → 展开态 finalReplyKey 渲染 + 复制剪贴板 =
//   围栏 SQL 全文；② 折叠态或非 completed → finalReplyKey findsNothing
//   （懒构建守护扩展）；③ 长回复不突破卡体 360 单滚动不变式；④ 0 步纯对话
//   run 展开态回复可见；⑤ markdown 渲染（Fix-K）：散文段走 MarkdownBody，
//   裸 ## / ** / 反引号不作为正文文本出现，围栏段复制语义保持。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/ai_message_type.dart'
    show AiMessageStatus, AiMessageType;
import 'package:dbmaster/models/ai_models.dart'
    show AiToolCall, ChatResponse, TokenUsage;
import 'package:dbmaster/models/database_models.dart'
    show AiMessage, DatabaseType, DbColumn, DbIndex, ForeignKey;
import 'package:dbmaster/models/query_optimizer/execution_plan.dart'
    show PerformanceReport;
import 'package:dbmaster/organisms/ai_workbench/agents/agent_confirm_card.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_plan_card.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_trajectory_card.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_snapshot_table.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentGate, AgentRunContext, GateDecision, GateDecisionKind;
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show ReadImpactAnalysis;
import 'package:dbmaster/services/ai/agent/agent_plan.dart'
    show
        AgentActionPlan,
        AgentPlanStatus,
        AgentPlanStep,
        AgentPlanStepKind,
        AgentPlanStepStatus,
        AgentRollbackSource,
        AgentRowsEstimateSource;
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart'
    show AgentChatConfig, AgentLoopRunner, AgentRunStatus;
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart'
    show AgentPermissionLedger;
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolSpec;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart'
    show AgentDbAccess, AgentToolExecutor, GateCallbacks;
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort, GateCardResult;
import 'package:dbmaster/services/ai/ai_session_manager.dart'
    show AiSessionManager;

// ── 测试脚手架 ───────────────────────────────────────────────────────────────

Widget _wrap(Widget child, {double width = 720, double viewportHeight = 0}) {
  Widget boxed = Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: child,
    ),
  );
  if (viewportHeight > 0) {
    boxed = SizedBox(
      height: viewportHeight,
      child: SingleChildScrollView(child: boxed),
    );
  }
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.light, useMaterial3: true),
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: boxed),
  );
}

/// 断言主焦点当前落在 [key] 子树内（T12 测试同款 helper）。
bool primaryFocusWithin(Key key) {
  final BuildContext? ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  var within = false;
  ctx.visitAncestorElements((Element el) {
    if (el.widget.key == key) {
      within = true;
      return false;
    }
    return true;
  });
  return within;
}

// ── 消息 fixtures（§5.2 结构镜像）───────────────────────────────────────────

int _seq = 0;

AiMessage mkPlain({bool user = false, String content = 'plain'}) => AiMessage(
  id: 'plain_${_seq++}',
  isUser: user,
  content: content,
  timestamp: DateTime.now(),
  type: AiMessageType.chat,
  status: AiMessageStatus.sent,
);

AiMessage mkAnchor(String runId, {int maxSteps = 25}) => AiMessage(
  id: 'agent_anchor_$runId',
  isUser: false,
  content: '',
  timestamp: DateTime.now(),
  type: AiMessageType.toolResult,
  toolName: 'agent_run',
  toolResultSummary: 'Agent run started (step limit $maxSteps)',
  toolResultData: <String, dynamic>{
    'agent': <String, dynamic>{
      'kind': 'agent_run',
      'runId': runId,
      'goal': 'goal',
      'contextSnapshot': <String, dynamic>{
        'conn': 'conn',
        'db': 'db',
        'readOnly': false,
        'maxSteps': maxSteps,
      },
    },
  },
);

/// 步消息对（toolCall + toolResult；agent_step 载荷在 result）。
List<AiMessage> mkStep(
  String runId,
  int stepNo,
  String tool, {
  Map<String, dynamic> args = const <String, dynamic>{},
  String decision = 'allowed',
  String? gateLevel,
  String summary = 'ok',
  int? rowCount,
  List<String> columns = const <String>[],
  List<Map<String, dynamic>> snapshotRows = const <Map<String, dynamic>>[],
  int durationMs = 128,
  String? errorCode,
  String? errorMessage,
}) {
  final DateTime now = DateTime.now();
  return <AiMessage>[
    AiMessage(
      id: 'agent_tc_${runId}_$stepNo',
      isUser: false,
      content: '',
      timestamp: now,
      type: AiMessageType.toolCall,
      toolName: tool,
      toolArguments: args,
    ),
    AiMessage(
      id: 'agent_tr_${runId}_$stepNo',
      isUser: false,
      content: summary,
      timestamp: now,
      type: AiMessageType.toolResult,
      toolName: tool,
      toolResultSummary: summary,
      toolResultData: <String, dynamic>{
        'agent': <String, dynamic>{
          'kind': 'agent_step',
          'runId': runId,
          'stepNo': stepNo,
          'tool': tool,
          'gateLevel': ?gateLevel,
          'gateDecision': decision,
          'summary': summary,
          if (rowCount != null)
            'resultRef': <String, dynamic>{
              'rowCount': rowCount,
              'columns': columns,
              'snapshotRows': snapshotRows,
            },
          'durationMs': durationMs,
          if (errorCode != null)
            'error': <String, dynamic>{
              'code': errorCode,
              'message': errorMessage,
            },
        },
      },
    ),
  ];
}

const Map<String, dynamic> kImpact = <String, dynamic>{
  'estimatedRows': 800000,
  'fullScan': true,
  'scannedTables': <String>['orders'],
  'indexSummary': null,
  'analysisUnavailable': false,
};

AiMessage mkGate(
  String runId,
  int stepNo, {
  String? outcome,
  String sql = 'SELECT * FROM orders',
}) => AiMessage(
  id: 'agent_gc_${runId}_$stepNo',
  isUser: false,
  content: '',
  timestamp: DateTime.now(),
  type: AiMessageType.toolResult,
  toolName: 'agent_confirm',
  status: AiMessageStatus.completed,
  toolResultSummary: 'Read confirmation awaiting decision',
  toolResultData: <String, dynamic>{
    'agent': <String, dynamic>{
      'kind': 'agent_confirm',
      'runId': runId,
      'stepNo': stepNo,
      'sql': sql,
      'impact': kImpact,
      'outcome': ?outcome,
    },
  },
);

AiMessage mkTerminal(
  String runId,
  String status, {
  int steps = 3,
  int? tokens,
  String summaryText = 'Completed · 3 step(s)',
  String? content,
}) => AiMessage(
  id: 'agent_end_$runId',
  isUser: false,
  // M1 回复区判定基准：默认 content = summaryText（真实 runner 的非
  // completed 终局即 content == summaryText；completed 且带模型全文的用例
  // 显式传 content）——既有结构/几何/键盘用例不被「模型回复」区干扰。
  content: content ?? summaryText,
  timestamp: DateTime.now(),
  type: AiMessageType.chat,
  status: AiMessageStatus.completed,
  toolResultSummary: summaryText,
  toolResultData: <String, dynamic>{
    'agent': <String, dynamic>{
      'kind': 'agent_run_end',
      'runId': runId,
      'status': status,
      'steps': steps,
      'tokens': ?tokens,
      'summaryText': summaryText,
    },
  },
);

/// 经典（M1）toolCall/toolResult 对——不带 agent 载荷。
List<AiMessage> mkClassicPair(String name) => <AiMessage>[
  AiMessage(
    id: 'classic_c_${_seq++}',
    isUser: false,
    content: '',
    timestamp: DateTime.now(),
    type: AiMessageType.toolCall,
    toolName: name,
  ),
  AiMessage(
    id: 'classic_r_${_seq++}',
    isUser: false,
    content: 'done',
    timestamp: DateTime.now(),
    type: AiMessageType.toolResult,
    toolName: name,
    toolResultData: <String, dynamic>{
      'workbench': <String, dynamic>{'kind': 'sql_card'},
    },
  ),
];

/// 三步终局 run 的标准 fixture。
List<AiMessage> mkCompletedRun(String runId) => <AiMessage>[
  mkAnchor(runId),
  ...mkStep(runId, 1, 'list_tables', summary: 'listed 12 tables'),
  ...mkStep(
    runId,
    2,
    'describe_table',
    args: <String, dynamic>{'table': 'orders'},
  ),
  ...mkStep(
    runId,
    3,
    'execute_readonly_sql',
    args: <String, dynamic>{'sql': 'SELECT 1'},
    rowCount: 5,
    columns: <String>['1'],
    snapshotRows: <Map<String, dynamic>>[
      <String, dynamic>{'1': 1},
    ],
  ),
  mkTerminal(runId, 'completed', steps: 3),
];

// ── 实时态测试台（真实 AgentLoopRunner，沿 T11 形态）───────────────────────

class _ChatScript {
  final List<Future<ChatResponse> Function()> queue =
      <Future<ChatResponse> Function()>[];

  Future<ChatResponse> call({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout = const Duration(seconds: 60),
    List<Map<String, dynamic>>? tools,
  }) {
    if (queue.isEmpty) {
      throw StateError('AgentTrajectoryCardTest: unexpected chat call');
    }
    return queue.removeAt(0)();
  }

  void respond(ChatResponse resp) => queue.add(() async => resp);

  void hold(Completer<ChatResponse> c) => queue.add(() => c.future);
}

AiToolCall _toolCall(String name, Map<String, dynamic> args) => AiToolCall(
  id: 'call-${name.hashCode.abs()}',
  type: 'function',
  functionName: name,
  functionArguments: jsonEncode(args),
);

ChatResponse _callResp(AiToolCall call, {TokenUsage? usage}) =>
    ChatResponse(content: '', toolCalls: <AiToolCall>[call], usage: usage);

ChatResponse _textResp(String content, {TokenUsage? usage}) => ChatResponse(
  content: content,
  toolCalls: const <AiToolCall>[],
  usage: usage,
);

class _ScriptedGate extends AgentGate {
  _ScriptedGate()
    : super(createAnalysis: (_) => throw StateError('scripted never analyzes'));

  final List<Future<GateDecision> Function()> decisions =
      <Future<GateDecision> Function()>[];

  @override
  Future<GateDecision> evaluate({
    required AgentToolSpec spec,
    required Map<String, dynamic> args,
    required AgentRunContext runCtx,
    required AgentPermissionLedger ledger,
  }) {
    if (decisions.isEmpty) {
      return Future.value(
        const GateDecision(
          kind: GateDecisionKind.allow,
          level: AgentGateLevel.l0,
        ),
      );
    }
    return decisions.removeAt(0)();
  }

  void allow() => decisions.add(
    () async => const GateDecision(
      kind: GateDecisionKind.allow,
      level: AgentGateLevel.l0,
    ),
  );

  void confirmL05() => decisions.add(
    () async => const GateDecision(
      kind: GateDecisionKind.confirm,
      level: AgentGateLevel.l05,
      impact: ReadImpactAnalysis(
        estimatedRows: 800000,
        fullScan: true,
        analysisUnavailable: false,
      ),
    ),
  );
}

class _DbSpy {
  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
  }) async => <Map<String, dynamic>>[
    <String, dynamic>{'id': 1},
  ];
}

class _Harness {
  _Harness()
    : chat = _ChatScript(),
      gate = _ScriptedGate(),
      db = _DbSpy(),
      sessionManager = AiSessionManager() {
    sessionManager.createSession();
    executor = AgentToolExecutor(
      gate: gate,
      db: AgentDbAccess(
        getTables: (String? connectionId, String? databaseName) async =>
            <String>['users', 'orders'],
        getTableColumns:
            (String t, {String? connectionId, String? databaseName}) async =>
                <DbColumn>[],
        getTableIndexes:
            (String t, {String? connectionId, String? databaseName}) async =>
                <DbIndex>[],
        getForeignKeys:
            (String t, {String? connectionId, String? databaseName}) async =>
                <ForeignKey>[],
        getCreateTableSql:
            (String t, {String? connectionId, String? databaseName}) async =>
                'CREATE TABLE t (...)',
        getExplainPlan: (String sql, {String? connectionId}) async =>
            <Map<String, dynamic>>[],
        executeQuery: db.executeQuery,
      ),
      audit:
          ({
            required String connectionId,
            String? connectionName,
            String? databaseName,
            required String runId,
            required int step,
            required String tool,
            String? sql,
            AgentGateLevel? gateLevel,
            Object? gateDecision,
            String? planId,
            required bool success,
            String? errorMessage,
          }) async {},
      recordToolCall: (_) {},
      recordL05Event: (_) {},
    );
    runner = AgentLoopRunner(
      executor: executor,
      sessionManager: sessionManager,
      resolveRunContext: (String runId) => AgentRunContext(
        runId: runId,
        connectionId: 'conn-1',
        connectionName: '测试连接',
        databaseName: 'db1',
        dbType: DatabaseType.mysql,
        readOnly: false,
      ),
      resolveChatConfig: () => const AgentChatConfig(
        provider: 'DeepSeek',
        model: 'deepseek-chat',
        apiKey: 'test-key',
      ),
      chat: chat.call,
      resolveMaxSteps: () async => 25,
    );
  }

  final _ChatScript chat;
  final _ScriptedGate gate;
  final _DbSpy db;
  final AiSessionManager sessionManager;
  late final AgentToolExecutor executor;
  late final AgentLoopRunner runner;

  Future<void> start({GateCallbacks? gates}) =>
      runner.start(userMessage: 'go', uiPort: _planUiPort, gates: gates);

  /// 分组函数产出本 run 的组消息（T14 itemBuilder 同款消费路径）。
  List<AiMessage> get runMessages {
    final List<AgentTrajectorySegment> segments = agentTrajectoryGrouping(
      sessionManager.currentMessages,
    );
    for (final AgentTrajectorySegment s in segments) {
      if (s.isRun) return s.run!.messages;
    }
    return const <AiMessage>[];
  }
}

/// uiPort 缺省 fake（T28：start 必填——本文件用例不触界面工具）。
class _NoopUiPort implements AgentUiPort {
  const _NoopUiPort();

  @override
  Future<AgentUiOutcome> openResultGrid(AgentResultRef ref, String? title) =>
      Future.value(const AgentUiOutcome.failure('noop'));

  @override
  Future<AgentUiOutcome> showTableStructure(String table) =>
      Future.value(const AgentUiOutcome.failure('noop'));

  @override
  Future<AgentUiOutcome> openSqlEditor(String sql) =>
      Future.value(const AgentUiOutcome.failure('noop'));

  @override
  Future<AgentUiOutcome> renderChart(AgentResultRef ref, String? chartKind) =>
      Future.value(const AgentUiOutcome.failure('noop'));

  @override
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label) =>
      Future.value(const AgentUiOutcome.failure('noop'));

  @override
  Future<AgentUiOutcome> suggestOpenInClassic(String sql) =>
      Future.value(const AgentUiOutcome.failure('noop'));

  @override
  Future<AgentUiOutcome> suggestFocusSidebar({
    String? database,
    String? table,
  }) => Future.value(const AgentUiOutcome.failure('noop'));

  @override
  Future<AgentUiOutcome> openOptimization(
    PerformanceReport report,
    String sql,
  ) => Future.value(const AgentUiOutcome.failure('noop'));
}

const _NoopUiPort _planUiPort = _NoopUiPort();

GateCallbacks _blockGates(Completer<GateCardResult> completer) => GateCallbacks(
  onL05Confirm: (ReadImpactAnalysis impact, String sql) => completer.future,
  onPlanApproval: (_) async => GateCardResult.rejected,
);

/// 卡上 spinner 在 running 态无限动画——pumpAndSettle 会挂起，用固定泵链
/// 冲刷 runner 微任务（fake 依赖即时完成）。
Future<void> _flushRunner(WidgetTester tester, {int rounds = 8}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

/// 测试尾冲刷 AiSessionManager 的 500ms 持久化防抖 Timer（真实 runner 落账
/// 触发；widget 测试 teardown 的 pending-timer 不变量要求清空）。
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ── 分组纯函数 ────────────────────────────────────────────────────────────

  group('agentTrajectoryGrouping', () {
    test('多 run 各一组；组序 = 锚点首次出现序；组内含锚点/步对/门卡/终局', () {
      final List<AiMessage> messages = <AiMessage>[
        mkPlain(user: true, content: 'q1'),
        mkAnchor('run_a'),
        ...mkStep('run_a', 1, 'list_tables'),
        mkGate('run_a', 2, outcome: 'approved'),
        ...mkStep('run_a', 2, 'execute_readonly_sql', decision: 'confirmed'),
        mkTerminal('run_a', 'completed', steps: 2),
        mkPlain(content: 'between'),
        mkAnchor('run_b'),
        ...mkStep('run_b', 1, 'list_tables'),
        mkTerminal('run_b', 'stoppedByUser', steps: 1),
        mkPlain(content: 'after'),
      ];
      final List<AgentTrajectorySegment> segments = agentTrajectoryGrouping(
        messages,
      );
      expect(segments, hasLength(5));
      expect(segments[0].message!.content, 'q1');
      expect(segments[1].isRun, isTrue);
      expect(segments[1].run!.runId, 'run_a');
      expect(segments[1].run!.messages, hasLength(7)); // 锚点+对1+门+对2+终局
      expect(segments[1].run!.terminal, isNotNull);
      expect(segments[1].run!.anchor.id, 'agent_anchor_run_a');
      expect(segments[2].message!.content, 'between');
      expect(segments[3].isRun, isTrue);
      expect(segments[3].run!.runId, 'run_b');
      expect(segments[3].run!.terminal, isNotNull);
      expect(segments[4].message!.content, 'after');
    });

    test('无终局 = 中断态组（terminal null）', () {
      final List<AiMessage> messages = <AiMessage>[
        mkAnchor('run_x'),
        ...mkStep('run_x', 1, 'list_tables'),
      ];
      final List<AgentTrajectorySegment> segments = agentTrajectoryGrouping(
        messages,
      );
      expect(segments, hasLength(1));
      expect(segments[0].run!.terminal, isNull);
    });

    test('平铺区间边界：agent 前后的普通消息按时间序平铺', () {
      final List<AiMessage> messages = <AiMessage>[
        mkPlain(content: 'before'),
        mkAnchor('run_a'),
        mkTerminal('run_a', 'completed', steps: 0),
        mkPlain(content: 'after'),
      ];
      final List<AgentTrajectorySegment> segments = agentTrajectoryGrouping(
        messages,
      );
      expect(
        segments
            .map(
              (AgentTrajectorySegment s) =>
                  s.isRun ? 'run:${s.run!.runId}' : 'msg:${s.message!.content}',
            )
            .toList(),
        equals(<String>['msg:before', 'run:run_a', 'msg:after']),
      );
    });

    test('步消息对吸收：agent toolCall 入组；经典 toolCall 不受影响', () {
      final List<AiMessage> classic = mkClassicPair('query');
      final List<AiMessage> messages = <AiMessage>[
        ...classic,
        mkAnchor('run_a'),
        ...mkStep('run_a', 1, 'list_tables'),
        mkTerminal('run_a', 'completed', steps: 1),
      ];
      final List<AgentTrajectorySegment> segments = agentTrajectoryGrouping(
        messages,
      );
      expect(segments, hasLength(3));
      // 经典 toolCall 与 toolResult 各自平铺（call 未被吞、result 不进组）。
      expect(segments[0].message!.id, classic[0].id);
      expect(segments[1].message!.id, classic[1].id);
      expect(segments[2].run!.messages, hasLength(4)); // 锚点+对+终局
      expect(
        segments[2].run!.messages.map((AiMessage m) => m.type).toSet(),
        containsAll(<AiMessageType>{
          AiMessageType.toolCall,
          AiMessageType.toolResult,
        }),
      );
    });

    test('excludeFromRun 参数化判断点预留：命中 kind 平铺，默认不排除（FC-6）', () {
      final AiMessage suggest = AiMessage(
        id: 'agent_sg_1',
        isUser: false,
        content: '',
        timestamp: DateTime.now(),
        type: AiMessageType.toolResult,
        toolResultData: <String, dynamic>{
          'agent': <String, dynamic>{'kind': 'agent_suggest', 'runId': 'run_a'},
        },
      );
      final List<AiMessage> messages = <AiMessage>[
        mkAnchor('run_a'),
        suggest,
        mkTerminal('run_a', 'completed', steps: 0),
      ];
      // 默认（A1）：不排除任何 kind——suggest 折叠进组。
      final List<AgentTrajectorySegment> byDefault = agentTrajectoryGrouping(
        messages,
      );
      expect(byDefault, hasLength(1));
      expect(byDefault[0].run!.messages, hasLength(3));

      // A2 T26 接线形态：排除判断命中 → 按位置平铺为顶级消息（锚点/终局
      // 仍收进同一 run 组——run 区间是一张卡）。
      final List<AgentTrajectorySegment> excluded = agentTrajectoryGrouping(
        messages,
        excludeFromRun: (String kind) => kind == 'agent_suggest',
      );
      expect(excluded, hasLength(2));
      expect(excluded[0].isRun, isTrue);
      expect(excluded[0].run!.messages, hasLength(2)); // 锚点+终局
      expect(excluded[1].message!.id, 'agent_sg_1');
    });
  });

  // ── §1.8-1/2：折叠态懒构建守护 + 几何 ────────────────────────────────────

  testWidgets('§1.8-1 折叠态（终局默认）只构建 header + 汇报行（NF1.1）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AgentTrajectoryCard(runMessages: mkCompletedRun('run_a'))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(AgentTrajectoryCard.headerKey), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.reportRowKey), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.stepsScrollKey), findsNothing);
    for (int i = 1; i <= 3; i++) {
      expect(find.byKey(AgentTrajectoryCard.stepRowKey(i)), findsNothing);
      expect(find.byKey(AgentTrajectoryCard.stepDetailKey(i)), findsNothing);
    }
    expect(find.byIcon(LucideIcons.chevronDown), findsOneWidget);
    // 终局折叠 = 60 ± 1。
    expect(
      tester.getSize(find.byType(AgentTrajectoryCard)).height,
      moreOrLessEquals(60, epsilon: 1),
    );
  });

  testWidgets('§1.8-2 展开态 3 步 = 34 + 24 + 3×24 + 2', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AgentTrajectoryCard(runMessages: mkCompletedRun('run_a'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    for (int i = 1; i <= 3; i++) {
      expect(find.byKey(AgentTrajectoryCard.stepRowKey(i)), findsOneWidget);
      expect(find.byKey(AgentTrajectoryCard.stepDetailKey(i)), findsNothing);
    }
    expect(
      tester.getSize(find.byType(AgentTrajectoryCard)).height,
      moreOrLessEquals(34 + 24 + 3 * 24 + 2, epsilon: 1),
    );
  });

  // ── §1.8-4：10 态 chip + token 三档 + 「—」───────────────────────────────

  testWidgets('10 态：终局态 chip 文案/图标逐态键断言', (WidgetTester tester) async {
    final List<(String, String, IconData, int?)> cases =
        <(String, String, IconData, int?)>[
          ('completed', 'Completed', LucideIcons.circleCheck, 1200),
          ('stoppedByUser', 'Stopped by user', LucideIcons.square, 999),
          ('stoppedByLimit', 'Step limit', LucideIcons.gauge, 1200000),
          ('stoppedByFailures', '3 failures', LucideIcons.triangleAlert, null),
          ('failed', 'Run failed', LucideIcons.circleX, null),
          ('weird-status', 'Unknown', LucideIcons.helpCircle, null),
        ];
    for (final (String status, String label, IconData icon, int? tokens)
        in cases) {
      await tester.pumpWidget(
        _wrap(
          AgentTrajectoryCard(
            runMessages: <AiMessage>[
              mkAnchor('run_s'),
              ...mkStep('run_s', 1, 'list_tables'),
              ...mkStep('run_s', 2, 'list_tables'),
              ...mkStep('run_s', 3, 'list_tables'),
              mkTerminal('run_s', status, steps: 3, tokens: tokens),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(label), findsWidgets, reason: status);
      expect(
        find.descendant(
          of: find.byKey(AgentTrajectoryCard.chipIconKey),
          matching: find.byIcon(icon),
        ),
        findsOneWidget,
        reason: status,
      );
    }
  });

  testWidgets('stoppedByContext 第五终止源：新显示态接线（非 unknown 降级）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[
            mkAnchor('run_ctx'),
            ...mkStep('run_ctx', 1, 'list_tables'),
            ...mkStep('run_ctx', 2, 'describe_table'),
            mkTerminal(
              'run_ctx',
              'stoppedByContext',
              steps: 2,
              summaryText: 'Context missing, run stopped',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // chip 标签 = l10n 新键（agentStoppedByContext），非 Unknown 兜底。
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.statusChipKey),
        matching: find.text('Stopped: database context required'),
      ),
      findsOneWidget,
    );
    expect(find.text('Unknown'), findsNothing);
    // 图标映射不抛 + chip 图标 = unplug（断开族：上下文未接入）。
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.chipIconKey),
        matching: find.byIcon(LucideIcons.unplug),
      ),
      findsOneWidget,
    );
    // 汇报行图标与 chip 同源（同 stoppedByLimit 模式），文案走 summaryText。
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.reportRowKey),
        matching: find.byIcon(LucideIcons.unplug),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.reportRowKey),
        matching: find.text('Context missing, run stopped'),
      ),
      findsOneWidget,
    );
    // 终局计数语义与 stoppedByLimit 同构：n/max（锚点 contextSnapshot 恢复
    // maxSteps = mkAnchor 默认 25），非中断态 stepsOnly。stepsCounterKey 挂在
    // Text 本体（非父容器），沿用 interrupted 用例的直接 find.text 断言。
    expect(find.text('2/25'), findsOneWidget);
  });

  testWidgets('10 态：interrupted 派生态只显 n 步 + token「—」+ 默认折叠', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[
            mkAnchor('run_i'),
            ...mkStep('run_i', 1, 'list_tables'),
            ...mkStep('run_i', 2, 'describe_table'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Interrupted'), findsWidgets);
    expect(find.text('Steps: 2'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.stepsScrollKey), findsNothing);
    expect(
      tester.getSize(find.byType(AgentTrajectoryCard)).height,
      moreOrLessEquals(60, epsilon: 1),
    );
  });

  testWidgets('token 紧凑格式：<1000 原值 / ≥1000 一位小数 k / ≥1M M', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[
            mkAnchor('run_t'),
            mkTerminal('run_t', 'completed', steps: 1, tokens: 999),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('999 tok'), findsOneWidget);
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[
            mkAnchor('run_t'),
            mkTerminal('run_t', 'completed', steps: 1, tokens: 18432),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('18.4k tok'), findsOneWidget);
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[
            mkAnchor('run_t'),
            mkTerminal('run_t', 'completed', steps: 1, tokens: 1200000),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1.2M tok'), findsOneWidget);
    expect(agentTrajectoryCompactTokens(0), '0');
    expect(agentTrajectoryCompactTokens(1000), '1.0k');
    expect(agentTrajectoryCompactTokens(999999), '1000.0k');
  });

  // ── §1.8-7：摘要行标记例外制 ──────────────────────────────────────────────

  testWidgets('§1.8-7 成功步无标记；门拦 shieldX；失败 circleAlert + 错误码', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[
            mkAnchor('run_m'),
            ...mkStep('run_m', 1, 'list_tables', summary: 'listed 12 tables'),
            ...mkStep(
              'run_m',
              2,
              'execute_readonly_sql',
              decision: 'blocked',
              gateLevel: 'l05',
              errorCode: 'GATE_REJECTED',
              errorMessage: 'user rejected',
              summary: 'blocked by gate',
            ),
            ...mkStep(
              'run_m',
              3,
              'execute_readonly_sql',
              errorCode: 'EXECUTION_FAILED',
              errorMessage: 'boom',
              summary: 'failed',
            ),
            mkTerminal('run_m', 'completed', steps: 3),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    // 成功步：无任何标记图标。
    for (final IconData marker in <IconData>[
      LucideIcons.shieldCheck,
      LucideIcons.shieldX,
      LucideIcons.ban,
      LucideIcons.circleAlert,
    ]) {
      expect(
        find.descendant(
          of: find.byKey(AgentTrajectoryCard.stepRowKey(1)),
          matching: find.byIcon(marker),
        ),
        findsNothing,
      );
    }
    // 门拦步：shieldX + Blocked 文案。
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.stepRowKey(2)),
        matching: find.byIcon(LucideIcons.shieldX),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.stepRowKey(2)),
        matching: find.text('Blocked'),
      ),
      findsOneWidget,
    );
    // 失败步：circleAlert + 错误码文案。
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.stepRowKey(3)),
        matching: find.byIcon(LucideIcons.circleAlert),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.stepRowKey(3)),
        matching: find.text('EXECUTION_FAILED'),
      ),
      findsOneWidget,
    );
  });

  // ── §1.4/§1.8-9：步详情懒构建 + 在舞台打开条件 + 快照复用 ────────────────

  testWidgets('§1.8-9 rowCount > 10 存在「在舞台打开」；≤ 10 findsNothing', (
    WidgetTester tester,
  ) async {
    final List<Map<String, dynamic>> snapshot = <Map<String, dynamic>>[
      for (int i = 0; i < 10; i++) <String, dynamic>{'id': i, 'name': 'n$i'},
    ];
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_d'),
      ...mkStep(
        'run_d',
        1,
        'execute_readonly_sql',
        args: <String, dynamic>{'sql': 'SELECT * FROM orders'},
        rowCount: 50,
        columns: <String>['id', 'name'],
        snapshotRows: snapshot,
      ),
      ...mkStep(
        'run_d',
        2,
        'execute_readonly_sql',
        args: <String, dynamic>{'sql': 'SELECT 1'},
        rowCount: 5,
        columns: <String>['1'],
        snapshotRows: <Map<String, dynamic>>[
          <String, dynamic>{'1': 1},
        ],
      ),
      mkTerminal('run_d', 'completed', steps: 2),
    ];
    final List<(String, int)> stageCalls = <(String, int)>[];
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: messages,
          onOpenResultInStage: (String runId, int stepNo) =>
              stageCalls.add((runId, stepNo)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    // 步 1：详情懒构建（点击前 findsNothing）→ 点击后参数/SQL/结果/快照。
    expect(find.byKey(AgentTrajectoryCard.stepDetailKey(1)), findsNothing);
    await tester.tap(find.byKey(AgentTrajectoryCard.stepRowKey(1)));
    await tester.pumpAndSettle();
    expect(find.byKey(AgentTrajectoryCard.stepDetailKey(1)), findsOneWidget);
    expect(find.byType(SelectableText), findsWidgets);
    expect(find.byType(ResultSnapshotTable), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.openInStageKey(1)), findsOneWidget);
    expect(find.text('Open in Stage'), findsOneWidget);
    expect(find.text('Showing first 10 of 50 rows'), findsOneWidget);
    await tester.tap(find.byKey(AgentTrajectoryCard.openInStageKey(1)));
    await tester.pumpAndSettle();
    expect(stageCalls, equals(<(String, int)>[('run_d', 1)]));
    // 步 2：rowCount ≤ 快照上限 → 无「在舞台打开」。
    await tester.tap(find.byKey(AgentTrajectoryCard.stepRowKey(2)));
    await tester.pumpAndSettle();
    expect(find.byKey(AgentTrajectoryCard.openInStageKey(2)), findsNothing);
  });

  // ── §1.8-5：25 步单滚动区 ─────────────────────────────────────────────────

  testWidgets('§1.8-5 25 步：卡体 ≤ 362、单 Scrollable、可滚动', (
    WidgetTester tester,
  ) async {
    final List<AiMessage> messages = <AiMessage>[mkAnchor('run_25')];
    for (int i = 1; i <= 25; i++) {
      messages.addAll(mkStep('run_25', i, 'list_tables', summary: 's$i'));
    }
    messages.add(mkTerminal('run_25', 'completed', steps: 25));
    await tester.pumpWidget(_wrap(AgentTrajectoryCard(runMessages: messages)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(find.byType(Scrollable), findsOneWidget);
    final double bodyHeight = tester
        .getSize(find.byKey(AgentTrajectoryCard.stepsScrollKey))
        .height;
    expect(bodyHeight, lessThanOrEqualTo(362));
    expect(bodyHeight, moreOrLessEquals(360, epsilon: 1));
    expect(find.byKey(AgentTrajectoryCard.stepRowKey(1)), findsOneWidget);
    await tester.drag(
      find.byKey(AgentTrajectoryCard.stepsScrollKey),
      const Offset(0, -200),
    );
    await tester.pump();
    final ScrollableState state = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    expect(state.position.pixels, greaterThan(0));
  });

  // ── §1.8-8：键盘 ─────────────────────────────────────────────────────────

  testWidgets('§1.8-8 Tab 进步列表、↓ roving、Enter 展开、Esc 回卡头', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AgentTrajectoryCard(runMessages: mkCompletedRun('run_k'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(primaryFocusWithin(AgentTrajectoryCard.headerKey), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      primaryFocusWithin(AgentTrajectoryCard.stepRowKey(1)),
      isTrue,
      reason: 'Tab 从卡头进入步列表首行',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(primaryFocusWithin(AgentTrajectoryCard.stepRowKey(2)), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.byKey(AgentTrajectoryCard.stepDetailKey(2)), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(primaryFocusWithin(AgentTrajectoryCard.headerKey), isTrue);
  });

  // ── §1.8-3：实时计数 + 消息 id 不变 ──────────────────────────────────────

  testWidgets('§1.8-3 running 实时计数刷新且消息对象 id 不变（stale 消息直证）', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    final Completer<ChatResponse> round1 = Completer<ChatResponse>();
    final Completer<ChatResponse> round2 = Completer<ChatResponse>();
    h.gate.allow();
    h.chat.hold(round1);
    h.chat.hold(round2);
    unawaited(h.start(gates: _blockGates(Completer<GateCardResult>())));
    await tester.pumpAndSettle();
    // 步落账前抓 stale 消息（组内仅锚点；用户消息是组外平铺段）。
    final List<AiMessage> staleMessages = h.runMessages;
    expect(staleMessages, hasLength(1));
    final AiMessage anchorBefore = staleMessages[0];
    round1.complete(
      _callResp(
        _toolCall('list_tables', <String, dynamic>{}),
        usage: const TokenUsage(totalTokens: 1200),
      ),
    );
    await tester.pumpAndSettle(); // 步 1 落账；chat#2 挂起 → running
    expect(h.runner.status, AgentRunStatus.running);
    // 传入 stale 消息列表（无终局、无步消息）——计数只能来自 runner。
    await tester.pumpWidget(
      _wrap(AgentTrajectoryCard(runMessages: staleMessages, runner: h.runner)),
    );
    await tester.pump();
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('1/25'), findsOneWidget);
    expect(find.text('1.2k tok'), findsOneWidget);
    // 消息对象 id 不变（卡不重写消息 JSON；runner 只追加不改写）。
    expect(identical(anchorBefore, h.runMessages[0]), isTrue);
    // 宿主重建后步列表出现。
    await tester.pumpWidget(
      _wrap(AgentTrajectoryCard(runMessages: h.runMessages, runner: h.runner)),
    );
    await tester.pump();
    expect(find.byKey(AgentTrajectoryCard.stepRowKey(1)), findsOneWidget);
    await _drainTimers(tester);
  });

  // ── §1.6/§1.8-6：awaitingUser 强制展开 + 未决嵌块宿主 ────────────────────

  testWidgets('§1.8-6 awaitingUser：强制展开 + chevron 禁用 + 未决嵌块可见', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    final Completer<GateCardResult> decision = Completer<GateCardResult>();
    final Completer<ChatResponse> round2 = Completer<ChatResponse>();
    final Completer<ChatResponse> round3 = Completer<ChatResponse>();
    h.gate.allow();
    h.chat.respond(
      _callResp(
        _toolCall('list_tables', <String, dynamic>{}),
        usage: const TokenUsage(totalTokens: 4200),
      ),
    );
    h.chat.hold(round2);
    unawaited(h.start(gates: _blockGates(decision)));
    await tester.pumpAndSettle();
    expect(h.runner.status, AgentRunStatus.running);
    // 轮 2：execute_readonly_sql → confirm(l05) → awaitingUser + 门卡消息。
    h.gate.confirmL05();
    round2.complete(
      _callResp(
        _toolCall('execute_readonly_sql', <String, dynamic>{
          'sql': 'SELECT * FROM orders',
        }),
      ),
    );
    h.chat.hold(round3);
    await tester.pumpAndSettle();
    expect(h.runner.status, AgentRunStatus.awaitingUser);
    final List<(String, int, GateCardResult)> decisions =
        <(String, int, GateCardResult)>[];
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: h.runMessages,
          runner: h.runner,
          onGateDecision: (String runId, int stepNo, GateCardResult d) =>
              decisions.add((runId, stepNo, d)),
        ),
        viewportHeight: 600,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // 强制展开：步列表与未决嵌块可见，chevron 朝上。
    expect(find.byKey(AgentTrajectoryCard.stepsScrollKey), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.stepRowKey(1)), findsOneWidget);
    expect(find.byType(AgentConfirmCard), findsOneWidget);
    expect(find.byIcon(LucideIcons.chevronUp), findsOneWidget);
    // 默认 builder 重建确认卡（impact 自载荷恢复）。
    expect(find.text('800,000 rows'), findsOneWidget);
    // chevron 禁用：点卡头不折叠（onTap 空转）。
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(AgentConfirmCard), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.stepsScrollKey), findsOneWidget);
    // 未决嵌块在视口内（几何可见率）。
    final Rect cardRect = tester.getRect(find.byType(AgentTrajectoryCard));
    final Rect gateRect = tester.getRect(find.byType(AgentConfirmCard));
    expect(gateRect.top, greaterThanOrEqualTo(cardRect.top));
    expect(gateRect.bottom, lessThanOrEqualTo(600));
    // 决策回调注入形态：allow → (runId, stepNo=2, approved)。
    await tester.tap(find.byKey(AgentConfirmCard.allowButtonKey));
    await tester.pump();
    expect(decisions, hasLength(1));
    expect(decisions[0].$1, h.runner.activeRunId);
    expect(decisions[0].$2, 2);
    expect(decisions[0].$3, GateCardResult.approved);
    // 决策落定（shell Completer）→ running（步 2 执行落账，chat#3 挂起）。
    decision.complete(GateCardResult.approved);
    await _flushRunner(tester);
    expect(h.runner.status, AgentRunStatus.running);
    await _drainTimers(tester);
  });

  testWidgets('§1.6 决策后：真实 runner 回填 outcome → 结论行 + 步行落位', (
    WidgetTester tester,
  ) async {
    final _Harness h = _Harness();
    final Completer<GateCardResult> decision = Completer<GateCardResult>();
    final Completer<ChatResponse> round2 = Completer<ChatResponse>();
    h.gate.confirmL05();
    h.chat.respond(
      _callResp(
        _toolCall('execute_readonly_sql', <String, dynamic>{
          'sql': 'SELECT * FROM orders',
        }),
      ),
    );
    h.chat.hold(round2);
    unawaited(h.start(gates: _blockGates(decision)));
    await tester.pumpAndSettle();
    expect(h.runner.status, AgentRunStatus.awaitingUser);
    await tester.pumpWidget(
      _wrap(AgentTrajectoryCard(runMessages: h.runMessages, runner: h.runner)),
    );
    await tester.pump();
    expect(find.byType(AgentConfirmCard), findsOneWidget);
    // 决策 approved → 步 1 执行落账 → runner 回填 outcome → 终局 completed。
    decision.complete(GateCardResult.approved);
    round2.complete(_textResp('done'));
    await _flushRunner(tester);
    expect(h.runner.status, AgentRunStatus.completed);
    await tester.pumpWidget(
      _wrap(AgentTrajectoryCard(runMessages: h.runMessages, runner: h.runner)),
    );
    await tester.pumpAndSettle();
    // 步 1 落位；卡仍展开（State 跨宿主重建存活——首泵时 run 进行中默认
    // 展开）；已决门卡嵌块在其详情位（懒构建：详情展开才渲染结论行）。
    expect(find.byKey(AgentTrajectoryCard.stepRowKey(1)), findsOneWidget);
    await tester.tap(find.byKey(AgentTrajectoryCard.stepRowKey(1)));
    await tester.pumpAndSettle();
    // 嵌块收为结论行（未决动作 findsNothing）。
    expect(find.byKey(AgentConfirmCard.conclusionKey), findsOneWidget);
    expect(find.text('Allowed (this time)'), findsOneWidget);
    expect(find.byKey(AgentConfirmCard.allowButtonKey), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.stepRowKey(1)),
        matching: find.byIcon(LucideIcons.shieldCheck),
      ),
      findsOneWidget,
    );
    await _drainTimers(tester);
  });

  testWidgets('10 态：stopping（实时）chip', (WidgetTester tester) async {
    final _Harness h = _Harness();
    final Completer<ChatResponse> round2 = Completer<ChatResponse>();
    h.gate.allow();
    h.chat.respond(_callResp(_toolCall('list_tables', <String, dynamic>{})));
    h.chat.hold(round2);
    unawaited(h.start(gates: _blockGates(Completer<GateCardResult>())));
    await tester.pumpAndSettle();
    expect(h.runner.status, AgentRunStatus.running);
    h.runner.requestStop(); // chat#2 挂起中：stopping 稳态可观察
    await tester.pump();
    expect(h.runner.status, AgentRunStatus.stopping);
    await tester.pumpWidget(
      _wrap(AgentTrajectoryCard(runMessages: h.runMessages, runner: h.runner)),
    );
    await tester.pump();
    expect(find.text('Stopping'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.chipIconKey),
        matching: find.byIcon(LucideIcons.square),
      ),
      findsOneWidget,
    );
    await _drainTimers(tester);
  });

  testWidgets('中断态未决门卡：既定降级「已随运行取消」（不改 payload）', (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[mkAnchor('run_z'), mkGate('run_z', 1)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 中断态默认折叠；展开后门卡以 rejected 合成结论渲染。
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(find.byType(AgentConfirmCard), findsOneWidget);
    expect(find.byKey(AgentConfirmCard.conclusionKey), findsOneWidget);
    expect(find.text('Canceled (run stopped)'), findsOneWidget);
    expect(find.byKey(AgentConfirmCard.allowButtonKey), findsNothing);
  });

  testWidgets('gateBlockBuilder 注入形态：自定义 builder 替换默认确认卡', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[mkAnchor('run_c'), mkGate('run_c', 1)],
          gateBlockBuilder:
              (
                BuildContext context, {
                required AiMessage gateMessage,
                required GateCardResult? outcome,
                required void Function(GateCardResult decision) onDecision,
              }) => const Text('custom-block'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(find.text('custom-block'), findsOneWidget);
    expect(find.byType(AgentConfirmCard), findsNothing);
  });

  testWidgets('§1.5 终局汇报行：summaryText 恒显（折叠态不被吃掉）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[
            mkAnchor('run_r'),
            mkTerminal(
              'run_r',
              'stoppedByUser',
              steps: 2,
              summaryText: 'Stopped here',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.reportRowKey),
        matching: find.text('Stopped here'),
      ),
      findsOneWidget,
    );
  });

  // ── M1：终局「模型回复」区（附录 2 M1 四条验收补充）───────────────────────

  testWidgets('M1-① completed 含 ```sql 围栏：展开态回复区渲染 + 复制剪贴板 = 围栏 SQL 全文', (
    WidgetTester tester,
  ) async {
    const String sql = 'SELECT id, name FROM users WHERE id = 1';
    // 剪贴板 mock（沿 sql_tool_card_test 同款 SystemChannels 拦截）。
    String? clipText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final Map<dynamic, dynamic>? args =
                  call.arguments as Map<dynamic, dynamic>?;
              clipText = args?['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return clipText == null
                  ? null
                  : <String, dynamic>{'text': clipText};
            default:
              return null;
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_f'),
      ...mkStep(
        'run_f',
        1,
        'execute_readonly_sql',
        args: <String, dynamic>{'sql': sql},
      ),
      mkTerminal(
        'run_f',
        'completed',
        steps: 1,
        summaryText: 'Completed · 1 step(s)',
        content:
            'Here is the query:\n```sql\n$sql\n```\nRun it in the editor if needed.',
      ),
    ];
    await tester.pumpWidget(_wrap(AgentTrajectoryCard(runMessages: messages)));
    await tester.pumpAndSettle();
    // 折叠态零构建（NF1.1 延伸）。
    expect(find.byKey(AgentTrajectoryCard.finalReplyKey), findsNothing);
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AgentTrajectoryCard.finalReplyKey), findsOneWidget);
    expect(find.text('Model reply'), findsOneWidget);
    expect(find.text('Here is the query:'), findsOneWidget);
    expect(find.text('Run it in the editor if needed.'), findsOneWidget);
    // 步详情未展开 → 唯一复制钮 = 回复区围栏段；点击后剪贴板 = 围栏内全文。
    await tester.tap(find.text('Copy'));
    await tester.pump();
    final ClipboardData? data = await Clipboard.getData('text/plain');
    expect(data?.text, sql);
    expect(find.text('Copied'), findsOneWidget);
    // 推进 2s 让复制反馈复位定时器触发（避免 pending timer 断言）。
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('M1-② 折叠态或非 completed 终局：finalReplyKey findsNothing', (
    WidgetTester tester,
  ) async {
    // stoppedByUser 且正文与 summary 不同：状态门先于正文判重，仍不渲染。
    final List<AiMessage> stopped = <AiMessage>[
      mkAnchor('run_ns'),
      ...mkStep('run_ns', 1, 'list_tables'),
      mkTerminal(
        'run_ns',
        'stoppedByUser',
        steps: 1,
        summaryText: 'Stopped by user',
        content: 'Partial narrative differing from the summary line',
      ),
    ];
    await tester.pumpWidget(_wrap(AgentTrajectoryCard(runMessages: stopped)));
    await tester.pumpAndSettle();
    expect(find.byKey(AgentTrajectoryCard.finalReplyKey), findsNothing);
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AgentTrajectoryCard.finalReplyKey), findsNothing);
    // 中断态（有锚点无终局）同样不渲染。
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: <AiMessage>[
            mkAnchor('run_ni'),
            ...mkStep('run_ni', 1, 'list_tables'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AgentTrajectoryCard.finalReplyKey), findsNothing);
  });

  testWidgets('M1-③ 长回复不突破卡体 360 上限：单一滚动区不变式保持', (WidgetTester tester) async {
    final String longProse = List<String>.generate(
      40,
      (int i) => 'Narrative line $i explaining the analysis in plain prose.',
    ).join('\n');
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_l'),
      ...mkStep('run_l', 1, 'list_tables'),
      mkTerminal(
        'run_l',
        'completed',
        steps: 1,
        summaryText: 'Completed · 1 step(s)',
        content: '$longProse\n```sql\nSELECT * FROM orders\n```\n$longProse',
      ),
    ];
    await tester.pumpWidget(_wrap(AgentTrajectoryCard(runMessages: messages)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    // 单一滚动区 + 卡体 360 上限（回复区在滚动区内，不另开滚动/不撑破卡体）。
    // 「单一」口径：排除多行 SelectableText 自带的文本内部滚动器后，滚动器
    // 恰为卡体 stepsScrollKey 一个。
    final Set<Element> selectableTexts = find
        .byType(SelectableText)
        .evaluate()
        .toSet();
    bool insideSelectableText(Element el) {
      bool inside = false;
      el.visitAncestorElements((Element ancestor) {
        if (selectableTexts.contains(ancestor)) {
          inside = true;
          return false;
        }
        return true;
      });
      return inside;
    }

    final List<Element> containerScrollables = find
        .byType(Scrollable)
        .evaluate()
        .where((Element el) => !insideSelectableText(el))
        .toList();
    expect(containerScrollables, hasLength(1));
    expect(find.byKey(AgentTrajectoryCard.stepsScrollKey), findsOneWidget);
    final double bodyHeight = tester
        .getSize(find.byKey(AgentTrajectoryCard.stepsScrollKey))
        .height;
    expect(bodyHeight, lessThanOrEqualTo(362));
    expect(bodyHeight, moreOrLessEquals(360, epsilon: 1));
    // 滚到底后步列表仍可达（单一滚动区，无嵌套滚动）。jumpTo 确定到位，
    // 避开 drag 惯性物理在测试环境的落点歧义。
    final ScrollableState scrollable =
        (containerScrollables.single as StatefulElement).state
            as ScrollableState;
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    final Rect cardRect = tester.getRect(find.byType(AgentTrajectoryCard));
    final Rect rowRect = tester.getRect(
      find.byKey(AgentTrajectoryCard.stepRowKey(1)),
    );
    expect(rowRect.top, greaterThanOrEqualTo(cardRect.top));
    expect(rowRect.bottom, lessThanOrEqualTo(cardRect.bottom + 1));
  });

  testWidgets('M1-④ 0 步纯对话 run：展开态回复可见（_hasBody 扩展）', (
    WidgetTester tester,
  ) async {
    const String answer = 'Plain conversational answer with no fenced code.';
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_p'),
      mkTerminal(
        'run_p',
        'completed',
        steps: 0,
        summaryText: 'Completed · 0 step(s)',
        content: answer,
      ),
    ];
    await tester.pumpWidget(_wrap(AgentTrajectoryCard(runMessages: messages)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    // 0 步 run 仅凭回复区即构建卡体（_hasBody 扩展）。
    expect(find.byKey(AgentTrajectoryCard.stepsScrollKey), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.finalReplyKey), findsOneWidget);
    expect(find.text(answer), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.stepRowKey(1)), findsNothing);
  });

  testWidgets('M1-⑤ markdown 渲染：散文段走 MarkdownBody、裸标记不再作为正文、围栏段复制保持', (
    WidgetTester tester,
  ) async {
    // 用户实报形态（走查缺陷 Fix-K）：## 标题 / - **粗体**：值 / 行内 `code`
    // 全部裸露；围栏段 = SQL 全文（复制语义走查已认可）。
    const String sql = 'SELECT id, name FROM users WHERE id = 1';
    String? clipText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          switch (call.method) {
            case 'Clipboard.setData':
              final Map<dynamic, dynamic>? args =
                  call.arguments as Map<dynamic, dynamic>?;
              clipText = args?['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return clipText == null
                  ? null
                  : <String, dynamic>{'text': clipText};
            default:
              return null;
          }
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_md'),
      ...mkStep(
        'run_md',
        1,
        'execute_readonly_sql',
        args: <String, dynamic>{'sql': sql},
      ),
      mkTerminal(
        'run_md',
        'completed',
        steps: 1,
        summaryText: 'Completed · 1 step(s)',
        content:
            '## 当前状态\n'
            '- **连接**：postgresql\n'
            '- 工具 `list_tables` 已执行\n'
            '```sql\n'
            '$sql\n'
            '```\n'
            '完成。',
      ),
    ];
    await tester.pumpWidget(_wrap(AgentTrajectoryCard(runMessages: messages)));
    await tester.pumpAndSettle();
    // 折叠态零构建不变式不受 Fix-K 影响。
    expect(find.byKey(AgentTrajectoryCard.finalReplyKey), findsNothing);
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(find.byKey(AgentTrajectoryCard.finalReplyKey), findsOneWidget);
    // 散文段 = MarkdownBody（两个散文段：标题清单块 + 尾句；围栏段不经过它）。
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.finalReplyKey),
        matching: find.byType(MarkdownBody),
      ),
      findsNWidgets(2),
    );
    // 裸 markdown 标记不再作为正文文本出现（井号/星号/反引号被渲染消费）。
    expect(find.text('## 当前状态'), findsNothing);
    expect(find.text('**连接**：postgresql'), findsNothing);
    expect(find.text('工具 `list_tables` 已执行'), findsNothing);
    // 渲染产物：标题文字、清单项（粗体 + 正文拼合为可选中文本）、行内 code
    // 并入段落文本。
    expect(find.text('当前状态'), findsOneWidget);
    expect(find.text('连接：postgresql'), findsOneWidget);
    expect(find.text('工具 list_tables 已执行'), findsOneWidget);
    expect(find.text('完成。'), findsOneWidget);
    // 围栏段保持 _codeBlock 视觉与复制语义：步详情未展开 → 唯一复制钮 =
    // 回复区围栏段；复制内容 = 围栏内 SQL 全文（非 markdown 加工文本）。
    expect(find.text(sql), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    final ClipboardData? data = await Clipboard.getData('text/plain');
    expect(data?.text, sql);
    expect(find.text('Copied'), findsOneWidget);
    // 推进 2s 让复制反馈复位定时器触发（避免 pending timer 断言）。
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copied'), findsNothing);
  });

  // ── T23：agent_plan 内嵌分支 + [查看失败边界] 接线 ─────────────────────────

  /// `agent_plan` 门卡消息（payload 携带 planId；活跃计划对象经
  /// planResolver 注入——T27/T28 装配形态的镜像）。
  AiMessage mkPlanGate(String runId, int stepNo) => AiMessage(
    id: 'agent_gp_${runId}_$stepNo',
    isUser: false,
    content: '',
    timestamp: DateTime.now(),
    type: AiMessageType.toolResult,
    toolName: 'submit_action_plan',
    status: AiMessageStatus.completed,
    toolResultSummary: 'Action plan awaiting approval',
    toolResultData: <String, dynamic>{
      'agent': <String, dynamic>{
        'kind': 'agent_plan',
        'runId': runId,
        'stepNo': stepNo,
        'planId': 'plan_t_1',
      },
    },
  );

  /// 活跃计划 fixture（单步；status 可变——就地可变值对象镜像）。
  AgentActionPlan mkPlanT(AgentPlanStatus status) {
    final AgentPlanStep step = AgentPlanStep(
      sql: 'UPDATE orders SET status = 1 WHERE id = 1',
      kind: AgentPlanStepKind.dml,
      estimatedRows: 12,
      estimatedRowsSource: AgentRowsEstimateSource.explain,
      rollbackSql: 'UPDATE orders SET status = 0 WHERE id = 1',
      rollbackSource: AgentRollbackSource.model,
    );
    return AgentActionPlan(
      planId: 'plan_t_1',
      runId: 'run_p',
      ctx: const AgentRunContext(
        runId: 'run_p',
        dbType: DatabaseType.mysql,
        readOnly: false,
      ),
      steps: <AgentPlanStep>[step],
      status: status,
    );
  }

  /// plan 分支注入形态（T27/T28 消费形态镜像）：resolver + builder 成对，
  /// 回调闭包宿主持有。
  ({
    AgentActionPlan? Function(AiMessage) resolve,
    AgentPlanGateBlockBuilder build,
    List<String> calls,
  })
  mkPlanWiring(AgentActionPlan plan) {
    final List<String> calls = <String>[];
    AgentActionPlan? resolve(AiMessage _) => plan;
    AgentPlanGateBlockBuilder build =
        (
          BuildContext context, {
          required AiMessage gateMessage,
          required AgentActionPlan plan,
        }) => AgentPlanCard(
          plan: plan,
          callbacks: AgentPlanCallbacks(
            // Fix-E：批准回调改带 forSession 勾选态（签名适配；本用例不勾选
            // → 记录不变，断言语义不变）。
            onApprove: ({required bool forSession}) => calls.add('approve'),
            onReject: () => calls.add('reject'),
          ),
        );
    return (resolve: resolve, build: build, calls: calls);
  }

  testWidgets('plan 分支：未决计划嵌块在非展开详情位强制渲染；批准回调直达宿主', (
    WidgetTester tester,
  ) async {
    final AgentActionPlan plan = mkPlanT(AgentPlanStatus.pendingApproval);
    final wiring = mkPlanWiring(plan);
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_p'),
      ...mkStep('run_p', 1, 'submit_action_plan'),
      mkPlanGate('run_p', 1),
    ];
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: messages,
          planResolver: wiring.resolve,
          planBlockBuilder: wiring.build,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    // 未决（pendingApproval）：不经步详情展开即渲染（§1.6 未决嵌块恒可见；
    // awaitingUser 的整卡强制展开由 runner 状态驱动，T13 既有用例覆盖）。
    expect(find.byType(AgentPlanCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(AgentTrajectoryCard.gateBlockKey('agent_gp_run_p_1')),
        matching: find.byType(AgentPlanCard),
      ),
      findsOneWidget,
    );
    // 批准回调直达宿主闭包（执行在 T28，卡只发信号）。
    expect(wiring.calls, isEmpty);
    await tester.tap(find.byKey(AgentPlanCard.approveButtonKey));
    await tester.pump();
    expect(wiring.calls, <String>['approve']);
  });

  testWidgets('plan 分支：决策后（done）收进 submit 步详情位（同 confirm 模式）', (
    WidgetTester tester,
  ) async {
    final AgentActionPlan plan = mkPlanT(AgentPlanStatus.done);
    plan.steps.first.runtime.status = AgentPlanStepStatus.done;
    final wiring = mkPlanWiring(plan);
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_p'),
      ...mkStep('run_p', 1, 'submit_action_plan'),
      mkPlanGate('run_p', 1),
      mkTerminal('run_p', 'completed', steps: 1, summaryText: 'Done'),
    ];
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: messages,
          planResolver: wiring.resolve,
          planBlockBuilder: wiring.build,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    // 已决计划不再强制渲染：步详情未展开时嵌块不出现。
    expect(find.byType(AgentPlanCard), findsNothing);
    // 展开 submit 步详情 → 嵌块出现在详情位。
    await tester.tap(find.byKey(AgentTrajectoryCard.stepRowKey(1)));
    await tester.pumpAndSettle();
    expect(find.byType(AgentPlanCard), findsOneWidget);
  });

  testWidgets('plan 分支：planResolver 未注入 → 防御性不渲染（不崩卡）', (
    WidgetTester tester,
  ) async {
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_p'),
      ...mkStep('run_p', 1, 'submit_action_plan'),
      mkPlanGate('run_p', 1),
    ];
    await tester.pumpWidget(_wrap(AgentTrajectoryCard(runMessages: messages)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AgentPlanCard), findsNothing);
    expect(find.byType(AgentConfirmCard), findsNothing);
    // 步行不受影响（submit 步照常渲染）。
    expect(find.byKey(AgentTrajectoryCard.stepRowKey(1)), findsOneWidget);
  });

  testWidgets('§1.5 [查看失败边界]：partialFailed 终局渲染入口；点击展开卡体 + 通知宿主', (
    WidgetTester tester,
  ) async {
    final AppLocalizations l10n = AppLocalizationsEn();
    final AgentActionPlan plan = mkPlanT(AgentPlanStatus.partialFailed);
    plan.steps.first.runtime.status = AgentPlanStepStatus.done;
    final wiring = mkPlanWiring(plan);
    var hostNotified = 0;
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_p'),
      ...mkStep('run_p', 1, 'submit_action_plan'),
      mkPlanGate('run_p', 1),
      mkTerminal(
        'run_p',
        'partialFailed',
        steps: 1,
        summaryText: 'Plan stopped on a failing statement',
      ),
    ];
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: messages,
          planResolver: wiring.resolve,
          planBlockBuilder: wiring.build,
          onViewFailureBoundary: () => hostNotified++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 终局默认折叠：汇报行恒显，入口文案为 T21 专属 key（占位替换断言）。
    expect(find.byKey(AgentTrajectoryCard.reportRowKey), findsOneWidget);
    expect(find.text(l10n.agentTrajectoryViewBoundary), findsOneWidget);
    expect(find.byKey(AgentTrajectoryCard.stepRowKey(1)), findsNothing);
    // 点击 → 宿主回调 + 卡体展开（滚动定位的可见性前提）。
    await tester.tap(find.text(l10n.agentTrajectoryViewBoundary));
    await tester.pumpAndSettle();
    expect(hostNotified, 1);
    expect(find.byKey(AgentTrajectoryCard.stepRowKey(1)), findsOneWidget);
    expect(find.byType(AgentPlanCard), findsOneWidget);
  });

  testWidgets('§1.5 [查看失败边界]：非失败终局 / 未注入回调 → 不渲染', (WidgetTester tester) async {
    final AppLocalizations l10n = AppLocalizationsEn();
    final List<AiMessage> messages = <AiMessage>[
      mkAnchor('run_p'),
      mkTerminal('run_p', 'completed', steps: 1),
    ];
    await tester.pumpWidget(
      _wrap(
        AgentTrajectoryCard(
          runMessages: messages,
          onViewFailureBoundary: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.agentTrajectoryViewBoundary), findsNothing);
  });
}
