import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// SQL 编辑器文本样式常量（re_editor 迁移后唯一保留的旧编辑器遗产）。
/// T001: 统一字体系统，使用专业编程字体栈。
class EditorTextStyle {
  // 字体栈委托 AppDesignSystem 集中声明（F-29）
  static const String fontFamily = AppDesignSystem.monoFontFamily;
  static const List<String> fontFamilyFallback =
      AppDesignSystem.monoFontFamilyFallback;
  static const double fontSize = 13.0;
  static const double lineHeight = 1.6;
  static const double lineNumberFontSize = 11.0;

  static TextStyle get baseStyle => const TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: fontSize,
    height: lineHeight,
  );

  static TextStyle forContext(BuildContext context) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: fontSize,
    height: lineHeight,
    color: context.themeColors.textPrimary,
  );

  static TextStyle lineNumberStyle(
    BuildContext context, {
    bool isCurrentLine = false,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: lineNumberFontSize,
    height: lineHeight,
    color: isCurrentLine
        ? context.themeColors.textSecondary
        : context.themeColors.textMuted,
    fontWeight: isCurrentLine ? FontWeight.w600 : FontWeight.normal,
  );
}
