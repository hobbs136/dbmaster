# macOS Sandbox Validation Notes

> 提取自历史发行策略文档 §6（2026-07-18 审计）。
> 客户端全免费后 MAS 上架优先级降低，但技术验证资料保留供参考。

## Required Entitlements

```
app-sandbox = true
network.client = true                      // 连所有数据库
network.server = true                      // SSH 隧道本地端口转发
files.user-selected.read-write = true      // 导出/导入文件选择器
files.bookmarks.app-scope = true           // SQLite 拖拽打开跨重启访问
// + Hardened Runtime + Library Validation（FFI 签名必需）
```

## Current State (2026-07-18 audit)

- `macos/` 完整脚手架 + `Release.entitlements`（app-sandbox / network.client+server / files.user-selected / keychain）+ Info.plist（MAS-ready）+ `DEVELOPMENT_TEAM=5766J8U7A3`、bundle `com.dbmaster.app`
- `scripts/build_macos.sh` + `scripts/bundle_freetds_macos.sh` + `scripts/verify_compliance.sh`
- Root `APPSTORE_SUBMISSION_GUIDE.md` with MAS compliance checklist
- SQL Server FFI loader prioritizes bundled `Frameworks/libsybdb.dylib` (`sqlserver_ffi_bindings.dart:82`)

## Code Audit Results

| Component | Implementation | Sandbox |
|-----------|---------------|---------|
| SSH | `dartssh2` pure Dart, bind `127.0.0.1:0`, no shell-out | ✅ |
| SQLite | `sqflite_common_ffi` uses system libsqlite3 (pubspec source=system) | ✅ |
| Other DBs (MySQL/PG/Mongo/Redis etc.) | Pure Dart drivers | ✅ |
| File export/import/backup | `FilePicker.saveFile`/`pickFiles` (NSSavePanel/NSOpenPanel) + app container | ✅ |
| SQL Server | FreeTDS FFI `libsybdb.dylib` (homebrew source, not team-signed) | ⚠️ Critical |
| SQLite drag-and-drop cross-restart | Path stored in `DbServer.host`, no security-scoped bookmark | ❌ blocker |
| 'Reveal in Finder' | `Process.run('open',[dir])` (`sqlite_tree_builder.dart:2138`) | ❌ Sandbox fail |

## Real Blockers (by severity)

1. **【Critical】FreeTDS dylib signing**: `bundle_freetds_macos.sh:146` uses ad-hoc (`codesign --force --deep --sign -`) → invalidates Distribution signing. Fix: team-sign each dylib in `Frameworks/` individually + Hardened Runtime + Library Validation + universal build. Build machine needs `brew install freetds openssl@3` (no dylibs in repo).
2. **Release signing identity**: `project.pbxproj:730` is `'Apple Development'` (not Distribution), `PROVISIONING_PROFILE_SPECIFIER=''` → change to `'Apple Distribution'` + MAS provisioning profile.
3. **【blocker】SQLite drag-and-drop cross-restart**: Add entitlement `files.bookmarks.app-scope` (currently missing from `Release.entitlements`) + `connection_provider.dart:909-943` add bookmark creation / `startAccessingSecurityScopedResource` code (currently absent, grep confirmed).
4. **'Reveal in Finder'**: Change to `NSWorkspace.open` or gate out on macOS sandbox builds.
5. **Deployment target 10.15** is low; monitor Apple minimum; raise `platform :osx` + `MACOSX_DEPLOYMENT_TARGET` to 11.0 if needed.
6. Run `APPSTORE_SUBMISSION_GUIDE.md` checklist + `verify_compliance.sh`; fix `RunnerTests` `com.example.dbmaster.RunnerTests` bundle id (cosmetic).
