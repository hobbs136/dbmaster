import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';
import '../../atoms/app_widgets.dart';
import '../../providers/app_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/server_connection_provider.dart';
import '../../models/database_models.dart' hide QueryTab;
import '../../models/ai_tree_node_context.dart';
import '../../models/table_maintenance_command.dart';
import '../sidebar/mysql_engine_status_dialog.dart';
import '../../services/ports/capability_table.dart';
import '../connection/connection_dialog.dart';
import '../connection/connection_export_import_dialog.dart';
import '../connection/error_boundary.dart';
import '../connection/password_prompt_dialog.dart';
import '../connection/table_dialog/create_table_dialog.dart';
import '../connection/table_dialog/create_super_table_dialog.dart';
import '../connection/table_dialog/edit_table_dialog.dart';
import '../connection/table_dialog/table_properties_dialog.dart';
import '../connection/table_dialog/rename_table_dialog.dart';
import '../connection/table_dialog/truncate_table_confirm_dialog.dart';
import '../connection/table_dialog/edit_index_dialog.dart';
import '../connection/database_dialog.dart';
import '../connection/schema_diff_dialog.dart';
import '../../services/schema_diff/schema_diff_service.dart';
import '../../services/schema_diff/schema_snapshot_service.dart';
import '../dialogs/confirm_maintenance_dialog.dart';
import '../dialogs/table_maintenance_result_dialog.dart';
import '../pro/pro_sync_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_logger.dart';
import '../../utils/sql_escape_utils.dart';
import '../../utils/index_dialect_names.dart';
import 'tree_item.dart';
import 'saved_queries/saved_queries_section.dart';
import 'sidebar_current_connection.dart';
import 'sidebar_section.dart';
import 'builders/tree_utils.dart';
import '../../molecules/context_menu.dart';
import '../../plugins/bootstrap.dart';
import '../../plugins/plugin_descriptor.dart' show PluginSource;
import '../../plugins/sidebar_plugin.dart';

class SidebarTree extends StatelessWidget {
  final String searchQuery;
  final Set<String> expandedItems;
  final Set<String> expandedDatabases;
  final Set<String> expandedTables;
  final Set<String> loadingDatabases;
  final Map<String, DbTable> loadedTableSchemas;
  final Map<String, List<ForeignKey>> loadedTableForeignKeys;
  final Set<String> loadingTableSchemas;
  final Function(String) onToggleExpand;
  final Function(String) onToggleDatabase;
  final Function(String) onToggleTable;
  final Future<void> Function(String, String) onLoadDatabaseInfo;
  final Future<void> Function(String)? onLoadTableSchema;
  final VoidCallback onShowConnectionManager;
  final VoidCallback onShowSettings;
  final VoidCallback onShowERDiagram;
  final VoidCallback onShowStoredProcedures;
  final VoidCallback onShowTriggers;
  final VoidCallback? onCollapseAll;
  final String? rightClickedNodeKey;
  final ValueChanged<String?>? onRightClickTargetChanged;
  final String? selectedNodeKey;
  final ValueChanged<String>? onSelectNode;
  final Map<String, int> tableRowCounts;
  final Future<void> Function(String connectionId, String databaseName)?
  onLoadTableRowCounts;
  final Map<String, List<Map<String, String>>> serverSearchResults;
  final ScrollController? scrollController;

  const SidebarTree({
    super.key,
    this.searchQuery = '',
    this.serverSearchResults = const {},
    required this.expandedItems,
    required this.expandedDatabases,
    required this.expandedTables,
    required this.loadingDatabases,
    this.loadedTableSchemas = const {},
    this.loadedTableForeignKeys = const {},
    this.loadingTableSchemas = const {},
    required this.onToggleExpand,
    required this.onToggleDatabase,
    required this.onToggleTable,
    required this.onLoadDatabaseInfo,
    this.onLoadTableSchema,
    required this.onShowConnectionManager,
    required this.onShowSettings,
    required this.onShowERDiagram,
    required this.onShowStoredProcedures,
    required this.onShowTriggers,
    this.onCollapseAll,
    this.rightClickedNodeKey,
    this.onRightClickTargetChanged,
    this.selectedNodeKey,
    this.onSelectNode,
    this.tableRowCounts = const {},
    this.onLoadTableRowCounts,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final connections = provider.connection.savedConnections;

        if (connections.isEmpty) {
          return AppEmptyState(
            icon: LucideIcons.database,
            title: AppLocalizations.of(context)!.sidebarNoConnections,
            description: AppLocalizations.of(
              context,
            )!.sidebarClickToCreateConnection,
            iconSize: 56,
            action: TextButton(
              onPressed: onShowConnectionManager,
              style: TextButton.styleFrom(
                foregroundColor: context.themeColors.accentBlue,
              ),
              child: Text(
                AppLocalizations.of(context)!.sidebarCreateConnection,
              ),
            ),
          );
        }

        // C22-1 单实例专注树：树只渲染当前连接（活动 tab → currentServer
        // → 侧栏选中，与顶部连接选择器同源）——多连接列表/分组装配删除，
        // 全部连接的入口收敛到选择器下拉；切换连接即切换树。
        final current = resolveSidebarCurrentConnection(provider);
        if (current == null) {
          return _buildNoCurrentHint(context);
        }

        final sq = searchQuery.toLowerCase();
        final recentSection = _buildRecentSection(context, provider);
        final favoriteEntries = provider.sidebar.favoriteTables.toList();

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space2),
          children: [
            if (favoriteEntries.isNotEmpty)
              _buildFavoritesSection(context, provider, favoriteEntries),
            ?recentSection,
            _buildConnectionNode(context, provider, current, sq),
          ],
        );
      },
    );
  }

  /// 有已保存连接但当前无锚定连接（全部未连接且未选中）：轻提示引导走
  /// 顶部选择器（点击提示也可直接打开管理器）。
  Widget _buildNoCurrentHint(BuildContext context) {
    final colors = context.themeColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.mousePointerClick,
              size: 32,
              color: colors.textMuted,
            ),
            const SizedBox(height: AppDesignSystem.space2),
            Text(
              AppLocalizations.of(context)!.sidebarSelectConnectionHint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesSection(
    BuildContext context,
    AppProvider provider,
    List<String> favoriteKeys,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return SidebarSection(
      icon: LucideIcons.star,
      iconColor: context.themeColors.warning,
      label: l10n.sidebarFavorites,
      count: favoriteKeys.length,
      children: favoriteKeys.map((key) {
        final parts = key.split(':');
        // Support 4-part keys (cid:db:schemaName:tableName) for schema-aware DBs
        final tableName = parts.length >= 4
            ? '${parts[2]}.${parts[3]}'
            : (parts.length >= 3 ? parts[2] : key);
        final connectionId = parts.isNotEmpty ? parts[0] : '';
        final databaseName = parts.length >= 2 ? parts[1] : '';

        final server = provider.connection.savedConnections.firstWhere(
          (s) => s.id == connectionId,
          orElse: () => DbServer(id: '', name: '', host: '', port: 0),
        );
        final connectionLabel = server.name.isNotEmpty
            ? '${server.name} · '
            : '';

        return TreeItem(
          level: 1,
          icon: LucideIcons.table2,
          iconColor: context.themeColors.accentBlue,
          label: '$connectionLabel$tableName',
          showArrow: false,
          trailing: InkWell(
            onTap: () => provider.sidebar.toggleFavoriteTable(key),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: Icon(
              LucideIcons.star,
              size: 14,
              color: context.themeColors.warning,
            ),
          ),
          onTap: () {
            provider.sidebar.selectConnection(connectionId);
            provider.sidebar.selectDatabase(databaseName);
            _switchAndOpenTableQuery(
              context,
              provider,
              connectionId,
              databaseName,
              tableName,
            );
          },
        );
      }).toList(),
    );
  }

  Widget? _buildRecentSection(BuildContext context, AppProvider provider) {
    final entries = provider.recentTables.entries;
    if (entries.isEmpty) return null;

    final displayEntries = entries.take(5).toList();
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesignSystem.space1),
      child: SidebarSection(
        icon: LucideIcons.clock,
        iconColor: AppDesignSystem.accentPrimary,
        label: l10n.recentTables,
        count: displayEntries.length,
        trailing: InkWell(
          onTap: () => provider.recentTables.clear(),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Padding(
            padding: const EdgeInsets.all(AppDesignSystem.space0_5),
            child: Icon(
              LucideIcons.eraser,
              size: 13,
              color: context.themeColors.textMuted,
            ),
          ),
        ),
        children: displayEntries.map((entry) {
          final server = provider.connection.savedConnections.firstWhere(
            (s) => s.id == entry.connectionId,
            orElse: () => DbServer(id: '', name: '', host: '', port: 0),
          );
          final connLabel = server.name.isNotEmpty
              ? server.name
              : entry.connectionId;
          return InkWell(
            onTap: () {
              provider.sidebar.selectConnection(entry.connectionId);
              provider.sidebar.selectDatabase(entry.databaseName);
              _switchAndOpenTableQuery(
                context,
                provider,
                entry.connectionId,
                entry.databaseName,
                entry.tableName,
              );
            },
            child: Container(
              height: 28,
              padding: const EdgeInsets.only(
                left: AppDesignSystem.space3 * 2 + 16 + AppDesignSystem.space2,
                right: AppDesignSystem.space2,
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.table2,
                    size: 12,
                    color: AppDesignSystem.accentPrimary,
                  ),
                  const SizedBox(width: AppDesignSystem.space1_5),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                          height: 1.3,
                        ),
                        children: [
                          TextSpan(
                            text: connLabel,
                            style: TextStyle(color: colors.textMuted),
                          ),
                          TextSpan(
                            text: ' · ${entry.tableName}',
                            style: TextStyle(color: colors.textPrimary),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }


  /// Display server-side search results as tree nodes under a connection.
  List<Widget> _buildSearchResults(
    BuildContext context,
    String connectionId,
    String searchQuery,
    List<Map<String, String>> results,
  ) {
    if (results.isEmpty) return [];
    final colors = context.themeColors;
    return [
      TreeItem(
        level: 2,
        icon: LucideIcons.search,
        iconColor: context.themeColors.accentBlue,
        label: 'Search Results (${results.length})',
        showArrow: false,
        isExpanded: false,
        onTap: () {},
      ),
      ...results.map((r) {
        final schemaName = r['schemaName'] ?? '';
        final objectName = r['objectName'] ?? '';
        final objectType = r['objectType'] ?? 'table';
        final icon = objectType == 'view'
            ? LucideIcons.eye
            : LucideIcons.table2;
        final label = schemaName.isNotEmpty
            ? '$schemaName.$objectName'
            : objectName;
        return TreeItem(
          level: 3,
          icon: icon,
          iconColor: colors.textSecondary,
          iconSize: 12,
          label: label,
          showArrow: false,
          onTap: () {},
          onDoubleTap: () {
            final provider = context.read<AppProvider>();
            final qualified = schemaName.isNotEmpty
                ? '$schemaName.$objectName'
                : objectName;
            // 双击 → query 编辑器（预填默认浏览查询，不自动执行）；
            // data 模式仅右键「浏览数据」进入
            provider.openTableQueryTab(connectionId, '', qualified);
          },
        );
      }),
    ];
  }

  /// Filter databases by search query. When search is non-empty, only show databases
  /// whose name matches or that contain matching tables/views.
  List<String> _filterDatabasesForSearch(
    List<String> allDatabases,
    AppProvider provider,
    String connectionId,
    String searchQuery,
  ) {
    if (searchQuery.isEmpty) return allDatabases;
    final sq = searchQuery.toLowerCase();
    return allDatabases.where((db) {
      if (db.toLowerCase().contains(sq)) return true;
      final cached = provider.getCachedDatabase(connectionId, db);
      if (cached != null) {
        if (cached.tables.any((t) => t.name.toLowerCase().contains(sq)))
          return true;
        if (cached.views.any((v) => v.toLowerCase().contains(sq))) return true;
        if (cached.procedures.any((p) => p.toLowerCase().contains(sq)))
          return true;
        // T010 — schema-aware filter: check schema names and children
        for (final schema in cached.schemas) {
          if (schema.name.toLowerCase().contains(sq)) return true;
          if (schema.tables.any((t) => t.name.toLowerCase().contains(sq)))
            return true;
          if (schema.views.any((v) => v.toLowerCase().contains(sq)))
            return true;
          if (schema.functions.any((f) => f.toLowerCase().contains(sq)))
            return true;
          if (schema.procedures.any((p) => p.toLowerCase().contains(sq)))
            return true;
        }
      }
      // If DB cache is not loaded yet, keep it in case it matches
      return true;
    }).toList();
  }

  /// C22-1 单实例树根：当前连接一行（类型图标 + 名称 + 状态点，右键 =
  /// 完整连接管理菜单）+ 展开区（保存查询/库列表/插件全局节点）。
  /// 原「连接卡片容器 + 品牌色左边条」随多连接列表一并移除（原型形态）。
  Widget _buildConnectionNode(
    BuildContext context,
    AppProvider provider,
    DbServer server,
    String searchQuery,
  ) {
    final isConnected = provider.isConnectionConnected(server.id);
    final isActive =
        rightClickedNodeKey == 'conn:${server.id}' ||
        selectedNodeKey == 'conn:${server.id}';
    final isConnecting = provider.isConnectionConnecting(server.id);
    var isExpanded = expandedItems.contains(server.id) && isConnected;
    final connectionDatabases = provider.getConnectionDatabases(server.id);

    if (searchQuery.isNotEmpty && isConnected) {
      final hasMatchingDatabase = connectionDatabases.any(
        (db) => db.toLowerCase().contains(searchQuery),
      );
      if (hasMatchingDatabase) {
        isExpanded = true;
      } else {
        final hasMatchingTable = connectionDatabases.any((dbName) {
          final db = provider.getCachedDatabase(server.id, dbName);
          if (db == null) return false;
          return db.tables.any(
                (t) => t.name.toLowerCase().contains(searchQuery),
              ) ||
              db.views.any((v) => v.toLowerCase().contains(searchQuery));
        });
        if (hasMatchingTable) {
          isExpanded = true;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 1,
          icon: server.type.typeIcon,
          iconColor: isConnected
              ? context.themeColors.brandColor(server.type)
              : context.themeColors.textSecondary,
          label: server.name,
          badge: server.type.displayName,
          isExpanded: isExpanded && isConnected,
          isSelected: isActive,
          isLoading: isConnecting,
          showArrow: isConnected,
          trailing: _buildConnectionStatusDots(
            context,
            server,
            isConnected,
            isConnected,
          ),
          onTap: () {
            if (isConnected) {
              onToggleExpand(server.id);
            } else {
              // Auto-expand is handled by sidebar_widget's ConnectionEstablished
              // stream listener. Connect and let the event-driven expand follow.
              _connectToServer(context, provider, server, () {});
            }
          },
          onDoubleTap: () {
            if (isConnected) {
              onToggleExpand(server.id);
            } else {
              // Same — auto-expand handled by ConnectionEstablished listener.
              _connectToServer(context, provider, server, () {});
            }
          },
          onContextMenu: (position) {
            onRightClickTargetChanged?.call('conn:${server.id}');
            _showConnectionContextMenu(
              context,
              provider,
              server,
              position,
            ).then((_) => onRightClickTargetChanged?.call(null));
          },
        ),
        if (isExpanded && isConnected)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDesignSystem.space4,
              0,
              AppDesignSystem.space1,
              AppDesignSystem.space2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Display server-side search results when filter is active
                if (searchQuery.isNotEmpty) ...[
                  ..._buildSearchResults(
                    context,
                    server.id,
                    searchQuery,
                    serverSearchResults[server.id] ?? [],
                  ),
                ],
                ..._buildConnectionTreeBody(
                  context,
                  provider,
                  server,
                  searchQuery,
                  connectionDatabases,
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 连接卡片展开区（C19 统一装配）：数据库列表层（连接级整树型不渲染）
  /// + 插件全局节点分缝（全类型；未迁移类型回退旧 dispatch，C20 SS）。
  List<Widget> _buildConnectionTreeBody(
    BuildContext context,
    AppProvider provider,
    DbServer server,
    String searchQuery,
    List<String> connectionDatabases,
  ) {
    final filteredDatabases = _filterDatabasesForSearch(
      connectionDatabases,
      provider,
      server.id,
      searchQuery,
    );
    return [
      // 连接级整树型（Redis 逻辑库列表 / SQLite ATTACH 扁平树）：整树经
      // buildGlobalTree 分缝渲染（插件恒接管），宿主不渲染列表层。
      if (!server.type.isConnectionLevelTree) ...[
        // 连接级已保存查询（实例树顶级节点）
        SavedQueriesSection(
          connectionId: server.id,
          searchQuery: searchQuery,
          expandedItems: expandedItems,
          selectedNodeKey: selectedNodeKey,
          rightClickedNodeKey: rightClickedNodeKey,
          onToggleExpand: onToggleExpand,
          onRightClickTargetChanged: onRightClickTargetChanged,
          onSelectNode: onSelectNode,
        ),
        ...filteredDatabases.map(
          (database) => _buildDatabaseNode(
            context,
            provider,
            server.id,
            database,
            searchQuery,
          ),
        ),
        // 分隔线
        buildDivider(context),
      ],
      // C15-C18 插件化全局节点：per-type 插件（mysql/pg/sqlite/redis/mongo/
      // doris/td）经 buildGlobalTree 首个非空树接管；未迁移类型走旧 dispatch
      // （C20 SS）。C16/C17 增补的载荷字段（searchQuery/databases/…）由
      // 各插件按需消费，未消费字段传实值无行为差异。
      ..._buildGlobalNodesForType(
        context,
        provider,
        server,
        searchQuery: searchQuery,
        databases: filteredDatabases,
        expandedDatabases: expandedDatabases,
        onToggleDatabase: onToggleDatabase,
        selectedNodeKey: selectedNodeKey,
        onSelectNode: onSelectNode,
      ),
    ];
  }

  Widget _buildConnectionStatusDots(
    BuildContext context,
    DbServer server,
    bool isConnected,
    bool isActive,
  ) {
    // T051 — Server connection health indicator (T2.2).
    // Placeholder until M3 health engine: shows 🟢 when connected to server.
    final serverConnected = context
        .watch<ServerConnectionProvider>()
        .isConnected;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (server.environment != null)
          Tooltip(
            message: server.environment!.displayName,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: server.environment!.badgeColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.themeColors.bgSecondary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        if (server.environment != null)
          const SizedBox(width: AppDesignSystem.space1_5),
        if (server.useSSL) ...[
          const SizedBox(width: AppDesignSystem.space1),
          Icon(LucideIcons.lock, size: 10, color: context.themeColors.success),
        ],
        // T051: 🟢 Server-connected indicator (placeholder until M3 health engine)
        if (serverConnected) ...[
          const SizedBox(width: AppDesignSystem.space1_5),
          Tooltip(
            message: 'Connected to DbMaster Server',
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: context.themeColors.success.withValues(alpha: 0.7),
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.themeColors.bgSecondary,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
        Tooltip(
          message: isActive
              ? AppLocalizations.of(context)!.connectionCurrent
              : isConnected
              ? AppLocalizations.of(context)!.connectionConnected
              : AppLocalizations.of(context)!.connectionDisconnect,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isActive
                  ? context.themeColors.success
                  : isConnected
                  ? context.themeColors.accentBlue
                  : context.themeColors.textMuted.withValues(alpha: 0.5),
              shape: BoxShape.circle,
              border: Border.all(
                color: context.themeColors.bgSecondary,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatabaseNode(
    BuildContext context,
    AppProvider provider,
    String connectionId,
    String databaseName,
    String searchQuery,
  ) {
    final key = '$connectionId:$databaseName';
    final isExpanded = expandedDatabases.contains(key);
    final isLoading = loadingDatabases.contains(key);
    final activeTab = provider.tab.activeTab;
    final isSelected =
        (activeTab?.connectionId == connectionId &&
            activeTab?.databaseName == databaseName) ||
        rightClickedNodeKey == 'db:$connectionId:$databaseName' ||
        selectedNodeKey == 'db:$connectionId:$databaseName';
    final db = provider.getCachedDatabase(connectionId, databaseName);
    final server = provider.connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('连接不存在'),
    );

    // If expanded from saved state but database schema not yet cached,
    // trigger lazy load (deferred to avoid side-effects during build).
    if (isExpanded &&
        db == null &&
        !isLoading &&
        server.type.hasDatabaseObjectLayer) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onLoadDatabaseInfo(connectionId, databaseName);
      });
    }

    final isSystem = _isSystemDatabase(databaseName);
    // 摘要徽章去晦涩化——只显示表数（本地化）；views/procedures 展开后由各自分组头显示计数
    final l10n = AppLocalizations.of(context)!;
    final summaryBadge = db != null && db.tables.isNotEmpty
        ? l10n.sidebarDbTableCount(db.tables.length)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: TreeIcons.database,
          iconColor: isSystem
              ? context.themeColors.textMuted
              : isSelected
              ? context.themeColors.accentBlue
              : context.themeColors.textSecondary,
          iconSize: 16,
          label: isSystem ? '[$databaseName]' : databaseName,
          badge: summaryBadge,
          isExpanded: isExpanded,
          isSelected: isSelected,
          isLoading: isLoading,
          showArrow: server.type.hasDatabaseObjectLayer,
          onTap: () {
            // 顺序执行（非并发）：PG 切库走 useDatabase 重连（关旧连接、开新连接），
            // 若 onLoadDatabaseInfo（含 useDatabase）与 _selectDatabase（含
            // switchToConnection 的 getDatabases 验证）并发，getDatabases 会命中
            // 正在关闭的旧连接 → switchToConnection 误判连接失活 → disconnect。
            // await 顺序化消除该竞态（MySQL 的 USE 无此问题，但顺序化对它无副作用）。
            () async {
              if (isExpanded &&
                  db == null &&
                  server.type.hasDatabaseObjectLayer) {
                await onLoadDatabaseInfo(connectionId, databaseName);
              } else {
                onToggleDatabase(key);
                if (!isExpanded) {
                  // 展开即重查（wrapper 带 forceRefresh）：外部新增/删除的
                  // 表、视图在下次展开时可见；失败时旧快照保留。
                  await onLoadDatabaseInfo(connectionId, databaseName);
                }
              }
              await _selectDatabase(
                context,
                provider,
                connectionId,
                databaseName,
              );
            }();
          },
          onDoubleTap: () {
            _selectDatabase(context, provider, connectionId, databaseName).then(
              (_) {
                provider.openQueryTab(connectionId, databaseName);
              },
            );
          },
          onContextMenu: (position) {
            onRightClickTargetChanged?.call('db:$connectionId:$databaseName');
            _showDatabaseContextMenu(
              context,
              provider,
              server.id,
              databaseName,
              position,
            ).then((_) => onRightClickTargetChanged?.call(null));
          },
        ),
        if (isExpanded && server.type.hasDatabaseObjectLayer)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: AppDesignSystem.curveDefault,
            child: db != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // C19 分缝反转后插件树是唯一路径：per-type 插件
                      // （PG/Mongo/TD/SS）优先，core 泛 SQL 共享树殿后兜底
                      // （MY/Doris/CH）。
                      ...?_buildPluginDatabaseTree(
                        context,
                        provider,
                        server,
                        connectionId,
                        databaseName,
                        db,
                        searchQuery,
                      ),
                    ],
                  )
                : Padding(
                    padding: EdgeInsets.only(left: _schemaNodeIndent(3)),
                    child: const SizedBox(
                      height: 20,
                      child: Center(
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }

  /// 树装配序（C19 反转）：per-type 插件按注册序在前、core 殿后。注册表
  /// 注册序为 core 先（能力菜单合并依赖「per-type 同 id 项覆盖 core」的
  /// 后者覆盖语义），故仅树装配两处分缝处反转，注册表/能力菜单装配不动。
  /// 语义：特定优先于通用——per-type 库级树（PG/Mongo/TD）非空即接管，
  /// core 泛 SQL 共享树只做兜底；全局树 core 恒空，反转对现网零行为变化。
  static List<SidebarPlugin> _treeAssemblyOrder(DatabaseType type) {
    final plugins = defaultPluginRegistry.sidebarPluginsFor(type);
    return [
      ...plugins.where(
        (p) => p.descriptor.source != PluginSource.core,
      ),
      ...plugins.where((p) => p.descriptor.source == PluginSource.core),
    ];
  }

  /// C15 插件全局节点分缝：按 [_treeAssemblyOrder] 序询问
  /// `buildGlobalTree`，首个提供非空树的插件接管整段（mysql/pg/sqlite/
  /// redis/mongo/doris/td/ss 全部迁入；core 全局树恒空）。插件树为空且
  /// 无 per-type 插件的类型（clickhouse）落空列表——CH 无 server 级节点
  /// 是 C18 复核裁定（零专属 UI）。
  List<Widget> _buildGlobalNodesForType(
    BuildContext context,
    AppProvider provider,
    DbServer server, {
    String searchQuery = '',
    List<String> databases = const [],
    Set<String> expandedDatabases = const {},
    Function(String)? onToggleDatabase,
    String? selectedNodeKey,
    ValueChanged<String>? onSelectNode,
  }) {
    for (final plugin in _treeAssemblyOrder(server.type)) {
      final tree = plugin.buildGlobalTree(
        context,
        SidebarTreeContext(
          provider: provider,
          connectionId: server.id,
          expandedItems: expandedItems,
          onToggleExpand: onToggleExpand,
          // C16：SQLite 整树连接级，需搜索词与表级展开态（MySQL/PG 不消费）
          searchQuery: searchQuery,
          expandedTables: expandedTables,
          onToggleTable: onToggleTable,
          // C17：Redis 整树连接级，需库列表/库级展开/key 样本选中态
          databases: databases,
          expandedDatabases: expandedDatabases,
          onToggleDatabase: onToggleDatabase ?? (_) {},
          selectedNodeKey: selectedNodeKey,
          onSelectNode: onSelectNode,
        ),
      );
      if (tree.isNotEmpty) return tree;
    }
    return const [];
  }

  /// C14/C15 插件库级树分缝实现（**C19 反转后为唯一路径**）：per-type
  /// 插件先、core 殿后（注册表注册序为 core 先——能力菜单合并依赖
  /// 「per-type 同 id 项覆盖 core」，故仅在此树装配处反转遍历序），按序
  /// 询问 `buildDatabaseTree`（宿主全量载荷 + 菜单路由透传），首个提供
  /// 非空树的插件接管；per-type 恒空类型（MySQL/Doris/CH）落 core 泛 SQL
  /// 共享树，SS 落宿主 legacy 分支（C20 迁）。
  List<Widget>? _buildPluginDatabaseTree(
    BuildContext context,
    AppProvider provider,
    DbServer server,
    String connectionId,
    String databaseName,
    Database db,
    String searchQuery,
  ) {
    for (final plugin in _treeAssemblyOrder(server.type)) {
      final tree = plugin.buildDatabaseTree(
        context,
        SidebarDatabaseTreeContext(
          provider: provider,
          connectionId: connectionId,
          server: server,
          databaseName: databaseName,
          db: db,
          searchQuery: searchQuery,
          expandedItems: expandedItems,
          onToggleExpand: onToggleExpand,
          expandedTables: expandedTables,
          onToggleTable: onToggleTable,
          loadedTableSchemas: loadedTableSchemas,
          loadedTableForeignKeys: loadedTableForeignKeys,
          loadingTableSchemas: loadingTableSchemas,
          tableRowCounts: tableRowCounts,
          onLoadTableRowCounts: onLoadTableRowCounts,
          onLoadTableSchema: onLoadTableSchema,
          rightClickedNodeKey: rightClickedNodeKey,
          onRightClickTargetChanged: onRightClickTargetChanged,
          selectedNodeKey: selectedNodeKey,
          onSelectNode: onSelectNode,
          onShowTableMenu: (ctx, tableName, pos) => _showTableMenu(
            ctx,
            provider,
            server,
            connectionId,
            databaseName,
            tableName,
            pos,
          ),
          onShowColumnMenu: (ctx, schema, col, pos) =>
              _showColumnMenu(ctx, provider, schema, col, pos),
          onShowIndexMenu: (idx, schema, tableName, columns, pos) =>
              _showIndexMenu(
                context,
                provider,
                connectionId,
                databaseName,
                schema,
                tableName,
                columns,
                idx,
                pos,
              ),
          onShowFkMenu: (fk, pos) => _showFkMenu(context, provider, fk, pos),
          onShowViewMenu: (name, pos, isMaterializedView) => _showViewMenu(
            context,
            provider,
            connectionId,
            databaseName,
            name,
            pos,
            isMaterializedView: isMaterializedView,
          ),
          onShowProcedureMenu: (name, pos, isFunction) => _showProcedureMenu(
            context,
            provider,
            connectionId,
            databaseName,
            name,
            pos,
            isFunction: isFunction,
          ),
          onInsertName: (name) => _insertSchemaName(context, provider, name),
          // offerCreateTable/categoryType 由消费方插件按分类语义传参
          // （泛 SQL 共享树 tables 头 = true / views 'view' / MV
          // 'materialized_view'；per-type schema 树 = false/null）。
          onShowCategoryMenu: (pos, offerCreateTable, categoryType) =>
              _showCategoryMenu(
                context,
                provider,
                connectionId,
                databaseName,
                pos,
                offerCreateTable: offerCreateTable,
                categoryType: categoryType,
              ),
        ),
      );
      if (tree.isNotEmpty) return tree;
    }
    return null;
  }

  static const _systemDatabases = {
    'information_schema',
    'mysql',
    'performance_schema',
    'sys',
    'pg_catalog',
    'pg_toast',
    'pg_temp',
    'template0',
    'template1',
  };

  bool _isSystemDatabase(String dbName) =>
      _systemDatabases.contains(dbName.toLowerCase());

  // ========== Schema Node Indentation ==========

  /// Calculate the left indent for non-TreeItem schema detail nodes
  /// (group headers, columns, indexes, foreign keys) at a given [level].
  ///
  /// Produces the same label-start position as [TreeItem] would at that level,
  /// matching: leftPadding + connectors + arrowSection + iconSize + iconGap.
  static double _schemaNodeIndent(int level) {
    const leftPad = AppDesignSystem.space3; // TreeItem uses space3 for level≥3
    const arrowSection = 14.0 + AppDesignSystem.space1; // arrow width + gap
    const iconSize = 14.0; // TreeItem icon size for level≥3
    const iconGap = AppDesignSystem.space2;
    final connectors = (level - 1) * AppDesignSystem.treeNodeIndent;
    return leftPad + connectors + arrowSection + iconSize + iconGap;
  }

  // _groupHeader/_colNode/_idxNode/_fkNode 已移除——列/索引/FK 叶子改由
  // tree_utils.buildInteractiveTableSchemaLeaves 统一生成（扁平列 + 交互式）。
  // _schemaNodeIndent 仍保留（加载占位缩进仍用）。

  // ========== Table Context Menu (per-DB-type) ==========

  void _openBrowseTable(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String table,
  ) {
    // spec 041 US2: 浏览表数据走 openBrowseDataTab（隐 editor+FilterBar+自动执行）
    provider.openBrowseDataTab(cid, db, table);
    // 记录最近访问
    provider.recentTables.recordTableAccess(
      connectionId: cid,
      databaseName: db,
      tableName: table,
    );
  }

  Future<void> _showTableMenu(
    BuildContext context,
    AppProvider provider,
    DbServer server,
    String cid,
    String db,
    String table,
    Offset pos,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final dt = server.type;
    final items = <ContextMenuItem>[
      ContextMenuItem(
        id: 'browse',
        label: l10n.browseData,
        icon: LucideIcons.table,
        onTap: () => _openBrowseTable(context, provider, cid, db, table),
      ),
    ];

    // Create Table — all SQL databases (not schema-less)
    if (!dt.isSchemaLess) {
      items.add(
        ContextMenuItem(
          id: 'create_table',
          label: l10n.createNewTable,
          icon: LucideIcons.plus,
          onTap: () => _doCreateTable(context, provider, cid, db),
        ),
      );
    }

    // Edit Table — only column-editable SQL databases
    if (dt.supportsColumnEdit) {
      items.add(
        ContextMenuItem(
          id: 'edit',
          label: l10n.editTable,
          icon: LucideIcons.pencil,
          onTap: () => _doEditTable(context, provider, cid, db, table),
        ),
      );
      items.add(
        ContextMenuItem(
          id: 'properties',
          label: l10n.properties,
          icon: LucideIcons.info,
          onTap: () => _doTableProperties(context, cid, db, table),
        ),
      );
      // U17：查看 DDL 直达（此前要 右键 → Properties → CREATE Statement
      // tab 三步）。CREATE Statement tab 在有外键支持的库是第 4 个、否则
      // 第 3 个。
      items.add(
        ContextMenuItem(
          id: 'view_ddl',
          label: l10n.viewTableDdl,
          icon: LucideIcons.code,
          onTap: () => _doTableProperties(
            context,
            cid,
            db,
            table,
            initialTabIndex: dt.supportsForeignKeys ? 3 : 2,
          ),
        ),
      );
    }

    // Data Sync（io.dataSync 位：MySQL/Doris）
    if (CapabilityTable.has(dt, 'io.dataSync')) {
      items.add(
        ContextMenuItem(
          id: 'data_sync',
          label: l10n.dataSync,
          icon: LucideIcons.refreshCw,
          onTap: () => _doDataSync(context, cid, db, table),
        ),
      );
    }

    // Maintenance commands — per-database granular capability
    if (dt.supportsAnalyzeTable ||
        dt.supportsOptimizeTable ||
        dt.supportsCheckTable) {
      items.add(const ContextMenuItem.divider());
      if (dt.supportsAnalyzeTable) {
        items.add(
          ContextMenuItem(
            id: 'analyze_table',
            label: l10n.analyzeTable,
            icon: LucideIcons.chartLine,
            onTap: () => _doMaintenance(
              context,
              provider,
              cid,
              db,
              table,
              TableMaintenanceCommand.analyze,
            ),
          ),
        );
      }
      if (dt.supportsOptimizeTable) {
        items.add(
          ContextMenuItem(
            id: 'optimize_table',
            label: l10n.optimizeTable,
            icon: LucideIcons.database,
            onTap: () => _doMaintenance(
              context,
              provider,
              cid,
              db,
              table,
              TableMaintenanceCommand.optimize,
            ),
          ),
        );
      }
      if (dt.supportsCheckTable) {
        items.add(
          ContextMenuItem(
            id: 'check_table',
            label: l10n.checkTable,
            icon: LucideIcons.clipboardCheck,
            onTap: () => _doMaintenance(
              context,
              provider,
              cid,
              db,
              table,
              TableMaintenanceCommand.check,
            ),
          ),
        );
      }
      items.add(const ContextMenuItem.divider());
    }

    // AI analysis（ai.analyze 位：MySQL/Doris MVP）
    if (CapabilityTable.has(dt, 'ai.analyze')) {
      items.add(
        ContextMenuItem(
          id: 'ai_analyze_table',
          label: l10n.aiAnalyzeTable,
          icon: LucideIcons.wandSparkles,
          onTap: () => _doAiAnalyzeTreeNode(
            context,
            provider,
            AiTreeNodeType.table,
            cid,
            db,
            table,
          ),
        ),
      );
    }

    // T018 — Engine Status（engine.status 位：MySQL 专有，非 Doris）
    if (CapabilityTable.has(dt, 'engine.status')) {
      items.add(
        ContextMenuItem(
          id: 'engine_status',
          label: l10n.engineStatusTitle,
          icon: LucideIcons.database,
          onTap: () => MysqlEngineStatusDialog.show(context, cid),
        ),
      );
    }

    // Rename — supported databases (SQL + Redis)
    if (dt.supportsRenameTable) {
      items.add(
        ContextMenuItem(
          id: 'rename',
          label: l10n.rename,
          icon: LucideIcons.pencilLine,
          onTap: () => _doRenameTable(context, provider, cid, db, table),
        ),
      );
    }

    // T018/FR-006 — Truncate is destructive and grouped with Drop at the
    // menu bottom behind a single divider (matches Drop's danger treatment).
    // （redis 特例为死分支：本菜单仅 SQL 类树透传，Redis 树菜单在插件内。）
    final hasTruncate = !dt.isSchemaLess;
    final hasDrop = !dt.isSchemaLess;
    if (hasTruncate || hasDrop) {
      items.add(const ContextMenuItem.divider());
      if (hasTruncate) {
        items.add(
          ContextMenuItem(
            id: 'truncate',
            label: l10n.truncate,
            icon: LucideIcons.eraser,
            isDestructive: true,
            onTap: () => _doTruncateTable(context, provider, cid, db, table),
          ),
        );
      }
      if (hasDrop) {
        items.add(
          ContextMenuItem(
            id: 'drop',
            label: l10n.dropTable,
            icon: LucideIcons.trash2,
            isDestructive: true,
            onTap: () => _confirmDropTable(context, provider, cid, db, table),
          ),
        );
      }
    }

    await ContextMenuUtils.show(context: context, position: pos, items: items);
  }

  // 列/索引/FK 双击或右键"插入" → 把名字插入当前活动查询编辑器
  void _insertSchemaName(
    BuildContext context,
    AppProvider provider,
    String name,
  ) {
    if (provider.tab.activeTab == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.sidebarOpenEditorFirst),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    provider.insertIntoActiveEditor?.call(name);
  }

  // 列右键菜单：插入到编辑器 / 复制列名 / 复制类型 / 复制全部列名
  Future<void> _showColumnMenu(
    BuildContext context,
    AppProvider provider,
    DbTable schema,
    DbColumn col,
    Offset pos,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await ContextMenuUtils.show(
      context: context,
      position: pos,
      items: [
        ContextMenuItem(
          id: 'insert',
          label: l10n.sidebarInsertIntoEditor,
          icon: LucideIcons.logIn,
          onTap: () => _insertSchemaName(context, provider, col.name),
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          id: 'copyName',
          label: l10n.sidebarCopyColumnName,
          icon: LucideIcons.copy,
          onTap: () => Clipboard.setData(ClipboardData(text: col.name)),
        ),
        ContextMenuItem(
          id: 'copyType',
          label: l10n.sidebarCopyColumnType,
          icon: LucideIcons.braces,
          onTap: () => Clipboard.setData(ClipboardData(text: col.type)),
        ),
        ContextMenuItem(
          id: 'copyAll',
          label: l10n.sidebarCopyAllColumnNames,
          icon: LucideIcons.copy,
          onTap: () => Clipboard.setData(
            ClipboardData(text: schema.columns.map((c) => c.name).join(', ')),
          ),
        ),
      ],
    );
  }

  // T029/FR-012 — Index leaf context menu (mirrors column-leaf treatment,
  // adds working destructive Drop Index via provider.dropIndex). The onIndexMenu
  // plumbing already existed in buildInteractiveTableSchemaLeaves — only needed
  // a handler + call-site wiring.
  Future<void> _showIndexMenu(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String schema,
    String table,
    List<DbColumn> columns,
    DbIndex idx,
    Offset pos,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final server = provider.connection.getServerById(cid);
    final isReadOnly = server?.readOnly ?? false;
    await ContextMenuUtils.show(
      context: context,
      position: pos,
      items: [
        ContextMenuItem(
          id: 'copyName',
          label: l10n.sidebarCopyIndexName,
          icon: LucideIcons.copy,
          onTap: () => Clipboard.setData(ClipboardData(text: idx.name)),
        ),
        ContextMenuItem(
          id: 'insert',
          label: l10n.sidebarInsertIntoEditor,
          icon: LucideIcons.logIn,
          onTap: () => _insertSchemaName(context, provider, idx.name),
        ),
        ContextMenuItem(
          id: 'editIndex',
          label: l10n.editIndex,
          icon: LucideIcons.pencil,
          onTap: () => showDialog(
            context: context,
            builder: (_) => EditIndexDialog(
              dbName: db,
              tableName: table,
              index: idx,
              columns: columns,
              connectionId: cid, // T063 — dialect resolution
              schema: schema, // T063 — schema-qualified drop/create
            ),
          ),
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          id: 'dropIndex',
          label: l10n.commonDelete,
          icon: LucideIcons.trash2,
          isDestructive: true,
          enabled: !isReadOnly,
          disabledReason: isReadOnly ? l10n.sidebarReadOnlyConnection : null,
          onTap: () => _confirmDropIndex(
            context,
            provider,
            cid,
            db,
            schema,
            table,
            idx.name,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDropIndex(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String schema,
    String table,
    String indexName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.editIndex),
        content: Text('$indexName · $table'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // T063 — resolve dialect + compose schema-qualified drop args so
    // non-default-schema indexes resolve (PG qualifies index, SQL Server table).
    final server = provider.connection.getServerById(cid);
    final type = server?.type;
    final names = IndexDialectNames.dropArgs(type, schema, table, indexName);
    try {
      final dropped = await provider.dropIndex(db, names.table, names.index);
      if (dropped && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.commonDelete)));
      } else if (!dropped && context.mounted) {
        // T039b — provider.dropIndex returns false (not throw) when the
        // adapter swallows a failure — e.g. PG/SQL Server index in a non-default
        // schema that the adapter's bare-name DDL can't resolve. Surface it
        // instead of silently no-op'ing (Constitution: errors not swallowed).
        // NOTE: the schema-qualification root cause is tracked as a backend
        // follow-up (see postgresql_adapter.dropIndex / sqlserver dropIndex).
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.dropIndexFailed(indexName),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.dropIndexFailed(e.toString()),
      );
    }
  }

  // T030/FR-012 — Foreign Key leaf context menu. Copy Name + Insert.
  // NOTE: destructive "Drop FK" is intentionally omitted for now — it needs a
  // cross-dialect provider.dropForeignKey (SQLite cannot DROP CONSTRAINT at all;
  // MySQL/PG/SQLServer need per-dialect DDL). Tracked as a backend follow-up.
  Future<void> _showFkMenu(
    BuildContext context,
    AppProvider provider,
    ForeignKey fk,
    Offset pos,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    await ContextMenuUtils.show(
      context: context,
      position: pos,
      items: [
        ContextMenuItem(
          id: 'copyName',
          label: l10n.sidebarCopyForeignKeyName,
          icon: LucideIcons.copy,
          onTap: () => Clipboard.setData(ClipboardData(text: fk.name)),
        ),
        ContextMenuItem(
          id: 'insert',
          label: l10n.sidebarInsertIntoEditor,
          icon: LucideIcons.logIn,
          onTap: () => _insertSchemaName(context, provider, fk.name),
        ),
      ],
    );
  }

  // T024/FR-008 — View leaf context menu (previously menu-less).
  // Browse/Call/Copy use existing primitives; Drop composes a DDL statement via
  // executeSqlScript (auto-refreshes). View-definition intentionally omitted:
  // no cross-dialect getViewDefinition facade exists yet.
  Future<void> _showViewMenu(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String viewName,
    Offset pos, {
    bool isMaterializedView = false,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final server = provider.connection.getServerById(cid);
    final isReadOnly = server?.readOnly ?? false;
    // T039b — resolve dialect for DDL escaping; null server (disconnected)
    // falls back to MySQL backticks (legacy behaviour, never crashes).
    final type = server?.type;
    await ContextMenuUtils.show(
      context: context,
      position: pos,
      items: [
        ContextMenuItem(
          id: 'browse',
          label: l10n.sidebarBrowseData,
          icon: LucideIcons.table,
          onTap: () {
            // spec 041 US2: 浏览视图走 openBrowseDataTab
            provider.openBrowseDataTab(cid, db, viewName, isView: true);
          },
        ),
        ContextMenuItem(
          id: 'copyName',
          label: l10n.sidebarCopyName,
          icon: LucideIcons.copy,
          onTap: () => Clipboard.setData(ClipboardData(text: viewName)),
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          id: 'drop',
          label: l10n.commonDelete,
          icon: LucideIcons.trash2,
          isDestructive: true,
          enabled: !isReadOnly,
          disabledReason: isReadOnly ? l10n.sidebarReadOnlyConnection : null,
          onTap: () => _confirmDropView(
            context,
            provider,
            type,
            viewName,
            isMaterializedView: isMaterializedView,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDropView(
    BuildContext context,
    AppProvider provider,
    DatabaseType? type,
    String viewName, {
    bool isMaterializedView = false,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(l10n.sidebarDropViewConfirm(viewName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // T039b — dialect-aware DROP VIEW (was MySQL-only backticks,
      // which broke on PostgreSQL/SQL Server). IF EXISTS is supported by all
      // three (SQL Server 2016+). Materialized views use DROP MATERIALIZED VIEW.
      final dropKind = isMaterializedView ? 'MATERIALIZED VIEW' : 'VIEW';
      await provider.executeSqlScript(
        'DROP $dropKind IF EXISTS ${SqlEscapeUtils.escapeQualifiedIdentifier(viewName, type)}',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.sidebarDropViewFailed(e.toString()),
      );
    }
  }

  // T025/FR-009 — Procedure leaf context menu (previously menu-less).
  Future<void> _showProcedureMenu(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String procName,
    Offset pos, {
    bool isFunction = false,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final server = provider.connection.getServerById(cid);
    final isReadOnly = server?.readOnly ?? false;
    // T039b — resolve dialect for invoke verb + DDL escaping.
    final type = server?.type;
    await ContextMenuUtils.show(
      context: context,
      position: pos,
      items: [
        ContextMenuItem(
          id: 'call',
          label: l10n.callProcedure(procName),
          icon: LucideIcons.play,
          // T039b — dialect-aware invoke: MySQL/PostgreSQL use CALL,
          // SQL Server uses EXEC. Identifier escaped per server.type.
          // Functions (folded into db.procedures for MySQL/Doris) can't be
          // CALLed — use SELECT name() instead.
          onTap: () {
            final esc = SqlEscapeUtils.escapeQualifiedIdentifier(
              procName,
              type,
            );
            final invoke = isFunction
                ? 'SELECT $esc();'
                : '${type?.procedureCallVerb ?? 'CALL'} $esc;';
            provider.openQueryTab(cid, db, sql: invoke);
          },
        ),
        ContextMenuItem(
          id: 'copyName',
          label: l10n.sidebarCopyName,
          icon: LucideIcons.copy,
          onTap: () => Clipboard.setData(ClipboardData(text: procName)),
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          id: 'drop',
          label: l10n.commonDelete,
          icon: LucideIcons.trash2,
          isDestructive: true,
          enabled: !isReadOnly,
          disabledReason: isReadOnly ? l10n.sidebarReadOnlyConnection : null,
          onTap: () => _confirmDropProcedure(context, provider, type, procName),
        ),
      ],
    );
  }

  Future<void> _confirmDropProcedure(
    BuildContext context,
    AppProvider provider,
    DatabaseType? type,
    String procName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(procName),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      // T039b — dialect-aware DROP PROCEDURE (was MySQL-only backticks).
      // Routines may be PROCEDURE or FUNCTION; DROP PROCEDURE covers the common
      // case (MySQL/Doris fold functions into db.procedures). IF EXISTS is
      // supported by MySQL/PG/SQL Server 2016+.
      await provider.executeSqlScript(
        'DROP PROCEDURE IF EXISTS ${SqlEscapeUtils.escapeQualifiedIdentifier(procName, type)}',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.sidebarDeleteFailed(e.toString()),
      );
    }
  }

  // T031-T035/FR-014 — Category folder header context menu (previously
  // menu-less). Offers Create Table (where a dialog exists) + a Refresh that
  // re-fetches the whole database object graph (no per-category refresh exists).
  Future<void> _showCategoryMenu(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    Offset pos, {
    bool offerCreateTable = false,
    String? categoryType,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    await ContextMenuUtils.show(
      context: context,
      position: pos,
      items: [
        if (offerCreateTable)
          ContextMenuItem(
            id: 'create_table',
            label: l10n.createNewTable,
            icon: LucideIcons.plus,
            onTap: () => _doCreateTable(context, provider, cid, db),
          ),
        if (categoryType == 'view')
          ContextMenuItem(
            id: 'create_view',
            label: l10n.sidebarCreateNewView,
            icon: LucideIcons.plus,
            onTap: () => _doCreateView(context, provider, cid, db),
          ),
        if (categoryType == 'materialized_view')
          ContextMenuItem(
            id: 'create_materialized_view',
            label: l10n.sidebarCreateNewMaterializedView,
            icon: LucideIcons.plus,
            onTap: () => _doCreateMaterializedView(context, provider, cid, db),
          ),
        ContextMenuItem(
          id: 'refresh',
          label: l10n.commonRefresh,
          icon: LucideIcons.refreshCw,
          onTap: () async {
            provider.invalidateDatabaseCache(cid, db);
            await provider.loadDatabaseInfo(cid, db, forceRefresh: true);
          },
        ),
      ],
    );
  }

  void _doCreateView(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
  ) {
    provider.openQueryTab(
      cid,
      db,
      sql: 'CREATE VIEW "new_view" AS\nSELECT * FROM "table_name";',
    );
  }

  void _doCreateMaterializedView(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
  ) {
    provider.openQueryTab(
      cid,
      db,
      sql:
          'CREATE MATERIALIZED VIEW "new_mv"\nAS\nSELECT column1, COUNT(*) AS cnt\nFROM "table_name"\nGROUP BY column1;',
    );
  }

  // ========== Table Action Handlers ==========

  void _doCreateTable(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
  ) {
    showDialog(
      context: context,
      builder: (_) => CreateTableDialog(dbName: db),
    );
  }

  Future<void> _doEditTable(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String table,
  ) async {
    // Load the latest schema before editing so the dialog shows real columns/indexes.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final columns = await provider.dbService.getTableColumns(
        table,
        databaseName: db,
      );
      final indexes = await provider.dbService.getTableIndexes(
        table,
        databaseName: db,
      );
      // 获取表注释以便 EditTableDialog 显示/修改
      String? comment;
      try {
        final adapter = provider.dbService.getAdapter(cid);
        if (adapter != null) {
          final result = await adapter.executeQuery(
            "SELECT TABLE_COMMENT FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = '${db.replaceAll("'", "''")}' AND TABLE_NAME = '${table.replaceAll("'", "''")}'",
          );
          if (result.rows.isNotEmpty) {
            final raw = result.rows.first['TABLE_COMMENT']?.toString() ?? '';
            comment = raw.isNotEmpty ? raw : null;
          }
        }
      } catch (_) {
        // 非关键路径，失败时 comment 保持 null
      }
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final tableModel = DbTable(
        name: table,
        columns: columns,
        indexes: indexes,
        comment: comment,
      );
      await showDialog(
        context: context,
        builder: (_) => EditTableDialog(dbName: db, table: tableModel),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.loadFailed(e),
        );
      }
    }
  }

  void _doTableProperties(
    BuildContext context,
    String cid,
    String db,
    String table, {
    int initialTabIndex = 0,
  }) {
    showDialog(
      context: context,
      builder: (_) => TablePropertiesDialog(
        tableName: table,
        dbName: db,
        connectionId: cid,
        initialTabIndex: initialTabIndex,
      ),
    );
  }

  Future<void> _doDataSync(
    BuildContext context,
    String cid,
    String db,
    String table,
  ) async {
    final appProvider = context.read<AppProvider>();
    if (!appProvider.tryDataSync(
      'data_sync_${DateTime.now().millisecondsSinceEpoch}',
    )) {
      return;
    }
    // open-core Phase B.2：Data Sync 对话框经 ProSyncUi SPI 注入
    // （OSS=NoOp，门禁已拦截，此处兜底 no-op）。
    if (context.mounted) {
      await context.read<ProSyncUi>().openDataSyncDialog(
        context,
        connectionId: cid,
        database: db,
        table: table,
      );
    }
  }

  Future<void> _doMaintenance(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String table,
    TableMaintenanceCommand command,
  ) async {
    if (!context.mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) =>
          ConfirmMaintenanceDialog(tableName: table, command: command),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final results = await provider.runTableMaintenance(
        db,
        table,
        command,
        connectionId: cid,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => TableMaintenanceResultDialog(
          tableName: table,
          command: command,
          sql: command.buildSql(db, table),
          results: results,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.maintenanceFailed(_labelForCommand(l10n, command), e.toString()),
        );
      }
    }
  }

  String _labelForCommand(
    AppLocalizations l10n,
    TableMaintenanceCommand command,
  ) {
    switch (command) {
      case TableMaintenanceCommand.analyze:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.optimize:
        return l10n.optimizeTable;
      case TableMaintenanceCommand.check:
        return l10n.checkTable;
      case TableMaintenanceCommand.vacuum:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.vacuumFull:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.pgAnalyze:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.reindex:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.reindexConcurrently:
        return l10n.analyzeTable;
      case TableMaintenanceCommand.cluster:
        return l10n.analyzeTable;
    }
  }

  Future<void> _doAiAnalyzeTreeNode(
    BuildContext context,
    AppProvider provider,
    AiTreeNodeType nodeType,
    String cid,
    String? db,
    String nodeName,
  ) async {
    if (!context.mounted) return;
    try {
      await provider.analyzeTreeNodeWithAi(
        AiTreeNodeContext(
          type: nodeType,
          connectionId: cid,
          databaseName: db,
          nodeName: nodeName,
        ),
        locale: LocaleProvider.codeOf(Localizations.localeOf(context)),
      );
    } catch (e) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.aiAnalyzeNodeFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _doRenameTable(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String table,
  ) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => RenameTableDialog(tableName: table),
    );
    if (newName != null && newName.isNotEmpty && newName != table) {
      try {
        await provider.renameTable(db, table, newName);
      } catch (e) {
        if (context.mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            // T061/FR-028 — operation-specific message (was sidebarExportFailed)
            AppLocalizations.of(context)!.renameFailed(e.toString()),
          );
        }
      }
    }
  }

  Future<void> _doTruncateTable(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String table,
  ) async {
    if (!context.mounted) return;
    final result = await showDialog<TruncateDialogResult>(
      context: context,
      builder: (_) => TruncateTableConfirmDialog(tableName: table),
    );
    if (result?.confirmed == true) {
      try {
        await provider.truncateTable(table, databaseName: db);
      } catch (e) {
        if (context.mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            // T061/FR-028 — operation-specific message (was sidebarExportFailed)
            AppLocalizations.of(context)!.truncateFailed(e.toString()),
          );
        }
      }
    }
  }

  Future<void> _confirmDropTable(
    BuildContext context,
    AppProvider provider,
    String cid,
    String db,
    String table,
  ) async {
    // T018 — use type-to-confirm dialog
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => DropTableConfirmDialog(tableName: table, dbName: db),
    );
    if (ok == true && context.mounted) {
      try {
        await provider.dropTable(db, table);
      } catch (e) {
        if (context.mounted)
          AppErrorHandler.showErrorSnackBar(
            context,
            // T061/FR-028 — operation-specific message (was sidebarExportFailed)
            AppLocalizations.of(context)!.dropTableFailed(e.toString()),
          );
      }
    }
  }
  // ========== TDengine 特有节点 ==========
  // C18 插件化：_buildTDengineNodes/_browseTDengineSuperTableData 与顶层
  // SuperTable 上下文菜单整体迁入 plugins/tdengine_sidebar_plugin.dart
  // （库级分缝见 _buildDatabaseNode 的 tdengine/mongodb 分支）。

  Future<void> _connectToServer(
    BuildContext context,
    AppProvider provider,
    DbServer server,
    VoidCallback onExpand,
  ) async {
    // 重入守卫：连接在途时不再弹密码框——取消弹窗不会中止在途连接，
    // 重复弹窗 + 不可中止的长链路是「取消后卡死」的入口（T29 走查）。
    if (provider.connection.isConnectionConnecting(server.id)) return;
    final serverWithPassword = await PasswordPromptDialog.ensurePassword(
      context,
      server,
    );
    if (serverWithPassword == null) return; // 用户取消

    final success = await provider.connectToServer(serverWithPassword);
    if (success && context.mounted) {
      // Auto-expand is now handled by the ConnectionEstablished stream
      // listener in sidebar_widget. This callback remains for caller compatibility.
      onExpand();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.connectedToServer(server.name),
          ),
          backgroundColor: context.themeColors.accentGreen,
        ),
      );
    } else if (!success && context.mounted) {
      AppErrorHandler.showErrorSnackBar(
        context,
        AppLocalizations.of(
          context,
        )!.connectionFailedWith(provider.errorMessage ?? 'unknown'),
      );
    }
  }

  Future<void> _selectDatabase(
    BuildContext context,
    AppProvider provider,
    String connectionId,
    String databaseName,
  ) async {
    await provider.switchToConnection(connectionId);
    await provider.changeDatabase(databaseName, connectionId: connectionId);
    // 树节点显式选库覆写 switchToConnection 内置的「默认第一个库」
    // tab 同步（工具栏库芯片与执行库跟随，2026-08-27 修复）；方向 A
    // （2026-09-04）：跟随式覆写——已绑定上下文的活跃 tab 不动。
    provider.followActiveTabDatabase(databaseName);
    provider.sidebar.selectConnection(connectionId);
    provider.sidebar.selectDatabase(databaseName);
  }

  Future<void> _switchAndOpenTableQuery(
    BuildContext context,
    AppProvider provider,
    String connectionId,
    String databaseName,
    String tableName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      // 如果连接已断开，先自动重连
      if (!provider.isConnectionConnected(connectionId)) {
        final server = provider.connection.savedConnections.firstWhere(
          (s) => s.id == connectionId,
          orElse: () => throw Exception('Connection not found'),
        );
        final serverWithPassword = await PasswordPromptDialog.ensurePassword(
          context,
          server,
        );
        if (serverWithPassword == null) return;
        final connected = await provider.connectToServer(serverWithPassword);
        if (!connected) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(
                    context,
                  )!.sidebarConnectFailed(server.name),
                ),
                backgroundColor: context.themeColors.accentRed,
              ),
            );
          }
          return;
        }
      }
      await provider.switchToConnection(connectionId);
      await provider.changeDatabase(databaseName, connectionId: connectionId);

      // 最近/收藏行点击 = 打开表 → query 编辑器（预填默认浏览查询，不自动执行）；
      // data 模式仅右键「浏览数据」进入
      await provider.openTableQueryTab(connectionId, databaseName, tableName);
      // 记录最近访问
      provider.recentTables.recordTableAccess(
        connectionId: connectionId,
        databaseName: databaseName,
        tableName: tableName,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.openTableDataFailed(e)),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _showConnectionContextMenu(
    BuildContext context,
    AppProvider provider,
    DbServer server,
    Offset position,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final isConnected = provider.isConnectionConnected(server.id);
    final isConnecting = provider.isConnectionConnecting(server.id);

    final items = <ContextMenuItem>[];
    if (!isConnected && !isConnecting) {
      items.add(
        ContextMenuItem(
          id: 'connect',
          label: l10n.connectionConnect,
          icon: LucideIcons.link,
          onTap: () =>
              _handleConnectionAction(context, provider, server, 'connect'),
        ),
      );
    }
    if (isConnecting) {
      items.add(
        ContextMenuItem(
          id: 'cancel_connect',
          label: l10n.cancelConnection,
          icon: LucideIcons.circleX,
          onTap: () => _handleConnectionAction(
            context,
            provider,
            server,
            'cancel_connect',
          ),
        ),
      );
    }
    if (isConnected) {
      items.add(
        ContextMenuItem(
          id: 'disconnect',
          label: l10n.connectionDisconnect,
          icon: LucideIcons.unlink,
          onTap: () =>
              _handleConnectionAction(context, provider, server, 'disconnect'),
        ),
      );
      items.add(
        ContextMenuItem(
          id: 'refresh',
          label: l10n.commonRefresh,
          icon: LucideIcons.refreshCw,
          onTap: () =>
              _handleConnectionAction(context, provider, server, 'refresh'),
        ),
      );
      // ddl.createDatabase 位（C19 收编原 {my,pg,do,td,ss} 字面量门控）
      if (CapabilityTable.has(server.type, 'ddl.createDatabase')) {
        items.add(
          ContextMenuItem(
            id: 'create_database',
            // T041/FR-016 — localized (was hardcoded 'Create Database')
            label: l10n.connectionCreateDatabase,
            icon: LucideIcons.folderPlus,
            onTap: () => _handleConnectionAction(
              context,
              provider,
              server,
              'create_database',
            ),
          ),
        );
      }
      // ai.analyze 位（MySQL/Doris MVP）
      if (CapabilityTable.has(server.type, 'ai.analyze')) {
        items.add(
          ContextMenuItem(
            id: 'ai_analyze_server',
            label: l10n.aiAnalyzeServer,
            icon: LucideIcons.wandSparkles,
            onTap: () => _doAiAnalyzeTreeNode(
              context,
              provider,
              AiTreeNodeType.connection,
              server.id,
              null,
              server.name,
            ),
          ),
        );
      }
    }
    items.addAll([
      ContextMenuItem(
        id: 'edit',
        label: l10n.connectionEditConnection,
        icon: LucideIcons.pencil,
        onTap: () => _handleConnectionAction(context, provider, server, 'edit'),
      ),
      ContextMenuItem(
        id: 'clone',
        label: l10n.connectionCloneConnection,
        icon: LucideIcons.copy,
        onTap: () =>
            _handleConnectionAction(context, provider, server, 'clone'),
      ),
      ContextMenuItem(
        id: 'export',
        label: l10n.exportThisConnection,
        icon: LucideIcons.fileUp,
        onTap: () {
          if (context.mounted) {
            ConnectionExportImportDialog.showExport(
              context,
              connections: [server],
            );
          }
        },
      ),
      if (isConnected)
        ContextMenuItem(
          id: 'toggle_readonly',
          // T041/FR-016 — localized (was hardcoded 'Disable/Enable Read-Only')
          label: server.readOnly
              ? l10n.connectionDisableReadOnly
              : l10n.connectionEnableReadOnly,
          icon: server.readOnly ? LucideIcons.lockOpen : LucideIcons.lock,
          onTap: () => _handleConnectionAction(
            context,
            provider,
            server,
            'toggle_readonly',
          ),
        ),
      if (provider.connectionGroups.isNotEmpty) ...[
        const ContextMenuItem.divider(),
        ...provider.connectionGroups.map(
          (group) => ContextMenuItem(
            id: 'move_to_${group.id}',
            // T041/FR-016 — localized (was hardcoded 'Move to ${group.name}')
            label: l10n.connectionMoveToGroup(group.name),
            icon: LucideIcons.folder,
            onTap: () => provider.moveConnectionToGroup(server.id, group.id),
          ),
        ),
        ContextMenuItem(
          id: 'move_to_none',
          // T041/FR-016 — localized (was hardcoded 'Remove from Group')
          label: l10n.connectionRemoveFromGroup,
          icon: LucideIcons.folderOpen,
          onTap: () => provider.moveConnectionToGroup(server.id, null),
        ),
      ],
      // T050/FR-021 — Collapse All moved BEFORE the destructive zone so
      // destructive Delete remains the menu's final item (previously Collapse All
      // was appended after Delete, violating "destructive = last item").
      if (onCollapseAll != null) ...[
        const ContextMenuItem.divider(),
        ContextMenuItem(
          id: 'collapse_all',
          label: l10n.connectionCollapseAll,
          icon: LucideIcons.chevronsDownUp,
          onTap: () => onCollapseAll!(),
        ),
      ],
      const ContextMenuItem.divider(),
      ContextMenuItem(
        id: 'delete',
        label: l10n.connectionDeleteConnectionTitle,
        icon: LucideIcons.trash2,
        isDestructive: true,
        onTap: () =>
            _handleConnectionAction(context, provider, server, 'delete'),
      ),
    ]);

    await ContextMenuUtils.show(
      context: context,
      position: position,
      items: items,
    );
  }

  void _handleConnectionAction(
    BuildContext context,
    AppProvider provider,
    DbServer server,
    String action,
  ) async {
    switch (action) {
      case 'connect':
        await _connectToServer(context, provider, server, () {});
        break;
      case 'cancel_connect':
        provider.cancelConnect(connectionId: server.id);
        break;
      case 'disconnect':
        await provider.disconnectConnection(connectionId: server.id);
        break;
      case 'refresh':
        // T015/FR-003 — refresh the right-clicked connection in place.
        // Previously this was a silent no-op when the right-clicked connection
        // was not the currently selected one (selectedConnectionId != server.id).
        await provider.refreshDatabases(connectionId: server.id);
        break;
      case 'edit':
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (_) => ConnectionDialog(existingServer: server),
          );
        }
        break;
      case 'clone':
        await provider.cloneConnection(server);
        break;
      case 'delete':
        _deleteConnection(context, provider, server);
        break;
      case 'create_database':
        _showCreateDatabaseDialog(context, provider);
        break;
      case 'toggle_readonly':
        final updatedServer = server.copyWith(readOnly: !server.readOnly);
        await provider.connection.saveConnection(updatedServer);
        break;
    }
  }

  Future<void> _showCreateDatabaseDialog(
    BuildContext context,
    AppProvider provider,
  ) async {
    await showDialog(
      context: context,
      // 传入当前连接的 DB 类型，让对话框按类型设置 charset/collation 默认值
      // （PG→UTF8/空；MySQL/Doris→utf8mb4；其它→空），避免把 MySQL 默认值透传给 PG。
      builder: (_) => CreateDatabaseDialog(
        databaseType: provider.connection.currentServer?.type,
      ),
    );
    if (context.mounted) {
      await provider.refreshDatabases();
    }
  }

  Future<void> _deleteConnection(
    BuildContext context,
    AppProvider provider,
    DbServer server,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text(
          l10n.deleteConnectionTitle,
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
        ),
        content: Text(
          l10n.deleteConnectionConfirm(server.name),
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.accentRed,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await provider.deleteConnection(server.id);
      } catch (e, stackTrace) {
        AppLogger.e(
          'SidebarTree',
          'Failed to delete connection: $e\n$stackTrace',
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.connDeleteConnectionFailed(e.toString())),
              backgroundColor: context.themeColors.accentRed,
            ),
          );
        }
      }
    }
  }

  Future<void> _showDatabaseContextMenu(
    BuildContext context,
    AppProvider provider,
    String connectionId,
    String dbName,
    Offset position,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final server = provider.connection.savedConnections.firstWhere(
      (s) => s.id == connectionId,
      orElse: () => throw Exception('Connection not found'),
    );
    final dbType = server.type;
    final isReadOnly = server.readOnly;

    final items = <ContextMenuItem>[];
    items.add(
      ContextMenuItem(
        id: 'select',
        label: l10n.selectDatabase,
        icon: LucideIcons.circleCheckBig,
        onTap: () => _handleDatabaseAction(
          context,
          provider,
          connectionId,
          dbName,
          'select',
        ),
      ),
    );
    items.add(
      ContextMenuItem(
        id: 'refresh',
        label: l10n.refresh,
        icon: LucideIcons.refreshCw,
        onTap: () => _handleDatabaseAction(
          context,
          provider,
          connectionId,
          dbName,
          'refresh',
        ),
      ),
    );
    // 「新建表」门控与动作路由同源（createTableMenuAction：null = 不提供；
    // PG/TD 有专属创建对话框，其余走通用 CreateTableDialog）
    final createTableAction = dbType.createTableMenuAction;
    if (createTableAction != null) {
      items.add(
        ContextMenuItem(
          id: createTableAction,
          label: createTableAction == 'create_supertable'
              ? 'Create SuperTable'
              : l10n.createNewTable,
          icon: LucideIcons.plus,
          onTap: () => _handleDatabaseAction(
            context,
            provider,
            connectionId,
            dbName,
            createTableAction,
          ),
        ),
      );
    }
    items.addAll([
      ContextMenuItem(
        id: 'properties',
        label: l10n.properties,
        icon: LucideIcons.info,
        onTap: () => _handleDatabaseAction(
          context,
          provider,
          connectionId,
          dbName,
          'properties',
        ),
      ),
      ContextMenuItem(
        id: 'export',
        label: l10n.exportStructure,
        icon: LucideIcons.download,
        onTap: () => _handleDatabaseAction(
          context,
          provider,
          connectionId,
          dbName,
          'export',
        ),
      ),
      ContextMenuItem(
        id: 'schema_diff',
        label: l10n.schemaDiffMenuItem,
        icon: LucideIcons.arrowRightLeft,
        onTap: () => _handleDatabaseAction(
          context,
          provider,
          connectionId,
          dbName,
          'schema_diff',
        ),
      ),
      // Phase E — Save Schema Snapshot context menu entry
      ContextMenuItem(
        id: 'save_snapshot',
        label: 'Save Schema Snapshot',
        icon: LucideIcons.camera,
        onTap: () => _handleDatabaseAction(
          context,
          provider,
          connectionId,
          dbName,
          'save_snapshot',
        ),
      ),
    ]);

    // ai.analyze 位（MySQL/Doris MVP）
    if (CapabilityTable.has(dbType, 'ai.analyze')) {
      items.add(
        ContextMenuItem(
          id: 'ai_analyze_database',
          label: l10n.aiAnalyzeDatabase,
          icon: LucideIcons.wandSparkles,
          onTap: () => _doAiAnalyzeTreeNode(
            context,
            provider,
            AiTreeNodeType.database,
            connectionId,
            dbName,
            dbName,
          ),
        ),
      );
    }

    items.addAll([
      const ContextMenuItem.divider(),
      ContextMenuItem(
        id: 'drop',
        label: l10n.dropDatabase,
        icon: LucideIcons.trash2,
        isDestructive: true,
        enabled: !isReadOnly,
        disabledReason: isReadOnly ? l10n.sidebarReadOnlyConnection : null,
        onTap: () => _handleDatabaseAction(
          context,
          provider,
          connectionId,
          dbName,
          'drop',
        ),
      ),
    ]);

    // T050/FR-021 — removed duplicate "Collapse All" from the database
    // menu. It now lives only on the connection menu (single canonical place).

    await ContextMenuUtils.show(
      context: context,
      position: position,
      items: items,
    );
  }

  void _handleDatabaseAction(
    BuildContext context,
    AppProvider provider,
    String connectionId,
    String dbName,
    String action,
  ) async {
    switch (action) {
      case 'select':
        await provider.switchToConnection(connectionId);
        provider.changeDatabase(dbName, connectionId: connectionId);
        // 显式选库覆写内置「默认第一个库」tab 同步（同 _selectDatabase，
        // 跟随式——已绑定 tab 不动，方向 A）。
        provider.followActiveTabDatabase(dbName);
        break;
      case 'refresh':
        provider.refreshDatabases();
        break;
      case 'create_table':
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => CreateTableDialog(dbName: dbName),
          );
        }
        break;
      case 'create_table_pg':
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => CreatePostgresTableDialog(dbName: dbName),
          );
        }
        break;
      case 'create_supertable':
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => CreateSuperTableDialog(dbName: dbName),
          );
        }
        break;
      case 'properties':
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (ctx) => DatabasePropertiesDialog(dbName: dbName),
          );
        }
        break;
      case 'export':
        _exportDatabase(context, provider, dbName);
        break;
      case 'schema_diff':
        if (context.mounted) {
          SchemaDiffDialog.show(
            context: context,
            initialConnectionId: connectionId,
            initialDatabaseName: dbName,
          );
        }
        break;
      // Phase E — Save Schema Snapshot
      case 'save_snapshot':
        _saveSchemaSnapshot(context, provider, connectionId, dbName);
        break;
      case 'drop':
        _dropDatabase(context, provider, connectionId, dbName);
        break;
    }
  }

  Future<void> _exportDatabase(
    BuildContext context,
    AppProvider provider,
    String dbName,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final sql = await provider.exportDatabaseStructure(dbName);
      // Provider returns '' silently when the connection dropped or the
      // adapter doesn't implement structure export — don't claim success.
      if (sql.trim().isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.exportFailed(l10n.noData)),
              backgroundColor: context.themeColors.accentRed,
            ),
          );
        }
        return;
      }
      await Clipboard.setData(ClipboardData(text: sql));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.copiedDbStructureToClipboard(dbName)),
            backgroundColor: context.themeColors.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.exportFailed(e.toString()),
            ),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  // Phase E — Save Schema Snapshot from context menu
  Future<void> _saveSchemaSnapshot(
    BuildContext context,
    AppProvider provider,
    String connectionId,
    String dbName,
  ) async {
    try {
      final connections = provider.connection.savedConnections;
      final conn = connections.where((c) => c.id == connectionId).firstOrNull;
      if (conn == null) return;

      final diffService = SchemaDiffService(provider.dbService);
      final snapshot = await diffService.captureSnapshot(
        connectionId: connectionId,
        connectionName: conn.name,
        databaseName: dbName,
      );

      final snapshotService = SchemaSnapshotService(diffService);
      final name =
          '${conn.name}_${dbName}_${DateTime.now().millisecondsSinceEpoch}';
      await snapshotService.saveSnapshot(
        snapshot: snapshot,
        name: name,
        dbType: conn.type.name,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Schema snapshot saved: $name'),
            backgroundColor: context.themeColors.accentGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save snapshot: $e'),
            backgroundColor: context.themeColors.accentRed,
          ),
        );
      }
    }
  }

  Future<void> _dropDatabase(
    BuildContext context,
    AppProvider provider,
    String connectionId,
    String dbName,
  ) async {
    final l10n = AppLocalizations.of(context)!;

    // T014 — get child object counts for consequence warning
    final cached = provider.getCachedDatabase(connectionId, dbName);
    final tableCount = cached?.tables.length ?? 0;
    final viewCount = cached?.views.length ?? 0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => DropDatabaseConfirmDialog(
        dbName: dbName,
        tableCount: tableCount,
        viewCount: viewCount,
      ),
    );

    if (confirm == true) {
      try {
        // Invalidate cache BEFORE drop to prevent stale schema on same-name recreate
        provider.invalidateDatabaseCache(connectionId, dbName);
        // 据 adapter 返回值区分成功/失败（原先无论结果都提示成功）
        final ok = await provider.dropDatabase(dbName);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok ? l10n.databaseDeleted(dbName) : l10n.commonFailed,
            ),
            backgroundColor: ok
                ? context.themeColors.accentGreen
                : context.themeColors.accentRed,
          ),
        );
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.deleteFailed(e)),
              backgroundColor: context.themeColors.accentRed,
            ),
          );
        }
      }
    }
  }
}
