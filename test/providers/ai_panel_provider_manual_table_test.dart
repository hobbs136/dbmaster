// B-03 上下文卡手动表契约（v0.3.5 批2 T5，Epic 2.1）：
// 从任务书边界冻结原文 + 验收 UI35-211~215 直译，不从实现反推。
//
// 不变量：
// ① 三元组（connectionId/databaseName/tableName）同批原子写入，禁止
//    「库跟随、表手动」混合态（单次 notify 内即全量就位）；
// ② tableName == null = 清空手动表（经 contextBuilder.setCurrentTable(null)
//    传播）；
// ③ 只换连接 / 只换库必须显式 tableName: null（provider 不继承旧表）；
// ④ restoreFollowContext() 同时清空手动表；
// ⑤ 会话级内存，不落盘；
// ⑥ setSelectedTable(String) 既有语义零改动（不写 selectedManualTable）。
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

  group('B-03 手动上下文三元组（UI35-211~215）', () {
    test('UI35-211 三元组原子落 provider 与 contextBuilder（单次通知即全量就位）', () {
      late String? seenConn;
      late String? seenDb;
      late String? seenTable;
      var notifications = 0;
      provider.addListener(() {
        notifications++;
        // 通知时刻读快照：三元组必须已经全部就位（无中间态）。
        seenConn = provider.selectedConnectionId;
        seenDb = provider.selectedDatabaseName;
        seenTable = provider.selectedManualTable;
      });

      provider.setManualDockContext(
        'conn_b',
        databaseName: 'shop',
        tableName: 'orders',
      );

      expect(provider.manualContextOverride, isTrue);
      expect(provider.selectedConnectionId, 'conn_b');
      expect(provider.selectedDatabaseName, 'shop');
      expect(provider.selectedManualTable, 'orders');
      expect(provider.contextBuilder.currentConnection, 'conn_b');
      expect(provider.contextBuilder.currentDatabase, 'shop');
      expect(provider.contextBuilder.currentTable, 'orders');
      expect(notifications, 1, reason: '一次 notify 承载三元组原子写入');
      expect(seenConn, 'conn_b');
      expect(seenDb, 'shop');
      expect(seenTable, 'orders', reason: '监听回调内三元组已全量就位');
    });

    test('UI35-212 只换库（显式 tableName: null）→ 表清空', () {
      provider.setManualDockContext(
        'conn_b',
        databaseName: 'shop',
        tableName: 'orders',
      );

      provider.setManualDockContext(
        'conn_b',
        databaseName: 'other_db',
        tableName: null,
      );

      expect(provider.selectedConnectionId, 'conn_b');
      expect(provider.selectedDatabaseName, 'other_db');
      expect(provider.selectedManualTable, isNull);
      expect(provider.contextBuilder.currentTable, isNull);
    });

    test('UI35-213 只换连接（显式 tableName: null）→ 表清空', () {
      provider.setManualDockContext(
        'conn_b',
        databaseName: 'shop',
        tableName: 'orders',
      );

      provider.setManualDockContext(
        'conn_c',
        databaseName: 'shop',
        tableName: null,
      );

      expect(provider.selectedConnectionId, 'conn_c');
      expect(provider.selectedDatabaseName, 'shop');
      expect(provider.selectedManualTable, isNull);
      expect(provider.contextBuilder.currentTable, isNull);
    });

    test(
      'UI35-214 tableName: null → contextBuilder.currentTable 与 getter 同清',
      () {
        provider.setManualDockContext(
          'conn_b',
          databaseName: 'shop',
          tableName: 'orders',
        );
        expect(provider.contextBuilder.currentTable, 'orders');

        provider.setManualDockContext(
          'conn_b',
          databaseName: 'shop',
          tableName: null,
        );

        expect(provider.selectedManualTable, isNull);
        expect(provider.contextBuilder.currentTable, isNull);
      },
    );

    test('UI35-215 restoreFollowContext → 手动表清空 + 回 FOLLOW', () {
      provider.setManualDockContext(
        'conn_b',
        databaseName: 'shop',
        tableName: 'orders',
      );

      provider.restoreFollowContext();

      expect(provider.selectedManualTable, isNull);
      expect(provider.contextBuilder.currentTable, isNull);
      expect(provider.manualContextOverride, isFalse);
    });

    test('B-03④ restoreFollowContext 后跟随投影不再携带手动表', () {
      provider.setManualDockContext(
        'conn_b',
        databaseName: 'shop',
        tableName: 'orders',
      );
      provider.restoreFollowContext();
      provider.syncFollowContext(
        connectionId: 'conn_a',
        databaseName: 'main',
        source: AiDockContextSource.sidebar,
      );

      expect(provider.selectedConnectionId, 'conn_a');
      expect(provider.selectedManualTable, isNull);
      expect(provider.contextBuilder.currentTable, isNull);
    });

    test('B-03⑤ 会话级内存：新实例 selectedManualTable 为 null（不落盘）', () {
      provider.setManualDockContext(
        'conn_b',
        databaseName: 'shop',
        tableName: 'orders',
      );
      final fresh = AiPanelProvider();
      expect(fresh.selectedManualTable, isNull);
      expect(fresh.manualContextOverride, isFalse);
    });
  });

  group('B-03⑥ setSelectedTable 既有语义零改动', () {
    test(
      'setSelectedTable 写 selectedTable/contextBuilder，不写 selectedManualTable',
      () {
        provider.setSelectedTable('t1');

        expect(provider.selectedTable, 't1');
        expect(provider.contextBuilder.currentTable, 't1');
        expect(provider.selectedManualTable, isNull);
      },
    );

    test('手动三元组不反向污染 selectedTable（其它调用方不受影响）', () {
      provider.setSelectedTable('t1');
      provider.setManualDockContext(
        'conn_b',
        databaseName: 'shop',
        tableName: 'orders',
      );

      expect(provider.selectedTable, 't1');
      expect(provider.selectedManualTable, 'orders');
    });
  });
}
