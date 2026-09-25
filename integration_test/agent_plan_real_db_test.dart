// ============================================================================
// Agent 计划链路簇真库集成测试（tasks-ai-agent.md T29 / design-ai-agent.md
// §6.7 计划簇（AC9.1/9.2/9.3/10.3/10.4/11.1-11.4、NF2.3 计划形态）+ §4.5
// 界面工具链组件面收口）。
//
// 被测：AgentLoopRunner + AgentToolExecutor + AgentPlanExecutor + 真实
// AgentUiPortImpl/WorkbenchStageController 的生产装配形态（计划批准回调按
// shell `_onPlanApproval` 语义镜像：L1 会话放行短路 + approvedForSession
// 登记 + approve → execute，deps 绑真 dbService 执行管线与脚本化
// ddlConfirm/dmlConfirm 确认回调——对话框 UI 是确认面，脚本化为决策），
// **唯一 mock = LLM chat 层**（脚本化 AgentChatFn，NF5.3 注入面；数据库
// 服务不 mock——经 embedded dbmaster server /api/gw 走真实测试库）。
//
// 覆盖（八方向 + AC4.4 方言实证）：
//   001 AC4.4 越界构造（MySQL 两段式执法）：锁 dbmaster_test_* 库 →
//       SELECT * FROM other.t / get_sample_data('other.t') →
//       INVALID_ARGUMENTS + 零 executeQuery 探针；同库限定名放行；
//   002 计划批准前零变化（AC9.1 重查断言）+ 批准后逐句落库；
//   003 拒绝零副作用 + 对话继续（AC9.2）；
//   004 计划内 DDL 逐次双门（dmlConfirm/ddlConfirm 门次数断言，AC10.3/10.4）；
//   005 中途失败边界（第 2 句构造失败）→ 三段可见 + 回退卡 + 回退过门 +
//       rolledBack 流转（AC11.1-11.3）；
//   006 planId 重放 → PLAN_ALREADY_EXECUTED 零库操作（AC11.4）；
//   007 readOnly 连接 submit → READONLY_CONNECTION 全链零 executeQuery
//       （NF2.3 计划形态）；
//   008 L1 会话放行短路（第二次 submit 免卡 + 逐语句审计对账，AC9.3 链路面
//       ——决策回调内 ledger.allowL1 登记（shell `_onPlanApproval`
//       approvedForSession 分支同款镜像）；UI 勾选面（Fix-E
//       agent_plan_card sessionCheckboxKey）归 AgentPlanCard 自身 widget
//       测试，本套驱动链路面）；
//   009 界面工具链（open_result_grid/pin_artifact/open_sql_editor/
//       render_chart/show_table_structure → 真 AgentUiPortImpl +
//       WorkbenchStageController 舞台/产物条状态断言 + 编辑器不自动执行 +
//       大结果 ref 全量行与行限一致，AC5.1-5.4）；
//   010 建议卡点击 → 新经典 tab 落位 + 审计（AC6.2/6.4，widget e2e）；
//   SS/CH 组：AC4.4 方言扩面执法断言（SS 三段式 / CH 两段式——Fix-G（M5）
//       已把两形态并入执法面，见 agent_tool_executor.dart 方言分立段数判定；
//       探针断言已翻转为「执法守卫拒绝」，穿透分支保留为违规告警）。
//
// 自建自删专用库（generateTestDatabaseName()，绝不污染共享状态、不依赖
// 用例间顺序；CH 账号无 DROP 授权——清理尽力而为并打印 leftover 标记）。
// 环境不可达（embedded server 二进制缺失 / DBMASTER_* 缺参 / 连不上）时
// 以可 grep 的 AGENT_PLAN_E2E_SKIP / SS_PLAN_E2E_SKIP / CH_PLAN_E2E_SKIP
// 打印并跳过（无假绿，沿 AGENT_LOOP_E2E_SKIP 惯例）。
//
// 运行（Windows 示例，凭据见 workspace test_db_server.txt）：
//   DBMASTER_SERVER_BIN=dist/Release/dbmaster-server.exe \
//   flutter test integration_test/agent_plan_real_db_test.dart \
//     --dart-define=DBMASTER_MYSQL_HOST=192.168.3.128 \
//     --dart-define=DBMASTER_MYSQL_USER=root \
//     --dart-define=DBMASTER_MYSQL_PASSWORD=... \
//     --dart-define=DBMASTER_SQLSERVER_HOST=192.168.3.128 \
//     --dart-define=DBMASTER_SQLSERVER_USER=sa \
//     --dart-define=DBMASTER_SQLSERVER_PASSWORD=... \
//     --dart-define=DBMASTER_CH_HOST=192.168.3.128 \
//     --dart-define=DBMASTER_CH_USER=ch_test \
//     --dart-define=DBMASTER_CH_PASSWORD=...
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
import 'package:dbmaster/models/ai_models.dart'
    show AiToolCall, ChatResponse, TokenUsage;
import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart'
    show AiMessage, DatabaseType, DbServer;
import 'package:dbmaster/organisms/ai_workbench/agent_ui_port_impl.dart';
import 'package:dbmaster/organisms/ai_workbench/agents/agent_suggestion_card.dart';
import 'package:dbmaster/organisms/ai_workbench/ai_workbench_shell.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/clickhouse_adapter.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentGate, AgentRunContext;
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show AgentGateAnalysis, ReadImpactAnalysis;
import 'package:dbmaster/services/ai/agent/agent_loop_runner.dart';
import 'package:dbmaster/services/ai/agent/agent_plan.dart'
    show
        AgentActionPlan,
        AgentPlanExecutionDeps,
        AgentPlanExecutor,
        AgentPlanRollbackDeps,
        AgentPlanStatEvent,
        AgentPlanStatus,
        AgentPlanStepStatus;
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolErrorCodes;
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
import 'package:dbmaster/services/sql_statement_gate_runner.dart'
    show SqlGateConfirmDecision;
import 'package:dbmaster/services/workbench_usage_stats_service.dart'
    show AgentPlanStat, WorkbenchUsageStatsService;

import 'config/clickhouse_test_config.dart';
import 'config/mysql_test_config.dart';
import 'config/sqlserver_test_config.dart';
import 'helpers/ch_gateway_e2e_helper.dart';
import 'helpers/ai_session_isolation_helper.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';
import 'helpers/ss_gateway_e2e_helper.dart';

/// D6：agent L0.5 行阈值默认（与 T17/T18 同口径）。
const int _l05Threshold = 10000;

/// plan_rows 种子行数（> 3000 行限；009 全量行 ref 断言源）。
const int _rowLimitProbeRows = 3500;

/// 用户配置的 chat 目标（NF5.1 断言面沿 T18；与 embedded server 无关）。
const String _userProvider = 'DeepSeek';
const String _userModel = 'deepseek-chat';
const String _userApiKey = 'sk-plan-e2e-user-key';
const String _userBaseUrl = 'https://api.user-deepseek.example/v1';

// ── chat 脚本化 fake（唯一 mock：LLM chat 层）───────────────────────────────

class _ChatScript {
  final List<Future<ChatResponse> Function()> queue =
      <Future<ChatResponse> Function()>[];
  final List<int> toolCounts = <int>[];

  int get callCount => toolCounts.length;

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
    toolCounts.add(tools?.length ?? 0);
    if (queue.isEmpty) {
      throw StateError(
        'AgentPlanRealDbTest: unexpected chat call #${toolCounts.length}',
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

int _callSeq = 0;

AiToolCall _toolCall(String name, [Map<String, dynamic> args = const {}]) =>
    AiToolCall(
      id: 'call-${name.hashCode.abs()}-${_callSeq++}',
      type: 'function',
      functionName: name,
      functionArguments: jsonEncode(args),
    );

ChatResponse _call(AiToolCall call, {String? content}) =>
    ChatResponse(content: content, toolCalls: <AiToolCall>[call]);

// ── 观测 taps（真服务外面包一层计数/捕获，不 mock 数据库服务）──────────────

class _DbTap {
  int executeQueryCalls = 0;
  final List<String> executedSql = <String>[];

  AgentDbAccess wrap(DatabaseService db) => AgentDbAccess(
    getTables: (String? connectionId) =>
        db.getTables(connectionId: connectionId),
    getTableColumns: db.getTableColumns,
    getTableIndexes: db.getTableIndexes,
    getForeignKeys: db.getForeignKeys,
    getCreateTableSql: db.getCreateTableSql,
    getExplainPlan: (String sql, {String? connectionId}) =>
        db.getExplainPlan(sql, connectionId: connectionId),
    executeQuery: (String sql, {String? connectionId, String? database}) {
      executeQueryCalls++;
      executedSql.add(sql);
      return db.executeQuery(
        sql,
        connectionId: connectionId,
        database: database,
      );
    },
  );
}

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
      'planId': planId,
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

/// run 上下文快照解析源（D15）。
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

/// 计划链路测试台：生产装配形态（真 executor + 真 gate 工厂 + 真
/// dbService + AgentPlanExecutor 审计经 tap 转发真实服务），计划批准回调按
/// shell `_onPlanApproval` 语义镜像（L1 会话放行短路 + 决策桥 + approve →
/// execute；deps 绑真 dbService 执行管线 + bypass 双通道 + 脚本化确认回调）。
class _PlanHarness {
  _PlanHarness({
    required this.dbService,
    required this.ctxSource,
    AiSessionManager? sessionManager,
    int maxSteps = 25,
    this.autoApproveL05 = false,
  }) : chat = _ChatScript(),
       dbTap = _DbTap(),
       auditTap = _AuditTap(),
       // Fix-H：默认装配走存储隔离 manager（临时目录 + prefs 前缀），
       // 防测试会话写进真实 Documents/prefs（用户存储污染缺陷）。
       sessionManager =
           sessionManager ?? (createIsolatedAiSessionManager()..createSession()) {
    planExecutor = AgentPlanExecutor(
      audit: auditTap.call,
      recordPlanEvent: (AgentPlanStatEvent event) {
        planEvents.add(event.name);
        WorkbenchUsageStatsService.instance.recordPlanEvent(
          AgentPlanStat.values.byName(event.name),
        );
      },
    );
    executor = AgentToolExecutor(
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
      recordL1Blocked: () {
        l1BlockedCount++;
        WorkbenchUsageStatsService().recordL1Blocked();
      },
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
    );
  }

  final DatabaseService dbService;
  final _CtxSource ctxSource;
  final _ChatScript chat;
  final _DbTap dbTap;
  final _AuditTap auditTap;
  final AiSessionManager sessionManager;
  final bool autoApproveL05;
  late final AgentPlanExecutor planExecutor;
  late final AgentToolExecutor executor;
  late final AgentLoopRunner runner;

  /// 计划事件统计（approved/rejected）。
  final List<String> planEvents = <String>[];

  /// L1 撞门拒绝计数（R14 字段 6，风险 1）。
  int l1BlockedCount = 0;

  /// 计划语句执行探针（deps.execute 计数——镜像生产绑定的真执行管线）。
  int planStatementCalls = 0;

  /// gate #2 确认回调观测（AC10.3/10.4 门次数断言面）。
  final List<String> dmlConfirmedStatements = <String>[];
  final List<String> ddlConfirmedStatements = <String>[];

  /// onPlanApproval 提交次数 / 其中真正阻塞等卡次数（AC9.3 免卡断言面）。
  int planSubmitCount = 0;
  int planCardWaits = 0;

  /// 已见计划对象（按提交序）。
  final List<AgentActionPlan> seenPlans = <AgentActionPlan>[];

  /// 当前计划决策桥（每次 [gates] 取用时刷新；测试侧 complete 落定）。
  Completer<GateCardResult> planDecision = Completer<GateCardResult>();

  /// L0.5 确认桥（autoApproveL05=false 时手动落定）。
  Completer<GateCardResult> cardCompleter = Completer<GateCardResult>();

  GateCallbacks get gates {
    cardCompleter = Completer<GateCardResult>();
    planDecision = Completer<GateCardResult>();
    return GateCallbacks(
      onL05Confirm: (ReadImpactAnalysis impact, String sql) {
        if (autoApproveL05) {
          return Future<GateCardResult>.value(GateCardResult.approved);
        }
        return cardCompleter.future;
      },
      // shell `_onPlanApproval` 同款镜像：提交计数 → L1 会话放行短路（免卡
      // 直接执行）→ 决策桥阻塞等人 → approved/approvedForSession 执行 +
      // rejected 零执行。
      onPlanApproval: (AgentActionPlan plan) async {
        seenPlans.add(plan);
        planSubmitCount++;
        if (runner.ledger.l1Allowed.contains(plan.ctx.connectionId ?? '')) {
          await executePlan(plan);
          return GateCardResult.approvedForSession;
        }
        planCardWaits++;
        final GateCardResult result = await planDecision.future;
        switch (result) {
          case GateCardResult.rejected:
            await planExecutor.reject(plan);
          case GateCardResult.approved:
            await executePlan(plan);
          case GateCardResult.approvedForSession:
            runner.ledger.allowL1(plan.ctx.connectionId ?? '');
            await executePlan(plan);
        }
        return result;
      },
    );
  }

  /// 批准后的执行装配（shell `_executeApprovedPlan`/`_planExecutionDeps`
  /// 镜像：approve（幂等）→ execute；执行通道 = 真 dbService.executeQuery
  /// 管线（readOnly 检查/DML 拦截/DDL 双门/行限全继承）+ bypass 双通道 +
  /// 脚本化确认回调（confirmed 决策））。
  Future<void> executePlan(AgentActionPlan plan) async {
    await planExecutor.approve(plan);
    await planExecutor.execute(plan: plan, deps: _depsFor(plan));
  }

  AgentPlanExecutionDeps _depsFor(AgentActionPlan plan) {
    final String? connectionId = plan.ctx.connectionId;
    final String? databaseName = plan.ctx.databaseName;
    return AgentPlanExecutionDeps(
      execute: (String statement) {
        planStatementCalls++;
        return dbService.executeQuery(
          statement,
          connectionId: connectionId,
          database: databaseName,
        );
      },
      executeBypassDdl: (String statement) => dbService.executeQueryBypassDdl(
        statement,
        connectionId: connectionId,
        database: databaseName,
      ),
      executeBypassDml: (String statement) => dbService.executeQueryBypassDml(
        statement,
        connectionId: connectionId,
        database: databaseName,
      ),
      // gate #2 脚本化确认（DdlConfirmDialog/DmlConfirmDialog 是 UI 确认面；
      // 本套记录语句并给 confirmed 决策）。
      ddlConfirm: (Object e) async {
        ddlConfirmedStatements.add(e.toString());
        return SqlGateConfirmDecision.confirmed;
      },
      dmlConfirm: (Object e) async {
        dmlConfirmedStatements.add(e.toString());
        return SqlGateConfirmDecision.confirmed;
      },
    );
  }

  List<AiMessage> get messages => sessionManager.currentMessages.toList();

  List<Map<String, dynamic>> payloads(String kind) => messages
      .where(
        (AiMessage m) =>
            m.toolResultData?['agent'] is Map<String, dynamic> &&
            (m.toolResultData!['agent'] as Map<String, dynamic>)['kind'] ==
                kind,
      )
      .map((AiMessage m) => m.toolResultData!['agent'] as Map<String, dynamic>)
      .toList();

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

/// uiPort 缺省 fake（不触界面工具的用例；界面类调用若发生以失败 outcome
/// 回喂走自纠路径——与 T18 同款）。
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

const _NoopUiPort _agentUiPort = _NoopUiPort();

/// AC11.4 重放探针的 fail-loud 执行通道：若防重失效而派发语句，立即抛错
/// 使断言失败（零库操作的结构保证）。
Future<List<Map<String, dynamic>>> _failExecute(String statement) =>
    throw StateError(
      'AGENT_PLAN_E2E: replayed plan dispatched "$statement" — '
      'PLAN_ALREADY_EXECUTED guard failed',
    );

/// 结构取数（shell `_fetchStageStructure` 镜像：真 dbService + 锁定上下文；
/// 列信息失败抛错由 port 层转失败 outcome；索引/外键/DDL 为方言能力面，
//  取不到置空不视为失败——本套仅取列信息主体）。
Future<StageStructureData> _fetchStageStructure(
  DatabaseService db,
  String connectionId,
  String databaseName,
  String table,
) async {
  final columns = await db.getTableColumns(
    table,
    connectionId: connectionId,
    databaseName: databaseName,
  );
  return StageStructureData(
    tableName: table,
    columns: columns,
    indexes: const [],
    foreignKeys: const [],
    ddl: null,
  );
}

// ── 种子（网关单语句模型：多值 INSERT 分批，沿 T17/T18 模式）───────────────

Future<void> _seedMainDb(MySQLAdapter seed) async {
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS plan_small ('
    'id INT PRIMARY KEY, '
    'label VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  await seed.executeQuery(
    "INSERT INTO plan_small (id, label) VALUES "
    "(1, 'alpha'), (2, 'beta'), (3, 'gamma') "
    'ON DUPLICATE KEY UPDATE id = id',
  );
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS plan_rows ('
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
    await seed.executeQuery('INSERT INTO plan_rows (label) VALUES $values');
  }
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS plan_ddl_a (id INT PRIMARY KEY) ENGINE=InnoDB',
  );
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS plan_ddl_b (id INT PRIMARY KEY) ENGINE=InnoDB',
  );
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS plan_ddl_c ('
    'id INT PRIMARY KEY, '
    'extra VARCHAR(32)) ENGINE=InnoDB',
  );
}

Future<void> _seedOtherDb(MySQLAdapter seed) async {
  await seed.executeQuery(
    'CREATE TABLE IF NOT EXISTS plan_other ('
    'id INT PRIMARY KEY, '
    'secret VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  await seed.executeQuery(
    "INSERT INTO plan_other (id, secret) VALUES (1, 'cross-db-leak-probe') "
    'ON DUPLICATE KEY UPDATE id = id',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  bool mysqlGatewayReady = false;
  bool ssGatewayReady = false;
  bool chGatewayReady = false;
  setUpAll(() async {
    mysqlGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    ssGatewayReady = await ensureEmbeddedServerForSsE2E();
    chGatewayReady = await ensureEmbeddedServerForChE2E();
  });

  // ==========================================================================
  // 计划链路簇 · MySQL 主战场（真库）
  // ==========================================================================
  group('Agent 计划链路簇 · MySQL 主战场（真库）', () {
    MySQLAdapter? seedAdapter;
    DatabaseService? dbService;
    DbServer? server;
    String? testDbName;
    String? otherDbName;
    bool ready = false;

    setUpAll(() async {
      if (!mysqlGatewayReady || !MySQLTestConfig.available) return;
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      otherDbName = '${MySQLTestConfig.generateTestDatabaseName()}_other';
      final seed = MySQLAdapter();
      try {
        await seed.connect(
          DatabaseConnection(
            id: 'agent_plan_seed_mysql',
            name: 'Agent Plan E2E Seed',
            type: DatabaseType.mysql,
            host: MySQLTestConfig.host,
            port: MySQLTestConfig.port,
            username: MySQLTestConfig.username,
            password: MySQLTestConfig.password,
          ),
        );
        // 幂等清扫历史遗留测试库（沿 T18 惯例：dbmaster_test_* 命名空间归
        // 测试所有）。
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
            print('AGENT_PLAN_E2E_CLEANUP: 已清扫遗留测试库 ${leftovers.length} 个');
          }
        } catch (_) {}

        await seed.executeQuery('CREATE DATABASE IF NOT EXISTS `$testDbName`');
        await seed.useDatabase(testDbName!);
        await _seedMainDb(seed);
        await seed.executeQuery('CREATE DATABASE IF NOT EXISTS `$otherDbName`');
        await seed.useDatabase(otherDbName!);
        await _seedOtherDb(seed);
        await seed.useDatabase(testDbName!);
        seedAdapter = seed;

        final svc = DatabaseService();
        final dbServer = DbServer(
          id: 'agent_plan_e2e_mysql',
          name: 'Agent Plan E2E MySQL',
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
        print('AGENT_PLAN_E2E_SKIP: MySQL 环境不可达：$e');
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
      final other = otherDbName;
      if (seed != null && seed.isConnected) {
        for (final dbName in <String>[?other, ?main]) {
          try {
            await seed.executeQuery('DROP DATABASE IF EXISTS `$dbName`');
          } catch (_) {}
        }
        try {
          await seed.disconnect();
        } catch (_) {}
      }
    });

    _PlanHarness newHarness({int maxSteps = 25, bool readOnly = false}) =>
        _PlanHarness(
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

    /// 直查 plan_small（seed adapter 独立会话，绕开被测链路）。
    Future<Map<int, String>> probeSmall() async {
      await seedAdapter!.useDatabase(testDbName!);
      final result = await seedAdapter!.executeQuery(
        'SELECT id, label FROM plan_small ORDER BY id',
      );
      return <int, String>{
        for (final row in result.rows)
          (row['id'] as num).toInt(): '${row['label']}',
      };
    }

    Future<bool> probeTableExists(String name) async {
      await seedAdapter!.useDatabase(testDbName!);
      final r = await seedAdapter!.executeQuery(
        "SELECT COUNT(*) AS c FROM information_schema.tables "
        "WHERE table_schema = '$testDbName' AND table_name = '$name'",
      );
      return (r.rows.first['c'] as num).toInt() > 0;
    }

    Future<bool> probeColumnExists(String table, String column) async {
      await seedAdapter!.useDatabase(testDbName!);
      final r = await seedAdapter!.executeQuery(
        "SELECT COUNT(*) AS c FROM information_schema.columns "
        "WHERE table_schema = '$testDbName' AND table_name = '$table' "
        "AND column_name = '$column'",
      );
      return (r.rows.first['c'] as num).toInt() > 0;
    }

    Future<String> probeColumnType(String table, String column) async {
      await seedAdapter!.useDatabase(testDbName!);
      final r = await seedAdapter!.executeQuery(
        "SELECT column_type AS t FROM information_schema.columns "
        "WHERE table_schema = '$testDbName' AND table_name = '$table' "
        "AND column_name = '$column'",
      );
      return '${r.rows.first['t']}';
    }

    /// submit_action_plan 参数构造 helper。
    Map<String, dynamic> planArgs(List<Map<String, dynamic>> steps) =>
        <String, dynamic>{'steps': steps, 'rationale': 'e2e plan'};

    /// 每用例重置 plan_small 为规范 3 行（组内共享库、用例间零依赖——
    /// 各用例以固定前置开跑，断言可钉死值）。
    setUp(() async {
      if (!ready || seedAdapter == null) return;
      try {
        await seedAdapter!.useDatabase(testDbName!);
        await seedAdapter!.executeQuery('TRUNCATE TABLE plan_small');
        await seedAdapter!.executeQuery(
          "INSERT INTO plan_small (id, label) VALUES "
          "(1, 'alpha'), (2, 'beta'), (3, 'gamma')",
        );
      } catch (_) {}
    });

    // ----------------------------------------------------------------------
    // 001 AC4.4 越界构造（MySQL 两段式执法）
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-001 AC4.4 越界限定名 → INVALID_ARGUMENTS + 零 executeQuery；同库限定名放行',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = newHarness();
        addTearDown(h.dispose);

        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': 'SELECT id FROM `$otherDbName`.plan_other',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('get_sample_data', <String, dynamic>{
              'table': '$otherDbName.plan_other',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': 'SELECT id FROM `$testDbName`.plan_small ORDER BY id',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('get_sample_data', <String, dynamic>{
              'table': '$testDbName.plan_small',
            }),
          ),
        );
        h.chat.respond(_text('越界被拒，同库限定名可用'));

        await h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '跨库读一下别的库',
          gates: h.gates,
        );

        final steps = h.steps;
        expect(steps, hasLength(4));
        // 步 1/2：越界限定名（SQL 面 + table 参数面）→ INVALID_ARGUMENTS。
        for (var i = 0; i < 2; i++) {
          final error = steps[i]['error'] as Map<String, dynamic>;
          expect(
            error['code'],
            AgentToolErrorCodes.invalidArguments,
            reason: '步 ${i + 1} 越界限定名必须被库级执法拒绝',
          );
          expect(
            error['message'].toString(),
            contains('cross-database'),
            reason: 'AC4.4 指引面：错误文案指引回锁定库',
          );
        }
        // 越界两步零 executeQuery（拦截在 handler 层，未触达库）。
        expect(
          h.dbTap.executedSql.where((String s) => s.contains(otherDbName!)),
          isEmpty,
          reason: '越界语句零执行探针',
        );
        // 审计：拦截也落（blocked / success=false）。
        for (var i = 0; i < 2; i++) {
          expect(h.auditTap.records[i]['success'], isFalse);
          expect(
            h.auditTap.records[i]['gateDecision'],
            AgentGateDecision.blocked,
          );
        }

        // 步 3/4：同库限定名放行（两段式首段 == 锁定库）。
        expect(
          steps[2].containsKey('error'),
          isFalse,
          reason: '同库限定名不误伤（SELECT 面）',
        );
        expect(
          steps[3].containsKey('error'),
          isFalse,
          reason: '同库限定名不误伤（get_sample_data 面）',
        );
        final ref3 = steps[2]['resultRef'] as Map<String, dynamic>;
        expect(ref3['rowCount'], 3);
        final ref4 = steps[3]['resultRef'] as Map<String, dynamic>;
        expect(ref4['rowCount'], 3);

        // 对照：DB 层本身会服务跨库读（root 凭据 + 同实例）——执法发生在
        // executor 层，是唯一拦截点。
        await seedAdapter!.useDatabase(otherDbName!);
        final control = await seedAdapter!.executeQuery(
          'SELECT id FROM `$otherDbName`.plan_other',
        );
        expect(control.rows, isNotEmpty, reason: 'DB 层对照：越界读本可达');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // ----------------------------------------------------------------------
    // 002 计划批准前零变化（AC9.1）+ 批准后执行
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-002 计划批准前零变化（库快照重查 + 全链零 executeQuery）→ 批准后逐句落库（AC9.1）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final before = await probeSmall();
        expect(before.length, 3);

        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall(
              'submit_action_plan',
              planArgs(<Map<String, dynamic>>[
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (81, 'plan_a')",
                  'rollback_sql':
                      'DELETE FROM plan_small WHERE id = 81 LIMIT 1',
                  'note': 'step 1',
                },
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (82, 'plan_b')",
                  'rollback_sql':
                      'DELETE FROM plan_small WHERE id = 82 LIMIT 1',
                  'note': 'step 2',
                },
              ]),
            ),
          ),
        );
        h.chat.respond(_text('计划已执行完成'));

        final GateCallbacks g = h.gates;
        final runFuture = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '插入两行',
          gates: g,
        );
        final reached = await _waitUntil(
          () => h.runner.status == AgentRunStatus.awaitingUser,
        );
        expect(reached, isTrue, reason: 'L1 计划卡阻塞等人（D7）');

        // A2 目录解锁：milestone 2 → 14 工具进 LLM 面。
        expect(
          h.chat.toolCounts.first,
          14,
          reason: 'A2 合龙后工具目录 = 14（6 A1 + 8 A2）',
        );

        // 批准前：计划 pendingApproval + 库零变化 + agent 通道零
        // executeQuery（估算走 EXPLAIN，不占执行通道）+ 计划语句零派发。
        final plan = h.seenPlans.single;
        expect(plan.status, AgentPlanStatus.pendingApproval);
        expect(h.dbTap.executeQueryCalls, 0, reason: '提交零执行（AC9.1）');
        expect(h.planStatementCalls, 0, reason: '批准前无语句进执行管线');
        expect(
          await probeSmall(),
          equals(before),
          reason: 'AC9.1 库快照重查：批准前零变化',
        );

        h.planDecision.complete(GateCardResult.approved);
        await runFuture;

        // 批准后：done + 两句真实落库（重查断言）。
        expect(plan.status, AgentPlanStatus.done);
        final after = await probeSmall();
        expect(after.keys, containsAll(<int>[81, 82]));
        expect(after[81], 'plan_a');
        expect(after[82], 'plan_b');
        expect(after.length, 5);
        // 回喂：done 计划携带步运行时态。
        final steps = h.steps;
        expect(steps, hasLength(1));
        expect(steps.first['tool'], 'submit_action_plan');
        expect(steps.first.containsKey('error'), isFalse);
        expect(steps.first['summary'].toString(), contains('done'));
        // 审计链：submit 工具 1 条（confirmed）+ approve 1 条 + 每步前后对
        //（2 步 × 2）= 6 条，planId 串联。
        final planRecords = h.auditTap.records
            .where((r) => r['planId'] == plan.planId)
            .toList();
        expect(planRecords, hasLength(6));
        expect(
          h.auditTap.records
              .where((r) => r['step'] == 0 && r['planId'] == plan.planId)
              .length,
          2,
          reason: 'AC11.2：步 0 前后审计对（step 用 0 基序号）',
        );
        expect(h.runner.status, AgentRunStatus.completed);
        expect(h.planEvents, contains('approved'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // ----------------------------------------------------------------------
    // 003 拒绝零副作用 + 对话继续（AC9.2）
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-003 计划拒绝 → PLAN_REJECTED + 库零变化 + 审计/统计 + 对话继续（AC9.2）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final before = await probeSmall();

        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall(
              'submit_action_plan',
              planArgs(<Map<String, dynamic>>[
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (83, 'rejected')",
                  'rollback_sql':
                      'DELETE FROM plan_small WHERE id = 83 LIMIT 1',
                },
              ]),
            ),
          ),
        );
        h.chat.respond(_text('用户拒绝了计划，我不再执行'));

        final GateCallbacks g = h.gates;
        final runFuture = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '插一行 83',
          gates: g,
        );
        final reached = await _waitUntil(
          () => h.runner.status == AgentRunStatus.awaitingUser,
        );
        expect(reached, isTrue);
        h.planDecision.complete(GateCardResult.rejected);
        await runFuture;

        // 回喂：PLAN_REJECTED + 语义明确（零执行 + 对话继续）。
        final steps = h.steps;
        expect(steps, hasLength(1));
        final error = steps.first['error'] as Map<String, dynamic>;
        expect(error['code'], AgentToolErrorCodes.planRejected);
        expect(error['message'].toString(), contains('nothing was executed'));
        // 库零变化（重查断言）。
        expect(await probeSmall(), equals(before), reason: 'AC9.2 零副作用');
        // 全链零执行。
        expect(h.dbTap.executeQueryCalls, 0);
        expect(h.planStatementCalls, 0);
        // 审计：submit 工具 rejected_by_user + planExecutor.reject 各一条。
        final planRecords = h.auditTap.records
            .where((r) => r['planId'] == h.seenPlans.single.planId)
            .toList();
        expect(planRecords, hasLength(2));
        expect(
          planRecords
              .where(
                (r) => r['gateDecision'] == AgentGateDecision.rejectedByUser,
              )
              .length,
          2,
        );
        // 统计：rejected 事件 + L1 撞门拒绝计数（风险 1）。
        expect(h.planEvents, contains('rejected'));
        expect(h.l1BlockedCount, 1);
        // run 收敛 + 回喂自纠（拒绝 ≠ 停止）。
        expect(h.runner.status, AgentRunStatus.completed);
        // 对话继续：新指令可用。
        h.chat.respond(_text('好的，换个思路'));
        await h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '那算了',
          gates: h.gates,
        );
        expect(h.runner.status, AgentRunStatus.completed);
        expect(h.payloads('agent_run_end'), hasLength(2));
        expect(await probeSmall(), equals(before), reason: '全程零副作用');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // ----------------------------------------------------------------------
    // 004 计划内 DDL 逐次双门（AC10.3/10.4）
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-004 计划内 DDL 逐次双门：dmlConfirm×2 + ddlConfirm×1 逐句过门（AC10.3/10.4）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        // 前置：三张 DDL 靶表在位（plan_ddl_c 含 extra 列）。
        expect(await probeTableExists('plan_ddl_a'), isTrue);
        expect(await probeTableExists('plan_ddl_b'), isTrue);
        expect(await probeColumnExists('plan_ddl_c', 'extra'), isTrue);

        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall(
              'submit_action_plan',
              planArgs(<Map<String, dynamic>>[
                <String, dynamic>{
                  'sql': 'DROP TABLE plan_ddl_a',
                  'irreversible': true,
                  'note': 'dml critical 门（dropTable 触发器）',
                },
                <String, dynamic>{
                  'sql': 'DROP TABLE plan_ddl_b',
                  'irreversible': true,
                  'note': 'L2 无会话放行：第二句仍逐次过门',
                },
                <String, dynamic>{
                  // ddl 分析门形态：MODIFY COLUMN → ALTER_COLUMN →
                  // DdlAlgorithm.copy（全表锁）→ beforeExecute 必要求确认
                  //（copy 规则与行数无关，确定性触发 ddlConfirm）。
                  // 注：ALTER ... DROP COLUMN 形态在计划通道当前会先撞
                  // DML 高危警告 rethrow（经典编辑器为横幅+继续、计划通道
                  // 无对应路径）——T29 实证遗留，见任务汇报。
                  'sql':
                      'ALTER TABLE plan_ddl_c MODIFY COLUMN extra VARCHAR(128)',
                  'irreversible': true,
                  'note': 'ddl 分析门（ALTER_COLUMN → COPY 全表锁）',
                },
              ]),
            ),
          ),
        );
        h.chat.respond(_text('三句 DDL 均已确认执行'));

        final GateCallbacks g = h.gates;
        final runFuture = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '清理三张表',
          gates: g,
        );
        final reached = await _waitUntil(
          () => h.runner.status == AgentRunStatus.awaitingUser,
        );
        expect(reached, isTrue);
        h.planDecision.complete(GateCardResult.approved);
        await runFuture;

        final plan = h.seenPlans.single;
        expect(plan.status, AgentPlanStatus.done, reason: '三句全部执行成功');

        // 门次数断言（AC10.4 双门第二道逐句）：计划批准一次（gate #1）+
        // 管线门（gate #2）逐语句：DROP×2 → dmlConfirm×2；ALTER MODIFY
        // COLUMN → ddlConfirm×1。L2 无会话放行（AC10.3）——第一句确认后
        // 第二句仍过门。
        expect(
          h.dmlConfirmedStatements,
          hasLength(2),
          reason: 'AC10.3：DDL 危险形态逐次过门，无会话放行短路',
        );
        expect(h.ddlConfirmedStatements, hasLength(1));
        // 功能真生效（重查断言）。
        expect(
          await probeTableExists('plan_ddl_a'),
          isFalse,
          reason: 'plan_ddl_a 真实删除',
        );
        expect(
          await probeTableExists('plan_ddl_b'),
          isFalse,
          reason: 'plan_ddl_b 真实删除',
        );
        expect(await probeColumnExists('plan_ddl_c', 'extra'), isTrue);
        expect(
          await probeColumnType('plan_ddl_c', 'extra'),
          'varchar(128)',
          reason: 'plan_ddl_c.extra 列真实加宽（MODIFY 过 ddl 门后执行）',
        );
        expect(await probeTableExists('plan_ddl_c'), isTrue);
        // 审计链：3 步 × 前后对 + approve + submit 工具 = 8 条 planId 串联。
        final planRecords = h.auditTap.records
            .where((r) => r['planId'] == plan.planId)
            .toList();
        expect(planRecords, hasLength(8));
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // ----------------------------------------------------------------------
    // 005 中途失败边界 + 回退过门 + rolledBack（AC11.1-11.3）
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-005 第 2 句失败 → 三段可见 + 回退计划过门执行 + rolledBack（AC11.1-11.3）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final before = await probeSmall();
        expect(before.length, 3);

        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall(
              'submit_action_plan',
              planArgs(<Map<String, dynamic>>[
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (91, 'fail_probe')",
                  'rollback_sql':
                      'DELETE FROM plan_small WHERE id = 91 LIMIT 1',
                  'note': 'step 1: 成功步（有回滚）',
                },
                <String, dynamic>{
                  'sql': 'INSERT INTO plan_missing (id) VALUES (1)',
                  'irreversible': true,
                  'note': 'step 2: 构造失败（表不存在）',
                },
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (93, 'skipped')",
                  'irreversible': true,
                  'note': 'step 3: 应被跳过',
                },
              ]),
            ),
          ),
        );
        h.chat.respond(_text('第 2 步失败，已停止并生成回退'));

        final GateCallbacks g = h.gates;
        final runFuture = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '三步计划，第二步会失败',
          gates: g,
        );
        final reached = await _waitUntil(
          () => h.runner.status == AgentRunStatus.awaitingUser,
        );
        expect(reached, isTrue);
        h.planDecision.complete(GateCardResult.approved);
        await runFuture;

        final plan = h.seenPlans.single;

        // AC11.1 失败边界三段：step1 done / step2 failed(+error) / step3
        // skipped。
        expect(plan.status, AgentPlanStatus.partialFailed);
        expect(
          plan.steps.map((s) => s.runtime.status).toList(),
          <AgentPlanStepStatus>[
            AgentPlanStepStatus.done,
            AgentPlanStepStatus.failed,
            AgentPlanStepStatus.skipped,
          ],
          reason: 'AC11.1 三段可见',
        );
        expect(plan.steps[1].runtime.error, isNotNull);
        expect(plan.steps[1].runtime.error, contains('plan_missing'));
        // 回喂：partialFailed + 进度（1/3）+ 失败步明细。
        final steps = h.steps;
        final error = steps.first['error'] as Map<String, dynamic>;
        expect(error['code'], AgentToolErrorCodes.executionFailed);
        expect(error['message'].toString(), contains('1/3'));
        // 库状态：step1 已落、step3 未执行。
        final mid = await probeSmall();
        expect(mid[91], 'fail_probe', reason: 'step 1 已执行');
        expect(mid.containsKey(93), isFalse, reason: 'step 3 从未执行');

        // AC11.3 回退组装：永不自动执行——新计划 pendingApproval 走同一门。
        final rollbackPlan = await h.planExecutor.buildRollbackPlan(
          plan: plan,
          deps: const AgentPlanRollbackDeps(),
        );
        expect(rollbackPlan, isNotNull);
        expect(
          rollbackPlan!.status,
          AgentPlanStatus.pendingApproval,
          reason: 'AC11.3 回退过门：组装产物待批准',
        );
        expect(rollbackPlan.rollbackOfPlanId, plan.planId);
        expect(rollbackPlan.steps, hasLength(1));
        expect(
          rollbackPlan.steps.first.sql,
          contains('DELETE FROM plan_small'),
        );
        // 原计划 → rollbackOffered；回退未执行（id 91 仍在）。
        expect(plan.status, AgentPlanStatus.rollbackOffered);
        expect(
          (await probeSmall()).containsKey(91),
          isTrue,
          reason: '回退批准前零执行',
        );

        // 回退执行（同一批准门语义：approve → execute）。
        await h.executePlan(rollbackPlan);
        expect(rollbackPlan.status, AgentPlanStatus.done);
        expect(
          (await probeSmall()).containsKey(91),
          isFalse,
          reason: '回退真实生效（step1 逆语句执行）',
        );

        // §7 流转收口：rolledBack + consumed。
        expect(h.planExecutor.markRolledBack(plan), isTrue);
        expect(plan.status, AgentPlanStatus.rolledBack);
        expect(plan.isConsumed, isTrue);
        // 回退语句同样落审计（独立 planId 串联）：组装血缘 1 条（Fix-F ③
        // 计划级事件，step=-1 + errorMessage 携带 rb_of_<原 planId> 血缘
        // 标记，见 agent_plan.dart buildRollbackPlan「回退血缘审计」）+
        // approve 1 条 + 前后对 2 条 = 4 条。
        final rollbackRecords = h.auditTap.records
            .where((r) => r['planId'] == rollbackPlan.planId)
            .toList();
        expect(rollbackRecords, hasLength(4));
        expect(
          rollbackRecords
              .where(
                (r) => (r['errorMessage'] ?? '').toString().contains('rb_of_'),
              )
              .single['errorMessage']
              .toString(),
          contains('rb_of_${plan.planId}'),
          reason: 'Fix-F ③ 血缘记录：回退计划审计链可溯源原计划',
        );
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // ----------------------------------------------------------------------
    // 006 planId 重放 → PLAN_ALREADY_EXECUTED（AC11.4）
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-006 终态计划重放 → PLAN_ALREADY_EXECUTED + consumed + 零库操作（AC11.4）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = newHarness();
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall(
              'submit_action_plan',
              planArgs(<Map<String, dynamic>>[
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (76, 'replay')",
                  'rollback_sql':
                      'DELETE FROM plan_small WHERE id = 76 LIMIT 1',
                },
              ]),
            ),
          ),
        );
        h.chat.respond(_text('执行完成'));

        final GateCallbacks g = h.gates;
        final runFuture = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '插一行 76',
          gates: g,
        );
        expect(
          await _waitUntil(
            () => h.runner.status == AgentRunStatus.awaitingUser,
          ),
          isTrue,
        );
        h.planDecision.complete(GateCardResult.approved);
        await runFuture;

        final plan = h.seenPlans.single;
        expect(plan.status, AgentPlanStatus.done);
        expect((await probeSmall()).containsKey(76), isTrue);

        // 重放（卡上再点 / 重复触发形态）：结构化拒绝 + 零库操作。
        final auditsBefore = h.auditTap.records.length;
        final statementsBefore = h.planStatementCalls;
        final result = await h.planExecutor.execute(
          plan: plan,
          deps: AgentPlanExecutionDeps(execute: _failExecute),
        );
        expect(result.ok, isFalse);
        expect(result.errorCode, AgentToolErrorCodes.planAlreadyExecuted);
        expect(result.errorMessage, contains(plan.planId));
        expect(plan.isConsumed, isTrue, reason: '终态重放标记（AC11.4）');
        expect(
          h.planStatementCalls,
          statementsBefore,
          reason: '重放零语句派发（deps.execute 若被调即 fail-loud 抛错）',
        );
        expect(h.auditTap.records.length, auditsBefore, reason: '重放零新审计');
        expect((await probeSmall()).containsKey(76), isTrue, reason: '库不因重放变化');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // ----------------------------------------------------------------------
    // 007 readOnly 连接 submit → READONLY_CONNECTION（NF2.3 计划形态）
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-007 readOnly 连接 submit_action_plan → READONLY_CONNECTION + 全链零 executeQuery（NF2.3）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final before = await probeSmall();
        final h = newHarness(readOnly: true);
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall(
              'submit_action_plan',
              planArgs(<Map<String, dynamic>>[
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (77, 'readonly')",
                  'rollback_sql':
                      'DELETE FROM plan_small WHERE id = 77 LIMIT 1',
                },
              ]),
            ),
          ),
        );
        h.chat.respond(_text('只读连接，计划提交被拒'));

        await h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '在只读连接上插一行',
          gates: h.gates,
        );

        // 门判定序 ③：readOnly × plan 类 → READONLY_CONNECTION（先于任何
        // 计划构造/执行）。
        final steps = h.steps;
        expect(steps, hasLength(1));
        final error = steps.first['error'] as Map<String, dynamic>;
        expect(error['code'], AgentToolErrorCodes.readonlyConnection);
        // NF2.3 断言面：整个 run 全链零 executeQuery（agent 通道 + 计划通道）。
        expect(h.dbTap.executeQueryCalls, 0);
        expect(h.planStatementCalls, 0);
        expect(h.dbTap.executedSql, isEmpty);
        // 快照 readOnly=true 入锚点。
        final anchors = h.payloads('agent_run');
        expect(anchors.first['contextSnapshot']['readOnly'], isTrue);
        // 审计 blocked + 计划未构造（门先拒）。
        expect(
          h.auditTap.records.first['gateDecision'],
          AgentGateDecision.blocked,
        );
        expect(h.seenPlans, isEmpty);
        // 对照：同一连接读通道可用（零执行非连接失效）+ 库未变。
        final control = await dbService!.executeQuery(
          'SELECT COUNT(*) AS c FROM plan_small',
        );
        expect((control.first['c'] as num).toInt(), 3);
        expect(await probeSmall(), equals(before));
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // ----------------------------------------------------------------------
    // 008 L1 会话放行短路（AC9.3 链路面）
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-008 L1 会话放行：首次 approvedForSession 登记 → 第二次 submit 免卡仍逐语句审计（AC9.3）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = newHarness();
        addTearDown(h.dispose);

        // —— 第 1 次 submit：卡上勾选「本会话内允许」→ approvedForSession ——
        //（Fix-E 已合入 agent_plan_card sessionCheckboxKey；本用例驱动链路面
        //——决策回调内 ledger.allowL1 登记（shell `_onPlanApproval`
        // approvedForSession 分支同款镜像），UI 勾选面归 AgentPlanCard 自身
        // widget 测试。）
        h.chat.respond(
          _call(
            _toolCall(
              'submit_action_plan',
              planArgs(<Map<String, dynamic>>[
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (61, 'session_l1')",
                  'rollback_sql':
                      'DELETE FROM plan_small WHERE id = 61 LIMIT 1',
                },
              ]),
            ),
          ),
        );
        h.chat.respond(_text('第一次已按会话放行执行'));

        final GateCallbacks g1 = h.gates;
        final run1 = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '插 61，本会话都允许',
          gates: g1,
        );
        expect(
          await _waitUntil(
            () => h.runner.status == AgentRunStatus.awaitingUser,
          ),
          isTrue,
        );
        h.planDecision.complete(GateCardResult.approvedForSession);
        await run1;

        final planA = h.seenPlans.single;
        expect(planA.status, AgentPlanStatus.done);
        expect(h.planSubmitCount, 1);
        expect(h.planCardWaits, 1);
        expect(
          h.runner.ledger.l1Allowed.contains(server!.id),
          isTrue,
          reason: '会话放行登记（AC9.3）',
        );
        expect((await probeSmall()).containsKey(61), isTrue);

        // —— 第 2 次 submit（新 run，账本跨 run 保留）：免卡 ——
        final auditsBefore = h.auditTap.records.length;
        h.chat.respond(
          _call(
            _toolCall(
              'submit_action_plan',
              planArgs(<Map<String, dynamic>>[
                <String, dynamic>{
                  'sql':
                      "INSERT INTO plan_small (id, label) VALUES (62, 'session_l1_2')",
                  'irreversible': true,
                },
              ]),
            ),
          ),
        );
        h.chat.respond(_text('第二次免卡直接执行'));

        final GateCallbacks g2 = h.gates;
        final run2 = h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '再插 62',
          gates: g2,
        );
        await run2;

        // 免卡：第二次不再阻塞等卡，直接批准执行。
        expect(h.planSubmitCount, 2);
        expect(h.planCardWaits, 1, reason: 'AC9.3 免卡：第二次不等卡');
        final planB = h.seenPlans[1];
        expect(planB.status, AgentPlanStatus.done);
        expect((await probeSmall()).containsKey(62), isTrue);
        // 逐语句审计对账（AC9.3 免卡 ≠ 免审计）：
        // submit 工具 1 条（allowed_session）+ approve 1 + 步前后对 2 = 4。
        final planBRecords = h.auditTap.records
            .where((r) => r['planId'] == planB.planId)
            .toList();
        expect(planBRecords, hasLength(4));
        expect(
          planBRecords.where((r) => r['step'] == 1).single['gateDecision'],
          AgentGateDecision.allowedSession,
          reason: '免卡执行的 submit 工具审计记 allowed_session',
        );
        expect(
          planBRecords.where((r) => r['step'] == 0).length,
          2,
          reason: '语句步前后审计对不受免卡影响',
        );
        expect(h.auditTap.records.length, auditsBefore + 4);
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    // ----------------------------------------------------------------------
    // 009 界面工具链（舞台/产物条状态，组件级；AC5.1-5.4）
    // ----------------------------------------------------------------------
    test(
      'AI-PLAN-E2E-009 界面工具链：网格/钉住/编辑器/图表/结构 → 舞台与产物条状态 + 编辑器不自动执行 + 大结果 ref 全量行（AC5.1-5.4）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        // 真实组件装配：真 AgentUiPortImpl + 真 WorkbenchStageController +
        // 结构取数绑真 dbService（shell `_fetchStageStructure` 镜像——连接与
        // 库取锁定上下文）；建议消息落账绑 harness 会话。
        final stage = WorkbenchStageController();
        addTearDown(stage.dispose);
        final h = newHarness();
        addTearDown(h.dispose);
        final port = AgentUiPortImpl(
          stageController: stage,
          structureFetcher: (String table) =>
              _fetchStageStructure(dbService!, server!.id, testDbName!, table),
          landSuggestionMessage: h.sessionManager.addMessage,
        );

        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': 'SELECT id FROM plan_rows',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('pin_artifact', <String, dynamic>{
              'result_ref': 'res_1',
              'label': 'big-rows',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('open_result_grid', <String, dynamic>{
              'result_ref': 'res_1',
              'title': 'plan_rows 全量',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': 'SELECT id FROM plan_small WHERE id <= 2',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('render_chart', <String, dynamic>{
              'result_ref': 'res_4',
              'chart_kind': 'bar',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': 'SELECT label FROM plan_small WHERE id <= 2',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('render_chart', <String, dynamic>{'result_ref': 'res_6'}),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('open_sql_editor', <String, dynamic>{
              'sql': 'SELECT 42 AS answer',
            }),
          ),
        );
        h.chat.respond(
          _call(
            _toolCall('show_table_structure', <String, dynamic>{
              'table': 'plan_small',
            }),
          ),
        );
        h.chat.respond(_text('舞台呈现完成'));

        final execBefore = h.dbTap.executeQueryCalls;
        await h.runner.start(uiPort: port, userMessage: '呈现结果', gates: h.gates);
        final execTotal = h.dbTap.executeQueryCalls - execBefore;

        expect(h.runner.status, AgentRunStatus.completed);
        final steps = h.steps;
        expect(
          steps.map((Map<String, dynamic> s) => s['tool']).toList(),
          <String>[
            'execute_readonly_sql',
            'pin_artifact',
            'open_result_grid',
            'execute_readonly_sql',
            'render_chart',
            'execute_readonly_sql',
            'render_chart',
            'open_sql_editor',
            'show_table_structure',
          ],
        );

        // 大结果 ref 全量行与行限一致（AC5.1）：3,500 行种子 × 3000 行限。
        final ref1 = h.executor.resultRefOf('res_1');
        expect(ref1, isNotNull);
        expect(ref1!.rowCount, 3000);
        expect(ref1.rows.length, 3000, reason: 'ref 全量行 == 行限内全量');

        // 终态舞台：pin 先行（舞台收起）仅钉产物条 → open_result_grid 复用
        // 同 refId tab 并开舞台；chart（数值列）成 tab；非适配图表不建 tab；
        // editor + structure 各一 tab → 共 4。
        expect(stage.tabs, hasLength(4));
        expect(stage.pinnedTabs, hasLength(1), reason: 'AC5.4 产物条钉住');
        expect(stage.stageVisible, isTrue, reason: 'open_result_grid 开舞台');
        final gridTab = stage.tabs.firstWhere(
          (WorkbenchStageTab t) => t.kind == WorkbenchStageTabKind.grid,
        );
        expect(gridTab.pinned, isTrue);
        expect(gridTab.resultRef, isNotNull);
        expect(
          gridTab.resultRef!.rows.length,
          3000,
          reason: '舞台网格消费全量行（行限内不复制截断）',
        );
        expect(gridTab.title, 'plan_rows 全量');
        expect(
          stage.tabs
              .where(
                (WorkbenchStageTab t) => t.kind == WorkbenchStageTabKind.chart,
              )
              .length,
          1,
          reason: '数值列结果成 chart tab（AC5.1）',
        );

        // 非数值结果图表失败回喂自纠（AC5.3）——不建 tab。
        final chartErrorStep = steps[6];
        expect(chartErrorStep['tool'], 'render_chart');
        final chartError = chartErrorStep['error'] as Map<String, dynamic>;
        expect(chartError['code'], AgentToolErrorCodes.executionFailed);
        expect(
          chartError['message'].toString(),
          contains('chart data mismatch'),
          reason: 'AC15.1 自纠通路：失败 detail 给可自纠方向',
        );

        // 编辑器槽：载入不自动执行（AC5.2）——9 步仅 3 次数据查询
        //（res_1/res_4/res_6），界面五工具 + 失败图表零执行；结构取数走
        // getTableColumns（describe 通道，不占 executeQuery）。
        expect(execTotal, 3, reason: '编辑器/网格/图表/结构均不自动执行');
        final editorTab = stage.tabs.firstWhere(
          (WorkbenchStageTab t) => t.kind == WorkbenchStageTabKind.editor,
        );
        expect(editorTab.initialSql, 'SELECT 42 AS answer');
        expect(editorTab.dirty, isFalse);

        // 结构卡：真 describe 取数（真 dbService）。
        final structureTab = stage.tabs.firstWhere(
          (WorkbenchStageTab t) => t.kind == WorkbenchStageTabKind.structure,
        );
        expect(structureTab.structure, isNotNull);
        expect(structureTab.structure!.tableName, 'plan_small');
        expect(
          structureTab.structure!.columns.map((c) => c.name).toSet(),
          containsAll(<String>{'id', 'label'}),
        );

        // 界面五工具 + 失败 render_chart 各落一条审计（allowed）。
        expect(
          h.auditTap.records
              .where(
                (r) =>
                    (r['tool'] as String) != 'execute_readonly_sql' &&
                    r['step'] != -1,
              )
              .length,
          6,
          reason: '界面五工具 + 失败图表共 6 条步审计',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    // ----------------------------------------------------------------------
    // 010 建议卡点击 → 新经典 tab 落位 + 审计（AC6.2/6.4，widget e2e）
    // ----------------------------------------------------------------------
    testWidgets(
      'AI-PLAN-E2E-010 open_in_classic 建议卡：零自动副作用 → 点击新 tab 落位 + 审计（AC6.2/6.4）',
      (tester) async {
        if (!ready) {
          // ignore: avoid_print
          print('AGENT_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        const suggestedSql = 'SELECT 42 AS answer';

        // ── 阶段 A（真实 IO 在 runAsync 区）：脚本化模型经回路产出建议卡
        //    消息（真 AgentUiPortImpl 落账）──
        AiMessage? suggestionMessage;
        AppProvider? appProviderRef;
        int tabsBefore = 0;
        await tester.runAsync(() async {
          final stage = WorkbenchStageController();
          final h = newHarness();
          h.chat.respond(
            _call(
              _toolCall('open_in_classic', <String, dynamic>{
                'sql': suggestedSql,
              }),
            ),
          );
          h.chat.respond(_text('已给出在经典中打开的建议'));
          final port = AgentUiPortImpl(
            stageController: stage,
            structureFetcher: (String table) => _fetchStageStructure(
              dbService!,
              server!.id,
              testDbName!,
              table,
            ),
            landSuggestionMessage: (AiMessage message) {
              suggestionMessage = message;
              h.sessionManager.addMessage(message);
            },
          );
          await h.runner.start(
            uiPort: port,
            userMessage: '给我一条在经典里跑的语句',
            gates: h.gates,
          );
          expect(h.runner.status, AgentRunStatus.completed);
          // R6 零自动副作用：建议级零执行（agent 通道零 executeQuery）。
          expect(h.dbTap.executeQueryCalls, 0);
          stage.dispose();
          h.dispose();

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
          tabsBefore = provider.tabs.length;
        });
        expect(
          suggestionMessage,
          isNotNull,
          reason: '建议卡消息已落账（真 port impl 产物）',
        );
        final Map<String, dynamic> suggestPayload =
            suggestionMessage!.toolResultData!['agent'] as Map<String, dynamic>;
        expect(suggestPayload['kind'], 'agent_suggest');
        expect(suggestPayload['action'], 'open_in_classic');
        expect(suggestPayload['applied'], isFalse);
        expect(
          (suggestPayload['payload'] as Map<String, dynamic>)['sql'],
          suggestedSql,
        );
        final AppProvider appProvider = appProviderRef!;

        try {
          // ── 阶段 C：泵工作台壳，建议卡渲染 + 点击应用 ──
          tester.view.physicalSize = const Size(1280, 1000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          appProvider.setAiPanelOpen(true);
          appProvider.setAiPanelFullscreen(true);
          await tester.pumpWidget(
            ChangeNotifierProvider<AppProvider>.value(
              value: appProvider,
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                locale: const Locale('en'),
                home: const Scaffold(body: AiWorkbenchShell()),
              ),
            ),
          );
          await tester.pumpAndSettle(const Duration(seconds: 2));

          appProvider.addAiMessage(suggestionMessage!);
          await tester.pumpAndSettle(const Duration(seconds: 1));

          final applyButton = find.byKey(AgentSuggestionCard.applyButtonKey);
          expect(
            applyButton,
            findsOneWidget,
            reason: '建议卡渲染（agent_suggest 顶级卡，T26 分组排除）',
          );
          await tester.ensureVisible(applyButton);
          await tester.tap(applyButton);
          await tester.pumpAndSettle(const Duration(seconds: 2));

          // AC6.2：新 tab 落位（不覆盖既有 tab）。
          expect(appProvider.tabs.length, tabsBefore + 1);
          expect(appProvider.tabs.last.sql, suggestedSql);

          // AC6.4：审计落档（na / success true / tool = 动作名；区别于
          // suggest 工具步审计的 allowed 决策）。
          bool audited = false;
          await tester.runAsync(() async {
            final deadline = DateTime.now().add(const Duration(seconds: 15));
            while (DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 200));
              final entries = AuditLogService()
                  .getRecentEntries(limit: 200)
                  .where(
                    (e) =>
                        e.agentTool == 'open_in_classic' &&
                        e.gateDecision == AgentGateDecision.na &&
                        e.success,
                  )
                  .toList();
              if (entries.isNotEmpty) {
                audited = true;
                break;
              }
            }
          });
          expect(audited, isTrue, reason: 'AC6.4 建议卡点击审计');
        } finally {
          await tester.runAsync(() async {
            try {
              await appProvider.disconnectConnection(connectionId: server!.id);
            } catch (_) {}
            try {
              appProvider.dispose();
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
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  });

  // ==========================================================================
  // AC4.4 方言扩面 · SS 三段式（Fix-G M5：执法面已含 SS 三段式首段=库——见
  // agent_tool_executor.dart `_firstSegmentIsDatabaseQualifier`；探针断言
  // 已翻转为执法守卫拒绝，穿透分支保留为违规告警。）
  // ==========================================================================
  group('Agent 计划链路簇 · AC4.4 SS 三段式方言执法（真库探针）', () {
    SqlServerAdapter? seedAdapter;
    DatabaseService? dbService;
    DbServer? server;
    String? testDbName;
    String? otherDbName;
    bool ready = false;

    setUpAll(() async {
      if (!ssGatewayReady || !SQLServerTestConfig.available) return;
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      otherDbName = '${SQLServerTestConfig.generateTestDatabaseName()}_o';
      final seed = SqlServerAdapter();
      try {
        await seed.connect(
          DatabaseConnection(
            id: 'agent_plan_seed_ss',
            name: 'Agent Plan E2E Seed SS',
            type: DatabaseType.sqlserver,
            host: SQLServerTestConfig.host,
            port: SQLServerTestConfig.port,
            username: SQLServerTestConfig.username,
            password: SQLServerTestConfig.password,
            database: SQLServerTestConfig.database,
          ),
        );
        if (!await seed.createDatabase(testDbName!)) {
          throw Exception('CREATE DATABASE $testDbName 失败');
        }
        await seed.useDatabase(testDbName!);
        await seed.executeQuery(
          'CREATE TABLE plan_ss_a (id INT PRIMARY KEY, val INT NOT NULL)',
        );
        await seed.executeQuery(
          'INSERT INTO plan_ss_a (id, val) VALUES (1, 10)',
        );
        if (!await seed.createDatabase(otherDbName!)) {
          throw Exception('CREATE DATABASE $otherDbName 失败');
        }
        await seed.useDatabase(otherDbName!);
        await seed.executeQuery(
          'CREATE TABLE plan_ss_b (id INT PRIMARY KEY, marker VARCHAR(64) NOT NULL)',
        );
        await seed.executeQuery(
          "INSERT INTO plan_ss_b (id, marker) VALUES (1, 'ss-cross-db-leak-probe')",
        );
        await seed.useDatabase(testDbName!);
        seedAdapter = seed;

        final svc = DatabaseService();
        final dbServer = DbServer(
          id: 'agent_plan_e2e_ss',
          name: 'Agent Plan E2E SS',
          type: DatabaseType.sqlserver,
          host: SQLServerTestConfig.host,
          port: SQLServerTestConfig.port,
          username: SQLServerTestConfig.username,
          password: SQLServerTestConfig.password,
          database: testDbName,
        );
        ready = await svc.connect(dbServer);
        if (!ready) await svc.disconnect();
        dbService = svc;
        server = dbServer;
      } catch (e) {
        // ignore: avoid_print
        print('SS_PLAN_E2E_SKIP: SQL Server 环境不可达：$e');
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
      if (seed != null && seed.isConnected) {
        for (final dbName in <String>[?otherDbName, ?testDbName]) {
          try {
            // 先切回 master 再删（SS 3702 in-use 规避，沿 T17 惯例）。
            await seed.useDatabase(SQLServerTestConfig.database);
            await seed.dropDatabase(dbName);
          } catch (_) {}
        }
        try {
          await seed.disconnect();
        } catch (_) {}
      }
    });

    test(
      'AI-PLAN-E2E-SS3P SS 三段式 other.dbo.t 越界读 → 执法守卫拒绝（AC4.4 M5 扩面后断言翻转）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('SS_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = _PlanHarness(
          dbService: dbService!,
          ctxSource: _CtxSource(
            connectionId: server!.id,
            connectionName: server!.name,
            databaseName: testDbName!,
            dbType: DatabaseType.sqlserver,
          ),
          // SS 网关 EXPLAIN 不支持（AC8.6 fail-closed confirm）——探针自动
          // 批准 L0.5，目标面是 AC4.4 执法层而非 L0.5。
          autoApproveL05: true,
        );
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': 'SELECT id FROM $otherDbName.dbo.plan_ss_b',
            }),
          ),
        );
        h.chat.respond(_text('探针完成'));

        await h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '跨库探针',
          gates: h.gates,
        );

        final steps = h.steps;
        expect(steps, hasLength(1));
        final step = steps.first;
        // Fix-G 扩面（M5）：SS 三段式 `db.schema.table` 首段=库入执法面
        //（agent_tool_executor `_firstSegmentIsDatabaseQualifier`）——越界
        // 三段式读必须被 executor 执法守卫拒绝（INVALID_ARGUMENTS +
        // cross-database），不再穿透到 DB 层。
        final Map<String, dynamic>? error =
            step['error'] as Map<String, dynamic>?;
        final bool rejectedByEnforcement =
            error != null &&
            error['code'] == AgentToolErrorCodes.invalidArguments &&
            error['message'].toString().contains('cross-database');
        expect(
          rejectedByEnforcement,
          isTrue,
          reason: 'Fix-G 执法守卫：SS 三段式首段=库，越界读必须被执法拒绝',
        );

        if (error == null) {
          final ref = step['resultRef'] as Map<String, dynamic>;
          // ignore: avoid_print
          print(
            'AGENT_PLAN_E2E_SS3P_VIOLATION: SS 三段式越界读 **穿透执行**，'
            '返回 ${ref['rowCount']} 行——Fix-G 执法面已覆盖 SS 三段式，穿透'
            '即执法失效（agent 通道可读锁定库之外的库），需立即复查 '
            '_crossDatabaseSqlProblem 的 SS 段数判定',
          );
        } else {
          // ignore: avoid_print
          print(
            'AGENT_PLAN_E2E_SS3P_GUARD: SS 三段式越界读被执法守卫拒绝'
            '（${error['code']}）——AC4.4 方言扩面生效（M5 实证收口）',
          );
        }
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  // ==========================================================================
  // AC4.4 方言扩面 · CH 两段式（Fix-G M5：执法面已含 CH 两段式首段=库；探针
  // 断言已翻转为执法守卫拒绝。CH 账号无 DROP 授权——清理尽力而为并打印
  // leftover 标记；探针读系统库 system.one，零额外库脚印。）
  // ==========================================================================
  group('Agent 计划链路簇 · AC4.4 CH 两段式方言执法（真库探针）', () {
    ClickhouseAdapter? seedAdapter;
    DatabaseService? dbService;
    DbServer? server;
    String? testDbName;
    bool ready = false;

    setUpAll(() async {
      if (!chGatewayReady || !ClickhouseTestConfig.available) return;
      testDbName = 'dbmaster_test_${DateTime.now().millisecondsSinceEpoch}_ch';
      final seed = ClickhouseAdapter();
      try {
        await seed.connect(
          DatabaseConnection(
            id: 'agent_plan_seed_ch',
            name: 'Agent Plan E2E Seed CH',
            type: DatabaseType.clickhouse,
            host: ClickhouseTestConfig.host,
            port: ClickhouseTestConfig.port,
            username: ClickhouseTestConfig.username,
            password: ClickhouseTestConfig.password,
            database: ClickhouseTestConfig.database,
          ),
        );
        await seed.executeQuery('CREATE DATABASE IF NOT EXISTS `$testDbName`');
        await seed.executeQuery(
          'CREATE TABLE `$testDbName`.plan_ch_a (id UInt32) '
          'ENGINE = MergeTree ORDER BY id',
        );
        await seed.executeQuery(
          "INSERT INTO `$testDbName`.plan_ch_a VALUES (1)",
        );
        seedAdapter = seed;

        final svc = DatabaseService();
        final dbServer = DbServer(
          id: 'agent_plan_e2e_ch',
          name: 'Agent Plan E2E CH',
          type: DatabaseType.clickhouse,
          host: ClickhouseTestConfig.host,
          port: ClickhouseTestConfig.port,
          username: ClickhouseTestConfig.username,
          password: ClickhouseTestConfig.password,
          database: testDbName,
        );
        ready = await svc.connect(dbServer);
        if (!ready) await svc.disconnect();
        dbService = svc;
        server = dbServer;
      } catch (e) {
        // ignore: avoid_print
        print('CH_PLAN_E2E_SKIP: ClickHouse 环境不可达：$e');
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
      final db = testDbName;
      if (seed != null && seed.isConnected && db != null) {
        var cleaned = false;
        try {
          await seed.executeQuery('DROP DATABASE IF EXISTS `$db`');
          cleaned = true;
        } catch (_) {}
        if (!cleaned) {
          try {
            await seed.executeQuery('DROP TABLE `$db`.plan_ch_a');
            cleaned = true;
          } catch (_) {}
        }
        if (!cleaned) {
          try {
            await seed.executeQuery('TRUNCATE TABLE `$db`.plan_ch_a');
            cleaned = true;
          } catch (_) {}
        }
        // ignore: avoid_print
        print(
          'AGENT_PLAN_E2E_CH_CLEANUP: db=$db cleaned=$cleaned '
          '（ch_test 无 DROP 授权时尽力清理，leftover 为空表/空库）',
        );
        try {
          await seed.disconnect();
        } catch (_) {}
      }
    });

    test(
      'AI-PLAN-E2E-CH2P CH 两段式 system.one 越界读 → 执法守卫拒绝（AC4.4 M5 扩面后断言翻转）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('CH_PLAN_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        final h = _PlanHarness(
          dbService: dbService!,
          ctxSource: _CtxSource(
            connectionId: server!.id,
            connectionName: server!.name,
            databaseName: testDbName!,
            dbType: DatabaseType.clickhouse,
          ),
          // CH EXPLAIN 经 MySQL 兼容口不可靠——探针自动批准 L0.5（目标面是
          // AC4.4 执法层）。
          autoApproveL05: true,
        );
        addTearDown(h.dispose);
        h.chat.respond(
          _call(
            _toolCall('execute_readonly_sql', <String, dynamic>{
              'sql': 'SELECT count() AS c FROM system.one',
            }),
          ),
        );
        h.chat.respond(_text('探针完成'));

        await h.runner.start(
          uiPort: _agentUiPort,
          userMessage: '跨库探针',
          gates: h.gates,
        );

        final steps = h.steps;
        expect(steps, hasLength(1));
        final step = steps.first;
        // Fix-G 扩面（M5）：CH 两段式 `db.table` 首段=库入执法面
        //（`_databaseQualifierDialects` 已含 clickhouse；与 PG 两段式 =
        // schema 的语义分立由 dbType 门保证）——越界两段式读必须被
        // executor 执法守卫拒绝，不再穿透到 DB 层。
        final Map<String, dynamic>? error =
            step['error'] as Map<String, dynamic>?;
        final bool rejectedByEnforcement =
            error != null &&
            error['code'] == AgentToolErrorCodes.invalidArguments &&
            error['message'].toString().contains('cross-database');
        expect(
          rejectedByEnforcement,
          isTrue,
          reason: 'Fix-G 执法守卫：CH 两段式首段=库，越界读必须被执法拒绝',
        );

        if (error == null) {
          final ref = step['resultRef'] as Map<String, dynamic>;
          // ignore: avoid_print
          print(
            'AGENT_PLAN_E2E_CH2P_VIOLATION: CH 两段式越界读（system.one，'
            '首段 system ≠ 锁定库）**穿透执行**，返回 ${ref['rowCount']} 行'
            '——Fix-G 执法面已覆盖 CH 两段式，穿透即执法失效，需立即复查 '
            '_crossDatabaseSqlProblem 的 CH 段数判定',
          );
        } else {
          // ignore: avoid_print
          print(
            'AGENT_PLAN_E2E_CH2P_GUARD: CH 两段式越界读被执法守卫拒绝'
            '（${error['code']}）——AC4.4 方言扩面生效（M5 实证收口）',
          );
        }
        expect(h.runner.status, AgentRunStatus.completed);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
