// ============================================================================
// DBT-T18 · MySQL 事件设计器 E2E（W-15 真库验证）
//
// 覆盖（任务书 T18 真库验证节，引擎 = WSL MySQL 8.0，连接信息唯一来源
// test_db_local_wsl.txt，凭据经 DBMASTER_MYSQL_* dart-define 注入）：
//   ① 自建库 → 新建 EVERY 1 MINUTE 事件（DO 无害 INSERT 自建表）→
//      information_schema.EVENTS 断言出现；
//   ② ALTER 改状态 DISABLE → 断言 STATUS 变化；
//   ③ SHOW CREATE EVENT 反解析回填断言（View DDL + 编辑表单回填）；
//   ④ DROP（typed confirmation）→ 断言消失；
//   ⑤ 取消路径零变化（确认门取消 → 库内事件不变）；
//   ⑥ readonly 连接 = 三动作服务层拦截（入口禁用 + 拦截断言）；
//   ⑦ event_scheduler 状态核实（OFF 亦兼容——只影响执行不影响 DDL）。
//
// 前置：DBMASTER_SERVER_BIN 指向 dbmaster-server.exe（embedded 网关，
// 无二进制时以可 grep 的 MYSQL_E2E_SKIP 整组跳过，FR-011 无假绿纪律）。
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dbmaster/l10n/app_localizations.dart';
import 'package:dbmaster/models/database_models.dart';
import 'package:dbmaster/molecules/destructive_confirm_dialog.dart';
import 'package:dbmaster/organisms/dialogs/mysql_events_dialog.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mysql_adapter.dart';
import 'package:dbmaster/services/database_abstract.dart';

import 'config/mysql_test_config.dart';
import 'helpers/mysql_gateway_e2e_helper.dart';

void main() {
  // T29：MySQL 族网关壳硬依赖 dbmaster server 会话（embedded 前置，D6）。
  bool mysqlE2EGatewayReady = false;
  setUpAll(() async {
    mysqlE2EGatewayReady = await ensureEmbeddedServerForMysqlE2E();
    if (mysqlE2EGatewayReady && !MySQLTestConfig.available) {
      // ignore: avoid_print
      print('MYSQL_E2E_SKIP: DBMASTER_MYSQL_* 未通过 --dart-define 提供'
          '（凭据不入库，缺参即跳过）');
      mysqlE2EGatewayReady = false;
    }
  });

  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('DBT-T18 MySQL Events Designer E2E', () {
    late AppProvider provider;
    late MySQLAdapter adapter;
    late String testDbName;
    late DbServer server;
    late DbServer roServer;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      testDbName = MySQLTestConfig.generateTestDatabaseName();

      // 种子：专用 adapter 建自删库 + 目标表（金标准 mysql_sidebar_menu 同法）。
      adapter = MySQLAdapter();
      final dbConn = DatabaseConnection(
        id: 'seed_${testDbName.hashCode}',
        name: 'Seed Connection',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
      );
      await adapter.connect(dbConn);
      await adapter.createDatabase(testDbName);
      await adapter.useDatabase(testDbName);
      await adapter.executeQuery(
        'CREATE TABLE `ev_seed` (id INT PRIMARY KEY, created_at TIMESTAMP '
        'DEFAULT CURRENT_TIMESTAMP)',
      );

      provider = AppProvider();
      AppProvider.devBypassGates = true;
      server = DbServer(
        id: 'dbt_t18_e2e_${testDbName.hashCode}',
        name: 'DBT T18 Events E2E',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: testDbName,
      );
      await provider.connection.saveConnection(server);
      final connected = await provider.connectToServer(server);
      expect(connected, isTrue, reason: '真库连接失败');

      roServer = DbServer(
        id: 'dbt_t18_ro_${testDbName.hashCode}',
        name: 'DBT T18 Events RO',
        type: DatabaseType.mysql,
        host: MySQLTestConfig.host,
        port: MySQLTestConfig.port,
        username: MySQLTestConfig.username,
        password: MySQLTestConfig.password,
        database: testDbName,
        readOnly: true,
      );
    });

    tearDown(() async {
      try {
        await adapter.executeQuery('DROP DATABASE IF EXISTS `$testDbName`');
      } catch (_) {}
      try {
        await adapter.disconnect();
      } catch (_) {}
      try {
        await provider.disconnectConnection(connectionId: server.id);
      } catch (_) {}
      try {
        await provider.disconnectConnection(connectionId: roServer.id);
      } catch (_) {}
      try {
        provider.dispose();
      } catch (_) {}
    });

    Future<void> pumpDialog(WidgetTester tester, DbServer sv) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppProvider>.value(
          value: provider,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => MysqlEventsDialog.show(
                    context,
                    connectionId: sv.id,
                    databaseName: testDbName,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pump();
    }

    /// 轮询等待条件成立（runAsync 放行真实 I/O；对话框内部加载在真实时钟
    /// 下完成——loader 在 dialog initState 里走 provider，同 T3 e2e 口径）。
    Future<bool> waitUntil(
      WidgetTester tester,
      bool Function() condition, {
      int timeoutMs = 30000,
    }) async {
      final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
      while (DateTime.now().isBefore(deadline)) {
        if (condition()) return true;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      return condition();
    }

    /// 库内事件清单（种子 adapter 只读直查，断言与 UI 无关）。
    Future<Map<String, String>> fetchEventStatuses() async {
      final result = await adapter.executeQuery(
        'SELECT EVENT_NAME, STATUS FROM information_schema.EVENTS '
        "WHERE EVENT_SCHEMA = '$testDbName'",
      );
      return {
        for (final row in result.rows)
          row['EVENT_NAME']?.toString() ?? '':
              row['STATUS']?.toString() ?? '',
      };
    }

    testWidgets('DBT-T18-CREATE：新建 EVERY 1 MINUTE 事件 → IS 断言出现', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) return;
      await pumpDialog(tester, server);

      expect(
        await waitUntil(tester, () => tester.any(find.text('No events'))),
        isTrue,
        reason: '自建库初始无事件 → 空态',
      );
      // event_scheduler 兼容断言：OFF 时提示行可见（不影响 DDL 路径）。
      final schedResult = await tester.runAsync(
        () => adapter.executeQuery('SELECT @@event_scheduler AS v'),
      );
      final scheduler = (schedResult?.rows.isNotEmpty ?? false)
          // runAsync 回调永不以 null 完成；schedResult 收窄后 rows 非空可解。
          ? schedResult!.rows.first.values.first?.toString() ?? ''
          : '';
      if (scheduler.toUpperCase() != 'ON') {
        expect(find.textContaining('event scheduler is OFF'), findsOneWidget,
            reason: '调度器 OFF（$scheduler）→ 提示行展示');
      }

      // 新建：EVERY 1 MINUTE，DO 无害 INSERT 自建表
      await tester.tap(find.text('New Event'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('mysql_event_field_name')),
        'ev_t18_seed',
      );
      await tester.enterText(
        find.byKey(const Key('mysql_event_field_every_value')),
        '1',
      );
      await tester.enterText(
        find.byKey(const Key('mysql_event_field_do_body')),
        'INSERT INTO `ev_seed` (id) VALUES (1)',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('mysql_event_form_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // DDL 预览门：预览 = 生成函数输出（逐字一致锚点）
      final expectedCreate =
          'CREATE EVENT `ev_t18_seed`\n'
          '  ON SCHEDULE EVERY 1 MINUTE\n'
          '  ON COMPLETION NOT PRESERVE\n'
          '  ENABLE\n'
          '  DO\n'
          'INSERT INTO `ev_seed` (id) VALUES (1)';
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      expect(find.text(expectedCreate), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm').first);
      await tester.pump();
      expect(
        await waitUntil(tester, () => tester.any(find.text('ev_t18_seed'))),
        isTrue,
        reason: '执行成功后列表刷新出现新事件',
      );

      // 库内断言（与 UI 无关的直查）
      final statuses = await tester.runAsync(fetchEventStatuses) ??
          const <String, String>{};
      expect(statuses['ev_t18_seed'], 'ENABLED');
    });

    testWidgets('DBT-T18-CANCEL：预览门取消 = 库内零变化', (tester) async {
      if (!mysqlE2EGatewayReady) return;
      await adapter.executeQuery(
        'CREATE EVENT `ev_cancel_probe` ON SCHEDULE EVERY 1 HOUR DO SELECT 1',
      );
      await pumpDialog(tester, server);
      expect(
        await waitUntil(tester, () => tester.any(find.text('ev_cancel_probe'))),
        isTrue,
      );

      // DROP typed 门：输入正确事件名后取消 = 零执行零变化
      await tester.tap(
        find.widgetWithIcon(IconButton, LucideIcons.trash2).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'ev_cancel_probe');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(TextButton, 'Cancel').last,
      );
      await tester.pumpAndSettle();
      expect(find.byType(DestructiveConfirmDialog), findsNothing,
          reason: '取消后门关闭');

      final statuses = await tester.runAsync(fetchEventStatuses) ??
          const <String, String>{};
      expect(statuses.containsKey('ev_cancel_probe'), isTrue,
          reason: '取消 = 库内零变化');
    });

    testWidgets('DBT-T18-ALTER-POPULATE-DROP：改状态/回填/删除全链路', (
      tester,
    ) async {
      if (!mysqlE2EGatewayReady) return;
      await adapter.executeQuery(
        "CREATE EVENT `ev_lifecycle` ON SCHEDULE EVERY 1 MINUTE "
        "COMMENT 'lifecycle probe' DO INSERT INTO `ev_seed` (id) VALUES (9)",
      );
      await pumpDialog(tester, server);
      expect(
        await waitUntil(tester, () => tester.any(find.text('ev_lifecycle'))),
        isTrue,
      );

      // ① View DDL：SHOW CREATE EVENT 真数据
      await tester.tap(
        find.widgetWithIcon(IconButton, LucideIcons.eye).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await waitUntil(
          tester,
          () => tester.any(find.textContaining('CREATE DEFINER=')),
        ),
        isTrue,
        reason: 'SHOW CREATE EVENT 返回真实 DDL',
      );
      // 两层 dialog 各有 Close（顶层 DDL 查看 + 底层列表）→ 取最上层（.last）。
      await tester.tap(find.widgetWithText(TextButton, 'Close').last);
      await tester.pumpAndSettle();

      // ② ALTER：编辑表单回填（反解析）→ 改状态 DISABLE → 确认
      await tester.tap(
        find.widgetWithIcon(IconButton, LucideIcons.pencil).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        await waitUntil(
          tester,
          () => (tester.widget<TextField>(
                    find.byKey(const Key('mysql_event_field_name')),
                  ).controller?.text ??
                  '') ==
              'ev_lifecycle',
        ),
        isTrue,
        reason: 'SHOW CREATE EVENT 反解析回填事件名',
      );
      // 调度与 DO body 回填
      expect(
        tester.widget<TextField>(
          find.byKey(const Key('mysql_event_field_every_value')),
        ).controller?.text ?? '',
        '1',
      );
      expect(
        (tester.widget<TextField>(
          find.byKey(const Key('mysql_event_field_do_body')),
        ).controller?.text ?? ''),
        contains('ev_seed'),
      );
      // 状态 DISABLE（回填态 ENABLE → 改 DISABLE）
      await tester.tap(find.byType(DropdownButton<String>).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('DISABLE').last);
      await tester.pump();
      await tester.tap(find.byKey(const Key('mysql_event_form_save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DestructiveConfirmDialog), findsOneWidget);
      expect(find.textContaining('ALTER EVENT `ev_lifecycle`'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm').first);
      await tester.pump();
      expect(
        await waitUntil(tester, () => tester.any(find.text('DISABLED'))),
        isTrue,
        reason: 'ALTER 后列表 STATUS 列变 DISABLED',
      );

      // 库内直查断言 STATUS 变化
      var statuses = await tester.runAsync(fetchEventStatuses) ??
          const <String, String>{};
      expect(statuses['ev_lifecycle'], 'DISABLED');

      // ③ DROP typed confirmation → 断言消失
      await tester.tap(
        find.widgetWithIcon(IconButton, LucideIcons.trash2).first,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'ev_lifecycle');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm').first);
      await tester.pump();
      expect(
        await waitUntil(
          tester,
          () => !tester.any(find.text('ev_lifecycle')),
        ),
        isTrue,
        reason: 'DROP 后列表刷新，事件消失',
      );

      statuses = await tester.runAsync(fetchEventStatuses) ??
          const <String, String>{};
      expect(statuses.containsKey('ev_lifecycle'), isFalse,
          reason: '库内直查确认消失');
    });

    testWidgets('DBT-T18-READONLY：三动作服务层拦截 + 入口禁用', (tester) async {
      if (!mysqlE2EGatewayReady) return;
      await adapter.executeQuery(
        'CREATE EVENT `ev_ro_probe` ON SCHEDULE EVERY 1 DAY DO SELECT 1',
      );
      await provider.connection.saveConnection(roServer);
      final connected = await provider.connectToServer(roServer);
      expect(connected, isTrue);

      await pumpDialog(tester, roServer);
      expect(
        await waitUntil(tester, () => tester.any(find.text('ev_ro_probe'))),
        isTrue,
      );

      // 入口禁用：New 按钮禁用 + 行内 Edit/Drop 禁用 + 提示行
      final newBtn = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'New Event'),
      );
      expect(newBtn.onPressed, isNull);
      expect(find.textContaining('read-only mode'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, LucideIcons.pencil).first,
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, LucideIcons.trash2).first,
            )
            .onPressed,
        isNull,
      );

      // 拦截断言：三动作 DDL 经服务层在只读连接上被拒（readonly 闸门）
      for (final ddl in [
        'CREATE EVENT `ev_x` ON SCHEDULE EVERY 1 DAY DO SELECT 1',
        'ALTER EVENT `ev_ro_probe` ENABLE',
        'DROP EVENT `ev_ro_probe`',
      ]) {
        Object? caught;
        await tester.runAsync(() async {
          try {
            await provider.dbService.executeQuery(
              ddl,
              connectionId: roServer.id,
              database: testDbName,
            );
          } catch (e) {
            caught = e;
          }
        });
        expect(caught, isNotNull, reason: '只读连接必须拒绝: $ddl');
        expect(caught.toString(), contains('只读'));
      }

      // 库内零变化（种子 adapter 直查）
      final statuses = await tester.runAsync(fetchEventStatuses) ??
          const <String, String>{};
      expect(statuses.containsKey('ev_ro_probe'), isTrue);
    });
  });
}
