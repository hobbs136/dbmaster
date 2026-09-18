# DbMaster UI 与配色改进方案

> 目标：统一冷暖色温、降低视觉噪音、强化信息层级、建立可维护的组件/交互规范。
> 适用范围：`lib/theme/`、`lib/screens/`、`lib/templates/`、`lib/organisms/`、`lib/atoms/`。
> 配套设计稿：见 `dbmaster-design-audit.design`（诊断报告、冷专业方向、布局重构、组件交互细节四页）。

---

## 1. 设计原则

1. **冷专业方向**：整体色温统一为 Slate 冷中性，品牌色使用靛蓝，避免暖白与冷蓝冲突。
2. **单一真相源**：所有颜色必须来自 `Theme.of(context).colorScheme` 或项目 token，禁止硬编码。
3. **层级优先**：用背景色差（surface/surfaceContainer）定义区域，减少 1px divider。
4. **反馈有度**：成功轻反馈（图标 + 文字），失败重反馈（彩色背景），加载有进度但不打扰。
5. **状态可见**：每个可交互元素必须提供 default / hover / active / selected / disabled / focus 的视觉区分。

---

## 2. 色彩系统重构

### 2.1 当前问题

- 深色主题用 Zinc 冷灰（`#09090b`），亮色主题却用暖白（`#F5F3EF`），冷暖冲突。
- 强调色过多：品牌蓝、AI 紫、数据库类型色、schema 类型色同时竞争注意力。
- 语义色亮暗同值，亮色下 warning 对比度不足。
- 主题消费入口混乱：`Theme.of(context)`、`AppDesignSystem`、硬编码并存。

### 2.2 新的中性色家族

统一使用 Slate 家族，亮暗两套共享同一色相、仅调整明度。

| Token | 亮色 | 暗色 | 用途 |
|-------|------|------|------|
| `background` | `#F8FAFC` | `#0B0F19` | 应用主背景 |
| `surface` | `#FFFFFF` | `#141B2A` | 卡片、面板 |
| `surfaceContainer` | `#F1F5F9` | `#1E293B` | 次级容器、输入框背景 |
| `surfaceContainerHigh` | `#E2E8F0` | `#27354F` | Hover 背景、分隔 |
| `outline` | `#CBD5E1` | `#334155` | 边框、divider |
| `outlineVariant` | `#E2E8F0` | `#1E293B` | 弱分割线 |

### 2.3 品牌色

仅保留一个品牌色家族，移除紫色 accent。

| Token | 值 | 用途 |
|-------|-----|------|
| `primary` | `#3574F0`（亮）/ `#5B91F8`（暗） | 主按钮、链接、选中指示、重点图标 |
| `primaryContainer` | `#EEF4FF` / `#1E3B8A` | 选中项背景、标签页 active 背景 |
| `onPrimary` | `#FFFFFF` | primary 上的文字 |

### 2.4 语义色

语义色需要亮暗两套值，并扩展 `surface` / `muted` 变体。

| Token | 亮色 | 暗色 | 用途 |
|-------|------|------|------|
| `success` | `#16A34A` | `#22C55E` | 成功图标、成功文字 |
| `successContainer` | `#DCFCE7` | `#14532D` | 成功背景（轻） |
| `warning` | `#D97706` | `#F59E0B` | 警告图标、警告文字 |
| `warningContainer` | `#FEF3C7` / 50% | `#78350F` | 警告背景（轻） |
| `error` | `#DC2626` | `#EF4444` | 错误图标、错误文字 |
| `errorContainer` | `#FEE2E2` / 80% | `#7F1D1D` | 错误背景 |
| `info` | `#0891B2` | `#22D3EE` | 信息图标 |

> 注意：亮色下大面积语义背景需要降低 alpha，避免过艳。

### 2.5 数据库类型色

保留数据库品牌色，但仅用于侧边栏图标和小面积标识，不用于主按钮或重点强调。

| 数据库 | 颜色 | 备注 |
|--------|------|------|
| MySQL | `#00758F` | 青 |
| PostgreSQL | `#336791` | 蓝 |
| SQLite | `#003B57` | 深蓝 |
| MongoDB | `#47A248` | 绿 |
| Redis | `#DC382D` | 红 |
| Doris | `#1E6FFF` | 蓝 |
| TDengine | `#3D5A80` | 灰蓝 |
| SQL Server | `#A91D22` | 深红 |

### 2.6 SQL 编辑器配色

提供两套高亮方案：

1. **默认冷主题**：与 Slate 壳体协调，降低饱和度。
2. **Darcula 传统主题**：保留给习惯用户，作为可选项。

冷主题推荐值：

| Token | 值 |
|-------|-----|
| `keyword` | `#5B91F8` |
| `string` | `#16A34A` |
| `comment` | `#64748B` |
| `function` | `#0891B2` |
| `number` | `#D97706` |
| `operator` | `#94A3B8` |

### 2.7 Token 映射实施

在 `lib/theme/design_system.dart` 中新增 `AppColorScheme` 扩展，或在 `app_theme.dart` 中统一映射：

```dart
// 亮色
ColorScheme light = ColorScheme(
  brightness: Brightness.light,
  primary: const Color(0xFF3574F0),
  onPrimary: Colors.white,
  primaryContainer: const Color(0xFFEEF4FF),
  surface: Colors.white,
  surfaceContainer: const Color(0xFFF1F5F9),
  surfaceContainerHigh: const Color(0xFFE2E8F0),
  background: const Color(0xFFF8FAFC),
  outline: const Color(0xFFCBD5E1),
  outlineVariant: const Color(0xFFE2E8F0),
  error: const Color(0xFFDC2626),
  onError: Colors.white,
  // ... 其他语义映射
);

// 暗色
ColorScheme dark = ColorScheme(
  brightness: Brightness.dark,
  primary: const Color(0xFF5B91F8),
  onPrimary: Colors.white,
  primaryContainer: const Color(0xFF1E3B8A),
  surface: const Color(0xFF141B2A),
  surfaceContainer: const Color(0xFF1E293B),
  surfaceContainerHigh: const Color(0xFF27354F),
  background: const Color(0xFF0B0F19),
  outline: const Color(0xFF334155),
  outlineVariant: const Color(0xFF1E293B),
  error: const Color(0xFFEF4444),
  onError: Colors.white,
  // ...
);
```

### 2.8 禁止项

- 禁止在业务代码中硬编码 `Color(0xFF...)`。
- 禁止引入新的 accent 色或强调色。
- 禁止亮色主题使用暖白（`#F5F3EF`、`#F0EDE8`）。
- 禁止语义色亮暗同值。

---

## 3. 布局重构

### 3.1 Header

#### 当前问题
- 按钮过多，平铺在 Header 上。
- 中间用 `Spacer()`，造成大面积真空。

#### 改进方案
- 高度：`44px` → `48px`。
- 左侧：Logo + 连接管理下拉（连接/新建/导入）。
- 中部：全局命令面板搜索条（`⌘K`），占位文字「搜索命令、表、连接…」。
- 右侧：
  - 工具菜单（AI / ER 图 / 性能 / 命令面板）
  - 主题切换
  - 设置
  - 服务器状态徽章

```dart
// 伪代码
AppBar(
  title: Row(
    children: [
      Logo(),
      SizedBox(width: 16),
      ConnectionDropdown(),
      Expanded(
        child: Center(
          child: CommandPaletteSearch(width: 480),
        ),
      ),
      ToolMenu(),
      ThemeToggle(),
      SettingsButton(),
      ServerStatusBadge(),
    ],
  ),
)
```

### 3.2 Sidebar

#### 当前问题
- MySQL Process Panel 动态插入，挤压 Tree 空间。
- 折叠态图标偏小、视觉重心偏上。

#### 改进方案
- 宽度：展开 `240px` 不变，折叠 `48px`。
- 折叠态图标：`18px` → `20px`，垂直居中。
- 结构：
  - Header（搜索 + 过滤）
  - Tree（`flex: 1`，稳定高度）
  - Bottom Panel（Process / Recent / Favorites，默认折叠，固定最大高度 `160px`）
  - Footer（连接状态、数据库类型）

```dart
Column(
  children: [
    SidebarHeader(),
    Expanded(child: SidebarTree()),
    CollapsibleBottomPanel(maxHeight: 160),
    SidebarFooter(),
  ],
)
```

### 3.3 Workspace

#### 当前问题
- 上下分栏时结果区容易被压到不可读。
- Resizer 仅 8px，不易命中。
- Execution Status Bar 成功态视觉过重。

#### 改进方案
- 默认左右分栏，允许切换上下。
- `minPanelWidth`：`200px` → `280px`。
- `minPanelHeight`：`50px` → `120px`。
- Resizer：`8px` → `12px`，hover 变品牌色。
- 成功态：文字 + 图标，无彩色背景。
- 错误态：保留彩色背景。

### 3.4 Execution Center

#### 当前问题
- 从底部向上推 workspace，打断编辑流。

#### 改进方案
- 改为右侧抽屉（`360px` 宽），从右侧滑入。
- 提供「钉住」模式：固定显示，workspace 自适应缩小。
- 提供关闭按钮和 `Esc` 快捷键。

```dart
Scaffold(
  endDrawer: ExecutionCenterDrawer(
    width: 360,
    canPin: true,
  ),
  body: MainWorkspace(),
)
```

### 3.5 Status Bar

- 高度：`26px` → `24px`。
- 背景：使用 `surfaceContainer`。
- 文字：使用 `muted-foreground`。
- 连接状态、行数、查询时间左对齐；编码、主题右对齐。

---

## 4. 组件规范

### 4.1 Button / IconButton

| 状态 | 视觉 |
|------|------|
| default | transparent 或 surfaceContainer 背景 |
| hover | surfaceContainerHigh 背景 |
| active | primaryContainer 背景，primary 前景 |
| disabled | muted-foreground，50% 透明度 |
| focus | 2px primary ring |

过渡：`150ms ease-out`。

### 4.2 Tree Item

| 状态 | 视觉 |
|------|------|
| default | transparent |
| hover | surfaceContainer 背景 |
| selected | primaryContainer 背景，左侧 3px primary 指示条 |
| expanded | 箭头旋转 90°，子项缩进 16px |
| dragging | surfaceContainerHigh + 阴影 |

### 4.3 Tabs

| 状态 | 视觉 |
|------|------|
| active | surface 背景，底部 2px primary 线 |
| inactive | transparent，muted-foreground 文字 |
| hover | surfaceContainer 背景 |
| close hover | error 色 |
| unsaved | 标题右侧 6px primary 圆点 |

### 4.4 Table

- 行高：`40px` → `28px`（高密度）。
- 数字列右对齐，文本列左对齐。
- 斑马纹：使用 `surfaceContainer` 与 `surface` 交替，对比度不超过 1.1:1。
- 表头：sortable hover 显示排序图标，sorted 列使用 primary 指示。
- 等宽字体：`JetBrains Mono`、`Fira Code`、Consolas 回退。

### 4.5 Search Input

- 背景：`surfaceContainer`。
- 聚焦：1px `primary` 边框。
- 空状态：占位文字使用 `muted-foreground`。
- 有结果：显示清除按钮。
- 无结果：显示「无匹配」提示。

### 4.6 Drawer

- 滑入动画：`200ms ease-in-out translateX`。
- 遮罩：`background@50%`，点击关闭。
- Header：标题 + 关闭 + 钉住按钮。
- 内容区：`surface` 背景。

### 4.7 Status Badges

| 状态 | 视觉 |
|------|------|
| online | 绿点 + 文字 |
| offline | 灰点 + 文字 |
| syncing | 蓝点脉冲 + 文字 |
| error | 红点 + 文字 |

---

## 5. 交互规范

### 5.1 反馈轻重

| 场景 | 反馈方式 |
|------|---------|
| 查询成功 | Status Bar 图标 + 文字，2s 后淡出 |
| 查询失败 | Snackbar（errorContainer 背景）+ 重试按钮 |
| 保存连接成功 | 短暂 success toast |
| 删除确认 | Dialog + 二次确认 |
| 长时间操作 | 进度条或 spinner + 可取消 |

### 5.2 过渡时长

| 元素 | 时长 | 缓动 |
|------|------|------|
| 按钮背景 | 150ms | ease-out |
| 抽屉滑入 | 200ms | ease-in-out |
| 面板展开 | 250ms | ease-in-out |
| 状态栏消息淡出 | 2000ms | linear |
| Resizer drag | 100ms | ease-out |
| Tooltip | 100ms | ease-out |

### 5.3 Loading / Empty / Error

- **Loading**：表格行 shimmer 骨架屏；整体 loading 用 circular progress + 遮罩。
- **Empty**：图标 + 说明文字 + 操作按钮（如「新建连接」）。
- **Error**：错误图标 + 说明 + 重试按钮；大面积错误使用 errorContainer 背景。

---

## 6. 代码实施清单

### 6.1 需要修改的文件

| 文件 | 修改内容 |
|------|---------|
| `lib/theme/design_system.dart` | 重新定义 token，移除暖色和硬编码 |
| `lib/theme/app_theme.dart` | 更新 ColorScheme 映射 |
| `lib/theme/app_colors.dart` | 更新 ThemeColors getter |
| `lib/atoms/app_header.dart` | 重构 Header 布局 |
| `lib/organisms/sidebar_widget.dart` | 稳定 Tree 区域，添加 CollapsibleBottomPanel |
| `lib/templates/main_workspace.dart` | 调整分区 |
| `lib/templates/editor_results_split.dart` | 调整 minPanel 尺寸和 resizer |
| `lib/organisms/execution_center_panel.dart` | 改为抽屉 |
| `lib/organisms/execution_status_bar.dart` | 轻反馈 |
| `lib/screens/home_screen.dart` | 移除多余 divider，集成 drawer |
| SQL 高亮文件 | 提供冷主题方案 |

### 6.2 Token 迁移步骤

1. 在 `design_system.dart` 中新增 `AppColorScheme` 或扩展 `ColorScheme`。
2. 逐步替换 `AppDesignSystem` 中的硬编码颜色为 token 引用。
3. 全局搜索 `Color(0xFF...)`，确认所有业务代码都通过 `context.themeColors` 或 `Theme.of(context).colorScheme` 消费。
4. 移除 `accentPurple` 等多余强调色。

### 6.3 Widget 重构步骤

1. **Header**：用 `Row` + `Expanded` 替换 `Spacer`，添加 `CommandPaletteSearch`。
2. **Sidebar**：用 `Column` + `Expanded` + `AnimatedSize` 底部面板替换动态插入。
3. **Workspace**：更新 `EditorResultsSplit` 的 `minPanelWidth/Height` 和 `resizer` 尺寸。
4. **Execution Center**：用 `Scaffold.endDrawer` 或自定义 `Stack` + `AnimatedPositioned` 实现抽屉。
5. **Status Bar**：降低高度，使用 muted 文字。

---

## 7. 验证清单

### 7.1 静态检查

- [ ] `dart analyze lib/` 无新增 warning/error。
- [ ] 无新增硬编码 `Color(0xFF...)`。
- [ ] 无新增 `print()` / `debugPrint()`。
- [ ] 用户可见文本走 `AppLocalizations.of(context)`。

### 7.2 视觉检查

- [ ] 亮色主题背景为 Slate 冷白（`#F8FAFC`），无色温冲突。
- [ ] 暗色主题背景为深蓝灰（`#0B0F19`）。
- [ ] Header 按钮分组清晰，中间搜索条可用。
- [ ] Sidebar Tree 不被底部面板挤压。
- [ ] Workspace 结果区最小高度不低于 120px。
- [ ] Execution Center 抽屉滑入顺畅，不推动 workspace。
- [ ] 成功态为轻反馈，失败态为重反馈。

### 7.3 交互检查

- [ ] 所有按钮有 hover/active 反馈。
- [ ] Tree item 有 selected/hover 状态。
- [ ] Tabs 有 active/inactive/close hover 状态。
- [ ] Resizer hover 变品牌色。
- [ ] 抽屉打开/关闭有 200ms 动画。

### 7.4 测试

- [ ] 更新相关 Widget 测试。
- [ ] 运行 `flutter test` 确保无回归。
- [ ] 如修改 SQL 高亮，补充解析/渲染测试。

---

## 8. 附录：新旧色值对照表

| 用途 | 旧值 | 新值（亮） | 新值（暗） |
|------|------|-----------|-----------|
| 背景 | `#F5F3EF` / `#09090b` | `#F8FAFC` | `#0B0F19` |
| 卡片 | `#FFFFFF` / `#18181b` | `#FFFFFF` | `#141B2A` |
| 输入框背景 | `#F0EDE8` / `#27272a` | `#F1F5F9` | `#1E293B` |
| 主品牌 | `#3574F0` | `#3574F0` | `#5B91F8` |
| AI 紫 | `#8b5cf6` | 移除，改用 primary | 移除 |
| Success | `#22c55e` | `#16A34A` | `#22C55E` |
| Warning | `#f59e0b` | `#D97706` | `#F59E0B` |
| Error | `#ef4444` | `#DC2626` | `#EF4444` |

---

*文档生成时间：2026-08-13*
*配套设计稿：项目根目录 `dbmaster-design-audit.design`*
