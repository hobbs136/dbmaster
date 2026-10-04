import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/providers/sidebar_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SidebarProvider', () {
    late SidebarProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = SidebarProvider();
    });

    group('初始状态', () {
      test('selectedConnectionId 应为 null', () {
        expect(provider.selectedConnectionId, isNull);
      });

      test('selectedDatabaseName 应为 null', () {
        expect(provider.selectedDatabaseName, isNull);
      });

      test('expandedConnectionId 应为 null', () {
        expect(provider.expandedConnectionId, isNull);
      });

      test('favoriteTables 应为空', () {
        expect(provider.favoriteTables, isEmpty);
      });
    });

    group('selectConnection', () {
      test('应更新 selectedConnectionId', () {
        provider.selectConnection('conn_1');
        expect(provider.selectedConnectionId, 'conn_1');
      });

      test('应同时更新 expandedConnectionId', () {
        provider.selectConnection('conn_1');
        expect(provider.expandedConnectionId, 'conn_1');
      });

      test('重复选择同一连接不应触发 notifyListeners', () {
        provider.selectConnection('conn_1');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.selectConnection('conn_1');
        expect(notified, isFalse);
      });

      test('选择不同连接应触发 notifyListeners', () {
        provider.selectConnection('conn_1');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.selectConnection('conn_2');
        expect(notified, isTrue);
      });

      test('应支持设为 null', () {
        provider.selectConnection('conn_1');
        provider.selectConnection(null);
        expect(provider.selectedConnectionId, isNull);
      });

      test('切换连接应清空已选数据库（Fix-J 归属不变式：库选择隶属于连接）', () {
        provider.selectConnection('conn_1');
        provider.selectDatabase('mydb');

        provider.selectConnection('conn_2');

        expect(
          provider.selectedDatabaseName,
          isNull,
          reason: 'mydb 归属 conn_1，换连接后残留即张冠李戴',
        );
      });

      test('重复选择同一连接保留已选数据库', () {
        provider.selectConnection('conn_1');
        provider.selectDatabase('mydb');

        provider.selectConnection('conn_1');

        expect(provider.selectedDatabaseName, 'mydb');
      });

      test('配对序列兼容：selectConnection 换连接后 selectDatabase 正常落新值'
          '（树库节点 / 收藏 / 最近调用序）', () {
        provider.selectConnection('conn_1');
        provider.selectDatabase('db_a');

        provider.selectConnection('conn_2');
        provider.selectDatabase('db_b');

        expect(provider.selectedConnectionId, 'conn_2');
        expect(provider.selectedDatabaseName, 'db_b');
      });
    });

    group('selectDatabase', () {
      test('应更新 selectedDatabaseName', () {
        provider.selectDatabase('mydb');
        expect(provider.selectedDatabaseName, 'mydb');
      });

      test('重复选择同一数据库不应触发 notifyListeners', () {
        provider.selectDatabase('mydb');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.selectDatabase('mydb');
        expect(notified, isFalse);
      });

      test('应支持设为 null', () {
        provider.selectDatabase('mydb');
        provider.selectDatabase(null);
        expect(provider.selectedDatabaseName, isNull);
      });
    });

    group('expandConnection', () {
      test('应更新 expandedConnectionId', () {
        provider.expandConnection('conn_1');
        expect(provider.expandedConnectionId, 'conn_1');
      });

      test('重复展开同一连接不应触发 notifyListeners', () {
        provider.expandConnection('conn_1');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.expandConnection('conn_1');
        expect(notified, isFalse);
      });
    });

    group('toggleFavoriteTable', () {
      test('应添加收藏', () {
        provider.toggleFavoriteTable('conn_1.mydb.users');
        expect(provider.isFavoriteTable('conn_1.mydb.users'), isTrue);
      });

      test('再次切换应取消收藏', () {
        provider.toggleFavoriteTable('conn_1.mydb.users');
        provider.toggleFavoriteTable('conn_1.mydb.users');
        expect(provider.isFavoriteTable('conn_1.mydb.users'), isFalse);
      });

      test('应触发 notifyListeners', () {
        var notified = false;
        provider.addListener(() => notified = true);
        provider.toggleFavoriteTable('conn_1.mydb.users');
        expect(notified, isTrue);
      });

      test('多个收藏应独立管理', () {
        provider.toggleFavoriteTable('table_a');
        provider.toggleFavoriteTable('table_b');
        expect(provider.isFavoriteTable('table_a'), isTrue);
        expect(provider.isFavoriteTable('table_b'), isTrue);
        expect(provider.favoriteTables.length, 2);
      });
    });

    group('clearSelection', () {
      test('应重置所有选择状态', () {
        provider.selectConnection('conn_1');
        provider.selectDatabase('mydb');
        provider.expandConnection('conn_2');

        provider.clearSelection();

        expect(provider.selectedConnectionId, isNull);
        expect(provider.selectedDatabaseName, isNull);
        expect(provider.expandedConnectionId, isNull);
      });

      test('不应清除收藏', () {
        provider.toggleFavoriteTable('table_a');
        provider.clearSelection();
        expect(provider.isFavoriteTable('table_a'), isTrue);
      });

      test('应触发 notifyListeners', () {
        provider.selectConnection('conn_1');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.clearSelection();
        expect(notified, isTrue);
      });
    });

    group('favoriteTables 不可变性', () {
      test('返回的集合不应可被外部修改', () {
        provider.toggleFavoriteTable('table_a');
        final favorites = provider.favoriteTables;
        // 尝试修改返回的集合不应影响内部状态
        // 但由于是 unmodifiable，尝试添加会抛出异常
        expect(() => favorites.add('table_b'), throwsUnsupportedError);
      });
    });

    group('sidebarExpandRequest 一次性展开请求通道（2b.1 R3）', () {
      test('初始状态应为 null', () {
        expect(provider.sidebarExpandRequest, isNull);
      });

      test('requestSidebarExpand 应设值并 notify', () {
        var notified = false;
        provider.addListener(() => notified = true);
        provider.requestSidebarExpand('conn_1:performance');
        expect(provider.sidebarExpandRequest, 'conn_1:performance');
        expect(notified, isTrue);
      });

      test('重复请求应覆盖旧值并 notify', () {
        provider.requestSidebarExpand('conn_1:performance');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.requestSidebarExpand('conn_2:performance');
        expect(provider.sidebarExpandRequest, 'conn_2:performance');
        expect(notified, isTrue);
      });

      test('consumeSidebarExpandRequest 应清除并 notify', () {
        provider.requestSidebarExpand('conn_1:performance');
        var notified = false;
        provider.addListener(() => notified = true);
        provider.consumeSidebarExpandRequest();
        expect(provider.sidebarExpandRequest, isNull);
        expect(notified, isTrue);
      });

      test('无请求时 consume 零副作用不通知', () {
        var notified = false;
        provider.addListener(() => notified = true);
        provider.consumeSidebarExpandRequest();
        expect(provider.sidebarExpandRequest, isNull);
        expect(notified, isFalse);
      });

      test('请求→消费往返后通道复位可复用（一次性信号不持久化）', () {
        provider.requestSidebarExpand('conn_1:performance');
        provider.consumeSidebarExpandRequest();
        provider.requestSidebarExpand('conn_2:performance');
        expect(provider.sidebarExpandRequest, 'conn_2:performance');
        provider.consumeSidebarExpandRequest();
        expect(provider.sidebarExpandRequest, isNull);
      });
    });

    group('resolveRestorableDatabase 纯判定（T1 侧栏库选择持久化）', () {
      test('persisted 命中 availableDatabases → 返回原值', () {
        expect(
          SidebarProvider.resolveRestorableDatabase(
            persisted: 'testdata',
            availableDatabases: ['testdata', 'other'],
          ),
          'testdata',
        );
      });

      test('persisted 为 null → null', () {
        expect(
          SidebarProvider.resolveRestorableDatabase(
            persisted: null,
            availableDatabases: ['testdata'],
          ),
          isNull,
        );
      });

      test('persisted 为空串（损坏）→ null', () {
        expect(
          SidebarProvider.resolveRestorableDatabase(
            persisted: '',
            availableDatabases: ['testdata'],
          ),
          isNull,
        );
      });

      test('库已不在列表（已删）→ null', () {
        expect(
          SidebarProvider.resolveRestorableDatabase(
            persisted: 'dropped_db',
            availableDatabases: ['other'],
          ),
          isNull,
        );
      });

      test('availableDatabases 为空（SQLite 无库列表语义）→ null 无副作用', () {
        expect(
          SidebarProvider.resolveRestorableDatabase(
            persisted: 'testdata',
            availableDatabases: <String>[],
          ),
          isNull,
        );
      });
    });

    group('最后选库持久化（按连接，T1）', () {
      Future<void> flushPrefsWrites() async {
        // 写路径为 fire-and-forget（getInstance + setString 均为 mock 内存
        // 存储，微任务级完成）；两拍零延时确保落盘完成。
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      }

      test('选库后写 prefs：selectConnection + selectDatabase → 键落盘（AC1）', () async {
        provider.selectConnection('c1');
        provider.selectDatabase('testdata');
        await flushPrefsWrites();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('sidebar_last_db_c1'), 'testdata');
      });

      test('未选连接时 selectDatabase 不写键（键属于连接）', () async {
        provider.selectDatabase('testdata');
        await flushPrefsWrites();

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys().where((k) => k.startsWith('sidebar_last_db_')),
          isEmpty,
        );
      });

      test('显式取消选库（selectDatabase(null)）清除当前连接的键', () async {
        provider.selectConnection('c1');
        provider.selectDatabase('testdata');
        await flushPrefsWrites();

        provider.selectDatabase(null);
        await flushPrefsWrites();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('sidebar_last_db_c1'), isNull);
      });

      test('getPersistedLastDatabase 读回预置值', () async {
        SharedPreferences.setMockInitialValues({'sidebar_last_db_c1': 'db_a'});
        expect(await provider.getPersistedLastDatabase('c1'), 'db_a');
      });

      test('getPersistedLastDatabase 缺键 → null', () async {
        expect(await provider.getPersistedLastDatabase('c1'), isNull);
      });

      test('getPersistedLastDatabase 值损坏（非字符串）→ null 静默不抛（AC6）', () async {
        SharedPreferences.setMockInitialValues({'sidebar_last_db_c1': 12345});
        expect(await provider.getPersistedLastDatabase('c1'), isNull);
      });

      test('clearPersistedLastDatabase 移除对应键', () async {
        SharedPreferences.setMockInitialValues({'sidebar_last_db_c1': 'db_a'});
        await provider.clearPersistedLastDatabase('c1');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('sidebar_last_db_c1'), isNull);
      });
    });

    group('持久化键归属连接（Fix-J 回归，T1 AC7）', () {
      Future<void> flushPrefsWrites() async {
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
      }

      test('selectConnection 换连接后：内存库选择清空，A 的持久化键仍在', () async {
        provider.selectConnection('conn_a');
        provider.selectDatabase('testdata');
        await flushPrefsWrites();

        // Fix-J 内存语义（既有）+ 键保留（新）。
        provider.selectConnection('conn_b');
        expect(provider.selectedDatabaseName, isNull);

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('sidebar_last_db_conn_a'),
          'testdata',
          reason: '键归属连接 conn_a，切换连接不清键',
        );
        expect(prefs.getString('sidebar_last_db_conn_b'), isNull);
      });

      test('clearSelection 不清持久化键（键属连接不属会话内选择）', () async {
        provider.selectConnection('conn_a');
        provider.selectDatabase('testdata');
        await flushPrefsWrites();

        provider.clearSelection();
        expect(provider.selectedDatabaseName, isNull);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('sidebar_last_db_conn_a'), 'testdata');
      });
    });
  });
}
