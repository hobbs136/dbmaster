// C22-1 · 侧边栏底部：状态行（连接计数）+ 全局动作行（AI/主题/设置）。
//
// AppHeader 整条下掉后，顶栏的全局动作迁入此处（原型 sidebar footer 位）；
// 命令面板入口归面包屑栏、Server 状态归底部全局状态栏（各自另行）。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../pages/about/about_page.dart';
import '../../providers/app_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';

class SidebarFooter extends StatelessWidget {
  /// 打开设置对话框（宿主路由注入）。
  final VoidCallback onShowSettings;

  const SidebarFooter({super.key, required this.onShowSettings});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusRow(context),
          _buildActionsRow(context),
        ],
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    final colors = context.themeColors;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final connectedCount = provider.activeConnectionCount;
        return Container(
          height: 26,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connectedCount > 0
                      ? colors.accentGreen
                      : colors.textMuted,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Expanded(
                child: Text(
                  AppLocalizations.of(
                    context,
                  )!.sidebarConnectionActive(connectedCount),
                  style: TextStyle(
                    fontSize: AppDesignSystem.fontSizeXs,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    return Consumer2<AppProvider, ThemeProvider>(
      builder: (context, provider, themeProvider, _) {
        final aiActive = provider.aiPanelOpen;
        return SizedBox(
          height: 30,
          child: Row(
            children: [
              const SizedBox(width: AppDesignSystem.space2),
              _ActionButton(
                icon: LucideIcons.sparkles,
                tooltip: l10n.shortcutCategoryAi,
                color: aiActive ? colors.accentBlue : colors.textSecondary,
                onPressed: () => provider.toggleAiPanel(),
              ),
              _ActionButton(
                icon: themeProvider.isDarkMode
                    ? LucideIcons.sun
                    : LucideIcons.moon,
                tooltip: themeProvider.isDarkMode
                    ? l10n.settingsLightMode
                    : l10n.settingsDarkMode,
                color: colors.textSecondary,
                onPressed: () => themeProvider.toggle(),
              ),
              _ActionButton(
                icon: LucideIcons.settings,
                tooltip: l10n.settingsTitle,
                color: colors.textSecondary,
                onPressed: onShowSettings,
              ),
              // T4 开源迁移：关于页入口（版本 / AGPL-3.0 授权声明 / 许可证全文）。
              _ActionButton(
                icon: LucideIcons.info,
                tooltip: l10n.settingsNavAbout,
                color: colors.textSecondary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutPage()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: IconButton(
        icon: Icon(icon, size: 15),
        color: color,
        onPressed: onPressed,
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space1_5,
        ),
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        splashRadius: 14,
      ),
    );
  }
}
