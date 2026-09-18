import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/ssh_tunnel_service.dart';

void main() {
  group('SshTunnelService', () {
    late SshTunnelService tunnelService;

    setUp(() {
      tunnelService = SshTunnelService();
    });

    tearDown(() async {
      await tunnelService.disconnect();
    });

    group('Configuration Validation', () {
      test('should throw when SSH host is missing', () async {
        final server = DbServer(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
          useSshTunnel: true,
          sshUsername: 'user',
        );

        expect(
          () => tunnelService.connect(
            server: server,
            targetHost: 'localhost',
            targetPort: 3306,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('SSH host is required'),
            ),
          ),
        );
      });

      test('should throw when SSH username is missing', () async {
        final server = DbServer(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
          useSshTunnel: true,
          sshHost: 'jump.example.com',
        );

        expect(
          () => tunnelService.connect(
            server: server,
            targetHost: 'localhost',
            targetPort: 3306,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('SSH username is required'),
            ),
          ),
        );
      });

      test(
        'should throw when SSH password is missing for password auth',
        () async {
          final server = DbServer(
            id: 'test',
            name: 'Test',
            type: DatabaseType.mysql,
            host: 'localhost',
            port: 3306,
            useSshTunnel: true,
            sshHost: 'jump.example.com',
            sshUsername: 'user',
            sshAuthMode: SshAuthMode.password,
          );

          expect(
            () => tunnelService.connect(
              server: server,
              targetHost: 'localhost',
              targetPort: 3306,
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                contains('SSH password is required'),
              ),
            ),
          );
        },
      );

      test('should throw when private key is missing for key auth', () async {
        final server = DbServer(
          id: 'test',
          name: 'Test',
          type: DatabaseType.mysql,
          host: 'localhost',
          port: 3306,
          useSshTunnel: true,
          sshHost: 'jump.example.com',
          sshUsername: 'user',
          sshAuthMode: SshAuthMode.privateKey,
        );

        expect(
          () => tunnelService.connect(
            server: server,
            targetHost: 'localhost',
            targetPort: 3306,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('SSH private key is required'),
            ),
          ),
        );
      });
    });

    group('State Management', () {
      test('should not be connected initially', () {
        expect(tunnelService.isConnected, isFalse);
        expect(tunnelService.localPort, isNull);
      });

      test('should disconnect cleanly', () async {
        await tunnelService.disconnect();
        expect(tunnelService.isConnected, isFalse);
        expect(tunnelService.localPort, isNull);
      });
    });
  });

  group('SshTunnelManager', () {
    late SshTunnelManager manager;

    setUp(() {
      manager = SshTunnelManager();
    });

    tearDown(() async {
      await manager.closeAllTunnels();
    });

    test('should not have tunnels initially', () {
      expect(manager.hasTunnel('test'), isFalse);
      expect(manager.getLocalPort('test'), isNull);
    });

    test('should close all tunnels', () async {
      await manager.closeAllTunnels();
      expect(manager.hasTunnel('test'), isFalse);
    });
  });

  group('DbServer SSH Configuration', () {
    test('should serialize SSH config to JSON', () {
      final server = DbServer(
        id: 'test',
        name: 'Test Server',
        type: DatabaseType.mysql,
        host: 'db.internal',
        port: 3306,
        useSshTunnel: true,
        sshHost: 'jump.example.com',
        sshPort: 22,
        sshUsername: 'admin',
        sshAuthMode: SshAuthMode.password,
      );

      final json = server.toJson();
      expect(json['useSshTunnel'], isTrue);
      expect(json['sshHost'], equals('jump.example.com'));
      expect(json['sshPort'], equals(22));
      expect(json['sshUsername'], equals('admin'));
      expect(json['sshAuthMode'], equals('password'));
      expect(
        json.containsKey('sshPassword'),
        isFalse,
      ); // Should not serialize sensitive data
    });

    test('should deserialize SSH config from JSON', () {
      final json = {
        'id': 'test',
        'name': 'Test Server',
        'type': 'mysql',
        'host': 'db.internal',
        'port': 3306,
        'useSshTunnel': true,
        'sshHost': 'jump.example.com',
        'sshPort': 2222,
        'sshUsername': 'admin',
        'sshAuthMode': 'privateKey',
      };

      final server = DbServer.fromJson(json);
      expect(server.useSshTunnel, isTrue);
      expect(server.sshHost, equals('jump.example.com'));
      expect(server.sshPort, equals(2222));
      expect(server.sshUsername, equals('admin'));
      expect(server.sshAuthMode, equals(SshAuthMode.privateKey));
    });

    test('copyWith should update SSH fields', () {
      final server = DbServer(
        id: 'test',
        name: 'Test',
        type: DatabaseType.mysql,
        host: 'localhost',
        port: 3306,
      );

      final updated = server.copyWith(
        useSshTunnel: true,
        sshHost: 'jump.example.com',
        sshUsername: 'user',
      );

      expect(updated.useSshTunnel, isTrue);
      expect(updated.sshHost, equals('jump.example.com'));
      expect(updated.sshUsername, equals('user'));
    });
  });
}
