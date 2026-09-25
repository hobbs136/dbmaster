import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/schema_analyzer/impact_report.dart';
import '../../../providers/app_provider.dart';
import '../../../theme/app_colors.dart';

/// Schema Impact Analysis 结果卡片
class SchemaImpactCard extends StatefulWidget {
  final Map<String, dynamic> data;

  const SchemaImpactCard({super.key, required this.data});

  @override
  State<SchemaImpactCard> createState() => _SchemaImpactCardState();
}

class _SchemaImpactCardState extends State<SchemaImpactCard> {
  bool _showRollback = false;

  RiskLevel _parseRiskLevel(String? level) {
    switch (level?.toLowerCase()) {
      case 'low':
        return RiskLevel.low;
      case 'medium':
        return RiskLevel.medium;
      case 'high':
        return RiskLevel.high;
      case 'critical':
        return RiskLevel.critical;
      default:
        return RiskLevel.low;
    }
  }

  Color _getRiskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return context.themeColors.success;
      case RiskLevel.medium:
        return context.themeColors.warning;
      case RiskLevel.high:
        return Colors.orange;
      case RiskLevel.critical:
        return context.themeColors.error;
    }
  }

  IconData _getRiskIcon(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return LucideIcons.circleCheckBig;
      case RiskLevel.medium:
        return LucideIcons.info;
      case RiskLevel.high:
        return LucideIcons.triangleAlert;
      case RiskLevel.critical:
        return LucideIcons.circleAlert;
    }
  }

  String _getRiskLabel(RiskLevel level) {
    final l10n = AppLocalizations.of(context)!;
    switch (level) {
      case RiskLevel.low:
        return l10n.schemaImpactRiskLow;
      case RiskLevel.medium:
        return l10n.schemaImpactRiskMedium;
      case RiskLevel.high:
        return l10n.schemaImpactRiskHigh;
      case RiskLevel.critical:
        return l10n.schemaImpactRiskCritical;
    }
  }

  IconData _getObjectTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'view':
        return LucideIcons.eye;
      case 'procedure':
        return LucideIcons.functionSquare;
      case 'function':
        return LucideIcons.code;
      case 'trigger':
        return LucideIcons.zap;
      case 'foreignkey':
      case 'foreign_key':
        return LucideIcons.link;
      case 'index':
      case 'index_':
        return LucideIcons.arrowUpDown;
      case 'constraint':
        return LucideIcons.gavel;
      default:
        return LucideIcons.circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final riskLevel = _parseRiskLevel(widget.data['riskLevel'] as String?);
    final riskColor = _getRiskColor(riskLevel);
    final ddlType = widget.data['ddlType'] as String? ?? 'DDL';
    final targetTable =
        widget.data['targetTable'] as String? ??
        AppLocalizations.of(context)!.commonUnknown;
    final affectedObjects =
        (widget.data['affectedObjects'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
    final warnings = (widget.data['warnings'] as List<dynamic>? ?? [])
        .cast<String>();
    final recommendations =
        (widget.data['recommendations'] as List<dynamic>? ?? []).cast<String>();
    final rollbackData = widget.data['rollbackScript'] as Map<String, dynamic>?;
    final requiresConfirmation =
        widget.data['requiresConfirmation'] as bool? ?? false;
    final hasDataLossRisk = widget.data['hasDataLossRisk'] as bool? ?? false;
    final isOverlay = context.watch<AppProvider>().isAiPanelOverlay;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isOverlay ? Colors.transparent : context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: riskColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2_5,
            ),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppDesignSystem.radiusMd),
              ),
            ),
            child: Row(
              children: [
                Icon(_getRiskIcon(riskLevel), size: 18, color: riskColor),
                const SizedBox(width: AppDesignSystem.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.schemaImpactTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.themeColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppDesignSystem.space0_5),
                      Text(
                        AppLocalizations.of(
                          context,
                        )!.schemaImpactSubtitle(targetTable, ddlType),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.themeColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space2,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Text(
                    _getRiskLabel(riskLevel),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: riskColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 数据丢失风险警告
          if (hasDataLossRisk) ...[
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.themeColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(
                  color: context.themeColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.trash2,
                    size: 16,
                    color: context.themeColors.error,
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context)!.schemaImpactDataLossWarning,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.themeColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 受影响对象
          if (affectedObjects.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Text(
                AppLocalizations.of(
                  context,
                )!.schemaImpactAffectedObjects(affectedObjects.length),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textSecondary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: affectedObjects.map((obj) {
                  final type = obj['type'] as String? ?? 'object';
                  final name =
                      obj['name'] as String? ??
                      AppLocalizations.of(context)!.commonUnknown;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppDesignSystem.space2,
                      vertical: AppDesignSystem.space1,
                    ),
                    decoration: BoxDecoration(
                      color: context.themeColors.bgSecondary,
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                      border: Border.all(
                        color: context.themeColors.borderSubtle,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getObjectTypeIcon(type),
                          size: 12,
                          color: context.themeColors.textMuted,
                        ),
                        const SizedBox(width: AppDesignSystem.space1),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.themeColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // 警告
          if (warnings.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                AppLocalizations.of(
                  context,
                )!.schemaImpactWarnings(warnings.length),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.warning,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: warnings.map((warning) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.triangleAlert,
                          size: 12,
                          color: context.themeColors.warning,
                        ),
                        const SizedBox(width: AppDesignSystem.space1_5),
                        Expanded(
                          child: Text(
                            warning,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.themeColors.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // 推荐
          if (recommendations.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Text(
                AppLocalizations.of(context)!.schemaImpactRecommendations,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.success,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: recommendations.map((rec) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          LucideIcons.lightbulb,
                          size: 12,
                          color: context.themeColors.success,
                        ),
                        const SizedBox(width: AppDesignSystem.space1_5),
                        Expanded(
                          child: Text(
                            rec,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.themeColors.textSecondary,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // 回滚脚本
          if (rollbackData != null) ...[
            const SizedBox(height: AppDesignSystem.space2_5),
            InkWell(
              onTap: () => setState(() => _showRollback = !_showRollback),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space3,
                  vertical: AppDesignSystem.space1_5,
                ),
                child: Row(
                  children: [
                    Icon(
                      _showRollback
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                      color: context.themeColors.accentPurple,
                    ),
                    const SizedBox(width: AppDesignSystem.space1_5),
                    Text(
                      _showRollback
                          ? AppLocalizations.of(
                              context,
                            )!.schemaImpactHideRollbackScript
                          : AppLocalizations.of(
                              context,
                            )!.schemaImpactShowRollbackScript,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: context.themeColors.accentPurple,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showRollback) ...[
              Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.themeColors.bgSecondary,
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                  border: Border.all(
                    color: context.themeColors.borderSubtle,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rollbackData['description'] != null)
                      Text(
                        rollbackData['description'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.themeColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const SizedBox(height: AppDesignSystem.space1_5),
                    SelectableText(
                      rollbackData['rollbackDdl'] as String? ??
                          AppLocalizations.of(
                            context,
                          )!.schemaImpactNoRollbackAvailable,
                      style: TextStyle(
                        fontFamily: AppDesignSystem.monoFontFamily,

                        fontFamilyFallback:
                            AppDesignSystem.monoFontFamilyFallback,
                        fontSize: 11,
                        color: context.themeColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (rollbackData['requiresDataBackup'] == true) ...[
                      const SizedBox(height: AppDesignSystem.space1_5),
                      Row(
                        children: [
                          Icon(
                            LucideIcons.databaseBackup,
                            size: 12,
                            color: context.themeColors.warning,
                          ),
                          const SizedBox(width: AppDesignSystem.space1),
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.schemaImpactBackupRequired,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.themeColors.warning,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],

          // 需要确认提示
          if (requiresConfirmation) ...[
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.themeColors.error.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(
                  color: context.themeColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.shield,
                    size: 16,
                    color: context.themeColors.error,
                  ),
                  const SizedBox(width: AppDesignSystem.space2),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(
                        context,
                      )!.schemaImpactConfirmationRequired,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.themeColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppDesignSystem.space2_5),
        ],
      ),
    );
  }
}
