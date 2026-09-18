import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/schema_analyzer/ddl_algorithm.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';
import 'package:dbmaster/services/schema_analyzer/schema_analyzer.dart';

/// SchemaAnalyzer.analyzeDdl 锁语义集成测试（design §4.3 / tasks T8）。
///
/// 用 mock executeQuery + mock getServerVersion 验证锁字段端到端流转：
/// analyzeDdl → DdlAlgorithmInferrer.infer → ImpactReport 锁字段。
/// 不连真实库（锁推断逻辑已在 ddl_algorithm_inferrer_test 纯单测覆盖）。
void main() {
  group('SchemaAnalyzer.analyzeDdl 锁语义集成', () {
    /// 构造 mock executeQuery：对 COUNT(*) 返回指定行数，其它查询返回空。
    Future<List<Map<String, dynamic>>> mockExecuteQuery(
      String sql, {
      int rowCount = 0,
    }) async {
      if (sql.toUpperCase().contains('COUNT(*)')) {
        return [{'count': rowCount}];
      }
      // 依赖查询（INFORMATION_SCHEMA）返回空 → 无依赖。
      return [];
    }

    test('MySQL 8.0.32 + ADD COLUMN（末尾）→ instant + low', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
        getServerVersion: () async => '8.0.32',
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.instant);
      expect(report.concurrencyImpact, ConcurrencyImpact.none);
      expect(report.lockType, isNotNull);
      expect(report.algorithmNote, contains('INSTANT'));
      expect(report.riskLevel, RiskLevel.low);
    });

    test('MySQL 5.7 + MODIFY COLUMN → copy + 大表 high', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t MODIFY COLUMN c BIGINT',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 50000),
        getServerVersion: () async => '5.7.43',
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.copy);
      expect(report.concurrencyImpact, ConcurrencyImpact.blocksDml);
      // copy + 50000 行（>10K）→ high
      expect(report.riskLevel, RiskLevel.high);
    });

    test('MySQL 8.0.32 + DROP COLUMN → instant', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t DROP COLUMN c',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 1000),
        getServerVersion: () async => '8.0.32',
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.instant);
    });

    test('MySQL + TRUNCATE TABLE → metadataOnly + high（R18 修复）', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'TRUNCATE TABLE t',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 0),
        getServerVersion: () async => '8.0.32',
      );
      expect(report.ddlType, 'TRUNCATE_TABLE');
      expect(report.ddlAlgorithm, DdlAlgorithm.metadataOnly);
      expect(report.riskLevel, RiskLevel.high); // 破坏性优先
    });

    test('不传 getServerVersion → 锁字段 unknown（向后兼容）', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 1000),
        // 不传 getServerVersion
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.unknown);
      expect(report.concurrencyImpact, ConcurrencyImpact.unknown);
      // 既有行为：ADD_COLUMN < 100000 → low
      expect(report.riskLevel, RiskLevel.low);
    });

    test('getServerVersion 抛异常 → 降级 unknown，不阻断', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
        getServerVersion: () async => throw Exception('连接断开'),
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.unknown);
      // 异常被吞，分析仍完成
      expect(report.targetTable, isNotNull);
    });

    test('PostgreSQL ADD_COLUMN → copy（B4：PG 锁语义已实现，ACCESS EXCLUSIVE）', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: 'postgresql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
        getServerVersion: () async => '15.3',
      );
      // B4：PG ALTER TABLE 拿 ACCESS EXCLUSIVE → copy（阻塞读写）。
      expect(report.ddlAlgorithm, DdlAlgorithm.copy);
      expect(report.concurrencyImpact, ConcurrencyImpact.blocksDml);
    });

    test('未实现的库（doris）→ 锁字段 unknown（不套用任何库语义）', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: 'doris',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.unknown);
    });

    test('显式 ALGORITHM=COPY → 用户指定优先', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT, ALGORITHM=COPY',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 50000),
        getServerVersion: () async => '8.0.32', // 即使支持 INSTANT
      );
      expect(report.ddlAlgorithm, DdlAlgorithm.copy);
      expect(report.concurrencyImpact, ConcurrencyImpact.blocksDml);
      expect(report.algorithmNote, contains('用户'));
    });

    test('toJson 含锁字段', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
        getServerVersion: () async => '8.0.32',
      );
      final json = report.toJson();
      expect(json['ddlAlgorithm'], 'instant');
      expect(json['concurrencyImpact'], 'none');
      expect(json['lockType'], isNotNull);
      expect(json['algorithmNote'], isNotNull);
    });

    test('formatReportForAI 含锁语义段落（algorithm 已知时）', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
        getServerVersion: () async => '8.0.32',
      );
      final text = SchemaAnalyzer.formatReportForAI(report);
      expect(text, contains('Lock Semantics'));
      expect(text, contains('INSTANT'));
    });

    test('formatReportForAI 不含锁语义段落（algorithm unknown 时避免噪音）', () async {
      final report = await SchemaAnalyzer.analyzeDdl(
        ddlStatement: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: 'mysql',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
        // 不传 getServerVersion → unknown
      );
      final text = SchemaAnalyzer.formatReportForAI(report);
      expect(text, isNot(contains('Lock Semantics')));
    });
  });
}
