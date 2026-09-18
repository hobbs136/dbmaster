// C12 · BSON 字段类型推断与徽章——NoSQL 文档渲染器 / JSON 树渲染器共用。
//
// 数据现实：Mongo adapter 的 _convertValue 在上行前已把 ObjectId/Binary/
// Timestamp 等原生 BSON 类型规约为 Dart 基础值（ObjectId → 24 位 hex 字符
// 串、DateTime → ISO8601 字符串、嵌套文档保留 Map、数组保留 List）。
// 本模块按「值形态 + Mongo 惯用格式」推断展示类型并配原型（result-panel-
// nosql）的六色徽章：ObjectId/String/Number/Boolean/ISODate/Array（Map 渲染
// 为嵌套文档框、null 无徽章）。启发式有误判面（如恰好 24 位 hex 的普通
// 字符串会被标为 ObjectId），换取不动 adapter 数据路径与查询历史序列化。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/app_colors.dart';

/// BSON 展示类型（原型六徽章 + Object/null 两个无徽章形态）。
enum BsonFieldType { objectId, string, number, boolean, isoDate, array, object, nullValue }

/// 24 位 hex（Mongo ObjectId.oid 上行形态）。
final RegExp _objectIdPattern = RegExp(r'^[0-9a-fA-F]{24}$');

/// ISO8601 日期时间（adapter 上行 DateTime.toIso8601String() 形态；
/// 要求含时间部分——纯日期串按 String 展示）。
final RegExp _isoDatePattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?(\.\d+)?(Z|[+-]\d{2}:?\d{2})?$',
);

BsonFieldType bsonFieldTypeOf(dynamic value) {
  if (value == null) return BsonFieldType.nullValue;
  if (value is bool) return BsonFieldType.boolean;
  if (value is num) return BsonFieldType.number;
  if (value is Map) return BsonFieldType.object;
  if (value is List) return BsonFieldType.array;
  if (value is String) {
    if (_objectIdPattern.hasMatch(value)) return BsonFieldType.objectId;
    if (_isoDatePattern.hasMatch(value)) return BsonFieldType.isoDate;
    return BsonFieldType.string;
  }
  return BsonFieldType.string;
}

/// 徽章背景色（原型色映射：ObjectId=brand / String=success / Number=warning /
/// Boolean=中性 / ISODate=info / Array=error；Object 与 null 无徽章）。
Color? bsonBadgeColor(BsonFieldType type, ThemeColors colors) {
  switch (type) {
    case BsonFieldType.objectId:
      return colors.accentBlue;
    case BsonFieldType.string:
      return colors.success;
    case BsonFieldType.number:
      return colors.warning;
    case BsonFieldType.boolean:
      // 中性徽章：背景用面层色而非语义色，文字用次级文本色。
      return colors.bgTertiary;
    case BsonFieldType.isoDate:
      return colors.info;
    case BsonFieldType.array:
      return colors.error;
    case BsonFieldType.object:
    case BsonFieldType.nullValue:
      return null;
  }
}

/// 徽章文字色（Boolean 用次级文本色，其余语义色底配白字）。
Color bsonBadgeTextColor(BsonFieldType type, ThemeColors colors) {
  if (type == BsonFieldType.boolean) return colors.textSecondary;
  // 深色语义底与浅色 *Light 变体底均可读。
  return Colors.white;
}

/// 徽章标签（BSON 惯用名，与原型一致——不进 l10n：类型名是技术词汇）。
String bsonBadgeLabel(BsonFieldType type) {
  switch (type) {
    case BsonFieldType.objectId:
      return 'ObjectId';
    case BsonFieldType.string:
      return 'String';
    case BsonFieldType.number:
      return 'Number';
    case BsonFieldType.boolean:
      return 'Boolean';
    case BsonFieldType.isoDate:
      return 'ISODate';
    case BsonFieldType.array:
      return 'Array';
    case BsonFieldType.object:
      return 'Object';
    case BsonFieldType.nullValue:
      return 'null';
  }
}

/// 类型徽章 widget（10px 圆角小标签，原型 .text-[10px] 形态）。
class BsonTypeBadge extends StatelessWidget {
  final BsonFieldType type;

  const BsonTypeBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final bg = bsonBadgeColor(type, colors);
    if (bg == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        bsonBadgeLabel(type),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: bsonBadgeTextColor(type, colors),
        ),
      ),
    );
  }
}

/// 字段值的等价显示文本（原型格式：字符串带引号 / ISODate("...") /
/// ObjectId 裸 hex / 数组截断 JSON）。
String bsonValueDisplay(dynamic value, {int maxLen = 64}) {
  final type = bsonFieldTypeOf(value);
  String text;
  switch (type) {
    case BsonFieldType.string:
      text = '"$value"';
    case BsonFieldType.isoDate:
      text = 'ISODate("$value")';
    case BsonFieldType.array:
    case BsonFieldType.object:
      // 简洁 JSON 预览；截断由 maxLen 统一处理。
      try {
        text = value.toString();
      } catch (_) {
        text = value.runtimeType.toString();
      }
    case BsonFieldType.nullValue:
      return 'null';
    default:
      text = value.toString();
  }
  if (text.length > maxLen) {
    return '${text.substring(0, maxLen)}…';
  }
  return text;
}
