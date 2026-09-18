/// 片段适用的数据库族 (US3, 020-mongo-daily-productivity)。
/// `all` = 适用于所有数据库类型（向后兼容：旧的自定义片段默认值）。
enum SnippetDbFamily { sql, mongodb, all }

class CodeSnippet {
  final String id;
  final String name;
  final String description;
  final String category;
  final String content;
  final List<String> variables;
  final bool isBuiltIn;
  final int usageCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastUsedAt;
  final SnippetDbFamily databaseFamily; // 020-mongo US3

  CodeSnippet({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.content,
    this.variables = const [],
    this.isBuiltIn = false,
    this.usageCount = 0,
    this.databaseFamily = SnippetDbFamily.all, // 020-mongo US3
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastUsedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  // -------------------------------------------------------------------------
  // Equality (based on id)
  // -------------------------------------------------------------------------
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodeSnippet &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  CodeSnippet incrementUsage() {
    return copyWith(
      usageCount: usageCount + 1,
      updatedAt: DateTime.now(),
      lastUsedAt: DateTime.now(),
    );
  }

  CodeSnippet copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    String? content,
    List<String>? variables,
    bool? isBuiltIn,
    int? usageCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsedAt,
    SnippetDbFamily? databaseFamily, // 020-mongo US3
  }) {
    return CodeSnippet(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      content: content ?? this.content,
      variables: variables ?? this.variables,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      usageCount: usageCount ?? this.usageCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      databaseFamily: databaseFamily ?? this.databaseFamily,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category,
      'content': content,
      'variables': variables,
      'isBuiltIn': isBuiltIn,
      'usageCount': usageCount,
      'databaseFamily': databaseFamily.name, // 020-mongo US3
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
    };
  }

  factory CodeSnippet.fromJson(Map<String, dynamic> json) {
    return CodeSnippet(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      category: json['category'] as String,
      content: json['content'] as String,
      variables: List<String>.from(json['variables'] as List),
      isBuiltIn: json['isBuiltIn'] as bool,
      usageCount: json['usageCount'] as int,
      databaseFamily: CodeSnippet._parseFamily(json['databaseFamily']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
    );
  }

  /// 解析 databaseFamily；缺失或非法值回退 [SnippetDbFamily.all]（向后兼容旧数据）。US3
  static SnippetDbFamily _parseFamily(Object? raw) {
    if (raw is String) {
      return SnippetDbFamily.values.firstWhere(
        (f) => f.name == raw,
        orElse: () => SnippetDbFamily.all,
      );
    }
    return SnippetDbFamily.all;
  }
}
