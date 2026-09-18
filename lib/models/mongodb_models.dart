/// MongoDB 特有数据模型
/// 用于导航界面展示 Collection、Document Schema 等信息
library;

/// 集合信息模型
class CollectionInfo {
  final String name;
  final String type; // 'collection', 'view'
  final int? documentCount;
  final int? storageSize;
  final bool isCapped;
  final bool isTimeSeries;
  final String? viewOn;
  final Map<String, dynamic>? options;

  const CollectionInfo({
    required this.name,
    this.type = 'collection',
    this.documentCount,
    this.storageSize,
    this.isCapped = false,
    this.isTimeSeries = false,
    this.viewOn,
    this.options,
  });

  /// 从适配器返回的 Map 创建实例
  factory CollectionInfo.fromAdapter(Map<String, dynamic> map) {
    return CollectionInfo(
      name: map['name'] as String? ?? '',
      type: map['type'] as String? ?? 'collection',
      documentCount: map['documentCount'] as int?,
      storageSize: map['storageSize'] as int?,
      isCapped: map['isCapped'] == true,
      isTimeSeries: map['isTimeSeries'] == true,
      viewOn: map['viewOn'] as String?,
      options: map['options'] as Map<String, dynamic>?,
    );
  }

  /// 是否为视图
  bool get isView => type == 'view';

  /// 是否为 GridFS 集合（以 .files 或 .chunks 结尾）
  bool get isGridFS => name.endsWith('.files') || name.endsWith('.chunks');

  /// GridFS bucket 名称（如果是 GridFS 集合）
  String? get gridfsBucket {
    if (name.endsWith('.files')) return name.substring(0, name.length - 6);
    if (name.endsWith('.chunks')) return name.substring(0, name.length - 7);
    return null;
  }

  /// 集合类型图标
  String get typeIcon {
    if (isView) return '👁️';
    if (isTimeSeries) return '⏱️';
    if (isCapped) return '🔄';
    if (isGridFS) return '🗄️';
    return '📦';
  }

  /// 集合类型描述
  String get typeDescription {
    if (isView) return 'View';
    if (isTimeSeries) return 'Time-Series';
    if (isCapped) return 'Capped';
    if (isGridFS) return 'GridFS';
    return 'Collection';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type,
      'documentCount': documentCount,
      'storageSize': storageSize,
      'isCapped': isCapped,
      'isTimeSeries': isTimeSeries,
      'viewOn': viewOn,
      'options': options,
    };
  }

  factory CollectionInfo.fromJson(Map<String, dynamic> json) {
    return CollectionInfo(
      name: json['name'] as String,
      type: json['type'] as String? ?? 'collection',
      documentCount: json['documentCount'] as int?,
      storageSize: json['storageSize'] as int?,
      isCapped: json['isCapped'] as bool? ?? false,
      isTimeSeries: json['isTimeSeries'] as bool? ?? false,
      viewOn: json['viewOn'] as String?,
      options: json['options'] as Map<String, dynamic>?,
    );
  }

  /// 格式化的存储大小显示
  String get formattedSize {
    if (storageSize == null) return 'N/A';
    final size = storageSize!;
    if (size >= 1073741824)
      return '${(size / 1073741824).toStringAsFixed(1)} GB';
    if (size >= 1048576) return '${(size / 1048576).toStringAsFixed(1)} MB';
    if (size >= 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '$size B';
  }

  /// 格式化的文档数量显示
  String get formattedDocumentCount {
    if (documentCount == null) return 'N/A';
    final count = documentCount!;
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

/// BSON 字段模型（用于展示推断的 Schema）
class BsonField {
  final String name;
  final String bsonType;
  final double occurrence; // 0.0 - 1.0
  final bool isNullable;
  final List<BsonField>? subFields; // Document 类型的子字段
  final List<String>? elementTypes; // Array 类型的元素类型

  const BsonField({
    required this.name,
    required this.bsonType,
    this.occurrence = 1.0,
    this.isNullable = false,
    this.subFields,
    this.elementTypes,
  });

  /// 从 Schema 推断结果的 Map 创建实例
  factory BsonField.fromSchema(String name, Map<String, dynamic> schema) {
    final type = schema['type'] as String? ?? 'Unknown';
    final occurrence = (schema['occurrence'] as int? ?? 1).toDouble();
    final totalSampled = schema['totalSampled'] as int? ?? 1;
    final occurrenceRate = totalSampled > 0 ? occurrence / totalSampled : 1.0;

    List<BsonField>? children;
    if (schema['subFields'] != null) {
      final subFields = schema['subFields'] as Map<String, dynamic>;
      children = subFields.entries
          .map((e) => BsonField.fromSchema(e.key, e.value))
          .toList();
    }

    List<String>? elements;
    if (schema['elementTypes'] != null) {
      elements = (schema['elementTypes'] as List).cast<String>();
    }

    return BsonField(
      name: name,
      bsonType: type,
      occurrence: occurrenceRate,
      isNullable: occurrenceRate < 1.0,
      subFields: children,
      elementTypes: elements,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'bsonType': bsonType,
      'occurrence': occurrence,
      'isNullable': isNullable,
      'subFields': subFields?.map((f) => f.toJson()).toList(),
      'elementTypes': elementTypes,
    };
  }

  factory BsonField.fromJson(Map<String, dynamic> json) {
    return BsonField(
      name: json['name'] as String,
      bsonType: json['bsonType'] as String? ?? 'Unknown',
      occurrence: (json['occurrence'] as num?)?.toDouble() ?? 1.0,
      isNullable: json['isNullable'] as bool? ?? false,
      subFields: (json['subFields'] as List<dynamic>?)
          ?.map((e) => BsonField.fromJson(e as Map<String, dynamic>))
          .toList(),
      elementTypes: (json['elementTypes'] as List<dynamic>?)?.cast<String>(),
    );
  }

  /// 出现率百分比
  int get occurrencePercentage => (occurrence * 100).round();

  /// 是否出现频率较低（< 100%）
  bool get isSparselyPopulated => occurrence < 1.0;

  /// 类型显示标签
  String get typeLabel {
    if (bsonType == 'Array' &&
        elementTypes != null &&
        elementTypes!.isNotEmpty) {
      return 'Array<${elementTypes!.join('|')}>';
    }
    return bsonType;
  }

  /// 字段路径（用于查询构建）
  String getPath([String? parentPath]) {
    if (parentPath == null || parentPath.isEmpty) return name;
    return '$parentPath.$name';
  }
}
