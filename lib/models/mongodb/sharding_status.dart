import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/foundation.dart';

part 'sharding_status.g.dart';

/// Represents a single shard in a MongoDB sharded cluster
@immutable
@JsonSerializable()
class ShardInfo {
  /// Shard identifier
  final String shardName;

  /// Shard host:port or replica set name
  final String shardHost;

  /// Shard state (0=online, 1=offline, etc.)
  final int? shardState;

  /// Whether this shard is being removed
  final bool isDraining;

  ShardInfo({
    required this.shardName,
    required this.shardHost,
    this.shardState,
    this.isDraining = false,
  });

  factory ShardInfo.fromJson(Map<String, dynamic> json) =>
      _$ShardInfoFromJson(json);

  Map<String, dynamic> toJson() => _$ShardInfoToJson(this);
}

/// Represents a sharded database
@immutable
@JsonSerializable()
class ShardedDatabase {
  /// Database name
  final String databaseName;

  /// Primary shard for this database
  final String primaryShard;

  /// Whether collections are partitioned
  final bool partitioned;

  /// Number of sharded collections
  final int? collectionsCount;

  ShardedDatabase({
    required this.databaseName,
    required this.primaryShard,
    this.partitioned = false,
    this.collectionsCount,
  });

  factory ShardedDatabase.fromJson(Map<String, dynamic> json) =>
      _$ShardedDatabaseFromJson(json);

  Map<String, dynamic> toJson() => _$ShardedDatabaseToJson(this);
}

/// Represents MongoDB sharding cluster status
@immutable
@JsonSerializable()
class ShardingStatus {
  /// All shards in the cluster
  final List<ShardInfo> shards;

  /// Databases with sharding enabled
  final List<ShardedDatabase> shardedDatabases;

  /// True if this is a sharded cluster
  final bool isShardedCluster;

  /// Whether the balancer is running
  final bool balancerEnabled;

  /// Total chunk count across all shards
  final int? chunksTotal;

  ShardingStatus({
    required this.shards,
    required this.shardedDatabases,
    this.isShardedCluster = false,
    this.balancerEnabled = false,
    this.chunksTotal,
  });

  factory ShardingStatus.fromJson(Map<String, dynamic> json) =>
      _$ShardingStatusFromJson(json);

  Map<String, dynamic> toJson() => _$ShardingStatusToJson(this);

  /// Create a standalone (non-sharded) status
  factory ShardingStatus.standalone() {
    return ShardingStatus(
      shards: [],
      shardedDatabases: [],
      isShardedCluster: false,
      balancerEnabled: false,
    );
  }
}
