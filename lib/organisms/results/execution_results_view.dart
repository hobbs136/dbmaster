import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../models/execution_result.dart';
import '../../models/execution_summary.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';

/// ExecutionResultsView - 多语句执行结果展示
/// 显示批量 SQL 执行后的汇总和各个语句的结果
class ExecutionResultsView extends StatelessWidget {
  final List<ExecutionResult>? executionResults;
  final Function(ExecutionResult result, int index) buildExecutionResultItem;

  const ExecutionResultsView({
    super.key,
    required this.executionResults,
    required this.buildExecutionResultItem,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (executionResults == null || executionResults!.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.clipboardList,
        title: l10n.resultsNoDataTitle,
        message: l10n.resultsNoDataMessage,
      );
    }

    final summary = ExecutionSummary.fromResults(
      executionResults!,
      DateTime.now().subtract(
        executionResults!.fold(
          Duration.zero,
          (sum, r) => sum + r.executionTime,
        ),
      ),
      DateTime.now(),
    );

    return Column(
      children: [
        _buildExecutionSummary(context, summary),
        Expanded(
          child: ListView.builder(
            itemCount: executionResults!.length,
            itemBuilder: (context, index) {
              final result = executionResults![index];
              return buildExecutionResultItem(result, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExecutionSummary(
    BuildContext context,
    ExecutionSummary summary,
  ) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Icon(
            summary.allSuccess
                ? LucideIcons.circleCheckBig
                : LucideIcons.triangleAlert,
            color: summary.allSuccess
                ? context.themeColors.accentGreen
                : context.themeColors.accentOrange,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.executionPlan,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: context.themeColors.textPrimary,
                  ),
                ),
                Text(
                  l10n.executionTime,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.themeColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.bgSecondary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              '${summary.totalTime.inMilliseconds}ms',
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textSecondary,
              ),
            ),
          ),
          if (summary.totalAffectedRows > 0) ...[
            const SizedBox(width: AppDesignSystem.space2),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.accentBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                l10n.executeSuccessRows(summary.totalAffectedRows),
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.accentBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ExecutionResultItem - 单个执行结果项
class ExecutionResultItem extends StatelessWidget {
  final ExecutionResult result;
  final int index;

  const ExecutionResultItem({
    super.key,
    required this.result,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSuccess = result.success;

    final sqlPreview = result.statement.sql.length > 60
        ? '${result.statement.sql.substring(0, 60)}...'
        : result.statement.sql;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: isSuccess
            ? context.themeColors.bgTertiary
            : context.themeColors.accentRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: isSuccess
              ? context.themeColors.borderLight
              : context.themeColors.accentRed.withValues(alpha: 0.3),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
            vertical: AppDesignSystem.space1,
          ),
          childrenPadding: EdgeInsets.zero,
          leading: Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space1,
            ),
            decoration: BoxDecoration(
              color: isSuccess
                  ? context.themeColors.accentGreen
                  : context.themeColors.accentRed,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            sqlPreview,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.themeColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: [
              Text(
                '${result.executionTime.inMilliseconds}ms',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textSecondary,
                ),
              ),
              if (result.affectedRows != null) ...[
                const SizedBox(width: AppDesignSystem.space2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDesignSystem.space1_5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: context.themeColors.accentBlue.withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(
                      AppDesignSystem.radiusSm,
                    ),
                  ),
                  child: Text(
                    l10n.executeSuccessRows(result.affectedRows!),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.themeColors.accentBlue,
                    ),
                  ),
                ),
              ],
            ],
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(AppDesignSystem.space3),
              decoration: BoxDecoration(
                color: context.themeColors.bgPrimary,
                border: Border(
                  top: BorderSide(
                    color: context.themeColors.borderSubtle,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSqlStatement(context, l10n),
                  if (result.errorMessage != null) ...[
                    const SizedBox(height: AppDesignSystem.space3),
                    _buildErrorSection(context, l10n),
                  ],
                  if (result.isTruncated) ...[
                    const SizedBox(height: AppDesignSystem.space2),
                    _buildTruncationWarning(context, l10n),
                  ],
                  if (result.hasData) ...[
                    const SizedBox(height: AppDesignSystem.space3),
                    _buildDataPreview(context, l10n),
                  ],
                  if (result.affectedRows != null && !result.hasData) ...[
                    const SizedBox(height: AppDesignSystem.space2),
                    _buildAffectedRows(context, l10n),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSqlStatement(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.performanceAnalyzerSqlStatement,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: context.themeColors.bgSecondary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SelectableText(
            result.statement.sql,
            style: TextStyle(
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: 11,
              color: context.themeColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorSection(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.commonError,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.themeColors.accentRed,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppDesignSystem.space2),
          decoration: BoxDecoration(
            color: context.themeColors.accentRed.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SelectableText(
            result.errorMessage!,
            style: TextStyle(
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              fontSize: 11,
              color: context.themeColors.accentRed,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDataPreview(BuildContext context, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.dataPreviewRows(result.data!.length),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: context.themeColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppDesignSystem.space1),
        Container(
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: context.themeColors.borderLight),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  context.themeColors.bgTertiary,
                ),
                columns: result.data!.first.keys.map((col) {
                  return DataColumn(
                    label: Text(
                      col,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.themeColors.textSecondary,
                      ),
                    ),
                  );
                }).toList(),
                rows: result.data!.take(100).map((row) {
                  return DataRow(
                    cells: result.data!.first.keys.map((col) {
                      return DataCell(
                        Text(
                          row[col]?.toString() ?? 'NULL',
                          style: TextStyle(
                            fontSize: 11,
                            color: row[col] == null
                                ? context.themeColors.textMuted
                                : context.themeColors.textPrimary,
                          ),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAffectedRows(BuildContext context, AppLocalizations l10n) {
    return Text(
      l10n.executeSuccessRows(result.affectedRows!),
      style: TextStyle(fontSize: 11, color: context.themeColors.accentBlue),
    );
  }

  Widget _buildTruncationWarning(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2_5,
        vertical: AppDesignSystem.space1_5,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(
          color: context.themeColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 14,
            color: context.themeColors.warning,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              l10n.resultsTruncatedMessage(result.limitValue ?? 0),
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 48, color: context.themeColors.textMuted),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
