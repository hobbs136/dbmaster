// ============================================================================
// SQLite + MySQL JSON columnTypes E2E（跨库验证）
// SQLite: 启发式检测（前 5 行 ≥80% 可解析为 JSON → json_detected）
// MySQL: result.cols type=0xf5 → json
// ============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';

import 'config/sqlite_test_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SQLite JSON columnTypes E2E（T032 启发式）', () {
    late SQLiteAdapter adapter;
    late String dbPath;
    late String tableName;

    setUp(() async {
      adapter = SQLiteAdapter();
      dbPath = SQLiteTestConfig.generateTestDatabasePath();
      tableName = SQLiteTestConfig.generateTestTableName();
      final conn = DatabaseConnection(
        id: 'sqlite_json_e2e',
        name: 'SQLite JSON E2E',
        host: dbPath,
        port: 0,
        type: DatabaseType.sqlite,
      );
      final connected = await adapter.connect(conn);
      expect(connected, isTrue, reason: '无法创建 SQLite 测试库');

      // 造表：含 JSON 文本列 + 普通文本列
      await adapter.executeQuery(
        'CREATE TABLE "$tableName" (id INTEGER PRIMARY KEY, profile TEXT, note TEXT)',
      );
      // 5 行 profile 都是合法 JSON（≥80% → 应识别为 json_detected）
      await adapter.executeQuery(
        "INSERT INTO \"$tableName\" (id, profile, note) VALUES "
        "(1, '{\"age\":30}', 'hello'), "
        "(2, '{\"age\":25}', 'world'), "
        "(3, '{\"age\":35}', 'foo'), "
        "(4, '{\"age\":40}', 'bar'), "
        "(5, '{\"age\":45}', 'baz')",
      );
    });

    tearDown(() async {
      try {
        await adapter.disconnect();
      } catch (_) {}
      await SQLiteTestConfig.cleanupDatabase(dbPath);
    });

    test('T032: 高 JSON 占比列识别为 json_detected', () async {
      final result = await adapter.executeQuery(
        'SELECT id, profile, note FROM "$tableName"',
      );
      expect(result.columnTypes, isNotNull, reason: '应返回 columnTypes');
      expect(result.columnTypes!['profile'], 'json_detected',
          reason: 'profile 列 100% 合法 JSON → 应识别');
      // note 列纯文本，不应识别为 JSON
      expect(result.columnTypes!['note'], isNot('json_detected'));
      print('SQLite columnTypes: ${result.columnTypes}');
    });

    test('T032: 低 JSON 占比列不误判', () async {
      // 造另一张表：只有 1/5 行像 JSON（20% < 80% 阈值）
      final t2 = '${tableName}_mixed';
      await adapter.executeQuery(
        'CREATE TABLE "$t2" (id INTEGER PRIMARY KEY, val TEXT)',
      );
      await adapter.executeQuery(
        "INSERT INTO \"$t2\" (id, val) VALUES "
        "(1, '{\"a\":1}'), " // 唯一一行 JSON
        "(2, 'plain text'), "
        "(3, 'hello'), "
        "(4, 'world'), "
        "(5, 'foo')",
      );
      final result = await adapter.executeQuery('SELECT val FROM "$t2"');
      // 1/5 = 20% < 80%，不应识别为 JSON
      if (result.columnTypes != null && result.columnTypes!.containsKey('val')) {
        expect(result.columnTypes!['val'], isNot('json_detected'),
            reason: '仅 20% 行是 JSON，不应误判');
      }
      // 不在 columnTypes 里也 acceptable（启发式不标）
    });

    test('T032: SQLite isJsonColumn 启发式判定', () async {
      final isJson = await adapter.isJsonColumn(tableName, 'profile');
      expect(isJson, isTrue, reason: 'profile 应识别为 JSON 列');
      final notJson = await adapter.isJsonColumn(tableName, 'note');
      expect(notJson, isFalse, reason: 'note 不应识别为 JSON 列');
    });

    test('T032: US4 SQLite json_extract SQL 真实执行', () async {
      // 验证 SQLite 的 json_extract 语法能真实执行（JsonExtractionSql 单测已验证生成）
      final directSql =
          'SELECT id, profile, json_extract(profile, \'\$.age\') AS age FROM "$tableName"';
      final result = await adapter.executeQuery(directSql);
      expect(result.rows.length, 5);
      // 提取的 age 值（SQLite json_extract 返回值）
      expect(result.rows.first['age'], isNotNull);
      print('SQLite json_extract 第一行 age: ${result.rows.first['age']}');
    });
  });
}
