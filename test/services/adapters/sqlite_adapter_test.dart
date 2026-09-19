import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/connection_failure.dart';
import 'package:dbmaster/models/sql_script_exception.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';

/// SQLiteAdapter 全面单元测试
///
/// 测试覆盖：
/// - 基础属性和状态管理
/// - 连接管理（connect, disconnect, testConnection）
/// - 数据库操作（getDatabases, useDatabase, getDatabaseProperties）
/// - 表操作（createTable, dropTable, renameTable, truncateTable, getTables）
/// - 列操作（getTableColumns, addColumn, dropColumn, modifyColumn）
/// - 索引操作（createIndex, dropIndex, getTableIndexes）
/// - 视图操作（getViews）
/// - CRUD 操作（executeQuery, getTableData, getTableRowCount）
/// - 高级功能（getExplainPlan, getServerVersion, exportDatabaseStructure, executeSqlScript）
/// - 字符集和排序规则（getCharsets, getCollations）
/// - 安全验证（validateCommand）
/// - 事务支持
/// - 边界条件和错误处理
void main() {
  group('SQLiteAdapter', () {
    late SQLiteAdapter adapter;
    late String dbPath;

    setUp(() async {
      adapter = SQLiteAdapter();
      dbPath = '${DateTime.now().millisecondsSinceEpoch}_test.db';
    });

    tearDown(() async {
      if (adapter.isConnected) {
        await adapter.disconnect();
      }
    });

    // ========================================================================
    // 基础属性测试
    // ========================================================================
    group('基础属性', () {
      test('应正确返回数据库类型', () {
        expect(adapter.databaseType, equals(DatabaseType.sqlite));
      });

      test('初始状态应未连接', () {
        expect(adapter.isConnected, isFalse);
        expect(adapter.currentConnection, isNull);
      });
    });

    // ========================================================================
    // 连接管理测试
    // ========================================================================
    group('连接管理', () {
      test('应成功连接到有效数据库', () async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );

        final result = await adapter.connect(connection);
        expect(result, isTrue);
        expect(adapter.isConnected, isTrue);
        expect(adapter.currentConnection, isNotNull);
        expect(adapter.currentConnection!.host, equals(dbPath));
      });

      test('应失败连接到无效路径', () async {
        final connection = DatabaseConnection(
          id: 'test_sqlite_bad',
          name: 'SQLite Bad',
          host: '',
          port: 0,
          type: DatabaseType.sqlite,
        );

        // T3：connect 失败不再 return false，改抛 AdapterConnectException。
        // 空 host 经 sqflite_ffi 路径重定向后无法打开 → CANTOPEN(14)。
        await expectLater(
          adapter.connect(connection),
          throwsA(
            isA<AdapterConnectException>()
                .having(
                  (e) => e.failure.kind,
                  'kind',
                  ConnectionFailureKind.fileNotFound,
                )
                .having((e) => e.failure.errorCode, 'errorCode', '14'),
          ),
        );
        expect(adapter.isConnected, isFalse);
      });

      test('应正确断开连接', () async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );

        await adapter.connect(connection);
        expect(adapter.isConnected, isTrue);

        await adapter.disconnect();
        expect(adapter.isConnected, isFalse);
        expect(adapter.currentConnection, isNull);
      });

      test('应测试连接成功', () async {
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

      test('应测试连接失败', () async {
        final connection = DatabaseConnection(
          id: 'test_sqlite_test_bad',
          name: 'SQLite Test Bad',
          host: '',
          port: 0,
          type: DatabaseType.sqlite,
        );

        final result = await adapter.testConnection(connection);
        expect(result, isNotNull);
      });

      test('重复断开不应抛出异常', () async {
        await adapter.disconnect();
        expect(adapter.isConnected, isFalse);
      });
    });

    // ========================================================================
    // 连接失败结构化异常（连接失败 UX 重构 T3）
    //
    // 场景稳定性说明（Windows 实测）：
    // - 「不存在的父目录路径」不可用作 fileNotFound 用例——sqflite_ffi 会
    //   自动创建父目录并连接成功；空 host 与「父路径被普通文件占据」
    //   才是稳定的 CANTOPEN(14)。
    // - WAL + 并发读者是确定性复现 PRAGMA journal_mode = DELETE 失败
    //   （BUSY 5 + offendingStatement）的手段，无需 env 门控。
    // ========================================================================
    group('连接失败结构化异常（T3）', () {
      DatabaseConnection conn(String host, {String id = 't3'}) =>
          DatabaseConnection(
            id: id,
            name: 'T3',
            type: DatabaseType.sqlite,
            host: host,
            port: 0,
          );

      test('connect 父路径被普通文件占据 → fileNotFound(14) + target=路径', () async {
        final blocker = File(
          '${Directory.systemTemp.absolute.path}'
          '${Platform.pathSeparator}dbmaster_t3_blocker_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        await blocker.writeAsString('i am a file, not a directory');
        addTearDown(() async {
          if (await blocker.exists()) await blocker.delete();
        });

        await expectLater(
          adapter.connect(conn('${blocker.path}${Platform.pathSeparator}x.db')),
          throwsA(
            isA<AdapterConnectException>()
                .having(
                  (e) => e.failure.kind,
                  'kind',
                  ConnectionFailureKind.fileNotFound,
                )
                .having((e) => e.failure.errorCode, 'errorCode', '14')
                .having(
                  (e) => e.failure.target,
                  'target',
                  '${blocker.path}${Platform.pathSeparator}x.db',
                )
                .having(
                  (e) => e.failure.offendingStatement,
                  'offendingStatement',
                  isNull,
                ),
          ),
        );
        expect(adapter.isConnected, isFalse);
      });

      test('connect 非法库文件 → notADatabase(26)，cause 保留原始异常链', () async {
        final garbage = File(
          '${Directory.systemTemp.absolute.path}'
          '${Platform.pathSeparator}dbmaster_t3_garbage_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        await garbage.writeAsString(
          'this is definitely not a sqlite database file',
        );
        addTearDown(() async {
          if (await garbage.exists()) await garbage.delete();
        });

        await expectLater(
          adapter.connect(conn(garbage.path)),
          throwsA(
            isA<AdapterConnectException>()
                .having(
                  (e) => e.failure.kind,
                  'kind',
                  ConnectionFailureKind.notADatabase,
                )
                .having((e) => e.failure.errorCode, 'errorCode', '26')
                .having(
                  (e) => e.failure.rawMessage,
                  'rawMessage',
                  contains('file is not a database'),
                )
                .having((e) => e.cause, 'cause', isA<Exception>()),
          ),
        );
      });

      test(
        'connect WAL + 并发读者 → PRAGMA journal_mode = DELETE 失败（fileLocked 5 + 语句归因）',
        () async {
          final path =
              '${Directory.systemTemp.absolute.path}'
              '${Platform.pathSeparator}dbmaster_t3_wal_${DateTime.now().millisecondsSinceEpoch}.db';
          final holder = SQLiteAdapter();
          await holder.connect(conn(path, id: 't3_holder'));
          await holder.setPragma('journal_mode', 'WAL');
          // 读者开事务并保持 SHARED 锁：WAL→DELETE 切换需要独占，被阻塞 → BUSY(5)。
          await holder.executeQuery('BEGIN');
          await holder.executeQuery(
            'CREATE TABLE IF NOT EXISTS t_probe_wal (id INTEGER PRIMARY KEY)',
          );
          await holder.executeQuery('SELECT COUNT(*) FROM t_probe_wal');
          addTearDown(() => holder.disconnect());

          await expectLater(
            adapter.connect(conn(path)),
            throwsA(
              isA<AdapterConnectException>()
                  .having(
                    (e) => e.failure.kind,
                    'kind',
                    ConnectionFailureKind.fileLocked,
                  )
                  .having((e) => e.failure.errorCode, 'errorCode', '5')
                  .having(
                    (e) => e.failure.offendingStatement,
                    'offendingStatement',
                    'PRAGMA journal_mode = DELETE',
                  ),
            ),
          );
        },
      );

      test('failureFromError 非 sqflite 异常 → unknown + errorCode 空', () {
        final failure = SQLiteAdapter.failureFromError(
          Exception('boom'),
          target: 'x.db',
        );
        expect(failure.kind, ConnectionFailureKind.unknown);
        expect(failure.errorCode, isEmpty);
        expect(failure.offendingStatement, isNull);
        expect(failure.target, 'x.db');
        expect(failure.rawMessage, contains('boom'));
        expect(
          failure.occurredAt.difference(DateTime.now()).inSeconds.abs(),
          lessThan(60),
        );
      });

      test('failureFromError 真实 DatabaseException → 取码 + statement 透传', () async {
        // 1) 带 code 的真实异常：垃圾文件 connect 失败的 cause（code 26）。
        final garbage = File(
          '${Directory.systemTemp.absolute.path}'
          '${Platform.pathSeparator}dbmaster_t3_garbage2_${DateTime.now().millisecondsSinceEpoch}.db',
        );
        await garbage.writeAsString('not a sqlite db at all');
        addTearDown(() async {
          if (await garbage.exists()) await garbage.delete();
        });
        Object? coded;
        try {
          await adapter.connect(conn(garbage.path));
        } on AdapterConnectException catch (e) {
          coded = e.cause;
        }
        expect(coded, isNotNull);

        final codedFailure = SQLiteAdapter.failureFromError(
          coded!,
          statement: 'PRAGMA journal_mode = DELETE',
          target: garbage.path,
        );
        expect(codedFailure.kind, ConnectionFailureKind.notADatabase);
        expect(codedFailure.errorCode, '26');
        expect(codedFailure.offendingStatement, 'PRAGMA journal_mode = DELETE');
        expect(codedFailure.target, garbage.path);

        // 2) 不带 code 的真实异常（查询错误）：ffi 未在 result 上带码 →
        //    getResultCode() 为 null → kind=unknown、errorCode=''。
        await adapter.connect(conn(dbPath));
        addTearDown(adapter.disconnect);
        Object? noCode;
        try {
          await adapter.executeQuery('SELECT * FROM t3_missing_table_xyz');
        } catch (e) {
          noCode = e;
        }
        expect(noCode, isNotNull);
        final noCodeFailure = SQLiteAdapter.failureFromError(noCode!);
        expect(noCodeFailure.kind, ConnectionFailureKind.unknown);
        expect(noCodeFailure.errorCode, isEmpty);
      });
    });

    // ========================================================================
    // 数据库操作测试
    // ========================================================================
    group('数据库操作', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      });

      test('应返回 main 数据库', () async {
        final dbs = await adapter.getDatabases();
        expect(dbs, isNotEmpty);
        expect(dbs.first, equals('main'));
      });

      test('应切换到指定数据库', () async {
        await adapter.useDatabase('main');
        expect(adapter.currentConnection!.database, equals('main'));
      });

      test('应获取数据库属性', () async {
        final props = await adapter.getDatabaseProperties('main');
        expect(props, isNotNull);
        expect(props!.containsKey('encoding'), isTrue);
        expect(props.containsKey('file'), isTrue);
      });

      test('未连接时 getTables 应抛出异常', () async {
        await adapter.disconnect();
        expect(() => adapter.getTables(), throwsException);
        expect(() => adapter.getTableColumns('test'), throwsException);
      });
    });

    // ========================================================================
    // 表操作测试
    // ========================================================================
    group('表操作', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      });

      test('应创建表', () async {
        final columns = [
          DbColumn(
            name: 'id',
            type: 'INTEGER',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'name', type: 'TEXT', isNullable: false),
          DbColumn(name: 'age', type: 'INTEGER', isNullable: true),
        ];

        final created = await adapter.createTable('users', columns);
        expect(created, isTrue);

        final tables = await adapter.getTables();
        expect(tables, contains('users'));
      });

      test('应创建带默认值的表', () async {
        final columns = [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'status', type: 'TEXT', defaultValue: '\'active\''),
        ];

        final created = await adapter.createTable('orders', columns);
        expect(created, isTrue);
      });

      test('应删除表', () async {
        await adapter.createTable('temp_table', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        ]);

        final dropped = await adapter.dropTable('temp_table');
        expect(dropped, isTrue);

        final tables = await adapter.getTables();
        expect(tables, isNot(contains('temp_table')));
      });

      test('应重命名表', () async {
        await adapter.createTable('old_name', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        ]);

        final renamed = await adapter.renameTable('old_name', 'new_name');
        expect(renamed, isTrue);

        final tables = await adapter.getTables();
        expect(tables, contains('new_name'));
        expect(tables, isNot(contains('old_name')));
      });

      test('应清空表', () async {
        await adapter.createTable('test_data', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'val', type: 'TEXT'),
        ]);

        await adapter.executeQuery(
          'INSERT INTO "test_data" (id, val) VALUES (1, "a")',
        );
        var count = await adapter.getTableRowCount('test_data');
        expect(count, 1);

        final truncated = await adapter.truncateTable('test_data');
        expect(truncated, isTrue);

        count = await adapter.getTableRowCount('test_data');
        expect(count, 0);
      });

      test('应获取表列表', () async {
        await adapter.createTable('table1', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        ]);
        await adapter.createTable('table2', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        ]);

        final tables = await adapter.getTables();
        expect(tables.length, greaterThanOrEqualTo(2));
        expect(tables, contains('table1'));
        expect(tables, contains('table2'));
      });
    });

    // ========================================================================
    // 列操作测试
    // ========================================================================
    group('列操作', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
        await adapter.createTable('test_columns', [
          DbColumn(
            name: 'id',
            type: 'INTEGER',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'name', type: 'TEXT', isNullable: false),
        ]);
      });

      test('应获取表列信息', () async {
        final columns = await adapter.getTableColumns('test_columns');
        expect(columns, isNotEmpty);
        expect(columns.any((c) => c.name == 'id'), isTrue);
        expect(columns.any((c) => c.name == 'name'), isTrue);

        final idCol = columns.firstWhere((c) => c.name == 'id');
        expect(idCol.isPrimaryKey, isTrue);
        expect(idCol.isNullable, isFalse);
      });

      test('应添加列', () async {
        final added = await adapter.addColumn(
          'test_columns',
          DbColumn(name: 'email', type: 'TEXT', isNullable: true),
        );
        expect(added, isTrue);

        final columns = await adapter.getTableColumns('test_columns');
        expect(columns.any((c) => c.name == 'email'), isTrue);
      });

      test('应添加带默认值的列', () async {
        final added = await adapter.addColumn(
          'test_columns',
          DbColumn(
            name: 'status',
            type: 'TEXT',
            isNullable: false,
            defaultValue: '\'pending\'',
          ),
        );
        expect(added, isTrue);

        final columns = await adapter.getTableColumns('test_columns');
        final statusCol = columns.firstWhere((c) => c.name == 'status');
        expect(statusCol.defaultValue, isNotNull);
      });

      test('应删除列', () async {
        await adapter.addColumn(
          'test_columns',
          DbColumn(name: 'temp_col', type: 'TEXT', isNullable: true),
        );

        final dropped = await adapter.dropColumn('test_columns', 'temp_col');
        expect(dropped, isTrue);

        final columns = await adapter.getTableColumns('test_columns');
        expect(columns.any((c) => c.name == 'temp_col'), isFalse);
      });

      test('应获取表详情', () async {
        final details = await adapter.getTableDetails('test_columns');
        expect(details.name, 'test_columns');
        expect(details.columns, isNotEmpty);
        expect(details.columns.length, greaterThanOrEqualTo(2));
      });
    });

    // ========================================================================
    // 索引操作测试
    // ========================================================================
    group('索引操作', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
        await adapter.createTable('test_indexes', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'email', type: 'TEXT'),
          DbColumn(name: 'username', type: 'TEXT'),
        ]);
      });

      test('应创建索引', () async {
        final created = await adapter.createIndex('test_indexes', 'idx_email', [
          'email',
        ]);
        expect(created, isTrue);

        final indexes = await adapter.getTableIndexes('test_indexes');
        expect(indexes.any((idx) => idx.name == 'idx_email'), isTrue);
      });

      test('应创建唯一索引', () async {
        final created = await adapter.createIndex(
          'test_indexes',
          'idx_username_unique',
          ['username'],
          unique: true,
        );
        expect(created, isTrue);

        final indexes = await adapter.getTableIndexes('test_indexes');
        final idx = indexes.firstWhere((i) => i.name == 'idx_username_unique');
        expect(idx.isUnique, isTrue);
      });

      test('应删除索引', () async {
        await adapter.createIndex('test_indexes', 'idx_to_drop', ['email']);

        final dropped = await adapter.dropIndex('test_indexes', 'idx_to_drop');
        expect(dropped, isTrue);

        final indexes = await adapter.getTableIndexes('test_indexes');
        expect(indexes.any((idx) => idx.name == 'idx_to_drop'), isFalse);
      });

      test('应获取表索引列表', () async {
        await adapter.createIndex('test_indexes', 'idx_email', ['email']);
        await adapter.createIndex('test_indexes', 'idx_username', ['username']);

        final indexes = await adapter.getTableIndexes('test_indexes');
        expect(indexes.length, greaterThanOrEqualTo(2));
      });
    });

    // ========================================================================
    // 视图操作测试
    // ========================================================================
    group('视图操作', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
        await adapter.createTable('test_views', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'name', type: 'TEXT'),
          DbColumn(name: 'age', type: 'INTEGER'),
        ]);
      });

      test('应创建和获取视图', () async {
        await adapter.executeQuery(
          'INSERT INTO "test_views" (id, name, age) VALUES (1, "Alice", 30)',
        );

        await adapter.executeQuery(
          'CREATE VIEW "adult_users" AS SELECT id, name FROM "test_views" WHERE age >= 18',
        );

        final views = await adapter.getViews();
        expect(views, contains('adult_users'));
      });
    });

    // ========================================================================
    // CRUD 操作测试
    // ========================================================================
    group('CRUD 操作', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
        await adapter.createTable('test_crud', [
          DbColumn(
            name: 'id',
            type: 'INTEGER',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'name', type: 'TEXT', isNullable: false),
          DbColumn(name: 'age', type: 'INTEGER', isNullable: true),
        ]);
      });

      test('应插入数据', () async {
        final result = await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name, age) VALUES (1, "Alice", 30)',
        );
        expect(result.affectedRows, 1);

        final count = await adapter.getTableRowCount('test_crud');
        expect(count, 1);
      });

      test('应查询数据', () async {
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name, age) VALUES (1, "Alice", 30)',
        );
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name, age) VALUES (2, "Bob", 25)',
        );

        final result = await adapter.executeQuery('SELECT * FROM "test_crud"');
        expect(result.rows.length, 2);
        expect(result.columns, contains('id'));
        expect(result.columns, contains('name'));
        expect(result.columns, contains('age'));

        final alice = result.rows.firstWhere((r) => r['name'] == 'Alice');
        expect(alice['age'], 30);
      });

      test('应更新数据', () async {
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name, age) VALUES (1, "Alice", 30)',
        );

        final result = await adapter.executeQuery(
          'UPDATE "test_crud" SET age = 31 WHERE id = 1',
        );
        expect(result.affectedRows, 1);

        final select = await adapter.executeQuery(
          'SELECT age FROM "test_crud" WHERE id = 1',
        );
        expect(select.rows.first['age'], 31);
      });

      test('应删除数据', () async {
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name) VALUES (1, "Alice")',
        );
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name) VALUES (2, "Bob")',
        );

        final result = await adapter.executeQuery(
          'DELETE FROM "test_crud" WHERE id = 1',
        );
        expect(result.affectedRows, 1);

        final count = await adapter.getTableRowCount('test_crud');
        expect(count, 1);
      });

      test('应分页获取数据', () async {
        for (int i = 1; i <= 10; i++) {
          await adapter.executeQuery(
            'INSERT INTO "test_crud" (id, name) VALUES ($i, "User$i")',
          );
        }

        final page1 = await adapter.getTableData(
          'test_crud',
          limit: 5,
          offset: 0,
        );
        expect(page1.rows.length, 5);
        expect(page1.rows.first['id'], 1);

        final page2 = await adapter.getTableData(
          'test_crud',
          limit: 5,
          offset: 5,
        );
        expect(page2.rows.length, 5);
        expect(page2.rows.first['id'], 6);
      });

      test('应获取表行数', () async {
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name) VALUES (1, "a")',
        );
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name) VALUES (2, "b")',
        );

        final count = await adapter.getTableRowCount('test_crud');
        expect(count, 2);
      });

      test('应执行复杂 SQL 查询', () async {
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name, age) VALUES (1, "Alice", 30)',
        );
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name, age) VALUES (2, "Bob", 25)',
        );
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name, age) VALUES (3, "Charlie", 35)',
        );

        final result = await adapter.executeQuery(
          'SELECT age, COUNT(*) as cnt, AVG(age) as avg_age FROM "test_crud" GROUP BY age',
        );
        expect(result.rows.isNotEmpty, isTrue);
      });

      test('应执行 SELECT 查询返回正确列', () async {
        await adapter.executeQuery(
          'INSERT INTO "test_crud" (id, name) VALUES (1, "test")',
        );

        final result = await adapter.executeQuery(
          'SELECT id, name FROM "test_crud"',
        );
        expect(result.columns.length, 2);
        expect(result.columns, contains('id'));
        expect(result.columns, contains('name'));
        expect(result.rows.length, 1);
      });
    });

    // ========================================================================
    // 高级功能测试
    // ========================================================================
    group('高级功能', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      });

      test('应获取服务器版本', () async {
        final version = await adapter.getServerVersion();
        expect(version, isNotNull);
        expect(version!.containsKey('version'), isTrue);
        expect(version['database'], 'SQLite');
      });

      test('应获取执行计划', () async {
        await adapter.createTable('test_plan', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'data', type: 'TEXT'),
        ]);
        await adapter.executeQuery(
          'INSERT INTO "test_plan" (id, data) VALUES (1, "test")',
        );

        final plan = await adapter.getExplainPlan('SELECT * FROM "test_plan"');
        expect(plan.rows.isNotEmpty, isTrue);
      });

      test('应执行 SQL 脚本', () async {
        await adapter.createTable('test_script', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'data', type: 'TEXT'),
        ]);

        final script = '''
INSERT INTO "test_script" (id, data) VALUES (10, "script1");
INSERT INTO "test_script" (id, data) VALUES (20, "script2");
INSERT INTO "test_script" (id, data) VALUES (30, "script3");
''';

        final result = await adapter.executeSqlScript(script.trim());
        expect(result, isTrue);

        final count = await adapter.getTableRowCount('test_script');
        expect(count, 3);
      });

      test('应执行字符串内含分号的脚本（分号不截断语句）', () async {
        await adapter.createTable('test_script_semi', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'data', type: 'TEXT'),
        ]);

        final script = '''
INSERT INTO "test_script_semi" (id, data) VALUES (10, "semi;colon");
INSERT INTO "test_script_semi" (id, data) VALUES (20, "plain");
''';

        final result = await adapter.executeSqlScript(script);
        expect(result, isTrue);

        final count = await adapter.getTableRowCount('test_script_semi');
        expect(count, 2);

        final rows = await adapter.executeQuery(
          'SELECT data FROM "test_script_semi" WHERE id = 10',
        );
        expect(rows.rows.first['data'], 'semi;colon');
      });

      test('脚本中途失败抛定位异常且前序语句已生效', () async {
        await adapter.createTable('test_script_fail', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'data', type: 'TEXT'),
        ]);

        final script = '''
INSERT INTO "test_script_fail" (id, data) VALUES (1, "ok");
THIS IS NOT VALID SQL;
INSERT INTO "test_script_fail" (id, data) VALUES (2, "never");
''';

        await expectLater(
          adapter.executeSqlScript(script),
          throwsA(
            isA<SqlScriptExecutionException>()
                .having((e) => e.statementIndex, '语句序号', 1)
                .having((e) => e.lineStart, '起始行', 2)
                .having((e) => e.committedCount, '已执行条数', 1),
          ),
        );

        // 部分提交：失败前的第一条已落库，失败后的第三条未执行
        final count = await adapter.getTableRowCount('test_script_fail');
        expect(count, 1);
      });

      test('应导出数据库结构', () async {
        await adapter.createTable('export_test', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'name', type: 'TEXT'),
        ]);

        final export = await adapter.exportDatabaseStructure('main');
        expect(export, isNotNull);
        expect(export.contains('CREATE TABLE'), isTrue);
        expect(export.contains('export_test'), isTrue);
      });

      test('应获取字符集', () async {
        final charsets = await adapter.getCharsets();
        expect(charsets, isNotEmpty);
        expect(charsets, contains('UTF-8'));
      });

      test('应获取排序规则', () async {
        final collations = await adapter.getCollations();
        expect(collations, isA<List<Map<String, String>>>());
      });
    });

    // ========================================================================
    // 存储过程和函数测试
    // ========================================================================
    group('存储过程和函数', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      });

      test('应返回空存储过程列表', () async {
        final procedures = await adapter.getProcedures();
        expect(procedures, isEmpty);
      });

      test('应返回空函数列表', () async {
        final functions = await adapter.getFunctions();
        expect(functions, isEmpty);
      });
    });

    // ========================================================================
    // 安全验证测试
    // ========================================================================
    group('安全验证', () {
      test('应允许安全命令（SELECT）', () {
        final result = adapter.validateCommand('SELECT * FROM users');
        expect(result.allowed, isTrue);
        expect(result.riskLevel, equals(CommandRiskLevel.safe));
      });

      test('应允许写操作命令（INSERT）', () {
        final result = adapter.validateCommand(
          'INSERT INTO users VALUES (1, "test")',
        );
        expect(result.allowed, isTrue);
        expect(result.riskLevel, equals(CommandRiskLevel.warning));
      });

      test('应允许带 WHERE 的 UPDATE', () {
        final result = adapter.validateCommand(
          'UPDATE users SET name = "test" WHERE id = 1',
        );
        expect(result.allowed, isTrue);
        expect(result.riskLevel, equals(CommandRiskLevel.warning));
      });

      test('应阻止无 WHERE 的 UPDATE', () {
        final result = adapter.validateCommand(
          'UPDATE users SET name = "test"',
        );
        expect(result.allowed, isFalse);
        expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
      });

      test('应阻止危险命令（DROP TABLE）', () {
        final result = adapter.validateCommand('DROP TABLE users');
        expect(result.allowed, isFalse);
        expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
      });

      test('应阻止危险命令（DELETE without WHERE）', () {
        final result = adapter.validateCommand('DELETE FROM users');
        expect(result.allowed, isFalse);
        expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
      });

      test('应阻止危险命令（TRUNCATE）', () {
        final result = adapter.validateCommand('TRUNCATE TABLE users');
        expect(result.allowed, isFalse);
        expect(result.riskLevel, equals(CommandRiskLevel.dangerous));
      });

      test('应区分大小写处理命令', () {
        final result1 = adapter.validateCommand('select * from users');
        final result2 = adapter.validateCommand('SELECT * FROM users');
        expect(result1.allowed, isTrue);
        expect(result2.allowed, isTrue);
      });
    });

    // ========================================================================
    // 事务测试
    // ========================================================================
    group('事务', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
        await adapter.createTable('test_tx', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'val', type: 'TEXT'),
        ]);
      });

      test('应支持事务提交', () async {
        await adapter.executeQuery('BEGIN TRANSACTION');
        await adapter.executeQuery(
          'INSERT INTO "test_tx" (id, val) VALUES (1, "a")',
        );
        await adapter.executeQuery(
          'INSERT INTO "test_tx" (id, val) VALUES (2, "b")',
        );
        await adapter.executeQuery('COMMIT');

        final count = await adapter.getTableRowCount('test_tx');
        expect(count, 2);
      });

      test('应支持事务回滚', () async {
        await adapter.executeQuery('BEGIN TRANSACTION');
        await adapter.executeQuery(
          'INSERT INTO "test_tx" (id, val) VALUES (1, "a")',
        );
        await adapter.executeQuery('ROLLBACK');

        final count = await adapter.getTableRowCount('test_tx');
        expect(count, 0);
      });
    });

    // ========================================================================
    // 数据类型测试
    // ========================================================================
    group('数据类型', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      });

      test('应处理多种数据类型', () async {
        await adapter.createTable('test_types', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'text_col', type: 'TEXT'),
          DbColumn(name: 'int_col', type: 'INTEGER'),
          DbColumn(name: 'real_col', type: 'REAL'),
          DbColumn(name: 'blob_col', type: 'BLOB'),
          DbColumn(name: 'numeric_col', type: 'NUMERIC'),
        ]);

        await adapter.executeQuery(
          'INSERT INTO "test_types" (id, text_col, int_col, real_col, blob_col, numeric_col) '
          'VALUES (1, \'hello\', 42, 3.14, CAST(\'blob_data\' AS BLOB), 99.9)',
        );

        final result = await adapter.executeQuery('SELECT * FROM "test_types"');
        expect(result.rows.length, 1);
        expect(result.rows.first['text_col'], 'hello');
        expect(result.rows.first['int_col'], 42);
        expect(result.rows.first['real_col'], 3.14);
      });

      test('应处理 NULL 值', () async {
        await adapter.createTable('test_null', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'nullable_col', type: 'TEXT', isNullable: true),
        ]);

        await adapter.executeQuery(
          'INSERT INTO "test_null" (id, nullable_col) VALUES (1, NULL)',
        );

        final result = await adapter.executeQuery('SELECT * FROM "test_null"');
        expect(result.rows.first['nullable_col'], isNull);
      });
    });

    // ========================================================================
    // 约束测试
    // ========================================================================
    group('约束', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      });

      test('应强制执行 PRIMARY KEY 约束', () async {
        await adapter.createTable('test_pk', [
          DbColumn(
            name: 'id',
            type: 'INTEGER',
            isPrimaryKey: true,
            isNullable: false,
          ),
          DbColumn(name: 'name', type: 'TEXT'),
        ]);

        await adapter.executeQuery(
          'INSERT INTO "test_pk" (id, name) VALUES (1, "Alice")',
        );

        expect(
          () => adapter.executeQuery(
            'INSERT INTO "test_pk" (id, name) VALUES (1, "Bob")',
          ),
          throwsException,
        );
      });

      test('应强制执行 NOT NULL 约束', () async {
        await adapter.createTable('test_notnull', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'required', type: 'TEXT', isNullable: false),
        ]);

        expect(
          () => adapter.executeQuery(
            'INSERT INTO "test_notnull" (id, required) VALUES (1, NULL)',
          ),
          throwsException,
        );
      });
    });

    // ========================================================================
    // 边界条件测试
    // ========================================================================
    group('边界条件', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      });

      test('应处理空表', () async {
        await adapter.createTable('empty_table', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        ]);

        final count = await adapter.getTableRowCount('empty_table');
        expect(count, 0);

        final data = await adapter.getTableData('empty_table');
        expect(data.rows, isEmpty);
      });

      test('应处理特殊字符表名', () async {
        await adapter.createTable('table_with_underscore', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
        ]);

        final tables = await adapter.getTables();
        expect(tables, contains('table_with_underscore'));
      });

      test('应处理大量数据', () async {
        await adapter.createTable('bulk_data', [
          DbColumn(name: 'id', type: 'INTEGER', isPrimaryKey: true),
          DbColumn(name: 'data', type: 'TEXT'),
        ]);

        for (int i = 1; i <= 100; i++) {
          await adapter.executeQuery(
            'INSERT INTO "bulk_data" (id, data) VALUES ($i, "data_$i")',
          );
        }

        final count = await adapter.getTableRowCount('bulk_data');
        expect(count, 100);
      });
    });

    // ========================================================================
    // AI 支持测试
    // ========================================================================
    group('AI 支持', () {
      setUp(() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite',
          name: 'Test SQLite',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      });

      test('应返回 SQLite 特定的 Schema 摘要', () async {
        final summary = await adapter.getAiSchemaSummary();
        expect(summary, contains('SQLite'));
      });
    });

    // ========================================================================
    // JSON 列启发式检测（016 US3 T050）
    // ========================================================================
    group('JSON 列启发式检测（016 T050）', () {
      Future<void> connect() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite_json',
          name: 'Test SQLite JSON',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        final ok = await adapter.connect(connection);
        expect(ok, isTrue);
      }

      test('isJsonColumn 对 JSON 文本列 → true（≥80% 可解析）', () async {
        await connect();
        await adapter.executeQuery('CREATE TABLE t (id INT, data TEXT)');
        // 插 5 行 JSON（100% 可解析 → 应检测为 JSON）
        for (final v in [
          '{"name":"a"}',
          '{"name":"b"}',
          '{"name":"c"}',
          '{"name":"d"}',
          '{"name":"e"}',
        ]) {
          await adapter.executeQuery(
            "INSERT INTO t (id, data) VALUES (0, '$v')",
          );
        }

        expect(await adapter.isJsonColumn('t', 'data'), isTrue);
      });

      test('isJsonColumn 对纯文本列 → false', () async {
        await connect();
        await adapter.executeQuery('CREATE TABLE t2 (id INT, note TEXT)');
        for (final v in ['hello', 'world', 'plain', 'text', 'row']) {
          await adapter.executeQuery(
            "INSERT INTO t2 (id, note) VALUES (0, '$v')",
          );
        }

        expect(await adapter.isJsonColumn('t2', 'note'), isFalse);
      });

      test('isJsonColumn 对 JSON 数组 → true', () async {
        await connect();
        await adapter.executeQuery('CREATE TABLE t3 (id INT, arr TEXT)');
        for (final v in ['[1,2,3]', '[4,5]', '[6]', '[7,8]', '[9,10]']) {
          await adapter.executeQuery(
            "INSERT INTO t3 (id, arr) VALUES (0, '$v')",
          );
        }

        expect(await adapter.isJsonColumn('t3', 'arr'), isTrue);
      });

      test('isJsonColumn 混合（<80% JSON）→ false', () async {
        await connect();
        await adapter.executeQuery('CREATE TABLE t4 (id INT, mixed TEXT)');
        // 5 行里 1 行 JSON（20% < 80% 阈值）→ 不算 JSON 列
        await adapter.executeQuery(
          "INSERT INTO t4 (id, mixed) VALUES (0, 'not json')",
        );
        await adapter.executeQuery(
          "INSERT INTO t4 (id, mixed) VALUES (0, 'plain')",
        );
        await adapter.executeQuery(
          "INSERT INTO t4 (id, mixed) VALUES (0, 'text')",
        );
        await adapter.executeQuery(
          "INSERT INTO t4 (id, mixed) VALUES (0, 'row')",
        );
        await adapter.executeQuery(
          "INSERT INTO t4 (id, mixed) VALUES (0, '{\"a\":1}')",
        );

        expect(await adapter.isJsonColumn('t4', 'mixed'), isFalse);
      });

      test('isJsonColumn 空列（全 NULL）→ false', () async {
        await connect();
        await adapter.executeQuery('CREATE TABLE t5 (id INT, nullable TEXT)');
        await adapter.executeQuery(
          "INSERT INTO t5 (id, nullable) VALUES (1, NULL)",
        );

        expect(await adapter.isJsonColumn('t5', 'nullable'), isFalse);
      });
    });

    // ========================================================================
    // PRAGMA Explorer（PragmaAdapter）
    // ========================================================================
    group('PRAGMA Explorer（PragmaAdapter）', () {
      Future<void> connect() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite_pragma',
          name: 'Test SQLite PRAGMA',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
      }

      test('adapter 应实现 PragmaAdapter', () {
        expect(adapter, isA<PragmaAdapter>());
      });

      test('getPragmas 返回非空列表 + 分类覆盖', () async {
        await connect();
        final pragmas = await adapter.getPragmas();
        expect(pragmas, isNotEmpty);
        // 确认 4 个分类都有覆盖。
        final categories = pragmas.map((p) => p.category).toSet();
        expect(categories, contains(PragmaCategory.performance));
        expect(categories, contains(PragmaCategory.durability));
        expect(categories, contains(PragmaCategory.security));
        expect(categories, contains(PragmaCategory.debug));
        // 确认关键 PRAGMA 在列表里。
        expect(pragmas.any((p) => p.name == 'journal_mode'), isTrue);
        expect(pragmas.any((p) => p.name == 'foreign_keys'), isTrue);
      });

      test('getPragmas journal_mode 有值（DELETE 或 WAL）', () async {
        await connect();
        final pragmas = await adapter.getPragmas();
        final jm = pragmas.firstWhere((p) => p.name == 'journal_mode');
        expect(jm.currentValue, isNotNull);
        expect([
          'delete',
          'wal',
          'truncate',
          'memory',
          'persist',
          'off',
        ], contains(jm.currentValue!.toLowerCase()));
      });

      test('setPragma journal_mode → WAL 生效', () async {
        await connect();
        // 先设 WAL
        final updated = await adapter.setPragma('journal_mode', 'WAL');
        expect(updated.currentValue?.toLowerCase(), 'wal');
        // 再查确认
        final pragmas = await adapter.getPragmas();
        final jm = pragmas.firstWhere((p) => p.name == 'journal_mode');
        expect(jm.currentValue?.toLowerCase(), 'wal');
      });

      test('setPragma foreign_keys → 1 生效', () async {
        await connect();
        final updated = await adapter.setPragma('foreign_keys', '1');
        expect(updated.currentValue, '1');
      });

      test('getPragmas 未连接 → 空列表', () async {
        // setUp 不 connect，直接查
        final fresh = SQLiteAdapter();
        expect(await fresh.getPragmas(), isEmpty);
      });
    });

    // ========================================================================
    // 维护操作（vacuum / integrityCheck / optimize）
    // ========================================================================
    group('维护操作（vacuum / integrityCheck / optimize）', () {
      /// 建临时库 + 建一张表 + 插几行（让 VACUUM 有实际意义）。
      Future<void> connect({bool readOnly = false}) async {
        final connection = DatabaseConnection(
          id: 'test_sqlite_maintenance',
          name: 'Test SQLite Maintenance',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
          readOnly: readOnly,
        );
        await adapter.connect(connection);
        await adapter.executeQuery(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);',
        );
        await adapter.executeQuery("INSERT INTO t (v) VALUES ('a'), ('b');");
      }

      test(
        'vacuum() 连接后 → message=VACUUM completed + executionTime ≥ 0',
        () async {
          await connect();
          final result = await adapter.vacuum();
          expect(result.message, 'VACUUM completed');
          expect(result.columns, isEmpty);
          expect(result.rows, isEmpty);
          expect(result.executionTime, greaterThanOrEqualTo(0));
        },
      );

      test('vacuum() 未连接 → 抛异常（guardReadOnly fail-closed）', () async {
        // setUp 的 adapter 未 connect，_currentConnection 为 null → guardReadOnly
        // fail-closed 抛 ReadOnlyBlockedException（而非「未连接到数据库」）。
        final fresh = SQLiteAdapter();
        expect(fresh.vacuum(), throwsA(isA<Exception>()));
      });

      test('vacuum() 只读连接 → 抛异常', () async {
        // 先正常连接 + 建表（只读连接建不了表），再运行时切只读。
        await connect();
        adapter.updateReadOnly(true);
        expect(adapter.vacuum(), throwsA(isA<Exception>()));
      });

      test('integrityCheck() 连接后 → rows 含单行 ok', () async {
        await connect();
        final result = await adapter.integrityCheck();
        // 正常库返回单行 {integrity_check: ok}
        expect(result.rows, hasLength(1));
        expect(result.rows.first['integrity_check'], 'ok');
        expect(result.columns, contains('integrity_check'));
      });

      test('integrityCheck() 未连接 → 抛异常（无 guardReadOnly，直接查未连接）', () async {
        final fresh = SQLiteAdapter();
        expect(fresh.integrityCheck(), throwsA(isA<Exception>()));
      });

      test('optimize() 连接后 → message=PRAGMA optimize completed', () async {
        await connect();
        final result = await adapter.optimize();
        expect(result.message, 'PRAGMA optimize completed');
        expect(result.columns, isEmpty);
        expect(result.rows, isEmpty);
      });

      // ======================================================================
      // saveAs（VACUUM INTO 策略）
      //
      // 用绝对路径：sqflite_common_ffi 测试环境会把「相对路径」重定向到
      // .dart_tool/sqflite_common_ffi/databases/，而 VACUUM INTO 由底层 SQLite
      // C 库按 CWD 解析——两者不一致会让复制的库读不到。绝对路径让两处对齐。
      // ======================================================================
      test(
        'saveAs(destPath) 连接后 → 产出新文件 + message=VACUUM INTO completed',
        () async {
          final destPath =
              '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}${dbPath}_copy.db';
          addTearDown(() async {
            final f = File(destPath);
            if (await f.exists()) await f.delete();
          });
          await connect();
          final result = await adapter.saveAs(destPath);
          expect(result.message, 'VACUUM INTO completed');
          expect(File(destPath).existsSync(), isTrue);
        },
      );

      test('saveAs() 复制的库可被独立打开 + 数据一致', () async {
        final destPath =
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}${dbPath}_copy2.db';
        addTearDown(() async {
          final f = File(destPath);
          if (await f.exists()) await f.delete();
        });
        await connect();
        // 源库已有 2 行（connect helper 插入）
        await adapter.saveAs(destPath);

        // 新开一个 adapter 连目标库，验证数据一致
        final copy = SQLiteAdapter();
        await copy.connect(
          DatabaseConnection(
            id: 'test_sqlite_copy',
            name: 'Copy',
            type: DatabaseType.sqlite,
            host: destPath,
            port: 0,
          ),
        );
        addTearDown(() async {
          if (copy.isConnected) await copy.disconnect();
        });
        final rows = await copy.executeQuery('SELECT COUNT(*) AS c FROM t;');
        expect(rows.rows.first['c'], 2);
      });

      test('saveAs() 未连接 → 抛异常（无 guardReadOnly，直接查未连接）', () async {
        final fresh = SQLiteAdapter();
        expect(fresh.saveAs('whatever.db'), throwsA(isA<Exception>()));
      });

      test('saveAs() 路径含单引号 → 抛 ArgumentError（防注入）', () async {
        await connect();
        // VACUUM INTO 的文件名 token 不支持参数绑定，手动防注入
        expect(
          adapter.saveAs("path'with'quote.db"),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('saveAs() 只读连接 → 仍可导出副本（源库只读，不 guard）', () async {
        final destPath =
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}${dbPath}_copy3.db';
        addTearDown(() async {
          final f = File(destPath);
          if (await f.exists()) await f.delete();
        });
        // 先正常连接 + 建表（只读连接建不了表），再运行时切只读
        await connect();
        adapter.updateReadOnly(true);
        final result = await adapter.saveAs(destPath);
        expect(result.message, 'VACUUM INTO completed');
        expect(File(destPath).existsSync(), isTrue);
      });
    });

    // ========================================================================
    // ATTACH 跨库（spec 050 / AttachAwareAdapter）
    // ========================================================================
    group('ATTACH 跨库（spec 050）', () {
      /// 建主库连接（建一张表 + 插几行，供跨库查询验证）。
      Future<void> connect() async {
        final connection = DatabaseConnection(
          id: 'test_sqlite_attach',
          name: 'Test SQLite ATTACH',
          type: DatabaseType.sqlite,
          host: dbPath,
          port: 0,
        );
        await adapter.connect(connection);
        await adapter.executeSqlScript(
          'CREATE TABLE main_users(id INTEGER PRIMARY KEY, name TEXT);'
          'INSERT INTO main_users(name) VALUES (\'alice\'), (\'bob\');',
        );
      }

      /// 建一个独立的附加库文件（archive 风格），返回绝对路径。
      ///
      /// 注意：spec 050 测试用唯一时间戳文件名，**不在 addTearDown 删除**——
      /// Windows 下 SQLite 句柄释放与文件删除存在时序竞争（`errno 32`，
      /// 另一个程序正在使用），adapter 的全局 disconnect（group tearDown）
      // 晚于测试内 addTearDown 执行，删文件时句柄未释放。沿用既有测试的惯例
      /// （setUp 也只 disconnect 不删文件），靠文件名唯一避免跨测试污染。
      Future<String> buildAttachedDb(String filename) async {
        final path =
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}$filename';
        final helper = SQLiteAdapter();
        final conn = DatabaseConnection(
          id: 'attach_helper',
          name: 'helper',
          type: DatabaseType.sqlite,
          host: path,
          port: 0,
        );
        await helper.connect(conn);
        await helper.executeSqlScript(
          'CREATE TABLE archive_orders('
          'id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL);'
          "INSERT INTO archive_orders(user_id, amount) VALUES (1, 99.0), (1, 10.5), (2, 50.0);",
        );
        await helper.disconnect();
        return path;
      }

      test('adapter 应实现 AttachAwareAdapter', () {
        expect(adapter, isA<AttachAwareAdapter>());
      });

      test('adapter 应实现 MultiSchemaObjectAdapter', () {
        expect(adapter, isA<MultiSchemaObjectAdapter>());
      });

      test('getDatabases 未连接 → 返回 main（向后兼容）', () async {
        expect(await adapter.getDatabases(), equals(['main']));
      });

      test('getDatabases 连接后含 main（PRAGMA database_list）', () async {
        await connect();
        final dbs = await adapter.getDatabases();
        expect(dbs, contains('main'));
        // 注：temp 是惰性的——无临时对象时 PRAGMA database_list 不列出它，
        // 故基线只断言 main（实际可能含 temp 也可能不含，不强制）。
      });

      test('listAttachedDatabases 返回 main（无附加库基线）', () async {
        await connect();
        final list = await adapter.listAttachedDatabases();
        final names = list.map((e) => e.name).toList();
        expect(names, contains('main'));
        // main 通常是 seq 0
        expect(list.firstWhere((e) => e.name == 'main').seq, 0);
        // main 的 file 字段应为主库路径
        expect(list.firstWhere((e) => e.name == 'main').file, isNotNull);
      });

      test('attachDatabase 成功 → getDatabases 含 alias', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_attach1.db',
        );

        await adapter.attachDatabase(attachedPath, 'archive');
        final dbs = await adapter.getDatabases();
        expect(dbs, contains('archive'));
      });

      test(
        'attachDatabase 成功 → listAttachedDatabases 含 archive + file',
        () async {
          await connect();
          final attachedPath = await buildAttachedDb(
            '${DateTime.now().millisecondsSinceEpoch}_attach2.db',
          );

          await adapter.attachDatabase(attachedPath, 'archive');
          final list = await adapter.listAttachedDatabases();
          final archive = list.firstWhere((e) => e.name == 'archive');
          expect(archive.file, isNotNull);
          expect(archive.seq, greaterThan(0));
        },
      );

      test('attachDatabase 文件不存在 → SQLite 创建空库（不抛错）', () async {
        // SQLite 语义：ATTACH 不存在的文件会创建空库（与 CONNECT 行为一致）。
        // 故文件不存在不抛错，而是得到一个空附加库（可查 sqlite_master）。
        await connect();
        final newPath =
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}nonexistent_${DateTime.now().millisecondsSinceEpoch}.db';
        await adapter.attachDatabase(newPath, 'ghost');
        // 附加成功，空库无表
        final tables = await adapter.getTables(schemaName: 'ghost');
        expect(tables, isEmpty);
        expect(await adapter.getDatabases(), contains('ghost'));
      });

      test('attachDatabase 重复 alias → 抛错', () async {
        await connect();
        final p1 = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_dup1.db',
        );
        final p2 = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_dup2.db',
        );

        await adapter.attachDatabase(p1, 'archive');
        // 第二次 ATTACH 同名 alias 应失败
        expect(
          () => adapter.attachDatabase(p2, 'archive'),
          throwsA(isA<Object>()),
        );
      });

      test('attachDatabase 非法 alias → ArgumentError（adapter 双保险）', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_bad_alias.db',
        );

        // main 是保留名
        expect(
          () => adapter.attachDatabase(attachedPath, 'main'),
          throwsA(isA<ArgumentError>()),
        );
        // table 是关键字
        expect(
          () => adapter.attachDatabase(attachedPath, 'table'),
          throwsA(isA<ArgumentError>()),
        );
        // 非法字符
        expect(
          () => adapter.attachDatabase(attachedPath, 'a-b'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('detachDatabase 成功 → getDatabases 不再含 alias', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_detach1.db',
        );

        await adapter.attachDatabase(attachedPath, 'archive');
        expect(await adapter.getDatabases(), contains('archive'));

        await adapter.detachDatabase('archive');
        expect(await adapter.getDatabases(), isNot(contains('archive')));
      });

      test('detachDatabase 不存在的 alias → 抛错', () async {
        await connect();
        expect(() => adapter.detachDatabase('ghost'), throwsA(isA<Object>()));
      });

      test('getTables(schemaName) 返回附加库的表（不是主库）', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_tables.db',
        );

        await adapter.attachDatabase(attachedPath, 'archive');

        final mainTables = await adapter.getTables();
        expect(mainTables, contains('main_users'));
        expect(mainTables, isNot(contains('archive_orders')));

        final archiveTables = await adapter.getTables(schemaName: 'archive');
        expect(archiveTables, contains('archive_orders'));
        expect(archiveTables, isNot(contains('main_users')));
      });

      test('跨库查询：SELECT * FROM archive.archive_orders 返回数据', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_cross.db',
        );

        await adapter.attachDatabase(attachedPath, 'archive');
        final result = await adapter.executeQuery(
          'SELECT * FROM archive.archive_orders ORDER BY id',
        );
        expect(result.rows, isNotEmpty);
        expect(result.rows!.length, 3);
      });

      test('跨库 JOIN：main JOIN archive 返回连接结果', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_join.db',
        );

        await adapter.attachDatabase(attachedPath, 'archive');
        final result = await adapter.executeQuery(
          'SELECT u.name, o.amount FROM main.main_users u '
          'JOIN archive.archive_orders o ON u.id = o.user_id ORDER BY o.amount DESC',
        );
        expect(result.rows, isNotEmpty);
        // 3 行（archive_orders 有 3 行，user_id 都能 JOIN 上）
        expect(result.rows!.length, 3);
      });

      test('未连接时 attachDatabase → 抛错', () async {
        expect(
          () => adapter.attachDatabase('/tmp/x.db', 'archive'),
          throwsA(isA<Object>()),
        );
      });

      test('未连接时 detachDatabase → 抛错', () async {
        expect(() => adapter.detachDatabase('archive'), throwsA(isA<Object>()));
      });

      test('未连接时 listAttachedDatabases → 抛错', () async {
        expect(() => adapter.listAttachedDatabases(), throwsA(isA<Object>()));
      });

      // ── C16 存量缺陷修复面：per-alias 元数据限定（columns/indexes/triggers）──

      test('getTableColumns(schemaName) 返回附加库表的列（不是 main 的）', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_cols.db',
        );
        await adapter.attachDatabase(attachedPath, 'archive');

        final columns = await adapter.getTableColumns(
          'archive_orders',
          schemaName: 'archive',
        );
        expect(
          columns.map((c) => c.name),
          containsAll(['id', 'user_id', 'amount']),
        );
        // 限定查询 main 表 → 附加库无此表 → 空列（未限定时恒查 main 是原缺陷）
        final wrongSide = await adapter.getTableColumns(
          'main_users',
          schemaName: 'archive',
        );
        expect(wrongSide, isEmpty);
      });

      test('getTableIndexes(schemaName) 限定到附加库的索引', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_idx.db',
        );
        await adapter.attachDatabase(attachedPath, 'archive');
        // 附加库建显式索引（archive_orders.amount 上）。
        await adapter.executeSqlScript(
          'CREATE INDEX archive.idx_amount ON archive_orders(amount);',
        );

        final indexes = await adapter.getTableIndexes(
          'archive_orders',
          schemaName: 'archive',
        );
        expect(indexes.map((i) => i.name), contains('idx_amount'));
      });

      test('getTriggers(schemaName) 限定到附加库的触发器', () async {
        await connect();
        final attachedPath = await buildAttachedDb(
          '${DateTime.now().millisecondsSinceEpoch}_trg.db',
        );
        await adapter.attachDatabase(attachedPath, 'archive');
        // 触发体含分号，executeSqlScript 的分号切分不识别 BEGIN...END——
        // 经 executeQuery（rawUpdate 单条执行）落 DDL。
        await adapter.executeQuery(
          'CREATE TRIGGER archive.trg_guard BEFORE INSERT ON archive_orders '
          'BEGIN SELECT 1; END',
        );
        await adapter.executeQuery(
          'CREATE TRIGGER trg_main_only BEFORE INSERT ON main_users '
          'BEGIN SELECT 1; END',
        );

        final archiveTriggers = await adapter.getTriggers(
          schemaName: 'archive',
        );
        expect(archiveTriggers.map((t) => t.name), ['trg_guard']);

        final mainTriggers = await adapter.getTriggers();
        expect(
          mainTriggers.map((t) => t.name),
          everyElement(isNot('trg_guard')),
        );
      });
    });
  });
}
