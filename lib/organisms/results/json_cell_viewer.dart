import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Tree-based JSON viewer dialog with syntax highlighting,
/// expand/collapse, search, and virtual scrolling.
class JsonCellViewer extends StatefulWidget {
  final String jsonString;
  final String columnName;

  const JsonCellViewer({
    super.key,
    required this.jsonString,
    required this.columnName,
  });

  @override
  State<JsonCellViewer> createState() => _JsonCellViewerState();
}

class _JsonRow {
  final int depth;
  final String? key;
  final dynamic value;
  final bool isExpandable;
  final String path;
  final bool isExpanded;

  const _JsonRow({
    required this.depth,
    this.key,
    this.value,
    required this.isExpandable,
    required this.path,
    this.isExpanded = false,
  });

  _JsonRow copyWith({bool? isExpanded}) {
    return _JsonRow(
      depth: depth,
      key: key,
      value: value,
      isExpandable: isExpandable,
      path: path,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }
}

class _JsonCellViewerState extends State<JsonCellViewer> {
  List<_JsonRow> _flattened = [];
  String _searchQuery = '';
  // T044: 记录哪些超长字符串值已展开看全文（按 _flattened 索引）。
  final Set<int> _expandedLongValues = {};
  bool _parseError = false;
  String _parseErrorMessage = '';
  static const _maxDepth = 50;
  static const _maxStringLength = 10000;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  void _parse() {
    try {
      final parsed = jsonDecode(widget.jsonString);
      _parseError = false;
      _flattened = _flatten(parsed, 0, '\$');
    } catch (e) {
      _parseError = true;
      _parseErrorMessage = e.toString();
    }
  }

  List<_JsonRow> _flatten(dynamic node, int depth, String path) {
    if (depth > _maxDepth) {
      return [
        _JsonRow(
          depth: depth,
          key: null,
          value: '<max depth reached>',
          isExpandable: false,
          path: path,
        ),
      ];
    }

    if (node is Map) {
      final rows = <_JsonRow>[
        _JsonRow(
          depth: depth,
          key: null,
          value: null,
          isExpandable: true,
          path: path,
          isExpanded: depth < 3,
        ),
      ];
      for (final entry in node.entries) {
        final childPath = '$path.${entry.key}';
        final child = entry.value;
        if (child is Map || child is List) {
          rows.add(
            _JsonRow(
              depth: depth + 1,
              key: entry.key.toString(),
              value: null,
              isExpandable: true,
              path: childPath,
              isExpanded: depth < 2,
            ),
          );
        } else {
          rows.add(
            _JsonRow(
              depth: depth + 1,
              key: entry.key.toString(),
              value: child,
              isExpandable: false,
              path: childPath,
            ),
          );
        }
      }
      return rows;
    }

    if (node is List) {
      final rows = <_JsonRow>[
        _JsonRow(
          depth: depth,
          key: null,
          value: null,
          isExpandable: true,
          path: path,
          isExpanded: depth < 3,
        ),
      ];
      for (int i = 0; i < node.length; i++) {
        final childPath = '$path[$i]';
        final child = node[i];
        if (child is Map || child is List) {
          rows.add(
            _JsonRow(
              depth: depth + 1,
              key: '[$i]',
              value: null,
              isExpandable: true,
              path: childPath,
              isExpanded: depth < 2,
            ),
          );
        } else {
          rows.add(
            _JsonRow(
              depth: depth + 1,
              key: '[$i]',
              value: child,
              isExpandable: false,
              path: childPath,
            ),
          );
        }
      }
      return rows;
    }

    return [
      _JsonRow(
        depth: depth,
        key: null,
        value: node,
        isExpandable: false,
        path: path,
      ),
    ];
  }

  void _toggle(int index) {
    final row = _flattened[index];
    if (!row.isExpandable) return;
    final newExpanded = !row.isExpanded;

    // Find the original node and rebuild
    try {
      final parsed = jsonDecode(widget.jsonString);
      final target = _resolve(parsed, row.path);
      if (target == null) return;

      setState(() {
        _flattened = _rebuild(parsed, row.path, newExpanded);
      });
    } catch (_) {}
  }

  dynamic _resolve(dynamic node, String path) {
    final parts = path
        .split('.')
        .where((p) => p.isNotEmpty && p != '\$')
        .toList();
    if (parts.isEmpty) return node;

    dynamic current = node;
    for (final part in parts) {
      final match = RegExp(r'^(.+)\[(\d+)\]$').firstMatch(part);
      if (match != null) {
        final key = match.group(1)!;
        final idx = int.parse(match.group(2)!);
        if (current is Map) {
          current = current[key];
        }
        if (current is List && idx < current.length) {
          current = current[idx];
        } else {
          return null;
        }
      } else if (current is Map) {
        current = current[part];
      } else if (current is List) {
        final idx = int.tryParse(part);
        if (idx != null && idx < current.length) {
          current = current[idx];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return current;
  }

  List<_JsonRow> _rebuild(dynamic node, String targetPath, bool expanded) {
    final rows = <_JsonRow>[];

    void recurse(dynamic n, int depth, String path, Set<String> expandPaths) {
      if (depth > _maxDepth) {
        rows.add(
          _JsonRow(
            depth: depth,
            key: null,
            value: '<max depth reached>',
            isExpandable: false,
            path: path,
          ),
        );
        return;
      }

      final shouldExpand =
          expandPaths.contains(path) || expanded && path == targetPath;

      if (n is Map) {
        rows.add(
          _JsonRow(
            depth: depth,
            key: null,
            value: null,
            isExpandable: true,
            path: path,
            isExpanded: shouldExpand,
          ),
        );
        if (shouldExpand) {
          for (final entry in n.entries) {
            final childPath = '$path.${entry.key}';
            final child = entry.value;
            if (child is Map || child is List) {
              recurse(child, depth + 1, childPath, expandPaths);
            } else {
              rows.add(
                _JsonRow(
                  depth: depth + 1,
                  key: entry.key.toString(),
                  value: child,
                  isExpandable: false,
                  path: childPath,
                ),
              );
            }
          }
        }
      } else if (n is List) {
        rows.add(
          _JsonRow(
            depth: depth,
            key: null,
            value: null,
            isExpandable: true,
            path: path,
            isExpanded: shouldExpand,
          ),
        );
        if (shouldExpand) {
          for (int i = 0; i < n.length; i++) {
            final childPath = '$path[$i]';
            final child = n[i];
            if (child is Map || child is List) {
              recurse(child, depth + 1, childPath, expandPaths);
            } else {
              rows.add(
                _JsonRow(
                  depth: depth + 1,
                  key: '[$i]',
                  value: child,
                  isExpandable: false,
                  path: childPath,
                ),
              );
            }
          }
        }
      } else {
        rows.add(
          _JsonRow(
            depth: depth,
            key: null,
            value: n,
            isExpandable: false,
            path: path,
          ),
        );
      }
    }

    final Set<String> toExpand = {};
    // Expand ancestors of targetPath
    final parts = targetPath.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      var current = parts[0];
      toExpand.add(current);
      for (int i = 1; i < parts.length; i++) {
        current = '$current.${parts[i]}';
        toExpand.add(current);
      }
    }
    toExpand.add(targetPath); // ensure target is expanded

    recurse(node, 0, '\$', toExpand);
    return rows;
  }

  List<_JsonRow> _getDisplayRows() {
    if (_searchQuery.isEmpty) return _flattened;
    return _flattened.where((r) {
      return r.path.toLowerCase().contains(_searchQuery) ||
          (r.key?.toLowerCase().contains(_searchQuery) ?? false) ||
          (r.value?.toString().toLowerCase().contains(_searchQuery) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          const Icon(LucideIcons.network, size: 18),
          const SizedBox(width: AppDesignSystem.space1),
          Flexible(
            child: Text(
              widget.columnName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 460,
        child: _parseError ? _buildError(colors) : _buildTree(colors),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n?.commonClose ?? 'Close'),
        ),
      ],
    );
  }

  Widget _buildError(dynamic colors) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.imageOff,
            size: 40,
            color: context.themeColors.error,
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Text(
            l10n?.jsonInvalidJson ?? 'Invalid JSON',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppDesignSystem.space1),
          Text(
            _parseErrorMessage,
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
          const SizedBox(height: AppDesignSystem.space2),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(AppDesignSystem.space2),
            decoration: BoxDecoration(
              color: colors.bgTertiary,
              borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
            ),
            child: SingleChildScrollView(
              child: Text(
                widget.jsonString,
                style: const TextStyle(
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTree(dynamic colors) {
    final l10n = AppLocalizations.of(context);
    final displayRows = _getDisplayRows();

    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: l10n?.jsonSearchHint ?? 'Search keys or values…',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        ),
        const SizedBox(height: AppDesignSystem.space2),
        Expanded(
          child: displayRows.isEmpty
              ? Center(
                  child: Text(
                    l10n?.jsonNoMatches ?? 'No matches',
                    style: TextStyle(fontSize: 13, color: colors.textMuted),
                  ),
                )
              : ListView.builder(
                  itemCount: displayRows.length,
                  itemExtent: 22,
                  itemBuilder: (_, i) => _buildRow(displayRows[i], colors),
                ),
        ),
      ],
    );
  }

  Widget _buildRow(_JsonRow row, dynamic colors) {
    final indent = row.depth * 16.0;

    if (row.isExpandable) {
      return Padding(
        padding: EdgeInsets.only(left: indent),
        child: GestureDetector(
          onTap: () => _toggle(_flattened.indexOf(row)),
          child: Row(
            children: [
              Icon(
                row.isExpanded
                    ? LucideIcons.chevronDown
                    : LucideIcons.chevronRight,
                size: 14,
                color: colors.textMuted,
              ),
              const SizedBox(width: 2),
              if (row.key != null)
                Text(
                  '${row.key}: ',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: AppDesignSystem.monoFontFamily,
                    fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                    color: Color(0xFF4099FF),
                  ),
                ),
              Text(
                _containerLabel(row.path),
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    // Value node
    return Padding(
      padding: EdgeInsets.only(left: indent + 16),
      child: Row(
        children: [
          if (row.key != null)
            Text(
              '${row.key}: ',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: AppDesignSystem.monoFontFamily,
                fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                color: Color(0xFF4099FF),
              ),
            ),
          // T044: 超长字符串值支持「Show full」切换展开看全文。
          ..._buildValueCell(row, colors),
        ],
      ),
    );
  }

  /// T044: 渲染值单元格。超长字符串（> _maxStringLength）显示截断文本 +
  /// 「Show full」/「Collapse」切换按钮；其它值单行显示。
  List<Widget> _buildValueCell(_JsonRow row, dynamic colors) {
    final value = row.value;
    final isLongString = value is String && value.length > _maxStringLength;
    final idx = _flattened.indexOf(row);
    final expanded = _expandedLongValues.contains(idx);
    // T061: 截断标记走 l10n（build 链路，context 可用）。
    final l10n = AppLocalizations.of(context);

    final baseStyle = TextStyle(
      fontSize: 11,
      fontFamily: AppDesignSystem.monoFontFamily,
      fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
      color: _valueColor(value),
    );

    if (!isLongString) {
      return [
        Flexible(
          child: Text(
            _formatValue(value, l10n: l10n),
            style: baseStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ];
    }

    // 超长字符串：截断态单行 + 按钮；展开态多行全文 + 折叠按钮。
    return [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded
                  ? '"$value"'
                  : _formatValue(value, l10n: l10n), // 截断态含 <truncated> 标记
              style: baseStyle,
              maxLines: expanded ? null : 1,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            InkWell(
              onTap: () => setState(() {
                if (expanded) {
                  _expandedLongValues.remove(idx);
                } else {
                  _expandedLongValues.add(idx);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  expanded ? '↑ Collapse' : '↓ Show full',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.accentBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  String _containerLabel(String path) {
    if (path == '\$') return '{} (root)';
    final last = path.split('.').last;
    if (last.contains('[')) return '[...]';
    return '{…}';
  }

  String _formatValue(dynamic value, {AppLocalizations? l10n}) {
    if (value == null) return 'null';
    if (value is String) {
      if (value.length > _maxStringLength) {
        // T061: <truncated> 走 l10n（l10n 为 null 时 fallback 英文，向后兼容）。
        final tag = l10n?.jsonTruncated ?? '<truncated>';
        return '"${value.substring(0, _maxStringLength)}…" $tag';
      }
      return '"$value"';
    }
    if (value is bool) return value.toString();
    if (value is num) return value.toString();
    return value.toString();
  }

  Color _valueColor(dynamic value) {
    // 暗色终端色系
    if (value == null) return const Color(0xFF858585);
    if (value is String) return const Color(0xFF46BF72);
    if (value is bool) return const Color(0xFF7B5CE5);
    if (value is num) return const Color(0xFFFF8A30);
    return const Color(0xFFD4D4D4);
  }
}

/// Convenience function to show the JSON viewer dialog.
Future<void> showJsonCellViewer(
  BuildContext context, {
  required String jsonString,
  required String columnName,
}) {
  return showDialog(
    context: context,
    builder: (_) =>
        JsonCellViewer(jsonString: jsonString, columnName: columnName),
  );
}
