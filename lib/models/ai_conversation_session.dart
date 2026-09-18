class AiConversationSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> messageIds;
  final String? parentSessionId;
  final bool isArchived;
  final Map<String, dynamic>? metadata;
  final String? goalSummary;
  final int userMessageCount;
  final DateTime? lastSummarizedAt;

  AiConversationSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageIds,
    this.parentSessionId,
    this.isArchived = false,
    this.metadata,
    this.goalSummary,
    this.userMessageCount = 0,
    this.lastSummarizedAt,
  });

  AiConversationSession copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? messageIds,
    String? parentSessionId,
    bool? isArchived,
    Map<String, dynamic>? metadata,
    String? goalSummary,
    int? userMessageCount,
    DateTime? lastSummarizedAt,
  }) {
    return AiConversationSession(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageIds: messageIds ?? this.messageIds,
      parentSessionId: parentSessionId ?? this.parentSessionId,
      isArchived: isArchived ?? this.isArchived,
      metadata: metadata ?? this.metadata,
      goalSummary: goalSummary ?? this.goalSummary,
      userMessageCount: userMessageCount ?? this.userMessageCount,
      lastSummarizedAt: lastSummarizedAt ?? this.lastSummarizedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'messageIds': messageIds,
      'parentSessionId': parentSessionId,
      'isArchived': isArchived,
      'metadata': metadata,
      'goalSummary': goalSummary,
      'userMessageCount': userMessageCount,
      'lastSummarizedAt': lastSummarizedAt?.toIso8601String(),
    };
  }

  factory AiConversationSession.fromJson(Map<String, dynamic> json) {
    return AiConversationSession(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      messageIds: (json['messageIds'] as List<dynamic>).cast<String>(),
      parentSessionId: json['parentSessionId'] as String?,
      isArchived: json['isArchived'] as bool? ?? false,
      metadata: json['metadata'] as Map<String, dynamic>?,
      goalSummary: json['goalSummary'] as String?,
      userMessageCount: json['userMessageCount'] as int? ?? 0,
      lastSummarizedAt: json['lastSummarizedAt'] != null
          ? DateTime.parse(json['lastSummarizedAt'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiConversationSession &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AiBookmark {
  final String id;
  final String messageId;
  final String? note;
  final DateTime createdAt;
  final List<String> tags;

  AiBookmark({
    required this.id,
    required this.messageId,
    this.note,
    required this.createdAt,
    this.tags = const [],
  });

  AiBookmark copyWith({
    String? id,
    String? messageId,
    String? note,
    DateTime? createdAt,
    List<String>? tags,
  }) {
    return AiBookmark(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'messageId': messageId,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'tags': tags,
    };
  }

  factory AiBookmark.fromJson(Map<String, dynamic> json) {
    return AiBookmark(
      id: json['id'] as String,
      messageId: json['messageId'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiBookmark && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AiMessageReference {
  final String id;
  final String sourceMessageId;
  final String targetMessageId;
  final String referenceType;

  AiMessageReference({
    required this.id,
    required this.sourceMessageId,
    required this.targetMessageId,
    required this.referenceType,
  });

  AiMessageReference copyWith({
    String? id,
    String? sourceMessageId,
    String? targetMessageId,
    String? referenceType,
  }) {
    return AiMessageReference(
      id: id ?? this.id,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      targetMessageId: targetMessageId ?? this.targetMessageId,
      referenceType: referenceType ?? this.referenceType,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceMessageId': sourceMessageId,
      'targetMessageId': targetMessageId,
      'referenceType': referenceType,
    };
  }

  factory AiMessageReference.fromJson(Map<String, dynamic> json) {
    return AiMessageReference(
      id: json['id'] as String,
      sourceMessageId: json['sourceMessageId'] as String,
      targetMessageId: json['targetMessageId'] as String,
      referenceType: json['referenceType'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiMessageReference &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
