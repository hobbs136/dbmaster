//! Dev-only tool: one-shot cleanup of local connection + embedded-server data.
//!
//! Problem context (PROJECT_STATUS P1):
//! - E2E/probe runs share the same AppSupport/embedded-server directory as the
//!   production app, polluting the vault (database_connections) and the local
//!   id mapping table (connection_server_id_map in SharedPreferences).
//! - Each connect/save for gateway-backed types registers a new row in the
//!   server-side SQLite because there is no deduplication guard.
//!
//! This script wipes:
//! 1. All saved connection metadata (`saved_connections` in SharedPreferences).
//! 2. The local→server id mapping (`connection_server_id_map`).
//! 3. All credentials (passwords + SSH secrets) from secure storage.
//! 4. The embedded-server data directory (SQLite + WAL + migrations state).
//! 5. Residual server session keys so the next run starts fresh embedded mode.
//!
//! Run with:
//!   flutter run -t lib/dev/cleanup_main.dart -d windows
//! (or macos/linux).
//!
//! ⚠️ THIS DELETES ALL LOCAL CONNECTIONS AND CREDENTIALS. Make sure you have
//! backups of any production connections before running.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/secure_storage_service.dart';
import '../services/embedded_server_service.dart';
import '../utils/app_logger.dart';

/// Keys mirrored from ConnectionProvider / ServerConnection.
const _kSavedConnections = 'saved_connections';
const _kConnectionServerIdMap = 'connection_server_id_map';
const _kServerUrl = 'server_url';
const _kRefreshToken = 'server_refresh_token';
const _kEmail = 'server_email';
const _kPreferredMode = 'server_preferred_mode';

/// Summary of what was cleaned.
class CleanupSummary {
  int sharedPrefKeysRemoved = 0;
  bool credentialsCleared = false;
  bool embeddedStopped = false;
  List<String> deletedPaths = [];
  List<String> deletedDirs = [];
  List<String> errors = [];

  @override
  String toString() {
    final buffer = StringBuffer()
      ..writeln('=== Cleanup Summary ===')
      ..writeln('SharedPreferences keys removed: $sharedPrefKeysRemoved')
      ..writeln('Credentials vault cleared: $credentialsCleared')
      ..writeln('Embedded server stopped: $embeddedStopped')
      ..writeln('Deleted files: ${deletedPaths.length}')
      ..writeln('Deleted directories: ${deletedDirs.length}');
    if (errors.isNotEmpty) {
      buffer.writeln('\nErrors (${errors.length}):');
      for (final e in errors) {
        buffer.writeln('  - $e');
      }
    }
    return buffer.toString();
  }
}

/// Stop the embedded child process so its SQLite files are not locked.
Future<bool> _stopEmbeddedServer() async {
  try {
    if (EmbeddedServerService.instance.isRunning) {
      await EmbeddedServerService.instance.stop();
      return true;
    }
  } catch (e) {
    AppLogger.w('CleanupEmbeddedData', 'Failed to stop embedded server: $e');
  }
  return false;
}

/// Remove known SharedPreferences keys related to connections/server session.
Future<int> _cleanupSharedPreferences(CleanupSummary summary) async {
  var removed = 0;
  try {
    final prefs = await SharedPreferences.getInstance();

    // Main connection/metadata keys.
    final keysToRemove = [
      _kSavedConnections,
      _kConnectionServerIdMap,
      _kServerUrl,
      _kRefreshToken,
      _kEmail,
      _kPreferredMode,
    ];

    for (final key in keysToRemove) {
      if (prefs.containsKey(key)) {
        final ok = await prefs.remove(key);
        if (ok) removed++;
      }
    }

    // Legacy fallback password entries (prefix-based, stored in SharedPreferences).
    final fallbackKeys = prefs
        .getKeys()
        .where((k) => k.startsWith('fallback_password_'))
        .toList();
    for (final key in fallbackKeys) {
      final ok = await prefs.remove(key);
      if (ok) removed++;
    }
  } catch (e, st) {
    final msg = 'SharedPreferences cleanup failed: $e';
    summary.errors.add(msg);
    AppLogger.e('CleanupEmbeddedData', msg, e, st);
  }
  return removed;
}

/// Clear the credentials vault (passwords + SSH secrets).
Future<bool> _cleanupCredentials(CleanupSummary summary) async {
  try {
    await SecureStorageService.clearAll();
    return true;
  } catch (e, st) {
    final msg = 'Credentials cleanup failed: $e';
    summary.errors.add(msg);
    AppLogger.e('CleanupEmbeddedData', msg, e, st);
    return false;
  }
}

/// Recursively delete [dir]. Returns true if the directory no longer exists.
Future<bool> _deleteDirectory(Directory dir, CleanupSummary summary) async {
  try {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      summary.deletedDirs.add(dir.path);
      return true;
    }
  } catch (e, st) {
    final msg = 'Failed to delete ${dir.path}: $e';
    summary.errors.add(msg);
    AppLogger.e('CleanupEmbeddedData', msg, e, st);
  }
  return !(await dir.exists());
}

/// Delete the embedded-server data directory and its backups.
Future<void> _cleanupEmbeddedDataDir(CleanupSummary summary) async {
  try {
    final support = await getApplicationSupportDirectory();
    final embeddedDir = Directory('${support.path}/embedded-server');
    summary.embeddedStopped = await _stopEmbeddedServer();
    await _deleteDirectory(embeddedDir, summary);

    // Also remove any `.bak-*` migration rebuild backups created by
    // init_pool_with_embedded_rebuild (server core/src/db/pool.rs).
    await for (final entity in support.list()) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('embedded-server.bak-')) {
          await _deleteDirectory(entity, summary);
        }
      }
    }
  } catch (e, st) {
    final msg = 'Embedded data directory cleanup failed: $e';
    summary.errors.add(msg);
    AppLogger.e('CleanupEmbeddedData', msg, e, st);
  }
}

/// Inspect the current SharedPreferences for a human-readable before-state.
Future<Map<String, dynamic>> inspectSharedPreferences() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final result = <String, dynamic>{};

    final rawConnections = prefs.getString(_kSavedConnections);
    if (rawConnections != null) {
      final list = jsonDecode(rawConnections) as List;
      result['saved_connections_count'] = list.length;
      result['saved_connection_names'] =
          list.map((e) => (e as Map)['name']?.toString() ?? '?').toList();
    } else {
      result['saved_connections_count'] = 0;
    }

    final rawMap = prefs.getString(_kConnectionServerIdMap);
    if (rawMap != null) {
      final map = jsonDecode(rawMap) as Map;
      result['connection_server_id_map_count'] = map.length;
    } else {
      result['connection_server_id_map_count'] = 0;
    }

    return result;
  } catch (e) {
    return {'error': e.toString()};
  }
}

/// Run the full cleanup and return a summary.
Future<CleanupSummary> runCleanup() async {
  final summary = CleanupSummary();

  summary.sharedPrefKeysRemoved = await _cleanupSharedPreferences(summary);
  summary.credentialsCleared = await _cleanupCredentials(summary);
  await _cleanupEmbeddedDataDir(summary);

  return summary;
}

/// Human-readable before/after report for the UI.
Future<String> buildReport(CleanupSummary summary) async {
  final before = await inspectSharedPreferences();
  final buffer = StringBuffer()
    ..writeln('BEFORE')
    ..writeln('  saved_connections: ${before['saved_connections_count']}')
    ..writeln(
        '  connection_server_id_map: ${before['connection_server_id_map_count']}')
    ..writeln()
    ..writeln(summary.toString());
  return buffer.toString();
}
