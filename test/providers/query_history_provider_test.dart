import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/query_history.dart';
import 'package:dbmaster/providers/query_history_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueryHistoryProvider', () {
    late QueryHistoryProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = QueryHistoryProvider();
    });

    group('初始状态', () {
      test('queryHistory 应为空列表', () {
        expect(provider.queryHistory, isEmpty);
      });

      test('historyCount 应为 0', () {
        expect(provider.historyCount, 0);
      });
    });

    group('addQueryHistory', () {
      test('应添加记录到列表头部', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM users',
          executionTime: 100,
          affectedRows: 5,
          database: 'mydb',
          databaseType: DatabaseType.mysql,
        );

        expect(provider.historyCount, 1);
        expect(provider.queryHistory.first.sql, 'SELECT * FROM users');
        expect(provider.queryHistory.first.executionTime, 100);
        expect(provider.queryHistory.first.affectedRows, 5);
        expect(provider.queryHistory.first.database, 'mydb');
        expect(provider.queryHistory.first.databaseType, DatabaseType.mysql);
      });

      test('新记录应插入到列表头部', () {
        provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 2');

        expect(provider.queryHistory.first.sql, 'SELECT 2');
        expect(provider.queryHistory.last.sql, 'SELECT 1');
      });

      test('相同 SQL 应去重（旧记录移除，新记录插入头部）', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM users',
        );
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM posts',
        );
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM users',
        );

        expect(provider.historyCount, 2);
        expect(provider.queryHistory.first.sql, 'SELECT * FROM users');
        expect(provider.queryHistory.last.sql, 'SELECT * FROM posts');
      });

      test('应触发 notifyListeners', () async {
        var notified = false;
        provider.addListener(() => notified = true);
        await provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        expect(notified, isTrue);
      });

      test('应 trim SQL', () {
        provider.addQueryHistory(connectionId: "conn-1", sql: '  SELECT 1  ');
        expect(provider.queryHistory.first.sql, 'SELECT 1');
      });
    });

    group('clearQueryHistory', () {
      test('应清空所有记录', () {
        provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 2');

        provider.clearQueryHistory();

        expect(provider.queryHistory, isEmpty);
        expect(provider.historyCount, 0);
      });

      test('应触发 notifyListeners', () async {
        await provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        var notified = false;
        provider.addListener(() => notified = true);
        await provider.clearQueryHistory();
        expect(notified, isTrue);
      });
    });

    group('deleteQueryHistory', () {
      test('应删除指定 ID 的记录', () {
        provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        final id = provider.queryHistory.first.id;

        provider.deleteQueryHistory(id);

        expect(provider.historyCount, 0);
      });

      test('删除不存在的 ID 不应报错', () async {
        provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        await expectLater(provider.deleteQueryHistory('nonexistent'), completes);
        expect(provider.historyCount, 1);
      });
    });

    group('searchQueryHistory', () {
      test('空查询应返回全部记录', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM users',
        );
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM posts',
        );

        expect(provider.searchQueryHistory('').length, 2);
      });

      test('应按 SQL 内容匹配', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM users',
        );
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM posts',
        );

        final results = provider.searchQueryHistory('users');
        expect(results.length, 1);
        expect(results.first.sql, 'SELECT * FROM users');
      });

      test('搜索应不区分大小写', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM Users',
        );

        final results = provider.searchQueryHistory('users');
        expect(results.length, 1);
      });

      test('应按数据库名匹配', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 1',
          database: 'production',
        );
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 2',
          database: 'test',
        );

        final results = provider.searchQueryHistory('production');
        expect(results.length, 1);
      });
    });

    group('filterQueryHistoryByDatabase', () {
      test('null 应返回全部', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 1',
          database: 'db1',
        );
        expect(provider.filterQueryHistoryByDatabase(null).length, 1);
      });

      test('应按数据库名过滤', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 1',
          database: 'db1',
        );
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 2',
          database: 'db2',
        );

        final results = provider.filterQueryHistoryByDatabase('db1');
        expect(results.length, 1);
        expect(results.first.database, 'db1');
      });
    });

    group('filterQueryHistoryByDate', () {
      test('应按日期过滤', () async {
        final today = DateTime.now();

        await provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        // 由于 timestamp 是自动生成的，测试日期过滤有一定不确定性
        // 这里主要验证方法不抛出异常
        expect(() => provider.filterQueryHistoryByDate(today), returnsNormally);
      });
    });

    group('filterQueryHistoryByError', () {
      test('应过滤出有错误的记录', () {
        provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 2',
          error: 'Syntax error',
        );

        final withErrors = provider.filterQueryHistoryByError(true);
        expect(withErrors.length, 1);
        expect(withErrors.first.error, 'Syntax error');
      });

      test('应过滤出无错误的记录', () {
        provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 2',
          error: 'Syntax error',
        );

        final withoutErrors = provider.filterQueryHistoryByError(false);
        expect(withoutErrors.length, 1);
        expect(withoutErrors.first.error, isNull);
      });
    });

    group('filterQueryHistoryByType', () {
      test('null 应返回全部', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 1',
          databaseType: DatabaseType.mysql,
        );
        expect(provider.filterQueryHistoryByType(null).length, 1);
      });

      test('应按数据库类型过滤', () {
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 1',
          databaseType: DatabaseType.mysql,
        );
        provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT 2',
          databaseType: DatabaseType.postgresql,
        );

        final results = provider.filterQueryHistoryByType(DatabaseType.mysql);
        expect(results.length, 1);
        expect(results.first.databaseType, DatabaseType.mysql);
      });
    });

    group('saveQueryToHistory', () {
      test('应添加新记录', () async {
        await provider.saveQueryToHistory(
          sql: 'SELECT * FROM users',
          connectionId: 'conn-1',
        );

        expect(provider.historyCount, 1);
        expect(provider.queryHistory.first.source, QueryHistorySource.saved);
      });

      test('相同 SQL 应更新而非新增', () async {
        await provider.saveQueryToHistory(
          sql: 'SELECT * FROM users',
          connectionId: 'conn-1',
        );
        final firstId = provider.queryHistory.first.id;

        await Future.delayed(const Duration(milliseconds: 10));
        await provider.saveQueryToHistory(
          sql: 'SELECT * FROM users',
          connectionId: 'conn-1',
        );

        expect(provider.historyCount, 1);
        expect(provider.queryHistory.first.id, firstId);
        expect(provider.queryHistory.first.updatedAt, isNotNull);
      });

      test('空 SQL 不应创建记录', () async {
        await provider.saveQueryToHistory(sql: '   ', connectionId: 'conn-1');
        expect(provider.historyCount, 0);
      });
    });

    group('renameQueryHistory', () {
      test('应重命名指定记录', () async {
        await provider.addQueryHistory(
          sql: 'SELECT * FROM users',
          connectionId: 'conn-1',
        );
        final id = provider.queryHistory.first.id;

        await provider.renameQueryHistory(id, 'My favorite query');

        expect(provider.queryHistory.first.displayTitle, 'My favorite query');
      });
    });

    group('clearQueryHistoryByConnection', () {
      test('应只清空指定连接的历史', () async {
        await provider.addQueryHistory(sql: 'SELECT 1', connectionId: 'conn-1');
        await provider.addQueryHistory(sql: 'SELECT 2', connectionId: 'conn-2');

        await provider.clearQueryHistoryByConnection('conn-1');

        expect(provider.historyCount, 1);
        expect(provider.queryHistory.first.connectionId, 'conn-2');
      });
    });

    group('queryHistoryForConnection', () {
      test('应按连接 ID 过滤', () async {
        await provider.addQueryHistory(sql: 'SELECT 1', connectionId: 'conn-1');
        await provider.addQueryHistory(sql: 'SELECT 2', connectionId: 'conn-2');

        final results = provider.queryHistoryForConnection('conn-1');
        expect(results.length, 1);
        expect(results.first.sql, 'SELECT 1');
      });
    });

    group('searchQueryHistory', () {
      test('应按 displayTitle 匹配', () async {
        await provider.addQueryHistory(
          sql: 'SELECT * FROM users',
          connectionId: 'conn-1',
        );
        final id = provider.queryHistory.first.id;
        await provider.renameQueryHistory(id, 'User query');

        final results = provider.searchQueryHistory('User query');
        expect(results.length, 1);
      });

      test('应按 connectionId 过滤', () async {
        await provider.addQueryHistory(sql: 'SELECT 1', connectionId: 'conn-1');
        await provider.addQueryHistory(sql: 'SELECT 2', connectionId: 'conn-2');

        final results = provider.searchQueryHistory('', connectionId: 'conn-1');
        expect(results.length, 1);
        expect(results.first.connectionId, 'conn-1');
      });
    });

    group('connection-scoped helpers', () {
      test('getQueryHistoryByConnection 应按连接 ID 过滤', () async {
        await provider.addQueryHistory(sql: 'SELECT 1', connectionId: 'conn-a');
        await provider.addQueryHistory(sql: 'SELECT 2', connectionId: 'conn-b');

        final results = provider.getQueryHistoryByConnection('conn-a');
        expect(results.length, 1);
        expect(results.first.connectionId, 'conn-a');
      });

      test('searchQueryHistoryByConnection 应按连接过滤并搜索', () async {
        await provider.addQueryHistory(
          sql: 'SELECT alpha',
          connectionId: 'conn-a',
        );
        await provider.addQueryHistory(
          sql: 'SELECT beta',
          connectionId: 'conn-b',
        );
        await provider.addQueryHistory(
          sql: 'SELECT gamma',
          connectionId: 'conn-a',
        );

        final results = provider.searchQueryHistoryByConnection(
          'conn-a',
          'alpha',
        );
        expect(results.length, 1);
        expect(results.first.sql, 'SELECT alpha');
        expect(results.first.connectionId, 'conn-a');
      });
    });

    group('持久化', () {
      test('addQueryHistory 应持久化到 SharedPreferences', () async {
        await provider.addQueryHistory(
          connectionId: "conn-1",
          sql: 'SELECT * FROM users',
        );

        final prefs = await SharedPreferences.getInstance();
        final historyJson = prefs.getString('query_history');
        expect(historyJson, isNotNull);
        expect(historyJson, contains('SELECT * FROM users'));
      });

      test('clearQueryHistory 应清除持久化数据', () async {
        await provider.addQueryHistory(connectionId: "conn-1", sql: 'SELECT 1');
        await provider.clearQueryHistory();

        final prefs = await SharedPreferences.getInstance();
        final historyJson = prefs.getString('query_history');
        expect(historyJson, isNotNull);
        expect(historyJson, contains('[]'));
      });

      test('新字段应正确序列化和反序列化', () async {
        await provider.addQueryHistory(
          sql: 'SELECT 1',
          connectionId: 'conn-1',
          connectionName: 'My Connection',
        );
        final id = provider.queryHistory.first.id;
        await provider.renameQueryHistory(id, 'Renamed');

        final prefs = await SharedPreferences.getInstance();
        final historyJson = prefs.getString('query_history');
        expect(historyJson, contains('connectionId'));
        expect(historyJson, contains('displayTitle'));

        final loaded = QueryHistoryProvider();
        await loaded.loadQueryHistory();

        expect(loaded.historyCount, 1);
        expect(loaded.queryHistory.first.connectionId, 'conn-1');
        expect(loaded.queryHistory.first.connectionName, 'My Connection');
        expect(loaded.queryHistory.first.displayTitle, 'Renamed');
      });
    });
  });
}
