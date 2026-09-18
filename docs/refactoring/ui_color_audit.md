# DbMaster 配色与视觉 UI 对标审查报告

> **日期**：2026-07-23
> **范围**：仅配色与视觉 UI（不含交互、功能、安全）
> **对标对象**：DataGrip（Darcula / New UI）、Navicat 16/17、TablePlus、DBeaver、VS Code Dark+、GitHub Dark
> **方法**：多代理编排工作流（52 个 agent，三阶段：事实提取 → 8 维度评审团 → 逐条对抗核实）
> **结论统计**：43 条初步发现 → **35 条确认（confirmed）、5 条程度修正（exaggerated）、0 条驳回**
> **严重度定义**：critical = 一眼就不专业；major = 与主流明显差距；minor = 打磨项

---

## 1. 背景与结论摘要

DbMaster 的功能架构已达专业数据库工具水准，差距集中在配色执行层。本次审查以源码级查证的主流工具基准为尺，逐维度比对，核心结论：

- **亮色主题是暗色的附属品**：弱化文字对比度 2.2:1 全面不达标、语义四色亮暗同值（warning 亮底仅 1.95:1）、SQL 快速高亮路径亮色破损、atoms 层活代码直接消费暗色令牌——亮色模式存在系统性破损。
- **accent 体系双轨**：换肤 accent（8 色枚举）与静态令牌 `#0ea5e9` 互不通信，514 处静态引用永不换色；另有第三套无令牌的 AI 紫 `#8b5cf6`（184 处硬编码）。
- **数据网格密度是消费级**：行高 40px（主流 20–24px）、数字不右对齐、斑马纹跨两档灰阶。
- **配色纪律处于"主题化迁移半途"**：192 处 `Color(0x…)` 硬编码、语义色在业务层重复定义、emoji 图标残留、声明字体未打包。
- **令牌主干本身是健康的**：暗色 Zinc 四级灰阶 + 语义色齐备、`context.themeColors` 已铺开 2400+ 处、迁移纪律（@Deprecated 别名）良好——大部分修复是"收编"而非"重建"。

---

## 2. 主流基准（源码级查证）

DataGrip Darcula / New UI、VS Code Dark+、GitHub Dark 的色值取自官方 theme.json / token 仓库；Navicat/TablePlus/DBeaver 取自官方文档，未公开 hex 的标注【近似】。

### 2.1 工具画像

| 工具 | 主背景 | 分层 | accent | 语法高亮（关键字/字符串/数字/注释） | 风格 |
|------|--------|------|--------|----------------------------------|------|
| DataGrip Darcula | `#2B2B2B` | 面板 `#3C3F41` | 蓝 | `#CC7832` / `#6A8759` / `#6897BB` / `#808080` | IDE 系高密度低饱和 |
| JetBrains New UI Dark | `#1E1F22` | `#2B2D30` → `#393B40` | `#3574F0` | 同 Darcula 系 | 现代 IDE |
| VS Code Dark+ | `#1E1E1E` | `#252526` | `#007ACC` | `#569CD6` / `#CE9178` / `#B5CEA8` / `#6A9955` | 编辑器基准 |
| GitHub Dark | `#0D1117` | inset `#010409` | `#1F6FEB` | fg.muted `#9198A1`（6.5:1） | token 双映射典范 |
| TablePlus | 【近似】浅灰白/深灰 | 弱斑马纹 | 品牌蓝 | 可定制；行标记 软删红/新增绿/修改橙 | 轻快商业工具 |
| DBeaver | Eclipse Dark 机制 | — | — | 社区推荐 Darkest Dark | IDE 系 |
| Navicat 16/17 | 官方暗色模式 | — | 品牌蓝 | — | 商业重功能 |

### 2.2 八条主流共识

1. **背景三层分层**：编辑器/主底最深、面板浅一档、浮层再浅一档，层间明度差仅 5–10%（JB `#1E1F22→#2B2D30→#393B40`；VS Code `#1E1E1E→#252526`）；大面积不用纯黑，纯黑仅作 inset 凹进（GitHub `#010409`）。
2. **文字不用纯白**：主文字落在 `#BBBBBB–#F0F6FC`（L≈73–97%），次要降一档，禁用降到 L≈35–45%；梯度比绝对值更重要。
3. **主 accent 高度一致选蓝**（JB `#3574F0`、VS Code `#007ACC`、GitHub `#1F6FEB`），使用纪律一致：只给 selection / focus border / link / 主按钮 / tab 指示，绝不铺大面积背景。
4. **选中态用"深一度 accent 底"**（`#2E436E` / `#0D293E`）而非亮 accent 直铺，保证选中区文字可读。
5. **暗色语义色提亮降饱和**：error 红收敛在 `#DB5C5C/#E74848/#F85149`，warning 琥珀 `#BA9752/#D29922`，success 绿 `#57965C/#3FB950`；大面积语义背景 = 深色调和底 + 亮色文字。
6. **SQL 语法高亮收敛为两大流派**（Darcula 橙绿蓝灰 / Dark+ 蓝橙绿绿）；共性是注释最低饱和、关键字与字符串对比最强、四色正交。
7. **数据网格高密度低装饰**：行高 20–24px、网格线极暗（`#393B40–#4F5152`）、斑马纹与底仅一档灰、NULL 灰化弱化、**数字右对齐文本左对齐**。
8. **风格两阵营**：IDE 系（DataGrip/DBeaver）高密度低饱和信息优先；独立商业工具（TablePlus/Navicat）轻快、留白多、以 per-connection 颜色标签区分环境——DbMaster 定位接近后者，但语法与网格细节应向 IDE 系取经。

### 2.3 查证来源

- JetBrains 官方主题：`intellij-community/.../darcula.theme.json`、`expUI_dark.theme.json`
- VS Code 官方主题：`microsoft/vscode .../dark_vs.json`、`dark_plus.json`
- GitHub Primer tokens：`primer/primitives .../dark.json5`、`bgColor.json5`
- TablePlus 官方文档（Fonts & Colors / Customize Colors）与 issue #476
- Navicat 官方帮助中心（Dark theme 支持说明）
- DBeaver 官方文档（UI Themes）

---

## 3. 差距总览

| 维度 | 🔴 critical | 🟠 major | 🟡 minor | 小计 |
|---|---|---|---|---|
| 背景与表面层级 | 0 | 3 | 2 | 5 |
| 文字颜色层级与对比度 | 1 | 2 | 2 | 5 |
| 语义色体系 | 1 | 3 | 2 | 6 |
| 品牌强调色纪律 | 1 | 2 | 2 | 5 |
| SQL 语法高亮配色 | 1 | 2 | 2 | 5 |
| 数据网格视觉 | 1 | 2 | 2 | 5 |
| 亮色主题完成度 | 2 | 2 | 2 | 6 |
| 视觉一致性（图标/圆角/阴影/字体落地） | 1 | 2 | 0 | 3 |
| **合计** | **8** | **18** | **14** | **40** |

---

## 4. 详细发现（40 条，全部经对抗核实）

### 4.1 背景与表面层级

#### F-01 [🟠 major] 暗色主题的 ColorScheme 只定义了 surface 一档，outline/surfaceContainer* 

- **差距**：暗色主题的 ColorScheme 只定义了 surface 一档，outline/surfaceContainer* 全部缺位，且暗色没有 dialogTheme/cardTheme/dividerTheme——未手动指定颜色的 Material 浮层（AlertDialog、Menu、BottomSheet、Divider）回落到 Material 3 基线的紫调灰（surfaceContainerHigh≈#2B2930 一族）与默认 outlineVariant，与 Zinc 灰阶并存形成第二套'野灰色'；亮色主题这些都定义了，亮暗契约严重不对称。
- **现状证据**：lib/theme/app_theme.dart:470-479（darkTheme 的 ColorScheme.dark 仅设 primary/secondary/surface=#18181b/error，无 outline、无 surfaceContainer*）；对照同文件 401-413 亮色 ColorScheme 设了 surfaceContainerHighest=#F0EDE8、outline=#E5E1DB，且亮色 420-426 有 cardTheme、455 有 dividerTheme，暗色三者全缺
- **主流做法**：JetBrains New UI Dark 与 VS Code Dark+ 的主题 JSON 对每一级表面与边框都有显式键值（Gray1-Gray5、widget.border #303031、menu.separator #454545），任何浮层都不会出现'体系外灰'；GitHub Dark 的 border 也显式映射 neutral.7 #3D444D。
- **修复建议**：补齐暗色 ColorScheme 契约：surfaceContainerLow=#18181b、surfaceContainerHigh=#27272a、surfaceContainerHighest=#3f3f46、outline=#27272a、outlineVariant=#3f3f46；并为 darkTheme 增加 dialogTheme（背景 #27272a、shadowModal、radiusMd）、popupMenuTheme（#27272a+shadowFloat）、cardTheme（#18181b、elevation 0）、dividerTheme（#27272a），与亮色逐项对称。
- **核实判定**：✅ confirmed（属实（confirmed）。逐行核实：lib/theme/app_theme.dart:470-479 darkTheme 的 ColorScheme.dark 仅设 primary/secondary/surface(#18181b, zinc-900)/error/onPrimary/onSecondary/onSurface/onError，确实没有 outline、outlineVariant 及任何 surfaceContainer*；darkTheme（463-526 整个 getter）也没有 dialogTheme、cardTheme、dividerTheme、popupMen…）

#### F-02 [🟠 major] shadowFloat/shadowModal 阴影令牌定义后全项目零引用，暗色浮层（右键菜单、溢出菜单、筛选弹层）既没

- **差距**：shadowFloat/shadowModal 阴影令牌定义后全项目零引用，暗色浮层（右键菜单、溢出菜单、筛选弹层）既没有阴影也没有统一边框，且浮层取色 bgTertiary 与输入框填充、表头、AI 气泡、工具卡片共用同一档 #27272a——'凹进的输入'和'浮起的弹层'挤在同一明度级，层级只能靠内容辨认。
- **现状证据**：lib/theme/design_system.dart:224-241（shadowFloat/shadowModal 定义）；Grep 全 lib/ 仅命中定义处与 244-252 的弃用别名，零业务引用；浮层实例 lib/organisms/connection/tabs_bar_widget.dart:134 弹出菜单仅设 color: bgTertiary（#27272a），无阴影无边框
- **主流做法**：JB New UI 浮层=面板级底色+Gray5(#4E5157) 描边+投影，hover/输入用 Gray3(#393B40) 另一档；VS Code 菜单 #252526 配 widget.border #303031，输入框 #3C3C3C 反而比菜单亮（inset 与 outset 明度方向相反、绝不共用一档）。
- **修复建议**：启用现有令牌：所有 PopupMenu/Dialog/Dropdown 装饰统一 'bgTertiary 或新增 bgElevated + shadowFloat + 1px borderLight(#3f3f46)' 三件套；层级语义明确为 L0 画布 #09090b / L1 面板 #18181b / L2 浮层 #27272a / 输入与 inset 单独给 bgInset（可复用 #131316），让'浮起'与'凹进'不再共用同一档。
- **核实判定**：⚠️ exaggerated（存在但程度/范围被夸大）
- **核实备注**：令牌部分属实：design_system.dart:224/234 定义 shadowFloat/shadowModal，全 lib/ 直接引用为零；但弃用别名 shadowLg(=shadowModal) 在 connection_dialog.dart:1391 被实际使用，shadowSm 另有 2 处使用，"零业务引用"对别名不成立。"浮层无阴影无边框"被证伪：右键菜单 ContextMenu（molecules/context_menu.dart:205-220）自带 boxShadow(black 0.25, blur 12, offset(0,4)) + Border.all(borderLight)；筛选弹层 ColumnFilterPopup（column_filter_widget.dart:138-148）同样带 Border.all + boxShadow 且取色 bgPrimary；仅溢出菜单（tabs_bar_widget.dart:134）确实只设 color: bgTertiary，但 M3 默认 elevation=3 运行时仍有 Material 阴影。bgTertiary=#27272a 与输入框填充(app_theme.dart:496)、表头(column_filter_widget.dart:466)、AI 气泡(design_system.dart:45 bgAiMessage)、思考卡片(thinking_card.dart:127) 同档属实，层级挤档问题成立。真实问题范围：令牌未统一接线 + 溢出菜单未显式声明阴影/边框 + 色彩层级撞档，而非"浮层普遍无阴影无边框"，故严重度 major 被夸大。

#### F-03 [🟠 major] 主画布 bgPrimary #09090b（Zinc-950）比所有基准工具的主底都深（JB New UI 最深 #1E

- **差距**：主画布 bgPrimary #09090b（Zinc-950）比所有基准工具的主底都深（JB New UI 最深 #1E1F22、VS Code #1E1E1E、GitHub #0D1117，经典 Darcula 更浅至 #2B2B2B），且配 textPrimary #fafafa 接近纯黑纯白对（对比度约 18.5:1）；近黑吃掉了色阶最底档，没有比这更深的'inset/凹进'级可用，AI 代码块只能硬编码 #282c34 另起炉灶。
- **现状证据**：lib/theme/design_system.dart:26 bgPrimary=#09090b（scaffold 经 app_theme.dart:467 透传）；:52 textPrimary=#fafafa
- **主流做法**：主流共识：大面积背景不用纯黑，纯黑只作 inset 凹进（GitHub #010409 专用于 inset，默认 canvas #0D1117）；主文字落在 #BBBBBB-#F0F6FC（L≈73-97%）而非纯白，长时间编码场景靠'深灰底+降一度白字'控制眩光。
- **修复建议**：方案 A（贴 GitHub）：bgPrimary 提到 #0D1117~#101014，ramp 顺移为 #101014/#18181c/#232327/#303036，textPrimary 降到 Zinc-200 #e4e4e7；方案 B（保留 Zinc 美学）：canvas 不动，新增 bgInset #050506 专供代码块/终端类凹进区域，并把 textPrimary 降至 #e4e4e7 缓解长时间盯屏的高反差。
- **核实判定**：✅ confirmed（核心事实全部属实。实际代码证据：(1) design_system.dart:26 `static const Color bgPrimary = Color(0xFF09090b);`（注释标注"主背景色（最外层）Zinc-950"）；(2) design_system.dart:52 `textPrimary = Color(0xFFfafafa)`（Zinc-50）；(3) app_theme.dart:467 darkTheme 中 `scaffoldBackgroundColor: bgPrimary`，透传属实。(4) "AI 代码块硬编码 #282c34"属实：lib/organ…）

#### F-04 [🟡 minor] AI 面板代码块（atom-one-dark #282c34，同一对值硬编码 4 次）与错误边界页（#1a1a1a/#2

- **差距**：AI 面板代码块（atom-one-dark #282c34，同一对值硬编码 4 次）与错误边界页（#1a1a1a/#2b2d30）是两级'游离表面'，不在 Zinc 四级色阶内；尤其错误边界是崩溃兜底 UI，却用一套与全 app 都不相同的灰，层级体系在最不该破的地方破了。
- **现状证据**：lib/organisms/ai_panel/ai_message_item.dart:587（另 1082/1436/1567 重复）isDark ? #282c34 : #fafafa；lib/organisms/connection/error_boundary.dart:134-167 #1a1a1a/#2b2d30/#5a5a5a；同文件 282-336 却在用令牌
- **主流做法**：DataGrip/VS Code 的嵌入代码视图与编辑器共用同一 editor.background 令牌（#1E1E1E 通吃），错误页同样走主题色板——基准工具里不存在'体系外灰'。
- **修复建议**：新增 codeBlock 表面令牌（暗=#1e1e22 或 bgInset、亮=#f6f6f4）替换 4 处 #282c34/#fafafa；error_boundary 全面改用 bgSecondary/bgTertiary/error 令牌——崩溃页是用户最后一屏，更应体现层级纪律。
- **核实判定**：✅ confirmed（属实，证据逐条核对通过：  1. AI 面板代码块：lib/organisms/ai_panel/ai_message_item.dart 中 `isDark ? const Color(0xFF282c34) : const Color(0xFFfafafa)` 确实一字不差重复 4 次（行 587 _buildCodeBlock、行 1082 markdown codeblockDecoration、行 1436、行 1567 两个工具结果容器）。#282c34 即 atom-one-dark 背景色，与 Zinc 色阶不符——lib/theme/design_system.dart:25…）

#### F-05 [🟡 minor] 亮色三级 #F0EDE8（输入/悬停）比二级卡片 #FFFFFF 更暗（凹进方向），暗色三级 #27272a 却比二级 

- **差距**：亮色三级 #F0EDE8（输入/悬停）比二级卡片 #FFFFFF 更暗（凹进方向），暗色三级 #27272a 却比二级 #18181b 更亮（浮起方向）——同一'bgTertiary'令牌在亮暗两模式明度方向相反，且亮色令牌无同源定义、散落两处硬编码，层级体系只有暗色半边是正式的。
- **现状证据**：lib/theme/app_theme.dart:387-389（亮 #F5F3EF/#FFFFFF/#F0EDE8）对照 lib/theme/design_system.dart:26-32（暗 #09090b/#18181b/#27272a）；另亮色 bgQuaternary #E8E5E0 在 app_theme.dart:393 被命名为 dividerColor，与 app_colors.dart:59 双份硬编码
- **主流做法**：JB/VS Code/GitHub 的亮暗主题共用同一套层级语义（canvas→panel→overlay 明度单调方向一致），只是色值不同；GitHub primer 的 bgColor.json5 正是'语义层亮暗双映射'的范本。
- **修复建议**：把层级语义写成文档并统一：L0 画布 / L1 面板 / L2 交互（hover 与 inset）/ L3 边框，亮暗同构——亮色 L2 保持 #F0EDE8 但只用于 hover/inset、浮层一律 #FFFFFF+shadowFloat+outline #E5E1DB；同时把亮色四级背景收编进 AppDesignSystem 同源定义，消除 app_theme/app_colors 双份硬编码。
- **核实判定**：✅ confirmed（代码事实全部核实属实。1) lib/theme/app_theme.dart:387-389 亮色主题 lightTheme getter 内局部常量：bgPrimary=0xFFF5F3EF、bgSecondary=0xFFFFFFFF、bgTertiary=0xFFF0EDE8（注释"输入框/悬停"），bgTertiary 在 :405 用作 surfaceContainerHighest；:393 dividerColor=0xFFE8E5E0，在 :455 用于 DividerThemeData。2) lib/theme/design_system.dart:26-32 暗色令牌：bg…）

### 4.2 文字颜色层级与对比度

#### F-06 [🔴 critical] 亮色模式的弱化文字 textMuted #9CA3AF 对比度仅 2.2–2.5:1，全面不达标且被大量用在 9–13p

- **差距**：亮色模式的弱化文字 textMuted #9CA3AF 对比度仅 2.2–2.5:1，全面不达标且被大量用在 9–13px 真实信息文本上（NULL、行号、tab 副标题、分组头），亮色下整片灰字发糊难读
- **现状证据**：lib/theme/app_colors.dart:73 textMuted=Color(0xFF9CA3AF)；实测对比度（WCAG 公式）：on bgSecondary #FFFFFF=2.54:1、on bgPrimary #F5F3EF=2.29:1、on bgTertiary #F0EDE8=2.17:1；消费点：NULL 13px 斜体 lib/organisms/results/virtualized_data_table.dart:547-550、行号 11px 同文件:485-491、tab 副标题 9px lib/organisms/connection/tabs_bar_widget.dart:678-689、分组头 lib/organisms/sidebar/builders/tree_utils.dart:306-323
- **主流做法**：主流工具暗亮两端的弱化文字都守住 4.5:1 正文线：GitHub Dark fg.muted #9198A1=6.5:1；VS Code 输入占位 #A6A6A6 也只用于占位符；JetBrains 最弱的 info 档 Gray7 #6F737A 在面板底仍约 4:1 且只用于辅助说明，9px 信息文字不会落到 3:1 以下
- **修复建议**：亮色 textMuted 提到 #78716C（Tailwind stone-500，暖灰与纸质底 #F5F3EF 同色系，on 白底 4.80:1、on 主底 4.33:1）或直接复用 textSecondary #6B6B6B；原 #9CA3AF 降级为纯装饰用途（图标/分隔符，需 ≥3:1 的图形对比线也只勉强），禁止再用于 9–13px 文本
- **核实判定**：✅ confirmed（核实结论：属实，且实际情况比描述略重。  1) 色值确认：lib/theme/app_colors.dart:72-73 — `Color get textMuted => _isDark ? AppDesignSystem.textTertiary : const Color(0xFF9CA3AF);` 亮色模式硬编码 #9CA3AF，无主题感知扩展覆盖、无上游修复迹象。  2) 背景色确认：app_colors.dart:51-56 亮色 bgSecondary=#FFFFFF、bgTertiary=#F0EDE8；bgPrimary=scaffoldBackgroundColor，app…）

#### F-07 [🟠 major] 暗色弱化文字 textTertiary #71717a 在面板底 3.67:1、在浮层/气泡底 3.08:1，作为承担语

- **差距**：暗色弱化文字 textTertiary #71717a 在面板底 3.67:1、在浮层/气泡底 3.08:1，作为承担语义的正文（NULL 值、行号、分组标签）不达 4.5:1 正文线
- **现状证据**：lib/theme/design_system.dart:58 textTertiary=Color(0xFF71717a)（Zinc-500）；实测：on bgPrimary #09090b=4.12:1、on bgSecondary #18181b=3.67:1、on bgTertiary #27272a=3.08:1；bgTertiary 是菜单/弹出层与 AI 气泡底色（lib/organisms/connection/tabs_bar_widget.dart:134、lib/organisms/ai_panel/ai_message_item.dart:966-978），Token 芯片 textMuted 正落在该底上（ai_message_item.dart:1249-1264）
- **主流做法**：GitHub Dark muted #9198A1 on #0D1117=6.5:1；JetBrains New UI 次要档 #9DA0A8 on #2B2D30≈6:1；最弱档（#656C76、#787878）只用于占位/装饰且也保持 ≥3.2:1；共识是'弱化文字降一档，不降到 3:1 边缘'
- **修复建议**：textTertiary 提亮到约 #94949E（Zinc-400/500 之间，实测 on bgSecondary 5.90:1、on bgTertiary 4.96:1、on bgPrimary 6.62:1，全部过 AA 正文线）；若坚持保留 Zinc-500 作装饰档，则把 NULL、行号、分组头等信息文本改走 textSecondary，textTertiary 只留给展开箭头等图形
- **核实判定**：✅ confirmed（发现属实。(1) 色值与行号精确：lib/theme/design_system.dart:58 textTertiary=Color(0xFF71717a)，L26/29/32 bgPrimary/bgSecondary/bgTertiary=#09090b/#18181b/#27272a。(2) 我按 WCAG 亮度公式独立复算三组对比度：4.12:1 / 3.67:1 / 3.08:1，与发现给出的实测值完全吻合，全部不达 4.5:1 正文线。(3) 证据代码均在且为活代码：tabs_bar_widget.dart:134 PopupMenuButton color=colors.bgT…）

#### F-08 [🟠 major] 禁用文字层级倒挂：暗色 textDisabled #7e7e88（4.95:1）比弱化档 textTertiary #7

- **差距**：禁用文字层级倒挂：暗色 textDisabled #7e7e88（4.95:1）比弱化档 textTertiary #71717a（4.12:1）更亮更显眼；亮色 textDisabled #696f77（4.58:1）与 textSecondary #6B6B6B（4.81:1）仅差 0.23，两档几乎不可区分
- **现状证据**：lib/theme/design_system.dart:61 textDisabled=Color(0xFF7e7e88)（注释自述'提升对比度以符合 WCAG AA'）；lib/theme/app_colors.dart:75 亮色 textDisabled=Color(0xFF696f77)；实测暗色 disabled 4.95:1 > tertiary 4.12:1，亮色 disabled 4.58:1 ≈ secondary 4.81:1
- **主流做法**：WCAG 明确豁免真正禁用控件的对比度要求，主流工具把禁用档放在梯度最底：JetBrains New UI disabled #5A5D63（on #1E1F22 仅 2.5:1）、Darcula disabled #777777；梯度方向永远是 primary > secondary > muted > disabled
- **修复建议**：暗色 textDisabled 降到 #5F5F66（on bgPrimary 3.14:1，低于 tertiary 修正后的 4.96:1，梯度恢复单调递减）；亮色 textDisabled 降到 #A39E97（on #F5F3EF 2.40:1，与 secondary 拉开 2.4 倍差距）；删除 design_system.dart:60 行那条'为 AA 提对比度'的注释依据——禁用态不需要过 AA
- **核实判定**：✅ confirmed（属实，四个对比度数字我全部独立复算并精确复现。  代码核实： 1. lib/theme/design_system.dart:61 `static const Color textDisabled = Color(0xFF7e7e88);`，第 60 行注释确为"禁用文本（提升对比度以符合 WCAG AA 标准，原 Zinc-600 对比度不足）"；第 58 行 `textTertiary = Color(0xFF71717a)`。暗色 scaffold 背景为同文件第 26 行 bgPrimary=#09090b。 2. lib/theme/app_colors.dart:74-75 `te…）

#### F-09 [🟡 minor] 暗色主文字 #fafafa（Zinc-50）近纯白，在 #09090b 底上 19:1，13px 高密度数据网格长时间阅

- **差距**：暗色主文字 #fafafa（Zinc-50）近纯白，在 #09090b 底上 19:1，13px 高密度数据网格长时间阅读有光晕刺眼感，明度梯度顶部过高
- **现状证据**：lib/theme/design_system.dart:52 textPrimary=Color(0xFFfafafa)；实测 on bgPrimary 19.06:1、on bgSecondary 16.97:1；单元格 13px monospace 正文用色 lib/organisms/results/virtualized_data_table.dart:650-655
- **主流做法**：主流暗色主文字普遍压到 #BBBBBB–#DFE1E5：VS Code #D4D4D4、JetBrains New UI #DFE1E5（12.6:1）、Darcula #BBBBBB；共识'主文字不用纯白'，AA 只需 4.5:1，19:1 的余量全部转化为视觉疲劳（GitHub #F0F6FC 是少数例外，但其内容密度远低于数据网格）
- **修复建议**：textPrimary 降为 Zinc-200 #e4e4e7（实测 15.68:1，仍远超 AA，与 textSecondary #a1a1aa 7.76:1 保持约 2 倍梯度差）；SQL 编辑器与数据网格这类长时注视区域优先受益
- **核实判定**：✅ confirmed（代码证据全部核实属实：lib/theme/design_system.dart:52 textPrimary=Color(0xFFfafafa)（Zinc-50），bgPrimary=0xFF09090b（:26）、bgSecondary=0xFF18181b（:29）。我按 WCAG 相对亮度公式独立复算：#fafafa/#09090b≈19.06:1、#fafafa/#18181b≈16.96:1，与评审数字吻合。数据网格用色链路：virtualized_data_table.dart:548-550 textColor=context.themeColors.textPrimary（非空…）

#### F-10 [🟡 minor] 亮暗两套灰阶色族不统一：暗色弱化档用冷灰 Zinc-500 #71717a，亮色弱化档却混入 Tailwind Gray

- **差距**：亮暗两套灰阶色族不统一：暗色弱化档用冷灰 Zinc-500 #71717a，亮色弱化档却混入 Tailwind Gray-400 #9CA3AF 冷灰，而亮色背景是暖纸质系（#F5F3EF/#F0EDE8），冷暖相冲导致灰字发'脏'发糊，且亮色在 secondary 与 muted 之间缺一个中间档
- **现状证据**：lib/theme/app_colors.dart:73 亮色 textMuted=Color(0xFF9CA3AF)（材料标注'属灰阶体系混入 Tailwind Gray-400'）；亮色背景 lib/theme/app_theme.dart:387-389 #F5F3EF/#F0EDE8 为暖灰；亮色梯度实测 13.77:1 → 5.33:1 → 2.54:1，第二到第三档直接腰斩
- **主流做法**：成熟主题的灰阶在同一色族内取档：JetBrains Gray1-14 同族梯度、GitHub neutral 色阶同族；暖底配暖灰（stone 系）、冷底配冷灰（zinc 系），保证弱化文字与底色色相一致不'浮'
- **修复建议**：亮色文字灰阶整体迁到 stone 暖灰族：textPrimary 维持 #2D2D2D、textSecondary 改 #57534E（stone-600）、textMuted 改 #78716C（stone-500）、textDisabled 改 #A8A29E（stone-400），四档对比度约 12.6/7.5/4.3/2.4:1，梯度均匀且与纸质底同色系
- **核实判定**：✅ confirmed（发现属实，逐项核实如下。  1) 亮色 textMuted 色值：lib/theme/app_colors.dart:72-73 原文为 `Color get textMuted => _isDark ? AppDesignSystem.textTertiary : const Color(0xFF9CA3AF);`。#9CA3AF 确为 Tailwind Gray-400，且是偏冷灰（R=156, G=163, B=175，蓝通道最高）。  2) 暗色弱化档：lib/theme/design_system.dart:57-58 注释明确写「弱化文本 Zinc-500」`textTertiar…）

### 4.3 语义色体系

#### F-11 [🔴 critical] error/warning/success/info 四色亮暗同值，亮色暖白底下 warning 琥珀（#f59e0b，

- **差距**：error/warning/success/info 四色亮暗同值，亮色暖白底下 warning 琥珀（#f59e0b，对比度仅约 1.95:1）、info 青（#06b6d4，约 2.16:1）、success 绿（#22c55e，约 2.18:1）作为文字/小图标色几乎不可读，warning 黄在亮底上是典型的“一眼业余”问题
- **现状证据**：lib/theme/design_system.dart:91/94/97/100 四色定义注释自述“亮暗同一套静态值”（#22c55e/#f59e0b/#ef4444/#06b6d4）；亮色底 #F5F3EF（app_theme.dart:387）；亮色 ColorScheme.error 直接复用 accentRed（app_theme.dart:406）；亮色下的实际承载：截断标记 ✂ 用 #f59e0b 且 fontSize 10（virtualized_data_table.dart:637-643）、tabs 已保存状态用 #22c55e（tabs_bar_widget.dart:661-668）、状态栏 severity 文字用同色（query_editor_status_bar.dart:66-71）
- **主流做法**：主流工具亮暗主题各有一套语义色：GitHub 亮主题 attention 文字 #9A6700、danger #D1242F、success #1A7F37（深一档保证白底可读），暗主题则提亮为 #D29922/#F85149/#3FB950；JetBrains 亮色 light 主题同样为 Label.errorForeground 等定义独立深红/深黄
- **修复建议**：为 AppDesignSystem 增加亮色变体：warning 亮色用 #B45309（Amber-700）或 GitHub #9A6700，success 用 #16A34A（Green-600）或 #1A7F37，info 用 #0891B2（Cyan-600），error 亮色保留 #DC2626（Red-600，比 #ef4444 深一档）；令牌按主题分支（仿 ThemeColors 的 _isDark 分支），全部小字号/图标语义色引用点自动生效
- **核实判定**：✅ confirmed（核心事实全部属实，仅两处细节描述有出入，不影响结论。  1) 四色定义：lib/theme/design_system.dart:91/94/97/100 确认 success=#22c55e、warning=#f59e0b、error=#ef4444、info=#06b6d4，均为 static const 单套值。但"注释自述亮暗同一套"不在这些行（91-100 行注释只是"成功色 Green-500"等）；真正的自述在 lib/theme/app_colors.dart:83 `// Accent colors - consistent across themes`，其下 accentG…）

#### F-12 [🟠 major] 语义色只有 fg 一种形态、没有 surface/muted 变体，大面积语义背景用亮色直铺 alpha（错误气泡 er

- **差距**：语义色只有 fg 一种形态、没有 surface/muted 变体，大面积语义背景用亮色直铺 alpha（错误气泡 error alpha 0.05、危险操作整圈 1px #ef4444 边框），暗色下过于稀薄、亮色下亮色底纹发脏
- **现状证据**：lib/theme/design_system.dart:91-100 四色各只有单值，无 bg/emphasis 分层；AI 面板错误气泡 error alpha 0.05（ai_message_item.dart:966-978）、危险操作气泡 1px error 边框（ai_message_item.dart:848-853,980-994）、代码块危险边框 error alpha 0.5（:678-680）、AI 面板 SnackBar 直接裸色 Colors.orange（ai_panel_widget.dart:2012）
- **主流做法**：JetBrains New UI Dark 与 GitHub Dark 都是“深色调和底 + 亮色文字”模式：error 底 #402929 / warning 底 #3D3223（JB），GitHub muted 底纹 = 色阶第 4 档 @10-15% alpha + 深色 emphasis 底（danger #DA3633）；语义色成套为 fg/fg-muted/bg/emphasis 四层
- **修复建议**：为每个语义色补 errorBg(#402929 量级暗色调和底 / 亮色 #FDE8E8)、errorBorder、errorFg 三层令牌；危险气泡改用 errorBg 底 + errorBorder 1px + errorFg 文字，替代 alpha 直铺；SnackBar 统一走令牌封装（AppErrorHandler 已有 helper，把 Colors.green/orange 裸色点全部收编）
- **核实判定**：✅ confirmed（核心事实全部属实，仅个别行号有偏移、"大面积"措辞略夸张。  1) 语义色无分层（属实）：lib/theme/design_system.dart:91-100 确实只有 success(#22c55e)/warning(#f59e0b)/error(#ef4444)/info(#06b6d4) 四个单值常量，无 bg/surface/emphasis/muted 变体；我进一步 grep 了整个 lib/theme/ 目录（design_system.dart + app_theme.dart），除已 @Deprecated 的别名外不存在任何语义色的 surface/muted 扩展，Th…）

#### F-13 [🟠 major] 同一语义（info）存在两个颜色双轨：令牌定义 info=#06b6d4 青，而校验 severity 体系两处硬编码 

- **差距**：同一语义（info）存在两个颜色双轨：令牌定义 info=#06b6d4 青，而校验 severity 体系两处硬编码 info=#3b82f6 蓝，用户在同一编辑器里看到的 info 圆点/计数是蓝色、其他 info 提示是青色，语义色不成套
- **现状证据**：lib/theme/design_system.dart:100 info=#06b6d4；但 query_editor_status_bar.dart:110 与 sql_highlighter.dart:855 两处硬编码 ErrorSeverity.info=0xFF3b82f6，且 error/warning 两个值（0xFFef4444/0xFFf59e0b）与令牌逐字节重复却仍硬编码
- **主流做法**：VS Code/JB/GitHub 的 info/notification 色全应用唯一来源（VS Code 行内 info 走 editorInfo.foreground #3794FF 单一键），severity 三档色直接映射同一组语义令牌
- **修复建议**：删除两处硬编码 switch，改为直接返回 AppDesignSystem.error/warning/info；若认为编辑器内 info 用蓝比青更合适（VS Code 惯例 #3794FF），则把 info 令牌本身改为蓝并全局统一，二选一但只留一个值
- **核实判定**：✅ confirmed（代码事实全部属实：1) lib/theme/design_system.dart:100 确为 `static const Color info = Color(0xFF06b6d4);`（Cyan-500）；2) lib/organisms/editor/query_editor_status_bar.dart:106-110 的 `_getSeverityColor` 硬编码 error=0xFFef4444 / warning=0xFFf59e0b / info=0xFF3b82f6；3) lib/organisms/editor/sql_highlighter.dart:848-856…）

#### F-14 [🟠 major] 数据类型图标色与状态语义色撞车：日期列图标=warning 琥珀、主键=error 红、JSON=info 青，侧栏里一

- **差距**：数据类型图标色与状态语义色撞车：日期列图标=warning 琥珀、主键=error 红、JSON=info 青，侧栏里一个普通 DATETIME 列看起来像个 warning、主键看起来像报错，语义色被“消耗”失去告警含义
- **现状证据**：lib/theme/design_system.dart:144-155：schemaAmber #F59E0B 与 warning 同值、schemaRed #EF4444 与 error 同值、schemaCyan #06B6D4 与 info 同值；且 schemaGreen #10B981 ≠ success #22c55e（又一种绿）；引用点 tree_utils.dart:183-273 列类型图标 + 主键红色图标
- **主流做法**：DataGrip/DBeaver 的列类型图标多用低饱和中性色或单色图标族（类型靠图标形状区分，颜色只给主键/外键少量强调），error/warning 色严格保留给校验与状态，绝不用于常规数据分类
- **修复建议**：给 schema 类型色与语义色解耦：日期改用紫/蓝系（如 #818CF8）、主键用金色 #EAB308 但与 error 红拉开、JSON 用绿系 #4ADE80；或更彻底：类型图标统一 textSecondary 中性色 + 仅主键/外键各保留一个专属色（金/紫），语义四色回归状态专用
- **核实判定**：✅ confirmed（色值撞车属实且逐条命中：design_system.dart:94 warning=#F59E0B 与 :146 schemaAmber 同值；:97 error=#EF4444 与 :155 schemaRed 同值；:100 info=#06B6D4 与 :150 schemaCyan 同值；:91 success=#22C55E 而 :147 schemaGreen=#10B981 确为第二种绿。引用点属实：tree_utils.dart:195 日期列=schemaAmber 日历图标、:210 JSON=schemaCyan、:258 PRIMARY 索引=schemaRed 钥匙图…）

#### F-15 [🟡 minor] 语义状态多处只靠颜色传达：行号栏 error/warning/info 三档都是 6px 同色圆点（形状无差异），状态栏

- **差距**：语义状态多处只靠颜色传达：行号栏 error/warning/info 三档都是 6px 同色圆点（形状无差异），状态栏 severity 图标固定 error_outline 不随级别变化，红绿色盲用户无法区分
- **现状证据**：lib/organisms/editor/sql_highlighter.dart:826-835 行号旁 6x6 圆点 shape: BoxShape.circle 三档同形仅靠 _getErrorColor 区分；query_editor_status_bar.dart:60-63 无论 severity 一律 Icons.error_outline，仅颜色变化
- **主流做法**：VS Code 用波浪下划线（红=error、黄=warning）+ Problems 面板里 error/warning/info 三个不同形状图标（x-circle / warning-triangle / info-circle）；DataGrip 校验条纹亦分形状与图标
- **修复建议**：行号栏改用小图标替代圆点：error=Icons.error 实心圆、warning=Icons.warning_amber 三角、info=Icons.info_outline；status bar 按 severity 映射对应图标；编辑器内同步加波浪 underline（CustomPainter 画 wavy line）作为颜色之外的第二通道
- **核实判定**：⚠️ exaggerated（存在但程度/范围被夸大）
- **核实备注**：两处代码描述均与实际相符，但影响范围被夸大，一半证据是死代码。

【属实部分】行号圆点：lib/organisms/editor/sql_highlighter.dart:826-835 确为 6x6、shape: BoxShape.circle 的圆点，三档 severity（_getErrorColor，848-857 行：error=红 0xFFef4444 / warning=琥珀 0xFFf59e0b / info=蓝 0xFF3b82f6）同形仅靠颜色区分。此为活代码：QueryEditorWidget._validateSql（query_editor_widget.dart:604-619）在 2549 行把 _validationErrorsByLine 传给 EnhancedSqlEditor → SqlCodeEditor → LineNumbers（sql_highlighter.dart:698-702）→ _LineNumberItem。且 errors 在该文件中只用于行号圆点，编辑文本内无波浪线等其他 severity 区分手段，红绿色盲用户对 error（红）与 warning（琥珀）档确实易混淆（info 蓝通常可区分，"无法区分"略有绝对化）。

【夸大部分】状态栏图标：query_editor_status_bar.dart:60-63 代码确为固定 Icons.error_outline、仅经 _getSeverityColor 改色（103-112 行），与描述一致。但 QueryEditorStatusBar 是死代码——全仓库（lib/、test/、integration_test/）grep `QueryEditorStatusBar|query_editor_status_bar` 仅命中其自身文件，无任何 import 或实例化，该状态栏不在实际 UI 中，真实用户不受影响。

结论：核心问题（行号圆点三档同形仅靠颜色）成立且为活代码，但发现的一半证据（状态栏）是未接入的死代码，实际影响面约为描述的一半。严重度 minor 的定性本身不高，维持该量级但范围应下修。

#### F-16 [🟡 minor] 语义色实现碎片化：与令牌逐字节相同的 hex 在业务层重复定义、还存在“双胞胎红” #f75454 与令牌 #ef444

- **差距**：语义色实现碎片化：与令牌逐字节相同的 hex 在业务层重复定义、还存在“双胞胎红” #f75454 与令牌 #ef4444 近似并存、多处 SnackBar 用 Material 裸色 Colors.green/orange，艳度与全 App 降饱和语义不一致
- **现状证据**：query_editor_status_bar.dart:106-110 与 sql_highlighter.dart:851-855 重复定义同值 hex；error_boundary.dart:134-167 用 #f75454 红 + #3574f0 蓝（均非令牌），同文件 282-336 行 SnackBar helper 却用令牌；裸色 SnackBar：export_service.dart:147 Colors.green、safety_warning_banner.dart:123 Colors.orange[600]、validation_rules_dialog.dart:133 Colors.green、schema_diff_page.dart:717 Colors.green
- **主流做法**：主流工具 toast/横幅色全部走统一语义令牌（JB Notification.background/foreground、GitHub alert 组件统一调用 danger/success attention 色阶），无业务层散色
- **修复建议**：以 AppErrorHandler 的 SnackBar helper 为唯一出口，全局替换 Colors.green/orange 裸色；error_boundary 的 #f75454/#3574f0 并入令牌；建议加一条 lint 约定（业务代码禁止 Color(0x 直接出现语义色 hex）防止再生
- **核实判定**：✅ confirmed（逐条核实证据，发现属实（个别细节表述略有出入但不影响结论）：  1. 重复定义同值 hex — 属实。lib/organisms/editor/query_editor_status_bar.dart:103-112 的 `_getSeverityColor` 返回 `Color(0xFFef4444)` / `Color(0xFFf59e0b)` / `Color(0xFF3b82f6)`；lib/organisms/editor/sql_highlighter.dart:848-857 的 `_getErrorColor` 逐字节相同。对照 lib/theme/design_system.…）

### 4.4 品牌强调色纪律

#### F-17 [🔴 critical] accent 双轨体系：换肤 accent（8 色枚举）与静态令牌 accentPrimary 是两套互不通信的主色，默

- **差距**：accent 双轨体系：换肤 accent（8 色枚举）与静态令牌 accentPrimary 是两套互不通信的主色，默认状态 UI 上就同时存在两种品牌蓝，换 accent 只换到极少数 Material 控件
- **现状证据**：AppDesignSystem.accentPrimary #0ea5e9（lib/theme/design_system.dart:80）被 123 个文件 514 处直接引用（侧栏选中、tab 指示条、外键、光标、排序列等）；而 ThemeProvider._applyAccentColor 只改 primaryColor/ColorScheme.primary/FAB/ElevatedButton（lib/providers/theme_provider.dart:235-252），默认 AccentColorType.blue 是 #3574f0（theme_provider.dart:29）——默认状态下 Material 按钮层 #3574f0 与其余全部 UI 的 #0ea5e9 就是两种不同的蓝；用户换成绿色/粉色后，514 处静态令牌引用仍是 Sky 蓝
- **主流做法**：主流工具单咽喉管理 accent：VS Code 全 UI 只读 color registry 的 focusBorder/button.background 等语义键（值统一 #007ACC），GitHub Primer 用 accent.fg/accent.emphasis/accent.muted 三个语义令牌派生同一蓝（#58A6FF/#1F6FEB/#388BFD@10%）——换色只改令牌源一处，全 UI 同步
- **修复建议**：统一咽喉：把 accentPrimary 从静态常量改为主题感知（经 ThemeColors getter 读 Theme.of(context).colorScheme.primary 或 ThemeProvider.accentColorValue），逐步替换 514 处直连；或在 AppTheme 构建 ThemeData 时强制 colorScheme.primary = AppDesignSystem.accentPrimary 并删除 AccentColorType 换肤功能。二选一，不允许双轨共存。
- **核实判定**：✅ confirmed（发现属实，双轨体系客观存在且无缓解因素。逐条核实：(1) lib/theme/design_system.dart:80 `static const Color accentPrimary = Color(0xFF0ea5e9)`（Sky-500），为纯 static const 令牌，无 ThemeExtension、无 of(context) 运行时重映射。(2) lib/providers/theme_provider.dart:29 AccentColorType.blue = #3574f0，且为默认值（第 120 行字段初始化 + 第 165 行 load() 回退），与 #0ea…）

#### F-18 [🟠 major] 默认品牌色 #0ea5e9（Sky-500 亮青蓝）饱和度偏高、色相偏青，气质接近 SaaS 营销页而非专业桌面工具

- **差距**：默认品牌色 #0ea5e9（Sky-500 亮青蓝）饱和度偏高、色相偏青，气质接近 SaaS 营销页而非专业桌面工具；主流开发者工具的 accent 全部收敛在更深、更沉的蓝
- **现状证据**：accentPrimary Sky-500 #0ea5e9、accentHover Sky-400 #38bdf8（lib/theme/design_system.dart:80-83）；讽刺的是 AccentColorType.blue 的 #3574f0（lib/providers/theme_provider.dart:29）恰恰就是 JetBrains New UI 的官方 Blue6，即'正确的色'存在于错误的层
- **主流做法**：JetBrains New UI #3574F0、VS Code #007ACC、GitHub emphasis #1F6FEB、TablePlus/Navicat 品牌蓝均在'中深蓝'区间；亮色高饱和青蓝在这些工具里只出现在图表/徽章等点缀位，从不做全产品主 accent
- **修复建议**：将品牌主色定为 #3574f0（或等量级如 #2F7DE1），hover 用深/亮一档的 #4E86F2 而非更艳的 #38bdf8；accentSubtle 保持 10-15% alpha 派生。做法等同 GitHub 双层 accent：文字/链接用亮一档（如 #6B9BFA），按钮填充用主色
- **核实判定**：✅ confirmed（属实。逐条核实结果：  1. design_system.dart:80-83 与描述完全一致——`static const Color accentPrimary = Color(0xFF0ea5e9);`（注释原文"主色调 Sky-500"）、`static const Color accentHover = Color(0xFF38bdf8);`（注释"悬停色 Sky-400"），另有 accentSubtle 为 15% 透明度的同色。  2. theme_provider.dart:29 确认 `AccentColorType.blue` 返回 `Color(0xFF3574f0)`…）

#### F-19 [🟠 major] AI 紫 #8b5cf6 是无令牌、纯硬编码的第三套'品牌色'，与主 accent 蓝和用户所选 accent 同屏竞争

- **差距**：AI 紫 #8b5cf6 是无令牌、纯硬编码的第三套'品牌色'，与主 accent 蓝和用户所选 accent 同屏竞争，AI 面板成为配色纪律最差的区域
- **现状证据**：#8b5cf6/accentPurple 在 52 个文件 184 处：AI 头像（ai_message_item.dart:112-123）、发送/流式指示（:168,199）、Markdown 引用条（:1077-1079）、工具图标（:1347）、Token 芯片（:1249-1264）等；令牌层 accentPurple 标 @Deprecated('使用 accentPrimary') 但值仍是 #8b5cf6（design_system.dart:116），弃用语义与实值自相矛盾；且 dbTDengine 与 schemaPurple 同为 #8B5CF6（design_system.dart:136,150）三色撞车
- **主流做法**：VS Code Copilot 聊天、JetBrains AI Assistant 的界面内 UI 均沿用产品单一 accent（蓝），AI 身份靠图标/头像形状而非独立色相表达；紫色只出现在品牌插画/营销层，不进功能性 UI
- **修复建议**：建一个独立 aiAccent 令牌（如 #8b5cf6 保留但正名，亮暗各给一值），AI 面板 184 处硬编码全部改走令牌；或更彻底地把 AI 相关强调收敛进主 accent + textSecondary 层级（对齐 VS Code 做法）。删除或修正 accentPurple 弃用别名，并让 dbTDengine 换色（如 #6D28D9 深一档紫）避开撞车
- **核实判定**：✅ confirmed（核实结论：发现属实，逐项验证如下。  【范围计数精确吻合】在 lib/ 下 grep `8b5cf6|8B5CF6|accentPurple`（不分大小写）得到 52 个文件 184 处，与证据数字完全一致。  【组件证据逐条复核（ai_message_item.dart）】 - AI 头像：112-123 行 `_buildAvatar`，117 行 AI 头像用裸 `const Color(0xFF8b5cf6)`，而同函数 116 行用户头像用 `AppDesignSystem.accentPrimary`——"同屏竞争"直接成立。 - 发送/流式指示：168、176、191、199 行…）

#### F-20 [🟡 minor] 8 色 accent 自选策略与专业工具气质相悖，其中粉/亮青/黄属消费级玩具色，黄色 accent 在按钮/链接上对比

- **差距**：8 色 accent 自选策略与专业工具气质相悖，其中粉/亮青/黄属消费级玩具色，黄色 accent 在按钮/链接上对比度直接不可读
- **现状证据**：AccentColorType 8 色（lib/providers/theme_provider.dart:23-43）：pink #ff6b9d、cyan #00d4aa、yellow #f2c55c 等；_applyAccentColor 直接把该色做 ElevatedButton 填充 + 白字（theme_provider.dart:245-249）——#f2c55c 黄底白字对比度约 1.8:1，远低于 WCAG AA 4.5:1；且如发现 1 所述，换色只影响按钮/FAB 等少数控件，用户得到的是'按钮粉、其余全蓝'的破碎体验
- **主流做法**：DataGrip、VS Code、TablePlus、Navicat、DBeaver 全部只认一个品牌蓝；个性化交给完整主题生态（插件主题包整体换配色），而非给用户一个会撕裂 UI 的 accent 色板
- **修复建议**：两条路：a) 砍掉 accent 换肤（推荐，对齐主流单品牌色策略，用省下的复杂度做深/浅主题打磨）；b) 若保留，收敛为 3-4 个低饱和专业色（如蓝 #3574F0、青 #0891B2、紫 #7C6BD9、绿 #3D9A50），每色配亮暗两套 + 前景色（深底白字/浅底深字）校验过对比度，并走发现 1 的统一咽喉真正全局生效
- **核实判定**：✅ confirmed（核实通过。代码证据：(1) theme_provider.dart:23-43 确认 8 色枚举，pink=0xFFff6b9d、cyan=0xFF00d4aa、yellow=0xFFf2c55c，与证据一致；(2) theme_provider.dart:245-250 _applyAccentColor 确实以 accentColorValue 填充 ElevatedButton 背景 + 硬编码 Colors.white 前景，app_theme.dart:357-362/376-381 有同样实现，且 main.dart:93-94 用 accentColorValue 构建应用主题，…）

#### F-21 [🟡 minor] accent 使用位置整体克制（选中/hover/焦点/链接/指示条均为低 alpha 或小面积），但 AI 用户气泡 

- **差距**：accent 使用位置整体克制（选中/hover/焦点/链接/指示条均为低 alpha 或小面积），但 AI 用户气泡 0.8 高 alpha 大面铺色与 error_boundary 硬编码 #3574f0 是纪律破例点
- **现状证据**：健康面：侧栏选中 accentPrimary alpha 0.15/0.1（tree_item.dart:97-117）、tab 底部 2px 指示条（tabs_bar_widget.dart:731-740）、外键链接色+下划线（virtualized_data_table.dart:653-658）、排序列名 accentBlue（column_filter_widget.dart:488-495）均克制；破例点：AI 用户气泡 accentPrimary alpha 0.8 整铺（ai_message_item.dart:966-978），error_boundary.dart:167 硬编码 0xFF3574f0（恰好等于 AccentColorType.blue，用户换 accent 后此按钮颜色孤立）
- **主流做法**：主流共识是'选中态用深一度 accent 底'：DataGrip selection #2F65CA 压暗底 / #0D293E 深蓝底、GitHub accent.muted=#388BFD@10% alpha——大面积极少用高 alpha 亮 accent 直铺，保证上面文字可读
- **修复建议**：用户气泡改为 accent 底纹法：accentPrimary @10-15% alpha 背景 + accentPrimary 左边条或图标标识（对齐 GitHub accent.muted 与 DataGrip selection 底）；error_boundary 的 0xFF3574f0 改为读当前主题 colorScheme.primary，消灭与枚举值绑死的硬编码
- **核实判定**：✅ confirmed（逐条核实，证据基本属实（仅 error_boundary 行号有偏差）。  健康面（全部属实）： 1. lib/organisms/sidebar/tree_item.dart:100-104 — 选中态确实是 accentPrimary.withValues(alpha: 0.15)（level 1/2）/ 0.1（其余），hover 用中性 bgTertiary，克制。 2. lib/organisms/connection/tabs_bar_widget.dart:731-740 — 底部指示条确为 height: 2 + isActive ? accentPrimary : trans…）

### 4.5 SQL 语法高亮配色

#### F-22 [🔴 critical] 亮色主题下，超过 2000 字符的 SQL 首帧及超过 8000 字符（约 400 行）的脚本永久使用硬编码暗色高亮，浅

- **差距**：亮色主题下，超过 2000 字符的 SQL 首帧及超过 8000 字符（约 400 行）的脚本永久使用硬编码暗色高亮，浅绿字符串 #6AAB73 落在暖白底 #F5F3EF 上对比度仅约 2.3:1，几乎不可读。
- **现状证据**：lib/organisms/editor/sql_highlighter.dart:296-297（keyword 硬编码 #CF8E6D）、:350-355（string #6AAB73 / number #2AACB8 / punctuation #D4D4D4 全部 const 暗色 hex）、:431-439（Mongo 快速高亮同样硬编码）；触发阈值 :109-110（_syncHighlightLength=2000 / _fastHighlightLength=8000）与 :193-202（大文件只走 _fastHighlight）；亮色底 bgPrimary #F5F3EF（lib/theme/app_theme.dart:387）
- **主流做法**：Darcula 与 VS Code Dark+/Light+ 的语法色均为主题绑定：亮暗各有一套完整 token 表，任何渲染路径（含大文件降级渲染）都从当前主题取色，不存在只为暗色写的兜底色。
- **修复建议**：_fastHighlight/_fastJsonHighlight/_fastMongoHighlight 已能访问 _currentTheme（buildTextSpan :149 每帧刷新），把 const Color(0xFF…) 换成 _currentTheme['string']!.color 等即可，零新架构；若担心空值，用 SqlEditorColors(isDark).colors 直接构造。亮色下 string 用既有 #A31515、number 用 #098658，对比度即可达标。
- **核实判定**：✅ confirmed（核实通过，发现属实。逐条证据均与实际代码吻合：  1. 阈值（sql_highlighter.dart:108-110）：`_maxHighlightLength=20000`、`_syncHighlightLength=2000`、`_fastHighlightLength=8000`，与描述一致。  2. 触发逻辑（:193-202）：文本 >8000 字符时走 `_cachedSpan = _fastHighlight(style)` 并直接返回，**永久**使用快速高亮，不会再触发完整解析；2000-8000 的中等文本先返回 `_fastHighlight` 首帧，再由 `_trig…）

#### F-23 [🟠 major] 暗色高亮中 built_in #499C54、string #6AAB73、comment #6A9955 三个 tok

- **差距**：暗色高亮中 built_in #499C54、string #6AAB73、comment #6A9955 三个 token 同为绿色系且明度接近，内置函数、字符串、注释在编辑器里肉眼难分，违背'注释最低饱和、关键字与字符串对比最强'的经典纪律。
- **现状证据**：lib/theme/app_colors.dart:103-113（_dark: built_in #499C54 / string #6AAB73 / comment #6A9955），lib/organisms/editor/sql_highlighter.dart:79-89 同值复制一份
- **主流做法**：两大流派每套只有一个绿色 token：Darcula 字符串绿 #6A8759、注释是灰 #808080；VS Code Dark+ 注释绿 #6A9955、字符串是橙棕 #CE9178——绿色从不同时承担三个语义。内置函数在两派中分别走 #FFC66D/#DCDCAA（黄）或关键字同色。
- **修复建议**：选定 Darcula 流派并消除三绿撞车：comment 降为灰 #808080（Darcula 原值，保留斜体）或 #6A737D（GitHub Dark 注释灰）；built_in 与 function 统一用 #DCDCAA（VS Code Dark+ 函数黄，现成 token）；string 保留 #6AAB73。改完关键字橙/字符串绿/函数黄/注释灰四色正交，一眼可分。
- **核实判定**：✅ confirmed（色值完全属实：lib/theme/app_colors.dart:103-113 的 _dark 表中 built_in=Color(0xFF499C54)、string=Color(0xFF6AAB73)、comment=Color(0xFF6A9955)；lib/organisms/editor/sql_highlighter.dart:79-89 存在同值 darkTheme 副本（但它是 _currentTheme 查不到 key 时的回退，line 476，而 getTheme 已含全部 9 个 key，属冗余死副本，非缓解因素）。built_in 是真实高频 token：项目用 p…）

#### F-24 [🟠 major] 同一 App 内存在两套互不相关的 SQL 配色：查询编辑器用自研调色板，AI 面板代码块却硬编码 atom-one-d

- **差距**：同一 App 内存在两套互不相关的 SQL 配色：查询编辑器用自研调色板，AI 面板代码块却硬编码 atom-one-dark 背景 #282c34 / 亮色 #fafafa 及其配套高亮色，AI 给出的 SQL 与用户正在编辑的 SQL 颜色体系完全对不上。
- **现状证据**：lib/organisms/ai_panel/ai_message_item.dart:587-593、:1082、:1436、:1567（isDark ? 0xFF282c34 : 0xFFfafafa 重复 4 处，注释自述 atom-one-dark/light 主题）；编辑器侧走 SqlEditorColors（lib/theme/app_colors.dart:97-134），背景 bgPrimary #09090b（lib/theme/design_system.dart:26）
- **主流做法**：DataGrip/VS Code 内所有代码呈现面（编辑器、diff、预览、文档弹窗）共享同一个 editor color scheme，只换亮度不换色相；背景也取自同一背景层级令牌而非第三方主题自带底色。
- **修复建议**：AI 面板代码块渲染改为复用 SqlEditorColors（isDark 由 Theme.brightness 给出）作为高亮 token 源，背景用令牌 bgSecondary（暗 #18181b / 亮 #FFFFFF）或 bgPrimary 而非 #282c34/#fafafa；删不掉的第三方高亮库至少用其 'theme 自定义' 能力注入同一组 hex，保证写 SQL 与看 SQL 颜色一致。
- **核实判定**：✅ confirmed（核实属实，发现的核心主张全部得到代码证实。  实际看到的证据： 1. AI 面板侧（lib/organisms/ai_panel/ai_message_item.dart，该文件是活代码，被 ai_panel_widget.dart:1342 的 AiMessageItem 引用）：    - 第 587 行 `_buildCodeBlock`（AI 给出的 SQL 代码卡片背景）：`color: isDark ? const Color(0xFF282c34) : const Color(0xFFfafafa)`    - 第 1082 行 markdown `codeblockDecora…）

#### F-25 [🟡 minor] 暗色关键字色 #CF8E6D 与 AccentColorType.orange #cf8e6d 逐字节相同却各自硬编码，

- **差距**：暗色关键字色 #CF8E6D 与 AccentColorType.orange #cf8e6d 逐字节相同却各自硬编码，用户把 accent 切换为橙色后，SQL 关键字与按钮/选中态/标签下划线同色，语法层与 UI 层互相污染。
- **现状证据**：lib/theme/app_colors.dart:104（keyword #CF8E6D）与 lib/providers/theme_provider.dart:35（AccentColorType.orange #cf8e6d）；材料确认两者无任何共享常量
- **主流做法**：Darcula 关键字橙 #CC7832 是语法层专属色，JB 的 accent 走蓝系（#3574F0/#2F65CA），语法色与 accent 色域刻意错开；VS Code Dark+ 关键字干脆用蓝 #569CD6 但与 UI accent #007ACC 明度拉开。
- **修复建议**：关键字改用经典 Darcula 橙 #CC7832（比 #CF8E6D 略深略纯，护眼且是事实标准），既打破与 accent 橙的撞车，又让配色回归可引用的经典值；同时在 app_colors.dart 加注释说明该值为语法层专属、不随 AccentColorType 变化。
- **核实判定**：✅ confirmed（属实。代码证据：(1) lib/theme/app_colors.dart:104 `SqlEditorColors._dark` 中 `'keyword': Color(0xFFCF8E6D)`；(2) lib/providers/theme_provider.dart:35 `AccentColorType.orange` 返回 `const Color(0xFFcf8e6d)`，两者 ARGB 逐字节相同（0xFFCF8E6D）。(3) 无共享常量属实：全库 grep 命中 7 处独立硬编码（另有 performance_models.dart:298 及 sql_highlighter…）

#### F-26 [🟡 minor] 亮色主题的 operator/punctuation 用纯黑 #000000，比正文 textPrimary #2D2D

- **差距**：亮色主题的 operator/punctuation 用纯黑 #000000，比正文 textPrimary #2D2D2D 更黑，标点在视觉上反而比标识符更'重'；暗色 number #2AACB8（青）既不属 Darcula 数字蓝 #6897BB 也不属 Dark+ 浅绿 #B5CEA8，且与 info #06b6d4/schemaCyan 同族，数字在满屏 token 里发闷下陷。
- **现状证据**：lib/theme/app_colors.dart:123-125（亮色 operator/punctuation #000000）vs lib/theme/app_theme.dart:390（textPrimary #2D2D2D）；暗色 number #2AACB8（app_colors.dart:107）vs info #06b6d4（lib/theme/design_system.dart:100）、schemaCyan #06B6D4（:150）
- **主流做法**：VS Code Light+ 标点与正文同深（默认前景 #000000 体系内一致，但其正文本身也是纯黑）；GitHub Light/Dark 的标点一律回落到 fg.default 而非更黑。数字取与关键字互补的亮色：Darcula #6897BB、Dark+ #B5CEA8，均明显亮于 DbMaster 的 #2AACB8。
- **修复建议**：亮色 operator/punctuation 改为 textPrimary 同款 #2D2D2D（或直接取 ThemeColors.textPrimary，免硬编码）；暗色 number 若走 Darcula 流派改 #6897BB（与关键字橙互补、远离 info 青），若走 Dark+ 流派改 #B5CEA8——配合第 2 条选定流派后统一替换，一处改动即可。
- **核实判定**：⚠️ exaggerated（存在但程度/范围被夸大）
- **核实备注**：色值与行号全部核实无误：lib/theme/app_colors.dart:123、125 亮色 operator/punctuation = Color(0xFF000000)，:107 暗色 number = Color(0xFF2AACB8)；lib/theme/app_theme.dart:390 亮色 textPrimary = Color(0xFF2D2D2D)；lib/theme/design_system.dart:100 info = #06b6d4、:150 schemaCyan = #06B6D4（与 #2AACB8 同属青色系，属实）。但发现被忽略的缓解因素，发现被夸大：(1) 该配色表由 SqlHighlightTheme.getTheme（lib/organisms/editor/sql_highlighter.dart:59-76）按 highlight.js class 名查表消费；我逐一 grep 了 pub-cache 中 highlight-0.7.0 的 sql/json/javascript/lua 四个语法文件（SqlHighlightController 只注册这四种，sql_highlighter.dart:132-137），它们发出的 class 仅含 keyword/literal/built_in/string/number/comment/doctag/attr/function/variable 等，均不发出 'operator' 或 'punctuation'。因此亮色 #000000 两项是死配置——SQL 编辑器里标点/操作符实际走 baseStyle，即 textPrimary #2D2D2D，评审所称"标点在视觉上比标识符更重"的画面在真实编辑器中不存在（快速高亮路径 _fastSqlHighlight 等更是直接硬编码色值，不经过该表）。(2) 暗色 number #2AACB8 确为活配置（SQL 经 C_NUMBER_MODE、JS 语法均发 number class，且 _fastJsonHighlight/_fastMongoHighlight 硬编码同色，甚至亮色主题下中等长度 JSON/Mongo 文本也会用到它），与文件注释自称的"VS Code Dark+ 风格"不符（Dark+ 数字实为浅绿 #B5CEA8）这一点成立；但"发闷下陷"属主观审美判断，且 #2AACB8 只是与 info/schemaCyan 同族而非同色，在满屏 token 中并不至于不可读。综合：事实陈述（色值、对比、风格不符）成立，但亮色半条的实际视觉影响为零（死配置），暗色半条为真实但轻微的一致性问题，整体严重度应低于 minor 或仅在 minor 下限，故判 exaggerated。

### 4.6 数据网格视觉

#### F-27 [🔴 critical] 数据网格行高 40px 是消费级 App 的疏松密度，与专业数据库工具的高密度网格差距一眼可见，同屏可见行数几乎只有主流

- **差距**：数据网格行高 40px 是消费级 App 的疏松密度，与专业数据库工具的高密度网格差距一眼可见，同屏可见行数几乎只有主流工具的一半
- **现状证据**：行高默认 40.0（lib/organisms/results/virtualized_data_table.dart:79），且表头（:349）、行（:449）、行号单元格（:478）、底部行数/分页栏（:401）全部复用同一 40px；单元格 padding 仅 horizontal space2，垂直方向大量留白
- **主流做法**：DataGrip 经典 Darcula 行高 20px、JetBrains New UI 24px（darcula.theme.json / expUI_dark.theme.json Table/List 键）；基准共识为数据网格行高 20-24px、高密度低装饰，NULL 灰化、信息优先
- **修复建议**：数据行高降到 24-26px（建议 26px，兼顾 13px 字号行高 1.4 与 hover 点击目标），表头 28px，底部状态/分页栏 28-32px；列宽默认值 150 可保留。若担心密度突变，可提供 紧凑/舒适 两档行高设置（TablePlus/DBeaver 均有行高自定义），默认紧凑
- **核实判定**：✅ confirmed（代码证据全部属实：lib/organisms/results/virtualized_data_table.dart:79 默认 rowHeight=40.0；表头(:349)、行(:449)、行号单元格(:478)、底部行数栏(:401)及行号表头(:381)全部 height: widget.rowHeight，分页栏 :1020 另硬编码 height: 40。单元格 padding :609-611 为 EdgeInsets.symmetric(horizontal: AppDesignSystem.space2=8.0)，垂直零 padding，13px monospace 字体在 …）

#### F-28 [🟠 major] 数字列不做右对齐，所有值统一左对齐，违背数据网格'数字右对齐、文本左对齐'的通用惯例，数值大小比较与位宽扫读困难

- **差距**：数字列不做右对齐，所有值统一左对齐，违背数据网格'数字右对齐、文本左对齐'的通用惯例，数值大小比较与位宽扫读困难
- **现状证据**：单元格统一 Alignment.centerLeft（virtualized_data_table.dart:612），无按列类型的对齐分支；字体 fontSize 13 monospace 左对齐（:650-652）。列类型元数据其实已存在：widget.columnTypes?[col] ?? ColumnDataType.string（:363）但只用于表头，未用于单元格对齐
- **主流做法**：基准共识第 7 条：'数字右对齐、文本左对齐为通用惯例'；Navicat/DBeaver/TablePlus 均默认数字列右对齐、NULL 灰化
- **修复建议**：在 _buildCell 中按 widget.columnTypes[columnName] 判断：ColumnDataType 的整数/小数/数值类型用 Alignment.centerRight（保持 monospace 使位宽对齐），文本/日期/JSON 维持 centerLeft；右对齐列的 padding 对称保留 space2
- **核实判定**：✅ confirmed（属实。实际文件路径为 lib/organisms/results/virtualized_data_table.dart（非证据中省略路径，但行号完全吻合）。核实结果：  1. 单元格容器第 612 行确为 `alignment: Alignment.centerLeft`，是全文件唯一的数据单元格对齐设置；在整个 results 目录下 grep `centerRight|TextAlign.right` 仅命中 query_history/result_history_table.dart（历史记录面板，与本网格无关），数据网格无任何按列类型的对齐分支。  2. 第 650-652 行确认…）

#### F-29 [🟠 major] 斑马纹跨两档 Zinc 灰阶（#09090b vs #18181b）对比偏强，且数据区主底用近纯黑的 Zinc-950，

- **差距**：斑马纹跨两档 Zinc 灰阶（#09090b vs #18181b）对比偏强，且数据区主底用近纯黑的 Zinc-950，长时间浏览时带状条纹比主流工具更显眼
- **现状证据**：偶数行 bgSecondary #18181b、奇数行 bgPrimary #09090b（virtualized_data_table.dart:434-436；令牌 lib/theme/design_system.dart:26,29）；行 hover 直接跳 bgTertiary #27272a（:445-446），hover 与斑马纹反差同样偏大
- **主流做法**：JetBrains New UI Table.stripeColor Gray2 #2B2D30 对基底 Gray1 #1E1F22 仅差一档灰、对比极弱（expUI_dark.theme.json Table 键）；TablePlus 暗色斑马纹弱到被用户报 issue 说'看不见'（TablePlus issue #476）；基准共识：斑马纹与底仅一档灰、大面积不用纯黑
- **修复建议**：斑马纹收敛为一档：基底 bgSecondary #18181b，条纹用 #1C1C1F（或 bgTertiary #27272a @ 35% alpha 叠加，约 #1F1F22）；hover 色同步收敛为 #26262A 量级，保持 hover 可辨但不刺眼。基底若坚持用 bgPrimary，则条纹改 #101013
- **核实判定**：✅ confirmed（代码证据全部属实，行号精确对应：  1) lib/organisms/results/virtualized_data_table.dart:433-436：`final isEven = rowIndex.isEven; final baseRowColor = isEven ? context.themeColors.bgSecondary : context.themeColors.bgPrimary;`——斑马纹确为偶数行 bgSecondary / 奇数行 bgPrimary。445-447 行 hover：`hoveredRow == rowIndex ? context.them…）

#### F-30 [🟡 minor] 单元格字体写死通用族名 'monospace'，Windows 下无此实体字体、会回落到系统默认（可能不是等宽字体），且

- **差距**：单元格字体写死通用族名 'monospace'，Windows 下无此实体字体、会回落到系统默认（可能不是等宽字体），且与 SQL 编辑器的 JetBrains Mono 字体栈不一致
- **现状证据**：单元格/行号均 fontFamily: 'monospace'（virtualized_data_table.dart:490,652）；而 SQL 编辑器声明的是完整字体栈 JetBrains Mono → Fira Code → Consolas → Monaco → Courier New（lib/organisms/editor/sql_highlighter.dart:17-27）
- **主流做法**：专业工具的表格与编辑器共用同一等宽字体栈（JetBrains 系全 IDE 默认 JetBrains Mono；TablePlus/DBeaver 表格跟随编辑器字体设置），保证数字位宽对齐与视觉统一
- **修复建议**：抽出共享常量（如 AppDesignSystem.monoFontFamilyFallback = ['JetBrains Mono','Fira Code','Consolas','Monaco','Courier New']），数据网格单元格、行号、编辑态单元格统一引用，与 SQL 编辑器同栈
- **核实判定**：✅ confirmed（逐条核实后确认属实。（1）代码证据与描述完全一致：lib/organisms/results/virtualized_data_table.dart:490 行号单元格 TextStyle(fontSize: 11, color: textMuted, fontFamily: 'monospace')；:652 数据单元格 TextStyle(fontSize: 13, fontFamily: 'monospace', ...)；另有 :227 测量用 valueStyle 与 :676 编辑态单元格同样写死 'monospace'。lib/organisms/editor/sql_highl…）

#### F-31 [🟡 minor] 次要元素的线条反而更重：行号列右边框用不透明 borderLight，比数据行分隔线（同色的 50% alpha）更抢眼

- **差距**：次要元素的线条反而更重：行号列右边框用不透明 borderLight，比数据行分隔线（同色的 50% alpha）更抢眼，视觉层级倒挂；表头与数据区之间缺少一条明确分界
- **现状证据**：数据行底线 borderLight #3f3f46 @ alpha 0.5（virtualized_data_table.dart:453-454）有效色约 #242429（克制、健康）；但行号列右边框用不透明 borderLight（:482-484，行号表头 :385 同），数据列之间零垂直分隔（:462-465 SizedBox 连续排列）；表头仅靠 bgTertiary 色块与数据区分隔，无底部强调线
- **主流做法**：DataGrip Table.gridColor #4F5152 极暗、TableHeader 有独立分隔线 #333638（darcula.theme.json）；VS Code/GitHub 系网格普遍只保留水平极暗行线，表头下缘一条略强的分界线建立层级
- **修复建议**：行号列右边框降为 borderLight @ 0.5 与行线同档；表头底部加一条 1px 不透明 borderLight 作为 header/数据区的明确分界（DataGrip TableHeader 有独立 separatorColor #333638）；列间维持无竖线即可
- **核实判定**：✅ confirmed（代码事实逐条核实属实（lib/organisms/results/virtualized_data_table.dart）： 1) 数据行底线 :452-455 确为 `border: Border(bottom: BorderSide(color: context.themeColors.borderLight.withValues(alpha: 0.5)))`，即 #3f3f46（暗色）50% alpha，有效色确实更淡。 2) 行号列单元格右边框 :480-483 确为不透明 `BorderSide(color: context.themeColors.borderLight)`；行号表…）

### 4.7 亮色主题完成度

#### F-32 [🔴 critical] atoms 层活代码直接消费暗色令牌，亮色模式下 loading 遮罩是一层近黑纱（#09090b@70%）、AppCa

- **差距**：atoms 层活代码直接消费暗色令牌，亮色模式下 loading 遮罩是一层近黑纱（#09090b@70%）、AppCard 是黑卡片（#18181b），亮色是暗色的附属品这一判断在这些组件上肉眼成立。
- **现状证据**：lib/atoms/app_widgets.dart:97 `AppDesignSystem.bgPrimary.withOpacity(0.7)`（bgPrimary=#09090b, design_system.dart:26）、:591 `AppDesignSystem.bgSecondary`（#18181b, design_system.dart:29）、:596 borderDefault；全文件 28 处 AppDesignSystem.bg/text/border 直连、零处 context.themeColors；该文件被 sidebar_tree.dart / results_widget.dart / welcome_screen.dart / main_workspace.dart / tree_item.dart 5 处活代码 import。
- **主流做法**：Navicat/TablePlus/DataGrip 亮色模式下不存在任何暗色硬编码背景；所有组件色值必须经由主题令牌解析（Flutter 中等同于 Theme.of(context).colorScheme 或语义 token 层），亮暗切换是令牌表整体替换，而非组件各自为战。
- **修复建议**：把 app_widgets.dart 的 37 处 AppDesignSystem 静态引用全部改为 context.themeColors.*（bgPrimary→ThemeColors.bgPrimary=Theme.scaffoldBackgroundColor，bgSecondary/textPrimary/borderDefault 同理）；同时删除/归档疑似死代码 app_button.dart、form_controls.dart（lib/ 内零 import 且同样直连暗色令牌），消除亮色盲区存量。
- **核实判定**：⚠️ exaggerated（存在但程度/范围被夸大）
- **核实备注**：证据逐条核验结果：① lib/atoms/app_widgets.dart:97 确为 `color: AppDesignSystem.bgPrimary.withOpacity(0.7)`（AppLoadingOverlay 内），bgPrimary=#09090b 见 design_system.dart:26；② :591 确为 AppCard 的 `color: AppDesignSystem.bgSecondary`（#18181b, design_system.dart:29），:596 确为 borderDefault；③ grep 精确计数该文件 AppDesignSystem.bg/text/border/divider 直连 28 处，与发现一致；④ context.themeColors 主题感知扩展确实存在（lib/theme/app_colors.dart:9-10，含 _isDark 分支的亮色文本/边框），但 app_widgets.dart 零处使用；⑤ 全 lib/ 仅 5 个 import 者：sidebar_tree.dart、results_widget.dart、welcome_screen.dart、main_workspace.dart、tree_item.dart，与发现完全一致。亮色主题确实存在（app_theme.dart:385 lightTheme，scaffold #F5F3EF 暖白、文字 #2D2D2D）。但发现被忽略的重大缓解因素：被点名的两个" Exhibit "组件在生产代码中是死代码——AppLoadingOverlay 全 lib/ 无任何实例化（仅 test/atoms/app_widgets_test.dart 和 docs 规格表出现），AppCard（app_widgets.dart 版）同样全 lib/ 零实例化（另有一个 app_card.dart 的同名 AppCard 也无人 import）。因此"亮色模式下 loading 遮罩是近黑纱、AppCard 是黑卡片"这一具体视觉场景在真实运行的 app 中不会发生，"肉眼成立"对这两个组件不成立。不过该文件的暗色令牌直连在活代码中真实可见：AppEmptyState（:178-181 title 用 textPrimary=#fafafa、:193-195 描述用 textTertiary）被 welcome_screen.dart:214、main_workspace.dart:138/144、sidebar_tree.dart:122、results_widget.dart:601 共 5 处核心路径活调用——亮色模式下标题是近白文字渲染在暖白背景上，基本不可读；AppStatusBadge 在 tree_item.dart:203 活使用（语义色+0.15 透明度底，暗色调优）。结论：文件级事实（行号、计数、import 关系、零主题感知）全部精确属实，"亮色是暗色附属品"的判断经由 AppEmptyState 在核心界面成立且严重；但两个旗舰例证组件是死代码，可达影响面被夸大——实际受害面是亮色模式下主工作区/侧栏/结果区/欢迎页的空状态文字近不可见，而非 loading 遮罩和黑卡片。

#### F-33 [🔴 critical] SQL 编辑器快速高亮兜底路径硬编码暗色 hex，亮色模式下标点色 #D4D4D4 在暖白 #F5F3EF 底上近乎隐形

- **差距**：SQL 编辑器快速高亮兜底路径硬编码暗色 hex，亮色模式下标点色 #D4D4D4 在暖白 #F5F3EF 底上近乎隐形，字符串绿 #6AAB73、数字青 #2AACB8 对比严重不足——亮色 SQL 高亮在 fast path 下是破损的。
- **现状证据**：lib/organisms/editor/sql_highlighter.dart:296-297 keyword 硬编码 #CF8E6D；:350-355 string #6AAB73 / number #2AACB8 / keyword #CF8E6D / punctuation #D4D4D4，无 isDark 分支；而行内错误点 :848-857 同样硬编码 #ef4444/#f59e0b/#3b82f6。项目其实已有亮色语法表 SqlEditorColors._light（app_colors.dart:116-126：keyword #AF5B1E、string #A31515、operator #000000），兜底路径未使用。
- **主流做法**：VS Code 官方 Dark+/Light+ 是两套独立 token 表（dark_plus.json 标点/文字 #D4D4D4，Light+ 为 #000000/#0451A5 量级），暗色浅灰 token 绝不允许落入亮色渲染路径；DataGrip 同理（Darcula 与 IntelliJ Light 各自完整）。
- **修复建议**：_fastSqlHighlight/_fastJsonHighlight 增加 isDark 入参（或从 context 读取），颜色一律从 SqlEditorColors(isDark: ...) 取；亮色建议直接用既有 _light 表：punctuation/operator #000000、string #A31515、number #098658、keyword #AF5B1E；行内错误点改用 AppDesignSystem.error/warning 令牌（当前 0xFFef4444 与令牌逐字节重复，属无意义硬编码）。
- **核实判定**：✅ confirmed（代码证据逐条核实属实：lib/organisms/editor/sql_highlighter.dart:296-297 中 _fastSqlHighlight 硬编码 keyword Color(0xFFCF8E6D)，无 isDark 分支；:349-355 中 _fastJsonHighlight 硬编码 string #6AAB73 / number #2AACB8 / keyword #CF8E6D / punctuation #D4D4D4（注：标点色属 JSON 快路径，SQL 快路径只染 keyword）；:848-857 _getErrorColor 硬编码 #ef4444/…）

#### F-34 [🟠 major] accent 双轨：用户换肤只改 Material ColorScheme，静态令牌引用处（标签页指示条、排序列表头、光

- **差距**：accent 双轨：用户换肤只改 Material ColorScheme，静态令牌引用处（标签页指示条、排序列表头、光标、外键链接等）永远停留在 #0ea5e9，亮暗两色下都会同时出现两种主色。
- **现状证据**：lib/providers/theme_provider.dart:29 AccentColorType.blue=#3574f0（另有 7 色 purple #9e7dd3 等）与 design_system.dart:80 accentPrimary=#0ea5e9 零交集；theme_provider.dart:235-252 _applyAccentColor 仅改 primaryColor/ColorScheme/FAB/ElevatedButton；而 tabs_bar_widget.dart:731-740 活动指示条、column_filter_widget.dart:488-495 排序列、sql_highlighter.dart:727-728 光标、virtualized_data_table.dart:653-658 外键链接均走静态令牌 #0ea5e9。
- **主流做法**：主流工具 accent 是单一源：TablePlus 自定义 accent 全 UI 生效；JetBrains 的 accent 色（#3574F0）经令牌层统一下发，selection/focus/button 全部跟随。用户可换肤的工具不存在'半套 UI 不换色'的状态。
- **修复建议**：把 accentPrimary/accentHover/accentSubtle 从静态常量升级为 ThemeColors 内基于 ColorScheme.primary 的 getter（accentPrimary→colorScheme.primary，hover/subtle 由其派生），ThemeProvider._applyAccentColor 只负责写 ColorScheme；静态引用处逐步迁移。短期可先统一默认值：要么 AccentColorType.blue 改 #0ea5e9，要么 accentPrimary 改 #3574f0，先消灭双主色并存。
- **核实判定**：✅ confirmed（属实。代码证据：(1) theme_provider.dart:29 AccentColorType.blue=Color(0xFF3574f0)，共 8 色（purple #9e7dd3 等），accentColorValue getter(148 行）返回之；(2) design_system.dart:80 accentPrimary=Color(0xFF0ea5e9)，与 8 色零交集；(3) _applyAccentColor(theme_provider.dart:235-252）及 main.dart:93-94 实际调用的 AppTheme.light/dark(colorSe…）

#### F-35 [🟠 major] 亮色令牌无同源定义，双份硬编码且已发生命名漂移

- **差距**：亮色令牌无同源定义，双份硬编码且已发生命名漂移——同一个 #E8E5E0 在 app_theme 里叫 dividerColor、在 app_colors 里是 bgQuaternary，改一次亮色需要人肉同步两处。
- **现状证据**：lib/theme/app_theme.dart:387-393 lightTheme 局部常量（#F5F3EF/#FFFFFF/#F0EDE8/#2D2D2D/#6B6B6B/#E5E1DB/#E8E5E0）与 lib/theme/app_colors.dart:53-75 ThemeColors getter 内的 const Color(0xFF...) 各自硬编码同一组值（bgSecondary #FFFFFF、bgTertiary #F0EDE8、textSecondary #6B6B6B、borderLight #E5E1DB 均双份）；暗色侧则集中在 AppDesignSystem（design_system.dart:26-75）单源，亮暗架构严重不对称。
- **主流做法**：GitHub primer 与 JetBrains 都是亮暗各一份完整 token 表（dark.json5 / light.json5、Gray1-14 色阶），语义层一份映射代码引用两套基元；改色只动 token 表，不存在双处硬编码。
- **修复建议**：在 AppDesignSystem 内增设 light 色阶常量区（bgPrimaryLight #F5F3EF、bgSecondaryLight #FFFFFF、bgTertiaryLight #F0EDE8、bgQuaternaryLight #E8E5E0、textPrimaryLight #2D2D2D、textSecondaryLight #6B6B6B、textMutedLight #9CA3AF、borderLight #E5E1DB），lightTheme 与 ThemeColors 统一引用，删除全部内联 const Color(0xFF...)。
- **核实判定**：✅ confirmed（属实。逐项核实结果：  1) 亮色双份硬编码确认。lib/theme/app_theme.dart:385-393 `lightTheme` getter 内定义局部常量：bgPrimary #F5F3EF、bgSecondary #FFFFFF、bgTertiary #F0EDE8、textPrimary #2D2D2D、textSecondary #6B6B6B、borderColor #E5E1DB、dividerColor #E8E5E0（393 行注释"分隔线"），并在 455 行 `dividerTheme: const DividerThemeData(color: divide…）

#### F-36 [🟡 minor] 亮色文字明度梯度断裂：textDisabled #696f77 比 textMuted #9CA3AF 更深、与 tex

- **差距**：亮色文字明度梯度断裂：textDisabled #696f77 比 textMuted #9CA3AF 更深、与 textSecondary #6B6B6B 几乎同明度（lum≈110 vs 107），禁用态在亮色下视觉上无法与次要文字区分。
- **现状证据**：lib/theme/app_colors.dart:71 textSecondary=#6B6B6B、:73 textMuted=#9CA3AF、:75 textDisabled=#696f77——亮色梯度为 #2D2D2D→#6B6B6B→#9CA3AF，但 disabled 回落到 #696f77，顺序倒挂；且 textMuted #9CA3AF 是 Tailwind Gray-400 混入暖灰体系（app_colors.dart:73 注释无来源），与 #E8E5E0/#F0EDE8 的暖色阶色相不一致。
- **主流做法**：共识是文字明度梯度单调：主→次→弱→禁用逐档变浅（GitHub light: #1F2328→#59636E→#8C959F；JetBrains light 同理 disabled 最浅），禁用永远比次要文字更弱，绝不能更深或同级。
- **修复建议**：亮色 textDisabled 改为比 muted 更浅的暖灰，建议 #B5B1AB 或 #A8A29E（Tailwind Stone-400，与暖色阶同族）；textMuted 同步换成暖灰族 #8A857E 量级，保证 #2D2D2D→#6B6B6B→#8A857E→#B5B1AB 单调递减且色相统一。
- **核实判定**：✅ confirmed（代码事实全部属实。lib/theme/app_colors.dart 实际内容：:70-71 textSecondary 亮色 = Color(0xFF6B6B6B)；:72-73 textMuted 亮色 = Color(0xFF9CA3AF)（该行确无来源注释）；:74-75 textDisabled 亮色 = Color(0xFF696f77)。亮色 textPrimary = #2D2D2D（lib/theme/app_theme.dart:390，经 onSurface 于 :409 接入）。明度核验（Rec.601 感知明度）：#6B6B6B≈107、#696f77≈110、#9C…）

#### F-37 [🟡 minor] 语义色与 ColorScheme 的亮暗不对称：success/warning/error/info 亮暗同用一套亮色值

- **差距**：语义色与 ColorScheme 的亮暗不对称：success/warning/error/info 亮暗同用一套亮色值，暖白底上 #22c55e/#f59e0b 对比偏弱；同时 darkTheme 的 ColorScheme.dark 未设 outline，导致亮色边框走令牌 #E5E1DB、暗色边框回落 Material 默认灰而非令牌 #27272a，亮暗边框来源不一致。
- **现状证据**：lib/theme/design_system.dart:91-100 success #22c55e / warning #f59e0b / error #ef4444 / info #06b6d4 静态常量无亮色变体；lib/theme/app_theme.dart:470-479 ColorScheme.dark 缺 outline/outlineVariant/divider（亮色 :411 设了 outline #E5E1DB），ThemeColors.borderColor（app_colors.dart:78 取 colorScheme.outline）暗色下回落 Material 默认值。
- **主流做法**：共识：暗色语义色提亮降饱和、亮色语义色加深保对比——GitHub light danger fg #CF222E / success fg #1A7F37 / attention #9A6700，与暗色 #F85149/#3FB950/#D29922 是两套值；亮暗 ColorScheme 字段应对称配置。
- **修复建议**：为亮色补一套加深语义色：success #16A34A、warning #B45309、error #DC2626、info #0891B2（Tailwind 600 档），经 ThemeColors 按 _isDark 分发；darkTheme 的 ColorScheme.dark 显式补 outline: Color(0xFF3F3F46)（=borderLight）与 outlineVariant: Color(0xFF27272A)（=borderDefault），使亮暗边框都出自令牌。
- **核实判定**：✅ confirmed（逐项核实均属实：  1) 语义色无亮暗变体——lib/theme/design_system.dart:91/94/97/100 确为静态常量 success=Color(0xFF22c55e)、warning=0xFFf59e0b、error=0xFFef4444、info=0xFF06b6d4，全文件无任何亮色主题变体；lib/theme/app_colors.dart:83-91 注释明写 "Accent colors - consistent across themes"，accentGreen/Orange/Red/Cyan 两主题直通同一令牌，亮暗确实共用一套值。暖白底（app_t…）

### 4.8 视觉一致性（图标/圆角/阴影/字体落地）

#### F-38 [🔴 critical] 数据库类型与 AI provider 图标用系统 emoji 文本渲染，Windows 上显示为彩色 Segoe UI 

- **差距**：数据库类型与 AI provider 图标用系统 emoji 文本渲染，Windows 上显示为彩色 Segoe UI Emoji，与全 App Material Icons 矢量风格正面冲突，第一眼就显得不专业
- **现状证据**：emoji _iconMap 定义于 lib/models/database_models.dart:92-101（🐬🐘📁🚀🔴🍃⚡📊），实际渲染点 6 处：welcome_screen.dart:241、sidebar_widget.dart:1085、connection_dialog.dart:738/:1659、query_editor_widget.dart:2264、ai_panel_widget.dart:1036，均以 Text(type.icon) 文本渲染；AI 面板另有 🤖🎭✨（ai_models.dart:15-92，ai_settings_dialog.dart:286 渲染）、⚙️📇📊✅❌（ai_panel_widget.dart:161/:2173/:2342 等）拼进消息文本。materialIcon getter（database_models.dart:141）已存在但仅 sidebar_tree.dart:716、schema_diff_page.dart:898 两处启用
- **主流做法**：DataGrip/DBeaver/Navicat/TablePlus 全部使用矢量品牌图标（SVG 数据库 logo 或单色 glyph），颜色受主题控制；VS Code/JetBrains 全系禁止 UI 内嵌 emoji 当功能图标，emoji 仅出现在用户内容里
- **修复建议**：完成已启动的迁移：全部 6 个 emoji 渲染点切到 materialIcon（Icons.storage/cable/cloud 等语义映射）；数据库品牌识别用 dbMysql #00758F/dbPostgresql #336791 等已有的品牌色令牌给矢量图标着色，替代 emoji 的颜色职能；AI provider 图标改用 Icons.smart_toy/psychology 等 + 着色圆底。短期若想要品牌 logo，可引入 font_awesome_flutter 或自打包 SVG 品牌图标集
- **核实判定**：✅ confirmed（逐项核实，证据全部属实，无遗漏缓解因素。1) emoji _iconMap 确在 lib/models/database_models.dart:92-101（🐬🐘📁🚀🔴🍃⚡📊），String get icon 在 :139。2) 6 处 Text(type.icon) 渲染点逐一验证：welcome_screen.dart:240-243（ActionChip avatar 内 Text(conn.type.icon)）、sidebar_widget.dart:1084-1087（Container Center 内 Text(conn.type.icon, fontSize 18)）、co…）

#### F-39 [🟠 major] 设计声明的 Inter 与 JetBrains Mono 均未打包进应用，实际渲染静默回退到各 OS 系统字体，声明字体

- **差距**：设计声明的 Inter 与 JetBrains Mono 均未打包进应用，实际渲染静默回退到各 OS 系统字体，声明字体链形同虚设且跨平台字形不一致
- **现状证据**：lib/theme/app_theme.dart:400/:469 声明 fontFamily: 'Inter'，但 pubspec.yaml 无 fonts: 段、assets/ 下只有 config 与 gumroad 目录（本次核实）；SQL 编辑器声明 JetBrains Mono 回退 Fira Code/Consolas（lib/organisms/editor/sql_highlighter.dart:17-27）同样未打包；数据网格直接用通用 'monospace'（lib/organisms/results/virtualized_data_table.dart:227,652）
- **主流做法**：JetBrains 全系 IDE 捆绑 JetBrains Runtime 自带字体、VS Code 打包其图标与默认等宽字体栈、TablePlus 明确选择系统原生字体作为设计决策——要么打包要么明确用系统字体，没有'声明了但不存在'的做法
- **修复建议**：把 Inter（Regular/Medium/SemiBold 四重）与 JetBrains Mono（Regular/Bold）woff2/ttf 打入 assets/fonts 并在 pubspec fonts: 注册；或将设计决策改为显式系统字体栈（Windows Segoe UI Variable / macOS .AppleSystemUIFont）并删除 Inter 声明——二选一，不要保留'声明了但不发货'的中间态；数据网格 'monospace' 改为与编辑器同一字体令牌
- **核实判定**：✅ confirmed（属实，全部证据点核实通过。(1) lib/theme/app_theme.dart:400 与 :469 两处 ThemeData 均声明 fontFamily: 'Inter'（light/dark 主题各一）。(2) pubspec.yaml 完整 77 行：无 fonts: 段、无 google_fonts 依赖，assets 仅声明 assets/config/。(3) assets/ 目录实测只有 config 与 gumroad 两个子目录；全仓搜 .ttf/.otf 仅命中 dist/ 构建产物中的 Flutter 内置图标字体（MaterialIcons、CupertinoIc…）

#### F-40 [🟠 major] 圆角令牌只定义了 6/10 两级，实际代码 607 处硬编码 BorderRadius 用 7 种不同取值（4/8/6/

- **差距**：圆角令牌只定义了 6/10 两级，实际代码 607 处硬编码 BorderRadius 用 7 种不同取值（4/8/6/12/3/2/5），圆角体系名存实亡
- **现状证据**：令牌仅 radiusSm 6.0/radiusMd 10.0 两级（lib/theme/design_system.dart:188-189），legacy radiusXs 4/radiusLg 16/radiusXl 24 未删（:193-197）且 app_theme.dart:131-134 再复制一份；实测全 lib/ 硬编码 BorderRadius.circular 607 处 vs 令牌引用 189 处，取值直方图 4px(171)/8px(105)/6px(95)/10-16px(41)/3px(20)/2px(18)/5px(1)；阴影同理：BoxShadow 硬编码 24 处 vs shadowFloat/shadowModal 令牌引用 12 处，legacy shadowSm(#20000000)/shadowXl(#50000000) 与主令牌不同值仍可用（design_system.dart:245-260）
- **主流做法**：JetBrains New UI 全 UI 统一 8px 圆角（组件内 4px），VS Code 近乎零圆角——主流是极窄的 2-3 档标尺且强制执行；语义阴影也只保留浮层/模态两档
- **修复建议**：收敛为三级圆角标尺（radiusSm 6 / radiusMd 8 / radiusLg 12，覆盖 90% 现状用量），删除 radiusXs/Xl 与 app_theme.dart 复制品，607 处硬编码按'容器 8、控件 6、卡片/对话框 12'规则 codemod 替换；阴影删除 shadowSm/shadowXl 旧值，24 处 BoxShadow 归并到 shadowFloat/shadowModal
- **核实判定**：⚠️ exaggerated（存在但程度/范围被夸大）
- **核实备注**：核心结论"圆角体系名存实亡"成立，但头条数字口径错误、范围被夸大。(1) 令牌定义属实：design_system.dart:188-189 仅 radiusSm=6.0/radiusMd=10.0 两级；:193-197 legacy radiusXs=4/radiusLg=16/radiusXl=24 带 @Deprecated 未删；app_theme.dart:131-134 确以硬编码字面量再复制 radiusLg=16.0/radiusXl=24.0。(2) "607 处硬编码"夸大：607 是 lib/ 下 BorderRadius.circular( 的总出现数（149 文件，与评审数一致），但其中 135 处是令牌引用（BorderRadius.circular(AppDesignSystem./AppTheme.xxx)），真实硬编码数字字面量约 451 处——评审自己的直方图求和也正好是 451，与标题 607 自相矛盾；另有 ~21 处变量表达式。评审所称"令牌引用 189"实为 radiusSm|Md|Xs|Lg|Xl 名字在 lib/ 的全部出现（含定义行/注释/ClipRRect），恰好 189。(3) 直方图单值档精确（4px=171/8px=105/6px=95/3px=20/5px=1 全部吻合），合并档有偏差："10-16px(41)"实为 10-16 区间 37 处（41 混入 20px×3+24px×1）；"2px(18)"实为 14（18 混入 1px×4）。不同取值实为 12 种（1/2/3/4/5/6/8/10/12/16/20/24），非 7 种。(4) 阴影细节错但实情更糟：BoxShadow( 全 lib/ 24 处中 5 处在 theme（4 处是令牌定义+app_theme.dart:238），业务硬编码实为 19 处；"shadowFloat/shadowModal 令牌引用 12 处"不属实——canonical 令牌在 theme 外引用为 0，仅 3 处 legacy 引用（shadowSm×2 于 app_icon_button.dart:350/interactive_widgets.dart:207、shadowLg×1 于 connection_dialog.dart:1391），主阴影令牌无人用。legacy 值不同属实：shadowSm=0x20000000(:245-247) vs shadowFloat=0x26000000(:224-231)、shadowXl=0x50000000(:253-259) vs shadowModal=0x40000000(:234-241)，且 shadowSm 仍在 2 处活代码使用。(5) 缓解因素：legacy 令牌均带 @Deprecated，属项目源码（design_system.dart）@Deprecated 注解明文记录的迁移中状态，但无强制机制。综合：硬编码规模被夸大约 35%（451 而非 607），阴影令牌引用数系误记（0 而非 12），但"令牌两级+硬编码泛滥+体系名存实亡"的定性判断与 major 严重度在 451 处硬编码、12 种取值、canonical 阴影令牌零引用的事实下依然成立。

---

## 5. 修复路线图（按投入产出比）

### 第一批：令牌值调整（零结构改动，消灭 4 个 critical） ✅ 已完成（`64bfc53c`，2026-07-23）

| # | 改动 | 涉及文件 | 对应发现 |
|---|------|---------|---------|
| 1 | 亮色 textMuted `#9CA3AF` → `#78716C`（stone-500 暖灰，on 白底 4.8:1） | `lib/theme/app_colors.dart:73` | F 对比度-critical |
| 2 | 语义色增加亮色变体：warning `#B45309`、success `#16A34A`、info `#0891B2`、error `#DC2626`，经 ThemeColors 按主题分发 | `lib/theme/design_system.dart:91-100` | F 语义-critical |
| 3 | 暗色 textPrimary `#fafafa` → `#e4e4e7`、textTertiary `#71717a` → `#94949E`、textDisabled 降至 `#5F5F66` | `lib/theme/design_system.dart:52,58,61` | F 对比度-major×2 |
| 4 | 暗色 ColorScheme 补齐：`outline=#3f3f46`、`outlineVariant=#27272a`、`surfaceContainer*` 三档，增加 dialogTheme/dividerTheme | `lib/theme/app_theme.dart:470-479` | F 表面-major |
| 5 | 数据网格行高 40→26px（表头 28px）、数字列按 `columnTypes` 右对齐 | `lib/organisms/results/virtualized_data_table.dart:79,612` | F 网格-critical/major |

### 第二批：收编（消灭"体系外颜色"） 🟡 主体完成（`47420b06`，2026-07-23）；#9 AI 紫/游离表面收编与 #10 SnackBar 裸色收敛转入第三批

| # | 改动 | 涉及文件 |
|---|------|---------|
| 6 | atoms 层 37 处 `AppDesignSystem` 静态引用改 `context.themeColors.*`；删除/归档死代码 `app_button.dart`、`form_controls.dart` | `lib/atoms/app_widgets.dart` 等 |
| 7 | SQL 快速高亮路径接 isDark 分支，颜色从 `SqlEditorColors(isDark)` 取 | `lib/organisms/editor/sql_highlighter.dart:296-355` |
| 8 | 6 处 emoji 渲染点切换到已有 `_materialIconMap`，用品牌色令牌着色 | `lib/models/database_models.dart` + 6 个渲染点 |
| 9 | AI 紫 `#8b5cf6`（184 处）正名为 `aiAccent` 令牌；AI 代码块 `#282c34`、error_boundary `#1a1a1a/#f75454/#3574f0` 收编令牌 | `lib/organisms/ai_panel/`、`lib/organisms/connection/error_boundary.dart` |
| 10 | SnackBar 裸色 `Colors.green/orange` 全部收敛到 `AppErrorHandler` helper | 206 处手写点分批迁移 |

### 第三批：架构（配色体系完工） ✅ 已完成（2026-07-24 基线分支 043-design-token-unification）

| # | 改动 | 说明 |
|---|------|------|
| 11 | accent 统一咽喉：`accentPrimary/accentHover/accentSubtle` 升级为基于 `colorScheme.primary` 的 ThemeColors getter，514 处静态引用逐步迁移 | 消灭双轨；顺带决定是否收敛 8 色自选为 3–4 个专业色 |
| 12 | 亮色令牌同源化：亮色四级背景/文字收编进 AppDesignSystem light 常量区，消除 app_theme/app_colors 双份硬编码 | 对标 GitHub primer 双映射 |
| 13 | SQL 高亮四色正交化：comment 降灰 `#808080`、built_in 并入 function 黄 `#DCDCAA`、keyword 改 Darcula 橙 `#CC7832`（同时消除与 AccentColorType.orange 撞车） | 选定 Darcula 流派 |
| 14 | 字体落地：Inter + JetBrains Mono 打入 `assets/fonts` 并注册 pubspec fonts 段；或改显式系统字体栈；网格 `'monospace'` 统一为编辑器同栈 | 二选一，不留中间态 |
| 15 | 圆角收敛为三级标尺（6/8/12），607 处硬编码按"容器 8、控件 6、卡片 12"codemod | 长期债 |

### 防回归约定

- 业务代码禁止 `Color(0x…)` 直接书写语义色 hex（可加自定义 lint）
- 新增颜色必须先加令牌再引用；语义色引用走 `AppErrorHandler` / ThemeColors
- 亮色模式下任何新 UI 必须过一遍渲染检查（atoms 层事故的根源）

---

## 6. 附录

### 6.1 核实过程说明

全部 43 条初步发现由独立核实 agent 逐条对抗验证：打开证据中的 file:line 核对代码、检查缓解因素（死代码、主题感知间接层、上游已修复），给出 confirmed / exaggerated / wrong 三级判定。5 条 exaggerated 发现正文保留，其核实备注说明了被夸大的部分（如"阴影令牌零引用"实为弃用别名有 3 处引用、行号圆点问题的一半证据是死代码路径）。

### 6.2 提取阶段四份事实摘要

**令牌层（tokens）**：以 AppDesignSystem 为唯一权威暗色令牌源（Zinc 灰阶 + Sky-500 主色 + 四语义色），结构清晰；但亮色令牌没有同源定义，散落在 lightTheme 局部常量与 ThemeColors getter 两处硬编码，亮暗严重不对称。最大隐患是 accent 体系双轨：accentPrimary(#0ea5e9) 与 ThemeProvider 的 8 个 AccentColorType（blue=#3574f0 等）完全不一致。另有 30+ 弃用别名三层转发、dark ColorScheme 缺 outline/divider、dbTDengine 与 schemaPurple/accentPurple 三色撞车等问题，整体属于"暗色主干健康、亮色与 accent 体系欠债"。

**组件层（components）**：配色整体一致性较高，数据网格、侧栏树、标签页、状态栏均通过 context.themeColors 走令牌；亮色另有一套暖白（#F5F3EF）覆盖。主要不一致点：SQL 编辑器快速高亮兜底与行内错误点硬编码暗色 hex 不随主题切换；AI 面板代码块背景（#282c34/#fafafa）与 AI 紫多处硬编码；数据网格数字列无右对齐。

**配色纪律（hardcoded）**：处于"主题化迁移半途"——ThemeColors 感知层已铺开 2402 处，但暗色常量直连仍有 944 处，lib/ 内残留 192 处 Color(0x… 硬编码（其中 query_editor_status_bar 与 sql_highlighter 的 error/warning hex 与令牌逐字节重复）；透明度 API 三代同堂（废弃 withOpacity 56 处、withOpacityValue 16 处、withValues 约 474 处）；emoji 图标部分迁移（materialIcon 启用 2 处）但数据库类型选择器与 AI 面板仍以文本 emoji 渲染；SnackBar 裸色与 9/10px 硬编码字号（42+160 处）进一步拉低一致性。

**基准（benchmark）**：见第 2 节。DataGrip Darcula/New UI、VS Code Dark+、GitHub Dark 为源码级查证；Darcula 语法四色经多源交叉确认；Navicat/TablePlus/DBeaver 未公开 hex 处已标注近似。

### 6.3 相关文档

- 工作流运行记录：`.workflows/`（findings 全文、journal）
- 项目设计系统：`lib/theme/design_system.dart`（令牌单一权威源目标）
