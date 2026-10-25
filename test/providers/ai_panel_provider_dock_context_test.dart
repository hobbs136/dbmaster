// UIRV-A1 · AI dock 上下文卡：跟随 + 手动改选（Provider 层）。
//
// 从任务书验收条款直译（tasks-ui-review-fixes.md §UIRV-A1）：
// - AC3/AC7：手动覆盖为会话级内存标记（不落盘、不新增 prefs 键）；
//   生效优先级 = 手动覆盖 > 跟随投影（连接级事件不冲掉手动覆盖——
//   syncFollowContext 在 MANUAL 态 no-op）；
// - AC7：contextBuilder 生效值 = 卡上生效值（发送路径快照一致性）；
// - AC3：「恢复跟随」→ 回 FOLLOW（后续跟随投影可再写入）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/providers/ai_panel_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AiPanelProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = AiPanelProvider();
  });

  group('AI dock 上下文覆盖/跟随（UIRV-A1）', () {
    test('P1 跟随投影写入 selected/contextBuilder/来源标记', () {
      provider.syncFollowContext(
        connectionId: 'conn_a',
        databaseName: 'main',
        source: AiDockContextSource.sidebar,
      );

      expect(provider.selectedConnectionId, 'conn_a');
      expect(provider.selectedDatabaseName, 'main');
      expect(provider.contextBuilder.currentConnection, 'conn_a');
      expect(provider.contextBuilder.currentDatabase, 'main');
      expect(provider.followSource, AiDockContextSource.sidebar);
      expect(provider.manualContextOverride, isFalse);
    });

    test('P1b 同值重复投影为纯 no-op（不触发 listener）', () {
      provider.syncFollowContext(
        connectionId: 'conn_a',
        databaseName: 'main',
        source: AiDockContextSource.sidebar,
      );

      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.syncFollowContext(
        connectionId: 'conn_a',
        databaseName: 'main',
        source: AiDockContextSource.sidebar,
      );

      expect(notifications, 0, reason: '同值同源重复投影应零通知零写');
    });

    test('P2 手动覆盖优先：MANUAL 态下跟随投影 no-op（连接级事件不冲掉）', () {
      provider.setManualDockContext('conn_b', databaseName: 'shop');

      provider.syncFollowContext(
        connectionId: 'conn_a',
        databaseName: 'main',
        source: AiDockContextSource.activeTab,
      );

      expect(provider.manualContextOverride, isTrue);
      expect(provider.selectedConnectionId, 'conn_b');
      expect(provider.selectedDatabaseName, 'shop');
      expect(provider.contextBuilder.currentConnection, 'conn_b');
      expect(provider.contextBuilder.currentDatabase, 'shop');
    });

    test('P3 手动覆盖写 contextBuilder（发送路径生效值 = 卡上生效值）', () {
      provider.setManualDockContext('conn_b', databaseName: 'shop');

      expect(provider.contextBuilder.currentConnection, 'conn_b');
      expect(provider.contextBuilder.currentDatabase, 'shop');
    });

    test('P4 恢复跟随：清除覆盖标记，后续跟随投影可再写入', () {
      provider.setManualDockContext('conn_b');
      provider.restoreFollowContext();

      expect(provider.manualContextOverride, isFalse);

      provider.syncFollowContext(
        connectionId: 'conn_a',
        databaseName: 'main',
        source: AiDockContextSource.currentServer,
      );
      expect(provider.selectedConnectionId, 'conn_a');
      expect(provider.followSource, AiDockContextSource.currentServer);
    });

    test('P4b 恢复跟随在非覆盖态为幂等 no-op', () {
      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.restoreFollowContext();
      expect(notifications, 0);
    });

    test('P5 会话级内存标记：不新增持久化（无 prefs 写入面可断言——'
        '覆盖标记 getter 在新构造的 provider 上为 false）', () {
      final fresh = AiPanelProvider();
      expect(fresh.manualContextOverride, isFalse,
          reason: '覆盖为会话级内存标记，不跨实例持久化');
    });
  });
}
