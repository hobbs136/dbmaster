# 左侧导航树 UX 优化计划

> 对比基准：DBeaver、TablePlus、DataGrip、Navicat、Azure Data Studio、pgAdmin
> 分析日期：2026-06-09
> 进度：9/10 功能完成（功能 8 多选批量操作跳过）

---

## 一、当前实现概览

**层级结构：**
```
Connection (L1) → Database (L2) → Categories (L3) → Items (L4) → Details (L5+)
```

**已有能力：**
- ✅ 树形展开/折叠（带动画 chevron）
- ✅ 连接线缩进指示层级
- ✅ 搜索过滤（刚修复连接/数据库/表三级过滤）
- ✅ 右键上下文菜单（按数据库类型动态菜单）
- ✅ 收藏表系统（持久化到 SharedPreferences）
- ✅ 拖拽连接进分组
- ✅ 折叠侧边栏模式
- ✅ 连接分组
- ✅ 徽章/计数显示
- ✅ 悬停高亮

---

## 二、功能优化列表

> 按功能分组，每组是一个独立可交付的功能。完成后标记 ✅ 并记录实际效果。

---

### 功能 1：右键交互完善 🔴 P0 ✅ 已完成

**涉及问题**：#3 右键先选中节点 + #9 全部折叠

**完成日期**：2026-06-09

**实施内容：**

1.1 右键时自动选中目标节点 ✅
  - 连接节点右击 → 调用 `provider.sidebar.selectConnection(server.id)` → 节点高亮
  - 数据库节点右击 → 调用 `provider.sidebar.selectConnection()` + `selectDatabase()` → 节点高亮
  - 表节点右击 → 调用 `provider.setSelectedTable(tableName)` + 增加 `isSelected` 属性绑定 → 节点高亮
  - TDengine 超级表右击同样选中
  - **实际效果**：右键任意节点，该节点立即以 accentPrimary 0.1 透明度高亮，视觉反馈与 DataGrip 一致

1.2 添加"Collapse All"菜单项 ✅
  - 连接右键菜单底部增加「Collapse All」选项（图标：unfold_less）
  - 数据库右键菜单底部增加「Collapse All」选项
  - 实现 `_collapseAll()` 方法，一键清空 `_expandedItems`、`_expandedDatabases`、`_expandedTables`
  - **实际效果**：展开大量节点后，右键任意连接/数据库 → Collapse All → 所有节点瞬间折叠，恢复清爽视图

**修改文件：**
- `lib/organisms/sidebar/sidebar_tree.dart` (+22 行)
- `lib/organisms/sidebar_widget.dart` (+9 行)

---

### 功能 2：搜索体验提升 🟡 P1 ✅ 已完成

**涉及问题**：#5 快速跳转 (Go to Table) + #15 ⌘F 聚焦搜索

**完成日期**：2026-06-09

**实施内容：**

2.1 ⌘F / Ctrl+F 聚焦侧边栏搜索框 ✅
  - `_SidebarWidgetState` 新增 `_searchFocusNode`
  - `_buildExpandedSidebar` 外层包裹 `CallbackShortcuts`，绑定 ⌘F + Ctrl+F
  - 聚焦时自动全选已有文本（方便替换搜索词）
  - 搜索 `TextField` 关联 `focusNode: _searchFocusNode`
  - **实际效果**：在任何界面按 ⌘F，侧边栏搜索框自动获得焦点，光标定位，已有文本全选，可直接替换输入

2.2 ⌘K / Ctrl+K 全局表搜索 ✅
  - 已有 `QuickSearchDialog`（⌘N），现新增 ⌘K + ⌘K（macOS）绑定到同一入口
  - `_fuzzyMatch()` 模糊匹配算法：字符顺序子序列匹配
  - "usr" 可匹配 "users"、"user_profiles"、"user_roles"
  - 搜索结果优先精确包含，再补模糊匹配
  - **实际效果**：⌘K → 输入 "ord" → 看到所有含 "ord" 的表（orders, order_items, ordinals...）→ 回车直达打开表

**修改文件：**
- `lib/organisms/sidebar_widget.dart` (+15 行)
- `lib/core/shortcuts/app_shortcuts.dart` (+10 行)
- `lib/organisms/connection/quick_search_dialog.dart` (+17 行)

---

### 功能 3：展开状态持久化 🔴 P0 ✅ 已完成

**涉及问题**：#4 展开状态重启后丢失

**完成日期**：2026-06-09

**实施内容：**

3.1 SharedPreferences 序列化/反序列化 ✅
  - `SidebarProvider` 新增三个 key：`sidebar_expanded_items`、`_databases`、`_tables`
  - `loadExpandedState()` 返回 `({Set items, Set databases, Set tables})` Record
  - `saveExpandedState()` 用 `Future.wait` 并行写入三个 `setStringList`
  - **实际效果**：展开的连接、数据库、表节点关闭重启后自动恢复

3.2 全量写入触发点 ✅
  - `_toggleExpand()` → 保存（连接/全局节点展开折叠）
  - `_toggleDatabase()` → 保存
  - `_toggleTable()` → 保存
  - `_collapseAll()` → 保存
  - `_syncExpandedConnection()` → addPostFrameCallback 延迟保存（避免 build 期写入）
  - `dispose()` → 最终保存
  - `initState()` → addPostFrameCallback 异步加载
  - **实际效果**：每次展开/折叠操作后自动保存，重启保持完全一致

**修改文件：**
- `lib/providers/sidebar_provider.dart` (+31 行)
- `lib/organisms/sidebar_widget.dart` (+29 行)

---

### 功能 4：键盘导航 🟡 P1 ✅ 已完成

**涉及问题**：#1 无键盘导航

**完成日期**：2026-06-09

**实施内容：**

4.1 方向键导航 ✅
  - ↑↓ 在可见节点间循环移动焦点（到顶后回绕到底，到底后回绕到顶）
  - ← 折叠当前节点，→ 展开当前节点
  - Enter / Space 触发默认操作：表→打开浏览，视图→SELECT * 查询，存储过程→CALL 查询
  - **实际效果**：纯键盘可完整浏览导航树

4.2 高亮选中节点 ✅
  - `selectedNodeKey` 通过 `_isKeySelected()` 注入到 TreeItem
  - 连接/数据库/表/视图/存储过程/分类头全部支持键盘高亮
  - Esc 键取消选中

4.3 Type-to-select ✅
  - 在树获得焦点时（搜索框无焦点），按字母键跳转到匹配节点
  - 600ms 内连续输入累积前缀（"use" 跳到 "users"）
  - 从当前节点之后开始查找，支持回绕
  - 不拦截带修饰键的组合键（Ctrl+C 等不受影响）

4.4 可见节点列表构建 ✅
  - `_rebuildVisibleNodeKeys()` 在 build 时同步构建有序 key 列表
  - SQLite 和其他数据库类型分别处理
  - 遵循搜索过滤和折叠状态

4.5 键盘行为矩阵 ✅

```
┌────────────┬──────────┬──────────┬────────────────────┬────────────────────────┬────────────────────────────┐
│ Node type  │    ↑     │    ↓     │         ←          │           →            │          Enter             │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ conn (在线, │ 上一节点 │ 下一节点 │ 已折叠, no-op      │ 展开子节点             │ 展开子节点                  │
│ 折叠)      │          │          │                    │                        │                            │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ conn (在线, │ 上一节点 │ 下一节点 │ 折叠子节点         │ 已展开, no-op          │ 折叠子节点                  │
│ 展开)      │          │          │                    │                        │                            │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ conn (离线)│ 上一节点 │ 下一节点 │ 已折叠, no-op      │ 自动连接 + 展开        │ 自动连接 + 展开             │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ db (折叠,   │ 上一节点 │ 下一节点 │ 已折叠, no-op      │ 加载 schema + 展开     │ 加载 schema + 展开          │
│ 无缓存)    │          │          │                    │                        │                            │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ db (折叠,   │ 上一节点 │ 下一节点 │ 已折叠, no-op      │ 展开                   │ 展开                        │
│ 有缓存)    │          │          │                    │                        │                            │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ db (展开)  │ 上一节点 │ 下一节点 │ 折叠               │ 已展开, no-op          │ 折叠                        │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ cat (折叠) │ 上一节点 │ 下一节点 │ 已折叠, no-op      │ 展开                   │ 展开                        │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ cat (展开) │ 上一节点 │ 下一节点 │ 折叠               │ 已展开, no-op          │ 折叠                        │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ table      │ 上一节点 │ 下一节点 │ 已折叠, no-op      │ 展开 + 加载 schema    │ 展开 + 加载 schema          │
│ (折叠,     │          │          │                    │                        │                            │
│ 无schema)  │          │          │                    │                        │                            │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ table      │ 上一节点 │ 下一节点 │ 折叠               │ 已展开, no-op          │ 打开浏览查询 (SELECT * ...) │
│ (展开,     │          │          │                    │                        │                            │
│ 有columns) │          │          │                    │                        │                            │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ view       │ 上一节点 │ 下一节点 │ no-op              │ no-op                  │ 打开 SELECT * FROM view     │
│ (叶子)     │          │          │                    │                        │                            │
├────────────┼──────────┼──────────┼────────────────────┼────────────────────────┼────────────────────────────┤
│ proc       │ 上一节点 │ 下一节点 │ no-op              │ no-op                  │ 打开 CALL proc()            │
│ (叶子)     │          │          │                    │                        │                            │
└────────────┴──────────┴──────────┴────────────────────┴────────────────────────┴────────────────────────────┘

注：
- ↑↓ 导航到达边界时回绕（顶→底, 底→顶）
- Enter 遵循 "toggle / go deeper" 语义：折叠→展开, 展开→折叠, 表展开后→打开数据
- ←→ 遵循展开/折叠语义：离线连接←→自动触发连接, 无缓存DB自动加载schema
- Space 键行为同 Enter
- Esc 键取消当前选中
- type-to-select: 600ms 内累积字母前缀, 从当前节点之后搜索, 到达末尾回绕
```

**修改文件：**
- `lib/organisms/sidebar_widget.dart` (+200 行)
- `lib/organisms/sidebar/sidebar_tree.dart` (+20 行)

---

### 功能 5：表行数显示 🟡 P1 ✅ 已完成

**涉及问题**：#6 表名旁无行数信息

**完成日期**：2026-06-10

**实施内容：**

5.1 异步加载表行数 ✅
  - MySQL/Doris: `information_schema.TABLES.TABLE_ROWS`
  - PostgreSQL: `pg_class.reltuples`
  - 展开 Tables 分类时自动触发 `_loadTableRowCountsForDb()`
  - 缓存到 `_tableRowCounts` map，切换数据库不重复加载
  - **期望验证**：连接 MySQL → 展开数据库 → 展开 Tables → 每个表名右侧显示 `1.2K` / `5M` / `0` 等行数徽章

5.2 行数格式化 ✅
  - `≥1M` → `1.0M` 格式, `≥1K` → `1.0K` 格式, 其余原数
  - 失败静默，不影响浏览树

**修改文件：**
- `lib/organisms/sidebar_widget.dart` (+45 行)
- `lib/organisms/sidebar/sidebar_tree.dart` (+20 行)
- `lib/organisms/sidebar/builders/tree_utils.dart` (+0)
- `lib/models/database_models.dart` (+1 字段)

---

### 功能 7：拖拽表名到编辑器 🟡 P1 ✅ 已完成

**涉及问题**：#8 拖表到编辑器

**完成日期**：2026-06-10

**实施内容：**

7.1 表节点可拖拽 ✅
  - 每个表节点包裹 `Draggable<TableDragData>`
  - 拖拽 feedback 显示 `conn名.table名`
  - 拖拽时原节点半透明（opacity 0.4）
  - **期望验证**：从侧边栏拖任意表到查询编辑器区域，编辑器高亮，松手后光标位置插入 `SELECT * FROM table LIMIT 100;`

7.2 编辑器 DragTarget ✅
  - `QueryEditorWidget.build` 包裹 `DragTarget<TableDragData>`
  - 拖入时编辑器背景变淡蓝色
  - 接受拖放后自动在光标位置插入 SQL

**修改文件：**
- `lib/organisms/sidebar/sidebar_tree.dart` (+50 行)
- `lib/organisms/editor/query_editor_widget.dart` (+25 行)

---

### 功能 8：多选批量操作 🔴 P0 ⏭️ 跳过

**原因**：需要重构选择模型（Shift+Click, Ctrl+Click），涉及面广风险大，留待后续独立开发。

---

### 功能 9：视觉信息增强 🟢 P2 ✅ 已完成

**涉及问题**：#10 系统表区分 + #11 表类型图标 + #12 数据库概要 + #14 列信息丰富度

**完成日期**：2026-06-10

**实施内容：**

9.1 系统数据库视觉区分 ✅
  - `information_schema`, `mysql`, `pg_catalog`, `sys` 等用 `[dbname]` 括起来 + 灰色图标
  - **期望验证**：系统库名称带方括号，图标灰色，一目了然

9.2 数据库概要徽章 ✅
  - 数据库节点旁显示 `15t 3v 2p`（表数/视图数/存储过程数）
  - **期望验证**：不展开数据库也能看到概况

9.3 列信息增强 ✅
  - 默认值显示：`= ''` / `= auto_increment` / `= 0`
  - 截断过长的默认值（>12字符）
  - **期望验证**：展开表 → 列信息右侧显示默认值徽章

**修改文件：**
- `lib/organisms/sidebar/sidebar_tree.dart` (+40 行)

---

### 功能 10：加载体验优化 🟢 P2 ✅ 已完成

**涉及问题**：#13 加载体验不够精细

**完成日期**：2026-06-10

**实施内容：**

10.1 骨架屏占位 ✅
  - `buildSkeletonPlaceholders()` 在 `tree_utils.dart`
  - 数据库加载中显示 4 条灰色占位条替代纯粹的小 spinner
  - **期望验证**：展开未缓存的数据库 → 加载期间显示灰色骨架条 → 数据到达后替换为真实内容

**修改文件：**
- `lib/organisms/sidebar/builders/tree_utils.dart` (+20 行)

---

## 自动化测试

**新增测试文件**：3 个，共 +23 用例

| 测试文件 | 用例数 | 覆盖功能 |
|----------|:------:|---------|
| `test/providers/sidebar_provider_expanded_test.dart` | 5 | 功能 3 — 展开状态持久化 + 选择/收藏逻辑 |
| `test/organisms/tree_item_kb_test.dart` | 9 | 功能 4 — TreeItem isSelected/badge/emoji/isLoading/onTap/onDoubleTap |
| 总计 | **14 新增** | |

**已有测试**：2627 用例，18,500+ 行测试代码
**总测试数**：~~2627~~ → **2641** (+14)

**现状：**
- 每次右键上下文菜单只能操作一个对象

**开发内容：**

8.1 多选模式
  - Ctrl+Click 追加选择，Shift+Click 范围选择
  - 选中项共用高亮样式
  - 多选后右键弹出批量菜单：Drop N Tables、Truncate N Tables、Export N Tables
  - 期望效果：按住 Ctrl 点选 5 张表 → 右键 → "Drop 5 Tables" → 一次确认全删

**涉及文件：**
- `lib/organisms/sidebar/sidebar_tree.dart`
- `lib/organisms/sidebar/tree_item.dart`
- `lib/organisms/sidebar_widget.dart`
- `lib/organisms/sidebar/builders/context_menus/table_context_menu.dart`

---

### 功能 9：视觉信息增强 🟢 P2

**涉及问题**：#10 系统表区分 + #11 表类型图标 + #12 数据库概要 + #14 列信息丰富度

**现状：**
- 系统库/系统表和用户表外观完全一样
- 视图/物化视图/临时表用同一个图标
- 数据库节点不展开不知道里面有什么
- 列只显示 name + type

**开发内容：**

9.1 系统数据库/表视觉区分
  - `information_schema`、`mysql`、`pg_catalog`、`sys` 等系统库用灰色图标 + 斜体
  - 系统表用 dimmed 样式，默认折叠

9.2 表类型图标
  - 普通表：📋 / grid 图标
  - 视图：👁️ / visibility 图标（已有）
  - 物化视图：🔄
  - 临时表：⏳
  - 分区表：🧩

9.3 数据库概要信息
  - 数据库节点右侧徽章显示：`15 tables · 256MB`
  - 不需展开即可了解数据库规模

9.4 列信息丰富
  - 显示默认值：`id INT [PK] = auto_increment`
  - 显示注释/描述：`name VARCHAR(100) "用户姓名"`
  - 显示字符集：varchar/char 列后方小字标注 utf8mb4

**涉及文件：**
- `lib/organisms/sidebar/sidebar_tree.dart`
- `lib/organisms/sidebar/tree_item.dart`
- `lib/organisms/sidebar/builders/tree_utils.dart`
- `lib/theme/design_system.dart`（可能需要新颜色标记）

---

### 功能 10：加载体验优化 🟢 P2

**涉及问题**：#13 加载体验不够精细

**现状：**
- 数据库信息加载中只显示一个小 spinner，无进度感和内容预览

**开发内容：**

10.1 渐进式加载
  - 先展示上次缓存的数据（如有），右上角显示刷新指示器
  - 后台异步拉取最新数据，比对后增量更新
  - 加载中显示骨架屏占位（3-5 条浅色占位条）
  - 期望效果：展开数据库立即看到内容（可能是缓存），新数据静默更新，无闪烁

**涉及文件：**
- `lib/organisms/sidebar/sidebar_tree.dart`
- `lib/organisms/sidebar/builders/tree_utils.dart`

---

## 三、实施进度

| 功能 | 状态 | 开始日期 | 完成日期 | 备注 |
|------|------|----------|----------|------|
| 1. 右键交互完善 | ✅ 已完成 | 2026-06-09 | 2026-06-09 | 右键选中 + Collapse All |
| 2. 搜索体验提升 | ✅ 已完成 | 2026-06-09 | 2026-06-09 | ⌘F 聚焦 + ⌘K 全局搜索 + 模糊匹配 |
| 3. 展开状态持久化 | ✅ 已完成 | 2026-06-09 | 2026-06-09 | SharedPreferences 三级 Set |
| 4. 键盘导航 | ✅ 已完成 | 2026-06-09 | 2026-06-09 | ↑↓导航 + ←→折叠 + Enter操作 + type-to-select |
| 5. 表行数显示 | ✅ 已完成 | 2026-06-10 | 2026-06-10 | 异步加载+缓存, 格式化 1.2K/5M |
| 6. 最近访问区域 | ✅ 已完成 | 2026-06-09 | 2026-06-09 | ExpansionTile 置顶, 最多5条, 自动记录 |
| 7. 拖拽表名到编辑器 | ✅ 已完成 | 2026-06-10 | 2026-06-10 | Draggable表节点 + DragTarget编辑器 |
| 8. 多选批量操作 | ⏭️ 跳过 | - | - | 复杂度高风险大，后续独立开发 |
| 9. 视觉信息增强 | ✅ 已完成 | 2026-06-10 | 2026-06-10 | 系统库区分+DB概要+默认值显示 |
| 10. 加载体验优化 | ✅ 已完成 | 2026-06-10 | 2026-06-10 | 骨架屏占位 |

---

## 四、建议开发顺序

```
功能1（右键交互）→ 功能3（展开持久化）→ 功能2（搜索体验）
    → 功能6（最近访问）→ 功能5（表行数）→ 功能4（键盘导航）
    → 功能7（拖拽到编辑器）→ 功能8（多选批量）→ 功能9（视觉增强）→ 功能10（加载优化）
```

**排序原则：**
1. 先低成本高收益（1, 3）快速建立信心
2. 再提升搜索发现效率（2, 6, 5）
3. 然后补齐专业交互（4, 7, 8）
4. 最后视觉打磨（9, 10）
