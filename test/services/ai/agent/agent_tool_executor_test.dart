// AgentToolExecutor 单测（T10 / design-ai-agent.md D3、D10、D19、§4.1、§5.2）。
//
// 覆盖任务书清单：逐工具正常/错误路径、拦截零执行（D3/AC15.3/AC4.2）、
// 计步含被拒（D10/AC2.3）、审计每调用一条（AC13.1，拦截/人拒也落）、
// 回喂格式与 D19 双上限、§5.2 步消息结构、L0.5 confirm 链（D7）、
// 真实 AgentGate + AgentGateAnalysis 的 ①-⑤ 全链集成、
// T2 方案 B fail-closed 防御（门旁路 × USE 语义族 db-less → 显式
// CONTEXT_REQUIRED，绝不空表/空列）。
//
// 依赖全注入（NF5.3）：db 访问 / 审计 / 统计均为 spy 闭包；门用
// _ScriptedGate（可编程判定）驱动链路分支，真实门的判定序分支由
// agent_gate_test.dart（T06）覆盖，此处另设「真实门集成」组验证链完整性。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/ai_memory_item.dart'
    show AiMemoryItem, AiMemoryScope, AiMemorySource;
import 'package:dbmaster/models/ai_message_type.dart' show AiMessageType;
import 'package:dbmaster/models/ai_models.dart' show AiToolCall;
import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbColumn, DbIndex, ForeignKey;
import 'package:dbmaster/models/query_optimizer/execution_plan.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart';
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart'
    show AgentGateAnalysis, ReadImpactAnalysis;
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolErrorCodes, AgentToolSpec;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart';
import 'package:dbmaster/services/ai/agent/agent_ui_port.dart'
    show AgentResultRef, AgentUiOutcome, AgentUiPort, GateCardResult;
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
  final List<String?> tablesConnectionIds = <String?>[];
  final List<String?> tablesDatabases = <String?>[];

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
  getTables: (String? connectionId, String? databaseName) async {
    spy.tablesCalls++;
    spy.tablesConnectionIds.add(connectionId);
    spy.tablesDatabases.add(databaseName);
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

/// T4：保存查询 spy（可编程结论；记录入参断言连接绑定取自快照）。
class _SaverSpy {
  int calls = 0;
  String? lastName;
  String? lastSql;
  String? lastConnectionId;
  String? lastDatabaseName;
  DatabaseType? lastDatabaseType;
  AgentSavedQuerySaveStatus result = AgentSavedQuerySaveStatus.saved;

  Future<AgentSavedQuerySaveStatus> call({
    required String name,
    required String sql,
    String? connectionId,
    String? databaseName,
    DatabaseType? databaseType,
  }) async {
    calls++;
    lastName = name;
    lastSql = sql;
    lastConnectionId = connectionId;
    lastDatabaseName = databaseName;
    lastDatabaseType = databaseType;
    return result;
  }
}

/// T4：prefs 历史写 spy（可编程抛错——写失败不得阻断工具回喂）。
class _HistorySpy {
  final List<Map<String, Object?>> writes = <Map<String, Object?>>[];
  Object? error;

  Future<void> call({
    required String sql,
    required String connectionId,
    String? connectionName,
    String? database,
    DatabaseType? databaseType,
    required int durationMs,
    required int affectedRows,
    String? error,
  }) async {
    final Object? err = this.error;
    if (err != null) throw err;
    writes.add(<String, Object?>{
      'sql': sql,
      'connectionId': connectionId,
      'connectionName': connectionName,
      'database': database,
      'databaseType': databaseType,
      'durationMs': durationMs,
      'affectedRows': affectedRows,
      'error': error,
    });
  }
}

/// T4：记忆访问 fake（三面可编程；save 记录落库条目）。
class _MemoryFake {
  final List<AiMemoryItem> saved = <AiMemoryItem>[];
  List<AiMemoryItem> global = <AiMemoryItem>[];
  List<AiMemoryItem> connection = <AiMemoryItem>[];
  List<AiMemoryItem> tableMatches = <AiMemoryItem>[];
  Object? forTableError;

  AgentMemoryAccess get access => AgentMemoryAccess(
    save:
        ({
          required AiMemoryScope scope,
          String? connectionId,
          String? subject,
          required String content,
        }) async {
          final AiMemoryItem item = AiMemoryItem(
            id: 'mem_fake_${saved.length}',
            scope: scope,
            connectionId: connectionId,
            subject: subject,
            content: content,
            source: AiMemorySource.agent,
            createdAt: 1,
            updatedAt: 1,
          );
          saved.add(item);
          return item;
        },
    listFor: (String? connectionId) => (global: global, connection: connection),
    forTable: (String table, String? connectionId) {
      final Object? err = forTableError;
      if (err != null) throw err;
      return tableMatches;
    },
  );
}

/// T4 用例的记忆条目构造。
AiMemoryItem _memItem(
  String id,
  AiMemoryScope scope, {
  String? subject,
  String content = 'note',
  int updatedAt = 1,
}) => AiMemoryItem(
  id: id,
  scope: scope,
  connectionId: scope == AiMemoryScope.connection ? 'conn-1' : null,
  subject: subject,
  content: content,
  source: AiMemorySource.agent,
  createdAt: updatedAt,
  updatedAt: updatedAt,
);

/// 2b.3：界面派发端口 spy——记录 openOptimization 载荷（report/sql），
/// 可编程抛错模拟「推送失败」旁挂路径（组装/推送异常不吞结果的测试面）。
class _UiPortSpy implements AgentUiPort {
  int openOptimizationCalls = 0;
  final List<PerformanceReport> reports = <PerformanceReport>[];
  final List<String> optimizationSqls = <String>[];
  Object? openOptimizationError;

  @override
  Future<AgentUiOutcome> openOptimization(
    PerformanceReport report,
    String sql,
  ) {
    openOptimizationCalls++;
    final Object? err = openOptimizationError;
    if (err != null) throw err;
    reports.add(report);
    optimizationSqls.add(sql);
    return Future<AgentUiOutcome>.value(const AgentUiOutcome.ok());
  }

  @override
  Future<AgentUiOutcome> openResultGrid(AgentResultRef ref, String? title) =>
      Future<AgentUiOutcome>.value(const AgentUiOutcome.ok());

  @override
  Future<AgentUiOutcome> showTableStructure(String table) =>
      Future<AgentUiOutcome>.value(const AgentUiOutcome.ok());

  @override
  Future<AgentUiOutcome> openSqlEditor(String sql) =>
      Future<AgentUiOutcome>.value(const AgentUiOutcome.ok());

  @override
  Future<AgentUiOutcome> renderChart(AgentResultRef ref, String? chartKind) =>
      Future<AgentUiOutcome>.value(const AgentUiOutcome.ok());

  @override
  Future<AgentUiOutcome> pinArtifact(AgentResultRef ref, String? label) =>
      Future<AgentUiOutcome>.value(const AgentUiOutcome.ok());

  @override
  Future<AgentUiOutcome> suggestOpenInClassic(String sql) =>
      Future<AgentUiOutcome>.value(const AgentUiOutcome.ok());

  @override
  Future<AgentUiOutcome> suggestFocusSidebar({
    String? database,
    String? table,
  }) => Future<AgentUiOutcome>.value(const AgentUiOutcome.ok());
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
/// T4 三个注入面（saver/history/memory）按需挂接——缺省 null 保持
/// 「未接线」语义（saver fail-closed、history 跳过、memory 走真实单例空态）。
/// [databaseName] 显式传（含 null）覆盖默认 'db1'——T2 方案 B fail-closed
/// 防御用例的 db-less 快照面（哨兵 [_autoDb] 区分「未传」与「显式 null」）。
class _Harness {
  /// 「未传 databaseName」哨兵：连接在场时回落 'db1'，无连接回落 null。
  static const String _autoDb = '\u0000auto-db';

  _Harness({
    GateDecision gateDecision = _allowL0,
    AgentGate? gateOverride,
    DatabaseType dbType = DatabaseType.mysql,
    String? connectionId = 'conn-1',
    String? databaseName = _autoDb,
    _SaverSpy? saver,
    _HistorySpy? history,
    _MemoryFake? memory,
  }) : gate = gateOverride ?? _ScriptedGate(gateDecision) {
    final String? resolvedDb = databaseName == _autoDb
        ? (connectionId == null ? null : 'db1')
        : databaseName;
    runCtx = AgentRunContext(
      runId: 'run-1',
      connectionId: connectionId,
      connectionName: connectionId == null ? null : '测试连接',
      databaseName: resolvedDb,
      dbType: dbType,
      readOnly: false,
    );
    executor = AgentToolExecutor(
      gate: gate,
      db: _access(db),
      audit: audit.record,
      recordToolCall: stats.toolCalls.add,
      recordL05Event: stats.l05Events.add,
      savedQuerySaver: saver?.call,
      recordAgentHistory: history?.call,
      memory: memory?.access,
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
    AgentUiPort? uiPort,
  ]) => executor.execute(
    call: _call(tool, args),
    runCtx: runCtx,
    ledger: ledger,
    gates: withGates ? gates : null,
    uiPort: uiPort,
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

  group('FU-18 list_tables 库路由对齐 run 快照', () {
    test('USE 语义族：快照 databaseName 原样传导（库不落连接初始库）', () async {
      final h = _Harness(dbType: DatabaseType.mysql, databaseName: 'testdb')
        ..db.tables = <String>['users', 'orders'];
      final out = await h.run('list_tables');

      expect(out.ok, isTrue);
      expect(h.db.tablesCalls, 1);
      expect(h.db.tablesConnectionIds, <String?>['conn-1']);
      expect(h.db.tablesDatabases, <String?>['testdb']);
      final feed = _decode(out.toLLMJson());
      expect((feed['data'] as Map<String, dynamic>)['tables'], <String>[
        'users',
        'orders',
      ]);
    });

    test('无库快照（sqlite）：传 null 不传空串，表清单照常返回', () async {
      final h = _Harness(dbType: DatabaseType.sqlite, databaseName: null)
        ..db.tables = <String>['t1'];
      final out = await h.run('list_tables');

      expect(out.ok, isTrue);
      expect(h.db.tablesDatabases, <String?>[null]);
      expect(
        (_decode(out.toLLMJson())['data'] as Map<String, dynamic>)['tables'],
        <String>['t1'],
      );
    });
  });

  group('六工具正常路径', () {
    test('list_tables：表清单 + 审计 allowed + 统计分桶', () async {
      final h = _Harness()..db.tables = <String>['users', 'orders', 'invoices'];
      final out = await h.run('list_tables');

      expect(out.ok, isTrue);
      expect(h.db.tablesCalls, 1);
      // FU-18：库随快照传导（默认 harness = conn-1 / db1）。
      expect(h.db.tablesDatabases, <String?>['db1']);
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

  group('2b.3 explain_plan optimization 旁挂推送（R6）', () {
    test('explain 成功 → uiPort.openOptimization 收到 report 且 sql 一致；'
        'plan 照常回模型', () async {
      final h = _Harness()
        ..db.explainResult = _mysqlExplainRow(type: 'ALL', rows: 12000);
      final spy = _UiPortSpy();
      const sql = 'SELECT * FROM big_table WHERE val = 42';

      final out = await h.run(
        'explain_plan',
        <String, dynamic>{'sql': sql},
        true,
        spy,
      );

      // 主链路结果不受旁挂影响：plan 照常回模型。
      expect(out.ok, isTrue);
      final feed = _decode(out.toLLMJson());
      expect(feed['ok'], isTrue);
      expect(
        (feed['data'] as Map<String, dynamic>)['plan'] as List,
        hasLength(1),
        reason: 'plan 回喂原样（旁挂不吞结果）',
      );

      // 推送载荷：report 由真实 QueryOptimizerService 组装。
      expect(spy.openOptimizationCalls, 1);
      expect(spy.optimizationSqls.single, sql, reason: 'sql 与目标语句精确一致');
      final PerformanceReport report = spy.reports.single;
      expect(report.executionPlan.originalQuery, sql);
      expect(
        report.executionPlan.steps,
        isNotEmpty,
        reason: 'report.executionPlan 非空',
      );
      expect(report.executionPlan.steps.single.scanType, ScanType.fullTable);
      expect(
        report.bottlenecks.any((b) => b.type == BottleneckType.fullTableScan),
        isTrue,
      );
      expect(
        report.indexRecommendations,
        isNotEmpty,
        reason: 'WHERE val 等值 → 提取 val 列生成索引推荐',
      );
    });

    test('uiPort null（未装配）→ 跳过推送不失败，plan 照常回模型', () async {
      final h = _Harness()
        ..db.explainResult = _mysqlExplainRow(type: 'ALL', rows: 12000);
      final out = await h.run('explain_plan', <String, dynamic>{
        'sql': 'SELECT * FROM big_table',
      });

      expect(out.ok, isTrue, reason: 'null uiPort 跳过推送不失败');
      expect(out.errorCode, isNull);
      expect(h.db.explainCalls, 1, reason: 'EXPLAIN 通道本身正常往返');
    });

    test('推送异常（组装/推送旁挂链路）→ 不吞结果：plan 照常回模型', () async {
      final h = _Harness()
        ..db.explainResult = _mysqlExplainRow(type: 'ALL', rows: 12000);
      final spy = _UiPortSpy()
        ..openOptimizationError = StateError('stage gone');
      final out = await h.run(
        'explain_plan',
        <String, dynamic>{'sql': 'SELECT * FROM big_table'},
        true,
        spy,
      );

      expect(out.ok, isTrue, reason: '旁挂异常不拦截主链路');
      final feed = _decode(out.toLLMJson());
      expect(
        (feed['data'] as Map<String, dynamic>)['plan'] as List,
        hasLength(1),
        reason: 'plan 照常回模型（推送失败不吞结果）',
      );
      expect(spy.openOptimizationCalls, 1, reason: '推送确实发起且失败被收敛');
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

  group('T2 fail-closed 防御（方案 B / FU-10：门旁路 × db-less 绝不空表/空列）', () {
    test('脚本 allow 旁路 × mysql 无库 × 数据工具 → CONTEXT_REQUIRED，零 db 访问，'
        '审计 blocked', () async {
      const List<(String, Object?)> cases = <(String, Object?)>[
        ('list_tables', null),
        ('describe_table', <String, dynamic>{'table': 'users'}),
        ('get_sample_data', <String, dynamic>{'table': 'users'}),
        ('execute_readonly_sql', <String, dynamic>{'sql': 'SELECT 1'}),
        ('explain_plan', <String, dynamic>{'sql': 'SELECT 1'}),
        ('show_table_structure', <String, dynamic>{'table': 'users'}),
      ];
      for (final (String tool, Object? args) in cases) {
        final h = _Harness(databaseName: null); // 脚本 allow 门（门旁路）
        final out = await h.run(tool, args);

        expect(out.ok, isFalse, reason: tool);
        expect(
          out.errorCode,
          AgentToolErrorCodes.contextRequired,
          reason: tool,
        );
        expect(out.errorMessage, contains('context chip'), reason: tool);
        expect(
          h.db.executeQueryCalls +
              h.db.tablesCalls +
              h.db.columnsCalls +
              h.db.indexesCalls +
              h.db.foreignKeysCalls +
              h.db.createTableSqlCalls +
              h.db.explainCalls,
          0,
          reason: '$tool 零 db 访问（fail-closed）',
        );
        expect(
          h.audit.records.single['gateDecision'],
          AgentGateDecision.blocked,
          reason: tool,
        );
        expect(h.audit.records.single['success'], isFalse, reason: tool);
        expect(h.executor.stepsUsed, 1, reason: tool);
      }
    });

    test('describe_table 吞错通道在无库情形不可达（columns/indexes/fk/DDL 全零调用）', () async {
      final h = _Harness(databaseName: null);
      final out = await h.run('describe_table', <String, dynamic>{
        'table': 'users',
      });
      expect(out.errorCode, AgentToolErrorCodes.contextRequired);
      expect(h.db.columnsCalls, 0);
      expect(h.db.indexesCalls, 0);
      expect(h.db.foreignKeysCalls, 0);
      expect(h.db.createTableSqlCalls, 0);
      // 回喂绝无空列载荷形态。
      expect(out.toLLMJson(), isNot(contains('"columns"')));
    });

    test('submit_action_plan：confirm(l1) 旁路 × mysql 无库 → 防御先于计划链', () async {
      final h = _Harness(
        databaseName: null,
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
      expect(out.errorCode, AgentToolErrorCodes.contextRequired);
      expect(h.db.executeQueryCalls, 0);
      expect(h.db.explainCalls, 0);
    });

    test('豁免：sqlite/pg/ss/mongo/redis 无库 × 脚本 allow → 照常执行（防御不拦）', () async {
      for (final DatabaseType dbType in <DatabaseType>[
        DatabaseType.sqlite,
        DatabaseType.postgresql,
        DatabaseType.sqlserver,
        DatabaseType.mongodb,
        DatabaseType.redis,
      ]) {
        final h = _Harness(dbType: dbType, databaseName: null)
          ..db.tables = <String>['t'];
        final out = await h.run('list_tables');
        expect(out.ok, isTrue, reason: '${dbType.name} 豁免（行为同现状）');
        expect(h.db.tablesCalls, 1, reason: '${dbType.name}');
      }
    });

    test('真实门 ②b：mysql 无库 → CONTEXT_REQUIRED，读前分析零构造零调用', () async {
      final mock = _ExplainMock();
      var factoryCalls = 0;
      final h = _Harness(
        databaseName: null,
        gateOverride: AgentGate(
          createAnalysis: (AgentRunContext runCtx) {
            factoryCalls++;
            return AgentGateAnalysis(
              getExplainPlan: mock.call,
              rowThreshold: 10000,
              dbType: runCtx.dbType,
            );
          },
        ),
      );
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT 1',
      });
      expect(out.errorCode, AgentToolErrorCodes.contextRequired);
      expect(out.ok, isFalse);
      expect(factoryCalls, 0, reason: '②b 先于 ④ 分析');
      expect(mock.callCount, 0);
      expect(h.db.executeQueryCalls, 0);
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

  group('T4 save_saved_query', () {
    test('成功：saver 收到 name/sql + 快照连接绑定；回喂 saved 载荷 + 审计 allowed', () async {
      final _SaverSpy saver = _SaverSpy();
      final h = _Harness(saver: saver);
      final out = await h.run('save_saved_query', <String, dynamic>{
        'name': '日报',
        'sql': 'SELECT 1',
      });

      expect(out.ok, isTrue);
      expect(saver.calls, 1);
      expect(saver.lastName, '日报');
      expect(saver.lastSql, 'SELECT 1');
      // 连接绑定取 run 快照（AC7.2），不由参数伪造。
      expect(saver.lastConnectionId, 'conn-1');
      expect(saver.lastDatabaseName, 'db1');
      expect(saver.lastDatabaseType, DatabaseType.mysql);
      final feed = _decode(out.toLLMJson());
      expect(feed['ok'], isTrue);
      expect((feed['data'] as Map<String, dynamic>)['saved'], isTrue);
      expect(h.audit.count, 1);
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.allowed);
      expect(h.audit.records.single['sql'], isNull); // 非数据工具无审计 SQL 面
      expect(h.stats.toolCalls, <String>['save_saved_query']);
      expect(h.db.executeQueryCalls, 0); // 不触达数据库
    });

    test(
      '参数非法：缺 name / 缺 sql / 空 name → INVALID_ARGUMENTS，saver 零调用',
      () async {
        final _SaverSpy saver = _SaverSpy();
        final h = _Harness(saver: saver);
        final noName = await h.run('save_saved_query', <String, dynamic>{
          'sql': 'SELECT 1',
        });
        final noSql = await h.run('save_saved_query', <String, dynamic>{
          'name': 'x',
        });
        final blankName = await h.run('save_saved_query', <String, dynamic>{
          'name': '  ',
          'sql': 'SELECT 1',
        });
        expect(noName.errorCode, AgentToolErrorCodes.invalidArguments);
        expect(noSql.errorCode, AgentToolErrorCodes.invalidArguments);
        expect(blankName.errorCode, AgentToolErrorCodes.invalidArguments);
        expect(saver.calls, 0);
        expect(h.executor.stepsUsed, 3);
      },
    );

    test('无锁定连接 → 门 ② CONTEXT_REQUIRED（真实门），saver 零调用', () async {
      final _SaverSpy saver = _SaverSpy();
      final h = _Harness(
        connectionId: null,
        saver: saver,
        gateOverride: AgentGate(
          createAnalysis: (_) => throw StateError('no analysis on this path'),
        ),
      );
      final out = await h.run('save_saved_query', <String, dynamic>{
        'name': 'x',
        'sql': 'SELECT 1',
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.contextRequired);
      expect(saver.calls, 0);
    });

    test('同名冲突 → SAVED_QUERY_CONFLICT 回喂自纠（审计 blocked）', () async {
      final _SaverSpy saver = _SaverSpy()
        ..result = AgentSavedQuerySaveStatus.duplicateName;
      final h = _Harness(saver: saver);
      final out = await h.run('save_saved_query', <String, dynamic>{
        'name': '日报',
        'sql': 'SELECT 1',
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.savedQueryConflict);
      expect(out.errorMessage, contains('日报'));
      expect(h.audit.records.single['gateDecision'], AgentGateDecision.blocked);
      expect(h.audit.records.single['success'], isFalse);
    });

    test('saver 未装配 → fail-closed EXECUTION_FAILED', () async {
      final h = _Harness();
      final out = await h.run('save_saved_query', <String, dynamic>{
        'name': 'x',
        'sql': 'SELECT 1',
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.executionFailed);
    });

    test('saver 失败态 → EXECUTION_FAILED', () async {
      final _SaverSpy saver = _SaverSpy()
        ..result = AgentSavedQuerySaveStatus.failed;
      final h = _Harness(saver: saver);
      final out = await h.run('save_saved_query', <String, dynamic>{
        'name': 'x',
        'sql': 'SELECT 1',
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.executionFailed);
    });

    test('F-01 节流：同 run 第 4 次保存被拒（SAVED_QUERY_LIMIT_EXCEEDED），'
        'saver 零新增调用', () async {
      final _SaverSpy saver = _SaverSpy();
      final h = _Harness(saver: saver);
      for (var i = 1; i <= 3; i++) {
        final out = await h.run('save_saved_query', <String, dynamic>{
          'name': 'q$i',
          'sql': 'SELECT $i',
        });
        expect(out.ok, isTrue, reason: '第 $i 次保存应放行');
      }
      expect(saver.calls, 3);

      final fourth = await h.run('save_saved_query', <String, dynamic>{
        'name': 'q4',
        'sql': 'SELECT 4',
      });
      expect(fourth.ok, isFalse);
      expect(fourth.errorCode, AgentToolErrorCodes.savedQueryLimitExceeded);
      expect(fourth.errorMessage, contains('manually'));
      // 同 run 第 5 次同样被拒（计数不随拒绝回退），saver 仍只 3 次。
      final fifth = await h.run('save_saved_query', <String, dynamic>{
        'name': 'q5',
        'sql': 'SELECT 5',
      });
      expect(fifth.errorCode, AgentToolErrorCodes.savedQueryLimitExceeded);
      expect(saver.calls, 3);
      // 超限拒绝同样计步 + 审计 blocked（每调用至少一条审计不变式 AC13.1）。
      expect(h.executor.stepsUsed, 5);
      expect(h.audit.records.last['gateDecision'], AgentGateDecision.blocked);
      expect(h.audit.records.last['success'], isFalse);
    });

    test('F-01 节流：runId 变化即新 run 归零——同一 executor 新 run 首次保存放行', () async {
      final _SaverSpy saver = _SaverSpy();
      final h = _Harness(saver: saver);
      for (var i = 0; i < 3; i++) {
        await h.run('save_saved_query', <String, dynamic>{
          'name': 'run1-$i',
          'sql': 'SELECT $i',
        });
      }
      expect(saver.calls, 3);

      // 新 run：executor 跨 run 复用（AiPanelProvider 单例装配），runId
      // 变化（runner.start 每 run 生成新 runId）→ 计数归零。
      const AgentRunContext run2Ctx = AgentRunContext(
        runId: 'run-2',
        connectionId: 'conn-1',
        connectionName: '测试连接',
        databaseName: 'db1',
        dbType: DatabaseType.mysql,
        readOnly: false,
      );
      final out = await h.executor.execute(
        call: _call('save_saved_query', <String, dynamic>{
          'name': 'run2-0',
          'sql': 'SELECT 0',
        }),
        runCtx: run2Ctx,
        ledger: h.ledger,
        gates: h.gates,
      );
      expect(out.ok, isTrue);
      expect(saver.calls, 4);
      expect(saver.lastName, 'run2-0');
    });
  });

  group('T4 save_memory', () {
    test('成功：缺省 scope 在锁定连接下落 connection（source=agent）', () async {
      final _MemoryFake memory = _MemoryFake();
      final h = _Harness(memory: memory);
      final out = await h.run('save_memory', <String, dynamic>{
        'subject': 'orders.status',
        'content': 'status=3 表示已支付',
      });

      expect(out.ok, isTrue);
      expect(memory.saved, hasLength(1));
      final AiMemoryItem item = memory.saved.single;
      expect(item.scope, AiMemoryScope.connection);
      expect(item.connectionId, 'conn-1');
      expect(item.subject, 'orders.status');
      expect(item.content, 'status=3 表示已支付');
      expect(item.source, AiMemorySource.agent);
      final feed = _decode(out.toLLMJson());
      final Map<String, dynamic> data = feed['data'] as Map<String, dynamic>;
      expect(data['memoryId'], 'mem_fake_0');
      expect(data['scope'], 'connection');
      expect(data['subject'], 'orders.status');
      expect(h.stats.toolCalls, <String>['save_memory']);
    });

    test('缺省 scope 在无连接时落 global', () async {
      final _MemoryFake memory = _MemoryFake();
      final h = _Harness(connectionId: null, memory: memory);
      final out = await h.run('save_memory', <String, dynamic>{
        'content': '团队约定：金额列单位分',
      });
      expect(out.ok, isTrue);
      expect(memory.saved.single.scope, AiMemoryScope.global);
      expect(memory.saved.single.connectionId, isNull);
    });

    test('显式 scope=global / connection 分别落对应作用域', () async {
      final _MemoryFake memory = _MemoryFake();
      final h = _Harness(memory: memory);
      await h.run('save_memory', <String, dynamic>{
        'scope': 'global',
        'content': 'g',
      });
      await h.run('save_memory', <String, dynamic>{
        'scope': 'connection',
        'content': 'c',
      });
      expect(memory.saved[0].scope, AiMemoryScope.global);
      expect(memory.saved[1].scope, AiMemoryScope.connection);
      expect(memory.saved[1].connectionId, 'conn-1');
    });

    test('scope=connection 无锁定连接 → CONTEXT_REQUIRED 回喂', () async {
      final _MemoryFake memory = _MemoryFake();
      final h = _Harness(connectionId: null, memory: memory);
      final out = await h.run('save_memory', <String, dynamic>{
        'scope': 'connection',
        'content': 'x',
      });
      expect(out.ok, isFalse);
      expect(out.errorCode, AgentToolErrorCodes.contextRequired);
      expect(memory.saved, isEmpty);
    });

    test('参数非法：缺 content / scope 非法值 → INVALID_ARGUMENTS', () async {
      final _MemoryFake memory = _MemoryFake();
      final h = _Harness(memory: memory);
      final noContent = await h.run('save_memory', <String, dynamic>{
        'subject': 's',
      });
      final badScope = await h.run('save_memory', <String, dynamic>{
        'scope': 'universe',
        'content': 'x',
      });
      expect(noContent.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(badScope.errorCode, AgentToolErrorCodes.invalidArguments);
      expect(memory.saved, isEmpty);
    });
  });

  group('T4 list_memories', () {
    test('返回全局 + 锁定连接两作用域摘要（id/subject/content 截断）', () async {
      final _MemoryFake memory = _MemoryFake()
        ..global = <AiMemoryItem>[
          _memItem('g1', AiMemoryScope.global, subject: 'team', content: 'g'),
        ]
        ..connection = <AiMemoryItem>[
          _memItem(
            'c1',
            AiMemoryScope.connection,
            subject: 'orders.status',
            content: 'x' * 300, // 超 120 摘要截断
          ),
        ];
      final h = _Harness(memory: memory);
      final out = await h.run('list_memories');

      expect(out.ok, isTrue);
      final feed = _decode(out.toLLMJson());
      final Map<String, dynamic> data = feed['data'] as Map<String, dynamic>;
      expect(data['globalCount'], 1);
      expect(data['connectionCount'], 1);
      final List<dynamic> memories = data['memories'] as List<dynamic>;
      expect(memories, hasLength(2));
      final Map<String, dynamic> globalEntry =
          memories[0] as Map<String, dynamic>;
      final Map<String, dynamic> connEntry =
          memories[1] as Map<String, dynamic>;
      expect(globalEntry['id'], 'g1');
      expect(globalEntry['scope'], 'global');
      expect(connEntry['id'], 'c1');
      expect(connEntry['scope'], 'connection');
      expect(connEntry['subject'], 'orders.status');
      expect((connEntry['content'] as String).length, 121); // 120 + 省略号
    });

    test('空态：无记忆返回空列与零计数；无连接时连接段为空', () async {
      final _MemoryFake memory = _MemoryFake()
        ..global = <AiMemoryItem>[
          _memItem('g1', AiMemoryScope.global, content: 'g'),
        ];
      final h = _Harness(connectionId: null, memory: memory);
      final out = await h.run('list_memories');
      final feed = _decode(out.toLLMJson());
      final Map<String, dynamic> data = feed['data'] as Map<String, dynamic>;
      expect(data['globalCount'], 1);
      expect(data['connectionCount'], 0);
      expect((data['memories'] as List<dynamic>), hasLength(1));
    });
  });

  group('T4 读工具历史挂钩（execute_readonly_sql / get_sample_data）', () {
    test('成功执行 → 写历史一条（字段口径对齐 T1：快照连接/库/方言 + '
        'affectedRows=行数 + error null）', () async {
      final _HistorySpy history = _HistorySpy();
      final h = _Harness(history: history)
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
          <String, dynamic>{'id': 2},
        ];
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT id FROM users',
      });

      expect(out.ok, isTrue);
      expect(history.writes, hasLength(1));
      final Map<String, Object?> write = history.writes.single;
      expect(write['sql'], 'SELECT id FROM users');
      expect(write['connectionId'], 'conn-1');
      expect(write['connectionName'], '测试连接');
      expect(write['database'], 'db1');
      expect(write['databaseType'], DatabaseType.mysql);
      expect(write['affectedRows'], 2);
      expect(write['error'], isNull);
      expect(write['durationMs'], isA<int>());
    });

    test('get_sample_data 成功 → 构造语句同样落历史', () async {
      final _HistorySpy history = _HistorySpy();
      final h = _Harness(history: history)
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ];
      final out = await h.run('get_sample_data', <String, dynamic>{
        'table': 'users',
        'limit': 5,
      });
      expect(out.ok, isTrue);
      expect(history.writes.single['sql'], 'SELECT * FROM users LIMIT 5');
    });

    test('EXPLAIN / INFORMATION_SCHEMA / SHOW 语句跳过历史写入', () async {
      final _HistorySpy history = _HistorySpy();
      final h = _Harness(history: history)
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'x': 1},
        ];
      for (final String sql in <String>['EXPLAIN SELECT 1', 'SHOW TABLES']) {
        final out = await h.run('execute_readonly_sql', <String, dynamic>{
          'sql': sql,
        });
        expect(out.ok, isTrue, reason: sql);
      }
      // T2（2026-09-29）起 information_schema 两段式在 MySQL 锁定库下由
      // AC4.4 白名单放行（目录元数据窄豁免，执法面归
      // agent_tool_executor_a2_test.dart T2 组覆盖）；performance_schema
      // 两段式仍被执法拦截（无从执行）。本用例验证**历史跳过判定本身**，
      // 两条语句统一走 PG（两段式 = schema 库内寻址，不执法）保持断言形态。
      final pg = _Harness(dbType: DatabaseType.postgresql, history: history)
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'x': 1},
        ];
      for (final String sql in <String>[
        'SELECT * FROM information_schema.tables',
        'select * from performance_schema.events',
      ]) {
        final out = await pg.run('execute_readonly_sql', <String, dynamic>{
          'sql': sql,
        });
        expect(out.ok, isTrue, reason: sql);
      }
      expect(history.writes, isEmpty);
      // 执行照常，仅历史跳过。
      expect(h.db.executeQueryCalls + pg.db.executeQueryCalls, 4);
    });

    test('执行失败 → 不写历史；历史写抛错 → 工具回喂不受影响', () async {
      final _HistorySpy history = _HistorySpy();
      final failing = _Harness(history: history)
        ..db.queryError = StateError('boom');
      final errOut = await failing.run(
        'execute_readonly_sql',
        <String, dynamic>{'sql': 'SELECT 1'},
      );
      expect(errOut.ok, isFalse);
      expect(history.writes, isEmpty);

      history.error = StateError('prefs down');
      final ok = _Harness(history: history)
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ];
      final out = await ok.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT 1',
      });
      expect(out.ok, isTrue); // 写失败吞错，不阻断回喂
    });

    test('recorder 未装配 → 跳过（无副作用、不抛错）', () async {
      final h = _Harness()
        ..db.queryResult = <Map<String, dynamic>>[
          <String, dynamic>{'id': 1},
        ];
      final out = await h.run('execute_readonly_sql', <String, dynamic>{
        'sql': 'SELECT 1',
      });
      expect(out.ok, isTrue);
    });
  });

  group('T4 describe_table 记忆合并', () {
    test('命中记忆 → memoryNotes 加性出现，连接级优先于全局', () async {
      final _MemoryFake memory = _MemoryFake()
        ..tableMatches = <AiMemoryItem>[
          // forTable 返回合并列（updatedAt 新→旧）；连接级须排到全局前。
          _memItem(
            'g1',
            AiMemoryScope.global,
            subject: 'users.name',
            content: '全局释义',
            updatedAt: 2,
          ),
          _memItem(
            'c1',
            AiMemoryScope.connection,
            subject: 'users.status',
            content: '连接级释义',
            updatedAt: 1,
          ),
        ];
      final h = _Harness(memory: memory)
        ..db.columns = <DbColumn>[
          DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
        ];
      final out = await h.run('describe_table', <String, dynamic>{
        'table': 'users',
      });

      expect(out.ok, isTrue);
      final feed = _decode(out.toLLMJson());
      final Map<String, dynamic> data = feed['data'] as Map<String, dynamic>;
      final List<dynamic> notes = data['memoryNotes'] as List<dynamic>;
      expect(notes, hasLength(2));
      expect((notes[0] as Map<String, dynamic>)['subject'], 'users.status');
      expect((notes[1] as Map<String, dynamic>)['subject'], 'users.name');
    });

    test('无记忆 → memoryNotes 字段省略（可选字段 skip 风格）', () async {
      final _MemoryFake memory = _MemoryFake();
      final h = _Harness(memory: memory)
        ..db.columns = <DbColumn>[
          DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
        ];
      final out = await h.run('describe_table', <String, dynamic>{
        'table': 'users',
      });
      final feed = _decode(out.toLLMJson());
      final Map<String, dynamic> data = feed['data'] as Map<String, dynamic>;
      expect(data.containsKey('memoryNotes'), isFalse);
      expect(data['columns'], isNotEmpty);
    });

    test('记忆面抛错 → describe 主体照常（无 memoryNotes）', () async {
      final _MemoryFake memory = _MemoryFake()
        ..forTableError = StateError('memory down');
      final h = _Harness(memory: memory)
        ..db.columns = <DbColumn>[
          DbColumn(name: 'id', type: 'int', isPrimaryKey: true),
        ];
      final out = await h.run('describe_table', <String, dynamic>{
        'table': 'users',
      });
      expect(out.ok, isTrue);
      final feed = _decode(out.toLLMJson());
      final Map<String, dynamic> data = feed['data'] as Map<String, dynamic>;
      expect(data.containsKey('memoryNotes'), isFalse);
      expect(data['columns'], isNotEmpty);
    });
  });
}
