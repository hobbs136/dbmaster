// C19 · 泛 SQL 库级对象树 —— core 插件的共享兜底树（自 sidebar_tree.dart
// `_buildDatabaseObjects` 逐行迁入，2026-08-19 旧框架下线）。
//
// 服务对象：库级树恒空的 per-type 插件类型（MySQL/Doris 走各自全局树 +
// 本共享树；ClickHouse 无 per-type 插件）+ 未来仅做 gateway-backed UI 的
// 新 SQL 类型（铁律 7：新类型不写 adapter 分支，天然落本树）。
//
// 分缝契约：`SidebarPlugin.buildDatabaseTree` 遍历序为 per-type 先、core
// 殿后（C19 反转）——PG/Mongo/TD/SS 的 per-type 库级树非空即接管，本树只在
// per-type 全空时兜底。
//
// 渲染内容（数据驱动，无类型分支）：Tables（行数徽章/拖拽/列扁平叶子）/
// Views / Materialized Views / Procedures（函数折入）/ Triggers / Events
// 六分类，分类可见性由 `DatabaseType` 能力 getter 裁决（§3.5.1 等价守卫
// 锚定的存量声明面）。菜单路由经 SidebarDatabaseTreeContext 回调透传，
// 本文件零 adapter import（铁律 3）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/database_models.dart';
import '../../../models/drag_models.dart';
import '../../../plugins/sidebar_plugin.dart';
import '../../../providers/app_provider.dart';
import '../../../services/trigger_service.dart';
import '../../../theme/app_colors.dart';
import '../../connection/definition_view_dialog.dart';
import '../../connection/error_boundary.dart' show AppErrorHandler;
import '../../../molecules/context_menu.dart';
import '../builders/tree_utils.dart';
import '../tree_item.dart';

/// 泛 SQL 库级对象树（CoreSidebarPlugin.buildDatabaseTree 的树装配实现）。
List<Widget> buildGenericSqlDatabaseTree(
  BuildContext context,
  SidebarDatabaseTreeContext c,
) {
  final type = c.server.type;
  // 非 SQL 类型防御排除（Redis/SQLite 连接级整树、Mongo/TD 有专属插件——
  // 正常分缝不会落到这里，返回空即回退宿主）。SS schema 树由 C20
  // per-type 插件接管（SqlserverSidebarPlugin 非空即先行），无需在此排除。
  if (!type.isSQL) return const [];

  final provider = c.provider;
  final connectionId = c.connectionId;
  final databaseName = c.databaseName;
  final db = c.db;
  final l10n = AppLocalizations.of(context)!;
  final widgets = <Widget>[];
  final sq = c.searchQuery.toLowerCase();

  bool isNodeSelected(String nodeKey) =>
      c.selectedNodeKey == nodeKey || c.rightClickedNodeKey == nodeKey;

  // Tables
  if (db.tables.isNotEmpty) {
    final filteredTables = sq.isEmpty
        ? db.tables
        : db.tables.where((t) => t.name.toLowerCase().contains(sq)).toList();
    if (filteredTables.isNotEmpty) {
      final key = '$connectionId:$databaseName:tables';
      // #6 Tables 改为可折叠、默认收起，与 Views/Procedures/Triggers/Events 一致（chevron 诚实）。
      final expanded = sq.isNotEmpty || c.expandedItems.contains(key);
      widgets.add(
        TreeItem(
          level: 3,
          icon: LucideIcons.table2,
          iconColor: context.themeColors.accentBlue,
          label:
              '${l10n.sidebarTables} (${filteredTables.length}${sq.isNotEmpty && filteredTables.length != db.tables.length ? "/${db.tables.length}" : ""})',
          isExpanded: expanded,
          isSelected: isNodeSelected('cat:$connectionId:$databaseName:tables'),
          onTap: () {
            // 仅在展开时加载行数（收起不触发）
            final willExpand = !expanded;
            c.onToggleExpand(key);
            if (willExpand) {
              c.onLoadTableRowCounts?.call(connectionId, databaseName);
            }
          },
          // T031/FR-014 — Tables category header menu (Create + Refresh)
          onContextMenu: (pos) =>
              c.onShowCategoryMenu?.call(pos, true, null),
        ),
      );
      if (expanded) {
        for (final table in filteredTables) {
          final tk = '$connectionId:$databaseName:${table.name}';
          final te = c.expandedTables.contains(tk);
          final schema = c.loadedTableSchemas[tk];
          final loading = c.loadingTableSchemas.contains(tk);
          final rowCountKey = '$connectionId:$databaseName:${table.name}';
          final rowCount = c.tableRowCounts[rowCountKey];
          final rowBadge = rowCount != null ? _formatRowCount(rowCount) : null;
          final dragData = TableDragData(
            tableName: table.name,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
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
                        '${c.server.name}.${table.name}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.4,
                child: _tableLeaf(
                  context,
                  c,
                  isNodeSelected,
                  table.name,
                  tk,
                  te,
                  loading,
                  rowBadge,
                ),
              ),
              child: _tableLeaf(
                context,
                c,
                isNodeSelected,
                table.name,
                tk,
                te,
                loading,
                rowBadge,
              ),
            ),
          ); // widgets.add(Draggable()
          if (te && schema != null) {
            // 列扁平（无 Columns 组头）+ 交互式叶子（双击插入、右键复制），共享 helper
            widgets.addAll(
              buildInteractiveTableSchemaLeaves(
                context: context,
                schema: schema,
                foreignKeys:
                    c.loadedTableForeignKeys[tk] ?? const <ForeignKey>[],
                indexesLabel: l10n.sidebarIndexes,
                foreignKeysLabel: l10n.sidebarForeignKeys,
                colKeyOf: (col) =>
                    'col:$connectionId:$databaseName:${table.name}:${col.name}',
                idxKeyOf: (idx) =>
                    'idx:$connectionId:$databaseName:${table.name}:${idx.name}',
                fkKeyOf: (fk) =>
                    'fk:$connectionId:$databaseName:${table.name}:${fk.name}',
                isSelected: isNodeSelected,
                onSelect: (key) => c.onSelectNode?.call(key),
                onInsert: c.onInsertName,
                onColumnMenu: (pos, col) =>
                    c.onShowColumnMenu?.call(context, schema, col, pos),
                onIndexMenu: (pos, idx) => c.onShowIndexMenu?.call(
                  idx,
                  '', // T063 — MySQL has no schema concept; bare names.
                  table.name,
                  schema.columns,
                  pos,
                ),
                onFkMenu: (pos, fk) => c.onShowFkMenu?.call(fk, pos),
              ),
            );
          } else if (te && loading) {
            widgets.add(_loadingNode(context));
          }
        }
      }
    }
  }

  // Views
  // 即使 Views 列表为空也渲染分类节点（显示 "(0)"），使 Create View 菜单可达
  if (type.supportsViews) {
    final filteredViews = sq.isEmpty
        ? db.views
        : db.views.where((v) => v.toLowerCase().contains(sq)).toList();
    if (filteredViews.isNotEmpty || sq.isEmpty) {
      final key = '$connectionId:$databaseName:views';
      final expanded = sq.isNotEmpty || c.expandedItems.contains(key);
      widgets.add(
        TreeItem(
          level: 3,
          icon: LucideIcons.eye,
          iconColor: context.themeColors.accentBlue,
          label:
              '${l10n.sidebarViews} (${filteredViews.length}${sq.isNotEmpty && filteredViews.length != db.views.length ? "/${db.views.length}" : ""})',
          isExpanded: expanded,
          isSelected: isNodeSelected('cat:$connectionId:$databaseName:views'),
          onTap: () => c.onToggleExpand(key),
          // T032/FR-014 — Views category header menu (Create + Refresh)
          onContextMenu: (pos) =>
              c.onShowCategoryMenu?.call(pos, false, 'view'),
        ),
      );
      if (expanded) {
        for (final v in filteredViews) {
          // T036/FR-015 — single-click opens (was no-op), per Q4.
          void openView() {
            // 单击/双击视图 → query 编辑器（预填默认浏览查询，不自动执行）；
            // data 模式仅右键「浏览数据」进入
            provider.openTableQueryTab(connectionId, databaseName, v);
          }

          widgets.add(
            TreeItem(
              level: 4,
              icon: LucideIcons.eye,
              iconColor: context.themeColors.textSecondary,
              iconSize: 12,
              label: v,
              showArrow: false,
              isSelected: isNodeSelected('view:$connectionId:$databaseName:$v'),
              onTap: openView,
              onDoubleTap: openView,
              onContextMenu: (pos) =>
                  c.onShowViewMenu?.call(v, pos, false),
            ),
          );
        }
      }
    }
  }

  // Materialized Views (PostgreSQL, Doris)
  // 即使 MV 列表为空也渲染分类节点（显示 "(0)"），使 Create MV 菜单可达
  if (type.supportsMaterializedViews) {
    final mvList = db.materializedViews;
    final filteredMVs = sq.isEmpty
        ? mvList
        : mvList.where((mv) => mv.toLowerCase().contains(sq)).toList();
    if (filteredMVs.isNotEmpty || sq.isEmpty) {
      final key = '$connectionId:$databaseName:materialized_views';
      final expanded = sq.isNotEmpty || c.expandedItems.contains(key);
      widgets.add(
        TreeItem(
          level: 3,
          icon: LucideIcons.database,
          iconColor: context.themeColors.accentBlue,
          label:
              '${l10n.sidebarMaterializedViews} (${filteredMVs.length}${sq.isNotEmpty && filteredMVs.length != mvList.length ? "/${mvList.length}" : ""})',
          isExpanded: expanded,
          isSelected: isNodeSelected(
            'cat:$connectionId:$databaseName:materialized_views',
          ),
          onTap: () => c.onToggleExpand(key),
          onContextMenu: (pos) =>
              c.onShowCategoryMenu?.call(pos, false, 'materialized_view'),
        ),
      );
      if (expanded) {
        for (final mv in filteredMVs) {
          void openMV() {
            // 单击/双击物化视图 → query 编辑器（预填默认浏览查询，方言感知）
            provider.openTableQueryTab(connectionId, databaseName, mv);
          }

          widgets.add(
            TreeItem(
              level: 4,
              icon: LucideIcons.database,
              iconColor: context.themeColors.textSecondary,
              iconSize: 12,
              label: mv,
              showArrow: false,
              isSelected: isNodeSelected(
                'mv:$connectionId:$databaseName:$mv',
              ),
              onTap: openMV,
              onDoubleTap: openMV,
              onContextMenu: (pos) =>
                  c.onShowViewMenu?.call(mv, pos, true),
            ),
          );
        }
      }
    }
  }

  // Procedures (includes functions)
  if (db.procedures.isNotEmpty && type.supportsProcedures) {
    final filteredProcedures = sq.isEmpty
        ? db.procedures
        : db.procedures.where((p) => p.toLowerCase().contains(sq)).toList();
    if (filteredProcedures.isNotEmpty) {
      final key = '$connectionId:$databaseName:procedures';
      final expanded = sq.isNotEmpty || c.expandedItems.contains(key);
      widgets.add(
        TreeItem(
          level: 3,
          icon: LucideIcons.network,
          iconColor: context.themeColors.accentBlue,
          label:
              '${l10n.sidebarProcedures} (${filteredProcedures.length}${sq.isNotEmpty && filteredProcedures.length != db.procedures.length ? "/${db.procedures.length}" : ""})',
          isExpanded: expanded,
          isSelected: isNodeSelected(
            'cat:$connectionId:$databaseName:procedures',
          ),
          onTap: () => c.onToggleExpand(key),
          // T033/FR-014 — Procedures category header menu (Refresh)
          onContextMenu: (pos) =>
              c.onShowCategoryMenu?.call(pos, false, null),
        ),
      );
      if (expanded) {
        for (final p in filteredProcedures) {
          // MySQL/Doris fold functions into db.procedures (see getDatabaseInfo).
          // Functions can't be CALLed — use SELECT name() instead.
          final isFunction = db.functions.contains(p);
          // T036/FR-015 — single-click runs the procedure (was no-op).
          void callProc() => provider.openQueryTab(
            connectionId,
            databaseName,
            sql: isFunction ? 'SELECT \`$p\`();' : 'CALL $p();',
          );
          widgets.add(
            TreeItem(
              level: 4,
              icon: LucideIcons.play,
              iconColor: context.themeColors.textSecondary,
              iconSize: 12,
              label: p,
              showArrow: false,
              isSelected: isNodeSelected(
                isFunction
                    ? 'func:$connectionId:$databaseName:$p'
                    : 'proc:$connectionId:$databaseName:$p',
              ),
              onTap: callProc,
              onDoubleTap: callProc,
              onContextMenu: (pos) =>
                  c.onShowProcedureMenu?.call(p, pos, isFunction),
            ),
          );
        }
      }
    }
  }

  // Triggers (MySQL/SQL Server)
  if (db.triggers.isNotEmpty && type.supportsTriggers) {
    final filteredTriggers = sq.isEmpty
        ? db.triggers
        : db.triggers
              .where((t) => t.name.toLowerCase().contains(sq))
              .toList();
    if (filteredTriggers.isNotEmpty) {
      final key = '$connectionId:$databaseName:triggers';
      final expanded = sq.isNotEmpty || c.expandedItems.contains(key);
      widgets.add(
        TreeItem(
          level: 3,
          icon: LucideIcons.zap,
          iconColor: context.themeColors.accentBlue,
          label:
              '${l10n.sidebarTriggers} (${filteredTriggers.length}${sq.isNotEmpty && filteredTriggers.length != db.triggers.length ? "/${db.triggers.length}" : ""})',
          isExpanded: expanded,
          isSelected: isNodeSelected(
            'cat:$connectionId:$databaseName:triggers',
          ),
          onTap: () => c.onToggleExpand(key),
          // T034/FR-014 — Triggers category header menu (Refresh)
          onContextMenu: (pos) =>
              c.onShowCategoryMenu?.call(pos, false, null),
        ),
      );
      if (expanded) {
        for (final t in filteredTriggers) {
          widgets.add(
            TreeItem(
              level: 4,
              icon: LucideIcons.zap,
              iconColor: context.themeColors.textSecondary,
              iconSize: 12,
              label: '${t.name}  (${t.timing} ${t.event})',
              showArrow: false,
              // T026/FR-010 — single-click opens definition,
              // double-click also opens definition, right-click opens full menu.
              onTap: () => _showTriggerDefinition(context, provider, t),
              onDoubleTap: () => _showTriggerDefinition(context, provider, t),
              onContextMenu: (pos) => _showTriggerMenu(
                context,
                provider,
                connectionId,
                t,
                pos,
                c.onInsertName,
              ),
            ),
          );
        }
      }
    }
  }

  // Events (MySQL only)
  if (db.events.isNotEmpty && type.supportsEvents) {
    final filteredEvents = sq.isEmpty
        ? db.events
        : db.events.where((e) => e.toLowerCase().contains(sq)).toList();
    if (filteredEvents.isNotEmpty) {
      final key = '$connectionId:$databaseName:events';
      final expanded = sq.isNotEmpty || c.expandedItems.contains(key);
      widgets.add(
        TreeItem(
          level: 3,
          icon: LucideIcons.calendar,
          iconColor: context.themeColors.accentBlue,
          label:
              '${l10n.sidebarEvents} (${filteredEvents.length}${sq.isNotEmpty && filteredEvents.length != db.events.length ? "/${db.events.length}" : ""})',
          isExpanded: expanded,
          isSelected: isNodeSelected('cat:$connectionId:$databaseName:events'),
          onTap: () => c.onToggleExpand(key),
          // T035/FR-014 — Events category header menu (Refresh)
          onContextMenu: (pos) =>
              c.onShowCategoryMenu?.call(pos, false, null),
        ),
      );
      if (expanded) {
        for (final e in filteredEvents) {
          widgets.add(
            TreeItem(
              level: 4,
              icon: LucideIcons.calendar,
              iconColor: context.themeColors.textSecondary,
              iconSize: 12,
              label: e,
              showArrow: false,
              // T027/FR-010 — single-click copies name, right-click
              // opens full menu (was a dead node).
              onTap: () {
                Clipboard.setData(ClipboardData(text: e));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.triggerCopied(e))),
                );
              },
              onContextMenu: (pos) => _showEventMenu(
                context,
                provider,
                e,
                pos,
                c.onInsertName,
              ),
            ),
          );
        }
      }
    }
  }

  return widgets;
}

// ── 私有装配 helper（自 sidebar_tree 随迁，行为逐行保持）──

/// 表叶子（Draggable 的 child/childWhenDragging 双消费，自原内联段提取）。
TreeItem _tableLeaf(
  BuildContext context,
  SidebarDatabaseTreeContext c,
  bool Function(String key) isNodeSelected,
  String tableName,
  String tk,
  bool te,
  bool loading,
  String? rowBadge,
) {
  final provider = c.provider;
  return TreeItem(
    level: 4,
    icon: LucideIcons.table2,
    iconColor: context.themeColors.accentBlue,
    iconSize: 12,
    label: tableName,
    showArrow: true,
    isExpanded: te,
    isLoading: loading,
    badge: rowBadge,
    isSelected:
        provider.selectedTable == tableName ||
        isNodeSelected('table:${c.connectionId}:${c.databaseName}:$tableName'),
    onTap: () => c.onToggleTable(tk),
    onDoubleTap: () {
      provider.openTableQueryTab(
        c.connectionId,
        c.databaseName,
        tableName,
      );
      // 记录最近访问
      provider.recentTables.recordTableAccess(
        connectionId: c.connectionId,
        databaseName: c.databaseName,
        tableName: tableName,
      );
    },
    onContextMenu: (pos) {
      c.onRightClickTargetChanged?.call(
        'table:${c.connectionId}:${c.databaseName}:$tableName',
      );
      c.onShowTableMenu(context, tableName, pos).then(
        (_) => c.onRightClickTargetChanged?.call(null),
      );
    },
  );
}

String _formatRowCount(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return count.toString();
}

Widget _loadingNode(BuildContext context) => Padding(
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
);

/// 计算非 TreeItem schema 明细节点的左缩进（与 TreeItem 同级标签位对齐）。
double _schemaNodeIndent(int level) {
  const leftPad = AppDesignSystem.space3; // TreeItem uses space3 for level≥3
  const arrowSection = 14.0 + AppDesignSystem.space1; // arrow width + gap
  const iconSize = 14.0; // TreeItem icon size for level≥3
  const iconGap = AppDesignSystem.space2;
  final connectors = (level - 1) * AppDesignSystem.treeNodeIndent;
  return leftPad + connectors + arrowSection + iconSize + iconGap;
}

Future<void> _showTriggerMenu(
  BuildContext context,
  AppProvider provider,
  String cid,
  DbTrigger t,
  Offset pos,
  void Function(String name) onInsertName,
) async {
  final l10n = AppLocalizations.of(context)!;
  final server = provider.connection.getServerById(cid);
  final isReadOnly = server?.readOnly ?? false;
  await ContextMenuUtils.show(
    context: context,
    position: pos,
    items: [
      ContextMenuItem(
        id: 'viewDefinition',
        label: l10n.triggerViewDefinition,
        icon: LucideIcons.fileText,
        onTap: () => _showTriggerDefinition(context, provider, t),
      ),
      ContextMenuItem(
        id: 'copyName',
        label: l10n.triggerCopyName,
        icon: LucideIcons.copy,
        onTap: () {
          Clipboard.setData(ClipboardData(text: t.name));
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.triggerCopied(t.name))));
        },
      ),
      ContextMenuItem(
        id: 'insert',
        label: l10n.sidebarInsertIntoEditor,
        icon: LucideIcons.logIn,
        onTap: () => onInsertName(t.name),
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        id: 'drop',
        label: l10n.triggerDeleteTitle,
        icon: LucideIcons.trash2,
        isDestructive: true,
        enabled: !isReadOnly,
        disabledReason: isReadOnly ? l10n.sidebarReadOnlyConnection : null,
        onTap: () => _confirmDropTrigger(context, provider, cid, t),
      ),
    ],
  );
}

Future<void> _showTriggerDefinition(
  BuildContext context,
  AppProvider provider,
  DbTrigger t,
) async {
  final l10n = AppLocalizations.of(context)!;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    String definition;
    try {
      definition = await TriggerService(
        provider.dbService,
      ).getCreateStatement(t.name);
    } catch (_) {
      // Fallback to the ACTION_STATEMENT body already loaded on the node.
      definition = t.statement ?? '';
    }
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await showDialog(
      context: context,
      builder: (_) => DefinitionViewDialog(
        title: l10n.triggerDefinition(t.name),
        definition: definition,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    AppErrorHandler.showErrorSnackBar(
      context,
      l10n.triggerFailedToLoadDefinition,
    );
  }
}

Future<void> _confirmDropTrigger(
  BuildContext context,
  AppProvider provider,
  String cid,
  DbTrigger t,
) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(l10n.triggerDeleteTitle),
      content: Text(l10n.triggerDeleteConfirm(t.name)),
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
    await TriggerService(provider.dbService).drop(t.name);
    // TriggerService.drop does not auto-refresh; refresh explicitly (Constitution V.5).
    await provider.refreshDatabases(connectionId: cid);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.triggerDeleted(t.name))));
  } catch (e) {
    if (!context.mounted) return;
    AppErrorHandler.showErrorSnackBar(
      context,
      l10n.sidebarDropTriggerFailed(e.toString()),
    );
  }
}

// T027/FR-010 — Event leaf context menu (previously a dead node).
// Events carry only a name (List<String>); DROP uses generic executeSqlScript
// (auto-refreshes). View-definition omitted: no dedicated method and parsing
// SHOW CREATE EVENT result rows is fragile — Copy/Insert/Drop already makes
// the node non-dead per FR-010.
Future<void> _showEventMenu(
  BuildContext context,
  AppProvider provider,
  String e,
  Offset pos,
  void Function(String name) onInsertName,
) async {
  final l10n = AppLocalizations.of(context)!;
  await ContextMenuUtils.show(
    context: context,
    position: pos,
    items: [
      ContextMenuItem(
        id: 'copyName',
        label: l10n.triggerCopyName,
        icon: LucideIcons.copy,
        onTap: () {
          Clipboard.setData(ClipboardData(text: e));
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l10n.triggerCopied(e))));
        },
      ),
      ContextMenuItem(
        id: 'insert',
        label: l10n.sidebarInsertIntoEditor,
        icon: LucideIcons.logIn,
        onTap: () => onInsertName(e),
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        id: 'drop',
        label: l10n.sidebarDropEvent,
        icon: LucideIcons.trash2,
        isDestructive: true,
        onTap: () => _confirmDropEvent(context, provider, e),
      ),
    ],
  );
}

Future<void> _confirmDropEvent(
  BuildContext context,
  AppProvider provider,
  String e,
) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: Text(l10n.sidebarDropEvent),
      content: Text(l10n.sidebarDropEventConfirm(e)),
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
    // executeSqlScript runs on the current connection and auto-refreshes.
    await provider.executeSqlScript('DROP EVENT IF EXISTS `$e`');
  } catch (e2) {
    if (!context.mounted) return;
    AppErrorHandler.showErrorSnackBar(
      context,
      l10n.sidebarEventOperationFailed(e2.toString()),
    );
  }
}
