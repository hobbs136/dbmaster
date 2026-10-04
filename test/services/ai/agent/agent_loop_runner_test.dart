// AgentLoopRunner 单测（T11 / design-ai-agent.md §4.3、§5.2、§6.4、§6.5、
// D11、D15、D17、D18、D19）。
//
// 覆盖任务书清单：状态机全迁移（§6.5 图逐边）、四停止源终局与汇报消息、
// 预算部分执行（AC2.2）、失败计数清零（D18）、usage null 降级（D11/AC3.4）、
// 快照不漂移（D15/AC7.2）、seed 裁剪（D19）、消息结构断言（§5.2）、
// resetSteps 接线（AC2.3 对账）、D17 isRunning 守卫、会话切换复位、
// T2 方案 B 上下文缺失终止（stoppedByContext：②a/②b 接入、批量占位回喂、
// zh/en 终局文案、用户停止优先、豁免回归）。
//
// 依赖全注入（NF5.3）：chat 脚本化闭包队列；executor 为**真实** AgentToolExecutor
// （步数对账走真实 D10 计数点），门用 _ScriptedGate 可编程判定；db / 审计 /
// 统计均为 spy 闭包（隔离 AuditLogService 与 WorkbenchUsageStatsService 单例）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/ai_memory_item.dart'
    show AiMemoryItem, AiMemoryScope;
import 'package:dbmaster/models/ai_message_type.dart'
    show AiMessageStatus, AiMessageType;
import 'package:dbmaster/models/ai_models.dart'
    show AiToolCall, ChatResponse, TokenUsage;
import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart'
    show AiMessage, DatabaseType, DbColumn, DbIndex, ForeignKey;
import 'package:dbmaster/models/query_optimizer/execution_plan.dart'
    show PerformanceReport;
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentGate, AgentRunContext, GateDecision, GateDecisionKind;
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show ReadImpactAnalysis;
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart';
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolErrorCodes, AgentToolSpec;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart'
    show AgentDbAccess, AgentToolExecutor, GateCallbacks;
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort, GateCardResult;
import 'package:dbmaster/services/ai/ai_session_manager.dart'
    show AiSessionManager;

// ── fakes / spies ───────────────────────────────────────────────────────────

/// 界面端口缺省 fake（T28：start 的 uiPort 已转必填——A1 相位用例不触界面
/// 工具，注入零副作用占位）。
class _NoopUiPort implements AgentUiPort {
  const _NoopUiPort();

  @override
  Future<AgentUiOutcome> openResultGrid(AgentResultRef ref, String? title) =>
      Future.value(const AgentUiOutcome.failure('noop port'));

  @override
  Future<AgentUiOutcome> showTableStructure(String table) =>
      Future.value(const AgentUiOutcome.failure('noop port'));

  @override
  Future<AgentUiOutcome> openSqlEditor(String sql) =>
      Future.value(const AgentUiOutcome.failure('noop port'));

  @override
  Future<AgentUiOutcome> renderChart(AgentResultRef ref, String? chartKind) =>
      Future.value(const AgentUiOutcome.failure('noop port'));

  @override
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label) =>
      Future.value(const AgentUiOutcome.failure('noop port'));

  @override
  Future<AgentUiOutcome> suggestOpenInClassic(String sql) =>
      Future.value(const AgentUiOutcome.failure('noop port'));

  @override
  Future<AgentUiOutcome> suggestFocusSidebar({
    String? database,
    String? table,
  }) => Future.value(const AgentUiOutcome.failure('noop port'));

  @override
  Future<AgentUiOutcome> openOptimization(
    PerformanceReport report,
    String sql,
  ) => Future.value(const AgentUiOutcome.failure('noop port'));
}

const _NoopUiPort _noopUiPort = _NoopUiPort();

/// chat 请求快照（history 在调用时点深拷贝——后续轮次追加不回写）。
class _ChatRequest {
  _ChatRequest({
    required this.provider,
    required this.model,
    required this.apiKey,
    required this.baseUrl,
    required this.message,
    required this.systemPrompt,
    required this.history,
    required this.tools,
    required this.timeout,
  });

  final String provider;
  final String model;
  final String apiKey;
  final String? baseUrl;
  final String message;
  final String? systemPrompt;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>>? tools;
  final Duration timeout;
}

/// 脚本化 chat：按调用序弹出一个闭包（响应 / 抛错 / Completer 门控均可）。
class _ChatScript {
  final List<Future<ChatResponse> Function()> queue =
      <Future<ChatResponse> Function()>[];
  final List<_ChatRequest> requests = <_ChatRequest>[];

  int get callCount => requests.length;

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
    requests.add(
      _ChatRequest(
        provider: provider,
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        message: message,
        systemPrompt: systemPrompt,
        history: history == null
            ? const <Map<String, dynamic>>[]
            : <Map<String, dynamic>>[
                for (final m in history) Map<String, dynamic>.of(m),
              ],
        tools: tools == null
            ? null
            : <Map<String, dynamic>>[
                for (final t in tools) Map<String, dynamic>.of(t),
              ],
        timeout: timeout,
      ),
    );
    if (queue.isEmpty) {
      throw StateError(
        'AgentLoopRunnerTest: unexpected chat call #'
        '${requests.length}',
      );
    }
    return queue.removeAt(0)();
  }

  void respond(ChatResponse resp) => queue.add(() async => resp);

  void failWith(Object error) => queue.add(() async => throw error);
}

ChatResponse _text(String content, {TokenUsage? usage}) => ChatResponse(
  content: content,
  toolCalls: const <AiToolCall>[],
  usage: usage,
);

AiToolCall _toolCall(String name, [Map<String, dynamic> args = const {}]) =>
    AiToolCall(
      id: 'call-${name.hashCode.abs()}',
      type: 'function',
      functionName: name,
      functionArguments: jsonEncode(args),
    );

ChatResponse _call(AiToolCall call, {String? content, TokenUsage? usage}) =>
    ChatResponse(content: content, toolCalls: <AiToolCall>[call], usage: usage);

/// 可编程门（真 AgentGate 子类覆写 evaluate；形态对齐 T10 测试先例）。
class _ScriptedGate extends AgentGate {
  _ScriptedGate()
    : super(createAnalysis: (_) => throw StateError('scripted never analyzes'));

  final List<Future<GateDecision> Function()> decisions =
      <Future<GateDecision> Function()>[];
  final List<AgentRunContext> seenRunCtx = <AgentRunContext>[];

  @override
  Future<GateDecision> evaluate({
    required AgentToolSpec spec,
    required Map<String, dynamic> args,
    required AgentRunContext runCtx,
    required AgentPermissionLedger ledger,
  }) {
    seenRunCtx.add(runCtx);
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

  void reject(String code) => decisions.add(
    () async => GateDecision(
      kind: GateDecisionKind.reject,
      level: AgentGateLevel.l0,
      reasonCode: code,
    ),
  );

  /// Fix-B 中-1 用例：evaluate 抛出（execute 链异常的最小制造点）。
  void failWith(Object error) => decisions.add(() async => throw error);

  void confirmL05(ReadImpactAnalysis impact) => decisions.add(
    () async => GateDecision(
      kind: GateDecisionKind.confirm,
      level: AgentGateLevel.l05,
      impact: impact,
    ),
  );
}

/// db 访问 spy（getTables 可门控以制造「在途步」）。
class _DbSpy {
  int getTablesCalls = 0;
  int executeQueryCalls = 0;
  Completer<List<String>>? getTablesGate;
  final List<String?> getTablesDatabases = <String?>[];

  Future<List<String>> getTables(
    String? connectionId,
    String? databaseName,
  ) async {
    getTablesCalls++;
    getTablesDatabases.add(databaseName);
    final Completer<List<String>>? gate = getTablesGate;
    if (gate != null) return gate.future;
    return <String>['users', 'orders'];
  }
}

/// 运行级统计 spy。
class _StatsSpy {
  int sessionStarts = 0;
  int activeDays = 0;
  int limitStops = 0;
  final List<({int steps, int? tokens})> runEnds =
      <({int steps, int? tokens})>[];
}

/// 测试台：真实 executor + 脚本化 chat/门 + spy 依赖。
/// [gateOverride] 注入真实 AgentGate（T2 方案 B ②a/②b 全链用例）；
/// [auditGate] 门控审计落账（构造「execute 在途」窗口，边界② 同帧用例）。
class _Harness {
  _Harness({
    int maxSteps = 25,
    DatabaseType dbType = DatabaseType.mysql,
    String connectionId = 'conn-1',
    bool readOnly = false,
    String locale = 'en',
    AgentMemoryResolver? memoryResolver,
    AgentGate? gateOverride,
  }) : chat = _ChatScript(),
       gate = _ScriptedGate(),
       realGate = gateOverride,
       db = _DbSpy(),
       stats = _StatsSpy(),
       sessionManager = AiSessionManager() {
    sessionManager.createSession();
    ctxHolder = _CtxHolder(
      AgentRunContext(
        runId: 'pending',
        connectionId: connectionId,
        connectionName: connectionId.isEmpty ? null : '测试连接',
        databaseName: connectionId.isEmpty ? null : 'db1',
        dbType: dbType,
        readOnly: readOnly,
      ),
    );
    executor = AgentToolExecutor(
      gate: realGate ?? gate,
      db: AgentDbAccess(
        getTables: db.getTables,
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
        executeQuery:
            (String sql, {String? connectionId, String? database}) async {
              db.executeQueryCalls++;
              return <Map<String, dynamic>>[
                <String, dynamic>{'id': 1},
              ];
            },
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
          }) async {
            final Completer<void>? gate = auditGate;
            if (gate != null) await gate.future;
            auditRecords.add(<String, Object?>{
              'connectionId': connectionId,
              'runId': runId,
              'step': step,
              'tool': tool,
              'sql': sql,
              'gateLevel': gateLevel,
              'gateDecision': gateDecision,
              'success': success,
              'errorMessage': errorMessage,
            });
          },
      recordToolCall: (_) {},
      recordL05Event: (_) {},
    );
    runner = AgentLoopRunner(
      executor: executor,
      sessionManager: sessionManager,
      // 快照解析（对齐生产语义：start 时按模板字段 + 本次 runId 构造一次性
      // 快照——D15；模板运行中可变，快照不变）。
      resolveRunContext: (String runId) => AgentRunContext(
        runId: runId,
        connectionId: ctxHolder.value.connectionId,
        connectionName: ctxHolder.value.connectionName,
        databaseName: ctxHolder.value.databaseName,
        dbType: ctxHolder.value.dbType,
        readOnly: ctxHolder.value.readOnly,
      ),
      resolveChatConfig: () => AgentChatConfig(
        provider: 'DeepSeek',
        model: 'deepseek-chat',
        apiKey: 'test-key',
        locale: locale,
      ),
      chat: chat.call,
      resolveMaxSteps: () async => maxSteps,
      memoryResolver: memoryResolver,
      stats: AgentRunStatsCallbacks(
        onSessionStart: () => stats.sessionStarts++,
        onActiveDay: () => stats.activeDays++,
        onRunEnd: ({required int steps, int? tokens}) =>
            stats.runEnds.add((steps: steps, tokens: tokens)),
        onLimitStop: () => stats.limitStops++,
      ),
    );
    runner.addListener(_onRunnerChange);
  }

  final _ChatScript chat;
  final _ScriptedGate gate;
  final AgentGate? realGate;
  final _DbSpy db;
  final _StatsSpy stats;
  final AiSessionManager sessionManager;

  /// 审计落账门控（T2 边界② 用例：构造「execute 在途」窗口）。
  Completer<void>? auditGate;

  /// 审计记录（Fix-B 中-1 用例：兜底审计断言面）。
  final List<Map<String, Object?>> auditRecords = <Map<String, Object?>>[];
  late final _CtxHolder ctxHolder;
  late final AgentToolExecutor executor;
  late final AgentLoopRunner runner;

  /// shell 门卡回调（决策由测试用 cardCompleter 手动落定；每次取 [gates]
  /// 重建——测试内只取一次）。
  Completer<GateCardResult> cardCompleter = Completer<GateCardResult>();
  final List<ReadImpactAnalysis> seenImpacts = <ReadImpactAnalysis>[];
  final List<String> seenConfirmSql = <String>[];
  final List<AgentRunStatus> statuses = <AgentRunStatus>[];

  GateCallbacks get gates {
    final Completer<GateCardResult> completer = Completer<GateCardResult>();
    cardCompleter = completer;
    return GateCallbacks(
      onL05Confirm: (ReadImpactAnalysis impact, String sql) {
        seenImpacts.add(impact);
        seenConfirmSql.add(sql);
        return completer.future;
      },
      onPlanApproval: (Object plan) async => GateCardResult.rejected,
    );
  }

  void _onRunnerChange() => statuses.add(runner.status);

  List<AiMessage> get messages => sessionManager.currentMessages.toList();

  /// §5.2 agent 载荷消息定位（kind 过滤）。
  List<Map<String, dynamic>> agentPayloads(String kind) => messages
      .where(
        (AiMessage m) =>
            m.toolResultData?['agent'] is Map<String, dynamic> &&
            (m.toolResultData!['agent'] as Map<String, dynamic>)['kind'] ==
                kind,
      )
      .map((AiMessage m) => m.toolResultData!['agent'] as Map<String, dynamic>)
      .toList();
}

/// 可变上下文持有器（快照不漂移用例：运行中改源，不影响已发快照）。
class _CtxHolder {
  _CtxHolder(this.value);

  AgentRunContext value;
}

Future<void> _flush([int rounds = 6]) async {
  for (int i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('状态机全迁移（§6.5 图逐边）', () {
    test('idle ──start──► running：运行中可观察，activeRunId 就位', () async {
      final h = _Harness();
      final Completer<ChatResponse> round1 = Completer<ChatResponse>();
      h.chat.queue.add(() => round1.future);

      unawaited(
        h.runner.start(
          uiPort: _noopUiPort,
          userMessage: '看看有哪些表',
          gates: h.gates,
        ),
      );
      await _flush();

      expect(h.runner.status, AgentRunStatus.running);
      expect(h.runner.isRunning, isTrue);
      expect(h.runner.activeRunId, isNotNull);
      expect(h.statuses.contains(AgentRunStatus.running), isTrue);

      round1.complete(_text('done'));
      await _flush();
      expect(h.runner.status, AgentRunStatus.completed);
    });

    test('running ──tool_calls 空──► completed：最终回复为终局消息正文', () async {
      final h = _Harness();
      h.chat.respond(_text('库里有 users 和 orders 两张表'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '看看有哪些表');

      expect(h.runner.status, AgentRunStatus.completed);
      expect(h.runner.isRunning, isFalse);
      final List<Map<String, dynamic>> ends = h.agentPayloads('agent_run_end');
      expect(ends, hasLength(1));
      expect(ends.first['status'], 'completed');
      expect(ends.first['steps'], 0);
      final AiMessage endMsg = h.messages.last;
      expect(endMsg.content, '库里有 users 和 orders 两张表');
      expect(endMsg.type, AiMessageType.chat);
      expect(endMsg.status, AiMessageStatus.completed);
    });

    test(
      'running ──门 confirm──► awaitingUser ──决策──► running ──► completed',
      () async {
        final h = _Harness();
        h.gate.confirmL05(
          const ReadImpactAnalysis(
            estimatedRows: 800000,
            fullScan: true,
            scannedTables: <String>['big_table'],
            indexSummary: 'no usable index',
            analysisUnavailable: false,
          ),
        );
        // 决策通过后 round1 调用收尾，round2 出最终文本。
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': 'SELECT * FROM big_table',
            }),
          ),
        );
        h.chat.respond(_text('分析完成'));

        final GateCallbacks gates = h.gates;
        unawaited(
          h.runner.start(uiPort: _noopUiPort, userMessage: '查大表', gates: gates),
        );
        await _flush();

        // awaitingUser 边 + 门卡宿主消息（决策前无 outcome）。
        expect(h.runner.status, AgentRunStatus.awaitingUser);
        expect(h.runner.isRunning, isTrue);
        final List<Map<String, dynamic>> cards = h.agentPayloads(
          'agent_confirm',
        );
        expect(cards, hasLength(1));
        expect(cards.first['runId'], h.runner.activeRunId);
        expect(cards.first['stepNo'], 1);
        expect(cards.first['sql'], 'SELECT * FROM big_table');
        final Map<String, dynamic> impact =
            cards.first['impact'] as Map<String, dynamic>;
        expect(impact['estimatedRows'], 800000);
        expect(impact['fullScan'], isTrue);
        expect(impact['analysisUnavailable'], isFalse);
        expect(cards.first.containsKey('outcome'), isFalse);
        expect(h.seenImpacts, hasLength(1));

        // 决策 approved → 回 running → 执行 → round2 → completed。
        h.cardCompleter.complete(GateCardResult.approved);
        await _flush();

        expect(h.runner.status, AgentRunStatus.completed);
        expect(h.statuses.contains(AgentRunStatus.awaitingUser), isTrue);
        expect(h.statuses.contains(AgentRunStatus.running), isTrue);
        // 决策回填 outcome。
        final Map<String, dynamic> settled = h
            .agentPayloads('agent_confirm')
            .first;
        expect(settled['outcome'], 'approved');
        expect(h.runner.stepsUsed, 1);
        expect(h.db.executeQueryCalls, 1); // approved 后真实执行
      },
    );

    test('awaitingUser ──停止（rejected）──► stoppedByUser：卡回填 rejected', () async {
      final h = _Harness();
      h.gate.confirmL05(
        const ReadImpactAnalysis(
          estimatedRows: null,
          fullScan: false,
          analysisUnavailable: true,
        ),
      );
      h.chat.respond(
        _call(_toolCall('get_sample_data', <String, dynamic>{'table': 't'})),
      );
      h.chat.respond(_text('不应到达')); // 停止后不再发起新轮

      unawaited(
        h.runner.start(uiPort: _noopUiPort, userMessage: '采样', gates: h.gates),
      );
      await _flush();
      expect(h.runner.status, AgentRunStatus.awaitingUser);

      h.runner.requestStop();
      await _flush();

      expect(h.runner.status, AgentRunStatus.stoppedByUser);
      expect(h.runner.isRunning, isFalse);
      expect(h.chat.callCount, 1); // 第二轮未发起
      expect(h.agentPayloads('agent_confirm').first['outcome'], 'rejected');
      final List<Map<String, dynamic>> ends = h.agentPayloads('agent_run_end');
      expect(ends.first['status'], 'stoppedByUser');
      // 门拒步消息落账（GATE_REJECTED，结果保留）。
      expect(
        h.messages.any(
          (AiMessage m) =>
              m.toolResultSummary?.contains('GATE_REJECTED') ?? false,
        ),
        isTrue,
      );
      expect(h.db.executeQueryCalls, 0); // 人拒零执行
    });

    test(
      'running ──requestStop──► stopping ──当前步完成──► stoppedByUser',
      () async {
        final h = _Harness();
        final Completer<List<String>> slowTable = Completer<List<String>>();
        h.db.getTablesGate = slowTable; // 在途步门控
        h.chat.respond(_call(_toolCall('list_tables')));
        h.chat.respond(_text('不应到达'));

        unawaited(
          h.runner.start(
            uiPort: _noopUiPort,
            userMessage: '列表',
            gates: h.gates,
          ),
        );
        await _flush();
        expect(h.runner.status, AgentRunStatus.running);

        h.runner.requestStop();
        expect(h.runner.status, AgentRunStatus.stopping); // stopping 边即时可观察
        expect(h.runner.isRunning, isTrue);

        // 在途调用完成（结果保留）。
        slowTable.complete(<String>['users']);
        await _flush();

        expect(h.runner.status, AgentRunStatus.stoppedByUser);
        expect(h.db.getTablesCalls, 1); // 当前步完整执行
        expect(h.chat.callCount, 1); // 不再发起新轮
        final List<Map<String, dynamic>> ends = h.agentPayloads(
          'agent_run_end',
        );
        expect(ends.first['status'], 'stoppedByUser');
        expect(ends.first['steps'], 1);
      },
    );

    test('running ──chat 抛出──► failed：错误态消息 + 脱敏明细', () async {
      final h = _Harness();
      h.chat.failWith(Exception('API error: 429 rate limited on key sk-123'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '你好');

      expect(h.runner.status, AgentRunStatus.failed);
      final AiMessage endMsg = h.messages.last;
      expect(endMsg.status, AiMessageStatus.failed);
      expect(endMsg.errorMessage, isNotNull);
      expect(endMsg.content, contains('provider error'));
      expect(h.agentPayloads('agent_run_end').first['status'], 'failed');
    });
  });

  group('预算与失败上限（AC2.2 / D18 / NF3.2）', () {
    test('预算部分执行：预算内执行完，剩余不派发 → stoppedByLimit', () async {
      final h = _Harness(maxSteps: 2);
      // 一轮 3 个 tool_calls：前 2 个执行，第 3 个占位不执行。
      h.chat.respond(
        ChatResponse(
          content: null,
          toolCalls: <AiToolCall>[
            _toolCall('list_tables'),
            _toolCall('list_tables'),
            _toolCall('list_tables'),
          ],
        ),
      );

      await h.runner.start(uiPort: _noopUiPort, userMessage: '连查三次');

      expect(h.runner.status, AgentRunStatus.stoppedByLimit);
      expect(h.runner.stepsUsed, 2); // 预算内 2 步
      expect(h.db.getTablesCalls, 2); // 第 3 个零执行
      expect(h.stats.limitStops, 1); // 字段 9
      final List<Map<String, dynamic>> ends = h.agentPayloads('agent_run_end');
      expect(ends.first['status'], 'stoppedByLimit');
      expect(ends.first['steps'], 2);
      expect(h.chat.callCount, 1); // 不自动请求继续（AC2.2）
    });

    test('连续 5 个失败工具调用 → stoppedByFailures（汇报失败工具与最后错误）', () async {
      final h = _Harness();
      // 修订（T2 方案 B）：失败驱动码自 CONTEXT_REQUIRED 换为
      // EXECUTION_FAILED——CONTEXT_REQUIRED 现为终止语义（stoppedByContext），
      // 不再能驱动「回喂后 run 继续」的失败计数。
      for (int i = 0; i < 5; i++) {
        h.gate.reject(AgentToolErrorCodes.executionFailed);
        h.chat.respond(_call(_toolCall('describe_table')));
      }

      await h.runner.start(uiPort: _noopUiPort, userMessage: '反复失败');

      expect(h.runner.status, AgentRunStatus.stoppedByFailures);
      expect(h.runner.stepsUsed, 5); // 被拒调用也计步（D10）
      expect(h.chat.callCount, 5);
      final List<Map<String, dynamic>> ends = h.agentPayloads('agent_run_end');
      expect(ends.first['status'], 'stoppedByFailures');
      final AiMessage endMsg = h.messages.last;
      expect(endMsg.content, contains('describe_table'));
      expect(endMsg.content, contains('5'));
    });

    test('失败计数清零：任何成功调用重置连续计数（D18）', () async {
      final h = _Harness();
      // 2 失败 → 1 成功 → 4 失败 = 最大连续 4 < 5 → 不触发停止。
      // 修订（T2 方案 B）：失败驱动码用 EXECUTION_FAILED（见上）。
      h.gate.reject(AgentToolErrorCodes.executionFailed);
      h.chat.respond(_call(_toolCall('describe_table')));
      h.gate.reject(AgentToolErrorCodes.executionFailed);
      h.chat.respond(_call(_toolCall('describe_table')));
      h.gate.allow();
      h.chat.respond(_call(_toolCall('list_tables'))); // 成功清零
      for (int i = 0; i < 4; i++) {
        h.gate.reject(AgentToolErrorCodes.executionFailed);
        h.chat.respond(_call(_toolCall('describe_table')));
      }
      h.chat.respond(_text('全部处理完'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '混合结果');

      expect(h.runner.status, AgentRunStatus.completed);
      expect(h.runner.stepsUsed, 7);
      expect(h.agentPayloads('agent_run_end').first['status'], 'completed');
    });
  });

  group('T2 方案 B：上下文缺失终止（stoppedByContext，FU-10 收口）', () {
    /// 真实门（②a/②b 全链）：读前分析不可达（拒绝先于 ④）。
    AgentGate realGate() => AgentGate(
      createAnalysis: (_) => throw StateError('②a/②b 拒绝先于读前分析'),
    );

    /// mysql 无库快照（连接在、库缺——②b 面）。
    void setDbLessCtx(
      _Harness h, {
      String connectionId = 'c1',
      String connectionName = '测试连接',
      DatabaseType dbType = DatabaseType.mysql,
    }) {
      h.ctxHolder.value = AgentRunContext(
        runId: 'pending',
        connectionId: connectionId,
        connectionName: connectionName,
        databaseName: null,
        dbType: dbType,
        readOnly: false,
      );
    }

    test('真实门 ②b：mysql 无库快照调 list_tables → 门拒 → 终态 stoppedByContext', () async {
      final h = _Harness(gateOverride: realGate());
      setDbLessCtx(h);
      h.chat.respond(_call(_toolCall('list_tables')));
      h.chat.respond(_text('不应到达'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '看看有哪些表');

      expect(h.runner.status, AgentRunStatus.stoppedByContext);
      expect(h.runner.isRunning, isFalse);
      expect(h.runner.stepsUsed, 1); // 被拒调用仍计步（D10）
      expect(h.db.getTablesCalls, 0); // 零执行
      expect(h.chat.callCount, 1); // 不回喂继续（无第二轮）
      // 锚点/终局 payload status。
      final List<Map<String, dynamic>> ends = h.agentPayloads('agent_run_end');
      expect(ends, hasLength(1));
      expect(ends.first['status'], 'stoppedByContext');
      expect(ends.first['steps'], 1);
      // 终局消息含引导文案（en 有连接变体：{conn} + context chip）。
      expect(h.messages.last.content, contains('context chip'));
      expect(h.messages.last.content, contains('测试连接'));
      expect(h.messages.last.content, contains('Run stopped'));
      // 门拒 blocked 审计落账现状不变。
      expect(h.auditRecords, hasLength(1));
      expect(h.auditRecords.single['gateDecision'], AgentGateDecision.blocked);
      expect(h.auditRecords.single['tool'], 'list_tables');
      expect(h.auditRecords.single['success'], isFalse);
      // 步消息对落账（blocked 形态）。
      expect(h.agentPayloads('agent_step'), hasLength(1));
    });

    test('②b 逐工具：7 个 requiresDatabase 工具在 mysql 无库快照上同终止', () async {
      const List<(String, Map<String, dynamic>)> cases =
          <(String, Map<String, dynamic>)>[
            ('list_tables', <String, dynamic>{}),
            ('describe_table', <String, dynamic>{'table': 'users'}),
            ('get_sample_data', <String, dynamic>{'table': 'users'}),
            ('execute_readonly_sql', <String, dynamic>{'sql': 'SELECT 1'}),
            ('explain_plan', <String, dynamic>{'sql': 'SELECT 1'}),
            ('show_table_structure', <String, dynamic>{'table': 'users'}),
            ('submit_action_plan', <String, dynamic>{}),
          ];
      for (final (String tool, Map<String, dynamic> args) in cases) {
        final h = _Harness(gateOverride: realGate());
        setDbLessCtx(h);
        h.chat.respond(_call(_toolCall(tool, args)));

        await h.runner.start(uiPort: _noopUiPort, userMessage: '调 $tool');

        expect(
          h.runner.status,
          AgentRunStatus.stoppedByContext,
          reason: tool,
        );
        expect(h.db.executeQueryCalls + h.db.getTablesCalls, 0, reason: tool);
        expect(
          h.agentPayloads('agent_run_end').first['status'],
          'stoppedByContext',
          reason: tool,
        );
      }
    });

    test('无连接快照调 requiresConnection 工具 → ②a 既有拒绝路径接入同一终止', () async {
      final h = _Harness(connectionId: '', gateOverride: realGate());
      h.chat.respond(_call(_toolCall('list_tables')));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列出表');

      expect(h.runner.status, AgentRunStatus.stoppedByContext);
      expect(
        h.agentPayloads('agent_run_end').first['status'],
        'stoppedByContext',
      );
      // en 无连接变体文案。
      expect(h.messages.last.content, contains('no connection is set'));
      expect(h.messages.last.content, contains('connection and a database'));
    });

    test('批次多调用：第 1 个命中终止 → 剩余 2 个占位回喂（不派发），收敛终局', () async {
      final h = _Harness();
      h.gate.reject(AgentToolErrorCodes.contextRequired);
      h.chat.respond(
        ChatResponse(
          content: null,
          toolCalls: <AiToolCall>[
            _toolCall('list_tables'),
            _toolCall('describe_table', <String, dynamic>{'table': 't'}),
            _toolCall('get_sample_data', <String, dynamic>{'table': 't'}),
          ],
        ),
      );

      await h.runner.start(uiPort: _noopUiPort, userMessage: '连查三个');

      expect(h.runner.status, AgentRunStatus.stoppedByContext);
      expect(h.runner.stepsUsed, 1); // 只第 1 个进入执行管线（D10）
      expect(h.gate.decisions, isEmpty, reason: '剩余 2 个未派发（占位回喂）');
      expect(h.chat.callCount, 1); // 不再发起下一轮
      final List<Map<String, dynamic>> ends = h.agentPayloads('agent_run_end');
      expect(ends.first['status'], 'stoppedByContext');
      expect(ends.first['steps'], 1);
      expect(h.db.getTablesCalls, 0);
      expect(h.agentPayloads('agent_step'), hasLength(1)); // 第 1 个步消息对
    });

    test('zh 终局文案：有连接变体（连接：{conn} + 上下文芯片）', () async {
      final h = _Harness(locale: 'zh', gateOverride: realGate());
      setDbLessCtx(h);
      h.chat.respond(_call(_toolCall('list_tables')));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列出表');

      expect(h.runner.status, AgentRunStatus.stoppedByContext);
      expect(h.messages.last.content, contains('本次运行已终止'));
      expect(h.messages.last.content, contains('（连接：测试连接）'));
      expect(h.messages.last.content, contains('上下文芯片'));
    });

    test('边界②：requestStop 与终止检查点同帧 → 用户停止语义不被抢', () async {
      final h = _Harness();
      h.auditGate = Completer<void>(); // 审计门控 = execute 在途窗口
      h.gate.reject(AgentToolErrorCodes.contextRequired);
      h.chat.respond(_call(_toolCall('list_tables')));

      unawaited(h.runner.start(uiPort: _noopUiPort, userMessage: '列表'));
      await _flush();

      h.runner.requestStop(); // 在途期间请求停止
      expect(h.runner.status, AgentRunStatus.stopping);
      h.auditGate!.complete();
      await _flush();

      expect(h.runner.status, AgentRunStatus.stoppedByUser);
      expect(
        h.agentPayloads('agent_run_end').first['status'],
        'stoppedByUser',
      );
      expect(
        h.agentPayloads('agent_run_end').first['status'],
        isNot('stoppedByContext'),
      );
    });

    test('豁免回归：sqlite 无库快照（无选库概念）→ ②b 不拦，数据流照常完成', () async {
      final h = _Harness(dbType: DatabaseType.sqlite, gateOverride: realGate());
      setDbLessCtx(h, dbType: DatabaseType.sqlite, connectionName: 'SQLite 库');
      h.chat.respond(_call(_toolCall('list_tables')));
      h.chat.respond(_text('完成'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列出表');

      expect(h.runner.status, AgentRunStatus.completed);
      expect(h.db.getTablesCalls, 1); // 正常执行（豁免，行为同现状）
      expect(h.runner.stepsUsed, 1);
      expect(
        h.agentPayloads('agent_run_end').first['status'],
        'completed',
      );
    });
  });

  group('token 计数（D11 / AC3.1 / AC3.4）', () {
    test('逐轮累加 usage：总数 = 各轮之和，终局与统计对账', () async {
      final h = _Harness();
      h.chat.respond(
        _call(
          _toolCall('list_tables'),
          usage: const TokenUsage(
            promptTokens: 100,
            completionTokens: 20,
            totalTokens: 120,
          ),
        ),
      );
      h.chat.respond(
        _text(
          '完成',
          usage: const TokenUsage(
            promptTokens: 200,
            completionTokens: 30,
            totalTokens: 230,
          ),
        ),
      );

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列表');

      expect(h.runner.tokenUsage?.totalTokens, 350);
      final List<Map<String, dynamic>> ends = h.agentPayloads('agent_run_end');
      expect(ends.first['tokens'], 350);
      expect(h.stats.runEnds.last.tokens, 350);
    });

    test('usage null 降级：任一轮缺失 → 整 run「—」（tokenUsage null）', () async {
      final h = _Harness();
      h.chat.respond(_call(_toolCall('list_tables'), usage: null));
      h.chat.respond(
        _text(
          '完成',
          usage: const TokenUsage(
            promptTokens: 10,
            completionTokens: 5,
            totalTokens: 15,
          ),
        ),
      );

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列表');

      expect(h.runner.tokenUsage, isNull);
      final List<Map<String, dynamic>> ends = h.agentPayloads('agent_run_end');
      expect(ends.first.containsKey('tokens'), isFalse); // 键缺席（非 0）
      expect(h.stats.runEnds.last.tokens, isNull);
    });
  });

  group('seed 与消息流（§4.6 / §5.2 / D19）', () {
    test('seed 裁剪：跳过 toolCall/toolResult、保留 chat；本轮消息不进 seed', () async {
      final h = _Harness();
      // 预置历史：2 chat + 1 toolCall + 1 toolResult。
      h.sessionManager.addMessage(
        AiMessage(
          id: 'prev_u1',
          isUser: true,
          content: 'previous question',
          timestamp: DateTime.now(),
          type: AiMessageType.chat,
        ),
      );
      h.sessionManager.addMessage(
        AiMessage(
          id: 'prev_a1',
          isUser: false,
          content: 'previous answer',
          timestamp: DateTime.now(),
          type: AiMessageType.chat,
        ),
      );
      h.sessionManager.addMessage(
        AiMessage(
          id: 'prev_tc',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.toolCall,
          toolName: 'legacy_tool',
          toolResultSummary: 'legacy result payload',
        ),
      );
      h.chat.respond(_text('hi'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '新问题');

      final _ChatRequest req = h.chat.requests.first;
      final String flat = req.history
          .map((Map<String, dynamic> m) => '${m['role']}:${m['content']}')
          .join('|');
      expect(flat, contains('previous question'));
      expect(flat, contains('previous answer'));
      expect(flat, isNot(contains('legacy_tool')));
      expect(flat, isNot(contains('legacy result payload')));
      // 本轮用户消息不进 seed（裁剪产物），只作为运行消息列末条出现一次。
      expect('新问题'.allMatches(flat).length, 1);
      expect(req.history.last['role'], 'user');
      expect(req.history.last['content'], '新问题');
      expect(req.message, '');

      // 系统提示词：身份 + 上下文注入（run 快照）。
      final String prompt = req.systemPrompt ?? '';
      expect(prompt, contains('workbench agent'));
      expect(prompt, contains('mysql'));
      expect(prompt, contains('测试连接'));
      expect(prompt, contains('db1'));

      // 工具目录：T28 A2 合龙 + T4 三工具后 17 工具全量。
      expect(req.tools, hasLength(17));
      expect(
        h.chat.requests.first.tools!.map(
          (Map<String, dynamic> t) =>
              (t['function'] as Map<String, dynamic>)['name'],
        ),
        containsAll(<String>['execute_readonly_sql', 'get_current_context']),
      );
    });

    test(
      '协议形态：round2 history = seed + user + assistant(tool_calls) + tool',
      () async {
        final h = _Harness();
        h.chat.respond(_call(_toolCall('list_tables')));
        h.chat.respond(_text('完成'));

        await h.runner.start(uiPort: _noopUiPort, userMessage: '列表');

        expect(h.chat.callCount, 2);
        final List<Map<String, dynamic>> hist = h.chat.requests[1].history;
        expect(hist.first['role'], 'user');
        expect(hist.first['content'], '列表');
        final Map<String, dynamic> assistant = hist[hist.length - 2];
        expect(assistant['role'], 'assistant');
        final List<dynamic> toolCalls =
            assistant['tool_calls'] as List<dynamic>;
        expect(toolCalls, hasLength(1));
        final Map<String, dynamic> toolMsg = hist.last;
        expect(toolMsg['role'], 'tool');
        expect(
          toolMsg['tool_call_id'],
          (toolCalls.first as Map<String, dynamic>)['id'],
        );
        final Map<String, dynamic> feed =
            jsonDecode(toolMsg['content'] as String) as Map<String, dynamic>;
        expect(feed['ok'], isTrue);
        expect(feed, contains('rowCount'));
      },
    );

    test('锚点消息结构（§5.2）：kind/runId/goal/contextSnapshot 四键', () async {
      final h = _Harness(maxSteps: 7);
      h.chat.respond(_text('完成'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '看看库结构');

      final List<Map<String, dynamic>> anchors = h.agentPayloads('agent_run');
      expect(anchors, hasLength(1));
      expect(anchors.first['runId'], h.runner.activeRunId);
      expect(anchors.first['goal'], '看看库结构');
      final Map<String, dynamic> snapshot =
          anchors.first['contextSnapshot'] as Map<String, dynamic>;
      expect(snapshot['conn'], '测试连接');
      expect(snapshot['db'], 'db1');
      expect(snapshot['readOnly'], isFalse);
      expect(snapshot['maxSteps'], 7); // 终局可自锚点恢复上限（中断态）
      // 落账序：用户消息 → 锚点 → … → 终局。
      final List<String> ids = h.messages.map((AiMessage m) => m.id).toList();
      expect(
        ids.indexOf('agent_u_${h.runner.activeRunId}'),
        lessThan(ids.indexOf('agent_anchor_${h.runner.activeRunId}')),
      );
    });

    test('步消息落账：executor 产 call/result 对经 runner 落会话（D2）', () async {
      final h = _Harness();
      h.chat.respond(_call(_toolCall('list_tables')));
      h.chat.respond(_text('完成'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列表');

      expect(h.runner.stepsUsed, 1);
      final List<Map<String, dynamic>> steps = h.agentPayloads('agent_step');
      expect(steps, hasLength(1));
      expect(steps.first['tool'], 'list_tables');
      expect(steps.first['stepNo'], 1);
      expect(steps.first['runId'], h.runner.activeRunId);
      expect(
        h.messages.any((AiMessage m) => m.type == AiMessageType.toolCall),
        isTrue,
      );
    });

    test('快照不漂移（D15/AC7.2）：运行中改上下文源不影响已发快照', () async {
      final h = _Harness();
      h.chat.respond(_call(_toolCall('list_tables')));
      h.chat.respond(_text('完成'));

      unawaited(
        h.runner.start(uiPort: _noopUiPort, userMessage: '列表', gates: h.gates),
      );
      await _flush();

      // 运行中改解析源（模拟切侧栏/切 tab）。
      h.ctxHolder.value = AgentRunContext(
        runId: 'pending',
        connectionId: 'conn-OTHER',
        connectionName: '另一个连接',
        databaseName: 'other_db',
        dbType: DatabaseType.postgresql,
        readOnly: true,
      );
      await _flush();

      expect(h.runner.status, AgentRunStatus.completed);
      expect(h.gate.seenRunCtx, isNotEmpty);
      for (final AgentRunContext seen in h.gate.seenRunCtx) {
        expect(seen.connectionId, 'conn-1'); // 全程只读启动快照
        expect(seen.dbType, DatabaseType.mysql);
        expect(seen.readOnly, isFalse);
      }
      // T1（reviewer P3-3，T2 补断言）：T1 批新增的 `_DbSpy.getTablesDatabases`
      // 记录字段此前只记录无断言——此处钉住 loop 级 list_tables 调用收到的
      // 库名序列 = run 快照库 db1（executor 经快照 runCtx 把库名传导到 db
      // 访问面，非空序列亦证明记录字段真被写入）。
      expect(h.db.getTablesDatabases, <String?>['db1']);
    });

    test('Fix-J 提示词：缺 database 注入缺失引导（en）——指向顶部上下文芯片，'
        '明确禁止指引侧栏树选库', () async {
      final h = _Harness();
      h.ctxHolder.value = AgentRunContext(
        runId: 'pending',
        connectionId: 'conn-1',
        connectionName: '测试连接',
        databaseName: null,
        dbType: DatabaseType.mysql,
        readOnly: false,
      );
      h.chat.respond(_text('hi'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列出表');

      final String prompt = h.chat.requests.first.systemPrompt ?? '';
      expect(prompt, contains('database: -'), reason: '缺库如实呈现（AC7.4）');
      expect(prompt, contains('Missing-context guidance'));
      expect(prompt, contains('context chip'));
      expect(prompt, contains('context picker'));
      expect(
        prompt,
        contains('never direct the user to the sidebar tree'),
        reason: '掐断「请先在侧边栏选中一个 database」误导指引',
      );
    });

    test('Fix-J 提示词：缺 database 注入缺失引导（zh 双语同步）', () async {
      final h = _Harness(locale: 'zh');
      h.ctxHolder.value = AgentRunContext(
        runId: 'pending',
        connectionId: 'conn-1',
        connectionName: '测试连接',
        databaseName: null,
        dbType: DatabaseType.mysql,
        readOnly: false,
      );
      h.chat.respond(_text('hi'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列出表');

      final String prompt = h.chat.requests.first.systemPrompt ?? '';
      expect(prompt, contains('上下文缺失引导'));
      expect(prompt, contains('上下文芯片'));
      expect(prompt, contains('上下文选择器'));
      expect(prompt, contains('不要指引用户去侧边栏树选库'));
    });

    test('Fix-J 提示词：database 已设置时不注入缺失引导（条件注入）', () async {
      final h = _Harness(); // 默认快照 databaseName='db1'
      h.chat.respond(_text('hi'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列出表');

      final String prompt = h.chat.requests.first.systemPrompt ?? '';
      expect(prompt, contains('database: db1'));
      expect(prompt, isNot(contains('Missing-context guidance')));
      // 修订（T2 方案 B）：原「isNot(contains('context chip'))」断言翻转——
      // 行为规则 8 恒在（上下文缺失不得调数据工具、指 context chip 设置），
      // 「context chip」不再是缺失引导独有锚点；条件注入面改用引导段落标题
      // 'Missing-context guidance' 锚定。
    });

    test('P3-1 提示词：databaseName 空串同视为未设置——注入缺失引导且 '
        'database 行渲染 -（与 gate ②b 谓词同语义）', () async {
      final h = _Harness();
      h.ctxHolder.value = AgentRunContext(
        runId: 'pending',
        connectionId: 'conn-1',
        connectionName: '测试连接',
        databaseName: '',
        dbType: DatabaseType.mysql,
        readOnly: false,
      );
      h.chat.respond(_text('hi'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '列出表');

      final String prompt = h.chat.requests.first.systemPrompt ?? '';
      expect(
        prompt,
        contains('database: -'),
        reason: '空串不得渲染为空 context 行（P3-1 旧行为）',
      );
      expect(prompt, contains('Missing-context guidance'));
      expect(prompt, contains('context chip'));
      expect(prompt, contains('context picker'));
    });
  });

  group('停止契约与复位（§6.4 / D12 / D17 / AC2.3 / AC8.5）', () {
    test('resetSteps 接线：新 run 计步归零（AC2.3 对账）+ 新 runId', () async {
      final h = _Harness();
      h.chat.respond(
        ChatResponse(
          content: null,
          toolCalls: <AiToolCall>[_toolCall('list_tables')],
        ),
      );
      h.chat.respond(_text('第一轮完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: '第一轮');
      final String? run1 = h.runner.activeRunId;
      expect(h.runner.stepsUsed, 1);

      h.chat.respond(_text('第二轮完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: '第二轮');

      expect(h.runner.activeRunId, isNot(run1)); // 新 runId
      expect(h.runner.stepsUsed, 0); // 对账归零
      expect(h.agentPayloads('agent_run'), hasLength(2)); // 两锚点
    });

    test('Fix-F ④：start 同步清 result_ref 注册表（不等下个 execute 惰性切换）', () async {
      final h = _Harness();
      // run1：execute_readonly_sql 产 row 形态结果 → 注册 res_1（T28 挂点）。
      h.chat.respond(
        _call(
          _toolCall('execute_readonly_sql', <String, dynamic>{
            'sql': 'SELECT * FROM users',
          }),
        ),
      );
      h.chat.respond(_text('第一轮完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: '第一轮');
      expect(h.executor.resultRefOf('res_1'), isNotNull, reason: 'run1 注册表在册');

      // run2 无工具调用（纯文本终局）——若清理仍靠下个 execute 的 runId
      // 惰性切换，run2 全程注册表都会留着 run1 的 res_1；start 同步序言
      // 清理（resetSteps 同挂点）则在首个 await 前即空。
      h.chat.respond(_text('第二轮完成'));
      final Future<void> second = h.runner.start(
        uiPort: _noopUiPort,
        userMessage: '第二轮',
      );
      expect(
        h.executor.resultRefOf('res_1'),
        isNull,
        reason: 'start 同步序言即清（空窗期同名 refId 不串 run）',
      );
      await second;
      expect(
        h.executor.resultRefOf('res_1'),
        isNull,
        reason: 'run2 无数据工具，注册表保持空（T09 跨 run 契约）',
      );
    });

    test('账本跨 run 保留：approvedForSession 落账，新 run 不清空（D12）', () async {
      final h = _Harness();
      h.gate.confirmL05(
        const ReadImpactAnalysis(
          estimatedRows: 1,
          fullScan: false,
          analysisUnavailable: false,
        ),
      );
      h.chat.respond(
        _call(
          _toolCall('execute_readonly_sql', <String, dynamic>{
            'sql': 'SELECT * FROM users',
          }),
        ),
      );
      h.chat.respond(_text('第一轮完成'));

      unawaited(
        h.runner.start(uiPort: _noopUiPort, userMessage: '第一轮', gates: h.gates),
      );
      await _flush();
      expect(h.runner.status, AgentRunStatus.awaitingUser);
      h.cardCompleter.complete(GateCardResult.approvedForSession);
      await _flush();
      expect(h.runner.status, AgentRunStatus.completed);

      // executor 真实 confirm 链已把连接记入账本。
      expect(h.runner.ledger.l05Allowed.contains('conn-1'), isTrue);

      h.chat.respond(_text('第二轮完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: '第二轮');
      expect(h.runner.ledger.l05Allowed.contains('conn-1'), isTrue); // 保留
    });

    test('D17 守卫：运行中再 start 静默拒绝（无第二 run、无重复消息）', () async {
      final h = _Harness();
      final Completer<ChatResponse> round1 = Completer<ChatResponse>();
      h.chat.queue.add(() => round1.future);

      unawaited(
        h.runner.start(uiPort: _noopUiPort, userMessage: '第一问', gates: h.gates),
      );
      await _flush();
      final String? run1 = h.runner.activeRunId;
      final int msgCount = h.messages.length;

      await h.runner.start(uiPort: _noopUiPort, userMessage: '第二问'); // 应被拒绝
      await _flush();

      expect(h.runner.activeRunId, run1);
      expect(h.chat.callCount, 1);
      expect(h.messages.length, msgCount);

      round1.complete(_text('完成'));
      await _flush();
      expect(h.runner.status, AgentRunStatus.completed);
    });

    test('会话切换复位：idle + 账本清空 + 在途门卡 rejected + 无终局消息', () async {
      final h = _Harness();
      h.runner.ledger.allowL05('conn-1'); // 预置放行验证清空
      h.gate.confirmL05(
        const ReadImpactAnalysis(
          estimatedRows: null,
          fullScan: false,
          analysisUnavailable: true,
        ),
      );
      h.chat.respond(
        _call(
          _toolCall('execute_readonly_sql', <String, dynamic>{
            'sql': 'SELECT * FROM big_table',
          }),
        ),
      );

      unawaited(
        h.runner.start(uiPort: _noopUiPort, userMessage: '等卡', gates: h.gates),
      );
      await _flush();
      expect(h.runner.status, AgentRunStatus.awaitingUser);

      h.runner.resetForSessionSwitch();
      await _flush();

      expect(h.runner.status, AgentRunStatus.idle);
      expect(h.runner.isRunning, isFalse);
      expect(h.runner.activeRunId, isNull);
      expect(h.runner.ledger.l05Allowed, isEmpty);
      // 无终局消息（旧 run 静默退出——终局不应落进切换后的会话）。
      expect(h.agentPayloads('agent_run_end'), isEmpty);
      // 在途门卡以 rejected 解决：卡面结论回填（已随运行取消态数据位）。
      expect(h.agentPayloads('agent_confirm').first['outcome'], 'rejected');
      expect(h.chat.callCount, 1); // 不再发起新轮
    });

    test('运行启动统计：sessionStart + activeDay 各一次（§6.1）', () async {
      final h = _Harness();
      h.chat.respond(_text('完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: '你好');
      expect(h.stats.sessionStarts, 1);
      expect(h.stats.activeDays, 1);
      expect(h.stats.runEnds, hasLength(1));
    });

    test('gates 为 null：confirm 档 fail-closed（T10 契约接线）', () async {
      final h = _Harness();
      h.gate.confirmL05(
        const ReadImpactAnalysis(
          estimatedRows: null,
          fullScan: false,
          analysisUnavailable: true,
        ),
      );
      h.chat.respond(_call(_toolCall('list_tables')));
      h.chat.respond(_text('完成'));

      await h.runner.start(
        uiPort: _noopUiPort,
        userMessage: '无门卡回调',
      ); // gates 缺省

      // fail-closed：GATE_REJECTED 步消息落账，零执行，run 继续（回喂自纠）。
      expect(h.db.getTablesCalls, 0);
      expect(h.runner.status, AgentRunStatus.completed);
      expect(
        h.messages.any(
          (AiMessage m) =>
              m.toolResultSummary?.contains('GATE_REJECTED') ?? false,
        ),
        isTrue,
      );
    });
  });

  group('Fix-B 中-1：execute 链异常兜底（runner try-catch）', () {
    test('execute 抛出 → 兜底失败步（审计 blocked + 步消息对）→ run 继续，状态不卡死', () async {
      final h = _Harness();
      h.gate.failWith(StateError('gate evaluation crashed'));
      h.chat.respond(_call(_toolCall('list_tables')));
      h.chat.respond(_text('自纠后完成'));

      await h.runner.start(uiPort: _noopUiPort, userMessage: '查表');

      // 异常不冒穿 _runLoop：run 正常收敛 completed（isRunning 翻 false）。
      expect(h.runner.status, AgentRunStatus.completed);
      expect(h.runner.isRunning, isFalse);
      expect(h.runner.stepsUsed, 1); // 计步在 execute 入口已完成
      // 审计兜底：该步恰一条（AC13.1），blocked + success=false 形态。
      expect(h.auditRecords, hasLength(1));
      expect(h.auditRecords.single['gateDecision'], AgentGateDecision.blocked);
      expect(h.auditRecords.single['success'], isFalse);
      expect(h.auditRecords.single['step'], 1);
      expect(h.auditRecords.single['tool'], 'list_tables');
      // 步消息对落账（EXECUTION_FAILED 形态，模型可自纠回喂）。
      final steps = h.agentPayloads('agent_step');
      expect(steps, hasLength(1));
      final error = steps.first['error'] as Map<dynamic, dynamic>;
      expect(error['code'], AgentToolErrorCodes.executionFailed);
      expect(
        h.messages.any((AiMessage m) => m.type == AiMessageType.toolCall),
        isTrue,
        reason: 'call 半条同样落账（步消息对完整）',
      );
    });

    test(
      'execute 连续抛出 → D18 失败计数收敛 stoppedByFailures（isRunning false）',
      () async {
        final h = _Harness();
        for (int i = 0; i < 5; i++) {
          h.gate.failWith(StateError('crash $i'));
          h.chat.respond(_call(_toolCall('list_tables')));
        }

        await h.runner.start(uiPort: _noopUiPort, userMessage: '连环崩');

        expect(h.runner.status, AgentRunStatus.stoppedByFailures);
        expect(h.runner.isRunning, isFalse);
        // 每个异常步恰好一条兜底审计（不变式贯穿连环异常）。
        expect(h.auditRecords, hasLength(5));
        expect(
          h.agentPayloads('agent_run_end').first['status'],
          'stoppedByFailures',
        );
      },
    );
  });

  group('Fix-B 低-1：execute 返回后的代数检查（跨会话不污染）', () {
    test('execute 在途会话切换 → 返回后步消息不写进新会话', () async {
      final h = _Harness();
      final Completer<List<String>> slow = Completer<List<String>>();
      h.db.getTablesGate = slow; // 在途步门控（execute 挂在 db future 上）
      h.chat.respond(_call(_toolCall('list_tables')));

      unawaited(h.runner.start(uiPort: _noopUiPort, userMessage: '在途'));
      await _flush(); // chat 已返回 tool_call，execute 在途

      // 会话切换（manager 换轨 + runner 复位——provider 接线路径的两步）。
      h.sessionManager.createSession(title: 'new session');
      h.runner.resetForSessionSwitch();
      await _flush();
      expect(h.messages, isEmpty, reason: '新会话为空');

      // 在途 execute 迟到返回：旧 run 步消息不得落进新会话。
      slow.complete(<String>['users']);
      await _flush();

      expect(h.messages, isEmpty, reason: '低-1：旧 run 步消息不写进新会话');
      expect(h.runner.status, AgentRunStatus.idle);
      expect(h.chat.callCount, 1, reason: '旧 run 静默退出，不再发起新轮');
    });
  });

  group('T4 系统提示词记忆块', () {
    AiMemoryItem memItem(
      String id,
      AiMemoryScope scope, {
      String? subject,
      String content = 'note',
      int updatedAt = 1,
    }) => AiMemoryItem(
      id: id,
      scope: scope,
      connectionId: scope == AiMemoryScope.connection ? 'conn-1' : null,
      subject: subject,
      content: content,
      createdAt: updatedAt,
      updatedAt: updatedAt,
    );

    test('有记忆：全局 + 锁定连接两段注入，含 subject/content 行', () async {
      final h = _Harness(
        memoryResolver: (String? connectionId) async => AgentMemorySnapshot(
          global: <AiMemoryItem>[
            memItem(
              'g1',
              AiMemoryScope.global,
              subject: 'team',
              content: '金额列单位是分',
            ),
          ],
          connection: <AiMemoryItem>[
            memItem(
              'c1',
              AiMemoryScope.connection,
              subject: 'orders.status',
              content: 'status=3 已支付',
            ),
          ],
        ),
      );
      h.chat.respond(_text('完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: '看订单');

      final String prompt = h.chat.requests.single.systemPrompt ?? '';
      expect(prompt, contains('Known memories'));
      expect(prompt, contains('Global memories:'));
      expect(prompt, contains('Locked-connection memories:'));
      expect(prompt, contains('- [team] 金额列单位是分'));
      expect(prompt, contains('- [orders.status] status=3 已支付'));
      // 上下文段与行为规则仍在（记忆块插在两者之间）。
      expect(prompt, contains('locked connection'));
      expect(prompt, contains('Behavior rules:'));
    });

    test('无记忆：整段省略（零占位噪音）', () async {
      final h = _Harness(
        memoryResolver: (String? connectionId) async =>
            const AgentMemorySnapshot(),
      );
      h.chat.respond(_text('完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: 'hi');

      final String prompt = h.chat.requests.single.systemPrompt ?? '';
      expect(prompt, isNot(contains('Known memories')));
      expect(prompt, contains('Behavior rules:'));
    });

    test('超限截断：预算 2000 字符按序保最新，省略标记收尾', () async {
      // 30 条 × ~110 字符 ≈ 3300 字符 → 必须截断。
      final List<AiMemoryItem> many = <AiMemoryItem>[
        for (int i = 0; i < 30; i++)
          memItem(
            'g$i',
            AiMemoryScope.global,
            subject: 't.c$i',
            content: 'fact-$i ${'x' * 90}',
            updatedAt: i,
          ),
      ];
      final h = _Harness(
        memoryResolver: (String? connectionId) async =>
            AgentMemorySnapshot(global: many),
      );
      h.chat.respond(_text('完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: 'hi');

      final String prompt = h.chat.requests.single.systemPrompt ?? '';
      final int start = prompt.indexOf('Known memories');
      final int end = prompt.indexOf('Behavior rules:');
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final String block = prompt.substring(start, end);
      expect(block.length, lessThanOrEqualTo(2000 + 2)); // 段间换行
      expect(block, contains('- …'));
      expect(block, isNot(contains('fact-29'))); // 最旧被截掉
    });

    test('行为规则含记忆指引行（save_memory / list_memories 查重）', () async {
      final h = _Harness(
        memoryResolver: (String? connectionId) async =>
            const AgentMemorySnapshot(),
      );
      h.chat.respond(_text('完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: 'hi');

      final String prompt = h.chat.requests.single.systemPrompt ?? '';
      expect(prompt, contains('save_memory'));
      expect(prompt, contains('list_memories'));
    });

    test('zh locale：记忆块与指引行中文化', () async {
      final h = _Harness(
        locale: 'zh',
        memoryResolver: (String? connectionId) async => AgentMemorySnapshot(
          connection: <AiMemoryItem>[
            memItem(
              'c1',
              AiMemoryScope.connection,
              subject: 'orders.status',
              content: 'status=3 已支付',
            ),
          ],
        ),
      );
      h.chat.respond(_text('完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: '看订单');

      final String prompt = h.chat.requests.single.systemPrompt ?? '';
      expect(prompt, contains('已知记忆'));
      expect(prompt, contains('当前连接记忆：'));
      expect(prompt, contains('- [orders.status] status=3 已支付'));
      expect(prompt, contains('save_memory 沉淀'));
    });

    test('记忆解析抛错 → 降级空态，run 照常完成', () async {
      final h = _Harness(
        memoryResolver: (String? connectionId) =>
            Future<AgentMemorySnapshot>.error(StateError('prefs down')),
      );
      h.chat.respond(_text('完成'));
      await h.runner.start(uiPort: _noopUiPort, userMessage: 'hi');

      expect(h.runner.status, AgentRunStatus.completed);
      final String prompt = h.chat.requests.single.systemPrompt ?? '';
      expect(prompt, isNot(contains('Known memories')));
    });
  });
}
