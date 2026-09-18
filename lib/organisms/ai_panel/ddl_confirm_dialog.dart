import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/schema_analyzer/ddl_algorithm.dart';
import '../../models/schema_analyzer/impact_report.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

enum DdlConfirmResult { cancel, execute }

/// DDL 执行确认对话框
/// 展示 Schema Impact Analysis 的详细结果
class DdlConfirmDialog extends StatefulWidget {
  final String sql;
  final ImpactReport impactReport;

  const DdlConfirmDialog({
    super.key,
    required this.sql,
    required this.impactReport,
  });

  @override
  State<DdlConfirmDialog> createState() => _DdlConfirmDialogState();
}

class _DdlConfirmDialogState extends State<DdlConfirmDialog> {
  bool _showRollback = false;
  final TextEditingController _confirmController = TextEditingController();

  Color get _riskColor {
    switch (widget.impactReport.riskLevel) {
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

  IconData get _riskIcon {
    switch (widget.impactReport.riskLevel) {
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

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  String get _riskLabel {
    switch (widget.impactReport.riskLevel) {
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

  bool get _requiresTextConfirm =>
      widget.impactReport.riskLevel == RiskLevel.critical;

  bool get _canExecute {
    if (!_requiresTextConfirm) return true;
    final expected = _getConfirmText();
    return _confirmController.text.trim().toUpperCase() == expected;
  }

  String _getConfirmText() {
    // CRITICAL 风险需要输入确认文本
    final table = widget.impactReport.targetTable.toUpperCase();
    return 'DROP $table';
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
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Icon(_riskIcon, color: _riskColor),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              l10n.ddlConfirmDialogTitle,
              style: TextStyle(
                color: context.themeColors.textPrimary,
                fontSize: AppDesignSystem.fontSize2xl,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSqlPreview(context),
            const SizedBox(height: AppDesignSystem.space3),
            _buildRiskLevelCard(context),
            // 第四阶段：锁信息区块（风险卡之后、受影响对象之前）。
            if (_shouldShowLockInfo) ...[
              const SizedBox(height: AppDesignSystem.space3),
              _buildLockInfoCard(context),
            ],
            if (widget.impactReport.affectedObjects.isNotEmpty) ...[
              const SizedBox(height: AppDesignSystem.space3),
              Text(
                l10n.ddlAffectedObjectsCount(
                  widget.impactReport.affectedObjects.length,
                ),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppDesignSystem.space1_5),
              _buildAffectedObjectsChips(context),
            ],
            if (widget.impactReport.warnings.isNotEmpty) ...[
              const SizedBox(height: AppDesignSystem.space3),
              _buildWarningList(context),
            ],
            if (widget.impactReport.rollbackScript != null) ...[
              const SizedBox(height: AppDesignSystem.space3),
              _buildRollbackSection(context),
            ],
            if (_requiresTextConfirm) ...[
              const SizedBox(height: AppDesignSystem.space4),
              _buildCriticalConfirmation(context),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, DdlConfirmResult.cancel),
          child: Text(
            l10n.commonCancel,
            style: TextStyle(color: context.themeColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _canExecute
              ? () => Navigator.pop(context, DdlConfirmResult.execute)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.themeColors.error,
            foregroundColor: Colors.white,
            disabledBackgroundColor: context.themeColors.error.withValues(
              alpha: 0.3,
            ),
          ),
          child: Text(l10n.ddlExecuteButton),
        ),
      ],
    );
  }

  Widget _buildSqlPreview(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: _riskColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.ddlSqlStatementLabel,
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            widget.sql,
            style: TextStyle(
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: 11,
              color: context.themeColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiskLevelCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _riskColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: _riskColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(_riskIcon, size: 18, color: _riskColor),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.ddlRiskLevelLabel(_riskLabel),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _riskColor,
                  ),
                ),
                if (widget.impactReport.hasDataLossRisk) ...[
                  const SizedBox(height: AppDesignSystem.space0_5),
                  Text(
                    l10n.ddlDataLossRiskDetected,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.error,
                    ),
                  ),
                ],
              ], // close Column.children
            ), // close Column
          ), // close Expanded
        ], // close Row.children
      ), // close Row
    ); // close Container
  }

  /// 第四阶段：是否展示锁信息区块。
  /// algorithm=unknown 且无 note → 隐藏（避免噪音）；
  /// algorithm=unknown 但有 note（如「无法解析版本」）→ 展示「保守处理」。
  bool get _shouldShowLockInfo {
    final algo = widget.impactReport.ddlAlgorithm;
    return algo != DdlAlgorithm.unknown ||
        widget.impactReport.algorithmNote != null;
  }

  /// 第四阶段：锁信息卡片（design §4.6）。
  /// 按 algorithm 分色：instant 绿 / inplace 黄 / copy 红 / metadataOnly 绿 / unknown 灰。
  Widget _buildLockInfoCard(BuildContext context) {
    final algo = widget.impactReport.ddlAlgorithm;
    final (color, icon, label) = _lockDisplay(algo, context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label · ${widget.impactReport.lockType ?? "未知"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (widget.impactReport.algorithmNote != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.impactReport.algorithmNote!,
                    style: TextStyle(
                      fontSize: 10,
                      color: context.themeColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 锁信息展示的 (颜色, 图标, 标签) 三元组。
  (Color, IconData, String) _lockDisplay(
    DdlAlgorithm algo,
    BuildContext context,
  ) {
    switch (algo) {
      case DdlAlgorithm.instant:
        return (context.themeColors.success, LucideIcons.zap, '⚡ 秒级无锁，可在线执行');
      case DdlAlgorithm.inplace:
        return (
          context.themeColors.warning,
          LucideIcons.refreshCw,
          '允许并发 DML，轻微影响',
        );
      case DdlAlgorithm.copy:
        return (context.themeColors.error, LucideIcons.lock, '⚠️ 全表锁，阻塞所有写操作');
      case DdlAlgorithm.metadataOnly:
        return (context.themeColors.success, LucideIcons.zap, '元数据操作，瞬间完成');
      case DdlAlgorithm.unknown:
        return (
          context.themeColors.textMuted,
          LucideIcons.circleHelp,
          '锁行为未知（保守处理）',
        );
    }
  }

  Widget _buildAffectedObjectsChips(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: widget.impactReport.affectedObjects
          .map(
            (obj) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                border: Border.all(
                  color: context.themeColors.borderSubtle,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getObjectTypeIcon(obj.type.name),
                    size: 12,
                    color: context.themeColors.textMuted,
                  ),
                  const SizedBox(width: AppDesignSystem.space1),
                  Text(
                    obj.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildWarningList(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.ddlWarningsCount(widget.impactReport.warnings.length),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.themeColors.warning,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1_5),
        ...widget.impactReport.warnings.map(
          (w) => Padding(
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
                    w,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRollbackSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showRollback = !_showRollback),
          child: Row(
            children: [
              Icon(
                _showRollback ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16,
                color: context.themeColors.accentPurple,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                _showRollback
                    ? l10n.schemaImpactHideRollbackScript
                    : l10n.schemaImpactShowRollbackScript,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: context.themeColors.accentPurple,
                ),
              ),
            ],
          ),
        ),
        if (_showRollback) ...[
          const SizedBox(height: AppDesignSystem.space1_5),
          // Warn that auto-generated rollback is best-effort
          // and may have wrong column types/constraints (placeholder VARCHAR(255));
          // never trust it unverified on production data.
          Row(
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
                  l10n.schemaImpactRollbackCaveat,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.warning,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.themeColors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(
                color: context.themeColors.borderSubtle,
              ),
            ),
            child: SelectableText(
              widget.impactReport.rollbackScript!.rollbackDdl,
              style: TextStyle(
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                fontSize: 11,
                color: context.themeColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCriticalConfirmation(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.themeColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.shield,
                size: 14,
                color: context.themeColors.error,
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                l10n.ddlTypeConfirmationToProceed,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.themeColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          Text(
            l10n.ddlTypeToConfirmDestructive(_getConfirmText()),
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space1_5),
          TextField(
            controller: _confirmController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _getConfirmText(),
              hintStyle: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2_5,
                vertical: AppDesignSystem.space2,
              ),
            ),
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
