import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/foundation.dart';

part 'replica_set_status.g.dart';

/// Replica set member role
enum ReplicaSetRole {
  @JsonValue('PRIMARY')
  primary,
  @JsonValue('SECONDARY')
  secondary,
  @JsonValue('ARBITER')
  arbiter,
  @JsonValue('HIDDEN')
  hidden,
  @JsonValue('DELAYED')
  delayed,
  @JsonValue('RECOVERING')
  recovering,
  @JsonValue('STARTUP')
  startup,
  @JsonValue('UNKNOWN')
  unknown,
  @JsonValue('STANDALONE')
  standalone,
}

/// Overall replica set health status
enum HealthStatus {
  @JsonValue('healthy')
  healthy,
  @JsonValue('degraded')
  degraded,
  @JsonValue('unhealthy')
  unhealthy,
}

/// Represents a single member in a MongoDB replica set
@immutable
@JsonSerializable()
class ReplicaSetMember {
  /// Member host:port identifier
  final String name;

  /// State string (PRIMARY, SECONDARY, ARBITER, etc.)
  final String state;

  /// Numeric state code (1=PRIMARY, 2=SECONDARY, etc.)
  final int stateInt;

  /// How long this member has been up (seconds)
  final int? uptimeSeconds;

  /// Last operation time
  final DateTime? optimeDate;

  /// Last heartbeat received
  final DateTime? lastHeartbeat;

  /// Lag behind primary in seconds (null for primary)
  final double? replicationLagSeconds;

  /// Round-trip ping time in milliseconds
  final double? pingMs;

  ReplicaSetMember({
    required this.name,
    required this.state,
    required this.stateInt,
    this.uptimeSeconds,
    this.optimeDate,
    this.lastHeartbeat,
    this.replicationLagSeconds,
    this.pingMs,
  })  : assert(name.isNotEmpty, 'Member name must not be empty'),
        assert(
          replicationLagSeconds == null || replicationLagSeconds >= 0,
          'Replication lag must be non-negative',
        ),
        assert(
          pingMs == null || pingMs >= 0,
          'Ping time must be non-negative',
        );

  factory ReplicaSetMember.fromJson(Map<String, dynamic> json) =>
      _$ReplicaSetMemberFromJson(json);

  Map<String, dynamic> toJson() => _$ReplicaSetMemberToJson(this);
}

/// Represents MongoDB replica set status
@immutable
@JsonSerializable()
class ReplicaSetStatus {
  /// Replica set name
  final String setName;

  /// Current node's role
  final ReplicaSetRole role;

  /// All members in the replica set
  final List<ReplicaSetMember> members;

  /// The current primary member (null if no primary)
  final ReplicaSetMember? primaryMember;

  /// Raw state code from replSetGetStatus
  final int myState;

  /// Overall cluster health
  final HealthStatus healthStatus;

  ReplicaSetStatus({
    required this.setName,
    required this.role,
    required this.members,
    this.primaryMember,
    required this.myState,
    required this.healthStatus,
  });

  factory ReplicaSetStatus.fromJson(Map<String, dynamic> json) =>
      _$ReplicaSetStatusFromJson(json);

  Map<String, dynamic> toJson() => _$ReplicaSetStatusToJson(this);
}
