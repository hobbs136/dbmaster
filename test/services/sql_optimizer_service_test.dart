import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/sql_optimizer_service.dart';

void main() {
  group('SqlOptimizerService', () {
    late SqlOptimizerService optimizer;

    setUp(() {
      optimizer = SqlOptimizerService();
    });

    group('analyze', () {
      test('detects SELECT *', () {
        final suggestions = optimizer.analyze('SELECT * FROM users');
        final selectStar = suggestions.where(
          (s) => s.type == '性能优化' && s.description.contains('SELECT *'),
        );
        expect(selectStar, isNotEmpty);
        expect(selectStar.first.priority, equals(Priority.high));
      });

      test('detects missing WHERE clause', () {
        final suggestions = optimizer.analyze('SELECT id FROM users');
        final missingWhere = suggestions.where(
          (s) => s.description.contains('缺少 WHERE'),
        );
        expect(missingWhere, isNotEmpty);
        expect(missingWhere.first.priority, equals(Priority.high));
      });

      test('does not flag missing WHERE for non-SELECT', () {
        final suggestions = optimizer.analyze(
          'INSERT INTO users (id) VALUES (1)',
        );
        final missingWhere = suggestions.where(
          (s) => s.description.contains('缺少 WHERE'),
        );
        expect(missingWhere, isEmpty);
      });

      test('detects leading wildcard LIKE', () {
        final suggestions = optimizer.analyze(
          "SELECT * FROM users WHERE name LIKE '%john%'",
        );
        final likeIssue = suggestions.where(
          (s) => s.description.contains('LIKE'),
        );
        expect(likeIssue, isNotEmpty);
        expect(likeIssue.first.priority, equals(Priority.high));
      });

      test('does not flag trailing wildcard LIKE', () {
        final suggestions = optimizer.analyze(
          "SELECT * FROM users WHERE name LIKE 'john%'",
        );
        final likeIssue = suggestions.where(
          (s) => s.description.contains('LIKE'),
        );
        expect(likeIssue, isEmpty);
      });

      test('detects multiple OR conditions', () {
        final suggestions = optimizer.analyze(
          "SELECT * FROM users WHERE status = 1 OR status = 2 OR status = 3 OR status = 4",
        );
        final orIssue = suggestions.where((s) => s.description.contains('OR'));
        expect(orIssue, isNotEmpty);
        expect(orIssue.first.priority, equals(Priority.medium));
      });

      test('does not flag single OR', () {
        final suggestions = optimizer.analyze(
          "SELECT * FROM users WHERE a = 1 OR b = 2",
        );
        final orIssue = suggestions.where((s) => s.description.contains('OR'));
        expect(orIssue, isEmpty);
      });

      test('detects DISTINCT', () {
        final suggestions = optimizer.analyze(
          'SELECT DISTINCT name FROM users',
        );
        final distinctIssue = suggestions.where(
          (s) => s.description.contains('DISTINCT'),
        );
        expect(distinctIssue, isNotEmpty);
        expect(distinctIssue.first.priority, equals(Priority.medium));
      });

      test('detects ORDER BY', () {
        final suggestions = optimizer.analyze(
          'SELECT * FROM users ORDER BY name',
        );
        final orderIssue = suggestions.where(
          (s) => s.description.contains('ORDER BY'),
        );
        expect(orderIssue, isNotEmpty);
        expect(orderIssue.first.priority, equals(Priority.medium));
      });

      test('detects subquery', () {
        final suggestions = optimizer.analyze(
          'SELECT * FROM users WHERE id IN (SELECT user_id FROM orders)',
        );
        final subqueryIssue = suggestions.where(
          (s) => s.description.contains('子查询'),
        );
        expect(subqueryIssue, isNotEmpty);
        expect(subqueryIssue.first.priority, equals(Priority.medium));
      });

      test('does not flag single SELECT as subquery', () {
        final suggestions = optimizer.analyze('SELECT * FROM users');
        final subqueryIssue = suggestions.where(
          (s) => s.description.contains('子查询'),
        );
        expect(subqueryIssue, isEmpty);
      });

      test('detects incorrect NULL comparison', () {
        final suggestions = optimizer.analyze(
          'SELECT * FROM users WHERE name = NULL',
        );
        final nullIssue = suggestions.where(
          (s) => s.description.contains('NULL'),
        );
        expect(nullIssue, isNotEmpty);
        expect(nullIssue.first.priority, equals(Priority.high));
      });

      test('detects incorrect != NULL comparison', () {
        final suggestions = optimizer.analyze(
          'SELECT * FROM users WHERE name != NULL',
        );
        final nullIssue = suggestions.where(
          (s) => s.description.contains('NULL'),
        );
        expect(nullIssue, isNotEmpty);
      });

      test('detects function in WHERE clause', () {
        final suggestions = optimizer.analyze(
          "SELECT * FROM users WHERE UPPER(name) = 'JOHN'",
        );
        final funcIssue = suggestions.where(
          (s) => s.description.contains('函数'),
        );
        expect(funcIssue, isNotEmpty);
        expect(funcIssue.first.priority, equals(Priority.high));
      });

      test('detects DATE function in WHERE', () {
        final suggestions = optimizer.analyze(
          "SELECT * FROM users WHERE DATE(created_at) = '2024-01-01'",
        );
        final funcIssue = suggestions.where(
          (s) => s.description.contains('函数'),
        );
        expect(funcIssue, isNotEmpty);
      });

      test('detects NOT IN', () {
        final suggestions = optimizer.analyze(
          'SELECT * FROM users WHERE id NOT IN (1, 2, 3)',
        );
        final notInIssue = suggestions.where(
          (s) => s.description.contains('NOT IN'),
        );
        expect(notInIssue, isNotEmpty);
        expect(notInIssue.first.priority, equals(Priority.medium));
      });

      test('returns empty for well-optimized SQL', () {
        final suggestions = optimizer.analyze(
          "SELECT id, name FROM users WHERE status = 1 AND name LIKE 'john%'",
        );
        expect(suggestions, isEmpty);
      });
    });

    group('generateOptimizationReport', () {
      test('returns success message for empty suggestions', () {
        final report = optimizer.generateOptimizationReport(
          'SELECT id FROM users',
          [],
        );
        expect(report, contains('看起来不错'));
      });

      test('includes SQL in report', () {
        const sql = 'SELECT * FROM users';
        final suggestions = optimizer.analyze(sql);
        final report = optimizer.generateOptimizationReport(sql, suggestions);
        expect(report, contains(sql));
        expect(report, contains('SQL优化分析报告'));
      });

      test('includes suggestion count', () {
        const sql = 'SELECT * FROM users';
        final suggestions = optimizer.analyze(sql);
        final report = optimizer.generateOptimizationReport(sql, suggestions);
        expect(report, contains('${suggestions.length} 条优化建议'));
      });

      test('includes before/after examples when available', () {
        const sql = 'SELECT * FROM users WHERE name = NULL';
        final suggestions = optimizer.analyze(sql);
        final report = optimizer.generateOptimizationReport(sql, suggestions);
        expect(report, contains('优化前'));
        expect(report, contains('优化后'));
      });
    });

    group('SqlOptimizationSuggestion toJson', () {
      test('serializes to JSON correctly', () {
        final suggestion = SqlOptimizationSuggestion(
          type: '性能优化',
          description: 'test',
          suggestion: 'fix it',
          priority: Priority.high,
          beforeExample: 'before',
          afterExample: 'after',
        );
        final json = suggestion.toJson();
        expect(json['type'], equals('性能优化'));
        expect(json['priority'], equals('high'));
        expect(json['beforeExample'], equals('before'));
        expect(json['afterExample'], equals('after'));
      });
    });
  });
}
