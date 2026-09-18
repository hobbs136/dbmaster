import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/mongodb/replica_set_status.dart';

void main() {
  group('ReplicaSetMember', () {
    late ReplicaSetMember member;

    setUp(() {
      member = ReplicaSetMember(
        name: 'mongo1:27017',
        state: 'PRIMARY',
        stateInt: 1,
        uptimeSeconds: 86400,
        optimeDate: DateTime.parse('2026-07-14T10:30:00Z'),
        lastHeartbeat: DateTime.parse('2026-07-14T10:30:05Z'),
        replicationLagSeconds: 0.0,
        pingMs: 0.5,
      );
    });

    test('should create instance with all required fields', () {
      expect(member.name, equals('mongo1:27017'));
      expect(member.state, equals('PRIMARY'));
      expect(member.stateInt, equals(1));
      expect(member.uptimeSeconds, equals(86400));
      expect(member.replicationLagSeconds, equals(0.0));
      expect(member.pingMs, equals(0.5));
    });

    test('should handle null optional fields', () {
      final minimalMember = ReplicaSetMember(
        name: 'mongo2:27017',
        state: 'SECONDARY',
        stateInt: 2,
      );

      expect(minimalMember.name, equals('mongo2:27017'));
      expect(minimalMember.uptimeSeconds, isNull);
      expect(minimalMember.optimeDate, isNull);
      expect(minimalMember.lastHeartbeat, isNull);
      expect(minimalMember.replicationLagSeconds, isNull);
      expect(minimalMember.pingMs, isNull);
    });

    test('should serialize to JSON', () {
      final json = member.toJson();
      expect(json['name'], equals('mongo1:27017'));
      expect(json['state'], equals('PRIMARY'));
      expect(json['stateInt'], equals(1));
      expect(json['uptimeSeconds'], equals(86400));
      expect(json['pingMs'], equals(0.5));
    });

    test('should deserialize from JSON', () {
      final json = {
        'name': 'mongo1:27017',
        'state': 'PRIMARY',
        'stateInt': 1,
        'uptimeSeconds': 86400,
        'optimeDate': '2026-07-14T10:30:00Z',
        'lastHeartbeat': '2026-07-14T10:30:05Z',
        'replicationLagSeconds': 0.0,
        'pingMs': 0.5,
      };

      final parsed = ReplicaSetMember.fromJson(json);
      expect(parsed.name, equals('mongo1:27017'));
      expect(parsed.state, equals('PRIMARY'));
      expect(parsed.stateInt, equals(1));
      expect(parsed.uptimeSeconds, equals(86400));
      expect(parsed.pingMs, equals(0.5));
    });

    test('should calculate replication lag correctly for secondary', () {
      final secondary = ReplicaSetMember(
        name: 'mongo2:27017',
        state: 'SECONDARY',
        stateInt: 2,
        optimeDate: DateTime.parse('2026-07-14T10:29:55Z'),
        replicationLagSeconds: 5.2,
        pingMs: 0.7,
      );

      expect(secondary.replicationLagSeconds, equals(5.2));
      expect(secondary.replicationLagSeconds! >= 0, isTrue);
    });

    test('should have null lag for primary', () {
      final primary = ReplicaSetMember(
        name: 'mongo1:27017',
        state: 'PRIMARY',
        stateInt: 1,
        replicationLagSeconds: null,
      );

      expect(primary.replicationLagSeconds, isNull);
    });
  });

  group('ReplicaSetMember Validation', () {
    test('should require non-empty name', () {
      expect(
        () => ReplicaSetMember(
          name: '',
          state: 'PRIMARY',
          stateInt: 1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should require non-negative replication lag', () {
      expect(
        () => ReplicaSetMember(
          name: 'mongo1:27017',
          state: 'PRIMARY',
          stateInt: 1,
          replicationLagSeconds: -1.0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should require non-negative ping', () {
      expect(
        () => ReplicaSetMember(
          name: 'mongo1:27017',
          state: 'PRIMARY',
          stateInt: 1,
          pingMs: -0.5,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ReplicaSetMember State Transitions', () {
    test('should handle all member states', () {
      final states = [
        'PRIMARY',
        'SECONDARY',
        'ARBITER',
        'HIDDEN',
        'DELAYED',
        'RECOVERING',
        'STARTUP',
        'UNKNOWN',
      ];

      for (final state in states) {
        final member = ReplicaSetMember(
          name: 'mongo:27017',
          state: state,
          stateInt: 1,
        );
        expect(member.state, equals(state));
      }
    });
  });

  group('ReplicaSetMember Null Safety', () {
    test('should safely handle nullable DateTime fields', () {
      final member = ReplicaSetMember(
        name: 'mongo:27017',
        state: 'STARTUP2',
        stateInt: 5,
      );

      expect(member.optimeDate, isNull);
      expect(member.lastHeartbeat, isNull);

      // Should not throw when accessing nullable fields
      expect(() => member.optimeDate?.toIso8601String(), returnsNormally);
      expect(() => member.lastHeartbeat?.toIso8601String(), returnsNormally);
    });

    test('should safely handle nullable numeric fields', () {
      final member = ReplicaSetMember(
        name: 'mongo:27017',
        state: 'STARTUP2',
        stateInt: 5,
      );

      expect(member.replicationLagSeconds, isNull);
      expect(member.pingMs, isNull);

      // Should not throw when accessing nullable fields
      expect(() => member.replicationLagSeconds?.toString(), returnsNormally);
      expect(() => member.pingMs?.toString(), returnsNormally);
    });
  });
}
