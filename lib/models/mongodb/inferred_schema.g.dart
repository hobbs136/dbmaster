// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inferred_schema.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SchemaField _$SchemaFieldFromJson(Map<String, dynamic> json) => SchemaField(
  name: json['name'] as String,
  bsonType: json['bsonType'] as String,
  presenceRatio: (json['presenceRatio'] as num).toDouble(),
  mixedTypes: (json['mixedTypes'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  isNested: json['isNested'] as bool,
  subFields: (json['subFields'] as List<dynamic>?)
      ?.map((e) => SchemaField.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SchemaFieldToJson(SchemaField instance) =>
    <String, dynamic>{
      'name': instance.name,
      'bsonType': instance.bsonType,
      'presenceRatio': instance.presenceRatio,
      'mixedTypes': instance.mixedTypes,
      'isNested': instance.isNested,
      'subFields': instance.subFields,
    };

InferredDocumentSchema _$InferredDocumentSchemaFromJson(
  Map<String, dynamic> json,
) => InferredDocumentSchema(
  collectionName: json['collectionName'] as String,
  totalSampled: (json['totalSampled'] as num).toInt(),
  fields: (json['fields'] as List<dynamic>)
      .map((e) => SchemaField.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$InferredDocumentSchemaToJson(
  InferredDocumentSchema instance,
) => <String, dynamic>{
  'collectionName': instance.collectionName,
  'totalSampled': instance.totalSampled,
  'fields': instance.fields,
};
