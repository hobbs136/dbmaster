// T25（J3 多连接长驻树地基）· AppProvider.activeContextConnection 单测。
//
// 覆盖（任务书验收标准 ①）：四态解析序（活动 tab → currentServer →
// 侧栏选中 → null）+ tab 指向未连接连接时仍返回该连接对象（上下文锚定
// 不过滤连接态）+ tab 指向已删除连接时逐级降级（不崩不悬空）+ 与执行
// 默认 activeConnectionId（tab → currentServer 两级，零改动）的分层差分。
//
// 用例登记建议编号：DBT-ACTX-001~007（回报 T28 汇总登记）。
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

  group('activeContextConnection 解析序（T25）', () {
    test('① 活动 tab 的连接优先于 currentServer', () {
      final provider = AppProvider();
      final a = _server('a', DatabaseType.mysql);
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(a);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.tab.addTab(_tab('a'));

      expect(provider.activeContextConnection, same(a));
    });

    test('② tab 无 connectionId（历史持久化 tab 兜底链生效）→ currentServer',
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

    test('③ tab 与 currentServer 均空 → 侧栏选中', () {
      final provider = AppProvider();
      final c = _server('c', DatabaseType.redis);
      provider.connection.addSavedServerForTest(c);
      provider.sidebar.selectConnection('c');

      expect(provider.activeContextConnection, same(c));
    });

    test('④ 三级全空 → null（冷启动）', () {
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

    test('tab 指向已删除连接（查不到）→ 降级 currentServer（不悬空）', () {
      final provider = AppProvider();
      final b = _server('b', DatabaseType.postgresql);
      provider.connection.addSavedServerForTest(b);
      provider.connection.setCurrentServerForTest(b);
      provider.tab.addTab(_tab('deleted-x')); // 不在 savedConnections

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
}
