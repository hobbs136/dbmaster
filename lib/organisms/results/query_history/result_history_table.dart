import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/query_history.dart';
import '../../../services/pii_masker.dart';
import '../../../theme/app_colors.dart';
import '../../../molecules/compact_popup_menu_item.dart';

/// Maximum number of characters shown in the SQL preview before truncating.
const int _kMaxSqlPreviewLength = 120;

/// A read-only table that displays query history entries.
///
/// Columns: Executed At, SQL Preview, Duration, Row Count, Status.
/// Tapping a row invokes [onRowTap] with the corresponding history entry.
class ResultHistoryTable extends StatelessWidget {
  final List<QueryHistory> history;
  final ValueChanged<QueryHistory> onRowTap;
  final ValueChanged<QueryHistory>? onRowDoubleTap;
  final ValueChanged<QueryHistory>? onRowDelete;

  const ResultHistoryTable({
    super.key,
    required this.history,
    required this.onRowTap,
    this.onRowDoubleTap,
    this.onRowDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.themeColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TableHeader(l10n: l10n, colors: colors),
        Expanded(
          child: ListView.builder(
            itemCount: history.length,
            itemBuilder: (context, index) {
              final entry = history[index];
              return _TableRow(
                history: entry,
                colors: colors,
                onTap: () => onRowTap(entry),
                onDoubleTap: onRowDoubleTap != null
                    ? () => onRowDoubleTap!(entry)
                    : null,
                onDelete: onRowDelete != null
                    ? () => onRowDelete!(entry)
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  final AppLocalizations l10n;
  final ThemeColors colors;

  const _TableHeader({required this.l10n, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        border: Border(bottom: BorderSide(color: colors.borderLight)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      child: Row(
        children: [
          _HeaderCell(
            text: l10n.queryHistoryExecutedAt,
            width: 120,
            colors: colors,
          ),
          Expanded(
            child: _HeaderCell(
              text: l10n.queryHistorySqlPreview,
              colors: colors,
            ),
          ),
          _HeaderCell(
            text: l10n.queryHistoryDuration,
            width: 80,
            colors: colors,
            align: TextAlign.right,
          ),
          _HeaderCell(
            text: l10n.queryHistoryRowCount,
            width: 80,
            colors: colors,
            align: TextAlign.right,
          ),
          _HeaderCell(
            text: l10n.status,
            width: 72,
            colors: colors,
            align: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final double? width;
  final ThemeColors colors;
  final TextAlign align;

  const _HeaderCell({
    required this.text,
    this.width,
    required this.colors,
    this.align = TextAlign.left,
  });

  @override
  Widget build(BuildContext context) {
    final cell = Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: AppDesignSystem.fontSizeXs,
        fontWeight: FontWeight.w600,
        color: colors.textSecondary,
      ),
    );
    if (width != null) {
      return SizedBox(width: width, child: cell);
    }
    return cell;
  }
}

class _TableRow extends StatelessWidget {
  final QueryHistory history;
  final ThemeColors colors;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onDelete;

  const _TableRow({
    required this.history,
    required this.colors,
    required this.onTap,
    this.onDoubleTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isError = history.error != null;

    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTap: onDelete != null ? () => _showContextMenu(context) : null,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colors.borderSubtle,
            ),
          ),
        ),
        child: Row(
          children: [
            _DataCell(
              text: _formatTimestamp(history.timestamp),
              width: 120,
              colors: colors,
            ),
            Expanded(
              child: _DataCell(
                text: _sanitizePreview(history.sql),
                colors: colors,
                truncate: true,
              ),
            ),
            _DataCell(
              text: '${history.executionTime}ms',
              width: 80,
              colors: colors,
              align: TextAlign.right,
            ),
            _DataCell(
              text: '${history.affectedRows}',
              width: 80,
              colors: colors,
              align: TextAlign.right,
            ),
            SizedBox(
              width: 72,
              child: Center(
                child: _StatusBadge(isError: isError, colors: colors),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return DateFormat('MM-dd HH:mm').format(timestamp);
  }

  String _sanitizePreview(String sql) {
    final masked = PIIMasker().maskValue(sql);
    if (masked.length <= _kMaxSqlPreviewLength) return masked;
    return '${masked.substring(0, _kMaxSqlPreviewLength)}...';
  }

  void _showContextMenu(BuildContext context) {
    if (onDelete == null) return;
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final offset = renderBox.localToGlobal(Offset.zero);
    final position = RelativeRect.fromLTRB(
      offset.dx,
      offset.dy,
      offset.dx + renderBox.size.width,
      offset.dy + renderBox.size.height,
    );

    showMenu<void>(
      context: context,
      position: position,
      items: [
        CompactPopupMenuItem<void>(
          onTap: onDelete,
          child: Row(
            children: [
              Icon(LucideIcons.trash2, size: 16, color: colors.accentRed),
              const SizedBox(width: AppDesignSystem.space2),
              Text(
                l10n.queryHistoryDelete,
                style: TextStyle(color: colors.accentRed),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DataCell extends StatelessWidget {
  final String text;
  final double? width;
  final ThemeColors colors;
  final TextAlign align;
  final bool truncate;

  const _DataCell({
    required this.text,
    this.width,
    required this.colors,
    this.align = TextAlign.left,
    this.truncate = false,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = Text(
      text,
      textAlign: align,
      maxLines: truncate ? 1 : null,
      overflow: truncate ? TextOverflow.ellipsis : null,
      style: TextStyle(
        fontSize: AppDesignSystem.fontSizeSm,
        color: colors.textPrimary,
      ),
    );
    if (width != null) {
      return SizedBox(width: width, child: textWidget);
    }
    return textWidget;
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isError;
  final ThemeColors colors;

  const _StatusBadge({required this.isError, required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = isError
        ? (l10n?.queryHistoryStatusError ?? 'Error')
        : (l10n?.queryHistoryStatusSuccess ?? 'Success');
    final badgeColor = isError ? colors.accentRed : colors.accentGreen;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeXs,
          fontWeight: FontWeight.w600,
          color: badgeColor,
        ),
      ),
    );
  }
}
