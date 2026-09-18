import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

enum AppThemeMode { dark, light, system }

extension AppThemeModeExt on AppThemeMode {
  String displayName(AppLocalizations l10n) {
    switch (this) {
      case AppThemeMode.dark:
        return l10n.settingsDarkMode;
      case AppThemeMode.light:
        return l10n.settingsLightMode;
      case AppThemeMode.system:
        return l10n.settingsSystem;
    }
  }
}

// accent 自选收敛为 4 个专业色（用户决策 2026-07-23）
enum AccentColorType { blue, teal, purple, green }

extension AccentColorTypeExt on AccentColorType {
  /// 亮色变体（plan §2.3：亮底用稍深一档，保证对比度）
  Color get color {
    switch (this) {
      case AccentColorType.blue:
        return const Color(0xFF3574F0); // JetBrains 官方蓝，默认
      case AccentColorType.teal:
        return const Color(0xFF0891B2); // Cyan-600
      case AccentColorType.purple:
        return const Color(0xFF7C6BD9); // 用户自选紫（独立于品牌蓝）
      case AccentColorType.green:
        return const Color(0xFF3D9A50); // 低饱和
    }
  }

  /// 暗色变体（plan §2.3：暗底提亮一档，保证在深色 Slate 背景上的可见度）
  Color get colorDark {
    switch (this) {
      case AccentColorType.blue:
        return const Color(0xFF4099FF); // 品牌蓝暗色变体（暗底提亮）
      case AccentColorType.teal:
        return const Color(0xFF22D3EE);
      case AccentColorType.purple:
        return const Color(0xFF9B8AE3);
      case AccentColorType.green:
        return const Color(0xFF4ADE80);
    }
  }

  String get name {
    switch (this) {
      case AccentColorType.blue:
        return '蓝色';
      case AccentColorType.teal:
        return '青色';
      case AccentColorType.purple:
        return '紫色';
      case AccentColorType.green:
        return '绿色';
    }
  }

  IconData get icon {
    switch (this) {
      case AccentColorType.blue:
        return LucideIcons.circle;
      case AccentColorType.teal:
        return LucideIcons.circle;
      case AccentColorType.purple:
        return LucideIcons.circle;
      case AccentColorType.green:
        return LucideIcons.circle;
    }
  }

  String displayName(AppLocalizations l10n) {
    switch (this) {
      case AccentColorType.blue:
        return l10n.colorBlue;
      case AccentColorType.teal:
        return l10n.colorCyan;
      case AccentColorType.purple:
        return l10n.colorPurple;
      case AccentColorType.green:
        return l10n.colorGreen;
    }
  }
}

class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'app_theme_mode';
  static const String _accentColorKey = 'app_accent_color';
  static const String _customColorsKey = 'app_custom_colors';
  static const String _sqlCoolThemeKey = 'app_sql_cool_theme';
  static const MethodChannel _platformChannel = MethodChannel(
    'dbmaster/window',
  );

  AppThemeMode _themeMode = AppThemeMode.dark;
  AccentColorType _accentColor = AccentColorType.blue;
  Map<String, String>? _customColors;
  bool _sqlCoolTheme = true; // plan §2.6：SQL 冷主题高亮默认开启（false=经典 Darcula）

  ThemeProvider() {
    final originalCallback =
        WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged;
    WidgetsBinding.instance.platformDispatcher.onPlatformBrightnessChanged =
        () {
          originalCallback?.call();
          if (_themeMode == AppThemeMode.system) {
            syncTitleBarTheme();
            notifyListeners();
          }
        };
  }

  AppThemeMode get themeMode => _themeMode;
  AccentColorType get accentColor => _accentColor;
  Map<String, String>? get customColors => _customColors;
  bool get sqlCoolTheme => _sqlCoolTheme;

  bool get isDarkMode {
    if (_themeMode == AppThemeMode.system) {
      return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
          Brightness.dark;
    }
    return _themeMode == AppThemeMode.dark;
  }

  Color get accentColorValue => _accentColor.color;

  /// 亮色 accent 变体（plan §2.3：亮底稍深一档，main.dart 的 theme: 使用）
  Color get accentColorLight => _accentColor.color;

  /// 暗色 accent 变体（plan §2.3：暗底提亮一档，main.dart 的 darkTheme: 使用）
  Color get accentColorDark => _accentColor.colorDark;

  // 旧版 8 色持久化值（中文名）→ 4 色枚举的映射
  static AccentColorType _migrateAccentValue(String stored) {
    switch (stored) {
      case '蓝色':
        return AccentColorType.blue;
      case '紫色':
      case '粉色':
        return AccentColorType.purple;
      case '绿色':
        return AccentColorType.green;
      case '青色':
        return AccentColorType.teal;
      case '橙色':
      case '红色':
      case '黄色':
      default:
        return AccentColorType.blue;
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeValue = prefs.getString(_themeModeKey);
    if (themeValue != null) {
      _themeMode = AppThemeMode.values.firstWhere(
        (e) => e.name == themeValue,
        orElse: () => AppThemeMode.dark,
      );
    }

    final accentValue = prefs.getString(_accentColorKey);
    if (accentValue != null) {
      // 8→4 旧值迁移——pink→purple、cyan→teal、
      // yellow/orange/red→blue；迁移后回写，避免每次启动重复映射
      _accentColor = _migrateAccentValue(accentValue);
      if (_accentColor.name != accentValue) {
        await prefs.setString(_accentColorKey, _accentColor.name);
      }
    }

    final customColorsJson = prefs.getString(_customColorsKey);
    if (customColorsJson != null) {
      try {
        _customColors = Map<String, String>.from(jsonDecode(customColorsJson));
      } catch (_) {
        _customColors = null;
      }
    }

    // plan §2.6：SQL 冷主题偏好（默认 true）
    final sqlCool = prefs.getBool(_sqlCoolThemeKey);
    if (sqlCool != null) _sqlCoolTheme = sqlCool;

    notifyListeners();
    // Delay title bar sync to ensure platform channel is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      syncTitleBarTheme();
    });
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
    await syncTitleBarTheme();
    notifyListeners();
  }

  Future<void> syncTitleBarTheme() async {
    try {
      await _platformChannel.invokeMethod('setTitleBarTheme', {
        'isDarkMode': isDarkMode,
      });
    } catch (_) {
      // Platform channel may not be available on all platforms
    }
  }

  Future<void> setAccentColor(AccentColorType color) async {
    if (_accentColor == color) return;
    _accentColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentColorKey, color.name);
    notifyListeners();
  }

  /// plan §2.6：切换 SQL 高亮主题（true=冷主题，false=经典 Darcula）
  Future<void> setSqlCoolTheme(bool value) async {
    if (_sqlCoolTheme == value) return;
    _sqlCoolTheme = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_sqlCoolThemeKey, value);
    notifyListeners();
  }

  Future<void> setCustomColors(Map<String, String> colors) async {
    _customColors = colors;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customColorsKey, jsonEncode(colors));
    notifyListeners();
  }

  Future<void> clearCustomColors() async {
    _customColors = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customColorsKey);
    notifyListeners();
  }

  Future<void> toggle() async {
    await setThemeMode(isDarkMode ? AppThemeMode.light : AppThemeMode.dark);
  }

  ThemeData get currentTheme {
    final baseTheme = isDarkMode ? AppTheme.darkTheme : AppTheme.lightTheme;
    return _applyAccentColor(baseTheme, isDark: isDarkMode);
  }

  ThemeData _applyAccentColor(ThemeData base, {required bool isDark}) {
    // 按亮度选 accent 变体（plan §2.3：亮/暗底用不同明度）
    final accent = isDark ? accentColorDark : accentColorLight;
    return base.copyWith(
      primaryColor: accent,
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: accent.withValues(alpha: 0.8),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  ThemeData getPreviewTheme(AppThemeMode mode, AccentColorType accent) {
    final isDark =
        mode == AppThemeMode.dark ||
        (mode == AppThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    final baseTheme = isDark ? AppTheme.darkTheme : AppTheme.lightTheme;
    // 预览同样按亮度选变体（plan §2.3）
    final color = isDark ? accent.colorDark : accent.color;

    return baseTheme.copyWith(
      primaryColor: color,
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: color,
        secondary: color.withValues(alpha: 0.8),
      ),
    );
  }
}
