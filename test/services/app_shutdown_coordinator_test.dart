// =============================================================================
// Unit tests for AppShutdownCoordinator (sleep-resume-fix batch T2, design D1).
// =============================================================================
// The coordinator owns the window-close teardown sequence: three cleanup steps
// (embedded server stop / clean-exit mark / logger dispose) run in order under
// one overall deadline, and the window-release closure runs unconditionally
// afterwards — on ANY path (step throws / step hangs / deadline fires) and
// never covered by the deadline itself.
//
// Test IDs SVC-SHUT-001..004 are pre-allocated in docs/test/
// unified_test_spec.md (registered by batch task T9).
//
// The coordinator is a pure-logic service (no material/widgets imports), so
// non-timer paths run in plain `test()`; deadline timing runs in `testWidgets`
// — flutter_test's own fake-async zone (timers fire via tester.pump) — which
// keeps the direct fake_async dependency out of pubspec.
// =============================================================================

import 'dart:async';

import 'package:dbmaster/services/app_shutdown_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const coordinator = AppShutdownCoordinator();

  group('SVC-SHUT-001 normal path', () {
    test('runs the four steps in order and releases exactly once', () async {
      final calls = <String>[];
      var releaseCount = 0;
      final outcome = await coordinator.run(
        stopEmbeddedServer: () async {
          calls.add('stop');
        },
        prepareCleanExit: () async {
          calls.add('cleanExit');
        },
        disposeLogger: () async {
          calls.add('dispose');
        },
        releaseWindowClose: () async {
          releaseCount++;
          calls.add('release');
        },
      );

      expect(calls, ['stop', 'cleanExit', 'dispose', 'release']);
      expect(releaseCount, 1);
      expect(outcome, ShutdownOutcome.normal);
    });
  });

  group('SVC-SHUT-002 step failures are isolated', () {
    test('a failure in each cleanup step still runs later steps and releases',
        () async {
      for (final failing in <String>['stop', 'cleanExit', 'dispose']) {
        final calls = <String>[];
        var releaseCount = 0;
        final outcome = await coordinator.run(
          stopEmbeddedServer: () async {
            calls.add('stop');
            if (failing == 'stop') throw StateError('stop failed');
          },
          prepareCleanExit: () async {
            calls.add('cleanExit');
            if (failing == 'cleanExit') throw StateError('cleanExit failed');
          },
          disposeLogger: () async {
            calls.add('dispose');
            if (failing == 'dispose') throw StateError('dispose failed');
          },
          releaseWindowClose: () async {
            releaseCount++;
            calls.add('release');
          },
        );

        expect(calls, ['stop', 'cleanExit', 'dispose', 'release'],
            reason: 'failing step: $failing — later steps must still run');
        expect(releaseCount, 1, reason: 'failing step: $failing');
        expect(outcome, ShutdownOutcome.stepFailed,
            reason: 'failing step: $failing');
      }
    });
  });

  group('SVC-SHUT-003 hung step is cut by the deadline', () {
    testWidgets('release still runs within the injected deadline',
        (tester) async {
      final calls = <String>[];
      final hang = Completer<void>();
      ShutdownOutcome? outcome;
      const deadline = Duration(seconds: 2);

      final done = coordinator
          .run(
            stopEmbeddedServer: () async {
              calls.add('stop');
            },
            prepareCleanExit: () async {
              calls.add('cleanExit');
            },
            disposeLogger: () => hang.future,
            releaseWindowClose: () async {
              calls.add('release');
            },
            deadline: deadline,
          )
          .then((value) {
            outcome = value;
            calls.add('done');
          });

      // 前两步是纯微任务，排空后应已执行；dispose 仍挂起。
      await tester.idle();
      expect(calls, ['stop', 'cleanExit']);

      // deadline 到点：超时分支触发，强制放行。
      await tester.pump(deadline);
      await done;

      expect(calls, ['stop', 'cleanExit', 'release', 'done']);
      expect(outcome, ShutdownOutcome.timedOut);
    });
  });

  group('SVC-SHUT-004 release is unconditional', () {
    test('a throwing release does not propagate', () async {
      var releaseCount = 0;
      final outcome = await coordinator.run(
        stopEmbeddedServer: () async {},
        prepareCleanExit: () async {},
        disposeLogger: () async {},
        releaseWindowClose: () async {
          releaseCount++;
          throw StateError('release failed');
        },
      );

      expect(releaseCount, 1);
      expect(outcome, ShutdownOutcome.normal);
    });

    testWidgets(
        'release is not covered by the deadline: it runs after the timeout '
        'even when it throws', (tester) async {
      final calls = <String>[];
      var releaseCount = 0;
      final hang = Completer<void>();
      const deadline = Duration(milliseconds: 100);

      final done = coordinator
          .run(
            stopEmbeddedServer: () async {
              calls.add('stop');
            },
            prepareCleanExit: () async {
              calls.add('cleanExit');
            },
            disposeLogger: () => hang.future,
            releaseWindowClose: () async {
              releaseCount++;
              calls.add('release');
              throw StateError('release failed');
            },
            deadline: deadline,
          )
          .then((_) => calls.add('done'));

      await tester.idle();
      await tester.pump(deadline);
      await done;

      // 不变量：超时路径 release 也必达且恰好一次；release 抛出的异常被
      // 协调器吞掉（run 正常结算，done 被记录）。
      expect(calls, ['stop', 'cleanExit', 'release', 'done']);
      expect(releaseCount, 1);
    });
  });
}
