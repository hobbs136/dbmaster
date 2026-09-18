import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/table_maintenance_command.dart';

/// 展示表维护命令（ANALYZE / OPTIMIZE / CHECK TABLE）执行结果。
class TableMaintenanceResultDialog extends StatelessWidget {
  final String tableName;
  final TableMaintenanceCommand command;
  final String sql;
  final List<Map<String, dynamic>> results;

  const TableMaintenanceResultDialog({
    super.key,
    required this.tableName,
    required this.command,
    required this.sql,
    required this.results,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final columns = results.isNotEmpty
        ? results.first.keys.toList()
        : <String>[];

    return AlertDialog(
      backgroundColor: context.themeColors.bgSecondary,
      title: Row(
        children: [
          Icon(_icon(), color: context.themeColors.accentBlue),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: Text(
              _title(l10n),
              style: TextStyle(color: context.themeColors.textPrimary),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.maintenanceExecutedSql,
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppDesignSystem.space2),
              decoration: BoxDecoration(
                color: context.themeColors.bgTertiary,
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                sql,
                style: TextStyle(
                  color: context.themeColors.textPrimary,
                  fontSize: 12,
                  fontFamily: AppDesignSystem.monoFontFamily,

                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                ),
              ),
            ),
            const SizedBox(height: AppDesignSystem.space3),
            Text(
              l10n.maintenanceResult,
              style: TextStyle(
                color: context.themeColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppDesignSystem.space1),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: context.themeColors.borderSubtle,
                  ),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppDesignSystem.space3),
                        child: Text(
                          l10n.noInformation,
                          style: TextStyle(
                            color: context.themeColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            context.themeColors.bgTertiary,
                          ),
                          border: TableBorder.symmetric(
                            inside: BorderSide(
                              color: context.themeColors.borderSubtle,
                            ),
                          ),
                          columns: columns
                              .map(
                                (c) => DataColumn(
                                  label: Text(
                                    c,
                                    style: TextStyle(
                                      color: context.themeColors.textPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          rows: results.map((row) {
                            return DataRow(
                              cells: columns
                                  .map(
                                    (c) => DataCell(
                                      Text(
                                        row[c]?.toString() ?? '',
                                        style: TextStyle(
                                          color:
                                              context.themeColors.textPrimary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          }).toList(),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }

  String _title(AppLocalizations l10n) {
    switch (command) {
      case TableMaintenanceCommand.analyze:
        return l10n.analyzeTableResultTitle(tableName);
      case TableMaintenanceCommand.optimize:
        return l10n.optimizeTableResultTitle(tableName);
      case TableMaintenanceCommand.check:
        return l10n.checkTableResultTitle(tableName);
      case TableMaintenanceCommand.vacuum:
        return l10n.vacuumTableResultTitle(tableName);
      case TableMaintenanceCommand.vacuumFull:
        return l10n.vacuumFullTableResultTitle(tableName);
      case TableMaintenanceCommand.pgAnalyze:
        return l10n.analyzeTablePgResultTitle(tableName);
      case TableMaintenanceCommand.reindex:
        return l10n.reindexTableResultTitle(tableName);
      case TableMaintenanceCommand.reindexConcurrently:
        return l10n.reindexConcurrentlyTableResultTitle(tableName);
      case TableMaintenanceCommand.cluster:
        return l10n.clusterTableResultTitle(tableName);
    }
  }

  IconData _icon() {
    switch (command) {
      case TableMaintenanceCommand.analyze:
        return LucideIcons.chartLine;
      case TableMaintenanceCommand.optimize:
        return LucideIcons.database;
      case TableMaintenanceCommand.check:
        return LucideIcons.clipboardCheck;
      case TableMaintenanceCommand.vacuum:
        return LucideIcons.sprayCan;
      case TableMaintenanceCommand.vacuumFull:
        return LucideIcons.sprayCan;
      case TableMaintenanceCommand.pgAnalyze:
        return LucideIcons.chartLine;
      case TableMaintenanceCommand.reindex:
        return LucideIcons.wrench;
      case TableMaintenanceCommand.reindexConcurrently:
        return LucideIcons.wrench;
      case TableMaintenanceCommand.cluster:
        return LucideIcons.arrowUpDown;
    }
  }
}
