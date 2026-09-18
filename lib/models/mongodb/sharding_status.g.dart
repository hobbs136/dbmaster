// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sharding_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ShardInfo _$ShardInfoFromJson(Map<String, dynamic> json) => ShardInfo(
  shardName: json['shardName'] as String,
  shardHost: json['shardHost'] as String,
  shardState: (json['shardState'] as num?)?.toInt(),
  isDraining: json['isDraining'] as bool? ?? false,
);

Map<String, dynamic> _$ShardInfoToJson(ShardInfo instance) => <String, dynamic>{
  'shardName': instance.shardName,
  'shardHost': instance.shardHost,
  'shardState': instance.shardState,
  'isDraining': instance.isDraining,
};

ShardedDatabase _$ShardedDatabaseFromJson(Map<String, dynamic> json) =>
    ShardedDatabase(
      databaseName: json['databaseName'] as String,
      primaryShard: json['primaryShard'] as String,
      partitioned: json['partitioned'] as bool? ?? false,
      collectionsCount: (json['collectionsCount'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ShardedDatabaseToJson(ShardedDatabase instance) =>
    <String, dynamic>{
      'databaseName': instance.databaseName,
      'primaryShard': instance.primaryShard,
      'partitioned': instance.partitioned,
      'collectionsCount': instance.collectionsCount,
    };

ShardingStatus _$ShardingStatusFromJson(Map<String, dynamic> json) =>
    ShardingStatus(
      shards: (json['shards'] as List<dynamic>)
          .map((e) => ShardInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      shardedDatabases: (json['shardedDatabases'] as List<dynamic>)
          .map((e) => ShardedDatabase.fromJson(e as Map<String, dynamic>))
          .toList(),
      isShardedCluster: json['isShardedCluster'] as bool? ?? false,
      balancerEnabled: json['balancerEnabled'] as bool? ?? false,
      chunksTotal: (json['chunksTotal'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ShardingStatusToJson(ShardingStatus instance) =>
    <String, dynamic>{
      'shards': instance.shards,
      'shardedDatabases': instance.shardedDatabases,
      'isShardedCluster': instance.isShardedCluster,
      'balancerEnabled': instance.balancerEnabled,
      'chunksTotal': instance.chunksTotal,
    };
