//! T1 侧栏库选择持久化 · 恢复链测试（AC2-AC5 / AC8 + 控制器触发点）。
//!
//! E2E 实锤缺陷：侧栏选中库重启后静默丢失，AI 工作台 agent run 上下文
//! 快照无库（database=null 裸跑失败）。恢复链复用显式选库链
//! （_selectDatabase 去 switchToConnection 变体），使芯片/工具栏/执行层
//! 天然统一。
//!
//! headless AppProvider（不 pump DbmasterApp，Pigeon 挂起陷阱）+ 测试钩子
//! 注入连接态（先例 app_provider_switch_tab_sync_test.dart）；数据库服务
//! 走 FakeAdapter（本文件只验证恢复编排与状态落定，不验真库 SQL）；secure
//! storage 走 method-channel mock（deleteConnection 路径，先例
//! connection_provider_ai_memory_cleanup_test.dart）。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbServer;
import 'package:dbmaster/organisms/sidebar/sidebar_controller.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/services/database_abstract.dart' show DatabaseAdapter;
import 'package:dbmaster/services/database_service.dart';

/// changeDatabase→getDatabaseInfo 链路触达的成员全覆盖
/// （isConnected/getDatabases/useDatabase/getTables），其余成员不会被
/// 恢复编排触达，noSuchMethod 兜底。
class _FakeAdapter implements DatabaseAdapter {
  final List<String> dbs;
  _FakeAdapter(this.dbs);

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getDatabases() async => dbs;

  @override
  Future<void> useDatabase(String dbName) async {}

  @override
  Future<List<String>> getTables() async => <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DbServer _server(String id, String name, DatabaseType type) => DbServer(
  id: id,
  type: type,
  name: name,
  host: '192.0.2.128',
  port: 3306,
  username: 'root',
);

void _connectForTest(AppProvider provider, DbServer server, List<String> dbs) {
  provider.connection.dbService.registerConnectedServerForTest(server);
  provider.connection.dbService.registerConnectedAdapterForTest(
    server.id,
    _FakeAdapter(dbs),
  );
  provider.connection.setConnectionDatabasesForTest(server.id, dbs, dbs);
}

QueryTab _unboundTab(String connectionId) => QueryTab(
  id: 't1',
  title: 'query',
  sql: 'SELECT 1',
  connectionId: connectionId,
);

/// fire-and-forget 恢复链（控制器触发点）与 unawaited prefs 写全部落定。
Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          switch (call.method) {
            case 'readAll':
              return <String, String>{};
            default:
              return null; // read/write/delete/deleteAll 静默成功
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  group('restoreSidebarDatabaseSelection facade（恢复编排）', () {
    test('AC2 恢复-正常路径：侧栏选中 + 连接级当前库（changeDatabase 真调用）'
        '+ 工具栏跟随', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_c1': 'testdata',
      });
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      _connectForTest(provider, c1, ['testdata', 'other_db']);
      // 模拟重启后：连接已建立（currentServer=c1），侧栏无任何选择。
      provider.connection.setCurrentServerForTest(c1);
      provider.tab.addTab(_unboundTab('c1'));

      await provider.restoreSidebarDatabaseSelection('c1');

      expect(provider.sidebar.selectedConnectionId, 'c1');
      expect(provider.sidebar.selectedDatabaseName, 'testdata');
      expect(
        provider.connection.getConnectionCurrentDatabase('c1')?.name,
        'testdata',
        reason: '连接级当前库经 changeDatabase 真调用落定（agent run 上下文源）',
      );
      expect(
        provider.activeTab?.databaseName,
        'testdata',
        reason: '未绑定活跃 tab 的库芯片跟随（followActiveTabDatabase 效应）',
      );
      // 恢复经 selectDatabase 重写同值键（幂等），键仍在。
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sidebar_last_db_c1'), 'testdata');
    });

    test('AC2 幂等：已选中同库时重放直接返回，状态不变', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_c1': 'testdata',
      });
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      _connectForTest(provider, c1, ['testdata']);
      provider.connection.setCurrentServerForTest(c1);

      await provider.restoreSidebarDatabaseSelection('c1');
      expect(provider.sidebar.selectedDatabaseName, 'testdata');

      await provider.restoreSidebarDatabaseSelection('c1');
      expect(provider.sidebar.selectedDatabaseName, 'testdata');
      expect(provider.sidebar.selectedConnectionId, 'c1');
    });

    test('AC3 恢复-库已删：getDatabases 不含持久化库 → 不恢复且键被删除', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_c1': 'dropped_db',
      });
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      _connectForTest(provider, c1, ['other_db']);
      provider.connection.setCurrentServerForTest(c1);

      await provider.restoreSidebarDatabaseSelection('c1');

      expect(provider.sidebar.selectedDatabaseName, isNull);
      expect(
        provider.sidebar.selectedConnectionId,
        isNull,
        reason: '校验失败零副作用：不落侧栏连接选择',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sidebar_last_db_c1'), isNull);
    });

    test('AC4 恢复-连接已删：savedConnections 无此 id → 不恢复且键被删除', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_gone': 'testdata',
      });
      final provider = AppProvider();

      await provider.restoreSidebarDatabaseSelection('gone');

      expect(provider.sidebar.selectedDatabaseName, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sidebar_last_db_gone'), isNull);
    });

    test('AC5 恢复-未连接：跳过恢复，不自动发起连接，键保留', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_c1': 'testdata',
      });
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      // 不注册 connected adapter —— 未连接态。
      provider.connection.setCurrentServerForTest(c1);

      await provider.restoreSidebarDatabaseSelection('c1');

      expect(provider.sidebar.selectedDatabaseName, isNull);
      expect(
        provider.isConnectionConnected('c1'),
        isFalse,
        reason: '启动路径零隐式网络动作：绝不自动发起连接',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('sidebar_last_db_c1'),
        'testdata',
        reason: '键保留，用户重连后库列表装载再试',
      );
    });

    test('AC6 恢复-prefs 损坏：非字符串值静默忽略不抛', () async {
      SharedPreferences.setMockInitialValues({'sidebar_last_db_c1': 12345});
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      _connectForTest(provider, c1, ['testdata']);
      provider.connection.setCurrentServerForTest(c1);

      await provider.restoreSidebarDatabaseSelection('c1');

      expect(provider.sidebar.selectedDatabaseName, isNull);
    });

    test('AC6 恢复-空串键：静默忽略不抛', () async {
      SharedPreferences.setMockInitialValues({'sidebar_last_db_c1': ''});
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      _connectForTest(provider, c1, ['testdata']);
      provider.connection.setCurrentServerForTest(c1);

      await provider.restoreSidebarDatabaseSelection('c1');

      expect(provider.sidebar.selectedDatabaseName, isNull);
    });

    test('边界③ 恢复只针对侧栏当前连接：非当前连接不恢复也不清键', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_c2': 'testdata',
      });
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      final c2 = _server('c2', 'PostgreSQL', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(c1);
      provider.connection.addSavedServerForTest(c2);
      _connectForTest(provider, c1, ['testdata']);
      _connectForTest(provider, c2, ['testdata']);
      // 侧栏当前连接是 c1；对 c2 发起恢复 → 非「已是侧栏当前的连接」。
      provider.connection.setCurrentServerForTest(c1);

      await provider.restoreSidebarDatabaseSelection('c2');

      expect(provider.sidebar.selectedDatabaseName, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('sidebar_last_db_c2'),
        'testdata',
        reason: '非当前连接跳过恢复，键保留（与未连接同语义）',
      );
    });
  });

  group('AC8 删除连接清键', () {
    test('AppProvider.deleteConnection 路径后对应持久化键被清除', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_c1': 'testdata',
      });
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      _connectForTest(provider, c1, ['testdata']);

      await provider.deleteConnection('c1');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sidebar_last_db_c1'), isNull);
    });
  });

  group('SidebarController 恢复触发点（库列表装载完成后）', () {
    AppProvider buildConnectedProvider(String persistedDb) {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_c1': persistedDb,
      });
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      _connectForTest(provider, c1, ['testdata', 'other_db']);
      provider.connection.setCurrentServerForTest(c1);
      return provider;
    }

    test('挂载路径：loadExpandedState 时已连接当前连接无选库 → 恢复', () async {
      final provider = buildConnectedProvider('testdata');
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);

      await controller.loadExpandedState();
      await _settle();

      expect(provider.sidebar.selectedDatabaseName, 'testdata');
      expect(
        provider.connection.getConnectionCurrentDatabase('c1')?.name,
        'testdata',
      );
    });

    test('挂载路径：未连接时零副作用（键保留、无选择、无连接动作）', () async {
      SharedPreferences.setMockInitialValues({
        'sidebar_last_db_c1': 'testdata',
      });
      final provider = AppProvider();
      final c1 = _server('c1', 'MySQL 8.0', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(c1);
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);

      await controller.loadExpandedState();
      await _settle();

      expect(provider.sidebar.selectedDatabaseName, isNull);
      expect(provider.isConnectionConnected('c1'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sidebar_last_db_c1'), 'testdata');
    });

    test('展开路径：已连接连接节点展开（handleConnectionTap）→ '
        '库列表装载完成后恢复', () async {
      final provider = buildConnectedProvider('testdata');
      final controller = SidebarController(appProvider: provider);
      addTearDown(controller.dispose);

      // 已连接分支：toggleExpand → _onConnectionExpanded（刷新 + 恢复尝试）。
      await controller.handleConnectionTap(
        provider.connection.savedConnections.first,
      );
      await _settle();

      expect(provider.sidebar.selectedDatabaseName, 'testdata');
      expect(provider.sidebar.selectedConnectionId, 'c1');
      expect(
        provider.connection.getConnectionCurrentDatabase('c1')?.name,
        'testdata',
      );
    });
  });
}
