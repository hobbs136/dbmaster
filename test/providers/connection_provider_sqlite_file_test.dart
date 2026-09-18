import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/providers/connection_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个 SQLite DbServer（仅用于测试，避开 SecureStorage / 真实连接）。
DbServer _sqlite(String host, {String id = 's', DateTime? lastConnected}) {
  return DbServer(
    id: id,
    name: host,
    type: DatabaseType.sqlite,
    host: host,
    port: 0,
    lastConnected: lastConnected,
  );
}

DbServer _mysql(String id, {DateTime? lastConnected}) {
  return DbServer(
    id: id,
    name: id,
    type: DatabaseType.mysql,
    host: 'localhost',
    port: 3306,
    lastConnected: lastConnected,
  );
}

void main() {
  group('ConnectionProvider SQLite 文件辅助函数', () {
    group('isSqliteFilePath', () {
      test('识别受支持的扩展名（大小写不敏感）', () {
        expect(ConnectionProvider.isSqliteFilePath('/a/b/c.db'), isTrue);
        expect(ConnectionProvider.isSqliteFilePath('C:/x/y.SQLITE'), isTrue);
        expect(ConnectionProvider.isSqliteFilePath('f.sqlite3'), isTrue);
        expect(ConnectionProvider.isSqliteFilePath('f.db3'), isTrue);
      });

      test('拒绝非 SQLite 扩展名 / 空路径', () {
        expect(ConnectionProvider.isSqliteFilePath('/a/b.txt'), isFalse);
        expect(ConnectionProvider.isSqliteFilePath('/a/b.json'), isFalse);
        expect(ConnectionProvider.isSqliteFilePath('noext'), isFalse);
        expect(ConnectionProvider.isSqliteFilePath(''), isFalse);
      });
    });

    group('normalizeSqlitePath', () {
      test('反斜杠转正斜杠 + 小写盘符', () {
        expect(
          ConnectionProvider.normalizeSqlitePath(r'C:\Users\me\a.db'),
          'c:/Users/me/a.db',
        );
      });

      test('已是正斜杠时盘符小写、其余不变', () {
        expect(
          ConnectionProvider.normalizeSqlitePath('D:/data/x.sqlite'),
          'd:/data/x.sqlite',
        );
      });

      test('修剪首尾空白', () {
        expect(ConnectionProvider.normalizeSqlitePath('  /a/b.db  '), '/a/b.db');
      });
    });

    group('sqliteDisplayName', () {
      test('去除扩展名', () {
        expect(ConnectionProvider.sqliteDisplayName('/a/b/my db.db'), 'my db');
        expect(ConnectionProvider.sqliteDisplayName(r'C:\x\y.sqlite3'), 'y');
      });

      test('无扩展名返回完整文件名', () {
        expect(ConnectionProvider.sqliteDisplayName('/a/b/noext'), 'noext');
      });
    });

    group('buildSqliteServer', () {
      test('字段正确且 name 取自文件名', () {
        final now = DateTime.utc(2026, 7, 9);
        final s = ConnectionProvider.buildSqliteServer(
          '/path/to/inventory.db',
          now: now,
        );

        expect(s.type, DatabaseType.sqlite);
        expect(s.host, '/path/to/inventory.db');
        expect(s.name, 'inventory');
        expect(s.port, 0);
        expect(s.username, isNull);
        expect(s.password, isNull);
        expect(s.database, isNull);
        expect(s.useSSL, isFalse);
        expect(s.lastConnected, now);
        expect(s.id, startsWith('sqlite_'));
      });
    });

    group('findExistingSqlite', () {
      final a = _sqlite('/a/b.db', id: 'a');
      final b = _sqlite(r'C:\Users\me\x.sqlite', id: 'b');
      final all = [a, b, _mysql('m')];

      test('规范化后命中既有 SQLite 连接', () {
        final hit = ConnectionProvider.findExistingSqlite(
          all,
          ConnectionProvider.normalizeSqlitePath('C:/Users/me/x.sqlite'),
        );
        expect(hit?.id, 'b');
      });

      test('未命中返回 null', () {
        expect(
          ConnectionProvider.findExistingSqlite(all, '/nope/db.sqlite'),
          isNull,
        );
      });

      test('忽略非 SQLite 连接', () {
        expect(
          ConnectionProvider.findExistingSqlite(all, 'localhost'),
          isNull,
        );
      });
    });

    group('sortRecentSqlite', () {
      final t1 = DateTime.utc(2026, 7, 1);
      final t2 = DateTime.utc(2026, 7, 5);
      final t3 = DateTime.utc(2026, 7, 9);

      test('按 lastConnected 降序（最近在前）', () {
        final all = [
          _sqlite('/old.db', id: '1', lastConnected: t1),
          _sqlite('/new.db', id: '3', lastConnected: t3),
          _sqlite('/mid.db', id: '2', lastConnected: t2),
        ];
        final sorted = ConnectionProvider.sortRecentSqlite(all);
        expect(sorted.map((s) => s.id), ['3', '2', '1']);
      });

      test('过滤掉非 SQLite 连接', () {
        final all = [
          _sqlite('/a.db', id: 'a', lastConnected: t2),
          _mysql('m', lastConnected: t3),
        ];
        final sorted = ConnectionProvider.sortRecentSqlite(all);
        expect(sorted, hasLength(1));
        expect(sorted.first.id, 'a');
      });

      test('null lastConnected 排到末尾', () {
        final all = [
          _sqlite('/null.db', id: 'n', lastConnected: null),
          _sqlite('/old.db', id: 'o', lastConnected: t1),
        ];
        final sorted = ConnectionProvider.sortRecentSqlite(all);
        expect(sorted.map((s) => s.id), ['o', 'n']);
      });

      test('超过 limit 时截断', () {
        final all = [
          for (var i = 0; i < 10; i++)
            _sqlite(
              '/f$i.db',
              id: '$i',
              lastConnected: t1.add(Duration(days: i)),
            ),
        ];
        final sorted = ConnectionProvider.sortRecentSqlite(all, limit: 3);
        expect(sorted, hasLength(3));
        // 最近三天：i = 9, 8, 7
        expect(sorted.map((s) => s.id), ['9', '8', '7']);
      });

      test('返回不可变列表', () {
        final sorted = ConnectionProvider.sortRecentSqlite([
          _sqlite('/a.db', id: 'a', lastConnected: t1),
        ]);
        expect(
          () => sorted.add(_sqlite('/b.db', id: 'b')),
          throwsUnsupportedError,
        );
      });
    });

    group('firstSqlitePath', () {
      test('返回首个受支持的 SQLite 路径', () {
        expect(
          ConnectionProvider.firstSqlitePath(['/a.txt', '/b/c.db', '/d/x.json']),
          '/b/c.db',
        );
      });

      test('无 SQLite 文件时返回 null', () {
        expect(
          ConnectionProvider.firstSqlitePath(['/a.txt', '/b/c.json']),
          isNull,
        );
      });

      test('空列表返回 null', () {
        expect(ConnectionProvider.firstSqlitePath(<String>[]), isNull);
      });
    });
  });
}
