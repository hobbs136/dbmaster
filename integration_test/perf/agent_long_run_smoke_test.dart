// ============================================================================
// T32 长运行冒烟（NF1.3/1.4，tasks-ai-agent.md T32 / design-ai-agent.md §6.8 /
// design-ai-agent-ui.md §1.8-5、§10.4-12）。
//
// 沿 M1 T01 探针口径（integration_test/perf/tool_card_probe_test.dart）：
// SchedulerBinding.addTimingsCallback 收集 FrameTiming 算 P95（build+raster
// 合计口径）；ProcessInfo.currentRss 中位数采样 0→25→50 对照；程序驱动滚动
// （animateTo + 按帧步进泵动）；真实时钟安全上限 + 冲账补泵。
//
// 场景：脚本化 LLM（AgentChatFn 注入缝，沿 T18 唯一 mock 形态）构造 50+ 步
//       run——真实 AgentLoopRunner + AgentToolExecutor + AgentGate +
//       AgentGateAnalysis 生产链，dbAccess 六函数全脚本化合成数据（**不连
//       真实库**，T32 铁律），混合数据工具（list_tables / describe_table /
//       get_sample_data / 点查）+ 每 5 步一次 2500 行大结果（触发 D19 双上限
//       截断回喂）。宿主 = 生产同款消费路径（agentTrajectoryGrouping →
//       AgentTrajectoryCard(runner 注入实时态)，workbench_chat_view.dart:869
//       /:974 镜像）+ 40 条种子对话使对话流具真实滚动行程。
//
// 断言（任务书五项，判定门柱逐条，不放宽）：
//   ① 停止按钮即时响应：requestStop 同步翻转 stopping（§6.8 检查点语义）；
//      在途 chat 释放后有限时间内（30s bound）到 stoppedByUser 终态；
//      steps 不再增长（AC1.3 不派发新调用）；
//   ② 对话流滚动可用：运行中（挂起态）drag 响应 + 3 轮全程滚动往返；
//   ③ 轨迹卡卡体 ≤ 362 + 单一滚动区（§1.8-5 口径）：A 终局 50 步卡
//      stepsScrollKey ≤ 362（且 ≈360 钳生效）+ 卡内单 Scrollable + 内部滚动
//      可用 + 折叠态整卡 ≤ 362；B live 20 步卡同款断言（展开默认态）；
//   ④ ProcessInfo.currentRss 25 步 vs 50 步对照非超线性（M1 操作化：25→50
//      增量 ≤ 2× 0→25 增量；采样窗内只有步进本身——运行中交互检查全部
//      移至 B 的挂起态，避免一次性 UI 分配污染后半窗）；
//   ⑤ P95 帧耗时 ≤ 16.7ms（运行期 + 滚动期全样本，build+raster 合计）。
//
// 相位结构：Phase A = 50 步长运行（25 步对照门定格 RSS；终局后做卡几何 +
// 3 轮滚动腿）；Phase B = 20 步挂起（live 交互检查）→ requestStop → 收敛。
//
// 口径披露：
//   - 结论以 profile 模式为准（flutter drive --profile）；debug 数值仅相对
//     参考并在结论块标注 MODE；
//   - RDP 环境影响：远端会话（SESSIONNAME=RDP-*）下合成帧率与软件光栅可
//     拉高 raster 分量（M1 T01 曾实测 32Hz 伪影）——结论块输出 build/raster
//     分量 P95 供归属判读：raster 主导超限 → 环境伪影嫌疑；build 主导超限 →
//     真实构建成本，须升级复核（本脚本不自行放宽任何门柱）。
//
// 运行：
//   flutter test -d windows integration_test/perf/agent_long_run_smoke_test.dart
//   （debug 数值仅相对参考）
//   flutter drive --profile -d windows \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/perf/agent_long_run_smoke_test.dart
// ============================================================================

@Timeout(Duration(minutes: 25))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart'
    show kDebugMode, kProfileMode, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show FrameTiming, SchedulerBinding;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/ai_message_type.dart'
    show AiMessageStatus, AiMessageType;
import 'package:dbmaster/models/ai_models.dart'
    show AiToolCall, ChatResponse, TokenUsage;
import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart'
    show AiMessage, DatabaseType, DbColumn, DbIndex, ForeignKey;
import 'package:dbmaster/organisms/ai_workbench/agents/agent_trajectory_card.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentGate, AgentRunContext;
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show AgentGateAnalysis;
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart'
    show
        AgentChatConfig,
        AgentLoopRunner,
        AgentRunStatsCallbacks,
        AgentRunStatus;
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart'
    show AgentDbAccess, AgentToolExecutor;
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort;
import 'package:dbmaster/services/ai/ai_session_manager.dart'
    show AiSessionManager;
import 'package:dbmaster/theme/design_system.dart' show AppDesignSystem;

import '../helpers/ai_session_isolation_helper.dart';

void _log(Object message) {
  // ignore: avoid_print
  print(message);
}

// ---- 探针参数（任务书允许自决清单：脚本构成 / 采样时机）----------------------

/// 长运行步数（任务书：50 步以上）。
const int _longRunSteps = 50;

/// RSS 对照点（M1 口径：翻倍前 = 25）。
const int _memoryHalfSteps = 25;

/// 停止/交互用例步数（≥15 步保证 360 钳生效；20 步 + 在途挂起）。
const int _stopRunSteps = 20;

/// 脚本化 chat 每调用延迟（步落账摊开，产生增量帧样本）。
const Duration _chatLatency = Duration(milliseconds: 20);

/// 滚动驱动（M1 口径）：全程 ×3 轮，下探 easeOutCubic + 回卷 easeInCubic。
const int _rounds = 3;
const Duration _legDuration = Duration(milliseconds: 1200);

/// RSS 采样：中位数口径降噪（M1 同参）。
const int _rssSamples = 5;
const Duration _rssSampleInterval = Duration(milliseconds: 100);

/// 内存判据余量系数（M1 同值：25→50 增量 ≤ 2× 0→25 增量）。
const double _memoryLinearitySlack = 2.0;

/// 帧门柱（ui 规格 §1.8-5 / 任务书 T32，不放宽）。
const double _gateP95Ms = 16.7;

/// 停止收敛 bound（任务书①：requestStop 后**有限时间**内到终态）。
const Duration _stopBound = Duration(seconds: 30);

/// 大结果行数（触发 D19 截断；脚本化，不连库）。
const int _bigRowCount = 2500;

// ---- 脚本化 chat（唯一 mock：LLM chat 层，AgentChatFn 注入缝）───────────────

int _callSeq = 0;

AiToolCall _toolCall(String name, [Map<String, dynamic> args = const {}]) =>
    AiToolCall(
      id: 'call-perf-${_callSeq++}',
      type: 'function',
      functionName: name,
      functionArguments: jsonEncode(args),
    );

TokenUsage _usage(int step) {
  final int prompt = 420 + 36 * step;
  const int completion = 48;
  return TokenUsage(
    promptTokens: prompt,
    completionTokens: completion,
    totalTokens: prompt + completion,
  );
}

ChatResponse _toolResp(String name, Map<String, dynamic> args, int step) =>
    ChatResponse(
      content: '',
      toolCalls: <AiToolCall>[_toolCall(name, args)],
      usage: _usage(step),
    );

ChatResponse _finalResp(String text) => ChatResponse(
  content: text,
  toolCalls: const <AiToolCall>[],
  usage: _usage(_longRunSteps + 1),
);

/// 混合数据工具脚本：i%5 → list_tables / describe_table / get_sample_data /
/// 点查 / **大结果查询**（2500 行 → D19 双上限截断回喂）；末尾追加纯文本
/// 终局响应（tool_calls 空 → completed）。
List<ChatResponse> _scriptRun(int steps) => <ChatResponse>[
  for (var i = 1; i <= steps; i++)
    switch (i % 5) {
      1 => _toolResp('list_tables', <String, dynamic>{}, i),
      2 => _toolResp('describe_table', <String, dynamic>{
        'table': 'loop_small',
      }, i),
      3 => _toolResp('get_sample_data', <String, dynamic>{
        'table': 'loop_small',
      }, i),
      4 => _toolResp('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id, label FROM loop_small WHERE id = $i',
      }, i),
      _ => _toolResp('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id, payload, c2, c3, c4, c5, c6, c7 FROM loop_rows',
      }, i),
    },
  _finalResp('Done. $_longRunSteps steps executed over scripted data.'),
];

/// 脚本化 chat 队列：按调用序弹出；支持 ①25 步 RSS 对照门（运行挂起、内容
/// 定格）②停止用例挂起点（第 M 次调用挂起直至释放）。
class _ChatScript {
  final List<ChatResponse> _queue = <ChatResponse>[];
  int calls = 0;
  Duration latency = _chatLatency;

  int? gateAtCall;
  final Completer<void> _gate1 = Completer<void>();
  bool get gate1Reached =>
      gateAtCall != null && calls >= gateAtCall! && !_gate1.isCompleted;
  void releaseGate() {
    if (!_gate1.isCompleted) _gate1.complete();
  }

  int? holdAtCall;
  Completer<ChatResponse>? _hold;
  ChatResponse? _holdResponse;
  bool get holdPending =>
      holdAtCall != null &&
      calls >= holdAtCall! &&
      _hold != null &&
      !_hold!.isCompleted;
  void armHold(int callNo, ChatResponse releaseWith) {
    holdAtCall = callNo;
    _hold = Completer<ChatResponse>();
    _holdResponse = releaseWith;
  }

  void releaseHold() => _hold!.complete(_holdResponse!);

  void enqueueAll(Iterable<ChatResponse> responses) =>
      _queue.addAll(responses);

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
  }) async {
    calls++;
    if (gateAtCall != null && calls >= gateAtCall! && !_gate1.isCompleted) {
      await _gate1.future;
    }
    if (holdAtCall != null &&
        calls >= holdAtCall! &&
        _hold != null &&
        !_hold!.isCompleted) {
      return _hold!.future; // 停止用例：在途挂起，等 releaseHold
    }
    if (_queue.isEmpty) {
      throw StateError('AgentLongRunSmoke: unexpected chat call #$calls');
    }
    final ChatResponse resp = _queue.removeAt(0);
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    return resp;
  }
}

// ---- 脚本化 dbAccess（六函数全合成数据，不连真实库）────────────────────────

class _ScriptedDb {
  int queryCalls = 0;
  int explainCalls = 0;
  int bigResultQueries = 0;

  /// 点查 → const 计划（X1）；LIMIT → 小表 ALL（X2/R9 均不命中）；
  /// 其余（大结果查询）→ ALL rows=2500（< 10,000 阈值 → R9/R10 不命中，
  /// 沿 explain_full_scan_rule.dart:92 小表不报口径）。
  List<Map<String, dynamic>> planFor(String sql) {
    final String upper = sql.toUpperCase();
    if (upper.contains(' WHERE ')) {
      return <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'select_type': 'SIMPLE',
          'table': 'loop_small',
          'type': 'const',
          'possible_keys': 'PRIMARY',
          'key': 'PRIMARY',
          'key_len': '4',
          'ref': 'const',
          'rows': 1,
          'filtered': 100.0,
        },
      ];
    }
    if (upper.contains(' LIMIT ')) {
      return <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 1,
          'select_type': 'SIMPLE',
          'table': 'loop_small',
          'type': 'ALL',
          'rows': 120,
          'filtered': 100.0,
        },
      ];
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'select_type': 'SIMPLE',
        'table': 'loop_rows',
        'type': 'ALL',
        'rows': _bigRowCount,
        'filtered': 100.0,
      },
    ];
  }

  List<Map<String, dynamic>> rowsFor(String sql) {
    final String upper = sql.toUpperCase();
    if (upper.contains(' WHERE ')) {
      return <Map<String, dynamic>>[
        <String, dynamic>{'id': 7, 'label': 'row_7'},
      ];
    }
    if (upper.contains(' LIMIT ')) {
      return <Map<String, dynamic>>[
        for (var r = 1; r <= 10; r++)
          <String, dynamic>{'id': r, 'label': 'row_$r'},
      ];
    }
    bigResultQueries++;
    // 每次独立生成（长运行内存面含大结果持引——resultRef 注册表语义）。
    return <Map<String, dynamic>>[
      for (var r = 1; r <= _bigRowCount; r++)
        <String, dynamic>{
          'id': r,
          'payload': 'payload_$r',
          'c2': 'v2_$r',
          'c3': 'v3_$r',
          'c4': 'v4_$r',
          'c5': 'v5_$r',
          'c6': 'v6_$r',
          'c7': 'v7_$r',
        },
    ];
  }

  AgentDbAccess access() => AgentDbAccess(
    getTables: (String? connectionId) async => <String>[
      for (var i = 1; i <= 12; i++) 'loop_table_$i',
    ],
    getTableColumns:
        (String t, {String? connectionId, String? databaseName}) async =>
            <DbColumn>[
              DbColumn(name: 'id', type: 'INT', isPrimaryKey: true),
              DbColumn(name: 'label', type: 'VARCHAR(64)'),
              DbColumn(name: 'payload', type: 'VARCHAR(255)'),
            ],
    getTableIndexes:
        (String t, {String? connectionId, String? databaseName}) async =>
            <DbIndex>[
              DbIndex(
                name: 'PRIMARY',
                columns: <String>['id'],
                isUnique: true,
                isForeignKey: false,
              ),
            ],
    getForeignKeys:
        (String t, {String? connectionId, String? databaseName}) async =>
            <ForeignKey>[],
    getCreateTableSql:
        (String t, {String? connectionId, String? databaseName}) async =>
            'CREATE TABLE $t (...)',
    getExplainPlan: (String sql, {String? connectionId}) async {
      explainCalls++;
      return planFor(sql);
    },
    executeQuery: (String sql, {String? connectionId, String? database}) async {
      queryCalls++;
      return rowsFor(sql);
    },
  );
}

// ---- 观测 no-op（审计/统计不入盘：perf 口径零 I/O 噪声）────────────────────

Future<void> _noopAudit({
  required String connectionId,
  String? connectionName,
  String? databaseName,
  required String runId,
  required int step,
  required String tool,
  String? sql,
  AgentGateLevel? gateLevel,
  AgentGateDecision? gateDecision,
  String? planId,
  required bool success,
  String? errorMessage,
}) async {}

AgentRunStatsCallbacks get _noopStats => AgentRunStatsCallbacks(
  onSessionStart: () {},
  onActiveDay: () {},
  onRunEnd: ({required int steps, int? tokens}) {},
  onLimitStop: () {},
);

/// uiPort 缺省 fake（本套用例不触界面工具；沿 T18 _NoopUiPort 形态）。
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
}

// ---- 测试台（生产链：真 runner + 真 executor + 真 gate/analysis，脚本数据）──

class _Harness {
  _Harness() : db = _ScriptedDb(), chat = _ChatScript() {
    // Fix-H：存储隔离 manager——「历史提问 N/历史回答 N」种子与 50 步 run
    // 消息只落临时目录（本套件即用户实报污染缺陷的写入源）。
    sessionManager = createIsolatedAiSessionManager()
      ..createSession(locale: 'en');
    executor = AgentToolExecutor(
      // 生产装配形态（AiPanelProvider._createAgentAnalysis 同款）：真门 +
      // 真分析，EXPLAIN 取数绑脚本化数据面。
      gate: AgentGate(
        createAnalysis: (AgentRunContext runCtx) => AgentGateAnalysis(
          getExplainPlan: (String sql) async {
            db.explainCalls++;
            return db.planFor(sql);
          },
          rowThreshold: 10000,
          dbType: DatabaseType.mysql,
        ),
      ),
      db: scriptedAccess,
      audit: _noopAudit,
      recordToolCall: (_) {},
      recordL05Event: (_) {},
    );
    runner = AgentLoopRunner(
      executor: executor,
      sessionManager: sessionManager,
      resolveRunContext: (String runId) => AgentRunContext(
        runId: runId,
        connectionId: 'perf-conn',
        connectionName: 'Perf Scripted Conn',
        databaseName: 'perf_db',
        dbType: DatabaseType.mysql,
        readOnly: false,
      ),
      resolveChatConfig: () => const AgentChatConfig(
        provider: 'Scripted',
        model: 'scripted-1',
        apiKey: 'perf-key',
        locale: 'en',
      ),
      chat: chat.call,
      resolveMaxSteps: () async => 100,
      stats: _noopStats,
    );
  }

  final _ScriptedDb db;
  final _ChatScript chat;
  late final AiSessionManager sessionManager;
  late final AgentToolExecutor executor;
  late final AgentLoopRunner runner;

  /// dbAccess 单例（gate 工厂与 executor 共享同一脚本面 + 计数）。
  late final AgentDbAccess scriptedAccess = db.access();

  Future<void> start() => runner.start(
    userMessage: '长运行冒烟：探索库结构并抽样数据',
    uiPort: const _NoopUiPort(),
  );

  /// §5.2 agent 载荷消息（kind 过滤）。
  List<Map<String, dynamic>> payloads(String kind) => sessionManager
      .currentMessages
      .where(
        (AiMessage m) =>
            m.toolResultData?['agent'] is Map<String, dynamic> &&
            (m.toolResultData!['agent'] as Map<String, dynamic>)['kind'] ==
                kind,
      )
      .map((AiMessage m) => m.toolResultData!['agent'] as Map<String, dynamic>)
      .toList();

  /// 种子对话（使对话流具真实滚动行程——长会话现实形态；RSS 0 基线在
  /// 种子之后采样，增量即 run 的边际成本）。
  void seedConversation({int pairs = 20}) {
    for (var i = 1; i <= pairs; i++) {
      sessionManager.addMessage(_seedMessage(isUser: true, i: i));
      sessionManager.addMessage(_seedMessage(isUser: false, i: i));
    }
  }

  AiMessage _seedMessage({required bool isUser, required int i}) => AiMessage(
    id: 'seed_${isUser ? 'u' : 'a'}_$i',
    isUser: isUser,
    content: isUser
        ? '历史提问 $i：这段会话种子用于给对话流提供真实滚动行程，'
              '覆盖查询计划与索引选择的讨论点 $i。'
        : '历史回答 $i：结论与依据（脚本化合成内容，不含真实库数据），'
              '含建议与注意事项的展开描述 $i。',
    timestamp: DateTime.now(),
    type: AiMessageType.chat,
    status: AiMessageStatus.sent,
  );

  void dispose() {
    runner.dispose();
    sessionManager.dispose();
  }
}

// ---- 帧采集与统计（M1 T01 探针口径逐字沿用）────────────────────────────────

class _FrameCollector {
  /// build + raster 合计帧耗时（ms）。
  final List<double> frameMs = <double>[];

  /// 分量诊断：build / raster（gate 不使用；RDP 归属判读用）。
  final List<double> buildMs = <double>[];
  final List<double> rasterMs = <double>[];

  /// 运行期 / 滚动期切面（相位拆分统计）。
  int runPhaseFrames = 0;

  /// 每轮结束时的帧计数标记（轮切面）。
  final List<int> roundMarks = <int>[0];

  void onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      frameMs.add(
        (timing.buildDuration.inMicroseconds +
                timing.rasterDuration.inMicroseconds) /
            1000.0,
      );
      buildMs.add(timing.buildDuration.inMicroseconds / 1000.0);
      rasterMs.add(timing.rasterDuration.inMicroseconds / 1000.0);
    }
  }

  void markRoundEnd() => roundMarks.add(frameMs.length);
}

double _percentile(List<double> values, double p) {
  if (values.isEmpty) {
    return 0.0;
  }
  final List<double> sorted = List<double>.of(values)..sort();
  var idx = (p * sorted.length).ceil() - 1;
  if (idx < 0) {
    idx = 0;
  }
  if (idx >= sorted.length) {
    idx = sorted.length - 1;
  }
  return sorted[idx];
}

void _logStats(String label, List<double> frames) {
  if (frames.isEmpty) {
    _log('$label: no frames');
    return;
  }
  _log(
    '$label: n=${frames.length} '
    'p50=${_percentile(frames, 0.50).toStringAsFixed(2)}ms '
    'p95=${_percentile(frames, 0.95).toStringAsFixed(2)}ms '
    'max=${frames.reduce((double a, double b) => a > b ? a : b).toStringAsFixed(2)}ms',
  );
}

// ---- 泵动辅助（M1 口径：live binding 下帧只在 pump() 调用时产出）───────────

/// 泵动直至条件成立（真实时钟 watchdog；运行期逐帧步进产生增量帧样本）。
/// [settle] = 谓词成立后是否 pumpAndSettle——**运行仍在推进时必须为 false**
/// （settle 会无限追逐 live run 的持续通知；仅门控/终局后的静止态可 settle）。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String label,
  Duration timeout = const Duration(seconds: 120),
  bool settle = true,
}) async {
  final Stopwatch watch = Stopwatch()..start();
  while (!done() && watch.elapsed < timeout) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    done(),
    isTrue,
    reason: '$label：${timeout.inSeconds}s watchdog 超时（运行未按预期推进）',
  );
  if (settle) {
    await tester.pumpAndSettle();
  }
}

/// 冲账补泵（M1 口径：FrameTiming 由引擎滞后批量上报，不补泵尾部帧不入账）。
Future<void> _flushFrameTimings(
  WidgetTester tester,
  _FrameCollector collector,
) async {
  var lastCount = -1;
  for (var i = 0; i < 30 && collector.frameMs.length != lastCount; i++) {
    lastCount = collector.frameMs.length;
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// 程序滚动单程（M1 _pumpDrivenLeg 逐字沿用：easeOutCubic 快起承载 fling；
/// 安全上限按真实时钟计，超限 jumpTo 落位）。
Future<void> _pumpDrivenLeg(
  WidgetTester tester,
  ScrollController controller,
  double target,
  Curve curve,
  String label,
) async {
  final animation = controller.animateTo(
    target,
    duration: _legDuration,
    curve: curve,
  );
  const step = Duration(milliseconds: 16);
  final watch = Stopwatch()..start();
  final capMs = 3 * _legDuration.inMilliseconds + 2000;
  bool legDone() => !controller.position.isScrollingNotifier.value;
  while (!legDone() && watch.elapsedMilliseconds < capMs) {
    await tester.pump(step);
  }
  if (!legDone()) {
    controller.jumpTo(target);
    await tester.pump(step);
  }
  await animation;
}

// ---- RSS 采样（M1 口径：中位数降噪）────────────────────────────────────────

Future<double> _sampleRssMedianMb() async {
  final List<int> values = <int>[];
  for (var i = 0; i < _rssSamples; i++) {
    values.add(ProcessInfo.currentRss);
    await Future<void>.delayed(_rssSampleInterval);
  }
  values.sort();
  return values[_rssSamples ~/ 2] / (1024 * 1024);
}

// ---- 真异步轮询（服务级等待；T18 _waitUntil 同形态）────────────────────────

Future<bool> _waitUntil(
  bool Function() predicate, {
  Duration timeout = _stopBound,
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return true;
}

// ---- 宿主（生产同款消费路径：agentTrajectoryGrouping → 轨迹卡，runner 实时态）─

Widget _buildHost({
  required AiSessionManager session,
  required AgentLoopRunner runner,
  required ScrollController chatController,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF161616),
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: AppDesignSystem.workbenchChatMaxWidth,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[session, runner]),
            builder: (BuildContext context, _) {
              final List<AgentTrajectorySegment> segments =
                  agentTrajectoryGrouping(session.currentMessages);
              return ListView.builder(
                controller: chatController,
                padding: const EdgeInsets.all(AppDesignSystem.space3),
                itemCount: segments.length,
                itemBuilder: (BuildContext context, int index) {
                  final AgentTrajectorySegment segment = segments[index];
                  final AgentTrajectoryRunGroup? group = segment.run;
                  if (group != null) {
                    // workbench_chat_view.dart:966 同款 live 判定。
                    final bool live =
                        group.runId == runner.activeRunId && runner.isRunning;
                    return Padding(
                      key: ValueKey<String>('agent_run_${group.runId}'),
                      padding: const EdgeInsets.only(
                        bottom: AppDesignSystem.space3,
                      ),
                      child: AgentTrajectoryCard(
                        runMessages: group.messages,
                        runner: live ? runner : null,
                      ),
                    );
                  }
                  final AiMessage? message = segment.message;
                  if (message == null) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    key: ValueKey<String>('msg_${message.id}'),
                    padding: const EdgeInsets.only(
                      bottom: AppDesignSystem.space3,
                    ),
                    child: Text(
                      message.content.isEmpty
                          ? (message.toolResultSummary ?? '')
                          : message.content,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}

// ---- 运行中交互检查（断言②③：对话流可交互 + 卡体不变式）──────────────────

Future<void> _checkLiveInteraction(
  WidgetTester tester,
  _Harness h,
  ScrollController chatController,
) async {
  // 跳到流底：轨迹卡在视口内（惰性 ListView 需滚达才构建；门控下内容已定格，
  // 连续跳底直至 offset 稳定）。
  for (var i = 0; i < 4; i++) {
    chatController.jumpTo(chatController.position.maxScrollExtent);
    await tester.pump();
  }

  final List<AgentTrajectorySegment> diagSegments =
      agentTrajectoryGrouping(h.sessionManager.currentMessages);
  _log(
    'diag: messages=${h.sessionManager.currentMessages.length} '
    'steps=${h.executor.stepsUsed} status=${h.runner.status.name} '
    'segments=${diagSegments.length} '
    'runGroups=${diagSegments.where((AgentTrajectorySegment s) => s.isRun).length} '
    'pixels=${chatController.position.pixels.toStringAsFixed(0)} '
    'maxExtent=${chatController.position.maxScrollExtent.toStringAsFixed(0)}',
  );

  final Finder card = find.byType(AgentTrajectoryCard);
  expect(card, findsOneWidget, reason: '单 run 折叠为一张轨迹卡');

  // ── 展开态卡体 ≤ 362 + ≈360 钳生效 + 单一滚动区 + 内部滚动可用（§1.8-5）──
  final Finder body = find.byKey(AgentTrajectoryCard.stepsScrollKey);
  expect(body, findsOneWidget, reason: 'live 卡默认展开（T13 _expanded=_isLive）');
  final double bodyHeight = tester.getSize(body).height;
  expect(
    bodyHeight,
    lessThanOrEqualTo(362),
    reason: '§1.8-5 卡体上限 362（不放宽）',
  );
  expect(bodyHeight, moreOrLessEquals(360, epsilon: 2), reason: '360 钳应生效');
  final List<Element> containerScrollables = _containerScrollables(card);
  expect(
    containerScrollables,
    hasLength(1),
    reason: '单一滚动区（无嵌套滚动；SelectableText 内部滚动器按 T13 口径排除）',
  );
  final ScrollableState cardScroll =
      (containerScrollables.single as StatefulElement).state
          as ScrollableState;
  // 内部滚动可用（T13 M1-③ 口径：jumpTo 确定到位，避开 drag 惯性物理在
  // live 测试环境的落点歧义）。
  expect(
    cardScroll.position.maxScrollExtent,
    greaterThan(0),
    reason: '步数超 360 卡体上限，卡体应有滚动行程',
  );
  cardScroll.position.jumpTo(cardScroll.position.maxScrollExtent);
  await tester.pump();
  expect(
    cardScroll.position.pixels,
    cardScroll.position.maxScrollExtent,
    reason: '卡体内部滚动可用（位置可驱动到滚动终点）',
  );

  // ── 折叠态整卡 ≤ 362（任务书③字面口径，测量并断言）─────────────────────
  await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
  await tester.pump();
  final double collapsedHeight = tester.getSize(card).height;
  expect(
    collapsedHeight,
    lessThanOrEqualTo(362),
    reason: '折叠态整卡 ≤ 362（不放宽）',
  );
  await tester.tap(find.byKey(AgentTrajectoryCard.headerKey)); // 恢复展开
  await tester.pump();

  // ── 对话流滚动可用（运行中 drag 响应，NF1.3 UI 可交互）──────────────────
  // 跳回流顶在种子行上 drag（该区域无内层可滚动容器，drag 落点确定），
  // 向上拖 → 对话流 pixels 应增大。
  chatController.jumpTo(0);
  await tester.pump();
  final double before = chatController.position.pixels;
  await tester.drag(find.byKey(const ValueKey<String>('msg_seed_u_1')),
      const Offset(0, -150));
  await tester.pump();
  expect(
    chatController.position.pixels,
    greaterThan(before),
    reason: '对话流滚动可用（运行中 drag 响应）',
  );
  chatController.jumpTo(chatController.position.maxScrollExtent);
  await tester.pump();
}

// ---- 「单一滚动区」口径（T13 M1-③ 同款）：排除 SelectableText 自带的文本
// 内部滚动器后，卡范围内容器级 Scrollable 恰为卡体一个 ────────────────────────

List<Element> _containerScrollables(Finder cardScope) {
  final Set<Element> selectableTexts =
      find.byType(SelectableText).evaluate().toSet();
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

  return find
      .descendant(of: cardScope, matching: find.byType(Scrollable))
      .evaluate()
      .where((Element el) => !insideSelectableText(el))
      .toList();
}

// ---- main ───────────────────────────────────────────────────────────────────

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  final String mode = kDebugMode
      ? 'debug（数值仅相对参考；结论以 profile 为准）'
      : kProfileMode
      ? 'profile（gate 结论口径）'
      : kReleaseMode
      ? 'release'
      : 'unknown';

  testWidgets('T32 agent long-run smoke: 50 步脚本化 run（NF1.3/1.4）', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;

    final ScrollController chatA = ScrollController();
    final ScrollController chatB = ScrollController();

    _log('==================== T32 AGENT LONG-RUN SMOKE ====================');
    _log('MODE: $mode');
    _log(
      'env: SESSIONNAME=${Platform.environment['SESSIONNAME'] ?? 'n/a'}'
      '（RDP-* = 远端会话，raster 分量可受会话帧率影响，见分量判读）',
    );
    _log(
      'scenario: scripted LLM $_longRunSteps steps（混合数据工具 + '
      '$_bigRowCount 行大结果截断回喂），真实 runner/executor/gate/analysis 链，'
      'dbAccess 全脚本化（不连真实库）',
    );

    // ══ Phase A：50 步长运行（帧/内存采样窗保持纯净：窗口内只有「25 步推进」
    // 本身，无任何一次性 UI 操作——运行中交互检查全部移至 Phase B 的挂起态）══
    final _Harness h = _Harness();
    h.chat.enqueueAll(_scriptRun(_longRunSteps));
    h.chat.gateAtCall = _memoryHalfSteps + 1; // 25 步执行完、第 26 次调用挂起
    h.seedConversation();

    await tester.pumpWidget(
      _buildHost(
        session: h.sessionManager,
        runner: h.runner,
        chatController: chatA,
      ),
    );
    await tester.pumpAndSettle();

    final double rss0Mb = await _sampleRssMedianMb();

    final _FrameCollector collector = _FrameCollector();
    SchedulerBinding.instance.addTimingsCallback(collector.onTimings);

    unawaited(h.start());

    // 锚点落账后跳到流底：轨迹卡进入构建范围（运行期每步刷新进入帧样本）。
    await _pumpUntil(
      tester,
      () => h.executor.stepsUsed >= 1,
      label: '锚点落账',
      settle: false, // run 仍在推进，settle 会无限追逐通知
    );
    chatA.jumpTo(chatA.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();

    // 阶段 1：步 1..25 落账（逐帧步进 → 增量帧样本），至 25 步对照门。
    // settle=false：live running 卡挂 spinner（repeat 动画，卡在视口内时
    // hasScheduledFrame 恒真）——pumpAndSettle 会无限追逐。
    await _pumpUntil(
      tester,
      () => h.chat.gate1Reached,
      label: '25 步对照门',
      settle: false,
    );
    expect(h.executor.stepsUsed, _memoryHalfSteps, reason: '对照门定格在 25 步');
    await _flushFrameTimings(tester, collector);
    final double rss25Mb = await _sampleRssMedianMb();
    h.chat.releaseGate();

    // 阶段 2：步 26..50 + 终局（运行期帧样本继续采集）。
    await _pumpUntil(tester, () => !h.runner.isRunning, label: '终局收敛');
    await tester.pumpAndSettle();

    // 终态断言：completed + 步数对账（AC2.3）。
    expect(h.runner.status, AgentRunStatus.completed, reason: '50 步脚本自然终局');
    expect(h.executor.stepsUsed, _longRunSteps, reason: '步数 = 调用数（AC2.3）');
    await _flushFrameTimings(tester, collector);
    collector.runPhaseFrames = collector.frameMs.length;
    final double rss50Mb = await _sampleRssMedianMb();

    // ── 终局卡几何（50 步全量在卡，rss50 采样之后——不污染内存对照窗）────
    // 注：运行中卡若已在视口构建（锚点后跳底），终局不自动收起（_expanded
    // 状态保持）——测量与初始展开态解耦：先强制折叠测整卡，再展开测卡体。
    final List<AgentTrajectorySegment> diagA =
        agentTrajectoryGrouping(h.sessionManager.currentMessages);
    _log(
      'diagA: messages=${h.sessionManager.currentMessages.length} '
      'segments=${diagA.length} '
      'runGroups=${diagA.where((AgentTrajectorySegment s) => s.isRun).length} '
      'pixels=${chatA.position.pixels.toStringAsFixed(0)} '
      'maxExtent=${chatA.position.maxScrollExtent.toStringAsFixed(0)}',
    );
    for (var i = 0; i < 4; i++) {
      chatA.jumpTo(chatA.position.maxScrollExtent);
      await tester.pump();
    }
    final Finder cardA = find.byType(AgentTrajectoryCard);
    expect(cardA, findsOneWidget, reason: '单 run 折叠为一张轨迹卡');
    final Finder bodyAFinder = find.byKey(AgentTrajectoryCard.stepsScrollKey);
    if (bodyAFinder.evaluate().isNotEmpty) {
      await tester.tap(find.byKey(AgentTrajectoryCard.headerKey)); // 收起
      await tester.pump();
    }
    final double collapsedA = tester.getSize(cardA).height;
    expect(collapsedA, lessThanOrEqualTo(362), reason: '折叠态整卡 ≤ 362');
    // 展开（tap header）：§1.8-5 口径——卡体 ≤ 362 + 单一滚动区 + 内部滚动可用。
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey));
    await tester.pump();
    final Finder bodyA = find.byKey(AgentTrajectoryCard.stepsScrollKey);
    expect(bodyA, findsOneWidget);
    final double bodyAHeight = tester.getSize(bodyA).height;
    expect(
      bodyAHeight,
      lessThanOrEqualTo(362),
      reason: '§1.8-5 卡体上限 362（不放宽）',
    );
    expect(bodyAHeight, moreOrLessEquals(360, epsilon: 2), reason: '360 钳应生效');
    final List<Element> containerScrollablesA = _containerScrollables(cardA);
    expect(
      containerScrollablesA,
      hasLength(1),
      reason: '单一滚动区（无嵌套滚动；SelectableText 内部滚动器按 T13 口径排除）',
    );
    final ScrollableState cardScrollA =
        (containerScrollablesA.single as StatefulElement).state
            as ScrollableState;
    // 内部滚动可用（T13 M1-③ 口径：jumpTo 确定到位，避开 drag 惯性物理在
    // live 测试环境的落点歧义）。
    expect(
      cardScrollA.position.maxScrollExtent,
      greaterThan(0),
      reason: '50 步内容超出 360 卡体上限，卡体应有滚动行程',
    );
    cardScrollA.position.jumpTo(cardScrollA.position.maxScrollExtent);
    await tester.pump();
    expect(
      cardScrollA.position.pixels,
      cardScrollA.position.maxScrollExtent,
      reason: '卡体内部滚动可用（位置可驱动到滚动终点）',
    );
    await tester.tap(find.byKey(AgentTrajectoryCard.headerKey)); // 收回折叠态
    await tester.pump();

    // D19 截断证据（会话文件快照 ≤10 行 + 大结果步存在）。
    final List<Map<String, dynamic>> stepPayloads = h.payloads('agent_step');
    final int bigSteps = stepPayloads
        .where(
          (Map<String, dynamic> p) =>
              ((p['resultRef'] as Map<String, dynamic>?)?['rowCount'] as num?)
                  ?.toInt() ==
              _bigRowCount,
        )
        .length;
    final int maxSnapshotRows = stepPayloads.fold<int>(0, (int acc, p) {
      final List<Object?>? rows =
          (p['resultRef'] as Map<String, dynamic>?)?['snapshotRows']
              as List<Object?>?;
      return rows != null && rows.length > acc ? rows.length : acc;
    });
    expect(bigSteps, greaterThan(0), reason: '大结果步应存在（截断回喂场景）');
    expect(
      maxSnapshotRows,
      lessThanOrEqualTo(10),
      reason: 'D19 会话快照 ≤10 行（UI 侧上限）',
    );

    // 对话流滚动：3 轮全程往返（M1 口径）——帧样本主采集段。
    final double maxExtent = chatA.position.maxScrollExtent;
    expect(maxExtent, greaterThan(0), reason: '长会话对话流应有可滚动行程');
    for (var round = 0; round < _rounds; round++) {
      await _pumpDrivenLeg(
        tester,
        chatA,
        maxExtent,
        Curves.easeOutCubic,
        'round ${round + 1} leg-down',
      );
      await _pumpDrivenLeg(tester, chatA, 0, Curves.easeInCubic,
          'round ${round + 1} leg-up');
      await _flushFrameTimings(tester, collector);
      collector.markRoundEnd();
    }
    await _flushFrameTimings(tester, collector);
    SchedulerBinding.instance.removeTimingsCallback(collector.onTimings);

    // ══ Phase A 数据汇总 ═══════════════════════════════════════════════════
    _log('---- phase A: $_longRunSteps-step run ----');
    _log(
      'run: status=${h.runner.status.name} steps=${h.executor.stepsUsed} '
      'tokens=${h.runner.tokenUsage?.totalTokens ?? '—'} '
      'chatCalls=${h.chat.calls} dbQueries=${h.db.queryCalls} '
      'explains=${h.db.explainCalls}',
    );
    _log(
      'truncation: big-result steps=$bigSteps '
      '(queryCalls for big=${h.db.bigResultQueries}), '
      'message snapshot maxRows=$maxSnapshotRows (D19 UI cap ≤10)',
    );
    _log('---- frames (build+raster, M1 T01 口径) ----');
    _logStats(
      'run-phase(0..${collector.runPhaseFrames})',
      collector.frameMs.sublist(0, collector.runPhaseFrames),
    );
    _logStats(
      'scroll-legs',
      collector.frameMs.sublist(collector.runPhaseFrames),
    );
    _logStats('ALL(gate population)', collector.frameMs);
    _log(
      'split p95: build=${_percentile(collector.buildMs, 0.95).toStringAsFixed(2)}ms '
      'raster=${_percentile(collector.rasterMs, 0.95).toStringAsFixed(2)}ms '
      '（raster 主导超限 → RDP/软光栅环境伪影嫌疑；build 主导 → 真实构建成本）',
    );

    // ══ Phase B：运行中交互（②③ live 态）+ 停止即时响应（①）════════════════
    // B 的运行在 20 步后在途挂起：内容定格、run 仍 isRunning（live 卡展开态）
    // ——交互检查在稳定内容上做，不触碰 A 的内存采样窗。
    final _Harness h2 = _Harness();
    h2.chat.enqueueAll(_scriptRun(_stopRunSteps));
    h2.chat.armHold(
      _stopRunSteps + 1,
      _toolResp('list_tables', <String, dynamic>{}, _stopRunSteps + 1),
    );
    h2.seedConversation(pairs: 15);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    h.dispose(); // 先卸树再 dispose（监听器移除先于 notifier 消亡）
    chatA.dispose();

    await tester.pumpWidget(
      _buildHost(
        session: h2.sessionManager,
        runner: h2.runner,
        chatController: chatB,
      ),
    );
    await tester.pumpAndSettle();

    unawaited(h2.start());
    final bool inflight = await _waitUntil(
      () =>
          h2.executor.stepsUsed >= _stopRunSteps && h2.chat.holdPending,
      timeout: const Duration(seconds: 60),
    );
    expect(inflight, isTrue, reason: '脚本应推进到第 ${_stopRunSteps + 1} 次调用在途挂起');
    expect(h2.runner.status, AgentRunStatus.running);
    // 不 settle（同上：live 卡 spinner 恒调度帧）——交互检查自持逐帧泵动。
    await tester.pump();
    await tester.pump();

    // 运行中（挂起态）交互检查：live 卡展开默认态 + 对话流 drag 响应。
    await _checkLiveInteraction(tester, h2, chatB);

    final Stopwatch stopWatch = Stopwatch()..start();
    h2.runner.requestStop();
    final String statusRightAfterStop = h2.runner.status.name;
    expect(
      h2.runner.status,
      AgentRunStatus.stopping,
      reason: 'requestStop 同步翻转 stopping（§6.8 停止按钮即时反馈）',
    );
    h2.chat.releaseHold(); // 在途调用完成（§6.4：当前步收尾后收敛）
    final bool converged = await _waitUntil(
      () => !h2.runner.isRunning,
      timeout: _stopBound,
    );
    final int stopMs = stopWatch.elapsedMilliseconds;
    expect(converged, isTrue, reason: 'requestStop 后 ${_stopBound.inSeconds}s 内到终态');
    expect(h2.runner.status, AgentRunStatus.stoppedByUser);
    expect(
      h2.executor.stepsUsed,
      _stopRunSteps,
      reason: 'AC1.3：停止后不再派发新调用',
    );
    expect(h2.chat.calls, _stopRunSteps + 1, reason: 'AC1.3：不再发起新轮');
    await tester.pumpAndSettle();

    // UI 呈现面：终局 chip 文案（en）。
    final AppLocalizations l10n = AppLocalizationsEn();
    final Finder chipText = find.descendant(
      of: find.byKey(AgentTrajectoryCard.statusChipKey),
      matching: find.byType(Text),
    );
    expect(chipText, findsOneWidget, reason: '停止后轨迹卡 chip 应呈现终局态');
    expect(
      tester.widget<Text>(chipText).data,
      l10n.agentStoppedByUser,
      reason: 'chip 文案 = Stopped by user（en）',
    );

    // ══ 收尾：卸树 + 释放（组件级资源纪律）══════════════════════════════════
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    h2.dispose();
    chatB.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();

    // ══ 门柱判定（逐条，不放宽）════════════════════════════════════════════
    final double p95All = _percentile(collector.frameMs, 0.95);
    final double firstHalfMb = rss25Mb - rss0Mb;
    final double secondHalfMb = rss50Mb - rss25Mb;
    final bool memorySuperLinear =
        secondHalfMb >
        _memoryLinearitySlack * (firstHalfMb <= 0 ? 1.0 : firstHalfMb);

    _log('---- memory (ProcessInfo.currentRss, M1 判据) ----');
    _log(
      'rss: 0步=${rss0Mb.toStringAsFixed(1)}MB '
      '$_memoryHalfSteps步=${rss25Mb.toStringAsFixed(1)}MB '
      '$_longRunSteps步=${rss50Mb.toStringAsFixed(1)}MB',
    );
    _log(
      'increments: 0→$_memoryHalfSteps=${firstHalfMb.toStringAsFixed(1)}MB '
      '$_memoryHalfSteps→$_longRunSteps=${secondHalfMb.toStringAsFixed(1)}MB '
      '(linear if second ≤ $_memoryLinearitySlack× first)',
    );
    _log('---- phase B: live interaction + stop responsiveness ----');
    _log(
      'requestStop@step$_stopRunSteps: status after = $statusRightAfterStop, '
      'terminal stoppedByUser in ${stopMs}ms (bound ${_stopBound.inMilliseconds}ms), '
      'steps stay $_stopRunSteps, chip="${l10n.agentStoppedByUser}"',
    );

    // ---- 断言（任务书五项逐条）----
    // 帧门柱：验收口径 = profile 模式结论为准（任务书验收标准原文），debug
    // 数值仅相对参考——debug 下不作为判定，超限时显著告警并要求 profile 复
    // 测；profile/release 下严格执行（门柱数值本身不放宽）。
    if (kDebugMode) {
      if (p95All > _gateP95Ms) {
        _log(
          '⚠ DEBUG p95=${p95All.toStringAsFixed(2)}ms > $_gateP95Ms ms：debug '
          '数值仅相对参考（JIT + 断言 + 无优化文本布局），profile 复测为结论口径；'
          '若 profile 仍超限 → 停止上报，不得放宽',
        );
      }
    } else {
      expect(
        p95All,
        lessThanOrEqualTo(_gateP95Ms),
        reason: 'NF1.4 P95 帧(build+raster 合计) ≤ $_gateP95Ms ms'
            '（M1 T01 探针口径；不达标须停止上报，不得放宽）',
      );
    }
    expect(
      memorySuperLinear,
      isFalse,
      reason: 'NF1.4 RSS 25→50 增量相对 0→25 增量非超线性'
          '（M1 判据：second ≤ 2× first；不达标须停止上报）',
    );

    // ---- 结论（随回报归档）----
    _log('==================== CONCLUSION ====================');
    _log('mode: $mode');
    _log(
      'gate P95: ${p95All.toStringAsFixed(2)}ms vs $_gateP95Ms ms → '
      '${kDebugMode
          ? (p95All <= _gateP95Ms
                ? "PASS（debug 相对参考）"
                : "DEBUG 超限（仅相对参考；profile 复测为结论口径）")
          : (p95All <= _gateP95Ms ? "PASS" : "FAIL（停止上报，不放宽）")} '
      '(frames=${collector.frameMs.length}, run-phase=${collector.runPhaseFrames}, '
      'legs=${collector.frameMs.length - collector.runPhaseFrames})',
    );
    _log(
      'gate memory: 25→50 增量 ${secondHalfMb.toStringAsFixed(1)}MB vs '
      '0→25 增量 ${firstHalfMb.toStringAsFixed(1)}MB → '
      '${memorySuperLinear ? "超线性 ⚠ FAIL" : "线性内 ✓ PASS"}',
    );
    _log(
      'gate stop: stoppedByUser in ${stopMs}ms ≤ ${_stopBound.inMilliseconds}ms ✓；'
      'stopping 同步翻转=$statusRightAfterStop',
    );
    _log(
      'gate card: A 终局 50 步卡 expandedBody=${bodyAHeight.toStringAsFixed(1)}px ≤362 ✓'
      '（≈360 钳生效）+ 单一滚动区 ✓ + 内部滚动 ✓ + 折叠整卡=${collapsedA.toStringAsFixed(1)}px ≤362 ✓；'
      'B live 20 步卡（展开/折叠/滚动/对话流 drag）断言全过 ✓',
    );
    _log(
      'gate chat-stream: 运行中 drag 响应 ✓（B 挂起态）+ A 3 轮全程往返 ✓ '
      '(maxExtent=${maxExtent.toStringAsFixed(0)}px)',
    );
    _log(
      '口径披露：本结论以 profile 模式为准；debug 数值仅相对参考。'
      'RDP 会话（SESSIONNAME=RDP-*）下 raster 分量受远端帧率影响——'
      '以 build/raster 分量 P95 判读归属，本脚本不自行放宽门柱。',
    );
    _log('====================================================');
  });
}
