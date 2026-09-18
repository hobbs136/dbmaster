import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:dbmaster/utils/app_logger.dart';
import 'dart:developer' as developer;
import 'package:dbmaster/services/ai/ai_service_localizations.dart';
import 'package:dbmaster/models/agent_checkpoint.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/models/database_models.dart' show ForeignKey;
import 'package:dbmaster/services/ai/readonly_sql_validator.dart';
// 调用 Mongo/Redis 专属方法时按类型分流（research D2）。
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'package:dbmaster/services/adapters/redis_gateway_adapter.dart'
    show RedisAdapter;
import 'package:dbmaster/pro/ai/database_tool_registry.dart';
import 'package:dbmaster/services/ai_service.dart';
import 'package:dbmaster/services/ai/prompt_builders/ai_prompt_builder.dart';
import 'package:dbmaster/services/ai/response_parsers/ai_response_parser.dart';
import 'package:dbmaster/services/ai_agent_runner.dart';
import 'package:dbmaster/pro/data_import/data_generation_service.dart';
import 'package:dbmaster/pro/data_import/file_analyzer.dart';
import 'package:dbmaster/pro/data_import/smart_import_service.dart';
import 'package:dbmaster/services/query_optimizer/query_optimizer_service.dart';
import 'package:dbmaster/services/query_history/query_history_service.dart';
import 'package:dbmaster/services/query_history/query_recommendation_engine.dart';
import 'package:dbmaster/services/schema_analyzer/schema_analyzer.dart';
import 'package:dbmaster/models/query_history/query_record.dart';
import 'package:dbmaster/pro/data_import/smart_import_models.dart';
import 'package:dbmaster/models/task_models.dart';

// AgentToolExecution / AgentRunResult 已迁至 lib/services/ai_agent_runner.dart
// （open-core Phase B.1 SPI 切口）——经此 import 维持本文件可编译；
// OSS 构建下本文件无任何可达引用，被 AOT tree-shake。

class _ToolCallResult {
  final String toolCallId;
  final String output;

  _ToolCallResult({required this.toolCallId, required this.output});
}

class AiAgentService implements AiAgentRunner {
  final DatabaseAdapter adapter;
  final AiClient _aiClient;
  final String? selectedDatabase;
  final String? preloadedContext;
  final AiPromptBuilder? _promptService;
  final AiResponseParser? _responseParser;
  final AiServiceLocalizations _l10n;

  // run_readonly_query 每 run（单条用户消息）调用上限，防失控循环。
  // 取值与 orchestrator 的 maxSqlExecutions 默认值（10）对齐。
  int _readonlyQueryCount = 0;
  static const int _maxReadonlyQueriesPerRun = 10;

  // Current AI provider settings (set during run)
  String _currentProvider = '';
  String _currentModel = '';
  String _currentApiKey = '';
  String? _currentBaseUrl;

  AiAgentService({
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

  // 重复检测：记录最近工具调用签名
  final Set<String> _recentToolSignatures = <String>{};
  String? _cachedSystemPrompt;

  /// 获取当前数据库类型的标识符引用符
  String get _quoteChar {
    switch (adapter.databaseType) {
      case DatabaseType.mysql:
      case DatabaseType.clickhouse:
      case DatabaseType.doris:
      case DatabaseType.tdengine:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.starrocks:
      case DatabaseType.mariadb:
        return '`';
      case DatabaseType.postgresql:
      case DatabaseType.sqlite:
        return '"';
      case DatabaseType.sqlserver:
        return '[';
      case DatabaseType.mongodb:
      case DatabaseType.redis:
        return '';
    }
  }

  /// 安全引用标识符（处理 SQL Server 方括号等不对称引号）
  String _quoteIdentifier(String name) {
    switch (adapter.databaseType) {
      case DatabaseType.sqlserver:
        return '[$name]';
      default:
        final q = _quoteChar;
        return '$q$name$q';
    }
  }

  /// 获取当前数据库类型的自增语法
  String _autoIncrementSyntax(String type) {
    switch (adapter.databaseType) {
      case DatabaseType.mysql:
      case DatabaseType.clickhouse:
      case DatabaseType.tdengine:
      case DatabaseType.oceanbase:
      case DatabaseType.tidb:
      case DatabaseType.mariadb:
        return '$type PRIMARY KEY AUTO_INCREMENT';
      case DatabaseType.doris:
        // Doris 不支持 MySQL 式 AUTO_INCREMENT 放在列定义中；
        // 自增能力由键模型（DUPLICATE/UNIQUE/AGGREGATE/PK）保证。
        return '$type PRIMARY KEY';
      case DatabaseType.starrocks:
        // StarRocks DUPLICATE 表无主键/AUTO_INCREMENT（自增列需建表期
        // 属性），薄适配面不做方言特化——裸类型即可。
        return type;
      case DatabaseType.postgresql:
        // PostgreSQL 使用 SERIAL 类型
        if (type.toUpperCase().contains('BIGINT')) {
          return 'BIGSERIAL PRIMARY KEY';
        }
        return 'SERIAL PRIMARY KEY';
      case DatabaseType.sqlite:
        return '$type PRIMARY KEY AUTOINCREMENT';
      case DatabaseType.sqlserver:
        return '$type PRIMARY KEY IDENTITY(1,1)';
      case DatabaseType.mongodb:
      case DatabaseType.redis:
        return '$type PRIMARY KEY';
    }
  }

  /// Detect and sanitize potential prompt injection attempts in user input.
  /// Returns sanitized text and logs warning if injection patterns detected.
  static String _sanitizeUserInput(String input) {
    // Patterns that attempt to override system instructions
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
      RegExp(r'\u003csystem\u003e', caseSensitive: false),
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
      developer.log(
        '⚠️ Potential prompt injection detected and sanitized',
        name: 'AiAgentService',
      );
    }

    return sanitized;
  }

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
        // 导致 C23「Schema 上下文开关」在 Pro 主路径失效——这里补回。
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

    /// Free/Pro 门禁：Free 用户纯对话（不给工具），Pro 才允许工具调用。
    /// 默认 true 保持既有调用方行为；门禁入口必须显式传 isPro。
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
    // Store current AI provider settings for tool execution
    _currentProvider = provider;
    _currentModel = model;
    _currentApiKey = apiKey;
    _currentBaseUrl = baseUrl;

    final history = <Map<String, dynamic>>[];
    final toolExecutions = <AgentToolExecution>[];
    final tools = DatabaseToolRegistry.getToolsFor(adapter.databaseType);
    final useTools =
        allowTools &&
        IAiClient.supportsToolCalling(provider) &&
        tools.isNotEmpty;
    // Accumulate reasoning across iterations
    String? accumulatedReasoning;
    // Accumulate token usage across iterations
    TokenUsage accumulatedUsage = const TokenUsage();
    // 迭代计数器
    var toolCallCount = 0;
    // Start iteration
    var startIteration = 0;

    // If resuming from checkpoint, restore state
    if (resumeFrom != null) {
      history.addAll(resumeFrom.history);
      for (final te in resumeFrom.toolExecutions) {
        toolExecutions.add(
          AgentToolExecution(
            toolName: te['toolName'] as String,
            arguments: te['arguments'] as Map<String, dynamic>,
            result: AiExecutionResult(
              success: te['resultSuccess'] as bool,
              output: te['resultOutput'] as String,
            ),
          ),
        );
      }
      accumulatedReasoning = resumeFrom.accumulatedReasoning;
      toolCallCount = resumeFrom.toolCallCount;
      startIteration = resumeFrom.currentIteration;
      developer.log(
        '🔄 Resuming from checkpoint at iteration $startIteration',
        name: 'AiAgentService',
      );
    } else {
      if (previousHistory != null && previousHistory.isNotEmpty) {
        history.addAll(previousHistory);
      }
      final sanitizedMessage = _sanitizeUserInput(userMessage);
      history.add({'role': 'user', 'content': sanitizedMessage});
    }

    for (int i = startIteration; i < maxIterations; i++) {
      developer.log(
        '🔄 Agent iteration ${i + 1}/$maxIterations (tools: $toolCallCount/$maxToolCalls)',
        name: 'AiAgentService',
      );
      onIterationStart?.call();

      late final String finalResponse;
      late final String? reasoningContent;
      late final ChatResponse? chatResponse;

      if (!useTools) {
        // Streaming mode for providers without tool support
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
        finalResponse = buffer.toString();
        reasoningContent = reasoningBuffer.isNotEmpty
            ? reasoningBuffer.toString()
            : null;
        // Accumulate reasoning from each iteration
        if (reasoningContent != null && reasoningContent.isNotEmpty) {
          accumulatedReasoning = (accumulatedReasoning?.isNotEmpty == true)
              ? '$accumulatedReasoning\n\n$reasoningContent'
              : reasoningContent;
        }
        chatResponse = null;
        // Streaming mode: no usage data available
      } else {
        final systemPrompt = await _getSystemPrompt();
        chatResponse = await _aiClient.chat(
          provider: provider,
          model: model,
          apiKey: apiKey,
          baseUrl: baseUrl,
          message: '',
          systemPrompt: systemPrompt,
          history: history,
          timeout: timeout,
          tools: tools,
          thinkingEnabled: thinkingEnabled,
        );
        finalResponse = chatResponse.content ?? '';
        reasoningContent = chatResponse.reasoningContent;
        if (chatResponse.usage != null) {
          accumulatedUsage += chatResponse.usage!;
        }
        if (reasoningContent != null && reasoningContent.isNotEmpty) {
          onStreamChunk?.call(
            AiStreamChunk(type: 'reasoning', text: reasoningContent),
          );
        }
        if (reasoningContent != null && reasoningContent.isNotEmpty) {
          accumulatedReasoning = (accumulatedReasoning?.isNotEmpty == true)
              ? '$accumulatedReasoning\n\n$reasoningContent'
              : reasoningContent;
          AppLogger.d(
            'AiAgent',
            '🧠 Accumulated reasoning: length=${accumulatedReasoning.length}',
          );
        }
      }

      // Handle tool calls (only for providers that support them)
      if (chatResponse != null && chatResponse.hasToolCalls) {
        // Check tool call limit
        if (toolCallCount >= maxToolCalls) {
          developer.log(
            '⛔ Tool call limit reached ($maxToolCalls), terminating iteration',
            name: 'AiAgentService',
          );
          // Create checkpoint for continuation
          final checkpoint = AgentCheckpoint(
            id: 'cp_${DateTime.now().millisecondsSinceEpoch}',
            sessionId: '', // Will be set by orchestrator
            userMessage: userMessage,
            history: List.from(history),
            toolExecutions: toolExecutions
                .map(
                  (e) => {
                    'toolName': e.toolName,
                    'arguments': e.arguments,
                    'resultSuccess': e.result.success,
                    'resultOutput': e.result.output,
                  },
                )
                .toList(),
            accumulatedReasoning: accumulatedReasoning,
            toolCallCount: toolCallCount,
            currentIteration: i + 1,
            provider: provider,
            model: model,
            baseUrl: baseUrl,
            thinkingEnabled: thinkingEnabled,
            createdAt: DateTime.now(),
          );
          return AgentRunResult(
            finalResponse:
                '${finalResponse.isNotEmpty ? '$finalResponse\n\n' : ''}⚠️ ${_l10n.toolCallLimitReached(maxToolCalls)}',
            extractedCommand: null,
            reasoningContent: accumulatedReasoning,
            securityCheck: SecurityCheckResult.ok,
            toolExecutions: toolExecutions,
            tokenUsage: accumulatedUsage,
            isInterrupted: true,
            checkpoint: checkpoint,
          );
        }

        AppLogger.d(
          'AiAgent',
          '🔧 Tool calling detected: reasoningLength=${reasoningContent?.length ?? 0}',
        );
        final assistantEntry = <String, dynamic>{
          'role': 'assistant',
          'content': chatResponse.content ?? '',
          'tool_calls': chatResponse.toolCalls.map((t) => t.toJson()).toList(),
        };
        if (reasoningContent != null && reasoningContent.isNotEmpty) {
          assistantEntry['reasoning_content'] = reasoningContent;
        }
        history.add(assistantEntry);

        // Detect and filter duplicate tool calls
        final uniqueToolCalls = <AiToolCall>[];
        final redundantToolIds = <String>{};
        for (final toolCall in chatResponse.toolCalls) {
          final args = _parseToolArguments(toolCall.functionArguments);
          final signature = '${toolCall.functionName}:${jsonEncode(args)}';
          if (_recentToolSignatures.contains(signature)) {
            developer.log(
              '🔄 Duplicate tool call detected: $signature',
              name: 'AiAgentService',
            );
            redundantToolIds.add(toolCall.id);
          } else {
            _recentToolSignatures.add(signature);
            if (_recentToolSignatures.length > 10) {
              _recentToolSignatures.remove(_recentToolSignatures.first);
            }
            uniqueToolCalls.add(toolCall);
          }
        }

        // 并行执行所有非重复工具调用
        final toolResults = await Future.wait(
          uniqueToolCalls.map((toolCall) async {
            final args = _parseToolArguments(toolCall.functionArguments);
            onToolCall?.call(toolCall.functionName, args);
            final result = await _executeTool(toolCall.functionName, args);
            onToolResult?.call(toolCall.functionName, args, result);
            toolExecutions.add(
              AgentToolExecution(
                toolName: toolCall.functionName,
                arguments: args,
                result: result,
              ),
            );
            return _ToolCallResult(
              toolCallId: toolCall.id,
              output: result.output,
            );
          }),
        );

        // 添加正常工具结果到历史
        for (final tr in toolResults) {
          history.add({
            'role': 'tool',
            'tool_call_id': tr.toolCallId,
            'content': tr.output,
          });
        }

        // 为重复的工具调用添加提示
        for (final toolCall in chatResponse.toolCalls) {
          if (redundantToolIds.contains(toolCall.id)) {
            history.add({
              'role': 'tool',
              'tool_call_id': toolCall.id,
              'content': _l10n.duplicateQuery,
            });
          }
        }

        toolCallCount += uniqueToolCalls.length;

        // Save checkpoint after tool execution
        onCheckpoint?.call(
          AgentCheckpoint(
            id: 'cp_${DateTime.now().millisecondsSinceEpoch}',
            sessionId: '', // Will be set by orchestrator
            userMessage: userMessage,
            history: List.from(history),
            toolExecutions: toolExecutions
                .map(
                  (e) => {
                    'toolName': e.toolName,
                    'arguments': e.arguments,
                    'resultSuccess': e.result.success,
                    'resultOutput': e.result.output,
                  },
                )
                .toList(),
            accumulatedReasoning: accumulatedReasoning,
            toolCallCount: toolCallCount,
            currentIteration: i + 1,
            provider: provider,
            model: model,
            baseUrl: baseUrl,
            thinkingEnabled: thinkingEnabled,
            createdAt: DateTime.now(),
          ),
        );

        continue;
      }

      // 优先从 <sql> 标签提取可执行语句（新的语句生成助手格式）
      final extractedCommands =
          _responseParser?.extractExecutableStatements(finalResponse) ?? [];

      if (extractedCommands.isNotEmpty) {
        // 有 <sql> 标签时不自动执行，让用户手动操作
        final firstCommand = extractedCommands.first;
        final security = adapter.validateCommand(firstCommand);

        AppLogger.d(
          'AiAgent',
          '✅ Returning AgentRunResult with ${extractedCommands.length} SQL statements',
        );
        return AgentRunResult(
          finalResponse: finalResponse,
          extractedCommand: firstCommand,
          extractedCommands: extractedCommands,
          reasoningContent: accumulatedReasoning,
          securityCheck: security,
          toolExecutions: toolExecutions,
          tokenUsage: accumulatedUsage,
        );
      }

      final security = SecurityCheckResult.ok;

      AppLogger.d(
        'AiAgent',
        '✅ Returning AgentRunResult: contentLength=${finalResponse.length}, reasoningLength=${accumulatedReasoning?.length ?? 0}',
      );
      return AgentRunResult(
        finalResponse: finalResponse,
        reasoningContent: accumulatedReasoning,
        securityCheck: security,
        toolExecutions: toolExecutions,
        tokenUsage: accumulatedUsage,
      );
    }

    throw Exception(_l10n.maxIterationsReached);
  }

  Map<String, dynamic> _parseToolArguments(String raw) {
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// 测试切口：直接驱动工具分发（生产路径经 run() 的 agent 循环进入）。
  @visibleForTesting
  Future<AiExecutionResult> executeToolForTesting(
    String name,
    Map<String, dynamic> args,
  ) => _executeTool(name, args);

  Future<AiExecutionResult> _executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      // Ensure we're operating on the selected database before executing any tool
      if (selectedDatabase != null && selectedDatabase!.isNotEmpty) {
        try {
          await adapter.useDatabase(selectedDatabase!);
        } catch (e) {
          developer.log(
            '⚠️ Failed to switch to database $selectedDatabase: $e',
            name: 'AiAgentService',
          );
        }
      }

      switch (name) {
        case 'get_table_schema':
          final table = args['table'] as String? ?? '';
          return AiExecutionResult.success(
            await adapter.getAiSchemaSummary(
              target: table,
              databaseName: selectedDatabase,
              locale: _l10n.locale,
            ),
          );
        case 'list_tables':
          final tables = await adapter.getTables();
          return AiExecutionResult.success(tables.join('\n'));
        case 'get_table_relationships':
          // 双向外键关系：删除/更新影响分析的第一入口（谁引用我 / 我引用谁）。
          final table = args['table'] as String? ?? '';
          if (table.isEmpty) {
            return AiExecutionResult.failure(_l10n.tableNameRequired);
          }
          try {
            final outgoing = await adapter.getForeignKeys(table);
            final incoming = await adapter.getReferencingForeignKeys(table);
            return AiExecutionResult.success(
              _formatTableRelationships(table, outgoing, incoming),
            );
          } catch (e) {
            return AiExecutionResult.failure(
              _l10n.toolExecutionFailed(e.toString()),
            );
          }
        case 'run_readonly_query':
          // 通用只读探索：白名单校验 → 每 run 计数 → 截断回传。
          final sql = args['sql'] as String? ?? '';
          final check = ReadonlySqlValidator.validate(
            sql,
            isSqlite: adapter.databaseType == DatabaseType.sqlite,
          );
          if (!check.allowed) {
            return AiExecutionResult.failure(
              'Rejected by read-only guard: ${check.reason}',
            );
          }
          if (_readonlyQueryCount >= _maxReadonlyQueriesPerRun) {
            return AiExecutionResult.failure(
              'Read-only query limit for this turn reached '
              '($_maxReadonlyQueriesPerRun). Continue with information you '
              'already have.',
            );
          }
          _readonlyQueryCount++;
          try {
            final result = await adapter.executeQuery(sql);
            return AiExecutionResult.success(_formatTruncatedRows(result));
          } catch (e) {
            return AiExecutionResult.failure(
              _l10n.toolExecutionFailed(e.toString()),
            );
          }
        case 'explain_query':
          final sql = args['sql'] as String? ?? '';
          final result = await adapter.getExplainPlan(sql);
          return AiExecutionResult.success(_formatQueryResult(result));
        case 'get_database_summary':
          return AiExecutionResult.success(
            await adapter.getAiSchemaSummary(
              databaseName: selectedDatabase,
              locale: _l10n.locale,
            ),
          );
        case 'list_super_tables':
          final result = await adapter.executeAiCommand(
            'SHOW STABLES',
            locale: _l10n.locale,
          );
          return result;
        case 'get_super_table_schema':
          final table = args['table'] as String? ?? '';
          final result = await adapter.executeAiCommand(
            'DESCRIBE $table',
            locale: _l10n.locale,
          );
          return result;
        case 'list_collections':
          final tables = await adapter.getTables();
          return AiExecutionResult.success(tables.join('\n'));
        case 'get_collection_schema':
          final collection = args['collection'] as String? ?? '';
          return AiExecutionResult.success(
            await adapter.getAiSchemaSummary(
              target: collection,
              databaseName: selectedDatabase,
              locale: _l10n.locale,
            ),
          );
        // Mongo 写/运维工具分发（research D8/D9/D10）。
        // 关键：analyze_export_mongo 走原生 stats+抽样，绝不复用 SQL 的 SELECT COUNT(*)（FR-009）。
        case 'import_documents_mongo':
          final collection = args['collection'] as String? ?? '';
          final docs = args['documents'] as List<dynamic>? ?? [];
          if (collection.isEmpty) {
            return AiExecutionResult.failure(_l10n.collectionNameRequired);
          }
          if (adapter is! MongoDBAdapter) {
            return AiExecutionResult.failure(_l10n.mongoOnlyAvailable);
          }
          final typedDocs = docs
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
          if (typedDocs.isEmpty) {
            return AiExecutionResult.failure(_l10n.mongoNoValidDocuments);
          }
          final ok = await (adapter as MongoDBAdapter).importDocuments(
            collection,
            typedDocs,
          );
          return AiExecutionResult.success(
            ok
                ? _l10n.mongoDocumentsImported(typedDocs.length, collection)
                : _l10n.mongoImportFailed,
          );
        case 'generate_test_data_mongo':
          final collection = args['collection'] as String? ?? '';
          var count = (args['count'] as num?)?.toInt() ?? 10;
          if (collection.isEmpty) {
            return AiExecutionResult.failure(_l10n.collectionNameRequired);
          }
          if (adapter is! MongoDBAdapter) {
            return AiExecutionResult.failure(_l10n.mongoOnlyAvailable);
          }
          if (count > 1000) count = 1000;
          if (count < 1) count = 1;
          final inserted = await (adapter as MongoDBAdapter).generateTestData(
            collection,
            count,
          );
          return AiExecutionResult.success(
            inserted > 0
                ? _l10n.mongoTestDataGenerated(inserted, collection)
                : _l10n.mongoTestDataEmpty,
          );
        case 'export_collection_mongo':
          final collection = args['collection'] as String? ?? '';
          final format = (args['format'] as String? ?? 'json').toLowerCase();
          final limit = (args['limit'] as num?)?.toInt();
          final filter = args['filter'] is Map
              ? Map<String, dynamic>.from(args['filter'] as Map)
              : null;
          if (collection.isEmpty) {
            return AiExecutionResult.failure(_l10n.collectionNameRequired);
          }
          if (adapter is! MongoDBAdapter) {
            return AiExecutionResult.failure(_l10n.mongoOnlyAvailable);
          }
          final output = await (adapter as MongoDBAdapter).exportCollection(
            collection,
            filter: filter,
            limit: limit,
            format: format,
          );
          return AiExecutionResult.success(
            _l10n.mongoExportCollectionResult(collection, format, output),
          );
        case 'analyze_export_mongo':
          final collection = args['collection'] as String? ?? '';
          final sampleLimit = (args['sample_limit'] as num?)?.toInt() ?? 3;
          if (collection.isEmpty) {
            return AiExecutionResult.failure(_l10n.collectionNameRequired);
          }
          if (adapter is! MongoDBAdapter) {
            return AiExecutionResult.failure(_l10n.mongoOnlyAvailable);
          }
          final analysis = await (adapter as MongoDBAdapter).analyzeExport(
            collection,
            sampleLimit: sampleLimit,
          );
          return AiExecutionResult.success(
            const JsonEncoder.withIndent('  ').convert(analysis),
          );
        case 'analyze_data_quality_mongo':
          final collection = args['collection'] as String? ?? '';
          if (collection.isEmpty) {
            return AiExecutionResult.failure(_l10n.collectionNameRequired);
          }
          if (adapter is! MongoDBAdapter) {
            return AiExecutionResult.failure(_l10n.mongoOnlyAvailable);
          }
          final reports = await (adapter as MongoDBAdapter).analyzeDataQuality(
            collection,
          );
          final buffer = StringBuffer();
          buffer.writeln(_l10n.mongoDataQualityReportTitle(collection));
          buffer.writeln();
          for (final r in reports) {
            if (r.containsKey('note')) {
              buffer.writeln(r['note']);
            } else {
              buffer.writeln(
                _l10n.mongoDataQualityFieldRow(
                  '${r['field']}',
                  '${r['type']}',
                  '${r['completeness']}',
                  '${r['missing']}',
                  r['sampled'] as int,
                ),
              );
            }
          }
          return AiExecutionResult.success(buffer.toString().trimRight());
        case 'get_keyspace_summary':
          return AiExecutionResult.success(
            await adapter.getAiSchemaSummary(
              databaseName: selectedDatabase,
              locale: _l10n.locale,
            ),
          );
        case 'find_documents_mongo':
          // Mongo 通用只读探索：find 语义经 aggregate($match/$limit/$project)
          // 组装（管道由本 handler 构造，模型无法注入 $out/$merge 等写阶段）。
          final collection = args['collection'] as String? ?? '';
          if (collection.isEmpty) {
            return AiExecutionResult.failure(_l10n.collectionNameRequired);
          }
          if (adapter is! MongoDBAdapter) {
            return AiExecutionResult.failure(_l10n.mongoOnlyAvailable);
          }
          final filter = _asJsonMap(args['filter']);
          final projection = _asJsonMap(args['projection']);
          var limit = (args['limit'] as num?)?.toInt() ?? 20;
          if (limit < 1) limit = 1;
          if (limit > 50) limit = 50;
          try {
            final mongo = adapter as MongoDBAdapter;
            final pipeline = <Map<String, dynamic>>[
              if (filter.isNotEmpty) {'\$match': filter},
              {'\$limit': limit},
              if (projection.isNotEmpty) {'\$project': projection},
            ];
            final result = await mongo.aggregate(collection, pipeline);
            final count = await mongo.countDocuments(
              collection,
              filter: filter.isEmpty ? null : filter,
            );
            return AiExecutionResult.success(
              'Total matching documents: $count\n\n${_formatTruncatedRows(result)}',
            );
          } catch (e) {
            return AiExecutionResult.failure(
              _l10n.toolExecutionFailed(e.toString()),
            );
          }
        case 'scan_keys':
          if (adapter is! RedisAdapter) {
            return AiExecutionResult.failure(_l10n.redisOnlyAvailable);
          }
          final pattern = args['pattern'] as String? ?? '*';
          var limit = (args['limit'] as num?)?.toInt() ?? 100;
          if (limit < 1) limit = 1;
          if (limit > 1000) limit = 1000;
          try {
            final keys = await (adapter as RedisAdapter).getAllKeys(
              pattern: pattern,
              limit: limit,
            );
            return AiExecutionResult.success(
              keys.isEmpty ? 'No keys matched "$pattern"' : keys.join('\n'),
            );
          } catch (e) {
            return AiExecutionResult.failure(
              _l10n.toolExecutionFailed(e.toString()),
            );
          }
        case 'get_key':
          final key = args['key'] as String? ?? '';
          if (key.isEmpty) {
            return AiExecutionResult.failure(_l10n.keyNameRequired);
          }
          if (adapter is! RedisAdapter) {
            return AiExecutionResult.failure(_l10n.redisOnlyAvailable);
          }
          try {
            final redis = adapter as RedisAdapter;
            final type = await redis.getKeyType(key);
            final ttl = await redis.getTTL(key);
            if (type == 'none') {
              return AiExecutionResult.success(
                jsonEncode({'key': key, 'exists': false}),
              );
            }
            final value = await _redisValuePreview(redis, key, type);
            return AiExecutionResult.success(
              jsonEncode({
                'key': key,
                'type': type,
                'ttl_seconds': ttl,
                'value': value,
              }),
            );
          } catch (e) {
            return AiExecutionResult.failure(
              _l10n.toolExecutionFailed(e.toString()),
            );
          }
        case 'generate_test_data':
          final table = args['table'] as String? ?? '';
          var count = (args['count'] as num?)?.toInt() ?? 10;
          final locale = args['locale'] as String?;
          final realisticMode = args['realistic_mode'] as bool? ?? true;
          final autoExecute = args['auto_execute'] as bool? ?? false;

          // Support larger batches (up to 1000)
          if (count > 1000) count = 1000;
          if (count < 1) count = 1;

          final dataService = DataGenerationService(
            adapter: adapter,
            locale: locale ?? 'en',
          );

          // Generate data
          final rows = await dataService.generateTestData(
            tableName: table,
            count: count,
            locale: locale,
            useRealisticData: realisticMode,
          );

          if (autoExecute) {
            // Direct execution
            final execResult = await dataService.executeInsert(
              tableName: table,
              rows: rows,
              batchSize: 1000,
            );

            final buffer = StringBuffer();
            buffer.writeln(_l10n.testDataGeneratedExecutedTitle);
            buffer.writeln();
            buffer.writeln(_l10n.toolResultLabelTable(table));
            buffer.writeln(_l10n.toolResultLabelRows(count));
            buffer.writeln(_l10n.toolResultLabelLocale(locale ?? 'en'));
            buffer.writeln(_l10n.toolResultLabelMode(realisticMode));
            buffer.writeln();
            buffer.writeln(_l10n.toolResultLabelResult(execResult.message));
            if (execResult.errors.isNotEmpty) {
              buffer.writeln(_l10n.toolResultLabelErrors);
              for (final error in execResult.errors.take(5)) {
                buffer.writeln('- $error');
              }
            }

            return AiExecutionResult.success(
              buffer.toString(),
              data: {
                'table': table,
                'count': count,
                'insertedRows': execResult.insertedRows,
                'failedRows': execResult.failedRows,
                'success': execResult.success,
                'toolType': 'data_generation',
                'autoExecuted': true,
              },
            );
          } else {
            // Return SQL statements (legacy mode)
            final sqlStatements = dataService.buildInsertSql(
              tableName: table,
              rows: rows,
            );

            final buffer = StringBuffer();
            buffer.writeln(_l10n.dataGenerated(table, count));
            buffer.writeln('\n${_l10n.insertStatementsGenerated}');
            buffer.writeln('---');
            for (final sql in sqlStatements) {
              buffer.writeln(sql);
            }
            buffer.writeln('---');
            buffer.writeln('\n${_l10n.executionNote}');
            buffer.writeln(_l10n.continueGeneratingNote);

            return AiExecutionResult.success(
              buffer.toString(),
              data: {
                'table': table,
                'count': count,
                'statements': sqlStatements,
                'toolType': 'data_generation',
                'autoExecuted': false,
              },
            );
          }
        case 'get_table_row_count':
          final table = args['table'] as String? ?? '';
          final count = await adapter.getTableRowCount(table);
          return AiExecutionResult.success(
            _l10n.tableRowCount(table, count),
            data: {'table': table, 'rowCount': count},
          );
        case 'smart_import':
          final filePath = args['file_path'] as String? ?? '';
          final targetTable = args['target_table'] as String?;

          if (filePath.isEmpty) {
            return AiExecutionResult.failure(_l10n.filePathRequired);
          }

          // Analyze file
          final analysis = await FileAnalyzer.analyzeFile(filePath);
          if (!analysis.success) {
            return AiExecutionResult.failure(
              _l10n.fileAnalysisFailed(
                analysis.errorMessage ?? 'Unknown error',
              ),
            );
          }

          // Infer table name
          final suggestedTable = targetTable ?? _suggestTableName(analysis);

          // Check if table exists
          final tables = await adapter.getTables();
          final tableExists = tables.any(
            (t) => t.toLowerCase() == suggestedTable.toLowerCase(),
          );

          int existingRowCount = 0;
          if (tableExists) {
            existingRowCount = await adapter.getTableRowCount(suggestedTable);
          }

          // Build result
          final buffer = StringBuffer();
          buffer.writeln(_l10n.smartImportTitle);
          buffer.writeln(_l10n.smartImportFile(analysis.fileName));
          buffer.writeln(
            _l10n.smartImportFormat(analysis.format.name.toUpperCase()),
          );
          buffer.writeln(_l10n.smartImportEncoding(analysis.encoding));
          if (analysis.delimiter != null) {
            buffer.writeln(_l10n.smartImportDelimiter(analysis.delimiter!));
          }
          buffer.writeln(_l10n.smartImportFieldCount(analysis.fields.length));
          buffer.writeln(
            _l10n.smartImportSampleRows(analysis.sampleData.length),
          );
          if (analysis.estimatedTotalRows != null) {
            buffer.writeln(
              _l10n.smartImportEstimatedRows(analysis.estimatedTotalRows),
            );
          }
          buffer.writeln('');

          buffer.writeln(_l10n.smartImportFields);
          for (final field in analysis.fields) {
            final type = analysis.inferredTypes[field] ?? 'TEXT';
            buffer.writeln(_l10n.smartImportField(field, type));
          }
          buffer.writeln('');

          buffer.writeln(_l10n.smartImportSampleData);
          final sampleJson = const JsonEncoder.withIndent(
            '  ',
          ).convert(analysis.sampleData.take(3).toList());
          buffer.writeln(sampleJson);
          buffer.writeln('');

          buffer.writeln(_l10n.smartImportTargetTable);
          buffer.writeln(_l10n.smartImportSuggestedTableName(suggestedTable));
          if (tableExists) {
            buffer.writeln(_l10n.smartImportTableExists);
            buffer.writeln(_l10n.smartImportExistingRows(existingRowCount));
            if (existingRowCount > 0) {
              buffer.writeln('');
              buffer.writeln(
                _l10n.smartImportDataDuplicateWarning(existingRowCount),
              );
              buffer.writeln(_l10n.smartImportOptionOverwrite);
              buffer.writeln(_l10n.smartImportOptionAppend);
              buffer.writeln(_l10n.smartImportOptionCancel);
            }
          } else {
            buffer.writeln(_l10n.smartImportTableNotExists);
          }
          buffer.writeln('');

          buffer.writeln(_l10n.smartImportSuggestedSQL);
          buffer.writeln(_l10n.smartImportSuggestedSQLNote);
          buffer.writeln('');
          buffer.writeln(_buildCreateTableSQL(suggestedTable, analysis));
          buffer.writeln('');
          buffer.writeln(_l10n.smartImportExecuteNote);
          if (analysis.estimatedTotalRows != null &&
              analysis.estimatedTotalRows! > 1000) {
            buffer.writeln(_l10n.smartImportLargeFileNote);
          }

          return AiExecutionResult.success(
            buffer.toString(),
            data: {
              'filePath': filePath,
              'tableName': suggestedTable,
              'tableExists': tableExists,
              'existingRowCount': existingRowCount,
              'analysis': {
                'format': analysis.format.name,
                'encoding': analysis.encoding,
                'delimiter': analysis.delimiter,
                'fields': analysis.fields,
                'inferredTypes': analysis.inferredTypes,
                'sampleData': analysis.sampleData,
                'estimatedTotalRows': analysis.estimatedTotalRows,
              },
              'toolType': 'smart_import',
            },
          );
        case 'analyze_export':
          final table = args['table'] as String? ?? '';
          final whereClause = args['where_clause'] as String?;

          if (table.isEmpty) {
            return AiExecutionResult.failure(_l10n.tableNameRequired);
          }

          // Check if table exists
          final tables = await adapter.getTables();
          final tableExists = tables.any(
            (t) => t.toLowerCase() == table.toLowerCase(),
          );

          if (!tableExists) {
            return AiExecutionResult.failure(_l10n.tableDoesNotExist(table));
          }

          // Get table schema
          final schema = await adapter.getAiSchemaSummary(
            target: table,
            databaseName: selectedDatabase,
            locale: _l10n.locale,
          );

          // Get row count
          var countSql =
              'SELECT COUNT(*) as count FROM ${_quoteIdentifier(table)}';
          if (whereClause != null && whereClause.isNotEmpty) {
            countSql += ' WHERE $whereClause';
          }
          final countResult = await adapter.executeQuery(countSql);
          final rowCount = countResult.rows.isNotEmpty
              ? (countResult.rows.first['count'] as int? ?? 0)
              : 0;

          // Get sample data
          var sampleSql = 'SELECT * FROM ${_quoteIdentifier(table)}';
          if (whereClause != null && whereClause.isNotEmpty) {
            sampleSql += ' WHERE $whereClause';
          }
          sampleSql += ' LIMIT 3';
          final sampleResult = await adapter.executeQuery(sampleSql);

          // Build result
          final buffer = StringBuffer();
          buffer.writeln(_l10n.exportAnalysisTitle(table));
          buffer.writeln();
          buffer.writeln(_l10n.exportAnalysisTotalRows(rowCount));
          if (whereClause != null && whereClause.isNotEmpty) {
            buffer.writeln('**Filter:** $whereClause');
          }
          buffer.writeln();
          buffer.writeln(_l10n.exportAnalysisTableSchemaLabel);
          buffer.writeln('```');
          buffer.writeln(schema);
          buffer.writeln('```');
          buffer.writeln();
          buffer.writeln(_l10n.exportAnalysisSampleDataLabel);
          buffer.writeln('```json');
          buffer.writeln(
            const JsonEncoder.withIndent('  ').convert(sampleResult.rows),
          );
          buffer.writeln('```');
          buffer.writeln();

          // Estimate file sizes
          final avgRowSize = sampleResult.rows.isNotEmpty
              ? const JsonEncoder().convert(sampleResult.rows.first).length
              : 100;
          final estimatedCsvSize = (avgRowSize * 0.7 * rowCount / 1024 / 1024)
              .toStringAsFixed(2);
          final estimatedJsonSize = (avgRowSize * 1.2 * rowCount / 1024 / 1024)
              .toStringAsFixed(2);

          buffer.writeln(_l10n.exportAnalysisEstimatedSizeLabel);
          buffer.writeln('- CSV format: ~${estimatedCsvSize}MB');
          buffer.writeln('- JSON format: ~${estimatedJsonSize}MB');
          buffer.writeln();

          if (rowCount > 100000) {
            buffer.writeln(_l10n.exportAnalysisLargeDatasetWarning(rowCount));
            buffer.writeln(_l10n.exportAnalysisBatchNote);
            buffer.writeln();
          }

          buffer.writeln(_l10n.exportAnalysisConfirmPrompt);
          buffer.writeln(_l10n.exportAnalysisConfirmFormatOption);
          buffer.writeln(_l10n.exportAnalysisConfirmOutputPath);
          buffer.writeln(_l10n.exportAnalysisConfirmRequirements);

          return AiExecutionResult.success(
            buffer.toString(),
            data: {
              'table': table,
              'rowCount': rowCount,
              'whereClause': whereClause,
              'schema': schema,
              'sampleData': sampleResult.rows,
              'estimatedCsvSize': estimatedCsvSize,
              'estimatedJsonSize': estimatedJsonSize,
              'toolType': 'analyze_export',
            },
          );
        case 'execute_import':
          final filePath = args['file_path'] as String? ?? '';
          final targetTable = args['target_table'] as String?;
          final conflictResolutionStr =
              args['conflict_resolution'] as String? ?? 'skip';

          if (filePath.isEmpty) {
            return AiExecutionResult.failure(_l10n.filePathRequired);
          }

          // Analyze file
          final analysis = await FileAnalyzer.analyzeFile(filePath);
          if (!analysis.success) {
            return AiExecutionResult.failure(
              _l10n.fileAnalysisFailed(
                analysis.errorMessage ?? 'Unknown error',
              ),
            );
          }

          final smartImport = SmartImportService(
            adapter: adapter,
            aiClient: _aiClient,
          );
          final tableName = targetTable ?? _suggestTableName(analysis);

          // Check if table exists
          final exists = await smartImport.tableExists(tableName);

          // Create table if not exists
          if (!exists) {
            final createResult = await smartImport.generateCreateTableSQL(
              analysis: analysis,
              provider: _currentProvider,
              model: _currentModel,
              apiKey: _currentApiKey,
              targetTable: tableName,
              baseUrl: _currentBaseUrl,
            );
            final createSQL = createResult['sql'] as String? ?? '';
            if (createSQL.isNotEmpty) {
              await smartImport.createTable(createSQL);
            }
          }

          // Parse conflict resolution
          final conflictResolution = ConflictResolution.values.firstWhere(
            (e) => e.name == conflictResolutionStr,
            orElse: () => ConflictResolution.skip,
          );

          // Execute import
          final importResult = await smartImport.importData(
            config: SmartImportConfig(filePath: filePath),
            analysis: analysis,
            tableName: tableName,
            conflictResolution: conflictResolution,
          );

          // Build result
          final buffer = StringBuffer();
          buffer.writeln(_l10n.importCompleteTitle);
          buffer.writeln();
          buffer.writeln(_l10n.importCompleteLabelTable(tableName));
          buffer.writeln(_l10n.importCompleteLabelFile(analysis.fileName));
          buffer.writeln(
            _l10n.importCompleteLabelTotalRows(
              importResult.importedRows + importResult.failedRows,
            ),
          );
          buffer.writeln(
            _l10n.importCompleteLabelImported(importResult.importedRows),
          );
          buffer.writeln(_l10n.importFailedLabel(importResult.failedRows));
          if (importResult.errorMessage != null) {
            buffer.writeln(_l10n.importErrorLabel(importResult.errorMessage!));
          }
          buffer.writeln();
          buffer.writeln(_l10n.importStatusLabel(importResult.success));

          return AiExecutionResult.success(
            buffer.toString(),
            data: {
              'tableName': tableName,
              'fileName': analysis.fileName,
              'importedRows': importResult.importedRows,
              'failedRows': importResult.failedRows,
              'success': importResult.success,
              'toolType': 'execute_import',
            },
          );
        case 'create_export_task':
          final table = args['table'] as String? ?? '';
          final format = args['format'] as String? ?? 'csv';
          final outputPath = args['output_path'] as String? ?? '';
          final whereClause = args['where_clause'] as String?;

          if (table.isEmpty) {
            return AiExecutionResult.failure(_l10n.tableNameRequired);
          }
          if (outputPath.isEmpty) {
            return AiExecutionResult.failure(_l10n.exportOutputPathRequired);
          }

          // Validate table exists
          final tables = await adapter.getTables();
          if (!tables.any((t) => t.toLowerCase() == table.toLowerCase())) {
            return AiExecutionResult.failure(_l10n.tableDoesNotExist(table));
          }

          // Parse format
          final exportFormat = ExportFormat.values.firstWhere(
            (e) => e.name == format.toLowerCase(),
            orElse: () => ExportFormat.csv,
          );

          // Return task configuration for orchestrator to create
          return AiExecutionResult.success(
            _l10n.exportTaskConfigCreated(
              table,
              exportFormat.name.toUpperCase(),
              outputPath,
            ),
            data: {
              'table': table,
              'format': exportFormat.name,
              'outputPath': outputPath,
              'whereClause': whereClause,
              'toolType': 'create_export_task',
            },
          );
        case 'analyze_query_performance':
          final query = args['query'] as String? ?? '';
          final databaseType = args['database_type'] as String? ?? 'mysql';

          if (query.isEmpty) {
            return AiExecutionResult.failure(_l10n.perfAnalysisQueryRequired);
          }

          try {
            // 1. Get EXPLAIN plan
            final explainResult = await adapter.getExplainPlan(query);

            if (explainResult.rows.isEmpty) {
              return AiExecutionResult.failure(_l10n.explainPlanUnavailable);
            }

            // 2. Analyze performance
            final report = QueryOptimizerService.analyzeQuery(
              rawExplainResults: explainResult.rows,
              originalQuery: query,
              databaseType: databaseType,
            );

            // 3. Format for AI
            final aiFormattedReport = QueryOptimizerService.formatReportForAI(
              report,
            );

            return AiExecutionResult.success(
              aiFormattedReport,
              data: {
                'executionPlan': report.executionPlan.toJson(),
                'bottlenecks': report.bottlenecks
                    .map((b) => b.toJson())
                    .toList(),
                'indexRecommendations': report.indexRecommendations
                    .map((r) => r.toJson())
                    .toList(),
                'queryRewrites': report.queryRewrites
                    .map((r) => r.toJson())
                    .toList(),
                'summary': report.summary,
                'highestSeverity': report.highestSeverity.name,
                'hasCriticalIssues': report.hasCriticalIssues,
                'totalEstimatedImprovement': report.totalEstimatedImprovement,
                'toolType': 'analyze_query_performance',
              },
            );
          } catch (e) {
            return AiExecutionResult.failure(
              _l10n.analyzeQueryPerformanceFailed(e.toString()),
            );
          }

        case 'analyze_data_quality':
          final filePath = args['file_path'] as String? ?? '';

          if (filePath.isEmpty) {
            return AiExecutionResult.failure(_l10n.filePathRequired);
          }

          // Analyze file
          final analysis = await FileAnalyzer.analyzeFile(filePath);
          if (!analysis.success) {
            return AiExecutionResult.failure(
              _l10n.fileAnalysisFailed(
                analysis.errorMessage ?? 'Unknown error',
              ),
            );
          }

          // Perform basic quality checks
          final qualityReport = _analyzeDataQuality(analysis);

          // Build result
          final buffer = StringBuffer();
          buffer.writeln(_l10n.dataQualityReportTitle);
          buffer.writeln();
          buffer.writeln(_l10n.importCompleteLabelFile(analysis.fileName));
          buffer.writeln(
            _l10n.dataQualityTotalRowsLabel(
              analysis.estimatedTotalRows ?? analysis.sampleData.length,
            ),
          );
          buffer.writeln(_l10n.dataQualityFieldsLabel(analysis.fields.length));
          buffer.writeln();

          if (qualityReport.issues.isEmpty) {
            buffer.writeln(_l10n.dataQualityNoIssuesDetected);
          } else {
            buffer.writeln(_l10n.dataQualityIssuesFoundLabel);
            for (final issue in qualityReport.issues) {
              buffer.writeln('- ${issue.description}');
            }
          }
          buffer.writeln();

          if (qualityReport.recommendations.isNotEmpty) {
            buffer.writeln(_l10n.dataQualityRecommendationsLabel);
            for (final rec in qualityReport.recommendations) {
              buffer.writeln('- $rec');
            }
          }

          return AiExecutionResult.success(
            buffer.toString(),
            data: {
              'fileName': analysis.fileName,
              'issues': qualityReport.issues.map((i) => i.toJson()).toList(),
              'recommendations': qualityReport.recommendations,
              'toolType': 'analyze_data_quality',
            },
          );
        case 'search_query_history':
          final keywords = args['keywords'] as String?;
          final tableFilter = args['table_filter'] as String?;
          final timeRange = args['time_range'] as String? ?? 'all';
          final limit = (args['limit'] as num?)?.toInt() ?? 10;

          // 解析时间范围
          DateTime? after;
          final now = DateTime.now();
          switch (timeRange) {
            case 'today':
              after = DateTime(now.year, now.month, now.day);
              break;
            case 'week':
              after = now.subtract(const Duration(days: 7));
              break;
            case 'month':
              after = now.subtract(const Duration(days: 30));
              break;
          }

          final historyService = QueryHistoryService();
          await historyService.initialize();

          final results = await historyService.search(
            SearchCriteria(
              keywords: keywords,
              tableFilter: tableFilter,
              after: after,
              limit: limit,
            ),
          );

          if (results.isEmpty) {
            return AiExecutionResult.success(
              _l10n.queryHistoryNoMatch,
              data: {'results': [], 'toolType': 'search_query_history'},
            );
          }

          final buffer = StringBuffer();
          buffer.writeln(_l10n.queryHistoryResultsTitle);
          buffer.writeln();
          buffer.writeln(_l10n.queryHistoryFoundCount(results.length));
          buffer.writeln();

          for (var i = 0; i < results.length; i++) {
            final record = results[i];
            buffer.writeln(
              '### ${i + 1}. ${record.queryType ?? record.detectedQueryType ?? _l10n.queryEntryDefaultType} - ${record.createdAt.toLocal().toString().substring(0, 16)}',
            );
            buffer.writeln('```sql');
            buffer.writeln(record.sqlStatement);
            buffer.writeln('```');
            buffer.writeln(
              _l10n.toolResultExecutionTimeLabel(
                record.executionTimeMs.toString(),
              ),
            );
            final rowCount = record.rowCount;
            if (rowCount != null) {
              buffer.writeln(_l10n.toolResultRowCountLabel(rowCount));
            }
            final databaseName = record.databaseName;
            if (databaseName != null) {
              buffer.writeln(_l10n.toolResultDatabaseLabel(databaseName));
            }
            if (record.tags.isNotEmpty) {
              buffer.writeln(
                _l10n.queryHistoryTagsLabel(record.tags.join(', ')),
              );
            }
            buffer.writeln();
          }

          return AiExecutionResult.success(
            buffer.toString(),
            data: {
              'results': results.map((r) => r.toMap()).toList(),
              'toolType': 'search_query_history',
            },
          );

        case 'recommend_similar_queries':
          final currentQuery = args['current_query'] as String? ?? '';
          final currentTable = args['current_table'] as String?;
          final limit = (args['limit'] as num?)?.toInt() ?? 5;

          final historyService = QueryHistoryService();
          await historyService.initialize();
          final recommendationEngine = QueryRecommendationEngine(
            historyService,
          );

          List<QueryRecommendation> recommendations;

          if (currentQuery.isNotEmpty) {
            recommendations = await recommendationEngine
                .recommendSimilarQueries(
                  currentQuery: currentQuery,
                  currentTable: currentTable,
                  limit: limit,
                );
          } else if (currentTable != null) {
            recommendations = await recommendationEngine.recommendForTable(
              tableName: currentTable,
              limit: limit,
            );
          } else {
            return AiExecutionResult.failure(
              _l10n.recommendRequiresQueryOrTable,
            );
          }

          if (recommendations.isEmpty) {
            return AiExecutionResult.success(
              _l10n.noSimilarQueriesFound,
              data: {
                'recommendations': [],
                'toolType': 'recommend_similar_queries',
              },
            );
          }

          final buffer = StringBuffer();
          buffer.writeln(_l10n.similarQueryRecommendationsTitle);
          buffer.writeln();

          for (var i = 0; i < recommendations.length; i++) {
            final rec = recommendations[i];
            buffer.writeln(
              _l10n.similarQueryEntryHeader(
                '${i + 1}',
                rec.record.queryType ??
                    rec.record.detectedQueryType ??
                    _l10n.queryEntryDefaultType,
                (rec.similarity * 100).toStringAsFixed(0),
              ),
            );
            buffer.writeln(_l10n.similarQueryLabelReason(rec.reason));
            buffer.writeln('```sql');
            buffer.writeln(rec.record.sqlStatement);
            buffer.writeln('```');
            buffer.writeln(
              _l10n.similarQueryLabelLastExecuted(
                rec.record.createdAt.toLocal().toString().substring(0, 16),
              ),
            );
            buffer.writeln(
              _l10n.toolResultExecutionTimeLabel(
                rec.record.executionTimeMs.toString(),
              ),
            );
            final recRowCount = rec.record.rowCount;
            if (recRowCount != null) {
              buffer.writeln(_l10n.toolResultRowCountLabel(recRowCount));
            }
            buffer.writeln();
          }

          return AiExecutionResult.success(
            buffer.toString(),
            data: {
              'recommendations': recommendations
                  .map(
                    (r) => {
                      'record': r.record.toMap(),
                      'similarity': r.similarity,
                      'reason': r.reason,
                    },
                  )
                  .toList(),
              'toolType': 'recommend_similar_queries',
            },
          );

        case 'analyze_schema_impact':
          final ddlStatement = args['ddl_statement'] as String? ?? '';
          final databaseType = args['database_type'] as String? ?? 'mysql';

          if (ddlStatement.isEmpty) {
            return AiExecutionResult.failure(_l10n.ddlStatementRequired);
          }

          try {
            final report = await SchemaAnalyzer.analyzeDdl(
              ddlStatement: ddlStatement,
              databaseType: databaseType,
              executeQuery: (sql) async {
                final result = await adapter.executeQuery(sql);
                return result.rows;
              },
              // B5：补 getServerVersion 让锁语义推断生效（此前锁字段恒 unknown，
              // AI 给用户看的危险评级不准）。与 query_editor 执行门对齐。
              getServerVersion: () async {
                final v = await adapter.getServerVersion();
                return v?['version'] as String?;
              },
            );

            final aiFormattedReport = SchemaAnalyzer.formatReportForAI(report);

            return AiExecutionResult.success(
              aiFormattedReport,
              data: {
                'ddlType': report.ddlType,
                'targetTable': report.targetTable,
                'riskLevel': report.riskLevel.name,
                'affectedObjects': report.affectedObjects
                    .map((o) => o.toJson())
                    .toList(),
                'dependencies': report.dependencies
                    .map((d) => d.toJson())
                    .toList(),
                'rollbackScript': report.rollbackScript?.toJson(),
                'warnings': report.warnings,
                'recommendations': report.recommendations,
                'requiresConfirmation': report.requiresConfirmation,
                'hasDataLossRisk': report.hasDataLossRisk,
                'toolType': 'analyze_schema_impact',
              },
            );
          } catch (e) {
            return AiExecutionResult.failure(
              _l10n.analyzeSchemaImpactFailed(e.toString()),
            );
          }

        default:
          return AiExecutionResult.failure(_l10n.unknownTool(name));
      }
    } catch (e) {
      return AiExecutionResult.failure(_l10n.toolExecutionFailed(e.toString()));
    }
  }

  String _formatQueryResult(QueryResult result) {
    if (result.rows.isEmpty) {
      return result.message ?? _l10n.affectedRows(result.affectedRows ?? 0);
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(result.rows);
    } catch (_) {
      return result.rows.toString();
    }
  }

  /// run_readonly_query 的结果截断：最多 [_maxReadonlyRows] 行、单元格
  /// [_maxReadonlyCellChars] 字符、总输出 [_maxReadonlyOutputChars] 字符，
  /// 超限附 truncation 说明，防撑爆模型上下文。
  String _formatTruncatedRows(QueryResult result) {
    if (result.rows.isEmpty) {
      return result.message ?? 'OK (0 rows)';
    }
    final total = result.rows.length;
    final shown = total > _maxReadonlyRows
        ? result.rows.take(_maxReadonlyRows).toList()
        : result.rows;
    final trimmed = shown.map((row) {
      final r = <String, dynamic>{};
      row.forEach((k, v) {
        final s = v?.toString() ?? 'NULL';
        r[k] = s.length > _maxReadonlyCellChars
            ? '${s.substring(0, _maxReadonlyCellChars)}…(+${s.length - _maxReadonlyCellChars} chars)'
            : s;
      });
      return r;
    }).toList();

    var output = const JsonEncoder.withIndent('  ').convert(trimmed);
    if (output.length > _maxReadonlyOutputChars) {
      output =
          '${output.substring(0, _maxReadonlyOutputChars)}\n... (output truncated)';
    }
    if (total > _maxReadonlyRows) {
      output += '\n(truncated: showing $_maxReadonlyRows of $total rows)';
    }
    return output;
  }

  static const int _maxReadonlyRows = 50;
  static const int _maxReadonlyCellChars = 200;
  static const int _maxReadonlyOutputChars = 8000;

  /// 工具参数里的 JSON object 安全转 `Map<String, dynamic>`（模型可能传
  /// `Map<dynamic, dynamic>` 或非对象，统一归一）。
  Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  /// get_key 工具的按类型取值预览（全部走只读命令）。
  Future<Object> _redisValuePreview(
    RedisAdapter redis,
    String key,
    String type,
  ) async {
    switch (type.toLowerCase()) {
      case 'string':
        return await redis.getString(key) ?? '';
      case 'hash':
        return await redis.getHashPreview(key, maxFields: 20);
      case 'list':
        return await redis.getListPreview(key, maxElements: 20);
      case 'set':
        return await redis.getSetPreview(key, maxMembers: 20);
      case 'zset':
        return await redis.getZSetPreview(key, maxItems: 20);
      default:
        return '(preview not supported for type $type)';
    }
  }

  /// get_table_relationships 工具的结果格式化：双向外键关系的紧凑 JSON。
  /// incoming_references 是删除/更新 [table] 行前必须先处理（或依赖其
  /// on_delete 动作）的子表。
  String _formatTableRelationships(
    String table,
    List<ForeignKey> outgoing,
    List<ForeignKey> incoming,
  ) {
    Map<String, dynamic> fkJson(ForeignKey fk) => {
      'column': fk.column,
      'references': '${fk.referencedTable}.${fk.referencedColumn}',
      if (fk.onDelete != null && fk.onDelete!.isNotEmpty)
        'on_delete': fk.onDelete,
    };

    return jsonEncode({
      'table': table,
      'outgoing_foreign_keys': outgoing.map(fkJson).toList(),
      'incoming_references': incoming
          .map(
            (fk) => ({
              'table': fk.table,
              'column': fk.column,
              'references': '${fk.referencedTable}.${fk.referencedColumn}',
              if (fk.onDelete != null && fk.onDelete!.isNotEmpty)
                'on_delete': fk.onDelete,
            }),
          )
          .toList(),
      'note':
          'Rows in incoming_references tables must be handled BEFORE '
          'deleting/updating "$table" rows, unless their on_delete action '
          '(e.g. CASCADE / SET NULL) already covers it.',
    });
  }

  /// 建议表名
  String _suggestTableName(FileAnalysisResult analysis) {
    final fileName = analysis.fileName.split('.').first;
    final cleanName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return cleanName.isEmpty ? 'imported_data' : cleanName;
  }

  /// 构建 CREATE TABLE 语句
  String _buildCreateTableSQL(String tableName, FileAnalysisResult analysis) {
    final buffer = StringBuffer();
    buffer.writeln(
      'CREATE TABLE IF NOT EXISTS ${_quoteIdentifier(tableName)} (',
    );

    final columnDefs = <String>[];
    for (final field in analysis.fields) {
      final type = analysis.inferredTypes[field] ?? 'TEXT';
      columnDefs.add('  ${_quoteIdentifier(field)} $type');
    }

    // 如果有 ID 列，设为 PRIMARY KEY
    final idField = analysis.fields.firstWhere(
      (f) => f.toLowerCase() == 'id',
      orElse: () => '',
    );
    if (idField.isNotEmpty) {
      final idx = analysis.fields.indexOf(idField);
      final type = analysis.inferredTypes[idField] ?? 'BIGINT';
      columnDefs[idx] =
          '  ${_quoteIdentifier(idField)} ${_autoIncrementSyntax(type)}';
    }

    buffer.writeln(columnDefs.join(',\n'));
    buffer.writeln(');');

    return buffer.toString();
  }

  /// Analyze data quality of a file
  DataQualityReport _analyzeDataQuality(FileAnalysisResult analysis) {
    final issues = <DataQualityIssue>[];
    final recommendations = <String>[];

    // Check for empty values
    for (final field in analysis.fields) {
      int emptyCount = 0;
      for (final row in analysis.sampleData) {
        final value = row[field];
        if (value == null || value.toString().trim().isEmpty) {
          emptyCount++;
        }
      }
      if (emptyCount > 0) {
        final percentageInt = (emptyCount / analysis.sampleData.length * 100)
            .round();
        issues.add(
          DataQualityIssue(
            type: 'missing_values',
            field: field,
            description: _l10n.dqIssueMissingValues(
              field,
              emptyCount,
              percentageInt,
            ),
            severity: emptyCount > analysis.sampleData.length * 0.5
                ? 'high'
                : 'medium',
          ),
        );
        recommendations.add(_l10n.dqRecFillEmptyValues(field));
      }
    }

    // Check for whitespace issues
    for (final field in analysis.fields) {
      int whitespaceCount = 0;
      for (final row in analysis.sampleData) {
        final value = row[field]?.toString() ?? '';
        if (value != value.trim()) {
          whitespaceCount++;
        }
      }
      if (whitespaceCount > 0) {
        issues.add(
          DataQualityIssue(
            type: 'whitespace',
            field: field,
            description: _l10n.dqIssueWhitespace(field, whitespaceCount),
            severity: 'low',
          ),
        );
        recommendations.add(_l10n.dqRecTrimWhitespace(field));
      }
    }

    // Check for duplicate rows (based on all fields)
    final seenRows = <String>{};
    int duplicateCount = 0;
    for (final row in analysis.sampleData) {
      final rowKey = analysis.fields
          .map((f) => row[f]?.toString() ?? '')
          .join('|');
      if (seenRows.contains(rowKey)) {
        duplicateCount++;
      } else {
        seenRows.add(rowKey);
      }
    }
    if (duplicateCount > 0) {
      issues.add(
        DataQualityIssue(
          type: 'duplicates',
          field: null,
          description: _l10n.dqIssueDuplicates(duplicateCount),
          severity: 'medium',
        ),
      );
      recommendations.add(_l10n.dqRecRemoveDuplicates);
    }

    // Check for inconsistent date formats
    for (final field in analysis.fields) {
      if (analysis.inferredTypes[field]?.toUpperCase().contains('DATE') ??
          false) {
        final datePatterns = <String>{};
        for (final row in analysis.sampleData) {
          final value = row[field]?.toString() ?? '';
          if (value.isNotEmpty) {
            if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value)) {
              datePatterns.add('YYYY-MM-DD');
            } else if (RegExp(r'^\d{2}/\d{2}/\d{4}').hasMatch(value)) {
              datePatterns.add('MM/DD/YYYY');
            } else if (RegExp(r'^\d{2}-\d{2}-\d{4}').hasMatch(value)) {
              datePatterns.add('DD-MM-YYYY');
            }
          }
        }
        if (datePatterns.length > 1) {
          issues.add(
            DataQualityIssue(
              type: 'inconsistent_format',
              field: field,
              description: _l10n.dqIssueInconsistentDateFormats(
                field,
                datePatterns.join(', '),
              ),
              severity: 'medium',
            ),
          );
          recommendations.add(_l10n.dqRecStandardizeDateFormat(field));
        }
      }
    }

    return DataQualityReport(issues: issues, recommendations: recommendations);
  }
}

/// Data quality issue
class DataQualityIssue {
  final String type;
  final String? field;
  final String description;
  final String severity;

  DataQualityIssue({
    required this.type,
    this.field,
    required this.description,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'field': field,
    'description': description,
    'severity': severity,
  };
}

/// Data quality report
class DataQualityReport {
  final List<DataQualityIssue> issues;
  final List<String> recommendations;

  DataQualityReport({required this.issues, required this.recommendations});
}

/// Helper interface for TDengine-specific tools.
/// Actual TDengine adapter should implement these via extension or mixin.
abstract class TDengineAdapterHelper {
  Future<List<String>> getSuperTables();
  Future<String> getSuperTableInfo(String tableName);
}
