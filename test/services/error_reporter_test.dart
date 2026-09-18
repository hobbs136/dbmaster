import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/error_event.dart';
import 'package:dbmaster/providers/execution_center_provider.dart';
import 'package:dbmaster/services/error_reporter.dart';

void main() {
  late ExecutionCenterProvider center;

  setUp(() {
    center = ExecutionCenterProvider();
    ErrorReporter.instance.attach(center);
  });

  tearDown(() {
    ErrorReporter.instance.detach();
  });

  test('report pushes to attached center and returns the event', () {
    final ev = ErrorReporter.instance.report(
      Exception('boom'),
      tag: 'Test',
      sql: 'SELECT password=secret FROM t',
    );
    expect(center.errors.single, same(ev));
    expect(ev.severity, ErrorSeverity.error);
    expect(ev.message, contains('boom'));
    // 密钥在 SQL 里，message 本身无密钥 → messageForLog 不变；messageForAi 含脱敏 SQL。
    expect(ev.messageForLog, 'Exception: boom');
    expect(ev.messageForAi, contains('***'));
  });

  test('dedupes the same object within the window', () {
    final err = Exception('once');
    ErrorReporter.instance.report(err);
    ErrorReporter.instance.report(err);
    expect(center.errors.length, 1);
  });

  test('different errors are both recorded', () {
    ErrorReporter.instance.report(Exception('a'));
    ErrorReporter.instance.report(Exception('b'));
    expect(center.errors.length, 2);
  });

  test('detach stops pushing', () {
    ErrorReporter.instance.detach();
    ErrorReporter.instance.report(Exception('x'));
    expect(center.errors, isEmpty);
  });

  // ── 防级联（导出后灰屏事故 2026-08-17）──

  test('listener exception does not escape and does not recurse', () {
    // 模拟事故形态：执行中心的监听器在 notifyListeners 时抛错——
    // 若异常逃逸到全局钩子会构成 report 自反馈环（UI 线程无限循环）。
    var listenerCalls = 0;
    void badListener() {
      listenerCalls++;
      throw Exception('listener blew up');
    }
    center.addListener(badListener);
    addTearDown(() => center.removeListener(badListener));

    // 不应抛出（监听器异常被就地吞掉）。
    ErrorReporter.instance.report(Exception('first error'));

    expect(listenerCalls, 1);
    expect(center.errors, isNotEmpty);
  });

  test('re-entrant report during notification is dropped (cascade guard)', () {
    // 事故形态推演：监听器抛错 → 全局钩子 → 再次 report（notify 期间）。
    // 若无重入闸，addError → notify → 又 report → 无限循环。
    var depth = 0;
    void recursiveListener() {
      depth++;
      if (depth < 5) {
        ErrorReporter.instance.report(Exception('cascade level $depth'));
      }
    }
    center.addListener(recursiveListener);
    addTearDown(() => center.removeListener(recursiveListener));

    ErrorReporter.instance.report(Exception('root cause'));

    // 根错误入中心一次；notify 期间的重入全部被丢弃。
    expect(center.errors.length, 1);
  });

  test('flood cap drops errors beyond 20 per second', () {
    for (var i = 0; i < 30; i++) {
      ErrorReporter.instance.report(Exception('flood $i'));
    }
    // 30 个互异异常 → 洪水上限 20/s 兜底截断（防报错风暴撑爆 UI/内存）。
    expect(center.errors.length, 20);
  });
}
