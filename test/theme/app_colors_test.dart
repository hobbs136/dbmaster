import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:dbmaster/models/database_models.dart';

void main() {
  group('ThemeColors', () {
    testWidgets('bgSecondary 在 light 模式下应为白色', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.bgSecondary, const Color(0xFFFFFFFF));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('textPrimary 应使用 colorScheme.onSurface', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(
                colors.textPrimary,
                Theme.of(context).colorScheme.onSurface,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('borderColor 应使用 colorScheme.outline', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.borderColor, Theme.of(context).colorScheme.outline);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('dividerColor 应使用 Theme dividerColor', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.dividerColor, Theme.of(context).dividerColor);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('borderSubtle：暗色为 borderDefault（白 10%），亮色为 50% 淡化', (
      tester,
    ) async {
      Future<void> pumpTheme(ThemeData theme) => tester.pumpWidget(
        // 换主题重泵必须带 key：无 key 时 MaterialApp 复用 State，
        // 主题不随重泵更新（flutter_test 陷阱，同 error_boundary_test）
        MaterialApp(
          key: ValueKey(theme.brightness),
          theme: theme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(
                colors.borderSubtle,
                theme.brightness == Brightness.dark
                    ? const Color(0x1AFFFFFF)
                    : AppDesignSystem.borderLightColorLight.withValues(
                        alpha: 0.5,
                      ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await pumpTheme(AppTheme.darkTheme);
      await pumpTheme(AppTheme.lightTheme);
    });

    testWidgets('context.themeColors 扩展应可用', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              // 直接使用扩展方法
              final colors = context.themeColors;
              expect(colors, isA<ThemeColors>());
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('AppColorsProvider.of 应返回 ThemeColors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final colors = AppColorsProvider.of(context);
              expect(colors, isA<ThemeColors>());
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    // 数据库类型品牌色主题分发（c02_token_spec §3.2 定版）
    group('brandColor 类型色主题分发', () {
      Future<ThemeColors> colorsWith(
        WidgetTester tester,
        ThemeData theme,
      ) async {
        late ThemeColors colors;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                colors = context.themeColors;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        return colors;
      }

      testWidgets('暗色：四个不达标类型分发 *Dark 变体', (tester) async {
        final colors = await colorsWith(tester, AppTheme.darkTheme);
        expect(
          colors.brandColor(DatabaseType.postgresql),
          AppDesignSystem.dbPostgresqlDark,
        );
        expect(
          colors.brandColor(DatabaseType.tdengine),
          AppDesignSystem.dbTDengineDark,
        );
        expect(
          colors.brandColor(DatabaseType.sqlite),
          AppDesignSystem.dbSqliteDark,
        );
        expect(
          colors.brandColor(DatabaseType.sqlserver),
          AppDesignSystem.dbSqlserverDark,
        );
      });

      testWidgets('暗色：其余类型用官方基值', (tester) async {
        final colors = await colorsWith(tester, AppTheme.darkTheme);
        expect(
          colors.brandColor(DatabaseType.mysql),
          DatabaseType.mysql.brandColor,
        );
        expect(
          colors.brandColor(DatabaseType.mongodb),
          DatabaseType.mongodb.brandColor,
        );
        expect(
          colors.brandColor(DatabaseType.redis),
          DatabaseType.redis.brandColor,
        );
        expect(
          colors.brandColor(DatabaseType.doris),
          DatabaseType.doris.brandColor,
        );
        expect(
          colors.brandColor(DatabaseType.clickhouse),
          DatabaseType.clickhouse.brandColor,
        );
      });

      testWidgets('亮色：全部类型用官方基值', (tester) async {
        final colors = await colorsWith(tester, AppTheme.lightTheme);
        for (final type in DatabaseType.values) {
          expect(colors.brandColor(type), type.brandColor, reason: type.name);
        }
      });
    });

    // accent 咽喉——themeColors.accentBlue 读取 ColorScheme.primary，
    // 换肤（改变 ColorScheme.primary）后消费点自动同步（F-16/F-33）
    group('accent 统一咽喉', () {
      const customAccent = Color(0xFF3D9A50);

      Future<ThemeColors> colorsWithAccent(WidgetTester tester) async {
        final theme = AppTheme.darkTheme.copyWith(
          colorScheme: AppTheme.darkTheme.colorScheme.copyWith(
            primary: customAccent,
          ),
        );
        late ThemeColors colors;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                colors = context.themeColors;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        return colors;
      }

      testWidgets('accentBlue 读取 ColorScheme.primary', (tester) async {
        final colors = await colorsWithAccent(tester);
        expect(colors.accentBlue, customAccent);
      });

      testWidgets('accentSubtle 由 primary 派生（15% alpha）', (tester) async {
        final colors = await colorsWithAccent(tester);
        expect(colors.accentSubtle, customAccent.withValues(alpha: 0.15));
      });

      testWidgets('accentBlueHover 由 primary 经 HSL 提亮派生', (tester) async {
        final colors = await colorsWithAccent(tester);
        final hsl = HSLColor.fromColor(customAccent);
        final expected = hsl
            .withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0))
            .toColor();
        expect(colors.accentBlueHover, expected);
        expect(colors.accentBlueHover, isNot(customAccent));
      });
    });

    testWidgets('bgHover 应是 bgTertiary 的别名', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.bgHover, colors.bgTertiary);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('bgActive 应是 bgTertiary 的别名', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.bgActive, colors.bgTertiary);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  // 语义色亮/暗双通道守卫（F-11，特性 046 T005）——
  // 四语义色必须经 ThemeColors 按主题分发，亮色取深一档 *Light 变体
  group('语义色亮/暗双通道（F-11）', () {
    testWidgets('暗色主题分发 AppDesignSystem 原值', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.success, AppDesignSystem.success);
              expect(colors.warning, AppDesignSystem.warning);
              expect(colors.error, AppDesignSystem.error);
              expect(colors.info, AppDesignSystem.info);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    // 语义色别名迁移零变化守卫（特性 046 T040，路径 B）——
    // 四个 accent 转发 getter 在暗色下必须与 AppDesignSystem 对应常量
    // 逐值相等，保证 205 处别名消费点迁移后暗色渲染零变化
    testWidgets('暗色下 accent 转发 getter 与 AppDesignSystem 常量逐值相等', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.accentRed, AppDesignSystem.error);
              expect(colors.accentGreen, AppDesignSystem.success);
              expect(colors.accentOrange, AppDesignSystem.warning);
              expect(colors.accentCyan, AppDesignSystem.info);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    testWidgets('亮色主题分发 *Light 变体', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.success, AppDesignSystem.successLight);
              expect(colors.warning, AppDesignSystem.warningLight);
              expect(colors.error, AppDesignSystem.errorLight);
              expect(colors.info, AppDesignSystem.infoLight);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('lightTheme ColorScheme.error 应为 errorLight', () {
      expect(AppTheme.lightTheme.colorScheme.error, AppDesignSystem.errorLight);
    });

    test('darkTheme ColorScheme.error 应为暗色 error 原值', () {
      expect(AppTheme.darkTheme.colorScheme.error, AppDesignSystem.error);
    });
  });

  // 亮色令牌单源化守卫（F-34）——亮色层级 hex 只允许
  // 出现在 design_system.dart 的 *Light 常量区，禁止双份硬编码回归
  group('亮色令牌单源化（US3）', () {
    test('app_theme/app_colors 中无亮色层级 hex 硬编码', () {
      const lightHexes = [
        '0xFFF5F3EF', // bgPrimaryLight
        '0xFFF0EDE8', // bgTertiaryLight
        '0xFFE8E5E0', // bgQuaternaryLight
        '0xFFE5E1DB', // borderLightColorLight
        '0xFF6B6B6B', // 旧 textSecondaryLight（已迁 stone 族）
        '0xFF9CA3AF', // 旧 textMutedLight（批次1 已修）
        '0xFF696f77', // 旧 textDisabledLight（批次1 已修）
      ];
      for (final path in [
        'lib/theme/app_theme.dart',
        'lib/theme/app_colors.dart',
      ]) {
        final src = io.File(path).readAsStringSync();
        for (final hex in lightHexes) {
          expect(
            src.contains(hex),
            isFalse,
            reason: '$path 不应再硬编码亮色层级值 $hex（应引用 *Light 常量区）',
          );
        }
      }
    });

    testWidgets('亮色分支取值与 *Light 常量区一致', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              final colors = ThemeColors(context);
              expect(colors.bgSecondary, AppDesignSystem.bgSecondaryLight);
              expect(colors.bgTertiary, AppDesignSystem.bgTertiaryLight);
              expect(colors.bgQuaternary, AppDesignSystem.bgQuaternaryLight);
              expect(colors.textSecondary, AppDesignSystem.textSecondaryLight);
              expect(colors.textMuted, AppDesignSystem.textMutedLight);
              expect(colors.textDisabled, AppDesignSystem.textDisabledLight);
              expect(colors.borderLight, AppDesignSystem.borderLightColorLight);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
