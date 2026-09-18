// C12 · JSON 树渲染器——原型 result-panel-nosql「JSON 树」视图。
//
// 结果集整体作为 JSON 数组渲染：`[ {...}, {...} ]`，逐层可展开/折叠，
// 值按 BSON 类型着色（复用 bson_type 判定）。行经扁平化 + ListView.builder
// 虚拟化，折叠子树不参与扁平化（深文档不会整树铺开）。与 JsonCellViewer
// （单元格 JSON 弹窗）刻意分开实现：那边是单值弹窗 chrome（搜索/复制），
// 这里是结果集内嵌视图，共享仅 ~60 行扁平化逻辑，不抽公共层。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/result_renderer_plugin.dart';
import '../../../theme/app_theme.dart';
import 'bson_type.dart';

/// 默认展开深度（根数组 + 文档对象层级）。
const int _kDefaultExpandDepth = 2;

class JsonTreeResultRenderer implements ResultRendererPlugin {
  const JsonTreeResultRenderer();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'json-tree-result-renderer',
        icon: LucideIcons.gitBranch,
        displayName: (l10n) => l10n.viewModeJsonTree,
      );

  @override
  String get viewModeId => 'jsonTree';

  @override
  Set<ResultDataShape> get supportedShapes => const {
        ResultDataShape.nosqlDocument,
        // Redis 面板的 JSON 视图（c03 §4：keyValue / json / cli）。
        ResultDataShape.redisKeyValue,
      };

  @override
  Widget build(BuildContext context, ResultRenderContext renderContext) {
    return _JsonTreeView(rows: renderContext.rows);
  }
}

/// 扁平整行：路径唯一定位（展开态 key）。
class _TreeRow {
  final int depth;
  final String? key;
  final dynamic value;
  final String path;

  const _TreeRow({
    required this.depth,
    this.key,
    required this.value,
    required this.path,
  });

  bool get isExpandable => value is Map || value is List;
}

class _JsonTreeViewState extends State<_JsonTreeView> {
  /// 用户显式折叠的路径。
  final Set<String> _collapsedPaths = {};

  /// 用户显式展开的路径（覆盖深于默认展开层的默认折叠）。
  final Set<String> _forcedExpandedPaths = {};

  bool _isCollapsed(String path, int depth) =>
      !_forcedExpandedPaths.contains(path) &&
      (_collapsedPaths.contains(path) || depth >= _kDefaultExpandDepth);

  @override
  Widget build(BuildContext context) {
    final rows = _flatten(widget.rows, 0, r'$');
    return ListView.builder(
      padding: const EdgeInsets.all(AppDesignSystem.space3),
      itemCount: rows.length,
      itemBuilder: (context, index) => _buildRow(context, rows[index]),
    );
  }

  /// 扁平化：展开态的 Map/List 节点递归展开子行，折叠的只出节点自身。
  /// 深于 [_kDefaultExpandDepth] 的容器默认折叠（深文档不整树铺开）。
  List<_TreeRow> _flatten(dynamic node, int depth, String path,
      {String? key}) {
    final row = _TreeRow(depth: depth, key: key, value: node, path: path);
    final isContainer = node is Map || node is List;
    if (!isContainer || _isCollapsed(path, depth)) {
      return [row];
    }
    final children = <_TreeRow>[];
    if (node is Map) {
      for (final entry in node.entries) {
        children.addAll(
          _flatten(
            entry.value,
            depth + 1,
            '$path.${entry.key}',
            key: entry.key.toString(),
          ),
        );
      }
    } else if (node is List) {
      for (var i = 0; i < node.length; i++) {
        children.addAll(
          _flatten(node[i], depth + 1, '$path[$i]', key: '$i'),
        );
      }
    }
    return [row, ...children];
  }

  Widget _buildRow(BuildContext context, _TreeRow row) {
    final colors = context.themeColors;
    final expanded = row.isExpandable && !_isCollapsed(row.path, row.depth);
    final type = bsonFieldTypeOf(row.value);

    return InkWell(
      onTap: row.isExpandable
          ? () => setState(() {
                if (_isCollapsed(row.path, row.depth)) {
                  _collapsedPaths.remove(row.path);
                  _forcedExpandedPaths.add(row.path);
                } else {
                  _collapsedPaths.add(row.path);
                  _forcedExpandedPaths.remove(row.path);
                }
              })
          : null,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppDesignSystem.space3 * row.depth.toDouble(),
          top: 1,
          bottom: 1,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              height: 18,
              child: row.isExpandable
                  ? Icon(
                      expanded
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronRight,
                      size: 14,
                      color: colors.textMuted,
                    )
                  : null,
            ),
            if (row.key != null) ...[
              Text(
                row.key!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: AppDesignSystem.monoFontFamily,
                  fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
              Text(
                ':',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
              const SizedBox(width: AppDesignSystem.space1_5),
            ],
            Expanded(
              child: _ValueText(value: row.value, type: type),
            ),
            if (row.isExpandable)
              Padding(
                padding: const EdgeInsets.only(left: AppDesignSystem.space2),
                child: Text(
                  _containerSummary(row.value),
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 容器节点的行尾摘要：{k1, k2, …} / [n 项]。l10n 空时退英文（防御式）。
  String _containerSummary(dynamic value) {
    final l10n = AppLocalizations.of(context);
    if (value is Map) {
      final keys = value.keys.take(3).map((k) => k.toString()).join(', ');
      final suffix = value.length > 3 ? ', …' : '';
      return '{$keys$suffix}';
    }
    if (value is List) {
      return l10n?.jsonTreeItemCount(value.length) ?? '${value.length} items';
    }
    return '';
  }
}

/// 值文本：标量按类型着色 + 等价展示（复用 bson_value_display 的引号/
/// ISODate 格式）；容器折叠态显示展开提示。
class _ValueText extends StatelessWidget {
  final dynamic value;
  final BsonFieldType type;

  const _ValueText({required this.value, required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final isContainer = value is Map || value is List;
    if (isContainer) {
      return Text(
        value is Map ? '{…}' : '[…]',
        style: TextStyle(
          fontSize: 12,
          fontFamily: AppDesignSystem.monoFontFamily,
          fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
          color: colors.textMuted,
        ),
      );
    }
    Color valueColor;
    switch (type) {
      case BsonFieldType.string:
      case BsonFieldType.objectId:
        valueColor = colors.success;
      case BsonFieldType.number:
        valueColor = colors.warning;
      case BsonFieldType.boolean:
        valueColor = colors.info;
      case BsonFieldType.isoDate:
        valueColor = colors.info;
      case BsonFieldType.nullValue:
        valueColor = colors.textMuted;
      case BsonFieldType.object:
      case BsonFieldType.array:
        valueColor = colors.textPrimary;
    }
    return Text(
      bsonValueDisplay(value, maxLen: 120),
      style: TextStyle(
        fontSize: 12,
        fontFamily: AppDesignSystem.monoFontFamily,
        fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
        color: valueColor,
      ),
    );
  }
}

class _JsonTreeView extends StatefulWidget {
  final List<Map<String, dynamic>> rows;

  const _JsonTreeView({required this.rows});

  @override
  State<_JsonTreeView> createState() => _JsonTreeViewState();
}
