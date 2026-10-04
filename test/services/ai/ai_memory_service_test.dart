import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/models/ai_memory_item.dart';
import 'package:dbmaster/services/ai/ai_memory_service.dart';

/// T3 · AiMemoryService 单测（AI-MEM-001~008）。
///
/// SharedPreferences 用 `setMockInitialValues`；防抖用真实 Timer
/// （test() 非 testWidgets，无 pending-timer 约束），flush() 用于确定性落盘。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AiMemoryService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AiMemoryService().resetForTesting();
    service = AiMemoryService();
    await service.initialize();
  });

  tearDown(() {
    // 取消在途防抖 Timer，避免跨用例迟到落盘污染 mock prefs。
    service.resetForTesting();
  });

  Future<SharedPreferences> prefs() => SharedPreferences.getInstance();

  /// 直接写 prefs 种子数据（可精确控制 updatedAt），再重载服务。
  Future<void> seedScope(String key, List<AiMemoryItem> items) async {
    final p = await prefs();
    await p.setString(key, jsonEncode(items.map((e) => e.toJson()).toList()));
    service.resetForTesting();
    await service.initialize();
  }

  group('AiMemoryItem 模型（AI-MEM-001）', () {
    test('fromJson/toJson 往返保留全部字段', () {
      final item = AiMemoryItem(
        id: 'mem_123_0',
        scope: AiMemoryScope.connection,
        connectionId: 'conn_1',
        subject: 'orders.status',
        content: '状态机：pending → paid → shipped',
        source: AiMemorySource.agent,
        createdAt: 1700000000000,
        updatedAt: 1700000001000,
      );
      final restored = AiMemoryItem.fromJson(item.toJson());
      expect(restored.id, item.id);
      expect(restored.scope, AiMemoryScope.connection);
      expect(restored.connectionId, 'conn_1');
      expect(restored.subject, 'orders.status');
      expect(restored.content, item.content);
      expect(restored.source, AiMemorySource.agent);
      expect(restored.createdAt, 1700000000000);
      expect(restored.updatedAt, 1700000001000);
    });

    test('未知 scope/source 回退默认值，缺字段不抛', () {
      final item = AiMemoryItem.fromJson(<String, dynamic>{
        'scope': 'bogus',
        'source': 'bogus',
        'content': 'x',
      });
      expect(item.scope, AiMemoryScope.global);
      expect(item.source, AiMemorySource.manual);
      expect(item.connectionId, isNull);
      expect(item.subject, isNull);
      expect(item.createdAt, 0);
    });

    test('copyWith 可清空 subject 且不影响身份字段', () {
      final item = AiMemoryItem(
        id: 'a',
        scope: AiMemoryScope.global,
        subject: 's',
        content: 'c',
        createdAt: 1,
        updatedAt: 1,
      );
      final cleared = item.copyWith(subject: null, updatedAt: 2);
      expect(cleared.subject, isNull);
      expect(cleared.content, 'c');
      expect(cleared.id, 'a');
      expect(cleared.scope, AiMemoryScope.global);
      expect(cleared.updatedAt, 2);
    });
  });

  group('add / list 增查（AI-MEM-002）', () {
    test('新增全局记忆：字段完整、listGlobal 新→旧', () async {
      final item = await service.add(
        scope: AiMemoryScope.global,
        subject: ' orders.status ',
        content: 'canonical status flow',
      );
      expect(item.id, startsWith('mem_'));
      expect(item.scope, AiMemoryScope.global);
      expect(item.connectionId, isNull);
      expect(item.subject, 'orders.status'); // 去首尾空白
      expect(item.source, AiMemorySource.manual); // 默认 manual
      expect(item.createdAt, greaterThan(0));
      expect(item.updatedAt, item.createdAt);

      expect(service.listGlobal(), hasLength(1));
      expect(service.listGlobal().first.id, item.id);
    });

    test('连接记忆写入独立作用域，与全局互不可见（分键隔离）', () async {
      await service.add(scope: AiMemoryScope.global, content: 'global fact');
      await service.add(
        scope: AiMemoryScope.connection,
        connectionId: 'conn_1',
        content: 'conn fact',
      );

      expect(service.listForConnection('conn_1'), hasLength(1));
      expect(service.listForConnection('conn_1').first.content, 'conn fact');
      expect(service.listGlobal().first.content, 'global fact');
      expect(service.listForConnection('conn_other'), isEmpty);
    });

    test('连接作用域缺 connectionId 抛 ArgumentError', () async {
      expect(
        () => service.add(scope: AiMemoryScope.connection, content: 'x'),
        throwsArgumentError,
      );
      expect(
        () => service.add(
          scope: AiMemoryScope.connection,
          connectionId: '  ',
          content: 'x',
        ),
        throwsArgumentError,
      );
    });

    test('空白 content 抛 ArgumentError；global 忽略传入的 connectionId', () async {
      expect(
        () => service.add(scope: AiMemoryScope.global, content: '   '),
        throwsArgumentError,
      );
      final item = await service.add(
        scope: AiMemoryScope.global,
        connectionId: 'conn_1',
        content: 'x',
      );
      expect(item.connectionId, isNull);
    });
  });

  group('update / remove / clearForConnection（AI-MEM-003）', () {
    test('update 修改内容并刷新 updatedAt（基于受控种子时间戳）', () async {
      await seedScope('ai_memory_global', [
        AiMemoryItem(
          id: 'm1',
          scope: AiMemoryScope.global,
          subject: 'orders.status',
          content: 'old',
          createdAt: 1000,
          updatedAt: 1000,
        ),
      ]);
      final stored = service.listGlobal().first;
      final ok = await service.update(
        stored.copyWith(content: '  new content  ', subject: '  '),
      );
      expect(ok, isTrue);

      final updated = service.listGlobal().first;
      expect(updated.content, 'new content'); // trim + 保留
      expect(updated.subject, isNull); // 空白 subject 规范化为 null
      expect(updated.updatedAt, greaterThan(1000)); // 刷新
      expect(updated.createdAt, 1000); // 创建时间不变
    });

    test('update 未知条目返回 false；空白 content 抛 ArgumentError', () async {
      final ghost = AiMemoryItem(
        id: 'nope',
        scope: AiMemoryScope.global,
        content: 'x',
        createdAt: 1,
        updatedAt: 1,
      );
      expect(await service.update(ghost), isFalse);
      expect(
        () => service.update(ghost.copyWith(content: ' ')),
        throwsArgumentError,
      );
    });

    test('remove 按 id 删除，二次删除返回 false', () async {
      final item = await service.add(
        scope: AiMemoryScope.global,
        content: 'to remove',
      );
      expect(await service.remove(item), isTrue);
      expect(service.listGlobal(), isEmpty);
      expect(await service.remove(item), isFalse);
    });

    test('clearForConnection 只清目标连接，其它作用域不受影响', () async {
      await service.add(
        scope: AiMemoryScope.connection,
        connectionId: 'conn_a',
        content: 'a rule',
      );
      await service.add(
        scope: AiMemoryScope.connection,
        connectionId: 'conn_b',
        content: 'b rule',
      );
      await service.add(scope: AiMemoryScope.global, content: 'global rule');

      await service.clearForConnection('conn_a');

      expect(service.listForConnection('conn_a'), isEmpty);
      expect(service.listForConnection('conn_b'), hasLength(1));
      expect(service.listGlobal(), hasLength(1));
      // 持久化键也一并移除（flush 由 clearForConnection 内部完成）。
      final p = await prefs();
      expect(p.getString('ai_memory_conn_conn_a'), isNull);
      expect(p.getString('ai_memory_conn_conn_b'), isNotNull);
    });
  });

  group('容量与截断纪律（AI-MEM-004/005）', () {
    test('单作用域超 200 条按 updatedAt 淘汰最旧', () async {
      // 种子 200 条，updatedAt = 1000..1199（最旧 = 1000）。
      final seeds = List<AiMemoryItem>.generate(200, (i) {
        return AiMemoryItem(
          id: 'seed_$i',
          scope: AiMemoryScope.global,
          content: 'c$i',
          createdAt: 1000 + i,
          updatedAt: 1000 + i,
        );
      });
      await seedScope('ai_memory_global', seeds);
      expect(service.listGlobal(), hasLength(200));

      await service.add(scope: AiMemoryScope.global, content: 'newest');

      final items = service.listGlobal();
      expect(items, hasLength(200));
      expect(items.any((m) => m.id == 'seed_0'), isFalse); // updatedAt 最旧被淘汰
      expect(items.any((m) => m.id == 'seed_1'), isTrue);
      expect(items.any((m) => m.content == 'newest'), isTrue);

      await service.flush();
      final p = await prefs();
      final persisted = jsonDecode(p.getString('ai_memory_global') ?? '[]');
      expect(persisted, hasLength(200));
    });

    test('content 截断到 500 字符', () async {
      final item = await service.add(
        scope: AiMemoryScope.global,
        content: 'x' * 600,
      );
      expect(item.content.length, 500);
      expect(item.content, 'x' * 500);
    });
  });

  group('防抖落盘（AI-MEM-006）', () {
    test('防抖窗口内不落盘，窗口后自动落盘', () async {
      await service.add(scope: AiMemoryScope.global, content: 'delayed');
      var p = await prefs();
      expect(p.getString('ai_memory_global'), isNull); // 窗口内未落盘

      await Future<void>.delayed(const Duration(milliseconds: 450));
      p = await prefs();
      final persisted = jsonDecode(p.getString('ai_memory_global') ?? '[]');
      expect(persisted, hasLength(1)); // 窗口后防抖定时器自动落盘
    });

    test('flush() 立即落盘且连接分键各写各的（写入防抖合并）', () async {
      await service.add(scope: AiMemoryScope.global, content: 'g');
      await service.add(scope: AiMemoryScope.global, content: 'g2');
      await service.add(
        scope: AiMemoryScope.connection,
        connectionId: 'conn_1',
        content: 'c1',
      );
      await service.flush();

      final p = await prefs();
      final globalItems =
          jsonDecode(p.getString('ai_memory_global') ?? '[]') as List<dynamic>;
      final connItems =
          jsonDecode(p.getString('ai_memory_conn_conn_1') ?? '[]')
              as List<dynamic>;
      expect(globalItems, hasLength(2));
      expect(connItems, hasLength(1));
      expect((connItems.first as Map<String, dynamic>)['content'], 'c1');
      // 分键隔离：全局键里没有连接记忆的内容。
      expect(p.getString('ai_memory_global'), isNot(contains('c1')));
    });
  });

  group('forTable 匹配（AI-MEM-007）', () {
    test('subject 前缀/包含命中，大小写不敏感，空 subject 不参与', () async {
      await service.add(
        scope: AiMemoryScope.global,
        subject: 'orders.status',
        content: 'prefix hit',
      );
      await service.add(
        scope: AiMemoryScope.global,
        subject: 'myorders.theme',
        content: 'contains hit',
      );
      await service.add(
        scope: AiMemoryScope.global,
        subject: 'user.prefs',
        content: 'miss',
      );
      await service.add(scope: AiMemoryScope.global, content: 'no subject');

      final hits = service.forTable('orders');
      expect(hits, hasLength(2));
      expect(
        hits.map((m) => m.content),
        containsAll(['prefix hit', 'contains hit']),
      );

      // 大小写不敏感。
      expect(service.forTable('ORDERS'), hasLength(2));
      // 空表名返回空。
      expect(service.forTable('  '), isEmpty);
      // 无命中表名。
      expect(service.forTable('payments'), isEmpty);
    });

    test('传 connectionId 时合并连接作用域命中', () async {
      await service.add(
        scope: AiMemoryScope.global,
        subject: 'orders.status',
        content: 'global hit',
      );
      await service.add(
        scope: AiMemoryScope.connection,
        connectionId: 'conn_1',
        subject: 'orders.audit',
        content: 'conn hit',
      );
      await service.add(
        scope: AiMemoryScope.connection,
        connectionId: 'conn_2',
        subject: 'orders.other',
        content: 'other conn hit',
      );

      final merged = service.forTable('orders', connectionId: 'conn_1');
      expect(merged, hasLength(2));
      expect(
        merged.map((m) => m.content),
        containsAll(['global hit', 'conn hit']),
      );
      // 不传 connectionId 只搜全局。
      expect(service.forTable('orders'), hasLength(1));
    });
  });

  group('初始化与重载（AI-MEM-008）', () {
    test('initialize 幂等：重复调用不重复加载', () async {
      await service.add(scope: AiMemoryScope.global, content: 'once');
      await service.flush();

      await service.initialize();
      await service.initialize();
      expect(service.listGlobal(), hasLength(1));
    });

    test('重置后重新 initialize 从 prefs 重载（含连接分键扫描）', () async {
      await service.add(
        scope: AiMemoryScope.connection,
        connectionId: 'conn_9',
        content: 'persisted conn',
      );
      await service.flush();

      service.resetForTesting();
      expect(service.listGlobal(), isEmpty);
      await service.initialize();

      expect(service.listForConnection('conn_9'), hasLength(1));
      expect(
        service.listForConnection('conn_9').first.content,
        'persisted conn',
      );
    });
  });
}
