import '../models/schema_diff_models.dart';
import 'database_abstract.dart';
import 'database_service.dart';

/// Schema Diff 同步策略（open-core Phase B.2 logic SPI，ADR 0001）。
///
/// 公开仓（OSS）的 Schema Diff 三栏页面只负责**展示**差异；将差异转化为
/// DDL 同步计划并执行（[SchemaSyncService]）属 Pro 能力，经此策略注入。
/// OSS 构建（`main_oss.dart`）不注入实现——`SchemaDiffPage` 在 ProModule
/// 拿到 null 时直接 short-circuit（不生成计划、不执行），用户操作入口
/// 仍由 `trySchemaSync` 门禁拦截，行为与 Pro 仓 NoOp 等价。
///
/// 遵循宪法 IV.4（AppProvider Facade）—— Pro 能力经 SPI 注入，非 Provider
/// 间直接引用。`dbService` 作为首参，使 Pro 仓实现仅需薄包一层
/// `SchemaSyncService(dbService)`。
///
/// `SyncPlan` / `SyncProgress` / `SyncExecutionPhase` 来自共享模型
/// `lib/models/schema_diff_models.dart`（OSS），不引入任何 Pro 符号。
abstract class SchemaSyncStrategy {
  const SchemaSyncStrategy();

  /// 根据差异报告生成同步计划（DDL 脚本列表）。
  ///
  /// 参数镜像 [SchemaSyncService.generateSyncPlan]——Pro 实现直接转发。
  SyncPlan generateSyncPlan(
    DatabaseService dbService, {
    required SchemaDiffReport report,
    required String targetConnectionId,
    required String targetDatabase,
    required DatabaseType dbType,
  });

  /// 执行同步计划，通过 Stream 发射实时进度。
  ///
  /// 参数镜像 [SchemaSyncService.executeWithProgress]——Pro 实现直接转发。
  Stream<SyncProgress> executeWithProgress(
    DatabaseService dbService, {
    required SyncPlan plan,
    required String connectionId,
    required String databaseName,
    required DatabaseType dbType,
    bool dryRun = true,
  });
}
