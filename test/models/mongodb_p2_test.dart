import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb_models.dart';

/// P2 高级功能和性能优化测试
void main() {
  group('GridFS 支持', () {
    test('CollectionInfo 应支持 GridFS 标识', () {
      final gridfsFiles = CollectionInfo(
        name: 'uploads.files',
        type: 'collection',
      );

      expect(gridfsFiles.isGridFS, isTrue);
      expect(gridfsFiles.gridfsBucket, equals('uploads'));
    });

    test('CollectionInfo 应识别 .chunks 后缀为 GridFS', () {
      final chunks = CollectionInfo(name: 'photos.chunks', type: 'collection');
      expect(chunks.isGridFS, isTrue);
      expect(chunks.gridfsBucket, equals('photos'));
    });
  });

  group('嵌套 Document 递归展开', () {
    test('BsonField 应支持多级嵌套', () {
      final root = BsonField(
        name: 'user',
        bsonType: 'Document',
        subFields: [
          BsonField(
            name: 'profile',
            bsonType: 'Document',
            subFields: [
              BsonField(name: 'avatar', bsonType: 'String'),
              BsonField(
                name: 'settings',
                bsonType: 'Document',
                subFields: [
                  BsonField(name: 'theme', bsonType: 'String'),
                  BsonField(name: 'notifications', bsonType: 'Boolean'),
                ],
              ),
            ],
          ),
        ],
      );

      expect(root.subFields!.length, equals(1));
      expect(root.subFields![0].subFields!.length, equals(2));
      expect(root.subFields![0].subFields![1].subFields!.length, equals(2));
    });
  });

  group('视图和时序集合标识', () {
    test('CollectionInfo 应标识时序集合', () {
      final ts = CollectionInfo(
        name: 'sensor_data',
        type: 'collection',
        isTimeSeries: true,
      );

      expect(ts.isTimeSeries, isTrue);
      expect(ts.typeIcon, equals('⏱️'));
    });

    test('CollectionInfo 应标识 Capped 集合', () {
      final capped = CollectionInfo(
        name: 'logs',
        type: 'collection',
        isCapped: true,
      );

      expect(capped.typeIcon, equals('🔄'));
    });
  });

  group('性能优化 - CollectionInfo', () {
    test('应支持格式化文档数量（大数字）', () {
      final info = CollectionInfo(name: 'users', documentCount: 1200000);
      expect(info.formattedDocumentCount, equals('1.2M'));
    });

    test('应支持格式化存储大小', () {
      final info = CollectionInfo(name: 'files', storageSize: 2345678901);
      expect(info.formattedSize, equals('2.2 GB'));
    });
  });
}
