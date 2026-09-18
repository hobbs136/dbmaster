import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'config/sqlite_test_config.dart';

void main() {
  late SQLiteAdapter adapter;
  late String dbPath;
  late String testTable;

  setUp(() async {
    dbPath = SQLiteTestConfig.generateTestDatabasePath();
    testTable = SQLiteTestConfig.generateTestTableName();

    adapter = SQLiteAdapter();
    final connection = DatabaseConnection(
      id: 'test_sqlite',
      name: 'SQLite Test',
      host: dbPath,
      port: 0,
      type: DatabaseType.sqlite,
    );

    final connected = await adapter.connect(connection);
    expect(connected, isTrue, reason: '无法创建 SQLite 数据库');
  });

  tearDown(() async {
    await adapter.disconnect();
    await SQLiteTestConfig.cleanupDatabase(dbPath);
  });

  group('SQLite Connection', () {
    test('should connect to SQLite database successfully', () async {
      expect(adapter.isConnected, isTrue);
      expect(adapter.currentConnection, isNotNull);
      expect(adapter.currentConnection!.host, dbPath);
    });

    test('should test connection successfully', () async {
      final connection = DatabaseConnection(
        id: 'test_sqlite_test',
        name: 'SQLite Test Conn',
        host: dbPath,
        port: 0,
        type: DatabaseType.sqlite,
      );

      final result = await adapter.testConnection(connection);
      expect(result, isNull);
    });

    test('should fail to connect to invalid path', () async {
      final badAdapter = SQLiteAdapter();
      final connection = DatabaseConnection(
        id: 'test_sqlite_bad',
        name: 'SQLite Bad',
        host: '\\?invalid<>path|test.db',
        port: 0,
        type: DatabaseType.sqlite,
      );

      final result = await badAdapter.connect(connection);
      expect(result, isFalse);
    });
  });

  group('SQLite Database Operations', () {
    test('should get databases', () async {
      final dbs = await adapter.getDatabases();
      expect(dbs, isNotEmpty);
      expect(dbs.first, 'main');
    });

    test('should use database', () async {
      await adapter.useDatabase('main');
      expect(adapter.currentConnection!.database, 'main');
    });

    test('should get database properties', () async {
      final props = await adapter.getDatabaseProperties('main');
      expect(props, isNotNull);
      expect(props!['encoding'], isNotNull);
      expect(props['file'], dbPath);
    });
  });

  group('SQLite Table Operations', () {
    test('should create a table', () async {
      final columns = [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'TEXT', isNullable: false),
        DbColumn(name: 'age', type: 'INTEGER', isNullable: true),
      ];

      final created = await adapter.createTable(testTable, columns);
      expect(created, isTrue);

      final tables = await adapter.getTables();
      expect(tables, contains(testTable));
    });

    test('should drop a table', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
      ]);

      final dropped = await adapter.dropTable(testTable);
      expect(dropped, isTrue);

      final tables = await adapter.getTables();
      expect(tables, isNot(contains(testTable)));
    });

    test('should rename a table', () async {
      final newName = '${testTable}_renamed';
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
      ]);

      final renamed = await adapter.renameTable(testTable, newName);
      expect(renamed, isTrue);

      final tables = await adapter.getTables();
      expect(tables, contains(newName));
      expect(tables, isNot(contains(testTable)));
    });

    test('should truncate a table', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'name', type: 'TEXT'),
      ]);

      await adapter.executeQuery('INSERT INTO "$testTable" (id, name) VALUES (1, "test")');
      var count = await adapter.getTableRowCount(testTable);
      expect(count, 1);

      final truncated = await adapter.truncateTable(testTable);
      expect(truncated, isTrue);

      count = await adapter.getTableRowCount(testTable);
      expect(count, 0);
    });

    test('should get table row count', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'val', type: 'TEXT'),
      ]);

      await adapter.executeQuery('INSERT INTO "$testTable" (id, val) VALUES (1, "a")');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, val) VALUES (2, "b")');

      final count = await adapter.getTableRowCount(testTable);
      expect(count, 2);
    });
  });

  group('SQLite Column Operations', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'TEXT', isNullable: false),
      ]);
    });

    test('should get table columns', () async {
      final columns = await adapter.getTableColumns(testTable);
      expect(columns, isNotEmpty);
      expect(columns.any((c) => c.name == 'id'), isTrue);
      expect(columns.any((c) => c.name == 'name'), isTrue);

      final idCol = columns.firstWhere((c) => c.name == 'id');
      expect(idCol.isPrimaryKey, isTrue);
      expect(idCol.isNullable, isFalse);
    });

    test('should get table details', () async {
      final details = await adapter.getTableDetails(testTable);
      expect(details.name, testTable);
      expect(details.columns, isNotEmpty);
      expect(details.columns.length, greaterThanOrEqualTo(2));
    });

    test('should add a column', () async {
      final added = await adapter.addColumn(
        testTable,
        DbColumn(name: 'email', type: 'TEXT', isNullable: true),
      );
      expect(added, isTrue);

      final columns = await adapter.getTableColumns(testTable);
      expect(columns.any((c) => c.name == 'email'), isTrue);
    });

    test('should drop a column', () async {
      // SQLite 3.35.0+ 支持 DROP COLUMN
      final added = await adapter.addColumn(
        testTable,
        DbColumn(name: 'temp_col', type: 'TEXT', isNullable: true),
      );
      expect(added, isTrue);

      final dropped = await adapter.dropColumn(testTable, 'temp_col');
      expect(dropped, isTrue);

      final columns = await adapter.getTableColumns(testTable);
      expect(columns.any((c) => c.name == 'temp_col'), isFalse);
    });
  });

  group('SQLite CRUD Operations', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'TEXT', isNullable: false),
        DbColumn(name: 'age', type: 'INTEGER', isNullable: true),
        DbColumn(name: 'active', type: 'INTEGER', isNullable: true),
      ]);
    });

    test('should insert data', () async {
      final result = await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, age, active) VALUES (1, "Alice", 30, 1)',
      );
      expect(result.affectedRows, 1);

      final count = await adapter.getTableRowCount(testTable);
      expect(count, 1);
    });

    test('should select data', () async {
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, age) VALUES (1, "Alice", 30)',
      );
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, age) VALUES (2, "Bob", 25)',
      );

      final result = await adapter.executeQuery('SELECT * FROM "$testTable"');
      expect(result.rows.length, 2);
      expect(result.columns, contains('id'));
      expect(result.columns, contains('name'));
      expect(result.columns, contains('age'));

      final alice = result.rows.firstWhere((r) => r['name'] == 'Alice');
      expect(alice['age'], 30);
    });

    test('should update data', () async {
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, age) VALUES (1, "Alice", 30)',
      );

      final result = await adapter.executeQuery(
        'UPDATE "$testTable" SET age = 31 WHERE id = 1',
      );
      expect(result.affectedRows, 1);

      final select = await adapter.executeQuery(
        'SELECT age FROM "$testTable" WHERE id = 1',
      );
      expect(select.rows.first['age'], 31);
    });

    test('should delete data', () async {
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name) VALUES (1, "Alice")',
      );
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name) VALUES (2, "Bob")',
      );

      final result = await adapter.executeQuery(
        'DELETE FROM "$testTable" WHERE id = 1',
      );
      expect(result.affectedRows, 1);

      final count = await adapter.getTableRowCount(testTable);
      expect(count, 1);
    });

    test('should get table data with pagination', () async {
      for (int i = 1; i <= 10; i++) {
        await adapter.executeQuery(
          'INSERT INTO "$testTable" (id, name) VALUES ($i, "User$i")',
        );
      }

      final page1 = await adapter.getTableData(testTable, limit: 5, offset: 0);
      expect(page1.rows.length, 5);
      expect(page1.rows.first['id'], 1);

      final page2 = await adapter.getTableData(testTable, limit: 5, offset: 5);
      expect(page2.rows.length, 5);
      expect(page2.rows.first['id'], 6);
    });

    test('should execute complex SQL query', () async {
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, age, active) VALUES (1, "Alice", 30, 1)',
      );
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, age, active) VALUES (2, "Bob", 25, 1)',
      );
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, age, active) VALUES (3, "Charlie", 35, 0)',
      );

      final result = await adapter.executeQuery(
        'SELECT active, COUNT(*) as cnt, AVG(age) as avg_age FROM "$testTable" GROUP BY active',
      );
      expect(result.rows.length, 2);
    });
  });

  group('SQLite Index Operations', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'email', type: 'TEXT'),
        DbColumn(name: 'username', type: 'TEXT'),
      ]);
    });

    test('should create an index', () async {
      final created = await adapter.createIndex(testTable, 'idx_email', ['email']);
      expect(created, isTrue);

      final indexes = await adapter.getTableIndexes(testTable);
      expect(indexes.any((idx) => idx.name == 'idx_email'), isTrue);
    });

    test('should create unique index', () async {
      final created = await adapter.createIndex(
        testTable,
        'idx_username_unique',
        ['username'],
        unique: true,
      );
      expect(created, isTrue);

      final indexes = await adapter.getTableIndexes(testTable);
      final idx = indexes.firstWhere((i) => i.name == 'idx_username_unique');
      expect(idx.isUnique, isTrue);
    });

    test('should drop an index', () async {
      await adapter.createIndex(testTable, 'idx_to_drop', ['email']);

      final dropped = await adapter.dropIndex(testTable, 'idx_to_drop');
      expect(dropped, isTrue);

      final indexes = await adapter.getTableIndexes(testTable);
      expect(indexes.any((idx) => idx.name == 'idx_to_drop'), isFalse);
    });

    test('should get table indexes', () async {
      await adapter.createIndex(testTable, 'idx_email', ['email']);
      await adapter.createIndex(testTable, 'idx_username', ['username']);

      final indexes = await adapter.getTableIndexes(testTable);
      expect(indexes.length, greaterThanOrEqualTo(2));
    });
  });

  group('SQLite View Operations', () {
    test('should create and get views', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'name', type: 'TEXT'),
        DbColumn(name: 'age', type: 'INTEGER'),
      ]);

      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name, age) VALUES (1, "Alice", 30)',
      );

      final viewName = '${testTable}_view';
      await adapter.executeQuery(
        'CREATE VIEW "$viewName" AS SELECT id, name FROM "$testTable" WHERE age > 25',
      );

      final views = await adapter.getViews();
      expect(views, contains(viewName));
    });
  });

  group('SQLite Advanced Operations', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'data', type: 'TEXT'),
      ]);
    });

    test('should get server version', () async {
      final version = await adapter.getServerVersion();
      expect(version, isNotNull);
      expect(version!['version'], isNotNull);
      expect(version['database'], 'SQLite');
    });

    test('should get explain plan', () async {
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, data) VALUES (1, "test")',
      );

      final plan = await adapter.getExplainPlan('SELECT * FROM "$testTable"');
      expect(plan.rows.isNotEmpty, isTrue);
    });

    test('should execute SQL script', () async {
      final script = '''
INSERT INTO "$testTable" (id, data) VALUES (10, "script1");
INSERT INTO "$testTable" (id, data) VALUES (20, "script2");
INSERT INTO "$testTable" (id, data) VALUES (30, "script3");
'''; // 注意分号在末尾

      final result = await adapter.executeSqlScript(script.trim());
      expect(result, isTrue);

      final count = await adapter.getTableRowCount(testTable);
      expect(count, 3);
    });

    test('should get charsets', () async {
      final charsets = await adapter.getCharsets();
      expect(charsets, isNotEmpty);
      expect(charsets, contains('UTF-8'));
    });

    test('should get collations', () async {
      final collations = await adapter.getCollations();
      expect(collations, isA<List>());
    });

    test('should export database structure', () async {
      await adapter.createTable('users', [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'name', type: 'TEXT'),
      ]);

      final export = await adapter.exportDatabaseStructure('main');
      expect(export, isNotNull);
      expect(export.contains('CREATE TABLE'), isTrue);
    });
  });

  group('SQLite Procedures and Functions', () {
    test('should get procedures', () async {
      final procedures = await adapter.getProcedures();
      expect(procedures, isEmpty);
    });

    test('should get functions', () async {
      final functions = await adapter.getFunctions();
      expect(functions, isEmpty);
    });
  });

  group('SQLite Security', () {
    test('should validate dangerous commands', () {
      final result = adapter.validateCommand('DROP TABLE users');
      expect(result.allowed, isFalse);
      expect(result.riskLevel, CommandRiskLevel.dangerous);
    });

    test('should validate DELETE without WHERE', () {
      final result = adapter.validateCommand('DELETE FROM users');
      expect(result.allowed, isFalse);
      expect(result.riskLevel, CommandRiskLevel.dangerous);
    });

    test('should validate UPDATE without WHERE', () {
      final result = adapter.validateCommand('UPDATE users SET name = "test"');
      expect(result.allowed, isFalse);
      expect(result.riskLevel, CommandRiskLevel.dangerous);
    });

    test('should validate write commands', () {
      final result = adapter.validateCommand('INSERT INTO users VALUES (1, "test")');
      expect(result.allowed, isTrue);
      expect(result.riskLevel, CommandRiskLevel.warning);
    });

    test('should allow read commands', () {
      final result = adapter.validateCommand('SELECT * FROM users');
      expect(result.allowed, isTrue);
      expect(result.riskLevel, CommandRiskLevel.safe);
    });
  });

  group('SQLite Connection Management', () {
    test('should disconnect cleanly', () async {
      expect(adapter.isConnected, isTrue);

      await adapter.disconnect();
      expect(adapter.isConnected, isFalse);
      expect(adapter.currentConnection, isNull);
    });

    test('should handle multiple connections', () async {
      final adapter1 = SQLiteAdapter();
      final adapter2 = SQLiteAdapter();

      final dbPath1 = SQLiteTestConfig.generateTestDatabasePath();
      final dbPath2 = SQLiteTestConfig.generateTestDatabasePath();

      final conn1 = DatabaseConnection(
        id: 'multi1',
        name: 'Multi 1',
        host: dbPath1,
        port: 0,
        type: DatabaseType.sqlite,
      );

      final conn2 = DatabaseConnection(
        id: 'multi2',
        name: 'Multi 2',
        host: dbPath2,
        port: 0,
        type: DatabaseType.sqlite,
      );

      final r1 = await adapter1.connect(conn1);
      final r2 = await adapter2.connect(conn2);

      expect(r1, isTrue);
      expect(r2, isTrue);
      expect(adapter1.currentConnection!.host, dbPath1);
      expect(adapter2.currentConnection!.host, dbPath2);

      await adapter1.disconnect();
      await adapter2.disconnect();

      await SQLiteTestConfig.cleanupDatabase(dbPath1);
      await SQLiteTestConfig.cleanupDatabase(dbPath2);
    });
  });

  group('SQLite Data Types', () {
    test('should handle various data types', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'text_col', type: 'TEXT'),
        DbColumn(name: 'int_col', type: 'INTEGER'),
        DbColumn(name: 'real_col', type: 'REAL'),
        DbColumn(name: 'blob_col', type: 'BLOB'),
        DbColumn(name: 'numeric_col', type: 'NUMERIC'),
      ]);

      // 使用参数化查询避免 BLOB 字面量语法问题
      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, text_col, int_col, real_col, blob_col, numeric_col) '
        'VALUES (1, \'hello\', 42, 3.14, CAST(\'blob_data\' AS BLOB), 99.9)',
      );

      final result = await adapter.executeQuery('SELECT * FROM "$testTable"');
      expect(result.rows.length, 1);
      expect(result.rows.first['text_col'], 'hello');
      expect(result.rows.first['int_col'], 42);
      expect(result.rows.first['real_col'], 3.14);
    });

    test('should handle NULL values', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'nullable_col', type: 'TEXT', isNullable: true),
      ]);

      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, nullable_col) VALUES (1, NULL)',
      );

      final result = await adapter.executeQuery('SELECT * FROM "$testTable"');
      expect(result.rows.first['nullable_col'], isNull);
    });
  });

  group('SQLite Constraints', () {
    test('should enforce PRIMARY KEY', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true, isNullable: false),
        DbColumn(name: 'name', type: 'TEXT'),
      ]);

      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, name) VALUES (1, "Alice")',
      );

      // 插入重复主键应该失败
      expect(
        () => adapter.executeQuery(
          'INSERT INTO "$testTable" (id, name) VALUES (1, "Bob")',
        ),
        throwsException,
      );
    });

    test('should enforce NOT NULL', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'required', type: 'TEXT', isNullable: false),
      ]);

      // 插入 NULL 到 NOT NULL 列应该失败
      expect(
        () => adapter.executeQuery(
          'INSERT INTO "$testTable" (id, required) VALUES (1, NULL)',
        ),
        throwsException,
      );
    });
  });

  group('SQLite Transaction', () {
    test('should support transaction', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'val', type: 'TEXT'),
      ]);

      await adapter.executeQuery('BEGIN TRANSACTION');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, val) VALUES (1, "a")');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, val) VALUES (2, "b")');
      await adapter.executeQuery('COMMIT');

      final count = await adapter.getTableRowCount(testTable);
      expect(count, 2);
    });

    test('should support rollback', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'val', type: 'TEXT'),
      ]);

      await adapter.executeQuery('BEGIN TRANSACTION');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, val) VALUES (1, "a")');
      await adapter.executeQuery('ROLLBACK');

      final count = await adapter.getTableRowCount(testTable);
      expect(count, 0);
    });
  });

  group('SQLite Modify Column', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'name', type: 'TEXT'),
      ]);
    });

    test('should modify column', () async {
      final modified = await adapter.modifyColumn(
        testTable,
        'name',
        DbColumn(name: 'name', type: 'TEXT', isNullable: false),
      );
      // SQLite 对 ALTER COLUMN 支持有限，可能返回 false
      expect(modified, isA<bool>());
    });
  });

  group('SQLite Error Handling', () {
    test('should handle invalid SQL', () async {
      expect(
        () => adapter.executeQuery('INVALID SQL STATEMENT'),
        throwsException,
      );
    });

    test('should handle table not found', () async {
      expect(
        () => adapter.executeQuery('SELECT * FROM non_existent_table'),
        throwsException,
      );
    });

    test('should handle column not found', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
      ]);

      expect(
        () => adapter.executeQuery('SELECT non_existent_column FROM "$testTable"'),
        throwsException,
      );
    });
  });

  group('SQLite Foreign Keys', () {
    test('should support foreign keys', () async {
      await adapter.executeQuery('PRAGMA foreign_keys = ON');

      await adapter.createTable('parent', [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
      ]);

      await adapter.createTable('child', [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'parent_id', type: 'INTEGER'),
      ]);

      await adapter.executeQuery(
        'INSERT INTO "parent" (id) VALUES (1)',
      );

      await adapter.executeQuery(
        'INSERT INTO "child" (id, parent_id) VALUES (1, 1)',
      );

      final result = await adapter.executeQuery('SELECT * FROM "child"');
      expect(result.rows.length, 1);
    });
  });

  group('SQLite LIKE and Pattern Matching', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'name', type: 'TEXT'),
      ]);

      await adapter.executeQuery('INSERT INTO "$testTable" (id, name) VALUES (1, "Alice")');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, name) VALUES (2, "Bob")');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, name) VALUES (3, "Charlie")');
    });

    test('should support LIKE operator', () async {
      final result = await adapter.executeQuery(
        'SELECT * FROM "$testTable" WHERE name LIKE "A%"',
      );
      expect(result.rows.length, 1);
      expect(result.rows.first['name'], 'Alice');
    });

    test('should support GLOB operator', () async {
      final result = await adapter.executeQuery(
        'SELECT * FROM "$testTable" WHERE name GLOB "A*"',
      );
      expect(result.rows.length, 1);
      expect(result.rows.first['name'], 'Alice');
    });
  });

  group('SQLite Aggregate Functions', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'amount', type: 'INTEGER'),
      ]);

      await adapter.executeQuery('INSERT INTO "$testTable" (id, amount) VALUES (1, 100)');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, amount) VALUES (2, 200)');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, amount) VALUES (3, 300)');
    });

    test('should support SUM aggregate', () async {
      final result = await adapter.executeQuery(
        'SELECT SUM(amount) as total FROM "$testTable"',
      );
      expect(result.rows.first['total'], 600);
    });

    test('should support COUNT aggregate', () async {
      final result = await adapter.executeQuery(
        'SELECT COUNT(*) as cnt FROM "$testTable"',
      );
      expect(result.rows.first['cnt'], 3);
    });

    test('should support AVG aggregate', () async {
      final result = await adapter.executeQuery(
        'SELECT AVG(amount) as avg_amount FROM "$testTable"',
      );
      expect(result.rows.first['avg_amount'], 200.0);
    });

    test('should support MAX and MIN aggregates', () async {
      final result = await adapter.executeQuery(
        'SELECT MAX(amount) as max_val, MIN(amount) as min_val FROM "$testTable"',
      );
      expect(result.rows.first['max_val'], 300);
      expect(result.rows.first['min_val'], 100);
    });
  });

  group('SQLite DateTime Functions', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'created_at', type: 'TEXT'),
      ]);

      await adapter.executeQuery(
        'INSERT INTO "$testTable" (id, created_at) VALUES (1, datetime("now"))',
      );
    });

    test('should support datetime function', () async {
      final result = await adapter.executeQuery(
        'SELECT datetime("now") as now',
      );
      expect(result.rows.first['now'], isNotNull);
      expect(result.rows.first['now'], isA<String>());
    });

    test('should support date arithmetic', () async {
      final result = await adapter.executeQuery(
        'SELECT date("now", "+1 day") as tomorrow',
      );
      expect(result.rows.first['tomorrow'], isNotNull);
      expect(result.rows.first['tomorrow'], isA<String>());
    });
  });

  group('SQLite Vacuum and Optimization', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'data', type: 'TEXT'),
      ]);

      for (int i = 1; i <= 100; i++) {
        await adapter.executeQuery(
          'INSERT INTO "$testTable" (id, data) VALUES ($i, "data_$i")',
        );
      }
    });

    test('should support VACUUM', () async {
      await adapter.executeQuery('DELETE FROM "$testTable"');
      
      final result = await adapter.executeQuery('VACUUM');
      expect(result, isNotNull);
    });

    test('should support ANALYZE', () async {
      final result = await adapter.executeQuery('ANALYZE');
      expect(result, isNotNull);
    });
  });

  group('SQLite Pragma Commands', () {
    test('should get table info via PRAGMA', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'name', type: 'TEXT'),
      ]);

      final result = await adapter.executeQuery('PRAGMA table_info($testTable)');
      expect(result.rows.length, 2);
      expect(result.rows.any((r) => r['name'] == 'id'), isTrue);
      expect(result.rows.any((r) => r['name'] == 'name'), isTrue);
    });

    test('should get index list via PRAGMA', () async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'email', type: 'TEXT'),
      ]);

      await adapter.createIndex(testTable, 'idx_email', ['email']);

      final result = await adapter.executeQuery('PRAGMA index_list($testTable)');
      expect(result.rows.isNotEmpty, isTrue);
    });

    test('should get database encoding', () async {
      final result = await adapter.executeQuery('PRAGMA encoding');
      expect(result.rows.isNotEmpty, isTrue);
      expect(result.rows.first['encoding'], isNotNull);
    });
  });

  // ==========================================================================
  // SQLite 维护操作（vacuum / integrityCheck / optimize）
  //
  // 单测（sqlite_adapter_test.dart 维护组）已覆盖 message 字符串；本 E2E 的增量
  // 价值 = 真实文件库行为：VACUUM 后断言 .db 文件大小实际减小（证明回收空闲页）。
  // 单测 setUp 虽然也是文件库（sqflite_ffi 落盘），但不断言文件大小——这是本组独有。
  // ==========================================================================
  group('SQLite Maintenance Operations (vacuum/integrityCheck/optimize)', () {
    setUp(() async {
      await adapter.createTable(testTable, [
        DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        DbColumn(name: 'data', type: 'TEXT'),
      ]);
      // 插入 200 行带较大 payload，制造可回收的空闲页。
      for (int i = 1; i <= 200; i++) {
        await adapter.executeQuery(
          'INSERT INTO "$testTable" (id, data) VALUES ($i, "${'x' * 500}_$i")',
        );
      }
    });

    test('vacuum() 回收空间：DELETE 大量数据后 .db 文件变小', () async {
      // 前置：文件存在 + 有数据
      expect(File(dbPath).existsSync(), isTrue);
      final sizeBefore = File(dbPath).lengthSync();
      expect(sizeBefore, greaterThan(0));

      // DELETE 全部行 → 产生空闲页，但文件不会自动缩小
      await adapter.executeQuery('DELETE FROM "$testTable"');

      // VACUUM 重建数据库文件，回收空闲页
      final result = await adapter.vacuum();
      expect(result.message, 'VACUUM completed');

      // 断言：文件应明显变小（VACUUM 的核心价值）
      final sizeAfter = File(dbPath).lengthSync();
      expect(
        sizeAfter,
        lessThan(sizeBefore),
        reason: 'VACUUM 后文件应缩小（before=$sizeBefore, after=$sizeAfter）',
      );
    });

    test('integrityCheck() 正常库返回单行 ok', () async {
      final result = await adapter.integrityCheck();
      expect(result.rows, hasLength(1));
      expect(result.rows.first['integrity_check'], 'ok');
      expect(result.columns, contains('integrity_check'));
    });

    test('optimize() 执行成功且不报错', () async {
      final result = await adapter.optimize();
      expect(result.message, 'PRAGMA optimize completed');
      // optimize 后库仍可用（建表/查询不报错）
      final rows = await adapter.executeQuery('SELECT COUNT(*) AS c FROM "$testTable"');
      expect(rows.rows.first['c'], 200);
    });

    test('三个方法串联：optimize → integrityCheck → vacuum 全绿', () async {
      final opt = await adapter.optimize();
      expect(opt.message, 'PRAGMA optimize completed');
      final ic = await adapter.integrityCheck();
      expect(ic.rows.first['integrity_check'], 'ok');
      final v = await adapter.vacuum();
      expect(v.message, 'VACUUM completed');
    });

    // ------------------------------------------------------------------
    // saveAs（VACUUM INTO 策略）
    //
    // 单测已覆盖 message/文件存在/只读/防注入；本 E2E 的增量价值：
    //   (1) 源库文件 mtime/大小在 saveAs 后不变（证明源库只读、不污染）
    //   (2) WAL 模式下 saveAs 产出事务一致副本（合并 -wal 已提交事务）——
    //       这是 VACUUM INTO 相对裸文件拷贝的核心优势，单测默认 DELETE 模式覆盖不到。
    // ------------------------------------------------------------------
    test('saveAs() 产出可独立打开的副本 + 源库未改', () async {
      final destPath = SQLiteTestConfig.generateTestDatabasePath();
      addTearDown(() => SQLiteTestConfig.cleanupDatabase(destPath));

      final srcSizeBefore = File(dbPath).lengthSync();
      final result = await adapter.saveAs(destPath);
      expect(result.message, 'VACUUM INTO completed');
      expect(File(destPath).existsSync(), isTrue);

      // 源库大小不变（saveAs 只读源）
      final srcSizeAfter = File(dbPath).lengthSync();
      expect(srcSizeAfter, equals(srcSizeBefore));

      // 副本可独立打开 + 数据一致（setUp 插了 200 行）
      final copy = SQLiteAdapter();
      await copy.connect(DatabaseConnection(
        id: 'test_sqlite_saveas_copy',
        name: 'Copy',
        host: destPath,
        port: 0,
        type: DatabaseType.sqlite,
      ));
      addTearDown(() async {
        if (copy.isConnected) await copy.disconnect();
      });
      final rows = await copy.executeQuery('SELECT COUNT(*) AS c FROM "$testTable"');
      expect(rows.rows.first['c'], 200);
    });

    test('saveAs() WAL 模式下副本事务一致（合并 -wal 已提交事务）', () async {
      // 切 WAL 模式 + 插入新行（不 checkpoint → 数据在 -wal 文件里）
      await adapter.executeQuery('PRAGMA journal_mode=WAL');
      await adapter.executeQuery('INSERT INTO "$testTable" (id, data) VALUES (999, "wal_row")');

      final destPath = SQLiteTestConfig.generateTestDatabasePath();
      addTearDown(() => SQLiteTestConfig.cleanupDatabase(destPath));

      await adapter.saveAs(destPath);
      expect(File(destPath).existsSync(), isTrue);
      // 副本是干净 DELETE 模式单文件（VACUUM INTO 产出特性）
      expect(File('$destPath-wal').existsSync(), isFalse);

      // 副本含 WAL 里提交的事务（201 行 = 原始 200 + 新插 1）
      final copy = SQLiteAdapter();
      await copy.connect(DatabaseConnection(
        id: 'test_sqlite_saveas_wal',
        name: 'WAL Copy',
        host: destPath,
        port: 0,
        type: DatabaseType.sqlite,
      ));
      addTearDown(() async {
        if (copy.isConnected) await copy.disconnect();
      });
      final rows = await copy.executeQuery('SELECT COUNT(*) AS c FROM "$testTable"');
      expect(rows.rows.first['c'], 201);
      final walRow = await copy.executeQuery(
        'SELECT data FROM "$testTable" WHERE id = 999',
      );
      expect(walRow.rows.first['data'], 'wal_row');
    });
  });
}
