import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb_models.dart';

/// MongoDB 模型测试
void main() {
  group('MongoDB 模型', () {
    group('CollectionInfo', () {
      test('应正确创建 CollectionInfo 实例', () {
        final collection = CollectionInfo(
          name: 'users',
          type: 'collection',
          documentCount: 12500,
          storageSize: 2345678,
          isCapped: false,
        );

        expect(collection.name, equals('users'));
        expect(collection.type, equals('collection'));
        expect(collection.documentCount, equals(12500));
        expect(collection.storageSize, equals(2345678));
        expect(collection.isCapped, isFalse);
        expect(collection.isView, isFalse);
      });

      test('应正确识别视图类型', () {
        final view = CollectionInfo(
          name: 'monthly_sales',
          type: 'view',
          viewOn: 'sales',
        );

        expect(view.isView, isTrue);
        expect(view.viewOn, equals('sales'));
      });

      test('应正确创建 Time-Series 集合', () {
        final tsCollection = CollectionInfo(
          name: 'sensor_data',
          type: 'collection',
          isTimeSeries: true,
        );

        expect(tsCollection.isTimeSeries, isTrue);
      });

      test('应支持 JSON 序列化和反序列化', () {
        final original = CollectionInfo(
          name: 'orders',
          type: 'collection',
          documentCount: 8200,
          storageSize: 1234567,
          isCapped: true,
          options: {'capped': true, 'size': 100000},
        );

        final json = original.toJson();
        final restored = CollectionInfo.fromJson(json);

        expect(restored.name, equals(original.name));
        expect(restored.type, equals(original.type));
        expect(restored.documentCount, equals(original.documentCount));
        expect(restored.isCapped, equals(original.isCapped));
      });
    });

    group('BsonField', () {
      test('应正确创建基础 BSON 字段', () {
        final field = BsonField(
          name: 'email',
          bsonType: 'String',
          occurrence: 1.0,
        );

        expect(field.name, equals('email'));
        expect(field.bsonType, equals('String'));
        expect(field.occurrence, equals(1.0));
        expect(field.isNullable, isFalse);
        expect(field.subFields, isNull);
      });

      test('应支持嵌套 Document 字段', () {
        final field = BsonField(
          name: 'profile',
          bsonType: 'Document',
          subFields: [
            BsonField(name: 'avatar', bsonType: 'String'),
            BsonField(name: 'age', bsonType: 'Number'),
          ],
        );

        expect(field.subFields, isNotNull);
        expect(field.subFields!.length, equals(2));
        expect(field.subFields![0].name, equals('avatar'));
      });

      test('应支持 Array 字段及元素类型', () {
        final field = BsonField(
          name: 'tags',
          bsonType: 'Array',
          elementTypes: ['String', 'Null'],
        );

        expect(field.elementTypes, isNotNull);
        expect(field.elementTypes!.contains('String'), isTrue);
      });

      test('应支持 JSON 序列化和反序列化', () {
        final original = BsonField(
          name: 'address',
          bsonType: 'Document',
          occurrence: 0.95,
          isNullable: true,
          subFields: [
            BsonField(name: 'city', bsonType: 'String'),
            BsonField(name: 'zip', bsonType: 'String'),
          ],
        );

        final json = original.toJson();
        final restored = BsonField.fromJson(json);

        expect(restored.name, equals(original.name));
        expect(restored.bsonType, equals(original.bsonType));
        expect(restored.occurrence, equals(original.occurrence));
        expect(restored.subFields!.length, equals(2));
      });

      test('应正确计算字段出现率', () {
        final field = BsonField(
          name: 'optional_field',
          bsonType: 'String',
          occurrence: 0.5,
        );

        expect(field.occurrencePercentage, equals(50));
      });
    });
  });
}
