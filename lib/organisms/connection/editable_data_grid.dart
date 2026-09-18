import 'package:flutter/material.dart';
import '../../theme/design_system.dart';
import '../../theme/app_colors.dart';

class EditableDataGrid extends StatefulWidget {
  final List<GridColumn> columns;
  final List<GridRow> rows;
  final ValueChanged<GridCell>? onCellChanged;
  final double rowHeight;
  final bool showRowNumbers;
  final bool editable;

  const EditableDataGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.onCellChanged,
    this.rowHeight = 40.0,
    this.showRowNumbers = true,
    this.editable = true,
  });

  @override
  State<EditableDataGrid> createState() => _EditableDataGridState();
}

class _EditableDataGridState extends State<EditableDataGrid> {
  late List<GridRow> _rows;
  EditingCell? _editingCell;

  @override
  void initState() {
    super.initState();
    _rows = List.from(widget.rows);
  }

  void _startEditing(int rowIndex, int columnIndex) {
    if (!widget.editable) return;
    setState(() {
      _editingCell = EditingCell(rowIndex, columnIndex);
    });
  }

  void _stopEditing() {
    if (_editingCell == null) return;
    setState(() {
      _editingCell = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildDataRows()),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: widget.rowHeight,
      decoration: BoxDecoration(
        color: AppDesignSystem.bgTertiary,
        border: Border(bottom: BorderSide(color: AppDesignSystem.divider)),
      ),
      child: Row(
        children: [
          if (widget.showRowNumbers) _buildHeaderCell('#', width: 50),
          ...widget.columns.map((col) => _buildHeaderCell(col.name)),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {double? width}) {
    return Container(
      width: width,
      constraints: BoxConstraints(minWidth: width ?? 120, maxWidth: 400),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppDesignSystem.borderLight)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeSm,
          fontWeight: AppDesignSystem.fontWeightSemibold,
          color: AppDesignSystem.textPrimary,
        ),
      ),
    );
  }

  Widget _buildDataRows() {
    return ListView.separated(
      // P0-4：行分隔线降为 50% alpha，与结果网格行线同档统一
      separatorBuilder: (_, _) => Container(
        height: 1,
        color: context.themeColors.borderSubtle,
      ),
      itemCount: _rows.length,
      itemBuilder: (context, rowIndex) {
        return _buildDataRow(rowIndex);
      },
    );
  }

  Widget _buildDataRow(int rowIndex) {
    final row = _rows[rowIndex];
    return Container(
      height: widget.rowHeight,
      decoration: BoxDecoration(
        color: rowIndex % 2 == 0
            ? AppDesignSystem.bgSecondary
            : AppDesignSystem.bgPrimary,
      ),
      child: Row(
        children: [
          if (widget.showRowNumbers) _buildRowNumberCell(rowIndex + 1),
          ...row.cells.asMap().entries.map((entry) {
            final columnIndex = entry.key;
            final cell = entry.value;
            return _buildDataCell(rowIndex, columnIndex, cell);
          }),
        ],
      ),
    );
  }

  Widget _buildRowNumberCell(int number) {
    return Container(
      width: 50,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space3,
        vertical: AppDesignSystem.space2,
      ),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppDesignSystem.borderLight)),
      ),
      child: Text(
        number.toString(),
        style: TextStyle(
          fontSize: AppDesignSystem.fontSizeSm,
          color: AppDesignSystem.textTertiary,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDataCell(int rowIndex, int columnIndex, GridCell cell) {
    final isEditing =
        _editingCell?.rowIndex == rowIndex &&
        _editingCell?.columnIndex == columnIndex;

    return InkWell(
      onDoubleTap: () => _startEditing(rowIndex, columnIndex),
      child: Container(
        constraints: const BoxConstraints(minWidth: 120, maxWidth: 400),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space3,
          vertical: AppDesignSystem.space2,
        ),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: AppDesignSystem.borderLight)),
        ),
        child: isEditing ? _buildEditingCell(cell) : _buildDisplayCell(cell),
      ),
    );
  }

  Widget _buildDisplayCell(GridCell cell) {
    final value = cell.value?.toString() ?? '';
    return Text(
      value.isEmpty && !cell.nullable ? '' : value,
      style: TextStyle(
        fontSize: AppDesignSystem.fontSizeSm,
        color: cell.value == null
            ? AppDesignSystem.textTertiary
            : AppDesignSystem.textPrimary,
        fontFamily: AppDesignSystem.monoFontFamily,

        fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildEditingCell(GridCell cell) {
    return TextField(
      autofocus: true,
      style: TextStyle(
        fontSize: AppDesignSystem.fontSizeSm,
        color: AppDesignSystem.textPrimary,
        fontFamily: AppDesignSystem.monoFontFamily,

        fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDesignSystem.space1,
          vertical: AppDesignSystem.space1,
        ),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: context.themeColors.accentBlue),
        ),
      ),
      onSubmitted: (_) => _stopEditing(),
    );
  }
}

class GridColumn {
  final String id;
  final String name;
  final String type;
  final bool nullable;
  final double? width;

  const GridColumn({
    required this.id,
    required this.name,
    required this.type,
    this.nullable = true,
    this.width,
  });
}

class GridRow {
  final String id;
  final List<GridCell> cells;

  const GridRow({required this.id, required this.cells});
}

class GridCell {
  final String columnId;
  final String columnName;
  final dynamic value;
  final String type;
  final bool nullable;

  const GridCell({
    required this.columnId,
    required this.columnName,
    required this.value,
    required this.type,
    this.nullable = true,
  });

  GridCell copyWith({
    String? columnId,
    String? columnName,
    dynamic value,
    String? type,
    bool? nullable,
  }) {
    return GridCell(
      columnId: columnId ?? this.columnId,
      columnName: columnName ?? this.columnName,
      value: value ?? this.value,
      type: type ?? this.type,
      nullable: nullable ?? this.nullable,
    );
  }
}

class EditingCell {
  final int rowIndex;
  final int columnIndex;

  EditingCell(this.rowIndex, this.columnIndex);
}
