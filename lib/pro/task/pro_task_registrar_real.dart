import 'package:dbmaster/models/task_models.dart';
import 'package:dbmaster/pro/data_import/import_task_executor.dart';
import 'package:dbmaster/pro/data_sync/data_sync_task_executor.dart';
import 'package:dbmaster/services/ai/ai_client.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/pro_task_registrar.dart';
import 'package:dbmaster/services/task/task_executor.dart';

/// [ProTaskRegistrar] 的 Pro 实现（open-core B.2）。
///
/// 为 [TaskType.import] 返回 [ImportTaskExecutor]，为 [TaskType.dataSync]
/// 返回 [DataSyncTaskExecutor]；其它类型返回 null（export / query 已由 OSS
/// 的 [TaskProvider._createExecutor] 自行处理）。
class ProTaskRegistrarImpl implements ProTaskRegistrar {
  const ProTaskRegistrarImpl();

  @override
  TaskExecutor? createExecutor(
    DbTask task,
    DatabaseAdapter adapter,
    AiClient aiClient,
    DatabaseService dbService,
  ) {
    switch (task.type) {
      case TaskType.import:
        final config = task.config is ImportTaskConfig
            ? task.config as ImportTaskConfig
            : null;
        if (config == null) return null;
        return ImportTaskExecutor(
          config: config,
          adapter: adapter,
          aiClient: aiClient,
        );
      case TaskType.dataSync:
        // 提供 DataSyncTaskExecutor（客户端直连源/目标库，单表）。
        // 注意：DataSyncDialog 的「本地即时」按钮目前不走 TaskProvider，
        // 直接 new DataSyncService 直跑（见 data_sync_dialog.dart 的 _startSync）。
        // 这条 executor 路径为未来「任务面板里也能跑 data_sync 任务」预留，
        // 当前无 UI 入口创建 dataSync 类型的 DbTask。
        // 多表 JOIN / 调度走服务端 DataSyncApiService，不经此路径。
        final config = task.config is DataSyncTaskConfig
            ? task.config as DataSyncTaskConfig
            : null;
        if (config == null) return null;
        return DataSyncTaskExecutor(
          config: config,
          databaseService: dbService,
        );
      case TaskType.export:
      case TaskType.query:
        return null;
    }
  }
}
