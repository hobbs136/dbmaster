// C14 · 侧边栏能力菜单 —— 分组能力目录的渲染半边（原型
// `sidebar-capability-menu.html`）。
//
// 职责边界（装配见 capability_menu_assembly.dart）：本 widget 只做渲染与
// 折叠态，不判定任何能力——数据来自装配结果（插件合并 + port 门控后的
// 组列表）。无活动连接或装配为空 → 整段隐藏。
//
// 徽章形态对齐原型：core / <type>-plugin / ai-plugin；AI 来源徽章用
// 品牌色底白字，highlight 项（AI 助手）brand-subtle 底 + 主色文字。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../plugins/bootstrap.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_colors.dart';
import 'capability_menu_assembly.dart';

/// 展开态菜单体的最大高度（超出滚动）；树仍是侧边栏主体（原型比例）。
const double _kMenuMaxHeight = 264;

class SidebarCapabilityMenu extends StatefulWidget {
  const SidebarCapabilityMenu({super.key});

  @override
  State<SidebarCapabilityMenu> createState() => _SidebarCapabilityMenuState();
}

class _SidebarCapabilityMenuState extends State<SidebarCapabilityMenu> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final server = resolveCapabilityMenuServer(
      currentServer: provider.connection.currentServer,
      activeTabConnectionId: provider.tab.activeTab?.connectionId,
      selectedConnectionId: provider.sidebar.selectedConnectionId,
      isConnected: provider.isConnectionConnected,
      savedConnections: provider.savedConnections,
    );
    if (server == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final groups = assembleCapabilityMenu(
      context: context,
      type: server.type,
      port: provider.connection.ports.resolveFor(server.type),
      plugins: defaultPluginRegistry.sidebarPluginsFor(server.type),
      l10n: l10n,
    );
    if (groups.isEmpty) return const SizedBox.shrink();

    final colors = context.themeColors;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, colors),
          if (_expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: _kMenuMaxHeight,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  AppDesignSystem.space2,
                  0,
                  AppDesignSystem.space2,
                  AppDesignSystem.space2,
                ),
                children: [
                  for (final group in groups) ...[
                    _GroupHeader(label: group.label),
                    for (final entry in group.items)
                      _CapabilityItemRow(entry: entry),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeColors colors) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space1_5,
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: _expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(width: AppDesignSystem.space1_5),
            Icon(LucideIcons.layoutGrid, size: 14, color: colors.textMuted),
            const SizedBox(width: AppDesignSystem.space1_5),
            Text(
              l10n.sidebarCapabilityTitle,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDesignSystem.space2,
        AppDesignSystem.space1_5,
        AppDesignSystem.space2,
        AppDesignSystem.space0_5,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: colors.textMuted,
        ),
      ),
    );
  }
}

class _CapabilityItemRow extends StatelessWidget {
  final AssembledCapabilityItem entry;

  const _CapabilityItemRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final highlighted = entry.item.highlight;
    final foreground =
        highlighted ? colors.accentBlue : colors.textPrimary;
    final iconColor = highlighted ? colors.accentBlue : colors.textSecondary;

    return Tooltip(
      message: '${entry.item.label(AppLocalizations.of(context)!)} · '
          '${entry.badge}',
      preferBelow: false,
      child: InkWell(
        onTap: entry.item.onActivate,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            color: highlighted ? colors.accentSubtle : null,
          ),
          child: Row(
            children: [
              Icon(entry.item.icon, size: 14, color: iconColor),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  entry.item.label(AppLocalizations.of(context)!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeSm,
                    fontWeight: highlighted ? FontWeight.w600 : null,
                    color: foreground,
                  ),
                ),
              ),
              _SourceBadge(badge: entry.badge, emphasized: entry.fromAi),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final String badge;
  final bool emphasized;

  const _SourceBadge({required this.badge, required this.emphasized});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: emphasized ? colors.accentBlue : colors.bgQuaternary,
      ),
      child: Text(
        badge,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          color: emphasized ? Colors.white : colors.textMuted,
        ),
      ),
    );
  }
}
