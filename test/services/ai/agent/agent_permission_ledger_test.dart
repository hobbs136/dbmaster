// AgentPermissionLedger 单测（T06 / design D12）。
//
// 覆盖：记录与只读查询（两集分立）、空串不可成为放行键、只读视图不可
// 变更、失效三路径（会话切换 / lockWorkbenchContext 变更 / 应用重启 =
// 对象消亡不持久化）、跨 run 保留（同会话多次运行共享放行）。
//
// L2 无集合 = 结构上不可表达（AC10.3）——本文件断言账本只存在 L0.5 与
// L1 两个放行面（无任何 L2 入口）。

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/ai/agent/agent_permission_ledger.dart';

void main() {
  group('记录与只读查询（D12：两集分立，key = connectionId）', () {
    test('初始态：两集皆空，任意 contains 为 false', () {
      final ledger = AgentPermissionLedger();
      expect(ledger.l05Allowed, isEmpty);
      expect(ledger.l1Allowed, isEmpty);
      expect(ledger.l05Allowed.contains('conn-a'), isFalse);
      expect(ledger.l1Allowed.contains('conn-a'), isFalse);
    });

    test('allowL05 / allowL1 各自记录，两集互不串扰', () {
      final ledger = AgentPermissionLedger()
        ..allowL05('conn-a')
        ..allowL1('conn-b');
      expect(ledger.l05Allowed.contains('conn-a'), isTrue);
      expect(
        ledger.l05Allowed.contains('conn-b'),
        isFalse,
        reason: 'L1 放行不落入 L0.5 集',
      );
      expect(ledger.l1Allowed.contains('conn-b'), isTrue);
      expect(
        ledger.l1Allowed.contains('conn-a'),
        isFalse,
        reason: 'L0.5 放行不落入 L1 集',
      );
    });

    test('空串 connectionId 不记录（无上下文占位不可成为放行键，T07 语义）', () {
      final ledger = AgentPermissionLedger()
        ..allowL05('')
        ..allowL1('');
      expect(ledger.l05Allowed, isEmpty);
      expect(ledger.l1Allowed, isEmpty);
    });

    test('只读视图不可被外部变更（变更只走 allowL05/allowL1/clearAll）', () {
      final ledger = AgentPermissionLedger()..allowL05('conn-a');
      expect(() => ledger.l05Allowed.add('conn-x'), throwsUnsupportedError);
      expect(() => ledger.l05Allowed.remove('conn-a'), throwsUnsupportedError);
      expect(() => ledger.l1Allowed.clear(), throwsUnsupportedError);
      expect(ledger.l05Allowed, unorderedEquals(<String>['conn-a']));
    });
  });

  group('失效三路径（D12）', () {
    test('路径一 会话切换：接线方（runner，T14）调 clearAll → 两集皆空', () {
      final ledger = AgentPermissionLedger()
        ..allowL05('conn-a')
        ..allowL1('conn-b');
      ledger.clearAll();
      expect(ledger.l05Allowed, isEmpty);
      expect(ledger.l1Allowed, isEmpty);
    });

    test('路径二 lockWorkbenchContext 变更：同一 clearAll 入口 → 两集皆空', () {
      final ledger = AgentPermissionLedger()
        ..allowL05('conn-a')
        ..allowL1('conn-a');
      ledger.clearAll();
      expect(ledger.l05Allowed, isEmpty);
      expect(ledger.l1Allowed, isEmpty);
    });

    test('路径三 应用重启：新实例为空（内存态不持久化，无任何存储面）', () {
      final old = AgentPermissionLedger()
        ..allowL05('conn-a')
        ..allowL1('conn-a');
      final fresh = AgentPermissionLedger();
      expect(fresh.l05Allowed, isEmpty);
      expect(fresh.l1Allowed, isEmpty);
      expect(
        old.l05Allowed.contains('conn-a'),
        isTrue,
        reason: '重启语义 = 进程内对象消亡，而非写穿到新实例；旧实例在同会话内仍有效',
      );
    });
  });

  group('跨 run 保留（D12：同一会话内放行对后续运行仍生效）', () {
    test('grant 一次，两次判定消费（gate evaluate ⑤ 的 contains 用法）均命中', () {
      final ledger = AgentPermissionLedger()..allowL05('conn-a');
      // design §4.2 ⑤ 原文消费形态：ledger.l05Allowed.contains(connectionId)。
      for (var round = 1; round <= 2; round++) {
        expect(
          ledger.l05Allowed.contains('conn-a'),
          isTrue,
          reason: '第 $round 轮 run 判定',
        );
      }
    });
  });
}
