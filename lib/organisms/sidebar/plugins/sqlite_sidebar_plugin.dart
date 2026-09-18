// C16 · SQLite 侧边栏插件 —— 整树连接级（无库级分缝）。
//
// 拆法裁定：SQLite 无服务器/数据库两层——ATTACH 的 alias 列表来自
// PRAGMA database_list，是**连接级**事实；连接卡展开区的全部内容即本树
// （单库扁平 / 多库 per-alias header，spec 050）。故整树走 buildGlobalTree，
// buildDatabaseTree 恒空（分缝回退契约不变，C19 删旧路径时无需反转）。
//
// 能力菜单（capabilityGroups）：与 core 同 'advanced' 组合并，补 SQLite
// 专有入口——Attach Database…（sqlite.attach 位）/ PRAGMA Explorer
// （sqlite.pragma 位），port 门控，本文件不写 DatabaseType 能力分支。
//
// 树装配体 `_SqliteConnectionTree` 自 builders/sqlite_tree_builder.dart
// 逐行迁入（行为保持）；Save As 原直 cast SQLiteAdapter 已收编为
// dbService.saveDatabaseAs（铁律 3：区块重建 adapter 直连清零）。
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/tab_provider.dart';
import '../../../models/database_models.dart' hide QueryTab;
import '../../../l10n/app_localizations.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/open_directory.dart';
import '../../../services/ai_service.dart';
import '../../connection/error_boundary.dart';
import '../../connection/attach_database_dialog.dart';
import '../../connection/pragma_panel.dart';
import '../../pro/pro_import_ui.dart';
import '../../connection/table_dialog/rename_table_dialog.dart';
import '../../connection/table_dialog/drop_table_confirm_dialog.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../tree_item.dart';
import '../builders/tree_utils.dart';
import '../capability/capability_menu_assembly.dart';
import '../../../molecules/compact_popup_menu_item.dart';
import '../../../theme/app_colors.dart';

class SqliteSidebarPlugin implements SidebarPlugin {
  const SqliteSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
    id: 'sqlite-sidebar',
    supportedTypes: {DatabaseType.sqlite},
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
            id: 'sqlite.attach',
            capabilityId: 'sqlite.attach',
            label: (l10n) => l10n.sqliteAttachDatabase,
            icon: LucideIcons.link,
            onActivate: () => _activateAttach(context),
          ),
          SidebarCapabilityItem(
            id: 'sqlite.pragma',
            capabilityId: 'sqlite.pragma',
            label: (l10n) => l10n.pragmaExplorerTitle,
            icon: LucideIcons.slidersHorizontal,
            onActivate: () => _activatePragmaExplorer(context),
          ),
        ],
      ),
    ];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    return _SqliteConnectionTree(
      context: context,
      provider: tree.provider,
      connectionId: tree.connectionId,
      searchQuery: tree.searchQuery,
      expandedItems: tree.expandedItems,
      expandedTables: tree.expandedTables,
      onToggleExpand: tree.onToggleExpand,
      onToggleTable: tree.onToggleTable,
    ).build();
  }

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) {
    // SQLite 整树是连接级（buildGlobalTree），库级分缝恒空。
    return const [];
  }

  // ── 能力项动作（树内同流程共享：showSqliteAttachFlow）──

  void _activateAttach(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    unawaited(
      showSqliteAttachFlow(context, context.read<AppProvider>(), server.id),
    );
  }

  void _activatePragmaExplorer(BuildContext context) {
    final server = resolveSidebarActionServer(context);
    if (server == null) return;
    PragmaExplorerDialog.show(
      context,
      provider: context.read<AppProvider>(),
      connectionId: server.id,
    );
  }
}

/// Attach Database 对话框 + ATTACH 执行 + SnackBar 反馈（能力菜单与
/// 树内 header 菜单/Database Info 菜单共用同一流程）。
Future<void> showSqliteAttachFlow(
  BuildContext context,
  AppProvider provider,
  String connectionId,
) async {
  final result = await showDialog<AttachResult?>(
    context: context,
    builder: (ctx) => AttachDatabaseDialog(connectionId: connectionId),
  );
  if (result == null || !context.mounted) return;
  await _performAttach(
    context,
    provider,
    connectionId,
    result.path,
    result.alias,
  );
}

Future<void> _performAttach(
  BuildContext context,
  AppProvider provider,
  String connectionId,
  String path,
  String alias,
) async {
  final l10n = AppLocalizations.of(context)!;
  final res = await provider.connection.attachDatabase(
    connectionId,
    path,
    alias,
  );
  if (!context.mounted) return;
  if (res.success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.sqliteAttachSuccess(alias)),
        backgroundColor: context.themeColors.success,
      ),
    );
  } else {
    // 校验失败（errorKey）或底层失败（errorDetail）
    final message = res.errorKey != null
        ? _localizeAttachError(context, res.errorKey!)
        : l10n.sqliteAttachFailed(res.errorDetail ?? '');
    AppErrorHandler.showErrorSnackBar(context, message);
  }
}

/// 把 alias 校验错误 key 翻译成本地化文案。
String _localizeAttachError(BuildContext context, String errorKey) {
  final l10n = AppLocalizations.of(context)!;
  switch (errorKey) {
    case 'sqliteAttachAliasInvalid':
      return l10n.sqliteAttachAliasInvalid;
    case 'sqliteAttachAliasReserved':
      return l10n.sqliteAttachAliasReserved;
    case 'sqliteAttachAliasKeyword':
      return l10n.sqliteAttachAliasKeyword;
    case 'sqliteAttachAliasDuplicate':
      return l10n.sqliteAttachAliasDuplicate;
    default:
      return errorKey;
  }
}

/// SQLite 连接级整树装配（自 builders/sqlite_tree_builder.dart 迁入，
/// 行为逐行保持：单库扁平 / ATTACH 多库 per-alias header、Tables/Views/
/// Indexes/Triggers 分类 + Database Info、表/列/索引/视图/触发器右键菜单、
/// 只读降级（DDL 仅 main）等全部保留）。
class _SqliteConnectionTree {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final String searchQuery;
  final Set<String> expandedItems;
  final Set<String> expandedTables;
  final Function(String) onToggleExpand;
  final Function(String) onToggleTable;

  _SqliteConnectionTree({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.searchQuery,
    required this.expandedItems,
    required this.expandedTables,
    required this.onToggleExpand,
    required this.onToggleTable,
  });

  List<Widget> build() {
    // spec 050：ATTACH 跨库——对 [main, ...attached] 循环渲染。
    // 数据库列表来自 provider.getConnectionDatabases（数据源 PRAGMA database_list）。
    // 仅有 main 时（无附加库），保持原有的扁平化结构（main 不显示独立 header 节点，
    // 直接展开 Tables/Views/...），避免破坏既有用户体验。
    // 有附加库时，每个库（含 main）作为独立的可折叠 header 节点，下挂各自子树。
    final databases = provider.getConnectionDatabases(connectionId);
    if (databases.length <= 1) {
      // 仅 main（或空）——走扁平化路径（向后兼容）
      return [_buildFlatSubtree(databases.isEmpty ? 'main' : databases.first)];
    }
    // 有附加库——每库一个 header 节点
    return [for (final alias in databases) _buildDatabaseSection(alias)];
  }

  /// 仅 main 库时的扁平化路径（向后兼容，不显示 main header 节点）。
  Widget _buildFlatSubtree(String alias) {
    final db = provider.getCachedDatabase(connectionId, alias);
    if (db != null) {
      return _buildDbSubtree(db, alias: alias);
    }
    return FutureBuilder<Database?>(
      future: _loadDatabaseInfo(alias),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingLeaf();
        }
        final db = snapshot.data;
        if (db == null) {
          return _buildInfoLeaf(
            LucideIcons.circleAlert,
            AppLocalizations.of(context)!.sidebarLoadDbInfoFailed,
            iconColor: context.themeColors.error,
          );
        }
        return _buildDbSubtree(db, alias: alias);
      },
    );
  }

  /// spec 050：附加库（含多库场景下的 main）的 header + 可折叠子树。
  Widget _buildDatabaseSection(String alias) {
    final headerKey = '$connectionId:db:$alias';
    final isExpanded = expandedItems.contains(headerKey);
    final isAttached = alias != 'main';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 1,
          icon: TreeIcons.database,
          iconColor: isAttached
              ? context.themeColors.accentGreen
              : AppDesignSystem.accentPrimary,
          label: alias,
          isExpanded: isExpanded,
          onContextMenu: (position) =>
              _showDatabaseHeaderContextMenu(alias, position),
          onTap: () => onToggleExpand(headerKey),
        ),
        if (isExpanded) _buildSectionContent(alias),
      ],
    );
  }

  /// 附加库 header 展开后的内容（按需 loadDatabaseInfo + 渲染子树）。
  Widget _buildSectionContent(String alias) {
    final db = provider.getCachedDatabase(connectionId, alias);
    if (db != null) {
      return _buildDbSubtree(db, alias: alias, showInfo: alias == 'main');
    }
    return FutureBuilder<Database?>(
      future: _loadDatabaseInfo(alias),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingLeaf();
        }
        final db = snapshot.data;
        if (db == null) {
          return _buildInfoLeaf(
            LucideIcons.circleAlert,
            AppLocalizations.of(context)!.sidebarLoadDbInfoFailed,
            iconColor: context.themeColors.error,
          );
        }
        return _buildDbSubtree(db, alias: alias, showInfo: alias == 'main');
      },
    );
  }

  /// 构建 SQLite 顶层子树（Tables/Views/Indexes/Triggers + Database Info）。
  /// [alias] 当前库名（main 或附加库 alias）；[showInfo] 是否显示 Database Info
  ///（仅 main 库显示，附加库的 PRAGMA 信息不在本节点展示）。
  Widget _buildDbSubtree(
    Database db, {
    String alias = 'main',
    bool showInfo = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTablesNode(db, alias: alias),
        _buildViewsNode(db, alias: alias),
        _buildIndexesNode(db, alias: alias),
        _buildTriggersNode(db, alias: alias),
        if (showInfo) ...[_buildDivider(), _buildDatabaseInfoNode()],
      ],
    );
  }

  Future<Database?> _loadDatabaseInfo([String alias = 'main']) async {
    final cached = provider.getCachedDatabase(connectionId, alias);
    if (cached != null) return cached;

    return await provider.loadDatabaseInfo(connectionId, alias);
  }

  Widget _buildTablesNode(Database db, {String alias = 'main'}) {
    final expandKey = '$connectionId:$alias:tables';
    final isExpanded = expandedItems.contains(expandKey);
    final filteredTables = db.tables
        .where(
          (t) =>
              searchQuery.isEmpty || t.name.toLowerCase().contains(searchQuery),
        )
        .toList();

    filteredTables.sort((a, b) {
      final aKey = '$connectionId:$alias:${a.name}';
      final bKey = '$connectionId:$alias:${b.name}';
      final aFav = provider.sidebar.isFavoriteTable(aKey);
      final bFav = provider.sidebar.isFavoriteTable(bKey);
      if (aFav && !bFav) return -1;
      if (!aFav && bFav) return 1;
      return a.name.compareTo(b.name);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: TreeIcons.tables,
          iconColor: AppDesignSystem.accentPrimary,
          label: 'Tables',
          badge: db.tables.isEmpty ? null : _formatNumber(db.tables.length),
          isExpanded: isExpanded,
          onTap: () => onToggleExpand(expandKey),
          onContextMenu: (position) => _showTablesContextMenu(db, position),
        ),
        if (isExpanded) ...[
          if (filteredTables.isEmpty)
            _buildInfoLeaf(
              LucideIcons.inbox,
              'No tables',
              iconColor: context.themeColors.textMuted,
            )
          else
            ...filteredTables.map(
              (table) => _buildTableNode(table, alias: alias),
            ),
        ],
      ],
    );
  }

  Widget _buildTableNode(DbTable table, {String alias = 'main'}) {
    final tableExpandKey = '$connectionId:$alias:${table.name}';
    final isTableExpanded = expandedTables.contains(tableExpandKey);
    final isFav = provider.sidebar.isFavoriteTable(tableExpandKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 3,
          icon: _getTableIcon(table),
          iconColor: context.themeColors.accentBlue,
          label: table.name,
          badge: table.columns.isEmpty ? null : '${table.columns.length}',
          isSelected: provider.selectedTable == table.name,
          isExpanded: isTableExpanded,
          showArrow: true,
          trailing: InkWell(
            onTap: () => provider.sidebar.toggleFavoriteTable(tableExpandKey),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            child: Icon(
              isFav ? LucideIcons.star : LucideIcons.star,
              size: 14,
              color: isFav
                  ? context.themeColors.warning
                  : context.themeColors.textMuted,
            ),
          ),
          onTap: () {
            provider.setSelectedTable(table.name);
            if (!isTableExpanded && table.columns.isEmpty) {
              provider.loadTableSchema(connectionId, alias, table.name);
            }
            onToggleTable(tableExpandKey);
          },
          onDoubleTap: () {
            _openTableQuery(table, alias: alias);
          },
          onContextMenu: (position) =>
              _showTableContextMenu(table, position, alias: alias),
        ),
        if (isTableExpanded) _buildTableDetails(table),
      ],
    );
  }

  Widget _buildTableDetails(DbTable table) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (table.columns.isNotEmpty)
          ...table.columns.map((column) {
            final (colIcon, colColor) = _getColumnIconInfo(column.type);
            final badges = <Widget>[];

            if (column.isPrimaryKey) {
              badges.add(
                _buildConstraintBadge('PK', context.themeColors.accentRed),
              );
            }
            if (!column.isNullable && !column.isPrimaryKey) {
              badges.add(
                _buildConstraintBadge('NOT NULL', context.themeColors.warning),
              );
            }
            if (column.defaultValue != null) {
              badges.add(
                _buildConstraintBadge(
                  'DEFAULT',
                  context.themeColors.accentPurple,
                ),
              );
            }

            return TreeItem(
              level: 4,
              icon: colIcon,
              iconColor: colColor,
              label: column.name,
              trailing: badges.isEmpty
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: badges),
              showArrow: false,
              onTap: () {},
              onContextMenu: (position) =>
                  _showColumnContextMenu(table.name, column, position),
            );
          })
        else
          _buildLoadingLeaf(),

        if (table.indexes.isNotEmpty) ...[
          _buildDivider(),
          ...table.indexes.map((index) {
            final (idxIcon, idxColor) = _getIndexIconInfo(
              index.name,
              index.isUnique,
            );
            return TreeItem(
              level: 4,
              icon: idxIcon,
              iconColor: idxColor,
              label: index.name,
              trailing: Text(
                index.columns.join(', '),
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textMuted,
                ),
              ),
              showArrow: false,
              onTap: () {},
              onContextMenu: (position) =>
                  _showIndexContextMenu(index, position),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildViewsNode(Database db, {String alias = 'main'}) {
    final expandKey = '$connectionId:$alias:views';
    final isExpanded = expandedItems.contains(expandKey);
    final filteredViews = db.views
        .where(
          (v) => searchQuery.isEmpty || v.toLowerCase().contains(searchQuery),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: TreeIcons.views,
          iconColor: context.themeColors.accentPurple,
          label: 'Views',
          badge: db.views.isEmpty ? null : _formatNumber(db.views.length),
          isExpanded: isExpanded,
          onTap: () => onToggleExpand(expandKey),
          onContextMenu: (position) => _showViewsContextMenu(db, position),
        ),
        if (isExpanded) ...[
          if (filteredViews.isEmpty)
            _buildInfoLeaf(
              LucideIcons.inbox,
              'No views',
              iconColor: context.themeColors.textMuted,
            )
          else
            ...filteredViews.map(
              (view) => TreeItem(
                level: 3,
                icon: TreeIcons.view,
                iconColor: context.themeColors.textSecondary,
                label: view,
                showArrow: false,
                onTap: () {},
                onContextMenu: (position) =>
                    _showViewContextMenu(view, position),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildIndexesNode(Database db, {String alias = 'main'}) {
    final expandKey = '$connectionId:$alias:indexes';
    final isExpanded = expandedItems.contains(expandKey);
    final allIndexes = <DbIndex>[];

    for (final table in db.tables) {
      allIndexes.addAll(table.indexes);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: TreeIcons.indexes,
          iconColor: context.themeColors.accentOrange,
          label: 'Indexes',
          badge: allIndexes.isEmpty ? null : _formatNumber(allIndexes.length),
          isExpanded: isExpanded,
          onTap: () => onToggleExpand(expandKey),
          onContextMenu: (position) => _showIndexesContextMenu(db, position),
        ),
        if (isExpanded) ...[
          if (allIndexes.isEmpty)
            _buildInfoLeaf(
              LucideIcons.inbox,
              'No indexes',
              iconColor: context.themeColors.textMuted,
            )
          else
            ...allIndexes.map((index) {
              final (idxIcon, idxColor) = _getIndexIconInfo(
                index.name,
                index.isUnique,
              );
              return TreeItem(
                level: 3,
                icon: idxIcon,
                iconColor: idxColor,
                label: index.name,
                trailing: Text(
                  index.columns.join(', '),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textMuted,
                  ),
                ),
                showArrow: false,
                onTap: () {},
                onContextMenu: (position) =>
                    _showIndexContextMenu(index, position),
              );
            }),
        ],
      ],
    );
  }

  Widget _buildTriggersNode(Database db, {String alias = 'main'}) {
    final expandKey = '$connectionId:$alias:triggers';
    final isExpanded = expandedItems.contains(expandKey);
    final filteredTriggers = db.triggers
        .where(
          (t) =>
              searchQuery.isEmpty || t.name.toLowerCase().contains(searchQuery),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: TreeIcons.triggers,
          iconColor: context.themeColors.accentYellow,
          label: 'Triggers',
          badge: db.triggers.isEmpty ? null : _formatNumber(db.triggers.length),
          isExpanded: isExpanded,
          onTap: () => onToggleExpand(expandKey),
          onContextMenu: (position) => _showTriggersContextMenu(db, position),
        ),
        if (isExpanded) ...[
          if (filteredTriggers.isEmpty)
            _buildInfoLeaf(
              LucideIcons.inbox,
              'No triggers',
              iconColor: context.themeColors.textMuted,
            )
          else
            ...filteredTriggers.map(
              (trigger) => TreeItem(
                level: 3,
                icon: TreeIcons.trigger,
                iconColor: context.themeColors.textSecondary,
                label: trigger.name,
                badge: '${trigger.timing} ${trigger.event}',
                showArrow: false,
                onTap: () {},
                onContextMenu: (position) =>
                    _showTriggerContextMenu(trigger, position),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildDatabaseInfoNode() {
    final expandKey = '$connectionId:db_info';
    final isExpanded = expandedItems.contains(expandKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: LucideIcons.info,
          iconColor: context.themeColors.accentCyan,
          label: 'Database Info',
          isExpanded: isExpanded,
          onTap: () {
            onToggleExpand(expandKey);
            if (!isExpanded) {
              _loadDatabaseMetaInfo();
            }
          },
          onContextMenu: (position) {
            final connection = provider.connection.savedConnections.firstWhere(
              (c) => c.id == connectionId,
              orElse: () => throw Exception('Connection not found'),
            );
            _showDatabaseInfoContextMenu(connection.host, position);
          },
        ),
        if (isExpanded) _buildDatabaseInfoDetails(),
      ],
    );
  }

  Widget _buildDatabaseInfoDetails() {
    final connection = provider.connection.savedConnections.firstWhere(
      (c) => c.id == connectionId,
      orElse: () => throw Exception('Connection not found'),
    );

    return FutureBuilder<Map<String, dynamic>>(
      future: _loadDatabaseMetaInfo(),
      builder: (context, snapshot) {
        final items = <Widget>[];

        if (snapshot.hasData) {
          final data = snapshot.data!;

          if (data.containsKey('version')) {
            items.add(
              _buildInfoLeaf(LucideIcons.code, 'SQLite ${data['version']}'),
            );
          }

          if (data.containsKey('encoding')) {
            items.add(
              _buildInfoLeaf(LucideIcons.type, 'Encoding: ${data['encoding']}'),
            );
          }

          // PRAGMA info
          if (data.containsKey('journal_mode')) {
            items.add(
              _buildInfoLeaf(
                LucideIcons.notebookPen,
                'Journal Mode: ${data['journal_mode']}',
              ),
            );
          }
          if (data.containsKey('synchronous')) {
            items.add(
              _buildInfoLeaf(
                LucideIcons.refreshCw,
                'Synchronous: ${data['synchronous']}',
              ),
            );
          }
          if (data.containsKey('cache_size')) {
            items.add(
              _buildInfoLeaf(
                LucideIcons.memoryStick,
                'Cache Size: ${data['cache_size']}',
              ),
            );
          }
          if (data.containsKey('temp_store')) {
            items.add(
              _buildInfoLeaf(
                LucideIcons.database,
                'Temp Store: ${data['temp_store']}',
              ),
            );
          }
          if (data.containsKey('locking_mode')) {
            items.add(
              _buildInfoLeaf(
                LucideIcons.lock,
                'Locking Mode: ${data['locking_mode']}',
              ),
            );
          }
        }

        final dbPath = connection.host;
        if (dbPath.isNotEmpty) {
          final fileName = dbPath.split('/').last;
          items.add(_buildInfoLeaf(LucideIcons.file, fileName));

          try {
            final file = File(dbPath);
            if (file.existsSync()) {
              final size = file.lengthSync();
              items.add(
                _buildInfoLeaf(LucideIcons.database, _formatFileSize(size)),
              );
            }
          } catch (e) {
            AppLogger.w('SQLiteNodes', 'Failed to get file size: $e');
          }
        }

        if (items.isEmpty && !snapshot.hasData) {
          items.add(_buildLoadingLeaf());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: items,
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadDatabaseMetaInfo() async {
    final result = <String, dynamic>{};

    try {
      final version = await provider.connection.dbService.getServerVersion();
      if (version != null) {
        result['version'] = version['version'] ?? 'N/A';
      }
    } catch (e) {
      AppLogger.w('SQLiteNodes', 'Failed to get version: $e');
    }

    try {
      final properties = await provider.getDatabaseProperties('main');
      if (properties != null) {
        result['encoding'] = properties['encoding'] ?? 'UTF-8';
      }
    } catch (e) {
      AppLogger.w('SQLiteNodes', 'Failed to get properties: $e');
    }

    // Query common PRAGMAs
    final pragmaList = [
      'journal_mode',
      'synchronous',
      'cache_size',
      'temp_store',
      'locking_mode',
    ];

    for (final pragma in pragmaList) {
      try {
        final rows = await provider.connection.dbService.executeQuery(
          'PRAGMA $pragma;',
          connectionId: connectionId,
        );
        if (rows.isNotEmpty) {
          final value = rows.first.values.first;
          result[pragma] = value?.toString() ?? 'N/A';
        }
      } catch (e) {
        AppLogger.w('SQLiteNodes', 'Failed to get PRAGMA $pragma: $e');
        result[pragma] = 'N/A';
      }
    }

    return result;
  }

  IconData _getTableIcon(DbTable table) {
    if (table.columns.any((c) => c.isPrimaryKey)) {
      return LucideIcons.table2;
    }
    return LucideIcons.table2;
  }

  (IconData, Color) _getColumnIconInfo(String type) {
    final t = type.toUpperCase();
    if (t.contains('INT')) {
      return (LucideIcons.pin, AppDesignSystem.schemaBlue);
    }
    if (t.contains('TEXT') || t.contains('CHAR') || t.contains('VARCHAR')) {
      return (LucideIcons.type, AppDesignSystem.schemaIndigo);
    }
    if (t.contains('REAL') || t.contains('FLOAT') || t.contains('DOUBLE')) {
      return (LucideIcons.dollarSign, AppDesignSystem.schemaPink);
    }
    if (t.contains('BLOB')) {
      return (LucideIcons.archive, AppDesignSystem.schemaPurple);
    }
    if (t.contains('BOOL')) {
      return (LucideIcons.toggleRight, AppDesignSystem.schemaGreen);
    }
    if (t.contains('DATE') || t.contains('TIME')) {
      return (LucideIcons.calendar, AppDesignSystem.schemaAmber);
    }
    return (LucideIcons.columns2, AppDesignSystem.schemaGray);
  }

  (IconData, Color) _getIndexIconInfo(String name, bool isUnique) {
    final n = name.toUpperCase();
    if (n.contains('PRIMARY') || n == 'PRIMARY') {
      return (LucideIcons.keyRound, context.themeColors.accentRed);
    }
    if (isUnique || n.contains('UNIQUE')) {
      return (LucideIcons.lock, context.themeColors.warning);
    }
    return (LucideIcons.arrowUpDown, context.themeColors.accentOrange);
  }

  Widget _buildConstraintBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1,
        vertical: 1,
      ),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoLeaf(IconData icon, String label, {Color? iconColor}) {
    return TreeItem(
      level: 3,
      icon: icon,
      iconColor: iconColor ?? context.themeColors.textSecondary,
      label: label,
      showArrow: false,
      onTap: () {},
    );
  }

  Widget _buildLoadingLeaf() {
    return _buildInfoLeaf(
      LucideIcons.hourglass,
      'Loading...',
      iconColor: context.themeColors.textMuted,
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(
        vertical: AppDesignSystem.space2,
        horizontal: AppDesignSystem.space3,
      ),
      color: context.themeColors.borderSubtle,
    );
  }

  String _formatNumber(int num) {
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toString();
  }

  String _formatFileSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '$bytes B';
  }

  /// 双击表名：打开 query 编辑器（预填默认浏览查询，不自动执行）。
  /// data 模式仅右键「浏览数据」进入（[_browseTableData]）。
  /// spec 050：附加库表传 `alias.tableName` 作为限定名，触发跨库 SELECT。
  void _openTableQuery(DbTable table, {String alias = 'main'}) {
    final qualified = alias == 'main' ? table.name : '$alias.${table.name}';
    provider.openTableQueryTab(connectionId, alias, qualified);
  }

  void _browseTableData(DbTable table, {String alias = 'main'}) {
    AppLogger.d('SQLiteNodes', 'Browse table: ${table.name} (alias: $alias)');
    // spec 041 US2: 走 openBrowseDataTab（顺带修硬编码方言）
    // spec 050：附加库传限定名 `alias.tableName`
    final qualified = alias == 'main' ? table.name : '$alias.${table.name}';
    provider.openBrowseDataTab(connectionId, alias, qualified);
  }

  void _showTableContextMenu(
    DbTable table,
    Offset position, {
    String alias = 'main',
  }) {
    // spec 050：附加库表节点仅支持只读操作（browse/structure/copy_create），
    // DDL（add_column/create_index/rename/empty/drop）仅 main 库可用。
    final isAttached = alias != 'main';
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'browse',
          child: Row(
            children: [
              Icon(
                LucideIcons.eye,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarBrowseData),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'structure',
          child: Row(
            children: [
              Icon(
                LucideIcons.network,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarViewStructure),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'copy_create',
          child: Row(
            children: [
              Icon(
                LucideIcons.copy,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Copy CREATE Statement'),
            ],
          ),
        ),
        if (!isAttached) ...[
          const PopupMenuDivider(height: 6),
          CompactPopupMenuItem(
            value: 'add_column',
            child: Row(
              children: [
                Icon(
                  LucideIcons.columns2,
                  size: 16,
                  color: context.themeColors.textSecondary,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text('Add Column'),
              ],
            ),
          ),
          CompactPopupMenuItem(
            value: 'create_index',
            child: Row(
              children: [
                Icon(
                  LucideIcons.arrowUpDown,
                  size: 16,
                  color: context.themeColors.textSecondary,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(AppLocalizations.of(context)!.sidebarCreateNewIndex),
              ],
            ),
          ),
          const PopupMenuDivider(height: 6),
          CompactPopupMenuItem(
            value: 'rename',
            child: Row(
              children: [
                Icon(
                  LucideIcons.pencil,
                  size: 16,
                  color: context.themeColors.textSecondary,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(AppLocalizations.of(context)!.tableRenameTable),
              ],
            ),
          ),
          CompactPopupMenuItem(
            value: 'empty',
            child: Row(
              children: [
                Icon(
                  LucideIcons.brushCleaning,
                  size: 16,
                  color: context.themeColors.warning,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  AppLocalizations.of(context)!.sidebarEmptyTable,
                  style: TextStyle(color: context.themeColors.warning),
                ),
              ],
            ),
          ),
          CompactPopupMenuItem(
            value: 'drop',
            child: Row(
              children: [
                Icon(
                  LucideIcons.trash2,
                  size: 16,
                  color: context.themeColors.error,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  AppLocalizations.of(context)!.dropTable,
                  style: TextStyle(color: context.themeColors.error),
                ),
              ],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      _handleTableAction(table, value, alias: alias);
    });
  }

  void _handleTableAction(
    DbTable table,
    String action, {
    String alias = 'main',
  }) {
    switch (action) {
      case 'browse':
        _browseTableData(table, alias: alias);
        break;
      case 'structure':
        provider.setSelectedTable(table.name);
        break;
      case 'copy_create':
        _copyCreateStatement(table);
        break;
      case 'add_column':
        _showAddColumnDialog(table);
        break;
      case 'create_index':
        _showCreateIndexDialog(table);
        break;
      case 'rename':
        _showRenameTableDialog(table);
        break;
      case 'empty':
        _showEmptyTableConfirm(table);
        break;
      case 'drop':
        _showDropTableDialog(table);
        break;
    }
  }

  void _copyCreateStatement(DbTable table) {
    final buffer = StringBuffer();
    buffer.writeln('CREATE TABLE "${table.name}" (');

    final columnDefs = table.columns.map((col) {
      final parts = <String>['"${col.name}"', col.type];
      if (col.isPrimaryKey) parts.add('PRIMARY KEY');
      if (!col.isNullable && !col.isPrimaryKey) parts.add('NOT NULL');
      if (col.defaultValue != null) parts.add('DEFAULT ${col.defaultValue}');
      return '  ${parts.join(' ')}';
    }).toList();

    buffer.write(columnDefs.join(',\n'));
    buffer.writeln();
    buffer.writeln(');');

    for (final index in table.indexes) {
      buffer.writeln();
      final uniqueStr = index.isUnique ? 'UNIQUE ' : '';
      buffer.writeln(
        'CREATE ${uniqueStr}INDEX "${index.name}" ON "${table.name}" '
        '(${index.columns.map((c) => '"$c"').join(', ')});',
      );
    }

    final tab = QueryTab(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      title: '${table.name}_create',
      sql: buffer.toString(),
      connectionId: connectionId,
      databaseName: 'main',
    );
    provider.addTab(tab);
  }

  void _showEmptyTableConfirm(DbTable table) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
        title: Text(
          AppLocalizations.of(context)!.sidebarEmptyTable,
          style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will delete all rows from "${table.name}" and run VACUUM to reclaim space.',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                color: context.themeColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final success = await provider.truncateTable(table.name);
                if (success) {
                  provider.invalidateDatabaseCache(connectionId, 'main');
                  provider.loadDatabaseInfo(connectionId, 'main');
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(
                            context,
                          )!.sidebarEmptyTableSuccess(table.name),
                        ),
                        backgroundColor: context.themeColors.success,
                      ),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  AppErrorHandler.showErrorSnackBar(
                    context,
                    AppLocalizations.of(
                      context,
                    )!.sidebarEmptyTableFailed(e.toString()),
                  );
                }
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.error,
            ),
            child: Text(AppLocalizations.of(context)!.sidebarEmptyTable),
          ),
        ],
      ),
    );
  }

  void _showAddColumnDialog(DbTable table) {
    final nameController = TextEditingController();
    final typeController = TextEditingController(text: 'TEXT');
    final defaultController = TextEditingController();
    bool isNotNull = false;
    bool isPrimaryKey = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: context.themeColors.bgSecondary,
          title: Text(
            'Add Column to "${table.name}"',
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.sidebarColumnName,
                    labelStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: AppDesignSystem.space3),
                TextField(
                  controller: typeController,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.sidebarDataType,
                    labelStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 12,
                    ),
                    hintText: AppLocalizations.of(context)!.sidebarDataTypeHint,
                    hintStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space3),
                TextField(
                  controller: defaultController,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.sidebarDefaultValueOptional,
                    labelStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space3),
                Row(
                  children: [
                    Checkbox(
                      value: isNotNull,
                      activeColor: context.themeColors.accentBlue,
                      onChanged: (value) =>
                          setState(() => isNotNull = value ?? false),
                    ),
                    Text(
                      'NOT NULL',
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space4),
                    Checkbox(
                      value: isPrimaryKey,
                      activeColor: context.themeColors.warning,
                      onChanged: (value) =>
                          setState(() => isPrimaryKey = value ?? false),
                    ),
                    Text(
                      'PRIMARY KEY',
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.commonCancel),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    typeController.text.isEmpty) {
                  Navigator.pop(ctx);
                  return;
                }
                Navigator.pop(ctx);

                try {
                  final column = DbColumn(
                    name: nameController.text,
                    type: typeController.text.toUpperCase(),
                    isNullable: !isNotNull,
                    isPrimaryKey: isPrimaryKey,
                    defaultValue: defaultController.text.isNotEmpty
                        ? defaultController.text
                        : null,
                  );
                  final success = await provider.addColumn(
                    'main',
                    table.name,
                    column,
                  );
                  if (success) {
                    provider.invalidateDatabaseCache(connectionId, 'main');
                    provider.loadDatabaseInfo(connectionId, 'main');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context)!.sidebarColumnAdded(
                              nameController.text,
                              table.name,
                            ),
                          ),
                          backgroundColor: context.themeColors.success,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppErrorHandler.showErrorSnackBar(
                      context,
                      AppLocalizations.of(
                        context,
                      )!.addColumnFailed(e.toString()),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentBlue,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    ).then((_) {
      nameController.dispose();
      typeController.dispose();
      defaultController.dispose();
    });
  }

  void _showCreateIndexDialog(DbTable table) {
    final nameController = TextEditingController(text: 'idx_${table.name}_');
    final columnsController = TextEditingController();
    bool isUnique = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: context.themeColors.bgSecondary,
          title: Text(
            AppLocalizations.of(context)!.sidebarCreateIndexTitle(table.name),
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.sidebarIndexName,
                    labelStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: AppDesignSystem.space3),
                TextField(
                  controller: columnsController,
                  style: TextStyle(
                    color: context.themeColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(
                      context,
                    )!.sidebarIndexColumns,
                    labelStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 12,
                    ),
                    hintText: AppLocalizations.of(
                      context,
                    )!.sidebarIndexColumnsHint,
                    hintStyle: TextStyle(
                      color: context.themeColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space2),
                Text(
                  'Available columns: ${table.columns.map((c) => c.name).join(', ')}',
                  style: TextStyle(
                    color: context.themeColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: AppDesignSystem.space3),
                Row(
                  children: [
                    Checkbox(
                      value: isUnique,
                      activeColor: context.themeColors.warning,
                      onChanged: (value) =>
                          setState(() => isUnique = value ?? false),
                    ),
                    Text(
                      'UNIQUE',
                      style: TextStyle(
                        color: context.themeColors.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.commonCancel),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isEmpty ||
                    columnsController.text.isEmpty) {
                  Navigator.pop(ctx);
                  return;
                }
                Navigator.pop(ctx);

                try {
                  final cols = columnsController.text
                      .split(',')
                      .map((c) => c.trim())
                      .where((c) => c.isNotEmpty)
                      .toList();

                  final success = await provider.createIndex(
                    'main',
                    table.name,
                    nameController.text,
                    cols,
                    unique: isUnique,
                  );
                  if (success) {
                    provider.invalidateDatabaseCache(connectionId, 'main');
                    provider.loadDatabaseInfo(connectionId, 'main');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            AppLocalizations.of(context)!.sidebarIndexCreated(
                              nameController.text,
                              table.name,
                            ),
                          ),
                          backgroundColor: context.themeColors.success,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppErrorHandler.showErrorSnackBar(
                      context,
                      AppLocalizations.of(
                        context,
                      )!.createIndexFailed(e.toString()),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.themeColors.accentBlue,
              ),
              child: Text(AppLocalizations.of(context)!.sidebarCreate),
            ),
          ],
        ),
      ),
    ).then((_) {
      nameController.dispose();
      columnsController.dispose();
    });
  }

  Future<void> _showRenameTableDialog(DbTable table) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => RenameTableDialog(tableName: table.name),
    );

    if (newName != null && newName.isNotEmpty && newName != table.name) {
      try {
        final success = await provider.renameTable('main', table.name, newName);
        if (success) {
          provider.invalidateDatabaseCache(connectionId, 'main');
          provider.loadDatabaseInfo(connectionId, 'main');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(
                    context,
                  )!.renameSuccess(table.name, newName),
                ),
                backgroundColor: context.themeColors.success,
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            AppLocalizations.of(context)!.renameFailed(e.toString()),
          );
        }
      }
    }
  }

  Future<void> _showDropTableDialog(DbTable table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DropTableConfirmDialog(
        tableName: table.name,
        databaseName: 'main',
        provider: provider,
      ),
    );

    if (confirmed == true) {
      try {
        final success = await provider.dropTable('main', table.name);
        if (success) {
          provider.invalidateDatabaseCache(connectionId, 'main');
          provider.loadDatabaseInfo(connectionId, 'main');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.sidebarDropSuccess),
                backgroundColor: context.themeColors.success,
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          AppErrorHandler.showErrorSnackBar(
            context,
            AppLocalizations.of(context)!.dropTableFailed(e.toString()),
          );
        }
      }
    }
  }

  void _showTablesContextMenu(Database db, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'create_table',
          child: Row(
            children: [
              Icon(
                LucideIcons.plus,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarNewTable),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarRefresh),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'ai_import',
          child: Row(
            children: [
              Icon(
                LucideIcons.sparkles,
                size: 16,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'AI Smart Import',
                style: TextStyle(color: context.themeColors.accentPurple),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'import_sql',
          child: Row(
            children: [
              Icon(
                LucideIcons.fileUp,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarImportSQL),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleTablesAction(db, value);
    });
  }

  void _handleTablesAction(Database db, String action) {
    switch (action) {
      case 'create_table':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: AppLocalizations.of(context)!.sidebarNewTable,
          sql:
              'CREATE TABLE "new_table" (\n  id INTEGER PRIMARY KEY AUTOINCREMENT,\n  name TEXT NOT NULL\n);',
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'refresh':
        provider.invalidateDatabaseCache(connectionId, 'main');
        provider.loadDatabaseInfo(connectionId, 'main');
        break;
      case 'ai_import':
        _showSmartImportDialog();
        break;
      case 'import_sql':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: AppLocalizations.of(context)!.sidebarImportSQL,
          sql:
              '-- Paste your SQL here or use file picker to import\n-- Example: .read /path/to/file.sql',
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
    }
  }

  void _showSmartImportDialog() {
    AppLogger.i('SQLiteNodes', 'AI Smart Import triggered');

    if (!provider.tryDataImport(
      'data_import_${DateTime.now().millisecondsSinceEpoch}',
    )) {
      return;
    }

    final adapter = provider.connection.dbService.currentAdapter;

    if (adapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.pleaseConnectDatabase),
          backgroundColor: context.themeColors.warning,
        ),
      );
      return;
    }

    // open-core Phase B.2：Smart Import 向导经 ProImportUi SPI 注入
    // （OSS=NoOp，门禁已拦截，此处兜底 no-op）。
    unawaited(
      context.read<ProImportUi>().openImportWizard(
        context,
        connectionId: connectionId,
        initialDatabase: 'main',
        adapter: adapter,
        aiClient: AiService().client,
      ),
    );
  }

  void _showColumnContextMenu(
    String tableName,
    DbColumn column,
    Offset position,
  ) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'copy_name',
          child: Row(
            children: [
              Icon(
                LucideIcons.copy,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Copy Name'),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'copy_type',
          child: Row(
            children: [
              Icon(
                LucideIcons.copy,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Copy Type'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'view_structure',
          child: Row(
            children: [
              Icon(
                LucideIcons.network,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarViewStructure),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'drop_column',
          child: Row(
            children: [
              Icon(
                LucideIcons.trash2,
                size: 16,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                AppLocalizations.of(context)!.dropColumn,
                style: TextStyle(color: context.themeColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleColumnAction(tableName, column, value);
    });
  }

  Future<void> _handleColumnAction(
    String tableName,
    DbColumn column,
    String action,
  ) async {
    switch (action) {
      case 'copy_name':
        Clipboard.setData(ClipboardData(text: column.name));
        break;
      case 'copy_type':
        Clipboard.setData(ClipboardData(text: column.type));
        break;
      case 'view_structure':
        provider.setSelectedTable(tableName);
        break;
      case 'drop_column':
        try {
          final success = await provider.dropColumn(
            'main',
            tableName,
            column.name,
          );
          if (success) {
            provider.invalidateDatabaseCache(connectionId, 'main');
            provider.loadDatabaseInfo(connectionId, 'main');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Column "${column.name}" dropped from "$tableName"',
                  ),
                  backgroundColor: context.themeColors.success,
                ),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              AppLocalizations.of(context)!.dropColumnFailed(e.toString()),
            );
          }
        }
        break;
    }
  }

  void _showIndexContextMenu(DbIndex index, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'copy_name',
          child: Row(
            children: [
              Icon(
                LucideIcons.copy,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Copy Name'),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'view_create',
          child: Row(
            children: [
              Icon(
                LucideIcons.network,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.createStatement),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'rebuild',
          child: Row(
            children: [
              Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Rebuild Index'),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'drop',
          child: Row(
            children: [
              Icon(
                LucideIcons.trash2,
                size: 16,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                AppLocalizations.of(context)!.dropIndex,
                style: TextStyle(color: context.themeColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleIndexAction(index, value);
    });
  }

  Future<void> _handleIndexAction(DbIndex index, String action) async {
    switch (action) {
      case 'copy_name':
        Clipboard.setData(ClipboardData(text: index.name));
        break;
      case 'view_create':
        final uniqueStr = index.isUnique ? 'UNIQUE ' : '';
        final sql =
            'CREATE ${uniqueStr}INDEX "${index.name}" ON "table_name" (${index.columns.map((c) => '"$c"').join(', ')});';
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: '${index.name}_create',
          sql: sql,
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'rebuild':
        try {
          await provider.connection.dbService.executeQuery(
            'REINDEX "${index.name}";',
          );
          provider.invalidateDatabaseCache(connectionId, 'main');
          provider.loadDatabaseInfo(connectionId, 'main');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(context)!.sidebarIndexRebuilt(index.name),
                ),
                backgroundColor: context.themeColors.success,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              AppLocalizations.of(
                context,
              )!.sidebarRebuildIndexFailed(e.toString()),
            );
          }
        }
        break;
      case 'drop':
        try {
          final success = await provider.dropIndex('main', '', index.name);
          if (success) {
            provider.invalidateDatabaseCache(connectionId, 'main');
            provider.loadDatabaseInfo(connectionId, 'main');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(
                      context,
                    )!.sidebarIndexDropped(index.name),
                  ),
                  backgroundColor: context.themeColors.success,
                ),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              AppLocalizations.of(context)!.dropIndexFailed(e.toString()),
            );
          }
        }
        break;
    }
  }

  void _showViewsContextMenu(Database db, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'create_view',
          child: Row(
            children: [
              Icon(
                LucideIcons.plus,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Create View'),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarRefresh),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleViewsAction(db, value);
    });
  }

  Future<void> _handleViewsAction(Database db, String action) async {
    switch (action) {
      case 'create_view':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: 'New View',
          sql: 'CREATE VIEW "new_view" AS\nSELECT * FROM "table_name";',
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'refresh':
        provider.invalidateDatabaseCache(connectionId, 'main');
        provider.loadDatabaseInfo(connectionId, 'main');
        break;
    }
  }

  void _showIndexesContextMenu(Database db, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'create_index',
          child: Row(
            children: [
              Icon(
                LucideIcons.plus,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarCreateNewIndex),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarRefresh),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleIndexesAction(db, value);
    });
  }

  Future<void> _handleIndexesAction(Database db, String action) async {
    switch (action) {
      case 'create_index':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: 'New Index',
          sql: 'CREATE INDEX "new_index" ON "table_name" ("column_name");',
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'refresh':
        provider.invalidateDatabaseCache(connectionId, 'main');
        provider.loadDatabaseInfo(connectionId, 'main');
        break;
    }
  }

  // ==========================================================================
  // spec 050：ATTACH 跨库——数据库 header 右键菜单 + Detach handler
  // ==========================================================================

  /// 多库场景下数据库 header 节点的右键菜单。
  /// - main header：显示「Attach Database…」
  /// - 附加库 header：显示「Detach」
  void _showDatabaseHeaderContextMenu(String alias, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    final isMain = alias == 'main';
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        if (isMain)
          CompactPopupMenuItem(
            value: 'attach',
            child: Row(
              children: [
                Icon(
                  LucideIcons.link,
                  size: 16,
                  color: context.themeColors.accentGreen,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(l10n.sqliteAttachDatabase),
              ],
            ),
          )
        else
          CompactPopupMenuItem(
            value: 'detach',
            child: Row(
              children: [
                Icon(
                  LucideIcons.unlink,
                  size: 16,
                  color: context.themeColors.warning,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  l10n.sqliteDetach,
                  style: TextStyle(color: context.themeColors.warning),
                ),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == null) return;
      if (value == 'attach') {
        _showAttachDialog();
      } else if (value == 'detach') {
        _detachDatabase(alias);
      }
    });
  }

  /// 弹出 Attach Database 对话框（与能力菜单同流程：showSqliteAttachFlow）。
  Future<void> _showAttachDialog() =>
      showSqliteAttachFlow(context, provider, connectionId);

  /// 执行 DETACH + SnackBar 反馈。
  Future<void> _detachDatabase(String alias) async {
    final l10n = AppLocalizations.of(context)!;
    final res = await provider.connection.detachDatabase(connectionId, alias);
    if (!context.mounted) return;
    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sqliteDetachSuccess(alias)),
          backgroundColor: context.themeColors.success,
        ),
      );
    } else {
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.sqliteDetachFailed(res.errorDetail ?? ''),
      );
    }
  }

  void _showDatabaseInfoContextMenu(String dbPath, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        // spec 050：Attach Database…（单库扁平场景的入口）
        CompactPopupMenuItem(
          value: 'attach',
          child: Row(
            children: [
              Icon(
                LucideIcons.link,
                size: 16,
                color: context.themeColors.accentGreen,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.sqliteAttachDatabase),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              Icon(
                LucideIcons.copy,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.sqliteCopyFilePath),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'open_folder',
          child: Row(
            children: [
              Icon(
                LucideIcons.folderOpen,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.sqliteOpenInFolder),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'toggle_wal',
          child: Row(
            children: [
              Icon(
                LucideIcons.arrowRightLeft,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.sqliteToggleWalMode),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'optimize',
          child: Row(
            children: [
              Icon(
                LucideIcons.gauge,
                size: 16,
                color: context.themeColors.accentBlue,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.sqliteOptimizeDatabase,
                style: TextStyle(color: context.themeColors.accentBlue),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'vacuum',
          child: Row(
            children: [
              Icon(
                LucideIcons.database,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.sqliteVacuum),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'integrity_check',
          child: Row(
            children: [
              Icon(
                LucideIcons.badgeCheck,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.sqliteIntegrityCheck),
            ],
          ),
        ),
        const PopupMenuDivider(),
        CompactPopupMenuItem(
          value: 'pragma_explorer',
          child: Row(
            children: [
              Icon(
                LucideIcons.slidersHorizontal,
                size: 16,
                color: context.themeColors.accentBlue,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.pragmaExplorerTitle),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'save_as',
          child: Row(
            children: [
              Icon(
                LucideIcons.saveAll,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(l10n.sqliteSaveAs),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleDatabaseInfoAction(dbPath, value);
    });
  }

  void _handleDatabaseInfoAction(String dbPath, String action) {
    switch (action) {
      case 'attach':
        _showAttachDialog();
        break;
      case 'copy_path':
        Clipboard.setData(ClipboardData(text: dbPath));
        break;
      case 'open_folder':
        _openFileFolder(dbPath);
        break;
      case 'vacuum':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: 'VACUUM',
          sql: 'VACUUM;',
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'integrity_check':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: 'Integrity Check',
          sql: 'PRAGMA integrity_check;',
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'toggle_wal':
        _showWalModeDialog();
        break;
      case 'optimize':
        _optimizeDatabase();
        break;
      case 'pragma_explorer':
        PragmaExplorerDialog.show(
          context,
          provider: provider,
          connectionId: connectionId,
        );
        break;
      case 'save_as':
        _saveDatabaseAs(dbPath);
        break;
    }
  }

  /// 右键 → Save As…：弹系统文件保存对话框 → VACUUM INTO 复制源库到新路径。
  ///
  /// VACUUM INTO 事务一致、WAL 模式也安全（合并 -wal 已提交事务）、产出干净
  /// DELETE 模式单文件。源库不受影响 → 只读连接也能导出副本。
  Future<void> _saveDatabaseAs(String srcPath) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: l10n.sqliteSaveAs,
        fileName: srcPath.split(Platform.pathSeparator).last,
        type: FileType.custom,
        allowedExtensions: const ['db', 'sqlite', 'sqlite3'],
      );
      if (result == null) return; // 用户取消

      String destPath = result;
      // 桌面端 saveFile 不总是加扩展名，手动补全
      if (!destPath.endsWith('.db') &&
          !destPath.endsWith('.sqlite') &&
          !destPath.endsWith('.sqlite3')) {
        destPath = '$destPath.db';
      }

      // 覆盖保护：FilePicker.saveFile 在桌面端可能不拦截已存在文件
      if (await File(destPath).exists()) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.sidebarSaveAsExists(destPath)),
            backgroundColor: context.themeColors.warning,
          ),
        );
        return;
      }

      // C16：经 dbService.saveDatabaseAs（服务层收编，UI 不再 cast adapter）。
      // 非 SQLite 连接的失败文案与旧直连路径逐字保持。
      try {
        await provider.connection.dbService.saveDatabaseAs(
          connectionId,
          destPath,
        );
      } on UnsupportedError {
        if (!context.mounted) return;
        AppErrorHandler.showErrorSnackBar(
          context,
          l10n.sidebarSaveAsFailed('Not a SQLite connection'),
        );
        return;
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sidebarSaveAsSuccess(destPath)),
          backgroundColor: context.themeColors.success,
        ),
      );
    } catch (e) {
      AppLogger.e('SQLiteTreeBuilder', 'Save As failed', e);
      if (!context.mounted) return;
      AppErrorHandler.showErrorSnackBar(
        context,
        l10n.sidebarSaveAsFailed(e.toString()),
      );
    }
  }

  Future<void> _openFileFolder(String filePath) async {
    await openDirectoryInFileManager(File(filePath).parent.path);
  }

  void _showViewContextMenu(String viewName, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'browse',
          child: Row(
            children: [
              Icon(
                LucideIcons.eye,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarBrowseData),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'copy_create',
          child: Row(
            children: [
              Icon(
                LucideIcons.copy,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Copy CREATE Statement'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'drop',
          child: Row(
            children: [
              Icon(
                LucideIcons.trash2,
                size: 16,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'Drop View',
                style: TextStyle(color: context.themeColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleViewAction(viewName, value);
    });
  }

  Future<void> _handleViewAction(String viewName, String action) async {
    switch (action) {
      case 'browse':
        // spec 041 US2: 走 openBrowseDataTab（顺带修硬编码方言）
        provider.openBrowseDataTab(
          connectionId,
          'main',
          viewName,
          isView: true,
        );
        break;
      case 'copy_create':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: '${viewName}_create',
          sql:
              '-- View CREATE statement requires querying sqlite_master\n'
              "SELECT sql FROM sqlite_master WHERE type='view' AND name='${viewName.replaceAll("'", "''")}';",
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'drop':
        try {
          await provider.connection.dbService.executeQuery(
            'DROP VIEW IF EXISTS "$viewName";',
          );
          provider.invalidateDatabaseCache(connectionId, 'main');
          provider.loadDatabaseInfo(connectionId, 'main');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('View "$viewName" dropped successfully'),
                backgroundColor: context.themeColors.success,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              AppLocalizations.of(context)!.sidebarDropViewFailed(e.toString()),
            );
          }
        }
        break;
    }
  }

  void _showTriggersContextMenu(Database db, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'create_trigger',
          child: Row(
            children: [
              Icon(
                LucideIcons.plus,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Create Trigger'),
            ],
          ),
        ),
        CompactPopupMenuItem(
          value: 'refresh',
          child: Row(
            children: [
              Icon(
                LucideIcons.refreshCw,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(AppLocalizations.of(context)!.sidebarRefresh),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleTriggersAction(db, value);
    });
  }

  Future<void> _handleTriggersAction(Database db, String action) async {
    switch (action) {
      case 'create_trigger':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: 'New Trigger',
          sql:
              'CREATE TRIGGER "trigger_name"\n'
              'BEFORE INSERT ON "table_name"\n'
              'BEGIN\n'
              '  -- trigger logic here\n'
              'END;',
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'refresh':
        provider.invalidateDatabaseCache(connectionId, 'main');
        provider.loadDatabaseInfo(connectionId, 'main');
        break;
    }
  }

  void _showTriggerContextMenu(DbTrigger trigger, Offset position) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: context.themeColors.bgTertiary,
      items: [
        CompactPopupMenuItem(
          value: 'copy_create',
          child: Row(
            children: [
              Icon(
                LucideIcons.copy,
                size: 16,
                color: context.themeColors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text('Copy CREATE Statement'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        CompactPopupMenuItem(
          value: 'drop',
          child: Row(
            children: [
              Icon(
                LucideIcons.trash2,
                size: 16,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                'Drop Trigger',
                style: TextStyle(color: context.themeColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      _handleTriggerAction(trigger, value);
    });
  }

  Future<void> _handleTriggerAction(DbTrigger trigger, String action) async {
    switch (action) {
      case 'copy_create':
        final tab = QueryTab(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          title: '${trigger.name}_create',
          sql: trigger.statement ?? '-- CREATE statement not available',
          connectionId: connectionId,
          databaseName: 'main',
        );
        provider.addTab(tab);
        break;
      case 'drop':
        try {
          await provider.connection.dbService.executeQuery(
            'DROP TRIGGER IF EXISTS "${trigger.name}";',
          );
          provider.invalidateDatabaseCache(connectionId, 'main');
          provider.loadDatabaseInfo(connectionId, 'main');
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Trigger "${trigger.name}" dropped successfully'),
                backgroundColor: context.themeColors.success,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            AppErrorHandler.showErrorSnackBar(
              context,
              AppLocalizations.of(
                context,
              )!.sidebarDropTriggerFailed(e.toString()),
            );
          }
        }
        break;
    }
  }

  Future<void> _showWalModeDialog() async {
    try {
      final rows = await provider.connection.dbService.executeQuery(
        'PRAGMA journal_mode;',
        connectionId: connectionId,
      );
      final currentMode = rows.isNotEmpty
          ? rows.first.values.first?.toString() ?? 'DELETE'
          : 'DELETE';

      if (!context.mounted) return;

      final newMode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.themeColors.bgSecondary,
          title: Text(
            'Journal Mode',
            style: TextStyle(color: context.themeColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current mode: $currentMode',
                style: TextStyle(color: context.themeColors.textSecondary),
              ),
              const SizedBox(height: AppDesignSystem.space4),
              Text(
                'WAL mode provides better concurrency but requires proper checkpointing.\n'
                'DELETE mode is more compatible and the current default.',
                style: TextStyle(
                  color: context.themeColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.commonCancel),
            ),
            if (currentMode.toUpperCase() != 'WAL')
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'WAL'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeColors.accentBlue,
                ),
                child: const Text('Switch to WAL'),
              )
            else
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, 'DELETE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.themeColors.warning,
                ),
                child: const Text('Switch to DELETE'),
              ),
          ],
        ),
      );

      if (newMode != null) {
        await provider.connection.dbService.executeQuery(
          'PRAGMA journal_mode=$newMode;',
          connectionId: connectionId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Journal mode switched to $newMode'),
              backgroundColor: context.themeColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.sidebarToggleWalFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _optimizeDatabase() async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Optimizing database...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Step 1: ANALYZE
      await provider.connection.dbService.executeQuery(
        'ANALYZE;',
        connectionId: connectionId,
      );

      // Step 2: REINDEX
      await provider.connection.dbService.executeQuery(
        'REINDEX;',
        connectionId: connectionId,
      );

      // Step 3: VACUUM
      await provider.connection.dbService.executeQuery(
        'VACUUM;',
        connectionId: connectionId,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Database optimized successfully (ANALYZE + REINDEX + VACUUM)',
            ),
            backgroundColor: context.themeColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.sidebarOptimizeDbFailed(e.toString()),
        );
      }
    }
  }
}
