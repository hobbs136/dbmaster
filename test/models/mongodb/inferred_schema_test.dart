import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb/inferred_schema.dart';

void main() {
  group('InferredDocumentSchema', () {
    test('should create schema from adapter output with valid data', () {
      final adapterOutput = {
        'collectionName': 'users',
        'totalSampled': 100,
        'fields': {
          'name': {'type': 'String', 'occurrence': 95},
          'age': {'type': 'int', 'occurrence': 80},
        },
      };

      final schema = InferredDocumentSchema.fromAdapterOutput(adapterOutput);

      expect(schema.collectionName, 'users');
      expect(schema.totalSampled, 100);
      expect(schema.fields.length, 2);
      expect(schema.fields[0].name, 'name');
      expect(schema.fields[0].bsonType, 'String');
      expect(schema.fields[0].presenceRatio, 0.95);
    });

    test('should handle empty collection (no fields)', () {
      final adapterOutput = {
        'collectionName': 'empty_collection',
        'totalSampled': 0,
        'fields': {},
      };

      final schema = InferredDocumentSchema.fromAdapterOutput(adapterOutput);

      expect(schema.collectionName, 'empty_collection');
      expect(schema.totalSampled, 0);
      expect(schema.fields.isEmpty, true);
      expect(schema.isEmpty, true);
    });

    test('should handle nested document fields', () {
      final adapterOutput = {
        'collectionName': 'users',
        'totalSampled': 50,
        'fields': {
          'address': {
            'type': 'document',
            'occurrence': 40,
            'subFields': {
              'city': {'type': 'String', 'occurrence': 38},
              'zip': {'type': 'String', 'occurrence': 35},
            },
          },
        },
      };

      final schema = InferredDocumentSchema.fromAdapterOutput(adapterOutput);

      expect(schema.fields.length, 1);
      final addressField = schema.fields[0];
      expect(addressField.name, 'address');
      expect(addressField.isNested, true);
      expect(addressField.subFields, isNotNull);
      expect(addressField.subFields!.length, 2);
      expect(addressField.subFields![0].name, 'city');
    });

    test('should calculate presence ratio correctly', () {
      final adapterOutput = {
        'collectionName': 'test',
        'totalSampled': 200,
        'fields': {
          'field1': {'type': 'String', 'occurrence': 100},
          'field2': {'type': 'int', 'occurrence': 50},
        },
      };

      final schema = InferredDocumentSchema.fromAdapterOutput(adapterOutput);

      expect(schema.fields[0].presenceRatio, 0.5);
      expect(schema.fields[1].presenceRatio, 0.25);
    });

    test('should handle missing field names gracefully', () {
      final adapterOutput = {
        'collectionName': 'test',
        'totalSampled': 10,
        'fields': {},
      };

      final schema = InferredDocumentSchema.fromAdapterOutput(adapterOutput);

      expect(schema.collectionName, 'test');
      expect(schema.totalSampled, 10);
      expect(schema.fields.isEmpty, true);
    });
  });

  group('SchemaField', () {
    test('should create field from adapter output', () {
      final fieldData = {
        'type': 'String',
        'occurrence': 80,
        'totalSampled': 100,
      };

      final field = SchemaField.fromAdapterOutput('username', fieldData);

      expect(field.name, 'username');
      expect(field.bsonType, 'String');
      expect(field.presenceRatio, 0.8);
      expect(field.isNested, false);
    });

    test('should handle nested fields recursively', () {
      final fieldData = {
        'type': 'document',
        'occurrence': 60,
        'totalSampled': 100,
        'subFields': {
          'nested1': {'type': 'int', 'occurrence': 55, 'totalSampled': 100},
          'nested2': {
            'type': 'document',
            'occurrence': 40,
            'totalSampled': 100,
            'subFields': {
              'deepNested': {'type': 'String', 'occurrence': 35, 'totalSampled': 100},
            },
          },
        },
      };

      final field = SchemaField.fromAdapterOutput('parent', fieldData);

      expect(field.name, 'parent');
      expect(field.isNested, true);
      expect(field.subFields, isNotNull);
      expect(field.subFields!.length, 2);
      
      // Check deep nesting
      final nested2 = field.subFields![1];
      expect(nested2.name, 'nested2');
      expect(nested2.isNested, true);
      expect(nested2.subFields!.length, 1);
      expect(nested2.subFields![0].name, 'deepNested');
    });

    test('should detect mixed types (future enhancement)', () {
      final fieldData = {
        'type': 'Mixed',
        'occurrence': 100,
        'totalSampled': 100,
      };

      final field = SchemaField.fromAdapterOutput('mixedField', fieldData);

      expect(field.name, 'mixedField');
      expect(field.bsonType, 'Mixed');
      expect(field.presenceRatio, 1.0);
    });

    test('should handle zero occurrence correctly', () {
      final fieldData = {
        'type': 'String',
        'occurrence': 0,
        'totalSampled': 100,
      };

      final field = SchemaField.fromAdapterOutput('rareField', fieldData);

      expect(field.presenceRatio, 0.0);
    });

    test('should handle array types', () {
      final fieldData = {
        'type': 'array',
        'occurrence': 30,
        'totalSampled': 100,
      };

      final field = SchemaField.fromAdapterOutput('tags', fieldData);

      expect(field.name, 'tags');
      expect(field.bsonType, 'array');
      expect(field.presenceRatio, 0.3);
    });
  });
}
