import 'dart:io';

/// SQLite 集成测试配置
///
/// SQLite 是本地文件数据库，使用临时文件进行测试
class SQLiteTestConfig {
  /// 生成唯一测试数据库文件路径
  static String generateTestDatabasePath() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempDir = Directory.systemTemp.path;
    return '$tempDir/dbmaster_test_$timestamp.db';
  }

  /// 生成唯一表名，避免并行测试冲突
  static String generateTestTableName() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'test_table_$timestamp';
  }

  /// 清理测试数据库文件
  static Future<void> cleanupDatabase(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      // 同时删除可能的 -journal 和 -shm 文件
      final journalFile = File('$path-journal');
      final shmFile = File('$path-shm');
      final walFile = File('$path-wal');
      if (await journalFile.exists()) await journalFile.delete();
      if (await shmFile.exists()) await shmFile.delete();
      if (await walFile.exists()) await walFile.delete();
    } catch (_) {}
  }
}
