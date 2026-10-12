// T16 J4 — 对象 tab 容器测试（内容分流 + 失效态 + 刷新）。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/connection/object_tabs/er_diagram_content.dart';
import 'package:dbmaster/organisms/connection/object_tabs/object_tab_view.dart';
import 'package:dbmaster/organisms/connection/object_tabs/table_properties_content.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart'
    show ObjectTabKind, ObjectTabRef;
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

Widget _buildObjectTabTest(AppProvider provider, ObjectTabView view) {
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
      child: Scaffold(body: view),
    ),
  );
}

void main() {
  group('ObjectTabView (T16 J4)', () {
    testWidgets('tableProperties ref → TablePropertiesContent 分流', (
      tester,
    ) async {
      final provider = AppProvider();
      await tester.pumpWidget(
        _buildObjectTabTest(
          provider,
          const ObjectTabView(
            tabId: 't-obj-1',
            ref: ObjectTabRef(
              kind: ObjectTabKind.tableProperties,
              connectionId: null,
              objectName: 'users',
            ),
          ),
        ),
      );
      // getTableProperties 等真实调用在无连接环境走失败路径（错误 snackbar +
      // noInformation 态），仍需渲染出内容件骨架。
      await tester.pump();
      expect(find.byType(TablePropertiesContent), findsOneWidget);
      expect(find.byType(ErDiagramContent), findsNothing);
    });

    testWidgets('erDiagram ref → ErDiagramContent 分流（无连接选择器兜底）', (
      tester,
    ) async {
      final provider = AppProvider();
      await tester.pumpWidget(
        _buildObjectTabTest(
          provider,
          const ObjectTabView(
            tabId: 't-obj-2',
            ref: ObjectTabRef(kind: ObjectTabKind.erDiagram),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ErDiagramContent), findsOneWidget);
      expect(find.byType(TablePropertiesContent), findsNothing);
    });

    testWidgets('失效态：锚定连接断开 → 「对象不可用」+ 关闭按钮关闭 tab', (
      tester,
    ) async {
      final provider = AppProvider();
      // 经 provider 开对象 tab（ghost 连接恒未连接 → 失效态）
      final tabId = provider.openObjectTab(
        const ObjectTabRef(
          kind: ObjectTabKind.tableProperties,
          connectionId: 'ghost-conn',
          objectName: 'users',
        ),
      );
      final ref = provider.tab.objectTabFor(tabId);
      expect(ref, isNotNull);

      await tester.pumpWidget(
        _buildObjectTabTest(
          provider,
          ObjectTabView(tabId: tabId, ref: ref!),
        ),
      );
      await tester.pumpAndSettle();

      // en: "Object unavailable"
      expect(find.text('Object unavailable'), findsOneWidget);
      expect(find.byType(TablePropertiesContent), findsNothing);

      // 关闭按钮：对象 tab 无未保存 → 直接关闭
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(provider.tabs, isEmpty);
      expect(provider.tab.objectTabFor(tabId), isNull);
    });

    testWidgets('刷新按钮存在（对象持有期间用户自决刷新）', (tester) async {
      final provider = AppProvider();
      await tester.pumpWidget(
        _buildObjectTabTest(
          provider,
          const ObjectTabView(
            tabId: 't-obj-3',
            ref: ObjectTabRef(
              kind: ObjectTabKind.erDiagram,
              connectionId: null,
            ),
          ),
        ),
      );
      await tester.pump();
      // 工具栏右侧刷新按钮（en tooltip: "Refresh"）。限定 16px：ER 图
      // header 的「重置布局」钮同为 refreshCw（18px），非本断言目标。
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Refresh',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              w.icon == LucideIcons.refreshCw &&
              w.size == 16,
        ),
        findsOneWidget,
      );
    });
  });
}
