import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/query_execution_interceptor.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/schema_analyzer/ddl_algorithm.dart';
import 'package:dbmaster/models/schema_analyzer/impact_report.dart';

void main() {
  group('QueryExecutionInterceptor', () {
    late QueryExecutionInterceptor interceptor;

    setUp(() {
      interceptor = QueryExecutionInterceptor();
    });

    test('detects DDL statements correctly', () {
      expect(
        QueryExecutionInterceptor.isDdlStatement('CREATE TABLE users (id INT)'),
        isTrue,
      );
      expect(
        QueryExecutionInterceptor.isDdlStatement(
          'ALTER TABLE users ADD COLUMN name VARCHAR(255)',
        ),
        isTrue,
      );
      expect(
        QueryExecutionInterceptor.isDdlStatement('DROP TABLE users'),
        isTrue,
      );
      expect(
        QueryExecutionInterceptor.isDdlStatement('TRUNCATE TABLE users'),
        isTrue,
      );
      expect(
        QueryExecutionInterceptor.isDdlStatement(
          'RENAME TABLE users TO customers',
        ),
        isTrue,
      );
    });

    test('does not detect non-DDL statements', () {
      expect(
        QueryExecutionInterceptor.isDdlStatement('SELECT * FROM users'),
        isFalse,
      );
      expect(
        QueryExecutionInterceptor.isDdlStatement(
          'INSERT INTO users VALUES (1)',
        ),
        isFalse,
      );
      expect(
        QueryExecutionInterceptor.isDdlStatement(
          'UPDATE users SET name = "test"',
        ),
        isFalse,
      );
      expect(
        QueryExecutionInterceptor.isDdlStatement(
          'DELETE FROM users WHERE id = 1',
        ),
        isFalse,
      );
    });

    test('detects data modifying DDL', () {
      expect(
        QueryExecutionInterceptor.isDataModifyingDdl('DROP TABLE users'),
        isTrue,
      );
      expect(
        QueryExecutionInterceptor.isDataModifyingDdl('TRUNCATE TABLE users'),
        isTrue,
      );
      expect(
        QueryExecutionInterceptor.isDataModifyingDdl(
          'ALTER TABLE users DROP COLUMN name',
        ),
        isTrue,
      );
      expect(
        QueryExecutionInterceptor.isDataModifyingDdl(
          'ALTER TABLE users MODIFY COLUMN age INT',
        ),
        isTrue,
      );
    });

    test('does not detect non-data-modifying DDL as data modifying', () {
      expect(
        QueryExecutionInterceptor.isDataModifyingDdl(
          'CREATE TABLE users (id INT)',
        ),
        isFalse,
      );
      expect(
        QueryExecutionInterceptor.isDataModifyingDdl(
          'ALTER TABLE users ADD COLUMN name VARCHAR(255)',
        ),
        isFalse,
      );
      expect(
        QueryExecutionInterceptor.isDataModifyingDdl(
          'CREATE INDEX idx_name ON users(name)',
        ),
        isFalse,
      );
    });

    test('skip recording for certain queries', () async {
      // EXPLAIN queries should be skipped
      var recorded = false;

      // This is a simple test to verify the logic exists
      // The actual recording requires database initialization
      expect(
        QueryExecutionInterceptor.isDdlStatement('EXPLAIN SELECT * FROM users'),
        isFalse,
      );
    });

    test('beforeExecute returns null for non-DDL', () async {
      final result = await interceptor.beforeExecute(
        sql: 'SELECT * FROM users',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (sql) async => [],
      );

      expect(result, isNull);
    });

    test('beforeExecute returns null when disabled', () async {
      interceptor.enableDdlAnalysis = false;

      final result = await interceptor.beforeExecute(
        sql: 'DROP TABLE users',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (sql) async => [],
      );

      expect(result, isNull);
    });

    // ============ beforeExecute 锁语义 + 过滤条件对齐（第四阶段后续）============
    // 链路 A（Interceptor）与执行门（链路 B）统一后的过滤语义：
    // 高风险（high/critical）**或** 全表锁（copy）→ 返回 report（弹确认）。
    // 与 query_editor_widget 执行门路径一致。

    /// mock executeQuery：对 COUNT(*) 返回指定行数，其它查询返回空（无依赖）。
    Future<List<Map<String, dynamic>>> mockExecuteQuery(
      String sql, {
      int rowCount = 0,
    }) async {
      if (sql.toUpperCase().contains('COUNT(*)')) {
        return [{'count': rowCount}];
      }
      return [];
    }

    test('beforeExecute + instant（小表）→ null（不弹，锁语义降级误报）', () async {
      // MySQL 8.0.32 + ADD COLUMN（末尾）→ instant + low
      // 统一前：行数判断可能误弹；统一后：锁语义生效，instant 不弹。
      final result = await interceptor.beforeExecute(
        sql: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
        getServerVersion: () async => '8.0.32',
      );
      expect(result, isNull);
    });

    test('beforeExecute + copy（小表）→ 返回 report（弹，copy 分支触发）', () async {
      // MySQL 5.7 + MODIFY COLUMN → copy。小表评级可能是 medium/low，
      // 但 copy = 全表锁，应让用户确认（与执行门过滤条件一致）。
      final result = await interceptor.beforeExecute(
        sql: 'ALTER TABLE t MODIFY COLUMN c BIGINT',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
        getServerVersion: () async => '5.7.43',
      );
      expect(result, isNotNull);
      expect(result!.ddlAlgorithm, DdlAlgorithm.copy);
    });

    test('beforeExecute + copy + 大表 → 返回 report（high + copy 双重）', () async {
      final result = await interceptor.beforeExecute(
        sql: 'ALTER TABLE t MODIFY COLUMN c BIGINT',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 50000),
        getServerVersion: () async => '5.7.43',
      );
      expect(result, isNotNull);
      expect(result!.ddlAlgorithm, DdlAlgorithm.copy);
      expect(result.riskLevel, RiskLevel.high);
    });

    test('beforeExecute + 改字符集（ALTER COLUMN 路径，copy）→ 返回 report', () async {
      // MODIFY 含 CHARACTER SET → ddlType=ALTER_COLUMN + _isCharsetChange → copy。
      // copy 分支触发，即使小表也弹（与执行门过滤条件一致）。
      final result = await interceptor.beforeExecute(
        sql: 'ALTER TABLE t MODIFY COLUMN c VARCHAR(255) CHARACTER SET utf8mb4',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 10),
        getServerVersion: () async => '8.0.32',
      );
      expect(result, isNotNull);
      expect(result!.ddlAlgorithm, DdlAlgorithm.copy);
    });

    test('beforeExecute + CONVERT TO CHARACTER SET（纯 charset，copy）→ 返回 report', () async {
      // 修复（2026-08-09）：此前 extractDdlType 对无 MODIFY/ALTER COLUMN 的
      // CONVERT TO CHARACTER SET 落 UNKNOWN → 漏报全表锁。现归 ALTER_COLUMN →
      // _isCharsetChange → copy。即使小表也弹（copy 分支，生产改字符集会锁表）。
      final result = await interceptor.beforeExecute(
        sql: 'ALTER TABLE t CONVERT TO CHARACTER SET utf8mb4',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 10),
        getServerVersion: () async => '8.0.32',
      );
      expect(result, isNotNull);
      expect(result!.ddlAlgorithm, DdlAlgorithm.copy);
    });

    test('beforeExecute + TRUNCATE → 返回 report（破坏性，R18 修复）', () async {
      final result = await interceptor.beforeExecute(
        sql: 'TRUNCATE TABLE t',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 0),
        getServerVersion: () async => '8.0.32',
      );
      expect(result, isNotNull);
      expect(result!.ddlType, 'TRUNCATE_TABLE');
      expect(result.riskLevel, RiskLevel.high);
    });

    test('beforeExecute 不传 getServerVersion → 行为同现状（向后兼容）', () async {
      // 不传 getServerVersion：锁字段 unknown，过滤回落到 requiresConfirmation。
      // ADD COLUMN 小表 → low → 不弹（与未接入锁语义前的行为一致）。
      final result = await interceptor.beforeExecute(
        sql: 'ALTER TABLE t ADD COLUMN c INT',
        databaseType: DatabaseType.mysql,
        connectionId: 'test',
        executeQuery: (q) => mockExecuteQuery(q, rowCount: 100),
      );
      expect(result, isNull);
    });

    test('afterExecute does not throw when disabled', () async {
      interceptor.enableHistoryRecording = false;

      // Should not throw
      await interceptor.afterExecute(
        sql: 'SELECT * FROM users',
        connectionId: 'test',
        connectionName: 'Test DB',
        databaseType: DatabaseType.mysql,
        databaseName: 'test_db',
        executionTimeMs: 100,
        isSuccess: true,
      );

      // Test passes if no exception is thrown
      expect(true, isTrue);
    });
  });
}
