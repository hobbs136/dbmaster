// Regression test for DatabaseConnection.fromDbServer (spec 044, PD-2 / T002).
//
// Verifies server.extra survives the DbServer -> DatabaseConnection mapping
// (previously dropped — a silent data-loss bug for ALL extra-based settings,
// not just Mongo), the 4 canonical keys remain present/authoritative, and the
// behavior holds across all 8 database types. Pure unit test: model classes
// only, no platform channels, no providers, no DB.
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DbServer mkServer({
    DatabaseType type = DatabaseType.mongodb,
    Map<String, dynamic>? extra,
    bool useSSL = false,
  }) =>
      DbServer(
        id: 's1',
        name: 'test',
        type: type,
        host: '127.0.0.1',
        port: 27017,
        username: 'admin',
        extra: extra,
        useSSL: useSSL,
      );

  group('DatabaseConnection.fromDbServer extra mapping (PD-2 / T002)', () {
    test('preserves server.extra keys (e.g. Mongo cluster settings)', () {
      final server = mkServer(extra: {
        'mongoConnectionMode': 'replicaSet',
        'mongoHosts': ['192.0.2.128:27018', '192.0.2.128:27019'],
        'mongoReplicaSet': 'rs0',
      });
      final conn = DatabaseConnection.fromDbServer(server);

      expect(conn.extra, isNotNull);
      expect(conn.extra!['mongoConnectionMode'], 'replicaSet');
      expect(conn.extra!['mongoHosts'],
          ['192.0.2.128:27018', '192.0.2.128:27019']);
      expect(conn.extra!['mongoReplicaSet'], 'rs0');
    });

    test('includes the 4 canonical keys', () {
      final conn = DatabaseConnection.fromDbServer(mkServer(useSSL: true));

      expect(conn.extra, isNotNull);
      expect(conn.extra!['useSSL'], true);
      expect(conn.extra!['timeout'], 30); // default timeoutSeconds
      expect(conn.extra!['charset'], 'utf8mb4'); // default
      expect(conn.extra!.containsKey('timezone'), true);
    });

    test('canonical keys override colliding server.extra keys (typed wins)', () {
      // The typed DbServer field is authoritative: it is written AFTER the
      // spread, so a stale server.extra['useSSL'] cannot shadow it.
      final server = mkServer(useSSL: true, extra: {'useSSL': false});
      final conn = DatabaseConnection.fromDbServer(server);

      expect(conn.extra!['useSSL'], true);
    });

    test('handles null extra (backward-compat: only canonical keys, no crash)', () {
      final conn = DatabaseConnection.fromDbServer(mkServer(extra: null));

      expect(conn.extra, isNotNull);
      expect(conn.extra!['useSSL'], false);
      expect(conn.extra!['timeout'], 30);
      expect(conn.extra!.length, 6); // 4 canonical keys + 网关 TLS 两键
    });

    test('preserves extra for all 8 database types', () {
      for (final type in DatabaseType.values) {
        final server = mkServer(type: type, extra: {'kind': type.name});
        final conn = DatabaseConnection.fromDbServer(server);

        expect(conn.extra!['kind'], type.name, reason: 'extra lost for $type');
        expect(conn.type, type);
      }
    });
  });

  // 网关 TLS 透传 + server 侧 SSH 隧道 wire 投影（Redis/Mongo/TD 网关
  // TLS；SSH 对象适用于全部网关连接类型）。
  group('fromDbServer gateway wire projections (ssh / tls)', () {
    test('useTls/tlsInsecure are projected into extra', () {
      final conn = DatabaseConnection.fromDbServer(DbServer(
        id: 's1',
        name: 'redis-tls',
        type: DatabaseType.redis,
        host: '127.0.0.1',
        port: 6379,
        useTls: true,
        tlsInsecure: true,
      ));

      expect(conn.extra!['useTls'], true);
      expect(conn.extra!['tlsInsecure'], true);
      expect(gatewayTlsWire(conn.extra),
          {'useTls': true, 'tlsInsecure': true});
    });

    test('gatewayTlsWire is empty when useTls is off (no wire keys)', () {
      final conn = DatabaseConnection.fromDbServer(mkServer());
      expect(conn.extra!['useTls'], false);
      expect(gatewayTlsWire(conn.extra), isEmpty);
    });

    test('ssh wire object is built when tunnel enabled (password auth)', () {
      final conn = DatabaseConnection.fromDbServer(DbServer(
        id: 's2',
        name: 'mysql-ssh',
        type: DatabaseType.mysql,
        host: '10.0.0.5',
        port: 3306,
        useSshTunnel: true,
        sshHost: 'jump.example.com',
        sshPort: 2222,
        sshUsername: 'deploy',
        sshAuthMode: SshAuthMode.password,
        sshPassword: 'hunter2',
      ));

      final wire = gatewaySshWire(conn);
      expect(wire, isNotNull);
      expect(wire!['host'], 'jump.example.com');
      expect(wire['port'], 2222);
      expect(wire['username'], 'deploy');
      expect(wire['authMode'], 'password');
      expect(wire['password'], 'hunter2');
      expect(wire.containsKey('privateKey'), isFalse);
      expect(wire.containsKey('passphrase'), isFalse);
    });

    test('ssh wire object carries key + passphrase (privateKey auth)', () {
      final conn = DatabaseConnection.fromDbServer(DbServer(
        id: 's3',
        name: 'pg-ssh',
        type: DatabaseType.postgresql,
        host: '10.0.0.6',
        port: 5432,
        useSshTunnel: true,
        sshHost: 'jump.example.com',
        sshUsername: 'deploy',
        sshAuthMode: SshAuthMode.privateKey,
        sshPrivateKey: '-----BEGIN OPENSSH PRIVATE KEY-----',
        sshPassphrase: 'secret',
      ));

      final wire = gatewaySshWire(conn);
      expect(wire!['authMode'], 'privateKey');
      expect(wire['privateKey'], '-----BEGIN OPENSSH PRIVATE KEY-----');
      expect(wire['passphrase'], 'secret');
      expect(wire.containsKey('password'), isFalse);
    });

    test('no ssh wire when tunnel disabled or host empty', () {
      final off = DatabaseConnection.fromDbServer(mkServer());
      expect(gatewaySshWire(off), isNull);

      final noHost = DatabaseConnection.fromDbServer(DbServer(
        id: 's4',
        name: 'no-host',
        type: DatabaseType.mysql,
        host: '10.0.0.5',
        port: 3306,
        useSshTunnel: true,
      ));
      expect(gatewaySshWire(noHost), isNull);
    });
  });

  group('isServerSideExecutedType', () {
    test('sqlite is the only locally-executed type', () {
      expect(isServerSideExecutedType(DatabaseType.sqlite), isFalse);
      for (final type in DatabaseType.values) {
        if (type == DatabaseType.sqlite) continue;
        expect(isServerSideExecutedType(type), isTrue,
            reason: '$type should be server-side executed');
      }
    });
  });
}
