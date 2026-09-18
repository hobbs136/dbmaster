/// AI Agent 工具分类器。
///
/// 单一真相源：判断某个工具调用是否属于写操作。
class AiToolClassifier {
  AiToolClassifier._();

  static const _writeToolNames = <String>{
    'smart_import',
    'execute_import',
    'create_export_task',
    'generate_test_data',
    'execute_sql',
    'run_sql',
    'modify_data',
    'insert_data',
    'update_data',
    'delete_data',
    'drop_collection',
    'drop_table',
  };

  /// 判断给定工具调用是否为写操作。
  static bool isWriteTool(String name, Map<String, dynamic> args) {
    if (_writeToolNames.contains(name)) return true;

    // 对于通用 SQL 执行工具，根据 SQL 内容判断。
    if (name == 'execute_sql' || name == 'run_sql') {
      final sql = args['sql'] as String? ?? '';
      return _isWriteSql(sql);
    }

    return false;
  }

  static bool _isWriteSql(String sql) {
    final upper = sql.trim().toUpperCase();
    if (upper.startsWith('SELECT') || upper.startsWith('SHOW') || upper.startsWith('DESCRIBE') || upper.startsWith('EXPLAIN')) {
      return false;
    }
    return true;
  }
}
