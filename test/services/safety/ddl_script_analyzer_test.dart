// ============================================================================
// DdlScriptAnalyzer 单测（P3 长尾收口，2026-08-25）
// 覆盖：多 DDL 逐条命中 / 预算截断 / 非 DDL 过滤 / statementIndex+lineStart
// 盖章 / INSTANT 低险不产 finding / 单语句 statementIndex=0。
// 注：单条失败的降级路径在 SchemaAnalyzer/DependencyAnalyzer 内部已逐层
// catch（COUNT/依赖/版本查询全部静默降级），helper 的 catch 是兜底防御，
// 无稳定注入点，不单独构造用例。
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/services/safety/ddl_script_analyzer.dart';
import 'package:dbmaster/services/safety/safety_finding.dart';

/// 假执行器：COUNT 恒返 0（小表），记录所有查询语句供断言。
class _FakeExecutor {
  final List<String> queries = [];

  Future<List<Map<String, dynamic>>> call(String sql) async {
    queries.add(sql);
    if (sql.startsWith('SELECT COUNT(*)')) {
      return [
        {'count': 0},
      ];
    }
    return const [];
  }
}

SQLStatement _stmt(int index, String sql, {int lineStart = 1}) {
  return SQLStatement(
    index: index,
    sql: sql,
    type: SQLType.ddl,
    lineStart: lineStart,
    lineEnd: lineStart,
  );
}

void main() {
  group('DdlScriptAnalyzer.analyzeScript', () {
    test('多 DDL 逐条命中：每条高风险 DDL 产独立 finding 并带语句序号/行号',
        () async {
      final executor = _FakeExecutor();
      final statements = [
        _stmt(0, 'DROP TABLE t0', lineStart: 1),
        _stmt(1, 'SELECT * FROM t1', lineStart: 5),
        _stmt(2, 'DROP TABLE t2', lineStart: 9),
      ];

      final findings = await DdlScriptAnalyzer.analyzeScript(
        statements: statements,
        databaseType: 'mysql',
        executeQuery: executor.call,
        getServerVersion: () async => '8.0.36',
      );

      expect(findings, hasLength(2));
      expect(findings[0].ruleId, 'ddl_impact');
      expect(findings[0].severity, Severity.high);
      expect(findings[0].affectedTable, 't0');
      expect(findings[0].statementIndex, 1); // 第 1 条语句（1-based）
      expect(findings[0].lineStart, 1);
      expect(findings[1].affectedTable, 't2');
      expect(findings[1].statementIndex, 3); // 第 3 条语句
      expect(findings[1].lineStart, 9);
      // 非 DDL 语句不消耗分析（COUNT 只查 t0/t2）。
      final countTargets = executor.queries
          .where((q) => q.startsWith('SELECT COUNT(*)'))
          .toList();
      expect(countTargets, hasLength(2));
      expect(countTargets.any((q) => q.contains('t1')), isFalse);
    });

    test('预算截断：12 条 DDL 预算 10，只分析前 10 条', () async {
      final executor = _FakeExecutor();
      final statements = [
        for (var i = 0; i < 12; i++)
          _stmt(i, 'DROP TABLE t$i', lineStart: i * 2 + 1),
      ];

      final findings = await DdlScriptAnalyzer.analyzeScript(
        statements: statements,
        databaseType: 'mysql',
        executeQuery: executor.call,
        getServerVersion: () async => '8.0.36',
        ddlAnalysisBudget: 10,
      );

      expect(findings, hasLength(10));
      expect(findings.map((f) => f.statementIndex),
          [for (var i = 1; i <= 10; i++) i]);
      // 超预算的 t10/t11 未发 COUNT 查询。
      final countTargets = executor.queries
          .where((q) => q.startsWith('SELECT COUNT(*)'))
          .toList();
      expect(countTargets, hasLength(10));
      expect(countTargets.any((q) => q.contains('t10')), isFalse);
      expect(countTargets.any((q) => q.contains('t11')), isFalse);
    });

    test('INSTANT 低险 DDL 不产 finding（CREATE TABLE 小表）', () async {
      final executor = _FakeExecutor();
      final findings = await DdlScriptAnalyzer.analyzeScript(
        statements: [_stmt(0, 'CREATE TABLE t_new (id int)')],
        databaseType: 'mysql',
        executeQuery: executor.call,
        getServerVersion: () async => '8.0.36',
      );
      expect(findings, isEmpty);
    });

    test('单语句脚本 statementIndex=0（单语句语义）', () async {
      final executor = _FakeExecutor();
      final findings = await DdlScriptAnalyzer.analyzeScript(
        statements: [_stmt(0, 'DROP TABLE t0', lineStart: 3)],
        databaseType: 'mysql',
        executeQuery: executor.call,
        getServerVersion: () async => '8.0.36',
      );
      expect(findings, hasLength(1));
      expect(findings[0].statementIndex, 0);
      expect(findings[0].lineStart, 3);
    });

    test('无 DDL 语句：零分析零 finding', () async {
      final executor = _FakeExecutor();
      final findings = await DdlScriptAnalyzer.analyzeScript(
        statements: [
          _stmt(0, 'SELECT * FROM t0'),
          _stmt(1, 'UPDATE t1 SET a = 1'),
        ],
        databaseType: 'mysql',
        executeQuery: executor.call,
      );
      expect(findings, isEmpty);
      expect(executor.queries, isEmpty);
    });

    test('getServerVersion 缺省：锁字段 unknown 仍正常评级（向后兼容）',
        () async {
      final executor = _FakeExecutor();
      final findings = await DdlScriptAnalyzer.analyzeScript(
        statements: [_stmt(0, 'TRUNCATE TABLE t0')],
        databaseType: 'mysql',
        executeQuery: executor.call,
      );
      expect(findings, hasLength(1));
      expect(findings[0].severity, Severity.high);
    });
  });
}
