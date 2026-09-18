// spec 041 US3: FilterBar 顶部筛选条 widget。
//
// 仅对 SQL 系 6 种显示（由 EditorResultsSplit 的 supportsFilterBar 门控）。
// per-tab 实例（Region-1 IndexedStack 内），各 tab 自持控制器。
// 布局：纵向多条件行 + 滚动（条件多时向下扩展）。
// 值输入类型感知：date/time/timestamp 列提供日期选择器（其余文本输入）。
//   - boolean/bit/enum 值需 per-db 编码（PG TRUE/FALSE、SQLServer 1/0、enum 需查值），
//     暂留文本输入，作后续小特性。
// Apply → buildFilteredSelect → AppProvider.executeCurrentQueryAndRecord（复用全部守卫/行限/历史/PII）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../models/filter_condition.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/filter_query_builder.dart';

class FilterBarStrip extends StatefulWidget {
  final String tabId;

  const FilterBarStrip({super.key, required this.tabId});

  @override
  State<FilterBarStrip> createState() => _FilterBarStripState();
}

class _FilterBarStripState extends State<FilterBarStrip> {
  final List<_FilterRow> _rows = [];
  FilterCombinator _combinator = FilterCombinator.and;
  List<DbColumn> _columns = const [];
  bool _loading = true;
  bool _columnsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsLoaded) {
      _columnsLoaded = true; // 防止 didChangeDependencies 重复触发
      _loadColumns();
    }
  }

  Future<void> _loadColumns() async {
    final provider = context.read<AppProvider>();
    try {
      final cols = await provider.getTableColumnsForBrowse(widget.tabId);
      if (!mounted) return;
      setState(() {
        _columns = cols;
        _loading = false;
        if (_rows.isEmpty && _columns.isNotEmpty) {
          _rows.add(
            _FilterRow(field: _columns.first.name, op: FilterOperator.eq),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      AppLogger.e('FilterBarStrip', '加载字段失败', e);
      setState(() => _loading = false);
    }
  }

  DbColumn? _columnFor(String field) {
    for (final c in _columns) {
      if (c.name == field) return c;
    }
    return null;
  }

  void _addRow() {
    setState(() {
      _rows.add(
        _FilterRow(
          field: _columns.isNotEmpty ? _columns.first.name : '',
          op: FilterOperator.eq,
        ),
      );
    });
  }

  void _removeRow(int index) {
    setState(() {
      _rows[index].valueController.dispose();
      _rows.removeAt(index);
    });
  }

  /// date/time 列弹出日期选择器，写入 'YYYY-MM-DD'（跨库 date 列均接受引号日期串）。
  Future<void> _pickDate(_FilterRow row) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      final m = picked.month.toString().padLeft(2, '0');
      final d = picked.day.toString().padLeft(2, '0');
      row.valueController.text = '${picked.year}-$m-$d';
    }
  }

  Future<void> _apply() async {
    final provider = context.read<AppProvider>();
    final target = provider.browseTargetFor(widget.tabId);
    final matching = provider.tabs.where((t) => t.id == widget.tabId).toList();
    if (matching.isEmpty || target == null) return;
    final dbType = matching.first.databaseType;
    if (dbType == null) return;

    final conditions = _rows.map((r) {
      final col = _columnFor(r.field);
      final isBoolean = col != null && _kindFor(col.type) == _ValueKind.boolean;
      return FilterCondition(
        field: r.field,
        op: r.op,
        value: r.valueController.text,
        kind: isBoolean ? FilterValueKind.boolean : FilterValueKind.string,
      );
    }).toList();
    // 同步到 provider（per-tab 模型，供未来持久化/复用）
    provider.setFilterConditions(widget.tabId, conditions);
    provider.setFilterCombinator(widget.tabId, _combinator);

    final sql = buildFilteredSelect(
      qualifiedTable: target,
      conditions: conditions,
      combinator: _combinator,
      dbType: dbType,
    );
    if (sql.isEmpty) return;
    try {
      await provider.executeCurrentQueryAndRecord(overrideSql: sql);
    } catch (e) {
      // executeCurrentQueryAndRecord 已把错误写入结果子标签；此处仅防未处理 rethrow。
      AppLogger.d('FilterBarStrip', 'Apply 执行失败（已记录到结果子标签）: $e');
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.valueController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_loading) {
      return _stripContainer(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.filterBarLoading,
              style: TextStyle(
                fontSize: 12,
                color: context.themeColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    if (_columns.isEmpty) {
      return _stripContainer(
        child: Text(
          l10n.filterBarNoColumns,
          style: TextStyle(fontSize: 12, color: context.themeColors.textMuted),
        ),
      );
    }
    // 纵向布局：顶部控制条 + 下方条件列表（自适应高度，3 行后滚动）
    return _stripContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildControlsRow(l10n),
          const SizedBox(height: 2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 140), // ~3 行后滚动
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < _rows.length; i++) ...[
                    if (i > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          _combinator == FilterCombinator.and
                              ? l10n.filterBarAnd
                              : l10n.filterBarOr,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: context.themeColors.textMuted,
                          ),
                        ),
                      ),
                    _buildConditionRow(i),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsRow(AppLocalizations l10n) {
    return Row(
      children: [
        _combinatorChip(l10n),
        const Spacer(),
        IconButton(
          icon: const Icon(LucideIcons.circlePlus, size: 18),
          tooltip: l10n.filterBarAddCondition,
          onPressed: _addRow,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed: () => unawaited(_apply()),
          icon: const Icon(LucideIcons.play, size: 16),
          label: Text(l10n.filterBarApply),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 30),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _combinatorChip(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => setState(
          () => _combinator = _combinator == FilterCombinator.and
              ? FilterCombinator.or
              : FilterCombinator.and,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: context.themeColors.bgTertiary,
            borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
          ),
          child: Text(
            _combinator == FilterCombinator.and
                ? l10n.filterBarAnd
                : l10n.filterBarOr,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildConditionRow(int index) {
    final row = _rows[index];
    final col = _columnFor(row.field);
    final fieldValue = _columns.any((c) => c.name == row.field)
        ? row.field
        : (_columns.isNotEmpty ? _columns.first.name : null);
    final noValue =
        row.op == FilterOperator.isNull || row.op == FilterOperator.isNotNull;
    return Row(
      children: [
        DropdownButton<String>(
          value: fieldValue,
          items: _columns
              .map(
                (c) => DropdownMenuItem(
                  value: c.name,
                  child: Text(
                    '${c.name}  (${c.type})',
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() {
            row.field = v ?? row.field;
            row.valueController.clear(); // 切字段时清空值（列类型可能变）
          }),
          underline: const SizedBox(),
          isDense: true,
        ),
        const SizedBox(width: 6),
        DropdownButton<FilterOperator>(
          value: row.op,
          items: FilterOperator.values
              .map(
                (o) => DropdownMenuItem(
                  value: o,
                  child: Text(
                    _opLabel(o),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => row.op = v ?? row.op),
          underline: const SizedBox(),
          isDense: true,
        ),
        const SizedBox(width: 6),
        if (noValue)
          const Spacer()
        else
          Expanded(child: _buildValueInput(row, col)),
        IconButton(
          icon: Icon(
            LucideIcons.circleMinus,
            size: 16,
            color: context.themeColors.textMuted,
          ),
          onPressed: _rows.length > 1 ? () => _removeRow(index) : null,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  /// 类型感知的值输入：boolean/enum/date/text 分别渲染对应控件。
  Widget _buildValueInput(_FilterRow row, DbColumn? col) {
    final kind = col == null ? _ValueKind.text : _kindFor(col.type);
    switch (kind) {
      case _ValueKind.boolean:
        return _buildBooleanInput(row);
      case _ValueKind.mysqlEnum:
        return _buildEnumInput(
          row,
          col == null ? null : _parseEnumValues(col.type),
        );
      case _ValueKind.date:
        return _buildDateInput(row, isDateTime: false);
      case _ValueKind.dateTime:
        return _buildDateInput(row, isDateTime: true);
      case _ValueKind.text:
        return _buildTextInput(row);
    }
  }

  /// boolean/bit → true/false 下拉（值经 buildFilteredSelect 按 dbType 编码裸值）。
  Widget _buildBooleanInput(_FilterRow row) {
    final v = ['true', 'false'].contains(row.valueController.text)
        ? row.valueController.text
        : 'true';
    return DropdownButton<String>(
      value: v,
      items: const [
        DropdownMenuItem(
          value: 'true',
          child: Text('true', style: TextStyle(fontSize: 12)),
        ),
        DropdownMenuItem(
          value: 'false',
          child: Text('false', style: TextStyle(fontSize: 12)),
        ),
      ],
      onChanged: (val) =>
          setState(() => row.valueController.text = val ?? 'true'),
      underline: const SizedBox(),
      isDense: true,
    );
  }

  /// MySQL enum → 可选值下拉（值作字符串，escapeString 加引号）。
  /// 解析失败（PG enum 无值）→ 退化为文本输入。
  Widget _buildEnumInput(_FilterRow row, List<String>? values) {
    if (values == null || values.isEmpty) return _buildTextInput(row);
    final current = values.contains(row.valueController.text)
        ? row.valueController.text
        : values.first;
    return DropdownButton<String>(
      value: current,
      items: values
          .map(
            (val) => DropdownMenuItem(
              value: val,
              child: Text(
                val,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (val) =>
          setState(() => row.valueController.text = val ?? values.first),
      underline: const SizedBox(),
      isDense: true,
    );
  }

  Widget _buildDateInput(_FilterRow row, {required bool isDateTime}) {
    return TextField(
      controller: row.valueController,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        hintText: isDateTime ? 'YYYY-MM-DD HH:MM' : 'YYYY-MM-DD',
        hintStyle: const TextStyle(fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            isDateTime ? LucideIcons.calendar : LucideIcons.calendar,
            size: 14,
          ),
          onPressed: () => isDateTime ? _pickDateTime(row) : _pickDate(row),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          tooltip: isDateTime ? 'Date & time' : 'Date',
        ),
      ),
    );
  }

  /// datetime/timestamp/time 列：先选日期再选时间，写入 'YYYY-MM-DD HH:MM:00'。
  Future<void> _pickDateTime(_FilterRow row) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t == null || !mounted) return;
    final dy =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final tm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
    row.valueController.text = '$dy $tm';
  }

  Widget _buildTextInput(_FilterRow row) {
    return TextField(
      controller: row.valueController,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        ),
      ),
    );
  }

  Widget _stripContainer({required Widget child}) {
    // 不设固定高：随内容自适应（条件少则矮、多则到 ~3 行后内部滚动）
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.themeColors.bgSecondary,
        border: Border(
          bottom: BorderSide(
            color: context.themeColors.borderSubtle,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// 值输入类型（决定控件形态）。
enum _ValueKind { text, date, dateTime, boolean, mysqlEnum }

/// 按列类型推断值输入形态。
/// - enum(...) → MySQL enum 下拉（从类型解析可选值）。
/// - boolean/bool/bit/tinyint(1) → true/false 下拉（值按 dbType 编码裸值）。
/// - datetime/timestamp/time → 日期+时间选择器。
/// - date → 仅日期选择器。
/// - 其余 → 文本。
_ValueKind _kindFor(String type) {
  final t = type.toLowerCase();
  if (t.contains('enum(')) return _ValueKind.mysqlEnum;
  if (t.contains('bool') || t == 'bit' || t.contains('tinyint(1)')) {
    return _ValueKind.boolean;
  }
  if (t.contains('datetime') || t.contains('timestamp') || t.contains('time')) {
    return _ValueKind.dateTime;
  }
  if (t.contains('date')) {
    return _ValueKind.date;
  }
  return _ValueKind.text;
}

/// 解析 MySQL `enum('a','b','c')` 类型为可选值列表。
/// PG enum 仅类型名（无值）→ 返回 null（退化为文本输入）。
List<String>? _parseEnumValues(String type) {
  final m = RegExp(r"enum\((.*)\)", caseSensitive: false).firstMatch(type);
  if (m == null) return null;
  final inner = m.group(1)!.trim();
  if (inner.isEmpty) return const [];
  return inner.split(',').map((raw) {
    var v = raw.trim();
    if (v.length >= 2 &&
        ((v.startsWith("'") && v.endsWith("'")) ||
            (v.startsWith('"') && v.endsWith('"')))) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }).toList();
}

/// 操作符下拉的符号标签（通用符号，无需 l10n）。
String _opLabel(FilterOperator op) {
  switch (op) {
    case FilterOperator.eq:
      return '=';
    case FilterOperator.ne:
      return '≠';
    case FilterOperator.gt:
      return '>';
    case FilterOperator.gte:
      return '≥';
    case FilterOperator.lt:
      return '<';
    case FilterOperator.lte:
      return '≤';
    case FilterOperator.like:
      return 'LIKE';
    case FilterOperator.notLike:
      return 'NOT LIKE';
    case FilterOperator.isNull:
      return 'IS NULL';
    case FilterOperator.isNotNull:
      return 'IS NOT NULL';
  }
}

class _FilterRow {
  String field;
  FilterOperator op;
  final TextEditingController valueController;

  _FilterRow({
    required this.field,
    required this.op,
    TextEditingController? valueController,
  }) : valueController = valueController ?? TextEditingController();
}
