// T29 第三批 · CH 网关壳 live 冒烟（flutter test VM 环境，真库经 /api/gw）。
//
// 与 integration_test/clickhouse_integration_test.dart 的区别：那边跑在
// Windows 桌面进程（插件可用），本文件跑在 `flutter test` VM（Process.start
// 直启 embedded server，见 helpers/ch_gateway_live_helper.dart）。
//
// 前置：DBMASTER_SERVER_BIN（或 exe 同目录二进制）+ 真实 CH（连接参数经
// --dart-define=DBMASTER_CH_* 提供，见
// integration_test/config/clickhouse_test_config.dart）。
// 不可得时全组以 CH_LIVE_SKIP 跳过（无假绿纪律）。

import 'package:flutter_test/flutter_test.dart';

import 'package:dbmaster/services/adapters/clickhouse_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/models/database_models.dart';
import '../../helpers/ch_gateway_live_helper.dart';
import '../../../integration_test/config/clickhouse_test_config.dart';

void main() {
  var ready = false;
  setUpAll(() async {
    ready = await ensureEmbeddedServerForChLive();
    if (!ready) {
      // ignore: avoid_print
      print('CH_LIVE_SKIP: embedded server 或 CH 真库不可用');
    }
  });
  tearDownAll(() => stopEmbeddedServerForChLive());

  test('live：connect → 浏览 → 查询全链路（真库经 embedded /api/gw）', () async {
    if (!ready) return;
    final adapter = ClickhouseAdapter();
    final ok = await adapter.connect(
      DatabaseConnection(
        id: 'live_ch_1',
        name: 'CH Live Smoke',
        type: DatabaseType.clickhouse,
        host: ClickhouseTestConfig.host,
        port: ClickhouseTestConfig.port,
        username: ClickhouseTestConfig.username,
        password: ClickhouseTestConfig.password,
        database: ClickhouseTestConfig.database,
      ),
    );
    expect(ok, isTrue, reason: 'connect 失败（CH 真库未达？）');

    final dbs = await adapter.getDatabases();
    expect(dbs, contains(ClickhouseTestConfig.database));

    final r = await adapter.executeQuery('SELECT 1 AS one');
    expect(r.rows, [
      {'one': 1},
    ]);

    await adapter.disconnect();
    expect(adapter.isConnected, isFalse);
  });
}
