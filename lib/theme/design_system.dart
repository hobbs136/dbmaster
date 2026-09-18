/// ============================================================================
/// 设计系统 - Design System
/// ============================================================================
///
/// 现代化极简设计风格
/// 深色：中性灰黑 + #4099FF 品牌蓝。
///
/// 配色重构（ui_color_improvement_plan.md §2，冷专业方向）：
///   - 中性色家族（亮暗同色相仅调明度），
///     消除原亮色暖白（#F5F3EF/#F0EDE8）与暗色 Zinc（#09090b）的冷暖冲突
///   - 品牌色靛蓝；语义色亮暗双值；移除独立紫色 accent（AI 收敛至 primary）
///   - 单一真相源：业务代码经 context.themeColors / ColorScheme 消费，勿直接引用此文件色值
///
/// 深色改版（2026-09）：暗色区对齐深色 IDE 风格——中性灰黑基调、
/// 亮度阶梯分层、白色低透明度边框、语义色换终端功能色；
/// 亮色区（*Light 常量与亮色变体）保持原值不动。
/// ============================================================================
library;

import 'package:flutter/material.dart';

/// ============================================================================
/// 颜色系统 - Color System
/// ============================================================================
class AppDesignSystem {
  // ==================== 背景色 - Background Colors（中性灰黑，暗色） ====================
  // 对应 ui_color_improvement_plan.md §2.2：background/surface/surfaceContainer/surfaceContainerHigh
  // 深色改版：纯 neutral 灰阶（无色相偏移），分层靠亮度阶梯
  // #161616 → #202020 → #2B2B2B → #363636。

  /// 主背景色（最外层）neutral #161616
  static const Color bgPrimary = Color(0xFF161616);

  /// 次级背景色（卡片、面板）neutral #202020
  static const Color bgSecondary = Color(0xFF202020);

  /// 三级背景色（输入框、悬停、次级容器）neutral #2B2B2B
  static const Color bgTertiary = Color(0xFF2B2B2B);

  /// 四级背景色（Hover 背景、分隔）neutral #363636
  static const Color bgQuaternary = Color(0xFF363636);

  // Legacy aliases for compatibility
  @Deprecated('使用 bgQuaternary')
  static const Color bgHover = bgTertiary;
  @Deprecated('使用 bgTertiary')
  static const Color bgActive = bgTertiary;
  @Deprecated('使用 bgSecondary')
  static const Color bgAi = bgSecondary;
  @Deprecated('使用 bgTertiary')
  static const Color bgAiMessage = bgTertiary;
  @Deprecated('使用 bgSecondary')
  static const Color bgAiUser = bgSecondary;

  // ==================== 文本色 - Text Colors（中性灰，暗色） ====================

  /// 主要文本 neutral-300（避免纯白在长时注视的数据网格中产生眩光）
  static const Color textPrimary = Color(0xFFD4D4D4);

  /// 次要文本 neutral-400
  static const Color textSecondary = Color(0xFFB3B3B3);

  /// 弱化文本（neutral-500）：bgPrimary/bgSecondary 上过 AA（5.59/5.03:1）；
  /// bgTertiary 上 4.38:1（大字 AA），长文请用 textSecondary
  static const Color textTertiary = Color(0xFF8F8F8F);

  /// 禁用文本（neutral-600，梯度最底档；WCAG 豁免禁用态对比度，无需过 AA）
  static const Color textDisabled = Color(0xFF7A7A7A);

  /// 反色文本（用于亮色/强调色底）
  static const Color textInverted = Color(0xFF161616);

  // ==================== 边框和分隔线 - Borders & Dividers（白色低透明度，暗色） ====================
  // 对应 plan §2.2 outline / outlineVariant：borderDefault=弱分割线、borderLight=可辨识边框。
  // 深色改版：白色低透明度叠层（叠不同底色自适应），非等效实色。

  /// 默认边框色（白 10%，淡，几乎不可见 → outlineVariant）
  static const Color borderDefault = Color(0x1AFFFFFF);

  /// 淡色边框（白 15%，可辨识 → outline）
  static const Color borderLight = Color(0x26FFFFFF);

  /// 结构性分隔线（白 10%，面板/区块边界，可辨识）
  static const Color divider = Color(0x1AFFFFFF);

  // ==================== 品牌色 - Brand Colors ====================
  // 对应 plan §2.3：仅保留一个品牌色家族（靛蓝），亮暗双值。

  // accent 统一咽喉（R1）：以下静态值仅作为 ColorScheme.primary 的默认
  // fallback 与测试基线，业务代码一律使用 context.themeColors.accentBlue*
  // （由 ThemeProvider 写入 ColorScheme，换肤全局生效）。

  /// 主色调（亮色默认品牌蓝，与 AccentColorType.blue 亮色变体一致）
  static const Color accentPrimary = Color(0xFF3574F0);

  /// 主色调暗色变体（暗底需更高明度；品牌蓝）
  static const Color accentPrimaryDark = Color(0xFF4099FF);

  /// 悬停色（静态 fallback = #4099FF 的 HSL lightness +0.08 派生；
  /// 运行时由 accentBlue 派生，默认主色的派生值即此）
  static const Color accentHover = Color(0xFF69AFFF);

  /// 柔和高亮背景
  static const Color accentSubtle = Color(0x264099FF); // 15% opacity（随主色重基）

  /// 选中项背景 / 标签页 active 背景（亮色）
  static const Color primaryContainer = Color(0xFFEEF4FF);

  /// 选中项背景 / 标签页 active 背景（暗色，accent 深蓝选中底）
  static const Color primaryContainerDark = Color(0xFF001D3D);

  // ==================== 语义色 - Semantic Colors（plan §2.4，亮暗双值 + container 变体） ====================

  /// 成功色（暗色，terminal-green #46BF72）
  static const Color success = Color(0xFF46BF72);

  /// 警告色（暗色，terminal-yellow #FF8A30）
  static const Color warning = Color(0xFFFF8A30);

  /// 错误色（暗色，terminal-red #FF5C5C）
  static const Color error = Color(0xFFFF5C5C);

  /// 信息色（暗色，terminal-cyan #42C8C8，暗底更通透）
  static const Color info = Color(0xFF42C8C8);

  // 亮色主题语义色变体（F-11）——上方四色为暗色优化值，
  // 直接铺在亮色底上对比度不足；亮色须用深一档变体。
  // 消费方应经 ThemeColors.success/warning/error/info 按主题分发，勿直接引用。
  /// 成功色（亮色主题）Green-600
  static const Color successLight = Color(0xFF16A34A);

  /// 警告色（亮色主题）Amber-600（plan §2.4）
  static const Color warningLight = Color(0xFFD97706);

  /// 错误色（亮色主题）Red-600
  static const Color errorLight = Color(0xFFDC2626);

  /// 信息色（亮色主题）Cyan-600
  static const Color infoLight = Color(0xFF0891B2);

  // 语义背景 container 变体（plan §2.4）——大面积语义背景使用，亮色降低饱和避免过艳。
  // 消费方经 ThemeColors.successContainer/warningContainer/errorContainer 按主题分发。
  /// 成功背景（暗色）
  static const Color successContainer = Color(0xFF14532D);

  /// 成功背景（亮色）
  static const Color successContainerLight = Color(0xFFDCFCE7);

  /// 警告背景（暗色）
  static const Color warningContainer = Color(0xFF78350F);

  /// 警告背景（亮色，约 50% 饱和）
  static const Color warningContainerLight = Color(0xFFFEF3C7);

  /// 错误背景（暗色）
  static const Color errorContainer = Color(0xFF7F1D1D);

  /// 错误背景（亮色，约 80% 饱和）
  static const Color errorContainerLight = Color(0xFFFEE2E2);

  // ==================== 亮色主题常量区（Slate 冷中性，单源化） ====================
  // 对应 plan §2.2：亮暗共享 Slate 色相，仅调明度。
  // lightTheme 局部常量与 ThemeColors 亮色分支统一引用此处（消除双份硬编码 F-34）。

  /// 亮色主背景（Slate-50 冷白）
  static const Color bgPrimaryLight = Color(0xFFF8FAFC);

  /// 亮色二级背景（纯白卡片）
  static const Color bgSecondaryLight = Color(0xFFFFFFFF);

  /// 亮色三级背景（输入框/悬停，Slate-100）
  static const Color bgTertiaryLight = Color(0xFFF1F5F9);

  /// 亮色四级背景（Hover/分隔，Slate-200）
  static const Color bgQuaternaryLight = Color(0xFFE2E8F0);

  /// 亮色主文字（Slate-900，非纯黑）
  static const Color textPrimaryLight = Color(0xFF0F172A);

  /// 亮色次要文字（Slate-600）
  static const Color textSecondaryLight = Color(0xFF475569);

  /// 亮色弱化文字（Slate-500，on 白底 ~4.6:1）
  static const Color textMutedLight = Color(0xFF64748B);

  /// 亮色禁用文字（Slate-400，梯度最底档）
  static const Color textDisabledLight = Color(0xFF94A3B8);

  /// 亮色边框（Slate-300 → outline）
  static const Color borderLightColorLight = Color(0xFFCBD5E1);

  /// 亮色结构性分隔线（Slate-300，可辨识）
  static const Color dividerLight = Color(0xFFCBD5E1);

  /// 亮色弱分割线（Slate-200 → outlineVariant）
  static const Color outlineVariantLight = Color(0xFFE2E8F0);

  // ==================== 代码块表面（R4：AI 代码块/嵌入代码视图） ====================
  // 新增代码块表面令牌（F-04），亮色经 codeBlockBgLight

  /// 代码块背景（暗色，主背景 #161616，与 bgPrimary 同底）
  static const Color codeBlockBg = Color(0xFF161616);

  /// 代码块背景（亮色，Slate-100）
  static const Color codeBlockBgLight = Color(0xFFF1F5F9);

  // ==================== 等宽字体栈（R7：编辑器与数据网格同源） ====================
  // 集中等宽字体声明（F-29），EditorTextStyle 与数据网格统一引用

  /// 等宽主字体（未随应用分发；不可用时按 fallback 回退）
  static const String monoFontFamily = 'JetBrains Mono';

  /// 等宽字体回退栈
  static const List<String> monoFontFamilyFallback = [
    'Fira Code',
    'Consolas',
    'Monaco',
    'Courier New',
    'monospace',
  ];

  // Legacy accent aliases for compatibility
  @Deprecated('使用 accentPrimary')
  static const Color accentBlue = accentPrimary;
  @Deprecated('使用 accentHover')
  static const Color accentBlueHover = accentHover;
  // accentPurple 收敛至主色（plan §2.3/§8：移除独立紫色 accent，AI 统一用 primary）。
  // 注意：schemaPurple（二进制/外键类型编码）是另一回事，保持紫色不变。
  @Deprecated('使用 accentPrimary（紫色 accent 已移除）')
  static const Color accentPurple = accentPrimary;
  @Deprecated('使用 warning')
  static const Color accentYellow = Color(0xFFeab308);
  @Deprecated('使用 error')
  static const Color accentPink = Color(0xFFec4899);

  // ==================== 数据库类型色 - Database Type Colors（plan §2.5 官方品牌色） ====================
  // 仅用于侧边栏图标和小面积标识，不用于主按钮/重点强调。
  // 基值 = 官方品牌色（亮色用，单一真相源，DatabaseType.brandColor 引用）；
  // *Dark = 暗底提亮变体（c02_token_spec §3 定版）——PostgreSQL/TDengine/SQLite/
  // SQL Server 四类型官方色在暗色 Slate 底对比度 < 3:1（WCAG 1.4.11），
  // 暗色经 ThemeColors.brandColor 分发变体，UI 勿直引基值。
  static const Color dbMysql = Color(0xFF00758F);
  static const Color dbPostgresql = Color(0xFF336791);
  static const Color dbMongodb = Color(0xFF47A248);
  static const Color dbRedis = Color(0xFFDC382D);
  static const Color dbDoris = Color(0xFF1E6FFF);
  static const Color dbTDengine = Color(0xFF3D5A80);
  static const Color dbSqlite = Color(0xFF003B57); // SQLite 官方深蓝
  static const Color dbSqlserver = Color(0xFFA91D22); // SQL Server 深红
  static const Color dbClickhouse = Color(0xFFE6A817); // CH 黄 - ClickHouse

  // T22-T25 四成员（MySQL 协议族薄适配）：基色取官方/近官方品牌色，
  // 除 MariaDB 外暗底对比度均 ≥ 3:1（无 *Dark 变体必要）。
  static const Color dbOceanbase = Color(0xFF3D7EFF); // OB 品牌蓝
  static const Color dbTidb = Color(0xFFE64545); // TiDB/PingCAP 红
  static const Color dbStarrocks = Color(0xFFF97316); // StarRocks 品牌橙
  static const Color dbMariadb = Color(0xFF003545); // MariaDB 官方深青

  /// PostgreSQL 暗色变体（官方 2.86 → 3.98，对 bgSecondary #202020）
  static const Color dbPostgresqlDark = Color(0xFF5382A8);

  /// TDengine 暗色变体（2.44 → 3.77，底色基准同上）
  static const Color dbTDengineDark = Color(0xFF5C7CA3);

  /// SQLite 暗色变体（1.45 → 3.86，SQLite 官方图标蓝，品牌保真）
  static const Color dbSqliteDark = Color(0xFF0F80CC);

  /// SQL Server 暗色变体（2.37 → 3.30）
  static const Color dbSqlserverDark = Color(0xFFD13438);

  /// MariaDB 暗色变体（官方深青 1.0x → 提亮青绿，暗底达标）
  static const Color dbMariadbDark = Color(0xFF3FC1B0);

  // ==================== Schema 类型色 - Schema Type-Coding Palette ====================
  // 列/索引/外键类型配色集中于此（原散落在 tree_utils 的硬编码 hex）。
  // 仅作集中化与命名，色值保持不变；后续暗色变体在此扩展即可。
  static const Color schemaBlue = Color(0xFF3B82F6); // 整数
  static const Color schemaIndigo = Color(0xFF6366F1); // 字符串
  static const Color schemaAmber = Color(0xFFF59E0B); // 日期/时间
  static const Color schemaGreen = Color(0xFF10B981); // 布尔/空间
  static const Color schemaPink = Color(0xFFEC4899); // 小数/浮点
  static const Color schemaPurple = Color(0xFF8B5CF6); // 二进制/外键
  static const Color schemaCyan = Color(0xFF06B6D4); // JSON
  static const Color schemaOrange = Color(0xFFF97316); // 枚举
  static const Color schemaYellow = Color(0xFFEAB308); // 时间戳
  static const Color schemaLime = Color(0xFF84CC16); // 几何
  static const Color schemaGray = Color(0xFF6B7280); // 默认
  static const Color schemaRed = Color(0xFFEF4444); // 主键

  // ==================== 间距系统 - Spacing System ====================
  // 4px 基准：所有间距在此集合中选择，禁止硬编码数值。
  static const double space0_5 = 2.0; // 极小（icon 与文字之间）
  static const double space1 = 4.0; // XS
  static const double space1_5 = 6.0; // XS-S（紧凑横排）
  static const double space2 = 8.0; // S
  static const double space2_5 = 10.0; // S-M
  static const double space3 = 12.0; // M
  static const double space4 = 16.0; // L
  static const double space5 = 20.0;
  static const double space6 = 24.0; // XL
  static const double space8 = 32.0; // XXL
  static const double space10 = 40.0; // XXXL

  // Legacy spacing aliases
  @Deprecated('使用 space1')
  static const double spacingXs = space1;
  @Deprecated('使用 space2')
  static const double spacingSm = space2;
  @Deprecated('使用 space3')
  static const double spacingMd = space3;
  @Deprecated('使用 space4')
  static const double spacingLg = space4;
  @Deprecated('使用 space6')
  static const double spacingXl = space6;
  @Deprecated('使用 space8')
  static const double spacing2xl = space8;
  @Deprecated('使用 space10')
  static const double spacing3xl = space10;

  // ==================== 圆角系统 - Border Radius System ====================
  // 三级标尺收敛（F-39）——控件 6 / 容器 8 / 对话框·大卡片 12；
  // radiusMd 由 10 改 8（预期内视觉变化，见 plan FR-011 例外清单）；
  // 弃用别名 radiusXs/radiusLg(16)/radiusXl 移除，8 处 radiusXs 引用已迁移
  static const double radiusSm = 6.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;

  // ==================== 字体系统 - Typography System ====================
  // 字号地板（契约 C4）：UI 文本最小字号 = 11（fontSizeXs），禁止 9/10px。
  // 例外：徽章/角标类 supplementary 文本允许 10px（如连接类型徽章），
  // 其余场景一律 >= fontSizeXs。
  static const double fontSizeXs = 11.0;
  static const double fontSizeSm = 12.0;
  static const double fontSizeMd = 13.0;
  static const double fontSizeLg = 14.0;
  static const double fontSizeXl = 15.0;
  static const double fontSize2xl = 16.0;
  static const double fontSize3xl = 18.0;
  static const double fontSize4xl = 20.0;
  static const double fontSizeDisplay = 24.0;

  /// 字体权重
  static const FontWeight fontWeightRegular = FontWeight.w400;
  static const FontWeight fontWeightMedium = FontWeight.w500;
  static const FontWeight fontWeightSemibold = FontWeight.w600;
  static const FontWeight fontWeightBold = FontWeight.w700;

  /// 行高
  static const double lineHeightTight = 1.25;
  static const double lineHeightNormal = 1.5;
  static const double lineHeightRelaxed = 1.75;

  // ==================== 阴影系统 - Shadow System ====================

  /// 浮层阴影（下拉菜单、Tooltip）
  static const List<BoxShadow> shadowFloat = [
    BoxShadow(
      color: Color(0x26000000),
      offset: Offset(0, 4),
      blurRadius: 12,
      spreadRadius: -2,
    ),
  ];

  /// 模态框阴影
  static const List<BoxShadow> shadowModal = [
    BoxShadow(
      color: Color(0x40000000),
      offset: Offset(0, 16),
      blurRadius: 40,
      spreadRadius: -6,
    ),
  ];

  // Legacy shadow aliases
  @Deprecated('使用 shadowFloat')
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x20000000), offset: Offset(0, 1), blurRadius: 2),
  ];
  @Deprecated('使用 shadowFloat')
  static const List<BoxShadow> shadowMd = shadowFloat;
  @Deprecated('使用 shadowModal')
  static const List<BoxShadow> shadowLg = shadowModal;
  @Deprecated('使用 shadowModal')
  static const List<BoxShadow> shadowXl = [
    BoxShadow(
      color: Color(0x50000000),
      offset: Offset(0, 20),
      blurRadius: 25,
      spreadRadius: -5,
    ),
  ];

  // ==================== 动画系统 - Animation System ====================
  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationNormal = Duration(milliseconds: 200);
  static const Duration durationSlow = Duration(milliseconds: 300);

  // Legacy animation aliases
  @Deprecated('使用 durationFast')
  static const Duration animationFast = durationFast;
  @Deprecated('使用 durationNormal')
  static const Duration animationNormal = durationNormal;
  @Deprecated('使用 durationSlow')
  static const Duration animationSlow = durationSlow;

  // ==================== 布局尺寸 - Layout Sizes ====================
  static const double sidebarWidth = 240.0;
  static const double sidebarMinWidth = 200.0;
  static const double sidebarCollapsedWidth = 44.0;
  static const double aiPanelWidth = 360.0;
  static const double aiPanelMinWidth = 320.0;
  static const double toolbarHeight = 36.0;
  static const double statusHeight = 24.0; // plan §3.5：26→24
  static const double tabBarHeight = 32.0;
  static const double tabBarDividerHeight =
      1.0; // plan §3.6：TabsBarWidget 底部分隔线
  static const double headerHeight = 48.0; // plan §3.1：44→48
  static const double minWindowWidth = 1024.0;
  static const double minWindowHeight = 768.0;

  /// 编辑器/工作区舒适最小宽度——面板降级阈值（plan §3.2）
  static const double minWorkspaceComfortWidth = 480.0;
  // ==================== 响应式断点 - Responsive Breakpoints（plan §3.3）====================
  /// 屏幕宽度分档断点——所有响应式判断的 single source of truth。
  /// `ResponsiveHelper` / `HomeScreen` / 布局组件统一引用，禁止散落硬编码。
  static const double breakpointCompact = 600.0;
  static const double breakpointMedium = 900.0;
  static const double breakpointExpanded = 1200.0;
  static const double breakpointLarge = 1600.0;

  /// 侧边栏自动折叠阈值 = breakpointMedium（900）。注意与 [minWindowWidth]
  /// （1024，OS 窗口最小尺寸）的关系：breakpointMedium 是 UI 折叠阈值，
  /// 用户可在 900~1024 之间看到折叠态侧边栏。
  static const double sidebarAutoCollapseBreakpoint = breakpointMedium;
  // AI 迷你 FAB 几何（plan §3.7：收敛硬编码 24/48/56）
  static const double aiFabSize = 56.0;
  static const double aiFabRightOffset = 24.0;
  static const double aiFabBottomOffset = 48.0;

  // ==================== 菜单尺寸 - Menu Sizes ====================
  // 体系 B（showMenu / PopupMenuButton）与自定义 ContextMenu 共用的紧凑菜单 token
  static const double menuItemHeight = 26.0;
  static const double menuFontSize = fontSizeSm;
  static const double menuIconSize = 14.0;
  static const double menuItemHPadding = space2_5;
  static const double menuDividerVPadding = space0_5;
  static const double menuVerticalPadding = space1;

  // ==================== Z-Index 层级 - Z-Index Layers ====================
  static const int zNormal = 0;
  static const int zFloating = 100;
  static const int zModal = 1000;
  static const int zTooltip = 2000;
  static const int zPopover = 2000;
  static const int zOverlay = 3000;

  // ==================== 过渡曲线 - Easing Curves ====================
  static const Curve curveDefault = Curves.easeInOut;
  static const Curve curveEnter = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;

  // ==================== 其他设计令牌 - Other Design Tokens ====================
  static const double inputMaxWidth = 400.0;
  static const double buttonMinWidth = 80.0;
  static const double iconSizeDefault = 18.0;
  static const double scrollbarWidth = 8.0;
  static const double tableMinRowHeight = 32.0;
  static const double treeNodeIndent = 16.0;
}

/// ============================================================================
/// 颜色扩展 - Color Extensions
/// ============================================================================
extension ColorExtension on Color {
  /// 获取浅色变体（悬停状态）
  Color get lighter {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness + 0.1).clamp(0.0, 1.0)).toColor();
  }

  /// 获取深色变体（按下状态）
  Color get darker {
    final hsl = HSLColor.fromColor(this);
    return hsl.withLightness((hsl.lightness - 0.1).clamp(0.0, 1.0)).toColor();
  }

  /// 获取透明度变体
  Color withOpacityValue(double opacity) {
    return withValues(alpha: opacity);
  }

  /// 判断是否为亮色
  bool get isLight => computeLuminance() > 0.5;
}

/// ============================================================================
/// 预定义文本样式 - Predefined Text Styles
/// ============================================================================
class AppTextStyles {
  /// 显示文本（页面标题）
  static const TextStyle display = TextStyle(
    fontSize: AppDesignSystem.fontSizeDisplay,
    fontWeight: AppDesignSystem.fontWeightBold,
    color: AppDesignSystem.textPrimary,
    height: AppDesignSystem.lineHeightTight,
  );

  /// 标题 1（章节标题）
  static const TextStyle h1 = TextStyle(
    fontSize: AppDesignSystem.fontSize4xl,
    fontWeight: AppDesignSystem.fontWeightBold,
    color: AppDesignSystem.textPrimary,
    height: AppDesignSystem.lineHeightTight,
  );

  /// 标题 2（子章节标题）
  static const TextStyle h2 = TextStyle(
    fontSize: AppDesignSystem.fontSize3xl,
    fontWeight: AppDesignSystem.fontWeightSemibold,
    color: AppDesignSystem.textPrimary,
    height: AppDesignSystem.lineHeightTight,
  );

  /// 标题 3（卡片标题）
  static const TextStyle h3 = TextStyle(
    fontSize: AppDesignSystem.fontSize2xl,
    fontWeight: AppDesignSystem.fontWeightSemibold,
    color: AppDesignSystem.textPrimary,
    height: AppDesignSystem.lineHeightTight,
  );

  /// 标题 4（小标题）
  static const TextStyle h4 = TextStyle(
    fontSize: AppDesignSystem.fontSizeXl,
    fontWeight: AppDesignSystem.fontWeightSemibold,
    color: AppDesignSystem.textPrimary,
    height: AppDesignSystem.lineHeightTight,
  );

  /// 正文（主要内容）
  static const TextStyle body = TextStyle(
    fontSize: AppDesignSystem.fontSizeMd,
    fontWeight: AppDesignSystem.fontWeightRegular,
    color: AppDesignSystem.textPrimary,
    height: AppDesignSystem.lineHeightNormal,
  );

  /// 正文大号
  static const TextStyle bodyLarge = TextStyle(
    fontSize: AppDesignSystem.fontSizeLg,
    fontWeight: AppDesignSystem.fontWeightRegular,
    color: AppDesignSystem.textPrimary,
    height: AppDesignSystem.lineHeightNormal,
  );

  /// 正文小号
  static const TextStyle bodySmall = TextStyle(
    fontSize: AppDesignSystem.fontSizeSm,
    fontWeight: AppDesignSystem.fontWeightRegular,
    color: AppDesignSystem.textSecondary,
    height: AppDesignSystem.lineHeightNormal,
  );

  /// 标签文本
  static const TextStyle label = TextStyle(
    fontSize: AppDesignSystem.fontSizeSm,
    fontWeight: AppDesignSystem.fontWeightMedium,
    color: AppDesignSystem.textSecondary,
    height: AppDesignSystem.lineHeightNormal,
  );

  /// 辅助文本
  static const TextStyle caption = TextStyle(
    fontSize: AppDesignSystem.fontSizeXs,
    fontWeight: AppDesignSystem.fontWeightRegular,
    color: AppDesignSystem.textTertiary,
    height: AppDesignSystem.lineHeightNormal,
  );

  /// 代码文本
  static const TextStyle code = TextStyle(
    fontSize: AppDesignSystem.fontSizeSm,
    fontWeight: AppDesignSystem.fontWeightRegular,
    color: AppDesignSystem.textPrimary,
    fontFamily: AppDesignSystem.monoFontFamily,

    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
    height: AppDesignSystem.lineHeightTight,
  );

  /// 按钮文本
  static const TextStyle button = TextStyle(
    fontSize: AppDesignSystem.fontSizeMd,
    fontWeight: AppDesignSystem.fontWeightMedium,
    height: AppDesignSystem.lineHeightNormal,
  );

  /// 链接文本
  static const TextStyle link = TextStyle(
    fontSize: AppDesignSystem.fontSizeMd,
    fontWeight: AppDesignSystem.fontWeightRegular,
    color: AppDesignSystem.accentPrimary,
    height: AppDesignSystem.lineHeightNormal,
  );
}
