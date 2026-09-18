import 'package:flutter/foundation.dart';

import 'adapters/mongo_cluster_strategy.dart';
import 'ai_agent_runner.dart';
import 'free_chat_runner.dart';
import 'pro_task_registrar.dart';
import 'schema_diff_sync_strategy.dart';

/// Pro 能力扩展点 SPI——客户端全免费，所有功能均可用。
///
/// isPro 恒为 true，所有 Pro 功能（AI Agent 工具循环、Schema Diff 同步、
/// Data Sync、Data Import、MongoDB 集群连接）均可用。
///
/// extends [ChangeNotifier]——使 AppProvider 的 addListener / removeListener /
/// dispose 签名稳定。
abstract class ProModule extends ChangeNotifier {
  /// Pro 是否已解锁——全免费客户端恒返回 true。
  bool get isPro;

  /// 启动初始化（全免费客户端为 no-op，不触碰 IAP / license 平台通道）。
  Future<void> initialize();

  /// MongoDB 集群（副本集 / 分片）连接策略。
  MongoClusterStrategy? get mongoClusterStrategy => null;

  /// Schema Diff 同步策略。
  SchemaSyncStrategy? get schemaSyncStrategy => null;

  /// Pro 任务执行器注册器。
  ProTaskRegistrar? get proTaskRegistrar => null;

  /// AI Agent 运行器工厂。默认返回 [FreeChatRunner]（无工具流式对话）；
  /// [ProModuleImpl] 覆写返回完整工具循环实现（AiAgentService.new）。
  AiAgentFactory get createAgentRunner => FreeChatRunner.new;
}

/// 全免费客户端默认 [ProModule] 实现——isPro 恒 true，零初始化开销。
///
/// 用作 [AppProvider] 构造函数默认值；所有 Pro 功能在客户端上均可用。
/// [ProModuleImpl]（lib/pro/）在此基础上注入真实 AI Agent / Schema Sync /
/// Mongo 集群等实现。
class FreeProModule extends ProModule {
  @override
  bool get isPro => true;

  @override
  Future<void> initialize() async {}
}
