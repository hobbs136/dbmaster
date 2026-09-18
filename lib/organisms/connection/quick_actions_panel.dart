/// 快捷操作面板组件
/// 参考 openclaw-manager Dashboard QuickActions 设计
/// 在数据库连接后显示，提供常用操作的快速入口
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../providers/app_provider.dart';
import 'table_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

class QuickActionsPanel extends StatelessWidget {
  const QuickActionsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final selectedId = provider.sidebar.selectedConnectionId;
        final isConnected =
            selectedId != null &&
            provider.connection.isConnectionConnected(selectedId) &&
            !provider.connection.isConnecting;
        if (!isConnected) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space1,
          ),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
            border: Border.all(
              color: context.themeColors.borderLight.withOpacity(0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.quickActionsTitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space2),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionBtn(
                      icon: LucideIcons.circlePlus,
                      label: l10n.quickActionsNewTable,
                      color: context.themeColors.success,
                      onTap: () => _openCreateTableDialog(context, provider),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Expanded(
                    child: _QuickActionBtn(
                      icon: LucideIcons.circlePlay,
                      label: l10n.quickActionsNewQuery,
                      color: context.themeColors.accentBlue,
                      onTap: () async =>
                          await context.read<AppProvider>().addNewTab(),
                    ),
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Expanded(
                    child: _QuickActionBtn(
                      icon: LucideIcons.sparkles,
                      label: l10n.quickActionsAiAssistant,
                      color: context.themeColors.accentPurple,
                      onTap: () => provider.toggleAiPanel(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openCreateTableDialog(BuildContext context, AppProvider provider) {
    final dbName = provider.sidebar.selectedDatabaseName;
    if (dbName == null || dbName.isEmpty) {
      _showSnackBar(
        context,
        AppLocalizations.of(context)!.quickActionsSelectDatabaseFirst,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => CreateTableDialog(dbName: dbName),
    );
  }
}

/// 快捷操作按钮（参考 openclaw-manager 风格）
class _QuickActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        hoverColor: color.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppDesignSystem.space1_5,
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: AppDesignSystem.space0_5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
