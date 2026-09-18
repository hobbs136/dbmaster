/// 侧边栏树节点类型，用于 AI 分析。
enum AiTreeNodeType {
  table,
  database,
  connection,
  view,
  procedure,
  function,
  trigger,
  event,
}

/// 描述一个待进行 AI 分析的侧边栏树节点。
class AiTreeNodeContext {
  final AiTreeNodeType type;
  final String connectionId;
  final String? databaseName;
  final String nodeName;

  const AiTreeNodeContext({
    required this.type,
    required this.connectionId,
    this.databaseName,
    required this.nodeName,
  });

  /// 当前节点是否属于 MySQL/Doris 方言。
  ///
  /// MySQL/Doris 节点使用 MysqlAiContextCollector 获取丰富上下文；
  /// 其他 SQL 数据库通过 AiAdapterMixin.getAiSchemaSummary() 获取基础架构摘要。
  bool get isMySqlDialect => true;

  /// 生成简洁的节点描述，用于 Prompt 标题。
  String get displayLabel {
    final db = databaseName;
    if (db != null && db.isNotEmpty) {
      return '$db.$nodeName';
    }
    return nodeName;
  }
}
