import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../models/result_filter.dart';
import '../../l10n/app_localizations.dart';
import '../../molecules/compact_popup_menu_item.dart';

class ColumnFilterPopup extends StatefulWidget {
  final String columnName;
  final ColumnFilter? initialFilter;
  final ColumnDataType columnType;
  final void Function(ColumnFilter) onApply;
  final VoidCallback onClear;

  const ColumnFilterPopup({
    super.key,
    required this.columnName,
    this.initialFilter,
    this.columnType = ColumnDataType.string,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<ColumnFilterPopup> createState() => _ColumnFilterPopupState();
}

class _ColumnFilterPopupState extends State<ColumnFilterPopup> {
  late FilterOperator _selectedOperator;
  late TextEditingController _valueController;
  late TextEditingController _valueEndController;
  late bool _isEnabled;

  @override
  void initState() {
    super.initState();
    _selectedOperator = widget.initialFilter?.operator ?? _getDefaultOperator();
    _valueController = TextEditingController(
      text: widget.initialFilter?.value ?? '',
    );
    _valueEndController = TextEditingController(
      text: widget.initialFilter?.valueEnd ?? '',
    );
    _isEnabled = widget.initialFilter?.isEnabled ?? true;
  }

  FilterOperator _getDefaultOperator() {
    switch (widget.columnType) {
      case ColumnDataType.numeric:
      case ColumnDataType.dateTime:
        return FilterOperator.equals;
      case ColumnDataType.string:
      case ColumnDataType.json:
        return FilterOperator.contains;
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _valueEndController.dispose();
    super.dispose();
  }

  List<FilterOperator> get _availableOperators {
    switch (widget.columnType) {
      case ColumnDataType.numeric:
        return FilterOperatorExtension.numericOperators;
      case ColumnDataType.dateTime:
        return FilterOperatorExtension.dateTimeOperators;
      case ColumnDataType.string:
      case ColumnDataType.json:
        return FilterOperatorExtension.stringOperators;
    }
  }

  String _typeLabel(AppLocalizations l10n) {
    switch (widget.columnType) {
      case ColumnDataType.numeric:
        return l10n.columnFilterTypeNumeric;
      case ColumnDataType.dateTime:
        return l10n.columnFilterTypeDateTime;
      case ColumnDataType.string:
      case ColumnDataType.json:
        return l10n.columnFilterTypeText;
    }
  }

  IconData get _typeIcon {
    switch (widget.columnType) {
      case ColumnDataType.numeric:
        return LucideIcons.pin;
      case ColumnDataType.dateTime:
        return LucideIcons.clock;
      case ColumnDataType.string:
      case ColumnDataType.json:
        return LucideIcons.type;
    }
  }

  Color get _typeColor {
    switch (widget.columnType) {
      case ColumnDataType.numeric:
        return Colors.blue;
      case ColumnDataType.dateTime:
        return Colors.orange;
      case ColumnDataType.string:
      case ColumnDataType.json:
        return Colors.green;
    }
  }

  void _handleApply() {
    final filter = ColumnFilter(
      columnName: widget.columnName,
      operator: _selectedOperator,
      value: _valueController.text,
      valueEnd: _valueEndController.text,
      isEnabled: _isEnabled,
    );
    widget.onApply(filter);
    Navigator.of(context).pop();
  }

  void _handleClear() {
    widget.onClear();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: context.themeColors.bgPrimary,
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.themeColors.bgPrimary,
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
          border: Border.all(color: context.themeColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilterHeader(context, l10n),
            const SizedBox(height: AppDesignSystem.space3),
            _buildEnableCheckbox(context),
            const SizedBox(height: AppDesignSystem.space2),
            _buildOperatorDropdown(context, l10n),
            if (_selectedOperator.requiresValue) ...[
              const SizedBox(height: AppDesignSystem.space2),
              _buildValueInputs(context, l10n),
            ],
            const SizedBox(height: AppDesignSystem.space3),
            _buildActionButtons(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterHeader(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        Icon(
          LucideIcons.listFilter,
          size: 16,
          color: context.themeColors.accentBlue,
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          child: Text(
            l10n.columnFilterFor(widget.columnName),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.themeColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1_5,
            vertical: AppDesignSystem.space0_5,
          ),
          decoration: BoxDecoration(
            color: _typeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_typeIcon, size: 12, color: _typeColor),
              const SizedBox(width: AppDesignSystem.space1),
              Text(
                _typeLabel(l10n),
                style: TextStyle(fontSize: 11, color: _typeColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnableCheckbox(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: _isEnabled,
          onChanged: (v) => setState(() => _isEnabled = v ?? true),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(
          AppLocalizations.of(context)!.filterEnable,
          style: TextStyle(
            fontSize: 12,
            color: context.themeColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildOperatorDropdown(BuildContext context, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: context.themeColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<FilterOperator>(
          value: _selectedOperator,
          isExpanded: true,
          items: _availableOperators.map((op) {
            return DropdownMenuItem(
              value: op,
              child: Text(
                _operatorLabel(l10n, op),
                style: TextStyle(
                  fontSize: 12,
                  color: context.themeColors.textPrimary,
                ),
              ),
            );
          }).toList(),
          onChanged: (op) {
            if (op != null) setState(() => _selectedOperator = op);
          },
        ),
      ),
    );
  }

  Widget _buildValueInputs(BuildContext context, AppLocalizations l10n) {
    if (_selectedOperator.requiresTwoValues) {
      return Column(
        children: [
          Row(
            children: [
              Text(
                l10n.filterFrom,
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: _buildValueField(_valueController, l10n.filterFrom),
              ),
            ],
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Row(
            children: [
              Text(
                l10n.filterTo,
                style: TextStyle(
                  fontSize: 11,
                  color: context.themeColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              Expanded(
                child: _buildValueField(_valueEndController, l10n.filterTo),
              ),
            ],
          ),
        ],
      );
    }
    return _buildValueField(_valueController, _getPlaceholder(l10n));
  }

  Widget _buildActionButtons(BuildContext context, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: TextButton(
            onPressed: _handleClear,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                vertical: AppDesignSystem.space2,
              ),
            ),
            child: Text(
              AppLocalizations.of(context)!.filterClear,
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        Expanded(
          child: ElevatedButton(
            onPressed: _handleApply,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.themeColors.accentBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                vertical: AppDesignSystem.space2,
              ),
            ),
            child: Text(l10n.connApply, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildValueField(
    TextEditingController controller,
    String placeholder,
  ) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 12, color: context.themeColors.textPrimary),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: TextStyle(
          fontSize: 12,
          color: context.themeColors.textMuted,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space2,
          vertical: AppDesignSystem.space2_5,
        ),
        filled: true,
        fillColor: context.themeColors.bgSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide(color: context.themeColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide(color: context.themeColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          borderSide: BorderSide(color: context.themeColors.accentBlue),
        ),
      ),
      inputFormatters: widget.columnType == ColumnDataType.numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
          : null,
      onSubmitted: (_) => _handleApply(),
    );
  }

  String _getPlaceholder(AppLocalizations l10n) {
    switch (widget.columnType) {
      case ColumnDataType.numeric:
        return l10n.columnFilterPlaceholderNumeric;
      case ColumnDataType.dateTime:
        return l10n.columnFilterPlaceholderDateTime;
      case ColumnDataType.string:
      case ColumnDataType.json:
        return l10n.columnFilterPlaceholderText;
    }
  }

  String _operatorLabel(AppLocalizations l10n, FilterOperator op) {
    switch (op) {
      case FilterOperator.equals:
        return l10n.filterOpEquals;
      case FilterOperator.notEquals:
        return l10n.filterOpNotEquals;
      case FilterOperator.contains:
        return l10n.filterOpContains;
      case FilterOperator.notContains:
        return l10n.filterOpNotContains;
      case FilterOperator.startsWith:
        return l10n.filterOpStartsWith;
      case FilterOperator.endsWith:
        return l10n.filterOpEndsWith;
      case FilterOperator.greaterThan:
        return l10n.filterOpGreaterThan;
      case FilterOperator.greaterThanOrEqual:
        return l10n.filterOpGreaterThanOrEqual;
      case FilterOperator.lessThan:
        return l10n.filterOpLessThan;
      case FilterOperator.lessThanOrEqual:
        return l10n.filterOpLessThanOrEqual;
      case FilterOperator.between:
        return l10n.filterOpBetween;
      case FilterOperator.isNull:
        return l10n.filterOpIsNull;
      case FilterOperator.isNotNull:
        return l10n.filterOpIsNotNull;
      case FilterOperator.isEmpty:
        return l10n.filterOpIsEmpty;
      case FilterOperator.isNotEmpty:
        return l10n.filterOpIsNotEmpty;
    }
  }
}

class ColumnHeaderWidget extends StatelessWidget {
  final String columnName;
  final ColumnFilter? filter;
  final SortState? sortState;
  final ColumnDataType columnType;
  final void Function(ColumnFilter) onFilterChanged;
  final VoidCallback onFilterCleared;
  final VoidCallback onSortToggle;
  final VoidCallback? onDoubleTap;

  /// US4 T052: 列头右键回调（columnName, globalPosition）。null 时不响应右键。
  final void Function(String columnName, Offset globalPosition)? onContextMenu;

  const ColumnHeaderWidget({
    super.key,
    required this.columnName,
    this.filter,
    this.sortState,
    this.columnType = ColumnDataType.string,
    required this.onFilterChanged,
    required this.onFilterCleared,
    required this.onSortToggle,
    this.onDoubleTap,
    this.onContextMenu,
  });

  void _showFilterPopup(BuildContext context, Offset position) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        CompactPopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: ColumnFilterPopup(
            columnName: columnName,
            initialFilter: filter,
            columnType: columnType,
            onApply: onFilterChanged,
            onClear: onFilterCleared,
          ),
        ),
      ],
      elevation: 0,
      color: Colors.transparent,
      shadowColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter =
        filter != null &&
        filter!.isEnabled &&
        (filter!.value.isNotEmpty || !filter!.operator.requiresValue);
    final hasSort = sortState != null;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onSortToggle,
        onDoubleTap: onDoubleTap,
        onSecondaryTapDown: onContextMenu != null
            ? (details) => onContextMenu!(columnName, details.globalPosition)
            : null,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
          ),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            border: Border(
              bottom: BorderSide(color: context.themeColors.borderLight),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (hasSort) ...[
                      Icon(
                        sortState!.ascending
                            ? LucideIcons.arrowUp
                            : LucideIcons.arrowDown,
                        size: 14,
                        color: context.themeColors.accentBlue,
                      ),
                      const SizedBox(width: AppDesignSystem.space1),
                    ],
                    Expanded(
                      child: Text(
                        columnName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: hasSort
                              ? context.themeColors.accentBlue
                              : context.themeColors.textSecondary,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // T040: JSON 列头 badge —— declared（jsonb/json）显示实心 {…}。
                    // 注：ColumnDataType 层 declared 与 detected 均归为 json，
                    // 差异化（detected 虚线）需扩枚举，超出本次范围，留后续。
                    if (columnType == ColumnDataType.json) ...[
                      const SizedBox(width: AppDesignSystem.space1),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: context.themeColors.accentPurple.withValues(
                            alpha: 0.15,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppDesignSystem.radiusSm,
                          ),
                        ),
                        child: Text(
                          '{…}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: context.themeColors.accentPurple,
                            fontFamily: AppDesignSystem.monoFontFamily,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1),
              GestureDetector(
                onTapDown: (details) {
                  _showFilterPopup(context, details.globalPosition);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: hasActiveFilter
                          ? context.themeColors.accentBlue.withValues(
                              alpha: 0.2,
                            )
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        AppDesignSystem.radiusSm,
                      ),
                    ),
                    child: Icon(
                      hasActiveFilter
                          ? LucideIcons.listFilter
                          : LucideIcons.listFilter,
                      size: 14,
                      color: hasActiveFilter
                          ? context.themeColors.accentBlue
                          : context.themeColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SortState {
  final String columnName;
  final bool ascending;

  const SortState({required this.columnName, required this.ascending});

  SortState copyWith({String? columnName, bool? ascending}) {
    return SortState(
      columnName: columnName ?? this.columnName,
      ascending: ascending ?? this.ascending,
    );
  }
}

class FilterStatusBar extends StatelessWidget {
  final int activeFilterCount;
  final int filteredCount;
  final int totalCount;
  final VoidCallback onClearAll;

  const FilterStatusBar({
    super.key,
    required this.activeFilterCount,
    required this.filteredCount,
    required this.totalCount,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (activeFilterCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.accentPurple.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: context.themeColors.accentPurple),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.listFilter,
            size: 14,
            color: context.themeColors.accentPurple,
          ),
          const SizedBox(width: AppDesignSystem.space2),
          Text(
            l10n.columnFilterActive(activeFilterCount),
            style: TextStyle(
              fontSize: 12,
              color: context.themeColors.accentPurple,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space2,
              vertical: AppDesignSystem.space0_5,
            ),
            decoration: BoxDecoration(
              color: context.themeColors.accentGreen.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: Text(
              l10n.columnFilterRowCount(
                filteredCount.toString(),
                totalCount.toString(),
              ),
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.accentGreen,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: AppDesignSystem.space3),
          TextButton.icon(
            onPressed: onClearAll,
            icon: const Icon(LucideIcons.eraser, size: 14),
            label: Text(l10n.connClearAll),
            style: TextButton.styleFrom(
              foregroundColor: context.themeColors.accentPurple,
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesignSystem.space2,
                vertical: AppDesignSystem.space1,
              ),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    );
  }
}
