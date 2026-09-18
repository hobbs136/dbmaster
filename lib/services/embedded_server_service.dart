//! Embedded server lifecycle manager (ADR-0003 S2b).
//!
// Spawns the dbmaster-server binary in `--embedded` mode as a child process,
//! reads the stdout handshake line to learn the assigned port + access token,
//! injects them into the [ServerConnection] singleton (so all existing API
//! services — data_sync / drift / telemetry — work unchanged), monitors the
//! child for crashes and auto-restarts, and tears it down on app exit.
//!
//! ## Handshake contract (server side, ADR-0003 S2)
//! On `--embedded` startup the server prints ONE JSON line to stdout (all
//! logging goes to stderr):
//! ```json
//! {"type":"dbmaster_embedded_ready","port":54321,
//!  "access_token":"...","refresh_token":"...","install_uuid":"...","version":"..."}
//! ```
//! The child shuts down when its stdin closes (parent gone) or on SIGINT.
//!
//! ## Mode selection
//! Auto-detect: if a server binary is found beside the app exe (or via the
//! `DBMASTER_SERVER_BIN` env var in dev), the app runs in embedded mode; if
//! not, the caller silently falls back to the existing remote-server connect
//! flow. See [locateBinary].
//!
//! ## Singleton + lifecycle
//! Singleton like [TelemetryService]: call [start] once at app startup (in
//! `main.dart`), [applyTo] to wire the connection, and [stop] on app exit.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import 'server_connection.dart';

/// Outcome of an embedded-server start attempt.
enum EmbeddedStartResult {
  /// Server spawned and handshake received.
  started,
  /// No server binary found — caller should fall back to remote mode.
  binaryNotFound,
  /// Binary found but spawn or handshake failed.
  failed,
}

/// Parsed stdout handshake payload from the embedded server.
@immutable
class EmbeddedHandshake {
  final int port;
  final String accessToken;
  final String refreshToken;
  final String installUuid;
  final String version;

  const EmbeddedHandshake({
    required this.port,
    required this.accessToken,
    required this.refreshToken,
    required this.installUuid,
    required this.version,
  });

  /// Parse the single stdout handshake line. Returns `null` on any shape error
  /// (caller treats null as a handshake failure).
  static EmbeddedHandshake? parse(String line) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      if (json['type'] != 'dbmaster_embedded_ready') return null;
      final port = json['port'];
      if (port is! int || port <= 0) return null;
      final access = json['access_token'];
      final refresh = json['refresh_token'];
      final uuid = json['install_uuid'];
      final version = json['version'];
      if (access is! String ||
          refresh is! String ||
          uuid is! String ||
          version is! String) {
        return null;
      }
      if (access.isEmpty || refresh.isEmpty) return null;
      return EmbeddedHandshake(
        port: port,
        accessToken: access,
        refreshToken: refresh,
        installUuid: uuid,
        version: version,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Singleton that owns the embedded server child process.
///
/// Mirrors the structural conventions of [TelemetryService]: private
/// constructor, `instance` getter, idempotent entry point, `@visibleForTesting`
/// injection seams + `resetForTesting`.
class EmbeddedServerService {
  static final EmbeddedServer _delegate = EmbeddedServer();
  static EmbeddedServerService? _instance;

  EmbeddedServerService._();

  /// The shared [EmbeddedServerService] instance.
  // `instance` getter (not a factory) so callers write
  // `EmbeddedServerService.instance`, matching the TelemetryService precedent.
  static EmbeddedServerService get instance =>
      _instance ??= EmbeddedServerService._();

  /// Underlying delegate. Exposed so tests can drive a fake.
  @visibleForTesting
  EmbeddedServer get delegate => _delegate;

  /// Whether the embedded server is currently running (a live child process).
  bool get isRunning => _delegate.isRunning;

  /// The most recent handshake, if any. Null before a successful [start] / after [stop].
  EmbeddedHandshake? get handshake => _delegate.handshake;

  /// Locate and start the embedded server. Does NOT touch [ServerConnection];
  /// call [applyTo] afterwards to wire the connection singleton.
  ///
  /// Returns [EmbeddedStartResult.started] on success,
  /// [EmbeddedStartResult.binaryNotFound] to signal the caller to fall back to
  /// remote-server mode, [EmbeddedStartResult.failed] on spawn/handshake error.
  Future<EmbeddedStartResult> start({Duration handshakeTimeout = const Duration(seconds: 15)}) =>
      _delegate.start(handshakeTimeout: handshakeTimeout);

  /// Wire the current handshake into the [ServerConnection] singleton.
  /// No-op if [handshake] is null (i.e. [start] didn't succeed).
  void applyTo(ServerConnection conn) => _delegate.applyTo(conn);

  /// Tear down the child process (close stdin → server's EOF shutdown path,
  /// wait, then kill if it doesn't exit). Safe to call multiple times.
  Future<void> stop() => _delegate.stop();

  /// vault 无界增长根治②（P1）：E2E 数据目录隔离——首次 [start] 前调用，
  /// 之后 embedded server 在一次性系统临时目录上跑（与生产
  /// `<AppSupport>/embedded-server` 分家），[stop] 后递归清理。幂等。
  /// 见 [EmbeddedServer.useIsolatedDataDir]。
  Future<void> useIsolatedDataDir() => _delegate.useIsolatedDataDir();

  /// Restart the child after an unexpected exit. Public so [ServerConnection]
  /// can trigger a restart from its embedded-mode heartbeat-failure path.
  Future<bool> restart() => _delegate.restart();

  /// Reset for clean test runs.
  @visibleForTesting
  static void resetForTesting() {
    _delegate.resetForTesting();
    _instance = null;
  }
}

/// The actual process owner. Split from the singleton so tests can swap a fake.
class EmbeddedServer {
  Process? _process;
  bool _stopping = false;
  EmbeddedHandshake? _handshake;
  // The directory passed to the server's --data-dir. Kept so restarts reuse it.
  String? _dataDir;
  // vault 无界增长根治②（P1）：E2E 隔离数据目录（一次性系统临时目录）。
  // 非空 = 本对象拥有清理责任（stop/resetForTesting 时递归删除）。
  Directory? _isolatedDir;
  // _doRestart 内部复用 stop()，但重启要在同一数据目录上再起——置位
  // 抑制 stop() 的隔离目录清理（否则 crash-restart 静默清空 vault）。
  bool _restarting = false;
  // Cancellation for the stdout handshake waiter so stop() can unblock it.
  Timer? _handshakeTimeout;
  Completer<EmbeddedHandshake>? _handshakeCompleter;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  int _restartAttempts = 0;
  static const int _maxRestartAttempts = 5;

  // U12 双通道竞态守卫：spawn 入口同步旗标 + 在飞 restart 单飞。两条重启通道
  // （崩溃退避 _autoRestartWithBackoff / 心跳触发的 restart()）与 stop() 并发
  // 交错时，旧逻辑可在同一 --data-dir 上产出孤儿双子进程（双 data_sync 调度器
  // 同库双跑）。_spawning 在任何 await 之前同步置位，第二个到达者直接退出。
  bool _spawning = false;
  Future<bool>? _spawnFuture;
  Future<bool>? _restartInFlight;

  bool get isRunning => _process != null;

  EmbeddedHandshake? get handshake => _handshake;

  /// 测试缝：当前将用/已用的 --data-dir（隔离目录断言用；生产勿读）。
  @visibleForTesting
  String? get debugDataDir => _dataDir;

  // ── Binary discovery ──

  /// The expected binary name for the current platform.
  static String get _binaryName {
    if (Platform.isWindows) return 'dbmaster-server.exe';
    if (Platform.isMacOS) return 'dbmaster-server';
    return 'dbmaster-server'; // linux
  }

  /// Locate the server binary, or `null` if not found.
  ///
  /// Search order:
  /// 1. `DBMASTER_SERVER_BIN` env var (dev override — points at the cargo
  ///    target dir, e.g. `../dbmaster-server/target/debug/dbmaster-server.exe`).
  /// 2. Beside the running app exe (`Platform.resolvedExecutable` dir) — the
  ///    production layout, where the build script copies dbmaster-server.exe
  ///    next to dbmaster.exe in `dist/<Mode>/`.
  ///
  /// Mirrors the same-dir convention historically used to locate `sybdb.dll`
  /// (retired with the FFI layer in T28; the convention now serves the server
  /// binary, which is a hard dependency for gateway-backed types — D6).
  @visibleForTesting
  File? locateBinary() {
    // 1. Env override (dev).
    final envPath = Platform.environment['DBMASTER_SERVER_BIN'];
    if (envPath != null && envPath.isNotEmpty) {
      final f = File(envPath);
      if (f.existsSync()) return f;
    }
    // 2. Beside the app exe (production / packaged dev build).
    final exeDir = File(Platform.resolvedExecutable).parent;
    final beside = File('${exeDir.path}${Platform.pathSeparator}$_binaryName');
    if (beside.existsSync()) return beside;
    return null;
  }

  // ── Lifecycle ──

  /// vault 无界增长根治②（P1）：E2E 数据目录隔离——预置一次性系统临时
  /// 目录，后续 [start]/[restart] 在其上跑（生产默认目录
  /// `<AppSupport>/embedded-server` 不受 E2E 污染）。幂等（同进程重复
  /// 调用复用同一目录）；进程已在跑/在 spawn 时为 no-op（数据目录随子
  /// 进程钉定）。清理责任归 [stop]/[resetForTesting]（递归删除；restart
  /// 不删）。
  Future<void> useIsolatedDataDir() async {
    if (_process != null || _spawning) {
      AppLogger.w('EmbeddedServer',
          'useIsolatedDataDir ignored: server already running/spawning');
      return;
    }
    final existing = _isolatedDir;
    if (existing != null) return;
    final dir = await Directory.systemTemp.createTemp('dbmaster-embedded-e2e-');
    _isolatedDir = dir;
    _dataDir = dir.path;
    AppLogger.i('EmbeddedServer', 'E2E isolated data dir: ${dir.path}');
  }

  /// 隔离目录清理（best-effort；仅 stop/resetForTesting 调，restart 抑制）。
  Future<void> _cleanupIsolatedDir() async {
    final dir = _isolatedDir;
    _isolatedDir = null;
    _dataDir = null;
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      AppLogger.w('EmbeddedServer', 'isolated dir cleanup skipped: $e');
    }
  }

  Future<EmbeddedStartResult> start({required Duration handshakeTimeout}) async {
    if (_process != null) return EmbeddedStartResult.started; // idempotent

    final binary = locateBinary();
    if (binary == null) {
      AppLogger.i('EmbeddedServer',
        'No server binary found beside app or via DBMASTER_SERVER_BIN; '
        'falling back to remote-server mode.');
      return EmbeddedStartResult.binaryNotFound;
    }

    // --data-dir: a stable subdir of the app support dir so connections /
    // credentials persist across restarts. Multiple app instances share it
    // (SQLite file-lock serializes; server-side INSERT OR IGNORE handles the
    // embedded-user row). E2E 经 useIsolatedDataDir 预置的临时目录优先
    // （_dataDir 已占位时跳过默认解析，也不触 path_provider）。
    if (_dataDir == null) {
      try {
        final support = await getApplicationSupportDirectory();
        _dataDir = '${support.path}${Platform.pathSeparator}embedded-server';
        await Directory(_dataDir!).create(recursive: true);
      } catch (e) {
        AppLogger.w('EmbeddedServer', 'Failed to resolve data dir: $e');
        return EmbeddedStartResult.failed;
      }
    }

    final ok = await _spawnAndHandshake(binary, _dataDir!, handshakeTimeout);
    if (!ok) return EmbeddedStartResult.failed;
    _restartAttempts = 0;
    AppLogger.i('EmbeddedServer',
      'Embedded server ready on port ${_handshake!.port} (v${_handshake!.version})');
    return EmbeddedStartResult.started;
  }

  /// Spawn entry with the twin guard: a live child or an in-flight spawn means
  /// someone is already bringing the server up — never spawn a second process
  /// against the same data dir. Returns true ("already satisfied") in that case.
  Future<bool> _spawnAndHandshake(
    File binary,
    String dataDir,
    Duration timeout,
  ) {
    if (_process != null || _spawning) return Future.value(true);
    _spawning = true;
    final future = _doSpawnAndHandshake(binary, dataDir, timeout).whenComplete(() {
      _spawning = false;
      _spawnFuture = null;
    });
    _spawnFuture = future;
    return future;
  }

  /// Spawn the process, wait for the handshake line, install the exit watcher.
  /// Returns true on success.
  Future<bool> _doSpawnAndHandshake(
    File binary,
    String dataDir,
    Duration timeout,
  ) async {
    _handshakeCompleter = Completer<EmbeddedHandshake>();
    _handshakeTimeout = Timer(timeout, () {
      if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
        AppLogger.w('EmbeddedServer', 'Handshake timed out after $timeout');
        _handshakeCompleter!.completeError(TimeoutException(
            'embedded server did not produce a handshake line', timeout));
      }
    });

    final Process proc;
    try {
      proc = await Process.start(
        binary.path,
        ['--embedded', '--data-dir', dataDir],
        // stdin piped so we can close it to trigger the server's EOF shutdown.
        // stdout piped to read the handshake; stderr piped (drained) to avoid
        // the child blocking when its stderr pipe buffer fills.
        mode: ProcessStartMode.normal,
      );
    } catch (e) {
      AppLogger.w('EmbeddedServer', 'Failed to spawn ${binary.path}: $e');
      _handshakeTimeout?.cancel();
      _handshakeTimeout = null;
      _handshakeCompleter = null;
      return false;
    }

    // stop() may have run while Process.start was awaiting — kill the newborn
    // instead of installing a child behind a completed teardown.
    if (_stopping) {
      AppLogger.i('EmbeddedServer',
          'Spawn aborted: stop requested while spawning');
      _handshakeTimeout?.cancel();
      _handshakeTimeout = null;
      _handshakeCompleter = null;
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
      return false;
    }
    _process = proc;

    // Read stdout line-by-line; resolve on the first handshake line.
    _stdoutSub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            final hs = EmbeddedHandshake.parse(line);
            if (hs != null &&
                _handshakeCompleter != null &&
                !_handshakeCompleter!.isCompleted) {
              _handshake = hs;
              _handshakeCompleter!.complete(hs);
            }
            // Non-handshake lines on stdout are unexpected (contract: only the
            // ready JSON goes to stdout). Log for diagnostics; don't fail.
            if (hs == null) {
              AppLogger.external('Server.stdout', line);
            }
          },
          onError: (e) {
            if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
              _handshakeCompleter!.completeError(e);
            }
          },
          onDone: () {
            // stdout closed before handshake → spawn failed (e.g. binary crashed
            // at startup). The exit watcher handles crash-restart if we already
            // had a handshake.
            if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
              _handshakeCompleter!.completeError(
                  StateError('embedded server stdout closed before handshake'));
            }
          },
          cancelOnError: true,
        );

    // Server 的 tracing 日志全部走 stderr（行式文本，main.rs:64-72）——逐行
    // 透传进 AppLogger 落盘（U14）。仍必须持续读，否则子进程会阻塞在写满的
    // stderr 管道缓冲上。allowMalformed：偶发非 UTF-8 字节不再炸流。
    _stderrSub = proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
          (line) => AppLogger.external('Server', line),
          onError: (Object e) =>
              AppLogger.w('EmbeddedServer', 'stderr read error: $e'),
        );

    try {
      await _handshakeCompleter!.future;
      _handshakeTimeout?.cancel();
      _handshakeTimeout = null;
    } catch (e) {
      _handshakeTimeout?.cancel();
      _handshakeTimeout = null;
      await _stdoutSub?.cancel();
      _stdoutSub = null;
      await _stderrSub?.cancel();
      _stderrSub = null;
      _process?.kill(ProcessSignal.sigkill);
      _process = null;
      AppLogger.w('EmbeddedServer', 'Handshake failed: $e');
      return false;
    }

    // stop() completed the handshake wait with an error, or flipped _stopping
    // after the handshake landed — let stop() own the teardown; don't install
    // the exit watcher (it would treat the imminent kill as a crash).
    if (_stopping) {
      await _stdoutSub?.cancel();
      _stdoutSub = null;
      await _stderrSub?.cancel();
      _stderrSub = null;
      _process?.kill(ProcessSignal.sigkill);
      _process = null;
      return false;
    }

    // Install the crash watcher now that we have a live, handshaked process.
    _watchExit();
    return true;
  }

  /// Monitor the child's exit future; on unexpected exit, auto-restart.
  void _watchExit() {
    final proc = _process;
    if (proc == null) return;
    // ignore: unawaited_futures — we attach .then, not await
    proc.exitCode.then((code) {
      // An exit we caused (stop/restart) or one belonging to a child that has
      // already been replaced by a respawn is not a crash of the current child.
      // Without the identity check, a stale watcher (e.g. exit delivered after
      // restart() respawned) would null the NEW child's state and schedule a
      // duplicate restart.
      if (_stopping || !identical(_process, proc)) return;
      AppLogger.w('EmbeddedServer',
          'Child process exited unexpectedly (code=$code); attempting restart.');
      _process = null;
      _handshake = null;
      _stdoutSub?.cancel();
      _stdoutSub = null;
      _stderrSub?.cancel();
      _stderrSub = null;
      // Auto-restart with backoff.
      unawaited(_autoRestartWithBackoff());
    });
  }

  Future<void> _autoRestartWithBackoff() async {
    if (_restartAttempts >= _maxRestartAttempts) {
      AppLogger.e('EmbeddedServer',
        'Exceeded $_maxRestartAttempts restart attempts; giving up. '
        'Connection will report disconnected.');
      // Flip the connection to disconnected so the UI reflects the loss.
      final conn = ServerConnection();
      conn.markEmbeddedLost();
      return;
    }
    _restartAttempts++;
    final delay = Duration(seconds: 1 << (_restartAttempts - 1)); // 1,2,4,8s
    AppLogger.i('EmbeddedServer',
      'Restart attempt $_restartAttempts/$_maxRestartAttempts in ${delay.inSeconds}s');
    await Future.delayed(delay);
    // Another channel (the heartbeat-driven restart()) may have respawned the
    // child while this backoff was sleeping — don't spawn a twin that would
    // run a second data_sync scheduler against the same SQLite data dir.
    if (_process != null) {
      AppLogger.i('EmbeddedServer', 'Restart skipped: child already running');
      return;
    }
    final binary = locateBinary();
    if (binary == null || _dataDir == null) {
      // Binary or data dir vanished mid-run — escalate instead of returning
      // silently (a silent return leaves the connection stuck at
      // `reconnecting`, whose status pill is not clickable).
      AppLogger.e('EmbeddedServer',
          'Restart aborted: server binary or data dir is missing');
      ServerConnection().markEmbeddedLost();
      return;
    }
    final ok = await _spawnAndHandshake(
        binary, _dataDir!, const Duration(seconds: 15));
    if (ok) {
      _restartAttempts = 0;
      // Re-apply the fresh handshake to the connection so API calls resume.
      applyTo(ServerConnection());
      AppLogger.i('EmbeddedServer',
        'Restarted; new port ${_handshake!.port}');
    } else {
      // Recurse to try again (up to _maxRestartAttempts).
      await _autoRestartWithBackoff();
    }
  }

  /// Restart on demand (e.g. from ServerConnection's embedded heartbeat path).
  ///
  /// Single-flight: concurrent callers (heartbeat timer, crash backoff, user
  /// action) share the in-flight restart instead of each running stop→spawn
  /// and racing each other into twin children.
  Future<bool> restart() {
    final existing = _restartInFlight;
    if (existing != null) return existing;
    final future = _doRestart().whenComplete(() => _restartInFlight = null);
    _restartInFlight = future;
    return future;
  }

  Future<bool> _doRestart() async {
    _restarting = true;
    try {
      await stop();
    } finally {
      _restarting = false;
    }
    _restartAttempts = 0;
    final binary = locateBinary();
    if (binary == null || _dataDir == null) return false;
    final ok = await _spawnAndHandshake(
        binary, _dataDir!, const Duration(seconds: 15));
    if (ok) {
      applyTo(ServerConnection());
      return true;
    }
    return false;
  }

  void applyTo(ServerConnection conn) {
    final hs = _handshake;
    if (hs == null) return;
    // Register the restart callback so ServerConnection's heartbeat-failure
    // path (embedded mode) can trigger a child restart without importing this
    // class (avoids a circular import).
    conn.embeddedRestartHandler = () => restart();
    conn.connectEmbedded(
      port: hs.port,
      accessToken: hs.accessToken,
      refreshToken: hs.refreshToken,
      installUuid: hs.installUuid,
      version: hs.version,
    );
  }

  Future<void> stop() async {
    _stopping = true;
    _handshakeTimeout?.cancel();
    _handshakeTimeout = null;
    // Unblock an in-flight handshake wait (its timer was just cancelled, so
    // nothing else would ever complete it) so the spawn future can settle…
    final pending = _handshakeCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('stop requested during handshake'));
      // …but the spawn may bail at its _stopping check without ever awaiting
      // this future — mark the error handled so it can't surface as an
      // unhandled async error (awaiting an ignored future still throws).
      pending.future.ignore();
    }
    // …then wait for that spawn to land before tearing down: it either
    // self-aborts (notices _stopping, kills the newborn) or installs a child
    // that the teardown below handles like any other.
    final spawn = _spawnFuture;
    if (spawn != null) {
      try {
        await spawn;
      } catch (_) {}
    }
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    await _stderrSub?.cancel();
    _stderrSub = null;
    final proc = _process;
    _process = null;
    if (proc == null) {
      _stopping = false;
      // 无进程可达（未起过/已停）：隔离目录仍按整停口径清理。
      if (!_restarting) await _cleanupIsolatedDir();
      return;
    }
    // Close stdin → triggers the server's stdin-EOF shutdown path (the
    // canonical parent-lifecycle signal per ADR-0003 S2).
    try {
      await proc.stdin.close();
    } catch (_) {
      // stdin may already be closed; ignore.
    }
    try {
      await proc.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      // Didn't exit gracefully in time → force kill.
      try {
        proc.kill(ProcessSignal.sigkill);
      } catch (_) {}
      try {
        await proc.exitCode;
      } catch (_) {}
    }
    _stopping = false;
    _handshake = null;
    // 隔离目录清理：仅整停（E2E tearDown）删——_doRestart 复用 stop()
    // 但要在同一目录再起（_restarting 抑制）。
    if (!_restarting) await _cleanupIsolatedDir();
  }

  void resetForTesting() {
    _stopping = true; // suppress auto-restart
    _handshakeTimeout?.cancel();
    _handshakeTimeout = null;
    final pending = _handshakeCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('reset during handshake'));
      pending.future.ignore();
    }
    _handshakeCompleter = null;
    _stdoutSub?.cancel();
    _stdoutSub = null;
    _stderrSub?.cancel();
    _stderrSub = null;
    _process?.kill(ProcessSignal.sigkill);
    _process = null;
    _handshake = null;
    _dataDir = null;
    // 隔离目录（若有）递归清理——sync 上下文 fire-and-forget。
    unawaited(_cleanupIsolatedDir());
    _restartAttempts = 0;
    _spawning = false;
    _spawnFuture = null;
    _restartInFlight = null;
    _stopping = false;
  }
}
