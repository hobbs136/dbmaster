import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dbmaster/core/commands/app_commands.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
import 'package:dbmaster/models/workbench_entry_intent.dart';
import 'package:dbmaster/organisms/connection/command_palette.dart'
    show Command;
import 'package:dbmaster/organisms/connection/connection_dialog.dart';
import 'package:dbmaster/organisms/connection/quick_search_dialog.dart';
import 'package:dbmaster/organisms/connection/schema_diff_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/tab_provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('buildCommands', () {
    late AppLocalizations l10n;
    late List<String> executedCommands;

    setUp(() {
      l10n = AppLocalizationsEn();
      executedCommands = [];
    });

    CommandBuilders buildHandlers() {
      return (
        onNewTab: () => executedCommands.add('new_tab'),
        onCloseTab: () => executedCommands.add('close_tab'),
        onExecuteQuery: () => executedCommands.add('execute_query'),
        onFormatSql: () => executedCommands.add('format_sql'),
        onToggleAiPanel: () => executedCommands.add('toggle_ai'),
        onToggleAiFullscreen: () =>
            executedCommands.add('toggle_ai_fullscreen'),
        onIncreaseOpacity: () => executedCommands.add('increase_opacity'),
        onDecreaseOpacity: () => executedCommands.add('decrease_opacity'),
        onShortcuts: () => executedCommands.add('shortcuts'),
        onPerformanceAnalyzer: () => executedCommands.add('performance'),
        onERDiagram: () => executedCommands.add('er_diagram'),
        onAuditLog: () => executedCommands.add('audit_log'),
      );
    }

    test('应返回 32 个命令（T15 扩充 19→32）', () {
      final commands = buildCommands(l10n, buildHandlers());
      expect(commands.length, 32);
    });

    test('应包含所有预期命令 ID', () {
      final commands = buildCommands(l10n, buildHandlers());
      final ids = commands.map((c) => c.id).toList();
      expect(
        ids,
        containsAll([
          'new_tab',
          'close_tab',
          'execute_query',
          'format_sql',
          'toggle_ai_panel',
          'toggle_ai_panel_fullscreen',
          'increase_opacity',
          'decrease_opacity',
          'shortcuts',
          'performance_analyzer',
          'er_diagram',
          'audit_log',
          'export_connections',
          'import_connections',
          'ai_memory_manager',
          'open_observe',
          'open_saved_queries',
          'open_history',
          'open_scheduled_tasks',
          // T15 命令面板扩充（13 条，只登记现有可路由能力）
          'new_connection',
          'edit_connection',
          'disconnect_connection',
          'open_connection_manager',
          'create_table',
          'refresh_objects',
          'view_table_ddl',
          'open_table_properties',
          'schema_diff',
          'import_wizard',
          'quick_search',
          'mysql_events',
          'redis_backup',
        ]),
      );
    });

    test('命令 id 应唯一', () {
      final commands = buildCommands(l10n, buildHandlers());
      final ids = commands.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'Command id 必须唯一');
    });

    test('T15 扩充命令应零新增键位（shortcut 为空）', () {
      final commands = buildCommands(l10n, buildHandlers());
      const newIds = [
        'new_connection',
        'edit_connection',
        'disconnect_connection',
        'open_connection_manager',
        'create_table',
        'refresh_objects',
        'view_table_ddl',
        'open_table_properties',
        'schema_diff',
        'import_wizard',
        'quick_search',
        'mysql_events',
        'redis_backup',
      ];
      for (final id in newIds) {
        final cmd = commands.firstWhere((c) => c.id == id);
        expect(
          cmd.shortcut,
          isEmpty,
          reason: '$id 不得声明 shortcut（键位唯一真相源纪律）',
        );
      }
    });

    test('每个命令应有非空 ID 和 label', () {
      final commands = buildCommands(l10n, buildHandlers());
      for (final cmd in commands) {
        expect(cmd.id, isNotEmpty, reason: 'Command ID should not be empty');
        expect(
          cmd.label,
          isNotEmpty,
          reason: 'Command label should not be empty',
        );
      }
    });

    test('每个命令应有非空 category', () {
      final commands = buildCommands(l10n, buildHandlers());
      for (final cmd in commands) {
        expect(
          cmd.category,
          isNotEmpty,
          reason: 'Command category should not be empty',
        );
      }
    });

    test('命令应有正确的快捷键映射', () {
      final commands = buildCommands(l10n, buildHandlers());
      final shortcuts = {for (var c in commands) c.id: c.shortcut};

      expect(shortcuts['new_tab'], 'Ctrl+T');
      expect(shortcuts['close_tab'], 'Ctrl+W');
      expect(shortcuts['execute_query'], 'Ctrl+Enter');
      expect(shortcuts['format_sql'], 'Ctrl+Shift+F');
      expect(shortcuts['toggle_ai_panel'], 'Ctrl+Shift+A');
      expect(shortcuts['toggle_ai_panel_fullscreen'], 'Ctrl+Shift+G');
      expect(shortcuts['increase_opacity'], 'Ctrl++');
      expect(shortcuts['decrease_opacity'], 'Ctrl+-');
      expect(shortcuts['shortcuts'], 'Ctrl+/');
    });

    testWidgets('new_tab 命令应触发 onNewTab 回调', (tester) async {
      final context = await _pumpContext(tester);
      final commands = buildCommands(l10n, buildHandlers());
      final newTabCmd = commands.firstWhere((c) => c.id == 'new_tab');
      newTabCmd.execute(context);
      expect(executedCommands, contains('new_tab'));
    });

    testWidgets('execute_query 命令应触发 onExecuteQuery 回调', (tester) async {
      final context = await _pumpContext(tester);
      final commands = buildCommands(l10n, buildHandlers());
      final cmd = commands.firstWhere((c) => c.id == 'execute_query');
      cmd.execute(context);
      expect(executedCommands, contains('execute_query'));
    });

    testWidgets('toggle_ai_panel 命令应触发 onToggleAiPanel 回调', (tester) async {
      final context = await _pumpContext(tester);
      final commands = buildCommands(l10n, buildHandlers());
      final cmd = commands.firstWhere((c) => c.id == 'toggle_ai_panel');
      cmd.execute(context);
      expect(executedCommands, contains('toggle_ai'));
    });

    testWidgets('所有命令执行回调应互不干扰', (tester) async {
      final context = await _pumpContext(tester);
      final commands = buildCommands(l10n, buildHandlers());
      for (final cmd in commands) {
        // 内联 execute（读 AppProvider 或开 dialog）的命令在此 harness
        // 无 Provider / 无 dialog 断言面，与 export/import_connections 同样
        // 跳过（各自正路径由下方 T15 组与 2b.4 组专测）。
        const inlineExecuteIds = [
          'export_connections',
          'import_connections',
          'ai_memory_manager',
          'open_observe',
          'open_saved_queries',
          'open_history',
          'open_scheduled_tasks',
          // T15 扩充（全部内联 execute）
          'new_connection',
          'edit_connection',
          'disconnect_connection',
          'open_connection_manager',
          'create_table',
          'refresh_objects',
          'view_table_ddl',
          'open_table_properties',
          'schema_diff',
          'import_wizard',
          'quick_search',
          'mysql_events',
          'redis_backup',
        ];
        if (inlineExecuteIds.contains(cmd.id)) continue;
        cmd.execute(context);
      }
      // 有些命令共享 handler 类型但不同实例，允许重复
      expect(executedCommands.length, 12);
    });

    test('命令 keywords 应包含搜索关键词', () {
      final commands = buildCommands(l10n, buildHandlers());
      final newTab = commands.firstWhere((c) => c.id == 'new_tab');
      expect(newTab.keywords, isNotEmpty);
      expect(newTab.keywords, contains('tab'));
    });

    test('命令应有正确的 icon', () {
      final commands = buildCommands(l10n, buildHandlers());
      final icons = {for (var c in commands) c.id: c.icon};
      expect(icons['new_tab'], LucideIcons.appWindow);
      expect(icons['execute_query'], LucideIcons.play);
      expect(icons['format_sql'], LucideIcons.alignLeft);
      expect(icons['toggle_ai_panel'], LucideIcons.bot);
      expect(icons['shortcuts'], LucideIcons.keyboard);
      expect(icons['export_connections'], LucideIcons.fileUp);
      expect(icons['import_connections'], LucideIcons.fileDown);
      expect(icons['open_observe'], LucideIcons.activity);
      expect(icons['open_saved_queries'], LucideIcons.bookmark);
      expect(icons['open_history'], LucideIcons.history);
      expect(icons['open_scheduled_tasks'], LucideIcons.clock);
    });
  });

  group('2b.4 工作台引流四条目（内联 execute 调用面）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('open_observe：开工作台 + 推 observe intent', (tester) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      final commands = buildCommands(AppLocalizationsEn(), _noopHandlers());
      commands.firstWhere((c) => c.id == 'open_observe').execute(context);

      expect(app.aiPanelOpen, isTrue);
      expect(app.aiPanelFullscreen, isTrue);
      final intent = app.aiPanel.workbenchEntryIntent;
      expect(intent, isNotNull);
      expect(intent!.tabTarget, equals(WorkbenchEntryTabTarget.observe));
      expect(intent.prompt, isNull);

      // 泄放 ensureSession 的持久化防抖 Timer（500ms）。
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('open_saved_queries：开工作台 + 推 savedQueries intent', (
      tester,
    ) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      final commands = buildCommands(AppLocalizationsEn(), _noopHandlers());
      commands
          .firstWhere((c) => c.id == 'open_saved_queries')
          .execute(context);

      expect(app.aiPanelOpen, isTrue);
      expect(app.aiPanelFullscreen, isTrue);
      expect(
        app.aiPanel.workbenchEntryIntent?.tabTarget,
        equals(WorkbenchEntryTabTarget.savedQueries),
      );

      // 泄放 ensureSession 的持久化防抖 Timer（500ms）。
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('open_history：开工作台 + 推 history intent', (tester) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      final commands = buildCommands(AppLocalizationsEn(), _noopHandlers());
      commands.firstWhere((c) => c.id == 'open_history').execute(context);

      expect(app.aiPanelOpen, isTrue);
      expect(app.aiPanelFullscreen, isTrue);
      expect(
        app.aiPanel.workbenchEntryIntent?.tabTarget,
        equals(WorkbenchEntryTabTarget.history),
      );

      // 泄放 ensureSession 的持久化防抖 Timer（500ms）。
      await tester.pump(const Duration(milliseconds: 600));
    });

    testWidgets('open_scheduled_tasks：开工作台 only（占位，tabTarget none）', (
      tester,
    ) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      final commands = buildCommands(AppLocalizationsEn(), _noopHandlers());
      commands
          .firstWhere((c) => c.id == 'open_scheduled_tasks')
          .execute(context);

      expect(app.aiPanelOpen, isTrue);
      expect(app.aiPanelFullscreen, isTrue);
      expect(
        app.aiPanel.workbenchEntryIntent?.tabTarget,
        equals(WorkbenchEntryTabTarget.none),
      );
      expect(app.aiPanel.workbenchEntryIntent?.prompt, isNull);

      // 泄放 ensureSession 的持久化防抖 Timer（500ms）。
      await tester.pump(const Duration(milliseconds: 600));
    });
  });

  group('T15 命令面板扩充（内联 execute 调用面：守卫 + 路由正路径）', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Command findCommand(String id) =>
        buildCommands(AppLocalizationsEn(), _noopHandlers()).firstWhere(
          (c) => c.id == id,
        );

    testWidgets('条件命令无连接/无浏览目标时静默不动作（fail-closed）', (tester) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      const conditionalIds = [
        'edit_connection',
        'disconnect_connection',
        'view_table_ddl',
        'open_table_properties',
        'create_table',
        'import_wizard',
        'mysql_events',
        'redis_backup',
      ];
      for (final id in conditionalIds) {
        findCommand(id).execute(context);
      }
      await tester.pump();
      // 零 dialog、零对象 tab（无连接上下文一律静默返回）。
      expect(find.byType(ConnectionDialog), findsNothing);
      expect(app.tab.tabs, isEmpty);
    });

    testWidgets('view_table_ddl：活动浏览 tab → openObjectTab（DDL 直达）', (
      tester,
    ) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      await app.openQueryTab('c1', 'db1');
      final browseTabId = app.activeTab!.id;
      app.setBrowseTarget(browseTabId, 'users');

      findCommand('view_table_ddl').execute(context);

      // T16 语义：对象 tab 是新建的独立 tab（editor/results 全隐），非挂在
      // 浏览 tab 上——断言新建 tab 的对象引用与字段映射。
      expect(app.tab.tabs.length, 2);
      final objectTab = app.tab.tabs.last;
      final ref = app.tab.objectTabFor(objectTab.id);
      expect(ref, isNotNull);
      expect(ref!.kind, ObjectTabKind.tableProperties);
      expect(ref.objectName, 'users');
      expect(ref.databaseName, 'db1');
      // tab.databaseType 为 null（无 adapter）→ supportsForeignKeys false → 2。
      expect(ref.initialTabIndex, 2);
    });

    testWidgets('open_table_properties：活动浏览 tab → openObjectTab（首 tab）', (
      tester,
    ) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      await app.openQueryTab('c1', 'db1');
      final browseTabId = app.activeTab!.id;
      app.setBrowseTarget(browseTabId, 'orders');

      findCommand('open_table_properties').execute(context);

      expect(app.tab.tabs.length, 2);
      final ref = app.tab.objectTabFor(app.tab.tabs.last.id);
      expect(ref, isNotNull);
      expect(ref!.kind, ObjectTabKind.tableProperties);
      expect(ref.objectName, 'orders');
      expect(ref.initialTabIndex, 0);
    });

    testWidgets('view_table_ddl/open_table_properties：手写 SQL tab（无浏览目标）不动作', (
      tester,
    ) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      await app.openQueryTab('c1', 'db1'); // 无 setBrowseTarget
      final tabId = app.activeTab!.id;

      findCommand('view_table_ddl').execute(context);
      findCommand('open_table_properties').execute(context);

      expect(app.tab.tabs.length, 1);
      expect(app.tab.objectTabFor(tabId), isNull);
    });

    testWidgets('new_connection：打开连接 dialog（新建形态）', (tester) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      findCommand('new_connection').execute(context);
      await tester.pump();
      expect(find.byType(ConnectionDialog), findsOneWidget);
    });

    testWidgets('open_connection_manager：打开连接管理 dialog', (tester) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      findCommand('open_connection_manager').execute(context);
      await tester.pump();
      expect(find.byType(ConnectionManagerDialog), findsOneWidget);
    });

    testWidgets('schema_diff：打开 Schema Diff dialog', (tester) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      findCommand('schema_diff').execute(context);
      await tester.pump();
      expect(find.byType(SchemaDiffDialog), findsOneWidget);
    });

    testWidgets('quick_search：打开快速搜索 dialog', (tester) async {
      final app = AppProvider();
      final context = await _pumpProviderContext(tester, app);
      findCommand('quick_search').execute(context);
      await tester.pump();
      expect(find.byType(QuickSearchDialog), findsOneWidget);
    });
  });
}

/// 空 handlers（2b.4 组只测内联 execute 的四条目，不经 CommandBuilders）。
CommandBuilders _noopHandlers() {
  return (
    onNewTab: () {},
    onCloseTab: () {},
    onExecuteQuery: () {},
    onFormatSql: () {},
    onToggleAiPanel: () {},
    onToggleAiFullscreen: () {},
    onIncreaseOpacity: () {},
    onDecreaseOpacity: () {},
    onShortcuts: () {},
    onPerformanceAnalyzer: () {},
    onERDiagram: () {},
    onAuditLog: () {},
  );
}

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return capturedContext;
}

/// 带 AppProvider 的 context（内联 execute 读 provider 的命令调用面用）。
/// 带 l10n delegates（T15 正路径断言会 pump 出 dialog，dialog 构建依赖
/// AppLocalizations）。
Future<BuildContext> _pumpProviderContext(
  WidgetTester tester,
  AppProvider app,
) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    ChangeNotifierProvider<AppProvider>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return capturedContext;
}
