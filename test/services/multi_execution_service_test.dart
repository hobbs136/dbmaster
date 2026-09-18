import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/multi_execution_service.dart';
import 'package:dbmaster/models/sql_statement.dart';

/// Mock database executor for testing
class MockDatabaseExecutor {
  final Map<String, List<Map<String, dynamic>>> _responses = {};
  final Set<String> _shouldFail = {};
  Duration? artificialDelay;

  void mockQuery(String sql, List<Map<String, dynamic>> response) {
    _responses[sql] = response;
  }

  void mockFailure(String sql) {
    _shouldFail.add(sql);
  }

  Future<List<Map<String, dynamic>>> executeQuery(String sql) async {
    if (artificialDelay != null) {
      await Future.delayed(artificialDelay!);
    }

    if (_shouldFail.contains(sql)) {
      throw Exception('Query failed: $sql');
    }

    return _responses[sql] ?? [];
  }
}

void main() {
  group('MultiExecutionService', () {
    late MultiExecutionService service;
    late MockDatabaseExecutor mockExecutor;

    setUp(() {
      mockExecutor = MockDatabaseExecutor();
      service = MultiExecutionService.withExecutor(mockExecutor.executeQuery);
    });

    tearDown(() {
      service.dispose();
    });

    test('should execute multiple statements sequentially', () async {
      mockExecutor.mockQuery('SELECT 1', [
        {'1': 1},
      ]);
      mockExecutor.mockQuery('SELECT 2', [
        {'2': 2},
      ]);

      final statements = [
        SQLStatement(
          index: 1,
          sql: 'SELECT 1',
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
        SQLStatement(
          index: 2,
          sql: 'SELECT 2',
          type: SQLType.select,
          lineStart: 2,
          lineEnd: 2,
        ),
      ];

      final results = await service.execute(statements);

      expect(results.length, 2);
      expect(results[0].statement.index, 1);
      expect(results[0].success, true);
      expect(results[1].statement.index, 2);
      expect(results[1].success, true);
    });

    test('should emit progress updates', () async {
      mockExecutor.mockQuery('SELECT 1', [
        {'1': 1},
      ]);
      mockExecutor.mockQuery('SELECT 2', [
        {'2': 2},
      ]);

      final statements = [
        SQLStatement(
          index: 1,
          sql: 'SELECT 1',
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
        SQLStatement(
          index: 2,
          sql: 'SELECT 2',
          type: SQLType.select,
          lineStart: 2,
          lineEnd: 2,
        ),
      ];

      final progressUpdates = <ExecutionProgress>[];
      service.progressStream.listen((progress) {
        progressUpdates.add(progress);
      });

      await service.execute(statements);

      expect(progressUpdates.length, greaterThanOrEqualTo(2));
      expect(progressUpdates.any((p) => p.currentIndex == 0), true);
      expect(progressUpdates.any((p) => p.currentIndex == 1), true);
      expect(progressUpdates.any((p) => p.currentIndex == 2), true);
    });

    test('should continue on error', () async {
      mockExecutor.mockQuery('SELECT 1', [
        {'1': 1},
      ]);
      mockExecutor.mockFailure('INVALID SQL');
      mockExecutor.mockQuery('SELECT 3', [
        {'3': 3},
      ]);

      final statements = [
        SQLStatement(
          index: 1,
          sql: 'SELECT 1',
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
        SQLStatement(
          index: 2,
          sql: 'INVALID SQL',
          type: SQLType.select,
          lineStart: 2,
          lineEnd: 2,
        ),
        SQLStatement(
          index: 3,
          sql: 'SELECT 3',
          type: SQLType.select,
          lineStart: 3,
          lineEnd: 3,
        ),
      ];

      final results = await service.execute(statements);

      expect(results.length, 3);
      expect(results[0].success, true);
      expect(results[1].success, false);
      expect(results[1].errorMessage, isNotNull);
      expect(results[2].success, true);
    });

    test('should support cancellation', () async {
      mockExecutor.artificialDelay = Duration(milliseconds: 100);
      mockExecutor.mockQuery('SELECT 1', [
        {'1': 1},
      ]);
      mockExecutor.mockQuery('SELECT 2', [
        {'2': 2},
      ]);
      mockExecutor.mockQuery('SELECT 3', [
        {'3': 3},
      ]);

      final statements = [
        SQLStatement(
          index: 1,
          sql: 'SELECT 1',
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
        SQLStatement(
          index: 2,
          sql: 'SELECT 2',
          type: SQLType.select,
          lineStart: 2,
          lineEnd: 2,
        ),
        SQLStatement(
          index: 3,
          sql: 'SELECT 3',
          type: SQLType.select,
          lineStart: 3,
          lineEnd: 3,
        ),
      ];

      final progressUpdates = <ExecutionProgress>[];
      service.progressStream.listen((progress) {
        progressUpdates.add(progress);
      });

      final future = service.execute(statements);

      // Wait a bit for first statement to start
      await Future.delayed(Duration(milliseconds: 50));
      service.cancel();

      final results = await future;

      expect(results.length, lessThan(3));
      expect(service.isExecuting, false);

      // Check that cancellation was recorded
      final finalProgress = progressUpdates.last;
      expect(finalProgress.status, ExecutionStatus.cancelled);
    });

    test('should throw if already executing', () async {
      mockExecutor.artificialDelay = Duration(milliseconds: 200);
      mockExecutor.mockQuery('SELECT 1', [
        {'1': 1},
      ]);

      final statements = [
        SQLStatement(
          index: 1,
          sql: 'SELECT 1',
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
      ];

      // Start first execution
      final future = service.execute(statements);

      // Try to start second execution while first is running
      expect(() => service.execute(statements), throwsA(isA<StateError>()));

      // Wait for first to complete
      await future;
    });

    test('should handle empty statement list', () async {
      final results = await service.execute([]);
      expect(results, isEmpty);
      expect(service.isExecuting, false);
    });

    test('should track execution time', () async {
      mockExecutor.artificialDelay = Duration(milliseconds: 50);
      mockExecutor.mockQuery('SELECT 1', [
        {'1': 1},
      ]);

      final statements = [
        SQLStatement(
          index: 1,
          sql: 'SELECT 1',
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
      ];

      final results = await service.execute(statements);

      expect(results.length, 1);
      expect(results[0].executionTime.inMilliseconds, greaterThanOrEqualTo(50));
    });

    test('should emit final progress with completed status', () async {
      mockExecutor.mockQuery('SELECT 1', [
        {'1': 1},
      ]);

      final statements = [
        SQLStatement(
          index: 1,
          sql: 'SELECT 1',
          type: SQLType.select,
          lineStart: 1,
          lineEnd: 1,
        ),
      ];

      final progressUpdates = <ExecutionProgress>[];
      service.progressStream.listen((progress) {
        progressUpdates.add(progress);
      });

      await service.execute(statements);

      final finalProgress = progressUpdates.last;
      expect(finalProgress.status, ExecutionStatus.completed);
      expect(finalProgress.isComplete, true);
      expect(finalProgress.percentComplete, 100.0);
    });
  });
}
