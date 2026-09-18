# Tasks

- [x] Task 1: 重构超时机制
  - [x] 1.1: 非流式chat()方法传递并使用timeout参数
  - [x] 1.2: 流式请求添加chunk间超时（30秒无新数据则超时）
  - [x] 1.3: ai_enhanced_service的_callAI传递timeout参数

- [x] Task 2: 重构流式SSE解析器
  - [x] 2.1: 提取公共SSE行解析方法，修复\r\n处理bug
  - [x] 2.2: 修复跨chunk JSON数据丢失问题（buffer清空前保留不完整行）
  - [x] 2.3: 分离reasoning/thinking内容，使用独立字段返回而非混入内容流
  - [x] 2.4: 修复Claude SSE格式：识别event行，处理message_stop事件替代[DONE]

- [x] Task 3: 优化Prompt工程
  - [x] 3.1: 步骤1表名分析prompt改为JSON格式输出要求+Few-Shot示例
  - [x] 3.2: 步骤3 SQL生成prompt合并dbInfo和tableSchemas消除冗余
  - [x] 3.3: 为ai_enhanced_service的所有_callAI调用添加systemPrompt
  - [x] 3.4: 传递正确的数据库方言信息（替代硬编码MySQL）

- [x] Task 4: 优化Agent流程
  - [x] 4.1: 添加简单查询快速路径（用户已指定表名时跳过步骤1）
  - [x] 4.2: 步骤1表名结果与实际数据库表名做校验，过滤不存在的表
  - [x] 4.3: 步骤1改用非流式chat()调用（只需最终结果，无需流式）
  - [x] 4.4: 消除_buildDatabaseContext中的重复建表语句获取

- [x] Task 5: 实现多轮对话历史
  - [x] 5.1: 在AiPanelProvider中维护对话历史列表（包含之前的用户消息和AI回复）
  - [x] 5.2: _sendMessage时将历史消息传递给_executeMultiTurnConversation
  - [x] 5.3: 限制历史消息长度（最近10轮），避免超出上下文窗口

- [x] Task 6: 添加重试机制
  - [x] 6.1: 在AiService中添加重试逻辑（429/503/网络错误自动重试，指数退避）
  - [x] 6.2: 非流式chat()方法添加重试
  - [x] 6.3: 流式chatStream()方法添加重试（仅对连接阶段错误重试）

- [x] Task 7: 改进SQL提取与安全检查
  - [x] 7.1: 增强_extractSql：处理多代码块、前缀文本、排除reasoning干扰
  - [x] 7.2: 改进_isDangerousSql：检查WHERE条件、INSERT不再标记危险、多语句逐条检查
  - [x] 7.3: 修复ai_enhanced_service中_isSafeSql的DELETE WHERE逻辑bug

- [x] Task 8: 表结构缓存
  - [x] 8.1: 在AiContextService中添加表结构缓存（Map<String, String>）
  - [x] 8.2: _buildDatabaseContext优先从缓存读取，缓存未命中时查询并缓存
  - [x] 8.3: 切换数据库时清空缓存

- [x] Task 9: API Key安全存储
  - [x] 9.1: 将API Key存储从SharedPreferences迁移到flutter_secure_storage
  - [x] 9.2: 修改AiConfigProvider的_persist和_load方法
  - [x] 9.3: 提供数据迁移逻辑（首次启动时从旧存储迁移到新存储）

- [x] Task 10: 统一厂商配置数据源
  - [x] 10.1: 以AiApiProviders（ai_service.dart）为唯一数据源，增加icon/color等UI字段
  - [x] 10.2: 删除ai_config_provider.dart中的AiProviders重复定义，引用AiApiProviders
  - [x] 10.3: 删除ai_panel_widget.dart中的_providers列表，引用AiApiProviders

# Task Dependencies
- Task 2 (SSE解析重构) 应先于 Task 3 (Prompt优化) 完成，因为reasoning分离影响SQL提取
- Task 4.2 (表名校验) 依赖 Task 3.1 (JSON格式输出)
- Task 5 (多轮对话) 依赖 Task 2.3 (reasoning分离)，因为历史消息需要区分内容类型
- Task 7.1 (SQL提取增强) 依赖 Task 2.3 (reasoning分离)
- Task 9 (API Key安全) 和 Task 10 (配置统一) 可并行
- Task 8 (表结构缓存) 和 Task 6 (重试机制) 可并行
