// C18 · TDengine 侧边栏插件 —— 库级树迁入（自 sidebar_tree.dart 内联段抽出，
// 顺手消债：原注释「extraction deferred — risky refactor with no live
// TDengine」由 C18 插件框架落地）。
//
// 树装配：库级对象子树 = SuperTables 分类 → SuperTable 叶子（badge
// "N cols, M tags"，首展开懒加载 detail）→ Columns/Tags 分组 + 列/标签
// 叶子。连接级全局节点恒空——刻意省略 server 级节点（dnodes/mnodes/
// cluster：adapter 仅暴露 getServerVersion，见下「Deliberately omits」）。
//
// 能力菜单（capabilityGroups）：恒空（C17 Mongo 同款裁定——TD 连接级无
// 真实独立入口：Browse/Delete SuperTable 是树内右键、Create SuperTable
// 是库菜单共享门控项，均随树/宿主菜单保留）。
//
// 文案：树内标签与删除确认已 l10n 化（C22-0，原 C18 迁入时硬编码英文）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../molecules/context_menu.dart';
import '../../../models/database_models.dart' hide QueryTab;
import '../../../models/tdengine_models.dart';
import '../../../organisms/connection/error_boundary.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/tab_provider.dart';
import '../../../theme/app_theme.dart';
import '../builders/tree_utils.dart';
import '../tree_item.dart';

// ── Capability Coverage (TDengine) ───────────────────────────────
// Surfaces (decided product features):
//   - SuperTables (expandable → Columns + Tags)
//   - SuperTable double-click browse + right-click context menu (Create/Delete SuperTable)
//   - Connection-level Create SuperTable / Create Database
// Deliberately omits (not a decided feature / not yet surfaced):
//   - Server-level nodes (dnodes/mnodes/cluster) — TDengine adapter exposes only
//     getServerVersion; richer server status not surfaced (revisit if requested)
//   - kill-process / replication / charset — N/A for TDengine
// ─────────────────────────────────────────────────────────────────
class TdengineSidebarPlugin implements SidebarPlugin {
  const TdengineSidebarPlugin();

  @override
  PluginDescriptor get descriptor => const PluginDescriptor(
        id: 'tdengine-sidebar',
        supportedTypes: {DatabaseType.tdengine},
        source: PluginSource.databaseType,
        icon: LucideIcons.database,
      );

  @override
  List<SidebarCapabilityGroup> capabilityGroups(BuildContext context) {
    // 恒空裁定：连接级无真实独立入口（同 MongodbSidebarPlugin 先例）。
    return const [];
  }

  @override
  List<Widget> buildGlobalTree(BuildContext context, SidebarTreeContext tree) {
    // 刻意省略 server 级节点（见文件头 Capability Coverage 注记）。
    return const [];
  }

  @override
  List<Widget> buildDatabaseTree(
    BuildContext context,
    SidebarDatabaseTreeContext db,
  ) {
    return _TdDatabaseNodes(
      context: context,
      provider: db.provider,
      connectionId: db.connectionId,
      databaseName: db.databaseName,
      searchQuery: db.searchQuery,
      expandedItems: db.expandedItems,
      onToggleExpand: db.onToggleExpand,
      expandedTables: db.expandedTables,
      onToggleTable: db.onToggleTable,
      onRightClickTargetChanged: db.onRightClickTargetChanged,
    ).build();
  }
}

/// TDengine 库级对象树装配（自 sidebar_tree.dart `_buildTDengineNodes`
/// 内联段逐行迁入）。展开键契约保持：分类 `cid:db:super_tables` 走
/// expandedItems，超级表明细 `cid:db:name` 走 expandedTables。
class _TdDatabaseNodes {
  final BuildContext context;
  final AppProvider provider;
  final String connectionId;
  final String databaseName;
  final String searchQuery;
  final Set<String> expandedItems;
  final void Function(String key) onToggleExpand;
  final Set<String> expandedTables;
  final void Function(String key) onToggleTable;
  final void Function(String? key)? onRightClickTargetChanged;

  _TdDatabaseNodes({
    required this.context,
    required this.provider,
    required this.connectionId,
    required this.databaseName,
    required this.searchQuery,
    required this.expandedItems,
    required this.onToggleExpand,
    required this.expandedTables,
    required this.onToggleTable,
    this.onRightClickTargetChanged,
  });

  List<Widget> build() {
    final l10n = AppLocalizations.of(context)!;
    final nodes = <Widget>[];
    final superTables = provider.getSuperTables(connectionId, databaseName);
    final isLoading = provider.isLoadingSuperTables(connectionId, databaseName);

    // SuperTables 节点
    final stExpandKey = '$connectionId:$databaseName:super_tables';
    final isStExpanded = expandedItems.contains(stExpandKey);

    // 渲染门：子树唯一数据源是 provider 的 SuperTables 缓存，而它此前
    // 仅由库节点鼠标展开 wrapper 填充——键盘展开、tab 恢复 changeDatabase、
    // 右键刷新等路径绕过 wrapper 时缓存恒 null，分类节点展开永远为空
    // （「无法展开」现场）。故 onTap 展开时自行拉取（对齐库/schema 节点
    // 「展开即重查」语义；loadSuperTables 自带 in-flight 守卫）。
    nodes.add(
      TreeItem(
        level: 3,
        icon: LucideIcons.table2,
        iconColor: context.themeColors.accentPurple,
        label: l10n.sidebarSuperTables,
        badge: superTables?.length.toString(),
        isExpanded: isStExpanded,
        isLoading: isLoading,
        onTap: () {
          final willExpand = !expandedItems.contains(stExpandKey);
          onToggleExpand(stExpandKey);
          if (willExpand) {
            provider.loadSuperTables(connectionId, databaseName);
          }
        },
      ),
    );

    if (isStExpanded && superTables != null) {
      final filtered = superTables
          .where(
            (st) =>
                searchQuery.isEmpty ||
                st.name.toLowerCase().contains(searchQuery),
          )
          .toList();

      for (final st in filtered) {
        final stKey = '$connectionId:$databaseName:${st.name}';
        final isStDetailExpanded = expandedTables.contains(stKey);
        final hasDetail = st.columns.isNotEmpty || st.tags.isNotEmpty;

        nodes.add(
          TreeItem(
            level: 4,
            icon: LucideIcons.folderBookmark,
            iconColor: context.themeColors.accentPurple,
            label: st.name,
            badge: hasDetail
                ? l10n.sidebarTdColsTags(st.columns.length, st.tags.length)
                : null,
            isExpanded: isStDetailExpanded,
            showArrow: true,
            onTap: () {
              final willExpand = !expandedTables.contains(stKey);
              onToggleTable(stKey);
              if (willExpand && !hasDetail) {
                provider.loadSuperTableDetail(
                  connectionId,
                  databaseName,
                  st.name,
                );
              }
            },
            onDoubleTap: () => browseSuperTableData(
              context,
              provider,
              connectionId,
              databaseName,
              st,
            ),
            onContextMenu: (position) {
              onRightClickTargetChanged?.call(
                'table:$connectionId:$databaseName:${st.name}',
              );
              showSuperTableContextMenu(
                context,
                provider,
                connectionId,
                databaseName,
                st,
                position,
              ).then((_) => onRightClickTargetChanged?.call(null));
            },
          ),
        );

        if (isStDetailExpanded) {
          // 列信息
          if (st.columns.isNotEmpty) {
            nodes.add(
              TreeItem(
                level: 5,
                icon: LucideIcons.columns2,
                iconColor: context.themeColors.textSecondary,
                label: l10n.sidebarTdColumnsCount(st.columns.length),
                showArrow: false,
                onTap: () {},
              ),
            );
            for (final col in st.columns) {
              final (colIcon, colColor) = getColumnIconInfo(col.type);
              nodes.add(
                TreeItem(
                  level: 6,
                  icon: colIcon,
                  iconColor: colColor,
                  label:
                      '${col.name}  ${col.type}${col.isPrimaryKey ? " [PK]" : ""}',
                  showArrow: false,
                  onTap: () {},
                ),
              );
            }
          }

          // 标签信息
          if (st.tags.isNotEmpty) {
            nodes.add(
              TreeItem(
                level: 5,
                icon: LucideIcons.tag,
                iconColor: context.themeColors.brandColor(
                  DatabaseType.tdengine,
                ),
                label: l10n.sidebarTdTagsCount(st.tags.length),
                showArrow: false,
                onTap: () {},
              ),
            );
            for (final tag in st.tags) {
              final tagColor = getTagTypeColor(tag.type);
              nodes.add(
                TreeItem(
                  level: 6,
                  icon: LucideIcons.tag,
                  iconColor: tagColor,
                  label: '${tag.name}  ${tag.type}',
                  showArrow: false,
                  onTap: () {},
                ),
              );
            }
          }
        }
      }
    }

    return nodes;
  }
}

/// SuperTable 双击 / 右键 Browse Data 共用路径（原内联段两处重复逻辑合并，
/// 行为一致：切连接+切库 → 预填 SELECT cols FROM st LIMIT 100 查询 tab）。
Future<void> browseSuperTableData(
  BuildContext context,
  AppProvider provider,
  String connectionId,
  String databaseName,
  TdSuperTable superTable,
) async {
  final l10n = AppLocalizations.of(context)!;
  try {
    await provider.switchToConnection(connectionId);
    await provider.changeDatabase(databaseName, connectionId: connectionId);

    final columns = superTable.columns.isNotEmpty
        ? superTable.columns.map((c) => c.name).join(', ')
        : '*';
    final sql = 'SELECT $columns\nFROM ${superTable.name}\nLIMIT 100;';

    final tab = QueryTab(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      title: l10n.queryTable(superTable.name),
      sql: sql,
      connectionId: connectionId,
      databaseName: databaseName,
      isAutoTitle: true,
    );
    provider.addTab(tab);
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

// ========== TDengine 上下文菜单 ==========

Future<void> showSuperTableContextMenu(
  BuildContext context,
  AppProvider provider,
  String connectionId,
  String databaseName,
  TdSuperTable superTable,
  Offset position,
) async {
  await ContextMenuUtils.show(
    context: context,
    position: position,
    items: [
      ContextMenuItem(
        id: 'browse_data',
        label: AppLocalizations.of(context)!.sidebarBrowseData,
        icon: LucideIcons.table2,
        onTap: () => browseSuperTableData(
          context,
          provider,
          connectionId,
          databaseName,
          superTable,
        ),
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        id: 'delete',
        label: AppLocalizations.of(context)!.sidebarTdDeleteTitle,
        icon: LucideIcons.trash2,
        isDestructive: true,
        onTap: () => dropSuperTable(
          context,
          provider,
          connectionId,
          databaseName,
          superTable.name,
        ),
      ),
    ],
  );
}

void dropSuperTable(
  BuildContext context,
  AppProvider provider,
  String connectionId,
  String databaseName,
  String superTableName,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Text(
        AppLocalizations.of(context)!.sidebarTdDeleteTitle,
        style: TextStyle(color: context.themeColors.textPrimary),
      ),
      content: Text(
        AppLocalizations.of(context)!.sidebarTdDeleteConfirm(superTableName),
        style: TextStyle(color: context.themeColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(AppLocalizations.of(context)!.commonCancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.error,
          ),
          child: Text(AppLocalizations.of(context)!.commonDelete),
        ),
      ],
    ),
  );

  if (confirm == true) {
    try {
      await provider.dropSuperTable(connectionId, databaseName, superTableName);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              )!.sidebarSuperTableDeleted(superTableName),
            ),
            backgroundColor: context.themeColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppErrorHandler.showErrorSnackBar(
          context,
          AppLocalizations.of(context)!.sidebarDeleteFailed(e.toString()),
        );
      }
    }
  }
}
