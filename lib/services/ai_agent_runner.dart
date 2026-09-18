import '../models/agent_checkpoint.dart';
import 'ai_service.dart';
import 'ai/prompt_builders/ai_prompt_builder.dart';
import 'ai/response_parsers/ai_response_parser.dart';
import 'database_abstract.dart';

// open-core Phase B.1 — AI Agent 抽象运行器（SPI 切口）。
//
// 公开仓（Apache-2.0）定义此抽象 + [FreeChatRunner] 默认实现（仅无工具对话，
// 即 AiAgentService 中 useTools=false 分支的行为克隆）；
// Pro 仓（专有）implements 注入完整工具循环（AiAgentService.new）。
//
// 此文件仅依赖 core 类型（DatabaseAdapter / AiClient / AiPromptBuilder /
// AiResponseParser / AgentCheckpoint / TokenUsage / AiStreamChunk /
// AiExecutionResult / SecurityCheckResult），不引入任何 Pro 符号——
// lib/main_oss.dart 经 main.dart → AppProvider → AiPanelProvider →
// AiSessionOrchestrator 仅可达此抽象 + [FreeChatRunner]，lib/services/
// ai_agent_service.dart 在 OSS 构建下被 AOT tree-shake。

/// 单次工具调用的执行记录（结构透出给 orchestrator / UI）。
class AgentToolExecution {
  final String toolName;
  final Map<String, dynamic> arguments;
  final AiExecutionResult result;

  AgentToolExecution({
    required this.toolName,
    required this.arguments,
    required this.result,
  });
}

/// Agent 一次 run() 的最终结果。
class AgentRunResult {
  final String finalResponse;
  final String? extractedCommand;
  final List<String> extractedCommands;
  final String? reasoningContent;
  final SecurityCheckResult securityCheck;
  final List<AgentToolExecution> toolExecutions;
  final TokenUsage? tokenUsage;
  final bool isInterrupted;
  final AgentCheckpoint? checkpoint;

  AgentRunResult({
    required this.finalResponse,
    this.extractedCommand,
    this.extractedCommands = const [],
    this.reasoningContent,
    required this.securityCheck,
    this.toolExecutions = const [],
    this.tokenUsage,
    this.isInterrupted = false,
    this.checkpoint,
  });
}

/// Agent 运行器构造器签名——与 [AiAgentRunner] 子类的构造器严格一致。
///
/// 默认实现 [FreeChatRunner] 在 OSS 构建下经 [ProModule.createAgentRunner]
/// 注入；Pro 仓实现返回完整工具循环（[AiAgentService] 实例）。
typedef AiAgentFactory = AiAgentRunner Function({
  required DatabaseAdapter adapter,
  AiClient? aiClient,
  String? selectedDatabase,
  String? preloadedContext,
  AiPromptBuilder? promptService,
  AiResponseParser? responseParser,
  String locale,
});

/// AI Agent 抽象运行器（open-core Phase B.1 SPI）。
///
/// `run` 签名与原 [AiAgentService.run] 完全一致——所有命名参数（含 Pro 专属
/// 的 onToolCall / onToolResult / onCheckpoint / resumeFrom / allowTools 等）
/// 保留在抽象层，使 Pro 实现无需覆写签名即可直接委托给 AiAgentService.run。
///
/// 默认 [FreeChatRunner] 忽略工具相关参数，仅实现无工具流式对话路径。
abstract class AiAgentRunner {
  Future<AgentRunResult> run({
    required String userMessage,
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    Duration timeout = const Duration(seconds: 60),
    bool thinkingEnabled = false,
    List<Map<String, dynamic>>? previousHistory,
    void Function()? onIterationStart,
    void Function(String toolName, Map<String, dynamic> args)? onToolCall,
    void Function(
      String toolName,
      Map<String, dynamic> args,
      AiExecutionResult result,
    )?
    onToolResult,
    void Function(AiStreamChunk chunk)? onStreamChunk,
    void Function(AgentCheckpoint checkpoint)? onCheckpoint,
    int maxIterations = 30,
    int maxToolCalls = 20,
    AgentCheckpoint? resumeFrom,
    bool readOnly = false,

    /// Free/Pro 门禁：Free 用户纯对话（不给工具），Pro 才允许工具调用。
    /// 默认 true 保持既有调用方行为；门禁入口必须显式传 allowTools。
    bool allowTools = true,
    bool Function()? isCancelled,
    Future<bool> Function({
      required String actionType,
      required String description,
      List<String>? statements,
      String? impactReport,
    })? onConfirmationRequested,
  });
}
