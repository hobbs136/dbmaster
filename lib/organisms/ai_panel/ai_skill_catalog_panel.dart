// C23.2 · AI 面板左栏——技能目录。
//
// 数据源 = PluginRegistry.aiSkills（编译期注册，C23.1 内置 10 技能 +
// Pro 注入），按 skillGroupId 分组渲染（SQL/数据/结构/运维，原型
// ai-panel-skills 左栏 240px）。点击技能 → 选中 + promptTemplate 填入
// 输入框（宿主回调）；插件徽章文本 = descriptor.id（反查无歧义）。
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../plugins/ai_skill_plugin.dart';
import '../../plugins/bootstrap.dart';
import '../../theme/app_theme.dart';

/// 技能分组 id → 目录分组次序（未知名分组按注册序排最后，不丢插件）。
const List<String> _kGroupOrder = [
  AiSkillGroupIds.sql,
  AiSkillGroupIds.data,
  AiSkillGroupIds.schema,
  AiSkillGroupIds.ops,
];

class AiSkillCatalogPanel extends StatelessWidget {
  /// 当前选中技能 id（null = 无选中）。
  final String? selectedSkillId;

  /// 点击技能条目（含 promptTemplate 为 null 的技能，宿主自行只选中）。
  final ValueChanged<AiSkillPlugin> onSkillSelected;

  const AiSkillCatalogPanel({
    super.key,
    required this.selectedSkillId,
    required this.onSkillSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final skills = defaultPluginRegistry.aiSkills;

    final groupNames = {
      AiSkillGroupIds.sql: l10n.aiSkillGroupSql,
      AiSkillGroupIds.data: l10n.aiSkillGroupData,
      AiSkillGroupIds.schema: l10n.aiSkillGroupSchema,
      AiSkillGroupIds.ops: l10n.aiSkillGroupOps,
    };

    // 分桶：known 走定序，未知组保留（排后），组内保持注册序
    final known = <String, List<AiSkillPlugin>>{};
    final unknown = <String, List<AiSkillPlugin>>{};
    for (final skill in skills) {
      final buckets = _kGroupOrder.contains(skill.skillGroupId)
          ? known
          : unknown;
      (buckets[skill.skillGroupId] ??= []).add(skill);
    }
    final orderedIds = [
      ..._kGroupOrder.where(known.containsKey),
      ...unknown.keys,
    ];
    List<AiSkillPlugin> groupOf(String id) =>
        known[id] ?? unknown[id] ?? const <AiSkillPlugin>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppDesignSystem.space3,
            AppDesignSystem.space2_5,
            AppDesignSystem.space3,
            AppDesignSystem.space2,
          ),
          child: Text(
            l10n.aiSkillCatalogTitle,
            style: AppTextStyles.label.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: context.themeColors.textMuted,
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: context.themeColors.dividerColor,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              vertical: AppDesignSystem.space1,
            ),
            children: [
              for (final groupId in orderedIds) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDesignSystem.space3,
                    AppDesignSystem.space2,
                    AppDesignSystem.space3,
                    AppDesignSystem.space1,
                  ),
                  child: Text(
                    groupNames[groupId] ?? groupId,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: context.themeColors.textMuted,
                    ),
                  ),
                ),
                for (final skill in groupOf(groupId))
                  _SkillTile(
                    skill: skill,
                    selected: skill.descriptor.id == selectedSkillId,
                    onTap: () => onSkillSelected(skill),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SkillTile extends StatelessWidget {
  final AiSkillPlugin skill;
  final bool selected;
  final VoidCallback onTap;

  const _SkillTile({
    required this.skill,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: 1,
      ),
      child: Material(
        color: selected ? colors.accentPurple.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1_5,
            ),
            child: Row(
              children: [
                Icon(
                  skill.descriptor.icon,
                  size: 14,
                  color: selected ? colors.accentPurple : colors.textMuted,
                ),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Text(
                    skill.displayName(l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? colors.accentPurple : colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppDesignSystem.space1),
                // 插件徽章（原型右缀 badge；id 即技术徽章文本）。
                // maxWidth 约束：长 id（query-optimizer-plugin）可收缩出省略号，
                // 否则挤出 240px 栏宽。
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 92),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.bgTertiary,
                      borderRadius:
                          BorderRadius.circular(AppDesignSystem.radiusSm / 2),
                    ),
                    child: Text(
                      skill.descriptor.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: colors.textMuted),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
