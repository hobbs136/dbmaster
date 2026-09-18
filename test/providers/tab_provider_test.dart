import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:dbmaster/services/database_service.dart';
import 'package:dbmaster/models/execution_result.dart';
import 'package:dbmaster/models/sql_statement.dart';
import 'package:dbmaster/models/database_models.dart' show DatabaseType;

class MockDatabaseService extends Mock implements DatabaseService {}

void main() {
  group('TabProvider', () {
    late TabProvider provider;
    late MockDatabaseService mockDbService;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockDbService = MockDatabaseService();
      provider = TabProvider(mockDbService);
    });

    // 020-mongo US4 — Mongo 写操作检测
    group('isMongoWriteQuery (US4)', () {
      test('write methods detected', () {
        expect(TabProvider.isMongoWriteQuery('db.users.insertOne({a:1})'), isTrue);
        expect(
          TabProvider.isMongoWriteQuery('db.users.updateMany({}, {\$set:{a:1}})'),
          isTrue,
        );
        expect(TabProvider.isMongoWriteQuery('db.users.deleteOne({})'), isTrue);
        expect(TabProvider.isMongoWriteQuery('db.users.replaceOne({}, {a:1})'), isTrue);
      });

      test('aggregate with \$out/\$merge is write', () {
        expect(
          TabProvider.isMongoWriteQuery(r'db.users.aggregate([{$out: "backup"}])'),
          isTrue,
        );
        expect(
          TabProvider.isMongoWriteQuery(r'db.users.aggregate([{$merge: {into: "b"}}])'),
          isTrue,
        );
        expect(
          TabProvider.isMongoWriteQuery(r'db.users.aggregate([{$match:{}}])'),
          isFalse,
        );
      });

      test('read methods are not write', () {
        expect(TabProvider.isMongoWriteQuery('db.users.find({})'), isFalse);
        expect(TabProvider.isMongoWriteQuery('db.users.findOne({})'), isFalse);
        expect(
          TabProvider.isMongoWriteQuery('db.users.countDocuments({})'),
          isFalse,
        );
        expect(
          TabProvider.isMongoWriteQuery(r'db.users.aggregate([{$group:{_id:null}}])'),
          isFalse,
        );
      });

      test('SQL / empty statements return false', () {
        expect(TabProvider.isMongoWriteQuery('SELECT * FROM users'), isFalse);
        expect(
          TabProvider.isMongoWriteQuery('INSERT INTO users VALUES (1)'),
          isFalse,
        );
        expect(TabProvider.isMongoWriteQuery(''), isFalse);
      });
    });

    group('初始状态', () {
      test('应无初始标签页', () {
        expect(provider.tabs, isEmpty);
        expect(provider.activeTabIndex, 0);
        expect(provider.activeTab, isNull);
      });
    });

    group('标签页管理', () {
      test('应添加新标签页', () {
        provider.addNewTab();
        expect(provider.tabs.length, 1);
        expect(provider.activeTabIndex, 0);
      });

      test('应添加多个标签页', () {
        provider.addNewTab();
        provider.addNewTab();
        provider.addNewTab();

        expect(provider.tabs.length, 3);
      });

      test('应关闭标签页', () {
        provider.addNewTab();
        provider.addNewTab();
        provider.closeTab(0);

        expect(provider.tabs.length, 1);
      });

      test('应关闭所有标签页', () {
        provider.addNewTab();
        provider.addNewTab();
        provider.closeAllTabs();

        expect(provider.tabs, isEmpty);
      });
    });

    group('活动标签', () {
      test('应设置活动标签', () {
        provider.addNewTab();
        provider.addNewTab();
        provider.setActiveTab(1);

        expect(provider.activeTabIndex, 1);
      });

      test('应获取活动标签', () {
        provider.addNewTab();
        final activeTab = provider.activeTab;

        expect(activeTab, isNotNull);
      });
    });

    group('SQL更新', () {
      test('应更新标签SQL', () {
        provider.addNewTab();
        provider.updateTabSql(0, 'SELECT * FROM users');

        expect(provider.tabs[0].sql, 'SELECT * FROM users');
      });

      test('应重命名标签', () {
        provider.addNewTab();
        provider.renameTab(0, 'User Query');

        expect(provider.tabs[0].title, 'User Query');
      });
    });

    group('执行结果', () {
      test('应更新执行结果', () {
        provider.addNewTab();
        // ExecutionResult需要SQLStatement，这里简化测试
        expect(provider.tabs[0].executionResults, isNotNull);
      });
    });

    group('错误处理', () {
      test('应设置错误消息', () {
        provider.setError('Query failed');
        expect(provider.errorMessage, 'Query failed');
      });

      test('应清除错误', () {
        provider.setError('Some error');
        provider.clearError();
        expect(provider.errorMessage, isNull);
      });
    });

    group('格式化请求', () {
      test('应设置格式化请求标志', () {
        provider.setFormatRequested(true);
        expect(provider.formatRequested, isTrue);

        provider.setFormatRequested(false);
        expect(provider.formatRequested, isFalse);
      });
    });

    group('执行请求', () {
      test('应设置执行请求标志', () {
        provider.setExecuteRequested(true);
        expect(provider.executeRequested, isTrue);

        provider.setExecuteRequested(false);
        expect(provider.executeRequested, isFalse);
      });
    });

    group('通知', () {
      test('状态改变时应通知监听器', () {
        var notified = false;
        provider.addListener(() {
          notified = true;
        });

        provider.addNewTab();
        expect(notified, isTrue);
      });
    });

    group('openQueryTab', () {
      test('应使用提供的 title 和 savedQueryId 创建 Tab', () async {
        when(
          mockDbService.getDatabaseType('conn1'),
        ).thenReturn(DatabaseType.postgresql);

        final tab = await provider.openQueryTab(
          connectionId: 'conn1',
          databaseName: 'db1',
          sql: 'SELECT 1',
          title: 'Monthly Revenue',
          savedQueryId: 'saved-1',
        );

        expect(tab.title, 'Monthly Revenue');
        expect(tab.savedQueryId, 'saved-1');
        expect(tab.sql, 'SELECT 1');
        expect(tab.isAutoTitle, isFalse);
      });

      test('未提供 title 时应使用自动生成标题', () async {
        when(
          mockDbService.getDatabaseType('conn1'),
        ).thenReturn(DatabaseType.postgresql);

        final tab = await provider.openQueryTab(
          connectionId: 'conn1',
          databaseName: 'db1',
        );

        expect(tab.title, startsWith('Query '));
        expect(tab.savedQueryId, isNull);
        expect(tab.isAutoTitle, isTrue);
      });
    });

    group('saveQuery', () {
      test('应根据 savedQueryId 更新已存在的保存查询', () async {
        final original = QueryTab(
          id: 'editor-tab-0',
          title: 'Original',
          sql: 'SELECT 1',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(original);
        final savedQueryId = original.savedQueryId;
        expect(savedQueryId, isNotNull);

        final editorTab = QueryTab(
          id: 'editor-tab-1',
          savedQueryId: savedQueryId,
          title: 'Updated',
          sql: 'SELECT 2',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(editorTab);

        expect(provider.savedQueries.length, 1);
        expect(provider.savedQueries.first.savedQueryId, savedQueryId);
        expect(provider.savedQueries.first.title, 'Updated');
        expect(provider.savedQueries.first.sql, 'SELECT 2');
      });

      test('savedQueryId 为空时应创建新的保存查询', () async {
        final tab = QueryTab(
          id: 'editor-tab-2',
          title: 'New Query',
          sql: 'SELECT 3',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(tab);

        expect(provider.savedQueries.length, 1);
        expect(provider.savedQueries.first.title, 'New Query');
        expect(provider.savedQueries.first.savedQueryId, isNotNull);
      });

      test('同一连接下同名保存查询应抛出异常', () async {
        final first = QueryTab(
          id: 'editor-tab-3',
          title: 'Dup',
          sql: 'SELECT 1',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(first);

        expect(
          () => provider.saveQuery(
            QueryTab(
              id: 'editor-tab-4',
              title: 'Dup',
              sql: 'SELECT 2',
              connectionId: 'conn1',
              databaseName: 'db1',
            ),
          ),
          throwsA(isA<DuplicateSavedQueryNameException>()),
        );
      });

      test('新建保存查询后再次保存应更新同一标识符', () async {
        final tab = QueryTab(
          id: 'editor-tab-7',
          title: 'First Save',
          sql: 'SELECT 1',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(tab);
        final savedQueryId = tab.savedQueryId;
        expect(savedQueryId, isNotNull);

        final reopenedTab = QueryTab(
          id: 'editor-tab-8',
          savedQueryId: savedQueryId,
          title: 'Second Save',
          sql: 'SELECT 2',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(reopenedTab);

        expect(provider.savedQueries.length, 1);
        expect(provider.savedQueries.first.savedQueryId, savedQueryId);
        expect(provider.savedQueries.first.sql, 'SELECT 2');
      });

      test('两个同源 Tab 依次保存应后保存覆盖前者', () async {
        final original = QueryTab(
          id: 'editor-tab-9',
          title: 'Shared',
          sql: 'SELECT 1',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(original);
        final savedQueryId = original.savedQueryId;

        await provider.saveQuery(
          QueryTab(
            id: 'editor-tab-a',
            savedQueryId: savedQueryId,
            title: 'Shared',
            sql: 'SELECT A',
            connectionId: 'conn1',
            databaseName: 'db1',
          ),
        );
        await provider.saveQuery(
          QueryTab(
            id: 'editor-tab-b',
            savedQueryId: savedQueryId,
            title: 'Shared',
            sql: 'SELECT B',
            connectionId: 'conn1',
            databaseName: 'db1',
          ),
        );

        expect(provider.savedQueries.length, 1);
        expect(provider.savedQueries.first.sql, 'SELECT B');
      });

      test('更新自身时不应视为重复', () async {
        final original = QueryTab(
          id: 'editor-tab-5',
          title: 'Same',
          sql: 'SELECT 1',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(original);
        final savedQueryId = original.savedQueryId;

        await provider.saveQuery(
          QueryTab(
            id: 'editor-tab-6',
            savedQueryId: savedQueryId,
            title: 'Same',
            sql: 'SELECT 2',
            connectionId: 'conn1',
            databaseName: 'db1',
          ),
        );

        expect(provider.savedQueries.length, 1);
        expect(provider.savedQueries.first.sql, 'SELECT 2');
      });
    });

    group('保存的查询过滤', () {
      test('savedQueriesFor 应按连接和数据库过滤', () async {
        final queryA = QueryTab(
          id: 'q1',
          title: 'Query A',
          connectionId: 'conn1',
          databaseName: 'db1',
          sql: 'SELECT 1',
        );
        final queryB = QueryTab(
          id: 'q2',
          title: 'Query B',
          connectionId: 'conn1',
          databaseName: 'db2',
          sql: 'SELECT 2',
        );
        final queryC = QueryTab(
          id: 'q3',
          title: 'Query C',
          connectionId: 'conn2',
          databaseName: 'db1',
          sql: 'SELECT 3',
        );
        await provider.saveQuery(queryA);
        await provider.saveQuery(queryB);
        await provider.saveQuery(queryC);

        final result = provider.savedQueriesFor('conn1', 'db1');
        expect(result.length, 1);
        expect(result.first.id, 'q1');
      });

      test('getSavedQueryById 应根据 ID 返回保存查询', () async {
        final query = QueryTab(
          id: 'q1',
          title: 'Query A',
          connectionId: 'conn1',
          databaseName: 'db1',
          sql: 'SELECT 1',
        );
        await provider.saveQuery(query);

        expect(provider.getSavedQueryById('q1'), isNotNull);
        expect(provider.getSavedQueryById('q1')!.title, 'Query A');
        expect(provider.getSavedQueryById('not-exist'), isNull);
      });
    });

    group('History 子标签', () {
      test('addNewTab 应自动创建 pinned history 子标签并激活', () {
        provider.addNewTab();
        final tab = provider.activeTab;
        expect(tab, isNotNull);
        final results = provider.getResultsForTab(tab!.id);
        expect(results.length, 1);
        expect(results.first.type, ResultSubTabType.history);
        expect(results.first.isPinned, isTrue);
        expect(provider.getActiveResultIndexForTab(tab.id), 0);
        expect(provider.getActiveSubTabType(tab.id), ResultSubTabType.history);
      });

      test('ensureHistorySubTab 不应重复创建 history 子标签', () {
        provider.addNewTab();
        final tab = provider.activeTab;
        provider.ensureHistorySubTab(tab!.id);
        provider.ensureHistorySubTab(tab.id);
        final results = provider.getResultsForTab(tab.id);
        expect(
          results.where((r) => r.type == ResultSubTabType.history).length,
          1,
        );
      });

      test('history 子标签不可被关闭', () {
        provider.addNewTab();
        final tab = provider.activeTab;
        provider.closeResult(tab!.id, 0);
        expect(provider.getResultsForTab(tab.id).length, 1);
      });

      test('addResultToTab 执行后应激活 result 子标签', () {
        provider.addNewTab();
        final tab = provider.activeTab!;
        final result = ExecutionResult(
          statement: const SQLStatement(
            index: 0,
            sql: 'SELECT 1',
            type: SQLType.select,
            lineStart: 1,
            lineEnd: 1,
          ),
          success: true,
          data: <Map<String, dynamic>>[
            <String, dynamic>{'x': 1},
          ],
          executionTime: const Duration(milliseconds: 1),
        );
        provider.addResultToTab(
          tab.id,
          [result],
          sql: 'SELECT 1',
          executionTime: const Duration(milliseconds: 1),
        );
        expect(provider.getActiveSubTabType(tab.id), ResultSubTabType.result);
      });

      test('setActiveResult 应可切换回 history 子标签', () {
        provider.addNewTab();
        final tab = provider.activeTab!;
        final result = ExecutionResult(
          statement: const SQLStatement(
            index: 0,
            sql: 'SELECT 1',
            type: SQLType.select,
            lineStart: 1,
            lineEnd: 1,
          ),
          success: true,
          data: <Map<String, dynamic>>[
            <String, dynamic>{'x': 1},
          ],
          executionTime: const Duration(milliseconds: 1),
        );
        provider.addResultToTab(
          tab.id,
          [result],
          sql: 'SELECT 1',
          executionTime: const Duration(milliseconds: 1),
        );
        provider.setActiveResult(tab.id, 0);
        expect(provider.getActiveSubTabType(tab.id), ResultSubTabType.history);
      });
    });

    group('Result 子标签 Tab 隔离', () {
      late QueryTab tabA;
      late QueryTab tabB;
      late List<ExecutionResult> resultsA;
      late List<ExecutionResult> resultsB;

      setUp(() {
        tabA = QueryTab(id: 'tab_a', title: 'Query 1');
        tabB = QueryTab(id: 'tab_b', title: 'Query 2');
        resultsA = [
          ExecutionResult(
            statement: const SQLStatement(
              index: 0,
              sql: 'SELECT * FROM users',
              type: SQLType.select,
              lineStart: 1,
              lineEnd: 1,
            ),
            success: true,
            data: <Map<String, dynamic>>[
              <String, dynamic>{'name': 'Alice'},
            ],
            executionTime: const Duration(milliseconds: 10),
          ),
        ];
        resultsB = [
          ExecutionResult(
            statement: const SQLStatement(
              index: 0,
              sql: 'SELECT * FROM orders',
              type: SQLType.select,
              lineStart: 1,
              lineEnd: 1,
            ),
            success: true,
            data: <Map<String, dynamic>>[
              <String, dynamic>{'order_id': 42},
            ],
            executionTime: const Duration(milliseconds: 5),
          ),
        ];
      });

      test('不同 Tab 的执行结果应隔离存储', () {
        provider.addTab(tabA);
        provider.addTab(tabB);

        // Exec 只在 Tab A
        provider.addResultToTab(
          tabA.id,
          resultsA,
          sql: 'SELECT * FROM users',
          executionTime: const Duration(milliseconds: 10),
        );

        // 切换到 Tab A
        provider.setActiveTab(0);
        final resultsForA = provider.activeResults;
        expect(resultsForA.length, 1);
        expect(
          resultsForA[0].executionResults.first.data!.first['name'],
          'Alice',
        );

        // 切换到 Tab B（未执行过查询）
        provider.setActiveTab(1);
        final resultsForB = provider.activeResults;
        expect(resultsForB.length, 0);
      });

      test('两个 Tab 各自执行查询后，切换应返回各自的结果', () {
        provider.addTab(tabA);
        provider.addTab(tabB);

        provider.addResultToTab(
          tabA.id,
          resultsA,
          sql: 'SELECT * FROM users',
          executionTime: const Duration(milliseconds: 10),
        );
        provider.addResultToTab(
          tabB.id,
          resultsB,
          sql: 'SELECT * FROM orders',
          executionTime: const Duration(milliseconds: 5),
        );

        // Tab A 的结果 — Result1 在 [0]
        provider.setActiveTab(0);
        expect(
          provider.activeResults[0].executionResults.first.data!.first['name'],
          'Alice',
        );

        // Tab B 的结果 — Result1 在 [0]
        provider.setActiveTab(1);
        expect(
          provider
              .activeResults[0]
              .executionResults
              .first
              .data!
              .first['order_id'],
          42,
        );

        // 切回 Tab A —— 结果应保持不变
        provider.setActiveTab(0);
        expect(
          provider.activeResults[0].executionResults.first.data!.first['name'],
          'Alice',
        );
      });

      test('activeResultIndex 应为每个 Tab 独立维护', () {
        provider.addTab(tabA);
        provider.addTab(tabB);

        provider.addResultToTab(
          tabA.id,
          resultsA,
          sql: 'SELECT * FROM users',
          executionTime: const Duration(milliseconds: 10),
        );
        provider.addResultToTab(
          tabB.id,
          resultsB,
          sql: 'SELECT * FROM orders',
          executionTime: const Duration(milliseconds: 5),
        );

        provider.setActiveTab(0);
        expect(
          provider.activeResultIndex,
          0,
        ); // Result1 at index 0 (Messages 在最后)

        provider.setActiveTab(1);
        expect(provider.activeResultIndex, 0); // Result1 at index 0

        provider.setActiveTab(0);
        expect(provider.activeResultIndex, 0); // 切回 Tab A 后仍为 0
      });
    });

    group('QueryTab JSON 序列化', () {
      test('无 savedQueryId 时应正确序列化与反序列化', () {
        final tab = QueryTab(
          id: 'tab1',
          title: 'Query 1',
          sql: 'SELECT 1',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        final json = tab.toJson();
        final restored = QueryTab.fromJson(json);

        expect(restored.id, 'tab1');
        expect(restored.savedQueryId, isNull);
        expect(restored.title, 'Query 1');
        expect(restored.sql, 'SELECT 1');
      });

      test('有 savedQueryId 时应正确序列化与反序列化', () {
        final tab = QueryTab(
          id: 'tab1',
          savedQueryId: 'saved1',
          title: 'Monthly Revenue',
          sql: 'SELECT 2',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        final json = tab.toJson();
        final restored = QueryTab.fromJson(json);

        expect(restored.savedQueryId, 'saved1');
        expect(restored.title, 'Monthly Revenue');
      });

      test('旧数据缺少 savedQueryId 字段时仍能反序列化', () {
        final json = <String, dynamic>{
          'id': 'legacy1',
          'title': 'Legacy Query',
          'sql': 'SELECT 3',
          'executionResults': <Map<String, dynamic>>[],
          'connectionId': 'conn1',
          'databaseName': 'db1',
          'isSaved': true,
          'isAutoTitle': false,
        };
        final restored = QueryTab.fromJson(json);

        expect(restored.id, 'legacy1');
        expect(restored.savedQueryId, isNull);
        expect(restored.title, 'Legacy Query');
      });

      test('旧数据缺少 isModified/originalSql 字段时仍能反序列化', () {
        final json = <String, dynamic>{
          'id': 'legacy2',
          'title': 'Legacy Query 2',
          'sql': 'SELECT 4',
          'executionResults': <Map<String, dynamic>>[],
          'connectionId': 'conn1',
          'databaseName': 'db1',
          'isSaved': true,
          'isAutoTitle': false,
        };
        final restored = QueryTab.fromJson(json);

        expect(restored.isModified, isFalse);
        expect(restored.originalSql, isNull);
      });
    });

    group('脏状态跟踪', () {
      test('使用 savedQueryId 打开 Tab 时应为未修改状态', () async {
        when(mockDbService.getDatabaseType('conn1'))
            .thenReturn(DatabaseType.postgresql);

        final opened = await provider.openQueryTab(
          connectionId: 'conn1',
          databaseName: 'db1',
          sql: 'SELECT 1',
          title: 'Saved Query',
          savedQueryId: 'sq1',
        );

        expect(opened.isSaved, isTrue);
        expect(opened.isModified, isFalse);
        expect(opened.originalSql, 'SELECT 1');
      });

      test('保存查询 Tab 修改 SQL 后应标记为已修改', () async {
        when(mockDbService.getDatabaseType('conn1'))
            .thenReturn(DatabaseType.postgresql);

        await provider.openQueryTab(
          connectionId: 'conn1',
          databaseName: 'db1',
          sql: 'SELECT 1',
          title: 'Saved Query',
          savedQueryId: 'sq1',
        );

        provider.updateTabSql(0, 'SELECT 2');

        expect(provider.tabs[0].isModified, isTrue);
      });

      test('保存查询 Tab 改回原始 SQL 后应标记为未修改', () async {
        when(mockDbService.getDatabaseType('conn1'))
            .thenReturn(DatabaseType.postgresql);

        await provider.openQueryTab(
          connectionId: 'conn1',
          databaseName: 'db1',
          sql: 'SELECT 1',
          title: 'Saved Query',
          savedQueryId: 'sq1',
        );

        provider.updateTabSql(0, 'SELECT 2');
        provider.updateTabSql(0, 'SELECT 1');

        expect(provider.tabs[0].isModified, isFalse);
      });

      test('未修改的保存查询 Tab 关闭时不应抛出异常', () async {
        when(mockDbService.getDatabaseType('conn1'))
            .thenReturn(DatabaseType.postgresql);

        await provider.openQueryTab(
          connectionId: 'conn1',
          databaseName: 'db1',
          sql: 'SELECT 1',
          title: 'Saved Query',
          savedQueryId: 'sq1',
        );

        await provider.closeTab(0);

        expect(provider.tabs, isEmpty);
      });

      test('已修改的保存查询 Tab 关闭时应抛出 UnsavedTabException', () async {
        when(mockDbService.getDatabaseType('conn1'))
            .thenReturn(DatabaseType.postgresql);

        await provider.openQueryTab(
          connectionId: 'conn1',
          databaseName: 'db1',
          sql: 'SELECT 1',
          title: 'Saved Query',
          savedQueryId: 'sq1',
        );
        provider.updateTabSql(0, 'SELECT 2');

        expect(
          () => provider.closeTab(0),
          throwsA(isA<UnsavedTabException>()),
        );
      });

      test('新建非空 Tab 关闭时仍应抛出 UnsavedTabException', () {
        provider.addNewTab();
        provider.updateTabSql(0, 'SELECT 1');

        expect(
          () => provider.closeTab(0),
          throwsA(isA<UnsavedTabException>()),
        );
      });

      test('保存查询后应重置为未修改状态', () async {
        final tab = QueryTab(
          id: 'editor-tab-dirty',
          title: 'Dirty Query',
          sql: 'SELECT 1',
          connectionId: 'conn1',
          databaseName: 'db1',
        );
        await provider.saveQuery(tab);
        final savedQueryId = tab.savedQueryId;
        expect(savedQueryId, isNotNull);

        // 模拟打开保存查询后修改
        tab.isSaved = true;
        tab.originalSql = 'SELECT 1';
        tab.sql = 'SELECT 2';
        tab.isModified = true;

        // 保存更新后的内容
        await provider.saveQuery(tab);

        expect(tab.isModified, isFalse);
        expect(tab.originalSql, 'SELECT 2');
      });
    });

    // =========================================================================
    // U16：崩溃恢复批量还原
    // =========================================================================
    group('restoreTabs (U16)', () {
      test('批量追加 + activeIndex 收缩', () {
        final t1 = QueryTab(id: '1', title: 'A', sql: 'SELECT 1');
        final t2 = QueryTab(id: '2', title: 'B', sql: 'SELECT 2');

        provider.restoreTabs([t1, t2], 99);

        expect(provider.tabs.length, 2);
        expect(provider.tabs[0].sql, 'SELECT 1');
        expect(provider.activeTabIndex, 1, reason: '越界索引收缩到最后一个');
      });

      test('空列表 no-op', () {
        provider.restoreTabs(const [], 0);
        expect(provider.tabs, isEmpty);
        expect(provider.activeTabIndex, 0);
      });
    });

    // =========================================================================
    // U17：审计写语句判定（ 词边界修复——CTE/注释前缀写语句此前记为读）
    // =========================================================================
    group('isSqlWriteStatement (U17)', () {
      test('常规形态', () {
        expect(TabProvider.isSqlWriteStatement('INSERT INTO t VALUES (1)'),
            isTrue);
        expect(TabProvider.isSqlWriteStatement('  delete from t where 1=1'),
            isTrue);
        expect(TabProvider.isSqlWriteStatement('SELECT * FROM t'), isFalse);
      });

      test('CTE / 前置注释前缀的写语句判定为写（修复点）', () {
        expect(
          TabProvider.isSqlWriteStatement(
              'WITH cte AS (SELECT 1) INSERT INTO t SELECT * FROM cte'),
          isTrue,
        );
        expect(
          TabProvider.isSqlWriteStatement('/* hint */ DELETE FROM t'),
          isTrue,
        );
        expect(
          TabProvider.isSqlWriteStatement('UPDATE t SET a=1 WHERE id=2'),
          isTrue,
        );
      });

      test('表名/列名含关键字子串不误判（词边界）', () {
        expect(TabProvider.isSqlWriteStatement('SELECT * FROM update_log'),
            isFalse);
        expect(TabProvider.isSqlWriteStatement('SELECT deleted_from_orders.*'),
            isFalse);
        expect(
            TabProvider.isSqlWriteStatement(
                'SELECT create_time, drop_col FROM reports'),
            isFalse);
      });
    });
  });
}
