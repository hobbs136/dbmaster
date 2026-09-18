# ADR 0001: Open-Core 双仓 + Tier Freeze（public 核心仓 + private Pro fork）

- **Status**: Superseded（2026-07-29：客户端已全免费，双仓 Pro fork 策略不再需要。lib/pro/ 保留在 public 仓中，所有功能免费开放。原 Accepted 状态记录保留作决策演进痕迹。）
- **Original Status**: Accepted（2026-07-25，P1 PoC Phase A make-or-break 通过；见文末验证记录）
- **Date**: 2026-07-25
- **Decision owner**: 霍其坤
- **决策演进**: 单仓 `lib/pro/`(A) → **双仓 Pro fork(C)**。曾基于"双仓对名声导向小团队过载"研究推荐单仓 A，但用户明确「public 仓下 Pro 代码必须不公开」为硬约束后，发现**单仓做不到**（lib/pro/ 在 public 仓里对任何 cloner 可读，license header 挡不住读抄）→ 改双仓 C。完整推演见 `.workflows/open-core-strategy/`（两轮对抗 workflow）。
- **Context**: `.workflows/open-core-strategy/01-explore.md` / `02-evaluate.md` / `03-recommend.md`

## Context

DbMaster 以 open-core 开源。仓库拆分经两轮对抗式研究（业界模式/Flutter 约束/先例/DbMaster 现状 + 三套双仓方案设计 + 对抗评估 + 单仓 A 专项 probe）。

**关键约束（用户 2026-07-25 拍板）**：public 仓（`github.com/hobbs136/dbmaster`，已存在，当前仅 docs）下，**Pro 源码必须对任何 clone 者不可读**。这排除所有单仓方案（Pro 在 lib/pro/ 仍公开可读），只剩双仓。

**已核实事实**（代码扫描，非记忆）：
- AppProvider Pro 门禁单一咽喉 `_isProUnlocked`(app_provider.dart:112) 喂 4 个 Pro gate(131-140) + `_aiQuotaService`。
- AiAdapterMixin(189行,8 adapter with) 仅 `getAiSchemaSummary`+`executeAiCommand` 是 AI（其余只读守卫留核心），import `ai_service_localizations`。
- SSH 已 OSS(7cc59107)；dart_mappable 未用（json_serializable tree-shake-clean）；Mongo 集群配置走 `DbServer.extra`(database_models.dart:316)。
- 14 处 `core→Pro` 硬 import 接缝（database_service→SSH、home_screen→ai_panel/purchase_dialog、sidebar_tree→data_sync/schema_diff、query_editor→smart_import/ai_service、app_provider:73→PurchaseProvider、main.dart:59→PurchaseProvider 注册）。
- 本仓 tree-shaking 机制干净（无 dart:mirrors/MapperRegistry），有 `lib/utils/build_flags.dart` 的 `kDirectBuild` 编译时常量门禁先例。

## Decision

### 1. 物理结构（双仓，Pro fork 模式）

**仓 1 — public / Apache-2.0**：`github.com/hobbs136/dbmaster`（权威上游）
```
dbmaster/
├─ lib/
│  ├─ main_oss.dart          # OSS 入口，NoOpProModule（全 false / 空 widget）
│  ├─ services/
│  │  ├─ pro_module.dart     # abstract class ProModule + NoOpProModule（SPI 契约，Apache）
│  │  ├─ database_service.dart  # 核心（Pro 调用点改可空注入）
│  │  ├─ adapters/           # 8 adapter；AiAdapterMixin 持 AiAdapterStrategy?（OSS 空实现）
│  │  │  └─ mongodb_adapter.dart  # 仅 Direct 模式（OSS）
│  │  └─ readonly_guard.dart
│  ├─ providers/app_provider.dart  # 持 ProModule pro（默认 NoOp）；_isProUnlocked => pro.isPro
│  ├─ models/database_models.dart  # DbServer（SSH 字段留 OSS；集群走 extra Map）
│  └─ ... 核心全留
├─ docs/                     # 隐私页（仓内已有，保留）
├─ pubspec.yaml              # 无 in_app_purchase/flutter_secure_storage/cryptography
├─ LICENSE                   # Apache-2.0
└─ .github/workflows/oss-ci.yml
```
**不变式**：public 仓 `lib/` 任何文件不得 import Pro 域（CI grep 断言）；Pro 代码物理不在本仓。

**仓 2 — private / 专有**：GitHub private 仓 `dbmaster-pro`（public 仓的 fork）
```
dbmaster-pro/  (upstream = hobbs136/dbmaster)
├─ lib/
│  ├─ main_pro.dart          # 仅本仓：ProModuleImpl() + runApp
│  └─ pro/                   # 仅本仓：全部 Pro 代码
│     ├─ ai/  schema_diff_sync/  data_sync/  data_import/  mongo_cluster/
│     ├─ purchase/           # purchase_service/pro_status_storage/license(Ed25519)
│     └─ gate/               # ProModuleImpl（实现 public 仓的 abstract）
├─ pubspec.yaml              # upstream pubspec + 追加 in_app_purchase/cryptography/...
├─ pro/LICENSE               # 专有
└─ scripts/build_pro.ps1
```
依赖关系：dbmaster-pro 是 dbmaster 的源码 fork，**git merge upstream/main** 同步；Pro 持有核心完整源码副本，核心内部类可被 Pro 直接引用（省一整层版本绑定，无需把核心抽成 pub 包）。

### 2. Tier Freeze（Day-1 定死，之后不动）

**OSS（Apache 核心，无限）**：8 库全开；连接/Tab/SSH 全无限(7cc59107)；AI 聊天 30 次/月（用户自带 key）；Schema Diff 查看、Mongo Direct、数据导出。

**Pro（专有，private fork）**：AI Agent/DDL、Schema Diff 同步、Data Sync、Data Import、Mongo 集群(RS/Sharded/Advanced)、IAP/离线 license。

**红线**：已免费的 OSS 功能绝不后挪 Pro（DbGate #994）；核心 license 绝不迁 BSL/SSPL/FSL（Sentry/Redis/HashiCorp）；tier 变更必须新 ADR。

### 3. 同步机制（git merge upstream，零 cherry-pick / 零 ref bump）
- (a) 核心 bugfix → public 仓提 PR 合并 → private fork `git fetch upstream && git merge upstream/main` 自动流入。
- (b) Pro 需核心新接口 → 先在 public 仓加 abstract 扩展点（additive）→ fork merge → 在 lib/pro/ 实现。
- (c) 外部 contributor PR → public 仓 review 合并 → fork merge 自动继承，贡献者完全不知道 Pro 存在。

### 4. 防线（双仓版，Pro 不进 public 仓）
1. **物理分仓（最强·根因）**：Pro 代码只存 private fork，public 仓 git history 永不可能含 Pro 字节。
2. **import 边界 CI 断言**：public 仓 CI 跑 `rg -n "import.*(lib/pro|purchase_provider|license|ssh_tunnel)" lib/` 必须零命中。
3. **pre-commit（private fork 侧）**：检测核心文件（lib/ 除 pro/）有未在 upstream 出现的改动即拒 commit——把"零核心改动"从纪律升级为工具强制（防 GitLab 式双仓滑坡）。
4. **OSS 二进制 gate**：public 仓 release 前 `flutter build --analyze-size` size.json + strings exe 双扫 Pro 符号断言零出现。
5. **LICENSE 放置**：public 根 Apache-2.0；private fork `pro/LICENSE` 专有；`.gitattributes linguist-vendored`。
6. **纪律级**：本 tier-freeze ADR + DCO 强制。

## Consequences

- **正面**：Pro 源码物理不公开（唯一能满足"Pro 不公开"硬约束的形态）；contributor clone public 仓即得完整 OSS 版、零凭证；public 仓 git history 干净可 star/portfolio；同步走 git 原生 merge 零工具税。
- **负面**：14 接缝拆分 + ProModule SPI + AiAdapterMixin strategy 注入是真工时（1 人 3-5w / 2 人 2-3w）；private fork "零核心改动"需 pre-commit 工具强制（否则 GitLab 式滑坡）；Pro exe 反编译护城河仍靠 Ed25519+机器码绑定（非藏源码，但源码私有已是第一道）。
- **Day-0 待办**：① public 仓首次只 push 清理 Pro 后的核心（当前仓 Pro 散在 lib/，须先 P1 拆完再首次 push 代码）② Gitee 旧仓处置（归档/只读镜像避陈旧镜像声誉税）③ Flathub 2026/05 AI 政策核实（二期前置）。

## Alternatives Considered（否决理由见 `.workflows/open-core-strategy/02-evaluate.md`）

- **A 单仓 lib/pro/**：public 仓下 Pro 仍可读，**做不到"Pro 不公开"**——被硬约束排除。
- **B 双仓 + Pro pub 包**：contributor 最净但 app-as-library 未验证(需 spike)、测试迁移第二套真实库 CI、4-6w、Renovate 调试税。
- **D 双仓 + Overlay**：构建分离最强但 path-package 压无文档 Dart 隐性行为、Pro 不能独立测试。
- C 相比 B/D：git-native merge 同步最省心、无需 pub 包机制/path-package spike、public 仓直接作核心上游改动最小。

## 验证记录（P1 PoC Phase A，2026-07-25）→ Status: Accepted

**make-or-break 通过**：branch `045-open-core-split-poc`（commits `e724a19e` / `f7065a98` / `ab626f6f` / `4ae13054`）。

- `flutter build windows --release --target=lib/main_oss.dart` 成功（43.1s，dbmaster.exe 44MB）。
- 扫描 gate `scripts/build_oss_scan.ps1` 机制成立（size.json + exe strings 双扫，可证伪断言）。
- AppProvider 注入化**修复 I.8**（删 PurchaseProvider 硬字段 → ProModule 构造注入）；4 gate + AiQuotaService 经 `_isProUnlocked` 单一咽喉自动跟随；_resolveAllowTools 统一咽喉顺带修 devBypassGates 不生效 bug。
- lib/ `dart analyze` **0 error**。
- 检出 **8 Pro 符号** = Phase B 精确清单：`PurchaseProvider` / `Ed25519` / `AiAgentService` / `AiServiceLocalizations` / `SchemaDiffSync` / `DataSyncer` / `_buildReplicaSetUri` / `_buildShardedUri`。

**Phase B 待办**（迁 8 符号到 Pro 仓 + main_pro + ProModuleImpl + Mongo Base/Cluster 拆分；1 人 ~1 周）。Branch `045-open-core-split-poc` 保留至 Phase B 完成（`main.dart` 现注入 NoOpProModule + 删顶层 PurchaseProvider，不合 master 以免破坏开发期 Pro/purchase_dialog）。

**Phase B 清零后**：扫描 gate `exit 0` = 完整 make-or-break，public 仓首次 push 干净核心代码（方案 X orphan 基线）。

## 验证记录（Phase B.1 OSS 侧解耦，2026-07-25）→ 扫描门 exit 0 ✅

**完整 make-or-break 达成**：`scripts/build_oss_scan.ps1` → `PASS: zero Pro symbols`（exit 0）。branch `045-open-core-split-poc`（commits `03a7f182` mongo / `d17b7b5a` purchase / `b92ac936` blocklist 精修 / `4128e9d0` trial / `4f4d64ab` ai-agent / `6e8eafee` 测试修复）。

**★策略 = rewire-only**：每 seam 仅打断 `lib/` 的 import 链（消费方改读新 SPI），Pro 源文件**留在 `lib/`** 不再被 `main_oss` 传递引用 → AOT tree-shake 移除。物理迁 `pro_staging/` + 测试迁移**整体推迟到 B.2**（dbmaster-pro 就绪后批量搬）。决策依据：实测迁源文件会破坏 ~22 个 incidental 测试（purchase 单 seam），rewire-only **0 测试破坏**且同等清零——`dart analyze lib/` 全程 0 error，63 个既有测试编译错误（Phase A `DbmasterApp(proModule:)` 签名 + `getAiSchemaSummary` signature drift，非本阶段引入）纹丝不动。

**5 seam + 4 新 SPI**：①mongo（删 cluster 私有方法 + `MongoClusterStrategy` SPI + `DatabaseService._adapterFactories` static→instance 注入）②purchase（`ProPurchaseUi` SPI + `DbmasterApp` 注入槽 + 4 importer rewire）③trial（`TrialGate` SPI + AppProvider 试用委托 `proModule.trial` + `trySchemaDiffSync`→`trySchemaSync` 改名）④blocklist 精修 ⑤ai-agent（`AiAgentRunner` SPI + `FreeChatRunner` 抽取 no-tools 路径 + orchestrator 工厂注入）。ProModule 保持 foundation-pure（UI 槽 ProPurchaseUi 独立 Provider 注入）。

**扫描门准确性修正（3 假阳，不改永不可清零）**：`Ed25519` 同时命中 dartssh2 的 `SSHEd25519Key`/`ed25519_impl`（OSS SSH 免费，合法在构建）→ 改 `TrialQuotaCrypto`；`AiServiceLocalizations` 是核心（8 adapter Free chat schema + `_checkAiQuota`）→ 删；`DataSyncer` 命中 L10n key `dataSyncError*`（非类）→ 改 `DataSyncService`/`DataSyncDialog`。

**name-based 扫描局限（诚实记录）**：Dart AOT 会 inline+de-name 仅内部使用的类（`SchemaSyncService`/`DataSyncService`/`DataSyncDialog` 的 NAME 在 trial seam 后被 tree-shake，scan 过但 inlined 代码可能仍在二进制）。→ **物理分仓 B.2 才是真保证，扫描门是 tripwire 后盾**（非唯一防线）。

**Phase B.2 待办**（Pro 仓侧，dbmaster-pro 就绪后）：clone dbmaster-pro + fork-init；批量搬 Pro 源文件 lib/→`dbmaster-pro/lib/pro/` + 测试迁移；写 `ProModuleImpl`（覆写 `mongoClusterStrategy`/`trial`/`createAgentRunner`/proPurchaseUi）+ `main_pro.dart`；`AiAgentService` 加 `implements AiAgentRunner`；验证 Pro 构建。此后 public 仓首次 push 干净核心（方案 X orphan 基线）。
