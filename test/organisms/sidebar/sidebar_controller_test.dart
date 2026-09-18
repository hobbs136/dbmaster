// SidebarWidget 拆分（plan §3.4）— SidebarController 单元测试。
//
// 覆盖拆分前零覆盖的键盘导航/展开状态逻辑（验收标准：
// 「SidebarController 覆盖 widget 测试或单元测试」）。
// 直接构造 KeyDownEvent 调 handleTreeKeyEvent，不依赖焦点系统；
// AppProvider 用真实构造 + 测试 helper（沿用 sidebar_widget_test 模式）。
// 需要连接态的用例经 registerConnectedAdapterForTest 注入已连接 adapter
// （registerConnectedServerForTest 只标记 servers，不影响 hasConnection）。
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey, PhysicalKeyboardKey;
import 'package:flutter/widgets.dart' show FocusNode, KeyEventResult;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/connection_event.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_controller.dart';
import 'package:dbmaster/organisms/sidebar/sidebar_visible_nodes.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/sqlite_adapter.dart';

DbServer _testServer({
  String id = 'alpha-conn',
  String name = 'Test PostgreSQL',
  DatabaseType type = DatabaseType.postgresql,
}) {
  return DbServer(
    id: id,
    type: type,
    name: name,
    host: 'localhost',
    port: 5432,
    username: 'test',
    password: 'test',
  );
}

void _setupConnectedServer(
  AppProvider provider,
  DbServer server, {
  List<String> databases = const ['testdb'],
}) {
  provider.connection.dbService.registerConnectedServerForTest(server);
  provider.connection.setConnectionDatabasesForTest(
    server.id,
    databases,
    databases,
  );
  // C22-1 单实例树：key 集/树只含当前连接（harness 直注册绕过
  // connectToServer，故补侧栏选中锚定）。
  provider.sidebar.selectConnection(server.id);
}

void _cacheDatabase(AppProvider provider, DbServer server, String dbName) {
  provider.connection.setCachedDatabaseForTest(
    server.id,
    dbName,
    Database(name: dbName, tables: [], views: [], functions: []),
  );
}

KeyDownEvent _key(
  LogicalKeyboardKey logical,
  PhysicalKeyboardKey physical,
) {
  return KeyDownEvent(
    physicalKey: physical,
    logicalKey: logical,
    timeStamp: Duration.zero,
  );
}

/// 谎报已连接的最小 stub：让 hasConnection(cid) == true 而无需真实数据库。
class _AlwaysConnectedAdapter extends SQLiteAdapter {
  @override
  bool get isConnected => true;
}

void _registerConnected(AppProvider provider, DbServer server) {
  provider.connection.dbService.registerConnectedAdapterForTest(
    server.id,
    _AlwaysConnectedAdapter(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SidebarController 展开状态', () {
    testWidgets('toggleExpand/toggleDatabase/toggleTable 增删集合并通知', (
      tester,
    ) async {
      final provider = AppProvider();
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.toggleExpand('cat:alpha-conn:testdb:tables');
      expect(controller.expandedItems, contains('cat:alpha-conn:testdb:tables'));
      controller.toggleExpand('cat:alpha-conn:testdb:tables');
      expect(controller.expandedItems, isNot(contains('cat:alpha-conn:testdb:tables')));

      controller.toggleDatabase('alpha-conn:testdb');
      expect(controller.expandedDatabases, contains('alpha-conn:testdb'));
      controller.toggleDatabase('alpha-conn:testdb');
      expect(controller.expandedDatabases, isEmpty);

      controller.toggleTable('alpha-conn:testdb:users');
      expect(controller.expandedTables, contains('alpha-conn:testdb:users'));
      controller.toggleTable('alpha-conn:testdb:users');
      expect(controller.expandedTables, isEmpty);

      // 每次 toggle 至少触发一次通知（toggle 内部还有 save 异步跟随）
      expect(notifications, greaterThanOrEqualTo(6));
    });

    testWidgets('collapseAll 清空三集合', (tester) async {
      final provider = AppProvider();
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);

      controller
        ..toggleExpand('cat:x:y')
        ..toggleDatabase('alpha-conn:testdb')
        ..toggleTable('alpha-conn:testdb:users');
      controller.collapseAll();

      expect(controller.expandedItems, isEmpty);
      expect(controller.expandedDatabases, isEmpty);
      expect(controller.expandedTables, isEmpty);
    });

    testWidgets('removeExpandedDatabase 移除指定 key', (tester) async {
      final provider = AppProvider();
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);

      controller.toggleDatabase('alpha-conn:testdb');
      controller.removeExpandedDatabase('alpha-conn', 'testdb');
      expect(controller.expandedDatabases, isEmpty);
    });

    testWidgets('pruneOrphanedExpandedDatabases 清理已删数据库的孤儿 key', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);

      // cid:dbName 格式（树点击路径）
      controller.toggleDatabase('alpha-conn:testdb');
      controller.toggleDatabase('alpha-conn:gone-db');

      // gone-db 已不在连接数据库列表中 → 被 prune；testdb 保留
      provider.connection.setConnectionDatabasesForTest(
        server.id,
        ['testdb'],
        ['testdb'],
      );
      controller.pruneOrphanedExpandedDatabases(provider);
      await tester.pump();

      expect(controller.expandedDatabases, contains('alpha-conn:testdb'));
      expect(controller.expandedDatabases, isNot(contains('alpha-conn:gone-db')));
    });

    testWidgets('持久化 round-trip + 裸连接 ID 过滤（T008）', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);

      final controllerA = SidebarController(appProvider: provider);
      controllerA
        ..toggleExpand('plain-uuid-connection') // 裸 UUID：load 时应被过滤
        ..toggleExpand('cat:alpha-conn:testdb:tables')
        ..toggleDatabase('alpha-conn:testdb')
        ..toggleTable('alpha-conn:testdb:users');
      await tester.pump(); // 让 async save 落盘
      controllerA.dispose();

      final controllerB = SidebarController(appProvider: provider);
      addTearDown(controllerB.dispose);
      await controllerB.loadExpandedState();
      await tester.pump();

      // 恢复非连接项（分类/数据库/表）
      expect(
        controllerB.expandedItems,
        contains('cat:alpha-conn:testdb:tables'),
      );
      expect(controllerB.expandedDatabases, contains('alpha-conn:testdb'));
      expect(controllerB.expandedTables, contains('alpha-conn:testdb:users'));
      // 连接 ID 被过滤，避免启动时自动展开连接
      expect(
        controllerB.expandedItems,
        isNot(contains('plain-uuid-connection')),
      );
    });

    testWidgets('ConnectionEstablished 清子展开态并自动展开连接（FR-007/US1）', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _registerConnected(provider, server);

      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      controller.subscribeToConnectionEvents();

      // 预置 stale 子展开态
      controller.toggleDatabase('alpha-conn:testdb');
      controller.toggleTable('alpha-conn:testdb:users');

      provider.connection.dbService.addEventForTest(
        ConnectionEstablished(server.id, server),
      );
      await tester.pump();
      await tester.pump();

      // US1: 连接节点自动展开；FR-007: 子展开态被清
      expect(controller.expandedItems, contains(server.id));
      expect(controller.expandedDatabases, isEmpty);
      expect(controller.expandedTables, isEmpty);
    });

    testWidgets('未连接的 ConnectionEstablished 事件被跳过', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      // 不 registerConnectedServerForTest → isConnectionConnected == false

      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      controller.subscribeToConnectionEvents();

      provider.connection.dbService.addEventForTest(
        ConnectionEstablished(server.id, server),
      );
      await tester.pump();
      await tester.pump();

      expect(controller.expandedItems, isNot(contains(server.id)));
    });
  });

  group('SidebarController 键盘导航', () {
    // C22-1：单实例树——beta 仍在 savedConnections 但非当前连接，
    // key 集/导航只覆盖 alpha（跨连接切换走顶部选择器，非键盘）。
    AppProvider buildProvider() {
      final provider = AppProvider();
      final alpha = _testServer(id: 'alpha-conn');
      final beta = _testServer(id: 'beta-conn');
      provider.connection.addSavedServerForTest(alpha);
      provider.connection.addSavedServerForTest(beta);
      _setupConnectedServer(provider, alpha);
      _setupConnectedServer(provider, beta);
      // 展开态 key 构建要求 isConnectionConnected（registerConnectedServer
      // 只标记 servers）——补谎报 adapter（本文件既有 helper）
      _registerConnected(provider, alpha);
      provider.connection.setCachedDatabaseForTest(
        'alpha-conn',
        'testdb',
        Database(name: 'testdb', tables: [], views: [], functions: []),
      );
      provider.sidebar.selectConnection('alpha-conn');
      return provider;
    }

    testWidgets('↓ 从 null 选中首节点、连续前进、末尾 wrap 回首（单实例树）', (tester) async {
      final provider = buildProvider();
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      controller.toggleExpand('alpha-conn');
      controller.rebuildVisibleNodeKeys(provider);

      // 展开后：连接根 → 保存查询分类 → 库节点（beta 非当前，不入 key 集）
      final keys = controller.visibleNodeKeys;
      expect(
        keys,
        ['conn:alpha-conn', 'cat:alpha-conn:saved_queries', 'db:alpha-conn:testdb'],
      );

      expect(
        controller.handleTreeKeyEvent(
          FocusNode(),
          _key(LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown),
        ),
        KeyEventResult.handled,
      );
      expect(controller.selectedNodeKey, 'conn:alpha-conn');

      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown),
      );
      expect(controller.selectedNodeKey, 'cat:alpha-conn:saved_queries');

      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown),
      );
      expect(controller.selectedNodeKey, 'db:alpha-conn:testdb');

      // 末尾再 ↓ → wrap 回首节点
      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown),
      );
      expect(controller.selectedNodeKey, 'conn:alpha-conn');
    });

    testWidgets('↑ 从首节点 wrap 到末尾（单实例树）', (tester) async {
      final provider = buildProvider();
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      controller.toggleExpand('alpha-conn');
      controller.rebuildVisibleNodeKeys(provider);

      // 选中首节点 → ↑ wrap 到末尾（库节点）
      controller.selectNode('conn:alpha-conn');
      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp),
      );
      expect(controller.selectedNodeKey, 'db:alpha-conn:testdb');
    });

    testWidgets('→ 展开已缓存的 db: 节点；← 收起（C19 统一 key 格式契约）', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      provider.connection.setCachedDatabaseForTest(
        server.id,
        'testdb',
        Database(name: 'testdb', tables: [], views: [], functions: []),
      );

      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      // db: 键盘分支只看 key 前缀，直接选中目标 key
      controller.selectNode('db:alpha-conn:testdb');

      final result = controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
      );
      expect(result, KeyEventResult.handled);
      await tester.pump();

      // 展开集合存「cid:db」裸格式（树渲染/prune 的消费契约）——C19 修复
      // 双格式 bug：此前键盘路径误存「db:cid:db」完整可见 key。
      expect(controller.expandedDatabases, contains('alpha-conn:testdb'));
      expect(
        controller.expandedDatabases,
        isNot(contains('db:alpha-conn:testdb')),
      );

      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft),
      );
      expect(
        controller.expandedDatabases,
        isNot(contains('alpha-conn:testdb')),
      );
    });

    testWidgets('→ 在离线 conn: 节点且用户取消密码弹窗时不展开', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      // 不连接 → isConnectionConnected == false

      final controller = SidebarController(
        appProvider: provider,
        // 模拟用户在密码弹窗点取消
        promptPassword: (server) async => null,
      );
      addTearDown(controller.dispose);
      controller
        ..rebuildVisibleNodeKeys(provider)
        ..selectNode('conn:alpha-conn');

      final result = controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
      );
      expect(result, KeyEventResult.handled);
      await tester.pump();
      await tester.pump();

      expect(controller.expandedItems, isNot(contains('alpha-conn')));
    });

    // T29 走查修复：连接在途时点连接节点不得重入弹密码框（重入弹窗 +
    // 不可中止长链路 = 「取消后卡死」的入口）。
    testWidgets('连接在途时 handleConnectionTap 不弹密码框不重复连接', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      // 标记在途连接（isConnectionConnecting → true）
      provider.connection.dbService.markConnectingForTest(server.id);

      var promptCount = 0;
      final controller = SidebarController(
        appProvider: provider,
        promptPassword: (server) async {
          promptCount++;
          return server;
        },
      );
      addTearDown(controller.dispose);

      await controller.handleConnectionTap(server);
      expect(promptCount, 0, reason: '在途连接不应再弹密码框');
      expect(provider.isConnectionConnected(server.id), isFalse);
    });

    testWidgets('→/← 展开/收起 cat: 分类节点', (tester) async {
      final provider = buildProvider();
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      controller
        ..toggleExpand('alpha-conn')
        ..rebuildVisibleNodeKeys(provider)
        ..selectNode('cat:alpha-conn:saved_queries');

      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
      );
      // 展开集合存裸 key（剥「cat:」前缀，C19 统一 key 契约——
      // SavedQueriesSection 按裸 key 查询展开态）
      expect(
        controller.expandedItems,
        contains('alpha-conn:saved_queries'),
      );

      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft),
      );
      expect(
        controller.expandedItems,
        isNot(contains('alpha-conn:saved_queries')),
      );
    });

    testWidgets('Esc 清空选中；无选中时 Esc 不拦截', (tester) async {
      final provider = buildProvider();
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      controller
        ..rebuildVisibleNodeKeys(provider)
        ..selectNode('conn:alpha-conn');

      expect(
        controller.handleTreeKeyEvent(
          FocusNode(),
          _key(LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
        ),
        KeyEventResult.handled,
      );
      expect(controller.selectedNodeKey, isNull);

      // 无选中再按 Esc → ignored
      expect(
        controller.handleTreeKeyEvent(
          FocusNode(),
          _key(LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
        ),
        KeyEventResult.ignored,
      );
    });

    testWidgets('type-to-select 跳到首字母匹配节点（wrap-around，单实例树）', (tester) async {
      final provider = buildProvider();
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);
      controller.toggleExpand('alpha-conn');
      controller.rebuildVisibleNodeKeys(provider);

      // 's' → saved_queries 分类
      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS),
      );
      expect(controller.selectedNodeKey, 'cat:alpha-conn:saved_queries');

      // 连续 't'：buffer 'st' 无匹配 → 退化为单字符 't' **重试**——
      // 从当前（cat）之后环找命中库节点 testdb（C19 修复：原实现只
      // 重置 buffer 不重搜）
      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.keyT, PhysicalKeyboardKey.keyT),
      );
      expect(controller.selectedNodeKey, 'db:alpha-conn:testdb');

      // 再按 'e'：buffer 'te' 仍为 testdb 前缀 → 保持
      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.keyE, PhysicalKeyboardKey.keyE),
      );
      expect(controller.selectedNodeKey, 'db:alpha-conn:testdb');
    });

    testWidgets('type-to-select 600ms 超时重置 buffer（单实例树）', (tester) async {
      final provider = buildProvider();
      var currentTime = DateTime(2026, 1, 1, 12);
      final controller = SidebarController(
        appProvider: provider,
        now: () => currentTime,
      );
      addTearDown(controller.dispose);
      controller.toggleExpand('alpha-conn');
      controller.rebuildVisibleNodeKeys(provider);

      // 's' → saved_queries 分类
      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.keyS, PhysicalKeyboardKey.keyS),
      );
      expect(controller.selectedNodeKey, 'cat:alpha-conn:saved_queries');

      // 700ms 后输入 't'：buffer 应重置为 't'（而非 'st'）→ 从当前
      // （cat）之后环找命中库节点 testdb
      currentTime = currentTime.add(const Duration(milliseconds: 700));
      controller.handleTreeKeyEvent(
        FocusNode(),
        _key(LogicalKeyboardKey.keyT, PhysicalKeyboardKey.keyT),
      );
      expect(controller.selectedNodeKey, 'db:alpha-conn:testdb');
    });
  });

  group('buildVisibleSidebarNodeKeys / sidebarNodeDisplayName', () {
    testWidgets('未展开连接：仅 conn key', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      final keys = buildVisibleSidebarNodeKeys(
        provider: provider,
        expandedItems: {},
        expandedDatabases: {},
        expandedTables: {},
        loadedTableSchemas: {},
        loadedTableForeignKeys: {},
        searchQuery: '',
      );
      expect(keys, ['conn:alpha-conn']);
    });

    testWidgets('展开连接+数据库+分类：层级有序', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _registerConnected(provider, server);
      _setupConnectedServer(provider, server);
      provider.connection.setCachedDatabaseForTest(
        server.id,
        'testdb',
        Database(
          name: 'testdb',
          tables: [DbTable(name: 'users')],
          views: [],
          functions: [],
        ),
      );

      final keys = buildVisibleSidebarNodeKeys(
        provider: provider,
        expandedItems: {'alpha-conn', 'alpha-conn:testdb:tables'},
        // 展开集合存裸 key（cid:db）——C19 统一 key 契约（此前测试喂的
        // 「db:」前缀格式与树渲染/toggleDatabase 实际存的不一致）
        expandedDatabases: {'alpha-conn:testdb'},
        expandedTables: {},
        loadedTableSchemas: {},
        loadedTableForeignKeys: {},
        searchQuery: '',
      );
      expect(keys, [
        'conn:alpha-conn',
        'cat:alpha-conn:saved_queries',
        'db:alpha-conn:testdb',
        'cat:alpha-conn:testdb:tables',
        'table:alpha-conn:testdb:users',
      ]);
    });

    testWidgets('搜索过滤：连接名不匹配且无子命中时整连接隐藏', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _setupConnectedServer(provider, server);

      final keys = buildVisibleSidebarNodeKeys(
        provider: provider,
        expandedItems: {},
        expandedDatabases: {},
        expandedTables: {},
        loadedTableSchemas: {},
        loadedTableForeignKeys: {},
        searchQuery: 'nonexistent',
      );
      expect(keys, isEmpty);
    });

    testWidgets('sidebarNodeDisplayName 各前缀解析', (tester) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);

      expect(sidebarNodeDisplayName('conn:alpha-conn', provider), 'alpha-conn');
      expect(
        sidebarNodeDisplayName('db:alpha-conn:testdb', provider),
        'testdb',
      );
      expect(
        sidebarNodeDisplayName('schema:alpha-conn:testdb:public', provider),
        'public',
      );
      expect(
        sidebarNodeDisplayName('col:alpha-conn:testdb:users:id', provider),
        'id',
      );
      expect(
        sidebarNodeDisplayName('savedquery:alpha-conn:missing', provider),
        'missing', // 查不到的 saved query 回退为 id
      );
    });

    testWidgets('PG schema 函数叶子 key = func: 前缀（C19 与 Enter/选中态统一）', (
      tester,
    ) async {
      final provider = AppProvider();
      final server = _testServer();
      provider.connection.addSavedServerForTest(server);
      _registerConnected(provider, server);
      _setupConnectedServer(provider, server);
      provider.connection.setCachedDatabaseForTest(
        server.id,
        'testdb',
        Database(
          name: 'testdb',
          tables: [],
          views: [],
          functions: [],
          schemas: [
            DbSchema(
              name: 'public',
              functions: ['my_func'],
              tables: [],
              views: [],
            ),
          ],
        ),
      );

      final keys = buildVisibleSidebarNodeKeys(
        provider: provider,
        expandedItems: {
          'alpha-conn',
          'alpha-conn:testdb:schema:public',
          'alpha-conn:testdb:schema:public:functions',
        },
        // 裸 key 契约：鼠标 toggleDatabase 与键盘展开同格式后子节点可见
        expandedDatabases: {'alpha-conn:testdb'},
        expandedTables: {},
        loadedTableSchemas: {},
        loadedTableForeignKeys: {},
        searchQuery: '',
      );
      // 原为 'fn:'（仅本构建器使用）——Enter 处理器与树内选中态均按
      // 'func:' 前缀匹配，三处不一致导致键盘 Enter 失效。
      expect(keys, contains('func:alpha-conn:testdb:my_func'));
      expect(keys, isNot(contains('fn:alpha-conn:testdb:my_func')));
    });
  });
}
