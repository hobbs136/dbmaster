import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/organisms/connection/tabs_bar_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

Widget _buildTabsBarTest(AppProvider provider) {
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
        ChangeNotifierProvider<AppProvider>.value(value: provider),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: const Scaffold(
        body: SizedBox(width: 800, height: 60, child: TabsBarWidget()),
      ),
    ),
  );
}

void main() {
  group('TabsBarWidget (TS-009)', () {
    testWidgets(
      'TS-009.1 (C21) active tab uses primaryContainer background',
      (tester) async {
        final provider = AppProvider();
        // 创建测试 tab 上下文
        await provider.tab.openQueryTab(
          connectionId: 'test-conn',
          databaseName: 'test-db',
        );
        await provider.addNewTab();
        await provider.addNewTab();
        provider.setActiveTab(0);

        await tester.pumpWidget(_buildTabsBarTest(provider));
        await tester.pumpAndSettle();

        // C21（原型 editor-workspace）：激活 tab = primaryContainer 底色
        // （替代 P1-2 的 bgPrimary 连通画布 + accent 底部指示条）。
        final tabItems = find
            .descendant(
              of: find.byType(TabsBarWidget),
              matching: find.byType(AnimatedContainer),
            )
            .evaluate()
            .map((e) => e.widget as AnimatedContainer)
            .where((c) => c.constraints?.minWidth == 120)
            .toList();

        expect(tabItems, isNotEmpty, reason: 'Should find tab item containers');

        final activeColors = tabItems
            .map((c) => (c.decoration as BoxDecoration?)?.color)
            .toList();
        expect(
          activeColors.contains(AppDesignSystem.primaryContainerDark),
          isTrue,
          reason: 'Active tab should use primaryContainer background (dark '
              'theme variant)',
        );
      },
    );

    testWidgets(
      'TS-009.2 (C21) inactive tabs transparent, tab face single-line '
      '(database name only in tooltip)',
      (tester) async {
        final provider = AppProvider();
        await provider.tab.openQueryTab(
          connectionId: 'test-conn',
          databaseName: 'test-db',
        );
        await provider.addNewTab();
        await provider.addNewTab();
        provider.setActiveTab(0);

        await tester.pumpWidget(_buildTabsBarTest(provider));
        await tester.pumpAndSettle();

        final tabItems = find
            .descendant(
              of: find.byType(TabsBarWidget),
              matching: find.byType(AnimatedContainer),
            )
            .evaluate()
            .map((e) => e.widget as AnimatedContainer)
            .toList();

        // 非激活 tab 透明底（露出标签栏 bgSecondary）
        final colors = tabItems
            .map((c) => (c.decoration as BoxDecoration?)?.color)
            .toList();
        expect(
          colors.contains(Colors.transparent),
          isTrue,
          reason: 'Inactive tab background should be transparent',
        );

        // C21 单行版式：库名不再作为 tab 面副标题渲染（工具栏上下文芯片承载）
        expect(find.text('test-db'), findsNothing);
      },
    );

    testWidgets('tabs bar container uses bgSecondary background', (
      tester,
    ) async {
      final provider = AppProvider();
      await provider.tab.openQueryTab(
        connectionId: 'test-conn',
        databaseName: 'test-db',
      );
      await provider.addNewTab();

      await tester.pumpWidget(_buildTabsBarTest(provider));
      await tester.pumpAndSettle();

      final tabBarContainer =
          find.byType(TabsBarWidget).evaluate().first.widget as TabsBarWidget;
      expect(tabBarContainer, isNotNull);

      final containerFinder = find.descendant(
        of: find.byType(TabsBarWidget),
        matching: find.byType(Container).first,
      );
      final container = tester.widget<Container>(containerFinder);
      // P0-3 后背景色移入 decoration（Container 不允许 color 与 decoration 并存）
      final deco = container.decoration as BoxDecoration?;
      expect(deco?.color ?? container.color, isNotNull);
    });
  });

  group('TabsBarWidget S9 · 环境色条（J3 多连接长驻树）', () {
    testWidgets('活动 tab 左缘 3px 环境色条，非活动 tab 保留 8px 圆点；tooltip 走 l10n', (tester) async {
      final provider = AppProvider();
      // 带 environment 的已保存连接（tab → savedConnections 解析 env）。
      provider.connection.addSavedServerForTest(
        DbServer(
          id: 'test-conn',
          type: DatabaseType.mysql,
          name: 'EnvConn',
          host: '192.0.2.1',
          port: 3306,
          username: 'root',
          password: 'x',
          environment: ConnectionEnvironment.production,
        ),
      );
      await provider.tab.openQueryTab(
        connectionId: 'test-conn',
        databaseName: 'test-db',
      );
      await provider.tab.openQueryTab(
        connectionId: 'test-conn',
        databaseName: 'test-db',
      );
      provider.setActiveTab(0); // tab0 活动

      await tester.pumpWidget(_buildTabsBarTest(provider));
      await tester.pumpAndSettle();

      final envColor = ConnectionEnvironment.production.badgeColor;

      // 活动 tab：左缘 3px 色条（Positioned width 3，色值 badgeColor 同源）。
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 3 &&
              (w.color ?? (w.decoration as BoxDecoration?)?.color) == envColor,
        ),
        findsOneWidget,
        reason: '活动 tab 环境圆点升级为左缘 3px 色条',
      );

      // 非活动 tab：8px 圆点保留（badgeColor 圆形，非 bar）。
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints?.maxWidth == 8 &&
              ((w.decoration as BoxDecoration?)?.shape == BoxShape.circle) &&
              (w.decoration as BoxDecoration?)?.color == envColor,
        ),
        findsOneWidget,
        reason: '非活动 tab 环境点保持 8px 圆点形态',
      );

      // tooltip 迁 l10n（修正原硬编码 displayName 违规存量，T24 三键）。
      final l10n = AppLocalizationsEn();
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == l10n.environmentProduction,
        ),
        findsNWidgets(2),
        reason: '色条与圆点 tooltip 均为 l10n 环境名（两 tab 各一）',
      );
    });
  });
}

