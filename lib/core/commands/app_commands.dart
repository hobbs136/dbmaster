// ============================================================================
// App Commands - Single source of truth for command palette
// ============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
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
      label: '${l10n.commandToggleAiPanel} (Fullscreen)',
      description: l10n.commandDescToggleAiPanel,
      icon: LucideIcons.maximize,
      category: l10n.shortcutCategoryView,
      shortcut: 'Ctrl+Shift+G',
      keywords: ['AI', 'fullscreen', 'panel'],
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
  ];
}
