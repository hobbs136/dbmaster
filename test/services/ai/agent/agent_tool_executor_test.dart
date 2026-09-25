// AgentToolExecutor 单测（T10 / design-ai-agent.md D3、D10、D19、§4.1、§5.2）。
//
// 覆盖任务书清单：逐工具正常/错误路径、拦截零执行（D3/AC15.3/AC4.2）、
// 计步含被拒（D10/AC2.3）、审计每调用一条（AC13.1，拦截/人拒也落）、
// 回喂格式与 D19 双上限、§5.2 步消息结构、L0.5 confirm 链（D7）、
// 真实 AgentGate + AgentGateAnalysis 的 ①-⑤ 全链集成。
//
// 依赖全注入（NF5.3）：db 访问 / 审计 / 统计均为 spy 闭包；门用
// _ScriptedGate（可编程判定）驱动链路分支，真实门的判定序分支由
// agent_gate_test.dart（T06）覆盖，此处另设「真实门集成」组验证链完整性。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/ai_message_type.dart' show AiMessageType;
import 'package:dbmaster/models/ai_models.dart' show AiToolCall;
import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbColumn, DbIndex, ForeignKey;
import 'package:dbmaster/services/ai/agent/agent_gate.dart';
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show AgentGateAnalysis, ReadImpactAnalysis;
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolErrorCodes, AgentToolSpec;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show GateCardResult;
import 'package:dbmaster/services/workbench_usage_stats_service.dart'
    show AgentL05Stat;

// ── fakes / spies ───────────────────────────────────────────────────────────

/// dbService 访问 spy：计数 + 记录收到的 SQL/连接/库，可编程返回/抛错。
class _DbSpy {
  int executeQueryCalls = 0;
  final List<String> executedSql = <String>[];
  final List<String?> executeConnectionIds = <String?>[];
  final List<String?> executeDatabases = <String?>[];
  List<Map<String, dynamic>> queryResult = <Map<String, dynamic>>[];
  Object? queryError;

  int explainCalls = 0;
  final List<String> explainedSql = <String>[];
  List<Map<String, dynamic>> explainResult = <Map<String, dynamic>>[];
  Object? explainError;

  int tablesCalls = 0;
  List<String> tables = <String>[];

  int columnsCalls = 0;
  List<DbColumn> columns = <DbColumn>[];
  int indexesCalls = 0;
  List<DbIndex> indexes = <DbIndex>[];
  Object? indexesError;
  int foreignKeysCalls = 0;
  List<ForeignKey> foreignKeys = <ForeignKey>[];
  int createTableSqlCalls = 0;
  String createTableSql = 'CREATE TABLE `users` (...)';
  Object? createTableSqlError;
}

AgentDbAccess _access(_DbSpy spy) => AgentDbAccess(
  getTables: (String? connectionId) async {
    spy.tablesCalls++;
    return spy.tables;
  },
  getTableColumns:
      (String tableName, {String? connectionId, String? databaseName}) async {
        spy.columnsCalls++;
        return spy.columns;
      },
  getTableIndexes:
      (String tableName, {String? connectionId, String? databaseName}) async {
        spy.indexesCalls++;
        final Object? err = spy.indexesError;
        if (err != null) throw err;
        return spy.indexes;
      },
  getForeignKeys:
      (String tableName, {String? connectionId, String? databaseName}) async {
        spy.foreignKeysCalls++;
        return spy.foreignKeys;
      },
  getCreateTableSql:
      (String tableName, {String? connectionId, String? databaseName}) async {
        spy.createTableSqlCalls++;
        final Object? err = spy.createTableSqlError;
        if (err != null) throw err;
        return spy.createTableSql;
      },
  getExplainPlan: (String sql, {String? connectionId}) async {
    spy.explainCalls++;
    spy.explainedSql.add(sql);
    final Object? err = spy.explainError;
    if (err != null) throw err;
    return spy.explainResult;
  },
  executeQuery: (String sql, {String? connectionId, String? database}) async {
    spy.executeQueryCalls++;
    spy.executedSql.add(sql);
    spy.executeConnectionIds.add(connectionId);
    spy.executeDatabases.add(database);
    final Object? err = spy.queryError;
    if (err != null) throw err;
    return spy.queryResult;
  },
);

/// 审计 spy（签名 = AgentAuditRecorder）。断言「每调用一条」与字段形态。
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
      'connectionName': connectionName,
      'databaseName': databaseName,
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

/// 统计 spy：工具调用分桶 + L0.5 卡事件。
class _StatsSpy {
  final List<String> toolCalls = <String>[];
  final List<AgentL05Stat> l05Events = <AgentL05Stat>[];
}

/// 可编程门（真 AgentGate 子类覆写 evaluate）：链路分支驱动用。
class _ScriptedGate extends AgentGate {
  _ScriptedGate(this.decision)
    : super(
        createAnalysis: (_) => throw StateError('scripted gate never analyzes'),
      );

  GateDecision decision;
  int evaluateCalls = 0;

  @override
  Future<GateDecision> evaluate({
    required AgentToolSpec spec,
    required Map<String, dynamic> args,
    required AgentRunContext runCtx,
    required AgentPermissionLedger ledger,
  }) async {
    evaluateCalls++;
    return decision;
  }
}

/// 可编程 EXPLAIN 取数 mock（形态对齐 agent_gate_test.dart 的 _ExplainMock）。
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
List<Map<String, dynamic>> _mysqlExplainRow({
  required String type,
  int? rows,
  String? key,
}) => <Map<String, dynamic>>[
  <String, dynamic>{
    'id': 1,
    'select_type': 'SIMPLE',
    'table': 'big_table',
    'type': type,
    'possible_keys': null,
    'key': key,
    'key_len': null,
    'ref': null,
    'rows': rows,
    'Extra': null,
  },
];

const GateDecision _allowL0 = GateDecision(
  kind: GateDecisionKind.allow,
  level: AgentGateLevel.l0,
);

/// 测试台：spy + 可编程门 + confirm 回调。真实门用 [gateOverride] 注入。
class _Harness {
  _Harness({
    GateDecision gateDecision = _allowL0,
    AgentGate? gateOverride,
    DatabaseType dbType = DatabaseType.mysql,
    String? connectionId = 'conn-1',
  }) : gate = gateOverride ?? _ScriptedGate(gateDecision) {
    runCtx = AgentRunContext(
      runId: 'run-1',
      connectionId: connectionId,
      connectionName: connectionId == null ? null : '测试连接',
      databaseName: connectionId == null ? null : 'db1',
      dbType: dbType,
      readOnly: false,
    );
    executor = AgentToolExecutor(
      gate: gate,
      db: _access(db),
      audit: audit.record,
      recordToolCall: stats.toolCalls.add,
      recordL05Event: stats.l05Events.add,
    );
  }

  final _DbSpy db = _DbSpy();
  final _AuditSpy audit = _AuditSpy();
  final _StatsSpy stats = _StatsSpy();
  final AgentPermissionLedger ledger = AgentPermissionLedger();
  late final AgentRunContext runCtx;
  final AgentGate gate;
  late final AgentToolExecutor executor;

  GateCardResult confirmResult = GateCardResult.approved;
  ReadImpactAnalysis? seenImpact;
  String? seenConfirmSql;
  bool confirmInvoked = false;

  GateCallbacks get gates => GateCallbacks(
    onL05Confirm: (ReadImpactAnalysis impact, String sql) async {
      confirmInvoked = true;
      seenImpact = impact;
      seenConfirmSql = sql;
      return confirmResult;
    },
    onPlanApproval: (Object plan) async => GateCardResult.rejected,
  );

  Future<AgentToolOutcome> run(
    String tool, [
    Object? args,
    bool withGates = true,
  ]) => executor.execute(
    call: _call(tool, args),
    runCtx: runCtx,
    ledger: ledger,
    gates: withGates ? gates : null,
  );
}

/// 工具调用（[args] 为 Map 时 JSON 编码；String 原样（畸形 JSON 用例）；缺省 {}）。
AgentToolCall _call(String name, [Object? args]) => AgentToolCall(
  id: 'call-$name',
  name: name,
  argumentsJson: args == null
      ? '{}'
      : args is String
      ? args
      : jsonEncode(args),
);

Map<String, dynamic> _decode(String json) =>
    jsonDecode(json) as Map<String, dynamic>;

/// 步消息 agent 载荷（§5.2）。
Map<String, dynamic> _agentPayload(AgentToolOutcome out) {
  final Map<String, dynamic> data =
      out.resultMessage.toolResultData ?? const <String, dynamic>{};
  return data['agent'] as Map<String, dynamic>;
}

void main() {
  group('链头：目录查找（AC1.6）与参数收窄（D4）', () {
    test('目录外工具 → UNKNOWN_TOOL + 审计 blocked + 零 db 访问 + 计步', () async {
      final h = _Harness();
      final out = await h.run('totally_fake_tool');

      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.unknownTool);
      expect(h.db.executeQueryCalls, 0);
      expect(h.db.tablesCalls, 0);
      expect(h.executor.stepsUsed, 1);
      // 审计：拦截尝试也落（AC13.1），gateLevel 无声明档可引 → null。
      expect(h.audit.count, 1);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.blocked);
      expect(h.audit.records.single['gateLevel'], isNull);
      expect(h.audit.records.single['success'], isFalse);
      expect(h.audit.records.single['runId'], 'run-1');
      // 步消息对仍完整（拦截不是空气泡）。
      expect(out.callMessage.toolName, 'totally_fake_tool');
      expect(out.resultMessage.type, AiMessageType.toolResult);
      // 目录外名字不进统计白名单。
      expect(h.stats.toolCalls, isEmpty);
    });

    test('T28 相位：submit_action_plan 可寻址且入 l1 计划链（无卡 UI → '
        'fail-closed PLAN_REJECTED）', () async {
      final h = _Harness(
        gateDecision: const GateDecision(
          kind: GateDecisionKind.confirm,
          level: AgentGateLevel.l1,
        ),
      );
      final out = await h.run('submit_action_plan', <String, dynamic>{
        'steps': <Map<String, dynamic>>[
          <String, dynamic>{'sql': 'DELETE FROM t', 'irreversible': true},
        ],
      }, false);
      // A1 期「不可寻址 → UNKNOWN_TOOL」断言随 milestone 2 合龙翻转：
      // 提交校验过后无批准回调（withGates=false）→ fail-closed 拒绝，零库操作。
      expect(out.errorCode, AgentToolErrorCodes.planRejected);
      expect(h.db.executeQueryCalls, 0);
    });

    test('畸形 JSON 参数 → INVALID_ARGUMENTS（链内计步 + 审计）', () async {
      final h = _Harness();
      final out = await h.run('list_tables', 'not json {{{');

      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(h.db.tablesCalls, 0);
      expect(h.executor.stepsUsed, 1);
      expect(h.audit.count, 1);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.blocked);
    });

    test('参数非 JSON 对象（数组）→ INVALID_ARGUMENTS', () async {
      final h = _Harness();
      final out = await h.run('list_tables', '[1, 2, 3]');
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(h.db.tablesCalls, 0);
    });

    test('缺必填参数 / 类型不符 → INVALID_ARGUMENTS', () async {
      final h = _Harness();
      final noSql = await h.run('execute_readonly_sql', <String, dynamic>{});
      expect(noSql.errorCode, AgentToolErrorCodes.invalidArguments);

      final notString = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 42,
      });
      expect(notString.errorCode, AgentToolErrorCodes.invalidArguments);

      final noTable = await h.run('describe_table', <String, dynamic>{});
      expect(noTable.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(h.executor.stepsUsed, 3);
      expect(h.db.executeQueryCalls, 0);
      expect(h.db.columnsCalls, 0);
    });
  });

  group('六工具正常路径', () {
    test('list_tables：表清单 + 审计 allowed + 统计分桶', () async {
      final h = _Harness()..db.tables = <String>['users', 'orders', 'invoices'];
      final out = await h.run('list_tables');

      expect(out.ok, isTrue);
      expect(h.db.tablesCalls, 1);
      final feed = _decode(out.toLLMJson());
      expect(feed['ok'], isTrue);
      expect((feed['data'] as Map<String, dynamic>)['tables'], <String>[
        'users',
        'orders',
        'invoices',
      ]);
      expect(feed['rowCount'], 3);
      expect(out.resultRef, isNull); // 非 row 形态
      expect(h.audit.count, 1);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.allowed);
      expect(h.audit.records.single['gateLevel'], AgentGateLevel.l0);
      expect(h.audit.records.single['sql'], isNull);
      expect(h.stats.toolCalls, <String>['list_tables']);
    });

    test('describe_table：列/索引/外键/DDL 齐备，方言缺面如实置 null', () async {
      final h = _Harness()
        ..db.columns = <DbColumn>[
          DbColumn(
            name: 'id',
            type: 'int',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'name', type: 'varchar(50)'),
        ]
        ..db.indexes = <DbIndex>[
          DbIndex(name: 'PRIMARY', columns: <String>['id'], isUnique: true),
        ]
        ..db.foreignKeys = <ForeignKey>[]
        ..db.createTableSqlError = UnsupportedError('no ddl');
      final out = await h.run('describe_table', <String, dynamic>{
        'table': 'users',
      });

      expect(out.ok, isTrue);
      final data = _decode(out.toLLMJson())['data'] as Map<String, dynamic>;
      expect((data['columns'] as List<dynamic>).length, 2);
      expect(
        ((data['columns'] as List<dynamic>).first
            as Map<String, dynamic>)['isPrimaryKey'],
        isTrue,
      );
      expect((data['indexes'] as List<dynamic>).length, 1);
      expect(data['foreignKeys'], isEmpty);
      expect(data['createTableSql'], isNull); // 方言差异如实
      expect(h.db.columnsCalls, 1);
      expect(h.db.indexesCalls, 1);
      expect(h.db.createTableSqlCalls, 1);
    });

    test('get_sample_data：默认 LIMIT 10 + 同形 SQL + resultRef + 回喂形态', () async {
      final h = _Harness()
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'name': 'a'},
          <String, dynamic>{'id': 2, 'name': 'b'},
        ];
      final out = await h.run('get_sample_data', <String, dynamic>{
        'table': 'users',
      });

      expect(out.ok, isTrue);
      expect(h.db.executedSql.single, 'SELECT * FROM users LIMIT 10');
      expect(h.db.executeConnectionIds.single, 'conn-1');
      expect(h.db.executeDatabases.single, 'db1');

      final feed = _decode(out.toLLMJson());
      expect(feed['ok'], isTrue);
      expect(feed['rowCount'], 2);
      expect(feed['columns'], <String>['id', 'name']);
      expect((feed['data'] as Map<String, dynamic>)['result_ref'], 'res_1');
      expect(
        ((feed['data'] as Map<String, dynamic>)['rows'] as List<dynamic>)
            .length,
        2,
      );

      expect(out.resultRef, isNotNull);
      expect(out.resultRef?.refId, 'res_1');
      expect(out.resultRef?.rowCount, 2);
      expect(out.resultRef?.sql, 'SELECT * FROM users LIMIT 10');

      // 审计 sql = 构造语句（脱敏在 T07 内部，此处原样传递）。
      expect(h.audit.records.single['sql'], 'SELECT * FROM users LIMIT 10');
      expect(h.stats.toolCalls, <String>['get_sample_data']);
    });

    test('get_sample_data：LIMIT clamp 1-100 默认 10（宽容 num/数字字符串）', () async {
      final h = _Harness();
      await h.run('get_sample_data', <String, dynamic>{
        'table': 't',
        'limit': 500,
      });
      await h.run('get_sample_data', <String, dynamic>{
        'table': 't',
        'limit': 0,
      });
      await h.run('get_sample_data', <String, dynamic>{
        'table': 't',
        'limit': '7',
      });
      await h.run('get_sample_data', <String, dynamic>{
        'table': 't',
        'limit': 'abc',
      });
      await h.run('get_sample_data', <String, dynamic>{'table': 't'});

      expect(h.db.executedSql, <String>[
        'SELECT * FROM t LIMIT 100',
        'SELECT * FROM t LIMIT 1',
        'SELECT * FROM t LIMIT 7',
        'SELECT * FROM t LIMIT 10',
        'SELECT * FROM t LIMIT 10',
      ]);
    });

    test('execute_readonly_sql：执行 + 行/列/rowCount + 步消息对', () async {
      final h = _Harness()
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
          <String, dynamic>{'id': 2},
          <String, dynamic>{'id': 3},
        ];
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM users',
      });

      expect(out.ok, isTrue);
      expect(h.db.executedSql.single, 'SELECT id FROM users');
      final feed = _decode(out.toLLMJson());
      expect(feed['rowCount'], 3);
      expect(feed['columns'], <String>['id']);
      expect(h.audit.records.single['sql'], 'SELECT id FROM users');
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.allowed);

      // §5.2 消息对。
      expect(out.callMessage.type, AiMessageType.toolCall);
      expect(out.callMessage.toolArguments, <String, dynamic>{
        'sql': 'SELECT id FROM users',
      });
      expect(out.resultMessage.type, AiMessageType.toolResult);
      expect(out.resultMessage.toolResultSummary, isNotEmpty);
    });

    test('explain_plan：EXPLAIN 通道 + 不执行目标语句（AC4.5）', () async {
      final h = _Harness()
        ..db.explainResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1, 'type': 'ALL'},
        ];
      final out = await h.run('explain_plan', <String, dynamic>{
        'sql': 'SELECT * FROM users',
      });

      expect(out.ok, isTrue);
      expect(h.db.explainedSql.single, 'SELECT * FROM users');
      expect(h.db.executeQueryCalls, 0); // 不执行目标语句
      final data = _decode(out.toLLMJson())['data'] as Map<String, dynamic>;
      expect((data['plan'] as List<dynamic>).length, 1);
      expect(h.audit.records.single['sql'], 'SELECT * FROM users');
    });

    test('get_current_context：run 快照（AC7.1），零 db 访问', () async {
      final h = _Harness();
      final out = await h.run('get_current_context');

      expect(out.ok, isTrue);
      final data = _decode(out.toLLMJson())['data'] as Map<String, dynamic>;
      expect(data['hasConnection'], isTrue);
      expect(data['connectionName'], '测试连接');
      expect(data['databaseName'], 'db1');
      expect(data['databaseType'], 'mysql');
      expect(data['readOnly'], isFalse);
      expect(h.db.executeQueryCalls, 0);
      expect(h.db.tablesCalls, 0);
      expect(h.audit.records.single['sql'], isNull);
    });

    test('get_current_context：无连接上下文也可用（AC7.4）', () async {
      final h = _Harness(connectionId: null);
      final out = await h.run('get_current_context');

      expect(out.ok, isTrue);
      final data = _decode(out.toLLMJson())['data'] as Map<String, dynamic>;
      expect(data['hasConnection'], isFalse);
      expect(data['connectionName'], isNull);
      // 无上下文运行：审计 connectionId 空串（§4.7 语义）。
      expect(h.audit.records.single['connectionId'], '');
    });
  });

  group('拦截零执行（D3 / AC15.3 / AC4.2 / AC9.7）', () {
    test('写语句 → WRITE_REJECTED_READONLY_CHANNEL + 计划路径指引 + 零执行', () async {
      final h = _Harness();
      const String update = "UPDATE users SET name = 'x' WHERE id = 1";
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': update,
      });

      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.writeRejectedReadonlyChannel);
      expect(out.errorMessage, contains('submit_action_plan'));
      expect(h.db.executeQueryCalls, 0);
      // 审计：拦截尝试也落（success=false + 被拦语句原样传入，脱敏在 T07）。
      expect(h.audit.records.single['success'], isFalse);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.blocked);
      expect(h.audit.records.single['sql'], update);
      // 拦截也计步 + 进统计（D10 同口径）。
      expect(h.executor.stepsUsed, 1);
      expect(h.stats.toolCalls, <String>['execute_readonly_sql']);
    });

    test('INSERT 同为写形态拒绝', () async {
      final h = _Harness();
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': "INSERT INTO users (name) VALUES ('a')",
      });
      expect(out.errorCode, AgentToolErrorCodes.writeRejectedReadonlyChannel);
      expect(h.db.executeQueryCalls, 0);
    });

    test('SELECT ... INTO / 多语句 / 空语句 → 拒绝且零执行', () async {
      final h = _Harness();
      final into = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * INTO new_table FROM users',
      });
      expect(into.ok, isFalse);
      expect(into.errorCode, AgentToolErrorCodes.invalidArguments);

      final multi = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT 1; SELECT 2',
      });
      expect(multi.ok, isFalse);

      final empty = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': '   ',
      });
      expect(empty.ok, isFalse);

      expect(h.db.executeQueryCalls, 0);
    });

    test('NoSQL 连接 × SQL 文本工具 → UNSUPPORTED_DIALECT（先于门 evaluate）', () async {
      for (final String tool in <String>[
        'execute_readonly_sql',
        'get_sample_data',
        'explain_plan',
      ]) {
        final h = _Harness(dbType: DatabaseType.mongodb);
        final out = await h.run(
          tool,
          tool == 'get_sample_data'
              ? <String, dynamic>{'table': 'col'}
              : <String, dynamic>{'sql': 'SELECT 1'},
        );
        expect(out.ok, isFalse, reason: tool);
        expect(
          out.errorCode,
          AgentToolErrorCodes.unsupportedDialect,
          reason: tool,
        );
        expect(h.db.executeQueryCalls, 0, reason: tool);
        expect(h.db.explainCalls, 0, reason: tool);
        // 预拦截必须先于门：evaluate 不可达（否则读前分析对 NoSQL 必
        // fail-closed 假确认）。
        expect((h.gate as _ScriptedGate).evaluateCalls, 0, reason: tool);
        expect(
          h.audit.records.single['gateDecision'],
          AgentGateDecision.blocked,
        );
      }
    });

    test('explain_plan 目标为写语句 → 只读闸先拒，EXPLAIN 零调用', () async {
      final h = _Harness();
      final out = await h.run('explain_plan', <String, dynamic>{
        'sql': 'UPDATE users SET name = 1',
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(h.db.explainCalls, 0);
    });

    test('explain_plan 目标为 EXPLAIN ANALYZE 写形态 → 拒（AC4.5 反面）', () async {
      final h = _Harness();
      final out = await h.run('explain_plan', <String, dynamic>{
        'sql': 'EXPLAIN ANALYZE DELETE FROM users',
      });
      expect(out.ok, isFalse);
      expect(h.db.explainCalls, 0);
      expect(h.db.executeQueryCalls, 0);
    });
  });

  group('Fix-B 中-2：get_sample_data 标识符白名单（方案①，零执行第一道防线）', () {
    test('白名单外字符 → INVALID_ARGUMENTS + 零执行 + 计步 + 审计 blocked', () async {
      final h = _Harness();
      final out = await h.run('get_sample_data', <String, dynamic>{
        'table': 'users; DROP TABLE x',
      });

      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(out.errorMessage, contains('plain identifier'));
      expect(h.db.executeQueryCalls, 0, reason: '零执行');
      expect(h.executor.stepsUsed, 1, reason: '被拒调用也计步（D10）');
      expect(h.audit.count, 1);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.blocked);
      expect(h.audit.records.single['success'], isFalse);
    });

    test('引界符 / 子查询 / 注释 / 空格注入形态同样拒绝（零执行）', () async {
      final h = _Harness();
      const List<String> badTables = <String>[
        '`users`',
        '"users"',
        "'users'",
        'users where 1=1 --',
        'users UNION SELECT 1',
        '(SELECT 1) AS t',
        'users;x',
        'a b',
      ];
      for (final String bad in badTables) {
        final out = await h.run('get_sample_data', <String, dynamic>{
          'table': bad,
        });
        expect(out.ok, isFalse, reason: bad);
        expect(
          out.errorCode,
          AgentToolErrorCodes.invalidArguments,
          reason: bad,
        );
      }
      expect(h.db.executeQueryCalls, 0);
      expect(h.executor.stepsUsed, badTables.length);
    });

    test('schema.table 限定形态放行（点号在白名单内；T28 起须 = 锁定库）', () async {
      final h = _Harness()
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ];
      // AC4.4 执法（T28）：限定首段须等于快照锁定库 db1——跨库限定走拒绝面
      //（agent_tool_executor_a2_test.dart 覆盖），此处验证锁定库限定放行。
      final out = await h.run('get_sample_data', <String, dynamic>{
        'table': 'db1.users',
      });

      expect(out.ok, isTrue);
      expect(h.db.executedSql.single, 'SELECT * FROM db1.users LIMIT 10');
    });
  });

  group('执行异常（AC15.1 / NF2.2）', () {
    test('executeQuery 抛错 → EXECUTION_FAILED + detail 脱敏回喂', () async {
      final h = _Harness()
        ..db.queryError = Exception('connect failed password=hunter2 host=x');
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM users',
      });

      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.executionFailed);
      expect(out.errorMessage, contains('***'));
      expect(out.errorMessage, isNot(contains('hunter2')));
      final feed = _decode(out.toLLMJson());
      expect(feed['ok'], isFalse);
      expect(
        (feed['error'] as Map<String, dynamic>)['code'],
        AgentToolErrorCodes.executionFailed,
      );
      expect(
        ((feed['error'] as Map<String, dynamic>)['message'] as String),
        isNot(contains('hunter2')),
      );
      // 门已放行、执行失败：审计 allowed + success=false。
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.allowed);
      expect(h.audit.records.single['success'], isFalse);
    });

    test('EXPLAIN 不支持方言（网关壳 UnsupportedError）→ UNSUPPORTED_DIALECT', () async {
      final h = _Harness()
        ..db.explainError = UnsupportedError(
          'sqlserver gateway has no explain',
        );
      final out = await h.run('explain_plan', <String, dynamic>{
        'sql': 'SELECT * FROM users',
      });
      expect(out.errorCode, AgentToolErrorCodes.unsupportedDialect);
      expect(out.ok, isFalse);
    });
  });

  group('计步（D10 / AC2.3）与复位', () {
    test('被拒调用消耗步数；审计每调用恰一条且 step 连续', () async {
      final h = _Harness()..db.tables = <String>['t'];
      await h.run('nope_tool'); // 目录外拒
      await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'DELETE FROM users',
      }); // 写拒
      await h.run('list_tables'); // 成功

      expect(h.executor.stepsUsed, 3);
      expect(h.audit.count, 3);
      expect(
        h.audit.records.map((Map<String, Object?> r) => r['step']).toList(),
        <Object?>[1, 2, 3],
      );
      expect(
        h.audit.records.every(
          (Map<String, Object?> r) => r['runId'] == 'run-1',
        ),
        isTrue,
      );
      expect(h.audit.records[2]['gateDecision'], AgentGateDecision.allowed);
    });

    test('resetSteps：新 run 从 1 重新计数', () async {
      final h = _Harness()..db.tables = <String>['t'];
      await h.run('list_tables');
      await h.run('list_tables');
      expect(h.executor.stepsUsed, 2);

      h.executor.resetSteps();
      expect(h.executor.stepsUsed, 0);
      await h.run('list_tables');
      expect(h.executor.stepsUsed, 1);
      expect(h.audit.records.last['step'], 1);
    });
  });

  group('L0.5 confirm 链（D7 / AC8.x）', () {
    const GateDecision confirmL05 = GateDecision(
      kind: GateDecisionKind.confirm,
      level: AgentGateLevel.l05,
      impact: ReadImpactAnalysis(
        estimatedRows: 800000,
        fullScan: true,
        scannedTables: <String>['big_table'],
        indexSummary: 'big_table: no index (ALL)',
        analysisUnavailable: false,
      ),
    );

    test('approved → 执行 + 审计 confirmed + 统计 shown', () async {
      final h = _Harness(gateDecision: confirmL05)
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ];
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM big_table WHERE x = 1',
      });

      expect(out.ok, isTrue);
      expect(h.db.executeQueryCalls, 1);
      expect(h.confirmInvoked, isTrue);
      expect(h.seenConfirmSql, 'SELECT * FROM big_table WHERE x = 1');
      expect(h.seenImpact?.estimatedRows, 800000);
      expect(h.seenImpact?.fullScan, isTrue);

      expect(
        h.audit.records.single['gateDecision'],
        AgentGateDecision.confirmed,
      );
      expect(h.audit.records.single['gateLevel'], AgentGateLevel.l05);
      expect(h.stats.l05Events, <AgentL05Stat>[AgentL05Stat.shown]);

      final payload = _agentPayload(out);
      expect(payload['gateDecision'], 'confirmed');
      expect(payload['gateLevel'], 'l05');
    });

    test('approvedForSession → 账本记录 + 审计 allowed_session + 统计', () async {
      final h = _Harness(gateDecision: confirmL05)
        ..confirmResult = GateCardResult.approvedForSession;
      final out = await h.run('get_sample_data', <String, dynamic>{
        'table': 'big_table',
      });

      expect(out.ok, isTrue);
      expect(h.ledger.l05Allowed.contains('conn-1'), isTrue);
      expect(h.seenConfirmSql, 'SELECT * FROM big_table LIMIT 10');
      expect(
        h.audit.records.single['gateDecision'],
        AgentGateDecision.allowedSession,
      );
      expect(h.stats.l05Events, <AgentL05Stat>[
        AgentL05Stat.shown,
        AgentL05Stat.sessionAllowed,
      ]);
    });

    test('rejected → GATE_REJECTED + 审计 rejected_by_user + 零执行', () async {
      final h = _Harness(gateDecision: confirmL05)
        ..confirmResult = GateCardResult.rejected;
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM big_table',
      });

      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.gateRejected);
      expect(h.db.executeQueryCalls, 0);
      expect(
        h.audit.records.single['gateDecision'],
        AgentGateDecision.rejectedByUser,
      );
      expect(h.audit.records.single['sql'], 'SELECT * FROM big_table');
      expect(h.stats.l05Events, <AgentL05Stat>[
        AgentL05Stat.shown,
        AgentL05Stat.rejected,
      ]);
    });

    test('无确认回调 → fail-closed GATE_REJECTED（绝不静默放行）', () async {
      final h = _Harness(gateDecision: confirmL05);
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM big_table',
      }, false); // gates = null

      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.gateRejected);
      expect(h.confirmInvoked, isFalse);
      expect(h.db.executeQueryCalls, 0);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.blocked);
      expect(h.stats.l05Events, <AgentL05Stat>[AgentL05Stat.shown]);
    });

    test('evaluate ⑤ 会话放行短路的 allow@l05 → 审计 allowed_session', () async {
      const GateDecision sessionAllow = GateDecision(
        kind: GateDecisionKind.allow,
        level: AgentGateLevel.l05,
      );
      final h = _Harness(gateDecision: sessionAllow)
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ];
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM big_table',
      });

      expect(out.ok, isTrue);
      expect(h.confirmInvoked, isFalse); // 短路：不出卡
      expect(
        h.audit.records.single['gateDecision'],
        AgentGateDecision.allowedSession,
      );
    });

    test('confirm(l1) 在 A1 结构不可达 → fail-loud 不变量守卫', () async {
      const GateDecision confirmL1 = GateDecision(
        kind: GateDecisionKind.confirm,
        level: AgentGateLevel.l1,
      );
      final h = _Harness(gateDecision: confirmL1);
      await expectLater(
        h.run('execute_readonly_sql', <String, dynamic>{'sql': 'SELECT 1'}),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('真实门集成（①-⑤ 全链：真 AgentGate + 真分析内核）', () {
    AgentGate realGate(_ExplainMock mock) => AgentGate(
      createAnalysis: (AgentRunContext runCtx) => AgentGateAnalysis(
        getExplainPlan: mock.call,
        rowThreshold: 10000,
        dbType: runCtx.dbType,
      ),
    );

    test('全表扫描 → confirm → 人批准 → 执行 + 审计 confirmed', () async {
      final mock = _ExplainMock()
        ..data = _mysqlExplainRow(type: 'ALL', rows: 500000);
      final h = _Harness(gateOverride: realGate(mock))
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ];
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM big_table WHERE nonindexed = 1',
      });

      expect(out.ok, isTrue);
      expect(h.confirmInvoked, isTrue);
      expect(h.db.executeQueryCalls, 1);
      expect(mock.callCount, 1); // 读前分析发生过
      expect(
        h.audit.records.single['gateDecision'],
        AgentGateDecision.confirmed,
      );
      expect(h.audit.records.single['gateLevel'], AgentGateLevel.l05);
    });

    test('命中索引小范围 → 直接放行执行（不出卡）', () async {
      final mock = _ExplainMock()
        ..data = _mysqlExplainRow(type: 'ref', rows: 50, key: 'idx_x');
      final h = _Harness(gateOverride: realGate(mock))
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ];
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM big_table WHERE indexed_col = 1',
      });

      expect(out.ok, isTrue);
      expect(h.confirmInvoked, isFalse);
      expect(h.db.executeQueryCalls, 1);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.allowed);
      expect(h.audit.records.single['gateLevel'], AgentGateLevel.l0);
    });

    test('无连接上下文 × requiresConnection → CONTEXT_REQUIRED（AC7.4）', () async {
      final mock = _ExplainMock();
      final h = _Harness(gateOverride: realGate(mock), connectionId: null);
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT 1',
      });

      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.contextRequired);
      expect(h.db.executeQueryCalls, 0);
      expect(mock.callCount, 0); // 判定序② 先于 ④ 分析
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.blocked);
    });
  });

  group('回喂格式与 D19 双上限', () {
    test('行快照 ≤20：超限截断标记 + rowCount/列名保留', () async {
      final h = _Harness()
        ..db.queryResult = List<Map<String, dynamic>>.generate(
          50,
          (int i) => <String, dynamic>{'id': i},
        );
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM big',
      });

      final feed = _decode(out.toLLMJson());
      expect(feed['rowCount'], 50);
      expect(feed['columns'], <String>['id']);
      expect(feed['truncated'], isTrue);
      expect(
        ((feed['data'] as Map<String, dynamic>)['rows'] as List<dynamic>)
            .length,
        20,
      );
      // resultRef 持全量（行限内不复制，T09）。
      expect(out.resultRef?.rows.length, 50);
    });

    test('字符上限 ≤4000：大结果收缩行 + 保留元数据 + 可解析', () async {
      final String pad = 'x' * 300;
      final h = _Harness()
        ..db.queryResult = List<Map<String, dynamic>>.generate(
          200,
          (int i) => <String, dynamic>{'id': i, 'blob': pad},
        );
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT * FROM big',
      });

      final String feed = out.toLLMJson();
      expect(feed.length, lessThanOrEqualTo(4000));
      final Map<String, dynamic> decoded = _decode(feed);
      expect(decoded['rowCount'], 200);
      expect(decoded['columns'], <String>['id', 'blob']);
      expect(decoded['truncated'], isTrue);
    });

    test('单行巨型载荷 → 弃行保元数据（rowCount/列名 + 截断标记）', () async {
      final h = _Harness()
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'v': 'x' * 20000},
        ];
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT v FROM t',
      });

      final String feed = out.toLLMJson();
      expect(feed.length, lessThanOrEqualTo(4000));
      final Map<String, dynamic> decoded = _decode(feed);
      expect(decoded['rowCount'], 1);
      expect(decoded['columns'], <String>['v']);
      expect(decoded['truncated'], isTrue);
      expect(
        ((decoded['data'] as Map<String, dynamic>)['rows'] as List<dynamic>),
        isEmpty,
      );
    });

    test('非 row 列表（tables）同样受字符上限约束', () async {
      final h = _Harness()
        ..db.tables = List<String>.generate(
          3000,
          (int i) => 'table_with_long_name_padding_$i',
        );
      final out = await h.run('list_tables');

      final String feed = out.toLLMJson();
      expect(feed.length, lessThanOrEqualTo(4000));
      final Map<String, dynamic> decoded = _decode(feed);
      expect(decoded['rowCount'], 3000);
      expect(decoded['truncated'], isTrue);
    });

    test('错误回喂形态：{ok:false, error:{code,message}}，无 data', () async {
      final h = _Harness();
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'DROP TABLE users',
      });
      final Map<String, dynamic> feed = _decode(out.toLLMJson());
      expect(feed['ok'], isFalse);
      expect(feed.containsKey('data'), isFalse);
      expect(feed.containsKey('rowCount'), isFalse);
      final Map<String, dynamic> error = feed['error'] as Map<String, dynamic>;
      expect(error['code'], AgentToolErrorCodes.writeRejectedReadonlyChannel);
      expect(error['message'], contains('submit_action_plan'));
    });
  });

  group('步消息结构（§5.2）', () {
    test('agent_step 载荷字段齐备；快照 ≤10；错误步带 error', () async {
      final h = _Harness()
        ..db.queryResult = List<Map<String, dynamic>>.generate(
          12,
          (int i) => <String, dynamic>{'id': i},
        );
      final okOut = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM t',
      });

      final Map<String, dynamic> payload = _agentPayload(okOut);
      expect(payload['kind'], 'agent_step');
      expect(payload['runId'], 'run-1');
      expect(payload['stepNo'], 1);
      expect(payload['tool'], 'execute_readonly_sql');
      expect(payload['gateLevel'], 'l0');
      expect(payload['gateDecision'], 'allowed');
      expect(payload['summary'], isNotEmpty);
      expect(payload['durationMs'], isA<int>());
      expect(payload.containsKey('error'), isFalse);
      final Map<String, dynamic> ref =
          payload['resultRef'] as Map<String, dynamic>;
      expect(ref['rowCount'], 12);
      expect((ref['snapshotRows'] as List<dynamic>).length, 10); // ≤10 不变式

      final errOut = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'DELETE FROM t',
      });
      final Map<String, dynamic> errPayload = _agentPayload(errOut);
      expect(errPayload['stepNo'], 2);
      final Map<String, dynamic> err =
          errPayload['error'] as Map<String, dynamic>;
      expect(err['code'], AgentToolErrorCodes.writeRejectedReadonlyChannel);
      expect(errPayload.containsKey('resultRef'), isFalse);
    });

    test('AgentToolCall.fromAiToolCall：AiClient 形态转换（T11 入口）', () {
      final AiToolCall aiCall = AiToolCall(
        id: 'call_abc',
        type: 'function',
        functionName: 'list_tables',
        functionArguments: '{"a":1}',
      );
      final AgentToolCall call = AgentToolCall.fromAiToolCall(aiCall);
      expect(call.id, 'call_abc');
      expect(call.name, 'list_tables');
      expect(call.argumentsJson, '{"a":1}');
    });
  });
}
