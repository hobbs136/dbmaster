export '../models/ai_models.dart';
export 'ai/ai_client.dart';

import 'ai/ai_client.dart';
import '../models/ai_models.dart';

final AiService _defaultInstance = AiService._internal();

class AiService implements IAiClient {
  final AiClient _client;

  AiService._internal() : _client = AiClient();

  factory AiService() => _defaultInstance;

  AiClient get client => _client;

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
  }) => _client.chat(
    provider: provider,
    model: model,
    apiKey: apiKey,
    baseUrl: baseUrl,
    message: message,
    systemPrompt: systemPrompt,
    history: history,
    timeout: timeout,
    promptCacheKey: promptCacheKey,
    tools: tools,
    thinkingEnabled: thinkingEnabled,
  );

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
  }) => _client.chatStream(
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
  );

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
  }) => _client.chatStreamWithReasoning(
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
    pendingRequestId: pendingRequestId,
  );

  @override
  Future<List<PendingRequest>> loadPendingRequests() =>
      _client.loadPendingRequests();

  @override
  PendingRequest? getPendingRequest(String requestId) =>
      _client.getPendingRequest(requestId);

  @override
  Map<String, PendingRequest> get allPendingRequests =>
      _client.allPendingRequests;

  @override
  Stream<AiStreamChunk> retryFromPending({
    required String requestId,
    required String apiKey,
  }) => _client.retryFromPending(requestId: requestId, apiKey: apiKey);

  @override
  Future<void> clearPendingRequest(String requestId) =>
      _client.clearPendingRequest(requestId);

  @override
  Future<void> clearAllPendingRequests() => _client.clearAllPendingRequests();

  @override
  void cancel() => _client.cancel();

  @override
  void dispose() => _client.dispose();

  @override
  bool get isRunning => _client.isRunning;

  @override
  Future<List<String>> fetchModels({
    required String baseUrl,
    required String apiKey,
  }) => _client.fetchModels(baseUrl: baseUrl, apiKey: apiKey);

  static bool supportsToolCalling(String provider) =>
      IAiClient.supportsToolCalling(provider);

  static bool supportsThinking(String provider, String model) =>
      IAiClient.supportsThinking(provider, model);
}
