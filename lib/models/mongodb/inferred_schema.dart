import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/foundation.dart';

part 'inferred_schema.g.dart';

/// Represents a single field in the inferred document schema
@immutable
@JsonSerializable()
class SchemaField {
  /// Field name (e.g., "age", "address")
  final String name;
  
  /// Dominant BSON type (e.g., "int", "String", "document", "array")
  final String bsonType;
  
  /// Presence percentage (0.0 to 1.0)
  final double presenceRatio;
  
  /// List of detected types if mixed (null if single type)
  final List<String>? mixedTypes;
  
  /// Whether field contains nested documents/arrays
  final bool isNested;
  
  /// Nested fields if isNested == true
  final List<SchemaField>? subFields;
  
  SchemaField({
    required this.name,
    required this.bsonType,
    required this.presenceRatio,
    this.mixedTypes,
    required this.isNested,
    this.subFields,
  }) : assert(name.isNotEmpty, 'Field name must not be empty'),
       assert(presenceRatio >= 0.0 && presenceRatio <= 1.0, 'Presence ratio must be between 0.0 and 1.0'),
       assert(
         !isNested || (subFields != null && subFields.isNotEmpty),
         'Nested fields must be non-empty if isNested is true',
       );
  
  factory SchemaField.fromJson(Map<String, dynamic> json) =>
      _$SchemaFieldFromJson(json);
  
  Map<String, dynamic> toJson() => _$SchemaFieldToJson(this);
  
  /// Create SchemaField from raw adapter output
  factory SchemaField.fromAdapterOutput(String fieldName, Map<String, dynamic> fieldData) {
    final type = fieldData['type'] as String? ?? 'Unknown';
    final occurrence = fieldData['occurrence'] as int? ?? 0;
    final totalSampled = fieldData['totalSampled'] as int? ?? 1;
    
    // Check for nested fields (subFields in adapter output)
    final subFieldsData = (fieldData['subFields'] as Map?)?.cast<String, dynamic>();
    final isNested = subFieldsData != null && subFieldsData.isNotEmpty;
    
    // Build nested field list
    List<SchemaField>? subFields;
    if (isNested) {
      subFields = subFieldsData.entries.map((entry) {
        return SchemaField.fromAdapterOutput(
          entry.key,
          {
            ...(entry.value as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
            'totalSampled': totalSampled,
          },
        );
      }).toList();
    }
    
    return SchemaField(
      name: fieldName,
      bsonType: type,
      presenceRatio: occurrence / totalSampled,
      isNested: isNested,
      subFields: subFields,
    );
  }
}

/// Container for the complete inferred schema of a collection
@immutable
@JsonSerializable()
class InferredDocumentSchema {
  /// Collection name
  final String collectionName;
  
  /// Number of documents sampled (max 100)
  final int totalSampled;
  
  /// All top-level fields
  final List<SchemaField> fields;
  
  InferredDocumentSchema({
    required this.collectionName,
    required this.totalSampled,
    required this.fields,
  }) : assert(collectionName.isNotEmpty, 'Collection name must not be empty'),
       assert(totalSampled >= 0, 'Total sampled must not be negative');
  
  factory InferredDocumentSchema.fromJson(Map<String, dynamic> json) =>
      _$InferredDocumentSchemaFromJson(json);
  
  Map<String, dynamic> toJson() => _$InferredDocumentSchemaToJson(this);
  
  /// Create InferredDocumentSchema from raw adapter output
  factory InferredDocumentSchema.fromAdapterOutput(Map<String, dynamic> adapterOutput) {
    final collectionName = adapterOutput['collectionName'] as String? ?? '';
    final totalSampled = adapterOutput['totalSampled'] as int? ?? 0;
    final fieldsData = (adapterOutput['fields'] as Map?)?.cast<String, dynamic>() ?? {};
    
    // Build field list from adapter output
    final fields = fieldsData.entries.map((entry) {
      return SchemaField.fromAdapterOutput(
        entry.key,
        {
          ...(entry.value as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{},
          'totalSampled': totalSampled,
        },
      );
    }).toList();
    
    return InferredDocumentSchema(
      collectionName: collectionName,
      totalSampled: totalSampled,
      fields: fields,
    );
  }
  
  /// Check if schema is empty (no fields sampled)
  bool get isEmpty => fields.isEmpty || totalSampled == 0;
}
