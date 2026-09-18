import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'design_system.dart';
export 'design_system.dart'; // 暴露 AppDesignSystem 间距/颜色令牌给所有导入 app_colors 的文件
import '../models/database_models.dart';
import '../providers/theme_provider.dart';

/// 主题感知的颜色扩展，供所有 widgets 使用
/// 用法：context.themeColors.bgPrimary
extension ThemeColorsExt on BuildContext {
  ThemeColors get themeColors => ThemeColors(this);
}

/// 安全读取 SQL 冷主题偏好（plan §2.6）。
/// 无 ThemeProvider 时（如单测）默认 true（冷主题），避免抛 ProviderNotFound。
bool sqlCoolThemeOf(BuildContext context) {
  try {
    return context.read<ThemeProvider>().sqlCoolTheme;
  } catch (_) {
    return true;
  }
}

/// 兼容层 InheritedWidget（已被 ThemeColorsExt 替代，保留以防旧代码引用）
/// 新代码请使用 context.themeColors
class AppColorsProvider extends InheritedWidget {
  final ThemeColors colors;

  const AppColorsProvider({
    super.key,
    required this.colors,
    required super.child,
  });

  static ThemeColors of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<AppColorsProvider>();
    // 回退：直接从 Context 获取主题色（不依赖 AppColorsProvider InheritedWidget）
    return provider?.colors ?? ThemeColors(context);
  }

  @override
  bool updateShouldNotify(AppColorsProvider oldWidget) =>
      colors != oldWidget.colors;
}

class ThemeColors {
  final BuildContext _ctx;
  ThemeColors(this._ctx);

  bool get _isDark {
    try {
      final themeProvider = _ctx.read<ThemeProvider>();
      return themeProvider.isDarkMode;
    } catch (_) {
      return Theme.of(_ctx).brightness == Brightness.dark;
    }
  }

  // Background colors
  // 亮色分支统一引用 *Light 常量区（F-34）
  Color get bgPrimary => Theme.of(_ctx).scaffoldBackgroundColor;
  Color get bgSecondary =>
      _isDark ? AppDesignSystem.bgSecondary : AppDesignSystem.bgSecondaryLight;
  Color get bgTertiary =>
      _isDark ? AppDesignSystem.bgTertiary : AppDesignSystem.bgTertiaryLight;
  Color get bgQuaternary => _isDark
      ? AppDesignSystem.bgQuaternary
      : AppDesignSystem.bgQuaternaryLight;

  // Legacy aliases
  Color get bgHover => bgTertiary;
  Color get bgActive => bgTertiary;
  Color get bgAi => bgSecondary;
  Color get bgAiMessage => bgTertiary;
  Color get bgAiUser => bgSecondary;

  // Text colors
  // 亮色分支统一引用 *Light 常量区（Slate 冷中性，plan §2.2）
  Color get textPrimary => Theme.of(_ctx).colorScheme.onSurface;
  Color get textSecondary => _isDark
      ? AppDesignSystem.textSecondary
      : AppDesignSystem.textSecondaryLight;
  Color get textMuted =>
      _isDark ? AppDesignSystem.textTertiary : AppDesignSystem.textMutedLight;
  Color get textDisabled => _isDark
      ? AppDesignSystem.textDisabled
      : AppDesignSystem.textDisabledLight;

  // Border colors
  Color get borderColor => Theme.of(_ctx).colorScheme.outline;
  Color get borderLight => _isDark
      ? AppDesignSystem.borderLight
      : AppDesignSystem.borderLightColorLight;

  /// 次级边框（网格线/弱描边/分隔）——暗色 = borderDefault（白 10%）；
  /// 亮色 = borderLightColorLight @50%（0.5 档既有渲染保持不变）
  Color get borderSubtle => _isDark
      ? AppDesignSystem.borderDefault
      : AppDesignSystem.borderLightColorLight.withValues(alpha: 0.5);

  Color get dividerColor => Theme.of(_ctx).dividerColor;

  // 语义色改为按主题分发（F-11）——暗色用 AppDesignSystem 原值，
  // 亮色用深一档 *Light 变体保证对比度；新代码请用 success/warning/error/info。
  Color get success =>
      _isDark ? AppDesignSystem.success : AppDesignSystem.successLight;
  Color get warning =>
      _isDark ? AppDesignSystem.warning : AppDesignSystem.warningLight;
  Color get error =>
      _isDark ? AppDesignSystem.error : AppDesignSystem.errorLight;
  Color get info => _isDark ? AppDesignSystem.info : AppDesignSystem.infoLight;

  // accent 统一咽喉（R1，F-16/F-33）——主强调色改从 ColorScheme.primary
  // 读取（ThemeProvider._applyAccentColor 为唯一写入点），hover/subtle 由其派生；
  // 换肤后全部 themeColors.accentBlue 消费点自动同步。
  Color get accentBlue => Theme.of(_ctx).colorScheme.primary;
  Color get accentBlueHover {
    final hsl = HSLColor.fromColor(accentBlue);
    return hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0)).toColor();
  }

  Color get accentSubtle => accentBlue.withValues(alpha: 0.15);

  // Accent colors（别名，转发到主题感知语义色）
  Color get accentGreen => success;
  Color get accentOrange => warning;
  Color get accentRed => error;
  // accentPurple 收敛至品牌主色（plan §2.3/§8：冷专业方向移除独立紫色 accent，
  // AI 面板/思考卡等 ~150 处消费点自动跟随 primary 换肤）。
  // 保留 getter 名以避免大面积改名；语义上 accentPurple ≡ accentBlue。
  // 注意：schemaPurple（类型编码）不在此列，仍为紫色。
  Color get accentPurple => accentBlue;

  // 语义背景 container 变体（plan §2.4）——大面积语义背景使用，按主题分发。
  Color get successContainer => _isDark
      ? AppDesignSystem.successContainer
      : AppDesignSystem.successContainerLight;
  Color get warningContainer => _isDark
      ? AppDesignSystem.warningContainer
      : AppDesignSystem.warningContainerLight;
  Color get errorContainer => _isDark
      ? AppDesignSystem.errorContainer
      : AppDesignSystem.errorContainerLight;

  // 选中项背景 / 标签页 active 背景（plan §2.3 primaryContainer）
  Color get primaryContainer => _isDark
      ? AppDesignSystem.primaryContainerDark
      : AppDesignSystem.primaryContainer;

  // 数据库类型品牌色（c02_token_spec §3.2 定版）——亮色用官方值
  // （DatabaseType.brandColor 为单一真相源），暗色对不达标类型
  // （PostgreSQL/TDengine/SQLite/SQL Server/MariaDB，官方色对暗底 < 3:1）
  // 分发 *Dark 提亮变体。UI 消费一律走此处，勿直引 AppDesignSystem.dbXxx。
  Color brandColor(DatabaseType type) {
    if (!_isDark) return type.brandColor;
    switch (type) {
      case DatabaseType.postgresql:
        return AppDesignSystem.dbPostgresqlDark;
      case DatabaseType.tdengine:
        return AppDesignSystem.dbTDengineDark;
      case DatabaseType.sqlite:
        return AppDesignSystem.dbSqliteDark;
      case DatabaseType.sqlserver:
        return AppDesignSystem.dbSqlserverDark;
      case DatabaseType.mariadb:
        return AppDesignSystem.dbMariadbDark;
      default:
        return type.brandColor;
    }
  }

  // 新增 codeBlockBg 代码块表面（F-04）
  Color get codeBlockBg =>
      _isDark ? AppDesignSystem.codeBlockBg : AppDesignSystem.codeBlockBgLight;
  Color get accentYellow => const Color(0xFFeab308);
  Color get accentCyan => info;
  Color get accentPink => const Color(0xFFec4899);
}

/// T010: SQL 编辑器语法高亮配色
/// 支持亮/暗模式自动切换
class SqlEditorColors {
  final bool isDark;

  /// plan §2.6：冷主题高亮方案（与壳体协调，降低饱和度）。
  /// 默认 false = 平台配套方案（暗=terminal 色系 / 亮=Light+）；true = 冷主题。
  final bool cool;

  const SqlEditorColors({required this.isDark, this.cool = false});

  // 暗色主题（terminal 色系：关键字蓝/内建与函数青/字符串绿/注释灰/数字橙，
  // 四色正交）
  // keyword→#4099FF（品牌蓝）、built_in/function→#42C8C8（terminal-cyan）、
  // string→#46BF72（terminal-green）、number→#FF8A30（terminal-yellow）、
  // comment→#858585、variable→#80BEFF（bright-blue）
  static const _dark = {
    'keyword': Color(0xFF4099FF),
    'built_in': Color(0xFF42C8C8),
    'string': Color(0xFF46BF72),
    'number': Color(0xFFFF8A30),
    'comment': Color(0xFF858585),
    'function': Color(0xFF42C8C8),
    'operator': Color(0xFFD4D4D4),
    'variable': Color(0xFF80BEFF),
    'punctuation': Color(0xFFD4D4D4),
  };

  // 亮色主题（Light+ 流派配套）
  // comment #008000→#6A737D（灰）、built_in 并入 function、
  // number→#0451A5、operator/punctuation 纯黑→#2D2D2D（不比正文更重）
  static const _light = {
    'keyword': Color(0xFFAF5B1E),
    'built_in': Color(0xFF795E26),
    'string': Color(0xFFA31515),
    'number': Color(0xFF0451A5),
    'comment': Color(0xFF6A737D),
    'function': Color(0xFF795E26),
    'operator': Color(0xFF2D2D2D),
    'variable': Color(0xFF001080),
    'punctuation': Color(0xFF2D2D2D),
  };

  // plan §2.6：冷主题（与壳体协调的中性低饱和方案，亮暗共用；
  // 品牌蓝随深色改版同步为 #4099FF）
  static const _cool = {
    'keyword': Color(0xFF4099FF),
    'built_in': Color(0xFF0891B2),
    'string': Color(0xFF16A34A),
    'number': Color(0xFFD97706),
    'comment': Color(0xFF64748B),
    'function': Color(0xFF0891B2),
    'operator': Color(0xFF94A3B8),
    'variable': Color(0xFF4099FF),
    'punctuation': Color(0xFF94A3B8),
  };

  Map<String, Color> get colors => cool ? _cool : (isDark ? _dark : _light);

  // 供 flutter_highlight（AI 面板代码块）复用同一配色体系，
  // 替换 atom-one 第三方主题（F-23）
  Map<String, TextStyle> toHighlightThemeMap(Color background) {
    TextStyle s(Color c, {bool italic = false}) =>
        TextStyle(color: c, fontStyle: italic ? FontStyle.italic : null);
    return {
      'root': TextStyle(color: punctuation, backgroundColor: background),
      'keyword': s(keyword),
      'built_in': s(builtIn),
      'string': s(string),
      'number': s(number),
      'comment': s(comment, italic: true),
      'function': s(function),
      'title': s(function),
      'operator': s(operator),
      'variable': s(variable),
      'params': s(variable),
      'punctuation': s(punctuation),
      'type': s(keyword),
      'literal': s(number),
      'symbol': s(number),
      'name': s(variable),
      'attr': s(variable),
      'meta': s(comment),
    };
  }

  Color get keyword => colors['keyword']!;
  Color get builtIn => colors['built_in']!;
  Color get string => colors['string']!;
  Color get number => colors['number']!;
  Color get comment => colors['comment']!;
  Color get function => colors['function']!;
  Color get operator => colors['operator']!;
  Color get variable => colors['variable']!;
  Color get punctuation => colors['punctuation']!;
}
