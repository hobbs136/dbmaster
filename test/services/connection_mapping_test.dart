// =============================================================================
// Unit tests for connection_mapping (ADR-0003 S3).
// =============================================================================
// Verifies the bidirectional DbServer ↔ server-row mapping including the
// SQL-first filtering, SQLite host↔file_path convention, enum conversions,
// extra JSON blob, SSH fields, and credential injection.
// =============================================================================

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/connection_mapping.dart';

void main() {
  group('serverDbTypeFromClient', () {
    test('maps the SQL libraries', () {
      expect(serverDbTypeFromClient(DatabaseType.mysql), 'mysql');
      expect(serverDbTypeFromClient(DatabaseType.postgresql), 'postgres');
      expect(serverDbTypeFromClient(DatabaseType.sqlite), 'sqlite');
      expect(serverDbTypeFromClient(DatabaseType.clickhouse), 'clickhouse');
    });

    test('returns null for non-SQL types (S3 stays keychain)', () {
      expect(serverDbTypeFromClient(DatabaseType.redis), isNull);
      expect(serverDbTypeFromClient(DatabaseType.mongodb), isNull);
      expect(serverDbTypeFromClient(DatabaseType.doris), isNull);
      expect(serverDbTypeFromClient(DatabaseType.tdengine), isNull);
      expect(serverDbTypeFromClient(DatabaseType.sqlserver), isNull);
    });
  });

  group('clientDbTypeFromServer', () {
    test('accepts canonical names and postgres aliases', () {
      expect(clientDbTypeFromServer('mysql'), DatabaseType.mysql);
      expect(clientDbTypeFromServer('postgres'), DatabaseType.postgresql);
      expect(clientDbTypeFromServer('postgresql'), DatabaseType.postgresql);
      expect(clientDbTypeFromServer('pg'), DatabaseType.postgresql);
      expect(clientDbTypeFromServer('sqlite'), DatabaseType.sqlite);
      expect(clientDbTypeFromServer('clickhouse'), DatabaseType.clickhouse);
    });

    test('is case-insensitive and rejects unknown', () {
      expect(clientDbTypeFromServer('MYSQL'), DatabaseType.mysql);
      expect(clientDbTypeFromServer('ClickHouse'), DatabaseType.clickhouse);
      expect(clientDbTypeFromServer('UnknownDB'), isNull);
      expect(clientDbTypeFromServer(null), isNull);
    });
  });

  group('isServerSyncable', () {
    test('true only for SQL libraries', () {
      expect(isServerSyncable(_mysql()), isTrue);
      expect(isServerSyncable(_sqlite()), isTrue);
      expect(isServerSyncable(_clickhouse()), isTrue);
      expect(isServerSyncable(_redis()), isFalse);
      expect(isServerSyncable(_mongodb()), isFalse);
    });
  });

  group('toCreateBody', () {
    test('MySQL body — full field coverage', () {
      final server = DbServer(
        id: 'c1',
        name: 'prod',
        type: DatabaseType.mysql,
        host: '10.0.0.5',
        port: 3306,
        username: 'dba',
        password: 'ignored-here',
        database: 'shop',
        useSSL: true,
        timeoutSeconds: 45,
        autoReconnect: true,
        charset: 'utf8mb4',
        timezone: 'UTC',
        groupId: 'g1',
        environment: ConnectionEnvironment.production,
        extra: {'poolSize': 10},
      );
      final body = toCreateBody(server, 'plaintext-pw');

      expect(body['db_type'], 'mysql');
      expect(body['host'], '10.0.0.5');
      expect(body['port'], 3306);
      expect(body['username'], 'dba');
      // Plaintext password is sent (server encrypts).
      expect(body['password'], 'plaintext-pw');
      expect(body['default_database'], 'shop');
      expect(body['use_ssl'], true);
      expect(body['timeout_seconds'], 45);
      expect(body['auto_reconnect'], true);
      expect(body['charset'], 'utf8mb4');
      expect(body['timezone'], 'UTC');
      expect(body['environment'], 'production');
      expect(body['group_id'], 'g1');
      // extra is JSON-encoded.
      expect(jsonDecode(body['extra'] as String), {'poolSize': 10});
      expect(body['kind'], 'collab');
      // null-valued fields are omitted (file_path, ssh_*).
      expect(body.containsKey('file_path'), isFalse);
      expect(body.containsKey('ssh_host'), isFalse);
    });

    test('SQLite body — host becomes file_path, sentinel host/port', () {
      final server = DbServer(
        id: 's1',
        name: 'local-db',
        type: DatabaseType.sqlite,
        host: '/data/my.db',
        port: 0,
      );
      final body = toCreateBody(server, '');

      expect(body['db_type'], 'sqlite');
      expect(body['host'], 'sqlite');
      expect(body['port'], 0);
      expect(body['username'], 'sqlite');
      expect(body['password'], '');
      expect(body['file_path'], '/data/my.db');
      // No default_database for SQLite.
      expect(body.containsKey('default_database'), isFalse);
    });

    test('SSH fields included when set', () {
      final server = DbServer(
        id: 'c2',
        name: 'tunneled',
        type: DatabaseType.mysql,
        host: 'db',
        port: 3306,
        username: 'u',
        useSshTunnel: true,
        sshHost: 'bastion',
        sshPort: 22,
        sshUsername: 'tunnel',
        sshAuthMode: SshAuthMode.privateKey,
        sshPrivateKey: '-----BEGIN KEY-----',
        sshPassphrase: 'phrase',
      );
      final body = toCreateBody(server, 'pw');
      expect(body['ssh_enabled'], true);
      expect(body['ssh_host'], 'bastion');
      expect(body['ssh_port'], 22);
      expect(body['ssh_username'], 'tunnel');
      expect(body['ssh_auth_mode'], 'privateKey');
      expect(body['ssh_private_key'], '-----BEGIN KEY-----');
      expect(body['ssh_passphrase'], 'phrase');
    });
  });

  group('fromServerRow', () {
    test('MySQL round-trip with credentials', () {
      final row = {
        'id': 'c1',
        'name': 'prod',
        'db_type': 'mysql',
        'host': '10.0.0.5',
        'port': 3306,
        'username': 'dba',
        'default_database': 'shop',
        'use_ssl': 1,
        'timeout_seconds': 45,
        'auto_reconnect': 1,
        'charset': 'utf8mb4',
        'timezone': 'UTC',
        'environment': 'production',
        'group_id': 'g1',
        'read_only': 0,
        'ssh_enabled': 0,
        'extra': '{"poolSize":10}',
      };
      final server = fromServerRow(row, plaintextPassword: 'secret');
      expect(server.id, 'c1');
      expect(server.type, DatabaseType.mysql);
      expect(server.host, '10.0.0.5');
      expect(server.port, 3306);
      expect(server.username, 'dba');
      expect(server.password, 'secret');
      expect(server.database, 'shop');
      expect(server.useSSL, isTrue);
      expect(server.timeoutSeconds, 45);
      expect(server.autoReconnect, isTrue);
      expect(server.charset, 'utf8mb4');
      expect(server.environment, ConnectionEnvironment.production);
      expect(server.groupId, 'g1');
      expect(server.extra, {'poolSize': 10});
    });

    test('SQLite — file_path restored into host', () {
      final row = {
        'id': 's1',
        'name': 'local',
        'db_type': 'sqlite',
        'host': 'sqlite',
        'port': 0,
        'username': 'sqlite',
        'file_path': '/data/my.db',
      };
      final server = fromServerRow(row);
      expect(server.type, DatabaseType.sqlite);
      expect(server.host, '/data/my.db'); // file path restored
      expect(server.port, 0);
      expect(server.username, isNull); // SQLite forces null
      expect(server.password, isNull);
    });

    test('SSH fields populated from SshCredentials', () {
      final row = {
        'id': 'c2',
        'name': 't',
        'db_type': 'postgres',
        'host': 'db',
        'port': 5432,
        'username': 'u',
        'ssh_enabled': 1,
        'ssh_host': 'bastion',
        'ssh_port': 22,
        'ssh_auth_mode': 'privateKey',
      };
      final server = fromServerRow(
        row,
        plaintextPassword: 'pw',
        ssh: const SshCredentials(
          username: 'tunnel',
          authMode: 'privateKey',
          privateKey: '-----BEGIN-----',
          passphrase: 'phrase',
        ),
      );
      expect(server.useSshTunnel, isTrue);
      expect(server.sshHost, 'bastion');
      expect(server.sshUsername, 'tunnel');
      expect(server.sshAuthMode, SshAuthMode.privateKey);
      expect(server.sshPrivateKey, '-----BEGIN-----');
      expect(server.sshPassphrase, 'phrase');
    });

    test('throws on unsupported db_type', () {
      expect(
        () => fromServerRow({'db_type': 'redis', 'id': 'x', 'name': 'r'}),
        throwsArgumentError,
      );
    });

    test('tolerates malformed extra JSON', () {
      final row = {
        'id': 'c1', 'name': 'n', 'db_type': 'mysql',
        'host': 'h', 'port': 3306, 'username': 'u',
        'extra': '{not valid json',
      };
      // Should not throw — extra just becomes null.
      final server = fromServerRow(row);
      expect(server.extra, isNull);
    });

    test('accepts bool true/false for integer columns (back-compat)', () {
      final row = {
        'id': 'c1', 'name': 'n', 'db_type': 'mysql',
        'host': 'h', 'port': 3306, 'username': 'u',
        'use_ssl': true, 'auto_reconnect': false, 'read_only': true,
      };
      final server = fromServerRow(row);
      expect(server.useSSL, isTrue);
      expect(server.autoReconnect, isFalse);
      expect(server.readOnly, isTrue);
    });
  });
}

DbServer _mysql() => DbServer(
      id: 'm', name: 'm', type: DatabaseType.mysql, host: 'h', port: 3306);
DbServer _sqlite() => DbServer(
      id: 's', name: 's', type: DatabaseType.sqlite, host: '/x.db', port: 0);
DbServer _redis() => DbServer(
      id: 'r', name: 'r', type: DatabaseType.redis, host: 'h', port: 6379);
DbServer _mongodb() => DbServer(
      id: 'g', name: 'g', type: DatabaseType.mongodb, host: 'h', port: 27017);
DbServer _clickhouse() => DbServer(
      id: 'ch', name: 'ch', type: DatabaseType.clickhouse, host: 'h', port: 9004);
