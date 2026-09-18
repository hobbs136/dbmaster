// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'replica_set_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReplicaSetMember _$ReplicaSetMemberFromJson(Map<String, dynamic> json) =>
    ReplicaSetMember(
      name: json['name'] as String,
      state: json['state'] as String,
      stateInt: (json['stateInt'] as num).toInt(),
      uptimeSeconds: (json['uptimeSeconds'] as num?)?.toInt(),
      optimeDate: json['optimeDate'] == null
          ? null
          : DateTime.parse(json['optimeDate'] as String),
      lastHeartbeat: json['lastHeartbeat'] == null
          ? null
          : DateTime.parse(json['lastHeartbeat'] as String),
      replicationLagSeconds: (json['replicationLagSeconds'] as num?)
          ?.toDouble(),
      pingMs: (json['pingMs'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$ReplicaSetMemberToJson(ReplicaSetMember instance) =>
    <String, dynamic>{
      'name': instance.name,
      'state': instance.state,
      'stateInt': instance.stateInt,
      'uptimeSeconds': instance.uptimeSeconds,
      'optimeDate': instance.optimeDate?.toIso8601String(),
      'lastHeartbeat': instance.lastHeartbeat?.toIso8601String(),
      'replicationLagSeconds': instance.replicationLagSeconds,
      'pingMs': instance.pingMs,
    };

ReplicaSetStatus _$ReplicaSetStatusFromJson(Map<String, dynamic> json) =>
    ReplicaSetStatus(
      setName: json['setName'] as String,
      role: $enumDecode(_$ReplicaSetRoleEnumMap, json['role']),
      members: (json['members'] as List<dynamic>)
          .map((e) => ReplicaSetMember.fromJson(e as Map<String, dynamic>))
          .toList(),
      primaryMember: json['primaryMember'] == null
          ? null
          : ReplicaSetMember.fromJson(
              json['primaryMember'] as Map<String, dynamic>,
            ),
      myState: (json['myState'] as num).toInt(),
      healthStatus: $enumDecode(_$HealthStatusEnumMap, json['healthStatus']),
    );

Map<String, dynamic> _$ReplicaSetStatusToJson(ReplicaSetStatus instance) =>
    <String, dynamic>{
      'setName': instance.setName,
      'role': _$ReplicaSetRoleEnumMap[instance.role]!,
      'members': instance.members,
      'primaryMember': instance.primaryMember,
      'myState': instance.myState,
      'healthStatus': _$HealthStatusEnumMap[instance.healthStatus]!,
    };

const _$ReplicaSetRoleEnumMap = {
  ReplicaSetRole.primary: 'PRIMARY',
  ReplicaSetRole.secondary: 'SECONDARY',
  ReplicaSetRole.arbiter: 'ARBITER',
  ReplicaSetRole.hidden: 'HIDDEN',
  ReplicaSetRole.delayed: 'DELAYED',
  ReplicaSetRole.recovering: 'RECOVERING',
  ReplicaSetRole.startup: 'STARTUP',
  ReplicaSetRole.unknown: 'UNKNOWN',
  ReplicaSetRole.standalone: 'STANDALONE',
};

const _$HealthStatusEnumMap = {
  HealthStatus.healthy: 'healthy',
  HealthStatus.degraded: 'degraded',
  HealthStatus.unhealthy: 'unhealthy',
};
