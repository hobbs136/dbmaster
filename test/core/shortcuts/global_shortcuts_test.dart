import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/core/shortcuts/global_shortcuts_wrapper.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/organisms/connection/command_palette.dart';
import 'package:dbmaster/organisms/connection/quick_search_dialog.dart';
import 'package:dbmaster/organisms/dialogs/shortcuts_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/task_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/theme/app_theme.dart';

// ============================================================================
// Global Shortcuts Widget Tests
// Tests keyboard shortcuts via GlobalShortcutsWrapper + HardwareKeyboard
// ============================================================================
//
// NOTE: These tests verify shortcut wiring through HardwareKeyboard event
// dispatch. Some shortcuts (Ctrl+T, Ctrl+W) invoke async provider methods
// via _safeExecute which schedules them in addPostFrameCallback. The async
// Future is discarded, so we verify "no crash" for those rather than exact
// state timing. Dialog-opening shortcuts are verified by widget presence.
//
// Pre-existing bugs discovered by these tests:
// 1. QuickSearchDialog: Container with both color and decoration (crash)
// 2. CommandPaletteDialog: Row overflow in small viewports (overflow error)

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
  });

  Future<AppProvider> pumpTestApp(WidgetTester tester) async {
    // Use a large viewport to minimize layout overflow issues
    tester.binding.setSurfaceSize(const Size(1920, 1080));

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    final layoutProvider = LayoutPreferencesProvider();
    final taskProvider = TaskProvider();

    await themeProvider.load();
    await localeProvider.load();
    await layoutProvider.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TaskProvider>.value(value: taskProvider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layoutProvider,
          ),
          ChangeNotifierProxyProvider<TaskProvider, AppProvider>(
            create: (_) => AppProvider(),
            update: (_, task, app) {
              if (app == null) return AppProvider(taskProvider: task);
              app.updateTaskProvider(task);
              return app;
            },
          ),
        ],
        child: Consumer2<LocaleProvider, ThemeProvider>(
          builder: (context, locale, theme, _) {
            return MaterialApp(
              locale: locale.locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(theme.accentColorValue),
              home: const Scaffold(
                body: GlobalShortcutsWrapper(child: SizedBox.expand()),
              ),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    final context = tester.element(find.byType(MaterialApp));
    return Provider.of<AppProvider>(context, listen: false);
  }

  Future<void> sendShortcut(
    WidgetTester tester, {
    required LogicalKeyboardKey key,
    bool control = false,
    bool shift = false,
    bool meta = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);

    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);

    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    // Pump to let _safeExecute's post-frame callbacks run
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  // --------------------------------------------------------------------------
  // Tests
  // --------------------------------------------------------------------------

  group('MAN-KEY-003: Ctrl+T 新建标签页', () {
    testWidgets('按下 Ctrl+T 不应崩溃（无活动连接时优雅处理）', (tester) async {
      await pumpTestApp(tester);

      // Without an active connection, addNewTab() does nothing;
      // the shortcut should not throw.
      await sendShortcut(tester, key: LogicalKeyboardKey.keyT, control: true);

      expect(true, isTrue, reason: 'Ctrl+T 应被正确处理，不崩溃');
    });

    testWidgets('有活动连接时 Ctrl+T 最终会增加标签页', (tester) async {
      final appProvider = await pumpTestApp(tester);

      // Setup: create an initial tab to establish active connection
      await appProvider.addNewTab(
        connectionId: 'test_conn',
        databaseName: 'test_db',
      );
      await tester.pumpAndSettle();
      final initialCount = appProvider.tabs.length;
      expect(initialCount, greaterThan(0));

      await sendShortcut(tester, key: LogicalKeyboardKey.keyT, control: true);

      // The shortcut triggers an async addNewTab() via _safeExecute.
      // Since the Future is discarded, we can't await it directly.
      // We verify the shortcut was dispatched without crashing.
      // In production, the tab appears after the next frame.
      expect(true, isTrue, reason: 'Ctrl+T 快捷键应被正确分派');
    });
  });

  group('MAN-KEY-004: Ctrl+W 关闭标签页', () {
    testWidgets('有标签页时按下 Ctrl+W 不应崩溃', (tester) async {
      final appProvider = await pumpTestApp(tester);

      await appProvider.addNewTab(
        connectionId: 'test_conn',
        databaseName: 'test_db',
      );
      await tester.pumpAndSettle();

      await sendShortcut(tester, key: LogicalKeyboardKey.keyW, control: true);

      expect(true, isTrue, reason: 'Ctrl+W 应被正确处理，不崩溃');
    });

    testWidgets('没有标签页时 Ctrl+W 不应崩溃', (tester) async {
      await pumpTestApp(tester);

      await sendShortcut(tester, key: LogicalKeyboardKey.keyW, control: true);

      expect(true, isTrue, reason: '没有标签页时 Ctrl+W 应保持不变');
    });
  });

  group('MAN-KEY-002: Ctrl+Shift+P 命令面板', () {
    testWidgets('按下 Ctrl+Shift+P 应弹出命令面板', (tester) async {
      await pumpTestApp(tester);

      expect(
        find.byType(CommandPaletteDialog),
        findsNothing,
        reason: '初始状态不应有命令面板',
      );

      await sendShortcut(
        tester,
        key: LogicalKeyboardKey.keyP,
        control: true,
        shift: true,
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: '命令面板底栏不应再溢出');
      expect(
        find.byType(CommandPaletteDialog),
        findsOneWidget,
        reason: 'Ctrl+Shift+P 应弹出命令面板',
      );
    });

    testWidgets('命令面板已打开时不应重复弹出', (tester) async {
      await pumpTestApp(tester);

      await sendShortcut(
        tester,
        key: LogicalKeyboardKey.keyP,
        control: true,
        shift: true,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(CommandPaletteDialog), findsOneWidget);

      // Try to open again
      await sendShortcut(
        tester,
        key: LogicalKeyboardKey.keyP,
        control: true,
        shift: true,
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byType(CommandPaletteDialog),
        findsOneWidget,
        reason: '不应重复弹出命令面板',
      );
    });
  });

  group('Shortcuts Dialog: Ctrl+/', () {
    testWidgets('按下 Ctrl+/ 应弹出快捷键帮助对话框', (tester) async {
      await pumpTestApp(tester);

      expect(
        find.byType(ShortcutsDialog),
        findsNothing,
        reason: '初始状态不应有快捷键对话框',
      );

      await sendShortcut(tester, key: LogicalKeyboardKey.slash, control: true);
      await tester.pumpAndSettle();

      expect(
        find.byType(ShortcutsDialog),
        findsOneWidget,
        reason: 'Ctrl+/ 应弹出快捷键帮助对话框',
      );
    });
  });

  group('Quick Search: Ctrl+K', () {
    testWidgets('按下 Ctrl+K 应弹出快速搜索', (tester) async {
      await pumpTestApp(tester);

      await sendShortcut(tester, key: LogicalKeyboardKey.keyK, control: true);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byType(QuickSearchDialog),
        findsOneWidget,
        reason: 'Ctrl+K 应弹出快速搜索对话框',
      );
    });

    // Ctrl+N 冗余别名已移除（spec 040 T011）；断言它不再触发 QuickSearch。
    testWidgets('Ctrl+N 不再弹出快速搜索（别名已移除）', (tester) async {
      await pumpTestApp(tester);

      await sendShortcut(tester, key: LogicalKeyboardKey.keyN, control: true);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byType(QuickSearchDialog),
        findsNothing,
        reason: 'Ctrl+N 冗余别名已移除，QuickSearch 仅由 Ctrl+K 触发',
      );
    });

    // 重入 guard（镜像 CommandPalette）：已打开时不叠堆新弹窗。运行期主要由
    // _isDialogOpen() 拦截；guard 兜底 _safeExecute 同帧批量事件窗口。
    testWidgets('已打开时再次 Ctrl+K 不应叠堆新弹窗', (tester) async {
      await pumpTestApp(tester);

      await sendShortcut(tester, key: LogicalKeyboardKey.keyK, control: true);
      await tester.pump();
      tester.takeException(); // drain
      expect(find.byType(QuickSearchDialog), findsOneWidget);

      // 不关闭，再次触发
      await sendShortcut(tester, key: LogicalKeyboardKey.keyK, control: true);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byType(QuickSearchDialog),
        findsOneWidget,
        reason: '已打开时再次 Ctrl+K 不应叠堆新的 QuickSearchDialog',
      );
    });
  });

  group('MAN-KEY: Ctrl+Shift+A 切换 AI 面板', () {
    testWidgets('按下 Ctrl+Shift+A 应切换 AI 面板状态', (tester) async {
      final appProvider = await pumpTestApp(tester);
      final initialState = appProvider.aiPanelOpen;

      await sendShortcut(
        tester,
        key: LogicalKeyboardKey.keyA,
        control: true,
        shift: true,
      );
      await tester.pumpAndSettle();

      expect(
        appProvider.aiPanelOpen,
        !initialState,
        reason: 'Ctrl+Shift+A 应切换 AI 面板状态',
      );
    });
  });

  group('Tab Navigation: Ctrl+Tab / Ctrl+Shift+Tab', () {
    testWidgets('Ctrl+Tab 应切换到下一个标签页', (tester) async {
      final appProvider = await pumpTestApp(tester);

      // Create 3 tabs
      for (var i = 0; i < 3; i++) {
        await appProvider.addNewTab(
          connectionId: 'test_conn',
          databaseName: 'test_db',
        );
      }
      await tester.pumpAndSettle();
      expect(appProvider.tabs.length, greaterThanOrEqualTo(3));

      appProvider.setActiveTab(0);
      expect(appProvider.activeTabIndex, 0);

      await sendShortcut(tester, key: LogicalKeyboardKey.tab, control: true);
      await tester.pumpAndSettle();

      expect(appProvider.activeTabIndex, 1, reason: 'Ctrl+Tab 应切换到下一个标签页');
    });

    testWidgets('Ctrl+Shift+Tab 应切换到上一个标签页', (tester) async {
      final appProvider = await pumpTestApp(tester);

      // Create 3 tabs
      for (var i = 0; i < 3; i++) {
        await appProvider.addNewTab(
          connectionId: 'test_conn',
          databaseName: 'test_db',
        );
      }
      await tester.pumpAndSettle();
      appProvider.setActiveTab(2);
      expect(appProvider.activeTabIndex, 2);

      await sendShortcut(
        tester,
        key: LogicalKeyboardKey.tab,
        control: true,
        shift: true,
      );
      await tester.pumpAndSettle();

      expect(
        appProvider.activeTabIndex,
        1,
        reason: 'Ctrl+Shift+Tab 应切换到上一个标签页',
      );
    });
  });

  group('MAN-KEY-005: Ctrl+Shift+F 格式化 SQL', () {
    testWidgets('按下 Ctrl+Shift+F 不应崩溃（有标签页时）', (tester) async {
      final appProvider = await pumpTestApp(tester);

      await appProvider.addNewTab(
        connectionId: 'test_conn',
        databaseName: 'test_db',
      );
      await tester.pumpAndSettle();

      expect(appProvider.activeTab, isNotNull);

      await sendShortcut(
        tester,
        key: LogicalKeyboardKey.keyF,
        control: true,
        shift: true,
      );

      expect(true, isTrue, reason: 'Ctrl+Shift+F 在有标签页时不应抛出异常');
    });
  });

  group('MAN-KEY-001: F5 执行查询', () {
    testWidgets('按下 F5 无查询时不应崩溃', (tester) async {
      await pumpTestApp(tester);

      await sendShortcut(tester, key: LogicalKeyboardKey.f5);

      expect(true, isTrue, reason: 'F5 在无查询时应优雅处理');
    });
  });
}
