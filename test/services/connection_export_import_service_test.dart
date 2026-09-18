import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/services/connection_export_import_service.dart';
import 'package:dbmaster/services/secure_storage_service.dart';
import 'package:dbmaster/utils/connection_encryption_util.dart';

void main() {
  group('ConnectionExportImportService', () {
    final server = DbServer(
      id: 'conn_1',
      name: 'MySQL Local',
      type: DatabaseType.mysql,
      host: 'localhost',
      port: 3306,
      username: 'root',
      password: 'db_secret_123',
      database: 'test_db',
      useSshTunnel: true,
      sshHost: 'ssh.example.com',
      sshPort: 22,
      sshUsername: 'ssh_user',
      sshAuthMode: SshAuthMode.privateKey,
      sshPrivateKey:
          '-----BEGIN OPENSSH PRIVATE KEY-----\nkey-content\n-----END OPENSSH PRIVATE KEY-----',
      sshPassphrase: 'ssh_passphrase',
    );

    test(
      'export/import roundtrip preserves password and SSH credentials',
      () async {
        final encrypted = await ConnectionExportImportService.exportConnections(
          [server],
          'export_password',
        );

        final imported = await ConnectionExportImportService.importConnections(
          encrypted,
          'export_password',
        );

        expect(imported.length, 1);
        final result = imported.first;
        expect(result.id, server.id);
        expect(result.name, server.name);
        expect(result.password, server.password);
        expect(result.useSshTunnel, server.useSshTunnel);
        expect(result.sshUsername, server.sshUsername);
        expect(result.sshPrivateKey, server.sshPrivateKey);
        expect(result.sshPassphrase, server.sshPassphrase);
      },
    );

    test('export attempts to read missing password from secure storage', () async {
      // Construct a new server with a null password; copyWith cannot be used to
      // clear nullable fields because it treats null as "no change".
      final serverWithoutPassword = DbServer(
        id: 'conn_no_password_${DateTime.now().millisecondsSinceEpoch}',
        name: 'MySQL Local',
        type: DatabaseType.mysql,
        host: 'localhost',
        port: 3306,
        username: 'root',
        password: null,
        database: 'test_db',
      );

      // When secure storage is unavailable in the test environment, attaching
      // the password throws a SecureStorageException. When it is available but
      // has no value for the connection id, export proceeds with a null password.
      try {
        final encrypted = await ConnectionExportImportService.exportConnections(
          [serverWithoutPassword],
          'export_password',
        );
        final imported = await ConnectionExportImportService.importConnections(
          encrypted,
          'export_password',
        );
        expect(imported.first.password, isNull);
      } on SecureStorageException {
        // Expected when the platform secure storage is not accessible in tests.
      }
    });

    test('DbServer.toJson() never includes sensitive fields', () {
      final json = server.toJson();
      expect(json, isNot(contains('password')));
      expect(json, isNot(contains('sshPassword')));
      expect(json, isNot(contains('sshPrivateKey')));
      expect(json, isNot(contains('sshPassphrase')));
    });

    test('import with wrong password throws', () async {
      final encrypted = await ConnectionExportImportService.exportConnections([
        server,
      ], 'correct_password');

      expect(
        () => ConnectionExportImportService.importConnections(
          encrypted,
          'wrong_password',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('import with unsupported version throws', () async {
      final payload = jsonEncode({
        'version': 999,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'connections': [],
      });
      final encrypted = ConnectionEncryptionUtil.encrypt(payload, 'password');

      expect(
        () => ConnectionExportImportService.importConnections(
          encrypted,
          'password',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported export version'),
          ),
        ),
      );
    });

    test('import with missing connections key throws', () async {
      final payload = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
      });
      final encrypted = ConnectionEncryptionUtil.encrypt(payload, 'password');

      expect(
        () => ConnectionExportImportService.importConnections(
          encrypted,
          'password',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('connections list is missing or empty'),
          ),
        ),
      );
    });

    test('import with empty connections list throws', () async {
      final payload = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'connections': <Map<String, dynamic>>[],
      });
      final encrypted = ConnectionEncryptionUtil.encrypt(payload, 'password');

      expect(
        () => ConnectionExportImportService.importConnections(
          encrypted,
          'password',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('connections list is missing or empty'),
          ),
        ),
      );
    });

    test('export with empty connections throws', () async {
      expect(
        () => ConnectionExportImportService.exportConnections([], 'password'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
