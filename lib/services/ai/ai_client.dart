import 'dart:convert';
import 'dart:io' show HttpClient, File, Directory;
import 'package:http/http.dart' show Request, Response, Client;
import 'package:http/io_client.dart' show IOClient;
import 'dart:async';
import 'dart:developer' as developer;
import 'package:path_provider/path_provider.dart';
import '../../models/ai_models.dart';
import 'anthropic_converter.dart';

abstract class IAiClient {
  Future<ChatResponse> chat({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout,
    String? promptCacheKey,
    List<Map<String, dynamic>>? tools,
    bool thinkingEnabled,
  });

  Stream<String> chatStream({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout,
    String? promptCacheKey,
    bool thinkingEnabled,
  });

  Stream<AiStreamChunk> chatStreamWithReasoning({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout,
    String? promptCacheKey,
    bool thinkingEnabled,
    String? pendingRequestId,
  });

  Future<List<PendingRequest>> loadPendingRequests();
  PendingRequest? getPendingRequest(String requestId);
  Map<String, PendingRequest> get allPendingRequests;
  Stream<AiStreamChunk> retryFromPending({
    required String requestId,
    required String apiKey,
  });
  Future<void> clearPendingRequest(String requestId);
  Future<void> clearAllPendingRequests();
  void cancel();
  void dispose();
  bool get isRunning;

  Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  });

  static bool supportsToolCalling(String provider) {
    // 补 'Kimi'——注册表名是 'Kimi'（ai_models.dart），此前只认
    // 'Kimi-Coding-Plan'，普通 Kimi 用户拿不到 tool calling。Moonshot API
    // 走 OpenAI 兼容的 tools/tool_calls，与 DeepSeek 同路径。
    // 补 'Claude'——_chatClaude 已支持 tools（AnthropicConverter
    // 在边界做 OpenAI↔Anthropic 格式转换）。
    // 补 'Gemini'/'Google Gemini'——改走官方 OpenAI 兼容端点
    // （/v1beta/openai），复用 _chatOpenAICompat；'Google Gemini' 是 UI
    // 层实际流转的 display name（ai_panel_widget.dart）。
    return provider == 'Claude' ||
        provider == 'Gemini' ||
        provider == 'Google Gemini' ||
        provider == 'Kimi' ||
        provider == 'Kimi-Coding-Plan' ||
        provider == 'MiniMax' ||
        provider == 'MiniMax-Token-Plan' ||
        provider == 'GLM-Coding-Plan' ||
        provider == 'DeepSeek' ||
        provider == 'OpenAI';
  }

  static bool supportsThinking(String provider, String model) {
    return provider == 'Kimi-Coding-Plan' && (model.startsWith('kimi-k2'));
  }
}

class AiClient implements IAiClient {
  static const int _maxConnectionsPerHost = 10;
  static const Duration _idleTimeout = Duration(seconds: 30);
  static const Duration _connectionTimeout = Duration(seconds: 15);

  Client? _sharedClient;
  // 可选 httpClient 注入（测试用，照 TDengineAdapter 先例）。
  // 注入的 client 由调用方持有，cancel()/dispose() 不关闭它。
  final Client? _injectedClient;
  DateTime? _lastRequestTime;
  final Map<int, bool> _activeRequests = {};
  int _requestId = 0;

  PendingRequest? _currentPendingRequest;
  final Map<String, PendingRequest> _savedPendingRequests = {};
  String? _pendingRequestsDir;

  AiClient({Client? httpClient}) : _injectedClient = httpClient;

  Client _getOrCreateClient() {
    final injected = _injectedClient;
    if (injected != null) return injected;
    if (_sharedClient != null && _isConnectionHealthy()) {
      return _sharedClient!;
    }
    _sharedClient = _createConfiguredClient();
    return _sharedClient!;
  }

  Client _createConfiguredClient() {
    final httpClient = HttpClient()
      ..maxConnectionsPerHost = _maxConnectionsPerHost
      ..idleTimeout = _idleTimeout
      ..connectionTimeout = _connectionTimeout;
    return IOClient(httpClient);
  }

  // 路由修正——注册 provider + 空/默认 baseUrl 时使用注册表的
  // apiVersion（此前对任何非空 baseUrl 一律强制 chatCompletions，而上游
  // getBaseUrl 永远回退注册表默认值，导致 Claude 的 messages 分支成为
  // 死代码）。仅当 baseUrl 是真正自定义的（≠注册表默认）时才强制
  // chatCompletions，保留 OpenAI 兼容网关代理 Claude 的逃生门。
  static AiApiProvider? _resolveApiProvider(String provider, String? baseUrl) {
    String normalize(String url) =>
        url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    final registered = AiApiProviders.getByName(provider);
    if (registered != null &&
        (baseUrl == null ||
            baseUrl.isEmpty ||
            normalize(baseUrl) == normalize(registered.defaultBaseUrl))) {
      return registered;
    }
    if (baseUrl != null && baseUrl.isNotEmpty) {
      return AiApiProvider(
        name: provider,
        defaultBaseUrl: baseUrl,
        apiVersion: ApiVersion.chatCompletions,
      );
    }
    return registered; // 可能为 null → 调用方抛「不支持的AI厂商」
  }

  bool _isConnectionHealthy() {
    if (_lastRequestTime == null) return true;
    final elapsed = DateTime.now().difference(_lastRequestTime!);
    return elapsed < _idleTimeout;
  }

  int _newRequest() {
    cancel();
    _requestId++;
    _activeRequests[_requestId] = true;
    _lastRequestTime = DateTime.now();
    return _requestId;
  }

  void _completeRequest(int requestId) {
    _activeRequests.remove(requestId);
  }

  @override
  void dispose() {
    // 注入的 client 由调用方持有，不在这里关闭
    if (_injectedClient == null) {
      try {
        _sharedClient?.close();
      } catch (_) {}
      _sharedClient = null;
    }
    _activeRequests.clear();
  }

  Future<String> _getPendingRequestsDir() async {
    if (_pendingRequestsDir != null) return _pendingRequestsDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _pendingRequestsDir = '${appDir.path}/pending_requests';
    final dir = Directory(_pendingRequestsDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return _pendingRequestsDir!;
  }

  Future<void> _savePendingRequest(PendingRequest request) async {
    _savedPendingRequests[request.id] = request;
    try {
      final dir = await _getPendingRequestsDir();
      final file = File('$dir/${request.id}.json');
      await file.writeAsString(jsonEncode(request.toJson()));
      developer.log('💾 已保存待恢复请求: ${request.id}', name: 'AiClient');
    } catch (e) {
      developer.log('⚠️ 保存待恢复请求失败: $e', name: 'AiClient');
    }
  }

  Future<void> _removePendingRequest(String requestId) async {
    _savedPendingRequests.remove(requestId);
    try {
      final dir = await _getPendingRequestsDir();
      final file = File('$dir/$requestId.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  Future<List<PendingRequest>> loadPendingRequests() async {
    final requests = <PendingRequest>[];
    try {
      final dir = await _getPendingRequestsDir();
      final dirObj = Directory(dir);
      if (!await dirObj.exists()) return requests;

      await for (final entity in dirObj.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          try {
            final content = await entity.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final request = PendingRequest.fromJson(json);
            requests.add(request);
            _savedPendingRequests[request.id] = request;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return requests;
  }

  @override
  PendingRequest? getPendingRequest(String requestId) {
    return _savedPendingRequests[requestId];
  }

  @override
  Map<String, PendingRequest> get allPendingRequests =>
      Map.unmodifiable(_savedPendingRequests);

  @override
  Stream<AiStreamChunk> retryFromPending({
    required String requestId,
    required String apiKey,
  }) async* {
    final pending = _savedPendingRequests[requestId];
    if (pending == null) {
      throw Exception('Pending request not found: $requestId');
    }

    developer.log(
      '🔄 恢复请求: $requestId, 已有内容长度: ${pending.accumulatedContent.length}',
      name: 'AiClient',
    );

    yield* chatStreamWithReasoning(
      provider: pending.provider,
      model: pending.model,
      apiKey: apiKey,
      baseUrl: pending.baseUrl,
      message: pending.message,
      systemPrompt: pending.systemPrompt,
      history: pending.history,
      timeout: pending.timeout,
      thinkingEnabled: pending.thinkingEnabled,
      pendingRequestId: requestId,
    );
  }

  @override
  Future<void> clearPendingRequest(String requestId) async {
    await _removePendingRequest(requestId);
  }

  @override
  Future<void> clearAllPendingRequests() async {
    final ids = _savedPendingRequests.keys.toList();
    for (final id in ids) {
      await _removePendingRequest(id);
    }
  }

  @override
  Future<ChatResponse> chat({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout = const Duration(seconds: 60),
    String? promptCacheKey,
    List<Map<String, dynamic>>? tools,
    bool thinkingEnabled = false,
  }) async {
    final requestId = _newRequest();

    // 路由走 _resolveApiProvider（见该方法注释）
    final apiProvider = _resolveApiProvider(provider, baseUrl);

    if (apiProvider == null) {
      throw Exception('Unsupported AI provider: $provider');
    }

    if (apiProvider.apiVersion == ApiVersion.messages) {
      return await _retryRequest(
        // history 不再拍平为 {role, content}——原始 OpenAI 格式
        // （含 tool_calls / role:'tool'）透传给 _chatClaude，由其内部
        // 的 AnthropicConverter 做协议转换；tools 同步透传。
        () => _chatClaude(
          requestId: requestId,
          baseUrl: apiProvider.defaultBaseUrl,
          apiKey: apiKey,
          model: model,
          message: message,
          systemPrompt: systemPrompt,
          history: history,
          tools: tools,
          timeout: timeout,
        ),
      );
    }

    return _retryRequest(
      () => _chatOpenAICompat(
        requestId: requestId,
        baseUrl: apiProvider.defaultBaseUrl,
        apiKey: apiKey,
        model: model,
        message: message,
        systemPrompt: systemPrompt,
        history: history,
        timeout: timeout,
        promptCacheKey: promptCacheKey,
        tools: tools,
        thinkingEnabled: thinkingEnabled,
      ),
    );
  }

  Future<ChatResponse> _chatOpenAICompat({
    required int requestId,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout = const Duration(seconds: 60),
    String? promptCacheKey,
    List<Map<String, dynamic>>? tools,
    bool thinkingEnabled = false,
  }) async {
    final messages = <Map<String, dynamic>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }

    if (history != null && history.isNotEmpty) {
      messages.addAll(history);
    }

    if (message.isNotEmpty) {
      messages.add({'role': 'user', 'content': message});
    }

    final url = Uri.parse('$baseUrl/chat/completions');
    final request = Request('POST', url);
    request.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    });

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': 4096,
      'temperature': 0.3,
    };

    if (promptCacheKey != null && promptCacheKey.isNotEmpty) {
      body['prompt_cache_key'] = promptCacheKey;
    }

    if (tools != null && tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }

    if (thinkingEnabled && IAiClient.supportsThinking('', model)) {
      body['thinking'] = {'type': 'enabled'};
    }

    request.body = jsonEncode(body);

    if (!_activeRequests.containsKey(requestId)) {
      throw Exception('Request was cancelled.');
    }

    final client = _getOrCreateClient();

    try {
      final stream = await client.send(request).timeout(timeout);
      final response = await Response.fromStream(stream);

      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final choice =
            (data['choices'] as List<dynamic>?)?.firstOrNull
                as Map<String, dynamic>?;
        final msg = choice?['message'] as Map<String, dynamic>?;
        final content = msg?['content'] as String?;
        final reasoningContent = msg?['reasoning_content'] as String?;
        final rawToolCalls = msg?['tool_calls'] as List<dynamic>?;

        final toolCalls = <AiToolCall>[];
        if (rawToolCalls != null) {
          for (final tc in rawToolCalls) {
            if (tc is Map<String, dynamic>) {
              toolCalls.add(AiToolCall.fromJson(tc));
            }
          }
        }

        final usage = _parseUsage(data);
        return ChatResponse(
          content: content,
          reasoningContent: reasoningContent,
          toolCalls: toolCalls,
          usage: usage,
        );
      } else {
        final error = jsonDecode(response.body);
        throw Exception(
          'API error: ${error['error']?['message'] ?? response.body}',
        );
      }
    } finally {
      _completeRequest(requestId);
    }
  }

  Future<ChatResponse> _chatClaude({
    required int requestId,
    String? baseUrl,
    required String apiKey,
    required String model,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    // 新增 tools 参数（OpenAI 格式，边界处转 Anthropic 格式）
    List<Map<String, dynamic>>? tools,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final url = Uri.parse(
      '${baseUrl ?? 'https://api.anthropic.com'}/v1/messages',
    );

    final messages = <Map<String, dynamic>>[];

    if (history != null && history.isNotEmpty) {
      // OpenAI 格式 history → Anthropic messages（转换器处理
      // tool_calls→content blocks、连续 role:'tool' 合并单条 user 等）
      messages.addAll(AnthropicConverter.convertHistory(history));
    }

    if (message.isNotEmpty) {
      messages.add({'role': 'user', 'content': message});
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 4096,
      'messages': messages,
    };

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system'] = systemPrompt;
    }

    // tools 注入（Anthropic 格式 input_schema）
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = AnthropicConverter.convertTools(tools);
      body['tool_choice'] = {'type': 'auto'};
    }

    if (!_activeRequests.containsKey(requestId)) {
      throw Exception('Request was cancelled.');
    }

    final request = Request('POST', url);
    request.headers.addAll({
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    });
    request.body = jsonEncode(body);

    final client = _getOrCreateClient();
    final stream = await client.send(request).timeout(timeout);
    final response = await Response.fromStream(stream);

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      // 解析改为遍历 content blocks（此前只取 [0]['text']，
      // 遇 tool_use block 会类型错误崩溃）；usage 沿用现有解析
      final chatResponse = AnthropicConverter.parseResponse(
        data as Map<String, dynamic>,
      );
      return ChatResponse(
        content: chatResponse.content,
        toolCalls: chatResponse.toolCalls,
        usage: _parseUsage(data),
      );
    } else {
      final error = jsonDecode(response.body);
      throw Exception('API error: ${error['error']?['message'] ?? response.body}');
    }
  }

  Future<T> _retryRequest<T>(
    Future<T> Function() request, {
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await request();
      } catch (e) {
        attempt++;
        final isRetryable =
            e is TimeoutException ||
            e.toString().contains('429') ||
            e.toString().contains('503') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection');
        if (!isRetryable || attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
      }
    }
  }

  TokenUsage? _parseUsage(Map<String, dynamic> data) {
    try {
      final usage = data['usage'] as Map<String, dynamic>?;
      if (usage == null) return null;

      // Claude format: input_tokens, output_tokens
      final inputTokens =
          (usage['input_tokens'] as num?)?.toInt() ??
          (usage['prompt_tokens'] as num?)?.toInt() ??
          0;
      final outputTokens =
          (usage['output_tokens'] as num?)?.toInt() ??
          (usage['completion_tokens'] as num?)?.toInt() ??
          0;
      final totalTokens =
          (usage['total_tokens'] as num?)?.toInt() ??
          inputTokens + outputTokens;

      if (inputTokens == 0 && outputTokens == 0) return null;
      return TokenUsage(
        promptTokens: inputTokens,
        completionTokens: outputTokens,
        totalTokens: totalTokens,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void cancel() {
    _activeRequests.clear();
    // 注入的 client 由调用方持有，不在这里关闭
    if (_injectedClient == null) {
      try {
        _sharedClient?.close();
      } catch (_) {}
      _sharedClient = null;
    }
  }

  List<String> _parseSseLines(StringBuffer buffer, String newChunk) {
    buffer.write(newChunk);
    final allContent = buffer.toString();
    final lines = <String>[];
    int start = 0;
    for (int i = 0; i < allContent.length; i++) {
      if (allContent[i] == '\n') {
        lines.add(allContent.substring(start, i));
        start = i + 1;
      } else if (allContent[i] == '\r' &&
          i + 1 < allContent.length &&
          allContent[i + 1] == '\n') {
        lines.add(allContent.substring(start, i));
        start = i + 2;
        i++;
      } else if (allContent[i] == '\r') {
        lines.add(allContent.substring(start, i));
        start = i + 1;
      }
    }
    buffer.clear();
    if (start < allContent.length) {
      buffer.write(allContent.substring(start));
    }
    return lines;
  }

  @override
  bool get isRunning => _activeRequests.isNotEmpty;

  @override
  Stream<String> chatStream({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout = const Duration(seconds: 60),
    String? promptCacheKey,
    bool thinkingEnabled = false,
  }) async* {
    await for (final chunk in chatStreamWithReasoning(
      provider: provider,
      model: model,
      apiKey: apiKey,
      baseUrl: baseUrl,
      message: message,
      systemPrompt: systemPrompt,
      history: history,
      timeout: timeout,
      promptCacheKey: promptCacheKey,
      thinkingEnabled: thinkingEnabled,
    )) {
      if (chunk.type == 'content') {
        yield chunk.text;
      }
    }
  }

  @override
  Stream<AiStreamChunk> chatStreamWithReasoning({
    required String provider,
    required String model,
    required String apiKey,
    String? baseUrl,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout = const Duration(seconds: 60),
    String? promptCacheKey,
    bool thinkingEnabled = false,
    String? pendingRequestId,
  }) async* {
    final requestId = _newRequest();

    // 路由走 _resolveApiProvider（见该方法注释）
    final apiProvider = _resolveApiProvider(provider, baseUrl);

    if (apiProvider == null) {
      throw Exception('Unsupported AI provider: $provider');
    }

    final pendingId =
        pendingRequestId ?? 'req_${DateTime.now().millisecondsSinceEpoch}';

    _currentPendingRequest = PendingRequest(
      id: pendingId,
      provider: provider,
      model: model,
      message: message,
      baseUrl: baseUrl,
      systemPrompt: systemPrompt,
      history: history,
      timeout: timeout,
      thinkingEnabled: thinkingEnabled,
      startedAt: DateTime.now(),
    );

    try {
      if (apiProvider.apiVersion == ApiVersion.messages) {
        yield* _chatClaudeStream(
          requestId: requestId,
          baseUrl: apiProvider.defaultBaseUrl,
          apiKey: apiKey,
          model: model,
          message: message,
          systemPrompt: systemPrompt,
          history: history,
          timeout: timeout,
        );
      } else {
        yield* _chatOpenAICompatStream(
          requestId: requestId,
          baseUrl: apiProvider.defaultBaseUrl,
          apiKey: apiKey,
          model: model,
          message: message,
          systemPrompt: systemPrompt,
          history: history,
          timeout: timeout,
          promptCacheKey: promptCacheKey,
          thinkingEnabled: thinkingEnabled,
        );
      }
    } finally {
      _currentPendingRequest = null;
    }
  }

  Stream<AiStreamChunk> _chatOpenAICompatStream({
    required int requestId,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout = const Duration(seconds: 60),
    String? promptCacheKey,
    bool thinkingEnabled = false,
  }) async* {
    developer.log('🚀 开始OpenAI兼容流式请求', name: 'AiClient');

    final messages = <Map<String, dynamic>>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt});
    }

    if (history != null && history.isNotEmpty) {
      messages.addAll(history);
    }

    if (message.isNotEmpty) {
      messages.add({'role': 'user', 'content': message});
    }

    final url = Uri.parse('$baseUrl/chat/completions');

    final body = <String, dynamic>{
      'model': model,
      'messages': messages,
      'max_tokens': 4096,
      'temperature': 0.3,
      'stream': true,
    };

    if (promptCacheKey != null && promptCacheKey.isNotEmpty) {
      body['prompt_cache_key'] = promptCacheKey;
    }

    if (thinkingEnabled && IAiClient.supportsThinking('', model)) {
      body['thinking'] = {'type': 'enabled'};
    }

    try {
      if (!_activeRequests.containsKey(requestId)) {
        throw Exception('Request was cancelled.');
      }

      final client = _getOrCreateClient();
      final streamedResponse = await _retryRequest(() async {
        final request = Request('POST', url);
        request.headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        });

        request.body = jsonEncode(body);
        return await client.send(request).timeout(timeout);
      });

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        final error = jsonDecode(body);
        throw Exception('API错误: ${error['error']?['message'] ?? body}');
      }

      final buffer = StringBuffer();

      await for (final chunk in streamedResponse.stream.timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) => sink.close(),
      )) {
        if (!_activeRequests.containsKey(requestId)) {
          return;
        }

        final lines = _parseSseLines(buffer, utf8.decode(chunk));

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          if (trimmed.startsWith('data: ')) {
            final data = trimmed.substring(6);
            if (data == '[DONE]') {
              return;
            }

            try {
              final json = jsonDecode(data);

              final delta =
                  json['choices']?[0]?['delta'] as Map<String, dynamic>?;
              String? reasoning;
              if (delta != null) {
                reasoning = delta['reasoning'] as String?;
                if (reasoning == null || reasoning.isEmpty) {
                  reasoning = delta['reasoning_content'] as String?;
                }
              }
              if (reasoning != null && reasoning.isNotEmpty) {
                _currentPendingRequest?.accumulatedReasoning += reasoning;
                yield AiStreamChunk.reasoning(reasoning);
              }

              final content =
                  json['choices']?[0]?['delta']?['content'] as String?;
              if (content != null && content.isNotEmpty) {
                _currentPendingRequest?.accumulatedContent += content;
                yield AiStreamChunk.content(content);
              }
            } catch (e) {
              // ignore malformed chunks
            }
          }
        }
      }
    } catch (e) {
      if (_currentPendingRequest != null &&
          _currentPendingRequest!.accumulatedContent.isNotEmpty) {
        await _savePendingRequest(_currentPendingRequest!);
      }
      rethrow;
    } finally {
      _completeRequest(requestId);
    }
  }

  Stream<AiStreamChunk> _chatClaudeStream({
    required int requestId,
    String? baseUrl,
    required String apiKey,
    required String model,
    required String message,
    String? systemPrompt,
    List<Map<String, dynamic>>? history,
    Duration timeout = const Duration(seconds: 60),
  }) async* {
    final url = Uri.parse(
      '${baseUrl ?? 'https://api.anthropic.com'}/v1/messages',
    );

    final messages = <Map<String, dynamic>>[];

    if (history != null && history.isNotEmpty) {
      messages.addAll(history);
    }

    if (message.isNotEmpty) {
      messages.add({'role': 'user', 'content': message});
    }

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 4096,
      'messages': messages,
      'stream': true,
    };

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system'] = systemPrompt;
    }

    try {
      if (!_activeRequests.containsKey(requestId)) {
        throw Exception('Request was cancelled.');
      }

      final client = _getOrCreateClient();
      final streamedResponse = await _retryRequest(() async {
        final request = Request('POST', url);
        request.headers.addAll({
          'Content-Type': 'application/json',
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
        });
        request.body = jsonEncode(body);
        return await client.send(request).timeout(timeout);
      });

      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        final error = jsonDecode(body);
        throw Exception('API错误: ${error['error']?['message'] ?? body}');
      }

      final buffer = StringBuffer();

      String? currentEvent;
      await for (final chunk in streamedResponse.stream.timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) => sink.close(),
      )) {
        if (!_activeRequests.containsKey(requestId)) {
          return;
        }

        final lines = _parseSseLines(buffer, utf8.decode(chunk));

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          if (trimmed.startsWith('event: ')) {
            currentEvent = trimmed.substring(7);
            if (currentEvent == 'message_stop') {
              return;
            }
            continue;
          }

          if (trimmed.startsWith('data: ')) {
            final data = trimmed.substring(6);

            try {
              final json = jsonDecode(data);
              final type = json['type'] as String?;

              if (type == 'content_block_delta') {
                final delta = json['delta'] as Map<String, dynamic>?;
                if (delta != null) {
                  final deltaType = delta['type'] as String?;
                  if (deltaType == 'text_delta') {
                    final text = delta['text'] as String?;
                    if (text != null && text.isNotEmpty) {
                      _currentPendingRequest?.accumulatedContent += text;
                      yield AiStreamChunk.content(text);
                    }
                  }
                }
              }
            } catch (e) {
              // ignore malformed chunks
            }
          }
        }
      }
    } catch (e) {
      if (_currentPendingRequest != null &&
          _currentPendingRequest!.accumulatedContent.isNotEmpty) {
        await _savePendingRequest(_currentPendingRequest!);
      }
      rethrow;
    } finally {
      _completeRequest(requestId);
    }
  }

  @override
  Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) async {
    final requestId = _newRequest();
    try {
      String normalizedUrl = baseUrl.trim();
      if (normalizedUrl.endsWith('/')) {
        normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
      }
      // 已含版本段（/v1、/v1beta、/v1beta/openai 等）则不追加 /v1——
      // 此前只认 /v1 结尾，Gemini 的 OpenAI 兼容端点会被拼成
      // .../v1beta/openai/v1/models（404）
      if (!RegExp(r'/v\d+\w*(/openai)?$').hasMatch(normalizedUrl)) {
        normalizedUrl = '$normalizedUrl/v1';
      }

      final uri = Uri.parse('$normalizedUrl/models');
      final request = Request('GET', uri);
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.headers['Accept'] = 'application/json';

      final client = _getOrCreateClient();
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 10));

      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch models (status ${response.statusCode}).');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? [];

      final models = data
          .map((item) => item['id'] as String?)
          .whereType<String>()
          .toList();

      models.sort();

      return models;
    } catch (e) {
      developer.log('⚠️ 获取模型列表失败: $e', name: 'AiClient');
      rethrow;
    } finally {
      _completeRequest(requestId);
    }
  }
}
