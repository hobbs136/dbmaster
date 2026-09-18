//! Sub-provider wrapping [ServerConnection] singleton for Provider-based UI reactivity.
//!
//! Exposes connection state, user profile, and action methods.
//! Registered as a sub-provider in [AppProvider].

import 'package:flutter/foundation.dart';
import '../services/embedded_server_service.dart';
import '../services/server_connection.dart';

class ServerConnectionProvider extends ChangeNotifier {
  final ServerConnection _service = ServerConnection();

  ServerConnectionState _connectionState = ServerConnectionState.disconnected;
  ServerUserProfile? _userProfile;
  String? _serverUrl;

  ServerConnectionProvider() {
    // perform an initial sync so the provider reflects
    // the singleton's current state at construction time. This matters for
    // embedded mode, where main.dart calls connectEmbedded() BEFORE the app
    // builds this provider (so the listener added below misses that
    // transition). Syncing here picks up the already-connected state.
    _syncFromService();
    _service.state.addListener(_onStateChanged);
  }

  // ── Getters ──

  ServerConnectionState get connectionState => _connectionState;
  ServerUserProfile? get userProfile => _userProfile;
  String? get serverUrl => _serverUrl;
  bool get isConnected => _connectionState == ServerConnectionState.connected;

  // expose embedded mode so the UI can show "Local mode"
  // instead of "Connected to <url>".
  bool get isEmbeddedMode => _service.isEmbeddedMode;

  // ── Actions ──

  /// Initialize the provider's session state.
  ///
  /// In embedded mode the singleton is already connected (main.dart called
  /// `connectEmbedded` before the provider existed), so there's nothing to
  /// restore. In remote mode, attempt to restore a previously-stored session so
  /// the user doesn't have to re-enter credentials after an app restart.
  // this is the first production callsite of
  // tryRestoreSession (previously defined but unused). Remote-mode users now
  // auto-reconnect on restart; embedded mode skips it.
  Future<void> initialize() async {
    if (_service.isEmbeddedMode) return; // already connected, nothing to restore
    if (_service.connectionState == ServerConnectionState.connected) return;
    await tryRestoreSession();
  }

  /// Attempt to restore a previous session on provider init. Returns whether
  /// the stored refresh token yielded a live session (the connect dialog's
  /// one-click reconnect surfaces a fallback error when it did not).
  Future<bool> tryRestoreSession() async {
    final restored = await _service.restoreSession();
    if (restored) {
      _syncFromService();
    }
    return restored;
  }

  /// Connect to a DbMaster server.
  Future<void> connect(String url, String email, String password) async {
    // U12：embedded → 远程切换时停掉本地子进程，避免远程会话下后台
    // data_sync/drift 调度器继续对本地库写入。
    if (_service.isEmbeddedMode) {
      await EmbeddedServerService.instance.stop();
    }
    await _service.connect(url, email, password);
    _syncFromService();
  }

  /// Disconnect from the server.
  Future<void> disconnect() async {
    // U12：embedded 模式的 Disconnect 同时停子进程——否则后台任务
    // （data_sync 等）在用户以为已断开后继续跑。
    final wasEmbedded = _service.isEmbeddedMode;
    await _service.disconnect();
    if (wasEmbedded) {
      await EmbeddedServerService.instance.stop();
    }
    _syncFromService();
  }

  /// Directly set the connection state for widget testing, bypassing the
  /// [ServerConnection] singleton. Call [notifyListeners] after setting.
  @visibleForTesting
  void setTestState({
    ServerConnectionState? connectionState,
    ServerUserProfile? userProfile,
    String? serverUrl,
    bool? embedded,
  }) {
    if (connectionState != null) _connectionState = connectionState;
    if (userProfile != null) _userProfile = userProfile;
    if (serverUrl != null) _serverUrl = serverUrl;
    if (embedded != null) _service.setEmbeddedModeForTesting(embedded);
    notifyListeners();
  }

  /// Get a valid access token for API calls.
  Future<String?> getAccessToken() => _service.getAccessToken();

  // ── Internal ──

  void _onStateChanged() {
    _syncFromService();
  }

  void _syncFromService() {
    _connectionState = _service.connectionState;
    _userProfile = _service.userProfile;
    _serverUrl = _service.serverUrl;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.state.removeListener(_onStateChanged);
    // ServerConnection 是全局单例，provider 只借用它的 state；此处不得 dispose
    // 单例，否则后续新建 provider 会读到已 disposed 的 ValueNotifier。
    // 单例的 dispose 由 app 关停路径负责。
    super.dispose();
  }
}
