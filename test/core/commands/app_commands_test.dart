import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/core/commands/app_commands.dart';
import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/l10n/app_localizations_en.dart';
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

    test('应返回 14 个命令', () {
      final commands = buildCommands(l10n, buildHandlers());
      expect(commands.length, 14);
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
        ]),
      );
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
        if (cmd.id == 'export_connections' || cmd.id == 'import_connections') {
          continue;
        }
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
    });
  });
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
