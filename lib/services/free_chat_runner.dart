import '../models/agent_checkpoint.dart';
import '../utils/app_logger.dart';
import 'ai/ai_service_localizations.dart';
import 'ai/prompt_builders/ai_prompt_builder.dart';
import 'ai/response_parsers/ai_response_parser.dart';
import 'ai_service.dart';
import 'ai_agent_runner.dart';
import 'database_abstract.dart';

// open-core Phase B.1 — Free/Pro 拆分的 OSS 默认 Agent 运行器。
//
// 行为克隆自 lib/services/ai_agent_service.dart 的 useTools=false 分支：
//   - 系统提示词构建（_getSystemPrompt / _buildDefaultSystemPrompt 逐字移植）
//   - 用户输入 sanitize（_sanitizeUserInput）
//   - 流式响应（_aiClient.chatStreamWithReasoning + content/reasoning 双缓冲）
//   - 结果组装（extractExecutableStatements → securityCheck；否则 ok）
//
// 不实现工具调用循环 / checkpoint 恢复 / onToolCall 回调（Pro 专属）——
// 构造签名与 [AiAgentFactory] 一致使 ProModule 可在 Pro 仓中切回完整实现。

/// OSS 默认 Agent 运行器：无工具纯流式对话。
///
/// 等价于 [AiAgentService] 在 `allowTools=false`（或 provider 不支持工具
/// 调用）时的行为；忽略 [run] 中所有工具相关参数。
class FreeChatRunner implements AiAgentRunner {
  final DatabaseAdapter adapter;
  final AiClient _aiClient;
  final String? selectedDatabase;
  final String? preloadedContext;
  final AiPromptBuilder? _promptService;
  final AiResponseParser? _responseParser;
  final AiServiceLocalizations _l10n;

  String? _cachedSystemPrompt;

  FreeChatRunner({
    required this.adapter,
    AiClient? aiClient,
    this.selectedDatabase,
    this.preloadedContext,
    AiPromptBuilder? promptService,
    AiResponseParser? responseParser,
    String locale = 'en',
  }) : _aiClient = aiClient ?? AiService().client,
       _promptService = promptService,
       _responseParser = responseParser,
       _l10n = AiServiceLocalizations(locale);

  Future<String> _getSystemPrompt() async {
    if (_cachedSystemPrompt != null) return _cachedSystemPrompt!;

    String base;
    if (_promptService != null && selectedDatabase != null) {
      final conn = adapter.currentConnection;
      if (conn != null) {
        base = await _promptService.buildSystemPrompt(
          connection: conn,
          databaseName: selectedDatabase,
          includeSchema: true,
        );
        // PromptBuilder 路径此前丢弃 preloadedContext（提及表 schema + FK），
        // 导致 C23「Schema 上下文开关」在 Pro 主路径失效——这里补回
        //（与 AiAgentService._getSystemPrompt 保持同构）。
        if (preloadedContext != null && preloadedContext!.isNotEmpty) {
          base =
              '$base\n[${_l10n.systemPromptContextLabel}]\n$preloadedContext\n';
        }
      } else {
        base = _buildDefaultSystemPrompt();
      }
    } else {
      base = _buildDefaultSystemPrompt();
    }
    _cachedSystemPrompt = '$base\n${_l10n.systemPromptLanguageInstruction}\n';
    return _cachedSystemPrompt!;
  }

  String _buildDefaultSystemPrompt() {
    final type = adapter.databaseType;
    final currentDb = selectedDatabase ?? 'Unknown';
    final contextInfo = preloadedContext != null && preloadedContext!.isNotEmpty
        ? '\n[${_l10n.systemPromptContextLabel}]\n$preloadedContext\n'
        : '';
    final base =
        '''${_l10n.systemPromptIdentity} Currently connected database type: ${type.displayName}.
$contextInfo

[${_l10n.systemPromptRulesLabel}]
1. ${_l10n.systemPromptRule1}
2. ${_l10n.systemPromptRule2}
3. ${_l10n.systemPromptRule3}
4. ${_l10n.systemPromptRule4}
5. ${_l10n.systemPromptRule5}
6. ${_l10n.systemPromptRule6}
7. ${_l10n.systemPromptRule7}
8. ${_l10n.systemPromptRule8}
9. ${_l10n.systemPromptRule9}
10. ${_l10n.systemPromptRule10}
11. ${_l10n.systemPromptRule11}
12. ${_l10n.systemPromptRule12}

[${_l10n.systemPromptDataRulesLabel}]
- ${_l10n.systemPromptDataRule1}
- ${_l10n.systemPromptDataRule2}
- ${_l10n.systemPromptDataRule3}
- ${_l10n.systemPromptDataRule4}
- ${_l10n.systemPromptDataRule5}

[${_l10n.systemPromptPerfRulesLabel}]
- ${_l10n.systemPromptPerfRule1}
- ${_l10n.systemPromptPerfRule2}
- ${_l10n.systemPromptPerfRule3}
- ${_l10n.systemPromptPerfRule4}

${_l10n.systemPromptCurrentDbLabel}:
$currentDb
''';
    return '$base\n${_l10n.systemPromptForDbType(type.displayName)}';
  }

  /// Detect and sanitize potential prompt injection attempts in user input.
  /// Returns sanitized text and logs warning if injection patterns detected.
  static String _sanitizeUserInput(String input) {
    final injectionPatterns = [
      RegExp(
        r'ignore\s+(previous|above|all)\s+instructions?',
        caseSensitive: false,
      ),
      RegExp(r'you\s+are\s+now\s+(a|an)\s+', caseSensitive: false),
      RegExp(r'system\s*[:\-]\s*', caseSensitive: false),
      RegExp(r'新的?\s*指令'),
      RegExp(r'忽略\s*(上述|前面|所有)'),
      RegExp(r'你现在\s*(是|扮演)'),
      RegExp(r'\[system\]', caseSensitive: false),
      RegExp(r'<system>', caseSensitive: false),
    ];

    var sanitized = input;
    var detected = false;
    for (final pattern in injectionPatterns) {
      if (pattern.hasMatch(sanitized)) {
        detected = true;
        sanitized = sanitized.replaceAll(pattern, '[BLOCKED]');
      }
    }

    if (detected) {
      AppLogger.w(
        'FreeChatRunner',
        '⚠️ Potential prompt injection detected and sanitized',
      );
    }

    return sanitized;
  }

  @override
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
    bool allowTools = true,
    bool Function()? isCancelled,
    Future<bool> Function({
      required String actionType,
      required String description,
      List<String>? statements,
      String? impactReport,
    })?
    onConfirmationRequested,
  }) async {
    // FreeChatRunner 永不使用工具——工具相关参数（onToolCall / onToolResult /
    // onCheckpoint / resumeFrom / allowTools 等）一律忽略；OSS 入口在
    // AiSessionOrchestrator.sendUserMessage 处已据 isPro 强制 allowTools=false。
    onIterationStart?.call();

    final history = <Map<String, dynamic>>[];
    if (previousHistory != null && previousHistory.isNotEmpty) {
      history.addAll(previousHistory);
    }
    final sanitizedMessage = _sanitizeUserInput(userMessage);
    history.add({'role': 'user', 'content': sanitizedMessage});

    // Streaming chat (no tools): port of AiAgentService useTools=false branch.
    final buffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final systemPrompt = await _getSystemPrompt();
    await for (final chunk in _aiClient.chatStreamWithReasoning(
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      message: '',
      systemPrompt: systemPrompt,
      history: history,
      timeout: timeout,
      thinkingEnabled: thinkingEnabled,
    )) {
      onStreamChunk?.call(chunk);
      if (chunk.type == 'content') {
        buffer.write(chunk.text);
      } else if (chunk.type == 'reasoning') {
        reasoningBuffer.write(chunk.text);
      }
    }
    final finalResponse = buffer.toString();
    final reasoningContent = reasoningBuffer.isNotEmpty
        ? reasoningBuffer.toString()
        : null;

    // 结果组装：优先抽取可执行语句并做安全校验；否则视为纯对话返回 ok。
    final extractedCommands =
        _responseParser?.extractExecutableStatements(finalResponse) ?? [];

    if (extractedCommands.isNotEmpty) {
      final firstCommand = extractedCommands.first;
      final security = adapter.validateCommand(firstCommand);

      AppLogger.d(
        'FreeChatRunner',
        '✅ Returning AgentRunResult with ${extractedCommands.length} SQL statements',
      );
      return AgentRunResult(
        finalResponse: finalResponse,
        extractedCommand: firstCommand,
        extractedCommands: extractedCommands,
        reasoningContent: reasoningContent,
        securityCheck: security,
      );
    }

    AppLogger.d(
      'FreeChatRunner',
      '✅ Returning AgentRunResult: contentLength=${finalResponse.length}',
    );
    return AgentRunResult(
      finalResponse: finalResponse,
      reasoningContent: reasoningContent,
      securityCheck: SecurityCheckResult.ok,
    );
  }
}
