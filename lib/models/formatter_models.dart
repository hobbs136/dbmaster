/// SQL 格式化器数据模型
/// 包含格式化选项和预设配置
library;

class FormatterOptions {
  final int indentSize;
  final bool useTabs;
  final bool uppercaseKeywords;
  final bool preserveComments;
  final int maxLineLength;
  final String commaStyle; // 'trailing', 'leading'
  final bool alignKeywords;
  final bool compactMode;
  final bool breakBeforeBrackets;

  const FormatterOptions({
    this.indentSize = 4,
    this.useTabs = false,
    this.uppercaseKeywords = true,
    this.preserveComments = true,
    this.maxLineLength = 80,
    this.commaStyle = 'trailing',
    this.alignKeywords = true,
    this.compactMode = false,
    this.breakBeforeBrackets = false,
  });

  FormatterOptions copyWith({
    int? indentSize,
    bool? useTabs,
    bool? uppercaseKeywords,
    bool? preserveComments,
    int? maxLineLength,
    String? commaStyle,
    bool? alignKeywords,
    bool? compactMode,
    bool? breakBeforeBrackets,
  }) {
    return FormatterOptions(
      indentSize: indentSize ?? this.indentSize,
      useTabs: useTabs ?? this.useTabs,
      uppercaseKeywords: uppercaseKeywords ?? this.uppercaseKeywords,
      preserveComments: preserveComments ?? this.preserveComments,
      maxLineLength: maxLineLength ?? this.maxLineLength,
      commaStyle: commaStyle ?? this.commaStyle,
      alignKeywords: alignKeywords ?? this.alignKeywords,
      compactMode: compactMode ?? this.compactMode,
      breakBeforeBrackets: breakBeforeBrackets ?? this.breakBeforeBrackets,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'indentSize': indentSize,
      'useTabs': useTabs,
      'uppercaseKeywords': uppercaseKeywords,
      'preserveComments': preserveComments,
      'maxLineLength': maxLineLength,
      'commaStyle': commaStyle,
      'alignKeywords': alignKeywords,
      'compactMode': compactMode,
      'breakBeforeBrackets': breakBeforeBrackets,
    };
  }

  factory FormatterOptions.fromJson(Map<String, dynamic> json) {
    return FormatterOptions(
      indentSize: json['indentSize'] as int? ?? 4,
      useTabs: json['useTabs'] as bool? ?? false,
      uppercaseKeywords: json['uppercaseKeywords'] as bool? ?? true,
      preserveComments: json['preserveComments'] as bool? ?? true,
      maxLineLength: json['maxLineLength'] as int? ?? 80,
      commaStyle: json['commaStyle'] as String? ?? 'trailing',
      alignKeywords: json['alignKeywords'] as bool? ?? true,
      compactMode: json['compactMode'] as bool? ?? false,
      breakBeforeBrackets: json['breakBeforeBrackets'] as bool? ?? false,
    );
  }
}

class FormatterPreset {
  final String id;
  final String name;
  final String description;
  final FormatterOptions options;
  final bool isBuiltIn;
  final DateTime? createdAt;

  const FormatterPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.options,
    this.isBuiltIn = false,
    this.createdAt,
  });

  FormatterPreset copyWith({
    String? id,
    String? name,
    String? description,
    FormatterOptions? options,
    bool? isBuiltIn,
    DateTime? createdAt,
  }) {
    return FormatterPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      options: options ?? this.options,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'options': options.toJson(),
      'isBuiltIn': isBuiltIn,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory FormatterPreset.fromJson(Map<String, dynamic> json) {
    return FormatterPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      options: FormatterOptions.fromJson(
        json['options'] as Map<String, dynamic>,
      ),
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
    );
  }
}

/// SQL 语法高亮样式
class SqlHighlightStyle {
  final String keywordColor;
  final String stringColor;
  final String numberColor;
  final String commentColor;
  final String functionColor;
  final String operatorColor;
  final String identifierColor;

  const SqlHighlightStyle({
    this.keywordColor = '#569CD6',
    this.stringColor = '#CE9178',
    this.numberColor = '#B5CEA8',
    this.commentColor = '#6A9955',
    this.functionColor = '#DCDCAA',
    this.operatorColor = '#D4D4D4',
    this.identifierColor = '#9CDCFE',
  });

  Map<String, dynamic> toJson() {
    return {
      'keywordColor': keywordColor,
      'stringColor': stringColor,
      'numberColor': numberColor,
      'commentColor': commentColor,
      'functionColor': functionColor,
      'operatorColor': operatorColor,
      'identifierColor': identifierColor,
    };
  }

  factory SqlHighlightStyle.fromJson(Map<String, dynamic> json) {
    return SqlHighlightStyle(
      keywordColor: json['keywordColor'] as String? ?? '#569CD6',
      stringColor: json['stringColor'] as String? ?? '#CE9178',
      numberColor: json['numberColor'] as String? ?? '#B5CEA8',
      commentColor: json['commentColor'] as String? ?? '#6A9955',
      functionColor: json['functionColor'] as String? ?? '#DCDCAA',
      operatorColor: json['operatorColor'] as String? ?? '#D4D4D4',
      identifierColor: json['identifierColor'] as String? ?? '#9CDCFE',
    );
  }
}

/// 格式化历史记录
class FormatHistory {
  final String id;
  final String originalSql;
  final String formattedSql;
  final FormatterOptions options;
  final DateTime timestamp;

  FormatHistory({
    required this.id,
    required this.originalSql,
    required this.formattedSql,
    required this.options,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalSql': originalSql,
      'formattedSql': formattedSql,
      'options': options.toJson(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory FormatHistory.fromJson(Map<String, dynamic> json) {
    return FormatHistory(
      id: json['id'] as String,
      originalSql: json['originalSql'] as String,
      formattedSql: json['formattedSql'] as String,
      options: FormatterOptions.fromJson(
        json['options'] as Map<String, dynamic>,
      ),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
