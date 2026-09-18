import 'dart:async';
import '../../models/task_models.dart';

/// 任务执行器抽象接口
abstract class TaskExecutor {
  /// 执行任务
  /// [onProgress] 进度回调
  /// [onLog] 日志回调
  Future<void> execute({
    required Function(TaskProgressUpdate) onProgress,
    required Function(TaskLog) onLog,
    required Function() isCancelled,
  });
}

/// 任务进度更新
class TaskProgressUpdate {
  final int progress;
  final String? phase;
  final int? processedRows;
  final int? totalRows;

  TaskProgressUpdate({
    required this.progress,
    this.phase,
    this.processedRows,
    this.totalRows,
  });
}
