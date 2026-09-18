import '../models/task_models.dart';
import 'ai/ai_client.dart';
import 'database_abstract.dart';
import 'database_service.dart';
import 'task/task_executor.dart';

/// Pro 任务执行器注册器（open-core Phase B.2 logic SPI，ADR 0001）。
///
/// 公开仓（OSS）的 [TaskProvider] 只调度导出（export）与查询（query）任务；
/// 导入（import）与数据同步（dataSync）任务的执行器依赖 Pro 专属服务，经此
/// 注册器注入。
///
/// OSS 构建（`main_oss.dart`）不注入实现——[ProModule.proTaskRegistrar]
/// 返回 null 时，[TaskProvider._createExecutor] 对这些类型直接返回 null
/// （与「不支持的执行任务类型」一致），相关任务在 OSS 不可启动。
///
/// 遵循宪法 IV.4（AppProvider Facade）—— Pro 能力经 SPI 注入。注册器只引
/// 用基础类型（[DbTask] / [DatabaseAdapter] / [AiClient] / [TaskExecutor] /
/// [DatabaseService]），不引入任何 Pro 符号。
abstract class ProTaskRegistrar {
  const ProTaskRegistrar();

  /// 为给定任务创建 Pro 执行器（[TaskType.import] / [TaskType.dataSync]）；
  /// 不支持时返回 null。
  ///
  /// `dbService` 用于 dataSync 这类需要双 adapter（源 + 目标）的执行器——它
  /// 内部按 config 里的 connectionId 自取所需 adapter。`adapter` 是 import /
  /// 单连接任务用的当前连接。
  TaskExecutor? createExecutor(
    DbTask task,
    DatabaseAdapter adapter,
    AiClient aiClient,
    DatabaseService dbService,
  );
}

/// OSS 默认实现：恒返回 null（无 Pro 任务执行器）。
///
/// 公开仓构建也可直接让 [ProModule] getter 返回 null——此类仅为「显式占位」
/// 便于未来扩展；当前 [FreeProModule] 直接返回 null（不构造此实例）。
class NoOpProTaskRegistrar extends ProTaskRegistrar {
  const NoOpProTaskRegistrar();

  @override
  TaskExecutor? createExecutor(
    DbTask task,
    DatabaseAdapter adapter,
    AiClient aiClient,
    DatabaseService dbService,
  ) => null;
}
