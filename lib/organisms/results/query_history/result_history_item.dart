import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/query_history.dart';
import '../../../services/pii_masker.dart';
import '../../../theme/app_colors.dart';
import '../../../molecules/compact_popup_menu_item.dart';

/// Maximum number of characters shown in the SQL preview before truncating.
const int _kMaxPreviewLength = 120;

/// A single query-history entry in the result panel history list.
///
/// Displays a sanitized SQL preview and a timestamp. Double-tap invokes
/// [onDoubleTap]; right-click reveals a context menu with a Delete action.
class ResultHistoryItem extends StatelessWidget {
  final QueryHistory history;
  final VoidCallback onDoubleTap;
  final VoidCallback? onDelete;

  const ResultHistoryItem({
    super.key,
    required this.history,
    required this.onDoubleTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return GestureDetector(
      onDoubleTap: onDoubleTap,
      onSecondaryTap: () => _showContextMenu(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _sanitizePreview(history.sql),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppDesignSystem.fontSizeSm,
                      color: colors.textPrimary,
                      height: AppDesignSystem.lineHeightTight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              _timestamp,
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeXs,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _timestamp {
    return DateFormat('MM-dd HH:mm').format(history.timestamp);
  }

  String _sanitizePreview(String sql) {
    final masked = PIIMasker().maskValue(sql);
    if (masked.length <= _kMaxPreviewLength) return masked;
    return '${masked.substring(0, _kMaxPreviewLength)}...';
  }

  void _showContextMenu(BuildContext context) {
    if (onDelete == null) return;
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context);

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
                l10n?.queryHistoryDelete ?? 'Delete',
                style: TextStyle(color: colors.accentRed),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
