//! SQL 语句门执行骨架（T20，design-ai-agent §2.3 / §6 计划期发现 #9）。
//!
//! 自 M1 `WorkbenchExecutionActions` 提取的「多语句两遍法 + 双异常路由」
//! 共享执行骨架（行为等价重构，M1 用户点卡执行路径零变化），两处消费：
//! - M1 工作台执行路径（`workbench_execution_actions.dart`）：
//!   `perStatement` 写确认模式，ConfirmExecuteDialog / DdlConfirmDialog /
//!   DmlConfirmDialog 与落卡统计经回调注入；
//! - A2 `AgentPlanExecutor`（计划模式）：`none` 写确认模式（计划卡批准即
//!   写授权，不逐句弹写确认）+ `haltOnStatementFailure` = true（第 k 句
//!   失败即停，k+1..n 标记 skipped）。
//!
//! 骨架（与 M1 既有语义逐点等价）：
//! 1. **拆分**：内置 `SQLParserService.split`（trim + 空语句过滤 + 拆分
//!    结果为空回退整块原文）；ParseException → fail-closed 零执行
//!    （`splitFailed`——畸形 SQL 不整块回退执行，F1）。
//! 2. **两遍法第一遍（gate #1 写门禁）**：全部语句先过写门禁——任一写
//!    语句取消则整批零执行（AC6.1 批量形态）；`perStatement` 模式逐写
//!    语句回调确认（M1 由 organisms 注入对话框），`none` 模式跳过整遍
//!    （A2 计划批准即授权）。
//! 3. **两遍法第二遍（逐语句执行）**：默认部分失败不中断后续语句
//!    （AC9.5，M1 语义）；`haltOnStatementFailure` = true 时第 k 句失败
//!    即停（A2 计划语义）。
//! 4. **双异常路由（gate #2 管线门禁）**：`DdlConfirmationRequiredException`
//!    → `ddlConfirm` 回调 → 确认后经 `executeBypassDdl`（双重门槛）；
//!    `DmlConfirmationRequiredException` → `dmlConfirm` 回调 →
//!    `executeBypassDml`。回调取消 → 中止余下语句（用户刚对危险语句
//!    说不，不再继续）；回调 abort（如 UI context 失效）→ 静默中止；
//!    回调缺位 → fail-closed 视同取消（零执行）。bypass 执行失败按
//!    普通语句失败处理（M1 语义：落错误面后继续余下语句）。
//! 5. **汇总**：逐语句结局（done/failed/skipped）+ 中止边界索引，经
//!    `onStatementResult` 逐语句回调（保持调用方落卡/统计的交错时序）
//!    与 [SqlStatementBatchResult] 终局双通道返回；中止面异常负载
//!    （split/DDL/DML）随终局透出，由调用方映射消息流/审计。
//!
//! services 层纪律：本文件禁 import material / Flutter widgets；对话框与
//! 一切 UI 确认交互经回调注入（`insertConfirmationCallback` 先例）。

import 'package:dbmaster/models/dml_risk_models.dart'
    show DmlConfirmationRequiredException;
import 'package:dbmaster/services/ai/ai_tool_classifier.dart'
    show AiToolClassifier;
import 'package:dbmaster/services/database_service.dart'
    show DdlConfirmationRequiredException, QueryExecutionResult;
import 'package:dbmaster/services/sql_parser_service.dart'
    show ParseException, SQLParserService;

/// gate #1 写确认决策（M1 三态 + 调用方环境中止）。
enum SqlWriteConfirmDecision {
  /// 仅本次放行（M1 allowOnce）。
  allowOnce,

  /// 会话级放行（M1 allowSession；放行集由调用方回调内自持并自行入集）。
  allowSession,

  /// 用户取消 → 整批零执行（AC6.2）。
  cancel,

  /// 调用方环境失效（如 UI context unmounted）→ 静默中止。
  aborted,
}

/// gate #2（DDL/DML 管线门禁）确认决策。
enum SqlGateConfirmDecision {
  /// 确认 → 经对应 bypass 通道执行（双门第二道）。
  confirmed,

  /// 用户取消 → 中止余下语句（调用方映射「已取消」消息/审计）。
  cancelled,

  /// 调用方环境失效 → 静默中止（不执行 bypass，不产取消消息面）。
  aborted,
}

/// gate #1 写确认策略形态。
enum SqlWriteConfirmMode {
  /// M1 模式：逐写语句回调确认（对话框实现由 organisms 注入）。
  perStatement,

  /// A2 计划模式：计划卡批准即写授权，不逐句确认（整遍跳过）。
  none,
}

/// 逐写语句确认回调（perStatement 模式注入）。
typedef SqlWriteConfirmCallback =
    Future<SqlWriteConfirmDecision> Function(String statement);

/// gate #1 写确认策略。
class SqlWriteConfirmStrategy {
  /// M1 模式：逐写语句确认（[onConfirmWrite] 由调用方绑定对话框实现）。
  const SqlWriteConfirmStrategy.perStatement(
    SqlWriteConfirmCallback this.onConfirmWrite,
  ) : mode = SqlWriteConfirmMode.perStatement;

  /// A2 计划模式：计划卡批准即写授权（无逐句确认回调）。
  const SqlWriteConfirmStrategy.none()
    : mode = SqlWriteConfirmMode.none,
      onConfirmWrite = null;

  /// 策略形态。
  final SqlWriteConfirmMode mode;

  /// perStatement 模式的确认回调（none 模式恒为 null）。
  final SqlWriteConfirmCallback? onConfirmWrite;
}

/// 单语句执行回调产物（裁决选项 A detailed 通道）：结果行 + 写/DDL
/// 语句的影响行数（[affectedRows] 引擎值；SELECT 等读语句为 null）。
class SqlStatementOutcome {
  const SqlStatementOutcome({required this.rows, this.affectedRows});

  /// [QueryExecutionResult] 投影（detailed 通道绑定点的解包助手）。
  factory SqlStatementOutcome.fromExecutionResult(QueryExecutionResult result) {
    return SqlStatementOutcome(
      rows: result.rows,
      affectedRows: result.affectedRows,
    );
  }

  /// 结果行。
  final List<Map<String, dynamic>> rows;

  /// 影响行数（引擎值；null = 无该概念或通道未供给）。
  final int? affectedRows;
}

/// 单语句执行回调（M1 绑 `AppProvider.executeQueryDetailed` facade——
/// DDL/DML 拦截、行限制、embedded 网关路由、只读连接检查、SELECT PII
/// 脱敏全部继承；返回 [SqlStatementOutcome] 使 affectedRows 贯通执行
/// 投影与历史双写，不再于 facade 解包层丢失）。
typedef SqlExecuteCallback =
    Future<SqlStatementOutcome> Function(String statement);

/// gate #2 DDL 双门确认回调（M1 由 organisms 绑 DdlConfirmDialog；A2 由
/// shell 绑同款对话框——沿 insertConfirmationCallback 独立注入先例）。
typedef SqlDdlConfirmCallback =
    Future<SqlGateConfirmDecision> Function(DdlConfirmationRequiredException e);

/// gate #2 DML 门确认回调（M1 由 organisms 绑 DmlConfirmDialog）。
typedef SqlDmlConfirmCallback =
    Future<SqlGateConfirmDecision> Function(DmlConfirmationRequiredException e);

/// 逐语句结局回调（落卡/统计等调用方副作用在此保持逐语句交错时序；
/// 仅 done / failed 触发，skipped 不回调）。
typedef SqlStatementResultCallback = void Function(SqlStatementResult result);

/// 单语句结局。
enum SqlStatementStatus {
  /// 执行成功（rows + durationMs 承载）。
  done,

  /// 执行失败（error 承载异常/错误原文；M1 语义下不中断后续语句）。
  failed,

  /// 未执行（中止边界后的余下语句）。
  skipped,
}

/// 单语句结局（[SqlStatementBatchResult.results] 的元素）。
class SqlStatementResult {
  const SqlStatementResult({
    required this.statement,
    required this.index,
    required this.status,
    this.rows,
    this.affectedRows,
    this.durationMs = 0,
    this.error,
  });

  /// 语句文本（拆分产物，已 trim）。
  final String statement;

  /// 批内序号（0 基）。
  final int index;

  /// 结局。
  final SqlStatementStatus status;

  /// 成功时的结果行（仅 done 非 null）。
  final List<Map<String, dynamic>>? rows;

  /// 成功时的影响行数（引擎值；仅 done 非 null，SELECT 等读语句可为
  /// null——裁决选项 A 只加不删的新载荷字段）。
  final int? affectedRows;

  /// 成功时的执行耗时（毫秒；多门路径只计最终成功执行段，与 M1
  /// stopwatch「bypass 前 reset 重启」口径一致）。
  final int durationMs;

  /// 失败时的异常/错误原文（仅 failed 非 null）。
  final Object? error;
}

/// 批次终局状态。
enum SqlBatchStatus {
  /// 全部语句走完（M1 语义下含逐句失败——部分失败继续，AC9.5）。
  completed,

  /// 拆分失败（ParseException）→ fail-closed 零执行（F1）。
  splitFailed,

  /// 空输入（空白 SQL；M1 空白守卫先行拦截，此为防御边界）。
  emptyInput,

  /// gate #1 写确认取消 → 整批零执行。
  writeCancelled,

  /// gate #2 DDL 取消 → 边界中止（余下 skipped）。
  ddlCancelled,

  /// gate #2 DML 取消 → 边界中止（余下 skipped）。
  dmlCancelled,

  /// 第 k 句失败即停（haltOnStatementFailure = true 的 A2 计划语义）。
  failureHalt,

  /// 静默中止（确认回调 abort / shouldContinue 探针拒绝；零消息面）。
  aborted,
}

/// 一批 SQL 的执行终局：逐语句结局 + 中止边界 + 异常负载。
class SqlStatementBatchResult {
  const SqlStatementBatchResult({
    required this.status,
    required this.results,
    required this.haltIndex,
    this.splitError,
    this.ddlException,
    this.dmlException,
  });

  /// 批次终局状态。
  final SqlBatchStatus status;

  /// 逐语句结局（时间序；中止时余下语句以 skipped 收尾）。
  final List<SqlStatementResult> results;

  /// 中止边界索引（首个 skipped 语句的 0 基序号；跑完/未进入执行段 = -1）。
  final int haltIndex;

  /// `splitFailed` 时的拆分异常原文。
  final ParseException? splitError;

  /// DDL 相关中止（ddlCancelled / aborted）时的异常负载。
  final DdlConfirmationRequiredException? ddlException;

  /// DML 相关中止（dmlCancelled / aborted）时的异常负载（审计字段：
  /// sql / analysis.riskLevel）。
  final DmlConfirmationRequiredException? dmlException;
}

/// 执行依赖：全部环境面（执行通道、确认 UI、放行策略）经注入。
class SqlGateRunDeps {
  const SqlGateRunDeps({
    required this.execute,
    this.writeConfirm = const SqlWriteConfirmStrategy.none(),
    this.ddlConfirm,
    this.dmlConfirm,
    this.executeBypassDdl,
    this.executeBypassDml,
    this.haltOnStatementFailure = false,
    this.shouldContinue,
    this.onStatementResult,
  });

  /// 语句执行入口（必填；M1 = `AppProvider.executeQuery` facade）。
  final SqlExecuteCallback execute;

  /// gate #1 写确认策略（默认 `none`——A2 计划模式；M1 须显式
  /// `perStatement` 注入对话框实现）。
  final SqlWriteConfirmStrategy writeConfirm;

  /// gate #2 DDL 双门确认回调；缺位时 DDL 异常 fail-closed 视同取消。
  final SqlDdlConfirmCallback? ddlConfirm;

  /// gate #2 DML 门确认回调；缺位时 fail-closed 视同取消。
  final SqlDmlConfirmCallback? dmlConfirm;

  /// DDL 确认后的 bypass 执行（M1 = `dbService.executeQueryBypassDdlDetailed`
  /// 投影；确认但未提供通道时 fail-closed 中止，不静默回落裸执行）。
  final SqlExecuteCallback? executeBypassDdl;

  /// DML 确认后的 bypass 执行（M1 = `dbService.executeQueryBypassDmlDetailed`
  /// 投影）。
  final SqlExecuteCallback? executeBypassDml;

  /// 第 k 句失败即停（A2 计划语义）；false = M1 部分失败继续（AC9.5）。
  final bool haltOnStatementFailure;

  /// 每语句执行前探针（false → 静默中止；M1 绑 `context.mounted`）。
  final bool Function()? shouldContinue;

  /// 逐语句结局回调（done/failed 同步回调，保持调用方落卡交错时序）。
  final SqlStatementResultCallback? onStatementResult;
}

/// 「多语句两遍法 + 双异常路由」共享执行骨架。
///
/// 无状态、可 const 构造；一次 `run` 处理一批 SQL：拆分 → 写门禁（第一
/// 遍）→ 逐语句执行 + 双异常路由（第二遍）→ 终局汇总返回。
class SqlStatementGateRunner {
  const SqlStatementGateRunner();

  /// 执行一批 SQL。
  Future<SqlStatementBatchResult> run({
    required String sql,
    required SqlGateRunDeps deps,
  }) async {
    // ① 拆分（fail-closed：畸形 SQL 零执行，不整块回退——F1）。
    final trimmed = sql.trim();
    if (trimmed.isEmpty) {
      return const SqlStatementBatchResult(
        status: SqlBatchStatus.emptyInput,
        results: <SqlStatementResult>[],
        haltIndex: -1,
      );
    }
    List<String> statements;
    try {
      final split =
          SQLParserService.split(sql)
              .map((parsed) => parsed.sql.trim())
              .where((statement) => statement.isNotEmpty)
              .toList(growable: false);
      // 拆分结果为空（如纯注释）→ 回退整块原文（M1 既有语义）。
      statements = split.isEmpty ? <String>[trimmed] : split;
    } on ParseException catch (e) {
      return SqlStatementBatchResult(
        status: SqlBatchStatus.splitFailed,
        results: const <SqlStatementResult>[],
        haltIndex: -1,
        splitError: e,
      );
    }

    // ② 两遍法第一遍（gate #1）：任一写语句取消 → 整批零执行（AC6.1）。
    if (deps.writeConfirm.mode == SqlWriteConfirmMode.perStatement) {
      final confirmWrite = deps.writeConfirm.onConfirmWrite;
      if (confirmWrite != null) {
        for (var i = 0; i < statements.length; i++) {
          final statement = statements[i];
          if (!AiToolClassifier.isWriteSql(statement)) continue;
          final decision = await confirmWrite(statement);
          if (decision == SqlWriteConfirmDecision.cancel) {
            return _halted(
              SqlBatchStatus.writeCancelled,
              statements,
              const <SqlStatementResult>[],
              i,
            );
          }
          if (decision == SqlWriteConfirmDecision.aborted) {
            return _halted(
              SqlBatchStatus.aborted,
              statements,
              const <SqlStatementResult>[],
              i,
            );
          }
          // allowOnce / allowSession：继续闸门遍历。会话放行集由调用方
          // 回调内自持——后续写语句回调内免弹（M1「连接级放行，后续
          // 免弹」语义移至注入侧实现）。
        }
      }
    }

    // ③ 两遍法第二遍：逐语句执行（部分失败继续——AC9.5；gate #2 取消/
    //    abort / 失败即停（A2）中止余下语句）。
    final outcomes = <SqlStatementResult>[];
    for (var i = 0; i < statements.length; i++) {
      final statement = statements[i];
      final mayContinue = deps.shouldContinue;
      if (mayContinue != null && !mayContinue()) {
        return _halted(SqlBatchStatus.aborted, statements, outcomes, i);
      }

      final stopwatch = Stopwatch()..start();
      List<Map<String, dynamic>> rows;
      int? affectedRows;
      try {
        final SqlStatementOutcome outcome = await deps.execute(statement);
        rows = outcome.rows;
        affectedRows = outcome.affectedRows;
      } on DdlConfirmationRequiredException catch (e) {
        final confirm = deps.ddlConfirm;
        // 回调缺位 fail-closed：视同取消（零执行）。
        final decision =
            confirm == null
                ? SqlGateConfirmDecision.cancelled
                : await confirm(e);
        if (decision != SqlGateConfirmDecision.confirmed) {
          return _halted(
            decision == SqlGateConfirmDecision.cancelled
                ? SqlBatchStatus.ddlCancelled
                : SqlBatchStatus.aborted,
            statements,
            outcomes,
            i,
            ddlException: e,
          );
        }
        final bypass = deps.executeBypassDdl;
        if (bypass == null) {
          // 确认了但无 bypass 通道：fail-closed 中止，不静默回落裸执行。
          return _halted(
            SqlBatchStatus.aborted,
            statements,
            outcomes,
            i,
            ddlException: e,
          );
        }
        try {
          // reset() 停表后紧接 start() 重启（bypass 执行段计时，M1 口径）。
          stopwatch
            ..reset()
            ..start();
          final SqlStatementOutcome outcome = await bypass(statement);
          rows = outcome.rows;
          affectedRows = outcome.affectedRows;
        } catch (execError) {
          _emitResult(
            deps,
            outcomes,
            statement,
            i,
            SqlStatementStatus.failed,
            error: execError,
          );
          if (deps.haltOnStatementFailure) {
            return _halted(SqlBatchStatus.failureHalt, statements, outcomes, i + 1);
          }
          continue;
        }
      } on DmlConfirmationRequiredException catch (e) {
        final confirm = deps.dmlConfirm;
        final decision =
            confirm == null
                ? SqlGateConfirmDecision.cancelled
                : await confirm(e);
        if (decision != SqlGateConfirmDecision.confirmed) {
          return _halted(
            decision == SqlGateConfirmDecision.cancelled
                ? SqlBatchStatus.dmlCancelled
                : SqlBatchStatus.aborted,
            statements,
            outcomes,
            i,
            dmlException: e,
          );
        }
        final bypass = deps.executeBypassDml;
        if (bypass == null) {
          return _halted(
            SqlBatchStatus.aborted,
            statements,
            outcomes,
            i,
            dmlException: e,
          );
        }
        try {
          stopwatch
            ..reset()
            ..start();
          final SqlStatementOutcome outcome = await bypass(statement);
          rows = outcome.rows;
          affectedRows = outcome.affectedRows;
        } catch (execError) {
          _emitResult(
            deps,
            outcomes,
            statement,
            i,
            SqlStatementStatus.failed,
            error: execError,
          );
          if (deps.haltOnStatementFailure) {
            return _halted(SqlBatchStatus.failureHalt, statements, outcomes, i + 1);
          }
          continue;
        }
      } catch (e) {
        _emitResult(
          deps,
          outcomes,
          statement,
          i,
          SqlStatementStatus.failed,
          error: e,
        );
        if (deps.haltOnStatementFailure) {
          return _halted(SqlBatchStatus.failureHalt, statements, outcomes, i + 1);
        }
        continue;
      }
      stopwatch.stop();
      _emitResult(
        deps,
        outcomes,
        statement,
        i,
        SqlStatementStatus.done,
        rows: rows,
        affectedRows: affectedRows,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }
    return SqlStatementBatchResult(
      status: SqlBatchStatus.completed,
      results: outcomes,
      haltIndex: -1,
    );
  }

  /// 中止终局：已完成结局原样 + 余下语句（[firstSkippedIndex] 起）标 skipped。
  static SqlStatementBatchResult _halted(
    SqlBatchStatus status,
    List<String> statements,
    List<SqlStatementResult> outcomes,
    int firstSkippedIndex, {
    DdlConfirmationRequiredException? ddlException,
    DmlConfirmationRequiredException? dmlException,
  }) {
    final all = List<SqlStatementResult>.of(outcomes);
    for (var i = firstSkippedIndex; i < statements.length; i++) {
      all.add(
        SqlStatementResult(
          statement: statements[i],
          index: i,
          status: SqlStatementStatus.skipped,
        ),
      );
    }
    return SqlStatementBatchResult(
      status: status,
      results: all,
      haltIndex: firstSkippedIndex,
      ddlException: ddlException,
      dmlException: dmlException,
    );
  }

  /// 记录单语句结局并回调调用方（保持落卡交错时序）。
  static void _emitResult(
    SqlGateRunDeps deps,
    List<SqlStatementResult> outcomes,
    String statement,
    int index,
    SqlStatementStatus status, {
    List<Map<String, dynamic>>? rows,
    int? affectedRows,
    int durationMs = 0,
    Object? error,
  }) {
    final result = SqlStatementResult(
      statement: statement,
      index: index,
      status: status,
      rows: rows,
      affectedRows: affectedRows,
      durationMs: durationMs,
      error: error,
    );
    outcomes.add(result);
    deps.onStatementResult?.call(result);
  }
}
