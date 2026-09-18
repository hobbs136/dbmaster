/// Represents a saved checkpoint of an agent run that can be resumed.
class AgentCheckpoint {
  final String id;
  final String sessionId;
  final String userMessage;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> toolExecutions;
  final String? accumulatedReasoning;
  final int toolCallCount;
  final int currentIteration;
  final String provider;
  final String model;
  final String? baseUrl;
  final bool thinkingEnabled;
  final DateTime createdAt;
  final DateTime? resumedAt;
  final bool isResumed;

  AgentCheckpoint({
    required this.id,
    required this.sessionId,
    required this.userMessage,
    required this.history,
    required this.toolExecutions,
    this.accumulatedReasoning,
    required this.toolCallCount,
    required this.currentIteration,
    required this.provider,
    required this.model,
    this.baseUrl,
    required this.thinkingEnabled,
    required this.createdAt,
    this.resumedAt,
    this.isResumed = false,
  });

  AgentCheckpoint copyWith({
    String? id,
    String? sessionId,
    String? userMessage,
    List<Map<String, dynamic>>? history,
    List<Map<String, dynamic>>? toolExecutions,
    String? accumulatedReasoning,
    int? toolCallCount,
    int? currentIteration,
    String? provider,
    String? model,
    String? baseUrl,
    bool? thinkingEnabled,
    DateTime? createdAt,
    DateTime? resumedAt,
    bool? isResumed,
  }) {
    return AgentCheckpoint(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      userMessage: userMessage ?? this.userMessage,
      history: history ?? this.history,
      toolExecutions: toolExecutions ?? this.toolExecutions,
      accumulatedReasoning: accumulatedReasoning ?? this.accumulatedReasoning,
      toolCallCount: toolCallCount ?? this.toolCallCount,
      currentIteration: currentIteration ?? this.currentIteration,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      baseUrl: baseUrl ?? this.baseUrl,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      createdAt: createdAt ?? this.createdAt,
      resumedAt: resumedAt ?? this.resumedAt,
      isResumed: isResumed ?? this.isResumed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'userMessage': userMessage,
      'history': history,
      'toolExecutions': toolExecutions,
      'accumulatedReasoning': accumulatedReasoning,
      'toolCallCount': toolCallCount,
      'currentIteration': currentIteration,
      'provider': provider,
      'model': model,
      'baseUrl': baseUrl,
      'thinkingEnabled': thinkingEnabled,
      'createdAt': createdAt.toIso8601String(),
      'resumedAt': resumedAt?.toIso8601String(),
      'isResumed': isResumed,
    };
  }

  factory AgentCheckpoint.fromJson(Map<String, dynamic> json) {
    return AgentCheckpoint(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      userMessage: json['userMessage'] as String,
      history: (json['history'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList(),
      toolExecutions: (json['toolExecutions'] as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList(),
      accumulatedReasoning: json['accumulatedReasoning'] as String?,
      toolCallCount: json['toolCallCount'] as int? ?? 0,
      currentIteration: json['currentIteration'] as int? ?? 0,
      provider: json['provider'] as String,
      model: json['model'] as String,
      baseUrl: json['baseUrl'] as String?,
      thinkingEnabled: json['thinkingEnabled'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      resumedAt: json['resumedAt'] != null
          ? DateTime.parse(json['resumedAt'] as String)
          : null,
      isResumed: json['isResumed'] as bool? ?? false,
    );
  }
}
