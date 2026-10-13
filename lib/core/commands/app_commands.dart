// ============================================================================
// App Commands - Single source of truth for command palette
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../models/workbench_entry_intent.dart';
import '../../organisms/ai_workbench/ai_memory_manager_dialog.dart';
import '../../organisms/connection/command_palette.dart';
import '../../organisms/connection/connection_dialog.dart';
import '../../organisms/connection/connection_export_import_dialog.dart';
import '../../organisms/connection/error_boundary.dart';
import '../../organisms/connection/quick_search_dialog.dart';
import '../../organisms/connection/schema_diff_dialog.dart';
import '../../organisms/connection/table_dialog/create_super_table_dialog.dart';
import '../../organisms/connection/table_dialog/create_table_dialog.dart';
import '../../organisms/dialogs/mysql_events_dialog.dart';
import '../../organisms/dialogs/redis_backup_dialog.dart';
import '../../organisms/sidebar/plugins/sqlite_sidebar_plugin.dart';
import '../../organisms/sidebar/sidebar_current_connection.dart';
import '../../providers/app_provider.dart';
import '../../providers/tab_provider.dart';
import '../../services/ports/capability_table.dart';

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

    // ── J2 命令面板扩充（db-tooling-completion T15，2026-10）──────────────
    // 只登记现有可路由能力（纯路由零新功能）；全部内联 execute（沿
    // ai_memory_manager 先例，不扩 CommandBuilders record）；全部不带
    // shortcut 字段（键位唯一真相源纪律——零新增键位）。条件命令的
    // 上下文缺失一律静默返回（resolveSidebarActionServer null 既有模式），
    // 缺库提示沿 mysql_sidebar_plugin `_showEventsDesigner` 先例。
    Command(
      id: 'new_connection',
      label: l10n.commandNewConnection,
      description: l10n.commandDescNewConnection,
      icon: LucideIcons.plus,
      category: l10n.shortcutCategoryFile,
      keywords: ['connection', 'connect', '新建', '连接'],
      // home_screen `_showConnectionDialog` 同一 dialog 新建形态。
      execute: (context) => showDialog(
        context: context,
        builder: (_) => const ConnectionDialog(),
      ),
    ),
    Command(
      id: 'edit_connection',
      label: l10n.connectionEditConnection,
      description: l10n.commandDescEditConnection,
      icon: LucideIcons.pencil,
      category: l10n.shortcutCategoryFile,
      keywords: ['connection', 'edit', '编辑', '连接'],
      // 树根右键「编辑连接」同一 dialog 编辑形态（sidebar_tree
      // `ConnectionDialog(existingServer: server)`）；锚定
      // resolveSidebarCurrentConnection（currentServer → tab → 侧栏选中）。
      execute: (context) {
        final server =
            resolveSidebarCurrentConnection(context.read<AppProvider>());
        if (server == null) return; // 无连接静默返回（既有模式）
        showDialog(
          context: context,
          builder: (_) => ConnectionDialog(existingServer: server),
        );
      },
    ),
    Command(
      id: 'disconnect_connection',
      label: l10n.menuDisconnect,
      description: l10n.commandDescDisconnectConnection,
      icon: LucideIcons.unplug,
      category: l10n.shortcutCategoryFile,
      keywords: ['connection', 'disconnect', '断开', '连接'],
      // 树根右键 disconnect case 同一调用（provider.disconnectConnection）。
      execute: (context) {
        final server =
            resolveSidebarCurrentConnection(context.read<AppProvider>());
        if (server == null) return; // 无连接静默返回（既有模式）
        unawaited(
          context.read<AppProvider>().disconnectConnection(connectionId: server.id),
        );
      },
    ),
    Command(
      id: 'open_connection_manager',
      label: l10n.connectionManager,
      description: l10n.commandDescOpenConnectionManager,
      icon: LucideIcons.database,
      category: l10n.shortcutCategoryFile,
      keywords: ['connection', 'manager', '连接管理'],
      // home_screen `_showConnectionManager` 同一 dialog（自包含管理面，
      // 连接态可用——展示已存连接清单 + 活动连接数）。
      execute: (context) => showDialog(
        context: context,
        builder: (_) => const ConnectionManagerDialog(),
      ),
    ),
    Command(
      id: 'create_table',
      label: l10n.createNewTable,
      description: l10n.commandDescCreateTable,
      icon: LucideIcons.table,
      category: l10n.commandCategoryTools,
      keywords: ['table', 'create', '新建', '建表'],
      // 树库级 create_table / create_table_pg / create_supertable 三分支
      // 同源（`createTableMenuAction` 门控与路由同源，null = 不提供——
      // mongodb/redis 无建表概念）；dbName 取当前库，无库提示（任务书口径）。
      execute: (context) {
        final provider = context.read<AppProvider>();
        final server = resolveSidebarCurrentConnection(provider);
        if (server == null) return;
        final action = server.type.createTableMenuAction;
        if (action == null) return;
        final dbName = provider.activeDatabaseName;
        if (dbName == null || dbName.isEmpty) {
          AppErrorHandler.showWarningSnackBar(
            context,
            l10n.selectDatabaseFirst,
          );
          return;
        }
        switch (action) {
          case 'create_table_pg':
            showDialog(
              context: context,
              builder: (_) => CreatePostgresTableDialog(dbName: dbName),
            );
          case 'create_supertable':
            showDialog(
              context: context,
              builder: (_) => CreateSuperTableDialog(dbName: dbName),
            );
          default:
            showDialog(
              context: context,
              builder: (_) => CreateTableDialog(dbName: dbName),
            );
        }
      },
    ),
    Command(
      id: 'refresh_objects',
      label: l10n.commandRefreshObjects,
      description: l10n.commandDescRefreshObjects,
      icon: LucideIcons.refreshCw,
      category: l10n.commandCategoryTools,
      keywords: ['refresh', 'objects', '刷新', '对象'],
      // 树库级 refresh case 同一调用（provider.refreshDatabases()）。
      execute: (context) {
        unawaited(context.read<AppProvider>().refreshDatabases());
      },
    ),
    Command(
      id: 'view_table_ddl',
      label: l10n.viewTableDdl,
      description: l10n.commandDescViewTableDdl,
      icon: LucideIcons.code,
      category: l10n.commandCategoryTools,
      keywords: ['ddl', 'table', '查看', '建表语句'],
      // T16 只读对象标签路由：活动浏览 tab → openObjectTab(tableProperties,
      // DDL 直达)——树 U17「查看 DDL」同语义（initialTabIndex 随外键支持
      // 取 3/2，sidebar_tree view_ddl case 同源）。无 browseTarget = 不可用。
      execute: (context) =>
          _openTablePropertiesFromBrowse(context, initialDdlTab: true),
    ),
    Command(
      id: 'open_table_properties',
      label: l10n.commandOpenTableProperties,
      description: l10n.commandDescOpenTableProperties,
      icon: LucideIcons.info,
      category: l10n.commandCategoryTools,
      keywords: ['table', 'properties', '表属性', '结构'],
      // T16 只读对象标签路由（树表节点 Properties 同语义，首 tab 起）。
      execute: (context) =>
          _openTablePropertiesFromBrowse(context, initialDdlTab: false),
    ),
    Command(
      id: 'schema_diff',
      label: l10n.schemaDiffMenuItem,
      description: l10n.commandDescSchemaDiff,
      icon: LucideIcons.arrowRightLeft,
      category: l10n.commandCategoryTools,
      keywords: ['schema', 'diff', '对比', '结构'],
      // 树库级 schema_diff case 同一入口（SchemaDiffDialog.show，参数可选
      // ——锚定当前连接/库上下文，无上下文时 dialog 内自选）。
      execute: (context) {
        final provider = context.read<AppProvider>();
        final server = resolveSidebarCurrentConnection(provider);
        unawaited(
          SchemaDiffDialog.show(
            context: context,
            initialConnectionId: server?.id ?? provider.activeConnectionId,
            initialDatabaseName: provider.activeDatabaseName,
          ),
        );
      },
    ),
    Command(
      id: 'import_wizard',
      label: l10n.smartImportTitle,
      description: l10n.commandDescImportWizard,
      icon: LucideIcons.fileDown,
      category: l10n.commandCategoryTools,
      keywords: ['import', 'wizard', '导入', '向导'],
      // SQLite 面板级唯一干净入口（showSqliteSmartImportFlow 顶层函数，
      // 能力菜单与树内右键共用——T5）；其它库型入口在编辑器上下文，
      // 无面板级路由 → 本命令 SQLite 专属（任务书核实结论）。
      execute: (context) {
        final provider = context.read<AppProvider>();
        final server = resolveSidebarCurrentConnection(provider);
        if (server == null || server.type != DatabaseType.sqlite) return;
        showSqliteSmartImportFlow(context, provider, server.id);
      },
    ),
    Command(
      id: 'quick_search',
      label: l10n.commandQuickSearch,
      description: l10n.commandDescQuickSearch,
      icon: LucideIcons.search,
      category: l10n.commandCategoryTools,
      keywords: ['search', 'quick', '快搜', '查找'],
      // global_shortcuts_wrapper Ctrl+K 同一入口（QuickSearchDialog.show）。
      execute: (context) => QuickSearchDialog.show(context),
    ),
    Command(
      id: 'mysql_events',
      label: l10n.mysqlEventsTitle,
      icon: LucideIcons.calendarClock,
      category: l10n.commandCategoryTools,
      keywords: ['mysql', 'event', '事件', '调度'],
      // 能力菜单 `mysql.events` 项同源路由（T18 事件设计器）：`event.list`
      // 位门控保留（{mysql}）+ 缺库提示，锚定当前连接。
      execute: (context) {
        final provider = context.read<AppProvider>();
        final server = resolveSidebarCurrentConnection(provider);
        if (server == null) return;
        if (!CapabilityTable.has(server.type, 'event.list')) return;
        final databaseName =
            server.database ?? provider.connection.currentDatabase?.name;
        if (databaseName == null || databaseName.isEmpty) {
          AppErrorHandler.showWarningSnackBar(
            context,
            l10n.selectDatabaseFirst,
          );
          return;
        }
        MysqlEventsDialog.show(
          context,
          connectionId: server.id,
          databaseName: databaseName,
        );
      },
    ),
    Command(
      id: 'redis_backup',
      label: l10n.redisBackupTitle,
      icon: LucideIcons.archive,
      category: l10n.commandCategoryTools,
      keywords: ['redis', 'backup', '备份', '持久化'],
      // 能力菜单 `redis.backup` 项同源路由（T20 备份触发）：`redis.backup`
      // 位门控保留（{redis}），锚定当前连接。
      execute: (context) {
        final server =
            resolveSidebarCurrentConnection(context.read<AppProvider>());
        if (server == null) return;
        if (!CapabilityTable.has(server.type, 'redis.backup')) return;
        RedisBackupDialog.show(context, connectionId: server.id);
      },
    ),
  ];
}

/// T15：活动浏览 tab → 只读对象标签（表属性/DDL 直达）。
///
/// 可用性 fail-closed：活动 tab 缺失或 `browseTargetFor` 为空 → 静默返回
/// （任务书「无 browseTarget = 禁用」；手写 SQL 结果网格天然不开放）。
/// connectionId/databaseName 取同一 tab 的绑定上下文（与 browse 目标同源）。
void _openTablePropertiesFromBrowse(
  BuildContext context, {
  required bool initialDdlTab,
}) {
  final provider = context.read<AppProvider>();
  final tab = provider.activeTab;
  final target = tab == null ? null : provider.browseTargetFor(tab.id);
  if (tab == null || target == null || target.isEmpty) return;
  provider.openObjectTab(
    ObjectTabRef(
      kind: ObjectTabKind.tableProperties,
      connectionId: tab.connectionId,
      databaseName: tab.databaseName,
      objectName: target,
      // 树 U17「查看 DDL」直达索引同源：有外键 tab 的库是第 4 个、否则第 3 个。
      initialTabIndex: initialDdlTab
          ? (tab.databaseType?.supportsForeignKeys ?? false ? 3 : 2)
          : 0,
    ),
  );
}
