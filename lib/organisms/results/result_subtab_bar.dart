import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/app_provider.dart';
import '../../providers/tab_provider.dart' show ResultSubTab;
import '../../theme/app_colors.dart';

/// 结果子标签栏
///
/// 显示在 SQL Editor 下方，管理当前 Query Tab 的多个查询结果：
/// - [Result 1], [Result 2], ... — 每次查询生成的结果标签
///   - 成功：绿色 check 图标 + 行数徽章
///   - 失败：红色 error 图标 + Error 标签
///   - 可通过 Pin 图标固定，下次查询不覆盖
///   - 支持 Name 注解自动命名
class ResultSubTabBar extends StatelessWidget {
  const ResultSubTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final activeTab = provider.tab.activeTab;
        if (activeTab == null) return const SizedBox.shrink();

        final results = provider.tab.activeResults;
        final activeResultIdx = provider.tab.activeResultIndex;

        if (results.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 28,
          decoration: BoxDecoration(
            color: context.themeColors.bgSecondary,
            border: Border(
              top: BorderSide(color: context.themeColors.dividerColor),
              bottom: BorderSide(color: context.themeColors.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return _ResultSubTabItem(
                      result: result,
                      isActive: index == activeResultIdx,
                      onTap: () =>
                          provider.tab.setActiveResult(activeTab.id, index),
                      onPin: result.isHistory
                          ? null
                          : () {
                              if (result.isPinned) {
                                provider.tab.unpinResult(activeTab.id, index);
                              } else {
                                provider.tab.pinResult(activeTab.id, index);
                              }
                            },
                      onClose: result.isHistory
                          ? null
                          : () => provider.tab.closeResult(activeTab.id, index),
                    );
                  },
                ),
              ),
              _ToolbarIcon(
                icon: LucideIcons.eraser,
                tooltip: AppLocalizations.of(context)!.toolbarCloseAll,
                onTap: () => provider.tab.closeAllResults(activeTab.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResultSubTabItem extends StatelessWidget {
  final ResultSubTab result;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onPin;
  final VoidCallback? onClose;

  const _ResultSubTabItem({
    required this.result,
    required this.isActive,
    required this.onTap,
    this.onPin,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final isError = result.hasError;
    final isHistory = result.isHistory;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2_5,
        ),
        decoration: BoxDecoration(
          // C21（原型 editor-results-split 子标签）：无 active 底色，
          // accent 文字 + 2px 下划线指示；错误子标签保留 error 下划线。
          border: Border(
            bottom: BorderSide(
              color: isActive
                  ? (isHistory
                        ? context.themeColors.accentBlue
                        : (isError
                              ? context.themeColors.error
                              : context.themeColors.accentBlue))
                  : Colors.transparent,
              width: 2,
            ),
            right: BorderSide(
              color: colors.borderSubtle,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isHistory) ...[
              Icon(
                LucideIcons.history,
                size: 12,
                color: isActive ? colors.textPrimary : colors.textSecondary,
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                l10n.resultHistorySubTabLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ] else ...[
              GestureDetector(
                onTap: onPin ?? () {},
                child: Icon(
                  result.isPinned ? LucideIcons.pin : LucideIcons.pin,
                  size: 12,
                  color: result.isPinned
                      ? context.themeColors.warning
                      : colors.textMuted,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Icon(
                isError ? LucideIcons.circleAlert : LucideIcons.circleCheckBig,
                size: 12,
                color: isError
                    ? context.themeColors.error
                    : context.themeColors.success,
              ),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                result.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? colors.textPrimary : colors.textSecondary,
                ),
              ),
              if (result.executionTime != null) ...[
                const SizedBox(width: AppDesignSystem.space1_5),
                Text(
                  _formatDuration(result.executionTime!),
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ],
              const SizedBox(width: AppDesignSystem.space1_5),
              GestureDetector(
                onTap: onClose ?? () {},
                child: Icon(LucideIcons.x, size: 12, color: colors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 1) return '${d.inMilliseconds}ms';
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    return '${d.inMinutes}m${d.inSeconds % 60}s';
  }
}

class _ToolbarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ToolbarIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1_5,
          ),
          child: Icon(icon, size: 14, color: context.themeColors.textMuted),
        ),
      ),
    );
  }
}
