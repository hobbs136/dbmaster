import 'package:flutter/material.dart';
import 'design_system.dart';
export 'design_system.dart';
export 'app_colors.dart';

// ============================================================================
// AppTheme - 全局主题常量
// ============================================================================
///
/// 注意：此文件保留向后兼容，新项目请直接使用 design_system.dart
/// 推荐用法：
///   - 颜色：AppDesignSystem.bgPrimary
///   - 间距：AppDesignSystem.space3
///   - 圆角：AppDesignSystem.radiusMd
// ============================================================================
class AppTheme {
  // ============================================================================
  // 颜色常量（已弃用，请使用 AppDesignSystem）
  // ============================================================================
  @Deprecated('使用 AppDesignSystem.bgPrimary')
  static const Color bgPrimary = AppDesignSystem.bgPrimary;

  @Deprecated('使用 AppDesignSystem.bgSecondary')
  static const Color bgSecondary = AppDesignSystem.bgSecondary;

  @Deprecated('使用 AppDesignSystem.bgTertiary')
  static const Color bgTertiary = AppDesignSystem.bgTertiary;

  @Deprecated('使用 AppDesignSystem.bgTertiary')
  static const Color bgHover = AppDesignSystem.bgTertiary;

  @Deprecated('使用 AppDesignSystem.bgTertiary')
  static const Color bgActive = AppDesignSystem.bgTertiary;

  @Deprecated('使用 AppDesignSystem.bgSecondary')
  static const Color bgAi = AppDesignSystem.bgSecondary;

  @Deprecated('使用 AppDesignSystem.bgTertiary')
  static const Color bgAiMessage = AppDesignSystem.bgTertiary;

  @Deprecated('使用 AppDesignSystem.bgSecondary')
  static const Color bgAiUser = AppDesignSystem.bgSecondary;

  // Aliases for compatibility
  @Deprecated('使用 AppDesignSystem.bgPrimary')
  static const Color darkSurface = AppDesignSystem.bgPrimary;

  @Deprecated('使用 AppDesignSystem.bgSecondary')
  static const Color darkCard = AppDesignSystem.bgSecondary;

  @Deprecated('使用 AppDesignSystem.accentPrimary')
  static const Color accentColor = AppDesignSystem.accentPrimary;

  @Deprecated('使用 AppDesignSystem.textPrimary')
  static const Color textPrimary = AppDesignSystem.textPrimary;

  @Deprecated('使用 AppDesignSystem.textSecondary')
  static const Color textSecondary = AppDesignSystem.textSecondary;

  @Deprecated('使用 AppDesignSystem.textTertiary')
  static const Color textMuted = AppDesignSystem.textTertiary;

  @Deprecated('使用 AppDesignSystem.info')
  static const Color textAccent = AppDesignSystem.info;

  @Deprecated('使用 AppDesignSystem.borderDefault')
  static const Color borderColor = AppDesignSystem.borderDefault;

  @Deprecated('使用 AppDesignSystem.borderLight')
  static const Color borderLight = AppDesignSystem.borderLight;

  @Deprecated('使用 AppDesignSystem.divider')
  static const Color dividerColor = AppDesignSystem.divider;

  @Deprecated('使用 AppDesignSystem.accentPrimary')
  static const Color accentBlue = AppDesignSystem.accentPrimary;

  @Deprecated('使用 AppDesignSystem.accentHover')
  static const Color accentBlueHover = AppDesignSystem.accentHover;

  @Deprecated('使用 AppDesignSystem.success')
  static const Color accentGreen = AppDesignSystem.success;

  @Deprecated('使用 AppDesignSystem.warning')
  static const Color accentOrange = AppDesignSystem.warning;

  @Deprecated('使用 AppDesignSystem.error')
  static const Color accentRed = AppDesignSystem.error;

  @Deprecated('使用 AppDesignSystem.accentPrimary（紫色 accent 已移除）')
  static const Color accentPurple = AppDesignSystem.accentPrimary;

  @Deprecated('使用 AppDesignSystem.warning')
  static const Color accentYellow = Color(0xFFeab308);

  @Deprecated('使用 AppDesignSystem.info')
  static const Color accentCyan = AppDesignSystem.info;

  @Deprecated('使用 AppDesignSystem.error')
  static const Color accentPink = Color(0xFFec4899);

  // ============================================================================
  // 间距系统（已弃用，请使用 AppDesignSystem）
  // ============================================================================
  @Deprecated('使用 AppDesignSystem.space1')
  static const double spacingXs = AppDesignSystem.space1;

  @Deprecated('使用 AppDesignSystem.space2')
  static const double spacingSm = AppDesignSystem.space2;

  @Deprecated('使用 AppDesignSystem.space3')
  static const double spacingMd = AppDesignSystem.space3;

  @Deprecated('使用 AppDesignSystem.space4')
  static const double spacingLg = AppDesignSystem.space4;

  @Deprecated('使用 AppDesignSystem.space6')
  static const double spacingXl = AppDesignSystem.space6;

  @Deprecated('使用 AppDesignSystem.space8')
  static const double spacing2xl = AppDesignSystem.space8;

  // 统一圆角（已弃用，请使用 AppDesignSystem）
  @Deprecated('使用 AppDesignSystem.radiusSm')
  static const double radiusSm = AppDesignSystem.radiusSm;

  @Deprecated('使用 AppDesignSystem.radiusMd')
  static const double radiusMd = AppDesignSystem.radiusMd;

  // ============================================================================
  // 布局尺寸（已弃用，请使用 AppDesignSystem）
  // ============================================================================
  @Deprecated('使用 AppDesignSystem.sidebarWidth')
  static const double sidebarWidth = AppDesignSystem.sidebarWidth;

  @Deprecated('使用 AppDesignSystem.aiPanelWidth')
  static const double aiPanelWidth = AppDesignSystem.aiPanelWidth;

  @Deprecated('使用 AppDesignSystem.toolbarHeight')
  static const double toolbarHeight = AppDesignSystem.toolbarHeight;

  @Deprecated('使用 AppDesignSystem.statusHeight')
  static const double statusHeight = AppDesignSystem.statusHeight;

  // ============================================================================
  // 统一卡片组件
  // ============================================================================

  /// 统一卡片样式
  /// 使用方式: Container(decoration: AppTheme.cardDecoration)
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: bgSecondary,
    borderRadius: BorderRadius.circular(radiusMd),
  );

  /// 统一卡片样式（带强调色边框）
  static BoxDecoration cardDecorationWithAccent(Color accentColor) =>
      BoxDecoration(
        color: bgSecondary,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1),
      );

  /// 统一内嵌卡片（略深）
  static BoxDecoration get cardDecorationNested => BoxDecoration(
    color: bgTertiary,
    borderRadius: BorderRadius.circular(radiusSm),
  );

  /// 统一输入框装饰
  static InputDecoration inputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: bgTertiary,
      hintText: hintText,
      hintStyle: const TextStyle(color: textMuted),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: accentBlue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusSm),
        borderSide: const BorderSide(color: accentRed),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2_5,
      ),
    );
  }

  // ============================================================================
  // 通用组件
  // ============================================================================

  /// 加载状态圆点（带脉冲动画）
  /// 推荐使用 common_widgets.dart 中的 StatusDot 组件
  static Widget statusDot({
    required bool isRunning,
    bool isLoading = false,
    double size = 6,
  }) {
    Color color;
    if (isLoading) {
      color = accentOrange;
    } else if (isRunning) {
      color = accentGreen;
    } else {
      color = accentRed;
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: isRunning
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }

  /// 空状态占位组件
  static Widget emptyState({
    required IconData icon,
    required String title,
    String? description,
    Widget? action,
    double iconSize = 48,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: textMuted),
            const SizedBox(height: spacingMd),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: textSecondary,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: spacingSm),
              Text(
                description,
                style: const TextStyle(fontSize: 13, color: textMuted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: spacingLg), action],
          ],
        ),
      ),
    );
  }

  /// 通用 Section 标题
  static Widget sectionTitle(
    String title, {
    String? actionText,
    VoidCallback? onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: spacingMd),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          if (actionText != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionText, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  /// 通用 Section 卡片
  static Widget sectionCard(Widget child, {EdgeInsets? padding}) {
    return Container(
      decoration: cardDecoration,
      padding: padding ?? const EdgeInsets.all(spacingLg),
      child: child,
    );
  }

  /// 通用 InfoRow（标签+值行）
  static Widget infoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: spacingXs),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: textMuted)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: 12, color: valueColor ?? textPrimary),
          ),
        ],
      ),
    );
  }

  /// 浅色主题 - 柔和暖白风格
  static ThemeData light(Color colorSeed) {
    return lightTheme.copyWith(
      primaryColor: colorSeed,
      colorScheme: lightTheme.colorScheme.copyWith(
        primary: colorSeed,
        secondary: colorSeed.withValues(alpha: 0.8),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorSeed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorSeed,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  static ThemeData dark(Color colorSeed) {
    return darkTheme.copyWith(
      primaryColor: colorSeed,
      colorScheme: darkTheme.colorScheme.copyWith(
        primary: colorSeed,
        secondary: colorSeed.withValues(alpha: 0.8),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorSeed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorSeed,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    // 亮色层级值统一引用 AppDesignSystem.*Light 常量区（F-34，
    // 消除 app_theme/app_colors 双份硬编码）
    const bgPrimary = AppDesignSystem.bgPrimaryLight; // 暖白背景（纸张色）
    const bgSecondary = AppDesignSystem.bgSecondaryLight; // 卡片背景（纯白）
    const bgTertiary = AppDesignSystem.bgTertiaryLight; // 输入框/悬停
    const textPrimary = AppDesignSystem.textPrimaryLight; // 主文字（深灰，非纯黑）
    const textSecondary = AppDesignSystem.textSecondaryLight; // 次要文字
    const borderColor = AppDesignSystem.borderLightColorLight; // 暖灰边框
    const dividerColor = AppDesignSystem.dividerLight; // 结构性分隔线（P0-1）

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bgPrimary,
      primaryColor: accentBlue,
      colorScheme: const ColorScheme.light(
        primary: accentBlue,
        // secondary 收敛至主色（plan §2.3：移除独立紫色 accent；运行时由换肤覆盖）
        secondary: accentBlue,
        surface: bgSecondary,
        // surface 层级（plan §2.2）：container = Slate-100、high/highest = Slate-200
        surfaceContainerLow: bgTertiary,
        surfaceContainer: bgTertiary,
        surfaceContainerHigh: AppDesignSystem.bgQuaternaryLight,
        surfaceContainerHighest: AppDesignSystem.bgQuaternaryLight,
        error: AppDesignSystem.errorLight,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: borderColor,
        outlineVariant: AppDesignSystem.outlineVariantLight,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSecondary,
        foregroundColor: textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: bgSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppDesignSystem.radiusMd)),
          // P1-4：亮白卡片在暖白底上对比不足，补 1px 暖灰描边
          side: BorderSide(color: borderColor),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: const BorderSide(color: accentBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm)),
        ),
      ),
      // P1-1：补建亮色 dialogTheme（原先缺失），与暗色对称并加 1px 描边
      dialogTheme: const DialogThemeData(
        backgroundColor: bgSecondary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: AppDesignSystem.fontSize2xl, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppDesignSystem.radiusLg)),
          side: BorderSide(color: borderColor),
        ),
      ),
      dividerTheme: const DividerThemeData(color: dividerColor, thickness: 1),
      // 紧凑菜单：浮层底色/圆角/12px 字号/垂直内边距（行高由 CompactPopupMenuItem 控制）
      popupMenuTheme: PopupMenuThemeData(
        color: bgTertiary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          // P1-1：浮层 1px 描边，与底色同处 theme 生效
          side: const BorderSide(color: borderColor),
        ),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: AppDesignSystem.menuFontSize,
            color: textPrimary,
          ),
        ),
        menuPadding: const EdgeInsets.symmetric(
          vertical: AppDesignSystem.menuVerticalPadding,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppDesignSystem.borderLightColorLight),
        radius: const Radius.circular(AppDesignSystem.radiusSm),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      primaryColor: AppDesignSystem.accentPrimaryDark,
      colorScheme: const ColorScheme.dark(
        // primary 用暗色变体（品牌蓝 #4099FF；暗底需更高明度，
        // 运行时由 ThemeProvider 写入对应亮/暗 accent 覆盖）
        primary: AppDesignSystem.accentPrimaryDark,
        // secondary 收敛至主色（plan §2.3：移除独立紫色 accent）
        secondary: AppDesignSystem.accentPrimaryDark,
        surface: bgSecondary,
        // surface 层级（plan §2.2）：container = Slate-800、high/highest = Slate-700 系
        surfaceContainerLow: bgTertiary,
        surfaceContainer: bgTertiary,
        surfaceContainerHigh: AppDesignSystem.bgQuaternary,
        surfaceContainerHighest: AppDesignSystem.bgQuaternary,
        outline: borderLight,
        outlineVariant: AppDesignSystem.borderDefault,
        onSurfaceVariant: textSecondary,
        error: accentRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgSecondary,
        foregroundColor: textPrimary,
        elevation: 0,
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textSecondary),
        titleLarge: TextStyle(color: textPrimary),
        titleMedium: TextStyle(color: textPrimary),
        titleSmall: TextStyle(color: textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: const BorderSide(
            color: AppDesignSystem.accentPrimaryDark,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppDesignSystem.accentPrimaryDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm)),
        ),
      ),
      // 暗色补 dialogTheme/dividerTheme（F-01），与亮色主题对称
      dialogTheme: const DialogThemeData(
        backgroundColor: bgSecondary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: AppDesignSystem.fontSize2xl, fontWeight: FontWeight.w600),
        // P1-1：浮层 1px 描边，与亮色对称
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppDesignSystem.radiusLg)),
          side: BorderSide(color: borderLight),
        ),
      ),
      // P1-4：暗色补建 cardTheme，与亮色对称（1px 描边），底色保持现状
      cardTheme: const CardThemeData(
        color: AppDesignSystem.bgSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppDesignSystem.radiusMd)),
          side: BorderSide(color: borderLight),
        ),
      ),
      dividerTheme: const DividerThemeData(color: dividerColor, thickness: 1),
      // 紧凑菜单：浮层底色/圆角/12px 字号/垂直内边距（行高由 CompactPopupMenuItem 控制）
      popupMenuTheme: PopupMenuThemeData(
        color: AppDesignSystem.bgTertiary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          // P1-1：浮层 1px 描边，与亮色对称
          side: const BorderSide(color: borderLight),
        ),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: AppDesignSystem.menuFontSize,
            color: AppDesignSystem.textPrimary,
          ),
        ),
        menuPadding: const EdgeInsets.symmetric(
          vertical: AppDesignSystem.menuVerticalPadding,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(borderLight),
        radius: const Radius.circular(AppDesignSystem.radiusSm),
      ),
    );
  }
}
