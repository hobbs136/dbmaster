// spec 040 Phase 2.3 — ShortcutBindings parity guard.
// Locks the dialog's single source (shortcutBindings) against drift from the
// real global handler: no phantom entries (shown-but-not-handled, like the old
// Ctrl+Enter) and no omissions (handled-but-not-shown, like the old missing
// Ctrl+K/Ctrl+Shift+G/Ctrl+Shift+L/Ctrl+,/Ctrl±).
//
// `globalHandled` mirrors GlobalShortcutsWrapper._handleKeyEvent's recognized
// combos — keep it in sync when editing the if-chain.
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/core/shortcuts/shortcut_bindings.dart';

/// GlobalShortcutsWrapper._handleKeyEvent 实际处理的 (control|shift|key) 集合。
/// 改 if-chain 时须同步更新此处。
const globalHandled = <String>{
  'true|false|T', // Ctrl+T  New Tab
  'true|false|W', // Ctrl+W  Close Tab
  'true|false|Tab', // Ctrl+Tab  Next Tab
  'true|true|Tab', // Ctrl+Shift+Tab  Prev Tab
  'true|true|A', // Ctrl+Shift+A  Toggle AI
  'true|true|P', // Ctrl+Shift+P  Command Palette
  'true|false|K', // Ctrl+K  Quick Search
  'true|false|/', // Ctrl+/  Shortcut Help
  'true|false|S', // Ctrl+S  Save (fallback)
  'true|true|F', // Ctrl+Shift+F  Format (fallback)
  'true|true|G', // Ctrl+Shift+G  AI Fullscreen
  'true|true|L', // Ctrl+Shift+L  Audit Log
  'true|false|,', // Ctrl+,  Settings
  'true|false|=', // Ctrl+=  Increase Opacity
  'true|false|-', // Ctrl+-  Decrease Opacity
  'false|false|F5', // F5  Execute (fallback)
};

String _combo(ShortcutBinding b) => '${b.control}|${b.shift}|${b.key}';

void main() {
  final l10n = AppLocalizationsEn();

  group('shortcutBindings parity (spec 040 Phase 2.3)', () {
    test('每条 binding 有非空 label 与 category', () {
      for (final b in shortcutBindings) {
        expect(b.label(l10n), isNotEmpty, reason: '空 label: ${_combo(b)}');
        expect(b.category(l10n), isNotEmpty, reason: '空 category: ${_combo(b)}');
      }
    });

    test('无重复 (control, shift, key, scope) 组合', () {
      final seen = <String>{};
      for (final b in shortcutBindings) {
        final id = '${_combo(b)}|${b.scope}';
        expect(seen, isNot(contains(id)), reason: '重复快捷键组合: $id');
        seen.add(id);
      }
    });

    test('全局 binding 均对应真实全局处理器（无幽灵条目）', () {
      for (final b in shortcutBindings) {
        if (b.scope != ShortcutScope.global) continue;
        expect(
          globalHandled,
          contains(_combo(b)),
          reason: '全局 binding 无对应处理器（幽灵条目）: ${b.label(l10n)} (${_combo(b)})',
        );
      }
    });

    test('全局处理器键集均在 bindings 展示（无遗漏）', () {
      final shown = shortcutBindings
          .where((b) => b.scope == ShortcutScope.global)
          .map(_combo)
          .toSet();
      for (final id in globalHandled) {
        expect(shown, contains(id), reason: '全局处理器未在 bindings 展示: $id');
      }
    });
  });
}
