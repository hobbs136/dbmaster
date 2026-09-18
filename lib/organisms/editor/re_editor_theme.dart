import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/sql.dart' as re_lang_sql;
import 'package:re_highlight/languages/json.dart' as re_lang_json;
import 'package:re_highlight/languages/javascript.dart' as re_lang_js;
import 'package:re_highlight/languages/lua.dart' as re_lang_lua;
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import 'editor_text_style.dart' show EditorTextStyle;

/// T17/T18：re_editor 主题映射。
///
/// 复用既有四色正交体系（SqlEditorColors：亮/暗 × 冷主题），把
/// [SqlHighlightTheme] 的 highlight 配色翻译为 re_editor 的
/// [CodeHighlightTheme]（键为 highlight 语义类名，与 highlight 包同源），
/// 基础观感（正文/光标/选区/背景）映射到 [CodeEditorStyle]。
class ReSqlEditorTheme {
  ReSqlEditorTheme._();

  static SqlEditorColors _editorColors(BuildContext context) {
    return SqlEditorColors(
      isDark: Theme.of(context).brightness == Brightness.dark,
      cool: sqlCoolThemeOf(context),
    );
  }

  /// 语法高亮主题。languages 只装当前语言（单条目 = 显式指定，
  /// 避免 re_editor 走 highlightAuto 误判 SQL/JS）。
  static CodeHighlightTheme highlightTheme(BuildContext context, String language) {
    final colors = _editorColors(context);
    return CodeHighlightTheme(
      languages: {language: _languageMode(language)},
      theme: _themeMap(colors),
    );
  }

  /// 高亮上限：超过即整篇纯文本（不跑 isolate 解析）。
  ///
  /// re_editor 默认 maxSize 4MB——MB 级 schema dump 的 isolate 解析要
  /// 15-20s，结果迟到（粘贴后长时间无色，随后突然上色），且大文档 span
  /// 应用与执行收尾渲染叠加时产生可感卡顿。旧编辑器 >20K 即不高亮，
  /// 此处放宽到 300K（isolate 解析 <2s，到达及时）；单行超 20K（压缩成
  /// 一行的脚本）同样放弃，避免 Skia 段落爆量。
  static const int _maxHighlightChars = 300 * 1024;
  static const int _maxHighlightLineChars = 20 * 1024;

  static CodeHighlightThemeMode _languageMode(String language) {
    CodeHighlightThemeMode mode;
    switch (language.toLowerCase()) {
      case 'json':
        mode = re_lang_json.langJson.themeMode;
      case 'javascript':
        mode = re_lang_js.langJavascript.themeMode;
      case 'lua':
        mode = re_lang_lua.langLua.themeMode;
      default:
        mode = re_lang_sql.langSql.themeMode;
    }
    return CodeHighlightThemeMode(
      mode: mode.mode,
      maxSize: _maxHighlightChars,
      maxLineLength: _maxHighlightLineChars,
    );
  }

  /// highlight 语义类名 → TextStyle。
  /// 键集合与 SqlEditorColors.toHighlightThemeMap 对齐（含 sql/js/lua
  /// 混合场景的 title/type/literal 等别名），未命中的类回退正文色。
  static Map<String, TextStyle> _themeMap(SqlEditorColors colors) {
    return {
      'keyword': TextStyle(color: colors.keyword),
      'built_in': TextStyle(color: colors.builtIn),
      'string': TextStyle(color: colors.string),
      'number': TextStyle(color: colors.number),
      'comment': TextStyle(color: colors.comment, fontStyle: FontStyle.italic),
      'function': TextStyle(color: colors.function),
      'title': TextStyle(color: colors.function),
      'operator': TextStyle(color: colors.operator),
      'variable': TextStyle(color: colors.variable),
      'params': TextStyle(color: colors.variable),
      'punctuation': TextStyle(color: colors.punctuation),
      'type': TextStyle(color: colors.keyword),
      'literal': TextStyle(color: colors.number),
      'symbol': TextStyle(color: colors.number),
      'name': TextStyle(color: colors.variable),
      'attr': TextStyle(color: colors.variable),
      'meta': TextStyle(color: colors.comment),
    };
  }

  /// 编辑器整体样式（字体/光标/选区/背景 + 语法主题）。
  static CodeEditorStyle style(BuildContext context, String language) {
    final tc = context.themeColors;
    return CodeEditorStyle(
      fontSize: EditorTextStyle.fontSize,
      fontFamily: EditorTextStyle.fontFamily,
      fontFamilyFallback: EditorTextStyle.fontFamilyFallback,
      fontHeight: EditorTextStyle.lineHeight,
      textColor: tc.textPrimary,
      hintTextColor: tc.textMuted,
      backgroundColor: tc.bgPrimary,
      selectionColor: tc.accentBlue.withValues(alpha: 0.25),
      cursorColor: tc.accentBlue,
      cursorWidth: 2,
      codeTheme: highlightTheme(context, language),
    );
  }
}
