# DbMaster UI Redesign - 现代化极简设计稿

> 版本：v1.0  
> 日期：2026-04-15  
> 风格方向：Modern Minimalist / Clean Tech（参考 Linear、Cursor、Raycast）

---

## 1. 设计愿景与核心原则

### 当前问题诊断

| 问题 | 现状 | 改进目标 |
|------|------|----------|
| 色彩偏色 | 主背景 #1a1f2e 带有明显蓝紫偏色，长时间使用易疲劳 | 转为中性深灰，降低饱和度 |
| 边框过多 | 大量使用 1px 实线边框分割区域 | 用留白+微妙背景色差替代硬边框 |
| 圆角不统一 | 混合 4px/8px/16px，缺乏一致性 | 统一 8px/12px 两级圆角系统 |
| 视觉厚重 | 卡片、按钮、面板都有明显边框和阴影 | 采用"浮层感"更弱、更扁平的处理 |
| 信息密度过高 | 各区域间距紧凑，缺乏呼吸感 | 增加内边距，强化内容焦点 |

### 新设计原则

1. **减法优先** - 每减少一条边框、一种颜色，界面就干净一分
2. **内容为王** - SQL 代码、数据表格、查询结果应是视觉焦点，UI 框架后退
3. **中性基调** - 用 Zinc/Gray 中性色取代蓝紫色调，让品牌色（Cyan/Blue）更突出
4. **一致性 > 创新** - 统一间距、圆角、动效规则，建立可预测的使用体验

---

## 2. 色彩系统重设计

### 2.1 深色模式（主推荐）

深色模式是 DbMaster 的主力场景，采用 **Zinc 950 ~ Zinc 800** 作为基调，彻底消除蓝紫偏色。

```dart
// 背景层级
static const Color bgPrimary     = Color(0xFF09090b);   // Zinc-950  最底层
static const Color bgSecondary   = Color(0xFF18181b);   // Zinc-900  侧边栏、面板
static const Color bgTertiary    = Color(0xFF27272a);   // Zinc-800  卡片、输入框、悬停
static const Color bgQuaternary  = Color(0xFF3f3f46);   // Zinc-700  边框、分隔线、禁用

// 文本层级
static const Color textPrimary   = Color(0xFFfafafa);   // Zinc-50   标题、主文本
static const Color textSecondary = Color(0xFFa1a1aa);   // Zinc-400  描述、标签
static const Color textTertiary  = Color(0xFF71717a);   // Zinc-500  占位符、辅助文字
static const Color textDisabled  = Color(0xFF52525b);   // Zinc-600  禁用状态

// 品牌色（科技青蓝）
static const Color accentPrimary = Color(0xFF0ea5e9);   // Sky-500   主按钮、链接、高亮
static const Color accentHover   = Color(0xFF38bdf8);   // Sky-400   悬停状态
static const Color accentSubtle  = Color(0xFF0ea5e9);   // Sky-500/15 背景高亮

// 语义色
static const Color success = Color(0xFF22c55e);   // Green-500
static const Color warning = Color(0xFFf59e0b);   // Amber-500
static const Color error   = Color(0xFFef4444);   // Red-500
static const Color info    = Color(0xFF06b6d4);   // Cyan-500
```

### 2.2 浅色模式（备选）

```dart
static const Color bgPrimary     = Color(0xFFffffff);   // White
static const Color bgSecondary   = Color(0xFFfafafa);   // Zinc-50
static const Color bgTertiary    = Color(0xFFf4f4f5);   // Zinc-100
static const Color bgQuaternary  = Color(0xFFe4e4e7);   // Zinc-200

static const Color textPrimary   = Color(0xFF18181b);   // Zinc-900
static const Color textSecondary = Color(0xFF71717a);   // Zinc-500
static const Color textTertiary  = Color(0xFFa1a1aa);   // Zinc-400
```

### 2.3 数据库类型色（保留，微调饱和度）

| 数据库 | 颜色 | Hex |
|--------|------|-----|
| MySQL | 海洋蓝 | #00758F |
| PostgreSQL | 深蓝 | #336791 |
| MongoDB | 鲜绿 | #4DB33D |
| Redis | 珊瑚红 | #DC382D |
| Doris | 天蓝 | #2B6F9F |

---

## 3. 字体系统

### 3.1 字体选择

采用 **Inter + JetBrains Mono** 组合，这是开发者工具的黄金标准：

- **Inter**：所有 UI 文本（标题、正文、标签）
- **JetBrains Mono**：SQL 编辑器、代码片段、查询结果中的代码数据

```yaml
# pubspec.yaml 中添加
dependencies:
  google_fonts: ^6.1.0
```

### 3.2 字号规范

| 级别 | 字号 | 字重 | 行高 | 用途 |
|------|------|------|------|------|
| Display | 24px | Bold (700) | 1.2 | 欢迎页大标题 |
| H1 | 18px | Semibold (600) | 1.3 | 对话框标题、面板标题 |
| H2 | 15px | Medium (500) | 1.4 | 卡片标题、区域标题 |
| H3 | 13px | Medium (500) | 1.4 | 小标题、列表分组 |
| Body | 13px | Regular (400) | 1.5 | 正文、描述文本 |
| BodySmall | 12px | Regular (400) | 1.5 | 辅助说明、元信息 |
| Caption | 11px | Medium (500) | 1.4 | 标签、状态文字、快捷键 |
| Code | 13px | Regular (400) | 1.6 | SQL 代码、查询结果 |

> 注：当前设计系统使用 11px~48px 的跨度，新版收紧到 11px~24px，更符合桌面工具的阅读距离。

---

## 4. 间距系统

保持 4px 基准网格，但**增加整体呼吸感**：

```dart
static const double space1  = 4.0;   // 微间距
static const double space2  = 8.0;   // 紧凑内边距
static const double space3  = 12.0;  // 标准内边距
static const double space4  = 16.0;  // 卡片内边距
static const double space5  = 20.0;  // 区域间距
static const double space6  = 24.0;  // 面板间距
static const double space8  = 32.0;  // 大模块间距
static const double space10 = 40.0;  // 页面级间距
```

### 应用规则

- **卡片/面板内边距**：16px（space4）
- **按钮内边距**：水平 12px，垂直 6px
- **列表项高度**：32px（紧凑）/ 40px（标准）
- **区域之间**：0px 边框 + 16~24px 内边距
- **树形节点缩进**：16px（原 20px 缩小）

---

## 5. 圆角系统

从三级圆角简化为**两级圆角**，决策更清晰：

```dart
static const double radiusSm = 6.0;   // 按钮、输入框、标签、小卡片
static const double radiusMd = 10.0;  // 面板、对话框、大卡片
```

- 取消 `radiusXs(4px)` 和 `radiusLg(16px)`
- 所有交互元素统一 6px
- 所有容器元素统一 10px
- 完全圆形（头像、状态点）使用 `Radius.circular(999)`

---

## 6. 阴影与层级

新版大幅减少阴影使用，采用**背景色对比**表达层级：

```dart
// 仅用于：下拉菜单、Tooltip、浮层面板
static const List<BoxShadow> shadowFloat = [
  BoxShadow(
    color: Color(0x26000000),  // 15% 黑
    offset: Offset(0, 4),
    blurRadius: 12,
    spreadRadius: -2,
  ),
];

// 仅用于：对话框、模态框
static const List<BoxShadow> shadowModal = [
  BoxShadow(
    color: Color(0x40000000),  // 25% 黑
    offset: Offset(0, 16),
    blurRadius: 40,
    spreadRadius: -6,
  ),
];
```

**去阴影化原则**：
- 卡片不使用阴影，用 `bgSecondary` 或 `bgTertiary` 背景色即可
- 按钮不使用阴影，用悬停背景色变化表达状态
- 仅浮层组件（Dropdown、Menu、Dialog）使用阴影

---

## 7. 组件规范重设计

### 7.1 按钮（Button）

#### Primary Button
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: accentPrimary,
    borderRadius: BorderRadius.circular(6),
  ),
  child: Text('执行', style: TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Colors.white,
  )),
)
```
- 悬停：`accentHover`
- 按下：`accentPrimary.withOpacity(0.9)`
- 禁用：`bgQuaternary` 背景 + `textDisabled` 文字

#### Secondary Button
- 背景：`bgTertiary`
- 边框：**无边框**
- 悬停：`bgQuaternary`

#### Ghost Button
- 背景：透明
- 悬停：`bgTertiary`

### 7.2 输入框（Input）

```dart
InputDecoration(
  filled: true,
  fillColor: bgTertiary,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide.none,  // 默认无边框
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: accentPrimary, width: 1.5),
  ),
  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
)
```

- 默认状态：**无边框**，仅靠背景色区分
- Focus 状态：1.5px 品牌色边框
- Error 状态：1.5px error 色边框

### 7.3 卡片（Card）

```dart
Container(
  decoration: BoxDecoration(
    color: bgSecondary,
    borderRadius: BorderRadius.circular(10),
  ),
  padding: EdgeInsets.all(16),
)
```

- **无阴影、无边框**
- 通过背景色 `bgSecondary` 或 `bgTertiary` 与底层区分
- 嵌套卡片使用 `bgTertiary`

### 7.4 标签页（Tabs）

采用 **Pill 风格** 或 **底部高亮** 的极简标签：

```dart
// 推荐：底部 2px 高亮指示器
Container(
  height: 32,
  padding: EdgeInsets.symmetric(horizontal: 12),
  child: Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Text('Query 1', style: TextStyle(
        fontSize: 12,
        color: isActive ? textPrimary : textTertiary,
      )),
      SizedBox(height: 6),
      Container(
        height: 2,
        width: double.infinity,
        color: isActive ? accentPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(1),
      ),
    ],
  ),
)
```

- 取消 Tab 背景色块
- 用底部细线和文字颜色变化表达选中状态
- 关闭按钮仅在悬停时显示

### 7.5 侧边栏（Sidebar）

#### 视觉规范
- 宽度：240px（展开）/ 44px（折叠）
- 背景：`bgSecondary`
- **与主区域之间：1px 分隔线改为 0px**，改用背景色差自然分割
- 树节点高度：28px
- 节点悬停：`bgTertiary` 背景，6px 圆角
- 节点选中：`accentPrimary.withOpacity(0.12)` 背景 + `accentPrimary` 文字

#### 头部
```dart
Container(
  height: 44,
  padding: EdgeInsets.symmetric(horizontal: 12),
  child: Row(
    children: [
      Icon(Icons.storage, size: 18, color: textSecondary),
      SizedBox(width: 8),
      Text('Connections', style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      )),
    ],
  ),
)
```

- 标题使用 `textSecondary`，弱化存在感
- 操作按钮（+、折叠）使用 Ghost 样式

### 7.6 表格（Data Table）

```dart
DataTable(
  headingRowColor: MaterialStateProperty.all(bgSecondary),
  dataRowHeight: 36,
  headingRowHeight: 32,
  dividerThickness: 0,  // 取消行分隔线
  // 行悬停用 bgTertiary
)
```

- **取消行与行之间的分隔线**
- 表头背景：`bgSecondary`
- 表体背景：`bgPrimary`
- 行悬停：`bgTertiary`
- 单元格内边距：水平 12px，垂直 8px
- 表头文字：12px / `textSecondary` / Medium
- 单元格文字：13px / `textPrimary` / Regular
- 选中行：左侧 2px `accentPrimary` 指示条 + `accentPrimary.withOpacity(0.08)` 背景

---

## 8. 页面布局重设计

### 8.1 主工作区结构

当前结构：
```
[Header 52px]
[Divider 1px]
[Sidebar | Resizer | Workspace | AI Panel]
[Divider 1px]
[StatusBar 28px]
```

新结构：
```
[Header 44px]        ← 高度从 52 减到 44，更紧凑
[Sidebar | Workspace | AI Panel]
[StatusBar 26px]     ← 底部状态栏融入主背景
```

**关键变化：**
1. **移除 Header 与主内容之间的分隔线**，用背景色差（Header: bgSecondary, Workspace: bgPrimary）自然分割
2. **Sidebar 与 Workspace 之间移除分隔线**
3. **StatusBar 不再用顶部分隔线**，而是直接作为底部条

### 8.2 Header 重设计

```dart
Container(
  height: 44,
  color: bgSecondary,
  padding: EdgeInsets.symmetric(horizontal: 12),
  child: Row(
    children: [
      // Logo / App Name
      Row(
        children: [
          Icon(Icons.storage, size: 18, color: accentPrimary),
          SizedBox(width: 8),
          Text('DbMaster', style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          )),
        ],
      ),
      Spacer(),
      // 核心操作按钮组（Ghost 样式）
      Row(
        children: [
          _HeaderButton(icon: Icons.add, label: 'New Connection'),
          _HeaderButton(icon: Icons.play_arrow, label: 'Run'),
          _HeaderButton(icon: Icons.smart_toy, label: 'AI'),
          _HeaderButton(icon: Icons.history, label: 'History'),
        ],
      ),
      Spacer(),
      // 右侧：设置、主题切换、用户头像
      Row(
        children: [
          IconButton(icon: Icons.settings_outlined, ...),
          IconButton(icon: Icons.dark_mode_outlined, ...),
          UserAvatar(size: 24),
        ],
      ),
    ],
  ),
)
```

**设计要点：**
- 高度从 52px 降至 44px
- 按钮从实心/描边改为 **Ghost 图标+文字** 组合
- 增加按钮间距（8px）
- 使用 `outline` 风格图标替代 `filled` 风格

### 8.3 欢迎页（Welcome Screen）

当前是居中大图标 + 大标题，新版采用更精致的中心构图：

```dart
Container(
  color: bgPrimary,
  child: Center(
    child: Container(
      width: 480,
      padding: EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: bgSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo（大）
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accentPrimary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.storage, size: 32, color: accentPrimary),
          ),
          SizedBox(height: 24),
          Text('DbMaster', style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          )),
          SizedBox(height: 8),
          Text(
            'AI-enhanced database management',
            style: TextStyle(fontSize: 14, color: textTertiary),
          ),
          SizedBox(height: 32),
          // 主按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onNewConnection,
              icon: Icon(Icons.add, size: 18),
              label: Text('New Connection'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentPrimary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          SizedBox(height: 12),
          // 次要按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenConnectionManager,
              icon: Icon(Icons.hub, size: 18),
              label: Text('Manage Connections'),
              style: OutlinedButton.styleFrom(
                foregroundColor: textSecondary,
                side: BorderSide.none,
                backgroundColor: bgTertiary,
                padding: EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
          SizedBox(height: 32),
          // 最近连接
          if (savedConnections.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Recent', style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textSecondary,
              )),
            ),
            SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: savedConnections.map((conn) {
                return ActionChip(
                  avatar: _DbIcon(conn.type, size: 14),
                  label: Text(conn.name, style: TextStyle(fontSize: 12)),
                  onPressed: () => connect(conn),
                  backgroundColor: bgTertiary,
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    ),
  ),
)
```

### 8.4 SQL 编辑器区

编辑器是核心使用场景，新版强调**沉浸式编码体验**：

```dart
Container(
  color: bgPrimary,
  child: Column(
    children: [
      // 工具栏 - 极简
      Container(
        height: 36,
        color: bgSecondary,
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _ToolbarButton(icon: Icons.play_arrow, tooltip: 'Run (⌘+Enter)'),
            _ToolbarButton(icon: Icons.format_align_left, tooltip: 'Format'),
            _ToolbarButton(icon: Icons.content_copy, tooltip: 'Copy'),
            VerticalDivider(width: 16, indent: 8, endIndent: 8),
            _ToolbarButton(icon: Icons.save, tooltip: 'Save'),
            Spacer(),
            // 当前连接信息
            Row(
              children: [
                _DbIcon('mysql', size: 12),
                SizedBox(width: 6),
                Text('localhost / mydb', style: TextStyle(
                  fontSize: 11,
                  color: textTertiary,
                )),
              ],
            ),
          ],
        ),
      ),
      // 编辑器主体
      Expanded(
        child: Container(
          color: bgPrimary,
          padding: EdgeInsets.all(12),
          child: EnhancedSqlEditor(),
        ),
      ),
    ],
  ),
)
```

**设计要点：**
- 编辑器背景 = `bgPrimary`（最底层）
- 工具栏高度从 42px 减到 36px
- 工具栏按钮使用纯图标（无文字），带 Tooltip
- 连接信息右对齐，弱化显示
- SQL 高亮配色需要同步更新为更柔和的色调

### 8.5 结果区（Results）

```dart
Container(
  color: bgSecondary,
  child: Column(
    children: [
      // 结果标签栏
      Container(
        height: 32,
        color: bgSecondary,
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _ResultTab(label: 'Grid', isActive: true),
            _ResultTab(label: 'JSON'),
            _ResultTab(label: 'Messages'),
            Spacer(),
            Text('1,234 rows · 45ms', style: TextStyle(
              fontSize: 11,
              color: textTertiary,
            )),
          ],
        ),
      ),
      // 结果内容
      Expanded(child: VirtualizedDataTable()),
    ],
  ),
)
```

### 8.6 AI 面板

AI 面板需要保持科技感但不突兀：

```dart
Container(
  width: 360,
  color: bgSecondary,
  child: Column(
    children: [
      // AI Panel Header
      Container(
        height: 44,
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: accentPrimary),
            SizedBox(width: 8),
            Text('AI Assistant', style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            )),
            Spacer(),
            IconButton(
              icon: Icon(Icons.settings_outlined, size: 16),
              onPressed: () {},
            ),
          ],
        ),
      ),
      // 消息列表
      Expanded(child: AiMessageList()),
      // 输入框
      Container(
        padding: EdgeInsets.all(12),
        color: bgSecondary,
        child: Container(
          decoration: BoxDecoration(
            color: bgTertiary,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration.collapsed(
                    hintText: 'Ask AI to optimize SQL...',
                    hintStyle: TextStyle(color: textTertiary),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.send, size: 18, color: accentPrimary),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    ],
  ),
)
```

- AI 面板宽度从 380px 缩到 360px
- 输入框采用圆角容器包裹，更像聊天应用
- AI 消息气泡去除复杂边框，改用微妙的背景色区分

---

## 9. 状态栏（Status Bar）

```dart
Container(
  height: 26,
  color: bgSecondary,
  padding: EdgeInsets.symmetric(horizontal: 12),
  child: Row(
    children: [
      // 连接状态
      Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: success,
            ),
          ),
          SizedBox(width: 6),
          Text('Connected', style: TextStyle(
            fontSize: 11,
            color: textSecondary,
          )),
        ],
      ),
      Spacer(),
      // 右侧信息
      Row(
        children: [
          Text('MySQL 8.0.32', style: TextStyle(
            fontSize: 11,
            color: textTertiary,
          )),
          SizedBox(width: 16),
          Text('UTF-8', style: TextStyle(
            fontSize: 11,
            color: textTertiary,
          )),
        ],
      ),
    ],
  ),
)
```

- 高度从 28px 减到 26px
- 取消顶部边框，直接融入 `bgSecondary`
- 状态指示器从 8px 减到 6px
- 文字全部使用 11px

---

## 10. 对话框规范

所有对话框统一规范：

```dart
Dialog(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
  ),
  backgroundColor: bgSecondary,
  child: Container(
    width: 480,
    padding: EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text('Dialog Title', style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        )),
        SizedBox(height: 16),
        // 内容
        Flexible(child: ...),
        SizedBox(height: 24),
        // 操作按钮（右对齐）
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {},
              child: Text('Cancel', style: TextStyle(color: textSecondary)),
            ),
            SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {},
              child: Text('Confirm'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
)
```

- 圆角：10px
- 内边距：24px
- 标题：16px / Semibold
- 内容区与按钮区间距：24px
- 按钮组右对齐
- **取消对话框的边框线**

---

## 11. 动画与微交互

### 动效规范

```dart
// 快速反馈（按钮按下、颜色变化）
static const Duration durationFast = Duration(milliseconds: 100);

// 标准过渡（悬停、展开）
static const Duration durationNormal = Duration(milliseconds: 200);

// 页面/面板切换
static const Duration durationSlow = Duration(milliseconds: 300);

// 缓动曲线
static const Curve curveDefault = Curves.easeInOut;
static const Curve curveEnter = Curves.easeOutCubic;
static const Curve curveExit = Curves.easeInCubic;
```

### 微交互清单

| 场景 | 效果 |
|------|------|
| 按钮悬停 | 背景色变化，200ms |
| 按钮按下 | scale 0.97，100ms |
| 侧边栏折叠/展开 | 宽度动画，300ms easeOutCubic |
| Tab 切换 | 底部指示器滑动，200ms |
| 行悬停 | 背景色变化，150ms |
| 对话框出现 | 从 0.95 scale + 0 opacity 淡入，200ms |
| Toast 出现 | 从顶部滑入 + 淡入，200ms |
| AI 消息出现 | 从底部滑入 + 淡入，300ms |

---

## 12. 图标规范

### 图标风格

- **统一使用 outline 风格**（线条图标）
- 笔画粗细：1.5px 感知（Flutter `Icons.xxx_outlined` 系列）
- 默认尺寸：18px（工具栏）/ 16px（列表）/ 14px（标签）/ 20px（空状态）
- 颜色规则：
  - 默认：`textSecondary`
  - 悬停/激活：`textPrimary`
  - 品牌/功能：`accentPrimary`
  - 禁用：`textDisabled`

### 推荐图标替换映射

| 场景 | 当前 | 建议替换为 |
|------|------|-----------|
| 新建连接 | `Icons.add` | `Icons.add_rounded` 或保持 |
| 设置 | `Icons.settings` | `Icons.settings_outlined` |
| 运行 | `Icons.play_arrow` | `Icons.play_arrow_outlined` |
| 历史 | `Icons.history` | `Icons.history_outlined` |
| 数据库 | `Icons.storage` | `Icons.storage_outlined` |
| 表格 | `Icons.table_chart` | `Icons.table_chart_outlined` |
| AI | `Icons.smart_toy` | `Icons.auto_awesome` |

---

## 13. 空状态（Empty State）

```dart
Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.inbox_outlined, size: 48, color: textTertiary),
      SizedBox(height: 16),
      Text('No data to display', style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: textSecondary,
      )),
      SizedBox(height: 4),
      Text('Run a query to see results here', style: TextStyle(
        fontSize: 13,
        color: textTertiary,
      )),
    ],
  ),
)
```

- 图标从 48~80px 统一为 48px
- 标题：14px / Medium / `textSecondary`
- 描述：13px / Regular / `textTertiary`
- 不使用 Primary 按钮色，保持空状态的"安静"

---

## 14. 实现优先级建议

由于 UI 重设计涉及范围较广，建议分阶段实施：

### Phase 1：设计系统底层（1-2 天）
- [ ] 更新 `design_system.dart` 新色彩、间距、圆角、字体
- [ ] 重构 `app_theme.dart` 的 `darkTheme` / `lightTheme`
- [ ] 更新 `app_colors.dart` 的 `ThemeColors`

### Phase 2：原子组件（2-3 天）
- [ ] 重写 `app_button.dart`
- [ ] 重写 `app_card.dart`
- [ ] 重写 `app_header.dart`
- [ ] 重写 `app_loading.dart`
- [ ] 重写 `empty_state_widget.dart`

### Phase 3：关键页面布局（3-4 天）
- [ ] `welcome_screen.dart`
- [ ] `home_screen.dart` + `main_workspace.dart`
- [ ] `sidebar_widget.dart` 及子组件
- [ ] `tabs_bar_widget.dart`
- [ ] `status_bar_widget.dart`

### Phase 4：功能区域（4-5 天）
- [ ] 编辑器区域（`query_editor_widget.dart`, `enhanced_sql_editor.dart`）
- [ ] 结果区域（`results_widget.dart`, `virtualized_data_table.dart`）
- [ ] AI 面板（`ai_panel_widget.dart`, `ai_message_item.dart`）
- [ ] 对话框统一（`connection_dialog.dart`, `settings_dialog.dart` 等）

### Phase 5：细节打磨（2-3 天）
- [ ] 图标全面替换为 outline 风格
- [ ] 动效统一检查
- [ ] 浅色主题完整测试
- [ ] 响应式布局测试

---

## 15. 设计稿总结

### 关键数字

| 设计元素 | 旧值 | 新值 |
|----------|------|------|
| 主背景 | `#1a1f2e` (蓝紫深) | `#09090b` (中性极深) |
| 面板背景 | `#242b3d` | `#18181b` |
| 品牌色 | `#4a9eed` (亮蓝) | `#0ea5e9` (天空蓝) |
| 标签页风格 | 背景块高亮 | 底部细线指示器 |
| 按钮圆角 | 4px | 6px |
| 卡片圆角 | 8px/16px | 10px |
| 表格分隔线 | 1px 实线 | 无边框，纯悬停反馈 |
| 边框使用 | 大量 | 极少，Focus/Error 除外 |
| Header 高度 | 52px | 44px |
| 工具栏高度 | 42px | 36px |
| 状态栏高度 | 28px | 26px |
| 主字号范围 | 11~48px | 11~24px |

### 一句话定义

> **一个更干净、更中性、更克制的 DbMaster —— 让 SQL 代码和数据表格成为绝对主角，UI 框架隐入背景。**

---

*设计稿完成。如需调整任何部分（如倾向浅色主题、想要更大圆角、或保留某些现有元素），请告知，我可以立即修订。*
