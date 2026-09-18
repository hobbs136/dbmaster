import 'package:flutter/foundation.dart';
import 'execution_result.dart';

@immutable
class ExecutionSummary {
  final int totalCount;
  final int successCount;
  final int errorCount;
  final Duration totalTime;
  final int totalAffectedRows;
  final DateTime startTime;
  final DateTime endTime;

  const ExecutionSummary({
    required this.totalCount,
    required this.successCount,
    required this.errorCount,
    required this.totalTime,
    required this.totalAffectedRows,
    required this.startTime,
    required this.endTime,
  });

  bool get allSuccess => errorCount == 0;

  factory ExecutionSummary.fromResults(
    List<ExecutionResult> results,
    DateTime startTime,
    DateTime endTime,
  ) {
    final totalCount = results.length;
    final successCount = results.where((r) => r.success).length;
    final errorCount = totalCount - successCount;
    final totalAffectedRows = results
        .where((r) => r.affectedRows != null)
        .fold(0, (sum, r) => sum + r.affectedRows!);

    return ExecutionSummary(
      totalCount: totalCount,
      successCount: successCount,
      errorCount: errorCount,
      totalTime: endTime.difference(startTime),
      totalAffectedRows: totalAffectedRows,
      startTime: startTime,
      endTime: endTime,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExecutionSummary &&
        other.totalCount == totalCount &&
        other.successCount == successCount &&
        other.errorCount == errorCount;
  }

  @override
  int get hashCode => Object.hash(totalCount, successCount, errorCount);

  @override
  String toString() {
    return 'ExecutionSummary($successCount/$totalCount success, $errorCount errors, ${totalTime.inMilliseconds}ms, $totalAffectedRows affected)';
  }
}
