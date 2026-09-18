# DbMaster 布局审查报告

> 审查日期：2026-06-09
> 审查范围：整体窗口布局、组件拆分、交互体验、视觉一致性、响应式设计

---

## 一、整体布局架构

```
┌──────────────────────────────────────────────────────┐
│  AppHeader (logo + 操作按钮)                          │
├──────┬──────────────────────────┬────────────────────┤
│      │  TabsBarWidget           │                    │
│      ├──────────────────────────┤                    │
│      │  QueryEditor (上)        │    AI Panel        │
│Sidebar│  ── Resizer ──          │    (可选侧边栏)    │
│      │  ResultSubTabBar         │                    │
│      │  ResultsWidget (下)      │                    │
│      │  ExecutionStatusBar      │                    │
├──────┴──────────────────────────┴────────────────────┤
│  StatusBarWidget (连接状态/服务器信息/任务/版本)       │
└──────────────────────────────────────────────────────┘
 + AI浮层 (Stack上层，全屏模式)
 + AI FAB (右下角浮动按钮)
```

**布局模式**：经典的 IDE 三栏式（侧边栏 | 编辑区 | 辅助面板）。类似 VS Code / DataGrip，是合理的选择。

### 组件树（关键路径）

```
HomeScreen (_HomeScreenState, 1161行)
├── AppHeader (atoms/app_header.dart)
├── Stack
│   ├── Row (底层：主工作区)
│   │   ├── SidebarWidget (organisms/sidebar_widget.dart, 375行)
│   │   ├── SidebarResizer
│   │   ├── Expanded → MainWorkspace (templates/main_workspace.dart, 138行)
│   │   │   ├── TabsBarWidget (organisms/connection/tabs_bar_widget.dart)
│   │   │   └── EditorResultsSplit (templates/editor_results_split.dart)
│   │   │       ├── QueryEditorWidget (IndexedStack)
│   │   │       ├── EditorResultsResizer
│   │   │       └── ResultsWidget + ResultSubTabBar + _ExecutionStatusBar
│   │   └── AiPanelWidget (可选侧边栏模式)
│   ├── AI 浮层 (全屏模式，Stack 上层)
│   └── AI FAB (迷你浮动按钮)
└── StatusBarWidget (底部状态栏, 28px)
```

### 涉及的关键文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/screens/home_screen.dart` | 1161 | 主页面：布局编排、AI 浮层、FAB、对话框、Provider 初始化 |
| `lib/templates/main_workspace.dart` | 138 | 工作区切换逻辑（欢迎页/连接中/工作区） |
| `lib/templates/editor_results_split.dart` | 210 | 编辑器/结果上下分割 |
| `lib/organisms/sidebar_widget.dart` | 375 | 侧边栏：连接树、搜索、数据库导航 |
| `lib/organisms/connection/tabs_bar_widget.dart` | 477 | Query Tab 栏 |
| `lib/organisms/results/results_widget.dart` | ~300 | 查询结果数据表 |
| `lib/organisms/results/result_subtab_bar.dart` | 215 | 结果子标签栏（新增） |
| `lib/organisms/connection/status_bar_widget.dart` | 717 | 底部状态栏 |
| `lib/atoms/app_header.dart` | 135 | 顶部标题栏 |
| `lib/theme/design_system.dart` | ~200 | 设计令牌定义 |

---

## 二、优点 ✅

### 2.1 架构设计

1. **清晰的三面板布局** — 侧边栏 + 工作区 + AI 面板，职责分明，符合 IDE 类应用的经典模式
2. **可拖拽调整大小** — 侧边栏、编辑器/结果分隔、AI 面板宽度都可通过拖拽调整，并持久化到 `LayoutPreferencesProvider`
3. **IndexedStack 管理 Tab** — 切换 Tab 时保持编辑器状态，避免重建
4. **AnimatedSwitcher 过渡** — 欢迎页 → 连接中 → 工作区三个阶段有淡入淡出动画
5. **折叠侧边栏** — 小屏幕（< 900px）或手动折叠时只显示连接图标列表，节省空间
6. **Provider 分层** — `AppProvider` 作为 facade 封装 11 个子 Provider，数据流单向清晰
7. **工作区感知 Tab** — Tab 绑定 connectionId + databaseName，切换连接时 Tab 自动跟随

### 2.2 交互设计

8. **Command Palette** — 支持键盘驱动的命令搜索和执行
9. **右键上下文菜单** — Tab 支持重命名、关闭、复制、关闭其他等操作
10. **AI 面板多模式** — 侧边栏 / 全屏浮层 / 迷你 FAB 三种形态
11. **前后端 Tab 转换按语法拆分** — 一次提交多条 SQL，每条生成独立结果子 Tab
12. **Pin/Unpin 结果** — 结果子 Tab 支持 Pin 操作，下次查询不覆盖

### 2.3 视觉/主题

13. **Design System Token** — `AppDesignSystem` 定义了颜色、间距、圆角、字号等统一令牌
14. **双主题支持** — 暗色/亮色模式，带 8 种主题色
15. **状态指示器动画** — 底部连接状态有脉冲环动画

---

## 三、问题与建议 🔧

### 3.1 架构拆分

#### ~~问题 1：`home_screen.dart` 过于臃肿（1161 行）~~ ✅ 已解决 (2026-06-09)

**原始问题**：`_HomeScreenState` 承担了过多职责——整体布局、AI 浮层管理、FAB 状态、对话框触发、偏移量持久化等。

**解决方案**：将 AI 浮层和 FAB 提取为独立组件，各自管理自己的布局偏移量状态。

**拆分结果**：

| 文件 | 行数 | 职责 |
|------|------|------|
| `lib/screens/home_screen.dart` | 1161 → **561** (-52%) | 整体布局编排、初始化、Provider 监听、对话框触发、命令构建 |
| `lib/organisms/ai_panel/ai_panel_overlay.dart` | **新建** | AI 全屏浮层：拖拽移动、透明度滑块、尺寸调整、快捷键帮助 |
| `lib/organisms/ai_panel/ai_mini_fab.dart` | **新建** | AI 迷你 FAB：拖拽移动、位置持久化 |

**关键改进**：
- 每个组件通过 `LayoutPreferencesProvider` 独立管理自己的偏移量，无需父组件协调
- 组件间通过 `VoidCallback` 通信（`onClose`、`onToggleDock`、`onTap`），耦合度最低
- 原 `_loadLayoutPreferences` / `_saveOverlayOffsets` / `_saveFabOffsets` 从 HomeScreen 中移除
- 零测试回归（169 通过，2 预存失败）

---

#### ~~问题 2：ResultSubTabBar 位置不当~~ ✅ 已解决 (2026-06-09)

**原始问题**：`ResultSubTabBar` 位于 `EditorResultsSplit` 中，但它直接操作 `provider.tab.activeResultIndex`（属于结果展示的内部状态），`EditorResultsSplit` 不应知道"结果有子 Tab"这个细节。

**解决方案**：将 `ResultSubTabBar` 移入 `ResultsWidget` 内部，使其成为结果展示组件的内部实现细节。

**改造前**：
```dart
// EditorResultsSplit
SizedBox(height: resultsHeight, child: Column(children: [
  ResultSubTabBar(),   // ← 在 ResultsWidget 外部
  ResultsWidget(),
  _ExecutionStatusBar(),
]))
// ResultsWidget 内部还有一套独立的 TabBar/TabBarView
```

**改造后**：
```dart
// EditorResultsSplit
SizedBox(height: resultsHeight, child: Column(children: [
  ResultsWidget(),          // ResultSubTabBar 已移入内部
  _ExecutionStatusBar(),    // 保留，因为它是全局摘要
]))
// ResultsWidget 内部结构
//   ├── ResultSubTabBar    ← 批次级标签
//   ├── 工具栏（导出/搜索/AI）
//   └── 内容区（内部 TabBarView 或 Messages 视图）
```

**关键改进**：
- `ResultsWidget` 数据源从 `tab.executionResults` 改为 `provider.tab.activeResults[activeResultIndex].executionResults`，确保与 ResultSubTabBar 选择同步
- `_ExecutionStatusBar` 同步改为从活跃 ResultSubTab 读取数据
- `EditorResultsSplit` 不再 import `result_subtab_bar.dart`
- 零测试回归（2625 passed，13 pre-existing）

---

#### ~~问题 3：Stack 层叠导致主工作区始终构建~~ ✅ 已解决 (2026-06-09)

**原始问题**：AI 浮层全屏时会遮住整个主工作区，但主工作区的 `Row`（侧边栏 + 工作区 + AI 侧边栏）始终在构建，所有 Provider 监听和表格渲染仍在运行——完全浪费。

**解决方案**：用 `if` 条件包裹 `Row`，全屏浮层模式下直接跳过构建：

```dart
Stack(
  children: [
    // 全屏浮层时完全跳过 —— 浮层遮住整个工作区，构建是浪费
    if (!appProvider.aiPanelOpen || !appProvider.aiPanelFullscreen)
      Row(...),          // 侧边栏 + 工作区 + AI 侧边栏
    if (fullscreen)       // AI 全屏浮层
      AiPanelOverlay(...),
    if (!aiOpen)          // 迷你 FAB
      AiMiniFab(...),
  ],
)
```

**三种模式的构建行为**：

| 模式 | Row (主工作区) | AiPanelOverlay | AiMiniFab |
|------|:---:|:---:|:---:|
| 正常（AI 关闭） | ✅ 构建 | — | ✅ 构建 |
| AI 侧边栏模式 | ✅ 构建 | — | — |
| AI 全屏浮层 | ❌ **跳过** | ✅ 构建 | — |

切换回其他模式时 Row 会正常重建——这是用户主动操作，一次性重建代价可接受。

**文件变更**：`lib/screens/home_screen.dart` — 1 行条件包裹 ($\pm$2 行)

---

### 3.2 交互体验

#### ~~问题 4：Tab 栏无溢出处理~~ ✅ 已解决 (2026-06-09)

**原始问题**：`TabsBarWidget` 使用水平 `ListView.builder`，Tab 数量超过屏幕宽度时后面的 Tab 完全不可见。用户打开 5+ 个 Tab 后无法快速跳转到被遮挡的 Tab。

**解决方案**：在 Tab 栏右侧 `+` 按钮左侧添加 `∨` 溢出下拉按钮（对标 VS Code），始终显示（有 Tab 时）。

```
[Tab1] [Tab2] [Tab3] ... [∨] [+]

点击 ∨ → 下拉菜单列出所有 Tab：
  ┌──────────────────────────────────────────┐
  │ ▌ 📄 Query 1       mysql-prod · mydb  [×] │
  │ ▌ 📄 Query 2       mysql-prod · mydb  [×] │  ← 橙色边框 = 当前激活
  │   📄 Query 3       postgres · other  [×] │
  │   ...                                    │
  └──────────────────────────────────────────┘
```

**菜单特性**：
- 左侧 3px 激活指示条（`isActive` 时 `accentPrimary` 色），醒目标识当前 Tab
- 每行显示：保存图标 / 标题 / 数据库名 / 关闭按钮
- 点击行 → 切换到该 Tab **并自动滚动至可视区域**（`ScrollController.animateTo`，200ms ease-out）
- 点击 `×` → 关闭该 Tab（含未保存确认）
- 最小宽度 260px，确保标题可读

**滚动定位算法**：
```dart
// 以 _approxTabWidth=160px 估算 Tab 位置，居中呈现于视口
target = index * 160 - viewportWidth / 2
// clamp 到合法滚动范围
target.clamp(0, maxScrollExtent)
// 200ms ease-out 动画
scrollController.animateTo(target)
```

**架构变化**：
- `TabsBarWidget` 从 `StatelessWidget` 改为 `StatefulWidget`（持有 `ScrollController`）
- `build()` 内嵌 `LayoutBuilder` 获取 viewport 宽度
- `_buildOverflowButton` 从 `static` 改为实例方法，`onSelected` 同时执行 `setActiveTab` + `_scrollToIndex`

---

#### ~~问题 5：编辑器/结果只支持上下分栏~~ ✅ 已解决 (2026-06-09)

**原始问题**：编辑器/结果固定为上下布局，宽屏显示器上浪费横向空间。

**解决方案**：新增 `EditorResultsOrientation` 枚举（`vertical` / `horizontal`），通过切换按钮一键切换。

**架构**：

```
lib/services/layout_preferences_service.dart   → 持久化键 editor_results_orientation
lib/providers/layout_preferences_provider.dart → enum + toggleEditorResultsOrientation()
lib/templates/editor_results_split.dart        → _buildVerticalSplit / _buildHorizontalSplit
lib/molecules/resizer_widgets.dart             → EditorResultsResizer 新增 isHorizontal + orientationToggle
```

**Resizer 上的切换按钮**：
```
上下分栏：
  ┌──────────────────────────────┐
  │        Editor                │
  ├──────────────────────────────┤
  │  ──────── [⇄] ────────       │  ← Resizer 中间悬浮 ⇄ 图标
  ├──────────────────────────────┤
  │        Results               │
  └──────────────────────────────┘

点击 ⇄ → 左右分栏：
  ┌──────────┬───────────────────┐
  │          │                   │
  │ Editor   │ │ [⇅] │ │ Results │  ← ⇅ 图标在垂直分隔条中间
  │          │                   │
  └──────────┴───────────────────┘
```

**文件变更**：4 个文件（service: +13行, provider: +20行, editor_results_split: 重写, resizer_widgets: +50行）

---

#### ~~问题 6：缺少面包屑导航~~ ✅ 已解决 (2026-06-09)

**原始问题**：底部 Tab 只显示 "Query 1" / "Query 2"，没有连接/数据库上下文信息。

**解决方案**：在 Tab 栏和编辑器之间添加一条 26px 高的面包屑栏。

**位置**：
```
┌──────────────────────────────────────────────────────┐
│ [Query 1] [Query 2]                        [+] [∨]  │  ← TabsBarWidget
├──────────────────────────────────────────────────────┤
│ [M] mysql-prod  >  mydb                              │  ← BreadcrumbBar (NEW)
├──────────────────────────────────────────────────────┤
│ SELECT * FROM users ...                              │  ← Editor
```

**特性**：
- 仅在 activeTab 存在且有 connectionId 时渲染
- 左起：[数据库类型徽标] 连接名  >  数据库名
- 徽标颜色与数据库类型对应（M=MySQL蓝, P=PG蓝, Mg=MongoDB绿 等）
- 无 Tab 或无连接时自动隐藏（`SizedBox.shrink()`）

**文件变更**：
- `lib/organisms/connection/breadcrumb_bar.dart` — 新建 (~140行)
- `lib/templates/main_workspace.dart` — 插入 `BreadcrumbBar` + 调整 `fixedHeight`

---

#### ~~问题 7：AI 浮层交互过于复杂~~ ✅ 已解决 (2026-06-09)

**原始问题**：AI 面板三种模式的交互过多——全屏浮层有拖拽移动 + 右下角拖拽调整大小 + 透明度滑块 + 毛玻璃，FAB 可拖拽移动。过量 raw `GestureDetector` 增加了代码复杂度和维护成本。

**简化方案**：

| 功能 | 之前 | 之后 |
|------|------|------|
| 浮层大小 | 右下角拖拽 resize | 3 个预设按钮 **S** / **M** / **L**（45%/65%/85%） |
| 透明度 | 滑块 5%~100% | 固定毛玻璃（blur: 8px, 透明度: 92%） |
| FAB 位置 | 可拖拽移动 + 持久化 | 固定右下角 |
| 偏移量存储 | `setOverlayOffsets` + `setFabOffsets` 6 个字段 | **已弃用**（`@Deprecated`） |

**保留**：
- 浮层拖拽移动（拖拽工具栏移动面板位置）
- `Cmd+Shift+A` 开关、`Cmd+Shift+F` 侧边栏/浮层切换
- 毛玻璃背景效果（固定 blur）

**代码量**：
| 文件 | 之前 | 之后 | 减少 |
|------|:---:|:---:|:---:|
| `ai_panel_overlay.dart` | 618行 | 421行 | **-32%** |
| `ai_mini_fab.dart`（StatelessWidget） | 150行 | 81行 | **-46%** |
| `LayoutPreferencesProvider` | — | 6 个 getter/setter @Deprecated | — |

---

### 3.3 视觉一致性

#### ~~问题 8：分割线使用过多~~ ✅ 已解决 (2026-06-09)

**原始问题**：Sidebar→Workspace 和 Workspace→AI Panel 之间各有一条 1px 竖分割线，共 5 处，违反设计系统"用留白和背景色差替代边框"的哲学。

**解决方案**：移除 2 条面板间竖分割线，保留 2 条水平段分割线（Header 下方 + StatusBar 上方）。

| 分割线 | 位置 | 决策 | 理由 |
|------|------|:--:|------|
| Header → 内容区 | `Container(height: 1)` | 保留 | 明确区域边界 |
| Sidebar → 工作区 | `Container(width: 1)` | **移除** | SidebarResizer 的 grab bar 已提供视觉分隔 |
| 工作区 → AI 面板 | `Container(width: 1)` | **移除** | AiPanelResizer 的 grab bar 已提供视觉分隔 |
| 内容区 → StatusBar | `Container(height: 1)` | 保留 | 明确区域边界 |

**变更**：`lib/screens/home_screen.dart` — 删除 2 个 `Container(width: 1, color: ...)`（-5 行）

---

#### ~~问题 9：间距值硬编码~~ ✅ 已解决 (2026-06-09)

**原始问题**：代码中混用了设计令牌和硬编码数字（`EdgeInsets.symmetric(horizontal: 8, vertical: 4)` 等），违反设计系统一致性。

**解决方案**：

1. 扩展 `AppDesignSystem` 间距令牌（新增 `space0_5`、`space1_5`、`space2_5`）
2. 用 Python 脚本批量替换 `lib/` 下所有 `EdgeInsets` 和 `SizedBox` 中的硬编码值
3. 在 `app_colors.dart` 添加 `export 'design_system.dart'`，使所有导入 `app_colors` 的文件自动获得 `AppDesignSystem` 引用

**完整令牌映射**：

| 数值 | 令牌 | 语义 |
|:---:|------|------|
| 2 | `space0_5` | 极小（icon↔文字） |
| 4 | `space1` | XS |
| 6 | `space1_5` | XS-S |
| 8 | `space2` | S |
| 10 | `space2_5` | S-M |
| 12 | `space3` | M |
| 16 | `space4` | L |
| 20 | `space5` | L-XL |
| 24 | `space6` | XL |
| 32 | `space8` | XXL |
| 40 | `space10` | XXXL |

**变更规模**：131 files changed, ~3K insertions（全部机械替换），0 regression

---

#### ~~问题 10：Resizer 组件重复~~ ✅ 已解决 (2026-06-09)

**原始问题**：`SidebarResizer`、`EditorResultsResizer`、`AiPanelResizer` 三个类共享相同的核心逻辑（`MouseRegion` + `GestureDetector` + `AnimatedContainer`），仅 `cursor`、`grabBarSize`、`SizedBox` 尺寸不同。

**解决方案**：合并为单个 `AppResizer`（StatefulWidget），通过构造参数控制行为。

| 使用场景 | 参数 | 效果 |
|------|------|------|
| 侧边栏 | `AppResizer()`（默认） | cursor: resizeColumn, grab: 1×24, width: 12 |
| AI 面板 | `AppResizer()`（默认） | 同上 |
| 上下分栏 | `EditorResultsResizer()` | cursor: resizeRow, grab: 40×3, height: 12, fillCrossAxis |
| 左右分栏 | `EditorResultsResizer(isHorizontal: true)` | cursor: resizeColumn, grab: 3×40, width: 12, fillCrossAxis |

**向后兼容**：`SidebarResizer` 和 `AiPanelResizer` 保留为 `typedef`，`EditorResultsResizer` 保留为 `AppResizer` 子类。零调用方变更。

**代码量**：270 行 → 155 行（-43%），4 个类 → 1 个类 + 1 个子类 + 2 个 typedef。

---

### 3.4 状态栏

#### ~~问题 11：底部状态栏信息过载~~ ✅ 已解决 (2026-06-09)

**原始问题**：`StatusBarWidget` 28px 内塞入连接状态、服务器名、数据库名、字符集、时区、版本号、查询结果统计、任务数和应用版本，小窗口下必然溢出。

**解决方案**：
- charset / 时区 / 版本号 → 移入连接状态的 `Tooltip`（悬停显示）
- 应用版本号 → 移入同一 Tooltip
- 不再需要的辅助类：删除 `_InfoChip`、`_ServerVersionChip`
- 保留：连接状态 + 服务器名 + 数据库名 + READ-ONLY + 任务指示器

**状态栏前后对比**：
```
之前: [● Connected] | [M] mysql-prod | [📦] mydb | [🔒] | [Aa] utf8mb4 | [🕐] UTC+8 | [v8.0.35] ...  [✕ Error] [📊 500] [⏳ 2] [v0.0.1]
之后: [● Connected] · [M] mysql-prod · [📦] mydb · [🔒 READ-ONLY]              [⏳ 2]
      ↑ 悬停 Tooltip: "Charset: utf8mb4 · Timezone: UTC+8 · DbMaster v0.0.1"
```

---

#### ~~问题 12：执行状态栏与底部状态栏信息重复~~ ✅ 已解决 (2026-06-09)

**原始问题**：`_ExecutionStatusBar` 和 `StatusBarWidget` 都显示查询结果行数和错误状态，用户同时看到两份重复信息。

**解决方案**：从底部 `StatusBarWidget` 中移除查询结果统计（`_buildQueryStatus`），保留 `_ExecutionStatusBar` 作为唯一的查询执行摘要显示位置。

- `_ExecutionStatusBar`：专注于**单次执行**摘要（"2 succeeded in 150ms · 500 行"）
- `StatusBarWidget`：专注于**全局**连接状态 + 任务计数

**变更**：`lib/organisms/connection/status_bar_widget.dart` — 删除 `_buildQueryStatus` 方法和相关字段（`resultCount`/`hasError`）

---

### 3.5 响应式设计

#### 问题 13：断点只有 900px 一个

```dart
// home_screen.dart:492
final isSmallScreen = constraints.maxWidth < 900;
```

桌面应用通常需要至少三个断点：

| 断点 | 宽度 | 布局策略 |
|------|------|---------|
| 紧凑 | < 900px | 侧边栏折叠，AI 面板仅浮层模式 |
| 中等 | 900-1200px | 侧边栏展开但较窄（220px），AI 面板可选 |
| 宽敞 | > 1200px | 侧边栏 + 工作区 + AI 面板三者同时可见 |

**建议**：利用已有的 `ResponsiveHelper` 工具类，定义 `LayoutBreakpoints`：

```dart
class LayoutBreakpoints {
  static const double compact = 900;
  static const double medium = 1200;
  static const double wide = 1600;
}
```

在 `medium` 断点上，侧边栏默认 260px；在 `wide` 断点上，侧边栏可以更宽（300px+）并显示更多信息。

---

### 3.6 性能

#### ~~问题 14：Consumer 粒度不够细~~ ✅ 已解决 (2026-06-09)

**原始问题**：多处 `Consumer<AppProvider>` 包裹大块 Widget 树，AppProvider 的 11 个子 Provider 任一 `notifyListeners()` 都触发整个子树重建。

**解决方案**：三处关键优化的 `context.select` 替换：

| 位置 | 原来 | 优化后 | 效果 |
|------|------|--------|------|
| `main_workspace.dart` | `Consumer<AppProvider>` 包裹 AnimatedSwitcher | `context.select` 仅选连接状态 | sidebar/AI/结果变更不再触发整个工作区重建 |
| `sidebar_widget.dart` | `Consumer<AppProvider>` 包裹 SidebarTree | `Selector<AppProvider, String?>` 仅选 `expandedConnectionId` | 查询/结果/AI 变更不再触发侧边栏树重建 |
| `results_widget.dart` | `Consumer<AppProvider>` 包裹数据表 | `context.select` 仅选 (tabId, resultIndex, resultCount) 三元组 | connection/sidebar/AI 变更不再触发数据表重建 |

**关键模式**：
```dart
// 精确选择（只重建需要的）
final resultKey = context.select<AppProvider, (String?, int, int)>(
  (p) => (p.tab.activeTab?.id, p.tab.activeResultIndex, p.tab.activeResults.length),
);
// 非重建读取（已由 select 触发保证数据新鲜）
final provider = context.read<AppProvider>();
```

Dart 3.0 Record 的 value-equality 比较使精确选择无需额外模型类。

---

## 四、总结与优先级

### 按优先级排列

| 优先级 | # | 问题 | 影响范围 | 预估工作量 |
|--------|---|------|---------|-----------|
| ~~🔴 高~~ ✅ | 1 | ~~HomeScreen 1161 行需拆分~~ | 维护性、可读性 | ~~大（3-4h）~~ 已完成 |
| ~~🔴 高~~ ✅ | 4 | ~~Tab 栏无溢出处理~~ | 可用性（多 Tab 场景） | ~~中（2h）~~ 已完成 |
| ~~🟡 中~~ ✅ | 2 | ~~ResultSubTabBar 位置不当~~ | 架构清晰度 | ~~小（0.5h）~~ 已完成 |
| ~~🟡 中~~ ✅ | 5 | ~~编辑器/结果不支持左右分栏~~ | 宽屏用户体验 | ~~中（2h）~~ 已完成 |
| ~~🟡 中~~ ✅ | 9 | ~~间距值硬编码~~ | 视觉一致性 | ~~中（1.5h）~~ 已完成 |
| ~~🟡 中~~ ✅ | 14 | ~~Consumer 粒度不够细~~ | 性能（大型数据库树） | ~~小（0.5h）~~ 已完成 |
| ~~🟢 低~~ ✅ | 3 | ~~AI 浮层全屏时主工作区仍在构建~~ | 性能（全屏浮层场景） | ~~小（0.5h）~~ 已完成 |
| ~~🟢 低~~ ✅ | 7 | ~~AI 浮层交互过于复杂~~ | 代码复杂度、维护性 | ~~中（2h）~~ 已完成 |
| ~~🟢 低~~ ✅ | 10 | ~~Resizer 组件重复~~ | 代码复用 | ~~小（1h）~~ 已完成 |
| ~~🟢 低~~ ✅ | 8 | ~~分割线使用过多~~ | 视觉一致性 | ~~小（0.5h）~~ 已完成 |
| ~~🟢 低~~ ✅ | 11 | ~~状态栏信息过载~~ | 小窗口体验 | ~~小（1h）~~ 已完成 |
| ~~🟢 低~~ ✅ | 12 | ~~执行状态栏与底部状态栏信息重复~~ | 信息架构 | ~~小（0.5h）~~ 已完成 |
| ~~🟢 低~~ ✅ | 6 | ~~缺少面包屑导航~~ | 深度导航体验 | ~~中（1.5h）~~ 已完成 |
| 🟢 低 | 13 | 断点只有 900px | 响应式设计 | 小（1h） |

### 建议实施顺序

1. **第一阶段**（低风险、高收益）：~~间距令牌统一 (#9)~~ ✅ 已完成、~~Resizer 合并 (#10)~~ ✅ 已完成、~~Consumer 粒度优化 (#14)~~ ✅ 已完成
2. **第二阶段**（解决可用性问题）：~~Tab 溢出菜单 (#4)~~ ✅ 已完成、~~状态栏精简 (#11, #12)~~ ✅ 已完成
3. **第三阶段**（架构改进）：~~HomeScreen 拆分 (#1)~~ ✅ 已完成、~~ResultSubTabBar 归位 (#2)~~ ✅ 已完成
4. **第四阶段**（体验增强）：~~左右分栏 (#5)~~ ✅ 已完成、~~AI 浮层简化 (#7)~~ ✅ 已完成、~~面包屑 (#6)~~ ✅ 已完成、多断点 (#13)

---

## 五、未涉及但值得关注的领域

以下领域未在本次审查中深入，但值得后续关注：

1. **键盘导航** — 现有快捷键是否覆盖所有高频操作？Tab 切换、面板聚焦是否可通过键盘完成？
2. **无障碍（A11y）** — Tooltip、语义标签、屏幕阅读器支持
3. **侧边栏虚拟化** — 大数据量表（1000+ 表）时侧边栏树是否卡顿？
4. **窗口状态恢复** — 关闭重开后是否恢复：窗口大小/位置、面板比例、Tab 状态？
5. **Touch 支持** — Surface Pro / iPad 等触屏设备上 Resizer 拖拽是否可用？

---

## 六、Bug 修复记录

### Bug #1：切换 Query Tab 时结果面板显示相同内容 🔧 已修复 (2026-06-09)

**症状**：不同 Query Tab 分别查询不同表，切换 Tab 时结果面板显示相同数据。

**根因**：两个问题叠加导致：

1. **Widget Key 未包含 Tab 标识**（主因）— `ResultTabContent` 的 key 是 `ValueKey('result_$index')`，当 Tab A 和 Tab B 各自有 1 条执行结果时，key 都是 `ValueKey('result_0')`。Flutter 的 element diffing 看到相同 key 就复用旧 element，仅调用 `didUpdateWidget`。如果状态重置不彻底，旧数据就会残留。

2. **`_tabStates` 缓存未随 Tab 切换清理**（次因）— `Map<int, ResultTabState>` 缓存了每个 index 的筛选/排序状态，切换 Tab 后旧 index 的 filter 会污染新 Tab 的数据。

**修复**：

| 文件 | 变更 |
|------|------|
| `lib/organisms/results/results_widget.dart` | (1) Widget key 加入 `tabId`: `ValueKey('result_${tabId}_$index')` (2) 检测 Tab 切换时清空 `_tabStates` 并重建 `TabController` |
| `lib/providers/app_provider.dart` | 删除 `executeCurrentQueryAndRecord` 中重复的 `addResultToTab` / `updateTabExecutionResults` 调用 |

**验证**：`dart analyze lib/` 零错误零警告，`flutter test` 2625 通过零回归。
