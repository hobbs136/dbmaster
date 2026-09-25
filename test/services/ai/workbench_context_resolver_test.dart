import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/ai_conversation_session.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/models/workbench_context_lock.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/ai/workbench_context_resolver.dart';

import '../../helpers/fake_pro_module.dart';

DbServer _server({
  required String id,
  required String name,
  String? database,
}) => DbServer(
  id: id,
  name: name,
  type: DatabaseType.sqlite,
  host: 'localhost',
  port: 0,
  username: 'root',
  password: null,
  database: database,
);

AiConversationSession _sessionWithLock(String id, String connectionId) =>
    AiConversationSession(
      id: id,
      title: id,
      createdAt: DateTime(2026, 9, 22),
      updatedAt: DateTime(2026, 9, 22),
      messageIds: const [],
      metadata: {
        WorkbenchContextLock.metadataKey: WorkbenchContextLock(
          connectionId: connectionId,
          databaseName: 'locked_db',
          lockedAt: DateTime(2026, 9, 22),
        ).toJson(),
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveWorkbenchContext（AC3.3 继承序四态）', () {
    late AppProvider provider;
    late FakeProModule fakePro;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
              switch (call.method) {
                case 'read':
                case 'write':
                case 'delete':
                case 'deleteAll':
                  return null;
                case 'readAll':
                  return <String, String>{};
                default:
                  return null;
              }
            },
          );
      fakePro = FakeProModule(isPro: true);
      provider = AppProvider(proModule: fakePro);
    });

    tearDown(() {
      fakePro.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
    });

    test('态一：活动 tab 已绑定上下文 → activeTab 来源，取 tab 的连接与库', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_1', name: 'MySQL 主库'),
      );
      await provider.tab.openQueryTab(
        connectionId: 'conn_1',
        databaseName: 'db_from_tab',
      );

      final value = resolveWorkbenchContext(provider);

      expect(value.source, WorkbenchContextSource.activeTab);
      expect(value.connectionId, 'conn_1');
      expect(value.connectionName, 'MySQL 主库');
      expect(value.databaseName, 'db_from_tab');
      expect(value.isAvailable, isTrue);
    });

    test(
      '态二：活动 tab 存在但未绑定（isContextBound=false）→ 不走 tab 来源，经侧栏序兜底标为 sidebar',
      () async {
        await provider.connection.saveConnection(
          _server(id: 'conn_1', name: 'MySQL 主库'),
        );
        await provider.tab.openQueryTab(
          connectionId: 'conn_1',
          databaseName: 'db_from_tab',
          bindContext: false,
        );

        final value = resolveWorkbenchContext(provider);

        // 两序差异的可观察面：值仍可解析出同一连接（侧栏序第二优先级取
        // activeTab.connectionId），但来源标识为 sidebar 而非 activeTab。
        expect(value.source, WorkbenchContextSource.sidebar);
        expect(value.connectionId, 'conn_1');
        expect(value.connectionName, 'MySQL 主库');
        expect(
          value.databaseName,
          'db_from_tab',
          reason: 'server.database 为空时回退活动 tab 的库名',
        );
        expect(value.isAvailable, isTrue);
      },
    );

    test('态三：无 tab 上下文、侧栏选中连接 → sidebar 来源', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_2', name: '分析库', database: 'db_on_server'),
      );
      provider.sidebar.selectConnection('conn_2');

      final value = resolveWorkbenchContext(provider);

      expect(value.source, WorkbenchContextSource.sidebar);
      expect(value.connectionId, 'conn_2');
      expect(value.connectionName, '分析库');
      expect(
        value.databaseName,
        'db_on_server',
        reason: '侧栏来源优先 server.database',
      );
      expect(value.isAvailable, isTrue);
    });

    test('态四：无 tab、无侧栏选中 → none，其余字段为 null（AC3.6 未设置态）', () {
      final value = resolveWorkbenchContext(provider);

      expect(value.source, WorkbenchContextSource.none);
      expect(value.connectionId, isNull);
      expect(value.connectionName, isNull);
      expect(value.databaseName, isNull);
      expect(value.isAvailable, isFalse);
    });

    test('侧栏选中的 id 不在 savedConnections → 解析为 null → none', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_1', name: 'MySQL 主库'),
      );
      provider.sidebar.selectConnection('ghost_not_saved');

      expect(
        resolveWorkbenchContext(provider).source,
        WorkbenchContextSource.none,
      );
    });

    test(
      'connectionId 不在 savedConnections → connectionName 以 id 兜底（§7.3）',
      () async {
        await provider.tab.openQueryTab(
          connectionId: 'ghost_conn',
          databaseName: 'db',
        );

        final value = resolveWorkbenchContext(provider);

        expect(value.source, WorkbenchContextSource.activeTab);
        expect(
          value.connectionName,
          'ghost_conn',
          reason: '名字解析失败时显示 id，不显示 null',
        );
      },
    );

    // ── Fix-J：侧栏库级继承（selectedDatabaseName 归属校验）──────────────
    // 归属不变式：selectedDatabaseName 的所属连接 = selectedConnectionId
    // （树库节点 / 收藏 / 最近 / focus 定位均 selectConnection+selectDatabase
    // 连调；selectConnection 换连接即清库）。

    test('Fix-J 主场景：侧栏树点选库 → databaseName 命中点选库', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_3', name: '实例连接'),
      );
      // 树库节点 tap 序列（SidebarTree._selectDatabase 同款配对）。
      provider.sidebar.selectConnection('conn_3');
      provider.sidebar.selectDatabase('db_picked');

      final value = resolveWorkbenchContext(provider);

      expect(value.source, WorkbenchContextSource.sidebar);
      expect(value.connectionId, 'conn_3');
      expect(
        value.databaseName,
        'db_picked',
        reason: '用户显式点选的库应体现当前意图（修复前此处为 null 缺口）',
      );
    });

    test('Fix-J 优先序：点选库优先于连接配置默认库（显式意图 > 静态配置）', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_3', name: '实例连接', database: 'db_on_server'),
      );
      provider.sidebar.selectConnection('conn_3');
      provider.sidebar.selectDatabase('db_picked');

      final value = resolveWorkbenchContext(provider);

      expect(value.databaseName, 'db_picked');
    });

    test(
      'Fix-J 归属边界：点选 A 的库后切到 B（switchToConnection 不触侧栏选择态）'
      '→ db_a 不错挂 B，回退 B 配置默认库',
      () async {
        await provider.connection.saveConnection(
          _server(id: 'conn_a', name: '连接 A'),
        );
        final DbServer serverB = _server(
          id: 'conn_b',
          name: '连接 B',
          database: 'db_b_default',
        );
        await provider.connection.saveConnection(serverB);
        provider.sidebar.selectConnection('conn_a');
        provider.sidebar.selectDatabase('db_a');
        // 选择器 / switchToConnection 链路只写 currentServer，不清侧栏选择
        // （clearSelection 生产零调用）——test-only hook 模拟切换成功态，
        // 侧栏残留 selectedConnectionId=conn_a + selectedDatabaseName=db_a。
        provider.connection.setCurrentServerForTest(serverB);

        final value = resolveWorkbenchContext(provider);

        expect(value.source, WorkbenchContextSource.sidebar);
        expect(value.connectionId, 'conn_b');
        expect(
          value.databaseName,
          'db_b_default',
          reason: 'db_a 归属 conn_a（selectedConnectionId），不得错挂 conn_b',
        );
      },
    );

    test(
      'Fix-J 归属记录缺失：仅 selectDatabase 无配对 selectConnection '
      '（focus 定位窄面）→ 不消费，回退未绑定 tab 库兜底',
      () async {
        await provider.connection.saveConnection(
          _server(id: 'conn_1', name: 'MySQL 主库'),
        );
        await provider.tab.openQueryTab(
          connectionId: 'conn_1',
          databaseName: 'db_from_tab',
          bindContext: false,
        );
        // 无归属记录的孤儿库选择（selectedConnectionId 保持 null）。
        provider.sidebar.selectDatabase('db_orphan');

        final value = resolveWorkbenchContext(provider);

        expect(value.source, WorkbenchContextSource.sidebar);
        expect(value.connectionId, 'conn_1');
        expect(
          value.databaseName,
          'db_from_tab',
          reason: 'selectedConnectionId=null ≠ conn_1，孤儿库不得消费',
        );
      },
    );

    test('Fix-J：tab 绑定上下文优先不受侧栏点选影响', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_1', name: 'MySQL 主库'),
      );
      await provider.connection.saveConnection(
        _server(id: 'conn_9', name: '分析库'),
      );
      await provider.tab.openQueryTab(
        connectionId: 'conn_1',
        databaseName: 'db_from_tab',
      );
      provider.sidebar.selectConnection('conn_9');
      provider.sidebar.selectDatabase('db_picked');

      final value = resolveWorkbenchContext(provider);

      expect(value.source, WorkbenchContextSource.activeTab);
      expect(value.connectionId, 'conn_1');
      expect(value.databaseName, 'db_from_tab');
    });
  });

  group('effectiveWorkbenchContext（锁定快照优先）', () {
    late AppProvider provider;
    late FakeProModule fakePro;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null,
          );
      fakePro = FakeProModule(isPro: true);
      provider = AppProvider(proModule: fakePro);
    });

    tearDown(() {
      fakePro.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
    });

    test('会话带锁定 → 锁定快照优先于当前跟随态（AC3.4 锁定不跟随）', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_locked', name: '锁定目标库'),
      );
      await provider.connection.saveConnection(
        _server(id: 'conn_tab', name: '当前 tab 库'),
      );
      await provider.tab.openQueryTab(
        connectionId: 'conn_tab',
        databaseName: 'db_from_tab',
      );

      final value = effectiveWorkbenchContext(
        _sessionWithLock('s1', 'conn_locked'),
        provider,
      );

      expect(value.connectionId, 'conn_locked');
      expect(value.connectionName, '锁定目标库');
      expect(value.databaseName, 'locked_db');
      expect(value.isAvailable, isTrue);
    });

    test('Fix-J：锁定态优先不受侧栏点选库影响', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_locked', name: '锁定目标库'),
      );
      await provider.connection.saveConnection(
        _server(id: 'conn_9', name: '分析库'),
      );
      provider.sidebar.selectConnection('conn_9');
      provider.sidebar.selectDatabase('db_picked');

      final value = effectiveWorkbenchContext(
        _sessionWithLock('s1', 'conn_locked'),
        provider,
      );

      expect(value.connectionId, 'conn_locked');
      expect(value.databaseName, 'locked_db', reason: '锁定快照优先于跟随解析');
    });

    test('会话无锁定 → 等于跟随态解析', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_1', name: 'MySQL 主库'),
      );
      await provider.tab.openQueryTab(
        connectionId: 'conn_1',
        databaseName: 'db1',
      );
      final unbound = AiConversationSession(
        id: 's2',
        title: 's2',
        createdAt: DateTime(2026, 9, 22),
        updatedAt: DateTime(2026, 9, 22),
        messageIds: const [],
      );

      final value = effectiveWorkbenchContext(unbound, provider);
      final follow = resolveWorkbenchContext(provider);

      expect(value.connectionId, follow.connectionId);
      expect(value.databaseName, follow.databaseName);
      expect(value.source, WorkbenchContextSource.activeTab);
    });

    test('会话为 null → 等于跟随态解析', () async {
      await provider.connection.saveConnection(
        _server(id: 'conn_1', name: 'MySQL 主库'),
      );
      await provider.tab.openQueryTab(
        connectionId: 'conn_1',
        databaseName: 'db1',
      );

      final value = effectiveWorkbenchContext(null, provider);

      expect(value.source, WorkbenchContextSource.activeTab);
      expect(value.connectionId, 'conn_1');
    });
  });
}
