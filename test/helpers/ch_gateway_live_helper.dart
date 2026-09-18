// T29 第三批 · CH 网关 live 测试共享前置 —— embedded server 会话注入。
//
// CH 网关壳（clickhouse_adapter）的执行通道是 T27 网关 API，硬依赖
// dbmaster server 会话（D6：embedded exe 随包）。与 integration_test 的
// ch_gateway_e2e_helper 同构，但面向 `flutter test` VM 环境：
// EmbeddedServerService.start() 依赖 path_provider（测试 VM 无插件通道，
// 必失败），故这里用 Process.start 直启 + EmbeddedHandshake.parse 读握手行，
// 注入 ServerConnection 单例。
//
// 二进制定位：`DBMASTER_SERVER_BIN` 环境变量优先，其次
// `Platform.resolvedExecutable` 同目录。不可得时返回 false——调用方以可
// grep 的 CH_LIVE_SKIP 打印并跳过（无假绿纪律；恢复条件：构建 server
// （cargo build）并设 DBMASTER_SERVER_BIN）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbmaster/services/embedded_server_service.dart';
import 'package:dbmaster/services/server_connection.dart';

Process? _chLiveServer;

/// 起 embedded server 并注入 ServerConnection 会话；已在 connected 态则
/// 直接复用。成功 = true；二进制不可得/握手失败 = false。
Future<bool> ensureEmbeddedServerForChLive() async {
  final conn = ServerConnection();
  if (conn.connectionState == ServerConnectionState.connected) return true;

  final binaryPath =
      Platform.environment['DBMASTER_SERVER_BIN'] ?? _besideExe();
  if (binaryPath == null) return false;

  final dataDir = await Directory.systemTemp.createTemp('ch_live_gw_');
  final proc = await Process.start(
    binaryPath,
    ['--embedded', '--data-dir', dataDir.path],
  );
  _chLiveServer = proc;

  // stderr 必须立即持续排空，否则子进程启动日志写满管道缓冲后阻塞，
  // handshake 永远等不到（实锤：迁移日志在握手行前输出）。
  unawaited(proc.stderr.drain<void>());

  final handshake = await proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .map(EmbeddedHandshake.parse)
      .firstWhere((hs) => hs != null, orElse: () => null)
      .timeout(const Duration(seconds: 15), onTimeout: () => null);

  if (handshake == null) {
    proc.kill(ProcessSignal.sigkill);
    return false;
  }

  conn.connectEmbedded(
    port: handshake.port,
    accessToken: handshake.accessToken,
    refreshToken: handshake.refreshToken,
    installUuid: handshake.installUuid,
    version: handshake.version,
  );
  return conn.connectionState == ServerConnectionState.connected;
}

/// 测试结束停掉 embedded server（最后一个用例的 tearDownAll 调用）。
Future<void> stopEmbeddedServerForChLive() async {
  final proc = _chLiveServer;
  _chLiveServer = null;
  if (proc != null) {
    proc.kill(ProcessSignal.sigkill);
  }
  ServerConnection.resetForTesting();
}

/// exe 同目录定位（发布形态：server 二进制随包）。
String? _besideExe() {
  final name = Platform.isWindows ? 'dbmaster-server.exe' : 'dbmaster-server';
  final beside = File(
      '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$name');
  return beside.existsSync() ? beside.path : null;
}
