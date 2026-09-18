import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sql_injection_detector.dart';

void main() {
  group('SqlInjectionDetector', () {
    late SqlInjectionDetector detector;

    setUp(() {
      detector = SqlInjectionDetector();
    });

    group('基本检测', () {
      test('应检测UNION注入', () {
        final threats = detector.analyze("' UNION SELECT * FROM users --");
        expect(threats, isNotEmpty);
      });

      test('应检测注释攻击', () {
        final threats = detector.analyze("admin'--");
        expect(threats, isNotEmpty);
      });

      test('应允许正常的SQL', () {
        final threats = detector.analyze("SELECT * FROM users");
        expect(threats, isEmpty);
      });

      test('应允许安全的用户输入', () {
        final threats = detector.analyze("John Doe");
        expect(threats, isEmpty);
      });
    });

    group('安全检查', () {
      test('应标记安全SQL', () {
        expect(detector.isSafe("SELECT * FROM users"), isTrue);
      });

      test('应标记危险SQL', () {
        expect(detector.isSafe("' OR '1'='1"), isFalse);
      });
    });

    group('清理输入', () {
      test('应转义单引号', () {
        final cleaned = detector.sanitize("John's Book");
        expect(cleaned, contains("''"));
      });

      test('应转义反斜杠', () {
        final cleaned = detector.sanitize("path\\to\\file");
        expect(cleaned, contains("\\\\"));
      });

      test('应保留原始内容', () {
        final cleaned = detector.sanitize("John's Book");
        expect(cleaned, contains('John'));
        expect(cleaned, contains('Book'));
      });
    });

    group('威胁分析', () {
      test('应分析复杂注入', () {
        final threats = detector.analyze(
          "1 UNION ALL SELECT password FROM admin",
        );
        expect(threats, isNotEmpty);
        expect(threats.any((t) => t.type.contains('UNION')), isTrue);
      });

      test('应生成威胁报告', () {
        final sql = "' OR '1'='1";
        final threats = detector.analyze(sql);
        final report = detector.generateThreatReport(sql, threats);
        expect(report, isNotEmpty);
      });
    });
  });
}
