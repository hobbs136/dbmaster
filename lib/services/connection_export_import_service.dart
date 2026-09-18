import 'dart:convert';

import '../models/database_models.dart';
import '../utils/connection_encryption_util.dart';
import 'secure_storage_service.dart';

/// Service for exporting and importing encrypted database connections.
///
/// The export format includes the connection password and SSH credentials
/// (which are normally excluded from [DbServer.toJson] and stored in secure
/// storage) so that a full backup/restore is possible.
class ConnectionExportImportService {
  static const int _currentVersion = 1;

  /// Exports a list of [connections] as an encrypted, Base64-encoded payload.
  ///
  /// For each connection, missing passwords or SSH credentials are read from
  /// secure storage when available. Throws an [ArgumentError] if
  /// [connections] is empty.
  static Future<String> exportConnections(
    List<DbServer> connections,
    String password,
  ) async {
    if (connections.isEmpty) {
      throw ArgumentError('connections cannot be empty');
    }

    final exportableConnections = await Future.wait(
      connections.map(_prepareConnectionForExport),
    );

    final payload = {
      'version': _currentVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'connections': exportableConnections,
    };

    final jsonString = jsonEncode(payload);
    return ConnectionEncryptionUtil.encrypt(jsonString, password);
  }

  /// Decrypts and parses an exported payload, returning the list of
  /// [DbServer] objects.
  ///
  /// Throws if decryption fails, the version is unsupported, or the
  /// connections list is missing or empty.
  static Future<List<DbServer>> importConnections(
    String encryptedContent,
    String password,
  ) async {
    final jsonString = ConnectionEncryptionUtil.decrypt(
      encryptedContent,
      password,
    );
    final payload = jsonDecode(jsonString) as Map<String, dynamic>;

    final version = payload['version'];
    if (version != _currentVersion) {
      throw FormatException('Unsupported export version: $version');
    }

    final connectionsJson = payload['connections'];
    if (connectionsJson is! List || connectionsJson.isEmpty) {
      throw FormatException('connections list is missing or empty');
    }

    return connectionsJson
        .cast<Map<String, dynamic>>()
        .map(DbServer.fromJson)
        .toList();
  }

  /// Ensures a connection has its password and SSH credentials present,
  /// reading from secure storage when needed, and returns the JSON map used
  /// for export (including sensitive fields).
  static Future<Map<String, dynamic>> _prepareConnectionForExport(
    DbServer server,
  ) async {
    var exportable = server;

    if (server.password == null || server.password!.isEmpty) {
      exportable = await SecureStorageService.attachPassword(exportable);
    }

    if (server.useSshTunnel) {
      final hasSshPassword =
          exportable.sshPassword != null && exportable.sshPassword!.isNotEmpty;
      final hasSshPrivateKey =
          exportable.sshPrivateKey != null &&
          exportable.sshPrivateKey!.isNotEmpty;
      if (!hasSshPassword && !hasSshPrivateKey) {
        exportable = await SecureStorageService.attachSshCredentials(
          exportable,
        );
      }
    }

    return _toExportJson(exportable);
  }

  /// Builds the export JSON map for [server], re-adding sensitive fields that
  /// [DbServer.toJson] intentionally omits.
  static Map<String, dynamic> _toExportJson(DbServer server) {
    return {
      ...server.toJson(),
      'password': server.password,
      'sshPassword': server.sshPassword,
      'sshPrivateKey': server.sshPrivateKey,
      'sshPassphrase': server.sshPassphrase,
    };
  }
}
