// =============================================================================
// Unit tests for AppLifecycleObserver (sleep-resume-fix batch T8, design D6).
// =============================================================================
// The observer logs every app lifecycle transition and fires one server probe
// on `resumed` (fire-and-forget: a hanging probe must not block the lifecycle
// callback; a throwing/failing probe must be swallowed with a log line). The
// class itself is the WidgetsBindingObserver, exposing attach/detach so the
// registration lifecycle is assertable WITHOUT importing main.dart (§0
// MUST NOT #7) — the mount widget in main.dart only calls attach/detach.
//
// Test IDs UI-LIFE-001..003 are pre-allocated in docs/test/
// unified_test_spec.md (registered by batch task T9).
//
// D7 ruling is intentionally NOT implemented here (no active cleanup of hung
// requests / no forced reconnects) — bounded self-healing comes from the
// batch's timeout + single-flight guards; evidence-driven follow-up only.
// =============================================================================

import 'dart:async';

import 'package:dbmaster/services/app_lifecycle_observer.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, SizedBox;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UI-LIFE-001 every transition is logged; probe fires on resumed only',
      () {
    test('logs one line per transition in order', () async {
      final logs = <String>[];
      var probeCount = 0;
      final observer = AppLifecycleObserver(
        probe: () async {
          probeCount++;
          return true;
        },
        onLog: logs.add,
      );

      observer.handle(AppLifecycleState.inactive);
      observer.handle(AppLifecycleState.paused);
      observer.handle(AppLifecycleState.hidden);
      observer.handle(AppLifecycleState.detached);
      observer.handle(AppLifecycleState.resumed);
      // 探活是 fire-and-forget 的 future,排空微任务让 then 回调落地。
      await Future<void>.delayed(Duration.zero);

      expect(logs, [
        'state → inactive',
        'state → paused',
        'state → hidden',
        'state → detached',
        'state → resumed',
        'post-resume server probe: ok',
      ]);
      expect(probeCount, 1, reason: '仅 resumed 触发一次探活');
    });

    test('paused / inactive / hidden / detached never trigger the probe',
        () async {
      final logs = <String>[];
      var probeCount = 0;
      final observer = AppLifecycleObserver(
        probe: () async {
          probeCount++;
          return true;
        },
        onLog: logs.add,
      );

      for (final state in AppLifecycleState.values) {
        if (state == AppLifecycleState.resumed) continue;
        observer.handle(state);
      }
      await Future<void>.delayed(Duration.zero);

      expect(probeCount, 0,
          reason: 'D6/D7: 探活仅在 resumed 触发,paused 等状态只打点');
      expect(logs.length, AppLifecycleState.values.length - 1);
      expect(logs.any((l) => l.startsWith('post-resume')), isFalse);
    });
  });

  group('UI-LIFE-002 probe failures never escape the lifecycle callback', () {
    test('probe returning false logs failed and does not throw', () async {
      final logs = <String>[];
      final observer = AppLifecycleObserver(
        probe: () async => false,
        onLog: logs.add,
      );

      expect(
        () => observer.handle(AppLifecycleState.resumed),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);

      expect(logs, contains('post-resume server probe: failed'));
    });

    test('a synchronously throwing probe is contained', () async {
      final logs = <String>[];
      final observer = AppLifecycleObserver(
        probe: () => throw StateError('sync boom'),
        onLog: logs.add,
      );

      expect(
        () => observer.handle(AppLifecycleState.resumed),
        returnsNormally,
        reason: 'Future.sync 把同步抛错折进 failed future,不外溢 handle',
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        logs,
        contains('post-resume server probe threw: Bad state: sync boom'),
      );
    });

    test('an asynchronously failing probe is contained', () async {
      final logs = <String>[];
      final observer = AppLifecycleObserver(
        probe: () async => throw StateError('async boom'),
        onLog: logs.add,
      );

      observer.handle(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(
        logs.any((l) => l.startsWith('post-resume server probe threw')),
        isTrue,
      );
    });

    test('a hanging probe does not block the lifecycle callback', () async {
      final probe = Completer<bool>();
      var probeCount = 0;
      final logs = <String>[];
      final observer = AppLifecycleObserver(
        probe: () {
          probeCount++;
          return probe.future;
        },
        onLog: logs.add,
      );

      observer.handle(AppLifecycleState.resumed);
      expect(probeCount, 1, reason: 'handle 同步返回时探活已发起(不等待)');
      expect(logs, ['state → resumed'],
          reason: 'probe 未结算,不得有 probe 结果日志');

      // 稍后结算也不得产生未处理异步错误(flutter_test 会把 zone 内未处理
      // 错误判为测试失败,这里能走完即证明 onError 兜住了)。
      probe.complete(false);
      await Future<void>.delayed(Duration.zero);
      expect(logs, contains('post-resume server probe: failed'));
    });
  });

  group('UI-LIFE-003 attach routes binding events; detach removes the observer',
      () {
    testWidgets(
        'binding dispatch reaches handle after attach and stops after detach '
        '(leak guard for the main.dart mount widget dispose)', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final logs = <String>[];
      var probeCount = 0;
      final observer = AppLifecycleObserver(
        probe: () async {
          probeCount++;
          return true;
        },
        onLog: logs.add,
      );

      observer.attach();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(logs, containsAll(<String>['state → inactive', 'state → paused']));
      expect(probeCount, 0, reason: 'paused 不得触发探活');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(probeCount, 1, reason: 'resumed 经 binding 派发进 handle 并探活');

      // 防泄漏断言:detach 之后 binding 不再派发给本观察者——main.dart 的
      // 挂载 widget 在 dispose 调 detach,泄漏即「dispose 后仍收事件」。
      logs.clear();
      observer.detach();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(logs, isEmpty, reason: 'detach 后不得再收到任何 lifecycle 事件');
      expect(probeCount, 1);
    });
  });
}
