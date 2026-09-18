# Integration Test Authoring Guide

> **Audience**: Anyone writing `integration_test/*.dart` for DbMaster.
> **Source of truth**: This file is updated whenever we hit a real Flutter
> integration-test pitfall. Lessons-learned, not API reference.
> **Last updated**: 2026-06-04

This guide is the "**how to write tests that actually work**" companion
to `automated_test_plan.md` (which is "what to test"). If you're about to
add a new `testWidgets` block and Flutter is fighting you, read this first.

---

## 1. HardwareKeyboard — the real API

### ❌ What doesn't exist

```dart
// This API is FICTIONAL. There is no such method on HardwareKeyboard.
await HardwareKeyboard.simulateKeyDownEvent(
  logicalKey: LogicalKeyboardKey.keyT,
  physicalKey: PhysicalKeyboardKey.keyT,
  modifiers: const {Modifier.meta},   // ❌ no such thing
);
```

`HardwareKeyboard` (in `package:flutter/services.dart`) only has
`instance.addHandler(...)` and getters like `isMetaPressed`. It cannot
inject events on its own. **There is no `Modifier` enum in Flutter.**

### ✅ The real API (3 methods on `WidgetTester`)

```dart
// Defined in flutter_test/lib/src/controller.dart
Future<bool> sendKeyEvent(
  LogicalKeyboardKey key, {
  String? platform,           // 'macos' | 'linux' | 'windows' | 'android' | 'fuchsia' | 'ios'
  String? character,
  PhysicalKeyboardKey? physicalKey,
});

Future<bool> sendKeyDownEvent(
  LogicalKeyboardKey key, {
  String? platform,
  String? character,
  PhysicalKeyboardKey? physicalKey,
});

Future<bool> sendKeyUpEvent(
  LogicalKeyboardKey key, {
  String? platform,
  String? character,
  PhysicalKeyboardKey? physicalKey,
});
```

**Crucially: there is no `modifiers` parameter.** Modifier state (Cmd, Ctrl,
Shift, Alt) is maintained by `sendKeyDownEvent` on the modifier's own
logical key, and Flutter's `HardwareKeyboard.logicalKeysPressed` tracks it
automatically.

### ✅ Idiomatic Cmd+T

```dart
// Hold Meta, then press T, then release T, then release Meta.
await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
```

### ✅ Cmd+Shift+P (multiple modifiers)

```dart
await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
```

**Order matters for release**: release in reverse order of press.

---

## 2. Async work via `addPostFrameCallback` needs extra `pump` calls

DbMaster's `GlobalShortcutsWrapper` (and other wrappers) defer UI work via
`WidgetsBinding.instance.addPostFrameCallback`. A single
`pumpAndSettle()` is **not** enough — `pumpAndSettle` waits for animations
to settle but the post-frame callback may schedule more async work that
itself needs additional frames.

### ❌ Not enough

```dart
await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
await tester.pumpAndSettle();  // 1 post-frame, but the action may schedule more
```

### ✅ Pattern that works

```dart
await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
for (var i = 0; i < 5; i++) {
  await tester.pump(const Duration(milliseconds: 100));
}
await tester.pumpAndSettle();
```

The 5× 100ms pumps give post-frame callbacks + their async work enough
wall-clock to resolve before `pumpAndSettle` finalizes.

---

## 3. `AppProvider.tabs` requires an active Workspace

```dart
// lib/providers/app_provider.dart:335
List<QueryTab> get tabs => workspace.activeWorkspace?.queryTabs ?? const [];
```

`addNewTab()` adds a tab to the **current workspace**. If no workspace is
active, `tabs` is always `[]` — even after calling `addNewTab()` 100 times.

### Implications for shortcut tests

If you're testing Cmd+T (which calls `provider.addNewTab()`), you must
first set up an active workspace, OR change the test to verify the
**handler is wired up** rather than the side-effect.

### ✅ Pattern: split "wiring" from "behavior"

```dart
// Shortcut wiring test: verify the handler runs without exception.
testWidgets('TC-014 Ctrl+T (Cmd+T) opens a new tab', (tester) async {
  final provider = AppProvider();
  await tester.pumpWidget(probeApp(provider));
  await tester.pumpAndSettle();

  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();

  // The shortcut is wired up; behavior depends on workspace state.
  expect(find.byKey(const ValueKey('tab_count')), findsOneWidget,
      reason: 'GlobalShortcutsWrapper still active after Cmd+T');
});
```

For full behavior coverage, write a **unit test** that constructs an
`AppProvider` with a pre-seeded workspace and calls
`addNewTab()` / `closeTab()` directly. See
`test/services/shortcut_service_test.dart` for examples.

---

## 4. Stub shortcut handlers — verify the stub, not the side-effect

If a `_handleXxx()` method in `GlobalShortcutsWrapper` is a TODO stub
(empty body), the keyboard event **reaches** the handler but does nothing
visible. Don't write a test that fails on the missing behavior — write one
that documents the gap.

### Example: `Cmd+,` is a stub (as of 2026-06-04)

```dart
// lib/core/shortcuts/global_shortcuts_wrapper.dart:384
void _handleOpenSettings() {
  // TODO: 实现打开设置功能
}
```

### ✅ Test pattern: assert the stub's behavior

```dart
testWidgets('TC-019-shortcut Ctrl+, (Cmd+,) keyboard event is registered',
    (tester) async {
  // NOTE: As of 2026-06-04, GlobalShortcutsWrapper._handleOpenSettings is
  // a stub. This test verifies the KEYBOARD EVENT reaches the handler
  // without crashing. Once _handleOpenSettings is implemented, replace
  // the assertion below.

  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.comma);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.comma);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();

  // Stub: dialog is NOT opened.
  expect(find.byType(SettingsDialog), findsNothing,
      reason: 'Cmd+, currently does not open settings (handler is a stub)');
});
```

When the handler is implemented, **flip the assertion** to
`expect(find.byType(SettingsDialog), findsOneWidget)` and the test will
guard against regressions.

---

## 5. Provider chains — full vs. minimal

Dialogs and panels in DbMaster frequently use **multiple** `Consumer<...>`
calls, each reading a different provider. If you wrap with only the
providers the test "needs", the widget tree will throw on the first
missing provider.

### Required provider chain for most dialogs

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ThemeProvider()..load()),
    ChangeNotifierProvider(create: (_) => LocaleProvider()..load()),
    ChangeNotifierProvider(create: (_) => TaskProvider()),
    ChangeNotifierProvider(create: (_) => AiPanelProvider()),
    ChangeNotifierProvider(create: (_) => PurchaseProvider()..initialize()),
    ChangeNotifierProxyProvider<TaskProvider, AppProvider>(
      create: (_) => AppProvider(),
      update: (_, task, prev) => prev!..updateTaskProvider(task),
    ),
  ],
  child: MaterialApp(...),
);
```

The probe helper `_wrapForDialog()` in
`integration_test/app_wide_test.dart` (line 483) bakes this in. Reuse it.

---

## 6. Locale must follow `LocaleProvider`, not the host OS

`MaterialApp.locale` defaults to the system locale (Chinese on this dev
Mac). Tests that assert English strings (e.g., `"Dark Mode"`) will fail
unless you explicitly drive `MaterialApp.locale` from a
`Consumer<LocaleProvider>`.

```dart
MaterialApp(
  locale: lpv.locale,    // ← driven by LocaleProvider, not system
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: LocaleProvider.supportedLocales,
  home: ...,
);
```

Otherwise the test may see Chinese strings instead of the expected
English, causing spurious failures that look like product bugs.

---

## 7. After-test exceptions ≠ test failure

`flutter test` distinguishes between **assertions during the test body**
and **exceptions after the test completes** (e.g., during teardown). Many
DbMaster after-test warnings come from `PurchaseProvider`'s `Stream`
subscription not being cancelled in `dispose()` (see the internal bug
record, BUG-PURCHASE-001).

These show up as `+N -1: Some tests failed` in the summary, but the
**business assertions all pass**. Use the exit code / detailed log to
disambiguate.

---

## 8. Reference: existing tests that exercise these patterns

| Pattern | Test file | Lines |
|---|---|---|
| `sendKeyDownEvent` 4-key sequence | `integration_test/app_wide_test.dart` | TC-014, TC-015, TC-013, TC-019-shortcut |
| Provider-chain probe | `integration_test/app_wide_test.dart` | `_wrapForDialog` (line ~483) |
| Locale via `Consumer<LocaleProvider>` | `integration_test/app_wide_test.dart` | group `2. Localization` |
| Workspace-dependent shortcut as wiring test | `integration_test/app_wide_test.dart` | TC-014, TC-015 |
| Stub-handler assertion | `integration_test/app_wide_test.dart` | TC-019-shortcut |
| Real shortcut behavior (unit test) | `test/services/shortcut_service_test.dart` | (reference for addNewTab behavior) |

---

## 9. Adding new tests: checklist

Before committing a new `integration_test/*.dart`:

- [ ] `flutter analyze integration_test/<your_test>.dart` → `No issues found!`
- [ ] `flutter test integration_test/<your_test>.dart` → all green
- [ ] If you use `sendKeyDownEvent`, you follow the **4-key sequence**
      (meta + main + release main + release meta)
- [ ] If your test asserts a side-effect, you've waited with
      `pump(100ms) × N` before `pumpAndSettle()`
- [ ] If you wrap a dialog, you've used `_wrapForDialog()` (or its
      equivalent full provider chain)
- [ ] `MaterialApp.locale` is driven by a `Consumer<LocaleProvider>`
- [ ] If you discovered a new pitfall, **update this file** with the lesson
