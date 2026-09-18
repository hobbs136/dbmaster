import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/theme/app_colors.dart';

void main() {
  group('SqlEditorColors', () {
    test('暗色模式应返回正确的关键字颜色', () {
      const colors = SqlEditorColors(isDark: true);
      expect(colors.keyword, const Color(0xFF4099FF));
    });

    test('暗色模式应返回正确的字符串颜色', () {
      const colors = SqlEditorColors(isDark: true);
      expect(colors.string, const Color(0xFF46BF72));
    });

    test('暗色模式应返回正确的注释颜色', () {
      const colors = SqlEditorColors(isDark: true);
      expect(colors.comment, const Color(0xFF858585));
    });

    test('亮色模式应返回正确的关键字颜色', () {
      const colors = SqlEditorColors(isDark: false);
      expect(colors.keyword, const Color(0xFFAF5B1E));
    });

    test('亮色模式应返回正确的字符串颜色', () {
      const colors = SqlEditorColors(isDark: false);
      expect(colors.string, const Color(0xFFA31515));
    });

    test('亮色模式应返回正确的注释颜色', () {
      const colors = SqlEditorColors(isDark: false);
      expect(colors.comment, const Color(0xFF6A737D));
    });

    test('暗色和亮色的关键字颜色应不同', () {
      const dark = SqlEditorColors(isDark: true);
      const light = SqlEditorColors(isDark: false);
      expect(dark.keyword, isNot(equals(light.keyword)));
    });

    test('应提供所有语法元素的颜色', () {
      const colors = SqlEditorColors(isDark: true);
      expect(colors.keyword, isA<Color>());
      expect(colors.builtIn, isA<Color>());
      expect(colors.string, isA<Color>());
      expect(colors.number, isA<Color>());
      expect(colors.comment, isA<Color>());
      expect(colors.function, isA<Color>());
      expect(colors.operator, isA<Color>());
      expect(colors.variable, isA<Color>());
      expect(colors.punctuation, isA<Color>());
    });

    test('colors map 应包含所有键', () {
      const colors = SqlEditorColors(isDark: true);
      final map = colors.colors;
      expect(
        map.keys,
        containsAll([
          'keyword',
          'built_in',
          'string',
          'number',
          'comment',
          'function',
          'operator',
          'variable',
          'punctuation',
        ]),
      );
    });
  });

  // plan §2.6：冷主题高亮方案（cool=true，亮暗同值，与 Slate 壳体协调）
  group('SqlEditorColors 冷主题（cool: true）', () {
    test('关键字为冷主题蓝 #4099FF', () {
      const colors = SqlEditorColors(isDark: true, cool: true);
      expect(colors.keyword, const Color(0xFF4099FF));
    });

    test('字符串为冷主题绿 #16A34A', () {
      const colors = SqlEditorColors(isDark: true, cool: true);
      expect(colors.string, const Color(0xFF16A34A));
    });

    test('注释为 Slate 灰 #64748B', () {
      const colors = SqlEditorColors(isDark: true, cool: true);
      expect(colors.comment, const Color(0xFF64748B));
    });

    test('亮暗同值（冷主题单一调色板）', () {
      const dark = SqlEditorColors(isDark: true, cool: true);
      const light = SqlEditorColors(isDark: false, cool: true);
      expect(dark.keyword, equals(light.keyword));
      expect(dark.string, equals(light.string));
    });
  });
}
