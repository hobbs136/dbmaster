import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// Pagination controls for the result-panel history view.
class ResultHistoryPagination extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const ResultHistoryPagination({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(top: BorderSide(color: context.themeColors.borderLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _PaginationButton(
            icon: LucideIcons.chevronsLeft,
            tooltip: l10n?.paginationFirstPage ?? 'First page',
            onPressed: currentPage > 1 ? () => onPageChanged(1) : null,
          ),
          _PaginationButton(
            icon: LucideIcons.chevronLeft,
            tooltip: l10n?.paginationPreviousPage ?? 'Previous page',
            onPressed: currentPage > 1
                ? () => onPageChanged(currentPage - 1)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
            ),
            child: Text(
              '$currentPage / $totalPages',
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textSecondary,
              ),
            ),
          ),
          _PaginationButton(
            icon: LucideIcons.chevronRight,
            tooltip: l10n?.paginationNextPage ?? 'Next page',
            onPressed: currentPage < totalPages
                ? () => onPageChanged(currentPage + 1)
                : null,
          ),
          _PaginationButton(
            icon: LucideIcons.chevronsRight,
            tooltip: l10n?.paginationLastPage ?? 'Last page',
            onPressed: currentPage < totalPages
                ? () => onPageChanged(totalPages)
                : null,
          ),
        ],
      ),
    );
  }
}

class _PaginationButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _PaginationButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: context.themeColors.textMuted),
        onPressed: onPressed,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      ),
    );
  }
}
