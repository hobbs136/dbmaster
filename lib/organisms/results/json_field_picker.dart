import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../models/database_models.dart';
import '../../theme/app_theme.dart';

/// US4: JSON 字段提取对话框（R: json_field_picker）。
///
/// 采样结果集前 N 行的 JSON 列，提取键的并集，以树展示。用户选一个叶子节点
/// → 生成数据库特定的提取 SQL（PG/MySQL/SQLite），确认后打开新 Tab。
///
/// 「字段不在所有采样行」时标琥珀色警告（T057）。
class JsonFieldPicker extends StatefulWidget {
  /// 该 JSON 列的采样值（原始字符串或已解析对象）
  final List<dynamic> sampleValues;

  /// 列名（生成 SQL 用）
  final String columnName;

  /// 数据库类型（决定 SQL 语法）
  final DatabaseType databaseType;

  /// 源查询的 FROM 表名（生成 SQL 用，未知则 null 用占位符）
  final String? sourceTable;

  /// 源查询的所有列名（FR-018: 保留原列 + 提取字段）
  final List<String> originalColumns;

  const JsonFieldPicker({
    super.key,
    required this.sampleValues,
    required this.columnName,
    required this.databaseType,
    this.sourceTable,
    required this.originalColumns,
  });

  /// 便捷调用：弹出选择器，返回生成的 SQL（null 表示取消）。
  static Future<String?> show(
    BuildContext context, {
    required List<dynamic> sampleValues,
    required String columnName,
    required DatabaseType databaseType,
    String? sourceTable,
    required List<String> originalColumns,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => JsonFieldPicker(
        sampleValues: sampleValues,
        columnName: columnName,
        databaseType: databaseType,
        sourceTable: sourceTable,
        originalColumns: originalColumns,
      ),
    );
  }

  @override
  State<JsonFieldPicker> createState() => _JsonFieldPickerState();
}

class _JsonFieldPickerState extends State<JsonFieldPicker> {
  _FieldNode? _root;
  String? _errorMessage;
  _FieldNode? _selected;

  @override
  void initState() {
    super.initState();
    _buildTree();
  }

  /// 采样前 N 行 JSON，合并键的并集成树（T051）。
  void _buildTree() {
    try {
      final samples = <dynamic>[];
      for (final v in widget.sampleValues.take(50)) {
        if (v == null) continue;
        if (v is String) {
          final trimmed = v.trim();
          if (trimmed.isEmpty) continue;
          samples.add(jsonDecode(trimmed));
        } else if (v is Map || v is List) {
          samples.add(v);
        }
      }
      if (samples.isEmpty) {
        _errorMessage = 'no_data';
        return;
      }
      _root = _mergeSamples(samples);
    } catch (e) {
      _errorMessage = 'invalid_json';
    }
  }

  /// 合并多个 JSON 样本为一棵并集树。
  /// 每个节点记录 totalCount/samplesSeen，用于「不在所有行」判定。
  _FieldNode _mergeSamples(List<dynamic> samples) {
    final root = _FieldNode(key: null, path: '', depth: 0);
    root.totalCount = samples.length;
    for (final sample in samples) {
      _mergeInto(root, sample, samples.length);
    }
    return root;
  }

  void _mergeInto(_FieldNode parent, dynamic node, int totalSamples) {
    if (node is Map) {
      for (final entry in node.entries) {
        final keyStr = entry.key.toString();
        var child = parent.children[keyStr];
        if (child == null) {
          child = _FieldNode(
            key: keyStr,
            path: parent.path.isEmpty ? keyStr : '${parent.path}.$keyStr',
            depth: parent.depth + 1,
          );
          parent.children[keyStr] = child;
        }
        child.samplesSeen++;
        child.totalCount = totalSamples;
        _mergeInto(child, entry.value, totalSamples);
      }
    } else if (node is List && node.isNotEmpty) {
      // 数组：合并所有元素的键（用 [0] 作 path 占位，但合并全部元素）
      final arrChild = parent.children['[0]'] ??= _FieldNode(
        key: '[0]',
        path: parent.path.isEmpty ? '[0]' : '${parent.path}[0]',
        depth: parent.depth + 1,
      );
      arrChild.samplesSeen++;
      arrChild.totalCount = totalSamples;
      for (final elem in node.take(5)) {
        // 取前 5 个元素合并（避免超大数组）
        _mergeInto(arrChild, elem, totalSamples);
      }
    }
    // 叶子值不递归
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.themeColors;
    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: [
          Icon(LucideIcons.network, color: colors.accentBlue, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n?.extractFieldAsColumn ?? 'Extract field as column',
              style: TextStyle(color: colors.textPrimary, fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 400,
        child: _buildContent(colors, l10n),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(
            l10n?.commonCancel ?? 'Cancel',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _generateSql(_selected!)),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accentBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: colors.accentBlue.withValues(alpha: 0.3),
          ),
          child: Text(l10n?.ddlExecuteButton ?? 'Generate'),
        ),
      ],
    );
  }

  Widget _buildContent(dynamic colors, AppLocalizations? l10n) {
    if (_errorMessage == 'no_data') {
      return _buildInfoState(
        colors,
        LucideIcons.inbox,
        l10n?.noJsonDataToSample ?? 'No data to sample',
        'The result set has no JSON values in this column',
      );
    }
    if (_errorMessage == 'invalid_json') {
      return _buildInfoState(
        colors,
        LucideIcons.circleAlert,
        'Invalid JSON',
        'Sampled values could not be parsed as JSON',
      );
    }
    if (_root == null || _root!.children.isEmpty) {
      return _buildInfoState(
        colors,
        LucideIcons.info,
        l10n?.noLeafNodes ?? 'No extractable fields',
        'No leaf nodes found in JSON structure',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.columnName} · ${_dbLabel()}',
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: _buildNodeTree(_root!, colors, l10n),
          ),
        ),
        if (_selected != null) _buildSelectionBar(colors, l10n),
      ],
    );
  }

  Widget _buildInfoState(
    dynamic colors,
    IconData icon,
    String title,
    String desc,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(color: colors.textPrimary, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 递归渲染节点树（缩进 + 可选「不在所有行」警告 + 点击选择叶子）。
  Widget _buildNodeTree(
    _FieldNode node,
    dynamic colors,
    AppLocalizations? l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: node.children.entries.map((e) {
        final child = e.value;
        return _buildNodeTile(child, colors, l10n);
      }).toList(),
    );
  }

  Widget _buildNodeTile(
    _FieldNode node,
    dynamic colors,
    AppLocalizations? l10n,
  ) {
    final isLeaf = node.children.isEmpty;
    final isSelected = _selected?.path == node.path;
    final notInAll = node.samplesSeen > 0 && node.samplesSeen < node.totalCount;
    final indent = 16.0 * node.depth;

    return InkWell(
      onTap: isLeaf ? () => setState(() => _selected = node) : null,
      child: Container(
        padding: EdgeInsets.fromLTRB(indent + 8, 4, 8, 4),
        color: isSelected
            ? colors.accentBlue.withValues(alpha: 0.15)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              isLeaf ? LucideIcons.circle : LucideIcons.folder,
              size: isLeaf ? 6 : 14,
              color: isLeaf
                  ? (isSelected ? colors.accentBlue : colors.textMuted)
                  : colors.accentOrange,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                node.key ?? '',
                style: TextStyle(
                  fontSize: 12,
                  color: isLeaf ? colors.textPrimary : colors.textSecondary,
                  fontWeight: isLeaf ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
            ),
            // T057: 不在所有行的字段标琥珀色警告
            if (notInAll) ...[
              Icon(LucideIcons.triangleAlert, size: 12, color: colors.warning),
              const SizedBox(width: 2),
              Text(
                '${node.samplesSeen}/${node.totalCount}',
                style: TextStyle(fontSize: 10, color: colors.warning),
              ),
            ],
            if (isSelected)
              Icon(LucideIcons.check, size: 14, color: colors.accentBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar(dynamic colors, AppLocalizations? l10n) {
    final notInAll =
        _selected!.samplesSeen > 0 &&
        _selected!.samplesSeen < _selected!.totalCount;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.bgTertiary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.borderLight),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleCheckBig, size: 14, color: colors.accentBlue),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${widget.columnName} → ${_selected!.path}',
              style: TextStyle(fontSize: 11, color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (notInAll)
            Text(
              l10n?.fieldNotInAllRows ?? 'not in all rows',
              style: TextStyle(fontSize: 10, color: colors.warning),
            ),
        ],
      ),
    );
  }

  String _dbLabel() {
    switch (widget.databaseType) {
      case DatabaseType.postgresql:
        return 'PostgreSQL';
      case DatabaseType.mysql:
        return 'MySQL';
      case DatabaseType.sqlite:
        return 'SQLite';
      default:
        return widget.databaseType.name;
    }
  }

  /// T053-T055: 生成数据库特定的提取 SQL（FR-017/018）。
  String _generateSql(_FieldNode node) {
    return JsonExtractionSql.generate(
      columnName: widget.columnName,
      fieldPath: node.path,
      databaseType: widget.databaseType,
      sourceTable: widget.sourceTable,
      originalColumns: widget.originalColumns,
    );
  }
}

/// JSON 字段提取 SQL 生成器（T053-T055，纯函数可单测）。
class JsonExtractionSql {
  /// 生成提取 SQL。
  ///
  /// [fieldPath] 点号路径如 "user.address.city" 或含数组 "[0].name"。
  /// PG: `col->'user'->'address'->>'city'`（末层用 ->> 取文本）
  /// MySQL: `JSON_EXTRACT(col, '$.user.address.city')`
  /// SQLite: `json_extract(col, '$.user.address.city')`
  /// 保留所有原列 + 提取字段（FR-018）。
  static String generate({
    required String columnName,
    required String fieldPath,
    required DatabaseType databaseType,
    String? sourceTable,
    required List<String> originalColumns,
  }) {
    final table = (sourceTable?.trim().isNotEmpty ?? false)
        ? sourceTable!
        : '<target_table>';

    // 构建原列列表（quote 列名避免关键字冲突）
    final cols = originalColumns.map(_quoteIdentifier).join(', ');
    final extractionExpr = _buildExtraction(
      columnName,
      fieldPath,
      databaseType,
    );
    final fieldAlias = _pathToAlias(fieldPath);

    return 'SELECT $cols, $extractionExpr AS "$fieldAlias"\nFROM $table;';
  }

  /// 按数据库类型构建提取表达式。
  static String _buildExtraction(
    String column,
    String path,
    DatabaseType dbType,
  ) {
    switch (dbType) {
      case DatabaseType.postgresql:
        return _pgExtraction(column, path);
      case DatabaseType.mysql:
        return "JSON_EXTRACT(${_quotedCol(column)}, '\$.$path')";
      case DatabaseType.sqlite:
        return "json_extract(${_quotedCol(column)}, '\$.$path')";
      default:
        // 兜底用 SQL 标准风格（MySQL 兼容）
        return "JSON_EXTRACT(${_quotedCol(column)}, '\$.$path')";
    }
  }

  /// PG 提取：拆分路径为段，对象键用 ->，末段用 ->> 取文本。
  /// 数组下标 [n] 用整数 ->n / ->>n（PG jsonb 数组用整数下标）。
  static String _pgExtraction(String column, String path) {
    final segments = _parsePath(path);
    if (segments.isEmpty) return _quotedCol(column);

    final buffer = StringBuffer(_quotedCol(column));
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final isLast = i == segments.length - 1;
      if (seg.isArray) {
        // PG 数组：整数下标 ->n（jsonb）/ ->>n（text）
        buffer.write(isLast ? "->>${seg.arrayIndex}" : "->${seg.arrayIndex}");
      } else {
        // 对象键：末层用 ->> 取 text，否则 -> 取 jsonb
        buffer.write(isLast ? "->>'${seg.key}'" : "->'${seg.key}'");
      }
    }
    return buffer.toString();
  }

  /// 解析路径为段（支持 user.address.city 和 data[0].name）。
  static List<_PathSegment> _parsePath(String path) {
    final segments = <_PathSegment>[];
    // 先按 . 拆，再处理每段里的 [n]
    final parts = path.split('.');
    for (final part in parts) {
      final arrayMatch = RegExp(r'^(\w+)\[(\d+)\]$').firstMatch(part);
      if (arrayMatch != null) {
        segments.add(_PathSegment(arrayMatch.group(1)!));
        segments.add(
          _PathSegment('', isArray: true, arrayIndex: arrayMatch.group(2)!),
        );
      } else {
        final idxMatch = RegExp(r'^\[(\d+)\]$').firstMatch(part);
        if (idxMatch != null) {
          segments.add(
            _PathSegment('', isArray: true, arrayIndex: idxMatch.group(1)!),
          );
        } else if (part.isNotEmpty) {
          segments.add(_PathSegment(part));
        }
      }
    }
    return segments;
  }

  /// 路径 → 别名（user.address.city → city；data[0].name → name）。
  static String _pathToAlias(String path) {
    final segments = _parsePath(path);
    final lastKey = segments.lastWhere(
      (s) => !s.isArray && s.key.isNotEmpty,
      orElse: () => _PathSegment('field'),
    );
    return lastKey.key;
  }

  static String _quotedCol(String name) => _quoteIdentifier(name);

  /// 列名加双引号（PG 风格，其它库容忍）。
  static String _quoteIdentifier(String name) {
    if (name.contains('"')) return name; // 已引用
    return '"$name"';
  }
}

/// 路径段（对象键 or 数组下标）。
class _PathSegment {
  final String key;
  final bool isArray;
  final String arrayIndex;
  const _PathSegment(this.key, {this.isArray = false, this.arrayIndex = ''});
}

/// 字段树节点（采样并集）。
class _FieldNode {
  final String? key;
  final String path;
  final int depth;
  final Map<String, _FieldNode> children = {};
  int samplesSeen = 0; // 该字段出现在多少行
  int totalCount = 0; // 总采样行数

  _FieldNode({this.key, required this.path, required this.depth});
}
