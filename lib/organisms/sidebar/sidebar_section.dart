// C22-0 · 侧边栏 section 容器 —— 收藏 / 最近表 / 连接分组的统一版式
//（原型 sidebar chrome 的 section 头：紧凑行 + 计数徽章 + 可折叠）。
//
// 替换原先三处各自为政的 ExpansionTile 头部（Material 主题样式与紧凑
// chrome 不符）；折叠状态由本组件自持（与 ExpansionTile 同语义：
// 重建即回到 initiallyExpanded，不持久化）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_colors.dart';

class SidebarSection extends StatefulWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;

  /// 非空时标题右侧渲染计数徽章。
  final int? count;

  /// 标题行右端动作（如最近表的清空按钮）。
  final Widget? trailing;

  final bool initiallyExpanded;
  final List<Widget> children;

  const SidebarSection({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
    this.count,
    this.trailing,
    this.initiallyExpanded = true,
    required this.children,
  });

  @override
  State<SidebarSection> createState() => _SidebarSectionState();
}

class _SidebarSectionState extends State<SidebarSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          hoverColor: colors.bgTertiary,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    LucideIcons.chevronRight,
                    size: 12,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                Icon(
                  widget.icon,
                  size: 14,
                  color: widget.iconColor ?? colors.textSecondary,
                ),
                const SizedBox(width: AppDesignSystem.space1_5),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeXs,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                if (widget.count != null) ...[
                  const SizedBox(width: AppDesignSystem.space1_5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space1,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.bgQuaternary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${widget.count}',
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSizeXs,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
                if (widget.trailing != null) ...[
                  const SizedBox(width: AppDesignSystem.space1),
                  widget.trailing!,
                ],
              ],
            ),
          ),
        ),
        if (_expanded) ...widget.children,
      ],
    );
  }
}
