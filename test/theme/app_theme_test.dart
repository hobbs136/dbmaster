import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('暗色主题应返回 ThemeData', () {
      final theme = AppTheme.darkTheme;
      expect(theme, isA<ThemeData>());
    });

    test('亮色主题应返回 ThemeData', () {
      final theme = AppTheme.lightTheme;
      expect(theme, isA<ThemeData>());
    });

    test('暗色主题 brightness 应为 dark', () {
      final theme = AppTheme.darkTheme;
      expect(theme.brightness, Brightness.dark);
    });

    test('亮色主题 brightness 应为 light', () {
      final theme = AppTheme.lightTheme;
      expect(theme.brightness, Brightness.light);
    });

    test('暗色和亮色主题应不同', () {
      final dark = AppTheme.darkTheme;
      final light = AppTheme.lightTheme;
      expect(
        dark.scaffoldBackgroundColor,
        isNot(equals(light.scaffoldBackgroundColor)),
      );
    });

    test('暗色主题 scaffoldBackgroundColor 应为深色系', () {
      final theme = AppTheme.darkTheme;
      final color = theme.scaffoldBackgroundColor;
      // 深色背景的亮度应较低
      expect(color.computeLuminance() < 0.5, isTrue);
    });

    test('亮色主题 scaffoldBackgroundColor 应为浅色系', () {
      final theme = AppTheme.lightTheme;
      final color = theme.scaffoldBackgroundColor;
      // 浅色背景的亮度应较高
      expect(color.computeLuminance() > 0.5, isTrue);
    });

    test('暗色主题 colorScheme 应为暗色', () {
      final theme = AppTheme.darkTheme;
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('亮色主题 colorScheme 应为亮色', () {
      final theme = AppTheme.lightTheme;
      expect(theme.colorScheme.brightness, Brightness.light);
    });
  });
}
