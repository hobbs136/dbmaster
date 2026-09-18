// SafetyReviewService 单测（ADR-0003 Part A T4）。
//
// 验证：规则聚合 + 严重度排序 + 异常规则静默跳过 + shouldShowDialog 阈值。

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;
import 'package:dbmaster/services/safety/safety_finding.dart';
import 'package:dbmaster/services/safety/safety_rule.dart';
import 'package:dbmaster/services/safety/safety_review_service.dart';

/// 测试用 mock 规则——返回固定 findings。
class _MockRule implements SafetyRule {
  @override
  final String id;
  final List<SafetyFinding> _findings;

  _MockRule(this.id, this._findings);

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    return _findings;
  }
}

/// 测试用 mock 规则——总是抛异常。
class _ThrowingRule implements SafetyRule {
  @override
  final String id = 'throwing';

  @override
  Future<List<SafetyFinding>> check(String sql, SafetyContext context) async {
    throw Exception('boom');
  }
}

void main() {
  test('聚合多条规则的 findings', () async {
    final service = SafetyReviewService([
      _MockRule('rule_a', [
        const SafetyFinding(
          ruleId: 'rule_a',
          severity: Severity.low,
          title: 'A-low',
          description: 'desc',
        ),
      ]),
      _MockRule('rule_b', [
        const SafetyFinding(
          ruleId: 'rule_b',
          severity: Severity.high,
          title: 'B-high',
          description: 'desc',
        ),
      ]),
    ]);

    final findings = await service.review('SELECT 1', _dummyContext());

    expect(findings.length, 2);
    expect(findings.any((f) => f.ruleId == 'rule_a'), isTrue);
    expect(findings.any((f) => f.ruleId == 'rule_b'), isTrue);
  });

  test('findings 按严重度降序排序（high → medium → low）', () async {
    final service = SafetyReviewService([
      _MockRule('r', [
        const SafetyFinding(
            ruleId: 'r', severity: Severity.low, title: 'low', description: ''),
        const SafetyFinding(
            ruleId: 'r', severity: Severity.high, title: 'high', description: ''),
        const SafetyFinding(
            ruleId: 'r', severity: Severity.medium, title: 'med', description: ''),
      ]),
    ]);

    final findings = await service.review('SELECT 1', _dummyContext());

    expect(findings.length, 3);
    expect(findings[0].severity, Severity.high);
    expect(findings[1].severity, Severity.medium);
    expect(findings[2].severity, Severity.low);
  });

  test('抛异常的规则被静默跳过，不阻断其他规则', () async {
    final service = SafetyReviewService([
      _MockRule('good', [
        const SafetyFinding(
            ruleId: 'good', severity: Severity.high, title: 'ok', description: ''),
      ]),
      _ThrowingRule(),
    ]);

    final findings = await service.review('SELECT 1', _dummyContext());

    // 好规则的 finding 保留，坏规则的不出现。
    expect(findings.length, 1);
    expect(findings.first.ruleId, 'good');
  });

  test('全部规则返回空 → findings 为空', () async {
    final service = SafetyReviewService([
      _MockRule('empty', []),
      _MockRule('empty2', []),
    ]);

    final findings = await service.review('SELECT 1', _dummyContext());

    expect(findings, isEmpty);
  });

  test('reviewScript 标注 statementIndex（从 1 开始）', () async {
    final service = SafetyReviewService([
      _MockRule('r', [
        const SafetyFinding(
            ruleId: 'r', severity: Severity.high, title: 't', description: 'd'),
      ]),
    ]);

    final findings = await service.reviewScript(
      ['SELECT 1', 'SELECT 2', 'SELECT 3'],
      _dummyContext(),
    );

    expect(findings.length, 3);
    expect(findings[0].statementIndex, 1);
    expect(findings[1].statementIndex, 2);
    expect(findings[2].statementIndex, 3);
  });

  test('reviewScript 传 statementLineStarts → finding.lineStart 对应（B3 行级红点）',
      () async {
    final service = SafetyReviewService([
      _MockRule('r', [
        const SafetyFinding(
            ruleId: 'r', severity: Severity.high, title: 't', description: 'd'),
      ]),
    ]);

    final findings = await service.reviewScript(
      ['SELECT 1', 'SELECT 2', 'SELECT 3'],
      _dummyContext(),
      statementLineStarts: [5, 10, 15], // 模拟 SQLStatement.lineStart
    );

    expect(findings[0].lineStart, 5);
    expect(findings[1].lineStart, 10);
    expect(findings[2].lineStart, 15);
  });

  test('reviewScript 不传 statementLineStarts → finding.lineStart = 0（向后兼容）',
      () async {
    final service = SafetyReviewService([
      _MockRule('r', [
        const SafetyFinding(
            ruleId: 'r', severity: Severity.high, title: 't', description: 'd'),
      ]),
    ]);

    final findings = await service.reviewScript(
      ['SELECT 1'],
      _dummyContext(),
    );

    expect(findings[0].lineStart, 0);
  });

  test('shouldShowDialog: 只有 low → false（静默通过）', () {
    final findings = [
      const SafetyFinding(
          ruleId: 'r', severity: Severity.low, title: 't', description: 'd'),
    ];
    expect(SafetyReviewService.shouldShowDialog(findings), isFalse);
  });

  test('shouldShowDialog: 有 medium → true', () {
    final findings = [
      const SafetyFinding(
          ruleId: 'r', severity: Severity.low, title: 't', description: 'd'),
      const SafetyFinding(
          ruleId: 'r', severity: Severity.medium, title: 't', description: 'd'),
    ];
    expect(SafetyReviewService.shouldShowDialog(findings), isTrue);
  });

  test('shouldShowDialog: 有 high → true', () {
    final findings = [
      const SafetyFinding(
          ruleId: 'r', severity: Severity.high, title: 't', description: 'd'),
    ];
    expect(SafetyReviewService.shouldShowDialog(findings), isTrue);
  });

  test('shouldShowDialog: 空 → false', () {
    expect(SafetyReviewService.shouldShowDialog([]), isFalse);
  });
}

/// 构造一个 dummy context（测试不依赖真实 schema 元数据）。
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
