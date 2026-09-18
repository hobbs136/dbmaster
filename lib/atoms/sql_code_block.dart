import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';

import '../theme/app_colors.dart';

/// SQL 代码高亮块。
///
/// 基于 flutter_highlight，配色复用 SqlEditorColors（与 SQL 编辑器同源）。
class SqlCodeBlock extends StatelessWidget {
  final String code;
  final EdgeInsetsGeometry padding;

  const SqlCodeBlock({
    super.key,
    required this.code,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // atom-one 第三方主题 → SqlEditorColors 同源映射（F-23）
    return HighlightView(
      code,
      language: 'sql',
      theme: SqlEditorColors(
        isDark: isDark,
        cool: sqlCoolThemeOf(context),
      ).toHighlightThemeMap(context.themeColors.codeBlockBg),
      padding: padding,
      textStyle: const TextStyle(
        fontSize: 12,
        fontFamily: AppDesignSystem.monoFontFamily,

        fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        height: 1.5,
      ),
    );
  }
}
