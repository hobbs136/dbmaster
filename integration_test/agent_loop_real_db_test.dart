// ============================================================================
// Agent 回路簇真库集成测试（tasks-ai-agent.md T18 / design-ai-agent.md §6.7
// 回路簇行 + §5.2 消息流 + §6.4 四停止源 + D15 快照 + D18 失败上限 + §7 A1
// 写兜底）。
//
// 被测：AgentLoopRunner + AgentToolExecutor + AgentGate 的生产装配形态
// （对齐 AiPanelProvider._buildAgentRunner：真 gate 工厂绑真
// dbService.getExplainPlan、AgentDbAccess 包真 DatabaseService tear-off），
// **唯一 mock = LLM chat 层**（脚本化 AgentChatFn，NF5.3 注入面；数据库
// 服务不 mock——经 embedded dbmaster server /api/gw 走真实测试库）。
//
// 覆盖（design §6.7 回路簇十方向 + AC2.2/D18）：
//   001 多步指令 list→describe→sample → 步数=调用数、轨迹消息齐
//       （用户消息/锚点/步对/终局）、全程无确认、审计逐条、真数据断言
//       （AC1.1/1.2/2.3）+ NF2.1 顺带（chat 请求目标=用户配置提供商）
//   002 写语句走只读通道 → 库前后零变化（重查断言）+
//       WRITE_REJECTED_READONLY_CHANNEL + submit_action_plan 指引（AC4.2/AC15.3）
//   003 超 3000 行结果 → agent 行数上限与手动执行一致（同设置对照，AC4.3）
//       + D19 会话快照 ≤10 行
//   004 L0.5 确认取消 → 读未执行（12,000 行大表 confirm(l05) → 人拒 →
//       GATE_REJECTED、零 executeQuery、审计 rejected_by_user，AC8.2 回路面）
//   005 超限停止（maxSteps=2 × 3 调用）→ 部分执行 + 现状汇报 + 不自动续
//       （AC2.2）→ 新指令可接续（AC2.4）
//   006 连续 5 个失败工具调用 → stoppedByFailures 汇报（D18/NF3.2）
//   007 readOnly 连接写意图 → 全链零 executeQuery（NF2.3）
//   008 敏感字面量会话 → 审计入档 SQL 脱敏 + prefs 落盘串与统计导出串
//       不含明文（AC13.2/NF2.2/NF6.2 字符串断言）
//   009 chat 抛错 → failed 终局 + 脱敏明细 + 重发可用（AC15.5）
//   010 杀进程重启 → 会话消息（=落盘内容）有锚点无终局 → 分组中断态 +
//       新 runner 不续跑、新指令可用（AC15.6，会话文件级断言——以
//       currentMessages 为 persist() 的写入内容，path_provider 在
//       flutter_tester 不可用故不直接读文件）
//   011 运行中切上下文源 → 快照不漂移（双库对照：漂移靶为空库，读取若
//       漂移必失败，AC7.2/D15）
//   012 L1 兜底（widget e2e）：脚本化模型在回复文本产出写 SQL → 终局正文
//       携带 SQL + agent 通道零执行 → M1 SQL 卡渲染（code 拦截层，与真实
//       AI 回复同一渲染路径）→ 用户执行路径过 ConfirmExecuteDialog 写门
//       （取消零变化/确认生效）+ DROP TABLE 危险双门（真管线 DmlSafety
//       critical → DmlConfirmDialog 键入确认，AC9.4/AC10.1-10.3 A1 形态）
//
// 自建自删专用库（generateTestDatabaseName()，绝不污染共享状态、不依赖
// 用例间顺序）。环境不可达（embedded server 二进制缺失 / DBMASTER_* 缺参 /
// 连不上）时以可 grep 的 AGENT_LOOP_E2E_SKIP 打印并跳过（无假绿，沿
// MYSQL_E2E_SKIP 惯例）。
//
// 运行（Windows 示例，凭据见 workspace test_db_server.txt）：
//   DBMASTER_SERVER_BIN=dist/Release/dbmaster-server.exe \
//   flutter test integration_test/agent_loop_real_db_test.dart \
//     --dart-define=DBMASTER_MYSQL_HOST=192.168.3.128 \
//     --dart-define=DBMASTER_MYSQL_USER=root \
//     --dart-define=DBMASTER_MYSQL_PASSWORD=...
// ============================================================================

@Timeout(Duration(minutes: 30))
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/ai_message_type.dart' show AiMessageStatus;
import 'package:dbmaster/models/ai_models.dart'
    show AiToolCall, ChatResponse, TokenUsage;
import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart'
    show AiMessage, DatabaseType, DbServer;
import 'package:dbmaster/models/query_optimizer/execution_plan.dart'
    show PerformanceReport;
import 'package:dbmaster/organisms/ai_panel/confirm_execute_dialog.dart';
import 'package:dbmaster/organisms/dialogs/dml_confirm_dialog.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_trajectory_card.dart'
    show agentTrajectoryGrouping;
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/cards/result_table_card.dart'
    show WorkbenchErrorCardPayload;
import 'package:dbmaster/organisms/ai_workbench/cards/sql_tool_card.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_card_payload.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentGate, AgentRunContext;
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show AgentGateAnalysis, ReadImpactAnalysis;
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolCatalog, AgentToolErrorCodes;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart'
    show AgentDbAccess, AgentToolExecutor, GateCallbacks;
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort, GateCardResult;
import 'package:dbmaster/services/ai/ai_session_manager.dart'
    show AiSessionManager;
import 'package:dbmaster/services/audit_log_service.dart' show AuditLogService;
import 'package:dbmaster/services/database_abstract.dart'
    show DatabaseConnection;
import 'package:dbmaster/services/database_service.dart' show DatabaseService;
import 'package:dbmaster/services/workbench_usage_stats_service.dart'
    show WorkbenchUsageStatsService;

import 'config/mysql_test_config.dart';
import 'helpers/ai_session_isolation_helper.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// D6：agent L0.5 行阈值默认（QuerySettingsService 口径；真库 12,000 行
/// 种子表使无 WHERE 全查命中 confirm(l05)）。
const int _l05Threshold = 10000;

/// loop_big 种子行数（≥ 阈值；AC8.2 回路面 004 的确认触发源）。
const int _bigRows = 12000;

/// loop_rows 种子行数（> 3000 行限；AC4.3 的超限结果源）。
const int _rowLimitProbeRows = 3500;

/// 用户配置的 chat 目标（NF2.1 断言面：请求必须打到用户配置提供商端点，
/// 与 embedded server /api/gw 无关）。
const String _userProvider = 'DeepSeek';
const String _userModel = 'deepseek-chat';
const String _userApiKey = 'sk-loop-e2e-user-key';
const String _userBaseUrl = 'https://api.user-deepseek.example/v1';

// ── chat 脚本化 fake（唯一 mock：LLM chat 层）───────────────────────────────

/// 一次 chat 调用的请求快照（NF2.1 断言面）。
class _ChatRequest {
  _ChatRequest({
    required this.provider,
    required this.model,
    required this.apiKey,
    required this.baseUrl,
    required this.systemPrompt,
    required this.tools,
  });

  final String provider;
  final String model;
  final String apiKey;
  final String? baseUrl;
  final String? systemPrompt;
  final List<Map<String, dynamic>>? tools;
}

/// 脚本化 chat：按调用序弹出闭包（响应 / 抛错 / Completer 门控 / 运行中
/// 侧效均可——011 用闭包侧效模拟切侧栏时机）。
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
        systemPrompt: systemPrompt,
        tools: tools,
      ),
    );
    if (queue.isEmpty) {
      throw StateError(
        'AgentLoopRealDbTest: unexpected chat call #${requests.length}',
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
      id: 'call-${name.hashCode.abs()}-${_callSeq++}',
      type: 'function',
      functionName: name,
      functionArguments: jsonEncode(args),
    );

int _callSeq = 0;

ChatResponse _call(AiToolCall call, {String? content, TokenUsage? usage}) =>
    ChatResponse(content: content, toolCalls: <AiToolCall>[call], usage: usage);

// ── 观测 taps（真服务外面包一层计数/捕获，不 mock 数据库服务）──────────────

/// dbService 访问计数/捕获：包装**真实** DatabaseService tear-off（生产
/// AgentDbAccess 的同款注入缝，仅加观测）。
class _DbTap {
  int executeQueryCalls = 0;
  int explainCalls = 0;
  final List<String> executedSql = <String>[];
  final List<String?> executeDatabases = <String?>[];
  final List<({String table, String? database})> describeColumnCalls =
      <({String table, String? database})>[];

  AgentDbAccess wrap(DatabaseService db) => AgentDbAccess(
    getTables: (String? connectionId, String? databaseName) => db.getTables(
      connectionId: connectionId,
      databaseName: databaseName,
    ),
    getTableColumns:
        (String tableName, {String? connectionId, String? databaseName}) {
          describeColumnCalls.add((table: tableName, database: databaseName));
          return db.getTableColumns(
            tableName,
            connectionId: connectionId,
            databaseName: databaseName,
          );
        },
    getTableIndexes: db.getTableIndexes,
    getForeignKeys: db.getForeignKeys,
    getCreateTableSql: db.getCreateTableSql,
    getExplainPlan: (String sql, {String? connectionId}) {
      explainCalls++;
      return db.getExplainPlan(sql, connectionId: connectionId);
    },
    executeQuery: (String sql, {String? connectionId, String? database}) {
      executeQueryCalls++;
      executedSql.add(sql);
      executeDatabases.add(database);
      return db.executeQuery(
        sql,
        connectionId: connectionId,
        database: database,
      );
    },
  );
}

/// 审计 tap：捕获 executor 传入的原始记录（敏感面流向证明）+ 转发**真实**
/// AuditLogService（生产路径照跑——落盘断言即针对真实入档内容）。
class _AuditTap {
  final List<Map<String, dynamic>> records = <Map<String, dynamic>>[];

  Future<void> call({
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
  }) async {
    records.add(<String, dynamic>{
      'connectionId': connectionId,
      'databaseName': databaseName,
      'runId': runId,
      'step': step,
      'tool': tool,
      'sql': sql,
      'gateDecision': gateDecision,
      'success': success,
      'errorMessage': errorMessage,
    });
    await AuditLogService().recordAgentEvent(
      connectionId: connectionId,
      connectionName: connectionName,
      databaseName: databaseName,
      runId: runId,
      step: step,
      tool: tool,
      sql: sql,
      gateLevel: gateLevel,
      gateDecision: gateDecision,
      planId: planId,
      success: success,
      errorMessage: errorMessage,
    );
  }
}

/// 运行级统计 tap：捕获 + 转发真实 WorkbenchUsageStatsService（008 的
/// 统计导出面即真实服务导出串）。
class _StatsTap {
  int sessionStarts = 0;
  int activeDays = 0;
  int limitStops = 0;
  final List<({int steps, int? tokens})> runEnds =
      <({int steps, int? tokens})>[];

  AgentRunStatsCallbacks get callbacks => AgentRunStatsCallbacks(
    onSessionStart: () {
      sessionStarts++;
      WorkbenchUsageStatsService().recordAgentSessionStart();
    },
    onActiveDay: () {
      activeDays++;
      WorkbenchUsageStatsService().recordAgentActiveDay();
    },
    onRunEnd: ({required int steps, int? tokens}) {
      runEnds.add((steps: steps, tokens: tokens));
      WorkbenchUsageStatsService().recordAgentRunEnd(
        steps: steps,
        tokens: tokens,
      );
    },
    onLimitStop: () {
      limitStops++;
      WorkbenchUsageStatsService().recordLimitStop();
    },
  );
}

/// run 上下文快照解析源（D15：可变源 + start 时一次快照全程只读）。
class _CtxSource {
  _CtxSource({
    required this.connectionId,
    required this.connectionName,
    required this.databaseName,
    required this.dbType,
    this.readOnly = false,
  });

  String connectionId;
  String connectionName;
  String databaseName;
  DatabaseType dbType;
  bool readOnly;
}

/// 回路测试台：生产装配形态（真 executor + 真 gate 工厂 + 真 dbService），
/// chat/maxSteps 注入脚本。
class _LoopHarness {
  _LoopHarness({
    required this.dbService,
    required this.ctxSource,
    AiSessionManager? sessionManager,
    int maxSteps = 25,
  }) : chat = _ChatScript(),
       dbTap = _DbTap(),
       auditTap = _AuditTap(),
       statsTap = _StatsTap(),
       // Fix-H：默认装配走存储隔离 manager（临时目录 + prefs 前缀），
       // 防测试会话写进真实 Documents/prefs（用户存储污染缺陷）。
       sessionManager =
           sessionManager ??
           (createIsolatedAiSessionManager()..createSession()) {
    executor = AgentToolExecutor(
      // 生产装配形态（AiPanelProvider._createAgentAnalysis 同款）：每次判定
      // 重新构造，EXPLAIN 经真连接注入。
      gate: AgentGate(
        createAnalysis: (AgentRunContext runCtx) => AgentGateAnalysis(
          getExplainPlan: (String sql) =>
              dbService.getExplainPlan(sql, connectionId: runCtx.connectionId),
          rowThreshold: _l05Threshold,
          dbType: runCtx.dbType,
        ),
      ),
      db: dbTap.wrap(dbService),
      audit: auditTap.call,
    );
    runner = AgentLoopRunner(
      executor: executor,
      sessionManager: this.sessionManager,
      resolveRunContext: (String runId) => AgentRunContext(
        runId: runId,
        connectionId: ctxSource.connectionId,
        connectionName: ctxSource.connectionName,
        databaseName: ctxSource.databaseName,
        dbType: ctxSource.dbType,
        readOnly: ctxSource.readOnly,
      ),
      resolveChatConfig: () => const AgentChatConfig(
        provider: _userProvider,
        model: _userModel,
        apiKey: _userApiKey,
        baseUrl: _userBaseUrl,
        locale: 'zh',
      ),
      chat: chat.call,
      resolveMaxSteps: () async => maxSteps,
      stats: statsTap.callbacks,
    );
  }

  final DatabaseService dbService;
  final _CtxSource ctxSource;
  final _ChatScript chat;
  final _DbTap dbTap;
  final _AuditTap auditTap;
  final _StatsTap statsTap;
  final AiSessionManager sessionManager;
  late final AgentToolExecutor executor;
  late final AgentLoopRunner runner;

  /// 门卡回调（L0.5 确认卡决策由测试经 [cardCompleter] 手动落定）。
  Completer<GateCardResult> cardCompleter = Completer<GateCardResult>();
  final List<ReadImpactAnalysis> seenImpacts = <ReadImpactAnalysis>[];
  final List<String> seenConfirmSql = <String>[];

  GateCallbacks get gates {
    final Completer<GateCardResult> completer = Completer<GateCardResult>();
    cardCompleter = completer;
    return GateCallbacks(
      onL05Confirm: (ReadImpactAnalysis impact, String sql) {
        seenImpacts.add(impact);
        seenConfirmSql.add(sql);
        return completer.future;
      },
      // A1 结构不可达（目录无 l1 工具）——沿 shell 占位实现。
      onPlanApproval: (Object plan) async => GateCardResult.rejected,
    );
  }

  List<AiMessage> get messages => sessionManager.currentMessages.toList();

  /// §5.2 agent 载荷消息（kind 过滤）。
  List<Map<String, dynamic>> payloads(String kind) => messages
      .where(
        (AiMessage m) =>
            m.toolResultData?['agent'] is Map<String, dynamic> &&
            (m.toolResultData!['agent'] as Map<String, dynamic>)['kind'] ==
                kind,
      )
      .map((AiMessage m) => m.toolResultData!['agent'] as Map<String, dynamic>)
      .toList();

  /// 步载荷（stepNo 升序）。
  List<Map<String, dynamic>> get steps => payloads('agent_step')
    ..sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          ((a['stepNo'] as num?) ?? 0).compareTo(((b['stepNo'] as num?) ?? 0)),
    );

  void dispose() {
    runner.dispose();
    sessionManager.dispose();
  }
}

Map<String, dynamic>? _payloadOf(AiMessage m) =>
    m.toolResultData?['agent'] is Map<String, dynamic>
    ? m.toolResultData!['agent'] as Map<String, dynamic>
    : null;

/// 真异步轮询（服务级用例：真实网络往返不排帧）。
Future<bool> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return true;
}

// ── 种子（网关单语句模型：多值 INSERT 分批，沿 T17 模式）───────────────────

Future<void> _seedMainDb(MySQLAdapter seed) async {
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS loop_small ('
    'id INT PRIMARY KEY, '
    'label VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  await seed.executeQuery(
    "INSERT INTO loop_small (id, label) VALUES "
    "(1, 'alpha'), (2, 'beta'), (3, 'gamma') "
    'ON DUPLICATE KEY UPDATE id = id',
  );
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS loop_secret ('
    'id INT PRIMARY KEY, '
    'api_key VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  await seed.executeQuery(
    "INSERT INTO loop_secret (id, api_key) VALUES (1, 'sk-loop-secret-abcdef123456') "
    'ON DUPLICATE KEY UPDATE id = id',
  );
  // 012 DDL 双门靶表：DROP TABLE → 影响分析判 high（requiresConfirmation）
  // → DdlConfirmDialog；非 critical 免键入确认。
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS loop_ddl_gate ('
    'id INT PRIMARY KEY, '
    'label VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  await seed.executeQuery(
    "INSERT INTO loop_ddl_gate (id, label) VALUES (1, 'to-drop') "
    'ON DUPLICATE KEY UPDATE id = id',
  );
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS loop_rows ('
    'id INT PRIMARY KEY AUTO_INCREMENT, '
    'label VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  const batchSize = 500;
  for (var offset = 0; offset < _rowLimitProbeRows; offset += batchSize) {
    final values = StringBuffer();
    for (var n = offset + 1; n <= offset + batchSize; n++) {
      if (values.isNotEmpty) values.write(',');
      values.write("('row_$n')");
    }
    await seed.executeQuery('INSERT INTO loop_rows (label) VALUES $values');
  }
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS loop_big ('
    'id INT PRIMARY KEY AUTO_INCREMENT, '
    'val INT NOT NULL, '
    'payload VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  for (var offset = 0; offset < _bigRows; offset += batchSize) {
    final values = StringBuffer();
    for (var n = offset + 1; n <= offset + batchSize; n++) {
      if (values.isNotEmpty) values.write(',');
      values.write("($n,'payload_$n')");
    }
    await seed.executeQuery(
      'INSERT INTO loop_big (val, payload) VALUES $values',
    );
  }
  try {
    await seed.executeQuery('ANALYZE TABLE loop_big');
  } catch (_) {
    // 统计刷新失败不阻断（InnoDB 新表默认统计亦接近实值）。
  }
}

/// 第二库（011 漂移对照）：**空库**（不含 loop_small）——若读取源漂移到
/// 此，describe/sample 必失败；真实运行全程读主库即快照不漂移的实证。
Future<void> _seedDriftDb(MySQLAdapter seed) async {
  // 刻意留空：仅保证库存在。
}

/// uiPort 缺省 fake（T28：start 的 uiPort 转必填——本套用例不触界面工具，
/// 界面类调用若发生将以失败 outcome 回喂走自纠路径）。
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

const _NoopUiPort _agentUiPort = _NoopUiPort();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  bool gatewayReady = false;
  setUpAll(() async {
    gatewayReady = await ensureEmbeddedServerForMysqlE2E();
  });

  group('Agent 回路簇 · MySQL 主战场（真库）', () {
    MySQLAdapter? seedAdapter;
    DatabaseService? dbService;
    DbServer? server;
    String? testDbName;
    String? driftDbName;
    bool ready = false;

    setUpAll(() async {
      if (!gatewayReady || !MySQLTestConfig.available) return;
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      // 后缀保证与主库名必然不同（生成器毫秒时间戳在背靠背调用下可能
      // 同毫秒同名——曾致主库/漂移库同库：1007/1054/漂移对照计数全链条
      // 由此而来，见 T18 回报）。
      driftDbName = '${MySQLTestConfig.generateTestDatabaseName()}_drift';
      final seed = MySQLAdapter();
      try {
        await seed.connect(
          DatabaseConnection(
            id: 'agent_loop_seed_mysql',
            name: 'Agent Loop E2E Seed',
            type: DatabaseType.mysql,
            host: MySQLTestConfig.host,
            port: MySQLTestConfig.port,
            username: MySQLTestConfig.username,
            password: MySQLTestConfig.password,
          ),
        );
        // 幂等清扫历史遗留测试库（dbmaster_test_* 命名空间归测试所有）：
        // 本文件 setUpAll 种子中途失败时 seedAdapter 尚未赋值、tearDownAll
        // 无从回收——上轮遗留库会让本轮 CREATE TABLE 撞 1050（网关壳
        // stale 库自愈路径还会把语句重发到无库路由）。
        try {
          final leftovers = (await seed.getDatabases())
              .where((String n) => n.startsWith('dbmaster_test_'))
              .toList();
          for (final name in leftovers) {
            try {
              await seed.dropDatabase(name);
            } catch (_) {}
          }
          if (leftovers.isNotEmpty) {
            // ignore: avoid_print
            print('AGENT_LOOP_E2E_CLEANUP: 已清扫遗留测试库 ${leftovers.length} 个');
          }
        } catch (_) {}
        // 建库/建表/种子全幂等（IF NOT EXISTS / ON DUPLICATE KEY）：网关链路
        // 观察到偶发「语句已提交但客户端收到二次执行错误」（1007/1050 时库
        // 实际已建好——诊断探针实证），幂等化后两类结果都收敛为同一终态。
        await seed.executeQuery('CREATE DATABASE IF NOT EXISTS `$testDbName`');
        await seed.useDatabase(testDbName!);
        await _seedMainDb(seed);
        await seed.executeQuery('CREATE DATABASE IF NOT EXISTS `$driftDbName`');
        await seed.useDatabase(driftDbName!);
        await _seedDriftDb(seed);
        await seed.useDatabase(testDbName!);
        seedAdapter = seed;

        // 被测主体：真实 DatabaseService（executor 的 dbAccess/gate 工厂均
        // 绑此连接——生产 AiPanelProvider._buildAgentRunner 同款装配）。
        final svc = DatabaseService();
        final dbServer = DbServer(
          id: 'agent_loop_e2e_mysql',
          name: 'Agent Loop E2E MySQL',
          type: DatabaseType.mysql,
          host: MySQLTestConfig.host,
          port: MySQLTestConfig.port,
          username: MySQLTestConfig.username,
          password: MySQLTestConfig.password,
          database: testDbName,
        );
        ready = await svc.connect(dbServer);
        if (!ready) await svc.disconnect();
        dbService = svc;
        server = dbServer;
      } catch (e) {
        // ignore: avoid_print
        print('AGENT_LOOP_E2E_SKIP: MySQL 环境不可达：$e');
        ready = false;
      }
    });

    tearDownAll(() async {
      final svc = dbService;
      if (svc != null) {
        try {
          await svc.disconnect();
        } catch (_) {}
      }
      final seed = seedAdapter;
      final main = testDbName;
      final drift = driftDbName;
      if (seed != null && seed.isConnected) {
        for (final dbName in <String>[?drift, ?main]) {
          try {
            await seed.executeQuery('DROP DATABASE IF EXISTS `$dbName`');
          } catch (_) {}
        }
        try {
          await seed.disconnect();
        } catch (_) {}
      }
    });

    _LoopHarness newHarness({int maxSteps = 25, bool readOnly = false}) =>
        _LoopHarness(
          dbService: dbService!,
          ctxSource: _CtxSource(
            connectionId: server!.id,
            connectionName: server!.name,
            databaseName: testDbName!,
            dbType: DatabaseType.mysql,
            readOnly: readOnly,
          ),
          maxSteps: maxSteps,
        );

    /// 直查 loop_small 指定行 label（seed adapter 独立会话，绕开被测链路）。
    Future<Map<int, String>> probeLabels() async {
      await seedAdapter!.useDatabase(testDbName!);
      final result = await seedAdapter!.executeQuery(
        'SELECT id, label FROM loop_small ORDER BY id',
      );
      return <int, String>{
        for (final row in result.rows)
          (row['id'] as num).toInt(): '${row['label']}',
      };
    }

    // --------------------------------------------------------------------
    // 001 多步钻取（AC1.1/1.2/2.3 + NF2.1）
    // --------------------------------------------------------------------
    test('AI-LOOP-E2E-001 多步指令 list→describe→sample：步数=调用数、轨迹消息齐、'
        '无确认、审计逐条（AC1.1/1.2/2.3）', () async {
      if (!ready) {
        // ignore: avoid_print
        print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      final h = newHarness();
      addTearDown(h.dispose);

      h.chat.respond(_call(_toolCall('list_tables')));
      h.chat.respond(
        _call(
          _toolCall('describe_table', <String, dynamic>{'table': 'loop_small'}),
        ),
      );
      h.chat.respond(
        _call(
          _toolCall('get_sample_data', <String, dynamic>{
            'table': 'loop_small',
            'limit': 5,
          }),
        ),
      );
      h.chat.respond(
        _text(
          '共 4 张表，loop_small 2 列，样本 3 行',
          usage: const TokenUsage(totalTokens: 50),
        ),
      );

      await h.runner.start(
        uiPort: _agentUiPort,
        userMessage: '了解库结构',
        gates: h.gates,
      );

      // 终态与对账（AC2.3：步数 = 进入执行管线的调用数）。
      expect(h.runner.status, AgentRunStatus.completed);
      expect(h.runner.stepsUsed, 3);
      expect(h.chat.callCount, 4);
      final ends = h.payloads('agent_run_end');
      expect(ends, hasLength(1));
      expect(ends.first['status'], 'completed');
      expect(ends.first['steps'], 3);

      // 轨迹消息齐（§5.2）：用户消息 → 锚点 → 3×(toolCall+toolResult) →
      // 终局，id 序可对账。
      final ids = h.messages.map((AiMessage m) => m.id).toList();
      final String runId = h.runner.activeRunId!;
      expect(
        ids,
        containsAll(<String>['agent_u_$runId', 'agent_anchor_$runId']),
      );
      for (var n = 1; n <= 3; n++) {
        expect(
          ids,
          containsAll(<String>['agent_tc_${runId}_$n', 'agent_tr_${runId}_$n']),
        );
      }
      expect(ids, contains('agent_end_$runId'));
      final anchors = h.payloads('agent_run');
      expect(anchors, hasLength(1));
      final snapshot = anchors.first['contextSnapshot'] as Map<String, dynamic>;
      expect(snapshot['conn'], server!.name);
      expect(snapshot['db'], testDbName);
      expect(snapshot['readOnly'], isFalse);
      expect(snapshot['maxSteps'], 25);

      // 步载荷：工具序列 + 真数据断言。
      final steps = h.steps;
      expect(steps.map((Map<String, dynamic> s) => s['tool']), <String>[
        'list_tables',
        'describe_table',
        'get_sample_data',
      ]);
      for (final s in steps) {
        expect(s['runId'], runId);
        expect(s['gateDecision'], 'allowed', reason: '小表查询干净放行');
        expect(s.containsKey('error'), isFalse);
      }
      final sample = steps[2];
      final resultRef = sample['resultRef'] as Map<String, dynamic>;
      expect(resultRef['rowCount'], 3, reason: 'loop_small 真实 3 行');
      final snapshotRows = (resultRef['snapshotRows'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(snapshotRows, isNotEmpty);
      expect(snapshotRows.first.keys, containsAll(<String>['id', 'label']));
      expect(
        snapshotRows
            .map((Map<String, dynamic> r) => (r['id'] as num).toInt())
            .toSet(),
        <int>{1, 2, 3},
        reason: '样本行 == 种子真实数据',
      );
      expect(steps[1]['summary'].toString(), contains('loop_small'));

      // AC1.1 全程无确认：无门卡消息。
      expect(h.payloads('agent_confirm'), isEmpty);
      expect(h.seenImpacts, isEmpty);

      // 审计逐条（AC13.1：3 步 3 条，同 runId/connectionId/databaseName）。
      expect(h.auditTap.records, hasLength(3));
      for (final r in h.auditTap.records) {
        expect(r['runId'], runId);
        expect(r['connectionId'], server!.id);
        expect(r['databaseName'], testDbName);
        expect(r['success'], isTrue);
      }

      // NF2.1：chat 请求目标 == 用户配置提供商（无 server 端点路径）。
      expect(h.chat.requests, isNotEmpty);
      for (final req in h.chat.requests) {
        expect(req.provider, _userProvider);
        expect(req.model, _userModel);
        expect(req.apiKey, _userApiKey);
        expect(req.baseUrl, _userBaseUrl);
        expect(req.baseUrl, isNot(contains('127.0.0.1')));
        expect(req.baseUrl, isNot(contains('/api/gw')));
      }
      // 工具目录全集 = activeMilestone 可寻址工具数（按目录推导不写死：
      // A2 合龙后 = 14（A1 六工具 + A2 八工具）；milestone 再推进时自动
      // 跟随，不再像固定数字那样过期）。
      expect(
        h.chat.requests.first.tools,
        hasLength(
          AgentToolCatalog.specsFor(
            milestone: AgentToolCatalog.activeMilestone,
          ).length,
        ),
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    // --------------------------------------------------------------------
    // 002 写语句走只读通道（AC4.2/AC15.3）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-002 写语句走只读通道 → WRITE_REJECTED + 库前后零变化（AC4.2/AC15.3）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final before = await probeLabels();

        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': "UPDATE loop_small SET label = 'hacked' WHERE id = 1",
            }),
          ),
        );
        h.chat.respond(_text('写语句被拒，我改为只读分析'));

        await h.runner.start(uiPort: _agentUiPort, userMessage: '把 id=1 改名');

        // 门可能已放行（小表），拦截在 handler 只读闸——审计 blocked。
        final steps = h.steps;
        expect(steps, hasLength(1));
        final error = steps.first['error'] as Map<String, dynamic>;
        expect(error['code'], AgentToolErrorCodes.writeRejectedReadonlyChannel);
        expect(
          error['message'],
          contains('submit_action_plan'),
          reason: 'AC4.2 指引面：错误文案指向行动计划路径',
        );
        expect(h.dbTap.executeQueryCalls, 0, reason: '写语句零执行');
        expect(
          h.auditTap.records.first['gateDecision'],
          AgentGateDecision.blocked,
          reason: 'D13：拦截尝试也落审计（success=false）',
        );
        expect(h.auditTap.records.first['success'], isFalse);
        expect(h.auditTap.records.first['sql'], contains('UPDATE'));

        // 库前后零变化（重查断言）。
        final after = await probeLabels();
        expect(after, equals(before), reason: 'AC15.3 门拦零副作用');
        // 回喂自纠：run 不因拦截停止。
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 003 行限同源（AC4.3）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-003 超 3000 行结果 → agent 行数上限与手动执行一致（AC4.3）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        const sql = 'SELECT id FROM loop_rows';

        // 同设置对照：手动执行（同一 dbService、同一查询设置管线）。
        final manualRows = await dbService!.executeQuery(sql);

        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{'sql': sql}),
          ),
        );
        h.chat.respond(_text('共 3500 行，已按行限返回'));

        await h.runner.start(uiPort: _agentUiPort, userMessage: '全量拉取');

        final steps = h.steps;
        expect(steps, hasLength(1));
        final resultRef = steps.first['resultRef'] as Map<String, dynamic>;
        expect(
          resultRef['rowCount'],
          manualRows.length,
          reason: 'agent 行限 == 手动执行行限（AC4.3 同源）',
        );
        expect(manualRows.length, 3000, reason: '3,500 行种子 × 默认 3000 行限');
        expect(
          h.dbTap.executedSql.first,
          sql,
          reason: 'agent 通道消费与手动相同的 executeQuery 管线（行限在管线内追加）',
        );
        // D19：会话步消息快照 ≤10 行（大结果只进内存引用）。
        final snapshotRows = resultRef['snapshotRows'] as List<dynamic>;
        expect(snapshotRows, hasLength(10));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 004 L0.5 确认取消 → 读未执行（AC8.2 回路面）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-004 L0.5 确认卡拒绝 → GATE_REJECTED、零执行、审计 rejected_by_user',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = newHarness();
        addTearDown(h.dispose);
        const sql = 'SELECT * FROM loop_big';
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{'sql': sql}),
          ),
        );
        h.chat.respond(_text('已按拒绝收敛，改用采样'));

        final GateCallbacks g = h.gates;
        final runFuture = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '全表扫一遍',
          gates: g,
        );
        final reached = await _waitUntil(
          () => h.runner.status == AgentRunStatus.awaitingUser,
        );
        expect(reached, isTrue, reason: '大表全查应进确认等待（D7 阻塞等人）');

        // 确认卡数据面：真 EXPLAIN 影响面（AC8.4 数据面在回路的形态）。
        expect(h.seenConfirmSql, <String>[sql]);
        final impact = h.seenImpacts.single;
        expect(impact.estimatedRows, isNotNull);
        expect(impact.estimatedRows!, greaterThanOrEqualTo(_l05Threshold));
        expect(impact.fullScan, isTrue);
        // 零执行时点：确认未决 → 读未发起。
        expect(h.dbTap.executeQueryCalls, 0);

        h.cardCompleter.complete(GateCardResult.rejected);
        await runFuture;

        final steps = h.steps;
        expect(steps, hasLength(1));
        final error = steps.first['error'] as Map<String, dynamic>;
        expect(error['code'], AgentToolErrorCodes.gateRejected);
        expect(h.dbTap.executeQueryCalls, 0, reason: '人拒后读未执行（AC8.2 回路面）');
        expect(steps.first.containsKey('resultRef'), isFalse);
        expect(
          h.auditTap.records.first['gateDecision'],
          AgentGateDecision.rejectedByUser,
        );
        expect(h.auditTap.records.first['success'], isFalse);
        // 回喂自纠：run 继续收敛 completed（拒绝不等于停止）。
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 005 超限停止 + 可接续（AC2.2/AC2.4）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-005 步数超限 → 部分执行 + stoppedByLimit 汇报 + 不自动续；新指令可接续（AC2.2/2.4）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = newHarness(maxSteps: 2);
        addTearDown(h.dispose);
        // 一轮 3 个 tool_calls：预算 2 → 前 2 执行、第 3 占位不执行。
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

        await h.runner.start(uiPort: _agentUiPort, userMessage: '连查三次');

        expect(h.runner.status, AgentRunStatus.stoppedByLimit);
        expect(h.runner.stepsUsed, 2, reason: '预算内 2 步（部分执行语义）');
        expect(h.chat.callCount, 1, reason: '不自动请求继续（AC2.2）');
        expect(h.statsTap.limitStops, 1, reason: '字段 9：超限停止计数');
        final ends = h.payloads('agent_run_end');
        expect(ends.first['status'], 'stoppedByLimit');
        expect(ends.first['steps'], 2);
        expect(
          ends.first['summaryText'].toString(),
          contains('2/2'),
          reason: '现状汇报：步数/上限可观察',
        );
        expect(h.auditTap.records, hasLength(2), reason: '占位调用不执行不落审计');

        // 可接续（AC2.4）：用户发新指令 → 新 runId、计步归零。
        h.chat.respond(_text('接续完成'));
        await h.runner.start(uiPort: _agentUiPort, userMessage: '继续');
        final run2 = h.payloads('agent_run');
        expect(run2, hasLength(2), reason: '接续 run 落新锚点');
        expect(h.runner.activeRunId, isNot(ends.first['runId']));
        expect(h.runner.stepsUsed, 0);
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 006 连续失败上限（D18/NF3.2）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-006 连续 5 个失败工具调用 → stoppedByFailures 汇报（D18/NF3.2）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = newHarness();
        addTearDown(h.dispose);
        // 脚本化持续失败：describe_table 缺 table 参数 → INVALID_ARGUMENTS
        //（handler 拒绝，确定性失败，不依赖库错误形态）。
        for (var i = 0; i < 5; i++) {
          h.chat.respond(_call(_toolCall('describe_table')));
        }

        await h.runner.start(uiPort: _agentUiPort, userMessage: '反复给坏参数');

        expect(h.runner.status, AgentRunStatus.stoppedByFailures);
        expect(h.runner.stepsUsed, 5, reason: '被拒调用也计步（D10）');
        expect(h.chat.callCount, 5);
        final ends = h.payloads('agent_run_end');
        expect(ends.first['status'], 'stoppedByFailures');
        final endMsg = h.messages.last;
        expect(endMsg.content, contains('5'), reason: '汇报连续失败次数');
        expect(endMsg.content, contains('describe_table'), reason: '汇报失败工具');
        for (final r in h.auditTap.records) {
          expect(r['success'], isFalse);
        }
        expect(h.auditTap.records, hasLength(5));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 007 readOnly 连接写意图 → 全链零 executeQuery（NF2.3）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-007 readOnly 连接写意图 → 全链零 executeQuery（NF2.3）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = newHarness(readOnly: true);
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': "DELETE FROM loop_small WHERE id = 3",
            }),
          ),
        );
        h.chat.respond(_text('只读连接，写意图被拒'));

        await h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '删掉 id=3',
          gates: h.gates,
        );

        final anchors = h.payloads('agent_run');
        expect(anchors.first['contextSnapshot']['readOnly'], isTrue);
        final steps = h.steps;
        expect(steps, hasLength(1));
        final error = steps.first['error'] as Map<String, dynamic>;
        expect(error['code'], AgentToolErrorCodes.writeRejectedReadonlyChannel);
        // NF2.3 断言面：整个 run 全链零 executeQuery。
        expect(h.dbTap.executeQueryCalls, 0);
        expect(h.dbTap.executedSql, isEmpty);
        // 对照：同一连接读通道本身可用（零执行非连接失效所致）。
        final control = await dbService!.executeQuery(
          'SELECT COUNT(*) AS c FROM loop_small',
        );
        expect((control.first['c'] as num).toInt(), 3);
        // 库未变。
        expect((await probeLabels()).length, 3);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 008 敏感字面量（AC13.2/NF2.2/NF6.2 字符串断言）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-008 敏感字面量会话 → 审计入档 SQL 脱敏、prefs 落盘串与统计导出不含明文（AC13.2/NF2.2）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        const secret = 'sk-loop-secret-abcdef123456';
        final sql = "SELECT id FROM loop_secret WHERE api_key = '$secret'";

        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{'sql': sql}),
          ),
        );
        h.chat.respond(_text('命中 1 行'));

        await h.runner.start(uiPort: _agentUiPort, userMessage: '按密钥查一行');

        // 功能真生效：查询成功且命中种子行（敏感断言前的通路证明）。
        final steps = h.steps;
        expect(steps, hasLength(1));
        expect(steps.first.containsKey('error'), isFalse);
        expect(
          (steps.first['resultRef'] as Map<String, dynamic>)['rowCount'],
          1,
        );
        // 敏感面确实流经审计入口（tap 捕获的是脱敏前原文）。
        expect(h.auditTap.records.first['sql'], contains(secret));

        // 真实入档面 1：AuditLogService 内存入档（=落盘内容）已脱敏。
        final runId = h.runner.activeRunId;
        final entries = AuditLogService()
            .getRecentEntries(limit: 50)
            .where((e) => e.agentRunId == runId)
            .toList();
        expect(entries, isNotEmpty, reason: '转发真实审计服务的入档记录');
        for (final e in entries) {
          expect(e.sql, isNot(contains(secret)));
          expect(e.sql, contains('***'), reason: 'api_key 字面量被 *** 替换');
          expect(e.errorMessage ?? '', isNot(contains(secret)));
        }

        // 真实入档面 2：防抖（2s）后的 prefs 落盘串不含明文。
        await Future<void>.delayed(const Duration(milliseconds: 2600));
        final prefs = await SharedPreferences.getInstance();
        final persisted = prefs.getString('audit_logs') ?? '';
        expect(persisted, isNotEmpty, reason: '防抖后审计应已写 prefs');
        expect(persisted, isNot(contains(secret)));

        // 导出面：统计导出 JSON 不含明文（NF6.2）。
        final exportJson = jsonEncode(
          WorkbenchUsageStatsService()
              .exportJson(appVersion: 'agent-loop-e2e')
              .toJson(),
        );
        expect(exportJson, isNot(contains(secret)));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 009 chat 抛错 → failed（AC15.5）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-009 chat 抛错 → failed 终局 + 脱敏明细 + 重发可用（AC15.5）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.failWith(
          Exception('API error: 401 invalid api_key=sk-live-9f8e7d6c'),
        );

        await h.runner.start(uiPort: _agentUiPort, userMessage: '你好');

        expect(h.runner.status, AgentRunStatus.failed);
        final ends = h.payloads('agent_run_end');
        expect(ends.first['status'], 'failed');
        final endMsg = h.messages.last;
        expect(endMsg.status, AiMessageStatus.failed);
        expect(endMsg.errorMessage, isNotNull);
        // NF2.2：错误明细过 redactSecrets（api_key= 掩码）。
        expect(endMsg.errorMessage, isNot(contains('sk-live-9f8e7d6c')));
        expect(endMsg.errorMessage, contains('***'));
        // chat 层错误不计 D18 失败计数：零步。
        expect(h.runner.stepsUsed, 0);

        // 重试出口（AC15.5 服务面 = regenerate 语义的重发）：新 run 可用。
        h.chat.respond(_text('恢复后的回复'));
        await h.runner.start(uiPort: _agentUiPort, userMessage: '重发');
        expect(h.runner.status, AgentRunStatus.completed);
        expect(h.payloads('agent_run_end').last['status'], 'completed');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 010 杀进程重启 → 中断态不续跑（AC15.6，会话消息级断言）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-010 杀进程重启 → 会话消息有锚点无终局、分组中断态、新 runner 不续跑（AC15.6）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final killedManager = createIsolatedAiSessionManager()..createSession();
        final h = _LoopHarness(
          dbService: dbService!,
          ctxSource: _CtxSource(
            connectionId: server!.id,
            connectionName: server!.name,
            databaseName: testDbName!,
            dbType: DatabaseType.mysql,
          ),
          sessionManager: killedManager,
        );
        addTearDown(h.dispose);

        // 第 1 轮 chat 永不返回（进程在途中被杀）；后续脚本仅供收敛清理。
        final Completer<ChatResponse> round1 = Completer<ChatResponse>();
        h.chat.queue.add(() => round1.future);

        final runFuture = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '中断我',
          gates: h.gates,
        );
        final running = await _waitUntil(
          () => h.runner.status == AgentRunStatus.running,
        );
        expect(running, isTrue);

        // 「杀进程」：以当时会话消息列（= persist() 的写入内容）为落盘快照。
        final persisted = killedManager.currentMessages
            .map((AiMessage m) => m.copyWith())
            .toList();
        expect(
          persisted.any((AiMessage m) => _payloadOf(m)?['kind'] == 'agent_run'),
          isTrue,
          reason: '锚点已落账',
        );
        expect(
          persisted.any(
            (AiMessage m) => _payloadOf(m)?['kind'] == 'agent_run_end',
          ),
          isFalse,
          reason: '无终局（run 在途中断）',
        );

        // 新进程：恢复同一会话消息（load() 自会话文件的等价形态），新
        // runner 构造其上——不从消息恢复运行态（FC-6 不续跑）。
        final revived = createIsolatedAiSessionManager()..createSession();
        revived.updateMessages(persisted);
        final h2 = _LoopHarness(
          dbService: dbService!,
          ctxSource: _CtxSource(
            connectionId: server!.id,
            connectionName: server!.name,
            databaseName: testDbName!,
            dbType: DatabaseType.mysql,
          ),
          sessionManager: revived,
        );
        addTearDown(h2.dispose);
        expect(h2.runner.status, AgentRunStatus.idle);
        expect(h2.runner.isRunning, isFalse);
        expect(h2.runner.activeRunId, isNull);

        // 中断态分组（AC15.6 渲染数据源）：有锚点无终局 → interrupted 组。
        final segments = agentTrajectoryGrouping(
          revived.currentMessages.toList(),
        );
        final runSegments = segments.where((s) => s.isRun).toList();
        expect(runSegments, hasLength(1));
        expect(runSegments.first.run!.terminal, isNull);
        expect(runSegments.first.run!.messages, isNotEmpty);

        // 新指令可用（不自动续跑 ≠ 会话死亡）。
        h2.chat.respond(_text('新进程继续'));
        await h2.runner.start(uiPort: _agentUiPort, userMessage: '重新开始');
        expect(h2.runner.status, AgentRunStatus.completed);
        final ends = h2.payloads('agent_run_end');
        expect(ends, hasLength(1));
        expect(ends.first['status'], 'completed');
        expect(
          agentTrajectoryGrouping(
            revived.currentMessages.toList(),
          ).where((s) => s.isRun).length,
          2,
          reason: '中断组 + 新 run 组并存',
        );

        // 收敛清理：让被杀 run 干净终局（不悬垂 future）。
        round1.complete(_text('迟到'));
        await runFuture;
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 011 运行中切上下文源 → 快照不漂移（AC7.2/D15）
    // --------------------------------------------------------------------
    test(
      'AI-LOOP-E2E-011 运行中切侧栏/tab → 读取来源不漂移（双库对照，AC7.2/D15）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final src = _CtxSource(
          connectionId: server!.id,
          connectionName: server!.name,
          databaseName: testDbName!,
          dbType: DatabaseType.mysql,
        );
        final h = _LoopHarness(dbService: dbService!, ctxSource: src);
        addTearDown(h.dispose);

        // 第 1 步按 dbA 描述；第 2 轮 chat 触发时切源（模拟切侧栏/切 tab）
        // 后再要求一次描述 + 一次采样——漂移靶 dbB 为空库（无 loop_small），
        // 若读取源随源漂移，describe/sample 必然失败。
        h.chat.respond(
          _call(
            _toolCall('describe_table', <String, dynamic>{
              'table': 'loop_small',
            }),
          ),
        );
        h.chat.queue.add(() async {
          src.databaseName = driftDbName!;
          return _call(
            _toolCall('describe_table', <String, dynamic>{
              'table': 'loop_small',
            }),
          );
        });
        h.chat.respond(
          _call(
            _toolCall('get_sample_data', <String, dynamic>{
              'table': 'loop_small',
              'limit': 5,
            }),
          ),
        );
        h.chat.respond(_text('两次结构一致，样本来自锁定库'));

        await h.runner.start(uiPort: _agentUiPort, userMessage: '结构对比');

        expect(h.runner.status, AgentRunStatus.completed);
        // 锚点快照 = 启动时锁定值。
        final anchors = h.payloads('agent_run');
        expect(anchors.first['contextSnapshot']['db'], testDbName);
        // 执行边界：describe/execute 的 database 参数全程 = 启动快照。
        expect(h.dbTap.describeColumnCalls, hasLength(2));
        for (final c in h.dbTap.describeColumnCalls) {
          expect(c.database, testDbName, reason: 'D15：快照全程只读');
        }
        for (final d in h.dbTap.executeDatabases) {
          expect(d, testDbName);
        }
        // 真数据面：采样行列来自 dbA（label），非 dbB（note）。
        final steps = h.steps;
        final sample = steps[2];
        final rows =
            (sample['resultRef'] as Map<String, dynamic>)['snapshotRows']
                as List<dynamic>;
        expect(rows, isNotEmpty);
        expect(rows.first as Map<String, dynamic>, contains('label'));
        expect(rows.first as Map<String, dynamic>, isNot(contains('note')));
        // 审计 databaseName 全程 = 启动快照。
        for (final r in h.auditTap.records) {
          expect(r['databaseName'], testDbName);
        }
        // 对照：漂移目标库确无 loop_small（漂移若发生必然失败）。
        await seedAdapter!.useDatabase(testDbName!);
        final driftCheck = await seedAdapter!.executeQuery(
          "SELECT COUNT(*) AS c FROM information_schema.tables "
          "WHERE table_schema = '$driftDbName' AND table_name = 'loop_small'",
        );
        expect((driftCheck.rows.first['c'] as num).toInt(), 0);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // --------------------------------------------------------------------
    // 012 L1 兜底（AC9.4/AC10.1-10.3 A1 形态）—— widget e2e
    // --------------------------------------------------------------------
    testWidgets(
      'AI-LOOP-E2E-012 L1 兜底：回复文本产出 SQL → agent 零执行 → M1 SQL 卡 + 写确认/DDL 双门',
      (tester) async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_LOOP_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        // B1：写批执行会推 execution tab 打开舞台 → 对话列收窄，测试字体
        // （Ahem 方块字）下 SQL 卡四动作钮 header 假性溢出（真机放得下
        // 520 档；与 workbench_mysql_e2e_test.dart 同款吞咽——仅 RenderFlex
        // overflow 类报告，其余原样转交既有处理器）。
        final previousOverflowHandler = FlutterError.onError;
        addTearDown(() => FlutterError.onError = previousOverflowHandler);
        FlutterError.onError = (FlutterErrorDetails details) {
          if (details.exception.toString().contains('RenderFlex overflowed')) {
            return;
          }
          previousOverflowHandler?.call(details);
        };
        const updateSql =
            "UPDATE loop_small SET label = 'manual_applied' WHERE id = 2 LIMIT 1";
        const ddlSql = 'DROP TABLE loop_ddl_gate';
        final modelReply =
            '当前目录没有 submit_action_plan 工具，'
            '请手动执行以下语句（会经过确认流）：\n```sql\n$updateSql\n```';

        // ── 阶段 A（真实 IO 在 runAsync 区）：脚本化模型经回路产出写 SQL ──
        final before = <int, String>{};
        AppProvider? appProviderRef;
        await tester.runAsync(() async {
          final h = newHarness();
          h.chat.respond(_call(_toolCall('list_tables')));
          h.chat.respond(_text(modelReply));
          await h.runner.start(uiPort: _agentUiPort, userMessage: '把 id=2 改名');
          expect(h.runner.status, AgentRunStatus.completed);
          // 终局正文携带完整写 SQL（AC9.4 A1 兜底：写语句进回复文本）。
          final ends = h.payloads('agent_run_end');
          expect(ends, hasLength(1));
          final endMsg = h.messages.last;
          expect(endMsg.content, contains(updateSql));
          // agent 通道零执行：写 SQL 从未触达 executeQuery 管线。
          expect(
            h.dbTap.executeQueryCalls,
            0,
            reason: 'list_tables 走 getTables；写语句只在回复文本',
          );
          for (final r in h.auditTap.records) {
            expect(r['sql'], isNot(contains(updateSql)));
          }
          before.addAll(await probeLabels());
          expect(before[2], isNot('manual_applied'), reason: '前置：尚未手动执行');

          // ── 阶段 B：真实 AppProvider 连接（M1 工作台 e2e 模式）──
          // Fix-H：注入存储隔离 manager，ensureSession/addAiMessage 的
          // 持久化落临时目录，不写真实 Documents/prefs。
          final provider = AppProvider(
            aiSessionManager: createIsolatedAiSessionManager(),
          );
          appProviderRef = provider;
          AppProvider.devBypassGates = true;
          provider.aiPanel.ensureSession();
          await provider.connection.saveConnection(server!);
          final connected = await provider.connectToServer(server!);
          expect(connected, isTrue, reason: 'AppProvider 连接 MySQL');
          await provider.refreshDatabases();
          await provider.openQueryTab(server!.id, testDbName!, sql: 'SELECT 1');
        });
        final AppProvider appProvider = appProviderRef!;

        try {
          // ── 阶段 C：泵工作台壳，模型产出的 SQL 经 M1 卡渲染层（code 拦截，
          //    与真实 AI 回复同一渲染路径）──
          tester.view.physicalSize = const Size(1280, 1000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          appProvider.setAiPanelOpen(true);
          appProvider.setAiPanelFullscreen(true);
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<AppProvider>.value(value: appProvider),
                // B3/B1 适配（同 workbench_mysql_e2e_test.dart harness）：
                // 舞台布局段消费 LayoutPreferencesProvider（对话列宽双模
                // 持久化），execution tab 推送打开舞台会构建
                // _buildStageLayout——harness 树补齐该 provider（与
                // main.dart 真实装配一致）。
                ChangeNotifierProvider<LayoutPreferencesProvider>(
                  create: (_) => LayoutPreferencesProvider()..load(),
                ),
              ],
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('en'),
                home: const Scaffold(body: AiWorkbenchShell()),
              ),
            ),
          );
          await tester.pumpAndSettle(const Duration(seconds: 2));

          Future<void> landModelSql(String sql) async {
            appProvider.addAiMessage(
              AiMessage(
                id: 'ai_model_sql_${DateTime.now().millisecondsSinceEpoch}',
                isUser: false,
                content: 'From the model reply:',
                timestamp: DateTime.now(),
                code: sql,
                status: AiMessageStatus.completed,
              ),
            );
            await tester.pumpAndSettle(const Duration(seconds: 1));
          }

          WorkbenchResultCardPayload? lastResultCard() {
            for (final message in appProvider.aiMessages.reversed) {
              final raw = message.toolResultData?['workbench'];
              if (raw is Map) {
                final payload = WorkbenchResultCardPayload.fromJson(
                  Map<String, dynamic>.from(raw),
                );
                if (payload != null) return payload;
              }
            }
            return null;
          }

          WorkbenchErrorCardPayload? lastErrorCard() {
            for (final message in appProvider.aiMessages.reversed) {
              final raw = message.toolResultData?['workbench'];
              if (raw is Map) {
                final error = WorkbenchErrorCardPayload.fromJson(
                  Map<String, dynamic>.from(raw),
                );
                if (error != null) return error;
              }
            }
            return null;
          }

          Future<bool> waitUntilCard(bool Function() predicate) async {
            final deadline = DateTime.now().add(const Duration(seconds: 30));
            while (!predicate()) {
              if (DateTime.now().isAfter(deadline)) return false;
              await tester.pump(const Duration(milliseconds: 100));
            }
            return true;
          }

          // —— DML：写徽标 + 写确认门（取消零变化 / 确认生效）——
          await landModelSql(updateSql);
          final executeButton = find.byKey(SqlToolCard.executeButtonKey);
          expect(executeButton, findsOneWidget, reason: 'M1 SQL 卡渲染执行按钮');
          expect(
            find.byKey(SqlToolCard.writeBadgeKey),
            findsOneWidget,
            reason: 'UPDATE 判写并渲染危险徽标',
          );

          await tester.ensureVisible(executeButton);
          await tester.tap(executeButton);
          await tester.pump();
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          final writeDialog = find.byType(ConfirmExecuteDialog);
          expect(writeDialog, findsOneWidget, reason: '写 SQL 执行必经写确认门');
          expect(
            find.descendant(of: writeDialog, matching: find.text(updateSql)),
            findsOneWidget,
            reason: '确认框含 SQL 全文',
          );

          // 取消路径：库零变化。
          await tester.tap(
            find.descendant(
              of: writeDialog,
              matching: find.widgetWithText(TextButton, 'Cancel'),
            ),
          );
          await tester.pumpAndSettle(const Duration(seconds: 2));
          final afterCancel = await tester.runAsync(probeLabels);
          expect(afterCancel![2], before[2], reason: '取消后数据库零变化');
          expect(lastResultCard(), isNull, reason: '取消后无结果卡（零执行）');

          // 确认路径：库已变更。
          await tester.tap(find.byKey(SqlToolCard.executeButtonKey));
          await tester.pump();
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          expect(find.byType(ConfirmExecuteDialog), findsOneWidget);
          await tester.tap(
            find.descendant(
              of: find.byType(ConfirmExecuteDialog),
              matching: find.widgetWithText(ElevatedButton, 'Confirm Execute'),
            ),
          );
          final landed = await waitUntilCard(
            () => lastResultCard() != null || lastErrorCard() != null,
          );
          expect(
            landed,
            isTrue,
            reason: '确认后执行应落卡（错误卡原文：${lastErrorCard()?.detail}）',
          );
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(lastResultCard(), isNotNull, reason: '确认路径应落结果卡');
          final afterConfirm = await tester.runAsync(probeLabels);
          expect(afterConfirm![2], 'manual_applied', reason: '确认后数据库已变更');

          // —— DDL 双门（写确认门 + 管线 DML 危险门）：DROP TABLE 在真管
          //    线上由 DmlSafetyService 判 critical（dropTable 触发器）→
          //    DmlConfirmationRequiredException → DmlConfirmDialog（键入
          //    表名确认后经 executeQueryBypassDml 执行）。
          await landModelSql(ddlSql);
          // 树中此刻有两张 SQL 卡（DML 已落）——取最后一张（本次落地的）。
          final ddlButton = find.byKey(SqlToolCard.executeButtonKey).last;
          await tester.ensureVisible(ddlButton);
          await tester.tap(ddlButton);
          await tester.pump();
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          // gate #1：写确认。
          expect(
            find.byType(ConfirmExecuteDialog),
            findsOneWidget,
            reason: 'DDL 先过写确认门（gate #1）',
          );
          await tester.tap(
            find.descendant(
              of: find.byType(ConfirmExecuteDialog),
              matching: find.widgetWithText(ElevatedButton, 'Confirm Execute'),
            ),
          );
          await tester.pump();
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          // gate #2：管线危险操作门（AC10.1-10.3 双门形态）。
          final dmlDialog = find.byType(DmlConfirmDialog);
          expect(
            dmlDialog,
            findsOneWidget,
            reason:
                'DROP TABLE 判 critical → DmlConfirmationRequiredException '
                '→ DmlConfirmDialog',
          );
          final WorkbenchResultCardPayload? cardBeforeDdl = lastResultCard();
          // critical 档需键入受影响对象名确认（DestructiveConfirmDialog）。
          await tester.enterText(
            find.descendant(of: dmlDialog, matching: find.byType(TextField)),
            'loop_ddl_gate',
          );
          await tester.pump();
          await tester.tap(
            find.descendant(
              of: dmlDialog,
              matching: find.widgetWithText(
                ElevatedButton,
                'Confirm Execution',
              ),
            ),
          );
          final ddlLanded = await waitUntilCard(
            () =>
                lastErrorCard() != null ||
                (lastResultCard() != null &&
                    !identical(lastResultCard(), cardBeforeDdl)),
          );
          expect(
            ddlLanded,
            isTrue,
            reason: 'DDL 确认后执行应落新卡（错误卡原文：${lastErrorCard()?.detail}）',
          );
          await tester.pumpAndSettle(const Duration(seconds: 2));
          expect(
            lastErrorCard(),
            isNull,
            reason: 'DDL 双门确认后应成功（错误卡原文：${lastErrorCard()?.detail}）',
          );
          // 功能真生效：重查断言表已被删除（DROP 真实落库）。
          final tableGone = await tester.runAsync(() async {
            await seedAdapter!.useDatabase(testDbName!);
            final r = await seedAdapter!.executeQuery(
              "SELECT COUNT(*) AS c FROM information_schema.tables "
              "WHERE table_schema = '$testDbName' AND table_name = 'loop_ddl_gate'",
            );
            return (r.rows.first['c'] as num).toInt() == 0;
          });
          expect(tableGone, isTrue, reason: 'DDL 双门确认后表真实删除');
        } finally {
          final provider = appProviderRef;
          if (provider != null) {
            await tester.runAsync(() async {
              try {
                await provider.disconnectConnection(connectionId: server!.id);
              } catch (_) {}
              try {
                provider.dispose();
              } catch (_) {}
              try {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('saved_queries');
                await prefs.remove('recent_tables');
                await prefs.remove('sidebar_favorite_tables');
                await prefs.remove('connection_groups');
                await prefs.remove('workbench_stats_v1');
              } catch (_) {}
            });
          }
        }
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });
}
