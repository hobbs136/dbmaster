// T18 · 全树执行探针：DbmasterApp（含侧栏/结果面板/状态栏）+ 真实 MySQL +
// 402 表脚本 → 真实 Run 按钮。此前编辑器版探针未挂 ResultsWidget/侧栏，
// 测不到用户报告的「卡在生成 402 个结果 tab」。
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:dbmaster/main.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/pro_module.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/screens/home_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

const bool kUseDdl = bool.fromEnvironment('FA_DDL', defaultValue: true);

String _script({int tableCount = 402, int fkCount = 60}) {
  if (!kUseDdl) {
    // 对照组：无 DDL → 不触发侧栏树刷新。
    return List.generate(
      402,
      (i) => 'SELECT ' + i.toString() + ' AS n',
    ).join(';');
  }
  final sb = StringBuffer();
  for (var t = 0; t < tableCount; t++) {
    sb.writeln('CREATE TABLE `fa_$t` (');
    sb.writeln('  `id` bigint NOT NULL AUTO_INCREMENT,');
    sb.writeln('  `ref_id` bigint DEFAULT NULL,');
    sb.writeln('  `name` varchar(64) NOT NULL,');
    sb.writeln('  `payload` text,');
    sb.writeln('  `create_time` datetime DEFAULT CURRENT_TIMESTAMP,');
    sb.writeln('  PRIMARY KEY (`id`),');
    sb.writeln('  KEY `idx_ref_$t` (`ref_id`)');
    sb.writeln(') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;');
    sb.writeln();
  }
  for (var f = 1; f <= fkCount; f++) {
    final t = f * 7;
    sb.writeln(
      'ALTER TABLE `fa_$t` ADD CONSTRAINT `fa_fk_$f` FOREIGN KEY '
      '(`ref_id`) REFERENCES `fa_${t - 1}`(`id`);',
    );
  }
  return sb.toString();
}

void main() {

  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  // 二进制不可得时全组以可 grep 的 MYSQL_E2E_SKIP 跳过（无假绿）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（开源剥离默认凭据，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final slowFrames = <String>[];
  WidgetsBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      if (t.totalSpan.inMilliseconds > 300) {
        final line =
            'build=${t.buildDuration.inMilliseconds}ms '
            'raster=${t.rasterDuration.inMilliseconds}ms '
            'total=${t.totalSpan.inMilliseconds}ms';
        slowFrames.add(line);
        debugPrint('[FA-FRAME] $line');
      }
    }
  });

  testWidgets('全树 402 表执行探针', (tester) async {
    if (!mysqlE2EGatewayReady) {
      return;
    }
    try {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1.0;
    } catch (_) {}

    // —— 1. 种子连接：建测试库 ——
    final seedAdapter = MySQLAdapter();
    final testDb = MySQLTestConfig.generateTestDatabaseName();
    final seedConn = DatabaseConnection(
      id: 'seed_${testDb.hashCode}',
      name: 'Seed',
      type: DatabaseType.mysql,
      host: MySQLTestConfig.host,
      port: MySQLTestConfig.port,
      username: MySQLTestConfig.username,
      password: MySQLTestConfig.password,
      database: '',
    );
    var seedOk = false;
    try {
      seedOk = await seedAdapter.connect(seedConn);
      if (seedOk) await seedAdapter.createDatabase(testDb);
    } catch (_) {}
    debugPrint('[FA] seed=$seedOk db=$testDb');
    assert(seedOk, '种子连接失败');

    // —— 2. 全 app ——
    AppProvider.devBypassGates = true;
    await tester.pumpWidget(DbmasterApp(proModule: FreeProModule()));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final home = tester.element(find.byType(HomeScreen));
    final provider = home.read<AppProvider>();

    final server = DbServer(
      id: 'fa_exec_${testDb.hashCode}',
      name: 'FA Exec',
      type: DatabaseType.mysql,
      host: MySQLTestConfig.host,
      port: MySQLTestConfig.port,
      username: MySQLTestConfig.username,
      password: MySQLTestConfig.password,
      database: testDb,
    );
    await provider.connection.saveConnection(server);
    expect(await provider.connectToServer(server), isTrue);
    await provider.refreshDatabases();
    await provider.tab.openQueryTab(
      connectionId: server.id,
      databaseName: testDb,
    );
    provider.setActiveTab(0);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    // —— 3. 装载脚本 + 真实 Run ——
    final state = tester.state<QueryEditorWidgetState>(
      find.byType(QueryEditorWidget),
    );
    final sql = _script();
    debugPrint('[FA] script_len=${sql.length}');
    state.controller.loadText(sql);
    await tester.pump(const Duration(milliseconds: 500));

    final sw = Stopwatch()..start();
    await tester.tap(find.byIcon(LucideIcons.play));
    await tester.pump(const Duration(milliseconds: 200));

    var done = false;
    var lastRate = 0;
    for (var i = 0; i < 1500 && !done; i++) {
      final swP = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 200));
      final ms = swP.elapsedMilliseconds;
      if (ms > 800) {
        debugPrint(
          '[FA] pump_stall at=${sw.elapsedMilliseconds}ms stall=${ms}ms',
        );
      }
      // 执行门放行
      final gate = find.textContaining('继续执行');
      if (gate.evaluate().isNotEmpty) {
        debugPrint('[FA] gate at=${sw.elapsedMilliseconds}ms');
        await tester.tap(gate.first);
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (sw.elapsedMilliseconds - lastRate > 5000) {
        lastRate = sw.elapsedMilliseconds;
        debugPrint(
          '[FA] t=${sw.elapsedMilliseconds}ms '
          'label=${state.execProgressDebug.value} '
          'executing=${state.isExecutingDebug}',
        );
      }
      if (!state.isExecutingDebug && sw.elapsedMilliseconds > 3000) {
        done = true;
        debugPrint('[FA] completed at=${sw.elapsedMilliseconds}ms');
      }
    }
    // 完成后再观察 5s（收尾渲染：结果面板/侧栏树刷新）
    for (var i = 0; i < 25; i++) {
      final swP = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 200));
      final ms = swP.elapsedMilliseconds;
      if (ms > 800) {
        debugPrint(
          '[FA] post_done_stall at=${sw.elapsedMilliseconds}ms stall=${ms}ms',
        );
      }
    }
    debugPrint(
      '[FA] total=${sw.elapsedMilliseconds}ms done=$done '
      'slow_frames=${slowFrames.length}',
    );

    // —— 清理 ——
    try {
      await seedAdapter.executeQuery('DROP DATABASE IF EXISTS `$testDb`');
      await seedAdapter.disconnect();
    } catch (_) {}
  });
}
