// T29 TDengine 批次 · TDengine E2E 共享前置 —— embedded server 会话注入。
//
// TDengine 网关壳（tdengine_gateway_adapter）的执行通道是 kind:"tdengine"
// 的网关 API（taosAdapter REST server 腿），硬依赖 dbmaster server 会话
//（D6：embedded exe 随包）。前置流程与 mongo/redis 等 helper 同构：
//   1. `DBMASTER_SERVER_BIN` 或 exe 同目录定位 server 二进制并 spawn；
//   2. 读 stdout 握手行（port + token）→ `applyTo` 注入 ServerConnection。
//
// 二进制不可得（未构建/未部署）时返回 false——各 E2E 组以可 grep 的
// TD_E2E_SKIP 打印并整体跳过（无假绿纪律）。

import 'dart:io';

import 'package:dbmaster/services/embedded_server_service.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 起 embedded server 并注入会话；已在跑则复用。成功 = ServerConnection
/// connected。
Future<bool> ensureEmbeddedServerForTdE2E() async {
  final embedded = EmbeddedServerService.instance;
  if (!embedded.isRunning) {
    // vault 根治②：E2E 隔离数据目录（一次性系统临时目录，与生产
    // <AppSupport>/embedded-server 分家；幂等，stop 后自动清理）。
    await embedded.useIsolatedDataDir();
    final result = await embedded.start();
    if (result != EmbeddedStartResult.started) {
      // ignore: avoid_print
      print(
        'TD_E2E_SKIP: embedded start result=$result '
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
    print('TD_E2E_SKIP: embedded handshake did not reach connected');
  }
  return connected;
}
