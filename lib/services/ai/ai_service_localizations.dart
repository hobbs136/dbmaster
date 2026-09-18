import '../../models/ai_tree_node_context.dart' show AiTreeNodeType;

/// Service-layer localizations for AI-related text that needs to be
/// internationalized but doesn't have access to Flutter's BuildContext.
///
/// This class provides localized strings for:
/// - System prompts sent to AI models
/// - Tool execution result messages
/// - Error messages that appear in AI responses
class AiServiceLocalizations {
  final String locale;

  AiServiceLocalizations(this.locale);

  bool get _isChinese => locale == 'zh' || locale == 'zh_TW';

  /// 响应语言策略：仅简体中文(zh)回中文，其余(含 zh_TW)回英文。
  /// 与 [_isChinese] 不同——后者含 zh_TW，仅用于历史 system-prompt 文本渲染。
  bool get _respondsChinese => locale == 'zh';

  // ==========================================================================
  // System Prompt
  // ==========================================================================

  String get systemPromptIdentity =>
      'You are DbMaster AI, an intelligent database analysis assistant.';

  String get systemPromptContextLabel => 'Database Context';

  String get systemPromptRulesLabel => 'Important Rules';

  String get systemPromptRule1 =>
      'You can execute read-only queries through provided tools (e.g., EXPLAIN, COUNT, schema queries), but cannot execute DML/DDL (INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE) without explicit user confirmation.';

  String get systemPromptRule2 =>
      'All executable SQL statements must be wrapped in <sql> and </sql> tags.';

  String get systemPromptRule3 =>
      'Each executable statement must be wrapped individually with <sql>...</sql>.';

  String get systemPromptRule4 =>
      'Tags should contain pure SQL only, do not add markdown code block markers (e.g. ```sql).';

  String get systemPromptRule5 =>
      'You may use minimal natural language for brief explanations outside <sql> tags.';

  String get systemPromptRule6 =>
      'For database metadata, you can use tools to query table structures.';

  String get systemPromptRule7 =>
      'For write operations (DELETE/UPDATE/DROP etc.), mark potential risks in the explanation.';

  String get systemPromptRule8 =>
      'When generating test data, use the generate_test_data tool. It is available for all SQL databases. Returns INSERT statements that require explicit user confirmation before execution.';

  String get systemPromptRule9 =>
      'When user wants to import data, use smart_import to analyze first, then execute_import to perform the actual import after user confirmation. When exporting, use analyze_export first, then create_export_task after confirmation.';

  String get systemPromptRule10 =>
      'CRITICAL FORMAT RULE: All executable SQL must be wrapped in <sql>...</sql> tags. Do not use markdown code blocks (```sql) or <execute> tags. Each statement must be individually wrapped. Example: <sql>SELECT * FROM users WHERE id = 1</sql>';

  String get systemPromptRule11 =>
      'Before importing data, use analyze_data_quality to check for missing values, duplicates, and format issues. Report findings to user and recommend cleaning steps.';

  String get systemPromptRule12 =>
      'When the user asks to delete or update data, always produce the complete SQL statement(s) in the SAME reply (wrapped in <sql> tags) with a risk note and a SELECT COUNT(*) preview — execution confirmation is handled by the client, so never replace producing statements with repeated questions. When you need schema or relationship facts, explore first with read-only tools (get_table_relationships, run_readonly_query) instead of asking the user.';

  String get systemPromptDataRulesLabel => 'Data Generation Rules';

  String get systemPromptDataRule1 =>
      'Use generate_test_data tool to generate test data. Supports realistic faker data (names, emails, addresses) in multiple languages. Max 1000 rows per call.';

  String get systemPromptDataRule2 =>
      'For large datasets (>1000 rows), use multiple calls. Check current row count (get_table_row_count) to decide if more is needed.';

  String get systemPromptDataRule3 =>
      'By default, use realistic_mode=true and auto_execute=false so user can review before execution. Only use auto_execute=true when user explicitly requests direct insertion.';

  String get systemPromptDataRule4 =>
      'Match the app locale for generated data (en/zh/de/fr/ru). If unsure, use en.';

  String get systemPromptDataRule5 =>
      'Report progress to user after execution is complete';

  String get systemPromptPerfRulesLabel => 'Performance Rules';

  String get systemPromptPerfRule1 =>
      'Avoid unconditional COUNT(*) (triggers full table scan in InnoDB)';

  String get systemPromptPerfRule2 =>
      'Avoid SELECT *, explicitly list required fields';

  String get systemPromptPerfRule3 =>
      'For large table deep pagination, use deferred join instead';

  String get systemPromptPerfRule4 =>
      'UPDATE/DELETE must have WHERE condition and use index';

  String get systemPromptCurrentDbLabel => 'Current database context';

  /// 响应语言策略：仅简体中文(zh)回简体中文，其余(含 zh_TW)一律英文。
  String get systemPromptLanguageInstruction => locale == 'zh'
      ? '请始终使用简体中文回答用户。'
      : 'Always respond to the user in English.';

  String systemPromptForDbType(String dbType) {
    switch (dbType.toLowerCase()) {
      case 'mysql':
        return 'Please use standard MySQL syntax, prioritize index utilization and LIMIT restrictions, provide performance optimization suggestions.';
      case 'postgresql':
        return 'Please use PostgreSQL syntax, make good use of JSONB operators, CTE and window functions, provide performance optimization suggestions.';
      case 'sqlite':
        return 'Please use SQLite syntax, note its type affinity mechanism, limited data type support (INTEGER/REAL/TEXT/BLOB/NULL), and restrictions such as no ALTER TABLE DROP COLUMN support, provide performance optimization suggestions.';
      case 'doris':
        return 'Please use Apache Doris syntax, focus on aggregation models and Rollup/materialized views, provide performance optimization suggestions.';
      case 'mongodb':
        return 'Please generate MongoDB queries. find example: find(users, {"age": {"\$gt": 18}}). aggregate example: aggregate(orders, [{"\$match": {"status": "done"}}, {"\$group": {"_id": null, "total": {"\$sum": 1}}}]), provide performance optimization suggestions.';
      case 'redis':
        return 'Please use Redis command format, note command time complexity, provide performance optimization suggestions.';
      case 'tdengine':
        return 'Please use TDengine SQL syntax, note the differences between super tables, sub tables, tags and normal columns, provide performance optimization suggestions.';
      default:
        return 'Please provide performance optimization suggestions.';
    }
  }

  // ==========================================================================
  // Error Messages (shown directly to users)
  // ==========================================================================

  String toolCallLimitReached(int count) => _isChinese
      ? 'AI助手已达到工具调用上限（$count次）。请简化您的问题，或分步进行操作。'
      : 'AI assistant has reached the tool call limit ($count times). Please simplify your question or proceed step by step.';

  String get maxIterationsReached => _isChinese
      ? 'Agent 达到最大迭代次数，未能完成对话。'
      : 'Agent reached maximum iterations and could not complete the conversation.';

  String get duplicateQuery => _isChinese
      ? '该查询已执行过，请基于已有结果直接回答，不要重复查询相同信息。'
      : 'This query has already been executed. Please answer directly based on the existing results without repeating the query.';

  String toolExecutionFailed(String error) =>
      _isChinese ? '工具执行失败: $error' : 'Tool execution failed: $error';

  String unknownTool(String name) =>
      _isChinese ? '未知工具: $name' : 'Unknown tool: $name';

  // ==========================================================================
  // Tool Result Messages (shown in AI context)
  // ==========================================================================

  String dataGenerated(String table, int count) => _isChinese
      ? '已为表 [$table] 生成 $count 条测试数据。'
      : 'Generated $count test data rows for table [$table].';

  String get insertStatementsGenerated => _isChinese
      ? '生成的 INSERT SQL 语句（未执行）:'
      : 'Generated INSERT SQL statements (not executed):';

  String get executionNote => _isChinese
      ? '说明：这些 INSERT 语句需要用户确认后才会执行。'
      : 'Note: These INSERT statements require user confirmation before execution.';

  String get continueGeneratingNote => _isChinese
      ? '你可以继续生成更多数据，或请求用户确认执行。'
      : 'You can continue generating more data, or ask the user to confirm execution.';

  String tableRowCount(String table, int count) => _isChinese
      ? '表 [$table] 当前有 $count 行数据。'
      : 'Table [$table] currently has $count rows of data.';

  String get filePathRequired =>
      _isChinese ? '文件路径不能为空' : 'File path cannot be empty';

  String fileAnalysisFailed(String error) =>
      _isChinese ? '文件分析失败: $error' : 'File analysis failed: $error';

  String affectedRows(int count) =>
      _isChinese ? '受影响行数: $count' : 'Affected rows: $count';

  // ==========================================================================
  // Smart Import Messages
  // ==========================================================================

  String get smartImportTitle =>
      _isChinese ? '【文件分析结果】' : '[File Analysis Result]';

  String smartImportFile(String name) =>
      _isChinese ? '文件: $name' : 'File: $name';

  String smartImportFormat(String format) =>
      _isChinese ? '格式: $format' : 'Format: $format';

  String smartImportEncoding(String encoding) =>
      _isChinese ? '编码: $encoding' : 'Encoding: $encoding';

  String smartImportDelimiter(String delimiter) =>
      _isChinese ? '分隔符: "$delimiter"' : 'Delimiter: "$delimiter"';

  String smartImportFieldCount(int count) =>
      _isChinese ? '字段数: $count' : 'Field count: $count';

  String smartImportSampleRows(int count) =>
      _isChinese ? '样本行数: $count' : 'Sample rows: $count';

  String smartImportEstimatedRows(int? rows) =>
      _isChinese ? '估计总行数: ~$rows' : 'Estimated total rows: ~$rows';

  String get smartImportFields => _isChinese ? '【字段列表】' : '[Field List]';

  String smartImportField(String field, String type) =>
      _isChinese ? '- $field: $type' : '- $field: $type';

  String get smartImportSampleData =>
      _isChinese ? '【样本数据（前3行）】' : '[Sample Data (first 3 rows)]';

  String get smartImportTargetTable =>
      _isChinese ? '【目标表状态】' : '[Target Table Status]';

  String smartImportSuggestedTableName(String name) =>
      _isChinese ? '建议表名: $name' : 'Suggested table name: $name';

  String get smartImportTableExists =>
      _isChinese ? '表状态: 已存在' : 'Table status: Exists';

  String get smartImportTableNotExists => _isChinese
      ? '表状态: 不存在（将自动创建）'
      : 'Table status: Does not exist (will be created automatically)';

  String smartImportExistingRows(int count) =>
      _isChinese ? '现有行数: $count' : 'Existing rows: $count';

  String smartImportDataDuplicateWarning(int count) => _isChinese
      ? '警告: 目标表已存在且包含 $count 行数据！直接导入可能会导致数据重复。请询问用户是否：'
      : 'Warning: Target table already exists and contains $count rows of data! Direct import may cause data duplication. Please ask the user whether to:';

  String get smartImportOptionOverwrite => _isChinese
      ? '1. 覆盖（删除现有表并重建）'
      : '1. Overwrite (delete existing table and recreate)';

  String get smartImportOptionAppend =>
      _isChinese ? '2. 追加（在现有数据后追加）' : '2. Append (add after existing data)';

  String get smartImportOptionCancel =>
      _isChinese ? '3. 取消导入' : '3. Cancel import';

  String get smartImportSuggestedSQL =>
      _isChinese ? '【建议的建表语句】' : '[Suggested CREATE TABLE Statement]';

  String get smartImportSuggestedSQLNote => _isChinese
      ? '基于文件分析，建议的 CREATE TABLE 语句如下：'
      : 'Based on file analysis, suggested CREATE TABLE statement:';

  String get smartImportExecuteNote => _isChinese
      ? '说明：请生成 CREATE TABLE 语句并用 <sql> 标签包裹，用户确认后执行。'
      : 'Note: Please generate CREATE TABLE statement wrapped in <sql> tags, executed after user confirmation.';

  String get smartImportLargeFileNote => _isChinese
      ? '注：该文件较大，建议使用分批导入方式。'
      : 'Note: This file is large, batch import is recommended.';

  // ==========================================================================
  // Context Builder Messages
  // ==========================================================================

  String contextCurrentDatabase(String name) =>
      _isChinese ? '当前数据库: $name' : 'Current database: $name';

  String contextCurrentTable(String name) =>
      _isChinese ? '当前表: $name' : 'Current table: $name';

  String contextRecentQueries(String queries) =>
      _isChinese ? '最近查询: $queries' : 'Recent queries: $queries';

  String contextGoalSummary(String summary) => _isChinese
      ? '当前会话目标摘要：$summary'
      : 'Current session goal summary: $summary';

  String get summarizePrompt => _isChinese
      ? '''请用1-2句话总结以下对话的当前任务目标和约束条件：

{messages}

摘要格式：
当前任务：<一句话描述>
约束：<如果有数据库、表、语法等约束请列出>'''
      : '''Please summarize the current task goal and constraints of the following conversation in 1-2 sentences:

{messages}

Summary format:
Current task: <one sentence description>
Constraints: <list database, table, syntax constraints if any>''';

  String earlierContext(String summary) =>
      _isChinese ? 'Earlier context: $summary' : 'Earlier context: $summary';

  // ==========================================================================
  // SqlPromptService Localizations
  // ==========================================================================

  String get sqlPromptRoleTitle => _isChinese ? '# Role' : '# Role';

  String get sqlPromptRoleIdentity => _isChinese
      ? '你是DbMaster AI，一个谨慎的数据库分析助手。'
      : 'You are DbMaster AI, a cautious database analysis assistant.';

  String get sqlPromptRoleWorkflow =>
      _isChinese ? '你的工作方式是：' : 'Your workflow:';

  String get sqlPromptRoleStep1 =>
      _isChinese ? '1. 分析用户意图' : '1. Analyze user intent';

  String get sqlPromptRoleStep2 => _isChinese
      ? '2. 生成SQL语句供用户审阅'
      : '2. Generate SQL statements for user review';

  String get sqlPromptRoleStep3 => _isChinese
      ? '3. 提供执行计划和风险提示'
      : '3. Provide execution plan and risk warnings';

  String get sqlPromptRoleStep4 => _isChinese
      ? '4. 让用户决定是否执行（通过"在新查询中打开"按钮）'
      : '4. Let the user decide whether to execute (via "Open in New Query" button)';

  String get sqlPromptSafetyRulesTitle => _isChinese
      ? '# Safety Rules (NEVER violate)'
      : '# Safety Rules (NEVER violate)';

  String get sqlPromptSafetyRule1 => _isChinese
      ? '1. 你可以通过提供的工具执行只读查询（如EXPLAIN、COUNT、Schema查询），但DML/DDL（INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE）必须经用户显式确认后才能执行'
      : '1. You can execute read-only queries through provided tools (e.g., EXPLAIN, COUNT, Schema queries), but DML/DDL (INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE) requires explicit user confirmation before execution';

  String get sqlPromptSafetyRule2Prefix => _isChinese
      ? '2. 对于DML/DDL（INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE）：'
      : '2. For DML/DDL (INSERT/UPDATE/DELETE/DROP/ALTER/TRUNCATE):';

  String get sqlPromptSafetyRule2a => _isChinese
      ? '   - 必须在本次回复中直接给出完整的可执行语句（用 <sql> 标签包裹）；执行确认由客户端的确认弹窗完成，禁止用反复追问代替产出'
      : '   - Always output the complete executable statement(s) in the same reply (wrapped in <sql> tags); execution confirmation is handled by the client\'s confirm dialog — never replace producing statements with asking questions';

  String get sqlPromptSafetyRule2b => _isChinese
      ? '   - 在回复中附带对应的 SELECT COUNT(*) 语句，供用户预览影响行数'
      : '   - Include a corresponding SELECT COUNT(*) statement in the reply so the user can preview affected rows';

  String get sqlPromptSafetyRule2c => _isChinese
      ? '   - 建议用户执行前先运行 SELECT 查看数据样本'
      : '   - Suggest running a SELECT first to view a data sample before executing';

  String get sqlPromptSafetyRule3 => _isChinese
      ? '3. 绝不假设表结构存在，未知表必须先查询元数据'
      : '3. Never assume table structure exists; unknown tables must query metadata first';

  String get sqlPromptSafetyRule4 => _isChinese
      ? '4. 始终优先只读操作（SELECT/EXPLAIN/SHOW）'
      : '4. Always prioritize read-only operations (SELECT/EXPLAIN/SHOW)';

  String get sqlPromptExplorationTitle => _isChinese
      ? '# 自主探索（Agent 工作方式）'
      : '# Autonomous Exploration (Agent Workflow)';

  String get sqlPromptExplorationRules => _isChinese
      ? '1. 信息不足时，先用只读工具自行查证再回答，不要凭空猜测，也不要把问题抛回给用户：\n'
            '   - 表间关系/外键 → `get_table_relationships`\n'
            '   - 表结构 → `get_table_schema`；数据样本/行数/元数据（如 information_schema） → `run_readonly_query`\n'
            '2. 最多向用户反问一次；若仍缺信息，基于已知 schema 做出最合理的假设并直接给出方案，同时显式声明假设\n'
            '3. 用户要求「删除/更新某条 SELECT 查出的数据」时，WHERE 条件必须与原查询完全一致，不得扩大或缩小范围'
      : '1. When information is missing, verify it yourself with read-only tools instead of guessing or bouncing the question back:\n'
            '   - Table relationships / foreign keys → `get_table_relationships`\n'
            '   - Table structure → `get_table_schema`; data samples / row counts / metadata (e.g. information_schema) → `run_readonly_query`\n'
            '2. Ask the user at most ONE clarifying question; if information is still missing, make the most reasonable assumption from the known schema, produce the answer, and state the assumption explicitly\n'
            '3. When the user asks to delete/update rows returned by a SELECT, keep the WHERE conditions EXACTLY the same as the original query — never widen or narrow the scope';

  String get sqlPromptDataModTitle => _isChinese
      ? '# 数据修改请求（DELETE / UPDATE）'
      : '# Data Modification Requests (DELETE / UPDATE)';

  String get sqlPromptDataModRules => _isChinese
      ? '当用户要删除或更新数据（尤其是「删除某条 SELECT 查出的数据」）时，必须在一次回复中给出完整方案：\n'
            '1. 先用 `get_table_relationships` 找出引用目标表的子表（incoming references）及其 ON DELETE 动作\n'
            '2. 给出按依赖顺序排列的多条语句（每条单独用 <sql> 包裹）：\n'
            '   - CASCADE / SET NULL 覆盖的子表：说明无需手动处理\n'
            '   - RESTRICT / NO ACTION 的子表：先给子表 DELETE（WHERE 语义与原查询一致），再给主表 DELETE\n'
            '   - 每条 DELETE 附带对应的 SELECT COUNT(*) 预览语句\n'
            '3. 原查询含 JOIN 时说明方言差异：MySQL 支持多表 DELETE；通用做法是 `DELETE FROM t WHERE id IN (SELECT ...)` 子查询\n'
            '4. 外键信息不可用时，声明假设并建议用户核实'
      : 'When the user wants to delete or update data (especially "delete the rows returned by this SELECT"), deliver the complete plan in ONE reply:\n'
            '1. First call `get_table_relationships` to find tables referencing the target table (incoming references) and their ON DELETE actions\n'
            '2. Provide statements ordered by dependency (each wrapped in its own <sql> tag):\n'
            '   - Child tables covered by CASCADE / SET NULL: state that no manual handling is needed\n'
            '   - Child tables under RESTRICT / NO ACTION: give the child DELETE first (WHERE semantics consistent with the original query), then the main-table DELETE\n'
            '   - Include a SELECT COUNT(*) preview for every DELETE\n'
            '3. If the original query contains JOINs, explain dialect differences: MySQL supports multi-table DELETE; the portable approach is a `DELETE FROM t WHERE id IN (SELECT ...)` subquery\n'
            '4. When FK information is unavailable, state your assumptions and suggest verification';

  String get sqlPromptContextTitle => _isChinese
      ? '# Context You Have Access To'
      : '# Context You Have Access To';

  String get sqlPromptContextConnection =>
      _isChinese ? 'Active connection' : 'Active connection';

  String get sqlPromptContextInstance =>
      _isChinese ? 'Instance name' : 'Instance name';

  String get sqlPromptContextDatabase =>
      _isChinese ? 'Current database' : 'Current database';

  String get sqlPromptSchemaTitle =>
      _isChinese ? '# Database Schema' : '# Database Schema';

  String get sqlPromptResponseFormatTitle =>
      _isChinese ? '# Response Format' : '# Response Format';

  String get sqlPromptResponseAnalysis => _isChinese
      ? '1. **Analysis**: 简要分析用户需求'
      : '1. **Analysis**: Briefly analyze user requirements';

  String get sqlPromptResponseQuery => _isChinese
      ? '2. **Query**: SQL语句，必须用 <sql> 和 </sql> 标签包裹'
      : '2. **Query**: SQL statements must be wrapped in <sql> and </sql> tags';

  String get sqlPromptResponseExecutionPlan => _isChinese
      ? '3. **Execution Plan**: 索引使用、预估成本、扫描方式'
      : '3. **Execution Plan**: Index usage, estimated cost, scan method';

  String get sqlPromptResponseWarning => _isChinese
      ? '4. **Warning**: 风险提示（锁表、大数据量、缺失索引等）'
      : '4. **Warning**: Risk warnings (table locks, large data volume, missing indexes, etc.)';

  String get sqlPromptSqlTagTitle => _isChinese
      ? '## SQL Tag Format (MUST follow)'
      : '## SQL Tag Format (MUST follow)';

  String get sqlPromptSqlTagRule1 => _isChinese
      ? '- 【强制】所有可执行SQL语句必须用 <sql> 和 </sql> 标签包裹，否则无法被提取执行'
      : '- [MANDATORY] All executable SQL must be wrapped in <sql> and </sql> tags, otherwise they cannot be extracted for execution';

  String get sqlPromptSqlTagRule2 => _isChinese
      ? '- 每条语句单独用 <sql>...</sql> 包裹'
      : '- Each statement must be individually wrapped with <sql>...</sql>';

  String get sqlPromptSqlTagRule3 => _isChinese
      ? '- 标签内只包含纯SQL，不要加markdown代码块'
      : '- Tags should contain pure SQL only, do not add markdown code blocks';

  String get sqlPromptSqlTagRule4 => _isChinese
      ? '- 多条语句使用多个 <sql> 标签'
      : '- Multiple statements use multiple <sql> tags';

  String get sqlPromptSqlTagRule5 => _isChinese
      ? '- 标签外可用极简自然语言说明'
      : '- Minimal natural language explanations allowed outside tags';

  String get sqlPromptSqlTagRule6 => _isChinese
      ? '- 禁止使用 ```sql markdown代码块'
      : '- Prohibit using ```sql markdown code blocks';

  String get sqlPromptSqlTagRule7 => _isChinese
      ? '- 正确示例：\u003csql\u003eSELECT * FROM users WHERE id = 1\u003c/sql\u003e'
      : '- Correct example: \u003csql\u003eSELECT * FROM users WHERE id = 1\u003c/sql\u003e';

  String get sqlPromptSyntaxTitle =>
      _isChinese ? '## Syntax Guidelines' : '## Syntax Guidelines';

  String get sqlPromptSyntaxStandard => _isChinese ? '标准语法' : 'standard syntax';

  String get sqlPromptSyntaxQuoteChar => _isChinese
      ? '表名/字段名使用正确引用符'
      : 'Use correct quote characters for table/column names';

  String get sqlPromptSyntaxStringQuote => _isChinese
      ? '字符串使用单引号，标识符使用'
      : 'Use single quotes for strings, use quote characters for identifiers';

  String get sqlPromptExampleTitle => _isChinese ? '## Example' : '## Example';

  String get sqlPromptExampleUserQuery =>
      _isChinese ? '查询最近7天注册用户' : 'Query users registered in the last 7 days';

  String get sqlPromptExampleAnalysis => _isChinese
      ? '用户想查询最近7天的注册用户'
      : 'User wants to query users registered in the last 7 days';

  String get sqlPromptExampleExecutionPlan => _isChinese
      ? '使用created_at索引（如存在），range扫描'
      : 'Use created_at index (if exists), range scan';

  String get sqlPromptExampleWarning => _isChinese
      ? '🔵 只读操作。如created_at无索引，将触发全表扫描'
      : '🔵 Read-only operation. If created_at has no index, will trigger full table scan';

  String get sqlPromptToneTitle => _isChinese ? '# Tone' : '# Tone';

  String get sqlPromptToneRule1 =>
      _isChinese ? '- 技术但易懂' : '- Technical but easy to understand';

  String get sqlPromptToneRule2 => _isChinese
      ? '- 不确定时询问schema信息而非猜测'
      : '- Ask for schema information when uncertain, rather than guessing';

  String get sqlPromptToneRule3 => _isChinese
      ? '- 性能问题要具体（索引使用、行数预估）'
      : '- Be specific about performance issues (index usage, row count estimation)';

  String get sqlPromptSchemaRemainingTables => _isChinese ? '还有' : 'more';

  String get sqlPromptSchemaTablesSuffix => _isChinese ? '个表' : 'tables';

  // ==========================================================================
  // AppProvider AI-analysis entry-point prompts
  // （sendAiAnalysis / analyzeTreeNodeWithAi / analyzeErrorWithAi /
  //  analyzeExecutionResultWithAi 发给模型的用户提示文本，按响应语言策略切换）
  // ==========================================================================

  // --- sendAiAnalysis：查询结果分析 ---
  String get analyzeQueryHeader => _respondsChinese
      ? '请分析以下 SQL 查询及其结果：'
      : 'Please analyze the following SQL query and its result:';

  String get resultSummaryLabel =>
      _respondsChinese ? '结果摘要：' : 'Result summary:';

  String get analyzeQueryPerformanceAsk => _respondsChinese
      ? '请从性能、索引建议、查询优化等方面给出分析。'
      : 'Please analyze it in terms of performance, index recommendations, and query optimization.';

  // --- analyzeWeeklyReportWithAi：慢查询周报分析（#29 M3 / ADR-0007）---
  String get analyzeWeeklyHeader => _respondsChinese
      ? '请分析以下慢查询周报（数据来自 dbmaster server 的慢查询采样）：'
      : 'Please analyze the following slow-query weekly report (sampled by the dbmaster server):';

  String get analyzeWeeklyAsk => _respondsChinese
      ? '请总结主要瓶颈（Top 查询 / 天分布 / 连接分布），并对最慢的查询形态给出优化方向。'
      : 'Summarize the main bottlenecks (top queries / daily distribution / connections) and suggest optimization directions for the slowest query shapes.';

  // --- analyzeTreeNodeWithAi：侧边栏节点分析 ---
  String nodeTypeLabel(AiTreeNodeType type) {
    switch (type) {
      case AiTreeNodeType.table:
        return _respondsChinese ? '数据表' : 'table';
      case AiTreeNodeType.database:
        return _respondsChinese ? '数据库' : 'database';
      case AiTreeNodeType.connection:
        return _respondsChinese ? '服务器' : 'server';
      default:
        return _respondsChinese ? '数据库对象' : 'database object';
    }
  }

  String analyzeTreeNodeHeader(String nodeType, String displayLabel) =>
      _respondsChinese
      ? '请分析以下 $nodeType `$displayLabel`：'
      : 'Please analyze the following $nodeType `$displayLabel`:';

  String get analyzeTreeNodeAsk => _respondsChinese
      ? '请从结构合理性、索引设计、潜在优化点、可能存在的问题等方面给出分析建议。'
      : 'Please provide analysis and suggestions on structural soundness, index design, potential optimizations, and possible issues.';

  // --- analyzeErrorWithAi：错误诊断 ---
  String get analyzeErrorHeader => _respondsChinese
      ? '请诊断下面的数据库错误：说明可能的原因，并给出排查与修复建议。'
      : 'Please diagnose the following database error: explain possible causes and provide troubleshooting and fix suggestions.';

  String get errorInfoLabel => _respondsChinese ? '错误信息：' : 'Error message:';

  String get relatedSqlLabel => _respondsChinese ? '相关 SQL：' : 'Related SQL:';

  // --- analyzeExecutionResultWithAi：执行结果分析（成功/空/错误三分支） ---
  String get executionFailedLabel =>
      _respondsChinese ? '执行失败，错误信息：' : 'Execution failed. Error message:';

  String get unknownErrorLabel => _respondsChinese ? '未知错误' : 'Unknown error';

  String get analyzeSqlErrorAsk => _respondsChinese
      ? '请分析该 SQL 错误的原因，并给出排查和修复建议。'
      : 'Please analyze the cause of this SQL error and provide troubleshooting and fix suggestions.';

  String get emptyResultHeader => _respondsChinese
      ? '该 SQL 执行成功，但返回结果为空。'
      : 'The SQL executed successfully but returned an empty result.';

  String executionTimeLabel(int ms) =>
      _respondsChinese ? '耗时: ${ms}ms' : 'Elapsed: ${ms}ms';

  String get analyzeEmptyResultAsk => _respondsChinese
      ? '请分析可能导致空结果的原因，并给出排查建议。'
      : 'Please analyze possible causes of the empty result and provide troubleshooting suggestions.';

  String rowsReturnedLabel(int count) =>
      _respondsChinese ? '返回 $count 行数据' : 'Returned $count rows';

  String truncatedLabel(int limit) => _respondsChinese
      ? '结果已截断，限制为前 $limit 行'
      : 'Result truncated, limited to the first $limit rows';

  String columnsLabel(List<String> columns) => _respondsChinese
      ? '列：${columns.join(', ')}'
      : 'Columns: ${columns.join(', ')}';

  // --- 会话标题（AI 面板可见）---
  String aiSessionTitleNode(String label) =>
      _respondsChinese ? 'AI 分析：$label' : 'AI Analysis: $label';

  String get aiSessionTitleError =>
      _respondsChinese ? 'AI 分析：错误诊断' : 'AI Analysis: Error Diagnosis';

  String get aiSessionTitleQueryResult =>
      _respondsChinese ? 'AI 分析：查询结果' : 'AI Analysis: Query Result';

  // ==========================================================================
  // User-facing service-layer messages (shown in the AI panel / session list)
  // 不同于发给模型的提示（_respondsChinese 仅 zh），这些用户可见串按 _isChinese
  // （zh + zh_TW）→中文，其余→英文，与既有 user-facing 文案一致。
  // ==========================================================================

  /// 配额耗尽提示（_checkAiQuota）。
  String get aiQuotaExhaustedUpgradePrompt => _isChinese
      ? '本月 Free AI 配额已用完，升级 Pro 可无限使用。'
      : 'The monthly Free AI quota has been used up. Upgrade to Pro for unlimited usage.';

  /// 未连接数据库，无法分析（sendAiAnalysis/analyzeTreeNodeWithAi 等入口）。
  String get aiAnalysisNoConnection => _isChinese
      ? '未连接到数据库，无法进行分析。'
      : 'Not connected to a database — analysis cannot proceed.';

  /// AI API Key 未配置。
  String get errorAiApiKeyMissing => _isChinese
      ? '请先配置 AI API Key。'
      : 'Please configure the AI API key first.';

  /// 收集节点上下文失败（catch 兜底，$error 为内部异常文本）。
  String errorAiCollectNodeContextFailed(String error) =>
      _isChinese ? '收集节点信息失败: $error' : 'Failed to collect node info: $error';

  /// 新建会话默认标题。
  String newChatTitle(int n) => _isChinese ? '新对话 $n' : 'New Chat $n';

  /// 分支会话标题。
  String branchSessionTitle(String preview) =>
      _isChinese ? '基于: $preview' : 'Based on: $preview';

  /// 摘要：空对话兜底。
  String get summaryEmptyConversation =>
      _isChinese ? '空对话' : 'Empty conversation.';

  /// 摘要：默认兜底文案。
  String get summaryDefaultFallback =>
      _isChinese ? '关于数据库操作的对话' : 'A conversation about database operations.';

  /// INSERT 执行被用户取消。
  String get aiInsertExecutionCancelled => _isChinese
      ? '用户已取消 INSERT 语句的执行。生成的 SQL 已保留在对话中，可手动执行。'
      : 'User cancelled the execution of INSERT statements. The generated SQL has been preserved in the conversation and can be executed manually.';

  /// 任务中断（有 checkpoint），提示可继续；$error 为内部异常。
  String taskInterruptedResumeHint(String error) => _isChinese
      ? '任务已中断。点击“继续”从中断处恢复。\n\n错误: $error'
      : 'Task interrupted. Click "Continue" to resume from where it was interrupted.\n\nError: $error';

  /// 任务失败但已保存部分内容，可凭 requestId 恢复。
  String errorPartialContentSaved(String error, String requestId) => _isChinese
      ? '发生错误: $error\n\n已保存已接收的内容。可使用请求 ID 恢复: $requestId'
      : 'An error occurred: $error\n\nReceived content has been saved. You can resume using request ID: $requestId';

  /// 通用失败兜底。
  String genericErrorOccurred(String error) =>
      _isChinese ? '发生错误: $error' : 'An error occurred: $error';

  /// 恢复后再次中断。
  String resumeInterruptedAgain(String error) => _isChinese
      ? '恢复后任务再次中断。点击“继续”重试。\n\n错误: $error'
      : 'Task was interrupted again after resuming. Click "Continue" to try again.\n\nError: $error';

  /// 恢复失败。
  String resumeFailed(String error) =>
      _isChinese ? '恢复失败: $error' : 'Resume failed: $error';

  /// 导出任务描述。
  String exportTaskDescription(String table, String format) =>
      _isChinese ? '导出 $table 为 $format' : 'Export $table to $format';

  /// 请求超时（orchestrator 捕获 TimeoutException 时使用）。
  String get requestTimeout => _isChinese
      ? '请求超时，请检查网络连接或增加超时时间。'
      : 'Request timed out. Please check the network connection or increase the timeout.';

  // ==========================================================================
  // p3: AI-facing tool-result / prompt / context strings (zh<->en via _isChinese)
  // ==========================================================================

  String get aiSummaryConversationDigestHeader => _isChinese
      ? "这是一个数据库AI助手的对话摘要:"
      : "This is a summary of a database AI assistant conversation:";
  String aiSummaryMoreMessagesHint(int count) =>
      _isChinese ? "... 共 $count 条消息" : "... $count messages in total";
  String get aiSummaryRoleUser => _isChinese ? "用户" : "User";
  String get aiSummarySummarizePrompt => _isChinese
      ? "请为以下对话生成一个简短的摘要(不超过50字):"
      : "Please generate a brief summary (max 50 characters) for the following conversation:";
  String analyzeQueryPerformanceFailed(String error) => _isChinese
      ? "分析查询性能失败: $error"
      : "Failed to analyze query performance: $error";
  String analyzeSchemaImpactFailed(String error) => _isChinese
      ? "分析架构影响失败: $error"
      : "Failed to analyze schema impact: $error";
  String get collectionNameRequired =>
      _isChinese ? "集合名称不能为空" : "Collection name is required";
  String dataQualityFieldsLabel(int count) =>
      _isChinese ? "**字段数：** $count" : "**Fields:** $count";
  String get dataQualityIssuesFoundLabel =>
      _isChinese ? "**发现的问题：**" : "**Issues Found:**";
  String get dataQualityNoIssuesDetected =>
      _isChinese ? "✅ **未发现重大问题。**" : "✅ **No major issues detected.**";
  String get dataQualityRecommendationsLabel =>
      _isChinese ? "**建议：**" : "**Recommendations:**";
  String get dataQualityReportTitle =>
      _isChinese ? "## 数据质量报告" : "## Data Quality Report";
  String dataQualityTotalRowsLabel(int rows) =>
      _isChinese ? "**总行数：** $rows" : "**Total Rows:** $rows";
  String get ddlStatementRequired =>
      _isChinese ? "需要提供 DDL 语句" : "DDL statement is required";
  String dqIssueDuplicates(int count) => _isChinese
      ? "在样本中发现 $count 行重复数据"
      : "Found $count duplicate rows in sample";
  String dqIssueInconsistentDateFormats(String field, String formats) =>
      _isChinese
      ? "字段 \"$field\" 的日期格式不一致: $formats"
      : "Field \"$field\" has inconsistent date formats: $formats";
  String dqIssueMissingValues(String field, int count, int percentage) =>
      _isChinese
      ? "字段 \"$field\" 有 $count 个空值($percentage%)"
      : "Field \"$field\" has $count empty values ($percentage%)";
  String dqIssueWhitespace(String field, int count) => _isChinese
      ? "字段 \"$field\" 有 $count 个值含首尾空格"
      : "Field \"$field\" has $count values with leading/trailing whitespace";
  String dqRecFillEmptyValues(String field) => _isChinese
      ? "考虑填充字段 \"$field\" 的空值，或设置默认值"
      : "Consider filling empty values in \"$field\" or setting a default value";
  String get dqRecRemoveDuplicates =>
      _isChinese ? "导入前去除重复行" : "Remove duplicate rows before import";
  String dqRecStandardizeDateFormat(String field) => _isChinese
      ? "将字段 \"$field\" 的日期格式统一为 ISO-8601 (YYYY-MM-DD)"
      : "Standardize date format in \"$field\" to ISO-8601 (YYYY-MM-DD)";
  String dqRecTrimWhitespace(String field) =>
      _isChinese ? "去除字段 \"$field\" 的首尾空格" : "Trim whitespace from \"$field\"";
  String get explainPlanUnavailable => _isChinese
      ? "无法获取该查询的 EXPLAIN 执行计划"
      : "Unable to get EXPLAIN plan for this query";
  String get exportAnalysisBatchNote => _isChinese
      ? "导出将分批执行，以降低内存占用。"
      : "Export will be performed in batches to minimize memory usage.";
  String get exportAnalysisConfirmFormatOption =>
      _isChinese ? "1. 导出格式（CSV/JSON/SQL）" : "1. Export format (CSV/JSON/SQL)";
  String get exportAnalysisConfirmOutputPath =>
      _isChinese ? "2. 输出文件路径" : "2. Output file path";
  String get exportAnalysisConfirmPrompt =>
      _isChinese ? "请确认：" : "Please confirm:";
  String get exportAnalysisConfirmRequirements =>
      _isChinese ? "3. 其他特定要求" : "3. Any specific requirements";
  String get exportAnalysisEstimatedSizeLabel =>
      _isChinese ? "**预计导出大小：**" : "**Estimated Export Size:**";
  String exportAnalysisLargeDatasetWarning(int count) => _isChinese
      ? "⚠️ **大数据集警告：** 该表包含 $count 行。"
      : "⚠️ **Large Dataset Warning:** This table contains $count rows.";
  String get exportAnalysisSampleDataLabel =>
      _isChinese ? "**样本数据（3 行）：**" : "**Sample Data (3 rows):**";
  String get exportAnalysisTableSchemaLabel =>
      _isChinese ? "**表结构：**" : "**Table Schema:**";
  String exportAnalysisTitle(String table) =>
      _isChinese ? "## 导出分析：$table" : "## Export Analysis: $table";
  String exportAnalysisTotalRows(int count) =>
      _isChinese ? "**总行数：** $count" : "**Total Rows:** $count";
  String get exportOutputPathRequired =>
      _isChinese ? "输出路径不能为空" : "Output path is required";
  String exportTaskConfigCreated(
    String table,
    String format,
    String outputPath,
  ) => _isChinese
      ? "已为表 \"$table\" 创建导出任务配置。格式：$format，输出：$outputPath"
      : "Export task configuration created for table \"$table\". Format: $format, Output: $outputPath";
  String importCompleteLabelFile(String name) =>
      _isChinese ? "**文件：** $name" : "**File:** $name";
  String importCompleteLabelImported(int count) =>
      _isChinese ? "**成功导入：** $count" : "**Successfully Imported:** $count";
  String importCompleteLabelTable(String name) =>
      _isChinese ? "**表：** $name" : "**Table:** $name";
  String importCompleteLabelTotalRows(int count) =>
      _isChinese ? "**已处理总行数：** $count" : "**Total Rows Processed:** $count";
  String get importCompleteTitle =>
      _isChinese ? "## 导入完成" : "## Import Complete";
  String importErrorLabel(String error) =>
      _isChinese ? "**错误：** $error" : "**Error:** $error";
  String importFailedLabel(int count) =>
      _isChinese ? "**失败：** $count" : "**Failed:** $count";
  String importStatusLabel(bool success) => _isChinese
      ? '**状态：** ${success ? '✅ 成功' : '❌ 失败'}'
      : '**Status:** ${success ? '✅ Success' : '❌ Failed'}';
  String mongoDataQualityFieldRow(
    String field,
    String type,
    String completeness,
    String missing,
    int sampled,
  ) => _isChinese
      ? "- **$field** ($type): 完整度 $completeness，缺失 $missing/$sampled"
      : "- **$field** ($type): completeness $completeness, missing $missing/$sampled";
  String mongoDataQualityReportTitle(String collection) => _isChinese
      ? "## 数据质量报告: $collection"
      : "## Data Quality Report: $collection";
  String mongoDocumentsImported(int count, String collection) => _isChinese
      ? "✅ 已向集合 \"$collection\" 插入 $count 个文档"
      : "✅ Inserted $count documents into collection \"$collection\"";
  String mongoExportCollectionResult(
    String collection,
    String format,
    String output,
  ) => _isChinese
      ? "导出集合 \"$collection\"（$format）：\\n\\n$output"
      : "Export collection \"$collection\" ($format):\\n\\n$output";
  String get mongoImportFailed => _isChinese
      ? "❌ 插入失败，请检查连接与文档格式"
      : "❌ Insert failed — please check the connection and document format";
  String get mongoNoValidDocuments =>
      _isChinese ? "没有可导入的有效文档" : "No valid documents to import";
  String get mongoOnlyAvailable => _isChinese
      ? "此工具仅适用于 MongoDB 连接"
      : "This tool is only available for MongoDB connections";
  String get redisOnlyAvailable => _isChinese
      ? "此工具仅适用于 Redis 连接"
      : "This tool is only available for Redis connections";
  String get keyNameRequired => _isChinese ? "键名不能为空" : "Key name is required";
  String get mongoTestDataEmpty => _isChinese
      ? "⚠️ 未生成数据（集合可能为空，无法推断 schema）"
      : "⚠️ No data generated (collection may be empty; unable to infer schema)";
  String mongoTestDataGenerated(int count, String collection) => _isChinese
      ? "✅ 已为集合 \"$collection\" 生成并插入 $count 条测试数据"
      : "✅ Generated and inserted $count test documents into collection \"$collection\"";
  String mysqlContextDatabaseStatsFailed(String error) => _isChinese
      ? "获取数据库统计失败: $error"
      : "Failed to fetch database statistics: $error";
  String get mysqlContextExplainHeader => _isChinese
      ? "执行计划 (EXPLAIN SELECT *):"
      : "Execution plan (EXPLAIN SELECT *):";
  String mysqlContextSchemaSummaryFailed(String error) =>
      _isChinese ? "获取表结构失败: $error" : "Failed to fetch table schema: $error";
  String get mysqlContextServerStatusHeader =>
      _isChinese ? "服务器状态:" : "Server status:";
  String get mysqlContextServerVariablesHeader =>
      _isChinese ? "服务器配置:" : "Server configuration:";
  String get noSimilarQueriesFound => _isChinese
      ? "历史记录中未找到相似查询。请先执行一些查询！"
      : "No similar queries found in history. Try running some queries first!";
  String get perfAnalysisQueryRequired => _isChinese
      ? "性能分析需要提供查询语句"
      : "Query is required for performance analysis";
  String get queryEntryDefaultType => _isChinese ? "查询" : "Query";
  String queryHistoryFoundCount(int count) =>
      _isChinese ? "找到 $count 条匹配的查询：" : "Found $count matching query(s):";
  String get queryHistoryNoMatch =>
      _isChinese ? "历史记录中未找到匹配的查询。" : "No matching queries found in history.";
  String get queryHistoryResultsTitle =>
      _isChinese ? "## 查询历史结果" : "## Query History Results";
  String queryHistoryTagsLabel(String tags) =>
      _isChinese ? "- **标签**：$tags" : "- **Tags**: $tags";
  String get recommendRequiresQueryOrTable => _isChinese
      ? "请提供 current_query 或 current_table 参数以便给出推荐"
      : "Please provide either current_query or current_table for recommendations";
  String similarQueryEntryHeader(
    String index,
    String typeLabel,
    String similarityPct,
  ) => _isChinese
      ? "### $index. $typeLabel (相似度: $similarityPct%)"
      : "### $index. $typeLabel (Similarity: $similarityPct%)";
  String similarQueryLabelLastExecuted(String dateStr) =>
      _isChinese ? "- **最近执行**：$dateStr" : "- **Last Executed**: $dateStr";
  String similarQueryLabelReason(String reason) =>
      _isChinese ? "**原因**：$reason" : "**Reason**: $reason";
  String get similarQueryRecommendationsTitle =>
      _isChinese ? "## 相似查询推荐" : "## Similar Query Recommendations";
  String get sqlPromptDorisGuidelines => _isChinese
      ? "# Apache Doris Guidelines\n- 选择合适的数据模型：明细（DUPLICATE）、聚合（AGGREGATE）、更新（UNIQUE）\n- 利用 Rollup 和物化视图加速查询\n- Bitmap 类型用于高效去重计数\n- 分区键选择查询过滤最频繁的列\n- 数据导入使用 Stream Load 或 Broker Load"
      : "# Apache Doris Guidelines\n- Choose the right data model: Duplicate, Aggregate, or Unique\n- Use Rollup and materialized views to accelerate queries\n- Use the Bitmap type for efficient distinct counting\n- Choose partition keys on the most frequently filtered columns\n- Use Stream Load or Broker Load for data ingestion";
  String get sqlPromptDorisPerformanceRules => _isChinese
      ? "## Apache Doris Critical Rules\n- COUNT(*) 性能较好，但大表仍要注意\n- 避免 SELECT *，明确列出所需字段\n- 利用 Rollup 和物化视图加速查询\n- 分区键选择查询过滤最频繁的列\n- Bitmap 类型用于高效去重计数\n- 避免高频小批量导入，建议攒批后导入\n- JOIN 操作确保关联字段有索引"
      : "## Apache Doris Critical Rules\n- COUNT(*) performs well, but still watch out on large tables\n- Avoid SELECT *, explicitly list required columns\n- Use Rollup and materialized views to accelerate queries\n- Choose partition keys on the most frequently filtered columns\n- Use the Bitmap type for efficient distinct counting\n- Avoid high-frequency small-batch inserts; batch them before loading\n- Ensure join columns are indexed";
  String get sqlPromptMongoGuidelines => _isChinese
      ? "# MongoDB Guidelines\n- 查询使用 find() 或 aggregate() 管道\n- 索引使用 createIndex()，关注复合索引前缀\n- 聚合管道善用 match、group、lookup 阶段\n- 大数据集使用分页：skip/limit 或范围查询\n- 文档嵌套深度不超过 3 层\n- 数组字段避免过大（小于 1000 元素）\n\n# Available MongoDB Tools (write/devops)\nWhen the user asks for these operations, call the corresponding tool instead of emitting raw Mongo shell:\n- **import_documents_mongo**: insert a batch of documents into a collection\n- **generate_test_data_mongo**: generate N schema-conforming test documents and insert them\n- **export_collection_mongo**: export a collection to JSON or CSV\n- **analyze_export_mongo**: pre-export analysis using native Mongo stats + sample (do NOT use SQL COUNT)\n- **analyze_data_quality_mongo**: per-field completeness / type consistency / null ratio report\n\nAll tools expect standard Mongo shell syntax (insertMany / find / aggregate)."
      : "# MongoDB Guidelines\n- Use find() or the aggregate() pipeline for queries\n- Create indexes with createIndex(); pay attention to compound-index prefixes\n- Leverage match, group, and lookup stages in aggregation pipelines\n- For large datasets, paginate via skip/limit or range queries\n- Keep document nesting depth under 3 levels\n- Avoid oversized array fields (stay below 1000 elements)\n\n# Available MongoDB Tools (write/devops)\nWhen the user asks for these operations, call the corresponding tool instead of emitting raw Mongo shell:\n- **import_documents_mongo**: insert a batch of documents into a collection\n- **generate_test_data_mongo**: generate N schema-conforming test documents and insert them\n- **export_collection_mongo**: export a collection to JSON or CSV\n- **analyze_export_mongo**: pre-export analysis using native Mongo stats + sample (do NOT use SQL COUNT)\n- **analyze_data_quality_mongo**: per-field completeness / type consistency / null ratio report\n\nAll tools expect standard Mongo shell syntax (insertMany / find / aggregate).";
  String get sqlPromptMongoPerformanceRules => _isChinese
      ? "## MongoDB Critical Rules\n- count() 在大集合上较慢，考虑使用 estimatedDocumentCount()\n- 避免返回大文档，使用 projection 限制字段\n- 大数据集分页使用范围查询（skip/limit 性能差）\n- 聚合管道善用索引，确保 \$match 在最前面\n- 避免文档嵌套深度超过 3 层\n- 数组字段避免过大（小于 1000 元素）"
      : "## MongoDB Critical Rules\n- count() is slow on large collections; prefer estimatedDocumentCount()\n- Avoid returning large documents; use projection to limit fields\n- For large datasets, paginate via range queries (skip/limit performs poorly)\n- Make good use of indexes in aggregation pipelines; ensure \$match comes first\n- Avoid document nesting deeper than 3 levels\n- Avoid oversized array fields (stay below 1000 elements)";
  String get sqlPromptMongoQueryFormatTitle => _isChinese
      ? "## MongoDB 查询格式（必须遵守）"
      : "## MongoDB Query Format (MUST follow)";
  String get sqlPromptMongoResponseFormatBlock => _isChinese
      ? "# Response Format\n1. **Analysis**: 简要分析用户需求（1-2 句话）\n2. **Query**: MongoDB 查询，必须用 <sql> 和 </sql> 标签包裹\n\n注意：\n- 对于简单的查询，不需要输出 Execution Plan 和 Warning\n- 仅在用户明确要求性能分析时，才提供优化建议"
      : "# Response Format\n1. **Analysis**: Briefly analyze user requirements (1-2 sentences)\n2. **Query**: MongoDB queries must be wrapped in <sql> and </sql> tags\n\nNote:\n- For simple queries, do NOT output Execution Plan and Warning\n- Only provide optimization suggestions when user explicitly requests performance analysis";
  String get sqlPromptMongoSafetyRulesBlock => _isChinese
      ? "1. 始终优先只读操作\n2. 对于写操作（insert/update/delete/drop），必须经用户显式确认\n3. 绝不假设集合结构存在，未知集合必须先查询元数据\n4. 始终优先只读操作（find/aggregate/count）"
      : "1. Always prioritize read-only operations\n2. Write operations (insert/update/delete/drop) require explicit user confirmation\n3. Never assume collection structure exists; query metadata first for unknown collections\n4. Always prioritize read-only operations (find/aggregate/count)";
  String get sqlPromptMysqlGuidelines => _isChinese
      ? "# MySQL Guidelines\n- 使用 InnoDB 引擎，字符集 utf8mb4\n- 善用 EXPLAIN 分析查询，关注 type、key、rows 字段\n- 优先覆盖索引（Covering Index），减少回表\n- 批量插入使用 INSERT ... VALUES (), () 语法\n- JSON 字段使用 JSON 函数操作（MySQL 5.7+）\n- 时间字段使用 DATETIME(3) 或 TIMESTAMP"
      : "# MySQL Guidelines\n- Use the InnoDB engine with the utf8mb4 charset\n- Use EXPLAIN to analyze queries; focus on the type, key, and rows fields\n- Prefer covering indexes to avoid table lookups\n- For bulk inserts, use INSERT ... VALUES (), ()\n- Operate on JSON fields with JSON functions (MySQL 5.7+)\n- Use DATETIME(3) or TIMESTAMP for time fields";
  String get sqlPromptMysqlPerformanceRules => _isChinese
      ? "## MySQL / InnoDB Critical Rules\n- InnoDB 表无条件 COUNT(*) 会触发全表扫描，必须避免\n  替代方案：\n  1. 使用 COUNT(*) 带 WHERE 条件\n  2. 维护计数表（trigger 更新）\n  3. 使用 SHOW TABLE STATUS（近似值）\n- 避免 SELECT *，明确列出所需字段\n- 大表深翻页（LIMIT 1000000, 10）必须改用延迟关联或游标\n- UPDATE/DELETE 必须有 WHERE 条件且使用索引\n- 批量插入使用 INSERT ... VALUES (), () 语法\n- JOIN 操作确保关联字段有索引\n- 避免在索引列上使用函数（如 DATE(created_at)）\n- 大表 ALTER 操作会锁表，建议使用 pt-online-schema-change"
      : "## MySQL / InnoDB Critical Rules\n- Unconditional COUNT(*) on InnoDB tables triggers a full table scan; avoid it\n  Alternatives:\n  1. Use COUNT(*) with a WHERE clause\n  2. Maintain a count table (updated via triggers)\n  3. Use SHOW TABLE STATUS (approximate value)\n- Avoid SELECT *, explicitly list required columns\n- For deep pagination on large tables (LIMIT 1000000, 10), use a deferred join or cursor\n- UPDATE/DELETE must have a WHERE condition and use an index\n- For bulk inserts, use INSERT ... VALUES (), ()\n- Ensure join columns are indexed\n- Avoid wrapping indexed columns in functions (e.g. DATE(created_at))\n- ALTER on large tables locks them; consider pt-online-schema-change";
  String get sqlPromptPostgresqlGuidelines => _isChinese
      ? "# PostgreSQL Guidelines\n- 善用 JSONB 操作符（箭头、双箭头、包含操作符）\n- 使用 CTE（WITH 子句）简化复杂查询\n- 窗口函数（ROW_NUMBER, LAG, LEAD）替代子查询\n- 利用 GIN/GiST 索引加速 JSONB 和全文搜索\n- 使用 pg_stat_statements 分析慢查询\n- 分区表使用声明式分区（Declarative Partitioning）\n- 数组类型使用 ANY 操作符：WHERE id = ANY(array)"
      : "# PostgreSQL Guidelines\n- Make good use of JSONB operators (arrow, double-arrow, containment)\n- Use CTEs (WITH clause) to simplify complex queries\n- Replace subqueries with window functions (ROW_NUMBER, LAG, LEAD)\n- Use GIN/GiST indexes to accelerate JSONB and full-text search\n- Use pg_stat_statements to analyze slow queries\n- Use declarative partitioning for partitioned tables\n- Use the ANY operator for array types: WHERE id = ANY(array)";
  String get sqlPromptPostgresqlPerformanceRules => _isChinese
      ? "## PostgreSQL Critical Rules\n- 大表 COUNT(*) 仍较慢，考虑使用 pg_class 近似值\n- 避免 SELECT *，明确列出所需字段\n- 善用覆盖索引（Index-Only Scan）\n- 大表分页使用 KEYSET 分页（WHERE id > last_id）\n- CTE 递归查询必须设置 max_execution_time\n- 避免在 WHERE 中使用函数（无法使用索引）\n- VACUUM ANALYZE 后查询统计信息才准确\n- 大表 ALTER 使用 CONCURRENTLY 避免锁表"
      : "## PostgreSQL Critical Rules\n- COUNT(*) on large tables is still slow; consider the pg_class approximation\n- Avoid SELECT *, explicitly list required columns\n- Make good use of covering indexes (Index-Only Scan)\n- For large-table pagination, use keyset pagination (WHERE id > last_id)\n- Set max_execution_time on recursive CTE queries\n- Avoid wrapping indexed columns in functions in WHERE (cannot use index)\n- Statistics are only accurate after VACUUM ANALYZE\n- Use ALTER ... CONCURRENTLY on large tables to avoid locking";
  String get sqlPromptRedisCommandFormatTitle => _isChinese
      ? "## Redis 命令格式（必须遵守）"
      : "## Redis Command Format (MUST follow)";
  String get sqlPromptRedisGuidelines => _isChinese
      ? "# Redis Guidelines\n- 关注命令时间复杂度，避免 O(N) 操作在大数据量时执行\n- 使用 Pipeline 批量执行命令减少 RTT\n- 大对象使用 Hash 分片（如超过 512 个字段）\n- 热 Key 使用本地缓存或读写分离\n- 过期策略：合理设置 TTL，避免同时过期\n- 使用 SCAN 替代 KEYS 遍历大数据集"
      : "# Redis Guidelines\n- Watch command time complexity; avoid O(N) operations on large datasets\n- Use Pipeline to batch commands and reduce RTT\n- Shard large objects into Hashes (e.g. > 512 fields)\n- Cache hot keys locally or use read/write splitting\n- Set TTLs wisely; avoid simultaneous expiry spikes\n- Use SCAN instead of KEYS to iterate large datasets";
  String get sqlPromptRedisPerformanceRules => _isChinese
      ? "## Redis Critical Rules\n- 关注命令时间复杂度，避免 O(N) 操作在大数据量时执行\n- KEYS 命令绝对禁止在大数据量时使用，必须用 SCAN\n- 使用 Pipeline 批量执行命令减少 RTT\n- 大对象使用 Hash 分片（如超过 512 个字段）\n- 热 Key 使用本地缓存或读写分离\n- 过期策略：合理设置 TTL，避免同时过期"
      : "## Redis Critical Rules\n- Watch command time complexity; avoid O(N) operations on large datasets\n- The KEYS command is strictly forbidden on large datasets; use SCAN instead\n- Use Pipeline to batch commands and reduce RTT\n- Shard large objects into Hashes (e.g. > 512 fields)\n- Cache hot keys locally or use read/write splitting\n- Set TTLs wisely; avoid simultaneous expiry spikes";
  String get sqlPromptRedisResponseFormatBlock => _isChinese
      ? "# Response Format\n1. **Analysis**: 简要分析用户需求（1-2 句话）\n2. **Command**: Redis 命令，必须用 <sql> 和 </sql> 标签包裹\n\n注意：\n- 对于简单的查询，不需要输出 Execution Plan 和 Warning\n- 仅在用户明确要求性能分析时，才提供优化建议"
      : "# Response Format\n1. **Analysis**: Briefly analyze user requirements (1-2 sentences)\n2. **Command**: Redis commands must be wrapped in <sql> and </sql> tags\n\nNote:\n- For simple queries, do NOT output Execution Plan and Warning\n- Only provide optimization suggestions when user explicitly requests performance analysis";
  String get sqlPromptRedisSafetyRulesBlock => _isChinese
      ? "1. 始终优先只读操作（GET, HGET, LRANGE, SMEMBERS, ZRANGE, SCAN 等）\n2. 对于写操作（SET, DEL, FLUSHDB 等），必须经用户显式确认\n3. KEYS 命令绝对禁止在大数据量时使用，必须用 SCAN\n4. 始终优先只读操作"
      : "1. Always prioritize read-only operations (GET, HGET, LRANGE, SMEMBERS, ZRANGE, SCAN, etc.)\n2. Write operations (SET, DEL, FLUSHDB, etc.) require explicit user confirmation\n3. The KEYS command is strictly forbidden on large datasets; use SCAN instead\n4. Always prioritize read-only operations";
  String get sqlPromptResponseFormatBlock => _isChinese
      ? "# Response Format\n1. **Analysis**: 简要分析用户需求（1-2 句话）\n2. **Query**: SQL 语句，必须用 <sql> 和 </sql> 标签包裹\n\n注意：\n- 对于简单的 SELECT 查询，不需要输出 Execution Plan 和 Warning\n- 执行计划和风险分析会在用户点击\"执行\"后通过实际 EXPLAIN 获取\n- 仅在用户明确要求性能分析时，才使用 explain_query 工具获取真实执行计划"
      : "# Response Format\n1. **Analysis**: Briefly analyze user requirements (1-2 sentences)\n2. **Query**: SQL statements must be wrapped in <sql> and </sql> tags\n\nNote:\n- For simple SELECT queries, do NOT output Execution Plan and Warning\n- Execution plan and risk analysis will be obtained via actual EXPLAIN after user clicks \"Execute\"\n- Only use explain_query tool to get real execution plan when user explicitly requests performance analysis";
  String get sqlPromptSqliteGuidelines => _isChinese
      ? "# SQLite Guidelines\n- 类型亲和性：声明类型但实际存储灵活（INTEGER/REAL/TEXT/BLOB/NULL）\n- 整数主键使用 ROWID 别名，自动自增\n- 外键约束默认关闭，需 PRAGMA foreign_keys = ON 启用\n- 使用事务包裹批量操作（BEGIN IMMEDIATE...COMMIT）\n- JSON1 扩展支持 JSON 操作（json_extract, json_array 等）\n- 全文搜索使用 FTS5 虚拟表"
      : "# SQLite Guidelines\n- Type affinity: types are declared but storage is flexible (INTEGER/REAL/TEXT/BLOB/NULL)\n- Integer primary keys alias ROWID and auto-increment\n- Foreign-key constraints are off by default; enable with PRAGMA foreign_keys = ON\n- Wrap bulk operations in transactions (BEGIN IMMEDIATE...COMMIT)\n- The JSON1 extension supports JSON operations (json_extract, json_array, etc.)\n- Use the FTS5 virtual table for full-text search";
  String get sqlPromptSqlitePerformanceRules => _isChinese
      ? "## SQLite Critical Rules\n- 使用正确的索引，特别是 WHERE、JOIN、ORDER BY 列\n- 避免 SELECT *，明确列出所需字段\n- 大表分页使用 LIMIT/OFFSET，但深分页性能会下降\n- 批量插入使用事务包裹（BEGIN...COMMIT）\n- 使用 EXPLAIN QUERY PLAN 分析查询计划\n- 避免在索引列上使用函数或类型转换\n- 定期执行 VACUUM 优化数据库文件大小"
      : "## SQLite Critical Rules\n- Use the right indexes, especially on WHERE, JOIN, and ORDER BY columns\n- Avoid SELECT *, explicitly list required columns\n- For large tables, paginate via LIMIT/OFFSET (deep pagination degrades)\n- Wrap bulk inserts in transactions (BEGIN...COMMIT)\n- Use EXPLAIN QUERY PLAN to analyze the query plan\n- Avoid wrapping indexed columns in functions or type conversions\n- Run VACUUM periodically to compact the database file";
  String get sqlPromptSqlserverGuidelines => _isChinese
      ? "# SQL Server Guidelines\n- 使用方括号 [] 引用标识符，避免关键字冲突\n- T-SQL 支持 CTE、窗口函数、PIVOT/UNPIVOT\n- 善用 SQL Server Agent 进行定时任务\n- 使用 TRY...CATCH 进行错误处理\n- 分区表用于大表管理（SWITCH 分区）\n- 使用 OUTPUT 子句获取 DML 操作影响的数据"
      : "# SQL Server Guidelines\n- Use square brackets [] to quote identifiers and avoid keyword conflicts\n- T-SQL supports CTEs, window functions, and PIVOT/UNPIVOT\n- Use SQL Server Agent for scheduled tasks\n- Use TRY...CATCH for error handling\n- Use partitioned tables for large-table management (SWITCH partitions)\n- Use the OUTPUT clause to return rows affected by DML";
  String get sqlPromptSqlserverPerformanceRules => _isChinese
      ? "## SQL Server Critical Rules\n- 避免 SELECT *，明确列出所需字段\n- 大表分页使用 OFFSET/FETCH 而非 TOP\n- 善用覆盖索引，减少 Key Lookup\n- 避免在 WHERE 中使用函数（导致索引失效）\n- 批量插入使用 BULK INSERT 或表值参数\n- 使用 TRY...CATCH 处理事务错误\n- 定期更新统计信息（UPDATE STATISTICS）"
      : "## SQL Server Critical Rules\n- Avoid SELECT *, explicitly list required columns\n- For large-table pagination, use OFFSET/FETCH rather than TOP\n- Make good use of covering indexes to reduce Key Lookups\n- Avoid wrapping indexed columns in functions in WHERE (disables index)\n- For bulk inserts, use BULK INSERT or table-valued parameters\n- Use TRY...CATCH to handle transaction errors\n- Update statistics periodically (UPDATE STATISTICS)";
  String get sqlPromptTdengineGuidelines => _isChinese
      ? "# TDengine Guidelines\n- 区分超级表（STable）和普通表，超级表定义 schema 和标签\n- 子表按设备或实体创建，标签用于分组过滤\n- 时间戳是主键，必须存在\n- 利用 LAST/LAST_ROW 函数获取最新数据\n- 数据订阅使用 topic 加 consumer group\n- 注意数据类型的选择，NCHAR 存储变长字符串"
      : "# TDengine Guidelines\n- Distinguish super tables (STable) from normal tables; the STable defines the schema and tags\n- Create subtables per device or entity; tags are used for grouping and filtering\n- The timestamp is the primary key and must exist\n- Use the LAST/LAST_ROW functions to fetch the latest data\n- Subscribe to data via a topic and consumer group\n- Choose data types carefully; NCHAR stores variable-length strings";
  String get sqlPromptTdenginePerformanceRules => _isChinese
      ? "## TDengine Critical Rules\n- 区分超级表（STable）和普通表\n- 子表按设备或实体创建，标签用于分组过滤\n- 时间戳是主键，必须存在\n- 利用 LAST/LAST_ROW 函数获取最新数据\n- 数据订阅使用 topic 加 consumer group\n- 注意数据类型选择，NCHAR 存储变长字符串"
      : "## TDengine Critical Rules\n- Distinguish super tables (STable) from normal tables\n- Create subtables per device or entity; tags are used for grouping and filtering\n- The timestamp is the primary key and must exist\n- Use the LAST/LAST_ROW functions to fetch the latest data\n- Subscribe to data via a topic and consumer group\n- Choose data types carefully; NCHAR stores variable-length strings";
  String get sqlPromptToolInstructionsBlock => _isChinese
      ? "## 查询性能分析\n当用户询问查询性能或优化时：\n1. 先用 `explain_query` 获取原始执行计划\n2. 再用 `analyze_query_performance` 获取详细分析：\n   - 瓶颈识别（全表扫描、缺失索引等）\n   - 索引建议（含 CREATE INDEX 语句）\n   - 查询改写建议\n3. 以清晰、可执行的方式呈现结论\n4. 对于索引建议，强调 CREATE INDEX 需要用户确认\n5. 提醒用户在生产数据库上执行优化的风险\n\n## 模式影响分析（DDL 安全）\n关键：在生成或执行任何 DDL 语句（CREATE、ALTER、DROP、TRUNCATE、RENAME）之前：\n1. 必须先用 `analyze_schema_impact` 评估影响\n2. 向用户呈现风险等级和受影响对象\n3. 若风险等级为 HIGH 或 CRITICAL：\n   - 展示告警与建议\n   - 展示回滚脚本\n   - 在继续之前显式请求用户确认\n4. 高风险时未经用户确认绝不执行 DDL\n5. 对于 DROP 操作，始终警告数据丢失风险"
      : "## Query Performance Analysis\nWhen users ask about query performance or optimization:\n1. First use `explain_query` to get raw execution plan\n2. Then use `analyze_query_performance` to get detailed analysis with:\n   - Bottleneck identification (full table scans, missing indexes, etc.)\n   - Index recommendations with CREATE INDEX statements\n   - Query rewrite suggestions\n3. Present findings in a clear, actionable format\n4. For index recommendations, emphasize that CREATE INDEX requires user confirmation\n5. Warn users about running optimizations on production databases\n\n## Schema Impact Analysis (DDL Safety)\nCRITICAL: Before generating or executing ANY DDL statement (CREATE, ALTER, DROP, TRUNCATE, RENAME):\n1. ALWAYS use `analyze_schema_impact` first to assess the impact\n2. Present the risk level and affected objects to the user\n3. If the risk level is HIGH or CRITICAL:\n   - Show the warnings and recommendations\n   - Display the rollback script\n   - EXPLICITLY ask for user confirmation before proceeding\n4. Never execute DDL without user confirmation when risk is high\n5. For DROP operations, always warn about data loss";
  String tableDoesNotExist(String table) =>
      _isChinese ? "表 \"$table\" 不存在" : "Table \"$table\" does not exist";
  String get tableNameRequired =>
      _isChinese ? "表名不能为空" : "Table name is required";
  String get testDataGeneratedExecutedTitle =>
      _isChinese ? "## 测试数据生成并执行" : "## Test Data Generated & Executed";
  String toolResultDatabaseLabel(String name) =>
      _isChinese ? "- **数据库**：$name" : "- **Database**: $name";
  String toolResultExecutionTimeLabel(String ms) =>
      _isChinese ? "- **执行时间**：${ms}ms" : "- **Execution Time**: ${ms}ms";
  String get toolResultLabelErrors =>
      _isChinese ? "\\n**错误:**" : "\\n**Errors:**";
  String toolResultLabelLocale(String value) =>
      _isChinese ? "**语言:** $value" : "**Locale:** $value";
  String toolResultLabelMode(bool realistic) => _isChinese
      ? '**模式：** ${realistic ? '真实数据' : '基础'}'
      : '**Mode:** ${realistic ? 'Realistic' : 'Basic'}';
  String toolResultLabelResult(String message) =>
      _isChinese ? "**结果:** $message" : "**Result:** $message";
  String toolResultLabelRows(int count) =>
      _isChinese ? "**行数:** $count" : "**Rows:** $count";
  String toolResultLabelTable(String table) =>
      _isChinese ? "**表:** $table" : "**Table:** $table";
  String toolResultRowCountLabel(int count) =>
      _isChinese ? "- **行数**：$count" : "- **Row Count**: $count";
  // --- schema-summary / context-builder labels (ai_adapter_mixin, mysql_collector, app_provider) ---
  String schemaSummaryDbTypeLabel(String type) =>
      _isChinese ? '数据库类型: $type' : 'Database type: $type';
  String schemaSummaryTableCount(int count) =>
      _isChinese ? '表数量: $count' : 'Table count: $count';
  String schemaSummaryTableList(String list) =>
      _isChinese ? '表列表: $list' : 'Tables: $list';
  String schemaSummaryMoreTables(int count) =>
      _isChinese ? '... 等共 $count 个表' : '... $count more tables';
  String schemaSummaryStructureHeader(String target) =>
      _isChinese ? '\n表 [$target] 结构:' : '\nTable [$target] structure:';
  String get schemaSummaryIndexesHeader => _isChinese ? '索引:' : 'Indexes:';
  String get schemaSummaryForeignKeysHeader => _isChinese
      ? '外键（本表引用其他表）:'
      : 'Foreign Keys (this table references others):';
  String get schemaSummaryReferencedByHeader => _isChinese
      ? '被引用（其他表引用本表，删除/更新本表数据前需先处理）:'
      : 'Referenced By (other tables reference this table; handle these before deleting/updating):';
  String schemaSummaryForeignKeyLine(
    String column,
    String refTable,
    String refColumn, [
    String? onDelete,
  ]) {
    final action = onDelete == null || onDelete.isEmpty
        ? ''
        : ' ON DELETE $onDelete';
    return _isChinese
        ? '  $column -> $refTable.$refColumn$action'
        : '  $column -> $refTable.$refColumn$action';
  }

  String schemaSummaryTableDetailsFailed(String target, String error) =>
      _isChinese
      ? '获取表 [$target] 详情失败: $error'
      : 'Failed to fetch details for table [$target]: $error';
  String schemaSummaryFetchFailed(String error) => _isChinese
      ? 'Schema 摘要获取失败: $error'
      : 'Failed to fetch schema summary: $error';
  String aiContextDatabaseCount(int count) =>
      _isChinese ? '数据库数量: $count' : 'Database count: $count';
  String aiContextDatabaseList(String list) =>
      _isChinese ? '数据库列表: $list' : 'Database list: $list';
  String get mysqlContextDbTypeMysql =>
      _isChinese ? '数据库类型: MySQL' : 'Database type: MySQL';
  String mysqlContextTargetTable(Object name) =>
      _isChinese ? '目标表: $name' : 'Target table: $name';
  String get mysqlContextTableStatsHeader =>
      _isChinese ? '\n表统计（近似值）:' : '\nTable statistics (approximate):';
  String mysqlContextEngine(Object engine) =>
      _isChinese ? '  引擎: $engine' : '  Engine: $engine';
  String mysqlContextApproxRows(Object rows) =>
      _isChinese ? '  近似行数: $rows' : '  Approx. rows: $rows';
  String mysqlContextDataSize(Object size) =>
      _isChinese ? '  数据大小: $size' : '  Data size: $size';
  String mysqlContextIndexSize(Object size) =>
      _isChinese ? '  索引大小: $size' : '  Index size: $size';
  String mysqlContextCollation(Object collation) =>
      _isChinese ? '  字符集排序: $collation' : '  Collation: $collation';
  String get mysqlContextTableListHeader =>
      _isChinese ? '\n表列表（含近似统计）:' : '\nTable list (with approx. stats):';
  String get mysqlContextNoTables => _isChinese ? '  （无表）' : '  (no tables)';
  String mysqlContextTableRow(
    Object name,
    Object rows,
    Object data,
    Object idx,
    Object engine,
  ) => _isChinese
      ? '  $name: ~$rows 行, 数据 $data, 索引 $idx, 引擎 $engine'
      : '  $name: ~$rows rows, data $data, index $idx, engine $engine';
  String get sqlPromptMongoQueryFormatMandatory => _isChinese
      ? '- 【强制】所有可执行 MongoDB 查询必须用 <sql> 和 </sql> 标签包裹，否则无法被提取执行'
      : '- [MANDATORY] All executable MongoDB queries must be wrapped in <sql> and </sql> tags, otherwise they cannot be extracted for execution';
  String get sqlPromptRedisCommandFormatMandatory => _isChinese
      ? '- 【强制】所有可执行 Redis 命令必须用 <sql> 和 </sql> 标签包裹，否则无法被提取执行'
      : '- [MANDATORY] All executable Redis commands must be wrapped in <sql> and </sql> tags, otherwise they cannot be extracted for execution';
}
