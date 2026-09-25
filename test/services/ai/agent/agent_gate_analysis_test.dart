// AgentGateAnalysis 单测（T05）：L0.5 读前分析判定内核。
//
// mock getExplainPlan 覆盖全分支：命中索引免确认 / 全表命中 / 超阈值 /
// 分析不可用 fail-closed / X1 正反（含 §8 三条失效条件）/ X2 正反
// （n=200 vs 201、带 ORDER BY、多表）/ R10 独立不豁免 / 阈值注入与分立。
//
// ⚠️ 双接线点（design 风险 5）：本分析直接实例化 ExplainFullScanRule（R9）
// 与 ExplainEstimatedRowsRule（R10）——编辑器侧 SafetyReviewService 是另一
// 接线点（其规则测试在 test/services/safety/rules/explain_*_rule_test.dart）。
// 规则本体演化时两侧需同步；阈值分立（agent 10,000 / 编辑器 100,000）是
// 有意设计（D6），不是漂移。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/models/dml_risk_models.dart' show SafetyConfig;
import 'package:dbmaster/services/ai/agent/agent_gate_analysis.dart';
import 'package:dbmaster/services/query_settings_service.dart';

/// 可编程的 EXPLAIN 取数 mock：记录调用次数，可切换返回数据/抛异常。
class _ExplainMock {
  int callCount = 0;
  List<Map<String, dynamic>> data = const <Map<String, dynamic>>[];
  Object? throwOnCall;

  Future<List<Map<String, dynamic>>> call(String sql) {
    callCount++;
    final err = throwOnCall;
    if (err != null) throw err;
    return Future.value(data);
  }
}

/// 构造一行 MySQL EXPLAIN 数据（字段名对齐 mysql_gateway_adapter 返回）。
List<Map<String, dynamic>> _mysqlRow({
  required String type,
  int? rows,
  String? key,
  String? possibleKeys,
  String? ref,
  String table = 'big_table',
}) => [
  <String, dynamic>{
    'id': 1,
    'select_type': 'SIMPLE',
    'table': table,
    'type': type,
    'possible_keys': possibleKeys,
    'key': key,
    'key_len': null,
    'ref': ref,
    'rows': rows,
    'Extra': null,
  },
];

/// 构造 PG EXPLAIN 文本行集（每行一个 QUERY PLAN 文本行）。
List<Map<String, dynamic>> _pgPlan(List<String> lines) => lines
    .map((line) => <String, dynamic>{'QUERY PLAN': line})
    .toList(growable: false);

AgentGateAnalysis _analysis(
  _ExplainMock mock, {
  int threshold = 10000,
  DatabaseType dbType = DatabaseType.mysql,
}) => AgentGateAnalysis(
  getExplainPlan: mock.call,
  rowThreshold: threshold,
  dbType: dbType,
);

void main() {
  group('基础判定（默认阈值 10,000）', () {
    test('命中索引小范围 → 不需确认，EXPLAIN 仅一次往返（两规则共享取数）', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(type: 'ref', rows: 500, key: 'idx_status');
      final result = await _analysis(mock).analyze(
        sql: 'SELECT id FROM big_table WHERE status = 1',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isFalse);
      expect(result.impact.analysisUnavailable, isFalse);
      expect(result.impact.fullScan, isFalse);
      expect(result.impact.estimatedRows, 500);
      expect(result.impact.scannedTables, ['big_table']);
      expect(result.impact.indexSummary, contains('idx_status'));
      expect(result.exemption, AgentL05Exemption.none);
      expect(mock.callCount, 1);
    });

    test('全表扫描大表 → 需确认（R9 信号，影响面字段齐）', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final result = await _analysis(mock).analyze(
        sql: 'SELECT * FROM big_table WHERE unindexed = 1',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isTrue);
      expect(result.impact.fullScan, isTrue);
      expect(result.impact.analysisUnavailable, isFalse);
      expect(result.impact.estimatedRows, 800000);
      expect(result.impact.scannedTables, ['big_table']);
      expect(result.impact.indexSummary, contains('no index'));
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('索引命中但结果集超阈值 → R10 独立确认面（fullScan=false 仍需确认）', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(type: 'ref', rows: 50000, key: 'idx_status');
      final result = await _analysis(mock).analyze(
        sql: 'SELECT id FROM big_table WHERE status = 1',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isTrue);
      expect(result.impact.fullScan, isFalse, reason: 'R10 信号不依赖扫描形态');
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('低于阈值的全表扫描 → 不需确认（阈值下界）', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 9999);
      final result = await _analysis(
        mock,
      ).analyze(sql: 'SELECT * FROM big_table', connectionId: 'c1');

      expect(result.requiresConfirmation, isFalse);
      expect(result.impact.fullScan, isFalse);
      expect(result.impact.estimatedRows, 9999);
    });
  });

  group('fail-closed（AC8.6：分析不可用 → 保守需确认，不进规则）', () {
    test('EXPLAIN 抛 UnsupportedError（如 SQL Server 网关）→ 需确认', () async {
      final mock = _ExplainMock()
        ..throwOnCall = UnsupportedError('EXPLAIN unsupported via gateway');
      final result = await _analysis(
        mock,
      ).analyze(sql: 'SELECT * FROM big_table', connectionId: 'c1');

      expect(result.requiresConfirmation, isTrue);
      expect(result.impact.analysisUnavailable, isTrue);
      expect(result.impact.estimatedRows, isNull);
      expect(result.exemption, AgentL05Exemption.none);
      expect(mock.callCount, 1, reason: '预检即失败，规则不再发起取数');
    });

    test('EXPLAIN 超时（TimeoutException）→ 需确认', () async {
      final mock = _ExplainMock()
        ..throwOnCall = TimeoutException('EXPLAIN timed out');
      final result = await _analysis(
        mock,
      ).analyze(sql: 'SELECT * FROM big_table', connectionId: 'c1');

      expect(result.requiresConfirmation, isTrue);
      expect(result.impact.analysisUnavailable, isTrue);
    });

    test('EXPLAIN 返回空计划 → 需确认', () async {
      final mock = _ExplainMock()..data = const <Map<String, dynamic>>[];
      final result = await _analysis(
        mock,
      ).analyze(sql: 'SELECT * FROM big_table', connectionId: 'c1');

      expect(result.requiresConfirmation, isTrue);
      expect(result.impact.analysisUnavailable, isTrue);
    });

    test('原始行非空但解析不出计划步（PG 空行集）→ 需确认', () async {
      final mock = _ExplainMock()..data = _pgPlan(['']);
      final result = await _analysis(
        mock,
        dbType: DatabaseType.postgresql,
      ).analyze(sql: 'SELECT * FROM users', connectionId: 'c1');

      expect(result.requiresConfirmation, isTrue);
      expect(result.impact.analysisUnavailable, isTrue);
    });
  });

  group('阈值注入与分立（AC8.7 / D6）', () {
    test('阈值经构造参数注入：同一计划 10,000 需确认 / 100,000 不需', () async {
      final row = _mysqlRow(type: 'ALL', rows: 50000);
      final mockA = _ExplainMock()..data = row;
      final mockB = _ExplainMock()..data = row;

      final confirm = await _analysis(
        mockA,
        threshold: 10000,
      ).analyze(sql: 'SELECT * FROM big_table', connectionId: 'c1');
      final allow = await _analysis(
        mockB,
        threshold: 100000,
      ).analyze(sql: 'SELECT * FROM big_table', connectionId: 'c1');

      expect(confirm.requiresConfirmation, isTrue);
      expect(allow.requiresConfirmation, isFalse);
    });

    test('agent 阈值与编辑器阈值默认值分立（D6：10,000 vs 100,000）', () {
      expect(QuerySettingsService.defaultAgentL05RowThreshold, 10000);
      expect(SafetyConfig.defaults.fullScanRowThreshold, 100000);
      expect(
        QuerySettingsService.defaultAgentL05RowThreshold,
        isNot(SafetyConfig.defaults.fullScanRowThreshold),
        reason: '分立是有意设计，互不影响',
      );
    });

    test('从 QuerySettingsService 读值注入（T06/T10 装配形态：修改后下次判定生效）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final threshold = await QuerySettingsService().getAgentL05RowThreshold();
      expect(threshold, 10000);

      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 50000);
      final result = await _analysis(
        mock,
        threshold: threshold,
      ).analyze(sql: 'SELECT * FROM big_table', connectionId: 'c1');

      expect(result.requiresConfirmation, isTrue);
    });
  });

  group('X1 主键/唯一键等值点查豁免（§8）', () {
    test('正：主键等值点查（type=const）→ 免确认且豁免命中可观察', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(
          type: 'const',
          rows: 1,
          key: 'PRIMARY',
          ref: 'const',
          table: 'users',
        );
      final result = await _analysis(
        mock,
      ).analyze(sql: 'SELECT * FROM users WHERE id = 42', connectionId: 'c1');

      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.uniqueKeyPointLookup);
      expect(result.impact.fullScan, isFalse);
      expect(result.impact.estimatedRows, 1);
      expect(result.impact.scannedTables, ['users']);
    });

    test('正：system 形态（单行系统表点查）→ 免确认', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(type: 'system', rows: 1, table: 'users');
      final result = await _analysis(
        mock,
      ).analyze(sql: 'SELECT * FROM users WHERE id = 1', connectionId: 'c1');

      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.uniqueKeyPointLookup);
    });

    test('反：非等值（范围，type=range）→ 不豁免', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(
          type: 'range',
          rows: 500,
          key: 'PRIMARY',
          table: 'users',
        );
      final result = await _analysis(
        mock,
      ).analyze(sql: 'SELECT * FROM users WHERE id > 42', connectionId: 'c1');

      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('反：IN 多值（type=range）→ 不豁免', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(
          type: 'range',
          rows: 3,
          key: 'PRIMARY',
          table: 'users',
        );
      final result = await _analysis(mock).analyze(
        sql: 'SELECT * FROM users WHERE id IN (1, 2, 3)',
        connectionId: 'c1',
      );

      expect(result.exemption, AgentL05Exemption.none);
    });

    test('反：复合唯一索引仅命中前缀（type=ref）→ 不豁免', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(
          type: 'ref',
          rows: 50,
          key: 'uk_tenant_user',
          table: 'users',
        );
      final result = await _analysis(mock).analyze(
        sql: 'SELECT * FROM users WHERE tenant_id = 7',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('反：函数包裹列致全表扫描（type=ALL）→ R9 命中且不豁免 → 需确认', () async {
      final mock = _ExplainMock()
        ..data = _mysqlRow(type: 'ALL', rows: 800000, table: 'users');
      final result = await _analysis(mock).analyze(
        sql: "SELECT * FROM users WHERE UPPER(name) = 'ALICE'",
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isTrue);
      expect(result.impact.fullScan, isTrue);
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('反：多表 JOIN（两个访问步）→ 不豁免', () async {
      final mock = _ExplainMock()
        ..data = [
          <String, dynamic>{
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'u',
            'type': 'eq_ref',
            'key': 'PRIMARY',
            'ref': 'const',
            'rows': 1,
          },
          <String, dynamic>{
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'o',
            'type': 'ref',
            'key': 'PRIMARY',
            'rows': 5,
          },
        ];
      final result = await _analysis(mock).analyze(
        sql:
            'SELECT * FROM users u JOIN orders o ON u.id = o.user_id WHERE u.id = 42',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('PG 正：Index Scan using pkey 无 Filter 残留 → 豁免', () async {
      final mock = _ExplainMock()
        ..data = _pgPlan([
          'Index Scan using users_pkey on users  (cost=0.15..8.17 rows=1 width=70)',
          '  Index Cond: (id = 42)',
        ]);
      final result = await _analysis(
        mock,
        dbType: DatabaseType.postgresql,
      ).analyze(sql: 'SELECT * FROM users WHERE id = 42', connectionId: 'c1');

      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.uniqueKeyPointLookup);
      expect(result.impact.estimatedRows, 1);
    });

    test('PG 反：Filter 残留 → 不豁免', () async {
      final mock = _ExplainMock()
        ..data = _pgPlan([
          'Index Scan using users_pkey on users  (cost=0.15..8.17 rows=1 width=70)',
          '  Index Cond: (id = 42)',
          '  Filter: (active = true)',
        ]);
      final result = await _analysis(mock, dbType: DatabaseType.postgresql)
          .analyze(
            sql: 'SELECT * FROM users WHERE id = 42 AND active = true',
            connectionId: 'c1',
          );

      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('PG 反：非 pkey 索引（唯一性不可证）→ 不豁免', () async {
      final mock = _ExplainMock()
        ..data = _pgPlan([
          'Index Scan using idx_users_email on users  (cost=0.29..8.30 rows=1 width=70)',
          "  Index Cond: (email = 'a@b.c'::text)",
        ]);
      final result = await _analysis(mock, dbType: DatabaseType.postgresql)
          .analyze(
            sql: "SELECT * FROM users WHERE email = 'a@b.c'",
            connectionId: 'c1',
          );

      expect(result.exemption, AgentL05Exemption.none);
    });

    test('PG 反：IN 多值（= ANY）→ 不豁免', () async {
      final mock = _ExplainMock()
        ..data = _pgPlan([
          'Index Scan using users_pkey on users  (cost=0.29..8.31 rows=2 width=70)',
          '  Index Cond: (id = ANY (ARRAY[1, 2]))',
        ]);
      final result = await _analysis(mock, dbType: DatabaseType.postgresql)
          .analyze(
            sql: 'SELECT * FROM users WHERE id IN (1, 2)',
            connectionId: 'c1',
          );

      expect(result.exemption, AgentL05Exemption.none);
    });

    test('PG 反：范围（>=）→ 不豁免', () async {
      final mock = _ExplainMock()
        ..data = _pgPlan([
          'Index Scan using users_pkey on users  (cost=0.15..243.11 rows=120 width=70)',
          '  Index Cond: (id >= 42)',
        ]);
      final result = await _analysis(
        mock,
        dbType: DatabaseType.postgresql,
      ).analyze(sql: 'SELECT * FROM users WHERE id >= 42', connectionId: 'c1');

      expect(result.exemption, AgentL05Exemption.none);
    });
  });

  group('X2 小 LIMIT 无 ORDER BY 早停豁免（§8；注入阈值使 R9 可命中）', () {
    // 单行聚合 + WHERE：R10 跳过（isSingleRowAggregate）、R9 仍查（带 WHERE）——
    // 这是「R9 命中而 R10 不命中」的可构造形态，使 X2 消解效果可观察。
    test('正：LIMIT 200 无 ORDER BY → R9 命中被早停豁免 → 免确认', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final result = await _analysis(mock, threshold: 200).analyze(
        sql: 'SELECT COUNT(*) FROM big_table WHERE unindexed = 1 LIMIT 200',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isFalse);
      expect(result.exemption, AgentL05Exemption.smallLimitEarlyStop);
      expect(result.impact.fullScan, isTrue, reason: '扫描形态事实如实记录，豁免只消解判定');
    });

    test('反：LIMIT 201（n > 200）→ 不豁免 → 需确认', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final result = await _analysis(mock, threshold: 200).analyze(
        sql: 'SELECT COUNT(*) FROM big_table WHERE unindexed = 1 LIMIT 201',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isTrue);
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('反：含 ORDER BY（filesort 需全扫）→ 不豁免 → 需确认', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final result = await _analysis(mock, threshold: 200).analyze(
        sql:
            'SELECT COUNT(*) FROM big_table WHERE unindexed = 1 ORDER BY 1 LIMIT 200',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isTrue);
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('反：多表 JOIN → 不豁免 → 需确认', () async {
      final mock = _ExplainMock()
        ..data = [
          <String, dynamic>{
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 'b',
            'type': 'ALL',
            'rows': 800000,
          },
          <String, dynamic>{
            'id': 1,
            'select_type': 'SIMPLE',
            'table': 't2',
            'type': 'eq_ref',
            'key': 'PRIMARY',
            'ref': 'test.b.id',
            'rows': 1,
          },
        ];
      // 无 WHERE 的单行聚合会被 R9 整体跳过（explain_full_scan_rule 的
      // aggregate 分支），补 WHERE 让 R9 真正进入检查。
      final result = await _analysis(mock, threshold: 100).analyze(
        sql:
            'SELECT COUNT(*) FROM big_table b JOIN t2 ON b.id = t2.id WHERE b.tenant = 7 LIMIT 100',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isTrue);
      expect(result.exemption, AgentL05Exemption.none);
    });

    test('R10 信号独立于豁免仍触发（§8 联动：X2 命中但大结果集信号残存）', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 800000);
      final result = await _analysis(
        mock,
        threshold: 100,
      ).analyze(sql: 'SELECT * FROM big_table LIMIT 200', connectionId: 'c1');

      expect(
        result.requiresConfirmation,
        isTrue,
        reason: 'R10 结果集规模信号不被 X2 消解',
      );
      expect(
        result.exemption,
        AgentL05Exemption.smallLimitEarlyStop,
        reason: '扫描形态信号确实被 X2 消解（豁免命中如实记录）',
      );
      expect(result.impact.fullScan, isTrue);
    });
  });

  group('语句范围与非 SELECT 跳过', () {
    test('SHOW 语句：不发起 EXPLAIN、不判需确认（与规则范围一致）', () async {
      final mock = _ExplainMock();
      final result = await _analysis(
        mock,
      ).analyze(sql: 'SHOW TABLES', connectionId: 'c1');

      expect(result.requiresConfirmation, isFalse);
      expect(
        result.impact.analysisUnavailable,
        isFalse,
        reason: '跳过分析 ≠ 分析不可用（后者才 fail-closed）',
      );
      expect(result.impact.estimatedRows, isNull);
      expect(mock.callCount, 0);
    });

    test('WITH（CTE）前缀语句进入分析', () async {
      final mock = _ExplainMock()..data = _mysqlRow(type: 'ALL', rows: 50);
      final result = await _analysis(mock).analyze(
        sql: 'WITH c AS (SELECT 1 AS x) SELECT * FROM c',
        connectionId: 'c1',
      );

      expect(result.requiresConfirmation, isFalse);
      expect(mock.callCount, 1);
    });
  });
}
