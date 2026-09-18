import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';

/// Header for the result-panel history view.
///
/// Contains the search field and the clear-all action.
class ResultHistoryHeader extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onClearAll;

  const ResultHistoryHeader({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    this.onClearAll,
  });

  @override
  State<ResultHistoryHeader> createState() => _ResultHistoryHeaderState();
}

class _ResultHistoryHeaderState extends State<ResultHistoryHeader> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant ResultHistoryHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery &&
        _controller.text != widget.searchQuery) {
      _controller.text = widget.searchQuery;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: l10n?.queryHistorySearchHint ?? 'Search history',
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(
                  fontSize: AppDesignSystem.fontSizeSm,
                  color: colors.textMuted,
                ),
              ),
              style: TextStyle(
                fontSize: AppDesignSystem.fontSizeSm,
                color: colors.textPrimary,
              ),
              onChanged: widget.onSearchChanged,
            ),
          ),
          if (widget.onClearAll != null)
            IconButton(
              icon: Icon(
                LucideIcons.brushCleaning,
                size: 18,
                color: colors.textMuted,
              ),
              tooltip: l10n?.queryHistoryClearAll ?? 'Clear all history',
              onPressed: widget.onClearAll,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}
