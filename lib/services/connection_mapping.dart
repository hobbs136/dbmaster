//! Mapping between the client [DbServer] model and the server's
//! `database_connections` row shape (ADR-0003 S3).
//!
//! The server schema (migration 002/005/007/008) and the client `DbServer`
//! carry the same information but differ in:
//! - **Naming**: server uses snake_case (`default_database`, `use_ssl`,
//!   `ssh_auth_mode`); the client uses camelCase (`database`, `useSSL`).
//! - **SQLite**: the client reuses `host` as the file path; the server has a
//!   dedicated `file_path` column (and expects `host='sqlite'`, `port=0`).
//! - **db_type**: server canonical is `mysql`/`postgres`/`sqlite`; the client
//!   enum is `mysql`/`postgresql`/`sqlite` (+ others not yet server-supported).
//! - **extra**: server stores a JSON string; the client holds a `Map`.
//! - **Credentials**: the connection row carries `password_encrypted` +
//!   `ssh_*_encrypted` (ciphertext); plaintext credentials come separately via
//!   the embedded-only `GET /api/connections/:id/credential` endpoint.

import 'dart:convert';

import '../models/database_models.dart';

/// The server-supported db_type canonical names.
const _kServerMysql = 'mysql';
const _kServerPostgres = 'postgres';
const _kServerSqlite = 'sqlite';
const _kServerClickhouse = 'clickhouse';

/// Plaintext SSH credentials returned by the credential endpoint, used to
/// hydrate a [DbServer] from a server row.
class SshCredentials {
  final String? username;
  final String? authMode; // 'password' | 'privateKey'
  final String? password;
  final String? privateKey;
  final String? passphrase;

  const SshCredentials({
    this.username,
    this.authMode,
    this.password,
    this.privateKey,
    this.passphrase,
  });
}

/// Convert a client [DatabaseType] to the server's canonical db_type string.
///
/// Only the SQL libraries are mapped (S3 scope); non-SQL types are not yet
/// server-supported and return null so callers can route them to keychain.
// defines which client types are eligible for server
/// storage (the S3 "SQL-first" decision).
String? serverDbTypeFromClient(DatabaseType type) {
  switch (type) {
    case DatabaseType.mysql:
      return _kServerMysql;
    case DatabaseType.postgresql:
      return _kServerPostgres;
    case DatabaseType.sqlite:
      return _kServerSqlite;
    case DatabaseType.clickhouse:
      return _kServerClickhouse;
    case DatabaseType.doris:
    case DatabaseType.redis:
    case DatabaseType.mongodb:
    case DatabaseType.tdengine:
    case DatabaseType.sqlserver:
    case DatabaseType.oceanbase:
    case DatabaseType.tidb:
    case DatabaseType.starrocks:
    case DatabaseType.mariadb:
      // T22-T25：经网关（/api/gw）消费，不走 S3 嵌入式同步——同 doris/sqlserver。
      return null; // not yet server-supported — stays in keychain
  }
}

/// Inverse of [serverDbTypeFromClient]: server db_type string → client enum.
/// Returns null for unknown / unsupported values.
DatabaseType? clientDbTypeFromServer(String? dbType) {
  switch (dbType?.toLowerCase()) {
    case _kServerMysql:
      return DatabaseType.mysql;
    case 'postgres':
    case 'postgresql':
    case 'pg':
      return DatabaseType.postgresql;
    case _kServerSqlite:
      return DatabaseType.sqlite;
    case _kServerClickhouse:
      return DatabaseType.clickhouse;
    default:
      return null;
  }
}

/// Build the JSON body for `POST /api/connections` from a client [DbServer].
///
/// [plaintextPassword] is the connection's DB password (the server encrypts
/// it; never send an already-encrypted value here). SSH secrets are pulled
/// from the [server] if present.
// client→server row mapping.
Map<String, dynamic> toCreateBody(DbServer server, String plaintextPassword) {
  final isSqlite = server.type == DatabaseType.sqlite;
  final body = <String, dynamic>{
    'name': server.name,
    'db_type': serverDbTypeFromClient(server.type),
    // SQLite: host is the file path; send it as file_path + sentinel host/port.
    if (isSqlite) 'host': 'sqlite' else 'host': server.host,
    if (isSqlite) 'port': 0 else 'port': server.port,
    if (isSqlite) 'username': 'sqlite' else 'username': server.username ?? '',
    'password': isSqlite ? '' : plaintextPassword,
    if (isSqlite) 'file_path': server.host else 'file_path': null,
    // Extended options (migration 008).
    'use_ssl': server.useSSL,
    'timeout_seconds': server.timeoutSeconds,
    'auto_reconnect': server.autoReconnect,
    if (server.charset != null) 'charset': server.charset,
    if (server.timezone != null) 'timezone': server.timezone,
    if (server.environment != null) 'environment': server.environment!.name,
    'read_only': server.readOnly,
    if (server.groupId != null) 'group_id': server.groupId,
    if (server.extra != null) 'extra': jsonEncode(server.extra),
    // Default DB name (mysql/postgres).
    if (server.database != null && server.database!.isNotEmpty)
      'default_database': server.database,
    'kind': 'collab',
    // SSH tunnel.
    'ssh_enabled': server.useSshTunnel,
    if (server.sshHost != null) 'ssh_host': server.sshHost,
    if (server.sshPort != null) 'ssh_port': server.sshPort,
    if (server.sshUsername != null) 'ssh_username': server.sshUsername,
    if (server.sshAuthMode != null) 'ssh_auth_mode': server.sshAuthMode!.name,
    if (server.sshPassword != null && server.sshPassword!.isNotEmpty)
      'ssh_password': server.sshPassword,
    if (server.sshPrivateKey != null && server.sshPrivateKey!.isNotEmpty)
      'ssh_private_key': server.sshPrivateKey,
    if (server.sshPassphrase != null && server.sshPassphrase!.isNotEmpty)
      'ssh_passphrase': server.sshPassphrase,
  };
  // Strip null values — the server treats omitted Optionals correctly and
  // sending explicit nulls is noisier than omitting.
  body.removeWhere((_, v) => v == null);
  return body;
}

/// Build a [DbServer] from a server connection row + its plaintext credential.
///
/// [row] is the JSON object from `GET /api/connections` (list) or the `data`
/// field of a create response. [plaintextPassword] is the DB password (from
/// the credential endpoint); [ssh] carries the plaintext SSH credentials.
// server row→client mapping (the credential endpoint
/// supplies the secrets the row omits in plaintext).
DbServer fromServerRow(
  Map<String, dynamic> row, {
  String? plaintextPassword,
  SshCredentials? ssh,
}) {
  final type = clientDbTypeFromServer(row['db_type'] as String?);
  if (type == null) {
    throw ArgumentError(
        'Unsupported server db_type: ${row['db_type']} (S3 only migrates SQL libraries)');
  }
  final isSqlite = type == DatabaseType.sqlite;

  // Decode the `extra` JSON blob (vendor-specific options) if present.
  Map<String, dynamic>? extra;
  final extraRaw = row['extra'];
  if (extraRaw is String && extraRaw.isNotEmpty) {
    try {
      final decoded = jsonDecode(extraRaw);
      if (decoded is Map<String, dynamic>) extra = decoded;
    } catch (_) {
      // Malformed extra — ignore rather than fail the whole mapping.
    }
  }

  // Environment enum.
  ConnectionEnvironment? env;
  final envRaw = row['environment'];
  if (envRaw is String) {
    env = ConnectionEnvironment.values
        .where((e) => e.name == envRaw)
        .cast<ConnectionEnvironment?>()
        .firstWhere((_) => true, orElse: () => null);
  }

  // SSH auth mode enum.
  SshAuthMode? sshAuthMode;
  final authModeRaw = ssh?.authMode ?? row['ssh_auth_mode'];
  if (authModeRaw is String) {
    sshAuthMode = SshAuthMode.values
        .where((m) => m.name == authModeRaw)
        .cast<SshAuthMode?>()
        .firstWhere((_) => true, orElse: () => null);
  }

  return DbServer(
    id: row['id'] as String,
    name: row['name'] as String,
    type: type,
    // SQLite: restore the file path from file_path into host (client convention).
    host: isSqlite ? (row['file_path'] as String? ?? '') : (row['host'] as String),
    port: isSqlite ? 0 : ((row['port'] as num?)?.toInt() ?? 0),
    username: isSqlite ? null : (row['username'] as String?),
    password: plaintextPassword,
    database: row['default_database'] as String?,
    useSSL: _asBool(row['use_ssl']),
    timeoutSeconds: (row['timeout_seconds'] as num?)?.toInt() ?? 30,
    autoReconnect: _asBool(row['auto_reconnect']),
    charset: row['charset'] as String?,
    timezone: row['timezone'] as String?,
    groupId: row['group_id'] as String?,
    environment: env,
    readOnly: _asBool(row['read_only']),
    useSshTunnel: _asBool(row['ssh_enabled']),
    sshHost: row['ssh_host'] as String?,
    sshPort: (row['ssh_port'] as num?)?.toInt(),
    sshUsername: ssh?.username ?? (row['ssh_username'] as String?),
    sshAuthMode: sshAuthMode,
    sshPassword: ssh?.password,
    sshPrivateKey: ssh?.privateKey,
    sshPassphrase: ssh?.passphrase,
    extra: extra,
  );
}

/// Whether a [DbServer] is eligible for server-side storage (S3 SQL-first).
/// Non-SQL types and SQL types whose server mapping is null stay in keychain.
bool isServerSyncable(DbServer server) =>
    serverDbTypeFromClient(server.type) != null;

/// Coerce a server bool/int value to a Dart bool. The server stores booleans
/// as SQLite integers (0/1) but some JSON paths may already emit true/false;
/// accept both without throwing on the type-cast.
// defensive coercion: `(x as num?)` would throw on a
/// bool, so we branch on the runtime type first.
bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v.toInt() != 0;
  return false;
}
