import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../molecules/destructive_confirm_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../models/table_maintenance_command.dart';

/// 表维护命令确认对话框。
class ConfirmMaintenanceDialog extends StatelessWidget {
  final String tableName;
  final TableMaintenanceCommand command;

  const ConfirmMaintenanceDialog({
    super.key,
    required this.tableName,
    required this.command,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return DestructiveConfirmDialog(
      icon: _icon(),
      title: _title(l10n),
      impactTone: DestructiveTone.warning,
      body: _message(l10n),
      impactDescription: _warning(l10n),
      confirmLabel: l10n.commonConfirm,
      onConfirm: () => Navigator.pop(context, true),
    );
  }

  String _title(AppLocalizations l10n) {
    switch (command) {
      case TableMaintenanceCommand.analyze:
        return l10n.confirmAnalyzeTable(tableName);
      case TableMaintenanceCommand.optimize:
        return l10n.confirmOptimizeTable(tableName);
      case TableMaintenanceCommand.check:
        return l10n.confirmCheckTable(tableName);
      case TableMaintenanceCommand.vacuum:
        return l10n.confirmVacuumTable(tableName);
      case TableMaintenanceCommand.vacuumFull:
        return l10n.confirmVacuumFullTable(tableName);
      case TableMaintenanceCommand.pgAnalyze:
        return l10n.confirmAnalyzeTablePg(tableName);
      case TableMaintenanceCommand.reindex:
        return l10n.confirmReindexTable(tableName);
      case TableMaintenanceCommand.reindexConcurrently:
        return l10n.confirmReindexConcurrentlyTable(tableName);
      case TableMaintenanceCommand.cluster:
        return l10n.confirmClusterTable(tableName);
    }
  }

  String _message(AppLocalizations l10n) {
    switch (command) {
      case TableMaintenanceCommand.analyze:
        return l10n.confirmAnalyzeTableMessage(tableName);
      case TableMaintenanceCommand.optimize:
        return l10n.confirmOptimizeTableMessage(tableName);
      case TableMaintenanceCommand.check:
        return l10n.confirmCheckTableMessage(tableName);
      case TableMaintenanceCommand.vacuum:
        return l10n.confirmVacuumTableMessage(tableName);
      case TableMaintenanceCommand.vacuumFull:
        return l10n.confirmVacuumFullTableMessage(tableName);
      case TableMaintenanceCommand.pgAnalyze:
        return l10n.confirmAnalyzeTablePgMessage(tableName);
      case TableMaintenanceCommand.reindex:
        return l10n.confirmReindexTableMessage(tableName);
      case TableMaintenanceCommand.reindexConcurrently:
        return l10n.confirmReindexConcurrentlyTableMessage(tableName);
      case TableMaintenanceCommand.cluster:
        return l10n.confirmClusterTableMessage(tableName);
    }
  }

  String? _warning(AppLocalizations l10n) {
    switch (command) {
      case TableMaintenanceCommand.optimize:
        return l10n.optimizeTableWarning;
      case TableMaintenanceCommand.vacuumFull:
        return l10n.vacuumFullWarning;
      case TableMaintenanceCommand.reindex:
        return l10n.reindexWarning;
      case TableMaintenanceCommand.cluster:
        return l10n.clusterWarning;
      default:
        return null;
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
