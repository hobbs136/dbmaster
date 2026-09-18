// C22-0 换装：品牌 header（原型 sidebar chrome 的 Header 段）——
// logo 方块（primary 底白图标）+ DbMaster 字标 + 右侧动作区
//（分组管理 / 新建分组 / 折叠，行为保持）；分组对话框硬编码英文
// 顺带 l10n 化（Create/Cancel/Delete Group → 既有 common* + 新键）。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../models/database_models.dart';
import '../../molecules/compact_popup_menu_item.dart';

class SidebarHeader extends StatelessWidget {
  final VoidCallback onToggleCollapse;
  final bool isCollapsed;

  const SidebarHeader({
    super.key,
    required this.onToggleCollapse,
    this.isCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              color: colors.accentBlue,
            ),
            child: Icon(
              LucideIcons.database,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            'DbMaster',
            style: TextStyle(
              fontSize: AppDesignSystem.fontSizeSm,
              fontWeight: AppDesignSystem.fontWeightSemibold,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (provider.connectionGroups.isNotEmpty)
                    PopupMenuButton<String>(
                      tooltip: AppLocalizations.of(
                        context,
                      )!.sidebarManageGroups,
                      icon: Icon(
                        LucideIcons.folder,
                        size: 14,
                        color: colors.textSecondary,
                      ),
                      itemBuilder: (context) => [
                        ...provider.connectionGroups.map(
                          (group) => CompactPopupMenuItem(
                            value: group.id,
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.folder,
                                  color: _parseColor(context, group.color),
                                ),
                                const SizedBox(width: AppDesignSystem.space2),
                                Text(group.name),
                              ],
                            ),
                          ),
                        ),
                        const PopupMenuDivider(height: 6),
                        CompactPopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(LucideIcons.trash2, color: colors.accentRed),
                              const SizedBox(width: AppDesignSystem.space2),
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.sidebarDeleteGroup,
                                style: TextStyle(color: colors.accentRed),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (value) {
                        if (value == 'delete') {
                          _showDeleteGroupDialog(context, provider);
                        }
                      },
                    ),
                  IconButton(
                    tooltip: AppLocalizations.of(context)!.sidebarNewGroup,
                    icon: Icon(
                      LucideIcons.folderPlus,
                      size: 14,
                      color: colors.textSecondary,
                    ),
                    onPressed: () => _showCreateGroupDialog(context, provider),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                  ),
                ],
              );
            },
          ),
          InkWell(
            onTap: onToggleCollapse,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            hoverColor: colors.bgTertiary,
            child: Container(
              padding: const EdgeInsets.all(AppDesignSystem.space1),
              child: Icon(
                LucideIcons.panelLeftClose,
                size: 14,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _parseColor(BuildContext context, String? colorStr) {
    if (colorStr == null) return context.themeColors.accentBlue;
    try {
      return Color(int.parse(colorStr.replaceFirst('#', '0xFF')));
    } catch (_) {
      return context.themeColors.accentBlue;
    }
  }

  void _showCreateGroupDialog(BuildContext context, AppProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sidebarNewGroup),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.sidebarGroupName,
            hintText: l10n.sidebarGroupHint,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await provider.addConnectionGroup(
                  ConnectionGroup(
                    id: 'group_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                  ),
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l10n.commonCreate),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _showDeleteGroupDialog(BuildContext context, AppProvider provider) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sidebarDeleteGroup),
        content: Text(l10n.sidebarDeleteGroupPrompt),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          ...provider.connectionGroups.map(
            (group) => TextButton(
              onPressed: () async {
                await provider.deleteConnectionGroup(group.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(
                group.name,
                style: TextStyle(color: context.themeColors.accentRed),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
