import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb/sharding_status.dart';

void main() {
  group('ShardInfo', () {
    test('should create instance with all required fields', () {
      final shard = ShardInfo(
        shardName: 'shard01',
        shardHost: 'rs_shard01/mongo1:27018,mongo2:27018',
      );

      expect(shard.shardName, equals('shard01'));
      expect(shard.shardHost, equals('rs_shard01/mongo1:27018,mongo2:27018'));
      expect(shard.isDraining, isFalse);
    });

    test('should handle draining shard', () {
      final drainingShard = ShardInfo(
        shardName: 'shard01',
        shardHost: 'rs_shard01/mongo1:27018',
        isDraining: true,
      );

      expect(drainingShard.isDraining, isTrue);
    });

    test('should serialize to JSON', () {
      final shard = ShardInfo(
        shardName: 'shard01',
        shardHost: 'rs_shard01/mongo1:27018',
        shardState: 0,
        isDraining: false,
      );

      final json = shard.toJson();
      expect(json['shardName'], equals('shard01'));
      expect(json['shardHost'], equals('rs_shard01/mongo1:27018'));
      expect(json['shardState'], equals(0));
      expect(json['isDraining'], isFalse);
    });

    test('should deserialize from JSON', () {
      final json = {
        'shardName': 'shard01',
        'shardHost': 'rs_shard01/mongo1:27018',
        'shardState': 0,
        'isDraining': true,
      };

      final parsed = ShardInfo.fromJson(json);
      expect(parsed.shardName, equals('shard01'));
      expect(parsed.shardHost, equals('rs_shard01/mongo1:27018'));
      expect(parsed.shardState, equals(0));
      expect(parsed.isDraining, isTrue);
    });

    test('should handle null shardState', () {
      final shard = ShardInfo(
        shardName: 'shard01',
        shardHost: 'rs_shard01/mongo1:27018',
      );

      expect(shard.shardState, isNull);
    });

    test('should handle different shard states', () {
      final onlineShard = ShardInfo(
        shardName: 'shard01',
        shardHost: 'rs_shard01/mongo1:27018',
        shardState: 0,
      );

      final offlineShard = ShardInfo(
        shardName: 'shard02',
        shardHost: 'rs_shard02/mongo2:27018',
        shardState: 1,
      );

      expect(onlineShard.shardState, equals(0));
      expect(offlineShard.shardState, equals(1));
    });
  });

  group('ShardInfo Edge Cases', () {
    test('should handle replica set host format', () {
      final rsShard = ShardInfo(
        shardName: 'shard01',
        shardHost: 'rs_shard01/host1:27018,host2:27018,host3:27018',
      );

      expect(rsShard.shardHost.contains(','), isTrue);
    });

    test('should handle single host format', () {
      final singleShard = ShardInfo(
        shardName: 'shard01',
        shardHost: 'mongo1:27018',
      );

      expect(singleShard.shardHost.contains(','), isFalse);
    });
  });
}
