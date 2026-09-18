// C15 · PostgreSQL 侧边栏插件 —— 首批 per-type SidebarPlugin 之二。
//
// 树装配（自 builders/postgresql_tree_builder.dart 整体迁入）：
// - 连接级全局节点：Server / Process List / Users（_PgGlobalNodes）；
// - 库级对象子树：schema-centric 树（Extensions + Schema → 7 分类 → 对象
//   叶子，_PgDatabaseNodes）——迁入后 sidebar_tree 的 PG 专装配删除，
//   树分缝由本插件接管（空库也返回「无数据」叶子，恒非空 = 恒接管）。
//
// 能力菜单（capabilityGroups）：与 core 同组 id 合并（'advanced'），补 PG
// 专有入口 Terminate（进程管理对话框，pg_stat_activity loader +
// pg_terminate_backend）。能力位经 port 门控（process.kill 含 pg）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../models/drag_models.dart';
import '../../../molecules/context_menu.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../../services/database_abstract.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_logger.dart';
import '../../connection/pg_extension_panel.dart';
import '../builders/tree_utils.dart';
import '../capability/capability_menu_assembly.dart';
import '../capability/process_manager_dialog.dart';
import '../tree_item.dart';

class PostgresqlSidebarPlugin implements SidebarPlugin {
  const PostgresqlSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'postgresql-sidebar',
        supportedTypes: {DatabaseType.postgresql},
        source: PluginSource.databaseType,
        icon: LucideIcons.database,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) {
    return [
      SidebarCapabilityGroup(
        id: 'advanced',
        label: (l10n) => l10n.sidebarCapGroupAdvanced,
        icon: LucideIcons.wrench,
        items: [
          SidebarCapabilityItem(
            id: 'process.kill',
            capabilityId: 'process.kill',
            label: (l10n) => l10n.processListKillQuery,
            icon: LucideIcons.circleStop,
            onActivate: () => _showProcessManager(context),
          ),
        ],
      ),
    ];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    return _PgGlobalNodes(
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
    return _PgDatabaseNodes(
      context: context,
      provider: db.provider,
      connectionId: db.connectionId,
      expandedItems: db.expandedItems,
      onToggleExpand: db.onToggleExpand,
    ).buildDatabaseTree(db);
  }

  // ── 能力项动作 ──────────────────────────────────────────────

  void _showProcessManager(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    final provider = context.read<AppProvider>();
    showDialog(
      context: context,
      builder: (_) => ProcessManagerDialog(
        connectionId: server.id,
        loader: (cid) => _loadProcesses(provider, cid),
        onKill: (cid, pid) => provider.killProcess(cid, pid),
      ),
    );
  }

  /// PG loader：pg_stat_activity 直查（provider 进程缓存路径为 MySQL
  /// SHOW PROCESSLIST 专用）。**不排除自身会话**——对话框里可见/可检视
  /// 自己的长查询与 MySQL SHOW PROCESSLIST 语义一致，且保证至少一行；
  /// 树内 Process List 节点保持「超管排除自身」的原展示语义。
  Future<List<ProcessListEntry>> _loadProcesses(
    AppProvider provider,
    String connectionId,
  ) async {
    final rows = await provider.executeQuery('''
        SELECT pid, usename, state,
               extract(epoch FROM now() - query_start)::int AS seconds,
               left(query, 120) AS query_preview
        FROM pg_stat_activity WHERE state IS NOT NULL
        ORDER BY query_start LIMIT 50
      ''', connectionId: connectionId);
    return [
      for (final p in rows)
        ProcessListEntry(
          id: int.tryParse(p['pid']?.toString() ?? '') ?? 0,
          user: p['usename']?.toString() ?? '?',
          command: p['state']?.toString() ?? '?',
          timeSeconds: int.tryParse(p['seconds']?.toString() ?? '') ?? 0,
          info: p['query_preview']?.toString(),
        ),
    ].where((e) => e.id > 0).toList();
  }
}

// ============================================================================
// 连接级全局节点（自 PostgresqlTreeBuilder.buildGlobalNodes 迁入）
// ============================================================================

class _PgGlobalNodes {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final Set<String> expandedItems;
  final Function(String) onToggleExpand;

  _PgGlobalNodes({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
    required this.onToggleExpand,
  });

  List<Widget> build() {
    final l10n = AppLocalizations.of(context)!;
    return [
      _buildGlobalNode(
        '$connectionId:pg_server',
        LucideIcons.monitor,
        context.themeColors.brandColor(DatabaseType.postgresql),
        l10n.sidebarServer,
        _buildServer,
      ),
      _buildGlobalNode(
        '$connectionId:pg_process',
        LucideIcons.list,
        context.themeColors.accentBlue,
        l10n.sidebarProcessList,
        _buildProcessList,
      ),
      _buildGlobalNode(
        '$connectionId:pg_users',
        LucideIcons.users,
        context.themeColors.brandColor(DatabaseType.postgresql),
        l10n.sidebarUsers,
        _buildUsers,
      ),
    ];
  }

  Widget _buildGlobalNode(
    String key,
    IconData icon,
    Color iconColor,
    String label,
    Widget Function() content,
  ) {
    final isExpanded = expandedItems.contains(key);
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
          onTap: () => onToggleExpand(key),
        ),
        if (isExpanded) content(),
      ],
    );
  }

  Widget _buildServer() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getServerInfo(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildLoadingLeaf(context);
        }
        final data = snapshot.data ?? {};
        if (data.isEmpty) {
          return buildInfoLeaf(
            context,
            LucideIcons.ban,
            'No data',
            iconColor: context.themeColors.textMuted,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildInfoLeaf(
              context,
              LucideIcons.info,
              'PostgreSQL ${data['version'] ?? 'N/A'}',
            ),
            buildInfoLeaf(
              context,
              LucideIcons.timer,
              'Uptime: ${data['uptime'] ?? 'N/A'}',
            ),
            buildInfoLeaf(
              context,
              LucideIcons.users,
              '${data['connections'] ?? '?'} connections',
            ),
            buildInfoLeaf(
              context,
              LucideIcons.database,
              '${data['dbSize'] ?? '?'}',
            ),
          ],
        );
      },
    );
  }

  Widget _buildProcessList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getProcessList(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildLoadingLeaf(context);
        }
        final processes = snapshot.data ?? [];
        if (processes.isEmpty) {
          return buildInfoLeaf(
            context,
            LucideIcons.ban,
            // 查询含 idle 会话，空结果表示确实无会话（非仅无 active 查询）。
            'No sessions',
            iconColor: context.themeColors.textMuted,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: processes.take(10).map((p) {
            return TreeItem(
              level: 3,
              icon: LucideIcons.chartLine,
              iconColor: p['state'] == 'active'
                  ? context.themeColors.warning
                  : context.themeColors.textSecondary,
              label:
                  '${p['usename'] ?? '?'} · ${p['application_name'] ?? '?'} (${p['state'] ?? '?'})',
              showArrow: false,
              onTap: () {},
              onContextMenu: (position) =>
                  _showProcessContextMenu(context, position, p),
            );
          }).toList(),
        );
      },
    );
  }

  // Users 节点 —— pg_user 角色/超管列表（弥补此前仅有 Server/Process 的不对称）
  Widget _buildUsers() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getUsers(),
      builder: (_, snapshot) {
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
          children: users.take(20).map((u) {
            final superVal = u['usesuper'];
            final isSuper =
                superVal == true ||
                superVal.toString() == 'true' ||
                superVal.toString() == '1' ||
                superVal.toString() == 't';
            return TreeItem(
              level: 3,
              icon: LucideIcons.user,
              iconColor: isSuper
                  ? context.themeColors.warning
                  : context.themeColors.textSecondary,
              label: '${u['usename'] ?? '?'}${isSuper ? " (superuser)" : ""}',
              showArrow: false,
              onTap: () {},
              // T039b/FR-011 — role leaf right-click (was menu-less)
              onContextMenu: (pos) => _showUserMenu(context, pos, u),
            );
          }).toList(),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getUsers() async {
    try {
      return await provider.executeQuery(
        'SELECT usename, usesuper FROM pg_user ORDER BY usename',
        connectionId: connectionId,
      );
    } catch (e) {
      AppLogger.e('PgSidebarPlugin', 'Users list failed', e);
      return [];
    }
  }

  // T039b/FR-004/FR-007/FR-023 — migrated from raw showMenu to the shared
  // ContextMenuUtils renderer (visual consistency + keyboard nav). Copy Query is
  // disabled with a reason when the session has no query text (was a silent
  // absence); Terminate is destructive and grouped at the bottom (pg_terminate_backend).
  Future<void> _showProcessContextMenu(
    BuildContext outerContext,
    Offset position,
    Map<String, dynamic> proc,
  ) async {
    final l10n = AppLocalizations.of(outerContext)!;
    final pidStr = proc['pid']?.toString() ?? '?';
    final user = proc['usename']?.toString() ?? '?';
    final query = proc['query_preview']?.toString();
    final hasQuery = query != null && query.isNotEmpty;

    await ContextMenuUtils.show(
      context: outerContext,
      position: position,
      items: [
        ContextMenuItem(
          id: 'copy_query',
          label: l10n.processListCopyQuery,
          icon: LucideIcons.copy,
          enabled: hasQuery,
          disabledReason: hasQuery ? null : l10n.processListNoQueryText,
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: query ?? ''));
            if (!outerContext.mounted) return;
            ScaffoldMessenger.of(outerContext).showSnackBar(
              SnackBar(
                content: Text(l10n.sqlCopied),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        const ContextMenuItem.divider(),
        ContextMenuItem(
          id: 'terminate',
          label: l10n.processListKillQuery,
          icon: LucideIcons.circleStop,
          isDestructive: true,
          onTap: () => _confirmAndKill(pidStr, user),
        ),
      ],
    );
  }

  // T039b/FR-011 — User (role) leaf context menu (previously a dead node).
  // Copy Name copies the role name. Refresh omitted: PG users load via a one-shot
  // FutureBuilder (no provider cache to invalidate); collapse/re-expand re-fetches.
  // Drop omitted: no provider/adapter dropRole exists yet.
  Future<void> _showUserMenu(
    BuildContext outerContext,
    Offset position,
    Map<String, dynamic> user,
  ) async {
    final l10n = AppLocalizations.of(outerContext)!;
    final name = user['usename']?.toString() ?? '?';
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

  void _confirmAndKill(String pidStr, String user) {
    final pid = int.tryParse(pidStr) ?? 0;
    if (pid == 0) return;
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.themeColors.bgSecondary,
        title: Text(l10n.processListKillConfirmTitle),
        content: Text(l10n.processListKillConfirm(pidStr, user, '')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            // await 终止结果并给出成功/失败反馈（原先 fire-and-forget 且无提示，
            // 且 adapter 会把"未终止"误报为成功——现以 pg_terminate_backend 返回值为准）
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await provider.killProcess(connectionId, pid);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? l10n.commonSuccess : l10n.commonFailed),
                  backgroundColor: ok
                      ? context.themeColors.accentGreen
                      : context.themeColors.error,
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(l10n.processListKillQuery),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _getServerInfo() async {
    try {
      final results = await provider.executeQuery('''
        SELECT version() AS version,
               pg_database_size(current_database()) AS size_bytes,
               (SELECT count(*) FROM pg_stat_activity) AS connections,
               extract(epoch FROM current_timestamp - pg_postmaster_start_time())::bigint AS uptime_seconds
      ''', connectionId: connectionId);
      if (results.isNotEmpty) {
        final r = results.first;
        final bytes = int.tryParse(r['size_bytes']?.toString() ?? '0') ?? 0;
        final uptimeSec =
            int.tryParse(r['uptime_seconds']?.toString() ?? '0') ?? 0;
        return {
          'version': r['version']?.toString().split(',').first ?? 'N/A',
          'connections': r['connections']?.toString() ?? '0',
          'dbSize': _formatSize(bytes),
          'uptime': _formatUptime(uptimeSec),
        };
      }
    } catch (e) {
      AppLogger.e('PgSidebarPlugin', 'Server info failed', e);
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> _getProcessList() async {
    try {
      // 非超管（无 pg_read_all_stats）在 pg_stat_activity 中只能看到自己会话；
      // 原查询又用 `pid <> pg_backend_pid()` 排除自身 → 结果恒为空。先判断权限：
      // 超管则排除自身并查看全部会话；非超管则保留自身会话（至少有内容可看/可终止）。
      final excludeSelfClause = await _isFullStatsVisible()
          ? 'AND pid <> pg_backend_pid()'
          : '';
      return await provider.executeQuery('''
        SELECT pid, usename, application_name, state,
               extract(epoch FROM now() - query_start)::int AS seconds,
               left(query, 80) AS query_preview
        FROM pg_stat_activity WHERE state IS NOT NULL $excludeSelfClause
        ORDER BY query_start LIMIT 20
      ''', connectionId: connectionId);
    } catch (e) {
      AppLogger.e('PgSidebarPlugin', 'Process list failed', e);
      return [];
    }
  }

  /// 当前连接用户是否为超管或持有 pg_read_all_stats（可在 pg_stat_activity
  /// 中查看全部会话）。判断失败时按 false 处理（保留自身会话），保守不抛错。
  Future<bool> _isFullStatsVisible() async {
    try {
      final rows = await provider.executeQuery(
        "SELECT (current_setting('is_superuser') = 'on') "
        "OR pg_has_role(current_user, 'pg_read_all_stats', 'member') AS visible",
        connectionId: connectionId,
      );
      if (rows.isEmpty) return false;
      final v = rows.first['visible'];
      return v == true || v.toString() == 't' || v.toString() == 'true';
    } catch (_) {
      return false;
    }
  }

  String _formatSize(int bytes) {
    if (bytes >= 1073741824) {
      return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _formatUptime(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// ============================================================================
// 库级 schema-centric 树（自 PostgresqlTreeBuilder.buildDatabaseNode 迁入；
// 参数改经 SidebarDatabaseTreeContext 供给，宿主菜单路由透传不变）
// ============================================================================

class _PgDatabaseNodes {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final Set<String> expandedItems;
  final Function(String) onToggleExpand;

  _PgDatabaseNodes({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.expandedItems,
    required this.onToggleExpand,
  });

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
    final onLoadTableSchema = c.onLoadTableSchema;
    final onShowTableMenu = c.onShowTableMenu;
    final onSelectNode = c.onSelectNode;
    final onInsertName = c.onInsertName;
    final onShowColumnMenu = c.onShowColumnMenu;
    final onShowIndexMenu = c.onShowIndexMenu;
    final onShowFkMenu = c.onShowFkMenu;
    final onShowViewMenu = c.onShowViewMenu;
    final onShowProcedureMenu = c.onShowProcedureMenu;
    // C19：context 回调带 offerCreateTable/categoryType 参（泛 SQL 共享树
    // 消费 true/'view' 语义）。PG schema 树不提供 Create Table（原
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

    // T015 — Extensions node (under database, same level as schemas)
    widgets.addAll(_buildExtensionsNode(l10n));

    for (final schema in db.schemas) {
      // 搜索过滤：若搜索词不匹配 schema 也不匹配 schema 下任何对象，则跳过
      final schemaMatch = schema.name.toLowerCase().contains(sq);
      final filteredTables = _filterTables(schema.tables, sq);
      final filteredViews = _filterStrings(schema.views, sq);
      final filteredMatViews = _filterStrings(schema.materializedViews, sq);
      final filteredFunctions = _filterStrings(schema.functions, sq);
      final filteredProcedures = _filterStrings(schema.procedures, sq);
      final filteredSequences = _filterStrings(schema.sequences, sq);
      final filteredTriggers = _filterTriggers(schema.triggers, sq);

      if (!schemaMatch &&
          filteredTables.isEmpty &&
          filteredViews.isEmpty &&
          filteredMatViews.isEmpty &&
          filteredFunctions.isEmpty &&
          filteredProcedures.isEmpty &&
          filteredSequences.isEmpty &&
          filteredTriggers.isEmpty) {
        continue;
      }

      final schemaKey = '$connectionId:$databaseName:schema:${schema.name}';
      final schemaExpanded = sq.isNotEmpty || expandedItems.contains(schemaKey);

      widgets.add(
        TreeItem(
          level: 3,
          icon: TreeIcons.schema,
          iconColor: context.themeColors.textSecondary,
          label: schema.name,
          badge: _schemaBadge(schema),
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
        // Tables
        if (schema.tables.isNotEmpty) {
          widgets.addAll(
            _buildObjectCategory(
              categoryKey: '$schemaKey:tables',
              icon: LucideIcons.table2,
              label: l10n.sidebarTables,
              items: filteredTables,
              totalCount: schema.tables.length,
              sq: sq,
              level: 4,
              itemBuilder: (table) => _buildTableNode(
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
                onLoadTableRowCounts: onLoadTableRowCounts,
                onLoadTableSchema: onLoadTableSchema,
                onShowTableMenu: onShowTableMenu,
                onSelectNode: onSelectNode,
                onInsertName: onInsertName,
                onShowColumnMenu: onShowColumnMenu,
                // T039b — 索引/外键叶子菜单透传
                onShowIndexMenu: onShowIndexMenu,
                onShowFkMenu: onShowFkMenu,
              ),
              onCategoryExpanded: () =>
                  onLoadTableRowCounts?.call(connectionId, databaseName),
              // T039b — Tables 分类头右键（Refresh）
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }

        // Views
        if (schema.views.isNotEmpty) {
          widgets.addAll(
            _buildSimpleObjectCategory(
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
                schema.name == 'public' ? viewName : '${schema.name}.$viewName',
              ),
              // T039b — View 叶子右键（Browse/Copy/Drop，schema-qualified 名透传）
              onItemContextMenu: onShowViewMenu == null
                  ? null
                  : (name, pos) => onShowViewMenu(
                      schema.name == 'public' ? name : '${schema.name}.$name',
                      pos,
                      false,
                    ),
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }

        // Materialized Views
        if (schema.materializedViews.isNotEmpty) {
          widgets.addAll(
            _buildSimpleObjectCategory(
              categoryKey: '$schemaKey:materializedViews',
              icon: LucideIcons.eye,
              label: l10n.sidebarMaterializedViews,
              items: filteredMatViews,
              totalCount: schema.materializedViews.length,
              sq: sq,
              level: 4,
              onDoubleTap: (mvName) => provider.openTableQueryTab(
                connectionId,
                databaseName,
                schema.name == 'public' ? mvName : '${schema.name}.$mvName',
              ),
              // T039b — 分类头右键（MatView 叶子 DROP 因 DROP MATERIALIZED VIEW 方言差异暂缓）
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }

        // Functions
        if (schema.functions.isNotEmpty) {
          widgets.addAll(
            _buildSimpleObjectCategory(
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
                sql: 'SELECT $fnName();',
              ),
              // T039b — 分类头右键（Function 叶子菜单暂缓：SELECT 调用 + DROP FUNCTION
              // 与 procedure 不同，需独立 handler；当前双击 SELECT 仍可用）
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }

        // Procedures
        if (schema.procedures.isNotEmpty) {
          widgets.addAll(
            _buildSimpleObjectCategory(
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
                sql: 'CALL $procName();',
              ),
              // T039b — Procedure 叶子右键（Call/Copy/Drop，dialect-aware）
              onItemContextMenu: onShowProcedureMenu == null
                  ? null
                  : (name, pos) => onShowProcedureMenu(
                      schema.name == 'public' ? name : '${schema.name}.$name',
                      pos,
                      false,
                    ),
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }

        // Sequences
        if (schema.sequences.isNotEmpty) {
          widgets.addAll(
            _buildSimpleObjectCategory(
              categoryKey: '$schemaKey:sequences',
              icon: LucideIcons.listOrdered,
              label: l10n.sidebarSequences,
              items: filteredSequences,
              totalCount: schema.sequences.length,
              sq: sq,
              level: 4,
              // T039b — 分类头右键 + 叶子 Copy Name（sequence 无双击/无 DROP 需求，
              // Copy Name 使其非死；DROP SEQUENCE 方言差异留作后续）
              onItemContextMenu: (name, pos) =>
                  _showObjectNameMenu(context, name, pos),
              onHeaderContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
        }

        // Triggers
        if (schema.triggers.isNotEmpty) {
          final key = '$schemaKey:triggers';
          final expanded = sq.isNotEmpty || expandedItems.contains(key);
          widgets.add(
            TreeItem(
              level: 4,
              icon: LucideIcons.zap,
              iconColor: context.themeColors.accentBlue,
              label:
                  '${l10n.sidebarTriggers} (${filteredTriggers.length}${sq.isNotEmpty && filteredTriggers.length != schema.triggers.length ? "/${schema.triggers.length}" : ""})',
              isExpanded: expanded,
              isSelected: _isNodeSelected(
                rightClickedNodeKey,
                selectedNodeKey,
                'cat:$key',
              ),
              showArrow: true,
              onTap: () => onToggleExpand(key),
              // T039b — Triggers 分类头右键（Refresh）
              onContextMenu: onShowCategoryMenu == null
                  ? null
                  : (pos) => onShowCategoryMenu(pos),
            ),
          );
          if (expanded) {
            for (final t in filteredTriggers) {
              widgets.add(
                TreeItem(
                  level: 5,
                  icon: LucideIcons.zap,
                  iconColor: context.themeColors.textSecondary,
                  iconSize: 12,
                  label: '${t.name}  (${t.timing} ${t.event})',
                  showArrow: false,
                  onTap: () {},
                  // T039b/FR-010 — trigger leaf right-click (was dead).
                  // Copy Name only: PG trigger View-Definition/Drop need
                  // dialect-specific DDL + a PG-capable TriggerService (follow-up).
                  onContextMenu: (pos) =>
                      _showObjectNameMenu(context, t.name, pos),
                ),
              );
            }
          }
        }
      }
    }

    return widgets;
  }

  // T007 — categorized badge with object type breakdown
  String? _schemaBadge(DbSchema schema) {
    final parts = <String>[];
    if (schema.tables.isNotEmpty) {
      parts.add(
        '${schema.tables.length} ${schema.tables.length == 1 ? 'table' : 'tables'}',
      );
    }
    if (schema.views.isNotEmpty) {
      parts.add(
        '${schema.views.length} ${schema.views.length == 1 ? 'view' : 'views'}',
      );
    }
    if (schema.materializedViews.isNotEmpty) {
      parts.add(
        '${schema.materializedViews.length} mat. view${schema.materializedViews.length == 1 ? '' : 's'}',
      );
    }
    if (schema.functions.isNotEmpty) {
      parts.add(
        '${schema.functions.length} function${schema.functions.length == 1 ? '' : 's'}',
      );
    }
    if (schema.procedures.isNotEmpty) {
      parts.add(
        '${schema.procedures.length} procedure${schema.procedures.length == 1 ? '' : 's'}',
      );
    }
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }

  List<DbTable> _filterTables(List<DbTable> tables, String sq) {
    if (sq.isEmpty) return tables;
    return tables.where((t) => t.name.toLowerCase().contains(sq)).toList();
  }

  List<String> _filterStrings(List<String> items, String sq) {
    if (sq.isEmpty) return items;
    return items.where((i) => i.toLowerCase().contains(sq)).toList();
  }

  List<DbTrigger> _filterTriggers(List<DbTrigger> triggers, String sq) {
    if (sq.isEmpty) return triggers;
    return triggers.where((t) => t.name.toLowerCase().contains(sq)).toList();
  }

  bool _isNodeSelected(
    String? rightClickedNodeKey,
    String? selectedNodeKey,
    String nodeKey,
  ) {
    return selectedNodeKey == nodeKey || rightClickedNodeKey == nodeKey;
  }

  // ============================================================================
  // Extensions Node (T014)
  // ============================================================================

  List<Widget> _buildExtensionsNode(AppLocalizations l10n) {
    final extKey = '$connectionId:extensions';
    final isExpanded = expandedItems.contains(extKey);

    if (!isExpanded) {
      return [
        TreeItem(
          level: 3,
          icon: LucideIcons.puzzle,
          iconColor: context.themeColors.brandColor(DatabaseType.postgresql),
          label: l10n.sidebarExtensions,
          isExpanded: false,
          showArrow: true,
          onTap: () => onToggleExpand(extKey),
        ),
      ];
    }

    return [
      TreeItem(
        level: 3,
        icon: LucideIcons.puzzle,
        iconColor: context.themeColors.brandColor(DatabaseType.postgresql),
        label: l10n.sidebarExtensions,
        isExpanded: true,
        showArrow: true,
        onTap: () => onToggleExpand(extKey),
      ),
      _buildExtensionsContent(),
    ];
  }

  Widget _buildExtensionsContent() {
    return FutureBuilder<List<PgExtension>>(
      future: _getExtensions(),
      builder: (_, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildLoadingLeaf(context);
        }
        final extensions = snapshot.data ?? [];
        if (extensions.isEmpty) {
          return buildInfoLeaf(
            context,
            LucideIcons.ban,
            AppLocalizations.of(context)!.noExtensionsInstalled,
            iconColor: context.themeColors.textMuted,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: extensions.map((ext) {
            return TreeItem(
              level: 4,
              icon: LucideIcons.puzzle,
              iconColor: context.themeColors.brandColor(
                DatabaseType.postgresql,
              ),
              iconSize: 12,
              label: '${ext.name} ${ext.version}',
              showArrow: false,
              onTap: () => showExtensionDetailDialog(
                context,
                provider,
                connectionId,
                ext,
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<List<PgExtension>> _getExtensions() async {
    try {
      final adapter = provider.dbService.getAdapter(connectionId);
      if (adapter != null && adapter is ExtensionAdapter) {
        return await adapter.getExtensions();
      }
    } catch (e) {
      AppLogger.e('PgSidebarPlugin', 'getExtensions failed', e);
    }
    return [];
  }

  // spec 041 US2: _escapeIdentifier 随 _openBrowseObject 迁移到 openBrowseDataTab 后无引用，删除（历史交由版本控制）

  // ============================================================================
  // 分类节点构建
  // ============================================================================

  List<Widget> _buildObjectCategory({
    required String categoryKey,
    required IconData icon,
    required String label,
    required List<DbTable> items,
    required int totalCount,
    required String sq,
    required int level,
    required Widget Function(DbTable item) itemBuilder,
    required VoidCallback onCategoryExpanded,
    void Function(Offset pos)? onHeaderContextMenu, // T039b
  }) {
    final widgets = <Widget>[];
    final expanded = sq.isNotEmpty || expandedItems.contains(categoryKey);
    widgets.add(
      TreeItem(
        level: level,
        icon: icon,
        iconColor: context.themeColors.accentBlue,
        label:
            '$label (${items.length}${sq.isNotEmpty && items.length != totalCount ? "/$totalCount" : ""})',
        isExpanded: expanded,
        isSelected: _isNodeSelected(null, null, 'cat:$categoryKey'),
        showArrow: true,
        onTap: () {
          onToggleExpand(categoryKey);
          if (!expanded) {
            onCategoryExpanded();
          }
        },
        onContextMenu: onHeaderContextMenu, // T039b — 分类头右键
      ),
    );
    if (expanded) {
      for (final item in items) {
        widgets.add(itemBuilder(item));
      }
    }
    return widgets;
  }

  // 委托到共享 buildSimpleObjectCategory（tree_utils），5 处调用点签名不变
  // T039b — 透传 onItemContextMenu / onHeaderContextMenu 到共享 helper
  List<Widget> _buildSimpleObjectCategory({
    required String categoryKey,
    required IconData icon,
    required String label,
    required List<String> items,
    required int totalCount,
    required String sq,
    required int level,
    void Function(String name)? onDoubleTap,
    void Function(String name, Offset pos)? onItemContextMenu,
    void Function(Offset pos)? onHeaderContextMenu,
  }) {
    return buildSimpleObjectCategory(
      context: context,
      expandedItems: expandedItems,
      onToggleExpand: onToggleExpand,
      isSelected: (key) => _isNodeSelected(null, null, key),
      categoryKey: categoryKey,
      icon: icon,
      label: label,
      items: items,
      totalCount: totalCount,
      sq: sq,
      level: level,
      onDoubleTap: onDoubleTap,
      onItemContextMenu: onItemContextMenu,
      onHeaderContextMenu: onHeaderContextMenu,
    );
  }

  // ============================================================================
  // 表节点构建
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
    required Future<void> Function(String, String)? onLoadTableRowCounts,
    required Future<void> Function(String)? onLoadTableSchema,
    required void Function(
      BuildContext context,
      String tableName,
      Offset position,
    )
    onShowTableMenu,
    // 交互式 schema 叶子所需的回调
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
    final widgets = <Widget>[];
    final tk = '$connectionId:$databaseName:$schemaName:${table.name}';
    final te = expandedTables.contains(tk);
    final schema = loadedTableSchemas[tk];
    final loading = loadingTableSchemas.contains(tk);
    final rowCountKey = '$connectionId:$databaseName:${table.name}';
    final rowCount = tableRowCounts[rowCountKey];
    final rowBadge = rowCount != null ? formatNumber(rowCount) : null;
    final qualifiedName = '$schemaName.${table.name}';
    final dragData = TableDragData(
      tableName: qualifiedName,
      databaseName: databaseName,
      connectionId: connectionId,
    );

    widgets.add(
      Draggable<TableDragData>(
        data: dragData,
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
        childWhenDragging: Opacity(
          opacity: 0.4,
          child: TreeItem(
            level: 5,
            icon: LucideIcons.table2,
            iconColor: context.themeColors.accentBlue,
            iconSize: 12,
            label: table.name,
            showArrow: true,
            isExpanded: te,
            isLoading: loading,
            badge: rowBadge,
            isSelected:
                provider.selectedTable == table.name ||
                _isNodeSelected(
                  rightClickedNodeKey,
                  selectedNodeKey,
                  'table:$connectionId:$databaseName:$schemaName:${table.name}',
                ),
            onTap: () => onToggleTable(tk),
            onDoubleTap: () => _openTableQuery(
              databaseName,
              schemaName == 'public' ? table.name : '$schemaName.${table.name}',
            ),
            onContextMenu: (pos) {
              onRightClickTargetChanged?.call(
                'table:$connectionId:$databaseName:$schemaName:${table.name}',
              );
              onShowTableMenu(
                context,
                schemaName == 'public'
                    ? table.name
                    : '$schemaName.${table.name}',
                pos,
              );
              onRightClickTargetChanged?.call(null);
            },
          ),
        ),
        child: TreeItem(
          level: 5,
          icon: LucideIcons.table2,
          iconColor: context.themeColors.accentBlue,
          iconSize: 12,
          label: table.name,
          showArrow: true,
          isExpanded: te,
          isLoading: loading,
          badge: rowBadge,
          isSelected:
              provider.selectedTable == table.name ||
              _isNodeSelected(
                rightClickedNodeKey,
                selectedNodeKey,
                'table:$connectionId:$databaseName:$schemaName:${table.name}',
              ),
          onTap: () => onToggleTable(tk),
          onDoubleTap: () => _openTableQuery(
            databaseName,
            schemaName == 'public' ? table.name : '$schemaName.${table.name}',
          ),
          onContextMenu: (pos) {
            onRightClickTargetChanged?.call(
              'table:$connectionId:$databaseName:$schemaName:${table.name}',
            );
            onShowTableMenu(
              context,
              schemaName == 'public'
                  ? table.name
                  : '$schemaName.${table.name}',
              pos,
            );
            onRightClickTargetChanged?.call(null);
          },
        ),
      ),
    );

    if (te && schema != null) {
      // 列扁平 + 交互式叶子（schema 感知 key），共享 helper
      widgets.addAll(
        buildInteractiveTableSchemaLeaves(
          context: context,
          schema: schema,
          foreignKeys: loadedTableForeignKeys[tk] ?? const <ForeignKey>[],
          indexesLabel: AppLocalizations.of(context)!.sidebarIndexes,
          foreignKeysLabel: AppLocalizations.of(context)!.sidebarForeignKeys,
          colKeyOf: (col) =>
              'col:$connectionId:$databaseName:$schemaName:${table.name}:${col.name}',
          idxKeyOf: (idx) =>
              'idx:$connectionId:$databaseName:$schemaName:${table.name}:${idx.name}',
          fkKeyOf: (fk) =>
              'fk:$connectionId:$databaseName:$schemaName:${table.name}:${fk.name}',
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
}

// T039b/FR-010 — Generic object-name context menu (Copy Name) for
// otherwise-dead simple-object leaves (sequences, triggers) whose richer
// actions (View-definition / Drop) need dialect-specific DDL or a
// PG-capable TriggerService tracked as a follow-up. Keeps the node non-dead.
Future<void> _showObjectNameMenu(
  BuildContext outerContext,
  String name,
  Offset position,
) async {
  final l10n = AppLocalizations.of(outerContext)!;
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
