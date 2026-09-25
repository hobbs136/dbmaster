// ============================================================================
// Agent L0.5 门簇真库集成测试（tasks-ai-agent.md T17 / design §6.7 门簇、§8
// 豁免、D6 判定链）。
//
// 被测：AgentGateAnalysis.analyze（T05 读前分析判定内核）+ AgentGate.evaluate
// （T06 门判定序）。EXPLAIN 取数直连真实 DatabaseService（经连接注入）——
// MySQL/PG/SS 均为网关壳 adapter，经 embedded dbmaster server 走 /api/gw 到
// 真实测试库（连接参数 --dart-define=DBMASTER_*，凭据不入库；库信息见
// workspace test_db_server.txt）。
//
// 覆盖（AC8.2/8.3/8.4/8.6/8.7 + §8 豁免正反 + AC4.5）：
// - MySQL 主战场（gate_big 12,000 行无二级索引 / gate_indexed 12,000 行含
//   idx_val，阈值 10,000）：
//   001 无 WHERE 全表查 → confirm(l05) + impact 字段齐（AC8.2 判定面/AC8.4 数据面）
//   002 confirm(l05) × 账本 ⑤ 会话放行 → allow@l05（D12）
//   003 索引范围查（type=range）→ allow（AC8.3）
//   004 PK 等值点查 → X1 豁免记录 + allow；PK 范围 → X1 失效（§8 失效条件一）
//   005 X2 早停正反：LIMIT 100 无 ORDER BY → allow；ORDER BY → confirm；
//       LIMIT 201 → 超 200 上限不豁免；get_sample_data LIMIT clamp 同形态
//   006 X2 豁免 × R10 独立命中 → 仍 confirm（§8 联动，注入阈值 100 演示）
//   007 阈值敏感：同语句同表，10,000 → confirm / 50,000 → allow（AC8.7，
//       门工厂每次判定重新构造 = 生产装配形态）
//   008 explain_plan 工具：无 L0.5 分析面 allow@l0 + 计划真往返 + 目标表
//       数据读前读后一致（AC4.5）
// - PG 抽查：
//   009 Seq Scan 大表 → confirm + fullScan
//   010 Index Scan 命中 → allow
//   011 PK 点查 X1（PG pkey 分支：using <t>_pkey + Index Cond 单列等值）
// - SS fail-closed：
//   012 网关 EXPLAIN 不支持（UnsupportedError）→ analysisUnavailable →
//       confirm(l05)（AC8.6）
//
// 自建自删专用库（generateTestDatabaseName() → dbmaster_test_<ts>，绝不污染
// 共享状态、不依赖用例间顺序）。环境不可达（embedded server 二进制缺失 /
// DBMASTER_* 缺参 / 连不上）时以可 grep 的 *_GATE_E2E_SKIP 打印并跳过
// （无假绿，沿 MYSQL_E2E_SKIP 惯例）。
//
// 运行（Windows 示例，凭据见 workspace test_db_server.txt）：
//   DBMASTER_SERVER_BIN=dist/Release/dbmaster-server.exe \
//   flutter test integration_test/agent_gate_l05_real_db_test.dart \
//     --dart-define=DBMASTER_MYSQL_HOST=192.168.3.128 \
//     --dart-define=DBMASTER_MYSQL_USER=root \
//     --dart-define=DBMASTER_MYSQL_PASSWORD=... \
//     --dart-define=DBMASTER_PG_HOST=192.168.3.128 \
//     --dart-define=DBMASTER_PG_USER=postgres \
//     --dart-define=DBMASTER_PG_PASSWORD=... \
//     --dart-define=DBMASTER_SQLSERVER_HOST=192.168.3.128 \
//     --dart-define=DBMASTER_SQLSERVER_USER=sa \
//     --dart-define=DBMASTER_SQLSERVER_PASSWORD=...
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/database_models.dart' show DatabaseType, DbServer;
import 'package:dbmaster/services/ai/agent/agent_gate.dart';
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart';
import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';
import 'package:dbmaster/services/ai/agent/agent_tool_catalog.dart'
    show AgentGateLevel, AgentToolCatalog, AgentToolSpec;
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/adapters/postgresql_adapter.dart';
import 'package:dbmaster/services/adapters/sqlserver_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';

import 'config/mysql_test_config.dart';
import 'config/postgresql_test_config.dart';
import 'config/sqlserver_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// D6：agent 专属 L0.5 行阈值默认值（QuerySettingsService.agentL05RowThreshold
/// 口径；本测试经构造注入，不读设置存储——AC8.7 阈值敏感即经此注入面验证）。
const int _defaultThreshold = 10000;

/// 种子行数（任务书：≥ 阈值；EXPLAIN 估值经 ANALYZE 后 ≈ 12,000）。
const int _seedRows = 12000;

/// AC8.7 翻转阈值：> EXPLAIN 估值（≈12,000）→ 同语句判定翻转。
const int _flippedThreshold = 50000;

/// §8 联动演示阈值（AI-GATE-E2E-006）：低于 T02 设置层 clamp 下限（1,000），
/// 仅在分析内核注入面使用——AgentGateAnalysis 不 clamp（clamp 归
/// QuerySettingsService，T05 契约），100 使 `LIMIT 150` 的 R10 有效行数
/// （min(12,000,150)=150）独立命中，演示「豁免消解 R9 但 R10 仍 confirm」。
const int _linkageThreshold = 100;

/// 从目录全集取真实 spec（判定序①按名判存；execute_readonly_sql /
/// get_sample_data / explain_plan 均 milestone 1）。
AgentToolSpec _catalogSpec(String name) => AgentToolCatalog.specsFor(
  milestone: 3,
).firstWhere((AgentToolSpec s) => s.name == name);

/// 生产装配形态的分析内核（design §4.2：dbService 经接口注入——闭包绑
/// `dbService.getExplainPlan`，阈值读当前配置）。
AgentGateAnalysis _analysis(
  DatabaseService service, {
  required DatabaseType dbType,
  int threshold = _defaultThreshold,
}) => AgentGateAnalysis(
  getExplainPlan: (String sql) => service.getExplainPlan(sql),
  rowThreshold: threshold,
  dbType: dbType,
);

/// run 启动快照（D15）：connectionId = DatabaseService 连接 id（账本 ⑤ 的键）。
AgentRunContext _runCtx(DbServer server) => AgentRunContext(
  runId: 'gate-e2e-run',
  connectionId: server.id,
  connectionName: server.name,
  databaseName: server.database,
  dbType: server.type,
  readOnly: false,
);

/// 数据探针（AC4.5 读前读后一致断言）：聚合值统一按字符串归一（网关解码
/// 的 Decimal/int 形态不一）。
Future<Map<String, String>> _probeTable(
  DatabaseService service,
  String table,
) async {
  final rows = await service.executeQuery(
    'SELECT COUNT(*) AS c, SUM(val) AS s, MAX(val) AS m FROM $table',
  );
  final row = rows.isEmpty ? <String, dynamic>{} : rows.first;
  return <String, String>{
    'count': '${row['c']}',
    'sum': '${row['s']}',
    'max': '${row['m']}',
  };
}

/// MySQL 种子：gate_big（无二级索引）+ gate_indexed（idx_val），各 12,000 行。
///
/// 网关单语句模型下 SET SESSION 不跨语句 → 不用递归 CTE，500 行/批多值
/// INSERT（24 批）；ANALYZE 刷新统计使 EXPLAIN rows 估值确定 ≥ 阈值。
Future<void> _seedMySqlGateTables(MySQLAdapter adapter) async {
  await adapter.executeQuery(
    'CREATE TABLE gate_big ('
    'id INT PRIMARY KEY AUTO_INCREMENT, '
    'val INT NOT NULL, '
    'payload VARCHAR(64) NOT NULL) ENGINE=InnoDB',
  );
  await adapter.executeQuery(
    'CREATE TABLE gate_indexed ('
    'id INT PRIMARY KEY AUTO_INCREMENT, '
    'val INT NOT NULL, '
    'payload VARCHAR(64) NOT NULL, '
    'INDEX idx_val (val)) ENGINE=InnoDB',
  );
  const batchSize = 1000;
  for (var offset = 0; offset < _seedRows; offset += batchSize) {
    final values = StringBuffer();
    for (var n = offset + 1; n <= offset + batchSize; n++) {
      if (values.isNotEmpty) values.write(',');
      values.write("($n,'payload_$n')");
    }
    await adapter.executeQuery(
      'INSERT INTO gate_big (val, payload) VALUES $values',
    );
    await adapter.executeQuery(
      'INSERT INTO gate_indexed (val, payload) VALUES $values',
    );
  }
  try {
    await adapter.executeQuery('ANALYZE TABLE gate_big');
    await adapter.executeQuery('ANALYZE TABLE gate_indexed');
  } catch (_) {
    // 统计刷新失败不阻断（InnoDB 新表默认统计亦接近实值）。
  }
}

/// PG 种子：同构两表（generate_series 单语句灌 12,000 行）+ ANALYZE。
Future<void> _seedPgGateTables(PostgreSQLAdapter adapter) async {
  await adapter.executeQuery(
    'CREATE TABLE gate_big ('
    'id SERIAL PRIMARY KEY, val INT NOT NULL, payload TEXT NOT NULL)',
  );
  await adapter.executeQuery(
    'CREATE TABLE gate_indexed ('
    'id SERIAL PRIMARY KEY, val INT NOT NULL, payload TEXT NOT NULL)',
  );
  await adapter.executeQuery('CREATE INDEX idx_val ON gate_indexed (val)');
  await adapter.executeQuery(
    "INSERT INTO gate_big (val, payload) "
    "SELECT i, 'payload_' || i FROM generate_series(1, $_seedRows) AS i",
  );
  await adapter.executeQuery(
    "INSERT INTO gate_indexed (val, payload) "
    "SELECT i, 'payload_' || i FROM generate_series(1, $_seedRows) AS i",
  );
  try {
    await adapter.executeQuery('ANALYZE gate_big');
    await adapter.executeQuery('ANALYZE gate_indexed');
  } catch (_) {
    // 同上：统计刷新失败不阻断。
  }
}

void main() {
  // 三个网关族共用同一 embedded server 会话（helper 实现彼此等价，起一个
  // 即全族可用；二进制缺失打印 MYSQL_E2E_SKIP）。
  bool gatewayReady = false;
  setUpAll(() async {
    gatewayReady = await ensureEmbeddedServerForMysqlE2E();
  });

  // ==========================================================================
  // MySQL 主战场
  // ==========================================================================
  group('Agent L0.5 门簇 · MySQL 主战场（真库）', () {
    MySQLAdapter? seedAdapter;
    DatabaseService? dbService;
    DbServer? server;
    String? testDbName;
    bool ready = false;

    setUpAll(() async {
      if (!gatewayReady || !MySQLTestConfig.available) return;
      testDbName = MySQLTestConfig.generateTestDatabaseName();
      final seed = MySQLAdapter();
      try {
        await seed.connect(
          DatabaseConnection(
            id: 'agent_gate_seed_mysql',
            name: 'Agent Gate E2E Seed',
            type: DatabaseType.mysql,
            host: MySQLTestConfig.host,
            port: MySQLTestConfig.port,
            username: MySQLTestConfig.username,
            password: MySQLTestConfig.password,
          ),
        );
        await seed.createDatabase(testDbName!);
        await seed.useDatabase(testDbName!);
        await _seedMySqlGateTables(seed);
        seedAdapter = seed;

        // 被测主体：真实 DatabaseService（getExplainPlan 经此连接注入分析内核）。
        final svc = DatabaseService();
        final dbServer = DbServer(
          id: 'agent_gate_e2e_mysql',
          name: 'Agent Gate E2E MySQL',
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
        print('MYSQL_GATE_E2E_SKIP: MySQL 环境不可达：$e');
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
    });

    test(
      'AI-GATE-E2E-001 无 WHERE 大表全查 → confirm(l05) + impact 字段齐（AC8.2/AC8.4）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('MYSQL_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        const sql = 'SELECT * FROM gate_big';

        // 判定面（AC8.2）：12,000 行无索引全表查（阈值 10,000）→ 需确认。
        final result = await _analysis(
          dbService!,
          dbType: DatabaseType.mysql,
        ).analyze(sql: sql, connectionId: server!.id);
        expect(result.requiresConfirmation, isTrue,
            reason: '无 WHERE 全表查 EXPLAIN 估值($_seedRows 行) ≥ 阈值($_defaultThreshold)');

        // 数据面（AC8.4）：EXPLAIN 真往返产出的影响面字段（进确认卡）。
        expect(result.impact.analysisUnavailable, isFalse);
        expect(result.impact.fullScan, isTrue, reason: 'ALL 扫描形态信号（R9）');
        expect(result.impact.estimatedRows, isNotNull);
        expect(result.impact.estimatedRows!,
            greaterThanOrEqualTo(_defaultThreshold),
            reason: '真实 EXPLAIN 估值（种子 $_seedRows 行 + ANALYZE）应 ≥ 阈值');
        expect(result.impact.scannedTables, contains('gate_big'));
        expect(result.impact.indexSummary, isNotNull,
            reason: '确认卡「索引缺失情况」行数据源（indexSummary）');

        // 门判定面（T06 ④）：execute_readonly_sql 升 L0.5 → confirm(l05)
        // 携带 impact（确认卡唯一消费面）。
        final gate = AgentGate(
          createAnalysis: (AgentRunContext ctx) =>
              _analysis(dbService!, dbType: ctx.dbType),
        );
        final decision = await gate.evaluate(
          spec: _catalogSpec('execute_readonly_sql'),
          args: <String, dynamic>{'sql': sql},
          runCtx: _runCtx(server!),
          ledger: AgentPermissionLedger(),
        );
        expect(decision.kind, GateDecisionKind.confirm);
        expect(decision.level, AgentGateLevel.l05);
        expect(decision.impact, isNotNull);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('AI-GATE-E2E-002 confirm(l05) × 账本 ⑤ 会话放行 → allow@l05（D12）',
        () async {
      if (!ready) {
        // ignore: avoid_print
        print('MYSQL_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      const sql = 'SELECT * FROM gate_big';
      final gate = AgentGate(
        createAnalysis: (AgentRunContext ctx) =>
            _analysis(dbService!, dbType: ctx.dbType),
      );
      final ledger = AgentPermissionLedger();

      final before = await gate.evaluate(
        spec: _catalogSpec('execute_readonly_sql'),
        args: <String, dynamic>{'sql': sql},
        runCtx: _runCtx(server!),
        ledger: ledger,
      );
      expect(before.kind, GateDecisionKind.confirm, reason: '放行前按 L0.5 判 confirm');

      ledger.allowL05(server!.id);
      final after = await gate.evaluate(
        spec: _catalogSpec('execute_readonly_sql'),
        args: <String, dynamic>{'sql': sql},
        runCtx: _runCtx(server!),
        ledger: ledger,
      );
      expect(after.kind, GateDecisionKind.allow, reason: '⑤ 会话放行短路（D12）');
      expect(after.level, AgentGateLevel.l05,
          reason: 'allowed_session 审计判据（allow@l05）的唯一产生源');
      expect(after.impact, isNull, reason: '放行不产确认卡数据');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('AI-GATE-E2E-003 索引范围查 → allow（AC8.3）', () async {
      if (!ready) {
        // ignore: avoid_print
        print('MYSQL_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      const sql = 'SELECT * FROM gate_indexed WHERE val BETWEEN 1 AND 50';

      final result = await _analysis(
        dbService!,
        dbType: DatabaseType.mysql,
      ).analyze(sql: sql, connectionId: server!.id);
      expect(result.requiresConfirmation, isFalse,
          reason: 'idx_val 命中（type=range）小范围查询无信号');
      expect(result.impact.fullScan, isFalse);
      expect(result.exemption, AgentL05Exemption.none,
          reason: 'range 非唯一访问形态，不属 X1/X2');

      final gate = AgentGate(
        createAnalysis: (AgentRunContext ctx) =>
            _analysis(dbService!, dbType: ctx.dbType),
      );
      final decision = await gate.evaluate(
        spec: _catalogSpec('execute_readonly_sql'),
        args: <String, dynamic>{'sql': sql},
        runCtx: _runCtx(server!),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.allow);
      expect(decision.level, AgentGateLevel.l0, reason: '全消 → 干净放行@声明档');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('AI-GATE-E2E-004 PK 等值点查 → X1 豁免记录 + allow；PK 范围 → 不豁免（§8 X1）',
        () async {
      if (!ready) {
        // ignore: avoid_print
        print('MYSQL_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      // 正：主键等值点查。当前规则体下 const 访问结构性不产 R9 finding
      //（const/eq_ref 不属低效扫描）——X1 命中记录「为何未弹卡」供审计与
      // 轨迹（T05 交付说明语义），此处验证 allow + 豁免形态如实记录。
      const sql = 'SELECT * FROM gate_big WHERE id = 42';
      final result = await _analysis(
        dbService!,
        dbType: DatabaseType.mysql,
      ).analyze(sql: sql, connectionId: server!.id);
      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.uniqueKeyPointLookup);
      expect(result.impact.fullScan, isFalse);
      expect(result.impact.analysisUnavailable, isFalse);

      // 反（§8 失效条件一）：主键范围（非等值）→ 访问形态降级 type=range，
      // 不豁免（结果集小 → allow，但豁免必须为 none）。
      const rangeSql = 'SELECT * FROM gate_big WHERE id > 11800';
      final rangeResult = await _analysis(
        dbService!,
        dbType: DatabaseType.mysql,
      ).analyze(sql: rangeSql, connectionId: server!.id);
      expect(rangeResult.requiresConfirmation, isFalse);
      expect(rangeResult.exemption, AgentL05Exemption.none,
          reason: '范围访问非唯一形态 → X1 失效（保守回严格档）');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('AI-GATE-E2E-005 X2 早停正反：LIMIT 100 → 豁免；ORDER BY/LIMIT 201 → 失效（§8 X2）',
        () async {
      if (!ready) {
        // ignore: avoid_print
        print('MYSQL_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      final analysis = _analysis(dbService!, dbType: DatabaseType.mysql);

      // 正：LIMIT ≤ 200 无 ORDER BY → 早停（有效行数 min(估值,100) < 阈值）。
      const sql = 'SELECT * FROM gate_big LIMIT 100';
      final result = await analysis.analyze(sql: sql, connectionId: server!.id);
      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.smallLimitEarlyStop);
      expect(result.impact.fullScan, isFalse);

      // get_sample_data 工具同形态（design §4.1「升 L0.5」工具，LIMIT clamp
      // 1-100 → 构造 SQL 恒落 X2 早停区间）→ 门 allow@l0。
      final gate = AgentGate(
        createAnalysis: (AgentRunContext ctx) =>
            _analysis(dbService!, dbType: ctx.dbType),
      );
      final sampleDecision = await gate.evaluate(
        spec: _catalogSpec('get_sample_data'),
        args: <String, dynamic>{'table': 'gate_big'},
        runCtx: _runCtx(server!),
        ledger: AgentPermissionLedger(),
      );
      expect(sampleDecision.kind, GateDecisionKind.allow);
      expect(sampleDecision.level, AgentGateLevel.l0);

      // 反一：ORDER BY 破坏早停（filesort 需全扫）→ R9 按原估值命中 → confirm。
      const orderSql = 'SELECT * FROM gate_big ORDER BY payload LIMIT 100';
      final orderResult = await analysis.analyze(
        sql: orderSql,
        connectionId: server!.id,
      );
      expect(orderResult.requiresConfirmation, isTrue,
          reason: 'ORDER BY + LIMIT 不受早停豁免，R9 按全表估值($_seedRows)命中');
      expect(orderResult.exemption, AgentL05Exemption.none);
      expect(orderResult.impact.fullScan, isTrue);

      // 反二：LIMIT 201 超出 X2 上限（§8：n > 200 不豁免）。无残存信号
      //（min(12000,201)=201 < 10,000）→ allow，但豁免必须为 none（200 边界）。
      const limit201Sql = 'SELECT * FROM gate_big LIMIT 201';
      final limit201Result = await analysis.analyze(
        sql: limit201Sql,
        connectionId: server!.id,
      );
      expect(limit201Result.requiresConfirmation, isFalse);
      expect(limit201Result.exemption, AgentL05Exemption.none,
          reason: 'n=201 > 200 上限 → X2 失效');
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('AI-GATE-E2E-006 X2 豁免 × R10 独立命中 → 仍 confirm（§8 联动）',
        () async {
      if (!ready) {
        // ignore: avoid_print
        print('MYSQL_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      // 注入阈值 100（见 _linkageThreshold 注）：`LIMIT 150` 的 R10 有效行数
      // min(12,000,150)=150 ≥ 100 独立命中；X2 消解 R9 扫描信号（150 ≤ 200
      // 无 ORDER BY）但消不掉 R10 —— §8「豁免只消解扫描形态信号，结果集规模
      // 信号独立成立仍命中」。
      const sql = 'SELECT * FROM gate_big LIMIT 150';
      final result = await _analysis(
        dbService!,
        dbType: DatabaseType.mysql,
        threshold: _linkageThreshold,
      ).analyze(sql: sql, connectionId: server!.id);
      expect(result.requiresConfirmation, isTrue,
          reason: 'X2 豁免已命中仍 confirm：R10 结果集规模信号独立成立');
      expect(result.exemption, AgentL05Exemption.smallLimitEarlyStop);
      expect(result.impact.fullScan, isTrue,
          reason: 'R9 信号如实记录（豁免消解判定，不篡改扫描形态事实）');
      expect(result.impact.analysisUnavailable, isFalse);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('AI-GATE-E2E-007 阈值敏感：10,000 → confirm / 50,000 → allow（AC8.7）',
        () async {
      if (!ready) {
        // ignore: avoid_print
        print('MYSQL_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      const sql = 'SELECT * FROM gate_big';

      // 判定面一（分析内核）：同一语句同一表，仅阈值不同 → 判定翻转。
      final atDefault = await _analysis(
        dbService!,
        dbType: DatabaseType.mysql,
        threshold: _defaultThreshold,
      ).analyze(sql: sql, connectionId: server!.id);
      expect(atDefault.requiresConfirmation, isTrue);

      final atFlipped = await _analysis(
        dbService!,
        dbType: DatabaseType.mysql,
        threshold: _flippedThreshold,
      ).analyze(sql: sql, connectionId: server!.id);
      expect(atFlipped.requiresConfirmation, isFalse,
          reason: '阈值 50,000 > EXPLAIN 估值(≈$_seedRows) → 两信号皆不命中');
      expect(atFlipped.impact.fullScan, isFalse);

      // 判定面二（门工厂闭包 = 生产装配形态）：修改后下次判定生效——工厂
      // 每次判定重新构造（AC8.7），无需重建 gate。
      var rowThreshold = _defaultThreshold;
      final gate = AgentGate(
        createAnalysis: (AgentRunContext ctx) => _analysis(
          dbService!,
          dbType: ctx.dbType,
          threshold: rowThreshold,
        ),
      );
      final before = await gate.evaluate(
        spec: _catalogSpec('execute_readonly_sql'),
        args: <String, dynamic>{'sql': sql},
        runCtx: _runCtx(server!),
        ledger: AgentPermissionLedger(),
      );
      expect(before.kind, GateDecisionKind.confirm);

      rowThreshold = _flippedThreshold; // 模拟用户改设置后的下一次判定
      final after = await gate.evaluate(
        spec: _catalogSpec('execute_readonly_sql'),
        args: <String, dynamic>{'sql': sql},
        runCtx: _runCtx(server!),
        ledger: AgentPermissionLedger(),
      );
      expect(after.kind, GateDecisionKind.allow);
      expect(after.level, AgentGateLevel.l0);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('AI-GATE-E2E-008 explain_plan 工具语义：allow@l0 + 计划真往返 + 数据零变化（AC4.5）',
        () async {
      if (!ready) {
        // ignore: avoid_print
        print('MYSQL_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      // 门：explain_plan 是 l0 数据工具但无 L0.5 分析面（design §4.1 表：
      // 仅 execute_readonly_sql / get_sample_data 升 L0.5）→ allow@l0。
      final gate = AgentGate(
        createAnalysis: (AgentRunContext ctx) =>
            _analysis(dbService!, dbType: ctx.dbType),
      );
      final decision = await gate.evaluate(
        spec: _catalogSpec('explain_plan'),
        args: <String, dynamic>{'sql': 'SELECT * FROM gate_big'},
        runCtx: _runCtx(server!),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.allow);
      expect(decision.level, AgentGateLevel.l0);

      // 计划真往返（真实 DatabaseService → 网关 → 真库 EXPLAIN）。
      final planRows = await dbService!.getExplainPlan('SELECT * FROM gate_big');
      expect(planRows, isNotEmpty, reason: 'EXPLAIN 必须返回真实计划行');
      expect('${planRows.first}', contains('gate_big'));

      // AC4.5：读前读后目标表数据一致（EXPLAIN 族操作零数据副作用）。
      final before = await _probeTable(dbService!, 'gate_big');
      await dbService!.getExplainPlan('SELECT * FROM gate_big');
      await _analysis(
        dbService!,
        dbType: DatabaseType.mysql,
      ).analyze(sql: 'SELECT * FROM gate_big', connectionId: server!.id);
      await dbService!.executeQuery('SELECT * FROM gate_big LIMIT 5');
      final after = await _probeTable(dbService!, 'gate_big');
      expect(after, equals(before),
          reason: '读前分析/EXPLAIN/取样不得改变目标表数据（AC4.5）');
    }, timeout: const Timeout(Duration(seconds: 90)));
  });

  // ==========================================================================
  // PG 抽查（同套核心用例）
  // ==========================================================================
  group('Agent L0.5 门簇 · PG 抽查（真库）', () {
    PostgreSQLAdapter? seedAdapter;
    DatabaseService? dbService;
    DbServer? server;
    String? testDbName;
    bool ready = false;

    setUpAll(() async {
      if (!gatewayReady || !PostgreSQLTestConfig.available) return;
      testDbName = PostgreSQLTestConfig.generateTestDatabaseName();
      final seed = PostgreSQLAdapter();
      try {
        await seed.connect(
          DatabaseConnection(
            id: 'agent_gate_seed_pg',
            name: 'Agent Gate E2E Seed PG',
            type: DatabaseType.postgresql,
            host: PostgreSQLTestConfig.host,
            port: PostgreSQLTestConfig.port,
            username: PostgreSQLTestConfig.username,
            password: PostgreSQLTestConfig.password,
            database: PostgreSQLTestConfig.database,
          ),
        );
        await seed.createDatabase(testDbName!);
        await seed.useDatabase(testDbName!);
        await _seedPgGateTables(seed);
        seedAdapter = seed;

        final svc = DatabaseService();
        final dbServer = DbServer(
          id: 'agent_gate_e2e_pg',
          name: 'Agent Gate E2E PG',
          type: DatabaseType.postgresql,
          host: PostgreSQLTestConfig.host,
          port: PostgreSQLTestConfig.port,
          username: PostgreSQLTestConfig.username,
          password: PostgreSQLTestConfig.password,
          database: testDbName,
        );
        ready = await svc.connect(dbServer);
        if (!ready) await svc.disconnect();
        dbService = svc;
        server = dbServer;
      } catch (e) {
        // ignore: avoid_print
        print('PG_GATE_E2E_SKIP: PostgreSQL 环境不可达：$e');
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
        try {
          await seed.dropDatabase(testDbName!);
        } catch (_) {}
        try {
          await seed.disconnect();
        } catch (_) {}
      }
    });

    test('AI-GATE-E2E-009 PG Seq Scan 大表 → confirm + fullScan', () async {
      if (!ready) {
        // ignore: avoid_print
        print('PG_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      const sql = 'SELECT * FROM gate_big';
      final result = await _analysis(
        dbService!,
        dbType: DatabaseType.postgresql,
      ).analyze(sql: sql, connectionId: server!.id);
      expect(result.requiresConfirmation, isTrue,
          reason: 'Seq Scan 估值($_seedRows 行) ≥ 阈值($_defaultThreshold)');
      expect(result.impact.fullScan, isTrue, reason: 'Seq Scan 扫描形态信号（R9）');
      expect(result.impact.analysisUnavailable, isFalse);
      expect(result.impact.estimatedRows, isNotNull);
      expect(result.impact.estimatedRows!, greaterThanOrEqualTo(_defaultThreshold));
      expect(result.impact.scannedTables, contains('gate_big'));

      // 门判定面：confirm(l05) 携带 impact。
      final gate = AgentGate(
        createAnalysis: (AgentRunContext ctx) =>
            _analysis(dbService!, dbType: ctx.dbType),
      );
      final decision = await gate.evaluate(
        spec: _catalogSpec('execute_readonly_sql'),
        args: <String, dynamic>{'sql': sql},
        runCtx: _runCtx(server!),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.confirm);
      expect(decision.level, AgentGateLevel.l05);
      expect(decision.impact, isNotNull);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('AI-GATE-E2E-010 PG Index Scan 命中 → allow', () async {
      if (!ready) {
        // ignore: avoid_print
        print('PG_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      const sql = 'SELECT * FROM gate_indexed WHERE val BETWEEN 1 AND 50';
      final result = await _analysis(
        dbService!,
        dbType: DatabaseType.postgresql,
      ).analyze(sql: sql, connectionId: server!.id);
      expect(result.requiresConfirmation, isFalse,
          reason: 'idx_val 命中（Index Scan）小范围查询无信号');
      expect(result.impact.fullScan, isFalse);
      expect(result.exemption, AgentL05Exemption.none,
          reason: 'Index Cond 含范围/AND 非单列等值 → 非 X1（保守）');

      final gate = AgentGate(
        createAnalysis: (AgentRunContext ctx) =>
            _analysis(dbService!, dbType: ctx.dbType),
      );
      final decision = await gate.evaluate(
        spec: _catalogSpec('execute_readonly_sql'),
        args: <String, dynamic>{'sql': sql},
        runCtx: _runCtx(server!),
        ledger: AgentPermissionLedger(),
      );
      expect(decision.kind, GateDecisionKind.allow);
      expect(decision.level, AgentGateLevel.l0);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('AI-GATE-E2E-011 PG PK 点查 X1（using <t>_pkey + 单列等值 Index Cond）',
        () async {
      if (!ready) {
        // ignore: avoid_print
        print('PG_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
        return;
      }
      const sql = 'SELECT * FROM gate_big WHERE id = 42';
      final result = await _analysis(
        dbService!,
        dbType: DatabaseType.postgresql,
      ).analyze(sql: sql, connectionId: server!.id);
      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.uniqueKeyPointLookup,
          reason: 'PG X1 分支：Index Scan using gate_big_pkey + Index Cond: '
              '(id = 42) 单列等值、无 Filter 残留');
      expect(result.impact.analysisUnavailable, isFalse);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // ==========================================================================
  // SS fail-closed（EXPLAIN 不可用方言）
  // ==========================================================================
  group('Agent L0.5 门簇 · SS fail-closed（真库）', () {
    SqlServerAdapter? seedAdapter;
    DatabaseService? dbService;
    DbServer? server;
    String? testDbName;
    bool ready = false;

    setUpAll(() async {
      if (!gatewayReady || !SQLServerTestConfig.available) return;
      testDbName = SQLServerTestConfig.generateTestDatabaseName();
      final seed = SqlServerAdapter();
      try {
        await seed.connect(
          DatabaseConnection(
            id: 'agent_gate_seed_ss',
            name: 'Agent Gate E2E Seed SS',
            type: DatabaseType.sqlserver,
            host: SQLServerTestConfig.host,
            port: SQLServerTestConfig.port,
            username: SQLServerTestConfig.username,
            password: SQLServerTestConfig.password,
            database: SQLServerTestConfig.database,
          ),
        );
        final created = await seed.createDatabase(testDbName!);
        if (!created) throw Exception('CREATE DATABASE $testDbName 失败');
        await seed.useDatabase(testDbName!);
        await seed.executeQuery(
          'CREATE TABLE gate_ss (id INT PRIMARY KEY, val INT NOT NULL)',
        );
        await seed.executeQuery(
          'INSERT INTO gate_ss (id, val) VALUES (1, 1), (2, 2), (3, 3)',
        );
        seedAdapter = seed;

        final svc = DatabaseService();
        final dbServer = DbServer(
          id: 'agent_gate_e2e_ss',
          name: 'Agent Gate E2E SS',
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
        print('SS_GATE_E2E_SKIP: SQL Server 环境不可达：$e');
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
        try {
          // SS 网关 dropDatabase 的 ALTER/DROP 经「当前记录库」路由——tearDown
          // 时仍指向测试库的话，DROP 会落在连着目标库的会话上（SS 3702
          // in-use，SINGLE_USER 也被 drop 语句自身的连接占用）→ 先切回
          // master 再删（adapter 路由缺陷的测试侧规避，见 T17 汇报遗留问题）。
          await seed.useDatabase(SQLServerTestConfig.database);
          // adapter.dropDatabase 内部 SINGLE_USER + ROLLBACK IMMEDIATE
          // 处理网关池在用连接后 DROP。
          await seed.dropDatabase(testDbName!);
        } catch (_) {}
        try {
          await seed.disconnect();
        } catch (_) {}
      }
    });

    test(
      'AI-GATE-E2E-012 SS 网关 EXPLAIN 不支持 → analysisUnavailable → confirm(l05)（AC8.6）',
      () async {
        if (!ready) {
          // ignore: avoid_print
          print('SS_GATE_E2E_SKIP: 环境未就绪（网关/凭据/连接）');
          return;
        }
        const sql = 'SELECT * FROM gate_ss';

        // 底层路径实证：真实服务上 EXPLAIN 抛 UnsupportedError（SHOWPLAN
        // 会话级开关 × 网关单语句独立连接不兼容，T28 已知边界——fail-loud
        // 而非空计划）。
        await expectLater(
          dbService!.getExplainPlan(sql),
          throwsUnsupportedError,
        );

        // fail-closed（AC8.6）：取数抛错 → 不进规则，保守 confirm。
        final result = await _analysis(
          dbService!,
          dbType: DatabaseType.sqlserver,
        ).analyze(sql: sql, connectionId: server!.id);
        expect(result.requiresConfirmation, isTrue,
            reason: 'fail-closed：分析不可用 → 保守 confirm，不进规则');
        expect(result.impact.analysisUnavailable, isTrue);
        expect(result.impact.estimatedRows, isNull);
        expect(result.exemption, AgentL05Exemption.none);

        // 门判定面：confirm(l05) 携带 impact（analysisUnavailable 进确认卡）。
        final gate = AgentGate(
          createAnalysis: (AgentRunContext ctx) =>
              _analysis(dbService!, dbType: ctx.dbType),
        );
        final decision = await gate.evaluate(
          spec: _catalogSpec('execute_readonly_sql'),
          args: <String, dynamic>{'sql': sql},
          runCtx: _runCtx(server!),
          ledger: AgentPermissionLedger(),
        );
        expect(decision.kind, GateDecisionKind.confirm);
        expect(decision.level, AgentGateLevel.l05);
        expect(decision.impact, isNotNull);
        expect(decision.impact!.analysisUnavailable, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}
