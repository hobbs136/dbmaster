// ============================================================================
// App Commands - Single source of truth for command palette
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../models/workbench_entry_intent.dart';
import '../../organisms/ai_workbench/ai_memory_manager_dialog.dart';
import '../../organisms/connection/command_palette.dart';
import '../../organisms/connection/connection_export_import_dialog.dart';
import '../../providers/app_provider.dart';

/// Builder type for command execute callbacks
typedef CommandBuilders = ({
  VoidCallback onNewTab,
  VoidCallback onCloseTab,
  VoidCallback onExecuteQuery,
  VoidCallback onFormatSql,
  VoidCallback onToggleAiPanel,
  VoidCallback onToggleAiFullscreen,
  VoidCallback onIncreaseOpacity,
  VoidCallback onDecreaseOpacity,
  VoidCallback onShortcuts,
  VoidCallback onPerformanceAnalyzer,
  VoidCallback onERDiagram,
  VoidCallback onAuditLog,
});

/// Build the complete command list for the Command Palette
List<Command> buildCommands(AppLocalizations l10n, CommandBuilders handlers) {
  return [
    Command(
      id: 'new_tab',
      label: l10n.commandNewTab,
      description: l10n.commandDescNewTab,
      icon: LucideIcons.appWindow,
      category: l10n.shortcutCategoryView,
      shortcut: 'Ctrl+T',
      keywords: ['标签', 'tab'],
      execute: (context) => handlers.onNewTab(),
    ),
    Command(
      id: 'close_tab',
      label: 'Close Tab',
      description: 'Close current tab',
      icon: LucideIcons.x,
      category: l10n.shortcutCategoryView,
      shortcut: 'Ctrl+W',
      keywords: ['关闭', 'close', 'tab'],
      execute: (context) => handlers.onCloseTab(),
    ),
    Command(
      id: 'execute_query',
      label: l10n.commandExecuteQuery,
      description: l10n.commandDescExecuteQuery,
      icon: LucideIcons.play,
      category: l10n.shortcutCategoryEdit,
      shortcut: 'Ctrl+Enter',
      keywords: ['执行', 'execute', 'query'],
      execute: (context) => handlers.onExecuteQuery(),
    ),
    Command(
      id: 'format_sql',
      label: l10n.commandFormatSql,
      description: l10n.commandDescFormatSql,
      icon: LucideIcons.alignLeft,
      category: l10n.shortcutCategoryEdit,
      shortcut: 'Ctrl+Shift+F',
      keywords: ['格式化', 'format'],
      execute: (context) => handlers.onFormatSql(),
    ),
    Command(
      id: 'toggle_ai_panel',
      label: l10n.commandToggleAiPanel,
      description: l10n.commandDescToggleAiPanel,
      icon: LucideIcons.bot,
      category: l10n.shortcutCategoryView,
      shortcut: 'Ctrl+Shift+A',
      keywords: ['AI', 'panel'],
      execute: (context) => handlers.onToggleAiPanel(),
    ),
    Command(
      id: 'toggle_ai_panel_fullscreen',
      // D2 迁移（design §3.1）：显示名换工作台文案，id 不改（快捷键三处
      // 同步纪律之外的面不动）。
      label: l10n.workbenchCommandEnterWorkbench,
      description: l10n.commandDescToggleAiPanel,
      icon: LucideIcons.maximize,
      category: l10n.shortcutCategoryView,
      shortcut: 'Ctrl+Shift+G',
      keywords: ['AI', 'workbench', 'fullscreen', 'panel'],
      execute: (context) => handlers.onToggleAiFullscreen(),
    ),
    Command(
      id: 'increase_opacity',
      label: 'Increase AI Overlay Opacity',
      description: 'Increase AI overlay background opacity',
      icon: LucideIcons.droplet,
      category: l10n.shortcutCategoryView,
      shortcut: 'Ctrl++',
      keywords: ['透明度', 'opacity'],
      execute: (context) => handlers.onIncreaseOpacity(),
    ),
    Command(
      id: 'decrease_opacity',
      label: 'Decrease AI Overlay Opacity',
      description: 'Decrease AI overlay background opacity',
      icon: LucideIcons.droplet,
      category: l10n.shortcutCategoryView,
      shortcut: 'Ctrl+-',
      keywords: ['透明度', 'opacity'],
      execute: (context) => handlers.onDecreaseOpacity(),
    ),
    Command(
      id: 'shortcuts',
      label: l10n.commandShortcuts,
      description: l10n.commandDescShortcuts,
      icon: LucideIcons.keyboard,
      category: l10n.commandCategoryHelp,
      shortcut: 'Ctrl+/',
      keywords: ['快捷键', 'shortcuts'],
      execute: (context) => handlers.onShortcuts(),
    ),
    Command(
      id: 'performance_analyzer',
      label: 'Performance Analyzer',
      description: 'Analyze slow queries, indexes, and table statistics',
      icon: LucideIcons.gauge,
      category: l10n.commandCategoryTools,
      keywords: [
        'performance',
        'analyzer',
        'slow query',
        'index',
        'statistics',
      ],
      execute: (context) => handlers.onPerformanceAnalyzer(),
    ),
    Command(
      id: 'er_diagram',
      label: 'ER Diagram',
      description: 'View entity-relationship diagram for current database',
      icon: LucideIcons.network,
      category: l10n.commandCategoryTools,
      keywords: ['er', 'diagram', 'relationship', 'schema'],
      execute: (context) => handlers.onERDiagram(),
    ),
    Command(
      id: 'audit_log',
      label: 'Query Audit Log',
      description: 'View query execution history and statistics',
      icon: LucideIcons.history,
      category: l10n.commandCategoryTools,
      keywords: ['audit', 'log', 'history', 'query', 'statistics'],
      execute: (context) => handlers.onAuditLog(),
    ),
    Command(
      id: 'export_connections',
      label: l10n.exportConnectionsTitle,
      icon: LucideIcons.fileUp,
      category: l10n.commandCategoryTools,
      execute: (context) => ConnectionExportImportDialog.showExport(
        context,
        connections: context.read<AppProvider>().connection.savedConnections,
      ),
    ),
    Command(
      id: 'import_connections',
      label: l10n.importConnectionsTitle,
      icon: LucideIcons.fileDown,
      category: l10n.commandCategoryTools,
      execute: (context) => ConnectionExportImportDialog.showImport(context),
    ),
    Command(
      id: 'ai_memory_manager',
      label: l10n.commandAiMemoryManager,
      description: l10n.commandDescAiMemoryManager,
      icon: LucideIcons.brain,
      category: l10n.commandCategoryTools,
      keywords: ['AI', 'memory', '记忆'],
      // 内联 execute（同 export/import_connections 先例，不扩 CommandBuilders）；
      // 当前连接 id 由命令面板上下文解析（currentServer 优先语义同侧栏）。
      execute: (context) => showAiMemoryManagerDialog(
        context,
        connectionId: context.read<AppProvider>().connection.currentServer?.id,
      ),
    ),
    Command(
      id: 'open_observe',
      label: l10n.commandOpenObserve,
      description: l10n.commandDescOpenObserve,
      icon: LucideIcons.activity,
      category: l10n.commandCategoryTools,
      keywords: ['observe', '观察', 'monitor', 'health', 'instance'],
      // 内联 execute（同 ai_memory_manager 先例，不扩 CommandBuilders）：
      // 开工作台 + 推 observe tab（R7；observe 单例跟随锁定连接，2b.1）。
      execute: (context) {
        final aiPanel = context.read<AppProvider>().aiPanel;
        aiPanel.setAiPanelOpen(true);
        aiPanel.setAiPanelFullscreen(true);
        aiPanel.ensureSession();
        aiPanel.requestWorkbenchEntry(
          tabTarget: WorkbenchEntryTabTarget.observe,
        );
      },
    ),
    Command(
      id: 'open_saved_queries',
      label: l10n.commandOpenSavedQueries,
      description: l10n.commandDescOpenSavedQueries,
      icon: LucideIcons.bookmark,
      category: l10n.commandCategoryTools,
      keywords: ['saved', 'query', '保存', '查询'],
      // 内联 execute（同 ai_memory_manager 先例）：开工作台 + 推保存的查询
      // tab（先行批 A4 舞台同源单例，§8-2）。
      execute: (context) {
        final aiPanel = context.read<AppProvider>().aiPanel;
        aiPanel.setAiPanelOpen(true);
        aiPanel.setAiPanelFullscreen(true);
        aiPanel.ensureSession();
        aiPanel.requestWorkbenchEntry(
          tabTarget: WorkbenchEntryTabTarget.savedQueries,
        );
      },
    ),
    Command(
      id: 'open_history',
      label: l10n.commandOpenHistory,
      description: l10n.commandDescOpenHistory,
      icon: LucideIcons.history,
      category: l10n.commandCategoryTools,
      keywords: ['history', '历史', 'query'],
      // 内联 execute（同 ai_memory_manager 先例）：开工作台 + 推查询历史
      // tab（先行批 A3 舞台同源单例，§8-2）。
      execute: (context) {
        final aiPanel = context.read<AppProvider>().aiPanel;
        aiPanel.setAiPanelOpen(true);
        aiPanel.setAiPanelFullscreen(true);
        aiPanel.ensureSession();
        aiPanel.requestWorkbenchEntry(
          tabTarget: WorkbenchEntryTabTarget.history,
        );
      },
    ),
    Command(
      id: 'open_scheduled_tasks',
      label: l10n.commandOpenScheduledTasks,
      description: l10n.commandDescOpenScheduledTasks,
      icon: LucideIcons.clock,
      category: l10n.commandCategoryTools,
      keywords: ['scheduled', 'task', '定时任务', 'cron'],
      // 内联 execute（同 ai_memory_manager 先例）：开工作台 only（占位）。
      // TODO: taskList 第二批接线——届时推 scheduledTasks tab；本批
      // tabTarget: none（描述文案已预告「随下一批上线」）。
      execute: (context) {
        final aiPanel = context.read<AppProvider>().aiPanel;
        aiPanel.setAiPanelOpen(true);
        aiPanel.setAiPanelFullscreen(true);
        aiPanel.ensureSession();
        aiPanel.requestWorkbenchEntry();
      },
    ),
  ];
}
