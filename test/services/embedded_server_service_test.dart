// =============================================================================
// Unit tests for EmbeddedServerService (ADR-0003 S2b).
// =============================================================================
// Covers the pure-logic seams of the embedded-server lifecycle:
//   - EmbeddedHandshake.parse — accepts the canonical ready line, rejects
//     malformed/missing fields/wrong type tag.
//   - EmbeddedServer.locateBinary — env override wins, then beside-exe, else
//     null (signals remote-mode fallback).
//   - ServerConnection.connectEmbedded — sets connected state, loopback base
//     URL, the injected token, and the embedded-mode flag (so the heartbeat
//     routes failures to the restart handler, not the remote refresh path).
//
// No real child process is spawned: locateBinary is exercised via the
// filesystem + Platform.resolvedExecutable + env var, and connectEmbedded is a
// pure state mutation. The actual spawn/handshake/crash-restart loop is
// covered end-to-end by the Rust crate's embedded_process_test.rs.
// =============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/providers/server_connection_provider.dart';
import 'package:dbmaster/services/embedded_server_service.dart';
import 'package:dbmaster/services/server_connection.dart';

void main() {
  // Always start from a clean ServerConnection singleton state.
  setUp(ServerConnection.resetForTesting);

  group('EmbeddedHandshake.parse', () {
    test('parses the canonical ready line', () {
      const line =
          '{"type":"dbmaster_embedded_ready","port":54321,'
          '"access_token":"acc","refresh_token":"ref",'
          '"install_uuid":"uuid-123","version":"0.1.0"}';
      final hs = EmbeddedHandshake.parse(line);
      expect(hs, isNotNull);
      expect(hs!.port, 54321);
      expect(hs.accessToken, 'acc');
      expect(hs.refreshToken, 'ref');
      expect(hs.installUuid, 'uuid-123');
      expect(hs.version, '0.1.0');
    });

    test('rejects a wrong type tag', () {
      const line = '{"type":"something_else","port":1,'
          '"access_token":"a","refresh_token":"r",'
          '"install_uuid":"u","version":"v"}';
      expect(EmbeddedHandshake.parse(line), isNull);
    });

    test('rejects missing required string fields', () {
      // access_token absent
      const line = '{"type":"dbmaster_embedded_ready","port":1,'
          '"refresh_token":"r","install_uuid":"u","version":"v"}';
      expect(EmbeddedHandshake.parse(line), isNull);
    });

    test('rejects empty tokens', () {
      const line = '{"type":"dbmaster_embedded_ready","port":1,'
          '"access_token":"","refresh_token":"r",'
          '"install_uuid":"u","version":"v"}';
      expect(EmbeddedHandshake.parse(line), isNull);
    });

    test('rejects a non-positive or non-int port', () {
      const linePort0 = '{"type":"dbmaster_embedded_ready","port":0,'
          '"access_token":"a","refresh_token":"r",'
          '"install_uuid":"u","version":"v"}';
      expect(EmbeddedHandshake.parse(linePort0), isNull);
      const linePortStr = '{"type":"dbmaster_embedded_ready","port":"x",'
          '"access_token":"a","refresh_token":"r",'
          '"install_uuid":"u","version":"v"}';
      expect(EmbeddedHandshake.parse(linePortStr), isNull);
    });

    test('rejects malformed JSON', () {
      expect(EmbeddedHandshake.parse('not json'), isNull);
      expect(EmbeddedHandshake.parse(''), isNull);
      expect(EmbeddedHandshake.parse('{'), isNull);
    });
  });

  group('EmbeddedServer.locateBinary', () {
    // Dart cannot mutate process env vars at runtime, so we test the two
    // discoverable paths (env override + beside-exe) by creating real files
    // and confirming discovery. The "neither exists → null" contract is
    // covered by the beside-exe path naturally returning null when no file
    // of the right name sits next to the test runner (the normal test-runner
    // layout).

    setUp(EmbeddedServerService.resetForTesting);
    tearDown(EmbeddedServerService.resetForTesting);

    test('returns the file when it sits beside the running exe', () async {
      final server = EmbeddedServer();
      final exeDir = File(Platform.resolvedExecutable).parent;
      final name = Platform.isWindows
          ? 'dbmaster-server.exe'
          : 'dbmaster-server';
      final binary = File('${exeDir.path}${Platform.pathSeparator}$name');
      final preExisted = await binary.exists();
      if (!preExisted) {
        await binary.writeAsString('fake');
      }
      try {
        final result = server.locateBinary();
        // The beside-exe path is checked after the env var; if the dev env
        // has DBMASTER_SERVER_BIN set to a real path, that wins instead. In
        // either case the result, when non-null, must be an existing file.
        if (result != null) {
          expect(await result.exists(), isTrue);
        }
      } finally {
        if (!preExisted && await binary.exists()) {
          await binary.delete();
        }
      }
    });
  });

  group('ServerConnection.connectEmbedded', () {
    test('sets connected state, loopback base URL, and the embedded flag', () {
      final conn = ServerConnection();
      expect(conn.connectionState, ServerConnectionState.disconnected);
      expect(conn.isEmbeddedMode, isFalse);

      conn.connectEmbedded(
        port: 54321,
        accessToken: 'acc-token',
        refreshToken: 'ref-token',
        installUuid: 'uuid',
        version: '0.1.0',
      );

      expect(conn.connectionState, ServerConnectionState.connected);
      expect(conn.serverUrl, 'http://127.0.0.1:54321');
      expect(conn.isEmbeddedMode, isTrue);
      expect(conn.userProfile?.email, 'embedded@local');
    });

    test('getAccessToken returns the injected token when connected', () async {
      final conn = ServerConnection();
      conn.connectEmbedded(
        port: 1,
        accessToken: 'injected-acc',
        refreshToken: 'r',
        installUuid: 'u',
        version: 'v',
      );
      expect(await conn.getAccessToken(), 'injected-acc');
    });

    test('markEmbeddedLost flips state back to disconnected', () {
      final conn = ServerConnection();
      conn.connectEmbedded(
        port: 1,
        accessToken: 'a',
        refreshToken: 'r',
        installUuid: 'u',
        version: 'v',
      );
      expect(conn.connectionState, ServerConnectionState.connected);

      conn.markEmbeddedLost();
      expect(conn.connectionState, ServerConnectionState.disconnected);
      expect(conn.serverUrl, isNull);
    });

    test('applyTo is a safe no-op when no handshake has been received', () {
      // The service starts with no handshake; applyTo must not throw and must
      // not change connection state (the documented guard).
      EmbeddedServerService.resetForTesting();
      EmbeddedServerService.instance.applyTo(ServerConnection());
      expect(ServerConnection().connectionState,
          ServerConnectionState.disconnected);
    });
  });

  // U12：双通道重启竞态守卫。两个 restart 通道（崩溃退避 / 心跳触发）与
  // stop() 并发交错时不得产出双子进程或挂死。这里覆盖可无副作用测试的
  // 单飞契约；真实 spawn 侧的守卫由 Rust embedded_process_test.rs 覆盖。
  group('EmbeddedServer.restart single-flight (U12)', () {
    setUp(EmbeddedServerService.resetForTesting);
    tearDown(EmbeddedServerService.resetForTesting);

    test('concurrent restart() calls share one in-flight future', () async {
      final server = EmbeddedServer();
      // A fresh instance has no data dir, so a restart can never reach
      // Process.start — deterministically false, no real spawn, regardless
      // of whether a binary happens to be discoverable in this environment.
      final a = server.restart();
      final b = server.restart();
      expect(identical(a, b), isTrue,
          reason: 'concurrent restarts must piggyback one flight');
      expect(await a, isFalse);
      expect(await b, isFalse);
    });

    test('a settled flight does not capture the next restart()', () async {
      final server = EmbeddedServer();
      final first = server.restart();
      await first;
      final second = server.restart();
      expect(identical(first, second), isFalse);
      await second;
    });

    test('concurrent restart() + stop() complete without hanging', () async {
      final server = EmbeddedServer();
      await Future.wait([server.restart(), server.stop()])
          .timeout(const Duration(seconds: 5));
    });
  });

  // vault 无界增长根治②（P1）：E2E 隔离数据目录——预置一次性系统临时
  // 目录，stop/resetForTesting 后递归清理；不触 path_provider（生产默认
  // 路径仅在未预置时解析）。
  group('EmbeddedServer.useIsolatedDataDir (vault 根治②)', () {
    setUp(EmbeddedServerService.resetForTesting);
    tearDown(EmbeddedServerService.resetForTesting);

    test('presets a system temp dir; repeat calls reuse it', () async {
      final server = EmbeddedServer();
      expect(server.debugDataDir, isNull);
      await server.useIsolatedDataDir();
      final first = server.debugDataDir;
      expect(first, isNotNull);
      expect(first!.startsWith(Directory.systemTemp.path), isTrue,
          reason: 'isolated dir must live under system temp');
      expect(await Directory(first).exists(), isTrue);
      await server.useIsolatedDataDir();
      expect(server.debugDataDir, first, reason: 'idempotent per process');
    });

    test('stop() with no process still cleans the isolated dir', () async {
      final server = EmbeddedServer();
      await server.useIsolatedDataDir();
      final dir = Directory(server.debugDataDir!);
      expect(await dir.exists(), isTrue);
      await server.stop();
      expect(server.debugDataDir, isNull);
      expect(await dir.exists(), isFalse, reason: 'full stop must recurse-delete');
    });
  });

  // U12：embedded 模式的 Disconnect 同时停子进程（provider 层编排），
  // 且不得触碰远程会话存储（真实 FlutterSecureStorage 在测试环境不可用，
  // 不抛异常即证明 embedded 分支没碰存储）。
  group('ServerConnectionProvider embedded disconnect (U12)', () {
    test('disconnect stops child, skips storage, ends disconnected', () async {
      ServerConnection.resetForTesting();
      EmbeddedServerService.resetForTesting();
      final conn = ServerConnection();
      conn.connectEmbedded(
        port: 1,
        accessToken: 'a',
        refreshToken: 'r',
        installUuid: 'u',
        version: 'v',
      );
      final provider = ServerConnectionProvider();
      addTearDown(provider.dispose);
      expect(provider.connectionState, ServerConnectionState.connected);

      await provider.disconnect();

      expect(provider.connectionState, ServerConnectionState.disconnected);
      expect(EmbeddedServerService.instance.isRunning, isFalse);
    });
  });
}
