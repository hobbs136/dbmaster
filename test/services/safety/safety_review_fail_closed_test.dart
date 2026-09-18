// T13 · fail-closed 改造单测（D2 决策：仅写类，2026-08-20 拍板）。
//
// 验证：规则执行异常（审查降级）时——
// - 写类 SQL（INSERT/UPDATE/DELETE/DDL/CALL）→ 注入
//   `review_degraded_fail_closed`（high）finding；
// - 读类 SQL（SELECT/其它）→ 维持静默跳过，不注入；
// - 无异常时正常规则结果不受影响；
// - reviewScript 多语句混合：只有写语句那条带 finding 且
//   statementIndex/lineStart 正确透传；
// - 编辑器执行门使用的判定函数（isWriteStatement /
//   containsWriteStatement）与 finding 工厂的字段契约。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/safety_review_service.dart';

/// 测试用 mock 规则——总是抛异常（模拟审查降级）。
class _ThrowingRule implements SafetyRule {
  @override
  final String id = 'throwing';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    throw Exception('boom');
  }
}

/// 测试用 mock 规则——返回固定 findings（模拟正常规则）。
class _StubRule implements SafetyRule {
  @override
  final String id = 'stub';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    return const [
      SafetyFinding(
        ruleId: 'stub',
        severity: Severity.low,
        title: 't',
        description: 'd',
      ),
    ];
  }
}

void main() {
  group('review() 规则异常 → fail-closed（D2：仅写类）', () {
    test('UPDATE（写类）→ 注入 review_degraded_fail_closed 且为 high', () async {
      final service = SafetyReviewService([_ThrowingRule()]);
      final findings = await service.review(
        'UPDATE users SET name = \'x\' WHERE id = 1',
        _dummyContext(),
      );

      final degraded = findings.where(
        (f) => f.ruleId == 'review_degraded_fail_closed',
      );
      expect(degraded, isNotEmpty);
      expect(degraded.single.severity, Severity.high);
      // high 语义 → 触发执行门弹窗。
      expect(SafetyReviewService.shouldShowDialog(findings), isTrue);
    });

    test('INSERT / DELETE / DDL / CALL（写类）→ 均注入 fail-closed finding',
        () async {
      final service = SafetyReviewService([_ThrowingRule()]);
      const writeSqls = [
        'INSERT INTO users (id) VALUES (1)',
        'DELETE FROM users WHERE id = 1',
        'ALTER TABLE users ADD COLUMN age INT',
        'DROP TABLE users',
        'TRUNCATE TABLE users',
        'CALL do_cleanup()',
      ];
      for (final sql in writeSqls) {
        final findings = await service.review(sql, _dummyContext());
        expect(
          findings.any((f) => f.ruleId == 'review_degraded_fail_closed'),
          isTrue,
          reason: '写类 SQL 应注入 fail-closed finding: $sql',
        );
      }
    });

    test('SELECT（读类）→ 不注入 fail-closed finding（静默跳过）', () async {
      final service = SafetyReviewService([_ThrowingRule()]);
      final findings = await service.review(
        'SELECT * FROM users WHERE id = 1',
        _dummyContext(),
      );

      expect(
        findings.any((f) => f.ruleId == 'review_degraded_fail_closed'),
        isFalse,
      );
      expect(findings, isEmpty);
    });

    test('无异常时正常规则结果不受影响（不注入）', () async {
      final service = SafetyReviewService([_StubRule()]);
      final findings = await service.review(
        'UPDATE users SET name = \'x\' WHERE id = 1',
        _dummyContext(),
      );

      expect(findings.length, 1);
      expect(findings.first.ruleId, 'stub');
      expect(
        findings.any((f) => f.ruleId == 'review_degraded_fail_closed'),
        isFalse,
      );
    });

    test('混合规则：好规则 finding 保留 + 写类降级注入并存', () async {
      final service = SafetyReviewService([_StubRule(), _ThrowingRule()]);
      final findings = await service.review(
        'DELETE FROM orders WHERE created_at < \'2020-01-01\'',
        _dummyContext(),
      );

      expect(findings.length, 2);
      // 严重度降序：high（fail-closed）在前，low（stub）在后。
      expect(findings.first.ruleId, 'review_degraded_fail_closed');
      expect(findings.first.severity, Severity.high);
      expect(findings.last.ruleId, 'stub');
    });
  });

  group('reviewScript() 多语句混合 → 仅写语句带 finding', () {
    test('读+写混合：只有写语句那条带 finding，statementIndex/lineStart 透传',
        () async {
      final service = SafetyReviewService([_ThrowingRule()]);
      final findings = await service.reviewScript(
        [
          'SELECT * FROM users',
          'UPDATE users SET name = \'x\' WHERE id = 1',
          'SELECT COUNT(*) FROM orders',
        ],
        _dummyContext(),
        statementLineStarts: [1, 5, 9],
      );

      final degraded = findings
          .where((f) => f.ruleId == 'review_degraded_fail_closed')
          .toList();
      // 只有第 2 条（写语句）注入，且标注来自第 2 条语句 + 起始行 5。
      expect(degraded.length, 1);
      expect(degraded.single.statementIndex, 2);
      expect(degraded.single.lineStart, 5);
      expect(degraded.single.severity, Severity.high);
    });

    test('全读脚本 → 无 fail-closed finding', () async {
      final service = SafetyReviewService([_ThrowingRule()]);
      final findings = await service.reviewScript(
        ['SELECT 1', 'SELECT 2'],
        _dummyContext(),
      );

      expect(
        findings.any((f) => f.ruleId == 'review_degraded_fail_closed'),
        isFalse,
      );
      expect(findings, isEmpty);
    });
  });

  group('isWriteStatement（T13 写类判定，编辑器门复用）', () {
    test('写类：INSERT/UPDATE/DELETE/DDL（CREATE/ALTER/DROP/TRUNCATE）/CALL',
        () {
      const writeSqls = [
        'INSERT INTO t VALUES (1)',
        'UPDATE t SET a = 1',
        'DELETE FROM t',
        'CREATE TABLE t (id INT)',
        'ALTER TABLE t ADD c INT',
        'DROP TABLE t',
        'TRUNCATE TABLE t',
        'CALL p()',
        'EXEC p',
        // 前置注释不掩蔽首关键词（cleanForAnalysis 语义）。
        '-- note\nUPDATE t SET a = 1',
      ];
      for (final sql in writeSqls) {
        expect(SafetyReviewService.isWriteStatement(sql), isTrue,
            reason: '应为写类: $sql');
      }
    });

    test('读类：SELECT / WITH / SHOW / 其它', () {
      const readSqls = [
        'SELECT * FROM t',
        'WITH c AS (SELECT 1) SELECT * FROM c',
        'SHOW TABLES',
        'EXPLAIN SELECT 1',
        '',
        '   ',
      ];
      for (final sql in readSqls) {
        expect(SafetyReviewService.isWriteStatement(sql), isFalse,
            reason: '应为读类: $sql');
      }
    });
  });

  group('containsWriteStatement（编辑器门整体异常用，多语句 best-effort）', () {
    test('首句读 + 后句写 → true（不能被首关键词骗过）', () {
      expect(
        SafetyReviewService.containsWriteStatement(
          'SELECT * FROM a;\nUPDATE b SET x = 1;\nSELECT 2',
        ),
        isTrue,
      );
    });

    test('全读多语句 → false', () {
      expect(
        SafetyReviewService.containsWriteStatement('SELECT 1; SELECT 2'),
        isFalse,
      );
    });

    test('单条写语句 → true；单条读语句 → false', () {
      expect(
        SafetyReviewService.containsWriteStatement('DELETE FROM t'),
        isTrue,
      );
      expect(
        SafetyReviewService.containsWriteStatement('SELECT 1'),
        isFalse,
      );
    });
  });

  group('degradedFailClosedFinding（finding 字段契约）', () {
    test('ruleId/severity 固定，title/description 为中文告警语义', () {
      final f = SafetyReviewService.degradedFailClosedFinding();
      expect(f.ruleId, 'review_degraded_fail_closed');
      expect(f.severity, Severity.high);
      expect(f.title, contains('安全审查降级'));
      expect(f.description, contains('无法确认该写操作的安全性'));
      expect(f.description, contains('来源'));
      // 无建议/无表名：执行门不展示「采用建议」按钮。
      expect(f.suggestion, isNull);
      expect(f.affectedTable, isNull);
      // 单语句语义：statementIndex=0（reviewScript 聚合时再标注）。
      expect(f.statementIndex, 0);
    });
  });

  group('failClosedForWrites 开关（T14 · B1 reviewFailClosedEnabled 接线）', () {
    test('false 时写类降级也只记日志，不注入 finding（回退纯 fail-open）', () async {
      final service = SafetyReviewService(
        [_ThrowingRule()],
        failClosedForWrites: false,
      );
      final findings = await service.review(
        'DELETE FROM orders WHERE id = 1',
        _dummyContext(),
      );
      expect(findings, isEmpty);
    });

    test('默认 true：不传参的既有构造行为不变（写类注入）', () async {
      final service = SafetyReviewService([_ThrowingRule()]);
      final findings = await service.review(
        'DELETE FROM orders WHERE id = 1',
        _dummyContext(),
      );
      expect(findings, hasLength(1));
      expect(findings.first.ruleId, 'review_degraded_fail_closed');
    });
  });
}

/// 构造一个 dummy mysql context（测试不依赖真实 schema 元数据）。
SafetyContext _dummyContext() {
  return SafetyContext(
    connectionId: 'test',
    dbType: DatabaseType.mysql,
    database: 'test',
    schemaCache: null,
    getRowCount: (_) async => null,
    getColumns: (_) async => null,
  );
}
