<!--
标题候选（择一）：
  主：让 AI 帮你写 SQL、建表、灌数据：DbMaster 的 AI Agent 实战
  备 1：8 种数据库一个 AI 助手：我用 Flutter 做了个能"自己干活"的 DB 工具
  备 2：不只是 GUI：把 AI 做成数据库工具的"一等公民"
掘金标签建议：Flutter / 数据库 / AI / 程序员工具 / ChatGPT
状态：打磨第 1 轮 2026-07-18。事实核查已对照代码完成（Agent 上限、tool calling 支持范围已修正）；GIF/截图位置用 🖼️ 占位，物料做好后替换。宣发定稿（B 方案·两篇旗舰）见 .workflows/dbmaster-launch-content/03-recommend.md。
发布前待办：填 GitHub 仓库链接；确认 AI 分析截图 + 两个 GIF 已替换占位。
-->

# 让 AI 帮你写 SQL、建表、灌数据：DbMaster 的 AI Agent 实战

## 写在前面：管多种数据库是什么体验

MySQL 用 Navicat、MongoDB 用 Studio 3T、Redis 用 RDM、TDengine 用 taosShell……一台机器装五六个客户端，快捷键各一套、SQL 方言各一套。更要命的是写 SQL 本身——复杂查询、性能调优、跨库迁移、造测试数据——这些活 IDE 帮不了你，你得自己想。

市面上的数据库工具基本都是"更好的 GUI"：连接更快、表格更漂亮、导出更方便。但它们都把最耗脑子的活留给了你：**理解 schema、写 SQL、排查问题、迁移数据**。

DbMaster 想干的事不太一样：**让 AI 替你干这些"耗脑子的活"**——不是挂一个对话框敷衍了事，而是把 AI 做成工具的"一等公民"，能读懂你的库、写出你要的 SQL、甚至自己跑完一整套任务。

## DbMaster 是什么

一句话：一个 Flutter 写的桌面 App，统一管理 **8 种数据库**——MySQL、PostgreSQL、SQLite、MongoDB、Redis、Doris、TDengine、SQL Server——外加一个**深度集成的 AI 助手**。

> 8 种库分两类：核心 6 个（MySQL / PG / SQLite / Mongo / Redis / SQL Server）+ 差异化 2 个（Doris / TDengine，OLAP + 时序，国内场景常用）。

但这篇文章不打算讲"我又写了第 N 个数据库 GUI"——GUI 人人会做。我想讲的是**它的 AI 是怎么做的，以及为什么这样做**。

## AI 集成：不是挂个对话框

很多工具的"AI 功能"长这样：旁边塞个 ChatGPT 框，你把报错粘进去，它给你吐一段解释。这本质上是"把网页版 ChatGPT 嵌进来"，AI 对你的数据库一无所知。

DbMaster 的 AI 不一样，它分三层。

### 第一层：带着"库上下文"对话

你和 AI 说"帮我看看 users 表最近的订单"，它不会反问"你有哪些表"——因为它**已经知道**。每次对话，系统会把当前连接的 schema（库、表、列、类型、主键、索引）按 token 预算压缩后注入 prompt。每种数据库还有**专属的 prompt 构造器和响应解析器**：Mongo 的查询是 `db.col.find()`，Redis 是 `GET/HGET`，SQL 是 `SELECT`——AI 拿到的上下文和被要求吐出的格式，是按你连的库裁剪过的。

这一层的能力：

- **NL2SQL（自然语言转查询）**："查出 30 天没下单的用户" → 它给你 `<sql>` 包好的 SELECT。
- **解释结果 / 解释报错**：结果面板一个按钮，按结果状态（成功 / 空 / 报错）给不同分析；侧边栏右键表 / 库也能直接"AI 分析"。
- **查询优化建议**：跑 EXPLAIN → 启发式分析 → AI 解读成"你这里少索引、这里全表扫"。

> 🖼️ *占位：结果面板 AI 分析截图*

这一层已经能省掉大量"查 schema + 拼 SQL + 查报错"的来回。但它还是**你问一句、它答一句**。

### 第二层：AI 能"动手"了——生成即执行

真正有意思的从这里开始。DbMaster 的 AI 不只是把 SQL 写在聊天框里让你复制——**它能直接执行**。消息里的代码块右上角有个 ▶ 按钮，一键跑。

但"AI 直接改库"听着吓人，所以这里做了**两道安全门**：

1. **命令风险评级**：`DROP` / `TRUNCATE` / 无 `WHERE` 的 `DELETE` → dangerous；`INSERT/UPDATE/ALTER` → warning。dangerous 强制弹二次确认。
2. **DDL 影响分析**：AI 生成的任何 DDL（建表 / 改表 / 删表）会**自动触发一次影响分析**——告诉你这条改动会影响哪些依赖对象、风险等级，并**附上回滚脚本**。你看着影响报告点"确认"，它才真正执行。

这一层的能力：

- **生成 + 执行 DDL**："帮我设计一张操作日志表，带索引" → CREATE TABLE + 索引 + 影响报告 + 回滚脚本。
- **智能导入**：丢一个 CSV / JSON，它分析文件结构 → 推断字段类型 → **自动建表** → 灌数据。整个过程不用你手写一行 schema。
- **生成测试数据**："给 users 表造 500 条多语言假数据" → 用 faker 批量生成，可一键 INSERT。
- **批量写**：Mongo 文档批量导入、SQL 批量 INSERT。
- **触发后台导出**：让它把某张表导成 CSV，它建一个后台任务，跑完写文件。

> 🖼️ *占位：智能导入 GIF（文件 → 自动建表 → 入库）*

到这里，AI 已经是个**能改库的助手**了。但还有第三层，是我觉得最值得讲的。

### 第三层：AI Agent——给它一个目标，它自己跑完

这是 DbMaster AI 的王牌。前面两层是"你说一句、它做一步"；Agent 模式是**你给一个目标，它自己拆解、调工具、多步执行、自我验证**。

原理是 **tool calling（函数调用）**：模型不再只输出文字，而是能"调用工具"。DbMaster 注册了一组数据库工具——`list_tables`、`get_table_schema`、`analyze_query_performance`、`generate_test_data`、`smart_import`、`execute_sql`……AI 在一个循环里（上限 30 轮 / 20 次工具调用 / 100 次 SQL 执行）：

1. 看目标，决定先调哪个工具；
2. 拿到工具返回，决定下一步；
3. 直到任务完成或需要你确认危险操作。

举个真实场景。你说：**"给新项目搭一套测试库，建 users/orders 两张表，各灌 200 条假数据，然后查一下性能有没有问题。"**

Agent 会自己：

- `list_tables` 看现状 → `get_table_schema` 看结构（发现没有这两张表）→ 生成建表 DDL → 弹影响确认 → 你点确认 → 建表 → `generate_test_data` 造数据 → 批量 INSERT → `analyze_query_performance` 跑 EXPLAIN → 给你一份"users 表缺 email 索引"的优化报告。

中间任何 dangerous 操作它都会停下来等你确认；网络断了还能断点续传（agent checkpoint 落盘，回来点"继续"）。

> 🖼️ *占位：AI Agent 多步任务 GIF*

这是我觉得"AI 一等公民"该有的样子：**不是聊天框，是一个会干活的初级 DBA**。

## 几个工程决策（干货时间）

做这套 AI 集成时，有几个决策值得拎出来讲，给同样在做 AI + 工具的同学参考。

**1. 用户自带 API Key，不代收 token 费。**
DbMaster 不内置任何模型，用户填自己的 key（OpenAI / Claude / Gemini / DeepSeek / Kimi / Ollama 都行）。好处是双重的：用户**成本可控**（用自己的额度 / 本地模型），DbMaster **不碰 token 账单**；更重要的是——**你的数据库数据只发到你自己选的模型**，工具方不搭中间服务器经手你的 SQL。对一个要连生产库的工具，这个隐私姿态很关键。

**2. Tool calling 的 provider 差异是个坑。**
不是所有模型 API 的 tool calling 都长一个样。DbMaster 目前对 **OpenAI、DeepSeek、Kimi** 支持完整 Agent（tool calling 全链路：注册工具 → 模型决策调用 → 结果回灌 → 继续推理）；Claude（Anthropic Messages API）和 Gemini 的 tool 格式不同，正在补齐，目标是"不管你用哪家 key，Agent 体验一致"。做 AI + 工具的同学注意：**tool calling 的兼容性工作量，往往比对话本身还大**——早做矩阵测试，别假设"OpenAI 兼容"就等于"tool calling 也兼容"。

**3. 每种数据库一套 prompt + 解析器。**
这是"深度集成"的关键。Mongo 的 AI 不能按 SQL 思维回答，Redis 的 AI 得知道你在问 KV 还是 hash。把 prompt 模板和响应解析按数据库类型分开，AI 输出质量直接上一个台阶——远好于"一套通用 prompt 走天下"。

**4. 用 Flutter 做桌面，一套代码三平台。**
DbMaster 是 Flutter desktop，Windows / macOS / Linux 一套代码。AI 这层是纯 Dart（SSH 隧道也用纯 Dart 的 dartssh2，不 shell out），跨平台行为一致，也方便后面上 Mac App Store。

## 现状和路线

- **现状**：8 种库全部可用，AI 三层能力（对话 / 生成执行 / Agent）已实现，支持 6 家模型 provider。
- **即将上架**：Mac App Store（中美区），Free / Pro 两种。Free 永久可用（AI 助手每月 30 次），Pro 解锁**高级 AI**——Agent、生成执行 DDL、智能导入、测试数据生成、批量写、后台导出，就是前面第二、三层那些"会动手"的能力。
- **后面**：补齐 Claude / Gemini 的 Agent 支持、更多 AI 自动化（定时任务）、Windows 版。

## 写在最后

做 DbMaster 的初衷很简单：**数据库工具最该被自动化的不是 UI，而是那些重复的脑力活**——读懂结构、写 SQL、调优、造数据、搬数据。GUI 已经卷到头了，下一站的差别在 AI。

如果你也天天和数据库打交道，欢迎试试，也欢迎来 GitHub 提需求 / 拍砖。

> 📌 **下一篇预告**：拿一个具体场景开刀——丢给 AI 一个 CSV 文件，看它怎么自己分析结构、建表、把数据灌进去，全程不写一行 schema。《智能导入实战》敬请期待。

> 🔗 GitHub：`<仓库链接>`（待填）
> 🔗 下载（Mac App Store 即将上架）：`<链接>`（待填）
