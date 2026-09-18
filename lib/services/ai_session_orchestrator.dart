import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../models/ai_conversation_session.dart';
import '../utils/app_logger.dart';
import '../models/database_models.dart';
import '../models/ai_message_type.dart';
import 'ai/ai_session_manager.dart';
import 'ai/ai_service_localizations.dart';
import 'ai/ai_context_builder.dart';
import 'ai_agent_runner.dart';
import 'free_chat_runner.dart';
import 'database_abstract.dart';
import 'database_service.dart';
import 'ai/ai_prompt_factory.dart';
import 'ai/ai_parser_factory.dart';
import 'ai/prompt_builders/ai_prompt_builder.dart';
import 'ai/response_parsers/ai_response_parser.dart';
import 'ai_service.dart';
import 'insert_execution_service.dart';
import 'query_execution_interceptor.dart';
import 'schema_analyzer/schema_analyzer.dart';
import '../providers/task_provider.dart';
import '../models/task_models.dart';

enum MessageDeltaType { add, update, remove, clear }

class MessageDelta {
  final MessageDeltaType type;
  final String? messageId;
  final AiMessage? message;
  final String? field;
  final dynamic value;

  MessageDelta({
    required this.type,
    this.messageId,
    this.message,
    this.field,
    this.value,
  });

  factory MessageDelta.add(AiMessage message) => MessageDelta(
    type: MessageDeltaType.add,
    messageId: message.id,
    message: message,
  );

  factory MessageDelta.update(String messageId, String field, dynamic value) =>
      MessageDelta(
        type: MessageDeltaType.update,
        messageId: messageId,
        field: field,
        value: value,
      );

  factory MessageDelta.remove(String messageId) =>
      MessageDelta(type: MessageDeltaType.remove, messageId: messageId);

  factory MessageDelta.clear() => MessageDelta(type: MessageDeltaType.clear);
}

class SessionSnapshot {
  final List<AiMessage> messages;
  final AiConversationSession? currentSession;
  final List<AiBookmark> bookmarks;
  SessionSnapshot({
    required this.messages,
    this.currentSession,
    this.bookmarks = const [],
  });
}

/// Callback for requesting user confirmation before executing INSERT statements.
typedef InsertConfirmationCallback =
    Future<bool> Function({
      required String tableName,
      required int count,
      required List<String> statements,
    });

class AiSessionOrchestrator {
  final AiSessionManager _sessionManager;
  final AiClient _aiClient;
  final DatabaseService? _dbService;
  final _stateController = StreamController<MessageDelta>.broadcast();

  /// Pending INSERT statements waiting for user confirmation.
  final List<String> _pendingInsertStatements = [];
  String? _pendingInsertTable;
  int _pendingInsertCount = 0;

  /// Callback to request user confirmation. Must be set by UI layer.
  InsertConfirmationCallback? onInsertConfirmationRequested;

  /// Agent 运行器工厂（open-core Phase B.1 SPI 切口）。
  ///
  /// 默认 [FreeChatRunner.new]——仅无工具流式对话（OSS 构建）；Pro 经
  /// [ProModule.createAgentRunner] 注入完整工具循环实现。本类不再 import
  /// lib/services/ai_agent_service.dart（OSS 构建 AOT tree-shake 该类）。
  final AiAgentFactory _agentFactory;

  /// Escape potentially dangerous characters in database identifiers and schema
  /// to prevent prompt injection attacks.
  static String _escapeForPrompt(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// 预载表结构上下文（sendUserMessage / resumeAgentTask 共用，C23 提取）：
  /// 库类型/当前库/表清单 + 用户提及表（否则前 3 张表）的 schema。
  /// 单表加载失败静默忽略；整体失败返回 null（对话继续，仅缺上下文）。
  Future<String?> _buildPreloadedContext({
    required DatabaseAdapter adapter,
    required String? selectedDatabase,
    required String userText,
    required String locale,
  }) async {
    try {
      final tables = await adapter.getTables();
      final buffer = StringBuffer();
      buffer.writeln('Database Type: ${adapter.databaseType.displayName}');
      buffer.writeln(
        'Current Database: ${_escapeForPrompt(selectedDatabase ?? 'Unknown')}',
      );
      buffer.writeln('Table Count: ${tables.length}');
      if (tables.isNotEmpty) {
        final escapedTables = tables.take(30).map(_escapeForPrompt).join(', ');
        buffer.writeln(
          'Table List: $escapedTables${tables.length > 30 ? '... and ${tables.length} tables total' : ''}',
        );
      }
      // Try to preload table schemas that user might mention
      final lowerText = userText.toLowerCase();
      final mentionedTables = tables
          .where((t) => lowerText.contains(t.toLowerCase()))
          .take(3)
          .toList();
      for (final table in mentionedTables) {
        try {
          final schema = await adapter.getAiSchemaSummary(
            target: table,
            databaseName: selectedDatabase,
            locale: locale,
          );
          buffer.writeln(
            '\n[Table Structure: ${_escapeForPrompt(table)}]\n${_escapeForPrompt(schema)}',
          );
        } catch (_) {
          // Ignore single table loading failure
        }
      }
      // Preload first 3 tables as general reference
      if (mentionedTables.isEmpty) {
        for (final table in tables.take(3)) {
          try {
            final schema = await adapter.getAiSchemaSummary(
              target: table,
              databaseName: selectedDatabase,
              locale: locale,
            );
            buffer.writeln(
              '\n[Table Structure: ${_escapeForPrompt(table)}]\n${_escapeForPrompt(schema)}',
            );
          } catch (_) {
            // Ignore single table loading failure
          }
        }
      }
      final result = buffer.toString();
      developer.log(
        '📋 Preloaded database context: ${result.length} chars',
        name: 'AiSessionOrchestrator',
      );
      return result;
    } catch (e) {
      developer.log(
        '⚠️ Failed to preload database context: $e',
        name: 'AiSessionOrchestrator',
      );
      return null;
    }
  }

  TaskProvider? _taskProvider;

  AiSessionOrchestrator({
    required AiSessionManager sessionManager,
    AiClient? aiClient,
    DatabaseService? dbService,
    TaskProvider? taskProvider,
    AiAgentFactory? agentFactory,
  }) : _sessionManager = sessionManager,
       _aiClient = aiClient ?? AiService().client,
       _dbService = dbService,
       _taskProvider = taskProvider,
       _agentFactory = agentFactory ?? FreeChatRunner.new {
    _sessionManager.addListener(_onSessionChange);
  }

  void updateTaskProvider(TaskProvider taskProvider) {
    _taskProvider = taskProvider;
  }

  void cancel() {
    _aiClient.cancel();
  }

  Stream<MessageDelta> get stateStream => _stateController.stream;

  SessionSnapshot get currentSnapshot {
    return SessionSnapshot(
      messages: _sessionManager.currentMessages,
      currentSession: _sessionManager.currentSession,
      bookmarks: _sessionManager.bookmarks,
    );
  }

  AiSessionManager get sessionManager => _sessionManager;

  void _onSessionChange() {
    if (!_stateController.isClosed) {
      _emitDelta(MessageDelta.clear());
      final messages = _sessionManager.currentMessages;
      for (final msg in messages) {
        _emitDelta(MessageDelta.add(msg));
      }
    }
  }

  /// 跨轮工具记忆保留的轮数（更早轮次的工具摘要被剥离，控制上下文体积）。
  static const int _retainedToolMemoryRounds = 3;

  /// 单条工具结果摘要的截断长度（会话里已截 2000，记忆再压到 400）。
  static const int _toolMemorySummaryChars = 400;

  /// 测试切口：直接驱动多轮历史组装（生产路径经 sendUserMessage 进入）。
  @visibleForTesting
  List<Map<String, dynamic>> buildPreviousHistoryForTesting(
    AiMessage currentUserMsg,
  ) => _buildPreviousHistory(currentUserMsg);

  /// 组装多轮对话历史。
  ///
  /// 此前仅保留 chat 消息，工具调用/结果在下一轮被整体过滤，Agent 每轮
  /// 从零探索（多轮越聊越糊涂的直接原因）。现把每轮 assistant 结论消息
  /// 之前累积的 toolCall/toolResult 压缩成自描述的紧凑文本摘要（工具名 +
  /// 精简参数 + 结果摘要），附到该轮 assistant 消息内容尾部——纯文本注入，
  /// 兼容所有 provider（不依赖原生 tool history）。
  /// 仅保留最近 [_retainedToolMemoryRounds] 轮的工具记忆。
  List<Map<String, dynamic>> _buildPreviousHistory(AiMessage currentUserMsg) {
    final entries = <_HistoryEntry>[];
    final pendingToolLines = <String>[];

    for (final m in _sessionManager.currentMessages) {
      if (m.id == currentUserMsg.id) continue;
      switch (m.type) {
        case AiMessageType.toolCall:
          final line = _summarizeToolCall(m);
          if (line != null) pendingToolLines.add(line);
        case AiMessageType.toolResult:
          final line = _summarizeToolResult(m);
          if (line != null) pendingToolLines.add(line);
        case AiMessageType.chat:
          if (m.isUser) {
            entries.add(_HistoryEntry(role: 'user', content: m.content));
          } else {
            var content = m.content;
            var toolMemory = '';
            if (pendingToolLines.isNotEmpty) {
              toolMemory =
                  '[Tools used earlier in this conversation round]\n'
                  '${pendingToolLines.join('\n')}';
              pendingToolLines.clear();
            }
            if (content.trim().isNotEmpty || toolMemory.isNotEmpty) {
              entries.add(
                _HistoryEntry(
                  role: 'assistant',
                  content: content.trim().isEmpty ? '(no text)' : content,
                  toolMemory: toolMemory.isEmpty ? null : toolMemory,
                ),
              );
            }
          }
      }
    }

    // 仅最近 N 个带工具记忆的轮次保留摘要，更早轮次剥离
    var budget = _retainedToolMemoryRounds;
    for (final e in entries.reversed) {
      if (e.toolMemory != null) {
        if (budget > 0) {
          budget--;
        } else {
          e.toolMemory = null;
        }
      }
    }

    return [
      for (final e in entries)
        {
          'role': e.role,
          'content': e.toolMemory == null
              ? e.content
              : '${e.content}\n\n${e.toolMemory}',
        },
    ];
  }

  /// toolCall 消息摘要：`- call 工具名(关键参数)`。
  String? _summarizeToolCall(AiMessage m) {
    final name = m.toolName;
    if (name == null || name.isEmpty) return null;
    return '- call $name(${_compactArgs(m.toolArguments)})';
  }

  /// toolResult 消息摘要：`- result 工具名: 摘要`（自描述，容忍并行执行
  /// 造成的 call/result 乱序交错）。
  String? _summarizeToolResult(AiMessage m) {
    final name = m.toolName ?? 'tool';
    final summary = m.toolResultSummary?.trim();
    if (summary == null || summary.isEmpty) return null;
    final short = summary.length > _toolMemorySummaryChars
        ? '${summary.substring(0, _toolMemorySummaryChars)}…'
        : summary;
    final flat = short.replaceAll(RegExp(r'\s+'), ' ');
    return '- result $name: $flat';
  }

  /// 工具参数的紧凑表示：最多 3 个键、单值截 60 字符。
  String _compactArgs(Map<String, dynamic>? args) {
    if (args == null || args.isEmpty) return '';
    final parts = args.entries.take(3).map((e) {
      var v = e.value.toString();
      if (v.length > 60) v = '${v.substring(0, 60)}…';
      return '${e.key}=$v';
    });
    return parts.join(', ');
  }

  void _emitDelta(MessageDelta delta) {
    if (!_stateController.isClosed) {
      _stateController.add(delta);
    }
  }

  Future<void> loadSession(String sessionId) async {
    _sessionManager.switchSession(sessionId);
  }

  Future<void> sendUserMessage({
    required String text,
    required DatabaseAdapter adapter,
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required Duration timeout,
    bool thinkingEnabled = false,
    String? selectedDatabase,
    int maxIterations = 30,
    int maxToolCalls = 20,
    int maxSqlExecutions = 10,
    String locale = 'en',

    /// Free/Pro 门禁：Free 纯对话（不给工具），Pro 允许 Agent 工具调用。
    bool allowTools = true,

    /// C23 上下文面板开关：是否预载表结构上下文（表清单 + 相关表 schema）。
    bool includeSchemaContext = true,

    /// C23 envelope 统一渲染：技能期望的结果载体类型名（AiSkillEnvelopeType.name；
    /// null = 不声明，渲染层走启发式）。盖章到本次助手回复消息。
    String? envelopeType,

    /// 是否由 orchestrator 入库用户消息。默认 true（历史行为）。
    /// ai_panel 的 _sendMessage 在校验前已自行入库（使 guard 失败时的错误消息
    /// 仍有前置用户消息，Regenerate 才能定位重发），故传 false 避免重复。
    bool recordUserMessage = true,
  }) async {
    if (_sessionManager.currentSession == null) {
      _sessionManager.createSession(locale: locale);
    }

    final userMsg = AiMessage(
      id: 'u_${DateTime.now().millisecondsSinceEpoch}',
      isUser: true,
      content: text,
      timestamp: DateTime.now(),
      type: AiMessageType.chat,
      status: AiMessageStatus.sent,
    );
    // 调用方已自行入库用户消息时跳过，避免重复（见 recordUserMessage 说明）
    if (recordUserMessage) {
      _sessionManager.addMessage(userMsg);
    }

    // Preload database context to reduce AI exploratory queries
    String? preloadedContext;
    if (includeSchemaContext) {
      preloadedContext = await _buildPreloadedContext(
        adapter: adapter,
        selectedDatabase: selectedDatabase,
        userText: text,
        locale: locale,
      );
    }

    // Create PromptBuilder and ResponseParser (if DatabaseService is available)
    AiPromptBuilder? promptBuilder;
    AiResponseParser? responseParser;
    if (_dbService != null) {
      promptBuilder = AiPromptFactory.createBuilder(
        type: adapter.databaseType,
        dbService: _dbService,
        locale: locale,
      );
      responseParser = AiParserFactory.createParser(
        type: adapter.databaseType,
        locale: locale,
      );
    }

    final agent = _agentFactory(
      adapter: adapter,
      aiClient: _aiClient,
      selectedDatabase: selectedDatabase,
      preloadedContext: preloadedContext,
      promptService: promptBuilder,
      responseParser: responseParser,
      locale: locale,
    );
    var currentAssistantId = '';
    String? pendingRequestId;
    String? currentCheckpointId;
    var partialContent = '';
    var partialReasoning = '';
    var hasStartedStreaming = false;
    var isFirstIteration = true;

    // Build previous conversation history for multi-turn context
    //（含跨轮工具记忆：见 _buildPreviousHistory 文档）
    final previousHistory = _buildPreviousHistory(userMsg);

    try {
      final result = await agent.run(
        userMessage: text,
        provider: provider,
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        timeout: timeout,
        thinkingEnabled: thinkingEnabled,
        previousHistory: previousHistory,
        maxIterations: maxIterations,
        maxToolCalls: maxToolCalls,
        allowTools: allowTools,
        onIterationStart: () {
          if (isFirstIteration) {
            currentAssistantId = 'a_${DateTime.now().millisecondsSinceEpoch}';
            partialContent = '';
            partialReasoning = '';
            hasStartedStreaming = false;
            isFirstIteration = false;
            AppLogger.d(
              'AiSessionOrchestrator',
              '🔄 onIterationStart: new currentAssistantId=$currentAssistantId',
            );
            final assistantMsg = AiMessage(
              id: currentAssistantId,
              isUser: false,
              content: '',
              reasoningContent: '',
              timestamp: DateTime.now(),
              isLoading: true,
              type: AiMessageType.chat,
              status: AiMessageStatus.streaming,
              envelopeType: envelopeType,
            );
            _sessionManager.addMessage(assistantMsg);
            AppLogger.d(
              'AiSessionOrchestrator',
              '   - Added assistant message to session',
            );
          }
        },
        onToolCall: (toolName, args) {
          final toolCallMsg = AiMessage(
            id: 'tc_${DateTime.now().millisecondsSinceEpoch}_$toolName',
            isUser: false,
            content: '',
            timestamp: DateTime.now(),
            type: AiMessageType.toolCall,
            toolName: toolName,
            toolArguments: args,
          );
          _sessionManager.addMessage(toolCallMsg);
        },
        onToolResult: (toolName, args, execResult) {
          // Check if this is a data generation tool result
          if (toolName == 'generate_test_data' &&
              execResult.structuredData != null &&
              execResult.structuredData!['toolType'] == 'data_generation') {
            final statements =
                (execResult.structuredData!['statements'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                [];
            final table = execResult.structuredData!['table'] as String? ?? '';
            final count = execResult.structuredData!['count'] as int? ?? 0;

            if (statements.isNotEmpty) {
              _pendingInsertStatements.addAll(statements);
              _pendingInsertTable = table;
              _pendingInsertCount += count;
            }
          }

          // Handle export task creation
          if (toolName == 'create_export_task' &&
              execResult.structuredData != null &&
              execResult.structuredData!['toolType'] == 'create_export_task') {
            final data = execResult.structuredData!;
            final table = data['table'] as String? ?? '';
            final formatStr = data['format'] as String? ?? 'csv';
            final outputPath = data['outputPath'] as String? ?? '';
            final whereClause = data['whereClause'] as String?;

            if (_taskProvider != null &&
                table.isNotEmpty &&
                outputPath.isNotEmpty) {
              // Get current connection info
              final connectionId = _dbService?.activeConnectionId;
              if (connectionId != null) {
                final format = ExportFormat.values.firstWhere(
                  (e) => e.name == formatStr.toLowerCase(),
                  orElse: () => ExportFormat.csv,
                );

                final config = ExportTaskConfig(
                  connectionId: connectionId,
                  description: AiServiceLocalizations(
                    locale,
                  ).exportTaskDescription(table, format.name.toUpperCase()),
                  tableName: table,
                  outputPath: outputPath,
                  format: format,
                  whereClause: whereClause,
                );

                final task = _taskProvider!.createTask(
                  type: TaskType.export,
                  config: config,
                  autoStart: true,
                );

                developer.log(
                  '📤 Export task created: ${task.id}',
                  name: 'AiSessionOrchestrator',
                );
              }
            }
          }

          final toolResultMsg = AiMessage(
            id: 'tr_${DateTime.now().millisecondsSinceEpoch}_$toolName',
            isUser: false,
            content: execResult.output,
            timestamp: DateTime.now(),
            type: AiMessageType.toolResult,
            toolName: toolName,
            toolResultSummary: execResult.output.length > 2000
                ? '${execResult.output.substring(0, 2000)}...(truncated)'
                : execResult.output,
          );
          _sessionManager.addMessage(toolResultMsg);
        },
        onStreamChunk: (chunk) {
          if (!hasStartedStreaming) {
            hasStartedStreaming = true;
            _sessionManager.updateMessage(currentAssistantId, isLoading: false);
          }
          if (chunk.type == 'reasoning') {
            partialReasoning += chunk.text;
            developer.log(
              '🧠 Received reasoning chunk: ${chunk.text.substring(0, chunk.text.length > 30 ? 30 : chunk.text.length)}..., totalLength=$partialReasoning.length',
              name: 'AiSessionOrchestrator',
            );
            _sessionManager.updateMessage(
              currentAssistantId,
              reasoningContent: partialReasoning,
            );
          } else {
            partialContent += chunk.text;
            _sessionManager.updateMessage(
              currentAssistantId,
              content: partialContent,
            );
          }
        },
        onCheckpoint: (checkpoint) {
          // Save checkpoint with session ID
          final sessionId = _sessionManager.currentSession?.id ?? '';
          final updatedCheckpoint = checkpoint.copyWith(sessionId: sessionId);
          _sessionManager.saveCheckpoint(updatedCheckpoint);
          currentCheckpointId = updatedCheckpoint.id;
          // Link checkpoint to the assistant message
          _sessionManager.updateMessage(
            currentAssistantId,
            checkpointId: currentCheckpointId,
          );
          developer.log(
            '💾 Checkpoint saved: ${updatedCheckpoint.id} at iteration ${updatedCheckpoint.currentIteration}',
            name: 'AiSessionOrchestrator',
          );
        },
      );

      // Debug logging
      AppLogger.d(
        'AiSessionOrchestrator',
        '📝 Final update START: targetMsgId=$currentAssistantId',
      );
      AppLogger.d(
        'AiSessionOrchestrator',
        '   - result.contentLength=${result.finalResponse.length}',
      );
      AppLogger.d(
        'AiSessionOrchestrator',
        '   - result.reasoningContent=${result.reasoningContent}',
      );
      AppLogger.d(
        'AiSessionOrchestrator',
        '   - result.reasoningLength=${result.reasoningContent?.length ?? 0}',
      );
      AppLogger.d(
        'AiSessionOrchestrator',
        '   - All message IDs in session: ${_sessionManager.currentMessages.map((m) => "${m.id.substring(0, m.id.length > 15 ? 15 : m.id.length)}...").toList()}',
      );
      AppLogger.d(
        'AiSessionOrchestrator',
        '   - Target message exists: ${_sessionManager.currentMessages.any((m) => m.id == currentAssistantId)}',
      );

      // Check if reasoningContent is null or empty
      if (result.reasoningContent == null || result.reasoningContent!.isEmpty) {
        AppLogger.w(
          'AiSessionOrchestrator',
          '⚠️ WARNING: result.reasoningContent is null or empty!',
        );
      }

      // Handle interrupted state (tool call limit reached)
      if (result.isInterrupted && result.checkpoint != null) {
        // Save checkpoint for continuation
        final sessionId = _sessionManager.currentSession?.id ?? '';
        final updatedCheckpoint = result.checkpoint!.copyWith(
          sessionId: sessionId,
        );
        _sessionManager.saveCheckpoint(updatedCheckpoint);
        currentCheckpointId = updatedCheckpoint.id;

        _sessionManager.updateMessage(
          currentAssistantId,
          content: result.finalResponse,
          reasoningContent: result.reasoningContent,
          isLoading: false,
          code: result.extractedCommand,
          extractedCommands: result.extractedCommands.isNotEmpty
              ? result.extractedCommands
              : null,
          isDangerous:
              result.securityCheck.riskLevel == CommandRiskLevel.dangerous,
          status: AiMessageStatus.interrupted,
          checkpointId: currentCheckpointId,
          promptTokens: result.tokenUsage?.promptTokens ?? 0,
          completionTokens: result.tokenUsage?.completionTokens ?? 0,
          totalTokens: result.tokenUsage?.totalTokens ?? 0,
        );
        developer.log(
          '⏸️ Task interrupted, checkpoint saved: $currentCheckpointId',
          name: 'AiSessionOrchestrator',
        );
      } else {
        // Clear checkpoint on success
        if (currentCheckpointId != null) {
          _sessionManager.deleteCheckpoint(currentCheckpointId!);
          currentCheckpointId = null;
        }

        _sessionManager.updateMessage(
          currentAssistantId,
          content: result.finalResponse,
          reasoningContent: result.reasoningContent,
          isLoading: false,
          code: result.extractedCommand,
          extractedCommands: result.extractedCommands.isNotEmpty
              ? result.extractedCommands
              : null,
          isDangerous:
              result.securityCheck.riskLevel == CommandRiskLevel.dangerous,
          status: AiMessageStatus.completed,
          checkpointId: null,
          promptTokens: result.tokenUsage?.promptTokens ?? 0,
          completionTokens: result.tokenUsage?.completionTokens ?? 0,
          totalTokens: result.tokenUsage?.totalTokens ?? 0,
        );
      }

      // Auto-analyze DDL statements in extracted commands
      await _analyzeDdlCommands(
        commands: result.extractedCommands,
        adapter: adapter,
        assistantId: currentAssistantId,
      );

      // Verify update
      final updatedMsg = _sessionManager.currentMessages.firstWhere(
        (m) => m.id == currentAssistantId,
        orElse: () => AiMessage(
          id: 'not_found',
          isUser: false,
          content: '',
          timestamp: DateTime.now(),
          type: AiMessageType.chat,
        ),
      );
      AppLogger.d(
        'AiSessionOrchestrator',
        '📝 Final update END: updatedMsg.reasoningLength=${updatedMsg.reasoningContent?.length ?? 0}, type=${updatedMsg.type}',
      );

      // Check if there are pending INSERT statements to execute
      if (_pendingInsertStatements.isNotEmpty) {
        final shouldExecute = await onInsertConfirmationRequested?.call(
          tableName: _pendingInsertTable ?? '',
          count: _pendingInsertCount,
          statements: _pendingInsertStatements,
        );

        if (shouldExecute == true) {
          // Execute the INSERT statements
          final executionService = InsertExecutionService(adapter: adapter);
          final result = await executionService.executeBatch(
            statements: _pendingInsertStatements,
          );

          // Add execution result as a system message
          final executionMsg = AiMessage(
            id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            content: result.toString(),
            timestamp: DateTime.now(),
            type: AiMessageType.chat,
            status: AiMessageStatus.completed,
          );
          _sessionManager.addMessage(executionMsg);

          // Clear pending statements
          _pendingInsertStatements.clear();
          _pendingInsertTable = null;
          _pendingInsertCount = 0;
        } else {
          // User cancelled - add cancellation message
          final cancelMsg = AiMessage(
            id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
            isUser: false,
            content: AiServiceLocalizations(locale).aiInsertExecutionCancelled,
            timestamp: DateTime.now(),
            type: AiMessageType.chat,
            status: AiMessageStatus.completed,
          );
          _sessionManager.addMessage(cancelMsg);

          _pendingInsertStatements.clear();
          _pendingInsertTable = null;
          _pendingInsertCount = 0;
        }
      }

      await _summarizeIfNeeded(
        provider: provider,
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        locale: locale,
      );
    } catch (e) {
      pendingRequestId = _aiClient.allPendingRequests.keys.lastOrNull;

      // Mark as interrupted instead of failed if we have a checkpoint
      final hasCheckpoint = currentCheckpointId != null;
      final status = hasCheckpoint
          ? AiMessageStatus.interrupted
          : AiMessageStatus.failed;
      final aiL10n = AiServiceLocalizations(locale);
      final errorMsg = hasCheckpoint
          ? aiL10n.taskInterruptedResumeHint('$e')
          : (pendingRequestId != null && partialContent.isNotEmpty
                ? aiL10n.errorPartialContentSaved('$e', pendingRequestId)
                : (e is TimeoutException
                      ? aiL10n.requestTimeout
                      : aiL10n.genericErrorOccurred('$e')));

      _sessionManager.updateMessage(
        currentAssistantId,
        content: errorMsg,
        isLoading: false,
        status: status,
        errorMessage: e.toString(),
      );
    } finally {
      _emitDelta(MessageDelta.clear());
      final messages = _sessionManager.currentMessages;
      AppLogger.d(
        'AiSessionOrchestrator',
        '📤 Finally block: sending ${messages.length} messages to UI',
      );
      for (final msg in messages) {
        AppLogger.d(
          'AiSessionOrchestrator',
          '   - msg[${msg.id.substring(0, msg.id.length > 10 ? 10 : msg.id.length)}]: type=${msg.type}, reasoning=${msg.reasoningContent?.length ?? 0}, content=${msg.content.length}',
        );
        _emitDelta(MessageDelta.add(msg));
      }
    }
  }

  Future<void> _summarizeIfNeeded({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    String locale = 'en',
  }) async {
    final session = _sessionManager.currentSession;
    if (session == null) return;
    final userMsgCount = session.userMessageCount + 1;

    _sessionManager.updateSessionMetadata(
      session.id,
      userMessageCount: userMsgCount,
    );

    if (userMsgCount % 5 != 0) return;

    final messages = _sessionManager.currentMessages;
    final summary = await AiContextBuilder.summarizeGoal(
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      messages: messages.where((m) => m.type == AiMessageType.chat).toList(),
      locale: locale,
    );

    if (summary != null && summary.isNotEmpty) {
      _sessionManager.updateSessionMetadata(
        session.id,
        goalSummary: summary,
        userMessageCount: userMsgCount,
        lastSummarizedAt: DateTime.now(),
      );
    }
  }

  Future<List<PendingRequest>> loadPendingRequests() async {
    return _aiClient.loadPendingRequests();
  }

  Future<void> retryPendingRequest({
    required String requestId,
    required String apiKey,
    required DatabaseAdapter adapter,
    String? selectedDatabase,
    bool allowTools = true,
  }) async {
    final pending = _aiClient.getPendingRequest(requestId);
    if (pending == null) {
      throw Exception('Pending request not found: $requestId');
    }

    await sendUserMessage(
      text: pending.message,
      adapter: adapter,
      provider: pending.provider,
      model: pending.model,
      apiKey: apiKey,
      baseUrl: pending.baseUrl,
      timeout: pending.timeout,
      thinkingEnabled: pending.thinkingEnabled,
      selectedDatabase: selectedDatabase,
      allowTools: allowTools,
    );

    await _aiClient.clearPendingRequest(requestId);
  }

  /// Resume an interrupted agent task from a checkpoint.
  Future<void> resumeAgentTask({
    required String messageId,
    required DatabaseAdapter adapter,
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required Duration timeout,
    bool thinkingEnabled = false,
    String? selectedDatabase,
    String locale = 'en',

    /// Free/Pro 门禁：Free 纯对话（不给工具），Pro 允许 Agent 工具调用。
    bool allowTools = true,

    /// C23 上下文面板开关：是否预载表结构上下文（表清单 + 相关表 schema）。
    bool includeSchemaContext = true,
  }) async {
    // Find the message
    final messages = _sessionManager.currentMessages;
    final message = messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => throw Exception('Message not found: $messageId'),
    );

    if (message.checkpointId == null) {
      throw Exception('No recoverable checkpoint for this message');
    }

    final checkpoint = _sessionManager.getCheckpoint(message.checkpointId!);
    if (checkpoint == null) {
      throw Exception('Checkpoint expired or does not exist');
    }

    // Preload database context
    String? preloadedContext;
    if (includeSchemaContext) {
      preloadedContext = await _buildPreloadedContext(
        adapter: adapter,
        selectedDatabase: selectedDatabase,
        userText: checkpoint.userMessage,
        locale: locale,
      );
    }

    AiPromptBuilder? promptBuilder;
    AiResponseParser? responseParser;
    if (_dbService != null) {
      promptBuilder = AiPromptFactory.createBuilder(
        type: adapter.databaseType,
        dbService: _dbService,
        locale: locale,
      );
      responseParser = AiParserFactory.createParser(
        type: adapter.databaseType,
        locale: locale,
      );
    }

    final agent = _agentFactory(
      adapter: adapter,
      aiClient: _aiClient,
      selectedDatabase: selectedDatabase,
      preloadedContext: preloadedContext,
      promptService: promptBuilder,
      responseParser: responseParser,
      locale: locale,
    );
    var currentAssistantId = messageId;
    String? currentCheckpointId;
    var partialContent = message.content;
    var partialReasoning = message.reasoningContent ?? '';
    var isFirstIteration = true;

    // Update message status to streaming
    _sessionManager.updateMessage(
      currentAssistantId,
      status: AiMessageStatus.streaming,
      isLoading: true,
    );

    try {
      final result = await agent.run(
        userMessage: checkpoint.userMessage,
        provider: checkpoint.provider,
        model: checkpoint.model,
        apiKey: apiKey,
        baseUrl: checkpoint.baseUrl,
        timeout: timeout,
        thinkingEnabled: checkpoint.thinkingEnabled,
        resumeFrom: checkpoint,
        allowTools: allowTools,
        onIterationStart: () {
          if (isFirstIteration) {
            isFirstIteration = false;
            _sessionManager.updateMessage(currentAssistantId, isLoading: false);
          }
        },
        onToolCall: (toolName, args) {
          final toolCallMsg = AiMessage(
            id: 'tc_${DateTime.now().millisecondsSinceEpoch}_$toolName',
            isUser: false,
            content: '',
            timestamp: DateTime.now(),
            type: AiMessageType.toolCall,
            toolName: toolName,
            toolArguments: args,
          );
          _sessionManager.addMessage(toolCallMsg);
        },
        onToolResult: (toolName, args, execResult) {
          final toolResultMsg = AiMessage(
            id: 'tr_${DateTime.now().millisecondsSinceEpoch}_$toolName',
            isUser: false,
            content: execResult.output,
            timestamp: DateTime.now(),
            type: AiMessageType.toolResult,
            toolName: toolName,
            toolResultSummary: execResult.output.length > 2000
                ? '${execResult.output.substring(0, 2000)}...(truncated)'
                : execResult.output,
            toolResultData: execResult.structuredData,
          );
          _sessionManager.addMessage(toolResultMsg);
        },
        onStreamChunk: (chunk) {
          if (chunk.type == 'reasoning') {
            partialReasoning += chunk.text;
            _sessionManager.updateMessage(
              currentAssistantId,
              reasoningContent: partialReasoning,
            );
          } else {
            partialContent += chunk.text;
            _sessionManager.updateMessage(
              currentAssistantId,
              content: partialContent,
            );
          }
        },
        onCheckpoint: (newCheckpoint) {
          final sessionId = _sessionManager.currentSession?.id ?? '';
          final updatedCheckpoint = newCheckpoint.copyWith(
            sessionId: sessionId,
            isResumed: true,
          );
          _sessionManager.saveCheckpoint(updatedCheckpoint);
          currentCheckpointId = updatedCheckpoint.id;
          _sessionManager.updateMessage(
            currentAssistantId,
            checkpointId: currentCheckpointId,
          );
        },
      );

      // Clear checkpoint on success
      if (currentCheckpointId != null) {
        _sessionManager.deleteCheckpoint(currentCheckpointId!);
      }
      if (message.checkpointId != null) {
        _sessionManager.deleteCheckpoint(message.checkpointId!);
      }

      _sessionManager.updateMessage(
        currentAssistantId,
        content: result.finalResponse,
        reasoningContent: result.reasoningContent,
        isLoading: false,
        code: result.extractedCommand,
        extractedCommands: result.extractedCommands.isNotEmpty
            ? result.extractedCommands
            : null,
        isDangerous:
            result.securityCheck.riskLevel == CommandRiskLevel.dangerous,
        status: AiMessageStatus.completed,
        checkpointId: null,
      );

      await _summarizeIfNeeded(
        provider: provider,
        model: model,
        apiKey: apiKey,
        baseUrl: baseUrl,
        locale: locale,
      );
    } catch (e) {
      final hasCheckpoint = currentCheckpointId != null;
      final status = hasCheckpoint
          ? AiMessageStatus.interrupted
          : AiMessageStatus.failed;
      final aiL10n = AiServiceLocalizations(locale);
      final errorMsg = hasCheckpoint
          ? aiL10n.resumeInterruptedAgain('$e')
          : (e is TimeoutException
                ? aiL10n.requestTimeout
                : aiL10n.resumeFailed('$e'));

      _sessionManager.updateMessage(
        currentAssistantId,
        content: errorMsg,
        isLoading: false,
        status: status,
        errorMessage: e.toString(),
      );
    } finally {
      _emitDelta(MessageDelta.clear());
      final updatedMessages = _sessionManager.currentMessages;
      for (final msg in updatedMessages) {
        _emitDelta(MessageDelta.add(msg));
      }
    }
  }

  /// Auto-analyze DDL commands and add impact analysis messages
  Future<void> _analyzeDdlCommands({
    required List<String> commands,
    required DatabaseAdapter adapter,
    required String assistantId,
  }) async {
    if (commands.isEmpty) return;

    final ddlCommands = commands
        .where(QueryExecutionInterceptor.isDdlStatement)
        .toList();
    if (ddlCommands.isEmpty) return;

    developer.log(
      'Auto-analyzing ${ddlCommands.length} DDL command(s)',
      name: 'AiSessionOrchestrator',
    );

    bool hasHighRisk = false;

    for (final ddl in ddlCommands) {
      try {
        final report = await SchemaAnalyzer.analyzeDdl(
          ddlStatement: ddl,
          databaseType: adapter.databaseType.name,
          executeQuery: (sql) async {
            final result = await adapter.executeQuery(sql);
            return result.rows;
          },
          // B5：补 getServerVersion 让锁语义推断生效（此前锁字段恒 unknown，
          // AI 给用户看的危险评级与执行门不一致）。
          getServerVersion: () async {
            final v = await adapter.getServerVersion();
            return v?['version'] as String?;
          },
        );

        final aiFormattedReport = SchemaAnalyzer.formatReportForAI(report);

        // Create tool result message for impact analysis
        final impactMsg = AiMessage(
          id: 'tr_${DateTime.now().millisecondsSinceEpoch}_impact',
          isUser: false,
          content: aiFormattedReport,
          timestamp: DateTime.now(),
          type: AiMessageType.toolResult,
          toolName: 'analyze_schema_impact',
          toolResultSummary:
              '${report.ddlType} on ${report.targetTable} - ${report.riskLevel.displayName}',
          toolResultData: {
            'ddlType': report.ddlType,
            'targetTable': report.targetTable,
            'riskLevel': report.riskLevel.name,
            'affectedObjects': report.affectedObjects
                .map((o) => o.toJson())
                .toList(),
            'dependencies': report.dependencies.map((d) => d.toJson()).toList(),
            'rollbackScript': report.rollbackScript?.toJson(),
            'warnings': report.warnings,
            'recommendations': report.recommendations,
            'requiresConfirmation': report.requiresConfirmation,
            'hasDataLossRisk': report.hasDataLossRisk,
            'toolType': 'analyze_schema_impact',
          },
        );
        _sessionManager.addMessage(impactMsg);

        if (report.riskLevel.isHighOrAbove) {
          hasHighRisk = true;
        }

        developer.log(
          'DDL analysis complete: ${report.ddlType} on ${report.targetTable} (${report.riskLevel.name})',
          name: 'AiSessionOrchestrator',
        );
      } catch (e) {
        developer.log(
          'Failed to auto-analyze DDL: $e',
          name: 'AiSessionOrchestrator',
        );
        // Continue with other DDL commands even if one fails
      }
    }

    // Mark assistant message as dangerous if any HIGH/CRITICAL risk
    if (hasHighRisk) {
      _sessionManager.updateMessage(assistantId, isDangerous: true);
      developer.log(
        'Marked assistant message as dangerous due to high-risk DDL',
        name: 'AiSessionOrchestrator',
      );
    }
  }

  void dispose() {
    _sessionManager.removeListener(_onSessionChange);
    _stateController.close();
  }
}

/// _buildPreviousHistory 的中间条目：content 为消息正文，toolMemory 为
/// 该轮工具探索摘要（第二遍按轮数预算决定是否保留）。
class _HistoryEntry {
  final String role;
  final String content;
  String? toolMemory;

  _HistoryEntry({required this.role, required this.content, this.toolMemory});
}
