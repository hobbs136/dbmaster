import 'package:dbmaster/models/schema_diff_models.dart';
import 'package:dbmaster/pro/schema_diff_sync/schema_sync_service.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/services/schema_diff_sync_strategy.dart';

/// [SchemaSyncStrategy] 的 Pro 实现（open-core B.2）。
///
/// 薄包一层 [SchemaSyncService]——按 SPI 契约每次调用按需构造
/// `SchemaSyncService(dbService)` 实例（服务对象本身无状态、轻量），
/// 转发 [generateSyncPlan] / [executeWithProgress] 的全部参数。
class ProSchemaSyncStrategy implements SchemaSyncStrategy {
  const ProSchemaSyncStrategy();

  @override
  SyncPlan generateSyncPlan(
    DatabaseService dbService, {
    required SchemaDiffReport report,
    required String targetConnectionId,
    required String targetDatabase,
    required DatabaseType dbType,
  }) {
    return SchemaSyncService(dbService).generateSyncPlan(
      report: report,
      targetConnectionId: targetConnectionId,
      targetDatabase: targetDatabase,
      dbType: dbType,
    );
  }

  @override
  Stream<SyncProgress> executeWithProgress(
    DatabaseService dbService, {
    required SyncPlan plan,
    required String connectionId,
    required String databaseName,
    required DatabaseType dbType,
    bool dryRun = true,
  }) {
    return SchemaSyncService(dbService).executeWithProgress(
      plan: plan,
      connectionId: connectionId,
      databaseName: databaseName,
      dbType: dbType,
      dryRun: dryRun,
    );
  }
}
