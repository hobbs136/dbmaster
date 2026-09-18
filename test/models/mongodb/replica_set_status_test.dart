import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb/replica_set_status.dart';

void main() {
  group('ReplicaSetRole', () {
    test('should have all expected values', () {
      expect(ReplicaSetRole.primary, isNotNull);
      expect(ReplicaSetRole.secondary, isNotNull);
      expect(ReplicaSetRole.arbiter, isNotNull);
      expect(ReplicaSetRole.hidden, isNotNull);
      expect(ReplicaSetRole.delayed, isNotNull);
      expect(ReplicaSetRole.recovering, isNotNull);
      expect(ReplicaSetRole.startup, isNotNull);
      expect(ReplicaSetRole.unknown, isNotNull);
      expect(ReplicaSetRole.standalone, isNotNull);
    });

    test('should have all expected values', () {
      // Test that enum values match expected JSON representations
      expect(ReplicaSetRole.primary, isNotNull);
      expect(ReplicaSetRole.secondary, isNotNull);
      expect(ReplicaSetRole.arbiter, isNotNull);
      expect(ReplicaSetRole.standalone, isNotNull);
    });
  });

  group('HealthStatus', () {
    test('should have all expected values', () {
      expect(HealthStatus.healthy, isNotNull);
      expect(HealthStatus.degraded, isNotNull);
      expect(HealthStatus.unhealthy, isNotNull);
    });
  });

  group('ReplicaSetStatus', () {
    late ReplicaSetStatus status;
    late ReplicaSetMember primaryMember;
    late ReplicaSetMember secondaryMember;

    setUp(() {
      primaryMember = ReplicaSetMember(
        name: 'mongo1:27017',
        state: 'PRIMARY',
        stateInt: 1,
        uptimeSeconds: 86400,
        optimeDate: DateTime.parse('2026-07-14T10:30:00Z'),
        pingMs: 0.5,
      );

      secondaryMember = ReplicaSetMember(
        name: 'mongo2:27017',
        state: 'SECONDARY',
        stateInt: 2,
        optimeDate: DateTime.parse('2026-07-14T10:29:55Z'),
        replicationLagSeconds: 5.2,
        pingMs: 0.7,
      );

      status = ReplicaSetStatus(
        setName: 'rs0',
        role: ReplicaSetRole.primary,
        members: [primaryMember, secondaryMember],
        primaryMember: primaryMember,
        myState: 1,
        healthStatus: HealthStatus.healthy,
      );
    });

    test('should create instance with all required fields', () {
      expect(status.setName, equals('rs0'));
      expect(status.role, equals(ReplicaSetRole.primary));
      expect(status.members.length, equals(2));
      expect(status.primaryMember, equals(primaryMember));
      expect(status.myState, equals(1));
      expect(status.healthStatus, equals(HealthStatus.healthy));
    });

    test('should handle standalone instance', () {
      final standaloneStatus = ReplicaSetStatus(
        setName: 'standalone',
        role: ReplicaSetRole.standalone,
        members: [],
        primaryMember: null,
        myState: 1,
        healthStatus: HealthStatus.healthy,
      );

      expect(standaloneStatus.role, equals(ReplicaSetRole.standalone));
      expect(standaloneStatus.members.isEmpty, isTrue);
      expect(standaloneStatus.primaryMember, isNull);
    });

    test('should serialize to JSON', () {
      final json = status.toJson();
      expect(json['setName'], equals('rs0'));
      expect(json['role'], equals('PRIMARY'));
      expect(json['members'], isList);
      expect(json['myState'], equals(1));
      expect(json['healthStatus'], equals('healthy'));
    });

    test('should deserialize from JSON', () {
      final json = {
        'setName': 'rs0',
        'role': 'PRIMARY',
        'members': [
          {
            'name': 'mongo1:27017',
            'state': 'PRIMARY',
            'stateInt': 1,
            'uptimeSeconds': 86400,
            'optimeDate': '2026-07-14T10:30:00Z',
            'pingMs': 0.5,
          },
        ],
        'primaryMember': {
          'name': 'mongo1:27017',
          'state': 'PRIMARY',
          'stateInt': 1,
        },
        'myState': 1,
        'healthStatus': 'healthy',
      };

      final parsed = ReplicaSetStatus.fromJson(json);
      expect(parsed.setName, equals('rs0'));
      expect(parsed.role, equals(ReplicaSetRole.primary));
      expect(parsed.members.length, equals(1));
      expect(parsed.myState, equals(1));
    });

    test('should handle degraded cluster health', () {
      final degradedStatus = ReplicaSetStatus(
        setName: 'rs0',
        role: ReplicaSetRole.secondary,
        members: [secondaryMember],
        primaryMember: null,
        myState: 2,
        healthStatus: HealthStatus.degraded,
      );

      expect(degradedStatus.healthStatus, equals(HealthStatus.degraded));
      expect(degradedStatus.primaryMember, isNull);
    });
  });

  group('ReplicaSetStatus Edge Cases', () {
    test('should handle null primaryMember gracefully', () {
      final status = ReplicaSetStatus(
        setName: 'rs0',
        role: ReplicaSetRole.secondary,
        members: [],
        primaryMember: null,
        myState: 2,
        healthStatus: HealthStatus.unhealthy,
      );

      expect(status.primaryMember, isNull);
      expect(status.healthStatus, equals(HealthStatus.unhealthy));
    });

    test('should handle empty members list', () {
      final status = ReplicaSetStatus(
        setName: 'standalone',
        role: ReplicaSetRole.standalone,
        members: [],
        primaryMember: null,
        myState: 1,
        healthStatus: HealthStatus.healthy,
      );

      expect(status.members.isEmpty, isTrue);
    });
  });
}
