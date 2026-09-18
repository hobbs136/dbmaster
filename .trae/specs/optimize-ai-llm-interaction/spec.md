# AI助手大模型交互优化 Spec

## Why
AI助手与大模型的交互存在超时机制缺失、Prompt设计缺陷、流式解析不可靠、上下文管理低效、无重试机制等严重问题，导致用户体验差（请求挂起、回复不完整、多轮对话失效、简单问题响应慢）。

## What Changes
- 重构超时机制：非流式请求实际使用timeout参数；流式请求添加chunk间超时
- 优化Prompt工程：步骤1改为JSON格式输出+Few-Shot示例；合并冗余上下文；添加systemPrompt
- 重构流式解析：提取公共SSE解析器；分离reasoning与正式内容；修复Claude SSE格式
- 优化上下文管理：实现多轮对话历史；消除重复建表语句获取；添加表结构缓存
- 增强错误恢复：添加AI调用重试机制；表名验证；简化流程（简单问题跳过三步）
- 统一配置管理：厂商配置单一数据源；API Key加密存储
- 修复安全检查：改进_isDangerousSql和_isSafeSql逻辑

## Impact
- Affected code: `lib/services/ai_service.dart`, `lib/organisms/ai_panel/ai_panel_widget.dart`, `lib/services/ai_enhanced_service.dart`, `lib/providers/ai_config_provider.dart`, `lib/services/ai_context_service.dart`, `lib/providers/ai_panel_provider.dart`

## ADDED Requirements

### Requirement: 超时机制完善
系统 SHALL 为所有AI请求提供完整的超时保护。

#### Scenario: 非流式请求超时
- **WHEN** 非流式chat()请求超过用户配置的超时时间
- **THEN** 请求被取消并抛出超时异常，用户看到友好的超时提示

#### Scenario: 流式请求chunk间超时
- **WHEN** 流式请求已建立连接，但连续30秒未收到新数据
- **THEN** 请求被取消并抛出超时异常

### Requirement: Prompt工程优化
系统 SHALL 使用结构化Prompt设计以提高LLM输出质量和稳定性。

#### Scenario: 步骤1表名分析
- **WHEN** AI分析用户需求确定相关表名
- **THEN** Prompt要求JSON格式输出，包含Few-Shot示例，表名结果与实际数据库表名做校验

#### Scenario: 简单查询快速路径
- **WHEN** 用户输入明确指定了表名（如"查询users表"）
- **THEN** 跳过步骤1直接进入SQL生成，减少一次AI调用

### Requirement: 流式解析可靠性
系统 SHALL 正确处理SSE流式数据的边界情况和不同厂商格式。

#### Scenario: 跨chunk的JSON数据
- **WHEN** SSE数据行被TCP分片切断
- **THEN** 不完整的JSON行被保留到下一个chunk再解析，数据不丢失

#### Scenario: Claude流式响应
- **WHEN** 使用Claude API进行流式请求
- **THEN** 正确解析Claude的event+data格式，识别message_stop事件正常终止流

#### Scenario: 思考过程分离
- **WHEN** 模型返回reasoning/thinking字段
- **THEN** 思考过程与正式内容分离存储，不污染SQL提取

### Requirement: 多轮对话历史
系统 SHALL 在AI对话中维护完整的对话历史。

#### Scenario: 连续对话
- **WHEN** 用户在AI面板中连续发送多条消息
- **THEN** 后续请求包含之前的用户消息和AI回复，模型能理解上下文

### Requirement: AI调用重试机制
系统 SHALL 对瞬态错误自动重试。

#### Scenario: API限流重试
- **WHEN** AI请求收到429状态码
- **THEN** 系统自动以指数退避重试最多3次

#### Scenario: 网络临时错误重试
- **WHEN** AI请求因网络错误失败
- **THEN** 系统自动重试最多2次

### Requirement: 表结构缓存
系统 SHALL 缓存已查询的表结构信息。

#### Scenario: 重复查询同一表
- **WHEN** 用户在同一数据库会话中多次发送AI消息
- **THEN** 表结构信息从缓存读取，不重复查询数据库

### Requirement: API Key安全存储
系统 SHALL 使用加密存储保存API Key。

#### Scenario: API Key持久化
- **WHEN** 用户配置AI厂商的API Key
- **THEN** Key通过flutter_secure_storage加密存储，不以明文保存在SharedPreferences中

## MODIFIED Requirements

### Requirement: SQL安全检查
系统 SHALL 对生成的SQL进行更精确的危险操作判断。

- 检查SQL语句的第一个关键字判断操作类型
- 对DELETE/UPDATE检查是否缺少WHERE条件
- INSERT不再标记为危险操作
- 多语句场景逐条检查

### Requirement: SQL提取
系统 SHALL 更健壮地从AI回复中提取SQL语句。

- 正确处理markdown代码块（```sql ... ```）
- 处理多个代码块场景
- 去除常见的前缀文本（"以下是SQL语句："等）
- 排除思考过程内容的干扰

### Requirement: 厂商配置统一
系统 SHALL 从单一数据源获取厂商和模型配置信息。

- `AiApiProviders`（ai_service.dart）为唯一数据源
- `AiProviders`（ai_config_provider.dart）和`_providers`（ai_panel_widget.dart）引用同一数据源
- 模型列表变更只需修改一处
