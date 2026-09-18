//! Gateway client for routing SQL query execution through the embedded server
//! (ADR-0003 S4).
//!
//! In embedded mode, SQL-library (mysql/postgresql/sqlite) queries typed in the
//! editor are sent to the server's `POST /api/db/:conn_id/query` endpoint
//! instead of being executed against a local adapter connection. The server
//! holds the credentials (mirrored in S3), opens a short-lived pool, runs the
//! SQL, and returns `{columns, rows, affectedRows, columnTypes, executionTimeMs}`.
//!
//! Routing policy (decision C): a query routes through the gateway ONLY when
//! all of:
//! - the app is in embedded mode ([ServerConnection.isEmbeddedMode]),
//! - the connection is a server-syncable SQL library (mysql/postgresql/sqlite),
//! - the query is NOT inside a transaction and is NOT itself BEGIN/COMMIT/
//!   ROLLBACK (the server gateway is stateless — transactions stay local),
//! - a server connection id exists for this local id (the connection was
//!   mirrored to the server in S3).
//!
//! Any condition failing falls back to the local adapter path. Gateway call
//! failures also fall back (transparent degradation).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/database_models.dart';
import 'connection_mapping.dart' as mapping;
import 'database_abstract.dart';
import 'ports/db_service_ports.dart';
import 'server_connection.dart';

/// SharedPreferences key holding the local-id → server-conn-id map.
///
/// Owned and written by [ConnectionProvider] in S3; read here so the gateway
/// knows which `:conn_id` to target. Kept as a constant so both sides agree
/// on the key.
// mirrors the private constant in ConnectionProvider.
const _kServerIdMapKey = 'connection_server_id_map';

/// Singleton that calls the embedded server's `/api/db/:conn_id/*` gateway.
///
/// Mirrors the HTTP-plumbing pattern of [ConnectionSyncService] (reads
/// [ServerConnection] for base URL + token). Stateless per request — the server
/// opens a fresh pool each call.
class DbGatewayService {
  DbGatewayService._();
  static final DbGatewayService instance = DbGatewayService._();

  /// Test-only HTTP client injection.
  @visibleForTesting
  http.Client? httpClient;

  /// Test-only injection of the embedded-mode flag (so tests can exercise
  /// [shouldRouteViaGateway] without a live ServerConnection).
  @visibleForTesting
  bool testEmbeddedMode = false;

  /// Whether the app is currently in embedded mode.
  bool get _isEmbedded =>
      testEmbeddedMode || ServerConnection().isEmbeddedMode;

  /// Send an authenticated request to the embedded server with a timeout.
  /// Used by txn / admin / browse helpers.
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final conn = ServerConnection();
    final baseUrl = conn.serverUrl;
    if (baseUrl == null ||
        conn.connectionState != ServerConnectionState.connected) {
      throw StateError('Not connected to a server (gateway unavailable).');
    }
    final token = await conn.getAccessToken();
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse('$baseUrl$path');
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final req = switch (method) {
        'GET' => client.get(uri, headers: headers),
        'POST' => client.post(uri, headers: headers, body: body == null ? '' : jsonEncode(body)),
        'DELETE' => client.delete(uri, headers: headers),
        _ => throw StateError('Unsupported method: $method'),
      };
      return await req.timeout(const Duration(seconds: 30));
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Decode the {ok, data, error} envelope; throws on API error.
  dynamic _unwrap(http.Response resp, String what) {
    if (resp.statusCode == 401) {
      throw StateError('Server auth failed during $what.');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (body['ok'] != true) {
      final err = body['error'];
      final msg = err is Map ? err['message'] : 'unknown error';
      throw StateError('$what failed: $msg');
    }
    return body['data'];
  }

  /// Decide whether a query for [server] should route through the gateway.
  ///
  /// Returns false (→ fall back to local adapter) when any policy condition
  /// fails: not embedded, non-SQL-library type, in a transaction, or the SQL
  /// itself is a transaction-control statement (BEGIN/COMMIT/ROLLBACK).
  ///
  /// [inTransaction] is the connection's current transaction flag
  /// (`_state.isInTransaction(connectionId)`). Note this does NOT check the
  /// server-id mapping presence — call [lookupServerConnId] separately and
  /// treat a null result as a fallback.
  // the routing gate. Kept pure (no IO) so it's trivially
  /// testable; the id-mapping lookup is a separate step.
  bool shouldRouteViaGateway(
    DbServer server,
    String sql, {
    bool inTransaction = false,
  }) {
    if (!_isEmbedded) return false;
    // T29：gateway-backed 类型（mysql 族/sqlserver，走 /api/gw 壳）不经旧
    // /api/db/:conn_id 通道，防双路由。
    if (DbServicePorts.isGatewayBacked(server.type)) return false;
    if (!mapping.isServerSyncable(server)) return false; // only SQL libs
    if (inTransaction) return false; // transactions stay local
    if (_isTransactionControlStatement(sql)) return false;
    return true;
  }

  /// Detect BEGIN / COMMIT / ROLLBACK (and START TRANSACTION / SET AUTOCOMMIT)
  /// at the statement level so they bypass the stateless gateway.
  static bool _isTransactionControlStatement(String sql) {
    final trimmed = sql.trimLeft().toUpperCase();
    // Strip a leading '(' for wrapper calls; rare but harmless.
    if (trimmed.startsWith('(')) {
      return _isTransactionControlStatement(trimmed.substring(1));
    }
    return trimmed.startsWith('BEGIN') ||
        trimmed.startsWith('START TRANSACTION') ||
        trimmed.startsWith('COMMIT') ||
        trimmed.startsWith('ROLLBACK') ||
        trimmed.startsWith('SET AUTOCOMMIT') ||
        trimmed.startsWith('SAVEPOINT') ||
        trimmed.startsWith('RELEASE SAVEPOINT');
  }

  /// Look up the server connection id for a given client-local connection id.
  /// Returns null when the connection was never mirrored to the server.
  Future<String?> lookupServerConnId(String localId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kServerIdMapKey);
      if (raw == null) return null;
      final map = (jsonDecode(raw) as Map).cast<String, String>();
      return map[localId];
    } catch (_) {
      return null;
    }
  }

  /// Execute a query via `POST /api/db/:conn_id/query`.
  ///
  /// Throws on transport/server error so the caller can fall back to the local
  /// adapter. The server gateway is single-statement and stateless; multi-
  /// statement SQL errors surface as the server's `QUERY_FAILED`.
  Future<QueryResult> executeQuery(
    String serverConnId,
    String sql, {
    String? database,
    int? limit,
  }) async {
    final conn = ServerConnection();
    final baseUrl = conn.serverUrl;
    if (baseUrl == null ||
        conn.connectionState != ServerConnectionState.connected) {
      throw StateError('Not connected to embedded server.');
    }
    final token = await conn.getAccessToken();
    final body = jsonEncode({
      if (database != null && database.isNotEmpty) 'db': database,
      'sql': sql,
      if (limit != null) 'limit': limit,
    });
    final uri = Uri.parse('$baseUrl/api/db/$serverConnId/query');
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final resp = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 401) {
        throw StateError('Gateway auth failed (token expired?).');
      }
      final envelope = jsonDecode(resp.body) as Map<String, dynamic>;
      if (envelope['ok'] != true) {
        final err = envelope['error'];
        final code = err is Map ? err['code'] : 'unknown';
        final msg = err is Map ? err['message'] : 'unknown error';
        throw StateError('Gateway query failed [$code]: $msg');
      }
      return _parseQueryResult(envelope['data'] as Map<String, dynamic>);
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Map the server's `{columns, rows, affectedRows, columnTypes, executionTimeMs}`
  /// payload to the client's [QueryResult].
  ///
  /// `columnTypes` arrives as `[{name,type}, ...]` (server) but [QueryResult]
  /// wants `Map<String,String>` — converted here. `executionTimeMs` maps to
  /// `QueryResult.executionTime`.
  // result-shape adaptation.
  QueryResult _parseQueryResult(Map<String, dynamic> data) {
    final columns = (data['columns'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final rows = ((data['rows'] as List<dynamic>?) ?? [])
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    final affectedRows = (data['affectedRows'] as num?)?.toInt();

    // columnTypes: [{name,type}] → Map<name,type>
    Map<String, String>? columnTypes;
    final ctRaw = data['columnTypes'];
    if (ctRaw is List && ctRaw.isNotEmpty) {
      columnTypes = {};
      for (final entry in ctRaw) {
        if (entry is Map) {
          final name = entry['name']?.toString();
          final type = entry['type']?.toString();
          if (name != null && type != null) {
            columnTypes[name] = type;
          }
        }
      }
    }

    final execMs = (data['executionTimeMs'] as num?)?.toInt();
    // S8 收尾: S10 txn_query includes the pinned connection's threadId so the
    // client can KILL a statement inside the transaction. Absent on db_query
    // (stateless pool dropped post-query).
    final threadId = (data['threadId'] as num?)?.toInt();

    return QueryResult(
      columns: columns,
      rows: rows,
      affectedRows: affectedRows,
      executionTime: execMs,
      columnTypes: columnTypes,
      threadId: threadId,
    );
  }

  // ── Browse endpoints (ADR-0003 S5) ───────────────────────────────────────
  // These wrap the server's GET /api/db/:conn_id/{databases,tables,columns,
  // views,procedures,functions,triggers,indexes,foreign_keys} endpoints. They
  // are NOT yet wired into ConnectionProvider's browse path (browse still uses
  // the local adapter); they exist as the building blocks for a future phase
  // that routes browse through the gateway, and for direct use by features
  // that already prefer the server view of the schema.
  // browse endpoint clients. Names only (matching the
  /// server's Vec<String> responses); richer metadata is a later refinement.

  Future<List<String>> _listNames(String connId, String path) async {
    final conn = ServerConnection();
    final baseUrl = conn.serverUrl;
    if (baseUrl == null ||
        conn.connectionState != ServerConnectionState.connected) {
      throw StateError('Not connected to embedded server.');
    }
    final token = await conn.getAccessToken();
    final uri = Uri.parse('$baseUrl/api/db/$connId/$path');
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final resp = await client.get(uri, headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 15));
      final envelope = jsonDecode(resp.body) as Map<String, dynamic>;
      if (envelope['ok'] != true) {
        throw StateError('browse $path failed: ${envelope['error']}');
      }
      final data = envelope['data'];
      if (data is! List) return [];
      return data.map((e) => e.toString()).toList();
    } finally {
      if (ownsClient) client.close();
    }
  }

  Future<List<String>> listDatabases(String connId) =>
      _listNames(connId, 'databases');

  Future<List<String>> listTables(String connId, {String? db}) =>
      _listNames(connId, db == null ? 'tables' : 'tables?db=${Uri.encodeQueryComponent(db)}');

  Future<List<String>> listViews(String connId, {String? db}) =>
      _listNames(connId, db == null ? 'views' : 'views?db=${Uri.encodeQueryComponent(db)}');

  Future<List<String>> listProcedures(String connId, {String? db}) =>
      _listNames(connId, db == null ? 'procedures' : 'procedures?db=${Uri.encodeQueryComponent(db)}');

  Future<List<String>> listFunctions(String connId, {String? db}) =>
      _listNames(connId, db == null ? 'functions' : 'functions?db=${Uri.encodeQueryComponent(db)}');

  Future<List<String>> listTriggers(String connId, {String? db}) =>
      _listNames(connId, db == null ? 'triggers' : 'triggers?db=${Uri.encodeQueryComponent(db)}');

  Future<List<String>> listIndexes(String connId, String table, {String? db}) {
    final q = 'table=${Uri.encodeQueryComponent(table)}'
        '${db == null ? '' : '&db=${Uri.encodeQueryComponent(db)}'}';
    return _listNames(connId, 'indexes?$q');
  }

  Future<List<String>> listForeignKeys(String connId, String table, {String? db}) {
    final q = 'table=${Uri.encodeQueryComponent(table)}'
        '${db == null ? '' : '&db=${Uri.encodeQueryComponent(db)}'}';
    return _listNames(connId, 'foreign_keys?$q');
  }

  /// Whether browse operations for [server] should attempt the gateway path.
  ///
  /// Returns true only when the app is in embedded mode AND [server] is a
  /// MySQL/Doris connection (the two SQL libraries whose server browse
  /// endpoints are exercised in S7). Other SQL libs (pg/sqlite) and non-SQL
  /// types fall through to their local adapters. Callers still need to
  /// [lookupServerConnId] separately and treat null as "fall back to local".
  ///
  /// This is the S7 browse-routing gate (mirrors the intent of
  /// [shouldRouteViaGateway] but for browse rather than query execution).
  bool isBrowseGatewayReady(DbServer server) {
    if (!_isEmbedded) return false;
    // T29：gateway-backed 类型（mysql 族/sqlserver）改走 /api/gw 壳，旧
    // /api/db browse/txn/admin 通道对其关闭，防双路由。
    if (DbServicePorts.isGatewayBacked(server.type)) return false;
    final t = server.type;
    return t == DatabaseType.mysql || t == DatabaseType.doris;
  }

  /// List columns for a table via `GET /api/db/:conn_id/columns`, returning
  /// rich [DbColumn] objects (name/type/isPrimaryKey/isNullable/defaultValue).
  ///
  /// Unlike [listTables] etc. which return bare names, the server's columns
  /// endpoint emits `{name, data_type, is_primary_key, is_nullable,
  /// default_value}` per column (see `columns_json` in db_handler.rs) — enough
  /// to populate a [DbColumn]. Used by the S7 browse path for MySQL/Doris.
  Future<List<DbColumn>> listColumnsRich(
    String connId,
    String table, {
    String? db,
  }) async {
    final conn = ServerConnection();
    final baseUrl = conn.serverUrl;
    if (baseUrl == null ||
        conn.connectionState != ServerConnectionState.connected) {
      throw StateError('Not connected to embedded server.');
    }
    final token = await conn.getAccessToken();
    final q = 'table=${Uri.encodeQueryComponent(table)}'
        '${db == null ? '' : '&db=${Uri.encodeQueryComponent(db)}'}';
    final uri = Uri.parse('$baseUrl/api/db/$connId/columns?$q');
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final resp = await client.get(uri, headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      }).timeout(const Duration(seconds: 15));
      final envelope = jsonDecode(resp.body) as Map<String, dynamic>;
      if (envelope['ok'] != true) {
        throw StateError('browse columns failed: ${envelope['error']}');
      }
      final data = envelope['data'];
      if (data is! List) return [];
      return data.map<DbColumn>((e) {
        final m = e as Map<String, dynamic>;
        return DbColumn(
          name: m['name']?.toString() ?? '',
          type: m['data_type']?.toString() ?? '',
          isPrimaryKey: _asBool(m['is_primary_key']),
          isNullable: _asBool(m['is_nullable']),
          defaultValue: m['default_value']?.toString(),
        );
      }).toList();
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Test connectivity for registered connections is covered by the
  /// gateway `/api/gw/connections/test` draft endpoint (T29 第三批起
  /// ClickHouse 也走该通道；旧 createConnectionRaw/testConnection/
  /// deleteConnection 临时连接三连随之退役删除）。

  // ── Transaction endpoints (ADR-0003 S10) ──────────────────────────────────
  // These wrap the server's session-pinned transaction API: begin opens a
  // pinned single-connection pool; query/commit/rollback address it by the
  // returned sessionId. The server-side pool is max_connections(1) so every
  // statement in the session hits the same physical connection (transaction
  // state persists across requests).

  /// Begin a transaction session (POST /api/db/:conn_id/txn/begin).
  ///
  /// Returns the server-generated `sessionId` on success, or null if the
  /// server rejected it (e.g. a transactionless engine returns
  /// UNSUPPORTED_TXN) or transport failed. Callers treat null as "fall back
  /// to local adapter transaction".
  Future<String?> txnBegin(String serverConnId, {String? db}) async {
    try {
      final resp = await _send(
        'POST',
        '/api/db/$serverConnId/txn/begin',
        body: {
          if (db != null && db.isNotEmpty) 'db': db,
        },
      );
      final data = _unwrap(resp, 'txn begin') as Map<String, dynamic>;
      final sid = data['sessionId']?.toString();
      return (sid != null && sid.isNotEmpty) ? sid : null;
    } catch (_) {
      return null;
    }
  }

  /// Run a statement inside an open transaction session
  /// (POST /api/db/:conn_id/txn/:session_id/query). Mirrors [executeQuery]'s
  /// result shape. Throws on transport/server error so the caller can decide
  /// how to surface it (S10 transactions do NOT silently fall back to a local
  /// non-transactional execution — that would be an autocommit footgun).
  Future<QueryResult> txnQuery(
    String serverConnId,
    String sessionId,
    String sql, {
    int? limit,
  }) async {
    final conn = ServerConnection();
    final baseUrl = conn.serverUrl;
    if (baseUrl == null ||
        conn.connectionState != ServerConnectionState.connected) {
      throw StateError('Not connected to embedded server.');
    }
    final token = await conn.getAccessToken();
    final body = jsonEncode({
      'sql': sql,
      if (limit != null) 'limit': limit,
    });
    final uri =
        Uri.parse('$baseUrl/api/db/$serverConnId/txn/$sessionId/query');
    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final resp = await client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: body,
      ).timeout(const Duration(seconds: 30));
      if (resp.statusCode == 401) {
        throw StateError('Gateway auth failed (token expired?).');
      }
      final envelope = jsonDecode(resp.body) as Map<String, dynamic>;
      if (envelope['ok'] != true) {
        final err = envelope['error'];
        final code = err is Map ? err['code'] : 'unknown';
        final msg = err is Map ? err['message'] : 'unknown error';
        throw StateError('txn query failed [$code]: $msg');
      }
      return _parseQueryResult(envelope['data'] as Map<String, dynamic>);
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Commit & close a transaction session
  /// (POST /api/db/:conn_id/txn/:session_id/commit). Throws on failure.
  Future<void> txnCommit(String serverConnId, String sessionId) async {
    final resp = await _send(
      'POST',
      '/api/db/$serverConnId/txn/$sessionId/commit',
    );
    _unwrap(resp, 'txn commit');
  }

  /// Rollback & close a transaction session
  /// (POST /api/db/:conn_id/txn/:session_id/rollback). Throws on failure.
  /// Best-effort when called from disconnect cleanup — callers swallow errors.
  Future<void> txnRollback(String serverConnId, String sessionId) async {
    final resp = await _send(
      'POST',
      '/api/db/$serverConnId/txn/$sessionId/rollback',
    );
    _unwrap(resp, 'txn rollback');
  }

  // ── Admin endpoints (ADR-0003 S8b prep) ───────────────────────────────────
  // KILL QUERY and multi-statement script execution. These cover the raw-SQL
  // consumers that the stateless single-statement gateway cannot (process-kill
  // needs an independent privileged connection; scripts need a real splitter).

  /// Kill a running query (POST /api/db/:conn_id/admin/kill).
  ///
  /// Returns true on success, false on any failure (caller falls back to a
  /// local-connection KILL). The server opens a fresh pool and issues
  /// `KILL QUERY <thread_id>`; the target thread is the client-supplied id,
  /// not this connection's own thread.
  Future<bool> adminKill(String serverConnId, int threadId) async {
    try {
      final resp = await _send(
        'POST',
        '/api/db/$serverConnId/admin/kill',
        body: {'thread_id': threadId},
      );
      final data = _unwrap(resp, 'admin kill') as Map<String, dynamic>;
      return data['killed'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Run a multi-statement script (POST /api/db/:conn_id/admin/script).
  ///
  /// The server splits with a real SQL-aware tokenizer (handles quotes /
  /// comments / `BEGIN...END` / `DELIMITER`) and executes each statement,
  /// continuing past errors. Returns per-statement results so the caller can
  /// report which succeeded. Throws on transport/server error so the caller
  /// can fall back to a local split(';') loop.
  Future<List<ScriptStatementResult>> adminScript(
    String serverConnId,
    String script, {
    String? db,
    int? limit,
  }) async {
    final resp = await _send(
      'POST',
      '/api/db/$serverConnId/admin/script',
      body: {
        'script': script,
        if (db != null && db.isNotEmpty) 'db': db,
        if (limit != null) 'limit': limit,
      },
    );
    final data = _unwrap(resp, 'admin script') as Map<String, dynamic>;
    final results = data['results'];
    if (results is! List) return [];
    return results.map<ScriptStatementResult>((e) {
      final m = e as Map<String, dynamic>;
      return ScriptStatementResult(
        sql: m['sql']?.toString() ?? '',
        ok: m['ok'] == true,
        columns: (m['columns'] as List<dynamic>?)
            ?.map((c) => c.toString())
            .toList(),
        rows: (m['rows'] as List<dynamic>?)
            ?.map((r) => Map<String, dynamic>.from(r as Map))
            .toList(),
        affectedRows: (m['affectedRows'] as num?)?.toInt(),
        error: m['error']?.toString(),
      );
    }).toList();
  }

  /// Convenience: reset the singleton's test seams between tests.
  @visibleForTesting
  void resetForTesting() {
    httpClient = null;
    testEmbeddedMode = false;
  }
}

/// Coerce a JSON-decoded value to bool. The server emits `is_primary_key` /
/// `is_nullable` as JSON booleans (see `columns_json`), but defensively accept
/// 0/1 ints too in case the shape shifts.
bool _asBool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v.toInt() != 0;
  return false;
}

/// Result of one statement in a multi-statement script run
/// (see [DbGatewayService.adminScript]).
class ScriptStatementResult {
  final String sql;
  final bool ok;
  final List<String>? columns;
  final List<Map<String, dynamic>>? rows;
  final int? affectedRows;
  final String? error;

  ScriptStatementResult({
    required this.sql,
    required this.ok,
    this.columns,
    this.rows,
    this.affectedRows,
    this.error,
  });
}
