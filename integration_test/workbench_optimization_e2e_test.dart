// ============================================================================
// Optimization kind 真库 e2e（2b.3 · tasks-workbench-2b.md §6.4 e2e 口径）。
//
// 被测：agent `explain_plan`（L0 只读通道）成功后的 optimization 旁挂推送
// 全链——真实 MySQL（网关壳 adapter 经 embedded dbmaster server 走 /api/gw）
// EXPLAIN 直驱 AgentToolExecutor（**免 LLM**：不装配 runner/chat），uiPort =
// 真实 [AgentUiPortImpl] + 真实 [WorkbenchStageController]。断言：
//   001 optimization tab 落地（stageVisible + kind + 载荷 sql 精确串）
//   002 report.executionPlan 非空（真实 EXPLAIN 解析出步骤）
//   003 瓶颈层按服务输出呈现（大表全表扫描 → fullTableScan 等，结构非空）
//   004 索引推荐层按服务输出呈现（WHERE 列提取 → 推荐 + DDL 语句在场）
//   005 tab 载荷完整（sql / report / 四层字段同源）
//   006 R6 去重：同 SQL 重复解释 → tab 恒 1 复用刷新；异 SQL 各开各的
//
// 自建自删专用库（generateTestDatabaseName() → dbmaster_test_<ts>，绝不
// 污染共享状态）。环境不可达（embedded server 二进制缺失 / DBMASTER_MYSQL_*
// 缺参 / 连不上）以可 grep 的 `MYSQL_OPT_E2E_SKIP` 打印并跳过（无假绿，
// 沿 MYSQL_E2E_SKIP 惯例）。
//
// 运行（Windows 示例，凭据见 workspace test_db_server.txt）：
//   DBMASTER_SERVER_BIN=dist/Release/dbmaster-server.exe \
//   flutter test integration_test/workbench_optimization_e2e_test.dart \
//     --dart-define=DBMASTER_MYSQL_HOST=192.168.3.128 \
//     --dart-define=DBMASTER_MYSQL_USER=root \
//     --dart-define=DBMASTER_MYSQL_PASSWORD=...
// ============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/audit_log_entry.dart' show AgentGateDecision;
import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbServer;
import 'package:dbmaster/models/query_optimizer/execution_plan.dart'
    show BottleneckType;
import 'package:dbmaster/organisms/ai_workbench/agent_ui_port_impl.dart';
import 'package:dbmaster/organisms/ai_workbench/workbench_stage.dart';
import 'package:dbmaster/services/ai/agent/agent_gate.dart';
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart';
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel;
import 'package:dbmaster/services/ai/agent/agent_tool_executor.dart'
    show AgentDbAccess, AgentToolCall, AgentToolExecutor;
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// 种子行数（大表语义：无索引全表查 → 全表扫描瓶颈确定性成立）。
const int _seedRows = 12000;

/// 种子表名（自建专用库内）。
const String _table = 'opt_big';

/// 被测语句：大表无索引等值查（全表扫描 + WHERE 列可提取 → 索引推荐）。
const String _sql = 'SELECT * FROM opt_big WHERE val = 42';

/// 异 SQL（R6 各开各的断言用）。
const String _otherSql = 'SELECT * FROM opt_big WHERE val = 99';

/// 审计 tap：捕获 executor 传入的原始记录（敏感面流向证明），不落真实
/// AuditLogService（本 e2e 免 LLM、免持久化面）。
final List<Map<String, Object?>> _auditRecords = <Map<String, Object?>>[];

Future<void> _audit({
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
  _auditRecords.add(<String, Object?>{
    'tool': tool,
    'gateDecision': gateDecision,
    'success': success,
  });
}

/// MySQL 种子：opt_big（id PK + val 无索引 + payload），12,000 行。
///
/// 网关单语句模型下 SET SESSION 不跨语句 → 不用递归 CTE，1,000 行/批多值
/// INSERT（12 批）；ANALYZE 刷新统计使 EXPLAIN rows 估值确定。
Future<void> _seed(MySQLAdapter adapter) async {
  await adapter.executeQuery(
    'CREATE TABLE $_table ('
    'id INT PRIMARY KEY AUTO_INCREMENT, '
    'val INT NOT NULL, '
    'payload VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  const batchSize = 1000;
  for (var offset = 0; offset < _seedRows; offset += batchSize) {
    final values = StringBuffer();
    for (var n = offset + 1; n <= offset + batchSize; n++) {
      if (values.isNotEmpty) values.write(',');
      values.write("($n,'payload_$n')");
    }
    await adapter.executeQuery(
      'INSERT INTO $_table (val, payload) VALUES $values',
    );
  }
  try {
    await adapter.executeQuery('ANALYZE TABLE $_table');
  } catch (_) {
    // 统计刷新失败不阻断（InnoDB 新表默认统计亦接近实值）。
  }
}

void main() {
  bool gatewayReady = false;
  setUpAll(() async {
    gatewayReady = await ensureEmbeddedServerForMysqlE2E();
  });

  group('Optimization 旁挂推送 · MySQL 真库（免 LLM 直驱 executor）', () {
    MySQLAdapter? seedAdapter;
    DatabaseService? dbService;
    DbServer? server;
    String? testDbName;
    late WorkbenchStageController stageController;
    late AgentUiPortImpl uiPort;
    late AgentToolExecutor executor;
    bool ready = false;

    setUpAll(() async {
      if (!gatewayReady || !MySQLTestConfig.available) return;
      stageController = WorkbenchStageController();
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      final seed = MySQLAdapter();
      try {
        await seed.connect(
          DatabaseConnection(
            id: 'opt_e2e_seed_mysql',
            name: 'Optimization E2E Seed',
            type: DatabaseType.mysql,
            host: MySQLTestConfig.host,
            port: MySQLTestConfig.port,
            username: MySQLTestConfig.username,
            password: MySQLTestConfig.password,
          ),
        );
        await seed.createDatabase(testDbName!);
        await seed.useDatabase(testDbName!);
        await _seed(seed);
        seedAdapter = seed;

        // 被测主体：真实 DatabaseService（EXPLAIN 经此连接注入 executor）。
        final svc = DatabaseService();
        final dbServer = DbServer(
          id: 'opt_e2e_mysql',
          name: 'Optimization E2E MySQL',
          type: DatabaseType.mysql,
          host: MySQLTestConfig.host,
          port: MySQLTestConfig.port,
          username: MySQLTestConfig.username,
          password: MySQLTestConfig.password,
          database: testDbName,
        );
        final connected = await svc.connect(dbServer);
        if (!connected) {
          await svc.disconnect();
        } else {
          dbService = svc;
          server = dbServer;
        }

        // uiPort = 真实 AgentUiPortImpl + 真实舞台 controller（生产装配面）。
        uiPort = AgentUiPortImpl(
          stageController: stageController,
          // 本 e2e 只走 openOptimization——structure 取数与建议落账不触达。
          structureFetcher: (_) async => throw StateError('unused in e2e'),
          landSuggestionMessage: (_) {},
        );

        // 生产装配形态（AiPanelProvider._createAgentAnalysis 同款）：真门 +
        // 真分析工厂；explain_plan 无 L0.5 分析面（agent_gate.dart:260）。
        final service = svc;
        executor = AgentToolExecutor(
          gate: AgentGate(
            createAnalysis: (AgentRunContext runCtx) => AgentGateAnalysis(
              getExplainPlan: (String sql) => service.getExplainPlan(
                sql,
                connectionId: runCtx.connectionId,
              ),
              rowThreshold: 10000,
              dbType: runCtx.dbType,
            ),
          ),
          db: AgentDbAccess(
            getTables: (String? connectionId, String? databaseName) =>
                service.getTables(
                  connectionId: connectionId,
                  databaseName: databaseName,
                ),
            getTableColumns: service.getTableColumns,
            getTableIndexes: service.getTableIndexes,
            getForeignKeys: service.getForeignKeys,
            getCreateTableSql: service.getCreateTableSql,
            getExplainPlan: (String sql, {String? connectionId}) =>
                service.getExplainPlan(sql, connectionId: connectionId),
            executeQuery:
                (String sql, {String? connectionId, String? database}) =>
                    service.executeQuery(
                      sql,
                      connectionId: connectionId,
                      database: database,
                    ),
          ),
          audit: _audit,
        );
        ready = true;
      } catch (e) {
        // ignore: avoid_print
        print('MYSQL_OPT_E2E_SKIP: MySQL 环境不可达：$e');
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
      final dbName = testDbName;
      if (seed != null && dbName != null && seed.isConnected) {
        try {
          await seed.executeQuery('DROP DATABASE IF EXISTS `$dbName`');
        } catch (_) {}
        try {
          await seed.disconnect();
        } catch (_) {}
      }
      stageController.dispose();
    });

    Future<void> explain(String sql) async {
      final out = await executor.execute(
        call: AgentToolCall(
          id: 'call-${_auditRecords.length}',
          name: 'explain_plan',
          argumentsJson: jsonEncode(<String, dynamic>{'sql': sql}),
        ),
        runCtx: AgentRunContext(
          runId: 'opt-e2e-run',
          connectionId: server!.id,
          connectionName: server!.name,
          databaseName: server!.database,
          dbType: DatabaseType.mysql,
          readOnly: false,
        ),
        ledger: AgentPermissionLedger(),
        uiPort: uiPort,
      );
      expect(out.ok, isTrue, reason: '主链回喂不受旁挂影响：$sql');
      expect(out.errorCode, isNull);
    }

    test('OPT-E2E-001 explain 成功 → optimization tab 落地 + report.executionPlan'
        ' 非空 + 瓶颈/索引推荐结构非空 + 载荷完整', () async {
      if (!ready) {
        // ignore: avoid_print
        print('MYSQL_OPT_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      await explain(_sql);

      // tab 落地（R6 推送链末端）。
      expect(stageController.stageVisible, isTrue, reason: 'openXxx 自动开舞台');
      expect(stageController.tabs, hasLength(1));
      expect(
        stageController.tabs.single.kind,
        WorkbenchStageTabKind.optimization,
      );

      // 载荷完整（sql 精确串 + report 同源）。
      final StageOptimizationData? payload =
          stageController.tabs.single.optimization;
      expect(payload, isNotNull);
      expect(payload!.sql, _sql, reason: '去重键 = 原 SQL 精确串');
      final report = payload.report;

      // report.executionPlan 非空（真实 EXPLAIN 解析出步骤）。
      expect(report.executionPlan.steps, isNotEmpty);
      expect(report.executionPlan.originalQuery, _sql);
      expect(
        report.executionPlan.databaseType,
        'mysql',
        reason: '方言串口径 = runCtx.dbType.name（gate analysis 同款）',
      );

      // 瓶颈层按服务输出呈现：大表无索引全表查确定性产出 fullTableScan
      //（≥0 即可，断言结构非空 + 该类型在场）。
      expect(report.bottlenecks, isNotEmpty);
      expect(
        report.bottlenecks.any((b) => b.type == BottleneckType.fullTableScan),
        isTrue,
        reason: 'SELECT * FROM opt_big（无索引）→ 全表扫描瓶颈',
      );

      // 索引推荐层按服务输出呈现：WHERE val 等值 → 提取 val 列 → 推荐
      // 非空且 DDL 语句在场（「应用此索引」填编辑器槽的数据源）。
      expect(report.indexRecommendations, isNotEmpty);
      expect(
        report.indexRecommendations.every(
          (r) => r.ddlStatement != null && r.ddlStatement!.isNotEmpty,
        ),
        isTrue,
      );

      // 重写建议/摘要/耗时字段齐全（tab 载荷完整）。
      expect(report.queryRewrites, isNotNull);
      expect(report.summary, isNotEmpty);
      expect(report.analysisDuration, isNotNull);

      // 主链审计：allowed + success（旁挂不影响审计判定）。
      expect(_auditRecords.last['gateDecision'], AgentGateDecision.allowed);
      expect(_auditRecords.last['success'], isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test(
      'OPT-E2E-002 R6 去重：同 SQL 重复解释 tab 恒 1 复用刷新；异 SQL 各开各的',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('MYSQL_OPT_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        await explain(_sql);
        expect(stageController.tabs, hasLength(1));
        final firstId = stageController.tabs.single.id;

        // 同 SQL 重复解释 → 复用同 tab（载荷替换刷新，不累积）。
        await explain(_sql);
        expect(stageController.tabs, hasLength(1));
        expect(stageController.tabs.single.id, firstId);
        expect(stageController.tabs.single.optimization?.sql, _sql);

        // 异 SQL → 各开各的。
        await explain(_otherSql);
        expect(stageController.tabs, hasLength(2));
        expect(
          stageController.tabs.map((t) => t.optimization?.sql).toList(),
          containsAll(<String>[_sql, _otherSql]),
        );
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
