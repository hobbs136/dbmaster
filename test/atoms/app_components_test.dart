import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/atoms/app_card.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

void main() {
  group('AppCard', () {
    testWidgets('basic card has no border and uses bgSecondary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme,
          home: Scaffold(
            body: AppCard(type: CardType.basic, child: Text('Card')),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, AppDesignSystem.bgSecondary);
      expect(decoration.border, isNull);
    });

    testWidgets('interactive card has accent border when selected', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.darkTheme,
          home: Scaffold(
            body: AppCard(
              type: CardType.interactive,
              isSelected: true,
              child: Text('Card'),
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(
        decoration.border!.top.color,
        // darkTheme 的 primary 为暗色变体 accentPrimaryDark（plan §2.3 亮度感知 accent）
        AppDesignSystem.accentPrimaryDark.withOpacityValue(0.4),
      );
    });
  });

}
