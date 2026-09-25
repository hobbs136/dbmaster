// AgentGate + AgentRunContext 单测（T06 / design §4.2、D3、D12、D15）。
//
// 判定序 ①-⑤ 逐环 + 顺序不可换断言（①>② / ②>③ / ③>⑤）+ readOnly 锁档
// + 无上下文引导 + 放行短路 + A1 目录锁（find 不可寻址 → evaluate 不可达；
// l1/suggest 分支经注入全集 spec 完整测试，FC-5）。
//
// 读前分析经注入工厂构造（AC8.7；gate 不依赖 dbService，NF5.3）——本文件
// 以真 AgentGateAnalysis + mock getExplainPlan 驱动；分析内核自身的分支面
// 由 agent_gate_analysis_test.dart（T05）覆盖，此处只断言门对
// requiresConfirmation 的消费与判定序。

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/ai/agent/agent_gate.dart';
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show AgentGateAnalysis, ReadImpactAnalysis;
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show
        AgentGateLevel,
        AgentToolCategory,
        AgentToolCatalog,
        AgentToolErrorCodes,
        AgentToolSpec;

/// 可编程 EXPLAIN 取数 mock：记录调用次数与收到的 SQL，可切换返回/抛错
///（形态对齐 agent_gate_analysis_test.dart 的 _ExplainMock）。
class _ExplainMock {
  int callCount = 0;
  final List<String> receivedSql = <String>[];
  List<Map<String, dynamic>> data = const <Map<String, dynamic>>[];
  Object? throwOnCall;

  Future<List<Map<String, dynamic>>> call(String sql) {
    callCount++;
    receivedSql.add(sql);
    final Object? err = throwOnCall;
    if (err != null) throw err;
    return Future.value(data);
  }
}

/// 一行 MySQL EXPLAIN 数据（字段名对齐 mysql_gateway_adapter 返回）。
List<Map<String, dynamic>> _mysqlRow({
  required String type,
  int? rows,
  String? key,
  String? ref,
  String table = 'big_table',
}) => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 1,
    'select_type': 'SIMPLE',
    'table': table,
    'type': type,
    'possible_keys': null,
    'key': key,
    'key_len': null,
    'ref': ref,
    'rows': rows,
    'Extra': null,
  },
];

/// 构造被测 gate：工厂注入真 AgentGateAnalysis + mock 取数。
/// [onCreate] 观察工厂构造次数（无分析面工具不得构造分析）。
AgentGate _gate(
  _ExplainMock mock, {
  int threshold = 10000,
  void Function(AgentRunContext runCtx)? onCreate,
}) => AgentGate(
  createAnalysis: (AgentRunContext runCtx) {
    onCreate?.call(runCtx);
    return AgentGateAnalysis(
      getExplainPlan: mock.call,
      rowThreshold: threshold,
      dbType: runCtx.dbType,
    );
  },
);

/// run 快照（D15）。readOnly 由构造侧写入（快照语义），evaluate 只消费。
AgentRunContext _runCtx({
  String? connectionId = 'conn-1',
  bool readOnly = false,
  DatabaseType dbType = DatabaseType.mysql,
}) => AgentRunContext(
  runId: 'run-1',
  connectionId: connectionId,
  connectionName: connectionId == null ? null : '测试连接',
  databaseName: connectionId == null ? null : 'db1',
  dbType: dbType,
  readOnly: readOnly,
);

/// 从目录全集取真实 spec（注入测试面：A1 期 find 对 A2 工具返回 null，
/// 但判定逻辑按序完整实现——FC-5）。
AgentToolSpec _spec(String name) => AgentToolCatalog.specsFor(
  milestone: 2,
).firstWhere((AgentToolSpec s) => s.name == name);

/// 伪造 spec（目录外名字 / 篡改档位），用于①判存与防伪造断言。
AgentToolSpec _forgedSpec(
  String name, {
  AgentGateLevel level = AgentGateLevel.l0,
  AgentToolCategory category = AgentToolCategory.data,
}) => AgentToolSpec(
  name: name,
  description: 'forged',
  inputSchema: const <String, dynamic>{},
  category: category,
  gateLevel: level,
  requiresConnection: true,
  requiresDatabase: true,
  milestone: 1,
);

void main() {
  group('① 目录查找（UNKNOWN_TOOL，AC1.6/AC7.3）', () {
    test('目录外名字 → reject UNKNOWN_TOOL（level=l0 占位：目录外无声明档可引）', () async {
      final decision = await _gate(_ExplainMock()).evaluate(
        spec: _forgedSpec('drop_all_tables'),
        args: const <String, dynamic>{},
        runCtx: _runCtx(),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.reject);
      expect(decision.reasonCode, AgentToolErrorCodes.unknownTool);
      expect(decision.level, AgentGateLevel.l0);
      expect(decision.impact, isNull);
    });

    test('顺序①>②：目录外名字 + 无连接 + readOnly → 仍是 UNKNOWN_TOOL', () async {
      final decision = await _gate(_ExplainMock()).evaluate(
        spec: _forgedSpec('drop_all_tables'),
        args: const <String, dynamic>{},
        runCtx: _runCtx(connectionId: null, readOnly: true),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.reasonCode, AgentToolErrorCodes.unknownTool);
    });

    test(
      'T28 相位：find 对 plan/suggest/界面工具放行（A2 合龙后可寻址）',
      () {
        // A1 期「find 返回 null」断言随 activeMilestone=2 翻转（任务书预留切换点）。
        expect(AgentToolCatalog.find('submit_action_plan'), isNotNull);
        expect(AgentToolCatalog.find('open_in_classic'), isNotNull);
        expect(AgentToolCatalog.find('render_chart'), isNotNull);
        // 全集仍在（注入测试取材面；T28 切 activeMilestone=2 后 find 放行）。
        expect(
          AgentToolCatalog.specsFor(
            milestone: 2,
          ).any((AgentToolSpec s) => s.name == 'submit_action_plan'),
          isTrue,
        );
      },
    );

    test('防伪造：真实名字 + 篡改档位/类别 → 以目录权威 spec 判定（仍走 l0 读前分析）', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final decision = await _gate(mock).evaluate(
        spec: _forgedSpec(
          'execute_readonly_sql',
          level: AgentGateLevel.suggest,
          category: AgentToolCategory.uiClassicSuggest,
        ),
        args: const <String, dynamic>{
          'sql': 'SELECT * FROM big_table WHERE unindexed = 1',
        },
        runCtx: _runCtx(),
        ledger: AgentPermissionLedger(),
      );
      expect(
        decision.kind,
        GateDecisionKind.confirm,
        reason: '伪造 suggest 档不生效——按目录声明的 l0 走读前分析并命中',
      );
      expect(decision.level, AgentGateLevel.l05);
    });
  });

  group('② CONTEXT_REQUIRED（requiresConnection 且快照无连接，AC7.4）', () {
    test('execute_readonly_sql + 无连接 → reject CONTEXT_REQUIRED', () async {
      final decision = await _gate(_ExplainMock()).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{'sql': 'SELECT 1'},
        runCtx: _runCtx(connectionId: null),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.reject);
      expect(decision.reasonCode, AgentToolErrorCodes.contextRequired);
      expect(decision.level, AgentGateLevel.l0);
      expect(decision.impact, isNull);
    });

    test('空串 connectionId 同视为无上下文（对齐 T07 审计空串占位语义）', () async {
      final decision = await _gate(_ExplainMock()).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{'sql': 'SELECT 1'},
        runCtx: _runCtx(connectionId: ''),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.reasonCode, AgentToolErrorCodes.contextRequired);
    });

    test(
      '顺序②>③：plan 工具 + readOnly + 无连接 → CONTEXT_REQUIRED 而非 READONLY_CONNECTION',
      () async {
        final decision = await _gate(_ExplainMock()).evaluate(
          spec: _spec('submit_action_plan'),
          args: const <String, dynamic>{},
          runCtx: _runCtx(connectionId: null, readOnly: true),
          ledger: AgentPermissionLedger(),
        );
        expect(decision.reasonCode, AgentToolErrorCodes.contextRequired);
      },
    );

    test('get_current_context 不要求连接：无连接 → allow（AC7.4 纯对话可用）', () async {
      final mock = _ExplainMock();
      final decision = await _gate(mock).evaluate(
        spec: _spec('get_current_context'),
        args: const <String, dynamic>{},
        runCtx: _runCtx(connectionId: null),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.allow);
      expect(decision.level, AgentGateLevel.l0);
      expect(mock.callCount, 0);
    });
  });

  group('③ READONLY_CONNECTION（readOnly × 写形态动作，NF2.3）', () {
    test(
      'readOnly + submit_action_plan（注入 spec）→ reject READONLY_CONNECTION（level=l1）',
      () async {
        final decision = await _gate(_ExplainMock()).evaluate(
          spec: _spec('submit_action_plan'),
          args: const <String, dynamic>{},
          runCtx: _runCtx(readOnly: true),
          ledger: AgentPermissionLedger(),
        );
        expect(decision.kind, GateDecisionKind.reject);
        expect(decision.reasonCode, AgentToolErrorCodes.readonlyConnection);
        expect(decision.level, AgentGateLevel.l1);
        expect(decision.impact, isNull);
      },
    );

    test('readOnly + 数据工具不受限：execute_readonly_sql 照常进读前分析', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final decision = await _gate(mock).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{'sql': 'SELECT * FROM big_table'},
        runCtx: _runCtx(readOnly: true),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.confirm);
      expect(decision.level, AgentGateLevel.l05);
    });

    test('readOnly + 元数据工具不受限：list_tables → allow 且零分析', () async {
      final mock = _ExplainMock();
      final decision = await _gate(mock).evaluate(
        spec: _spec('list_tables'),
        args: const <String, dynamic>{},
        runCtx: _runCtx(readOnly: true),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.allow);
      expect(mock.callCount, 0);
    });

    test('顺序③>⑤：readOnly + plan + 两集账本命中 → 仍 READONLY_CONNECTION', () async {
      final ledger = AgentPermissionLedger()
        ..allowL05('conn-1')
        ..allowL1('conn-1');
      final decision = await _gate(_ExplainMock()).evaluate(
        spec: _spec('submit_action_plan'),
        args: const <String, dynamic>{},
        runCtx: _runCtx(readOnly: true),
        ledger: ledger,
      );
      expect(decision.reasonCode, AgentToolErrorCodes.readonlyConnection);
    });
  });

  group('④ 档判定 · l0 数据读取（读前分析，D6/T05）', () {
    test('全表扫描大表 → confirm(l05)，impact 携带确认卡数据（AC8.4）', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final decision = await _gate(mock).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{
          'sql': 'SELECT * FROM big_table WHERE unindexed = 1',
        },
        runCtx: _runCtx(),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.confirm);
      expect(decision.level, AgentGateLevel.l05);
      expect(decision.reasonCode, isNull);
      final ReadImpactAnalysis? impact = decision.impact;
      expect(impact, isNotNull);
      expect(impact?.estimatedRows, 800000);
      expect(impact?.fullScan, isTrue);
      expect(impact?.analysisUnavailable, isFalse);
      expect(impact?.scannedTables, <String>['big_table']);
    });

    test('命中索引小范围 → allow(l0)，impact 不携带（确认卡是唯一消费面）', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(type: 'ref', rows: 500, key: 'idx_status');
      final decision = await _gate(mock).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{
          'sql': 'SELECT id FROM big_table WHERE status = 1',
        },
        runCtx: _runCtx(),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.allow);
      expect(decision.level, AgentGateLevel.l0);
      expect(decision.impact, isNull);
    });

    test('豁免消解（X1 主键点查，§8）→ allow(l0)', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(
          type: 'const',
          rows: 1,
          key: 'PRIMARY',
          ref: 'const',
          table: 'users',
        );
      final decision = await _gate(mock).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{
          'sql': 'SELECT * FROM users WHERE id = 42',
        },
        runCtx: _runCtx(),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.allow);
      expect(decision.level, AgentGateLevel.l0);
    });

    test('R10 独立信号（索引命中但超阈值）→ confirm(l05)，fullScan=false 仍需确认', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(type: 'ref', rows: 50000, key: 'idx_status');
      final decision = await _gate(mock).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{
          'sql': 'SELECT id FROM big_table WHERE status = 1',
        },
        runCtx: _runCtx(),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.confirm);
      expect(decision.level, AgentGateLevel.l05);
      expect(decision.impact?.fullScan, isFalse);
    });

    test(
      '分析不可用（EXPLAIN 抛不支持）→ confirm(l05) 且 impact.analysisUnavailable（fail-closed 穿透门，AC8.6）',
      () async {
        final mock = _ExplainMock()
          ..throwOnCall = UnsupportedError('EXPLAIN unsupported via gateway');
        final decision = await _gate(mock).evaluate(
          spec: _spec('execute_readonly_sql'),
          args: const <String, dynamic>{'sql': 'SELECT * FROM big_table'},
          runCtx: _runCtx(),
          ledger: AgentPermissionLedger(),
        );
        expect(decision.kind, GateDecisionKind.confirm);
        expect(decision.level, AgentGateLevel.l05);
        expect(decision.impact?.analysisUnavailable, isTrue);
        expect(decision.impact?.estimatedRows, isNull);
      },
    );

    test(
      '非 SELECT 语句（写语句）→ allow(l0)：只读通道拦截在 executor handler（design §4.1，门只管权限面）',
      () async {
        final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 1);
        final decision = await _gate(mock).evaluate(
          spec: _spec('execute_readonly_sql'),
          args: const <String, dynamic>{'sql': "UPDATE users SET name = 'x'"},
          runCtx: _runCtx(),
          ledger: AgentPermissionLedger(),
        );
        expect(decision.kind, GateDecisionKind.allow);
        expect(decision.level, AgentGateLevel.l0);
        expect(mock.callCount, 0, reason: 'UPDATE 不进 EXPLAIN 分析（T05 语句范围）');
      },
    );

    test(
      '元数据/上下文类 l0 工具零分析：list_tables / describe_table / explain_plan → allow 且工厂零构造',
      () async {
        final mock = _ExplainMock();
        var factoryCalls = 0;
        final gate = _gate(mock, onCreate: (_) => factoryCalls++);
        final ledger = AgentPermissionLedger();
        for (final String name in <String>[
          'list_tables',
          'describe_table',
          'explain_plan',
        ]) {
          final decision = await gate.evaluate(
            spec: _spec(name),
            args: const <String, dynamic>{},
            runCtx: _runCtx(),
            ledger: ledger,
          );
          expect(decision.kind, GateDecisionKind.allow, reason: name);
          expect(decision.level, AgentGateLevel.l0, reason: name);
        }
        expect(factoryCalls, 0);
        expect(mock.callCount, 0);
      },
    );

    test(
      '参数缺形：sql 缺失 / 非 String → allow(l0) 且零分析（INVALID_ARGUMENTS 是 T10 handler 职责）',
      () async {
        final mock = _ExplainMock();
        var factoryCalls = 0;
        final gate = _gate(mock, onCreate: (_) => factoryCalls++);
        final missing = await gate.evaluate(
          spec: _spec('execute_readonly_sql'),
          args: const <String, dynamic>{},
          runCtx: _runCtx(),
          ledger: AgentPermissionLedger(),
        );
        final wrongType = await gate.evaluate(
          spec: _spec('execute_readonly_sql'),
          args: const <String, dynamic>{'sql': 42},
          runCtx: _runCtx(),
          ledger: AgentPermissionLedger(),
        );
        expect(missing.kind, GateDecisionKind.allow);
        expect(wrongType.kind, GateDecisionKind.allow);
        expect(factoryCalls, 0);
      },
    );

    test('get_sample_data：按 args 构造分析 SQL（SELECT * FROM t LIMIT n）', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(type: 'ALL', rows: 500, table: 'orders');
      final decision = await _gate(mock).evaluate(
        spec: _spec('get_sample_data'),
        args: const <String, dynamic>{'table': 'orders'},
        runCtx: _runCtx(),
        ledger: AgentPermissionLedger(),
      );
      expect(mock.receivedSql.last, 'SELECT * FROM orders LIMIT 10');
      expect(decision.kind, GateDecisionKind.allow, reason: '500 行低于阈值 10,000');
    });

    test(
      'get_sample_data：LIMIT 归一化——缺省 10 / 越界 clamp 100 / 字符串 20 / 0 clamp 1',
      () async {
        final mock = _ExplainMock()
          ..data = _mysqlRow(type: 'ALL', rows: 5, table: 't');
        final gate = _gate(mock);
        final ledger = AgentPermissionLedger();
        Future<String> lastSql(Map<String, dynamic> args) async {
          await gate.evaluate(
            spec: _spec('get_sample_data'),
            args: args,
            runCtx: _runCtx(),
            ledger: ledger,
          );
          return mock.receivedSql.last;
        }

        expect(
          await lastSql(const <String, dynamic>{'table': 't', 'limit': 500}),
          'SELECT * FROM t LIMIT 100',
        );
        expect(
          await lastSql(const <String, dynamic>{'table': 't', 'limit': '20'}),
          'SELECT * FROM t LIMIT 20',
        );
        expect(
          await lastSql(const <String, dynamic>{'table': 't', 'limit': 0}),
          'SELECT * FROM t LIMIT 1',
        );
        expect(
          await lastSql(const <String, dynamic>{'table': 't'}),
          'SELECT * FROM t LIMIT 10',
        );
      },
    );
  });

  group('④ 档判定 · plan(l1)——A1 目录无此工具，注入测试判定逻辑完整（FC-5）', () {
    test(
      'submit_action_plan（注入 spec）→ confirm(l1)，impact/reasonCode 皆空',
      () async {
        final decision = await _gate(_ExplainMock()).evaluate(
          spec: _spec('submit_action_plan'),
          args: const <String, dynamic>{},
          runCtx: _runCtx(),
          ledger: AgentPermissionLedger(),
        );
        expect(decision.kind, GateDecisionKind.confirm);
        expect(decision.level, AgentGateLevel.l1);
        expect(decision.reasonCode, isNull);
        expect(decision.impact, isNull);
      },
    );

    test(
      'l1 无会话放行短路：账本 l05/l1 命中仍 confirm(l1)（L1 放行在 executor 计划链路，T28/AC9.3）',
      () async {
        final ledger = AgentPermissionLedger()
          ..allowL05('conn-1')
          ..allowL1('conn-1');
        final decision = await _gate(_ExplainMock()).evaluate(
          spec: _spec('submit_action_plan'),
          args: const <String, dynamic>{},
          runCtx: _runCtx(),
          ledger: ledger,
        );
        expect(decision.kind, GateDecisionKind.confirm);
        expect(decision.level, AgentGateLevel.l1);
      },
    );
  });

  group('④ 档判定 · suggest → allow（派发为建议卡，用户点击才是执行）', () {
    test('open_in_classic（注入 spec）→ allow，level=suggest，零分析', () async {
      final mock = _ExplainMock();
      var factoryCalls = 0;
      final decision = await _gate(mock, onCreate: (_) => factoryCalls++)
          .evaluate(
            spec: _spec('open_in_classic'),
            args: const <String, dynamic>{'sql': 'SELECT 1'},
            runCtx: _runCtx(),
            ledger: AgentPermissionLedger(),
          );
      expect(decision.kind, GateDecisionKind.allow);
      expect(decision.level, AgentGateLevel.suggest);
      expect(factoryCalls, 0);
      expect(mock.callCount, 0);
    });
  });

  group('⑤ 会话放行短路（D12 账本 / AC8.5）', () {
    test(
      'confirm(l05) 候选 + l05 账本命中同连接 → allow 且 level=l05（allowed_session 审计判据唯一源）',
      () async {
        final mock = _ExplainMock()
          ..data = _mysqlRow(type: 'ALL', rows: 800000);
        final ledger = AgentPermissionLedger()..allowL05('conn-1');
        final decision = await _gate(mock).evaluate(
          spec: _spec('execute_readonly_sql'),
          args: const <String, dynamic>{'sql': 'SELECT * FROM big_table'},
          runCtx: _runCtx(),
          ledger: ledger,
        );
        expect(decision.kind, GateDecisionKind.allow);
        expect(
          decision.level,
          AgentGateLevel.l05,
          reason: 'allow@l05 ⟺ allowed_session（evaluate 内唯一产生源是⑤）',
        );
        expect(decision.impact, isNull);
        expect(mock.callCount, 1, reason: '短路发生在分析之后——分析照常执行');
      },
    );

    test('账本只含其它连接 → 仍 confirm(l05)（放行键 = connectionId，粒度 AC8.5）', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final ledger = AgentPermissionLedger()..allowL05('conn-other');
      final decision = await _gate(mock).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{'sql': 'SELECT * FROM big_table'},
        runCtx: _runCtx(),
        ledger: ledger,
      );
      expect(decision.kind, GateDecisionKind.confirm);
      expect(decision.level, AgentGateLevel.l05);
    });

    test('分析干净时账本命中不产生 allow@l05（level 仍 l0——短路只在 confirm 候选上发生）', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(type: 'ref', rows: 500, key: 'idx_status');
      final ledger = AgentPermissionLedger()..allowL05('conn-1');
      final decision = await _gate(mock).evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{
          'sql': 'SELECT id FROM big_table WHERE status = 1',
        },
        runCtx: _runCtx(),
        ledger: ledger,
      );
      expect(decision.kind, GateDecisionKind.allow);
      expect(decision.level, AgentGateLevel.l0);
    });
  });

  group('evaluate 无状态与快照语义（NF5.3 / D15）', () {
    test('同一 gate 实例先后消费不同 runCtx 快照，判定各自独立（依赖全注入，不持运行态）', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final gate = _gate(mock);
      final ledger = AgentPermissionLedger();
      final readOnlyReject = await gate.evaluate(
        spec: _spec('submit_action_plan'),
        args: const <String, dynamic>{},
        runCtx: _runCtx(readOnly: true),
        ledger: ledger,
      );
      final normalConfirm = await gate.evaluate(
        spec: _spec('submit_action_plan'),
        args: const <String, dynamic>{},
        runCtx: _runCtx(readOnly: false),
        ledger: ledger,
      );
      final noContext = await gate.evaluate(
        spec: _spec('execute_readonly_sql'),
        args: const <String, dynamic>{'sql': 'SELECT 1'},
        runCtx: _runCtx(connectionId: null),
        ledger: ledger,
      );
      expect(readOnlyReject.reasonCode, AgentToolErrorCodes.readonlyConnection);
      expect(normalConfirm.kind, GateDecisionKind.confirm);
      expect(noContext.reasonCode, AgentToolErrorCodes.contextRequired);
    });

    test('AgentRunContext 不可变快照字段（D15：构造侧写入 readOnly，含可空性）', () {
      const AgentRunContext ctx = AgentRunContext(
        runId: 'r',
        dbType: DatabaseType.postgresql,
        readOnly: true,
      );
      expect(ctx.connectionId, isNull);
      expect(ctx.connectionName, isNull);
      expect(ctx.databaseName, isNull);
      expect(ctx.dbType, DatabaseType.postgresql);
      expect(ctx.readOnly, isTrue);
    });
  });
}
