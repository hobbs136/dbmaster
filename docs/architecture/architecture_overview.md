# DbMaster 项目架构全景文档

**版本**: v1.2  
**日期**: 2026-06-16  
**适用范围**: DbMaster v3.2.0+

---

## 目录

1. [项目概览](#1-项目概览)
2. [技术栈](#2-技术栈)
3. [分层架构](#3-分层架构)
4. [状态管理系统](#4-状态管理系统)
5. [数据库适配器体系](#5-数据库适配器体系)
6. [服务层全览](#6-服务层全览)
7. [UI 层架构 (Atomic Design)](#7-ui-层架构-atomic-design)
8. [功能模块地图](#8-功能模块地图)
9. [数据模型层](#9-数据模型层)
10. [主题系统](#10-主题系统)
11. [国际化系统](#11-国际化系统)
12. [Pro/Free 功能门控](#12-profree-功能门控)
13. [关键技术决策](#13-关键技术决策)
14. [目录结构完整清单](#14-目录结构完整清单)

---

## 1. 项目概览

DbMaster 是一款 Flutter 桌面端多数据库管理工具，支持 **8 种数据库系统**：

| # | 数据库类型 | 适配器文件 | 连接方式 | 状态 |
|---|-----------|-----------|---------|------|
| 1 | MySQL | `mysql_adapter.dart` + `mysql_base_adapter.dart` | Native TCP (mysql_client) | ✅ 完整 |
| 2 | PostgreSQL | `postgresql_adapter.dart` | Native TCP (postgres) | 🏘️ 社区维护 |
| 3 | SQLite | `sqlite_adapter.dart` | 本地文件 (sqlite3) | ✅ 完整 |
| 4 | MongoDB | `mongodb_adapter.dart` | Native TCP (mongo_dart) | ✅ 完整 |
| 5 | Redis | `redis_adapter.dart` | Native TCP (`redis/redis.dart`) | ✅ 完整 |
| 6 | Doris | `doris_adapter.dart` | MySQL 协议 (`mysql_base_adapter.dart`) | ✅ 完整 |
| 7 | TDengine | `tdengine_adapter.dart` | REST API | ✅ 完整 |
| 8 | SQL Server | `sqlserver_adapter*.dart` | FreeTDS FFI (DB-Library) | 🏘️ 社区维护 |

**核心指标**：
- `lib/**/*.dart` 文件：338
- `test/**/*.dart` 文件：212
- `integration_test/*.dart` 文件：29
- 单元/Widget 测试用例：~3,087
- 集成测试用例：~665
- 国际化：6 种语言 (en, zh, zh_TW, de, fr, ru)
- 平台支持：macOS, Windows, Linux, Web (实验性)

---

## 2. 技术栈

| 层级 | 技术选择 |
|------|---------|
| 框架 | Flutter 3.x (Desktop-first) |
| 语言 | Dart |
| 状态管理 | Provider + ChangeNotifier (Facade Pattern) |
| 数据库驱动 | mysql_client, postgres, mongo_dart, redis/redis.dart, sqlite3, FreeTDS FFI |
| HTTP 客户端 | http (REST API: TDengine) |
| 持久化存储 | SharedPreferences, FlutterSecureStorage |
| 内购 | in_app_purchase (Pigeon 通道) |
| 国际化 | Flutter intl / ARB |
| 测试 | flutter_test, mockito, build_runner |
| CI/CD | Git (Gitee), flutter analyze, flutter test |

---

## 3. 分层架构

```
┌─────────────────────────────────────────────────────┐
│  Presentation Layer                                  │
│  main.dart → MaterialApp(HomeScreen)                  │
├─────────────────────────────────────────────────────┤
│  Pages / Screens / Templates                         │
│  HomeScreen, AuthScreen, AIChatPage, WelcomeScreen    │
├─────────────────────────────────────────────────────┤
│  Organisms (Feature Components)                       │
│  Editor, Sidebar, Results, AI Panel, Connection       │
│  Dialogs, Task Panel, Smart Import                    │
├─────────────────────────────────────────────────────┤
│  Molecules / Atoms (Reusable Components)             │
│  Buttons, Cards, FormControls, ThinkingCard, etc.    │
├─────────────────────────────────────────────────────┤
│  State Management (Providers)                        │
│  AppProvider (facade) → ~10 core sub-providers       │
├─────────────────────────────────────────────────────┤
│  Business Logic (Services)                           │
│  DatabaseService, Adapters, AI, Schema, Export, etc. │
├─────────────────────────────────────────────────────┤
│  Data Models                                         │
│  Connection, QueryResult, Task, AI Session, etc.     │
├─────────────────────────────────────────────────────┤
│  Infrastructure                                      │
│  Config, Core (Commands/Errors/Shortcuts), Theme     │
└─────────────────────────────────────────────────────┘
```

### 关键原则

1. **Provider 层不与 UI 耦合** — Provider 只暴露数据和操作方法，不引用 Widget
2. **Service 层不与 Provider 耦合** — Service 是纯业务逻辑，通过 DatabaseService 接收连接
3. **Adapter 层是插件式** — 每个数据库适配器独立实现 `DatabaseAdapter` 接口
4. **UI 遵循 Atomic Design** — atoms → molecules → organisms → templates → pages

---

## 4. 状态管理系统

### 4.1 AppProvider — 中央 Facade

`AppProvider` (`lib/providers/app_provider.dart`) 是所有状态的统一入口，直接聚合约 10 个核心子 Provider：

```
AppProvider (ChangeNotifier)
├── ConnectionProvider     — 连接生命周期、服务器列表
├── TabProvider            — 标签页状态、SQL 格式化、查询取消
├── QueryHistoryProvider   — 持久化查询历史、全文搜索
├── AiPanelProvider        — AI 对话面板、消息流、会话管理
├── AiConfigProvider       — AI 提供商/模型配置、API Key
├── SidebarProvider        — 侧边栏树展开/折叠、右键菜单
├── QuerySettingsProvider  — 每连接查询设置 (行数限制、超时)
├── RecentTablesProvider   — 每连接最近访问表
├── PurchaseProvider       — 内购状态、Pro 验证
└── TaskProvider           — 后台任务编排
```

> `ThemeProvider`、`LocaleProvider`、`LayoutPreferencesProvider` 在 `main.dart` 顶层直接提供，不由 `AppProvider` 持有。

`lib/providers/` 下共有 14 个 `.dart` 文件，但 `AppProvider`  facade 只直接聚合其中约 10 个核心 Provider。

### 4.2 Provider 双向绑定

在 `main.dart` 中使用 `ChangeNotifierProxyProvider` 实现双向绑定：

```
TaskProvider ←→ AppProvider
  ↑                  ↓
  └── TaskProvider.setDatabaseService(appProvider.connection.dbService)
  └── AppProvider.updateTaskProvider(taskProvider)
```

原因：TaskProvider 需要 DatabaseService 来执行 AI 任务，而 DatabaseService 由 ConnectionProvider 持有。

### 4.3 Provider 初始化顺序

```dart
MultiProvider([
  TaskProvider(),                    // 1. 最先创建（AppProvider 依赖它）
  ThemeProvider()..load(),           // 2. 从 SharedPreferences 加载
  LocaleProvider()..load(),          // 3. 从 SharedPreferences 加载
  LayoutPreferencesProvider()..load(),// 4. 从 SharedPreferences 加载
  PurchaseProvider()..initialize(),  // 5. 初始化内购（需 Pigeon 通道）
  ChangeNotifierProxyProvider<        // 6. 最后创建，依赖前面所有 Provider
    TaskProvider, AppProvider>
])
```

---

## 5. 数据库适配器体系

### 5.1 基础接口

`DatabaseAdapter` (`lib/services/database_abstract.dart`) 是所有数据库适配器的基类，定义了全套操作签名：

```dart
abstract class DatabaseAdapter {
  // 连接管理
  Future<bool> connect(DatabaseConnection connection);
  Future<void> disconnect();
  bool get isConnected;

  // 查询
  Future<QueryResult> query(String sql);
  Future<void> execute(String sql);

  // Schema 浏览
  Future<List<String>> getDatabases();
  Future<List<String>> getTables(String database);
  Future<List<Map<String, dynamic>>> getColumns(String database, String table);
  // ... 更多 schema 方法

  // 默认 no-op 实现，子类按需覆写
}
```

### 5.2 能力接口 (Capability Interfaces)

通过 `if (adapter is DdlAdapter)` 运行时类型检查，实现细粒度的能力控制：

| 接口 | 关键方法 | 实现适配器 |
|------|---------|-----------|
| `TransactionalAdapter` | `beginTransaction()`, `commit()`, `rollback()` | MySQL, PG, SQLite, Doris, TDengine, SQL Server |
| `SqlSchemaAdapter` | `getViews()`, `getProcedures()`, `getFunctions()`, `getTriggers()`, `getTableIndexes()`, `getForeignKeys()` | MySQL, PG, SQLite, Doris, TDengine, SQL Server |
| `DdlAdapter` | `createTable()`, `dropTable()`, `addColumn()`, `modifyColumn()`, `createIndex()`, `dropIndex()` | MySQL, PG, SQLite, Doris, TDengine, SQL Server |
| `SqlScriptAdapter` | `exportDatabaseStructure()`, `executeSqlScript()` | MySQL, PG, SQLite, Doris, TDengine, SQL Server |
| `CharsetAdapter` | `getCharsets()`, `getCollations()` | MySQL, Doris |
| `AiAdapterMixin` | `getAiSchemaSummary()`, `executeAiCommand()` | 全部 (Mixin) |
| `DisconnectAware` | `onDisconnect` 回调 | 全部 (Mixin) |

### 5.3 适配器实现矩阵

| 适配器 | 文件大小 | 连接实现 | 事务 | DDL | Schema | AI | FFI |
|--------|---------|---------|------|-----|--------|----|-----|
| MySQL | ~919 行 (11 + 908) | `mysql_client`，继承 `MySQLBaseAdapter` | ✅ | ✅ | ✅ | ✅ | — |
| PostgreSQL | ~877 行 | `postgres` package | ✅ | ✅ | ✅ | ✅ | — |
| MongoDB | ~1,519 行 | `mongo_dart` | ❌ | ❌ | ✅ | ✅ | — |
| Redis | ~1,370 行 | `redis/redis.dart` | ❌ | ❌ | ✅ | ✅ | — |
| SQLite | ~877 行 | `sqlite3` 本地文件 | ✅ | ✅ | ✅ | ✅ | — |
| Doris | ~344 行 | 继承 `MySQLBaseAdapter` (MySQL 协议) | ✅ | ✅ | ✅ | ✅ | — |
| TDengine | ~985 行 | REST API (HTTP) | ✅ | ✅ | ✅ | ✅ | — |
| SQL Server | ~1,897 行 native + stub | FreeTDS DB-Library (FFI) | ✅ | ✅ | ✅ | ✅ | ✅ |

### 5.4 MySQL/Doris 基础适配器继承

MySQL 与 Doris 现在共用 `MySQLBaseAdapter`（`lib/services/adapters/mysql_base_adapter.dart`，908 行），通过继承复用 MySQL 协议逻辑，不再使用早期的 `bindConnection()` 会话模型：

```
MySQLBaseAdapter (908 行)
├── MySQLAdapter (11 行)     — 条件导出/子类选择
└── DorisAdapter (344 行)    — 覆盖 SHOW 等 Doris 特定行为
```

- `mysql_adapter.dart` 仅包含约 11 行的平台/子类分发逻辑。
- `doris_adapter.dart` 约 344 行，专注于 Doris 与 MySQL 的差异点。
- 两者各自维护独立的 `MySQLConnection` 实例，不再共享底层 TCP 连接。

### 5.5 SQL Server 条件导出模式

SQL Server 适配器使用 Dart 条件导出，分离 FFI 实现和 Web 存根：

```
sqlserver_adapter.dart        (导出门)
├── sqlserver_adapter_native.dart  (~1,897 行 — FreeTDS FFI)
└── sqlserver_adapter_stub.dart    (Web 存根，抛 UnsupportedError)
```

```dart
// sqlserver_adapter.dart
export 'sqlserver_adapter_stub.dart'
  if (dart.library.ffi) 'sqlserver_adapter_native.dart';
```

**约束**：Native 和 Stub 必须声明完全相同的 `class` 签名（相同的 `implements` 子句）。

---

## 6. 服务层全览

### 6.1 核心服务

| 服务文件 | 职责 |
|---------|------|
| `database_service.dart` | 数据库核心：连接管理、查询执行、Schema 查询。组合 `_ConnectionManager` + `_QueryExecutor` + `_SchemaManager` |
| `database_abstract.dart` | 适配器接口定义 + `QueryResult`/`DatabaseConnection` 数据类 |
| `database_tools.dart` | 数据库工具函数（DDL 生成、类型推断等） |
| `database_tool_registry.dart` | 数据库工具注册与查找 |

### 6.2 AI 子系统

```
lib/services/ai/
├── ai_client.dart              — AI API 客户端 (Anthropic/OpenAI 统一接口)
├── ai_context_builder.dart     — 上下文构建器
├── ai_parser_factory.dart      — 响应解析器工厂
├── ai_prompt_factory.dart      — Prompt 构建器工厂
├── ai_session_manager.dart     — AI 会话状态管理
├── ai_service_localizations.dart — AI 服务多语言提示
├── prompt_builders/
│   ├── sql_prompt_builder.dart — SQL 生成 Prompt
│   ├── mongodb_prompt_builder.dart
│   ├── redis_prompt_builder.dart
│   └── ... (7 个数据库特定 Builder)
└── response_parsers/
    ├── sql_response_parser.dart — SQL 响应解析
    ├── mongodb_response_parser.dart
    ├── redis_response_parser.dart
    └── ... (各数据库特定 Parser)
```

顶层 AI 服务（`lib/services/` 下）：
| 服务 | 职责 |
|------|------|
| `ai_service.dart` | AI 主服务入口，协调所有 AI 功能 |
| `ai_agent_service.dart` | AI Agent 自主执行模式 |
| `ai_conversation_service.dart` | 多轮对话管理 |
| `ai_context_service.dart` | 重新导出 `ai/ai_context_builder.dart`（无独立 `AiContextService` 类） |
| `ai_context_compressor.dart` | 重新导出 `ai/ai_context_builder.dart`（无独立 `AiContextCompressor` 类） |
| `ai_session_orchestrator.dart` | 多会话编排 |
| `ai_session_store.dart` | 会话持久化存储 |
| `ai_message_update_manager.dart` | 消息流实时更新 |
| `ai_skill_service.dart` | AI 技能注册与调度 |
| `ai_summary_service.dart` | 查询结果 AI 摘要 |

### 6.3 SQL / 查询服务

| 服务 | 职责 |
|------|------|
| `sql_parser_service.dart` | SQL 语句解析（拆分多语句、提取对象引用） |
| `sql_validator_service.dart` | SQL 语法/语义验证 |
| `sql_formatter_service.dart` | SQL 代码格式化 |
| `sql_prompt_service.dart` | 自然语言 → SQL 的 Prompt 服务 |
| `sql_injection_detector.dart` | SQL 注入检测 |
| `sql_autocomplete_service.dart` | SQL 自动补全候选生成 |
| `sql_quick_fix_service.dart` | SQL 错误快速修复建议 |
| `sql_optimizer_service.dart` | SQL 性能优化建议 |
| `paginated_result_service.dart` | 大结果集分页 |
| `multi_execution_service.dart` | 批量语句执行 |
| `query_execution_interceptor.dart` | 查询执行拦截（审计/权限/限流） |
| `insert_execution_service.dart` | INSERT 批量执行优化 |
| `query_settings_service.dart` | 查询运行时设置 |
| `query_analyzer_service.dart` | SQL 查询分析 |

### 6.4 Schema / ER / 导入导出

| 服务 | 职责 |
|------|------|
| `schema_analyzer/schema_analyzer.dart` | Schema 结构分析 |
| `schema_analyzer/dependency_analyzer.dart` | 对象间依赖关系分析 |
| `schema_analyzer/impact_assessor.dart` | DDL 变更影响评估 |
| `schema_analyzer/rollback_generator.dart` | DDL 回滚脚本生成 |
| `schema_diff/schema_diff_service.dart` | 两个数据库 Schema 差异对比 |
| `schema_diff/schema_sync_service.dart` | Schema 同步执行 |
| `schema_diff/table_dependency_sorter.dart` | 表依赖拓扑排序 |
| `er_diagram_service.dart` | ER 图数据生成 |
| `er_layout.dart` | ER 图自动布局算法 |
| `export_service.dart` | 数据导出 (CSV/JSON/Excel/SQL INSERT) |
| `backup_service.dart` | 数据库备份 |
| `import_service.dart` | 数据导入 |
| `smart_import_service.dart` | 智能导入 (自动检测格式/类型映射) |
| `data_generation_service.dart` | 测试数据生成 |
| `faker_data_service.dart` | Faker 假数据生成 |
| `index_optimizer_service.dart` | 索引优化建议 |
| `performance_analyzer_service.dart` | 查询性能分析 |

### 6.5 安全

| 服务 | 职责 |
|------|------|
| `auth_token_storage.dart` | 认证令牌安全存储（数据库连接凭据等） |
| `secure_storage_service.dart` | 通用安全存储 |
| `ssh_tunnel_service.dart` | SSH 隧道连接 |
| `audit_log_service.dart` | 操作审计日志 |
| `pii_masker.dart` | PII (个人身份信息) 自动检测与掩码 |
| `background_filter_service.dart` | 后台数据过滤 |
| `pro_status_storage.dart` | Pro 订阅状态持久化 |
| `purchase_service.dart` | 应用内购买 |

### 6.6 专用服务

| 服务 | 职责 |
|------|------|
| `redis_script_service.dart` | Redis Lua 脚本管理 |
| `code_snippet_service.dart` | 代码片段存储与检索 |
| `mongodb_shell_parser.dart` | MongoDB Shell 语法解析 |
| `stored_procedure_service.dart` | 存储过程管理 |
| `trigger_service.dart` | 触发器管理 |
| `schema_context_service.dart` | Schema 上下文缓存 |
| `streaming_file_reader.dart` | 大文件流式读取 |
| `file_analyzer.dart` | 文件格式自动检测 |

### 6.7 任务系统

| 文件 | 职责 |
|------|------|
| `services/task/task_executor.dart` | 后台任务执行引擎 |
| `services/task/export_task_executor.dart` | 导出任务专用执行器 |
| `services/task/import_task_executor.dart` | 导入任务专用执行器 |

### 6.8 数据同步

| 文件 | 职责 |
|------|------|
| `services/data_sync/data_sync_service.dart` | 跨数据库数据同步 |

---

## 7. UI 层架构 (Atomic Design)

```
atoms/           — 不可拆分的基础组件
  AppButton, AppCard, AppHeader, AppIconButton,
  AppLoading, TypewriterText, AppScrollbar,
  AppTransitions, AppWidgets, EmptyStateWidget

molecules/       — 原子组件的简单组合
  ThinkingCard, ContextMenu, FormControls,
  HeaderButton, PasswordField, SearchBar,
  SkeletonLoader, ToastService, UserAvatar,
  VerificationCodeField, ResizerWidgets

organisms/       — 功能区域组件
  ├── ai_panel/          — AI 对话面板 (13 文件)
  ├── charts/            — 图表 (1 文件)
  ├── connection/        — 连接/对话框/ER图/表操作 (~29 文件)
  │   └── table_dialog/  — 表操作对话框 (9 文件)
  ├── dialogs/           — 通用对话框 (14 文件)
  ├── editor/            — SQL 编辑器 (14 文件)
  ├── query_optimizer/   — 查询优化器 UI (1 文件)
  ├── results/           — 结果展示 (7 文件)
  ├── sidebar/           — 侧边栏/树/右键菜单 (19 文件)
  ├── smart_import/      — 智能导入向导 (2 文件)
  ├── task_panel/        — 任务面板 (4 文件)
  └── workspace/         — 目录保留，当前为空（Workspace 概念已由扁平 Tab 架构取代）

templates/       — 页面布局
  welcome_screen, main_workspace, editor_results_split,
  connecting_screen, workspace

pages/           — 独立页面
  ├── ai_chat/           — AI 聊天独立页面
  └── auth/              — 认证页面 (6 文件)

screens/         — 主屏幕
  home_screen, auth_screen
```

---

## 8. 功能模块地图

按用户视角，DbMaster 包含以下功能模块：

### 8.1 连接管理
- **功能**: 新建/编辑/删除/导入/导出数据库连接
- **入口**: 欢迎屏幕 "New Connection"、菜单 File > New Connection
- **核心文件**: `lib/organisms/connection/connection_dialog.dart`, `lib/providers/connection_provider.dart`
- **支持**: SSH 隧道、SSL/TLS、多种认证方式
- **状态**: ✅ 完整

### 8.2 查询编辑器
- **功能**: SQL/MongoDB/Redis 多模式编辑器、语法高亮、自动补全、代码片段、格式化
- **入口**: Workspace 中的 Query Tab
- **核心文件**: `lib/organisms/editor/`, `lib/organisms/editor/sql_autocomplete.dart`
- **状态**: ✅ 核心功能完整

### 8.3 侧边栏数据浏览器
- **功能**: 树形结构浏览数据库对象（表/视图/存储过程/函数/触发器）、右键菜单操作
- **入口**: 主界面左侧面板
- **核心文件**: `lib/organisms/sidebar/`, 8 个 TreeBuilder
- **支持数据库**: MySQL, PG, MongoDB, Redis, SQLite, SQL Server, TDengine, Doris
- **状态**: ✅ 完整

### 8.4 结果展示
- **功能**: 表格/卡片视图、列排序/隐藏、复制单元格/行、数据导出
- **入口**: 查询执行后下方区域
- **核心文件**: `lib/organisms/results/`
- **状态**: ✅ 核心功能完整（多列排序未实现）

### 8.5 AI 助手面板
- **功能**: 自然语言生成 SQL、Schema 问答、数据洞察、DDL 确认执行
- **入口**: 主界面右侧 AI 面板
- **核心文件**: `lib/organisms/ai_panel/`, `lib/services/ai/`
- **状态**: ✅ 完整

### 8.6 Schema 差异对比
- **功能**: 两个数据库/快照的 Schema 差异检测、DDL 脚本生成、同步执行
- **入口**: 菜单 Tools > Schema Diff
- **核心文件**: `lib/organisms/connection/schema_diff_dialog.dart`, `lib/services/schema_diff/`
- **状态**: ⚠️ 核心可用，UI 需改进

### 8.7 ER 图
- **功能**: 数据库实体关系图可视化
- **入口**: 右键数据库 > View ER Diagram
- **核心文件**: `lib/organisms/connection/er_canvas.dart`, `lib/services/er_diagram_service.dart`
- **状态**: ⚠️ 基本可用

### 8.8 智能导入
- **功能**: 自动检测文件格式、类型推断、列映射、数据验证
- **入口**: 菜单 File > Import
- **核心文件**: `lib/organisms/smart_import/`, `lib/services/smart_import_service.dart`
- **状态**: ⚠️ 支持 CSV/JSON/SQL，需增强

### 8.9 数据导出
- **功能**: CSV/JSON/Excel/SQL INSERT 格式导出
- **入口**: 结果工具栏 Export 按钮
- **核心文件**: `lib/organisms/connection/export_dialog.dart`, `lib/services/export_service.dart`
- **状态**: ✅ 核心格式支持

### 8.10 数据备份
- **功能**: 数据库结构+数据备份
- **入口**: 右键数据库 > Backup
- **核心文件**: `lib/organisms/connection/backup_dialog.dart`, `lib/services/backup_service.dart`
- **状态**: ⚠️ 部分数据库支持

### 8.11 查询历史
- **功能**: 持久化查询历史、全文搜索、收藏、标签
- **入口**: 左侧边栏 Query History 区域
- **核心文件**: `lib/organisms/sidebar/query_history/`, `lib/providers/query_history_provider.dart`
- **状态**: ✅ 完整

### 8.12 查询优化器
- **功能**: EXPLAIN 解析、索引建议、查询重写、性能分析
- **入口**: 编辑器工具栏 Optimize 按钮
- **核心文件**: `lib/organisms/query_optimizer/`, `lib/services/query_optimizer/`
- **状态**: ⚠️ 引擎层完整，UI 待完善

### 8.13 Workspace 系统（已移除）
- **原功能**: 连接+数据库绑定的工作区，独立标签页组，多 Workspace 快速切换
- **当前状态**: 该模块已架构性移除，由扁平 Tab 架构取代。`lib/organisms/workspace/` 目录保留但为空，`WorkspaceProvider` 不再存在。
- **替代文件**: `lib/providers/tab_provider.dart` 管理所有标签页状态

### 8.14 任务面板
- **功能**: 后台任务显示、进度跟踪、任务取消
- **入口**: 底部状态栏任务图标
- **核心文件**: `lib/organisms/task_panel/`, `lib/providers/task_provider.dart`
- **状态**: ⚠️ 基本可用

### 8.15 命令面板
- **功能**: 快速命令搜索与执行
- **入口**: Ctrl+Shift+P
- **核心文件**: `lib/organisms/connection/command_palette.dart`
- **状态**: ✅ 完整

### 8.16 代码片段
- **功能**: SQL 代码模板管理与插入
- **入口**: 编辑器右键 > Insert Snippet
- **核心文件**: `lib/organisms/connection/code_snippets_panel.dart`, `lib/services/code_snippet_service.dart`
- **状态**: ✅ 完整

### 8.17 认证系统
- **状态**: ❌ 已移除
- **说明**: 用户注册/登录/密码重置/个人资料模块已整体移除。当前仅保留 `auth_token_storage.dart` 用于数据库连接凭据的安全存储。

### 8.18 审计日志
- **功能**: 操作记录、敏感操作追踪
- **入口**: 菜单 View > Audit Log
- **核心文件**: `lib/organisms/dialogs/audit_log_dialog.dart`, `lib/services/audit_log_service.dart`
- **状态**: ✅ 完整

### 8.19 PII 掩码
- **功能**: 个人身份信息自动检测与脱敏
- **入口**: 查询结果工具栏 Mask PII 按钮
- **核心文件**: `lib/organisms/dialogs/pii_masking_dialog.dart`, `lib/services/pii_masker.dart`
- **状态**: ✅ 完整

### 8.20 主题系统
- **功能**: 暗色/亮色/跟随系统主题切换 + 8 种强调色
- **入口**: 菜单 View > Theme
- **核心文件**: `lib/theme/`, `lib/providers/theme_provider.dart`
- **状态**: ✅ 完整

### 8.21 国际化
- **功能**: 6 种语言运行时切换
- **入口**: 菜单 View > Language
- **核心文件**: `lib/l10n/`, `lib/providers/locale_provider.dart`
- **状态**: ✅ 完整

### 8.22 快捷键系统
- **功能**: 全局快捷键映射、自定义、冲突检测
- **入口**: 设置 > Shortcuts
- **核心文件**: `lib/core/shortcuts/`, `lib/organisms/dialogs/shortcuts_dialog.dart`
- **状态**: ✅ 完整

### 8.23 数据同步
- **功能**: 跨数据库数据同步
- **入口**: 菜单 Tools > Data Sync
- **核心文件**: `lib/organisms/connection/data_sync_dialog.dart`, `lib/services/data_sync/`
- **状态**: ⚠️ 实验性

### 8.24 存储过程/触发器管理
- **功能**: 存储过程查看/编辑/执行、触发器管理
- **入口**: 侧边栏右键
- **核心文件**: `lib/organisms/dialogs/procedure_editor_dialog.dart`, `lib/organisms/dialogs/triggers_dialog.dart`
- **状态**: ⚠️ 仅 SQL 数据库支持

### 8.25 测试数据生成
- **功能**: 假数据生成用于测试
- **入口**: 菜单 Tools > Generate Test Data
- **核心文件**: `lib/services/data_generation_service.dart`, `lib/services/faker_data_service.dart`
- **状态**: ⚠️ 基本可用

### 8.26 状态栏
- **功能**: 连接状态、数据库名、行数、执行时间、编码显示
- **入口**: 主界面底部
- **核心文件**: `lib/organisms/connection/status_bar_widget.dart`
- **状态**: ✅ 完整

### 8.27 标签页管理
- **功能**: 新建/关闭/拖拽排序/恢复关闭的标签页
- **入口**: 标签栏
- **核心文件**: `lib/organisms/connection/tabs_bar_widget.dart`, `lib/providers/tab_provider.dart`
- **状态**: ✅ 完整

### 8.28 数据编辑
- **功能**: 行内编辑、批量更新
- **入口**: 双击结果单元格
- **核心文件**: `lib/organisms/connection/editable_data_grid.dart`
- **状态**: ⚠️ 基本可用

### 8.29 查询计划可视化
- **功能**: EXPLAIN 结果图形化展示
- **入口**: 编辑器工具栏 Explain 按钮
- **核心文件**: `lib/organisms/query_optimizer/query_plan_visualizer.dart`
- **状态**: ⚠️ 基本可用

### 8.30 Pro/Free 功能门控
- **功能**: 免费版限制 (MySQL+SQLite, 3 连接)、Pro 解锁全部功能
- **入口**: 购买按钮/触发 Pro 功能时
- **核心文件**: `lib/providers/purchase_provider.dart`, `lib/services/purchase_service.dart`
- **状态**: ✅ 完整

---

## 9. 数据模型层

### 9.1 核心模型

| 模型文件 | 关键类 | 说明 |
|---------|--------|------|
| `models/database_models.dart` | `DatabaseConnection`, `QueryResult`, `DbServer`, `DatabaseType` | 数据库核心数据类 |
| `models/execution_result.dart` | `ExecutionResult`, `ExecutionSummary` | 查询执行结果封装 |
| `models/sql_statement.dart` | `SqlStatement` | SQL 语句解析结果 |
| `models/connection_event.dart` | `ConnectionEvent` | 连接事件 |
| `models/workspace_models.dart` | `Workspace`, `QueryTab` | Workspace 数据模型 |

### 9.2 AI 模型

| 模型文件 | 说明 |
|---------|------|
| `models/ai_models.dart` | AI 提供商/模型/消息类型 |
| `models/ai_message_type.dart` | AI 消息数据结构 |
| `models/ai_conversation_session.dart` | AI 会话会话数据 |
| `models/agent_checkpoint.dart` | Agent 检查点状态 |

### 9.3 数据库特定模型

| 模型文件 | 说明 |
|---------|------|
| `models/mongodb_models.dart` | MongoDB 集合/文档模型 |
| `models/redis_key_models.dart` | Redis 键/值模型 |
| `models/redis_function.dart` | Redis 函数模型 |
| `models/redis_script.dart` | Redis Lua 脚本模型 |
| `models/tdengine_models.dart` | TDengine 超级表模型 |

### 9.4 功能模型

| 模型文件 | 说明 |
|---------|------|
| `models/schema_diff_models.dart` | Schema 差异模型 |
| `models/smart_import_models.dart` | 智能导入配置模型 |
| `models/task_models.dart` | 后台任务模型 |
| `models/code_snippet.dart` | 代码片段模型 |
| `models/query_history.dart` / `models/query_history/query_record.dart` | 查询历史模型 |
| `models/er_diagram.dart` | ER 图模型 |
| `models/backup_models.dart` | 备份配置模型 |
| `models/import_models.dart` | 导入配置模型 |
| `models/editable_data.dart` | 可编辑数据模型 |
| `models/audit_log_entry.dart` | 审计日志条目 |
| `models/data_sync_models.dart` | 数据同步模型 |
| `models/drag_models.dart` | 拖拽数据模型 |
| `models/result_filter.dart` | 结果过滤模型 |
| `models/result_search.dart` | 结果搜索模型 |
| `models/formatter_models.dart` | 格式化配置模型 |
| `models/performance_models.dart` | 性能指标模型 |
| `models/query_optimizer/execution_plan.dart` | 执行计划模型 |
| `models/schema_analyzer/impact_report.dart` | 影响评估报告 |
| `models/stored_procedure.dart` | 存储过程模型 |
| `models/trigger.dart` | 触发器模型 |


---

## 10. 主题系统

### 10.1 两层设计

1. **`AppDesignSystem`** (`lib/theme/design_system.dart`) — 规范级 Token 常量
   - 间距 (Spacing): xs(4), sm(8), md(16), lg(24), xl(32)
   - 圆角 (Radii): sm(4), md(8), lg(12), xl(16)
   - 颜色 (Colors): 语义化颜色常量
   - **新代码必须使用此类**

2. **`AppTheme`** (`lib/theme/app_theme.dart`) — ThemeData 构建器
   - `AppTheme.light(accentColor)` / `AppTheme.dark(accentColor)`
   - 便捷方法: `cardDecoration()`, `inputDecoration()` 等
   - 旧版颜色别名标记 `@Deprecated`，应迁移到 `AppDesignSystem`

### 10.2 ThemeProvider

管理 `AppThemeMode` enum (`dark`, `light`, `system`) 和 `AccentColorType` (8 种颜色 + 自定义):
- 持久化键: `app_theme_mode`, `app_accent_color`
- 编辑器高亮颜色由 `AppTheme` / `AppDesignSystem` 统一提供；`lib/theme/sql_editor_colors.dart` 不存在

---

## 11. 国际化系统

### 11.1 技术方案

使用 Flutter `intl` / ARB 系统：
- 源文件: `lib/l10n/app_*.arb` (6 个语言)
- 生成文件: `lib/l10n/app_localizations*.dart`
- 生成命令: `flutter gen-l10n`

### 11.2 语言列表

| 代码 | 语言 | ARB 文件 |
|------|------|---------|
| en | English | `app_en.arb` (源) |
| zh | 简体中文 | `app_zh.arb` |
| zh_TW | 繁體中文 | `app_zh_TW.arb` |
| de | Deutsch | `app_de.arb` |
| fr | Français | `app_fr.arb` |
| ru | Русский | `app_ru.arb` |

### 11.3 LocaleProvider

运行时语言切换，通过 `LocaleProvider.locale` → `MaterialApp.locale` 传递给整个 Widget 树。

---

## 12. Pro/Free 功能门控

### 12.1 三层架构

```
PurchaseService         — 单例，in_app_purchase 封装
  ↓
ProStatusStorage        — 持久化层（FlutterSecureStorage/SharedPreferences）
  ↓
PurchaseProvider        — ChangeNotifier，暴露 isPro
  ↓
AppProvider             — 业务门控（isDatabaseTypeAllowed, canAddConnection, canUseAi）
```

### 12.2 限制规则

| 功能 | Free | Pro |
|------|------|-----|
| 数据库类型 | MySQL + SQLite | 全部 8 种 |
| 最大连接数 | 3 | 无限 |
| AI 功能 | ❌ | ✅ |
| Schema Diff | ❌ | ✅ |
| 数据导入 | ❌ | ✅ |
| 自定义强调色 | ❌ | ✅ |

### 12.3 产品 ID

- `com.dbmaster.app.pro.monthly`
- `com.dbmaster.app.pro.yearly`

### 12.4 安全要求

Pro 状态 **绝对不能** 以明文存储在 SharedPreferences 中。使用 `FlutterSecureStorage`，web 降级到加密的 SharedPreferences。

---

## 13. 关键技术决策

### 13.1 Provider Facade 模式

**决策**: 使用单一 `AppProvider` 聚合约 10 个核心子 Provider，统一暴露给 UI 层。

**理由**:
- Widget 树只需 `context.watch<AppProvider>()` 即可访问全部状态
- 跨 Provider 协作在 AppProvider 层统一处理
- 各子 Provider 保持职责单一

**代价**: AppProvider 耦合了所有子 Provider，需要大量 proxy 方法。

### 13.2 ChangeNotifierProxyProvider 双向绑定

**决策**: TaskProvider 和 AppProvider 通过 `ChangeNotifierProxyProvider` 的 `update` 回调互相注入依赖。

**理由**: TaskProvider 需要 DatabaseService 来执行 AI 任务，DatabaseService 由 ConnectionProvider 持有。两者不存在自然的父子/先后关系，必须双向绑定。

### 13.3 适配器能力接口模式

**决策**: 使用 `if (adapter is DdlAdapter)` 运行时类型检查，而非在基类中定义所有方法。

**理由**: 8 种数据库能力差异极大（MySQL 支持事务/DDL/Schema，MongoDB 是文档数据库），统一接口会导致大量 no-op 实现或异常抛出。

### 13.4 SQL Server FFI 条件导出

**决策**: 使用 Dart conditional exports 分离 SQL Server 的 FFI 实现和 Web 存根。

**理由**: FreeTDS DB-Library 通过 FFI 调用原生 C 库，在 Web 上不可用。条件导出允许同一 `import` 语句在不同平台加载不同实现。

### 13.5 MySQL/Doris 基础适配器继承

**决策**: MySQL 和 Doris 共用 `MySQLBaseAdapter`，`mysql_adapter.dart` 只保留约 11 行的条件导出/子类选择逻辑，`doris_adapter.dart` 覆盖 Doris 特定行为。

**理由**: 通过基类继承复用 908 行 MySQL 协议实现，避免两套适配器重复；当前两者各自维护独立连接，不再依赖早期的 `bindConnection()` 会话模型。

### 13.6 主题 Token 系统

**决策**: 采用两层主题设计 — `AppDesignSystem` (语义 Token) + `AppTheme` (Material ThemeData)。

**理由**: Token 常量便于 AI 代码生成和跨组件一致性，Material ThemeData 确保原生 Material 组件正确渲染。

### 13.7 ARB 国际化 + 运行时切换

**决策**: 使用 Flutter 官方 intl/ARB 方案，支持运行时语言切换。

**理由**: ARB 是 Flutter 推荐方案，工具链成熟。运行时切换通过 LocaleProvider 实现，无需重启。

---

## 14. 目录结构完整清单

```
dbmaster-flutter/
├── lib/                                   # 338 个 Dart 文件
│   ├── main.dart                          # 应用入口，Provider 树配置
│   ├── atoms/                             # 原子 UI 组件 (~10 文件)
│   ├── molecules/                         # 分子 UI 组件 (~12 文件)
│   ├── organisms/                         # 功能区域组件
│   │   ├── ai_panel/                      # AI 面板 (13 文件)
│   │   ├── charts/                        # 图表 (1 文件)
│   │   ├── connection/                    # 连接/对话框/ER/表操作 (~29 文件)
│   │   │   └── table_dialog/              # 表操作对话框 (9 文件)
│   │   ├── dialogs/                       # 通用对话框 (14 文件)
│   │   ├── editor/                        # SQL 编辑器 (14 文件)
│   │   │   └── shortcuts/                 # 编辑器快捷键
│   │   ├── query_optimizer/               # 查询优化器 UI (1 文件)
│   │   ├── results/                       # 结果展示 (7 文件)
│   │   ├── sidebar/                       # 侧边栏 (19 文件)
│   │   │   └── builders/                  # 树构建器
│   │   │       ├── context_menus/         # 右键菜单 (3 文件)
│   │   │       └── dialogs/               # 对话框 (3 文件)
│   │   ├── smart_import/                  # 智能导入 (2 文件)
│   │   ├── task_panel/                    # 任务面板 (4 文件)
│   │   └── workspace/                     # 目录保留，当前为空（Workspace 概念已由扁平 Tab 架构取代）
│   ├── pages/                             # 独立页面
│   │   ├── ai_chat/                       # AI 聊天页 (1 文件)
│   │   └── auth/                          # 认证页面 (6 文件)
│   ├── screens/                           # 主屏幕 (2 文件)
│   ├── templates/                         # 布局模板 (6 文件)
│   ├── providers/                         # 状态管理 (14 文件)
│   ├── services/                          # 业务逻辑
│   │   ├── adapters/                      # 数据库适配器 (17 文件)
│   │   ├── ai/                            # AI 子系统
│   │   │   ├── prompt_builders/           # Prompt 构建器 (~7 文件)
│   │   │   └── response_parsers/          # 响应解析器 (~7 文件)
│   │   ├── data_sync/                     # 数据同步 (1 文件)
│   │   ├── query_history/                 # 查询历史 (2 文件)
│   │   ├── query_optimizer/               # 查询优化器 (4 文件)
│   │   ├── schema_analyzer/               # Schema 分析 (4 文件)
│   │   ├── schema_diff/                   # Schema 差异 (3 文件)
│   │   └── task/                          # 任务执行器 (3 文件)
│   ├── models/                            # 数据模型 (~32 文件)
│   │   ├── auth/                          # 认证模型 (2 文件)
│   │   ├── query_history/                 # 查询历史模型
│   │   ├── query_optimizer/               # 执行计划模型
│   │   └── schema_analyzer/               # 影响报告模型
│   ├── config/                            # 应用配置 (1 文件)
│   ├── core/                              # 基础设施
│   │   ├── commands/                      # 命令定义 (1 文件)
│   │   ├── errors/                        # 异常体系 (1 文件)
│   │   └── shortcuts/                     # 快捷键系统 (1 文件)
│   ├── domain/services/mocks/             # Mock 服务 (1 文件)
│   ├── theme/                             # 主题 (3 文件)
│   ├── l10n/                              # 国际化 ARB + 生成代码 (~18 文件)
│   └── utils/                             # 工具类 (~10 文件)
├── test/                                  # 单元/Widget 测试 (212 文件)
├── integration_test/                      # 集成测试 (29 文件)
├── docs/                                  # 文档 (~45 文件)
├── scripts/                               # 构建/数据生成脚本
├── assets/                                # 静态资源
├── pubspec.yaml                           # 依赖配置
└── README.md                              # 项目说明
```

---

## 附录

### A. 开发命令速查

```bash
flutter pub get                              # 安装依赖
flutter run                                  # 调试运行
flutter test                                 # 运行全部单元测试
flutter test test/some_test.dart             # 运行单个测试
dart run build_runner build                  # 重新生成 mock
flutter analyze                              # 代码分析
flutter gen-l10n                             # 重新生成国际化代码
```

### B. 相关文档

- [统一测试规格](test/unified_test_spec.md) — 全部测试用例
- [测试文档 README](test/README.md) — 测试文档导航
- [布局审查报告](refactoring/layout_review.md) — 布局问题清单及修复进度
- [AI 开发指南（已归档）](../archive/ai_readme.md) — 历史 AI 术语说明，部分类名已过期

---

*文档结束*

## 附录 C：布局重构历史 (2026-06-09)

| 问题 | 描述 | 变更 |
|------|------|------|
| #1 | `home_screen.dart` 1161行臃肿 | 拆分 `AiPanelOverlay` + `AiMiniFab` 至 `organisms/ai_panel/` |
| #2 | `ResultSubTabBar` 位于 `EditorResultsSplit` 外部 | 内聚至 `ResultsWidget` 内部，数据源切换为 `activeResults[activeResultIndex]` |
| #3 | AI 全屏浮层时主工作区仍构建 | 条件跳过 `Row` 构建 |
| B1 | 切换 Query Tab 时结果面板相同 | Widget key 加 `tabId` 隔离 + 清理 `_tabStates` 缓存 |
| #9 | 间距值硬编码 | 全项目 ~3000 处 `EdgeInsets`/`SizedBox` 替换为 `AppDesignSystem.spaceX` 令牌 |
| #4 | Tab 栏无溢出处理 | 添加 `∨` 溢出下拉菜单，列出所有 Tab 并支持快速切换/关闭 |
| #5 | 编辑器/结果只支持上下 | 新增 `EditorResultsOrientation` 枚举 + 工具栏 ⇄/⇅ 切换按钮，支持左右分栏 |
| #6 | 缺少面包屑导航 | 新增 `BreadcrumbBar`，在 Tab 栏与编辑器之间显示 [M] 连接 > 数据库 路径 |
| #14 | Consumer 粒度过粗 | 三处关键 `context.select` 优化，减少无关 Provider 变更导致的重建 |
| #10 | Resizer 组件重复 | 合并为 `AppResizer` + typedef 向后兼容，270→155行 |
| #7 | AI 浮层交互复杂 | 去除拖拽 resize/透明度滑块/FAB 拖拽，改为 S/M/L 预设尺寸 + 固定效果 |

**新增文件**：
- `lib/organisms/ai_panel/ai_panel_overlay.dart` (~400行)
- `lib/organisms/ai_panel/ai_mini_fab.dart` (~150行)
- `docs/refactoring/layout_review.md` (布局审查 + 修复追踪)
- `test/providers/tab_provider_test.dart` (+3 新测试)

*最后更新: 2026-06-16*
