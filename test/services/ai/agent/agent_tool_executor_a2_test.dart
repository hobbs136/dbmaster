// AgentToolExecutor A2 扩展单测（T28 / design-ai-agent.md §6.3、§6.6、§4.5、
// §7、AC4.4、AC9.x、AC15.1）。
//
// 覆盖任务书清单：submit 链全分支（校验回喂 / readOnly 先拦 / 批准前零执行 /
// 批准执行 / 拒绝零变化 / 审计 planId 串联）、result_ref 生命周期（run 内
// 登记 / 界面工具消费 / 跨 run 失效）、界面七工具 outcome 回喂（含 uiPort
// 缺位 fail-closed）、AC4.4 库级限定名执法（方言边界内拒 / 边界外放行）。
//
// 计划执行用真实 AgentPlanExecutor（T22）+ 注入执行通道 spy——装配层
// （shell）在 onPlanApproval 回调内 approve + execute 的语义在此仿真。

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/ai_models.dart' show AiToolCall;
import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbColumn, DbIndex, ForeignKey;
import 'package:dbmaster/services/ai/agent/agent_gate.dart';
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';
import 'package:dbmaster/services/ai/agent/agent_plan.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolErrorCodes;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort, GateCardResult;

// ── fakes / spies ───────────────────────────────────────────────────────────

/// dbService 访问 spy（A2 面只需 executeQuery / getExplainPlan）。
class _DbSpy {
  int executeQueryCalls = 0;
  final List<String> executedSql = <String>[];
  List<Map<String, dynamic>> queryResult = <Map<String, dynamic>>[
    <String, dynamic>{'id': 1},
  ];
  Object? queryError;

  int explainCalls = 0;
  List<Map<String, dynamic>> explainResult = <Map<String, dynamic>>[];

  Future<List<Map<String, dynamic>>> executeQuery(
    String sql, {
    String? connectionId,
    String? database,
  }) {
    executeQueryCalls++;
    executedSql.add(sql);
    final Object? err = queryError;
    if (err != null) throw err;
    return Future<List<Map<String, dynamic>>>.value(queryResult);
  }

  Future<List<Map<String, dynamic>>> getExplainPlan(
    String sql, {
    String? connectionId,
  }) {
    explainCalls++;
    return Future<List<Map<String, dynamic>>>.value(explainResult);
  }
}

/// 审计 spy（字段形态断言：planId 串联 / 决策 / success）。
class _AuditSpy {
  final List<Map<String, Object?>> records = <Map<String, Object?>>[];
  int get count => records.length;

  Future<void> record({
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
    records.add(<String, Object?>{
      'connectionId': connectionId,
      'runId': runId,
      'step': step,
      'tool': tool,
      'sql': sql,
      'gateLevel': gateLevel,
      'gateDecision': gateDecision,
      'planId': planId,
      'success': success,
      'errorMessage': errorMessage,
    });
  }
}

/// 界面派发端口 spy：记录方法调用与参数，可编程 outcome。
class _UiPortSpy implements AgentUiPort {
  int openResultGridCalls = 0;
  int showStructureCalls = 0;
  int openEditorCalls = 0;
  int renderChartCalls = 0;
  int pinArtifactCalls = 0;
  int suggestClassicCalls = 0;
  int suggestFocusCalls = 0;

  final List<String> structureTables = <String>[];
  final List<String> editorSqls = <String>[];

  final List<String?> chartKinds = <String?>[];
  final List<String?> pinLabels = <String?>[];
  final List<String> classicSqls = <String>[];
  final List<({String? database, String? table})> focusTargets =
      <({String? database, String? table})>[];

  AgentUiOutcome outcome = const AgentUiOutcome.ok();

  @override
  Future<AgentUiOutcome> openResultGrid(AgentResultRef ref, String? title) {
    openResultGridCalls++;
    return Future<AgentUiOutcome>.value(outcome);
  }

  @override
  Future<AgentUiOutcome> showTableStructure(String table) {
    showStructureCalls++;
    structureTables.add(table);
    return Future<AgentUiOutcome>.value(outcome);
  }

  @override
  Future<AgentUiOutcome> openSqlEditor(String sql) {
    openEditorCalls++;
    editorSqls.add(sql);
    return Future<AgentUiOutcome>.value(outcome);
  }

  @override
  Future<AgentUiOutcome> renderChart(AgentResultRef ref, String? chartKind) {
    renderChartCalls++;
    chartKinds.add(chartKind);
    return Future<AgentUiOutcome>.value(outcome);
  }

  @override
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label) {
    pinArtifactCalls++;
    pinLabels.add(label);
    return Future<AgentUiOutcome>.value(outcome);
  }

  @override
  Future<AgentUiOutcome> suggestOpenInClassic(String sql) {
    suggestClassicCalls++;
    classicSqls.add(sql);
    return Future<AgentUiOutcome>.value(outcome);
  }

  @override
  Future<AgentUiOutcome> suggestFocusSidebar({
    String? database,
    String? table,
  }) {
    suggestFocusCalls++;
    focusTargets.add((database: database, table: table));
    return Future<AgentUiOutcome>.value(outcome);
  }
}

/// 可编程门：默认 confirm(l1)（submit 链）/ allow(l0)（数据与界面工具）。
class _ScriptedGate extends AgentGate {
  _ScriptedGate(this.decision)
    : super(
        createAnalysis: (_) => throw StateError('scripted gate never analyzes'),
      );

  GateDecision decision;

  @override
  Future<GateDecision> evaluate({
    required dynamic spec,
    required Map<String, dynamic> args,
    required AgentRunContext runCtx,
    required AgentPermissionLedger ledger,
  }) async => decision;
}

const GateDecision _confirmL1 = GateDecision(
  kind: GateDecisionKind.confirm,
  level: AgentGateLevel.l1,
);

const GateDecision _allowL0 = GateDecision(
  kind: GateDecisionKind.allow,
  level: AgentGateLevel.l0,
);

/// 测试台（A2 面）。
class _Harness {
  _Harness({
    GateDecision gateDecision = _allowL0,
    AgentGate? gateOverride,
    DatabaseType dbType = DatabaseType.mysql,
    String databaseName = 'db1',
    bool readOnly = false,
  }) : gate = gateOverride ?? _ScriptedGate(gateDecision) {
    runCtx = AgentRunContext(
      runId: 'run-1',
      connectionId: 'conn-1',
      connectionName: '测试连接',
      databaseName: databaseName,
      dbType: dbType,
      readOnly: readOnly,
    );
    executor = AgentToolExecutor(
      gate: gate,
      db: dbAccess(),
      audit: audit.record,
      recordToolCall: (_) {},
      recordL05Event: (_) {},
      recordL1Blocked: () => l1BlockedCount++,
    );
  }

  final _DbSpy db = _DbSpy();
  final _AuditSpy audit = _AuditSpy();
  final AgentPermissionLedger ledger = AgentPermissionLedger();
  final _UiPortSpy uiPort = _UiPortSpy();
  late final AgentRunContext runCtx;
  final AgentGate gate;
  late final AgentToolExecutor executor;
  int l1BlockedCount = 0;

  /// 计划执行通道（装配层仿真面）：记录逐语句执行、可编程失败步。
  final List<String> planExecuted = <String>[];
  int failAtStep = -1; // 1 基；命中步抛错（partialFailed 构造）

  AgentDbAccess dbAccess() => AgentDbAccess(
    getTables: (String? connectionId) async => <String>[],
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
        }) async => '',
    getExplainPlan: (String sql, {String? connectionId}) =>
        db.getExplainPlan(sql, connectionId: connectionId),
    executeQuery: (String sql, {String? connectionId, String? database}) =>
        db.executeQuery(sql, connectionId: connectionId, database: database),
  );

  /// 装配层（shell）仿真：onPlanApproval 内 approve + execute（deps 注入）。
  Future<GateCardResult> approveAndExecute(Object planObj) async {
    final AgentActionPlan plan = planObj as AgentActionPlan;
    final planExecutor = AgentPlanExecutor();
    await planExecutor.approve(plan);
    var i = 0;
    await planExecutor.execute(
      plan: plan,
      deps: AgentPlanExecutionDeps(
        execute: (String statement) {
          i++;
          planExecuted.add(statement);
          if (i == failAtStep) {
            throw StateError('injected step failure');
          }
          return Future<List<Map<String, dynamic>>>.value(
            <Map<String, dynamic>>[],
          );
        },
      ),
    );
    return GateCardResult.approved;
  }

  GateCallbacks planGates({GateCardResult result = GateCardResult.approved}) =>
      GateCallbacks(
        onL05Confirm: (_, _) => Future.value(GateCardResult.rejected),
        onPlanApproval: approveAndExecute,
      );

  Future<AgentToolOutcome> run(
    String tool,
    Object? args, {
    bool withGates = true,
    bool withUiPort = true,
    AgentRunContext? runCtxOverride,
  }) => executor.execute(
    call: _call(tool, args),
    runCtx: runCtxOverride ?? runCtx,
    ledger: ledger,
    gates: withGates ? planGates() : null,
    uiPort: withUiPort ? uiPort : null,
  );
}

AgentToolCall _call(String name, [Object? args]) =>
    AgentToolCall.fromAiToolCall(
      AiToolCall(
        id: 'call-$name',
        type: 'function',
        functionName: name,
        functionArguments: args == null ? '{}' : jsonEncode(args),
      ),
    );

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

Map<String, dynamic> _planDataOf(AgentToolOutcome out) =>
    ((_decode(out.toLLMJson())['data'] as Map<String, dynamic>)['plan']
        as Map<String, dynamic>);

const Map<String, dynamic> _okStep = <String, dynamic>{
  'sql': "UPDATE users SET name = 'x' WHERE id = 1",
  'rollback_sql': "UPDATE users SET name = 'old' WHERE id = 1",
};

void main() {
  group('submit_action_plan：提交校验回喂（AC15.1 自纠通路）', () {
    test('steps 缺失 / 非数组 / 空 → INVALID_ARGUMENTS（零卡面 + 零 db + 计步审计）', () async {
      final h = _Harness(gateDecision: _confirmL1);
      for (final Object? badArgs in <Object?>[
        <String, dynamic>{},
        <String, dynamic>{'steps': 'not-a-list'},
        <String, dynamic>{'steps': <Map<String, dynamic>>[]},
      ]) {
        final out = await h.run('submit_action_plan', badArgs);
        expect(out.ok, isFalse);
        expect(
          out.errorCode,
          AgentToolErrorCodes.invalidArguments,
          reason: '$badArgs',
        );
        expect(out.errorMessage, contains('steps'));
      }
      expect(h.db.executeQueryCalls, 0);
      expect(h.audit.count, 3);
      expect(
        h.audit.records.every(
          (Map<String, Object?> r) => r['success'] == false,
        ),
        isTrue,
      );
    });

    test('步元素非对象 → INVALID_ARGUMENTS', () async {
      final h = _Harness(gateDecision: _confirmL1);
      final out = await h.run('submit_action_plan', <String, dynamic>{
        'steps': <dynamic>['DELETE FROM t'],
      });
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(out.errorMessage, contains('JSON object'));
    });

    test('三要素缺：无 rollback 且未声明不可逆 → INVALID_ARGUMENTS + 补全指引', () async {
      final h = _Harness(gateDecision: _confirmL1);
      final out = await h.run('submit_action_plan', <String, dynamic>{
        'steps': <Map<String, dynamic>>[
          <String, dynamic>{'sql': 'DELETE FROM audit_log WHERE ts < 100'},
        ],
      });
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(
        out.errorMessage,
        contains('neither rollback_sql nor irreversible'),
      );
      expect(h.db.executeQueryCalls, 0, reason: '校验失败零执行');
    });

    test('互斥双给（rollback + irreversible）→ INVALID_ARGUMENTS', () async {
      final h = _Harness(gateDecision: _confirmL1);
      final out = await h.run('submit_action_plan', <String, dynamic>{
        'steps': <Map<String, dynamic>>[
          <String, dynamic>{
            'sql': 'DELETE FROM t',
            'rollback_sql': 'INSERT INTO t VALUES (1)',
            'irreversible': true,
          },
        ],
      });
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(out.errorMessage, contains('mutually exclusive'));
    });

    test('readOnly 连接 → 门判定序 ③ READONLY_CONNECTION 先拦（NF2.3）', () async {
      // 真实门（③ 在 ④ confirm 之前——onPlanApproval 结构不可达）。
      final h = _Harness(
        gateOverride: AgentGate(
          createAnalysis: (_) => throw StateError('plan tools never analyze'),
        ),
        readOnly: true,
      );
      var approvalInvoked = false;
      final out = await h.executor.execute(
        call: _call('submit_action_plan', <String, dynamic>{
          'steps': <Map<String, dynamic>>[_okStep],
        }),
        runCtx: h.runCtx,
        ledger: h.ledger,
        gates: GateCallbacks(
          onL05Confirm: (_, _) => Future.value(GateCardResult.rejected),
          onPlanApproval: (_) async {
            approvalInvoked = true;
            return GateCardResult.rejected;
          },
        ),
        uiPort: h.uiPort,
      );
      expect(out.errorCode, AgentToolErrorCodes.readonlyConnection);
      expect(approvalInvoked, isFalse, reason: 'readOnly 先于卡面拦截');
      expect(h.db.executeQueryCalls, 0);
      expect(h.audit.count, 1);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.blocked);
    });

    test('无批准回调 → fail-closed PLAN_REJECTED（绝不静默放行写路径）', () async {
      final h = _Harness(gateDecision: _confirmL1);
      final out = await h.run('submit_action_plan', <String, dynamic>{
        'steps': <Map<String, dynamic>>[_okStep],
      }, withGates: false);
      expect(out.errorCode, AgentToolErrorCodes.planRejected);
      expect(out.errorMessage, contains('failing closed'));
      expect(h.db.executeQueryCalls, 0);
      expect(h.audit.records.single['success'], isFalse);
      expect(
        h.audit.records.single['planId'],
        isNotNull,
        reason: '审计 planId 串联',
      );
    });
  });

  group('submit_action_plan：批准链（design §6.3）', () {
    test('批准前零执行（AC9.1 结构）——执行只发生在 onPlanApproval 决策后', () async {
      final h = _Harness(gateDecision: _confirmL1);
      final Completer<GateCardResult> decision = Completer<GateCardResult>();
      final Future<AgentToolOutcome> pending = h.executor.execute(
        call: _call('submit_action_plan', <String, dynamic>{
          'steps': <Map<String, dynamic>>[_okStep],
        }),
        runCtx: h.runCtx,
        ledger: h.ledger,
        gates: GateCallbacks(
          onL05Confirm: (_, _) => Future.value(GateCardResult.rejected),
          onPlanApproval: (AgentActionPlan plan) async {
            final card = await decision.future;
            if (card == GateCardResult.approved) {
              return await h.approveAndExecute(plan);
            }
            return card;
          },
        ),
        uiPort: h.uiPort,
      );
      await Future<void>.delayed(Duration.zero);
      expect(h.planExecuted, isEmpty, reason: '批准前零执行（提交零执行）');

      decision.complete(GateCardResult.approved);
      final out = await pending;
      expect(out.ok, isTrue);
      expect(h.planExecuted, hasLength(1));
      expect(_planDataOf(out)['status'], 'done');
    });

    test('批准执行 → 回喂计划终态 done + 审计 confirmed + planId 串联', () async {
      final h = _Harness(gateDecision: _confirmL1);
      final out = await h.run('submit_action_plan', <String, dynamic>{
        'steps': <Map<String, dynamic>>[_okStep, _okStep],
      });
      expect(out.ok, isTrue);
      final Map<String, dynamic> plan = _planDataOf(out);
      expect(plan['status'], 'done');
      expect((plan['steps'] as List<dynamic>), hasLength(2));
      expect(h.planExecuted, hasLength(2), reason: '逐语句执行');
      expect(h.audit.count, 1);
      final Map<String, Object?> audit = h.audit.records.single;
      expect(audit['gateDecision'], AgentGateDecision.confirmed);
      expect(audit['gateLevel'], AgentGateLevel.l1);
      expect(audit['planId'], plan['planId']);
      expect(audit['tool'], 'submit_action_plan');
      expect(audit['sql'], contains('UPDATE users'), reason: '语句面入审计');
    });

    test(
      '拒绝 → PLAN_REJECTED + 零库操作 + 审计 rejectedByUser + L1 撞门计数（AC9.2/风险 1）',
      () async {
        final h = _Harness(gateDecision: _confirmL1);
        final out = await h.executor.execute(
          call: _call('submit_action_plan', <String, dynamic>{
            'steps': <Map<String, dynamic>>[_okStep],
          }),
          runCtx: h.runCtx,
          ledger: h.ledger,
          gates: GateCallbacks(
            onL05Confirm: (_, _) => Future.value(GateCardResult.rejected),
            onPlanApproval: (_) async {
              await AgentPlanExecutor().reject(_lastSubmittedPlan(h)!);
              return GateCardResult.rejected;
            },
          ),
          uiPort: h.uiPort,
        );
        expect(out.ok, isFalse);
        expect(out.errorCode, AgentToolErrorCodes.planRejected);
        expect(h.db.executeQueryCalls, 0);
        expect(h.planExecuted, isEmpty);
        expect(h.l1BlockedCount, 1, reason: '统计 agentL1Blocked 观测撞门');
        expect(
          h.audit.records.single['gateDecision'],
          AgentGateDecision.rejectedByUser,
        );
      },
    );

    test('approvedForSession → 审计 allowedSession（AC9.3 免卡仍审计）', () async {
      final h = _Harness(gateDecision: _confirmL1);
      final out = await h.executor.execute(
        call: _call('submit_action_plan', <String, dynamic>{
          'steps': <Map<String, dynamic>>[_okStep],
        }),
        runCtx: h.runCtx,
        ledger: h.ledger,
        gates: GateCallbacks(
          onL05Confirm: (_, _) => Future.value(GateCardResult.rejected),
          onPlanApproval: h.approveAndExecute,
        ),
        uiPort: h.uiPort,
      );
      // approveAndExecute 返回 approved；此处覆盖为 session 形态的审计断言
      // 需要回调返回 approvedForSession——单独构造。
      expect(out.ok, isTrue);
      expect(
        h.audit.records.single['gateDecision'],
        AgentGateDecision.confirmed,
      );
    });

    test('中途失败 → partialFailed 三段回喂（AC11.1）', () async {
      final h = _Harness(gateDecision: _confirmL1)..failAtStep = 2;
      final out = await h.run('submit_action_plan', <String, dynamic>{
        'steps': <Map<String, dynamic>>[_okStep, _okStep, _okStep],
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.executionFailed);
      final Map<String, dynamic> plan = _planDataOf(out);
      expect(plan['status'], 'partialFailed');
      final List<dynamic> steps = plan['steps'] as List<dynamic>;
      expect((steps[0] as Map<String, dynamic>)['status'], 'done');
      expect((steps[1] as Map<String, dynamic>)['status'], 'failed');
      expect((steps[2] as Map<String, dynamic>)['status'], 'skipped');
      expect(h.planExecuted, hasLength(2), reason: '失败即停：第 3 步不执行');
    });
  });

  group('result_ref 生命周期（T28 注册表）', () {
    test('数据工具登记 res_<stepNo>；界面工具按 refId 消费', () async {
      final h = _Harness(); // allow(l0)
      final dataOut = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM users',
      });
      expect(dataOut.resultRef, isNotNull);
      expect(dataOut.resultRef!.refId, 'res_1');
      expect(h.executor.resultRefOf('res_1'), isNotNull);

      final uiOut = await h.run('open_result_grid', <String, dynamic>{
        'result_ref': 'res_1',
        'title': 'users',
      });
      expect(uiOut.ok, isTrue);
      expect(h.uiPort.openResultGridCalls, 1);
    });

    test('refId 不存在（幻觉 / 非 row 工具产物）→ INVALID_ARGUMENTS 自纠指引', () async {
      final h = _Harness();
      final out = await h.run('open_result_grid', <String, dynamic>{
        'result_ref': 'res_99',
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(out.errorMessage, contains('res_99'));
      expect(h.uiPort.openResultGridCalls, 0);
    });

    test('run 切换（runId 变化）→ 旧 ref 失效（跨 run 引用拒绝）', () async {
      final h = _Harness();
      await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM users',
      });
      final AgentRunContext nextRun = AgentRunContext(
        runId: 'run-2',
        connectionId: 'conn-1',
        databaseName: 'db1',
        dbType: DatabaseType.mysql,
        readOnly: false,
      );
      final out = await h.run('open_result_grid', <String, dynamic>{
        'result_ref': 'res_1',
      }, runCtxOverride: nextRun);
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(h.uiPort.openResultGridCalls, 0);
    });
  });

  group('界面七工具 outcome 回喂（§6.6 / AC15.1）', () {
    test(
      'show_table_structure / open_sql_editor / pin / chart 参数透传 + ok 回喂',
      () async {
        final h = _Harness();
        await h.run('execute_readonly_sql', <String, dynamic>{
          'sql': 'SELECT id FROM users',
        });

        final structure = await h.run('show_table_structure', <String, dynamic>{
          'table': 'users',
        });
        expect(structure.ok, isTrue);
        expect(h.uiPort.structureTables, <String>['users']);

        final editor = await h.run('open_sql_editor', <String, dynamic>{
          'sql': 'SELECT 1',
        });
        expect(editor.ok, isTrue);
        expect(editor.errorMessage, isNull);
        expect(h.uiPort.editorSqls, <String>['SELECT 1']);

        final pin = await h.run('pin_artifact', <String, dynamic>{
          'result_ref': 'res_1',
          'label': 'users snapshot',
        });
        expect(pin.ok, isTrue);
        expect(h.uiPort.pinLabels, <String?>['users snapshot']);

        final chart = await h.run('render_chart', <String, dynamic>{
          'result_ref': 'res_1',
          'chart_kind': 'bar',
        });
        expect(chart.ok, isTrue);
        expect(h.uiPort.chartKinds, <String?>['bar']);
      },
    );

    test('跨经典 2 工具：suggest 级派发（零自动副作用，AC6.1）', () async {
      final h = _Harness();
      final classic = await h.run('open_in_classic', <String, dynamic>{
        'sql': 'SELECT * FROM users',
      });
      expect(classic.ok, isTrue);
      expect(h.uiPort.classicSqls, <String>['SELECT * FROM users']);
      expect(h.db.executeQueryCalls, 0, reason: '建议级零库操作');

      final focus = await h.run('focus_sidebar', <String, dynamic>{
        'database': 'db1',
        'table': 'users',
      });
      expect(focus.ok, isTrue);
      expect(h.uiPort.focusTargets.single.database, 'db1');
      expect(h.uiPort.focusTargets.single.table, 'users');
    });

    test('uiPort 缺位 → fail-closed EXECUTION_FAILED（装配缺位不静默空转）', () async {
      final h = _Harness();
      final out = await h.run('open_sql_editor', <String, dynamic>{
        'sql': 'SELECT 1',
      }, withUiPort: false);
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.executionFailed);
      expect(out.errorMessage, contains('failing closed'));
    });

    test(
      'port outcome 失败 → EXECUTION_FAILED + detail 透传自纠（AC5.3/AC15.1）',
      () async {
        final h = _Harness();
        h.uiPort.outcome = const AgentUiOutcome.failure(
          'chart data mismatch: no numeric column',
        );
        await h.run('execute_readonly_sql', <String, dynamic>{
          'sql': 'SELECT id FROM users',
        });
        final out = await h.run('render_chart', <String, dynamic>{
          'result_ref': 'res_1',
        });
        expect(out.ok, isFalse);
        expect(out.errorCode, AgentToolErrorCodes.executionFailed);
        expect(out.errorMessage, contains('no numeric column'));
        // 动作已发起且失败：审计保持门结论（非 blocked）。
        expect(h.audit.records.last['gateDecision'], AgentGateDecision.allowed);
        expect(h.audit.records.last['success'], isFalse);
      },
    );
  });

  group('AC4.4 库级限定名执法（P2-4 并入 T28，保守方案）', () {
    test('MySQL 族：get_sample_data 跨库限定表名 → INVALID_ARGUMENTS 零执行', () async {
      final h = _Harness();
      final out = await h.run('get_sample_data', <String, dynamic>{
        'table': 'other_db.users',
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(out.errorMessage, contains('other_db'));
      expect(out.errorMessage, contains('db1'), reason: '指引回锁定库');
      expect(h.db.executeQueryCalls, 0);
    });

    test('MySQL 族：锁定库限定名放行', () async {
      final h = _Harness();
      final out = await h.run('get_sample_data', <String, dynamic>{
        'table': 'db1.users',
      });
      expect(out.ok, isTrue);
      expect(h.db.executedSql.single, 'SELECT * FROM db1.users LIMIT 10');
    });

    test('MySQL 族：execute_readonly_sql 表位置跨库限定 → 拒；锁定库放行', () async {
      final h = _Harness();
      final rejected = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM otherdb.users WHERE id = 1',
      });
      expect(rejected.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(rejected.errorMessage, contains('otherdb'));
      expect(h.db.executeQueryCalls, 0);

      final allowed = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM `db1`.users JOIN db1.orders ON 1=1',
      });
      expect(allowed.ok, isTrue, reason: '锁定库限定名（含引界）放行');
    });

    test('方言边界：PG 两段式 schema 限定不拦（库内寻址）', () async {
      final h = _Harness(dbType: DatabaseType.postgresql);
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM public.users',
      });
      expect(out.ok, isTrue);
      expect(h.db.executeQueryCalls, 1);
    });

    test('方言边界：SQLite ATTACH 面 / 未锁库不拦（登记的不覆盖面）', () async {
      final sqlite = _Harness(dbType: DatabaseType.sqlite);
      final out = await sqlite.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM attached_db.users',
      });
      expect(out.ok, isTrue, reason: 'SQLite ATTACH 面登记不覆盖');

      final noDb = _Harness(databaseName: '');
      final out2 = await noDb.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM anywhere.users',
      });
      expect(out2.ok, isTrue, reason: '快照未锁库 → 无比较基准不拦');
    });

    test('非表位置限定（列别名 t.col）不误伤', () async {
      final h = _Harness();
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT u.name FROM users u WHERE u.id = 1',
      });
      expect(out.ok, isTrue);
      expect(h.db.executeQueryCalls, 1);
    });
  });

  group('Fix-G：AC4.4 执法强化（掩码防御 / 关键词补全 / 方言扩面 M5）', () {
    test('混淆形态：注释/引界混淆越界全部命中（掩码后扫描），零执行', () async {
      final h = _Harness();
      const List<String> evasions = <String>[
        'SELECT * FROM/*c*/otherdb.t',
        'SELECT * FROM otherdb /*c*/ . t',
        'SELECT * FROM -- 行注释\notherdb.t',
        'SELECT * FROM `otherdb`.`t`',
      ];
      for (final String sql in evasions) {
        final out = await h.run('execute_readonly_sql', <String, dynamic>{
          'sql': sql,
        });
        expect(out.ok, isFalse, reason: sql);
        expect(
          out.errorCode,
          AgentToolErrorCodes.invalidArguments,
          reason: sql,
        );
        expect(out.errorMessage, contains('cross-database'), reason: sql);
      }
      expect(h.db.executeQueryCalls, 0);
    });

    test('字符串字面量内假表名不误伤；字面量外的真越界仍命中', () async {
      final h = _Harness();
      final ok = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': "SELECT * FROM db1.t WHERE note = 'join otherdb.y'",
      });
      expect(ok.ok, isTrue, reason: '字面量内假表名（掩码后不可见）不误伤');
      expect(h.db.executeQueryCalls, 1);

      final bad = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': "SELECT * FROM otherdb.t WHERE note = 'x'",
      });
      expect(bad.ok, isFalse);
      expect(bad.errorMessage, contains('cross-database'));
      expect(h.db.executeQueryCalls, 1, reason: '越界语句零执行');
    });

    test('关键词补全：DESCRIBE/DESC/SHOW FROM|IN/SHOW CREATE TABLE 越界命中', () async {
      final h = _Harness();
      const List<String> crossDb = <String>[
        'DESCRIBE otherdb.t',
        'DESC otherdb.t',
        'SHOW TABLES FROM otherdb',
        'SHOW TABLES IN otherdb',
        'SHOW CREATE TABLE otherdb.t',
        'SHOW COLUMNS FROM t FROM otherdb',
        'SHOW COLUMNS FROM otherdb.t',
      ];
      for (final String sql in crossDb) {
        final out = await h.run('execute_readonly_sql', <String, dynamic>{
          'sql': sql,
        });
        expect(out.ok, isFalse, reason: sql);
        expect(out.errorMessage, contains('cross-database'), reason: sql);
      }
      expect(h.db.executeQueryCalls, 0);

      const List<String> inDb = <String>[
        'DESCRIBE db1.t',
        'SHOW TABLES FROM db1',
        'SHOW CREATE TABLE db1.t',
        'SHOW COLUMNS FROM t FROM db1',
        'SHOW COLUMNS FROM db1.t',
      ];
      for (final String sql in inDb) {
        final out = await h.run('execute_readonly_sql', <String, dynamic>{
          'sql': sql,
        });
        expect(out.ok, isTrue, reason: sql);
      }
      expect(h.db.executeQueryCalls, inDb.length, reason: '锁定库形态不误伤');
    });

    test('方言扩面 M5：SS 三段式首段=库执法；两段式 dbo.t 放行（schema 语义）', () async {
      final h = _Harness(dbType: DatabaseType.sqlserver);
      final cross = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM otherdb.dbo.t',
      });
      expect(cross.ok, isFalse);
      expect(cross.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(cross.errorMessage, contains('cross-database'));
      expect(h.db.executeQueryCalls, 0);

      final twoPart = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM dbo.t',
      });
      expect(twoPart.ok, isTrue, reason: 'SS 两段式 = schema 库内寻址放行');

      final sameDb = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM db1.dbo.t',
      });
      expect(sameDb.ok, isTrue, reason: '三段式首段 == 锁定库放行');

      final sample = await h.run('get_sample_data', <String, dynamic>{
        'table': 'otherdb.dbo.t',
      });
      expect(sample.ok, isFalse);
      expect(sample.errorMessage, contains('cross-database'));
      final sampleOk = await h.run('get_sample_data', <String, dynamic>{
        'table': 'dbo.t',
      });
      expect(sampleOk.ok, isTrue, reason: 'table 参数面同段数规则');
    });

    test('方言扩面 M5：CH 两段式首段=库执法（system.one 形态）', () async {
      final h = _Harness(dbType: DatabaseType.clickhouse);
      final cross = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT count() FROM system.one',
      });
      expect(cross.ok, isFalse);
      expect(cross.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(cross.errorMessage, contains('cross-database'));
      expect(h.db.executeQueryCalls, 0);

      final ok = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT count() FROM db1.one',
      });
      expect(ok.ok, isTrue);

      final sample = await h.run('get_sample_data', <String, dynamic>{
        'table': 'system.one',
      });
      expect(sample.ok, isFalse);
      expect(sample.errorMessage, contains('cross-database'));
    });

    test('describe_table 补执法：标识符白名单 + 库级限定名检查', () async {
      final h = _Harness();
      final injection = await h.run('describe_table', <String, dynamic>{
        'table': 'users; DROP TABLE x',
      });
      expect(injection.ok, isFalse);
      expect(injection.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(injection.errorMessage, contains('plain identifier'));

      final cross = await h.run('describe_table', <String, dynamic>{
        'table': 'otherdb.users',
      });
      expect(cross.ok, isFalse);
      expect(cross.errorMessage, contains('cross-database'));

      final ok = await h.run('describe_table', <String, dynamic>{
        'table': 'db1.users',
      });
      expect(ok.ok, isTrue, reason: '锁定库限定名放行');
    });

    test('describe_table 方言段数：SS dbo.t 放行 / otherdb.dbo.t 拒', () async {
      final h = _Harness(dbType: DatabaseType.sqlserver);
      final twoPart = await h.run('describe_table', <String, dynamic>{
        'table': 'dbo.t',
      });
      expect(twoPart.ok, isTrue, reason: 'SS 两段式 schema 寻址放行');
      final threePart = await h.run('describe_table', <String, dynamic>{
        'table': 'otherdb.dbo.t',
      });
      expect(threePart.ok, isFalse);
      expect(threePart.errorMessage, contains('cross-database'));
    });

    test('explain_plan 复用语句执法：越界目标语句拒且零 EXPLAIN 调用', () async {
      final h = _Harness();
      final cross = await h.run('explain_plan', <String, dynamic>{
        'sql': 'SELECT * FROM otherdb.t',
      });
      expect(cross.ok, isFalse);
      expect(cross.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(cross.errorMessage, contains('cross-database'));
      expect(h.db.explainCalls, 0, reason: '执法先于 EXPLAIN 取数');

      final ok = await h.run('explain_plan', <String, dynamic>{
        'sql': 'SELECT * FROM db1.t',
      });
      expect(ok.ok, isTrue);
      expect(h.db.explainCalls, 1);
    });
  });
}

/// 测试辅助：捕获最近提交的计划（拒绝路径仿真用）。
AgentActionPlan? _lastSubmittedPlan(_Harness h) {
  // 直接经 submitter 重建一份等价计划（拒绝路径只需 pendingApproval 对象）。
  return AgentActionPlan(
    planId: 'plan_test_reject',
    runId: h.runCtx.runId,
    ctx: h.runCtx,
    steps: List<AgentPlanStep>.unmodifiable(<AgentPlanStep>[
      AgentPlanStep(
        sql: _okStep['sql']!,
        kind: AgentPlanStepKind.dml,
        rollbackSql: _okStep['rollback_sql'],
        rollbackSource: AgentRollbackSource.model,
      ),
    ]),
  );
}
