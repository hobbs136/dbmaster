/// TDengine 列定义
class TdColumn {
  final String name;
  final String
  type; // TIMESTAMP, INT, BIGINT, FLOAT, DOUBLE, BINARY(n), NCHAR(n), BOOL
  final int? length; // 对于BINARY/NCHAR类型
  final Object? defaultValue;
  final bool isPrimaryKey; // 时间戳列自动为主键

  TdColumn({
    required this.name,
    required this.type,
    this.length,
    this.defaultValue,
    this.isPrimaryKey = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'length': length,
      'defaultValue': defaultValue,
      'isPrimaryKey': isPrimaryKey,
    };
  }

  factory TdColumn.fromJson(Map<String, dynamic> json) {
    return TdColumn(
      name: json['name'] as String,
      type: json['type'] as String,
      length: json['length'] as int?,
      defaultValue: json['defaultValue'],
      isPrimaryKey: json['isPrimaryKey'] as bool? ?? false,
    );
  }
}

/// TDengine 标签定义
class TdTag {
  final String name;
  final String type; // INT, BIGINT, FLOAT, DOUBLE, BINARY(n), NCHAR(n), BOOL
  final int? length;
  final Object? defaultValue;

  TdTag({
    required this.name,
    required this.type,
    this.length,
    this.defaultValue,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'length': length,
      'defaultValue': defaultValue,
    };
  }

  factory TdTag.fromJson(Map<String, dynamic> json) {
    return TdTag(
      name: json['name'] as String,
      type: json['type'] as String,
      length: json['length'] as int?,
      defaultValue: json['defaultValue'],
    );
  }
}

/// 超级表定义
class TdSuperTable {
  final String name;
  final List<TdColumn> columns; // 数据列 (ts + 普通列)
  final List<TdTag> tags; // 标签列
  final String? comment;
  final DateTime? createTime;

  TdSuperTable({
    required this.name,
    required this.columns,
    required this.tags,
    this.comment,
    this.createTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'columns': columns.map((c) => c.toJson()).toList(),
      'tags': tags.map((t) => t.toJson()).toList(),
      'comment': comment,
      'createTime': createTime?.toIso8601String(),
    };
  }

  factory TdSuperTable.fromJson(Map<String, dynamic> json) {
    return TdSuperTable(
      name: json['name'] as String,
      columns: (json['columns'] as List<dynamic>)
          .map((c) => TdColumn.fromJson(c as Map<String, dynamic>))
          .toList(),
      tags: (json['tags'] as List<dynamic>)
          .map((t) => TdTag.fromJson(t as Map<String, dynamic>))
          .toList(),
      comment: json['comment'] as String?,
      createTime: json['createTime'] != null
          ? DateTime.parse(json['createTime'] as String)
          : null,
    );
  }
}

/// 子表信息
class TdSubTable {
  final String name;
  final String superTableName; // 所属超级表
  final Map<String, dynamic> tags; // 标签值
  final DateTime? createTime;

  TdSubTable({
    required this.name,
    required this.superTableName,
    required this.tags,
    this.createTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'superTableName': superTableName,
      'tags': tags,
      'createTime': createTime?.toIso8601String(),
    };
  }

  factory TdSubTable.fromJson(Map<String, dynamic> json) {
    return TdSubTable(
      name: json['name'] as String,
      superTableName: json['superTableName'] as String,
      tags: json['tags'] as Map<String, dynamic>,
      createTime: json['createTime'] != null
          ? DateTime.parse(json['createTime'] as String)
          : null,
    );
  }
}

/// 子表分页结果（游标分页）
class TdSubTablePageResult {
  final List<TdSubTable> items;
  final bool hasMore;

  const TdSubTablePageResult({required this.items, required this.hasMore});
}
