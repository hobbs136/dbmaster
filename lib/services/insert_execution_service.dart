import 'dart:async';

import 'database_abstract.dart';

/// Result of a batch insert execution.
class InsertExecutionResult {
  final int totalStatements;
  final int successCount;
  final int failureCount;
  final List<String> errors;
  final List<String> executedSql;

  InsertExecutionResult({
    required this.totalStatements,
    required this.successCount,
    required this.failureCount,
    required this.errors,
    required this.executedSql,
  });

  bool get allSuccess => failureCount == 0;
  bool get hasErrors => errors.isNotEmpty;

  @override
  String toString() {
    if (allSuccess) {
      return '成功执行 $successCount 条 SQL';
    }
    return '执行完成: 成功 $successCount 条, 失败 $failureCount 条';
  }
}

/// Handles batch INSERT execution with confirmation support.
class InsertExecutionService {
  final DatabaseAdapter adapter;

  InsertExecutionService({required this.adapter});

  /// Execute a list of INSERT SQL statements.
  /// Each statement is validated before execution.
  Future<InsertExecutionResult> executeBatch({
    required List<String> statements,
    bool skipValidation = false,
  }) async {
    final errors = <String>[];
    final executed = <String>[];
    var successCount = 0;

    for (final sql in statements) {
      try {
        // Validate command if not skipped
        if (!skipValidation) {
          final check = adapter.validateCommand(sql);
          if (!check.allowed) {
            errors.add('被拒绝: $sql\n原因: ${check.reason}');
            continue;
          }
        }

        // Execute
        final result = await adapter.executeQuery(sql);
        successCount++;
        executed.add(sql);

        // Log if there was a message
        if (result.message != null && result.message!.isNotEmpty) {
          // Success message from server
        }
      } catch (e) {
        errors.add('执行失败: $sql\n错误: $e');
      }
    }

    return InsertExecutionResult(
      totalStatements: statements.length,
      successCount: successCount,
      failureCount: statements.length - successCount,
      errors: errors,
      executedSql: executed,
    );
  }

  /// Check if a set of SQL statements are safe to execute.
  /// Returns validation results for each statement.
  List<SecurityCheckResult> validateStatements(List<String> statements) {
    return statements.map((sql) => adapter.validateCommand(sql)).toList();
  }

  /// Check if any statement requires user confirmation.
  bool needsConfirmation(List<String> statements) {
    for (final sql in statements) {
      final check = adapter.validateCommand(sql);
      if (check.riskLevel == CommandRiskLevel.warning ||
          check.riskLevel == CommandRiskLevel.dangerous) {
        return true;
      }
    }
    return false;
  }
}
