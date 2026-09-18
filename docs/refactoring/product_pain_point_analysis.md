# DbMaster 产品优化方向

> **日期**: 2026-07-08 · **目标市场**: 美国
> **对标**: DataGrip · TablePlus · DBeaver · Navicat

---

## 一、数据库组合：从 10 个减到 8 个

美国市场数据库管理工具必须有 PG + MySQL + SQLite + MongoDB + Redis + SQL Server，这是入场券。Doris 和 TDengine 是你的蓝海差异化——全球没有竞品同时支持它们。

### 最终组合

| 层级 | 数据库 | 理由 |
|------|--------|------|
| 🔑 核心 | **PostgreSQL** | 美国新项目默认 RDBMS，没有 PG 支持 = 自绝于 50% 开发者 |
| 🔑 核心 | **MySQL** | 美国存量最大 RDBMS |
| 🔑 核心 | **SQLite** | 全球部署量第一，零 CI 成本（文件数据库，无需外部服务） |
| 🔑 核心 | **MongoDB** | 美国 Node.js/创业生态文档数据库标准 |
| 🔑 核心 | **Redis** | 数据库工具完整性标志 |
| 🔑 核心 | **SQL Server** | 美国企业市场（银行/保险/政府）入场券 |
| 🚀 差异化 | **Doris** | Apache 顶级项目，继承 MySQL 协议（适配器仅 386 行），零竞品 |
| 🚀 差异化 | **TDengine** | 时间序列数据库，全球唯一桌面客户端支持 |
| ❌ 砍掉 | **Elasticsearch** | Kibana 体验碾压一切桌面工具，无损失 |
| ❌ 砍掉 | **Snowflake** | 自带 Web UI 极好，云数据仓库用户不会用桌面客户端 |

### 减负效果

| 指标 | 瘦身前 | 瘦身后 |
|------|--------|--------|
| 数据库数 | 10 | 8 |
| CI 外部服务 | 9 种 | 5 种（PG + MySQL + MongoDB + Redis + TDengine） |
| 适配器代码 | 11,735 行 | ~9,900 行 |
| 集成测试 | 15,951 行 | ~12,700 行 |
| SQL Server FFI stub 同步 | 每次接口变更必做 | 保留，但接口变更频率已降低 |

---

## 二、数据库原生体验：深化 PG / MySQL / SQLite

> **核心洞察**：当前适配器架构把数据库当成可互换的——同一条 `SELECT * FROM` 在 8 种数据库上返回相同的结果。但数据库不是可互换的。PG 用户和 SQLite 用户的需求几乎没有交集。深化不是加功能，是**让每种数据库的独特灵魂浮出水面**。

### 架构基础：能力接口模式（已存在）

你在 `database_abstract.dart` 中已有 `CharsetAdapter`、`SqlSchemaAdapter`、`DdlAdapter` 等能力接口，UI 通过 `if (adapter is CharsetAdapter)` 决定展示什么。新增 6 个能力接口即可解锁数据库专属体验——**不修改 `DatabaseAdapter` 基类，零破坏性**：

```dart
abstract interface class SchemaAwareAdapter { ... }   // PG + SQL Server
abstract interface class ExtensionAdapter { ... }     // PG
abstract interface class JsonAdapter { ... }          // PG + MySQL + SQLite
abstract interface class ProcessListAdapter { ... }   // MySQL
abstract interface class ReplicationAdapter { ... }   // MySQL
abstract interface class PragmaAdapter { ... }        // SQLite
```

---

### PostgreSQL：可扩展性就是它的超能力

PG 不是数据库，是**数据库构建平台**。PostGIS、pgvector、TimescaleDB 把 PG 变成了地理信息系统、向量数据库、时序数据库。当前 DbMaster 和所有竞品一样——把它们当成普通扩展忽略掉。

#### PG-1. Schema 优先导航 🔴 P0 · 2-3d

**问题**：PG 用户的思维模型是 "schema → table"（`auth.users`、`api.orders`），不是 "database → table"。当前侧边栏把所有 schema 的表平铺在一起，有 20 个 schema 时是灾难。

**目标**：连接 PG 时，树形结构 L2 改为 schema。schema 节点显示对象计数。状态栏显示当前 `search_path`，点击可编辑。

**能力接口**：`SchemaAwareAdapter` — `getSchemas()`、`getCurrentSchema()`、`setSearchPath(List<String>)`

#### PG-2. 扩展浏览器（Extension Browser）🟡 P1 · 3-4d

- 侧边栏新增 "Extensions" 节点 → 列出 PostGIS、pgvector、pgcrypto 等
- 点击扩展 → 展示它注册的类型、函数、操作符
- **pgvector 专属**：显示向量索引（IVFFlat/HNSW）、维度、距离函数 → 这是每个 AI 开发者需要的东西，目前没有任何桌面工具在做

**能力接口**：`ExtensionAdapter` — `getExtensions()` → `List<PgExtension>`

#### PG-3. JSONB 结构化浏览器 🟡 P1 · 3-4d

- 结果表格中 `jsonb` 列以 `{…}` 图标标记
- 双击 → 弹出树形 JSON 查看器
- 右键 → "Extract field as column" → 自动生成 `data->>'field'` 查询

**能力接口**：`JsonAdapter` — `getJsonColumns(table)`、`isJsonbColumn(table, column)`

---

### MySQL：运维可见性就是它的超能力

MySQL 独特之处不在查询能力（PG 更强），而在运维工具链：`SHOW` 命令、`PERFORMANCE_SCHEMA`、`INFORMATION_SCHEMA`。

#### MY-1. 实时进程列表 🔴 P0 · 2-3d

`SHOW PROCESSLIST` 是 DBA 前三个操作之一，当前必须手动敲 SQL。

- 侧边栏底部新增 "Running Queries" 面板（仅 MySQL）
- 实时刷新：Query ID · User · Host · Time · State · Info
- 一键 Kill · 慢查询（>5s）红色高亮

**能力接口**：`ProcessListAdapter` — `getProcessList()`、`killProcess(int id)`

#### MY-2. 存储引擎感知 🟡 P1 · 1-2d

- 表列表显示引擎图标（InnoDB = 🔒，MyISAM = ⚡）
- 表属性面板：InnoDB 行格式（COMPACT/DYNAMIC）、压缩状态
- `SHOW ENGINE INNODB STATUS` 解析为可读摘要

**能力接口**：`EngineInfoAdapter` — `getTableEngine(table)`、`getEngineStatus(engine)`

#### MY-3. 复制状态 🟡 P1 · 2-3d

- 状态栏复制指示器：`Replication: ✅ Running | Lag: 2s`
- IO/SQL 线程中断 → 状态栏变红
- 点击展开 `SHOW SLAVE STATUS` 摘要

**能力接口**：`ReplicationAdapter` — `getReplicationStatus()` → `ReplicationStatus?`

---

### SQLite：零摩擦就是它的超能力

SQLite 的本质不是"轻量级数据库"，是**"数据库就是文件"**。它的连接不需要 host/port/user/password，只需要一个文件路径。当前连接对话框用与其他数据库相同的表单——这从根本上误解了 SQLite。

#### SL-1. 拖拽打开（Zero-Friction Connect）🔴 P0 · 1-2d

- 连接方式改为文件选择器 "Open .db File"，而非填表单
- 拖拽 `.db`/`.sqlite`/`.sqlite3` 文件到窗口 → 自动打开
- Recent Files 列表（而非 Recent Connections）
- 命令行支持：`dbmaster ./mydb.sqlite`

这个改动让体验从"配置数据库连接"变为"打开文件"——与用户心智模型一致。

#### SL-2. PRAGMA 探索器 🟢 P2 · 3-4d

SQLite 有 60+ 个 PRAGMA，无人能记住。

- 右键数据库 → "PRAGMA Explorer"
- 分类面板：性能 · 持久性 · 安全 · 调试
- 每项：当前值 + 描述 + 推荐值 + 一键修改

**能力接口**：`PragmaAdapter` — `getPragmas()`、`setPragma(name, value)`

#### SL-3. 文件操作作为一等公民 🟢 P2 · 2-3d

- 右键 → Vacuum / Integrity Check / Optimize → 一键执行
- "Save As…" → 复制 .db 并可选 VACUUM INTO 瘦身
- 状态栏：文件路径 · 大小 · WAL 模式 · 页大小
- ATTACH：拖入第二个 .db → 附加数据库 → 可跨库查询

---

### 数据库原生体验优先级矩阵

| # | 改进项 | 数据库 | 工时 | 用户感知 | 竞品差距 | 优先级 |
|---|--------|--------|------|---------|---------|--------|
| PG-1 | Schema 优先导航 | PG | 2-3d | 🔴 极高 | 中 | **P0** |
| MY-1 | 进程列表 | MySQL | 2-3d | 🔴 极高 | 中 | **P0** |
| SL-1 | 拖拽打开 | SQLite | 1-2d | 🔴 极高 | 大 | **P0** |
| PG-2 | 扩展浏览器 | PG | 3-4d | 🟡 高 | 大 | P1 |
| PG-3 | JSONB 浏览器 | PG | 3-4d | 🟡 高 | 大 | P1 |
| MY-2 | 存储引擎感知 | MySQL | 1-2d | 🟡 高 | 中 | P1 |
| MY-3 | 复制状态 | MySQL | 2-3d | 🟡 中 | 中 | P1 |
| SL-2 | PRAGMA 探索器 | SQLite | 3-4d | 🟢 中 | 大 | P2 |
| SL-3 | 文件操作 | SQLite | 2-3d | 🟢 中 | 大 | P2 |

**P0 三项共 5-8 天**，即可覆盖三种数据库用户每天最频繁的需求。

---

## 三、通用体验深度：三大支柱补齐"最常用路径"

> 与第二章互补：第二章是**纵向深度**（每种数据库的独特体验），本章是**横向体验**（所有数据库共享的路径优化）。

用户一天的标准路径：

```
打开连接 → 选数据库 → 写 SQL → 执行 → 看结果 → 导出/分析
```

这条路径上当前摩擦最大的三个点：

| 摩擦点 | 当前 | 用户心里的话 |
|--------|------|------------|
| 执行 | 无 DML 防护，无资源预估，无超时 | "这条 SQL 会不会把库搞挂？" |
| Schema 变更 | 能看差异，同步靠手写 | "怎么安全同步到生产库？" |
| 结果处理 | 仅表格，导出无 PII 检查 | "又要切到 Excel 画图？" |

### 支柱 A：执行安全网（1-2 周）

让用户在点击"执行"前有安全感。

| # | 改进项 | 优先级 | 工时 | 核心行为 |
|---|--------|--------|------|---------|
| A1 | DML 硬拦截 | 🔴 P0 | 3-4d | DELETE/UPDATE 无 WHERE → 弹窗输入表名确认；有 WHERE 无 LIMIT → 警告条二次点击。集成 SQL 注入检测自动提级 |
| A2 | EXPLAIN 预检 | 🔴 P0 | 2-3d | SELECT 执行前自动 EXPLAIN，全表扫描 >10K 行 → 黄色警告 +「仍然执行」「取消优化」 |
| A3 | 超时熔断 | 🟡 P1 | 1-2d | 默认 30s 超时自动 kill query，最后 5s 倒计时，超时后提示重试/优化/加 LIMIT |

### 支柱 B：Schema Diff 闭环（2-4 周）

从"能看差异"到"能完成同步"，全程不离开工具。

| # | 改进项 | 优先级 | 工时 | 核心行为 |
|---|--------|--------|------|---------|
| B1 | 三栏可视化 | 🟠 P1 | 3-4d | 左:对象树 · 中:差异明细(颜色编码+筛选) · 右:DDL 预览。忽略规则保存为 Profile |
| B2 | 同步+回滚 | 🟠 P1 | 3-4d | Dry Run → 逐条执行 → 失败自动回滚(PG)/提示手动回滚(MySQL) → 完成摘要 → 自动刷新 Schema 树 |
| B3 | 快照管理 | 🟢 P2 | 2-3d | 一键存快照(JSON)，快照 vs 快照 / 快照 vs 当前对比，导出/导入 |

### 支柱 C：结果到洞察闭环（4-6 周）

查询结果不离开工具就能完成分析和导出。

| # | 改进项 | 优先级 | 工时 | 核心行为 |
|---|--------|--------|------|---------|
| C1 | 一键图表 | 🟠 P1 | 3-4d | 自动检测列类型推荐图表(日期+数值→折线，分类+数值→柱状)。基于 fl_chart（已集成）。AI「分析趋势」按钮 |
| C2 | PII 保护导出 | 🟡 P1 | 2-3d | 导出前自动检测 PII 列 → 每列选择脱敏方式(掩码/哈希/删除/保留) → 写入审计日志 |
| C3 | 就地分析 | 🟢 P2 | 2-3d | 统计摘要栏(COUNT/SUM/AVG/MIN/MAX/MEDIAN)，点击统计值→生成查询 SQL，拖拽分组 |

---

## 四、执行路线

```
阶段 1（2-3 周）              阶段 2（2-4 周）           阶段 3（4-6 周）
锋利化                        闭环化                    精细化

A1 DML 拦截                   B1 Schema Diff 三栏       B3 快照管理
A2 EXPLAIN 预检               B2 同步+回滚              C3 就地分析
A3 超时熔断                    C1 一键图表               PRAGMA 探索器 (SL-2)
PG-1 Schema 优先导航           C2 PII 导出               SQLite 文件操作 (SL-3)
MY-1 进程列表                 扩展浏览器 (PG-2)          安全阈值配置 UI
SL-1 拖拽打开                 JSONB 浏览器 (PG-3)
                              存储引擎感知 (MY-2)
                              复制状态 (MY-3)

交付：用户感到安全             交付：工作流不离开工具      交付：高级场景覆盖
+ 三种数据库的独特体验                                       + 数据库特定深度完成
```

### 测试策略

| 层级 | 当前负担 | 瘦身后 |
|------|---------|--------|
| 全量 CI 集成测试数据库 | 9 种外部服务 | 5 种 |
| ES + Snowflake 测试 | 删除 | — |
| 新增测试（支柱 A/B/C） | — | ~15 个测试文件 |

### 不做清单

- 新增数据库类型（Oracle, DB2）— 广度已够
- Vim/Emacs 模式 — 用户基数小
- 团队协作/共享查询 — 需后端，偏离本地优先定位
- 仪表板/报表系统 — 一键图表覆盖 80%
- 内联编辑增强 — 美国企业偏好显式 UPDATE 可审计
- AI 对话增强 — 重心转向安全网+分析引擎

---

## 五、差异化定位

| 能力 | DataGrip | TablePlus | DBeaver | DbMaster |
|------|----------|-----------|---------|----------|
| 多数据库（8 种） | ✅ | ❌ (6) | ✅ | ✅ |
| 内置 AI | ✅ (JetBrains) | ❌ | ❌ | ✅ |
| 本地隐私优先 | ❌ | ✅ | ✅ | ✅ |
| DML 安全拦截 | ❌ | ❌ | ❌ | ✅ (支柱 A) |
| Schema Diff 闭环 | ⚠️ | ❌ | ⚠️ | ✅ (支柱 B) |
| PII 保护导出 | ❌ | ❌ | ❌ | ✅ (支柱 C) |
| PG 扩展浏览器 | ❌ | ❌ | ❌ | ✅ |
| PG JSONB 查看器 | ❌ | ❌ | ❌ | ✅ |
| MySQL 进程列表 | ⚠️ (手工 SQL) | ⚠️ | ⚠️ | ✅ (一键) |
| MySQL 复制监控 | ❌ | ❌ | ❌ | ✅ |
| SQLite 拖拽打开 | ❌ | ❌ | ❌ | ✅ |
| SQLite PRAGMA 探索器 | ❌ | ❌ | ❌ | ✅ |
| Doris 支持 | ❌ | ❌ | ❌ | ✅ |
| TDengine 支持 | ❌ | ❌ | ❌ | ✅ |

**一句话定位**：面向美国市场的本地优先数据库客户端，AI 驱动的安全网 + 分析引擎，唯一同时支持 Doris 和 TDengine 的工具。

---

*文档版本: v3.0 · 2026-07-08*
