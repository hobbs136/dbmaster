// HOTFIX: dart:convert needed for jsonEncode of PG jsonb values (auto-parsed to Map/List)
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../models/result_filter.dart';
import '../../models/er_diagram.dart' show ForeignKey;
import '../connection/column_filter_widget.dart';

class CellEditState {
  final String cellKey;
  final int rowIndex;
  final String colName;
  final dynamic originalValue;
  dynamic newValue;
  final TextEditingController controller;
  final FocusNode focusNode;

  CellEditState({
    required this.cellKey,
    required this.rowIndex,
    required this.colName,
    required this.originalValue,
    required this.newValue,
    required this.controller,
    required this.focusNode,
  });

  bool get hasChanged => newValue != originalValue?.toString();
}

class VirtualizedDataTable extends StatefulWidget {
  final List<String> columns;
  final List<Map<String, dynamic>> data;
  final Map<String, ColumnDataType>? columnTypes;
  final Set<String> truncatedColumns; // (max)→capped 截断列
  final double rowHeight;
  // 新增 headerHeight（F-26）——表头/底栏与数据行高解耦，不再共用 40px
  final double headerHeight;
  final double defaultColumnWidth;
  final void Function(int rowIndex, String columnName, dynamic value)?
  onCellEdit;
  final void Function(ColumnFilter)? onFilterChanged;
  final void Function(String columnName)? onFilterCleared;
  final void Function(String columnName)? onSortToggle;
  final Map<String, ColumnFilter>? activeFilters;
  final SortState? sortState;
  final ResultFilterService? filterService;
  final CellEditState? activeCellEdit;
  final void Function(String cellKey, String newValue)? onEditConfirm;
  final void Function(String cellKey)? onEditCancel;
  final Map<String, dynamic>? pendingEdits;
  final bool showRowNumbers;
  final double rowNumberColumnWidth;
  final void Function(
    int rowIndex,
    String columnName,
    dynamic value,
    Offset position,
  )?
  onCellContextMenu;

  /// US4 T052: 列头右键回调（columnName, globalPosition）。
  /// 仅对 JSON 列由调用方弹「Extract field」菜单。
  final void Function(String columnName, Offset globalPosition)?
  onHeaderContextMenu;
  final List<ForeignKey>? foreignKeys;
  final void Function(
    String referencedTable,
    String referencedColumn,
    dynamic value,
  )?
  onForeignKeyTap;

  // Phase B — double-click JSON cell opens tree viewer instead of edit mode
  final void Function(int rowIndex, String columnName, dynamic value)?
  onJsonCellDoubleTap;

  const VirtualizedDataTable({
    super.key,
    required this.columns,
    required this.data,
    this.columnTypes,
    this.truncatedColumns = const <String>{},
    // 行高 40→26（F-26，对齐专业工具 22-28px 密度），表头/底栏 28
    this.rowHeight = 26.0,
    this.headerHeight = 28.0,
    this.defaultColumnWidth = 150.0,
    this.onCellEdit,
    this.onFilterChanged,
    this.onFilterCleared,
    this.onSortToggle,
    this.activeFilters,
    this.sortState,
    this.filterService,
    this.activeCellEdit,
    this.onEditConfirm,
    this.onEditCancel,
    this.pendingEdits,
    this.showRowNumbers = true,
    this.rowNumberColumnWidth = 50.0,
    this.onCellContextMenu,
    this.onHeaderContextMenu,
    this.foreignKeys,
    this.onForeignKeyTap,
    this.onJsonCellDoubleTap,
  });

  @override
  State<VirtualizedDataTable> createState() => _VirtualizedDataTableState();
}

class _VirtualizedDataTableState extends State<VirtualizedDataTable> {
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  late Map<String, double> _columnWidths;
  String? _resizingColumn;
  double _resizingStartX = 0;
  double _resizingStartWidth = 0;

  /// feature 038：hover 改 ValueNotifier + 行级重建，避免整表 setState
  final ValueNotifier<int?> _hoveredRowNotifier = ValueNotifier<int?>(null);

  /// 右键上下文：记录最近被右键的单元格，用于行底色 + 单元格边框高亮。
  /// 持久直到下一次右键（等同 Excel/DBeaver「右键即选中」语义）。
  final ValueNotifier<({int row, String col})?> _contextCellNotifier =
      ValueNotifier<({int row, String col})?>(null);

  /// feature 038：FK 列预计算（initState/didUpdateWidget），cell 构建 O(1) 查表
  Map<String, ForeignKey>? _fkByColumn;

  /// feature 038：cell 显示值惰性缓存（含 JSON 截断结果），仅缓存非编辑态
  final Map<int, Map<String, _CellDisplay>> _displayCache = {};

  static const int _lazyLoadThreshold = 1000;
  bool _isLargeDataset = false;

  @override
  void initState() {
    super.initState();
    _initColumnWidths();
    _checkDatasetSize();
    _computeFkMap();
  }

  void _computeFkMap() {
    final fks = widget.foreignKeys;
    if (fks == null || fks.isEmpty) {
      _fkByColumn = null;
      return;
    }
    _fkByColumn = {for (final fk in fks) fk.column: fk};
  }

  void _initColumnWidths() {
    _columnWidths = Map.fromEntries(
      widget.columns.map((col) => MapEntry(col, widget.defaultColumnWidth)),
    );
  }

  void _checkDatasetSize() {
    _isLargeDataset = widget.data.length > _lazyLoadThreshold;
  }

  @override
  void didUpdateWidget(VirtualizedDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.columns.length != widget.columns.length ||
        !oldWidget.columns.every((col) => widget.columns.contains(col))) {
      _initColumnWidths();
    }
    if (oldWidget.data.length != widget.data.length) {
      _checkDatasetSize();
      // 数据长度变化时重置滚动位置
      if (_verticalController.hasClients) {
        _verticalController.jumpTo(0);
      }
    }
    if (!identical(oldWidget.foreignKeys, widget.foreignKeys)) {
      _computeFkMap();
    }
    // feature 038：显示值缓存失效条件——数据/列/列类型实例变化
    if (!identical(oldWidget.data, widget.data) ||
        !identical(oldWidget.columns, widget.columns) ||
        !identical(oldWidget.columnTypes, widget.columnTypes)) {
      _displayCache.clear();
      // 结果集更换时清掉右键高亮，避免旧行号指向新数据里不相干的行
      _contextCellNotifier.value = null;
    }
  }

  @override
  void dispose() {
    _hoveredRowNotifier.dispose();
    _contextCellNotifier.dispose();
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  double _getColumnWidth(String columnName) {
    return _columnWidths[columnName] ?? widget.defaultColumnWidth;
  }

  void _onColumnResizeStart(String columnName, DragStartDetails details) {
    _resizingColumn = columnName;
    _resizingStartX = details.globalPosition.dx;
    _resizingStartWidth = _getColumnWidth(columnName);
  }

  void _onColumnResizeUpdate(DragUpdateDetails details) {
    if (_resizingColumn == null) return;
    final delta = details.globalPosition.dx - _resizingStartX;
    final newWidth = (_resizingStartWidth + delta).clamp(50.0, 600.0);
    setState(() {
      _columnWidths[_resizingColumn!] = newWidth;
    });
  }

  void _onColumnResizeEnd() {
    _resizingColumn = null;
  }

  /// TC-040: Auto-fit column width to content
  void _autoFitColumn(String columnName) {
    const minWidth = 50.0;
    const maxWidth = 600.0;
    const padding = 24.0; // horizontal padding inside cell

    // Measure header text width
    final headerPainter = TextPainter(
      text: TextSpan(
        text: columnName,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    );
    headerPainter.layout();
    double maxContentWidth = headerPainter.size.width + padding;
    headerPainter.dispose();

    // Measure each cell value width
    // feature 038：采样上限 1000 行，避免大结果集双击列头卡秒级
    final valueStyle = const TextStyle(fontSize: 13, fontFamily: 'monospace');
    for (final row in widget.data.take(1000)) {
      final value = row[columnName];
      if (value == null) continue;
      final text = value.toString();
      if (text.length > 200) continue; // skip very long values

      final painter = TextPainter(
        text: TextSpan(text: text, style: valueStyle),
        textDirection: TextDirection.ltr,
      );
      painter.layout();
      maxContentWidth = math.max(maxContentWidth, painter.size.width + padding);
      painter.dispose();
    }

    final newWidth = maxContentWidth.clamp(minWidth, maxWidth);
    setState(() {
      _columnWidths[columnName] = newWidth;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (widget.columns.isEmpty || widget.data.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          l10n.tableNoData,
          style: TextStyle(color: context.themeColors.textMuted),
        ),
      );
    }

    final totalWidth = _calculateTotalWidth();
    final rowCount = widget.data.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            trackVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: totalWidth,
                child: Column(
                  children: [
                    // Header inside horizontal scroll view
                    _buildHeader(),
                    Expanded(
                      child: Scrollbar(
                        controller: _verticalController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        child: _isLargeDataset
                            ? _buildVirtualizedList(rowCount)
                            : _buildSimpleList(rowCount),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildFooter(rowCount),
      ],
    );
  }

  double _calculateTotalWidth() {
    double total = _columnWidths.values.fold(0.0, (sum, w) => sum + w);
    if (widget.showRowNumbers) {
      total += widget.rowNumberColumnWidth;
    }
    return total;
  }

  Widget _buildSimpleList(int rowCount) {
    return ListView.builder(
      key: ValueKey('simple_list_${widget.data.length}'),
      controller: _verticalController,
      itemCount: rowCount,
      itemExtent: widget.rowHeight,
      cacheExtent: widget.rowHeight * 10,
      itemBuilder: (context, index) {
        final row = widget.data[index];
        return _buildRow(index, key: ValueKey('row_${row.hashCode}'));
      },
    );
  }

  Widget _buildVirtualizedList(int rowCount) {
    return ListView.builder(
      key: ValueKey('virtual_list_${widget.data.length}'),
      controller: _verticalController,
      itemCount: rowCount,
      itemExtent: widget.rowHeight,
      // feature 038：cacheExtent 50→5 行，深跳一帧构建量 ~120→~30 行
      cacheExtent: widget.rowHeight * 5,
      addAutomaticKeepAlives: false,
      findChildIndexCallback: (Key key) {
        if (key is ValueKey) {
          final indexString = key.value.toString().replaceAll('row_', '');
          return int.tryParse(indexString);
        }
        return null;
      },
      itemBuilder: (context, index) {
        return _buildRow(index, key: ValueKey('row_$index'));
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      width: _calculateTotalWidth(),
      height: widget.headerHeight,
      color: context.themeColors.bgTertiary,
      child: Row(
        children: [
          if (widget.showRowNumbers) _buildRowNumberHeader(),
          ...widget.columns.map((col) {
            return _ColumnHeaderWithResizer(
              columnName: col,
              width: _getColumnWidth(col),
              isResizing: _resizingColumn == col,
              filter: widget.activeFilters?[col],
              sortState: widget.sortState?.columnName == col
                  ? widget.sortState
                  : null,
              columnType: widget.columnTypes?[col] ?? ColumnDataType.string,
              onFilterChanged: widget.onFilterChanged ?? (_) {},
              onFilterCleared: () => widget.onFilterCleared?.call(col),
              onSortToggle: () => widget.onSortToggle?.call(col),
              onDoubleTap: () => _autoFitColumn(col),
              onResizeStart: (details) => _onColumnResizeStart(col, details),
              onResizeUpdate: _onColumnResizeUpdate,
              onResizeEnd: _onColumnResizeEnd,
              onContextMenu: widget.onHeaderContextMenu != null
                  ? (columnName, position) =>
                        widget.onHeaderContextMenu!(columnName, position)
                  : null,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRowNumberHeader() {
    return Container(
      width: widget.rowNumberColumnWidth,
      height: widget.headerHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Text(
        '#',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.themeColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildFooter(int rowCount) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: widget.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: context.themeColors.bgTertiary,
        border: Border(top: BorderSide(color: context.themeColors.borderLight)),
      ),
      child: Row(
        children: [
          Text(
            l10n.tableRowCountTotal(rowCount.toString()),
            style: TextStyle(
              fontSize: 11,
              color: context.themeColors.textSecondary,
            ),
          ),
          if (_isLargeDataset) ...[
            const SizedBox(width: AppDesignSystem.space2),
            Text(
              l10n.tableLargeDatasetHint,
              style: TextStyle(
                fontSize: 11,
                color: context.themeColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(int rowIndex, {Key? key}) {
    final row = widget.data[rowIndex];
    final isEven = rowIndex.isEven;
    final baseRowColor = isEven
        ? context.themeColors.bgSecondary
        : context.themeColors.bgPrimary;

    return MouseRegion(
      key: key,
      onEnter: (_) => _hoveredRowNotifier.value = rowIndex,
      onExit: (_) => _hoveredRowNotifier.value = null,
      // 外层监听右键上下文，行级重建（沿用 feature 038 性能路径）
      child: ValueListenableBuilder<({int row, String col})?>(
        valueListenable: _contextCellNotifier,
        builder: (context, contextCell, _) {
          final isContextRow = contextCell?.row == rowIndex;
          return ValueListenableBuilder<int?>(
            valueListenable: _hoveredRowNotifier,
            builder: (context, hoveredRow, _) {
              // 行色优先级：右键行 > hover > 奇偶底色
              final rowColor = isContextRow
                  ? context.themeColors.accentBlue.withValues(alpha: 0.15)
                  : (hoveredRow == rowIndex
                        ? context.themeColors.bgTertiary
                        : baseRowColor);
              return Container(
                height: widget.rowHeight,
                decoration: BoxDecoration(
                  color: rowColor,
                  border: Border(
                    bottom: BorderSide(
                      color: context.themeColors.borderSubtle,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    if (widget.showRowNumbers) _buildRowNumberCell(rowIndex),
                    ...widget.columns.map((colName) {
                      final isContextCell =
                          isContextRow && contextCell?.col == colName;
                      return SizedBox(
                        width: _getColumnWidth(colName),
                        child: _buildCell(
                          rowIndex,
                          colName,
                          row[colName],
                          isContextCell: isContextCell,
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRowNumberCell(int rowIndex) {
    return Container(
      width: widget.rowNumberColumnWidth,
      height: widget.rowHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: context.themeColors.borderLight),
        ),
      ),
      child: Text(
        '${rowIndex + 1}',
        style: TextStyle(
          fontSize: 11,
          color: context.themeColors.textMuted,
          fontFamily: AppDesignSystem.monoFontFamily,

          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        ),
      ),
    );
  }

  ForeignKey? _findForeignKey(String columnName) => _fkByColumn?[columnName];

  /// feature 038：惰性显示值缓存。语义与原 _buildCell 内联计算完全一致：
  /// - null → 'NULL'
  /// - Map/List（PG jsonb 被驱动解析为 Dart 对象）→ jsonEncode 后 80 字符截断
  /// - 字符串内容嗅探 JSON（trim + 首尾括号），确认 JSON 列做 80 字符截断
  _CellDisplay _displayFor(int rowIndex, String columnName, dynamic value) {
    final rowCache = _displayCache[rowIndex];
    final cached = rowCache?[columnName];
    if (cached != null) return cached;

    final rawText = value?.toString() ?? 'NULL';
    final trimmed = rawText.trim();
    final looksLikeJson =
        value != null &&
        trimmed.length >= 2 &&
        ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
            (trimmed.startsWith('[') && trimmed.endsWith(']')));

    var text = rawText;
    final isConfirmedJson =
        widget.columnTypes?[columnName] == ColumnDataType.json;
    if ((isConfirmedJson || looksLikeJson) && value != null) {
      final raw = (value is Map || value is List) ? jsonEncode(value) : rawText;
      text = raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
    }

    final display = _CellDisplay(text: text, looksLikeJson: looksLikeJson);
    // 容量保护：滚动穿超大结果集时防止无界增长
    if (_displayCache.length > 20000) _displayCache.clear();
    (_displayCache[rowIndex] ??= {})[columnName] = display;
    return display;
  }

  Widget _buildCell(
    int rowIndex,
    String columnName,
    dynamic value, {
    bool isContextCell = false,
  }) {
    final cellKey = '${rowIndex}_$columnName';
    final isEditing = widget.activeCellEdit?.cellKey == cellKey;
    final hasPendingEdit = widget.pendingEdits?.containsKey(cellKey) ?? false;

    String displayValue;
    bool looksLikeJson = false;
    if (isEditing) {
      displayValue = widget.activeCellEdit!.newValue?.toString() ?? '';
    } else if (hasPendingEdit) {
      displayValue = widget.pendingEdits![cellKey]?.toString() ?? '';
    } else {
      // feature 038：非编辑态走惰性缓存，避免滚动帧重复 toString/jsonEncode
      final display = _displayFor(rowIndex, columnName, value);
      displayValue = display.text;
      looksLikeJson = display.looksLikeJson;
    }
    final isNull = value == null && !isEditing && !hasPendingEdit;
    // 数值列右对齐（F-27）——等宽字体下便于位宽扫读与量级比较。
    // 元数据经 addPostFrameCallback 异步探测（宽表可能秒级延迟），
    // 首帧先用值类型即时判定，避免"先左后右"的对齐跳变。
    final typeFromMeta = widget.columnTypes?[columnName];
    final isNumeric = typeFromMeta != null
        ? typeFromMeta == ColumnDataType.numeric
        : value is num;
    final textColor = isNull
        ? context.themeColors.textMuted
        : context.themeColors.textPrimary;
    final cursor = widget.onCellEdit != null
        ? SystemMouseCursors.click
        : SystemMouseCursors.basic;

    // 检查是否为外键列（feature 038：O(1) 预计算查表）
    final fk = _findForeignKey(columnName);

    // Phase B — detect JSON columns via metadata + content fallback
    // NOTE: Content-based detection (looksLikeJson) is used for badge only.
    // Double-click opens viewer ONLY for metadata-confirmed JSON to avoid
    // false positives on text columns storing JSON-like strings (HStore, etc.)
    if (isEditing || hasPendingEdit) {
      final trimmed = displayValue.trim();
      looksLikeJson =
          !isNull &&
          trimmed.length >= 2 &&
          ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
              (trimmed.startsWith('[') && trimmed.endsWith(']')));
    }
    final isConfirmedJson =
        widget.columnTypes != null &&
        widget.columnTypes![columnName] == ColumnDataType.json;
    final isJsonCol = isConfirmedJson || looksLikeJson;

    if (isEditing) {
      return _buildEditingCell(cellKey);
    }

    return GestureDetector(
      // Phase B — only metadata-confirmed JSON opens viewer on double-click
      // HOTFIX: content-based detection (looksLikeJson) only enables badge, not viewer
      onDoubleTap: () {
        if (isConfirmedJson && !isNull && widget.onJsonCellDoubleTap != null) {
          widget.onJsonCellDoubleTap!(rowIndex, columnName, value);
        } else if (widget.onCellEdit != null) {
          widget.onCellEdit!(rowIndex, columnName, value);
        }
      },
      onSecondaryTapDown: widget.onCellContextMenu != null
          ? (details) {
              // 记录右键上下文，触发行/单元格高亮
              _contextCellNotifier.value = (row: rowIndex, col: columnName);
              widget.onCellContextMenu!(
                rowIndex,
                columnName,
                value,
                details.globalPosition,
              );
            }
          : null,
      onTap: () {
        if (fk != null && !isNull && widget.onForeignKeyTap != null) {
          widget.onForeignKeyTap!(
            fk.referencedTable,
            fk.referencedColumn,
            value,
          );
        }
      },
      child: MouseRegion(
        cursor: (fk != null && !isNull) ? SystemMouseCursors.click : cursor,
        child: Container(
          // P0-4：单元格右侧 1px 竖线（与既有行线同档 50% alpha）；
          // 右键目标单元格改加 accent 全边框；key 供 widget 测试结构断言
          key: isContextCell ? const ValueKey('results-context-cell') : null,
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space2,
          ),
          decoration: isContextCell
              ? BoxDecoration(
                  border: Border.all(
                    color: context.themeColors.accentBlue,
                    width: 1,
                  ),
                )
              : BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: context.themeColors.borderSubtle,
                    ),
                  ),
                ),
          alignment: isNumeric ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Phase B — {…} badge for JSON columns
              if (isJsonCol && !isNull)
                Padding(
                  padding: const EdgeInsets.only(right: AppDesignSystem.space1),
                  child: Text(
                    '{…}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.themeColors.accentGreen,
                    ),
                  ),
                ),
              // 截断指示：该列是 (max) 被 capped CAST（真长度不可知，LIMIT）
              if (widget.truncatedColumns.contains(columnName))
                Padding(
                  padding: const EdgeInsets.only(right: AppDesignSystem.space1),
                  child: Tooltip(
                    message:
                        AppLocalizations.of(context)?.resultColumnTruncated ??
                        'Value may be truncated',
                    child: Text(
                      '✂',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.themeColors.accentOrange,
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: Text(
                  displayValue,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppDesignSystem.monoFontFamily,

                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    color: (fk != null && !isNull)
                        ? context.themeColors.accentBlue
                        : textColor,
                    fontStyle: isNull ? FontStyle.italic : null,
                    decoration: (fk != null && !isNull)
                        ? TextDecoration.underline
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditingCell(String cellKey) {
    final edit = widget.activeCellEdit!;
    final textStyle = TextStyle(
      fontSize: 13,
      fontFamily: AppDesignSystem.monoFontFamily,

      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
      color: context.themeColors.textPrimary,
    );
    final boxDecoration = BoxDecoration(
      color: context.themeColors.accentBlue.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
    );

    // 根据值类型选择编辑器
    final value = edit.originalValue;
    final strValue = edit.controller.text;

    // 布尔值编辑器
    if (value is bool ||
        strValue.toLowerCase() == 'true' ||
        strValue.toLowerCase() == 'false') {
      return _buildBooleanEditor(edit, cellKey);
    }

    // JSON 编辑器
    if ((strValue.trim().startsWith('{') && strValue.trim().endsWith('}')) ||
        (strValue.trim().startsWith('[') && strValue.trim().endsWith(']'))) {
      return _buildJsonEditor(edit, cellKey, textStyle, boxDecoration);
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space1,
      ),
      decoration: boxDecoration,
      child: TextField(
        controller: edit.controller,
        focusNode: edit.focusNode,
        style: textStyle,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1,
            vertical: AppDesignSystem.space1,
          ),
          border: InputBorder.none,
        ),
        onSubmitted: (value) => widget.onEditConfirm?.call(cellKey, value),
        onChanged: (value) => edit.newValue = value,
      ),
    );
  }

  Widget _buildBooleanEditor(CellEditState edit, String cellKey) {
    bool currentValue = edit.controller.text.toLowerCase() == 'true';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space1,
      ),
      decoration: BoxDecoration(
        color: context.themeColors.accentBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: currentValue,
            onChanged: (value) {
              edit.controller.text = value.toString();
              edit.newValue = value.toString();
              widget.onEditConfirm?.call(cellKey, value.toString());
            },
          ),
          Text(currentValue ? 'TRUE' : 'FALSE'),
        ],
      ),
    );
  }

  Widget _buildJsonEditor(
    CellEditState edit,
    String cellKey,
    TextStyle textStyle,
    BoxDecoration boxDecoration,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDesignSystem.space1_5,
        vertical: AppDesignSystem.space1,
      ),
      decoration: boxDecoration,
      child: TextField(
        controller: edit.controller,
        focusNode: edit.focusNode,
        style: textStyle,
        maxLines: 5,
        minLines: 1,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppDesignSystem.space1,
            vertical: AppDesignSystem.space1,
          ),
          border: InputBorder.none,
          hintText: AppLocalizations.of(context)!.sidebarJsonHint,
        ),
        onSubmitted: (value) => widget.onEditConfirm?.call(cellKey, value),
        onChanged: (value) => edit.newValue = value,
      ),
    );
  }
}

class _ColumnHeaderWithResizer extends StatelessWidget {
  final String columnName;
  final double width;
  final bool isResizing;
  final ColumnFilter? filter;
  final SortState? sortState;
  final ColumnDataType columnType;
  final ValueChanged<ColumnFilter> onFilterChanged;
  final VoidCallback onFilterCleared;
  final VoidCallback onSortToggle;
  final GestureDragStartCallback onResizeStart;
  final GestureDragUpdateCallback onResizeUpdate;
  final VoidCallback onResizeEnd;
  final VoidCallback? onDoubleTap;

  /// US4 T052: 列头右键回调（透传到 ColumnHeaderWidget）
  final void Function(String columnName, Offset globalPosition)? onContextMenu;

  const _ColumnHeaderWithResizer({
    required this.columnName,
    required this.width,
    required this.isResizing,
    required this.filter,
    required this.sortState,
    required this.columnType,
    required this.onFilterChanged,
    required this.onFilterCleared,
    required this.onSortToggle,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
    this.onDoubleTap,
    this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    // P0-4：列头右侧 1px 竖线，与数据单元格竖线同档同位（列右缘对齐）
    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: context.themeColors.borderSubtle,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ColumnHeaderWidget(
              columnName: columnName,
              filter: filter,
              sortState: sortState,
              columnType: columnType,
              onFilterChanged: onFilterChanged,
              onFilterCleared: onFilterCleared,
              onSortToggle: onSortToggle,
              onDoubleTap: onDoubleTap,
              onContextMenu: onContextMenu,
            ),
          ),
          _ColumnResizeHandle(
            isResizing: isResizing,
            onResizeStart: onResizeStart,
            onResizeUpdate: onResizeUpdate,
            onResizeEnd: onResizeEnd,
          ),
        ],
      ),
    );
  }
}

class _ColumnResizeHandle extends StatelessWidget {
  final bool isResizing;
  final GestureDragStartCallback onResizeStart;
  final GestureDragUpdateCallback onResizeUpdate;
  final VoidCallback onResizeEnd;

  const _ColumnResizeHandle({
    required this.isResizing,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: onResizeStart,
        onHorizontalDragUpdate: onResizeUpdate,
        onHorizontalDragEnd: (_) => onResizeEnd(),
        child: Container(
          width: 8,
          color: isResizing
              ? context.themeColors.accentBlue.withValues(alpha: 0.3)
              : Colors.transparent,
          child: Center(
            child: Container(
              width: 1,
              height: 20,
              decoration: BoxDecoration(
                color: isResizing
                    ? context.themeColors.accentBlue
                    : context.themeColors.borderLight,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PaginatedDataTable extends StatefulWidget {
  final List<String> columns;
  final List<Map<String, dynamic>> data;
  final int pageSize;
  final Map<String, ColumnDataType>? columnTypes;
  final void Function(int rowIndex, String columnName, dynamic value)?
  onCellEdit;
  final void Function(ColumnFilter)? onFilterChanged;
  final void Function(String columnName)? onFilterCleared;
  final void Function(String columnName)? onSortToggle;
  final Map<String, ColumnFilter>? activeFilters;
  final SortState? sortState;
  final ResultFilterService? filterService;

  const PaginatedDataTable({
    super.key,
    required this.columns,
    required this.data,
    this.pageSize = 100,
    this.columnTypes,
    this.onCellEdit,
    this.onFilterChanged,
    this.onFilterCleared,
    this.onSortToggle,
    this.activeFilters,
    this.sortState,
    this.filterService,
  });

  @override
  State<PaginatedDataTable> createState() => _PaginatedDataTableState();
}

class _PaginatedDataTableState extends State<PaginatedDataTable> {
  int _currentPage = 0;
  late int _totalPages;

  @override
  void initState() {
    super.initState();
    _totalPages = (widget.data.length / widget.pageSize).ceil().clamp(
      1,
      999999,
    );
  }

  @override
  void didUpdateWidget(PaginatedDataTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _totalPages = (widget.data.length / widget.pageSize).ceil().clamp(
        1,
        999999,
      );
      if (_currentPage >= _totalPages) {
        _currentPage = _totalPages - 1;
      }
    }
  }

  List<Map<String, dynamic>> get _currentPageData {
    if (widget.data.isEmpty) return const [];
    final start = _currentPage * widget.pageSize;
    final end = (start + widget.pageSize).clamp(0, widget.data.length);
    return widget.data.sublist(start, end);
  }

  int get _startRow =>
      widget.data.isEmpty ? 0 : _currentPage * widget.pageSize + 1;
  int get _endRow {
    if (widget.data.isEmpty) return 0;
    return ((_currentPage + 1) * widget.pageSize).clamp(0, widget.data.length);
  }

  int get _totalRows => widget.data.length;

  void _goToPage(int page) {
    setState(() {
      _currentPage = page.clamp(0, _totalPages - 1);
    });
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      setState(() => _currentPage++);
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      setState(() => _currentPage--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: VirtualizedDataTable(
            key: ValueKey('$_currentPage-$_totalPages'),
            columns: widget.columns,
            data: _currentPageData,
            columnTypes: widget.columnTypes,
            onCellEdit: widget.onCellEdit,
            onFilterChanged: widget.onFilterChanged,
            onFilterCleared: widget.onFilterCleared,
            onSortToggle: widget.onSortToggle,
            activeFilters: widget.activeFilters,
            sortState: widget.sortState,
            filterService: widget.filterService,
          ),
        ),
        _buildPaginationBar(),
      ],
    );
  }

  Widget _buildPaginationBar() {
    final l10n = AppLocalizations.of(context)!;
    final textSecondary = context.themeColors.textSecondary;
    final textMuted = context.themeColors.textMuted;
    final textPrimary = context.themeColors.textPrimary;
    final bgTertiary = context.themeColors.bgTertiary;
    final borderLight = context.themeColors.borderLight;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppDesignSystem.space3),
      decoration: BoxDecoration(
        color: bgTertiary,
        border: Border(top: BorderSide(color: borderLight)),
      ),
      child: Row(
        children: [
          Text(
            l10n.tableRowRange(
              _startRow.toString(),
              _endRow.toString(),
              _totalRows.toString(),
            ),
            style: TextStyle(fontSize: 12, color: textMuted),
          ),
          const Spacer(),
          _buildPageButton(
            icon: LucideIcons.chevronsLeft,
            color: textSecondary,
            onPressed: _currentPage > 0 ? () => _goToPage(0) : null,
          ),
          _buildPageButton(
            icon: LucideIcons.chevronLeft,
            color: textSecondary,
            onPressed: _currentPage > 0 ? _previousPage : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignSystem.space3,
            ),
            child: Text(
              '${_currentPage + 1} / $_totalPages',
              style: TextStyle(fontSize: 12, color: textPrimary),
            ),
          ),
          _buildPageButton(
            icon: LucideIcons.chevronRight,
            color: textSecondary,
            onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
          ),
          _buildPageButton(
            icon: LucideIcons.chevronsRight,
            color: textSecondary,
            onPressed: _currentPage < _totalPages - 1
                ? () => _goToPage(_totalPages - 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildPageButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 18, color: color),
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

/// feature 038：cell 显示值缓存记录（惰性预计算，仅非编辑态使用）
class _CellDisplay {
  const _CellDisplay({required this.text, required this.looksLikeJson});

  /// 最终显示文本（含 NULL 占位与 JSON 80 字符截断）
  final String text;

  /// 内容嗅探是否为 JSON（badge 显示依据）
  final bool looksLikeJson;
}
