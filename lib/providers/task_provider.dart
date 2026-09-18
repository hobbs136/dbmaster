import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/task_models.dart';
import '../services/ai/ai_client.dart';
import '../services/database_abstract.dart';
import '../services/database_service.dart';
import '../services/pro_task_registrar.dart';
import '../services/task/export_task_executor.dart';
import '../services/task/task_executor.dart';

/// 任务管理器
/// 负责任务的创建、调度、执行和状态管理
class TaskProvider extends ChangeNotifier {
  final List<DbTask> _tasks = [];
  DatabaseService? _dbService;
  AiClient? _aiClient;
  // open-core Phase B.2：Pro 任务执行器注册器（import 等）经 ProModule SPI
  // 注入。OSS=null → import 任务不可启动（与「不支持的执行任务类型」一致）。
  ProTaskRegistrar? _proTaskRegistrar;

  TaskProvider({DatabaseService? dbService, AiClient? aiClient})
    : _dbService = dbService,
      _aiClient = aiClient;

  /// 设置数据库服务（延迟注入）
  void setDatabaseService(DatabaseService dbService) {
    _dbService = dbService;
  }

  /// 设置 AI 客户端（延迟注入）
  void setAiClient(AiClient aiClient) {
    _aiClient = aiClient;
  }

  /// 设置 Pro 任务执行器注册器（延迟注入，AppProvider 在 ProModule 接好后调用）。
  /// 传 null 重置回 OSS 状态（无 import 等执行器）。
  void setProTaskRegistrar(ProTaskRegistrar? registrar) {
    _proTaskRegistrar = registrar;
  }

  // Getters
  List<DbTask> get tasks => List.unmodifiable(_tasks);
  List<DbTask> get activeTasks => _tasks.where((t) => t.isActive).toList();
  List<DbTask> get completedTasks =>
      _tasks.where((t) => t.status == TaskStatus.completed).toList();
  List<DbTask> get failedTasks =>
      _tasks.where((t) => t.status == TaskStatus.failed).toList();

  int get runningTaskCount =>
      _tasks.where((t) => t.status == TaskStatus.running).length;

  bool get hasRunningTasks => runningTaskCount > 0;

  /// 创建新任务
  DbTask createTask({
    required TaskType type,
    required TaskConfig config,
    bool autoStart = true,
  }) {
    final task = DbTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}_${_tasks.length}',
      type: type,
      config: config,
      status: TaskStatus.pending,
    );

    _tasks.insert(0, task);
    notifyListeners();

    if (autoStart) {
      // 延迟启动，让 UI 先渲染
      Future.delayed(const Duration(milliseconds: 100), () {
        startTask(task.id);
      });
    }

    return task;
  }

  /// 获取任务
  DbTask? getTask(String taskId) {
    try {
      return _tasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      return null;
    }
  }

  /// 更新任务状态
  void updateTaskStatus(String taskId, TaskStatus status) {
    final task = getTask(taskId);
    if (task == null) return;

    task.status = status;

    if (status == TaskStatus.running && task.startedAt == null) {
      task.startedAt = DateTime.now();
    }

    if (status == TaskStatus.completed ||
        status == TaskStatus.failed ||
        status == TaskStatus.cancelled) {
      task.completedAt = DateTime.now();
    }

    notifyListeners();
  }

  /// 更新任务进度
  void updateTaskProgress(
    String taskId, {
    required int progress,
    String? phase,
    int? processedRows,
    int? totalRows,
  }) {
    final task = getTask(taskId);
    if (task == null) return;

    task.progress = progress.clamp(0, 100);
    if (phase != null) task.currentPhase = phase;
    if (processedRows != null) task.processedRows = processedRows;
    if (totalRows != null) task.totalRows = totalRows;

    notifyListeners();
  }

  /// 设置任务输出路径
  void setTaskOutputPath(String taskId, String path) {
    final task = getTask(taskId);
    if (task == null) return;

    task.outputPath = path;
    notifyListeners();
  }

  /// 设置任务错误信息
  void setTaskError(String taskId, String error) {
    final task = getTask(taskId);
    if (task == null) return;

    task.errorMessage = error;
    task.addError(error);
    notifyListeners();
  }

  /// 设置任务结果统计
  void setTaskResults(
    String taskId, {
    int? totalRows,
    int? processedRows,
    int? affectedRows,
  }) {
    final task = getTask(taskId);
    if (task == null) return;

    if (totalRows != null) task.totalRows = totalRows;
    if (processedRows != null) task.processedRows = processedRows;
    if (affectedRows != null) task.affectedRows = affectedRows;

    notifyListeners();
  }

  /// 取消任务
  Future<void> cancelTask(String taskId) async {
    final task = getTask(taskId);
    if (task == null) return;

    task.cancel();
    updateTaskStatus(taskId, TaskStatus.cancelled);
    task.addInfo('任务已取消');
    notifyListeners();
  }

  /// 重试任务
  Future<void> retryTask(String taskId) async {
    final task = getTask(taskId);
    if (task == null) return;

    // 重置任务状态
    task.status = TaskStatus.pending;
    task.progress = 0;
    task.currentPhase = null;
    task.errorMessage = null;
    task.totalRows = null;
    task.processedRows = null;
    task.affectedRows = null;
    task.outputPath = null;
    task.logs.clear();
    task.reset();
    task.startedAt = null;
    task.completedAt = null;

    notifyListeners();

    // 自动开始执行
    await startTask(taskId);
  }

  /// 开始执行任务
  Future<void> startTask(String taskId) async {
    final task = getTask(taskId);
    if (task == null) return;

    if (task.status != TaskStatus.pending) {
      return;
    }

    updateTaskStatus(taskId, TaskStatus.running);

    try {
      // 获取数据库适配器
      final adapter = _getAdapter(task.config.connectionId);
      if (adapter == null) {
        throw Exception('数据库连接不可用');
      }

      // 创建执行器
      final executor = _createExecutor(task, adapter);
      if (executor == null) {
        throw Exception('不支持的执行任务类型');
      }

      // 执行任务
      await executor.execute(
        onProgress: (update) {
          updateTaskProgress(
            taskId,
            progress: update.progress,
            phase: update.phase,
            processedRows: update.processedRows,
            totalRows: update.totalRows,
          );
        },
        onLog: (log) {
          task.addLog(log);
          notifyListeners();
        },
        isCancelled: () => task.isCancelled,
      );

      if (!task.isCancelled) {
        updateTaskStatus(taskId, TaskStatus.completed);
        task.addSuccess('任务执行完成');
      }
    } catch (e) {
      if (!task.isCancelled) {
        setTaskError(taskId, e.toString());
        updateTaskStatus(taskId, TaskStatus.failed);
      }
    }
  }

  /// 创建任务执行器
  TaskExecutor? _createExecutor(DbTask task, DatabaseAdapter adapter) {
    switch (task.type) {
      case TaskType.import:
        // open-core Phase B.2：import 执行器（ImportTaskExecutor）依赖 Pro 专属
        // SmartImportService/FileAnalyzer，经 ProTaskRegistrar SPI 注入。
        // OSS（registrar=null 或 _aiClient=null）→ 返回 null，导入任务不可启动。
        final aiClient = _aiClient;
        if (aiClient == null) return null;
        final dbService = _dbService;
        if (dbService == null) return null;
        return _proTaskRegistrar?.createExecutor(task, adapter, aiClient, dbService);
      case TaskType.dataSync:
        // executor（经 ProTaskRegistrar 注入 DataSyncTaskExecutor）。
        // 注意：DataSyncDialog 的「本地即时」按钮不走 TaskProvider，直接 new
        // DataSyncService 直跑。这条路径为未来 UI 入口预留，当前无 dataSync
        // 类型的 DbTask 被创建。OSS 或 dbService 未注入 → 返回 null。
        final aiClient = _aiClient;
        final dbService = _dbService;
        if (aiClient == null || dbService == null) return null;
        return _proTaskRegistrar?.createExecutor(task, adapter, aiClient, dbService);
      case TaskType.export:
        return ExportTaskExecutor(
          config: task.config as ExportTaskConfig,
          adapter: adapter,
        );
      case TaskType.query:
        // TODO: 实现查询任务执行器
        return null;
    }
  }

  /// 获取数据库适配器
  DatabaseAdapter? _getAdapter(String connectionId) {
    return _dbService?.getAdapter(connectionId);
  }

  /// 删除任务
  void removeTask(String taskId) {
    final task = getTask(taskId);
    if (task != null && task.status == TaskStatus.running) {
      // 先取消再删除
      task.cancel();
    }
    _tasks.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  /// 清空已完成的任务
  void clearCompletedTasks() {
    _tasks.removeWhere((t) => t.isDone);
    notifyListeners();
  }

  /// 获取任务统计
  Map<String, int> getTaskStats() {
    return {
      'total': _tasks.length,
      'pending': _tasks.where((t) => t.status == TaskStatus.pending).length,
      'running': _tasks.where((t) => t.status == TaskStatus.running).length,
      'completed': _tasks.where((t) => t.status == TaskStatus.completed).length,
      'failed': _tasks.where((t) => t.status == TaskStatus.failed).length,
      'cancelled': _tasks.where((t) => t.status == TaskStatus.cancelled).length,
    };
  }

  @override
  void dispose() {
    // 取消所有运行中的任务
    for (final task in _tasks) {
      if (task.status == TaskStatus.running) {
        task.cancel();
      }
    }
    super.dispose();
  }
}
