// spec 040 Phase 2.2 — editor focus-state tracking (double-trigger guard).
// Locks the register/unregister/isSqlEditorFocused logic that lets the global
// HardwareKeyboard handler defer F5/Ctrl+S/Ctrl+Shift+F to the editor when it
// holds primary focus.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/core/shortcuts/editor_focus_state.dart';

void main() {
  testWidgets('isSqlEditorFocused 反映已注册焦点节点是否持主焦', (tester) async {
    // 无注册 / 未持焦 → false
    expect(isSqlEditorFocused, isFalse);

    final node = FocusNode();
    registerEditorFocusNode(node);
    expect(isSqlEditorFocused, isFalse); // 注册但未持主焦

    // 持主焦 → true
    await tester.pumpWidget(
      Focus(focusNode: node, autofocus: true, child: const SizedBox()),
    );
    await tester.pump();
    expect(node.hasFocus, isTrue);
    expect(isSqlEditorFocused, isTrue);

    // 注销 → false（即便仍持焦，已不在注册集合）
    unregisterEditorFocusNode(node);
    expect(isSqlEditorFocused, isFalse);

    node.dispose();
  });

  test('register/unregister 幂等且不抛', () {
    final a = FocusNode();
    final b = FocusNode();
    registerEditorFocusNode(a);
    registerEditorFocusNode(a); // 重复注册幂等
    registerEditorFocusNode(b);
    unregisterEditorFocusNode(a);
    unregisterEditorFocusNode(a); // 重复注销幂等
    unregisterEditorFocusNode(b);
    a.dispose();
    b.dispose();
  });
}
