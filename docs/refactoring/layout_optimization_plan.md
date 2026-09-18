# DbMaster 客户端布局优化方案

> 文档版本：2026-08-14（2026-08-13 初稿；本轮加「实施进度」并标注已完成节）
> 基于代码审查范围：`lib/screens/home_screen.dart`、`lib/templates/main_workspace.dart`、`lib/templates/editor_results_split.dart`、`lib/organisms/sidebar_widget.dart`、`lib/atoms/app_header.dart`、`lib/organisms/connection/status_bar_widget.dart`、`lib/organisms/ai_panel/*`、`lib/organisms/execution_center/*`、`lib/theme/design_system.dart`、`lib/utils/responsive_helper.dart`

---

## 实施进度（2026-08-14 更新）

> 下文「三、详细优化方案」保持原始设计方案不动；本节反映**实际实施状态**。
> 实施顺序按节推进（低风险先行），未严格遵循 §4.1 的 Phase 划分。

| 节 | 状态 | 说明 |
|---|---|---|
| §3.1 HomeScreen Stack 拆层 | ✅ 已完成 | 4 层独立 widget（`lib/screens/home/`），HomeScreen 薄壳（build 58 行），分支已合并 master |
| §3.2 右侧面板共存策略 | ✅ 已完成 | 路径 B 显示降级（不改持久态），三级逐级，见下方笔记 |
| §3.3 响应式断点统一 | ✅ 已完成 | 600/900/1200/1600 → `AppDesignSystem` 常量（single source of truth），`ResponsiveHelper`/`HomeScreen`/`app_card` 统一引用，无残留硬编码 |
| §3.4 SidebarWidget 拆分 | ✅ 已完成 | 1682→366 行；`SidebarController`（1044 行，不依赖 BuildContext）+ `sidebar_visible_nodes.dart`（408 行纯函数）+ `sidebar_search_field.dart`（73 行），键盘导航从零覆盖到 19 单测，见下方笔记 |
| §3.5 侧边栏搜索重建 | ✅ 已完成 | 稳定 key（SidebarTree 内部早已过滤，原动态 key 是遗留 bug） |
| §3.6 魔法数收敛 | ✅ 已完成 | `+1.0` → `tabBarDividerHeight` 常量 |
| §3.7 AI FAB 位置 | ✅ 已完成 | 收敛为 `aiFab*Offset/aiFabSize` 常量（保持原视觉值） |
| §3.8 状态栏信息去重 | ✅ 已完成 | 删 `StatusBarWidget._buildLastExecutionSummary`（与 `ExecutionStatusBar` 数据源相同、信息冗余）；全局底部不再显示"行·ms"，执行详情归结果区 `ExecutionStatusBar`（信息更全） |
| §3.9 WelcomeScreen i18n | ✅ 已完成 | `welcomeSubtitle` ARB key |

### 关键实现笔记（与原方案的差异）

- **§3.4 实际拆 4 个文件**（plan 原列 2 个新增文件，实施时把最重的纯逻辑独立成第三个文件便于单测）：`sidebar_controller.dart`（ChangeNotifier：3 展开集合 + 键盘导航全套 + 懒加载 + 连接事件订阅 + 搜索/树 FocusNode 等 UI 资源；`AppProvider` 构造注入、密码弹窗经 `promptPassword` 回调注入、时钟经 `now` 注入——不依赖 BuildContext）+ `sidebar_visible_nodes.dart`（可见节点 key 构建纯函数库，含 type-to-select 显示名解析）+ `sidebar_search_field.dart`（受控搜索框）+ `sidebar_widget.dart` 退化为 366 行 UI 壳（折叠/展开布局 + 需要 context 的 6 个对话框路由）。
- **§3.4 顺手清理**：删 `_SyncedExpandedConnection` + no-op `_syncExpandedConnection`（注释自述 no-op，仅产生无意义 rebuild）；为可测性给 `DatabaseService` 补 `registerConnectedAdapterForTest` 测试钩子（原 `registerConnectedServerForTest` 注释声称让 hasConnection 为 true 但实现只标记 servers，不兑现）。
- **§3.4 测试**：`sidebar_controller_test.dart` 19 单测（↑↓/←→/Esc/type-to-select buffer 语义与超时/展开持久化 round-trip/ConnectionEstablished 清子展开/可见节点层级/搜索过滤/displayName 解析）——键盘导航**从零覆盖到有覆盖**；widget 冒烟 +2（↓ 导航不异常 / 搜索输入过滤+清空按钮）。注意 `tester.sendKeyDownEvent` 连续按同一键必须成对 keyUp（`HardwareKeyboard._assertEventIsRegular` 断言物理键重复按下）。
- **§3.4 已知既有问题（原样迁移，未修）**：①键盘展开 db: 节点存入 `'db:cid:db'` 格式 key，而树点击存 `'cid:db'` 格式——`pruneOrphanedExpandedDatabases` 对 `'db:'` 前缀 key 会误判孤儿（connId 解析成 'db'）；②`_handleTreeEnter` 处理 `func:` 前缀但 visible nodes 生成的是 `fn:`（schema functions），两处前缀不一致；③type-to-select buffer 无匹配重置后当次不重试（原实现语义，测试已锁定）。修复留后续独立任务。
- **§3.4 后续可选收益（未做）**：6 个 e2e 文件各自复制的 `_SidebarTestHarness` 展开状态机可替换为注入 `SidebarController`（消 6 份重复）。
- **§3.2 改用路径 B（显示降级）**：原方案给「可配置优先级」未拍板；讨论后定为**显示降级**（渲染层覆盖、不改持久态）+ **三级完整**（sidebar 折叠 → AI 改浮层 → EC 改浮层，阈值 `minWorkspaceComfortWidth=480`）+ 拥挤态手动展开**纯显示阻止 + SnackBar 提示**。核心是 `lib/layout/effective_layout.dart` 的 `computeEffectiveLayout` 纯函数 + HomeScreen 接入；14 单测覆盖。不做 autoManaged 状态机；EC pin 手动阻止留后续。
- **§3.2 关键发现**：`AiPanelOverlay` 注释写"全屏浮层"，实际是**可缩放非全屏浮层**（8 方向手柄），AI 降级直接复用它，无需新建组件。
- **§3.5 遗留 bug**：`sidebar_widget.dart:66` 注释早写"SidebarTree now uses a stable key"，但 key 实际是动态的（改注释漏改代码）；`SidebarTree` 早已接收 `searchQuery` 内部过滤。改回稳定 key 一行修复。
- **验证方式**：§3.2 纯函数 14 测试 + 已桌面走查通过；§3.5/3.6/3.7/3.9 sidebar+ai_welcome 68 测试零回归。HomeScreen widget 测试因 pump 成本高跳过（项目无 home_screen 测试先例），靠纯函数 + 桌面走查兜底。

---

## 一、目标与范围

### 1.1 优化目标

1. 降低主布局文件 `HomeScreen` 的认知与维护成本
2. 明确多面板（侧边栏 / AI / 执行中心）共存时的空间分配规则
3. 统一响应式断点，消除小窗口/折叠态的冲突
4. 减少侧边栏在大数据量下的不必要重建
5. 将硬编码尺寸/位置收敛到 `AppDesignSystem`，保持设计语言一致

### 1.2 非目标

- 不改动数据库适配器、查询执行逻辑、Provider 数据流
- 不引入新的动画系统或第三方布局库
- 不重新设计品牌色与字体体系

---

## 二、现状摘要

当前布局是典型的桌面 IDE 三栏结构：

```
┌─────────────────────────────────────────────────────────────┐
│  AppHeader (48px)                                           │
├───────┬──────────────────────────────┬──────────────────────┤
│       │  TabsBarWidget (32px)        │                      │
│       ├──────────────────────────────┤   AI Panel           │
│       │  QueryEditor                 │   (可选 docked)      │
│Sidebar│  ── Resizer ──               │                      │
│       │  ResultsWidget               ├──────────────────────┤
│       │  ExecutionStatusBar          │  Execution Center    │
├───────┴──────────────────────────────┴──────────────────────┤
│  StatusBarWidget (24px)                                     │
└─────────────────────────────────────────────────────────────┘
+ AI 全屏浮层 (Stack 上层)
+ AI 迷你 FAB (右下角)
```

主要痛点：

- `HomeScreen.build()` 约 140 行，Stack 内叠加了 4 类 layer，z-order 隐式
- AI 面板与执行中心同时 docked 时缺乏 workspace 最小宽度保护
- 响应式断点与 `minWindowWidth`、`ResponsiveHelper` 不完全一致
- `SidebarTree` 以 `searchQuery` 为 `ValueKey`，每次输入都会重建整棵树
- `SidebarWidget` 约 1700 行，混合布局、状态、键盘导航、懒加载
- 部分尺寸/偏移为硬编码（如 `+1.0`、AI FAB `bottom: 48`）

---

## 三、详细优化方案

### 3.1 HomeScreen：Stack 层级解耦

#### 问题
`HomeScreen` 的 `Stack` 直接包含：

1. 主工作区 Row（sidebar + workspace + execution center docked + AI docked）
2. 执行中心浮动 scrim + 面板
3. AI 全屏浮层
4. AI 迷你 FAB

z-order 由代码顺序决定，后续维护容易误改覆盖关系。

#### 方案

将 `Stack` 拆分为语义明确的 layer widget：

```
Stack(
  children: [
    _MainWorkspaceLayer(),      // z = 0
    _ExecutionCenterOverlay(),  // z = 1
    _AiFullscreenOverlay(),     // z = 2
    _AiMiniFab(),               // z = 3
  ],
)
```

新增文件建议：

| 组件 | 建议文件 | 职责 |
|------|---------|------|
| `_MainWorkspaceLayer` | `lib/templates/home_layers/main_workspace_layer.dart` | 渲染底层 Row，处理 sidebar/execution center docked/AI docked 的水平布局 |
| `_ExecutionCenterOverlay` | `lib/templates/home_layers/execution_center_overlay.dart` | 浮动模式下的 scrim + 右侧面板 |
| `_AiFullscreenOverlay` | 复用 `lib/organisms/ai_panel/ai_panel_overlay.dart` | 全屏浮层 |
| `_AiMiniFab` | 复用 `lib/organisms/ai_panel/ai_mini_fab.dart` | 右下角 FAB |

每个 layer 只订阅自己关心的状态，降低 `HomeScreen` 的 rebuild 范围。

#### 验收标准

- `HomeScreen.build()` 行数 < 60 行
- `Stack` 子项数量 ≤ 4，且每个子项为独立 widget
- 新增/修改 widget 测试覆盖 layer 显隐逻辑

---

### 3.2 右侧面板：AI 与执行中心共存策略

#### 问题
当 `aiPanelOpen = true` 且 `executionCenter.isOpen && isPinned = true` 时，workspace 右侧同时被 AI 面板和执行中心占用。在 1024~1280px 窗口下，编辑器可用宽度可能低于舒适值（建议 ≥ 480px）。

#### 方案

在 `LayoutPreferencesProvider` 或 `AppProvider` 中新增「workspace 最小宽度保护」逻辑：

```dart
// 伪代码
final totalWidth = constraints.maxWidth;
final sidebarW = shouldCollapseSidebar ? collapsedWidth : layoutProvider.sidebarWidth;
final aiW = appProvider.aiPanelOpen && !appProvider.aiPanelFullscreen ? layoutProvider.aiPanelWidth : 0;
final ecW = appProvider.executionCenter.isOpen && appProvider.executionCenter.isPinned
    ? appProvider.executionCenter.width
    : 0;
final consumedW = sidebarW + aiW + ecW;
final availableWorkspaceW = totalWidth - consumedW;

const minWorkspaceWidth = 480.0;
if (availableWorkspaceW < minWorkspaceWidth) {
  // 优先级：执行中心 > AI 面板（可配置）
  // 方案 A：自动将 AI 切换为浮层
  // 方案 B：自动折叠侧边栏
  // 方案 C：显示一个 subtle 提示，让用户手动处理
}
```

推荐采用「可配置优先级」策略：

- 默认优先级：执行中心（任务/错误）> AI 面板 > 侧边栏
- 当空间不足时，按优先级从低到高自动切换形态：
  1. 侧边栏折叠
  2. AI 面板切换为浮层
  3. 执行中心切换为浮动 overlay

#### 验收标准

- 窗口宽度 1024px 时，AI + 执行中心 + 展开侧边栏 不会使 editor 区域 < 480px
- 自动切换形态时，用户上一次手动设置不应被覆盖（增加一个 `autoManaged` 标记）
- widget 测试覆盖三种面板组合的宽度约束场景

---

### 3.3 响应式断点统一

#### 问题
- `HomeScreen` 折叠阈值：`constraints.maxWidth < 900`
- `ResponsiveHelper` 断点：600 / 900 / 1200 / 1600
- `AppDesignSystem.minWindowWidth`：1024
- `ResponsiveHelper.getSidebarWidth` 在 < 600 时返回 0，与折叠逻辑不一致

#### 方案

在 `AppDesignSystem` 中集中定义响应式常量，所有布局代码统一引用：

```dart
// lib/theme/design_system.dart
class AppDesignSystem {
  static const double breakpointCompact = 600;
  static const double breakpointMedium = 900;
  static const double breakpointExpanded = 1200;
  static const double breakpointLarge = 1600;

  static const double sidebarAutoCollapseBreakpoint = breakpointMedium;
  static const double minWorkspaceComfortWidth = 480;
}
```

修改点：

1. `HomeScreen` 使用 `AppDesignSystem.sidebarAutoCollapseBreakpoint` 而非硬编码 900
2. `ResponsiveHelper` 引用上述常量，删除重复硬编码
3. 明确 `minWindowWidth` 与 `breakpointMedium` 的关系：
   - `minWindowWidth` 是 OS 窗口最小尺寸（1024）
   - `breakpointMedium` 是 UI 折叠阈值（900）
   - 在文档中注释：允许用户在 900~1024 之间看到折叠态侧边栏

#### 验收标准

- 所有响应式判断通过 `ResponsiveHelper` 或 `AppDesignSystem` 常量
- 无其他文件硬编码 600/900/1200/1600
- `flutter analyze` 无新增 warning

---

### 3.4 SidebarWidget 职责拆分

#### 问题
`SidebarWidget` 约 1700 行，同时承担：

- UI 渲染（header / search / tree / footer / MySQL process panel）
- 展开状态管理（connection / database / table / category）
- 键盘导航（↑↓←→ / Enter / Space / type-to-select）
- 懒加载触发（database / table schema / schema objects）
- 右键菜单与对话框路由

#### 方案

第一阶段拆分：

```
SidebarWidget
├── SidebarController (ChangeNotifier，管理展开状态 + 键盘导航)
├── SidebarHeader
├── SidebarSearchField
├── SidebarTree (纯展示，接收 expanded sets + callbacks)
├── MysqlProcessPanel (已独立)
└── SidebarFooter
```

新增文件：

| 文件 | 职责 |
|------|------|
| `lib/organisms/sidebar/sidebar_controller.dart` | 展开状态、键盘导航、可见节点列表、type-to-select |
| `lib/organisms/sidebar/sidebar_search_field.dart` | 搜索框 UI + onChanged 回调 |

`SidebarController` 不依赖 `BuildContext`，方便单元测试。

#### 验收标准

- `SidebarWidget` 行数 < 800
- `SidebarController` 覆盖 widget 测试或单元测试
- 键盘导航、展开持久化行为与拆分前一致

---

### 3.5 侧边栏搜索重建优化

#### 问题

```dart
SidebarTree(
  key: ValueKey('sidebar_$_searchQuery'),
  ...
)
```

每次搜索输入都会替换 `SidebarTree` 的 key，导致整棵树 dispose/create，状态（如滚动位置、内部 hover）丢失。

#### 方案

使用稳定 key，搜索过滤在 `SidebarTree` 内部完成：

```dart
// SidebarWidget
Expanded(
  child: SidebarTree(
    key: const ValueKey('sidebar_tree'),
    searchQuery: _searchQuery,
    ...
  ),
)
```

`SidebarTree` 内部：

```dart
class SidebarTree extends StatelessWidget {
  final String searchQuery;
  ...

  @override
  Widget build(BuildContext context) {
    final visibleNodes = _filterNodes(searchQuery);
    return ListView.builder(...);
  }
}
```

滚动位置由外部传入的 `ScrollController` 维持。

#### 验收标准

- 搜索输入时 `SidebarTree` 不发生 dispose/create
- 搜索过滤结果正确，widget 测试断言过滤前后节点数量

---

### 3.6 编辑/结果分栏魔法数收敛

#### 问题
`MainWorkspace._buildMainContent` 中：

```dart
final fixedHeight = AppDesignSystem.tabBarHeight + breadcrumbH + 1.0;
```

`+1.0` 是为了 `TabsBarWidget` 底部的 1px 分隔线，依赖注释维护。

#### 方案

1. 在 `AppDesignSystem` 中新增：

```dart
static const double tabBarDividerHeight = 1.0;
```

2. `TabsBarWidget` 将分隔线画在自身高度预算内，或对外暴露：

```dart
static double totalHeight(bool hasBreadcrumb) =>
    AppDesignSystem.tabBarHeight + (hasBreadcrumb ? BreadcrumbBar.height : 0) + AppDesignSystem.tabBarDividerHeight;
```

3. `MainWorkspace` 直接调用上述工具方法。

#### 验收标准

- `MainWorkspace` 中无硬编码 `+1.0`
- 调整 `tabBarHeight` 后布局行为仍可预测

---

### 3.7 AI 迷你 FAB 位置规范化

#### 问题

```dart
Positioned(
  right: 24,
  bottom: 48,
  child: AiMiniFab(...),
)
```

`bottom: 48` 是任意值，可能与 status bar 或 snackbar 重叠。

#### 方案

定义常量并考虑安全边距：

```dart
// AppDesignSystem
static const double aiFabSize = 56.0;
static const double aiFabRightOffset = 24.0;
static const double aiFabBottomOffset = statusHeight + space3; // 24 + 12 = 36
```

或者使用 `MediaQuery.viewInsets` + `ScaffoldMessenger` 安全区域动态计算。推荐先用常量，后续根据 snackbar 高度动态调整。

#### 验收标准

- FAB 不再与状态栏文字/图标重叠
- 常量集中在 `AppDesignSystem`

---

### 3.8 状态栏与结果区状态栏信息去重

#### 问题
`StatusBarWidget._buildLastExecutionSummary` 与 `EditorResultsSplit._ExecutionStatusBar` 都显示「行数 · 耗时」，用户可能分不清两者差异。

#### 方案

明确分工：

| 组件 | 显示内容 | 触发条件 |
|------|---------|---------|
| `ExecutionStatusBar`（结果区底部） | 当前子标签的语句级成功/错误、行数、耗时 | 每次查询结果变化 |
| `StatusBarWidget`（全局底部） | 当前 Tab 的汇总：总语句数、总行数、总耗时 | 保留，但仅在空间充足时显示 |

当右侧面板较多时，`StatusBarWidget` 可隐藏执行摘要，只保留连接状态，避免底部信息过载。

#### 验收标准

- `StatusBarWidget` 在宽度不足时优雅截断或隐藏执行摘要
- tooltip 说明「当前 Tab 汇总」与「当前结果子标签」的区别

---

### 3.9 WelcomeScreen 副标题国际化

#### 问题

```dart
Text('AI-enhanced database management', ...)
```

硬编码英文，未走 `AppLocalizations`。

#### 方案

1. 在 `app_en.arb` 及所有语言 ARB 中新增 `welcomeSubtitle`
2. 替换为：

```dart
Text(l10n.welcomeSubtitle, ...)
```

#### 验收标准

- 无硬编码英文用户可见文本
- `flutter gen-l10n` 后各语言文件生成正确

---

## 四、实施计划

### 4.1 阶段划分

> ⓘ 实际实施状态见顶部「实施进度」。本表为原始 Phase 规划，实际按节推进、低风险先行，未严格遵循此顺序。

| 阶段 | 内容 | 预计影响文件 | 优先级 |
|------|------|-------------|--------|
| Phase 1 | HomeScreen Stack 拆层、右侧面板共存策略 | `home_screen.dart` + 新增 `templates/home_layers/*` | P0 |
| Phase 2 | 响应式断点统一、AI FAB 位置规范化 | `design_system.dart`、`responsive_helper.dart`、`home_screen.dart`、`ai_mini_fab.dart` | P0 |
| Phase 3 | SidebarWidget 拆分 + 搜索重建优化 | `sidebar_widget.dart` + 新增 `sidebar_controller.dart`、`sidebar_search_field.dart`、`sidebar_tree.dart` | P1 |
| Phase 4 | 编辑/结果分栏魔法数收敛、状态栏信息去重 | `main_workspace.dart`、`tabs_bar_widget.dart`、`editor_results_split.dart`、`status_bar_widget.dart` | P1 |
| Phase 5 | WelcomeScreen 国际化 | `welcome_screen.dart`、ARB 文件 | P2 |

### 4.2 依赖关系

```
Phase 2 响应式常量
    ↓
Phase 1 右侧面板共存策略（依赖 breakpoint 常量）
    ↓
Phase 3 Sidebar 拆分（可独立，但建议在其后进行）
    ↓
Phase 4 分栏与状态栏细节
    ↓
Phase 5 国际化
```

---

## 五、验证方案

### 5.1 单元/widget 测试

| 测试目标 | 类型 | 关键断言 |
|----------|------|---------|
| HomeScreen layer 显隐 | widget | AI 浮层打开时隐藏底层 workspace；执行中心浮动时 scrim 存在 |
| 右侧面板宽度保护 | widget | 给定 1024px 宽度，AI + EC + sidebar 同时打开时 editor ≥ 480px |
| 侧边栏搜索 | widget | 输入搜索词后 `SidebarTree` key 不变，节点数量变化 |
| 响应式断点 | widget | 宽度 899px 时 sidebar 折叠，901px 时展开 |
| SidebarController | unit | 键盘导航、展开状态持久化、type-to-select |

### 5.2 人工验证点

- 暗色/亮色主题下分隔线可见性
- 最小窗口尺寸（1024×768）下各面板无 overflow
- 长连接名/数据库名在顶部栏、状态栏的截断与 tooltip
- AI 浮层拖拽缩放后重新打开位置是否正确恢复

---

## 六、风险与回滚

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| HomeScreen 拆层后对话框/Provider 上下文丢失 | 中 | 每个 layer 内部继续使用 `context.read/showDialog`，不依赖 HomeScreen 的 context |
| SidebarController 拆分后键盘导航回归 | 中 | 保留现有 `_handleTreeKeyEvent` 逻辑，先复制再重构，配套完整 widget 测试 |
| 右侧面板自动切换形态干扰用户习惯 | 低 | 增加「记住我的选择」偏好，auto-managed 状态仅在不冲突时生效 |
| 响应式断点改动影响既有测试 | 低 | 全量 `flutter test` 后根据失败测试调整断言 |
| ARB 变更导致生成文件冲突 | 低 | 执行 `flutter gen-l10n` 并提交生成文件 |

---

## 七、参考文档

- `docs/refactoring/layout_review.md`（2026-06-09 历史审查）
- `docs/architecture/ui-redesign-minimalist-spec.md`
- `docs/test/unified_test_spec.md`
