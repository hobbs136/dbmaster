import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_colors.dart';

/// `@` 表引用候选浮层（design-ai-workbench §4.7 / 决策 D13）。
///
/// 复用 `SlashCommandMenu` 的浮层语汇（maxHeight 200 / bgSecondary / radiusMd /
/// borderLight / 同款阴影）；候选按 [prefix] 大小写不敏感前缀过滤。
/// 候选数据由宿主经 `AiInputArea.onTableMentionQuery` 注入，本组件不做数据获取。
class AiTableMentionMenu extends StatelessWidget {
  /// 当前 `@` 引用 token 的已输入前缀（`@` 与光标之间的文本，不含 `@`）。
  final String prefix;

  /// 宿主查询得到的候选表名全集（组件内再做前缀过滤）。
  final List<String> candidates;

  /// 键盘导航高亮行索引（由 AiInputArea 状态持有，越界自动收敛）。
  final int highlightIndex;

  /// 选中（点击或键盘 Enter）某张表时的回调，参数为表名。
  final ValueChanged<String> onTableSelected;

  const AiTableMentionMenu({
    super.key,
    required this.prefix,
    required this.candidates,
    required this.highlightIndex,
    required this.onTableSelected,
  });

  /// 前缀过滤（大小写不敏感、startsWith 语义）；[prefix] 为空时全量返回。
  /// AiInputArea 的键盘导航也用它计算可视候选集，保证两处过滤口径同源。
  static List<String> filterCandidates(List<String> candidates, String prefix) {
    if (prefix.isEmpty) return List<String>.unmodifiable(candidates);
    final String lower = prefix.toLowerCase();
    return candidates
        .where((c) => c.toLowerCase().startsWith(lower))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final List<String> filtered = filterCandidates(candidates, prefix);

    if (filtered.isEmpty) {
      return const SizedBox.shrink();
    }

    final int safeHighlight = highlightIndex.clamp(0, filtered.length - 1);

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: context.themeColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: AppDesignSystem.space1),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final String table = filtered[index];
          final bool isHighlighted = index == safeHighlight;
          if (isHighlighted) {
            // 键盘导航时高亮行滚动进可视区。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Scrollable.ensureVisible(context);
            });
          }
          return InkWell(
            onTap: () => onTableSelected(table),
            child: Container(
              key: isHighlighted
                  ? const ValueKey('aiTableMentionHighlight')
                  : null,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space2,
              ),
              decoration: isHighlighted
                  ? BoxDecoration(
                      color: context.themeColors.accentPurple.withValues(
                        alpha: 0.12,
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  Icon(
                    LucideIcons.table2,
                    size: 16,
                    color: context.themeColors.accentPurple,
                  ),
                  const SizedBox(width: AppDesignSystem.space2_5),
                  Expanded(
                    child: Text(
                      table,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.themeColors.textPrimary,
                        fontFamily: AppDesignSystem.monoFontFamily,
                        fontFamilyFallback:
                            AppDesignSystem.monoFontFamilyFallback,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
