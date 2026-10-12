// T16 J4 — 主标签栏只读对象 tab 渲染测试（角标 + 本地化标题 + 关闭无确认）。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/connection/tabs_bar_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart'
    show ObjectTabKind, ObjectTabRef;
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
  group('TabsBarWidget object tabs (T16 J4)', () {
    testWidgets('对象 tab：box 角标 + 本地化标题（表属性/ER 图）', (tester) async {
      final provider = AppProvider();
      await provider.tab.openQueryTab(
        connectionId: 'test-conn',
        databaseName: 'test-db',
      );
      provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'test-conn',
          databaseName: 'test-db',
          objectName: 'users',
        ),
      );
      provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.erDiagram,
          connectionId: 'test-conn',
          databaseName: 'test-db',
        ),
      );

      await tester.pumpWidget(_buildTabsBarTest(provider));
      await tester.pumpAndSettle();

      // 「对象」角标：两个对象 tab 各渲染一个 box 图标（普通 query tab 无）
      final badges = find.byIcon(LucideIcons.box);
      expect(badges.evaluate().length, 2, reason: '对象 tab 类型点位为 box 角标');
      // 本地化标题（en 模板："Table Properties — {table}" / "ER Diagram — {db}"）
      expect(find.text('Table Properties — users'), findsOneWidget);
      expect(find.text('ER Diagram — test-db'), findsOneWidget);
    });

    testWidgets('普通 query tab：无对象角标', (tester) async {
      final provider = AppProvider();
      await provider.tab.openQueryTab(
        connectionId: 'test-conn',
        databaseName: 'test-db',
      );

      await tester.pumpWidget(_buildTabsBarTest(provider));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.box), findsNothing);
    });

    testWidgets('对象 tab 关闭：直接关闭，无未保存确认弹窗', (tester) async {
      final provider = AppProvider();
      final tabId = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'test-conn',
          databaseName: 'test-db',
          objectName: 'users',
        ),
      );
      expect(provider.tabs.length, 1);

      await tester.pumpWidget(_buildTabsBarTest(provider));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      expect(provider.tabs, isEmpty, reason: '只读对象 tab 关闭无确认路径');
      expect(provider.tab.objectTabFor(tabId), isNull, reason: '关闭清理引用');
      expect(find.byType(AlertDialog), findsNothing, reason: '不弹任何确认 dialog');
    });
  });
}
