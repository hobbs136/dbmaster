// C23.2 · AI 面板右栏——上下文面板。
//
// 原型 ai-panel-skills 右栏 260px：当前连接卡（类型 icon + 名称）+
// 当前数据库 + 「附加 Schema 上下文」toggle（发送时附带当前库表结构，
// 映射 AiContextBuilder 的 schema 上下文开关）。原型「选中表」多选编辑
// 已 descoped（侧边栏树已提供表浏览，见 task_ui_phase2.md 范围裁定）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../theme/app_theme.dart';

class AiContextPanel extends StatelessWidget {
  /// 当前选中连接（null = 未选）。
  final DbServer? connection;

  /// 当前选中数据库（null = 未选/全部库）。
  final String? databaseName;

  /// Schema 上下文开关（宿主持有状态）。
  final bool schemaContextEnabled;

  final ValueChanged<bool> onSchemaContextChanged;

  const AiContextPanel({
    super.key,
    required this.connection,
    required this.databaseName,
    required this.schemaContextEnabled,
    required this.onSchemaContextChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;
    // 局部变量承接，使下方空检查可做类型提升（字段不参与提升）
    final conn = connection;

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
            l10n.aiContextPanelTitle,
            style: AppTextStyles.label.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: colors.textMuted,
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: colors.dividerColor),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(AppDesignSystem.space3),
            children: [
              // 当前连接
              Text(
                l10n.aiContextConnectionSection,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space1_5),
              if (conn == null)
                _InfoCard(
                  icon: LucideIcons.unplug,
                  title: l10n.aiContextNoConnection,
                  subtitle: null,
                )
              else
                _InfoCard(
                  icon: conn.type.typeIcon,
                  title: conn.name.isNotEmpty
                      ? conn.name
                      : '${conn.host}:${conn.port}',
                  subtitle: conn.host,
                ),
              const SizedBox(height: AppDesignSystem.space4),

              // 当前数据库
              Text(
                l10n.aiContextDatabaseSection,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space1_5),
              _InfoCard(
                icon: LucideIcons.database,
                title: databaseName ?? l10n.aiPanelAllDatabases,
                subtitle: conn?.host,
              ),
              const SizedBox(height: AppDesignSystem.space4),

              // Schema 上下文 toggle
              Container(
                decoration: BoxDecoration(
                  color: colors.bgTertiary,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(color: colors.borderLight),
                ),
                padding: const EdgeInsets.all(AppDesignSystem.space2_5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.table2,
                          size: 14,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: AppDesignSystem.space2),
                        Expanded(
                          child: Text(
                            l10n.aiContextSchemaContext,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        Switch(
                          value: schemaContextEnabled,
                          onChanged: onSchemaContextChanged,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppDesignSystem.space1),
                    Text(
                      l10n.aiContextSchemaContextDesc,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const _InfoCard({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space2_5),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Icon(icon, size: 14, color: colors.accentPurple),
          ),
          const SizedBox(width: AppDesignSystem.space2_5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
