/// Redis Lua 脚本模型
///
/// 用于在客户端本地存储和管理 Redis Lua 脚本。
/// 支持全局脚本（所有连接可见）和连接级脚本（仅特定连接可见）。
class RedisScript {
  final String id;
  final String name;
  final String code;
  final List<String> tags;

  /// true = 所有 Redis 连接可见；false = 仅 [connectionId] 指定的连接可见
  final bool isGlobal;

  /// 当 [isGlobal] 为 false 时，绑定到特定连接
  final String? connectionId;

  // B3 — 脚本 SHA1(运行时由 SCRIPT LOAD 填充,供 EVALSHA 复用)
  final String? sha1;

  final DateTime createdAt;
  final DateTime modifiedAt;

  RedisScript({
    required this.id,
    required this.name,
    required this.code,
    this.tags = const [],
    this.isGlobal = true,
    this.connectionId,
    this.sha1,
    required this.createdAt,
    required this.modifiedAt,
  });

  RedisScript copyWith({
    String? id,
    String? name,
    String? code,
    List<String>? tags,
    bool? isGlobal,
    String? connectionId,
    String? sha1,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return RedisScript(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      tags: tags ?? this.tags,
      isGlobal: isGlobal ?? this.isGlobal,
      connectionId: connectionId ?? this.connectionId,
      sha1: sha1 ?? this.sha1,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'tags': tags,
        'isGlobal': isGlobal,
        'connectionId': connectionId,
        'sha1': sha1,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory RedisScript.fromJson(Map<String, dynamic> json) {
    return RedisScript(
      id: json['id'] as String,
      name: json['name'] as String,
      code: json['code'] as String,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      isGlobal: json['isGlobal'] as bool? ?? true,
      connectionId: json['connectionId'] as String?,
      sha1: json['sha1'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
    );
  }
}
