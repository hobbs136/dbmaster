import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../molecules/destructive_confirm_dialog.dart';
import '../../models/database_models.dart';
import '../../models/dml_risk_models.dart';
import '../../models/sql_statement.dart';
import '../../services/sql_parser_service.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Result returned by [DmlConfirmDialog].
enum DmlConfirmResult { confirm, cancel }

/// Modal confirmation dialog for critical-risk DML operations.
///
/// Displayed when a user attempts to execute a statement like DELETE without
/// WHERE, DROP TABLE, or TRUNCATE. Requires the user to type the object name
/// to confirm execution.
class DmlConfirmDialog extends StatefulWidget {
  final RiskAnalysisResult analysis;
  final List<SQLStatement> statements;
  final DatabaseType dbType;
  final int? estimatedRows;

  const DmlConfirmDialog({
    super.key,
    required this.analysis,
    required this.statements,
    required this.dbType,
    this.estimatedRows,
  });

  /// Show the dialog and return the user's decision.
  static Future<DmlConfirmResult?> show(
    BuildContext context, {
    required RiskAnalysisResult analysis,
    required List<SQLStatement> statements,
    required DatabaseType dbType,
    int? estimatedRows,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DmlConfirmDialog(
        analysis: analysis,
        statements: statements,
        dbType: dbType,
        estimatedRows: estimatedRows,
      ),
    );
    return confirmed == true
        ? DmlConfirmResult.confirm
        : DmlConfirmResult.cancel;
  }

  @override
  State<DmlConfirmDialog> createState() => _DmlConfirmDialogState();
}

class _DmlConfirmDialogState extends State<DmlConfirmDialog> {
  String? _expectedName;

  @override
  void initState() {
    super.initState();
    // The expected confirmation name is the first affected object, if any.
    _expectedName = widget.analysis.affectedObjects.isNotEmpty
        ? widget.analysis.affectedObjects.first
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return DestructiveConfirmDialog(
      icon: LucideIcons.triangleAlert,
      title: l10n?.dmlCriticalTitle ?? 'Critical Risk Operation',
      impactTone: DestructiveTone.error,
      confirmLabel: l10n?.dmlConfirmExecute ?? 'Confirm Execution',
      onConfirm: () => Navigator.of(context).pop(true),
      requireTypedConfirmation: _expectedName,
      contentWidth: 520,
      extraContent: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Risk summary
          _buildRiskSummary(l10n),
          const SizedBox(height: 16),

          // Statements with risk levels
          _buildStatementsList(l10n),
          const SizedBox(height: 16),

          // Estimated affected rows
          _buildRowEstimate(l10n),
        ],
      ),
    );
  }

  Widget _buildRiskSummary(AppLocalizations? l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.themeColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(
          color: context.themeColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n?.dmlRiskSummary ?? 'Risk Summary',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: context.themeColors.error,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.analysis.triggers.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.circleAlert,
                    size: 16,
                    color: context.themeColors.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_triggerLabel(t, l10n))),
                ],
              ),
            ),
          ),
          if (widget.analysis.hasInjectionPattern) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  LucideIcons.shield,
                  size: 16,
                  color: context.themeColors.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    l10n?.dmlSqlInjectionDetail(
                          widget.analysis.injectionDetails ?? '',
                        ) ??
                        'SQL Injection: ${widget.analysis.injectionDetails ?? ""}',
                    style: TextStyle(color: context.themeColors.error),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatementsList(AppLocalizations? l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n?.dmlStatementsToExecute ?? 'Statements to execute:',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...widget.statements.map((stmt) {
          final riskColor = _riskColor(stmt);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          AppDesignSystem.radiusSm,
                        ),
                      ),
                      child: Text(
                        _typeLabel(stmt.type),
                        style: TextStyle(
                          fontSize: 11,
                          color: riskColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stmt.sql.length > 120
                            ? '${stmt.sql.substring(0, 120)}...'
                            : stmt.sql,
                        style: const TextStyle(
                          fontFamily: AppDesignSystem.monoFontFamily,

                          fontFamilyFallback:
                              AppDesignSystem.monoFontFamilyFallback,
                          fontSize: 12,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRowEstimate(AppLocalizations? l10n) {
    final rows = widget.estimatedRows;
    if (rows == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.rows3, size: 18, color: Colors.orange[700]),
          const SizedBox(width: 8),
          Text(
            l10n?.dmlEstimatedAffectedRows(rows) ??
                'Estimated affected rows: $rows',
            style: TextStyle(color: Colors.orange[800]),
          ),
        ],
      ),
    );
  }

  String _typeLabel(SQLType type) {
    switch (type) {
      case SQLType.delete:
        return 'DELETE';
      case SQLType.update:
        return 'UPDATE';
      case SQLType.insert:
        return 'INSERT';
      case SQLType.select:
        return 'SELECT';
      case SQLType.ddl:
        return 'DDL';
      case SQLType.call:
        return 'CALL';
      case SQLType.other:
        return 'SQL';
    }
  }

  Color _riskColor(SQLStatement stmt) {
    switch (stmt.type) {
      case SQLType.delete:
      case SQLType.update:
        if (!SQLParserService.hasWhereClause(stmt.sql)) {
          return context.themeColors.error;
        }
        return Colors.orange;
      case SQLType.ddl:
        final sub = SQLParserService.detectDdlSubType(stmt.sql);
        if (sub == DdlSubType.dropTable ||
            sub == DdlSubType.dropDatabase ||
            sub == DdlSubType.truncate) {
          return context.themeColors.error;
        }
        if (sub == DdlSubType.alterDropColumn) {
          return Colors.orange;
        }
        return Colors.grey;
      default:
        return Colors.green;
    }
  }

  String _triggerLabel(RiskTrigger trigger, AppLocalizations? l10n) {
    switch (trigger) {
      case RiskTrigger.deleteWithoutWhere:
        return l10n?.dmlTriggerDeleteWithoutWhere ??
            'DELETE without WHERE clause';
      case RiskTrigger.updateWithoutWhere:
        return l10n?.dmlTriggerUpdateWithoutWhere ??
            'UPDATE without WHERE clause';
      case RiskTrigger.dropTable:
        return l10n?.dmlTriggerDropTable ?? 'DROP TABLE operation';
      case RiskTrigger.dropDatabase:
        return l10n?.dmlTriggerDropDatabase ?? 'DROP DATABASE operation';
      case RiskTrigger.truncateTable:
        return l10n?.dmlTriggerTruncateTable ?? 'TRUNCATE TABLE operation';
      case RiskTrigger.dmlWithoutLimit:
        return l10n?.dmlTriggerDmlWithoutLimit ?? 'DML without LIMIT clause';
      case RiskTrigger.alterDropColumn:
        return l10n?.dmlTriggerAlterDropColumn ?? 'ALTER TABLE DROP COLUMN';
      case RiskTrigger.sqlInjection:
        return l10n?.dmlTriggerSqlInjection ?? 'SQL injection pattern detected';
      // Doris UPDATE 模型守卫（本地化文案）
      case RiskTrigger.dorisUpdateOnNonUpdatableModel:
        return l10n?.dorisUpdateGuardMessage ??
            'Doris UPDATE not supported on Duplicate/Aggregate model';
    }
  }
}
