//! Server connection service — manages authentication, heartbeat, and session persistence.
//!
//! Communicates with the DbMaster server (dbmaster-server) via REST API.
//! Access tokens are never persisted; refresh tokens are stored in secure storage.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/app_logger.dart';
import '../utils/version_compare.dart';
import 'telemetry_service.dart';

/// Connection state machine.
enum ServerConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// Lightweight user profile received from the server.
class ServerUserProfile {
  final String id;
  final String email;
  final String displayName;

  const ServerUserProfile({
    required this.id,
    required this.email,
    required this.displayName,
  });

  factory ServerUserProfile.fromJson(Map<String, dynamic> json) {
    return ServerUserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String,
    );
  }
}

/// Singleton service managing the connection to a DbMaster team server.
///
/// ## Usage
/// ```dart
/// final conn = ServerConnection();
/// await conn.connect('https://myserver:3000', 'user@example.com', 'password');
/// // conn.connectionState is now ServerConnectionState.connected
/// await conn.disconnect();
/// ```
class ServerConnection {
  static final ServerConnection _instance = ServerConnection._();
  factory ServerConnection() => _instance;

  ServerConnection._();

  /// Test-only injection for the HTTP client. When set, used instead of
  /// creating a new [http.Client] in [connect] and [restoreSession].
  @visibleForTesting
  http.Client? testHttpClient;

  /// Test-only injection for secure storage. When set, used instead of
  /// the default [FlutterSecureStorage].
  @visibleForTesting
  FlutterSecureStorage? testSecureStorage;

  FlutterSecureStorage get _storage =>
      testSecureStorage ?? const FlutterSecureStorage();

  static const _serverUrlKey = 'server_url';
  static const _refreshTokenKey = 'server_refresh_token';
  static const _emailKey = 'server_email';

  // U12 模式持久化：用户显式登录过远程 server 后记录 'remote'，下次启动跳过
  // embedded 自动拉起、直接恢复远程会话；无记录 = 默认 embedded。远程登出
  // （disconnect）时删除，回到默认。
  static const _preferredModeKey = 'server_preferred_mode';
  static const _remoteModeValue = 'remote';

  // ── HTTP client ──
  http.Client? _client;
  bool _ownsClient = true;

  // ── State ──
  final _stateController = ValueNotifier<ServerConnectionState>(
    ServerConnectionState.disconnected,
  );
  ValueListenable<ServerConnectionState> get state => _stateController;
  ServerConnectionState get connectionState => _stateController.value;

  // ── Connection details ──
  String? _baseUrl;
  String? get serverUrl => _baseUrl;

  // ── Server version（U15：握手 version 原本只进一条日志就丢）──
  // embedded 模式来自握手；远程模式连接后 best-effort 拉 /api/instance。
  String? _serverVersion;
  String? get serverVersion => _serverVersion;

  bool _serverVersionOutdated = false;

  /// 所连 server 是否低于客户端要求的最低兼容版本。
  bool get serverVersionOutdated => _serverVersionOutdated;

  /// 客户端要求的最低兼容 server 版本（Cargo 语义化版本，与 /api/instance、
  /// 握手的 version 同源）。升 server 端契约（API/握手字段）时同步抬此值。
  static const String minCompatibleServerVersion = '0.1.0';

  String? _accessToken;
  String? _refreshToken;

  /// Single-flight guard for the access-token refresh POST so concurrent API
  /// callers share one request instead of firing N parallel refreshes.
  Future<void>? _refreshInFlight;

  // embedded mode flag. When true, heartbeat failures
  // route to "restart the embedded child process" via EmbeddedServerService
  // instead of the remote-mode "refresh token via /api/auth/refresh" path.
  bool _embeddedMode = false;
  bool get isEmbeddedMode => _embeddedMode;

  /// Test hook (invoked via ServerConnectionProvider.setTestState): flip the
  /// embedded flag without spawning a child process. Intentionally not
  /// @visibleForTesting — the provider's own test-only setter calls it.
  void setEmbeddedModeForTesting(bool enabled) => _embeddedMode = enabled;

  ServerUserProfile? _userProfile;
  ServerUserProfile? get userProfile => _userProfile;

  // ── Heartbeat ──
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  static const Duration _initialReconnectDelay = Duration(seconds: 1);

  // ── Public API ──

  /// Connect to a DbMaster server.
  ///
  /// Sends `POST /api/auth/login`, stores tokens and user profile,
  /// and starts a periodic heartbeat.
  Future<void> connect(String url, String email, String password) async {
    if (_stateController.value == ServerConnectionState.connecting) return;
    // 远程登录路径——显式退出 embedded 语义（否则上一会话的 embedded 标志
    // 残留：心跳失败会走错重启分支、access token 永不主动刷新）。
    _embeddedMode = false;

    _stateController.value = ServerConnectionState.connecting;
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    try {
      if (_ownsClient) {
        _client?.close();
      }
      _client = testHttpClient ?? http.Client();
      _ownsClient = testHttpClient == null;

      final response = await _client!.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = body['access_token'] as String;
        _refreshToken = body['refresh_token'] as String;
        _userProfile = ServerUserProfile.fromJson(
          body['user'] as Map<String, dynamic>,
        );

        // Persist refresh token and server URL for session restoration
        await _storage.write(key: _serverUrlKey, value: _baseUrl);
        await _storage.write(key: _refreshTokenKey, value: _refreshToken);
        // Remember the email so the connect dialog can prefill it on the next
        // sign-in (only the password needs re-entry after a session expiry).
        await _storage.write(key: _emailKey, value: email);
        // U12：记住远程偏好，下次启动不再被 embedded 自动拉起抢占。
        await _storage.write(key: _preferredModeKey, value: _remoteModeValue);

        _stateController.value = ServerConnectionState.connected;
        _reconnectAttempt = 0;
        _startHeartbeat();

        AppLogger.i('ServerConnection',
          'Connected to server at $_baseUrl as ${_userProfile!.email}',
        );
        TelemetryService.instance.logServerConnected(_baseUrl!);
        // U15：best-effort 拉取 server 版本（远程握手不带，/api/instance 免认证）。
        unawaited(fetchInstanceVersion());
      } else if (response.statusCode == 401) {
        _cleanup();
        throw ServerConnectionException('Invalid email or password.');
      } else {
        _cleanup();
        throw ServerConnectionException(
          'Server returned ${response.statusCode}.',
        );
      }
    } catch (e) {
      if (e is ServerConnectionException) rethrow;
      _cleanup();
      throw ServerConnectionException(
        'Could not reach server at $_baseUrl. Check the URL and try again.',
      );
    }
  }

  /// Disconnect from the server.
  ///
  /// Clears all tokens, stops heartbeat, and reverts to disconnected state.
  /// Remote mode = sign-out（凭据 + 远程偏好一并清除，下次启动回默认 embedded）；
  /// embedded 模式下不触碰存储的远程会话（那里可能存着尚未使用的远程凭据，
  /// 且远程偏好不属于本地模式的退出语义）。
  Future<void> disconnect() async {
    final wasEmbedded = _embeddedMode;
    _cleanup();
    _baseUrl = null;
    if (!wasEmbedded) {
      await _storage.delete(key: _serverUrlKey);
      await _storage.delete(key: _refreshTokenKey);
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _preferredModeKey);
    }
    _stateController.value = ServerConnectionState.disconnected;
    AppLogger.i('ServerConnection', 'Disconnected from server');
  }

  /// The last stored remote session, for prefilling the connect dialog and
  /// offering one-click reconnect after a disconnect. Returns `null` when no
  /// server URL was ever stored (or the secure store is unavailable).
  Future<({String url, String? email, bool hasRefreshToken})?>
      readStoredSession() async {
    try {
      final url = await _storage.read(key: _serverUrlKey);
      if (url == null || url.isEmpty) return null;
      final email = await _storage.read(key: _emailKey);
      final rt = await _storage.read(key: _refreshTokenKey);
      return (
        url: url,
        email: (email == null || email.isEmpty) ? null : email,
        hasRefreshToken: rt != null && rt.isNotEmpty,
      );
    } catch (e) {
      // Unavailable plugin (e.g. widget tests without a storage mock) must
      // not break opening the dialog — behave as "no stored session".
      AppLogger.w('ServerConnection', 'readStoredSession failed: $e');
      return null;
    }
  }

  /// The persisted mode preference, for main.dart's startup decision:
  /// `'remote'` = the user explicitly signed in to a remote server before, so
  /// skip the embedded auto-start and restore the remote session instead;
  /// `null` = no preference yet, keep the embedded-first default. Storage
  /// failures behave as "no preference" (embedded default stays safe).
  Future<String?> readPreferredMode() async {
    try {
      return await _storage.read(key: _preferredModeKey);
    } catch (e) {
      AppLogger.w('ServerConnection', 'readPreferredMode failed: $e');
      return null;
    }
  }

  // ── Auth-failure signaling ──

  /// Count of auth failures (HTTP 401 on an authenticated API call) reported
  /// by the API services. The UI listens to this to surface a single
  /// "session expired — sign in again" prompt even when several parallel
  /// calls fail at once.
  final ValueNotifier<int> _authFailures = ValueNotifier(0);
  ValueListenable<int> get authFailures => _authFailures;

  /// Called by API services right before they throw their `*ApiAuthException`.
  void reportAuthFailure() {
    // A "please reconnect" prompt makes no sense for a local embedded server —
    // self-heal instead with a best-effort refresh. The 401 means our access
    // token went stale (embedded uses the same 15m/7d JWT pair as remote mode,
    // ADR-0003 S2); a rejected refresh escalates to a child restart inside
    // [_doRefreshAccessToken], so no user action is ever needed.
    if (_embeddedMode) {
      unawaited(_refreshAccessToken());
      return;
    }
    _authFailures.value++;
  }

  // ── Embedded mode (ADR-0003 S2b) ──

  /// Restart callback invoked when the embedded child dies and the heartbeat
  /// notices the loss. Set by [EmbeddedServerService.applyTo] so this class
  /// doesn't import (and cycle with) that service.
  // invert the dependency: the connection calls a
  // callback it doesn't own, rather than importing EmbeddedServerService.
  Future<bool> Function()? embeddedRestartHandler;

  /// Wire up a connection to an embedded (in-process-spawned) server.
  ///
  /// Bypasses the [connect] login POST — the server's `--embedded` mode hands
  /// us a token directly via the stdout handshake. Sets the base URL to the
  /// loopback port, stores the token pair, and starts the heartbeat.
  // the embedded path: no email/password, no secure
  // storage of remote creds (the embedded server's own SQLite holds state).
  void connectEmbedded({
    required int port,
    required String accessToken,
    required String refreshToken,
    required String installUuid,
    required String version,
  }) {
    _embeddedMode = true;
    _baseUrl = 'http://127.0.0.1:$port';
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    // The embedded server synthesizes a single user (email embedded@local);
    // we don't GET /api/me to avoid an extra round-trip at startup — the token
    // already authorizes every API call.
    _userProfile = const ServerUserProfile(
      id: 'embedded',
      email: 'embedded@local',
      displayName: 'Local User',
    );
    if (_ownsClient) {
      _client?.close();
    }
    _client = testHttpClient ?? http.Client();
    _ownsClient = testHttpClient == null;

    _stateController.value = ServerConnectionState.connected;
    _reconnectAttempt = 0;
    _startHeartbeat();
    _serverVersion = version;
    _checkServerVersion();
    AppLogger.i('ServerConnection',
        'Connected to embedded server at $_baseUrl (v$version)');
    TelemetryService.instance.logServerConnected(_baseUrl!);
  }

  /// Best-effort 拉取 `/api/instance`（免认证）补全远程 server 版本。
  /// 失败不影响连接——版本展示退化为「未知」。connect/restoreSession 连接
  /// 成功后 fire-and-forget 调用；测试可直接 await。
  Future<void> fetchInstanceVersion() async {
    final base = _baseUrl;
    final client = _client;
    if (base == null || client == null) return;
    try {
      final resp = await client
          .get(Uri.parse('$base/api/instance'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = body['data'];
      if (data is Map<String, dynamic>) {
        final version = data['version'];
        if (version is String && version.isNotEmpty) {
          _serverVersion = version;
          _checkServerVersion();
          AppLogger.i('ServerConnection', 'Remote server version: $version');
        }
      }
    } catch (e) {
      AppLogger.w('ServerConnection', 'fetch /api/instance failed: $e');
    }
  }

  void _checkServerVersion() {
    final v = _serverVersion;
    if (v == null) return;
    final cmp = compareVersions(v, minCompatibleServerVersion);
    // null = 跨风格不可比（如日期 tag），不误报。
    _serverVersionOutdated = cmp != null && cmp < 0;
    if (_serverVersionOutdated) {
      AppLogger.w('ServerConnection',
          'Server version $v is below the minimum compatible '
          '$minCompatibleServerVersion — some features may misbehave; '
          'please upgrade dbmaster-server');
    }
  }

  /// Called by [EmbeddedServerService] when the child has died permanently
  /// (restart attempts exhausted). Flips state to disconnected so the UI
  /// reflects the loss.
  // terminal failure signal from the process owner.
  void markEmbeddedLost() {
    _cleanup();
    _baseUrl = null;
    _stateController.value = ServerConnectionState.disconnected;
    AppLogger.e('ServerConnection',
      'Embedded server lost permanently; state → disconnected');
  }

  /// Attempt to restore a previous session using the stored refresh token.
  ///
  /// Returns `true` if the session was successfully restored.
  Future<bool> restoreSession() async {
    final url = await _storage.read(key: _serverUrlKey);
    final token = await _storage.read(key: _refreshTokenKey);
    if (url == null || token == null) return false;

    _baseUrl = url;
    _stateController.value = ServerConnectionState.connecting;

    try {
      if (_ownsClient) {
        _client?.close();
      }
      _client = testHttpClient ?? http.Client();
      _ownsClient = testHttpClient == null;

      final response = await _client!.post(
        Uri.parse('$_baseUrl/api/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': token}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = body['access_token'] as String;
        _refreshToken = body['refresh_token'] as String;

        await _storage.write(key: _refreshTokenKey, value: _refreshToken);
        // U12 补丁：恢复成功即记住 remote 偏好。只靠 connect() 写会让
        // 「从未重新登录、一直走会话恢复」的用户每次启动都被 embedded
        // 默认抢占（恢复路径表达了明确的 remote 意图，与登录等价）。
        await _storage.write(key: _preferredModeKey, value: _remoteModeValue);

        // Fetch user profile
        final meResp = await _client!.get(
          Uri.parse('$_baseUrl/api/me'),
          headers: _authHeaders(),
        );
        if (meResp.statusCode == 200) {
          final meBody = jsonDecode(meResp.body) as Map<String, dynamic>;
          _userProfile = ServerUserProfile.fromJson(meBody);
        }

        _stateController.value = ServerConnectionState.connected;
        _reconnectAttempt = 0;
        _startHeartbeat();
        AppLogger.i('ServerConnection', 'Session restored for ${_userProfile?.email ?? "unknown"}');
        TelemetryService.instance.logServerConnected(_baseUrl!);
        unawaited(fetchInstanceVersion());
        return true;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Refresh token rejected by the server — the stored session is
        // genuinely invalid, drop it (disconnect also clears secure storage).
        await disconnect();
        return false;
      } else {
        // Transient server error (5xx / restart in progress): keep the stored
        // credentials so a later retry can still restore the session.
        _cleanup();
        _stateController.value = ServerConnectionState.disconnected;
        return false;
      }
    } catch (e) {
      // Server unreachable: keep stored credentials, but fall back to
      // `disconnected` — previously this left the state stuck at `connecting`
      // forever, and the status pill is not clickable in that state.
      AppLogger.w('ServerConnection', 'Session restore failed: $e');
      _cleanup();
      _stateController.value = ServerConnectionState.disconnected;
      return false;
    }
  }

  /// Get the current access token, refreshing if needed.
  ///
  /// Both modes decode the JWT `exp` claim and refresh proactively when the
  /// access token is expired or within 60s of expiry. Remote mode refreshes the
  /// 15-minute access token via the stored refresh token; without this every
  /// API call 401s after 15 minutes even though a valid refresh token is on
  /// hand (the heartbeat pings the unauthenticated `/api/health`, so it never
  /// notices). Embedded mode uses the identical 15m/7d handshake pair
  /// (ADR-0003 S2) — an embedded app left open past the access token's TTL
  /// used to 401 every server API until restart. Newer servers mint far-future
  /// embedded access tokens, so in practice the refresh path stays dormant
  /// there; it is what keeps older embedded servers working.
  ///
  /// Embedded refreshes only on *provable* near-expiry (decodable `exp`): an
  /// undecodable token must not trigger a refresh on every call — auth routes
  /// are rate-limited, and a genuinely stale unknown token is covered by the
  /// reactive 401 → [reportAuthFailure] refresh.
  ///
  /// Returns `null` if not connected.
  Future<String?> getAccessToken() async {
    if (_stateController.value != ServerConnectionState.connected) return null;

    final exp = _jwtExpiryEpoch(_accessToken);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_embeddedMode) {
      if (exp != null && exp - now <= 60 && _refreshToken != null) {
        await _refreshAccessToken();
      }
      return _accessToken;
    }
    if ((exp == null || exp - now <= 60) && _refreshToken != null) {
      await _refreshAccessToken();
    }
    return _accessToken;
  }

  /// Best-effort decode of the JWT `exp` claim. The signature is not verified
  /// here — the server verifies it; this only decides when to refresh.
  static int? _jwtExpiryEpoch(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is int) return exp;
      if (exp is num) return exp.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshAccessToken() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _doRefreshAccessToken();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<void> _doRefreshAccessToken() async {
    final token = _refreshToken;
    final base = _baseUrl;
    if (token == null || base == null || _client == null) return;
    try {
      final response = await _client!
          .post(
            Uri.parse('$base/api/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': token}),
          )
          // T29 走查：刷新无超时会成为网关联调的硬挂起点（子进程卡死时
          // 上游每个请求都先在这里等）。10s 覆盖本地 embedded 重启窗口。
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = body['access_token'] as String?;
        final newRefresh = body['refresh_token'] as String?;
        if (newRefresh != null && newRefresh.isNotEmpty) {
          _refreshToken = newRefresh;
          // Embedded tokens are memory-only: the same storage slot may hold a
          // remote session's refresh token, which an embedded value would
          // clobber (and later poison the remote restore with a 401).
          if (!_embeddedMode) {
            await _storage.write(key: _refreshTokenKey, value: newRefresh);
          }
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        if (_embeddedMode) {
          // A rejected refresh within one embedded boot is unexpected (the
          // handshake pair is fresh and rotates on use). Treat it as a child
          // that needs re-handshaking rather than dropping the session — the
          // restart mints a new pair and reconnects via connectEmbedded.
          AppLogger.w('ServerConnection',
              'Embedded refresh token rejected; restarting embedded server');
          if (_stateController.value == ServerConnectionState.connected) {
            _stateController.value = ServerConnectionState.reconnecting;
            _scheduleEmbeddedRestart();
          }
          return;
        }
        AppLogger.w('ServerConnection',
            'Refresh token rejected; dropping session');
        await disconnect();
      }
      // Other statuses (5xx) and network errors keep the current tokens; the
      // next getAccessToken() call retries the refresh.
    } catch (e) {
      AppLogger.w('ServerConnection', 'Token refresh failed: $e');
    }
  }

  // ── Heartbeat ──

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _heartbeat());
  }

  Future<void> _heartbeat() async {
    try {
      final resp = await _client!.get(Uri.parse('$_baseUrl/api/health'));
      if (resp.statusCode != 200) {
        _handleHeartbeatFailure();
      } else {
        // Successful heartbeat — if we were reconnecting, transition back
        if (_stateController.value == ServerConnectionState.reconnecting) {
          _stateController.value = ServerConnectionState.connected;
          _reconnectAttempt = 0;
        }
      }
    } catch (_) {
      _handleHeartbeatFailure();
    }
  }

  void _handleHeartbeatFailure() {
    if (_stateController.value != ServerConnectionState.connected) return;
    // embedded mode routes failures to "restart the
    // child process" instead of "refresh the remote token". The child's exit
    // watcher in EmbeddedServerService also independently triggers restart;
    // both paths converge on a fresh handshake + applyTo.
    if (_embeddedMode) {
      _stateController.value = ServerConnectionState.reconnecting;
      _scheduleEmbeddedRestart();
      return;
    }
    _stateController.value = ServerConnectionState.reconnecting;
    _reconnectAttempt = 0;
    _scheduleReconnect();
  }

  // embedded reconnect: invoke the restart handler set
  // by EmbeddedServerService. On success it calls connectEmbedded() again,
  // flipping state back to connected. On failure, escalate to markEmbeddedLost
  // via the service's own attempt counter.
  void _scheduleEmbeddedRestart() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 1), () async {
      final handler = embeddedRestartHandler;
      if (handler == null) {
        markEmbeddedLost();
        return;
      }
      try {
        final ok = await handler();
        if (!ok) {
          // The handler's restart() is a single attempt and does not escalate
          // on its own — flip to disconnected here so the UI is not stuck at
          // `reconnecting` forever (that pill is not clickable).
          markEmbeddedLost();
        }
      } catch (_) {
        markEmbeddedLost();
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      AppLogger.w('ServerConnection',
        'Server connection lost after $_maxReconnectAttempts attempts',
      );
      _cleanup();
      _stateController.value = ServerConnectionState.disconnected;
      return;
    }

    final delay = _initialReconnectDelay * (1 << _reconnectAttempt);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      _reconnectAttempt++;
      try {
        final restored = await restoreSession();
        if (!restored) {
          _scheduleReconnect();
        }
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  // ── Internal ──

  Map<String, String> _authHeaders() {
    return {
      'Content-Type': 'application/json',
      if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
    };
  }

  void _cleanup() {
    if (_ownsClient) {
      _client?.close();
    }
    _client = null;
    _ownsClient = true;
    _accessToken = null;
    _refreshToken = null;
    _userProfile = null;
    _serverVersion = null;
    _serverVersionOutdated = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    // reset embedded-mode bookkeeping so a later
    // connect() (remote) isn't treated as embedded.
    _embeddedMode = false;
  }

  /// Reset singleton state for clean test runs.
  @visibleForTesting
  static void resetForTesting() {
    _instance._cleanup();
    _instance._stateController.value = ServerConnectionState.disconnected;
    _instance._baseUrl = null;
    _instance._reconnectAttempt = 0;
    _instance._authFailures.value = 0;
    _instance.testHttpClient = null;
    _instance.testSecureStorage = null;
    _instance.embeddedRestartHandler = null;
    _instance._serverVersion = null;
    _instance._serverVersionOutdated = false;
  }

  /// Release resources. Call when the app is shutting down.
  void dispose() {
    _cleanup();
    _stateController.dispose();
  }
}

/// Exception thrown by [ServerConnection] on connection/auth failures.
class ServerConnectionException implements Exception {
  final String message;
  const ServerConnectionException(this.message);

  @override
  String toString() => 'ServerConnectionException: $message';
}
