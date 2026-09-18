// T29 非 SQL 批次（B4）· Redis E2E 共享前置 —— embedded server 会话注入。
//
// Redis 网关壳（redis_gateway_adapter）的执行通道是 kind:"redis" 的
// 命令/pipeline 网关 API + 订阅转发 SSE（ADR-0006），硬依赖 dbmaster
// server 会话（D6：embedded exe 随包）。与 pg/mongo helper 同构。
//
// 二进制不可得（未构建/未部署）时返回 false——各 E2E 组以可 grep 的
// REDIS_E2E_SKIP 打印并整体跳过（无假绿纪律）。

import 'dart:io';

import 'package:dbmaster/services/embedded_server_service.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 起 embedded server 并注入会话；已在跑则复用。成功 = ServerConnection
/// connected。
Future<bool> ensureEmbeddedServerForRedisE2E() async {
  final embedded = EmbeddedServerService.instance;
  if (!embedded.isRunning) {
    // vault 根治②：E2E 隔离数据目录（一次性系统临时目录，与生产
    // <AppSupport>/embedded-server 分家；幂等，stop 后自动清理）。
    await embedded.useIsolatedDataDir();
    final result = await embedded.start();
    if (result != EmbeddedStartResult.started) {
      // ignore: avoid_print
      print(
        'REDIS_E2E_SKIP: embedded start result=$result '
        '(resolvedExecutable=${Platform.resolvedExecutable}; '
        'DBMASTER_SERVER_BIN=${Platform.environment['DBMASTER_SERVER_BIN']})',
      );
      return false;
    }
  }
  embedded.applyTo(ServerConnection());
  final connected =
      ServerConnection().connectionState == ServerConnectionState.connected;
  if (!connected) {
    // ignore: avoid_print
    print('REDIS_E2E_SKIP: embedded handshake did not reach connected');
  }
  return connected;
}
