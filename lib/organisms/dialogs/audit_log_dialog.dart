import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../services/audit_log_service.dart';
import '../../models/audit_log_entry.dart';

class AuditLogDialog extends StatefulWidget {
  const AuditLogDialog({super.key});

  static void show(BuildContext context) {
    showDialog(context: context, builder: (context) => const AuditLogDialog());
  }

  @override
  State<AuditLogDialog> createState() => _AuditLogDialogState();
}

class _AuditLogDialogState extends State<AuditLogDialog> {
  final AuditLogService _auditLog = AuditLogService();
  List<AuditLogEntry> _entries = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool? _filterSuccess;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    await _auditLog.initialize();
    setState(() {
      _entries = _auditLog.getRecentEntries(limit: 1000);
      _isLoading = false;
    });
  }

  List<AuditLogEntry> get _filteredEntries {
    return _entries.where((entry) {
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!entry.sql.toLowerCase().contains(query) &&
            !(entry.connectionName?.toLowerCase().contains(query) ?? false)) {
          return false;
        }
      }
      if (_filterSuccess != null && entry.success != _filterSuccess) {
        return false;
      }
      if (_startDate != null && entry.timestamp.isBefore(_startDate!)) {
        return false;
      }
      if (_endDate != null && entry.timestamp.isAfter(_endDate!)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      backgroundColor: colors.bgPrimary,
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(AppDesignSystem.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.history,
                      color: colors.accentBlue,
                      size: 24,
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    Text(
                      l10n.auditLogTitle,
                      style: TextStyle(
                        fontSize: AppDesignSystem.fontSize2xl,
                        fontWeight: AppDesignSystem.fontWeightBold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _exportLogs(),
                      icon: Icon(LucideIcons.download, size: 16),
                      label: Text(l10n.toolbarExport),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    TextButton.icon(
                      onPressed: () => _clearLogs(),
                      icon: Icon(
                        LucideIcons.trash2,
                        size: 16,
                        color: colors.accentRed,
                      ),
                      label: Text(
                        l10n.bottomPanelLogsClearAll,
                        style: TextStyle(color: colors.accentRed),
                      ),
                    ),
                    const SizedBox(width: AppDesignSystem.space2),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(LucideIcons.x),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppDesignSystem.space4),
            _buildFilterBar(),
            const SizedBox(height: AppDesignSystem.space4),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredEntries.isEmpty
                  ? _buildEmptyState()
                  : _buildLogTable(),
            ),
            const SizedBox(height: AppDesignSystem.space2),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: TextField(
            decoration: InputDecoration(
              hintText: l10n.dlgSearchHint,
              prefixIcon: Icon(LucideIcons.search, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space3,
                vertical: AppDesignSystem.space2,
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space3),
        DropdownButton<bool?>(
          value: _filterSuccess,
          hint: Text(l10n.auditLogAllStatus),
          underline: Container(),
          items: [
            DropdownMenuItem(value: null, child: Text(l10n.auditLogAll)),
            DropdownMenuItem(value: true, child: Text(l10n.commonSuccess)),
            DropdownMenuItem(value: false, child: Text(l10n.commonFailed)),
          ],
          onChanged: (value) => setState(() => _filterSuccess = value),
        ),
      ],
    );
  }

  Widget _buildLogTable() {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderLight),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
              vertical: AppDesignSystem.space2,
            ),
            decoration: BoxDecoration(
              color: colors.bgSecondary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppDesignSystem.radiusSm),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    l10n.auditLogTime,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    l10n.searchTypeConnection,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'SQL',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.auditLogDuration,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.auditLogRows,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: Text(
                    l10n.auditLogStatus,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(width: AppDesignSystem.space10),
              ],
            ),
          ),
          // Body
          Expanded(
            child: ListView.builder(
              itemCount: _filteredEntries.length,
              itemBuilder: (context, index) {
                final entry = _filteredEntries[index];
                return _buildLogRow(entry, index % 2 == 0);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogRow(AuditLogEntry entry, bool isEven) {
    final colors = context.themeColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      color: isEven
          ? colors.bgPrimary
          : colors.bgSecondary.withValues(alpha: 0.5),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entry.connectionName ?? entry.connectionId,
              style: TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              entry.sql.length > 60
                  ? '${entry.sql.substring(0, 60)}...'
                  : entry.sql,
              style: TextStyle(
                fontSize: 12,
                fontFamily: AppDesignSystem.monoFontFamily,

                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: entry.isWriteQuery
                    ? colors.accentOrange
                    : colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              '${entry.executionTime.inMilliseconds}ms',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              entry.rowCount?.toString() ?? '-',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space1_5,
                vertical: AppDesignSystem.space0_5,
              ),
              decoration: BoxDecoration(
                color: entry.success
                    ? colors.accentGreen.withValues(alpha: 0.1)
                    : colors.accentRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                entry.success
                    ? AppLocalizations.of(context)!.commonSuccess
                    : AppLocalizations.of(context)!.commonFailed,
                style: TextStyle(
                  fontSize: 11,
                  color: entry.success ? colors.accentGreen : colors.accentRed,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: IconButton(
              icon: Icon(
                LucideIcons.copy,
                size: 14,
                color: colors.textSecondary,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: entry.sql));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context)!.sidebarSqlCopied,
                    ),
                  ),
                );
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.history,
            size: 48,
            color: context.themeColors.textMuted,
          ),
          const SizedBox(height: AppDesignSystem.space4),
          Text(
            l10n.auditLogEmpty,
            style: TextStyle(
              fontSize: 16,
              color: context.themeColors.textMuted,
            ),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n.auditLogEmptyHint,
            style: TextStyle(
              fontSize: 13,
              color: context.themeColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final l10n = AppLocalizations.of(context)!;
    final stats = _auditLog.getStatistics();
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppDesignSystem.space2,
        horizontal: AppDesignSystem.space3,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat(l10n.auditLogTotal, stats['totalQueries'].toString()),
          _buildStat(
            l10n.commonSuccess,
            stats['successfulQueries'].toString(),
            color: context.themeColors.accentGreen,
          ),
          _buildStat(
            l10n.commonFailed,
            stats['failedQueries'].toString(),
            color: context.themeColors.accentRed,
          ),
          _buildStat(
            l10n.auditLogWrite,
            stats['writeQueries'].toString(),
            color: context.themeColors.accentOrange,
          ),
          _buildStat(
            l10n.auditLogAvgTime,
            '${stats['avgExecutionTimeMs'].toStringAsFixed(0)}ms',
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value, {Color? color}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color ?? context.themeColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: context.themeColors.textSecondary,
          ),
        ),
      ],
    );
  }

  void _exportLogs() {
    final l10n = AppLocalizations.of(context)!;
    final buffer = StringBuffer();
    buffer.writeln(
      'Timestamp,Connection,Database,SQL,Duration(ms),Rows,Status,Error',
    );
    for (final entry in _filteredEntries) {
      buffer.writeln(
        '"${entry.timestamp.toIso8601String()}",'
        '"${entry.connectionName ?? entry.connectionId}",'
        '"${entry.databaseName ?? ''}",'
        '"${entry.sql.replaceAll('"', '""')}",'
        '${entry.executionTime.inMilliseconds},'
        '${entry.rowCount ?? ''},'
        '${entry.success ? l10n.commonSuccess : l10n.commonFailed},'
        '"${entry.errorMessage ?? ''}"',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.sidebarLogsExported)));
  }

  void _clearLogs() {
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.auditLogClearTitle),
          content: Text(l10n.auditLogClearConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel),
            ),
            TextButton(
              onPressed: () async {
                await _auditLog.clearLogs();
                if (!mounted) return;
                setState(() {
                  _entries = [];
                });
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: Text(
                l10n.auditLogClear,
                style: TextStyle(color: context.themeColors.accentRed),
              ),
            ),
          ],
        );
      },
    );
  }
}
