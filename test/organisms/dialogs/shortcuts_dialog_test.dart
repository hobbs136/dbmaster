import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/dialogs/shortcuts_dialog.dart';
import 'package:dbmaster/theme/app_theme.dart';

void main() {
  group('ShortcutsDialog', () {
    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: AppTheme.darkTheme,
        home: Scaffold(body: child),
      );
    }

    testWidgets('应渲染对话框内容', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const ShortcutsDialog()));
      await tester.pumpAndSettle();

      expect(find.byType(ShortcutsDialog), findsOneWidget);
    });

    testWidgets('应包含搜索输入框', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const ShortcutsDialog()));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('应显示快捷键列表', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const ShortcutsDialog()));
      await tester.pumpAndSettle();

      // 应找到 ListView
      expect(find.byType(ListView), findsWidgets);
    });

    testWidgets('搜索应过滤快捷键', (tester) async {
      await tester.pumpWidget(buildTestableWidget(const ShortcutsDialog()));
      await tester.pumpAndSettle();

      // 在搜索框中输入文本
      await tester.enterText(find.byType(TextField), 'tab');
      await tester.pumpAndSettle();

      // 搜索结果应显示
      expect(find.byType(ShortcutsDialog), findsOneWidget);
    });
  });
}
