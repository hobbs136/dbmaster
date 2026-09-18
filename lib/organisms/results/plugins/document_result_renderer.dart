// C12 · NoSQL 文档渲染器——原型 result-panel-nosql「文档卡片」视图。
//
// 每行即一份文档（nosqlDocument 形态：Mongo adapter 上行保留嵌套 Map/List）。
// 卡片结构按原型：头部 = _id（或首字段）+ 类型徽章 + mono 值；字段行 =
// 字段名 + 六色 BSON 徽章 + mono 值；嵌套文档渲染为可折叠子框。超过
// [_kCollapsedFieldThreshold] 个顶层字段的文档默认折叠（长文档防溢出），
// 其余全展。表格视图仍可作为兜底切换（table 渲染器同声明 nosqlDocument）。
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../l10n/app_localizations.dart';
import '../../../plugins/plugin_descriptor.dart';
import '../../../plugins/result_renderer_plugin.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_theme.dart';
import 'bson_type.dart';

/// 顶层字段数超过该阈值的文档默认折叠（展示前 N 个字段 + 展开按钮）。
const int _kCollapsedFieldThreshold = 8;

/// 折叠态预览的字段数。
const int _kCollapsedFieldPreview = 4;

class DocumentResultRenderer implements ResultRendererPlugin {
  const DocumentResultRenderer();

  @override
  PluginDescriptor get descriptor => PluginDescriptor(
        id: 'document-result-renderer',
        icon: LucideIcons.layoutGrid,
        displayName: (l10n) => l10n.viewModeDocument,
      );

  @override
  String get viewModeId => 'document';

  @override
  Set<ResultDataShape> get supportedShapes => const {ResultDataShape.nosqlDocument};

  @override
  Widget build(BuildContext context, ResultRenderContext renderContext) {
    return _DocumentCardList(documents: renderContext.rows);
  }
}

class _DocumentCardList extends StatefulWidget {
  final List<Map<String, dynamic>> documents;

  const _DocumentCardList({required this.documents});

  @override
  State<_DocumentCardList> createState() => _DocumentCardListState();
}

class _DocumentCardListState extends State<_DocumentCardList> {
  /// 展开的文档索引（超阈值文档默认折叠）。
  final Set<int> _expandedDocs = {};

  /// 展开的嵌套对象（「docIndex#fieldPath」）。
  final Set<String> _expandedObjects = {};

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      itemCount: widget.documents.length,
      itemBuilder: (context, index) {
        final doc = widget.documents[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppDesignSystem.space4),
          child: _DocumentCard(
            doc: doc,
            docIndex: index,
            expanded: _expandedDocs.contains(index),
            expandedObjects: _expandedObjects,
            onToggleExpanded: () => setState(() {
              if (!_expandedDocs.remove(index)) _expandedDocs.add(index);
            }),
            onToggleObject: (path) => setState(() {
              if (!_expandedObjects.remove(path)) _expandedObjects.add(path);
            }),
          ),
        );
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  final int docIndex;

  /// 超阈值折叠语义下的展开态；字段数 ≤ 阈值的文档恒视为展开。
  final bool expanded;
  final Set<String> expandedObjects;
  final VoidCallback onToggleExpanded;
  final ValueChanged<String> onToggleObject;

  const _DocumentCard({
    required this.doc,
    required this.docIndex,
    required this.expanded,
    required this.expandedObjects,
    required this.onToggleExpanded,
    required this.onToggleObject,
  });

  /// 头部字段：优先 `_id`（BSON 惯例主键），否则首字段。
  MapEntry<String, dynamic> get _headerField {
    final id = doc.entries.where((e) => e.key == '_id').firstOrNull;
    return id ?? doc.entries.first;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final header = _headerField;
    final bodyFields = doc.entries
        .where((e) => e.key != header.key)
        .toList(growable: false);
    final collapsible =
        bodyFields.length > _kCollapsedFieldThreshold;
    final visibleFields = collapsible && !expanded
        ? bodyFields.take(_kCollapsedFieldPreview).toList(growable: false)
        : bodyFields;

    return Container(
      padding: const EdgeInsets.all(AppDesignSystem.space4),
      decoration: BoxDecoration(
        color: colors.bgPrimary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusMd),
        border: Border.all(color: colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：_id + 徽章 + 值（+ 超阈值文档的展开/折叠按钮）
          Container(
            padding: const EdgeInsets.only(
              bottom: AppDesignSystem.space3,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.borderLight),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _FieldRow(
                    name: header.key,
                    value: header.value,
                    compact: true,
                  ),
                ),
                if (collapsible)
                  TextButton.icon(
                    onPressed: onToggleExpanded,
                    icon: Icon(
                      expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 14,
                    ),
                    label: Text(
                      expanded
                          ? l10n.documentCollapse
                          : l10n.documentExpandMore(
                              bodyFields.length - visibleFields.length,
                            ),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.accentBlue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDesignSystem.space2,
                        vertical: AppDesignSystem.space1,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppDesignSystem.space3),
          for (final field in visibleFields)
            if (bsonFieldTypeOf(field.value) == BsonFieldType.object)
              _NestedObjectBox(
                name: field.key,
                value: field.value as Map,
                objectKey: '$docIndex#${field.key}',
                expandedObjects: expandedObjects,
                onToggle: onToggleObject,
              )
            else
              Padding(
                padding: const EdgeInsets.only(
                  bottom: AppDesignSystem.space2,
                ),
                child: _FieldRow(name: field.key, value: field.value),
              ),
        ],
      ),
    );
  }
}

/// 字段行：名 + 徽章 + mono 值（原型 .flex items-start gap-2 形态）。
class _FieldRow extends StatelessWidget {
  final String name;
  final dynamic value;
  final bool compact;

  const _FieldRow({required this.name, required this.value, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final type = bsonFieldTypeOf(value);
    final isNull = type == BsonFieldType.nullValue;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppDesignSystem.space2),
        if (!isNull) ...[
          BsonTypeBadge(type: type),
          const SizedBox(width: AppDesignSystem.space2),
        ],
        Expanded(
          child: Text(
            bsonValueDisplay(value, maxLen: compact ? 40 : 96),
            style: TextStyle(
              fontSize: 12,
              fontFamily: AppDesignSystem.monoFontFamily,
              fontFamilyFallback: AppDesignSystem.monoFontFamilyFallback,
              color: isNull ? colors.textMuted : colors.textPrimary,
              fontStyle: isNull ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// 嵌套文档框（原型 profile 子框）：可折叠，字段行缩进渲染。
class _NestedObjectBox extends StatelessWidget {
  final String name;
  final Map value;
  final String objectKey;
  final Set<String> expandedObjects;
  final ValueChanged<String> onToggle;

  const _NestedObjectBox({
    required this.name,
    required this.value,
    required this.objectKey,
    required this.expandedObjects,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final l10n = AppLocalizations.of(context)!;
    final expanded = expandedObjects.contains(objectKey);
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesignSystem.space2),
      padding: const EdgeInsets.all(AppDesignSystem.space2),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(AppDesignSystem.radiusSm),
        border: Border.all(color: colors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: AppDesignSystem.space2),
              BsonTypeBadge(type: BsonFieldType.object),
              const Spacer(),
              GestureDetector(
                onTap: () => onToggle(objectKey),
                child: Row(
                  children: [
                    Icon(
                      expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 12,
                      color: colors.textSecondary,
                    ),
                    Text(
                      expanded ? l10n.documentCollapse : l10n.documentExpand,
                      style: TextStyle(
                        fontSize: 10,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(
                left: AppDesignSystem.space2,
                top: AppDesignSystem.space1_5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in value.entries)
                    if (bsonFieldTypeOf(entry.value) == BsonFieldType.object)
                      _NestedObjectBox(
                        name: entry.key.toString(),
                        value: entry.value as Map,
                        objectKey: '$objectKey.${entry.key}',
                        expandedObjects: expandedObjects,
                        onToggle: onToggle,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppDesignSystem.space1_5,
                        ),
                        child: _FieldRow(
                          name: entry.key.toString(),
                          value: entry.value,
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
