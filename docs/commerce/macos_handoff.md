# macOS 接续交接 — DbMaster 商业化

> ⚠️ **DEPRECATED (2026-07-29)**: 客户端已全免费，MAS 上架策略暂停。技术验证资料已提取至 `../technical/macos_sandbox_notes.md`。原引用文档已归档至 `../archive/commerce/`。
>
> **2026-07-18** Windows 会话产出，供 macOS 上接续。原引用 [`free_pro_gating.md`](../archive/commerce/free_pro_gating.md) + [`launch_strategy.md`](../archive/commerce/launch_strategy.md)（已归档）。
>
> 本文档的事实均经一次并行代码审计核实（5 个切片，file:line 见各节）。

---

## ⚠️ 第 0 步：切机前必须 commit+push（否则工作丢失）

当前 4 个产出文件**都未提交**，换机器 `git pull` 会丢：
- `docs/commerce/`（整目录 untracked：`free_pro_gating.md`、`launch_strategy.md`、本文）
- `.workflows/china-us-launch-membership/03-recommend.md`（untracked）
- `.workflows/current-state.md`（tracked，但 COMPLETED 改动 unstaged）

**确认 `.workflows/` 未被 gitignore**（86 个文件已入库），所以提交后能随 git 同步到 Mac。切机前在 Windows 跑：

```bash
git add docs/commerce .workflows/china-us-launch-membership .workflows/current-state.md
git commit -m "docs(commerce): 中美发行策略 + Free/Pro 门禁规格 + macOS 接续交接"
git push
```

> 这些都是 `.md`，pre-commit 的 `CHANGE:` 钩子不扫 markdown，不会拦截。

---

## 1. 已定稿决策（摘要）

| 项 | 定稿 | 详见 |
|----|------|------|
| 渠道 | **Mac App Store 单渠道**（中美通吃），不上移动端/MS Store；Windows 后补 | launch_strategy §1 |
| 主体 | 国内公司 Apple Developer 账号（解决此前 Apple 账号受阻） | launch_strategy §1 |
| 定价 | 美 $9.9/月·$99/年；中 ¥29/月·¥199/年 | launch_strategy §2 |
| 合规 | 国区 APP 备案（主体办）+ 隐私政策 GitHub Pages + 国内镜像 | launch_strategy §3 |
| Free/Pro | 用量门 + 功能门混合；Free 够用永久免费 | free_pro_gating §1-2 |
| AI 分级 | 基础 AI（读）Free 30 次/月；高级 AI（写/Agent）Pro 专属 6 条 | free_pro_gating §3 |
| Tool Calling | ✅ 决策 B 已完成（2026-07-18），待真 key E2E | free_pro_gating §4 |
| dev 口子 | `kDebugMode` 编译期守，release 物理消失 | free_pro_gating §5.2 |

---

## 2. 仓库现状（关键修正：比预期成熟）

### 2.1 macOS 构建基础设施已大量就位（审计确认）
- `macos/` **完整脚手架**：Runner.xcodeproj/xcworkspace、Podfile（platform :osx `'10.15'`）、`DebugProfile.entitlements` + `Release.entitlements`、Info.plist、PrivacyInfo.xcprivacy、Products.storekit、AppIcon 全套。
- `scripts/build_macos.sh` 已存在（`build_windows.ps1` 的对应物），自动调 `bundle_freetds_macos.sh`，有 Release 签名守卫（无 team/identity 时自动降级 Debug）。
- `scripts/bundle_freetds_macos.sh` 已存在：从 `brew --prefix freetds` 拷 `libsybdb.dylib`(+`.5`)、从 `openssl@3` 拷 `libssl/libcrypto` 进 `Contents/Frameworks`，`install_name_tool` 修 `@rpath`。
- `APPSTORE_SUBMISSION_GUIDE.md`（仓库根，24KB，2026-05-30）已有 MAS 提交合规清单；`scripts/verify_compliance.sh` 已引用。
- `Release.entitlements` 已配：`app-sandbox=true`、`network.client/server=true`、`files.user-selected.read-only/read-write=true`、`keychain-access-groups`。
- Info.plist 已 MAS-ready：`ITSAppUsesNonExemptEncryption=false`、`LSApplicationCategoryType=public.app-category.developer-tools`、各项 usage string。
- `DEVELOPMENT_TEAM=5766J8U7A3`、`PRODUCT_BUNDLE_IDENTIFIER=com.dbmaster.app`。
- SQL Server FFI 加载器已把 bundled `Frameworks/libsybdb.dylib` 放在搜索路径**第一位**（`sqlserver_ffi_bindings.dart:82`），brew 路径是兜底。

### 2.2 门禁现状：全关（需重启）
`app_provider.dart` 8 个权限 getter 全 `=> true`（行 113/117/121/125/142/146/150/154），5 处调用点全注释（502/533/582/639-653/1983）。`AiQuotaService`（71 行，完整可用）**完全断连**（import/字段/构造全注释）。`canUseDataSync` **不存在**。详见 §4.1。

---

## 3. macOS 沙盒冲刺（真实阻塞点，审计后修正）

> 完整验证清单见 `launch_strategy.md §6.3`（已据审计更新）。下面是**确认的真实阻塞点**，按严重度：

1. **【命门】FreeTDS dylib 签名**：`bundle_freetds_macos.sh:146` 用 `codesign --force --deep --sign -`（**ad-hoc**）重签 → **会使 Distribution 签名失效**，MAS 上传必拒。必须改成：用 team 身份逐个签 `Frameworks/` 下的 `libsybdb`/`libssl`/`libcrypto` + Hardened Runtime + Library Validation（homebrew 来源的 dylib 不被 team 签 → 库校验会挡 dlopen）。还需 universal（arm64+x86_64）构建。
2. **Release 签名身份错误**：`project.pbxproj:730` Release 是 `'Apple Development'`（非 Distribution），`PROVISIONING_PROFILE_SPECIFIER=''`。MAS 上传要 `'Apple Distribution'` + Mac App Store provisioning profile（国内主体 Apple 账号提供）。
3. **【blocker】SQLite 拖拽跨重启**：`connection_provider.dart:909-943` 把 SQLite 文件路径存进 `DbServer.host`，但**全仓库无 security-scoped bookmark**（grep 确认）。沙盒下重启后重开该路径会被拒（EPERM）。需：entitlement 加 `files.bookmarks.app-scope` + 在 pick/drop 时建 bookmark、connect 时 `startAccessingSecurityScopedResource`、disconnect 时 stop。（launch_strategy §6 原标"🟡 待验"，审计确认是**缺失**，非未验。）
4. **'Reveal in Finder' shell-out**：`sqlite_tree_builder.dart:2138` `Process.run('open',[dir])` 沙盒下会失败。改 `NSWorkspace.open` 或在 macOS 沙盒构建上去掉/门控该菜单项。
5. **部署目标 10.15 偏低**：Apple 近年抬高底线，低于 11.0 可能警告/拒；构建时留意，必要时升 `platform :osx` + `MACOSX_DEPLOYMENT_TARGET` 到 11.0。
6. **构建机依赖**：无 dylib 入库，macOS 构建机必须 `brew install freetds openssl@3`。
7. 跑 `APPSTORE_SUBMISSION_GUIDE.md` 合规清单 + `scripts/verify_compliance.sh`；`RunnerTests` 的 `com.example.dbmaster.RunnerTests` bundle id 顺手改掉（cosmetic）。

**SSH/SQLite/导出/备份均沙盒兼容**（审计确认）：SSH 纯 `dartssh2` 无 shell-out、绑 `127.0.0.1:0`（`network.server` 已配）；SQLite 用系统 `libsqlite3`（`pubspec.yaml:59-67` source=system，无需打包）；导出走 `FilePicker.saveFile`（NSSavePanel）；备份存 app container。

---

## 4. 待办任务清单

### 4.1 重启门禁 — ✅ 已完成（2026-07-19，见 free_pro_gating.md §5.3）
以下为当时的实施范围（存档，行号已失效）：
范围（精确，审计后）：
- 8 个 getter 改回真判断（行 113/117/121/125/146/150/154 走 `purchaseProvider.isPro`；142 `canViewSchemaDiff` 保持 true 是有意 Free 开放）。
- 取消注释 5 处调用点（502-506/533-537/582-586/639-653/1983-1987）。
- **重连 `AiQuotaService`**：取消注释 import(行 11)/字段(行 74)/构造(行 303-308)。⚠️ **坑**：构造里引用了 `_loadAiQuota()`（行 308）但该方法体不存在——直接取消注释会**编译失败**，需实现它或删该调用；并删掉行 306 的重复游离注释。
- 新增 `canUseDataSync`（Data Sync 现完全无门禁）。
- 清除所有 `'暂时禁用 Free/Pro 门控'` 注释（行 78/112/116/120/124/132/145/149/153/406/501/532/581/637/1982）。
- 验证：`dart analyze lib/` 0 新增 + widget/integration 测试（`AiQuotaService.resetForTesting()` 已有，便于隔离）。

### 4.2 Tool Calling 补全（决策 B）—— ✅ 已完成（2026-07-18，T1-T4）
详见 `free_pro_gating.md` §4。要点：① Kimi 名字 bug 已修；② Claude 走方案 A（agent 循环 history 保持 OpenAI 格式，`AnthropicConverter` 在 client 边界转换，**agent loop 未改 provider-aware、`AiToolCall` 未动**——与原审计建议不同，更省）；③ Gemini 走 OpenAI-compat 端点（含 getByName display name 兜底 + 旧 baseUrl load 迁移）。**额外修了 3 个审计外发现**：A. Claude 路由死代码（`_resolveApiProvider`）；B. Gemini display name 错位；C. 旧默认 baseUrl 被持久化。测试 177 例全绿。**待办：真 key E2E**（Claude/Gemini Agent 循环 + checkpoint 恢复 + Claude 流式回归）。

### 4.3 还没做的（非 Mac 阻塞）
- **Q4 国内宣发**细化（掘金/V2EX/知乎/B站/GitHub 矩阵 + 内容节奏）。
- **Q5 功能短视频**策划（单功能单视频，15-60s，中美双平台素材复用）。

### 4.4 收尾（tech debt，非阻塞）
- `docs/README.md` 索引补 `commerce/`。
- 536 个历史 `// CHANGE:` 标记散落 84 个 lib/*.dart（钩子只拦新增行，旧的不抓）——单独清理。

---

## 5. 关键文件索引

| 用途 | 路径 |
|------|------|
| 门禁规格 | `docs/commerce/free_pro_gating.md` |
| 发行/定价/合规/沙盒 | `docs/commerce/launch_strategy.md` |
| 本文（接续） | `docs/commerce/macos_handoff.md` |
| 决策记录 | `.workflows/china-us-launch-membership/03-recommend.md` |
| 工作流状态 | `.workflows/current-state.md` |
| MAS 提交指南（已有） | `APPSTORE_SUBMISSION_GUIDE.md` |
| macOS 构建 | `scripts/build_macos.sh`、`scripts/bundle_freetds_macos.sh`、`scripts/verify_compliance.sh` |
| entitlements | `macos/Runner/{DebugProfile,Release}.entitlements` |
| 门禁代码 | `lib/providers/app_provider.dart`（getter+调用点）、`lib/services/ai_quota_service.dart`、`lib/providers/purchase_provider.dart:22`(`isPro`) |
| Tool Calling | `lib/services/ai/ai_client.dart`、`lib/services/ai_agent_service.dart`、`lib/models/ai_models.dart`、`lib/services/database_tool_registry.dart` |
| FFI / SQLite 持久化 | `lib/services/adapters/sqlserver_ffi_bindings.dart`、`lib/providers/connection_provider.dart:909-943` |
| Finder shell-out | `lib/organisms/sidebar/builders/sqlite_tree_builder.dart:2138` |
