// T25（J3 多连接长驻树地基）→ T1 再反转（S5 重锚定）·
// AppProvider.activeContextConnection 单测。
//
// 覆盖：四态解析序（T1 反转后：侧栏选中 → 活动 tab → currentServer →
// null）+ tab 指向未连接连接时仍返回该连接对象（上下文锚定不过滤连接态）
// + tab 指向已删除连接时逐级降级（不崩不悬空）+ 与执行默认
// activeConnectionId（tab → currentServer 两级，零改动）的分层差分；
// T1 新增 tab 激活回同步组（切 tab / 空白 tab / 同 tab 改绑 / 高频
// notify 幂等——面板跟随最近连接级手势）。
//
// 用例登记建议编号：DBT-ACTX-001~012（回报 T28 汇总登记）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/database_models.dart'
    show DatabaseType, DbServer;
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart' show QueryTab;

DbServer _server(String id, DatabaseType type) => DbServer(
      id: id,
      type: type,
      name: 'srv-$id',
      host: '192.0.2.128',
      port: 3306,
      username: 'u',
    );

QueryTab _tab(String connectionId) => QueryTab(
      id: 't-$connectionId',
      title: 'query',
      sql: 'SELECT 1',
      connectionId: connectionId,
      databaseName: 'db',
      databaseType: DatabaseType.mysql,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('activeContextConnection 解析序（T1 再反转：选中 → 活动 tab → currentServer）', () {
    test('① 侧栏选中优先于活动 tab 与 currentServer（三级并存）', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.tab.addTab(_tab('a')); // 回同步把选中写为 a
      // 显式再写选中 B：模拟树点选 B——最近连接级手势胜出（S5 缺陷
      // 场景：tab 优先序下选中级在多连接并存时永不可达）。
      provider.sidebar.selectConnection('b');

      expect(provider.activeContextConnection, same(b));
    });

    test('② 选中为空 → 活动 tab 的连接优先于 currentServer', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.tab.addTab(_tab('a'));
      provider.sidebar.selectConnection(null); // 选中级显式清空

      expect(provider.activeContextConnection, same(a));
    });

    test('③ tab 无 connectionId（历史持久化 tab 兜底链生效）→ currentServer',
        () {
      final provider = AppProvider();
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.tab.addTab(
        QueryTab(id: 't-free', title: 'query', sql: 'SELECT 1'),
      );

      expect(provider.activeContextConnection, same(b));
    });

    test('④ tab 与 currentServer 均空 → 侧栏选中', () {
      final provider = AppProvider();
      final c = _server('c', DatabaseType.redis);
      provider.connection.addSavedServerForTest(c);
      provider.sidebar.selectConnection('c');

      expect(provider.activeContextConnection, same(c));
    });

    test('⑤ 三级全空 → null（冷启动）', () {
      final provider = AppProvider();
      expect(provider.activeContextConnection, isNull);
    });

    test('tab 指向未连接连接 → 仍返回该连接对象（上下文不过滤连接态）', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      // 仅入 savedConnections，不注册连接态（isConnectionConnected=false）。
      provider.connection.addSavedServerForTest(a);
      provider.tab.addTab(_tab('a'));

      expect(provider.activeContextConnection, same(a));
    });

    test('tab 指向已删除连接（查不到）→ 逐级降级不悬空', () {
      final provider = AppProvider();
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.tab.addTab(_tab('deleted-x')); // 不在 savedConnections
      // 回同步把选中也写成已删连接 id（选中级同样解析不到）→ 双级降级。

      expect(provider.activeContextConnection, same(b));
    });

    test('分层差分：activeConnectionId（执行默认）不含侧栏选中级，零改动', () {
      final provider = AppProvider();
      final c = _server('c', DatabaseType.redis);
      provider.connection.addSavedServerForTest(c);
      provider.sidebar.selectConnection('c');

      expect(
        provider.activeConnectionId,
        isNull,
        reason: '执行默认语义零改动：tab → currentServer 两级',
      );
      expect(provider.activeContextConnection, same(c));
    });
  });

  group('tab 激活回同步（T1：面板跟随最近连接级手势）', () {
    test('选中 B + 激活绑 A 的 tab → 选中回 A（最新手势胜出）', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      // 前置：选中锚在 B（模拟树点选 B 后切回 tab 的场景）。
      provider.sidebar.selectConnection('b');

      provider.tab.addTab(_tab('a'));

      expect(
        provider.sidebar.selectedConnectionId,
        'a',
        reason: 'tab 激活 = 连接级手势，回同步写选中',
      );
    });

    test('激活空白/未绑定 tab（cid=null）→ 选中保持 B（不清选中）', () {
      final provider = AppProvider();
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(b);
      provider.sidebar.selectConnection('b');

      provider.tab.addTab(
        QueryTab(id: 't-free', title: 'query', sql: 'SELECT 1'),
      );

      expect(
        provider.sidebar.selectedConnectionId,
        'b',
        reason: '空白 tab 不清选中——保持用户最后一次连接级手势',
      );
    });

    test('同 tab 工具栏改绑 B（syncTabConnection 同 tab 换连接）→ 选中 B', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      provider.tab.addTab(_tab('a')); // 活动tab 绑 A

      provider.syncTabConnection(0, 'b');

      expect(
        provider.sidebar.selectedConnectionId,
        'b',
        reason: '改绑也是连接级手势，回同步跟随新连接',
      );
    });

    test('高频 tab notify（查询执行期风暴）→ 选中零变化零额外 notify', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      provider.connection.addSavedServerForTest(a);
      provider.tab.addTab(_tab('a'));
      final before = provider.sidebar.selectedConnectionId;

      var sidebarNotifies = 0;
      provider.sidebar.addListener(() => sidebarNotifies++);

      // 模拟查询执行期 notify 风暴：结果刷新等高频通知，活动 tab 的
      // (id, connectionId) 不变。
      for (var i = 0; i < 50; i++) {
        provider.tab.updateTabExecutionResults(0, const []);
      }

      expect(provider.sidebar.selectedConnectionId, before);
      expect(
        sidebarNotifies,
        0,
        reason: 'listener 幂等：O(1) 快照比较，无变化零写零 notify',
      );
    });
  });

  group('currentServer 变更回同步（T1b：面板跟随最近连接级事件）', () {
    // setCurrentServerForTest 本身不 notify——借 clearError()（无条件
    // notifyListeners、零状态副作用）驱动 connection listener。
    test('currentServer A → B → 选中 B（任何成为 currentServer 的路径）', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(a);
      provider.connection.clearError();
      expect(provider.sidebar.selectedConnectionId, 'a');

      provider.connection.setCurrentServerForTest(b);
      provider.connection.clearError();

      expect(provider.sidebar.selectedConnectionId, 'b');
    });

    test('currentServer → null（断开清理）→ 选中不变（不写不清）', () async {
      final provider = AppProvider();
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.connection.clearError();
      expect(provider.sidebar.selectedConnectionId, 'b');

      // 真实断开清理路径：无剩余连接 → currentServer 置 null + notify。
      await provider.connection.disconnectAllConnections();

      expect(
        provider.sidebar.selectedConnectionId,
        'b',
        reason: '变为 null 不写不清——锚点降级交已连接护栏/解析链',
      );
    });

    test('connection 高频 notify（databases 刷新类）→ 零额外写（幂等）', () {
      final provider = AppProvider();
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.connection.clearError(); // 首次：写选中 b
      expect(provider.sidebar.selectedConnectionId, 'b');

      var sidebarNotifies = 0;
      provider.sidebar.addListener(() => sidebarNotifies++);

      // currentServer id 不变的风暴（库列表刷新等）。
      for (var i = 0; i < 50; i++) {
        provider.connection.clearError();
      }

      expect(provider.sidebar.selectedConnectionId, 'b');
      expect(
        sidebarNotifies,
        0,
        reason: 'O(1) last-seen 比较，id 不变零写零 notify',
      );
    });

    test('组合防打架：currentServer=B（选中 B）后激活绑 A 的 tab → 选回 A', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.connection.clearError(); // connection 回同步 → 选中 B
      expect(provider.sidebar.selectedConnectionId, 'b');

      provider.tab.addTab(_tab('a')); // tab 激活 → 回同步 → 选回 A

      expect(
        provider.sidebar.selectedConnectionId,
        'a',
        reason: '两 listener 收敛同值：最新连接级手势胜出',
      );
    });
  });
}
