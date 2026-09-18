// reports-M1（#29）· 慢查询 embedded E2E 共享前置 —— embedded server 会话注入。
//
// 与 td_gateway_e2e_helper 同构（embedded spawn + 握手 + applyTo），独立成
// helper 避免跨功能命名混淆。二进制不可得（未构建/未部署）时返回 false——
// 测试组以可 grep 的 QS_E2E_SKIP 打印并整体跳过（无假绿纪律）。

import 'dart:io';

import 'package:dbmaster/services/embedded_server_service.dart';
import 'package:dbmaster/services/server_connection.dart';

/// 起 embedded server 并注入会话；已在跑则复用。成功 = ServerConnection
/// connected。
Future<bool> ensureEmbeddedServerForQueryStatsE2E() async {
  final embedded = EmbeddedServerService.instance;
  if (!embedded.isRunning) {
    // vault 根治②：E2E 隔离数据目录（一次性系统临时目录，与生产
    // <AppSupport>/embedded-server 分家；幂等，stop 后自动清理——生产
    // 数据目录零残留由该隔离保证）。
    await embedded.useIsolatedDataDir();
    final result = await embedded.start();
    if (result != EmbeddedStartResult.started) {
      // ignore: avoid_print
      print(
        'QS_E2E_SKIP: embedded start result=$result '
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
    print('QS_E2E_SKIP: embedded handshake did not reach connected');
  }
  return connected;
}
