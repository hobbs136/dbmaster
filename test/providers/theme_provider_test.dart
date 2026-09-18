import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeProvider', () {
    late ThemeProvider provider;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      provider = ThemeProvider();
    });

    group('初始状态', () {
      test('应默认使用暗色主题', () {
        expect(provider.isDarkMode, isTrue);
        expect(provider.themeMode, AppThemeMode.dark);
        expect(provider.accentColor, AccentColorType.blue);
      });

      test('默认强调色应为蓝色', () {
        expect(provider.accentColorValue, equals(const Color(0xFF3574f0)));
      });
    });

    group('主题模式切换', () {
      test('应切换到亮色主题', () async {
        await provider.setThemeMode(AppThemeMode.light);
        expect(provider.isDarkMode, isFalse);
        expect(provider.themeMode, AppThemeMode.light);
      });

      test('应切换到系统主题', () async {
        await provider.setThemeMode(AppThemeMode.system);
        expect(provider.themeMode, AppThemeMode.system);
        // isDarkMode 取决于系统亮度，在测试中通常是 light
        expect(provider.isDarkMode, isFalse);
      });

      test('重复设置相同模式不应触发 notify', () async {
        var notifyCount = 0;
        provider.addListener(() => notifyCount++);
        await provider.setThemeMode(AppThemeMode.dark); // 已经是 dark
        expect(notifyCount, 0);
      });

      test('toggle 应在暗/亮之间切换', () async {
        await provider.setThemeMode(AppThemeMode.dark);
        await provider.toggle();
        expect(provider.themeMode, AppThemeMode.light);
        await provider.toggle();
        expect(provider.themeMode, AppThemeMode.dark);
      });
    });

    group('强调色切换', () {
      test('应切换到紫色', () async {
        await provider.setAccentColor(AccentColorType.purple);
        expect(provider.accentColor, AccentColorType.purple);
        expect(provider.accentColorValue, equals(const Color(0xFF7C6BD9)));
      });

      test('应切换到全部 4 种强调色（043a 收敛后）', () async {
        for (final color in AccentColorType.values) {
          await provider.setAccentColor(color);
          expect(provider.accentColor, color);
        }
      });

      test('重复设置相同强调色不应触发 notify', () async {
        var notifyCount = 0;
        provider.addListener(() => notifyCount++);
        await provider.setAccentColor(AccentColorType.blue);
        expect(notifyCount, 0);
      });
    });

    group('持久化', () {
      test('主题模式应保存到 SharedPreferences', () async {
        await provider.setThemeMode(AppThemeMode.light);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('app_theme_mode'), equals('light'));
      });

      test('强调色应保存到 SharedPreferences', () async {
        await provider.setAccentColor(AccentColorType.green);
        final prefs = await SharedPreferences.getInstance();
        // AccentColorTypeExt.name returns localized Chinese names
        expect(prefs.getString('app_accent_color'), equals('绿色'));
      });

      test('load 应恢复保存的主题模式', () async {
        SharedPreferences.setMockInitialValues({
          'app_theme_mode': 'light',
          'app_accent_color': '红色',
        });
        await provider.load();
        expect(provider.themeMode, AppThemeMode.light);
        // 043a：旧值 红色 → 迁移为 blue
        expect(provider.accentColor, AccentColorType.blue);
      });

      test('load 应处理无效主题模式值', () async {
        SharedPreferences.setMockInitialValues({'app_theme_mode': 'invalid'});
        await provider.load();
        expect(provider.themeMode, AppThemeMode.dark); // fallback
      });

      test('load 应处理无效强调色值', () async {
        SharedPreferences.setMockInitialValues({'app_accent_color': 'invalid'});
        await provider.load();
        expect(provider.accentColor, AccentColorType.blue); // fallback
      });
    });

    group('自定义颜色', () {
      test('setCustomColors 应保存自定义颜色映射', () async {
        await provider.setCustomColors({'primary': '#FF0000'});
        expect(provider.customColors, equals({'primary': '#FF0000'}));
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('app_custom_colors'),
          equals('{"primary":"#FF0000"}'),
        );
      });

      test('clearCustomColors 应清除自定义颜色', () async {
        await provider.setCustomColors({'primary': '#FF0000'});
        await provider.clearCustomColors();
        expect(provider.customColors, isNull);
      });
    });

    group('currentTheme', () {
      test('暗色主题应返回 dark theme', () {
        provider = ThemeProvider();
        final theme = provider.currentTheme;
        expect(theme.brightness, Brightness.dark);
      });

      test('亮色主题应返回 light theme', () async {
        await provider.setThemeMode(AppThemeMode.light);
        final theme = provider.currentTheme;
        expect(theme.brightness, Brightness.light);
      });
    });

    group('getPreviewTheme', () {
      test('应返回指定模式和强调色的预览主题', () {
        final preview = provider.getPreviewTheme(
          AppThemeMode.light,
          AccentColorType.teal,
        );
        expect(preview.brightness, Brightness.light);
        expect(preview.primaryColor, equals(const Color(0xFF0891B2)));
      });
    });
  });

  group('accent 8→4 旧值迁移（043a）', () {
    Future<AccentColorType> loadWithStored(String stored) async {
      SharedPreferences.setMockInitialValues({'app_accent_color': stored});
      final p = ThemeProvider();
      await p.load();
      return p.accentColor;
    }

    test('粉色 → purple', () async {
      expect(await loadWithStored('粉色'), AccentColorType.purple);
    });

    test('青色 → teal', () async {
      expect(await loadWithStored('青色'), AccentColorType.teal);
    });

    test('黄色/橙色/红色 → blue', () async {
      expect(await loadWithStored('黄色'), AccentColorType.blue);
      expect(await loadWithStored('橙色'), AccentColorType.blue);
      expect(await loadWithStored('红色'), AccentColorType.blue);
    });

    test('合法值 蓝色/紫色/绿色/青色 保留', () async {
      expect(await loadWithStored('蓝色'), AccentColorType.blue);
      expect(await loadWithStored('紫色'), AccentColorType.purple);
      expect(await loadWithStored('绿色'), AccentColorType.green);
      expect(await loadWithStored('青色'), AccentColorType.teal);
    });

    test('迁移后回写持久化（不重复映射）', () async {
      SharedPreferences.setMockInitialValues({'app_accent_color': '粉色'});
      final p = ThemeProvider();
      await p.load();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_accent_color'), '紫色');
    });

    test('枚举恰好 4 个值且色值符合专业色板', () {
      expect(AccentColorType.values.length, 4);
      expect(AccentColorType.blue.color, const Color(0xFF3574F0));
      expect(AccentColorType.teal.color, const Color(0xFF0891B2));
      expect(AccentColorType.purple.color, const Color(0xFF7C6BD9));
      expect(AccentColorType.green.color, const Color(0xFF3D9A50));
    });
  });

}
