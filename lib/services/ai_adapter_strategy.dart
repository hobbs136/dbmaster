import 'database_abstract.dart';

/// 数据库 adapter 的 AI 执行能力策略（open-core 双仓拆分，ADR 0001）。
///
/// [AiAdapterMixin.executeAiCommand] 委托到此策略；OSS 下 adapter.aiStrategy
/// 为 `null`（mixin 抛 `UnsupportedError`），Pro 仓注入 `ProAiStrategy` 实现
/// 真实 agent 工具执行。
///
/// **不委托 `getAiSchemaSummary`**：它是基础 Free chat 的 schema 上下文收集
/// （被 ai_session_orchestrator / mysql_ai_context_collector 等 Free 路径调用），
/// 留核心 mixin 以确保 OSS Free chat 不丢上下文（survey 测绘确认委托会
/// 导致公开仓 Free chat 永久丢 schema 上下文）。
abstract class AiAdapterStrategy {
  const AiAdapterStrategy();

  /// 执行 AI 生成的命令（agent 工具路径，Pro-only）。
  ///
  /// 入参 [command] 可能是 SQL 或 NoSQL（如 Mongo JSON 串）—— 实现按
  /// [DatabaseAdapter.databaseType] 分发，内部调 [DatabaseAdapter.executeQuery]。
  /// agent 路径在更上游已被 ProModule.isPro 门禁截断，此处的 null-throw
  /// 是第二道纵深防线。
  Future<AiExecutionResult> executeAiCommand(
    DatabaseAdapter adapter,
    String command, {
    String locale = 'en',
  });
}
