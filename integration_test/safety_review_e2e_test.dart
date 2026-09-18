// SQL 安全审查 E2E 测试（三阶段累计 6 条规则）。
//
// 路径 A：直接 new SafetyReviewService + 真实 MySQL 连接的 SafetyContext，
// 绕过 widget 层。真实触发 6 条规则（含真实 EXPLAIN）。
//
// 连真实 MySQL 8.0（参数经 DBMASTER_MYSQL_* 提供）。连不上则跳过（CI 友好）。
// 运行：flutter test integration_test/safety_review_e2e_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/safety_review_service.dart';
import 'package:dbmaster/services/safety/rules/schema_compat_rule.dart';
import 'package:dbmaster/services/safety/rules/missing_limit_rule.dart';
import 'package:dbmaster/services/safety/rules/full_table_scan_rule.dart';
import 'package:dbmaster/services/safety/rules/sql_injection_rule.dart';
import 'package:dbmaster/services/safety/rules/explain_full_scan_rule.dart';
import 'package:dbmaster/services/safety/rules/explain_estimated_rows_rule.dart';
import 'package:dbmaster/services/safety/rules/executable_comment_rule.dart';
import 'package:dbmaster/services/safety/rules/tautology_predicate_rule.dart';
import 'package:dbmaster/services/safety/rules/complementary_or_rule.dart';
import 'package:dbmaster/services/safety/rules/writable_cte_rule.dart';
import 'package:dbmaster/services/safety/rules/file_write_rule.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// 测试用大表行数（> MissingLimit 阈值 10万 的话要改阈值，这里用 5 万
/// 触发 ExplainFullScan/ExplainEstimatedRows 的相对小阈值验证 + 静态规则）。
/// 实际 MissingLimitRule 默认阈值 10 万——这里建 12 万行表触发它。
const _bigTableRows = 120000;

late MySQLAdapter adapter;
late String testDbName;
late SafetyReviewService service;
late SafetyContext ctx;
bool _connected = false;

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  group('SafetyReview E2E（真实 MySQL）', () {
    setUp(() async {
      adapter = MySQLAdapter();
      testDbName = MySQLTestConfig.generateTestDatabaseName();

      final connection = DatabaseConnection(
        id: 'safety_e2e_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Safety E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: '',
      );

      try {
        final ok = await adapter.connect(connection);
        if (!ok || !adapter.isConnected) return;
        _connected = true;
        await adapter.createDatabase(testDbName);
        await adapter.useDatabase(testDbName);
      } catch (_) {
        _connected = false;
      }

      // 装配 6 条规则（与 query_editor_widget 注册一致）。
      service = SafetyReviewService([
        SchemaCompatRule(),
        MissingLimitRule(),
        FullTableScanRule(),
        SqlInjectionRule(),
        ExplainFullScanRule(rowThreshold: 10000),
        ExplainEstimatedRowsRule(rowThreshold: 100000),
      ]);

      // 构造真实 SafetyContext（getExplainPlan 真连 MySQL）。
      ctx = SafetyContext(
        connectionId: 'safety_e2e',
        dbType: DatabaseType.mysql,
        database: testDbName,
        schemaCache: null,
        getRowCount: (tableName) async {
          try {
            return adapter.getTableRowCount(tableName);
          } catch (_) {
            return null;
          }
        },
        getColumns: (tableName) async => null,
        getExplainPlan: (sql) {
          try {
            return adapter.getExplainPlan(sql).then((r) => r.rows);
          } catch (_) {
            return null;
          }
        },
        explainTimeoutSeconds: 5,
      );
    });

    tearDown(() async {
      if (_connected) {
        try {
          await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
        } catch (_) {}
        try {
          await adapter.disconnect();
        } catch (_) {}
      }
    });

    /// 辅助：建大表（递归 CTE 批量插入，极快）。
    Future<void> seedBigTable({
      String table = 'big_table',
      int rows = _bigTableRows,
    }) async {
      await adapter.executeQuery(
        'CREATE TABLE `$table` ('
        'id INT PRIMARY KEY, '
        'name VARCHAR(64), '
        'status INT, '
        'created_at DATETIME'
        ')',
      );
      await adapter.executeQuery(
        // T29：网关每语句独立连接，SET SESSION 不跨语句保持——改用语句级
        // optimizer hint SET_VAR（MySQL 8 支持 cte_max_recursion_depth）。
        'INSERT /*+ SET_VAR(cte_max_recursion_depth = ${rows + 1000}) */ '
        'INTO `$table` (id, name, status, created_at) '
        'WITH RECURSIVE seq AS ('
        '  SELECT 1 AS n'
        '  UNION ALL SELECT n + 1 FROM seq WHERE n < $rows'
        ") SELECT n, CONCAT('row_', n), n % 5, '2024-01-01 00:00:00' FROM seq",
      );
    }

    /// 辅助：建小表（验证小表不触发全表扫告警）。
    Future<void> seedSmallTable({String table = 'small_table'}) async {
      await adapter.executeQuery(
        'CREATE TABLE `$table` (id INT PRIMARY KEY, name VARCHAR(64))',
      );
      for (var i = 1; i <= 50; i++) {
        await adapter.executeQuery(
          "INSERT INTO `$table` VALUES ($i, 'item_$i')",
        );
      }
    }

    // ────────────────────────────────────────────────────────
    // R3 MissingLimitRule
    // ────────────────────────────────────────────────────────
    test('R3: 大表 SELECT 无 LIMIT → medium finding + LIMIT 建议', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();

      final findings = await service.review(
        'SELECT * FROM big_table',
        ctx,
      );
      final limitFindings = findings.where((f) => f.ruleId == 'missing_limit');
      expect(limitFindings, isNotEmpty,
          reason: '大表无 LIMIT 应触发 MissingLimitRule');
      final f = limitFindings.first;
      expect(f.severity, Severity.medium);
      expect(f.suggestion, contains('LIMIT'));
    });

    test('R3: 大表 SELECT 有 LIMIT → 不触发 MissingLimit', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();

      final findings = await service.review(
        'SELECT * FROM big_table LIMIT 100',
        ctx,
      );
      final limitFindings = findings.where((f) => f.ruleId == 'missing_limit');
      expect(limitFindings, isEmpty, reason: '有 LIMIT 不应触发');
    });

    // ────────────────────────────────────────────────────────
    // R6 FullTableScanRule（静态：函数包裹列 + LIKE 通配）
    // ────────────────────────────────────────────────────────
    test('R6: WHERE YEAR(col) → 静态全表扫 finding', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();

      final findings = await service.review(
        "SELECT * FROM big_table WHERE YEAR(created_at) = 2024 LIMIT 10",
        ctx,
      );
      // 加了 LIMIT 避免 MissingLimit 干扰，聚焦函数包裹列。
      final ftsFindings =
          findings.where((f) => f.ruleId == 'full_table_scan');
      expect(ftsFindings, isNotEmpty,
          reason: 'YEAR(created_at) 破坏索引应触发静态全表扫');
    });

    test('R6: LIKE 前缀通配 → 静态全表扫 finding', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();

      final findings = await service.review(
        "SELECT * FROM big_table WHERE name LIKE '%abc%' LIMIT 10",
        ctx,
      );
      final ftsFindings =
          findings.where((f) => f.ruleId == 'full_table_scan');
      expect(ftsFindings, isNotEmpty, reason: "LIKE '%abc%' 应触发");
    });

    // ────────────────────────────────────────────────────────
    // R7 SqlInjectionRule
    // ────────────────────────────────────────────────────────
    test('R7: OR 1=1 永真式 → high injection finding', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;

      final findings = await service.review(
        'SELECT * FROM small_table WHERE id = 1 OR 1=1',
        ctx,
      );
      final injFindings =
          findings.where((f) => f.ruleId == 'sql_injection');
      expect(injFindings, isNotEmpty, reason: 'OR 1=1 应触发注入检测');
      expect(injFindings.first.severity, Severity.high);
    });

    test('R7: 正常不等式 OR b = 2 → 不触发注入', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;

      final findings = await service.review(
        'SELECT * FROM small_table WHERE a = 1 OR b = 2',
        ctx,
      );
      final injFindings =
          findings.where((f) => f.ruleId == 'sql_injection');
      expect(injFindings, isEmpty, reason: '不等式不是注入');
    });

    // ────────────────────────────────────────────────────────
    // R9 ExplainFullScanRule（EXPLAIN 实证）
    // ────────────────────────────────────────────────────────
    test('R9: 无索引列查询大表 → EXPLAIN 全表扫 finding', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();
      // status 列无索引 → EXPLAIN type=ALL
      final findings = await service.review(
        'SELECT * FROM big_table WHERE status = 1 LIMIT 10',
        ctx,
      );
      final explainFindings =
          findings.where((f) => f.ruleId == 'explain_full_scan');
      expect(explainFindings, isNotEmpty,
          reason: '无索引列 + 大表应触发 EXPLAIN 全表扫');
      final f = explainFindings.first;
      expect(f.severity, Severity.medium);
      expect(f.title, contains('全表扫描'));
    });

    test('R9: 主键查询（走索引）→ 不触发 EXPLAIN 全表扫', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();
      // id 是主键 → EXPLAIN type=const/ref
      final findings = await service.review(
        'SELECT * FROM big_table WHERE id = 1',
        ctx,
      );
      final explainFindings =
          findings.where((f) => f.ruleId == 'explain_full_scan');
      expect(explainFindings, isEmpty, reason: '主键查询走索引不应触发');
    });

    test('R9: 小表全表扫 → 不触发（< 阈值，优化器正常决策）', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedSmallTable();
      final findings = await service.review(
        'SELECT * FROM small_table WHERE name = "x"',
        ctx,
      );
      final explainFindings =
          findings.where((f) => f.ruleId == 'explain_full_scan');
      expect(explainFindings, isEmpty, reason: '小表全表扫不报');
    });

    // ────────────────────────────────────────────────────────
    // R10 ExplainEstimatedRowsRule
    // ────────────────────────────────────────────────────────
    test('R10: 大表无 WHERE SELECT → 大行数预警 finding', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();
      final findings = await service.review(
        'SELECT * FROM big_table',
        ctx,
      );
      final rowsFindings =
          findings.where((f) => f.ruleId == 'explain_estimated_rows');
      expect(rowsFindings, isNotEmpty,
          reason: '12 万行表全量 SELECT 应触发大行数预警');
      expect(rowsFindings.first.suggestion, contains('LIMIT'));
    });

    // ────────────────────────────────────────────────────────
    // 反例：正常 SQL 静默通过
    // ────────────────────────────────────────────────────────
    test('正常小表查询 → 零 finding（静默通过）', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedSmallTable();
      final findings = await service.review(
        'SELECT * FROM small_table WHERE id = 1',
        ctx,
      );
      expect(findings, isEmpty, reason: '正常小表查询不应有任何 finding');
    });

    test('正常大表主键点查 + LIMIT → 零 high/medium finding', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();
      final findings = await service.review(
        'SELECT * FROM big_table WHERE id = 1 LIMIT 1',
        ctx,
      );
      // 主键查询 + LIMIT → 不应有 medium/high
      final actionable = findings.where((f) =>
          f.severity == Severity.medium || f.severity == Severity.high);
      expect(actionable, isEmpty,
          reason: '主键点查 + LIMIT 不应触发任何 medium/high finding');
    });

    // ────────────────────────────────────────────────────────
    // 引擎聚合：多规则同触发的 ExecutionGateDialog 判定
    // ────────────────────────────────────────────────────────
    test('聚合判定：有 medium → shouldShowDialog = true', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedBigTable();
      final findings = await service.review(
        'SELECT * FROM big_table WHERE status = 1',
        ctx,
      );
      // 应同时有 missing_limit（无 LIMIT 大表）+ explain_full_scan（无索引）
      // + 可能 explain_estimated_rows
      expect(findings.length, greaterThanOrEqualTo(1));
      expect(SafetyReviewService.shouldShowDialog(findings), isTrue);
    });

    // ────────────────────────────────────────────────────────
    // B6 规则包（T10-T14）：真实 MySQL 上下文端到端
    // ────────────────────────────────────────────────────────
    test('B6：dbx 同款攻击面 SQL 逐条命中（真库上下文）', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedSmallTable();
      // 注册面与 query_editor_widget._buildSafetyService 一致（T14）。
      final b6 = SafetyReviewService([
        ExecutableCommentRule(),
        TautologyPredicateRule(),
        ComplementaryOrRule(),
        WritableCteRule(),
        FileWriteRule(),
      ]);

      final cases = <String, String>{
        '/*!40000 DELETE FROM logs */ SELECT 1': 'executable_comment',
        'SELECT * FROM small_table WHERE 1=1': 'tautology_predicate',
        'SELECT * FROM small_table WHERE id IS NULL OR id IS NOT NULL':
            'complementary_or',
        'WITH t AS (DELETE FROM logs RETURNING id) SELECT * FROM t':
            'writable_cte',
        "SELECT * FROM small_table INTO OUTFILE '/tmp/x'": 'file_write',
      };
      for (final entry in cases.entries) {
        final findings = await b6.review(entry.key, ctx);
        expect(
          findings.map((f) => f.ruleId),
          contains(entry.value),
          reason: '${entry.key} 应命中 ${entry.value}',
        );
      }
    });

    test('B6：正常业务 SQL 全链零误报（含既有规则合跑）', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      await seedSmallTable();
      final full = SafetyReviewService([
        ...[
          SchemaCompatRule(),
          MissingLimitRule(),
          FullTableScanRule(),
          SqlInjectionRule(),
        ],
        ExecutableCommentRule(),
        TautologyPredicateRule(),
        ComplementaryOrRule(),
        WritableCteRule(),
        FileWriteRule(),
      ]);
      final findings = await full.review(
        'SELECT id, name FROM small_table WHERE id = 1 LIMIT 10',
        ctx,
      );
      expect(
        findings.where((f) =>
            f.severity == Severity.medium || f.severity == Severity.high),
        isEmpty,
        reason: '正常点查 + LIMIT 不应触发任何 medium/high（B6 零误报）',
      );
    });

    test('B6：fail-closed 开关关断后写类降级不注入（T14 接线）', () async {
      if (!mysqlE2EGatewayReady) {
        return;
      }
      if (!_connected) return;
      final svc = SafetyReviewService(
        [_ThrowingRule()],
        failClosedForWrites: false,
      );
      expect(
        await svc.review('DELETE FROM small_table WHERE id = 1', ctx),
        isEmpty,
      );
    });
  });
}

/// 总是抛异常的规则（fail-closed 降级路径用）。
class _ThrowingRule implements SafetyRule {
  @override
  String get id => 'throwing';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    throw StateError('boom');
  }
}
