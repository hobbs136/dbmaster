# DbMaster 统一测试用例规格

**版本**: v1.7  
**日期**: 2026-07-29  
**适用范围**: DbMaster v3.2.0+  
**自动化状态**: ~3,728 单元/Widget 用例 / 214 测试文件 / 全量稳定（无已知偶发失败）；含集成约 ~4,240 用例 / 237 测试文件（另：dbmaster-server Rust 集成测试 33 例，见 18.6.2）
**近期修复 (2026-07-30)**: 三个 flake 存案清零——① `clearAllBackups`：`returnsNormally` 不 await Future 导致 Future 逃逸竞态，改 `await expectLater(..., completes)` 根因修复（同类隐患 widget_test×3、query_history_provider×1 已一并修复）；② `empty content roundtrip`：3200 次随机 salt/nonce 压力测试未复现，定性 runner 层噪声，零改动；③ `sqlserver_golden_disconnect` hang：产品层根因修复（dbsettime/dbsetlogintime FFI 绑定落地，SS-TIMEOUT-301 实证 30s 中止）+ isolate 看门狗护栏保留兜底
**近期修复 (2026-07-29)**: 盘点 12 个预存失败文件，修复 8 处真实问题——① T051 给 SidebarTree/AppHeader 加 ServerConnectionProvider 依赖后 3 个测试文件未同步注入（sidebar 8 例、app_components 1 例）；② `ServerConnectionProvider.dispose()` 误杀全局单例的 ValueNotifier（生产 bug）；③ M1 免费化后 mongodb_connection_form 仍断言旧 Pro 门控语义（1 例）；④ feature 039 只读守卫 fail-closed 后 stored_procedure/trigger 测试未 stub `currentServer`（16 例）；⑤ mongodb_validator 两个非法 JSON fixture（`\.` 与 `\w` 非法转义、`$x(...)` 未用 `${}` 插值）；⑥ `importBackup` 按 `Platform.pathSeparator` 切文件名导致 Windows 混合分隔符路径失败（生产 bug）

---

## 1. 概述与导航

### 1.1 文档目的

本文档是 DbMaster 项目 **唯一权威的测试用例入口**，整合了原有 40+ 个分散测试文档并补充了 ~125 个缺失模块的测试用例。

### 1.2 测试策略（自动化优先）

**核心理念**: 能自动化的绝不人工验证，能用纯逻辑测试的决不依赖 Widget 渲染。

| 判定条件 | 测试类型 | 工具 |
|---------|---------|------|
| 纯逻辑（算法、数据转换、状态变更） | **自动化单元测试** | flutter_test, mockito |
| 数据模型（toJson/fromJson/copyWith） | **自动化单元测试** | flutter_test |
| Widget 组件渲染、状态切换、事件回调 | **自动化 Widget 测试** | flutter_test WidgetTester |
| 涉及外部系统（真实数据库、网络 API） | **集成测试** | flutter_test integration |
| 视觉颜色/主题/多语言一致性 | **仅人工** (无法自动化) | 肉眼检查 |
| 键盘快捷键、拖拽、动画平滑度 | **仅人工** (无法自动化) | 手工操作 |
| 长时间稳定性、性能体验 | **仅人工** (无法自动化) | 监控工具 |

### 1.3 测试用例编号规则

```
[层级]-[模块]-[序号]

层级代码:
  C     = Core           (核心基础设施)
  P     = Provider       (状态管理)
  M     = Model          (数据模型)
  AD    = Adapter        (数据库适配器)
  AI    = AI Service     (AI 系统)
  SQL   = SQL Service    (查询服务)
  SC    = Schema         (Schema/ER/导入导出)
  SEC   = Security       (安全与认证)
  UA    = UI Atom        (原子组件)
  UM    = UI Molecule    (分子组件)
  UE    = UI Editor      (编辑器)
  UR    = UI Results     (结果展示)
  US    = UI Sidebar     (侧边栏)
  UC    = UI Connection  (连接/对话框)
  UEP   = UI EntityPanel (实体面板)
  UAI   = UI AI Panel    (AI 面板)
  UT    = UI Task        (任务面板)
  UW    = UI Workspace   (Workspace)
  UP    = Page           (页面/屏幕)
  PLG   = UI Plugin      (UI 插件框架 lib/plugins/)
  PORT  = Capability Port(能力缝/连接语义 lib/services/ports/)
  SVC   = Service        (专用服务)
  INT   = Integration    (集成测试)
  E2E   = End-to-End     (端到端)
  REG   = Regression     (回归测试)
```

### 1.4 测试环境搭建

```bash
# 前置条件
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# 运行全部自动化测试
flutter test

# 运行单个测试
flutter test test/path/to/test.dart

# 运行集成测试
flutter test integration_test/mysql_integration_test.dart \
  --dart-define=DBMASTER_MYSQL_HOST=<host>
```

### 1.5 相关文档索引

| 文档 | 内容 | 状态 |
|------|------|------|
| `unified_test_spec.md` (本文档) | 统一测试入口 | ✅ 主文档 |
| `app_wide_manual_test_cases.md` | 通用功能手动测试（被整合） | 📦 归档 |
| `mysql_manual_test_cases.md` | MySQL 手动测试（被整合） | 📦 归档 |
| `mysql_automated_test_cases.md` | MySQL 自动化（被整合） | 📦 归档 |
| `ai_panel_manual_test_cases.md` | AI 面板手动测试（被整合） | 📦 归档 |
| `workspace_manual_test_cases.md` | Workspace 手动测试（被整合） | 📦 归档 |
| 其余 35+ 文档 | 各模块测试文档（被整合） | 📦 归档 |
| `guides/integration_test_authoring_guide.md` | 集成测试编写指南 | 📋 参考 |

### 1.6 最新统计 (2026-06-08)

| 指标 | 数值 |
|------|------|
| 单元 + Widget 测试用例 | ~3,235 |
| 测试文件数 | 210 |
| 集成测试用例 | ~715 (31 文件) |
| 模型覆盖率 | ~91% (31/34) |
| AI 服务覆盖率 | ~91% (Batch 4 已完成) |
| Schema 服务覆盖率 | ~58% |
| 预存失败 (需外部服务) | 12 (SQL Server FFI + Redis 连接) |

---

## 2. 核心基础设施测试 (C)

### 2.1 主题系统

**自动化覆盖**: `test/theme/app_colors_test.dart` (21，含 F-11 语义色亮/暗双通道守卫组，特性 046 T005/T040 + #33 C06「brandColor 类型色主题分发」组), `test/theme/app_theme_test.dart` (9), `test/theme/design_system_test.dart` (20，含 #33 C06「类型色 *Dark 变体定版值 + WCAG 3:1 对比度」组), `test/theme/sql_editor_colors_test.dart` (9), `test/theme/lucide_migration_guard_test.dart` (2) — #33 C07 守卫（lib/ 禁止 Material `Icons.*` 残留 + `DatabaseType.typeIcon` Lucide 落位抽查）— 61 用例全部通过；`test/theme/semantic_color_usage_test.dart` — C-THEME-006（契约 C1 静态扫描：lib/ 禁止直用 `AppDesignSystem.error/success/warning/info`，须走 `context.themeColors.*` 分发）

**人工测试用例**:

| # | 用例 | 优先级 | 步骤摘要 | 预期结果 |
|---|------|--------|---------|---------|
| C-THEME-001 | 暗色模式切换 | P0 | View > Theme > Dark | 背景变深、文字变浅、所有面板同步、图标适配 |
| C-THEME-002 | 亮色模式切换 | P0 | View > Theme > Light | 背景变浅、文字变深、无暗色残留元素 |
| C-THEME-003 | 跟随系统模式 | P0 | View > Theme > System + 切换系统主题 | 实时跟随、无闪烁 |
| C-THEME-004 | 运行时主题切换保持状态 | P0 | 打开标签页+查询结果 → 切换主题 | 标签页保留、光标保持、侧边栏状态保持 |
| C-THEME-005 | 强调色切换 | P1 | 切换 8 种强调色 | 编辑器光标、选中高亮、按钮颜色即时变化 |
| C-THEME-007 | C06 四主题回归走查 | P0 | 亮/暗 × 编辑器冷暖四组合逐一切换走查（c02 §8.4） | 背景/文本/语义色正确；PG/TDengine/SQLite/SS 类型色暗色用提亮变体（可辨 ≥3:1）、亮色回官方色 |
| C-THEME-008 | C07 Lucide 图标走查 | P0 | 桌面走查高频界面（侧边栏/工具栏/右键菜单/连接对话框/设置） | 图标统一 Lucide 描边风格、无缺字方块（tofu）、无 Material 图标混排、尺寸观感协调 |

### 2.2 国际化

**自动化覆盖**: `test/l10n/localizations_test.dart` — 11 用例

**人工测试用例**:

| # | 用例 | 优先级 | 语言 | 验证重点 |
|---|------|--------|------|---------|
| C-I18N-001 | English | P0 | en | 无硬编码中文残留、布局无溢出 |
| C-I18N-002 | 简体中文 | P0 | zh | 术语翻译准确（Connection→连接） |
| C-I18N-003 | 繁體中文 | P0 | zh_TW | 繁体中文字符正确 |
| C-I18N-004 | Deutsch | P1 | de | 特殊字符 ä/ö/ü/ß 正确、长单词适配 |
| C-I18N-005 | Français | P1 | fr | 特殊字符 é/è/à/ç 正确 |
| C-I18N-006 | Русский | P1 | ru | 西里尔字母正确渲染 |
| C-I18N-007 | 运行时全界面切换验证 | P0 | 全部 | 逐语言检查所有界面字符串 |

### 2.3 快捷键系统

**自动化覆盖**: `test/core/shortcuts/global_shortcuts_test.dart`（全局快捷键）、`test/organisms/connection/quick_search_dialog_test.dart`（QuickSearch）、`test/utils/sql_escape_utils_test.dart`（标识符引用）

**人工测试用例**:

| # | 用例 | 优先级 | 快捷键 | 预期行为 |
|---|------|--------|--------|---------|
| C-KEY-001 | 执行查询 | P0 | F5 / Ctrl+Enter | 执行编辑器当前 SQL |
| C-KEY-002 | 命令面板 | P0 | Ctrl+Shift+P | 弹出命令列表、实时过滤、Esc 关闭 |
| C-KEY-003 | 新建标签页 | P0 | Ctrl+T | 在 Workspace 内新建 Query Tab |
| C-KEY-004 | 关闭标签页 | P0 | Ctrl+W | 关闭当前 Query Tab |
| C-KEY-005 | 格式化 SQL | P0 | Ctrl+Shift+F | 多行缩进格式化 |
| C-KEY-006 | 打开设置 | P1 | Ctrl+, | 弹出设置对话框 |

### 2.4 设置系统

**人工测试用例**:

| # | 用例 | 优先级 | 步骤摘要 |
|---|------|--------|---------|
| C-SET-001 | 修改编辑器字体大小 | P0 | 设置 > Editor > Font Size → 观察编辑器变化 |
| C-SET-002 | 修改 Tab 缩进大小 | P0 | 设置 > Tab Size → 按 Tab 验证空格数 |
| C-SET-003 | 启用/禁用行号 | P0 | 设置 > Show Line Numbers → 观察编辑器行号 |
| C-SET-004 | 修改结果页大小 | P0 | 设置 > Results Page Size → 执行查询验证分页 |
| C-SET-005 | 自动保存开关 | P1 | 开关 Auto Save → 编辑内容后观察标签标记 |
| C-SET-006 | 设置持久化 | P0 | 修改任意设置 → 重启应用 → 验证保留 |

### 2.5 错误边界

**自动化覆盖**: ErrorBoundary 机制在 `lib/organisms/connection/error_boundary.dart`

**人工测试用例**:

| # | 用例 | 优先级 |
|---|------|--------|
| C-ERR-001 | 应用崩溃恢复 | P0 |
| C-ERR-002 | SnackBar 错误/警告/成功/信息提示 | P1 |
| C-ERR-003 | 日志输出正确性 | P1 |

---

## 3. Provider 状态管理测试 (P)

### 3.1 已覆盖 Provider

| Provider | 测试文件 | 用例数 | 状态 |
|---------|---------|--------|------|
| AppProvider | `test/app_provider_test.dart` | 30 | ✅ |
| ConnectionProvider | `test/providers/connection_provider_test.dart` | 17 | ✅ |
| TabProvider | `test/providers/tab_provider_test.dart` | 20 | ✅ |
| SidebarProvider | `test/providers/sidebar_provider_test.dart` | 22 | ✅ |
| QueryHistoryProvider | `test/providers/query_history_provider_test.dart` | 24 | ✅ |
| TaskProvider | `test/providers/task_provider_test.dart` | 23 | ✅ |
| ThemeProvider | `test/providers/theme_provider_test.dart` | 19 | ✅ |
| LocaleProvider | `test/locale_provider_test.dart` | 15 | ✅ |
| AIConfigProvider | `test/ai_config_provider_test.dart` | 18 | ✅ |
| AIPanelProvider | `test/providers/ai_panel_provider_test.dart` | 29 | ✅ |
| PurchaseProvider | `test/providers/purchase_provider_test.dart` | 9 | ✅ |
| LayoutPreferencesProvider | `test/providers/layout_preferences_provider_test.dart` | 25 | ✅ |
| RecentTablesProvider | `test/providers/recent_tables_provider_test.dart` | 8 | ⚠️ 需补充 |

### 3.2 待补充自动化测试

| # | 用例 | 优先级 | 测试内容 |
|---|------|--------|---------|
| P-CONN-001 | ConnectionProvider 连接活性验证 | P0 | switchToConnection / connectToServer 半开连接清理 | ✅ 已覆盖 |
| P-CONN-002 | ConnectionProvider SSH 隧道连接 | P1 | SSH config → 隧道建立 → 通过隧道查询 |
| P-CONN-003 | ConnectionProvider 多连接并发 | P1 | 同时维护多个连接，切换不互相影响 |
| P-CONN-004 | ConnectionProvider 连接断开自动重连 | P1 | 模拟断线 → 自动重连 → 状态恢复 |
| P-RECENT-001 | RecentTablesProvider clearForConnection | P0 | 清除指定连接记录，其他连接保留 |
| P-SAVED-001 | TabProvider.savedQueriesFor 按连接+数据库过滤 | P0 | 保存查询按 connectionId + databaseName 正确分组 | ✅ 已覆盖 |
| P-SAVED-002 | TabProvider.getSavedQueryById 按 ID 查找 | P0 | 根据 queryId 返回对应保存查询，不存在返回 null | ✅ 已覆盖 |
| P-SAVED-003 | QueryTab JSON 序列化含 savedQueryId | P0 | toJson/fromJson 正确保留 savedQueryId；旧数据缺少该字段时反序列化不报错 | ✅ 已覆盖 |
| P-SAVED-004 | TabProvider.openQueryTab 使用保存查询标题 | P0 | 传入 title 与 savedQueryId 时，新 Tab 标题等于保存名称且携带 savedQueryId | ✅ 已覆盖 |
| P-SAVED-005 | TabProvider.saveQuery 按 savedQueryId 原地更新 | P0 | 对已存在 savedQueryId 的 Tab 保存时更新原查询，不创建重复项 | ✅ 已覆盖 |
| P-SAVED-006 | TabProvider.saveQuery 创建新保存查询 | P0 | 对无 savedQueryId 的 Tab 保存时创建新保存查询并分配 savedQueryId | ✅ 已覆盖 |
| P-SAVED-007 | TabProvider.saveQuery 同一连接下禁止重名 | P1 | 同一 connectionId 下已存在同名保存查询时抛出 DuplicateSavedQueryNameException | ✅ 已覆盖 |
| P-SAVED-008 | TabProvider.openQueryTab 已保存查询初始为未修改 | P0 | 传入 savedQueryId 打开 Tab 时 isSaved=true, isModified=false, originalSql=sql | ✅ 已覆盖 |
| P-SAVED-009 | TabProvider.updateTabSql 维护 isModified | P0 | 保存查询 Tab 的 SQL 偏离 originalSql 时 isModified=true，恢复时 false | ✅ 已覆盖 |
| P-SAVED-010 | TabProvider.closeTab 未修改保存查询直接关闭 | P0 | isSaved=true 且 isModified=false 的 Tab 关闭时不抛异常 | ✅ 已覆盖 |
| P-SAVED-011 | TabProvider.closeTab 已修改保存查询需确认 | P0 | isSaved=true 且 isModified=true 的 Tab 关闭时抛出 UnsavedTabException | ✅ 已覆盖 |
| P-SAVED-012 | TabProvider.saveQuery 保存后重置脏状态 | P0 | 保存成功后 Tab 的 isModified=false, originalSql=当前 sql | ✅ 已覆盖 |
| P-BULK-001 | TabProvider.isTabUnsaved 识别新建未保存 Tab | P0 | isSaved=false 且 sql 非空时返回 true | ✅ 已覆盖 |
| P-BULK-002 | TabProvider.isTabUnsaved 识别已修改保存查询 | P0 | isSaved=true 且 isModified=true 时返回 true | ✅ 已覆盖 |
| P-BULK-003 | BulkCloseController 默认全部 pending | P0 | 构造后所有 item.decision 为 pending | ✅ 已覆盖 |
| P-BULK-004 | BulkCloseController saveAllPending 仅影响 pending | P0 | 已显式 discard 的 Tab 不会被改为 save | ✅ 已覆盖 |
| P-BULK-005 | BulkCloseController discardAllPending 仅影响 pending | P0 | 已显式 save 的 Tab 不会被改为 discard | ✅ 已覆盖 |
| P-BULK-006 | BulkCloseController setDecision 更新单个 Tab | P0 | 设置后对应 item 状态改变并触发 notifyListeners | ✅ 已覆盖 |
| P-BULK-007 | BulkCloseController pendingAll 重置所有决定 | P1 | 调用后所有 item 回到 pending | ✅ 已覆盖 |
| P-BULK-008 | BulkCloseController decisionFor 对未知 Tab 返回 pending | P0 | 传入不在列表中的 Tab 时不抛异常，返回 pending | ✅ 已覆盖 |
| P-BULK-009 | BulkCloseController setDecision 忽略未知 Tab | P0 | 传入不在列表中的 Tab 时不抛异常、不通知监听器 | ✅ 已覆盖 |
| P-BULK-010 | BulkCloseController 处理已关闭的 stale Tab | P1 | 旧 controller 引用已不在新列表中的 Tab 时行为安全 | ✅ 已覆盖 |
| P-CLOSE-001 | CloseDecisionApplier 取消返回 false | P0 | result.confirmed=false 时不执行任何保存/关闭 | ✅ 已覆盖 |
| P-CLOSE-002 | CloseDecisionApplier 保存成功并关闭对应 Tab | P0 | save 回调返回 true 后按索引关闭该 Tab | ✅ 已覆盖 |
| P-CLOSE-003 | CloseDecisionApplier 保存失败阻止窗口关闭 | P0 | 任一 save 回调返回 false 时整体返回 false | ✅ 已覆盖 |
| P-CLOSE-004 | CloseDecisionApplier 忽略已不存在的 Tab | P0 | decisions 中引用已从列表移除的 Tab 时不抛异常 | ✅ 已覆盖 |
| P-CLOSE-005 | CloseDecisionApplier 3+ Tab 丢弃按高索引到低索引关闭 | P1 | 避免关闭过程中索引错位 | ✅ 已覆盖 |
| P-CLOSE-006 | 窗口关闭时未保存 Tab 显示批量确认对话框 | P0 | `_WindowCloseGuard` 使用全局 NavigatorKey 展示 `BulkCloseDialog`，不抛 null 异常 | ✅ 已覆盖 (`test/main/window_close_guard_test.dart`) |
| P-CLOSE-007 | 窗口关闭时全部 Tab 已保存则直接关闭 | P0 | 无未保存 Tab 时立即执行 `_doClose`，不显示对话框 | ✅ 已覆盖 (`test/main/window_close_guard_test.dart`) |
| P-CLOSE-008 | 窗口关闭对话框打开时忽略重复关闭事件 | P1 | `_showingDialog` 为 true 时再次触发 `onWindowClose` 不弹出第二个对话框 | ✅ 已覆盖 (`test/main/window_close_guard_test.dart`) |
| P-CLOSE-009 | 窗口关闭对话框取消后保留 Tab 状态 | P0 | 取消后 `closeRequested` 为 false，未保存 Tab 仍然存在 | ✅ 已覆盖 (`test/main/window_close_guard_test.dart`) |

### 3.3 人工测试用例

| # | 用例 | 优先级 |
|---|------|--------|
| P-MANUAL-001 | Pro/Free 功能门控 UI 表现 | P0 |
| P-MANUAL-002 | Workspace 切换时状态栏同步 | P0 |
| P-MANUAL-003 | 最近访问表实时更新 | P1 |

---

## 4. 数据模型测试 (M)

### 4.1 已覆盖模型 (12 个测试文件)

`test/models/ai_conversation_session_test.dart`, `test/models/ai_message_test.dart`, `test/models/code_snippet_test.dart`, `test/models/execution_result_test.dart`, `test/models/mongodb_models_test.dart`, `test/models/mongodb_p2_test.dart`, `test/models/redis_function_test.dart`, `test/models/redis_key_models_test.dart` (43 用例), `test/models/redis_script_test.dart`, `test/models/schema_diff_models_test.dart`, `test/models/smart_import_models_test.dart`, `test/models/task_models_test.dart`

### 4.2 模型测试覆盖状态 (Batch 1 已完成, +20 文件/+264 用例)

| # | 用例 | 优先级 | 模型文件 | 测试文件 | 状态 |
|---|------|--------|---------|---------|------|
| M-DB-001 | DatabaseModels 序列化 | P0 | `database_models.dart` | `test/models/database_models_extended_test.dart` | ✅ |
| M-DB-002 | DatabaseType enum 完整性 | P0 | | `test/models/database_models_test.dart` + `_extended_test.dart` | ✅ |
| M-EXEC-001 | ExecutionSummary 序列化 | P1 | `execution_result.dart` | `test/models/execution_summary_test.dart` | ✅ |
| M-AUDIT-001 | AuditLogEntry 序列化 | P1 | `audit_log_entry.dart` | `test/models/audit_log_entry_test.dart` | ✅ |
| M-BACKUP-001 | BackupModels 序列化 | P2 | `backup_models.dart` | `test/models/backup_models_test.dart` | ✅ |
| M-IMPORT-001 | ImportModels 序列化 | P2 | `import_models.dart` | `test/models/import_models_test.dart` | ✅ |
| M-ER-001 | ERDiagram/ERNode/EREdge | P2 | `er_diagram.dart` | `test/models/er_diagram_test.dart` | ✅ |
| M-IMPACT-001 | ImpactReport 序列化 | P2 | `schema_analyzer/impact_report.dart` | `test/models/impact_report_test.dart` | ✅ |
| M-EXPLAIN-001 | ExecutionPlan 序列化 | P2 | `query_optimizer/execution_plan.dart` | `test/models/execution_plan_test.dart` | ✅ |
| M-PERF-001 | PerformanceModels 序列化 | P2 | `performance_models.dart` | `test/models/performance_models_test.dart` | ✅ |
| M-EDITABLE-001 | EditableData 序列化 | P2 | `editable_data.dart` | `test/models/editable_data_test.dart` | ✅ |
| M-FILTER-001 | ResultFilter/ColumnFilter | P2 | `result_filter.dart` | `test/models/result_filter_test.dart` | ✅ |
| M-SEARCH-001 | ResultSearch 序列化 | P2 | `result_search.dart` | `test/models/result_search_test.dart` | ✅ |
| M-FORMAT-001 | FormatterModels 序列化 | P2 | `formatter_models.dart` | `test/models/formatter_models_test.dart` | ✅ |
| M-DRAG-001 | DragModels 序列化 | P2 | `drag_models.dart` | `test/models/drag_models_test.dart` | ✅ |
| M-CONN-EVENT-001 | ConnectionEvent 序列化 | P2 | `connection_event.dart` | `test/models/connection_event_test.dart` | ✅ |
| M-DATASYNC-001 | DataSyncModels 序列化 | P2 | `data_sync_models.dart` | `test/models/data_sync_models_test.dart` | ✅ |
| M-PROC-001 | StoredProcedure 序列化 | P2 | `stored_procedure.dart` | `test/models/stored_procedure_test.dart` | ✅ |
| M-TRIGGER-001 | Trigger 序列化 | P2 | `trigger.dart` | `test/models/trigger_test.dart` | ✅ |
| M-CP-001 | AgentCheckpoint 序列化 | P2 | `agent_checkpoint.dart` | `test/models/agent_checkpoint_test.dart` | ✅ |

> **模型覆盖率: ~90% (28/31)**。仅 `mongodb_models`、`redis_key_models`、`tdengine_models` 等少量数据库特定模型无独立单元测试（其逻辑已在适配器测试中覆盖）。

---

## 5. 数据库适配器测试 (AD)

### 5.0 网关 wire 透传（server 侧 SSH 隧道 + TLS 透传，2026-08-29）

| # | 用例 | 优先级 | 被测 | 测试文件 | 状态 |
|---|------|--------|------|---------|------|
| GW-WIRE-001 | DbServer useTls/tlsInsecure 序列化往返 + 旧 JSON 无键默认 false + copyWith | P0 | `database_models.dart` | `test/models/database_models_extended_test.dart` | ✅ |
| GW-WIRE-002 | fromDbServer extra 投影：useTls 两键 + ssh wire 对象（password/privateKey 两态、隧道关/host 空不生成） | P0 | `database_abstract.dart` | `test/services/database_abstract_test.dart` | ✅ |
| GW-WIRE-003 | isServerSideExecutedType：sqlite 唯一本地执行类型（网关壳类型不建本地 SSH 隧道） | P0 | `database_abstract.dart` | `test/services/database_abstract_test.dart` | ✅ |
| GW-WIRE-004 | redis/tdengine draft body：useTls 开启 → extra 两键；ssh 原样透传；关闭/无 ssh 不下发 | P0 | `redis_gateway_adapter.dart` / `tdengine_gateway_adapter.dart` | 同名 `*_test.dart` 新增 group | ✅ |
| GW-WIRE-005 | mongodb draft body：TLS 两键与集群四模式键合并同段 extra；ssh 透传 | P0 | `mongodb_gateway_adapter.dart` | `mongodb_gateway_adapter_test.dart` 新增 group | ✅ |
| GW-WIRE-006 | SQL 族（mysql 代表）draft body：ssh 对象透传；useTls 不透传（仅三类 NoSQL 生效） | P0 | `mysql_gateway_adapter.dart` | `mysql_gateway_adapter_test.dart` 新增 group | ✅ |

### 5.1 MySQL

**自动化**: `test/services/adapters/mysql_adapter_test.dart` (104 用例) + `mysql_mocks.dart` — 含 ProcessListAdapter (7)、ReplicationAdapter (6)、Engine status (4)  
**Widget**: `test/organisms/sidebar/mysql_process_panel_test.dart` (9) — 进程列表面板  
**Model**: `test/models/database_models_extended_test.dart` — ProcessInfo (5) + ReplicationStatus (8)  
**集成**: `integration_test/mysql_integration_test.dart` (60 用例)  
**性能基准**: `integration_test/mysql_performance_benchmark_test.dart` (3 用例) — $APPEAL Performance 维度基线：P1 元数据加载（getTables，1000/5000 表）、P2 大数据量取数（10 万行）、P3 查询取消（KILL QUERY 延迟）；参数可调（`DBMASTER_BENCH_TABLES` / `DBMASTER_BENCH_ROWS` / `DBMASTER_BENCH_STRICT`），基线数据见 `docs/appeal_product_analysis.md` §4.1.5  
**人工**: 见 `mysql_manual_test_cases.md` (📦 归档，主要覆盖 UI 交互)
- 连接管理 UI (连接/断开/SSH 配置)
- 侧边栏导航 (多数据库树形展开/折叠/右键菜单)
- 实体面板 (表/视图/存储过程/函数列表)
- 表结构管理 (创建/编辑/删除表 UI)
- 索引管理 (创建/编辑/删除索引 UI)
- 外键管理 (外键创建/删除 UI)
- 数据操作 UI (行内编辑/批量操作)
- Schema Diff & Sync UI
- 数据导入导出 UI
- 只读模式 UI

### 5.2 PostgreSQL

**自动化**: `test/services/adapters/postgresql_adapter_test.dart` (82 用例)  
**集成**: `integration_test/postgresql_integration_test.dart` (55 用例)  
**性能基准（contracts C1）**: `integration_test/postgresql_performance_benchmark_test.dart` (3 用例) — P1 元数据（1000 表）、P2 大结果集（10 万行）、P3 查询取消（pg_cancel_backend）；基线见 `docs/appeal_product_analysis.md` §4.1.6  
**验收口径（feature 038, research.md D3）**: SC-001 的 P2 ≤1s 以 **Profile 模式**（`flutter drive --profile -d windows --target=integration_test/postgresql_performance_benchmark_test.dart`）为准——D3 记录实测 P2 = 249ms（Debug JIT 5471ms 为 per-row 异步架构在 JIT 下的伪影，非生产地板）；Debug strict 阈值降级为防劣化回归线，不作验收
**人工**: 同 MySQL 的 UI 交互覆盖面，加 PostgreSQL 特有功能 (Schema/表空间/扩展)

**2026-07-09 P1 新增（待编写测试）**：
| 用例 ID | 描述 | 优先级 | 类型 |
|---------|------|:------:|------|
| PG-EXT-001 | `getExtensions()` 返回已安装扩展列表（含 name/version/schema/description） | P1 | 单元 |
| PG-EXT-002 | `getExtensions()` 无扩展时返回空列表，不抛异常 | P1 | 单元 |
| PG-EXT-003 | `getVectorIndexes()` 检测 IVFFlat 索引（含 dimensions/distance） | P1 | 单元 |
| PG-EXT-004 | `getVectorIndexes()` 检测 HNSW 索引，区分 IVFFlat 视觉标识 | P1 | 单元 |
| PG-EXT-005 | `getVectorIndexes()` 无 pgvector 或未创建索引时返回空列表 | P1 | 单元 |
| PG-EXT-006 | `getJsonColumns()` 返回 jsonb/json 类型列名 | P1 | 单元 |
| PG-EXT-007 | `isJsonColumn()` 对 jsonb 列返回 true，integer/text 列返回 false | P1 | 单元 |
| PG-EXT-008 | `QueryResult.columnTypes` 包含 PG typeOid→name 映射（jsonb=3802, json=114） | P1 | 单元 |
| PG-EXT-101 | 侧边栏 Extensions 节点仅在 PG 连接时渲染（非 PG 不出现） | P1 | Widget |
| PG-EXT-102 | 展开 Extensions 节点 → 显示已安装扩展列表（名称+版本） | P1 | Widget |
| PG-EXT-103 | 点击扩展 → 详情面板显示元信息 + schema 分组成员列表 + 搜索过滤 | P1 | Widget |
| PG-EXT-104 | 扩展详情面板空/加载/错误状态正确渲染 | P1 | Widget |
| PG-EXT-105 | pgvector 扩展详情面板包含 Vector Indexes 区域（含索引名/类型/维度/距离） | P1 | Widget |
| PG-EXT-106 | JSONB 列在结果表格中以 `{…}` 标记区分（declared vs detected） | P1 | Widget |
| PG-EXT-107 | JSON 树查看器：展开/折叠、语法高亮、搜索、大字串截断、深度限制 | P1 | Widget |
| PG-EXT-201 | PG 真实连接：Extensions 节点 + 详情面板端到端验证 | P1 | 集成 |
| PG-EXT-202 | PG 真实连接：JSONB 列类型检测 + 树查看器渲染 | P1 | 集成 |

### 5.3 MongoDB

**自动化**: `test/services/adapters/mongodb_adapter_test.dart` (137 用例) + `mongodb_adapter_extended_test.dart` (10 用例)  
**集成**: `integration_test/mongodb_integration_test.dart` (62 用例) + `mongodb_real_data_test.dart`  
**性能基准**: `integration_test/mongodb_performance_benchmark_test.dart` (2 用例) — M1 集合元数据（500 集合）、M2 大结果集（10 万文档 find）；基线见 `docs/appeal_product_analysis.md` §4.1.6  
**人工**: 集合浏览、文档查看/编辑、聚合管道构建、索引管理 UI

#### 5.3.1 MongoDB 体验对等 (feature 018)

> 覆盖 spec `018-mongo-experience-parity` 的 5 个用户故事。新增自动化测试见下表“测试文件”列；带 ⚙️ 的为需实时 Mongo 的集成/人工用例。

| 用例 ID | 故事 | 用例 | 优先级 | 类型 | 测试文件 / 验证方式 |
|---------|------|------|--------|------|---------------------|
| AD-MG-V001 | US1 | `getViews()` 仅返回真正视图，不含 `system.*` | P1 | 集成 ⚙️ | `mongodb_adapter_test.dart`（连真实 Mongo 建视图断言） |
| AD-MG-EX001 | US4 | `getExplainPlan()` 返回服务端 plan（queryPlanner/executionStats），非静态提示 | P2 | 集成 ⚙️ | `mongodb_adapter_test.dart`（解析失败应回退提示不抛异常） |
| AD-MG-EXP001 | US5 | `exportCollection()` 输出合法 JSON / CSV | P3 | 集成 ⚙️ | `mongodb_adapter_test.dart` |
| AD-MG-EXP002 | US5 | `analyzeExport()` 使用原生 stats + 抽样，非 SQL `SELECT COUNT(*)` | P3 | 集成 ⚙️ | `mongodb_adapter_test.dart` |
| AD-MG-DQ001 | US5 | `analyzeDataQuality()` 每字段完整度/类型一致性/空值率 | P3 | 集成 ⚙️ | `mongodb_adapter_test.dart` |
| AD-MG-TD001 | US5 | `generateTestData()` 依 schema 合成并插入 N 条 | P3 | 集成 ⚙️ | `mongodb_adapter_test.dart` |
| AI-MG-OPT001 | US4 | MongoOptimizerService：无投影/`$match` 未前置/`$lookup`/弃用 count | P2 | 单元 ✅ | `test/services/mongo_optimizer_service_test.dart` |
| AI-MG-INJ001 | US4 | NoSqlInjectionDetector：`$where`/`$function`/认证操作符注入/正则注入 | P2 | 单元 ✅ | `test/services/nosql_injection_detector_test.dart` |
| AI-MG-IDX001 | US4 | MongoIndexAdvisorService：ESR 复合索引建议 + 既有索引去重 | P2 | 单元 ✅ | `test/services/mongo_index_advisor_test.dart` |
| AI-MG-TOOL001 | US5 | 工具注册：Mongo 含 5 个写/运维工具，不含 SQL 专用工具 | P3 | 单元 ✅ | `test/services/database_tool_registry_test.dart` |
| AI-MG-CMD001 | US4 | `/optimize`、`/analyze`、安全分析、`/explain` 在 Mongo 连接走原生路径 | P2 | 人工 ⚙️ | 连 Mongo → AI 面板逐一执行，确认无 SQL 错误 |
| SQL-M-MENU001 | US3 | Mongo/Redis Tab 右键菜单与工具栏均无 Format 项；格式化代码路径为安全 no-op | P2 | 人工 ✅ | 右键编辑器 + 触发格式化断言不崩 |

#### 5.3.2 MongoDB 日常生产力 (feature 020)

> 覆盖 spec `020-mongo-daily-productivity`：自动补全(US1) + 字段补全(US2) + 片段包(US3) + 历史加固(US4)。SQL→Mongo 翻译经评估砍除（见 spec Out of Scope）。

| 用例 ID | 故事 | 用例 | 优先级 | 类型 | 测试文件 / 验证方式 |
|---------|------|------|--------|------|---------------------|
| DP-MG-AC001 | US1 | Mongo tab 自动补全：集合名 / 方法名 / `$operator` 三类建议 | P1 | 单元 ✅ | `test/services/mongo_autocomplete_service_test.dart` (9) |
| DP-MG-AC002 | US1 | 光标上下文分类：`db.us`→集合；`db.users.`→方法；`{$`→$operator；不可解析→方法+$op 不抛 | P1 | 单元 ✅ | 同上 |
| DP-MG-AC003 | US1 | Mongo tab 不再误触发 SQL 补全；SQL tab 补全字节级不变 | P1 | 人工 ⚙️ | 连 Mongo → 编辑器输入断言 + SQL 回归 |
| DP-MG-AC004 | US1 | 弹窗复用 + Mongo 标题(l10n 6 语言) | P2 | 人工 ✅ | Mongo tab 触发补全查看标题 |
| DP-MG-FD001 | US2 | 字段补全：采样推断 `inferDocumentSchema` + `sampled · type · coverage%` 指示 | P2 | 单元 ✅ | `mongo_autocomplete_service_test.dart` (buildFieldSuggestions) |
| DP-MG-FD002 | US2 | 空集合 / 3s 超时 → 降级为集合+方法，不崩不挂 | P2 | 集成 ⚙️ | 连 Mongo → 空集合 / 大集合 |
| DP-MG-SN001 | US3 | Mongo 片段包：8 条内置（CRUD/聚合/索引/工具），`databaseFamily: mongodb` | P2 | 单元 ✅ | `test/services/code_snippet_service_test.dart` |
| DP-MG-SN002 | US3 | `SnippetDbFamily` 字段 + `_currentVersion` 1.0→1.1 迁移 + 旧 JSON 回退 `all` | P2 | 单元 ✅ | `test/models/code_snippet_test.dart` |
| DP-MG-SN003 | US3 | Mongo tab 片段面板只显示 Mongo 片段、隐藏 SQL | P2 | Widget ✅ | `CodeSnippetsPanel` / `SnippetCommandsOverlay` 独立 Widget 测试（`test/organisms/connection/code_snippets_panel_test.dart` 4 用例、`test/organisms/editor/snippet_commands_test.dart` 6 用例）。生产接入仍待 T027。 |
| DP-MG-HS001 | US4 | `_isWriteQuery` Mongo 写检测：insert/update/delete/replace/aggregate+`$out`/`$merge` | P1 | 单元 ✅ | `test/providers/tab_provider_test.dart` (isMongoWriteQuery) |
| DP-MG-HS002 | US4 | Mongo 查询历史记录 `queryType`(find/aggregate/insert/…) + `collectionName` 正确 | P1 | 人工 ⚙️ | ⚠️ 待 T017：多录制点(query_editor/app_provider/interceptor) + 运行时确认哪个系统喂可见历史面板(FR-007) |

#### 5.3.3 MongoDB 集群连接 (feature 044)

> 覆盖 spec `044-mongodb-cluster-connection`：副本集(US1) + 分片 via mongos(US2) + Advanced 粘贴连接串(US3)。★FR-007 密码绝不进 URI/extra（走 SecureStorage）。Pro 门控 `tryMongoCluster`。集成用例需设备 + 真库（CI `-d <device>`），本机 integration_test 触发多设备提示跑不起——已下沉 headless 单测/widget 测。

| 用例 ID | 故事 | 用例 | 优先级 | 类型 | 测试文件 / 验证方式 |
|---------|------|------|--------|------|---------------------|
| MC-DIRECT-001 | — | Direct 模式（无 extra）URI 字节级等价旧单 host（向后兼容） | P0 | 单元 ✅ | `mongodb_replicaset_uri_test.dart`（direct mode byte-identical） |
| MC-FROMDB-001 | — | `fromDbServer` spread `server.extra` 不丢 mongo 键 + 不破 8 种 DB 类型 | P0 | 单元 ✅ | `test/services/database_abstract_test.dart`（T002 回归） |
| MC-RS-URI001 | US1 | replicaSet URI = 多 host + `replicaSet=` + `authSource=`，无凭据 | P1 | 单元 ✅ | `mongodb_replicaset_uri_test.dart`（dbFactory 捕获 URI） |
| MC-RS-URI002 | US1 | replicaSet 无 seed 列表 → 回退单 host | P2 | 单元 ✅ | 同上 |
| MC-RS-NAME001 | US1 | post-connect replicaSet 名校验（不符仅 warn 不阻断）(PD-5) | P2 | 集成 ⚙️ | `mongodb_replicaset_e2e_test.dart`（T013） |
| MC-RS-E2E001 | US1 | 连 rs0 → `getReplicaSetStatus().setName=='rs0'` + 有 PRIMARY | P1 | 集成 ⚙️ | `mongodb_replicaset_e2e_test.dart`（T011，gated RS 密码） |
| MC-RS-FAILOVER001 | US1 | 主切换后 adapter 透明重连（T014 `_withReconnect`）(PD-4) | P2 | 集成 ⚙️ | `mongodb_replicaset_e2e_test.dart`（T033，gated `DBMASTER_MONGO_RS_FAILOVER=1`） |
| MC-SH-URI001 | US2 | sharded URI = 多 mongos host，**无 `replicaSet=`**(PD-10) | P1 | 单元 ✅ | `mongodb_replicaset_uri_test.dart`（sharded 多 host + 单 host 回退） |
| MC-SH-E2E001 | US2 | 连 mongos → `getDatabases` 非空 + `getShardingStatus` 非 null | P2 | 集成 ⚙️ | `mongodb_sharded_e2e_test.dart`（T022，gated mongos 密码+seeds） |
| MC-AD-PARSE001 | US3 | `parseConnectionString` 14 例 + `credentialFreeUri` 无 @（FR-007）(PD-7) | P0 | 单元 ✅ | `mongodb_parse_connection_string_test.dart`（15 用例） |
| MC-AD-OPEN001 | US3 | SRV（`mongodb+srv://`）走 `Db.create` 异步 DNS(PD-6)；advanced 用 credential-free URI | P2 | 集成 ⚙️ | Atlas SRV 端点（本机无） |
| MC-RC-CLS001 | US1 | `_shouldReconnect` 瞬态(ConnectionException/NotWritablePrimary/…)/永久(认证/超时) 分类 | P1 | 单元 ✅ | `mongodb_reconnect_test.dart`（11 用例） |
| MC-DLG-MODE001 | 全 | 模式下拉(Direct/Replica Set/Sharded/Advanced) + Pro 门控(Free→tryMongoCluster false 回退) | P1 | Widget ✅ | `mongodb_connection_form_test.dart`（T010） |
| MC-DLG-FIELD001 | US1/2/3 | 按模式渲染字段 + host/port 隐藏 + 种子/连接串回填 + 空/格式校验 | P1 | Widget ✅ | 同上（含 host:port 格式校验、Advanced 粘贴框、Sharded mongos 列表） |
| MC-DLG-CRED001 | US3 | Advanced 粘贴串：user/pass 解析→DbServer.password（不进 extra/URI）(FR-007) | P0 | Widget ✅ | 同上（credentialFreeUri 无 @ 断言） |
| MC-DLG-LEAK001 | US1/2 | 模式切换清控制器（防 replicaSet↔sharded `_mongoHostsController` 跨拓扑泄漏） | P1 | Widget ✅ | 同上（对抗式验证修复） |
| MC-L10N-001 | 全 | 18 个 `connectionMongo*` 键 × 6 语 ARB + `flutter gen-l10n` | P2 | 单元 ✅ | ARB 全覆盖（en/de/fr/ru/zh/zh_TW） |

### 5.4 Redis

**自动化**: `test/services/adapters/redis_adapter_test.dart` (192 用例)  
**集成**: `integration_test/redis_integration_test.dart` (66 用例)  
**性能基准**: `integration_test/redis_performance_benchmark_test.dart` (2 用例) — R1 海量 key 全量 SCAN（10 万 key）、R2 namespace 聚合（暴露 scanKeys 默认参数上限）；基线见 `docs/appeal_product_analysis.md` §4.1.6  
**人工**: Redis 键浏览、值查看器、Lua 脚本编辑/执行、Redis 函数管理、发布/订阅 UI

### 5.5 SQLite

**自动化**: `test/services/adapters/sqlite_adapter_test.dart` (62 用例)  
**集成**: `integration_test/sqlite_integration_test.dart` (65 用例) + `sqlite_nodes_context_menu_test.dart`  
**人工**: 文件选择/创建数据库、本地文件路径管理

### 5.6 Doris

**自动化**: `test/services/adapters/doris_adapter_test.dart` (72 用例，全绿；含 027 方言对齐：renameTable/renameColumn/createIndex(USING INVERTED)/dropIndex/dropColumn/export 回灌预期；034 追加 engine 忽略 / 默认值转义 / COMMENT 位置断言)  
**集成**: `integration_test/doris_integration_test.dart` (41 用例；027 已对齐过时断言：rename/dropColumn/modifyColumn/dropIndex 现期望成功)  
**真库 E2E**: `integration_test/doris_sidebar_menu_e2e_test.dart` (20 用例：11 adapter 级方言/表模型 + 9 widget 级 SidebarTree 菜单；连真实 Doris 3.0.2；2026-07-16 全绿)  
**真库 E2E**: `integration_test/doris_create_table_e2e_test.dart` (4 用例：Doris 真实实例上 DUPLICATE/UNIQUE 建表，并断言 MySQL 引擎名不泄露；2026-07-16 全绿)
**结构性不变量**: `test/services/database_service_no_doris_dialect_test.dart` (028 新增，断言服务层 0 Doris 方言字符串——方言单一真相 = DorisAdapter)
**架构(028)**: 服务层 11 个 DDL 方法 Doris 处理已统一委托 `DorisAdapter`（去 `mysql‖doris` bypass）；027 真库 E2E 保持全绿证明零行为回归。
**原生特性(029+030)**: 建表对话框暴露 Doris 表模型选择（DUPLICATE/UNIQUE/PRIMARY KEY/AGGREGATE 四模型闭环）+ 分桶配置；模型/分桶/聚合函数经 options 透传，`DorisAdapter.createTable` 发模型关键字（注：Doris 无独立 PRIMARY KEY 关键字，PK = UNIQUE KEY + Merge-on-Write；AGGREGATE 值列 `TYPE AGGFUNC`，维度列 = PK）。UNIQUE/PK 可 UPDATE（呼应 F6）。
**人工**: 同 MySQL 的 UI 交互覆盖面

#### Doris 支持矩阵

| 能力 | 状态 | 测试覆盖 | 证据 / 备注 |
|------|------|----------|-------------|
| TCP 连接 / SSH 隧道 / 字符集 / 时区 | 已实现且已测 | adapter + integration + E2E | `mysql_base_adapter.dart` connect，`database_service.dart` `_ConnectionManager` |
| 每 Query Tab 独立会话 | 已实现且已测 | integration | `DatabaseService.createTabSession` / `useDatabase` |
| 查询执行 / 自动 LIMIT / EXPLAIN | 已实现且已测 | integration + E2E | `DorisAdapter.executeQuery`，`DatabaseService._applyRowLimit` |
| 事务 BEGIN/COMMIT/ROLLBACK | 已实现且已测 | integration | `MySQLBaseAdapter` transaction |
| 只读模式拦截 | 已实现且已测 | 单元/集成 | `QueryExecutionInterceptor` |
| 数据库列表 / 切换 / 创建 / 删除 | 已实现且已测 | integration + E2E | `DorisAdapter.createDatabase`，`DatabaseService.getDatabases/useDatabase/dropDatabase` |
| 表列表 + 表元数据 | 已实现且已测 | integration + E2E | `DorisAdapter.getTablesWithMetadata` |
| 列信息（PRI/UNI/AGG/DUP） | 已实现且已测 | integration | `DorisAdapter.getTableColumns` |
| 索引（SHOW INDEX） | 已实现且已测 | integration + E2E | `DorisAdapter.getTableIndexes` |
| 外键（解析 SHOW CREATE TABLE） | 已实现且已测 | integration | `DorisAdapter.getForeignKeys` |
| 视图 | 已实现且已测 | integration | `MySQLBaseAdapter.getViews` |
| 存储过程 / 函数 / 触发器 / 事件 | 不适用 | N/A | Doris 不支持；`DorisAdapter` 覆写为空 |
| CREATE TABLE（通用列） | 已实现且已测 | E2E | `DorisAdapter.createTable` |
| 表模型：DUPLICATE / UNIQUE / PK / AGGREGATE | 已实现且已测 | E2E | `create_table_dialog.dart` + `DorisAdapter.createTable` |
| MySQL 引擎不泄露到 Doris DDL | 已实现且已测 | E2E | `DorisAdapter.createTable` 忽略 `engine` 选项；`doris_create_table_e2e_test.dart` 真库断言无 InnoDB/MyISAM/MEMORY/ARCHIVE/CSV |
| Hash 分桶 | 已实现且已测 | E2E | 同上 |
| RANGE 分区 | 已实现且已测 | E2E | 同上 |
| DROP / RENAME / TRUNCATE TABLE | 已实现且已测 | E2E | UI 右键菜单 + `DatabaseService` |
| ADD / DROP / MODIFY / RENAME COLUMN | 已实现且已测 | integration | `MySQLBaseAdapter` / `DorisAdapter` |
| CREATE INDEX（USING INVERTED）/ DROP INDEX | 已实现且已测 | integration + E2E | `DorisAdapter.createIndex` / `dropIndex` |
| 结构导出（可回灌） | 已实现且已测 | E2E | `DorisAdapter.exportDatabaseStructure` |
| Schema Diff / Schema Sync | 已实现且已测 | E2E（对话框打开） | `SchemaDiffService` / `SchemaSyncService` |
| Data Sync | 已实现且已测 | E2E（对话框打开） | `DataSyncService` 通用 adapter |
| AI 表 / 库 / 连接分析 | 已实现且已测 | 单元 | `DorisPromptBuilder`，tool registry |
| UPDATE 模型守卫 | 已实现且已测 | E2E | `QueryExecutionInterceptor.checkDorisUpdateGuard` |
| LIST 分区 | 未实现 | 无 | 需 follow-up spec |
| 动态分区 | 未实现 | 无 | 需 follow-up spec |
| 物化视图 / Rollup | 未实现 | 无 | AI prompt 提及，无 UI / adapter |
| Bitmap / NGram / BloomFilter 索引类型 | 部分实现 | 无 | `createIndex` 固定 `USING INVERTED` |
| Stream Load / Broker Load | 未实现 | 无 | 无专用导入 UI |
| Doris 专用类型（HLL / Bitmap / Array / Map / Struct / Variant） | 未实现 | 无 | 建表对话框类型列表沿用 MySQL 类型 |
| 完整 Widget 级右键菜单 E2E | 已实现且已测 | E2E | 本特性新增 |
| Kill Query / Process List | 部分实现 | smoke | UI 支持，真实 kill 断言待补 |

#### 新增 E2E 用例

| 用例 ID | 场景 | 文件 |
|---------|------|------|
| E2E-DORIS-SIDEBAR-001 | connection menu > Create Database | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-SIDEBAR-002 | table menu > Create Table with model / buckets / partition | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-SIDEBAR-003 | table menu > Insert + Select | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-SIDEBAR-004 | table menu > Drop Table | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-SIDEBAR-005 | table menu > Truncate | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-SIDEBAR-006 | table menu > Rename | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-SIDEBAR-007 | table menu > Data Sync dialog | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-SIDEBAR-008 | database menu > Schema Diff & Sync dialog | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-SIDEBAR-009 | Performance category smoke | `integration_test/doris_sidebar_menu_e2e_test.dart` |
| E2E-DORIS-CREATE-001 | adapter-level > simple CREATE TABLE without MySQL engine | `integration_test/doris_create_table_e2e_test.dart` |
| E2E-DORIS-CREATE-002 | adapter-level > DUPLICATE KEY model | `integration_test/doris_create_table_e2e_test.dart` |
| E2E-DORIS-CREATE-003 | adapter-level > UNIQUE KEY model | `integration_test/doris_create_table_e2e_test.dart` |
| E2E-DORIS-CREATE-004 | cleanup > unique test database name + drop on tearDown | `integration_test/doris_create_table_e2e_test.dart` |

#### 034 Doris MySQL 特化行为修复

本次修复（spec `034-doris-mysql-leak`）针对 Doris 与 MySQL 混用导致的 UI 误导与非法 DDL 问题：

| 修复点 | 文件 | 说明 | 测试 |
|--------|------|------|------|
| 隐藏 MySQL 引擎选择 | `lib/organisms/connection/table_dialog/create_table_dialog.dart` | Doris 连接下不显示 `InnoDB/MyISAM` 等引擎下拉 | `test/organisms/connection/table_dialog/create_table_dialog_doris_test.dart` |
| 隐藏 AI（AUTO_INCREMENT）列 | `create_table_dialog.dart` / `edit_table_dialog.dart` | Doris 使用键模型保证唯一性，不使用 MySQL 式自增 | 同上 + `edit_table_dialog_doris_test.dart` |
| Doris 专属数据类型列表 | `create_table_dialog.dart` / `edit_table_dialog.dart` | 过滤掉 `ENUM/SET/LONGTEXT/MEDIUMTEXT/YEAR/BIT/LONGBLOB/MEDIUMBLOB` 等 MySQL 专属类型 | 同上 |
| 忽略 `engine` 选项 | `lib/services/adapters/doris_adapter.dart` | `createTable` 不再追加 `ENGINE=`，避免建表失败 | `test/services/adapters/doris_adapter_test.dart` |
| 字符串默认值加引号 | `doris_adapter.dart` | `DEFAULT 'value'` 并转义单引号 | 同上 |
| COMMENT 位置调整 | `doris_adapter.dart` | 表级 `COMMENT` 位于 `PROPERTIES` 之前 | 同上 |
| 跳过 `SET time_zone` | `lib/services/database_service.dart` / `mysql_base_adapter.dart` | Doris 不支持该会话变量 | 集成测试回归 |
| `SHOW COLLATION WHERE` 规避 | `database_service.dart` | Doris 分支直接返回空列表 | 集成测试回归 |
| `SHOW FULL TABLES` 过滤放宽 | `database_service.dart` / `doris_adapter.dart` | 接受 Doris 非 `VIEW` 的 Table_type | `doris_adapter_test.dart` |
| AI 自增语法修正 | `lib/services/ai_agent_service.dart` | Doris 分支不再生成 `AUTO_INCREMENT` | 单元/集成回归 |
| 维护命令排除 Doris | `lib/models/database_models.dart` / `lib/organisms/sidebar/sidebar_tree.dart` | 不展示 `OPTIMIZE/CHECK TABLE` 等 MySQL 命令 | widget 回归 |
| 属性对话框标签 Doris 感知 | `table_properties_dialog.dart` / `database_dialog.dart` | Doris 下隐藏 Engine/Collation 等 MySQL 专属标签 | widget 回归 |

#### 035 Doris 真实实例建表 E2E

本次补充（spec `035-doris-real-instance-e2e`）在真实 Doris 实例上验证建表 DDL 不携带 MySQL 引擎，并覆盖 DUPLICATE/UNIQUE 模型：

| 验证点 | 文件 | 说明 | 测试 |
|--------|------|------|------|
| 真实实例建表成功 | `integration_test/doris_create_table_e2e_test.dart` | 连真实 Doris，创建临时数据库/表，运行 `SHOW CREATE TABLE` | 4 用例全绿 |
| MySQL 引擎名不泄露 | 同上 | 断言返回 DDL 不含 `InnoDB` / `MyISAM` / `MEMORY` / `ARCHIVE` / `CSV` 等 MySQL 引擎 | 同上 |
| DUPLICATE KEY 模型 | 同上 | `options['model'] = 'DUPLICATE'`，断言 DDL 含 `DUPLICATE KEY` | 同上 |
| UNIQUE KEY 模型 | 同上 | `options['model'] = 'UNIQUE'`，断言 DDL 含 `UNIQUE KEY` | 同上 |
| 字符串默认值转义 | 同上 | 列 `defaultValue = 'active'`，验证建表成功 | 同上 |
| 唯一库名 + 清理 | 同上 | `DorisTestConfig.generateTestDatabaseName()` + `DROP DATABASE IF EXISTS` in tearDown | 同上 |

#### 主要缺口与 follow-up

1. **LIST 分区 / 动态分区**：需独立 spec 扩展 `DorisAdapter.createTable` 与建表对话框。
2. **物化视图 / Rollup**：需 UI + adapter 支持。
3. **Stream Load / Broker Load**：需专用导入入口。
4. **Kill Query 真实终止断言**：需构造 victim query 后验证 process list 变化。

### 5.7 TDengine

**自动化**: `tdengine_adapter_test.dart` (71) + `_security_test.dart` (3) + `_dialogs_test.dart` (8) + `_pagination_test.dart` (5) + `_resilience_test.dart` (10) + `_sidebar_tree_test.dart` (13) = 110 用例  
**集成**: `integration_test/tdengine_integration_test.dart`  
**人工**: 超级表创建/管理 UI、子表浏览、时序数据可视化

### 5.8 SQL Server

**自动化**: `test/services/adapters/sqlserver_adapter_test.dart` (51 用例) + live 金标准 `test/services/adapters/sqlserver_golden_*.dart`（feature 024）  
**集成**: `integration_test/sqlserver_integration_test.dart` (41 用例) — 社区维护，不阻塞核心 CI  
**人工**: Windows 认证 UI、FreeTDS 配置、Schema 浏览 (schema.table 语法)

#### 5.8.1 SQL Server 正确性地基 (feature 024)

> 覆盖 spec `024-sqlserver-correctness-foundation`：致命正确性修复（varmax 截断/日期货币解码/EXEC 不冻结/断连检测）+ 能力补全（ProcessList/Charset）+ 测试地基。`SS-*` case ID，分层 0xx 单元 / 1xx Widget / 2xx 集成(live)。live 用例连真实 SQL Server 2022，不可达时**显式 SKIP 计数**（FR-011，防假绿：见 `test/helpers/sqlserver_live_test_helper.dart` 的 `SQLSERVER_LIVE_SKIP` 上报）。

| 用例 ID | 故事 | 用例 | 优先级 | 类型 | 状态 |
|---------|------|------|:------:|------|------|
| SS-DEC-201 | US2 | `datetime2`/`date`/`time`/`datetimeoffset` 解码值与 SSMS 一致 | P1 | 集成 | ✅ 通过 |
| SS-DEC-202 | US2 | `money`/`smallmoney` 解码为正确金额（精度边界按 SQL Server 语义） | P1 | 集成 | ✅ 通过 |
| SS-DEC-203 | US1 | `(n)varchar(max)` 列被截断时列级标记 `mayBeTruncated`；非(max)列无误报 | P1 | 集成 | ✅ 通过 |
| SS-DEC-101 | US1 | 截断指示徽标在结果表单元格渲染（6 语言 L10n） | P1 | Widget | ✅ 实现（widget 测试待补） |
| SS-BROWSE-201 | US1 | 表浏览（getDefaultBrowseQuery→executeQuery）(max) 列截断标记 | P1 | 集成 | ✅ 通过 |
| SS-EXEC-201 | US3 | 执行存储过程不冻结 UI（`SET LOCK_TIMEOUT` 30s + fire-and-forget `catchError` 兜底） | P1 | 集成 | ✅ 通过 |
| SS-EXEC-002 | US3 | fire-and-forget bypass 调用点有错误兜底（不 null-check 崩溃） | P1 | 单元 | ✅ 代码审查 |
| SS-EXEC-202 | US3 | EXEC 出错（缺必填参数，error 201）不断连 + 错误含服务器正文（message handler 捕获，dbdead 探活替代字符串匹配） | P1 | 集成 | ✅ 通过 |
| SS-EXEC-203 | US3 | UI 管线（AppProvider.executeCurrentQuery 经 DatabaseService）EXEC 出错不断连 + 服务器正文浮现（severity-based `_isConnectionBroken`，integration_test 驱动真 app） | P1 | 集成 | ✅ 通过 |
| SS-PL-201 | US5 | `getProcessList()` 返回活跃会话（DMV 映射 `ProcessInfo`） | P2 | 集成 | ✅ 通过 |
| SS-PL-202 | US5 | `killProcess(spid)` 终止会话（`KILL <spid>`，无 CONNECTION 关键字） | P2 | 集成 | ✅ 通过 |
| SS-CH-201 | US5 | `getCollations()` 返回服务端排序规则；`implements CharsetAdapter` | P2 | 集成 | ✅ 通过 |
| SS-DISC-201 | US4 | 连接丢失触发 `onDisconnect`（executeQuery catch + varmax 重连失败路径；含 KILL 后查询 <120s 返回的显式耗时断言） | P2 | 集成 | ✅ 通过 |
| SS-TIMEOUT-301 | — | `dbsettime` 生效实证：timeout=30 时 `WAITFOR DELAY '00:00:35'` 在 [25s,60s] 内抛出而非跑满成功（2026-07-30 超时绑定落地） | P1 | 集成 | ✅ 通过 |

> `SS-DEC-001/002`（离线单元：FFI 常量存在性、`implements` 断言）并入 `sqlserver_adapter_test.dart` 扩展。LIMIT 声明：varmax「读全 (max)」不在本 feature（需升级 FreeTDS）；SS-DEC-203 验收的是「截断被显式化」，代码标注 `// LIMIT:`。

#### 5.8.2 SQL Server 能力对齐二期 A (feature 025)

> 覆盖 spec `025-sqlserver-capability-parity`：补全 A2–A9（Replication/Json/Sequences/MatViews/导出含 proc/GO/modifyColumn oldName）。`SS-*` case ID，2xx 集成(live)。

| 用例 ID | 故事 | 用例 | 优先级 | 类型 | 状态 |
|---------|------|------|:------:|------|------|
| SS-CAP-001 | — | `implements ReplicationAdapter` + `implements JsonAdapter` | P2 | 单元 | ✅ 通过 |
| SS-SEQ-201 | A4 | `getSequences()` 返回 `sys.sequences` | P2 | 集成 | ✅ 通过 |
| SS-MV-201 | A5 | `getMaterializedViews()` 返回索引视图 | P2 | 集成 | ✅ 通过 |
| SS-REP-201 | A2 | `getReplicationStatus()` standalone 返 null 不抛（AlwaysOn 时返 raw） | P2 | 集成 | ✅ 通过 |
| SS-JSON-201 | A3 | `getJsonColumns()`/`isJsonColumn()` 经 `ISJSON()` 检测 | P2 | 集成 | ✅ 通过 |
| SS-EXP-201 | A7 | `exportDatabaseStructure` 含 proc/func/trigger（sys.sql_modules） | P2 | 集成 | ✅ 通过 |
| SS-SCRIPT-201 | A8 | `executeSqlScript` 认 `GO` 批分隔符 | P2 | 集成 | ✅ 通过 |
| SS-DDL-201 | A9 | `modifyColumn` 用 `oldColumnName` 改名（sp_rename） | P2 | 集成 | ✅ 通过 |

> 注：A2 `ReplicationStatus` 为 MySQL 形状，SQL Server AlwaysOn best-effort 映射 + `raw` 保留 DMV 全字段；standalone 返 null。A5 SQL Server 无独立物化视图，以「索引视图」（带唯一聚集索引的视图）近似。

---

## 6. AI 系统测试 (AI)

### 6.1 AI 基础服务 — ✅ 已覆盖

12 个测试文件，143 用例，全部通过：
- `ai_client_static_test.dart` (10) — AI 客户端静态方法
- `ai_context_builder_test.dart` (25) — 上下文构建器
- `ai_parser_factory_test.dart` (9) — 解析器工厂
- `ai_prompt_factory_test.dart` (9) — Prompt 工厂
- `ai_service_localizations_test.dart` (12) — AI 多语言
- `ai_session_manager_test.dart` (32) — 会话管理器
- `sql_prompt_builder_test.dart` (7) — SQL Prompt 构建器
- `mongodb_response_parser_test.dart` (10) — MongoDB 响应解析
- `redis_response_parser_test.dart` (10) — Redis 响应解析
- `sql_response_parser_test.dart` (15) — SQL 响应解析
- `ai_skill_service_test.dart` (3) — AI 技能服务
- `ai_summary_service_test.dart` (1) — AI 摘要服务

### 6.2 AI 高阶服务测试 (Batch 4 已完成, +6 文件/+58 用例)

| # | 用例 | 优先级 | 服务 | 测试文件 | 状态 |
|---|------|--------|------|---------|------|
| AI-SVC-001 | AiService 单例/接口/客户端 | P0 | `ai_service.dart` | `test/services/ai_service_test.dart` | ✅ (9 用例) |
| AI-SVC-002 | AiAgentService 模型 (Result/Tool/Execution) | P0 | `ai_agent_service.dart` | `test/services/ai_agent_service_test.dart` | ✅ (11 用例) |
| AI-SVC-003 | AiConversationService 会话 CRUD | P0 | `ai_conversation_service.dart` | `test/services/ai_conversation_service_test.dart` | ✅ (19 用例) |
| AI-SVC-004 | AiSessionOrchestrator 消息 Delta/快照 | P1 | `ai_session_orchestrator.dart` | `test/services/ai_session_orchestrator_test.dart` | ✅ (8 用例) |
| AI-SVC-005 | AiSessionStore 单例/重置 | P1 | `ai_session_store.dart` | `test/services/ai_session_store_test.dart` | ✅ (2 用例) |
| AI-SVC-006 | AiMessageUpdateManager 流更新 | P1 | `ai_message_update_manager.dart` | `test/services/ai_message_update_manager_test.dart` | ✅ (9 用例) |
| AI-SVC-007 | AiContextService | P1 | `ai_context_service.dart` | re-exports `ai_context_builder` (already tested 25 用例) | ✅ 已有 |
| AI-SVC-008 | AiContextCompressor | P1 | `ai_context_compressor.dart` | same re-export | ✅ 已有 |

### 6.3 AI Panel UI 测试

**Widget 测试**: `test/widgets/ai_conversation_list_test.dart` (1), `test/widgets/ai_message_item_test.dart` (3)  
**集成测试**: `integration_test/ai_panel_test.dart` (9)  
**人工测试**: 参见 `ai_panel_manual_test_cases.md` (📦 归档)

**🔴 待补充 Widget 测试**:

| # | 用例 | 优先级 |
|---|------|--------|
| UAI-W-001 | AIPanelWidget 面板打开/关闭 | P0 |
| UAI-W-002 | AIWelcomeState 欢迎页渲染 | P1 |
| UAI-W-003 | AISlashCommandMenu 命令菜单 | P1 |
| UAI-W-004 | ConfirmExecuteDialog 确认对话框 | P0 |
| UAI-W-005 | DDLConfirmDialog DDL 确认 | P0 |
| UAI-W-006 | AIBookmarkPanel 书签面板 | P2 |

### 6.3.1 spec 042 — 全屏 AI 助手浮层缩放重构

**特性**: 全屏浮层几何改为显式矩形状态机——8 个手柄「拖哪边动哪边、对边严格不动」；S/M/L 预设移除；位置+尺寸持久化与恢复（legacy 兼容）。断言一律基于渲染几何（`getRect` on `ai_overlay_panel`），锚定「对边坐标不变」而非仅「尺寸变大」。

**Widget 测试**: `test/organisms/ai_panel/ai_panel_overlay_test.dart` (17) ✅

| # | 用例 | 优先级 | 类型 | 文件 / 说明 |
|---|------|--------|------|------|
| UAI-OV-001 | 浮层渲染不灰屏（冒烟） | P1 | 自动化 | 同上 |
| UAI-OV-002 | 无存档首次打开默认观感 910×538.2 @ (245,171.3)（1400×900） | P0 | 自动化 | 同上（I9） |
| UAI-OV-003 | S/M/L 预设入口移除（工具栏 + 快捷键对话框） | P1 | 自动化 | 同上（I8） |
| UAI-OV-004 | 拖 right 边：left/top/height 不动 | P0 | 自动化 | 同上（I1） |
| UAI-OV-005 | 拖 top 边：bottom 坐标不动（核心回归） | P0 | 自动化 | 同上（I1） |
| UAI-OV-006 | 拖 bottom 边：top 不动 | P0 | 自动化 | 同上（I1） |
| UAI-OV-007 | 拖 left 边：right 坐标不动（核心回归） | P0 | 自动化 | 同上（I1） |
| UAI-OV-008 | 拖 topLeft 角：bottom/right 不动（核心回归） | P0 | 自动化 | 同上（I1） |
| UAI-OV-009 | 拖 bottomRight 角：left/top 不动 | P0 | 自动化 | 同上（I1） |
| UAI-OV-010 | min-clamp：拖 top 越界 height=300 且 bottom 不动 | P0 | 自动化 | 同上（I1/I2） |
| UAI-OV-011 | min-clamp：拖 left 越界 width=400 且 right 不动 | P0 | 自动化 | 同上（I1/I2） |
| UAI-OV-012 | 工具栏移动：位置随 delta、尺寸不变 | P1 | 自动化 | 同上（I7） |
| UAI-OV-013 | 窗口缩放：clamp 进视口且不重新居中 | P0 | 自动化 | 同上（I3/I4） |
| UAI-OV-014 | 移动+缩放后位置/尺寸四值精确持久化 | P0 | 自动化 | 同上（契约§3） |
| UAI-OV-015 | 重开后位置+尺寸恢复（误差 ≤1px） | P0 | 自动化 | 同上（I5） |
| UAI-OV-016 | legacy 仅尺寸存档 → 按存档尺寸居中恢复 | P1 | 自动化 | 同上（I5 兼容） |
| UAI-OV-017 | 越界存档（超大/超界）clamp 进视口 | P1 | 自动化 | 同上（I3） |

**人工（仅渲染外观）**: 生成 exe 后按内部走查清单检查（手柄显示、贴边手感、窗口缩放无错位、工具栏排布、重开位置）。

### 6.4 数据库特有 AI Builder/Parser 测试

| # | 用例 | 优先级 | 覆盖对象 |
|---|------|--------|---------|
| AI-DB-001 | MongoDB Prompt Builder | P1 | Prompt 模板正确性 |
| AI-DB-002 | Redis Prompt Builder | P1 | 同上 |
| AI-DB-003 | ES Prompt Builder | P2 | 同上 |
| AI-DB-004 | TDengine Prompt Builder | P2 | 同上 |
| AI-DB-005 | MongoDB Response Parser 边界情况 | P1 | 异常 JSON、嵌套文档 |
| AI-DB-006 | Redis Response Parser 边界情况 | P1 | 二进制数据、大键值 |

### 6.5 通用数据库 Agent（FK 能力 + 只读工具 + 跨轮记忆，2026-09-03）

**背景**：AI 助手对「删除某 SELECT 查出的数据 + 找关联」类请求多轮给不出 DELETE。根因 = 外键信息不在 AI 上下文 / 无只读探索工具 / 安全提示词措辞诱导反复追问 / 跨轮工具结果被过滤。本批补齐「手（run_readonly_query）、眼（双向 FK）、记忆（工具摘要跨轮）、性格（提示词）」四块能力。

**单元测试**（新增 3 文件 + 扩展 2 文件，全部 ✅）：

| # | 用例 | 优先级 | 测试文件 | 状态 |
|---|------|--------|---------|------|
| AI-AGENT-001 | 只读 SQL 校验器全矩阵（白名单/多语句/INTO/FOR UPDATE/CTE 藏 DML/EXPLAIN ANALYZE/PRAGMA 名单/字面量掩码） | P0 | `test/services/ai/readonly_sql_validator_test.dart` (45) | ✅ |
| AI-AGENT-002 | getReferencingForeignKeys 默认实现（反向过滤/大小写/自引用/静默/阈值>200 空） | P0 | `test/services/adapters/referencing_foreign_keys_test.dart` (4) | ✅ |
| AI-AGENT-003 | MySQL/PG information_schema 反查快路径（SQL 形状 + ON DELETE/UPDATE 映射 + 失败回退） | P0 | 同上 (3) | ✅ |
| AI-AGENT-004 | 工具注册表含新工具（SQL 六库 × 2 + Mongo + Redis × 2） | P1 | `test/pro/ai/ai_agent_tool_handlers_test.dart` | ✅ |
| AI-AGENT-005 | get_table_relationships 工具（双向 FK JSON/空表名失败） | P0 | 同上 | ✅ |
| AI-AGENT-006 | run_readonly_query 工具（放行/写拒/PRAGMA 门控/每 run 上限 10/行 50 截断/单元格截断） | P0 | 同上 | ✅ |
| AI-AGENT-007 | find_documents_mongo（count+样本/limit 钳 50/非 Mongo 拒） | P1 | 同上 | ✅ |
| AI-AGENT-008 | scan_keys / get_key（键列表/type+ttl+value/非 Redis 拒） | P1 | 同上 | ✅ |
| AI-AGENT-009 | 提示词 agent 化（安全规则新措辞 zh/en、自主探索 section、数据修改规范） | P0 | `test/services/ai/prompt_builders/sql_prompt_builder_test.dart` (+4) | ✅ |
| AI-AGENT-010 | 跨轮工具记忆（摘要附轮次/仅保留最近 3 轮/无工具时回归旧行为/超长截断） | P0 | `test/services/ai_session_orchestrator_history_test.dart` (4) | ✅ |

**真实库集成测试**：`integration_test/ai_agent_fk_readonly_e2e_test.dart`（自建自删专用库）：

| # | 用例 | 数据库 | 状态 |
|---|------|--------|------|
| AI-AGENT-E2E-001 | 反查引用 tasks 的子表（CASCADE）+ get_table_relationships 工具全链 + 只读写拒（数据未被删） | MySQL（embedded 网关） | ⚠️ 环境相关：192.168.x.x 不可达时与基线集成测试一致失败；SQLite 路径已真跑通过 |
| AI-AGENT-E2E-002 | referential_constraints 反查子表与 ON DELETE | PostgreSQL | 同上 |
| AI-AGENT-E2E-003 | PRAGMA 全表扫描默认实现 + PRAGMA 只读名单放行 | SQLite（本地文件） | ✅ 已通过 |

**边界与安全**：工具面全只读（白名单 + 单语句 + 黑名单三层校验 + 只读连接守卫双保险）；写语句唯一路径仍是 extractedCommands + 确认弹窗执行门；结果回传 50 行/8KB 截断、每 run 只读查询上限 10 次。

---

## 7. SQL 查询服务测试 (SQL)

### 7.1 已覆盖服务 (✅)

| 测试文件 | 用例数 | 覆盖服务 |
|---------|--------|---------|
| `sql_parser_service_test.dart` | 13 | SQL 解析 |
| `sql_validator_service_test.dart` | 22 | SQL 验证 |
| `sql_formatter_service_test.dart` | 22 | SQL 格式化 |
| `sql_injection_detector_test.dart` | 11 | 注入检测 |
| `paginated_result_service_test.dart` | 7 | 分页结果 |
| `multi_execution_service_test.dart` | 8 | 多语句执行 |
| `query_execution_interceptor_test.dart` | 8 | 执行拦截 |
| `sql_prompt_service_test.dart` | 17 | ✅ SQL Prompt |

### 7.2 服务测试覆盖状态 (Batch 2 已完成, +6 文件/+76 用例)

| # | 用例 | 优先级 | 服务 | 测试文件 | 状态 |
|---|------|--------|------|---------|------|
| SQL-AC-001 | SqlAutocompleteService 枚举和模型 | P1 | `sql_autocomplete_service.dart` | `test/services/sql_autocomplete_service_test.dart` | ✅ |
| SQL-AC-002 | SqlAutocompleteService DB 补全 | P1 | | 需 DatabaseService mock | ⚠️ 需集成 |
| SQL-QF-001 | SqlQuickFixService action 清单 | P1 | `sql_quick_fix_service.dart` | `test/services/sql_quick_fix_service_test.dart` | ✅ |
| SQL-QF-002 | SqlQuickFixService DB 修复 | P1 | | 需 DatabaseService mock | ⚠️ 需集成 |
| SQL-OPT-001 | SqlOptimizerService 优化建议 | P1 | `sql_optimizer_service.dart` | `test/services/sql_optimizer_service_test.dart` | ✅ (22 用例) |
| SQL-INS-001 | InsertExecutionService 批量 | P1 | `insert_execution_service.dart` | `test/services/insert_execution_service_test.dart` | ✅ (10 用例) |

### 7.3 查询优化器

**自动化覆盖**: `query_optimizer_service_test.dart` (9), `explain_parser_test.dart` (8), `index_recommendation_engine_test.dart` (7), `performance_analyzer_test.dart` (8), `query_rewrite_engine_test.dart` (6) — 全部通过

| # | 用例 | 优先级 | 测试内容 | 状态 |
|---|------|--------|---------|------|
| ~~SQL-QO-001~~ | 优化器服务完整流程 | P1 | 接收查询 → 解析 EXPLAIN → 生成建议 | ✅ 已覆盖 |

### 7.4 查询编辑器人工测试

| # | 用例 | 优先级 | 说明 |
|---|------|--------|------|
| SQL-M001 | SQL 语法高亮颜色 | P0 | 关键字/字符串/数字/注释/函数各色 |
| SQL-M002 | MongoDB/JavaScript 语法高亮 | P0 | Mongo shell：`db`/方法名/`$`操作符/字符串/数字独立颜色（018 改为 JS 语法） |
| SQL-M003 | 自动补全列表交互 | P0 | 弹出/过滤/选择/插入 |
| SQL-M004 | 函数签名提示 | P1 | 参数列表、当前位置高亮 |
| SQL-M005 | 代码片段插入 | P1 | 触发词 → 片段列表 → 占位符导航 |

---

## 8. Schema / ER / 导入导出测试 (SC)

### 8.1 Schema 分析器

**自动化覆盖**: `test/services/schema_analyzer/schema_analyzer_test.dart` (13 用例), `test/services/schema_context_service_test.dart` (14 用例) ✅

**Batch 2 已完成 ✅**:

| # | 用例 | 优先级 | 服务 | 测试文件 | 状态 |
|---|------|--------|------|---------|------|
| SC-DEP-001 | DependencyAnalyzer 表依赖 | P0 | `dependency_analyzer.dart` | `test/services/schema_analyzer/dependency_analyzer_test.dart` | ✅ (10 用例) |
| SC-IMPACT-001 | ImpactAssessor DDL 分析 | P0 | `impact_assessor.dart` | `test/services/schema_analyzer/impact_assessor_test.dart` | ✅ (30 用例) |
| SC-ROLL-001 | RollbackGenerator 回滚 | P1 | `rollback_generator.dart` | `test/services/schema_analyzer/rollback_generator_test.dart` | ✅ (20 用例) |
| SC-CTX-001 | SchemaContextService 上下文构建 | P1 | `schema_context_service.dart` | `test/services/schema_context_service_test.dart` | ✅ (14 用例) |

### 8.2 Schema Diff

**自动化覆盖**: `schema_diff_service_test.dart` (27), `schema_sync_service_test.dart` (13), `table_dependency_sorter_test.dart` (12) ✅

**🔴 待补充**:

| # | 用例 | 优先级 | 服务 | 测试重点 | 状态 |
|---|------|--------|------|---------|------|
| SC-DIFF-001 | SchemaDiffService 完整对比 | P0 | `schema_diff_service.dart` | 表差异、列差异、索引差异 | ✅ 已覆盖 |
| SC-DIFF-002 | SchemaDiffService DDL 生成 | P0 | `schema_sync_service.dart` | 差异 → DDL 脚本 | ✅ `schema_sync_service_test.dart` |
| SC-DIFF-003 | SchemaDiffService 忽略规则 | P1 | | 忽略指定表/列 |
| SC-DIFF-004 | SchemaDiffService 大 Schema 性能 | P2 | | 100+ 表对比性能 |

### 8.3 ER 图

**自动化覆盖**: `test/services/er_layout_test.dart` (20 用例) ✅

**🔴 待补充**:

| # | 用例 | 优先级 | 测试内容 |
|---|------|--------|---------|
| SC-ER-001 | ERDiagramService 元数据生成 | P0 | 从 Schema 生成 ER 图数据 |
| SC-ER-002 | ERDiagramService 大型 Schema | P2 | 50+ 表布局性能 |

### 8.4 导入/导出/备份

**自动化覆盖**: `backup_service_test.dart` (25), `import_service_test.dart` (13), `smart_import_enhanced_test.dart` (10), `file_analyzer_test.dart` (16), `streaming_file_reader_test.dart` (11), `export_service_test.dart` (8), `faker_data_service_test.dart` (29) ✅

| # | 用例 | 优先级 | 服务 | 状态 |
|---|------|--------|------|------|
| SC-EXP-001 | ExportService CSV/JSON 内容生成 | P0 | `export_service.dart` | ✅ (8 用例) |
| SC-EXP-002 | ExportService 文件 I/O | P1 | | ⚠️ 集成测试 |
| SC-BAK-001 | BackupService 备份流程 | P0 | `backup_service.dart` | ✅ (25 用例) |
| SC-DG-001 | FakerDataService 数据生成 | P1 | `faker_data_service.dart` | ✅ (29 用例) |
| SC-DG-002 | DataGenerationService | P2 | `data_generation_service.dart` | 🔴 可自动化 |

---

## 9. 安全与认证测试 (SEC)

### 9.1 已覆盖 (✅)

| 测试文件 | 用例数 |
|---------|--------|
| `auth_service_test.dart` | 12 |
| `auth_token_storage_test.dart` | 5 |
| `secure_storage_service_test.dart` | 7 |
| `ssh_tunnel_service_test.dart` | 11 |
| `audit_log_service_test.dart` | 23 |
| `audit_sql_sanitizer_test.dart` | 18 |
| `pii_masker_test.dart` | 24 |
| `pro_status_storage_test.dart` | 5 |
| `purchase_service_security_test.dart` | 3 |
| `background_filter_service_test.dart` | 5 |
| `database_tool_registry_test.dart` | 12 |

### 9.2 🔴 待补充

| # | 用例 | 优先级 | 测试内容/状态 |
|---|------|--------|---------------|
| ~~SEC-AUTH-001~~ | AuthService 登录流程 | P0 | 凭证验证、token 获取 — ✅ `test/services/auth_service_test.dart` |
| SEC-AUTH-002 | AuthService 注册流程 | P1 | 字段验证、重复检测 — 🔴 未覆盖 |
| SEC-AUTH-003 | AuthService 密码重置 | P1 | 邮件发送、token 验证 — 🔴 未覆盖 |
| ~~SEC-AUTH-004~~ | AuthService Token 刷新 | P1 | 自动刷新、过期处理 — ✅ `test/services/auth_service_test.dart` |
| SEC-AUTH-005 | AuthService 登录失败锁定 | P2 | 错误次数限制 — 🔴 未覆盖 |
| SEC-DB-001 | DatabaseTools 安全验证 | P1 | 危险操作识别 — 🔴 未覆盖 |
| ~~SEC-DB-002~~ | DatabaseToolRegistry 命令注册 | P1 | 安全级别分配 — ✅ `test/services/database_tool_registry_test.dart` |

### 9.3 安全人工测试

| # | 用例 | 优先级 |
|---|------|--------|
| SEC-M001 | SSH 隧道连接 UI | P0 |
| SEC-M002 | SQL 注入检测 UI 警告 | P1 |
| SEC-M003 | PII 掩码结果对比 | P1 |
| SEC-M004 | 审计日志查看和搜索 | P1 |
| SEC-M005 | Pro 购买和恢复流程 | P0 |

---

## 10. UI 组件测试 — Atoms/Molecules (UA/UM)

### 10.1 Atoms (Batch 3 已完成)

**自动化覆盖**: `test/atoms/app_components_test.dart` (3), `test/atoms/typewriter_text_test.dart` (4), `test/atoms/app_widgets_test.dart` (12) ✅

| 组件 | 测试状态 |
|------|---------|
| AppStatusBadge (5 状态类型) | ✅ (12 用例) |
| AppEmptyState (带/不带描述/action) | ✅ |
| AppLoadingOverlay (加载/非加载) | ✅ |
| TypewriterText | ✅ (4 用例) |
| AppCard/AppHeader | ✅ (3 用例)；AppButton/AppIconButton 已删除（特性 046 T011 死库移除，按钮唯一层为 app_widgets.dart） |
| AppScrollbar/AppTransitions | 🔴 待补充 (P3，纯视觉) |

### 10.2 Molecules

**自动化覆盖**: `test/molecules/thinking_card_test.dart` (7), `test/molecules/bulk_close_dialog_test.dart` (8), `test/utils/close_decision_applier_test.dart` (5), `test/molecules/destructive_confirm_dialog_test.dart` (6) — UM-DEST-001..006（契约 C3 危险确认对话框唯一外壳：渲染结构/按钮顺序/onConfirm/typed-confirmation）

**✅ 已覆盖（契约 C3）**:

| # | 用例 | 优先级 | 组件 |
|---|------|--------|------|
| UM-DEST-001 | DestructiveConfirmDialog 渲染图标/标题/影响说明/双按钮 | P0 | 危险确认对话框 |
| UM-DEST-002 | DestructiveConfirmDialog Cancel 在左、确认钮在右 | P0 | 危险确认对话框 |
| UM-DEST-003 | DestructiveConfirmDialog 点击确认触发 onConfirm | P0 | 危险确认对话框 |
| UM-DEST-004 | DestructiveConfirmDialog Cancel pop 返回 false | P0 | 危险确认对话框 |
| UM-DEST-005 | requireTypedConfirmation 输入匹配（大小写不敏感）前确认钮禁用 | P0 | 危险确认对话框 |
| UM-DEST-006 | impactDescription 为 null 时隐藏影响说明容器 | P1 | 危险确认对话框 |

**🔴 待补充**:

| # | 用例 | 优先级 | 组件 |
|---|------|--------|------|
| UM-BULK-001 | BulkCloseDialog 显示 Save All / Discard All / Cancel | P0 | 批量关闭对话框 |
| UM-BULK-002 | BulkCloseDialog 列出未保存 Tab 标题和 SQL 片段 | P0 | 批量关闭对话框 |
| UM-BULK-003 | BulkCloseDialog 取消返回 confirmed=false | P0 | 批量关闭对话框 |
| UM-BULK-004 | BulkCloseDialog Discard All 全部标记 discard | P0 | 批量关闭对话框 |
| UM-BULK-005 | BulkCloseDialog Save All 全部标记 save | P0 | 批量关闭对话框 |
| UM-BULK-006 | BulkCloseDialog 逐项决定覆盖批量决定 | P1 | 批量关闭对话框 |
| UM-BULK-007 | BulkCloseDialog 三个未保存 Tab 渲染无 null 错误 | P0 | 批量关闭对话框 |
| UM-BULK-008 | BulkCloseDialog 单个未保存 Tab 渲染无 null 错误 | P0 | 批量关闭对话框 |
| UM-BULK-009 | BulkCloseDialog 三个 Tab Discard All 决策一致 | P1 | 批量关闭对话框 |
| UM-001 | ContextMenu 渲染和点击 | P1 | 右键菜单 |
| UM-002 | FormControls 表单控件 | P1 | 各类表单输入 |
| UM-003 | SearchBar 搜索交互 | P1 | 搜索栏 |
| UM-004 | SkeletonLoader 加载骨架 | P2 | 加载占位 |
| UM-005 | ToastService 提示弹出 | P1 | Toast |
| UM-006 | PasswordField 密码输入 | P1 | 密码可见性切换 |
| UM-007 | VerificationCodeField | P2 | 验证码输入 |

---

## 11. UI 组件测试 — 编辑器 (UE)

### 11.1 已覆盖 (Batch 3)

**自动化**: `test/organisms/editor/sql_highlighter_test.dart` (6), `test/organisms/editor/sql_editor_controller_test.dart` (12), `test/organisms/editor/query_editor_shortcuts_test.dart` (3), `test/organisms/editor/sql_autocomplete_test.dart` (4), `test/organisms/editor/snippet_commands_test.dart` (9) ✅

| 组件 | 测试状态 |
|------|---------|
| SqlHighlightController 高亮逻辑 | ✅ (6 用例) |
| SqlEditorController (language/focus/dispose) | ✅ (12 用例) |
| EditorTextStyle 字体度量 | ✅ |
| SqlHighlightTheme.getTheme | ✅ |
| QueryEditorShortcuts (Ctrl+S 保存到历史) | ✅ (3 用例) |
| EnhancedSQLEditor Widget | 🔴 Widget 测试 (需 MaterialApp + localization) |
| QueryEditorToolbar | 🔴 Widget 测试 |
| SQLAutocomplete Widget | ✅ (4 用例) |

### 11.2 Query Editor 快捷键测试

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| UE-001 | Ctrl+S 保存非空查询到历史 | P1 | 自动化 | 编辑器有焦点时按 Ctrl+S，侧边栏历史出现该条目 |
| UE-002 | Ctrl+S 在空编辑器下无操作 | P1 | 自动化 | 空内容时不创建历史记录 |
| UE-003 | Ctrl+S 重复保存更新已有条目 | P2 | 自动化 | 相同 SQL 不重复创建，更新原条目时间戳 |
| UE-004 | Ctrl+S 新查询弹出命名对话框 | P0 | 自动化 | 当前 tab 无 savedQueryId 时弹出命名输入框 |
| UE-005 | Ctrl+S 已保存查询直接更新 | P0 | 自动化 | 当前 tab 有 savedQueryId 时不弹窗直接保存 |
| UE-006 | 工具栏 Save 按钮与快捷键行为一致 | P0 | 自动化 | 同样依据 savedQueryId 决定是否弹窗 |
| UE-007 | 全局 Ctrl/Cmd+S 与编辑器保存行为一致 | P0 | 自动化 | GlobalShortcutsWrapper._handleSaveExport 与编辑器走相同判断逻辑 |
| UE-008 | 取消命名对话框不保存 | P1 | 自动化 | 取消后 savedQueries 列表保持不变 |

### 11.3 编辑器人工测试

| # | 用例 | 优先级 | 说明 |
|---|------|--------|------|
| UE-M001 | SQL 语法高亮视觉效果 | P0 | 各 Token 类型颜色区分清晰 |
| UE-M002 | MongoDB 模式高亮 | P0 | JSON/MongoDB Shell 语法着色 |
| UE-M003 | 自动补全列表 | P0 | 表名/列名/关键字候选、键盘导航 |
| UE-M004 | 函数签名提示 | P1 | 输入函数时自动弹出参数说明 |
| UE-M005 | 代码片段插入 | P1 | 触发词 + Tab → 模板展开 |
| UE-M006 | 查找与替换 | P0 | Ctrl+F 查找、Ctrl+H 替换 |
| UE-M007 | 跳转到行 | P1 | Ctrl+G 输入行号 |
| UE-M008 | 编辑器字体大小调节 | P0 | 设置面板调节字号即时生效 |

### 11.4 spec 041 — 查询/结果布局重构（FilterBar + 固定 viewMode）

**特性**: 右键浏览表/视图数据 → **data 模式**（FilterBar + 数据网格，隐 editor/工具栏/子标签栏）；新建查询 → **query 模式**（editor+工具栏+结果含子标签）；固定不切换；data 模式 SQL 进查询历史。

**入口规则（2026-07-23 修订）**：双击表/视图/物化视图、Enter（已展开节点）、最近/收藏表行点击 → **query 编辑器**（预填方言感知默认浏览查询，不自动执行）；**仅右键「浏览数据」** → data 模式；Mongo 集合双击不变。

| # | 用例 | 优先级 | 类型 | 文件 / 说明 |
|---|------|--------|------|------|
| P-PL-001 | PanelLayout 默认 query 预设（results 隐） | P0 | 自动化 | `test/providers/tab_provider_panel_layout_test.dart` |
| P-PL-002 | addResultToTab/addErrorMessageToTab 翻 resultsVisible true（含 0 行空集） | P0 | 自动化 | 同上（FR-009） |
| P-PL-003 | closeAllTabs 清理 per-tab 布局（会话内不持久化） | P1 | 自动化 | 同上 |
| P-PL-004 | 新建 query tab 默认 PanelLayout.query | P0 | 自动化 | 同上（US4/T027） |
| SQL-FB-001 | buildFilteredSelect 各方言引号 + SQLServer TOP vs LIMIT | P0 | 自动化 | `test/utils/filter_query_builder_test.dart` |
| SQL-FB-002 | AND/OR、isNull/isNotNull、like | P0 | 自动化 | 同上 |
| SQL-FB-003 | 恶意值（O'Brien/;/--）escapeString 转义 + 标识符白名单跳过 | P0 | 自动化 | 同上（注入防护） |
| SQL-FB-004 | boolean 按 dbType 裸值（PG TRUE/FALSE、其余 1/0） | P0 | 自动化 | 同上 |
| E2E-041-BROWSE | Browse Data → data 模式（PanelLayout.browse + browseTarget + 自动执行 results + resultsVisible + 字段加载） | P0 | 集成 | `mysql_sidebar_menu_e2e_test.dart` / `postgresql_sidebar_menu_e2e_test.dart`（真库） |
| E2E-041-OPEN | 双击表/视图/物化视图、最近/收藏行点击 → query 编辑器（editorVisible=true、browseTarget=null、预填 SQL、不自动执行）；TC-SS-BRW-001 同规则（widget） | P0 | 集成 | 同上 + `sqlserver_sidebar_menu_e2e_test.dart`（NAV-001/002）+ `test/organisms/sidebar/sqlserver_sidebar_tree_test.dart`（真库+widget） |
| E2E-041-FILTER | FilterBar Apply → eq/AND/OR 过滤行数 + 恶意值转义 + 注入防护（表仍在） | P0 | 集成 | `mysql_sidebar_menu_e2e_test.dart`（真库） |
| E2E-041-BOOL | FilterBar boolean → tinyint(1) 1/0 过滤 | P1 | 集成 | 同上（真库） |
| UE-041-M01 | data 模式视觉：仅 FilterBar + 数据网格，无 editor/工具栏/子标签 | P0 | 人工 | 生成 exe 后肉眼 |
| UE-041-M02 | FilterBar 自适应高度（1-3 行随内容，4+ 滚动） | P1 | 人工 | 同上 |
| UE-041-M03 | date 列日历选择器、boolean/MySQL-enum 下拉 | P1 | 人工 | 同上 |

---

## 12. UI 组件测试 — 结果展示 (UR)

### 12.1 已覆盖 (Batch 3)

**自动化**: `test/organisms/results/virtualized_data_table_test.dart` (6), `test/organisms/results/statistics_panel_test.dart` (8), `test/organisms/results/messages_view_test.dart` (5), `test/organisms/results/query_history/` (16+)  
**性能基准（Debug 代理, contracts C2）**: `test/organisms/results/virtualized_data_table_benchmark_test.dart` (2 用例) — U1 10 万行首帧 build+layout、U2 深滚动帧耗时；**开发期回归线，非验收依据**；基线见 `docs/appeal_product_analysis.md` §4.1.6  
**Profile 帧率验收基准（feature 038, contracts C3, SC-002 验收依据）**: `integration_test/results_scroll_frame_benchmark_test.dart` — 合成 10 万行 × 6 列（复用 Debug 代理同款生成器，**无需真实库**），以 `flutter drive --profile -d windows --driver=test_driver/integration_test.dart --target=integration_test/results_scroll_frame_benchmark_test.dart` 运行，经 `IntegrationTestWidgetsFlutterBinding.watchPerformance` 采集 `scroll_100k`/`jump_100k`（`average_frame_build_time_millis` ≤ 33ms）与 `first_frame_100k`（≤ 380ms）；输出落 `build/integration_response_data.json`。修复前 Debug 代理基线 U1 479ms / U2 232ms → 修复后 312ms / 74ms（research.md D4）；**Profile 验收达标（T011, 2026-07-21）**：scroll_100k avg 2.47ms（p99 4.66/worst 10.76）/ jump_100k avg 8.64ms / first_frame_100k 26.04ms，均远优于 ≤33ms/≤380ms 预算，missed_frame_build_budget_count=0；数值回填 `docs/appeal_product_analysis.md` §4.1.6  
**集成**: `integration_test/results_display_test.dart`

| 组件 | 测试状态 |
|------|---------|
| VirtualizedDataTable | ✅ (6 用例) |
| StatisticsPanel | ✅ (8 用例) |
| MessagesView 构造函数约定 | ✅ (5 用例) |
| ResultHistoryView / ResultHistoryItem / ResultHistoryHeader / ResultHistoryPagination | ✅ (16+ 用例) |
| ResultsWidget Tab 切换 | ✅ (Widget + 集成覆盖) |
| CardView/ChartView | 🔴 视觉组件 (人工) |

### 12.2 结果面板查询历史 (Result Panel Query History)

**自动化**: `test/organisms/results/query_history/result_history_view_test.dart` (7), `test/organisms/results/query_history/result_history_item_test.dart` (4), `test/organisms/results/query_history/result_history_header_test.dart` (2), `test/organisms/results/query_history/result_history_pagination_test.dart` (3), `test/organisms/results/results_widget_test.dart` (3), `test/organisms/results/result_subtab_bar_test.dart` (+1), `test/organisms/editor/query_editor_widget_test.dart` (3), `test/providers/tab_provider_test.dart` (+5), `test/providers/query_history_provider_test.dart` (+2)

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| UR-QH-001 | ResultHistoryView 渲染历史列表与日期分组 | P0 | 自动化 | 按 Today/Yesterday/Last 7 days/Older 分组展示 |
| UR-QH-002 | ResultHistoryView 空态 | P0 | 自动化 | 无历史时显示空提示 |
| UR-QH-003 | ResultHistoryItem 渲染 SQL 摘要与时间戳 | P0 | 自动化 | 行内显示脱敏 SQL 摘要与执行时间 |
| UR-QH-004 | ResultHistoryItem 双击复用 | P0 | 自动化 | 双击将完整 SQL 追加到编辑器底部 |
| UR-QH-005 | ResultHistoryItem 右键删除 | P1 | 自动化 | 右键菜单触发删除确认 |
| UR-QH-006 | ResultHistoryHeader 搜索过滤 | P0 | 自动化 | 输入关键词即时过滤 SQL 摘要/时间戳 |
| UR-QH-007 | ResultHistoryHeader 清空全部 | P1 | 自动化 | 清空按钮弹出二次确认 |
| UR-QH-008 | ResultHistoryPagination 分页切换 | P1 | 自动化 | 上一页/下一页/首页/末页更新可见记录 |
| UR-QH-009 | ResultsWidget 历史/结果视图切换 | P0 | 自动化 | 执行后自动切到结果视图，可手动返回历史 |
| UR-QH-010 | ResultSubTabBar pinned History 子标签 | P0 | 自动化 | 历史子标签固定、可点击切换、不可关闭 |
| UR-QH-011 | TabProvider history 子标签行为 | P0 | 单元测试 | 新建 Tab 自动创建 pinned history 子标签 |
| UR-QH-012 | QueryHistoryProvider 连接范围搜索 | P0 | 单元测试 | 连接级搜索/过滤辅助方法 |
| UR-QH-013 | 性能：500 条历史加载 <1s | P1 | 自动化 | 大数据量列表加载 smoke test |
| UR-QH-014 | 性能：搜索过滤 <300ms | P1 | 自动化 | 100 条记录搜索过滤 smoke test |
| UR-QH-015 | 性能：双击回调 <2s | P1 | 自动化 | 历史条目双击响应 smoke test |
| UR-QH-016 | 性能：分页切换 <500ms | P1 | 自动化 | 分页按钮切换响应 smoke test |
| UR-QH-017 | 性能：历史↔结果视图切换 <500ms | P1 | 自动化 | 视图切换响应 smoke test |
| UR-QH-018 | 切换到 History 后 ResultSubTabBar 保持可见 | P0 | 自动化 | ResultsWidget 始终渲染 ResultSubTabBar，History 激活时结果子标签仍可点击 |
| UR-QH-019 | History↔Results 切换不重新执行查询 | P0 | 自动化 | 切回结果视图时复用已有 ExecutionResult，不触发新的查询执行 |
| UR-QH-020 | ResultHistoryTable 渲染表格列 | P0 | 自动化 | 列包含 Executed At / SQL Preview / Duration / Row Count / Status |
| UR-QH-021 | 历史行单击替换编辑器 SQL | P0 | 自动化 | 单击行调用 onHistoryTapped 并将完整 SQL 加载到当前编辑器 |
| UR-QH-022 | 历史行双击追加编辑器 SQL | P1 | 自动化 | 双击行调用 onHistoryDoubleTapped 将 SQL 追加到编辑器底部 |
| UR-QH-023 | 长 SQL 预览截断不破坏布局 | P1 | 自动化 | 超长 SQL 在 SQL Preview 列截断显示，列对齐保持 |
| UR-QH-024 | 历史表格无排序/过滤控件 | P1 | 自动化 | 当前迭代表格静态展示，不渲染列头排序按钮或过滤器 |

### 12.3 结果展示人工测试

| # | 用例 | 优先级 | 说明 |
|---|------|--------|------|
| UR-M001 | 网格/卡片视图切换 | P0 | 切换后数据一致 |
| UR-M002 | 列宽手动调整 | P0 | 拖拽列分隔线 |
| UR-M003 | 列隐藏/显示 | P0 | 右键列头隐藏/恢复 |
| UR-M004 | 单列排序 | P0 | 点击列头切换升降序 |
| UR-M005 | 多列排序 | P1 | Shift+点击多列 |
| UR-M006 | 复制单元格 | P0 | 右键 → Copy Cell |
| UR-M007 | 复制行为 JSON/CSV/SQL | P0 | 右键复制多种格式 |
| UR-M008 | 导出 CSV/JSON/Excel | P0 | 导出文件内容验证 |
| UR-M009 | 大数据集滚动性能 | P1 | 10,000+ 行滚动流畅性 |
| UR-M010 | 分页控件 | P0 | 上一页/下一页/跳转 |

---

## 13. UI 组件测试 — 侧边栏 (US)

### 13.1 已覆盖 (Batch 3)

**自动化**: `test/organisms/tree_item_test.dart` (16), `test/organisms/tree_item_extended_test.dart` (9), `test/organisms/sidebar/query_history/` (3+)  
**集成**: `integration_test/sidebar_tree_test.dart`

| 组件 | 状态 |
|------|------|
| TreeItem (label/icon/arrow/badge/emoji/loading/trailing/onTap/onDoubleTap/levels/showArrow/Tooltip) | ✅ (25 用例，含 US-008/US-009 截断 Tooltip，契约 C6，特性 046 T030) |
| QueryHistorySection (渲染/搜索/打开/范围) | ✅ 已迁移至结果面板 (UR-QH-xxx) |
| QueryHistoryItem (渲染/右键/打开) | ✅ 已迁移至结果面板 (UR-QH-xxx) |
| SidebarTree | ✅ Widget 测试覆盖 (015-sidebar-scroll-jump-fix: 不可变 Set 替换模式 + 稳定 key + scrollController 安全网 + 搜索/键盘导航滚动保持) |
| MySQL/PG/Mongo/Redis/SQLite/SQLServer/Doris/TDengine TreeBuilder | ✅ PG/SQL Server schema-first tree (013-pg-sidebar-audit: data loading + keyboard nav + search + badges). Remaining builders pending. |
| Connection/Database/Table ContextMenu | ✅ MySQL E2E 覆盖 (39 用例)；其他数据库/剩余菜单项待补充 |

TreeItem 截断 Tooltip 用例（契约 C6，特性 046 T030，`test/organisms/tree_item_test.dart`）：

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| US-008 | TreeItem 截断 label 悬停 Tooltip 携带完整名 | P1 | 自动化 | label 分支包裹 Tooltip 且 message 为未截断完整 label |
| US-009 | TreeItem labelWidget 分支不挂 Tooltip | P2 | 自动化 | labelWidget 模式不冗余包裹 Tooltip |

### 13.2 侧边栏查询历史测试

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| US-001 | QueryHistorySection 渲染与分组 | P1 | 自动化 | 按 Today/Yesterday/Older 分组展示 |
| US-002 | QueryHistorySection 空态 | P1 | 自动化 | 无历史时显示空提示 |
| US-003 | QueryHistorySection 搜索过滤 | P1 | 自动化 | 按 SQL/标题/数据库/连接名/时间戳过滤 |
| US-004 | QueryHistorySection 点击打开新 Tab | P1 | 自动化 | 点击历史条目在正确连接/数据库下打开 |
| US-005 | QueryHistorySection 按连接范围过滤 | P1 | 自动化 | 仅展示当前连接的历史 |
| US-006 | QueryHistoryItem 右键重命名/删除 | P2 | 自动化 | 右键菜单触发重命名和删除回调 |
| US-007 | 工具栏历史按钮已移除 | P2 | 自动化 | QueryEditorToolbar 不再包含历史按钮 |

### 13.3 侧边栏人工测试

| # | 用例 | 优先级 | 说明 |
|---|------|--------|------|
| US-M001 | 多连接树形展示 | P0 | 多类型连接区分 |
| US-M002 | 树节点展开/折叠 | P0 | 性能（100+ 表）|
| US-M003 | 右键菜单完整性 | P0 | 各节点类型菜单项正确 |
| US-M004 | 双击数据库打开 Workspace | P0 | 侧边栏→Workspace 联动 |
| US-M005 | 双击表名打开查询 | P0 | 自动生成 SELECT * FROM |
| US-M006 | 搜索过滤 | P1 | 实时过滤、高亮 |
| US-M007 | 单击保存查询选中 | P0 | 单击保存查询项仅高亮，不打开 |
| US-M008 | 双击保存查询打开 Tab | P0 | 双击保存查询项在编辑器中打开 |
| US-M009 | 双击已打开保存查询激活现有 Tab | P0 | 重复双击同一保存查询不创建重复 Tab |
| US-M010 | PG schema 优先树渲染 | P0 | 连接 PG 多 schema DB → 展开 DB 节点 → schema 节点出现 (非 "No data") (013-pg-sidebar-audit) |
| US-M011 | PG schema 按对象类型分类 | P1 | 展开 schema → Tables/Views/Functions/Procedures 分类显示 (013-pg-sidebar-audit) |
| US-M012 | 非 schema-aware DB 平面结构不变 | P0 | MySQL/SQLite 展开后仍为平面层次，无回归 (013-pg-sidebar-audit) |
| US-M013 | schema 徽章分类格式 | P2 | 徽章显示 "12 tables, 3 views" 而非纯数字 "15" (013-pg-sidebar-audit) |
| US-M014 | schema 键盘导航 | P2 | 箭头键展开/折叠 schema 节点，Enter 进入选择 (013-pg-sidebar-audit) |
| US-M015 | schema 搜索过滤 | P2 | 搜索表名自动展开至包含该表的 schema 节点 (013-pg-sidebar-audit) |

### 13.4 MySQL 侧边栏菜单端到端测试

**测试文件**: `integration_test/mysql_sidebar_menu_e2e_test.dart` (84 用例，全部通过)  
**执行环境**: 真实 MySQL 8.0.46 (`192.168.x.x:3306`)  
**测试目标**: 覆盖 SidebarTree 中连接、数据库、分类文件夹、表、列、索引、外键、视图、存储过程、触发器、事件、进程、用户、保存查询、最近/收藏表节点的单击、双击、右键菜单 → 对话框 → 确认 → 数据库状态验证的完整链路。

| # | 用例 | 优先级 | 类型 | 内容 | 对应文件 |
|---|------|--------|------|------|----------|
| E2E-SM-001 | 连接节点 → Create Database | P0 | 集成 | 右键连接 → Create Database → 输入库名 → 确认 → 数据库真实创建 → 侧边栏刷新 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-002 | 数据库节点 → Drop Database | P0 | 集成 | 右键数据库 → Drop Database → 输入确认 → 数据库被删除 → 不再存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-003 | 数据库节点 → New Table | P0 | 集成 | 右键数据库 → New Table → 输入表名/列名 → 表真实创建 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-004 | 表节点 → Browse Data | P0 | 集成 | 右键表 → Browse Data → 打开新查询 Tab 并生成 SELECT | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-005 | 表节点 → Drop Table | P0 | 集成 | 右键表 → Drop Table → 输入确认 → 表被删除 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-006 | 表节点 → Truncate Table | P0 | 集成 | 右键表 → Truncate → 确认 → 数据清空但结构保留 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-007 | 视图节点 → Drop View | P0 | 集成 | 右键视图 → Delete → 视图被删除 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-008 | 存储过程节点 → Drop Procedure | P0 | 集成 | 右键存储过程 → Delete → 存储过程被删除 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-009 | 触发器节点 → Drop Trigger | P0 | 集成 | 右键触发器 → Delete Trigger → 触发器被删除 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-010 | 事件节点 → Drop Event | P0 | 集成 | 右键事件 → Drop Event → 事件被删除 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-011 | 进程节点 → 右键菜单存在 | P1 | 集成 | 右键进程节点 → Kill Query / Copy Query 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-012 | 用户节点 → 右键菜单存在 | P1 | 集成 | 右键用户节点 → Copy Name / Refresh 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-013 | 表节点 → 双击 Browse Data | P0 | 集成 | 双击表 → 自动生成 SELECT 并打开 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-014 | 数据库节点 → 双击打开查询 Tab | P1 | 集成 | 双击数据库 → 切换当前数据库并打开新查询 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-015 | 视图节点 → Browse Data | P1 | 集成 | 右键视图 → Browse Data → 打开视图浏览查询 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-016 | 存储过程节点 → Call | P1 | 集成 | 右键存储过程 → Call → 生成 CALL SQL 并打开 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-017 | 触发器节点 → View Definition | P1 | 集成 | 右键触发器 → View Definition → 打开 DefinitionViewDialog | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-018 | 表节点 → Analyze Table | P1 | 集成 | 右键表 → Analyze Table → 执行 maintenance 命令 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-019 | 表节点 → Optimize Table | P1 | 集成 | 右键表 → Optimize Table → 执行 maintenance 命令 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-020 | 表节点 → Check Table | P1 | 集成 | 右键表 → Check Table → 执行 maintenance 命令 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-021 | 表节点 → Rename Table | P1 | 集成 | 右键表 → Rename → 输入新名 → 表被重命名 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-022 | 连接节点 → Refresh | P1 | 集成 | 右键连接 → Refresh → 刷新数据库列表 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-023 | 连接节点 → Disconnect | P1 | 集成 | 右键连接 → Disconnect → 连接断开 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-024 | 连接节点 → Connect | P1 | 集成 | 右键未连接保存连接 → Connect → 连接成功 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-025 | 数据库节点 → Select Database | P1 | 集成 | 右键数据库 → Select Database → 当前数据库切换 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-026 | 索引叶子 → Drop Index | P1 | 集成 | 右键索引叶子 → Delete → 索引被删除 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-027 | 表节点 → 展开结构 | P1 | 集成 | 单击表 → 显示列、索引、外键子节点 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-028 | 列叶子 → Insert into Editor | P2 | 集成 | 右键列叶子 → Insert into Editor 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-029 | 索引叶子 → Copy Name / Insert into Editor | P2 | 集成 | 右键索引叶子 → Copy Name / Insert into Editor 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-030 | 外键叶子 → Copy Name / Insert into Editor | P2 | 集成 | 右键外键叶子 → Copy Name / Insert into Editor 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-031 | 连接节点 → Toggle Read-Only | P1 | 集成 | 右键连接 → Toggle Read-Only → 只读标志切换 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-032 | 连接节点 → Collapse All | P2 | 集成 | 右键连接 → Collapse All → 所有展开节点折叠 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-033 | 连接节点 → Delete Connection | P1 | 集成 | 右键连接 → Delete → 保存连接被删除 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-034 | 数据库节点 → Properties | P1 | 集成 | 右键数据库 → Properties → 打开 DatabasePropertiesDialog | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-035 | 表节点 → Engine Status | P1 | 集成 | 右键表 → Engine Status → 打开引擎状态对话框 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-036 | 视图节点 → Copy Name | P2 | 集成 | 右键视图 → Copy Name 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-037 | 存储过程节点 → Copy Name | P2 | 集成 | 右键存储过程 → Copy Name 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-038 | 触发器节点 → Copy Name | P2 | 集成 | 右键触发器 → Copy Name 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-039 | Tables 文件夹 → Refresh | P2 | 集成 | 右键 Tables 文件夹 → Refresh → 重新加载表列表 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-040 | 列叶子 → Copy Name / Type / All | P2 | 集成 | 右键列叶子 → Copy Name / Type / All 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-041 | 列叶子 → 双击插入列名 | P2 | 集成 | 双击列叶子 → 将列名插入当前编辑器 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-042 | 触发器节点 → Insert into Editor | P2 | 集成 | 右键触发器 → Insert into Editor 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-043 | 事件节点 → Copy Name / Insert into Editor | P2 | 集成 | 右键事件 → Copy Name / Insert into Editor 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-044 | 索引叶子 → Edit Index | P2 | 集成 | 右键索引叶子 → Edit Index 菜单项存在 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-045 | 视图节点 → 双击 Browse Data | P2 | 集成 | 双击视图 → 打开视图浏览查询 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-046 | 存储过程节点 → 双击 Call | P2 | 集成 | 双击存储过程 → 生成 CALL SQL 并打开 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-047 | 连接节点 → Edit Connection | P1 | 集成 | 右键连接 → Edit Connection → 打开 ConnectionDialog | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-048 | 连接节点 → Clone Connection | P1 | 集成 | 右键连接 → Clone Connection → 保存列表出现副本连接 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-049 | 连接节点 → Export This Connection | P2 | 集成 | 右键连接 → Export This Connection → 打开导出对话框 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-050 | 连接节点 → Move to Group | P2 | 集成 | 右键连接 → Move to Group → 选择分组后真实移动连接，并验证 groupId 更新 / Remove from Group | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-051 | 表节点 → Properties | P1 | 集成 | 右键表 → Properties → 打开 TablePropertiesDialog | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-052 | 表节点 → Edit Table | P1 | 集成 | 右键表 → Edit Table → 打开 EditTableDialog | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-053 | 保存查询生命周期 | P1 | 集成 | 创建 / 打开 / 重命名 / 删除保存查询 → UI 同步更新 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-054 | Recent Tables 区域 → Clear All | P2 | 集成 | 记录最近访问表 → 显示 Recent 区域 → Clear All 后清空 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-055 | Favorite Tables 区域 → 取消收藏 | P2 | 集成 | 收藏表 → 显示 Favorite 区域 → 点击星标取消收藏 → 区域消失 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-056 | 表节点 → Edit Table 真实保存 | P1 | 集成 | 右键表 → Edit Table → 添加列 → 保存 → 数据库表结构真实变更 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-057 | Recent 表行 → 单击 Browse | P1 | 集成 | 单击 Recent 表行 → 打开 Browse Data 查询 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-058 | Favorite 表行 → 单击 Browse | P1 | 集成 | 单击 Favorite 表行 → 打开 Browse Data 查询 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-059 | 保存查询行 → 双击打开 | P2 | 集成 | 双击保存查询行 → 打开查询 Tab 并加载 SQL | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-060 | 表节点 → Data Sync | P1 | 集成 | 选择源/目标连接、库、表 → 同步 → 目标表数据正确 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-061 | 数据库节点 → Schema Diff & Sync | P1 | 集成 | 选择源/目标数据库 → Compare → 显示 Schema 差异对象 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-062 | 列叶子 → Copy Column Name | P2 | 集成 | 右键列叶子 → Copy column name → 断言剪贴板内容为列名 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-063 | 索引叶子 → Copy Index Name | P2 | 集成 | 右键索引叶子 → Copy index name → 断言剪贴板内容为索引名 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-064 | 视图节点 → Copy Name | P2 | 集成 | 右键视图 → Copy Name → 断言剪贴板内容为视图名 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-065 | 存储过程节点 → Copy Name | P2 | 集成 | 右键存储过程 → Copy Name → 断言剪贴板内容为过程名 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-066 | Server 全局节点 → 展开加载状态 | P1 | 集成 | 单击 Server 节点 → 展开并显示 MySQL 版本/运行时间/线程数/查询数等 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-067 | Performance 全局节点 → 展开进程列表 | P1 | 集成 | 单击 Performance 节点 → 展开并显示进程列表与刷新间隔选择器 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-068 | Users 全局节点 → 展开用户列表 | P1 | 集成 | 单击 Users 节点 → 展开并显示用户列表 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-069 | 用户叶子 → Copy Name | P2 | 集成 | 右键用户叶子 → Copy Name → 断言剪贴板内容为 `user@host` | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-070 | 触发器节点 → 双击 View Definition | P2 | 集成 | 双击触发器节点 → 打开 DefinitionViewDialog | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-071 | 连接节点 → 单击切换当前连接 | P2 | 集成 | 单击已保存连接 → 当前活跃连接切换为目标连接 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-072 | 连接节点 → 双击连接未连接服务器 | P2 | 集成 | 双击未连接的保存连接 → 连接成功 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-073 | 数据库节点 → Refresh | P2 | 集成 | 右键数据库 → Refresh → 重新加载数据库对象 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-074 | 外键叶子 → 双击插入名称 | P2 | 集成 | 双击外键叶子 → 将外键名插入当前编辑器 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-075 | 事件节点 → 单击复制名称 | P2 | 集成 | 单击事件节点 → 复制事件名到剪贴板 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-076 | 视图节点 → 单击 Browse Data | P2 | 集成 | 单击视图节点 → 打开视图浏览查询 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-077 | 存储过程节点 → 单击 Call | P2 | 集成 | 单击存储过程节点 → 生成 CALL SQL 并打开 Tab | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-078 | 列叶子 → 单击选中 | P2 | 集成 | 单击列叶子 → TreeItem 进入选中状态 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-079 | 外键叶子 → 单击选中 | P2 | 集成 | 单击外键叶子 → TreeItem 进入选中状态 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-080 | 数据库节点 → Save Schema Snapshot 真实保存 | P1 | 集成 | 右键数据库 → Save Schema Snapshot → 断言本地快照文件生成 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-081 | Performance 节点 → 自动刷新间隔切换 | P1 | 集成 | 点击 5s/Off 间隔按钮 → 验证 provider 自动刷新间隔变化 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-082 | 进程叶子 → Copy Query | P1 | 集成 | 右键运行中的查询进程 → Copy Query → 断言剪贴板包含 SQL | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-083 | 进程叶子 → Kill Query | P1 | 集成 | 右键运行中的查询进程 → Kill Query → 断言进程从列表消失 | `mysql_sidebar_menu_e2e_test.dart` |
| E2E-SM-084 | 连接节点 → drag-and-drop 移动到分组 | P0 | 集成 | 拖拽连接节点到分组文件夹 → 验证 groupId 更新 | `mysql_sidebar_menu_e2e_test.dart` |

> **注意**: 上述测试中发现并修复了两个生产缺陷：
> 1. `sidebar_tree.dart` 中 `_doTruncateTable` 的 `showDialog` 返回类型与 `TruncateTableConfirmDialog` 不匹配，导致确认后实际未执行清空。修复后 E2E-SM-006 通过。
> 2. `sidebar_tree.dart` 在未创建连接分组时未渲染 Favorite Tables 区域，导致收藏表不可见。修复后在无分组模式下也会显示收藏区域，E2E-SM-055 通过。

---

### 13.5 Redis 二/三波编辑器与工作台端到端测试

**测试文件**: `integration_test/redis_wave23_editors_e2e_test.dart` (8 用例，全部通过)
**执行环境**: 真实 Redis 7.4.2 (`192.168.x.x:6379`，db15)
**测试目标**: 覆盖第二波键编辑器（Geo/Stream/大 key）与第三波 Lua 脚本工作台的完整交互链路，替代受 RDP 输入注入不稳影响的 Win32 GUI 点击驱动。详细用例与验证记录见内部测试报告（W2.4/W2.5/W2.7/W2.8/W3.3–W3.6）。

| # | 用例 | 优先级 | 内容 |
|---|------|--------|------|
| E2E-RED-ED-001 | Geo 编辑器（W2.4） | P0 | zset key → 切 Geo 视图 → 成员坐标 → GEODIST（与服务器值一致）→ GEOADD → 删除成员，服务端 ZCARD 校验 |
| E2E-RED-ED-002 | Stream 编辑器（W2.5） | P0 | XADD/XDEL/XTRIM（近似语义）/消费者组 CREATE/DESTROY，服务端 XLEN/XINFO GROUPS 校验 |
| E2E-RED-ED-003 | CONFIG SET（W2.7） | P0 | Config 节点 → Edit Config → loglevel 修改生效并恢复；只读参数 databases 友好失败提示 |
| E2E-RED-ED-004 | 大 key 编辑器（W2.8） | P1 | 3000 字段 hash + 3000 成员 set 编辑器正常加载渲染，无阻塞无报错 |
| E2E-RED-ED-005 | Lua 工作台管理（W3.3） | P0 | New → Save → 列表 → 改名 Save → Delete（确认）全流程 |
| E2E-RED-ED-006 | Lua Sync（W3.4） | P0 | Sync → sha1 写回 → 列表 synced → 服务端 SCRIPT EXISTS=true |
| E2E-RED-ED-007 | Lua Run EVALSHA（W3.5） | P0 | synced 脚本 EVALSHA 命中返回结果；改脚本后旧 sha 触发 NOSCRIPT 自动 fallback EVAL |
| E2E-RED-ED-008 | Lua Flush（W3.6） | P1 | Flush → 服务端 SCRIPT EXISTS=false + snackbar 提示 |

### 13.6 真实库 sidebar 菜单 E2E 约定（功能自动化基线 / 单一权威源）

> **单一权威源**：本节为功能 UI 流程测试的唯一权威约定。凡涉及数据库的 UI 功能流程（右键菜单 drop table / truncate / rename / 编辑表，视图/存储过程/触发器删除，执行 SQL，Data Sync，Schema Diff，Kill Query 等）**必须连真实测试库写自动化 E2E 用例并断言功能真生效，不依赖人工点 exe**；人工仅检查渲染外观（溢出 / 显示位置 / 遮挡）。

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| E2E-SM-CONV-01 | 真实库 sidebar 菜单 E2E = 涉库功能验收唯一方式 | P0 | 约定 | 复刻 `E2E-SM-001~084` 模式：真实 `AppProvider` + adapter 连真实库 → `setUp` 建专用库 `dbmaster_test_<ts>` + 种子 → 驱动右键菜单 / 确认弹窗 → **重查断言**（`getTables()` / `getDatabases()` 等确认对象已变更）→ `tearDown` `DROP DATABASE` 回收。仅 mock 会挂起的平台通道（Pigeon / SharedPreferences / FlutterSecureStorage），**数据库本身不 mock**。连接信息见 `C:\Users\hobbs\Projects\dbmaster\test_db_server.txt`；配置走 `integration_test/config/<dbtype>_test_config.dart`（`DBMASTER_<DBTYPE>_<FIELD>` / `generateTestDatabaseName()` / `isConfigured`）。 |

**当前覆盖状态（本表为各库 sidebar 菜单 E2E 的权威清单）：**

| 数据库 | 覆盖 | spec 用例 | 测试文件 | 状态 |
|--------|------|-----------|----------|------|
| MySQL | 完整 | E2E-SM-001~084 (13.4) | `integration_test/mysql_sidebar_menu_e2e_test.dart` | ✅ 金标准模板 |
| Redis | 完整 | E2E-RED-ED-001~008 (13.5) + 19.1 | `redis_sidebar_menu_e2e_test.dart` (42) / `redis_wave23_editors_e2e_test.dart` (8) | ✅ 通过 |
| PostgreSQL | 完整 | **spec 待登记** | `postgresql_sidebar_menu_e2e_test.dart` (64 用例已实现) | ⚠️ 用例已建、spec 序列待补 |
| SQLite | 部分 | 19.1 (18) | `sqlite_nodes_context_menu_test.dart` | ◐ 仅节点右键菜单 |
| SQL Server | 完整（自动+人工） | 附录 C / SS-CAP-* (5.8.2) | `sqlserver_sidebar_menu_e2e_test.dart` (24) / `sqlserver_exec_ui_test.dart` (1) / `sqlserver_capability_parity_test.dart` | ✅ **自动化 sidebar 菜单 E2E 已实现并全绿（24 用例 `E2E-SS-*`，2026-07-15）**：真实 SQL Server 2022 + `SidebarTree` widget + 右键菜单/确认弹窗 + 重查断言，覆盖连接/数据库/表(drop/truncate/rename/edit)/视图/proc/index 删除 + 浏览/Call/SELECT 生成 + clipboard + 全局节点。Drop Table/Database/Edit-Table 三例因头肩 harness 下确认弹窗 ElevatedButton 不响应，改为「菜单开弹窗(UI) + 直接调 provider 方法 + 重查」混合验证（注释说明）。人工全量用例另见内部测试报告（~60 用例）。 |
| Doris | 方言修复真库 E2E | 027-doris-correctness-fixes | `doris_sidebar_menu_e2e_test.dart` (7) | ✅ 真实 Doris 3.0.2 方言修复 E2E 已实现并全绿（2026-07-15）：建表/重命名表列/索引(USING INVERTED)/删列/导出回灌/UPDATE 模型探测。注：本轮为 adapter/服务层方言真库断言（非完整 widget 右键菜单流，可后续按 E2E-SM 模板扩展） |
| TDengine | 无 | 19.1 集成测试 | — | ○ sidebar 菜单 E2E 待补 |

> 新增任何「改库 / 改状态」的右键菜单功能时，按 `E2E-SM-CONV-01` 复刻真实库用例并登记到对应 `E2E-<DB>-*` 序列——**未配真实库 E2E 不算功能交付**。

### 13.7 跨连接路由回归测试（Doris↔PostgreSQL）

**测试文件**: `integration_test/doris_pg_connection_routing_test.dart` (4 用例)  
**执行环境**: 真实 Doris 3.0.2 (`192.168.x.x:9030`) + PostgreSQL 17 (`192.168.x.x:5432`)  
**关联 bug**: 内部 bug 记录（展开 PG 库报 `MySQLServerException [1044] Access denied ... lykrflow_test`）  
**测试目标**: 验证 `ConnectionProvider` 元数据链路（`changeDatabase` / `switchToConnection` / `refreshDatabases` / `loadDatabaseInfo`）显式按 `connectionId` 路由，绝不静默回退到可被并发链路偷走的全局 `activeConnectionId`。每用例自建自删专用库（`dbmaster_route_d/p_<ts>`）。

| # | 用例 | 优先级 | 类型 | 内容 | 对应文件 |
|---|------|--------|------|------|----------|
| E2E-ROUTE-001 | changeDatabase 显式路由 | P0 | 集成 | 全局 active 被偷到 Doris 后 `changeDatabase(pgDb, connectionId: pgId)` → 无 errorMessage、当前库=pgDb、PG 元数据可查（修复前抛 MySQLServerException） | `doris_pg_connection_routing_test.dart` |
| E2E-ROUTE-002 | loadDatabaseInfo 归还 active | P0 | 集成 | 当前=PG 时后台加载 Doris 库信息 → 返回表数据且结束后 `dbService.activeConnectionId` 归还为 PG | `doris_pg_connection_routing_test.dart` |
| E2E-ROUTE-003 | switchToConnection 显式路由 | P1 | 集成 | 全局 active=Doris 时 `switchToConnection(pgId)` → 成功且 PG 库列表正确、无 errorMessage | `doris_pg_connection_routing_test.dart` |
| E2E-ROUTE-004 | 用户场景完整回放 | P0 | 集成 | 连 Doris 执行查询 → 连 PG → 并发执行「点击 PG 库」（switchToConnection+changeDatabase）与「Doris 节点懒加载」（loadDatabaseInfo）→ 无 MySQLServerException、active 停留 PG、双侧缓存正确 | `doris_pg_connection_routing_test.dart` |


## 14. UI 组件测试 — 连接/对话框 (UC)

### 14.1 已覆盖

**自动化**: `test/organisms/tabs_bar_widget_test.dart` (3), `test/organisms/connection/code_snippets_panel_test.dart` (4)  
**集成**: `integration_test/export_backup_test.dart` (8), `integration_test/table_dialogs_test.dart`, `integration_test/table_management_test.dart`

### 14.2 🔴 待补充自动化 (大量 P0/P1 缺口)

| # | 用例 | 优先级 | 组件 |
|---|------|--------|------|
| UC-001 | ConnectionDialog 表单验证 | P0 | `connection_dialog.dart` |
| UC-002 | ConnectionDialog 各数据库类型表单 | P0 | 类型切换时表单变化 |
| UC-003 | DatabaseDialog 数据库列表 | P1 | `database_dialog.dart` |
| UC-004 | SQLiteConnectionDialog 文件选择 | P1 | `sqlite_connection_dialog.dart` |
| UC-005 | SettingsDialog 设置面板 | P1 | `settings_dialog.dart` |
| UC-006 | SchemaDiffDialog 差异展示 | P0 | `schema_diff_dialog.dart` |
| UC-007 | BackupDialog 备份选项 | P1 | `backup_dialog.dart` |
| UC-008 | ExportDialog 导出选项 | P0 | `export_dialog.dart` |
| UC-009 | CommandPalette 命令搜索 | P1 | `command_palette.dart` |
| UC-010 | CodeFormatterDialog 格式化选项 | P1 | `code_formatter_dialog.dart` |
| UC-011 | StatusBarWidget 状态显示 | P1 | `status_bar_widget.dart` |
| UC-012 | EditableDataGrid 行编辑 | P1 | `editable_data_grid.dart` |
| UC-013 | CreateTableDialog 表创建表单 | P0 | `table_dialog/create_table_dialog.dart` |
| UC-014 | EditTableDialog 表编辑 | P1 | `table_dialog/edit_table_dialog.dart` |
| UC-015 | DropTableConfirmDialog 确认 | P1 | `table_dialog/drop_table_confirm_dialog.dart` |
| UC-016 | ERDiagramDialog ER 图 | P1 | `er_diagram_dialog.dart` |

### 14.3 连接管理人工测试

| # | 用例 | 优先级 | 说明 |
|---|------|--------|------|
| UC-M001 | 新建连接完整流程 | P0 | 各类型数据库连接表单填写和测试 |
| UC-M002 | 连接测试按钮 | P0 | 正确/错误凭证的反馈 |
| UC-M003 | SSH 隧道配置 | P1 | SSH 配置项和连接测试 |
| UC-M004 | SSL/TLS 配置 | P1 | 证书选择和验证 |
| UC-M005 | 连接编辑/删除 | P0 | 修改和删除已有连接 |
| UC-M006 | Schema Diff 对话框操作 | P1 | 源/目标选择、差异浏览 |
| UC-M007 | ER 图交互操作 | P1 | 节点拖拽、缩放、导出 |
| UC-M008 | 命令面板搜索和执行 | P1 | 模糊搜索、命令分类 |

---

## 15. UI 组件测试 — 其他 Organisms (UAI/UEP/UT/UW)

### 15.1 AI Panel (UAI)

参见第 6.3 节 AI Panel UI 测试

### 15.2 Entity Panel (UEP)

**已覆盖**: `test/organisms/entity_panel/redis_value_viewer_test.dart` (5)

| # | 用例 | 优先级 | 组件 |
|---|------|--------|------|
| UEP-001 | EntityPanel Tab 切换 | P0 | `entity_panel.dart` |
| UEP-002 | TablesTab 表列表 | P0 | `tables_tab.dart` |
| UEP-003 | ProgrammableObjectsTab | P1 | `programmable_objects_tab.dart` |
| UEP-004 | RedisKeysTab 键浏览 | P1 | `redis_keys_tab.dart` |
| UEP-005 | RedisScriptsTab 脚本列表 | P1 | `redis_scripts_tab.dart` |
| UEP-006 | RecentTables 换行/折叠/清除 | P1 | 自动换行、折叠展开交互 |

### 15.3 Task Panel (UT)

| # | 用例 | 优先级 | 组件 |
|---|------|--------|------|
| UT-001 | TaskPanel 任务列表渲染 | P0 | `task_panel.dart` |
| UT-002 | TaskListItem 进度显示 | P0 | `task_list_item.dart` |
| UT-003 | TaskDetailDialog 详情 | P1 | `task_detail_dialog.dart` |
| UT-004 | ExportTaskCreateDialog | P1 | `export_task_create_dialog.dart` |
| UT-005 | 任务取消和重试 | P1 | 取消进行中任务 |

### 15.4 Smart Import (UW-IM)

| # | 用例 | 优先级 | 说明 |
|---|------|--------|------|
| UW-IM-001 | SmartImportDialog 文件上传 | P0 | 拖拽/选择文件 |
| UW-IM-002 | ImportWizardDialog 步骤向导 | P0 | 多步向导导航 |
| UW-IM-003 | 列映射 UI | P1 | 源列→目标列映射 |
| UW-IM-004 | 类型推断结果展示 | P1 | 自动推断的类型建议 |

### 15.5 Workspace Tab Bar (UW)

| # | 用例 | 优先级 | 测试内容 |
|---|------|--------|---------|
| UW-001 | WorkspaceTabBar 多 Workspace 切换 | P0 | 切换时 EntityPanel/QueryTabs 联动 |
| UW-002 | Workspace 退出确认 | P1 | 有未保存查询时确认 |

### 15.6 其他

| # | 用例 | 优先级 | 组件 |
|---|------|--------|------|
| UO-001 | AppCharts 图表渲染 | P2 | `charts/app_charts.dart` |
| UO-002 | QueryPlanVisualizer 计划可视化 | P2 | `query_optimizer/query_plan_visualizer.dart` |

---

## 16. 页面/屏幕测试 (UP)

### 16.1 已覆盖

**自动化**: `test/templates/welcome_screen_test.dart` (6) ✅

### 16.2 🔴 待补充

| # | 用例 | 优先级 | 页面 | 测试内容 |
|---|------|--------|------|---------|
| UP-HOME-001 | HomeScreen 渲染 | P0 | `home_screen.dart` | 侧边栏+主区域+状态栏布局 |
| UP-HOME-002 | HomeScreen 面板分隔调整 | P1 | | ResizableSplitView 拖拽 |
| UP-HOME-003 | HomeScreen 窗口缩放适配 | P1 | | 最小/最大窗口下的布局 |
| UP-LOGIN-001 | LoginPage 表单验证 | P1 | `login_page.dart` | 空字段/无效凭证错误提示 |
| UP-LOGIN-002 | LoginPage 登录成功跳转 | P1 | | 登录后导航到 HomeScreen |
| UP-REG-001 | RegisterPage 注册表单 | P2 | `register_page.dart` | 字段验证、密码强度 |
| UP-FORGOT-001 | ForgotPasswordPage 重置 | P2 | `forgot_password_page.dart` | 邮箱验证发送 |
| UP-PROFILE-001 | ProfilePage 资料编辑 | P2 | `profile_page.dart` | 头像/昵称修改 |
| UP-AICHAT-001 | AIChatPage 独立页面 | P2 | `ai_chat_page.dart` | 全屏 AI 聊天模式 |
| UP-MAIN-001 | MainWorkspace 布局 | P1 | `main_workspace.dart` | WorkspaceTabBar + QueryTabBar + Editor + Results |
| UP-CONN-001 | ConnectingScreen 加载状态 | P2 | `connecting_screen.dart` | 连接中动画 |

### 16.3 页面人工测试

| # | 用例 | 优先级 | 说明 |
|---|------|--------|------|
| UP-M001 | HomeScreen 完整布局 | P0 | 所有面板正确渲染 |
| UP-M002 | 分割面板拖拽 | P0 | 侧边栏/编辑器/结果的拖拽分隔 |
| UP-M003 | 窗口缩放响应式 | P0 | 最大化/最小化/自定义大小 |
| UP-M004 | 登录/注册完整流程 | P1 | 创建账号→登录→使用 |
| UP-M005 | 欢迎屏幕交互 | P1 | 最近连接/新建连接/设置按钮 |

---

## 17. 专用服务测试 (SVC)

### 17.1 已覆盖

| 测试 | 用例数 | 服务 |
|------|--------|------|
| `redis_script_service_test.dart` | 7 | RedisScriptService |
| `code_snippet_service_test.dart` | 19 | CodeSnippetService |
| `mongodb_shell_parser_test.dart` | 27 | MongoDBShellParser |
| `stored_procedure_service_test.dart` | 22 | StoredProcedureService |
| `trigger_service_test.dart` | 24 | TriggerService |
| `data_sync/data_sync_service_test.dart` | 12 | DataSyncService |

### 17.2 🔴 待补充

| # | 用例 | 优先级 | 服务 | 测试重点 | 状态 |
|---|------|--------|------|---------|------|
| SVC-PROC-001 | StoredProcedureService 获取列表 | P1 | `stored_procedure_service.dart` | 各数据库存储过程列表 | ✅ 已覆盖 |
| SVC-PROC-002 | StoredProcedureService 获取定义 | P1 | | 存储过程源码 | ✅ 已覆盖 |
| SVC-TRIG-001 | TriggerService 获取列表 | P1 | `trigger_service.dart` | 各数据库触发器列表 | ✅ 已覆盖 |
| SVC-TRIG-002 | TriggerService 创建/删除 | P1 | | 触发器 CRUD | ✅ 已覆盖 |
| SVC-SYNC-001 | DataSyncService 表同步配置 | P1 | `data_sync/` | 源↔目标映射 | ✅ 已覆盖 |
| SVC-SYNC-002 | DataSyncService 增量同步 | P2 | | 变更检测和同步 | 🔴 未覆盖 |
| SVC-TASK-001 | TaskExecutor 任务执行 | P0 | `task/task_executor.dart` | 任务排队、执行、状态变更 | 🔴 未覆盖 |
| SVC-TASK-002 | ExportTaskExecutor 导出任务 | P1 | `task/export_task_executor.dart` | 大文件流式导出 | 🔴 未覆盖 |
| SVC-TASK-003 | ImportTaskExecutor 导入任务 | P1 | `task/import_task_executor.dart` | 批量导入、错误处理 | 🔴 未覆盖 |
| SVC-TASK-004 | TaskExecutor 任务取消 | P1 | | 取消信号传播 | 🔴 未覆盖 |
| SVC-TASK-005 | TaskExecutor 并发控制 | P2 | | 最大并发任务数 | 🔴 未覆盖 |

---

## 18. 🔴 新增模块测试（现有文档未覆盖）

### 18.1 Auth 系统完整测试

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| NEW-AUTH-001 | 用户注册 → 登录 → 使用 | P0 | 集成 | 完整认证流程 |
| NEW-AUTH-002 | Token 过期自动刷新 | P1 | 自动化 | Refresh token 机制 |
| NEW-AUTH-003 | 多设备登录 | P2 | 人工 | Session 管理 |
| NEW-AUTH-004 | 第三方登录 (Google/GitHub) | P2 | 人工 | OAuth 回调 |

### 18.2 Data Sync 系统

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| NEW-DS-001 | MySQL→PostgreSQL 表同步 | P1 | 集成 | 跨数据库全量同步 |
| NEW-DS-002 | 同步冲突检测 | P1 | 自动化 | 主键冲突处理 |
| NEW-DS-003 | 同步进度显示 | P1 | 人工 | UI 进度条 |

### 18.3 Agent Checkpoint 系统

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| NEW-CP-001 | AgentCheckpoint 序列化 | P1 | 自动化 | `agent_checkpoint.dart` toJson/fromJson |
| NEW-CP-002 | Checkpoint 保存/恢复 | P2 | 自动化 | Agent 执行中保存/恢复现场 |

### 18.4 Workspace Session 切换

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| NEW-WS-001 | Session 隔离验证 | P0 | 自动化 | 不同 Workspace 的变量/临时表互不影响 |
| NEW-WS-002 | Workspace 切换性能 | P1 | 人工 | 快速切换时 UI 无卡顿 |

### 18.5 DML 执行安全网

| # | 用例 | 优先级 | 类型 | 内容 |
|---|------|--------|------|------|
| NEW-DML-001 | DELETE 无 WHERE 拦截 | P0 | 自动化 | `DmlSafetyService.analyze()` 返回 `critical`，确认对话框弹出 |
| NEW-DML-002 | DROP TABLE 拦截 | P0 | 自动化 | 模态确认，要求输入表名，输入匹配后执行 |
| NEW-DML-003 | TRUNCATE 拦截 | P0 | 自动化 | 与 DROP TABLE 同级处理 |
| NEW-DML-004 | DROP DATABASE 拦截 | P0 | 自动化 | 要求输入数据库名确认 |
| NEW-DML-005 | UPDATE 无 WHERE 拦截 | P0 | 自动化 | 与 DELETE 无 WHERE 同级 |
| NEW-DML-006 | DELETE 有 WHERE 无 LIMIT 警告 | P1 | 自动化 | 返回 `high` 风险，警告条显示，2s 冷却确认 |
| NEW-DML-007 | UPDATE 有 WHERE + LIMIT 静默通过 | P1 | 自动化 | 返回 `normal` 风险，直接执行 |
| NEW-DML-008 | 主键 WHERE 高选择性静默通过 | P1 | 自动化 | `WHERE id = 42` 检测为 PK 精确匹配 |
| NEW-DML-009 | SQL 注释中 DML 关键字不误报 | P1 | 自动化 | `-- DELETE FROM users` 不触发拦截 |
| NEW-DML-010 | 字符串中 DML 关键字不误报 | P1 | 自动化 | `SELECT 'DELETE FROM users'` 不触发拦截 |
| NEW-DML-011 | 多语句批处理汇总确认 | P1 | 自动化 | 3 条混合风险语句 → 单次汇总对话框 |
| NEW-DML-012 | SQL 注入模式风险升级 | P2 | 自动化 | `' OR 1=1` 将 high → critical |
| NEW-DML-013 | 非 SQL 数据库跳过检查 | P1 | 自动化 | MongoDB/Redis 返回 `normal` |
| NEW-DML-014 | EXPLAIN 预检 — 全表扫描警告 | P2 | 自动化 | Seq Scan 检测 + 行数阈值 → 警告 |
| NEW-DML-015 | EXPLAIN 预检 — 索引查询静默通过 | P2 | 自动化 | 使用索引时返回 `null` |
| NEW-DML-016 | EXPLAIN 预检 — 超时静默跳过 | P2 | 自动化 | 3s 超时后不阻塞执行 |
| NEW-DML-017 | 确认对话框 — 表名匹配/不匹配 | P1 | Widget | `DmlConfirmDialog` 输入匹配 → enabled，不匹配 → disabled |
| NEW-DML-018 | 警告条 — 冷却倒计时 + LIMIT 追加 | P1 | Widget | `SafetyWarningBanner` 2s 冷却 + 点击「添加 LIMIT」 |
| NEW-DML-019 | 全局快捷键 F5 触发 DML 拦截 | P1 | 人工 | F5 执行危险 SQL → 对话框弹出 |
| NEW-DML-020 | 被阻止操作审计日志记录 | P1 | 自动化 | `logBlockedOperation()` 写入 `AppLogger` |

### 18.6 Server Platform M1（客户端免费化 + 团队服务端连接）

#### 18.6.1 US1 客户端免费化清理验证（Phase 3 / T013–T026）

| # | 用例 | 优先级 | 类型 | 内容 | 状态 |
|---|------|--------|------|------|------|
| NEW-FREE-001 | 静态检查零新增错误 | P0 | 自动化 | `dart analyze lib/` 零新增 error/warning（基线 info lint 不计） | ✅ 已覆盖 (T023) |
| NEW-FREE-002 | 全量单测回归通过 | P0 | 自动化 | `flutter test` 全部通过，无缺失 import / 断引用 | ✅ 已覆盖 (T024) |
| NEW-FREE-003 | `_LightApp` 树无 PurchaseProvider | P1 | 自动化 | `test/widget_test.dart` 不再引用 PurchaseProvider / Pro 门逻辑 | ✅ 已覆盖 (T025) |
| NEW-FREE-004 | 集成测试无 Pro 限制 | P0 | 集成 | `flutter test integration_test/` 全部数据库操作不受功能门拦截 | ✅ 已覆盖 (T026) |
| NEW-FREE-005 | UI 无购买入口残留 | P1 | 人工 | 状态栏/设置/AI 面板无购买按钮、试用弹窗、Pro 标识 | ✅ 已覆盖 (US1 独立测试） |

#### 18.6.2 US2 服务端 Auth/Workspace API（Phase 4 / T041–T043，Rust 集成测试 31 例）

| # | 用例 | 优先级 | 类型 | 内容 | 状态 |
|---|------|--------|------|------|------|
| NEW-SRV-001 | 注册成功 + 重复邮箱 409 + 校验 400 | P0 | 集成 | `auth_test.rs` register_* (4 例，含邮箱大小写不敏感唯一） | ✅ 已覆盖 |
| NEW-SRV-002 | 登录成功 + 错误密码 401 + 不存在邮箱 401 | P0 | 集成 | `auth_test.rs` login_* (3 例） | ✅ 已覆盖 |
| NEW-SRV-003 | 刷新令牌成功 + 复用 401 + 非法 401 | P0 | 集成 | `auth_test.rs` refresh_token_* (3 例） | ✅ 已覆盖 |
| NEW-SRV-004 | GET/PATCH /api/me | P0 | 集成 | `user_test.rs` (6 例：未认证 401、改资料、改密码吊销 refresh token、校验 400) | ✅ 已覆盖 |
| NEW-SRV-005 | Workspace CRUD + 成员管理 | P0 | 集成 | `workspace_test.rs` (15 例：创建/列表/详情/加入/退出/移除成员/删除，403/404/409/422 边界） | ✅ 已覆盖 |
| NEW-SRV-006 | 登录限流 5 次/分钟 → 429 | P1 | 集成 | per-IP 滑动窗口限流（T030a）。`login_rate_limited_after_5_attempts` + `rate_limit_is_per_ip`（窗口过期恢复不测——需真实等待 60s，计数逻辑由 `rate_limiter.rs` 单元测试覆盖）。⚠️ 同步修复：该中间件此前未挂载到路由（T030a 遗留缺口），已在 `router.rs` 补挂载 | ✅ 已覆盖 (2026-07-29) |

#### 18.6.3 US3 客户端-服务端连接与转化触点（Phase 5 / T057–T060，Dart 33 例）

| # | 用例 | 优先级 | 类型 | 内容 | 状态 |
|---|------|--------|------|------|------|
| NEW-CONN-001 | connect() 成功/401/500/网络错误 | P0 | 自动化 | `server_connection_test.dart` 5 例，含 trailing slash 归一化与用户友好错误消息 | ✅ 已覆盖 |
| NEW-CONN-002 | disconnect() 清理状态 | P0 | 自动化 | token/_baseUrl/连接状态全清 | ✅ 已覆盖 |
| NEW-CONN-003 | restoreSession() 有效/无 token/401 | P0 | 自动化 | 会话恢复三分支 | ✅ 已覆盖 |
| NEW-CONN-004 | getAccessToken() 连接态返回 token | P1 | 自动化 | 断开返回 null、连接返回 token | ✅ 已覆盖 |
| NEW-CONN-005 | 状态通知器生命周期 + 枚举唯一性 | P1 | 自动化 | StateNotifier 跟踪 + 状态枚举互异 | ✅ 已覆盖 |
| NEW-CONN-006 | ServerConnectDialog 渲染与输入 | P0 | Widget | `server_connect_dialog_test.dart` 8 例：字段存在、密码 obscured、输入、取消、Connect 按钮 | ✅ 已覆盖 |
| NEW-CONN-007 | ServerStatusBar 四状态渲染 | P0 | Widget | `server_status_bar_test.dart` 6 例：disconnected/connecting/connected/reconnecting + 点击弹对话框 | ✅ 已覆盖 |
| NEW-CONN-008 | ConversionGuideRow 触点展示与关闭 | P1 | Widget | `conversion_touchpoints_test.dart` 6 例：渲染/回调/自定义图标/关闭移除/guideId 独立 | ✅ 已覆盖 |

---

## 19. 集成测试 (INT)

### 19.1 现有集成测试 (31 个文件, ~715 用例)

| 文件 | 用例数 | 覆盖 | 状态 |
|------|--------|------|------|
| `ai_deepseek_end_to_end_test.dart` | 1 | DeepSeek E2E | ✅ |
| `ai_deepseek_test.dart` | 3 | DeepSeek API | ✅ |
| `ai_panel_test.dart` | 9 | AI 面板 | ✅ |
| `ai_panel_widget_flow_test.dart` | 2 | AI Panel Widget Flow | ✅ |
| `app_startup_test.dart` | 3 | 应用启动 | ✅ |
| `app_wide_test.dart` | 21 | 应用级 | ✅ |
| `data_sync_integration_test.dart` | 2 | 数据同步 | ✅ |
| `doris_integration_test.dart` | 41 | Doris 全功能 | ✅ |
| `ecommerce_to_test_db_sync_test.dart` | 3 | 数据同步 | ✅ |
| `export_backup_test.dart` | 8 | 导出/备份 | ✅ |
| `mongodb_integration_test.dart` | 62 | MongoDB 全功能 | ✅ |
| `mongodb_real_data_test.dart` | 44 | MongoDB 真实数据 | ✅ |
| `mysql_integration_test.dart` | 60 | MySQL 全功能 | ✅ |
| `postgresql_integration_test.dart` | 55 | PostgreSQL 全功能 | ✅ |
| `query_workflow_test.dart` | 3 | 查询工作流 | ✅ |
| `redis_integration_test.dart` | 66 | Redis 全功能 | ✅ |
| `redis_sidebar_menu_e2e_test.dart` | 42 | Redis 侧边栏菜单 E2E | ✅ |
| `redis_wave23_editors_e2e_test.dart` | 8 | Redis 二/三波编辑器与工作台（geo/stream/CONFIG/大 key/Lua） | ✅ |
| `results_display_test.dart` | 9 | 结果展示 | ✅ |
| `schema_diff_sync_test.dart` | 3 | Schema Diff | ✅ |
| `sidebar_tree_test.dart` | 8 | 侧边栏树 (含 015 滚动位置保持) | ✅ |
| `sqlserver_adapter_test.dart` | 51 | SQL Server 适配器 (含 SchemaAwareAdapter) | ✅ |
| `postgresql_adapter_test.dart` | 82 | PG 适配器 (含 SchemaAwareAdapter) | ✅ |
| `sqlite_integration_test.dart` | 65 | SQLite 全功能 | ✅ |
| `sqlite_nodes_context_menu_test.dart` | 18 | SQLite 节点右键菜单 | ✅ |
| `sqlserver_integration_test.dart` | 41 | SQL Server 全功能 | ✅ |
| `table_dialogs_test.dart` | 15 | 表操作对话框 | ✅ |
| `table_management_test.dart` | 3 | 表管理 | ✅ |
| `tdengine_integration_test.dart` | 37 | TDengine 全功能 | ✅ |
| `user_journey_test.dart` | 22 | 用户旅程 | ✅ |
| `workspace_integration_test.dart` | 7 | Workspace | ✅ |

### 19.2 集成测试配置速查

所有集成测试通过环境变量配置连接信息：
```bash
DBMASTER_MYSQL_HOST       DBMASTER_PG_HOST
DBMASTER_MONGO_HOST       DBMASTER_REDIS_HOST
DBMASTER_DORIS_HOST       DBMASTER_SQLSERVER_HOST
DBMASTER_TDENGINE_*       DBMASTER_ORACLE_*
```

### 19.3 🔴 缺失的集成测试

| # | 优先级 | 测试内容 |
|---|--------|---------|
| INT-AUTH-001 | P1 | Auth 系统集成测试（登录→API 调用→退出） |
| INT-SYNC-001 | P1 | DataSync 完整同步流程 |
| INT-TASK-001 | P1 | 后台任务完整执行流程 |

---

## 20. 端到端用户旅程测试 (E2E)

### 20.1 首次使用流程

| # | 用例 | 优先级 | 步骤 |
|---|------|--------|------|
| E2E-001 | 新用户首次体验 | P0 | 启动 → 欢迎屏幕 → 新建连接 → 连接成功 → 浏览数据库 → 执行第一条查询 |
| E2E-002 | Pro 购买流程 | P1 | 触发 Pro 功能 → 购买页面 → 完成购买 → Pro 功能解锁 |

### 20.2 日常使用流程

| # | 用例 | 优先级 | 步骤 |
|---|------|--------|------|
| E2E-003 | 多数据库查询 | P0 | 连接 MySQL → 查询 → 切换到 PostgreSQL → 查询 → 对比结果 |
| E2E-004 | AI 辅助查询 | P0 | 打开 AI 面板 → 输入自然语言问题 → AI 生成 SQL → 确认执行 → 查看结果 |
| E2E-005 | Schema Diff 工作流 | P1 | 连接两个数据库 → 运行 Schema Diff → 查看差异 → 生成同步脚本 |
| E2E-006 | 数据导入导出 | P1 | 查询结果 → 导出 CSV → 修改 → 导入到另一数据库 |
| E2E-007 | 多 Workspace 切换 | P0 | 打开 3 个 Workspace → 快速切换 → 每个 Workspace 状态独立 |

### 20.3 高级使用流程

| # | 用例 | 优先级 | 步骤 |
|---|------|--------|------|
| E2E-008 | ER 图生成 | P1 | 选择数据库 → 生成 ER 图 → 调整布局 → 导出图片 |
| E2E-009 | 查询优化工作流 | P1 | 执行慢查询 → 查看 EXPLAIN → 应用索引建议 → 重新执行对比 |
| E2E-010 | 存储过程开发 | P2 | 创建存储过程 → 编辑 → 执行测试 → 查看结果 |

---

## 21. 回归测试清单 (REG)

### 21.1 核心健康检查（每次提交）

```bash
flutter analyze lib/       # 0 warnings
flutter test               # ~3,087 用例全量通过
```

### 21.2 完整回归测试（每次发布）

```bash
# 1. 代码质量
flutter analyze
dart format --set-exit-if-changed lib/ test/

# 2. 单元测试全量
flutter test

# 3. 测试数据生成
python scripts/generate_test_data.py

# 4. 核心集成测试
flutter test integration_test/mysql_integration_test.dart
flutter test integration_test/postgresql_integration_test.dart
flutter test integration_test/sqlite_integration_test.dart
flutter test integration_test/workspace_integration_test.dart
flutter test integration_test/export_backup_test.dart
flutter test integration_test/schema_diff_sync_test.dart
flutter test integration_test/user_journey_test.dart

# 5. 可选集成测试（需外部服务）
flutter test integration_test/mongodb_integration_test.dart
flutter test integration_test/redis_integration_test.dart
# ... 其余集成测试
```

### 21.3 人工回归清单

| # | 用例 | 优先级 | 检查项 |
|---|------|--------|--------|
| REG-M001 | 暗色/亮色模式 | P0 | 所有面板主题一致 |
| REG-M002 | 6 种语言切换 | P0 | 主要界面无未翻译文本 |
| REG-M003 | 连接/查询 MySQL | P0 | 核心流程正常 |
| REG-M004 | 连接/查询 SQLite | P0 | 核心流程正常（无需外部服务） |
| REG-M005 | 快捷键 | P0 | F5/Ctrl+Enter/Ctrl+T/Ctrl+W |
| REG-M006 | 窗口缩放 | P1 | 最小→最大→自定义 |
| REG-M007 | 8 小时稳定性 | P1 | 无崩溃/内存泄漏/响应变慢 |

### 21.4 平台兼容性检查

| 平台 | 优先级 | 检查项 |
|------|--------|--------|
| macOS | P0 | 全功能、FFI (FreeTDS/SQLite)、菜单栏 |
| Windows | P0 | 全功能、FFI、注册表 |
| Linux | P1 | 核心功能、FFI |
| Web | P2 | SQL Server 存根生效、SharedPreferences 降级 |

---

## 附录 A: 测试文件完整索引

### 单元测试文件 (~140 个)

详见 `test/` 目录（~140 个测试文件）与各章节「自动化覆盖」标注。

### 集成测试文件 (25 个)

详见第 19 章。

### 手动测试文档 (已归档)

| 原文档 | 归档原因 |
|--------|---------|
| `app_wide_manual_test_cases.md` | 整合至第 2-14 章 |
| `*_manual_test_cases.md` (20+ 个) | 整合至第 5 章各数据库适配器 |
| `*_automated_test_cases.md` (12+ 个) | 整合至第 5 章各数据库适配器 |
| `ai_panel_manual_test_cases.md` | 整合至第 6 章 |
| `workspace_manual_test_cases.md` | 整合至第 15 章 |
| `er_diagram_manual_test_cases.md` | 整合至第 8 章 |
| `query_optimizer_manual_test_cases.md` | 整合至第 7 章 |
| `smart_import_manual_test_cases.md` | 整合至第 15 章 |
| `connection_management_manual_test_cases.md` | 整合至第 14 章 |
| `data_generation_manual_test_cases.md` | 整合至第 8 章 |
| `ssh_tunnel_manual_test_cases.md` | 整合至第 9 章 |
| `audit_log_manual_test_cases.md` | 整合至第 9 章 |
| `task_panel_manual_test_cases.md` | 整合至第 15 章 |
| `user_journey_test_cases.md` | 整合至第 20 章 |
| `UI_MANUAL_TEST_PLAN.md` | 整合至第 10-16 章 |
| `ui-redesign-test-spec.md` | 整合至第 10 章 |
| `automated_test_plan.md` | 整合至全文档 |
| `automated_test_report.md` | 整合至各章节状态标注 |
| `automated_test_supplement_plan.md` | 整合至各章节 🔴 待补充 |
| `task_test_supplement_p0p1p2.md` | 整合至各章节 |
| `guides/integration_test_authoring_guide.md` | 集成测试编写指南（移至 guides/） |

---

## 附录 B: 测试优先级定义

| 优先级 | 定义 | 通过标准 |
|--------|------|---------|
| P0 | 核心功能，阻塞发布 | 100% 通过 |
| P1 | 重要功能，影响用户体验 | 90% 以上通过 |
| P2 | 辅助功能，可延后 | 80% 以上通过 |
| P3 | 未来功能，仅跟踪 | 按需 |

---

---

## 附录 C: SQL Server 外部交付验收测试运行记录

**运行批次**: ss-handoff-20260715-001  
**被测产物**: `dist\Release\dbmaster.exe`  
**目标数据库**: SQL Server 2022 @ `192.168.x.x:1433` / `dbmaster_handoff_setup`  
**执行方式**: AI CLI 完成环境与数据准备；UI 交互用例需人工或外部自动化执行  
**参考文档**: 内部 SQL Server UI 功能测试报告  
**详细报告**: 内部测试运行记录（2026-07-15）  

### 环境准备状态

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Windows 构建产物 | 完成 | `dist\Release\dbmaster.exe` 存在 |
| 凭据读取 | 完成 | 从 `C:\Users\hobbs\Projects\dbmaster\test_db_server.txt` 读取，未记录密码 |
| SQL Server 网络可达 | 完成 | `192.168.x.x:1433` TCP 端口可达 |
| 独立测试库 | 完成 | `dbmaster_handoff_setup` 已创建，含 `t_types` / `p_echo` / `p_needparam` / `p_multi` |
| 应用启动 | 部分完成 | 进程已启动，窗口已捕获；但主窗口内容区域为空白，需进一步排查 |

### 用例覆盖与映射

| 外部用例 | 内部映射 | 优先级 | 当前状态 |
|----------|----------|--------|----------|
| TC-SS-EXE-001 / TC-SS-EXE-003 / TC-SS-EXE-004 | SS-EXEC-201/202/203 | P0 | PASS（Widget test） |
| TC-SS-EXE-002 | SS-EXEC-202 | P0 | PASS（ConnectionProvider Widget test） |
| TC-SS-EXE-005 | SS-EXEC-203 | P0 | PASS（Sidebar Widget test） |
| TC-SS-CON-001 ~ TC-SS-CON-003 | SS-DISC-201 | P1 | PASS（ConnectionProvider Widget test） |
| TC-SS-TYP-001 ~ TC-SS-TYP-003 | SS-DEC-201/202/203 | P1 | PASS（Widget test） |
| TC-SS-QRY-001 | 基线 | P1 | PASS（Widget test） |
| TC-SS-QRY-002 | SS-DDL-201 | P1 | PASS（Widget test） |
| TC-SS-QRY-003 | SS-SCRIPT-201 | P1 | PASS（Unit test） |
| TC-SS-QRY-004 | SS-SCRIPT-201 | P1 | PASS（Widget test） |
| TC-SS-BRW-001 | SS-BROWSE-201 | P1 | PASS（Sidebar Widget test） |
| TC-SS-BRW-002 | SS-BROWSE-201 / SqlSchemaAdapter | P1 | PASS（Sidebar Widget test） |
| TC-SS-CAP-001 | SS-PL-201 | P2 | PASS（Integration test against real SQL Server） |
| TC-SS-CAP-002 | SS-CH-201 | P2 | PASS（Integration test against real SQL Server） |
| TC-SS-CAP-003 | SS-SEQ-201 | P2 | PASS（Integration test against real SQL Server） |
| TC-SS-CAP-004 | SS-MV-201 | P2 | PASS（Integration test against real SQL Server） |
| TC-SS-CAP-005 | SS-REP-201 | P2 | PASS（Integration test against real SQL Server） |
| TC-SS-CAP-006 | SS-EXP-201 | P2 | PASS（Integration test against real SQL Server） |

### 自动化 Widget 测试覆盖

针对 UI 渲染不稳定、外部 GUI 自动化难以校准的问题，已新增 Widget 测试覆盖结果面板与 DDL 确认横幅行为：

| 文件 | 覆盖用例 | 状态 |
|------|----------|------|
| `test/organisms/results/sqlserver_results_widget_test.dart` | TC-SS-EXE-001 / TC-SS-EXE-003 / TC-SS-EXE-004 / TC-SS-QRY-001 / TC-SS-QRY-004 / TC-SS-TYP-001~003 | PASS |
| `test/organisms/results/sqlserver_ddl_banner_widget_test.dart` | TC-SS-QRY-002 | PASS |
| `test/providers/sqlserver_connection_provider_test.dart` | TC-SS-EXE-002 / TC-SS-CON-001~003 | PASS |
| `test/organisms/sidebar/sqlserver_sidebar_tree_test.dart` | TC-SS-EXE-005 / TC-SS-BRW-001 / TC-SS-BRW-002 | PASS |
| `test/utils/sql_server_batch_splitter_test.dart` | TC-SS-QRY-003 | PASS |
| `integration_test/sqlserver_capability_parity_test.dart` | TC-SS-CAP-001~006 | PASS |

### 注意与阻塞项

- **主窗口空白**: Release exe 在自动化环境下渲染不稳定；已改为 Widget 测试验证结果面板渲染，不直接驱动 exe。
- P0/P1 用例已全部通过 Widget/Unit 测试覆盖。
- P2 能力补全用例通过真实 SQL Server 集成测试全部覆盖。
- 当前测试共覆盖 24 个用例并全部 PASS。

## 附录：Feature 037 — 可操作错误 + Pro 试用额度（2026-07-19）

### TC-ERR 错误可操作化（US1/US2）

| 测试文件 | 用例 | 状态 |
|---|---|---|
| `test/utils/secret_redactor_test.dart` | TC-ERR-001 密钥脱敏（password/pwd/quoted/uri/bearer/apikey/sql） | PASS |
| `test/services/error_reporter_test.dart` | TC-ERR-002 捕获→中心、去重、detach | PASS |
| `test/organisms/actionable_error_test.dart` | TC-ERR-003 复制 / AI / Retry 按钮；复制写脱敏剪贴板 | PASS |
| `test/organisms/error_boundary_test.dart` | TC-ERR-004 `showErrorSnackBar` 复制 action 写脱敏剪贴板 | PASS |

### TC-CENTER 执行中心（US3）

| 测试文件 | 用例 | 状态 |
|---|---|---|
| `test/providers/execution_center_provider_test.dart` | TC-CENTER-001 LRU 上限 / 增删 / 清空 / toggle | PASS |
| `test/organisms/execution_center_panel_test.dart` | TC-CENTER-002 Tasks/Errors tab、错误列出、dismiss | PASS |

### TC-TRIAL 按功能试用额度（US4）

| 测试文件 | 用例 | 状态 |
|---|---|---|
| `test/services/trial/trial_quota_service_test.dart` | TC-TRIAL-001~007 消费/用尽/Pro 无限/幂等/退还/持久化/机器绑定/按功能独立 | PASS |
| `test/providers/trial_wiring_test.dart` | TC-TRIAL-008 `trySchemaDiffSync`/`tryDataImport` 经 AppProvider 全流程；Pro 不受限；跨实例持久化 | PASS |
| `test/providers/app_provider_gating_test.dart` | TC-GATE 回归：连接/Tab/AI 门禁不变 | PASS |
| `test/organisms/schema_diff/schema_sync_executor_test.dart` | TC-SDS 回归：Schema Sync 执行器渲染 | PASS |

### 说明
- 试用门禁为 pre-DB 逻辑，已由单元 + wiring 测试覆盖；Schema Sync 的 DB 部分沿用既有集成测试。
- 试用额度 R1：本机自签 + 机器码绑定；抗 casual/重装/跨机，清 app 数据会重置（离线约束）。

## 附录：C01a — UI 插件注册框架（2026-08-18）

> 框架基建测试（`lib/plugins/`：描述符 / 三接口 / AiSkill 占位 / 注册表 / bootstrap）。
> 纯框架通路验证，不涉真实数据库；业务行为归 C2（连接表单）/ C3（渲染器）/ C4（侧边栏）区块测试。

### PLG-REG 注册表与描述符（test/plugins/plugin_registry_test.dart）

| 用例 | 覆盖 | 状态 |
|---|---|---|
| PLG-REG-001 | descriptor.supports：空集=全类型 / 成员判定 / 按 id 相等 | PASS |
| PLG-REG-002 | 按类型查连接表单插件（无命中 null）与侧边栏插件（**多命中合并**，C14 语义） | PASS |
| PLG-REG-003 | 多插件命中同类型：取注册序首个且不抛 | PASS |
| PLG-REG-004 | id 冲突跨种类拒绝（全局 id 空间）；override: true 显式替换 | PASS |
| PLG-REG-005 | seal() 后注册抛 StateError（编译期注册边界） | PASS |
| PLG-REG-006 | 渲染器查询：按形态 / 类型+形态组合 / 全类型通用件不过滤 | PASS |
| PLG-REG-007 | descriptorById 徽章反查；AiSkill 注册列举与 envelope 形态 | PASS |

### PLG-IF 接口契约与会话生命周期（test/plugins/plugin_interfaces_test.dart）

| 用例 | 覆盖 | 状态 |
|---|---|---|
| PLG-IF-001 | 表单会话 createSession→build→collect→dispose 全链路（copyWith 合并语义） | PASS |
| PLG-IF-002 | 同一插件多会话互不共享状态（插件本体无状态） | PASS |
| PLG-IF-003 | ConnectionDraft 桥：宿主推新值对会话 collect 可见 | PASS |
| PLG-IF-004 | 判等陷阱守卫：DbServer 同 id copyWith == 相等，draft.update 仍生效并通知 | PASS |
| PLG-IF-005 | 侧边栏 capabilityGroups 元数据：分组 + capabilityId 仅作 port 查询键 | PASS |
| PLG-IF-006 | 渲染器 build 消费 ResultRenderContext（ExecutionResult 载体） | PASS |

### 说明
- ConnectionDraft（PLG-IF-004）是设计决策守卫：DbServer 只按 id 判等，ValueNotifier 会静默丢弃 copyWith 新值，故草稿桥用强制赋值 + 总是通知。
- bootstrap 默认注册 = C08 连接表单八件 + C14-C20 侧边栏十件 + C11 结果渲染器三件（注册接线用例见各任务附录 PLG-C08-001 / PLG-C11-009）；`defaultPluginRegistry` 创建即注册保证 e2e 不经 main() 也能取到默认件。

## 附录：C08 — per-type 连接表单（2026-08-19）

**自动化**: `test/organisms/connection/forms/connection_forms_test.dart`（13 用例）+ 存量 `mongodb_connection_form_test.dart` 11 用例适配新壳全绿

| # | 用例 | 结果 |
|---|------|------|
| PLG-C08-001 | 注册分发：8 类型各命中专属插件、SS 无命中（C20 前走壳内兜底） | PASS |
| PLG-C08-002 | MySQL 编辑回填 + collect 往返无损（charset/timezone/timeout） | PASS |
| PLG-C08-003 | forSave 密码语义：测试连接恒携带 / 保存受「保存密码」开关约束 | PASS |
| PLG-C08-004 | SQLite：host=路径、port=0、readOnly 一等字段；空路径 collect 拦截 | PASS |
| PLG-C08-005 | Redis 三态回填（ACL/仅密码/无认证）+ collect 凭据语义 | PASS |
| PLG-C08-006 | Redis db index：'db2' 回填还原 '2'，collect 写回纯数字（database 字段承载） | PASS |
| PLG-C08-007 | TDengine 超时镜像 extra['timeout']（adapter 实际消费键） | PASS |
| PLG-C08-008 | Mongo replicaSet extra 三键（ConnectionExtraKeys 常量）+ direct null 向后兼容 | PASS |
| PLG-C08-009 | Mongo advanced：URI 凭据剥离（FR-007 无 @）+ host/port 派生首节点 | PASS |
| PLG-C08-010 | 壳 widget：类型导航切换 → 端口默认值 + 插件徽章跟随（mysql→pg→ss 兜底） | PASS |
| PLG-C08-011 | 壳 widget：编辑态类型导航禁用——点其他类型不切换表单（类型=既有连接固有属性） | PASS |

**人工测试用例**:

| # | 用例 | 优先级 | 步骤摘要 | 预期结果 | 结果 |
|---|------|--------|---------|---------|------|
| C-CONN-001 | C08 连接对话框走查 | P0 | 新建连接：逐类型点左栏导航（9 类型），对照原型 connection-*.html；再编辑一条既有连接尝试点导航 | 右侧表单随类型切换且字段集正确；MySQL/Doris 高级含 charset/timezone；Redis 三态认证 + db index；Mongo 四模式；TD/CH 无 SSL/SSH/Token/HTTP 死字段；SS 走通用表单。**编辑态：类型导航禁用（不可点击、非当前项置灰），点其他类型无反应** | **PASS（2026-08-19 用户桌面走查通过）** |
| C-CONN-002 | 连接往返编辑真库走查 | P0 | 对 192.168.x.x 各类型建连接→保存→重开编辑 | 字段无损回填；测试连接通过；保存后侧栏可连 | **PASS（2026-08-19 用户真库走查通过）** |

## 附录：C10 — port 化连接语义（2026-08-19）

**自动化**: `test/services/ports/` 三文件 40 用例全绿。C2 代码侧收口件——连接对话框的测试/保存经 `DbCapabilityPort` 双形态（AdapterBacking 本地直连 / GatewayBacking 网关），能力真值表随附守卫。

### PORT-CAP 能力真值表（test/services/ports/capability_table_test.dart）

| # | 用例 | 结果 |
|---|------|------|
| PORT-CAP-001 | §3.5.1 等价守卫：17 个收编 getter ↔ 能力位逐格等价（c04 §12.2 事实源，防三源漂移） | PASS |
| PORT-CAP-002 | 派生 getter 语义：isSqlLike ≡ sql.query、isNoSQL/isSchemaLess ≡ 补集、programmableObjects = 五位之或 | PASS |
| PORT-CAP-003 | §3.2 marker 位取值（tx/ddl/script 同集、process.list 含 pg、process.kill 排除 ss 等） | PASS |
| PORT-CAP-004 | §3.3 DS 分支位（server.users/engine.status 仅 my、通用位全类型、query.explain=SQL 七类） | PASS |
| PORT-CAP-005 | §3.4 非 SQL 专有位（redis.*/mongo.*/td.* 精确类型集、ch.dictionary 恒 false） | PASS |
| PORT-CAP-006 | 键空间 lint：位 id 形如 <域>.<名>（多段名合法）且域在注册表内；未知 id 恒 false；of/has 自洽 | PASS |

### PORT-ADP AdapterBacking（test/services/ports/adapter_backing_test.dart）

| # | 用例 | 结果 |
|---|------|------|
| PORT-ADP-001 | testConnection 透传 DatabaseService 的 String? 语义（null=成功 / 错误串原样） | PASS |
| PORT-ADP-002 | persistConnection 本地 no-op 返回原 id；removeConnection no-op | PASS |
| PORT-ADP-003 | connectionState：directAdapter + 本地连接表 readOnly 反查（查无退化 false） | PASS |
| PORT-ADP-004 | 能力位委托真值表；Tier 1/流式执行抛 UnimplementedError（C13/C14 占位） | PASS |

### PORT-GWY GatewayBacking（test/services/ports/gateway_backing_test.dart）

| # | 用例 | 结果 |
|---|------|------|
| PORT-GWY-001 | test 请求形状：/api/gw/connections/test + Bearer + camelCase 草稿体（host/port/username/password/defaultDatabase） | PASS |
| PORT-GWY-002 | sqlite 草稿体仅 filePath（客户端 host=路径的 wire 映射） | PASS |
| PORT-GWY-003 | 连接失败也是 HTTP 200：{ok:false,error} → 失败结果（非异常） | PASS |
| PORT-GWY-004 | wire 错误映射：400 UNSUPPORTED_DB_TYPE / 401 UNAUTHORIZED / 未连接 CONFIG → PortException(code) | PASS |
| PORT-GWY-005 | 非网关类型（redis）本地即拒 UNSUPPORTED_DB_TYPE，零 HTTP 调用 | PASS |
| PORT-GWY-006 | **embedded 与远程两形态行为一致**：同路径/头/体，仅 baseUrl 不同（token 来自各自会话） | PASS |
| PORT-GWY-007 | persistConnection：草稿体+name/readOnly、charset/timezone 空省略；缺 serverConnId → DB_ERROR | PASS |
| PORT-GWY-008 | removeConnection：DELETE {id} 204 幂等；服务端错误 → PortException | PASS |
| PORT-GWY-009 | connectionState：embeddedServer/remoteServer 形态 + 注册表 readOnly 反查（列表失败退化 false） | PASS |
| PORT-GWY-010 | 路由：T28 前 9 类型全部 AdapterBacking（迁移协调矩阵编译期落点） | PASS |

**说明**
- 测试经 ServerConnection 单例两形态注入（connectEmbedded 握手 / connect 全程 login + fake storage），无真实 server 进程；真库联调归 T28 竖切窗口。
- ConnectionProvider 接线（testConnection/saveConnection/deleteConnection 经 port）由既有连接链路测试回归覆盖（dialog/forms/app_provider/editor/sidebar 借道用例全绿）。

## 附录：C14 — 侧边栏能力菜单框架（2026-08-19）

**自动化**: `test/organisms/sidebar/capability/capability_menu_assembly_test.dart`（7 用例）+ `sidebar_capability_menu_test.dart`（6 用例）+ `plugin_registry_test.dart` 多命中查询改写

| # | 用例 | 结果 |
|---|------|------|
| CAP-MENU-001 | port 门控：位取 false / 未知位隐藏、null 位无条件展示 | PASS |
| CAP-MENU-002 | 组内全部门控掉 → 整组隐藏（空组不出现在装配结果） | PASS |
| CAP-MENU-003 | 跨插件同组 id 合并；同项 id 后者覆盖前者（per-type 盖 core 语义） | PASS |
| CAP-MENU-004 | 徽章文本解析：core / `<type>`-plugin / ai-plugin | PASS |
| CAP-MENU-005 | core 插件 × 能力真值表：mysql 全项 / redis 只剩通用位 / sqlite 对象组整组消失 | PASS |
| CAP-MENU-006 | core 插件 buildObjectTree 恒空（树分缝回退契约，C19 删旧路径的依赖） | PASS |
| CAP-MENU-012 | 活动连接锚定：currentServer 优先 / 回退活动 tab→侧栏选中（须已连接，动作假定活连接） | PASS |
| CAP-MENU-007 | widget：无活动连接 → 整段隐藏 | PASS |
| CAP-MENU-008 | widget：mysql 分组+项+core 徽章+AI 高亮渲染 | PASS |
| CAP-MENU-009 | widget：redis 门控后对象组消失（真值表经 port 生效于 UI） | PASS |
| CAP-MENU-010 | widget：点击 AI Assistant 激活 onActivate（AI 面板开合） | PASS |
| CAP-MENU-011 | widget：折叠态点头部隐藏项、保留段头 | PASS |
| CAP-MENU-013 | widget：回退锚定下选中节点未连接 → 菜单仍隐藏 | PASS |

**真库 E2E**（`integration_test/c14_capability_menu_procedures_e2e_test.dart`，MySQL @192.168.x.x）：

| # | 用例 | 结果 |
|---|------|------|
| CAP-MENU-E2E-001 | 用户点击路径（connectToServer → changeDatabase → 显式目标库查询）返回该库存储过程（含 PARAMETERS 参数）与函数（含返回类型/参数）；一次性库 `dbmaster_c14_e2e` 建/清 | PASS |

**C14 期间连带修复（存量缺陷，用户真机报告触发）**：`StoredProcedureService` 的 `PARAMETER_COUNT` 列在 MySQL `information_schema.ROUTINES` 中不存在（error 1054）且被 catch-吞错返回空列表 → 存储过程对话框自诞生起恒空。修复 = 删该列（本就无人消费）+ 列序前移 + 错误上抛（对话框 loadFailed 错误路径复活）+ `database` 显式参数（不依赖连接会话 USE 状态——网关优先浏览/多连接形态下 DATABASE() 不可靠）；`sidebar_widget` 既有入口与能力菜单入口同修。单测 3 件跟进（列序/上抛语义）。

**说明**
- 装配测试的 port 用两类 fake：canned map（门控语义）+ CapabilityTable 委托（core 插件内容 × 真值表面，防表漂移）。

## 附录：C15 — MySQL/PG 侧边栏插件（首批 per-type SidebarPlugin，2026-08-19）

**自动化**: `test/organisms/sidebar/plugins/mysql_sidebar_plugin_test.dart`（5）+ `postgresql_sidebar_plugin_test.dart`（8，改写自原 postgresql_tree_builder_test）+ `capability/process_manager_dialog_test.dart`（4）+ 既有 capability/assembly/plugins 套件接口跟进（52 项全绿）

| # | 用例 | 结果 |
|---|------|------|
| SB-PLG-001 | MY buildGlobalTree 三节点（Server/Performance/Users） | PASS |
| SB-PLG-002 | MY Performance 展开：刷新间隔选择器渲染 + 进程按需加载不崩溃 | PASS |
| SB-PLG-003 | MY capabilityGroups：advanced 组 process.kill + engine.status（能力键=id，port 门控键） | PASS |
| SB-PLG-004 | MY descriptor：类型限定 mysql + databaseType 来源徽章 | PASS |
| SB-PLG-005 | MY buildDatabaseTree 恒空（分缝回退契约：库级走通用装配至 C19） | PASS |
| SB-PLG-006 | PG buildDatabaseTree 渲染 schema 节点 | PASS |
| SB-PLG-007 | PG schema 展开 → 七对象分类（Tables/Views/MatViews/Functions/Procedures/Sequences/Triggers） | PASS |
| SB-PLG-008 | PG tables 分类展开渲染表叶子 | PASS |
| SB-PLG-009 | PG 表展开渲染扁平交互式列叶子（列+索引/FK 分割线） | PASS |
| SB-PLG-010 | PG 库级树搜索过滤（schema 名与对象名双命中） | PASS |
| SB-PLG-011 | PG 空 schema 库返回 No Data 叶子（恒非空 = 恒接管分缝） | PASS |
| SB-PLG-012 | PG buildGlobalTree 三节点（Server/Process List/Users） | PASS |
| SB-PLG-013 | PG capabilityGroups：advanced 组 process.kill（Terminate） | PASS |
| SB-PLG-014 | 进程管理对话框：loader 归一化行渲染 + 慢进程高亮路径 | PASS |
| SB-PLG-015 | 进程管理对话框：空列表空态 / loader 抛错错误态（不静默空列表） | PASS |
| SB-PLG-016 | 进程管理对话框：Kill 确认 → onKill 调用 + 成功反馈 + 刷新 | PASS |

**接口演进（既有用例改写）**：`SidebarPlugin.buildObjectTree` 拆两级（buildGlobalTree/buildDatabaseTree，新增 SidebarDatabaseTreeContext 全量载荷）——CAP-MENU-006 改写为「core 插件两级树恒空」；fakes/assembly 测试同步。旧 `builders/mysql_tree_builder.dart`(517 行)/`postgresql_tree_builder.dart`(1,258 行) 删除，代码整体迁入插件（行为逐行保持，除迁移时清除 2 个死变量）。

**真库 E2E**（`integration_test/c15_sidebar_plugins_e2e_test.dart`，MY/PG @192.168.x.x，全只读断言）：

| # | 用例 | 结果 |
|---|------|------|
| SB-PLG-E2E-001 | MY 插件全局树：连接展开后 Server/Performance/Users 渲染（树分缝 → buildGlobalTree） | PASS |
| SB-PLG-E2E-002 | MY process.kill 项激活 → 进程管理对话框列出真进程（SHOW PROCESSLIST） | PASS |
| SB-PLG-E2E-003 | MY engine.status 项激活 → Engine Status 对话框打开（真 SHOW ENGINE INNODB STATUS） | PASS |
| SB-PLG-E2E-004 | PG 插件库级树：schema 层 + Tables 分类渲染、分类默认收起（分缝 → buildDatabaseTree） | PASS |
| SB-PLG-E2E-005 | PG process.kill 项激活 → 对话框列出 pg_stat_activity 会话（loader 不排自身，与 MySQL SHOW PROCESSLIST 语义一致） | PASS |

**存量金标准回归（同日）**：`postgresql_sidebar_menu_e2e`（64 用例）**全绿**——插件接管的 PG 库级树/schema/表展开/全部菜单路径真库验证；`mysql_sidebar_menu_e2e` 74/84 过（树/库/表/列/索引/FK/视图/过程/触发器/Server 全局全过）。

**C15 期间连带修复（存量断裂，master 干净仓复现证实非 C15 引入）**：
- **7 个挂 SidebarTree 的 e2e harness 缺 `Provider<ServerConnectionProvider>`**——树内连接状态点（server-platform M1 起）watch 该 provider，缺供即整树 ProviderNotFoundException，**全套件自 M1 起不可运行**（此前无人发现：unified_test_spec 的 PASS 记录早于 M1）。修复 = mysql/pg/redis×2/sqlserver/sidebar_tree/doris-helpers 七处 harness 补供断开态实例。
- 修复后 mysql 金标准暴露 **10 个存量失败**（Performance/Users 全局簇 tap 未命中 + connect 簇第二连接卡片不渲染）：在干净 master + 仅 harness 修复的对照 worktree 上**逐簇复现同构**，确认为存量漂移（疑共享库库列表变长致全局节点低于视口 + 连接卡片渲染 flake），登记待修——不阻塞 C15（行为等价性由代码逐行迁移 + 74/84 金标准 + 专项 E2E 共同锚定）。
- **`defaultPluginRegistry` 改为创建即注册默认件**（bootstrap.dart）：e2e/集成测试自建 widget 树不经 main()，树分缝后 MySQL/PG 树由插件提供，空注册表 = 树消失（C15 E2E 首轮 +2/-83 的根因）。main() 仅保留 seal()；对 defaultPluginRegistry 重复调用 registerDefaultUiPlugins 会 id 冲突 fail-loud（测试侧三处调用点已清）。
- 树分缝（sidebar_tree `_buildDatabaseObjectsOrSchemaAware` 顶部插件优先）无独立用例——core 插件树恒空即回退路径，C15 首个 per-type 插件落地时随真库 E2E 补。

## 附录：C19 — 旧框架下线（泛 SQL 共享树收编 core + 键盘导航 key 契约统一，2026-08-19）

**自动化用例**（`test/organisms/sidebar/plugins/generic_sql_database_tree_test.dart` + `sidebar_controller_test.dart` + `capability_table_test.dart` + `sql_escape_test.dart`）：

| # | 用例 | 结果 |
|---|------|------|
| SB-PLG-055 | MySQL 全五分类渲染（Tables/Views/Stored Procedures/Triggers/Events + 表/触发器叶子） | PASS |
| SB-PLG-056 | Doris MV 分类渲染；triggers/events 能力位裁剪（数据误有不渲染） | PASS |
| SB-PLG-057 | ClickHouse 走共享树；procedures 能力位裁剪 | PASS |
| SB-PLG-058 | SS 与非 SQL 类型返回空（SS 走宿主 legacy 分支至 C20；Mongo/Redis 插件接管） | PASS |
| SB-PLG-059 | 搜索过滤：表名命中 + Views (1) 计数 | PASS |
| SB-PLG-060 | 分类头菜单路由分类语义（tables=(true,null)/views=(false,'view')/MV=(false,'materialized_view')/procedures=(false,null)） | PASS |
| SB-PLG-061 | 视图/MV 叶子菜单透传 isMaterializedView | PASS |
| SB-PLG-062 | 过程叶子菜单透传 isFunction（函数折入语义保持） | PASS |
| CAP-MENU-006R | core 插件：全局树恒空 + 库级树 = 泛 SQL 共享兜底（C19 反转契约改写） | PASS |
| KB-NAV-001 | → 展开已缓存 db: 节点存裸 key「cid:db」（双格式 bug 回归守卫） | PASS |
| KB-NAV-002 | type-to-select 多字符无匹配退化为单字符重试（修复「不重试」） | PASS |
| KB-NAV-003 | PG schema 函数叶子 key = func: 前缀（与 Enter 处理器/树内选中态统一） | PASS |
| KB-NAV-004 | visible keys 全裸 key 契约（saved_queries/db/分类/schema/sqlite 六类 membership 改裸后鼠标展开的子节点进入键盘导航） | PASS |
| PORT-CAP-C19 | ddl.createDatabase={my,pg,do,td,ss} / pg.serverSearch={pg} / createTableMenuAction 等价守卫 / 树形态 getter | PASS |
| ESC-C19 | escapeQualifiedIdentifier 方言分发（PG 双引号/SS 方括号内嵌]双写/MySQL+null 反引号） | PASS |

**关键契约变更（既有用例改写）**：树分缝遍历序反转（per-type 先、core 殿后——仅树装配两处，能力菜单装配序不动）；`_buildDatabaseObjectsOrSchemaAware`/`_buildDatabaseObjects`/trigger+event 菜单五件删除（迁 `capability/generic_sql_database_tree.dart`）；`SidebarDatabaseTreeContext` 菜单回调扩参（onShowCategoryMenu+offerCreateTable/categoryType、onShowViewMenu+isMaterializedView、onShowProcedureMenu+isFunction、onShowTableMenu→Future）；sidebar 宿主三文件 `DatabaseType.` 字面量清零（仅剩 SS legacy 两处至 C20）。

**键盘导航 key 契约（C19 定版）**：可见节点 key 带导航前缀（`conn:`/`db:`/`cat:`/`schema:`/`table:`/`view:`/`proc:`/`func:`/`fn→func 统一`）；展开集合（expandedItems/Databases/Tables）一律存裸 key（`cid:…` 起点）。修复 P3 三 bug：db:/cid:db 双格式（键盘存前缀式致树不认+prune 误判+visible keys 查前缀式致鼠标展开子节点不进导航）、fn:/func: 不一致（Enter 失效）、type-to-select 不重试。controller cat:/schema: 键盘分支同步剥前缀。

**人工测试用例**:

| # | 用例 | 优先级 | 步骤摘要 | 预期结果 | 结果 |
|---|------|--------|---------|---------|------|
| C-SIDEBAR-001 | C14 能力菜单框架走查 | P0 | 连一条 MySQL 与一条 Redis（192.168.x.x 或本地 SQLite），展开侧边栏至连接成功；观察树下方新「能力」段；点头部折叠/展开；对照原型 sidebar-capability-menu.html | MySQL：数据库对象组（存储过程/函数/触发器）+ 高级组（Schema 对比/AI 助手高亮）+ core 徽章；Redis：对象组整组消失、高级组仍在；点 AI 助手开合 AI 面板；点存储过程/触发器打开对应对话框；无连接时整段隐藏 | **PASS（2026-08-19 用户走查通过）** |
| C-SIDEBAR-002 | C15 MySQL/PG 树插件化走查 | P0 | 连 MySQL：展开连接看 Server/Performance/Users 三全局节点与迁移前一致；能力菜单「高级」组出现终止查询/引擎状态（mysql-plugin 徽章）；点终止查询开进程管理对话框（≥自身会话，慢进程红高亮，Kill 有确认+反馈）；点引擎状态开 InnoDB 对话框。切 PG：库下 schema/七分类/Extensions 树一致；高级组出现终止查询（postgresql-plugin 徽章）；对话框列出 pg_stat_activity 会话。随手右键树节点确认菜单不变 | 三全局节点/schema 树/右键菜单与迁移前逐项一致（回归面零变化）；两个新能力项 + 进程管理对话框按预期工作 | **PASS（2026-08-19 用户走查通过，C15 收口）** |
| C-SIDEBAR-003 | C16 SQLite 树插件化走查 | P0 | 连一条本地 SQLite：展开连接看 Tables/Views/Indexes/Triggers/Database Info 扁平结构（单库无 main 头）；展开 Tables 看表叶子（列数徽章/收藏星标）与表展开列徽章（PK/NOT NULL/DEFAULT）；右键表/Tables 头/Database Info 对照菜单项（Browse Data/Copy CREATE/Save As…/VACUUM 等）；能力菜单「高级」组出现 Attach Database… 与 PRAGMA Explorer（sqlite-plugin 徽章）；点 PRAGMA Explorer 打开面板；ATTACH 第二个 .db 后树切多库 header 形态 | 扁平结构/分类头/右键菜单与迁移前逐项一致（回归面零变化）；两个新能力项工作；多库 header 渲染（附加库子树内容存在登记的存量元数据缺陷，结构正确） | **PASS（2026-08-19 用户确认「没有问题」，C16 收口）** |
| C-SIDEBAR-004 | C17 MongoDB/Redis 树插件化走查 | P0 | 连一条 Redis（192.168.x.x）：展开连接看逻辑库节点（badge=key 数）+ 全局节点（Server/Replication/Memory/Stats/Clients/Config/Slow Log/Functions/Workbench/Lua/Pipeline/Transaction/Keyspace Notifications/ACL/Pub/Sub）与迁移前一致；展开某库看 Keys/Namespaces/Expiring Soon/DB Info 四分类；右键库对照菜单（Select DB/Refresh/New Key/Flush DB）；能力菜单出现「键空间」组（新建键）+「高级」组 9 面板项（redis-plugin 徽章，点 Workbench/编辑配置开面板/对话框）。切 MongoDB：展开连接看 Server/Replication/Sharding 三全局节点；展开库看 Collections/Views/GridFS Buckets；展开集合看 Document Schema 与 Indexes（属性徽章）；右键集合 Validation Rules 打开真查看器（无 validator 集合显示未配置态）；双击集合开 find() 查询 tab | Redis 整树/全局节点/库展开四分类/右键菜单与迁移前逐项一致（回归面零变化）；能力菜单两组工作；Mongo 两级树 + 验证规则真查看器按预期 | **PASS（2026-08-19 用户走查通过，C17 收口）** |
| C-SIDEBAR-005 | C18 Doris 树插件化 + TDengine 树插件化走查（CH 共享路径一并扫） | P0 | 连一条 Doris（192.168.x.x:9030 remote_user）：展开连接看 Server/Performance 两全局节点与迁移前一致（无 Users 节点）；展开 Server 看 Doris 版本（version_comment）+ enable_feature_binlog 叶子；展开 Performance 看进程列表（间隔选择器 5s/10s/30s/Off、慢进程红高亮；**列错位修复后进程行应正常显示 [Id] User • Command • Time**）；右键进程 Copy Query/Kill Query；能力菜单「高级」组出现终止查询（doris-plugin 徽章）→ 点开进程管理对话框列真进程；展开任一库看 Tables/Views/Materialized Views 分类（泛 SQL 共享路径）。若有 TDengine 凭据（192.168.x.x:6041，**当前未知——待用户提供**）：展开库看 SuperTables 分类（badge=超表数）→ 展开超级表看 Columns/Tags 分组与列徽章 [PK]；双击超级表开 SELECT … LIMIT 100 查询 tab；右键对照 Browse Data/Delete SuperTable（红，确认文案警告连带删子表）；右键库看 Create SuperTable。ClickHouse：连一条 CH（9004，需网关在线）扫共享对象树分类与表菜单 | Doris 两全局节点/版本叶子/进程列表（修复后行对齐）/库级分类与迁移前一致（回归面零变化）；TD SuperTables 树/双击浏览/右键菜单按预期；CH 共享路径可用 | **PASS（2026-08-19 用户走查通过，C18 收口；TD 真库凭据仍待补——TD 树行为由 tdengine_sidebar_plugin 单测 7 例锚定，凭据到位后补真库验证）** |
| C-SIDEBAR-006 | C19 旧框架下线走查（泛 SQL 共享树 + 键盘导航修复） | P0 | 连一条 MySQL（192.168.x.x）：展开连接→展开库，确认 Tables/Views/Stored Procedures/Triggers/Events 分类与此前完全一致（分类头计数/表叶子行数徽章/拖拽手感）；右键 Tables 头看 Create Table + Refresh、右键 Views 头看 Create View、右键 MV 头（若有）看 Create Materialized View、右键表对照完整菜单（Data Sync/AI 分析/引擎状态/重命名/截断/删除）。连 Doris：库级 Tables/Views/Materialized Views 分类一致。键盘：↑↓ 导航选中库节点按 → ——**树应实际展开**（修复前键盘展开无视觉效果）；再按 ← 收起；导航到 PG schema 函数叶子按 Enter ——应开 SELECT 查询 tab（修复前 fn: 键无响应）；在树上快速输入「xy」类无匹配前缀后再输单字符 ——选中态应跳到单字符首个匹配（修复前纹丝不动）。连接右键菜单 Create Database 仍在（MY/PG/DO/TD/SS）；库右键 Create Table（MY）/Create SuperTable（TD，若有凭据）仍在 | 泛 SQL 分类树/全部右键菜单与迁移前逐项一致（回归面零变化——共享路径只是换实现不改行为）；三个键盘修复各自生效；门控项类型集不变 | **PASS（2026-08-19 用户走查通过，C19 收口）** |
| C-SIDEBAR-007 | C20 SQL Server 树插件化 + T28 网关壳走查（#30 结案用户面） | P0 | 前置：embedded server 随包（exe 同目录 dbmaster-server.exe 或 DBMASTER_SERVER_BIN）。连一条 SS（192.168.x.x:1433 sa）：展开连接看 Server Status / Process List / Users 三全局节点与迁移前一致（标签仍硬编码英文——沿旧行为）；展开 Server Status 看 @@VERSION/Edition/连接数叶子；展开 Users 右键 sql_login 仅 Copy Name；展开库看 schema-first 树（schema 计数徽章 → Tables/Views/Stored Procedures/Functions 分类；无 Triggers 节点）；双击表开 SELECT TOP 100 tab、双击过程开 EXEC [schema].[proc]; tab；右键表/视图/过程对照菜单（Browse/Copy/Drop）。查询执行：编辑器跑 SELECT 确认走网关（结果正常）；长查询超时行为（若验证：WAITFOR 60s + 连接 timeout 30s → 应报 [TIMEOUT] 错误而非静默成功——FFI 版缺陷不复现）。事务按钮应不可见（网关 v1 不支持手动事务）；执行计划入口应报「暂不支持」明确错误 | SS 三全局节点/schema 树/右键菜单与迁移前逐项一致（回归面零变化）；查询经网关正常返回；超时报错不静默成功；事务入口降级隐藏 | **PASS（2026-08-20 用户走查通过，C20/C4 收口）** |
## 附录：C11 — 渲染器注册化（2026-08-20）

**自动化**: `test/organisms/results/result_renderer_plugins_test.dart`（12 用例）+ `results_view_mode_test.dart` 改写（6 用例：4 个 widget 切换回归 + 2 个注册表断言）。行为保持重构——切换条视觉/交互零变化，模式集合来源从硬编码三分支改为注册表；`ResultViewMode` 枚举删除（viewModeId 字符串替代，命名对齐原枚举名）。

### PLG-C11 渲染器插件（test/organisms/results/result_renderer_plugins_test.dart）

| # | 用例 | 结果 |
|---|------|------|
| PLG-C11-001 | viewModeId 与原 ResultViewMode 枚举名逐一对齐（table/chart/card） | PASS |
| PLG-C11-002 | chart/card 仅声明 sqlRows；table 兼声明 nosqlDocument/redisKeyValue（C12 起三形态兜底） | PASS |
| PLG-C11-003 | descriptor：core 来源 + 空类型集（全类型通用件）+ id 互异（全局 id 空间） | PASS |
| PLG-C11-004 | descriptor displayName 消费既有 viewMode* l10n 键（en 值锁定 Table/Chart/Card，文案零变化） | PASS |
| PLG-C11-005 | table 渲染器 → VirtualizedDataTable（无交互桥亦可构建） | PASS |
| PLG-C11-006 | chart 渲染器 → ChartView（columnTypes + AI 趋势回调经 renderContext 透传） | PASS |
| PLG-C11-007 | card 渲染器 → CardView | PASS |
| PLG-C11-008 | 表格交互桥逐项转发：filterService 同实例 / columns / rows / columnTypes / 过滤与排序回调经桥可触发 | PASS |
| PLG-C11-009 | registerDefaultUiPlugins 注册三渲染器（独立 registry，注册序 table→chart→card = 默认视图序） | PASS |
| PLG-C11-010 | defaultPluginRegistry 同样就位（e2e/单测不经 main() 也能取到——C15 教训守卫） | PASS |
| PLG-C11-011 | 形态过滤：nosqlDocument / redisKeyValue 命中 C12 渲染器（详单测见 C12 附录） | PASS |
| PLG-C11-012 | 类型过滤：空类型集渲染器对任意类型（含 mongodb）命中 | PASS |

### 宿主切换回归（test/organisms/results/results_view_mode_test.dart 改写）

| # | 用例 | 结果 |
|---|------|------|
| PLG-C11-101 | 默认渲染表格视图，切换条三 label 可见（Table/Chart/Card，经 descriptor.displayName） | PASS |
| PLG-C11-102 | 切 Card → CardView 出现、表格消失；再切回 Table 表格恢复 | PASS |
| PLG-C11-103 | 切 Chart → ChartView 出现、表格消失 | PASS |
| PLG-C11-104 | 注册表断言：默认注册含 table/chart/card、注册序首个 = table（默认视图） | PASS |

**说明**
- 宿主 `_viewModeId` 为可空字符串（null = 取注册序首个渲染器），已选 id 不在适用列表时自愈回退首个，不抛错。
- 表格交互面（过滤/排序/单元格编辑/右键/JSON 双击）全部保留在宿主 state，经 `TableViewInteraction` 桥下发——渲染器无状态，切走再切回交互恢复。
- 无独立人工走查项：行为保持重构、切换条视觉零变化；C12 NoSQL 渲染器走查项见 C-RSLT-001。

## 附录：C12 — NoSQL 文档 / Redis 键值渲染器（2026-08-20）

**自动化**: `test/organisms/results/result_renderer_c12_test.dart`（新，19 用例）+ `results_view_mode_test.dart` 增 C12 组（3 用例）+ `result_renderer_plugins_test.dart` 两断言随形态扩展改写。三新渲染器：`document`（文档卡片，nosqlDocument）/ `jsonTree`（JSON 树，nosqlDocument+redisKeyValue）/ `keyValue`（键值卡，redisKeyValue）；注册序 document→keyValue→jsonTree→table…（jsonTree 双形态声明必须在两个专有卡之后，否则抢默认视图）。形态判定：`ExecutionResult.dataShape`（DatabaseService 按连接类型暂存 `lastDataShape`，Mongo→nosqlDocument / Redis→redisKeyValue / SQL 家族→sqlRows；null=历史结果回退 sqlRows）。

### PLG-C12 渲染器与形态判定（result_renderer_c12_test.dart）

| # | 用例 | 结果 |
|---|------|------|
| PLG-C12-001 | viewModeId 对齐 c03 §4 命名表（document/jsonTree/keyValue） | PASS |
| PLG-C12-002 | 形态声明：document→nosqlDocument；jsonTree→双形态；keyValue→redisKeyValue | PASS |
| PLG-C12-003 | descriptor：core 来源 + 空类型集 + id 全局唯一（含 table 共 4 件互异） | PASS |
| PLG-C12-004 | displayName 消费新 viewMode* l10n 键（en 值锁定 Documents/JSON Tree/Key-Value） | PASS |
| PLG-C12-005 | 注册序：nosqlDocument → [document, jsonTree, table]（document 默认 + 表格兜底可切） | PASS |
| PLG-C12-006 | 注册序：redisKeyValue → [keyValue, jsonTree, table] | PASS |
| PLG-C12-007 | 注册序：sqlRows 不变 [table, chart, card]（C11 行为保持） | PASS |
| PLG-C12-008 | shapeForDatabaseType 九类型映射（mongo→nosqlDocument、redis→redisKeyValue、SQL 七类→sqlRows） | PASS |
| PLG-C12-009 | ExecutionResult.dataShape toJson/fromJson 往返 | PASS |
| PLG-C12-010 | 历史记录无 dataShape → null（宿主回退 sqlRows）；copyWith 可补标 | PASS |
| PLG-C12-011 | BSON 类型推断六徽章 + Object/null（24-hex=ObjectId、ISO8601 带时间=ISODate 等） | PASS |
| PLG-C12-012 | 推断边界：纯日期不带时间是 String；23 位 hex / UUID 不是 ObjectId | PASS |
| PLG-C12-013 | 值展示格式：字符串带引号 / ISODate("…") 包裹 / 超长截断省略号 | PASS |
| PLG-C12-014 | 文档卡片结构：_id 头 + 六徽章 + 嵌套对象框默认折叠 | PASS |
| PLG-C12-015 | 嵌套对象点击展开后内部字段可见 | PASS |
| PLG-C12-016 | 超阈值文档默认折叠（前 4 字段 + 展开 +N 按钮） | PASS |
| PLG-C12-017 | JSON 树：根/文档层默认展开、深层容器默认折叠（项数摘要） | PASS |
| PLG-C12-018 | JSON 树点击折叠节点强制展开（覆盖默认折叠层） | PASS |
| PLG-C12-019 | keyValue：GET 单行单字段→String 卡（标题取命令键名 + 长度脚注）；HGETALL→Hash 卡（Field/Value 表）；多行→序号卡 | PASS |

### 宿主形态默认视图（results_view_mode_test.dart C12 组）

| # | 用例 | 结果 |
|---|------|------|
| PLG-C12-101 | nosqlDocument 结果默认文档视图（切换条 Documents/JSON Tree/Table，无 Chart/Card；可切回表格兜底） | PASS |
| PLG-C12-102 | redisKeyValue 结果默认键值视图（String 徽章渲染、表格不在） | PASS |
| PLG-C12-103 | 无形态标记（历史结果）回退 sqlRows：Table/Chart/Card（C11 行为保持） | PASS |

**人工测试用例**:

| # | 用例 | 优先级 | 步骤摘要 | 预期结果 | 结果 |
|---|------|--------|---------|---------|------|
| C-RSLT-001 | C12 结果面板形态化走查 | P0 | 连一条 MongoDB（192.168.x.x:27017）：跑 `db.<集合>.find({})` 查询——结果面板默认**文档卡片**视图（_id 头 + ObjectId 蓝/String 绿/Number 橙/Boolean 灰/ISODate 蓝/Array 红徽章；嵌套对象折叠框可展开；超长文档「展开 +N 字段」按钮）；切 **JSON 树**（根数组→文档→字段逐层展开/折叠，值按类型着色）；切 **Table** 兜底（拍平视图可用，行为同旧版）；跑 count 查询确认单字段卡不炸。连一条 Redis：跑 `GET <key>` / `HGETALL <key>`——默认**键值视图**（String 卡=键名标题+值块+长度；Hash 卡=Field/Value 表）；切 JSON 树/Table 可用。跑普通 SQL（MySQL/PG）确认默认 Table 不变（无回归） | Mongo 三视图 / Redis 三视图按原型 result-panel-nosql/redis 工作；SQL 家族结果面板零变化；切换条文案六语正确 | **PASS（2026-08-20 用户走查通过；首轮反馈「Mongo Browse Documents 直开编辑器」已修复——见「走查反馈修复」节；C3 整段关闭）** |

## 附录：C13 — port 执行通道流式对接（2026-08-20）

**自动化**: `test/services/ports/port_execution_test.dart`（新，11 用例）+ E2E `integration_test/c13_port_streaming_e2e_test.dart`（2 用例，embedded server + 真库 SS）。GatewayBacking.execute() 真 SSE 流式（行批到达即下发，meta→rows*→complete|error）+ X-Execution-Id 取消（DELETE /api/gw/executions/{id}，server 以 error(CANCELLED) 收流）；AdapterBacking.execute() 包装现状 executeQuery 为单批块流（分页/行限语义不变）。

### GWY-C13 网关流式执行（单测）

| # | 用例 | 结果 |
|---|------|------|
| GWY-C13-001 | 请求形状：POST /api/gw/connections/{id}/query + X-Execution-Id 合法 UUID + camelCase 体（sql/database/schema/rowLimit/timeoutMs）+ Bearer | PASS |
| GWY-C13-002 | 块序契约：meta → rows*（多批累计）→ complete 终态关流（§4.2 四事件） | PASS |
| GWY-C13-003 | 真流式：meta 块在终态事件下发前即可收到（服务端 hold 终态门控——聚合实现会超时） | PASS |
| GWY-C13-004 | error 事件 → ExecutionError(code/engineCode) 后流关闭 | PASS |
| GWY-C13-005 | 前置 4xx（流未开始）→ ExecutionError 块（MULTI_STATEMENT 透传），session 面不抛 | PASS |
| GWY-C13-006 | 流裸断（无终态事件）→ ExecutionError(CONNECTION_FAILED) 兜底 | PASS |
| GWY-C13-007 | 未连接 server → CONFIG 错误块 | PASS |
| GWY-C13-008 | cancel() → DELETE /api/gw/executions/{id}（与 X-Execution-Id 同源；幂等二次不再发） | PASS |

### ADP-C13 包装块流（单测）

| # | 用例 | 结果 |
|---|------|------|
| ADP-C13-001 | 现状结果 → meta + 单批 rows + complete（列序=首行 keys；透传 connectionId/database） | PASS |
| ADP-C13-002 | 异常 → ExecutionError(DB_ERROR)（消息原样透传，现状 UI 语义） | PASS |
| ADP-C13-003 | 空结果 / cancel 幂等 no-op（本地取消走既有 KILL 链路，v1 边界） | PASS |

### C13 E2E（embedded server + 192.168.x.x:1433 真库）

| # | 用例 | 结果 |
|---|------|------|
| C13-SSE-E2E-001 | 流式块序：meta 先于数据块、行批累计 = complete.rowCount（sys.all_columns rowLimit 600 → 恰 600 + truncated）、位置数组行与 meta 列序对齐 | PASS |
| C13-CXL-E2E-001 | 取消：WAITFOR 60s 进行中 cancel() → error(CANCELLED) 终态收流（<50s，即时中断） | PASS |

## 附录：存量缺陷修复窗口（2026-08-20，C3 同窗）

### SQLite 附加库子树元数据错库（C16 登记，service 层 threading schemaName）

- 修复：`getDatabaseInfo` sqlite 特判（跳过 useDatabase 防 server.database 被错写成 alias + alias 透传到 `<alias>.sqlite_master`）；`getTables/getViews/getTriggers/getAllTables` 增可选 schemaName；`getTableColumns/getTableIndexes` sqlite 分支经 databaseName 承载 alias 限定 PRAGMA；adapter 三面（columns/indexes/triggers）增 schemaName 限定。
- 单测：`sqlite_adapter_test.dart` ATTACH 组 +3（columns 索引触发器 per-alias 限定与不串库）全绿。
- E2E：`c16_sqlite_sidebar_plugin_e2e_test.dart` C16-LT-ATTACH 由「结构守卫（不锁缺陷）」升级为**真内容断言**（附加库头下 ext_probe 存在、main_probe 不得串库），4/4 绿。

### e2e「tap 不命中」族（MY 10 + RD 4 + wave23 1 + DO 5 = 20 例，全部为测试 harness 缺陷非产品缺陷）

| 组 | 根因 | 修复 | 验证 |
|---|------|------|------|
| MY 10（Performance/Users/进程/用户/Kill Query + Connect×2） | tap 派生 Offset y=980/1006 超出默认 800×600 视口（折叠线下 tap 落空）；第二张连接卡在 lazy 列表折叠线下不构建 | pumpHarness 设 1280×1600 视口（逐测恢复）+ tapNode/rightClickNode/expandCategory 补 ensureVisible | **PASS（85/85，原 75/85）** |
| RD 4（db 菜单组 Select DB/Refresh/New Key/Flush DB） | 菜单项已统一 `CompactPopupMenuItem`（PopupMenuItem 子类），`find.widgetWithText(PopupMenuItem<String>)` 的 byType 精确匹配不认子类 | tapPopupMenuItem 改谓词子类型匹配 + ensureVisible | **PASS（42/42，原 38/42）** |
| wave23 Lua W3.3（rename） | 第二次 enterText 的 IME 文本被 re_editor 连接抢占、名字段 controller 不更新（enterLuaCode 同款坑，文件内已有先例注释） | 按 enterLuaCode 惯例直接写 controller.text | **PASS（8/8 全套，原 7/8）** |
| DO views_mv 5 | setUp 硬编码 `root/''` 凭据已无法连接 → 静默 return → 全树不渲染（远程 root 口令变更）；**连带真产品缺陷**：默认库选取取 SHOW DATABASES 首个 = Doris `__internal_schema`（USE 被 FE 1105 拒） | 换 DorisTestConfig 凭据 + `ConnectionProvider._pickDefaultDatabase` 跳过 `__` 前缀内部库（connect 存桩 + refresh 兜底×2）+ setUp 顺序修正（useDatabase 先于 refresh，防共享连接上下文被切走落错库） | **PASS（5/5，原 0/5；doris_menu 21/21 回归无恙）** |

### 走查反馈修复（C-RSLT-001 首轮，2026-08-20）

**Mongo 集合「Browse Documents」直开查询编辑器**（应直接看数据）：菜单 browse 分支改走 `provider.openBrowseDataTab`（spec 041 US2 数据浏览入口——隐 editor + 自动执行 find → C12 文档卡片直出）；`openBrowseDataTab` 的 FilterBar 可见性按连接类型门控（仅 SQL 系——FilterBar 的 Apply 是 SQL WHERE 拼装，对 Mongo 会生成非法查询；非 SQL 字段级过滤待 FilterBar 支持方言后再放开）；双击集合保留查询 tab 预填行为（对齐 SQL 双击语义）。

| # | 用例 | 结果 |
|---|------|------|
| C17-MG-BROWSE（integration_test/c17_sidebar_plugins_e2e_test.dart） | 集合行右键 Browse Documents → 新 tab 预填 `db.<集合>.find().limit(100)`（方言感知）+ editor/FilterBar 双隐 + find 执行返回 nosqlDocument 形态与探针文档（真库自建集合 + insertOne 探针，收尾 drop） | **PASS（c17 全套 7/7）** |

*注：自动执行的 unawaited 胶水在 integration binding 下不可推进（runAsync 外真实 IO 挂起，与 SQL 浏览路径同款应用内行为）——用例在 runAsync 内驱动同一 `executeCurrentQueryAndRecord` 调用验证执行链。*

## 附录：C21 — 编辑器 chrome 一致化（2026-08-20）

> 原型见内部原型页（editor-workspace / editor-executing / editor-results-split）。铁律 5：re_editor 本体不动（仅外围加 `onSelectionChanged` 选区回调管线）。范围裁定：工具栏右侧上下文芯片（连接/库/LIMIT/超时）一期不做——连接/库与 BreadcrumbBar 双显冗余，LIMIT/超时为功能新增（QuerySettings 无 per-connection UI 基建）登记 backlog；data-grid-edit 提交/放弃 footer = 完整写回功能（results_widget 注释明示「另立项」），不属换装。

### 标签条（test/organisms/tabs_bar_widget_test.dart，TS-009.1/009.2 按 C21 重写）

| # | 用例 | 结果 |
|---|------|------|
| TS-009.1 (C21) | 激活 tab = primaryContainer 底色（暗色 `primaryContainerDark`，替代 P1-2 bgPrimary 连通画布 + accent 底部指示条） | PASS |
| TS-009.2 (C21) | 非激活 tab 透明底；tab 面单行版式——库名不再作副标题渲染（BreadcrumbBar 承载，仅 tooltip 保留） | PASS |

视觉锚点（人工走查项）：类型色圆点 8px（`brandColor` 主题感知分发，无连接回退 textMuted）+ 13px 单行标题 + saved 徽章（save 图标 success）+ 环境点 + tab 间 border-right 分隔。

### 工具栏（test/organisms/editor/query_editor_toolbar_test.dart）

| # | 用例 | 结果 |
|---|------|------|
| TRB-C21-001 | 空闲：主按钮位 = labeled 运行（play + Execute 文案，filled 变体）；不渲染停止按钮 | PASS |
| TRB-C21-002 | 执行中：主按钮位切换为停止（square + Stop，danger 变体），运行按钮消失——单主按钮位状态化，取消能力保留 | PASS |
| TRB-C21-003 | readOnly：显示 lock 只读状态 chip（Read-only 文案，非交互——readOnly 是连接属性） | PASS |
| TRB-C21-004 | 非 readOnly：不显示只读 chip | PASS |

配套：`ToolbarButton` 增 variant（ghost 默认/filled/outline/danger）——ghost 存量行为零变化（AppHeader 等全部消费点不回归）。

### 底部状态条（test/organisms/editor/query_editor_status_bar_test.dart，C21 重写——原 widget 为零引用死代码，首次接线进编辑器）

| # | 用例 | 结果 |
|---|------|------|
| SBAR-001 | 就绪态：success 图标 + Ready + 行列（Ln/Col 格式）+ 右段 UTF-8 \| SQL \| MySQL | PASS |
| SBAR-002 | 执行中：warning spinner + Executing；elapsed ValueNotifier 到位后显示已耗时（0:03.2 tabular 格式） | PASS |
| SBAR-003 | 无数据库类型上下文：右段仅 UTF-8 \| 语言（JavaScript 场景） | PASS |
| SBAR-004 | 光标移动经 ValueNotifier 局部更新行列（不重建编辑器——execProgress 同款契约） | PASS |

管线：`ReSqlEditor.onSelectionChanged`（控制器本身 ValueNotifier，selection setter 触发；逻辑行经 `index2lineIndex` 折算）；`QueryEditorWidget` 持 `_cursorPos`/`_execElapsed` 两个 ValueNotifier + 1s tick Timer（dispose 成对释放）。

### 轻度对齐件（无独立用例，视觉走查覆盖）

- `EditorResultsResizer`：grip chip 手柄（bgQuaternary 圆角块 + grip 图标，hover/拖拽 accent 化）+ 4px borderLight 静止 bar——12px 命中区与拖拽语义不变。
- `ResultSubTabBar` active 项去底色（下划线 + accent 文字式，原型结果子标签语汇）；功能（pin/close/耗时/错误色）不动。
- `ExecutionStatusBar` 两处硬编码中文 l10n 化（`executionStatusBarRows`/`executionStatusBarErrorHint`，存量红线违规顺手修）。

### 人工走查

| # | 走查项 | 结果 |
|---|------|------|
| C-EDIT-001 | C21 编辑器 chrome：tab 条（类型色圆点/primaryContainer 激活/单行）+ 工具栏（运行 filled/执行中停止/只读 chip）+ 底部状态条（就绪/执行中耗时/行列/上下文）+ 分栏 grip 手柄，亮暗双主题 | **PASS（2026-08-20 用户走查，无问题）** |

## C22-0 · 侧边栏视觉终态（2026-08-20）

> 范围：顶部连接选择器（新组件）+ 紧凑 chrome（品牌 header/描边搜索框/border-top footer/折叠 rail）+ 既有面统一 SidebarSection（收藏/最近表/连接分组）+ SS/TD/PG 树文案 l10n 六语。行为保持的视觉重样式——树本体（C15-C20 插件）与能力菜单（C14）不动。测试文件：`test/organisms/sidebar/c22_sidebar_chrome_test.dart`。

| # | 用例 | 结果 |
|---|------|------|
| SEL-C22-001 | 选择器显示当前连接名 + 地址（活动 tab → currentServer → 侧栏选中回退源） | PASS |
| SEL-C22-002 | SQLite 地址不拼端口（host 承载文件路径） | PASS |
| SEL-C22-003 | 无已保存连接：占位按钮（No connection）点击打开连接管理器 | PASS |
| SEL-C22-004 | 菜单列出全部连接（类型图标/当前项加粗/已连接状态点）+ 管理入口；未连接项走注入的连接流程（onConnectionTap——密码弹窗等副作用留宿主 controller） | PASS |
| SEL-C22-005 | 列表非空路径的「Manage Connections…」入口可打开管理器 | PASS |
| SEC-C22-001 | SidebarSection 默认展开；头部点击折叠再展开；计数徽章；trailing 动作不冒泡为折叠 | PASS |
| SBAR-C22-001 | 展开态冒烟：DbMaster 品牌字标 + 选择器接线（name - host:port）+ 搜索框 + footer | PASS |
| SBAR-C22-002 | 折叠态冒烟：panelLeftOpen 展开按钮 + settings 按钮 + 类型图标 rail | PASS |

## C22-1 · 单实例专注树 + AppHeader 下掉（2026-08-20，走查反馈修复窗口）

> 范围：SidebarTree 单实例化（只渲染当前连接）+ 分组迁选择器分区下拉 + AppHeader 整条下掉（命令面板→面包屑栏 / AI·主题·设置→footer 动作行 / ServerStatusBar→底部状态栏）。测试文件：`test/organisms/sidebar/c221_single_instance_test.dart`。

| # | 用例 | 结果 |
|---|------|------|
| SST-C22-001 | 多连接并存：树只渲染当前连接，切换选中即换树（非当前连接名不出现在树中） | PASS |
| SST-C22-002 | 有连接但无当前锚定：显示选择器引导提示（sidebarSelectConnectionHint） | PASS |
| SST-C22-003 | 回归（走查反馈 2026-08-20）：开着 A 连接的查询 tab 时 currentServer 切 B——树渲染 B 不被 tab 抢回（resolver currentServer 优先） | PASS |
| SEL-C22-G-001 | 选择器下拉按组分区：未分组在前 + 组头小节（组色圆点+组名，不可点）+ 孤儿组回退未分组 | PASS |
| FTR-C22-001 | footer 动作行：AI/主题/设置三键就位（暗色主题显 sun）；设置走注入回调 | PASS |
| FTR-C22-002 | AI 按钮点击切换 aiPanelOpen | PASS |
| BRC-C22-001 | BreadcrumbBar 无 tab 时仍渲染（常显），点击搜索入口（Ctrl+K 徽章）回调命令面板 | PASS |

适配：sidebar_controller_test 键盘导航 6 例改单实例契约（key 集只含当前连接；type-to-select「从当前节点环找 + 无匹配退化单字符重试」语义保持）；sidebar_widget_test helper 补侧栏选中锚定。⚠ 192.168.x.x 测试库端口不可达（2026-08-20 晚）——真库 E2E 套件待环境恢复补跑；c16 SQLite 专项 E2E 4/4（本地文件库）验证单实例树真 UI 链路。



l10n：13 新键六语（sidebarServerStatus/sidebarNoUsers/sidebarNoActiveProcesses/sidebarTdColsTags/sidebarTdColumnsCount/sidebarTdTagsCount/sidebarTdDeleteTitle/sidebarTdDeleteConfirm/sidebarDeleteGroup/sidebarDeleteGroupPrompt/sidebarConnectionSwitch/sidebarConnectionNone/sidebarManageConnections）——en 值与原硬编码逐字一致（E2E/存量断言零适配）；顺带修 recentTables 五语未译 + 分组对话框硬编码英文（commonCreate/commonCancel 复用）+ 删零引用键 sidebarDatabaseNavigation。连带修 c15/c18 E2E 存量 `onShowTableMenu (_,_,_) {}` Future 签名编译错（C19 遗留，AOT 才暴露）。

E2E 回归（2026-08-20，-d windows 逐文件）：mysql 金标准 58 过/2 跳/0 失败、redis 菜单 42/42、doris views_mv 5/5（DBMASTER_DORIS_HOST）、c15 5/5、c16 4/4、c17 7/7、c18 4/4、SS menu 24/24（embedded 前置需 DBMASTER_SERVER_BIN 指向 dist/Release/dbmaster-server.exe）。

### 人工走查

| # | 走查项 | 结果 |
|---|------|------|
| C-SIDEBAR-008 | C22-0+C22-1 侧边栏视觉终态走查：品牌 header（logo+DbMaster+分组动作）+ 顶部连接选择器（当前连接显示/按组分区下拉/切换/管理入口/空态）+ **单实例专注树**（树只显示当前连接：类型图标+名称+状态点树根行，展开=库列表/全局节点；切换选择器即换树；树根右键=完整连接管理菜单；无当前锚定时显示选择器引导提示）+ 描边搜索框 + 收藏/最近表新 section 头（计数徽章/折叠）+ footer 状态行+动作行（AI/主题/设置）+ 折叠 rail（32px/primaryContainer 激活）+ **顶部菜单栏已整条下掉**（命令面板入口在面包屑栏右端 ⌘K 徽章、Server 状态在底部状态栏右端），亮暗双主题；SS 全局节点与 TD 树文案已本地化（六语切换抽查） | **PASS（2026-08-21 用户走查通过，C22-0/C22-1 收口，#33 一期完成）** |

## C23 · AI 面板三栏重构 + skill 接口化（2026-08-22，#33 二期 M1）

> 范围：AI 面板三栏（左技能目录 240 / 中对话 / 右上下文 260，断点 700px 响应式）
> + AiSkillPlugin 接口化（C01a 占位接线，内置 10 技能四分组）+ envelope
> 统一渲染（sql/markdown/diff/json 分发，diff 新增）+ Schema 上下文开关。
> 测试文件：`test/organisms/ai_panel/skills/builtin_ai_skills_test.dart`、
> `ai_panel_three_column_test.dart`、`ai_context_panel_test.dart`、
> `ai_result_renderer_test.dart`（envelope 分发组）。

### 单元/Widget 用例

| # | 用例 | 结果 |
|---|------|------|
| SKL-C23-001 | bootstrap 默认注册 10 内置技能，id 全局唯一，来源均 PluginSource.ai | PASS |
| SKL-C23-002 | 四分组次序与计数：SQL 3（nl2sql/sql-explain/query-optimizer）/ 数据 2 / 结构 3 / 运维 2 | PASS |
| SKL-C23-003 | resultType 声明：nl2sql=sql、schema-diff=diff、import-mapping=json，其余默认 markdown | PASS |
| SKL-C23-004 | nl2sql 无 promptTemplate（自由输入），sql-explain 有模板 | PASS |
| ENV-C23-001 | AiSkillEnvelope.typeFromName 四型往返；null/未知名 → null（存量消息回退启发式） | PASS |
| ENV-C23-002 | envelope sql：无围栏裸 SQL 直接 SqlCodeBlock | PASS |
| ENV-C23-003 | envelope json → 代码块路径；envelope markdown → MarkdownBody；无 envelope 含围栏 SQL 仍走启发式（存量行为） | PASS |
| ENV-C23-004 | envelope diff：+/-/@@ 行渲染且不进 SqlCodeBlock | PASS |
| CTX-C23-001 | 上下文面板：无连接空态卡；有连接显示名称 + host；未选库回退 All Databases | PASS |
| CTX-C23-002 | Schema 上下文 toggle 初始态由宿主传入（默认开），点击回调新值 | PASS |
| COL-C23-001 | 宽面（1000px）：左技能目录 + 右上下文栏常驻；无窄模式入口按钮 | PASS |
| COL-C23-002 | 窄面（400px）：两栏隐藏，header sparkles 入口；点击弹 Tab 对话框（Skills/Context 两标签可达） | PASS |
| COL-C23-003 | 窄面入口选带模板技能：对话框关闭 + promptTemplate 填入输入框 | PASS |

### 人工走查

| # | 走查项 | 结果 |
|---|------|------|
| C-AI-001 | C23 三栏走查：全屏/大 overlay（≥700px）左技能目录（四分组头 + 10 技能条目 + 插件徽章 + 选中态）+ 中对话（现有链路不变）+ 右上下文（连接卡/当前库/Schema toggle）；停靠侧栏（400px）单栏 + header sparkles 入口弹 Tab 对话框；技能点击填模板；Schema toggle 关闭后发送不预载表结构；六语切换抽查 | **PASS（2026-08-22 用户走查通过，C23/M1 收口）** |

### 走查反馈修复（C-AI-001 后续，2026-08-22）

**AI 面板「全屏」真铺满**（用户反馈「全屏时没有真正铺满整个程序面板」）：根因——`AiFullscreenOverlay` 把 aiFullscreen 与 aiAsOverlay 两种形态都渲染成 `AiPanelOverlay` 浮动窗（默认 65% 视口、可拖拽），「全屏」名不副实。修复——fs=true 走 `Positioned.fill` 真全屏（AiPanelWidget 直铺 z2 层，退出 = header minimize / Ctrl+Shift+F）；浮窗仅留窄窗布局降级（aiAsOverlay && !fs）。测试：`test/screens/home/ai_fullscreen_overlay_test.dart` 3 例（FS-C23-001 真铺满尺寸 1200×800 / FS-C23-002 退出态不渲染 / FS-C23-003 窄窗降级仍浮窗且非铺满）+ home_layers_test「shown when AI fullscreen」改新契约。

## C22-M2 · 安全审查 UI 迁移（2026-08-22，#33 二期 M2 首项）

> 范围：①设置对话框安全规则区按新设计系统重构（紧凑分区头 + 单容器行列表
> + 级别圆点 Tooltip，替代 12 张独立重卡片；开关序/阈值行结构保持 =
> tapSwitch 索引契约不变）；②红点复核（re_editor 槽位已全 token 化，
> **复核通过无改动**）；③安全审查横幅 + 执行门弹窗 + 状态栏指示器
> l10n 化（原硬编码英文/中文/emoji，+20 键六语）；④死代码清理
> （`SafetyFinding.colorFor/labelFor`、`SafetyReviewResult.label`）。
> 测试文件：`test/organisms/connection/settings_dialog_test.dart`（改写
> 渲染用例）、`test/organisms/editor/query_editor_widget_test.dart`
> （T13 组改 l10n 断言）、`test/organisms/results/sqlserver_ddl_banner_widget_test.dart`（l10n 化 + 新增倒计时用例）。

### 单元/Widget 用例

| # | 用例 | 结果 |
|---|------|------|
| SET-C22M2-001 | 安全规则分区渲染 12 开关（B1 六 + B6 六，含末位 reviewFailClosed）+ 级别圆点 Tooltip 计数：高危 6 / 警告 5 / 策略 1（映射真相源 = rules/*.dart severity，改规则严重度时同步） | PASS |
| SET-C22M2-002~006 | 既有 tapSwitch 索引用例（2/7/13 号开关 + 阈值两例）在新区版式下不变仍绿（结构契约保持） | PASS |
| GATE-C22M2-001 | 执行门单语句：严重度徽章（l10n safetySeverityHigh）+ finding 中文标题/描述；无建议按钮、无跳过按钮；取消 → cancel | PASS |
| GATE-C22M2-002 | 「知情继续执行」（l10n gateProceed，已去 ⚠ emoji 前缀）→ proceed | PASS |
| GATE-C22M2-003 | 取消（l10n commonCancel）→ cancel | PASS |
| BAN-C22M2-001 | 横幅三动作经 l10n 断言（commonConfirm / safetyBannerAddLimit / commonCancel），点取消不触发确认 | PASS |
| BAN-C22M2-002 | 冷却期确认按钮显示倒计时占位文案（safetyBannerCooldown(3)）且点击不触发回调 | PASS |

### 附带影响（集成测试同步）

`integration_test/b123_safety_ui_e2e_test.dart`：「⚠ 知情继续执行」断言改「知情继续执行」（l10n zh 值，去 emoji）；其余中文断言（取消/分区标题/规则名/阈值标签）经 l10n zh 值继续匹配，无需改。

### 人工走查

| # | 走查项 | 结果 |
|---|------|------|
| C-SEC-001 | 设置对话框安全规则区新语汇（紧凑分区头 + 单容器行列表 + 级别圆点）；执行门六语抽查；状态栏指示器去 emoji | **PASS（2026-08-22 用户走查通过）** |

## C23 后续 · AI 全屏「直接消失」二轮修复（2026-08-22，真实路径 e2e）

> 用户走查反馈：「ai全屏化直接消失了」。**根因**：全屏态下 z0/z1/z3 兄弟层
> 全部 `SizedBox.shrink`（0×0 非定位子项），home_screen 四层 Stack（loose
> fit）自身宽度塌成 0；全屏分支的 `Positioned.fill` 只能铺满这个 0 宽的
> Stack → 面板实际渲染 0×875 = 不可见。首轮修复的隔离测试用了
> `Stack(fit: expand)`（强制 Stack 满尺寸）恰好掩盖该塌缩；执行中心层的
> 同款 `Positioned.fill` 能工作是因为它弹出时 z0 工作区仍渲染（有满尺寸
> 非定位子项撑 Stack）。**修复**：全屏分支改 `SizedBox.expand`（自撑满的
> 非定位子项，自身铺满 + 把 Stack 尺寸撑回，不依赖兄弟层状态）。连带修
> `_HomeScreenState.dispose` 的 `context.read`（deactivated-ancestor 断言，
> e2e 卸载期暴露）→ 挂接时缓存 `_attachedProvider`。
> 测试文件：`test/screens/home/ai_fullscreen_e2e_test.dart`（**真实
> HomeScreen 路径**——四层 Stack + provider 全树 + 点按钮交互）；
> 首轮隔离测试 `ai_fullscreen_overlay_test.dart` 头注释补「expand 掩盖」警示。

### 单元/Widget 用例

| # | 用例 | 结果 |
|---|------|------|
| E2E-FS-001 | 停靠面板（有连接，宽窗 1400×900）点 header 全屏 → 面板仍存在、非浮动窗、尺寸 1400×875（视口减 25px 状态栏） | PASS |
| E2E-FS-002 | 全屏态点 header minimize → 退出回停靠面板（面板不消失、FAB 不出现、fs=false） | PASS |
| E2E-FS-003 | 面板关闭态点右下 FAB（onTap = 开面板 + 直入全屏，用户最可能入口）→ 面板可见且铺满 | PASS |

### 既有用例回归

`ai_fullscreen_overlay_test.dart` 3 例（层隔离）+ `home_layers_test.dart` 12 例（z 层显隐）修复后全绿，零适配。

### 人工走查

| # | 走查项 | 结果 |
|---|------|------|
| C-AI-002 | AI 全屏二轮修复复验：FAB 直入全屏 / 停靠面板全屏按钮 → 面板真铺满工作区；minimize 退出回停靠 | **PASS（2026-08-22 用户走查通过）** |

## C22-M2 · 设置对话框整窗迁移（2026-08-22，#33 二期 M2 第二项）

> 范围：单列长滚动（400px × 10 分区）→ **左导航 + 右分区**（原型
> settings-page.html：640×520 弹窗，左 176px 导航六项 + 右滚动分区）。
> 分区映射：外观（主题 + 编辑器自动补全，默认页）/ AI 配置（自动执行
> SQL）/ 查询（自动 LIMIT + 数值）/ 语言 / 安全（首项迁移的安全规则区
> 原样嵌入）/ 关于（订阅 SPI + 日志 U14 + 更新 U15 + 关于 U17）。
> **descope**：原型「快捷键」导航页无对应设置内容，不落空页（登记
> task_ui_phase2.md）；原型的「侧边栏密度/字体大小」无设置基建，同
> descope。l10n +6 键六语（settingsNav*）；lucide 子集字体再生成
> （227 图标）。测试适配：开关索引从全对话框序改为**页内序**
> （find.byType(Switch) 只命中当前页）；阈值定位改页内唯一 TextField。
>
> **续（同日）：外观页内联主题控件**——ThemePreviewDialog（372 行，
> 暂存-应用式弹窗）退役删除，其控件内联外观页并改**即点即生效**：
> 主题模式三卡（dark/light/system，选中 = accent 15% 底 + 2px 描边）+
> 强调色圆点 28px（选中 = check + 光晕，ValueKey('accent_dot_*') 测试钩
> 子）+ SQL 冷主题开关（默认开）。外观页开关序变更：sqlCool(0) +
> 自动补全(1)——既有自动补全/持久化用例索引 +1 适配。孤儿 l10n 键 5 个
> （settingsThemeSettings/Apply/Preview/PrimaryButton/SecondaryButton，
> 保留不删，登记 task_ui_phase2）。
> 测试文件：`test/organisms/connection/settings_dialog_test.dart`（重写
> 为分页导航式 + 主题控件即点即生效用例）、`integration_test/
> b123_safety_ui_e2e_test.dart`、`integration_test/app_wide_test.dart`；
> 删除 `test/organisms/dialogs/theme_preview_dialog_test.dart`（随弹窗
> 退役，关键断言移植：模式卡渲染/点击生效/强调色切换）。

### 单元/Widget 用例

| # | 用例 | 结果 |
|---|------|------|
| SET-NAV-001 | 左导航六项常驻；默认页 = 外观（编辑器分区 + 自动补全开关在默认页；C22 M2 续后 nav「外观」全局唯一——页内不再有同文案分区头） | PASS |
| SET-NAV-002 | 导航切页：查询页（自动 LIMIT）/ 安全页（安全审查规则分区）/ 关于页（日志区块）内容各就各位 | PASS |
| SET-NAV-003 | 语言页：常规设置分区头 + Locale 下拉 | PASS |
| SET-NAV-004 | 主题控件内联渲染：主题模式/强调色分区头 + moon/sun/sunMoon 三卡 | PASS |
| SET-NAV-005 | 主题控件即点即生效：点 Light 卡 → themeMode=light；点 accent_dot 首圆点 → 强调色切换；sqlCool 开关（页内序 0，默认开 → 点 → 关） | PASS |
| SET-NAV-006~008 | 页内开关：自动补全（外观页 1）/ 自动 LIMIT（查询页 0）/ 自动执行 SQL（AI 页 0，默认 false → 开 → true） | PASS |
| SET-C22M2-001~006 | 安全页既有用例适配页内索引（schemaCompat 0 / explainEstimatedRows 5 / reviewFailClosed 11 / 阈值两例改页内唯一 TextField） | PASS |
| MAN-SET-006 | 持久化两例跨页操作（外观→查询→AI 依次切换后关闭重载） | PASS |
| MAN-I18N-001~007 | 六语溢出检测在分页版式下全过（默认页含内联主题控件） | PASS |

### 人工走查

| # | 走查项 | 结果 |
|---|------|------|
| C-SET-001 | 设置对话框整窗迁移：左导航六分区切换；外观页内联主题控件即点即生效（模式卡/强调色圆点/SQL 冷主题） | **PASS（2026-08-22 用户走查通过）** |

## C22-M2 · 导入导出向导迁移（2026-08-22，#33 二期 M2 第三项）

> 范围：①**死代码删除**——`lib/pro/data_import/smart_import_dialog.dart`
> （2939 行，被 ImportWizardDialog 取代后零引用）与
> `lib/organisms/connection/export_dialog.dart`（495 行，
> `ExportDialog.show` 零调用方，结果导出实际走 PiiExportDialog），
> 净 -3,434 行；②`pii_export_dialog.dart` 全量重构——硬编码中文清零
> （16 新键六语：步骤标签/检测文案/动作下拉/确认汇总/脚注），`dynamic`
> 颜色参数全改类型化 `ThemeColors`，原型 wizard 语汇（20px 圆点三态
> 步骤指示器 + radio-chip 格式选择 + 单容器行列表 + outline/filled
> footer 动作）；③`import_wizard_dialog.dart` 步骤指示器对齐原型
> （标签随行 + 1px 连接线，替代 32px 圆点下置标签），动作条
> ElevatedButton+Colors.white 手工样式 → FilledButton/OutlinedButton
> （走 ColorScheme.primary，换肤生效）；④`export_task_create_dialog.dart`
> Colors.red → themeColors.error、主按钮 → FilledButton。
> `connection_export_import_dialog.dart` 复核已全新式，无改动。
> 测试文件：新增 `test/organisms/results/pii_export_dialog_test.dart`
> （PII 对话框此前**零测试覆盖**）；ImportWizardDialog/ExportTaskCreateDialog
> 维持零 widget 测试现状（行为未变，Pro 区既有覆盖模式）。

### 单元/Widget 用例

| # | 用例 | 结果 |
|---|------|------|
| PII-EXP-001 | 步骤指示器三标签随行渲染 + 格式芯片三枚（CSV/JSON/Excel）+ 默认 CSV 下一步可点 | PASS |
| PII-EXP-002 | email 列检测命中：检测计数文案 + 行级动作下拉（普通 PII 默认 mask） | PASS |
| PII-EXP-003 | 无 PII 数据：未检测态（标题 + 副文案），无动作下拉 | PASS |
| PII-EXP-004 | 全流程返回值契约：切 JSON → 确认汇总 → 导出，PiiExportSelection.format='json'、email=mask、id/name=keep | PASS |

## C22-M2 · 团队协作 + Server 管理页面迁移（2026-08-22，#33 二期 M2 第四/五项）

> 范围：两族对话框「颜色已 token 化、排版旧」中间态收尾——排版统一到
> AppTextStyles（h3 头部替代 18/16px bold；body/caption/code 行文本；
> `fontFamily: 'monospace'` 全部换 AppTextStyles.code 等宽栈）+
> `Theme.of(context).textTheme.*` 18 处清零 + `Colors.red` 三处 →
> `themeColors.error` + FilledButton 主按钮化（走 ColorScheme.primary）。
> **团队协作**（7 文件）：team_query_library / workspace_list /
> workspace_members / join / approval_list / submit_approval
> （create_workspace 复核零旧式无改动）。**Server 管理**（11 文件）：
> server_status_bar **l10n 化九键六语**（Not connected/Connecting…/Local/
> Connected/Reconnecting…/{s}s/Server: {url}/Disconnect/Unknown——EN 值与
> 原硬编码逐字一致，**全部既有测试零适配通过**，含集成 mysql/pg/redis/ss
> e2e 的 tapMenuItem('Disconnect')）；server_connect_dialog（未知错误
> l10n + 间距/排版 token；URL 占位符 `https://myserver:3000` 保留——技术
> 示例 locale 不变式）；task_edit / drift×4（含 diff 页）/ data_sync×2 /
> health_check 收尾（✓/✗ 字形 → Lucide check/x 图标，F-37 方向；
> 'MySQL'/'PostgreSQL' 下拉项为品牌名保留）。
> 测试文件：无新增（行为/结构契约不变）；既有 63 例（server 族）+
> results 族 167 例回归全绿。

### 既有用例回归（契约保持验证）

| # | 用例 | 结果 |
|---|------|------|
| SRV-REG-001 | server 族 63 例（status_bar 9 态/菜单 + connect 表单序 + task_edit 预填 + connections + drift 列表/间隔编辑 + diff + data_sync + health 列表/创建/历史 + team_query + workspace + mcp + conversion）全绿零适配 | PASS |
| SRV-L10N-001 | 状态栏 l10n 化后 EN 值逐字保真：'Not connected'/'Connecting…'/'Reconnecting…'/'Local'/'Disconnect' 等被 server_status_bar_test 与四个集成 e2e 钉住的字符串全部原样命中 | PASS |

## 走查缺陷 · Data Sync 面板关闭后灰屏卡死（2026-08-22 晚，C22-M2 走查反馈）

> **用户报告**：Data Sync Tasks 面板点击 Close 后整个程序灰屏卡死。
> **日志取证**（`dbmaster_20260822_183541.log` 19:38:28）：
> 1. `DataSyncApiException(401: Server session expired)` —— embedded 会话
>    约 1 小时后过期，面板在途 `listTasks()` 被拒；对话框已关闭 → FutureBuilder
>    已卸载 → 拒绝无监听者 → unhandled zone error → ErrorBoundary 全屏接管。
> 2. `Null check operator used on a null value @ _DefaultErrorWidget.build:134`
>    —— **致命层**：ErrorBoundary 包在 MaterialApp **外层**（main.dart:164/212），
>    错误屏接管时没有 Localizations 祖先，`AppLocalizations.of(context)!` 空断言
>    → 错误屏自身崩溃 → release 灰屏无响应（任何未捕获错误都会走到这里）。
> **修复**：①`_DefaultErrorWidget` 自包含化——l10n 可空 + 英文回退（错误屏是
> 全应用最后兜底，绝不能再崩）；②server 族 10 个对话框的 FutureBuilder 数据
> future 加 `.ignore()`（关闭后无监听者的拒绝就地吞掉，FutureBuilder 自身
> 监听与错误分支不受影响）；③连带修 `setState(() => _future = future)` 箭头
> 闭包返回 Future 的断言陷阱（10 处改块体）。
> **遗留**（另立）：embedded 会话 ~1h 过期本身未修——server 端 embedded session
> 策略或客户端透明重认证，需 server 侧配合。

### 单元/Widget 用例

| # | 用例 | 结果 |
|---|------|------|
| EBS-001 | 无 Localizations 祖先（灰屏事故场景）：错误屏英文回退渲染（Something went wrong / Retry / 错误文本经 redactSecrets 的 toString），`takeException` 为空 | PASS |
| EBS-002 | 有 Localizations 祖先：l10n 文案（An error occurred / Report Issue） | PASS |
| EBS-003 | Retry 恢复原子树（错误屏退出回 child） | PASS |

> 测试工程注意（EBS 组踩坑记录）：ErrorBoundary 的 initState 覆写全局
> `FlutterError.onError`——flutter_test binding 在**测试体结束**时即断言已还原，
> tearDown/addTearDown 都太晚；正确姿势 = 捕获还原闭包 + 每例体末尾
> try/finally 显式还原。断言渲染文本须用 `textContaining`（实际渲染的是
> `Exception: xxx`）。

## C22-M2 · 结果面板去拥挤：语句层并入子标签层（2026-08-22，用户走查反馈两轮）

> 反馈一轮：「结果面板拥挤——history + Result 2… 下面还有查询语句层，
> 有几个语句就有一个 tab，想去掉」。首轮处理：单语句隐藏语句层 +
> 多语句标签序号化。
>
> 反馈二轮（用户拍板终态）：「完全可以将这个 tab 与 result 合并，
> result 保持现有命名，因为一个 query 始终只有一个 result tab」。
> **终态 = 语句层整体并入子标签层**：
> - `addResultToTab` **扇出**：一次执行 N 条语句 → N 个 Result 子标签
>   （沿用「Result N」命名，逐个插入自然连续编号），每子标签恰一条
>   ExecutionResult；`executedSql` = 语句级 SQL；子标签栏本身是
>   ListView.builder 懒构建（400+ 语句 DDL dump 无全量布局回退）。
> - **替换语义升级**：从「替换首个未 Pin」→「整批替换所有未 Pin 的
>   result 子标签」（History 是 pinned 不受影响；pin 粒度细化到单条
>   语句；单语句 + Name 注解仍用注解命名）。
> - **内层索引机制全套移除**（`_tabActiveInnerResultIndex`/
>   `setActiveInnerResult`/`getActiveInnerResultIndex`/
>   `activeInnerResultIndex`）——每子标签恰一条结果，无内层切换语义。
> - ResultsWidget：语句 TabBar/TabBarView/懒构建标签条/语句标签组件
>   全删（净 -190 行）；内容 = 活跃子标签单结果；AI 分析/导出读
>   `results.first`；TickerProviderStateMixin 退役。
>
> 测试契约：多语句切换 = 点子标签「Result N」；`executionResults` 每子
> 标签长度恒 1。适配：ai_analyze_current_result（重写为扇出 + 子标签
> 切换 + 整批替换/pin 保留/语句级 executedSql/closeResult clamp 四组）、
> sqlserver_results_widget（Result 1/2 子标签 + 无 TabBar）、
> results_widget_test（单语句无语句层断言不变）。

### 单元/Widget 用例

| # | 用例 | 结果 |
|---|------|------|
| RSLT-C22M2-001 | 单语句批次：无语句 TabBar（工具栏仅 AI/导出/搜索），数据表头直接渲染 | PASS |
| RSLT-C22M2-002 | 多语句扇出：Result 1 / Result 2 子标签（现有命名）+ 无语句内层 TabBar；默认显示第 1 个结果网格 | PASS |
| RSLT-C22M2-003 | 既有回归：点 Result 2 子标签后 AI 分析第 2 条（闭包冻结回归守卫换轨到子标签层仍生效） | PASS |
| RSLT-C22M2-004 | 扇出契约：两语句 → 两子标签各恰一条；label = Result 1/Result 2；executedSql = 语句级 | PASS |
| RSLT-C22M2-005 | 整批替换：再执行替换全部未 Pin 子标签；Pin 的语句子标签保留 | PASS |
| RSLT-C22M2-006 | closeResult 后活跃子标签索引 clamp 回合法范围 | PASS |

### 人工走查

| # | 走查项 | 结果 |
|---|------|------|
| C-RSLT-002 | 结果面板语句层并入子标签层复验：单语句直接呈现；多语句扇出 Result 1/N 子标签（现有命名）可切换；pin 某条语句结果再执行不被覆盖；History 不受影响 | **PASS（2026-08-22 用户复验通过）** |

*文档结束*  
*最后更新: 2026-08-22（**M2 第四/五项团队协作 + Server 管理迁移：7+11 文件排版 token 化 + status_bar l10n 九键六语（EN 逐字保真零适配）+ 63 例回归全绿**。同日 M2 第三项导入导出向导迁移：死代码 -3,434 行 + PII 导出对话框全量重构（l10n 16 键六语 + 原型 wizard 语汇）+ PII-EXP 4 例新增。同日 C-SET-001/C-SEC-001 走查 PASS（设置对话框 + 安全审查区）。同日 C-RSLT-002 复验 PASS——结果面板语句层并入子标签层收口。同日 M2 第二项设置对话框完成（含续）：左导航六分区 + 外观页内联主题控件 + ThemePreviewDialog 退役。同日 C-AI-002 走查 PASS——AI 全屏二轮修复收口。同日 C22-M2 安全审查 UI 迁移 + C-AI-001 走查通过——C23 收口，#33 二期 M1 完成。2026-08-21：C-SIDEBAR-008 走查通过——#33 一期（C0-C5）全部完成）*
