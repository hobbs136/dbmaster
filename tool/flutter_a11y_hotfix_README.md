# Flutter 3.41.4 Windows 可访问性崩溃热修

本目录的 `flutter_a11y_hotfix_3.41.4.patch` 是 Flutter 上游
[flutter/flutter#193372](https://github.com/flutter/flutter/pull/193372)
（2026-10-19 合入 master）向本地 Flutter 3.41.4 SDK 的回移补丁。

修复 Windows 可访问性桥 `HitTestSync` 在 traversal parent 缺失时对过期
`FlutterPlatformNodeDelegate` 解引用导致的 release 崩溃（`flutter_windows.dll+0xf283`，
`0xc0000005` / `0xc000041d`）。背景与证据见
`docs/bugs/flutter_windows_a11y_hittest_crash.md`（本地文档，不入 git）。

## 应用（Flutter SDK 根目录）

```bash
SDK=/c/soft/flutter_windows_3.41.4-stable/flutter
F="$SDK/packages/flutter/lib/src/semantics/semantics.dart"
cp "$F" "$F.bak-$(date +%Y%m%d)"
cd "$SDK"
git apply /d/workspace/dbmaster/dbmaster-flutter/tool/flutter_a11y_hotfix_3.41.4.patch
# 或 patch -p1 < ...（补丁基于 3.41.4 SDK HEAD，直接应用）
flutter clean && flutter pub get
```

## 撤销

```bash
git -C "$SDK" checkout -- packages/flutter/lib/src/semantics/semantics.dart
# 或恢复 .bak-* 备份
```

## 何时移除

上游修复进入 Flutter stable（3.50+）后升级 SDK 并删除本补丁。
本补丁只改框架 Dart 语义树实现，不改引擎 DLL。
