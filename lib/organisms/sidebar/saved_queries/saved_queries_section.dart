import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/tab_provider.dart';
import '../../../theme/app_theme.dart';
import 'saved_query_rename_dialog.dart';
import '../tree_item.dart';
import '../../../molecules/context_menu.dart';

/// Connection-level "Saved Queries" section for the sidebar tree.
class SavedQueriesSection extends StatelessWidget {
  final String connectionId;
  final String searchQuery;
  final Set<String> expandedItems;
  final String? selectedNodeKey;
  final String? rightClickedNodeKey;
  final ValueChanged<String>? onToggleExpand;
  final ValueChanged<String?>? onRightClickTargetChanged;
  final ValueChanged<String>? onSelectNode;

  const SavedQueriesSection({
    super.key,
    required this.connectionId,
    required this.searchQuery,
    required this.expandedItems,
    this.selectedNodeKey,
    this.rightClickedNodeKey,
    this.onToggleExpand,
    this.onRightClickTargetChanged,
    this.onSelectNode,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final l10n = AppLocalizations.of(context)!;
    final sq = searchQuery.toLowerCase();
    final savedQueries = provider.savedQueriesForConnection(connectionId);
    final filteredQueries = sq.isEmpty
        ? savedQueries
        : savedQueries.where((q) {
            return q.title.toLowerCase().contains(sq) ||
                q.sql.toLowerCase().contains(sq);
          }).toList();

    final key = '$connectionId:saved_queries';
    final expanded = sq.isNotEmpty || expandedItems.contains(key);
    final hasChildren = filteredQueries.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreeItem(
          level: 2,
          icon: LucideIcons.bookmark,
          iconColor: context.themeColors.accentBlue,
          label:
              '${l10n.savedQueriesTitle} (${filteredQueries.length}${sq.isNotEmpty && filteredQueries.length != savedQueries.length ? "/${savedQueries.length}" : ""})',
          isExpanded: expanded,
          isSelected: _isKeySelected('cat:$key'),
          showArrow: true,
          onTap: () => onToggleExpand?.call(key),
        ),
        if (expanded) ...[
          if (hasChildren)
            ...filteredQueries.map((query) {
              final nodeKey = 'savedquery:$connectionId:${query.id}';
              return TreeItem(
                level: 3,
                icon: LucideIcons.bookmark,
                iconColor: context.themeColors.textSecondary,
                iconSize: 12,
                label: query.title,
                showArrow: false,
                isSelected: _isKeySelected(nodeKey),
                onTap: () => onSelectNode?.call(nodeKey),
                onDoubleTap: () => provider.openSavedQuery(query),
                onContextMenu: (pos) {
                  onRightClickTargetChanged?.call(nodeKey);
                  _showSavedQueryContextMenu(
                    context,
                    provider,
                    query,
                    pos,
                  ).then((_) => onRightClickTargetChanged?.call(null));
                },
              );
            })
          else
            _buildEmptyNode(context, l10n),
        ],
      ],
    );
  }

  bool _isKeySelected(String nodeKey) {
    return selectedNodeKey == nodeKey || rightClickedNodeKey == nodeKey;
  }

  Widget _buildEmptyNode(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppDesignSystem.space4 + AppDesignSystem.treeNodeIndent * 2,
        top: AppDesignSystem.space1,
        bottom: AppDesignSystem.space1,
      ),
      child: Text(
        l10n.savedQueriesNoQueries,
        style: TextStyle(fontSize: 11, color: context.themeColors.textMuted),
      ),
    );
  }

  Future<void> _showSavedQueryContextMenu(
    BuildContext context,
    AppProvider provider,
    QueryTab query,
    Offset pos,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final items = <ContextMenuItem>[
      ContextMenuItem(
        id: 'open',
        label: l10n.savedQueriesOpen,
        icon: LucideIcons.externalLink,
        onTap: () => provider.openSavedQuery(query),
      ),
      ContextMenuItem(
        id: 'rename',
        label: l10n.queryHistoryRename,
        icon: LucideIcons.pencil,
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (dialogCtx) => SavedQueryRenameDialog(
              initialTitle: query.title,
              onSave: (newTitle) {
                if (newTitle.isNotEmpty) {
                  provider.renameSavedQuery(query.id, newTitle);
                }
              },
            ),
          );
        },
      ),
      const ContextMenuItem.divider(),
      ContextMenuItem(
        id: 'delete',
        label: l10n.savedQueriesDeleteTitle,
        icon: LucideIcons.trash2,
        isDestructive: true,
        onTap: () => provider.deleteSavedQuery(query.id),
      ),
    ];
    await ContextMenuUtils.show(context: context, position: pos, items: items);
  }
}
