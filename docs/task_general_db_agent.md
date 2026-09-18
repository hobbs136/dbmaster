# 任务：通用数据库 Agent（FK 能力 + 只读工具 + 跨轮记忆 + 提示词 agent 化）

> 状态：已完成（2026-09-03）
> 验收场景：AI 面板发送「SELECT ... 我想删除这个 sql 查出来的数据，你帮我看看是否有关联的其他数据需要删除」——应在一轮内给出含子表分析、按依赖顺序排列的 DELETE 方案 + COUNT 预览。

## 1. 背景与根因

用户反馈 AI 助手对上述请求多轮给不出 DELETE 语句。探查结论（Agent 基础设施已完整：30 轮迭代循环 / 工具去重 / 并行执行 / checkpoint），缺口在四块：

| 要素 | 缺口 | 表现 |
|---|---|---|
| 眼 | 所有喂 AI 的 schema（getAiSchemaSummary / getCompactSchema / preloadedContext）均无外键 | AI 无法回答「有没有关联数据」，只能反问 |
| 手 | 无任意只读查询工具（get_table_schema 也不含 FK） | AI 不能自己查 information_schema / 数据样本 |
| 性格 | sqlPromptSafetyRule2a「必须先询问用户确认」被模型当对话动作 | 反复追问而非直接产出语句（确认本由客户端弹窗承担） |
| 记忆 | previousHistory 过滤掉全部 toolCall/toolResult | 每轮从零探索，越聊越糊涂 |

附带 bug：Pro 主路径（PromptBuilder 存在时）丢弃 preloadedContext，导致 C23「Schema 上下文开关」失效。

## 2. 实现（四块）

### B. 眼：外键关系能力
- `DatabaseAdapter.getReferencingForeignKeys(tableName)`（`database_abstract.dart`）：反向外键默认实现 = 遍历全表 getForeignKeys 过滤（表数 >200 返回空防 N+1；自引用保留；单表失败静默）；`DatabaseService` 门面转发。
- 快路径覆写：MySQL（KEY_COLUMN_USAGE 反查 + REFERENTIAL_CONSTRAINTS 取 ON DELETE/UPDATE，失败回退默认扫描）、PostgreSQL（table_constraints/constraint_column_usage + referential_constraints）。
- `AiAdapterMixin.getAiSchemaSummary` 目标表追加「Foreign Keys / Referenced By」两段（列映射 + ON DELETE 动作）——`get_table_schema` 工具与 `_buildPreloadedContext` 自动受益。
- 新工具 `get_table_relationships(table)`：双向 FK 关系 JSON（registry + handler）。

### A. 手：通用只读探索
- 新文件 `lib/services/ai/readonly_sql_validator.dart`：单语句 + 首关键字白名单（SELECT/WITH/SHOW/EXPLAIN/DESCRIBE/DESC/PRAGMA-仅SQLite只读名单）+ 黑名单子句（INTO/FOR UPDATE/FOR SHARE/LOCK IN SHARE MODE/:=）+ WITH/EXPLAIN 词级 DML 扫描（防 PG `WITH x AS (DELETE...)` 与 `EXPLAIN ANALYZE UPDATE`）+ 字符串字面量/注释掩码。
- 工具 `run_readonly_query`（SQL 六库）：校验 → 每 run 计数（上限 10，对齐 maxSqlExecutions 默认值）→ 截断回传（50 行 / 单元格 200 字符 / 总 8KB）。
- Mongo `find_documents_mongo`（aggregate $match/$limit/$project 组装 + countDocuments；管道由 handler 构造，模型无法注入 $out/$merge）；Redis `scan_keys` + `get_key`（type/ttl/按类型预览）。

### C. 性格：提示词（ai_service_localizations.dart，EN/zh 双语）
- sqlPromptSafetyRule2a 改写：「必须在本次回复中直接给出完整语句（<sql> 包裹）；执行确认由客户端确认弹窗完成，禁止用反复追问代替产出」；2b/2c 改为「在回复中附带」。
- 新 section「自主探索工作流」：信息不足先用工具查证；最多反问一次；SELECT→DML 的 WHERE 必须完全一致。
- 新 section「数据修改请求规范」：先 get_table_relationships 找子表 → 按依赖顺序多条 <sql>（子表→主表，CASCADE/SET NULL 说明无需手动处理）+ 每条 COUNT 预览 + JOIN 方言说明 + 假设声明。
- 默认提示词（路径 B）新增 systemPromptRule12（同义英文规则）。
- **修复 preloadedContext 丢弃**：`AiAgentService._getSystemPrompt` / `FreeChatRunner._getSystemPrompt` 在 PromptBuilder 路径追加 preloadedContext（`Database Context` 段）。

### D. 记忆：跨轮工具结果
- `AiSessionOrchestrator._buildPreviousHistory`：toolCall/toolResult 压缩为自描述摘要（`- call 工具(参数)` / `- result 工具: 摘要≤400字`）附到所属轮次 assistant 消息尾部；仅保留最近 3 轮；纯文本注入兼容所有 provider。

## 3. 安全模型（不变的部分）

- 工具面**全部只读**：白名单校验（拒即返回明确错误让模型换路）+ 各 adapter 只读连接守卫双保险。
- 写操作唯一路径仍是 `extractedCommands` + `validateCommand` 风险分级 + 确认弹窗执行门（带 WHERE 的 DELETE=warning 需确认；无 WHERE=dangerous 拒绝）。
- 防失控：每 run 只读查询 ≤10 次（叠加既有 maxToolCalls=20 / maxIterations=30）；结果截断防上下文膨胀。

## 4. 明确不做（后续迭代）

- 写操作工具化（AI 直接执行 DML）——维持执行门设计。
- 通用 agent 规划器/子任务分解。
- SQLParserService SELECT JOIN 解析增强（Agent 用只读查询自证）。

## 5. 测试与验证

- 单元测试 3 新文件 + 2 扩展，全绿：校验器 45 用例、FK 7 用例、工具 handler 15 用例、提示词 +4、跨轮记忆 4。用例清单见 `docs/test/unified_test_spec.md` §6.5（AI-AGENT-001..010）。
- 真实库集成 `integration_test/ai_agent_fk_readonly_e2e_test.dart`：SQLite 组 ✅；MySQL/PG 组依赖 192.168.x.x 测试库（2026-09-03 探测不可达，与基线集成测试同因挂起；服务器恢复后可直接 `DBMASTER_SERVER_BIN=dist/Release/dbmaster-server.exe flutter test -d windows integration_test/ai_agent_fk_readonly_e2e_test.dart`）。
- 人工验收（LLM 端到端，依赖 API key，不在 CI）：连真实库发原始场景消息，确认一轮内给出含子表分析、依赖顺序 DELETE + COUNT 预览的完整方案。

## 6. 关键文件

| 领域 | 文件 |
|---|---|
| 反向外键 | `lib/services/database_abstract.dart`、`database_service.dart`、`adapters/mysql_gateway_adapter.dart`、`adapters/postgresql_gateway_adapter.dart` |
| FK 进 AI 上下文 | `lib/services/adapters/ai_adapter_mixin.dart` |
| 只读校验器 | `lib/services/ai/readonly_sql_validator.dart`（新） |
| 工具 | `lib/pro/ai/database_tool_registry.dart`、`lib/pro/ai/ai_agent_service.dart` |
| 提示词 | `lib/services/ai/ai_service_localizations.dart`、`prompt_builders/sql_prompt_builder.dart`、`pro/ai/ai_agent_service.dart`、`services/free_chat_runner.dart` |
| 跨轮记忆 | `lib/services/ai_session_orchestrator.dart` |
