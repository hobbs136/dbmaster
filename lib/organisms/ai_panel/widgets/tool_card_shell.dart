import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_colors.dart';

/// 可缩放的工具容器 - 将工具卡片包装在一个可整体缩放的大卡片中
class ToolCardShell extends StatefulWidget {
  final String toolName;
  final Widget child;

  const ToolCardShell({super.key, required this.toolName, required this.child});

  @override
  State<ToolCardShell> createState() => _ToolCardShellState();
}

class _ToolCardShellState extends State<ToolCardShell> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isOverlay = context.watch<AppProvider>().isAiPanelOverlay;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isOverlay ? Colors.transparent : context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: isOverlay
              ? context.themeColors.borderSubtle
              : context.themeColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppDesignSystem.radiusMd),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space2,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(AppDesignSystem.radiusMd),
                  bottom: _expanded
                      ? Radius.zero
                      : const Radius.circular(AppDesignSystem.radiusMd),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.wrench,
                    size: 16,
                    color: context.themeColors.accentPurple,
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Expanded(
                    child: Text(
                      widget.toolName == 'tool_group'
                          ? AppLocalizations.of(context)!.toolGroupTitle
                          : AppLocalizations.of(
                              context,
                            )!.toolCallTitle(widget.toolName),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.themeColors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 18,
                    color: context.themeColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // 内容区域
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}
