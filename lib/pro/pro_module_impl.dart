import 'package:dbmaster/pro/ai/ai_agent_service.dart';
import 'package:dbmaster/pro/mongo/cluster_mongo_uri_strategy.dart';
import 'package:dbmaster/pro/schema_diff_sync/schema_sync_strategy_real.dart';
import 'package:dbmaster/pro/task/pro_task_registrar_real.dart';
import 'package:dbmaster/services/adapters/mongo_cluster_strategy.dart';
import 'package:dbmaster/services/ai_agent_runner.dart';
import 'package:dbmaster/services/pro_module.dart';
import 'package:dbmaster/services/pro_task_registrar.dart';
import 'package:dbmaster/services/schema_diff_sync_strategy.dart';

/// [ProModule] 的全功能实现——客户端完全免费，零付费墙。
///
/// isPro 恒为 true，initialize 为 no-op。不经 IAP / license / trial 通道。
///
/// 装配真实 Pro 行为：
///  - [AiAgentService.new] 完整工具循环（替代 FreeChatRunner）；
///  - [ClusterMongoUriStrategy] 副本集 / 分片 URI 构建；
///  - [ProSchemaSyncStrategy] Schema Diff 同步计划与执行；
///  - [ProTaskRegistrarImpl] 导入任务执行器。
class ProModuleImpl extends ProModule {
  @override
  bool get isPro => true;

  @override
  Future<void> initialize() async {
    // 全免费客户端：无 IAP / license 平台通道需要初始化。
    notifyListeners();
  }

  @override
  AiAgentFactory get createAgentRunner => AiAgentService.new;

  @override
  SchemaSyncStrategy? get schemaSyncStrategy => const ProSchemaSyncStrategy();

  @override
  ProTaskRegistrar? get proTaskRegistrar => const ProTaskRegistrarImpl();

  @override
  MongoClusterStrategy? get mongoClusterStrategy =>
      const ClusterMongoUriStrategy();
}
