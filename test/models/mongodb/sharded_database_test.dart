import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb/sharding_status.dart';

void main() {
  group('ShardedDatabase', () {
    test('should create instance with all required fields', () {
      final db = ShardedDatabase(
        databaseName: 'test_db',
        primaryShard: 'shard01',
      );

      expect(db.databaseName, equals('test_db'));
      expect(db.primaryShard, equals('shard01'));
      expect(db.partitioned, isFalse);
    });

    test('should handle partitioned database', () {
      final partitionedDb = ShardedDatabase(
        databaseName: 'sales_db',
        primaryShard: 'shard01',
        partitioned: true,
        collectionsCount: 12,
      );

      expect(partitionedDb.partitioned, isTrue);
      expect(partitionedDb.collectionsCount, equals(12));
    });

    test('should serialize to JSON', () {
      final db = ShardedDatabase(
        databaseName: 'test_db',
        primaryShard: 'shard01',
        partitioned: true,
        collectionsCount: 8,
      );

      final json = db.toJson();
      expect(json['databaseName'], equals('test_db'));
      expect(json['primaryShard'], equals('shard01'));
      expect(json['partitioned'], isTrue);
      expect(json['collectionsCount'], equals(8));
    });

    test('should deserialize from JSON', () {
      final json = {
        'databaseName': 'users_db',
        'primaryShard': 'shard02',
        'partitioned': true,
        'collectionsCount': 15,
      };

      final parsed = ShardedDatabase.fromJson(json);
      expect(parsed.databaseName, equals('users_db'));
      expect(parsed.primaryShard, equals('shard02'));
      expect(parsed.partitioned, isTrue);
      expect(parsed.collectionsCount, equals(15));
    });

    test('should handle null collectionsCount', () {
      final db = ShardedDatabase(
        databaseName: 'test_db',
        primaryShard: 'shard01',
        partitioned: true,
      );

      expect(db.collectionsCount, isNull);
      expect(db.partitioned, isTrue);
    });

    test('should handle non-partitioned database', () {
      final nonPartitionedDb = ShardedDatabase(
        databaseName: 'config_db',
        primaryShard: 'shard01',
        partitioned: false,
      );

      expect(nonPartitionedDb.partitioned, isFalse);
    });
  });

  group('ShardedDatabase Edge Cases', () {
    test('should handle database with no collections', () {
      final emptyDb = ShardedDatabase(
        databaseName: 'new_db',
        primaryShard: 'shard01',
        partitioned: true,
        collectionsCount: 0,
      );

      expect(emptyDb.collectionsCount, equals(0));
    });

    test('should handle database with many collections', () {
      final largeDb = ShardedDatabase(
        databaseName: 'big_db',
        primaryShard: 'shard01',
        partitioned: true,
        collectionsCount: 1000,
      );

      expect(largeDb.collectionsCount, equals(1000));
    });

    test('should handle different primary shards', () {
      final db1 = ShardedDatabase(
        databaseName: 'db1',
        primaryShard: 'shard01',
      );

      final db2 = ShardedDatabase(
        databaseName: 'db2',
        primaryShard: 'shard02',
      );

      expect(db1.primaryShard, equals('shard01'));
      expect(db2.primaryShard, equals('shard02'));
    });
  });
}
