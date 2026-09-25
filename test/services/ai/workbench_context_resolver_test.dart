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
