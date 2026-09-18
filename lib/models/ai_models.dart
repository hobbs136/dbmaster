import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

enum ApiVersion { chatCompletions, messages }

// provider 图标从 emoji String 迁移为 IconData（F-37），
// 渲染处统一用 Icon(p.icon, color: Color(p.color)) 着品牌色
class AiApiProvider {
  final String name;
  final String defaultBaseUrl;
  final ApiVersion apiVersion;
  final IconData icon;
  final int color;
  final List<String> models;

  const AiApiProvider({
    required this.name,
    required this.defaultBaseUrl,
    required this.apiVersion,
    this.icon = LucideIcons.bot,
    this.color = 0xFF10a37f,
    this.models = const [],
  });
}

class AiApiProviders {
  static const String customModelKey = 'custom_model';

  static const Map<String, AiApiProvider> all = {
    'OpenAI': AiApiProvider(
      name: 'OpenAI',
      defaultBaseUrl: 'https://api.openai.com/v1',
      apiVersion: ApiVersion.chatCompletions,
      icon: LucideIcons.bot,
      color: 0xFF10a37f,
      models: ['gpt-4-turbo', 'gpt-4o', 'gpt-4o-mini', 'gpt-3.5-turbo'],
    ),
    'Claude': AiApiProvider(
      name: 'Claude',
      defaultBaseUrl: 'https://api.anthropic.com',
      apiVersion: ApiVersion.messages,
      icon: LucideIcons.brain,
      color: 0xFFd97757,
      models: [
        'claude-3-opus',
        'claude-3-sonnet',
        'claude-3-haiku',
        'claude-3-5-sonnet',
      ],
    ),
    'Gemini': AiApiProvider(
      name: 'Google Gemini',
      // 改指官方 OpenAI 兼容端点——原默认 .../v1beta 拼出的
      // /v1beta/chat/completions 根本不存在，Gemini 全链路不可用；
      // /v1beta/openai 支持 chat/completions + tools + Bearer 鉴权
      defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      apiVersion: ApiVersion.chatCompletions,
      icon: LucideIcons.sparkles,
      color: 0xFF4285f4,
      models: [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-2.0-flash',
        'gemini-2.0-pro',
        'gemini-1.5-pro',
        'gemini-1.5-flash',
      ],
    ),
    'Ollama': AiApiProvider(
      name: 'Ollama',
      defaultBaseUrl: 'http://localhost:11434/v1',
      apiVersion: ApiVersion.chatCompletions,
      icon: LucideIcons.monitor,
      color: 0xFF9333EA,
      models: [
        'llama3',
        'llama3.1',
        'mistral',
        'qwen2.5:14b',
        'qwen2.5:32b',
        'codellama',
        'phi3',
      ],
    ),
    'DeepSeek': AiApiProvider(
      name: 'DeepSeek',
      defaultBaseUrl: 'https://api.deepseek.com/v1',
      apiVersion: ApiVersion.chatCompletions,
      icon: LucideIcons.textSearch,
      color: 0xFF4d6bfa,
      models: ['deepseek-chat', 'deepseek-coder', 'deepseek-reasoner'],
    ),
    'Kimi': AiApiProvider(
      name: 'Kimi',
      defaultBaseUrl: 'https://api.moonshot.cn/v1',
      apiVersion: ApiVersion.chatCompletions,
      icon: LucideIcons.star,
      color: 0xFF00d4aa,
      models: ['moonshot-v1-8k', 'moonshot-v1-32k', 'moonshot-v1-128k'],
    ),
  };

  static AiApiProvider? getByName(String name) {
    final byKey = all[name] ?? all[name.replaceAll(' ', '-')];
    if (byKey != null) return byKey;
    // 兜底按 display name 匹配——UI 层用 p.name 流转 provider
    // 标识（ai_panel_widget.dart），如 'Google Gemini' ≠ 注册表 key 'Gemini'
    for (final provider in all.values) {
      if (provider.name == name) return provider;
    }
    return null;
  }
}

class AiToolCall {
  final String id;
  final String type;
  final String functionName;
  final String functionArguments;

  AiToolCall({
    required this.id,
    required this.type,
    required this.functionName,
    required this.functionArguments,
  });

  factory AiToolCall.fromJson(Map<String, dynamic> json) {
    final function = json['function'] as Map<String, dynamic>?;
    return AiToolCall(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'function',
      functionName: function?['name'] as String? ?? '',
      functionArguments: function?['arguments'] as String? ?? '{}',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'function': {'name': functionName, 'arguments': functionArguments},
  };
}

class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  TokenUsage operator +(TokenUsage other) => TokenUsage(
    promptTokens: promptTokens + other.promptTokens,
    completionTokens: completionTokens + other.completionTokens,
    totalTokens: totalTokens + other.totalTokens,
  );

  bool get isEmpty => totalTokens == 0;

  Map<String, dynamic> toJson() => {
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'totalTokens': totalTokens,
  };

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
    promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
    completionTokens: (json['completionTokens'] as num?)?.toInt() ?? 0,
    totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
  );
}

class ChatResponse {
  final String? content;
  final String? reasoningContent;
  final List<AiToolCall> toolCalls;
  final TokenUsage? usage;

  ChatResponse({
    this.content,
    this.reasoningContent,
    this.toolCalls = const [],
    this.usage,
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

class AiStreamChunk {
  final String type;
  final String text;

  AiStreamChunk({required this.type, required this.text});

  factory AiStreamChunk.reasoning(String text) =>
      AiStreamChunk(type: 'reasoning', text: text);
  factory AiStreamChunk.content(String text) =>
      AiStreamChunk(type: 'content', text: text);
}

class PendingRequest {
  final String id;
  final String provider;
  final String model;
  final String message;
  String accumulatedContent;
  String accumulatedReasoning;
  final DateTime startedAt;
  final String? baseUrl;
  final String? systemPrompt;
  final List<Map<String, dynamic>>? history;
  final Duration timeout;
  final bool thinkingEnabled;

  PendingRequest({
    required this.id,
    required this.provider,
    required this.model,
    required this.message,
    this.accumulatedContent = '',
    this.accumulatedReasoning = '',
    required this.startedAt,
    this.baseUrl,
    this.systemPrompt,
    this.history,
    this.timeout = const Duration(seconds: 60),
    this.thinkingEnabled = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider,
    'model': model,
    'message': message,
    'accumulatedContent': accumulatedContent,
    'accumulatedReasoning': accumulatedReasoning,
    'startedAt': startedAt.toIso8601String(),
    'baseUrl': baseUrl,
    'systemPrompt': systemPrompt,
    'history': history,
    'timeout': timeout.inSeconds,
    'thinkingEnabled': thinkingEnabled,
  };

  factory PendingRequest.fromJson(Map<String, dynamic> json) => PendingRequest(
    id: json['id'] as String,
    provider: json['provider'] as String,
    model: json['model'] as String,
    message: json['message'] as String,
    accumulatedContent: json['accumulatedContent'] as String? ?? '',
    accumulatedReasoning: json['accumulatedReasoning'] as String? ?? '',
    startedAt: DateTime.parse(json['startedAt'] as String),
    baseUrl: json['baseUrl'] as String?,
    systemPrompt: json['systemPrompt'] as String?,
    history: (json['history'] as List<dynamic>?)
        ?.map((e) => e as Map<String, dynamic>)
        .toList(),
    timeout: Duration(seconds: json['timeout'] as int? ?? 60),
    thinkingEnabled: json['thinkingEnabled'] as bool? ?? false,
  );
}
