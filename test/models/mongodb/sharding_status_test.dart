import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb/sharding_status.dart';

void main() {
  group('ShardingStatus', () {
    test('should create instance with all required fields', () {
      final status = ShardingStatus(
        shards: [],
        shardedDatabases: [],
        isShardedCluster: false,
        balancerEnabled: false,
      );

      expect(status.shards.isEmpty, isTrue);
      expect(status.shardedDatabases.isEmpty, isTrue);
      expect(status.isShardedCluster, isFalse);
      expect(status.balancerEnabled, isFalse);
    });

    test('should handle standalone instance', () {
      final standaloneStatus = ShardingStatus.standalone();

      expect(standaloneStatus.isShardedCluster, isFalse);
      expect(standaloneStatus.shards.isEmpty, isTrue);
      expect(standaloneStatus.shardedDatabases.isEmpty, isTrue);
    });

    test('should serialize to JSON', () {
      final status = ShardingStatus(
        shards: [
          ShardInfo(
            shardName: 'shard01',
            shardHost: 'rs_shard01/mongo1:27018',
          ),
        ],
        shardedDatabases: [
          ShardedDatabase(
            databaseName: 'test_db',
            primaryShard: 'shard01',
          ),
        ],
        isShardedCluster: true,
        balancerEnabled: true,
        chunksTotal: 1500,
      );

      final json = status.toJson();
      expect(json['isShardedCluster'], isTrue);
      expect(json['balancerEnabled'], isTrue);
      expect(json['chunksTotal'], equals(1500));
      expect(json['shards'], isList);
      expect(json['shardedDatabases'], isList);
    });

    test('should deserialize from JSON', () {
      final json = {
        'shards': [
          {
            'shardName': 'shard01',
            'shardHost': 'rs_shard01/mongo1:27018',
            'isDraining': false,
          },
        ],
        'shardedDatabases': [
          {
            'databaseName': 'test_db',
            'primaryShard': 'shard01',
            'partitioned': true,
            'collectionsCount': 12,
          },
        ],
        'isShardedCluster': true,
        'balancerEnabled': true,
        'chunksTotal': 1500,
      };

      final parsed = ShardingStatus.fromJson(json);
      expect(parsed.isShardedCluster, isTrue);
      expect(parsed.balancerEnabled, isTrue);
      expect(parsed.chunksTotal, equals(1500));
      expect(parsed.shards.length, equals(1));
      expect(parsed.shardedDatabases.length, equals(1));
    });

    test('should handle null chunksTotal', () {
      final status = ShardingStatus(
        shards: [],
        shardedDatabases: [],
        isShardedCluster: true,
        balancerEnabled: false,
        chunksTotal: null,
      );

      expect(status.chunksTotal, isNull);
    });

    test('should handle balancer disabled', () {
      final status = ShardingStatus(
        shards: [],
        shardedDatabases: [],
        isShardedCluster: true,
        balancerEnabled: false,
      );

      expect(status.balancerEnabled, isFalse);
    });
  });

  group('ShardingStatus Edge Cases', () {
    test('should handle empty shards list', () {
      final status = ShardingStatus(
        shards: [],
        shardedDatabases: [],
        isShardedCluster: true,
        balancerEnabled: true,
      );

      expect(status.shards.isEmpty, isTrue);
      expect(status.isShardedCluster, isTrue);
    });

    test('should handle multiple shards', () {
      final status = ShardingStatus(
        shards: [
          ShardInfo(
            shardName: 'shard01',
            shardHost: 'rs_shard01/mongo1:27018',
          ),
          ShardInfo(
            shardName: 'shard02',
            shardHost: 'rs_shard02/mongo2:27018',
          ),
          ShardInfo(
            shardName: 'shard03',
            shardHost: 'rs_shard03/mongo3:27018',
          ),
        ],
        shardedDatabases: [],
        isShardedCluster: true,
        balancerEnabled: true,
      );

      expect(status.shards.length, equals(3));
    });
  });
}
