// T22 AgentPlan 单测（design-ai-agent §4.4 / §6.3 / §7）。
//
// 服务层纯逻辑面：注入桩断言（无 UI、无真实库——真库计划链路簇归 T29
// integration_test/agent_plan_real_db_test.dart）。覆盖：
// - 提交校验互斥矩阵（steps 非空 / 单语句 / rollback 与 irreversible
//   二选一全分支 / 估算填充与归一 / planId 唯一）；
// - 状态机全迁移（approve / reject / execute 终局 / rollbackOffered →
//   rolledBack / consumed 标记）；
// - 逐语句执行 + 审计链（planId + step 序号串联，前后成对还原顺序）；
// - 失败边界三段（1..k-1 done / k failed+error / k+1..n skipped，AC11.1）；
// - DDL/DML 双门逐语句（确认 → bypass 第二道；人拒/缺位 fail-closed）；
// - none 写确认模式（计划批准即写授权，零逐句写确认）；
// - 回退组装（逆序 / 模型优先 / auto 推导两形态与不生成边界 / 来源标注）；
// - 回退过门（新计划 pendingApproval 须再批准 + DDL 逆语句双门，AC11.3）；
// - 防重三路（终态重执行 PLAN_ALREADY_EXECUTED / 重复触发可预期 /
//   模型重复提交新 planId，AC11.4）。
import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/models/dml_risk_models.dart'
    show
        DmlConfirmationRequiredException,
        DmlRiskLevel,
        DmlWarningRequiredException,
        RiskAnalysisResult;
import 'package:dbmaster/models/schema_analyzer/impact_report.dart'
    show ImpactReport, RiskLevel;
import 'package:dbmaster/models/sql_statement.dart' show SQLStatement, SQLType;
import 'package:dbmaster/services/ai/agent/agent_gate.dart'
    show AgentRunContext;
import 'package:dbmaster/services/ai/agent/agent_plan.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolErrorCodes;
import 'package:dbmaster/services/database_service.dart'
    show DdlConfirmationRequiredException;
import 'package:dbmaster/services/sql_statement_gate_runner.dart'
    show SqlGateConfirmDecision, SqlStatementOutcome;

// ── 测试桩与助手 ─────────────────────────────────────────────────────────────

AgentRunContext _ctx() => AgentRunContext(
  runId: 'run_test',
  dbType: DatabaseType.mysql,
  readOnly: false,
  connectionId: 'conn_1',
  connectionName: '测试连接',
  databaseName: 'db1',
);

ImpactReport _ddlImpact(String sql) => ImpactReport(
  ddlStatement: sql,
  targetTable: 't1',
  ddlType: 'DROP',
  riskLevel: RiskLevel.high,
  affectedObjects: const [],
  dependencies: const [],
  warnings: const [],
  recommendations: const [],
  requiresConfirmation: true,
  analyzedAt: DateTime(2026, 1, 1),
);

/// 审计记录桩条目。
class _AuditCall {
  const _AuditCall({
    required this.planId,
    required this.step,
    required this.sql,
    required this.gateLevel,
    required this.gateDecision,
    required this.success,
    this.errorMessage,
  });

  final String? planId;
  final int step;
  final String? sql;
  final AgentGateLevel? gateLevel;
  final AgentGateDecision? gateDecision;
  final bool success;
  final String? errorMessage;
}

/// 执行环境桩集合（审计/统计/执行/bypass/确认回调全 spy）。
class _Harness {
  final List<_AuditCall> auditCalls = <_AuditCall>[];
  final List<AgentPlanStatEvent> statEvents = <AgentPlanStatEvent>[];
  final List<String> executedStatements = <String>[];
  final List<String> bypassDdlStatements = <String>[];
  final List<String> bypassDmlStatements = <String>[];
  final List<String> ddlConfirmStatements = <String>[];
  final List<String> dmlConfirmStatements = <String>[];

  late final AgentPlanExecutor executor = AgentPlanExecutor(
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
          AgentGateDecision? gateDecision,
          String? planId,
          required bool success,
          String? errorMessage,
        }) async {
          auditCalls.add(
            _AuditCall(
              planId: planId,
              step: step,
              sql: sql,
              gateLevel: gateLevel,
              gateDecision: gateDecision,
              success: success,
              errorMessage: errorMessage,
            ),
          );
        },
    recordPlanEvent: statEvents.add,
  );

  /// 逐语句执行桩：[failAt] 语句抛错；[ddlAt]/[dmlAt] 语句抛对应确认异常；
  /// [dmlWarningAt] 语句抛 DmlWarningRequiredException（M6 high 档通道）。
  AgentPlanExecutionDeps deps({
    Set<String> failAt = const <String>{},
    Set<String> ddlAt = const <String>{},
    Set<String> dmlAt = const <String>{},
    Set<String> dmlWarningAt = const <String>{},
    Set<String> bypassDmlFailAt = const <String>{},
    bool ddlConfirmed = true,
    bool dmlConfirmed = true,
    bool ddlConfirmPresent = true,
    bool dmlConfirmPresent = true,
    bool bypassDdlPresent = true,
    bool bypassDmlPresent = true,
    bool Function()? shouldContinue,
    void Function(AgentActionPlan plan)? onStepStateChange,
  }) {
    return AgentPlanExecutionDeps(
      execute: (String statement) async {
        executedStatements.add(statement);
        if (failAt.contains(statement)) {
          throw Exception('boom: $statement');
        }
        if (ddlAt.contains(statement)) {
          throw DdlConfirmationRequiredException(
            sql: statement,
            impactReport: _ddlImpact(statement),
          );
        }
        if (dmlAt.contains(statement)) {
          throw DmlConfirmationRequiredException(
            sql: statement,
            analysis: const RiskAnalysisResult(
              riskLevel: DmlRiskLevel.critical,
            ),
            statements: <SQLStatement>[
              SQLStatement(
                index: 0,
                sql: statement,
                type: SQLType.ddl,
                lineStart: 0,
                lineEnd: 0,
              ),
            ],
          );
        }
        if (dmlWarningAt.contains(statement)) {
          throw DmlWarningRequiredException(
            sql: statement,
            analysis: const RiskAnalysisResult(riskLevel: DmlRiskLevel.high),
          );
        }
        return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
      },
      executeBypassDdl: bypassDdlPresent
          ? (String statement) async {
              bypassDdlStatements.add(statement);
              return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
            }
          : null,
      executeBypassDml: bypassDmlPresent
          ? (String statement) async {
              bypassDmlStatements.add(statement);
              if (bypassDmlFailAt.contains(statement)) {
                throw Exception('bypass boom: $statement');
              }
              return const SqlStatementOutcome(rows: <Map<String, dynamic>>[]);
            }
          : null,
      ddlConfirm: ddlConfirmPresent
          ? (DdlConfirmationRequiredException e) async {
              ddlConfirmStatements.add(e.sql);
              return ddlConfirmed
                  ? SqlGateConfirmDecision.confirmed
                  : SqlGateConfirmDecision.cancelled;
            }
          : null,
      dmlConfirm: dmlConfirmPresent
          ? (DmlConfirmationRequiredException e) async {
              dmlConfirmStatements.add(e.sql);
              return dmlConfirmed
                  ? SqlGateConfirmDecision.confirmed
                  : SqlGateConfirmDecision.cancelled;
            }
          : null,
      shouldContinue: shouldContinue,
      onStepStateChange: onStepStateChange,
    );
  }
}

const AgentPlanSubmitter _submitter = AgentPlanSubmitter();

/// 便捷提交（固定 planId，便于断言）。
Future<AgentActionPlan> _plan(
  List<AgentPlanStepInput> steps, {
  AgentPlanRowsEstimator? estimator,
  String planId = 'plan_test_1',
}) async {
  final AgentPlanSubmitResult result = await _submitter.submit(
    steps: steps,
    ctx: _ctx(),
    estimateRows: estimator,
    planIdFactory: () => planId,
  );
  expect(result.ok, isTrue, reason: '测试计划必须合法：${result.errorMessage}');
  return result.plan!;
}

Future<AgentActionPlan> _threeStepPlan() => _plan(<AgentPlanStepInput>[
  const AgentPlanStepInput(
    sql: "INSERT INTO users (id, name) VALUES (1, 'a')",
    rollbackSql: 'DELETE FROM users WHERE id = 1',
  ),
  const AgentPlanStepInput(
    sql: "UPDATE users SET name = 'b' WHERE id = 1",
    rollbackSql: "UPDATE users SET name = 'a' WHERE id = 1",
  ),
  const AgentPlanStepInput(
    sql: 'DELETE FROM users WHERE id = 1',
    irreversible: true,
  ),
]);

/// 组「INSERT 步 + 必失败 UPDATE 步」计划并执行到 partialFailed，再组装
/// 回退计划，从产物反查 INSERT 步是否生成了 DELETE 逆语句（auto 推导探针）。
Future<String> _rollbackDeleteFor(
  String insertSql, {
  Future<List<String>> Function(String table)? pkReader,
}) async {
  final _Harness h = _Harness();
  final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
    AgentPlanStepInput(sql: insertSql, irreversible: true),
    const AgentPlanStepInput(
      sql: "UPDATE users SET name = 'skip' WHERE id = 1",
      rollbackSql: "UPDATE users SET name = 'old' WHERE id = 1",
    ),
  ]);
  await h.executor.approve(plan);
  await h.executor.execute(
    plan: plan,
    deps: h.deps(
      failAt: <String>{"UPDATE users SET name = 'skip' WHERE id = 1"},
    ),
  );
  expect(plan.status, AgentPlanStatus.partialFailed);
  final AgentActionPlan? rollback = await h.executor.buildRollbackPlan(
    plan: plan,
    deps: AgentPlanRollbackDeps(primaryKeyColumns: pkReader),
  );
  if (rollback == null) return '';
  return rollback.steps
      .map((AgentPlanStep s) => s.sql)
      .firstWhere((String s) => s.startsWith('DELETE'), orElse: () => '');
}

void main() {
  // ── G1 提交校验互斥矩阵 ─────────────────────────────────────────────────

  group('G1 提交校验（互斥矩阵 + 单语句 + 估算填充 + planId）', () {
    test('空 steps → INVALID_ARGUMENTS 拒绝', () async {
      final AgentPlanSubmitResult result = await _submitter.submit(
        steps: const <AgentPlanStepInput>[],
        ctx: _ctx(),
      );
      expect(result.ok, isFalse);
      expect(result.plan, isNull);
      expect(result.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(result.errorMessage, contains('non-empty'));
    });

    test('空 sql / 纯空白 sql → INVALID_ARGUMENTS', () async {
      final AgentPlanSubmitResult result = await _submitter.submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(sql: '   ', irreversible: true),
        ],
        ctx: _ctx(),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(result.errorMessage, contains('steps[1].sql'));
    });

    test('多语句步 → INVALID_ARGUMENTS（AC15.4 单语句辨识）', () async {
      final AgentPlanSubmitResult result = await _submitter.submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(
            sql: 'UPDATE a SET x = 1; UPDATE b SET y = 2',
            irreversible: true,
          ),
        ],
        ctx: _ctx(),
      );
      expect(result.ok, isFalse);
      expect(result.errorMessage, contains('exactly one SQL statement'));
    });

    test('畸形 SQL（未闭合注释）→ INVALID_ARGUMENTS，不整块放行（F1）', () async {
      final AgentPlanSubmitResult result = await _submitter.submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(sql: 'UPDATE a SET x = 1 /*', irreversible: true),
        ],
        ctx: _ctx(),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, AgentToolErrorCodes.invalidArguments);
    });

    test('rollbackSql 多语句 → INVALID_ARGUMENTS', () async {
      final AgentPlanSubmitResult result = await _submitter.submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(
            sql: 'UPDATE a SET x = 1',
            rollbackSql: 'UPDATE a SET x = 0; UPDATE b SET y = 0',
          ),
        ],
        ctx: _ctx(),
      );
      expect(result.ok, isFalse);
      expect(result.errorMessage, contains('rollback_sql'));
    });

    test('rollbackSql 与 irreversible 同给 → INVALID_ARGUMENTS（自相矛盾）', () async {
      final AgentPlanSubmitResult result = await _submitter.submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(
            sql: 'UPDATE a SET x = 1',
            rollbackSql: 'UPDATE a SET x = 0',
            irreversible: true,
          ),
        ],
        ctx: _ctx(),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(result.errorMessage, contains('mutually exclusive'));
    });

    test('缺 rollback 未声明不可逆 → INVALID_ARGUMENTS + 补全指引（AC15.1）', () async {
      final AgentPlanSubmitResult result = await _submitter.submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(sql: 'UPDATE a SET x = 1'),
        ],
        ctx: _ctx(),
      );
      expect(result.ok, isFalse);
      expect(result.errorMessage, contains('neither rollback_sql nor'));
      expect(result.errorMessage, contains('irreversible'));
    });

    test('合法混合 → pendingApproval；来源标注与类别正确', () async {
      final AgentActionPlan plan = await _threeStepPlan();

      expect(plan.status, AgentPlanStatus.pendingApproval);
      expect(plan.planId, 'plan_test_1');
      expect(plan.runId, 'run_test');
      expect(plan.steps, hasLength(3));
      // rollback 步：rollbackSource = model；irreversible 步：无 rollback。
      expect(plan.steps[0].rollbackSource, AgentRollbackSource.model);
      expect(plan.steps[0].irreversible, isFalse);
      expect(plan.steps[2].rollbackSql, isNull);
      expect(plan.steps[2].irreversible, isTrue);
      // 类别：INSERT/UPDATE/DELETE 全 dml。
      expect(
        plan.steps.map((AgentPlanStep s) => s.kind),
        everyElement(AgentPlanStepKind.dml),
      );
      // 初始 runtime 全 pending。
      expect(
        plan.steps.map((AgentPlanStep s) => s.runtime.status),
        everyElement(AgentPlanStepStatus.pending),
      );
    });

    test('类别判定：CREATE/DROP → ddl', () async {
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'CREATE TABLE t1 (id INT)',
          irreversible: true,
        ),
        const AgentPlanStepInput(
          sql: 'DROP TABLE t2',
          rollbackSql: 'CREATE TABLE t2 (id INT)',
        ),
      ]);
      expect(
        plan.steps.map((AgentPlanStep s) => s.kind),
        everyElement(AgentPlanStepKind.ddl),
      );
    });

    test('估算填充：estimator 填 explain；空值/缺省归一 unavailable（§4.4 不变式）', () async {
      final AgentActionPlan plan = await _plan(
        <AgentPlanStepInput>[
          const AgentPlanStepInput(
            sql: 'UPDATE a SET x = 1',
            irreversible: true,
          ),
        ],
        estimator: (String sql) async => const AgentPlanRowsEstimate(
          rows: 42,
          source: AgentRowsEstimateSource.explain,
        ),
        planId: 'plan_est',
      );
      expect(plan.steps[0].estimatedRows, 42);
      expect(
        plan.steps[0].estimatedRowsSource,
        AgentRowsEstimateSource.explain,
      );

      // rows 为 null → source 强制 unavailable。
      final AgentActionPlan nullRows = await _plan(
        <AgentPlanStepInput>[
          const AgentPlanStepInput(
            sql: 'UPDATE a SET x = 2',
            irreversible: true,
          ),
        ],
        estimator: (String sql) async => const AgentPlanRowsEstimate(
          source: AgentRowsEstimateSource.explain,
        ),
        planId: 'plan_est_null',
      );
      expect(nullRows.steps[0].estimatedRows, isNull);
      expect(
        nullRows.steps[0].estimatedRowsSource,
        AgentRowsEstimateSource.unavailable,
      );

      // 无 estimator → unavailable。
      final AgentActionPlan noEst = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(sql: 'UPDATE a SET x = 3', irreversible: true),
      ], planId: 'plan_est_none');
      expect(noEst.steps[0].estimatedRows, isNull);
      expect(
        noEst.steps[0].estimatedRowsSource,
        AgentRowsEstimateSource.unavailable,
      );
    });

    test('planId：`plan_<ts>_<seq>` 格式且进程内唯一（模型重复提交新 planId）', () async {
      AgentPlanIds.resetForTesting();
      final AgentPlanSubmitResult first = await _submitter.submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(sql: 'UPDATE a SET x = 1', irreversible: true),
        ],
        ctx: _ctx(),
      );
      final AgentPlanSubmitResult second = await _submitter.submit(
        steps: const <AgentPlanStepInput>[
          AgentPlanStepInput(sql: 'UPDATE a SET x = 1', irreversible: true),
        ],
        ctx: _ctx(),
      );
      expect(first.plan!.planId, isNot(second.plan!.planId));
      expect(first.plan!.planId, matches(RegExp(r'^plan_\d+_\d+$')));
      // 重复提交 = 两个独立 pendingApproval 计划（不静默沿用旧批准）。
      expect(first.plan!.status, AgentPlanStatus.pendingApproval);
      expect(second.plan!.status, AgentPlanStatus.pendingApproval);
    });

    test('AgentPlanStepInput.fromJson 宽容解析：类型不符交校验链拒绝', () async {
      final AgentPlanStepInput parsed = AgentPlanStepInput.fromJson(
        <String, dynamic>{
          'sql': 'UPDATE a SET x = 1',
          'rollback_sql': '  ',
          'irreversible': 'yes', // 非 bool → false
          'note': 42, // 非 String → null
        },
      );
      expect(parsed.sql, 'UPDATE a SET x = 1');
      expect(parsed.rollbackSql, isNull);
      expect(parsed.irreversible, isFalse);
      expect(parsed.note, isNull);

      final AgentPlanSubmitResult result = await _submitter.submit(
        steps: <AgentPlanStepInput>[parsed],
        ctx: _ctx(),
      );
      expect(result.ok, isFalse, reason: '缺 rollback 且未声明不可逆必须拒');

      final AgentPlanStepInput badSql = AgentPlanStepInput.fromJson(
        <String, dynamic>{'sql': 123, 'irreversible': true},
      );
      final AgentPlanSubmitResult bad = await _submitter.submit(
        steps: <AgentPlanStepInput>[badSql],
        ctx: _ctx(),
      );
      expect(bad.ok, isFalse);
    });
  });

  // ── G2 状态机 ────────────────────────────────────────────────────────────

  group('G2 状态机迁移', () {
    test('approve：pendingApproval → approved（统计 + 审计 confirmed）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();

      final bool approved = await h.executor.approve(plan);
      expect(approved, isTrue);
      expect(plan.status, AgentPlanStatus.approved);
      expect(h.statEvents, <AgentPlanStatEvent>[AgentPlanStatEvent.approved]);
      expect(h.auditCalls, hasLength(1));
      expect(h.auditCalls.single.planId, 'plan_test_1');
      expect(h.auditCalls.single.gateDecision, AgentGateDecision.confirmed);
      expect(h.auditCalls.single.gateLevel, AgentGateLevel.l1);
      expect(h.auditCalls.single.success, isTrue);

      // 重复决策幂等忽略。
      expect(await h.executor.approve(plan), isFalse);
      expect(plan.status, AgentPlanStatus.approved);
      expect(h.statEvents, hasLength(1));
    });

    test(
      'reject：pendingApproval → rejected + consumed + 审计人拒（AC13.1/AC9.2）',
      () async {
        final _Harness h = _Harness();
        final AgentActionPlan plan = await _threeStepPlan();

        expect(await h.executor.reject(plan), isTrue);
        expect(plan.status, AgentPlanStatus.rejected);
        expect(plan.isConsumed, isTrue);
        expect(h.statEvents, <AgentPlanStatEvent>[AgentPlanStatEvent.rejected]);
        expect(
          h.auditCalls.single.gateDecision,
          AgentGateDecision.rejectedByUser,
        );
        expect(h.auditCalls.single.success, isFalse);
        // 零执行。
        expect(h.executedStatements, isEmpty);
        // 重复决策幂等忽略。
        expect(await h.executor.reject(plan), isFalse);
      },
    );

    test('execute 于 pendingApproval → fail-loud StateError（未批准不可执行）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();

      await expectLater(
        h.executor.execute(plan: plan, deps: h.deps()),
        throwsA(isA<StateError>()),
      );
      expect(h.executedStatements, isEmpty);
    });

    test('isTerminal 矩阵：五终态 / 四非终态', () {
      const List<AgentPlanStatus> terminal = <AgentPlanStatus>[
        AgentPlanStatus.done,
        AgentPlanStatus.partialFailed,
        AgentPlanStatus.rolledBack,
        AgentPlanStatus.rejected,
        AgentPlanStatus.consumed,
      ];
      const List<AgentPlanStatus> nonTerminal = <AgentPlanStatus>[
        AgentPlanStatus.pendingApproval,
        AgentPlanStatus.approved,
        AgentPlanStatus.executing,
        AgentPlanStatus.rollbackOffered,
      ];
      for (final AgentPlanStatus s in terminal) {
        expect(AgentActionPlan.isTerminalStatus(s), isTrue, reason: '$s 应为终态');
      }
      for (final AgentPlanStatus s in nonTerminal) {
        expect(AgentActionPlan.isTerminalStatus(s), isFalse, reason: '$s 应非终态');
      }
    });
  });

  // ── G3 全成功执行 + 审计链 + none 写确认 ────────────────────────────────

  group('G3 执行（全成功 + 审计链 + none 写确认）', () {
    test('严格串行全成功 → done；审计链前后成对按 step 串联（AC11.2）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(),
      );

      expect(result.ok, isTrue);
      expect(plan.status, AgentPlanStatus.done);
      expect(result.errorCode, isNull);
      expect(
        plan.steps.map((AgentPlanStep s) => s.runtime.status),
        everyElement(AgentPlanStepStatus.done),
      );
      // 严格串行：按序执行三条语句。
      expect(h.executedStatements, <String>[
        "INSERT INTO users (id, name) VALUES (1, 'a')",
        "UPDATE users SET name = 'b' WHERE id = 1",
        'DELETE FROM users WHERE id = 1',
      ]);

      // 审计链：计划级 approve 一条（step=-1）+ 每步 dispatch + outcome
      // 成对，step 序号递增，planId 串联（AC11.2）。
      expect(h.auditCalls, hasLength(7));
      final _AuditCall approveAudit = h.auditCalls.first;
      expect(approveAudit.step, -1);
      expect(approveAudit.gateDecision, AgentGateDecision.confirmed);
      final List<_AuditCall> stepAudits = h.auditCalls
          .where((c) => c.step >= 0)
          .toList(growable: false);
      expect(stepAudits.map((c) => c.step).toList(), <int>[0, 0, 1, 1, 2, 2]);
      expect(h.auditCalls.every((c) => c.planId == 'plan_test_1'), isTrue);
      expect(h.auditCalls.every((c) => c.success), isTrue);
      expect(
        h.auditCalls.every((c) => c.gateLevel == AgentGateLevel.l1),
        isTrue,
      );
      // dispatch 记录带语句原文（审计链可还原执行内容）。
      expect(stepAudits.first.sql, plan.steps.first.sql);
    });

    test('none 写确认模式：写语句直接执行，无逐句写确认交互（批准即授权）', () async {
      final _Harness h = _Harness();
      // 三条全是写语句——deps 不含任何写确认通道，语句必须直接经 execute
      // 执行（若 executor 误用 perStatement 写确认，将零执行可辨）。
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(),
      );
      expect(result.ok, isTrue);
      expect(h.executedStatements, hasLength(3));
    });

    test('onStepStateChange：状态变化逐段通知（卡刷新通道）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.approve(plan);

      final List<AgentPlanStatus> observed = <AgentPlanStatus>[];
      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          onStepStateChange: (AgentActionPlan p) => observed.add(p.status),
        ),
      );
      expect(result.ok, isTrue);
      expect(observed.first, AgentPlanStatus.executing);
      expect(observed.last, AgentPlanStatus.done);
      // executing 起始 + 每步 running/done 各一次 + 终局 done。
      expect(observed.length, greaterThanOrEqualTo(7));
    });
  });

  // ── G4 失败边界三段（AC11.1）────────────────────────────────────────────

  group('G4 失败边界三段（AC11.1）', () {
    test('第 2 步失败 → [done, failed+error, skipped]；第 3 步零执行', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          failAt: <String>{"UPDATE users SET name = 'b' WHERE id = 1"},
        ),
      );

      expect(result.ok, isFalse);
      expect(plan.status, AgentPlanStatus.partialFailed);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.done);
      expect(plan.steps[1].runtime.status, AgentPlanStepStatus.failed);
      expect(plan.steps[1].runtime.error, contains('boom'));
      expect(plan.steps[2].runtime.status, AgentPlanStepStatus.skipped);
      // k+1..n 不执行：只触达前两条语句。
      expect(h.executedStatements, hasLength(2));
      expect(result.errorCode, AgentToolErrorCodes.executionFailed);
      expect(result.errorMessage, contains('step 2 failed'));

      // 失败步审计：dispatch + outcome(success=false, errorMessage)。
      final List<_AuditCall> failed = h.auditCalls
          .where((c) => c.step == 1)
          .toList(growable: false);
      expect(failed, hasLength(2));
      expect(failed.last.success, isFalse);
      expect(failed.last.errorMessage, contains('boom'));
      // 未执行步无审计（从未 dispatch）。
      expect(h.auditCalls.where((c) => c.step == 2), isEmpty);
    });

    test('第 1 步即失败 → 全体 [failed, skipped, skipped]，零成功步', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          failAt: <String>{"INSERT INTO users (id, name) VALUES (1, 'a')"},
        ),
      );
      expect(result.ok, isFalse);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.failed);
      expect(plan.steps[1].runtime.status, AgentPlanStepStatus.skipped);
      expect(plan.steps[2].runtime.status, AgentPlanStepStatus.skipped);
      expect(h.executedStatements, hasLength(1));
    });

    test('shouldContinue 探针拒绝 → 本步起全 skipped（未启动不标 failed）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.approve(plan);

      var probeCount = 0;
      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          shouldContinue: () {
            probeCount += 1;
            return probeCount <= 1; // 第 1 步前放行、第 2 步前拒绝
          },
        ),
      );
      expect(result.ok, isFalse);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.done);
      expect(plan.steps[1].runtime.status, AgentPlanStepStatus.skipped);
      expect(plan.steps[2].runtime.status, AgentPlanStepStatus.skipped);
      expect(h.executedStatements, hasLength(1));
    });
  });

  // ── G5/G6 DDL/DML 双门（AC10.4 不豁免）─────────────────────────────────

  group('G5 DDL 双门逐语句（AC10.4）', () {
    Future<AgentActionPlan> ddlPlan() => _plan(<AgentPlanStepInput>[
      const AgentPlanStepInput(
        sql: 'CREATE TABLE t1 (id INT)',
        rollbackSql: 'DROP TABLE t1',
      ),
      const AgentPlanStepInput(
        sql: 'CREATE TABLE t2 (id INT)',
        rollbackSql: 'DROP TABLE t2',
      ),
    ]);

    test('DDL 异常逐次接住 → 确认后经 executeBypassDdl 第二道执行', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await ddlPlan();
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          ddlAt: <String>{
            'CREATE TABLE t1 (id INT)',
            'CREATE TABLE t2 (id INT)',
          },
        ),
      );

      expect(result.ok, isTrue);
      // 逐语句双门：每条 DDL 各一次确认 + 各一次 bypass（非一次打包）。
      expect(h.ddlConfirmStatements, hasLength(2));
      expect(h.bypassDdlStatements, <String>[
        'CREATE TABLE t1 (id INT)',
        'CREATE TABLE t2 (id INT)',
      ]);
      expect(plan.status, AgentPlanStatus.done);
    });

    test('DDL 人拒 → 失败边界 + 审计 rejectedByUser + 余下 skipped', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await ddlPlan();
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          ddlAt: <String>{'CREATE TABLE t1 (id INT)'},
          ddlConfirmed: false,
        ),
      );

      expect(result.ok, isFalse);
      expect(plan.status, AgentPlanStatus.partialFailed);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.failed);
      expect(plan.steps[0].runtime.error, contains('DDL'));
      expect(plan.steps[1].runtime.status, AgentPlanStepStatus.skipped);
      // 人拒零执行：bypass 从未触达。
      expect(h.bypassDdlStatements, isEmpty);
      final _AuditCall outcome = h.auditCalls.last;
      expect(outcome.gateDecision, AgentGateDecision.rejectedByUser);
      expect(outcome.success, isFalse);
    });

    test('ddlConfirm 缺位 → fail-closed 视同取消（零执行）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await ddlPlan();
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          ddlAt: <String>{'CREATE TABLE t1 (id INT)'},
          ddlConfirmPresent: false,
        ),
      );
      expect(result.ok, isFalse);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.failed);
      expect(h.bypassDdlStatements, isEmpty);
    });

    test('确认了但 bypass 通道缺位 → fail-closed 中止（不静默回落裸执行）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await ddlPlan();
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          ddlAt: <String>{'CREATE TABLE t1 (id INT)'},
          bypassDdlPresent: false,
        ),
      );
      expect(result.ok, isFalse);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.failed);
      expect(h.executedStatements, hasLength(1), reason: '仅初次尝试，无第二道执行');
    });
  });

  group('G6 DML 双门（管线 critical 形态透传）', () {
    test('DROP TABLE 触发 DmlConfirmationRequiredException → 人拒零执行', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'DROP TABLE legacy',
          rollbackSql: 'CREATE TABLE legacy (id INT)',
        ),
      ]);
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(dmlAt: <String>{'DROP TABLE legacy'}, dmlConfirmed: false),
      );
      expect(result.ok, isFalse);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.failed);
      expect(plan.steps[0].runtime.error, contains('DML'));
      expect(h.bypassDmlStatements, isEmpty);
      expect(h.auditCalls.last.gateDecision, AgentGateDecision.rejectedByUser);
    });

    test('DML 确认 → executeBypassDml 第二道执行成功', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'DROP TABLE legacy',
          rollbackSql: 'CREATE TABLE legacy (id INT)',
        ),
      ]);
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(dmlAt: <String>{'DROP TABLE legacy'}),
      );
      expect(result.ok, isTrue);
      expect(h.dmlConfirmStatements, <String>['DROP TABLE legacy']);
      expect(h.bypassDmlStatements, <String>['DROP TABLE legacy']);
    });
  });

  // ── G6b M6 DML 风险标注与 high 档 warning 形态（附录 2 选③）────────────

  group('G6b M6 提交期静态标注（dmlRiskTier）', () {
    test('ALTER DROP COLUMN → high + alterDropColumn trigger（T29 004 复现形）', () async {
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'ALTER TABLE users DROP COLUMN legacy',
          irreversible: true,
        ),
      ]);
      expect(plan.steps[0].dmlRiskTier, AgentPlanDmlRiskTier.high);
      expect(plan.steps[0].dmlRiskTriggers, contains('alterDropColumn'));
    });

    test('DELETE 有 WHERE 无 LIMIT → high + dmlWithoutLimit；有 LIMIT → none', () async {
      final AgentActionPlan high = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'DELETE FROM users WHERE id = 1',
          irreversible: true,
        ),
      ], planId: 'plan_dml_del');
      expect(high.steps[0].dmlRiskTier, AgentPlanDmlRiskTier.high);
      expect(high.steps[0].dmlRiskTriggers, contains('dmlWithoutLimit'));

      final AgentActionPlan limited = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'DELETE FROM users WHERE id = 1 LIMIT 1',
          irreversible: true,
        ),
      ], planId: 'plan_dml_del_limit');
      expect(limited.steps[0].dmlRiskTier, AgentPlanDmlRiskTier.none);
      expect(limited.steps[0].dmlRiskTriggers, isEmpty);
    });

    test('INSERT / CREATE → none（正常档不标注）', () async {
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: "INSERT INTO users (id, name) VALUES (1, 'a')",
          rollbackSql: 'DELETE FROM users WHERE id = 1',
        ),
        const AgentPlanStepInput(
          sql: 'CREATE TABLE t1 (id INT)',
          irreversible: true,
        ),
      ]);
      expect(
        plan.steps.map((AgentPlanStep s) => s.dmlRiskTier),
        everyElement(AgentPlanDmlRiskTier.none),
      );
    });

    test('critical（DROP TABLE / UPDATE 无 WHERE）不标注 high——仍走模态双门', () async {
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'DROP TABLE legacy',
          rollbackSql: 'CREATE TABLE legacy (id INT)',
        ),
        const AgentPlanStepInput(
          sql: 'UPDATE users SET admin = 1',
          irreversible: true,
        ),
      ]);
      expect(
        plan.steps.map((AgentPlanStep s) => s.dmlRiskTier),
        everyElement(AgentPlanDmlRiskTier.none),
        reason: 'critical 由 DmlConfirmDialog 模态双门承载，不进 high 通道',
      );
    });
  });

  group('G6c M6 执行期 warning 形态（high 标注 → bypass；未标注 → fail-closed）', () {
    test('① ALTER DROP COLUMN 计划：标注可见 → 批准 → warning 经 bypass 重执行标 done', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'ALTER TABLE users DROP COLUMN legacy',
          irreversible: true,
        ),
      ]);
      expect(plan.steps[0].dmlRiskTier, AgentPlanDmlRiskTier.high);
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          dmlWarningAt: <String>{'ALTER TABLE users DROP COLUMN legacy'},
        ),
      );

      expect(result.ok, isTrue);
      expect(plan.status, AgentPlanStatus.done);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.done);
      // 经典同通道：初次执行 1 次（warning 拦）+ bypass 重执行 1 次。
      expect(h.executedStatements, <String>[
        'ALTER TABLE users DROP COLUMN legacy',
      ]);
      expect(h.bypassDmlStatements, <String>[
        'ALTER TABLE users DROP COLUMN legacy',
      ]);
      // 结局审计：dispatch + bypass 成功（confirmed = 批准即覆盖的确认语义）。
      final List<_AuditCall> stepAudits = h.auditCalls
          .where((c) => c.step == 0)
          .toList(growable: false);
      expect(stepAudits, hasLength(2));
      expect(stepAudits.last.success, isTrue);
      expect(stepAudits.last.gateDecision, AgentGateDecision.confirmed);
    });

    test('② 多步计划混编：high 步 bypass 放行 + 后续步照常执行（严格串行不中断）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'DELETE FROM users WHERE id = 1',
          irreversible: true,
        ),
        const AgentPlanStepInput(
          sql: "INSERT INTO users (id, name) VALUES (9, 'z')",
          rollbackSql: 'DELETE FROM users WHERE id = 9',
        ),
      ]);
      expect(plan.steps[0].dmlRiskTier, AgentPlanDmlRiskTier.high);
      expect(plan.steps[1].dmlRiskTier, AgentPlanDmlRiskTier.none);
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(dmlWarningAt: <String>{
          'DELETE FROM users WHERE id = 1',
        }),
      );
      expect(result.ok, isTrue);
      expect(plan.status, AgentPlanStatus.done);
      expect(
        plan.steps.map((AgentPlanStep s) => s.runtime.status),
        everyElement(AgentPlanStepStatus.done),
      );
    });

    test('③ 未标注漂移步冒 warning → fail-closed 保持 failed（bypass 不放行）', () async {
      final _Harness h = _Harness();
      // INSERT 静态分析 = none；构造执行期冒 warning 的漂移步（构造性不可
      // 达的防御面——静态 ⇒ 标注与执行期判定一致，此分支只守漂移）。
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: "INSERT INTO users (id, name) VALUES (1, 'a')",
          rollbackSql: 'DELETE FROM users WHERE id = 1',
        ),
      ]);
      expect(plan.steps[0].dmlRiskTier, AgentPlanDmlRiskTier.none);
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          dmlWarningAt: <String>{"INSERT INTO users (id, name) VALUES (1, 'a')"},
        ),
      );
      expect(result.ok, isFalse);
      expect(plan.status, AgentPlanStatus.partialFailed);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.failed);
      expect(
        h.bypassDmlStatements,
        isEmpty,
        reason: '未标注步 warning 一律 fail-closed，bypass 零触达',
      );
    });

    test('bypass 通道缺位 → fail-closed 保持 failed（不静默回落裸执行）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'ALTER TABLE users DROP COLUMN legacy',
          irreversible: true,
        ),
      ]);
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          dmlWarningAt: <String>{'ALTER TABLE users DROP COLUMN legacy'},
          bypassDmlPresent: false,
        ),
      );
      expect(result.ok, isFalse);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.failed);
    });

    test('bypass 重执行失败 → 普通步失败（reason 取重执行错误）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'ALTER TABLE users DROP COLUMN legacy',
          irreversible: true,
        ),
      ]);
      await h.executor.approve(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(
          dmlWarningAt: <String>{'ALTER TABLE users DROP COLUMN legacy'},
          bypassDmlFailAt: <String>{'ALTER TABLE users DROP COLUMN legacy'},
        ),
      );
      expect(result.ok, isFalse);
      expect(plan.steps[0].runtime.status, AgentPlanStepStatus.failed);
      expect(plan.steps[0].runtime.error, contains('bypass boom'));
      expect(h.auditCalls.last.success, isFalse);
    });
  });

  // ── G7 防重三路（AC11.4）────────────────────────────────────────────────

  group('G7 防重（AC11.4）', () {
    test('done 计划再执行 → PLAN_ALREADY_EXECUTED，零库操作，重复触发可预期', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.approve(plan);
      await h.executor.execute(plan: plan, deps: h.deps());
      expect(h.executedStatements, hasLength(3));

      final AgentPlanExecutionResult replay = await h.executor.execute(
        plan: plan,
        deps: h.deps(),
      );
      expect(replay.ok, isFalse);
      expect(replay.errorCode, AgentToolErrorCodes.planAlreadyExecuted);
      expect(plan.status, AgentPlanStatus.done, reason: '终态值保留供卡呈现');
      expect(plan.isConsumed, isTrue);
      expect(h.executedStatements, hasLength(3), reason: '重放零库操作');

      // 第二次重放结果一致（可预期）。
      final AgentPlanExecutionResult replay2 = await h.executor.execute(
        plan: plan,
        deps: h.deps(),
      );
      expect(replay2.errorCode, AgentToolErrorCodes.planAlreadyExecuted);
      expect(h.executedStatements, hasLength(3));
    });

    test('partialFailed 计划再执行 → 同样 PLAN_ALREADY_EXECUTED', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.approve(plan);
      await h.executor.execute(
        plan: plan,
        deps: h.deps(
          failAt: <String>{"UPDATE users SET name = 'b' WHERE id = 1"},
        ),
      );
      final int executed = h.executedStatements.length;

      final AgentPlanExecutionResult replay = await h.executor.execute(
        plan: plan,
        deps: h.deps(),
      );
      expect(replay.errorCode, AgentToolErrorCodes.planAlreadyExecuted);
      expect(plan.status, AgentPlanStatus.partialFailed);
      expect(h.executedStatements, hasLength(executed));
    });

    test('rejected 计划触达执行器 → PLAN_ALREADY_EXECUTED（从未执行也不可再执行）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _threeStepPlan();
      await h.executor.reject(plan);

      final AgentPlanExecutionResult result = await h.executor.execute(
        plan: plan,
        deps: h.deps(),
      );
      expect(result.errorCode, AgentToolErrorCodes.planAlreadyExecuted);
      expect(h.executedStatements, isEmpty);
    });

    test('markConsumed：终态标记，非终态忽略', () async {
      final AgentActionPlan plan = await _threeStepPlan();
      expect(plan.isConsumed, isFalse);
      expect(
        AgentPlanExecutor().markConsumed(plan),
        isFalse,
        reason: 'pendingApproval 非终态不标记',
      );
      plan.status = AgentPlanStatus.done;
      expect(AgentPlanExecutor().markConsumed(plan), isTrue);
      expect(plan.isConsumed, isTrue);
    });
  });

  // ── G8 回退组装（AC11.3 前半：逆序 + 两路来源 + 不生成边界）────────────

  group('G8 回退组装', () {
    test('completed 步逆序组装；模型 rollbackSql 优先于 auto；失败步不参与', () async {
      final _Harness h = _Harness();
      // step0 INSERT 带模型回退（故意 WHERE id = 99，验证模型优先）；
      // step1 CREATE 声明 irreversible（机械可推导 → 仍 auto 推导 DROP）；
      // step2 执行失败 → 边界，不参与回退。
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: "INSERT INTO users (id, name) VALUES (7, 'z')",
          rollbackSql: 'DELETE FROM users WHERE id = 99',
        ),
        const AgentPlanStepInput(
          sql: 'CREATE TABLE extra (id INT)',
          irreversible: true,
        ),
        const AgentPlanStepInput(
          sql: 'DELETE FROM users WHERE id = 7',
          irreversible: true,
        ),
      ]);
      await h.executor.approve(plan);
      await h.executor.execute(
        plan: plan,
        deps: h.deps(failAt: <String>{'DELETE FROM users WHERE id = 7'}),
      );
      expect(plan.status, AgentPlanStatus.partialFailed);
      final int executedBeforeBuild = h.executedStatements.length;
      final int auditBeforeBuild = h.auditCalls.length;

      final AgentActionPlan? rollback = await h.executor.buildRollbackPlan(
        plan: plan,
        deps: AgentPlanRollbackDeps(
          primaryKeyColumns: (String table) async => <String>['id'],
        ),
      );
      expect(rollback, isNotNull);
      // 逆序：step1（CREATE → auto DROP）在前、step0（模型回退）在后。
      expect(rollback!.steps, hasLength(2));
      expect(rollback.steps[0].sql, 'DROP TABLE extra');
      expect(rollback.steps[0].note, contains('step 1'));
      // 模型 rollbackSql 优先于 auto 推导（WHERE id = 99 而非 7）。
      expect(rollback.steps[1].sql, 'DELETE FROM users WHERE id = 99');
      // 逆的逆 = 原语句（回退计划自身的 rollbackSql，来源 model）。
      expect(rollback.steps[1].rollbackSql, plan.steps[0].sql);
      expect(rollback.steps[1].rollbackSource, AgentRollbackSource.model);
      // 新计划：pendingApproval + 新 planId + 回退标识；原计划翻 rollbackOffered。
      expect(rollback.status, AgentPlanStatus.pendingApproval);
      expect(rollback.planId, isNot(plan.planId));
      expect(rollback.rollbackOfPlanId, plan.planId);
      expect(rollback.ctx, same(plan.ctx));
      expect(rollback.runId, plan.runId);
      expect(plan.status, AgentPlanStatus.rollbackOffered);
      // M6：回退步同走静态标注——auto DROP TABLE = critical → none；模型
      // 逆语句 DELETE 无 LIMIT = high + dmlWithoutLimit。
      expect(rollback.steps[0].dmlRiskTier, AgentPlanDmlRiskTier.none);
      expect(rollback.steps[1].dmlRiskTier, AgentPlanDmlRiskTier.high);
      expect(rollback.steps[1].dmlRiskTriggers, contains('dmlWithoutLimit'));
      // 永不自动执行：组装过程零执行触达（AC11.3 结构保证）。
      expect(h.executedStatements, hasLength(executedBeforeBuild));
      expect(h.bypassDdlStatements, isEmpty);
      // Fix-F ③：组装成功落一条血缘审计（planId = 新回退计划；errorMessage
      // 携带 rb_of_<原 planId>——审计链据此区分「回退补偿」与「新发起」）。
      expect(h.auditCalls, hasLength(auditBeforeBuild + 1));
      final _AuditCall lineage = h.auditCalls.last;
      expect(lineage.planId, rollback.planId);
      expect(lineage.step, -1);
      expect(lineage.gateDecision, AgentGateDecision.na);
      expect(lineage.success, isTrue);
      expect(lineage.errorMessage, contains('rb_of_plan_test_1'));
    });

    test('INSERT auto 推导：DELETE 只按 PK 列定位；多行 OR 组合；转义还原', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: "INSERT INTO users (id, name) VALUES (1, 'O''Brien'), (2, 'x')",
          irreversible: true,
        ),
        const AgentPlanStepInput(
          sql: 'UPDATE users SET name = NULL WHERE id = 1',
          rollbackSql: "UPDATE users SET name = 'old' WHERE id = 1",
        ),
      ]);
      await h.executor.approve(plan);
      await h.executor.execute(
        plan: plan,
        deps: h.deps(
          failAt: <String>{'UPDATE users SET name = NULL WHERE id = 1'},
        ),
      );

      final AgentActionPlan? rollback = await h.executor.buildRollbackPlan(
        plan: plan,
        deps: AgentPlanRollbackDeps(
          primaryKeyColumns: (String table) async => <String>['id'],
        ),
      );
      expect(rollback, isNotNull);
      expect(rollback!.steps, hasLength(1));
      // WHERE 只含 PK 列（id），多行 OR 组合。
      expect(
        rollback.steps[0].sql,
        'DELETE FROM users WHERE (id = 1) OR (id = 2)',
      );
      expect(rollback.steps[0].note, contains('step 0'));
      expect(rollback.steps[0].kind, AgentPlanStepKind.dml);
    });

    test('INSERT 不生成边界：无 PK / reader 缺位或抛错 / 隐式列 / 非字面量 / PK 不在插入列', () async {
      // 无 PK。
      expect(
        await _rollbackDeleteFor(
          "INSERT INTO logs (id, msg) VALUES (1, 'a')",
          pkReader: (String table) async => const <String>[],
        ),
        isEmpty,
        reason: '无 PK 不自动生成',
      );
      // reader 抛错 = 无 PK 证据。
      expect(
        await _rollbackDeleteFor(
          "INSERT INTO logs (id, msg) VALUES (1, 'a')",
          pkReader: (String table) => throw Exception('describe failed'),
        ),
        isEmpty,
      );
      // reader 缺位。
      expect(
        await _rollbackDeleteFor("INSERT INTO logs (id, msg) VALUES (1, 'a')"),
        isEmpty,
      );
      // 隐式列清单（无法核对 PK 赋值）。
      expect(
        await _rollbackDeleteFor(
          "INSERT INTO logs (id, msg) VALUES (1, 'a')",
          pkReader: (String table) async => const <String>['id'],
        ),
        isNotEmpty,
        reason: '对照组：显式列 + 有 PK 正常生成',
      );
      expect(
        await _rollbackDeleteFor(
          'INSERT INTO logs VALUES (1, \'a\')',
          pkReader: (String table) async => const <String>['id'],
        ),
        isEmpty,
      );
      // 非字面量（函数）。
      expect(
        await _rollbackDeleteFor(
          'INSERT INTO logs (id, msg) VALUES (1, NOW())',
          pkReader: (String table) async => const <String>['id'],
        ),
        isEmpty,
      );
      // PK 不在插入列。
      expect(
        await _rollbackDeleteFor(
          "INSERT INTO logs (msg) VALUES ('a')",
          pkReader: (String table) async => const <String>['id'],
        ),
        isEmpty,
      );
    });

    test('CREATE 形态推导：TABLE/INDEX/VIEW；CREATE 形态外不推导', () async {
      // 经「CREATE 步 + 必失败步」组装探针（同 INSERT 探针模式）。
      Future<String> rollbackFor(String createSql) async {
        final _Harness h = _Harness();
        final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
          AgentPlanStepInput(sql: createSql, irreversible: true),
          const AgentPlanStepInput(
            sql: "UPDATE users SET name = 'skip' WHERE id = 1",
            rollbackSql: "UPDATE users SET name = 'old' WHERE id = 1",
          ),
        ]);
        await h.executor.approve(plan);
        await h.executor.execute(
          plan: plan,
          deps: h.deps(
            failAt: <String>{"UPDATE users SET name = 'skip' WHERE id = 1"},
          ),
        );
        final AgentActionPlan? rollback = await h.executor.buildRollbackPlan(
          plan: plan,
          deps: const AgentPlanRollbackDeps(),
        );
        if (rollback == null) return '';
        return rollback.steps
            .map((AgentPlanStep s) => s.sql)
            .firstWhere((String s) => s.startsWith('DROP'), orElse: () => '');
      }

      expect(
        await rollbackFor('CREATE TABLE `orders` (id INT)'),
        'DROP TABLE `orders`',
      );
      expect(
        await rollbackFor('CREATE INDEX idx_a ON orders (a)'),
        'DROP INDEX idx_a',
      );
      expect(
        await rollbackFor('CREATE OR REPLACE VIEW v1 AS SELECT 1'),
        'DROP VIEW v1',
      );
      expect(
        await rollbackFor('CREATE FUNCTION f1() RETURNS INT RETURN 1'),
        isEmpty,
      );
      // UPDATE 形态外（不可机械反演）。
      expect(
        await rollbackFor('UPDATE orders SET a = 1 WHERE id = 1'),
        isEmpty,
      );
    });

    test('全部不可回退（形态外 + 无模型回退）→ 返回 null，原状态不变', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(sql: 'UPDATE a SET x = 1', irreversible: true),
        const AgentPlanStepInput(sql: 'UPDATE b SET y = 2', irreversible: true),
      ]);
      await h.executor.approve(plan);
      await h.executor.execute(
        plan: plan,
        deps: h.deps(failAt: <String>{'UPDATE b SET y = 2'}),
      );
      expect(plan.status, AgentPlanStatus.partialFailed);

      final AgentActionPlan? rollback = await h.executor.buildRollbackPlan(
        plan: plan,
        deps: AgentPlanRollbackDeps(
          primaryKeyColumns: (String table) async => const <String>['id'],
        ),
      );
      expect(rollback, isNull);
      expect(plan.status, AgentPlanStatus.partialFailed, reason: '原状态不变');
    });

    test('非失败边界计划（done / pendingApproval）→ 不组装', () async {
      final _Harness h = _Harness();
      final AgentActionPlan done = await _threeStepPlan();
      await h.executor.approve(done);
      await h.executor.execute(plan: done, deps: h.deps());
      expect(
        await h.executor.buildRollbackPlan(
          plan: done,
          deps: const AgentPlanRollbackDeps(),
        ),
        isNull,
      );

      final AgentActionPlan fresh = await _threeStepPlan();
      expect(
        await h.executor.buildRollbackPlan(
          plan: fresh,
          deps: const AgentPlanRollbackDeps(),
        ),
        isNull,
      );
    });
  });

  // ── G9 回退过门 + rolledBack 流转（AC11.3 后半）─────────────────────────

  group('G9 回退过门与 rolledBack 流转（AC11.3）', () {
    test('回退计划须再批准才可执行；DDL 逆语句逐次双门；成功后原计划 rolledBack', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'CREATE TABLE extra (id INT)',
          rollbackSql: 'DROP TABLE extra',
        ),
        const AgentPlanStepInput(
          sql: 'UPDATE users SET name = NULL WHERE id = 1',
          rollbackSql: "UPDATE users SET name = 'old' WHERE id = 1",
        ),
      ]);
      await h.executor.approve(plan);
      await h.executor.execute(
        plan: plan,
        deps: h.deps(
          failAt: <String>{"UPDATE users SET name = NULL WHERE id = 1"},
        ),
      );

      final AgentActionPlan? rollback = await h.executor.buildRollbackPlan(
        plan: plan,
        deps: AgentPlanRollbackDeps(planIdFactory: () => 'plan_rb_1'),
      );
      expect(rollback, isNotNull);
      expect(rollback!.planId, 'plan_rb_1');

      // 未批准执行 → fail-loud（新计划走同一 L1 门：批准是执行前置）。
      await expectLater(
        h.executor.execute(plan: rollback, deps: h.deps()),
        throwsA(isA<StateError>()),
      );

      // 批准 → 执行：DROP TABLE 逆语句触发 DDL 双门（逐次，不豁免）。
      await h.executor.approve(rollback);
      final AgentPlanExecutionResult rbResult = await h.executor.execute(
        plan: rollback,
        deps: h.deps(ddlAt: <String>{'DROP TABLE extra'}),
      );
      expect(rbResult.ok, isTrue);
      expect(rollback.status, AgentPlanStatus.done);
      expect(h.ddlConfirmStatements, contains('DROP TABLE extra'));
      expect(h.bypassDdlStatements, contains('DROP TABLE extra'));

      // 原计划流转：rollbackOffered → rolledBack。
      expect(plan.status, AgentPlanStatus.rollbackOffered);
      expect(h.executor.markRolledBack(plan), isTrue);
      expect(plan.status, AgentPlanStatus.rolledBack);
      expect(plan.isConsumed, isTrue);
      // 非 rollbackOffered 时 markRolledBack 幂等忽略。
      expect(h.executor.markRolledBack(plan), isFalse);

      // 终态重放：rolledBack 计划再执行 → PLAN_ALREADY_EXECUTED。
      final AgentPlanExecutionResult replay = await h.executor.execute(
        plan: plan,
        deps: h.deps(),
      );
      expect(replay.errorCode, AgentToolErrorCodes.planAlreadyExecuted);
    });

    test('回退计划自身失败 → 原计划停留 rollbackOffered（可重组装）', () async {
      final _Harness h = _Harness();
      final AgentActionPlan plan = await _plan(<AgentPlanStepInput>[
        const AgentPlanStepInput(
          sql: 'CREATE TABLE extra (id INT)',
          rollbackSql: 'DROP TABLE extra',
        ),
        const AgentPlanStepInput(
          sql: 'UPDATE users SET name = NULL WHERE id = 1',
          rollbackSql: "UPDATE users SET name = 'old' WHERE id = 1",
        ),
      ]);
      await h.executor.approve(plan);
      await h.executor.execute(
        plan: plan,
        deps: h.deps(
          failAt: <String>{"UPDATE users SET name = NULL WHERE id = 1"},
        ),
      );
      final AgentActionPlan? rollback = await h.executor.buildRollbackPlan(
        plan: plan,
        deps: const AgentPlanRollbackDeps(),
      );
      expect(rollback, isNotNull);

      // 回退执行失败（逆序首步 DROP 失败）→ 原计划停留 rollbackOffered。
      await h.executor.approve(rollback!);
      await h.executor.execute(
        plan: rollback,
        deps: h.deps(failAt: <String>{'DROP TABLE extra'}),
      );
      expect(rollback.status, AgentPlanStatus.partialFailed);
      expect(plan.status, AgentPlanStatus.rollbackOffered);
      // 停留 rollbackOffered 可重组装（换新 planId 再走一次批准门）。
      final AgentActionPlan? rebuilt = await h.executor.buildRollbackPlan(
        plan: plan,
        deps: const AgentPlanRollbackDeps(),
      );
      expect(rebuilt, isNotNull);
      expect(rebuilt!.planId, isNot(rollback.planId));
      expect(rebuilt.status, AgentPlanStatus.pendingApproval);
    });
  });
}
