import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../services/sql_autocomplete_service.dart';
import '../../utils/app_logger.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

class SQLAutocomplete extends StatelessWidget {
  final List<Suggestion> suggestions;
  final int selectedIndex;
  final Function(Suggestion) onSelected;
  final Function(int index) onSelectionChanged;
  final Function() onDismiss;
  final Offset cursorPosition;
  final String title; // 020-mongo — 可复用于 Mongo 补全弹窗 (US1)

  const SQLAutocomplete({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelected,
    required this.onSelectionChanged,
    required this.onDismiss,
    required this.cursorPosition,
    this.title = 'SQL Autocomplete',
  });

  Color _getTypeColor(BuildContext context, SuggestionType type) {
    switch (type) {
      case SuggestionType.keyword:
        return context.themeColors.accentPurple;
      case SuggestionType.table:
        return context.themeColors.info;
      case SuggestionType.column:
        return context.themeColors.accentBlue;
      case SuggestionType.function:
        return context.themeColors.warning;
      case SuggestionType.datatype:
        return context.themeColors.error;
      case SuggestionType.operator:
        return context.themeColors.warning;
      // 020-mongo — Mongo 补全类型配色 (US1/US2)
      case SuggestionType.collection:
        return context.themeColors.info;
      case SuggestionType.field:
        return context.themeColors.accentBlue;
      case SuggestionType.method:
        return context.themeColors.accentPurple;
    }
  }

  String _getTypeLabel(SuggestionType type) {
    switch (type) {
      case SuggestionType.keyword:
        return 'KEYWORD';
      case SuggestionType.table:
        return 'TABLE';
      case SuggestionType.column:
        return 'COLUMN';
      case SuggestionType.function:
        return 'FUNCTION';
      case SuggestionType.datatype:
        return 'TYPE';
      case SuggestionType.operator:
        return 'OPERATOR';
      // 020-mongo — Mongo 补全类型标签 (US1/US2)
      case SuggestionType.collection:
        return 'COLLECTION';
      case SuggestionType.field:
        return 'FIELD';
      case SuggestionType.method:
        return 'METHOD';
    }
  }

  IconData _getTypeIcon(SuggestionType type) {
    switch (type) {
      case SuggestionType.keyword:
        return LucideIcons.code;
      case SuggestionType.table:
        return LucideIcons.table2;
      case SuggestionType.column:
        return LucideIcons.columns2;
      case SuggestionType.function:
        return LucideIcons.functionSquare;
      case SuggestionType.datatype:
        return LucideIcons.braces;
      case SuggestionType.operator:
        return LucideIcons.calculator;
      // 020-mongo — Mongo 补全类型图标 (US1/US2)
      case SuggestionType.collection:
        return LucideIcons.database;
      case SuggestionType.field:
        return LucideIcons.clipboardList;
      case SuggestionType.method:
        return LucideIcons.terminal;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onDismiss,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            left: cursorPosition.dx,
            top: cursorPosition.dy + 20,
            child: Material(
              color: context.themeColors.bgSecondary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
              elevation: 8,
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 320,
                  maxWidth: 400,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: context.themeColors.borderColor),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildHeader(context),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        itemBuilder: (context, index) {
                          return _buildSuggestionItem(context, index);
                        },
                      ),
                    ),
                    _buildFooter(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(
          bottom: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.sparkles,
            size: 14,
            color: context.themeColors.accentBlue,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            title, // 020-mongo — 复用弹窗，标题由调用方传入 (US1)
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: context.themeColors.textPrimary,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space1_5,
              vertical: AppDesignSystem.space0_5,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.bgHover,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              '${suggestions.length} items',
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionItem(BuildContext context, int index) {
    final suggestion = suggestions[index];
    final isSelected = index == selectedIndex;

    return MouseRegion(
      onEnter: (_) => onSelectionChanged(index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AppLogger.d(
            'SqlAutocomplete',
            '🖱️ [SQLAutocomplete] Item tapped: ${suggestion.text}',
          );
          onSelected(suggestion);
        },
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space3,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? context.themeColors.bgActive
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: context.themeColors.borderLight,
                width: index == suggestions.length - 1 ? 0 : 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                alignment: Alignment.centerLeft,
                child: Icon(
                  _getTypeIcon(suggestion.type),
                  size: 14,
                  color: _getTypeColor(context, suggestion.type),
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: Text(
                  suggestion.text,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    color: isSelected
                        ? context.themeColors.textPrimary
                        : _getTypeColor(context, suggestion.type),
                    fontWeight: isSelected
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ),
              if (suggestion.detail != null) ...[
                const SizedBox(width: AppDesignSystem.space2),
                Text(
                  suggestion.detail!,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.themeColors.textMuted,
                  ),
                ),
              ],
              const SizedBox(width: AppDesignSystem.space2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDesignSystem.space1,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: _getTypeColor(
                    context,
                    suggestion.type,
                  ).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
                ),
                child: Text(
                  _getTypeLabel(suggestion.type),
                  style: TextStyle(
                    fontSize: 11,
                    color: _getTypeColor(context, suggestion.type),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(top: BorderSide(color: context.themeColors.borderLight)),
      ),
      child: Row(
        children: [
          _buildShortcutHint(context, '↑↓', l10n?.commonNavigate ?? 'Navigate'),
          const SizedBox(width: AppDesignSystem.space1_5),
          _buildShortcutHint(context, 'Enter', l10n?.commonSelect ?? 'Select'),
          const SizedBox(width: AppDesignSystem.space1_5),
          _buildShortcutHint(context, 'Esc', l10n?.commonClose ?? 'Close'),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildShortcutHint(BuildContext context, String key, String label) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1,
            vertical: 1,
          ),
          decoration: BoxDecoration(
            color: context.themeColors.bgHover,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            border: Border.all(color: context.themeColors.borderLight),
          ),
          child: Text(
            key,
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
              fontFamily: AppDesignSystem.monoFontFamily,

              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space1),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.themeColors.textMuted),
        ),
      ],
    );
  }
}
