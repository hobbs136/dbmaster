# Workspace 布局变更 — 修复计划

## 背景
WorkspaceTabBar 已从全宽顶部移至右侧主区域上方（Sidebar 右侧）。此变更需要配套修复状态路由层面的连锁反应，确保所有 tab 操作在 workspace 模式下正确路由到 workspace 内部，而非全局 TabProvider。

## 阶段一：修复高优先级功能异常

### 1.1 修复 DDL 执行结果不写入 workspace
**文件**: `lib/providers/app_provider.dart`
**问题**: `executeQueryBypassDdlAndUpdateResults()` 第 730 行直接调用 `tab.updateTabExecutionResults(...)`，绕过 workspace 路由。
**方案**: 将 `tab.updateTabExecutionResults(activeTabIndex, ...)` 改为 `updateTabExecutionResults(activeTabIndex, ...)`（调用 AppProvider 自身的兼容方法）。

### 1.2 修复 Query Tab 重命名在 Workspace 下无效
**文件**: `lib/organisms/connection/tabs_bar_widget.dart`
**问题**: 第 112 行 `provider.tab.renameTab(index, controller.text)` 直接操作全局 TabProvider。
**方案**: 
- 在 AppProvider 添加 `renameTab(int index, String title)` 兼容方法（优先 workspace，fallback 全局）
- TabsBarWidget 中改为调用 `provider.renameTab(index, ...)`

### 1.3 修复 Duplicate Tab 在 Workspace 下添加到全局
**文件**: `lib/organisms/connection/tabs_bar_widget.dart`
**问题**: 第 233 行 `provider.tab.addTab(tab.copyWith(...))` 直接操作全局 TabProvider。
**方案**: 改为 `provider.addTab(tab.copyWith(...))`（AppProvider.addTab 已有 workspace 路由）。

### 1.4 修复 AI Panel 修改 tab 的 connection/database
**文件**: `lib/organisms/ai_panel/ai_panel_widget.dart`
**问题**: 第 2265-2267 和 2342-2344 行调用 `provider.updateTabConnection()` / `provider.updateTabDatabase()`，这两个方法在 AppProvider 中没有 workspace 路由，且已被标记 @Deprecated。
**方案**: 
- 在 workspace 模式下，query tab 的 connectionId / databaseName 由 workspace 固定绑定，不应被 AI Panel 修改
- 因此，在 AI Panel 的这两个调用点添加判断：若 `provider.workspace.activeWorkspace != null`，则跳过 updateTabConnection/updateTabDatabase 调用（或改为只修改 SQL 内容，不修改连接上下文）

## 阶段二：修复中优先级功能不完整

### 2.1 统一 QueryEditor 执行逻辑
**文件**: `lib/organisms/editor/query_editor_widget.dart`
**问题**: 第 920 行直接调用 `provider.tab.executeCurrentQuery(...)`，绕过 `executeCurrentQueryAndRecord()`，导致查询历史不被记录。
**方案**: 
- 将 QueryEditor 中的执行逻辑统一改为调用 `provider.executeCurrentQueryAndRecord()`
- 但需注意：QueryEditor 当前会传递 `overrideSql` 参数，而 `executeCurrentQueryAndRecord()` 内部已经从 `activeTab.sql` 获取 SQL
- 因此需要让 `executeCurrentQueryAndRecord()` 支持传入 `overrideSql` 参数，或者让 QueryEditor 先更新 activeTab.sql 再调用

### 2.2 给缺失 workspace 路由的方法添加兼容层
**文件**: `lib/providers/app_provider.dart`
**问题**: `formatCurrentSql()`、`cancelQuery()`、`saveQuery()`、`openSavedQuery()` 缺少 workspace 路由。
**方案**: 
- `formatCurrentSql()`: 添加 workspace 路由，优先取 workspace activeTab
- `cancelQuery()`: 添加 workspace 路由，优先取 workspace activeTab 的 sessionId 作为 trackingKey
- `saveQuery()`: 添加 workspace 路由，优先保存 workspace activeTab
- `openSavedQuery()`: 添加 workspace 路由，优先在当前 workspace 打开

## 阶段三：视觉优化

### 3.1 区分两级 Tab 的视觉层级
**文件**: `lib/organisms/workspace/workspace_tab_bar.dart` + `lib/organisms/connection/tabs_bar_widget.dart`
**问题**: 一级 WorkspaceTabBar 和二级 Query TabBar 紧邻堆叠，视觉上可能难以区分。
**方案**: 
- 给 WorkspaceTabBar 增加细微的高度/背景色差异（如高度 38px，背景色略深于 Query TabBar）
- 或给 WorkspaceTabBar 和 Query TabBar 之间增加更明显的分割线
- 保持改动最小，只做样式微调

## 验证清单
- [ ] DDL 执行后结果正确显示在 workspace query tab 中
- [ ] 在 workspace 模式下可以重命名 query tab
- [ ] 在 workspace 模式下可以 duplicate query tab
- [ ] AI Panel 执行 SQL 时不会错误修改 workspace 的 connection/database
- [ ] 查询历史正常记录
- [ ] 取消查询、格式化、保存查询在 workspace 模式下正常工作
- [ ] flutter analyze 无新增错误
