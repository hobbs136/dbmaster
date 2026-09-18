import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../models/result_search.dart';

class SearchBarWidget extends StatefulWidget {
  final ResultSearchService searchService;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final int resultCount;
  final int currentIndex;

  const SearchBarWidget({
    super.key,
    required this.searchService,
    required this.onSearch,
    required this.onClear,
    required this.resultCount,
    required this.currentIndex,
  });

  @override
  State<SearchBarWidget> createState() => _SearchBarWidgetState();
}

class _SearchBarWidgetState extends State<SearchBarWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchService.searchText);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSearch() {
    widget.searchService.setSearchText(_controller.text);
    widget.onSearch();
  }

  void _handleClear() {
    _controller.clear();
    widget.searchService.clear();
    widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.search,
            size: 16,
            color: context.themeColors.textSecondary,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: l10n.searchPlaceholder,
                hintStyle: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.textMuted,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: AppDesignSystem.space2,
                ),
                border: InputBorder.none,
                filled: false,
              ),
              onSubmitted: (_) => _handleSearch(),
              onChanged: (value) {
                if (value.isEmpty) {
                  _handleClear();
                }
              },
            ),
          ),
          const SizedBox(width: AppDesignSystem.space2),
          _buildToolButton(
            icon: LucideIcons.code,
            tooltip: l10n.filterRegex,
            isActive: widget.searchService.useRegex,
            onPressed: () {
              setState(() {
                widget.searchService.toggleRegex();
              });
              if (_controller.text.isNotEmpty) {
                _handleSearch();
              }
            },
          ),
          const SizedBox(width: AppDesignSystem.space1),
          _buildToolButton(
            icon: LucideIcons.type,
            tooltip: AppLocalizations.of(context)!.sidebarCaseSensitive,
            isActive: widget.searchService.caseSensitive,
            onPressed: () {
              setState(() {
                widget.searchService.toggleCaseSensitive();
              });
              if (_controller.text.isNotEmpty) {
                _handleSearch();
              }
            },
          ),
          const SizedBox(width: AppDesignSystem.space2),
          if (widget.resultCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              decoration: BoxDecoration(
                color: context.themeColors.accentBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              ),
              child: Text(
                '${widget.currentIndex + 1} / ${widget.resultCount}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.accentBlue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: AppDesignSystem.space2),
            _buildNavButton(
              icon: LucideIcons.chevronUp,
              tooltip: l10n.paginationPreviousPage,
              onPressed: widget.resultCount > 0
                  ? () {
                      widget.searchService.previousResult();
                      widget.onSearch();
                    }
                  : null,
            ),
            const SizedBox(width: AppDesignSystem.space1),
            _buildNavButton(
              icon: LucideIcons.chevronDown,
              tooltip: l10n.paginationNextPage,
              onPressed: widget.resultCount > 0
                  ? () {
                      widget.searchService.nextResult();
                      widget.onSearch();
                    }
                  : null,
            ),
          ] else if (_controller.text.isNotEmpty) ...[
            Text(
              l10n.searchNoResults,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ],
          const SizedBox(width: AppDesignSystem.space2),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 16),
            onPressed: _handleClear,
            tooltip: l10n.resultsClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            color: context.themeColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isActive
                ? context.themeColors.accentBlue.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive
                ? context.themeColors.accentBlue
                : context.themeColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      color: onPressed != null
          ? context.themeColors.textPrimary
          : context.themeColors.textMuted,
    );
  }
}
