// SPDX-License-Identifier: Apache-2.0
//
// spec 050：SQLite ATTACH 跨库 E2E 真库验证。
//
// 用 sqflite_ffi + 真实临时 .db 文件，覆盖 design §8 E2E 清单：
// - ATTACH 真库 → PRAGMA database_list 确认
// - 跨库 SELECT 返回数据
// - 跨库 JOIN 返回连接结果
// - DETACH → PRAGMA database_list 不含 + 跨库查询失败
// - 多附加库（2 个 → 都可见 → 各自 Detach）
// - 会话内存：断开重连后附加库列表为空
//
// 这是 spec 050 的最高价值验证——单测用 mock，widget 测成本过高，
// 唯有真库 E2E 能端到端验证 ATTACH/Detach/跨库查询的真实行为。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/sqlite_test_config.dart';

void main() {
  late SQLiteAdapter adapter;
  late String mainDbPath;

  /// 构造一个独立的 archive 风格 .db 文件（建表 + 插数据），返回路径。
  /// 调用方负责 cleanup。
  Future<String> buildArchiveDb(String tag) async {
    final path = SQLiteTestConfig.generateTestDatabasePath().replaceAll(
      RegExp(r'\.db$'),
      '_$tag.db',
    );
    final helper = SQLiteAdapter();
    final conn = DatabaseConnection(
      id: 'archive_$tag',
      name: 'archive $tag',
      host: path,
      port: 0,
      type: DatabaseType.sqlite,
    );
    expect(await helper.connect(conn), isTrue);
    await helper.executeSqlScript(
      'CREATE TABLE archive_orders('
      'id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL);'
      "INSERT INTO archive_orders(user_id, amount) VALUES "
      "(1, 99.0), (1, 10.5), (2, 50.0), (3, 7.25);",
    );
    await helper.disconnect();
    return path;
  }

  setUp(() async {
    mainDbPath = SQLiteTestConfig.generateTestDatabasePath();
    adapter = SQLiteAdapter();
    final connection = DatabaseConnection(
      id: 'test_attach_main',
      name: 'Main',
      host: mainDbPath,
      port: 0,
      type: DatabaseType.sqlite,
    );
    expect(await adapter.connect(connection), isTrue);
    // 主库建表 + 插数据，供跨库 JOIN
    await adapter.executeSqlScript(
      'CREATE TABLE main_users(id INTEGER PRIMARY KEY, name TEXT);'
      "INSERT INTO main_users(name) VALUES ('alice'), ('bob'), ('carol');",
    );
  });

  tearDown(() async {
    await adapter.disconnect();
    await SQLiteTestConfig.cleanupDatabase(mainDbPath);
  });

  group('spec 050 ATTACH 跨库（真库 E2E）', () {
    test('ATTACH 真库 → getDatabases + PRAGMA database_list 含 alias', () async {
      final archivePath = await buildArchiveDb('list');
      addTearDown(() async => SQLiteTestConfig.cleanupDatabase(archivePath));

      await adapter.attachDatabase(archivePath, 'archive');

      final dbs = await adapter.getDatabases();
      expect(dbs, contains('main'));
      expect(dbs, contains('archive'));

      // PRAGMA database_list 应有 archive 行，file 指向附加文件
      final list = await adapter.listAttachedDatabases();
      final archive = list.firstWhere((e) => e.name == 'archive');
      expect(archive.seq, greaterThan(0));
      expect(archive.file, isNotNull);
    });

    test('跨库 SELECT：SELECT * FROM archive.archive_orders 返回 4 行', () async {
      final archivePath = await buildArchiveDb('select');
      addTearDown(() async => SQLiteTestConfig.cleanupDatabase(archivePath));

      await adapter.attachDatabase(archivePath, 'archive');
      final result = await adapter.executeQuery(
        'SELECT * FROM archive.archive_orders ORDER BY id',
      );
      expect(result.rows, isNotNull);
      expect(result.rows!.length, 4);
    });

    test('跨库 JOIN：main.main_users JOIN archive.archive_orders', () async {
      final archivePath = await buildArchiveDb('join');
      addTearDown(() async => SQLiteTestConfig.cleanupDatabase(archivePath));

      await adapter.attachDatabase(archivePath, 'archive');
      final result = await adapter.executeQuery(
        'SELECT u.name AS user, o.amount AS amt '
        'FROM main.main_users u '
        'JOIN archive.archive_orders o ON u.id = o.user_id '
        'ORDER BY o.amount DESC',
      );
      expect(result.rows, isNotNull);
      // archive_orders 有 4 行（user_id 1,1,2,3），都能 JOIN 上 main_users
      expect(result.rows!.length, 4);
      // 最大 amount 99.0 对应 alice（user_id=1）
      final firstRow = result.rows!.first;
      final rowMap = firstRow;
      expect(rowMap['user'], equals('alice'));
    });

    test('DETACH → database_list 不含 alias + 跨库查询失败', () async {
      final archivePath = await buildArchiveDb('detach');
      addTearDown(() async => SQLiteTestConfig.cleanupDatabase(archivePath));

      await adapter.attachDatabase(archivePath, 'archive');
      expect(await adapter.getDatabases(), contains('archive'));

      await adapter.detachDatabase('archive');

      expect(await adapter.getDatabases(), isNot(contains('archive')));
      // 跨库查询应失败（archive 已不存在）
      expect(
        () => adapter.executeQuery('SELECT * FROM archive.archive_orders'),
        throwsA(isA<Object>()),
      );
    });

    test('多附加库：ATTACH 2 个 → 都可见 → 各自 Detach', () async {
      final p1 = await buildArchiveDb('multi1');
      final p2 = await buildArchiveDb('multi2');
      addTearDown(() async {
        await SQLiteTestConfig.cleanupDatabase(p1);
        await SQLiteTestConfig.cleanupDatabase(p2);
      });

      await adapter.attachDatabase(p1, 'arch1');
      await adapter.attachDatabase(p2, 'arch2');

      final dbs = await adapter.getDatabases();
      expect(dbs, containsAll(['arch1', 'arch2']));

      // 两个附加库的表都能查
      final r1 = await adapter.executeQuery(
        'SELECT COUNT(*) AS c FROM arch1.archive_orders',
      );
      expect(r1.rows!.first['c'], anyOf(equals(4), equals('4')));

      // Detach 第一个，第二个仍在
      await adapter.detachDatabase('arch1');
      final dbsAfter1 = await adapter.getDatabases();
      expect(dbsAfter1, isNot(contains('arch1')));
      expect(dbsAfter1, contains('arch2'));

      // Detach 第二个
      await adapter.detachDatabase('arch2');
      expect(await adapter.getDatabases(), isNot(contains('arch2')));
    });

    test('会话内存：断开重连后附加库列表为空（无持久化）', () async {
      final archivePath = await buildArchiveDb('persist');
      addTearDown(() async => SQLiteTestConfig.cleanupDatabase(archivePath));

      await adapter.attachDatabase(archivePath, 'archive');
      expect(await adapter.getDatabases(), contains('archive'));

      // 断开重连
      await adapter.disconnect();
      final reConn = DatabaseConnection(
        id: 'test_attach_main',
        name: 'Main',
        host: mainDbPath,
        port: 0,
        type: DatabaseType.sqlite,
      );
      expect(await adapter.connect(reConn), isTrue);

      // 附加库列表应空（只有 main）
      final dbs = await adapter.getDatabases();
      expect(dbs, contains('main'));
      expect(dbs, isNot(contains('archive')));
    });

    test('getTables(schemaName) 真库：附加库表 ≠ 主库表', () async {
      final archivePath = await buildArchiveDb('schema');
      addTearDown(() async => SQLiteTestConfig.cleanupDatabase(archivePath));

      await adapter.attachDatabase(archivePath, 'archive');

      final mainTables = await adapter.getTables();
      expect(mainTables, contains('main_users'));
      expect(mainTables, isNot(contains('archive_orders')));

      final archiveTables = await adapter.getTables(schemaName: 'archive');
      expect(archiveTables, contains('archive_orders'));
      expect(archiveTables, isNot(contains('main_users')));
    });

    test('DETACH 不存在的 alias → 抛错', () async {
      expect(
        () => adapter.detachDatabase('ghost'),
        throwsA(isA<Object>()),
      );
    });
  });
}
