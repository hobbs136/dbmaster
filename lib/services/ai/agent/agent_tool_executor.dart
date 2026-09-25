/// Agent 工具执行器：单一拦截点 + A1 六工具 handler（tasks-ai-agent.md T10 /
/// design-ai-agent.md D3、D10、D19、§4.1、§5.2）。
///
/// D3 链序（**不可绕**，任何 handler 不自带权限判定）：
///
/// 1. 计步——[execute] 入口自增（D10：含被门拒/人拒/目录外拒绝的全部调用，
///    AC2.3 对账基准，与审计同点）；
/// 2. 目录查找——dispatch 侧 `AgentToolCatalog.find`（milestone 可寻址锁，
///    T04）→ 目录外 `UNKNOWN_TOOL`（AC1.6）；
/// 3. 参数解析——JSON 对象形态校验，失败 `INVALID_ARGUMENTS`（D4：运行时
///    校验以手写收窄为准，未知参数忽略）；
/// 4. NoSQL 方言预拦截——SQL 文本类工具（execute_readonly_sql /
///    get_sample_data / explain_plan）在 `runCtx.dbType.isNoSQL` 连接上直接
///    `UNSUPPORTED_DIALECT`。**必须先于门 evaluate**：否则读前分析对
///    NoSQL 连接 EXPLAIN 必失败 → fail-closed 假确认（T05 前置契约「消费方
///    先做 NoSQL 拦截，本模块不重复判」的执行侧落点）。这是拒绝路径，不是
///    执行旁路——审计（blocked）与计步照常；
/// 5. 门 evaluate——`AgentGate.evaluate` 判定序 ①-⑤（T06）：reject → 回喂
///    错误（审计 blocked）；allow → 执行（审计 allowed / allowed_session，
///    后者判据 = kind==allow && level==l05，T06 类注⑤）；
/// 6. confirm(l05) → `GateCallbacks.onL05Confirm` 阻塞等人（D7：tool_call
///    不返回直到卡上决策落定；停止时 Completer 以 cancel 解决由 runner 协同，
///    T11）。approved → 执行（confirmed）；approvedForSession → 账本
///    [AgentPermissionLedger.allowL05] + 执行（allowed_session）；rejected /
///    无回调（fail-closed）→ `GATE_REJECTED`。confirm(l1)（T28 A2 合龙，
///    `submit_action_plan` 为目录唯一 l1 声明工具）→ 计划链
///    [AgentToolExecutor._runPlanChain]：提交校验（T22）→
///    `GateCallbacks.onPlanApproval(plan)` 阻塞等人——**执行（approve +
///    execute）由装配层（shell）在回调内完成**（deps 是 UI 绑定面，T22 文件
///    头装配说明）；计划为就地可变对象，回调返回后本执行器按 plan 终态组装
///    回喂（design §6.3：done → {ok, steps}；拒绝 → PLAN_REJECTED）；
/// 7. handler 执行——A1 六工具 + A2 界面七工具（见各 `_handle*`），全部经
///    注入的 [AgentDbAccess] 函数触达 dbService（组件级 MUST NOT 3：不直接
///    实例化 Adapter）；`execute_readonly_sql` / `get_sample_data` 先过
///    `ReadonlySqlValidator` 第二道防线（AC9.7）——写语句回
///    `WRITE_REJECTED_READONLY_CHANNEL` 且 detail 指引
///    「write statements require submit_action_plan」（AC4.2，D5），并受
///    **库级限定名执法**（AC4.4，P2-4 并入 T28；Fix-G 扩面 M5 + 掩码防御 +
///    describe/explain 同判：限定首段 ≠ 锁定 databaseName 且方言上限定符
///    首段语义为「库」→ INVALID_ARGUMENTS 拒，见
///    [_crossDatabaseSqlProblem] / [_crossDatabaseTableArgProblem]）；界面工具经 run 内 uiPort 派发
///    （null → fail-closed 拒，outcome 失败回喂自纠 AC15.1）；
/// 8. 步消息——§5.2 结构：toolCall + toolResult 消息对，
///    `toolResultData['agent'] = {kind:'agent_step', runId, stepNo, tool,
///    gateLevel, gateDecision, summary, resultRef?:{rowCount, columns,
///    snapshotRows≤10}, durationMs, error?}` + `toolResultSummary` 兜底文本；
///    row 形态结果同时登记 **run 内 result_ref 注册表**（T28：refId =
///    `res_<stepNo>`，界面工具与本注册表消费；run 切换（runId 变化）即失效
///    ——跨 run 引用一律 INVALID_ARGUMENTS）；
/// 9. 审计——每次 execute 恰好一条 `recordAgentEvent`（T07；拦截/人拒也落，
///    AC13.1；审计写失败不阻断执行路径）；
/// 10. 统计——`recordAgentToolCall`（T08 白名单分桶；目录外名字被其静默
///     拒收）+ L0.5 卡事件（shown/sessionAllowed/rejected）；
/// 11. 回喂 JSON——design §4.1 格式 `{ok, data?, error?{code,message},
///     truncated?, rowCount?, columns?}` + D19 双上限（行快照 ≤20、单结果
///     字符 ≤4000、超限截断标记 + rowCount/列名保留），三级降级：先减行、
///     再弃载荷保元数据、最后硬截断。
///
/// handler 执行异常 → `EXECUTION_FAILED`，detail 过 `redactSecrets`（NF2.2，
/// AC15.1 自纠通路）。
///
/// 本文件不 import material（组件级 §0 MUST NOT 2）；公共 API 显式类型。
library;

import 'dart:convert';
import 'dart:math' as math;

import '../../../models/ai_message_type.dart' show AiMessageType;
import '../../../models/ai_models.dart' show AiToolCall;
import '../../../models/audit_log_entry.dart' show AgentGateDecision;
import '../../../models/database_models.dart'
    show AiMessage, DatabaseType, DbColumn, DbIndex, ForeignKey;
import '../../../utils/app_logger.dart' show AppLogger;
import '../../../utils/secret_redactor.dart' show redactSecrets;
import '../../audit_log_service.dart' show AuditLogService;
import '../../query_optimizer/explain_parser.dart' show ExplainParser;
import '../../workbench_usage_stats_service.dart'
    show AgentL05Stat, WorkbenchUsageStatsService;
import 'agent_gate.dart'
    show AgentGate, AgentRunContext, GateDecision, GateDecisionKind;
import 'agent_gate_analysis.dart' show ReadImpactAnalysis;
import 'agent_permission_ledger.dart' show AgentPermissionLedger;
import 'agent_plan.dart'
    show
        AgentActionPlan,
        AgentPlanRowsEstimate,
        AgentPlanRowsEstimator,
        AgentPlanStatus,
        AgentPlanStep,
        AgentPlanStepInput,
        AgentPlanStepStatus,
        AgentPlanSubmitter,
        AgentRowsEstimateSource;
import 'agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolCatalog, AgentToolErrorCodes, AgentToolSpec;
import 'agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort, GateCardResult;
import '../readonly_sql_validator.dart' show ReadonlySqlValidator;
import '../sql_literal_mask.dart' show maskSqlLiteralsAndComments;

/// L1 计划批准回调签名（design §4.3 原文：
/// `Future<GateCardResult> Function(AgentActionPlan plan)`）。
///
/// T28 收口：A1 期以 `Object` 占位的参数类型收紧为 [AgentActionPlan]
/// （一处改动，实现方签名不受影响——参数逆变下既有 `Function(Object)`
/// 实现仍合法）。**执行语义**：装配层（shell）实现本回调时承担
/// 「approve + execute（deps 装配）」——计划执行依赖 UI 确认面（DDL/DML
/// 双门对话框），只可能在装配层注入（T22 文件头装配说明）；计划为就地
/// 可变对象，本执行器在回调返回后按 plan 终态组装回喂。
typedef AgentPlanApprovalCallback =
    Future<GateCardResult> Function(AgentActionPlan plan);

/// 门卡回调（design §4.3）：由 UI 层（shell，T14/T28）实现注入。
///
/// - [onL05Confirm]：落 L0.5 确认卡消息 + 等 Completer（阻塞等人，D7）；
///   停止 / 会话切换时以 rejected 解决（T11/T14 协同）；
/// - [onPlanApproval]：L1 计划卡批准（T28 真接线：落卡 + 注册表 +
///   等 Completer；approved → 装配层 approve + execute；rejected →
///   reject 零执行）。
class GateCallbacks {
  const GateCallbacks({
    required this.onL05Confirm,
    required this.onPlanApproval,
  });

  /// L0.5 确认卡：入参 = 读前影响面（AC8.4 确认卡数据）+ 待确认 SQL。
  final Future<GateCardResult> Function(ReadImpactAnalysis impact, String sql)
  onL05Confirm;

  /// L1 计划卡批准（T28 真接线；无 UI 宿主时 fail-closed → PLAN_REJECTED）。
  final AgentPlanApprovalCallback onPlanApproval;
}

/// 一次待执行的工具调用（T10 接口草案）。
///
/// [argumentsJson] 保持 LLM 原始 JSON 文本，由 [AgentToolExecutor.execute]
/// **在链内**解析——畸形 JSON 也是一次完整调用（计步 + 审计 +
/// INVALID_ARGUMENTS 回喂），不把解析失败漏到链外（D10）。
class AgentToolCall {
  const AgentToolCall({
    required this.id,
    required this.name,
    required this.argumentsJson,
  });

  /// tool_call id（OpenAI/Anthropic 协议回填 role:'tool' 用）。
  final String id;

  /// 工具名（snake_case，对齐目录）。
  final String name;

  /// LLM 参数 JSON 文本（AiToolCall.functionArguments）。
  final String argumentsJson;

  /// 从 AiClient 的 AiToolCall 构造（T11 消费入口；jsonDecode 失败时
  /// argumentsJson 为原文，由 execute 在链内拒绝）。
  factory AgentToolCall.fromAiToolCall(AiToolCall call) => AgentToolCall(
    id: call.id,
    name: call.functionName,
    argumentsJson: call.functionArguments,
  );
}

/// dbService 访问函数集（design §2.1 EXEC 复用面；组件级 MUST NOT 3——
/// 执行器经注入函数触达 DatabaseService，不直接实例化 Adapter）。
///
/// 生产装配（T14 shell）直接传 DatabaseService 的方法 tear-off——签名按
/// dbService 现状裁剪（多出的可选命名参数如 sessionId 不影响 tear-off
/// 赋值，Dart 函数子型保证）。测试注入闭包 spy。
class AgentDbAccess {
  const AgentDbAccess({
    required this.getTables,
    required this.getTableColumns,
    required this.getTableIndexes,
    required this.getForeignKeys,
    required this.getCreateTableSql,
    required this.getExplainPlan,
    required this.executeQuery,
  });

  /// 列表（list_tables；NoSQL 连接 = 集合名）。
  final Future<List<String>> Function(String? connectionId) getTables;

  final Future<List<DbColumn>> Function(
    String tableName, {
    String? connectionId,
    String? databaseName,
  })
  getTableColumns;

  final Future<List<DbIndex>> Function(
    String tableName, {
    String? connectionId,
    String? databaseName,
  })
  getTableIndexes;

  final Future<List<ForeignKey>> Function(
    String tableName, {
    String? connectionId,
    String? databaseName,
  })
  getForeignKeys;

  final Future<String> Function(
    String tableName, {
    String? connectionId,
    String? databaseName,
  })
  getCreateTableSql;

  /// EXPLAIN 只读通道（explain_plan；不支持方言抛 UnsupportedError）。
  final Future<List<Map<String, dynamic>>> Function(
    String sql, {
    String? connectionId,
  })
  getExplainPlan;

  /// 查询执行管线（execute_readonly_sql / get_sample_data；天然继承
  /// 行限 3000 语义与 DDL/DML 拦截，design §2.1 EXEC 面）。
  final Future<List<Map<String, dynamic>>> Function(
    String sql, {
    String? connectionId,
    String? database,
  })
  executeQuery;
}

/// 审计记录函数类型（签名 = T07 `AuditLogService.recordAgentEvent` 原文，
/// 一字不差；注入供测试 spy）。
typedef AgentAuditRecorder =
    Future<void> Function({
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
    });

/// 工具调用计数函数类型（T08 `recordAgentToolCall`；仅收目录名）。
typedef AgentToolCallStatsRecorder = void Function(String toolName);

/// L0.5 卡事件计数函数类型（T08 `recordL05Event`）。
typedef AgentL05StatsRecorder = void Function(AgentL05Stat event);

/// L1 撞门拒绝计数函数类型（T28 `recordL1Blocked`，R14 字段 6 / 风险 1）。
typedef AgentL1BlockedStatsRecorder = void Function();

/// 单次工具执行结果（T10 接口草案：`{ok, toLLMJson(), stepMessage,
/// resultRef?}`）。
///
/// - [toLLMJson]：`role:'tool'` 回喂内容（§4.1 格式 + D19 双上限已应用）；
/// - [callMessage] + [resultMessage]：§5.2 步消息对（type: toolCall +
///   toolResult，agent 载荷挂在 resultMessage.toolResultData['agent']），
///   由 runner（T11）落 sessionManager；
/// - [resultRef]：row 形态结果的内存引用（A2 舞台/产物条寻址；
///   refId = `res_<stepNo>`，rows 为行限内全量不复制，T09 契约）。
class AgentToolOutcome {
  const AgentToolOutcome({
    required this.ok,
    required this.feedJson,
    required this.callMessage,
    required this.resultMessage,
    required this.errorCode,
    required this.errorMessage,
    this.resultRef,
  });

  /// 是否成功（拦截 / 人拒 / 执行失败均为 false）。
  final bool ok;

  /// 回喂 JSON 文本（builder 产物，避免重复编码）。
  final String feedJson;

  /// §5.2 toolCall 消息。
  final AiMessage callMessage;

  /// §5.2 toolResult 消息。
  final AiMessage resultMessage;

  /// 失败错误码（§4.1 全集）；成功为 null。T11 停止汇报消费。
  final String? errorCode;

  /// 失败明细（已脱敏）；成功为 null。
  final String? errorMessage;

  /// row 形态结果引用；非 row 工具为 null。
  final AgentResultRef? resultRef;

  /// 回喂 JSON（role:'tool' content，紧凑 JSON 文本）。
  String toLLMJson() => feedJson;
}

/// 工具执行器（D3 单一拦截点）。构造注入全部依赖（NF5.3 可脱离 UI 单测）：
/// [gate] 为已装配的 [AgentGate]（其 createAnalysis 工厂闭包内绑
/// dbService.getExplainPlan + QuerySettingsService 阈值——T06 文件头装配
/// 示例，生产接线归 T14；executor 只消费 gate 实例，不直接依赖
/// QuerySettingsService / 分析工厂——那是门的内部依赖，避免第二装配点）。
class AgentToolExecutor {
  AgentToolExecutor({
    required AgentGate gate,
    required AgentDbAccess db,
    AgentAuditRecorder? audit,
    AgentToolCallStatsRecorder? recordToolCall,
    AgentL05StatsRecorder? recordL05Event,
    AgentPlanRowsEstimator? planRowsEstimator,
    AgentL1BlockedStatsRecorder? recordL1Blocked,
  }) : _gate = gate,
       _db = db,
       _audit = audit ?? AuditLogService().recordAgentEvent,
       _recordToolCall =
           recordToolCall ?? WorkbenchUsageStatsService().recordAgentToolCall,
       _recordL05Event =
           recordL05Event ?? WorkbenchUsageStatsService().recordL05Event,
       _planRowsEstimatorOverride = planRowsEstimator,
       _recordL1Blocked =
           recordL1Blocked ?? WorkbenchUsageStatsService().recordL1Blocked;

  /// D19：LLM 行快照上限（与 UI 侧 N=10 独立）。
  static const int _llmRowSnapshotCap = 20;

  /// D19：单结果字符上限（超限截断 + 截断标记 + rowCount/列名保留）。
  static const int _llmCharCap = 4000;

  /// §5.2：会话文件步消息快照行上限（复用 M1 take(N) 不变式模式）。
  static const int _messageSnapshotRows = 10;

  /// `toolResultSummary` 兜底文本长度上限（一行摘要）。
  static const int _summaryMaxChars = 200;

  /// get_sample_data LIMIT 归一化（与 agent_gate.dart 私有常量**同值同步**：
  /// clamp 1-100、默认 10——两侧需一致，gate 侧注释已互指）。
  static const int _sampleLimitMin = 1;
  static const int _sampleLimitMax = 100;
  static const int _sampleLimitDefault = 10;

  /// get_sample_data table 参数标识符白名单（Fix-B 中-2，方案①）：只放行
  /// 字母 / 数字 / 下划线 / 点——点号在白名单内是为容纳 `schema.table` /
  /// `db.table` 限定形态（多库连接下的合法寻址）；其余任何字符（空格 /
  /// 引号 / 分号 / 括号 / 注释符等）一律 INVALID_ARGUMENTS 拒绝（零执行、
  /// 计步、审计 blocked）。同形 SQL（`SELECT * FROM $table` 无引界拼接）的
  /// 注入面第一道防线；只读校验（ReadonlySqlValidator）为第二道。gate 侧
  /// `_analysisSqlFor` 的同形构造不做此校验（参数校验是 executor handler
  /// 职责，gate 契约明确 args 不校验）——分析侧畸形 SQL 只影响 EXPLAIN
  /// 精度（fail-closed 需确认），无执行面。
  static final RegExp _tableIdentifierPattern = RegExp(r'^[A-Za-z0-9_.]+$');

  /// 写语句首关键字集（= ReadonlySqlValidator._dmlWords 的写语句子集）：
  /// 校验器拒绝后按首关键字分类错误码——写语句回
  /// WRITE_REJECTED_READONLY_CHANNEL（AC4.2 + 计划路径指引），其余拒绝形态
  /// （多语句 / 空语句 / PRAGMA 越界等）回 INVALID_ARGUMENTS。
  static const Set<String> _writeStatementPrefixes = <String>{
    'INSERT',
    'UPDATE',
    'DELETE',
    'MERGE',
    'REPLACE',
    'TRUNCATE',
    'CREATE',
    'ALTER',
    'DROP',
    'GRANT',
    'REVOKE',
    'CALL',
    'EXEC',
    'EXECUTE',
    'SET',
    'USE',
    'ATTACH',
    'DETACH',
    'REINDEX',
    'VACUUM',
    'ANALYZE',
    'LOAD',
    'COPY',
  };

  /// SQL 文本类工具（NoSQL 连接预拦截面 + 确认卡/审计取 SQL 面）。
  static const Set<String> _sqlTextTools = <String>{
    'execute_readonly_sql',
    'get_sample_data',
    'explain_plan',
  };

  final AgentGate _gate;
  final AgentDbAccess _db;
  final AgentAuditRecorder _audit;
  final AgentToolCallStatsRecorder _recordToolCall;
  final AgentL05StatsRecorder _recordL05Event;
  final AgentPlanRowsEstimator? _planRowsEstimatorOverride;
  final AgentL1BlockedStatsRecorder _recordL1Blocked;

  int _stepsUsed = 0;

  /// run 内 result_ref 注册表（T28，§4.5 AgentResultRef 寻址）：refId =
  /// `res_<stepNo>` → 引用。run 切换（runId 变化）时整体失效——跨 run 的
  /// 同名 refId 不代表同一结果（T09 契约），界面工具查不到一律拒绝。
  final Map<String, AgentResultRef> _resultRefs = <String, AgentResultRef>{};

  /// 当前注册表归属的 runId（null = 尚无 run）。
  String? _resultRefsRunId;

  /// D10 步数计数：进入执行管线的每个 tool_call（含被门拒、被用户拒、
  /// 目录外拒绝）。AC2.3 对账基准——与审计同点、同口径。
  int get stepsUsed => _stepsUsed;

  /// 计数器复位（新 run 起点；T11 `start` 时调用——runner 的 maxSteps 预算
  /// 与本计数同源对账）。
  void resetSteps() {
    _stepsUsed = 0;
  }

  /// result_ref 注册表复位（新 run 起点同步清理；Fix-F ④——原惰性清理靠
  /// 下一个 execute 的 runId 切换（见 [execute] 入口），两次 run 之间的
  /// 空窗期轨迹卡「在舞台打开」按 refId 查询会解析到**上一 run** 的同名
  /// 引用（refId = `res_<stepNo>` 跨 run 必然撞名——T09「跨 run 同名
  /// refId 不代表同一结果」契约）。runner `start` 与 [resetSteps] 同挂点
  /// 调用；清空后归属 runId 一并复位（下次 execute 重新登记归属）。
  void resetResultRefs() {
    _resultRefs.clear();
    _resultRefsRunId = null;
  }

  /// run 内 result_ref 查询（T28：shell 轨迹卡「在舞台打开」优先查注册表
  /// ——全量行口径；查不到回落消息快照。仅当前 run 有效）。
  AgentResultRef? resultRefOf(String refId) => _resultRefs[refId];

  /// 执行一次工具调用（链序见 library 注释 1-11，D3 不可绕）。
  ///
  /// [uiPort] = 本次 run 的界面派发端口（T28：runner.start 必填传入；缺省
  /// null 时界面七工具 fail-closed 拒绝——A2 相位下生产路径恒有端口）。
  Future<AgentToolOutcome> execute({
    required AgentToolCall call,
    required AgentRunContext runCtx,
    required AgentPermissionLedger ledger,
    GateCallbacks? gates,
    AgentUiPort? uiPort,
  }) async {
    // run 边界：注册表随 runId 切换整体失效（防跨 run 同名 refId 串数据）。
    if (_resultRefsRunId != runCtx.runId) {
      _resultRefs.clear();
      _resultRefsRunId = runCtx.runId;
    }

    // 1. 计步（D10：入口自增，含被拒调用）。
    _stepsUsed += 1;
    final int stepNo = _stepsUsed;
    final Stopwatch clock = Stopwatch()..start();

    // 2. dispatch 侧目录查找（milestone 可寻址锁在 find，T04）。
    final AgentToolSpec? spec = AgentToolCatalog.find(call.name);

    // 3. 参数解析（链内：畸形 JSON 也计步 + 审计 + 回喂）。
    Map<String, dynamic> args = const <String, dynamic>{};
    String? argsError;
    if (spec != null) {
      final Map<String, dynamic>? parsed = _parseArguments(call.argumentsJson);
      if (parsed == null) {
        argsError = 'arguments must be a valid JSON object';
      } else {
        args = parsed;
      }
    }

    if (spec == null) {
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: null,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: AgentToolErrorCodes.unknownTool,
        errorMessage:
            'tool "${call.name}" is not in the agent tool catalog '
            '(known tools: milestone ${AgentToolCatalog.activeMilestone} set)',
      );
    }

    // 统计：工具调用计数（进入管线即计，与步数同口径；目录名即白名单）。
    _recordToolCall(spec.name);

    if (argsError != null) {
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: spec.gateLevel,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: AgentToolErrorCodes.invalidArguments,
        errorMessage: argsError,
      );
    }

    // 4. NoSQL 方言预拦截（先于 evaluate——见 library 注释 4）。
    if (_sqlTextTools.contains(spec.name) && runCtx.dbType.isNoSQL) {
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: spec.gateLevel,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: AgentToolErrorCodes.unsupportedDialect,
        errorMessage:
            'SQL tools are not supported on ${runCtx.dbType.name} '
            'connections',
      );
    }

    // 5. 门 evaluate（判定序 ①-⑤ 封装在 T06；args 不做参数校验是 gate 契约，
    //    缺形参由上方/handler 侧拦截）。
    final GateDecision decision = await _gate.evaluate(
      spec: spec,
      args: args,
      runCtx: runCtx,
      ledger: ledger,
    );

    switch (decision.kind) {
      case GateDecisionKind.reject:
        return _assemble(
          call: call,
          args: args,
          runCtx: runCtx,
          stepNo: stepNo,
          clock: clock,
          auditLevel: decision.level,
          auditDecision: AgentGateDecision.blocked,
          ok: false,
          errorCode: decision.reasonCode ?? AgentToolErrorCodes.executionFailed,
          errorMessage: 'rejected by the permission gate',
          auditSql: _auditSqlFor(spec, args),
        );

      case GateDecisionKind.allow:
        // ⑤ 会话放行短路的 allow@l05 → allowed_session（T06 唯一产生源；
        //    其余 allow 的 level 恒为 l0/suggest）。
        final AgentGateDecision auditDecision =
            decision.level == AgentGateLevel.l05
            ? AgentGateDecision.allowedSession
            : AgentGateDecision.allowed;
        return _runHandler(
          call: call,
          args: args,
          spec: spec,
          runCtx: runCtx,
          stepNo: stepNo,
          clock: clock,
          auditLevel: decision.level,
          auditDecision: auditDecision,
          uiPort: uiPort,
        );

      case GateDecisionKind.confirm:
        return _runConfirmChain(
          call: call,
          args: args,
          spec: spec,
          runCtx: runCtx,
          ledger: ledger,
          gates: gates,
          decision: decision,
          stepNo: stepNo,
          clock: clock,
          uiPort: uiPort,
        );
    }
  }

  /// execute 链异常的兜底合成（Fix-B 中-1）：[execute] 本身抛出（门
  /// evaluate 崩溃 / l1 结构守卫 StateError 等 unforeseen 路径——计步已在
  /// execute 入口完成，但审计与步消息未落）。由 runner 捕获后调用本方法为
  /// **该步**补齐审计记录（EXECUTION_FAILED / blocked 形态，维持「每次调用
  /// 至少一条审计」不变式 AC13.1）与步消息对，零 db 访问；[errorMessage]
  /// 原始异常文本，本方法内过 `redactSecrets`（NF2.2）。
  ///
  /// stepNo 取当前 [_stepsUsed]（异常步的计步已自增，与 execute 内
  /// stepNo 同源）；duration 置 0（兜底瞬时，不启动计时器）。
  Future<AgentToolOutcome> rescueOutcome({
    required AgentToolCall call,
    required AgentRunContext runCtx,
    required String errorMessage,
  }) {
    return _assemble(
      call: call,
      args: const <String, dynamic>{},
      runCtx: runCtx,
      stepNo: _stepsUsed,
      clock: Stopwatch(),
      auditLevel: null,
      auditDecision: AgentGateDecision.blocked,
      ok: false,
      errorCode: AgentToolErrorCodes.executionFailed,
      errorMessage: redactSecrets(errorMessage),
    );
  }

  // ── confirm 链（D7 阻塞等人）────────────────────────────────────────────

  Future<AgentToolOutcome> _runConfirmChain({
    required AgentToolCall call,
    required Map<String, dynamic> args,
    required AgentToolSpec spec,
    required AgentRunContext runCtx,
    required AgentPermissionLedger ledger,
    required GateCallbacks? gates,
    required GateDecision decision,
    required int stepNo,
    required Stopwatch clock,
    required AgentUiPort? uiPort,
  }) async {
    if (decision.level == AgentGateLevel.l1) {
      // T28 A2 合龙：L1 计划链（submit_action_plan = 目录唯一 l1 声明工具，
      // dispatch 面窄——非该工具的 l1 判定 = 目录漂移，fail-loud 守卫）。
      if (spec.name != 'submit_action_plan') {
        throw StateError(
          'AgentToolExecutor: confirm(l1) reached for non-plan tool '
          '"${spec.name}" (catalog drift; plan channel is submit_action_plan '
          'only)',
        );
      }
      return _runPlanChain(
        call: call,
        args: args,
        runCtx: runCtx,
        gates: gates,
        decision: decision,
        stepNo: stepNo,
        clock: clock,
      );
    }

    // 统计：确认卡已呈现。
    _recordL05Event(AgentL05Stat.shown);

    // fail-closed：无确认回调 / 无可确认语句 → 拒绝，绝不静默放行。
    final String? gateSql = _gateCardSql(spec, args);
    if (gates == null || gateSql == null) {
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: decision.level,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: AgentToolErrorCodes.gateRejected,
        errorMessage:
            'confirmation gate was triggered but no confirmation UI is '
            'available; failing closed',
        auditSql: _auditSqlFor(spec, args),
      );
    }

    final ReadImpactAnalysis impact =
        decision.impact ??
        const ReadImpactAnalysis(
          estimatedRows: null,
          fullScan: false,
          analysisUnavailable: true,
        );

    // 阻塞等人（D7）：直到卡上决策落定；停止时 shell 以 rejected 解决。
    final GateCardResult card = await gates.onL05Confirm(impact, gateSql);

    switch (card) {
      case GateCardResult.rejected:
        _recordL05Event(AgentL05Stat.rejected);
        return _assemble(
          call: call,
          args: args,
          runCtx: runCtx,
          stepNo: stepNo,
          clock: clock,
          auditLevel: decision.level,
          auditDecision: AgentGateDecision.rejectedByUser,
          ok: false,
          errorCode: AgentToolErrorCodes.gateRejected,
          errorMessage: 'the user rejected this read at the L0.5 gate',
          auditSql: _auditSqlFor(spec, args),
        );

      case GateCardResult.approved:
        return _runHandler(
          call: call,
          args: args,
          spec: spec,
          runCtx: runCtx,
          stepNo: stepNo,
          clock: clock,
          auditLevel: decision.level,
          auditDecision: AgentGateDecision.confirmed,
          uiPort: uiPort,
        );

      case GateCardResult.approvedForSession:
        // 会话放行（AC8.5）：账本记连接，后续同连接免卡（evaluate ⑤ 短路）。
        ledger.allowL05(runCtx.connectionId ?? '');
        _recordL05Event(AgentL05Stat.sessionAllowed);
        return _runHandler(
          call: call,
          args: args,
          spec: spec,
          runCtx: runCtx,
          stepNo: stepNo,
          clock: clock,
          auditLevel: decision.level,
          auditDecision: AgentGateDecision.allowedSession,
          uiPort: uiPort,
        );
    }
  }

  // ── handler 派发与 A1 六工具 ────────────────────────────────────────────

  Future<AgentToolOutcome> _runHandler({
    required AgentToolCall call,
    required Map<String, dynamic> args,
    required AgentToolSpec spec,
    required AgentRunContext runCtx,
    required int stepNo,
    required Stopwatch clock,
    required AgentGateLevel auditLevel,
    required AgentGateDecision auditDecision,
    required AgentUiPort? uiPort,
  }) async {
    final _HandlerPayload payload;
    try {
      payload = await _dispatch(spec.name, args, runCtx, uiPort);
    } on _ToolException catch (e) {
      // handler 内拒绝（只读闸 / 参数收窄 / 方言不支持——均未触达库）：
      // 审计与步消息按拦截形态落 blocked（D13：拦截尝试也落，success=false +
      // 被拦语句；门本身可能已放行——写语句走只读通道即此形态，AC4.2）。
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: auditLevel,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: e.code,
        errorMessage: e.message,
        auditSql: _auditSqlFor(spec, args),
      );
    } catch (e) {
      // EXECUTION_FAILED：detail 过 redactSecrets（NF2.2），模型可据此自纠
      //（AC15.1）。执行已实际发起（门结论保持 allowed/confirmed/allowed_
      // session，与 handler 内拦截的 blocked 区分）。
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: auditLevel,
        auditDecision: auditDecision,
        ok: false,
        errorCode: AgentToolErrorCodes.executionFailed,
        errorMessage: redactSecrets(e.toString()),
        auditSql: _auditSqlFor(spec, args),
      );
    }
    return _assemble(
      call: call,
      args: args,
      runCtx: runCtx,
      stepNo: stepNo,
      clock: clock,
      auditLevel: auditLevel,
      auditDecision: auditDecision,
      ok: true,
      payload: payload,
      auditSql: payload.auditSql,
    );
  }

  Future<_HandlerPayload> _dispatch(
    String name,
    Map<String, dynamic> args,
    AgentRunContext runCtx,
    AgentUiPort? uiPort,
  ) {
    switch (name) {
      case 'execute_readonly_sql':
        return _handleExecuteReadonlySql(args, runCtx);
      case 'list_tables':
        return _handleListTables(runCtx);
      case 'describe_table':
        return _handleDescribeTable(args, runCtx);
      case 'get_sample_data':
        return _handleGetSampleData(args, runCtx);
      case 'explain_plan':
        return _handleExplainPlan(args, runCtx);
      case 'get_current_context':
        return _handleGetCurrentContext(runCtx);
      // ── A2 界面七工具（T28；suggest 级经 uiPort 落建议卡消息）──────────
      case 'open_result_grid':
        return _handleOpenResultGrid(args, uiPort);
      case 'show_table_structure':
        return _handleShowTableStructure(args, uiPort);
      case 'open_sql_editor':
        return _handleOpenSqlEditor(args, uiPort);
      case 'render_chart':
        return _handleRenderChart(args, uiPort);
      case 'pin_artifact':
        return _handlePinArtifact(args, uiPort);
      case 'open_in_classic':
        return _handleSuggestOpenInClassic(args, uiPort);
      case 'focus_sidebar':
        return _handleSuggestFocusSidebar(args, uiPort);
      // submit_action_plan 不经 dispatch：l1 confirm 在链内先行（计划须在
      // onPlanApproval 之前构造——回调入参即计划对象）。
      default:
        // 不变量守卫：find 过滤集与 handler 集合同步（新工具入目录必须配
        // handler——fail-loud 好过静默空结果）。
        throw StateError(
          'AgentToolExecutor: no handler for catalog tool "$name"',
        );
    }
  }

  /// execute_readonly_sql：单语句；先库级限定名执法（AC4.4）再
  /// ReadonlySqlValidator（AC9.7 第二道防线）再执行（读前分析已在 gate
  /// evaluate④ 完成）。写语句 → WRITE_REJECTED_READONLY_CHANNEL + 计划路径
  /// 指引（AC4.2，D5）。
  Future<_HandlerPayload> _handleExecuteReadonlySql(
    Map<String, dynamic> args,
    AgentRunContext runCtx,
  ) async {
    final String sql = _requiredStringArg(args, 'sql');

    final String? crossDb = _crossDatabaseSqlProblem(sql, runCtx);
    if (crossDb != null) {
      throw _ToolException(AgentToolErrorCodes.invalidArguments, crossDb);
    }

    final check = ReadonlySqlValidator.validate(
      sql,
      isSqlite: runCtx.dbType == DatabaseType.sqlite,
    );
    if (!check.allowed) {
      throw _rejectByValidator(sql, check.reason);
    }

    final List<Map<String, dynamic>> rows = await _db.executeQuery(
      sql,
      connectionId: runCtx.connectionId,
      database: runCtx.databaseName,
    );
    return _rowPayload(
      sql: sql,
      rows: rows,
      summary: 'query ok: ${rows.length} row(s)',
    );
  }

  /// list_tables：作用域锁 run 快照（AC4.4）——connectionId/database 只取
  /// 快照值。
  Future<_HandlerPayload> _handleListTables(AgentRunContext runCtx) async {
    final List<String> tables = await _db.getTables(runCtx.connectionId);
    return _HandlerPayload(
      data: <String, dynamic>{'tables': tables},
      summary: 'listed ${tables.length} table(s)',
      shrinkKey: 'tables',
      shrinkList: tables,
      rowCount: tables.length,
    );
  }

  /// describe_table：列/索引/外键 + 建表 DDL；方言差异如实（可选面取不到
  /// → null，不伪造）。table 先过标识符白名单（[_tableIdentifierPattern]，
  /// 与 get_sample_data 同量级——describe 各取数通道按方言拼接/传参，白名单
  /// 是注入面第一道防线），再过 AC4.4 库级限定名执法（同 get_sample_data
  /// 的段数规则；Fix-G 补齐——describe 通道同样能读其他库的结构元数据）。
  Future<_HandlerPayload> _handleDescribeTable(
    Map<String, dynamic> args,
    AgentRunContext runCtx,
  ) async {
    final String table = _requiredStringArg(args, 'table').trim();
    if (!_tableIdentifierPattern.hasMatch(table)) {
      throw _ToolException(
        AgentToolErrorCodes.invalidArguments,
        "argument 'table' must be a plain identifier (letters, digits, "
        'underscore, and dot for schema-qualified names are allowed): '
        '"$table"',
      );
    }
    // AC4.4 库级执法：限定表名首段 ≠ 锁定库 → 拒（方言适用范围内）。
    final String? crossDb = _crossDatabaseTableArgProblem(table, runCtx);
    if (crossDb != null) {
      throw _ToolException(AgentToolErrorCodes.invalidArguments, crossDb);
    }
    final String? connectionId = runCtx.connectionId;
    final String? databaseName = runCtx.databaseName;

    final List<DbColumn> columns = await _db.getTableColumns(
      table,
      connectionId: connectionId,
      databaseName: databaseName,
    );
    // 索引/外键/DDL 为方言能力面（SqlSchemaAdapter capability）——取不到如实
    // 置 null；列信息是主体，失败走 EXECUTION_FAILED（上层 catch）。
    List<DbIndex>? indexes;
    try {
      indexes = await _db.getTableIndexes(
        table,
        connectionId: connectionId,
        databaseName: databaseName,
      );
    } catch (e) {
      AppLogger.d(
        'AgentToolExecutor',
        'describe_table: indexes unavailable for "$table": $e',
      );
    }
    List<ForeignKey>? foreignKeys;
    try {
      foreignKeys = await _db.getForeignKeys(
        table,
        connectionId: connectionId,
        databaseName: databaseName,
      );
    } catch (e) {
      AppLogger.d(
        'AgentToolExecutor',
        'describe_table: foreign keys unavailable for "$table": $e',
      );
    }
    String? createTableSql;
    try {
      createTableSql = await _db.getCreateTableSql(
        table,
        connectionId: connectionId,
        databaseName: databaseName,
      );
    } catch (e) {
      AppLogger.d(
        'AgentToolExecutor',
        'describe_table: create table SQL unavailable for "$table": $e',
      );
    }

    return _HandlerPayload(
      data: <String, dynamic>{
        'table': table,
        'columns': <Map<String, dynamic>>[
          for (final DbColumn c in columns)
            <String, dynamic>{
              'name': c.name,
              'type': c.type,
              'isPrimaryKey': c.isPrimaryKey,
              'isNullable': c.isNullable,
              'defaultValue': c.defaultValue,
            },
        ],
        'indexes': indexes == null
            ? null
            : <Map<String, dynamic>>[
                for (final DbIndex i in indexes)
                  <String, dynamic>{
                    'name': i.name,
                    'columns': i.columns,
                    'isUnique': i.isUnique,
                  },
              ],
        'foreignKeys': foreignKeys == null
            ? null
            : <Map<String, dynamic>>[
                for (final ForeignKey fk in foreignKeys)
                  <String, dynamic>{
                    'name': fk.name,
                    'column': fk.column,
                    'referencedTable': fk.referencedTable,
                    'referencedColumn': fk.referencedColumn,
                  },
              ],
        'createTableSql': createTableSql,
      },
      summary:
          'described $table: ${columns.length} column(s), '
          '${indexes?.length ?? 0} index(es), ${foreignKeys?.length ?? 0} '
          'foreign key(s)',
    );
  }

  /// get_sample_data：`SELECT * FROM <table> LIMIT n`（n clamp 1-100 默认
  /// 10，与 gate 侧分析 SQL 同形——两侧构造逻辑需同步）；table 先过标识符
  /// 白名单（[_tableIdentifierPattern]，注入面第一道防线——同形 SQL 无引界
  /// 拼接，白名单外字符一律 INVALID_ARGUMENTS 零执行），再过只读校验
  /// （第二道防线）。
  Future<_HandlerPayload> _handleGetSampleData(
    Map<String, dynamic> args,
    AgentRunContext runCtx,
  ) async {
    final String table = _requiredStringArg(args, 'table').trim();
    if (!_tableIdentifierPattern.hasMatch(table)) {
      throw _ToolException(
        AgentToolErrorCodes.invalidArguments,
        "argument 'table' must be a plain identifier (letters, digits, "
        'underscore, and dot for schema-qualified names are allowed): '
        '"$table"',
      );
    }
    final int limit = _normalizeSampleLimit(args);
    final String sql = 'SELECT * FROM $table LIMIT $limit';

    // AC4.4 库级执法：限定表名首段 ≠ 锁定库 → 拒（方言适用范围内）。
    final String? crossDb = _crossDatabaseTableArgProblem(table, runCtx);
    if (crossDb != null) {
      throw _ToolException(AgentToolErrorCodes.invalidArguments, crossDb);
    }

    final check = ReadonlySqlValidator.validate(
      sql,
      isSqlite: runCtx.dbType == DatabaseType.sqlite,
    );
    if (!check.allowed) {
      throw _rejectByValidator(sql, check.reason);
    }

    final List<Map<String, dynamic>> rows = await _db.executeQuery(
      sql,
      connectionId: runCtx.connectionId,
      database: runCtx.databaseName,
    );
    return _rowPayload(
      sql: sql,
      rows: rows,
      summary: 'sampled $table: ${rows.length} row(s)',
    );
  }

  /// explain_plan：EXPLAIN 只读通道，**不执行目标语句**（AC4.5）。目标语句
  /// 先过 AC4.4 库级限定名执法（与 execute_readonly_sql 同判——EXPLAIN
  /// 同样会把其他库的元数据/计划信息带回，Fix-G 补齐），再过只读校验
  ///（拦 EXPLAIN ANALYZE 写形态与多语句）；不支持方言 →
  /// UNSUPPORTED_DIALECT（网关壳 UnsupportedError）。
  Future<_HandlerPayload> _handleExplainPlan(
    Map<String, dynamic> args,
    AgentRunContext runCtx,
  ) async {
    final String sql = _requiredStringArg(args, 'sql');

    final String? crossDb = _crossDatabaseSqlProblem(sql, runCtx);
    if (crossDb != null) {
      throw _ToolException(AgentToolErrorCodes.invalidArguments, crossDb);
    }

    final check = ReadonlySqlValidator.validate(
      sql,
      isSqlite: runCtx.dbType == DatabaseType.sqlite,
    );
    if (!check.allowed) {
      throw _ToolException(
        AgentToolErrorCodes.invalidArguments,
        'statement was rejected by the read-only gate before explaining: '
        '${check.reason ?? ''} (explain_plan is for read-only statements; it '
        'never executes them)',
      );
    }

    final List<Map<String, dynamic>> plan;
    try {
      plan = await _db.getExplainPlan(sql, connectionId: runCtx.connectionId);
    } on UnsupportedError {
      throw _ToolException(
        AgentToolErrorCodes.unsupportedDialect,
        'EXPLAIN is not supported on this connection dialect',
      );
    }
    return _HandlerPayload(
      data: <String, dynamic>{'plan': plan},
      summary: 'explain plan: ${plan.length} plan row(s)',
      auditSql: sql,
      shrinkKey: 'plan',
      shrinkList: plan,
    );
  }

  /// get_current_context：返回 run 快照（连接名/库/类型/readOnly，与芯片
  /// 一致，AC7.1）；无连接时字段为 null——纯对话可用（AC7.4）。
  Future<_HandlerPayload> _handleGetCurrentContext(
    AgentRunContext runCtx,
  ) async {
    final bool hasConnection =
        runCtx.connectionId != null && runCtx.connectionId!.isNotEmpty;
    return _HandlerPayload(
      data: <String, dynamic>{
        'hasConnection': hasConnection,
        'connectionName': runCtx.connectionName,
        'databaseName': runCtx.databaseName,
        'databaseType': runCtx.dbType.name,
        'readOnly': runCtx.readOnly,
      },
      summary: hasConnection
          ? 'context: ${runCtx.connectionName ?? ''}@'
                '${runCtx.databaseName ?? ''} (${runCtx.dbType.name}'
                '${runCtx.readOnly ? ', read-only' : ''})'
          : 'context: no connection locked',
    );
  }

  // ── L1 计划链（T28，design §6.3 / AC9.x / AC11.4 / AC15.1）──────────────

  /// submit_action_plan 链：提交校验（T22）→ onPlanApproval 阻塞等人（执行
  /// 在装配层回调内完成——见 [AgentPlanApprovalCallback] 注释）→ 按 plan
  /// 终态回喂。提交零执行是结构保证：本链在用户决策返回前不触达任何
  /// execute 通道（AC9.1）；readOnly 连接已在前序门判定序 ③ 拒
  /// （READONLY_CONNECTION，NF2.3）。
  Future<AgentToolOutcome> _runPlanChain({
    required AgentToolCall call,
    required Map<String, dynamic> args,
    required AgentRunContext runCtx,
    required GateCallbacks? gates,
    required GateDecision decision,
    required int stepNo,
    required Stopwatch clock,
  }) async {
    // 参数解析（D4 手写收窄）：steps = 非空数组、元素为对象（元素内字段由
    // AgentPlanStepInput.fromJson 宽容解析，交校验链统一拒绝）。
    final dynamic rawSteps = args['steps'];
    if (rawSteps is! List || rawSteps.isEmpty) {
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: decision.level,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: AgentToolErrorCodes.invalidArguments,
        errorMessage:
            "'steps' must be a non-empty array of plan steps; each step "
            'needs sql plus either rollback_sql or irreversible',
      );
    }
    final List<AgentPlanStepInput> inputs = <AgentPlanStepInput>[
      for (final Object? element in rawSteps)
        if (element is Map<String, dynamic>)
          AgentPlanStepInput.fromJson(element),
    ];
    if (inputs.length != rawSteps.length) {
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: decision.level,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: AgentToolErrorCodes.invalidArguments,
        errorMessage: 'each entry of steps must be a JSON object',
      );
    }

    // 提交校验 + 估算填充（T22 AgentPlanSubmitter：互斥校验 / 单语句 /
    // 三要素 / estimateRows 读前分析管线）。
    final AgentPlanRowsEstimator estimator =
        _planRowsEstimatorOverride ??
        (String sql) => _estimatePlanRowsFromExplain(sql, runCtx);
    final result = await const AgentPlanSubmitter().submit(
      steps: inputs,
      ctx: runCtx,
      estimateRows: estimator,
    );
    final plan = result.plan;
    if (plan == null) {
      // 校验不过 → INVALID_ARGUMENTS 回喂自纠（AC15.1；detail 已含补全指引）。
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: decision.level,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: result.errorCode ?? AgentToolErrorCodes.invalidArguments,
        errorMessage: result.errorMessage ?? 'plan submission was rejected',
      );
    }
    // 此处起 plan 已收窄为非空（本地量类型提升）。

    // fail-closed：无计划卡 UI → 拒绝（绝不静默放行写路径）。
    if (gates == null) {
      return _assemble(
        call: call,
        args: args,
        runCtx: runCtx,
        stepNo: stepNo,
        clock: clock,
        auditLevel: decision.level,
        auditDecision: AgentGateDecision.blocked,
        ok: false,
        errorCode: AgentToolErrorCodes.planRejected,
        errorMessage:
            'a plan approval card was triggered but no approval UI is '
            'available; failing closed without executing anything',
        auditSql: _planAuditSql(plan),
        auditPlanId: plan.planId,
      );
    }

    // 阻塞等人（D7）：runner 包装层落计划卡 + awaitingUser + 停止协同；
    // 装配层（shell）在回调内完成 approve + execute（deps 为 UI 绑定面）。
    GateCardResult card;
    try {
      card = await gates.onPlanApproval(plan);
    } catch (e) {
      // 生产路径由 runner 包装层兜底（rejected）；直调路径防御：
      // 回调异常 = 卡面失败 → fail-closed 拒绝。
      AppLogger.e(
        'AgentToolExecutor',
        'plan approval callback failed, failing closed to rejected',
        e,
      );
      card = GateCardResult.rejected;
    }

    final String planSql = _planAuditSql(plan);
    switch (card) {
      case GateCardResult.rejected:
        // 统计 agentL1Blocked（R14 字段 6，风险 1 撞门观测）。
        _recordL1Blocked();
        return _assemble(
          call: call,
          args: args,
          runCtx: runCtx,
          stepNo: stepNo,
          clock: clock,
          auditLevel: decision.level,
          auditDecision: AgentGateDecision.rejectedByUser,
          ok: false,
          errorCode: AgentToolErrorCodes.planRejected,
          errorMessage:
              'the user rejected this action plan at the L1 approval gate; '
              'nothing was executed and the conversation continues',
          auditSql: planSql,
          auditPlanId: plan.planId,
        );

      case GateCardResult.approvedForSession:
        // L1 会话放行（AC9.3）：账本登记在装配层（决策发起点）；后续同连接
        // 计划免卡仍逐语句审计（AgentPlanExecutor 前后审计对）。
        final feed = _planFeed(plan, 'approved for the session');
        return _assemble(
          call: call,
          args: args,
          runCtx: runCtx,
          stepNo: stepNo,
          clock: clock,
          auditLevel: decision.level,
          auditDecision: AgentGateDecision.allowedSession,
          ok: feed.errorCode == null,
          errorCode: feed.errorCode,
          errorMessage: feed.errorMessage,
          payload: feed.payload,
          auditSql: planSql,
          auditPlanId: plan.planId,
        );

      case GateCardResult.approved:
        final feed = _planFeed(plan, 'approved');
        return _assemble(
          call: call,
          args: args,
          runCtx: runCtx,
          stepNo: stepNo,
          clock: clock,
          auditLevel: decision.level,
          auditDecision: AgentGateDecision.confirmed,
          ok: feed.errorCode == null,
          errorCode: feed.errorCode,
          errorMessage: feed.errorMessage,
          payload: feed.payload,
          auditSql: planSql,
          auditPlanId: plan.planId,
        );
    }
  }

  /// 计划步估算默认实现（读前分析管线同源解析器）：EXPLAIN 估算 → explain；
  /// 取数失败 / 空计划 / 解析不出 / 负值 → unavailable（fail-safe 不猜——
  /// AC9.6 卡上如实标注「估算不可用」）。计数来源（count）保留给 SELECT
  /// 形态的未来扩展，写语句无从计数。
  Future<AgentPlanRowsEstimate> _estimatePlanRowsFromExplain(
    String sql,
    AgentRunContext runCtx,
  ) async {
    try {
      final List<Map<String, dynamic>> rows = await _db.getExplainPlan(
        sql,
        connectionId: runCtx.connectionId,
      );
      if (rows.isEmpty) return const AgentPlanRowsEstimate();
      final planParsed = ExplainParser.parse(
        rawResults: rows,
        databaseType: runCtx.dbType.name,
        originalQuery: sql,
      );
      final int total = planParsed.totalRows;
      if (total < 0) return const AgentPlanRowsEstimate();
      return AgentPlanRowsEstimate(
        rows: total,
        source: AgentRowsEstimateSource.explain,
      );
    } on Object {
      return const AgentPlanRowsEstimate();
    }
  }

  /// 计划回喂组装（风险 6 对策：终局状态对齐模型认知；§4.4 步运行时态为
  /// 数据源）。done → ok 载荷；partialFailed → EXECUTION_FAILED + 首个失败
  /// 步摘要；防御态（回调返回 approved 但 plan 未执行——装配层缺位）→
  /// 明确报「未执行」防模型误报已写入。
  ({_HandlerPayload payload, String? errorCode, String? errorMessage})
  _planFeed(AgentActionPlan plan, String label) {
    final List<Map<String, dynamic>> stepsJson = <Map<String, dynamic>>[
      for (var i = 0; i < plan.steps.length; i++)
        <String, dynamic>{
          'index': i + 1,
          'status': plan.steps[i].runtime.status.name,
          'error': ?plan.steps[i].runtime.error,
        },
    ];
    final Map<String, dynamic> data = <String, dynamic>{
      'plan': <String, dynamic>{
        'planId': plan.planId,
        'status': plan.status.name,
        'steps': stepsJson,
      },
    };
    switch (plan.status) {
      case AgentPlanStatus.done:
        return (
          payload: _HandlerPayload(
            data: data,
            summary:
                'plan ${plan.planId} executed: done '
                '(${plan.steps.length} step(s))',
          ),
          errorCode: null,
          errorMessage: null,
        );
      case AgentPlanStatus.partialFailed:
        final AgentPlanStep failed = plan.steps.firstWhere(
          (AgentPlanStep s) => s.runtime.status == AgentPlanStepStatus.failed,
          orElse: () => plan.steps.first,
        );
        final String message =
            'step failed: ${failed.runtime.error ?? 'unknown error'} '
            '(${plan.completedSteps.length}/${plan.steps.length} steps done; '
            'skipped steps were never executed)';
        return (
          payload: _HandlerPayload(
            data: data,
            summary:
                'plan ${plan.planId} partially failed '
                '(${plan.completedSteps.length}/${plan.steps.length})',
          ),
          errorCode: AgentToolErrorCodes.executionFailed,
          errorMessage: message,
        );
      default:
        // pendingApproval / approved / executing（异步未收敛）/ 终态未执行：
        // 如实报告状态，不给「已写入」信号。
        return (
          payload: _HandlerPayload(
            data: data,
            summary:
                'plan ${plan.planId} not executed '
                '(status: ${plan.status.name})',
          ),
          errorCode: AgentToolErrorCodes.executionFailed,
          errorMessage:
              'the plan was $label but execution did not complete '
              '(status: ${plan.status.name}); nothing further was executed',
        );
    }
  }

  /// 工具级审计 SQL 面：计划全部步语句按序拼接（逐语句审计对在
  /// AgentPlanExecutor 内以单语句落，planId 串联，AC11.2）。
  static String _planAuditSql(AgentActionPlan plan) =>
      plan.steps.map((AgentPlanStep s) => s.sql).join(';\n');

  // ── A2 界面七工具（T28，design §4.5 / §6.6；经 uiPort 派发）────────────

  /// uiPort 缺位守卫（fail-closed）：A2 相位下生产路径恒有端口（start 的
  /// uiPort 必填），null 仅出现于装配缺位——拒绝而非静默空转。
  AgentUiPort _requireUiPort(AgentUiPort? uiPort, String tool) {
    final AgentUiPort? port = uiPort;
    if (port == null) {
      throw _ToolException(
        AgentToolErrorCodes.executionFailed,
        'no UI port is attached to this run; "$tool" cannot dispatch a '
        'workbench action (failing closed)',
      );
    }
    return port;
  }

  /// run 内 result_ref 解析：查不到（跨 run / 幻觉 refId / 非 row 工具产物）
  /// → INVALID_ARGUMENTS 指引自纠（AC15.1）。
  AgentResultRef _requireResultRef(String refId) {
    final AgentResultRef? ref = _resultRefs[refId];
    if (ref == null) {
      throw _ToolException(
        AgentToolErrorCodes.invalidArguments,
        "result_ref '$refId' does not exist in this run; refs live only "
        'inside the run that produced them (format res_<stepNo>) — re-run '
        'the query tool first',
      );
    }
    return ref;
  }

  /// open_result_grid：舞台网格呈现全量行（行限内，§6.6）。
  Future<_HandlerPayload> _handleOpenResultGrid(
    Map<String, dynamic> args,
    AgentUiPort? uiPort,
  ) async {
    final String refId = _requiredStringArg(args, 'result_ref');
    final AgentResultRef ref = _requireResultRef(refId);
    final AgentUiOutcome outcome = await _requireUiPort(
      uiPort,
      'open_result_grid',
    ).openResultGrid(ref, _optionalStringArg(args, 'title'));
    return _uiOutcomePayload(
      outcome,
      okSummary:
          'opened result grid for $refId '
          '(${ref.rowCount} row(s) within the row limit)',
      action: 'open_result_grid',
    );
  }

  /// show_table_structure：舞台结构卡（describe 数据经 port impl 取数）。
  Future<_HandlerPayload> _handleShowTableStructure(
    Map<String, dynamic> args,
    AgentUiPort? uiPort,
  ) async {
    final String table = _requiredStringArg(args, 'table');
    final AgentUiOutcome outcome = await _requireUiPort(
      uiPort,
      'show_table_structure',
    ).showTableStructure(table);
    return _uiOutcomePayload(
      outcome,
      okSummary: 'showed structure of $table in the stage',
      action: 'show_table_structure',
    );
  }

  /// open_sql_editor：舞台编辑器槽载入**不自动执行**（AC5.2；未保存保护在
  /// controller 内单点执法，AC5.5）。
  Future<_HandlerPayload> _handleOpenSqlEditor(
    Map<String, dynamic> args,
    AgentUiPort? uiPort,
  ) async {
    final String sql = _requiredStringArg(args, 'sql');
    final AgentUiOutcome outcome = await _requireUiPort(
      uiPort,
      'open_sql_editor',
    ).openSqlEditor(sql);
    return _uiOutcomePayload(
      outcome,
      okSummary: 'loaded SQL into a stage editor slot (not executed)',
      action: 'open_sql_editor',
    );
  }

  /// render_chart：图表不适配 → outcome 失败回喂自纠（AC5.3/AC15.1）。
  Future<_HandlerPayload> _handleRenderChart(
    Map<String, dynamic> args,
    AgentUiPort? uiPort,
  ) async {
    final String refId = _requiredStringArg(args, 'result_ref');
    final AgentResultRef ref = _requireResultRef(refId);
    final AgentUiOutcome outcome = await _requireUiPort(
      uiPort,
      'render_chart',
    ).renderChart(ref, _optionalStringArg(args, 'chart_kind'));
    return _uiOutcomePayload(
      outcome,
      okSummary: 'rendered chart for $refId',
      action: 'render_chart',
    );
  }

  /// pin_artifact：产物条钉引用（对话推进不丢，AC5.4）。
  Future<_HandlerPayload> _handlePinArtifact(
    Map<String, dynamic> args,
    AgentUiPort? uiPort,
  ) async {
    final String refId = _requiredStringArg(args, 'result_ref');
    final AgentResultRef ref = _requireResultRef(refId);
    final AgentUiOutcome outcome = await _requireUiPort(
      uiPort,
      'pin_artifact',
    ).pinArtifact(ref, _optionalStringArg(args, 'label'));
    return _uiOutcomePayload(
      outcome,
      okSummary: 'pinned $refId to the artifact strip',
      action: 'pin_artifact',
    );
  }

  /// open_in_classic：建议级（R6）——port 落建议卡消息，点击才有副作用
  /// （AC6.1/6.3；审计在用户点击时落，AC6.4）。
  Future<_HandlerPayload> _handleSuggestOpenInClassic(
    Map<String, dynamic> args,
    AgentUiPort? uiPort,
  ) async {
    final String sql = _requiredStringArg(args, 'sql');
    final AgentUiOutcome outcome = await _requireUiPort(
      uiPort,
      'open_in_classic',
    ).suggestOpenInClassic(sql);
    return _uiOutcomePayload(
      outcome,
      okSummary:
          'suggested opening the SQL in the classic editor '
          '(nothing runs until the user clicks)',
      action: 'open_in_classic',
    );
  }

  /// focus_sidebar：建议级（R6）——同上。
  Future<_HandlerPayload> _handleSuggestFocusSidebar(
    Map<String, dynamic> args,
    AgentUiPort? uiPort,
  ) async {
    final AgentUiOutcome outcome = await _requireUiPort(uiPort, 'focus_sidebar')
        .suggestFocusSidebar(
          database: _optionalStringArg(args, 'database'),
          table: _optionalStringArg(args, 'table'),
        );
    return _uiOutcomePayload(
      outcome,
      okSummary:
          'suggested locating the target in the sidebar '
          '(nothing moves until the user clicks)',
      action: 'focus_sidebar',
    );
  }

  /// 界面工具产物：outcome.ok → 成功载荷；失败 → [_PortFailure]（上抛进
  /// _runHandler 的 EXECUTION_FAILED 分支——动作已发起，审计保持门结论，
  /// 与 handler 内拦截的 blocked 区分）。
  _HandlerPayload _uiOutcomePayload(
    AgentUiOutcome outcome, {
    required String okSummary,
    required String action,
  }) {
    if (!outcome.ok) {
      throw _PortFailure(outcome.message ?? '$action failed');
    }
    return _HandlerPayload(
      data: <String, dynamic>{'action': action, 'ui': 'ok'},
      summary: okSummary,
    );
  }

  /// 可选字符串参数（null / 非字符串 / 空白 → null）。
  static String? _optionalStringArg(Map<String, dynamic> args, String key) {
    final dynamic value = args[key];
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  // ── 汇编：步消息 + 审计 + 回喂（链尾，每次 execute 恰走一次）───────────

  Future<AgentToolOutcome> _assemble({
    required AgentToolCall call,
    required Map<String, dynamic> args,
    required AgentRunContext runCtx,
    required int stepNo,
    required Stopwatch clock,
    required AgentGateLevel? auditLevel,
    required AgentGateDecision auditDecision,
    required bool ok,
    String? errorCode,
    String? errorMessage,
    _HandlerPayload? payload,
    String? auditSql,
    String? auditPlanId,
  }) async {
    final int durationMs = clock.elapsedMilliseconds;
    final String summary = _buildSummary(
      ok: ok,
      payload: payload,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );

    // 回喂 JSON（§4.1 + D19 双上限）。
    final _HandlerPayload? p = payload;
    final List<Map<String, dynamic>>? rows = p?.rows;
    final String feed = _buildFeedJson(
      ok: ok,
      data: p?.data,
      errorCode: errorCode,
      errorMessage: errorMessage,
      rowCount: p?.rowCount,
      columns: p?.columns,
      refId: 'res_$stepNo',
      rows: rows,
      shrinkKey: p?.shrinkKey,
      shrinkList: p?.shrinkList,
    );

    // row 形态结果引用（内存不复制，T09 契约）+ run 内注册表登记（T28：
    // 界面工具 result_ref 寻址唯一来源；run 切换整体失效）。
    AgentResultRef? resultRef;
    if (ok && p != null && rows != null) {
      resultRef = AgentResultRef(
        refId: 'res_$stepNo',
        sql: auditSql ?? '',
        rowCount: p.rowCount ?? rows.length,
        columns: p.columns ?? const <String>[],
        rows: rows,
      );
      _resultRefs[resultRef.refId] = resultRef;
    }

    // §5.2 步消息对。
    final DateTime now = DateTime.now();
    final List<Map<String, dynamic>>? rowsForSnapshot = rows;
    final List<Map<String, dynamic>> snapshotRows = rowsForSnapshot == null
        ? const <Map<String, dynamic>>[]
        : rowsForSnapshot
              .take(_messageSnapshotRows)
              .map((Map<String, dynamic> r) => Map<String, dynamic>.of(r))
              .toList();
    final AiMessage callMessage = AiMessage(
      id: 'agent_tc_${runCtx.runId}_$stepNo',
      isUser: false,
      content: '',
      timestamp: now,
      type: AiMessageType.toolCall,
      toolName: call.name,
      toolArguments: Map<String, dynamic>.of(args),
    );
    final Map<String, dynamic> agentPayload = <String, dynamic>{
      'kind': 'agent_step',
      'runId': runCtx.runId,
      'stepNo': stepNo,
      'tool': call.name,
      if (auditLevel != null) 'gateLevel': auditLevel.name,
      'gateDecision': auditDecision.wireName,
      'summary': summary,
      if (resultRef != null)
        'resultRef': <String, dynamic>{
          'rowCount': resultRef.rowCount,
          'columns': resultRef.columns,
          'snapshotRows': snapshotRows,
        },
      'durationMs': durationMs,
      if (!ok && errorCode != null)
        'error': <String, dynamic>{'code': errorCode, 'message': errorMessage},
    };
    final AiMessage resultMessage = AiMessage(
      id: 'agent_tr_${runCtx.runId}_$stepNo',
      isUser: false,
      content: summary,
      timestamp: now,
      type: AiMessageType.toolResult,
      toolName: call.name,
      toolResultSummary: summary,
      toolResultData: <String, dynamic>{'agent': agentPayload},
    );

    // 审计：每次调用至少一条（拦截/人拒也落，AC13.1）；写失败不阻断执行
    //（T07 防抖容错语义，此处兜底同语义）。planId 串联计划链（AC11.2）。
    try {
      await _audit(
        connectionId: runCtx.connectionId ?? '',
        connectionName: runCtx.connectionName,
        databaseName: runCtx.databaseName,
        runId: runCtx.runId,
        step: stepNo,
        tool: call.name,
        sql: auditSql,
        gateLevel: auditLevel,
        gateDecision: auditDecision,
        planId: auditPlanId,
        success: ok,
        errorMessage: ok ? null : errorMessage,
      );
    } catch (e) {
      AppLogger.e(
        'AgentToolExecutor',
        'agent audit record failed (execution continues)',
        e,
      );
    }

    return AgentToolOutcome(
      ok: ok,
      feedJson: feed,
      callMessage: callMessage,
      resultMessage: resultMessage,
      errorCode: errorCode,
      errorMessage: errorMessage,
      resultRef: resultRef,
    );
  }

  // ── 回喂 JSON builder（§4.1 格式 + D19 双上限）─────────────────────────

  /// 三级降级：①行快照 ≤20 + 字符超限时对收缩列表对半减行；②载荷弃置保
  /// 元数据（rowCount/列名保留 + 截断标记）；③病态（元数据本身超限）硬
  /// 截断到 [_llmCharCap]。
  String _buildFeedJson({
    required bool ok,
    Map<String, dynamic>? data,
    String? errorCode,
    String? errorMessage,
    int? rowCount,
    List<String>? columns,
    String? refId,
    List<Map<String, dynamic>>? rows,
    String? shrinkKey,
    List<Object>? shrinkList,
  }) {
    int kept = rows != null
        ? math.min(rows.length, _llmRowSnapshotCap)
        : (shrinkList?.length ?? 0);
    bool truncated = rows != null && rows.length > kept;

    while (true) {
      final String encoded = jsonEncode(
        _feedMap(
          ok: ok,
          data: data,
          errorCode: errorCode,
          errorMessage: errorMessage,
          rowCount: rowCount,
          columns: columns,
          truncated: truncated,
          refId: refId,
          rows: rows,
          shrinkKey: shrinkKey,
          shrinkList: shrinkList,
          kept: kept,
        ),
      );
      if (encoded.length <= _llmCharCap) return encoded;
      if (shrinkList != null && kept > 0) {
        truncated = true;
        kept = kept ~/ 2;
        continue;
      }
      // 载荷弃置：保 ok/error/rowCount/列名 + 截断标记。
      final String fallback = jsonEncode(
        _feedMap(
          ok: ok,
          data: <String, dynamic>{
            'note': 'result payload omitted: exceeded $_llmCharCap characters',
          },
          errorCode: errorCode,
          errorMessage: errorMessage,
          rowCount: rowCount,
          columns: columns,
          truncated: true,
          refId: refId,
          rows: null,
          shrinkKey: null,
          shrinkList: null,
          kept: 0,
        ),
      );
      if (fallback.length <= _llmCharCap) return fallback;
      return fallback.substring(0, _llmCharCap);
    }
  }

  Map<String, dynamic> _feedMap({
    required bool ok,
    required Map<String, dynamic>? data,
    required String? errorCode,
    required String? errorMessage,
    required int? rowCount,
    required List<String>? columns,
    required bool truncated,
    required String? refId,
    required List<Map<String, dynamic>>? rows,
    required String? shrinkKey,
    required List<Object>? shrinkList,
    required int kept,
  }) {
    final Map<String, dynamic> dataCopy = data == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.of(data);
    if (refId != null && rows != null) dataCopy['result_ref'] = refId;
    if (shrinkList != null && shrinkKey != null) {
      dataCopy[shrinkKey] = kept <= 0
          ? const <Object>[]
          : shrinkList.take(kept).toList();
    }
    return <String, dynamic>{
      'ok': ok,
      if (!ok && errorCode != null)
        'error': <String, dynamic>{'code': errorCode, 'message': errorMessage},
      if (dataCopy.isNotEmpty) 'data': dataCopy,
      'rowCount': ?rowCount,
      'columns': ?columns,
      if (truncated) 'truncated': true,
    };
  }

  // ── 私有辅助 ────────────────────────────────────────────────────────────

  /// LLM 参数 JSON 解析：非 JSON 对象（含畸形文本 / 数组 / null）→ null。
  Map<String, dynamic>? _parseArguments(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// 必填字符串参数（D4 手写收窄：类型不符 / 空 → INVALID_ARGUMENTS）。
  String _requiredStringArg(Map<String, dynamic> args, String key) {
    final dynamic value = args[key];
    if (value is String && value.trim().isNotEmpty) return value;
    throw _ToolException(
      AgentToolErrorCodes.invalidArguments,
      "argument '$key' must be a non-empty string",
    );
  }

  /// 校验器拒绝 → 错误分类（需带被拒语句）：写语句首关键字 →
  /// WRITE_REJECTED_READONLY_CHANNEL + 计划路径指引（AC4.2，D5）；其余 →
  /// INVALID_ARGUMENTS（校验器 reason）。
  _ToolException _rejectByValidator(String sql, String? reason) {
    if (_isWriteStatement(sql)) {
      return _ToolException(
        AgentToolErrorCodes.writeRejectedReadonlyChannel,
        'only read-only SQL is allowed on this channel; write statements '
        'require submit_action_plan',
      );
    }
    return _ToolException(
      AgentToolErrorCodes.invalidArguments,
      reason ?? 'statement rejected by the read-only SQL gate',
    );
  }

  // ── AC4.4 库级限定名执法（P2-4 并入 T28；Fix-G 方言扩面 M5 + 掩码防御）──
  //
  // 规则：限定名首段 ≠ 锁定 databaseName 且方言上限定符首段语义为「库」→
  // INVALID_ARGUMENTS 拒 + 指引回锁定库。**方言分立最小段数判定（M5，T29
  // 真库实证钉住 SS3P/CH2P 穿透）**：
  // - MySQL 协议族 + ClickHouse（[_databaseQualifierDialects]）：
  //   `db.table`（≥2 段）首段 = 库 → 执法；CH 两段式首段 = 库（与 PG 两段式
  //   = schema 的语义分立由 dbType 门保证）；
  // - SQL Server：仅三段式 `db.schema.table`（≥3 段）首段 = 库 → 执法；
  //   两段式 `dbo.t` = schema 库内寻址（与 PG 同语义）→ 放行；
  // - PostgreSQL：两段式 `schema.table` 是库内合法寻址（非跨库）→ 不拦；
  //   三段式跨库在 PG 单连接上本就不可达 → 不拦（不可达 = 无越界面）；
  // - SQLite：ATTACH 跨库面**不覆盖**（本地文件库方言边界，登记不改判）；
  // - NoSQL：SQL 文本类工具已被链序 ④ 预拦截，执法不可达。
  // 语句面扫描前先掩码字面量与注释（[maskSqlLiteralsAndComments]，引界
  // 标识符保持可见——否则 `` `db`.t `` 形态被掩码吞掉形成逃逸洞），注释
  // 混淆（`FROM/*c*/otherdb.t`、`FROM otherdb /*c*/ . t`）与字面量内假
  // 表名（不误伤）同源消解。databaseName == null（快照未锁库）→ 无比较
  // 基准不拦（快照语义一致）；比较大小写不敏感（SQL 标识符惯例）。
  // 写通道（submit_action_plan 步 SQL）**不扩**本执法（M5 明示：计划卡
  // 逐语句全文人审即同意门）。

  /// 两段式限定符 `db.table` 首段语义 = 库的方言（MySQL 协议族 +
  /// ClickHouse——M5 真库实证 CH2P 探针 `system.one` 穿透后扩入）。
  static const Set<DatabaseType> _databaseQualifierDialects = <DatabaseType>{
    DatabaseType.mysql,
    DatabaseType.doris,
    DatabaseType.oceanbase,
    DatabaseType.tidb,
    DatabaseType.starrocks,
    DatabaseType.mariadb,
    DatabaseType.clickhouse,
  };

  /// 本方言是否存在任一库级限定名执法形态（MySQL 族 + CH 两段式 / SS
  /// 三段式）。不在集内（PG / SQLite / NoSQL 等）→ 执法整体不生效。
  static bool _hasEnforcement(DatabaseType dbType) =>
      _databaseQualifierDialects.contains(dbType) ||
      dbType == DatabaseType.sqlserver;

  /// 限定名首段是否按「库」语义执法（M5 方言分立最小段数判定）：MySQL 族
  /// + CH → ≥2 段即执法；SS → 仅 ≥3 段（`db.schema.table`）执法，两段式
  /// `dbo.t` = schema 库内寻址放行；其余方言不执法。
  static bool _firstSegmentIsDatabaseQualifier(
    DatabaseType dbType,
    int segmentCount,
  ) {
    if (segmentCount < 2) return false;
    if (_databaseQualifierDialects.contains(dbType)) return true;
    if (dbType == DatabaseType.sqlserver) return segmentCount >= 3;
    return false;
  }

  /// 表位置限定名扫描（FROM / JOIN / INTO / UPDATE / DESCRIBE / DESC 后的
  /// 首个限定标识符，2~3 段；支持反引号 / 双引号 / 方括号引界与段间空白）。
  /// 保守正则：只扫表位置首段，函数调用 / 列限定（`t.col`）不在这些关键字
  /// 后，不误伤；ORDER BY 尾部的 DESC 后无限定标识符形态，不误伤。
  static final RegExp _tablePositionPattern = RegExp(
    r'\b(?:FROM|JOIN|INTO|UPDATE|DESCRIBE|DESC)\s+'
    r'((?:[`"\[]?)[A-Za-z0-9_]+(?:[`"\]]?)'
    r'(?:\s*\.\s*(?:[`"\[]?)[A-Za-z0-9_]+(?:[`"\]]?)){1,2})',
    caseSensitive: false,
  );

  /// SHOW 语句的 FROM|IN 段（`SHOW TABLES FROM db` / `SHOW COLUMNS FROM t
  /// FROM db`——取语句内**最后一个**匹配：双段形态后者才是库位）。捕获段
  /// 可带限定（`FROM otherdb.t` → 首段为库）。
  static final RegExp _showFromInPattern = RegExp(
    r'\b(?:FROM|IN)\s+((?:[`"\[]?)[A-Za-z0-9_]+(?:[`"\]]?)'
    r'(?:\s*\.\s*(?:[`"\[]?)[A-Za-z0-9_]+(?:[`"\]]?))?)',
    caseSensitive: false,
  );

  /// `SHOW CREATE TABLE <qualified>` 的限定名位（无 FROM|IN 段的 SHOW
  /// 形态；单段 = 锁定库内表，不执法）。
  static final RegExp _showCreateTablePattern = RegExp(
    r'\bSHOW\s+CREATE\s+TABLE\s+((?:[`"\[]?)[A-Za-z0-9_]+(?:[`"\]]?)'
    r'(?:\s*\.\s*(?:[`"\[]?)[A-Za-z0-9_]+(?:[`"\]]?)){1,2})',
    caseSensitive: false,
  );

  /// 限定名切段（段间空白裁剪；段内引界由 [_stripQuotes] 在比对时剥离）。
  /// 段字符类不含点号，split('.') 不会切进引界内容。
  static List<String> _splitQualified(String name) => name
      .split('.')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  /// 库名直比（SHOW FROM|IN 库位段 / 限定名首段共用）：≠ 锁定库 → 拒绝文案。
  static String? _databaseNameProblem(String database, String locked) {
    final String name = _stripQuotes(database);
    if (name.isEmpty || name.toLowerCase() == locked.toLowerCase()) {
      return null;
    }
    return _crossDatabaseMessage(name, locked);
  }

  /// 限定名判定：段数与方言达执法形态（[_firstSegmentIsDatabaseQualifier]）
  /// 且首段 ≠ 锁定库 → 拒绝文案。
  static String? _qualifiedNameProblem(
    List<String> segments,
    DatabaseType dbType,
    String locked,
  ) {
    if (!_firstSegmentIsDatabaseQualifier(dbType, segments.length)) {
      return null;
    }
    return _databaseNameProblem(segments.first, locked);
  }

  /// get_sample_data / describe_table 的 table 参数执法（限定名首段比对，
  /// 段数规则按方言：MySQL 族 + CH ≥2 段、SS ≥3 段）。
  String? _crossDatabaseTableArgProblem(String table, AgentRunContext runCtx) {
    final String? locked = _lockedDatabaseOrNull(runCtx);
    if (locked == null) return null;
    if (!_hasEnforcement(runCtx.dbType)) return null;
    return _qualifiedNameProblem(_splitQualified(table), runCtx.dbType, locked);
  }

  /// execute_readonly_sql / explain_plan 语句执法：先掩码字面量与注释
  ///（[maskSqlLiteralsAndComments]，maskQuotedIdentifiers: false——引界
  /// 标识符保持可见参与比对），再扫表位置限定名首段。扫描面（Fix-G）：
  /// [_tablePositionPattern]（FROM / JOIN / INTO / UPDATE / DESCRIBE /
  /// DESC）+ SHOW 语句库位段（[_showFromInPattern] 取最后一个 FROM|IN 段
  /// ——`SHOW TABLES FROM db` 单段即库名直比；`SHOW COLUMNS FROM t FROM
  /// db` 双段取后者；[_showCreateTablePattern] 覆盖 `SHOW CREATE TABLE
  /// db.t`）。
  String? _crossDatabaseSqlProblem(String sql, AgentRunContext runCtx) {
    final String? locked = _lockedDatabaseOrNull(runCtx);
    if (locked == null) return null;
    if (!_hasEnforcement(runCtx.dbType)) return null;
    final String masked = maskSqlLiteralsAndComments(
      sql,
      maskQuotedIdentifiers: false,
    );
    for (final RegExpMatch match in _tablePositionPattern.allMatches(masked)) {
      final String? problem = _qualifiedNameProblem(
        _splitQualified(match.group(1)!),
        runCtx.dbType,
        locked,
      );
      if (problem != null) return problem;
    }
    if (RegExp(r'^\s*SHOW\b', caseSensitive: false).hasMatch(masked)) {
      final List<RegExpMatch> fromIn = _showFromInPattern
          .allMatches(masked)
          .toList();
      if (fromIn.isNotEmpty) {
        final List<String> segments = _splitQualified(fromIn.last.group(1)!);
        // FROM|IN 库位段：单段 = 库名直比；多段 = 限定名走段数规则。
        final String? problem = segments.length <= 1
            ? _databaseNameProblem(
                segments.isEmpty ? '' : segments.single,
                locked,
              )
            : _qualifiedNameProblem(segments, runCtx.dbType, locked);
        if (problem != null) return problem;
      }
      final RegExpMatch? createTable = _showCreateTablePattern.firstMatch(
        masked,
      );
      if (createTable != null) {
        final String? problem = _qualifiedNameProblem(
          _splitQualified(createTable.group(1)!),
          runCtx.dbType,
          locked,
        );
        if (problem != null) return problem;
      }
    }
    return null;
  }

  static String? _lockedDatabaseOrNull(AgentRunContext runCtx) {
    final String? locked = runCtx.databaseName;
    return (locked == null || locked.isEmpty) ? null : locked;
  }

  static String _crossDatabaseMessage(String foreign, String locked) =>
      "cross-database reference '$foreign.*' is outside this run's locked "
      'database "$locked"; qualify objects within the locked database only '
      '(AC4.4 scope lock)';

  /// 标识符去引界（`a` / "a" / [a] 段内引界）。
  static String _stripQuotes(String identifier) {
    String result = identifier.trim();
    while (result.length >= 2 &&
        ((result.startsWith('`') && result.endsWith('`')) ||
            (result.startsWith('"') && result.endsWith('"')) ||
            (result.startsWith('[') && result.endsWith(']')))) {
      result = result.substring(1, result.length - 1);
    }
    return result;
  }

  /// 语句是否写形态（首关键字白名单，集合注释见 [_writeStatementPrefixes]）。
  bool _isWriteStatement(String sql) {
    final RegExpMatch? match = RegExp(r'^[A-Za-z]+').firstMatch(sql.trim());
    final String? word = match?.group(0);
    return word != null && _writeStatementPrefixes.contains(word.toUpperCase());
  }

  /// get_sample_data LIMIT 归一化（与 agent_gate.dart `_sampleLimit` 同逻辑
  /// 同值：宽容 num / 数字字符串——LLM 参数经 JSON 往返；clamp 1-100 默认
  /// 10，解析不出用默认）。
  int _normalizeSampleLimit(Map<String, dynamic> args) {
    final dynamic raw = args['limit'];
    int? limit;
    if (raw is int) {
      limit = raw;
    } else if (raw is num) {
      limit = raw.toInt();
    } else if (raw is String) {
      limit = int.tryParse(raw.trim());
    }
    if (limit == null) return _sampleLimitDefault;
    if (limit < _sampleLimitMin) return _sampleLimitMin;
    if (limit > _sampleLimitMax) return _sampleLimitMax;
    return limit;
  }

  /// 确认卡 / 审计取 SQL 面（与 gate `_analysisSqlFor` 同形——两侧需同步）：
  /// execute_readonly_sql 取原文；get_sample_data 构造同形 SELECT（table 的
  /// 标识符白名单校验在 handler 执行前——本方法构造的语句仅入卡面/审计，
  /// 不执行）。
  String? _gateCardSql(AgentToolSpec spec, Map<String, dynamic> args) {
    switch (spec.name) {
      case 'execute_readonly_sql':
        final dynamic sql = args['sql'];
        return sql is String && sql.trim().isNotEmpty ? sql : null;
      case 'get_sample_data':
        final dynamic table = args['table'];
        if (table is String && table.trim().isNotEmpty) {
          return 'SELECT * FROM ${table.trim()} LIMIT '
              '${_normalizeSampleLimit(args)}';
        }
        return null;
      default:
        return null;
    }
  }

  /// 审计 SQL：数据类工具才有（execute_readonly_sql 原文 / get_sample_data
  /// 构造语句 / explain_plan 目标语句）；其余 null（§4.7 语义）。
  String? _auditSqlFor(AgentToolSpec spec, Map<String, dynamic> args) {
    if (spec.name == 'explain_plan') {
      final dynamic sql = args['sql'];
      return sql is String && sql.trim().isNotEmpty ? sql : null;
    }
    return _gateCardSql(spec, args);
  }

  /// row 形态 handler 产物（列名取首行键序；空结果列名为空表）。
  _HandlerPayload _rowPayload({
    required String sql,
    required List<Map<String, dynamic>> rows,
    required String summary,
  }) {
    return _HandlerPayload(
      data: const <String, dynamic>{},
      summary: summary,
      auditSql: sql,
      rows: rows,
      rowCount: rows.length,
      columns: rows.isEmpty
          ? const <String>[]
          : rows.first.keys.toList(growable: false),
      shrinkKey: 'rows',
      shrinkList: rows,
    );
  }

  /// 一行摘要（`toolResultSummary` 兜底文本；技术英文——services 层无
  /// BuildContext，l10n 化由 UI 批次承接，任务书自决项）。
  String _buildSummary({
    required bool ok,
    _HandlerPayload? payload,
    String? errorCode,
    String? errorMessage,
  }) {
    final String raw = ok
        ? (payload?.summary ?? 'ok')
        : (errorCode == null ? 'failed' : '$errorCode: ${errorMessage ?? ''}');
    if (raw.length <= _summaryMaxChars) return raw;
    return '${raw.substring(0, _summaryMaxChars)}…';
  }
}

/// handler 内部产物（成功路径）：data 载荷 + 摘要 + row/收缩元数据。
class _HandlerPayload {
  const _HandlerPayload({
    required this.data,
    required this.summary,
    this.auditSql,
    this.rows,
    this.rowCount,
    this.columns,
    this.shrinkKey,
    this.shrinkList,
  });

  /// 成功载荷（row 形态时 rows 由 builder 注入 data['rows']）。
  final Map<String, dynamic> data;

  /// 一行摘要（步消息 + toolResultSummary）。
  final String summary;

  /// 产生结果的语句（审计 + resultRef.sql）。
  final String? auditSql;

  /// row 形态结果（resultRef / D19 行快照 / 顶层 rowCount+columns）。
  final List<Map<String, dynamic>>? rows;

  /// 结果总行数（row 形态）。
  final int? rowCount;

  /// 结果列名（row 形态）。
  final List<String>? columns;

  /// D19 字符超限时收缩的 data 键（rows / tables / plan）。
  final String? shrinkKey;

  /// 与 [shrinkKey] 对应的收缩列表。
  final List<Object>? shrinkList;
}

/// handler 内部工具错误（静态码 + 模型可读 detail；不改跨模块错误语义，
/// 仅 executor 内部传输）。
class _ToolException implements Exception {
  const _ToolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// 界面派发失败（AgentUiOutcome.failure 的传输形态）：上抛进 _runHandler
/// 的 EXECUTION_FAILED 分支——动作已发起且失败（区别于 handler 内拦截的
/// blocked），detail 即 port 侧自纠指引（AC15.1 通路）。
class _PortFailure implements Exception {
  const _PortFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
