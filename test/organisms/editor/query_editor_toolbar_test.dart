import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/editor/query_editor_toolbar.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('QueryEditorToolbar', () {
    Future<void> _setLargeSize(WidgetTester tester) async {
      tester.view.physicalSize = const Size(2400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Widget _buildToolbar({
      bool isExecuting = false,
      bool isReadOnly = false,
      bool workspaceMode = false,
    }) {
      final selectorPlaceholder = workspaceMode
          ? const SizedBox.shrink()
          : const Text('CTX');
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
            ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider(),
            ),
            ChangeNotifierProvider<LayoutPreferencesProvider>(
              create: (_) => LayoutPreferencesProvider(),
            ),
          ],
          child: Scaffold(
            body: QueryEditorToolbar(
              isExecuting: isExecuting,
              isSaving: false,
              splitMode: SplitMode.none,
              isReadOnly: isReadOnly,
              onExecute: () {},
              onStop: () {},
              onFormat: () {},
              onSave: () {},
              onSplitHorizontal: () {},
              onSplitVertical: () {},
              onCloseSplit: () {},
              connectionSelector: selectorPlaceholder,
              databaseSelector: selectorPlaceholder,
              limitSelector: const Text('LIMIT 3000'),
              timeoutSelector: const Text('30s'),
              commandPaletteButton: const Text('Ctrl+K'),
            ),
          ),
        ),
      );
    }

    testWidgets('does not show saved-queries bookmark button', (tester) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.bookmark), findsNothing);
      expect(find.byIcon(LucideIcons.bookmark), findsNothing);
    });

    testWidgets('still shows save button', (tester) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.save), findsOneWidget);
    });

    testWidgets(
      'TRB-C21-001 idle: 主按钮位 = labeled 运行（play 图标 + Execute 文案）',
      (tester) async {
        await _setLargeSize(tester);
        await tester.pumpWidget(_buildToolbar());
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.play), findsOneWidget);
        expect(find.text('Execute'), findsOneWidget);
        // 空闲态不渲染停止按钮
        expect(find.byIcon(LucideIcons.square), findsNothing);
      },
    );

    testWidgets(
      'TRB-C21-002 executing: 主按钮位切换为停止（square + Stop），运行按钮消失',
      (tester) async {
        await _setLargeSize(tester);
        await tester.pumpWidget(_buildToolbar(isExecuting: true));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.square), findsOneWidget);
        expect(find.text('Stop'), findsOneWidget);
        expect(find.byIcon(LucideIcons.play), findsNothing);
      },
    );

    testWidgets(
      'TRB-C21-003 readOnly: 显示 lock 只读状态 chip（非交互）',
      (tester) async {
        await _setLargeSize(tester);
        await tester.pumpWidget(_buildToolbar(isReadOnly: true));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.lock), findsOneWidget);
        expect(find.text('Read-only'), findsOneWidget);
      },
    );

    testWidgets(
      'TRB-C21-004 非 readOnly: 不显示只读 chip',
      (tester) async {
        await _setLargeSize(tester);
        await tester.pumpWidget(_buildToolbar(isReadOnly: false));
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.lock), findsNothing);
      },
    );

    testWidgets(
      'TRB-C21-005 上下文芯片集群在右端渲染（连接/库/LIMIT/超时/⌘K，'
      'C21 M3——消解 BreadcrumbBar 双显）',
      (tester) async {
        await _setLargeSize(tester);
        await tester.pumpWidget(_buildToolbar());
        await tester.pumpAndSettle();

        // 注入的芯片占位（连接/库 ×2 共用 'CTX' + LIMIT + 超时 + 面板入口）。
        expect(find.text('CTX'), findsNWidgets(2));
        expect(find.text('LIMIT 3000'), findsOneWidget);
        expect(find.text('30s'), findsOneWidget);
        expect(find.text('Ctrl+K'), findsOneWidget);
      },
    );

    testWidgets(
      'TRB-C21-006 工作区模式（无连接上下文）隐藏四芯片，保留命令面板入口',
      (tester) async {
        await _setLargeSize(tester);
        await tester.pumpWidget(_buildToolbar(workspaceMode: true));
        await tester.pumpAndSettle();

        expect(find.text('CTX'), findsNothing);
        expect(find.text('LIMIT 3000'), findsNothing);
        expect(find.text('30s'), findsNothing);
        // 命令面板入口不随连接上下文隐藏（全局动作）。
        expect(find.text('Ctrl+K'), findsOneWidget);
      },
    );
  });
}
