import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/execution_summary.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';

SQLStatement _stmt(String sql, {int index = 0}) => SQLStatement(
  index: index,
  sql: sql,
  type: sql.trim().toUpperCase().startsWith('SELECT')
      ? SQLType.select
      : SQLType.update,
  lineStart: 0,
  lineEnd: 0,
);

void main() {
  group('ExecutionSummary', () {
    final start = DateTime(2026, 6, 1, 12, 0);
    final end = DateTime(2026, 6, 1, 12, 0, 5); // 5 seconds later

    test('fromResults computes correct totals', () {
      final results = [
        ExecutionResult(
          statement: _stmt('SELECT * FROM users'),
          success: true,
          executionTime: const Duration(milliseconds: 100),
          affectedRows: 10,
        ),
        ExecutionResult(
          statement: _stmt('SELECT * FROM orders'),
          success: true,
          executionTime: const Duration(milliseconds: 200),
        ),
        ExecutionResult(
          statement: _stmt('DROP TABLE bad'),
          success: false,
          executionTime: Duration.zero,
          errorMessage: 'No permission',
        ),
      ];
      final summary = ExecutionSummary.fromResults(results, start, end);
      expect(summary.totalCount, 3);
      expect(summary.successCount, 2);
      expect(summary.errorCount, 1);
      expect(summary.allSuccess, false);
    });

    test('fromResults all success', () {
      final results = [
        ExecutionResult(
          statement: _stmt('SELECT 1'),
          success: true,
          executionTime: const Duration(milliseconds: 10),
        ),
        ExecutionResult(
          statement: _stmt('SELECT 2'),
          success: true,
          executionTime: const Duration(milliseconds: 5),
        ),
      ];
      final summary = ExecutionSummary.fromResults(results, start, end);
      expect(summary.allSuccess, true);
      expect(summary.errorCount, 0);
    });

    test('totalAffectedRows ignores null values', () {
      final results = [
        ExecutionResult(
          statement: _stmt('UPDATE t SET x=1'),
          success: true,
          executionTime: const Duration(milliseconds: 50),
          affectedRows: 5,
        ),
        ExecutionResult(
          statement: _stmt('SELECT 1'),
          success: true,
          executionTime: const Duration(milliseconds: 10),
        ),
      ];
      final summary = ExecutionSummary.fromResults(results, start, end);
      expect(summary.totalAffectedRows, 5);
    });

    test('totalTime is computed from start and end', () {
      final results = <ExecutionResult>[];
      final s = DateTime(2026, 6, 1, 12, 0, 0);
      final e = DateTime(2026, 6, 1, 12, 0, 3);
      final summary = ExecutionSummary.fromResults(results, s, e);
      expect(summary.totalTime, const Duration(seconds: 3));
    });

    test('allSuccess is true when no errors', () {
      final results = [
        ExecutionResult(
          statement: _stmt('SELECT 1'),
          success: true,
          executionTime: Duration.zero,
        ),
      ];
      final summary = ExecutionSummary.fromResults(results, start, end);
      expect(summary.allSuccess, true);
    });

    test('toString contains success/error counts', () {
      final results = [
        ExecutionResult(
          statement: _stmt('SELECT 1'),
          success: true,
          executionTime: Duration.zero,
        ),
        ExecutionResult(
          statement: _stmt('BAD SQL'),
          success: false,
          executionTime: Duration.zero,
          errorMessage: 'Syntax error',
        ),
      ];
      final summary = ExecutionSummary.fromResults(results, start, end);
      expect(summary.toString(), contains('1/2'));
      expect(summary.toString(), contains('1 errors'));
    });

    test('equality check', () {
      final a = ExecutionSummary(
        totalCount: 5,
        successCount: 4,
        errorCount: 1,
        totalTime: const Duration(seconds: 1),
        totalAffectedRows: 0,
        startTime: DateTime(2026, 6, 1, 12, 0),
        endTime: DateTime(2026, 6, 1, 12, 0, 1),
      );
      final b = ExecutionSummary(
        totalCount: 5,
        successCount: 4,
        errorCount: 1,
        totalTime: const Duration(seconds: 1),
        totalAffectedRows: 0,
        startTime: DateTime(2026, 6, 1, 12, 0),
        endTime: DateTime(2026, 6, 1, 12, 0, 1),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
