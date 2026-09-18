// 2026-08-27 回归：query 工具栏连接不跟随侧边栏切换。
//
// 根因（两层）：
// 1. 五月 workspace 实验（ad792732）把 AppProvider 的
//    updateTabConnection/Database/DatabaseType 抽成空 stub，实验退役后
//    stub 残留——编辑器工具栏连接/库下拉与 AI 面板上下文应用全部静默
//    失效（tab 私有上下文永不更新）。
// 2. 侧边栏/对话框等切换入口只调 switchToConnection（全局 active），
//    不与 tab 私有上下文同步——工具栏芯片与执行链（读 tab 字段）停在
//    原连接。
//
// 修复：三代理恢复真实委托 + switchToConnection 成功后同步活跃 tab
// （connectionId + databaseType + 默认第一个库）；树节点/快速搜索显式
// 选库随后覆写 databaseName。非活跃 tab 各自保持（per-tab 隔离）。
//
// 方向 A（2026-09-04）：侧边栏导航劫持活跃 tab 修复。上述「活跃 tab 跟随」
// 在多 tab 场景劫持了用户正在使用的 tab（侧边栏点实例 D/库 E 导航去双击
// 表 F，活跃的 query C 上下文被覆写成 D/E，切回 C 工具栏显示 D/E）。引入
// QueryTab.isContextBound：双击表/工具栏下拉/AI 应用等显式动作 → 绑定，
// 侧边栏导航（switchToConnection / followActiveTabDatabase）只跟随未绑定
// tab（「+」新建空白 tab——2026-08-27 的跟随语义保留）。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbServer;
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;
import 'package:dbmaster/services/database_abstract.dart' show DatabaseAdapter;

/// switchToConnection 判活只碰 isConnected + getDatabases——其余成员
/// noSuchMethod 兜底（不会被本测试路径触达）。
class _FakeAdapter implements DatabaseAdapter {
  final List<String> dbs;
  _FakeAdapter(this.dbs);

  @override
  bool get isConnected => true;

  @override
  Future<List<String>> getDatabases() async => dbs;

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
  provider.connection.dbService
      .registerConnectedAdapterForTest(server.id, _FakeAdapter(dbs));
  provider.connection.setConnectionDatabasesForTest(server.id, dbs, dbs);
}

QueryTab _tab(String connectionId, DatabaseType type, String db) => QueryTab(
      id: 't1',
      title: 'query',
      sql: 'SELECT 1',
      connectionId: connectionId,
      databaseName: db,
      databaseType: type,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('switchToConnection → 活跃 tab 上下文同步', () {
    test('成功切换：connectionId/type/默认库同步到活跃 tab', () async {
      final provider = AppProvider();
      final a = _server('conn-a', 'A', DatabaseType.mysql);
      final b = _server('conn-b', 'B', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a, ['db_a1', 'db_a2']);
      _connectForTest(provider, b, ['db_b1', 'db_b2']);
      provider.connection.setCurrentServerForTest(a);
      provider.tab.addTab(_tab('conn-a', DatabaseType.mysql, 'db_a1'));

      final ok = await provider.switchToConnection('conn-b');

      expect(ok, isTrue);
      expect(provider.connection.currentServer?.id, 'conn-b');
      // 工具栏芯片与执行链读的字段必须跟上（本修复核心断言）。
      expect(provider.activeTab?.connectionId, 'conn-b');
      expect(provider.activeTab?.databaseType, DatabaseType.postgresql);
      expect(provider.activeTab?.databaseName, 'db_b1',
          reason: '旧库不在新连接上，回落第一个库');
    });

    test('失败切换（未注册连接）：tab 保持原上下文', () async {
      final provider = AppProvider();
      final a = _server('conn-a', 'A', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(a);
      _connectForTest(provider, a, ['db_a1']);
      provider.connection.setCurrentServerForTest(a);
      provider.tab.addTab(_tab('conn-a', DatabaseType.mysql, 'db_a1'));

      final ok = await provider.switchToConnection('no-such-conn');

      expect(ok, isFalse);
      expect(provider.activeTab?.connectionId, 'conn-a');
      expect(provider.activeTab?.databaseName, 'db_a1');
    });

    test('updateTabConnection/Database/DatabaseType 真实委托（stub 回归守卫）',
        () {
      final provider = AppProvider();
      provider.tab
          .addTab(_tab('conn-a', DatabaseType.mysql, 'db_a1'));

      provider.updateTabConnection(0, 'conn-x');
      provider.updateTabDatabase(0, 'db_x');
      provider.updateTabDatabaseType(0, DatabaseType.sqlite);

      expect(provider.tabs[0].connectionId, 'conn-x',
          reason: 'ad792732 曾把本代理抽成空 stub，切换上下文静默失效');
      expect(provider.tabs[0].databaseName, 'db_x');
      expect(provider.tabs[0].databaseType, DatabaseType.sqlite);
    });
  });

  group('方向 A：tab 上下文绑定（2026-09-04 侧边栏导航劫持修复）', () {
    test('已绑定 tab（双击表 openQueryTab 打开）不被侧边栏切换覆写', () async {
      final provider = AppProvider();
      final a = _server('conn-a', 'A', DatabaseType.mysql);
      final b = _server('conn-b', 'B', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a, ['db_a1']);
      _connectForTest(provider, b, ['db_b1']);
      provider.connection.setCurrentServerForTest(a);

      // 双击表路径：openQueryTab 携带显式上下文（默认绑定）。
      await provider.openQueryTab('conn-a', 'db_a1');
      expect(provider.activeTab?.isContextBound, isTrue,
          reason: 'openQueryTab 的调用方均携带显式上下文，默认绑定');

      // 侧边栏点实例 B 导航（此时活跃 tab 是 query A 的 tab）。
      final ok = await provider.switchToConnection('conn-b');

      expect(ok, isTrue);
      expect(provider.connection.currentServer?.id, 'conn-b',
          reason: '连接层全局切换照常（侧边栏高亮/浏览功能不受影响）');
      expect(provider.activeTab?.connectionId, 'conn-a',
          reason: '已绑定 tab 的上下文不得被侧边栏导航劫持');
      expect(provider.activeTab?.databaseName, 'db_a1');
      expect(provider.activeTab?.databaseType, DatabaseType.mysql);
    });

    test('未绑定 tab（「+」新建）跟随侧边栏切换（2026-08-27 语义保留）', () async {
      final provider = AppProvider();
      final a = _server('conn-a', 'A', DatabaseType.mysql);
      final b = _server('conn-b', 'B', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a, ['db_a1']);
      _connectForTest(provider, b, ['db_b1']);
      provider.connection.setCurrentServerForTest(a);
      provider.tab.addTab(_tab('conn-a', DatabaseType.mysql, 'db_a1'));

      // 「+」新建无参：抄活跃 tab 上下文但不绑定（跟随型）。
      await provider.addNewTab();
      expect(provider.activeTab?.isContextBound, isFalse);

      final ok = await provider.switchToConnection('conn-b');

      expect(ok, isTrue);
      expect(provider.activeTab?.connectionId, 'conn-b',
          reason: '跟随型 tab 的工具栏芯片与执行库继续跟随侧边栏');
      expect(provider.activeTab?.databaseName, 'db_b1');
    });

    test('工具栏显式切换（sync+bind）后，侧边栏不再覆写该 tab', () async {
      final provider = AppProvider();
      final a = _server('conn-a', 'A', DatabaseType.mysql);
      final b = _server('conn-b', 'B', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      _connectForTest(provider, a, ['db_a1']);
      _connectForTest(provider, b, ['db_b1']);
      provider.connection.setCurrentServerForTest(a);
      provider.tab.addTab(_tab('conn-a', DatabaseType.mysql, 'db_a1'));

      // 模拟 _switchConnection：switchToConnection 成功后显式 sync + bind。
      final ok = await provider.switchToConnection('conn-b');
      expect(ok, isTrue);
      provider.syncTabConnection(0, 'conn-b');
      provider.bindTabContext(0);
      expect(provider.tabs[0].connectionId, 'conn-b');

      // 之后侧边栏切回 A：已绑定 tab 不动。
      await provider.switchToConnection('conn-a');

      expect(provider.connection.currentServer?.id, 'conn-a');
      expect(provider.tabs[0].connectionId, 'conn-b',
          reason: '工具栏显式选过的连接是该 tab 的用户设定，侧边栏不得覆写');
      expect(provider.tabs[0].databaseName, 'db_b1');
    });

    test('followActiveTabDatabase：未绑定跟随 / 已绑定不动', () {
      final provider = AppProvider();
      provider.tab.addTab(_tab('conn-a', DatabaseType.mysql, 'db_a1'));

      provider.followActiveTabDatabase('db_a2');
      expect(provider.tabs[0].databaseName, 'db_a2',
          reason: '未绑定 tab 的库芯片跟随侧边栏选库');

      provider.bindTabContext(0);
      provider.followActiveTabDatabase('db_a1');
      expect(provider.tabs[0].databaseName, 'db_a2',
          reason: '已绑定 tab 的库为用户显式设定，侧边栏选库不得覆写');
    });

    test('QueryTab 序列化：isContextBound 往返 + 旧持久化数据兜底', () {
      final bound = QueryTab(
        id: 't1',
        title: 'q',
        connectionId: 'conn-a',
        databaseName: 'db_a1',
        isContextBound: true,
      );
      expect(QueryTab.fromJson(bound.toJson()).isContextBound, isTrue);

      // 旧数据（无 isContextBound 字段）：带上下文恢复的 tab 视为已绑定
      // （崩溃恢复后首次侧边栏导航不得劫持），无上下文的跟随。
      final legacy = {
        'id': 't2',
        'title': 'q',
        'sql': '',
        'connectionId': 'conn-a',
        'databaseName': 'db_a1',
      };
      expect(QueryTab.fromJson(legacy).isContextBound, isTrue);
      expect(
        QueryTab.fromJson({...legacy, 'connectionId': null}).isContextBound,
        isFalse,
      );
    });
  });
}
