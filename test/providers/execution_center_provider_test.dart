import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/error_event.dart';
import 'package:dbmaster/providers/execution_center_provider.dart';

ErrorEvent _ev(String id) => ErrorEvent(
      id: id,
      timestamp: DateTime.now(),
      severity: ErrorSeverity.error,
      message: 'err $id',
    );

void main() {
  test('addError inserts newest first; LRU caps at maxErrors', () {
    final p = ExecutionCenterProvider();
    final total = ExecutionCenterProvider.maxErrors + 5;
    for (var i = 0; i < total; i++) {
      p.addError(_ev('e$i'));
    }
    expect(p.errors.length, ExecutionCenterProvider.maxErrors);
    expect(p.errors.first.id, 'e${total - 1}');
  });

  test('dismissError removes by id', () {
    final p = ExecutionCenterProvider();
    p.addError(_ev('a'));
    p.addError(_ev('b'));
    p.dismissError('a');
    expect(p.errors.map((e) => e.id), ['b']);
  });

  test('clearErrors empties the list', () {
    final p = ExecutionCenterProvider();
    p.addError(_ev('a'));
    p.clearErrors();
    expect(p.errors, isEmpty);
  });

  test('toggle flips isOpen and notifies listeners', () {
    final p = ExecutionCenterProvider();
    var notified = 0;
    p.addListener(() => notified++);
    expect(p.isOpen, isFalse);
    p.toggle();
    expect(p.isOpen, isTrue);
    p.toggle();
    expect(p.isOpen, isFalse);
    expect(notified, 2);
  });
}
