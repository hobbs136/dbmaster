//! Anonymous telemetry service for the conversion-funnel experiment
//! (`telemetry-funnel-plan.md` §5).
//!
//! Emits anonymized events to either the user's connected DbMaster Server
//! (`POST /api/telemetry/event`) or, when unconnected, a central default bucket.
//! Persists a 1000-event LRU queue locally so events are not lost when the
//! network is unavailable.
//!
//! Privacy contract (defensive.md):
//!   * `install_uuid` is a random v4 UUID — NOT a machine fingerprint.
//!     Users can reset it via [resetInstallUuid].
//!   * Payloads never include credentials, SQL text, database names, or PII.
//!     Inbound `extra` fields are PII-masked via [PIIMasker] and unknown
//!     reserved keys are dropped.
//!   * Logs record only event names and outcomes, never payloads.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/app_logger.dart';
import 'pii_masker.dart';
import 'server_connection.dart';

/// Canonical funnel event type names.
///
/// Server-side `VALID_EVENT_TYPES` whitelist must include these (see
/// `telemetry-funnel-plan.md` §3 — backend engineer's task).
class TelemetryEventType {
  static const featureUsed = 'feature_used';
  static const touchpointExposed = 'touchpoint_exposed';
  static const touchpointClicked = 'touchpoint_clicked';
  static const serverDownloadClicked = 'server_download_clicked';
  static const serverConnected = 'server_connected';

  // Reserved for downstream license ADR (NOT emitted by this client yet).
  static const trialStarted = 'trial_started';

  TelemetryEventType._();
}

/// Singleton telemetry dispatcher (fire-and-forget; no Provider — has no UI
/// state). Lifecycle: call [init] once at app startup. Tests reset via
/// [resetForTesting].
class TelemetryService {
  static final TelemetryService _instance = TelemetryService._();
  factory TelemetryService() => _instance;
  TelemetryService._();

  static TelemetryService get instance => _instance;

  // ── Test injection hooks ──
  @visibleForTesting
  String? testInstallUuid;

  @visibleForTesting
  http.Client? testHttpClient;

  @visibleForTesting
  FlutterSecureStorage? testSecureStorage;

  @visibleForTesting
  SharedPreferences? testPrefs;

  @visibleForTesting
  String? testAppVersion;

  @visibleForTesting
  String? testOs;

  /// Overrides the central default bucket URL in tests.
  @visibleForTesting
  String? testDefaultEndpoint;

  /// Force-init without touching secure storage / prefs (for unit tests).
  @visibleForTesting
  bool testSkipPersistence = false;

  // ── Internal state ──
  static const String _installUuidKey = 'telemetry_install_uuid_v1';
  static const String _queuePrefKey = 'telemetry_queue_v1';
  static const String _featureCountPrefKey = 'telemetry_feature_counts_v1';
  static const String _liteFlagPrefKey = 'telemetry_lite_enabled_v1';
  static const String _liteFlagFetchedAtPrefKey =
      'telemetry_lite_flag_fetched_at_v1';

  /// Hard cap on queued events. Oldest are dropped first (LRU).
  static const int maxQueueSize = 1000;

  /// Eligibility threshold for the lite touchpoint gate (D1=B): users who have
  /// completed a given feature ≥ [liteEligibilityThreshold] times become
  /// eligible to see the lite touchpoint when not connected to a Server.
  /// See `telemetry-funnel-plan.md` §1.B.
  static const int liteEligibilityThreshold = 3;

  /// Per-(install_uuid × guideId) lifetime render cap for lite touchpoints
  /// (anti-fatigue). See `telemetry-funnel-plan.md` §1.B "频率闸门".
  static const int liteMaxExposuresPerGuide = 3;

  String? _installUuid;
  String _appVersion = 'unknown';
  String _os = 'unknown';
  String _locale = 'en';
  bool _initialized = false;
  http.Client? _ownedClient;

  /// Funnel lite kill switch — defaults to ON; can be flipped remotely via
  /// `/api/health` field `funnel_lite_enabled` (D5 — pending architect ADR;
  /// see `telemetry-funnel-plan.md` §1.B / §12).
  bool _liteTouchpointEnabled = true;
  DateTime? _liteFlagFetchedAt;
  static const Duration _liteFlagRefreshInterval = Duration(hours: 24);

  /// Feature-completion counters, used by [LiteTouchpointGate] for the ≥3
  /// eligibility gate. Keyed by feature id.
  final Map<String, int> _featureCounts = {};

  /// Pending events awaiting send.
  final List<_TelemetryEvent> _queue = [];

  bool _flushing = false;
  bool _refreshingFlag = false;

  /// Default central bucket. Override at build time via
  /// `--dart-define=TELEMETRY_BUCKET_URL=...`. Production MUST be https.
  static const String _defaultBucketUrl = String.fromEnvironment(
    'TELEMETRY_BUCKET_URL',
    defaultValue: 'https://telemetry.dbmaster.tech/api/telemetry/event',
  );

  // ── Lifecycle ──

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _os = testOs ?? Platform.operatingSystem;
    _appVersion = testAppVersion ??
        const String.fromEnvironment(
          'APP_VERSION',
          defaultValue: '0.0.1+1',
        );

    if (testInstallUuid != null) {
      _installUuid = testInstallUuid;
    } else if (!testSkipPersistence) {
      _installUuid = await _loadOrCreateInstallUuid();
    }

    if (!testSkipPersistence) {
      await _loadQueue();
      await _loadFeatureCounts();
      await _loadLiteFlag();
    }

    // Kick off a background flush + flag refresh. Fire-and-forget — failures
    // are logged but never block the UI.
    unawaited(_flush());
    unawaited(refreshLiteFlag());
  }

  Future<String> _loadOrCreateInstallUuid() async {
    final storage = testSecureStorage ?? const FlutterSecureStorage();
    try {
      final existing = await storage.read(key: _installUuidKey);
      if (existing != null && _isValidUuidV4(existing)) {
        return existing;
      }
    } catch (e) {
      AppLogger.w('TelemetryService', 'Failed to read install_uuid: $e');
    }
    final fresh = const Uuid().v4();
    try {
      await storage.write(key: _installUuidKey, value: fresh);
    } catch (e) {
      AppLogger.w('TelemetryService', 'Failed to persist install_uuid: $e');
    }
    return fresh;
  }

  static bool _isValidUuidV4(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  /// Reset and generate a new anonymous install_uuid. Surfaced as the
  /// "reset telemetry id" affordance required by `methodology.md`.
  Future<void> resetInstallUuid() async {
    final storage = testSecureStorage ?? const FlutterSecureStorage();
    final fresh = const Uuid().v4();
    await storage.write(key: _installUuidKey, value: fresh);
    _installUuid = fresh;
    _featureCounts.clear();
    if (!testSkipPersistence) {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      await prefs.remove(_featureCountPrefKey);
    }
  }

  // ── Public read-only state ──

  String? get installUuid => _installUuid;
  String get appVersion => _appVersion;
  String get os => _os;
  bool get isInitialized => _initialized;
  bool get liteTouchpointEnabled => _liteTouchpointEnabled;

  /// Update the auto-injected locale. Called by [LocaleProvider] on change.
  void setLocale(String locale) {
    _locale = locale;
  }

  /// Read-only view of the pending queue as JSON-serializable maps
  /// (tests + diagnostics only). Returns a defensive copy so callers cannot
  /// mutate internal state.
  @visibleForTesting
  List<Map<String, Object?>> get debugQueueSnapshot =>
      _queue.map((e) => e.toJson()).toList(growable: false);

  /// Feature-completion count (used by [LiteTouchpointGate]).
  int featureCount(String featureId) => _featureCounts[featureId] ?? 0;

  /// Whether a feature has been completed enough times to be eligible for the
  /// lite touchpoint when not connected to a Server (D1=B, ≥3 by default).
  bool isFeatureEligibleForLite(
    String featureId, {
    int threshold = liteEligibilityThreshold,
  }) {
    return featureCount(featureId) >= threshold;
  }

  // ── Public semantic API ──

  /// Emit a `feature_used` event. Each call also increments the in-memory
  /// feature counter used by the lite-touchpoint eligibility gate.
  void logFeatureUsed(String featureId, {Map<String, Object?>? extra}) {
    _featureCounts[featureId] = (featureCount(featureId) + 1).clamp(0, 1 << 30);
    if (!testSkipPersistence) unawaited(_persistFeatureCounts());
    _enqueue(TelemetryEventType.featureUsed, {
      'feature_id': featureId,
      if (extra != null) ...extra,
    });
  }

  void logTouchpointExposed(
    String touchpointId, {
    required bool serverConnected,
  }) {
    _enqueue(TelemetryEventType.touchpointExposed, {
      'touchpoint_id': touchpointId,
      'server_connected': serverConnected,
    });
  }

  void logTouchpointClick(
    String touchpointId, {
    required bool serverConnected,
    String? targetUrl,
  }) {
    _enqueue(TelemetryEventType.touchpointClicked, {
      'touchpoint_id': touchpointId,
      'server_connected': serverConnected,
      'target_url': ?targetUrl,
    });
  }

  void logServerDownloadClick(
    String targetUrl, {
    String source = 'connect_dialog',
  }) {
    _enqueue(TelemetryEventType.serverDownloadClicked, {
      'target_url': targetUrl,
      'source': source,
    });
  }

  /// Emit a `server_connected` event. The client does not deduplicate — the
  /// server treats the first event per install_uuid as the conversion point
  /// (see `telemetry-funnel-plan.md` §9).
  ///
  /// Only the host's SHA-256 prefix is sent (DEFENSIVE-NOTE: never emit the
  /// raw server URL — that would leak internal deployment addresses).
  void logServerConnected(String serverUrl) {
    final hostHash = _hashHost(serverUrl);
    _enqueue(TelemetryEventType.serverConnected, {
      'server_url_host_hash': hostHash,
    });
  }

  // ── Kill switch (D5) ──

  /// Refresh the funnel-lite kill switch from the connected server's
  /// `/api/health` (preferred) — falls back silently when no server or fetch
  /// fails. Caches for 24h. The remote field is `funnel_lite_enabled: bool`
  /// (architect ADR pending — `telemetry-funnel-plan.md` §12 D5).
  Future<void> refreshLiteFlag() async {
    if (_refreshingFlag) return;
    if (_liteFlagFetchedAt != null &&
        DateTime.now().toUtc().difference(_liteFlagFetchedAt!) <
            _liteFlagRefreshInterval) {
      return; // cache hit
    }
    _refreshingFlag = true;
    try {
      final sc = ServerConnection();
      final url = sc.serverUrl;
      if (url == null ||
          sc.connectionState != ServerConnectionState.connected) {
        return; // Not connected — keep local default.
      }
      final client = testHttpClient ?? (_ownedClient ??= http.Client());
      final resp = await client
          .get(Uri.parse('$url/api/health'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      if (body is Map<String, dynamic> &&
          body['funnel_lite_enabled'] is bool) {
        _liteTouchpointEnabled = body['funnel_lite_enabled'] as bool;
        _liteFlagFetchedAt = DateTime.now().toUtc();
        if (!testSkipPersistence) await _persistLiteFlag();
        AppLogger.i('TelemetryService',
          'Lite flag refreshed: enabled=$_liteTouchpointEnabled',
        );
      }
    } catch (e) {
      // Remote flag is best-effort; never fatal.
      AppLogger.w('TelemetryService', 'Lite flag refresh skipped: $e');
    } finally {
      _refreshingFlag = false;
    }
  }

  /// Locally override the flag (e.g. for testing or a debug toggle).
  Future<void> setLiteTouchpointEnabled(bool enabled) async {
    _liteTouchpointEnabled = enabled;
    _liteFlagFetchedAt = DateTime.now().toUtc();
    if (!testSkipPersistence) await _persistLiteFlag();
  }

  // ── Internal: enqueue / flush ──

  /// Reserved keys auto-injected into every payload. Callers cannot
  /// overwrite these — supplying any of them is logged and dropped.
  static const Set<String> _reservedKeys = {
    'install_uuid',
    'app_version',
    'os',
    'locale',
    'ts',
    'idempotency_key',
  };

  void _enqueue(String eventType, Map<String, Object?> payload) {
    if (!_initialized) {
      AppLogger.w('TelemetryService', 'Dropping $eventType — not initialized');
      return;
    }
    if (_installUuid == null) {
      AppLogger.w('TelemetryService',
        'Dropping $eventType — install_uuid missing',
      );
      return;
    }

    // PII-mask string values + drop reserved keys with a warning.
    final cleaned = <String, Object?>{};
    for (final entry in payload.entries) {
      if (_reservedKeys.contains(entry.key)) {
        AppLogger.w('TelemetryService',
          'Dropping reserved key "${entry.key}" from $eventType payload',
        );
        continue;
      }
      cleaned[entry.key] = _maskValue(entry.value);
    }

    final fullPayload = <String, Object?>{
      'install_uuid': _installUuid,
      'app_version': _appVersion,
      'os': _os,
      'locale': _locale,
      'ts': DateTime.now().toUtc().toIso8601String(),
      'idempotency_key': const Uuid().v4(),
      ...cleaned,
    };

    final event = _TelemetryEvent(
      eventType: eventType,
      payload: fullPayload,
      queuedAt: DateTime.now().toUtc(),
    );
    _queue.add(event);
    _evictIfNeeded();
    if (!testSkipPersistence) unawaited(_persistQueue());
    unawaited(_flush());
  }

  Object? _maskValue(Object? value) {
    if (value is! String) return value;
    if (value.isEmpty) return value;
    return PIIMasker().maskValue(value);
  }

  void _evictIfNeeded() {
    while (_queue.length > maxQueueSize) {
      final dropped = _queue.removeAt(0);
      // DEFENSIVE-NOTE: log only the event type, never the payload — payload
      // might contain a target_url that could indirectly identify a user.
      AppLogger.w('TelemetryService',
        'Queue full — dropped oldest event (type=${dropped.eventType})',
      );
    }
  }

  String _resolveEndpoint() {
    final sc = ServerConnection();
    if (sc.connectionState == ServerConnectionState.connected &&
        sc.serverUrl != null &&
        sc.serverUrl!.isNotEmpty) {
      return '${sc.serverUrl}/api/telemetry/event';
    }
    return testDefaultEndpoint ?? _defaultBucketUrl;
  }

  Future<void> _flush() async {
    if (_flushing) return;
    if (_queue.isEmpty) return;
    _flushing = true;
    try {
      final endpoint = _resolveEndpoint();
      // Sanity-check endpoint scheme — production must be https (dev may use
      // http for localhost). Silently skip if malformed.
      final uri = Uri.tryParse(endpoint);
      if (uri == null || !uri.hasScheme) {
        AppLogger.w('TelemetryService', 'Skipping flush — bad endpoint');
        return;
      }
      final isLocal = _isLocalhost(uri.host);
      if (uri.scheme != 'https' && !isLocal && kDebugMode == false) {
        AppLogger.w('TelemetryService',
          'Skipping flush — endpoint not https and not localhost',
        );
        return;
      }

      final client = testHttpClient ?? (_ownedClient ??= http.Client());
      while (_queue.isNotEmpty) {
        final event = _queue.first;
        final consumed = await _sendOnce(client, endpoint, event);
        if (consumed) {
          _queue.remove(event);
        } else {
          // Transient failure (network / 5xx / 429) — keep event, back off.
          break;
        }
      }
      if (!testSkipPersistence) unawaited(_persistQueue());
    } finally {
      _flushing = false;
    }
  }

  static bool _isLocalhost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' || h == '127.0.0.1' || h == '::1';
  }

  /// Sends one event. Returns true if the event should leave the queue
  /// (success OR permanent 4xx failure), false on transient failure.
  Future<bool> _sendOnce(
    http.Client client,
    String endpoint,
    _TelemetryEvent event,
  ) {
    return _doSend(client, endpoint, event).then((status) {
      switch (status) {
        case _SendStatus.success:
          return true;
        case _SendStatus.permanentFailure:
          return true; // drop poison-pill event
        case _SendStatus.transientFailure:
          return false; // keep, retry later
      }
    }).catchError((_) => false);
  }

  Future<_SendStatus> _doSend(
    http.Client client,
    String endpoint,
    _TelemetryEvent event,
  ) async {
    try {
      final response = await client
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'event_type': event.eventType,
              'event_payload': event.payload,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _SendStatus.success;
      }
      if (response.statusCode == 429 || response.statusCode >= 500) {
        AppLogger.w('TelemetryService',
          'Transient send failure ${response.statusCode} for ${event.eventType}',
        );
        return _SendStatus.transientFailure;
      }
      AppLogger.w('TelemetryService',
        'Dropping ${event.eventType} — server returned ${response.statusCode}',
      );
      return _SendStatus.permanentFailure;
    } catch (e) {
      AppLogger.w('TelemetryService',
        'Send error for ${event.eventType} (will retry): $e',
      );
      return _SendStatus.transientFailure;
    }
  }

  // ── Persistence helpers ──

  Future<void> _loadQueue() async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_queuePrefKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            try {
              _queue.add(_TelemetryEvent.fromJson(item));
            } catch (_) {
              // Skip malformed event rather than fail init.
            }
          }
          if (_queue.length >= maxQueueSize) break;
        }
      }
    } catch (e) {
      AppLogger.w('TelemetryService', 'Failed to load queue: $e');
    }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      final json = jsonEncode(_queue.map((e) => e.toJson()).toList());
      await prefs.setString(_queuePrefKey, json);
    } catch (e) {
      AppLogger.w('TelemetryService', 'Failed to persist queue: $e');
    }
  }

  Future<void> _loadFeatureCounts() async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(_featureCountPrefKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _featureCounts.clear();
        decoded.forEach((k, v) {
          if (k is String && v is int) _featureCounts[k] = v;
        });
      }
    } catch (e) {
      AppLogger.w('TelemetryService', 'Failed to load feature counts: $e');
    }
  }

  Future<void> _persistFeatureCounts() async {
    try {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      await prefs.setString(
        _featureCountPrefKey,
        jsonEncode(_featureCounts),
      );
    } catch (e) {
      AppLogger.w('TelemetryService', 'Failed to persist feature counts: $e');
    }
  }

  Future<void> _loadLiteFlag() async {
    final prefs = testPrefs ?? await SharedPreferences.getInstance();
    _liteTouchpointEnabled = prefs.getBool(_liteFlagPrefKey) ?? true;
    final fetchedStr = prefs.getString(_liteFlagFetchedAtPrefKey);
    if (fetchedStr != null) {
      _liteFlagFetchedAt = DateTime.tryParse(fetchedStr);
    }
  }

  Future<void> _persistLiteFlag() async {
    try {
      final prefs = testPrefs ?? await SharedPreferences.getInstance();
      await prefs.setBool(_liteFlagPrefKey, _liteTouchpointEnabled);
      if (_liteFlagFetchedAt != null) {
        await prefs.setString(
          _liteFlagFetchedAtPrefKey,
          _liteFlagFetchedAt!.toIso8601String(),
        );
      }
    } catch (e) {
      AppLogger.w('TelemetryService', 'Failed to persist lite flag: $e');
    }
  }

  /// SHA-256 prefix of the server host. Used by [logServerConnected] so that
  /// raw deployment addresses never enter the payload or log.
  static String _hashHost(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host ?? url;
    final digest = sha256.convert(utf8.encode(host));
    return digest.bytes
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Release the owned HTTP client. Singleton is never destroyed across the
  /// app lifecycle except in tests.
  @visibleForTesting
  void dispose() {
    _ownedClient?.close();
    _ownedClient = null;
    _initialized = false;
    _queue.clear();
    _featureCounts.clear();
  }

  /// Reset all in-memory state for a clean test run. Does NOT clear secure
  /// storage / prefs (test harness owns those via fakes).
  @visibleForTesting
  Future<void> resetForTesting() async {
    _flushing = false;
    _refreshingFlag = false;
    _ownedClient?.close();
    _ownedClient = null;
    _queue.clear();
    _featureCounts.clear();
    _installUuid = testInstallUuid;
    _liteTouchpointEnabled = true;
    _liteFlagFetchedAt = null;
    _initialized = false;
    _locale = 'en';
    _appVersion = testAppVersion ??
        const String.fromEnvironment('APP_VERSION', defaultValue: '0.0.1+1');
    _os = testOs ?? 'unknown';
  }
}

enum _SendStatus { success, transientFailure, permanentFailure }

/// Serializable telemetry event used by the on-disk queue.
class _TelemetryEvent {
  _TelemetryEvent({
    required this.eventType,
    required this.payload,
    required this.queuedAt,
  });

  final String eventType;
  final Map<String, Object?> payload;
  final DateTime queuedAt;

  Map<String, dynamic> toJson() => {
        'event_type': eventType,
        'payload': payload,
        'queued_at': queuedAt.toIso8601String(),
      };

  factory _TelemetryEvent.fromJson(Map<String, dynamic> json) {
    return _TelemetryEvent(
      eventType: json['event_type'] as String,
      payload: Map<String, Object?>.from(json['payload'] as Map? ?? const {}),
      queuedAt: DateTime.parse(json['queued_at'] as String),
    );
  }
}
