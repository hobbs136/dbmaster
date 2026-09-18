import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/models/database_models.dart';
import 'config/sqlite_test_config.dart';

/// SQLiteNodes 右键菜单功能集成测试
/// 
/// 测试 SQLite 表名节点的右键菜单功能：
/// - Browse Data
/// - View Structure
/// - Copy CREATE Statement
/// - Add Column
/// - Create Index
/// - Rename Table
/// - Empty Table
/// - Drop Table
/// 
/// 由于右键菜单需要 BuildContext，本测试通过直接调用 adapter 方法
/// 来验证各菜单项生成的 SQL 和实际数据库操作。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('SQLiteNodes Context Menu Operations', () {
    late SQLiteAdapter adapter;
    late String dbPath;
    late String testTable;

    setUp(() async {
      dbPath = SQLiteTestConfig.generateTestDatabasePath();
      testTable = 'test_users';

      adapter = SQLiteAdapter();
      final connection = DatabaseConnection(
        id: 'test_ctx_menu',
        name: 'Test Context Menu',
        host: dbPath,
        port: 0,
        type: DatabaseType.sqlite,
      );

      final connected = await adapter.connect(connection);
      expect(connected, isTrue, reason: '无法创建 SQLite 数据库');

      // 创建测试表
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'TEXT', isNullable: false),
        DbColumn(name: 'email', type: 'TEXT'),
      ]);

      // 插入测试数据
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, email) VALUES (1, "Alice", "alice@test.com")',
      );
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, email) VALUES (2, "Bob", "bob@test.com")',
      );
    });

    tearDown(() async {
      await adapter.disconnect();
      await SQLiteTestConfig.cleanupDatabase(dbPath);
    });

    group('Browse Data', () {
      test('should query table data', () async {
        final result = await adapter.getTableData(testTable, limit: 100, offset: 0);
        expect(result.rows.length, 2);
        expect(result.columns, contains('id'));
        expect(result.columns, contains('name'));
        expect(result.columns, contains('email'));

        final alice = result.rows.firstWhere((r) => r['name'] == 'Alice');
        expect(alice['email'], 'alice@test.com');
      });

      test('should support pagination', () async {
        for (int i = 3; i <= 10; i++) {
          await adapter.executeQuery(
            'INSERT INTO "$testTable" (id, name, email) VALUES ($i, "User$i", "user$i@test.com")',
          );
        }

        final page1 = await adapter.getTableData(testTable, limit: 5, offset: 0);
        expect(page1.rows.length, 5);

        final page2 = await adapter.getTableData(testTable, limit: 5, offset: 5);
        expect(page2.rows.length, 5);
      });
    });

    group('View Structure', () {
      test('should get table columns', () async {
        final columns = await adapter.getTableColumns(testTable);
        expect(columns, isNotEmpty);
        expect(columns.length, 3);
        expect(columns.any((c) => c.name == 'id'), isTrue);
        expect(columns.any((c) => c.name == 'name'), isTrue);
        expect(columns.any((c) => c.name == 'email'), isTrue);

        final idCol = columns.firstWhere((c) => c.name == 'id');
        expect(idCol.isPrimaryKey, isTrue);
        expect(idCol.isNullable, isFalse);
      });

      test('should get table details', () async {
        final details = await adapter.getTableDetails(testTable);
        expect(details.name, testTable);
        expect(details.columns, isNotEmpty);
        expect(details.columns.length, 3);
      });
    });

    group('Copy CREATE Statement', () {
      test('should export database structure', () async {
        final structure = await adapter.exportDatabaseStructure('main');
        expect(structure, isNotNull);
        expect(structure.contains('CREATE TABLE'), isTrue);
        expect(structure.contains(testTable), isTrue);
      });

      test('should get CREATE TABLE sql', () async {
        final result = await adapter.executeQuery(
          "SELECT sql FROM sqlite_master WHERE type='table' AND name='$testTable'",
        );
        expect(result.rows.isNotEmpty, isTrue);
        expect(result.rows.first['sql'], isNotNull);
      });
    });

    group('Add Column', () {
      test('should add column successfully', () async {
        final added = await adapter.addColumn(
          testTable,
          DbColumn(name: 'phone', type: 'TEXT', isNullable: true),
        );
        expect(added, isTrue);

        final columns = await adapter.getTableColumns(testTable);
        expect(columns.length, 4);
        expect(columns.any((c) => c.name == 'phone'), isTrue);
      });

      test('should add column with default value', () async {
        final added = await adapter.addColumn(
          testTable,
          DbColumn(name: 'status', type: 'TEXT', isNullable: false, defaultValue: '\'active\''),
        );
        expect(added, isTrue);

        final columns = await adapter.getTableColumns(testTable);
        final statusCol = columns.firstWhere((c) => c.name == 'status');
        expect(statusCol.defaultValue, isNotNull);
      });
    });

    group('Create Index', () {
      test('should create index', () async {
        final created = await adapter.createIndex(testTable, 'idx_name', ['name']);
        expect(created, isTrue);

        final indexes = await adapter.getTableIndexes(testTable);
        expect(indexes.any((i) => i.name == 'idx_name'), isTrue);
      });

      test('should create unique index', () async {
        final created = await adapter.createIndex(
          testTable,
          'idx_email_unique',
          ['email'],
          unique: true,
        );
        expect(created, isTrue);

        final indexes = await adapter.getTableIndexes(testTable);
        final idx = indexes.firstWhere((i) => i.name == 'idx_email_unique');
        expect(idx.isUnique, isTrue);
      });

      test('should create composite index', () async {
        final created = await adapter.createIndex(
          testTable,
          'idx_name_email',
          ['name', 'email'],
        );
        expect(created, isTrue);

        final indexes = await adapter.getTableIndexes(testTable);
        final idx = indexes.firstWhere((i) => i.name == 'idx_name_email');
        expect(idx.columns.length, 2);
      });
    });

    group('Rename Table', () {
      test('should rename table', () async {
        final newName = '${testTable}_renamed';
        final renamed = await adapter.renameTable(testTable, newName);
        expect(renamed, isTrue);

        final tables = await adapter.getTables();
        expect(tables, contains(newName));
        expect(tables, isNot(contains(testTable)));
      });

      test('should preserve data after rename', () async {
        final newName = '${testTable}_renamed';
        await adapter.renameTable(testTable, newName);

        final count = await adapter.getTableRowCount(newName);
        expect(count, 2);

        final result = await adapter.executeQuery('SELECT * FROM "$newName"');
        expect(result.rows.length, 2);
      });
    });

    group('Empty Table', () {
      test('should empty table preserving structure', () async {
        var count = await adapter.getTableRowCount(testTable);
        expect(count, 2);

        final emptied = await adapter.truncateTable(testTable);
        expect(emptied, isTrue);

        count = await adapter.getTableRowCount(testTable);
        expect(count, 0);

        // 验证表结构仍存在
        final columns = await adapter.getTableColumns(testTable);
        expect(columns.isNotEmpty, isTrue);
        expect(columns.length, 3);
      });

      test('should allow inserting after empty', () async {
        await adapter.truncateTable(testTable);

        await adapter.executeQuery(
          'INSERT INTO "$testTable" (id, name, email) VALUES (99, "NewUser", "new@test.com")',
        );

        final count = await adapter.getTableRowCount(testTable);
        expect(count, 1);
      });
    });

    group('Drop Table', () {
      test('should drop table', () async {
        final dropped = await adapter.dropTable(testTable);
        expect(dropped, isTrue);

        final tables = await adapter.getTables();
        expect(tables, isNot(contains(testTable)));
      });

      test('should fail to query dropped table', () async {
        await adapter.dropTable(testTable);

        expect(
          () => adapter.executeQuery('SELECT * FROM "$testTable"'),
          throwsException,
        );
      });
    });

    group('Integration', () {
      test('should perform full workflow', () async {
        // 1. 添加列
        await adapter.addColumn(
          testTable,
          DbColumn(name: 'age', type: 'INTEGER', isNullable: true),
        );

        // 2. 创建索引
        await adapter.createIndex(testTable, 'idx_email', ['email']);

        // 3. 更新数据
        await adapter.executeQuery(
          'UPDATE "$testTable" SET age = 30 WHERE id = 1',
        );

        // 4. 验证
        final result = await adapter.executeQuery('SELECT * FROM "$testTable" WHERE id = 1');
        expect(result.rows.first['age'], 30);

        // 5. 重命名
        final newName = '${testTable}_final';
        await adapter.renameTable(testTable, newName);

        // 6. 验证重命名后数据
        final count = await adapter.getTableRowCount(newName);
        expect(count, 2);

        // 7. 导出结构
        final structure = await adapter.exportDatabaseStructure('main');
        expect(structure.contains(newName), isTrue);

        // 8. 删除
        await adapter.dropTable(newName);

        final tables = await adapter.getTables();
        expect(tables, isNot(contains(newName)));
      });
    });
  });
}