// T14 provider 级测试（tasks-ai-agent.md T14 / design-ai-agent §2.3、D12、
// D15、D17、AC1.3、AC7.4、AC8.5）。
//
// 覆盖：agentRunner 装配与构造注入优先 / 默认装配可运行（未知 provider
// 同步抛错 → failed 终局收敛，不触网不悬挂）/ reader 注入流到 run 快照与
// chat 配置 / 会话切换在途复位 + 账本清空 / 消息追加不误杀 / 锁定变更清
// 账本（D12）/ D17 isRunning 守卫 / requestStop 即时收敛 / 无上下文纯对话
// + CONTEXT_REQUIRED 数据形状（AC7.4）。
//
// 注入式 runner 沿 agent_loop_runner_test 的依赖注入模式（脚本化 chat +
// 真实 executor + spy 闭包，NF5.3）；默认装配用例经真实 AiService 路径的
// 「Unsupported provider」快速失败驱动（无网络依赖）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/ai_message_type.dart'
    show AiMessageStatus, AiMessageType;
import 'package:dbmaster/models/ai_models.dart' show AiToolCall, ChatResponse;
import 'package:dbmaster/models/database_models.dart'
    show AiMessage, DatabaseType, DbColumn, DbIndex, ForeignKey;
import 'package:dbmaster/models/query_optimizer/execution_plan.dart'
    show PerformanceReport;
import 'package:dbmaster/providers/ai_panel_provider.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentGate, AgentRunContext;
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show AgentGateAnalysis;
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart'
    show AgentDbAccess, AgentToolExecutor;
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort;
import 'package:dbmaster/services/ai/ai_session_manager.dart'
    show AiSessionManager;
import 'package:dbmaster/services/query_settings_service.dart'
    show QuerySettingsService;

// ── 脚本化 chat（沿 agent_loop_runner_test 的 _ChatScript 模式精简） ──────────

ChatResponse _text(String content) => ChatResponse(content: content);

AiToolCall _toolCall(String name, Map<String, dynamic> args) => AiToolCall(
  id: 'call_${_toolCallSeq++}',
  type: 'function',
  functionName: name,
  functionArguments: jsonEncode(args),
);

int _toolCallSeq = 0;

ChatResponse _call(AiToolCall call) =>
    ChatResponse(content: '', toolCalls: <AiToolCall>[call]);

class _ChatScript {
  final List<String> seenProviders = <String>[];
  final List<String?> seenSystemPrompts = <String?>[];
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
    seenProviders.add(provider);
    seenSystemPrompts.add(systemPrompt);
    if (queue.isEmpty) {
      throw StateError('unexpected chat call');
    }
    return queue.removeAt(0)();
  }

  void respond(ChatResponse resp) => queue.add(() async => resp);

  void blockOn(Completer<ChatResponse> gate) => queue.add(() => gate.future);
}

Future<void> _flush([int rounds = 8]) async {
  for (int i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ── 注入式测试台（真实 executor + 真实 gate + spy 闭包）────────────────────

class _AgentHarness {
  _AgentHarness({String connectionId = 'conn-1'})
    : sessionManager = AiSessionManager(),
      chat = _ChatScript() {
    sessionManager.createSession();
    runner = AgentLoopRunner(
      executor: AgentToolExecutor(
        gate: AgentGate(
          createAnalysis: (AgentRunContext runCtx) => AgentGateAnalysis(
            getExplainPlan: (String sql) async => <Map<String, dynamic>>[],
            rowThreshold: 10000,
            dbType: runCtx.dbType,
          ),
        ),
        db: AgentDbAccess(
          getTables: (String? connectionId, String? databaseName) async =>
              <String>['t1', 't2'],
          getTableColumns:
              (
                String tableName, {
                String? connectionId,
                String? databaseName,
              }) async => <DbColumn>[],
          getTableIndexes:
              (
                String tableName, {
                String? connectionId,
                String? databaseName,
              }) async => <DbIndex>[],
          getForeignKeys:
              (
                String tableName, {
                String? connectionId,
                String? databaseName,
              }) async => <ForeignKey>[],
          getCreateTableSql:
              (
                String tableName, {
                String? connectionId,
                String? databaseName,
              }) async => 'CREATE TABLE t1 (id INT)',
          getExplainPlan: (String sql, {String? connectionId}) async =>
              <Map<String, dynamic>>[],
          executeQuery:
              (String sql, {String? connectionId, String? database}) async =>
                  <Map<String, dynamic>>[
                    <String, dynamic>{'id': 1},
                  ],
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
      ),
      sessionManager: sessionManager,
      resolveRunContext: (String runId) => AgentRunContext(
        runId: runId,
        connectionId: connectionId.isEmpty ? null : connectionId,
        connectionName: connectionId.isEmpty ? null : '测试连接',
        databaseName: connectionId.isEmpty ? null : 'db1',
        dbType: DatabaseType.mysql,
        readOnly: false,
      ),
      resolveChatConfig: () => const AgentChatConfig(
        provider: 'scripted',
        model: 'm1',
        apiKey: 'k1',
      ),
      chat: chat.call,
    );
    provider = AiPanelProvider(
      sessionManager: sessionManager,
      agentRunner: runner,
    );
  }

  final AiSessionManager sessionManager;
  final _ChatScript chat;
  late final AgentLoopRunner runner;
  late final AiPanelProvider provider;

  List<AiMessage> get messages => sessionManager.currentMessages.toList();

  /// §5.2 agent 载荷（kind 过滤）。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('T14 装配与持有（design §2.2 末段）', () {
    test('默认装配：agentRunner 就位且 idle（构造不触网）', () {
      final provider = AiPanelProvider();
      expect(provider.agentRunner.isRunning, isFalse);
      expect(provider.agentRunner.status, AgentRunStatus.idle);
      expect(provider.agentRunner.ledger.l05Allowed, isEmpty);
      provider.dispose();
    });

    test('构造注入优先：与 orchestrator 同款持有方式', () {
      final h = _AgentHarness();
      expect(identical(h.provider.agentRunner, h.runner), isTrue);
      h.provider.dispose();
    });
  });

  group('T14 reader 注入（默认装配 runner，未知 provider 快速失败路径）', () {
    test('无 reader → 无上下文快照（AC7.4）+ failed 终局收敛不悬挂', () async {
      final provider = AiPanelProvider();
      // 无既有会话直发：runner.start 内部建会话的 notify 不得误伤刚就位的
      // activeRunId（会话切换检测的 idle 窗口回归守卫）。
      await provider.agentRunner.start(
        uiPort: const _NoopUiPort(),
        userMessage: 'hi',
      );

      expect(provider.agentRunner.status, AgentRunStatus.failed);
      expect(
        provider.agentRunner.activeRunId,
        isNotNull,
        reason: 'start 内部建会话不触发在途复位（idle 只清账本）',
      );
      final anchors = _payloadsOf(provider.aiMessages, 'agent_run');
      expect(anchors, hasLength(1));
      final snapshot =
          anchors.first['contextSnapshot'] as Map<dynamic, dynamic>;
      expect(snapshot['conn'], '', reason: '无上下文快照 conn 为空');
      expect(snapshot['db'], '');
      expect(snapshot['readOnly'], isFalse);
      final ends = _payloadsOf(provider.aiMessages, 'agent_run_end');
      expect(ends.first['status'], 'failed');
      provider.dispose();
    });

    test('context reader 注入 → 快照进锚点（D15 解析来源）', () async {
      final provider = AiPanelProvider();
      provider.agentContextSnapshotReader = () => (
        connectionId: 'c9',
        connectionName: '连接九',
        databaseName: 'db9',
        dbType: DatabaseType.postgresql,
        readOnly: true,
      );
      await provider.agentRunner.start(
        uiPort: const _NoopUiPort(),
        userMessage: 'hi',
      );

      final anchors = _payloadsOf(provider.aiMessages, 'agent_run');
      final snapshot =
          anchors.first['contextSnapshot'] as Map<dynamic, dynamic>;
      expect(snapshot['conn'], '连接九');
      expect(snapshot['db'], 'db9');
      expect(snapshot['readOnly'], isTrue);
      provider.dispose();
    });

    test('chat config reader 注入 → 配置流到 chat 调用（失败明细可辨识）', () async {
      final provider = AiPanelProvider();
      const bogus = AgentChatConfig(
        provider: '__no_such_provider__',
        model: 'm',
        apiKey: 'k',
      );
      provider.agentChatConfigReader = () => bogus;
      await provider.agentRunner.start(
        uiPort: const _NoopUiPort(),
        userMessage: 'hi',
      );

      expect(provider.agentRunner.status, AgentRunStatus.failed);
      final ends = _payloadsOf(provider.aiMessages, 'agent_run_end');
      final summaryText = ends.first['summaryText'];
      expect(summaryText, isA<String>());
      expect(
        summaryText! as String,
        contains('__no_such_provider__'),
        reason: 'reader 配置进入真实 chat 调用（Unsupported provider 可辨识）',
      );
      provider.dispose();
    });
  });

  group('T14 发送即启动 run（脚本化 tool_calls，AC 侧组件面）', () {
    test('start：用户消息/锚点/步消息对/终局落同一会话账本', () async {
      final h = _AgentHarness();
      h.chat.respond(_call(_toolCall('list_tables', <String, dynamic>{})));
      h.chat.respond(_text('库里有 t1 和 t2'));

      await h.provider.agentRunner.start(
        uiPort: const _NoopUiPort(),
        userMessage: '看看有哪些表',
      );

      expect(h.runner.status, AgentRunStatus.completed);
      expect(h.runner.stepsUsed, 1);
      final ids = h.messages.map((AiMessage m) => m.id).toList();
      expect(ids, contains(startsWith('agent_u_')), reason: '用户消息自落');
      expect(ids, contains(startsWith('agent_anchor_')), reason: '轨迹锚点');
      expect(ids, contains(startsWith('agent_tc_')), reason: '步消息 call 半条');
      expect(ids, contains(startsWith('agent_tr_')), reason: '步消息 result 半条');
      expect(ids, contains(startsWith('agent_end_')), reason: '终局');
      final user = h.messages.firstWhere(
        (AiMessage m) => m.id.startsWith('agent_u_'),
      );
      expect(user.isUser, isTrue);
      expect(user.content, '看看有哪些表');
      final steps = h.agentPayloads('agent_step');
      expect(steps, hasLength(1));
      expect(steps.first['tool'], 'list_tables');
      expect(steps.first['summary'], contains('2 table'));
      h.provider.dispose();
    });
  });

  group('T14 停止与 D17 守卫（注入式）', () {
    test('requestStop 即时：同步进 stopping，终局 stoppedByUser', () async {
      final h = _AgentHarness();
      final Completer<ChatResponse> round1 = Completer<ChatResponse>();
      h.chat.blockOn(round1);
      unawaited(
        h.runner.start(uiPort: const _NoopUiPort(), userMessage: '慢一点'),
      );
      await _flush();

      expect(h.runner.status, AgentRunStatus.running);
      h.runner.requestStop();
      expect(h.runner.status, AgentRunStatus.stopping, reason: '停止即时（同步态翻转）');

      round1.complete(_text('late'));
      await _flush();
      expect(h.runner.status, AgentRunStatus.stoppedByUser);
      final ends = h.agentPayloads('agent_run_end');
      expect(ends.first['status'], 'stoppedByUser');
      h.provider.dispose();
    });

    test('D17：运行中第二次 start 静默拒绝（不产生并行第二运行）', () async {
      final h = _AgentHarness();
      final Completer<ChatResponse> round1 = Completer<ChatResponse>();
      h.chat.blockOn(round1);
      unawaited(h.runner.start(uiPort: const _NoopUiPort(), userMessage: '一'));
      await _flush();
      final firstRunId = h.runner.activeRunId;
      expect(firstRunId, isNotNull);

      await h.runner.start(uiPort: const _NoopUiPort(), userMessage: '二');
      expect(h.runner.activeRunId, firstRunId);
      expect(
        h.messages.where((AiMessage m) => m.isUser).length,
        1,
        reason: '第二次 start 不落用户消息',
      );

      round1.complete(_text('done'));
      await _flush();
      expect(h.runner.status, AgentRunStatus.completed);
      h.provider.dispose();
    });
  });

  group('T14 会话切换与账本（provider 接线，AC8.5/D12）', () {
    test('会话切换在途复位：idle + 账本清空 + 终局不落新会话', () async {
      final h = _AgentHarness();
      final Completer<ChatResponse> round1 = Completer<ChatResponse>();
      h.chat.blockOn(round1);
      unawaited(h.runner.start(uiPort: const _NoopUiPort(), userMessage: '跑着'));
      await _flush();
      h.runner.ledger.allowL05('conn-1');
      expect(h.runner.ledger.l05Allowed, isNotEmpty);

      h.provider.createNewSession(title: 'next session');
      await _flush();

      expect(h.runner.status, AgentRunStatus.idle, reason: '在途 run 复位');
      expect(h.runner.isRunning, isFalse);
      expect(h.runner.activeRunId, isNull);
      expect(h.runner.ledger.l05Allowed, isEmpty, reason: '账本清空（D12）');
      expect(h.messages, isEmpty, reason: '新会话不接旧终局');

      // 旧 run 的挂起 chat 迟到返回：代数不等静默退出，不产生终局/崩溃。
      round1.complete(_text('late'));
      await _flush();
      expect(h.messages, isEmpty);
      expect(h.runner.status, AgentRunStatus.idle);
      h.provider.dispose();
    });

    test('运行中消息落地不误杀（sessionManager 逐消息 notify）', () async {
      final h = _AgentHarness();
      final Completer<ChatResponse> round1 = Completer<ChatResponse>();
      h.chat.blockOn(round1);
      unawaited(h.runner.start(uiPort: const _NoopUiPort(), userMessage: '跑着'));
      await _flush();

      h.provider.addAiMessage(
        AiMessage(
          id: 'outside_1',
          isUser: true,
          content: '旁路消息',
          timestamp: DateTime.now(),
        ),
      );
      await _flush();
      expect(h.runner.isRunning, isTrue, reason: '消息追加不是会话切换');

      round1.complete(_text('done'));
      await _flush();
      expect(h.runner.status, AgentRunStatus.completed);
      h.provider.dispose();
    });

    test('lockWorkbenchContext / unlock 变更清账本（D12）', () {
      final h = _AgentHarness();
      h.runner.ledger.allowL05('conn-1');
      expect(h.runner.ledger.l05Allowed, isNotEmpty);

      h.provider.lockWorkbenchContext('conn-1', 'db1');
      expect(h.runner.ledger.l05Allowed, isEmpty, reason: '锁定变更清放行');

      h.runner.ledger.allowL05('conn-1');
      h.provider.unlockWorkbenchContext();
      expect(h.runner.ledger.l05Allowed, isEmpty, reason: '解锁同样清放行');
      h.provider.dispose();
    });
  });

  group('T14 无上下文纯对话 + CONTEXT_REQUIRED（AC7.4 数据形状）', () {
    test('数据工具在无上下文快照上被 ②a 拦截 → 修订（T2 方案 B）：运行立即终止 '
        'stoppedByContext（终局引导选库，不再回喂继续）', () async {
      final h = _AgentHarness(connectionId: '');
      h.chat.respond(
        _call(
          _toolCall('execute_readonly_sql', <String, dynamic>{
            'sql': 'SELECT 1',
          }),
        ),
      );
      h.chat.respond(_text('不应到达')); // 终止后不再发起下一轮

      await h.provider.agentRunner.start(
        uiPort: const _NoopUiPort(),
        userMessage: '查一下',
      );

      final steps = h.agentPayloads('agent_step');
      expect(steps, hasLength(1));
      final error = steps.first['error'] as Map<dynamic, dynamic>;
      expect(error['code'], 'CONTEXT_REQUIRED', reason: 'AC7.4 运行时出口错误码');
      expect(h.runner.status, AgentRunStatus.stoppedByContext);
      final ends = h.agentPayloads('agent_run_end');
      expect(ends.first['status'], 'stoppedByContext');
      expect(
        h.chat.seenProviders,
        hasLength(1),
        reason: '不回喂继续（无第二轮）',
      );
      expect(h.messages.last.content, contains('context chip'));
      h.provider.dispose();
    });
  });

  group('Fix-B P2-3：L0.5 阈值翻转经装配面即时生效（AC8.7 字面）', () {
    test('设置修改后下一个 run 首次判定用新阈值（start await 点同步刷新）', () async {
      // 初始设置 20000 → 默认装配 provider（构造预热读该值）。
      SharedPreferences.setMockInitialValues(<String, Object>{
        'agent_l05_row_threshold': 20000,
      });
      final provider = AiPanelProvider();
      await _flush();
      expect(provider.agentL05ThresholdForTest, 20000, reason: '构造预热');

      // 用户改设置（设置 UI 写 prefs）→ 发新消息（run 启动）。
      await QuerySettingsService().setAgentL05RowThreshold(5000);
      // 无 chat reader → failed 终局（不触网）；但 start 的 resolveMaxSteps
      // await 点（P2-3 刷新挂点）已同步完成——修复前该值仍为 20000。
      await provider.agentRunner.start(
        uiPort: const _NoopUiPort(),
        userMessage: 'hi',
      );

      expect(
        provider.agentL05ThresholdForTest,
        5000,
        reason: 'AC8.7：修改后下次判定生效（run 启动即刷新，一步延迟消除）',
      );
      provider.dispose();
    });
  });
}

/// 消息流 agent 载荷提取（kind 过滤；独立于 harness 供默认装配用例复用）。
List<Map<String, dynamic>> _payloadsOf(
  List<AiMessage> messages,
  String kind,
) => messages
    .where(
      (AiMessage m) =>
          m.toolResultData?['agent'] is Map<String, dynamic> &&
          (m.toolResultData!['agent'] as Map<String, dynamic>)['kind'] == kind,
    )
    .map((AiMessage m) => m.toolResultData!['agent'] as Map<String, dynamic>)
    .toList();
