import 'dart:io' as io;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/theme/design_system.dart';

void main() {
  group('AppDesignSystem Colors', () {
    test('背景色应有正确的 ARGB 值（中性灰黑）', () {
      expect(AppDesignSystem.bgPrimary, const Color(0xFF161616));
      expect(AppDesignSystem.bgSecondary, const Color(0xFF202020));
      expect(AppDesignSystem.bgTertiary, const Color(0xFF2B2B2B));
      expect(AppDesignSystem.bgQuaternary, const Color(0xFF363636));
    });

    test('文本色应有正确的 ARGB 值（中性灰）', () {
      expect(AppDesignSystem.textPrimary, const Color(0xFFD4D4D4));
      expect(AppDesignSystem.textSecondary, const Color(0xFFB3B3B3));
      expect(AppDesignSystem.textTertiary, const Color(0xFF8F8F8F));
      expect(AppDesignSystem.textDisabled, const Color(0xFF7A7A7A));
      expect(AppDesignSystem.textInverted, const Color(0xFF161616));
    });

    test('边框色应有正确的 ARGB 值（白色低透明度 outline/outlineVariant）', () {
      expect(AppDesignSystem.borderDefault, const Color(0x1AFFFFFF));
      expect(AppDesignSystem.borderLight, const Color(0x26FFFFFF));
      expect(AppDesignSystem.divider, const Color(0x1AFFFFFF));
    });

    test('品牌色应有正确的 ARGB 值（靛蓝，亮暗双值）', () {
      expect(AppDesignSystem.accentPrimary, const Color(0xFF3574F0));
      expect(AppDesignSystem.accentPrimaryDark, const Color(0xFF4099FF));
      expect(AppDesignSystem.accentHover, const Color(0xFF69AFFF));
      expect(AppDesignSystem.primaryContainer, const Color(0xFFEEF4FF));
      expect(AppDesignSystem.primaryContainerDark, const Color(0xFF001D3D));
    });

    test('语义色应有正确的 ARGB 值（terminal 功能色）', () {
      expect(AppDesignSystem.success, const Color(0xFF46BF72));
      expect(AppDesignSystem.warning, const Color(0xFFFF8A30));
      expect(AppDesignSystem.error, const Color(0xFFFF5C5C));
      expect(AppDesignSystem.info, const Color(0xFF42C8C8));
    });

    test('亮色语义变体应有正确的 ARGB 值（plan §2.4）', () {
      expect(AppDesignSystem.successLight, const Color(0xFF16A34A));
      expect(AppDesignSystem.warningLight, const Color(0xFFD97706));
      expect(AppDesignSystem.errorLight, const Color(0xFFDC2626));
      expect(AppDesignSystem.infoLight, const Color(0xFF0891B2));
    });

    test('语义背景 container 变体应有正确的 ARGB 值（plan §2.4）', () {
      expect(AppDesignSystem.successContainer, const Color(0xFF14532D));
      expect(AppDesignSystem.successContainerLight, const Color(0xFFDCFCE7));
      expect(AppDesignSystem.warningContainer, const Color(0xFF78350F));
      expect(AppDesignSystem.warningContainerLight, const Color(0xFFFEF3C7));
      expect(AppDesignSystem.errorContainer, const Color(0xFF7F1D1D));
      expect(AppDesignSystem.errorContainerLight, const Color(0xFFFEE2E2));
    });

    test('亮色层级常量区应有正确的 ARGB 值（Slate 单源化）', () {
      expect(AppDesignSystem.bgPrimaryLight, const Color(0xFFF8FAFC));
      expect(AppDesignSystem.bgSecondaryLight, const Color(0xFFFFFFFF));
      expect(AppDesignSystem.bgTertiaryLight, const Color(0xFFF1F5F9));
      expect(AppDesignSystem.bgQuaternaryLight, const Color(0xFFE2E8F0));
      expect(AppDesignSystem.textPrimaryLight, const Color(0xFF0F172A));
      expect(AppDesignSystem.textSecondaryLight, const Color(0xFF475569));
      expect(AppDesignSystem.textMutedLight, const Color(0xFF64748B));
      expect(AppDesignSystem.textDisabledLight, const Color(0xFF94A3B8));
      expect(AppDesignSystem.borderLightColorLight, const Color(0xFFCBD5E1));
      expect(AppDesignSystem.dividerLight, const Color(0xFFCBD5E1));
      expect(AppDesignSystem.outlineVariantLight, const Color(0xFFE2E8F0));
    });

    test('代码块表面令牌应有正确的 ARGB 值（暗色）', () {
      expect(AppDesignSystem.codeBlockBg, const Color(0xFF161616));
      expect(AppDesignSystem.codeBlockBgLight, const Color(0xFFF1F5F9));
    });

    test('等宽字体主字体与回退栈（US5）', () {
      expect(AppDesignSystem.monoFontFamily, 'JetBrains Mono');
      expect(AppDesignSystem.monoFontFamilyFallback, isNotEmpty);
      expect(
        AppDesignSystem.monoFontFamilyFallback,
        containsAll(['Consolas', 'Monaco', 'Courier New', 'monospace']),
      );
    });

    test('暗色文字明度梯度应单调递减（primary > secondary > tertiary > disabled）', () {
      double lum(Color c) => c.computeLuminance();
      expect(
        lum(AppDesignSystem.textPrimary),
        greaterThan(lum(AppDesignSystem.textSecondary)),
      );
      expect(
        lum(AppDesignSystem.textSecondary),
        greaterThan(lum(AppDesignSystem.textTertiary)),
      );
      expect(
        lum(AppDesignSystem.textTertiary),
        greaterThan(lum(AppDesignSystem.textDisabled)),
      );
    });

    test('所有颜色不应相同', () {
      final colors = [
        AppDesignSystem.bgPrimary,
        AppDesignSystem.bgSecondary,
        AppDesignSystem.bgTertiary,
        AppDesignSystem.textPrimary,
        AppDesignSystem.textSecondary,
        AppDesignSystem.accentPrimary,
        AppDesignSystem.success,
        AppDesignSystem.error,
      ];
      expect(colors.toSet().length, colors.length);
    });
  });

  group('数据库类型色暗色变体（c02_token_spec §3 定版）', () {
    // WCAG 相对亮度与对比度（1.4.11 图形物件基准 3:1）；
    // c.r/g/b 为 0-1 浮点（新版 Color API，替代已废弃的 .red/.green/.blue）
    double luminance(Color c) {
      double lin(double ch) => ch <= 0.03928
          ? ch / 12.92
          : math.pow((ch + 0.055) / 1.055, 2.4).toDouble();
      return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }

    double contrast(Color a, Color b) {
      final l1 = luminance(a);
      final l2 = luminance(b);
      return (l1 > l2 ? (l1 + 0.05) / (l2 + 0.05) : (l2 + 0.05) / (l1 + 0.05));
    }

    test('四个 *Dark 变体应有定版值', () {
      expect(AppDesignSystem.dbPostgresqlDark, const Color(0xFF5382A8));
      expect(AppDesignSystem.dbTDengineDark, const Color(0xFF5C7CA3));
      expect(AppDesignSystem.dbSqliteDark, const Color(0xFF0F80CC));
      expect(AppDesignSystem.dbSqlserverDark, const Color(0xFFD13438));
    });

    test('官方基值对暗底不达标（< 3:1，变体存在理由，锁定基线）', () {
      expect(
        contrast(AppDesignSystem.dbSqlite, AppDesignSystem.bgSecondary),
        lessThan(3.0),
      );
      expect(
        contrast(AppDesignSystem.dbSqlserver, AppDesignSystem.bgSecondary),
        lessThan(3.0),
      );
      expect(
        contrast(AppDesignSystem.dbTDengine, AppDesignSystem.bgSecondary),
        lessThan(3.0),
      );
      expect(
        contrast(AppDesignSystem.dbPostgresql, AppDesignSystem.bgSecondary),
        lessThan(3.0),
      );
    });

    test('暗色变体对暗底达标（>= 3:1，对 bgSecondary）', () {
      expect(
        contrast(AppDesignSystem.dbSqliteDark, AppDesignSystem.bgSecondary),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrast(AppDesignSystem.dbSqlserverDark, AppDesignSystem.bgSecondary),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrast(AppDesignSystem.dbTDengineDark, AppDesignSystem.bgSecondary),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrast(AppDesignSystem.dbPostgresqlDark, AppDesignSystem.bgSecondary),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('其余类型官方色对暗底达标（无需变体）', () {
      for (final c in [
        AppDesignSystem.dbMysql,
        AppDesignSystem.dbMongodb,
        AppDesignSystem.dbRedis,
        AppDesignSystem.dbDoris,
        AppDesignSystem.dbClickhouse,
      ]) {
        expect(
          contrast(c, AppDesignSystem.bgSecondary),
          greaterThanOrEqualTo(3.0),
        );
      }
    });
  });

  group('AppDesignSystem Spacing', () {
    test('间距应有正确值', () {
      expect(AppDesignSystem.space1, 4.0);
      expect(AppDesignSystem.space2, 8.0);
      expect(AppDesignSystem.space3, 12.0);
      expect(AppDesignSystem.space4, 16.0);
      expect(AppDesignSystem.space6, 24.0);
      expect(AppDesignSystem.space8, 32.0);
      expect(AppDesignSystem.space10, 40.0);
    });

    test('间距应递增', () {
      expect(AppDesignSystem.space1 < AppDesignSystem.space2, isTrue);
      expect(AppDesignSystem.space2 < AppDesignSystem.space3, isTrue);
      expect(AppDesignSystem.space4 < AppDesignSystem.space6, isTrue);
      expect(AppDesignSystem.space6 < AppDesignSystem.space8, isTrue);
    });
  });

  group('AppDesignSystem Border Radius', () {
    test('圆角三级标尺应有正确值（US6）', () {
      expect(AppDesignSystem.radiusSm, 6.0);
      expect(AppDesignSystem.radiusMd, 8.0);
      expect(AppDesignSystem.radiusLg, 12.0);
    });

    test('lib/ 中无标尺外数值圆角残留（US6，特例除外）', () {
      // 特例：circular(1)=拖拽手柄精美元素、circular(20)=AI 浮层大面板
      // （042 已定稿）、circular(24)=accent 色圈正圆
      final result = io.Process.runSync('grep', [
        '-rnE',
        r'circular\([0-9]+\)',
        'lib/',
        '--include=*.dart',
      ]);
      final leftovers = result.stdout
          .toString()
          .split('\n')
          .where(
            (ln) =>
                ln.trim().isNotEmpty &&
                !ln.contains('circular(1)') &&
                !ln.contains('circular(20)') &&
                !ln.contains('circular(24)'),
          )
          .toList();
      expect(
        leftovers,
        isEmpty,
        reason:
            '数值圆角应统一为 radiusSm/Md/Lg 标尺（F-39）：${leftovers.take(5).join(' | ')}',
      );
    });
  });

  group('AppDesignSystem Typography', () {
    test('字号应有正确值', () {
      expect(AppDesignSystem.fontSizeXs, 11.0);
      expect(AppDesignSystem.fontSizeSm, 12.0);
      expect(AppDesignSystem.fontSizeMd, 13.0);
      expect(AppDesignSystem.fontSizeLg, 14.0);
      expect(AppDesignSystem.fontSizeXl, 15.0);
      expect(AppDesignSystem.fontSize2xl, 16.0);
      expect(AppDesignSystem.fontSize3xl, 18.0);
      expect(AppDesignSystem.fontSize4xl, 20.0);
      expect(AppDesignSystem.fontSizeDisplay, 24.0);
    });
  });
}
