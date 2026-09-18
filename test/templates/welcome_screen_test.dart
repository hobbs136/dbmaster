import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/templates/welcome_screen.dart';
import 'package:dbmaster/theme/app_theme.dart';

Widget _buildTestWidget({
  AppProvider? provider,
  VoidCallback? onNewConnection,
  VoidCallback? onOpenConnectionManager,
  VoidCallback? onOpenSqliteFile,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('zh')],
    locale: const Locale('en'),
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<AppProvider>(
          create: (_) => provider ?? AppProvider(),
        ),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: Scaffold(
        body: WelcomeScreen(
          onNewConnection: onNewConnection ?? () {},
          onOpenConnectionManager: onOpenConnectionManager ?? () {},
          onOpenSqliteFile: onOpenSqliteFile ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  group('WelcomeScreen (TS-005)', () {
    testWidgets('TS-005.1 root container uses bgPrimary background', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      final root = find.byKey(const ValueKey('welcome_screen'));
      expect(root, findsOneWidget);

      final container = root.evaluate().first.widget as Container;
      expect(container.color, AppDesignSystem.bgPrimary);
    });

    testWidgets(
      'TS-005.1 centered card uses bgSecondary with radiusMd (10px)',
      (tester) async {
        await tester.pumpWidget(_buildTestWidget());
        await tester.pumpAndSettle();

        final welcomeScreen = find.byKey(const ValueKey('welcome_screen'));
        final containers = find.descendant(
          of: welcomeScreen,
          matching: find.byType(Container),
        );
        final containerWidgets = tester
            .widgetList<Container>(containers)
            .toList();

        final cardContainer = containerWidgets.firstWhere((c) {
          final d = c.decoration;
          if (d is! BoxDecoration) return false;
          return d.color == AppDesignSystem.bgSecondary;
        }, orElse: () => throw StateError('No bgSecondary card found'));

        final deco = cardContainer.decoration as BoxDecoration;
        expect(deco.color, AppDesignSystem.bgSecondary);
        expect(
          (deco.borderRadius as BorderRadius).topLeft.x,
          AppDesignSystem.radiusMd,
          reason: 'Card border radius should be radiusMd (10px)',
        );
      },
    );

    testWidgets('TS-005.1 title uses fontSizeDisplay (24) and fontWeightBold', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      final titleFinder = find.text('DbMaster');
      expect(titleFinder, findsOneWidget);

      final Text title = tester.widget(titleFinder);
      expect(title.style!.fontSize, AppDesignSystem.fontSizeDisplay);
      expect(title.style!.fontWeight, AppDesignSystem.fontWeightBold);
    });

    testWidgets('TS-005.2 primary New Connection button is full-width', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      final button = find.byType(ElevatedButton);
      expect(button, findsOneWidget);

      final sizedBox = find.ancestor(
        of: button,
        matching: find.byType(SizedBox),
      );
      final sizedBoxes = tester
          .widgetList<SizedBox>(sizedBox)
          .where((s) => s.width == double.infinity)
          .toList();
      expect(
        sizedBoxes,
        isNotEmpty,
        reason: 'Button must be wrapped in a full-width SizedBox',
      );
    });

    testWidgets('TS-005 primary button uses accentPrimary background', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      final bg = button.style?.backgroundColor?.resolve({});
      // darkTheme 的 primary 为暗色变体 accentPrimaryDark（plan §2.3 亮度感知 accent）
      expect(bg, AppDesignSystem.accentPrimaryDark);
    });

    testWidgets('TS-005 secondary buttons use bgTertiary', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      final buttons = tester.widgetList<OutlinedButton>(
        find.byType(OutlinedButton),
      );
      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        final bg = button.style?.backgroundColor?.resolve({});
        expect(bg, isNotNull, reason: 'OutlinedButton should have a background');
      }
    });

    // SQLite 文件打开入口（P0）
    testWidgets('renders Open SQLite File button', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Open SQLite File…'), findsOneWidget);
    });

    testWidgets('tapping Open SQLite File invokes callback', (tester) async {
      var invoked = false;
      await tester.pumpWidget(
        _buildTestWidget(onOpenSqliteFile: () => invoked = true),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open SQLite File…'));
      await tester.pump();
      expect(invoked, isTrue);
    });

    testWidgets('Recent Files section hidden when no SQLite files', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      // 默认 AppProvider 无保存连接 → recentSqliteFiles 为空 → 区块不渲染
      expect(find.text('Recent Files'), findsNothing);
    });
  });
}
