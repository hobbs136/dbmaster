/// AI 记忆条目模型（AI 记忆服务 T3）。
///
/// 记忆是 AI 助手跨会话可复用的简短事实（表语义、业务规则、用户偏好），
/// 由 `AiMemoryService` 分两个作用域持久化：
/// - [AiMemoryScope.global]：跨连接通用；
/// - [AiMemoryScope.connection]：绑定单个连接（[connectionId] 必填）。
library;

/// AI 记忆作用域。
enum AiMemoryScope {
  /// 跨连接全局记忆。
  global,

  /// 单连接记忆（[AiMemoryItem.connectionId] 必填）。
  connection,
}

/// AI 记忆来源。
enum AiMemorySource {
  /// Agent 工具链自动沉淀。
  agent,

  /// 用户在管理对话框手动维护。
  manual,
}

/// 单条 AI 记忆。
///
/// 身份字段（[id]/[scope]/[connectionId]/[source]/[createdAt]）创建后不可变；
/// [copyWith] 仅允许变更 [subject]/[content]/[updatedAt]。
class AiMemoryItem {
  const AiMemoryItem({
    required this.id,
    required this.scope,
    this.connectionId,
    this.subject,
    required this.content,
    this.source = AiMemorySource.manual,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 唯一 id（时间戳字符串，见 `AiMemoryService.add`）。
  final String id;

  /// 作用域；[AiMemoryScope.connection] 时 [connectionId] 非空。
  final AiMemoryScope scope;

  /// 所属连接 id（仅连接作用域有值）。
  final String? connectionId;

  /// 主题标签（如 `orders.status`），可空。
  final String? subject;

  /// 记忆内容（服务层截断到 500 字符）。
  final String content;

  /// 来源（agent / manual）。
  final AiMemorySource source;

  /// 创建时间（毫秒时间戳）。
  final int createdAt;

  /// 最后更新时间（毫秒时间戳）。
  final int updatedAt;

  /// 哨兵对象：区分「未传」与「显式传 null（清除字段）」。
  static const Object _unset = Object();

  AiMemoryItem copyWith({
    Object? subject = _unset,
    Object? content = _unset,
    int? updatedAt,
  }) {
    return AiMemoryItem(
      id: id,
      scope: scope,
      connectionId: connectionId,
      subject: identical(subject, _unset) ? this.subject : subject as String?,
      content: identical(content, _unset) ? this.content : content as String,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AiMemoryItem.fromJson(Map<String, dynamic> json) {
    return AiMemoryItem(
      id: json['id'] as String? ?? '',
      scope: _scopeFromName(json['scope'] as String?),
      connectionId: json['connectionId'] as String?,
      subject: json['subject'] as String?,
      content: json['content'] as String? ?? '',
      source: _sourceFromName(json['source'] as String?),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'scope': scope.name,
      'connectionId': connectionId,
      'subject': subject,
      'content': content,
      'source': source.name,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  /// 防御性解析：未知作用域/来源回退默认值（存量数据损坏不致崩）。
  static AiMemoryScope _scopeFromName(String? name) => AiMemoryScope.values
      .firstWhere((v) => v.name == name, orElse: () => AiMemoryScope.global);

  static AiMemorySource _sourceFromName(String? name) => AiMemorySource.values
      .firstWhere((v) => v.name == name, orElse: () => AiMemorySource.manual);
}
