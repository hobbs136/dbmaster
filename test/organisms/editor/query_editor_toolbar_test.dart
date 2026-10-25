import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/editor/query_editor_toolbar.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 工具栏 AI Dock 开关稳定 Key（测试与自动化定位用；与实现侧 const 同名）。
Key get _kAiDockToggle => const Key('editorToolbarAiDockToggle');

void main() {
  group('QueryEditorToolbar', () {
    AppProvider? app;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null,
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null,
          );
      // 不手动 dispose：provider 包在树拆卸时已 dispose（双重 dispose 会
      // 触发 ExecutionCenterProvider after-dispose 断言）。
      app = null;
    });

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
            ChangeNotifierProvider<AppProvider>(
              create: (_) {
                app = AppProvider();
                return app!;
              },
            ),
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

    testWidgets('TRB-C21-001 idle: 主按钮位 = labeled 运行（play 图标 + Execute 文案）', (
      tester,
    ) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.play), findsOneWidget);
      expect(find.text('Execute'), findsOneWidget);
      // 空闲态不渲染停止按钮
      expect(find.byIcon(LucideIcons.square), findsNothing);
    });

    testWidgets('TRB-C21-002 executing: 主按钮位切换为停止（square + Stop），运行按钮消失', (
      tester,
    ) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar(isExecuting: true));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.square), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);
      expect(find.byIcon(LucideIcons.play), findsNothing);
    });

    testWidgets('TRB-C21-003 readOnly: 显示 lock 只读状态 chip（非交互）', (tester) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar(isReadOnly: true));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.lock), findsOneWidget);
      expect(find.text('Read-only'), findsOneWidget);
    });

    testWidgets('TRB-C21-004 非 readOnly: 不显示只读 chip', (tester) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar(isReadOnly: false));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.lock), findsNothing);
    });

    testWidgets('TRB-C21-005 上下文芯片集群在右端渲染（连接/库/LIMIT/超时/⌘K，'
        'C21 M3——消解 BreadcrumbBar 双显）', (tester) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();

      // 注入的芯片占位（连接/库 ×2 共用 'CTX' + LIMIT + 超时 + 面板入口）。
      expect(find.text('CTX'), findsNWidgets(2));
      expect(find.text('LIMIT 3000'), findsOneWidget);
      expect(find.text('30s'), findsOneWidget);
      expect(find.text('Ctrl+K'), findsOneWidget);
    });

    testWidgets('TRB-C21-006 工作区模式（无连接上下文）隐藏四芯片，保留命令面板入口', (tester) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar(workspaceMode: true));
      await tester.pumpAndSettle();

      expect(find.text('CTX'), findsNothing);
      expect(find.text('LIMIT 3000'), findsNothing);
      expect(find.text('30s'), findsNothing);
      // 命令面板入口不随连接上下文隐藏（全局动作）。
      expect(find.text('Ctrl+K'), findsOneWidget);
    });

    // ════════════════════════════════════════════════════════════════════════
    // v0.3.5 批1 T2 · UI35-129~133：主工作区工具栏 AI Dock 开关
    // ════════════════════════════════════════════════════════════════════════

    testWidgets('UI35-129 AI 开关存在：24px 见方，位于 ⌘K 入口左侧 4px', (tester) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();

      final toggleRect = tester.getRect(find.byKey(_kAiDockToggle));
      expect(toggleRect.width, 24, reason: 'AI 开关 24px 见方');
      expect(toggleRect.height, 24);

      final paletteRect = tester.getRect(find.text('Ctrl+K'));
      expect(
        toggleRect.right + 4,
        closeTo(paletteRect.left, 0.5),
        reason: 'AI 开关在命令面板入口左侧，间距 4px',
      );
    });

    testWidgets('UI35-130 tap AI 开关 = provider.toggleAiPanel()（关闭 → 打开）', (
      tester,
    ) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();

      expect(app!.aiPanelOpen, isFalse, reason: '初始关闭');
      await tester.tap(find.byKey(_kAiDockToggle));
      await tester.pumpAndSettle();
      expect(app!.aiPanelOpen, isTrue, reason: 'tap 开合经典 dock（toggleAiPanel）');
    });

    testWidgets('UI35-131 点亮条件：aiPanelOpen && !aiPanelFullscreen → 有强调描边态', (
      tester,
    ) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();

      Container containerOf() => tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(_kAiDockToggle),
              matching: find.byType(Container),
            )
            .first,
      );

      expect(
        containerOf().decoration,
        isA<BoxDecoration>().having((d) => d.border, 'border', isNull),
        reason: '关闭态无强调底/描边',
      );
      expect(app!.aiPanelOpen, isFalse);

      await tester.tap(find.byKey(_kAiDockToggle));
      await tester.pumpAndSettle();

      expect(app!.aiPanelOpen, isTrue);
      expect(app!.aiPanelFullscreen, isFalse);
      expect(
        containerOf().decoration,
        isA<BoxDecoration>().having((d) => d.border, 'border', isNotNull),
        reason: '开态（非全屏）呈现 accent 底 + accent 描边（颜色不断言，静态自查）',
      );
    });

    testWidgets('UI35-132 工作区模式（isWorkspaceMode）下 AI 开关恒显', (tester) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar(workspaceMode: true));
      await tester.pumpAndSettle();

      expect(
        find.byKey(_kAiDockToggle),
        findsOneWidget,
        reason: '四芯片隐藏但 AI 开关保留',
      );
      expect(find.text('Ctrl+K'), findsOneWidget, reason: '⌘K 零改动');
    });

    testWidgets('UI35-133 AI 开关 tooltip 含快捷键文案（aiDockToggleTooltip），无新增快捷键绑定', (
      tester,
    ) async {
      await _setLargeSize(tester);
      await tester.pumpWidget(_buildToolbar());
      await tester.pumpAndSettle();

      // Tooltip message 断言（不触发长按）。
      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(_kAiDockToggle),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Toggle AI Assistant (Ctrl+Shift+A)');
    });
  });
}
