// T16 J4 — 只读对象标签（ER 图/表属性）TabProvider 单元测试。
// 覆盖：openObjectTab 新建/去重复用聚焦/initialTabIndex 覆写/关闭清理/
// QueryTab.toJson 零改守卫（对象态不进持久化面）。
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:dbmaster/services/database_service.dart';

class MockDatabaseService extends Mock implements DatabaseService {}

void main() {
  group('TabProvider object tabs (T16 J4)', () {
    late TabProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = TabProvider(MockDatabaseService());
    });

    test('openObjectTab 新建：全隐布局 + 上下文绑定 + 关闭无未保存', () {
      final tabId = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          databaseName: 'db1',
          objectName: 'users',
        ),
      );

      expect(provider.tabs.length, 1);
      expect(provider.activeTab?.id, tabId);
      final ref = provider.objectTabFor(tabId);
      expect(ref, isNotNull);
      expect(ref!.kind, ObjectTabKind.tableProperties);
      expect(ref.objectName, 'users');
      expect(ref.connectionId, 'conn-1');
      // 对象 tab 三面板全隐（内容占满由 EditorResultsSplit 分流）
      final layout = provider.panelLayoutFor(tabId);
      expect(layout.editorVisible, isFalse);
      expect(layout.filterBarVisible, isFalse);
      expect(layout.resultsVisible, isFalse);
      // 不跟随侧栏连接切换（per-tab connectionId 隔离）
      expect(provider.activeTab?.isContextBound, isTrue);
      // 只读视图：sql 恒空 → isTabUnsaved 恒 false → 关闭无确认路径
      expect(provider.activeTab?.sql, isEmpty);
      expect(TabProvider.isTabUnsaved(provider.activeTab!), isFalse);
    });

    test('去重：同 kind+connectionId+objectName 复用聚焦，不无限开新', () {
      final first = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'users',
        ),
      );
      // 切走后再开同对象
      provider.openQueryTab(connectionId: 'conn-1', databaseName: 'db1');
      expect(provider.tabs.length, 2);
      final second = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'users',
        ),
      );
      expect(second, first);
      expect(provider.tabs.length, 2, reason: '复用既有对象 tab，不新增');
      expect(provider.activeTab?.id, first);
    });

    test('复用时 initialTabIndex 覆写（「查看 DDL」直达语义）', () {
      final tabId = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'users',
          initialTabIndex: 0,
        ),
      );
      provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'users',
          initialTabIndex: 3,
        ),
      );
      expect(provider.objectTabFor(tabId)?.initialTabIndex, 3);
    });

    test('去重键区分：不同 objectName / 不同 connectionId 不复用', () {
      provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'users',
        ),
      );
      provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'orders',
        ),
      );
      provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-2',
          objectName: 'users',
        ),
      );
      provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.erDiagram,
          connectionId: 'conn-1',
          databaseName: 'db1',
        ),
      );
      expect(provider.tabs.length, 4, reason: '四个不同去重键各开一个');
    });

    test('ER 图 ref：objectName 空 + 同连接去重', () {
      final a = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.erDiagram,
          connectionId: 'conn-1',
          databaseName: 'db1',
        ),
      );
      final b = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.erDiagram,
          connectionId: 'conn-1',
          databaseName: 'db2',
        ),
      );
      expect(a, b, reason: '同连接 ER 图 tab 复用（databaseName 不入键）');
      expect(provider.tabs.length, 1);
    });

    test('关闭清理：forceCloseTab / closeAllTabs 清空对象引用', () async {
      final tabId = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'users',
        ),
      );
      expect(provider.objectTabFor(tabId), isNotNull);
      await provider.forceCloseTab(0);
      expect(provider.objectTabFor(tabId), isNull);

      final tabId2 = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.erDiagram,
          connectionId: 'conn-1',
        ),
      );
      await provider.closeAllTabs();
      expect(provider.objectTabFor(tabId2), isNull);
      expect(provider.tabs, isEmpty);
    });

    test('QueryTab.toJson 零改守卫：对象态不进持久化面', () {
      final tabId = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'users',
        ),
      );
      final json = provider.tabs.first.toJson();
      // 既有字段集之外不得出现对象引用字段（会话级平行 map 承载）
      expect(json.keys, containsAll(<String>['id', 'title', 'sql']));
      expect(
        json.keys.any((k) => k.toLowerCase().contains('object')),
        isFalse,
        reason: '对象引用不得渗入 QueryTab.toJson',
      );
      // 对象 tab 关闭后按普通 tab 模型回收（id 稳定）
      expect(json['id'], tabId);
    });

    test('tab id 唯一性：同毫秒连续打开不碰撞（引用不被覆盖）', () {
      // 连续同步调用两次（同毫秒）——回归锚定：时间戳 id 碰撞曾导致
      // 第二个对象 tab 覆盖第一个的引用（两 tab 同 id）。
      final id1 = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'conn-1',
          objectName: 'users',
        ),
      );
      final id2 = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.erDiagram,
          connectionId: 'conn-1',
        ),
      );
      expect(id1, isNot(id2));
      expect(provider.tabs.length, 2);
      expect(
        provider.tabs.map((t) => t.id).toSet().length,
        2,
        reason: 'tab id 不得重复',
      );
      expect(provider.objectTabFor(id1)?.objectName, 'users');
      expect(provider.objectTabFor(id2)?.kind, ObjectTabKind.erDiagram);
    });
  });
}
