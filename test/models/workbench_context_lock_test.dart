import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/models/workbench_context_lock.dart';
import 'package:dbmaster/providers/ai_panel_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorkbenchContextLock 模型', () {
    test('toJson → fromMetadata 往返一致', () {
      final lock = WorkbenchContextLock(
        connectionId: 'conn_1',
        databaseName: 'db_1',
        lockedAt: DateTime(2026, 9, 22, 10, 30, 0),
      );

      final restored = WorkbenchContextLock.fromMetadata({
        WorkbenchContextLock.metadataKey: lock.toJson(),
      });

      expect(restored, equals(lock));
    });

    test('databaseName 为 null（连接级锁定）可往返', () {
      final lock = WorkbenchContextLock(
        connectionId: 'conn_1',
        lockedAt: DateTime(2026, 9, 22),
      );

      final restored = WorkbenchContextLock.fromMetadata({
        WorkbenchContextLock.metadataKey: lock.toJson(),
      });

      expect(restored?.databaseName, isNull);
      expect(restored?.connectionId, 'conn_1');
    });

    test('metadata 为空 / 无键 → null（跟随态）', () {
      expect(WorkbenchContextLock.fromMetadata(null), isNull);
      expect(WorkbenchContextLock.fromMetadata(const {}), isNull);
      expect(
        WorkbenchContextLock.fromMetadata({'other.key': 1}),
        isNull,
        reason: 'workbench.context 命名空间之外的键不构成锁定',
      );
    });

    test('畸形数据 → null，不抛异常（损坏 JSON 兜底）', () {
      expect(
        WorkbenchContextLock.fromMetadata({
          WorkbenchContextLock.metadataKey: 'not_a_map',
        }),
        isNull,
      );
      expect(
        WorkbenchContextLock.fromMetadata({
          WorkbenchContextLock.metadataKey: <String, dynamic>{},
        }),
        isNull,
        reason: '缺 connectionId 视为无效',
      );
      expect(
        WorkbenchContextLock.fromMetadata({
          WorkbenchContextLock.metadataKey: <String, dynamic>{
            'connectionId': 42,
          },
        }),
        isNull,
      );
    });

    test('键名位于 workbench.context 命名空间（C-3）', () {
      expect(WorkbenchContextLock.metadataKey, 'workbench.contextLock');
    });
  });

  group('AiPanelProvider 工作台锁定成员（锁定随会话，AC3.5）', () {
    late AiPanelProvider aiPanel;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      aiPanel = AiPanelProvider();
    });

    test('新建会话默认无锁定（跟随态）', () {
      aiPanel.createNewSession();

      expect(aiPanel.workbenchContextLock, isNull);
    });

    test('无会话时锁定为 no-op，不抛异常', () {
      aiPanel.lockWorkbenchContext('conn_1', 'db_1');

      expect(aiPanel.workbenchContextLock, isNull);
      expect(aiPanel.sessionManager.currentSession, isNull);
    });

    test('锁定写入当前会话并可读回', () {
      aiPanel.createNewSession();

      aiPanel.lockWorkbenchContext('conn_1', 'db_1');

      final lock = aiPanel.workbenchContextLock;
      expect(lock, isNotNull);
      expect(lock!.connectionId, 'conn_1');
      expect(lock.databaseName, 'db_1');
      // 存储形态：session.metadata 的 workbench.contextLock 键。
      final raw = aiPanel.sessionManager.currentSession?.metadata;
      expect(raw, isNotNull);
      expect(raw!.containsKey(WorkbenchContextLock.metadataKey), isTrue);
      expect(
        raw[WorkbenchContextLock.metadataKey],
        isA<Map<String, dynamic>>(),
      );
    });

    test('切换会话各带各的锁定（会话 A 锁 conn_a、会话 B 锁 conn_b）', () {
      aiPanel.createNewSession(); // A
      aiPanel.lockWorkbenchContext('conn_a', 'db_a');
      final sessionA = aiPanel.sessionManager.currentSession!;

      aiPanel.createNewSession(); // B（新会话不带 A 的锁定）
      expect(aiPanel.workbenchContextLock, isNull);
      aiPanel.lockWorkbenchContext('conn_b', null);
      final sessionB = aiPanel.sessionManager.currentSession!;

      aiPanel.switchSession(sessionA.id);
      expect(aiPanel.workbenchContextLock?.connectionId, 'conn_a');
      expect(aiPanel.workbenchContextLock?.databaseName, 'db_a');

      aiPanel.switchSession(sessionB.id);
      expect(aiPanel.workbenchContextLock?.connectionId, 'conn_b');
      expect(aiPanel.workbenchContextLock?.databaseName, isNull);
    });

    test('解除锁定仅作用于当前会话，其它会话锁定保留', () {
      aiPanel.createNewSession();
      aiPanel.lockWorkbenchContext('conn_a', 'db_a');
      final sessionA = aiPanel.sessionManager.currentSession!;

      aiPanel.createNewSession();
      aiPanel.lockWorkbenchContext('conn_b', 'db_b');

      aiPanel.unlockWorkbenchContext();
      expect(aiPanel.workbenchContextLock, isNull);

      aiPanel.switchSession(sessionA.id);
      expect(aiPanel.workbenchContextLock?.connectionId, 'conn_a');
    });

    test('解除不存在的锁定为 no-op；锁定后解除再锁定可循环', () {
      aiPanel.createNewSession();

      aiPanel.unlockWorkbenchContext();
      expect(aiPanel.workbenchContextLock, isNull);

      aiPanel.lockWorkbenchContext('conn_1', 'db_1');
      aiPanel.unlockWorkbenchContext();
      aiPanel.lockWorkbenchContext('conn_2', 'db_2');
      expect(aiPanel.workbenchContextLock?.connectionId, 'conn_2');
    });

    test('解除锁定保留 metadata 其它条目（不整 map 清空）', () {
      aiPanel.createNewSession();
      aiPanel.lockWorkbenchContext('conn_1', 'db_1');
      final metadata = aiPanel.sessionManager.currentSession!.metadata!;
      metadata['unrelated.key'] = 'keep-me';

      aiPanel.unlockWorkbenchContext();

      expect(aiPanel.workbenchContextLock, isNull);
      expect(
        aiPanel.sessionManager.currentSession?.metadata?['unrelated.key'],
        'keep-me',
      );
    });

    test('lockWorkbenchContext 触发 notifyListeners（setter 尾通知）', () {
      aiPanel.createNewSession();
      var notifications = 0;
      aiPanel.addListener(() => notifications++);

      aiPanel.lockWorkbenchContext('conn_1', 'db_1');

      expect(notifications, 1);
    });
  });
}
