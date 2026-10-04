/// 行动计划：模型 + 提交校验 + 状态机 + 执行器 + 补偿回退 + 防重
/// （tasks-ai-agent.md T22 / design-ai-agent.md §4.4、§6.3、§7）。
///
/// §7 多步写等效保障（无事务连接）的全部载体——四条铁律：
/// 1. **幂等防重**（AC11.4）：planId 唯一（`plan_<ts>_<seq>`）；终态计划
///    （done / partialFailed / rolledBack / rejected）再次执行 →
///    `PLAN_ALREADY_EXECUTED`，零库操作；重复触发结果可预期；
/// 2. **失败边界**（AC11.1）：第 k 步失败即停，runtime 三段更新
///    （1..k-1 done / k failed+error / k+1..n skipped），计划翻
///    `partialFailed`；
/// 3. **回退过门**（AC11.3）：回退计划组装**永不自动执行**——只产出一个
///    `pendingApproval` 新计划，走同一 L1 批准门 + DDL 逆语句逐次双门；
/// 4. **全程审计**（AC11.2）：每步执行前后各落一条 `recordAgentEvent`
///    （planId + step 序号串联），失败步、DDL 人拒与回退动作同样落。
///
/// 执行底座 = T20 [SqlStatementGateRunner]（`none` 写确认模式：计划卡批准
/// 即写授权，不逐句弹写确认；每步一次 run 调用 = 天然严格串行，失败即停
/// 由本执行器在步边界实现）。
///
/// **消费接口说明（T23 计划卡 / T28 接线层）**
/// - 状态观察面：[AgentActionPlan.status] + [AgentActionPlan.isConsumed] +
///   [AgentPlanStep.runtime]（pending/running/done/failed/skipped + error）
///   ——plan 是就地可变值对象，卡每次收到
///   [AgentPlanExecutionDeps.onStepStateChange] 回调后重读 plan 全量即可
///   （partialFailed 三段 = steps[].runtime 派生；consumed 提示 =
///   isConsumed；回退计划标识 = rollbackOfPlanId）。未用 ChangeNotifier：
///   services 层纯 Dart，回调即通知。
/// - M6 标注观察面：[AgentPlanStep.dmlRiskTier] + `dmlRiskTriggers`（提交
///   期静态标注，提交后只读）——计划卡 high 步「需显式确认」徽标 +
///   triggers 摘要的数据源；执行期 high 标注步冒 DML warning 经
///   [AgentPlanExecutionDeps.executeBypassDml] 重执行（批准即覆盖）。
/// - executor 装配形态：`AgentPlanExecutor()`（默认绑
///   `AuditLogService().recordAgentEvent`；统计注入点见
///   [AgentPlanStatsRecorder] 桥接说明）；执行环境（execute/bypass/确认
///   回调）逐次经 [AgentPlanExecutionDeps] 注入——同一 executor 实例可
///   服务多个计划。
/// - ddlConfirm 注入：沿 `insertConfirmationCallback` 先例（§6 计划期发现
///   #3）独立注入于 [AgentPlanExecutionDeps.ddlConfirm]（shell 绑
///   DdlConfirmDialog，签名 = T20 `SqlDdlConfirmCallback`，confirmed /
///   cancelled / aborted 三态），不经 GateCallbacks；dmlConfirm 同理
///   （DROP TABLE 等管线 critical 形态走 DmlConfirmDialog，附录 2 修订）。
///
/// 本文件不 import material / Flutter widgets（组件级 §0 MUST NOT 2）；
/// 公共 API 显式类型；审计写失败不阻断执行路径（T07 容错语义）。
library;

import '../../../models/audit_log_entry.dart' show AgentGateDecision;
import '../../../models/database_models.dart' show DatabaseType;
import '../../../models/dml_risk_models.dart'
    show
        DmlRiskLevel,
        DmlWarningRequiredException,
        RiskAnalysisResult,
        RiskTrigger;
import '../../../models/sql_statement.dart' show SQLStatement, SQLType;
import '../../../utils/app_logger.dart' show AppLogger;
import '../../../utils/secret_redactor.dart' show redactSecrets;
import '../../audit_log_service.dart' show AuditLogService;
import '../../dml_safety_service.dart' show DmlSafetyService;
import '../../sql_parser_service.dart' show ParseException, SQLParserService;
import '../../sql_statement_gate_runner.dart'
    show
        SqlBatchStatus,
        SqlDdlConfirmCallback,
        SqlDmlConfirmCallback,
        SqlExecuteCallback,
        SqlGateRunDeps,
        SqlStatementBatchResult,
        SqlStatementGateRunner,
        SqlStatementResult,
        SqlStatementStatus,
        SqlWriteConfirmStrategy;
import 'agent_gate.dart' show AgentRunContext;
import 'agent_tool_catalog.dart' show AgentGateLevel, AgentToolErrorCodes;
import 'agent_tool_executor.dart' show AgentAuditRecorder;

/// 语句类别（design §4.4：dml | ddl）。非 DDL 一律 dml——SELECT 等读语句
/// 不是计划形态（提交指引问题，非执行风险面；写授权在门与确认链）。
enum AgentPlanStepKind { dml, ddl }

/// 影响行估算来源（AC9.6，卡上标注）：EXPLAIN 估算 | 计数 | 估算不可用。
enum AgentRowsEstimateSource { explain, count, unavailable }

/// 回滚来源（§7 两路）：模型提供 | 执行器机械推导。
enum AgentRollbackSource { model, auto }

/// DML 风险档（M6，design 附录 2「计划通道 DmlWarning 形态」选③）：
/// 提交期由 [AgentPlanSubmitter] 逐步跑 `DmlSafetyService.analyze` 纯静态
/// 确定性分析标注（与执行期 `checkDmlSafety` 同源输入——同一 split 产物 +
/// 同一 analyze，`query_execution_interceptor.dart`；静态 ⇒ 提交期标注与
/// 执行期 `DmlWarningRequiredException` 判定构造性一致）。
///
/// - [none]：静态分析未见 high（含 normal 与 critical——critical 仍走
///   DmlConfirmDialog 模态双门，不经本通道）；
/// - [high]：静态分析判 high——计划卡「需显式确认的步」（批准前可见 +
///   标注，批准即覆盖）；执行期 warning 异常经既有 `executeBypassDml`
///   通道重执行标 done（经典同通道：非阻断横幅 + 继续 = bypass）。
enum AgentPlanDmlRiskTier { none, high }

/// 逐语句运行时状态值（§4.4；ui 规格 §9-A1 缺口修订）。
enum AgentPlanStepStatus { pending, running, done, failed, skipped }

/// 逐语句运行时状态（就地可变——执行器逐段写入）。
class AgentPlanStepRuntime {
  AgentPlanStepRuntime({AgentPlanStepStatus? status, this.error})
    : status = status ?? AgentPlanStepStatus.pending;

  /// 当前状态。
  AgentPlanStepStatus status;

  /// failed 时的错误摘要（已过 `redactSecrets` 脱敏）。
  String? error;
}

/// 计划状态机（§4.4 九值 + consumed 标记）。
///
/// 流转：`pendingApproval → approved|rejected`；`approved → executing →
/// done|partialFailed`；`partialFailed → rollbackOffered → rolledBack`。
/// 终态 = done / partialFailed / rolledBack / rejected（[isTerminal]）——
/// 终态计划 = consumed（[AgentActionPlan.isConsumed] 标记，防重 AC11.4；
/// status 保留终态值供卡呈现「终态 + consumed 提示」，不翻 consumed 值，
/// `consumed` 枚举值保留给宿主聚合呈现用——执行器不设置）。
enum AgentPlanStatus {
  pendingApproval,
  approved,
  executing,
  done,
  partialFailed,
  rollbackOffered,
  rolledBack,
  rejected,
  consumed,
}

/// 计划单步（§4.4 字段原文；sql/kind/估算/回滚为提交期定形，runtime 可变）。
class AgentPlanStep {
  AgentPlanStep({
    required this.sql,
    required this.kind,
    this.estimatedRows,
    this.estimatedRowsSource = AgentRowsEstimateSource.unavailable,
    this.rollbackSql,
    this.rollbackSource,
    this.irreversible = false,
    this.note,
    this.dmlRiskTier = AgentPlanDmlRiskTier.none,
    this.dmlRiskTriggers = const <String>[],
  }) : runtime = AgentPlanStepRuntime() {
    // §4.4 构造不变式（提交校验保证；程序化构造侧自查）：
    // rollbackSql 非空 ⇒ rollbackSource 必填；rollbackSql 与 irreversible
    // 互斥；estimatedRows == null ⇔ source == unavailable。
    assert(
      rollbackSql == null || rollbackSource != null,
      'rollbackSource is required when rollbackSql is provided',
    );
    assert(
      !(rollbackSql != null && irreversible),
      'rollbackSql and irreversible are mutually exclusive',
    );
    assert(
      (estimatedRows == null) ==
          (estimatedRowsSource == AgentRowsEstimateSource.unavailable),
      'estimatedRows is null iff estimatedRowsSource == unavailable',
    );
  }

  /// 单语句（提交校验保证；AC15.4 可辨识）。
  final String sql;

  /// 语句类别。
  final AgentPlanStepKind kind;

  /// 影响估算（提交处理时由读前分析管线填充，非模型输入）。
  final int? estimatedRows;

  /// 估算依据（AC9.6）。
  final AgentRowsEstimateSource estimatedRowsSource;

  /// 模型提供的逆语句；null ⇔ irreversible == true（提交互斥校验保证）。
  final String? rollbackSql;

  /// 回滚来源（§7 两路）：rollbackSql != null 时必填。
  final AgentRollbackSource? rollbackSource;

  /// 显式不可逆声明（与 rollbackSql 互斥）。
  final bool irreversible;

  /// 模型备注。
  final String? note;

  /// DML 风险档（M6 提交期静态标注；计划卡 high 步「需显式确认」徽标与
  /// 执行期 warning→bypass 重执行的判据）。
  final AgentPlanDmlRiskTier dmlRiskTier;

  /// high 档触发器名摘要（`RiskTrigger.name` 技术串，卡上 triggers 行
  /// 数据源；none 档恒空——沿经典横幅 `t.name` 直排先例，不入 l10n）。
  final List<String> dmlRiskTriggers;

  /// 逐语句运行时状态（执行器唯一写入方；不进提交 schema）。
  final AgentPlanStepRuntime runtime;
}

/// 行动计划（§4.4；多步写等效保障的载体，就地可变值对象）。
class AgentActionPlan {
  AgentActionPlan({
    required this.planId,
    required this.runId,
    required this.ctx,
    required this.steps,
    this.status = AgentPlanStatus.pendingApproval,
    this.rollbackOfPlanId,
    this.isConsumed = false,
  });

  /// `'plan_<ts>_<seq>'` 防重主键（AC11.4；[AgentPlanIds.next] 生成）。
  final String planId;

  /// 所属 agent run（= ctx.runId；冗余字段按 §4.4 原文保留）。
  final String runId;

  /// run 启动快照（D15，全程只读）。
  final AgentRunContext ctx;

  /// 有序步骤（提交校验保证非空、逐条单语句）。
  final List<AgentPlanStep> steps;

  /// 计划状态（[AgentPlanExecutor] 唯一写入方）。
  AgentPlanStatus status;

  /// 回退计划标识：本计划是 `rollbackOfPlanId` 所指计划的补偿回退计划
  /// （null = 常规计划；T23 卡头「回退计划标识」数据源）。
  final String? rollbackOfPlanId;

  /// 终态防重标记（AC11.4）：终态计划被重复触发后置位；卡据此呈现
  /// consumed 提示并隐藏动作行。status 保留终态值不翻转。
  bool isConsumed;

  /// 终态判定（§7：done / partialFailed / rolledBack = 终态；rejected
  /// 从未执行、同样不可再执行；consumed 为宿主聚合态）。
  static bool isTerminalStatus(AgentPlanStatus status) =>
      status == AgentPlanStatus.done ||
      status == AgentPlanStatus.partialFailed ||
      status == AgentPlanStatus.rolledBack ||
      status == AgentPlanStatus.rejected ||
      status == AgentPlanStatus.consumed;

  /// 本计划是否已处终态。
  bool get isTerminal => isTerminalStatus(status);

  /// 已完成步（runtime == done；回退组装的输入面）。
  List<AgentPlanStep> get completedSteps => steps
      .where((AgentPlanStep s) => s.runtime.status == AgentPlanStepStatus.done)
      .toList(growable: false);
}

/// planId 生成器（`plan_<ts>_<seq>`；序列生成细节 = 任务书自决项）。
///
/// ts = 毫秒时间戳、seq = 进程内单调递增序号——同毫秒多次提交也不重号；
/// 测试经注入工厂（[AgentPlanSubmitter.submit] / [AgentPlanRollbackDeps]
/// 的 planIdFactory）替换。
class AgentPlanIds {
  const AgentPlanIds._();

  static int _sequence = 0;

  /// 生成下一个 planId。
  static String next() {
    _sequence += 1;
    return 'plan_${DateTime.now().millisecondsSinceEpoch}_$_sequence';
  }

  /// 测试专用：复位序号。
  static void resetForTesting() => _sequence = 0;
}

/// 提交期单步原始输入（submit_action_plan 的 steps[] 元素形态，§4.1）。
class AgentPlanStepInput {
  const AgentPlanStepInput({
    required this.sql,
    this.rollbackSql,
    this.irreversible = false,
    this.note,
  });

  /// 目标语句（模型文本；单语句约束在校验链判定）。
  final String sql;

  /// 模型提供的逆语句（空串视为未提供）。
  final String? rollbackSql;

  /// 显式不可逆声明（仅 true 视为声明）。
  final bool irreversible;

  /// 模型备注。
  final String? note;

  /// LLM 参数宽容解析（类型不符 → 空值形态，交校验链统一拒绝；
  /// D4 手写收窄同源——解析不做静默修正）。
  factory AgentPlanStepInput.fromJson(Map<String, dynamic> json) {
    final dynamic sql = json['sql'];
    final dynamic rollback = json['rollback_sql'];
    final dynamic irreversible = json['irreversible'];
    final dynamic note = json['note'];
    return AgentPlanStepInput(
      sql: sql is String ? sql : '',
      rollbackSql: rollback is String && rollback.trim().isNotEmpty
          ? rollback.trim()
          : null,
      irreversible: irreversible is bool && irreversible,
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
    );
  }
}

/// 单步影响估算产物（提交处理时逐步填充）。
class AgentPlanRowsEstimate {
  const AgentPlanRowsEstimate({
    this.rows,
    this.source = AgentRowsEstimateSource.unavailable,
  });

  /// 估算行数（null = 不可用；source 将被归一为 unavailable）。
  final int? rows;

  /// 估算来源。
  final AgentRowsEstimateSource source;
}

/// 影响估算函数（生产装配由 T28 绑读前分析管线：EXPLAIN 估算 →
/// explain / 计数查询 → count / 不可用 → unavailable；缺省恒 unavailable）。
typedef AgentPlanRowsEstimator =
    Future<AgentPlanRowsEstimate> Function(String sql);

/// 提交结果：校验过 → plan（pendingApproval，估算已填充）；不过 → 错误码
/// + 指引模型自纠的 detail（AC15.1 回喂通路）。
class AgentPlanSubmitResult {
  const AgentPlanSubmitResult({this.plan, this.errorCode, this.errorMessage});

  /// 校验通过并完成估算填充的计划；失败为 null。
  final AgentActionPlan? plan;

  /// 失败错误码（当前恒 INVALID_ARGUMENTS）；成功为 null。
  final String? errorCode;

  /// 模型可读失败明细（英文，指引补全）；成功为 null。
  final String? errorMessage;

  /// 是否成功。
  bool get ok => plan != null;
}

/// 提交处理（校验 + 估算填充 + 组装；§4.4 提交校验 / AC9.5/9.6/15.1）。
///
/// 校验链（首错即拒，全部 INVALID_ARGUMENTS 回喂自纠）：
/// ① steps 非空；② 每步 sql 非空；③ 每步 sql 经 `SQLParserService.split`
/// 恰为一条可执行语句（AC15.4；畸形 SQL 拒——不整块回退，F1 同源）；
/// ④ rollbackSql 非空时同样恰为一条语句（回退步将来要成为可执行步）；
/// ⑤ 每步 rollbackSql 与 irreversible **二选一**——两者同给（自相矛盾）
/// 同拒，缺 rollback 未声明不可逆拒（detail 指引补全，§9-A4 二义消解）。
/// 三要素（改什么 = sql / 影响多少行 = 估算+来源 / 回滚方案 = rollbackSql
/// 或显式不可逆）齐备 + 估算填充完成 → `pendingApproval`。
class AgentPlanSubmitter {
  const AgentPlanSubmitter();

  /// 处理一次计划提交。
  Future<AgentPlanSubmitResult> submit({
    required List<AgentPlanStepInput> steps,
    required AgentRunContext ctx,
    AgentPlanRowsEstimator? estimateRows,
    String Function()? planIdFactory,
  }) async {
    // ① steps 非空。
    if (steps.isEmpty) {
      return const AgentPlanSubmitResult(
        errorCode: AgentToolErrorCodes.invalidArguments,
        errorMessage:
            "'steps' must be a non-empty array of plan steps; each step "
            'needs sql plus either rollback_sql or irreversible',
      );
    }

    final List<AgentPlanStep> assembled = <AgentPlanStep>[];
    for (var i = 0; i < steps.length; i++) {
      final AgentPlanStepInput input = steps[i];
      final int no = i + 1;

      // ② sql 非空。
      final String sql = input.sql.trim();
      if (sql.isEmpty) {
        return AgentPlanSubmitResult(
          errorCode: AgentToolErrorCodes.invalidArguments,
          errorMessage: "steps[$no].sql must be a non-empty SQL statement",
        );
      }

      // ③ 单语句（畸形/多语句均拒；拆分为空 = 无可执行语句，同拒）。
      final String? splitError = _singleStatementProblem(sql);
      if (splitError != null) {
        return AgentPlanSubmitResult(
          errorCode: AgentToolErrorCodes.invalidArguments,
          errorMessage: 'steps[$no].sql $splitError',
        );
      }

      // ④ rollbackSql 非空时同样单语句。
      final String? rollbackSql = input.rollbackSql?.trim();
      final bool hasRollback = rollbackSql != null && rollbackSql.isNotEmpty;
      if (hasRollback) {
        final String? rollbackProblem = _singleStatementProblem(rollbackSql);
        if (rollbackProblem != null) {
          return AgentPlanSubmitResult(
            errorCode: AgentToolErrorCodes.invalidArguments,
            errorMessage: 'steps[$no].rollback_sql $rollbackProblem',
          );
        }
      }

      // ⑤ rollbackSql 与 irreversible 二选一（§4.4 互斥校验）。
      final bool declaredIrreversible = input.irreversible;
      if (hasRollback && declaredIrreversible) {
        return AgentPlanSubmitResult(
          errorCode: AgentToolErrorCodes.invalidArguments,
          errorMessage:
              'steps[$no] provides both rollback_sql and '
              'irreversible=true; provide exactly one of them (they are '
              'mutually exclusive)',
        );
      }
      if (!hasRollback && !declaredIrreversible) {
        return AgentPlanSubmitResult(
          errorCode: AgentToolErrorCodes.invalidArguments,
          errorMessage:
              'steps[$no] has neither rollback_sql nor irreversible=true; '
              'provide a rollback statement for the step, or explicitly '
              'declare it irreversible',
        );
      }

      // 估算填充（读前分析管线注入；缺省 unavailable）。
      final AgentPlanRowsEstimate estimate = await _estimateFor(
        estimateRows,
        sql,
      );

      // M6 标注（估算填充同挂点）：逐步跑 DmlSafetyService.analyze 纯静态
      // 确定性分析——与执行期 checkDmlSafety 同源输入（同一 split + 同一
      // analyze），提交期标注与执行期 warning 判定构造性一致。
      final ({AgentPlanDmlRiskTier tier, List<String> triggers}) dml =
          assessDmlRiskTier(sql, ctx.dbType);

      assembled.add(
        AgentPlanStep(
          sql: sql,
          kind: _classifyKind(sql),
          estimatedRows: estimate.rows,
          estimatedRowsSource: estimate.source,
          rollbackSql: hasRollback ? rollbackSql : null,
          rollbackSource: hasRollback ? AgentRollbackSource.model : null,
          irreversible: declaredIrreversible,
          note: input.note,
          dmlRiskTier: dml.tier,
          dmlRiskTriggers: dml.triggers,
        ),
      );
    }

    return AgentPlanSubmitResult(
      plan: AgentActionPlan(
        planId: (planIdFactory ?? AgentPlanIds.next)(),
        runId: ctx.runId,
        ctx: ctx,
        steps: List<AgentPlanStep>.unmodifiable(assembled),
      ),
    );
  }

  /// 单语句判定：null = 恰一条可执行语句；否则返回问题描述片段。
  static String? _singleStatementProblem(String sql) {
    final List<String> statements = _splitStatements(sql);
    if (statements.isEmpty) {
      return 'contains no executable statement';
    }
    if (statements.length > 1) {
      return 'must contain exactly one SQL statement; split it into separate '
          'plan steps';
    }
    return null;
  }

  /// 拆分并过滤空语句（ParseException = 畸形，不可作为计划步——F1）。
  static List<String> _splitStatements(String sql) {
    try {
      return SQLParserService.split(sql)
          .map((s) => s.sql.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } on ParseException {
      return const <String>[];
    }
  }

  /// 估算归一：管线返回 rows == null / 负值时 source 强制 unavailable
  ///（§4.4 不变式 estimatedRows == null ⇔ source == unavailable）。
  static Future<AgentPlanRowsEstimate> _estimateFor(
    AgentPlanRowsEstimator? estimator,
    String sql,
  ) async {
    if (estimator == null) {
      return const AgentPlanRowsEstimate();
    }
    final AgentPlanRowsEstimate raw = await estimator(sql);
    if (raw.rows == null || raw.rows! < 0) {
      return const AgentPlanRowsEstimate();
    }
    return raw;
  }

  /// 语句类别（复用 SQLParserService.detectType：SQLType.ddl → ddl，
  /// 其余 → dml）。
  static AgentPlanStepKind _classifyKind(String sql) {
    return SQLParserService.detectType(sql) == SQLType.ddl
        ? AgentPlanStepKind.ddl
        : AgentPlanStepKind.dml;
  }

  /// M6 静态分析器（无状态共享实例；与执行期 `checkDmlSafety` 同源服务
  /// ——`QueryExecutionInterceptor` 持有的同款 `DmlSafetyService`）。
  static final DmlSafetyService _dmlSafety = DmlSafetyService();

  /// DML 风险档静态标注（M6）：`SQLParserService.split` →
  /// `DmlSafetyService.analyze`——与执行期 `checkDmlSafety` 逐点同源的
  /// 确定性输入（`query_execution_interceptor.dart` DML 检查段：唯一输入
  /// 即 analyze 产物）。仅 high 档标注（`DmlWarningRequiredException` 的
  /// 唯一静态来源）；critical 不标注（仍走 DmlConfirmDialog 模态双门）。
  /// analyze 自身是同步纯函数（无连接上下文、无开关面）——提交期标注
  /// 永不阻断，执行期是否真抛 warning 由管线开关决定，标注仅作知情与
  /// bypass 判据，fail-safe。split 畸形（校验链已先拒，此防御不可达）
  /// → none 不标注。triggers 为空但命中注入面时补 `sqlInjection` 名
  /// （analyze 的注入升档不进 triggers 列表，卡上摘要需可辨）。
  static ({AgentPlanDmlRiskTier tier, List<String> triggers})
  assessDmlRiskTier(String sql, DatabaseType dbType) {
    const ({AgentPlanDmlRiskTier tier, List<String> triggers}) unmarked = (
      tier: AgentPlanDmlRiskTier.none,
      triggers: <String>[],
    );
    final List<SQLStatement> statements;
    try {
      statements = SQLParserService.split(sql)
          .where((SQLStatement s) => s.sql.trim().isNotEmpty)
          .toList(growable: false);
    } on ParseException {
      return unmarked;
    }
    if (statements.isEmpty) return unmarked;
    final RiskAnalysisResult analysis = _dmlSafety.analyze(
      statements,
      dbType,
    );
    if (analysis.riskLevel != DmlRiskLevel.high) return unmarked;
    final List<String> triggers = <String>[
      for (final RiskTrigger trigger in analysis.triggers) trigger.name,
    ];
    if (triggers.isEmpty && analysis.hasInjectionPattern) {
      triggers.add(RiskTrigger.sqlInjection.name);
    }
    return (tier: AgentPlanDmlRiskTier.high, triggers: triggers);
  }
}

/// 计划事件统计分桶（值 = design §4.7 recordPlanEvent 的
/// shown/approved/rejected）。
///
/// **桥接说明**：`WorkbenchUsageStatsService.recordPlanEvent(AgentPlanStat)`
/// 按 T08 的有意延后归 T28 落地（该服务注释「recordPlanEvent/recordL1Blocked
/// 归 A2 T28」与统计测试「字段 4/6 归 T28 后为 14 键」均为此证）；届时
/// `AgentPlanStat` 枚举定义在统计服务文件内（其 imports 白名单纪律），
/// 装配层按 name 桥接（`AgentPlanStat.values.byName(e.name)`），两处枚举
/// 值需同步（评审对照项）。
enum AgentPlanStatEvent { shown, approved, rejected }

/// 计划事件计数函数类型（T28 落统计方法后由装配层注入桥接）。
typedef AgentPlanStatsRecorder = void Function(AgentPlanStatEvent event);

/// 回退组装依赖：describe 取 PK（注入函数）+ 估算 + planId 工厂 + 通知。
class AgentPlanRollbackDeps {
  const AgentPlanRollbackDeps({
    this.primaryKeyColumns,
    this.estimateRows,
    this.planIdFactory,
    this.onStateChange,
  });

  /// 读表主键列名（生产绑 describe → getTableColumns → isPrimaryKey 投影；
  /// 缺位 = 一律视为无 PK → INSERT 形态不自动生成回退，fail-safe）。
  final Future<List<String>> Function(String table)? primaryKeyColumns;

  /// 回退步影响估算（缺省 unavailable）。
  final AgentPlanRowsEstimator? estimateRows;

  /// 新计划 planId 工厂（缺省 [AgentPlanIds.next]）。
  final String Function()? planIdFactory;

  /// 原计划翻 rollbackOffered 时的状态通知（卡刷新）。
  final void Function(AgentActionPlan plan)? onStateChange;
}

/// 执行环境依赖：执行通道 + 确认回调 + 状态通知（逐次执行注入）。
class AgentPlanExecutionDeps {
  const AgentPlanExecutionDeps({
    required this.execute,
    this.executeBypassDdl,
    this.executeBypassDml,
    this.ddlConfirm,
    this.dmlConfirm,
    this.shouldContinue,
    this.onStepStateChange,
  });

  /// 语句执行入口（必填；绑 `AppProvider.executeQueryDetailed` facade
  /// 投影——readOnly 检查、DML 拦截、DDL 双门、行限、网关路由全部继承；
  /// 返回 [SqlStatementOutcome]（裁决选项 A 回调型扩宽）。
  final SqlExecuteCallback execute;

  /// DDL 确认后的 bypass 执行（双门第二道；缺位时确认后 fail-closed 中止）。
  final SqlExecuteCallback? executeBypassDdl;

  /// DML 确认后的 bypass 执行（DROP TABLE 等管线 critical 形态）。
  final SqlExecuteCallback? executeBypassDml;

  /// DDL 双门确认回调（shell 绑 DdlConfirmDialog；沿
  /// insertConfirmationCallback 独立注入先例——§6 计划期发现 #3，不经
  /// GateCallbacks）。缺位 fail-closed 视同取消。
  final SqlDdlConfirmCallback? ddlConfirm;

  /// DML 门确认回调（shell 绑 DmlConfirmDialog）。
  final SqlDmlConfirmCallback? dmlConfirm;

  /// 每语句执行前探针（false → 中止边界：本步起余下全 skipped；绑
  /// context.mounted / 停止态）。
  final bool Function()? shouldContinue;

  /// 状态变化通知（步 runtime 或计划 status 任一变化后回调；卡刷新唯一
  /// 通道——重读 plan 全量）。
  final void Function(AgentActionPlan plan)? onStepStateChange;
}

/// 执行终局。
class AgentPlanExecutionResult {
  const AgentPlanExecutionResult({
    required this.plan,
    required this.ok,
    this.errorCode,
    this.errorMessage,
  });

  /// 计划引用（终局状态就地可读）。
  final AgentActionPlan plan;

  /// 全部步成功 = true；失败边界 / 防重拒绝 = false。
  final bool ok;

  /// 失败错误码（PLAN_ALREADY_EXECUTED / 步失败 EXECUTION_FAILED）。
  final String? errorCode;

  /// 失败明细（已脱敏）。
  final String? errorMessage;
}

/// 计划执行器（§6.3 批准后逐语句段 / §7 等效保障）。
///
/// 决策与执行入口（卡片动作 → T28 接线层调用）：
/// - [approve] / [reject]：pendingApproval → approved / rejected（统计 +
///   审计 + 通知；重复决策幂等忽略——「重复触发结果可预期」）；
/// - [execute]：approved → executing → done / partialFailed（严格串行逐
///   语句 + 前后审计 + 失败边界三段 + 防重）；
/// - [buildRollbackPlan]：失败边界 → 组装逆序补偿新计划（永不自动执行）；
/// - [markRolledBack]：回退计划执行成功后原计划 rollbackOffered →
///   rolledBack；
/// - [markConsumed]：终态重放标记（execute 防重路径自动调用）。
class AgentPlanExecutor {
  AgentPlanExecutor({
    SqlStatementGateRunner? runner,
    AgentAuditRecorder? audit,
    AgentPlanStatsRecorder? recordPlanEvent,
  }) : _runner = runner ?? const SqlStatementGateRunner(),
       _audit = audit ?? AuditLogService().recordAgentEvent,
       _recordPlanEvent = recordPlanEvent;

  /// 计划语句审计的 tool 名（计划产自 submit_action_plan 工具调用）。
  static const String _planAuditTool = 'submit_action_plan';

  /// 计划级决策事件的 step 占位（无对应语句；语句步用 0 基序号）。
  static const int _planLevelAuditStep = -1;

  final SqlStatementGateRunner _runner;
  final AgentAuditRecorder _audit;
  final AgentPlanStatsRecorder? _recordPlanEvent;

  // ── 决策入口（卡动作）────────────────────────────────────────────────────

  /// 批准计划：pendingApproval → approved。
  ///
  /// 统计 approved + 审计一条（planId / step=-1 / confirmed / success=true）。
  /// 非 pendingApproval（已决策/已执行）→ 幂等忽略返回 false。
  Future<bool> approve(
    AgentActionPlan plan, {
    void Function(AgentActionPlan plan)? onStateChange,
  }) async {
    if (plan.status != AgentPlanStatus.pendingApproval) return false;
    plan.status = AgentPlanStatus.approved;
    _recordPlanEvent?.call(AgentPlanStatEvent.approved);
    await _auditQuietly(
      plan: plan,
      step: _planLevelAuditStep,
      sql: null,
      gateDecision: AgentGateDecision.confirmed,
      success: true,
      errorMessage: null,
    );
    onStateChange?.call(plan);
    return true;
  }

  /// 拒绝计划：pendingApproval → rejected（零执行，AC9.2）。
  ///
  /// 统计 rejected + 审计一条（人拒也落，AC13.1——被拒计划必须在审计链上
  /// 留痕，否则从审计视角消失）。非 pendingApproval → 幂等忽略返回 false。
  Future<bool> reject(
    AgentActionPlan plan, {
    void Function(AgentActionPlan plan)? onStateChange,
  }) async {
    if (plan.status != AgentPlanStatus.pendingApproval) return false;
    plan.status = AgentPlanStatus.rejected;
    plan.isConsumed = true;
    _recordPlanEvent?.call(AgentPlanStatEvent.rejected);
    await _auditQuietly(
      plan: plan,
      step: _planLevelAuditStep,
      sql: null,
      gateDecision: AgentGateDecision.rejectedByUser,
      success: false,
      errorMessage: 'plan rejected by the user at the L1 approval gate',
    );
    onStateChange?.call(plan);
    return true;
  }

  // ── 执行入口（AC11.1 失败边界 / AC11.2 审计链 / AC11.4 防重）───────────

  /// 执行已批准计划：严格串行逐语句，第 k 步失败即停。
  ///
  /// 入口防重：status 非 approved → 结构化拒绝——executing / 终态 →
  /// `PLAN_ALREADY_EXECUTED` + [AgentActionPlan.isConsumed] 置位 + 零库
  /// 操作（AC11.4，重复触发可预期）；pendingApproval → fail-loud
  /// `StateError`（未经批准触达执行器是接线层结构缺陷，沿 agent_gate /
  /// executor 的不变量守卫先例，不静默吞）。
  Future<AgentPlanExecutionResult> execute({
    required AgentActionPlan plan,
    required AgentPlanExecutionDeps deps,
  }) async {
    if (plan.status == AgentPlanStatus.pendingApproval) {
      throw StateError(
        'AgentPlanExecutor: plan ${plan.planId} is still pendingApproval; '
        'call approve() before execute() (plan execution requires explicit '
        'user approval, AC9.1)',
      );
    }
    if (plan.status != AgentPlanStatus.approved) {
      // 防重（AC11.4）：executing / 终态 / consumed 一律拒绝，幂等可预期。
      plan.isConsumed = true;
      deps.onStepStateChange?.call(plan);
      return AgentPlanExecutionResult(
        plan: plan,
        ok: false,
        errorCode: AgentToolErrorCodes.planAlreadyExecuted,
        errorMessage:
            'plan ${plan.planId} has already been through the approval and '
            'execution flow (status: ${plan.status.name}); submit a new plan '
            'for further changes',
      );
    }

    plan.status = AgentPlanStatus.executing;
    for (final AgentPlanStep step in plan.steps) {
      step.runtime
        ..status = AgentPlanStepStatus.pending
        ..error = null;
    }
    deps.onStepStateChange?.call(plan);

    for (var i = 0; i < plan.steps.length; i++) {
      final AgentPlanStep step = plan.steps[i];

      // shouldContinue 探针（false → 中止边界：本步起余下全 skipped，
      // 本步未启动不标 failed）。
      final bool Function()? mayContinue = deps.shouldContinue;
      if (mayContinue != null && !mayContinue()) {
        _skipRemainder(plan, i);
        plan.status = AgentPlanStatus.partialFailed;
        AppLogger.d(
          'AgentPlanExecutor',
          'plan ${plan.planId} aborted before step ${i + 1}',
        );
        deps.onStepStateChange?.call(plan);
        return _failedResult(plan, 'execution aborted before step ${i + 1}');
      }

      step.runtime.status = AgentPlanStepStatus.running;
      deps.onStepStateChange?.call(plan);

      // 前置审计（dispatch 记录：成对首条——审计链按
      // (planId, step, timestamp) 还原顺序，AC11.2）。
      await _auditQuietly(
        plan: plan,
        step: i,
        sql: step.sql,
        gateDecision: AgentGateDecision.na,
        success: true,
        errorMessage: null,
      );

      // 单语句一次 run（halt 语义由本执行器在步边界实现；none 写确认 =
      // 计划批准即写授权，A2 计划语义）。
      final SqlStatementBatchResult batch = await _runner.run(
        sql: step.sql,
        deps: SqlGateRunDeps(
          execute: deps.execute,
          writeConfirm: const SqlWriteConfirmStrategy.none(),
          ddlConfirm: deps.ddlConfirm,
          dmlConfirm: deps.dmlConfirm,
          executeBypassDdl: deps.executeBypassDdl,
          executeBypassDml: deps.executeBypassDml,
          haltOnStatementFailure: false,
          shouldContinue: null,
        ),
      );

      if (batch.results.isEmpty) {
        // 未进入执行段（拆分失败 / 空输入防御边界）。
        final String reason =
            'statement did not run (batch status: ${batch.status.name})';
        await _recordFailure(plan, i, deps, reason, AgentGateDecision.blocked);
        return _failedResult(plan, 'step ${i + 1} did not run: $reason');
      }
      final SqlStatementResult outcome = batch.results.first;
      switch (outcome.status) {
        case SqlStatementStatus.done:
          step.runtime
            ..status = AgentPlanStepStatus.done
            ..error = null;
          await _auditQuietly(
            plan: plan,
            step: i,
            sql: step.sql,
            gateDecision: AgentGateDecision.na,
            success: true,
            errorMessage: null,
          );
          deps.onStepStateChange?.call(plan);

        case SqlStatementStatus.failed:
          // M6 选③（high 档 = 计划卡「需显式确认的步」，批准即覆盖）：步
          // 已标注 high 且执行期冒 DmlWarningRequiredException → 经既有
          // deps.executeBypassDml 重执行标 done（经典同通道：非阻断横幅 +
          // 继续 = bypass）；未标注冒 warning（构造性不可达的漂移，fail-
          // closed 保持 failed）；bypass 通道缺位同样 fail-closed。
          final Object? failure = outcome.error;
          final SqlExecuteCallback? bypassDml = deps.executeBypassDml;
          if (failure is DmlWarningRequiredException &&
              step.dmlRiskTier == AgentPlanDmlRiskTier.high &&
              bypassDml != null) {
            final Object? retryError = await _retryMarkedHighStep(
              step,
              bypassDml,
            );
            if (retryError == null) {
              // 重执行成功：审计 confirmed（批准即对 high 步的显式确认）。
              await _auditQuietly(
                plan: plan,
                step: i,
                sql: step.sql,
                gateDecision: AgentGateDecision.confirmed,
                success: true,
                errorMessage: null,
              );
              deps.onStepStateChange?.call(plan);
              break;
            }
            // bypass 重执行失败 = 普通步失败（reason 取重执行错误原文）。
            final String reason = redactSecrets(retryError.toString());
            await _recordFailure(plan, i, deps, reason, AgentGateDecision.na);
            return _failedResult(
              plan,
              'step ${i + 1} failed: ${step.runtime.error}',
            );
          }
          final String reason = redactSecrets(outcome.error.toString());
          await _recordFailure(plan, i, deps, reason, AgentGateDecision.na);
          return _failedResult(
            plan,
            'step ${i + 1} failed: ${step.runtime.error}',
          );

        case SqlStatementStatus.skipped:
          // 批级中止面：DDL/DML 双门人拒 / abort / fail-closed（单语句批
          // 中 skipped 仅出现于这些形态——语句未执行，边界呈现为失败步）。
          final String reason;
          final AgentGateDecision decision;
          switch (batch.status) {
            case SqlBatchStatus.ddlCancelled:
              reason = 'DDL confirmation was cancelled by the user';
              decision = AgentGateDecision.rejectedByUser;
            case SqlBatchStatus.dmlCancelled:
              reason = 'DML confirmation was cancelled by the user';
              decision = AgentGateDecision.rejectedByUser;
            case SqlBatchStatus.aborted:
              reason =
                  'confirmation was aborted (fail-closed before execution)';
              decision = AgentGateDecision.blocked;
            default:
              reason = 'statement did not run (${batch.status.name})';
              decision = AgentGateDecision.blocked;
          }
          await _recordFailure(plan, i, deps, reason, decision);
          return _failedResult(plan, 'step ${i + 1} did not run: $reason');
      }
    }

    plan.status = AgentPlanStatus.done;
    deps.onStepStateChange?.call(plan);
    return AgentPlanExecutionResult(plan: plan, ok: true);
  }

  /// M6 high 标注步的 bypass 重执行：成功 → 步标 done 返回 null；失败 →
  /// 返回错误原文（步保持 running，调用方走失败臂）。bypass 语义 = 经典
  /// 「非阻断横幅 + 继续」的 `executeQueryBypassDml` 同通道——计划批准即
  /// 对 high 步的显式确认（批准前卡上逐 high 步可见 + 标注，M6 选③）。
  Future<Object?> _retryMarkedHighStep(
    AgentPlanStep step,
    SqlExecuteCallback bypass,
  ) async {
    try {
      await bypass(step.sql);
    } on Object catch (e) {
      return e;
    }
    step.runtime
      ..status = AgentPlanStepStatus.done
      ..error = null;
    return null;
  }

  /// 步失败边界：第 k 步 failed(+error) + k+1..n skipped + 计划
  /// partialFailed（AC11.1 三段）+ 结局审计（AC11.2 失败步同样落）。
  Future<void> _recordFailure(
    AgentActionPlan plan,
    int index,
    AgentPlanExecutionDeps deps,
    String reason,
    AgentGateDecision decision,
  ) async {
    final AgentPlanStep step = plan.steps[index];
    step.runtime
      ..status = AgentPlanStepStatus.failed
      ..error = reason;
    _skipRemainder(plan, index + 1);
    plan.status = AgentPlanStatus.partialFailed;
    await _auditQuietly(
      plan: plan,
      step: index,
      sql: step.sql,
      gateDecision: decision,
      success: false,
      errorMessage: reason,
    );
    deps.onStepStateChange?.call(plan);
  }

  static void _skipRemainder(AgentActionPlan plan, int from) {
    for (var i = from; i < plan.steps.length; i++) {
      plan.steps[i].runtime
        ..status = AgentPlanStepStatus.skipped
        ..error = null;
    }
  }

  static AgentPlanExecutionResult _failedResult(
    AgentActionPlan plan,
    String message,
  ) {
    return AgentPlanExecutionResult(
      plan: plan,
      ok: false,
      errorCode: AgentToolErrorCodes.executionFailed,
      errorMessage: message,
    );
  }

  // ── 回退组装（AC11.3：永不自动执行——结构保证）─────────────────────────

  /// 组装补偿回退计划：completed 步逆序 → 新计划（pendingApproval，走同一
  /// L1 门）。**只组装不执行**——执行需宿主对新计划再走 approve → execute。
  ///
  /// 逆语句来源两路（模型优先，§7）：① 原步 rollbackSql（模型提供）；
  /// ② 机械推导（自决授权锁定两形态）：INSERT → `DELETE ... WHERE pk`
  /// （describe 有 PK 才生成——[AgentPlanRollbackDeps.primaryKeyColumns]
  /// 缺位 / 无 PK / 插入列不含全 PK / VALUES 非字面量 → 不生成）；
  /// CREATE TABLE/VIEW/INDEX/TRIGGER → `DROP <TYPE> <name>`。两路皆无
  /// （模型未提供且形态外——UPDATE/DELETE/ALTER 等不可机械反演）→ 该步
  /// 不进回退计划（卡上声明，§7）。机械可推导形态**即使原步声明
  /// irreversible 也可推导**（irreversible 是「模型给不出」的声明，
  /// §7 的执行器推导是独立兜底路）。
  ///
  /// 组装产物非空 → 原计划 partialFailed → rollbackOffered；无可回退步 →
  /// 返回 null（原状态不变）。非 partialFailed / rollbackOffered（重
  /// 组装）→ 返回 null。
  Future<AgentActionPlan?> buildRollbackPlan({
    required AgentActionPlan plan,
    required AgentPlanRollbackDeps deps,
  }) async {
    if (plan.status != AgentPlanStatus.partialFailed &&
        plan.status != AgentPlanStatus.rollbackOffered) {
      return null;
    }

    final List<AgentPlanStep> rollbackSteps = <AgentPlanStep>[];
    final List<AgentPlanStep> doneSteps = plan.completedSteps.reversed.toList();
    for (final AgentPlanStep step in doneSteps) {
      final int originalIndex = plan.steps.indexOf(step);

      // ① 模型 rollbackSql 优先；② 机械推导（irreversible 不阻断——见类
      //    注释）。两路皆无 → 跳过（卡上声明）。
      String? inverse = step.rollbackSql;
      inverse ??= await _deriveAutoInverse(step.sql, deps);
      if (inverse == null) continue;

      final AgentPlanRowsEstimate estimate =
          await AgentPlanSubmitter._estimateFor(deps.estimateRows, inverse);
      // M6：回退步同走静态标注（逆语句 DELETE 无 LIMIT / 模型逆语句等同样
      // 可命中 high——回退计划与常规计划同一批准门、同一执行器，标注判据
      // 与执行期 warning→bypass 形态保持一致）。
      final ({AgentPlanDmlRiskTier tier, List<String> triggers}) dml =
          AgentPlanSubmitter.assessDmlRiskTier(inverse, plan.ctx.dbType);
      rollbackSteps.add(
        AgentPlanStep(
          sql: inverse,
          kind: AgentPlanSubmitter._classifyKind(inverse),
          estimatedRows: estimate.rows,
          estimatedRowsSource: estimate.source,
          // 逆的逆 = 原语句（回退计划再被反悔时的补偿；原文出自模型）。
          rollbackSql: step.sql,
          rollbackSource: AgentRollbackSource.model,
          note: 'rollback of ${plan.planId} step $originalIndex',
          dmlRiskTier: dml.tier,
          dmlRiskTriggers: dml.triggers,
        ),
      );
    }
    if (rollbackSteps.isEmpty) return null;

    final AgentActionPlan rollbackPlan = AgentActionPlan(
      planId: (deps.planIdFactory ?? AgentPlanIds.next)(),
      runId: plan.runId,
      ctx: plan.ctx,
      steps: List<AgentPlanStep>.unmodifiable(rollbackSteps),
      rollbackOfPlanId: plan.planId,
    );
    if (plan.status == AgentPlanStatus.partialFailed) {
      plan.status = AgentPlanStatus.rollbackOffered;
      deps.onStateChange?.call(plan);
    }
    // Fix-F ③ 回退血缘审计（组装成功落一条计划级事件，step=-1）：planId
    // 记新回退计划、errorMessage 携带 `rb_of_<原 planId>` 血缘标记——审计
    // 链据此把该 planId 后续的批准/逐步记录识别为「回退补偿」而非「新发
    // 起」（审计写失败不阻断组装，沿本类既有容错语义）。组装零执行不变
    // （AC11.3：只产出 pendingApproval 新计划，执行须再走批准门）。
    await _auditQuietly(
      plan: rollbackPlan,
      step: _planLevelAuditStep,
      sql: null,
      gateDecision: AgentGateDecision.na,
      success: true,
      errorMessage: 'rollback plan assembled (rb_of_${plan.planId})',
    );
    return rollbackPlan;
  }

  /// 回退计划执行成功后：原计划 rollbackOffered → rolledBack（§7 流转；
  /// 由接线层在回退计划 execute 返回 ok 后调用）。
  bool markRolledBack(
    AgentActionPlan plan, {
    void Function(AgentActionPlan plan)? onStateChange,
  }) {
    if (plan.status != AgentPlanStatus.rollbackOffered) return false;
    plan.status = AgentPlanStatus.rolledBack;
    plan.isConsumed = true;
    onStateChange?.call(plan);
    return true;
  }

  /// 终态重放标记（AC11.4「卡上再点」路径；execute 防重分支自动调用，
  /// 宿主亦可显式标记）。非终态 → 忽略返回 false。
  bool markConsumed(
    AgentActionPlan plan, {
    void Function(AgentActionPlan plan)? onStateChange,
  }) {
    if (!plan.isTerminal) return false;
    plan.isConsumed = true;
    onStateChange?.call(plan);
    return true;
  }

  // ── 审计（AC11.2：写失败不阻断执行路径）────────────────────────────────

  Future<void> _auditQuietly({
    required AgentActionPlan plan,
    required int step,
    required String? sql,
    required AgentGateDecision gateDecision,
    required bool success,
    required String? errorMessage,
  }) async {
    try {
      await _audit(
        connectionId: plan.ctx.connectionId ?? '',
        connectionName: plan.ctx.connectionName,
        databaseName: plan.ctx.databaseName,
        runId: plan.runId,
        step: step,
        tool: _planAuditTool,
        sql: sql,
        gateLevel: AgentGateLevel.l1,
        gateDecision: gateDecision,
        planId: plan.planId,
        success: success,
        errorMessage: errorMessage,
      );
    } catch (e) {
      AppLogger.e(
        'AgentPlanExecutor',
        'agent plan audit record failed (execution continues)',
        e,
      );
    }
  }

  // ── 机械推导（自决授权：INSERT / CREATE 两形态锁定）───────────────────

  /// 自动逆语句推导。可推导形态之外（UPDATE/DELETE/ALTER 等、INSERT 无 PK
  /// 或非字面量 VALUES、CREATE 形态外对象）→ null（不自动生成）。
  Future<String?> _deriveAutoInverse(
    String sql,
    AgentPlanRollbackDeps deps,
  ) async {
    final String? createInverse = _deriveCreateDrop(sql);
    if (createInverse != null) return createInverse;
    return _deriveInsertDelete(sql, deps);
  }

  static final RegExp _createPattern = RegExp(
    r'^\s*CREATE\s+(?:OR\s+REPLACE\s+)?(?:TEMP(?:ORARY)?\s+)?(?:UNIQUE\s+)?'
    r'(TABLE|VIEW|INDEX|TRIGGER)\s+(?:IF\s+NOT\s+EXISTS\s+)?([^\s(]+)',
    caseSensitive: false,
  );

  /// CREATE TABLE/VIEW/INDEX/TRIGGER → `DROP <TYPE> <name>`（锁定形态，
  /// 其余 CREATE 对象不推导；对象名按原文保留引界）。
  static String? _deriveCreateDrop(String sql) {
    final RegExpMatch? match = _createPattern.firstMatch(sql);
    if (match == null) return null;
    final String objectType = match.group(1)!.toUpperCase();
    final String objectName = match.group(2)!;
    if (objectName.isEmpty) return null;
    return 'DROP $objectType $objectName';
  }

  static final RegExp _insertPattern = RegExp(
    r'^\s*INSERT\s+(?:IGNORE\s+)?INTO\s+([^\s(]+)\s*(?:\(([^)]*)\)\s*)?'
    r'VALUES\s*(.+?)\s*;?\s*$',
    caseSensitive: false,
    dotAll: true,
  );

  /// INSERT → `DELETE FROM <table> WHERE (pk = v [AND ...]) [OR ...]`。
  ///
  /// 锁定形态：单表 + **显式**列清单 + **全字面量** VALUES（数字 / 单引号
  /// 字符串（'' 转义）/ NULL）；多行元组按行生成 OR 组合。隐式列清单
  /// （无法核对 PK 是否被赋值）、PK 缺失、插入列不含全部 PK、任何非字面量
  /// （函数 / 占位符 / DEFAULT / 子查询）→ null（不自动生成，fail-safe）。
  /// 表名与 WHERE 列名按原语句写法保留（含引界与限定前缀）。
  static Future<String?> _deriveInsertDelete(
    String sql,
    AgentPlanRollbackDeps deps,
  ) async {
    final RegExpMatch? match = _insertPattern.firstMatch(sql);
    if (match == null) return null;
    final String table = match.group(1)!;
    final String? columnsPart = match.group(2);
    final String valuesPart = match.group(3)!;

    final List<String>? pkColumns = await _readPrimaryKeyColumns(deps, table);
    if (pkColumns == null || pkColumns.isEmpty) return null;

    // 显式列清单（缺省/空 = 隐式全列 → 无法核对 PK 赋值，不推导）。
    if (columnsPart == null || columnsPart.trim().isEmpty) return null;
    final List<String> rawColumns = columnsPart
        .split(',')
        .map((String c) => c.trim())
        .where((String c) => c.isNotEmpty)
        .toList(growable: false);
    final List<String> plainColumns = rawColumns
        .map(_stripIdentifierQuotes)
        .toList(growable: false);

    // PK 列必须全部在插入列中（少一列即无法定位行）。
    final List<int> pkIndexes = <int>[];
    for (final String pk in pkColumns) {
      final int index = plainColumns.indexOf(pk);
      if (index < 0) return null;
      pkIndexes.add(index);
    }

    // VALUES 元组拆解（顶层括号组；组间只许逗号与空白）。
    final List<List<String>>? tuples = _splitValueTuples(valuesPart);
    if (tuples == null) return null;

    final List<String> rowPredicates = <String>[];
    for (final List<String> tuple in tuples) {
      if (tuple.length != rawColumns.length) return null;
      final List<String> predicates = <String>[];
      for (final int pkIndex in pkIndexes) {
        final String? literal = _normalizeValueLiteral(tuple[pkIndex]);
        if (literal == null) return null; // 非字面量 → 整体不推导
        predicates.add(
          literal == 'NULL'
              ? '${rawColumns[pkIndex]} IS NULL'
              : '${rawColumns[pkIndex]} = $literal',
        );
      }
      rowPredicates.add(predicates.join(' AND '));
    }
    if (rowPredicates.isEmpty) return null;
    final String where = rowPredicates.length == 1
        ? rowPredicates.first
        : rowPredicates.map((String p) => '($p)').join(' OR ');
    return 'DELETE FROM $table WHERE $where';
  }

  static Future<List<String>?> _readPrimaryKeyColumns(
    AgentPlanRollbackDeps deps,
    String table,
  ) async {
    final Future<List<String>> Function(String table)? reader =
        deps.primaryKeyColumns;
    if (reader == null) return null;
    try {
      return await reader(table);
    } on Object {
      // describe 失败 = 无 PK 证据 → 不自动生成（fail-safe，不猜）。
      return null;
    }
  }

  /// 顶层 VALUES 元组拆解：`(v,v),(v,v)` → [[v,v],[v,v]]。
  /// 组间出现任何非逗号/空白字符、嵌套括号、引号未闭合 → null。
  static List<List<String>>? _splitValueTuples(String body) {
    final List<List<String>> tuples = <List<String>>[];
    var depth = 0;
    final List<String> current = <String>[];
    final StringBuffer token = StringBuffer();
    String? quote; // 当前引界（' / " / `）
    var betweenGroups = true; // 是否处于组间（只许逗号/空白）

    void endToken() {
      current.add(token.toString().trim());
      token.clear();
    }

    for (var i = 0; i < body.length; i++) {
      final String ch = body[i];
      if (quote != null) {
        token.write(ch);
        if (ch == quote) {
          // '' / "" / `` 转义：连续两个同引号 = 字面量内的引号。
          if (i + 1 < body.length && body[i + 1] == quote) {
            token.write(body[i + 1]);
            i += 1;
          } else {
            quote = null;
          }
        }
        continue;
      }
      if (ch == "'" || ch == '"' || ch == '`') {
        quote = ch;
        token.write(ch);
        continue;
      }
      if (ch == '(') {
        if (depth > 0) return null; // 嵌套括号 = 非字面量形态
        depth = 1;
        betweenGroups = false;
        continue;
      }
      if (ch == ')') {
        if (depth != 1) return null;
        if (token.isNotEmpty) endToken();
        tuples.add(List<String>.of(current));
        current.clear();
        depth = 0;
        betweenGroups = true;
        continue;
      }
      if (depth == 0) {
        if (ch == ',') continue; // 组间逗号
        if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') continue;
        return null; // 组间出现其他字符（裸值/关键字形态）→ 不推导
      }
      if (ch == ',') {
        endToken();
        continue;
      }
      token.write(ch);
    }
    if (quote != null || depth != 0 || !betweenGroups) return null;
    return tuples.isEmpty ? null : tuples;
  }

  /// 字面量归一：数字原样；单引号字符串解转义后按 SQL 规则再转义；
  /// NULL → 'NULL'；其余（括号/函数/占位符/裸标识符）→ null。
  static String? _normalizeValueLiteral(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toUpperCase() == 'NULL') return 'NULL';
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) return trimmed;
    if (trimmed.startsWith("'") &&
        trimmed.endsWith("'") &&
        trimmed.length >= 2) {
      final String inner = trimmed.substring(1, trimmed.length - 1);
      if (inner.contains("'") && !inner.contains("''")) return null;
      return "'${inner.replaceAll("'", "''")}'";
    }
    return null;
  }

  /// 标识符去引界（`a` / "a" / [a] → a；用于 PK 名匹配，不改原文）。
  static String _stripIdentifierQuotes(String identifier) {
    var result = identifier.trim();
    while (result.length >= 2 &&
        ((result.startsWith('`') && result.endsWith('`')) ||
            (result.startsWith('"') && result.endsWith('"')) ||
            (result.startsWith('[') && result.endsWith(']')))) {
      result = result.substring(1, result.length - 1);
    }
    return result;
  }
}
