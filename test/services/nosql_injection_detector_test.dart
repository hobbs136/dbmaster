import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/nosql_injection_detector.dart';

void main() {
  late NoSqlInjectionDetector detector;

  setUp(() => detector = NoSqlInjectionDetector());

  group('NoSqlInjectionDetector.analyze', () {
    test('\$where → critical 服务端 JS 执行威胁', () {
      final threats = detector.analyze(
        "db.users.find({\$where: \"this.password == '123'\"})",
      );
      final where = threats.where((t) => t.type == '服务端 JS 执行').toList();
      expect(where, hasLength(1));
      expect(where.first.severity, NoSqlThreatSeverity.critical);
    });

    test('认证字段操作符注入 → critical 认证绕过', () {
      final threats = detector.analyze(
        r"db.users.find({username: {$ne: null}, password: {$ne: null}})",
      );
      final bypass = threats.where((t) => t.type == '认证绕过（操作符注入）').toList();
      expect(bypass, isNotEmpty);
      expect(bypass.first.severity, NoSqlThreatSeverity.critical);
    });

    test('\$function → 聚合表达式注入威胁', () {
      final threats = detector.analyze(
        r"db.coll.aggregate([{$function: {body: function(){return 1}, args:[], lang:'js'}}])",
      );
      expect(
        threats.map((t) => t.type),
        contains('聚合表达式注入'),
      );
    });

    test('安全查询 → 无威胁', () {
      final threats = detector.analyze(
        'db.users.find({email: "alice@example.com", age: {\$gte: 18}}, {name: 1})',
      );
      // 等值查询 + 范围查询（非认证字段）应不触发认证绕过
      expect(
        threats.where((t) => t.type == '认证绕过（操作符注入）'),
        isEmpty,
      );
      expect(
        threats.where((t) => t.type == '服务端 JS 执行'),
        isEmpty,
      );
    });
  });

  group('NoSqlInjectionDetector.generateThreatReport', () {
    test('空威胁 → 安全消息', () {
      final report = detector.generateThreatReport(
        'db.users.find({name: "bob"})',
        const [],
      );
      expect(report, contains('查询看起来安全'));
    });

    test('有威胁 → 报告含风险描述', () {
      final threats = detector.analyze(r'db.users.find({$where: "1"})');
      final report = detector.generateThreatReport(
        r'db.users.find({$where: "1"})',
        threats,
      );
      expect(report, contains('NoSQL 注入安全分析报告'));
      expect(report, contains('风险描述'));
    });
  });
}
