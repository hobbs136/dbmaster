// T18 · 大脚本执行卡死探针（用户实测反馈：402 表 + 外键脚本，执行中段卡死，
// 结果出现后恢复）。
//
// 复现口径：真实 MySQL（DBMASTER_MYSQL_* 提供）+ 402 张 CREATE TABLE + 外键
// ALTER（mysqldump 风格），经编辑器 → Run 全链路执行。
// 测量：①帧计时回调（>300ms 帧逐条留证）②pump 停顿（pump 阻塞 = UI
// 线程被卡，比帧回调更直接）③阶段墙钟。
//
// 运行：flutter test -d windows integration_test/t18_exec_freeze_probe_test.dart
// 输出：[T18-EXEC] ... / [T18-FRAME] ...

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart' hide QueryTab;
import 'package:dbmaster/organisms/editor/query_editor_widget.dart';
import 'package:dbmaster/organisms/results/results_widget.dart';
import 'package:dbmaster/organisms/pro/pro_purchase_ui.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/providers/layout_preferences_provider.dart';
import 'package:dbmaster/providers/locale_provider.dart';
import 'package:dbmaster/providers/theme_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';
import 'package:dbmaster/theme/app_theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

/// mysqldump 风格：先 402 张表（不带内联 FK），后跟外键 ALTER —— 与用户
/// 「402 张表及一些外键」 workload 对齐。
String _build402TableScript({int tableCount = 402, int fkCount = 60}) {
  final sb = StringBuffer();
  sb.writeln('-- T18 exec freeze probe');
  for (var t = 0; t < tableCount; t++) {
    sb.writeln('CREATE TABLE `t18_table_$t` (');
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
  // 外键：每 7 张表挂一条（约 60 条），引用前一表（前向引用全部成立）。
  for (var f = 1; f <= fkCount; f++) {
    final t = f * 7;
    sb.writeln(
      'ALTER TABLE `t18_table_$t` ADD CONSTRAINT `fk_t18_$f` FOREIGN KEY '
      '(`ref_id`) REFERENCES `t18_table_${t - 1}`(`id`);',
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
        debugPrint('[T18-FRAME] $line');
      }
    }
  });

  testWidgets('T18 探针：402 表 + 外键脚本执行全程帧停顿测量', (tester) async {
    if (!mysqlE2EGatewayReady) {
      return;
    }
    SharedPreferences.setMockInitialValues({});

    // ── 种子连接：建一次性测试库 ──
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
    var connected = false;
    try {
      connected = await seedAdapter.connect(seedConn);
      if (connected) {
        await seedAdapter.createDatabase(testDb);
      }
    } catch (_) {}
    debugPrint('[T18-EXEC] seed_connected=$connected');

    // ── AppProvider 连真实 MySQL ──
    AppProvider.devBypassGates = true;
    final provider = AppProvider();
    await provider.querySettings.load();
    final server = DbServer(
      id: 't18_exec_${testDb.hashCode}',
      name: 'T18 Exec Probe',
      type: DatabaseType.mysql,
      host: MySQLTestConfig.host,
      port: MySQLTestConfig.port,
      username: MySQLTestConfig.username,
      password: MySQLTestConfig.password,
      database: testDb,
    );
    await provider.connection.saveConnection(server);
    if (connected) {
      final ok = await provider.connectToServer(server);
      debugPrint('[T18-EXEC] provider_connected=$ok');
      await provider.refreshDatabases();
      await provider.tab.openQueryTab(
        connectionId: server.id,
        databaseName: testDb,
      );
      provider.setActiveTab(0);
    }
    assert(connected, '连不上测试 MySQL，无法复现');

    final themeProvider = ThemeProvider();
    final localeProvider = LocaleProvider();
    final layoutProvider = LayoutPreferencesProvider();
    await themeProvider.load();
    await localeProvider.load();
    await layoutProvider.load();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<LocaleProvider>.value(value: localeProvider),
          ChangeNotifierProvider<LayoutPreferencesProvider>.value(
            value: layoutProvider,
          ),
          Provider<ProPurchaseUi>.value(value: const NoOpProPurchaseUi()),
        ],
        child: MaterialApp(
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(themeProvider.accentColorValue),
          home: Scaffold(
            body: SizedBox(
              width: 1280,
              height: 800,
              child: Column(
                children: [
                  // 与真实 app（EditorResultsSplit）同构：编辑器在上、
                  // ResultsWidget 在下——此前探针只挂编辑器，结果面板从未
                  // 渲染，「无回归」是假阴性。
                  const Expanded(child: QueryEditorWidget(tabIndex: 0)),
                  SizedBox(
                    height: 320,
                    child: ResultsWidget(
                      showSubTabs: true,
                      onHistoryDoubleTapped: (_) {},
                      onHistoryTapped: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final script = _build402TableScript();
    debugPrint('[T18-EXEC] script_len=${script.length}');

    final state = tester.state<QueryEditorWidgetState>(
      find.byType(QueryEditorWidget),
    );
    final swLoad = Stopwatch()..start();
    state.controller.loadText(script);
    await tester.pump(const Duration(milliseconds: 500));
    debugPrint('[T18-EXEC] load+pump=${swLoad.elapsedMilliseconds}ms');

    // ── 点击 Run，进入执行观察窗：pump 停顿 = UI 线程被卡 ──
    final swRun = Stopwatch()..start();
    await tester.tap(find.byIcon(LucideIcons.play));
    await tester.pump(const Duration(milliseconds: 200));

    var maxStallMs = 0;
    var stallsOver1s = 0;
    final stallLog = <String>[];
    // 执行观察窗：最长 120s；每 200ms 一泵并记录墙钟。
    var done = false;
    var sawProgress = false;
    var lastRateLog = 0;
    // ignore: invalid_use_of_protected_member
    final ValueNotifier<String?> _execProgress = tester
        .state<QueryEditorWidgetState>(find.byType(QueryEditorWidget))
        .execProgressDebug;
    for (var i = 0; i < 900 && !done; i++) {
      final sw = Stopwatch()..start();
      await tester.pump(const Duration(milliseconds: 200));
      final ms = sw.elapsedMilliseconds;
      if (ms > maxStallMs) maxStallMs = ms;
      if (ms > 1000) {
        stallsOver1s++;
        stallLog.add('at=${swRun.elapsedMilliseconds}ms stall=${ms}ms');
      }
      // 执行门出现则放行（402 条 DDL 可能触发）。
      final gate = find.textContaining('继续执行');
      if (gate.evaluate().isNotEmpty) {
        debugPrint(
          '[T18-EXEC] gate_shown_at=${swRun.elapsedMilliseconds}ms → proceed',
        );
        await tester.tap(gate.first);
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (swRun.elapsedMilliseconds > 3000) {
        final resultsLen = provider.tab.activeTab?.executionResults.length ?? 0;
        if (!sawProgress && _execProgress.value != null) {
          sawProgress = true;
          debugPrint(
            '[T18-EXEC] progress_label_visible_at=${swRun.elapsedMilliseconds}ms',
          );
        }
        if (swRun.elapsedMilliseconds - lastRateLog > 5000) {
          lastRateLog = swRun.elapsedMilliseconds;
          debugPrint(
            '[T18-EXEC] rate_at=${swRun.elapsedMilliseconds}ms '
            'label=${_execProgress.value} results=$resultsLen',
          );
        }
        // 完成：执行态回落 + 进度到达总数 + 结果已写入。
        final label = _execProgress.value;
        if (!state.isExecutingDebug &&
            label != null &&
            label.endsWith('/462') &&
            resultsLen >= 462) {
          done = true;
          debugPrint('[T18-EXEC] completed_at=${swRun.elapsedMilliseconds}ms');
        }
      }
    }
    // 完成后再泵 3s 观察结果渲染帧（用户「出现执行结果后恢复」阶段）。
    final swRender = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    debugPrint('[T18-EXEC] render_window=${swRender.elapsedMilliseconds}ms');
    final runMs = swRun.elapsedMilliseconds;
    debugPrint('[T18-EXEC] total_wall=${runMs}ms done=$done');
    expect(done, isTrue, reason: '180s 内应完成 120 表脚本执行');
    debugPrint(
      '[T18-EXEC] max_pump_stall=${maxStallMs}ms stalls_over_1s=$stallsOver1s',
    );
    for (final l in stallLog.take(20)) {
      debugPrint('[T18-EXEC] stall: $l');
    }
    debugPrint('[T18-EXEC] slow_frames_over_300ms=${slowFrames.length}');

    // ── 清理 ──
    try {
      await seedAdapter.executeQuery('DROP DATABASE IF EXISTS `$testDb`');
      await seedAdapter.disconnect();
    } catch (_) {}
  });
}
