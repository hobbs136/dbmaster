// C20 · SQL Server 侧边栏插件 —— per-type SidebarPlugin 收官件（与 T28
// 网关竖切同窗）。
//
// 树装配（自 builders/sqlserver_tree_builder.dart 整体迁入）：
// - 连接级全局节点：Server Status / Process List（只读）/ Users（_SsGlobalNodes）；
// - 库级对象子树：schema-first 树（Schema → Tables/Views/Procedures/Functions，
//   _SsDatabaseNodes）——迁入后 sidebar_tree 的 SS legacy 分支（最后两处
//   DatabaseType. 字面量）删除，宿主字面量真正归零；core 泛 SQL 共享树的
//   SS 排除分支同步移除（SS 由本插件接管 schema 层）。
//
// 能力菜单（capabilityGroups）：恒空（C18 TD/C17 Mongo 同款裁定）——port 位表
// process.kill = {my,do,pg}（SS 进程只读无 kill），连接级无其它真实独立入口；
// 树内右键与共享门控菜单随树/宿主菜单保留。
//
// 文案：全局节点标签与空态文案已 l10n 化（C22-0，原 C20 迁入时硬编码英文）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../models/drag_models.dart';
import '../../../molecules/context_menu.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/sql_escape_utils.dart';
import '../builders/tree_utils.dart';
import '../tree_item.dart';

// ── Capability Coverage ──────────────────────────────────────────
// Surfaces (decided product features):
//   - Tables → columns / indexes / foreign-keys via SqlSchemaAdapter
//     (getTableColumns/Indexes/getForeignKeys) + SchemaAwareAdapter 4-seg keys
//   - Tables → double-click browse (SELECT TOP N) via getDefaultBrowseQuery;
//     right-click context menu (browse/create/edit/properties) via shared _showTableMenu
//   - Views       → double-click browse (SELECT TOP N * FROM [schema].[view])
//   - Procedures  → double-click EXEC [schema].[proc];
//   - Functions   → double-click SELECT [schema].[fn]();  (scalar; TVF assumed scalar — known limitation)
//   - Connection globals: Server Status, Process List (read-only), Users (sql_logins)
// Deliberately omits (not a decided feature for SQL Server):
//   - Kill process        — process.kill 位表 = {my,do,pg}（SS 进程只读）；the
//                           sys.dm_exec_sessions query here also fetches no query text, so unlike
//                           MySQL/PG there is nothing to copy or terminate from the leaf
//   - Replication / Charset nodes — not a decided feature (no adapter capability surfaced)
//   - AI analyze / maintenance from tree — gated to MySQL/Doris path
//   - Triggers node        — getTriggers exists but trigger surfacing not yet decided (revisit)
// Fork note: consumes only shared helpers (buildInteractiveTableSchemaLeaves,
//   buildSimpleObjectCategory). Fork on demand only if SQL Server needs to diverge.
// ─────────────────────────────────────────────────────────────────
class SqlserverSidebarPlugin implements SidebarPlugin {
  const SqlserverSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'sqlserver-sidebar',
        supportedTypes: {DatabaseType.sqlserver},
        source: PluginSource.databaseType,
        icon: LucideIcons.database,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) {
    // 恒空裁定：连接级无真实独立入口（process.kill 位不含 ss——进程只读）。
    return const [];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    return _SsGlobalNodes(
      context: context,
      provider: tree.provider,
      connectionId: tree.connectionId,
      expandedItems: tree.expandedItems,
      onToggleExpand: tree.onToggleExpand,
    ).build();
  }

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) {
    return _SsDatabaseNodes(
      context: context,
      provider: db.provider,
      connectionId: db.connectionId,
      expandedItems: db.expandedItems,
      onToggleExpand: db.onToggleExpand,
    ).buildDatabaseTree(db);
  }
}

// ============================================================================
// 连接级全局节点（自 SqlServerTreeBuilder.buildGlobalNodes 迁入）
// ============================================================================

class _SsGlobalNodes {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final Set<String> expandedItems;
  final Function(String) onToggleExpand;

  _SsGlobalNodes({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
    required this.onToggleExpand,
  });

  List<Widget> build() {
    return [
      _buildGlobalNode(
        '$connectionId:sqlserver_status',
        LucideIcons.heartPulse,
        context.themeColors.accentBlue,
        AppLocalizations.of(context)!.sidebarServerStatus,
        _buildServerStatusContent,
      ),
      _buildGlobalNode(
        '$connectionId:sqlserver_process',
        LucideIcons.list,
        context.themeColors.accentBlue,
        AppLocalizations.of(context)!.sidebarProcessList,
        _buildProcessListContent,
      ),
      _buildGlobalNode(
        '$connectionId:sqlserver_users',
        LucideIcons.users,
        context.themeColors.accentBlue,
        AppLocalizations.of(context)!.sidebarUsers,
        _buildUsersContent,
      ),
    ];
  }

  Widget _buildGlobalNode(
    String expandKey,
    IconData icon,
    Color iconColor,
    String label,
    Widget Function() contentBuilder,
  ) {
    final isExpanded = expandedItems.contains(expandKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: icon,
          iconColor: iconColor,
          label: label,
          isExpanded: isExpanded,
          showArrow: true,
          onTap: () {
            onToggleExpand(expandKey);
          },
        ),
        if (isExpanded) contentBuilder(),
      ],
    );
  }

  Widget _buildServerStatusContent() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getServerStatus(),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildLoadingLeaf(context);
        }
        if (snapshot.hasError ||
            snapshot.data == null ||
            snapshot.data!.isEmpty) {
          return buildInfoLeaf(
            context,
            LucideIcons.ban,
            AppLocalizations.of(context)!.commonNoData,
            iconColor: context.themeColors.textMuted,
          );
        }
        final data = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data.entries.map((entry) {
            return buildInfoLeaf(
              context,
              LucideIcons.circle,
              '${entry.key}: ${entry.value}',
              iconColor: Colors.transparent,
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildProcessListContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getProcessList(),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildLoadingLeaf(context);
        }
        final processes = snapshot.data ?? [];
        if (processes.isEmpty) {
          return buildInfoLeaf(
            context,
            LucideIcons.ban,
            AppLocalizations.of(context)!.sidebarNoActiveProcesses,
            iconColor: context.themeColors.textMuted,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: processes.take(10).map((proc) {
            return TreeItem(
              level: 3,
              icon: LucideIcons.memoryStick,
              iconColor: context.themeColors.textSecondary,
              label:
                  '${proc['program'] ?? 'Unknown'} (${proc['status'] ?? '?'})',
              showArrow: false,
              onTap: () {},
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildUsersContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getUsers(),
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildLoadingLeaf(context);
        }
        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return buildInfoLeaf(
            context,
            LucideIcons.ban,
            AppLocalizations.of(context)!.sidebarNoUsers,
            iconColor: context.themeColors.textMuted,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: users.map((user) {
            return TreeItem(
              level: 3,
              icon: LucideIcons.user,
              iconColor: context.themeColors.textSecondary,
              label: user['name']?.toString() ?? 'Unknown',
              showArrow: false,
              onTap: () {},
              // T039b/FR-011 — sql_login leaf right-click (was menu-less)
              onContextMenu: (pos) => _showUserMenu(context, pos, user),
            );
          }).toList(),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _getServerStatus() async {
    try {
      // SERVERPROPERTY 返回 sql_variant——tiberius 解码 todo!() panic（T28
      // 已知边界），SQL 层 CAST 成 nvarchar 规避（信息无损）。
      final result = await provider.executeQuery('''
        SELECT @@VERSION AS version,
               CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) AS edition,
               CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) AS product_version,
               (SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process = 1) AS user_connections,
               (SELECT COUNT(*) FROM sys.dm_exec_requests WHERE blocking_session_id > 0) AS blocked_requests
      ''', connectionId: connectionId);
      if (result.isNotEmpty) return Map<String, dynamic>.from(result.first);
    } catch (e) {
      AppLogger.e('SqlserverSidebarPlugin', '获取服务器状态失败', e);
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> _getProcessList() async {
    try {
      return await provider.executeQuery('''
        SELECT s.session_id AS spid, s.login_name AS loginame,
               s.status, s.program_name AS program,
               DB_NAME(s.database_id) AS dbname, r.blocking_session_id AS blocked
        FROM sys.dm_exec_sessions s
        LEFT JOIN sys.dm_exec_requests r ON s.session_id = r.session_id
        WHERE s.is_user_process = 1 ORDER BY s.session_id
      ''', connectionId: connectionId);
    } catch (e) {
      AppLogger.e('SqlserverSidebarPlugin', '获取进程列表失败', e);
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getUsers() async {
    try {
      return await provider.executeQuery('''
        SELECT name, type_desc, create_date, is_disabled
        FROM sys.sql_logins ORDER BY name
      ''', connectionId: connectionId);
    } catch (e) {
      AppLogger.e('SqlserverSidebarPlugin', '获取用户列表失败', e);
      return [];
    }
  }

  // T039b/FR-011 — User (sql_login) leaf context menu (was menu-less).
  // Copy Name copies the login name. Drop omitted: no dropLogin facade exists.
  Future<void> _showUserMenu(
    BuildContext outerContext,
    Offset position,
    Map<String, dynamic> user,
  ) async {
    final l10n = AppLocalizations.of(outerContext)!;
    // T039b — '?' fallback for parity with PG _showUserMenu (was 'Unknown').
    final name = user['name']?.toString() ?? '?';
    await ContextMenuUtils.show(
      context: outerContext,
      position: position,
      items: [
        ContextMenuItem(
          id: 'copyName',
          label: l10n.sidebarCopyName,
          icon: LucideIcons.copy,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: name));
            if (!outerContext.mounted) return;
            ScaffoldMessenger.of(outerContext).showSnackBar(
              SnackBar(
                content: Text(l10n.sqlCopied),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ============================================================================
// 库级 schema-first 树（自 SqlServerTreeBuilder.buildDatabaseNode 迁入）
// ============================================================================

class _SsDatabaseNodes {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final Set<String> expandedItems;
  final Function(String) onToggleExpand;

  _SsDatabaseNodes({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
    required this.onToggleExpand,
  });

  /// Schema-first database node builder (equivalent to PG's buildDatabaseTree).
  /// Renders schemas as L3 nodes with object count badges, with tables/views/
  /// procedures/functions nested within each schema.
  List<Widget> buildDatabaseTree(SidebarDatabaseTreeContext c) {
    // 宿主上下文解构（方法体保持迁移前形状）
    final server = c.server;
    final databaseName = c.databaseName;
    final db = c.db;
    final searchQuery = c.searchQuery;
    final expandedTables = c.expandedTables;
    final loadedTableSchemas = c.loadedTableSchemas;
    final loadedTableForeignKeys = c.loadedTableForeignKeys;
    final loadingTableSchemas = c.loadingTableSchemas;
    final onToggleTable = c.onToggleTable;
    final onRightClickTargetChanged = c.onRightClickTargetChanged;
    final rightClickedNodeKey = c.rightClickedNodeKey;
    final selectedNodeKey = c.selectedNodeKey;
    final tableRowCounts = c.tableRowCounts;
    final onLoadTableRowCounts = c.onLoadTableRowCounts;
    final onShowTableMenu = c.onShowTableMenu;
    final onSelectNode = c.onSelectNode;
    final onInsertName = c.onInsertName;
    final onShowColumnMenu = c.onShowColumnMenu;
    final onShowIndexMenu = c.onShowIndexMenu;
    final onShowFkMenu = c.onShowFkMenu;
    // C19：context 回调带 isMaterializedView/isFunction 参（泛 SQL 共享树
    // 消费 MV 语义）。SS 视图恒普通视图、过程叶子恒过程（原 false 语义），
    // 适配为零参形态供下方分类使用。
    final onShowViewMenu = c.onShowViewMenu == null
        ? null
        : (String name, Offset pos) => c.onShowViewMenu!(name, pos, false);
    final onShowProcedureMenu = c.onShowProcedureMenu == null
        ? null
        : (String name, Offset pos) => c.onShowProcedureMenu!(name, pos, false);
    // C19：context 回调带 offerCreateTable/categoryType 参（泛 SQL 共享树
    // 消费 true/'view' 语义）。SS schema 树不提供 Create Table（原
    // offerCreateTable=false 语义），适配为零参形态供下方分类头使用。
    final onShowCategoryMenu = c.onShowCategoryMenu == null
        ? null
        : (Offset pos) => c.onShowCategoryMenu!(pos, false, null);

    final l10n = AppLocalizations.of(context)!;
    final sq = searchQuery.toLowerCase();
    final widgets = <Widget>[];

    if (db.schemas.isEmpty) {
      widgets.add(
        TreeItem(
          level: 3,
          icon: LucideIcons.info,
          iconColor: context.themeColors.textMuted,
          label: l10n.commonNoData,
          showArrow: false,
          onTap: () {},
        ),
      );
      return widgets;
    }

    for (final schema in db.schemas) {
      // 搜索过滤 + schema 跳过（镜像 PG builder）
      final schemaMatch = schema.name.toLowerCase().contains(sq);
      final filteredTables = _filterTables(schema.tables, sq);
      final filteredViews = _filterStrings(schema.views, sq);
      final filteredProcedures = _filterStrings(schema.procedures, sq);
      final filteredFunctions = _filterStrings(schema.functions, sq);

      if (!schemaMatch &&
          filteredTables.isEmpty &&
          filteredViews.isEmpty &&
          filteredProcedures.isEmpty &&
          filteredFunctions.isEmpty) {
        continue;
      }

      final schemaKey = '$connectionId:$databaseName:schema:${schema.name}';
      final schemaExpanded = sq.isNotEmpty || expandedItems.contains(schemaKey);
      final objectCount =
          schema.tables.length +
          schema.views.length +
          schema.procedures.length +
          schema.functions.length;

      widgets.add(
        TreeItem(
          level: 3,
          icon: TreeIcons.schema,
          iconColor: context.themeColors.textSecondary,
          label: schema.name,
          badge: objectCount > 0 ? '$objectCount objects' : null,
          isExpanded: schemaExpanded,
          isSelected: _isNodeSelected(
            rightClickedNodeKey,
            selectedNodeKey,
            'schema:$connectionId:$databaseName:${schema.name}',
          ),
          showArrow: true,
          onTap: () => onToggleExpand(schemaKey),
        ),
      );

      if (schemaExpanded) {
        // Tables — 可折叠分类 + 可展开表节点（镜像 PG）
        if (schema.tables.isNotEmpty) {
          final tablesKey = '$schemaKey:tables';
          final tablesExpanded =
              sq.isNotEmpty || expandedItems.contains(tablesKey);
          widgets.add(
            TreeItem(
              level: 4,
              icon: LucideIcons.table2,
              iconColor: context.themeColors.accentBlue,
              label:
                  '${l10n.sidebarTables} (${filteredTables.length}${sq.isNotEmpty && filteredTables.length != schema.tables.length ? "/${schema.tables.length}" : ""})',
              isExpanded: tablesExpanded,
              isSelected: _isNodeSelected(
                rightClickedNodeKey,
                selectedNodeKey,
                'cat:$tablesKey',
              ),
              showArrow: true,
              onTap: () {
                onToggleExpand(tablesKey);
                onLoadTableRowCounts?.call(connectionId, databaseName);
              },
              // T039b — Tables 分类头右键（Refresh）
              onContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
          if (tablesExpanded) {
            for (final table in filteredTables) {
              widgets.add(
                _buildTableNode(
                  server: server,
                  databaseName: databaseName,
                  schemaName: schema.name,
                  table: table,
                  expandedTables: expandedTables,
                  loadedTableSchemas: loadedTableSchemas,
                  loadedTableForeignKeys: loadedTableForeignKeys,
                  loadingTableSchemas: loadingTableSchemas,
                  onToggleTable: onToggleTable,
                  onRightClickTargetChanged: onRightClickTargetChanged,
                  rightClickedNodeKey: rightClickedNodeKey,
                  selectedNodeKey: selectedNodeKey,
                  tableRowCounts: tableRowCounts,
                  onShowTableMenu: onShowTableMenu,
                  onSelectNode: onSelectNode,
                  onInsertName: onInsertName,
                  onShowColumnMenu: onShowColumnMenu,
                  // T039b — 索引/外键叶子菜单透传
                  onShowIndexMenu: onShowIndexMenu,
                  onShowFkMenu: onShowFkMenu,
                ),
              );
            }
          }
        }

        // Views — 双击浏览（schema-qualified → getDefaultBrowseQuery）
        if (schema.views.isNotEmpty) {
          widgets.addAll(
            buildSimpleObjectCategory(
              context: context,
              expandedItems: expandedItems,
              onToggleExpand: onToggleExpand,
              isSelected: (key) =>
                  _isNodeSelected(rightClickedNodeKey, selectedNodeKey, key),
              categoryKey: '$schemaKey:views',
              icon: LucideIcons.eye,
              label: l10n.sidebarViews,
              items: filteredViews,
              totalCount: schema.views.length,
              sq: sq,
              level: 4,
              onDoubleTap: (viewName) => provider.openTableQueryTab(
                connectionId,
                databaseName,
                '${schema.name}.$viewName',
              ),
              // T039b — View 叶子右键（Browse/Copy/Drop，schema-qualified 名透传）
              onItemContextMenu: onShowViewMenu == null
                  ? null
                  : (name, pos) => onShowViewMenu('${schema.name}.$name', pos),
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }

        // Procedures — 双击 EXEC（T-SQL，非 PG 的 CALL）
        if (schema.procedures.isNotEmpty) {
          widgets.addAll(
            buildSimpleObjectCategory(
              context: context,
              expandedItems: expandedItems,
              onToggleExpand: onToggleExpand,
              isSelected: (key) =>
                  _isNodeSelected(rightClickedNodeKey, selectedNodeKey, key),
              categoryKey: '$schemaKey:procedures',
              icon: LucideIcons.network,
              label: l10n.sidebarProcedures,
              items: filteredProcedures,
              totalCount: schema.procedures.length,
              sq: sq,
              level: 4,
              onDoubleTap: (procName) => provider.openQueryTab(
                connectionId,
                databaseName,
                sql: 'EXEC ${_bracketed('${schema.name}.$procName')};',
              ),
              // T039b — Procedure 叶子右键（Call/Copy/Drop，dialect-aware）
              onItemContextMenu: onShowProcedureMenu == null
                  ? null
                  : (name, pos) =>
                        onShowProcedureMenu('${schema.name}.$name', pos),
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }

        // Functions — 双击 SELECT fn()（标量；TVF 暂按标量处理 — 已知限制）
        if (schema.functions.isNotEmpty) {
          widgets.addAll(
            buildSimpleObjectCategory(
              context: context,
              expandedItems: expandedItems,
              onToggleExpand: onToggleExpand,
              isSelected: (key) =>
                  _isNodeSelected(rightClickedNodeKey, selectedNodeKey, key),
              categoryKey: '$schemaKey:functions',
              icon: LucideIcons.functionSquare,
              label: l10n.sidebarFunctions,
              items: filteredFunctions,
              totalCount: schema.functions.length,
              sq: sq,
              level: 4,
              onDoubleTap: (fnName) => provider.openQueryTab(
                connectionId,
                databaseName,
                sql: 'SELECT ${_bracketed('${schema.name}.$fnName')}();',
              ),
              // T039b — 分类头右键（Function 叶子菜单暂缓：SELECT 调用 + DROP FUNCTION
              // 与 procedure 不同，需独立 handler；当前双击 SELECT 仍可用）
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }
      }
    }

    return widgets;
  }

  // ============================================================================
  // 表节点构建 + 交互辅助（镜像 PG，schema-qualified name 无 public 简写）
  // ============================================================================

  Widget _buildTableNode({
    required DbServer server,
    required String databaseName,
    required String schemaName,
    required DbTable table,
    required Set<String> expandedTables,
    required Map<String, DbTable> loadedTableSchemas,
    required Map<String, List<ForeignKey>> loadedTableForeignKeys,
    required Set<String> loadingTableSchemas,
    required Function(String) onToggleTable,
    required Function(String?)? onRightClickTargetChanged,
    required String? rightClickedNodeKey,
    required String? selectedNodeKey,
    required Map<String, int> tableRowCounts,
    required void Function(
      BuildContext context,
      String tableName,
      Offset position,
    )
    onShowTableMenu,
    required ValueChanged<String>? onSelectNode,
    required void Function(String name) onInsertName,
    void Function(
      BuildContext context,
      DbTable schema,
      DbColumn col,
      Offset position,
    )?
    onShowColumnMenu,
    // T039b — 索引/外键叶子菜单回调
    void Function(
      DbIndex idx,
      String schema,
      String tableName,
      List<DbColumn> columns,
      Offset pos,
    )?
    onShowIndexMenu,
    void Function(ForeignKey fk, Offset pos)? onShowFkMenu,
  }) {
    final tk = '$connectionId:$databaseName:$schemaName:${table.name}';
    final te = expandedTables.contains(tk);
    final schema = loadedTableSchemas[tk];
    final loading = loadingTableSchemas.contains(tk);
    final rowCount =
        tableRowCounts['$connectionId:$databaseName:${table.name}'];
    final rowBadge = rowCount != null ? formatNumber(rowCount) : null;
    final qualifiedName = '$schemaName.${table.name}';
    final selected =
        provider.selectedTable == table.name ||
        _isNodeSelected(rightClickedNodeKey, selectedNodeKey, 'table:$tk');
    final leaf = _tableLeaf(
      table: table,
      te: te,
      loading: loading,
      rowBadge: rowBadge,
      selected: selected,
      qualifiedName: qualifiedName,
      tk: tk,
      databaseName: databaseName,
      onToggleTable: onToggleTable,
      onRightClickTargetChanged: onRightClickTargetChanged,
      onShowTableMenu: onShowTableMenu,
    );

    final widgets = <Widget>[
      Draggable<TableDragData>(
        data: TableDragData(
          tableName: qualifiedName,
          databaseName: databaseName,
          connectionId: connectionId,
        ),
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.table2,
                  size: 14,
                  color: context.themeColors.accentBlue,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  '${server.name}.$qualifiedName',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.4, child: leaf),
        child: leaf,
      ),
    ];

    if (te && schema != null) {
      // 列扁平 + 交互式叶子（schema 感知 key），共享 helper
      widgets.addAll(
        buildInteractiveTableSchemaLeaves(
          context: context,
          schema: schema,
          foreignKeys: loadedTableForeignKeys[tk] ?? const <ForeignKey>[],
          indexesLabel: AppLocalizations.of(context)!.sidebarIndexes,
          foreignKeysLabel: AppLocalizations.of(context)!.sidebarForeignKeys,
          colKeyOf: (col) => 'col:$tk:${col.name}',
          idxKeyOf: (idx) => 'idx:$tk:${idx.name}',
          fkKeyOf: (fk) => 'fk:$tk:${fk.name}',
          isSelected: (key) =>
              _isNodeSelected(rightClickedNodeKey, selectedNodeKey, key),
          onSelect: (key) => onSelectNode?.call(key),
          onInsert: onInsertName,
          onColumnMenu: onShowColumnMenu == null
              ? null
              : (pos, col) => onShowColumnMenu(context, schema, col, pos),
          // T039b — 索引/外键叶子右键菜单（透传到共享 handler）
          onIndexMenu: onShowIndexMenu == null
              ? null
              : (pos, idx) => onShowIndexMenu(
                  idx,
                  schemaName,
                  table.name,
                  schema.columns,
                  pos,
                ),
          onFkMenu: onShowFkMenu == null
              ? null
              : (pos, fk) => onShowFkMenu(fk, pos),
        ),
      );
    } else if (te && loading) {
      widgets.add(buildTreeLoadingNode(context));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  TreeItem _tableLeaf({
    required DbTable table,
    required bool te,
    required bool loading,
    required String? rowBadge,
    required bool selected,
    required String qualifiedName,
    required String tk,
    required String databaseName,
    required Function(String) onToggleTable,
    required Function(String?)? onRightClickTargetChanged,
    required void Function(
      BuildContext context,
      String tableName,
      Offset position,
    )
    onShowTableMenu,
  }) {
    return TreeItem(
      level: 5,
      icon: LucideIcons.table2,
      iconColor: context.themeColors.accentBlue,
      iconSize: 12,
      label: table.name,
      showArrow: true,
      isExpanded: te,
      isLoading: loading,
      badge: rowBadge,
      isSelected: selected,
      onTap: () => onToggleTable(tk),
      onDoubleTap: () => _openTableQuery(databaseName, qualifiedName),
      onContextMenu: (pos) {
        onRightClickTargetChanged?.call('table:$tk');
        onShowTableMenu(context, qualifiedName, pos);
        onRightClickTargetChanged?.call(null);
      },
    );
  }

  bool _isNodeSelected(
    String? rightClickedNodeKey,
    String? selectedNodeKey,
    String nodeKey,
  ) {
    return selectedNodeKey == nodeKey || rightClickedNodeKey == nodeKey;
  }

  List<DbTable> _filterTables(List<DbTable> tables, String sq) {
    if (sq.isEmpty) return tables;
    return tables.where((t) => t.name.toLowerCase().contains(sq)).toList();
  }

  List<String> _filterStrings(List<String> items, String sq) {
    if (sq.isEmpty) return items;
    return items.where((i) => i.toLowerCase().contains(sq)).toList();
  }

  /// 双击表名：打开 query 编辑器（预填默认浏览查询，不自动执行）。
  /// data 模式仅右键「浏览数据」进入（sidebar_tree 共享菜单的 browse 项）。
  void _openTableQuery(String databaseName, String tableName) {
    provider.openTableQueryTab(connectionId, databaseName, tableName);
    provider.recentTables.recordTableAccess(
      connectionId: connectionId,
      databaseName: databaseName,
      tableName: tableName,
    );
  }

  /// 将 schema.object 拆分并对每段做 T-SQL 标识符转义（复用 SqlEscapeUtils）
  String _bracketed(String qualifiedName) {
    return qualifiedName
        .split('.')
        .map(SqlEscapeUtils.escapeSqlServerIdentifier)
        .join('.');
  }
}
