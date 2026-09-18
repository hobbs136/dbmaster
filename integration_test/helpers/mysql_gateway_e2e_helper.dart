// T29 · MySQL 族 E2E 共享前置 —— embedded server 会话注入。
//
// MySQL 族网关壳（mysql_gateway_adapter）的执行通道是 T27 网关 API，硬依赖
// dbmaster server 会话（D6：embedded exe 随包）。E2E 前置流程：
//   1. `DBMASTER_SERVER_BIN` 或 exe 同目录定位 server 二进制并 spawn；
//   2. 读 stdout 握手行（port + token）→ `applyTo` 注入 ServerConnection 单例。
//
// 二进制不可得（未构建/未部署）时返回 false——各 E2E 组以可 grep 的
// MYSQL_E2E_SKIP 打印并整体跳过（FR-011 无假绿纪律）。

import 'dart:io';

import 'package:dbmaster/services/embedded_server_service.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 起 embedded server 并注入会话；已在跑则复用。成功 = ServerConnection
/// connected。
Future<bool> ensureEmbeddedServerForMysqlE2E() async {
  final embedded = EmbeddedServerService.instance;
  if (!embedded.isRunning) {
    // vault 根治②：E2E 隔离数据目录（一次性系统临时目录，与生产
    // <AppSupport>/embedded-server 分家；幂等，stop 后自动清理）。
    await embedded.useIsolatedDataDir();
    final result = await embedded.start();
    if (result != EmbeddedStartResult.started) {
      // ignore: avoid_print
      print(
        'MYSQL_E2E_SKIP: embedded start result=$result '
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
    print('MYSQL_E2E_SKIP: embedded handshake did not reach connected');
  }
  return connected;
}
